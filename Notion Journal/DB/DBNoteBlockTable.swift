//
//  DBNoteBlockTable.swift
//  Notion Journal
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBNoteBlockTable {
    let db: SQLiteDB
    let enqueueDirtyFn: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirtyFn = enqueueDirty
    }

    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        enqueueDirtyFn(entity, entityID, op, updatedAtMs)
    }

    func loadNJNoteBlock(noteID: String, orderKey: Double) -> [String: Any]? {
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT instance_id, note_id, block_id, order_key, view_state_json, created_at_ms, updated_at_ms, deleted
            FROM nj_note_block
            WHERE note_id=? AND order_key=? AND deleted=0
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, orderKey)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            return [
                "instance_id": sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? "",
                "note_id": sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? "",
                "block_id": sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "",
                "order_key": sqlite3_column_double(stmt, 3),
                "view_state_json": sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? "",
                "created_at_ms": sqlite3_column_int64(stmt, 5),
                "updated_at_ms": sqlite3_column_int64(stmt, 6),
                "deleted": sqlite3_column_int64(stmt, 7)
            ]
        }
    }

    func loadNJNoteBlock(instanceID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT
              instance_id,
              note_id,
              block_id,
              order_key,
              created_at_ms,
              updated_at_ms,
              deleted
            FROM nj_note_block
            WHERE instance_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadNJNoteBlock.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, instanceID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let noteID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let blockID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
            let orderKey = sqlite3_column_int64(stmt, 3)
            let createdAtMs = sqlite3_column_int64(stmt, 4)
            let updatedAtMs = sqlite3_column_int64(stmt, 5)
            let deleted = sqlite3_column_int64(stmt, 6)

            return [
                "instance_id": instanceID,
                "note_id": noteID,
                "block_id": blockID,
                "order_key": orderKey,
                "created_at_ms": createdAtMs,
                "updated_at_ms": updatedAtMs,
                "deleted": deleted
            ]
        }
    }

    func applyNJNoteBlock(_ f: [String: Any]) {
        let instanceID =
          (f["instance_id"] as? String) ??
          (f["instanceID"] as? String) ??
          (f["id"] as? String) ??
          ""
        if instanceID.isEmpty { return }

        let noteID = (f["note_id"] as? String) ?? ""
        let blockID = (f["block_id"] as? String) ?? ""
        let orderKey = (f["order_key"] as? Int64) ?? 0
        let createdAtMs = (f["created_at_ms"] as? Int64) ?? 0
        let updatedAtMs = (f["updated_at_ms"] as? Int64) ?? 0
        let deleted = (f["deleted"] as? Int64) ?? 0

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_note_block(
              instance_id,
              note_id,
              block_id,
              order_key,
              created_at_ms,
              updated_at_ms,
              deleted
            )
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(instance_id) DO UPDATE SET
              note_id=excluded.note_id,
              block_id=excluded.block_id,
              order_key=excluded.order_key,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyNJNoteBlock.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, instanceID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, orderKey)
            sqlite3_bind_int64(stmt, 5, createdAtMs)
            sqlite3_bind_int64(stmt, 6, updatedAtMs)
            sqlite3_bind_int64(stmt, 7, deleted)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyNJNoteBlock.step", rc1) }
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: updatedAtMs)
    }

    func findFirstInstanceByBlock(blockID: String) -> (noteID: String, instanceID: String)? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT note_id, instance_id
            FROM nj_note_block
            WHERE block_id=? AND deleted=0
            ORDER BY order_key ASC
            LIMIT 1;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "findFirstInstanceByBlock.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let noteID = String(cString: sqlite3_column_text(stmt, 0))
            let instanceID = String(cString: sqlite3_column_text(stmt, 1))
            return (noteID, instanceID)
        }
    }
}
