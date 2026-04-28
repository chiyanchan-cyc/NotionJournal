//
//  DBNoteBlockTable.swift
//  Notion Journal
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBNoteBlockTable {
    let db: SQLiteDB
    let enqueueDirtyFn: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirtyFn = enqueueDirty
    }

    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        enqueueDirtyFn(entity, entityID, op, updatedAtMs)
    }

    func loadNJNoteBlock(noteID: String, orderKey: Double) -> [String: Any]? {
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT instance_id, note_id, block_id, order_key, is_checked,
                   card_row_id, card_status, card_priority, card_category, card_area, card_context, card_title,
                   view_state_json, created_at_ms, updated_at_ms, deleted
            FROM nj_note_block
            WHERE note_id=? AND order_key=? AND deleted=0
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, orderKey)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            return [
                "instance_id": sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? "",
                "note_id": sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? "",
                "block_id": sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "",
                "order_key": sqlite3_column_double(stmt, 3),
                "is_checked": sqlite3_column_int64(stmt, 4),
                "card_row_id": sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? "",
                "card_status": sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? "",
                "card_priority": sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? "",
                "card_category": sqlite3_column_text(stmt, 8).flatMap { String(cString: $0) } ?? "",
                "card_area": sqlite3_column_text(stmt, 9).flatMap { String(cString: $0) } ?? "",
                "card_context": sqlite3_column_text(stmt, 10).flatMap { String(cString: $0) } ?? "",
                "card_title": sqlite3_column_text(stmt, 11).flatMap { String(cString: $0) } ?? "",
                "view_state_json": sqlite3_column_text(stmt, 12).flatMap { String(cString: $0) } ?? "",
                "created_at_ms": sqlite3_column_int64(stmt, 13),
                "updated_at_ms": sqlite3_column_int64(stmt, 14),
                "deleted": sqlite3_column_int64(stmt, 15)
            ]
        }
    }

    func loadNJNoteBlock(instanceID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT
              instance_id,
              note_id,
              block_id,
              order_key,
              is_checked,
              card_row_id,
              card_status,
              card_priority,
              card_category,
              card_area,
              card_context,
              card_title,
              view_state_json,
              created_at_ms,
              updated_at_ms,
              deleted
            FROM nj_note_block
            WHERE instance_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadNJNoteBlock.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, instanceID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let noteID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let blockID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
            let orderKey = sqlite3_column_double(stmt, 3)
            let isChecked = sqlite3_column_int64(stmt, 4)
            let cardRowID = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""
            let cardStatus = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? ""
            let cardPriority = sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? ""
            let cardCategory = sqlite3_column_text(stmt, 8).flatMap { String(cString: $0) } ?? ""
            let cardArea = sqlite3_column_text(stmt, 9).flatMap { String(cString: $0) } ?? ""
            let cardContext = sqlite3_column_text(stmt, 10).flatMap { String(cString: $0) } ?? ""
            let cardTitle = sqlite3_column_text(stmt, 11).flatMap { String(cString: $0) } ?? ""
            let viewStateJSON = sqlite3_column_text(stmt, 12).flatMap { String(cString: $0) } ?? ""
            let createdAtMs = sqlite3_column_int64(stmt, 13)
            let updatedAtMs = sqlite3_column_int64(stmt, 14)
            let deleted = sqlite3_column_int64(stmt, 15)

            return [
                "instance_id": instanceID,
                "note_id": noteID,
                "block_id": blockID,
                "order_key": orderKey,
                "is_checked": isChecked,
                "card_row_id": cardRowID,
                "card_status": cardStatus,
                "card_priority": cardPriority,
                "card_category": cardCategory,
                "card_area": cardArea,
                "card_context": cardContext,
                "card_title": cardTitle,
                "view_state_json": viewStateJSON,
                "created_at_ms": createdAtMs,
                "updated_at_ms": updatedAtMs,
                "deleted": deleted
            ]
        }
    }

    private func doubleAny(_ v: Any?) -> Double {
        if let v = v as? Double { return v }
        if let v = v as? Float { return Double(v) }
        if let v = v as? Int { return Double(v) }
        if let v = v as? Int64 { return Double(v) }
        if let v = v as? NSNumber { return v.doubleValue }
        if let v = v as? String { return Double(v) ?? 0 }
        return 0
    }

    private func int64Any(_ v: Any?) -> Int64 {
        if let v = v as? Int64 { return v }
        if let v = v as? Int { return Int64(v) }
        if let v = v as? NSNumber { return v.int64Value }
        if let v = v as? String { return Int64(v) ?? 0 }
        return 0
    }

    func applyNJNoteBlock(_ f: [String: Any]) {
        let instanceID =
          (f["instance_id"] as? String) ??
          (f["instanceID"] as? String) ??
          (f["id"] as? String) ??
          ""
        if instanceID.isEmpty { return }

        let noteID = (f["note_id"] as? String) ?? ""
        let blockID = (f["block_id"] as? String) ?? ""
        let orderKey = doubleAny(f["order_key"])
        let isChecked = int64Any(f["is_checked"]) > 0 ? Int64(1) : Int64(0)
        let cardRowID = (f["card_row_id"] as? String) ?? ""
        let cardStatus = (f["card_status"] as? String) ?? ""
        let cardPriority = (f["card_priority"] as? String) ?? ""
        let cardCategory = (f["card_category"] as? String) ?? ""
        let cardArea = (f["card_area"] as? String) ?? ""
        let cardContext = (f["card_context"] as? String) ?? ""
        let cardTitle = (f["card_title"] as? String) ?? ""
        let viewStateJSON = (f["view_state_json"] as? String) ?? ""
        let createdAtMs = int64Any(f["created_at_ms"])
        let updatedAtMs = int64Any(f["updated_at_ms"])
        let deleted = int64Any(f["deleted"])
        if let existing = loadNJNoteBlock(instanceID: instanceID) {
            let existingUpdatedAt = (existing["updated_at_ms"] as? Int64) ?? 0
            let existingDeleted = (existing["deleted"] as? Int64) ?? 0
            if existingUpdatedAt > updatedAtMs, updatedAtMs > 0 {
                return
            }
            if existingUpdatedAt == updatedAtMs,
               existingDeleted > deleted {
                return
            }
        }

        db.withDB { dbp in
            if !blockID.isEmpty {
                var ensureBlockStmt: OpaquePointer?
                let ensureBlockSQL = """
                INSERT OR IGNORE INTO nj_block(
                  block_id, block_type, payload_json, domain_tag, tag_json, goal_id,
                  lineage_id, parent_block_id, created_at_ms, updated_at_ms, deleted, dirty_bl
                )
                VALUES(?, 'text', '{}', '', '', NULL, '', '', 0, 0, 0, 0);
                """
                if sqlite3_prepare_v2(dbp, ensureBlockSQL, -1, &ensureBlockStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(ensureBlockStmt, 1, blockID, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(ensureBlockStmt)
                }
                sqlite3_finalize(ensureBlockStmt)
            }

            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_note_block(
              instance_id,
              note_id,
              block_id,
              order_key,
              is_checked,
              card_row_id,
              card_status,
              card_priority,
              card_category,
              card_area,
              card_context,
              card_title,
              view_state_json,
              created_at_ms,
              updated_at_ms,
              deleted
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(instance_id) DO UPDATE SET
              note_id=excluded.note_id,
              block_id=excluded.block_id,
              order_key=excluded.order_key,
              is_checked=excluded.is_checked,
              card_row_id=excluded.card_row_id,
              card_status=excluded.card_status,
              card_priority=excluded.card_priority,
              card_category=excluded.card_category,
              card_area=excluded.card_area,
              card_context=excluded.card_context,
              card_title=excluded.card_title,
              view_state_json=excluded.view_state_json,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyNJNoteBlock.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, instanceID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, orderKey)
            sqlite3_bind_int64(stmt, 5, isChecked)
            sqlite3_bind_text(stmt, 6, cardRowID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, cardStatus, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, cardPriority, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, cardCategory, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 10, cardArea, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 11, cardContext, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 12, cardTitle, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 13, viewStateJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 14, createdAtMs)
            sqlite3_bind_int64(stmt, 15, updatedAtMs)
            sqlite3_bind_int64(stmt, 16, deleted)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyNJNoteBlock.step", rc1) }
        }
        // Remote apply must not enqueue dirty again; local edit paths already do that.
    }

    func updateEditorLease(instanceID: String, deviceID: String, nowMs: Int64, expiresAtMs: Int64) {
        guard !instanceID.isEmpty, !deviceID.isEmpty else { return }

        let existingJSON = loadNJNoteBlock(instanceID: instanceID)?["view_state_json"] as? String ?? ""
        var root: [String: Any] = [:]
        if let data = existingJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = object
        }

        root["editor_lease"] = [
            "device_id": deviceID,
            "updated_at_ms": nowMs,
            "expires_at_ms": expiresAtMs
        ]

        let nextJSON: String = {
            guard JSONSerialization.isValidJSONObject(root),
                  let data = try? JSONSerialization.data(withJSONObject: root, options: []),
                  let s = String(data: data, encoding: .utf8) else {
                return existingJSON
            }
            return s
        }()

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note_block
            SET view_state_json=?,
                updated_at_ms=?
            WHERE instance_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "updateEditorLease.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nextJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, nowMs)
            sqlite3_bind_text(stmt, 3, instanceID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "updateEditorLease.step", rc1) }
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: nowMs)
    }

    func activeRemoteEditorLease(blockID: String, localDeviceID: String, nowMs: Int64) -> (deviceID: String, expiresAtMs: Int64)? {
        guard !blockID.isEmpty else { return nil }

        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT view_state_json
            FROM nj_note_block
            WHERE block_id=? AND deleted=0 AND view_state_json <> '';
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "activeRemoteEditorLease.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let json = String(cString: c)
                guard let data = json.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let lease = root["editor_lease"] as? [String: Any] else {
                    continue
                }
                let deviceID = (lease["device_id"] as? String) ?? ""
                let expiresAtMs = int64Any(lease["expires_at_ms"])
                guard !deviceID.isEmpty,
                      deviceID != localDeviceID,
                      expiresAtMs > nowMs else {
                    continue
                }
                return (deviceID, expiresAtMs)
            }
            return nil
        }
    }

    func findFirstInstanceByBlock(blockID: String) -> (noteID: String, instanceID: String)? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT note_id, instance_id
            FROM nj_note_block
            WHERE block_id=? AND deleted=0
            ORDER BY order_key ASC
            LIMIT 1;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "findFirstInstanceByBlock.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let noteID = String(cString: sqlite3_column_text(stmt, 0))
            let instanceID = String(cString: sqlite3_column_text(stmt, 1))
            return (noteID, instanceID)
        }
    }

    func markNoteBlockDeleted(instanceID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note_block
            SET deleted=1,
                updated_at_ms=?
            WHERE instance_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "markNoteBlockDeleted.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, instanceID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "markNoteBlockDeleted.step", rc1) }
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: nowMs)
    }

    func hasLiveInstance(blockID: String) -> Bool {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT 1
            FROM nj_note_block
            WHERE block_id=? AND deleted=0
            LIMIT 1;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "hasLiveInstance.prepare", rc0); return false }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    func liveInstances(noteID: String) -> [(instanceID: String, blockID: String)] {
        db.withDB { dbp in
            var out: [(instanceID: String, blockID: String)] = []
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT instance_id, block_id
            FROM nj_note_block
            WHERE note_id=? AND deleted=0
            ORDER BY order_key ASC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "liveInstances.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let instanceID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let blockID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                if !instanceID.isEmpty && !blockID.isEmpty {
                    out.append((instanceID, blockID))
                }
            }
            return out
        }
    }

    func setChecked(instanceID: String, isChecked: Bool, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note_block
            SET is_checked=?,
                updated_at_ms=?
            WHERE instance_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "setChecked.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, isChecked ? 1 : 0)
            sqlite3_bind_int64(stmt, 2, nowMs)
            sqlite3_bind_text(stmt, 3, instanceID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "setChecked.step", rc1) }
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: nowMs)
    }

    func nextCardRowID(noteID: String) -> String {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT card_row_id
            FROM nj_note_block
            WHERE note_id=? AND deleted=0 AND card_row_id <> '';
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                db.dbgErr(dbp, "nextCardRowID.prepare", rc0)
                return "1"
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
            var maxValue = 0
            while sqlite3_step(stmt) == SQLITE_ROW {
                let raw = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let digits = raw.filter(\.isNumber)
                if let value = Int(digits) {
                    maxValue = max(maxValue, value)
                }
            }
            return String(maxValue + 1)
        }
    }

    func updateCardRowFields(
        instanceID: String,
        cardRowID: String,
        status: String,
        priority: String,
        category: String,
        area: String,
        context: String,
        title: String,
        nowMs: Int64
    ) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note_block
            SET card_row_id=?,
                card_status=?,
                card_priority=?,
                card_category=?,
                card_area=?,
                card_context=?,
                card_title=?,
                updated_at_ms=?
            WHERE instance_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "updateCardRowFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, cardRowID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, priority, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, area, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, context, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, nowMs)
            sqlite3_bind_text(stmt, 9, instanceID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "updateCardRowFields.step", rc1) }
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: nowMs)
    }

    func liveInstances(blockID: String) -> [(instanceID: String, noteID: String)] {
        db.withDB { dbp in
            var out: [(instanceID: String, noteID: String)] = []
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT instance_id, note_id
            FROM nj_note_block
            WHERE block_id=? AND deleted=0
            ORDER BY order_key ASC;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "liveInstancesByBlock.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let instanceID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let noteID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                if !instanceID.isEmpty && !noteID.isEmpty {
                    out.append((instanceID, noteID))
                }
            }
            return out
        }
    }
}
