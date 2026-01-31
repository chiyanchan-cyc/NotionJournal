import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDB {
    static var debugSQL: Bool = false

    private let db: OpaquePointer?
    private let path: String

    private let q = DispatchQueue(label: "nj.sqlite.serial")
    private let qKey = DispatchSpecificKey<UInt8>()
    private let qKeyVal: UInt8 = 1

    init(path: String, resetSchema: Bool) {
        self.path = path
        q.setSpecific(key: qKey, value: qKeyVal)

        if resetSchema {
            let fm = FileManager.default
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(atPath: path + "-wal")
            try? fm.removeItem(atPath: path + "-shm")
            print("NJ_DB_RESET_DELETED:", path)
            SQLiteDB.resetCloudKitCursors()
        }

        var p: OpaquePointer?
        let rc = sqlite3_open(path, &p)
        if rc != SQLITE_OK {
            fatalError("sqlite open failed rc=\(rc)")
        }
        db = p

        print("NJ_DB_OPENED:", path)

        exec("PRAGMA foreign_keys = ON;")
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;")

        if resetSchema {
            DBSchemaInstaller.hardRecreateSchema(db: self)
            resetCloudKitCursors()
        }

        print("NJ_DB_SCHEMA nj_note:")
        exec("PRAGMA table_info(nj_note);")
    }

    deinit {
        if DispatchQueue.getSpecific(key: qKey) != nil {
            sqlite3_close(db)
        } else {
            q.sync {
                sqlite3_close(db)
            }
        }
    }

    func withDB<T>(_ body: (OpaquePointer) -> T) -> T {
        guard let dbp = db else { fatalError("SQLiteDB not opened") }
        if DispatchQueue.getSpecific(key: qKey) != nil {
            return body(dbp)
        }
        return q.sync {
            body(dbp)
        }
    }

    func dbgErr(_ dbp: OpaquePointer, _ where_: String, _ rc: Int32) {
        let msg = String(cString: sqlite3_errmsg(dbp))
        print("NJ_SQL_ERR \(where_) rc=\(rc) msg=\(msg)")
    }

    func exec(_ sql: String) {
        withDB { dbp in
            if SQLiteDB.debugSQL { print("SQL:", sql) }
            let rc = sqlite3_exec(dbp, sql, nil, nil, nil)
            if rc != SQLITE_OK { dbgErr(dbp, "exec", rc) }
        }
    }

    func queryRows(_ sql: String) -> [[String: String]] {
        withDB { dbp in
            var stmt: OpaquePointer?
            var rows: [[String: String]] = []

            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK {
                return []
            }

            defer { sqlite3_finalize(stmt) }

            let columnCount = sqlite3_column_count(stmt)

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: String] = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    let valuePtr = sqlite3_column_text(stmt, i)
                    if let valuePtr {
                        row[name] = String(cString: valuePtr)
                    } else {
                        row[name] = "NULL"
                    }
                }
                rows.append(row)
            }

            return rows
        }
    }

    private static func resetCloudKitCursors() {
        let d = UserDefaults.standard

        d.removeObject(forKey: "NJ_CK_SINCE_notebook")
        d.removeObject(forKey: "NJ_CK_SINCE_tab")
        d.removeObject(forKey: "NJ_CK_SINCE_note")
        d.removeObject(forKey: "NJ_CK_SINCE_block")
        d.removeObject(forKey: "NJ_CK_SINCE_note_block")

        d.removeObject(forKey: "nj_ck_last_pull_ms_notebook")
        d.removeObject(forKey: "nj_ck_last_pull_ms_tab")
        d.removeObject(forKey: "nj_ck_last_pull_ms_note")
        d.removeObject(forKey: "nj_ck_last_pull_ms_block")
        d.removeObject(forKey: "nj_ck_last_pull_ms_note_block")

        d.removeObject(forKey: "nj_ck_bootstrap_done_v1")

        d.synchronize()

        print("NJ_CK_RESET: cleared all pull cursors")
    }

    func resetCloudKitCursors() {
        exec("""
        INSERT OR REPLACE INTO nj_kv (k, v) VALUES
            ('ck_since_notebook', '0'),
            ('ck_since_tab', '0'),
            ('ck_since_note', '0'),
            ('ck_since_block', '0'),
            ('ck_since_note_block', '0');
        """)
        print("NJ_CK_CURSORS_RESET")
    }
}
