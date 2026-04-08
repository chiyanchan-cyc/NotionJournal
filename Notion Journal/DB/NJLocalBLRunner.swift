//
//  NJLocalBLRunner.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/7.
//


import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NJLocalBLRunner {

    enum Kind: String {
        case deriveBlockTagIndexAndDomainV1
    }

    private let db: SQLiteDB

    init(db: SQLiteDB) {
        self.db = db
    }

    
    func loadDomainPreview3FromBlockTag(blockID: String) -> String {
        if blockID.isEmpty { return "" }
        return db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            SELECT tag
            FROM nj_block_tag
            WHERE block_id=? AND instr(tag, '.')>0
            ORDER BY tag ASC
            LIMIT 3;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let t = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                if !t.isEmpty { out.append(t) }
            }

            return out.joined(separator: ", ")
        }
    }

    func run(_ kind: Kind, limit: Int = 300) {
        switch kind {
        case .deriveBlockTagIndexAndDomainV1:
            runDeriveBlockTagIndexAndDomainV1(limit: limit)
        }
    }

    // Re-queue existing calendar memory photos so both the calendar row and the linked
    // attachment thumbnail asset get republished to CloudKit.
    @discardableResult
    func backfillDirtyForCalendarPhotos(limit: Int = 8000) -> Int {
        db.withDB { dbp in
            var changed = 0

            func execute(_ sql: String) -> Int {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else {
                    if let stmt { sqlite3_finalize(stmt) }
                    return 0
                }
                defer { sqlite3_finalize(stmt) }
                let bindCount = sqlite3_bind_parameter_count(stmt)
                if bindCount > 0 {
                    for idx in 1...bindCount {
                        sqlite3_bind_int64(stmt, idx, Int64(limit))
                    }
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
                return Int(sqlite3_changes(dbp))
            }

            changed += execute("""
            INSERT OR IGNORE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, ignore)
            SELECT 'calendar_item', c.date_key, 'upsert', c.updated_at_ms, 0, '', 0
            FROM (
              SELECT date_key, updated_at_ms
              FROM nj_calendar_item
              WHERE deleted = 0
                AND photo_attachment_id <> ''
              ORDER BY updated_at_ms DESC
              LIMIT ?
            ) c;
            """)

            changed += execute("""
            UPDATE nj_dirty
            SET
              op='upsert',
              updated_at_ms=(
                SELECT c.updated_at_ms
                FROM (
                  SELECT date_key, updated_at_ms
                  FROM nj_calendar_item
                  WHERE deleted = 0
                    AND photo_attachment_id <> ''
                  ORDER BY updated_at_ms DESC
                  LIMIT ?
                ) c
                WHERE c.date_key = nj_dirty.entity_id
              ),
              attempts=0,
              last_error='',
              ignore=0
            WHERE entity='calendar_item'
              AND entity_id IN (
                SELECT date_key
                FROM (
                  SELECT date_key
                  FROM nj_calendar_item
                  WHERE deleted = 0
                    AND photo_attachment_id <> ''
                  ORDER BY updated_at_ms DESC
                  LIMIT ?
                )
              );
            """)

            changed += execute("""
            INSERT OR IGNORE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, ignore)
            SELECT 'attachment', a.attachment_id, 'upsert', a.updated_at_ms, 0, '', 0
            FROM (
              SELECT DISTINCT a.attachment_id, a.updated_at_ms
              FROM nj_attachment a
              JOIN nj_calendar_item c
                ON c.photo_attachment_id = a.attachment_id
               AND c.deleted = 0
              WHERE a.deleted = 0
                AND a.attachment_id <> ''
              ORDER BY a.updated_at_ms DESC
              LIMIT ?
            ) a;
            """)

            changed += execute("""
            UPDATE nj_dirty
            SET
              op='upsert',
              updated_at_ms=(
                SELECT a.updated_at_ms
                FROM (
                  SELECT DISTINCT a.attachment_id, a.updated_at_ms
                  FROM nj_attachment a
                  JOIN nj_calendar_item c
                    ON c.photo_attachment_id = a.attachment_id
                   AND c.deleted = 0
                  WHERE a.deleted = 0
                    AND a.attachment_id <> ''
                  ORDER BY a.updated_at_ms DESC
                  LIMIT ?
                ) a
                WHERE a.attachment_id = nj_dirty.entity_id
              ),
              attempts=0,
              last_error='',
              ignore=0
            WHERE entity='attachment'
              AND entity_id IN (
                SELECT attachment_id
                FROM (
                  SELECT DISTINCT a.attachment_id
                  FROM nj_attachment a
                  JOIN nj_calendar_item c
                    ON c.photo_attachment_id = a.attachment_id
                   AND c.deleted = 0
                  WHERE a.deleted = 0
                    AND a.attachment_id <> ''
                  ORDER BY a.updated_at_ms DESC
                  LIMIT ?
                )
              );
            """)

            return changed
        }
    }

    func markBlocksMissingTagIndexDirty(limit: Int = 8000) {
        db.withDB { dbp in
            let sql = """
            UPDATE nj_block
            SET dirty_bl=1
            WHERE deleted=0
              AND COALESCE(tag_json,'') <> ''
              AND block_id NOT IN (
                SELECT DISTINCT block_id FROM nj_block_tag
              )
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            _ = sqlite3_step(stmt)
        }
    }

    func runDeriveBlockTagIndexAndDomainV1All(limit: Int = 5000) {
        let rows = loadAllBlocks(limit: limit)
        if rows.isEmpty { return }

        for r in rows {
            let blockID = r.blockID
            if blockID.isEmpty { continue }

            let jsonTags = parseTagJSON(r.tagJSON)
            let noteDomains = loadNoteDomainsForBlock(blockID: blockID)

            let merged = Array(Set(jsonTags + noteDomains)).filter { !$0.isEmpty }.sorted()

            rebuildBlockTagIndex(blockID: blockID, tags: merged, nowMs: r.updatedAtMs)

            let domain = deriveDomainPreferNote(noteDomains: noteDomains, tags: merged)

            setDomainAndClearDirty(blockID: blockID, domainTag: domain, nowMs: r.updatedAtMs)
        }
    }

    // Backfill dirty rows for live note-block attachments.
    // Designed for one-time repair: inserts missing rows and only re-enables ignored rows.
    // Intentionally limited to note_block to avoid forcing broad block CAS conflicts.
    @discardableResult
    func backfillMissingDirtyForLiveBlocks(limit: Int = 20000) -> Int {
        db.withDB { dbp in
            var inserted = 0

            var stmt2: OpaquePointer?
            let sql2 = """
            INSERT OR IGNORE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, ignore)
            SELECT 'note_block', nb.instance_id, 'upsert', nb.updated_at_ms, 0, '', 0
            FROM (
              SELECT DISTINCT instance_id, updated_at_ms
              FROM nj_note_block
              WHERE deleted = 0
                AND instance_id <> ''
              ORDER BY updated_at_ms DESC
              LIMIT ?
            ) nb;
            """
            if sqlite3_prepare_v2(dbp, sql2, -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt2, 1, Int64(limit))
                if sqlite3_step(stmt2) == SQLITE_DONE {
                    inserted += Int(sqlite3_changes(dbp))
                }
            }
            sqlite3_finalize(stmt2)

            var stmt2b: OpaquePointer?
            let sql2b = """
            UPDATE nj_dirty
            SET
              op='upsert',
              attempts=0,
              last_error='',
              ignore=0
            WHERE entity='note_block'
              AND ignore=1
              AND entity_id IN (
                SELECT DISTINCT instance_id
                FROM nj_note_block
                WHERE deleted = 0
                  AND instance_id <> ''
                ORDER BY updated_at_ms DESC
                LIMIT ?
              );
            """
            if sqlite3_prepare_v2(dbp, sql2b, -1, &stmt2b, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt2b, 1, Int64(limit))
                if sqlite3_step(stmt2b) == SQLITE_DONE {
                    inserted += Int(sqlite3_changes(dbp))
                }
            }
            sqlite3_finalize(stmt2b)

            return inserted
        }
    }

    // Re-queue recently updated live note-block links so blocks that were created locally
    // but never had their placement row pushed can still appear on other devices.
    @discardableResult
    func backfillDirtyForRecentlyUpdatedLiveNoteBlocks(windowHours: Int = 48, limit: Int = 4000) -> Int {
        let cutoffMs = Int64(Date().timeIntervalSince1970 * 1000.0) - Int64(windowHours) * 60 * 60 * 1000

        return db.withDB { dbp in
            var changed = 0

            var stmtInsert: OpaquePointer?
            let sqlInsert = """
            INSERT OR IGNORE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, ignore)
            SELECT 'note_block', nb.instance_id, 'upsert', nb.updated_at_ms, 0, '', 0
            FROM (
              SELECT DISTINCT instance_id, updated_at_ms
              FROM nj_note_block
              WHERE deleted = 0
                AND instance_id <> ''
                AND updated_at_ms >= ?
              ORDER BY updated_at_ms DESC
              LIMIT ?
            ) nb;
            """
            if sqlite3_prepare_v2(dbp, sqlInsert, -1, &stmtInsert, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmtInsert, 1, cutoffMs)
                sqlite3_bind_int64(stmtInsert, 2, Int64(limit))
                if sqlite3_step(stmtInsert) == SQLITE_DONE {
                    changed += Int(sqlite3_changes(dbp))
                }
            }
            sqlite3_finalize(stmtInsert)

            var stmtUpdate: OpaquePointer?
            let sqlUpdate = """
            UPDATE nj_dirty
            SET
              op='upsert',
              attempts=0,
              last_error='',
              ignore=0,
              updated_at_ms = (
                SELECT nb.updated_at_ms
                FROM nj_note_block nb
                WHERE nb.instance_id = nj_dirty.entity_id
                LIMIT 1
              )
            WHERE entity='note_block'
              AND entity_id IN (
                SELECT DISTINCT instance_id
                FROM nj_note_block
                WHERE deleted = 0
                  AND instance_id <> ''
                  AND updated_at_ms >= ?
                ORDER BY updated_at_ms DESC
                LIMIT ?
              );
            """
            if sqlite3_prepare_v2(dbp, sqlUpdate, -1, &stmtUpdate, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmtUpdate, 1, cutoffMs)
                sqlite3_bind_int64(stmtUpdate, 2, Int64(limit))
                if sqlite3_step(stmtUpdate) == SQLITE_DONE {
                    changed += Int(sqlite3_changes(dbp))
                }
            }
            sqlite3_finalize(stmtUpdate)

            return changed
        }
    }

    // Repair missing note<->block links using attachment ownership as source of truth.
    // Creates live nj_note_block rows when attachment.note_id/block_id exists but link is missing.
    @discardableResult
    func repairMissingNoteBlockLinksFromAttachments(limit: Int = 4000) -> Int {
        db.withDB { dbp in
            struct Candidate {
                let noteID: String
                let blockID: String
                let updatedAtMs: Int64
            }

            var candidates: [Candidate] = []
            var q: OpaquePointer?
            let sqlQ = """
            SELECT a.note_id, a.block_id, MAX(a.updated_at_ms) AS um
            FROM nj_attachment a
            JOIN nj_block b
              ON b.block_id = a.block_id
             AND b.deleted = 0
            LEFT JOIN nj_note_block nb
              ON nb.note_id = a.note_id
             AND nb.block_id = a.block_id
             AND nb.deleted = 0
            WHERE a.deleted = 0
              AND a.note_id <> ''
              AND a.block_id <> ''
              AND nb.instance_id IS NULL
            GROUP BY a.note_id, a.block_id
            ORDER BY um DESC
            LIMIT ?;
            """
            if sqlite3_prepare_v2(dbp, sqlQ, -1, &q, nil) == SQLITE_OK {
                sqlite3_bind_int64(q, 1, Int64(limit))
                while sqlite3_step(q) == SQLITE_ROW {
                    let noteID = sqlite3_column_text(q, 0).flatMap { String(cString: $0) } ?? ""
                    let blockID = sqlite3_column_text(q, 1).flatMap { String(cString: $0) } ?? ""
                    let um = sqlite3_column_int64(q, 2)
                    if !noteID.isEmpty && !blockID.isEmpty {
                        candidates.append(Candidate(noteID: noteID, blockID: blockID, updatedAtMs: um))
                    }
                }
            }
            sqlite3_finalize(q)
            if candidates.isEmpty { return 0 }

            func nextOrderKey(_ noteID: String) -> Double {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = """
                SELECT COALESCE(MAX(order_key), 0)
                FROM nj_note_block
                WHERE note_id=? AND deleted=0;
                """
                guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return 1000 }
                sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let m = sqlite3_column_double(stmt, 0)
                    let out = m + 1000
                    return out < 1000 ? 1000 : out
                }
                return 1000
            }

            func hasLive(_ noteID: String, _ blockID: String) -> Bool {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = """
                SELECT 1
                FROM nj_note_block
                WHERE note_id=? AND block_id=? AND deleted=0
                LIMIT 1;
                """
                guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
                sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, blockID, -1, SQLITE_TRANSIENT)
                return sqlite3_step(stmt) == SQLITE_ROW
            }

            var insNB: OpaquePointer?
            let sqlInsNB = """
            INSERT INTO nj_note_block
            (instance_id, note_id, block_id, order_key, created_at_ms, updated_at_ms, deleted)
            VALUES (?, ?, ?, ?, ?, ?, 0);
            """
            if sqlite3_prepare_v2(dbp, sqlInsNB, -1, &insNB, nil) != SQLITE_OK {
                sqlite3_finalize(insNB)
                return 0
            }
            defer { sqlite3_finalize(insNB) }

            var insDirty: OpaquePointer?
            let sqlDirty = """
            INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, ignore)
            VALUES('note_block', ?, 'upsert', ?, 0, '', 0)
            ON CONFLICT(entity, entity_id) DO UPDATE SET
              op='upsert',
              updated_at_ms=excluded.updated_at_ms,
              attempts=0,
              last_error='',
              ignore=0;
            """
            if sqlite3_prepare_v2(dbp, sqlDirty, -1, &insDirty, nil) != SQLITE_OK {
                sqlite3_finalize(insDirty)
                return 0
            }
            defer { sqlite3_finalize(insDirty) }

            var changed = 0
            for c in candidates {
                if hasLive(c.noteID, c.blockID) { continue }
                let now = c.updatedAtMs > 0 ? c.updatedAtMs : Int64(Date().timeIntervalSince1970 * 1000.0)
                let iid = UUID().uuidString
                let ok = nextOrderKey(c.noteID)

                sqlite3_reset(insNB); sqlite3_clear_bindings(insNB)
                sqlite3_bind_text(insNB, 1, iid, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insNB, 2, c.noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insNB, 3, c.blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(insNB, 4, ok)
                sqlite3_bind_int64(insNB, 5, now)
                sqlite3_bind_int64(insNB, 6, now)
                if sqlite3_step(insNB) == SQLITE_DONE {
                    changed += 1
                    sqlite3_reset(insDirty); sqlite3_clear_bindings(insDirty)
                    sqlite3_bind_text(insDirty, 1, iid, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(insDirty, 2, now)
                    _ = sqlite3_step(insDirty)
                }
            }
            return changed
        }
    }

    // Repair missing note<->block links using historical nj_note_block tombstones.
    // This recovers blocks that lost live mapping but had prior note ownership.
    @discardableResult
    func repairMissingNoteBlockLinksFromHistory(limit: Int = 4000) -> Int {
        db.withDB { dbp in
            struct Candidate {
                let noteID: String
                let blockID: String
                let updatedAtMs: Int64
            }

            var candidates: [Candidate] = []
            var q: OpaquePointer?
            let sqlQ = """
            SELECT h.note_id, h.block_id, h.updated_at_ms
            FROM nj_note_block h
            JOIN nj_note n
              ON n.note_id = h.note_id
             AND n.deleted = 0
            JOIN nj_block b
              ON b.block_id = h.block_id
             AND b.deleted = 0
            LEFT JOIN nj_note_block live
              ON live.block_id = h.block_id
             AND live.deleted = 0
            WHERE h.deleted = 1
              AND h.note_id <> ''
              AND h.block_id <> ''
              AND live.instance_id IS NULL
              AND h.updated_at_ms = (
                SELECT MAX(h2.updated_at_ms)
                FROM nj_note_block h2
                WHERE h2.block_id = h.block_id
              )
            ORDER BY h.updated_at_ms DESC
            LIMIT ?;
            """
            if sqlite3_prepare_v2(dbp, sqlQ, -1, &q, nil) == SQLITE_OK {
                sqlite3_bind_int64(q, 1, Int64(limit))
                while sqlite3_step(q) == SQLITE_ROW {
                    let noteID = sqlite3_column_text(q, 0).flatMap { String(cString: $0) } ?? ""
                    let blockID = sqlite3_column_text(q, 1).flatMap { String(cString: $0) } ?? ""
                    let um = sqlite3_column_int64(q, 2)
                    if !noteID.isEmpty && !blockID.isEmpty {
                        candidates.append(Candidate(noteID: noteID, blockID: blockID, updatedAtMs: um))
                    }
                }
            }
            sqlite3_finalize(q)
            if candidates.isEmpty { return 0 }

            func nextOrderKey(_ noteID: String) -> Double {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = """
                SELECT COALESCE(MAX(order_key), 0)
                FROM nj_note_block
                WHERE note_id=? AND deleted=0;
                """
                guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return 1000 }
                sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let m = sqlite3_column_double(stmt, 0)
                    let out = m + 1000
                    return out < 1000 ? 1000 : out
                }
                return 1000
            }

            func hasLive(_ noteID: String, _ blockID: String) -> Bool {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = """
                SELECT 1
                FROM nj_note_block
                WHERE note_id=? AND block_id=? AND deleted=0
                LIMIT 1;
                """
                guard sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
                sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, blockID, -1, SQLITE_TRANSIENT)
                return sqlite3_step(stmt) == SQLITE_ROW
            }

            var insNB: OpaquePointer?
            let sqlInsNB = """
            INSERT INTO nj_note_block
            (instance_id, note_id, block_id, order_key, created_at_ms, updated_at_ms, deleted)
            VALUES (?, ?, ?, ?, ?, ?, 0);
            """
            if sqlite3_prepare_v2(dbp, sqlInsNB, -1, &insNB, nil) != SQLITE_OK {
                sqlite3_finalize(insNB)
                return 0
            }
            defer { sqlite3_finalize(insNB) }

            var insDirty: OpaquePointer?
            let sqlDirty = """
            INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, ignore)
            VALUES('note_block', ?, 'upsert', ?, 0, '', 0)
            ON CONFLICT(entity, entity_id) DO UPDATE SET
              op='upsert',
              updated_at_ms=excluded.updated_at_ms,
              attempts=0,
              last_error='',
              ignore=0;
            """
            if sqlite3_prepare_v2(dbp, sqlDirty, -1, &insDirty, nil) != SQLITE_OK {
                sqlite3_finalize(insDirty)
                return 0
            }
            defer { sqlite3_finalize(insDirty) }

            var changed = 0
            for c in candidates {
                if hasLive(c.noteID, c.blockID) { continue }
                let now = c.updatedAtMs > 0 ? c.updatedAtMs : Int64(Date().timeIntervalSince1970 * 1000.0)
                let iid = UUID().uuidString
                let ok = nextOrderKey(c.noteID)

                sqlite3_reset(insNB); sqlite3_clear_bindings(insNB)
                sqlite3_bind_text(insNB, 1, iid, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insNB, 2, c.noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insNB, 3, c.blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(insNB, 4, ok)
                sqlite3_bind_int64(insNB, 5, now)
                sqlite3_bind_int64(insNB, 6, now)
                if sqlite3_step(insNB) == SQLITE_DONE {
                    changed += 1
                    sqlite3_reset(insDirty); sqlite3_clear_bindings(insDirty)
                    sqlite3_bind_text(insDirty, 1, iid, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(insDirty, 2, now)
                    _ = sqlite3_step(insDirty)
                }
            }
            return changed
        }
    }

    private func runDeriveBlockTagIndexAndDomainV1(limit: Int) {
        let rows = loadDirtyBlocks(limit: limit)
        if rows.isEmpty { return }

        for r in rows {
            let blockID = r.blockID
            if blockID.isEmpty { continue }

            let jsonTags = parseTagJSON(r.tagJSON)
            let noteDomains = loadNoteDomainsForBlock(blockID: blockID)

            let merged = Array(Set(jsonTags + noteDomains)).filter { !$0.isEmpty }.sorted()

            rebuildBlockTagIndex(blockID: blockID, tags: merged, nowMs: r.updatedAtMs)

            let domain = deriveDomainPreferNote(noteDomains: noteDomains, tags: merged)

            setDomainAndClearDirty(blockID: blockID, domainTag: domain, nowMs: r.updatedAtMs)
        }
    }


    private struct DirtyBlockRow {
        let blockID: String
        let tagJSON: String
        let updatedAtMs: Int64
    }

    private func loadDirtyBlocks(limit: Int) -> [DirtyBlockRow] {
        db.withDB { dbp in
            var out: [DirtyBlockRow] = []
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            SELECT block_id, COALESCE(tag_json,''), updated_at_ms
            FROM nj_block
            WHERE deleted=0 AND dirty_bl=1
            ORDER BY updated_at_ms ASC
            LIMIT ?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { return out }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let bid = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let tj = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                let um = sqlite3_column_int64(stmt, 2)
                out.append(DirtyBlockRow(blockID: bid, tagJSON: tj, updatedAtMs: um))
            }
            return out
        }
    }

    private func loadAllBlocks(limit: Int) -> [DirtyBlockRow] {
        db.withDB { dbp in
            var out: [DirtyBlockRow] = []
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            SELECT block_id, COALESCE(tag_json,''), updated_at_ms
            FROM nj_block
            WHERE deleted=0
            ORDER BY updated_at_ms DESC
            LIMIT ?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { return out }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let bid = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let tj = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                let um = sqlite3_column_int64(stmt, 2)
                out.append(DirtyBlockRow(blockID: bid, tagJSON: tj, updatedAtMs: um))
            }
            return out
        }
    }

    private func parseTagJSON(_ s: String) -> [String] {
        guard let data = s.data(using: .utf8) else { return [] }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return Array(Set(arr)).filter { !$0.isEmpty }.sorted()
    }

    private func rebuildBlockTagIndex(blockID: String, tags: [String], nowMs: Int64) {
        db.withDB { dbp in
            var del: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, "DELETE FROM nj_block_tag WHERE block_id=?;", -1, &del, nil)
            if rc0 != SQLITE_OK { return }
            sqlite3_bind_text(del, 1, blockID, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(del)
            sqlite3_finalize(del)

            if tags.isEmpty { return }

            for t in tags {
                var ins: OpaquePointer?
                let rc1 = sqlite3_prepare_v2(dbp, """
                INSERT INTO nj_block_tag(block_id, tag, dirty_bl, created_at_ms, updated_at_ms)
                VALUES(?, ?, 0, ?, ?)
                ON CONFLICT(block_id, tag) DO UPDATE SET
                  updated_at_ms=excluded.updated_at_ms,
                  dirty_bl=0;
                """, -1, &ins, nil)
                if rc1 != SQLITE_OK { continue }
                sqlite3_bind_text(ins, 1, blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(ins, 2, t, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(ins, 3, nowMs)
                sqlite3_bind_int64(ins, 4, nowMs)
                _ = sqlite3_step(ins)
                sqlite3_finalize(ins)
            }
        }
    }

    private func deriveDomainFromTags(_ tags: [String]) -> String {
        if tags.isEmpty { return "" }
        let t = tags[0]
        let parts = t.split(separator: ".")
        if parts.count >= 2 { return "\(parts[0]).\(parts[1])" }
        return t
    }

    private func setDomainAndClearDirty(blockID: String, domainTag: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            UPDATE nj_block
            SET domain_tag=?, dirty_bl=0, updated_at_ms=?
            WHERE block_id=?;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, domainTag, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, nowMs)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)

            _ = sqlite3_step(stmt)
        }
    }

    private func loadNoteDomainsForBlock(blockID: String) -> [String] {
        if blockID.isEmpty { return [] }
        return db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, """
            SELECT DISTINCT n.tab_domain
            FROM nj_note_block nb
            JOIN nj_note n ON n.note_id = nb.note_id
            WHERE nb.block_id=? AND nb.deleted=0 AND n.deleted=0 AND n.tab_domain<>''
            ORDER BY n.tab_domain ASC;
            """, -1, &stmt, nil)
            if rc != SQLITE_OK { return out }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let d = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                if !d.isEmpty { out.append(d) }
            }
            return out
        }
    }

    private func deriveDomainPreferNote(noteDomains: [String], tags: [String]) -> String {
        if let d = noteDomains.sorted().first, !d.isEmpty { return d }
        for t in tags {
            if t.contains(".") { return t }
        }
        return ""
    }

}
