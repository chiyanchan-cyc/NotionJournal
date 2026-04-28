import Foundation
import UIKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJLoadedTextBlock {
    let blockID: String
    let instanceID: String
    let orderKey: Double
    let isChecked: Bool
    let cardRowID: String
    let cardStatus: String
    let cardPriority: String
    let cardCategory: String
    let cardArea: String
    let cardContext: String
    let cardTitle: String
    let payloadJSON: String
    let protonJSON: String
    let rtfData: Data
}

extension DBNoteRepository {

    private func normalizePersistableProtonJSON(_ protonJSON: String) -> String {
        NJPayloadV1.normalizeProtonDocumentV2(protonJSON)
    }

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

            let existingProtonJSON = ((try? v1.proton1Data())?.proton_json ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existingProtonJSON.isEmpty {
                v1.upsertProton1(protonJSON: NJPayloadV1.protonDocumentV2FromRTFBase64(rtfBase64))
            }

            if let out = try? JSONEncoder().encode(v1),
               let s = String(data: out, encoding: .utf8) {
                return s
            }
        }

        guard
            let d = existingPayloadJSON.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else {
            var v1 = NJPayloadV1(v: 1, sections: [:])
            v1.upsertProton1(protonJSON: NJPayloadV1.protonDocumentV2FromRTFBase64(rtfBase64))
            guard let data = try? JSONEncoder().encode(v1),
                  let text = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return text
        }

        var m = obj
        if let protonJSON = m["proton_json"] as? String, !protonJSON.isEmpty {
            m.removeValue(forKey: "rtf_base64")
        } else {
            m["proton_json"] = NJPayloadV1.protonDocumentV2FromRTFBase64(rtfBase64)
            m.removeValue(forKey: "rtf_base64")
        }
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

    private func rtfBase64HasRenderableContent(_ rtfBase64: String) -> Bool {
        guard let data = Data(base64Encoded: rtfBase64) else { return false }
        let decoded =
            (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)) ??
            (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))
        guard let decoded else { return false }
        if Self.containsAttachments(decoded) { return true }
        let visible = decoded.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !visible.isEmpty
    }

    private func protonJSONHasRenderableContent(_ protonJSON: String) -> Bool {
        let trimmed = protonJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        guard let rootAny = try? JSONSerialization.jsonObject(with: data) else { return false }

        func nodeHasContent(_ node: [String: Any]) -> Bool {
            let type = (node["type"] as? String) ?? ""
            if type == "rich" {
                return rtfBase64HasRenderableContent((node["rtf_base64"] as? String) ?? "")
            }
            if type == "list" {
                let items = (node["items"] as? [Any]) ?? []
                return items.contains { item in
                    guard let item = item as? [String: Any] else { return false }
                    return rtfBase64HasRenderableContent((item["rtf_base64"] as? String) ?? "")
                }
            }
            if type == "attachment" { return true }
            if let text = node["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            let children = (node["contents"] as? [Any]) ?? []
            return children.contains { child in
                guard let child = child as? [String: Any] else { return false }
                return nodeHasContent(child)
            }
        }

        if let root = rootAny as? [String: Any],
           let doc = root["doc"] as? [Any] {
            return doc.contains { item in
                guard let node = item as? [String: Any] else { return false }
                return nodeHasContent(node)
            }
        }

        if let nodes = rootAny as? [Any] {
            return nodes.contains { item in
                guard let node = item as? [String: Any] else { return false }
                return nodeHasContent(node)
            }
        }

        return false
    }

    private func payloadJSONHasRenderableContent(_ payloadJSON: String) -> Bool {
        let (protonJSON, rtfBase64) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payloadJSON)
        if protonJSONHasRenderableContent(protonJSON) { return true }
        return rtfBase64HasRenderableContent(rtfBase64)
    }
    
    func saveSingleProtonBlock(blockID: String, protonJSON: String, tagJSON: String, goalID: String? = nil) {
        let now = DBNoteRepository.nowMs()
        let normalizedProtonJSON = normalizePersistableProtonJSON(protonJSON)

        print("NJ_SAVE_SINGLE_PROTON_BLOCK block_id=\(blockID) proton_json_bytes=\(normalizedProtonJSON.utf8.count)")
        print("NJ_SAVE_SINGLE_PROTON_BLOCK proton_json_preview=\(String(normalizedProtonJSON.prefix(240)))")

        let shouldEnqueue = !DBDirtyQueueTable.isInPullScope()
        print("NJ_SAVE_SINGLE_PROTON_BLOCK enqueue_allowed=\(shouldEnqueue ? 1 : 0)")

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

            func selectTagJSON(_ blockID: String) -> String? {
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, "SELECT tag_json FROM nj_block WHERE block_id = ? LIMIT 1;", -1, &stmt, nil)
                if rc0 != SQLITE_OK { sqlite3_finalize(stmt); return nil }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                let rc1 = sqlite3_step(stmt)
                if rc1 == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) { return String(cString: c) }
                if rc1 == SQLITE_ROW { return "" }
                return nil
            }

            func selectNoteBlockInstanceIDs(_ blockID: String) -> [String] {
                var out: [String] = []
                var stmt: OpaquePointer?
                let sql = """
                SELECT instance_id
                FROM nj_note_block
                WHERE block_id = ? AND deleted = 0;
                """
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { sqlite3_finalize(stmt); return out }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let instanceID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                    if !instanceID.isEmpty {
                        out.append(instanceID)
                    }
                }
                return out
            }

            func upsertBlock(_ blockID: String, _ payload: String, _ tagJSON: String, _ now: Int64, _ goalID: String?) -> Int32 {
                var stmt: OpaquePointer?
                let sql = """
                INSERT INTO nj_block
                (block_id, block_type, payload_json, domain_tag, tag_json, goal_id, lineage_id, parent_block_id, created_at_ms, updated_at_ms, deleted, dirty_bl)
                VALUES (?, 'text', ?, '', ?, ?, '', '', ?, ?, 0, 0)
                ON CONFLICT(block_id) DO UPDATE SET
                    payload_json = excluded.payload_json,
                    tag_json = CASE
                        WHEN excluded.tag_json = '' THEN nj_block.tag_json
                        ELSE excluded.tag_json
                    END,
                    goal_id = CASE
                        WHEN excluded.goal_id IS NULL OR excluded.goal_id = '' THEN nj_block.goal_id
                        ELSE excluded.goal_id
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
                if let gid = goalID, !gid.isEmpty {
                    sqlite3_bind_text(stmt, 4, gid, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                sqlite3_bind_int64(stmt, 5, now)
                sqlite3_bind_int64(stmt, 6, now)

                return sqlite3_step(stmt)
            }

            func touchNoteBlocks(_ blockID: String, _ now: Int64) -> Int32 {
                var stmt: OpaquePointer?
                let sql = """
                UPDATE nj_note_block
                SET updated_at_ms = ?, deleted = 0
                WHERE block_id = ?;
                """
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { sqlite3_finalize(stmt); return rc0 }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_int64(stmt, 1, now)
                sqlite3_bind_text(stmt, 2, blockID, -1, SQLITE_TRANSIENT)
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
                    v1.upsertProton1(protonJSON: normalizedProtonJSON)
                    if let out = try? JSONEncoder().encode(v1),
                       let s = String(data: out, encoding: .utf8) { newPayload = s }
                } else {
                    var v1 = NJPayloadV1(v: 1, sections: [:])
                    v1.upsertProton1(protonJSON: normalizedProtonJSON)
                    if let out = try? JSONEncoder().encode(v1),
                       let s = String(data: out, encoding: .utf8) { newPayload = s }
                }

                if !protonJSONHasRenderableContent(normalizedProtonJSON),
                   payloadJSONHasRenderableContent(normalized) {
                    _ = exec("ROLLBACK;")
                    didCommit = true
                    print("NJ_SAVE_SINGLE_PROTON_BLOCK SKIP_EMPTY_OVER_RENDERABLE block_id=\(blockID)")
                    break
                }

                let oldTagJSON = selectTagJSON(blockID) ?? ""
                let effectiveTagJSON = tagJSON.isEmpty ? oldTagJSON : tagJSON
                if newPayload == normalized && effectiveTagJSON == oldTagJSON {
                    _ = exec("ROLLBACK;")
                    didCommit = true
                    print("NJ_SAVE_SINGLE_PROTON_BLOCK NO_CHANGE block_id=\(blockID)")
                    break
                }

                print("NJ_SAVE_SINGLE_PROTON_BLOCK payload_bytes=\(newPayload.utf8.count)")
                print("NJ_SAVE_SINGLE_PROTON_BLOCK payload_preview=\(String(newPayload.prefix(260)))")

                let rcBlock = upsertBlock(blockID, newPayload, tagJSON, now, goalID)
                if rcBlock != SQLITE_DONE {
                    _ = exec("ROLLBACK;")
                    if isBusy(rcBlock) { backoff(attempt); continue }
                    db.dbgErr(dbp, "saveSingleProtonBlock.upsertBlock", rcBlock)
                    return
                }

                let noteBlockInstanceIDs = selectNoteBlockInstanceIDs(blockID)
                if !noteBlockInstanceIDs.isEmpty {
                    let rcTouch = touchNoteBlocks(blockID, now)
                    if rcTouch != SQLITE_DONE {
                        _ = exec("ROLLBACK;")
                        if isBusy(rcTouch) { backoff(attempt); continue }
                        db.dbgErr(dbp, "saveSingleProtonBlock.touchNoteBlocks", rcTouch)
                        return
                    }
                }

                if shouldEnqueue {
                    let rcBlockDirty = upsertDirty("block", blockID, "upsert", now)
                    if rcBlockDirty != SQLITE_DONE {
                        _ = exec("ROLLBACK;")
                        if isBusy(rcBlockDirty) { backoff(attempt); continue }
                        db.dbgErr(dbp, "saveSingleProtonBlock.upsertDirty.block", rcBlockDirty)
                        return
                    }

                    for instanceID in noteBlockInstanceIDs {
                        let rcNoteBlockDirty = upsertDirty("note_block", instanceID, "upsert", now)
                        if rcNoteBlockDirty != SQLITE_DONE {
                            _ = exec("ROLLBACK;")
                            if isBusy(rcNoteBlockDirty) { backoff(attempt); continue }
                            db.dbgErr(dbp, "saveSingleProtonBlock.upsertDirty.note_block", rcNoteBlockDirty)
                            return
                        }
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
            SELECT nb.block_id, nb.instance_id, nb.order_key, nb.is_checked,
                   nb.card_row_id, nb.card_status, nb.card_priority, nb.card_category, nb.card_area, nb.card_context, nb.card_title,
                   b.payload_json
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
                let isChecked = sqlite3_column_int64(stmt, 3) > 0
                let cardRowID = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                let cardStatus = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""
                let cardPriority = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? ""
                let cardCategory = sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? ""
                let cardArea = sqlite3_column_text(stmt, 8).flatMap { String(cString: $0) } ?? ""
                let cardContext = sqlite3_column_text(stmt, 9).flatMap { String(cString: $0) } ?? ""
                let cardTitle = sqlite3_column_text(stmt, 10).flatMap { String(cString: $0) } ?? ""
                let payload = sqlite3_column_text(stmt, 11).flatMap { String(cString: $0) } ?? ""

                guard !blockID.isEmpty else { continue }

                let (protonJSON, rtfBase64) = extractProtonJSONAndRTFBase64(fromPayloadJSON: payload)
                let rtfData = Data(base64Encoded: rtfBase64) ?? Self.emptyRTF()

                out.append(
                    NJLoadedTextBlock(
                        blockID: blockID,
                        instanceID: instanceID,
                        orderKey: orderKey,
                        isChecked: isChecked,
                        cardRowID: cardRowID,
                        cardStatus: cardStatus,
                        cardPriority: cardPriority,
                        cardCategory: cardCategory,
                        cardArea: cardArea,
                        cardContext: cardContext,
                        cardTitle: cardTitle,
                        payloadJSON: payload,
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
            return p.proton_json.isEmpty ? ("", p.rtf_base64) : (p.proton_json, "")
        }

        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ("", "")
        }

        if let sections = obj["sections"] as? [String: Any],
           let proton1 = sections["proton1"] as? [String: Any],
           let dataNode = proton1["data"] as? [String: Any] {
            let protonJSON = dataNode["proton_json"] as? String ?? ""
            return (
                protonJSON,
                protonJSON.isEmpty ? dataNode["rtf_base64"] as? String ?? "" : ""
            )
        }

        let protonJSON = obj["proton_json"] as? String ?? ""
        let rtfBase64 = obj["rtf_base64"] as? String ?? ""
        return protonJSON.isEmpty ? ("", rtfBase64) : (protonJSON, "")
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
        var resolvedInstanceID = ""
        var dirtyInstanceIDs: [String] = []

        db.withDB { dbp in
            _ = sqlite3_exec(dbp, "BEGIN IMMEDIATE;", nil, nil, nil)
            defer {
                if sqlite3_get_autocommit(dbp) == 0 {
                    _ = sqlite3_exec(dbp, "COMMIT;", nil, nil, nil)
                }
            }

            var ensureBlockStmt: OpaquePointer?
            let ensureBlockSQL = """
            INSERT OR IGNORE INTO nj_block
            (block_id, block_type, payload_json, domain_tag, tag_json, goal_id, lineage_id, parent_block_id, created_at_ms, updated_at_ms, deleted, dirty_bl)
            VALUES (?, 'text', '{}', '', '', NULL, '', '', ?, ?, 0, 0);
            """
            if sqlite3_prepare_v2(dbp, ensureBlockSQL, -1, &ensureBlockStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(ensureBlockStmt, 1, blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(ensureBlockStmt, 2, now)
                sqlite3_bind_int64(ensureBlockStmt, 3, now)
                _ = sqlite3_step(ensureBlockStmt)
            }
            sqlite3_finalize(ensureBlockStmt)

            struct ExistingLink {
                let instanceID: String
                let orderKey: Double
            }

            var liveLinks: [ExistingLink] = []
            var existingStmt: OpaquePointer?
            let existingSQL = """
            SELECT instance_id, order_key
            FROM nj_note_block
            WHERE note_id = ?
              AND block_id = ?
              AND deleted = 0
            ORDER BY order_key ASC, created_at_ms ASC, instance_id ASC;
            """
            if sqlite3_prepare_v2(dbp, existingSQL, -1, &existingStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(existingStmt, 1, noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(existingStmt, 2, blockID, -1, SQLITE_TRANSIENT)
                while sqlite3_step(existingStmt) == SQLITE_ROW {
                    let instanceID = sqlite3_column_text(existingStmt, 0).flatMap { String(cString: $0) } ?? ""
                    let currentOrderKey = sqlite3_column_double(existingStmt, 1)
                    if !instanceID.isEmpty {
                        liveLinks.append(ExistingLink(instanceID: instanceID, orderKey: currentOrderKey))
                    }
                }
            }
            sqlite3_finalize(existingStmt)

            if let canonical = liveLinks.first {
                resolvedInstanceID = canonical.instanceID

                if canonical.orderKey != orderKey {
                    var updateStmt: OpaquePointer?
                    let updateSQL = """
                    UPDATE nj_note_block
                    SET order_key = ?, updated_at_ms = ?
                    WHERE instance_id = ?;
                    """
                    if sqlite3_prepare_v2(dbp, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
                        sqlite3_bind_double(updateStmt, 1, orderKey)
                        sqlite3_bind_int64(updateStmt, 2, now)
                        sqlite3_bind_text(updateStmt, 3, canonical.instanceID, -1, SQLITE_TRANSIENT)
                        _ = sqlite3_step(updateStmt)
                    }
                    sqlite3_finalize(updateStmt)
                    dirtyInstanceIDs.append(canonical.instanceID)
                }

                if liveLinks.count > 1 {
                    var tombstoneStmt: OpaquePointer?
                    let tombstoneSQL = """
                    UPDATE nj_note_block
                    SET deleted = 1, updated_at_ms = ?
                    WHERE instance_id = ?;
                    """
                    if sqlite3_prepare_v2(dbp, tombstoneSQL, -1, &tombstoneStmt, nil) == SQLITE_OK {
                        for duplicate in liveLinks.dropFirst() {
                            sqlite3_reset(tombstoneStmt)
                            sqlite3_clear_bindings(tombstoneStmt)
                            sqlite3_bind_int64(tombstoneStmt, 1, now)
                            sqlite3_bind_text(tombstoneStmt, 2, duplicate.instanceID, -1, SQLITE_TRANSIENT)
                            if sqlite3_step(tombstoneStmt) == SQLITE_DONE {
                                dirtyInstanceIDs.append(duplicate.instanceID)
                            }
                        }
                    }
                    sqlite3_finalize(tombstoneStmt)
                }

                return
            }

            var revivedInstanceID = ""
            var reviveStmt: OpaquePointer?
            let reviveSQL = """
            SELECT instance_id
            FROM nj_note_block
            WHERE note_id = ?
              AND block_id = ?
              AND deleted = 1
            ORDER BY updated_at_ms DESC, created_at_ms DESC, instance_id DESC
            LIMIT 1;
            """
            if sqlite3_prepare_v2(dbp, reviveSQL, -1, &reviveStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(reviveStmt, 1, noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(reviveStmt, 2, blockID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(reviveStmt) == SQLITE_ROW {
                    revivedInstanceID = sqlite3_column_text(reviveStmt, 0).flatMap { String(cString: $0) } ?? ""
                }
            }
            sqlite3_finalize(reviveStmt)

            if !revivedInstanceID.isEmpty {
                var restoreStmt: OpaquePointer?
                let restoreSQL = """
                UPDATE nj_note_block
                SET deleted = 0, order_key = ?, updated_at_ms = ?
                WHERE instance_id = ?;
                """
                if sqlite3_prepare_v2(dbp, restoreSQL, -1, &restoreStmt, nil) == SQLITE_OK {
                    sqlite3_bind_double(restoreStmt, 1, orderKey)
                    sqlite3_bind_int64(restoreStmt, 2, now)
                    sqlite3_bind_text(restoreStmt, 3, revivedInstanceID, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(restoreStmt) == SQLITE_DONE {
                        resolvedInstanceID = revivedInstanceID
                        dirtyInstanceIDs.append(revivedInstanceID)
                    }
                }
                sqlite3_finalize(restoreStmt)
                return
            }

            let instanceID = UUID().uuidString

            var stmt: OpaquePointer?
            let insertNB = """
            INSERT INTO nj_note_block
            (block_id, created_at_ms, deleted, instance_id, note_id, order_key, is_checked, updated_at_ms)
            VALUES (?, ?, 0, ?, ?, ?, 0, ?);
            """
            if sqlite3_prepare_v2(dbp, insertNB, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, now)
                sqlite3_bind_text(stmt, 3, instanceID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, noteID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 5, orderKey)
                sqlite3_bind_int64(stmt, 6, now)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    resolvedInstanceID = instanceID
                    dirtyInstanceIDs.append(instanceID)
                }
            }
            sqlite3_finalize(stmt)
        }

        for instanceID in Set(dirtyInstanceIDs) {
            enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: now)
        }
        return resolvedInstanceID
    }

    private func extractRTFBase64(fromPayloadJSON payload: String) -> String? {
        if let normalized = try? NJPayloadConverterV1.convertToV1(payload),
           let data = normalized.data(using: .utf8),
           let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
           let p = try? v1.proton1Data() {
            return p.proton_json.isEmpty ? p.rtf_base64 : nil
        }

        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let sections = obj["sections"] as? [String: Any],
           let proton1 = sections["proton1"] as? [String: Any],
           let dataNode = proton1["data"] as? [String: Any] {
            if let protonJSON = dataNode["proton_json"] as? String, !protonJSON.isEmpty {
                return nil
            }
            return dataNode["rtf_base64"] as? String
        }

        if let protonJSON = obj["proton_json"] as? String, !protonJSON.isEmpty {
            return nil
        }
        return obj["rtf_base64"] as? String
    }
}
