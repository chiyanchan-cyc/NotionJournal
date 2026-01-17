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
  return items
    .map(it => `${roleLabel(it.role)}:\n${it.text}`)
    .join("\n\n")
    .trim()
}

function getAllTurnBlocks() {
  const main = document.querySelector("main")
  if (!main) return []
  return Array.from(
    main.querySelectorAll('article[data-testid^="conversation-turn"], div[data-testid^="conversation-turn"]')
  )
}

function getBlockTop(el) {
  const r = el.getBoundingClientRect()
  return r.top + window.scrollY
}

function extractFromBlock(block) {
  const nodes = Array.from(
    block.querySelectorAll('[data-message-author-role]')
  )

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
  // 1) DISCOVER ALL BLOCKS (no scrolling logic yet)
  const blocks = getAllTurnBlocks()

  if (blocks.length === 0) {
    return { ok: false, error: "no conversation blocks found" }
  }

  // 2) ORDER BLOCKS BY ACTUAL POSITION
  const ordered = blocks
    .map(b => ({ el: b, top: getBlockTop(b) }))
    .sort((a, b) => a.top - b.top)

  const items = []

  // 3) WALK BLOCKS ONE BY ONE
  for (let i = 0; i < ordered.length; i++) {
    const block = ordered[i].el

    // scroll THIS block into view
    block.scrollIntoView({ block: "center", behavior: "auto" })
    await sleep(60) // slow on purpose – hydration time

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

browser.runtime.onMessage.addListener((msg) => {
  if (!msg || !msg.type) return
  if (msg.type === "nj_extract_chat_dom") return extractChatDom()
  if (msg.type === "nj_extract_html") return Promise.resolve(extractHtmlSnapshot())
})
