import UIKit

func NJEditorCanonicalBodyFont(
    size: CGFloat = 17,
    bold: Bool = false,
    italic: Bool = false
) -> UIFont {
    let weight: UIFont.Weight = bold ? .semibold : .regular
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    guard italic else { return base }
    if let nfd = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitItalic)) {
        return UIFont(descriptor: nfd, size: size)
    }
    return base
}

func NJEditorHasExplicitBoldTrait(_ font: UIFont) -> Bool {
    let descriptor = font.fontDescriptor
    let traitMap = descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
    let rawWeight = (traitMap?[.weight] as? NSNumber)?.doubleValue
        ?? Double(UIFont.Weight.regular.rawValue)

    if rawWeight >= Double(UIFont.Weight.semibold.rawValue) - 0.05 {
        return true
    }

    let normalizedName = font.fontName.lowercased()
    if normalizedName.contains("bold") || normalizedName.contains("semibold") {        return true
    }
    if normalizedName.contains("demi") || normalizedName.contains("heavy") || normalizedName.contains("black") {        return true
    }

    return false
}

func NJEditorStandardizeFontFamily(_ font: UIFont) -> UIFont {
    let fd = font.fontDescriptor
    if fd.symbolicTraits.contains(.traitMonoSpace) { return font }

    let size = font.pointSize
    let hadBoldTrait = NJEditorHasExplicitBoldTrait(font)
    let hadItalic = fd.symbolicTraits.contains(.traitItalic)
    return NJEditorCanonicalBodyFont(size: size, bold: hadBoldTrait, italic: hadItalic)
}

func NJEditorStandardizeFontFamily(_ s: NSAttributedString) -> NSAttributedString {
    if s.length == 0 { return s }
    let m = NSMutableAttributedString(attributedString: s)
    let full = NSRange(location: 0, length: m.length)
    m.beginEditing()
    m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
        guard let old = value as? UIFont else { return }
        let nf = NJEditorStandardizeFontFamily(old)
        if nf.fontName != old.fontName || nf.pointSize != old.pointSize {
            m.addAttribute(.font, value: nf, range: range)
        }
    }
    m.endEditing()
    return m
}

func NJEditorApplyBaseFontWhereMissing(_ input: NSAttributedString, baseFont: UIFont) -> NSAttributedString {
    if input.length == 0 { return input }
    let m = NSMutableAttributedString(attributedString: input)
    let full = NSRange(location: 0, length: m.length)
    m.beginEditing()
    m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
        if value == nil {
            m.addAttribute(.font, value: baseFont, range: range)
        }
    }
    m.endEditing()
    return m
}

func NJEditorCanonicalizeRichText(_ input: NSAttributedString, baseSize: CGFloat = 17) -> NSAttributedString {
    let baseFont = NJEditorCanonicalBodyFont(size: baseSize)
    return NJEditorApplyBaseFontWhereMissing(
        NJEditorStandardizeFontFamily(input),
        baseFont: baseFont
    )
}

func NJEditorNormalizeBodyText(_ input: NSAttributedString, baseSize: CGFloat = 17) -> NSAttributedString {
    NJEditorCanonicalizeRichText(input, baseSize: baseSize)
}

func NJEditorCanonicalTypingAttributes(
    _ attributes: [NSAttributedString.Key: Any],
    baseSize: CGFloat = 17
) -> [NSAttributedString.Key: Any] {
    var out = attributes
    if let font = out[.font] as? UIFont {
        out[.font] = NJEditorStandardizeFontFamily(font)
    } else {
        out[.font] = NJEditorCanonicalBodyFont(size: baseSize)
    }
    if out[.foregroundColor] == nil {
        out[.foregroundColor] = UIColor.label
    }
    return out
}
