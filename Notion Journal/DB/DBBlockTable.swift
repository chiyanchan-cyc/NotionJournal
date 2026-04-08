//
//  DBBlockTable.swift
//  Notion Journal
//

import Foundation
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
        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
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
        if existingDeleted == 0, existingUpdatedAtMs > updatedAtMs, updatedAtMs > 0 {
            return
        }

        let existingPayload = (existing?["payload_json"] as? String) ?? ""
        let incomingPayload = (f["payload_json"] as? String) ?? ""
        let payloadJSON: String = {
            if hasPayloadKey {
                if incomingPayload.isEmpty, !existingPayload.isEmpty {
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

        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
    }
    
}
