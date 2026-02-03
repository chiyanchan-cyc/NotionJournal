import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


@MainActor
final class DBNoteRepository {
    
    let db: SQLiteDB
    
    private let dirtyQueue: DBDirtyQueueTable
    private let noteTable: DBNoteTable
    private let blockTable: DBBlockTable
    private let noteBlockTable: DBNoteBlockTable
    let attachmentTable: DBAttachmentTable
    let goalTable: DBGoalTable
    private let cloudBridge: DBCloudBridge
    
    
    init(db: SQLiteDB) {
        self.db = db
        self.dirtyQueue = DBDirtyQueueTable(db: db)
        
        let dq = self.dirtyQueue
        
        self.blockTable = DBBlockTable(db: db, enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) })
        
        self.noteBlockTable = DBNoteBlockTable(db: db, enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) })

        self.attachmentTable = DBAttachmentTable(db: db, enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) })
        
        self.noteTable = DBNoteTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) },
            loadRTF: { _ in
                nil
            },
            emptyRTF: { Self.emptyRTF() },
            nowMs: { Self.nowMs() }
        )
        self.goalTable = DBGoalTable(db: db)
        self.cloudBridge = DBCloudBridge(
            noteTable: self.noteTable,
            blockTable: self.blockTable,
            noteBlockTable: self.noteBlockTable,
            attachmentTable: self.attachmentTable,
            goalTable: self.goalTable
        )
    }
    
    func listOrphanClipBlocks(limit: Int = 200) -> [DBBlockTable.NJOrphanClipRow] {
        blockTable.listOrphanClipBlocks(limit: limit)
    }
    
    func upsertTagsForNoteBlockInstanceID(
        instanceID: String,
        tags: [String],
        nowMs: Int64
    ) {
        var resolvedBlockID = instanceID
        
        if !blockTable.hasBlock(blockID: resolvedBlockID) {
            if let nb = noteBlockTable.loadNJNoteBlock(instanceID: instanceID),
               let bid = nb["block_id"] as? String,
               !bid.isEmpty {
                resolvedBlockID = bid
            }
        }
        
        upsertTagsForBlockID(
            blockID: resolvedBlockID,
            tags: tags,
            nowMs: nowMs
        )
    }
    
    func upsertTagsForBlockID(
        blockID: String,
        tags: [String],
        nowMs: Int64
    ) {
        guard blockTable.hasBlock(blockID: blockID) else {
            print("NJ_TAG no block \(blockID)")
            return
        }
        
        blockTable.upsertTagsForBlockID(
            blockID: blockID,
            tags: tags,
            nowMs: nowMs
        )
    }
    
    func applyPulled(entity: String, rows: [(String, [String: Any])]) {
        switch entity {
        case "notebook":
            for (_, f) in rows { applyRemoteUpsert(entity: "notebook", fields: f) }
            
        case "tab":
            for (_, f) in rows { applyRemoteUpsert(entity: "tab", fields: f) }
            
        case "note":
            for (_, f) in rows { applyRemoteUpsert(entity: "note", fields: f) }
            
        case "block":
            for (_, f) in rows { applyRemoteUpsert(entity: "block", fields: f) }

        case "attachment":
            for (_, f) in rows { applyRemoteUpsert(entity: "attachment", fields: f) }

        case "note_block":
            func noteID(_ f: [String: Any]) -> String { (f["note_id"] as? String) ?? (f["noteID"] as? String) ?? "" }
            func blockID(_ f: [String: Any]) -> String { (f["block_id"] as? String) ?? (f["blockID"] as? String) ?? "" }
            
            var pending: [[String: Any]] = rows.map { $0.1 }
            var passes = 0
            while !pending.isEmpty && passes < 5 {
                passes += 1
                var next: [[String: Any]] = []
                next.reserveCapacity(pending.count)
                
                for f in pending {
                    let n = noteID(f)
                    let b = blockID(f)
                    if n.isEmpty || b.isEmpty { continue }
                    if getNote(NJNoteID(n)) == nil { next.append(f); continue }
                    if hasBlock(blockID: b) == false { next.append(f); continue }
                    applyRemoteUpsert(entity: "note_block", fields: f)
                }
                
                if next.count == pending.count { break }
                pending = next
            }
            
        default:
            break
        }
    }
    
    func cloudFields(entity: String, id: String) -> [String: Any] {
        if entity == "notebook" { return loadNotebookFields(notebookID: id) ?? [:] }
        if entity == "tab" { return loadTabFields(tabID: id) ?? [:] }
        return loadRecord(entity: entity, id: id) ?? [:]
    }
    
    func localCount(entity: String) -> Int {
        let table: String
        switch entity {
        case "notebook": table = "nj_notebook"
        case "tab": table = "nj_tab"
        case "note": table = "nj_note"
        case "block": table = "nj_block"
        case "note_block": table = "nj_note_block"
        default: return 0
        }
        
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "localCount.prepare", rc0); return 0 }
            defer { sqlite3_finalize(stmt) }
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_ROW { db.dbgErr(dbp, "localCount.step", rc1); return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
    
    
    
    
    func hasBlock(blockID: String) -> Bool {
        blockTable.hasBlock(blockID: blockID)
    }
    
    func listNotes(tabDomainKey: String) -> [NJNote] {
        noteTable.listNotes(tabDomainKey: tabDomainKey)
    }
    
    func getNote(_ id: NJNoteID) -> NJNote? {
        noteTable.getNote(id)
    }
    
    func loadBlockPayloadJSON(blockID: String) -> String {
        blockTable.loadBlockPayloadJSON(blockID: blockID)
    }
    
    func createNote(notebook: String, tabDomain: String, title: String) -> NJNote {
        noteTable.createNote(notebook: notebook, tabDomain: tabDomain, title: title)
    }
    
    func upsertNote(_ note: NJNote) {
        noteTable.upsertNote(note)
    }
    
    func deleteNote(_ noteID: NJNoteID) {
        noteTable.deleteNote(noteID)
    }
    
    func deleteNote(noteID: String) {
        noteTable.deleteNote(NJNoteID(noteID))
    }
    
    func markNoteDeleted(noteID: String) {
        noteTable.markNoteDeleted(noteID: noteID)
    }
    
    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        dirtyQueue.enqueueDirty(entity: entity, entityID: entityID, op: op, updatedAtMs: updatedAtMs)
    }
    
    func takeDirtyBatch(limit: Int) -> [(String, String)] {
        (try? dirtyQueue.takeDirtyBatch(limit: limit))?.map { ($0.entity, $0.entityID) } ?? []
    }

    func takeDirtyBatchDetailed(limit: Int) -> [NJDirtyItem] {
        (try? dirtyQueue.takeDirtyBatch(limit: limit)) ?? []
    }
    
    
    func clearDirty(entity: String, entityID: String) {
        dirtyQueue.clearDirty(entity: entity, entityID: entityID)
    }
    
    func loadRecord(entity: String, id: String) -> [String: Any]? {
        if entity == "notebook" { return loadNotebookFields(notebookID: id) }
        if entity == "tab" { return loadTabFields(tabID: id) }
        return cloudBridge.loadRecord(entity: entity, id: id)
    }
    
    func applyRemoteUpsert(entity: String, fields: [String: Any]) {
        if entity == "notebook" { applyNotebookFields(fields); return }
        if entity == "tab" { applyTabFields(fields); return }
        cloudBridge.applyRemoteUpsert(entity: entity, fields: fields)
    }
    
    func recordDirtyError(entity: String, entityID: String, code: Int, domain: String, message: String, retryAfterSec: Double?) {
        dirtyQueue.recordDirtyError(entity: entity, entityID: entityID, code: code, domain: domain, message: message, retryAfterSec: retryAfterSec)
    }
    
    private func loadNotebookFields(notebookID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived
            FROM nj_notebook
            WHERE notebook_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadNotebookFields.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)
            
            let rc1 = sqlite3_step(stmt)
            guard rc1 == SQLITE_ROW else { return nil }
            
            return [
                "notebook_id": String(cString: sqlite3_column_text(stmt, 0)),
                "title": String(cString: sqlite3_column_text(stmt, 1)),
                "color_hex": String(cString: sqlite3_column_text(stmt, 2)),
                "created_at_ms": sqlite3_column_int64(stmt, 3),
                "updated_at_ms": sqlite3_column_int64(stmt, 4),
                "is_archived": sqlite3_column_int64(stmt, 5)
            ]
        }
    }
    
    private func loadTabFields(tabID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden
            FROM nj_tab
            WHERE tab_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadTabFields.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, tabID, -1, SQLITE_TRANSIENT)
            
            let rc1 = sqlite3_step(stmt)
            guard rc1 == SQLITE_ROW else { return nil }
            
            return [
                "tab_id": String(cString: sqlite3_column_text(stmt, 0)),
                "notebook_id": String(cString: sqlite3_column_text(stmt, 1)),
                "title": String(cString: sqlite3_column_text(stmt, 2)),
                "domain_key": String(cString: sqlite3_column_text(stmt, 3)),
                "color_hex": String(cString: sqlite3_column_text(stmt, 4)),
                "order": sqlite3_column_int64(stmt, 5),
                "created_at_ms": sqlite3_column_int64(stmt, 6),
                "updated_at_ms": sqlite3_column_int64(stmt, 7),
                "is_hidden": sqlite3_column_int64(stmt, 8)
            ]
        }
    }
    
    private func applyNotebookFields(_ f: [String: Any]) {
        guard let notebookID = f["notebook_id"] as? String else { return }
        let title = (f["title"] as? String) ?? ""
        let color = (f["color_hex"] as? String) ?? "#64748B"
        let created = (f["created_at_ms"] as? Int64) ?? Self.nowMs()
        let updated = (f["updated_at_ms"] as? Int64) ?? created
        let archived = (f["is_archived"] as? Int64) ?? 0
        
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_notebook(notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(notebook_id) DO UPDATE SET
                title=excluded.title,
                color_hex=excluded.color_hex,
                updated_at_ms=excluded.updated_at_ms,
                is_archived=excluded.is_archived;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyNotebookFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, color, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, created)
            sqlite3_bind_int64(stmt, 5, updated)
            sqlite3_bind_int64(stmt, 6, archived)
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyNotebookFields.step", rc1) }
        }
    }
    
    private func applyTabFields(_ f: [String: Any]) {
        guard let tabID = f["tab_id"] as? String else { return }
        let notebookID = (f["notebook_id"] as? String) ?? ""
        let title = (f["title"] as? String) ?? ""
        let dom = (f["domain_key"] as? String) ?? ""
        let color = (f["color_hex"] as? String) ?? "#64748B"
        let ord = (f["order"] as? Int64) ?? 0
        let created = (f["created_at_ms"] as? Int64) ?? Self.nowMs()
        let updated = (f["updated_at_ms"] as? Int64) ?? created
        let hidden = (f["is_hidden"] as? Int64) ?? 0
        
        if notebookID.isEmpty { return }
        
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_tab(tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(tab_id) DO UPDATE SET
                notebook_id=excluded.notebook_id,
                title=excluded.title,
                domain_key=excluded.domain_key,
                color_hex=excluded.color_hex,
                ord=excluded.ord,
                updated_at_ms=excluded.updated_at_ms,
                is_hidden=excluded.is_hidden;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyTabFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, tabID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, dom, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, color, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, ord)
            sqlite3_bind_int64(stmt, 7, created)
            sqlite3_bind_int64(stmt, 8, updated)
            sqlite3_bind_int64(stmt, 9, hidden)
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyTabFields.step", rc1) }
        }
    }
    
    func findFirstInstanceByBlock(blockID: String) -> (noteID: String, instanceID: String)? {
        noteBlockTable.findFirstInstanceByBlock(blockID: blockID)
    }
    
    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }
    
    static func emptyRTF() -> Data {
        let zwsp = String(UnicodeScalar(8203)!)
        let a = NSAttributedString(string: zwsp, attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ])
        return (try? a.data(
            from: NSRange(location: 0, length: a.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }
    
    
}
