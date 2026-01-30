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

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  log("onMessage", msg)

  ;(async () => {
    try {
      if (msg.type === "nj_clip") {
        const mode = msg.mode || ""

        const debugInfo = {
          received_mode: mode,
          mode_type: typeof mode,
          mode_length: mode.length,
          is_chat_dom: mode === "chat_dom",
          is_chat_universal: mode === "chat_universal",
          is_html_landscape: mode === "html_landscape",
          char_codes: Array.from(mode).map(c => c.charCodeAt(0))
        }

        log("DEBUG", debugInfo)

        if (mode !== "chat_dom" && mode !== "chat_universal" && mode !== "html_landscape") {
          return sendResponse({
            ok: false,
            error: "invalid_mode",
            debug: debugInfo,
            help: "Mode must be chat_dom, chat_universal, or html_landscape"
          })
        }

        const tab = await activeTab()
        if (!tab || !tab.id) return sendResponse({ ok: false, error: "no_active_tab" })

        const block_id = (crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}_${Math.random().toString(16).slice(2)}`
        const captured_at_ms = Date.now()

        let extracted
        if (mode === "chat_dom") {
          extracted = await browser.tabs.sendMessage(tab.id, { type: "nj_extract_chat_dom" })
        } else if (mode === "chat_universal") {
          extracted = await browser.tabs.sendMessage(tab.id, { type: "nj_extract_chat_universal" })
        } else {
          extracted = await browser.tabs.sendMessage(tab.id, { type: "nj_extract_html" })
        }

        if (!extracted || extracted.ok !== true) {
          return sendResponse({
            ok: false,
            error: "extract_not_ok",
            detail: extracted || null,
            debug: { mode_used: mode }
          })
        }

        const native_mode = (mode === "chat_universal") ? "chat_dom" : mode

        const payload = {
          type: "clip_save",
          block_id,
          mode: native_mode,
          extractor_mode: mode,
          extractor_method: extracted.method || "",
          url: extracted.url || tab.url || "",
          title: extracted.title || tab.title || "",
          captured_at_ms
        }

        if (mode === "chat_dom" || mode === "chat_universal") {
          payload.dom_items = extracted.dom_items || []
          payload.txt = extracted.chat_txt || ""
        } else {
          payload.head_html = extracted.head_html || ""
          payload.body_html = extracted.body_html || ""
          payload.txt = extracted.html_txt || ""
        }
          
          payload.extractor_debug = extracted.debug || null
          payload.extractor_platform = extracted.platform || null


        log("SENDING_NATIVE", {
          block_id,
          sent_mode: payload.mode,
          extractor_mode: payload.extractor_mode,
          host: NATIVE_HOST
        })

        let native
        try {
          native = await sendNative(payload)
        } catch (e) {
          log("NATIVE_THROW", String(e))
          return sendResponse({ ok: false, error: "native_throw", detail: String(e), block_id })
        }

        log("NATIVE_RESP", native)

        if (native && native.ok === false && native.error === "invalid_mode") {
          return sendResponse({
            ok: false,
            error: "native_invalid_mode",
            native,
            debug: { sent_mode: payload.mode, extractor_mode: payload.extractor_mode }
          })
        }

        return sendResponse(native)
      }

      if (msg.type === "debug_paths") {
        let native
        try {
          native = await sendNative({ type: "debug_paths" })
        } catch (e) {
          return sendResponse({ ok: false, error: "native_throw", detail: String(e) })
        }
        return sendResponse(native)
      }

      return sendResponse({ ok: false, error: "unknown_type", type: msg.type })
    } catch (e) {
      return sendResponse({ ok: false, error: "bg_exception", detail: String(e) })
    }
  })()

  return true
})
