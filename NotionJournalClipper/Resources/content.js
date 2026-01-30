function sleep(ms) {
  return new Promise(r => setTimeout(r, ms))
}

function cleanText(s) {
  return (s || "")
    .replace(/\u00a0/g, " ")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
}

function roleLabel(role) {
  if (role === "assistant") return "Assistant"
  if (role === "user") return "User"
  return "Unknown"
}

function buildChatTxt(items) {
  return items.map(it => `${roleLabel(it.role)}:\n${it.text}`).join("\n\n").trim()
}

function getAllTurnBlocks() {
  const main = document.querySelector("main")
  if (!main) return []
  return Array.from(main.querySelectorAll('article[data-testid^="conversation-turn"], div[data-testid^="conversation-turn"]'))
}

function getBlockTop(el) {
  const r = el.getBoundingClientRect()
  return r.top + window.scrollY
}

function extractFromBlock(block) {
  const nodes = Array.from(block.querySelectorAll('[data-message-author-role]'))
  const out = []
  for (const n of nodes) {
    const role = (n.getAttribute("data-message-author-role") || "").toLowerCase()
    if (role !== "assistant" && role !== "user") continue
    const root = n.querySelector(".markdown") || n
    const text = cleanText(root.innerText || "")
    if (!text) continue
    out.push({ role, text })
  }
  return out
}

async function extractChatDom() {
  const blocks = getAllTurnBlocks()
  if (blocks.length === 0) {
    return { ok: false, error: "no conversation blocks found" }
  }

  const ordered = blocks
    .map(b => ({ el: b, top: getBlockTop(b) }))
    .sort((a, b) => a.top - b.top)

  const items = []
  for (let i = 0; i < ordered.length; i++) {
    const block = ordered[i].el
    block.scrollIntoView({ block: "center", behavior: "auto" })
    await sleep(60)
    const extracted = extractFromBlock(block)
    for (const it of extracted) items.push(it)
  }

  const chat_txt = buildChatTxt(items)

  return {
    ok: chat_txt.length > 0,
    method: "deterministic_block_walk",
    url: location.href,
    title: document.title || "",
    dom_items: items,
    chat_txt,
    debug: {
      total_blocks: ordered.length,
      total_messages: items.length
    }
  }
}

function extractHtmlSnapshot() {
  return {
    ok: true,
    method: "html_snapshot",
    url: location.href,
    title: document.title || "",
    html_txt: document.body ? document.body.innerText : ""
  }
}

function detectPlatform() {
  const host = location.hostname.toLowerCase()
  if (host.includes("kimi")) return "kimi"
  if (host.includes("deepseek")) return "deepseek"
  if (host.includes("openai") || host.includes("chatgpt")) return "chatgpt"
  if (host.includes("claude")) return "claude"
  if (host.includes("gemini")) return "gemini"
  return "generic"
}

function isScrollable(el) {
  if (!el) return false
  const style = window.getComputedStyle(el)
  const oy = style.overflowY
  if (!(oy === "auto" || oy === "scroll")) return false
  return el.scrollHeight > el.clientHeight + 120
}

function pickBestScrollContainer() {
  const root = document.scrollingElement || document.documentElement
  const vpH = window.innerHeight || 1
  const vpW = window.innerWidth || 1

  const candidates = Array.from(document.querySelectorAll("main, section, div, article"))
    .filter(el => el && el.isConnected)
    .filter(el => el !== document.body && el !== document.documentElement)
    .filter(el => el.getClientRects().length > 0)
    .filter(el => isScrollable(el))
    .map(el => {
      const r = el.getBoundingClientRect()
      const area = Math.max(0, r.width) * Math.max(0, r.height)
      const centerDist =
        Math.abs((r.left + r.width / 2) - vpW / 2) +
        Math.abs((r.top + r.height / 2) - vpH / 2)
      const score =
        area +
        Math.min(8000, el.scrollHeight - el.clientHeight) * 2 -
        centerDist * 2

      return { el, score, r }
    })
    .sort((a, b) => b.score - a.score)

  if (candidates.length > 0) return candidates[0].el
  return root
}

function scrollMetrics(el) {
  if (!el) return { top: 0, height: 0, client: 0 }
  if (el === document.scrollingElement || el === document.documentElement || el === document.body) {
    const s = document.scrollingElement || document.documentElement
    return { top: s.scrollTop, height: s.scrollHeight, client: s.clientHeight }
  }
  return { top: el.scrollTop, height: el.scrollHeight, client: el.clientHeight }
}

function scrollToBottom(el) {
  if (!el) return
  if (el === document.scrollingElement || el === document.documentElement || el === document.body) {
    const s = document.scrollingElement || document.documentElement
    s.scrollTop = s.scrollHeight
    return
  }
  el.scrollTop = el.scrollHeight
}

function getAllMessageBlocks(container) {
  const selectors = [
    "[data-message-author-role]",
    "[data-message-role]",
    "[data-role]",
    "[data-testid*='message']",
    "[data-testid*='chat-message']",
    "[role='listitem']",
    "[role='article']",
    "article",
    "[class*='message']:not([class*='messages'])",
    "[class*='bubble']",
    "[class*='chat-item']",
    "[class*='turn']",
    "div[data-index]",
    "div[class*='group']",
    "div[class*='item']",
    ".chat-content > div",
    ".conversation > div",
    "[class*='history'] > div"
  ]

  for (const sel of selectors) {
    let els
    try { els = container.querySelectorAll(sel) } catch (e) { els = null }
    if (els && els.length >= 2) return Array.from(els)
  }

  const children = Array.from(container.querySelectorAll("div, article, section"))
    .filter(el => {
      if (!el || !el.isConnected) return false
      if (el.getClientRects().length === 0) return false
      const text = (el.innerText || "").trim()
      if (text.length < 20 || text.length > 20000) return false
      const h = el.offsetHeight || 0
      if (h < 28) return false
      if (el.querySelector("input, textarea")) return false
      if (el.closest("nav, header, footer")) return false
      const hasStructured = el.querySelector("p, pre, ul, ol, blockquote, code") != null
      return hasStructured || text.includes("\n")
    })

  if (children.length >= 2) {
    children.sort((a, b) => (a.getBoundingClientRect().top - b.getBoundingClientRect().top))
    return children.slice(0, 400)
  }

  return []
}

function guessRoleByGeometry(block) {
  const r = block.getBoundingClientRect()
  const midX = r.left + r.width / 2
  const w = window.innerWidth || 1
  if (midX > w * 0.56) return "user"
  if (midX < w * 0.44) return "assistant"
  return null
}

function guessRole(block, index) {
  const dataRole =
    block.getAttribute("data-message-author-role") ||
    block.getAttribute("data-message-role") ||
    block.getAttribute("data-role") ||
    block.closest("[data-message-author-role]")?.getAttribute("data-message-author-role") ||
    block.closest("[data-message-role]")?.getAttribute("data-message-role") ||
    block.closest("[data-role]")?.getAttribute("data-role")

  if (dataRole) {
    const r = String(dataRole).toLowerCase()
    if (r.includes("user") || r.includes("human") || r.includes("me")) return "user"
    if (r.includes("assistant") || r.includes("ai") || r.includes("bot") || r.includes("model")) return "assistant"
  }

  const cls = String(block.className || "").toLowerCase()
  if (cls.match(/user|human|me|mine|self|我|用户|提问/)) return "user"
  if (cls.match(/assistant|ai|bot|model|回答|助理/)) return "assistant"

  const geo = guessRoleByGeometry(block)
  if (geo) return geo

  return (index % 2 === 0) ? "user" : "assistant"
}

function extractTextFromBlock(block) {
  const clone = block.cloneNode(true)

  const uiSelectors = [
    "button",
    "[class*='button']",
    "[class*='action']",
    "[class*='toolbar']",
    "[class*='feedback']",
    "[class*='copy']",
    "[class*='regenerate']",
    "svg",
    "img[class*='avatar']"
  ]

  for (const sel of uiSelectors) {
    clone.querySelectorAll(sel).forEach(el => el.remove())
  }

  clone.querySelectorAll("pre").forEach(pre => {
    const code = pre.querySelector("code")
    const lang =
      code?.className?.match(/language-(\w+)/)?.[1] ||
      code?.className?.match(/lang-(\w+)/)?.[1] || ""
    const text = (code?.innerText || pre.innerText || "").trim()
    pre.outerHTML = `\`\`\`${lang}\n${text}\n\`\`\``
  })

  let text = (clone.innerText || clone.textContent || "")
    .replace(/\u00a0/g, " ")
    .replace(/\r\n/g, "\n")
    .trim()

  text = text
    .replace(/复制|Copy|拷贝|复制代码|Copied!/g, "")
    .replace(/点赞|点踩|Good|Bad/g, "")
    .replace(/反馈|Feedback|举报/g, "")
    .replace(/重新生成|Regenerate/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim()

  return text
}

async function hydrateByScrolling(container) {
  const debugSteps = []
  let last = scrollMetrics(container)

  for (let i = 0; i < 22; i++) {
    scrollToBottom(container)
    await sleep(260)

    const now = scrollMetrics(container)
    debugSteps.push({ i, before: last, after: now })

    const grew = now.height > last.height + 20
    const moved = Math.abs(now.top - last.top) > 20

    last = now

    if (!grew && !moved) {
      if (i >= 2) break
    }
  }

  return debugSteps
}

async function extractUniversalChat() {
  const platform = detectPlatform()
  const container = pickBestScrollContainer()

  const debug = {
    platform,
    url: location.href,
    title: document.title || "",
    container_tag: container?.tagName || "none",
    container_id: container?.id || "",
    container_class: String(container?.className || "").slice(0, 200),
    scroll_before: scrollMetrics(container),
    selector_counts: {}
  }

  const scrollSteps = await hydrateByScrolling(container)
  debug.scroll_steps = scrollSteps
  debug.scroll_after = scrollMetrics(container)

  const blocks = getAllMessageBlocks(container)

  debug.raw_blocks = blocks.length
  const probeSelectors = [
    "[data-message-author-role]",
    "[data-message-role]",
    "[data-role]",
    "[data-testid*='message']",
    "article",
    "[class*='message']",
    "[role='listitem']"
  ]
  for (const sel of probeSelectors) {
    try { debug.selector_counts[sel] = container.querySelectorAll(sel).length } catch (e) { debug.selector_counts[sel] = -1 }
  }

  if (!blocks || blocks.length === 0) {
    return { ok: false, error: "no_blocks_universal", debug }
  }

  const items = []
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i]
    if (!block || !block.isConnected) continue
    if (block.closest("nav, header, footer")) continue
    if (block.querySelector("input, textarea")) continue

    const text = extractTextFromBlock(block)
    if (!text || text.length < 5) continue

    const role = guessRole(block, items.length)
    items.push({ role, text })
  }

  const deduped = []
  for (let i = 0; i < items.length; i++) {
    const prev = deduped[deduped.length - 1]
    if (prev && prev.role === items[i].role && prev.text === items[i].text) continue
    deduped.push(items[i])
  }

  const chat_txt = buildChatTxt(deduped)

  return {
    ok: chat_txt.length > 0,
    method: "universal_chat_extractor_v3",
    platform,
    url: location.href,
    title: document.title || "",
    dom_items: deduped,
    chat_txt,
    debug: {
      ...debug,
      extracted_items: items.length,
      deduped_items: deduped.length
    }
  }
}

browser.runtime.onMessage.addListener((msg) => {
  if (!msg || !msg.type) return
  if (msg.type === "nj_extract_chat_dom") return extractChatDom()
  if (msg.type === "nj_extract_chat_universal") return extractUniversalChat()
  if (msg.type === "nj_extract_html") return Promise.resolve(extractHtmlSnapshot())
})
