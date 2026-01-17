import Foundation
import UIKit
import Proton
import ProtonCore

typealias NJProtonJSON = [String: Any]
typealias NJProtonAttrs = [NSAttributedString.Key: Any]

struct NJProtonAuditCodec {
    static let encoder = NJProtonJSONEncoder_Audit()
    static let decoder = NJProtonJSONDecoder_Audit()
}

struct NJProtonJSONEncoder_Audit: EditorContentEncoder {
    let textEncoders: [EditorContent.Name: AnyEditorTextEncoding<NJProtonJSON>] = [
        .paragraph: AnyEditorTextEncoding(NJProtonParagraphEncoder_Audit()),
        .text: AnyEditorTextEncoding(NJProtonTextEncoder_Audit())
    ]

    let attachmentEncoders: [EditorContent.Name: AnyEditorContentAttachmentEncoding<NJProtonJSON>] = [:]
}

private struct NJProtonParagraphEncoder_Audit: EditorTextEncoding {
    func encode(name: EditorContent.Name, string: NSAttributedString) -> NJProtonJSON {
        var json: NJProtonJSON = [:]
        json["type"] = name.rawValue

        if let ps = string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            json["paragraphStyle"] = ps.nj_protonJSONValue
        }

        json["contents"] = contentsFrom(string)
        return json
    }
}

private extension EditorTextEncoding where EncodedType == NJProtonJSON {
    func contentsFrom(_ string: NSAttributedString) -> [NJProtonJSON] {
        var out: [NJProtonJSON] = []

        string.enumerateInlineContents().forEach { content in
            switch content.type {
            case .viewOnly:
                break
            case let .text(name, attributedString):
                if let encoder = NJProtonJSONEncoder_Audit().textEncoders[name] {
                    out.append(encoder.encode(name: name, string: attributedString))
                }
            case .attachment:
                break
            }
        }

        return out
    }
}

private struct NJProtonTextEncoder_Audit: EditorTextEncoding {
    func encode(name: EditorContent.Name, string: NSAttributedString) -> NJProtonJSON {
        var json: NJProtonJSON = [:]
        json["type"] = name.rawValue
        json["text"] = string.string

        var attributesJSON: NJProtonJSON = [:]

        string.enumerateAttributes(in: string.fullRange, options: .longestEffectiveRangeNotRequired) { attrs, _, _ in
            if attributesJSON["font"] == nil, let font = attrs[.font] as? UIFont {
                attributesJSON["font"] = font.nj_protonJSONValue
            }

            if attributesJSON["paragraphStyle"] == nil, let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
                attributesJSON["paragraphStyle"] = ps.nj_protonJSONValue
            }

            if attributesJSON["foregroundColor"] == nil, let c = attrs[.foregroundColor] as? UIColor {
                attributesJSON["foregroundColor"] = c.nj_rgbaJSONValue
            }

            if attributesJSON["backgroundColor"] == nil, let c = attrs[.backgroundColor] as? UIColor {
                attributesJSON["backgroundColor"] = c.nj_rgbaJSONValue
            }

            if attributesJSON["underline"] == nil, attrs[.underlineStyle] != nil {
                attributesJSON["underline"] = true
            }

            if attributesJSON["strike"] == nil, attrs[.strikethroughStyle] != nil {
                attributesJSON["strike"] = true
            }

            if attributesJSON["listItem"] == nil, let li = attrs[.listItem] {
                if let tl = li as? NSTextList {
                    attributesJSON["listItem"] = [
                        "kind": "textList",
                        "markerFormat": (tl.markerFormat == .decimal) ? "decimal" : "disc",
                        "startingItemNumber": tl.startingItemNumber
                    ]
                } else if let tls = li as? [NSTextList] {
                    attributesJSON["listItem"] = [
                        "kind": "textListArray",
                        "value": tls.map { tl in
                            [
                                "markerFormat": (tl.markerFormat == .decimal) ? "decimal" : "disc",
                                "startingItemNumber": tl.startingItemNumber
                            ]
                        }
                    ]
                } else if let s = li as? String {
                    attributesJSON["listItem"] = [
                        "kind": "string",
                        "value": s
                    ]
                } else {
                    attributesJSON["listItem"] = [
                        "kind": "raw",
                        "value": String(describing: li)
                    ]
                }
            }
        }

        if !attributesJSON.isEmpty {
            json["attributes"] = attributesJSON
        }

        return json
    }
}

struct NJProtonJSONDecoder_Audit: EditorContentDecoding {
    func decode(mode: EditorContentMode, maxSize: CGSize, value: NJProtonJSON, context: Void?) throws -> NSAttributedString {
        let out = NSMutableAttributedString()
        let contents = (value["contents"] as? [Any]) ?? []
        for any in contents {
            guard let node = any as? NJProtonJSON else { continue }
            out.append(try decodeNode(mode: mode, maxSize: maxSize, node: node))
        }
        return out
    }

    func decodeDocument(mode: EditorContentMode, maxSize: CGSize, json: String) throws -> NSAttributedString {
        guard let data = json.data(using: .utf8) else { return NSAttributedString(string: "") }
        let rootAny = try JSONSerialization.jsonObject(with: data, options: [])
        guard let paras = rootAny as? [Any] else { return NSAttributedString(string: "") }

        let out = NSMutableAttributedString()

        for any in paras {
            guard let node = any as? NJProtonJSON else { continue }
            out.append(try decodeNode(mode: mode, maxSize: maxSize, node: node))
        }

        return out
    }

    private func decodeNode(mode: EditorContentMode, maxSize: CGSize, node: NJProtonJSON) throws -> NSAttributedString {
        var type = (node["type"] as? String) ?? ""
        if type.hasPrefix("_") { type.removeFirst() }

        if type == "paragraph" {
            return try decodeParagraph(mode: mode, maxSize: maxSize, node: node)
        }

        if type == "text" {
            return decodeText(node)
        }

        return NSAttributedString(string: "")
    }

    private func decodeParagraph(mode: EditorContentMode, maxSize: CGSize, node: NJProtonJSON) throws -> NSAttributedString {
        let result = NSMutableAttributedString()

        let contents = (node["contents"] as? [Any]) ?? []
        for any in contents {
            guard let child = any as? NJProtonJSON else { continue }
            result.append(try decodeNode(mode: mode, maxSize: maxSize, node: child))
        }

        result.append(NSAttributedString(string: "\n"))

        if let psJSON = node["paragraphStyle"] as? NJProtonJSON {
            let ps = decodeParagraphStyle(psJSON)
            result.addAttribute(.paragraphStyle, value: ps, range: result.fullRange)
        }

        return result
    }

    private func decodeText(_ node: NJProtonJSON) -> NSAttributedString {
        let text = (node["text"] as? String) ?? ""
        let out = NSMutableAttributedString(string: text)

        guard let attrs = node["attributes"] as? NJProtonJSON else {
            return out
        }

        if let fontJSON = attrs["font"] as? NJProtonJSON {
            out.addAttribute(.font, value: decodeFont(fontJSON), range: out.fullRange)
        }

        if let psJSON = attrs["paragraphStyle"] as? NJProtonJSON {
            out.addAttribute(.paragraphStyle, value: decodeParagraphStyle(psJSON), range: out.fullRange)
        }

        if let li = attrs["listItem"] {
            if let d = li as? NJProtonJSON {
                let kind = (d["kind"] as? String) ?? ""
                if kind == "textList" {
                    let mf = (d["markerFormat"] as? String) == "decimal" ? NSTextList.MarkerFormat.decimal : .disc
                    let tl = NSTextList(markerFormat: mf, options: 0)
                    if let s = d["startingItemNumber"] as? Int { tl.startingItemNumber = s }
                    out.addAttribute(.listItem, value: tl, range: out.fullRange)
                } else if kind == "textListArray" {
                    let arr = (d["value"] as? [Any]) ?? []
                    let tls: [NSTextList] = arr.compactMap { any in
                        guard let dd = any as? NJProtonJSON else { return nil }
                        let mf = (dd["markerFormat"] as? String) == "decimal" ? NSTextList.MarkerFormat.decimal : .disc
                        let tl = NSTextList(markerFormat: mf, options: 0)
                        if let s = dd["startingItemNumber"] as? Int { tl.startingItemNumber = s }
                        return tl
                    }
                    if !tls.isEmpty {
                        out.addAttribute(.listItem, value: tls, range: out.fullRange)
                    }
                } else if kind == "string" {
                    if let s = d["value"] as? String {
                        out.addAttribute(.listItem, value: s, range: out.fullRange)
                    }
                }
            } else if let s = li as? String {
                out.addAttribute(.listItem, value: s, range: out.fullRange)
            }
        }

        if let c = attrs["foregroundColor"] as? NJProtonJSON {
            out.addAttribute(.foregroundColor, value: decodeColor(c), range: out.fullRange)
        }

        if let c = attrs["backgroundColor"] as? NJProtonJSON {
            out.addAttribute(.backgroundColor, value: decodeColor(c), range: out.fullRange)
        }

        if attrs["strike"] as? Bool == true {
            out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: out.fullRange)
        }

        if attrs["underline"] as? Bool == true {
            out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: out.fullRange)
        }

        return out
    }

    private func decodeColor(_ json: NJProtonJSON) -> UIColor {
        let r = json["r"] as? CGFloat ?? 0
        let g = json["g"] as? CGFloat ?? 0
        let b = json["b"] as? CGFloat ?? 0
        let a = json["a"] as? CGFloat ?? 1
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private func decodeParagraphStyle(_ json: NJProtonJSON) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()

        if let v = json["alignment"] as? Int, let a = NSTextAlignment(rawValue: v) { style.alignment = a }
        if let v = json["firstLineHeadIndent"] as? CGFloat { style.firstLineHeadIndent = v }
        if let v = json["headIndent"] as? CGFloat { style.headIndent = v }
        if let v = json["tailIndent"] as? CGFloat { style.tailIndent = v }
        if let v = json["lineSpacing"] as? CGFloat { style.lineSpacing = v }
        if let v = json["paragraphSpacing"] as? CGFloat { style.paragraphSpacing = v }
        if let v = json["paragraphSpacingBefore"] as? CGFloat { style.paragraphSpacingBefore = v }
        if let v = json["lineHeightMultiple"] as? CGFloat { style.lineHeightMultiple = v }
        if let v = json["minimumLineHeight"] as? CGFloat { style.minimumLineHeight = v }
        if let v = json["maximumLineHeight"] as? CGFloat { style.maximumLineHeight = v }

        if let arr = json["textLists"] as? [Any] {
            let tls: [NSTextList] = arr.compactMap { any in
                guard let d = any as? NJProtonJSON else { return nil }
                let mf = (d["markerFormat"] as? String) == "decimal" ? NSTextList.MarkerFormat.decimal : .disc
                let tl = NSTextList(markerFormat: mf, options: 0)
                if let s = d["startingItemNumber"] as? Int { tl.startingItemNumber = s }
                return tl
            }
            style.textLists = tls
        }

        return style
    }

    private func decodeFont(_ json: NJProtonJSON) -> UIFont {
        let size = json["size"] as? CGFloat ?? UIFont.systemFontSize
        let family = json["family"] as? String
        let styleName = json["textStyle"] as? String

        var fontDescriptor: UIFontDescriptor
        if let styleName {
            fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: UIFont.TextStyle(rawValue: styleName))
        } else {
            fontDescriptor = UIFont.systemFont(ofSize: size).fontDescriptor
        }

        if let family {
            fontDescriptor = fontDescriptor.withFamily(family)
        }

        var traits = fontDescriptor.symbolicTraits
        if json["isBold"] as? Bool == true { traits.formUnion(.traitBold) }
        if json["isItalics"] as? Bool == true { traits.formUnion(.traitItalic) }
        if json["isMonospace"] as? Bool == true { traits.formUnion(.traitMonoSpace) }

        if let updated = fontDescriptor.withSymbolicTraits(traits) {
            fontDescriptor = updated
        }

        return UIFont(descriptor: fontDescriptor, size: size)
    }
}

private extension UIFont {
    var nj_protonJSONValue: NJProtonJSON {
        let d = fontDescriptor
        return [
            "name": fontName,
            "family": familyName,
            "size": d.pointSize,
            "isBold": d.symbolicTraits.contains(.traitBold),
            "isItalics": d.symbolicTraits.contains(.traitItalic),
            "isMonospace": d.symbolicTraits.contains(.traitMonoSpace),
            "textStyle": d.object(forKey: .textStyle) as? String ?? "UICTFontTextStyleBody"
        ]
    }
}

private extension NSParagraphStyle {
    var nj_protonJSONValue: NJProtonJSON {
        var o: NJProtonJSON = [
            "alignment": alignment.rawValue,
            "firstLineHeadIndent": firstLineHeadIndent,
            "headIndent": headIndent,
            "tailIndent": tailIndent,
            "lineSpacing": lineSpacing,
            "paragraphSpacing": paragraphSpacing,
            "paragraphSpacingBefore": paragraphSpacingBefore,
            "lineHeightMultiple": lineHeightMultiple,
            "minimumLineHeight": minimumLineHeight,
            "maximumLineHeight": maximumLineHeight
        ]

        if !textLists.isEmpty {
            o["textLists"] = textLists.map { tl in
                [
                    "markerFormat": (tl.markerFormat == .decimal) ? "decimal" : "disc",
                    "startingItemNumber": tl.startingItemNumber
                ]
            }
        }

        return o
    }
}

private extension UIColor {
    var nj_rgbaJSONValue: NJProtonJSON {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return ["r": r, "g": g, "b": b, "a": a]
    }
}

