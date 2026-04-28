import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBHealthSampleCloudTable {
    let db: SQLiteDB
    let enqueueDirty: (String, String, String, Int64) -> Void

    init(
        db: SQLiteDB,
        enqueueDirty: @escaping (String, String, String, Int64) -> Void
    ) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func loadHealthSample(sampleID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT sample_id, type, start_ms, end_ms, value_num, value_str, unit,
                   source, metadata_json, device_id, inserted_at_ms
            FROM health_samples
            WHERE sample_id = ? AND type = 'workout'
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sampleID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readFields(stmt)
        }
    }

    func applyRemote(_ fields: [String: Any]) {
        let sampleID = string(fields, "sample_id", fallback: string(fields, "sampleID"))
        if sampleID.isEmpty { return }

        let type = string(fields, "type")
        guard type == "workout" else { return }

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO health_samples(
                sample_id, type, start_ms, end_ms, value_num, value_str, unit,
                source, metadata_json, device_id, inserted_at_ms
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(sample_id) DO UPDATE SET
                type = excluded.type,
                start_ms = excluded.start_ms,
                end_ms = excluded.end_ms,
                value_num = excluded.value_num,
                value_str = excluded.value_str,
                unit = excluded.unit,
                source = excluded.source,
                metadata_json = excluded.metadata_json,
                device_id = excluded.device_id,
                inserted_at_ms = excluded.inserted_at_ms;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, sampleID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, "workout", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, int64(fields, "start_ms"))
            sqlite3_bind_int64(stmt, 4, int64(fields, "end_ms"))
            sqlite3_bind_double(stmt, 5, double(fields, "value_num"))
            sqlite3_bind_text(stmt, 6, string(fields, "value_str"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, string(fields, "unit", fallback: "s"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, string(fields, "source"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, string(fields, "metadata_json"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 10, string(fields, "device_id"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 11, int64(fields, "inserted_at_ms", fallback: int64(fields, "updated_at_ms")))
            _ = sqlite3_step(stmt)
        }
    }

    @discardableResult
    func enqueueWorkoutSamplesForCloud(startMs: Int64, endMs: Int64, limit: Int = 500) -> Int {
        let rows: [(String, Int64)] = db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT sample_id, inserted_at_ms
            FROM health_samples
            WHERE type = 'workout'
              AND start_ms >= ?
              AND start_ms < ?
            ORDER BY start_ms DESC
            LIMIT ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, startMs)
            sqlite3_bind_int64(stmt, 2, endMs)
            sqlite3_bind_int(stmt, 3, Int32(max(1, limit)))

            var out: [(String, Int64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let id = String(cString: c)
                let insertedAt = sqlite3_column_int64(stmt, 1)
                out.append((id, insertedAt))
            }
            return out
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        for (sampleID, insertedAt) in rows {
            enqueueDirty(
                NJHealthSampleCloudMapper.entity,
                sampleID,
                "upsert",
                max(insertedAt, now)
            )
        }

        return rows.count
    }

    private func readFields(_ stmt: OpaquePointer?) -> [String: Any] {
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        return [
            "sample_id": columnText(stmt, 0),
            "type": columnText(stmt, 1),
            "start_ms": sqlite3_column_int64(stmt, 2),
            "end_ms": sqlite3_column_int64(stmt, 3),
            "value_num": sqlite3_column_double(stmt, 4),
            "value_str": columnText(stmt, 5),
            "unit": columnText(stmt, 6),
            "source": columnText(stmt, 7),
            "metadata_json": columnText(stmt, 8),
            "device_id": columnText(stmt, 9),
            "inserted_at_ms": sqlite3_column_int64(stmt, 10),
            "created_at_ms": sqlite3_column_int64(stmt, 10),
            "updated_at_ms": now
        ]
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private func string(_ fields: [String: Any], _ key: String, fallback: String = "") -> String {
        if let value = fields[key] as? String { return value }
        if let value = fields[key] as? NSNumber { return value.stringValue }
        return fallback
    }

    private func int64(_ fields: [String: Any], _ key: String, fallback: Int64 = 0) -> Int64 {
        if let value = fields[key] as? Int64 { return value }
        if let value = fields[key] as? Int { return Int64(value) }
        if let value = fields[key] as? NSNumber { return value.int64Value }
        if let value = fields[key] as? String { return Int64(value) ?? fallback }
        return fallback
    }

    private func double(_ fields: [String: Any], _ key: String, fallback: Double = 0) -> Double {
        if let value = fields[key] as? Double { return value }
        if let value = fields[key] as? Float { return Double(value) }
        if let value = fields[key] as? NSNumber { return value.doubleValue }
        if let value = fields[key] as? String { return Double(value) ?? fallback }
        return fallback
    }
}
