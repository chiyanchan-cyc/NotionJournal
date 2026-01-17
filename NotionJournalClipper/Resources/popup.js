function setStatus(s) {
  const el = document.getElementById("status")
  el.textContent = s || ""
}

async function doClip(mode) {
  setStatus("Working...")
  try {
    const res = await browser.runtime.sendMessage({ type: "nj_clip", mode })
    if (!res) {
      setStatus("Failed\n(no response)")
      return
    }
    if (res.ok) {
      window.close()
      return
    }
    setStatus("Failed\n" + JSON.stringify(res, null, 2))
  } catch (e) {
    setStatus("Failed\n" + String(e))
  }
}

document.getElementById("btnDom").addEventListener("click", () => doClip("chat_dom"))
document.getElementById("btnHtml").addEventListener("click", () => doClip("html_landscape"))
