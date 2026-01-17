import SafariServices
import Foundation
import WebKit

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupId = "group.com.CYC.NotionJournal"
    private var renderJobs: [String: RenderJob] = [:]

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        handle(message: message) { response in
            let responseItem = NSExtensionItem()
            responseItem.userInfo = [SFExtensionMessageKey: response]
            context.completeRequest(returningItems: [responseItem], completionHandler: nil)
        }
    }

    private func handle(message: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let type = (message["type"] as? String) ?? ""

        if type == "ping" {
            completion(["ok": true, "type": "pong", "ts": Date().timeIntervalSince1970])
            return
        }

        if type == "debug_paths" {
            guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
                completion(["ok": false, "error": "app_group_nil"])
                return
            }
            let inbox = root.appendingPathComponent("Clips/Inbox", isDirectory: true)
            completion(["ok": true, "group_root": root.path, "inbox_root": inbox.path])
            return
        }

        if type == "clip_save" {
            clipSave(message: message, completion: completion)
            return
        }

        completion(["ok": false, "error": "unknown_type", "type": type])
    }

    private func clipSave(message: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard
            let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId),
            let blockId = message["block_id"] as? String,
            let mode = message["mode"] as? String,
            let urlStr = message["url"] as? String
        else {
            completion(["ok": false, "error": "missing_fields"])
            return
        }

        let inbox = root.appendingPathComponent("Clips/Inbox", isDirectory: true)
        let dir = inbox.appendingPathComponent(blockId, isDirectory: true)
        let jsonURL = dir.appendingPathComponent("\(blockId).json")
        let pdfURL = dir.appendingPathComponent("\(blockId).pdf")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion(["ok": false, "error": "mkdir_failed", "detail": error.localizedDescription])
            return
        }

        let now = Date()
        let createdAtMs = Int64(now.timeIntervalSince1970 * 1000.0)
        let createdAtISO = ISO8601DateFormatter().string(from: now)
        let website = URL(string: urlStr)?.host ?? ""

        let bodyText = (message["txt"] as? String) ?? ""
        let srcTitle = (message["title"] as? String) ?? ""

        let jsonObj: [String: Any] = [
            "created_at_ms": createdAtMs,
            "created_at_iso": createdAtISO,
            "website": website,
            "url": urlStr,
            "mode": mode,
            "title": srcTitle,
            "body": bodyText
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            completion(["ok": false, "error": "write_json_failed", "detail": error.localizedDescription, "json": jsonURL.path])
            return
        }

        let title = srcTitle
        let baseURL = URL(string: urlStr)

        let html: String
        let pageRect: CGRect

        if mode == "chat_dom" {
            let items = (message["dom_items"] as? [[String: Any]]) ?? []
            html = renderChatHTML(title: title, url: urlStr, items: items)
            pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        } else if mode == "html_landscape" {
            let head = (message["head_html"] as? String) ?? ""
            let body = (message["body_html"] as? String) ?? ""
            html = renderPageHTMLLandscape(title: title, url: urlStr, head: head, body: body)
            pageRect = CGRect(x: 0, y: 0, width: 792, height: 612)
        } else {
            completion(["ok": false, "error": "invalid_mode"])
            return
        }

        renderPDF(blockId: blockId, html: html, baseURL: baseURL, pageRect: pageRect, timeoutSec: 18.0) { data, err in
            if let err = err {
                completion([
                    "ok": false,
                    "error": "pdf_failed",
                    "pdf_error": err,
                    "dir": dir.path,
                    "json": jsonURL.path
                ])
                return
            }

            guard let data = data else {
                completion([
                    "ok": false,
                    "error": "pdf_failed",
                    "pdf_error": "no_data",
                    "dir": dir.path,
                    "json": jsonURL.path
                ])
                return
            }

            do {
                try data.write(to: pdfURL, options: .atomic)
                completion([
                    "ok": true,
                    "block_id": blockId,
                    "mode": mode,
                    "dir": dir.path,
                    "json": jsonURL.path,
                    "pdf": pdfURL.path,
                    "pdf_bytes": data.count
                ])
            } catch {
                completion([
                    "ok": false,
                    "error": "write_pdf_failed",
                    "detail": error.localizedDescription,
                    "dir": dir.path,
                    "json": jsonURL.path,
                    "pdf": pdfURL.path
                ])
            }
        }
    }

    private func renderPDF(blockId: String, html: String, baseURL: URL?, pageRect: CGRect, timeoutSec: TimeInterval, completion: @escaping (Data?, String?) -> Void) {
        DispatchQueue.main.async {
            let job = RenderJob(blockId: blockId, html: html, baseURL: baseURL, pageRect: pageRect, timeoutSec: timeoutSec) { [weak self] data, err in
                self?.renderJobs[blockId] = nil
                completion(data, err)
            }
            self.renderJobs[blockId] = job
            job.start()
        }
    }

    private final class RenderJob: NSObject, WKNavigationDelegate {
        private let blockId: String
        private let html: String
        private let baseURL: URL?
        private let pageRect: CGRect
        private let timeoutSec: TimeInterval
        private let completion: (Data?, String?) -> Void

        private var webView: WKWebView?
        private var done = false
        private var timeoutWork: DispatchWorkItem?

        init(blockId: String, html: String, baseURL: URL?, pageRect: CGRect, timeoutSec: TimeInterval, completion: @escaping (Data?, String?) -> Void) {
            self.blockId = blockId
            self.html = html
            self.baseURL = baseURL
            self.pageRect = pageRect
            self.timeoutSec = timeoutSec
            self.completion = completion
        }

        func start() {
            let cfg = WKWebViewConfiguration()
            cfg.defaultWebpagePreferences.allowsContentJavaScript = false

            let wv = WKWebView(frame: pageRect, configuration: cfg)
            wv.navigationDelegate = self
            self.webView = wv

            let work = DispatchWorkItem { [weak self] in
                self?.finish(data: nil, err: "timeout")
            }
            self.timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSec, execute: work)

            wv.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if done { return }
            waitForAssetsAndLayout(webView: webView, triesLeft: 12) { [weak self] _ in
                guard let self = self else { return }
                if self.done { return }
                self.renderFullDocumentPDF(webView: webView)
            }
        }

        private func waitForAssetsAndLayout(webView: WKWebView, triesLeft: Int, completion: @escaping (Bool) -> Void) {
            if triesLeft <= 0 { completion(false); return }

            let js =
"""
(() => {
  const imgs = Array.from(document.images || []);
  const imgsDone = imgs.every(i => i.complete);
  const rs = document.readyState;
  return { readyState: rs, imgsDone: imgsDone, scrollW: document.documentElement.scrollWidth, scrollH: document.documentElement.scrollHeight };
})()
"""
            webView.evaluateJavaScript(js) { [weak self] v, _ in
                guard let self = self else { return }
                if self.done { return }

                if let d = v as? [String: Any],
                   let rs = d["readyState"] as? String,
                   let imgsDone = d["imgsDone"] as? Bool,
                   rs == "complete",
                   imgsDone == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        completion(true)
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.waitForAssetsAndLayout(webView: webView, triesLeft: triesLeft - 1, completion: completion)
                }
            }
        }

        private func renderFullDocumentPDF(webView: WKWebView) {
            let js =
"""
(() => {
  const de = document.documentElement;
  return { w: de.scrollWidth, h: de.scrollHeight };
})()
"""
            webView.evaluateJavaScript(js) { [weak self] v, _ in
                guard let self = self else { return }
                if self.done { return }

                var cssW: CGFloat = self.pageRect.width
                var cssH: CGFloat = self.pageRect.height

                if let d = v as? [String: Any] {
                    if let w = d["w"] as? Double, w > 0 { cssW = CGFloat(w) }
                    if let h = d["h"] as? Double, h > 0 { cssH = CGFloat(h) }
                }

                let pointsW = self.pageRect.width
                let scale = pointsW / max(cssW, 1)
                let pointsH = ceil(cssH * scale)

                let cfg = WKPDFConfiguration()
                cfg.rect = CGRect(x: 0, y: 0, width: pointsW, height: max(pointsH, self.pageRect.height))

                webView.createPDF(configuration: cfg) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let data):
                        self.finish(data: data, err: nil)
                    case .failure(let error):
                        self.finish(data: nil, err: error.localizedDescription)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(data: nil, err: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(data: nil, err: error.localizedDescription)
        }

        private func finish(data: Data?, err: String?) {
            if done { return }
            done = true
            timeoutWork?.cancel()
            timeoutWork = nil
            webView?.navigationDelegate = nil
            webView = nil
            completion(data, err)
        }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func renderChatHTML(title: String, url: String, items: [[String: Any]]) -> String {
        var rows = ""
        for it in items {
            let role = ((it["role"] as? String) ?? "unknown").lowercased()
            let text = (it["text"] as? String) ?? ""
            let cls = role == "user" ? "user" : role == "assistant" ? "assistant" : "other"
            rows += """
            <div class="msg \(cls)">
              <div class="role">\(esc(role.uppercased()))</div>
              <div class="text">\(esc(text).replacingOccurrences(of: "\n", with: "<br/>"))</div>
            </div>
            """
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <title>\(esc(title))</title>
          <style>
            @page { size: letter portrait; margin: 24pt; }
            body{font:12pt -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; color:#111;}
            .hdr{margin-bottom:14pt;}
            .t{font-weight:800;font-size:14pt;margin:0 0 6pt 0;}
            .u{font-size:9pt;color:#666;word-break:break-all;}
            .msg{border-radius:12pt;padding:12pt 12pt;margin:10pt 0;page-break-inside:avoid;}
            .msg.user{background:#e8f0ff;}
            .msg.assistant{background:#eefcef;}
            .msg.other{background:#f3f4f6;}
            .role{font-weight:800;font-size:9pt;margin-bottom:6pt;color:#334155;}
            .text{white-space:normal;line-height:1.35;}
          </style>
        </head>
        <body>
          <div class="hdr">
            <div class="t">\(esc(title))</div>
            <div class="u">\(esc(url))</div>
          </div>
          \(rows)
        </body>
        </html>
        """
    }

    private func renderPageHTMLLandscape(title: String, url: String, head: String, body: String) -> String {
        let safeTitle = esc(title)
        let safeURL = esc(url)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <base href="\(safeURL)"/>
          <title>\(safeTitle)</title>
          \(head)
          <style>
            @page { size: letter landscape; margin: 18pt; }
            body{font:11pt -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; color:#111;}
            img{max-width:100% !important; height:auto !important;}
            pre, code{white-space:pre-wrap; word-break:break-word;}
            a{word-break:break-all;}
            .nj_hdr{margin:0 0 10pt 0; padding:0 0 10pt 0; border-bottom:1px solid #e5e7eb;}
            .nj_title{font-weight:800;font-size:13pt;margin:0 0 4pt 0;}
            .nj_url{font-size:9pt;color:#666; margin:0;}
          </style>
        </head>
        <body>
          <div class="nj_hdr">
            <div class="nj_title">\(safeTitle)</div>
            <div class="nj_url">\(safeURL)</div>
          </div>
          \(body)
        </body>
        </html>
        """
    }
}
