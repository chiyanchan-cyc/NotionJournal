import Foundation

enum NJQuickNotePayload {
    static func makePayloadJSON(protonJSON: String, rtfBase64: String) -> String {
        let protonJSON = {
            let normalized = NJPayloadV1.normalizeProtonDocumentV2(protonJSON)
            if !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return normalized
            }
            return NJPayloadV1.protonDocumentV2FromRTFBase64(rtfBase64)
        }()
        var protonData: [String: JSONValue] = [
            "proton_v": .int(1),
            "proton_json": .string(protonJSON)
        ]

        let v1 = NJPayloadV1(
            v: 1,
            sections: [
                "proton1": NJSectionV1(v: 1, data: protonData)
            ]
        )

        guard let data = try? JSONEncoder().encode(v1) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func makePayloadJSON(from plainText: String) -> String {
        makePayloadJSON(protonJSON: "", rtfBase64: NJPayloadConverterV1.makeRTFBase64(plainText))
    }

    static func plainText(from payloadJSON: String) -> String {
        guard
            let data = payloadJSON.data(using: .utf8),
            let v1 = try? JSONDecoder().decode(NJPayloadV1.self, from: data),
            let proton = try? v1.proton1Data()
        else { return "" }

        if !proton.proton_json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainTextFromProtonJSON(proton.proton_json)
        }

        if !proton.rtf_base64.isEmpty,
           let text = try? NJPayloadConverterV1.decodeRTFBase64ToPlainText(proton.rtf_base64) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    static func title(from payloadJSON: String) -> String {
        let text = plainText(from: payloadJSON)
        guard !text.isEmpty else { return "" }
        if let line = text.split(whereSeparator: { $0.isNewline }).first {
            return String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func plainTextFromProtonJSON(_ protonJSON: String) -> String {
        guard let data = protonJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let doc = root["doc"] as? [[String: Any]] else {
            return ""
        }

        var lines: [String] = []
        for node in doc {
            let type = node["type"] as? String ?? ""
            if type == "rich",
               let rtfBase64 = node["rtf_base64"] as? String,
               let text = try? NJPayloadConverterV1.decodeRTFBase64ToPlainText(rtfBase64) {
                lines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if let items = node["items"] as? [[String: Any]] {
                let itemText = items.compactMap { item -> String? in
                    guard let rtfBase64 = item["rtf_base64"] as? String,
                          let text = try? NJPayloadConverterV1.decodeRTFBase64ToPlainText(rtfBase64) else {
                        return nil
                    }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                lines.append(contentsOf: itemText)
            }
        }

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
