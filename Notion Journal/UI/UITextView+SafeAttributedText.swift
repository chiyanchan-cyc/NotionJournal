import UIKit

#if canImport(Proton)
import Proton
#endif

extension UITextView {
    func setAttributedTextSafely(_ newText: NSAttributedString, targetSelection: NSRange? = nil) {
        let oldTextLength = attributedText.length
        let newTextLength = newText.length

        var loc = selectedRange.location
        if loc == NSNotFound { loc = 0 }

        let safeLoc = min(loc, min(oldTextLength, newTextLength))
        if selectedRange.location != safeLoc || selectedRange.length != 0 {
            selectedRange = NSRange(location: safeLoc, length: 0)
        }

        attributedText = newText

        if let targetSelection {
            selectedRange = clampedRange(targetSelection, in: newTextLength)
        }
    }

    private func clampedRange(_ r: NSRange, in len: Int) -> NSRange {
        if len <= 0 { return NSRange(location: 0, length: 0) }
        var loc = r.location == NSNotFound ? 0 : r.location
        loc = max(0, min(loc, len))
        var l = max(0, r.length)
        if loc + l > len { l = max(0, len - loc) }
        return NSRange(location: loc, length: l)
    }
}

#if canImport(Proton)
extension EditorView {
    func setAttributedTextSafely(_ newText: NSAttributedString, targetSelection: NSRange? = nil) {
        let oldTextLength = attributedText.length
        let newTextLength = newText.length

        var loc = selectedRange.location
        if loc == NSNotFound { loc = 0 }

        let safeLoc = min(loc, min(oldTextLength, newTextLength))
        if selectedRange.location != safeLoc || selectedRange.length != 0 {
            selectedRange = NSRange(location: safeLoc, length: 0)
        }

        attributedText = newText

        if let targetSelection {
            selectedRange = clampedRange(targetSelection, in: newTextLength)
        }
    }

    private func clampedRange(_ r: NSRange, in len: Int) -> NSRange {
        if len <= 0 { return NSRange(location: 0, length: 0) }
        var loc = r.location == NSNotFound ? 0 : r.location
        loc = max(0, min(loc, len))
        var l = max(0, r.length)
        if loc + l > len { l = max(0, len - loc) }
        return NSRange(location: loc, length: l)
    }
}
#endif
