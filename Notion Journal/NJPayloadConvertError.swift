//
//  NJPayloadConvertError.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/16.
//


import Foundation
import UIKit

enum NJPayloadConvertError: Error {
    case invalidJSON
    case invalidRTFBase64
    case unsupportedTopLevelV(Int)
    case missingSections
    case unsupportedSectionVersion(String, Int)
}

struct NJPayloadConverterV1 {
    static func convertToV1(_ inputJSON: String) throws -> String {
        let data = inputJSON.data(using: .utf8) ?? Data()
        let objAny = try JSONSerialization.jsonObject(with: data, options: [])
        guard let obj = objAny as? [String: Any] else { throw NJPayloadConvertError.invalidJSON }

        if let v = obj["v"] as? Int {
            guard v == 1 else { throw NJPayloadConvertError.unsupportedTopLevelV(v) }
            guard let sections = obj["sections"] as? [String: Any] else { throw NJPayloadConvertError.missingSections }
            if let clip = sections["clip"] as? [String: Any], let sv = clip["v"] as? Int, sv != 1 { throw NJPayloadConvertError.unsupportedSectionVersion("clip", sv) }
            if let p = sections["proton1"] as? [String: Any], let sv = p["v"] as? Int, sv != 1 { throw NJPayloadConvertError.unsupportedSectionVersion("proton1", sv) }
            return try normalizeV1Envelope(obj)
        }

        return try convertLegacyFlatToV1(obj)
    }

    private static func convertLegacyFlatToV1(_ obj: [String: Any]) throws -> String {
        let rtfBase64 = (obj["rtf_base64"] as? String) ?? ""
        if !rtfBase64.isEmpty { try validateRTFBase64(rtfBase64) }

        let website = (obj["website"] as? String) ?? ""
        let url = (obj["url"] as? String) ?? ""
        let title = (obj["title"] as? String) ?? ""
        let mode = (obj["mode"] as? String) ?? nil
        let createdAtIOS = (obj["created_at_ios"] as? String) ?? nil
        let createdAtMs = (obj["created_at_ms"] as? Int64) ?? (obj["created_at_ms"] as? Int).map(Int64.init) ?? 0

        let pdfPath = (obj["pdf_path"] as? String) ?? (obj["PDF_Path"] as? String)
        let jsonPath = (obj["json_path"] as? String) ?? (obj["JSON_Path"] as? String)

        let clipBody: String = {
            if let body = obj["body"] as? String, !body.isEmpty { return body }
            if let summary = obj["summary"] as? String, !summary.isEmpty {
                if title.isEmpty { return summary }
                return title + "\n\n" + summary
            }
            return title.isEmpty ? "" : (title + "\n\n")
        }()

        var sections: [String: Any] = [:]

        var clipData: [String: Any] = [:]
        if !website.isEmpty { clipData["website"] = website }
        if !url.isEmpty { clipData["url"] = url }
        if !title.isEmpty { clipData["title"] = title }
        if let mode { clipData["mode"] = mode }
        if let createdAtIOS { clipData["created_at_ios"] = createdAtIOS }
        if createdAtMs != 0 { clipData["created_at_ms"] = createdAtMs }
        if let pdfPath { clipData["pdf_path"] = pdfPath }
        if let jsonPath { clipData["json_path"] = jsonPath }
        clipData["body"] = clipBody

        if !clipData.isEmpty {
            sections["clip"] = [
                "v": 1,
                "data": clipData
            ]
        }

        var protonData: [String: Any] = [
            "proton_v": 1,
            "proton_json": (obj["proton_json"] as? String) ?? ""
        ]
        if !rtfBase64.isEmpty {
            protonData["rtf_base64"] = rtfBase64
        } else {
            let seeded = makeRTFBase64(title + "\n\n" + (obj["summary"] as? String ?? ""))
            protonData["rtf_base64"] = seeded
        }

        sections["proton1"] = [
            "v": 1,
            "data": protonData
        ]

        let out: [String: Any] = [
            "v": 1,
            "sections": sections
        ]

        return try encodeMinifiedJSON(out)
    }

    private static func normalizeV1Envelope(_ obj: [String: Any]) throws -> String {
        guard let sectionsAny = obj["sections"] as? [String: Any] else { throw NJPayloadConvertError.missingSections }
        var sectionsOut: [String: Any] = [:]

        if let clip = sectionsAny["clip"] as? [String: Any] {
            let sv = (clip["v"] as? Int) ?? 1
            if sv != 1 { throw NJPayloadConvertError.unsupportedSectionVersion("clip", sv) }
            let data = (clip["data"] as? [String: Any]) ?? [:]
            var dataOut = data
            if let bp = dataOut["body"] as? String { dataOut["body"] = bp }
            if dataOut["pdf_path"] == nil, let p = dataOut["PDF_Path"] { dataOut["pdf_path"] = p; dataOut.removeValue(forKey: "PDF_Path") }
            if dataOut["json_path"] == nil, let p = dataOut["JSON_Path"] { dataOut["json_path"] = p; dataOut.removeValue(forKey: "JSON_Path") }
            dataOut.removeValue(forKey: "rtf_base64")
            dataOut.removeValue(forKey: "proton_v")
            dataOut.removeValue(forKey: "proton_json")
            sectionsOut["clip"] = ["v": 1, "data": dataOut]
        }

        if let p = sectionsAny["proton1"] as? [String: Any] {
            let sv = (p["v"] as? Int) ?? 1
            if sv != 1 { throw NJPayloadConvertError.unsupportedSectionVersion("proton1", sv) }
            let data = (p["data"] as? [String: Any]) ?? [:]
            var dataOut = data
            dataOut["proton_v"] = 1
            if dataOut["proton_json"] == nil { dataOut["proton_json"] = "" }
            if let rtf = dataOut["rtf_base64"] as? String, !rtf.isEmpty {
                try validateRTFBase64(rtf)
            }
            sectionsOut["proton1"] = ["v": 1, "data": dataOut]
        }

        let out: [String: Any] = ["v": 1, "sections": sectionsOut]
        return try encodeMinifiedJSON(out)
    }

    static func makeRTFBase64(_ text: String) -> String {
        let attr = NSAttributedString(string: text)
        let r = NSRange(location: 0, length: attr.length)
        let data = try? attr.data(from: r, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        return data?.base64EncodedString() ?? ""
    }

    static func decodeRTFBase64ToPlainText(_ rtfBase64: String) throws -> String {
        try validateRTFBase64(rtfBase64)
        guard let data = Data(base64Encoded: rtfBase64) else { throw NJPayloadConvertError.invalidRTFBase64 }
        let attr = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        return attr.string
    }

    private static func validateRTFBase64(_ s: String) throws {
        if s.hasPrefix("PROTON1:") { throw NJPayloadConvertError.invalidRTFBase64 }
        guard Data(base64Encoded: s) != nil else { throw NJPayloadConvertError.invalidRTFBase64 }
    }

    private static func encodeMinifiedJSON(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
