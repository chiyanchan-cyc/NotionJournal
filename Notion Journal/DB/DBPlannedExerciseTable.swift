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
            SELECT plan_id, date_key, sport, target_distance_km, target_duration_min, notes,
                   created_at_ms, updated_at_ms, deleted
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
                plan_id, date_key, sport, target_distance_km, target_duration_min, notes,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(plan_id) DO UPDATE SET
                date_key = excluded.date_key,
                sport = excluded.sport,
                target_distance_km = excluded.target_distance_km,
                target_duration_min = excluded.target_duration_min,
                notes = excluded.notes,
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
            sqlite3_bind_text(stmt, 3, p.sport, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, p.targetDistanceKm)
            sqlite3_bind_double(stmt, 5, p.targetDurationMin)
            sqlite3_bind_text(stmt, 6, p.notes, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, p.createdAtMs)
            sqlite3_bind_int64(stmt, 8, p.updatedAtMs)
            sqlite3_bind_int64(stmt, 9, Int64(p.deleted))
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
            SELECT plan_id, date_key, sport, target_distance_km, target_duration_min, notes,
                   created_at_ms, updated_at_ms, deleted
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
                "sport": p.sport,
                "target_distance_km": p.targetDistanceKm,
                "target_duration_min": p.targetDurationMin,
                "notes": p.notes,
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
            sport: (fields["sport"] as? String) ?? "",
            targetDistanceKm: (fields["target_distance_km"] as? Double) ?? ((fields["target_distance_km"] as? NSNumber)?.doubleValue ?? 0),
            targetDurationMin: (fields["target_duration_min"] as? Double) ?? ((fields["target_duration_min"] as? NSNumber)?.doubleValue ?? 0),
            notes: (fields["notes"] as? String) ?? "",
            createdAtMs: (fields["created_at_ms"] as? Int64) ?? ((fields["created_at_ms"] as? NSNumber)?.int64Value ?? 0),
            updatedAtMs: (fields["updated_at_ms"] as? Int64) ?? ((fields["updated_at_ms"] as? NSNumber)?.int64Value ?? 0),
            deleted: Int((fields["deleted"] as? Int64) ?? ((fields["deleted"] as? NSNumber)?.int64Value ?? 0))
        )
        upsertPlan(p)
    }

    private func readRow(_ stmt: OpaquePointer?) -> NJPlannedExercise {
        let planID = String(cString: sqlite3_column_text(stmt, 0))
        let dateKey = String(cString: sqlite3_column_text(stmt, 1))
        let sport = String(cString: sqlite3_column_text(stmt, 2))
        let dist = sqlite3_column_double(stmt, 3)
        let dur = sqlite3_column_double(stmt, 4)
        let notes = String(cString: sqlite3_column_text(stmt, 5))
        let created = sqlite3_column_int64(stmt, 6)
        let updated = sqlite3_column_int64(stmt, 7)
        let deleted = Int(sqlite3_column_int64(stmt, 8))
        return NJPlannedExercise(
            planID: planID,
            dateKey: dateKey,
            sport: sport,
            targetDistanceKm: dist,
            targetDurationMin: dur,
            notes: notes,
            createdAtMs: created,
            updatedAtMs: updated,
            deleted: deleted
        )
    }
}
