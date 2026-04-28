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
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_cloud_id, photo_thumb_path,
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
            let photoCloudID = String(cString: sqlite3_column_text(stmt, 4))
            let photoThumbPath = String(cString: sqlite3_column_text(stmt, 5))
            let createdAtMs = sqlite3_column_int64(stmt, 6)
            let updatedAtMs = sqlite3_column_int64(stmt, 7)
            let deleted = Int(sqlite3_column_int64(stmt, 8))

            return NJCalendarItem(
                dateKey: key,
                title: title,
                photoAttachmentID: photoAttachmentID,
                photoLocalID: photoLocalID,
                photoCloudID: photoCloudID,
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
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_cloud_id, photo_thumb_path,
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
            let photoCloudID = String(cString: sqlite3_column_text(stmt, 4))
            let photoThumbPath = String(cString: sqlite3_column_text(stmt, 5))
            let createdAtMs = sqlite3_column_int64(stmt, 6)
            let updatedAtMs = sqlite3_column_int64(stmt, 7)
            let deleted = Int(sqlite3_column_int64(stmt, 8))

            return NJCalendarItem(
                dateKey: key,
                title: title,
                photoAttachmentID: photoAttachmentID,
                photoLocalID: photoLocalID,
                photoCloudID: photoCloudID,
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
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_cloud_id, photo_thumb_path,
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
                let photoCloudID = String(cString: sqlite3_column_text(stmt, 4))
                let photoThumbPath = String(cString: sqlite3_column_text(stmt, 5))
                let createdAtMs = sqlite3_column_int64(stmt, 6)
                let updatedAtMs = sqlite3_column_int64(stmt, 7)
                let deleted = Int(sqlite3_column_int64(stmt, 8))

                out.append(NJCalendarItem(
                    dateKey: key,
                    title: title,
                    photoAttachmentID: photoAttachmentID,
                    photoLocalID: photoLocalID,
                    photoCloudID: photoCloudID,
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
              date_key, title, photo_attachment_id, photo_local_id, photo_cloud_id, photo_thumb_path,
              created_at_ms, updated_at_ms, deleted
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date_key) DO UPDATE SET
              title = excluded.title,
              photo_attachment_id = excluded.photo_attachment_id,
              photo_local_id = excluded.photo_local_id,
              photo_cloud_id = excluded.photo_cloud_id,
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
            sqlite3_bind_text(stmt, 5, item.photoCloudID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, item.photoThumbPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, item.createdAtMs)
            sqlite3_bind_int64(stmt, 8, item.updatedAtMs)
            sqlite3_bind_int64(stmt, 9, Int64(item.deleted))

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

    func backfillThumbPath(attachmentID: String, thumbPath: String) {
        let normalizedAttachmentID = attachmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThumbPath = thumbPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAttachmentID.isEmpty, !normalizedThumbPath.isEmpty else { return }

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_calendar_item
            SET photo_thumb_path = CASE
                    WHEN photo_thumb_path IS NULL OR photo_thumb_path = '' THEN ?
                    ELSE photo_thumb_path
                END
            WHERE photo_attachment_id = ? AND deleted = 0;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "calendar.backfillThumb.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, normalizedThumbPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, normalizedAttachmentID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "calendar.backfillThumb.step", rc1) }
        }
    }

    func listItemsBefore(dateKey: String) -> [NJCalendarItem] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_cloud_id, photo_thumb_path,
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
                let photoCloudID = String(cString: sqlite3_column_text(stmt, 4))
                let photoThumbPath = String(cString: sqlite3_column_text(stmt, 5))
                let createdAtMs = sqlite3_column_int64(stmt, 6)
                let updatedAtMs = sqlite3_column_int64(stmt, 7)
                let deleted = Int(sqlite3_column_int64(stmt, 8))

                out.append(NJCalendarItem(
                    dateKey: key,
                    title: title,
                    photoAttachmentID: photoAttachmentID,
                    photoLocalID: photoLocalID,
                    photoCloudID: photoCloudID,
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
                SELECT planning_key, kind, target_key, note, proton_json, created_at_ms, updated_at_ms, deleted
                FROM nj_planning_note
                WHERE planning_key = ?
                LIMIT 1;
                """
                : """
                SELECT planning_key, kind, target_key, note, proton_json, created_at_ms, updated_at_ms, deleted
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
                planning_key, kind, target_key, note, proton_json, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(planning_key) DO UPDATE SET
                kind = excluded.kind,
                target_key = excluded.target_key,
                note = excluded.note,
                proton_json = excluded.proton_json,
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
            sqlite3_bind_text(stmt, 5, n.protonJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, n.createdAtMs)
            sqlite3_bind_int64(stmt, 7, n.updatedAtMs)
            sqlite3_bind_int64(stmt, 8, Int64(n.deleted))

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "planningNote.upsert.step", rc1) }
        }
        if !DBDirtyQueueTable.isInPullScope() {
            enqueueDirty("planning_note", n.planningKey, "upsert", n.updatedAtMs)
        }
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
            "proton_json": n.protonJSON,
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
        let protonJSON = (fields["proton_json"] as? String) ?? (fields["protonJSON"] as? String) ?? ""
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

        let existing = loadNoteByPlanningKeyIncludingDeleted(planningKey: planningKey)
        let mergedNote: String = {
            if !note.isEmpty { return note }
            return existing?.note ?? ""
        }()
        let mergedProtonJSON: String = {
            if !protonJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return protonJSON }
            return existing?.protonJSON ?? ""
        }()

        let noteRow = NJPlanningNote(
            planningKey: planningKey,
            kind: resolvedKind,
            targetKey: resolvedTarget,
            note: mergedNote,
            protonJSON: mergedProtonJSON,
            createdAtMs: createdAt > 0 ? createdAt : (existing?.createdAtMs ?? 0),
            updatedAtMs: updatedAt,
            deleted: deleted
        )

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_planning_note(
                planning_key, kind, target_key, note, proton_json, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(planning_key) DO UPDATE SET
                kind = excluded.kind,
                target_key = excluded.target_key,
                note = excluded.note,
                proton_json = excluded.proton_json,
                created_at_ms = CASE
                    WHEN nj_planning_note.created_at_ms IS NULL OR nj_planning_note.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_planning_note.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "planningNote.applyRemote.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteRow.planningKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, noteRow.kind, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, noteRow.targetKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, noteRow.note, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, noteRow.protonJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, noteRow.createdAtMs)
            sqlite3_bind_int64(stmt, 7, noteRow.updatedAtMs)
            sqlite3_bind_int64(stmt, 8, Int64(noteRow.deleted))

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "planningNote.applyRemote.step", rc1) }
        }
    }

    private func readRow(_ stmt: OpaquePointer?) -> NJPlanningNote {
        let planningKey = String(cString: sqlite3_column_text(stmt, 0))
        let kind = String(cString: sqlite3_column_text(stmt, 1))
        let targetKey = String(cString: sqlite3_column_text(stmt, 2))
        let note = String(cString: sqlite3_column_text(stmt, 3))
        let protonJSON = String(cString: sqlite3_column_text(stmt, 4))
        let createdAt = sqlite3_column_int64(stmt, 5)
        let updatedAt = sqlite3_column_int64(stmt, 6)
        let deleted = Int(sqlite3_column_int64(stmt, 7))
        return NJPlanningNote(
            planningKey: planningKey,
            kind: kind,
            targetKey: targetKey,
            note: note,
            protonJSON: protonJSON,
            createdAtMs: createdAt,
            updatedAtMs: updatedAt,
            deleted: deleted
        )
    }
}

final class DBFinanceMacroEventTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func list(startKey: String, endKey: String) -> [NJFinanceMacroEvent] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT event_id, date_key, title, category, region, time_text, impact, source, notes,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_finance_macro_event
            WHERE deleted = 0 AND date_key BETWEEN ? AND ?
            ORDER BY date_key ASC, time_text ASC, updated_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, startKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, endKey, -1, SQLITE_TRANSIENT)

            var out: [NJFinanceMacroEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(readEvent(stmt))
            }
            return out
        }
    }

    func list(dateKey: String) -> [NJFinanceMacroEvent] {
        list(startKey: dateKey, endKey: dateKey)
    }

    func upsert(_ row: NJFinanceMacroEvent) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_macro_event(
                event_id, date_key, title, category, region, time_text, impact, source, notes,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
                date_key = excluded.date_key,
                title = excluded.title,
                category = excluded.category,
                region = excluded.region,
                time_text = excluded.time_text,
                impact = excluded.impact,
                source = excluded.source,
                notes = excluded.notes,
                created_at_ms = CASE
                    WHEN nj_finance_macro_event.created_at_ms IS NULL OR nj_finance_macro_event.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_finance_macro_event.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, row.eventID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.region, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, row.timeText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, row.impact, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, row.source, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, row.notes, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 10, row.createdAtMs)
            sqlite3_bind_int64(stmt, 11, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 12, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_macro_event", row.eventID, "upsert", row.updatedAtMs)
    }

    func markDeleted(eventID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_finance_macro_event
            SET deleted = 1, updated_at_ms = ?
            WHERE event_id = ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, eventID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_macro_event", eventID, "upsert", nowMs)
    }

    func loadFields(eventID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT event_id, date_key, title, category, region, time_text, impact, source, notes,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_finance_macro_event
            WHERE event_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, eventID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = readEvent(stmt)
            return [
                "event_id": row.eventID,
                "date_key": row.dateKey,
                "title": row.title,
                "category": row.category,
                "region": row.region,
                "time_text": row.timeText,
                "impact": row.impact,
                "source": row.source,
                "notes": row.notes,
                "created_at_ms": row.createdAtMs,
                "updated_at_ms": row.updatedAtMs,
                "deleted": row.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let eventID = (fields["event_id"] as? String) ?? (fields["eventID"] as? String) ?? ""
        guard !eventID.isEmpty else { return }
        let row = NJFinanceMacroEvent(
            eventID: eventID,
            dateKey: (fields["date_key"] as? String) ?? (fields["dateKey"] as? String) ?? "",
            title: (fields["title"] as? String) ?? "",
            category: (fields["category"] as? String) ?? "",
            region: (fields["region"] as? String) ?? "",
            timeText: (fields["time_text"] as? String) ?? (fields["timeText"] as? String) ?? "",
            impact: (fields["impact"] as? String) ?? "",
            source: (fields["source"] as? String) ?? "",
            notes: (fields["notes"] as? String) ?? "",
            createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
            updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
            deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
        )
        upsert(row)
    }

    private func readEvent(_ stmt: OpaquePointer?) -> NJFinanceMacroEvent {
        NJFinanceMacroEvent(
            eventID: String(cString: sqlite3_column_text(stmt, 0)),
            dateKey: String(cString: sqlite3_column_text(stmt, 1)),
            title: String(cString: sqlite3_column_text(stmt, 2)),
            category: String(cString: sqlite3_column_text(stmt, 3)),
            region: String(cString: sqlite3_column_text(stmt, 4)),
            timeText: String(cString: sqlite3_column_text(stmt, 5)),
            impact: String(cString: sqlite3_column_text(stmt, 6)),
            source: String(cString: sqlite3_column_text(stmt, 7)),
            notes: String(cString: sqlite3_column_text(stmt, 8)),
            createdAtMs: sqlite3_column_int64(stmt, 9),
            updatedAtMs: sqlite3_column_int64(stmt, 10),
            deleted: sqlite3_column_int64(stmt, 11)
        )
    }
}

final class DBFinanceDailyBriefTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func load(dateKey: String) -> NJFinanceDailyBrief? {
        load(dateKey: dateKey, includeDeleted: false)
    }

    func loadIncludingDeleted(dateKey: String) -> NJFinanceDailyBrief? {
        load(dateKey: dateKey, includeDeleted: true)
    }

    private func load(dateKey: String, includeDeleted: Bool) -> NJFinanceDailyBrief? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = includeDeleted
                ? """
                SELECT date_key, news_summary, expectation_summary, watch_items, bias,
                       created_at_ms, updated_at_ms, deleted
                FROM nj_finance_daily_brief
                WHERE date_key = ?
                LIMIT 1;
                """
                : """
                SELECT date_key, news_summary, expectation_summary, watch_items, bias,
                       created_at_ms, updated_at_ms, deleted
                FROM nj_finance_daily_brief
                WHERE date_key = ? AND deleted = 0
                LIMIT 1;
                """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, dateKey, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readBrief(stmt)
        }
    }

    func list(startKey: String, endKey: String) -> [NJFinanceDailyBrief] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT date_key, news_summary, expectation_summary, watch_items, bias,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_finance_daily_brief
            WHERE deleted = 0 AND date_key BETWEEN ? AND ?
            ORDER BY date_key ASC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, startKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, endKey, -1, SQLITE_TRANSIENT)

            var out: [NJFinanceDailyBrief] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(readBrief(stmt))
            }
            return out
        }
    }

    func upsert(_ row: NJFinanceDailyBrief) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_daily_brief(
                date_key, news_summary, expectation_summary, watch_items, bias,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date_key) DO UPDATE SET
                news_summary = excluded.news_summary,
                expectation_summary = excluded.expectation_summary,
                watch_items = excluded.watch_items,
                bias = excluded.bias,
                created_at_ms = CASE
                    WHEN nj_finance_daily_brief.created_at_ms IS NULL OR nj_finance_daily_brief.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_finance_daily_brief.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, row.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.newsSummary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.expectationSummary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.watchItems, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.bias, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, row.createdAtMs)
            sqlite3_bind_int64(stmt, 7, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 8, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_daily_brief", row.dateKey, "upsert", row.updatedAtMs)
    }

    func markDeleted(dateKey: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_finance_daily_brief
            SET deleted = 1, updated_at_ms = ?
            WHERE date_key = ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, dateKey, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_daily_brief", dateKey, "upsert", nowMs)
    }

    func loadFields(dateKey: String) -> [String: Any]? {
        guard let row = loadIncludingDeleted(dateKey: dateKey) else { return nil }
        return [
            "date_key": row.dateKey,
            "news_summary": row.newsSummary,
            "expectation_summary": row.expectationSummary,
            "watch_items": row.watchItems,
            "bias": row.bias,
            "created_at_ms": row.createdAtMs,
            "updated_at_ms": row.updatedAtMs,
            "deleted": row.deleted
        ]
    }

    func applyRemote(_ fields: [String: Any]) {
        let dateKey = (fields["date_key"] as? String) ?? (fields["dateKey"] as? String) ?? ""
        guard !dateKey.isEmpty else { return }
        let row = NJFinanceDailyBrief(
            dateKey: dateKey,
            newsSummary: (fields["news_summary"] as? String) ?? (fields["newsSummary"] as? String) ?? "",
            expectationSummary: (fields["expectation_summary"] as? String) ?? (fields["expectationSummary"] as? String) ?? "",
            watchItems: (fields["watch_items"] as? String) ?? (fields["watchItems"] as? String) ?? "",
            bias: (fields["bias"] as? String) ?? "",
            createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
            updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
            deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
        )
        upsert(row)
    }

    private func readBrief(_ stmt: OpaquePointer?) -> NJFinanceDailyBrief {
        NJFinanceDailyBrief(
            dateKey: String(cString: sqlite3_column_text(stmt, 0)),
            newsSummary: String(cString: sqlite3_column_text(stmt, 1)),
            expectationSummary: String(cString: sqlite3_column_text(stmt, 2)),
            watchItems: String(cString: sqlite3_column_text(stmt, 3)),
            bias: String(cString: sqlite3_column_text(stmt, 4)),
            createdAtMs: sqlite3_column_int64(stmt, 5),
            updatedAtMs: sqlite3_column_int64(stmt, 6),
            deleted: sqlite3_column_int64(stmt, 7)
        )
    }
}

final class DBFinanceResearchSessionTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func list() -> [NJFinanceResearchSession] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT session_id, title, theme_id, premise_id, status, summary, last_message_at_ms,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_finance_research_session
            WHERE deleted = 0
            ORDER BY updated_at_ms DESC, created_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var out: [NJFinanceResearchSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(read(stmt)) }
            return out
        }
    }

    func load(sessionID: String) -> NJFinanceResearchSession? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT session_id, title, theme_id, premise_id, status, summary, last_message_at_ms,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_finance_research_session
            WHERE session_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return read(stmt)
        }
    }

    func upsert(_ row: NJFinanceResearchSession) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_research_session(
                session_id, title, theme_id, premise_id, status, summary, last_message_at_ms,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                title = excluded.title,
                theme_id = excluded.theme_id,
                premise_id = excluded.premise_id,
                status = excluded.status,
                summary = excluded.summary,
                last_message_at_ms = excluded.last_message_at_ms,
                created_at_ms = CASE WHEN nj_finance_research_session.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_finance_research_session.created_at_ms END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.sessionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.themeID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.premiseID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, row.summary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, row.lastMessageAtMs)
            sqlite3_bind_int64(stmt, 8, row.createdAtMs)
            sqlite3_bind_int64(stmt, 9, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 10, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_research_session", row.sessionID, "upsert", row.updatedAtMs)
    }

    func loadFields(sessionID: String) -> [String: Any]? {
        guard let row = load(sessionID: sessionID) else { return nil }
        return [
            "session_id": row.sessionID,
            "title": row.title,
            "theme_id": row.themeID,
            "premise_id": row.premiseID,
            "status": row.status,
            "summary": row.summary,
            "last_message_at_ms": row.lastMessageAtMs,
            "created_at_ms": row.createdAtMs,
            "updated_at_ms": row.updatedAtMs,
            "deleted": row.deleted
        ]
    }

    func applyRemote(_ fields: [String: Any]) {
        let sessionID = (fields["session_id"] as? String) ?? ""
        guard !sessionID.isEmpty else { return }
        upsert(
            NJFinanceResearchSession(
                sessionID: sessionID,
                title: (fields["title"] as? String) ?? "",
                themeID: (fields["theme_id"] as? String) ?? "",
                premiseID: (fields["premise_id"] as? String) ?? "",
                status: (fields["status"] as? String) ?? "",
                summary: (fields["summary"] as? String) ?? "",
                lastMessageAtMs: (fields["last_message_at_ms"] as? Int64) ?? ((fields["last_message_at_ms"] as? NSNumber)?.int64Value ?? 0),
                createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
                updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
                deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
            )
        )
    }

    private func read(_ stmt: OpaquePointer?) -> NJFinanceResearchSession {
        NJFinanceResearchSession(
            sessionID: String(cString: sqlite3_column_text(stmt, 0)),
            title: String(cString: sqlite3_column_text(stmt, 1)),
            themeID: String(cString: sqlite3_column_text(stmt, 2)),
            premiseID: String(cString: sqlite3_column_text(stmt, 3)),
            status: String(cString: sqlite3_column_text(stmt, 4)),
            summary: String(cString: sqlite3_column_text(stmt, 5)),
            lastMessageAtMs: sqlite3_column_int64(stmt, 6),
            createdAtMs: sqlite3_column_int64(stmt, 7),
            updatedAtMs: sqlite3_column_int64(stmt, 8),
            deleted: sqlite3_column_int64(stmt, 9)
        )
    }
}

final class DBFinanceResearchMessageTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func list(sessionID: String) -> [NJFinanceResearchMessage] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT message_id, session_id, role, body, source_refs_json, retrieval_context_json,
                   task_request_json, sync_status, created_at_ms, updated_at_ms, deleted
            FROM nj_finance_research_message
            WHERE deleted = 0 AND session_id = ?
            ORDER BY created_at_ms ASC, updated_at_ms ASC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)
            var out: [NJFinanceResearchMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(read(stmt)) }
            return out
        }
    }

    func upsert(_ row: NJFinanceResearchMessage) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_research_message(
                message_id, session_id, role, body, source_refs_json, retrieval_context_json,
                task_request_json, sync_status, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(message_id) DO UPDATE SET
                session_id = excluded.session_id,
                role = excluded.role,
                body = excluded.body,
                source_refs_json = excluded.source_refs_json,
                retrieval_context_json = excluded.retrieval_context_json,
                task_request_json = excluded.task_request_json,
                sync_status = excluded.sync_status,
                created_at_ms = CASE WHEN nj_finance_research_message.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_finance_research_message.created_at_ms END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.messageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.sessionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.role, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.body, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.sourceRefsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, row.retrievalContextJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, row.taskRequestJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, row.syncStatus, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 9, row.createdAtMs)
            sqlite3_bind_int64(stmt, 10, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 11, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_research_message", row.messageID, "upsert", row.updatedAtMs)
    }

    func loadFields(messageID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT message_id, session_id, role, body, source_refs_json, retrieval_context_json,
                   task_request_json, sync_status, created_at_ms, updated_at_ms, deleted
            FROM nj_finance_research_message
            WHERE message_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, messageID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = read(stmt)
            return [
                "message_id": row.messageID,
                "session_id": row.sessionID,
                "role": row.role,
                "body": row.body,
                "source_refs_json": row.sourceRefsJSON,
                "retrieval_context_json": row.retrievalContextJSON,
                "task_request_json": row.taskRequestJSON,
                "sync_status": row.syncStatus,
                "created_at_ms": row.createdAtMs,
                "updated_at_ms": row.updatedAtMs,
                "deleted": row.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let messageID = (fields["message_id"] as? String) ?? ""
        guard !messageID.isEmpty else { return }
        upsert(
            NJFinanceResearchMessage(
                messageID: messageID,
                sessionID: (fields["session_id"] as? String) ?? "",
                role: (fields["role"] as? String) ?? "",
                body: (fields["body"] as? String) ?? "",
                sourceRefsJSON: (fields["source_refs_json"] as? String) ?? "",
                retrievalContextJSON: (fields["retrieval_context_json"] as? String) ?? "",
                taskRequestJSON: (fields["task_request_json"] as? String) ?? "",
                syncStatus: (fields["sync_status"] as? String) ?? "",
                createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
                updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
                deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
            )
        )
    }

    private func read(_ stmt: OpaquePointer?) -> NJFinanceResearchMessage {
        NJFinanceResearchMessage(
            messageID: String(cString: sqlite3_column_text(stmt, 0)),
            sessionID: String(cString: sqlite3_column_text(stmt, 1)),
            role: String(cString: sqlite3_column_text(stmt, 2)),
            body: String(cString: sqlite3_column_text(stmt, 3)),
            sourceRefsJSON: String(cString: sqlite3_column_text(stmt, 4)),
            retrievalContextJSON: String(cString: sqlite3_column_text(stmt, 5)),
            taskRequestJSON: String(cString: sqlite3_column_text(stmt, 6)),
            syncStatus: String(cString: sqlite3_column_text(stmt, 7)),
            createdAtMs: sqlite3_column_int64(stmt, 8),
            updatedAtMs: sqlite3_column_int64(stmt, 9),
            deleted: sqlite3_column_int64(stmt, 10)
        )
    }
}

final class DBFinanceResearchTaskTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void
    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) { self.db = db; self.enqueueDirty = enqueueDirty }
    func list(sessionID: String) -> [NJFinanceResearchTask] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT task_id, session_id, message_id, task_kind, instruction, status, priority, result_summary, result_refs_json,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_finance_research_task
            WHERE deleted = 0 AND session_id = ?
            ORDER BY updated_at_ms DESC, created_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)
            var out: [NJFinanceResearchTask] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(read(stmt)) }
            return out
        }
    }
    func upsert(_ row: NJFinanceResearchTask) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_research_task(
                task_id, session_id, message_id, task_kind, instruction, status, priority, result_summary, result_refs_json,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                session_id = excluded.session_id, message_id = excluded.message_id, task_kind = excluded.task_kind,
                instruction = excluded.instruction, status = excluded.status, priority = excluded.priority,
                result_summary = excluded.result_summary, result_refs_json = excluded.result_refs_json,
                created_at_ms = CASE WHEN nj_finance_research_task.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_finance_research_task.created_at_ms END,
                updated_at_ms = excluded.updated_at_ms, deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.taskID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.sessionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.messageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.taskKind, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.instruction, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, row.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, row.priority)
            sqlite3_bind_text(stmt, 8, row.resultSummary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, row.resultRefsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 10, row.createdAtMs)
            sqlite3_bind_int64(stmt, 11, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 12, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_research_task", row.taskID, "upsert", row.updatedAtMs)
    }
    func loadFields(taskID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "SELECT task_id, session_id, message_id, task_kind, instruction, status, priority, result_summary, result_refs_json, created_at_ms, updated_at_ms, deleted FROM nj_finance_research_task WHERE task_id = ? LIMIT 1;"
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, taskID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = read(stmt)
            return ["task_id": row.taskID, "session_id": row.sessionID, "message_id": row.messageID, "task_kind": row.taskKind, "instruction": row.instruction, "status": row.status, "priority": row.priority, "result_summary": row.resultSummary, "result_refs_json": row.resultRefsJSON, "created_at_ms": row.createdAtMs, "updated_at_ms": row.updatedAtMs, "deleted": row.deleted]
        }
    }
    func applyRemote(_ fields: [String: Any]) {
        let taskID = (fields["task_id"] as? String) ?? ""
        guard !taskID.isEmpty else { return }
        upsert(NJFinanceResearchTask(taskID: taskID, sessionID: (fields["session_id"] as? String) ?? "", messageID: (fields["message_id"] as? String) ?? "", taskKind: (fields["task_kind"] as? String) ?? "", instruction: (fields["instruction"] as? String) ?? "", status: (fields["status"] as? String) ?? "", priority: (fields["priority"] as? Int64) ?? ((fields["priority"] as? NSNumber)?.int64Value ?? 0), resultSummary: (fields["result_summary"] as? String) ?? "", resultRefsJSON: (fields["result_refs_json"] as? String) ?? "", createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0), updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0), deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)))
    }
    private func read(_ stmt: OpaquePointer?) -> NJFinanceResearchTask {
        NJFinanceResearchTask(taskID: String(cString: sqlite3_column_text(stmt, 0)), sessionID: String(cString: sqlite3_column_text(stmt, 1)), messageID: String(cString: sqlite3_column_text(stmt, 2)), taskKind: String(cString: sqlite3_column_text(stmt, 3)), instruction: String(cString: sqlite3_column_text(stmt, 4)), status: String(cString: sqlite3_column_text(stmt, 5)), priority: sqlite3_column_int64(stmt, 6), resultSummary: String(cString: sqlite3_column_text(stmt, 7)), resultRefsJSON: String(cString: sqlite3_column_text(stmt, 8)), createdAtMs: sqlite3_column_int64(stmt, 9), updatedAtMs: sqlite3_column_int64(stmt, 10), deleted: sqlite3_column_int64(stmt, 11))
    }
}

final class DBFinanceFindingTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void
    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) { self.db = db; self.enqueueDirty = enqueueDirty }
    func list(sessionID: String, premiseID: String = "") -> [NJFinanceFinding] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = premiseID.isEmpty
            ? "SELECT finding_id, session_id, premise_id, stance, summary, confidence, source_refs_json, created_at_ms, updated_at_ms, deleted FROM nj_finance_finding WHERE deleted = 0 AND session_id = ? ORDER BY updated_at_ms DESC;"
            : "SELECT finding_id, session_id, premise_id, stance, summary, confidence, source_refs_json, created_at_ms, updated_at_ms, deleted FROM nj_finance_finding WHERE deleted = 0 AND premise_id = ? ORDER BY updated_at_ms DESC;"
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, premiseID.isEmpty ? sessionID : premiseID, -1, SQLITE_TRANSIENT)
            var out: [NJFinanceFinding] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(read(stmt)) }
            return out
        }
    }
    func upsert(_ row: NJFinanceFinding) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_finding(finding_id, session_id, premise_id, stance, summary, confidence, source_refs_json, created_at_ms, updated_at_ms, deleted)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(finding_id) DO UPDATE SET
                session_id = excluded.session_id, premise_id = excluded.premise_id, stance = excluded.stance, summary = excluded.summary,
                confidence = excluded.confidence, source_refs_json = excluded.source_refs_json,
                created_at_ms = CASE WHEN nj_finance_finding.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_finance_finding.created_at_ms END,
                updated_at_ms = excluded.updated_at_ms, deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.findingID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.sessionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.premiseID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.stance, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.summary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 6, row.confidence)
            sqlite3_bind_text(stmt, 7, row.sourceRefsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, row.createdAtMs)
            sqlite3_bind_int64(stmt, 9, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 10, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_finding", row.findingID, "upsert", row.updatedAtMs)
    }
    func loadFields(findingID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "SELECT finding_id, session_id, premise_id, stance, summary, confidence, source_refs_json, created_at_ms, updated_at_ms, deleted FROM nj_finance_finding WHERE finding_id = ? LIMIT 1;"
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, findingID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = read(stmt)
            return ["finding_id": row.findingID, "session_id": row.sessionID, "premise_id": row.premiseID, "stance": row.stance, "summary": row.summary, "confidence": row.confidence, "source_refs_json": row.sourceRefsJSON, "created_at_ms": row.createdAtMs, "updated_at_ms": row.updatedAtMs, "deleted": row.deleted]
        }
    }
    func applyRemote(_ fields: [String: Any]) {
        let findingID = (fields["finding_id"] as? String) ?? ""
        guard !findingID.isEmpty else { return }
        upsert(NJFinanceFinding(findingID: findingID, sessionID: (fields["session_id"] as? String) ?? "", premiseID: (fields["premise_id"] as? String) ?? "", stance: (fields["stance"] as? String) ?? "", summary: (fields["summary"] as? String) ?? "", confidence: (fields["confidence"] as? Double) ?? ((fields["confidence"] as? NSNumber)?.doubleValue ?? 0), sourceRefsJSON: (fields["source_refs_json"] as? String) ?? "", createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0), updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0), deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)))
    }
    private func read(_ stmt: OpaquePointer?) -> NJFinanceFinding {
        NJFinanceFinding(findingID: String(cString: sqlite3_column_text(stmt, 0)), sessionID: String(cString: sqlite3_column_text(stmt, 1)), premiseID: String(cString: sqlite3_column_text(stmt, 2)), stance: String(cString: sqlite3_column_text(stmt, 3)), summary: String(cString: sqlite3_column_text(stmt, 4)), confidence: sqlite3_column_double(stmt, 5), sourceRefsJSON: String(cString: sqlite3_column_text(stmt, 6)), createdAtMs: sqlite3_column_int64(stmt, 7), updatedAtMs: sqlite3_column_int64(stmt, 8), deleted: sqlite3_column_int64(stmt, 9))
    }
}

final class DBFinanceJournalLinkTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void
    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) { self.db = db; self.enqueueDirty = enqueueDirty }
    func upsert(_ row: NJFinanceJournalLink) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_journal_link(link_id, session_id, message_id, finding_id, note_block_id, excerpt, created_at_ms, updated_at_ms, deleted)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(link_id) DO UPDATE SET session_id = excluded.session_id, message_id = excluded.message_id, finding_id = excluded.finding_id, note_block_id = excluded.note_block_id, excerpt = excluded.excerpt, created_at_ms = CASE WHEN nj_finance_journal_link.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_finance_journal_link.created_at_ms END, updated_at_ms = excluded.updated_at_ms, deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.linkID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 2, row.sessionID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 3, row.messageID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 4, row.findingID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 5, row.noteBlockID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 6, row.excerpt, -1, SQLITE_TRANSIENT); sqlite3_bind_int64(stmt, 7, row.createdAtMs); sqlite3_bind_int64(stmt, 8, row.updatedAtMs); sqlite3_bind_int64(stmt, 9, row.deleted); _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_journal_link", row.linkID, "upsert", row.updatedAtMs)
    }
    func loadFields(linkID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "SELECT link_id, session_id, message_id, finding_id, note_block_id, excerpt, created_at_ms, updated_at_ms, deleted FROM nj_finance_journal_link WHERE link_id = ? LIMIT 1;"
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, linkID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return [
                "link_id": String(cString: sqlite3_column_text(stmt, 0)),
                "session_id": String(cString: sqlite3_column_text(stmt, 1)),
                "message_id": String(cString: sqlite3_column_text(stmt, 2)),
                "finding_id": String(cString: sqlite3_column_text(stmt, 3)),
                "note_block_id": String(cString: sqlite3_column_text(stmt, 4)),
                "excerpt": String(cString: sqlite3_column_text(stmt, 5)),
                "created_at_ms": sqlite3_column_int64(stmt, 6),
                "updated_at_ms": sqlite3_column_int64(stmt, 7),
                "deleted": sqlite3_column_int64(stmt, 8)
            ]
        }
    }
    func applyRemote(_ fields: [String: Any]) {
        let linkID = (fields["link_id"] as? String) ?? ""
        guard !linkID.isEmpty else { return }
        upsert(NJFinanceJournalLink(linkID: linkID, sessionID: (fields["session_id"] as? String) ?? "", messageID: (fields["message_id"] as? String) ?? "", findingID: (fields["finding_id"] as? String) ?? "", noteBlockID: (fields["note_block_id"] as? String) ?? "", excerpt: (fields["excerpt"] as? String) ?? "", createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0), updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0), deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)))
    }
}

final class DBFinanceSourceItemTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void
    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) { self.db = db; self.enqueueDirty = enqueueDirty }
    func listForPremise(_ premiseID: String, limit: Int = 40) -> [NJFinanceSourceItem] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT source_item_id, source_id, source_name, source_url, market_id, premise_ids_json, fetched_at_ms, published_at_ms,
                   content_hash, raw_excerpt, raw_text_ck_asset_path, raw_json, deleted
            FROM nj_finance_source_item
            WHERE deleted = 0 AND premise_ids_json LIKE ?
            ORDER BY fetched_at_ms DESC
            LIMIT ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, "%\(premiseID)%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            var out: [NJFinanceSourceItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(read(stmt)) }
            return out
        }
    }
    func upsert(_ row: NJFinanceSourceItem) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_source_item(source_item_id, source_id, source_name, source_url, market_id, premise_ids_json, fetched_at_ms, published_at_ms, content_hash, raw_excerpt, raw_text_ck_asset_path, raw_json, deleted)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_item_id) DO UPDATE SET source_id = excluded.source_id, source_name = excluded.source_name, source_url = excluded.source_url, market_id = excluded.market_id, premise_ids_json = excluded.premise_ids_json, fetched_at_ms = excluded.fetched_at_ms, published_at_ms = excluded.published_at_ms, content_hash = excluded.content_hash, raw_excerpt = excluded.raw_excerpt, raw_text_ck_asset_path = excluded.raw_text_ck_asset_path, raw_json = excluded.raw_json, deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.sourceItemID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 2, row.sourceID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 3, row.sourceName, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 4, row.sourceURL, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 5, row.marketID, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 6, row.premiseIDsJSON, -1, SQLITE_TRANSIENT); sqlite3_bind_int64(stmt, 7, row.fetchedAtMs); sqlite3_bind_int64(stmt, 8, row.publishedAtMs); sqlite3_bind_text(stmt, 9, row.contentHash, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 10, row.rawExcerpt, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 11, row.rawTextCKAssetPath, -1, SQLITE_TRANSIENT); sqlite3_bind_text(stmt, 12, row.rawJSON, -1, SQLITE_TRANSIENT); sqlite3_bind_int64(stmt, 13, row.deleted); _ = sqlite3_step(stmt)
        }
        enqueueDirty("finance_source_item", row.sourceItemID, "upsert", row.fetchedAtMs)
    }
    func loadFields(sourceItemID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "SELECT source_item_id, source_id, source_name, source_url, market_id, premise_ids_json, fetched_at_ms, published_at_ms, content_hash, raw_excerpt, raw_text_ck_asset_path, raw_json, deleted FROM nj_finance_source_item WHERE source_item_id = ? LIMIT 1;"
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sourceItemID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = read(stmt)
            return ["source_item_id": row.sourceItemID, "source_id": row.sourceID, "source_name": row.sourceName, "source_url": row.sourceURL, "market_id": row.marketID, "premise_ids_json": row.premiseIDsJSON, "fetched_at_ms": row.fetchedAtMs, "published_at_ms": row.publishedAtMs, "content_hash": row.contentHash, "raw_excerpt": row.rawExcerpt, "raw_text_ck_asset_path": row.rawTextCKAssetPath, "raw_json": row.rawJSON, "deleted": row.deleted]
        }
    }
    func applyRemote(_ fields: [String: Any]) {
        let sourceItemID = (fields["source_item_id"] as? String) ?? ""
        guard !sourceItemID.isEmpty else { return }
        upsert(NJFinanceSourceItem(sourceItemID: sourceItemID, sourceID: (fields["source_id"] as? String) ?? "", sourceName: (fields["source_name"] as? String) ?? "", sourceURL: (fields["source_url"] as? String) ?? "", marketID: (fields["market_id"] as? String) ?? "", premiseIDsJSON: (fields["premise_ids_json"] as? String) ?? "", fetchedAtMs: (fields["fetched_at_ms"] as? Int64) ?? ((fields["fetched_at_ms"] as? NSNumber)?.int64Value ?? 0), publishedAtMs: (fields["published_at_ms"] as? Int64) ?? ((fields["published_at_ms"] as? NSNumber)?.int64Value ?? 0), contentHash: (fields["content_hash"] as? String) ?? "", rawExcerpt: (fields["raw_excerpt"] as? String) ?? "", rawTextCKAssetPath: (fields["raw_text_ck_asset_path"] as? String) ?? "", rawJSON: (fields["raw_json"] as? String) ?? "", deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)))
    }
    private func read(_ stmt: OpaquePointer?) -> NJFinanceSourceItem {
        NJFinanceSourceItem(sourceItemID: String(cString: sqlite3_column_text(stmt, 0)), sourceID: String(cString: sqlite3_column_text(stmt, 1)), sourceName: String(cString: sqlite3_column_text(stmt, 2)), sourceURL: String(cString: sqlite3_column_text(stmt, 3)), marketID: String(cString: sqlite3_column_text(stmt, 4)), premiseIDsJSON: String(cString: sqlite3_column_text(stmt, 5)), fetchedAtMs: sqlite3_column_int64(stmt, 6), publishedAtMs: sqlite3_column_int64(stmt, 7), contentHash: String(cString: sqlite3_column_text(stmt, 8)), rawExcerpt: String(cString: sqlite3_column_text(stmt, 9)), rawTextCKAssetPath: String(cString: sqlite3_column_text(stmt, 10)), rawJSON: String(cString: sqlite3_column_text(stmt, 11)), deleted: sqlite3_column_int64(stmt, 12))
    }
}

final class DBFinanceTransactionTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func listRecent(limit: Int = 200) -> [NJFinanceTransaction] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT transaction_id, fingerprint, source_type, account_id, account_label, external_ref,
                   occurred_at_ms, date_key, merchant_name, amount_minor, currency_code, direction,
                   analysis_nature, category, tag_text, fx_rate_to_cny, amount_cny_minor, status, counterparty,
                   item_name, details, note, import_batch_id, source_file_name, raw_payload_json, created_at_ms,
                   updated_at_ms, deleted
            FROM nj_finance_transaction
            WHERE deleted = 0
            ORDER BY occurred_at_ms DESC, updated_at_ms DESC
            LIMIT ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(max(1, limit)))
            var out: [NJFinanceTransaction] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(read(stmt))
            }
            return out
        }
    }

    func list(startKey: String, endKey: String) -> [NJFinanceTransaction] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT transaction_id, fingerprint, source_type, account_id, account_label, external_ref,
                   occurred_at_ms, date_key, merchant_name, amount_minor, currency_code, direction,
                   analysis_nature, category, tag_text, fx_rate_to_cny, amount_cny_minor, status, counterparty,
                   item_name, details, note, import_batch_id, source_file_name, raw_payload_json, created_at_ms,
                   updated_at_ms, deleted
            FROM nj_finance_transaction
            WHERE deleted = 0 AND date_key BETWEEN ? AND ?
            ORDER BY occurred_at_ms DESC, updated_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, startKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, endKey, -1, SQLITE_TRANSIENT)
            var out: [NJFinanceTransaction] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(read(stmt))
            }
            return out
        }
    }

    func load(transactionID: String) -> NJFinanceTransaction? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT transaction_id, fingerprint, source_type, account_id, account_label, external_ref,
                   occurred_at_ms, date_key, merchant_name, amount_minor, currency_code, direction,
                   analysis_nature, category, tag_text, fx_rate_to_cny, amount_cny_minor, status, counterparty,
                   item_name, details, note, import_batch_id, source_file_name, raw_payload_json, created_at_ms,
                   updated_at_ms, deleted
            FROM nj_finance_transaction
            WHERE transaction_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, transactionID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return read(stmt)
        }
    }

    func loadByFingerprint(_ fingerprint: String) -> NJFinanceTransaction? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT transaction_id, fingerprint, source_type, account_id, account_label, external_ref,
                   occurred_at_ms, date_key, merchant_name, amount_minor, currency_code, direction,
                   analysis_nature, category, tag_text, fx_rate_to_cny, amount_cny_minor, status, counterparty,
                   item_name, details, note, import_batch_id, source_file_name, raw_payload_json, created_at_ms,
                   updated_at_ms, deleted
            FROM nj_finance_transaction
            WHERE fingerprint = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fingerprint, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return read(stmt)
        }
    }

    func upsert(_ row: NJFinanceTransaction, enqueue: Bool = true) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_finance_transaction(
                transaction_id, fingerprint, source_type, account_id, account_label, external_ref,
                occurred_at_ms, date_key, merchant_name, amount_minor, currency_code, direction,
                analysis_nature, category, tag_text, fx_rate_to_cny, amount_cny_minor, status, counterparty,
                item_name, details, note, import_batch_id, source_file_name, raw_payload_json, created_at_ms,
                updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(transaction_id) DO UPDATE SET
                fingerprint = excluded.fingerprint,
                source_type = excluded.source_type,
                account_id = excluded.account_id,
                account_label = excluded.account_label,
                external_ref = excluded.external_ref,
                occurred_at_ms = excluded.occurred_at_ms,
                date_key = excluded.date_key,
                merchant_name = excluded.merchant_name,
                amount_minor = excluded.amount_minor,
                currency_code = excluded.currency_code,
                direction = excluded.direction,
                analysis_nature = excluded.analysis_nature,
                category = excluded.category,
                tag_text = excluded.tag_text,
                fx_rate_to_cny = excluded.fx_rate_to_cny,
                amount_cny_minor = excluded.amount_cny_minor,
                status = excluded.status,
                counterparty = excluded.counterparty,
                item_name = excluded.item_name,
                details = excluded.details,
                note = excluded.note,
                import_batch_id = excluded.import_batch_id,
                source_file_name = excluded.source_file_name,
                raw_payload_json = excluded.raw_payload_json,
                created_at_ms = CASE
                    WHEN nj_finance_transaction.created_at_ms IS NULL OR nj_finance_transaction.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_finance_transaction.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, row.transactionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.fingerprint, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.sourceType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.accountID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.accountLabel, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, row.externalRef, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, row.occurredAtMs)
            sqlite3_bind_text(stmt, 8, row.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, row.merchantName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 10, row.amountMinor)
            sqlite3_bind_text(stmt, 11, row.currencyCode, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 12, row.direction, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 13, row.analysisNature, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 14, row.category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 15, row.tagText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 16, row.fxRateToCNY)
            sqlite3_bind_int64(stmt, 17, row.amountCNYMinor)
            sqlite3_bind_text(stmt, 18, row.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 19, row.counterparty, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 20, row.itemName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 21, row.details, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 22, row.note, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 23, row.importBatchID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 24, row.sourceFileName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 25, row.rawPayloadJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 26, row.createdAtMs)
            sqlite3_bind_int64(stmt, 27, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 28, row.deleted)
            _ = sqlite3_step(stmt)
        }
        if enqueue {
            enqueueDirty("finance_transaction", row.transactionID, "upsert", row.updatedAtMs)
        }
    }

    func loadFields(transactionID: String) -> [String: Any]? {
        guard let row = load(transactionID: transactionID) else { return nil }
        return [
            "transaction_id": row.transactionID,
            "fingerprint": row.fingerprint,
            "source_type": row.sourceType,
            "account_id": row.accountID,
            "account_label": row.accountLabel,
            "external_ref": row.externalRef,
            "occurred_at_ms": row.occurredAtMs,
            "date_key": row.dateKey,
            "merchant_name": row.merchantName,
            "amount_minor": row.amountMinor,
            "currency_code": row.currencyCode,
            "direction": row.direction,
            "analysis_nature": row.analysisNature,
            "category": row.category,
            "tag_text": row.tagText,
            "fx_rate_to_cny": row.fxRateToCNY,
            "amount_cny_minor": row.amountCNYMinor,
            "status": row.status,
            "counterparty": row.counterparty,
            "item_name": row.itemName,
            "details": row.details,
            "note": row.note,
            "import_batch_id": row.importBatchID,
            "source_file_name": row.sourceFileName,
            "raw_payload_json": row.rawPayloadJSON,
            "created_at_ms": row.createdAtMs,
            "updated_at_ms": row.updatedAtMs,
            "deleted": row.deleted
        ]
    }

    func applyRemote(_ fields: [String: Any]) {
        let transactionID = (fields["transaction_id"] as? String) ?? (fields["transactionID"] as? String) ?? ""
        guard !transactionID.isEmpty else { return }
        upsert(
            NJFinanceTransaction(
                transactionID: transactionID,
                fingerprint: (fields["fingerprint"] as? String) ?? "",
                sourceType: (fields["source_type"] as? String) ?? (fields["sourceType"] as? String) ?? "",
                accountID: (fields["account_id"] as? String) ?? (fields["accountID"] as? String) ?? "",
                accountLabel: (fields["account_label"] as? String) ?? (fields["accountLabel"] as? String) ?? "",
                externalRef: (fields["external_ref"] as? String) ?? (fields["externalRef"] as? String) ?? "",
                occurredAtMs: (fields["occurred_at_ms"] as? Int64) ?? ((fields["occurred_at_ms"] as? NSNumber)?.int64Value ?? 0),
                dateKey: (fields["date_key"] as? String) ?? (fields["dateKey"] as? String) ?? "",
                merchantName: (fields["merchant_name"] as? String) ?? (fields["merchantName"] as? String) ?? "",
                amountMinor: (fields["amount_minor"] as? Int64) ?? ((fields["amount_minor"] as? NSNumber)?.int64Value ?? 0),
                currencyCode: (fields["currency_code"] as? String) ?? (fields["currencyCode"] as? String) ?? "",
                direction: (fields["direction"] as? String) ?? "",
                analysisNature: (fields["analysis_nature"] as? String) ?? (fields["analysisNature"] as? String) ?? "",
                category: (fields["category"] as? String) ?? "",
                tagText: (fields["tag_text"] as? String) ?? (fields["tagText"] as? String) ?? "",
                fxRateToCNY: (fields["fx_rate_to_cny"] as? Double) ?? ((fields["fx_rate_to_cny"] as? NSNumber)?.doubleValue ?? 1.0),
                amountCNYMinor: (fields["amount_cny_minor"] as? Int64) ?? ((fields["amount_cny_minor"] as? NSNumber)?.int64Value ?? 0),
                status: (fields["status"] as? String) ?? "",
                counterparty: (fields["counterparty"] as? String) ?? "",
                itemName: (fields["item_name"] as? String) ?? (fields["itemName"] as? String) ?? "",
                details: (fields["details"] as? String) ?? "",
                note: (fields["note"] as? String) ?? "",
                importBatchID: (fields["import_batch_id"] as? String) ?? (fields["importBatchID"] as? String) ?? "",
                sourceFileName: (fields["source_file_name"] as? String) ?? (fields["sourceFileName"] as? String) ?? "",
                rawPayloadJSON: (fields["raw_payload_json"] as? String) ?? (fields["rawPayloadJSON"] as? String) ?? "",
                createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
                updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
                deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
            )
        )
    }

    private func text(_ stmt: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).flatMap { String(cString: $0) } ?? ""
    }

    private func read(_ stmt: OpaquePointer?) -> NJFinanceTransaction {
        NJFinanceTransaction(
            transactionID: text(stmt, 0),
            fingerprint: text(stmt, 1),
            sourceType: text(stmt, 2),
            accountID: text(stmt, 3),
            accountLabel: text(stmt, 4),
            externalRef: text(stmt, 5),
            occurredAtMs: sqlite3_column_int64(stmt, 6),
            dateKey: text(stmt, 7),
            merchantName: text(stmt, 8),
            amountMinor: sqlite3_column_int64(stmt, 9),
            currencyCode: text(stmt, 10),
            direction: text(stmt, 11),
            analysisNature: text(stmt, 12),
            category: text(stmt, 13),
            tagText: text(stmt, 14),
            fxRateToCNY: sqlite3_column_double(stmt, 15),
            amountCNYMinor: sqlite3_column_int64(stmt, 16),
            status: text(stmt, 17),
            counterparty: text(stmt, 18),
            itemName: text(stmt, 19),
            details: text(stmt, 20),
            note: text(stmt, 21),
            importBatchID: text(stmt, 22),
            sourceFileName: text(stmt, 23),
            rawPayloadJSON: text(stmt, 24),
            createdAtMs: sqlite3_column_int64(stmt, 25),
            updatedAtMs: sqlite3_column_int64(stmt, 26),
            deleted: sqlite3_column_int64(stmt, 27)
        )
    }
}
