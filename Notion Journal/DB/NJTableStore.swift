import Foundation
import SQLite3

private let NJ_TABLE_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NJTableStore {
    static let tableDidChangeNotification = Notification.Name("NJTableStore.tableDidChange")

    enum RenameError: LocalizedError {
        case duplicateName

        var errorDescription: String? {
            switch self {
            case .duplicateName:
                return "That table name is already in use."
            }
        }
    }

    static let shared = NJTableStore()
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private let db: SQLiteDB

    private init() {
        let dbPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notion_journal.sqlite")
            .path
        let db = SQLiteDB(path: dbPath, resetSchema: false)
        DBSchemaInstaller.ensureSchema(db: db)
        self.db = db
    }

    func ensureIdentity(
        tableID: String,
        preferredShortID: String?,
        preferredName: String?
    ) -> (shortID: String, name: String?, changed: Bool) {
        let trimmedID = tableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return ("", nil, false) }

        let normalizedPreferredShortID = Self.normalizedShortID(preferredShortID)
        let normalizedPreferredName = Self.normalizedName(preferredName)

        return db.withDB { dbp in
            var currentShortID: String?
            var currentName: String?
            var currentPayload: [String: Any] = [:]

            if let row = self.loadRow(tableID: trimmedID, dbp: dbp) {
                currentShortID = row.shortID
                currentName = row.name
                currentPayload = row.payload ?? [:]
            }

            let shortID: String
            if let existing = Self.normalizedShortID(currentShortID), !existing.isEmpty {
                shortID = existing
            } else if let preferred = normalizedPreferredShortID,
                      self.isShortIDAvailable(preferred, for: trimmedID, dbp: dbp) {
                shortID = preferred
            } else {
                shortID = self.generateUniqueShortID(for: trimmedID, dbp: dbp)
            }

            let name: String?
            if let existing = Self.normalizedName(currentName), !existing.isEmpty {
                name = existing
            } else if let preferred = normalizedPreferredName {
                name = self.uniqueName(for: trimmedID, preferredName: preferred, dbp: dbp)
            } else {
                name = nil
            }

            let changed = shortID != currentShortID || name != currentName || currentPayload.isEmpty
            if changed {
                currentPayload["table_id"] = trimmedID
                currentPayload["table_short_id"] = shortID
                if let name {
                    currentPayload["table_name"] = name
                } else {
                    currentPayload.removeValue(forKey: "table_name")
                }
                self.upsertCanonicalPayload(tableID: trimmedID, payload: currentPayload, dbp: dbp, markDirty: true)
            }

            return (shortID, name, changed)
        }
    }

    func renameTable(
        tableID: String,
        proposedName: String?
    ) -> Result<String?, RenameError> {
        let trimmedID = tableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return .success(nil) }
        let normalizedProposed = Self.normalizedName(proposedName)

        return db.withDB { dbp in
            if let normalizedProposed,
               !self.isNameAvailable(normalizedProposed, for: trimmedID, dbp: dbp) {
                return .failure(.duplicateName)
            }

            var payload = self.loadRow(tableID: trimmedID, dbp: dbp)?.payload ?? [:]
            payload["table_id"] = trimmedID
            if let existingShortID = self.loadRow(tableID: trimmedID, dbp: dbp)?.shortID,
               !existingShortID.isEmpty {
                payload["table_short_id"] = existingShortID
            }
            if let normalizedProposed {
                payload["table_name"] = normalizedProposed
            } else {
                payload.removeValue(forKey: "table_name")
            }
            self.upsertCanonicalPayload(tableID: trimmedID, payload: payload, dbp: dbp, markDirty: true)
            return .success(normalizedProposed)
        }
    }

    func loadCanonicalPayload(tableID: String) -> [String: Any]? {
        let trimmedID = tableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        return db.withDB { dbp in
            self.loadRow(tableID: trimmedID, dbp: dbp)?.payload
        }
    }

    func loadCloudFields(tableID: String) -> [String: Any]? {
        let trimmedID = tableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT table_id, short_id, name, canonical_json, created_at_ms, updated_at_ms, deleted
            FROM nj_table
            WHERE table_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, trimmedID, -1, NJ_TABLE_SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            func text(_ idx: Int32) -> String {
                sqlite3_column_text(stmt, idx).map { String(cString: $0) } ?? ""
            }

            return [
                "table_id": text(0),
                "short_id": text(1),
                "name": text(2),
                "canonical_json": text(3),
                "created_at_ms": sqlite3_column_int64(stmt, 4),
                "updated_at_ms": sqlite3_column_int64(stmt, 5),
                "deleted": sqlite3_column_int64(stmt, 6)
            ]
        }
    }

    func listKnownTableIDs(limit: Int = 500) -> [String] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT table_id
            FROM nj_table
            WHERE deleted = 0
            ORDER BY updated_at_ms DESC
            LIMIT ?;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(max(1, limit)))

            var ids: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                if !id.isEmpty {
                    ids.append(id)
                }
            }
            return ids
        }
    }

    func upsertCanonicalPayload(tableID: String, payload: [String: Any]) {
        db.withDB { dbp in
            self.upsertCanonicalPayload(tableID: tableID, payload: payload, dbp: dbp, markDirty: true)
        }
    }

    func cacheCanonicalPayload(tableID: String, payload: [String: Any]) {
        db.withDB { dbp in
            self.upsertCanonicalPayload(tableID: tableID, payload: payload, dbp: dbp, markDirty: false)
        }
    }

    func applyCloudFields(_ fields: [String: Any]) {
        let tableID = ((fields["table_id"] as? String) ?? (fields["id"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableID.isEmpty else { return }

        let canonicalJSON = (fields["canonical_json"] as? String) ?? "{}"
        let payload: [String: Any] = {
            guard let data = canonicalJSON.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ["table_id": tableID]
            }
            return root
        }()
        let updatedAtMs = Self.int64(fields["updated_at_ms"])
        let createdAtMs = Self.int64(fields["created_at_ms"])
        let deleted = Self.int64(fields["deleted"])

        db.withDB { dbp in
            if let local = self.loadRow(tableID: tableID, dbp: dbp),
               updatedAtMs <= 0 || local.updatedAtMs >= updatedAtMs {
                print("NJ_TABLE_CLOUD_SKIP_OLDER table_id=\(tableID) local_updated=\(local.updatedAtMs) remote_updated=\(updatedAtMs)")
                return
            }

            if deleted > 0 {
                self.applyCloudDelete(tableID: tableID, updatedAtMs: updatedAtMs, dbp: dbp)
            } else {
                self.upsertCanonicalPayload(
                    tableID: tableID,
                    payload: payload,
                    createdAtMs: createdAtMs,
                    updatedAtMs: updatedAtMs,
                    dbp: dbp,
                    markDirty: false
                )
            }
        }
        NotificationCenter.default.post(
            name: Self.tableDidChangeNotification,
            object: self,
            userInfo: ["table_id": tableID]
        )
    }

    private func upsertCanonicalPayload(
        tableID: String,
        payload: [String: Any],
        createdAtMs: Int64? = nil,
        updatedAtMs: Int64? = nil,
        dbp: OpaquePointer?,
        markDirty: Bool
    ) {
        guard let dbp else { return }
        let trimmedID = tableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        var normalizedPayload = payload
        normalizedPayload["table_id"] = trimmedID
        guard JSONSerialization.isValidJSONObject(normalizedPayload),
              let data = try? JSONSerialization.data(withJSONObject: normalizedPayload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            print("NJ_TABLE_SAVE_INVALID_JSON table_id=\(trimmedID) keys=\(Array(normalizedPayload.keys).sorted())")
            return
        }

        let shortID = Self.normalizedShortID(normalizedPayload["table_short_id"] as? String) ?? ""
        let name = Self.normalizedName(normalizedPayload["table_name"] as? String) ?? ""
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let created = (createdAtMs ?? 0) > 0 ? createdAtMs! : now
        let updated = (updatedAtMs ?? 0) > 0 ? updatedAtMs! : now

        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO nj_table(
            table_id,
            short_id,
            name,
            canonical_json,
            created_at_ms,
            updated_at_ms,
            deleted
        )
        VALUES(?, ?, ?, ?, ?, ?, 0)
        ON CONFLICT(table_id) DO UPDATE SET
            short_id = excluded.short_id,
            name = excluded.name,
            canonical_json = excluded.canonical_json,
            updated_at_ms = excluded.updated_at_ms,
            deleted = 0;
        """
        guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else {
            self.db.dbgErr(dbp, "nj_table.upsert.prepare", sqlite3_errcode(dbp))
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, trimmedID, -1, NJ_TABLE_SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, shortID, -1, NJ_TABLE_SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, name, -1, NJ_TABLE_SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, json, -1, NJ_TABLE_SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, created)
        sqlite3_bind_int64(stmt, 6, updated)

        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            self.db.dbgErr(dbp, "nj_table.upsert.step", rc)
            return
        }

        if markDirty {
            enqueueDirty(tableID: trimmedID, updatedAtMs: updated, dbp: dbp)
        }
        print("NJ_TABLE_SAVE_OK table_id=\(trimmedID) bytes=\(data.count) dirty=\(markDirty ? 1 : 0)")
    }

    private func applyCloudDelete(tableID: String, updatedAtMs: Int64, dbp: OpaquePointer?) {
        guard let dbp else { return }
        var stmt: OpaquePointer?
        let sql = """
        UPDATE nj_table
        SET deleted = 1, updated_at_ms = ?
        WHERE table_id = ?;
        """
        guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else {
            self.db.dbgErr(dbp, "nj_table.cloudDelete.prepare", sqlite3_errcode(dbp))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, updatedAtMs > 0 ? updatedAtMs : Int64(Date().timeIntervalSince1970 * 1000.0))
        sqlite3_bind_text(stmt, 2, tableID, -1, NJ_TABLE_SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            self.db.dbgErr(dbp, "nj_table.cloudDelete.step", rc)
        }
    }

    private func enqueueDirty(tableID: String, updatedAtMs: Int64, dbp: OpaquePointer?) {
        guard let dbp, !DBDirtyQueueTable.isInPullScope() else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error)
        VALUES('table', ?, 'upsert', ?, 0, '')
        ON CONFLICT(entity, entity_id) DO UPDATE SET
          op='upsert',
          updated_at_ms=excluded.updated_at_ms,
          attempts=0,
          last_error='',
          last_error_at_ms=0,
          last_error_code=0,
          last_error_domain='',
          next_retry_at_ms=0,
          ignore=0;
        """
        guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else {
            self.db.dbgErr(dbp, "nj_table.dirty.prepare", sqlite3_errcode(dbp))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, tableID, -1, NJ_TABLE_SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, updatedAtMs)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            self.db.dbgErr(dbp, "nj_table.dirty.step", rc)
        } else {
            NotificationCenter.default.post(name: .njDirtyEnqueued, object: nil)
        }
    }

    private func loadRow(tableID: String, dbp: OpaquePointer?) -> (shortID: String?, name: String?, payload: [String: Any]?, updatedAtMs: Int64)? {
        var stmt: OpaquePointer?
        let sql = """
        SELECT short_id, name, canonical_json, updated_at_ms
        FROM nj_table
        WHERE table_id = ? AND deleted = 0
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, tableID, -1, NJ_TABLE_SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let shortID = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
        let payload: [String: Any]? = sqlite3_column_text(stmt, 2).flatMap {
            let json = String(cString: $0)
            guard let data = json.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let updatedAtMs = sqlite3_column_int64(stmt, 3)
        return (shortID, name, payload, updatedAtMs)
    }

    private func isShortIDAvailable(_ shortID: String, for tableID: String, dbp: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        let sql = """
        SELECT table_id
        FROM nj_table
        WHERE short_id = ? AND deleted = 0
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, shortID, -1, NJ_TABLE_SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
        let owner = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        return owner == tableID
    }

    private func isNameAvailable(_ name: String, for tableID: String, dbp: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        let sql = """
        SELECT table_id
        FROM nj_table
        WHERE deleted = 0
          AND lower(trim(name)) = lower(trim(?))
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, name, -1, NJ_TABLE_SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
        let owner = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        return owner == tableID
    }

    private func generateUniqueShortID(for tableID: String, dbp: OpaquePointer?) -> String {
        var generator = SystemRandomNumberGenerator()
        while true {
            let candidate = String((0..<4).map { _ in Self.alphabet.randomElement(using: &generator)! })
            if isShortIDAvailable(candidate, for: tableID, dbp: dbp) {
                return candidate
            }
        }
    }

    private func uniqueName(for tableID: String, preferredName: String, dbp: OpaquePointer?) -> String {
        if isNameAvailable(preferredName, for: tableID, dbp: dbp) {
            return preferredName
        }

        var suffix = 2
        while true {
            let candidate = "\(preferredName) \(suffix)"
            if isNameAvailable(candidate, for: tableID, dbp: dbp) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func normalizedShortID(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard trimmed.count == 4, trimmed.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return trimmed
    }

    private static func normalizedName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }
}
