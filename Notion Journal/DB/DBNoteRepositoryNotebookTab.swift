import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
extension DBNoteRepository {

    func listNotebooks() -> [(String, String, String, Int64, Int64, Int64)] {
        db.withDB { dbp in
            var out: [(String, String, String, Int64, Int64, Int64)] = []
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived
            FROM nj_notebook
            ORDER BY updated_at_ms DESC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listNotebooks.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let notebookID = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let colorHex = String(cString: sqlite3_column_text(stmt, 2))
                let createdAtMs = sqlite3_column_int64(stmt, 3)
                let updatedAtMs = sqlite3_column_int64(stmt, 4)
                let isArchived = sqlite3_column_int64(stmt, 5)
                out.append((notebookID, title, colorHex, createdAtMs, updatedAtMs, isArchived))
            }
            return out
        }
    }

    func listTabs(notebookID: String) -> [(String, String, String, String, String, Int64, Int64, Int64, Int64)] {
        db.withDB { dbp in
            var out: [(String, String, String, String, String, Int64, Int64, Int64, Int64)] = []
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden
            FROM nj_tab
            WHERE notebook_id = ?
            ORDER BY ord ASC, updated_at_ms DESC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listTabs.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let tabID = String(cString: sqlite3_column_text(stmt, 0))
                let nbID = String(cString: sqlite3_column_text(stmt, 1))
                let title = String(cString: sqlite3_column_text(stmt, 2))
                let domainKey = String(cString: sqlite3_column_text(stmt, 3))
                let colorHex = String(cString: sqlite3_column_text(stmt, 4))
                let ord = sqlite3_column_int64(stmt, 5)
                let createdAtMs = sqlite3_column_int64(stmt, 6)
                let updatedAtMs = sqlite3_column_int64(stmt, 7)
                let isHidden = sqlite3_column_int64(stmt, 8)
                out.append((tabID, nbID, title, domainKey, colorHex, ord, createdAtMs, updatedAtMs, isHidden))
            }
            return out
        }
    }

    func upsertNotebook(notebookID: String, title: String, colorHex: String, isArchived: Int64) {
        let now = Self.nowMs()
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
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "upsertNotebook.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, colorHex, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, now)
            sqlite3_bind_int64(stmt, 5, now)
            sqlite3_bind_int64(stmt, 6, isArchived)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "upsertNotebook.step", rc1) }
        }
        enqueueDirty(entity: "notebook", entityID: notebookID, op: "upsert", updatedAtMs: now)
    }

    func upsertTab(tabID: String, notebookID: String, title: String, domainKey: String, colorHex: String, order: Int64, isHidden: Int64) {
        let now = Self.nowMs()
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
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "upsertTab.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, tabID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, domainKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, colorHex, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, order)
            sqlite3_bind_int64(stmt, 7, now)
            sqlite3_bind_int64(stmt, 8, now)
            sqlite3_bind_int64(stmt, 9, isHidden)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "upsertTab.step", rc1) }
        }
        enqueueDirty(entity: "tab", entityID: tabID, op: "upsert", updatedAtMs: now)
    }
}
