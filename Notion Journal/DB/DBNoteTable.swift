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
        SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, note_type, dominance_mode, is_checklist, card_id, card_category, card_area, card_context, card_status, card_priority, pinned, favorited, deleted
        FROM nj_note
        WHERE deleted = 0
          AND (tab_domain = ? OR tab_domain LIKE ?)
        ORDER BY pinned DESC, updated_at_ms \(order);
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
                let noteTypeRaw = String(cString: sqlite3_column_text(stmt, 6))
                let dominanceModeRaw = String(cString: sqlite3_column_text(stmt, 7))
                let isChecklist = sqlite3_column_int64(stmt, 8)
                let cardID = String(cString: sqlite3_column_text(stmt, 9))
                let cardCategory = String(cString: sqlite3_column_text(stmt, 10))
                let cardArea = String(cString: sqlite3_column_text(stmt, 11))
                let cardContext = String(cString: sqlite3_column_text(stmt, 12))
                let cardStatus = String(cString: sqlite3_column_text(stmt, 13))
                let cardPriority = String(cString: sqlite3_column_text(stmt, 14))
                let pinned = sqlite3_column_int64(stmt, 15)
                let favorited = sqlite3_column_int64(stmt, 16)
                let deleted = sqlite3_column_int64(stmt, 17)

                let rtf = loadRTF(noteID) ?? emptyRTF()

                out.append(NJNote(
                    id: NJNoteID(noteID),
                    createdAtMs: createdMs,
                    updatedAtMs: updatedMs,
                    notebook: notebook,
                    tabDomain: tab,
                    title: title,
                    rtfData: rtf,
                    deleted: deleted,
                    pinned: pinned,
                    favorited: favorited,
                    noteTypeRaw: noteTypeRaw,
                    dominanceModeRaw: dominanceModeRaw,
                    isChecklist: isChecklist,
                    cardID: cardID,
                    cardCategory: cardCategory,
                    cardArea: cardArea,
                    cardContext: cardContext,
                    cardStatus: cardStatus,
                    cardPriority: cardPriority
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
            SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, note_type, dominance_mode, is_checklist, card_id, card_category, card_area, card_context, card_status, card_priority, pinned, favorited, deleted
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
            let noteTypeRaw = String(cString: sqlite3_column_text(stmt, 6))
            let dominanceModeRaw = String(cString: sqlite3_column_text(stmt, 7))
            let isChecklist = sqlite3_column_int64(stmt, 8)
            let cardID = String(cString: sqlite3_column_text(stmt, 9))
            let cardCategory = String(cString: sqlite3_column_text(stmt, 10))
            let cardArea = String(cString: sqlite3_column_text(stmt, 11))
            let cardContext = String(cString: sqlite3_column_text(stmt, 12))
            let cardStatus = String(cString: sqlite3_column_text(stmt, 13))
            let cardPriority = String(cString: sqlite3_column_text(stmt, 14))
            let pinned = sqlite3_column_int64(stmt, 15)
            let favorited = sqlite3_column_int64(stmt, 16)
            let deleted = sqlite3_column_int64(stmt, 17)

            let rtf = loadRTF(noteID) ?? emptyRTF()

            return NJNote(
                id: NJNoteID(noteID),
                createdAtMs: createdMs,
                updatedAtMs: updatedMs,
                notebook: notebook,
                tabDomain: tab,
                title: title,
                rtfData: rtf,
                deleted: deleted,
                pinned: pinned,
                favorited: favorited,
                noteTypeRaw: noteTypeRaw,
                dominanceModeRaw: dominanceModeRaw,
                isChecklist: isChecklist,
                cardID: cardID,
                cardCategory: cardCategory,
                cardArea: cardArea,
                cardContext: cardContext,
                cardStatus: cardStatus,
                cardPriority: cardPriority
            )
        }
    }

    func listFavoriteNotes(notebook: String? = nil) -> [NJNote] {
        let notebookFilter = notebook?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sql: String
        if notebookFilter.isEmpty {
            sql = """
            SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, note_type, dominance_mode, is_checklist, card_id, card_category, card_area, card_context, card_status, card_priority, pinned, favorited, deleted
            FROM nj_note
            WHERE deleted = 0
              AND favorited > 0
            ORDER BY pinned DESC, updated_at_ms DESC;
            """
        } else {
            sql = """
            SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, note_type, dominance_mode, is_checklist, card_id, card_category, card_area, card_context, card_status, card_priority, pinned, favorited, deleted
            FROM nj_note
            WHERE deleted = 0
              AND favorited > 0
              AND notebook = ?
            ORDER BY pinned DESC, updated_at_ms DESC;
            """
        }

        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listFavoriteNotes.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            if !notebookFilter.isEmpty {
                sqlite3_bind_text(stmt, 1, notebookFilter, -1, SQLITE_TRANSIENT)
            }

            var out: [NJNote] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let noteID = String(cString: sqlite3_column_text(stmt, 0))
                let createdMs = sqlite3_column_int64(stmt, 1)
                let updatedMs = sqlite3_column_int64(stmt, 2)
                let notebook = String(cString: sqlite3_column_text(stmt, 3))
                let tab = String(cString: sqlite3_column_text(stmt, 4))
                let title = String(cString: sqlite3_column_text(stmt, 5))
                let noteTypeRaw = String(cString: sqlite3_column_text(stmt, 6))
                let dominanceModeRaw = String(cString: sqlite3_column_text(stmt, 7))
                let isChecklist = sqlite3_column_int64(stmt, 8)
                let cardID = String(cString: sqlite3_column_text(stmt, 9))
                let cardCategory = String(cString: sqlite3_column_text(stmt, 10))
                let cardArea = String(cString: sqlite3_column_text(stmt, 11))
                let cardContext = String(cString: sqlite3_column_text(stmt, 12))
                let cardStatus = String(cString: sqlite3_column_text(stmt, 13))
                let cardPriority = String(cString: sqlite3_column_text(stmt, 14))
                let pinned = sqlite3_column_int64(stmt, 15)
                let favorited = sqlite3_column_int64(stmt, 16)
                let deleted = sqlite3_column_int64(stmt, 17)

                let rtf = loadRTF(noteID) ?? emptyRTF()

                out.append(NJNote(
                    id: NJNoteID(noteID),
                    createdAtMs: createdMs,
                    updatedAtMs: updatedMs,
                    notebook: notebook,
                    tabDomain: tab,
                    title: title,
                    rtfData: rtf,
                    deleted: deleted,
                    pinned: pinned,
                    favorited: favorited,
                    noteTypeRaw: noteTypeRaw,
                    dominanceModeRaw: dominanceModeRaw,
                    isChecklist: isChecklist,
                    cardID: cardID,
                    cardCategory: cardCategory,
                    cardArea: cardArea,
                    cardContext: cardContext,
                    cardStatus: cardStatus,
                    cardPriority: cardPriority
                ))
            }
            return out
        }
    }

    func listNotesByDateRange(startMs: Int64, endMs: Int64) -> [NJNote] {
        let sql = """
        SELECT note_id, created_at_ms, updated_at_ms, notebook, tab_domain, title, note_type, dominance_mode, is_checklist, card_id, card_category, card_area, card_context, card_status, card_priority, pinned, favorited, deleted
        FROM nj_note
        WHERE deleted = 0
          AND created_at_ms >= ?
          AND created_at_ms <= ?
        ORDER BY created_at_ms DESC;
        """

        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listNotesByDateRange.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, startMs)
            sqlite3_bind_int64(stmt, 2, endMs)

            var out: [NJNote] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let noteID = String(cString: sqlite3_column_text(stmt, 0))
                let createdMs = sqlite3_column_int64(stmt, 1)
                let updatedMs = sqlite3_column_int64(stmt, 2)
                let notebook = String(cString: sqlite3_column_text(stmt, 3))
                let tab = String(cString: sqlite3_column_text(stmt, 4))
                let title = String(cString: sqlite3_column_text(stmt, 5))
                let noteTypeRaw = String(cString: sqlite3_column_text(stmt, 6))
                let dominanceModeRaw = String(cString: sqlite3_column_text(stmt, 7))
                let isChecklist = sqlite3_column_int64(stmt, 8)
                let cardID = String(cString: sqlite3_column_text(stmt, 9))
                let cardCategory = String(cString: sqlite3_column_text(stmt, 10))
                let cardArea = String(cString: sqlite3_column_text(stmt, 11))
                let cardContext = String(cString: sqlite3_column_text(stmt, 12))
                let cardStatus = String(cString: sqlite3_column_text(stmt, 13))
                let cardPriority = String(cString: sqlite3_column_text(stmt, 14))
                let pinned = sqlite3_column_int64(stmt, 15)
                let favorited = sqlite3_column_int64(stmt, 16)
                let deleted = sqlite3_column_int64(stmt, 17)

                let rtf = loadRTF(noteID) ?? emptyRTF()

                out.append(NJNote(
                    id: NJNoteID(noteID),
                    createdAtMs: createdMs,
                    updatedAtMs: updatedMs,
                    notebook: notebook,
                    tabDomain: tab,
                    title: title,
                    rtfData: rtf,
                    deleted: deleted,
                    pinned: pinned,
                    favorited: favorited,
                    noteTypeRaw: noteTypeRaw,
                    dominanceModeRaw: dominanceModeRaw,
                    isChecklist: isChecklist,
                    cardID: cardID,
                    cardCategory: cardCategory,
                    cardArea: cardArea,
                    cardContext: cardContext,
                    cardStatus: cardStatus,
                    cardPriority: cardPriority
                ))
            }
            return out
        }
    }

    private func nextCardID() -> String {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "SELECT card_id FROM nj_note WHERE deleted = 0 AND note_type = 'card' AND card_id <> '';"
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "nextCardID.prepare", rc0); return "CRD-0001" }
            defer { sqlite3_finalize(stmt) }

            var maxValue = 0
            while sqlite3_step(stmt) == SQLITE_ROW {
                let raw = String(cString: sqlite3_column_text(stmt, 0))
                let digits = raw.reversed().prefix { $0.isNumber }.reversed()
                if let value = Int(String(digits)) {
                    maxValue = max(maxValue, value)
                }
            }
            return String(format: "CRD-%04d", maxValue + 1)
        }
    }

    func createNote(notebook: String, tabDomain: String, title: String, noteType: NJNoteType = .note) -> NJNote {
        let now = nowMs()
        let id = UUID().uuidString.lowercased()
        let cardID = noteType == .card ? nextCardID() : ""
        let note = NJNote(
            id: NJNoteID(id),
            createdAtMs: now,
            updatedAtMs: now,
            notebook: notebook,
            tabDomain: tabDomain,
            title: title,
            rtfData: emptyRTF(),
            deleted: 0,
            pinned: 0,
            favorited: 0,
            noteTypeRaw: noteType.rawValue,
            cardID: cardID,
            cardStatus: noteType == .card ? "Pending" : "",
            cardPriority: noteType == .card ? "Medium" : ""
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
              notebook, tab_domain, title, note_type, dominance_mode, is_checklist, card_id, card_category, card_area, card_context, card_status, card_priority, pinned, favorited, deleted
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET
              created_at_ms = CASE
                WHEN nj_note.created_at_ms IS NULL OR nj_note.created_at_ms = 0 THEN excluded.created_at_ms
                ELSE nj_note.created_at_ms
              END,
              updated_at_ms=excluded.updated_at_ms,
              notebook=excluded.notebook,
              tab_domain=excluded.tab_domain,
              title=excluded.title,
              note_type=excluded.note_type,
              dominance_mode=excluded.dominance_mode,
              is_checklist=excluded.is_checklist,
              card_id=excluded.card_id,
              card_category=excluded.card_category,
              card_area=excluded.card_area,
              card_context=excluded.card_context,
              card_status=excluded.card_status,
              card_priority=excluded.card_priority,
              pinned=excluded.pinned,
              favorited=excluded.favorited,
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
            sqlite3_bind_text(stmt, 7, note.noteTypeRaw, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, note.dominanceModeRaw, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 9, note.isChecklist)
            sqlite3_bind_text(stmt, 10, note.cardID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 11, note.cardCategory, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 12, note.cardArea, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 13, note.cardContext, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 14, note.cardStatus, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 15, note.cardPriority, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 16, note.pinned)
            sqlite3_bind_int64(stmt, 17, note.favorited)
            sqlite3_bind_int64(stmt, 18, note.deleted)

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

    func setPinned(noteID: String, pinned: Bool) {
        let now = nowMs()
        let val: Int64 = pinned ? 1 : 0
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note
            SET pinned = ?,
                updated_at_ms = ?
            WHERE note_id = ?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "setPinned.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, val)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, noteID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "setPinned.step", rc1) }
        }
        enqueueDirty("note", noteID, "upsert", now)
    }

    func setFavorited(noteID: String, favorited: Bool) {
        let now = nowMs()
        let val: Int64 = favorited ? 1 : 0
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note
            SET favorited = ?,
                updated_at_ms = ?
            WHERE note_id = ?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "setFavorited.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, val)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, noteID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "setFavorited.step", rc1) }
        }
        enqueueDirty("note", noteID, "upsert", now)
    }
}
