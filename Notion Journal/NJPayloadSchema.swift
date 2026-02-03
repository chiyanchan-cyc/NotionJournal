import Foundation

struct NJPayloadV1: Codable, Equatable {
    var v: Int
    var sections: [String: NJSectionV1]

    init(v: Int = 1, sections: [String: NJSectionV1] = [:]) {
        self.v = v
        self.sections = sections
    }

    func clipData() throws -> NJClipDataV1? {
        guard let s = sections["clip"] else { return nil }
        guard s.v == 1 else { throw NJPayloadError.unsupportedSectionVersion(section: "clip", v: s.v) }
        return try decode(NJClipDataV1.self, from: s.data)
    }

    func audioData() throws -> NJAudioDataV1? {
        guard let s = sections["audio"] else { return nil }
        guard s.v == 1 else { throw NJPayloadError.unsupportedSectionVersion(section: "audio", v: s.v) }
        return try decode(NJAudioDataV1.self, from: s.data)
    }

    func proton1Data() throws -> NJProton1DataV1? {
        guard let s = sections["proton1"] else { return nil }
        guard s.v == 1 else { throw NJPayloadError.unsupportedSectionVersion(section: "proton1", v: s.v) }
        return try decode(NJProton1DataV1.self, from: s.data)
    }

    func validate() throws {
        guard v == 1 else { throw NJPayloadError.unsupportedPayloadVersion(v) }
        for (k, s) in sections {
            guard s.v == 1 else { throw NJPayloadError.unsupportedSectionVersion(section: k, v: s.v) }
            if k == "proton1" {
                let data = try decode(NJProton1DataV1.self, from: s.data)
                try validateBase64RTF(data.rtf_base64)
                if data.proton_v != 1 { throw NJPayloadError.unsupportedProtonVersion(data.proton_v) }
            }
            if k == "clip" {
                _ = try decode(NJClipDataV1.self, from: s.data)
            }
            if k == "audio" {
                _ = try decode(NJAudioDataV1.self, from: s.data)
            }
        }
    }

    mutating func ensureProton1ExistsWithRTFBase64(_ rtfBase64: String) throws {
        try validateBase64RTF(rtfBase64)
        if let s = sections["proton1"], s.v == 1 {
            var data = try decode(NJProton1DataV1.self, from: s.data)
            data.proton_v = 1
            if data.proton_json.isEmpty { data.proton_json = "" }
            data.rtf_base64 = rtfBase64
            sections["proton1"] = NJSectionV1(v: 1, data: try encodeToObject(data))
            return
        }
        let data = NJProton1DataV1(proton_v: 1, proton_json: "", rtf_base64: rtfBase64)
        sections["proton1"] = NJSectionV1(v: 1, data: try encodeToObject(data))
    }

    private func validateBase64RTF(_ s: String) throws {
        if s.hasPrefix("PROTON1:") { throw NJPayloadError.invalidRTFBase64Prefix }
        if Data(base64Encoded: s) == nil { throw NJPayloadError.invalidBase64 }
    }
    
    mutating func upsertProton1(protonJSON: String) {
        if let s = sections["proton1"], s.v == 1 {
            var old = s.data
            old["proton_v"] = .int(1)
            old["proton_json"] = .string(protonJSON)
            sections["proton1"] = NJSectionV1(v: 1, data: old)
            return
        }

        sections["proton1"] = NJSectionV1(
            v: 1,
            data: [
                "proton_v": .int(1),
                "proton_json": .string(protonJSON)
            ]
        )
    }


    private func decode<T: Decodable>(_ type: T.Type, from obj: [String: JSONValue]) throws -> T {
        let data = try JSONEncoder().encode(obj)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func encodeToObject<T: Encodable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return obj
    }
}

struct NJSectionV1: Codable, Equatable {
    var v: Int
    var data: [String: JSONValue]
}

struct NJClipDataV1: Codable, Equatable {
    var website: String
    var url: String
    var title: String
    var summary: String?
    var mode: String?
    var created_at_ms: Int64
    var created_at_ios: String?
    var pdf_path: String?
    var json_path: String?
    var body: String?
}

struct NJAudioDataV1: Codable, Equatable {
    var title: String?
    var recorded_at_ms: Int64
    var recorded_at_iso: String?
    var audio_path: String?
    var audio_ext: String?
    var original_filename: String?
    var transcript_txt: String?
    var transcript_updated_ms: Int64?
}

struct NJProton1DataV1: Codable {
    var proton_v: Int
    var proton_json: String
    var rtf_base64: String

    enum CodingKeys: String, CodingKey {
        case proton_v
        case proton_json
        case rtf_base64
    }

    init(proton_v: Int, proton_json: String, rtf_base64: String = "") {
        self.proton_v = proton_v
        self.proton_json = proton_json
        self.rtf_base64 = rtf_base64
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proton_v = (try? c.decode(Int.self, forKey: .proton_v)) ?? 1
        proton_json = (try? c.decode(String.self, forKey: .proton_json)) ?? ""
        rtf_base64 = (try? c.decode(String.self, forKey: .rtf_base64)) ?? ""
    }
}

enum NJPayloadError: Error, Equatable {
    case unsupportedPayloadVersion(Int)
    case unsupportedSectionVersion(section: String, v: Int)
    case unsupportedProtonVersion(Int)
    case invalidRTFBase64Prefix
    case invalidBase64
}

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        }
    }
}
