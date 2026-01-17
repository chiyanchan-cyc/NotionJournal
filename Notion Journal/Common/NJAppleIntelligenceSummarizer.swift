import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum NJAppleIntelligenceSummarizer {
    struct Result {
        let title: String?
        let summary: String?
        let error: String?
        let mode: String
    }

    static func summarizeAuto(text: String) async -> Result {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return Result(title: "", summary: "", error: nil, mode: "empty") }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .unavailable:
                return Result(title: nil, summary: nil, error: "Apple Intelligence unavailable", mode: "unavailable")
            case .available:
                let hardMaxSourceChars = 200000
                let source = t.count > hardMaxSourceChars ? String(t.prefix(hardMaxSourceChars)) : t

                let singleLimitChars = 12000
                if source.count <= singleLimitChars {
                    let r = await summarizeSingle(model: model, text: source)
                    return Result(title: r.title, summary: r.summary, error: r.error, mode: "single")
                }

                let chunks = chunkByLines(source, maxChars: 9000)
                var notes: [String] = []
                notes.reserveCapacity(chunks.count)

                var lastErr: String? = nil
                for i in 0..<chunks.count {
                    let r = await summarizeChunk(model: model, idx: i + 1, total: chunks.count, text: chunks[i])
                    if let e = r.error, !e.isEmpty { lastErr = e }
                    if let s = r.summary, !s.isEmpty { notes.append(s) }
                }

                if notes.isEmpty {
                    let tail = String(source.suffix(12000))
                    let r = await summarizeSingle(model: model, text: tail)
                    return Result(title: r.title, summary: r.summary, error: r.error ?? lastErr ?? "summarize_failed", mode: "chunked_fallback_single_tail")
                }

                let combined = notes.joined(separator: "\n")
                let reduceLimitChars = 12000
                let reduceInput = clampHeadTail(combined, limit: reduceLimitChars)

                let final = await reduceNotes(model: model, notes: reduceInput)
                if (final.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let fallback = fallbackFromFreeform(final.freeform ?? "")
                    return Result(
                        title: fallback.title.isEmpty ? nil : fallback.title,
                        summary: fallback.summary.isEmpty ? nil : fallback.summary,
                        error: final.error ?? "reduce_parse_fallback",
                        mode: "chunked_reduce_fallback"
                    )
                }

                return Result(title: final.title, summary: final.summary, error: final.error, mode: "chunked")
            }
        }
        #endif

        return Result(title: nil, summary: nil, error: "FoundationModels unavailable", mode: "unavailable")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func summarizeSingle(model: SystemLanguageModel, text: String) async -> (title: String?, summary: String?, error: String?) {
        do {
            let session = LanguageModelSession(model: model, tools: [], instructions: { "Plain text only. No markdown." })
            let p =
            """
            Return EXACTLY one line:

            Line 1: SUMMARY: <EXACTLY 5 bullet points, each starting with "• ", each 8–20 words. Plain text only.>

            DOCUMENT:
            \(text)
            """

            let r = try await session.respond(to: p)
            let parsed = parseTitleSummaryLoose(r.content)
            if !parsed.summary.isEmpty || !parsed.title.isEmpty {
                return (parsed.title.isEmpty ? nil : parsed.title, parsed.summary.isEmpty ? nil : parsed.summary, nil)
            }
            let fb = fallbackFromFreeform(r.content)
            return (fb.title.isEmpty ? nil : fb.title, fb.summary.isEmpty ? nil : fb.summary, nil)
        } catch {
            return (nil, nil, String(describing: error))
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func summarizeChunk(model: SystemLanguageModel, idx: Int, total: Int, text: String) async -> (summary: String?, error: String?) {
        do {
            let session = LanguageModelSession(model: model, tools: [], instructions: { "Plain text only. No markdown." })
            let p =
"""
Read PART \(idx)/\(total) and output ONE paragraph note.

Rules:
- ONE paragraph
- 50–90 words
- No bullets, no labels
- Capture durable facts/decisions only

PART:
\(text)
"""
            let r = try await session.respond(to: p)
            let out = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return (out.isEmpty ? nil : out, nil)
        } catch {
            return (nil, String(describing: error))
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func reduceNotes(model: SystemLanguageModel, notes: String) async -> (title: String?, summary: String?, error: String?, freeform: String?) {
        do {
            let session = LanguageModelSession(model: model, tools: [], instructions: { "Plain text only. No markdown." })
            let p =
"""
Return EXACTLY two lines:

Line 1: TITLE: <8–14 words; descriptive; include site/app if obvious; no quotes; no trailing punctuation>
Line 2: SUMMARY: <ONE paragraph; max 200 words; describes the WHOLE document>

SOURCE NOTES:
\(notes)
"""
            let r = try await session.respond(to: p)
            let parsed = parseTitleSummaryLoose(r.content)
            if !parsed.summary.isEmpty || !parsed.title.isEmpty {
                return (parsed.title.isEmpty ? nil : parsed.title, parsed.summary.isEmpty ? nil : parsed.summary, nil, r.content)
            }
            let fb = fallbackFromFreeform(r.content)
            return (fb.title.isEmpty ? nil : fb.title, fb.summary.isEmpty ? nil : fb.summary, "reduce_parse_fallback", r.content)
        } catch {
            return (nil, nil, String(describing: error), nil)
        }
    }
    #endif

    private static func chunkByLines(_ s: String, maxChars: Int) -> [String] {
        if s.count <= maxChars { return [s] }
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var out: [String] = []
        var buf: [String] = []
        var n = 0

        func flush() {
            if buf.isEmpty { return }
            out.append(buf.joined(separator: "\n"))
            buf.removeAll(keepingCapacity: true)
            n = 0
        }

        for line in lines {
            let add = line.count + 1
            if n + add > maxChars && !buf.isEmpty { flush() }
            buf.append(line)
            n += add
        }
        flush()
        return out.isEmpty ? [s] : out
    }

    private static func clampHeadTail(_ s: String, limit: Int) -> String {
        if s.count <= limit { return s }
        let headCount = limit / 2
        let tailCount = limit - headCount
        let head = String(s.prefix(headCount))
        let tail = String(s.suffix(tailCount))
        return head + "\n…\n" + tail
    }

    private static func parseTitleSummaryLoose(_ s: String) -> (title: String, summary: String) {
        let raw = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.isEmpty { return ("", "") }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var title = ""
        var summary = ""

        for line in lines {
            let u = line.uppercased()
            if u.hasPrefix("TITLE:") || u.hasPrefix("TITLE -") || u.hasPrefix("TITLE—") {
                title = stripAfterLabel(line)
            } else if u.hasPrefix("SUMMARY:") || u.hasPrefix("SUMMARY -") || u.hasPrefix("SUMMARY—") {
                summary = stripAfterLabel(line)
            }
        }

        if title.isEmpty && summary.isEmpty {
            if let first = lines.first {
                title = first
                if lines.count > 1 {
                    summary = lines.dropFirst().joined(separator: " ")
                } else {
                    summary = first
                }
            }
        }

        if title.count > 90 { title = String(title.prefix(90)) }

        summary = summary.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if summary.count > 1200 {
            summary = String(summary.prefix(1200)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (title, summary)
    }

    private static func stripAfterLabel(_ line: String) -> String {
        if let idx = line.firstIndex(of: ":") {
            return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let r = line.range(of: "-") {
            return String(line[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let r = line.range(of: "—") {
            return String(line[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackFromFreeform(_ s: String) -> (title: String, summary: String) {
        let raw = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.isEmpty { return ("", "") }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let firstLine = lines.first ?? ""
        var title = firstLine
        if title.count > 90 { title = String(title.prefix(90)) }

        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = joined.split(separator: " ")
        if words.count <= 200 {
            return (title, joined)
        }
        let clipped = words.prefix(200).joined(separator: " ")
        return (title, clipped)
    }
}
