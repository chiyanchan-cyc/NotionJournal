const NATIVE_HOST = "LLMJournal.NotionJournal.NotionJournalClipper"

function log(...a) { console.log("[NJClipper BG]", ...a) }
log("LOADED", { ts: Date.now(), href: location.href })

async function activeTab() {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true })
  return tabs && tabs[0] ? tabs[0] : null
}

async function sendNative(payload) {
  return await browser.runtime.sendNativeMessage(NATIVE_HOST, payload)
}

function summarizeExtracted(extracted) {
  if (!extracted || typeof extracted !== "object") return { ok: false }
  const items = extracted.dom_items || []
  const roles = items.slice(0, 12).map(x => x.role)
  const txtLen = (extracted.chat_txt || extracted.html_txt || "").length
  return {
    ok: !!extracted.ok,
    method: extracted.method || "",
    url: extracted.url || "",
    title: extracted.title || "",
    items_count: items.length,
    first_roles: roles,
    txt_len: txtLen,
    debug: extracted.debug || null
  }
}

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  log("onMessage", msg)

  ;(async () => {
    try {
      if (msg.type === "nj_clip") {
        const mode = msg.mode || ""
        if (mode !== "chat_dom" && mode !== "html_landscape") return sendResponse({ ok: false, error: "invalid_mode" })

        const tab = await activeTab()
        if (!tab || !tab.id) return sendResponse({ ok: false, error: "no_active_tab" })

        const block_id = (crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}_${Math.random().toString(16).slice(2)}`
        const captured_at_ms = Date.now()

        let extracted
        if (mode === "chat_dom") extracted = await browser.tabs.sendMessage(tab.id, { type: "nj_extract_chat_dom" })
        else extracted = await browser.tabs.sendMessage(tab.id, { type: "nj_extract_html" })

        log("extracted", summarizeExtracted(extracted))

        if (!extracted || extracted.ok !== true) {
          const err = { ok: false, error: "extract_not_ok", detail: extracted || null }
          log("extract_not_ok", err)
          return sendResponse(err)
        }

        const payload = {
          type: "clip_save",
          block_id,
          mode,
          url: extracted.url || tab.url || "",
          title: extracted.title || tab.title || "",
          captured_at_ms
        }

        if (mode === "chat_dom") {
          payload.dom_items = extracted.dom_items || []
          payload.txt = extracted.chat_txt || ""
        } else {
          payload.head_html = extracted.head_html || ""
          payload.body_html = extracted.body_html || ""
          payload.txt = extracted.html_txt || ""
        }

        let native
        try {
          native = await sendNative(payload)
        } catch (e) {
          const err = { ok: false, error: "native_throw", detail: String(e), block_id }
          log("native_throw", err)
          return sendResponse(err)
        }

        log("native_response(clip_save)", native)
        return sendResponse(native)
      }

      if (msg.type === "debug_paths") {
        let native
        try {
          native = await sendNative({ type: "debug_paths" })
        } catch (e) {
          const err = { ok: false, error: "native_throw", detail: String(e) }
          log("native_throw", err)
          return sendResponse(err)
        }
        log("native_response(debug_paths)", native)
        return sendResponse(native)
      }

      return sendResponse({ ok: false, error: "unknown_type", type: msg.type })
    } catch (e) {
      const err = { ok: false, error: "bg_exception", detail: String(e) }
      log("bg_exception", err)
      return sendResponse(err)
    }
  })()

  return true
})
