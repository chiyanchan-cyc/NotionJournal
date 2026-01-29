import Foundation

extension DBNoteRepository {

    func exportBlockRows(fromDate: Date, toDate: Date, tagFilter: String?) throws -> [NJBlockExporter.Row] {
        let cal = Calendar(identifier: .gregorian)
        var c = cal
        c.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current

        let start = c.startOfDay(for: fromDate)
        let endExclusive = c.date(byAdding: .day, value: 1, to: c.startOfDay(for: toDate)) ?? toDate

        let startMs = Int64(start.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000.0)

        let tag = tagFilter?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagOpt = (tag == nil || tag!.isEmpty) ? nil : tag!

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "'", with: "''")
        }

        let tagExistsSQL: String
        if let t = tagOpt {
            tagExistsSQL = "AND EXISTS (SELECT 1 FROM nj_block_tag bt WHERE bt.block_id = b.block_id AND bt.tag = '\(esc(t))')"
        } else {
            tagExistsSQL = ""
        }

        let sql = """
        SELECT
            n.note_id AS note_id,
            n.tab_domain AS note_domain,
            b.block_id AS block_id,
            b.tag_json AS block_domain_json,
            b.payload_json AS payload_json,
            CASE WHEN b.updated_at_ms > 0 THEN b.updated_at_ms ELSE b.created_at_ms END AS ts_ms,
            IFNULL(tags.tags_csv, '') AS tags_csv
        FROM nj_note n
        JOIN nj_note_block nb ON nb.note_id = n.note_id AND nb.deleted = 0
        JOIN nj_block b ON b.block_id = nb.block_id AND b.deleted = 0
        LEFT JOIN (
            SELECT block_id, GROUP_CONCAT(tag, '|') AS tags_csv
            FROM nj_block_tag
            GROUP BY block_id
        ) tags ON tags.block_id = b.block_id
        WHERE n.deleted = 0
          AND (CASE WHEN b.updated_at_ms > 0 THEN b.updated_at_ms ELSE b.created_at_ms END) >= \(startMs)
          AND (CASE WHEN b.updated_at_ms > 0 THEN b.updated_at_ms ELSE b.created_at_ms END) < \(endMs)
          \(tagExistsSQL)
        ORDER BY n.updated_at_ms ASC, nb.order_key ASC;
        """

        let rows = db.queryRows(sql)

        return rows.map { r in
            let noteID = r["note_id"] ?? ""
            let noteDomain = r["note_domain"] ?? ""
            let blockID = r["block_id"] ?? ""
            let blockDomainJSON = r["block_domain_json"]
            let payloadJSON = r["payload_json"] ?? ""
            let tsMs = Int64(r["ts_ms"] ?? "0") ?? 0

            let tagsCSV = r["tags_csv"] ?? ""
            let tags = tagsCSV.isEmpty ? [] : tagsCSV.split(separator: "|").map { String($0) }

            let rtf = Self.extractRTFBase64(fromPayloadJSON: payloadJSON)

            return NJBlockExporter.Row(
                noteID: noteID,
                noteDomain: noteDomain,
                blockID: blockID,
                blockDomainJSON: blockDomainJSON,
                rtfBase64: rtf,
                tsMs: tsMs,
                tags: tags
            )
        }
    }

    private static func extractRTFBase64(fromPayloadJSON s: String) -> String? {
        guard let data = s.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        func get(_ dict: [String: Any], _ key: String) -> Any? { dict[key] }

        func findRTF(_ any: Any) -> String? {
            if let d = any as? [String: Any] {
                if let v = d["rtf_base64"] as? String, !v.isEmpty { return v }

                if let sections = d["sections"] as? [String: Any] {
                    if let p1 = sections["proton1"] as? [String: Any],
                       let pdata = (p1["data"] as? [String: Any]) {
                        if let v = pdata["rtf_base64"] as? String, !v.isEmpty { return v }
                        if let rich = pdata["rich"] as? [String: Any],
                           let v = rich["rtf_base64"] as? String, !v.isEmpty { return v }
                    }
                }

                for (_, v) in d {
                    if let hit = findRTF(v) { return hit }
                }
            }

            if let a = any as? [Any] {
                for v in a {
                    if let hit = findRTF(v) { return hit }
                }
            }

            return nil
        }

        if let hit = findRTF(obj) { return hit }

        if let root = obj as? [String: Any] {
            if let direct = root["rtf_base64"] as? String, !direct.isEmpty { return direct }
            if let sections = get(root, "sections") as? [String: Any] {
                if let p1 = sections["proton1"] as? [String: Any],
                   let pdata = (p1["data"] as? [String: Any]) {
                    if let v = pdata["rtf_base64"] as? String, !v.isEmpty { return v }
                }
            }
        }

        return nil
    }
}
