import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DBNoteRepository {

    func exportBlockRows(fromDate: Date, toDate: Date, tagFilter: String?) throws -> [NJBlockExporter.Row] {
        let tz = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        let start = cal.startOfDay(for: fromDate)
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: toDate)) ?? toDate

        let startMs = Int64(start.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000.0)

        let tokens = Self.parseFilterTokens(tagFilter)

        var tagWhere = ""
        var binders: [(OpaquePointer?) -> Void] = []

        binders.append({ stmt in sqlite3_bind_int64(stmt, 1, startMs) })
        binders.append({ stmt in sqlite3_bind_int64(stmt, 2, endMs) })

        if !tokens.isEmpty {
            var parts: [String] = []
            var idx = 3

            for rawTok in tokens {
                let tok = rawTok.lowercased()

                if tok.hasSuffix(".*") {
                    let p = String(tok.dropLast(2))
                    let like = p.isEmpty ? "%" : "\(p).%"
                    parts.append("LOWER(t.tag) LIKE ?")
                    let j = idx
                    binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j), like, -1, SQLITE_TRANSIENT) })
                    idx += 1
                } else if tok.hasSuffix(".") {
                    let like = "\(tok)%"
                    parts.append("LOWER(t.tag) LIKE ?")
                    let j = idx
                    binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j), like, -1, SQLITE_TRANSIENT) })
                    idx += 1
                } else {
                    if tok.contains(".") {
                        parts.append("(LOWER(t.tag) = ? OR LOWER(t.tag) LIKE ? OR LOWER(t.tag) LIKE ? OR LOWER(t.tag) LIKE ?)")
                        let j0 = idx
                        binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j0), tok, -1, SQLITE_TRANSIENT) })
                        idx += 1

                        let j1 = idx
                        let likePrefix = "\(tok).%"
                        binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j1), likePrefix, -1, SQLITE_TRANSIENT) })
                        idx += 1

                        let j2 = idx
                        let likeMidExact = "%.\(tok)"
                        binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j2), likeMidExact, -1, SQLITE_TRANSIENT) })
                        idx += 1

                        let j3 = idx
                        let likeMidChild = "%.\(tok).%"
                        binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j3), likeMidChild, -1, SQLITE_TRANSIENT) })
                        idx += 1
                    } else {
                        parts.append("LOWER(t.tag) = ?")
                        let j = idx
                        binders.append({ stmt in sqlite3_bind_text(stmt, Int32(j), tok, -1, SQLITE_TRANSIENT) })
                        idx += 1
                    }
                }
            }

            tagWhere = """
            AND EXISTS (
                SELECT 1
                FROM nj_block_tag t
                WHERE t.block_id = b.block_id
                  AND (\(parts.joined(separator: " OR ")))
            )
            """
        }

        let tsExpr = """
        (MAX(
            IFNULL(NULLIF(nb.updated_at_ms,0),0),
            IFNULL(NULLIF(b.updated_at_ms,0),0),
            IFNULL(NULLIF(nb.created_at_ms,0),0),
            IFNULL(NULLIF(b.created_at_ms,0),0),
            IFNULL(NULLIF(alltags.tag_updated_ms,0),0)
        ))
        """

        let sql = """
        SELECT
            n.note_id AS note_id,
            n.tab_domain AS note_domain,
            b.block_id AS block_id,
            b.tag_json AS block_domain_json,
            b.payload_json AS payload_json,
            \(tsExpr) AS ts_ms,
            IFNULL(alltags.tags_csv, '') AS tags_csv
        FROM nj_note n
        JOIN nj_note_block nb ON nb.note_id = n.note_id AND nb.deleted = 0
        JOIN nj_block b ON b.block_id = nb.block_id AND b.deleted = 0
        LEFT JOIN (
            SELECT
                block_id,
                GROUP_CONCAT(tag, '|') AS tags_csv,
                MAX(updated_at_ms) AS tag_updated_ms
            FROM nj_block_tag
            GROUP BY block_id
        ) alltags ON alltags.block_id = b.block_id
        WHERE n.deleted = 0
          AND \(tsExpr) >= ?
          AND \(tsExpr) < ?
          \(tagWhere)
        ORDER BY \(tsExpr) ASC,
                 nb.order_key ASC;
        """

        return db.withDB { dbp in
            var out: [NJBlockExporter.Row] = []
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return out }
            defer { sqlite3_finalize(stmt) }

            for f in binders { f(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let noteID = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
                let noteDomain = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
                let blockID = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""

                let tagJSON = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
                let payloadJSON = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                let tsMs = sqlite3_column_int64(stmt, 5)

                let tagsCSV = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? ""
                let blockTags = tagsCSV.isEmpty ? [] : tagsCSV.split(separator: "|").map { String($0) }

                out.append(NJBlockExporter.Row(
                    blockID: blockID,
                    noteID: noteID,
                    noteDomain: noteDomain,
                    tagJSON: tagJSON,
                    tsMs: tsMs,
                    payloadJSON: payloadJSON,
                    blockTags: blockTags
                ))
            }

            return out
        }
    }

    private static func parseFilterTokens(_ s: String?) -> [String] {
        let raw = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return [] }
        return raw
            .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "#" }
    }
}
