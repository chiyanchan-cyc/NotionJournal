import Foundation

final class DBCloudBridge {
    let noteTable: DBNoteTable
    let blockTable: DBBlockTable
    let noteBlockTable: DBNoteBlockTable
    let goalTable: DBGoalTable

    init(
        noteTable: DBNoteTable,
        blockTable: DBBlockTable,
        noteBlockTable: DBNoteBlockTable,
        goalTable: DBGoalTable
    ) {
        self.noteTable = noteTable
        self.blockTable = blockTable
        self.noteBlockTable = noteBlockTable
        self.goalTable = goalTable
    }

    func loadRecord(entity: String, id: String) -> [String: Any]? {
        switch entity {
        case "note":
            return loadNJNote(noteID: id)
        case "block":
            return blockTable.loadNJBlock(blockID: id)
        case "note_block":
            return noteBlockTable.loadNJNoteBlock(instanceID: id)
        case "goal":
            return goalTable.loadNJGoal(goalID: id)
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
        case "goal":
            goalTable.applyNJGoal(fields)
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
        let deleted = (fields["deleted"] as? Int64) ?? 0

        let existing = noteTable.getNote(NJNoteID(noteID))
        if let existing, existing.updatedAtMs > updatedAt, updatedAt > 0 {
            return
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
            deleted: deleted
        )
        noteTable.upsertNote(note)
    }
}
