import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBCalendarTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(
        db: SQLiteDB,
        enqueueDirty: @escaping (String, String, String, Int64) -> Void
    ) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func loadItem(dateKey: String) -> NJCalendarItem? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_thumb_path,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_calendar_item
            WHERE date_key = ? AND deleted = 0
            LIMIT 1;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.load.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, dateKey, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let key = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let photoAttachmentID = String(cString: sqlite3_column_text(stmt, 2))
            let photoLocalID = String(cString: sqlite3_column_text(stmt, 3))
            let photoThumbPath = String(cString: sqlite3_column_text(stmt, 4))
            let createdAtMs = sqlite3_column_int64(stmt, 5)
            let updatedAtMs = sqlite3_column_int64(stmt, 6)
            let deleted = Int(sqlite3_column_int64(stmt, 7))

            return NJCalendarItem(
                dateKey: key,
                title: title,
                photoAttachmentID: photoAttachmentID,
                photoLocalID: photoLocalID,
                photoThumbPath: photoThumbPath,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                deleted: deleted
            )
        }
    }

    func loadItemIncludingDeleted(dateKey: String) -> NJCalendarItem? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_thumb_path,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_calendar_item
            WHERE date_key = ?
            LIMIT 1;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.loadAny.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, dateKey, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let key = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let photoAttachmentID = String(cString: sqlite3_column_text(stmt, 2))
            let photoLocalID = String(cString: sqlite3_column_text(stmt, 3))
            let photoThumbPath = String(cString: sqlite3_column_text(stmt, 4))
            let createdAtMs = sqlite3_column_int64(stmt, 5)
            let updatedAtMs = sqlite3_column_int64(stmt, 6)
            let deleted = Int(sqlite3_column_int64(stmt, 7))

            return NJCalendarItem(
                dateKey: key,
                title: title,
                photoAttachmentID: photoAttachmentID,
                photoLocalID: photoLocalID,
                photoThumbPath: photoThumbPath,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                deleted: deleted
            )
        }
    }

    func listItems(startKey: String, endKey: String) -> [NJCalendarItem] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_thumb_path,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_calendar_item
            WHERE deleted = 0 AND date_key BETWEEN ? AND ?
            ORDER BY date_key ASC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.list.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, startKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, endKey, -1, SQLITE_TRANSIENT)

            var out: [NJCalendarItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let photoAttachmentID = String(cString: sqlite3_column_text(stmt, 2))
                let photoLocalID = String(cString: sqlite3_column_text(stmt, 3))
                let photoThumbPath = String(cString: sqlite3_column_text(stmt, 4))
                let createdAtMs = sqlite3_column_int64(stmt, 5)
                let updatedAtMs = sqlite3_column_int64(stmt, 6)
                let deleted = Int(sqlite3_column_int64(stmt, 7))

                out.append(NJCalendarItem(
                    dateKey: key,
                    title: title,
                    photoAttachmentID: photoAttachmentID,
                    photoLocalID: photoLocalID,
                    photoThumbPath: photoThumbPath,
                    createdAtMs: createdAtMs,
                    updatedAtMs: updatedAtMs,
                    deleted: deleted
                ))
            }
            return out
        }
    }

    func upsertItem(_ item: NJCalendarItem) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_calendar_item(
              date_key, title, photo_attachment_id, photo_local_id, photo_thumb_path,
              created_at_ms, updated_at_ms, deleted
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date_key) DO UPDATE SET
              title = excluded.title,
              photo_attachment_id = excluded.photo_attachment_id,
              photo_local_id = excluded.photo_local_id,
              photo_thumb_path = excluded.photo_thumb_path,
              created_at_ms = CASE
                WHEN nj_calendar_item.created_at_ms IS NULL OR nj_calendar_item.created_at_ms = 0
                THEN excluded.created_at_ms
                ELSE nj_calendar_item.created_at_ms
              END,
              updated_at_ms = excluded.updated_at_ms,
              deleted = excluded.deleted;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.upsert.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, item.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, item.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, item.photoAttachmentID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, item.photoLocalID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, item.photoThumbPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, item.createdAtMs)
            sqlite3_bind_int64(stmt, 7, item.updatedAtMs)
            sqlite3_bind_int64(stmt, 8, Int64(item.deleted))

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "calendar.upsert.step", rc1) }
        }
        enqueueDirty("calendar_item", item.dateKey, "upsert", item.updatedAtMs)
    }

    func markDeleted(dateKey: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_calendar_item
            SET deleted = 1,
                updated_at_ms = ?
            WHERE date_key = ?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.delete.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, dateKey, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "calendar.delete.step", rc1) }
        }
        enqueueDirty("calendar_item", dateKey, "upsert", nowMs)
    }

    func listItemsBefore(dateKey: String) -> [NJCalendarItem] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_thumb_path,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_calendar_item
            WHERE deleted = 0 AND date_key < ?
            ORDER BY date_key ASC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.listBefore.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, dateKey, -1, SQLITE_TRANSIENT)

            var out: [NJCalendarItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let photoAttachmentID = String(cString: sqlite3_column_text(stmt, 2))
                let photoLocalID = String(cString: sqlite3_column_text(stmt, 3))
                let photoThumbPath = String(cString: sqlite3_column_text(stmt, 4))
                let createdAtMs = sqlite3_column_int64(stmt, 5)
                let updatedAtMs = sqlite3_column_int64(stmt, 6)
                let deleted = Int(sqlite3_column_int64(stmt, 7))

                out.append(NJCalendarItem(
                    dateKey: key,
                    title: title,
                    photoAttachmentID: photoAttachmentID,
                    photoLocalID: photoLocalID,
                    photoThumbPath: photoThumbPath,
                    createdAtMs: createdAtMs,
                    updatedAtMs: updatedAtMs,
                    deleted: deleted
                ))
            }
            return out
        }
    }
}

final class DBPlanningNoteTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(
        db: SQLiteDB,
        enqueueDirty: @escaping (String, String, String, Int64) -> Void
    ) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func makePlanningKey(kind: String, targetKey: String) -> String {
        "\(kind):\(targetKey)"
    }

    func loadNote(kind: String, targetKey: String) -> NJPlanningNote? {
        loadNoteByPlanningKey(planningKey: makePlanningKey(kind: kind, targetKey: targetKey), includeDeleted: false)
    }

    func loadNoteIncludingDeleted(kind: String, targetKey: String) -> NJPlanningNote? {
        loadNoteByPlanningKey(planningKey: makePlanningKey(kind: kind, targetKey: targetKey), includeDeleted: true)
    }

    func loadNoteByPlanningKeyIncludingDeleted(planningKey: String) -> NJPlanningNote? {
        loadNoteByPlanningKey(planningKey: planningKey, includeDeleted: true)
    }

    private func loadNoteByPlanningKey(planningKey: String, includeDeleted: Bool) -> NJPlanningNote? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = includeDeleted
                ? """
                SELECT planning_key, kind, target_key, note, created_at_ms, updated_at_ms, deleted
                FROM nj_planning_note
                WHERE planning_key = ?
                LIMIT 1;
                """
                : """
                SELECT planning_key, kind, target_key, note, created_at_ms, updated_at_ms, deleted
                FROM nj_planning_note
                WHERE planning_key = ? AND deleted = 0
                LIMIT 1;
                """

            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "planningNote.load.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, planningKey, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readRow(stmt)
        }
    }

    func upsertNote(_ n: NJPlanningNote) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_planning_note(
                planning_key, kind, target_key, note, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(planning_key) DO UPDATE SET
                kind = excluded.kind,
                target_key = excluded.target_key,
                note = excluded.note,
                created_at_ms = CASE
                    WHEN nj_planning_note.created_at_ms IS NULL OR nj_planning_note.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_planning_note.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "planningNote.upsert.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, n.planningKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, n.kind, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, n.targetKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, n.note, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 5, n.createdAtMs)
            sqlite3_bind_int64(stmt, 6, n.updatedAtMs)
            sqlite3_bind_int64(stmt, 7, Int64(n.deleted))

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "planningNote.upsert.step", rc1) }
        }
        enqueueDirty("planning_note", n.planningKey, "upsert", n.updatedAtMs)
    }

    func markDeleted(kind: String, targetKey: String, nowMs: Int64) {
        let key = makePlanningKey(kind: kind, targetKey: targetKey)
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_planning_note
            SET deleted = 1, updated_at_ms = ?
            WHERE planning_key = ?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "planningNote.delete.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "planningNote.delete.step", rc1) }
        }
        enqueueDirty("planning_note", key, "upsert", nowMs)
    }

    func loadPlanningNoteFields(planningKey: String) -> [String: Any]? {
        guard let n = loadNoteByPlanningKeyIncludingDeleted(planningKey: planningKey) else { return nil }
        return [
            "planning_key": n.planningKey,
            "kind": n.kind,
            "target_key": n.targetKey,
            "note": n.note,
            "created_at_ms": n.createdAtMs,
            "updated_at_ms": n.updatedAtMs,
            "deleted": n.deleted
        ]
    }

    func applyRemote(_ fields: [String: Any]) {
        let planningKey = (fields["planning_key"] as? String) ?? (fields["planningKey"] as? String) ?? ""
        if planningKey.isEmpty { return }

        let kind = (fields["kind"] as? String) ?? ""
        let targetKey = (fields["target_key"] as? String) ?? (fields["targetKey"] as? String) ?? ""
        let note = (fields["note"] as? String) ?? ""
        let createdAt = (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0)
        let updatedAt = (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0)
        let deleted = Int((fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0))

        if let existing = loadNoteByPlanningKeyIncludingDeleted(planningKey: planningKey),
           existing.updatedAtMs > updatedAt,
           updatedAt > 0 {
            return
        }

        let resolvedKind: String = {
            if !kind.isEmpty { return kind }
            if let idx = planningKey.firstIndex(of: ":") {
                return String(planningKey[..<idx])
            }
            return ""
        }()
        let resolvedTarget: String = {
            if !targetKey.isEmpty { return targetKey }
            if let idx = planningKey.firstIndex(of: ":") {
                return String(planningKey[planningKey.index(after: idx)...])
            }
            return ""
        }()

        let noteRow = NJPlanningNote(
            planningKey: planningKey,
            kind: resolvedKind,
            targetKey: resolvedTarget,
            note: note,
            createdAtMs: createdAt > 0 ? createdAt : (loadNoteByPlanningKeyIncludingDeleted(planningKey: planningKey)?.createdAtMs ?? 0),
            updatedAtMs: updatedAt,
            deleted: deleted
        )
        upsertNote(noteRow)
    }

    private func readRow(_ stmt: OpaquePointer?) -> NJPlanningNote {
        let planningKey = String(cString: sqlite3_column_text(stmt, 0))
        let kind = String(cString: sqlite3_column_text(stmt, 1))
        let targetKey = String(cString: sqlite3_column_text(stmt, 2))
        let note = String(cString: sqlite3_column_text(stmt, 3))
        let createdAt = sqlite3_column_int64(stmt, 4)
        let updatedAt = sqlite3_column_int64(stmt, 5)
        let deleted = Int(sqlite3_column_int64(stmt, 6))
        return NJPlanningNote(
            planningKey: planningKey,
            kind: kind,
            targetKey: targetKey,
            note: note,
            createdAtMs: createdAt,
            updatedAtMs: updatedAt,
            deleted: deleted
        )
    }
}
