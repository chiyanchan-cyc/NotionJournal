import SwiftUI
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NJReconstructedNotePersistence: ObservableObject {
    @Published var title: String = ""
    @Published var tab: String = ""
    @Published var blocks: [NJNoteEditorContainerPersistence.BlockState] = []
    @Published var focusedBlockID: UUID? = nil

    private var store: AppStore? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var didConfigure = false

    private var spec: NJReconstructedSpec

    init(spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
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

    private func sqlWhereForSpec() -> (whereSQL: String, binder: (OpaquePointer?) -> Void) {
        let startMs = spec.startMs
        let endMs = spec.endMs

        let timeExpr: String = {
            switch spec.timeField {
            case .blockCreatedAtMs: return "b.created_at_ms"
            case .tagCreatedAtMs: return "t.created_at_ms"
            }
        }()

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
            return (whereSQL, binder)
        }
    }

    private func dbLoadRows() -> [Row] {
        guard let store else { return [] }
        return store.notes.db.withDB { dbp in
            var out: [Row] = []
            var stmt: OpaquePointer?

            let (whereSQL, binder) = sqlWhereForSpec()

            let orderSQL = spec.newestFirst ? "DESC" : "ASC"
            let sql = """
            SELECT b.block_id, b.proton_json, b.created_at_ms
            FROM nj_block b
            JOIN nj_block_tag t
              ON t.block_id = b.block_id COLLATE NOCASE
            WHERE \(whereSQL)
            GROUP BY b.block_id
            ORDER BY b.created_at_ms \(orderSQL)
            LIMIT ?;
            """

            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return [] }
            defer { sqlite3_finalize(stmt) }

            binder(stmt)

            sqlite3_bind_int(stmt, sqlite3_bind_parameter_count(stmt), Int32(max(1, spec.limit)))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let blockID = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let protonJSON = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let createdAtMs = sqlite3_column_int64(stmt, 2)
                if !blockID.isEmpty {
                    out.append(Row(blockID: blockID, protonJSON: protonJSON, createdAtMs: createdAtMs))
                }
            }

            return out
        }
    }

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
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
            let id = UUID()
            let h = makeHandle()
            h.ownerBlockUUID = id

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
                    id: id,
                    blockID: r.blockID,
                    instanceID: "",
                    orderKey: ok,
                    createdAtMs: r.createdAtMs,
                    domainPreview: domainPreview,
                    attr: attr,
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: false,
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
        focusedBlockID = blocks.first?.id
    }

    private func makeTypedFromPlain(_ s: String) -> NSAttributedString {
        let cleaned = s.isEmpty ? "\u{200B}" : s
        return NSAttributedString(string: cleaned)
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
            let protonJSON = b.protonHandle.exportProtonJSONString()
            b.protonJSON = protonJSON
            blocks[i].protonJSON = protonJSON
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: protonJSON,
                tagJSON: b.tagJSON
            )
            b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
            b.isDirty = false
            blocks[i] = b
            return
        }

        let liveAttr = editor.attributedText
        let tagRes = NJTagExtraction.extract(from: liveAttr)
        let tags = tagRes?.tags ?? []

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
            guard !tags.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: tags),
                  let s = String(data: data, encoding: .utf8)
            else { return "" }
            return s
        }()

        if !tagJSON.isEmpty {
            b.tagJSON = tagJSON
            blocks[i].tagJSON = tagJSON
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

        let tagJSONToSave = tagJSON.isEmpty ? b.tagJSON : tagJSON

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
