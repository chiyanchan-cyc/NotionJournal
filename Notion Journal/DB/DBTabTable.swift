//
//  DBTabTable.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/6.
//


import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class DBTabTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func listTabsTuple(notebookID: String) -> [(String, String, String, String, String, Int64, Int64, Int64, Int64)] {
        db.withDB { dbp in
            var out: [(String, String, String, String, String, Int64, Int64, Int64, Int64)] = []
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden
            FROM nj_tab
            WHERE notebook_id=?
            ORDER BY ord ASC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBTabTable.listTabsTuple.prepare", rc0); return out }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let tabID = String(cString: sqlite3_column_text(stmt, 0))
                let nbID = String(cString: sqlite3_column_text(stmt, 1))
                let title = String(cString: sqlite3_column_text(stmt, 2))
                let dom = String(cString: sqlite3_column_text(stmt, 3))
                let color = String(cString: sqlite3_column_text(stmt, 4))
                let ord = sqlite3_column_int64(stmt, 5)
                let created = sqlite3_column_int64(stmt, 6)
                let updated = sqlite3_column_int64(stmt, 7)
                let hidden = sqlite3_column_int64(stmt, 8)
                out.append((tabID, nbID, title, dom, color, ord, created, updated, hidden))
            }
            return out
        }
    }

    func loadNJTab(tabID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden
            FROM nj_tab
            WHERE tab_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBTabTable.loadNJTab.prepare", rc0); return nil }
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

    func applyNJTab(_ f: [String: Any]) {
        let tabID = (f["tab_id"] as? String) ?? ""
        if tabID.isEmpty { return }

        let notebookID = (f["notebook_id"] as? String) ?? ""
        let title = (f["title"] as? String) ?? ""
        let dom = (f["domain_key"] as? String) ?? ""
        let color = (f["color_hex"] as? String) ?? "#64748B"
        let ord = (f["order"] as? Int64) ?? 0
        let created = (f["created_at_ms"] as? Int64) ?? Int64((f["created_at_ms"] as? Int) ?? 0)
        let updated = (f["updated_at_ms"] as? Int64) ?? Int64((f["updated_at_ms"] as? Int) ?? 0)
        let hidden = (f["is_hidden"] as? Int64) ?? Int64((f["is_hidden"] as? Int) ?? 0)

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
                created_at_ms=excluded.created_at_ms,
                updated_at_ms=excluded.updated_at_ms,
                is_hidden=excluded.is_hidden;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "DBTabTable.applyNJTab.prepare", rc0); return }
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
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "DBTabTable.applyNJTab.step", rc1) }
        }
    }

    func upsertLocal(tabID: String, notebookID: String, title: String, domainKey: String, colorHex: String, ord: Int64, createdAtMs: Int64, updatedAtMs: Int64, isHidden: Int64) {
        let f: [String: Any] = [
            "tab_id": tabID,
            "notebook_id": notebookID,
            "title": title,
            "domain_key": domainKey,
            "color_hex": colorHex,
            "order": ord,
            "created_at_ms": createdAtMs,
            "updated_at_ms": updatedAtMs,
            "is_hidden": isHidden
        ]
        applyNJTab(f)
        enqueueDirty("tab", tabID, "upsert", updatedAtMs)
    }
}
