import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private static let appGroupID = "group.com.CYC.NotionJournal"
    private static let inboxRelPath = "Audio/Inbox"
    private let finishLock = NSLock()
    private var didFinish = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleShare()
    }

    private func handleShare() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish()
            return
        }

        var jobs: [(NSItemProvider, String)] = []
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Audio.identifier) {
                    jobs.append((provider, UTType.mpeg4Audio.identifier))
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                    jobs.append((provider, UTType.audio.identifier))
                }
            }
        }

        if jobs.isEmpty {
            finish()
            return
        }

        let group = DispatchGroup()
        for (provider, typeId) in jobs {
            group.enter()
            loadAndCopy(provider: provider, typeId: typeId) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.finish()
        }
    }

    private func loadAndCopy(provider: NSItemProvider, typeId: String, completion: @escaping () -> Void) {
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
            if let url = item as? URL {
                self.copyToInbox(url: url)
            } else if let data = item as? Data {
                self.writeDataToInbox(data: data, suggestedName: nil)
            }
            completion()
        }
    }

    private func copyToInbox(url: URL) {
        guard let inbox = inboxURL() else {
            return
        }

        let fm = FileManager.default
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let blockID = UUID().uuidString.lowercased()
        let dir = inbox.appendingPathComponent(blockID, isDirectory: true)

        let audioURL = dir.appendingPathComponent("\(blockID).\(ext)", isDirectory: false)
        let jsonURL = dir.appendingPathComponent("\(blockID).json", isDirectory: false)

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let recordedAt = fileRecordedAt(url: url) ?? Date()
        let recordedAtMs = Int64(recordedAt.timeIntervalSince1970 * 1000.0)
        let recordedAtISO = ISO8601DateFormatter().string(from: recordedAt)

        let jsonObj: [String: Any] = [
            "recorded_at_ms": recordedAtMs,
            "recorded_at_iso": recordedAtISO,
            "original_filename": url.lastPathComponent
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            return
        }

        do {
            if fm.fileExists(atPath: audioURL.path) { try fm.removeItem(at: audioURL) }
            try fm.copyItem(at: url, to: audioURL)
        } catch {
            return
        }
    }

    private func writeDataToInbox(data: Data, suggestedName: String?) {
        guard let inbox = inboxURL() else {
            return
        }

        let blockID = UUID().uuidString.lowercased()
        let dir = inbox.appendingPathComponent(blockID, isDirectory: true)
        let name = suggestedName?.isEmpty == false ? suggestedName! : "\(blockID).m4a"
        let audioURL = dir.appendingPathComponent(name, isDirectory: false)
        let jsonURL = dir.appendingPathComponent("\(blockID).json", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: audioURL, options: .atomic)

            let now = Date()
            let jsonObj: [String: Any] = [
                "recorded_at_ms": Int64(now.timeIntervalSince1970 * 1000.0),
                "recorded_at_iso": ISO8601DateFormatter().string(from: now),
                "original_filename": name
            ]
            let payload = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys])
            try payload.write(to: jsonURL, options: .atomic)
        } catch {
            return
        }
    }

    private func inboxURL() -> URL? {
        let fm = FileManager.default
        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return nil
        }
        return base.appendingPathComponent(Self.inboxRelPath, isDirectory: true)
    }

    private func fileRecordedAt(url: URL) -> Date? {
        if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            if let c = values.creationDate { return c }
            if let m = values.contentModificationDate { return m }
        }
        return nil
    }

    private func finish() {
        finishLock.lock()
        if didFinish {
            finishLock.unlock()
            return
        }
        didFinish = true
        finishLock.unlock()
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
