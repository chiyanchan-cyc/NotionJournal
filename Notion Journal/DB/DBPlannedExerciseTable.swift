import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBPlannedExerciseTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(
        db: SQLiteDB,
        enqueueDirty: @escaping (String, String, String, Int64) -> Void
    ) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func listPlans(startKey: String, endKey: String) -> [NJPlannedExercise] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT plan_id, date_key, week_key, title, category, sport, session_type,
                   target_distance_km, target_duration_min, notes, goal_json, cue_json,
                   block_json, source_plan_id, created_at_ms, updated_at_ms, deleted
            FROM nj_planned_exercise
            WHERE deleted = 0 AND date_key BETWEEN ? AND ?
            ORDER BY date_key ASC, updated_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, startKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, endKey, -1, SQLITE_TRANSIENT)

            var out: [NJPlannedExercise] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(readRow(stmt))
            }
            return out
        }
    }

    func upsertPlan(_ p: NJPlannedExercise) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_planned_exercise(
                plan_id, date_key, week_key, title, category, sport, session_type,
                target_distance_km, target_duration_min, notes, goal_json, cue_json,
                block_json, source_plan_id, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(plan_id) DO UPDATE SET
                date_key = excluded.date_key,
                week_key = excluded.week_key,
                title = excluded.title,
                category = excluded.category,
                sport = excluded.sport,
                session_type = excluded.session_type,
                target_distance_km = excluded.target_distance_km,
                target_duration_min = excluded.target_duration_min,
                notes = excluded.notes,
                goal_json = excluded.goal_json,
                cue_json = excluded.cue_json,
                block_json = excluded.block_json,
                source_plan_id = excluded.source_plan_id,
                created_at_ms = CASE
                    WHEN nj_planned_exercise.created_at_ms IS NULL OR nj_planned_exercise.created_at_ms = 0
                    THEN excluded.created_at_ms
                    ELSE nj_planned_exercise.created_at_ms
                END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, p.planID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, p.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, p.weekKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, p.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, p.category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, p.sport, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, p.sessionType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 8, p.targetDistanceKm)
            sqlite3_bind_double(stmt, 9, p.targetDurationMin)
            sqlite3_bind_text(stmt, 10, p.notes, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 11, p.goalJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 12, p.cueJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 13, p.blockJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 14, p.sourcePlanID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 15, p.createdAtMs)
            sqlite3_bind_int64(stmt, 16, p.updatedAtMs)
            sqlite3_bind_int64(stmt, 17, Int64(p.deleted))
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("planned_exercise", p.planID, "upsert", p.updatedAtMs)
    }

    func markDeleted(planID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_planned_exercise
            SET deleted = 1, updated_at_ms = ?
            WHERE plan_id = ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, planID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("planned_exercise", planID, "upsert", nowMs)
    }

    func loadPlan(planID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT plan_id, date_key, week_key, title, category, sport, session_type,
                   target_distance_km, target_duration_min, notes, goal_json, cue_json,
                   block_json, source_plan_id, created_at_ms, updated_at_ms, deleted
            FROM nj_planned_exercise
            WHERE plan_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, planID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let p = readRow(stmt)
            return [
                "plan_id": p.planID,
                "date_key": p.dateKey,
                "week_key": p.weekKey,
                "title": p.title,
                "category": p.category,
                "sport": p.sport,
                "session_type": p.sessionType,
                "target_distance_km": p.targetDistanceKm,
                "target_duration_min": p.targetDurationMin,
                "notes": p.notes,
                "goal_json": p.goalJSON,
                "cue_json": p.cueJSON,
                "block_json": p.blockJSON,
                "source_plan_id": p.sourcePlanID,
                "created_at_ms": p.createdAtMs,
                "updated_at_ms": p.updatedAtMs,
                "deleted": p.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let planID = (fields["plan_id"] as? String) ?? (fields["planID"] as? String) ?? ""
        if planID.isEmpty { return }
        let p = NJPlannedExercise(
            planID: planID,
            dateKey: (fields["date_key"] as? String) ?? "",
            weekKey: (fields["week_key"] as? String) ?? "",
            title: (fields["title"] as? String) ?? "",
            category: (fields["category"] as? String) ?? "",
            sport: (fields["sport"] as? String) ?? "",
            sessionType: (fields["session_type"] as? String) ?? "",
            targetDistanceKm: (fields["target_distance_km"] as? Double) ?? ((fields["target_distance_km"] as? NSNumber)?.doubleValue ?? 0),
            targetDurationMin: (fields["target_duration_min"] as? Double) ?? ((fields["target_duration_min"] as? NSNumber)?.doubleValue ?? 0),
            notes: (fields["notes"] as? String) ?? "",
            goalJSON: (fields["goal_json"] as? String) ?? "",
            cueJSON: (fields["cue_json"] as? String) ?? "",
            blockJSON: (fields["block_json"] as? String) ?? "",
            sourcePlanID: (fields["source_plan_id"] as? String) ?? "",
            createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
            updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
            deleted: Int((fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0))
        )
        upsertPlan(p)
    }

    private func readRow(_ stmt: OpaquePointer?) -> NJPlannedExercise {
        let planID = String(cString: sqlite3_column_text(stmt, 0))
        let dateKey = String(cString: sqlite3_column_text(stmt, 1))
        let weekKey = String(cString: sqlite3_column_text(stmt, 2))
        let title = String(cString: sqlite3_column_text(stmt, 3))
        let category = String(cString: sqlite3_column_text(stmt, 4))
        let sport = String(cString: sqlite3_column_text(stmt, 5))
        let sessionType = String(cString: sqlite3_column_text(stmt, 6))
        let dist = sqlite3_column_double(stmt, 7)
        let dur = sqlite3_column_double(stmt, 8)
        let notes = String(cString: sqlite3_column_text(stmt, 9))
        let goalJSON = String(cString: sqlite3_column_text(stmt, 10))
        let cueJSON = String(cString: sqlite3_column_text(stmt, 11))
        let blockJSON = String(cString: sqlite3_column_text(stmt, 12))
        let sourcePlanID = String(cString: sqlite3_column_text(stmt, 13))
        let created = sqlite3_column_int64(stmt, 14)
        let updated = sqlite3_column_int64(stmt, 15)
        let deleted = Int(sqlite3_column_int64(stmt, 16))
        return NJPlannedExercise(
            planID: planID,
            dateKey: dateKey,
            weekKey: weekKey,
            title: title,
            category: category,
            sport: sport,
            sessionType: sessionType,
            targetDistanceKm: dist,
            targetDurationMin: dur,
            notes: notes,
            goalJSON: goalJSON,
            cueJSON: cueJSON,
            blockJSON: blockJSON,
            sourcePlanID: sourcePlanID,
            createdAtMs: created,
            updatedAtMs: updated,
            deleted: deleted
        )
    }
}
