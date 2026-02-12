import Foundation

enum NJQuickNotePayload {
    static func makePayloadJSON(protonJSON: String, rtfBase64: String) -> String {
        let protonData: [String: JSONValue] = [
            "proton_v": .int(1),
            "proton_json": .string(protonJSON),
            "rtf_base64": .string(rtfBase64)
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

        let rtfBase64 = proton.rtf_base64
        guard !rtfBase64.isEmpty else { return "" }

        if let text = try? NJPayloadConverterV1.decodeRTFBase64ToPlainText(rtfBase64) {
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
}
