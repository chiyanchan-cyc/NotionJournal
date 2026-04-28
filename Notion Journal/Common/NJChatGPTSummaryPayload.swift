import Foundation

struct NJChatGPTSummaryPayloadSpec: Equatable {
    var date: String
    var topic: String
    var domains: [String]
    var summary: String
    var context: String?
    var takeaway: String?
    var openQuestions: [String]
    var sourcePDFPath: String?
    var sourceTextPath: String?
    var sourceJSONPath: String?
    var sourceTitle: String?
}

enum NJChatGPTSummaryPayload {
    static func makePayloadJSON(from spec: NJChatGPTSummaryPayloadSpec) -> String {
        let visibleText = renderVisibleText(from: spec)
        let protonData: [String: JSONValue] = [
            "proton_v": .int(1),
            "proton_json": .string(
                NJPayloadV1.protonDocumentV2FromRTFBase64(
                    NJPayloadConverterV1.makeRTFBase64(visibleText)
                )
            )
        ]

        let summaryData = NJChatGPTSummaryDataV1(
            date: spec.date,
            topic: spec.topic,
            domains: spec.domains,
            summary: spec.summary,
            context: clean(spec.context),
            takeaway: clean(spec.takeaway),
            open_questions: spec.openQuestions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            source_pdf_path: clean(spec.sourcePDFPath),
            source_text_path: clean(spec.sourceTextPath),
            source_json_path: clean(spec.sourceJSONPath),
            source_title: clean(spec.sourceTitle)
        )

        guard
            let summaryObjectData = try? JSONEncoder().encode(summaryData),
            let summaryObject = try? JSONDecoder().decode([String: JSONValue].self, from: summaryObjectData),
            let payloadData = try? JSONEncoder().encode(
                NJPayloadV1(
                    v: 1,
                    sections: [
                        "proton1": NJSectionV1(v: 1, data: protonData),
                        "chatgpt_summary": NJSectionV1(v: 1, data: summaryObject)
                    ]
                )
            )
        else {
            return NJQuickNotePayload.makePayloadJSON(from: visibleText)
        }

        return String(data: payloadData, encoding: .utf8) ?? "{}"
    }

    static func renderVisibleText(from spec: NJChatGPTSummaryPayloadSpec) -> String {
        var lines: [String] = []

        let topic = spec.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topic.isEmpty {
            lines.append(topic)
            lines.append("")
        }

        let summary = spec.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            lines.append(summary)
        }

        let context = clean(spec.context) ?? ""
        if !context.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Context")
            lines.append(context)
        }

        let takeaway = clean(spec.takeaway) ?? ""
        if !takeaway.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Takeaway")
            lines.append(takeaway)
        }

        let openQuestions = spec.openQuestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !openQuestions.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Open Questions")
            lines.append(contentsOf: openQuestions.map { "- \($0)" })
        }

        let sourceHints = [
            clean(spec.sourcePDFPath).map { "PDF: \($0)" },
            clean(spec.sourceTextPath).map { "Text: \($0)" },
            clean(spec.sourceJSONPath).map { "JSON: \($0)" }
        ].compactMap { $0 }

        if !sourceHints.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Source")
            lines.append(contentsOf: sourceHints)
        }

        return lines.joined(separator: "\n")
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
