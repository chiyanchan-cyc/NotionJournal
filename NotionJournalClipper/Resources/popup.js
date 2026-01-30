function setStatus(s) {
  const el = document.getElementById("status")
  el.textContent = s || ""
}

async function doClip(mode) {
  // Show what we're sending
  setStatus("Sending mode: " + mode + "\nWaiting for response...")
  
  try {
    const res = await browser.runtime.sendMessage({ type: "nj_clip", mode })
    if (!res) {
      setStatus("Failed (no response)")
      return
    }
    if (res.ok) {
      window.close()
      return
    }
    // Show full error including debug info
    setStatus("Failed\n" + JSON.stringify(res, null, 2))
  } catch (e) {
    setStatus("Failed\n" + String(e))
  }
}

document.getElementById("btnDom").addEventListener("click", () => doClip("chat_dom"))
document.getElementById("btnHtml").addEventListener("click", () => doClip("html_landscape"))
document.getElementById("btnUniversal").addEventListener("click", () => doClip("chat_universal"))
