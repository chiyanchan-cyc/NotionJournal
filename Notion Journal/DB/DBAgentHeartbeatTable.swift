import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBAgentHeartbeatRunTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func upsert(_ row: NJAgentHeartbeatRun) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_agent_heartbeat_run(
                run_id, heartbeat_key, scheduled_for_ms, started_at_ms, completed_at_ms, status,
                coverage_start_ms, coverage_end_ms, date_key, market_session, output_ref, error_summary,
                source_refs_json, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(run_id) DO UPDATE SET
                heartbeat_key = excluded.heartbeat_key,
                scheduled_for_ms = excluded.scheduled_for_ms,
                started_at_ms = excluded.started_at_ms,
                completed_at_ms = excluded.completed_at_ms,
                status = excluded.status,
                coverage_start_ms = excluded.coverage_start_ms,
                coverage_end_ms = excluded.coverage_end_ms,
                date_key = excluded.date_key,
                market_session = excluded.market_session,
                output_ref = excluded.output_ref,
                error_summary = excluded.error_summary,
                source_refs_json = excluded.source_refs_json,
                created_at_ms = CASE WHEN nj_agent_heartbeat_run.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_agent_heartbeat_run.created_at_ms END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.runID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.heartbeatKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, row.scheduledForMs)
            sqlite3_bind_int64(stmt, 4, row.startedAtMs)
            sqlite3_bind_int64(stmt, 5, row.completedAtMs)
            sqlite3_bind_text(stmt, 6, row.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, row.coverageStartMs)
            sqlite3_bind_int64(stmt, 8, row.coverageEndMs)
            sqlite3_bind_text(stmt, 9, row.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 10, row.marketSession, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 11, row.outputRef, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 12, row.errorSummary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 13, row.sourceRefsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 14, row.createdAtMs)
            sqlite3_bind_int64(stmt, 15, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 16, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("agent_heartbeat_run", row.runID, "upsert", row.updatedAtMs)
    }

    func loadFields(runID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT run_id, heartbeat_key, scheduled_for_ms, started_at_ms, completed_at_ms, status,
                   coverage_start_ms, coverage_end_ms, date_key, market_session, output_ref, error_summary,
                   source_refs_json, created_at_ms, updated_at_ms, deleted
            FROM nj_agent_heartbeat_run
            WHERE run_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, runID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = read(stmt)
            return [
                "run_id": row.runID,
                "heartbeat_key": row.heartbeatKey,
                "scheduled_for_ms": row.scheduledForMs,
                "started_at_ms": row.startedAtMs,
                "completed_at_ms": row.completedAtMs,
                "status": row.status,
                "coverage_start_ms": row.coverageStartMs,
                "coverage_end_ms": row.coverageEndMs,
                "date_key": row.dateKey,
                "market_session": row.marketSession,
                "output_ref": row.outputRef,
                "error_summary": row.errorSummary,
                "source_refs_json": row.sourceRefsJSON,
                "created_at_ms": row.createdAtMs,
                "updated_at_ms": row.updatedAtMs,
                "deleted": row.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let runID = (fields["run_id"] as? String) ?? ""
        guard !runID.isEmpty else { return }
        upsert(
            NJAgentHeartbeatRun(
                runID: runID,
                heartbeatKey: (fields["heartbeat_key"] as? String) ?? "",
                scheduledForMs: int64(fields["scheduled_for_ms"]),
                startedAtMs: int64(fields["started_at_ms"]),
                completedAtMs: int64(fields["completed_at_ms"]),
                status: (fields["status"] as? String) ?? "",
                coverageStartMs: int64(fields["coverage_start_ms"]),
                coverageEndMs: int64(fields["coverage_end_ms"]),
                dateKey: (fields["date_key"] as? String) ?? "",
                marketSession: (fields["market_session"] as? String) ?? "",
                outputRef: (fields["output_ref"] as? String) ?? "",
                errorSummary: (fields["error_summary"] as? String) ?? "",
                sourceRefsJSON: (fields["source_refs_json"] as? String) ?? "",
                createdAtMs: int64(fields["created_at_ms"]),
                updatedAtMs: int64(fields["updated_at_ms"]),
                deleted: int64(fields["deleted"])
            )
        )
    }

    private func read(_ stmt: OpaquePointer?) -> NJAgentHeartbeatRun {
        NJAgentHeartbeatRun(
            runID: text(stmt, 0),
            heartbeatKey: text(stmt, 1),
            scheduledForMs: sqlite3_column_int64(stmt, 2),
            startedAtMs: sqlite3_column_int64(stmt, 3),
            completedAtMs: sqlite3_column_int64(stmt, 4),
            status: text(stmt, 5),
            coverageStartMs: sqlite3_column_int64(stmt, 6),
            coverageEndMs: sqlite3_column_int64(stmt, 7),
            dateKey: text(stmt, 8),
            marketSession: text(stmt, 9),
            outputRef: text(stmt, 10),
            errorSummary: text(stmt, 11),
            sourceRefsJSON: text(stmt, 12),
            createdAtMs: sqlite3_column_int64(stmt, 13),
            updatedAtMs: sqlite3_column_int64(stmt, 14),
            deleted: sqlite3_column_int64(stmt, 15)
        )
    }
}

final class DBAgentBackfillTaskTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func upsert(_ row: NJAgentBackfillTask) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_agent_backfill_task(
                task_id, heartbeat_key, missed_run_id, target_run_id, date_key, market_session,
                coverage_start_ms, coverage_end_ms, reason, status, priority, attempt_count,
                last_attempt_at_ms, result_ref, result_summary, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                heartbeat_key = excluded.heartbeat_key,
                missed_run_id = excluded.missed_run_id,
                target_run_id = excluded.target_run_id,
                date_key = excluded.date_key,
                market_session = excluded.market_session,
                coverage_start_ms = excluded.coverage_start_ms,
                coverage_end_ms = excluded.coverage_end_ms,
                reason = excluded.reason,
                status = excluded.status,
                priority = excluded.priority,
                attempt_count = excluded.attempt_count,
                last_attempt_at_ms = excluded.last_attempt_at_ms,
                result_ref = excluded.result_ref,
                result_summary = excluded.result_summary,
                created_at_ms = CASE WHEN nj_agent_backfill_task.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_agent_backfill_task.created_at_ms END,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.taskID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.heartbeatKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, row.missedRunID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, row.targetRunID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.dateKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, row.marketSession, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, row.coverageStartMs)
            sqlite3_bind_int64(stmt, 8, row.coverageEndMs)
            sqlite3_bind_text(stmt, 9, row.reason, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 10, row.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 11, row.priority)
            sqlite3_bind_int64(stmt, 12, row.attemptCount)
            sqlite3_bind_int64(stmt, 13, row.lastAttemptAtMs)
            sqlite3_bind_text(stmt, 14, row.resultRef, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 15, row.resultSummary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 16, row.createdAtMs)
            sqlite3_bind_int64(stmt, 17, row.updatedAtMs)
            sqlite3_bind_int64(stmt, 18, row.deleted)
            _ = sqlite3_step(stmt)
        }
        enqueueDirty("agent_backfill_task", row.taskID, "upsert", row.updatedAtMs)
    }

    func loadFields(taskID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT task_id, heartbeat_key, missed_run_id, target_run_id, date_key, market_session,
                   coverage_start_ms, coverage_end_ms, reason, status, priority, attempt_count,
                   last_attempt_at_ms, result_ref, result_summary, created_at_ms, updated_at_ms, deleted
            FROM nj_agent_backfill_task
            WHERE task_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, taskID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let row = read(stmt)
            return [
                "task_id": row.taskID,
                "heartbeat_key": row.heartbeatKey,
                "missed_run_id": row.missedRunID,
                "target_run_id": row.targetRunID,
                "date_key": row.dateKey,
                "market_session": row.marketSession,
                "coverage_start_ms": row.coverageStartMs,
                "coverage_end_ms": row.coverageEndMs,
                "reason": row.reason,
                "status": row.status,
                "priority": row.priority,
                "attempt_count": row.attemptCount,
                "last_attempt_at_ms": row.lastAttemptAtMs,
                "result_ref": row.resultRef,
                "result_summary": row.resultSummary,
                "created_at_ms": row.createdAtMs,
                "updated_at_ms": row.updatedAtMs,
                "deleted": row.deleted
            ]
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let taskID = (fields["task_id"] as? String) ?? ""
        guard !taskID.isEmpty else { return }
        upsert(
            NJAgentBackfillTask(
                taskID: taskID,
                heartbeatKey: (fields["heartbeat_key"] as? String) ?? "",
                missedRunID: (fields["missed_run_id"] as? String) ?? "",
                targetRunID: (fields["target_run_id"] as? String) ?? "",
                dateKey: (fields["date_key"] as? String) ?? "",
                marketSession: (fields["market_session"] as? String) ?? "",
                coverageStartMs: int64(fields["coverage_start_ms"]),
                coverageEndMs: int64(fields["coverage_end_ms"]),
                reason: (fields["reason"] as? String) ?? "",
                status: (fields["status"] as? String) ?? "",
                priority: int64(fields["priority"]),
                attemptCount: int64(fields["attempt_count"]),
                lastAttemptAtMs: int64(fields["last_attempt_at_ms"]),
                resultRef: (fields["result_ref"] as? String) ?? "",
                resultSummary: (fields["result_summary"] as? String) ?? "",
                createdAtMs: int64(fields["created_at_ms"]),
                updatedAtMs: int64(fields["updated_at_ms"]),
                deleted: int64(fields["deleted"])
            )
        )
    }

    private func read(_ stmt: OpaquePointer?) -> NJAgentBackfillTask {
        NJAgentBackfillTask(
            taskID: text(stmt, 0),
            heartbeatKey: text(stmt, 1),
            missedRunID: text(stmt, 2),
            targetRunID: text(stmt, 3),
            dateKey: text(stmt, 4),
            marketSession: text(stmt, 5),
            coverageStartMs: sqlite3_column_int64(stmt, 6),
            coverageEndMs: sqlite3_column_int64(stmt, 7),
            reason: text(stmt, 8),
            status: text(stmt, 9),
            priority: sqlite3_column_int64(stmt, 10),
            attemptCount: sqlite3_column_int64(stmt, 11),
            lastAttemptAtMs: sqlite3_column_int64(stmt, 12),
            resultRef: text(stmt, 13),
            resultSummary: text(stmt, 14),
            createdAtMs: sqlite3_column_int64(stmt, 15),
            updatedAtMs: sqlite3_column_int64(stmt, 16),
            deleted: sqlite3_column_int64(stmt, 17)
        )
    }
}

private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String {
    guard let cstr = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: cstr)
}

private func int64(_ value: Any?) -> Int64 {
    if let value = value as? Int64 { return value }
    if let value = value as? Int { return Int64(value) }
    if let value = value as? NSNumber { return value.int64Value }
    if let value = value as? String { return Int64(value) ?? 0 }
    return 0
}
