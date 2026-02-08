import Foundation
import UIKit

struct NJTagExtractionResult {
    let tags: [String]
    let cleaned: NSAttributedString
}

enum NJTagExtraction {

    static func extract(from attr: NSAttributedString) -> NJTagExtractionResult? {
        extract(from: attr, existingTags: [])
    }

    static func extract(from attr: NSAttributedString, existingTags: [String]) -> NJTagExtractionResult? {
        let s0 = attr.string as NSString
        let full = NSRange(location: 0, length: s0.length)

        var foundLine: String? = nil
        var foundEnclosingRange: NSRange? = nil

        s0.enumerateSubstrings(in: full, options: [.byLines]) { substring, range, enclosingRange, stop in
            guard var line = substring else { return }

            line = line.replacingOccurrences(of: "\u{200B}", with: "")
            if line.hasSuffix("\r") { line.removeLast() }

            if isValidTagLine(line) {
                foundLine = line
                foundEnclosingRange = enclosingRange
                stop.pointee = true
            }
        }

        guard let tagLine = foundLine, let removeRange = foundEnclosingRange else { return nil }

        let incoming = parseTags(from: tagLine)
        if incoming.isEmpty { return nil }

        let merged = Array(Set(existingTags).union(incoming)).sorted()

        let cleanedAttr = NSMutableAttributedString(attributedString: attr)
        if removeRange.location != NSNotFound, removeRange.location + removeRange.length <= cleanedAttr.length {
            cleanedAttr.deleteCharacters(in: removeRange)
        }

        return NJTagExtractionResult(tags: merged, cleaned: cleanedAttr)
    }

    private static func isValidTagLine(_ line: String) -> Bool {
        if line.hasPrefix(" ") { return false }
        if line.hasPrefix("\t") { return false }
        return line.hasPrefix("@tag:")
    }

    private static func parseTags(from line: String) -> [String] {
        let raw = line.dropFirst(5)
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0 != "#" }
    }
}
