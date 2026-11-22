import Foundation

/// Strict SubRip (.srt) parser. Deterministic, Foundation only.
enum SRTParser {
    /// Parses SRT text into cues with track 0, in file order.
    static func parse(_ text: String) throws -> [Cue] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [[String]] = []
        var current: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        guard !blocks.isEmpty else { throw SubtitleParseError.emptyInput }

        var cues: [Cue] = []
        for block in blocks {
            guard block.count >= 2 else {
                throw SubtitleParseError.malformedCue(block.joined(separator: "\n"))
            }
            guard Int(block[0].trimmingCharacters(in: .whitespaces)) != nil else {
                throw SubtitleParseError.malformedCue(block[0])
            }
            let (start, end) = try parseTimingLine(block[1])
            guard block.count >= 3 else { throw SubtitleParseError.malformedCue(block[1]) }
            let cueText = block[2...].joined(separator: "\n")
            cues.append(Cue(start: start, end: end, text: cueText, track: 0))
        }
        return cues
    }

    /// "HH:MM:SS,mmm --> HH:MM:SS,mmm" with end strictly after start.
    static func parseTimingLine(_ line: String) throws -> (Double, Double) {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { throw SubtitleParseError.malformedTimeRange(line) }
        let start = try parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces), raw: line)
        let end = try parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces), raw: line)
        guard end > start else { throw SubtitleParseError.malformedTimeRange(line) }
        return (start, end)
    }

    /// "HH:MM:SS,mmm"; hours may use more than two digits; MM and SS must be < 60.
    static func parseTimestamp(_ ts: String, raw: String) throws -> Double {
        let main = ts.components(separatedBy: ",")
        guard main.count == 2,
              main[1].count == 3,
              main[1].allSatisfy({ $0.isNumber }),
              let ms = Int(main[1])
        else { throw SubtitleParseError.malformedTimeRange(raw) }
        let hms = main[0].components(separatedBy: ":")
        guard hms.count == 3,
              hms[0].count >= 2, hms[1].count == 2, hms[2].count == 2,
              hms.allSatisfy({ field in field.allSatisfy({ $0.isNumber }) }),
              let h = Int(hms[0]), let m = Int(hms[1]), let s = Int(hms[2]),
              m < 60, s < 60
        else { throw SubtitleParseError.malformedTimeRange(raw) }
        return Double(h) * 3600 + Double(m) * 60 + Double(s) + Double(ms) / 1000
    }
}
