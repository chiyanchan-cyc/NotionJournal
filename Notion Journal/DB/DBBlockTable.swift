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
                "lineage_id": sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? "",
                "parent_block_id": sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? "",
                "created_at_ms": sqlite3_column_int64(stmt, 7),
                "updated_at_ms": sqlite3_column_int64(stmt, 8),
                "deleted": sqlite3_column_int64(stmt, 9)
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
        let payloadJSON: String = {
            if hasPayloadKey { return (f["payload_json"] as? String) ?? "" }
            return loadBlockPayloadJSON(blockID: blockID)
        }()
        let domainTag = (f["domain_tag"] as? String) ?? ""
        let tagJSON = (f["tag_json"] as? String) ?? ""
        let lineageID = (f["lineage_id"] as? String) ?? ""
        let parentBlockID = (f["parent_block_id"] as? String) ?? ""
        let createdAtMs = (f["created_at_ms"] as? Int64) ?? 0
        let updatedAtMs = (f["updated_at_ms"] as? Int64) ?? 0
        let deleted = (f["deleted"] as? Int64) ?? 0


        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_block(
              block_id,
              block_type,
              payload_json,
              domain_tag,
              tag_json,
              lineage_id,
              parent_block_id,
              created_at_ms,
              updated_at_ms,
              deleted,
              dirty_bl
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(block_id) DO UPDATE SET
              block_type=excluded.block_type,
              payload_json=excluded.payload_json,
              domain_tag=excluded.domain_tag,
              tag_json=excluded.tag_json,
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
            sqlite3_bind_text(stmt, 6, lineageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, parentBlockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, createdAtMs)
            sqlite3_bind_int64(stmt, 9, updatedAtMs)
            sqlite3_bind_int64(stmt, 10, deleted)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyNJBlock.step", rc1) }
        }

        enqueueDirty(entity: "block", entityID: blockID, op: "upsert", updatedAtMs: updatedAtMs)
    }
    
}
