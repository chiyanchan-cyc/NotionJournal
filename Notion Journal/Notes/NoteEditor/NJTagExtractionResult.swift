import Foundation
import UIKit

struct NJTagExtractionResult {
    let tags: [String]
    let cleaned: NSAttributedString
}

enum NJTagExtraction {

    static func extract(from attr: NSAttributedString) -> NJTagExtractionResult? {
        let s0 = attr.string
        let normalized = s0
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{200B}", with: "")

        let lines = normalized.components(separatedBy: "\n")
        guard let idx = lines.firstIndex(where: isValidTagLine) else { return nil }

        let tags = parseTags(from: lines[idx])
        if tags.isEmpty { return nil }

        let ns = normalized as NSString
        var start = 0
        for _ in 0..<idx {
            let r = ns.lineRange(for: NSRange(location: start, length: 0))
            start = r.location + r.length
        }
        let removeRange = ns.lineRange(for: NSRange(location: start, length: 0))

        let cleanedAttr = NSMutableAttributedString(attributedString: attr)
        if removeRange.location != NSNotFound, removeRange.location + removeRange.length <= cleanedAttr.length {
            cleanedAttr.deleteCharacters(in: removeRange)
        }

        let unique = Array(Set(tags)).sorted()
        return NJTagExtractionResult(tags: unique, cleaned: cleanedAttr)
    }


    private static func isValidTagLine(_ line: String) -> Bool {
        let l = line.replacingOccurrences(of: "\u{200B}", with: "")
        if l.hasPrefix(" ") { return false }
        if l.hasPrefix("\t") { return false }
        return l.hasPrefix("@tag:")
    }

    private static func parseTags(from line: String) -> [String] {
        let raw = line.dropFirst(5)
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
