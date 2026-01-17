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

        goalTable.upsertLocalGoal(
            goalID: goalID,
            originBlockID: originBlockID,
            domainTagsJSON: domainTagsJSON(from: domainTagsText),
            goalTag: optionalString(from: goalTagText),
            status: "open",
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
}
