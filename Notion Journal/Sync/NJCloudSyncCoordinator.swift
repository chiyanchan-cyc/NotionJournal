import Foundation
import SQLite3

private enum NJLog {
    nonisolated static var push: Bool { false }
    nonisolated static var pull: Bool { false }
    nonisolated static var noisy: Bool { false }
    nonisolated static func p(_ s: String) { if push { print(s) } }
    nonisolated static func l(_ s: String) { if pull { print(s) } }
    nonisolated static func n(_ s: String) { if noisy { print(s) } }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor NJCloudSyncCoordinator {
    private let repo: DBNoteRepository
    private let transport: NJCloudKitTransport
    private var isSyncing = false
    private var pendingSync = false
    private var isPulling = false
    private let syncDisabledEntities: Set<String> = [
        "health_sample",
        "finance_macro_event",
        "investment_chart_drawing",
        "renewal_item",
        "card_schema",
        "card"
    ]
    private let maxFutureCursorSkewMs: Int64 = 60_000
    private let overlapPullMsByEntity: [String: Int64] = [
        "block": 300_000,
        "table": 7 * 24 * 60 * 60 * 1_000,
        "note_block": 300_000,
        "attachment": 300_000,
        "note": 120_000,
        "finance_transaction": 300_000,
        "investment_ledger_transaction": 300_000,
        "investment_chart_drawing": 300_000
    ]

    init(repo: DBNoteRepository, transport: NJCloudKitTransport) {
        self.repo = repo
        self.transport = transport
    }

    func syncOnce() async {
        if isSyncing {
            pendingSync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        while true {
            pendingSync = false

            await pushAll()
            await pullAll(forceSinceZero: false)

            let remainingDirty = await MainActor.run {
                repo.pendingDirtyCount()
            }
            if remainingDirty > 0 {
                pendingSync = true
            }

            if !pendingSync { break }
        }
    }

    func pushPendingOnly() async {
        if isSyncing {
            pendingSync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        for _ in 0..<6 {
            pendingSync = false

            let beforeCount = await MainActor.run {
                repo.pendingDirtyCount()
            }
            if beforeCount <= 0 { break }

            await pushAll()

            let remainingDirty = await MainActor.run {
                repo.pendingDirtyCount()
            }
            if remainingDirty <= 0 || remainingDirty >= beforeCount { break }
        }
    }

    func pullAll(forceSinceZero: Bool) async {
        if isPulling {
            NJLog.l("NJ_CK_PULL_SKIP reason=in_flight forceSinceZero=\(forceSinceZero)")
            return
        }
        isPulling = true
        defer { isPulling = false }

        let order: [(String, String)] = await MainActor.run { NJCloudSchema.syncOrder }

        for (entity, recordType) in order {
            if syncDisabledEntities.contains(entity) {
                NJLog.l("NJ_CK_PULL_SKIP entity=\(entity) reason=pull_query_not_deployed")
                continue
            }

            let cursorMs: Int64 = forceSinceZero ? 0 : await loadLastPullMs(entity: entity)
            let overlapMs = overlapPullMsByEntity[entity] ?? 0
            let sinceMs = max(0, cursorMs - overlapMs)

            NJLog.l("NJ_CK_PULL_BEGIN entity=\(entity) recordType=\(recordType) forceSinceZero=\(forceSinceZero) cursor=\(cursorMs) since=\(sinceMs)")
            var (rawRows, newMax) = await transport.pullEntityAll(entity: entity, recordType: recordType, sinceMs: sinceMs)
            NJLog.l("NJ_CK_PULL_TRANSPORT_DONE entity=\(entity) rawRows=\(rawRows.count) newMax=\(newMax)")

            if entity == "table" {
                let tableIDs = await MainActor.run {
                    NJTableStore.shared.listKnownTableIDs()
                }
                NJLog.l("NJ_CK_PULL_TABLE_DIRECT_BEGIN requested=\(tableIDs.count)")
                let directRows = await transport.fetchEntityRecords(entity: entity, recordType: recordType, ids: tableIDs)
                NJLog.l("NJ_CK_PULL_TABLE_DIRECT_DONE requested=\(tableIDs.count) rows=\(directRows.count)")
                if !directRows.isEmpty {
                    rawRows.append(contentsOf: directRows)
                    for row in directRows {
                        let updated = Self.int64Any(row["updated_at_ms"])
                        if updated > newMax { newMax = updated }
                    }
                }
            }

            let rows: [(String, [String: Any])] = rawRows.map { r in
                (Self.inferID(entity: entity, row: r), r)
            }

            if !rows.isEmpty {
                NJLog.l("NJ_CK_PULL_APPLY_BEGIN entity=\(entity) rows=\(rows.count)")
                await MainActor.run {
                    DBDirtyQueueTable.withPullScope {
                        repo.applyPulled(entity: entity, rows: rows)
                    }
                }
                NJLog.l("NJ_CK_PULL_APPLY_DONE entity=\(entity) rows=\(rows.count)")
            }

            if newMax > cursorMs {
                await saveLastPullMs(entity: entity, ms: newMax)
            }

            NJLog.l("NJ_CK_PULL_END entity=\(entity) rows=\(rows.count) newMax=\(newMax) savedCursor=\(newMax > cursorMs ? 1 : 0)")
        }
    }

    func pushAll() async {
        let order: [(String, String)] = await MainActor.run { NJCloudSchema.syncOrder }

        let rawBatch = await MainActor.run {
            repo.takeDirtyBatchDetailed(limit: 50)
        }
        let supportedEntities = Set(order.map(\.0)).subtracting(syncDisabledEntities)
        let skippedBatch = rawBatch.filter { !supportedEntities.contains($0.entity) }
        if !skippedBatch.isEmpty {
            let skippedCounts = Dictionary(grouping: skippedBatch, by: { $0.entity }).mapValues(\.count)
            NJLog.p("NJ_PUSH_SKIP_UNSUPPORTED byEntity=\(skippedCounts)")
            for item in skippedBatch {
                await MainActor.run {
                    repo.clearDirty(entity: item.entity, entityID: item.entityID)
                }
            }
        }

        let batch = rawBatch.filter { supportedEntities.contains($0.entity) }

        let sample = batch.prefix(5).map { "\($0.entity):\($0.entityID):\($0.op)" }
        let entityCounts = Dictionary(grouping: batch, by: { $0.entity }).mapValues(\.count)
        NJLog.p("NJ_PUSH_ALL batchCount=\(batch.count) byEntity=\(entityCounts) sample=\(sample)")

        if batch.isEmpty { return }

        for (entity, recordType) in order {
            let items = batch.filter { $0.entity == entity }
            let ids = items.map { $0.entityID }
            if ids.isEmpty { continue }

            let deleteIDs = items.filter { $0.op == "delete" }.map { $0.entityID }
            if !deleteIDs.isEmpty {
                NJLog.p("NJ_PUSH_DELETE entity=\(entity) ids=\(deleteIDs.count)")
                let deleted = await transport.deleteEntity(entity: entity, recordType: recordType, ids: deleteIDs)
                if !deleted.isEmpty {
                    for id in deleted {
                        await MainActor.run {
                            repo.clearDirty(entity: entity, entityID: id)
                        }
                    }
                }
            }

            let upsertIDs = items.filter { $0.op != "delete" }.map { $0.entityID }
            if upsertIDs.isEmpty { continue }

            var rows: [(String, [String: Any])] = []
            rows.reserveCapacity(upsertIDs.count)

            for id in upsertIDs {
                let f = await MainActor.run {
                    repo.cloudFields(entity: entity, id: id)
                }
                if f.isEmpty {
                    NJLog.p("NJ_PUSH_SKIP_EMPTY entity=\(entity) id=\(id)")
                    continue
                }
                rows.append((id, f))
            }


            if rows.isEmpty { continue }

            NJLog.p("NJ_PUSH_PREP entity=\(entity) dirtyIDs=\(upsertIDs.count) rows=\(rows.count)")

            let saved = await transport.pushEntity(entity: entity, recordType: recordType, rows: rows)

            let tryIDs = Set(rows.map { $0.0 })
            let savedIDs = Set(saved)
            let missing = Array(tryIDs.subtracting(savedIDs)).sorted()
            NJLog.p("NJ_PUSH_ENTITY entity=\(entity) try=\(rows.count) saved=\(saved.count) missing=\(missing.count) savedHead=\(saved.prefix(5)) missingHead=\(missing.prefix(20)) tryHead=\(rows.prefix(5).map{$0.0})")

            if !saved.isEmpty {
                for id in saved {
                    await MainActor.run {
                        repo.clearDirty(entity: entity, entityID: id)
                    }
                }
            }

        }
    }

    private static func inferID(entity: String, row: [String: Any]) -> String {
        switch entity {
        case "notebook":
            return (row["notebook_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "tab":
            return (row["tab_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "note":
            return (row["note_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "block":
            return (row["block_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "table":
            return (row["table_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "note_block":
            return (row["instance_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "goal":
            return (row["goal_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "calendar_item":
            return (row["date_key"] as? String) ?? (row["id"] as? String) ?? ""
        case "planned_exercise":
            return (row["plan_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "health_sample":
            return (row["sample_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "planning_note":
            return (row["planning_key"] as? String) ?? (row["id"] as? String) ?? ""
        case "finance_transaction":
            return (row["transaction_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "investment_ledger_transaction":
            return (row["ledger_transaction_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "investment_chart_drawing":
            return (row["drawing_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "investment_symbol":
            return (row["symbol_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "investment_symbol_relationship":
            return (row["relationship_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "agent_heartbeat_run":
            return (row["run_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "agent_backfill_task":
            return (row["task_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "time_slot":
            return (row["time_slot_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "personal_goal":
            return (row["goal_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "renewal_item":
            return (row["renewal_item_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "card_schema":
            return (row["schema_key"] as? String) ?? (row["id"] as? String) ?? ""
        case "card":
            return (row["card_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "outline":
            return (row["outline_id"] as? String) ?? (row["id"] as? String) ?? ""
        case "outline_node":
            return (row["node_id"] as? String) ?? (row["id"] as? String) ?? ""
        default:
            return (row["id"] as? String) ?? ""
        }
    }

    private static func int64Any(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func loadLastPullMs(entity: String) async -> Int64 {
        let key = "ck_since_\(entity)"
        return await MainActor.run {
            repo.db.withDB { dbp in
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, "SELECT v FROM nj_kv WHERE k=?;", -1, &stmt, nil)
                if rc0 != SQLITE_OK { return 0 }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

                let rc1 = sqlite3_step(stmt)
                if rc1 != SQLITE_ROW { return 0 }

                guard let cstr = sqlite3_column_text(stmt, 0) else { return 0 }
                let s = String(cString: cstr)
                let stored = Int64(s) ?? 0
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let capped = min(stored, now + self.maxFutureCursorSkewMs)
                if capped != stored {
                    print("NJ_CK_CURSOR_CLAMP entity=\(entity) stored=\(stored) capped=\(capped) now=\(now)")
                }
                return capped
            }
        }
    }

    private func saveLastPullMs(entity: String, ms: Int64) async {
        let key = "ck_since_\(entity)"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let clamped = min(ms, now + maxFutureCursorSkewMs)
        if clamped != ms {
            print("NJ_CK_CURSOR_SAVE_CLAMP entity=\(entity) incoming=\(ms) saved=\(clamped) now=\(now)")
        }
        let val = String(clamped)
        await MainActor.run {
            repo.db.withDB { dbp in
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, "INSERT INTO nj_kv(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v;", -1, &stmt, nil)
                if rc0 != SQLITE_OK { return }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, val, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
        }
    }
}
