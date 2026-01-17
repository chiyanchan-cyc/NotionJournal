//
//  DBNotebookTable.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/4.
//


import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class DBNotebookTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func listNotebooksUpdatedDescTuple() -> [(String, String, String, Int64, Int64, Int64)] {
        db.withDB { dbp in
            var out: [(String, String, String, Int64, Int64, Int64)] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived
            FROM nj_notebook
            ORDER BY updated_at_ms DESC;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBNotebookTable.listNotebooksUpdatedDescTuple.prepare", rc0); return out }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let color = String(cString: sqlite3_column_text(stmt, 2))
                let created = sqlite3_column_int64(stmt, 3)
                let updated = sqlite3_column_int64(stmt, 4)
                let archived = sqlite3_column_int64(stmt, 5)
                out.append((id, title, color, created, updated, archived))
            }
            return out
        }
    }

    func listNotebooks() -> [[String: Any]] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived
            FROM nj_notebook
            ORDER BY title COLLATE NOCASE ASC;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBNotebookTable.listNotebooks.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            var out: [[String: Any]] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                if rc != SQLITE_ROW { db.dbgErr(dbp, "DBNotebookTable.listNotebooks.step", rc); break }

                let notebookID = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let colorHex = String(cString: sqlite3_column_text(stmt, 2))
                let createdAtMs = Int64(sqlite3_column_int64(stmt, 3))
                let updatedAtMs = Int64(sqlite3_column_int64(stmt, 4))
                let isArchived = Int64(sqlite3_column_int64(stmt, 5))

                out.append([
                    "notebook_id": notebookID,
                    "title": title,
                    "color_hex": colorHex,
                    "created_at_ms": createdAtMs,
                    "updated_at_ms": updatedAtMs,
                    "is_archived": isArchived
                ])
            }
            return out
        }
    }

    func loadNJNotebook(notebookID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived
            FROM nj_notebook
            WHERE notebook_id = ?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBNotebookTable.loadNJNotebook.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 == SQLITE_DONE { return nil }
            if rc1 != SQLITE_ROW { db.dbgErr(dbp, "DBNotebookTable.loadNJNotebook.step", rc1); return nil }

            let nid = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let colorHex = String(cString: sqlite3_column_text(stmt, 2))
            let createdAtMs = Int64(sqlite3_column_int64(stmt, 3))
            let updatedAtMs = Int64(sqlite3_column_int64(stmt, 4))
            let isArchived = Int64(sqlite3_column_int64(stmt, 5))

            return [
                "notebook_id": nid,
                "title": title,
                "color_hex": colorHex,
                "created_at_ms": createdAtMs,
                "updated_at_ms": updatedAtMs,
                "is_archived": isArchived
            ]
        }
    }

    func applyNJNotebook(_ f: [String: Any]) {
        let notebookID = (f["notebook_id"] as? String) ?? ""
        if notebookID.isEmpty { return }

        let title = (f["title"] as? String) ?? ""
        let colorHex = (f["color_hex"] as? String) ?? ""
        let createdAtMs = (f["created_at_ms"] as? Int64) ?? Int64((f["created_at_ms"] as? Int) ?? 0)
        let updatedAtMs = (f["updated_at_ms"] as? Int64) ?? Int64((f["updated_at_ms"] as? Int) ?? 0)
        let isArchived = (f["is_archived"] as? Int64) ?? Int64((f["is_archived"] as? Int) ?? 0)

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_notebook(notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(notebook_id) DO UPDATE SET
                title=excluded.title,
                color_hex=excluded.color_hex,
                created_at_ms=excluded.created_at_ms,
                updated_at_ms=excluded.updated_at_ms,
                is_archived=excluded.is_archived;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBNotebookTable.applyNJNotebook.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, colorHex, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, createdAtMs)
            sqlite3_bind_int64(stmt, 5, updatedAtMs)
            sqlite3_bind_int64(stmt, 6, isArchived)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "DBNotebookTable.applyNJNotebook.step", rc1) }
        }
    }

    func upsertLocal(notebookID: String, title: String, colorHex: String, createdAtMs: Int64, updatedAtMs: Int64, isArchived: Int64) {
        let f: [String: Any] = [
            "notebook_id": notebookID,
            "title": title,
            "color_hex": colorHex,
            "created_at_ms": createdAtMs,
            "updated_at_ms": updatedAtMs,
            "is_archived": isArchived
        ]
        applyNJNotebook(f)
        enqueueDirty("notebook", notebookID, "upsert", updatedAtMs)
    }
}
