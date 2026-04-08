import Foundation

final class DBCloudBridge {
    let noteTable: DBNoteTable
    let blockTable: DBBlockTable
    let noteBlockTable: DBNoteBlockTable
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

    init(
        noteTable: DBNoteTable,
        blockTable: DBBlockTable,
        noteBlockTable: DBNoteBlockTable,
        attachmentTable: DBAttachmentTable,
        goalTable: DBGoalTable,
        calendarTable: DBCalendarTable,
        plannedExerciseTable: DBPlannedExerciseTable,
        planningNoteTable: DBPlanningNoteTable,
        financeMacroEventTable: DBFinanceMacroEventTable,
        financeDailyBriefTable: DBFinanceDailyBriefTable,
        financeResearchSessionTable: DBFinanceResearchSessionTable,
        financeResearchMessageTable: DBFinanceResearchMessageTable,
        financeResearchTaskTable: DBFinanceResearchTaskTable,
        financeFindingTable: DBFinanceFindingTable,
        financeJournalLinkTable: DBFinanceJournalLinkTable,
        financeSourceItemTable: DBFinanceSourceItemTable,
        timeSlotTable: DBTimeSlotTable,
        personalGoalTable: DBPersonalGoalTable
    ) {
        self.noteTable = noteTable
        self.blockTable = blockTable
        self.noteBlockTable = noteBlockTable
        self.attachmentTable = attachmentTable
        self.goalTable = goalTable
        self.calendarTable = calendarTable
        self.plannedExerciseTable = plannedExerciseTable
        self.planningNoteTable = planningNoteTable
        self.financeMacroEventTable = financeMacroEventTable
        self.financeDailyBriefTable = financeDailyBriefTable
        self.financeResearchSessionTable = financeResearchSessionTable
        self.financeResearchMessageTable = financeResearchMessageTable
        self.financeResearchTaskTable = financeResearchTaskTable
        self.financeFindingTable = financeFindingTable
        self.financeJournalLinkTable = financeJournalLinkTable
        self.financeSourceItemTable = financeSourceItemTable
        self.timeSlotTable = timeSlotTable
        self.personalGoalTable = personalGoalTable
    }

    func loadRecord(entity: String, id: String) -> [String: Any]? {
        switch entity {
        case "note":
            return loadNJNote(noteID: id)
        case "block":
            return blockTable.loadNJBlock(blockID: id)
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
        case "time_slot":
            return timeSlotTable.loadFields(timeSlotID: id)
        case "personal_goal":
            return personalGoalTable.loadFields(goalID: id)
        default:
            return nil
        }
    }

    func applyRemoteUpsert(entity: String, fields: [String: Any]) {
        switch entity {
        case "note":
            applyNJNote(fields: fields)
        case "block":
            blockTable.applyNJBlock(fields)
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
        case "time_slot":
            timeSlotTable.applyRemote(fields)
        case "personal_goal":
            personalGoalTable.applyRemote(fields)
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
            "pinned": n.pinned,
            "deleted": n.deleted
        ]
    }

    private func applyNJNote(fields: [String: Any]) {
        let noteID = (fields["note_id"] as? String) ?? ""
        if noteID.isEmpty { return }

        let createdAt = (fields["created_at_ms"] as? Int64) ?? 0
        let updatedAt = (fields["updated_at_ms"] as? Int64) ?? 0
        let notebook = (fields["notebook"] as? String) ?? ""
        let tabDomain = (fields["tab_domain"] as? String) ?? ""
        let title = (fields["title"] as? String) ?? ""
        let pinned = (fields["pinned"] as? Int64) ?? 0
        let deleted = (fields["deleted"] as? Int64) ?? 0

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
            pinned: pinned
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
