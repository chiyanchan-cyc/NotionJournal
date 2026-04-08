import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


@MainActor
final class DBNoteRepository {
    
    let db: SQLiteDB
    
    private let dirtyQueue: DBDirtyQueueTable
    private let noteTable: DBNoteTable
    private let blockTable: DBBlockTable
    private let noteBlockTable: DBNoteBlockTable
    let attachmentTable: DBAttachmentTable
    let goalTable: DBGoalTable
    let calendarTable: DBCalendarTable
    let plannedExerciseTable: DBPlannedExerciseTable
    let planningNoteTable: DBPlanningNoteTable
    let financeMacroEventTable: DBFinanceMacroEventTable
    let financeDailyBriefTable: DBFinanceDailyBriefTable
    let financeResearchSessionTable: DBFinanceResearchSessionTable
    let financeResearchMessageTable: DBFinanceResearchMessageTable
    let financeResearchTaskTable: DBFinanceResearchTaskTable
    let financeFindingTable: DBFinanceFindingTable
    let financeJournalLinkTable: DBFinanceJournalLinkTable
    let financeSourceItemTable: DBFinanceSourceItemTable
    let timeSlotTable: DBTimeSlotTable
    let personalGoalTable: DBPersonalGoalTable
    private let cloudBridge: DBCloudBridge
    
    
    init(db: SQLiteDB) {
        self.db = db
        self.dirtyQueue = DBDirtyQueueTable(db: db)
        
        let dq = self.dirtyQueue
        
        self.blockTable = DBBlockTable(db: db, enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) })
        
        self.noteBlockTable = DBNoteBlockTable(db: db, enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) })

        self.attachmentTable = DBAttachmentTable(db: db, enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) })
        
        self.noteTable = DBNoteTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) },
            loadRTF: { _ in
                nil
            },
            emptyRTF: { Self.emptyRTF() },
            nowMs: { Self.nowMs() }
        )
        self.goalTable = DBGoalTable(db: db)
        self.calendarTable = DBCalendarTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.plannedExerciseTable = DBPlannedExerciseTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.planningNoteTable = DBPlanningNoteTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeMacroEventTable = DBFinanceMacroEventTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeDailyBriefTable = DBFinanceDailyBriefTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeResearchSessionTable = DBFinanceResearchSessionTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeResearchMessageTable = DBFinanceResearchMessageTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeResearchTaskTable = DBFinanceResearchTaskTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeFindingTable = DBFinanceFindingTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeJournalLinkTable = DBFinanceJournalLinkTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.financeSourceItemTable = DBFinanceSourceItemTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.timeSlotTable = DBTimeSlotTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.personalGoalTable = DBPersonalGoalTable(
            db: db,
            enqueueDirty: { e, id, op, ms in dq.enqueueDirty(entity: e, entityID: id, op: op, updatedAtMs: ms) }
        )
        self.cloudBridge = DBCloudBridge(
            noteTable: self.noteTable,
            blockTable: self.blockTable,
            noteBlockTable: self.noteBlockTable,
            attachmentTable: self.attachmentTable,
            goalTable: self.goalTable,
            calendarTable: self.calendarTable,
            plannedExerciseTable: self.plannedExerciseTable,
            planningNoteTable: self.planningNoteTable,
            financeMacroEventTable: self.financeMacroEventTable,
            financeDailyBriefTable: self.financeDailyBriefTable,
            financeResearchSessionTable: self.financeResearchSessionTable,
            financeResearchMessageTable: self.financeResearchMessageTable,
            financeResearchTaskTable: self.financeResearchTaskTable,
            financeFindingTable: self.financeFindingTable,
            financeJournalLinkTable: self.financeJournalLinkTable,
            financeSourceItemTable: self.financeSourceItemTable,
            timeSlotTable: self.timeSlotTable,
            personalGoalTable: self.personalGoalTable
        )
    }
    
    func listOrphanClipBlocks(limit: Int = 200) -> [DBBlockTable.NJOrphanClipRow] {
        blockTable.listOrphanClipBlocks(limit: limit)
    }

    func listOrphanAudioBlocks(limit: Int = 200) -> [DBBlockTable.NJOrphanAudioRow] {
        blockTable.listOrphanAudioBlocks(limit: limit)
    }

    func listOrphanQuickBlocks(limit: Int = 200) -> [DBBlockTable.NJOrphanQuickRow] {
        blockTable.listOrphanQuickBlocks(limit: limit)
    }

    func listAudioBlocks(limit: Int = 200) -> [DBBlockTable.NJAudioRow] {
        blockTable.listAudioBlocks(limit: limit)
    }

    func loadBlock(blockID: String) -> [String: Any]? {
        blockTable.loadNJBlock(blockID: blockID)
    }

    func listNotesByDateRange(startMs: Int64, endMs: Int64) -> [NJNote] {
        noteTable.listNotesByDateRange(startMs: startMs, endMs: endMs)
    }

    func lastJournaledAtMsForTag(_ tag: String) -> Int64 {
        blockTable.lastJournaledAtMsForTag(tag)
    }

    func listTagSuggestions(prefix: String, limit: Int = 12) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT tag
            FROM (
                SELECT DISTINCT t.tag AS tag
                FROM nj_block_tag t
                WHERE lower(t.tag) LIKE lower(?)
                UNION
                SELECT DISTINCT g.goal_tag AS tag
                FROM nj_goal g
                WHERE g.goal_tag IS NOT NULL
                  AND trim(g.goal_tag) <> ''
                  AND lower(g.goal_tag) LIKE lower(?)
            )
            ORDER BY tag COLLATE NOCASE ASC
            LIMIT ?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return out }
            defer { sqlite3_finalize(stmt) }

            let pattern = "\(trimmed)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(max(1, limit)))

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
            }
            return out
        }
    }

    func listGoalSummaries(includeDeleted: Bool = false) -> [NJGoalSummary] {
        goalTable.listGoalSummaries(includeDeleted: includeDeleted)
    }

    func listJournalEntryDateKeysByGoalTag(
        tags: [String],
        startMs: Int64,
        endMs: Int64
    ) -> [String: Set<String>] {
        let cleanedTags = Array(
            Set(
                tags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        guard !cleanedTags.isEmpty, endMs > startMs else { return [:] }

        return db.withDB { dbp in
            var out: [String: Set<String>] = [:]
            var stmt: OpaquePointer?
            let placeholders = Array(repeating: "?", count: cleanedTags.count).joined(separator: ",")
            let sql = """
            SELECT t.tag, b.created_at_ms
            FROM nj_block_tag t
            JOIN nj_block b
              ON b.block_id = t.block_id
            WHERE t.tag IN (\(placeholders))
              AND b.deleted = 0
              AND b.created_at_ms >= ?
              AND b.created_at_ms < ?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return out }
            defer { sqlite3_finalize(stmt) }

            var bindIndex: Int32 = 1
            for tag in cleanedTags {
                sqlite3_bind_text(stmt, bindIndex, tag, -1, SQLITE_TRANSIENT)
                bindIndex += 1
            }
            sqlite3_bind_int64(stmt, bindIndex, startMs)
            sqlite3_bind_int64(stmt, bindIndex + 1, endMs)

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let tagC = sqlite3_column_text(stmt, 0) else { continue }
                let tag = String(cString: tagC).trimmingCharacters(in: .whitespacesAndNewlines)
                if tag.isEmpty { continue }
                let createdAtMs = sqlite3_column_int64(stmt, 1)
                let date = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000.0)
                let key = Self.dateKey(date)
                out[tag, default: []].insert(key)
            }
            return out
        }
    }

    func markBlockDeleted(blockID: String) {
        blockTable.markBlockDeleted(blockID: blockID)
    }

    func loadBlockTagJSON(blockID: String) -> String {
        blockTable.loadNJBlock(blockID: blockID)?["tag_json"] as? String ?? ""
    }

    func updateBlockTagJSON(blockID: String, tagJSON: String, nowMs: Int64) {
        blockTable.updateBlockTagJSON(blockID: blockID, tagJSON: tagJSON, updatedAtMs: nowMs)
    }

    func updateBlockCreatedAtMs(blockID: String, createdAtMs: Int64, nowMs: Int64) {
        blockTable.updateBlockCreatedAtMs(blockID: blockID, createdAtMs: createdAtMs, updatedAtMs: nowMs)
    }

    func markNoteBlockDeleted(instanceID: String, nowMs: Int64) {
        noteBlockTable.markNoteBlockDeleted(instanceID: instanceID, nowMs: nowMs)
    }

    func updateBlockPayloadJSON(blockID: String, payloadJSON: String, updatedAtMs: Int64) {
        blockTable.updateBlockPayloadJSON(blockID: blockID, payloadJSON: payloadJSON, updatedAtMs: updatedAtMs)
    }

    func setBlockGoalID(blockID: String, goalID: String) {
        blockTable.setGoalID(blockID: blockID, goalID: goalID, updatedAtMs: Self.nowMs())
    }

    func createQuickNoteBlock(payloadJSON: String, createdAtMs: Int64? = nil, tags: [String] = []) -> String? {
        let title = NJQuickNotePayload.title(from: payloadJSON)
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let blockID = UUID().uuidString
        let now = createdAtMs ?? Self.nowMs()
        let cleanedTags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let tagJSON: String = {
            guard !cleanedTags.isEmpty,
                  let d = try? JSONSerialization.data(withJSONObject: cleanedTags),
                  let s = String(data: d, encoding: .utf8)
            else { return "" }
            return s
        }()

        blockTable.applyNJBlock([
            "block_id": blockID,
            "block_type": "quick",
            "payload_json": payloadJSON,
            "domain_tag": "",
            "tag_json": tagJSON,
            "goal_id": "",
            "lineage_id": "",
            "parent_block_id": "",
            "created_at_ms": now,
            "updated_at_ms": now,
            "deleted": Int64(0)
        ])
        if !cleanedTags.isEmpty {
            blockTable.upsertTagsForBlockID(blockID: blockID, tags: cleanedTags, nowMs: now)
        }

        return blockID
    }
    
    func upsertTagsForNoteBlockInstanceID(
        instanceID: String,
        tags: [String],
        nowMs: Int64
    ) {
        var resolvedBlockID = instanceID
        
        if !blockTable.hasBlock(blockID: resolvedBlockID) {
            if let nb = noteBlockTable.loadNJNoteBlock(instanceID: instanceID),
               let bid = nb["block_id"] as? String,
               !bid.isEmpty {
                resolvedBlockID = bid
            }
        }
        
        upsertTagsForBlockID(
            blockID: resolvedBlockID,
            tags: tags,
            nowMs: nowMs
        )
    }
    
    func upsertTagsForBlockID(
        blockID: String,
        tags: [String],
        nowMs: Int64
    ) {
        guard blockTable.hasBlock(blockID: blockID) else {
            print("NJ_TAG no block \(blockID)")
            return
        }
        
        blockTable.upsertTagsForBlockID(
            blockID: blockID,
            tags: tags,
            nowMs: nowMs
        )
    }
    
    func applyPulled(entity: String, rows: [(String, [String: Any])]) {
        switch entity {
        case "notebook":
            for (_, f) in rows { applyRemoteUpsert(entity: "notebook", fields: f) }
            
        case "tab":
            for (_, f) in rows { applyRemoteUpsert(entity: "tab", fields: f) }
            
        case "note":
            for (_, f) in rows { applyRemoteUpsert(entity: "note", fields: f) }

        case "goal":
            for (_, f) in rows { applyRemoteUpsert(entity: "goal", fields: f) }

        case "block":
            for (_, f) in rows { applyRemoteUpsert(entity: "block", fields: f) }

        case "attachment":
            for (_, f) in rows { applyRemoteUpsert(entity: "attachment", fields: f) }

        case "calendar_item":
            for (_, f) in rows { applyRemoteUpsert(entity: "calendar_item", fields: f) }
        case "planned_exercise":
            for (_, f) in rows { applyRemoteUpsert(entity: "planned_exercise", fields: f) }
        case "planning_note":
            for (_, f) in rows { applyRemoteUpsert(entity: "planning_note", fields: f) }
        case "finance_macro_event":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_macro_event", fields: f) }
        case "finance_daily_brief":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_daily_brief", fields: f) }
        case "finance_research_session":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_research_session", fields: f) }
        case "finance_research_message":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_research_message", fields: f) }
        case "finance_research_task":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_research_task", fields: f) }
        case "finance_finding":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_finding", fields: f) }
        case "finance_journal_link":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_journal_link", fields: f) }
        case "finance_source_item":
            for (_, f) in rows { applyRemoteUpsert(entity: "finance_source_item", fields: f) }
        case "time_slot":
            for (_, f) in rows { applyRemoteUpsert(entity: "time_slot", fields: f) }
        case "personal_goal":
            for (_, f) in rows { applyRemoteUpsert(entity: "personal_goal", fields: f) }

        case "outline":
            for (_, f) in rows { applyRemoteUpsert(entity: "outline", fields: f) }

        case "outline_node":
            for (_, f) in rows { applyRemoteUpsert(entity: "outline_node", fields: f) }

        case "note_block":
            func noteID(_ f: [String: Any]) -> String { (f["note_id"] as? String) ?? (f["noteID"] as? String) ?? "" }
            func blockID(_ f: [String: Any]) -> String { (f["block_id"] as? String) ?? (f["blockID"] as? String) ?? "" }
            
            var pending: [[String: Any]] = rows.map { $0.1 }
            var passes = 0
            while !pending.isEmpty && passes < 5 {
                passes += 1
                var next: [[String: Any]] = []
                next.reserveCapacity(pending.count)
                
                for f in pending {
                    let n = noteID(f)
                    let b = blockID(f)
                    if n.isEmpty || b.isEmpty { continue }
                    if getNote(NJNoteID(n)) == nil { next.append(f); continue }
                    if hasBlock(blockID: b) == false { next.append(f); continue }
                    applyRemoteUpsert(entity: "note_block", fields: f)
                }
                
                if next.count == pending.count { break }
                pending = next
            }
            
        default:
            break
        }
    }
    
    func cloudFields(entity: String, id: String) -> [String: Any] {
        if entity == "notebook" { return loadNotebookFields(notebookID: id) ?? [:] }
        if entity == "tab" { return loadTabFields(tabID: id) ?? [:] }
        if entity == "outline" { return loadOutlineFields(outlineID: id) ?? [:] }
        if entity == "outline_node" { return loadOutlineNodeFields(nodeID: id) ?? [:] }
        return loadRecord(entity: entity, id: id) ?? [:]
    }

    func cleanupCalendarItemsOlderThan3Months() {
        // Memory photos should persist indefinitely. Keep this method as a no-op so
        // older callers remain safe while we preserve historical calendar data.
    }

    func restoreDeletedCalendarPhotoItems() -> Int {
        let items: [NJCalendarItem] = db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT date_key, title, photo_attachment_id, photo_local_id, photo_cloud_id, photo_thumb_path,
                   created_at_ms, updated_at_ms, deleted
            FROM nj_calendar_item
            WHERE deleted = 1
              AND (
                trim(photo_attachment_id) <> ''
                OR trim(photo_local_id) <> ''
                OR trim(photo_cloud_id) <> ''
                OR trim(photo_thumb_path) <> ''
              )
            ORDER BY date_key ASC;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return [] }
            defer { sqlite3_finalize(stmt) }

            var out: [NJCalendarItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                let photoAttachmentID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
                let photoLocalID = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
                let photoCloudID = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                let photoThumbPath = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""
                let createdAtMs = sqlite3_column_int64(stmt, 6)
                let updatedAtMs = sqlite3_column_int64(stmt, 7)
                let deleted = Int(sqlite3_column_int64(stmt, 8))
                out.append(
                    NJCalendarItem(
                        dateKey: key,
                        title: title,
                        photoAttachmentID: photoAttachmentID,
                        photoLocalID: photoLocalID,
                        photoCloudID: photoCloudID,
                        photoThumbPath: photoThumbPath,
                        createdAtMs: createdAtMs,
                        updatedAtMs: updatedAtMs,
                        deleted: deleted
                    )
                )
            }
            return out
        }

        guard !items.isEmpty else { return 0 }

        let now = Self.nowMs()
        var restored = 0
        for var item in items {
            item.deleted = 0
            item.updatedAtMs = now
            calendarTable.upsertItem(item)
            if !item.photoAttachmentID.isEmpty, var att = attachmentByID(item.photoAttachmentID) {
                att.deleted = 0
                att.updatedAtMs = now
                attachmentTable.upsertAttachment(att, nowMs: now)
            }
            restored += 1
        }
        return restored
    }
    
    func localCount(entity: String) -> Int {
        let table: String
        switch entity {
        case "notebook": table = "nj_notebook"
        case "tab": table = "nj_tab"
        case "note": table = "nj_note"
        case "block": table = "nj_block"
        case "note_block": table = "nj_note_block"
        case "calendar_item": table = "nj_calendar_item"
        case "planned_exercise": table = "nj_planned_exercise"
        case "planning_note": table = "nj_planning_note"
        case "finance_macro_event": table = "nj_finance_macro_event"
        case "finance_daily_brief": table = "nj_finance_daily_brief"
        case "finance_research_session": table = "nj_finance_research_session"
        case "finance_research_message": table = "nj_finance_research_message"
        case "finance_research_task": table = "nj_finance_research_task"
        case "finance_finding": table = "nj_finance_finding"
        case "finance_journal_link": table = "nj_finance_journal_link"
        case "finance_source_item": table = "nj_finance_source_item"
        case "time_slot": table = "nj_time_slot"
        case "personal_goal": table = "nj_personal_goal"
        case "outline": table = "nj_outline"
        case "outline_node": table = "nj_outline_node"
        default: return 0
        }
        
        return db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "localCount.prepare", rc0); return 0 }
            defer { sqlite3_finalize(stmt) }
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_ROW { db.dbgErr(dbp, "localCount.step", rc1); return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
    
    
    
    
    func hasBlock(blockID: String) -> Bool {
        blockTable.hasBlock(blockID: blockID)
    }
    
    func listNotes(tabDomainKey: String) -> [NJNote] {
        noteTable.listNotes(tabDomainKey: tabDomainKey)
    }
    
    func getNote(_ id: NJNoteID) -> NJNote? {
        noteTable.getNote(id)
    }
    
    func loadBlockPayloadJSON(blockID: String) -> String {
        blockTable.loadBlockPayloadJSON(blockID: blockID)
    }
    
    func createNote(notebook: String, tabDomain: String, title: String) -> NJNote {
        noteTable.createNote(notebook: notebook, tabDomain: tabDomain, title: title)
    }
    
    func upsertNote(_ note: NJNote) {
        noteTable.upsertNote(note)
    }
    
    func deleteNote(_ noteID: NJNoteID) {
        noteTable.deleteNote(noteID)
    }
    
    func deleteNote(noteID: String) {
        noteTable.deleteNote(NJNoteID(noteID))
    }
    
    func markNoteDeleted(noteID: String) {
        noteTable.markNoteDeleted(noteID: noteID)
    }

    func setPinned(noteID: String, pinned: Bool) {
        noteTable.setPinned(noteID: noteID, pinned: pinned)
    }
    
    func enqueueDirty(entity: String, entityID: String, op: String, updatedAtMs: Int64) {
        dirtyQueue.enqueueDirty(entity: entity, entityID: entityID, op: op, updatedAtMs: updatedAtMs)
    }
    
    func takeDirtyBatch(limit: Int) -> [(String, String)] {
        (try? dirtyQueue.takeDirtyBatch(limit: limit))?.map { ($0.entity, $0.entityID) } ?? []
    }

    func takeDirtyBatchDetailed(limit: Int) -> [NJDirtyItem] {
        (try? dirtyQueue.takeDirtyBatch(limit: limit)) ?? []
    }
    
    
    func clearDirty(entity: String, entityID: String) {
        dirtyQueue.clearDirty(entity: entity, entityID: entityID)
    }
    
    func loadRecord(entity: String, id: String) -> [String: Any]? {
        if entity == "notebook" { return loadNotebookFields(notebookID: id) }
        if entity == "tab" { return loadTabFields(tabID: id) }
        if entity == "outline" { return loadOutlineFields(outlineID: id) }
        if entity == "outline_node" { return loadOutlineNodeFields(nodeID: id) }
        return cloudBridge.loadRecord(entity: entity, id: id)
    }
    
    func applyRemoteUpsert(entity: String, fields: [String: Any]) {
        if entity == "notebook" { applyNotebookFields(fields); return }
        if entity == "tab" { applyTabFields(fields); return }
        if entity == "outline" { applyOutlineFields(fields); return }
        if entity == "outline_node" { applyOutlineNodeFields(fields); return }
        cloudBridge.applyRemoteUpsert(entity: entity, fields: fields)
    }
    
    func recordDirtyError(entity: String, entityID: String, code: Int, domain: String, message: String, retryAfterSec: Double?) {
        dirtyQueue.recordDirtyError(entity: entity, entityID: entityID, code: code, domain: domain, message: message, retryAfterSec: retryAfterSec)
    }
    
    private func loadNotebookFields(notebookID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived
            FROM nj_notebook
            WHERE notebook_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadNotebookFields.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)
            
            let rc1 = sqlite3_step(stmt)
            guard rc1 == SQLITE_ROW else { return nil }
            
            return [
                "notebook_id": String(cString: sqlite3_column_text(stmt, 0)),
                "title": String(cString: sqlite3_column_text(stmt, 1)),
                "color_hex": String(cString: sqlite3_column_text(stmt, 2)),
                "created_at_ms": sqlite3_column_int64(stmt, 3),
                "updated_at_ms": sqlite3_column_int64(stmt, 4),
                "is_archived": sqlite3_column_int64(stmt, 5)
            ]
        }
    }
    
    private func loadTabFields(tabID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            SELECT tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden
            FROM nj_tab
            WHERE tab_id=?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadTabFields.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, tabID, -1, SQLITE_TRANSIENT)
            
            let rc1 = sqlite3_step(stmt)
            guard rc1 == SQLITE_ROW else { return nil }
            
            return [
                "tab_id": String(cString: sqlite3_column_text(stmt, 0)),
                "notebook_id": String(cString: sqlite3_column_text(stmt, 1)),
                "title": String(cString: sqlite3_column_text(stmt, 2)),
                "domain_key": String(cString: sqlite3_column_text(stmt, 3)),
                "color_hex": String(cString: sqlite3_column_text(stmt, 4)),
                "order": sqlite3_column_int64(stmt, 5),
                "created_at_ms": sqlite3_column_int64(stmt, 6),
                "updated_at_ms": sqlite3_column_int64(stmt, 7),
                "is_hidden": sqlite3_column_int64(stmt, 8)
            ]
        }
    }
    
    private func applyNotebookFields(_ f: [String: Any]) {
        guard let notebookID = f["notebook_id"] as? String else { return }
        let title = (f["title"] as? String) ?? ""
        let color = (f["color_hex"] as? String) ?? "#64748B"
        let created = (f["created_at_ms"] as? Int64) ?? Self.nowMs()
        let updated = (f["updated_at_ms"] as? Int64) ?? created
        let archived = (f["is_archived"] as? Int64) ?? 0
        
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_notebook(notebook_id, title, color_hex, created_at_ms, updated_at_ms, is_archived)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(notebook_id) DO UPDATE SET
                title=excluded.title,
                color_hex=excluded.color_hex,
                updated_at_ms=excluded.updated_at_ms,
                is_archived=excluded.is_archived;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyNotebookFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, color, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, created)
            sqlite3_bind_int64(stmt, 5, updated)
            sqlite3_bind_int64(stmt, 6, archived)
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyNotebookFields.step", rc1) }
        }
    }
    
    private func applyTabFields(_ f: [String: Any]) {
        guard let tabID = f["tab_id"] as? String else { return }
        let notebookID = (f["notebook_id"] as? String) ?? ""
        let title = (f["title"] as? String) ?? ""
        let dom = (f["domain_key"] as? String) ?? ""
        let color = (f["color_hex"] as? String) ?? "#64748B"
        let ord = (f["order"] as? Int64) ?? 0
        let created = (f["created_at_ms"] as? Int64) ?? Self.nowMs()
        let updated = (f["updated_at_ms"] as? Int64) ?? created
        let hidden = (f["is_hidden"] as? Int64) ?? 0
        
        if notebookID.isEmpty { return }
        
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_tab(tab_id, notebook_id, title, domain_key, color_hex, ord, created_at_ms, updated_at_ms, is_hidden)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(tab_id) DO UPDATE SET
                notebook_id=excluded.notebook_id,
                title=excluded.title,
                domain_key=excluded.domain_key,
                color_hex=excluded.color_hex,
                ord=excluded.ord,
                updated_at_ms=excluded.updated_at_ms,
                is_hidden=excluded.is_hidden;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyTabFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, tabID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, notebookID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, dom, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, color, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, ord)
            sqlite3_bind_int64(stmt, 7, created)
            sqlite3_bind_int64(stmt, 8, updated)
            sqlite3_bind_int64(stmt, 9, hidden)
            
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyTabFields.step", rc1) }
        }
    }
    
    func findFirstInstanceByBlock(blockID: String) -> (noteID: String, instanceID: String)? {
        noteBlockTable.findFirstInstanceByBlock(blockID: blockID)
    }

    func calendarItem(dateKey: String) -> NJCalendarItem? {
        calendarTable.loadItem(dateKey: dateKey)
    }

    func listCalendarItems(startKey: String, endKey: String) -> [NJCalendarItem] {
        calendarTable.listItems(startKey: startKey, endKey: endKey)
    }

    func upsertCalendarItem(_ item: NJCalendarItem) {
        calendarTable.upsertItem(item)
    }

    func backfillCalendarThumbPath(attachmentID: String, thumbPath: String) {
        calendarTable.backfillThumbPath(attachmentID: attachmentID, thumbPath: thumbPath)
    }

    func deleteCalendarItem(dateKey: String, nowMs: Int64) {
        calendarTable.markDeleted(dateKey: dateKey, nowMs: nowMs)
    }

    func listPlannedExercises(startKey: String, endKey: String) -> [NJPlannedExercise] {
        plannedExerciseTable.listPlans(startKey: startKey, endKey: endKey)
    }

    func upsertPlannedExercise(_ plan: NJPlannedExercise) {
        plannedExerciseTable.upsertPlan(plan)
    }

    func deletePlannedExercise(planID: String, nowMs: Int64) {
        plannedExerciseTable.markDeleted(planID: planID, nowMs: nowMs)
    }

    func listFinanceMacroEvents(startKey: String, endKey: String) -> [NJFinanceMacroEvent] {
        financeMacroEventTable.list(startKey: startKey, endKey: endKey)
    }

    func listFinanceMacroEvents(dateKey: String) -> [NJFinanceMacroEvent] {
        financeMacroEventTable.list(dateKey: dateKey)
    }

    func financeDailyBrief(dateKey: String) -> NJFinanceDailyBrief? {
        financeDailyBriefTable.load(dateKey: dateKey)
    }

    func upsertFinanceMacroEvent(_ row: NJFinanceMacroEvent) {
        financeMacroEventTable.upsert(row)
    }

    func listFinanceDailyBriefs(startKey: String, endKey: String) -> [NJFinanceDailyBrief] {
        financeDailyBriefTable.list(startKey: startKey, endKey: endKey)
    }

    func listFinanceResearchSessions() -> [NJFinanceResearchSession] {
        financeResearchSessionTable.list()
    }

    func financeResearchSession(sessionID: String) -> NJFinanceResearchSession? {
        financeResearchSessionTable.load(sessionID: sessionID)
    }

    func upsertFinanceResearchSession(_ row: NJFinanceResearchSession) {
        financeResearchSessionTable.upsert(row)
    }

    func listFinanceResearchMessages(sessionID: String) -> [NJFinanceResearchMessage] {
        financeResearchMessageTable.list(sessionID: sessionID)
    }

    func upsertFinanceResearchMessage(_ row: NJFinanceResearchMessage) {
        financeResearchMessageTable.upsert(row)
    }

    func listFinanceResearchTasks(sessionID: String) -> [NJFinanceResearchTask] {
        financeResearchTaskTable.list(sessionID: sessionID)
    }

    func upsertFinanceResearchTask(_ row: NJFinanceResearchTask) {
        financeResearchTaskTable.upsert(row)
    }

    func listFinanceFindings(sessionID: String, premiseID: String = "") -> [NJFinanceFinding] {
        financeFindingTable.list(sessionID: sessionID, premiseID: premiseID)
    }

    func upsertFinanceFinding(_ row: NJFinanceFinding) {
        financeFindingTable.upsert(row)
    }

    func upsertFinanceJournalLink(_ row: NJFinanceJournalLink) {
        financeJournalLinkTable.upsert(row)
    }

    func listFinanceSourceItems(premiseID: String, limit: Int = 40) -> [NJFinanceSourceItem] {
        financeSourceItemTable.listForPremise(premiseID, limit: limit)
    }

    func upsertFinanceSourceItem(_ row: NJFinanceSourceItem) {
        financeSourceItemTable.upsert(row)
    }

    func saveFinanceDay(dateKey: String, events: [NJFinanceMacroEvent], brief: NJFinanceDailyBrief?, nowMs: Int64) {
        let existing = financeMacroEventTable.list(dateKey: dateKey)
        let incomingIDs = Set(events.map(\.eventID))
        for row in existing where !incomingIDs.contains(row.eventID) {
            financeMacroEventTable.markDeleted(eventID: row.eventID, nowMs: nowMs)
        }
        for row in events {
            financeMacroEventTable.upsert(row)
        }

        if let brief {
            financeDailyBriefTable.upsert(brief)
        } else if financeDailyBriefTable.loadIncludingDeleted(dateKey: dateKey) != nil {
            financeDailyBriefTable.markDeleted(dateKey: dateKey, nowMs: nowMs)
        }
    }

    func planningNote(kind: String, targetKey: String) -> NJPlanningNote? {
        planningNoteTable.loadNote(kind: kind, targetKey: targetKey)
    }

    func upsertPlanningNote(_ note: NJPlanningNote) {
        planningNoteTable.upsertNote(note)
    }

    func upsertPlanningNote(kind: String, targetKey: String, note: String, protonJSON: String = "", nowMs: Int64) {
        let key = planningNoteTable.makePlanningKey(kind: kind, targetKey: targetKey)
        let existing = planningNoteTable.loadNoteIncludingDeleted(kind: kind, targetKey: targetKey)
        let row = NJPlanningNote(
            planningKey: key,
            kind: kind,
            targetKey: targetKey,
            note: note,
            protonJSON: protonJSON,
            createdAtMs: existing?.createdAtMs ?? nowMs,
            updatedAtMs: nowMs,
            deleted: 0
        )
        planningNoteTable.upsertNote(row)
    }

    func deletePlanningNote(kind: String, targetKey: String, nowMs: Int64) {
        planningNoteTable.markDeleted(kind: kind, targetKey: targetKey, nowMs: nowMs)
    }

    func savePlanningReminder(weekStartKey: String, dateKey: String, weeklyNote: String, dailyNote: String, nowMs: Int64) {
        let weeklyText = weeklyNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let dailyText = dailyNote.trimmingCharacters(in: .whitespacesAndNewlines)

        if weeklyText.isEmpty {
            if planningNoteTable.loadNoteIncludingDeleted(kind: "weekly", targetKey: weekStartKey) != nil {
                planningNoteTable.markDeleted(kind: "weekly", targetKey: weekStartKey, nowMs: nowMs)
            }
        } else {
            upsertPlanningNote(kind: "weekly", targetKey: weekStartKey, note: weeklyText, nowMs: nowMs)
        }

        if dailyText.isEmpty {
            if planningNoteTable.loadNoteIncludingDeleted(kind: "daily", targetKey: dateKey) != nil {
                planningNoteTable.markDeleted(kind: "daily", targetKey: dateKey, nowMs: nowMs)
            }
        } else {
            upsertPlanningNote(kind: "daily", targetKey: dateKey, note: dailyText, nowMs: nowMs)
        }
    }

    func loadPlanningReminder(weekStartKey: String, dateKey: String) -> (weeklyNote: String, dailyNote: String) {
        let weekly = planningNoteTable.loadNote(kind: "weekly", targetKey: weekStartKey)?.note ?? ""
        let daily = planningNoteTable.loadNote(kind: "daily", targetKey: dateKey)?.note ?? ""
        return (weekly, daily)
    }

    func listTimeSlots(ownerScope: String = "ME") -> [NJTimeSlotRecord] {
        timeSlotTable.list(ownerScope: ownerScope)
    }

    func upsertTimeSlot(_ row: NJTimeSlotRecord) {
        timeSlotTable.upsert(row)
    }

    func deleteTimeSlot(timeSlotID: String, nowMs: Int64) {
        timeSlotTable.markDeleted(timeSlotID: timeSlotID, nowMs: nowMs)
    }

    func listPersonalGoals(ownerScope: String = "ME") -> [NJPersonalGoalRecord] {
        personalGoalTable.list(ownerScope: ownerScope)
    }

    func upsertPersonalGoal(_ row: NJPersonalGoalRecord) {
        personalGoalTable.upsert(row)
    }

    func deletePersonalGoal(goalID: String, nowMs: Int64) {
        personalGoalTable.markDeleted(goalID: goalID, nowMs: nowMs)
    }
    
    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func sundayWeekStartKey(for date: Date, calendar: Calendar = Calendar.current) -> String {
        var cal = calendar
        cal.firstWeekday = 1
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return dateKey(start)
    }
    
    static func emptyRTF() -> Data {
        let zwsp = String(UnicodeScalar(8203)!)
        let a = NSAttributedString(string: zwsp, attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ])
        return (try? a.data(
            from: NSRange(location: 0, length: a.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }
    
    
}
