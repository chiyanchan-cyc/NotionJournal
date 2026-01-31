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

    @TaskLocal static var pullScopeTaskDepth: Int = 0

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
        return try await Self.$pullScopeTaskDepth.withValue(Self.pullScopeTaskDepth + 1) {
            try await f()
        }
    }

    static func isInPullScope() -> Bool {
        if Self.pullScopeTaskDepth > 0 { return true }
        let td = Thread.current.threadDictionary
        return ((td[_pullScopeKey] as? Int) ?? 0) > 0
    }

    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        if Self.isInPullScope() { return }

        var didCommit = false

        db.withDB { dbp in
            func isBusy(_ rc: Int32) -> Bool {
                let primary = rc & 0xFF
                return primary == SQLITE_BUSY || primary == SQLITE_LOCKED
            }

            func backoff(_ attempt: Int) {
                let ms = min(800, 25 * (1 << attempt))
                usleep(useconds_t(ms * 1000))
            }

            func exec(_ sql: String) -> Int32 {
                sqlite3_exec(dbp, sql, nil, nil, nil)
            }

            for attempt in 0..<7 {
                let rcBegin = exec("BEGIN IMMEDIATE;")
                if rcBegin != SQLITE_OK {
                    if isBusy(rcBegin) { backoff(attempt); continue }
                    db.dbgErr(dbp, "enqueueDirty.begin", rcBegin)
                    _ = exec("ROLLBACK;")
                    return
                }

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

                if rc0 != SQLITE_OK {
                    sqlite3_finalize(stmt)
                    _ = exec("ROLLBACK;")
                    if isBusy(rc0) { backoff(attempt); continue }
                    db.dbgErr(dbp, "enqueueDirty.prepare", rc0)
                    return
                }

                guard let stmt else {
                    _ = exec("ROLLBACK;")
                    backoff(attempt)
                    continue
                }

                sqlite3_bind_text(stmt, 1, entity, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, entityID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, op, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, updatedAtMs)

                let rc1 = sqlite3_step(stmt)
                sqlite3_finalize(stmt)

                if rc1 != SQLITE_DONE {
                    _ = exec("ROLLBACK;")
                    if isBusy(rc1) { backoff(attempt); continue }
                    db.dbgErr(dbp, "enqueueDirty.step", rc1)
                    return
                }

                let rcCommit = exec("COMMIT;")
                if rcCommit != SQLITE_OK {
                    _ = exec("ROLLBACK;")
                    if isBusy(rcCommit) { backoff(attempt); continue }
                    db.dbgErr(dbp, "enqueueDirty.commit", rcCommit)
                    return
                }

                didCommit = true
                break
            }

            if !didCommit {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_DIRTY_ENQ GIVE_UP entity=\(entity) id=\(entityID) op=\(op) ts=\(updatedAtMs) msg=\(msg)")
            }
        }

        if didCommit {
            NotificationCenter.default.post(name: .njDirtyEnqueued, object: nil)
        }
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
            guard let stmt else { return }
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

    func takeDirtyBatch(limit: Int) -> [NJDirtyItem] {
        let maxAttempts = 10
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        var out: [NJDirtyItem] = []

        db.withDB { dbp in
            func isBusy(_ rc: Int32) -> Bool {
                let primary = rc & 0xFF
                return primary == SQLITE_BUSY || primary == SQLITE_LOCKED
            }

            func backoff(_ attempt: Int) {
                let ms = min(800, 25 * (1 << attempt))
                usleep(useconds_t(ms * 1000))
            }

            func execRC(_ sql: String) -> Int32 {
                sqlite3_exec(dbp, sql, nil, nil, nil)
            }

            func colText(_ stmt: OpaquePointer, _ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }

            var didBegin = false
            for attempt in 0..<7 {
                let rc = execRC("BEGIN IMMEDIATE;")
                if rc == SQLITE_OK { didBegin = true; break }
                if isBusy(rc) { backoff(attempt); continue }
                db.dbgErr(dbp, "takeDirtyBatch.begin", rc)
                _ = execRC("ROLLBACK;")
                return
            }
            if !didBegin { return }

            var ok = true
            defer {
                if ok {
                    var didCommit = false
                    for attempt in 0..<7 {
                        let rc = execRC("COMMIT;")
                        if rc == SQLITE_OK { didCommit = true; break }
                        if isBusy(rc) { backoff(attempt); continue }
                        db.dbgErr(dbp, "takeDirtyBatch.commit", rc)
                        break
                    }
                    if !didCommit { _ = execRC("ROLLBACK;") }
                } else {
                    _ = execRC("ROLLBACK;")
                }
            }

            do {
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, """
                SELECT entity, entity_id, op, updated_at_ms, attempts, last_error, ignore
                FROM nj_dirty
                WHERE ignore = 0
                  AND attempts < ?
                  AND (next_retry_at_ms = 0 OR next_retry_at_ms <= ?)
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
                    let entity = colText(stmt, 0)
                    let entityID = colText(stmt, 1)
                    let op = colText(stmt, 2)
                    let updatedAt = sqlite3_column_int64(stmt, 3)
                    let attempts = Int(sqlite3_column_int(stmt, 4))
                    let lastError = colText(stmt, 5)
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
                whereParts.reserveCapacity(out.count)
                for _ in out { whereParts.append("(entity = ? AND entity_id = ?)") }
                let whereClause = whereParts.joined(separator: " OR ")

                var bump: OpaquePointer?
                let rc1 = sqlite3_prepare_v2(dbp, """
                UPDATE nj_dirty
                SET attempts = attempts + 1
                WHERE ignore = 0 AND (\(whereClause));
                """, -1, &bump, nil)
                if rc1 != SQLITE_OK { db.dbgErr(dbp, "takeDirtyBatch.bump.prepare", rc1); ok = false; return }
                guard let bump else { ok = false; return }
                defer { sqlite3_finalize(bump) }

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
            guard let stmt else { return }
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
                guard let s else { return -1 }
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
