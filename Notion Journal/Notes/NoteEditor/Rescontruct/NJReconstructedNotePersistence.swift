//
//  NJReconstructedNotePersistence.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/23.
//

import SwiftUI
import Combine
import UIKit
import Proton
import SQLite3
import CryptoKit

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func NJStableUUID(_ s: String) -> UUID {
    let d = Data(s.utf8)
    let h = SHA256.hash(data: d)
    var b = [UInt8](h.prefix(16))
    b[6] = (b[6] & 0x0F) | 0x50
    b[8] = (b[8] & 0x3F) | 0x80
    let u = uuid_t(b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    return UUID(uuid: u)
}

final class NJReconstructedNotePersistence: ObservableObject {
    @Published var title: String = ""
    @Published var tab: String = ""
    @Published var blocks: [NJNoteEditorContainerPersistence.BlockState] = []
    @Published var focusedBlockID: UUID? = nil
    @Published var blockMainDomainByBlockID: [String: String] = [:]

    private var store: AppStore? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var didConfigure = false

    private var spec: NJReconstructedSpec

    init(spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
    }

    private func collapseKey(blockID: String) -> String {
        "nj.reconstructed.collapse.\(blockID)"
    }

    func loadCollapsed(blockID: String) -> Bool {
        UserDefaults.standard.bool(forKey: collapseKey(blockID: blockID))
    }

    func saveCollapsed(blockID: String, collapsed: Bool) {
        UserDefaults.standard.set(collapsed, forKey: collapseKey(blockID: blockID))
    }

    func setCollapsed(id: UUID, collapsed: Bool) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        var arr = blocks
        arr[i].isCollapsed = collapsed
        blocks = arr
        saveCollapsed(blockID: arr[i].blockID, collapsed: collapsed)
    }

    func configure(store: AppStore) {
        if didConfigure { return }
        self.store = store
        self.didConfigure = true
    }

    func updateSpec(_ spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
    }

    func rowBackgroundColor(blockID: String) -> Color? {
        guard let key = blockMainDomainByBlockID[blockID], !key.isEmpty else { return nil }
        return NJDomainColorConfig.color(for: key)?.opacity(0.22)
    }

    private func dbLoadNoteDomainForBlockID(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            let candidates = [
                "tab_domain",
                "domain",
                "domain_tag"
            ]

            for col in candidates {
                var stmt: OpaquePointer?
                let sql = """
                SELECT n.\(col)
                FROM nj_note n
                JOIN nj_note_block nb
                  ON nb.note_id = n.note_id
                WHERE nb.block_id = ? COLLATE NOCASE
                  AND (n.deleted IS NULL OR n.deleted = 0)
                ORDER BY n.updated_at_ms DESC
                LIMIT 1;
                """
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { continue }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let c = sqlite3_column_text(stmt, 0) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { return s }
                    }
                }
            }

            return ""
        }
    }

    private func dbLoadBlockTagJSON(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = "SELECT tag_json FROM nj_block WHERE block_id = ? LIMIT 1;"
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { out = String(cString: c) }
            }
            return out
        }
    }

    private func dbLoadDomainPreview3FromBlockTag(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var tags: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT tag
            FROM nj_block_tag
            WHERE block_id = ? COLLATE NOCASE
            ORDER BY created_at_ms ASC
            LIMIT 3;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { tags.append(s) }
                }
            }
            return tags.joined(separator: ", ")
        }
    }

    private struct Row {
        let blockID: String
        let protonJSON: String
        let createdAtMs: Int64
    }
    
    private func currentWeekRangeMs() -> (start: Int64, end: Int64) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        let now = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let startDate = cal.date(from: comps) ?? now
        let endDate = cal.date(byAdding: .day, value: 7, to: startDate) ?? now
        return (Int64(startDate.timeIntervalSince1970 * 1000), Int64(endDate.timeIntervalSince1970 * 1000) - 1)
    }


    private func sqlWhereForSpec() -> (whereSQL: String, binder: (OpaquePointer?) -> Void) {
        var startMs = spec.startMs
        var endMs = spec.endMs

        if startMs == nil && endMs == nil {
            if case .exact(let tagRaw) = spec.match {
                let t = tagRaw.lowercased()
                if t == "#weekly" || t == "weekly" {
                    let r = currentWeekRangeMs()
                    startMs = r.start
                    endMs = r.end
                }
            }
        }

        let timeExpr: String = {
            switch spec.timeField {
            case .blockCreatedAtMs:
                return "b.created_at_ms"
            case .tagCreatedAtMs:
                return "t.created_at_ms"
            }
        }()

        let fmt: (Int64?) -> String = { ms in
            guard let ms else { return "nil" }
            let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
            return "\(ms) (\(d))"
        }
        print("NJ_RECON_SPEC id=\(spec.id) match=\(spec.match) timeField=\(spec.timeField) startMs=\(fmt(startMs)) endMs=\(fmt(endMs)) timeExpr=\(timeExpr)")

        switch spec.match {
        case .exact(let tagRaw):
            let tagA = tagRaw
            let tagB: String = {
                if tagRaw.hasPrefix("#") { return String(tagRaw.dropFirst()) }
                return "#\(tagRaw)"
            }()
            var whereParts: [String] = []
            whereParts.append("(lower(t.tag)=lower(?) OR lower(t.tag)=lower(?))")
            if startMs != nil { whereParts.append("\(timeExpr) >= ?") }
            if endMs != nil { whereParts.append("\(timeExpr) <= ?") }
            let whereSQL = whereParts.joined(separator: " AND ")
            let binder: (OpaquePointer?) -> Void = { stmt in
                guard let stmt else { return }
                var i: Int32 = 1
                sqlite3_bind_text(stmt, i, tagA, -1, SQLITE_TRANSIENT); i += 1
                sqlite3_bind_text(stmt, i, tagB, -1, SQLITE_TRANSIENT); i += 1
                if let startMs {
                    sqlite3_bind_int64(stmt, i, startMs); i += 1
                }
                if let endMs {
                    sqlite3_bind_int64(stmt, i, endMs); i += 1
                }
            }
            print("NJ_RECON_WHERE exact sql=\(whereSQL) tagA=\(tagA) tagB=\(tagB)")
            return (whereSQL, binder)

        case .prefix(let prefixRaw):
            let p = prefixRaw.lowercased()
            let like1 = p + "%"
            let pHash = p.hasPrefix("#") ? String(p.dropFirst()) : "#"+p
            let like2 = pHash + "%"

            var whereParts: [String] = []
            whereParts.append("(lower(t.tag) LIKE ? OR lower(t.tag) LIKE ?)")
            if startMs != nil { whereParts.append("\(timeExpr) >= ?") }
            if endMs != nil { whereParts.append("\(timeExpr) <= ?") }
            let whereSQL = whereParts.joined(separator: " AND ")
            let binder: (OpaquePointer?) -> Void = { stmt in
                guard let stmt else { return }
                var i: Int32 = 1
                sqlite3_bind_text(stmt, i, like1, -1, SQLITE_TRANSIENT); i += 1
                sqlite3_bind_text(stmt, i, like2, -1, SQLITE_TRANSIENT); i += 1
                if let startMs {
                    sqlite3_bind_int64(stmt, i, startMs); i += 1
                }
                if let endMs {
                    sqlite3_bind_int64(stmt, i, endMs); i += 1
                }
            }
            print("NJ_RECON_WHERE prefix sql=\(whereSQL) like1=\(like1) like2=\(like2)")
            return (whereSQL, binder)
        }
    }

    private func dbExtractProtonJSONFromPayload(_ payload: String) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let proton1 = sections["proton1"] as? [String: Any],
            let dataNode = proton1["data"] as? [String: Any],
            let pj = dataNode["proton_json"] as? String
        else { return nil }
        return pj
    }

    private func dbLoadProtonJSONAny(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            let candidates = [
                "proton_json",
                "protonJSON",
                "proton_json_str",
                "proton_json_text",
                "payload_json",
                "payload_json_str",
                "payload",
                "payload_str",
                "payload_text",
                "rtf_payload",
                "content_json",
                "content"
            ]

            for col in candidates {
                var stmt: OpaquePointer?
                let sql = "SELECT \(col) FROM nj_block WHERE block_id = ? LIMIT 1;"
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { continue }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) != SQLITE_ROW { continue }

                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                if s.isEmpty { continue }

                if s.first == "{" {
                    if let extracted = dbExtractProtonJSONFromPayload(s) {
                        return extracted
                    }
                }

                return s
            }

            let msg = String(cString: sqlite3_errmsg(dbp))
            print("NJ_RECON PROTON_NOT_FOUND block_id=\(blockID) msg=\(msg)")
            return ""
        }
    }

    private func dbLoadCreatedAtMs(_ blockID: String) -> Int64 {
        guard let store else { return 0 }
        return store.notes.db.withDB { dbp in
            var out: Int64 = 0
            var stmt: OpaquePointer?
            let sql = "SELECT created_at_ms FROM nj_block WHERE block_id = ? LIMIT 1;"
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_RECON CREATED_PREP_FAIL rc=\(rc0) msg=\(msg)")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                out = sqlite3_column_int64(stmt, 0)
            }
            return out
        }
    }

    private func dbLoadBlockIDsBySpec() -> [String] {
        guard let store else { return [] }
        return store.notes.db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?

            let (whereSQL, binder) = sqlWhereForSpec()
            let orderSQL = spec.newestFirst ? "DESC" : "ASC"

        let timeExpr: String = {
            switch spec.timeField {
            case .blockCreatedAtMs:
                return "b.created_at_ms"
            case .tagCreatedAtMs:
                return "t.created_at_ms"
            }
        }()

            let sql = """
            SELECT t.block_id
            FROM nj_block_tag t
            LEFT JOIN nj_block b
              ON b.block_id = t.block_id COLLATE NOCASE
            WHERE \(whereSQL)
            GROUP BY t.block_id
            ORDER BY \(timeExpr) \(orderSQL)
            LIMIT ?;
            """
            print("NJ_RECON_QUERY sql=\(sql) limit=\(spec.limit) newestFirst=\(spec.newestFirst)")

            // Debug counts for tag-only vs tag+time
            do {
                var stmtCount: OpaquePointer?
                let countSQL = """
                SELECT COUNT(*)
                FROM nj_block_tag t
                LEFT JOIN nj_block b
                  ON b.block_id = t.block_id COLLATE NOCASE
                WHERE \(whereSQL);
                """
                if sqlite3_prepare_v2(dbp, countSQL, -1, &stmtCount, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(stmtCount) }
                    binder(stmtCount)
                    if sqlite3_step(stmtCount) == SQLITE_ROW {
                        let c = sqlite3_column_int64(stmtCount, 0)
                        print("NJ_RECON_COUNT where_count=\(c)")
                    }
                }
            }

            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_RECON IDS_PREP_FAIL rc=\(rc0) msg=\(msg)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            binder(stmt)

            let n = sqlite3_bind_parameter_count(stmt)
            sqlite3_bind_int(stmt, n, Int32(max(1, spec.limit)))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { out.append(s) }
                }
            }

            if out.isEmpty {
                print("NJ_RECON IDS_EMPTY spec=\(spec.id)")
            }

            return out
        }
    }

    private func dbLoadRows() -> [Row] {
        let ids = dbLoadBlockIDsBySpec()
        if ids.isEmpty { return [] }

        var out: [Row] = []
        out.reserveCapacity(ids.count)

        for bid in ids {
            let createdAtMs = dbLoadCreatedAtMs(bid)
            let protonJSON = dbLoadProtonJSONAny(bid)
            out.append(Row(blockID: bid, protonJSON: protonJSON, createdAtMs: createdAtMs))
        }

        return out
    }

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
        blockMainDomainByBlockID = [:]

        let rows = dbLoadRows()
        if rows.isEmpty {
            blocks = []
            focusedBlockID = nil
            return
        }

        var out: [NJNoteEditorContainerPersistence.BlockState] = []
        out.reserveCapacity(rows.count)

        var ok: Double = 1000

        for r in rows {
            let noteDomain = dbLoadNoteDomainForBlockID(r.blockID)
            let mainKey = NJDomainColorConfig.normalizedSecondTierKey(noteDomain)
            if !mainKey.isEmpty {
                blockMainDomainByBlockID[r.blockID] = mainKey
            }

            let stableID = UUID(uuidString: r.blockID)
                ?? NJStableUUID("\(spec.id)|\(r.blockID)|")
            let h = makeHandle()
            h.ownerBlockUUID = stableID

            let attr: NSAttributedString = {
                if !r.protonJSON.isEmpty {
                    let first = h.previewFirstLineFromProtonJSON(r.protonJSON)
                    return makeTypedFromPlain(first)
                }
                return makeTypedFromPlain("")
            }()

            let domainPreview = dbLoadDomainPreview3FromBlockTag(r.blockID)
            let tagJSON = dbLoadBlockTagJSON(r.blockID)

            out.append(
                NJNoteEditorContainerPersistence.BlockState(
                    id: stableID,
                    blockID: r.blockID,
                    instanceID: "",
                    orderKey: ok,
                    createdAtMs: r.createdAtMs,
                    domainPreview: domainPreview,
                    attr: attr,
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: loadCollapsed(blockID: r.blockID),
                    protonHandle: h,
                    isDirty: false,
                    loadedUpdatedAtMs: 0,
                    loadedPayloadHash: "",
                    protonJSON: r.protonJSON,
                    tagJSON: tagJSON
                )
            )

            ok += 1
        }

        blocks = out
        assert(Set(blocks.map { $0.id }).count == blocks.count)
        focusedBlockID = blocks.first?.id
    }

    private func makeTypedFromPlain(_ s: String) -> NSAttributedString {
        let cleaned = s.isEmpty ? "\u{200B}" : s
        return NSAttributedString(string: cleaned)
    }

    private func extractPhotoAttachments(from attr: NSAttributedString) -> [NJPhotoAttachmentView] {
        if attr.length == 0 { return [] }
        var out: [NJPhotoAttachmentView] = []
        let r = NSRange(location: 0, length: attr.length)
        attr.enumerateAttribute(.attachment, in: r, options: []) { value, range, _ in
            guard let att = value as? Attachment else { return }
            guard att.isBlockType else { return }
            guard let view = att.contentView as? NJPhotoAttachmentView else { return }
            out.append(view)
        }
        return out
    }

    func hydrateProton(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let json = blocks[i].protonJSON
        if json.isEmpty { return }
        blocks[i].protonHandle.hydrateFromProtonJSONString(json)
    }

    func markDirty(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty { blocks[i].isDirty = true }
    }

    func scheduleCommit(_ id: UUID, debounce: Double = 0.9) {
        commitWork[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitBlockNow(id) }
        commitWork[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    func forceEndEditingAndCommitNow(_ id: UUID) {
        commitWork[id]?.cancel()
        commitWork[id] = nil
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[i].protonHandle.isEditing = false
        markDirty(id)
        commitBlockNow(id, force: true)
    }

    func commitBlockNow(_ id: UUID) {
        commitBlockNow(id, force: false)
    }

    func commitBlockNow(_ id: UUID, force: Bool = false) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty { return }

        if !force && blocks[i].protonHandle.isEditing {
            scheduleCommit(id, debounce: 0.6)
            return
        }

        var b = blocks[i]

        guard let editor = b.protonHandle.editor else {
            if b.protonJSON.isEmpty {
                b.isDirty = false
                blocks[i] = b
                return
            }
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: b.protonJSON,
                tagJSON: b.tagJSON
            )
            b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
            b.isDirty = false
            blocks[i] = b
            return
        }

        let liveAttr = editor.attributedText

        let existingTags: [String] = {
            guard !b.tagJSON.isEmpty,
                  let data = b.tagJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()

        let tagRes = NJTagExtraction.extract(from: liveAttr, existingTags: existingTags)
        let mergedTags = tagRes?.tags ?? existingTags

        if let tagRes {
            NotificationCenter.default.post(
                name: Notification.Name("NJ_BLOCK_TAGS_EXTRACTED"),
                object: nil,
                userInfo: [
                    "block_id": b.blockID,
                    "tags": tagRes.tags
                ]
            )
        }

        let mergedTagJSON: String = {
            guard !mergedTags.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: mergedTags),
                  let s = String(data: data, encoding: .utf8)
            else { return "" }
            return s
        }()

        if !mergedTagJSON.isEmpty {
            b.tagJSON = mergedTagJSON
            blocks[i].tagJSON = mergedTagJSON
        }

        let originalAttr = editor.attributedText
        let originalSel  = editor.selectedRange

        if let cleaned = tagRes?.cleaned {
            editor.attributedText = cleaned
        }

        let protonJSON = b.protonHandle.exportProtonJSONString()

        editor.attributedText = originalAttr
        editor.selectedRange = originalSel

        b.protonJSON = protonJSON
        blocks[i].protonJSON = protonJSON

        let nowMs = DBNoteRepository.nowMs()
        let views = extractPhotoAttachments(from: originalAttr)
        let existing = store.notes.listAttachments(blockID: b.blockID)
        var existingByID: [String: NJAttachmentRecord] = [:]
        for e in existing { existingByID[e.attachmentID] = e }

        var seen = Set<String>()
        for v in views {
            let id = v.attachmentID
            seen.insert(id)
            let prior = existingByID[id]
            let thumb = v.image.flatMap { img in
                NJAttachmentCache.saveThumbnail(image: img, attachmentID: id, width: NJAttachmentCache.thumbWidth)
            }
            let thumbPath = thumb?.url.path ?? prior?.thumbPath ?? ""
            let displayW = Int(v.displaySize.width)
            let displayH = Int(v.displaySize.height)
            let fullPhotoRef = v.fullPhotoRef.isEmpty ? (prior?.fullPhotoRef ?? "") : v.fullPhotoRef
            let record = NJAttachmentRecord(
                attachmentID: id,
                blockID: b.blockID,
                noteID: nil,
                kind: .photo,
                thumbPath: thumbPath,
                fullPhotoRef: fullPhotoRef,
                displayW: displayW,
                displayH: displayH,
                createdAtMs: prior?.createdAtMs ?? nowMs,
                updatedAtMs: nowMs,
                deleted: 0
            )
            store.notes.upsertAttachment(record, nowMs: nowMs)
        }

        for e in existing where !seen.contains(e.attachmentID) {
            store.notes.markAttachmentDeleted(attachmentID: e.attachmentID, nowMs: nowMs)
        }

        let tagJSONToSave = b.tagJSON

        store.notes.saveSingleProtonBlock(
            blockID: b.blockID,
            protonJSON: protonJSON,
            tagJSON: tagJSONToSave
        )

        b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
        b.isDirty = false
        blocks[i] = b

    }
}
