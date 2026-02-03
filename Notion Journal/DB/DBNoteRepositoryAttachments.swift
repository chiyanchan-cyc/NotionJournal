import Foundation

@MainActor
extension DBNoteRepository {

    func attachmentByID(_ attachmentID: String) -> NJAttachmentRecord? {
        attachmentTable.loadNJAttachment(attachmentID: attachmentID)
    }

    func listAttachments(blockID: String) -> [NJAttachmentRecord] {
        attachmentTable.listAttachments(blockID: blockID)
    }

    func upsertAttachment(_ attachment: NJAttachmentRecord, nowMs: Int64) {
        attachmentTable.upsertAttachment(attachment, nowMs: nowMs)
    }

    func markAttachmentDeleted(attachmentID: String, nowMs: Int64) {
        attachmentTable.markDeleted(attachmentID: attachmentID, nowMs: nowMs)
    }

    func clearAttachmentThumbPath(attachmentID: String, nowMs: Int64) {
        attachmentTable.clearThumbPath(attachmentID: attachmentID, nowMs: nowMs)
    }
}

