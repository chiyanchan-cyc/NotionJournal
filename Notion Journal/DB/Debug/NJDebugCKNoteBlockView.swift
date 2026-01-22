import SwiftUI
import CloudKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJDebugCKNoteBlockView: View {
    let recordType: String
    let db: SQLiteDB

    @State private var log: String = ""
    @State private var isRunning = false
    @State private var fetchedCount = 0
    @State private var appliedCount = 0
    @State private var skippedCount = 0
    @State private var localCount = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(isRunning ? "Running..." : "Fetch CK deleted=0") {
                    Task { await run(applyLocal: false) }
                }
                .disabled(isRunning)

                Button(isRunning ? "Running..." : "Fetch + Apply Local") {
                    Task { await run(applyLocal: true) }
                }
                .disabled(isRunning)

                Button("Clear") { log = "" }
            }

            HStack {
                Text("fetched=\(fetchedCount) applied=\(appliedCount) skipped=\(skippedCount) local=\(localCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView {
                Text(log)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .navigationTitle("CK NoteBlock Debug")
    }

    private func run(applyLocal: Bool) async {
        if isRunning { return }
        isRunning = true
        fetchedCount = 0
        appliedCount = 0
        skippedCount = 0
        localCount = countLocal()

        append("BEGIN recordType=\(recordType) applyLocal=\(applyLocal) localBefore=\(localCount)")

        do {
            let ckdb = CKContainer(identifier: "iCloud.com.CYC.NotionJournal").privateCloudDatabase
            let predicate = NSPredicate(format: "deleted == 0")
            let query = CKQuery(recordType: recordType, predicate: predicate)

            let records = try await fetchAll(db: ckdb, query: query)
            fetchedCount = records.count
            append("CK_FETCH_DONE count=\(records.count)")

            for r in records {
                let f = recordToFields(r)

                let instanceID = (f["instance_id"] as? String) ?? r.recordID.recordName
                let noteID = (f["note_id"] as? String) ?? ""
                let blockID = (f["block_id"] as? String) ?? ""
                let deleted = int64Any(f["deleted"])
                let createdAtMs = int64Any(f["created_at_ms"])
                let updatedAtMs = int64Any(f["updated_at_ms"])
                let viewState = (f["view_state_json"] as? String) ?? ""
                let orderKey = doubleAny(f["order_key"])

                append("CK id=\(r.recordID.recordName) inst=\(instanceID) note=\(noteID) block=\(blockID) ok=\(orderKey) del=\(deleted) c=\(createdAtMs) u=\(updatedAtMs) keys=\(Array(f.keys).sorted())")

                if applyLocal {
                    if instanceID.isEmpty || noteID.isEmpty || blockID.isEmpty {
                        skippedCount += 1
                        append("APPLY_SKIP missing required fields")
                        continue
                    }
                    upsertLocal(
                        instanceID: instanceID,
                        noteID: noteID,
                        blockID: blockID,
                        orderKey: orderKey,
                        viewStateJSON: viewState,
                        createdAtMs: createdAtMs,
                        updatedAtMs: updatedAtMs,
                        deleted: deleted
                    )
                    appliedCount += 1
                }
            }

            localCount = countLocal()
            append("DONE localAfter=\(localCount)")
        } catch {
            append("ERROR \(String(describing: error))")
        }

        isRunning = false
    }

    private func fetchAll(db: CKDatabase, query: CKQuery) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        while true {
            let (page, next) = try await fetchPage(db: db, query: cursor == nil ? query : nil, cursor: cursor)
            out.append(contentsOf: page)
            cursor = next
            if cursor == nil { break }
        }

        return out
    }

    private func fetchPage(db: CKDatabase, query: CKQuery?, cursor: CKQueryOperation.Cursor?) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { cont in
            var page: [CKRecord] = []

            let op: CKQueryOperation
            if let cursor {
                op = CKQueryOperation(cursor: cursor)
            } else {
                op = CKQueryOperation(query: query!)
            }

            op.resultsLimit = 200
            op.recordFetchedBlock = { r in
                page.append(r)
            }
            op.queryCompletionBlock = { nextCursor, err in
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                cont.resume(returning: (page, nextCursor))
            }

            db.add(op)
        }
    }

    private func recordToFields(_ r: CKRecord) -> [String: Any] {
        var f: [String: Any] = [:]
        for k in r.allKeys() {
            let v = r[k]
            if let v = v as? NSString { f[k] = v as String; continue }
            if let v = v as? NSNumber { f[k] = v; continue }
            if let v = v as? NSDate { f[k] = Int64(v.timeIntervalSince1970 * 1000); continue }
            if let v = v as? Data { f[k] = v.base64EncodedString(); continue }
            if let v = v { f[k] = v }
        }
        return f
    }

    private func upsertLocal(instanceID: String, noteID: String, blockID: String, orderKey: Double, viewStateJSON: String, createdAtMs: Int64, updatedAtMs: Int64, deleted: Int64) {
        let cMs = createdAtMs != 0 ? createdAtMs : updatedAtMs
        let uMs = updatedAtMs != 0 ? updatedAtMs : createdAtMs

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_note_block
            (block_id, created_at_ms, deleted, instance_id, note_id, order_key, updated_at_ms, view_state_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(instance_id) DO UPDATE SET
              block_id=excluded.block_id,
              created_at_ms=CASE WHEN nj_note_block.created_at_ms IS NULL OR nj_note_block.created_at_ms = 0 THEN excluded.created_at_ms ELSE nj_note_block.created_at_ms END,
              deleted=excluded.deleted,
              note_id=excluded.note_id,
              order_key=excluded.order_key,
              updated_at_ms=excluded.updated_at_ms,
              view_state_json=excluded.view_state_json;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, cMs)
            sqlite3_bind_int64(stmt, 3, deleted)
            sqlite3_bind_text(stmt, 4, instanceID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 6, orderKey)
            sqlite3_bind_int64(stmt, 7, uMs)
            sqlite3_bind_text(stmt, 8, viewStateJSON, -1, SQLITE_TRANSIENT)

            _ = sqlite3_step(stmt)
        }
    }

    private func countLocal() -> Int {
        var c = 0
        db.withDB { dbp in
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(dbp, "SELECT COUNT(*) FROM nj_note_block WHERE deleted=0;", -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) != SQLITE_ROW { return }
            c = Int(sqlite3_column_int(stmt, 0))
        }
        return c
    }

    private func int64Any(_ v: Any?) -> Int64 {
        if let v = v as? Int64 { return v }
        if let v = v as? Int { return Int64(v) }
        if let v = v as? Double { return Int64(v) }
        if let v = v as? NSNumber { return v.int64Value }
        if let v = v as? String { return Int64(v) ?? 0 }
        return 0
    }

    private func doubleAny(_ v: Any?) -> Double {
        if let v = v as? Double { return v }
        if let v = v as? Int64 { return Double(v) }
        if let v = v as? Int { return Double(v) }
        if let v = v as? NSNumber { return v.doubleValue }
        if let v = v as? String { return Double(v) ?? 0 }
        return 0
    }

    private func append(_ s: String) {
        log += s + "\n"
        print(s)
    }
}
