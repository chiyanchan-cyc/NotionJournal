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
