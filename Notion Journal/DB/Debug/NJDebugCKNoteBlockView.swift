import SwiftUI
import CloudKit
import SQLite3

struct NJDebugCKNoteBlockView: View {
    let containerID: String
    let recordType: String
    let noteBlockTable: DBNoteBlockTable

    @State private var log: String = ""
    @State private var isRunning = false
    @State private var fetchedCount = 0
    @State private var appliedCount = 0
    @State private var skippedCount = 0
    @State private var localCount = -1

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(isRunning ? "Running..." : "Fetch CK deleted=0 + Apply Local") {
                    Task { await run() }
                }
                .disabled(isRunning)
                Button("Clear Log") { log = "" }
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

    private func run() async {
        if isRunning { return }
        isRunning = true
        fetchedCount = 0
        appliedCount = 0
        skippedCount = 0
        append("BEGIN container=\(containerID) recordType=\(recordType)")

        let container = CKContainer(identifier: containerID)
        let db = container.privateCloudDatabase

        do {
            let predicate = NSPredicate(format: "deleted == 0")
            let query = CKQuery(recordType: recordType, predicate: predicate)

            let (records, cursor) = try await fetchAll(db: db, query: query)
            if cursor != nil { append("WARN cursor non-nil (unexpected in await loop)") }

            fetchedCount = records.count
            append("CK_FETCH_DONE count=\(records.count)")

            for r in records {
                let f = recordToFields(r)
                let id = (f["instance_id"] as? String) ?? (f["id"] as? String) ?? ""
                if id.isEmpty {
                    skippedCount += 1
                    append("SKIP missing_id record=\(r.recordID.recordName) keys=\(Array(f.keys).sorted())")
                    continue
                }

                noteBlockTable.applyNJNoteBlock(f)
                appliedCount += 1

                let noteID = (f["note_id"] as? String) ?? ""
                let blockID = (f["block_id"] as? String) ?? ""
                let orderKeyAny = f["order_key"]
                let updatedAt = f["updated_at_ms"] ?? 0
                append("APPLY ok id=\(id) note=\(noteID) block=\(blockID) order=\(String(describing: orderKeyAny)) updated=\(updatedAt)")
            }

            localCount = countLocal()
            append("LOCAL_COUNT nj_note_block=\(localCount)")
            append("DONE")
        } catch {
            append("ERROR \(String(describing: error))")
        }

        isRunning = false
    }

    private func fetchAll(db: CKDatabase, query: CKQuery) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        var out: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        var nextQuery: CKQuery? = query
        var nextCursor: CKQueryOperation.Cursor? = nil

        while true {
            if let c = nextCursor {
                let (recs, newCursor) = try await db.records(matching: c)
                out.append(contentsOf: recs.compactMap { $0.1 })
                nextCursor = newCursor
            } else if let q = nextQuery {
                let (matchResults, newCursor) = try await db.records(matching: q, resultsLimit: 200)
                out.append(contentsOf: matchResults.compactMap { $0.1 })
                nextCursor = newCursor
                nextQuery = nil
            } else {
                break
            }

            if nextCursor == nil {
                cursor = nil
                break
            }
        }

        return (out, cursor)
    }

    private func recordToFields(_ r: CKRecord) -> [String: Any] {
        var f: [String: Any] = [:]
        f["id"] = r.recordID.recordName

        for k in r.allKeys() {
            let v = r[k]
            if let v = v as? NSString { f[k] = v as String; continue }
            if let v = v as? NSNumber { f[k] = v.int64Value; continue }
            if let v = v as? NSDate { f[k] = Int64(v.timeIntervalSince1970 * 1000); continue }
            if let v = v as? Data { f[k] = v.base64EncodedString(); continue }
            if let v = v { f[k] = v }
        }

        if f["instance_id"] == nil, let id = f["id"] as? String { f["instance_id"] = id }

        return f
    }

    private func countLocal() -> Int {
        var c = -1
        noteBlockTable.db.withDB { dbp in
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(dbp, "SELECT COUNT(*) FROM nj_note_block WHERE deleted=0;", -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) != SQLITE_ROW { return }
            c = Int(sqlite3_column_int(stmt, 0))
        }
        return c
    }

    private func append(_ s: String) {
        log += s + "\n"
        print(s)
    }
}
