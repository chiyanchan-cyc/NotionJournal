import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
extension DBNoteRepository {
    func listOutlineCategories() -> [String] {
        db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT DISTINCT category
            FROM nj_outline
            WHERE deleted=0
              AND TRIM(category) <> ''
            ORDER BY category COLLATE NOCASE ASC;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listOutlineCategories.prepare", rc0); return out }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                out.append(String(cString: c))
            }
            return out
        }
    }

    func listOutlines(category: String?) -> [NJOutlineSummary] {
        db.withDB { dbp in
            var out: [NJOutlineSummary] = []
            var stmt: OpaquePointer?

            let sql: String
            if let category {
                sql = """
                SELECT outline_id, title, category, status, created_at_ms, updated_at_ms
                FROM nj_outline
                WHERE deleted=0 AND category=?
                ORDER BY updated_at_ms DESC;
                """
            } else {
                sql = """
                SELECT outline_id, title, category, status, created_at_ms, updated_at_ms
                FROM nj_outline
                WHERE deleted=0
                ORDER BY updated_at_ms DESC;
                """
            }

            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listOutlines.prepare", rc0); return out }
            defer { sqlite3_finalize(stmt) }

            if let category {
                sqlite3_bind_text(stmt, 1, category, -1, SQLITE_TRANSIENT)
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let outlineID = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let category = String(cString: sqlite3_column_text(stmt, 2))
                let status = String(cString: sqlite3_column_text(stmt, 3))
                let createdAtMs = sqlite3_column_int64(stmt, 4)
                let updatedAtMs = sqlite3_column_int64(stmt, 5)
                out.append(NJOutlineSummary(
                    outlineID: outlineID,
                    title: title,
                    category: category,
                    status: status,
                    createdAtMs: createdAtMs,
                    updatedAtMs: updatedAtMs
                ))
            }
            return out
        }
    }

    func createOutline(title: String, category: String) -> NJOutlineSummary? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let now = Self.nowMs()
        let outlineID = UUID().uuidString.lowercased()
        var didWrite = false

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_outline(outline_id, title, category, status, created_at_ms, updated_at_ms, deleted)
            VALUES(?, ?, ?, '', ?, ?, 0);
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "createOutline.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, outlineID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, trimmedTitle, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, now)
            sqlite3_bind_int64(stmt, 5, now)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "createOutline.step", rc1) }
            else { didWrite = true }
        }

        if didWrite {
            enqueueDirty(entity: "outline", entityID: outlineID, op: "upsert", updatedAtMs: now)
        }

        return NJOutlineSummary(
            outlineID: outlineID,
            title: trimmedTitle,
            category: category,
            status: "",
            createdAtMs: now,
            updatedAtMs: now
        )
    }

    func updateOutlineTitle(outlineID: String, title: String) {
        let now = Self.nowMs()
        var didWrite = false
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, "UPDATE nj_outline SET title=?, updated_at_ms=? WHERE outline_id=?;", -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "updateOutlineTitle.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, outlineID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "updateOutlineTitle.step", rc1) }
            else { didWrite = true }
        }
        if didWrite {
            enqueueDirty(entity: "outline", entityID: outlineID, op: "upsert", updatedAtMs: now)
        }
    }

    func listOutlineNodes(outlineID: String) -> [NJOutlineNodeRecord] {
        db.withDB { dbp in
            var out: [NJOutlineNodeRecord] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT node_id, outline_id, parent_node_id, ord, title, comment, domain_tag, is_checklist, is_checked, is_collapsed, filter_json, created_at_ms, updated_at_ms
            FROM nj_outline_node
            WHERE outline_id=? AND deleted=0
            ORDER BY parent_node_id ASC, ord ASC;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listOutlineNodes.prepare", rc0); return out }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, outlineID, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let nodeID = String(cString: sqlite3_column_text(stmt, 0))
                let outlineID = String(cString: sqlite3_column_text(stmt, 1))
                let parentNodeID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) }
                let ord = Int(sqlite3_column_int64(stmt, 3))
                let title = String(cString: sqlite3_column_text(stmt, 4))
                let comment = String(cString: sqlite3_column_text(stmt, 5))
                let domainTag = String(cString: sqlite3_column_text(stmt, 6))
                let isChecklist = sqlite3_column_int64(stmt, 7) > 0
                let isChecked = sqlite3_column_int64(stmt, 8) > 0
                let isCollapsed = sqlite3_column_int64(stmt, 9) > 0
                let filterJSON = String(cString: sqlite3_column_text(stmt, 10))
                let createdAtMs = sqlite3_column_int64(stmt, 11)
                let updatedAtMs = sqlite3_column_int64(stmt, 12)

                out.append(NJOutlineNodeRecord(
                    nodeID: nodeID,
                    outlineID: outlineID,
                    parentNodeID: parentNodeID,
                    ord: ord,
                    title: title,
                    comment: comment,
                    domainTag: domainTag,
                    isChecklist: isChecklist,
                    isChecked: isChecked,
                    isCollapsed: isCollapsed,
                    filterJSON: filterJSON,
                    createdAtMs: createdAtMs,
                    updatedAtMs: updatedAtMs
                ))
            }
            return out
        }
    }

    func createOutlineNode(outlineID: String, parentNodeID: String?, title: String) -> NJOutlineNodeRecord {
        let now = Self.nowMs()
        let nodeID = UUID().uuidString.lowercased()
        let ord = nextOutlineNodeOrder(outlineID: outlineID, parentNodeID: parentNodeID)
        var didWrite = false

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_outline_node(
                node_id, outline_id, parent_node_id, ord, title, comment, domain_tag,
                is_checklist, is_checked, is_collapsed, filter_json, goal_refs_json, block_refs_json, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, '', '', 0, 0, 0, '{}', '[]', '[]', ?, ?, 0);
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "createOutlineNode.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nodeID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, outlineID, -1, SQLITE_TRANSIENT)
            if let parentNodeID {
                sqlite3_bind_text(stmt, 3, parentNodeID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_int64(stmt, 4, Int64(ord))
            sqlite3_bind_text(stmt, 5, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, now)
            sqlite3_bind_int64(stmt, 7, now)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "createOutlineNode.step", rc1) }
            else { didWrite = true }
        }

        if didWrite {
            enqueueDirty(entity: "outline_node", entityID: nodeID, op: "upsert", updatedAtMs: now)
        }

        return NJOutlineNodeRecord(
            nodeID: nodeID,
            outlineID: outlineID,
            parentNodeID: parentNodeID,
            ord: ord,
            title: title,
            comment: "",
            domainTag: "",
            isChecklist: false,
            isChecked: false,
            isCollapsed: false,
            filterJSON: "{}",
            createdAtMs: now,
            updatedAtMs: now
        )
    }

    func updateOutlineNodeBasics(nodeID: String, title: String, comment: String, domainTag: String, isChecklist: Bool, isChecked: Bool) {
        let now = Self.nowMs()
        var didWrite = false
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_outline_node
            SET title=?, comment=?, domain_tag=?, is_checklist=?, is_checked=?, updated_at_ms=?
            WHERE node_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "updateOutlineNodeBasics.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, comment, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, domainTag, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, isChecklist ? 1 : 0)
            sqlite3_bind_int64(stmt, 5, isChecked ? 1 : 0)
            sqlite3_bind_int64(stmt, 6, now)
            sqlite3_bind_text(stmt, 7, nodeID, -1, SQLITE_TRANSIENT)

            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "updateOutlineNodeBasics.step", rc1) }
            else { didWrite = true }
        }
        if didWrite {
            enqueueDirty(entity: "outline_node", entityID: nodeID, op: "upsert", updatedAtMs: now)
        }
    }

    func updateOutlineNodeCollapsed(nodeID: String, isCollapsed: Bool) {
        let now = Self.nowMs()
        var didWrite = false
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "UPDATE nj_outline_node SET is_collapsed=?, updated_at_ms=? WHERE node_id=?;"
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "updateOutlineNodeCollapsed.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, isCollapsed ? 1 : 0)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, nodeID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "updateOutlineNodeCollapsed.step", rc1) }
            else { didWrite = true }
        }
        if didWrite {
            enqueueDirty(entity: "outline_node", entityID: nodeID, op: "upsert", updatedAtMs: now)
        }
    }

    func updateOutlineNodeFilter(nodeID: String, filterJSON: String) {
        let now = Self.nowMs()
        var didWrite = false
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "UPDATE nj_outline_node SET filter_json=?, updated_at_ms=? WHERE node_id=?;"
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "updateOutlineNodeFilter.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, filterJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, nodeID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "updateOutlineNodeFilter.step", rc1) }
            else { didWrite = true }
        }
        if didWrite {
            enqueueDirty(entity: "outline_node", entityID: nodeID, op: "upsert", updatedAtMs: now)
        }
    }

    func canDeleteOutlineNode(nodeID: String) -> Bool {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT
              EXISTS(SELECT 1 FROM nj_outline_node c WHERE c.parent_node_id = n.node_id AND c.deleted=0) AS has_children,
              COALESCE(n.goal_refs_json, '[]') AS goal_refs_json,
              COALESCE(n.block_refs_json, '[]') AS block_refs_json
            FROM nj_outline_node n
            WHERE n.node_id=? AND n.deleted=0
            LIMIT 1;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "canDeleteOutlineNode.prepare", rc0); return false }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nodeID, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
            let hasChildren = sqlite3_column_int64(stmt, 0) > 0
            let goalRefs = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? "[]"
            let blockRefs = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? "[]"

            if hasChildren { return false }
            if !jsonArrayIsEmpty(goalRefs) { return false }
            if !jsonArrayIsEmpty(blockRefs) { return false }
            return true
        }
    }

    func deleteOutlineNode(nodeID: String) {
        let now = Self.nowMs()
        var didWrite = false
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = "UPDATE nj_outline_node SET deleted=1, updated_at_ms=? WHERE node_id=?;"
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "deleteOutlineNode.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, now)
            sqlite3_bind_text(stmt, 2, nodeID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "deleteOutlineNode.step", rc1) }
            else { didWrite = true }
        }
        if didWrite {
            enqueueDirty(entity: "outline_node", entityID: nodeID, op: "upsert", updatedAtMs: now)
        }
    }

    func listOutlineReconstructedBlockIDs(
        rules: [NJOutlineFilterRule],
        op: String,
        startMs: Int64?,
        endMs: Int64?,
        limit: Int
    ) -> [String] {
        db.withDB { dbp in
            let activeRules = rules
                .map { NJOutlineFilterRule(id: $0.id, field: $0.field, value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.value.isEmpty }
            let upperOp = op.uppercased() == "OR" ? "OR" : "AND"

            var condition = "b.deleted=0"
            if !activeRules.isEmpty {
                let parts = activeRules.map { rule -> String in
                    switch rule.field {
                    case .domain:
                        return """
                        (
                            lower(COALESCE(b.domain_tag,'')) LIKE lower(?)
                            OR EXISTS (
                                SELECT 1
                                FROM nj_block_tag t
                                WHERE t.block_id = b.block_id
                                  AND lower(t.tag) LIKE lower(?)
                            )
                        )
                        """
                    case .tag:
                        return "EXISTS (SELECT 1 FROM nj_block_tag t WHERE t.block_id = b.block_id AND lower(t.tag) LIKE lower(?))"
                    }
                }
                condition += " AND (" + parts.joined(separator: " \(upperOp) ") + ")"
            }
            if startMs != nil { condition += " AND b.created_at_ms >= ?" }
            if endMs != nil { condition += " AND b.created_at_ms <= ?" }

            let sql = """
            SELECT b.block_id
            FROM nj_block b
            WHERE \(condition)
            ORDER BY b.created_at_ms DESC
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listOutlineReconstructedBlockIDs.prepare", rc0); return [] }
            defer { sqlite3_finalize(stmt) }

            var i: Int32 = 1
            for rule in activeRules {
                switch rule.field {
                case .domain:
                    sqlite3_bind_text(stmt, i, "%\(rule.value)%", -1, SQLITE_TRANSIENT)
                    i += 1
                    sqlite3_bind_text(stmt, i, "%\(rule.value)%", -1, SQLITE_TRANSIENT)
                    i += 1
                case .tag:
                    sqlite3_bind_text(stmt, i, "%\(rule.value)%", -1, SQLITE_TRANSIENT)
                    i += 1
                }
            }
            if let startMs {
                sqlite3_bind_int64(stmt, i, startMs)
                i += 1
            }
            if let endMs {
                sqlite3_bind_int64(stmt, i, endMs)
                i += 1
            }
            sqlite3_bind_int(stmt, i, Int32(max(limit, 1)))

            var out: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let blockID = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                if !blockID.isEmpty { out.append(blockID) }
            }
            return out
        }
    }

    func listOutlineReconstructedBlocks(
        domain: String,
        tags: [String],
        op: String,
        startMs: Int64?,
        endMs: Int64?,
        limit: Int
    ) -> [NJOutlineReconstructedRow] {
        db.withDB { dbp in
            var out: [NJOutlineReconstructedRow] = []
            var stmt: OpaquePointer?

            let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let upperOp = op.uppercased() == "OR" ? "OR" : "AND"

            let domainSQL = """
            (
                lower(COALESCE(b.domain_tag,'')) LIKE lower(?)
                OR EXISTS (
                    SELECT 1
                    FROM nj_block_tag td
                    WHERE td.block_id = b.block_id
                      AND lower(td.tag) LIKE lower(?)
                )
            )
            """
            let tagSQL: String = {
                if cleanTags.isEmpty { return "" }
                if upperOp == "AND" {
                    return cleanTags.map { _ in
                        "EXISTS (SELECT 1 FROM nj_block_tag t WHERE t.block_id = b.block_id AND lower(t.tag) LIKE lower(?))"
                    }.joined(separator: " AND ")
                }
                let ors = cleanTags.map { _ in "lower(t.tag) LIKE lower(?)" }.joined(separator: " OR ")
                return "EXISTS (SELECT 1 FROM nj_block_tag t WHERE t.block_id = b.block_id AND (\(ors)))"
            }()

            var condition: String = "b.deleted=0"
            if !trimmedDomain.isEmpty && !cleanTags.isEmpty {
                condition += " AND ((\(domainSQL)) \(upperOp) (\(tagSQL)))"
            } else if !trimmedDomain.isEmpty {
                condition += " AND (\(domainSQL))"
            } else if !cleanTags.isEmpty {
                condition += " AND (\(tagSQL))"
            }
            if startMs != nil { condition += " AND b.created_at_ms >= ?" }
            if endMs != nil { condition += " AND b.created_at_ms <= ?" }

            let sql = """
            SELECT
              b.block_id,
              b.created_at_ms,
              COALESCE(b.domain_tag, ''),
              COALESCE(b.payload_json, ''),
              COALESCE((SELECT GROUP_CONCAT(t2.tag, '|') FROM nj_block_tag t2 WHERE t2.block_id = b.block_id), '')
            FROM nj_block b
            WHERE \(condition)
            ORDER BY b.created_at_ms DESC
            LIMIT ?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "listOutlineReconstructedBlocks.prepare", rc0); return out }
            defer { sqlite3_finalize(stmt) }

            var i: Int32 = 1
            if !trimmedDomain.isEmpty {
                sqlite3_bind_text(stmt, i, "%\(trimmedDomain)%", -1, SQLITE_TRANSIENT)
                i += 1
                sqlite3_bind_text(stmt, i, "%\(trimmedDomain)%", -1, SQLITE_TRANSIENT)
                i += 1
            }
            if !cleanTags.isEmpty {
                for t in cleanTags {
                    sqlite3_bind_text(stmt, i, "%\(t)%", -1, SQLITE_TRANSIENT)
                    i += 1
                }
            }
            if let startMs {
                sqlite3_bind_int64(stmt, i, startMs)
                i += 1
            }
            if let endMs {
                sqlite3_bind_int64(stmt, i, endMs)
                i += 1
            }
            sqlite3_bind_int(stmt, i, Int32(max(limit, 1)))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let blockID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let createdAtMs = sqlite3_column_int64(stmt, 1)
                let domainTag = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
                let payload = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
                let tagsStr = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                if blockID.isEmpty { continue }
                let tags = tagsStr.split(separator: "|").map { String($0) }
                out.append(NJOutlineReconstructedRow(
                    blockID: blockID,
                    createdAtMs: createdAtMs,
                    domainTag: domainTag,
                    tags: tags,
                    title: outlineBlockTitle(payloadJSON: payload)
                ))
            }
            return out
        }
    }

    private func jsonArrayIsEmpty(_ raw: String) -> Bool {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return true
        }
        return arr.isEmpty
    }

    private func outlineBlockTitle(payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (obj["title"] as? String) ?? ""
    }

    func moveOutlineNode(nodeID: String, parentNodeID: String?, ord: Int) {
        let now = Self.nowMs()
        var didWrite = false
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            UPDATE nj_outline_node
            SET parent_node_id=?, ord=?, updated_at_ms=?
            WHERE node_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "moveOutlineNode.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }
            if let parentNodeID {
                sqlite3_bind_text(stmt, 1, parentNodeID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_int64(stmt, 2, Int64(ord))
            sqlite3_bind_int64(stmt, 3, now)
            sqlite3_bind_text(stmt, 4, nodeID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "moveOutlineNode.step", rc1) }
            else { didWrite = true }
        }
        if didWrite {
            enqueueDirty(entity: "outline_node", entityID: nodeID, op: "upsert", updatedAtMs: now)
        }
    }

    func loadOutlineFields(outlineID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT outline_id, title, category, status, created_at_ms, updated_at_ms, deleted
            FROM nj_outline
            WHERE outline_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadOutlineFields.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, outlineID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return [
                "outline_id": String(cString: sqlite3_column_text(stmt, 0)),
                "title": String(cString: sqlite3_column_text(stmt, 1)),
                "category": String(cString: sqlite3_column_text(stmt, 2)),
                "status": String(cString: sqlite3_column_text(stmt, 3)),
                "created_at_ms": sqlite3_column_int64(stmt, 4),
                "updated_at_ms": sqlite3_column_int64(stmt, 5),
                "deleted": sqlite3_column_int64(stmt, 6)
            ]
        }
    }

    func loadOutlineNodeFields(nodeID: String) -> [String: Any]? {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            SELECT node_id, outline_id, parent_node_id, ord, title, comment, domain_tag, is_checklist, is_checked, is_collapsed, filter_json, created_at_ms, updated_at_ms, deleted
            FROM nj_outline_node
            WHERE node_id=?;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "loadOutlineNodeFields.prepare", rc0); return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nodeID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let parentNodeID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
            return [
                "node_id": String(cString: sqlite3_column_text(stmt, 0)),
                "outline_id": String(cString: sqlite3_column_text(stmt, 1)),
                "parent_node_id": parentNodeID,
                "ord": sqlite3_column_int64(stmt, 3),
                "title": String(cString: sqlite3_column_text(stmt, 4)),
                "comment": String(cString: sqlite3_column_text(stmt, 5)),
                "domain_tag": String(cString: sqlite3_column_text(stmt, 6)),
                "is_checklist": sqlite3_column_int64(stmt, 7),
                "is_checked": sqlite3_column_int64(stmt, 8),
                "is_collapsed": sqlite3_column_int64(stmt, 9),
                "filter_json": String(cString: sqlite3_column_text(stmt, 10)),
                "created_at_ms": sqlite3_column_int64(stmt, 11),
                "updated_at_ms": sqlite3_column_int64(stmt, 12),
                "deleted": sqlite3_column_int64(stmt, 13)
            ]
        }
    }

    func applyOutlineFields(_ f: [String: Any]) {
        let outlineID = ((f["outline_id"] as? String) ?? (f["outlineID"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if outlineID.isEmpty { return }

        let title = ((f["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (f["category"] as? String) ?? ""
        let status = (f["status"] as? String) ?? ""
        let now = Self.nowMs()
        let createdAtMs = max(1, int64Any(f["created_at_ms"]) ?? now)
        let updatedAtMs = max(1, int64Any(f["updated_at_ms"]) ?? createdAtMs)
        let deleted = (int64Any(f["deleted"]) ?? 0) > 0 ? Int64(1) : Int64(0)

        db.withDB { dbp in
            var existingStmt: OpaquePointer?
            let rcE = sqlite3_prepare_v2(dbp, "SELECT updated_at_ms FROM nj_outline WHERE outline_id=? LIMIT 1;", -1, &existingStmt, nil)
            if rcE == SQLITE_OK {
                sqlite3_bind_text(existingStmt, 1, outlineID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(existingStmt) == SQLITE_ROW {
                    let existingUpdatedAt = sqlite3_column_int64(existingStmt, 0)
                    if existingUpdatedAt > updatedAtMs {
                        sqlite3_finalize(existingStmt)
                        return
                    }
                }
            }
            sqlite3_finalize(existingStmt)

            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_outline(outline_id, title, category, status, created_at_ms, updated_at_ms, deleted)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(outline_id) DO UPDATE SET
              title=excluded.title,
              category=excluded.category,
              status=excluded.status,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyOutlineFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, outlineID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, title.isEmpty ? "Outline" : title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 5, createdAtMs)
            sqlite3_bind_int64(stmt, 6, updatedAtMs)
            sqlite3_bind_int64(stmt, 7, deleted)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyOutlineFields.step", rc1) }
        }
    }

    func applyOutlineNodeFields(_ f: [String: Any]) {
        let nodeID = ((f["node_id"] as? String) ?? (f["nodeID"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if nodeID.isEmpty { return }
        let outlineID = ((f["outline_id"] as? String) ?? (f["outlineID"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if outlineID.isEmpty { return }

        let parentRaw = ((f["parent_node_id"] as? String) ?? (f["parentNodeID"] as? String) ?? "")
        let parentNodeID = parentRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ord = Int(int64Any(f["ord"]) ?? 0)
        let title = (f["title"] as? String) ?? ""
        let comment = (f["comment"] as? String) ?? ""
        let domainTag = (f["domain_tag"] as? String) ?? ""
        let isChecklist: Int64 = (int64Any(f["is_checklist"]) ?? 0) > 0 ? 1 : 0
        let isChecked: Int64 = (int64Any(f["is_checked"]) ?? 0) > 0 ? 1 : 0
        let isCollapsed: Int64 = (int64Any(f["is_collapsed"]) ?? 0) > 0 ? 1 : 0
        let filterJSON = (f["filter_json"] as? String) ?? "{}"
        let now = Self.nowMs()
        let createdAtMs = max(1, int64Any(f["created_at_ms"]) ?? now)
        let updatedAtMs = max(1, int64Any(f["updated_at_ms"]) ?? createdAtMs)
        let deleted: Int64 = (int64Any(f["deleted"]) ?? 0) > 0 ? 1 : 0

        db.withDB { dbp in
            var existingStmt: OpaquePointer?
            let rcE = sqlite3_prepare_v2(dbp, "SELECT updated_at_ms FROM nj_outline_node WHERE node_id=? LIMIT 1;", -1, &existingStmt, nil)
            if rcE == SQLITE_OK {
                sqlite3_bind_text(existingStmt, 1, nodeID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(existingStmt) == SQLITE_ROW {
                    let existingUpdatedAt = sqlite3_column_int64(existingStmt, 0)
                    if existingUpdatedAt > updatedAtMs {
                        sqlite3_finalize(existingStmt)
                        return
                    }
                }
            }
            sqlite3_finalize(existingStmt)

            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_outline_node(
                node_id, outline_id, parent_node_id, ord, title, comment, domain_tag,
                is_checklist, is_checked, is_collapsed, filter_json, goal_refs_json, block_refs_json, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', '[]', ?, ?, ?)
            ON CONFLICT(node_id) DO UPDATE SET
              outline_id=excluded.outline_id,
              parent_node_id=excluded.parent_node_id,
              ord=excluded.ord,
              title=excluded.title,
              comment=excluded.comment,
              domain_tag=excluded.domain_tag,
              is_checklist=excluded.is_checklist,
              is_checked=excluded.is_checked,
              is_collapsed=excluded.is_collapsed,
              filter_json=excluded.filter_json,
              created_at_ms=excluded.created_at_ms,
              updated_at_ms=excluded.updated_at_ms,
              deleted=excluded.deleted;
            """
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "applyOutlineNodeFields.prepare", rc0); return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nodeID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, outlineID, -1, SQLITE_TRANSIENT)
            if parentNodeID.isEmpty {
                sqlite3_bind_null(stmt, 3)
            } else {
                sqlite3_bind_text(stmt, 3, parentNodeID, -1, SQLITE_TRANSIENT)
            }
            sqlite3_bind_int64(stmt, 4, Int64(ord))
            sqlite3_bind_text(stmt, 5, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, comment, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, domainTag, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 8, isChecklist)
            sqlite3_bind_int64(stmt, 9, isChecked)
            sqlite3_bind_int64(stmt, 10, isCollapsed)
            sqlite3_bind_text(stmt, 11, filterJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 12, createdAtMs)
            sqlite3_bind_int64(stmt, 13, updatedAtMs)
            sqlite3_bind_int64(stmt, 14, deleted)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE { db.dbgErr(dbp, "applyOutlineNodeFields.step", rc1) }
        }
    }

    @discardableResult
    func enqueueOutlineDirtyBackfillIfNeeded() -> Int {
        struct RowID { let id: String; let updatedAtMs: Int64 }
        let (outlineRows, nodeRows): ([RowID], [RowID]) = db.withDB { dbp in
            func load(_ sql: String, label: String) -> [RowID] {
                var out: [RowID] = []
                var stmt: OpaquePointer?
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK {
                    db.dbgErr(dbp, "enqueueOutlineDirtyBackfillIfNeeded.\(label).prepare", rc0)
                    return out
                }
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let c = sqlite3_column_text(stmt, 0) else { continue }
                    let id = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if id.isEmpty { continue }
                    out.append(RowID(id: id, updatedAtMs: sqlite3_column_int64(stmt, 1)))
                }
                return out
            }

            let outlines = load(
                "SELECT outline_id, updated_at_ms FROM nj_outline;",
                label: "outline.select"
            )
            let nodes = load(
                "SELECT node_id, updated_at_ms FROM nj_outline_node;",
                label: "node.select"
            )
            return (outlines, nodes)
        }

        let now = Self.nowMs()
        for r in outlineRows {
            enqueueDirty(entity: "outline", entityID: r.id, op: "upsert", updatedAtMs: max(r.updatedAtMs, now))
        }
        for r in nodeRows {
            enqueueDirty(entity: "outline_node", entityID: r.id, op: "upsert", updatedAtMs: max(r.updatedAtMs, now))
        }

        let dirtyOutlineCount = db.withDB { scalarCount(dbp: $0, sql: "SELECT COUNT(1) FROM nj_dirty WHERE entity='outline';") }
        let dirtyNodeCount = db.withDB { scalarCount(dbp: $0, sql: "SELECT COUNT(1) FROM nj_dirty WHERE entity='outline_node';") }
        let changed = dirtyOutlineCount + dirtyNodeCount
        print("NJ_OUTLINE_BACKFILL outlines=\(outlineRows.count) nodes=\(nodeRows.count) dirty_outline=\(dirtyOutlineCount) dirty_node=\(dirtyNodeCount) changed=\(changed)")
        return changed
    }

    private func scalarCount(dbp: OpaquePointer?, sql: String) -> Int {
        var stmt: OpaquePointer?
        let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
        if rc0 != SQLITE_OK { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func int64Any(_ v: Any?) -> Int64? {
        guard let v else { return nil }
        if let n = v as? NSNumber { return n.int64Value }
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let d = v as? Double { return Int64(d) }
        if let s = v as? String {
            if let i = Int64(s) { return i }
            if let d = Double(s) { return Int64(d) }
        }
        return nil
    }

    private func nextOutlineNodeOrder(outlineID: String, parentNodeID: String?) -> Int {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql: String
            if parentNodeID == nil {
                sql = """
                SELECT COALESCE(MAX(ord), -1)
                FROM nj_outline_node
                WHERE outline_id=? AND parent_node_id IS NULL AND deleted=0;
                """
            } else {
                sql = """
                SELECT COALESCE(MAX(ord), -1)
                FROM nj_outline_node
                WHERE outline_id=? AND parent_node_id=? AND deleted=0;
                """
            }
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { db.dbgErr(dbp, "nextOutlineNodeOrder.prepare", rc0); return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, outlineID, -1, SQLITE_TRANSIENT)
            if let parentNodeID {
                sqlite3_bind_text(stmt, 2, parentNodeID, -1, SQLITE_TRANSIENT)
            }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0) + 1)
        }
    }
}
