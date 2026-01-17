//
//  NJTextRTFCloudMapper.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/3.
//


import Foundation

enum NJTextRTFCloudMapper {
    static let blockType: String = "text"

    static func isTextRTFBlockType(_ s: String) -> Bool {
        s == blockType
    }

    static func validatePayloadJSON(_ payloadJSON: String) -> Bool {
        guard let d = payloadJSON.data(using: .utf8) else { return false }
        guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return obj["rtf_base64"] is String
    }
}
