//
//  NJBlockExporter.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/29.
//


import Foundation
import UIKit

final class NJBlockExporter {
    struct Row {
        let noteID: String
        let noteDomain: String
        let blockID: String
        let blockDomainJSON: String?
        let rtfBase64: String?
        let tsMs: Int64
        let tags: [String]
    }

    static func rtfBase64ToPlainText(_ s: String?) -> String {
        guard let s, let data = Data(base64Encoded: s) else { return "" }
        if let attr = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.rtf,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func exportJSON(
        tzID: String,
        fromDate: Date,
        toDate: Date,
        tagFilter: String?,
        fetchRows: () throws -> [Row]
    ) throws -> Data {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = TimeZone(identifier: tzID) ?? .current
        df.dateFormat = "yyyy-MM-dd"

        let rows = try fetchRows()

        let blocks: [NJBlockExportItem] = rows.map {
            NJBlockExportItem(
                ts_ms: $0.tsMs,
                note_id: $0.noteID,
                block_id: $0.blockID,
                note_domain: $0.noteDomain,
                block_domain: $0.blockDomainJSON,
                block_tags: $0.tags,
                body: rtfBase64ToPlainText($0.rtfBase64)
            )
        }

        let bundle = NJBlockExportBundle(
            schema: "nj_block_export_v1",
            range: NJExportRange(
                from: df.string(from: fromDate),
                to: df.string(from: toDate),
                tz: tzID
            ),
            tag_filter: (tagFilter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : tagFilter,
            count: blocks.count,
            blocks: blocks
        )

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(bundle)
    }
}
