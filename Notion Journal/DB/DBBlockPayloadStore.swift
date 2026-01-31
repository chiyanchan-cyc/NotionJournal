import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJLoadedTextBlock {
    let blockID: String
    let instanceID: String
    let orderKey: Double
    let protonJSON: String
    let rtfData: Data
}

extension DBNoteRepository {

    private func jsonString(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj) else { return "{}" }
        let d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    private func normalizeToV1PayloadJSON(_ payload: String) -> String {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payload) {
            return normalized
        }
        return payload
    }

    
    private func mergeRTFBase64IntoPayload(existingPayloadJSON: String, rtfBase64: String) -> String {
        let normalized = normalizeToV1PayloadJSON(existingPayloadJSON)

        if let data = normalized.data(using: .utf8),
           var v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data) {

            _ = try? v1.ensureProton1ExistsWithRTFBase64(rtfBase64)

            if let out = try? JSONEncoder().encode(v1),
               let s = String(data: out, encoding: .utf8) {
                return s
            }
        }

        guard
            let d = existingPayloadJSON.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else {
            return jsonString(["rtf_base64": rtfBase64])
        }

        var m = obj
        m["rtf_base64"] = rtfBase64
        return jsonString(m)
    }

    private func loadPayloadJSON(blockID: String) -> String {
        var payload: String = "{}"
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT payload_json
            FROM nj_block
            WHERE block_id = ? AND deleted = 0
            LIMIT 1;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let cstr = sqlite3_column_text(stmt, 0) {
                        payload = String(cString: cstr)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        return payload
    }

    static func decodeAttributedTextFromRTFBase64(_ base64: String?) -> NSAttributedString {
        guard let base64, let data = Data(base64Encoded: base64) else { return NSAttributedString(string: "") }

        if let rtfd = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) { return rtfd }

        if let rtf = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) { return rtf }

        return NSAttributedString(string: "")
    }

    static func encodeRTFBase64FromAttributedText(_ text: NSAttributedString) -> String {
        let hasAttachments = containsAttachments(text)
        let docType: NSAttributedString.DocumentType = hasAttachments ? .rtfd : .rtf
        let range = NSRange(location: 0, length: text.length)

        guard let data = try? text.data(from: range, documentAttributes: [.documentType: docType]) else {
            return ""
        }

        return data.base64EncodedString()
    }

    static func containsAttachments(_ text: NSAttributedString) -> Bool {
        if text.length == 0 { return false }
        var found = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
    
    func saveSingleProtonBlock(blockID: String, protonJSON: String, tagJSON: String) {
        let now = DBNoteRepository.nowMs()

        print("NJ_SAVE_SINGLE_PROTON_BLOCK block_id=\(blockID) proton_json_bytes=\(protonJSON.utf8.count)")
        print("NJ_SAVE_SINGLE_PROTON_BLOCK proton_json_preview=\(String(protonJSON.prefix(240)))")
        print("NJ_SAVE_SINGLE_PROTON_BLOCK tag_json_bytes=\(tagJSON.utf8.count)")
        print("NJ_SAVE_SINGLE_PROTON_BLOCK tag_json_preview=\(String(tagJSON.prefix(240)))")

        let shouldEnqueue = !DBDirtyQueueTable.isInPullScope()

        var didCommit = false
        var didEnqueue = false

        db.withDB { dbp in
            func isBusy(_ rc: Int32) -> Bool {
                rc == SQLITE_BUSY || rc == SQLITE_LOCKED
            }

            func backoff(_ attempt: Int) {
                let ms = min(800, 25 * (1 << attempt))
                usleep(useconds_t(ms * 1000))
            }

            func exec(_ sql: String) -> Int32 {
                sqlite3_exec(dbp, sql, nil, nil, nil)
            }

            func selectPayloadJSON(_ blockID: String) -> String? {
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, "SELECT payload_json FROM nj_block WHERE block_id = ? LIMIT 1;", -1, &stmt, nil)
                if rc0 != SQLITE_OK { sqlite3_finalize(stmt); return nil }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                let rc1 = sqlite3_step(stmt)
                if rc1 == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) { return String(cString: c) }
                return nil
            }

            func upsertBlock(_ blockID: String, _ payload: String, _ tagJSON: String, _ now: Int64) -> Int32 {
                var stmt: OpaquePointer?
                let sql = """
                INSERT INTO nj_block
                (block_id, block_type, payload_json, domain_tag, tag_json, lineage_id, parent_block_id, created_at_ms, updated_at_ms, deleted, dirty_bl)
                VALUES (?, 'text', ?, '', ?, '', '', ?, ?, 0, 0)
                ON CONFLICT(block_id) DO UPDATE SET
                    payload_json = excluded.payload_json,
                    tag_json = CASE
                        WHEN excluded.tag_json = '' THEN nj_block.tag_json
                        ELSE excluded.tag_json
                    END,
                    updated_at_ms = excluded.updated_at_ms,
                    deleted = 0,
                    dirty_bl = CASE
                        WHEN excluded.tag_json = '' THEN nj_block.dirty_bl
                        WHEN excluded.tag_json = nj_block.tag_json THEN nj_block.dirty_bl
                        ELSE 1
                    END;
                """
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { sqlite3_finalize(stmt); return rc0 }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, tagJSON, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, now)
                sqlite3_bind_int64(stmt, 5, now)

                return sqlite3_step(stmt)
            }

            func upsertDirty(_ entity: String, _ entityID: String, _ op: String, _ updatedAtMs: Int64) -> Int32 {
                var stmt: OpaquePointer?
                let sql = """
                INSERT INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error)
                VALUES(?, ?, ?, ?, 0, '')
                ON CONFLICT(entity, entity_id) DO UPDATE SET
                  op=excluded.op,
                  updated_at_ms=excluded.updated_at_ms,
                  attempts=0,
                  last_error='',
                  ignore=0;
                """
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { sqlite3_finalize(stmt); return rc0 }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, entity, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, entityID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, op, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, updatedAtMs)

                return sqlite3_step(stmt)
            }

            for attempt in 0..<7 {
                let rcBegin = exec("BEGIN IMMEDIATE;")
                if rcBegin != SQLITE_OK {
                    if isBusy(rcBegin) { backoff(attempt); continue }
                    db.dbgErr(dbp, "saveSingleProtonBlock.begin", rcBegin)
                    _ = exec("ROLLBACK;")
                    return
                }

                let oldPayloadInTx = selectPayloadJSON(blockID)
                let normalized = normalizeToV1PayloadJSON(oldPayloadInTx ?? "{}")

                var newPayload = normalized

                if let data = normalized.data(using: .utf8),
                   var v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data) {
                    v1.upsertProton1(protonJSON: protonJSON)
                    if let out = try? JSONEncoder().encode(v1),
                       let s = String(data: out, encoding: .utf8) { newPayload = s }
                } else {
                    var v1 = NJPayloadV1(v: 1, sections: [:])
                    v1.upsertProton1(protonJSON: protonJSON)
                    if let out = try? JSONEncoder().encode(v1),
                       let s = String(data: out, encoding: .utf8) { newPayload = s }
                }

                print("NJ_SAVE_SINGLE_PROTON_BLOCK payload_bytes=\(newPayload.utf8.count)")
                print("NJ_SAVE_SINGLE_PROTON_BLOCK payload_preview=\(String(newPayload.prefix(260)))")

                let rcBlock = upsertBlock(blockID, newPayload, tagJSON, now)
                if rcBlock != SQLITE_DONE {
                    _ = exec("ROLLBACK;")
                    if isBusy(rcBlock) { backoff(attempt); continue }
                    db.dbgErr(dbp, "saveSingleProtonBlock.upsertBlock", rcBlock)
                    return
                }

                if shouldEnqueue {
                    let rcDirty = upsertDirty("block", blockID, "upsert", now)
                    if rcDirty != SQLITE_DONE {
                        _ = exec("ROLLBACK;")
                        if isBusy(rcDirty) { backoff(attempt); continue }
                        db.dbgErr(dbp, "saveSingleProtonBlock.upsertDirty", rcDirty)
                        return
                    }
                    didEnqueue = true
                }

                let rcCommit = exec("COMMIT;")
                if rcCommit != SQLITE_OK {
                    _ = exec("ROLLBACK;")
                    if isBusy(rcCommit) { backoff(attempt); continue }
                    db.dbgErr(dbp, "saveSingleProtonBlock.commit", rcCommit)
                    return
                }

                didCommit = true
                print("NJ_SAVE_SINGLE_PROTON_BLOCK TX_DONE enqueued=\(didEnqueue ? 1 : 0)")
                break
            }

            if !didCommit {
                let msg = String(cString: sqlite3_errmsg(dbp))
                print("NJ_SAVE_SINGLE_PROTON_BLOCK GIVE_UP msg=\(msg)")
            }
        }

        if didCommit && didEnqueue {
            NotificationCenter.default.post(name: .njDirtyEnqueued, object: nil)
        }
    }

    func updateNoteBlockOrderKey(instanceID: String, orderKey: Double) {
        if instanceID.isEmpty { return }
        let now = Self.nowMs()

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_note_block
            SET order_key = ?, updated_at_ms = ?, deleted = 0
            WHERE instance_id = ?;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, orderKey)
                sqlite3_bind_int64(stmt, 2, now)
                sqlite3_bind_text(stmt, 3, instanceID, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: now)
    }


    func loadAllTextBlocksRTFWithPlacement(noteID: String) -> [NJLoadedTextBlock] {
        var out: [NJLoadedTextBlock] = []

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT nb.block_id, nb.instance_id, nb.order_key, b.payload_json
                    FROM nj_note_block nb
                    JOIN nj_block b ON b.block_id = nb.block_id
                    WHERE nb.note_id = ? AND nb.deleted = 0 AND b.deleted = 0
                    ORDER BY nb.order_key ASC;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let blockID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let instanceID = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                let orderKey = sqlite3_column_double(stmt, 2)
                let payload = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""

                guard !blockID.isEmpty else { continue }

                let (protonJSON, rtfBase64) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payload)
                let rtfData = Data(base64Encoded: rtfBase64) ?? Self.emptyRTF()

                out.append(
                    NJLoadedTextBlock(
                        blockID: blockID,
                        instanceID: instanceID,
                        orderKey: orderKey,
                        protonJSON: protonJSON,
                        rtfData: rtfData
                    )
                )
            }
        }
        return out
    }
    
    private func extractProtonJSONAndRTFBase64(fromPayloadJSON payload: String) -> (String, String) {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payload),
           let data = normalized.data(using: .utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
           let p = try? v1.proton1Data() {
            return (p.proton_json, p.rtf_base64)
        }

        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ("", "")
        }

        let protonJSON = obj["proton_json"] as? String ?? ""
        let rtfBase64 = obj["rtf_base64"] as? String ?? ""
        return (protonJSON, rtfBase64)
    }
    func nextAppendOrderKey(noteID: String) -> Double {
        var out: Double = 1000

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT COALESCE(MAX(nb.order_key), 0)
            FROM nj_note_block nb
            JOIN nj_block b ON b.block_id = nb.block_id
            WHERE nb.note_id = ? AND nb.deleted = 0
              AND b.deleted = 0;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let m = sqlite3_column_double(stmt, 0)
                    out = m + 1000
                    if out < 1000 { out = 1000 }
                }
            }
            sqlite3_finalize(stmt)
        }

        return out
    }

    func attachExistingBlockToNote(noteID: String, blockID: String, orderKey: Double) -> String {
        let now = Self.nowMs()
        let instanceID = UUID().uuidString

        db.withDB { dbp in
            _ = sqlite3_exec(dbp, "BEGIN IMMEDIATE;", nil, nil, nil)
            defer { _ = sqlite3_exec(dbp, "COMMIT;", nil, nil, nil) }

            var stmt: OpaquePointer?
            let insertNB = """
            INSERT INTO nj_note_block
            (block_id, created_at_ms, deleted, instance_id, note_id, order_key, updated_at_ms)
            VALUES (?, ?, 0, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(dbp, insertNB, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, now)
                sqlite3_bind_text(stmt, 3, instanceID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 5, orderKey)
                sqlite3_bind_int64(stmt, 6, now)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: now)
        return instanceID
    }

    private func extractRTFBase64(fromPayloadJSON payload: String) -> String? {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payload),
           let data = normalized.data(using: .utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
           let p = try? v1.proton1Data() {
            return p.rtf_base64
        }

        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return obj["rtf_base64"] as? String
    }
}
