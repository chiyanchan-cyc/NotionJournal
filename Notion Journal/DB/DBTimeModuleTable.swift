import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBTimeSlotTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func list(ownerScope: String = "ME") -> [NJTimeSlotRecord] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT time_slot_id, owner_scope, title, category, start_at_ms, end_at_ms, notes,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_time_slot
            WHERE deleted = 0 AND owner_scope = ?
            ORDER BY start_at_ms ASC, updated_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, ownerScope, -1, SQLITE_TRANSIENT)

            var out: [NJTimeSlotRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(readRow(stmt))
            }
            return out
        }
    }

    func upsert(_ row: NJTimeSlotRecord) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_time_slot(
                time_slot_id, owner_scope, title, category, start_at_ms, end_at_ms, notes,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(time_slot_id) DO UPDATE SET
                owner_scope = excluded.owner_scope,
                title = excluded.title,
                category = excluded.category,
                start_at_ms = excluded.start_at_ms,
                end_at_ms = excluded.end_at_ms,
                notes = excluded.notes,
                created_at_ms = CASE
                    WHEN nj_time_slot.created_at_ms IS NULL OR nj_time_slot.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_time_slot.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, row.timeSlotID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.ownerScope, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 5, row.startAtMs)
            sqlite3_bind_int64(stmt, 6, row.endAtMs)
            sqlite3_bind_text(stmt, 7, row.notes, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, row.createdAtMs)
            sqlite3_bind_int64(stmt, 9, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 10, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("time_slot", row.timeSlotID, "upsert", row.updatedAtMs)
    }

    func markDeleted(timeSlotID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_time_slot
            SET deleted = 1, updated_at_ms = ?
            WHERE time_slot_id = ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, timeSlotID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("time_slot", timeSlotID, "upsert", nowMs)
    }

    func loadFields(timeSlotID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT time_slot_id, owner_scope, title, category, start_at_ms, end_at_ms, notes,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_time_slot
            WHERE time_slot_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, timeSlotID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let r = readRow(stmt)
            return [
                "time_slot_id": r.timeSlotID,
                "owner_scope": r.ownerScope,
                "title": r.title,
                "category": r.category,
                "start_at_ms": r.startAtMs,
                "end_at_ms": r.endAtMs,
                "notes": r.notes,
                "created_at_ms": r.createdAtMs,
                "updated_at_ms": r.updatedAtMs,
                "deleted": r.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let id = (fields["time_slot_id"] as? String) ?? ""
        guard !id.isEmpty else { return }
        let r = NJTimeSlotRecord(
            timeSlotID: id,
            ownerScope: (fields["owner_scope"] as? String) ?? "ME",
            title: (fields["title"] as? String) ?? "",
            category: (fields["category"] as? String) ?? "personal",
            startAtMs: (fields["start_at_ms"] as? Int64) ?? ((fields["start_at_ms"] as? NSNumber)?.int64Value ?? 0),
            endAtMs: (fields["end_at_ms"] as? Int64) ?? ((fields["end_at_ms"] as? NSNumber)?.int64Value ?? 0),
            notes: (fields["notes"] as? String) ?? "",
            createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
            updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
            deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
        )
        upsert(r)
    }

    private func readRow(_ stmt: OpaquePointer?) -> NJTimeSlotRecord {
        NJTimeSlotRecord(
            timeSlotID: String(cString: sqlite3_column_text(stmt, 0)),
            ownerScope: String(cString: sqlite3_column_text(stmt, 1)),
            title: String(cString: sqlite3_column_text(stmt, 2)),
            category: String(cString: sqlite3_column_text(stmt, 3)),
            startAtMs: sqlite3_column_int64(stmt, 4),
            endAtMs: sqlite3_column_int64(stmt, 5),
            notes: String(cString: sqlite3_column_text(stmt, 6)),
            createdAtMs: sqlite3_column_int64(stmt, 7),
            updatedAtMs: sqlite3_column_int64(stmt, 8),
            deleted: sqlite3_column_int64(stmt, 9)
        )
    }
}

final class DBPersonalGoalTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func list(ownerScope: String = "ME") -> [NJPersonalGoalRecord] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT goal_id, owner_scope, title, focus, keyword, weekly_target, status,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_personal_goal
            WHERE deleted = 0 AND owner_scope = ?
            ORDER BY updated_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, ownerScope, -1, SQLITE_TRANSIENT)

            var out: [NJPersonalGoalRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(readRow(stmt))
            }
            return out
        }
    }

    func upsert(_ row: NJPersonalGoalRecord) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_personal_goal(
                goal_id, owner_scope, title, focus, keyword, weekly_target, status,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(goal_id) DO UPDATE SET
                owner_scope = excluded.owner_scope,
                title = excluded.title,
                focus = excluded.focus,
                keyword = excluded.keyword,
                weekly_target = excluded.weekly_target,
                status = excluded.status,
                created_at_ms = CASE
                    WHEN nj_personal_goal.created_at_ms IS NULL OR nj_personal_goal.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_personal_goal.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, row.goalID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.ownerScope, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.focus, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.keyword, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, row.weeklyTarget)
            sqlite3_bind_text(stmt, 7, row.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, row.createdAtMs)
            sqlite3_bind_int64(stmt, 9, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 10, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("personal_goal", row.goalID, "upsert", row.updatedAtMs)
    }

    func markDeleted(goalID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_personal_goal
            SET deleted = 1, updated_at_ms = ?
            WHERE goal_id = ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, goalID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("personal_goal", goalID, "upsert", nowMs)
    }

    func loadFields(goalID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT goal_id, owner_scope, title, focus, keyword, weekly_target, status,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_personal_goal
            WHERE goal_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, goalID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let r = readRow(stmt)
            return [
                "goal_id": r.goalID,
                "owner_scope": r.ownerScope,
                "title": r.title,
                "focus": r.focus,
                "keyword": r.keyword,
                "weekly_target": r.weeklyTarget,
                "status": r.status,
                "created_at_ms": r.createdAtMs,
                "updated_at_ms": r.updatedAtMs,
                "deleted": r.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let id = (fields["goal_id"] as? String) ?? ""
        guard !id.isEmpty else { return }
        let r = NJPersonalGoalRecord(
            goalID: id,
            ownerScope: (fields["owner_scope"] as? String) ?? "ME",
            title: (fields["title"] as? String) ?? "",
            focus: (fields["focus"] as? String) ?? "keyword",
            keyword: (fields["keyword"] as? String) ?? "",
            weeklyTarget: (fields["weekly_target"] as? Int64) ?? ((fields["weekly_target"] as? NSNumber)?.int64Value ?? 0),
            status: (fields["status"] as? String) ?? "active",
            createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
            updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
            deleted: (fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0)
        )
        upsert(r)
    }

    private func readRow(_ stmt: OpaquePointer?) -> NJPersonalGoalRecord {
        NJPersonalGoalRecord(
            goalID: String(cString: sqlite3_column_text(stmt, 0)),
            ownerScope: String(cString: sqlite3_column_text(stmt, 1)),
            title: String(cString: sqlite3_column_text(stmt, 2)),
            focus: String(cString: sqlite3_column_text(stmt, 3)),
            keyword: String(cString: sqlite3_column_text(stmt, 4)),
            weeklyTarget: sqlite3_column_int64(stmt, 5),
            status: String(cString: sqlite3_column_text(stmt, 6)),
            createdAtMs: sqlite3_column_int64(stmt, 7),
            updatedAtMs: sqlite3_column_int64(stmt, 8),
            deleted: sqlite3_column_int64(stmt, 9)
        )
    }
}
