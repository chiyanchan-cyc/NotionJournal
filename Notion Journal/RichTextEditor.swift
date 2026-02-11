import SwiftUI
import UIKit

struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var selection: NSRange
    var onCtrlReturn: () -> Void

    init(attributedText: Binding<NSAttributedString>, selection: Binding<NSRange>, onCtrlReturn: @escaping () -> Void) {
        _attributedText = attributedText
        _selection = selection
        self.onCtrlReturn = onCtrlReturn
    }

    private func normalizeForAppearance(_ attr: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: m.length)

        m.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value != nil {
                m.removeAttribute(.foregroundColor, range: range)
            }
        }

        m.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        return m
    }

    func makeUIView(context: Context) -> AutoSizingTextView {
        let tv = AutoSizingTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 2, bottom: 6, right: 2)
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        let normalized = normalizeForAppearance(attributedText)
        tv.attributedText = normalized
        tv.selectedRange = clampedRange(selection, in: normalized.length)
        tv.autocorrectionType = .yes
        tv.spellCheckingType = .yes
        tv.smartQuotesType = .yes
        tv.smartDashesType = .yes
        tv.smartInsertDeleteType = .yes
        tv.onCmdReturn = onCtrlReturn
        tv.applyBodyTypingDefaults()
        return tv
    }

    func updateUIView(_ uiView: AutoSizingTextView, context: Context) {
        uiView.onCmdReturn = onCtrlReturn

        let normalized = normalizeForAppearance(attributedText)
        let safeSelection = clampedRange(selection, in: normalized.length)

        if !context.coordinator.isProgrammatic {
            if uiView.attributedText != normalized {
                context.coordinator.isProgrammatic = true
                uiView.setAttributedTextSafely(normalized, targetSelection: safeSelection)
                context.coordinator.isProgrammatic = false
            }

            if uiView.selectedRange.location != safeSelection.location || uiView.selectedRange.length != safeSelection.length {
                context.coordinator.isProgrammatic = true
                uiView.selectedRange = safeSelection
                context.coordinator.isProgrammatic = false
            }
        }

        uiView.applyBodyTypingDefaults()
        uiView.invalidateIntrinsicContentSize()
    }

    private func clampedRange(_ r: NSRange, in len: Int) -> NSRange {
        if len <= 0 { return NSRange(location: 0, length: 0) }
        var loc = r.location == NSNotFound ? 0 : r.location
        loc = max(0, min(loc, len))
        var l = max(0, r.length)
        if loc + l > len { l = max(0, len - loc) }
        return NSRange(location: loc, length: l)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: RichTextEditor
        var isProgrammatic = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammatic else { return }
            parent.attributedText = textView.attributedText
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammatic else { return }
            parent.selection = textView.selectedRange
        }
        
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            true
        }

    }
}

final class AutoSizingTextView: UITextView {
    var onCmdReturn: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        if isScrollEnabled { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let w = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let size = sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\r", modifierFlags: [.command], action: #selector(cmdReturn)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabIndent)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(tabOutdent))
        ]
    }

    func applyBodyTypingDefaults() {
        var t = typingAttributes
        if t[.font] == nil { t[.font] = UIFont.preferredFont(forTextStyle: .body) }
        if t[.foregroundColor] == nil { t[.foregroundColor] = UIColor.label }
        if t[.paragraphStyle] == nil {
            let p = NSMutableParagraphStyle()
            p.alignment = .natural
            p.defaultTabInterval = 28
            t[.paragraphStyle] = p
        }
        typingAttributes = t
    }

    @objc private func cmdReturn() {
        if markedTextRange != nil { return }
        onCmdReturn?()
    }

    @objc private func tabIndent() { applyIndent(delta: 1) }
    @objc private func tabOutdent() { applyIndent(delta: -1) }

    private func applyIndent(delta: Int) {
        if markedTextRange != nil { return }
        let full = attributedText ?? NSAttributedString(string: "")
        let m = NSMutableAttributedString(attributedString: full)
        let ns = m.string as NSString
        let len = ns.length
        var sel = selectedRange
        if sel.location == NSNotFound { return }
        sel = safeRange(sel, in: len)

        let indentWidth: CGFloat = 28

        let target: NSRange
        if sel.length == 0 {
            target = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        } else {
            target = ns.lineRange(for: sel)
        }

        var starts: [Int] = []
        var i = target.location
        starts.append(i)
        while i < target.location + target.length {
            if ns.character(at: i) == 10 {
                let n = i + 1
                if n < target.location + target.length { starts.append(n) }
            }
            i += 1
        }

        for s0 in starts {
            if s0 >= len { continue }
            let attrs = m.attributes(at: s0, effectiveRange: nil)
            let p0 = (attrs[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
            let mp = (p0.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()

            let cur = max(mp.firstLineHeadIndent, mp.headIndent)
            let curLevel = Int(round(cur / indentWidth))
            let nextLevel = max(0, curLevel + delta)
            let base = CGFloat(nextLevel) * indentWidth

            mp.firstLineHeadIndent = base
            mp.headIndent = base
            mp.defaultTabInterval = indentWidth

            let lr = ns.lineRange(for: NSRange(location: s0, length: 0))
            m.addAttribute(.paragraphStyle, value: mp, range: lr)
        }

        attributedText = m
        selectedRange = sel
        delegate?.textViewDidChange?(self)
    }

    private func safeRange(_ r: NSRange, in len: Int) -> NSRange {
        if len <= 0 { return NSRange(location: 0, length: 0) }
        var loc = max(0, min(r.location, len))
        var l = max(0, r.length)
        if loc + l > len { l = max(0, len - loc) }
        return NSRange(location: loc, length: l)
    }
}
