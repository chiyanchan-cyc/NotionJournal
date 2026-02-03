import Foundation
import UniformTypeIdentifiers

final class NJAudioShareReceiver {
    static let appGroupID = "group.com.CYC.NotionJournal"
    static let inboxRelPath = "Audio/Inbox"

    static func handleIncomingURL(_ url: URL) -> String? {
        let fm = FileManager.default
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), !type.conforms(to: .audio) {
            print("NJ_AUDIO_SHARE skip_non_audio ext=\(ext)")
            return nil
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("NJ_AUDIO_SHARE group_container_missing appGroupID=\(appGroupID)")
            return nil
        }

        let inboxURL = base.appendingPathComponent(inboxRelPath, isDirectory: true)
        let blockID = UUID().uuidString.lowercased()
        let dir = inboxURL.appendingPathComponent(blockID, isDirectory: true)

        let audioURL = dir.appendingPathComponent("\(blockID).\(ext)", isDirectory: false)
        let jsonURL = dir.appendingPathComponent("\(blockID).json", isDirectory: false)

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("NJ_AUDIO_SHARE mkdir_failed err=\(error)")
            return nil
        }

        let recordedAt = fileRecordedAt(url: url) ?? Date()
        let recordedAtMs = Int64(recordedAt.timeIntervalSince1970 * 1000.0)
        let recordedAtISO = ISO8601DateFormatter().string(from: recordedAt)

        let originalName = url.lastPathComponent

        let jsonObj: [String: Any] = [
            "recorded_at_ms": recordedAtMs,
            "recorded_at_iso": recordedAtISO,
            "original_filename": originalName
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            print("NJ_AUDIO_SHARE write_json_failed err=\(error)")
            return nil
        }

        do {
            if fm.fileExists(atPath: audioURL.path) { try fm.removeItem(at: audioURL) }
            try fm.copyItem(at: url, to: audioURL)
        } catch {
            print("NJ_AUDIO_SHARE copy_audio_failed err=\(error)")
            return nil
        }

        return blockID
    }

    private static func fileRecordedAt(url: URL) -> Date? {
        if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            if let c = values.creationDate { return c }
            if let m = values.contentModificationDate { return m }
        }
        return nil
    }
}
