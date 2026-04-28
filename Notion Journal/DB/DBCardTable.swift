import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBCardTable {
    static let personalIdentificationSchemaKey = "common.personal_identification"

    private let db: SQLiteDB
    private let enqueueDirty: ((String, String, String, Int64) -> Void)?

    init(db: SQLiteDB, enqueueDirty: ((String, String, String, Int64) -> Void)? = nil) {
        self.db = db
        self.enqueueDirty = enqueueDirty
    }

    func ensurePersonalIdentificationSchema(nowMs: Int64) {
        let shouldEnqueue = loadCardSchema(schemaKey: Self.personalIdentificationSchemaKey) == nil
        let fieldDefs: [[String: Any]] = [
            ["key": "person_name", "label": "Person", "type": "string"],
            ["key": "document_name", "label": "Document", "type": "string"],
            ["key": "document_type", "label": "Type", "type": "string"],
            ["key": "jurisdiction", "label": "Jurisdiction", "type": "string"],
            ["key": "document_number_hint", "label": "Number Hint", "type": "string"],
            ["key": "expiry_date", "label": "Expiry Date", "type": "date"],
            ["key": "reminder_offsets", "label": "Reminder Offsets", "type": "json"],
            ["key": "notes", "label": "Notes", "type": "string"]
        ]
        let viewDefs: [[String: Any]] = [
            [
                "key": "default",
                "title": "Personal Identification",
                "sort": [["field": "expiry_date", "direction": "asc"]],
                "group": "person_name"
            ]
        ]

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_card_schema(
                schema_key, display_name, category, field_defs_json, view_defs_json,
                version, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(schema_key) DO UPDATE SET
                display_name = excluded.display_name,
                category = excluded.category,
                field_defs_json = excluded.field_defs_json,
                view_defs_json = excluded.view_defs_json,
                version = excluded.version,
                updated_at_ms = excluded.updated_at_ms,
                deleted = 0;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, Self.personalIdentificationSchemaKey)
            bindText(stmt, 2, "Personal Identification")
            bindText(stmt, 3, "Database")
            bindText(stmt, 4, jsonString(fieldDefs))
            bindText(stmt, 5, jsonString(viewDefs))
            sqlite3_bind_int64(stmt, 6, 1)
            sqlite3_bind_int64(stmt, 7, nowMs)
            sqlite3_bind_int64(stmt, 8, nowMs)
            _ = sqlite3_step(stmt)
        }
        if shouldEnqueue {
            enqueueDirty?("card_schema", Self.personalIdentificationSchemaKey, "upsert", nowMs)
        }
    }

    func mirrorPersonalIdentificationCards(from rows: [NJRenewalItemRecord], nowMs: Int64) {
        ensurePersonalIdentificationSchema(nowMs: nowMs)

        for row in rows {
            let cardID = "card.personal_id.\(row.renewalItemID)"
            let titleParts = [row.personName, row.documentName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let title = titleParts.isEmpty ? "Personal Identification" : titleParts.joined(separator: " - ")
            let subtitle = row.expiryDateKey.isEmpty ? row.documentType : "Expires \(row.expiryDateKey)"
            let payload: [String: Any] = [
                "source": "renewal_item",
                "renewal_item_id": row.renewalItemID,
                "schema": Self.personalIdentificationSchemaKey
            ]
            let cardUpdatedAt = row.updatedAtMs > 0 ? row.updatedAtMs : nowMs
            let existingUpdatedAt = loadCard(cardID: cardID).map { int64Any($0["updated_at_ms"]) } ?? 0
            let shouldEnqueue = existingUpdatedAt == 0 || existingUpdatedAt < cardUpdatedAt

            upsertCard(
                cardID: cardID,
                schemaKey: Self.personalIdentificationSchemaKey,
                title: title,
                subtitle: subtitle,
                status: row.status,
                priority: row.priority,
                area: "Database",
                context: "Personal Identification",
                ownerScope: row.ownerScope,
                sourceEntity: "renewal_item",
                sourceID: row.renewalItemID,
                payloadJSON: jsonString(payload),
                createdAtMs: row.createdAtMs > 0 ? row.createdAtMs : nowMs,
                updatedAtMs: cardUpdatedAt,
                deleted: row.deleted
            )

            upsertField(cardID: cardID, key: "person_name", type: "string", string: row.personName, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "document_name", type: "string", string: row.documentName, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "document_type", type: "string", string: row.documentType, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "jurisdiction", type: "string", string: row.jurisdiction, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "document_number_hint", type: "string", string: row.documentNumberHint, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "expiry_date", type: "date", date: row.expiryDateKey, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "reminder_offsets", type: "json", json: row.reminderOffsetsJSON, updatedAtMs: nowMs, deleted: row.deleted)
            upsertField(cardID: cardID, key: "notes", type: "string", string: row.notes, updatedAtMs: nowMs, deleted: row.deleted)
            if shouldEnqueue {
                enqueueDirty?("card", cardID, "upsert", cardUpdatedAt)
            }
        }
    }

    func listPersonalIdentificationRecords(ownerScope: String = "ME") -> [NJRenewalItemRecord] {
        let cardIDs: [String] = db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT card_id
            FROM nj_card
            WHERE schema_key = ?
              AND deleted = 0
              AND owner_scope = ?
            ORDER BY
              CASE WHEN trim(subtitle) = '' THEN 1 ELSE 0 END ASC,
              title COLLATE NOCASE ASC,
              updated_at_ms DESC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, Self.personalIdentificationSchemaKey)
            bindText(stmt, 2, ownerScope)

            var out: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(colText(stmt, 0))
            }
            return out
        }

        let rows = cardIDs.compactMap { cardID -> NJRenewalItemRecord? in
            guard let card = loadCard(cardID: cardID) else { return nil }
            let fields = fieldStringMap(cardID: cardID)
            let renewalItemID = stringAny(card["source_id"], fallback: cardID.replacingOccurrences(of: "card.personal_id.", with: ""))
            return NJRenewalItemRecord(
                renewalItemID: renewalItemID,
                ownerScope: stringAny(card["owner_scope"], fallback: ownerScope),
                personName: fields["person_name"] ?? "",
                documentName: fields["document_name"] ?? stringAny(card["title"]),
                documentType: fields["document_type"] ?? "",
                jurisdiction: fields["jurisdiction"] ?? "",
                documentNumberHint: fields["document_number_hint"] ?? "",
                expiryDateKey: fields["expiry_date"] ?? "",
                status: stringAny(card["status"]),
                priority: stringAny(card["priority"]),
                reminderOffsetsJSON: fields["reminder_offsets"] ?? "[]",
                notes: fields["notes"] ?? "",
                createdAtMs: int64Any(card["created_at_ms"]),
                updatedAtMs: int64Any(card["updated_at_ms"]),
                deleted: int64Any(card["deleted"])
            )
        }

        return rows.sorted {
            let leftKey = $0.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightKey = $1.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if leftKey.isEmpty != rightKey.isEmpty { return !leftKey.isEmpty }
            if leftKey != rightKey { return leftKey < rightKey }
            if $0.personName.localizedCaseInsensitiveCompare($1.personName) != .orderedSame {
                return $0.personName.localizedCaseInsensitiveCompare($1.personName) == .orderedAscending
            }
            return $0.documentName.localizedCaseInsensitiveCompare($1.documentName) == .orderedAscending
        }
    }

    func upsertPersonalIdentificationRecord(_ row: NJRenewalItemRecord, nowMs: Int64) {
        mirrorPersonalIdentificationCards(from: [row], nowMs: nowMs)
    }

    func markPersonalIdentificationDeleted(renewalItemID: String, nowMs: Int64) {
        let cardID = "card.personal_id.\(renewalItemID)"
        db.exec("""
        UPDATE nj_card
        SET deleted = 1,
            updated_at_ms = \(nowMs)
        WHERE card_id = '\(cardID.replacingOccurrences(of: "'", with: "''"))';
        """)
        db.exec("""
        UPDATE nj_card_field_value
        SET deleted = 1,
            updated_at_ms = \(nowMs)
        WHERE card_id = '\(cardID.replacingOccurrences(of: "'", with: "''"))';
        """)
        enqueueDirty?("card", cardID, "upsert", nowMs)
    }

    func loadCardSchema(schemaKey: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT schema_key, display_name, category, field_defs_json, view_defs_json,
                   version, created_at_ms, updated_at_ms, deleted
            FROM nj_card_schema
            WHERE schema_key = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, schemaKey)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return [
                "schema_key": colText(stmt, 0),
                "display_name": colText(stmt, 1),
                "category": colText(stmt, 2),
                "field_defs_json": colText(stmt, 3),
                "view_defs_json": colText(stmt, 4),
                "version": sqlite3_column_int64(stmt, 5),
                "created_at_ms": sqlite3_column_int64(stmt, 6),
                "updated_at_ms": sqlite3_column_int64(stmt, 7),
                "deleted": sqlite3_column_int64(stmt, 8)
            ]
        }
    }

    func loadCard(cardID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT card_id, schema_key, title, subtitle, status, priority, area, context,
                   owner_scope, source_entity, source_id, note_id, payload_json,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_card
            WHERE card_id = ?
            LIMIT 1;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, cardID)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return [
                "card_id": colText(stmt, 0),
                "schema_key": colText(stmt, 1),
                "title": colText(stmt, 2),
                "subtitle": colText(stmt, 3),
                "status": colText(stmt, 4),
                "priority": colText(stmt, 5),
                "area": colText(stmt, 6),
                "context": colText(stmt, 7),
                "owner_scope": colText(stmt, 8),
                "source_entity": colText(stmt, 9),
                "source_id": colText(stmt, 10),
                "note_id": colText(stmt, 11),
                "payload_json": colText(stmt, 12),
                "fields_json": fieldsJSON(cardID: cardID),
                "created_at_ms": sqlite3_column_int64(stmt, 13),
                "updated_at_ms": sqlite3_column_int64(stmt, 14),
                "deleted": sqlite3_column_int64(stmt, 15)
            ]
        }
    }

    func applyRemoteCardSchema(_ fields: [String: Any]) {
        let schemaKey = stringAny(fields["schema_key"], fallback: stringAny(fields["id"]))
        guard !schemaKey.isEmpty else { return }
        let incomingUpdatedAt = int64Any(fields["updated_at_ms"])
        if let existing = loadCardSchema(schemaKey: schemaKey) {
            let existingUpdatedAt = int64Any(existing["updated_at_ms"])
            if existingUpdatedAt > incomingUpdatedAt, incomingUpdatedAt > 0 { return }
        }

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_card_schema(
                schema_key, display_name, category, field_defs_json, view_defs_json,
                version, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(schema_key) DO UPDATE SET
                display_name = excluded.display_name,
                category = excluded.category,
                field_defs_json = excluded.field_defs_json,
                view_defs_json = excluded.view_defs_json,
                version = excluded.version,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, schemaKey)
            bindText(stmt, 2, stringAny(fields["display_name"]))
            bindText(stmt, 3, stringAny(fields["category"]))
            bindText(stmt, 4, stringAny(fields["field_defs_json"], fallback: "[]"))
            bindText(stmt, 5, stringAny(fields["view_defs_json"], fallback: "[]"))
            sqlite3_bind_int64(stmt, 6, int64Any(fields["version"], fallback: 1))
            sqlite3_bind_int64(stmt, 7, int64Any(fields["created_at_ms"]))
            sqlite3_bind_int64(stmt, 8, incomingUpdatedAt)
            sqlite3_bind_int64(stmt, 9, int64Any(fields["deleted"]))
            _ = sqlite3_step(stmt)
        }
    }

    func applyRemoteCard(_ fields: [String: Any]) {
        let cardID = stringAny(fields["card_id"], fallback: stringAny(fields["id"]))
        guard !cardID.isEmpty else { return }
        let incomingUpdatedAt = int64Any(fields["updated_at_ms"])
        if let existing = loadCard(cardID: cardID) {
            let existingUpdatedAt = int64Any(existing["updated_at_ms"])
            if existingUpdatedAt > incomingUpdatedAt, incomingUpdatedAt > 0 { return }
        }

        upsertCard(
            cardID: cardID,
            schemaKey: stringAny(fields["schema_key"]),
            title: stringAny(fields["title"]),
            subtitle: stringAny(fields["subtitle"]),
            status: stringAny(fields["status"]),
            priority: stringAny(fields["priority"]),
            area: stringAny(fields["area"]),
            context: stringAny(fields["context"]),
            ownerScope: stringAny(fields["owner_scope"], fallback: "ME"),
            sourceEntity: stringAny(fields["source_entity"]),
            sourceID: stringAny(fields["source_id"]),
            payloadJSON: stringAny(fields["payload_json"], fallback: "{}"),
            createdAtMs: int64Any(fields["created_at_ms"]),
            updatedAtMs: incomingUpdatedAt,
            deleted: int64Any(fields["deleted"])
        )

        applyRemoteFieldsJSON(cardID: cardID, fieldsJSON: stringAny(fields["fields_json"], fallback: "{}"), updatedAtMs: incomingUpdatedAt)
    }

    private func upsertCard(
        cardID: String,
        schemaKey: String,
        title: String,
        subtitle: String,
        status: String,
        priority: String,
        area: String,
        context: String,
        ownerScope: String,
        sourceEntity: String,
        sourceID: String,
        payloadJSON: String,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        deleted: Int64
    ) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_card(
                card_id, schema_key, title, subtitle, status, priority, area, context,
                owner_scope, source_entity, source_id, note_id, payload_json,
                created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?)
            ON CONFLICT(card_id) DO UPDATE SET
                schema_key = excluded.schema_key,
                title = excluded.title,
                subtitle = excluded.subtitle,
                status = excluded.status,
                priority = excluded.priority,
                area = excluded.area,
                context = excluded.context,
                owner_scope = excluded.owner_scope,
                source_entity = excluded.source_entity,
                source_id = excluded.source_id,
                payload_json = excluded.payload_json,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, cardID)
            bindText(stmt, 2, schemaKey)
            bindText(stmt, 3, title)
            bindText(stmt, 4, subtitle)
            bindText(stmt, 5, status)
            bindText(stmt, 6, priority)
            bindText(stmt, 7, area)
            bindText(stmt, 8, context)
            bindText(stmt, 9, ownerScope)
            bindText(stmt, 10, sourceEntity)
            bindText(stmt, 11, sourceID)
            bindText(stmt, 12, payloadJSON)
            sqlite3_bind_int64(stmt, 13, createdAtMs)
            sqlite3_bind_int64(stmt, 14, updatedAtMs)
            sqlite3_bind_int64(stmt, 15, deleted)
            _ = sqlite3_step(stmt)
        }
    }

    private func fieldsJSON(cardID: String) -> String {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT field_key, value_type, string_value, number_value, date_value, bool_value, json_value
            FROM nj_card_field_value
            WHERE card_id = ? AND deleted = 0
            ORDER BY field_key ASC;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return "{}" }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, cardID)

            var out: [String: Any] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = colText(stmt, 0)
                let type = colText(stmt, 1)
                switch type {
                case "number":
                    out[key] = sqlite3_column_double(stmt, 3)
                case "date":
                    out[key] = colText(stmt, 4)
                case "bool":
                    out[key] = sqlite3_column_int64(stmt, 5) != 0
                case "json":
                    out[key] = colText(stmt, 6)
                default:
                    out[key] = colText(stmt, 2)
                }
            }
            return jsonString(out)
        }
    }

    private func fieldStringMap(cardID: String) -> [String: String] {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT field_key, value_type, string_value, number_value, date_value, bool_value, json_value
            FROM nj_card_field_value
            WHERE card_id = ? AND deleted = 0;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, cardID)

            var out: [String: String] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = colText(stmt, 0)
                let type = colText(stmt, 1)
                switch type {
                case "number":
                    out[key] = String(sqlite3_column_double(stmt, 3))
                case "date":
                    out[key] = colText(stmt, 4)
                case "bool":
                    out[key] = sqlite3_column_int64(stmt, 5) == 0 ? "false" : "true"
                case "json":
                    out[key] = colText(stmt, 6)
                default:
                    out[key] = colText(stmt, 2)
                }
            }
            return out
        }
    }

    private func applyRemoteFieldsJSON(cardID: String, fieldsJSON: String, updatedAtMs: Int64) {
        guard let data = fieldsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        for (key, value) in object {
            if let bool = value as? Bool {
                upsertField(cardID: cardID, key: key, type: "bool", updatedAtMs: updatedAtMs, deleted: 0, bool: bool ? 1 : 0)
            } else if let number = value as? NSNumber {
                upsertField(cardID: cardID, key: key, type: "number", updatedAtMs: updatedAtMs, deleted: 0, number: number.doubleValue)
            } else {
                upsertField(cardID: cardID, key: key, type: "string", string: "\(value)", updatedAtMs: updatedAtMs, deleted: 0)
            }
        }
    }

    private func upsertField(
        cardID: String,
        key: String,
        type: String,
        string: String = "",
        date: String = "",
        json: String = "",
        updatedAtMs: Int64,
        deleted: Int64,
        number: Double = 0,
        bool: Int64 = 0
    ) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_card_field_value(
                card_id, field_key, value_type, string_value, number_value,
                date_value, bool_value, json_value, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(card_id, field_key) DO UPDATE SET
                value_type = excluded.value_type,
                string_value = excluded.string_value,
                number_value = excluded.number_value,
                date_value = excluded.date_value,
                bool_value = excluded.bool_value,
                json_value = excluded.json_value,
                updated_at_ms = excluded.updated_at_ms,
                deleted = excluded.deleted;
            """
            guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, cardID)
            bindText(stmt, 2, key)
            bindText(stmt, 3, type)
            bindText(stmt, 4, string)
            sqlite3_bind_double(stmt, 5, number)
            bindText(stmt, 6, date)
            sqlite3_bind_int64(stmt, 7, bool)
            bindText(stmt, 8, json)
            sqlite3_bind_int64(stmt, 9, updatedAtMs)
            sqlite3_bind_int64(stmt, 10, deleted)
            _ = sqlite3_step(stmt)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func colText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private func stringAny(_ value: Any?, fallback: String = "") -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return fallback
    }

    private func int64Any(_ value: Any?, fallback: Int64 = 0) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? fallback }
        return fallback
    }

    private func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
