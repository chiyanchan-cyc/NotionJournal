////
////  NJProtonJSONDecoder.swift
////  Notion Journal
////
////  Created by Mac on 2026/1/14.
////
//
//
//import Foundation
//import UIKit
//
//struct NJProtonJSONDecoder {
//    typealias JSON = [String: Any]
//    typealias Attributes = [NSAttributedString.Key: Any]
//
//    static func decodeDocument(jsonString: String, maxWidth: CGFloat) -> NSAttributedString? {
//        guard let data = jsonString.data(using: .utf8) else { return nil }
//        let any = try? JSONSerialization.jsonObject(with: data, options: [])
//        guard let contents = any as? [Any] else { return nil }
//
//        let out = NSMutableAttributedString(attributedString: decodeContents(contents, maxSize: CGSize(width: maxWidth, height: 1000000)))
//        applyListHeuristics(out)
//        return out
//    }
//
//    private static func applyListHeuristics(_ s: NSMutableAttributedString) {
//        let ns = s.string as NSString
//        var i = 0
//        while i < ns.length {
//            let pr = ns.paragraphRange(for: NSRange(location: i, length: 0))
//            if pr.length == 0 { break }
//
//            let line = ns.substring(with: pr)
//            let trimmed = line.trimmingCharacters(in: .newlines)
//
//            if trimmed.hasPrefix("\u{200B}") {
//                let after = String(trimmed.dropFirst())
//                let next = after.drop(while: { $0 == " " || $0 == "\t" }).first
//
//                let isNumber = next.map { $0 >= "0" && $0 <= "9" } ?? false
//                let mf: NSTextList.MarkerFormat = isNumber ? .decimal : .disc
//
//                let existing = s.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
//                let ps = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
//
//                ps.firstLineHeadIndent = 24
//                ps.headIndent = 24
//                ps.paragraphSpacingBefore = 2
//                ps.paragraphSpacing = 2
//                ps.textLists = [NSTextList(markerFormat: mf, options: 0)]
//
//                s.addAttribute(.paragraphStyle, value: ps, range: pr)
//            }
//
//            i = pr.location + pr.length
//        }
//    }
//
//    private static func decodeContents(_ contents: [Any], maxSize: CGSize) -> NSAttributedString {
//        let out = NSMutableAttributedString()
//        for item in contents {
//            guard let node = item as? JSON else { continue }
//            out.append(decodeNode(node, maxSize: maxSize))
//        }
//        return out
//    }
//
//    private static func decodeNode(_ value: JSON, maxSize: CGSize) -> NSAttributedString {
//        var type = value["type"] as? String ?? ""
//        if type.hasPrefix("_") { type.removeFirst() }
//
//        if type == "paragraph" {
//            return decodeParagraph(value, maxSize: maxSize)
//        }
//        if type == "text" {
//            return decodeText(value)
//        }
//        return NSAttributedString(string: "")
//    }
//
//    private static func decodeParagraph(_ value: JSON, maxSize: CGSize) -> NSAttributedString {
//        let result = NSMutableAttributedString()
//
//        if let contents = value["contents"] as? [Any] {
//            result.append(decodeContents(contents, maxSize: maxSize))
//        }
//
//        result.append(NSAttributedString(string: "\n"))
//
//        guard let psJSON = value["paragraphStyle"] as? JSON else {
//            return result
//        }
//
//        let ps = NSMutableParagraphStyle()
//
//        if let v = psJSON["alignment"] as? Int {
//            ps.alignment = NSTextAlignment(rawValue: v) ?? ps.alignment
//        }
//        if let v = psJSON["firstLineHeadIndent"] as? CGFloat {
//            ps.firstLineHeadIndent = v
//        }
//        if let v = psJSON["headIndent"] as? CGFloat {
//            ps.headIndent = v
//        }
//        if let v = psJSON["tailIndent"] as? CGFloat {
//            ps.tailIndent = v
//        }
//        if let v = psJSON["lineSpacing"] as? CGFloat {
//            ps.lineSpacing = v
//        }
//        if let v = psJSON["paragraphSpacing"] as? CGFloat {
//            ps.paragraphSpacing = v
//        }
//        if let v = psJSON["paragraphSpacingBefore"] as? CGFloat {
//            ps.paragraphSpacingBefore = v
//        }
//        if let v = psJSON["lineHeightMultiple"] as? CGFloat {
//            ps.lineHeightMultiple = v
//        }
//        if let v = psJSON["minimumLineHeight"] as? CGFloat {
//            ps.minimumLineHeight = v
//        }
//        if let v = psJSON["maximumLineHeight"] as? CGFloat {
//            ps.maximumLineHeight = v
//        }
//
//        result.addAttribute(.paragraphStyle, value: ps, range: result.fullRange)
//        return result
//    }
//
//    private static func decodeText(_ value: JSON) -> NSAttributedString {
//        let text = value["text"] as? String ?? ""
//        let out = NSMutableAttributedString(string: text)
//
//        guard let attrs = value["attributes"] as? JSON else {
//            return out
//        }
//
//        if let fontJSON = attrs["font"] as? JSON {
//            out.addAttributes(decodeFont(fontJSON), range: out.fullRange)
//        }
//
//        if let c = attrs["foregroundColor"] as? JSON {
//            out.addAttribute(.foregroundColor, value: decodeColor(c), range: out.fullRange)
//        }
//
//        if attrs["strike"] as? Bool == true {
//            out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: out.fullRange)
//        }
//
//        if attrs["underline"] as? Bool == true {
//            out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: out.fullRange)
//        }
//
//        return out
//    }
//
//    private static func decodeColor(_ json: JSON) -> UIColor {
//        let r = json["r"] as? CGFloat ?? 0
//        let g = json["g"] as? CGFloat ?? 0
//        let b = json["b"] as? CGFloat ?? 0
//        let a = json["a"] as? CGFloat ?? 1
//        return UIColor(red: r, green: g, blue: b, alpha: a)
//    }
//
//    private static func decodeParagraphStyle(_ json: JSON) -> Attributes {
//        let style = NSMutableParagraphStyle()
//
//        if let v = json["alignment"] as? Int { style.alignment = .init(rawValue: v) ?? .natural }
//        if let v = json["firstLineHeadIndent"] as? CGFloat { style.firstLineHeadIndent = v }
//        if let v = json["headIndent"] as? CGFloat { style.headIndent = v }
//        if let v = json["tailIndent"] as? CGFloat { style.tailIndent = v }
//        if let v = json["lineSpacing"] as? CGFloat { style.lineSpacing = v }
//        if let v = json["paragraphSpacing"] as? CGFloat { style.paragraphSpacing = v }
//        if let v = json["paragraphSpacingBefore"] as? CGFloat { style.paragraphSpacingBefore = v }
//        if let v = json["lineHeightMultiple"] as? CGFloat { style.lineHeightMultiple = v }
//        if let v = json["minimumLineHeight"] as? CGFloat { style.minimumLineHeight = v }
//        if let v = json["maximumLineHeight"] as? CGFloat { style.maximumLineHeight = v }
//
//        if let arr = json["textLists"] as? [Any] {
//            style.textLists = arr.compactMap {
//                guard let d = $0 as? JSON else { return nil }
//                let mf: NSTextList.MarkerFormat =
//                    (d["markerFormat"] as? String) == "decimal" ? .decimal : .disc
//                return NSTextList(markerFormat: mf, options: 0)
//            }
//        }
//
//        return [.paragraphStyle: style]
//    }
//
//    
//    private static func decodeFont(_ json: JSON) -> Attributes {
//        let size = json["size"] as? CGFloat ?? UIFont.systemFontSize
//        let family = json["family"] as? String
//        let name = json["name"] as? String
//
//        var fontDescriptor: UIFontDescriptor
//        if let name {
//            fontDescriptor = UIFontDescriptor(name: name, size: size)
//        } else if let family {
//            fontDescriptor = UIFontDescriptor(fontAttributes: [.family: family])
//        } else {
//            fontDescriptor = UIFont.systemFont(ofSize: size).fontDescriptor
//        }
//
//        var traits = fontDescriptor.symbolicTraits
//        if json["isBold"] as? Bool == true { traits.formUnion(.traitBold) }
//        if json["isItalics"] as? Bool == true { traits.formUnion(.traitItalic) }
//        if json["isMonospace"] as? Bool == true { traits.formUnion(.traitMonoSpace) }
//
//        if let updated = fontDescriptor.withSymbolicTraits(traits) {
//            fontDescriptor = updated
//        }
//
//        let font = UIFont(descriptor: fontDescriptor, size: size)
//        return [.font: font]
//    }
//}
//
//private extension NSMutableAttributedString {
//    var fullRange: NSRange { NSRange(location: 0, length: length) }
//}
