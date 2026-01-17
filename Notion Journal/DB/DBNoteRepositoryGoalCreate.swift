import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
extension DBNoteRepository {
    func createGoalSeedling(
        name: String,
        descriptionPlainText: String,
        originBlockID: String? = nil
    ) -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let goalID = UUID().uuidString
        let payload = NJGoalPayloadV1.make(name: name, plainText: descriptionPlainText).toJSON()

        goalTable.upsertLocalGoal(
            goalID: goalID,
            originBlockID: originBlockID,
            domainTagsJSON: "[]",
            goalTag: nil,
            status: "open",
            reflectCadence: nil,
            payloadJSON: payload,
            createdAtMs: now,
            updatedAtMs: now,
            deleted: 0
        )

        upsertDirty(entity: "goal", entityID: goalID, op: "upsert", updatedAtMs: now)
        return goalID
    }

    private func upsertDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error)
            VALUES(?,?,?,?,0,'')
            ON CONFLICT(entity, entity_id) DO UPDATE SET
                op=excluded.op,
                updated_at_ms=excluded.updated_at_ms,
                attempts=0,
                last_error='';
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, entity, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entityID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, op, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, updatedAtMs)
            _ = sqlite3_step(stmt)
        }
    }
}
