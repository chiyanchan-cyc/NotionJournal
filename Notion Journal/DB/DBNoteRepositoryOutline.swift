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
        }
    }

    func listOutlineNodes(outlineID: String) -> [NJOutlineNodeRecord] {
        db.withDB { dbp in
            var out: [NJOutlineNodeRecord] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT node_id, outline_id, parent_node_id, ord, title, comment, domain_tag, is_checklist, is_checked, created_at_ms, updated_at_ms
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
                let createdAtMs = sqlite3_column_int64(stmt, 9)
                let updatedAtMs = sqlite3_column_int64(stmt, 10)

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

        db.withDB { dbp in
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO nj_outline_node(
                node_id, outline_id, parent_node_id, ord, title, comment, domain_tag,
                is_checklist, is_checked, created_at_ms, updated_at_ms, deleted
            ) VALUES(?, ?, ?, ?, ?, '', '', 0, 0, ?, ?, 0);
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
            createdAtMs: now,
            updatedAtMs: now
        )
    }

    func updateOutlineNodeBasics(nodeID: String, title: String, comment: String, domainTag: String, isChecklist: Bool, isChecked: Bool) {
        let now = Self.nowMs()
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
        }
    }

    func moveOutlineNode(nodeID: String, parentNodeID: String?, ord: Int) {
        let now = Self.nowMs()
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
        }
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
