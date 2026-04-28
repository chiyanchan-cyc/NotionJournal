import Foundation

final class DBCloudBridge {
    let noteTable: DBNoteTable
    let blockTable: DBBlockTable
    let noteBlockTable: DBNoteBlockTable
    let attachmentTable: DBAttachmentTable
    let goalTable: DBGoalTable
    let calendarTable: DBCalendarTable
    let plannedExerciseTable: DBPlannedExerciseTable
    let healthSampleCloudTable: DBHealthSampleCloudTable
    let planningNoteTable: DBPlanningNoteTable
    let financeMacroEventTable: DBFinanceMacroEventTable
    let financeDailyBriefTable: DBFinanceDailyBriefTable
    let financeResearchSessionTable: DBFinanceResearchSessionTable
    let financeResearchMessageTable: DBFinanceResearchMessageTable
    let financeResearchTaskTable: DBFinanceResearchTaskTable
    let financeFindingTable: DBFinanceFindingTable
    let financeJournalLinkTable: DBFinanceJournalLinkTable
    let financeSourceItemTable: DBFinanceSourceItemTable
    let financeTransactionTable: DBFinanceTransactionTable
    let agentHeartbeatRunTable: DBAgentHeartbeatRunTable
    let agentBackfillTaskTable: DBAgentBackfillTaskTable
    let timeSlotTable: DBTimeSlotTable
    let personalGoalTable: DBPersonalGoalTable
    let renewalItemTable: DBRenewalItemTable
    let cardTable: DBCardTable

    init(
        noteTable: DBNoteTable,
        blockTable: DBBlockTable,
        noteBlockTable: DBNoteBlockTable,
        attachmentTable: DBAttachmentTable,
        goalTable: DBGoalTable,
        calendarTable: DBCalendarTable,
        plannedExerciseTable: DBPlannedExerciseTable,
        healthSampleCloudTable: DBHealthSampleCloudTable,
        planningNoteTable: DBPlanningNoteTable,
        financeMacroEventTable: DBFinanceMacroEventTable,
        financeDailyBriefTable: DBFinanceDailyBriefTable,
        financeResearchSessionTable: DBFinanceResearchSessionTable,
        financeResearchMessageTable: DBFinanceResearchMessageTable,
        financeResearchTaskTable: DBFinanceResearchTaskTable,
        financeFindingTable: DBFinanceFindingTable,
        financeJournalLinkTable: DBFinanceJournalLinkTable,
        financeSourceItemTable: DBFinanceSourceItemTable,
        financeTransactionTable: DBFinanceTransactionTable,
        agentHeartbeatRunTable: DBAgentHeartbeatRunTable,
        agentBackfillTaskTable: DBAgentBackfillTaskTable,
        timeSlotTable: DBTimeSlotTable,
        personalGoalTable: DBPersonalGoalTable,
        renewalItemTable: DBRenewalItemTable,
        cardTable: DBCardTable
    ) {
        self.noteTable = noteTable
        self.blockTable = blockTable
        self.noteBlockTable = noteBlockTable
        self.attachmentTable = attachmentTable
        self.goalTable = goalTable
        self.calendarTable = calendarTable
        self.plannedExerciseTable = plannedExerciseTable
        self.healthSampleCloudTable = healthSampleCloudTable
        self.planningNoteTable = planningNoteTable
        self.financeMacroEventTable = financeMacroEventTable
        self.financeDailyBriefTable = financeDailyBriefTable
        self.financeResearchSessionTable = financeResearchSessionTable
        self.financeResearchMessageTable = financeResearchMessageTable
        self.financeResearchTaskTable = financeResearchTaskTable
        self.financeFindingTable = financeFindingTable
        self.financeJournalLinkTable = financeJournalLinkTable
        self.financeSourceItemTable = financeSourceItemTable
        self.financeTransactionTable = financeTransactionTable
        self.agentHeartbeatRunTable = agentHeartbeatRunTable
        self.agentBackfillTaskTable = agentBackfillTaskTable
        self.timeSlotTable = timeSlotTable
        self.personalGoalTable = personalGoalTable
        self.renewalItemTable = renewalItemTable
        self.cardTable = cardTable
    }

    func loadRecord(entity: String, id: String) -> [String: Any]? {
        switch entity {
        case "note":
            return loadNJNote(noteID: id)
        case "block":
            return blockTable.loadNJBlock(blockID: id)
        case "table":
            return NJTableStore.shared.loadCloudFields(tableID: id)
        case "note_block":
            return noteBlockTable.loadNJNoteBlock(instanceID: id)
        case "attachment":
            return loadNJAttachment(attachmentID: id)
        case "goal":
            return goalTable.loadNJGoal(goalID: id)
        case "calendar_item":
            return loadNJCalendarItem(dateKey: id)
        case "planned_exercise":
            return plannedExerciseTable.loadPlan(planID: id)
        case "health_sample":
            return healthSampleCloudTable.loadHealthSample(sampleID: id)
        case "planning_note":
            return planningNoteTable.loadPlanningNoteFields(planningKey: id)
        case "finance_macro_event":
            return financeMacroEventTable.loadFields(eventID: id)
        case "finance_daily_brief":
            return financeDailyBriefTable.loadFields(dateKey: id)
        case "finance_research_session":
            return financeResearchSessionTable.loadFields(sessionID: id)
        case "finance_research_message":
            return financeResearchMessageTable.loadFields(messageID: id)
        case "finance_research_task":
            return financeResearchTaskTable.loadFields(taskID: id)
        case "finance_finding":
            return financeFindingTable.loadFields(findingID: id)
        case "finance_journal_link":
            return financeJournalLinkTable.loadFields(linkID: id)
        case "finance_source_item":
            return financeSourceItemTable.loadFields(sourceItemID: id)
        case "finance_transaction":
            return financeTransactionTable.loadFields(transactionID: id)
        case "agent_heartbeat_run":
            return agentHeartbeatRunTable.loadFields(runID: id)
        case "agent_backfill_task":
            return agentBackfillTaskTable.loadFields(taskID: id)
        case "time_slot":
            return timeSlotTable.loadFields(timeSlotID: id)
        case "personal_goal":
            return personalGoalTable.loadFields(goalID: id)
        case "renewal_item":
            return renewalItemTable.loadFields(renewalItemID: id)
        case "card_schema":
            return cardTable.loadCardSchema(schemaKey: id)
        case "card":
            return cardTable.loadCard(cardID: id)
        default:
            return nil
        }
    }

    private func int64Any(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    func applyRemoteUpsert(entity: String, fields: [String: Any]) {
        switch entity {
        case "note":
            applyNJNote(fields: fields)
        case "block":
            blockTable.applyNJBlock(fields)
        case "table":
            NJTableStore.shared.applyCloudFields(fields)
        case "note_block":
            noteBlockTable.applyNJNoteBlock(fields)
        case "attachment":
            attachmentTable.applyNJAttachment(fields)
        case "goal":
            goalTable.applyNJGoal(fields)
        case "calendar_item":
            applyNJCalendarItem(fields: fields)
        case "planned_exercise":
            plannedExerciseTable.applyRemote(fields)
        case "health_sample":
            healthSampleCloudTable.applyRemote(fields)
        case "planning_note":
            planningNoteTable.applyRemote(fields)
        case "finance_macro_event":
            financeMacroEventTable.applyRemote(fields)
        case "finance_daily_brief":
            financeDailyBriefTable.applyRemote(fields)
        case "finance_research_session":
            financeResearchSessionTable.applyRemote(fields)
        case "finance_research_message":
            financeResearchMessageTable.applyRemote(fields)
        case "finance_research_task":
            financeResearchTaskTable.applyRemote(fields)
        case "finance_finding":
            financeFindingTable.applyRemote(fields)
        case "finance_journal_link":
            financeJournalLinkTable.applyRemote(fields)
        case "finance_source_item":
            financeSourceItemTable.applyRemote(fields)
        case "finance_transaction":
            financeTransactionTable.applyRemote(fields)
        case "agent_heartbeat_run":
            agentHeartbeatRunTable.applyRemote(fields)
        case "agent_backfill_task":
            agentBackfillTaskTable.applyRemote(fields)
        case "time_slot":
            timeSlotTable.applyRemote(fields)
        case "personal_goal":
            personalGoalTable.applyRemote(fields)
        case "renewal_item":
            renewalItemTable.applyRemote(fields)
        case "card_schema":
            cardTable.applyRemoteCardSchema(fields)
        case "card":
            cardTable.applyRemoteCard(fields)
        default:
            break
        }
    }

    private func loadNJNote(noteID: String) -> [String: Any]? {
        guard let n = noteTable.getNote(NJNoteID(noteID)) else { return nil }
        return [
            "note_id": n.id.raw,
            "created_at_ms": n.createdAtMs,
            "updated_at_ms": n.updatedAtMs,
            "notebook": n.notebook,
            "tab_domain": n.tabDomain,
            "title": n.title,
            "note_type": n.noteTypeRaw,
            "dominance_mode": n.dominanceModeRaw,
            "is_checklist": n.isChecklist,
            "card_id": n.cardID,
            "card_category": n.cardCategory,
            "card_area": n.cardArea,
            "card_context": n.cardContext,
            "card_status": n.cardStatus,
            "card_priority": n.cardPriority,
            "pinned": n.pinned,
            "favorited": n.favorited,
            "deleted": n.deleted
        ]
    }

    private func applyNJNote(fields: [String: Any]) {
        let noteID = (fields["note_id"] as? String) ?? ""
        if noteID.isEmpty { return }

        let createdAt = int64Any(fields["created_at_ms"])
        let updatedAt = int64Any(fields["updated_at_ms"])
        let notebook = (fields["notebook"] as? String) ?? ""
        let tabDomain = (fields["tab_domain"] as? String) ?? ""
        let title = (fields["title"] as? String) ?? ""
        let incomingNoteTypeRaw = (fields["note_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dominanceModeRaw = (fields["dominance_mode"] as? String) ?? NJNoteDominanceMode.block.rawValue
        let isChecklist = int64Any(fields["is_checklist"])
        let cardID = (fields["card_id"] as? String) ?? ""
        let cardCategory = (fields["card_category"] as? String) ?? ""
        let cardArea = (fields["card_area"] as? String) ?? ""
        let cardContext = (fields["card_context"] as? String) ?? ""
        let cardStatus = (fields["card_status"] as? String) ?? ""
        let cardPriority = (fields["card_priority"] as? String) ?? ""
        let pinned = int64Any(fields["pinned"])
        let favorited = int64Any(fields["favorited"])
        let deleted = int64Any(fields["deleted"])

        let existing = noteTable.getNote(NJNoteID(noteID))
        if let existing {
            if existing.updatedAtMs > updatedAt, updatedAt > 0 {
                return
            }
            if existing.updatedAtMs == updatedAt,
               existing.deleted > deleted {
                return
            }
        }

        let inferredCardType: Bool = {
            if !cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if !cardCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if !cardArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if !cardContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if !cardStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if !cardPriority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            return false
        }()

        let noteTypeRaw: String = {
            if !incomingNoteTypeRaw.isEmpty {
                return incomingNoteTypeRaw
            }
            if let existing, existing.noteType == .card {
                return NJNoteType.card.rawValue
            }
            if inferredCardType {
                return NJNoteType.card.rawValue
            }
            return NJNoteType.note.rawValue
        }()

        let keepRTF = existing?.rtfData ?? noteTable.emptyRTF()

        let note = NJNote(
            id: NJNoteID(noteID),
            createdAtMs: createdAt > 0 ? createdAt : (existing?.createdAtMs ?? 0),
            updatedAtMs: updatedAt,
            notebook: notebook,
            tabDomain: tabDomain,
            title: title,
            rtfData: keepRTF,
            deleted: deleted,
            pinned: pinned,
            favorited: favorited,
            noteTypeRaw: noteTypeRaw,
            dominanceModeRaw: dominanceModeRaw,
            isChecklist: isChecklist,
            cardID: cardID,
            cardCategory: cardCategory,
            cardArea: cardArea,
            cardContext: cardContext,
            cardStatus: cardStatus,
            cardPriority: cardPriority
        )
        noteTable.upsertNote(note)
    }

    private func loadNJAttachment(attachmentID: String) -> [String: Any]? {
        guard let a = attachmentTable.loadNJAttachment(attachmentID: attachmentID) else { return nil }
        let fm = FileManager.default
        let thumbExists = !a.thumbPath.isEmpty && fm.fileExists(atPath: a.thumbPath)
        var out: [String: Any] = [
            "attachment_id": a.attachmentID,
            "block_id": a.blockID,
            "kind": a.kind.rawValue,
            "thumb_path": thumbExists ? a.thumbPath : "",
            "full_photo_ref": a.fullPhotoRef,
            "display_w": a.displayW,
            "display_h": a.displayH,
            "created_at_ms": a.createdAtMs,
            "updated_at_ms": a.updatedAtMs,
            "deleted": a.deleted
        ]
        if let n = a.noteID { out["note_id"] = n }
        if thumbExists {
            out["thumb_asset"] = URL(fileURLWithPath: a.thumbPath)
        }
        return out
    }

    private func loadNJCalendarItem(dateKey: String) -> [String: Any]? {
        guard let item = calendarTable.loadItemIncludingDeleted(dateKey: dateKey) else { return nil }
        return [
            "date_key": item.dateKey,
            "title": item.title,
            "photo_attachment_id": item.photoAttachmentID,
            "photo_cloud_id": item.photoCloudID,
            "created_at_ms": item.createdAtMs,
            "updated_at_ms": item.updatedAtMs,
            "deleted": item.deleted
        ]
    }

    private func applyNJCalendarItem(fields: [String: Any]) {
        let key = (fields["date_key"] as? String) ?? (fields["dateKey"] as? String) ?? ""
        if key.isEmpty { return }

        let title = (fields["title"] as? String) ?? ""
        let photoAttachmentID = (fields["photo_attachment_id"] as? String) ?? ""
        let photoCloudID = (fields["photo_cloud_id"] as? String) ?? ""
        let createdAt = (fields["created_at_ms"] as? Int64) ?? 0
        let updatedAt = (fields["updated_at_ms"] as? Int64) ?? 0
        let deleted = (fields["deleted"] as? Int64) ?? 0

        let existing = calendarTable.loadItemIncludingDeleted(dateKey: key)
        if let existing, existing.updatedAtMs > updatedAt, updatedAt > 0 {
            return
        }

        let preservedLocalID: String = {
            guard let existing, existing.photoAttachmentID == photoAttachmentID else { return "" }
            return existing.photoLocalID
        }()

        let thumbPath: String = {
            guard !photoAttachmentID.isEmpty else { return "" }

            if let existing,
               existing.photoAttachmentID == photoAttachmentID,
               !existing.photoThumbPath.isEmpty,
               FileManager.default.fileExists(atPath: existing.photoThumbPath) {
                return existing.photoThumbPath
            }

            if let attachment = attachmentTable.loadNJAttachment(attachmentID: photoAttachmentID),
               !attachment.thumbPath.isEmpty,
               FileManager.default.fileExists(atPath: attachment.thumbPath) {
                return attachment.thumbPath
            }

            guard let url = NJAttachmentCache.fileURL(for: photoAttachmentID),
                  FileManager.default.fileExists(atPath: url.path)
            else { return "" }
            return url.path
        }()

        let item = NJCalendarItem(
            dateKey: key,
            title: title,
            photoAttachmentID: photoAttachmentID,
            photoLocalID: preservedLocalID,
            photoCloudID: photoCloudID,
            photoThumbPath: thumbPath,
            createdAtMs: createdAt > 0 ? createdAt : (existing?.createdAtMs ?? 0),
            updatedAtMs: updatedAt,
            deleted: Int(deleted)
        )
        calendarTable.upsertItem(item)
    }
}
