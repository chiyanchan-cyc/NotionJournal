////
////  NJProtonJSONEncoder 2.swift
////  Notion Journal
////
////  Created by Mac on 2026/1/14.
////
//
//
//import Foundation
//import UIKit
//import Proton
//import ProtonCore
//
//typealias NJProtonJSON = [String: Any]
//
//struct NJProtonJSONEncoder: EditorContentEncoder {
//    let textEncoders: [EditorContent.Name: AnyEditorTextEncoding<NJProtonJSON>] = [
//        .paragraph: AnyEditorTextEncoding(NJProtonParagraphEncoder()),
//        .text: AnyEditorTextEncoding(NJProtonTextEncoder())
//    ]
//
//    let attachmentEncoders: [EditorContent.Name: AnyEditorContentAttachmentEncoding<NJProtonJSON>] = [:]
//}
//
//private struct NJProtonParagraphEncoder: EditorTextEncoding {
//    func encode(name: EditorContent.Name, string: NSAttributedString) -> NJProtonJSON {
//        var json: NJProtonJSON = [:]
//        json["type"] = name.rawValue
//
//        let full = NSRange(location: 0, length: string.length)
//        var paragraphStyleJSON: NJProtonJSON?
//        string.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, _, stop in
//            if let ps = value as? NSParagraphStyle {
//                paragraphStyleJSON = ps.nj_protonJSONValue
//                stop.pointee = true
//            }
//        }
//        if let paragraphStyleJSON {
//            json["paragraphStyle"] = paragraphStyleJSON
//        }
//
//        json["contents"] = NJProtonParagraphEncoder.contentsFrom(string)
//        return json
//    }
//
//    private static func contentsFrom(_ string: NSAttributedString) -> [NJProtonJSON] {
//        var contents: [NJProtonJSON] = []
//
//        string.enumerateInlineContents().forEach { content in
//            switch content.type {
//            case .viewOnly:
//                break
//            case let .text(name, attributedString):
//                if let encoder = NJProtonJSONEncoder().textEncoders[name] {
//                    contents.append(encoder.encode(name: name, string: attributedString))
//                }
//            case let .attachment(name, _, contentView, _):
//                if let encodable = NJProtonJSONEncoder().attachmentEncoders[name] {
//                    contents.append(encodable.encode(name: name, view: contentView))
//                }
//            }
//        }
//
//        return contents
//    }
//}
//
//private struct NJProtonTextEncoder: EditorTextEncoding {
//    func encode(name: EditorContent.Name, string: NSAttributedString) -> NJProtonJSON {
//        var json: NJProtonJSON = [:]
//        json["type"] = name.rawValue
//        json["text"] = string.string
//
//        guard string.length > 0 else { return json }
//
//        let attrs = string.attributes(at: 0, effectiveRange: nil)
//        var attributesJSON: NJProtonJSON = [:]
//
//        if let font = attrs[.font] as? UIFont {
//            attributesJSON["font"] = font.nj_protonJSONValue
//        }
//
//        if let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
//            attributesJSON["paragraphStyle"] = ps.nj_protonJSONValue
//        }
//
//        if let c = attrs[.foregroundColor] as? UIColor {
//            attributesJSON["foregroundColor"] = c.nj_rgbaJSONValue
//        }
//
//        if let c = attrs[.backgroundColor] as? UIColor {
//            attributesJSON["backgroundColor"] = c.nj_rgbaJSONValue
//        }
//
//        if (attrs[.underlineStyle] as? Int ?? 0) != 0 {
//            attributesJSON["underline"] = true
//        }
//
//        if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 {
//            attributesJSON["strike"] = true
//        }
//
//        if !attributesJSON.isEmpty {
//            json["attributes"] = attributesJSON
//        }
//
//        return json
//    }
//}
//
//private extension UIFont {
//    var nj_protonJSONValue: NJProtonJSON {
//        let d = fontDescriptor
//        return [
//            "name": fontName,
//            "family": familyName,
//            "size": d.pointSize,
//            "isBold": d.symbolicTraits.contains(.traitBold),
//            "isItalics": d.symbolicTraits.contains(.traitItalic),
//            "isMonospace": d.symbolicTraits.contains(.traitMonoSpace),
//            "textStyle": d.object(forKey: .textStyle) as? String ?? "UICTFontTextStyleBody"
//        ]
//    }
//}
//
//private extension NSParagraphStyle {
//    var nj_protonJSONValue: NJProtonJSON {
//        var o: NJProtonJSON = [
//            "alignment": alignment.rawValue,
//            "firstLineHeadIndent": firstLineHeadIndent,
//            "headIndent": headIndent,
//            "tailIndent": tailIndent,
//            "lineSpacing": lineSpacing,
//            "paragraphSpacing": paragraphSpacing,
//            "paragraphSpacingBefore": paragraphSpacingBefore,
//            "lineHeightMultiple": lineHeightMultiple,
//            "minimumLineHeight": minimumLineHeight,
//            "maximumLineHeight": maximumLineHeight
//        ]
//
//        if !textLists.isEmpty {
//            o["textLists"] = textLists.map { tl in
//                [
//                    "markerFormat": (tl.markerFormat == .decimal) ? "decimal" : "disc",
//                    "startingItemNumber": tl.startingItemNumber
//                ]
//            }
//        }
//
//        return o
//    }
//}
//
//private extension UIColor {
//    var nj_rgbaJSONValue: NJProtonJSON {
//        var r: CGFloat = 0
//        var g: CGFloat = 0
//        var b: CGFloat = 0
//        var a: CGFloat = 0
//        getRed(&r, green: &g, blue: &b, alpha: &a)
//        return ["r": r, "g": g, "b": b, "a": a]
//    }
//}
