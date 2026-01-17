//
//  NJRTF64Codec.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/13.
//


import Foundation
import UIKit

enum NJRTF64Codec {
    static func decode(_ b64: String?) -> NSAttributedString {
        guard
            let b64,
            let data = Data(base64Encoded: b64),
            let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        else {
            return NSAttributedString(string: "")
        }
        return attr
    }

    static func encode(_ attr: NSAttributedString) -> String {
        let range = NSRange(location: 0, length: attr.length)
        let data = (try? attr.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
        return data.base64EncodedString()
    }
}
