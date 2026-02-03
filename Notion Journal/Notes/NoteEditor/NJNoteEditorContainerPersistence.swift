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
        var domainPreview: String
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

        init(
            id: UUID = UUID(),
            blockID: String,
            instanceID: String,
            orderKey: Double,
            createdAtMs: Int64 = 0,
            domainPreview: String = "",
            attr: NSAttributedString,
            sel: NSRange = NSRange(location: 0, length: 0),
            isCollapsed: Bool = false,
            protonHandle: NJProtonEditorHandle = NJProtonEditorHandle(),
            isDirty: Bool = false,
            loadedUpdatedAtMs: Int64 = 0,
            loadedPayloadHash: String = "",
            protonJSON: String = "",
            tagJSON: String = "",
            clipPDFRel: String = ""
        ) {
            self.id = id
            self.blockID = blockID
            self.instanceID = instanceID
            self.orderKey = orderKey
            self.createdAtMs = createdAtMs
            self.domainPreview = domainPreview
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
        }

        static func == (lhs: BlockState, rhs: BlockState) -> Bool {
            lhs.id == rhs.id &&
            lhs.blockID == rhs.blockID &&
            lhs.instanceID == rhs.instanceID &&
            lhs.orderKey == rhs.orderKey &&
            lhs.createdAtMs == rhs.createdAtMs &&
            lhs.domainPreview == rhs.domainPreview &&
            lhs.attr.isEqual(to: rhs.attr) &&
            NSEqualRanges(lhs.sel, rhs.sel) &&
            lhs.isCollapsed == rhs.isCollapsed &&
            lhs.isDirty == rhs.isDirty &&
            lhs.loadedUpdatedAtMs == rhs.loadedUpdatedAtMs &&
            lhs.loadedPayloadHash == rhs.loadedPayloadHash &&
            lhs.protonJSON == rhs.protonJSON &&
            lhs.tagJSON == rhs.tagJSON &&
            lhs.clipPDFRel == rhs.clipPDFRel
        }
    }

    @Published var title: String = ""
    @Published var tab: String = ""
    @Published var blocks: [BlockState] = []
    @Published var focusedBlockID: UUID? = nil

    private var store: AppStore? = nil
    private var noteID: NJNoteID? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var didConfigure = false

    init() { }

    private func extractClipPDFRelFromPayload(_ payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8) else { return "" }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        guard let sections = root["sections"] as? [String: Any] else { return "" }
        guard let clip = sections["clip"] as? [String: Any] else { return "" }
        guard let clipData = clip["data"] as? [String: Any] else { return "" }
        guard let pdfPath = clipData["pdf_path"] as? String else { return "" }
        return pdfPath.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
            guard let store, let noteID else { return }

            if let note = store.notes.getNote(noteID) {
                title = note.title
                tab = note.tabDomain
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
            }

            let rows = store.notes.loadAllTextBlocksRTFWithPlacement(noteID: noteID.raw)

            if rows.isEmpty {
                let h = makeHandle()

                let newBlockID = UUID().uuidString
                let id = UUID(uuidString: newBlockID)
                    ?? NJStableUUID("\(noteID.raw)|\(newBlockID)|")
                h.ownerBlockUUID = id

                let b = BlockState(
                    id: id,
                    blockID: newBlockID,
                    instanceID: "",
                    orderKey: 1000,
                    createdAtMs: DBNoteRepository.nowMs(),
                    domainPreview: "",
                    attr: makeEmptyBlockAttr(),
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: loadCollapsed(blockID: newBlockID),
                    protonHandle: h,
                    isDirty: false,
                    loadedUpdatedAtMs: 0,
                    loadedPayloadHash: "",
                    protonJSON: "",
                    tagJSON: ""
                )

                blocks = [b]
                return
            }

            var out: [BlockState] = []
            out.reserveCapacity(rows.count)

            for row in rows {
                let stableID = UUID(uuidString: row.instanceID)
                    ?? UUID(uuidString: row.blockID)
                    ?? NJStableUUID("\(noteID.raw)|\(row.blockID)|\(row.instanceID)")
                let h = makeHandle()
                h.ownerBlockUUID = stableID

                let protonJSON = row.protonJSON

                let attr: NSAttributedString = {
                    if !protonJSON.isEmpty {
                        let first = h.previewFirstLineFromProtonJSON(protonJSON)
                        return ensureNonEmptyTyped(stripZWSP(NSAttributedString(string: first)))
                    }
                    let s = (try? NSAttributedString(
                        data: row.rtfData,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )) ?? makeEmptyBlockAttr()
                    return ensureNonEmptyTyped(stripZWSP(s))
                }()

                let createdAtMs = dbLoadBlockCreatedAtMs(row.blockID)
                let tagJSON = dbLoadBlockTagJSON(row.blockID)
                let domainPreview = {
                    let fromIndex = dbLoadDomainPreview3FromBlockTag(row.blockID)
                    if !fromIndex.isEmpty { return fromIndex }
                    return domainPreviewFromTagJSON(tagJSON)
                }()
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
                        domainPreview: domainPreview,
                        attr: attr,
                        sel: NSRange(location: 0, length: 0),
                        isCollapsed: loadCollapsed(blockID: row.blockID),
                        protonHandle: h,
                        isDirty: false,
                        loadedUpdatedAtMs: 0,
                        loadedPayloadHash: "",
                        protonJSON: protonJSON,
                        tagJSON: tagJSON,
                        clipPDFRel: clipPDFRel
                    )
                )

            }

            blocks = out
            assert(Set(blocks.map { $0.id }).count == blocks.count)
            focusedBlockID = blocks.first?.id
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

    func commitNoteMetaNow() {
        guard let store, let noteID else { return }
        let now = DBNoteRepository.nowMs()
        let safeTitle = title.isEmpty ? "Untitled" : title
        let safeTab = tab.isEmpty ? "default" : tab
        if var n = store.notes.getNote(noteID) {
            n.title = safeTitle
            n.tabDomain = safeTab
            n.updatedAtMs = now
            store.notes.upsertNote(n)
        }
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
        guard let store, let noteID else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty { return }

        if !force && blocks[i].protonHandle.isEditing {
            scheduleCommit(id, debounce: 0.6)
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
