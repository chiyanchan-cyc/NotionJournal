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

final class NJNoteEditorContainerPersistence: ObservableObject {

    struct BlockState: Identifiable, Equatable {
        let id: UUID
        var blockID: String
        var instanceID: String
        var orderKey: Double
        var createdAtMs: Int64
        var cardRowID: String
        var cardStatus: String
        var cardPriority: String
        var cardCategory: String
        var cardArea: String
        var cardContext: String
        var cardTitle: String
        var domainPreview: String
        var goalPreview: String
        var attr: NSAttributedString
        var sel: NSRange
        var isCollapsed: Bool
        var protonHandle: NJProtonEditorHandle
        var isDirty: Bool
        var loadedUpdatedAtMs: Int64
        var loadedPayloadHash: String
        var protonJSON: String
        var tagJSON: String
        var clipPDFRel: String
        var isChecked: Bool
        var verifiedLocalEditAtMs: Int64

        init(
            id: UUID = UUID(),
            blockID: String,
            instanceID: String,
            orderKey: Double,
            createdAtMs: Int64 = 0,
            cardRowID: String = "",
            cardStatus: String = "",
            cardPriority: String = "",
            cardCategory: String = "",
            cardArea: String = "",
            cardContext: String = "",
            cardTitle: String = "",
            domainPreview: String = "",
            goalPreview: String = "",
            attr: NSAttributedString,
            sel: NSRange = NSRange(location: 0, length: 0),
            isCollapsed: Bool = false,
            protonHandle: NJProtonEditorHandle = NJProtonEditorHandle(),
            isDirty: Bool = false,
            loadedUpdatedAtMs: Int64 = 0,
            loadedPayloadHash: String = "",
            protonJSON: String = "",
            tagJSON: String = "",
            clipPDFRel: String = "",
            isChecked: Bool = false,
            verifiedLocalEditAtMs: Int64 = 0
        ) {
            self.id = id
            self.blockID = blockID
            self.instanceID = instanceID
            self.orderKey = orderKey
            self.createdAtMs = createdAtMs
            self.cardRowID = cardRowID
            self.cardStatus = cardStatus
            self.cardPriority = cardPriority
            self.cardCategory = cardCategory
            self.cardArea = cardArea
            self.cardContext = cardContext
            self.cardTitle = cardTitle
            self.domainPreview = domainPreview
            self.goalPreview = goalPreview
            self.attr = attr
            self.sel = sel
            self.isCollapsed = isCollapsed
            self.protonHandle = protonHandle
            self.isDirty = isDirty
            self.loadedUpdatedAtMs = loadedUpdatedAtMs
            self.loadedPayloadHash = loadedPayloadHash
            self.protonJSON = protonJSON
            self.tagJSON = tagJSON
            self.clipPDFRel = clipPDFRel
            self.isChecked = isChecked
            self.verifiedLocalEditAtMs = verifiedLocalEditAtMs
        }

        static func == (lhs: BlockState, rhs: BlockState) -> Bool {
            lhs.id == rhs.id &&
            lhs.blockID == rhs.blockID &&
            lhs.instanceID == rhs.instanceID &&
            lhs.orderKey == rhs.orderKey &&
            lhs.createdAtMs == rhs.createdAtMs &&
            lhs.cardRowID == rhs.cardRowID &&
            lhs.cardStatus == rhs.cardStatus &&
            lhs.cardPriority == rhs.cardPriority &&
            lhs.cardCategory == rhs.cardCategory &&
            lhs.cardArea == rhs.cardArea &&
            lhs.cardContext == rhs.cardContext &&
            lhs.cardTitle == rhs.cardTitle &&
            lhs.domainPreview == rhs.domainPreview &&
            lhs.goalPreview == rhs.goalPreview &&
            lhs.attr.isEqual(to: rhs.attr) &&
            NSEqualRanges(lhs.sel, rhs.sel) &&
            lhs.isCollapsed == rhs.isCollapsed &&
            lhs.isDirty == rhs.isDirty &&
            lhs.loadedUpdatedAtMs == rhs.loadedUpdatedAtMs &&
            lhs.loadedPayloadHash == rhs.loadedPayloadHash &&
            lhs.protonJSON == rhs.protonJSON &&
            lhs.tagJSON == rhs.tagJSON &&
            lhs.clipPDFRel == rhs.clipPDFRel &&
            lhs.isChecked == rhs.isChecked &&
            lhs.verifiedLocalEditAtMs == rhs.verifiedLocalEditAtMs
        }
    }

    @Published var title: String = ""
    @Published var tab: String = ""
    @Published var noteType: NJNoteType = .note
    @Published var dominanceMode: NJNoteDominanceMode = .block
    @Published var isChecklist: Bool = false
    @Published var cardID: String = ""
    @Published var cardCategory: String = ""
    @Published var cardArea: String = ""
    @Published var cardContext: String = ""
    @Published var cardStatus: String = ""
    @Published var cardPriority: String = ""
    @Published var blocks: [BlockState] = []
    @Published var focusedBlockID: UUID? = nil
    @Published private(set) var hasPendingRemoteRefresh: Bool = false

    private var store: AppStore? = nil
    private var noteID: NJNoteID? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var noteMetaCommitWork: DispatchWorkItem? = nil
    private var didConfigure = false
    private var loadedContentWatermarkMs: Int64 = 0
    private var loadedContentSignature: String = ""
    @Published private(set) var hasPendingNoteMetaChanges: Bool = false
    private let editorLeaseDurationMs: Int64 = 120_000

    init() { }

    private var localEditorDeviceID: String {
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? UIDevice.current.identifierForVendor?.uuidString ?? "unknown" : host
    }

    private func extractClipPDFRelFromPayload(_ payloadJSON: String) -> String {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payloadJSON),
           let data = normalized.data(using: .utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data) {
            if let clip = try? v1.clipData(), let p = clip.pdf_path, !p.isEmpty {
                return p.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let audio = try? v1.audioData(), let p = audio.pdf_path, !p.isEmpty {
                return p.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let summary = try? v1.chatGPTSummaryData(),
               let p = summary.source_pdf_path,
               !p.isEmpty {
                return p.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = payloadJSON.data(using: .utf8) else { return "" }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        guard let sections = root["sections"] as? [String: Any] else { return "" }

        if let clip = sections["clip"] as? [String: Any],
           let clipData = clip["data"] as? [String: Any],
           let pdfPath = (clipData["pdf_path"] as? String) ?? (clipData["PDF_Path"] as? String) {
            return pdfPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let audio = sections["audio"] as? [String: Any],
           let audioData = audio["data"] as? [String: Any],
           let pdfPath = (audioData["pdf_path"] as? String) ?? (audioData["PDF_Path"] as? String) {
            return pdfPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let summary = sections["chatgpt_summary"] as? [String: Any],
           let summaryData = summary["data"] as? [String: Any],
           let pdfPath = summaryData["source_pdf_path"] as? String {
            return pdfPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    private func stablePayloadHash(_ protonJSON: String) -> String {
        guard !protonJSON.isEmpty else { return "" }
        let data = Data(protonJSON.utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func stableContentSignature(parts: [String]) -> String {
        let joined = parts.joined(separator: "\u{1F}")
        let data = Data(joined.utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func currentContentSignature() -> String {
        guard let store, let noteID else { return "" }

        let note = store.notes.getNote(noteID)
        let rows = store.notes.loadAllTextBlocksRTFWithPlacement(noteID: noteID.raw)
        var parts: [String] = [
            "note_id=\(noteID.raw)",
            "title=\(note?.title ?? "")",
            "tab=\(note?.tabDomain ?? "")",
            "note_type=\(note?.noteType.rawValue ?? "")",
            "dominance=\(note?.dominanceMode.rawValue ?? "")",
            "is_checklist=\((note?.isChecklist ?? 0) > 0 ? 1 : 0)",
            "card_id=\(note?.cardID ?? "")",
            "card_category=\(note?.cardCategory ?? "")",
            "card_area=\(note?.cardArea ?? "")",
            "card_context=\(note?.cardContext ?? "")",
            "card_status=\(note?.cardStatus ?? "")",
            "card_priority=\(note?.cardPriority ?? "")"
        ]
        parts.reserveCapacity(parts.count + rows.count * 5)

        for row in rows {
            parts.append("block_id=\(row.blockID)")
            parts.append("instance_id=\(row.instanceID)")
            parts.append("order_key=\(row.orderKey)")
            parts.append("is_checked=\(row.isChecked ? 1 : 0)")
            parts.append("card_row_id=\(row.cardRowID)")
            parts.append("card_status=\(row.cardStatus)")
            parts.append("card_priority=\(row.cardPriority)")
            parts.append("card_category=\(row.cardCategory)")
            parts.append("card_area=\(row.cardArea)")
            parts.append("card_context=\(row.cardContext)")
            parts.append("card_title=\(row.cardTitle)")
            parts.append("payload=\(row.payloadJSON)")
        }

        return stableContentSignature(parts: parts)
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

    private func visibleTextScore(_ attr: NSAttributedString) -> Int {
        let text = attr.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count
    }

    private func shouldPreferRTFFallback(protonAttr: NSAttributedString, rtfAttr: NSAttributedString) -> Bool {
        if !hasMeaningfulAttributedContent(rtfAttr) { return false }
        if !hasMeaningfulAttributedContent(protonAttr) { return true }

        let protonScore = visibleTextScore(protonAttr)
        let rtfScore = visibleTextScore(rtfAttr)
        guard rtfScore > 0 else { return false }

        // Older weekly blocks can carry a stale Proton projection beside the
        // full RTF source. Use RTF when it is clearly the richer representation.
        return rtfScore >= max(protonScore + 40, protonScore * 2)
    }

    private func shouldAllowRTFFallback(for protonJSON: String) -> Bool {
        protonAttachmentNodeCount(protonJSON) == 0
    }

    private func isPlaceholderPayload(_ payloadJSON: String) -> Bool {
        let trimmed = payloadJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "{}"
    }

    private func dbLoadBlockPayloadJSON(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = """
            SELECT payload_json
            FROM nj_block
            WHERE block_id = ? AND deleted = 0
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let c = sqlite3_column_text(stmt, 0) {
                out = String(cString: c)
            }
            return out
        }
    }

    private func shouldProtectPlaceholderShell(blockID: String, persistedProtonJSON: String, attr: NSAttributedString) -> Bool {
        guard persistedProtonJSON.isEmpty else { return false }
        guard !hasMeaningfulAttributedContent(attr) else { return false }
        return isPlaceholderPayload(dbLoadBlockPayloadJSON(blockID))
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

    private func dbLoadClipPDFRel(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = """
            SELECT payload_json
            FROM nj_block
            WHERE block_id = ? AND deleted = 0
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let payload = String(cString: c)
                    out = extractClipPDFRelFromPayload(payload)
                }
            }

            return out
        }
    }

    private func dbLoadBlockProtonJSON(_ blockID: String) -> String {
        guard let store else { return "" }
        let payloadJSON = store.notes.db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = """
            SELECT payload_json
            FROM nj_block
            WHERE block_id = ? AND deleted = 0
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let c = sqlite3_column_text(stmt, 0) {
                out = String(cString: c)
            }
            return out
        }
        guard !payloadJSON.isEmpty else { return "" }

        if let normalized = try? NJPayloadConverterV1.convertToV1(payloadJSON),
           let data = normalized.data(using: String.Encoding.utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
           let proton = try? v1.proton1Data() {
            return proton.proton_json
        }

        guard let data = payloadJSON.data(using: String.Encoding.utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        if let sections = obj["sections"] as? [String: Any],
           let proton1 = sections["proton1"] as? [String: Any],
           let dataNode = proton1["data"] as? [String: Any] {
            return dataNode["proton_json"] as? String ?? ""
        }
        return obj["proton_json"] as? String ?? ""
    }

    private func decodeStoredRTF(_ data: Data) -> NSAttributedString? {
        if let rtfd = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) {
            return rtfd
        }

        if let rtf = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return rtf
        }

        return nil
    }

    func configure(store: AppStore, noteID: NJNoteID) {
        if didConfigure { return }
        self.store = store
        self.noteID = noteID
        self.didConfigure = true
    }

    private func domainPreviewFromTagJSON(_ tagJSON: String) -> String {
        if tagJSON.isEmpty { return "" }
        if let data = tagJSON.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.joined(separator: ", ")
        }
        return ""
    }

    private func collapseKey(blockID: String) -> String {
        let n = noteID?.raw ?? "no_note"
        return "nj.note.collapse.\(n).\(blockID)"
    }

    func loadCollapsed(blockID: String) -> Bool {
        UserDefaults.standard.bool(forKey: collapseKey(blockID: blockID))
    }

    func saveCollapsed(blockID: String, collapsed: Bool) {
        UserDefaults.standard.set(collapsed, forKey: collapseKey(blockID: blockID))
    }

    private func dbLoadBlockCreatedAtMs(_ blockID: String) -> Int64 {
        guard let store else { return 0 }
        return store.notes.db.withDB { dbp in
            var out: Int64 = 0
            var stmt: OpaquePointer?
            let sql = "SELECT created_at_ms FROM nj_block WHERE block_id = ? LIMIT 1;"
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                out = sqlite3_column_int64(stmt, 0)
            }
            return out
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

    private func dbLoadGoalPreview(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.goalTable.loadGoalPreviewForOriginBlock(blockID: blockID)
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
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_TAG_PREVIEW SQL_PREP_FAIL rc=\(rc0) msg=\(msg)")
                return ""
            }
            defer { sqlite3_finalize(stmt) }

            let b0 = sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if b0 != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_TAG_PREVIEW SQL_BIND_FAIL b0=\(b0) msg=\(msg)")
                return ""
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { tags.append(s) }
                }
            }

            let out = tags.joined(separator: ", ")
            if out.isEmpty {
                print("NJ_TAG_PREVIEW EMPTY block_id=\(blockID)")
            }
            return out
        }
    }
    
    private func dbDebugAttachments(_ blockID: String) {
        guard let store else { return }
        store.notes.db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT name
            FROM sqlite_master
            WHERE type='table' AND name LIKE '%attach%';
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            var tables: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { tables.append(String(cString: c)) }
            }

            print("NJ_ATTACH_DEBUG tables=\(tables) block_id=\(blockID)")

            for t in tables {
                var st2: OpaquePointer?
                let q = "SELECT * FROM \(t) WHERE block_id = ? LIMIT 5;"
                let rc = sqlite3_prepare_v2(dbp, q, -1, &st2, nil)
                if rc != SQLITE_OK { continue }
                defer { sqlite3_finalize(st2) }
                sqlite3_bind_text(st2, 1, blockID, -1, SQLITE_TRANSIENT)

                let colCount = sqlite3_column_count(st2)
                var colNames: [String] = []
                colNames.reserveCapacity(Int(colCount))
                for i in 0..<colCount {
                    if let n = sqlite3_column_name(st2, i) { colNames.append(String(cString: n)) }
                }

                var rowN = 0
                while sqlite3_step(st2) == SQLITE_ROW {
                    rowN += 1
                    var parts: [String] = []
                    for i in 0..<colCount {
                        let name = colNames[Int(i)]
                        if let c = sqlite3_column_text(st2, i) {
                            parts.append("\(name)=\(String(cString: c))")
                        } else {
                            let v = sqlite3_column_int64(st2, i)
                            parts.append("\(name)=\(v)")
                        }
                    }
                    print("NJ_ATTACH_DEBUG \(t) row\(rowN): " + parts.joined(separator: " | "))
                }

                if rowN == 0 {
                    print("NJ_ATTACH_DEBUG \(t) no rows for block_id")
                }
            }
        }
    }

    private func locallyProtectedReloadBlock(existing: BlockState?, incoming: BlockState) -> BlockState {
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

        existing.instanceID = incoming.instanceID.isEmpty ? existing.instanceID : incoming.instanceID
        existing.orderKey = incoming.orderKey
        existing.createdAtMs = incoming.createdAtMs
        existing.cardRowID = incoming.cardRowID
        existing.cardStatus = incoming.cardStatus
        existing.cardPriority = incoming.cardPriority
        existing.cardCategory = incoming.cardCategory
        existing.cardArea = incoming.cardArea
        existing.cardContext = incoming.cardContext
        existing.cardTitle = incoming.cardTitle
        existing.domainPreview = incoming.domainPreview
        existing.goalPreview = incoming.goalPreview
        existing.isCollapsed = incoming.isCollapsed
        if !incoming.tagJSON.isEmpty {
            existing.tagJSON = incoming.tagJSON
        }
        existing.clipPDFRel = incoming.clipPDFRel
        existing.isChecked = incoming.isChecked

        print(
            "NJ_NOTE_RELOAD_PRESERVE_LOCAL block_id=\(existing.blockID) " +
            "dirty=\(existing.isDirty ? 1 : 0) editing=\(existing.protonHandle.isEditing ? 1 : 0) " +
            "verified=\(existing.verifiedLocalEditAtMs) local_updated=\(existing.loadedUpdatedAtMs) " +
            "incoming_updated=\(incoming.loadedUpdatedAtMs)"
        )

        return existing
    }

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
            hasPendingRemoteRefresh = false
            guard let store, let noteID else { return }
            let priorBlocks = blocks
            let priorFocusedID = focusedBlockID

            if let note = store.notes.getNote(noteID) {
                title = note.title
                tab = note.tabDomain
                noteType = note.noteType
                dominanceMode = note.dominanceMode
                isChecklist = note.isChecklist > 0
                cardID = note.cardID
                cardCategory = note.cardCategory
                cardArea = note.cardArea
                cardContext = note.cardContext
                cardStatus = note.noteType == .card ? (note.cardStatus.isEmpty ? "Pending" : note.cardStatus) : note.cardStatus
                cardPriority = note.noteType == .card ? (note.cardPriority.isEmpty ? "Medium" : note.cardPriority) : note.cardPriority
            } else {
                let now = DBNoteRepository.nowMs()
                let note = NJNote(
                    id: noteID,
                    createdAtMs: now,
                    updatedAtMs: now,
                    notebook: "default",
                    tabDomain: "default",
                    title: "Untitled",
                    rtfData: DBNoteRepository.emptyRTF(),
                    deleted: 0
                )
                store.notes.upsertNote(note)
                title = note.title
                tab = note.tabDomain
                noteType = note.noteType
                dominanceMode = note.dominanceMode
                isChecklist = note.isChecklist > 0
                cardID = note.cardID
                cardCategory = note.cardCategory
                cardArea = note.cardArea
                cardContext = note.cardContext
                cardStatus = note.noteType == .card ? (note.cardStatus.isEmpty ? "Pending" : note.cardStatus) : note.cardStatus
                cardPriority = note.noteType == .card ? (note.cardPriority.isEmpty ? "Medium" : note.cardPriority) : note.cardPriority
            }

            let rows = store.notes.loadAllTextBlocksRTFWithPlacement(noteID: noteID.raw)

            if rows.isEmpty {
                let h = makeHandle()

                let newBlockID = UUID().uuidString
                let id = UUID(uuidString: newBlockID)
                    ?? NJStableUUID("\(noteID.raw)|\(newBlockID)|")
                h.ownerBlockUUID = id
                let inheritedTagJSON: String = {
                    let t = tab.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { return "" }
                    if let data = try? JSONSerialization.data(withJSONObject: [t]),
                       let s = String(data: data, encoding: .utf8) {
                        return s
                    }
                    return ""
                }()

                let b = BlockState(
                    id: id,
                    blockID: newBlockID,
                    instanceID: "",
                    orderKey: 1000,
                    createdAtMs: DBNoteRepository.nowMs(),
                    cardRowID: noteType == .card ? store.notes.nextCardRowID(noteID: noteID.raw) : "",
                    cardStatus: noteType == .card ? "Pending" : "",
                    cardPriority: noteType == .card ? "Medium" : "",
                    domainPreview: "",
                    goalPreview: "",
                    attr: makeEmptyBlockAttr(),
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: loadCollapsed(blockID: newBlockID),
                    protonHandle: h,
                    isDirty: false,
                    loadedUpdatedAtMs: 0,
                    loadedPayloadHash: "",
                    protonJSON: "",
                    tagJSON: inheritedTagJSON,
                    isChecked: false
                )

                blocks = [b]
                return
            }

            var out: [BlockState] = []
            out.reserveCapacity(rows.count)
            let priorByID: [UUID: BlockState] = Dictionary(uniqueKeysWithValues: priorBlocks.map { ($0.id, $0) })

            for row in rows {
                let stableID = UUID(uuidString: row.instanceID)
                    ?? UUID(uuidString: row.blockID)
                    ?? NJStableUUID("\(noteID.raw)|\(row.blockID)|\(row.instanceID)")
                let existing = priorByID[stableID]
                let h = existing?.protonHandle ?? makeHandle()
                h.ownerBlockUUID = stableID

                var protonJSON = row.protonJSON

                let attr: NSAttributedString = {
                    if !protonJSON.isEmpty {
                        let decoded = h.attributedStringFromProtonJSONString(protonJSON)
                        let cleaned = stripZWSP(decoded)
                        if let rtf = decodeStoredRTF(row.rtfData) {
                            let fallback = stripZWSP(rtf)
                            if shouldAllowRTFFallback(for: protonJSON),
                               shouldPreferRTFFallback(protonAttr: cleaned, rtfAttr: fallback) {
                                let rebuilt = h.exportProtonJSONString(from: fallback)
                                if !rebuilt.isEmpty {
                                    protonJSON = rebuilt
                                }
                                return ensureNonEmptyTyped(fallback)
                            }
                        }
                        if hasMeaningfulAttributedContent(cleaned) {
                            return ensureNonEmptyTyped(cleaned)
                        }
                        return ensureNonEmptyTyped(cleaned)
                    }
                    let s = decodeStoredRTF(row.rtfData) ?? makeEmptyBlockAttr()
                    return ensureNonEmptyTyped(stripZWSP(s))
                }()

                let createdAtMs = dbLoadBlockCreatedAtMs(row.blockID)
                let tagJSON = dbLoadBlockTagJSON(row.blockID)
                let loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(row.blockID)
                let loadedPayloadHash = stablePayloadHash(protonJSON)
                let domainPreview = {
                    let fromIndex = dbLoadDomainPreview3FromBlockTag(row.blockID)
                    if !fromIndex.isEmpty { return fromIndex }
                    return domainPreviewFromTagJSON(tagJSON)
                }()
                let goalPreview = dbLoadGoalPreview(row.blockID)
                let clipPDFRel = dbLoadClipPDFRel(row.blockID)

                if clipPDFRel.isEmpty {
                    dbDebugAttachments(row.blockID)
                }

                out.append(
                    BlockState(
                        id: stableID,
                        blockID: row.blockID,
                        instanceID: row.instanceID,
                        orderKey: row.orderKey,
                        createdAtMs: createdAtMs,
                        cardRowID: row.cardRowID,
                        cardStatus: row.cardStatus.isEmpty && noteType == .card ? "Pending" : row.cardStatus,
                        cardPriority: row.cardPriority.isEmpty && noteType == .card ? "Medium" : row.cardPriority,
                        cardCategory: row.cardCategory,
                        cardArea: row.cardArea,
                        cardContext: row.cardContext,
                        cardTitle: row.cardTitle,
                        domainPreview: domainPreview,
                        goalPreview: goalPreview,
                        attr: attr,
                        sel: existing?.sel ?? NSRange(location: 0, length: 0),
                        isCollapsed: existing?.isCollapsed ?? loadCollapsed(blockID: row.blockID),
                        protonHandle: h,
                        isDirty: false,
                        loadedUpdatedAtMs: loadedUpdatedAtMs,
                        loadedPayloadHash: loadedPayloadHash,
                        protonJSON: protonJSON,
                        tagJSON: tagJSON,
                        clipPDFRel: clipPDFRel,
                        isChecked: row.isChecked
                    )
                )

            }

            var priorByBlockID: [String: BlockState] = [:]
            for prior in priorBlocks where priorByBlockID[prior.blockID] == nil {
                priorByBlockID[prior.blockID] = prior
            }
            out = out.map { incoming in
                locallyProtectedReloadBlock(existing: priorByBlockID[incoming.blockID], incoming: incoming)
            }

            blocks = out

            if noteType == .card {
                normalizeCardRows()
            }

            // My Mac can keep rows mounted without reliably re-triggering the
            // per-row onAppear hydration path. If a block's preview string is
            // empty until full Proton content is applied, the row can stay
            // visually blank even though payload_json is present locally.
            for idx in blocks.indices {
                let protonJSON = blocks[idx].protonJSON
                guard !protonJSON.isEmpty else { continue }
                guard !blocks[idx].protonHandle.isEditing else { continue }
                blocks[idx].protonHandle.hydrateFromProtonJSONString(protonJSON)
            }

            let loadedBlockIDs = Set(blocks.map(\.blockID))
            let recoverablePriorBlocks = priorBlocks.filter { prior in
                hasMeaningfulAttributedContent(prior.attr) &&
                (prior.isDirty || prior.instanceID.isEmpty) &&
                !loadedBlockIDs.contains(prior.blockID)
            }

            if !recoverablePriorBlocks.isEmpty {
                let firstExistingOrder = blocks.first?.orderKey ?? 1000
                for (offset, prior) in recoverablePriorBlocks.enumerated() {
                    var recovered = prior
                    recovered.protonHandle.ownerBlockUUID = recovered.id
                    recovered.isDirty = true
                    recovered.orderKey = max(1, firstExistingOrder - Double(recoverablePriorBlocks.count - offset))
                    if noteType == .card && recovered.cardRowID.isEmpty {
                        recovered.cardRowID = store.notes.nextCardRowID(noteID: noteID.raw)
                    }
                    if noteType == .card && recovered.cardPriority.isEmpty {
                        recovered.cardPriority = "Medium"
                    }
                    if noteType == .card && recovered.cardStatus.isEmpty {
                        recovered.cardStatus = "Pending"
                    }
                    blocks.insert(recovered, at: min(offset, blocks.count))
                    scheduleCommit(recovered.id, debounce: 0.15)
                }
            }

            assert(Set(blocks.map { $0.id }).count == blocks.count)
            focusedBlockID = blocks.contains(where: { $0.id == priorFocusedID }) ? priorFocusedID : blocks.first?.id
            loadedContentWatermarkMs = currentContentWatermarkMs()
            loadedContentSignature = currentContentSignature()

            for b in blocks {
                guard !b.protonJSON.isEmpty else { continue }
                guard !b.isDirty else { continue }
                guard !b.protonHandle.isEditing else { continue }
                b.protonHandle.hydrateFromProtonJSONString(b.protonJSON)
            }
        }

    func markPendingRemoteRefresh() {
        hasPendingRemoteRefresh = true
    }

    func clearPendingRemoteRefresh() {
        hasPendingRemoteRefresh = false
    }

    func markLocalContentCommitted() {
        loadedContentWatermarkMs = max(loadedContentWatermarkMs, currentContentWatermarkMs())
        loadedContentSignature = currentContentSignature()
        hasPendingRemoteRefresh = false
    }

    func hasRemoteContentUpdateAvailable() -> Bool {
        let currentSignature = currentContentSignature()
        if !currentSignature.isEmpty, currentSignature == loadedContentSignature {
            return false
        }
        return currentContentWatermarkMs() > loadedContentWatermarkMs
    }

    private func currentContentWatermarkMs() -> Int64 {
        guard let store, let noteID else { return 0 }
        return store.notes.db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT MAX(v) FROM (
              SELECT COALESCE((SELECT updated_at_ms FROM nj_note WHERE note_id=? LIMIT 1), 0) AS v
              UNION ALL
              SELECT COALESCE(MAX(nb.updated_at_ms), 0) AS v
              FROM nj_note_block nb
              WHERE nb.note_id=? AND nb.deleted=0
              UNION ALL
              SELECT COALESCE(MAX(b.updated_at_ms), 0) AS v
              FROM nj_note_block nb
              JOIN nj_block b ON b.block_id = nb.block_id
              WHERE nb.note_id=? AND nb.deleted=0 AND b.deleted=0
            );
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, noteID.raw, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, noteID.raw, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, noteID.raw, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return 0
        }
    }

    private func reloadBlockFromStore(at index: Int) {
        guard store != nil else { return }
        guard blocks.indices.contains(index) else { return }

        var b = blocks[index]
        if b.isDirty || b.protonHandle.isEditing {
            markPendingRemoteRefresh()
            return
        }

        let protonJSON = dbLoadBlockProtonJSON(b.blockID)
        guard !protonJSON.isEmpty else {
            markPendingRemoteRefresh()
            return
        }

        b.protonJSON = protonJSON
        b.tagJSON = dbLoadBlockTagJSON(b.blockID)
        b.goalPreview = dbLoadGoalPreview(b.blockID)
        b.clipPDFRel = dbLoadClipPDFRel(b.blockID)
        b.attr = ensureNonEmptyTyped(stripZWSP(b.protonHandle.attributedStringFromProtonJSONString(protonJSON)))
        b.loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)
        b.loadedPayloadHash = stablePayloadHash(protonJSON)
        b.isDirty = false
        b.verifiedLocalEditAtMs = 0
        blocks[index] = b
        blocks[index].protonHandle.hydrateFromProtonJSONString(protonJSON)
        markLocalContentCommitted()
    }

    func hasActivelyEditingBlock() -> Bool {
        blocks.contains { $0.protonHandle.isEditing }
    }

    func flushDirtyBlocksNow() {
        let ids = blocks
            .filter { $0.isDirty && !$0.protonHandle.isEditing }
            .map(\.id)
        for id in ids {
            commitBlockNow(id, force: true)
        }
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

    func refreshGoalPreview(blockID: String) {
        guard let i = blocks.firstIndex(where: { $0.blockID == blockID }) else { return }
        let preview = dbLoadGoalPreview(blockID)
        if blocks[i].goalPreview != preview {
            blocks[i].goalPreview = preview
            blocks = Array(blocks)
        }
    }

    func updateBlockCreatedAt(_ id: UUID, createdAtMs: Int64) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }

        let normalized = max(1, createdAtMs)
        let nowMs = DBNoteRepository.nowMs()
        let blockID = blocks[i].blockID

        store.notes.updateBlockCreatedAtMs(blockID: blockID, createdAtMs: normalized, nowMs: nowMs)

        blocks[i].createdAtMs = normalized
        blocks = Array(blocks)
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

    func scheduleNoteMetaCommit(debounce: Double = 0.4) {
        noteMetaCommitWork?.cancel()
        hasPendingNoteMetaChanges = true
        let w = DispatchWorkItem { [weak self] in
            self?.commitNoteMetaNow()
            self?.noteMetaCommitWork = nil
        }
        noteMetaCommitWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    func commitNoteMetaNow() {
        guard let store, let noteID else { return }
        noteMetaCommitWork?.cancel()
        noteMetaCommitWork = nil
        let now = DBNoteRepository.nowMs()
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
        let safeTab = tab.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : tab
        let safeCardStatus = noteType == .card ? (cardStatus.isEmpty ? "Pending" : cardStatus) : ""
        let safeCardPriority = noteType == .card ? (cardPriority.isEmpty ? "Medium" : cardPriority) : ""
        if var n = store.notes.getNote(noteID) {
            if n.title == safeTitle &&
                n.tabDomain == safeTab &&
                n.noteType == noteType &&
                n.dominanceMode == dominanceMode &&
                (n.isChecklist > 0) == isChecklist &&
                n.cardID == cardID &&
                n.cardCategory == cardCategory &&
                n.cardArea == cardArea &&
                n.cardContext == cardContext &&
                n.cardStatus == safeCardStatus &&
                n.cardPriority == safeCardPriority {
                hasPendingNoteMetaChanges = false
                return
            }
            n.title = safeTitle
            n.tabDomain = safeTab
            n.noteType = noteType
            n.dominanceMode = dominanceMode
            n.isChecklist = isChecklist ? 1 : 0
            n.cardID = cardID
            n.cardCategory = cardCategory
            n.cardArea = cardArea
            n.cardContext = cardContext
            n.cardStatus = safeCardStatus
            n.cardPriority = safeCardPriority
            n.updatedAtMs = now
            store.notes.upsertNote(n)
            markLocalContentCommitted()
        }
        hasPendingNoteMetaChanges = false
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



    func commitBlockNow(_ id: UUID) {
        commitBlockNow(id, force: false)
    }
    
    func commitBlockNow(_ id: UUID, force: Bool = false) {
        guard let store, let noteID else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty && blocks[i].verifiedLocalEditAtMs <= 0 { return }

        if !force && shouldDeferCommitWhileFocused(id: id, index: i) {
            scheduleCommit(id, debounce: 0.6, source: "commitBlockNow.deferFocused")
            return
        }

        if shouldAbortForRemoteEditorLease(index: i) {
            return
        }

        var b = blocks[i]

        if b.instanceID.isEmpty {
            let ok = (b.orderKey > 0) ? b.orderKey : store.notes.nextAppendOrderKey(noteID: noteID.raw)
            let instanceID = store.notes.attachExistingBlockToNote(
                noteID: noteID.raw,
                blockID: b.blockID,
                orderKey: ok
            )
            b.instanceID = instanceID
            b.orderKey = ok
            blocks[i].instanceID = instanceID
            blocks[i].orderKey = ok
        }


        commitNoteMetaNow()

        guard let editor = b.protonHandle.editor else {
            let snapshotAttr = b.attr
            let hasSnapshot = hasMeaningfulAttributedContent(snapshotAttr)
            let persistedProtonJSON = b.protonJSON
            let snapshotTags: [String] = {
                var existingTags: [String] = {
                    guard !b.tagJSON.isEmpty,
                          let data = b.tagJSON.data(using: .utf8),
                          let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
                    else { return [] }
                    return arr
                }()

                let inheritedTag = tab.trimmingCharacters(in: .whitespacesAndNewlines)
                if !inheritedTag.isEmpty,
                   !existingTags.contains(where: { $0.caseInsensitiveCompare(inheritedTag) == .orderedSame }) {
                    existingTags.append(inheritedTag)
                }
                return NJTagExtraction.extract(from: snapshotAttr, existingTags: existingTags)?.tags ?? existingTags
            }()

            let snapshotTagJSON: String = {
                guard !snapshotTags.isEmpty,
                      let data = try? JSONSerialization.data(withJSONObject: snapshotTags),
                      let s = String(data: data, encoding: .utf8)
                else { return b.tagJSON }
                return s
            }()

            if hasSnapshot {
                if shouldProtectPlaceholderShell(
                    blockID: b.blockID,
                    persistedProtonJSON: persistedProtonJSON,
                    attr: snapshotAttr
                ) {
                    b.isDirty = false
                    blocks[i] = b
                    return
                }
                let protonJSON: String = {
                    if !persistedProtonJSON.isEmpty {
                        return persistedProtonJSON
                    }
                    return b.protonHandle.exportProtonJSONString(from: snapshotAttr)
                }()
                if shouldProtectStructuredAttachmentDowngrade(
                    existingProtonJSON: persistedProtonJSON,
                    candidateProtonJSON: protonJSON,
                    sourceAttr: snapshotAttr
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
                b.tagJSON = snapshotTagJSON
                blocks[i].protonJSON = protonJSON
                blocks[i].tagJSON = snapshotTagJSON
                if shouldAbortStaleEditorSave(index: i, candidateProtonJSON: protonJSON) {
                    return
                }
                store.notes.saveSingleProtonBlock(
                    blockID: b.blockID,
                    protonJSON: protonJSON,
                    tagJSON: snapshotTagJSON
                )
                b.loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)
                b.loadedPayloadHash = stablePayloadHash(protonJSON)
                b.isDirty = false
                b.verifiedLocalEditAtMs = 0
                markLocalContentCommitted()
                blocks[i] = b
                return
            }

            if b.protonJSON.isEmpty {
                b.isDirty = false
                blocks[i] = b
                return
            }
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: b.protonJSON,
                tagJSON: snapshotTagJSON
            )
            b.tagJSON = snapshotTagJSON
            b.loadedUpdatedAtMs = dbLoadBlockUpdatedAtMs(b.blockID)
            b.loadedPayloadHash = stablePayloadHash(b.protonJSON)
            b.isDirty = false
            b.verifiedLocalEditAtMs = 0
            markLocalContentCommitted()
            blocks[i] = b
            return
        }

        let liveAttr = editor.attributedText

        var existingTags: [String] = {
            guard !b.tagJSON.isEmpty,
                  let data = b.tagJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()

        let inheritedTag = tab.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inheritedTag.isEmpty,
           !existingTags.contains(where: { $0.caseInsensitiveCompare(inheritedTag) == .orderedSame }) {
            existingTags.append(inheritedTag)
        }

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

        let tagJSON: String = {
            guard !mergedTags.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: mergedTags),
                  let s = String(data: data, encoding: .utf8)
            else { return "" }
            return s
        }()

        if !tagJSON.isEmpty {
            b.tagJSON = tagJSON
            blocks[i].tagJSON = tagJSON
        }

        let originalAttr = editor.attributedText
        let views = extractPhotoAttachments(from: originalAttr)
        let sourceAttrForProton = tagRes?.cleaned ?? originalAttr
        if views.isEmpty,
           shouldProtectPlaceholderShell(
                blockID: b.blockID,
                persistedProtonJSON: b.protonJSON,
                attr: sourceAttrForProton
           ) {
            b.isDirty = false
            blocks[i] = b
            return
        }
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
                noteID: noteID.raw,
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

        let tagJSONToSave = tagJSON.isEmpty ? b.tagJSON : tagJSON

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

    private func shouldDeferCommitWhileFocused(id: UUID, index: Int) -> Bool {
        guard blocks.indices.contains(index) else { return false }
        let handle = blocks[index].protonHandle
        if handle.isEditing { return true }
        guard focusedBlockID == id else { return false }
        if let responderHandle = NJProtonEditorHandle.firstResponderHandle(), responderHandle === handle {
            return true
        }
        return false
    }

    func setBlockChecked(_ id: UUID, isChecked: Bool) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let instanceID = blocks[i].instanceID
        guard !instanceID.isEmpty else { return }

        let nowMs = DBNoteRepository.nowMs()
        store.notes.setNoteBlockChecked(instanceID: instanceID, isChecked: isChecked, nowMs: nowMs)
        store.sync.schedulePush(debounceMs: 0)
        blocks[i].isChecked = isChecked
        blocks = Array(blocks)
    }

    private func ensureBlockInstance(at index: Int) -> String? {
        guard let store, let noteID, blocks.indices.contains(index) else { return nil }
        if !blocks[index].instanceID.isEmpty {
            return blocks[index].instanceID
        }

        let orderKey = blocks[index].orderKey > 0 ? blocks[index].orderKey : store.notes.nextAppendOrderKey(noteID: noteID.raw)
        let instanceID = store.notes.attachExistingBlockToNote(
            noteID: noteID.raw,
            blockID: blocks[index].blockID,
            orderKey: orderKey
        )
        blocks[index].instanceID = instanceID
        blocks[index].orderKey = orderKey
        if noteType == .card && blocks[index].cardRowID.isEmpty {
            blocks[index].cardRowID = store.notes.nextCardRowID(noteID: noteID.raw)
        }
        if noteType == .card && blocks[index].cardStatus.isEmpty {
            blocks[index].cardStatus = "Pending"
        }
        if noteType == .card && blocks[index].cardPriority.isEmpty {
            blocks[index].cardPriority = "Medium"
        }
        return instanceID
    }

    func updateCardRowFields(
        _ id: UUID,
        cardRowID: String? = nil,
        status: String? = nil,
        priority: String? = nil,
        category: String? = nil,
        area: String? = nil,
        context: String? = nil,
        title: String? = nil
    ) {
        guard let store else { return }
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        guard let instanceID = ensureBlockInstance(at: index) else { return }

        if let cardRowID {
            blocks[index].cardRowID = cardRowID
        }
        if let status {
            blocks[index].cardStatus = status
        }
        if let priority {
            blocks[index].cardPriority = priority
        }
        if let category {
            blocks[index].cardCategory = category
        }
        if let area {
            blocks[index].cardArea = area
        }
        if let context {
            blocks[index].cardContext = context
        }
        if let title {
            blocks[index].cardTitle = title
        }

        let nowMs = DBNoteRepository.nowMs()
        store.notes.updateNoteBlockCardRowFields(
            instanceID: instanceID,
            cardRowID: blocks[index].cardRowID,
            status: blocks[index].cardStatus,
            priority: blocks[index].cardPriority,
            category: blocks[index].cardCategory,
            area: blocks[index].cardArea,
            context: blocks[index].cardContext,
            title: blocks[index].cardTitle,
            nowMs: nowMs
        )
        store.sync.schedulePush(debounceMs: 0)
        blocks = Array(blocks)
    }

    private func normalizeCardRows() {
        guard let store, let noteID else { return }

        var didChange = false
        for index in blocks.indices {
            var needsPersist = false

            if blocks[index].cardRowID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let existingMax = max(store.notes.nextCardRowID(noteID: noteID.raw), "1")
                let persistedValue = Int(existingMax) ?? 1
                let localMax = blocks.compactMap { Int($0.cardRowID) }.max() ?? 0
                blocks[index].cardRowID = String(max(localMax + 1, persistedValue))
                needsPersist = true
                didChange = true
            }

            if blocks[index].cardPriority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks[index].cardPriority = "Medium"
                needsPersist = true
                didChange = true
            }
            if blocks[index].cardStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks[index].cardStatus = "Pending"
                needsPersist = true
                didChange = true
            }

            if needsPersist, !blocks[index].instanceID.isEmpty {
                store.notes.updateNoteBlockCardRowFields(
                    instanceID: blocks[index].instanceID,
                    cardRowID: blocks[index].cardRowID,
                    status: blocks[index].cardStatus,
                    priority: blocks[index].cardPriority,
                    category: blocks[index].cardCategory,
                    area: blocks[index].cardArea,
                    context: blocks[index].cardContext,
                    title: blocks[index].cardTitle,
                    nowMs: DBNoteRepository.nowMs()
                )
            }
        }

        if didChange {
            store.sync.schedulePush(debounceMs: 0)
            blocks = Array(blocks)
        }
    }
}
