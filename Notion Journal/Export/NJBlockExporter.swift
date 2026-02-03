import Foundation
import UIKit

struct NJBlockExporter {

    struct Row {
        let blockID: String
        let noteID: String
        let noteDomain: String
        let tagJSON: String
        let tsMs: Int64
        let payloadJSON: String
        let blockTags: [String]
    }

    static func exportJSON(
        tzID: String,
        fromDate: Date,
        toDate: Date,
        tagFilter: String?,
        fetchRows: () throws -> [Row]
    ) throws -> Data {
        let rows = try fetchRows()

        var blocks: [[String: Any]] = []
        blocks.reserveCapacity(rows.count)

        for r in rows {
            let body = plainTextFromPayloadJSON(r.payloadJSON)
            let rtf = rtfBase64FromPayloadJSON(r.payloadJSON)

            blocks.append([
                "block_id": r.blockID,
                "note_id": r.noteID,
                "note_domain": r.noteDomain,
                "block_domain": r.tagJSON,
                "block_tags": r.blockTags,
                "ts_ms": r.tsMs,
                "body": body,
                "rtf_base64": rtf
            ])
        }

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = TimeZone(identifier: tzID) ?? TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"

        let obj: [String: Any] = [
            "schema": "nj_block_export_v2",
            "range": [
                "from": df.string(from: fromDate),
                "to": df.string(from: toDate),
                "tz": tzID
            ],
            "count": rows.count,
            "blocks": blocks
        ]

        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    private static func plainTextFromPayloadJSON(_ s: String) -> String {
        guard let data = s.data(using: .utf8) else { return "" }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return "" }

        func findString(_ any: Any, key: String) -> String? {
            if let d = any as? [String: Any] {
                if let v = d[key] as? String, !v.isEmpty { return v }
                for (_, v) in d {
                    if let hit = findString(v, key: key) { return hit }
                }
            } else if let a = any as? [Any] {
                for v in a {
                    if let hit = findString(v, key: key) { return hit }
                }
            }
            return nil
        }

        func findRTF(_ any: Any) -> String? {
            if let d = any as? [String: Any] {
                if let v = d["rtf_base64"] as? String, !v.isEmpty { return v }
                for (_, v) in d {
                    if let hit = findRTF(v) { return hit }
                }
            } else if let a = any as? [Any] {
                for v in a {
                    if let hit = findRTF(v) { return hit }
                }
            }
            return nil
        }

        if let protonJSON = findString(root, key: "proton_json"),
           let pdata = protonJSON.data(using: .utf8),
           let pobj = try? JSONSerialization.jsonObject(with: pdata),
           let rtf = findRTF(pobj) {
            return plainTextFromRTFBase64(rtf)
        }

        if let rtf = findString(root, key: "rtf_base64") {
            return plainTextFromRTFBase64(rtf)
        }

        return ""
    }

    private static func rtfBase64FromPayloadJSON(_ s: String) -> String {
        guard let data = s.data(using: .utf8) else { return "" }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return "" }

        func findString(_ any: Any, key: String) -> String? {
            if let d = any as? [String: Any] {
                if let v = d[key] as? String, !v.isEmpty { return v }
                for (_, v) in d {
                    if let hit = findString(v, key: key) { return hit }
                }
            } else if let a = any as? [Any] {
                for v in a {
                    if let hit = findString(v, key: key) { return hit }
                }
            }
            return nil
        }

        func findRTF(_ any: Any) -> String? {
            if let d = any as? [String: Any] {
                if let v = d["rtf_base64"] as? String, !v.isEmpty { return v }
                for (_, v) in d {
                    if let hit = findRTF(v) { return hit }
                }
            } else if let a = any as? [Any] {
                for v in a {
                    if let hit = findRTF(v) { return hit }
                }
            }
            return nil
        }

        if let protonJSON = findString(root, key: "proton_json"),
           let pdata = protonJSON.data(using: .utf8),
           let pobj = try? JSONSerialization.jsonObject(with: pdata),
           let rtf = findRTF(pobj) {
            return rtf
        }

        if let rtf = findString(root, key: "rtf_base64") {
            return rtf
        }

        return ""
    }

    private static func plainTextFromRTFBase64(_ b64: String) -> String {
        guard let data = Data(base64Encoded: b64) else { return "" }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        let s = (try? NSAttributedString(data: data, options: opts, documentAttributes: nil)) ?? NSAttributedString(string: "")
        return s.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
