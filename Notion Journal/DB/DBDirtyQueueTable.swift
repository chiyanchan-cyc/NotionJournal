import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJDirtyItem {
    let entity: String
    let entityID: String
    let op: String
    let updatedAtMS: Int64
    let attempts: Int
    let lastError: String
    let ignore: Bool
}

final class DBDirtyQueueTable {
    let db: SQLiteDB

    init(db: SQLiteDB) {
        self.db = db
    }
    
    private static let _pullScopeKey = "nj_dirty_pull_scope_depth"

    static func withPullScope<T>(_ f: () throws -> T) rethrows -> T {
        let td = Thread.current.threadDictionary
        let d = (td[_pullScopeKey] as? Int) ?? 0
        td[_pullScopeKey] = d + 1
        defer {
            let d2 = (td[_pullScopeKey] as? Int) ?? 1
            if d2 <= 1 { td.removeObject(forKey: _pullScopeKey) }
            else { td[_pullScopeKey] = d2 - 1 }
        }
        return try f()
    }

    static func withPullScopeAsync<T>(_ f: () async throws -> T) async rethrows -> T {
        let td = Thread.current.threadDictionary
        let d = (td[_pullScopeKey] as? Int) ?? 0
        td[_pullScopeKey] = d + 1
        defer {
            let d2 = (td[_pullScopeKey] as? Int) ?? 1
            if d2 <= 1 { td.removeObject(forKey: _pullScopeKey) }
            else { td[_pullScopeKey] = d2 - 1 }
        }
        return try await f()
    }

    private static func _isInPullScope() -> Bool {
        let td = Thread.current.threadDictionary
        return ((td[_pullScopeKey] as? Int) ?? 0) > 0
    }

    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        if Self._isInPullScope() { return }
        let stack = Thread.callStackSymbols.prefix(10).joined(separator: " | ")
        //            print("NJ_DIRTY_ENQ entity=\(entity) id=\(entityID) op=\(op) ts=\(updatedAtMs) stack=\(stack)")
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error)
            VALUES(?, ?, ?, ?, 0, '')
            ON CONFLICT(entity, entity_id) DO UPDATE SET
              op=excluded.op,
              updated_at_ms=excluded.updated_at_ms,
              attempts=0,
              last_error='',
              ignore=0;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "enqueueDirty.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, entity, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entityID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, op, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, updatedAtMs)
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "enqueueDirty.step", rc1) }
        }
            
        NotificationCenter.default.post(name: .njDirtyEnqueued, object: nil)
        
    }

    func recordDirtyError(entity: String, entityID: String, code: Int, domain: String, message: String, retryAfterSec: Double?) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let next = retryAfterSec != nil ? now + Int64((retryAfterSec! * 1000.0).rounded()) : 0

        let msg: String = {
            let s = message
            if s.count <= 500 { return s }
            let i = s.index(s.startIndex, offsetBy: 500)
            return String(s[..<i])
        }()

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_dirty
            SET last_error=?,
                last_error_at_ms=?,
                last_error_code=?,
                last_error_domain=?,
                next_retry_at_ms=?
            WHERE entity=? AND entity_id=? COLLATE NOCASE;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "recordDirtyError.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            let msgp = (msg as NSString).utf8String
            let domp = (domain as NSString).utf8String
            let ep = (entity as NSString).utf8String
            let idp = (entityID as NSString).utf8String

            sqlite3_bind_text(stmt, 1, msgp, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_int(stmt, 3, Int32(code))
            sqlite3_bind_text(stmt, 4, domp, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 5, next)
            sqlite3_bind_text(stmt, 6, ep, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, idp, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "recordDirtyError.step", rc1) }

            let ch = sqlite3_changes(dbp)
            if ch == 0 {
                print("NJ_DIRTY_ERR_MISS entity=\(entity) id=\(entityID)")
            }
        }
    }

//    func housekeepDirty(maxKeepMs: Int64, maxRows: Int) {
//        let now = Int64(Date().timeIntervalSince1970 * 1000)
//        let cutoff = now - maxKeepMs
//
//        db.withDB { dbp in
//            var s1: OpaquePointer?
//            let rc0 = sqlite3_prepare_v2(dbp, """
//            DELETE FROM nj_dirty
//            WHERE ignore=1 AND updated_at_ms < ?;
//            """, -1, &s1, nil)
//            if rc0 == SQLITE_OK, let s1 {
//                defer { sqlite3_finalize(s1) }
//                sqlite3_bind_int64(s1, 1, cutoff)
//                _ = sqlite3_step(s1)
//            }
//
//            var s2: OpaquePointer?
//            let rc1 = sqlite3_prepare_v2(dbp, """
//            DELETE FROM nj_dirty
//            WHERE rowid IN (
//                SELECT rowid FROM nj_dirty
//                ORDER BY updated_at_ms DESC
//                LIMIT -1 OFFSET ?
//            );
//            """, -1, &s2, nil)
//            if rc1 == SQLITE_OK, let s2 {
//                defer { sqlite3_finalize(s2) }
//                sqlite3_bind_int(s2, 1, Int32(maxRows))
//                _ = sqlite3_step(s2)
//            }
//        }
//    }

    func takeDirtyBatch(limit: Int) -> [NJDirtyItem] {

        let maxAttempts = 10
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        var out: [NJDirtyItem] = []

        db.withDB { dbp in
            func exec(_ sql: String) -> Bool {
                var err: UnsafeMutablePointer<Int8>?
                let rc = sqlite3_exec(dbp, sql, nil, nil, &err)
                if rc != SQLITE_OK {
                    db.dbgErr(dbp, "dirty.exec", rc)
                    if let err { sqlite3_free(err) }
                    return false
                }
                return true
            }

            if !exec("BEGIN IMMEDIATE;") { return }
            var ok = true
            defer {
                if ok { _ = exec("COMMIT;") } else { _ = exec("ROLLBACK;") }
            }

            do {
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, """
                SELECT entity, entity_id, op, updated_at_ms, attempts, last_error, ignore
                FROM nj_dirty
                WHERE ignore = 0 AND attempts < ? AND (next_retry_at_ms = 0 OR next_retry_at_ms <= ?)
                ORDER BY updated_at_ms DESC
                LIMIT ?;
                """, -1, &stmt, nil)
                if rc0 != SQLITE_OK { db.dbgErr(dbp, "takeDirtyBatch.select.prepare", rc0); ok = false; return }
                guard let stmt else { ok = false; return }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_int(stmt, 1, Int32(maxAttempts))
                sqlite3_bind_int64(stmt, 2, now)
                sqlite3_bind_int(stmt, 3, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let entity = String(cString: sqlite3_column_text(stmt, 0))
                    let entityID = String(cString: sqlite3_column_text(stmt, 1))
                    let op = String(cString: sqlite3_column_text(stmt, 2))
                    let updatedAt = sqlite3_column_int64(stmt, 3)
                    let attempts = Int(sqlite3_column_int(stmt, 4))
                    let lastError = String(cString: sqlite3_column_text(stmt, 5))
                    let ignore = sqlite3_column_int(stmt, 6) != 0

                    out.append(NJDirtyItem(
                        entity: entity,
                        entityID: entityID,
                        op: op,
                        updatedAtMS: updatedAt,
                        attempts: attempts,
                        lastError: lastError,
                        ignore: ignore
                    ))
                }
            }

            if out.isEmpty { return }

            do {
                var whereParts: [String] = []
                for _ in out { whereParts.append("(entity = ? AND entity_id = ?)") }
                let whereClause = whereParts.joined(separator: " OR ")

                var bump: OpaquePointer?
                let rc1 = sqlite3_prepare_v2(dbp, """
                UPDATE nj_dirty
                SET attempts = attempts + 1
                WHERE ignore = 0 AND (\(whereClause));
                """, -1, &bump, nil)

                var idx: Int32 = 1
                for it in out {
                    sqlite3_bind_text(bump, idx, it.entity, -1, SQLITE_TRANSIENT); idx += 1
                    sqlite3_bind_text(bump, idx, it.entityID, -1, SQLITE_TRANSIENT); idx += 1
                }


                let rc2 = sqlite3_step(bump)
                if rc2 != SQLITE_DONE { db.dbgErr(dbp, "takeDirtyBatch.bump.step", rc2); ok = false; return }
            }

            do {
                var ig: OpaquePointer?
                let rc3 = sqlite3_prepare_v2(dbp, """
                UPDATE nj_dirty
                SET ignore = 1
                WHERE ignore = 0 AND attempts >= ?;
                """, -1, &ig, nil)
                if rc3 != SQLITE_OK { db.dbgErr(dbp, "takeDirtyBatch.ignore.prepare", rc3); ok = false; return }
                guard let ig else { ok = false; return }
                defer { sqlite3_finalize(ig) }

                sqlite3_bind_int(ig, 1, Int32(maxAttempts))

                let rc4 = sqlite3_step(ig)
                if rc4 != SQLITE_DONE { db.dbgErr(dbp, "takeDirtyBatch.ignore.step", rc4); ok = false; return }
            }
        }

        return out
    }

    func clearDirty(entity: String, entityID: String) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            DELETE FROM nj_dirty
            WHERE entity=? AND entity_id=? COLLATE NOCASE;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "clearDirty.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            let e = (entity as NSString).utf8String
            let id = (entityID as NSString).utf8String

            let rb1 = sqlite3_bind_text(stmt, 1, e, -1, SQLITE_TRANSIENT)
            if rb1 != SQLITE_OK { db.dbgErr(dbp, "clearDirty.bind1", rb1); return }

            let rb2 = sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
            if rb2 != SQLITE_OK { db.dbgErr(dbp, "clearDirty.bind2", rb2); return }

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "clearDirty.step", rc1); return }

            let ch = sqlite3_changes(dbp)
            if ch != 0 { return }

            func count(_ sql: String, _ tag: String) -> Int {
                var s: OpaquePointer?
                let rc = sqlite3_prepare_v2(dbp, sql, -1, &s, nil)
                if rc != SQLITE_OK { db.dbgErr(dbp, "clearDirty.\(tag).prepare", rc); return -1 }
                defer { sqlite3_finalize(s) }
                sqlite3_bind_text(s, 1, e, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(s, 2, id, -1, SQLITE_TRANSIENT)
                let r = sqlite3_step(s)
                if r != SQLITE_ROW { db.dbgErr(dbp, "clearDirty.\(tag).step", r); return -1 }
                return Int(sqlite3_column_int(s, 0))
            }

            let strict = count("SELECT COUNT(1) FROM nj_dirty WHERE entity=? AND entity_id=?;", "count_strict")
            let nocase = count("SELECT COUNT(1) FROM nj_dirty WHERE entity=? AND entity_id=? COLLATE NOCASE;", "count_nocase")
            let anyEnt = count("SELECT COUNT(1) FROM nj_dirty WHERE entity=?;", "count_entity_only")

            print("NJ_DIRTY_CLEAR_MISS entity=\(entity) id=\(entityID) strict=\(strict) nocase=\(nocase) entityOnly=\(anyEnt)")
        }
    }

}

extension Notification.Name {
    static let njDirtyEnqueued = Notification.Name("nj_dirty_enqueued")
}
