//
//  preview.js
//  Notion Journal
//
//  Created by Mac on 2026/1/7.
//


function getClipId() {
  const h = (location.hash || "").slice(1)
  try { return decodeURIComponent(h) } catch (_) { return h }
}

async function loadPreview() {
  const clip_id = getClipId()
  document.getElementById("clipIdLabel").textContent = clip_id ? `#${clip_id}` : ""

  const res = await browser.runtime.sendMessage({ type: "nj_preview_get", clip_id })
  const html = (res && res.ok) ? (res.html || "") : ""

  if (!html) {
    const wrap = document.getElementById("wrap")
    wrap.innerHTML = `<div class="msg">No preview HTML found for this clip_id.</div>`
    return
  }

  document.open()
  document.write(html)
  document.close()
}

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("reloadBtn").addEventListener("click", () => loadPreview())
  loadPreview()
})
