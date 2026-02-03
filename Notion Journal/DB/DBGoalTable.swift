import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBGoalTable {
    private let db: SQLiteDB

    init(db: SQLiteDB) {
        self.db = db
    }

    func loadGoalPreviewForOriginBlock(blockID: String) -> String {
        if blockID.isEmpty { return "" }
        return db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = """
            SELECT goal_tag, payload_json
            FROM nj_goal
            WHERE origin_block_id=? AND deleted=0
            ORDER BY updated_at_ms DESC
            LIMIT 1;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                let goalTag = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let payloadJSON = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""

                let trimmedTag = goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTag.isEmpty { return trimmedTag }

                if let data = payloadJSON.data(using: .utf8),
                   let payload = try? JSONDecoder().decode(NJGoalPayloadV1.self, from: data) {
                    out = payload.name
                } else if let data = payloadJSON.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let name = obj["name"] as? String {
                    out = name
                }
            }

            return out
        }
    }

    func loadNJGoal(goalID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT goal_id, origin_block_id, domain_tags_json, goal_tag, status, reflect_cadence, payload_json, created_at_ms, updated_at_ms, deleted
            FROM nj_goal
            WHERE goal_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, goalID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_ROW { return nil }

            func colText(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }

            func colTextOpt(_ i: Int32) -> String? {
                guard let c = sqlite3_column_text(stmt, i) else { return nil }
                return String(cString: c)
            }

            func colInt64(_ i: Int32) -> Int64 {
                sqlite3_column_int64(stmt, i)
            }

            return [
                "goal_id": colText(0),
                "origin_block_id": colTextOpt(1) as Any,
                "domain_tags_json": colText(2),
                "goal_tag": colTextOpt(3) as Any,
                "status": colText(4),
                "reflect_cadence": colTextOpt(5) as Any,
                "payload_json": colText(6),
                "created_at_ms": colInt64(7),
                "updated_at_ms": colInt64(8),
                "deleted": colInt64(9)
            ]
        }
    }

    func applyNJGoal(_ fields: [String: Any]) {
        let goalID = (fields["goal_id"] as? String) ?? ""
        if goalID.isEmpty { return }

        let originBlockID = fields["origin_block_id"] as? String
        let domainTagsJSON = (fields["domain_tags_json"] as? String) ?? ""
        let goalTag = fields["goal_tag"] as? String
        let status = (fields["status"] as? String) ?? ""
        let reflectCadence = fields["reflect_cadence"] as? String
        let payloadJSON = (fields["payload_json"] as? String) ?? ""
        let createdAt = (fields["created_at_ms"] as? Int64) ?? Int64((fields["created_at_ms"] as? Int) ?? 0)
        let updatedAt = (fields["updated_at_ms"] as? Int64) ?? Int64((fields["updated_at_ms"] as? Int) ?? 0)
        let deleted = (fields["deleted"] as? Int64) ?? Int64((fields["deleted"] as? Int) ?? 0)

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_goal(
                goal_id, origin_block_id, domain_tags_json, goal_tag, status, reflect_cadence, payload_json, created_at_ms, updated_at_ms, deleted
            ) VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(goal_id) DO UPDATE SET
                origin_block_id=excluded.origin_block_id,
                domain_tags_json=excluded.domain_tags_json,
                goal_tag=excluded.goal_tag,
                status=excluded.status,
                reflect_cadence=excluded.reflect_cadence,
                payload_json=excluded.payload_json,
                created_at_ms=excluded.created_at_ms,
                updated_at_ms=excluded.updated_at_ms,
                deleted=excluded.deleted;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, goalID, -1, SQLITE_TRANSIENT)

            if let s = originBlockID {
                sqlite3_bind_text(stmt, 2, s, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 2)
            }

            sqlite3_bind_text(stmt, 3, domainTagsJSON, -1, SQLITE_TRANSIENT)

            if let s = goalTag {
                sqlite3_bind_text(stmt, 4, s, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            sqlite3_bind_text(stmt, 5, status, -1, SQLITE_TRANSIENT)

            if let s = reflectCadence {
                sqlite3_bind_text(stmt, 6, s, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }

            sqlite3_bind_text(stmt, 7, payloadJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, createdAt)
            sqlite3_bind_int64(stmt, 9, updatedAt)
            sqlite3_bind_int64(stmt, 10, deleted)

            _ = sqlite3_step(stmt)
        }
    }
    
    func upsertLocalGoal(
        goalID: String,
        originBlockID: String?,
        domainTagsJSON: String,
        goalTag: String?,
        status: String,
        reflectCadence: String?,
        payloadJSON: String,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        deleted: Int64
    ) {
        applyNJGoal([
            "goal_id": goalID,
            "origin_block_id": originBlockID as Any,
            "domain_tags_json": domainTagsJSON,
            "goal_tag": goalTag as Any,
            "status": status,
            "reflect_cadence": reflectCadence as Any,
            "payload_json": payloadJSON,
            "created_at_ms": createdAtMs,
            "updated_at_ms": updatedAtMs,
            "deleted": deleted
        ])
    }

}
