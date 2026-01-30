import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NJClipIngestor {
    static let appGroupID = "group.com.CYC.NotionJournal"
    static let inboxRelPath = "Clips/Inbox"
    static let ubiquityID = "iCloud.com.CYC.NotionJournal"
    static let hkTZ = "Asia/Hong_Kong"

    struct ClipDiskItem {
        let folderURL: URL
        let clipID: String
        let jsonURL: URL
        let pdfURL: URL
    }

    static func ingestAll(store: AppStore) async {
        let fm = FileManager.default

        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("NJ_CLIP_INGEST group_container_missing appGroupID=\(appGroupID)")
            return
        }

        let inboxURL = base.appendingPathComponent(inboxRelPath, isDirectory: true)
        print("NJ_CLIP_INGEST inbox=\(inboxURL.path)")

        guard fm.fileExists(atPath: inboxURL.path) else {
            print("NJ_CLIP_INGEST inbox_not_exist")
            return
        }

        guard let kids = try? fm.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("NJ_CLIP_INGEST list_failed inbox=\(inboxURL.path)")
            return
        }

        let folders = kids.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        print("NJ_CLIP_INGEST folders=\(folders.count)")

        for folder in folders {
            let rawID = folder.lastPathComponent
            let clipID = rawID.lowercased()

            let jsonURL = folder.appendingPathComponent("\(clipID).json", isDirectory: false)
            let pdfURL = folder.appendingPathComponent("\(clipID).pdf", isDirectory: false)

            if !fm.fileExists(atPath: jsonURL.path) {
                print("NJ_CLIP_INGEST skip_missing_json clipID=\(clipID) json=\(jsonURL.lastPathComponent)")
                continue
            }
            if !fm.fileExists(atPath: pdfURL.path) {
                print("NJ_CLIP_INGEST skip_missing_pdf clipID=\(clipID) pdf=\(pdfURL.lastPathComponent)")
                continue
            }

            await ingestOne(store: store, item: ClipDiskItem(folderURL: folder, clipID: clipID, jsonURL: jsonURL, pdfURL: pdfURL))
        }
    }

    static func ingestOne(store: AppStore, item: ClipDiskItem) async {
        let fm = FileManager.default
        print("NJ_CLIP_INGEST one_begin clipID=\(item.clipID) folder=\(item.folderURL.path)")

        guard let rawJSON = try? Data(contentsOf: item.jsonURL) else {
            print("NJ_CLIP_INGEST read_json_failed clipID=\(item.clipID) path=\(item.jsonURL.path)")
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: rawJSON),
              let dict = obj as? [String: Any] else {
            print("NJ_CLIP_INGEST parse_json_failed clipID=\(item.clipID) path=\(item.jsonURL.path)")
            return
        }

        let urlStr = (dict["url"] as? String) ?? ""
        let website = (dict["website"] as? String) ?? ""
        let mode = (dict["mode"] as? String) ?? ""
        let createdAtISO = (dict["created_at_iso"] as? String) ?? ""

        let createdAtMs: Int64 = {
            if let n = dict["created_at_ms"] as? NSNumber { return n.int64Value }
            if let n = dict["created_at_ms"] as? Int { return Int64(n) }
            if let s = dict["created_at_ms"] as? String, let v = Int64(s) { return v }
            return DBNoteRepository.nowMs()
        }()

        let srcTitle = (dict["title"] as? String) ?? ""

        let body = (
            (dict["body"] as? String) ??
            (dict["txt"] as? String) ??
            (dict["chat_txt"] as? String) ??
            ""
        )

        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("NJ_CLIP_INGEST skip_empty_body clipID=\(item.clipID)")
            return
        }

        guard let ubiq = fm.url(forUbiquityContainerIdentifier: ubiquityID) else {
            print("NJ_CLIP_INGEST ubiquity_missing ubiquityID=\(ubiquityID)")
            return
        }

        let docs = ubiq.appendingPathComponent("Documents", isDirectory: true)
        let (yyyy, mm) = yearMonthHK(ms: createdAtMs)
        let destDir = docs
            .appendingPathComponent(yyyy, isDirectory: true)
            .appendingPathComponent(mm, isDirectory: true)

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            print("NJ_CLIP_INGEST mkdir_failed dir=\(destDir.path) err=\(error)")
            return
        }

        let destPDF = destDir.appendingPathComponent("\(item.clipID).pdf", isDirectory: false)
        let destJSON = destDir.appendingPathComponent("\(item.clipID).json", isDirectory: false)

        print("NJ_CLIP_INGEST ai_begin clipID=\(item.clipID) body_len=\(body.count)")
        let r = await NJAppleIntelligenceSummarizer.summarizeAuto(text: body)
        let aiTitleRaw = (r.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let aiSummaryRaw = (r.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        print("NJ_CLIP_INGEST ai_done clipID=\(item.clipID) mode=\(r.mode) err=\(r.error ?? "") title_len=\(aiTitleRaw.count) sum_len=\(aiSummaryRaw.count)")

        let finalTitle = srcTitle.isEmpty ? "Clip" : srcTitle

        let headerWebsite = website.isEmpty ? (urlStr.isEmpty ? "Website" : urlStr) : website
        let headerLine = "\(headerWebsite) - \(finalTitle)"

        let bullets = aiSummaryRaw.isEmpty ? "" : aiSummaryRaw
        let finalSummary = headerLine + "\n" + bullets

        let protonRTFText = finalTitle + "\n\n" + finalSummary
        let protonRTFBase64 = makeRTFBase64(protonRTFText)

        let pdfOK = copyFile(fm: fm, src: item.pdfURL, dst: destPDF, label: "PDF", clipID: item.clipID)
        let jsonOK = writeBytesAtomic(fm: fm, data: rawJSON, dst: destJSON, label: "JSON", clipID: item.clipID)

        if !pdfOK || !jsonOK {
            print("NJ_CLIP_INGEST copy_failed clipID=\(item.clipID) pdfOK=\(pdfOK) jsonOK=\(jsonOK)")
            return
        }

        let payloadObj: [String: Any] = [
            "v": 1,
            "sections": [
                "clip": [
                    "v": 1,
                    "data": [
                        "website": website,
                        "url": urlStr,
                        "title": finalTitle,
                        "summary": finalSummary,
                        "created_at_ios": createdAtISO,
                        "created_at_ms": createdAtMs,
                        "mode": mode,
                        "pdf_path": "Documents/\(yyyy)/\(mm)/\(item.clipID).pdf",
                        "json_path": "Documents/\(yyyy)/\(mm)/\(item.clipID).json",
                        "body": body
                    ]
                ],
                "proton1": [
                    "v": 1,
                    "data": [
                        "proton_v": 1,
                        "proton_json": "",
                        "rtf_base64": protonRTFBase64
                    ]
                ]
            ]
        ]

        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadObj)) ?? Data()
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"

        let now = DBNoteRepository.nowMs()

        let fields: [String: Any] = [
            "block_id": item.clipID,
            "block_type": "clip",
            "payload_json": payloadJSON,
            "domain_tag": "",
            "tag_json": "[]",
            "lineage_id": "",
            "parent_block_id": "",
            "created_at_ms": createdAtMs,
            "updated_at_ms": now,
            "deleted": Int64(0)
        ]

        print("NJ_CLIP_INGEST db_upsert_begin clipID=\(item.clipID)")
        store.notes.applyRemoteUpsert(entity: "block", fields: fields)

        let dbHas = dbHasBlock(store: store, blockID: item.clipID)
        print("NJ_CLIP_INGEST db_upsert_done clipID=\(item.clipID) dbHas=\(dbHas)")

        let dirtyHas = dbHasDirty(store: store, entity: "block", entityID: item.clipID)
        print("NJ_CLIP_INGEST dirty_check clipID=\(item.clipID) dirtyHas=\(dirtyHas)")

        store.sync.schedulePush(debounceMs: 0)
        print("NJ_CLIP_INGEST push_scheduled clipID=\(item.clipID)")

        if dbHas && dirtyHas {
            do {
                try fm.removeItem(at: item.folderURL)
                print("NJ_CLIP_INGEST inbox_deleted folder=\(item.folderURL.path)")
            } catch {
                print("NJ_CLIP_INGEST inbox_delete_failed folder=\(item.folderURL.path) err=\(error)")
            }
        } else {
            print("NJ_CLIP_INGEST keep_inbox_folder clipID=\(item.clipID) dbHas=\(dbHas) dirtyHas=\(dirtyHas)")
        }
    }

    static func copyFile(fm: FileManager, src: URL, dst: URL, label: String, clipID: String) -> Bool {
        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
            print("NJ_CLIP_INGEST copy_ok clipID=\(clipID) \(label) src=\(src.path) dst=\(dst.path)")
            return true
        } catch {
            print("NJ_CLIP_INGEST copy_fail clipID=\(clipID) \(label) src=\(src.path) dst=\(dst.path) err=\(error)")
            return false
        }
    }

    static func writeBytesAtomic(fm: FileManager, data: Data, dst: URL, label: String, clipID: String) -> Bool {
        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try data.write(to: dst, options: [.atomic])
            print("NJ_CLIP_INGEST write_ok clipID=\(clipID) \(label) dst=\(dst.path) bytes=\(data.count)")
            return true
        } catch {
            print("NJ_CLIP_INGEST write_fail clipID=\(clipID) \(label) dst=\(dst.path) err=\(error)")
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

    static func yearMonthHK(ms: Int64) -> (String, String) {
        let sec = TimeInterval(ms) / 1000.0
        let d = Date(timeIntervalSince1970: sec)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: hkTZ) ?? .current
        let y = cal.component(.year, from: d)
        let m = cal.component(.month, from: d)
        return (String(format: "%04d", y), String(format: "%02d", m))
    }

    static func makeRTFBase64(_ s: String) -> String {
        let attr = NSAttributedString(string: s)
        let data = (try? attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
        return data.base64EncodedString()
    }
}
