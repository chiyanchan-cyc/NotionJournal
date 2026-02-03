import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBAttachmentTable {
    let db: SQLiteDB
    let enqueueDirtyFn: (String, String, String, Int64) -> Void

    init(db: SQLiteDB, enqueueDirty: @escaping (String, String, String, Int64) -> Void) {
        self.db = db
        self.enqueueDirtyFn = enqueueDirty
    }

    func loadNJAttachment(attachmentID: String) -> NJAttachmentRecord? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT attachment_id, block_id, note_id, kind, thumb_path, full_photo_ref,
                   display_w, display_h, created_at_ms, updated_at_ms, deleted
            FROM nj_attachment
            WHERE attachment_id = ? LIMIT 1;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, attachmentID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let id = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let blockID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let noteID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) }
            let kindRaw = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
            let thumbPath = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
            let fullPhotoRef = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""
            let displayW = Int(sqlite3_column_int64(stmt, 6))
            let displayH = Int(sqlite3_column_int64(stmt, 7))
            let createdAtMs = sqlite3_column_int64(stmt, 8)
            let updatedAtMs = sqlite3_column_int64(stmt, 9)
            let deleted = Int(sqlite3_column_int64(stmt, 10))

            let kind = NJAttachmentKind(rawValue: kindRaw) ?? .photo

            return NJAttachmentRecord(
                attachmentID: id,
                blockID: blockID,
                noteID: noteID,
                kind: kind,
                thumbPath: thumbPath,
                fullPhotoRef: fullPhotoRef,
                displayW: displayW,
                displayH: displayH,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                deleted: deleted
            )
        }
    }

    func listAttachments(blockID: String) -> [NJAttachmentRecord] {
        var out: [NJAttachmentRecord] = []
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT attachment_id, block_id, note_id, kind, thumb_path, full_photo_ref,
                   display_w, display_h, created_at_ms, updated_at_ms, deleted
            FROM nj_attachment
            WHERE block_id = ? AND deleted = 0;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let blockID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                let noteID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) }
                let kindRaw = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
                let thumbPath = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                let fullPhotoRef = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""
                let displayW = Int(sqlite3_column_int64(stmt, 6))
                let displayH = Int(sqlite3_column_int64(stmt, 7))
                let createdAtMs = sqlite3_column_int64(stmt, 8)
                let updatedAtMs = sqlite3_column_int64(stmt, 9)
                let deleted = Int(sqlite3_column_int64(stmt, 10))
                let kind = NJAttachmentKind(rawValue: kindRaw) ?? .photo

                out.append(NJAttachmentRecord(
                    attachmentID: id,
                    blockID: blockID,
                    noteID: noteID,
                    kind: kind,
                    thumbPath: thumbPath,
                    fullPhotoRef: fullPhotoRef,
                    displayW: displayW,
                    displayH: displayH,
                    createdAtMs: createdAtMs,
                    updatedAtMs: updatedAtMs,
                    deleted: deleted
                ))
            }
        }
        return out
    }

    func upsertAttachment(_ a: NJAttachmentRecord, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_attachment(
              attachment_id,
              block_id,
              note_id,
              kind,
              thumb_path,
              full_photo_ref,
              display_w,
              display_h,
              created_at_ms,
              updated_at_ms,
              deleted,
              dirty_bl
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            ON CONFLICT(attachment_id) DO UPDATE SET
              block_id=excluded.block_id,
              note_id=excluded.note_id,
              kind=excluded.kind,
              thumb_path=excluded.thumb_path,
              full_photo_ref=excluded.full_photo_ref,
              display_w=excluded.display_w,
              display_h=excluded.display_h,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted,
              dirty_bl=1;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, a.attachmentID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, a.blockID, -1, SQLITE_TRANSIENT)
            if let noteID = a.noteID {
                sqlite3_bind_text(stmt, 3, noteID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, a.kind.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, a.thumbPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, a.fullPhotoRef, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, Int64(a.displayW))
            sqlite3_bind_int64(stmt, 8, Int64(a.displayH))
            sqlite3_bind_int64(stmt, 9, a.createdAtMs == 0 ? nowMs : a.createdAtMs)
            sqlite3_bind_int64(stmt, 10, nowMs)
            sqlite3_bind_int64(stmt, 11, Int64(a.deleted))

            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE { db.dbgErr(dbp, "upsertAttachment.step", rc) }
        }

        enqueueDirtyFn("attachment", a.attachmentID, "upsert", nowMs)
    }

    func markDeleted(attachmentID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_attachment
            SET deleted=1, updated_at_ms=?, dirty_bl=1
            WHERE attachment_id=?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, attachmentID, -1, SQLITE_TRANSIENT)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE { db.dbgErr(dbp, "markDeletedAttachment.step", rc) }
        }
        enqueueDirtyFn("attachment", attachmentID, "delete", nowMs)
    }

    func clearThumbPath(attachmentID: String, nowMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_attachment
            SET thumb_path='', updated_at_ms=?, dirty_bl=1
            WHERE attachment_id=?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, nowMs)
            sqlite3_bind_text(stmt, 2, attachmentID, -1, SQLITE_TRANSIENT)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE { db.dbgErr(dbp, "clearThumbPath.step", rc) }
        }
        enqueueDirtyFn("attachment", attachmentID, "upsert", nowMs)
    }

    func applyNJAttachment(_ f: [String: Any]) {
        let attachmentID = (f["attachment_id"] as? String) ?? (f["attachmentID"] as? String) ?? ""
        if attachmentID.isEmpty { return }

        let blockID = (f["block_id"] as? String) ?? ""
        let noteID = (f["note_id"] as? String)
        let kindRaw = (f["kind"] as? String) ?? "photo"
        let kind = NJAttachmentKind(rawValue: kindRaw) ?? .photo

        let thumbPath: String = {
            if let u = f["thumb_asset"] as? URL { return u.path }
            if let s = f["thumb_asset"] as? String, s.hasPrefix("file://"), let u = URL(string: s) { return u.path }
            if let s = f["thumb_path"] as? String { return s }
            return ""
        }()

        let fullPhotoRef = (f["full_photo_ref"] as? String) ?? ""
        let displayW = (f["display_w"] as? Int) ?? Int((f["display_w"] as? Int64) ?? 400)
        let displayH = (f["display_h"] as? Int) ?? Int((f["display_h"] as? Int64) ?? 400)
        let createdAtMs = (f["created_at_ms"] as? Int64) ?? 0
        let updatedAtMs = (f["updated_at_ms"] as? Int64) ?? 0
        let deleted = (f["deleted"] as? Int64).map { Int($0) } ?? 0

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_attachment(
              attachment_id,
              block_id,
              note_id,
              kind,
              thumb_path,
              full_photo_ref,
              display_w,
              display_h,
              created_at_ms,
              updated_at_ms,
              deleted,
              dirty_bl
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(attachment_id) DO UPDATE SET
              block_id=excluded.block_id,
              note_id=excluded.note_id,
              kind=excluded.kind,
              thumb_path=excluded.thumb_path,
              full_photo_ref=excluded.full_photo_ref,
              display_w=excluded.display_w,
              display_h=excluded.display_h,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted,
              dirty_bl=0;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, attachmentID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, blockID, -1, SQLITE_TRANSIENT)
            if let noteID {
                sqlite3_bind_text(stmt, 3, noteID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, kind.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, thumbPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, fullPhotoRef, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 7, Int64(displayW))
            sqlite3_bind_int64(stmt, 8, Int64(displayH))
            sqlite3_bind_int64(stmt, 9, createdAtMs)
            sqlite3_bind_int64(stmt, 10, updatedAtMs)
            sqlite3_bind_int64(stmt, 11, Int64(deleted))

            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE { db.dbgErr(dbp, "applyNJAttachment.step", rc) }
        }
    }
}
