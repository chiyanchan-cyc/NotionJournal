//
//  NJGoalPayloadV1.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/10.
//


import Foundation
import UIKit

struct NJGoalPayloadV1: Codable {
    let v: Int
    let name: String
    let rtf64: String

    static func make(name: String, plainText: String) -> NJGoalPayloadV1 {
        let s = NSAttributedString(string: plainText)
        let rtf = (try? s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        return NJGoalPayloadV1(v: 1, name: name, rtf64: rtf.base64EncodedString())
    }

    func toJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = []
        let d = (try? enc.encode(self)) ?? Data()
        return String(data: d, encoding: .utf8) ?? ""
    }
}
