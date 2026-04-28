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
    @Published private(set) var hasPendingRemoteRefresh: Bool = false

    private var store: AppStore? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var didConfigure = false
    private var loadedContentWatermarkMs: Int64 = 0
    private var loadedContentSignature: String = ""
    private let editorLeaseDurationMs: Int64 = 120_000

    private var spec: NJReconstructedSpec

    init(spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
    }

    private var localEditorDeviceID: String {
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? UIDevice.current.identifierForVendor?.uuidString ?? "unknown" : host
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

    func enqueueEditorChange(_ id: UUID, source: String = "unknown") {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.focusedBlockID != id {
                self.focusedBlockID = id
            }
            if let i = self.blocks.firstIndex(where: { $0.id == id }) {
                if self.shouldAbortForRemoteEditorLease(index: i) {
                    return
                }
                self.blocks[i].verifiedLocalEditAtMs = DBNoteRepository.nowMs()
                self.publishEditorLease(for: i, source: source)
            }
            self.markDirty(id, source: source)
            self.scheduleCommit(id, source: source)
        }
    }

    func configure(store: AppStore) {
        if didConfigure { return }
        self.store = store
        self.didConfigure = true
    }

    func makeWiredHandle() -> NJProtonEditorHandle {
        let h = NJProtonEditorHandle()
        h.attachmentResolver = { [weak store] id in
            store?.notes.attachmentByID(id)
        }
        h.attachmentThumbPathCleaner = { [weak store] id in
            store?.notes.clearAttachmentThumbPath(attachmentID: id, nowMs: DBNoteRepository.nowMs())
        }
        h.onOpenFullPhoto = { id in
            NJPhotoLibraryPresenter.presentFullPhoto(localIdentifier: id)
        }
        h.onUserTyped = { [weak self, weak h] _, _ in
            guard let self, let handle = h, let id = handle.ownerBlockUUID else { return }
            if handle.isRunningProgrammaticUpdate { return }
            self.enqueueEditorChange(id, source: "recon.persistence.onUserTyped.\(handle.userEditSourceHint)")
        }
        h.onSnapshot = { _, _ in
            // Passive snapshots can be emitted by layout/hydration on idle devices.
            // Only explicit user edits should enqueue a save.
        }
        return h
    }

    func addBlankBlock(
        blockID: String? = nil,
        initialProtonJSON: String = "",
        makeHandle: @escaping () -> NJProtonEditorHandle
    ) -> UUID {
        let stableBlockID = (blockID ?? UUID().uuidString).trimmingCharacters(in: .whitespacesAndNewlines)
        let newID = UUID(uuidString: stableBlockID) ?? NJStableUUID("\(spec.id)|\(stableBlockID)|")
        let handle = makeHandle()
        handle.ownerBlockUUID = newID

        let nextOrder = (blocks.map(\.orderKey).max() ?? 999) + 1
        let new = NJNoteEditorContainerPersistence.BlockState(
            id: newID,
            blockID: stableBlockID,
            instanceID: "",
            orderKey: nextOrder,
            createdAtMs: DBNoteRepository.nowMs(),
            domainPreview: "",
            goalPreview: "",
            attr: makeTypedFromPlain(""),
            sel: NSRange(location: 0, length: 0),
            isCollapsed: false,
            protonHandle: handle,
            isDirty: true,
            loadedUpdatedAtMs: 0,
            loadedPayloadHash: "",
            protonJSON: initialProtonJSON,
            tagJSON: ""
        )

        blocks.insert(new, at: 0)
        focusedBlockID = newID
        scheduleCommit(newID)
        return newID
    }

    func updateSpec(_ spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
        self.hasPendingRemoteRefresh = false
    }

    func markPendingRemoteRefresh() {
        hasPendingRemoteRefresh = true
    }

    func clearPendingRemoteRefresh() {
        hasPendingRemoteRefresh = false
    }

    func hasActivelyEditingBlock() -> Bool {
        blocks.contains { $0.protonHandle.isEditing }
    }

    func hasRemoteContentUpdateAvailable() -> Bool {
        let currentSignature = currentContentSignature()
        if !currentSignature.isEmpty, currentSignature == loadedContentSignature {
            return false
        }
        return currentContentWatermarkMs() > loadedContentWatermarkMs
    }

    private func markLocalContentCommitted() {
        loadedContentWatermarkMs = max(loadedContentWatermarkMs, currentContentWatermarkMs())
        loadedContentSignature = currentContentSignature()
        hasPendingRemoteRefresh = false
    }

    private func stableContentSignature(parts: [String]) -> String {
        let joined = parts.joined(separator: "\u{1F}")
        let data = Data(joined.utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func currentContentSignature() -> String {
        let blockIDs = blocks.map(\.blockID)
        var parts: [String] = [
            "spec_id=\(spec.id)",
            "title=\(title)",
            "tab=\(tab)"
        ]
        parts.reserveCapacity(parts.count + blockIDs.count * 3)

        for blockID in blockIDs {
            parts.append("block_id=\(blockID)")
            parts.append("payload=\(dbLoadBlockPayloadJSON(blockID))")
            parts.append("tag_json=\(dbLoadBlockTagJSON(blockID))")
        }

        parts.append("visible_block_count=\(blockIDs.count)")

        return stableContentSignature(parts: parts)
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

    private func dbLoadBlockProtonJSON(_ blockID: String) -> String {
        let payloadJSON = dbLoadBlockPayloadJSON(blockID)
        guard !payloadJSON.isEmpty else { return "" }
        let (protonJSON, _) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payloadJSON)
        return protonJSON
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

    private func domainPreviewFromTagJSON(_ tagJSON: String) -> String {
        if tagJSON.isEmpty { return "" }
        if let data = tagJSON.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.joined(separator: ", ")
        }
        return ""
    }

    private func stablePayloadHash(_ protonJSON: String) -> String {
        guard !protonJSON.isEmpty else { return "" }
        let data = Data(protonJSON.utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func dbLoadBlockUpdatedAtMs(_ blockID: String) -> Int64 {
        guard let store else { return 0 }
        return store.notes.db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "SELECT updated_at_ms FROM nj_block WHERE block_id = ? LIMIT 1;"
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return 0
        }
    }

    private func shouldDeferCommitWhileFocused(id: UUID, index: Int) -> Bool {
        guard blocks.indices.contains(index) else { return false }
        let handle = blocks[index].protonHandle
        if handle.isEditing { return true }
        guard focusedBlockID == id else { return false }
        if let responderHandle = NJProtonEditorHandle.firstResponderHandle(),
           responderHandle === handle || responderHandle.ownerBlockUUID == id {
            return true
        }
        if let activeHandle = NJProtonEditorHandle.activeHandle(),
           activeHandle === handle || activeHandle.ownerBlockUUID == id {
            return true
        }
        return false
    }

    private func shouldAbortStaleEditorSave(index: Int, candidateProtonJSON: String) -> Bool {
        guard blocks.indices.contains(index) else { return false }
        let b = blocks[index]
        let dbUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)

        guard b.loadedUpdatedAtMs > 0,
              dbUpdatedAtMs > b.loadedUpdatedAtMs else {
            return false
        }

        let candidateHash = stablePayloadHash(candidateProtonJSON)
        let loadedHash = b.loadedPayloadHash.isEmpty ? stablePayloadHash(b.protonJSON) : b.loadedPayloadHash
        print("NJ_BLOCK_ABORT_STALE_EDITOR_SAVE block_id=\(b.blockID) loaded_updated_at_ms=\(b.loadedUpdatedAtMs) db_updated_at_ms=\(dbUpdatedAtMs) candidate_matches_loaded=\(candidateHash == loadedHash ? 1 : 0) verified_local_edit=\(b.verifiedLocalEditAtMs > 0 ? 1 : 0)")

        if b.verifiedLocalEditAtMs <= 0 {
            print("NJ_BLOCK_ABORT_REMOTE_STALE_SAVE_NO_LOCAL_EDIT block_id=\(b.blockID) loaded_updated_at_ms=\(b.loadedUpdatedAtMs) db_updated_at_ms=\(dbUpdatedAtMs)")
            markPendingRemoteRefresh()
            blocks[index].isDirty = false
            blocks[index].verifiedLocalEditAtMs = 0
            blocks[index].protonHandle.isEditing = false
            reloadBlockFromStore(at: index)
            return true
        }

        if candidateHash != loadedHash {
            markPendingRemoteRefresh()
            return false
        }

        if b.isDirty || b.protonHandle.isEditing {
            markPendingRemoteRefresh()
            return true
        }

        reloadBlockFromStore(at: index)
        return true
    }

    private func noteBlockInstanceID(for index: Int) -> String {
        guard blocks.indices.contains(index) else { return "" }
        let existing = blocks[index].instanceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty { return existing }
        return store?.notes.findFirstInstanceByBlock(blockID: blocks[index].blockID)?.instanceID ?? ""
    }

    private func publishEditorLease(for index: Int, source: String) {
        guard let store, blocks.indices.contains(index) else { return }
        let instanceID = noteBlockInstanceID(for: index)
        guard !instanceID.isEmpty else { return }
        let nowMs = DBNoteRepository.nowMs()
        store.notes.updateNoteBlockEditorLease(
            instanceID: instanceID,
            deviceID: localEditorDeviceID,
            nowMs: nowMs,
            expiresAtMs: nowMs + editorLeaseDurationMs
        )
        print("NJ_BLOCK_EDITOR_LEASE_PUBLISH source=\(source) block_id=\(blocks[index].blockID) instance_id=\(instanceID) device_id=\(localEditorDeviceID) expires_at_ms=\(nowMs + editorLeaseDurationMs)")
        store.sync.schedulePush(debounceMs: 0)
    }

    private func shouldAbortForRemoteEditorLease(index: Int) -> Bool {
        guard let store, blocks.indices.contains(index) else { return false }
        let nowMs = DBNoteRepository.nowMs()
        guard let lease = store.notes.activeRemoteEditorLease(
            blockID: blocks[index].blockID,
            localDeviceID: localEditorDeviceID,
            nowMs: nowMs
        ) else {
            return false
        }
        print("NJ_BLOCK_ABORT_REMOTE_EDITOR_LEASE block_id=\(blocks[index].blockID) remote_device_id=\(lease.deviceID) expires_at_ms=\(lease.expiresAtMs) now_ms=\(nowMs)")
        markPendingRemoteRefresh()
        blocks[index].isDirty = false
        blocks[index].verifiedLocalEditAtMs = 0
        blocks[index].protonHandle.isEditing = false
        return true
    }

    private struct Row {
        let blockID: String
        let payloadJSON: String
        let createdAtMs: Int64
    }

    private struct MarkerLookupKey: Hashable {
        let tag: String
        let content: String
    }

    private enum MarkerBucket: Hashable {
        case year(String)
        case month(String)
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
        let spec = self.spec
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
            if case .all = spec.match {
                return "b.created_at_ms"
            }
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
        print("NJ_RECON_SPEC id=\(spec.id) match=\(spec.match) timeField=\(spec.timeField) startMs=\(fmt(startMs)) endMs=\(fmt(endMs)) timeExpr=\(timeExpr) include=\(spec.includeTags) include_mode=\(spec.includeMode) exclude=\(spec.excludeTags)")

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
            for _ in spec.excludeTags {
                whereParts.append("t.block_id NOT IN (SELECT block_id FROM nj_block_tag WHERE lower(tag)=lower(?))")
            }
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
                for t in spec.excludeTags {
                    sqlite3_bind_text(stmt, i, t, -1, SQLITE_TRANSIENT); i += 1
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
            for _ in spec.excludeTags {
                whereParts.append("t.block_id NOT IN (SELECT block_id FROM nj_block_tag WHERE lower(tag)=lower(?))")
            }
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
                for t in spec.excludeTags {
                    sqlite3_bind_text(stmt, i, t, -1, SQLITE_TRANSIENT); i += 1
                }
            }
            print("NJ_RECON_WHERE prefix sql=\(whereSQL) like1=\(like1) like2=\(like2)")
            return (whereSQL, binder)
        case .all:
            var whereParts: [String] = []
            whereParts.append("(b.deleted IS NULL OR b.deleted = 0)")
            if startMs != nil { whereParts.append("\(timeExpr) >= ?") }
            if endMs != nil { whereParts.append("\(timeExpr) <= ?") }
            if !spec.includeTags.isEmpty {
                if spec.includeMode == .all {
                    for _ in spec.includeTags {
                        whereParts.append("b.block_id IN (SELECT ti.block_id FROM nj_block_tag ti WHERE lower(ti.tag)=lower(?))")
                    }
                } else {
                    let ors = spec.includeTags.map { _ in "lower(ti.tag)=lower(?)" }.joined(separator: " OR ")
                    whereParts.append("b.block_id IN (SELECT ti.block_id FROM nj_block_tag ti WHERE \(ors))")
                }
            }
            for _ in spec.excludeTags {
                whereParts.append("b.block_id NOT IN (SELECT block_id FROM nj_block_tag WHERE lower(tag)=lower(?))")
            }
            let whereSQL = whereParts.joined(separator: " AND ")
            let binder: (OpaquePointer?) -> Void = { stmt in
                guard let stmt else { return }
                var i: Int32 = 1
                if let startMs {
                    sqlite3_bind_int64(stmt, i, startMs); i += 1
                }
                if let endMs {
                    sqlite3_bind_int64(stmt, i, endMs); i += 1
                }
                for t in spec.includeTags {
                    sqlite3_bind_text(stmt, i, t, -1, SQLITE_TRANSIENT); i += 1
                }
                for t in spec.excludeTags {
                    sqlite3_bind_text(stmt, i, t, -1, SQLITE_TRANSIENT); i += 1
                }
            }
            print("NJ_RECON_WHERE all sql=\(whereSQL)")
            return (whereSQL, binder)
        case .customIDs:
            return ("b.deleted=0", { _ in })
        }
    }

    private func extractProtonJSONAndRTFBase64(fromPayloadJSON payload: String) -> (String, String) {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payload),
           let data = normalized.data(using: .utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
           let proton = try? v1.proton1Data() {
            return proton.proton_json.isEmpty ? ("", proton.rtf_base64) : (proton.proton_json, "")
        }

        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("", "")
        }

        if let sections = root["sections"] as? [String: Any],
           let proton1 = sections["proton1"] as? [String: Any],
           let dataNode = proton1["data"] as? [String: Any] {
            let protonJSON = dataNode["proton_json"] as? String ?? ""
            return (
                protonJSON,
                protonJSON.isEmpty ? dataNode["rtf_base64"] as? String ?? "" : ""
            )
        }

        let protonJSON = root["proton_json"] as? String ?? ""
        let rtfBase64 = root["rtf_base64"] as? String ?? ""
        return protonJSON.isEmpty ? ("", rtfBase64) : (protonJSON, "")
    }

    private func dbLoadBlockPayloadJSON(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT payload_json
            FROM nj_block
            WHERE block_id = ? AND deleted = 0
            LIMIT 1;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_RECON PAYLOAD_PREP_FAIL block_id=\(blockID) rc=\(rc0) msg=\(msg)")
                return ""
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let c = sqlite3_column_text(stmt, 0) {
                return String(cString: c)
            }
            return ""
        }
    }

    private func blockContent(fromPayloadJSON payloadJSON: String, handle: NJProtonEditorHandle) -> (protonJSON: String, attr: NSAttributedString) {
        guard !payloadJSON.isEmpty else { return ("", makeTypedFromPlain("")) }

        func protonJSONHasStructuredAttachment(_ json: String) -> Bool {
            guard !json.isEmpty,
                  let data = json.data(using: .utf8),
                  let rootAny = try? JSONSerialization.jsonObject(with: data),
                  let root = rootAny as? [String: Any],
                  let doc = root["doc"] as? [Any] else {
                return false
            }

            return doc.contains { item in
                guard let node = item as? [String: Any] else { return false }
                return (node["type"] as? String) == "attachment"
            }
        }

        func visibleTextScore(_ attr: NSAttributedString) -> Int {
            attr.string
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: "\u{200B}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .count
        }

        let (storedProtonJSON, rtfBase64) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payloadJSON)
        if !storedProtonJSON.isEmpty {
            let protonAttr = handle.attributedStringFromProtonJSONString(storedProtonJSON)
            let preview = firstLineKey(protonAttr)
            if !rtfBase64.isEmpty && !protonJSONHasStructuredAttachment(storedProtonJSON) {
                let fallbackAttr = DBNoteRepository.decodeAttributedTextFromRTFBase64(rtfBase64)
                let protonScore = visibleTextScore(protonAttr)
                let fallbackScore = visibleTextScore(fallbackAttr)
                if fallbackScore >= max(protonScore + 40, protonScore * 2) {
                    let rebuilt = handle.exportProtonJSONString(from: fallbackAttr)
                    return (rebuilt.isEmpty ? storedProtonJSON : rebuilt, ensureNonEmptyTyped(fallbackAttr))
                }
            }
            if !preview.isEmpty || rtfBase64.isEmpty {
                return (storedProtonJSON, ensureNonEmptyTyped(protonAttr))
            }
            let attr = DBNoteRepository.decodeAttributedTextFromRTFBase64(rtfBase64)
            let fallbackPreview = firstLineKey(attr)
            if !fallbackPreview.isEmpty {
                let rebuilt = handle.exportProtonJSONString(from: attr)
                return (rebuilt.isEmpty ? storedProtonJSON : rebuilt, ensureNonEmptyTyped(attr))
            }
            return (storedProtonJSON, ensureNonEmptyTyped(protonAttr))
        }

        guard !rtfBase64.isEmpty else { return ("", makeTypedFromPlain("")) }

        let attr = DBNoteRepository.decodeAttributedTextFromRTFBase64(rtfBase64)
        let rebuilt = handle.exportProtonJSONString(from: attr)
        return (rebuilt, ensureNonEmptyTyped(attr))
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

            switch spec.match {
            case .customIDs(let ids):
                if ids.isEmpty { return [] }
                let limitCount = max(1, spec.limit)
                let trimmed = ids
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if trimmed.isEmpty { return [] }
                return Array(trimmed.prefix(limitCount))
            case .all:
                let sql = """
                SELECT b.block_id
                FROM nj_block b
                WHERE \(whereSQL)
                ORDER BY b.created_at_ms \(orderSQL)
                LIMIT ?;
                """
                print("NJ_RECON_QUERY all sql=\(sql) limit=\(spec.limit) newestFirst=\(spec.newestFirst)")
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
            default:
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
            let payloadJSON = dbLoadBlockPayloadJSON(bid)
            out.append(Row(blockID: bid, payloadJSON: payloadJSON, createdAtMs: createdAtMs))
        }

        return out
    }

    private func markerValues(for createdAtMs: Int64) -> (years: [String], months: [String]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1

        let date = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromSunday = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromSunday, to: startOfDay) ?? startOfDay

        var years: [String] = []
        var yearSeen = Set<String>()
        var months: [String] = []
        var monthSeen = Set<String>()

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: day)
            if let year = comps.year {
                let yearText = String(format: "%04d", year)
                if yearSeen.insert(yearText).inserted {
                    years.append(yearText)
                }
            }
            if let year = comps.year, let month = comps.month {
                let monthText = String(format: "%04d%02d", year, month)
                if monthSeen.insert(monthText).inserted {
                    months.append(monthText)
                }
            }
        }

        return (years, months)
    }

    private func dbLoadBlockIDsForExactTag(_ tag: String) -> [String] {
        guard let store else { return [] }
        return store.notes.db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT DISTINCT t.block_id
            FROM nj_block_tag t
            LEFT JOIN nj_block b
              ON b.block_id = t.block_id COLLATE NOCASE
            WHERE lower(t.tag)=lower(?)
              AND (b.deleted IS NULL OR b.deleted = 0)
            ORDER BY b.created_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, tag, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { out.append(s) }
                }
            }
            return out
        }
    }

    private func markerBucket(for tag: String, createdAtMs: Int64) -> MarkerBucket? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
        let comps = calendar.dateComponents([.year, .month], from: date)

        switch tag.lowercased() {
        case "#year":
            guard let year = comps.year else { return nil }
            return .year(String(format: "%04d", year))
        case "#month":
            guard let year = comps.year, let month = comps.month else { return nil }
            return .month(String(format: "%04d%02d", year, month))
        default:
            return nil
        }
    }

    private func markerRowsForWeekly(rows: [Row]) -> [MarkerLookupKey: Row] {
        guard spec.isWeekly else { return [:] }

        var wanted: [MarkerLookupKey] = []
        var seenWanted = Set<MarkerLookupKey>()
        for row in rows {
            let values = markerValues(for: row.createdAtMs)
            for year in values.years {
                let key = MarkerLookupKey(tag: "#YEAR", content: year)
                if seenWanted.insert(key).inserted {
                    wanted.append(key)
                }
            }
            for month in values.months {
                let key = MarkerLookupKey(tag: "#MONTH", content: month)
                if seenWanted.insert(key).inserted {
                    wanted.append(key)
                }
            }
        }

        if wanted.isEmpty { return [:] }

        let grouped = Dictionary(grouping: wanted, by: \.tag)
        var resolved: [MarkerLookupKey: Row] = [:]

        for (tag, keys) in grouped {
            let candidates = dbLoadBlockIDsForExactTag(tag)
            if candidates.isEmpty { continue }

            for blockID in candidates {
                let createdAtMs = dbLoadCreatedAtMs(blockID)
                guard let bucket = markerBucket(for: tag, createdAtMs: createdAtMs) else { continue }
                let match = keys.first { key in
                    switch (bucket, key.tag.lowercased(), key.content) {
                    case (.year(let year), "#year", let content):
                        return year == content
                    case (.month(let month), "#month", let content):
                        return month == content
                    default:
                        return false
                    }
                }
                guard let match else { continue }
                if resolved[match] != nil { continue }
                resolved[match] = Row(
                    blockID: blockID,
                    payloadJSON: dbLoadBlockPayloadJSON(blockID),
                    createdAtMs: createdAtMs
                )
            }
        }

        return resolved
    }

    private func buildBlockState(from row: Row, makeHandle: @escaping () -> NJProtonEditorHandle) -> NJNoteEditorContainerPersistence.BlockState {
        let noteDomain = dbLoadNoteDomainForBlockID(row.blockID)
        let mainKey = NJDomainColorConfig.normalizedSecondTierKey(noteDomain)
        if !mainKey.isEmpty {
            blockMainDomainByBlockID[row.blockID] = mainKey
        }

        let stableID = UUID(uuidString: row.blockID)
            ?? NJStableUUID("\(spec.id)|\(row.blockID)|")
        let h = makeHandle()
        h.ownerBlockUUID = stableID
        let content = blockContent(fromPayloadJSON: row.payloadJSON, handle: h)

        let tagJSON = dbLoadBlockTagJSON(row.blockID)
        let loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(row.blockID)
        let loadedPayloadHash = stablePayloadHash(content.protonJSON)
        let domainPreview = {
            let fromIndex = dbLoadDomainPreview3FromBlockTag(row.blockID)
            if !fromIndex.isEmpty { return fromIndex }
            return domainPreviewFromTagJSON(tagJSON)
        }()

        return NJNoteEditorContainerPersistence.BlockState(
            id: stableID,
            blockID: row.blockID,
            instanceID: "",
            orderKey: 0,
            createdAtMs: row.createdAtMs,
            domainPreview: domainPreview,
            attr: content.attr,
            sel: NSRange(location: 0, length: 0),
            isCollapsed: loadCollapsed(blockID: row.blockID),
            protonHandle: h,
            isDirty: false,
            loadedUpdatedAtMs: loadedUpdatedAtMs,
            loadedPayloadHash: loadedPayloadHash,
            protonJSON: content.protonJSON,
            tagJSON: tagJSON
        )
    }

    private func locallyProtectedReloadBlock(
        existing: NJNoteEditorContainerPersistence.BlockState?,
        incoming: NJNoteEditorContainerPersistence.BlockState
    ) -> NJNoteEditorContainerPersistence.BlockState {
        guard var existing else { return incoming }

        let isActivelyLocal = existing.isDirty
            || existing.protonHandle.isEditing
            || existing.verifiedLocalEditAtMs > 0
        let hasNewerLocalSnapshot = existing.loadedUpdatedAtMs > incoming.loadedUpdatedAtMs
            && !existing.loadedPayloadHash.isEmpty
            && existing.loadedPayloadHash != incoming.loadedPayloadHash
        let wouldDropExistingContent = !existing.protonJSON.isEmpty && incoming.protonJSON.isEmpty

        guard isActivelyLocal || hasNewerLocalSnapshot || wouldDropExistingContent else {
            return incoming
        }

        existing.createdAtMs = incoming.createdAtMs
        existing.domainPreview = incoming.domainPreview
        if !incoming.tagJSON.isEmpty {
            existing.tagJSON = incoming.tagJSON
        }
        existing.isCollapsed = incoming.isCollapsed

        print(
            "NJ_RECON_RELOAD_PRESERVE_LOCAL block_id=\(existing.blockID) " +
            "dirty=\(existing.isDirty ? 1 : 0) editing=\(existing.protonHandle.isEditing ? 1 : 0) " +
            "verified=\(existing.verifiedLocalEditAtMs) local_updated=\(existing.loadedUpdatedAtMs) " +
            "incoming_updated=\(incoming.loadedUpdatedAtMs)"
        )

        return existing
    }

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
        blockMainDomainByBlockID = [:]
        hasPendingRemoteRefresh = false

        let rows = dbLoadRows()
        if rows.isEmpty {
            blocks = []
            focusedBlockID = nil
            return
        }

        var out: [NJNoteEditorContainerPersistence.BlockState] = []
        out.reserveCapacity(rows.count)
        if spec.isWeekly {
            let weeklyRows = rows.sorted { $0.createdAtMs < $1.createdAtMs }
            let markerRows = markerRowsForWeekly(rows: weeklyRows)
            var seenYears = Set<String>()
            var seenMonths = Set<String>()
            for row in weeklyRows {
                let values = markerValues(for: row.createdAtMs)
                for year in values.years where !seenYears.contains(year) {
                    seenYears.insert(year)
                    let key = MarkerLookupKey(tag: "#YEAR", content: year)
                    if let marker = markerRows[key] {
                        out.append(buildBlockState(from: marker, makeHandle: makeHandle))
                    }
                }
                for month in values.months where !seenMonths.contains(month) {
                    seenMonths.insert(month)
                    let key = MarkerLookupKey(tag: "#MONTH", content: month)
                    if let marker = markerRows[key] {
                        out.append(buildBlockState(from: marker, makeHandle: makeHandle))
                    }
                }
                out.append(buildBlockState(from: row, makeHandle: makeHandle))
            }
        } else {
            for row in rows {
                out.append(buildBlockState(from: row, makeHandle: makeHandle))
            }
        }

        if !spec.isWeekly {
            if case .all = spec.match {
                out.sort { spec.newestFirst ? ($0.createdAtMs > $1.createdAtMs) : ($0.createdAtMs < $1.createdAtMs) }
            } else if case .customIDs = spec.match {
                out.sort { spec.newestFirst ? ($0.createdAtMs > $1.createdAtMs) : ($0.createdAtMs < $1.createdAtMs) }
            } else {
                // Sort by first line (case-insensitive), then by created time (newest first).
                out.sort {
                    let a = firstLineKey($0.attr).lowercased()
                    let b = firstLineKey($1.attr).lowercased()
                    if a != b { return a < b }
                    return $0.createdAtMs > $1.createdAtMs
                }
            }
        }

        var priorByBlockID: [String: NJNoteEditorContainerPersistence.BlockState] = [:]
        for prior in blocks where priorByBlockID[prior.blockID] == nil {
            priorByBlockID[prior.blockID] = prior
        }
        out = out.map { incoming in
            locallyProtectedReloadBlock(existing: priorByBlockID[incoming.blockID], incoming: incoming)
        }

        blocks = out
        assert(Set(blocks.map { $0.id }).count == blocks.count)
        let priorFocusedID = focusedBlockID
        focusedBlockID = blocks.contains(where: { $0.id == priorFocusedID }) ? priorFocusedID : blocks.first?.id
        loadedContentWatermarkMs = currentContentWatermarkMs()
        loadedContentSignature = currentContentSignature()
        for b in blocks where !b.protonJSON.isEmpty && !b.isDirty && !b.protonHandle.isEditing {
            b.protonHandle.hydrateFromProtonJSONString(b.protonJSON)
        }
    }

    private func makeTypedFromPlain(_ s: String) -> NSAttributedString {
        let cleaned = s.isEmpty ? "\u{200B}" : s
        return NSAttributedString(string: cleaned)
    }

    private func ensureNonEmptyTyped(_ attr: NSAttributedString) -> NSAttributedString {
        hasMeaningfulAttributedContent(attr) ? attr : makeTypedFromPlain("")
    }

    private func firstLineKey(_ attr: NSAttributedString) -> String {
        let s = attr.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        return s.split(whereSeparator: \.isNewline).first.map { String($0) } ?? ""
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

    private func blockAttachmentCount(in attr: NSAttributedString) -> Int {
        if attr.length == 0 { return 0 }
        var count = 0
        let r = NSRange(location: 0, length: attr.length)
        attr.enumerateAttribute(.attachment, in: r, options: []) { value, _, _ in
            guard let att = value as? Attachment, att.isBlockType else { return }
            count += 1
        }
        return count
    }

    private func objectReplacementCount(in attr: NSAttributedString) -> Int {
        attr.string.reduce(0) { $0 + ($1 == "\u{FFFC}" ? 1 : 0) }
    }

    private func protonPhotoNodeCount(_ protonJSON: String) -> Int {
        guard !protonJSON.isEmpty else { return 0 }
        return protonJSON.components(separatedBy: "\"kind\":\"photo\"").count - 1
    }

    private func protonAttachmentNodeCount(_ protonJSON: String) -> Int {
        guard !protonJSON.isEmpty,
              let data = protonJSON.data(using: .utf8),
              let rootAny = try? JSONSerialization.jsonObject(with: data),
              let root = rootAny as? [String: Any],
              let doc = root["doc"] as? [Any] else {
            return 0
        }

        return doc.reduce(0) { count, item in
            guard let node = item as? [String: Any],
                  (node["type"] as? String) == "attachment" else {
                return count
            }
            return count + 1
        }
    }

    private func shouldProtectStructuredAttachmentDowngrade(
        existingProtonJSON: String,
        candidateProtonJSON: String,
        sourceAttr: NSAttributedString
    ) -> Bool {
        let existingCount = protonAttachmentNodeCount(existingProtonJSON)
        guard existingCount > 0 else { return false }

        let candidateCount = protonAttachmentNodeCount(candidateProtonJSON)
        guard candidateCount < existingCount else { return false }

        let liveBlockAttachments = blockAttachmentCount(in: sourceAttr)
        let orphanObjects = objectReplacementCount(in: sourceAttr)
        guard orphanObjects > liveBlockAttachments else { return false }

        print("NJ_BLOCK_PROTECT_ATTACHMENT_DOWNGRADE existing=\(existingCount) candidate=\(candidateCount) live=\(liveBlockAttachments) orphan=\(orphanObjects)")
        return true
    }

    private func hasMeaningfulAttributedContent(_ attr: NSAttributedString) -> Bool {
        if extractPhotoAttachments(from: attr).isEmpty == false { return true }
        let text = attr.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty
    }

    private func stabilizedProtonJSON(
        exported: String,
        fallback: String,
        sourceAttr: NSAttributedString
    ) -> String {
        func normalize(_ json: String) -> String {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let rootAny = try? JSONSerialization.jsonObject(with: data, options: []),
                  let root = rootAny as? [String: Any] else {
                return json
            }

            if let schema = root["schema"] as? String,
               (schema == "nj_proton_doc_v1" || schema == "nj_proton_doc_v2"),
               let doc = root["doc"] as? [Any],
               JSONSerialization.isValidJSONObject(["schema": "nj_proton_doc_v2", "doc": doc]),
               let normalizedData = try? JSONSerialization.data(withJSONObject: ["schema": "nj_proton_doc_v2", "doc": doc], options: []),
               let normalized = String(data: normalizedData, encoding: .utf8) {
                return normalized
            }

            guard root["schema"] == nil,
                  let doc = root["doc"] as? [Any] else {
                return json
            }

            guard JSONSerialization.isValidJSONObject(["schema": "nj_proton_doc_v2", "doc": doc]),
                  let normalizedData = try? JSONSerialization.data(withJSONObject: ["schema": "nj_proton_doc_v2", "doc": doc], options: []),
                  let normalized = String(data: normalizedData, encoding: .utf8) else {
                return json
            }
            return normalized
        }

        let normalizedExported = normalize(exported)
        if !normalizedExported.isEmpty { return normalizedExported }
        if hasMeaningfulAttributedContent(sourceAttr) { return normalize(fallback) }
        return normalizedExported
    }

    func hydrateProton(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        guard !blocks[i].isDirty else { return }
        guard !blocks[i].protonHandle.isEditing else { return }
        let json = blocks[i].protonJSON
        if json.isEmpty { return }
        blocks[i].protonHandle.hydrateFromProtonJSONString(json)
    }

    func markDirty(_ id: UUID, source: String = "unknown") {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        print("NJ_BLOCK_MARK_DIRTY source=\(source) block_id=\(blocks[i].blockID) id=\(id.uuidString)")
        if !blocks[i].isDirty { blocks[i].isDirty = true }
    }

    func updateBlockCreatedAt(_ id: UUID, createdAtMs: Int64) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }

        let normalized = max(1, createdAtMs)
        let nowMs = DBNoteRepository.nowMs()
        let blockID = blocks[i].blockID

        store.notes.updateBlockCreatedAtMs(blockID: blockID, createdAtMs: normalized, nowMs: nowMs)

        var arr = blocks
        arr[i].createdAtMs = normalized
        blocks = arr
    }

    func scheduleCommit(_ id: UUID, debounce: Double = 0.9, source: String = "unknown") {
        commitWork[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitBlockNow(id) }
        commitWork[id] = w
        if let i = blocks.firstIndex(where: { $0.id == id }) {
            print("NJ_BLOCK_SCHEDULE_COMMIT source=\(source) block_id=\(blocks[i].blockID) id=\(id.uuidString) debounce=\(debounce)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    func forceEndEditingAndCommitNow(_ id: UUID) {
        commitWork[id]?.cancel()
        commitWork[id] = nil
        NJCollapsibleAttachmentView.flushActiveBodyEditing()
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let shouldCommit = blocks[i].isDirty || blocks[i].verifiedLocalEditAtMs > 0
        blocks[i].protonHandle.isEditing = false
        guard shouldCommit else { return }
        commitBlockNow(id, force: true)
    }

    func forceEndEditingAndCommitAllDirtyNow() {
        NJCollapsibleAttachmentView.flushActiveBodyEditing()

        let commitIDs = blocks
            .filter { $0.isDirty || $0.verifiedLocalEditAtMs > 0 }
            .map(\.id)

        for id in commitIDs {
            commitWork[id]?.cancel()
            commitWork[id] = nil
            if let i = blocks.firstIndex(where: { $0.id == id }) {
                blocks[i].protonHandle.isEditing = false
            }
        }

        for id in commitIDs {
            commitBlockNow(id, force: true)
        }
    }

    func deleteBlock(_ id: UUID) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let b = blocks[i]

        let now = DBNoteRepository.nowMs()
        store.notes.markBlockDeleted(blockID: b.blockID)
        for att in store.notes.listAttachments(blockID: b.blockID) {
            store.notes.markAttachmentDeleted(attachmentID: att.attachmentID, nowMs: now)
        }

        blocks.remove(at: i)
        if focusedBlockID == id {
            if blocks.indices.contains(i) {
                focusedBlockID = blocks[i].id
            } else {
                focusedBlockID = blocks.last?.id
            }
        }
    }

    func commitBlockNow(_ id: UUID) {
        commitBlockNow(id, force: false)
    }

    func commitBlockNow(_ id: UUID, force: Bool = false) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty && blocks[i].verifiedLocalEditAtMs <= 0 { return }

        if !force && shouldDeferCommitWhileFocused(id: id, index: i) {
            scheduleCommit(id, debounce: 0.6, source: "commitBlockNow.deferEditing")
            return
        }

        if shouldAbortForRemoteEditorLease(index: i) {
            return
        }

        var b = blocks[i]
        guard let editor = b.protonHandle.editor else {
            var protonJSONToSave = b.protonJSON
            if protonJSONToSave.isEmpty && b.attr.length > 0 {
                let rebuilt = b.protonHandle.exportProtonJSONString(from: b.attr)
                if !rebuilt.isEmpty {
                    protonJSONToSave = rebuilt
                    b.protonJSON = rebuilt
                    blocks[i].protonJSON = rebuilt
                }
            }
            if protonJSONToSave.isEmpty {
                b.isDirty = false
                blocks[i] = b
                return
            }
            if shouldProtectStructuredAttachmentDowngrade(
                existingProtonJSON: b.protonJSON,
                candidateProtonJSON: protonJSONToSave,
                sourceAttr: b.attr
            ) {
                b.isDirty = false
                blocks[i] = b
                return
            }
            if shouldAbortStaleEditorSave(index: i, candidateProtonJSON: protonJSONToSave) {
                return
            }
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: protonJSONToSave,
                tagJSON: b.tagJSON
            )
            b.loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)
            b.loadedPayloadHash = stablePayloadHash(protonJSONToSave)
            b.isDirty = false
            b.verifiedLocalEditAtMs = 0
            markLocalContentCommitted()
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
        let views = extractPhotoAttachments(from: originalAttr)
        let sourceAttrForProton = tagRes?.cleaned ?? originalAttr
        var protonJSON = stabilizedProtonJSON(
            exported: b.protonHandle.exportProtonJSONString(from: sourceAttrForProton),
            fallback: b.protonJSON,
            sourceAttr: sourceAttrForProton
        )
        if !views.isEmpty && protonPhotoNodeCount(protonJSON) < views.count {
            protonJSON = stabilizedProtonJSON(
                exported: b.protonHandle.exportProtonJSONString(from: originalAttr),
                fallback: protonJSON.isEmpty ? b.protonJSON : protonJSON,
                sourceAttr: originalAttr
            )
        }
        if shouldProtectStructuredAttachmentDowngrade(
            existingProtonJSON: b.protonJSON,
            candidateProtonJSON: protonJSON,
            sourceAttr: originalAttr
        ) {
            b.isDirty = false
            blocks[i] = b
            return
        }

        guard !protonJSON.isEmpty else {
            b.isDirty = false
            blocks[i] = b
            return
        }

        b.protonJSON = protonJSON
        blocks[i].protonJSON = protonJSON
        if shouldAbortStaleEditorSave(index: i, candidateProtonJSON: protonJSON) {
            return
        }

        let nowMs = DBNoteRepository.nowMs()
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

        b.loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)
        b.loadedPayloadHash = stablePayloadHash(protonJSON)
        b.isDirty = false
        b.verifiedLocalEditAtMs = 0
        markLocalContentCommitted()
        blocks[i] = b

    }

    private func reloadBlockFromStore(at index: Int) {
        guard blocks.indices.contains(index) else { return }

        var b = blocks[index]
        if b.isDirty || b.protonHandle.isEditing {
            markPendingRemoteRefresh()
            return
        }

        let content = blockContent(fromPayloadJSON: dbLoadBlockPayloadJSON(b.blockID), handle: b.protonHandle)
        guard !content.protonJSON.isEmpty else {
            markPendingRemoteRefresh()
            return
        }

        b.protonJSON = content.protonJSON
        b.tagJSON = dbLoadBlockTagJSON(b.blockID)
        let fromIndex = dbLoadDomainPreview3FromBlockTag(b.blockID)
        b.domainPreview = fromIndex.isEmpty ? domainPreviewFromTagJSON(b.tagJSON) : fromIndex
        b.attr = content.attr
        b.loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)
        b.loadedPayloadHash = stablePayloadHash(content.protonJSON)
        b.isDirty = false
        b.verifiedLocalEditAtMs = 0
        blocks[index] = b
        blocks[index].protonHandle.hydrateFromProtonJSONString(content.protonJSON)
        markLocalContentCommitted()
    }

    private func currentContentWatermarkMs() -> Int64 {
        guard let store else { return 0 }
        return store.notes.db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT COALESCE(MAX(updated_at_ms), 0)
            FROM nj_block
            WHERE deleted = 0
              AND block_id IN (
                SELECT DISTINCT block_id
                FROM nj_note_block
                WHERE deleted = 0
              );
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return 0
        }
    }
}
