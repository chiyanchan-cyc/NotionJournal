import UIKit

enum TextStyleToggle {
    static func toggleBold(_ attr: NSAttributedString, range: NSRange) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.font, in: range, options: []) { v, r, _ in
            let font = (v as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
            let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            var traits = font.fontDescriptor.symbolicTraits
            if isBold { traits.remove(.traitBold) } else { traits.insert(.traitBold) }
            let desc = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            let newFont = UIFont(descriptor: desc, size: font.pointSize)
            m.addAttribute(.font, value: newFont, range: r)
        }
        return m
    }

    static func toggleItalic(_ attr: NSAttributedString, range: NSRange) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.font, in: range, options: []) { v, r, _ in
            let font = (v as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
            let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            var traits = font.fontDescriptor.symbolicTraits
            if isItalic { traits.remove(.traitItalic) } else { traits.insert(.traitItalic) }
            let desc = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            let newFont = UIFont(descriptor: desc, size: font.pointSize)
            m.addAttribute(.font, value: newFont, range: r)
        }
        return m
    }

    static func toggleUnderline(_ attr: NSAttributedString, range: NSRange) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.underlineStyle, in: range, options: []) { v, r, _ in
            let cur = (v as? NSNumber)?.intValue ?? 0
            let isOn = cur != 0
            if isOn {
                m.removeAttribute(.underlineStyle, range: r)
            } else {
                m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }
        return m
    }

    static func toggleStrikethrough(_ attr: NSAttributedString, range: NSRange) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.strikethroughStyle, in: range, options: []) { v, r, _ in
            let cur = (v as? NSNumber)?.intValue ?? 0
            let isOn = cur != 0
            if isOn {
                m.removeAttribute(.strikethroughStyle, range: r)
            } else {
                m.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }
        return m
    }
}
