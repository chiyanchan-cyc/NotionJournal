import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NJAudioIngestor {
    static let appGroupID = "group.com.CYC.NotionJournal"
    static let inboxRelPath = "Audio/Inbox"
    static let ubiquityID = "iCloud.com.CYC.NotionJournal"

    struct AudioDiskItem {
        let folderURL: URL
        let blockID: String
        let jsonURL: URL
        let audioURL: URL
        let audioExt: String
    }

    static func ingestAll(store: AppStore) async {
        let fm = FileManager.default

        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("NJ_AUDIO_INGEST group_container_missing appGroupID=\(appGroupID)")
            return
        }

        let inboxURL = base.appendingPathComponent(inboxRelPath, isDirectory: true)
        print("NJ_AUDIO_INGEST inbox=\(inboxURL.path)")

        guard fm.fileExists(atPath: inboxURL.path) else {
            print("NJ_AUDIO_INGEST inbox_not_exist")
            return
        }

        guard let kids = try? fm.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("NJ_AUDIO_INGEST list_failed inbox=\(inboxURL.path)")
            return
        }

        let folders = kids.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        print("NJ_AUDIO_INGEST folders=\(folders.count)")

        for folder in folders {
            let rawID = folder.lastPathComponent
            let blockID = rawID.lowercased()

            let jsonURL = folder.appendingPathComponent("\(blockID).json", isDirectory: false)
            if !fm.fileExists(atPath: jsonURL.path) {
                print("NJ_AUDIO_INGEST skip_missing_json blockID=\(blockID) json=\(jsonURL.lastPathComponent)")
                continue
            }

            guard let audioURL = findAudioFile(in: folder) else {
                print("NJ_AUDIO_INGEST skip_missing_audio blockID=\(blockID)")
                continue
            }

            let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension.lowercased()

            await ingestOne(
                store: store,
                item: AudioDiskItem(
                    folderURL: folder,
                    blockID: blockID,
                    jsonURL: jsonURL,
                    audioURL: audioURL,
                    audioExt: ext
                )
            )
        }
    }

    static func ingestOne(store: AppStore, item: AudioDiskItem) async {
        let fm = FileManager.default
        print("NJ_AUDIO_INGEST one_begin blockID=\(item.blockID) folder=\(item.folderURL.path)")

        guard let rawJSON = try? Data(contentsOf: item.jsonURL) else {
            print("NJ_AUDIO_INGEST read_json_failed blockID=\(item.blockID) path=\(item.jsonURL.path)")
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: rawJSON),
              let dict = obj as? [String: Any] else {
            print("NJ_AUDIO_INGEST parse_json_failed blockID=\(item.blockID) path=\(item.jsonURL.path)")
            return
        }

        let recordedAtMs: Int64 = {
            if let n = dict["recorded_at_ms"] as? NSNumber { return n.int64Value }
            if let n = dict["recorded_at_ms"] as? Int { return Int64(n) }
            if let s = dict["recorded_at_ms"] as? String, let v = Int64(s) { return v }
            if let n = dict["created_at_ms"] as? NSNumber { return n.int64Value }
            if let n = dict["created_at_ms"] as? Int { return Int64(n) }
            if let s = dict["created_at_ms"] as? String, let v = Int64(s) { return v }
            return DBNoteRepository.nowMs()
        }()

        let recordedAtISO: String = {
            if let s = dict["recorded_at_iso"] as? String, !s.isEmpty { return s }
            let d = Date(timeIntervalSince1970: TimeInterval(recordedAtMs) / 1000.0)
            return ISO8601DateFormatter().string(from: d)
        }()
        let originalName = (dict["original_filename"] as? String) ?? ""
        let title = originalName.isEmpty ? "Audio Recording" : stripExtension(originalName)

        guard let ubiq = fm.url(forUbiquityContainerIdentifier: ubiquityID) else {
            print("NJ_AUDIO_INGEST ubiquity_missing ubiquityID=\(ubiquityID)")
            return
        }

        let docs = ubiq.appendingPathComponent("Documents", isDirectory: true)
        let (yyyy, mm) = yearMonthLocal(ms: recordedAtMs)
        let destDir = docs
            .appendingPathComponent(yyyy, isDirectory: true)
            .appendingPathComponent(mm, isDirectory: true)

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            print("NJ_AUDIO_INGEST mkdir_failed dir=\(destDir.path) err=\(error)")
            return
        }

        let destAudio = destDir.appendingPathComponent("\(item.blockID).\(item.audioExt)", isDirectory: false)
        let audioOK = copyFile(fm: fm, src: item.audioURL, dst: destAudio, label: "AUDIO", blockID: item.blockID)

        if !audioOK {
            print("NJ_AUDIO_INGEST copy_failed blockID=\(item.blockID)")
            return
        }

        let placeholderText = "Audio Recording\n\n(Transcript pending)"
        let rtfBase64 = NJPayloadConverterV1.makeRTFBase64(placeholderText)

        let payloadObj: [String: Any] = [
            "v": 1,
            "sections": [
                "audio": [
                    "v": 1,
                    "data": [
                        "title": title,
                        "recorded_at_ms": recordedAtMs,
                        "recorded_at_iso": recordedAtISO,
                        "audio_path": "Documents/\(yyyy)/\(mm)/\(item.blockID).\(item.audioExt)",
                        "audio_ext": item.audioExt,
                        "original_filename": originalName,
                        "transcript_txt": ""
                    ]
                ],
                "proton1": [
                    "v": 1,
                    "data": [
                        "proton_v": 1,
                        "proton_json": "",
                        "rtf_base64": rtfBase64
                    ]
                ]
            ]
        ]

        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadObj)) ?? Data()
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"

        let now = DBNoteRepository.nowMs()

        let fields: [String: Any] = [
            "block_id": item.blockID,
            "block_type": "audio",
            "payload_json": payloadJSON,
            "domain_tag": "",
            "tag_json": "[]",
            "lineage_id": "",
            "parent_block_id": "",
            "created_at_ms": recordedAtMs,
            "updated_at_ms": now,
            "deleted": Int64(0)
        ]

        print("NJ_AUDIO_INGEST db_upsert_begin blockID=\(item.blockID)")
        store.notes.applyRemoteUpsert(entity: "block", fields: fields)

        let dbHas = dbHasBlock(store: store, blockID: item.blockID)
        print("NJ_AUDIO_INGEST db_upsert_done blockID=\(item.blockID) dbHas=\(dbHas)")

        let dirtyHas = dbHasDirty(store: store, entity: "block", entityID: item.blockID)
        print("NJ_AUDIO_INGEST dirty_check blockID=\(item.blockID) dirtyHas=\(dirtyHas)")

        store.sync.schedulePush(debounceMs: 0)
        print("NJ_AUDIO_INGEST push_scheduled blockID=\(item.blockID)")

        if dbHas && dirtyHas {
            do {
                try fm.removeItem(at: item.folderURL)
                print("NJ_AUDIO_INGEST inbox_deleted folder=\(item.folderURL.path)")
            } catch {
                print("NJ_AUDIO_INGEST inbox_delete_failed folder=\(item.folderURL.path) err=\(error)")
            }
        } else {
            print("NJ_AUDIO_INGEST keep_inbox_folder blockID=\(item.blockID) dbHas=\(dbHas) dirtyHas=\(dirtyHas)")
        }
    }

    static func findAudioFile(in folder: URL) -> URL? {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }
        let audio = kids.filter { $0.pathExtension.lowercased() != "json" }
        return audio.first
    }

    static func stripExtension(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? name : base
    }

    static func copyFile(fm: FileManager, src: URL, dst: URL, label: String, blockID: String) -> Bool {
        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
            print("NJ_AUDIO_INGEST copy_ok blockID=\(blockID) \(label) src=\(src.path) dst=\(dst.path)")
            return true
        } catch {
            print("NJ_AUDIO_INGEST copy_fail blockID=\(blockID) \(label) src=\(src.path) dst=\(dst.path) err=\(error)")
            return false
        }
    }

    static func dbHasBlock(store: AppStore, blockID: String) -> Bool {
        store.db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, "SELECT 1 FROM nj_block WHERE block_id=? AND deleted=0 LIMIT 1;", -1, &stmt, nil)
            if rc != SQLITE_OK { return false }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    static func dbHasDirty(store: AppStore, entity: String, entityID: String) -> Bool {
        store.db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, "SELECT 1 FROM nj_dirty WHERE entity=? AND entity_id=? LIMIT 1;", -1, &stmt, nil)
            if rc != SQLITE_OK { return false }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, entity, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entityID, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    static func yearMonthLocal(ms: Int64) -> (String, String) {
        let sec = TimeInterval(ms) / 1000.0
        let d = Date(timeIntervalSince1970: sec)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let y = cal.component(.year, from: d)
        let m = cal.component(.month, from: d)
        return (String(format: "%04d", y), String(format: "%02d", m))
    }
}
