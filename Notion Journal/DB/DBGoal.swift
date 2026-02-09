import Foundation
import SQLite3
import UIKit

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
extension DBNoteRepository {
    func createGoalSeedling(name: String, descriptionPlainText: String, originBlockID: String?, domainTagsText: String, goalTagText: String) -> String {

        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let goalID = UUID().uuidString

        let s = NSAttributedString(string: descriptionPlainText)
        let rtf = (try? s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        let payload: [String: Any] = [
            "v": 1,
            "name": name,
            "rtf64": rtf.base64EncodedString()
        ]
        let payloadData = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? ""

        let trimmedGoalTag = goalTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = trimmedGoalTag.isEmpty ? "open" : "in_progress"
        goalTable.upsertLocalGoal(
            goalID: goalID,
            originBlockID: originBlockID,
            domainTagsJSON: domainTagsJSON(from: domainTagsText),
            goalTag: optionalString(from: goalTagText),
            status: status,
            reflectCadence: nil,
            payloadJSON: payloadJSON,
            createdAtMs: now,
            updatedAtMs: now,
            deleted: 0
        )

        upsertDirtyGoal(goalID: goalID, updatedAtMs: now)
        return goalID
    }

    private func domainTagsJSON(from text: String) -> String {
        let parts = text
            .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let data = (try? JSONSerialization.data(withJSONObject: parts, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func optionalString(from text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func upsertDirtyGoal(goalID: String, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error)
            VALUES('goal', ?, 'upsert', ?, 0, '')
            ON CONFLICT(entity, entity_id) DO UPDATE SET
                op='upsert',
                updated_at_ms=excluded.updated_at_ms,
                attempts=0,
                last_error='';
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, goalID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, updatedAtMs)
            _ = sqlite3_step(stmt)
        }
    }

    func updateGoalStatus(goalID: String, status: String) {
        if goalID.isEmpty { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_goal
            SET status=?,
                updated_at_ms=?,
                deleted=0
            WHERE goal_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, goalID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        upsertDirtyGoal(goalID: goalID, updatedAtMs: now)
    }

    func updateGoalTag(goalID: String, goalTag: String, setInProgress: Bool) {
        if goalID.isEmpty { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let trimmed = goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql: String
            if setInProgress {
                sql = """
                UPDATE nj_goal
                SET goal_tag=?,
                    status='in_progress',
                    updated_at_ms=?,
                    deleted=0
                WHERE goal_id=?;
                """
            } else {
                sql = """
                UPDATE nj_goal
                SET goal_tag=?,
                    updated_at_ms=?,
                    deleted=0
                WHERE goal_id=?;
                """
            }
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            if trimmed.isEmpty {
                sqlite3_bind_null(stmt, 1)
            } else {
                sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            }
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, goalID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        upsertDirtyGoal(goalID: goalID, updatedAtMs: now)
    }

    func updateGoalComment(goalID: String, commentPlainText: String) {
        if goalID.isEmpty { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let payloadJSON: String = {
            if let g = goalTable.loadNJGoal(goalID: goalID) {
                let raw = (g["payload_json"] as? String) ?? ""
                if let data = raw.data(using: .utf8),
                   let payload = try? JSONDecoder().decode(NJGoalPayloadV1.self, from: data) {
                    return NJGoalPayloadV1.make(name: payload.name, plainText: commentPlainText).toJSON()
                }
                if let data = raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = obj["name"] as? String {
                    return NJGoalPayloadV1.make(name: name, plainText: commentPlainText).toJSON()
                }
            }
            return NJGoalPayloadV1.make(name: "Untitled", plainText: commentPlainText).toJSON()
        }()

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_goal
            SET payload_json=?,
                updated_at_ms=?,
                deleted=0
            WHERE goal_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, payloadJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, goalID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }

        upsertDirtyGoal(goalID: goalID, updatedAtMs: now)
    }

    func migrateGoalStatusForTaggedGoals() -> Int {
        let rows: [(String, String, String)] = db.withDB { dbp in
            var out: [(String, String, String)] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT goal_id, status, goal_tag
            FROM nj_goal
            WHERE deleted = 0;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return [] }
            defer { sqlite3_finalize(stmt) }

            func colText(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let gid = colText(0)
                let st = colText(1)
                let tag = colText(2)
                out.append((gid, st, tag))
            }
            return out
        }

        var updated = 0
        for (gid, st, tag) in rows {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTag.isEmpty { continue }
            let s = st.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["archive", "archived", "done", "closed"].contains(s) { continue }
            if ["in_progress", "progress", "active", "working"].contains(s) { continue }
            updateGoalStatus(goalID: gid, status: "in_progress")
            updated += 1
        }
        return updated
    }
}
