import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
extension DBNoteRepository {

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

    func listNotes(tabDomainKey: String) -> [NJNote] {
        noteTable.listNotes(tabDomainKey: tabDomainKey)
    }

    func getNote(_ id: NJNoteID) -> NJNote? {
        noteTable.getNote(id)
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
        dirtyQueue.takeDirtyBatch(limit: limit)
    }

    func takeDirtyBatchDetailed(limit: Int) -> [NJDirtyItem] {
        dirtyQueue.takeDirtyBatch(limit: limit)
    }

    func clearDirty(entity: String, entityID: String) {
        dirtyQueue.clearDirty(entity: entity, entityID: entityID)
    }
}
