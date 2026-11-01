import Foundation

/// Strict SubRip (SRT) parser (lane L5, unit u1). Typed refusals on malformed
/// input; no guessing, no partial adoption of a broken block. Spec scope:
/// positive integer index line, "HH:MM:SS,mmm --> HH:MM:SS,mmm" timing line
/// (optional coordinate tail ignored), one or more text lines, blocks split on
/// blank lines (a whitespace-only line counts as blank EVERYWHERE, including
/// inside cue text). Tolerates a UTF-8 BOM and CR/LF/CRLF endings. Inline tags
/// in cue text are kept verbatim; presentation stripping belongs to the
/// renderer.
/// Explicit boundaries (strict by design, documented per independent review):
/// the timing separator must be exactly " --> " (tabs or other spacing refuse);
/// cue indices must be positive integers but monotonic sequence is NOT required
/// (accepted deviation: file order is preserved; playback does not depend on
/// index order).
public enum SRTParser {

    public enum ParseError: Error, Equatable {
        case emptyDocument
        case badIndex(line: Int)
        case badTimingLine(line: Int)
        case badTimestamp(line: Int)
        case endNotAfterStart(line: Int)
        case missingText(line: Int)
    }

    /// Parses whole-document SRT text into cues in file order.
    public static func parse(_ content: String) throws -> [SubtitleCue] {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var cues: [SubtitleCue] = []
        var i = 0
        var sawAnyBlock = false
        while i < lines.count {
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
            guard i < lines.count else { break }
            sawAnyBlock = true
            let indexLine = i + 1 // 1-based for diagnostics
            guard isPositiveInt(lines[i]) else { throw ParseError.badIndex(line: indexLine) }
            let index = Int(lines[i])!
            i += 1
            guard i < lines.count, !lines[i].isEmpty else { throw ParseError.badTimingLine(line: i + 1) }
            let timingLine = i + 1
            let (start, end) = try parseTiming(lines[i], line: timingLine)
            i += 1
            var textLines: [String] = []
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[i])
                i += 1
            }
            // missingText points at the line where text was expected (first
            // line after the timing line), not at the timing line itself.
            guard !textLines.isEmpty else { throw ParseError.missingText(line: timingLine + 1) }
            cues.append(SubtitleCue(index: index, startSeconds: start, endSeconds: end, lines: textLines))
        }
        guard sawAnyBlock else { throw ParseError.emptyDocument }
        return cues
    }

    static func isPositiveInt(_ s: String) -> Bool {
        guard !s.isEmpty, s.allSatisfy({ $0 >= "0" && $0 <= "9" }), let v = Int(s), v > 0 else { return false }
        return true
    }

    static func parseTiming(_ line: String, line number: Int) throws -> (Double, Double) {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { throw ParseError.badTimingLine(line: number) }
        guard let start = parseTimestamp(parts[0]) else { throw ParseError.badTimestamp(line: number) }
        // Optional coordinate tail after the end timestamp (" X1:a X2:b Y1:c Y2:d").
        let endToken = parts[1].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let end = parseTimestamp(endToken) else { throw ParseError.badTimestamp(line: number) }
        guard end > start else { throw ParseError.endNotAfterStart(line: number) }
        return (start, end)
    }

    /// "HH:MM:SS,mmm" - hours any non-negative integer, mm/ss two digits < 60,
    /// milliseconds exactly three digits. Comma is the only accepted separator.
    static func parseTimestamp(_ s: String) -> Double? {
        let hms = s.split(separator: ":", omittingEmptySubsequences: false)
        guard hms.count == 3 else { return nil }
        guard !hms[0].isEmpty, hms[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let hh = Int(hms[0]) else { return nil }
        guard hms[1].count == 2, hms[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let mm = Int(hms[1]), mm >= 0, mm < 60 else { return nil }
        let sm = hms[2].split(separator: ",", omittingEmptySubsequences: false)
        guard sm.count == 2 else { return nil }
        guard sm[0].count == 2, sm[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let ss = Int(sm[0]), ss >= 0, ss < 60 else { return nil }
        guard sm[1].count == 3, sm[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let ms = Int(sm[1]) else { return nil }
        return Double(hh) * 3600 + Double(mm) * 60 + Double(ss) + Double(ms) / 1000
    }
}
