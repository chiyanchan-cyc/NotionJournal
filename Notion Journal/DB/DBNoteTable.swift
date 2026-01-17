//
//  DBNoteTable.swift
//  Notion Journal
//

import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBNoteTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void
    let loadRTF: (String) -> Data?
    let emptyRTF: () -> Data
    let nowMs: () -> Int64

    init(
        db: SQLiteDB,
        enqueueDirty: @escaping (String, String, String, Int64) -> Void,
        loadRTF: @escaping (String) -> Data?,
        emptyRTF: @escaping () -> Data,
        nowMs: @escaping () -> Int64
    ) {
        self.db = db
        self.enqueueDirty = enqueueDirty
        self.loadRTF = loadRTF
        self.emptyRTF = emptyRTF
        self.nowMs = nowMs
    }

    func listNotes(tabDomainKey: String, sortAscending: Bool = false) -> [NJNote] {
        let order = sortAscending ? "ASC" : "DESC"
        let sanitized = tabDomainKey.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "._", with: ".")
        let exact = sanitized.hasSuffix(".") ? String(sanitized.dropLast()) : sanitized
        let prefix = exact + ".%"

        let sql = """
        SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, deleted
        FROM nj_note
        WHERE deleted = 0
          AND (tab_domain = ? OR tab_domain LIKE ?)
        ORDER BY updated_at_ms \(order);
        """

        return db.withDB { dbp in
            do {
                var s0: OpaquePointer?
                let q0 = "SELECT COUNT(*) FROM nj_note WHERE deleted=0 AND tab_domain=?;"
                let rcq = sqlite3_prepare_v2(dbp, q0, -1, &s0, nil)
                if rcq == SQLITE_OK, let s0 {
                    sqlite3_bind_text(s0, 1, exact, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(s0) == SQLITE_ROW {
                        let c = sqlite3_column_int64(s0, 0)
//                        print("NJ_LISTNOTES key=\(exact) COUNT(tab_domain=key)=\(c)")
                    } else {
//                        print("NJ_LISTNOTES key=\(exact) COUNT step not row")
                    }
                    sqlite3_finalize(s0)
                } else {
//                    print("NJ_LISTNOTES COUNT prepare rc=\(rcq)")
                }
            }

            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listNotes.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, exact, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, prefix, -1, SQLITE_TRANSIENT)

            var out: [NJNote] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let noteID = String(cString: sqlite3_column_text(stmt, 0))
                let createdMs = sqlite3_column_int64(stmt, 1)
                let updatedMs = sqlite3_column_int64(stmt, 2)
                let notebook = String(cString: sqlite3_column_text(stmt, 3))
                let tab = String(cString: sqlite3_column_text(stmt, 4))
                let title = String(cString: sqlite3_column_text(stmt, 5))
                let deleted = sqlite3_column_int64(stmt, 6)

                let rtf = loadRTF(noteID) ?? emptyRTF()

                out.append(NJNote(
                    id: NJNoteID(noteID),
                    createdAtMs: createdMs,
                    updatedAtMs: updatedMs,
                    notebook: notebook,
                    tabDomain: tab,
                    title: title,
                    rtfData: rtf,
                    deleted: deleted
                ))
            }

//            print("NJ_LISTNOTES key=\(exact) prefix=\(prefix) outCount=\(out.count)")
            return out
        }
    }

    func getNote(_ id: NJNoteID) -> NJNote? {
        let noteID = id.raw
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, deleted
            FROM nj_note
            WHERE note_id = ?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "getNote.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let createdMs = sqlite3_column_int64(stmt, 1)
            let updatedMs = sqlite3_column_int64(stmt, 2)
            let notebook = String(cString: sqlite3_column_text(stmt, 3))
            let tab = String(cString: sqlite3_column_text(stmt, 4))
            let title = String(cString: sqlite3_column_text(stmt, 5))
            let deleted = sqlite3_column_int64(stmt, 6)

            let rtf = loadRTF(noteID) ?? emptyRTF()

            return NJNote(
                id: NJNoteID(noteID),
                createdAtMs: createdMs,
                updatedAtMs: updatedMs,
                notebook: notebook,
                tabDomain: tab,
                title: title,
                rtfData: rtf,
                deleted: deleted
            )
        }
    }

    func createNote(notebook: String, tabDomain: String, title: String) -> NJNote {
        let now = nowMs()
        let id = UUID().uuidString.lowercased()
        let note = NJNote(
            id: NJNoteID(id),
            createdAtMs: now,
            updatedAtMs: now,
            notebook: notebook,
            tabDomain: tabDomain,
            title: title,
            rtfData: emptyRTF(),
            deleted: 0
        )
        upsertNote(note)
        return note
    }

    func upsertNote(_ note: NJNote) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_note(
              note_id, created_at_ms, updated_at_ms,
              notebook, tab_domain, title, deleted
            )
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET
              created_at_ms = CASE
                WHEN nj_note.created_at_ms IS NULL OR nj_note.created_at_ms = 0 THEN excluded.created_at_ms
                ELSE nj_note.created_at_ms
              END,
              updated_at_ms=excluded.updated_at_ms,
              notebook=excluded.notebook,
              tab_domain=excluded.tab_domain,
              title=excluded.title,
              deleted=excluded.deleted;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "upsertNote.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, note.id.raw, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, note.createdAtMs)
            sqlite3_bind_int64(stmt, 3, note.updatedAtMs)
            sqlite3_bind_text(stmt, 4, note.notebook, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, note.tabDomain, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, note.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, note.deleted)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "upsertNote.step", rc1) }
        }
        enqueueDirty("note", note.id.raw, "upsert", note.updatedAtMs)
    }

    func deleteNote(_ noteID: NJNoteID) {
        let now = nowMs()
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note
            SET deleted = 1,
                updated_at_ms = ?
            WHERE note_id = ?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "deleteNote.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, now)
            sqlite3_bind_text(stmt, 2, noteID.raw, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "deleteNote.step", rc1) }
        }
        enqueueDirty("note", noteID.raw, "upsert", now)
    }

    func markNoteDeleted(noteID: String) {
        let now = nowMs()
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note
            SET deleted=1, updated_at_ms=?
            WHERE note_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "markNoteDeleted.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, now)
            sqlite3_bind_text(stmt, 2, noteID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "markNoteDeleted.step", rc1) }
        }
        enqueueDirty("note", noteID, "upsert", now)
    }
}
