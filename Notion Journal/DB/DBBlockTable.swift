//
//  DBBlockTable.swift
//  Notion Journal
//

import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBBlockTable {
    let db: SQLiteDB
    let enqueueDirtyFn: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirtyFn = enqueueDirty
    }

    
    struct NJOrphanClipRow: Identifiable {
        let id: String
        let createdAtMs: Int64
        let payloadJSON: String
    }

    struct NJOrphanAudioRow: Identifiable {
        let id: String
        let createdAtMs: Int64
        let payloadJSON: String
    }

    struct NJOrphanQuickRow: Identifiable {
        let id: String
        let createdAtMs: Int64
        let payloadJSON: String
    }

    struct NJAudioRow: Identifiable {
        let id: String
        let updatedAtMs: Int64
        let payloadJSON: String
    }
    
//    func loadBlockCreatedAtMs(blockID: String) -> Int64 {
//        db.withDB { dbp in
//            var out: Int64 = 0
//            var stmt: OpaquePointer?
//            let sql = "SELECT created_at_ms FROM nj_block WHERE block_id = ? LIMIT 1;"
//            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return 0 }
//            defer { sqlite3_finalize(stmt) }
//            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
//            if sqlite3_step(stmt) == SQLITE_ROW {
//                out = sqlite3_column_int64(stmt, 0)
//            }
//            return out
//        }
//    }
//
//    func loadBlockTagJSON(blockID: String) -> String {
//        db.withDB { dbp in
//            var out = ""
//            var stmt: OpaquePointer?
//            let sql = "SELECT tag_json FROM nj_block WHERE block_id = ? LIMIT 1;"
//            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
//            defer { sqlite3_finalize(stmt) }
//            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
//            if sqlite3_step(stmt) == SQLITE_ROW {
//                if let c = sqlite3_column_text(stmt, 0) { out = String(cString: c) }
//            }
//            return out
//        }
//    }
//
//    func loadDomainPreview3FromBlockTag(blockID: String) -> String {
//        db.withDB { dbp in
//            var tags: [String] = []
//            var stmt: OpaquePointer?
//            let sql = """
//            SELECT domain
//            FROM nj_block_tag
//            WHERE block_id = ? AND deleted = 0
//            ORDER BY created_at_ms ASC
//            LIMIT 3;
//            """
//            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
//            defer { sqlite3_finalize(stmt) }
//            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
//            while sqlite3_step(stmt) == SQLITE_ROW {
//                if let c = sqlite3_column_text(stmt, 0) {
//                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
//                    if !s.isEmpty { tags.append(s) }
//                }
//            }
//            return tags.joined(separator: ", ")
//        }
//    }
    
    func loadBlockPayloadJSON(blockID: String) -> String {
        db.withDB { dbp in
            var out = ""
            let sql = "SELECT payload_json FROM nj_block WHERE block_id = ? LIMIT 1;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    out = String(cString: c)
                }
            }
            return out
        }
    }

    func listOrphanClipBlocks(limit: Int = 200) -> [NJOrphanClipRow] {
        var out: [NJOrphanClipRow] = []

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT b.block_id, b.created_at_ms, b.payload_json
            FROM nj_block b
            LEFT JOIN nj_note_block nb
              ON nb.block_id = b.block_id AND nb.deleted = 0
            WHERE b.block_type = 'clip'
              AND b.deleted = 0
              AND nb.block_id IS NULL
            ORDER BY b.created_at_ms DESC
            LIMIT ?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bid = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                    if bid.isEmpty { continue }
                    let ms = sqlite3_column_int64(stmt, 1)
                    let payload = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "{}"
                    out.append(NJOrphanClipRow(id: bid, createdAtMs: ms, payloadJSON: payload))
                }
            }
            sqlite3_finalize(stmt)
        }

        return out
    }

    func listOrphanAudioBlocks(limit: Int = 200) -> [NJOrphanAudioRow] {
        var out: [NJOrphanAudioRow] = []

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT b.block_id, b.created_at_ms, b.payload_json
            FROM nj_block b
            LEFT JOIN nj_note_block nb
              ON nb.block_id = b.block_id AND nb.deleted = 0
            WHERE b.block_type = 'audio'
              AND b.deleted = 0
              AND nb.block_id IS NULL
            ORDER BY b.created_at_ms DESC
            LIMIT ?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bid = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                    if bid.isEmpty { continue }
                    let ms = sqlite3_column_int64(stmt, 1)
                    let payload = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "{}"
                    out.append(NJOrphanAudioRow(id: bid, createdAtMs: ms, payloadJSON: payload))
                }
            }
            sqlite3_finalize(stmt)
        }

        return out
    }

    func listOrphanQuickBlocks(limit: Int = 200) -> [NJOrphanQuickRow] {
        var out: [NJOrphanQuickRow] = []

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT b.block_id, b.created_at_ms, b.payload_json
            FROM nj_block b
            LEFT JOIN nj_note_block nb
              ON nb.block_id = b.block_id AND nb.deleted = 0
            WHERE b.block_type = 'quick'
              AND b.deleted = 0
              AND nb.block_id IS NULL
            ORDER BY b.created_at_ms DESC
            LIMIT ?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bid = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                    if bid.isEmpty { continue }
                    let ms = sqlite3_column_int64(stmt, 1)
                    let payload = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "{}"
                    out.append(NJOrphanQuickRow(id: bid, createdAtMs: ms, payloadJSON: payload))
                }
            }
            sqlite3_finalize(stmt)
        }

        return out
    }

    func listAudioBlocks(limit: Int = 200) -> [NJAudioRow] {
        var out: [NJAudioRow] = []

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT b.block_id, b.updated_at_ms, b.payload_json
            FROM nj_block b
            WHERE b.block_type = 'audio'
              AND b.deleted = 0
            ORDER BY b.updated_at_ms ASC
            LIMIT ?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bid = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                    if bid.isEmpty { continue }
                    let ms = sqlite3_column_int64(stmt, 1)
                    let payload = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "{}"
                    out.append(NJAudioRow(id: bid, updatedAtMs: ms, payloadJSON: payload))
                }
            }
            sqlite3_finalize(stmt)
        }

        return out
    }

    func lastJournaledAtMsForTag(_ tag: String) -> Int64 {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT b.created_at_ms
            FROM nj_block_tag t
            JOIN nj_block b
              ON b.block_id = t.block_id
            WHERE t.tag = ? COLLATE NOCASE
              AND b.deleted = 0
            ORDER BY b.created_at_ms DESC
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return 0
        }
    }

    func countBlocksForTag(_ tag: String) -> Int {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let alternate = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : "#\(trimmed)"
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT COUNT(DISTINCT b.block_id)
            FROM nj_block_tag t
            JOIN nj_block b
              ON b.block_id = t.block_id
            WHERE (lower(t.tag) = lower(?) OR lower(t.tag) = lower(?))
              AND b.deleted = 0;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, alternate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int64(stmt, 0))
            }
            return 0
        }
    }

    func latestBlockIDForTag(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let alternate = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : "#\(trimmed)"
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let sqlIndexed = """
            SELECT b.block_id
            FROM nj_block_tag t
            JOIN nj_block b
              ON b.block_id = t.block_id
            WHERE (lower(t.tag) = lower(?) OR lower(t.tag) = lower(?))
              AND b.deleted = 0
            ORDER BY b.created_at_ms DESC, b.updated_at_ms DESC
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sqlIndexed, -1, &stmt, nil)
            if rc != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, alternate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let c = sqlite3_column_text(stmt, 0) {
                return String(cString: c)
            }

            sqlite3_finalize(stmt)
            stmt = nil

            let sqlFallback = """
            SELECT b.block_id
            FROM nj_block b
            WHERE b.deleted = 0
              AND (
                lower(COALESCE(b.tag_json, '')) LIKE lower(?)
                OR lower(COALESCE(b.tag_json, '')) LIKE lower(?)
              )
            ORDER BY b.created_at_ms DESC, b.updated_at_ms DESC
            LIMIT 1;
            """
            let rcFallback = sqlite3_prepare_v2(dbp, sqlFallback, -1, &stmt, nil)
            if rcFallback != SQLITE_OK { return "" }
            let p1 = "%\"\(trimmed)\"%"
            let p2 = "%\"\(alternate)\"%"
            sqlite3_bind_text(stmt, 1, p1, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, p2, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let c = sqlite3_column_text(stmt, 0) {
                return String(cString: c)
            }
            return ""
        }
    }

    func markBlockDeleted(blockID: String) {
        let now = DBNoteRepository.nowMs()
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET deleted=1,
                updated_at_ms=?,
                dirty_bl=1
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "markBlockDeleted.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, now)
            sqlite3_bind_text(stmt, 2, blockID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "markBlockDeleted.step", rc1) }
        }
        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: now)
    }

    func repairFutureUpdatedAtMsForAllBlocks(nowMs: Int64, skewMs: Int64 = 5 * 60 * 1000) -> Int {
        var repaired: [String] = []

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let selectSQL = """
            SELECT block_id
            FROM nj_block
            WHERE deleted = 0
              AND updated_at_ms > ?;
            """
            if sqlite3_prepare_v2(dbp, selectSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, nowMs + skewMs)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let c = sqlite3_column_text(stmt, 0) {
                        repaired.append(String(cString: c))
                    }
                }
            }
            sqlite3_finalize(stmt)

            guard !repaired.isEmpty else { return }

            var updateStmt: OpaquePointer?
            let updateSQL = """
            UPDATE nj_block
            SET updated_at_ms = ?, dirty_bl = 1
            WHERE block_id = ?;
            """
            if sqlite3_prepare_v2(dbp, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
                for blockID in repaired {
                    sqlite3_reset(updateStmt)
                    sqlite3_clear_bindings(updateStmt)
                    sqlite3_bind_int64(updateStmt, 1, nowMs)
                    sqlite3_bind_text(updateStmt, 2, blockID, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(updateStmt)
                }
            }
            sqlite3_finalize(updateStmt)
        }

        for blockID in repaired {
            enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: nowMs)
        }

        return repaired.count
    }

    func hasFutureUpdatedAtBlocks(nowMs: Int64, skewMs: Int64 = 5 * 60 * 1000) -> Bool {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT 1
            FROM nj_block
            WHERE deleted = 0
              AND updated_at_ms > ?
            LIMIT 1;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return false }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, nowMs + skewMs)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    func updateBlockPayloadJSON(blockID: String, payloadJSON: String, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET payload_json=?,
                updated_at_ms=?,
                dirty_bl=1,
                deleted=0
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "updateBlockPayloadJSON.prepare", rc); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, payloadJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, updatedAtMs)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)

            let rc2 = sqlite3_step(stmt)
            if rc2 != SQLITE_DONE { db.dbgErr(dbp, "updateBlockPayloadJSON.step", rc2) }
        }
        if !DBDirtyQueueTable.isInPullScope() {
            enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
        }
    }

    func migrateAllBlockPayloadsToProtonDocV2(nowMs: Int64) -> (scanned: Int, changed: Int) {
        let rows: [(String, String)] = db.withDB { dbp in
            var out: [(String, String)] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT block_id, payload_json
            FROM nj_block
            WHERE COALESCE(payload_json, '') <> '';
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK {
                db.dbgErr(dbp, "migrateAllBlockPayloadsToProtonDocV2.select.prepare", rc)
                return out
            }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let blockID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let payloadJSON = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                if !blockID.isEmpty {
                    out.append((blockID, payloadJSON))
                }
            }
            return out
        }

        var changed = 0
        for (index, row) in rows.enumerated() {
            guard let normalized = Self.normalizedBlockPayloadForProtonDocV2Migration(row.1),
                  normalized != row.1 else {
                continue
            }
            updateBlockPayloadJSON(
                blockID: row.0,
                payloadJSON: normalized,
                updatedAtMs: nowMs + Int64(index)
            )
            changed += 1
        }

        if changed > 0 {
            print("NJ_BLOCK_PAYLOAD_V2_MIGRATION scanned=\(rows.count) changed=\(changed)")
        }
        return (rows.count, changed)
    }

    private static func normalizedBlockPayloadForProtonDocV2Migration(_ payloadJSON: String) -> String? {
        guard let normalized = try? NJPayloadConverterV1.convertToV1(payloadJSON),
              let data = normalized.data(using: .utf8),
              var payload = try? JSONDecoder().decode(NJPayloadV1.self, from: data) else {
            return nil
        }

        let changed = payload.normalizeProtonStorageToV2()
        guard changed || normalized != payloadJSON else { return nil }

        guard let out = try? JSONEncoder().encode(payload),
              let text = String(data: out, encoding: .utf8) else {
            return nil
        }
        return text
    }

    func updateBlockCreatedAtMs(blockID: String, createdAtMs: Int64, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET created_at_ms=?,
                updated_at_ms=?,
                dirty_bl=1,
                deleted=0
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "updateBlockCreatedAtMs.prepare", rc); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, createdAtMs)
            sqlite3_bind_int64(stmt, 2, updatedAtMs)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)

            let rc2 = sqlite3_step(stmt)
            if rc2 != SQLITE_DONE { db.dbgErr(dbp, "updateBlockCreatedAtMs.step", rc2) }
        }
        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
    }

    func setGoalID(blockID: String, goalID: String, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET goal_id=?,
                updated_at_ms=?,
                dirty_bl=1,
                deleted=0
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "setGoalID.prepare", rc); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, goalID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, updatedAtMs)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)

            let rc2 = sqlite3_step(stmt)
            if rc2 != SQLITE_DONE { db.dbgErr(dbp, "setGoalID.step", rc2) }
        }
        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
    }

    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        enqueueDirtyFn(entity, entityID, op, updatedAtMs)
    }

    func hasBlock(blockID: String) -> Bool {
        let sql = "SELECT 1 FROM nj_block WHERE block_id=? AND deleted=0 LIMIT 1;"
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "hasBlock.prepare", rc); return false }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    func upsertTagsForBlockID(blockID: String, tags: [String], nowMs: Int64) {
        let uniq = Array(Set(tags)).filter { !$0.isEmpty }.sorted()
        if uniq.isEmpty {
            print("NJ_TAG DBBlockTable.upsertTagsForBlockID skip empty tags")
           return
        }

        let exists = hasBlock(blockID: blockID)
        print("NJ_TAG DBBlockTable.upsertTagsForBlockID blockID=\(blockID) tags=\(uniq) exists=\(exists)")

        if !exists { return }

        let data = (try? JSONSerialization.data(withJSONObject: uniq)) ?? Data()
        let jsonStr = String(data: data, encoding: .utf8) ?? "[]"

        updateBlockTagJSON(blockID: blockID, tagJSON: jsonStr, updatedAtMs: nowMs)
        markBlockDirty(blockID: blockID, updatedAtMs: nowMs)
        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: nowMs)

    }
    
    func markBlockDirty(blockID: String, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET dirty_bl=1, updated_at_ms=?
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "markBlockDirty.prepare", rc); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, updatedAtMs)
            sqlite3_bind_text(stmt, 2, blockID, -1, SQLITE_TRANSIENT)

            let rc2 = sqlite3_step(stmt)
            if rc2 != SQLITE_DONE { db.dbgErr(dbp, "markBlockDirty.step", rc2) }
        }
    }

    func loadNJBlock(blockID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            SELECT
              block_id,
              block_type,
              payload_json,
              domain_tag,
              tag_json,
              goal_id,
              lineage_id,
              parent_block_id,
              created_at_ms,
              updated_at_ms,
              deleted
            FROM nj_block
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "loadNJBlock.prepare", rc); return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            return [
                "block_id": blockID,
                "block_type": sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? "",
                "payload_json": sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "",
                "domain_tag": sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? "",
                "tag_json": sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? "",
                "goal_id": sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? "",
                "lineage_id": sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? "",
                "parent_block_id": sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? "",
                "created_at_ms": sqlite3_column_int64(stmt, 8),
                "updated_at_ms": sqlite3_column_int64(stmt, 9),
                "deleted": sqlite3_column_int64(stmt, 10)
            ]
        }
    }

    private func hasPendingLocalPush(blockID: String) -> Bool {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            SELECT 1
            FROM nj_dirty
            WHERE entity='block'
              AND entity_id=? COLLATE NOCASE
              AND ignore=0
            LIMIT 1;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { return false }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }
   
    func updateBlockTagJSON(
        blockID: String,
        tagJSON: String,
        updatedAtMs: Int64
    ) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET tag_json=?,
                updated_at_ms=?,
                dirty_bl=CASE
                  WHEN tag_json <> ? THEN 1
                  ELSE dirty_bl
                END
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "updateBlockTagJSON.prepare", rc); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, tagJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, updatedAtMs)
            sqlite3_bind_text(stmt, 3, tagJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, blockID, -1, SQLITE_TRANSIENT)

            let rc2 = sqlite3_step(stmt)
            if rc2 != SQLITE_DONE { db.dbgErr(dbp, "updateBlockTagJSON.step", rc2) }
        }
    }
    
    private func isPlaceholderPayload(_ payload: String) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "{}"
    }

    private func extractProtonJSONAndRTFBase64(fromPayloadJSON payload: String) -> (String, String) {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payload),
           let data = normalized.data(using: .utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
           let proton = try? v1.proton1Data() {
            return proton.proton_json.isEmpty ? ("", proton.rtf_base64) : (proton.proton_json, "")
        }

        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("", "")
        }

        if let sections = root["sections"] as? [String: Any],
           let proton1 = sections["proton1"] as? [String: Any],
           let dataNode = proton1["data"] as? [String: Any] {
            let protonJSON = dataNode["proton_json"] as? String ?? ""
            return (
                protonJSON,
                protonJSON.isEmpty ? dataNode["rtf_base64"] as? String ?? "" : ""
            )
        }

        let protonJSON = root["proton_json"] as? String ?? ""
        let rtfBase64 = root["rtf_base64"] as? String ?? ""
        return protonJSON.isEmpty ? ("", rtfBase64) : (protonJSON, "")
    }

    private func rtfBase64HasRenderableContent(_ rtfBase64: String) -> Bool {
        guard let data = Data(base64Encoded: rtfBase64) else { return false }
        let decoded =
            (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)) ??
            (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))
        guard let decoded else { return false }

        var hasAttachment = false
        if decoded.length > 0 {
            decoded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: decoded.length), options: []) { value, _, stop in
                if value != nil {
                    hasAttachment = true
                    stop.pointee = true
                }
            }
        }
        if hasAttachment { return true }

        let visible = decoded.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !visible.isEmpty
    }

    private func protonJSONHasRenderableContent(_ protonJSON: String) -> Bool {
        let trimmed = protonJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        guard let rootAny = try? JSONSerialization.jsonObject(with: data) else { return false }

        func nodeHasContent(_ node: [String: Any]) -> Bool {
            let type = (node["type"] as? String) ?? ""
            if type == "rich" {
                return rtfBase64HasRenderableContent((node["rtf_base64"] as? String) ?? "")
            }
            if type == "list" {
                let items = (node["items"] as? [Any]) ?? []
                return items.contains { item in
                    guard let item = item as? [String: Any] else { return false }
                    return rtfBase64HasRenderableContent((item["rtf_base64"] as? String) ?? "")
                }
            }
            if type == "attachment" { return true }
            if let text = node["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            let children = (node["contents"] as? [Any]) ?? []
            return children.contains { child in
                guard let child = child as? [String: Any] else { return false }
                return nodeHasContent(child)
            }
        }

        if let root = rootAny as? [String: Any], let doc = root["doc"] as? [Any] {
            return doc.contains { item in
                guard let node = item as? [String: Any] else { return false }
                return nodeHasContent(node)
            }
        }

        if let nodes = rootAny as? [Any] {
            return nodes.contains { item in
                guard let node = item as? [String: Any] else { return false }
                return nodeHasContent(node)
            }
        }

        return false
    }

    private func payloadJSONHasRenderableContent(_ payloadJSON: String) -> Bool {
        let (protonJSON, rtfBase64) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payloadJSON)
        if protonJSONHasRenderableContent(protonJSON) { return true }
        return rtfBase64HasRenderableContent(rtfBase64)
    }

    private func protonAttachmentNodeCount(_ protonJSON: String) -> Int {
        let trimmed = protonJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return 0 }
        guard let rootAny = try? JSONSerialization.jsonObject(with: data) else { return 0 }

        func countNode(_ node: [String: Any]) -> Int {
            let type = (node["type"] as? String) ?? ""
            var count = type == "attachment" ? 1 : 0
            let contents = (node["contents"] as? [Any]) ?? []
            for child in contents {
                if let child = child as? [String: Any] {
                    count += countNode(child)
                }
            }
            return count
        }

        if let root = rootAny as? [String: Any], let doc = root["doc"] as? [Any] {
            return doc.reduce(0) { total, item in
                guard let node = item as? [String: Any] else { return total }
                return total + countNode(node)
            }
        }

        if let nodes = rootAny as? [Any] {
            return nodes.reduce(0) { total, item in
                guard let node = item as? [String: Any] else { return total }
                return total + countNode(node)
            }
        }

        return 0
    }

    private func payloadAttachmentNodeCount(_ payloadJSON: String) -> Int {
        let (protonJSON, _) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payloadJSON)
        return protonAttachmentNodeCount(protonJSON)
    }

    private func isEffectivelyEmptyPayload(_ payload: String) -> Bool {
        isPlaceholderPayload(payload) || !payloadJSONHasRenderableContent(payload)
    }

    private var localEditorDeviceID: String {
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? UIDevice.current.identifierForVendor?.uuidString ?? "unknown" : host
    }

    private func int64Any(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func hasActiveLocalEditorLease(blockID: String, nowMs: Int64) -> Bool {
        let localDeviceID = localEditorDeviceID
        guard !blockID.isEmpty, !localDeviceID.isEmpty else { return false }

        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT view_state_json
            FROM nj_note_block
            WHERE block_id=? AND deleted=0 AND view_state_json <> '';
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                db.dbgErr(dbp, "hasActiveLocalEditorLease.prepare", rc0)
                return false
            }
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
                if deviceID == localDeviceID, expiresAtMs > nowMs {
                    return true
                }
            }

            return false
        }
    }

    func applyNJBlock(_ f: [String: Any]) {
        let blockID = (f["block_id"] as? String) ?? ""
        if blockID.isEmpty { return }

        let blockType = (f["block_type"] as? String) ?? ""
        let hasPayloadKey = f.keys.contains("payload_json")
        let domainTag = (f["domain_tag"] as? String) ?? ""
        let tagJSON = (f["tag_json"] as? String) ?? ""
        let goalID = (f["goal_id"] as? String) ?? ""
        let lineageID = (f["lineage_id"] as? String) ?? ""
        let parentBlockID = (f["parent_block_id"] as? String) ?? ""
        let createdAtMs = (f["created_at_ms"] as? Int64) ?? 0
        let updatedAtMs = (f["updated_at_ms"] as? Int64) ?? 0
        let deleted = (f["deleted"] as? Int64) ?? 0

        let existing = loadNJBlock(blockID: blockID)
        let existingDeleted = (existing?["deleted"] as? Int64) ?? 0
        let existingUpdatedAtMs = (existing?["updated_at_ms"] as? Int64) ?? 0
        let existingPayload = (existing?["payload_json"] as? String) ?? ""
        let incomingPayload = (f["payload_json"] as? String) ?? ""
        let localPendingPush = hasPendingLocalPush(blockID: blockID)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Prefer local content while a local block change is still pending push.
        if existingDeleted == 0, localPendingPush {
            print("NJ_BLOCK_PULL_SKIP_PENDING_LOCAL_PUSH block_id=\(blockID) remote_updated_at_ms=\(updatedAtMs) local_updated_at_ms=\(existingUpdatedAtMs)")
            return
        }

        if existingDeleted == 0,
           hasPayloadKey,
           hasActiveLocalEditorLease(blockID: blockID, nowMs: nowMs) {
            print("NJ_BLOCK_PULL_SKIP_ACTIVE_LOCAL_LEASE block_id=\(blockID) remote_updated_at_ms=\(updatedAtMs) local_updated_at_ms=\(existingUpdatedAtMs)")
            return
        }

        // On timestamp ties, keep local content to avoid stale remote payloads
        // overwriting fresh edits from another open editor on this device.
        let shouldUpgradePlaceholderOnTie =
            hasPayloadKey &&
            existingUpdatedAtMs == updatedAtMs &&
            updatedAtMs > 0 &&
            isEffectivelyEmptyPayload(existingPayload) &&
            !isEffectivelyEmptyPayload(incomingPayload)

        if existingDeleted == 0,
           existingUpdatedAtMs >= updatedAtMs,
           updatedAtMs > 0,
           !shouldUpgradePlaceholderOnTie {
            return
        }

        let payloadJSON: String = {
            if hasPayloadKey {
                let localAttachmentCount = payloadAttachmentNodeCount(existingPayload)
                let incomingAttachmentCount = payloadAttachmentNodeCount(incomingPayload)
                if existingDeleted == 0,
                   localAttachmentCount > 0,
                   incomingAttachmentCount < localAttachmentCount {
                    print("NJ_BLOCK_PULL_SKIP_ATTACHMENT_DOWNGRADE block_id=\(blockID) remote_updated_at_ms=\(updatedAtMs) local_updated_at_ms=\(existingUpdatedAtMs) local_attachment_count=\(localAttachmentCount) incoming_attachment_count=\(incomingAttachmentCount)")
                    return existingPayload
                }
                if isEffectivelyEmptyPayload(incomingPayload),
                   !isEffectivelyEmptyPayload(existingPayload) {
                    print("NJ_BLOCK_PULL_SKIP_EMPTY_PAYLOAD_OVER_RENDERABLE block_id=\(blockID) remote_updated_at_ms=\(updatedAtMs) local_updated_at_ms=\(existingUpdatedAtMs)")
                    return existingPayload
                }
                return incomingPayload
            }
            return existingPayload
        }()

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_block(
              block_id,
              block_type,
              payload_json,
              domain_tag,
              tag_json,
              goal_id,
              lineage_id,
              parent_block_id,
              created_at_ms,
              updated_at_ms,
              deleted,
              dirty_bl
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(block_id) DO UPDATE SET
              block_type=excluded.block_type,
              payload_json=excluded.payload_json,
              domain_tag=excluded.domain_tag,
              tag_json=excluded.tag_json,
              goal_id=CASE
                WHEN excluded.goal_id = '' THEN nj_block.goal_id
                ELSE excluded.goal_id
              END,
              lineage_id=excluded.lineage_id,
              parent_block_id=excluded.parent_block_id,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted,
              dirty_bl=CASE
                WHEN excluded.tag_json != nj_block.tag_json THEN 1
                ELSE nj_block.dirty_bl
              END;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { db.dbgErr(dbp, "applyNJBlock.prepare", rc); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, blockType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, payloadJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, domainTag, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, tagJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, goalID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, lineageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, parentBlockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 9, createdAtMs)
            sqlite3_bind_int64(stmt, 10, updatedAtMs)
            sqlite3_bind_int64(stmt, 11, deleted)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyNJBlock.step", rc1) }
        }

        if !DBDirtyQueueTable.isInPullScope() {
            enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
        }
    }
    
}
