import Foundation

struct ASSParseResult {
    var cues: [Cue]
    var meta: [CueMeta]
    var playResX: Double?
    var playResY: Double?
}

/// SubStation Alpha (.ass) parser covering Script Info PlayRes, the Events
/// Format/Dialogue grammar, commas inside Text, {\anN} override tags and \N
/// hard line breaks. Deterministic, Foundation only.
enum ASSParser {
    static func parse(_ text: String) throws -> ASSParseResult {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var section = ""
        var playResX: Double?
        var playResY: Double?
        var formatColumns: [String] = []
        var cues: [Cue] = []
        var meta: [CueMeta] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            switch section {
            case "script info":
                let kv = line.components(separatedBy: ":")
                if kv.count == 2 {
                    let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = kv[1].trimmingCharacters(in: .whitespaces)
                    if key == "playresx" { playResX = Double(value) }
                    if key == "playresy" { playResY = Double(value) }
                }
            case "events":
                let lowered = line.lowercased()
                if lowered.hasPrefix("format:") {
                    let rest = String(line.dropFirst("format:".count))
                    formatColumns = rest.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                } else if lowered.hasPrefix("dialogue:") {
                    guard !formatColumns.isEmpty else {
                        throw SubtitleParseError.malformedCue(line)
                    }
                    let rest = String(line.dropFirst("dialogue:".count))
                    // Split into exactly formatColumns.count fields; the last
                    // field (Text) keeps its commas verbatim.
                    let fields = rest
                        .split(separator: ",", maxSplits: formatColumns.count - 1, omittingEmptySubsequences: false)
                        .map(String.init)
                    guard fields.count == formatColumns.count else {
                        throw SubtitleParseError.malformedCue(line)
                    }
                    func field(_ name: String) -> String? {
                        guard let i = formatColumns.firstIndex(of: name) else { return nil }
                        return fields[i].trimmingCharacters(in: .whitespaces)
                    }
                    guard let startRaw = field("start"),
                          let endRaw = field("end"),
                          let textRaw = field("text")
                    else { throw SubtitleParseError.malformedCue(line) }
                    let start = try parseASSTime(startRaw, raw: line)
                    let end = try parseASSTime(endRaw, raw: line)
                    guard end > start else { throw SubtitleParseError.malformedTimeRange(line) }
                    let layer = field("layer").flatMap(Int.init) ?? 0
                    let (cleanText, anchor) = stripOverrides(textRaw)
                    cues.append(Cue(start: start, end: end, text: cleanText, track: layer))
                    meta.append(CueMeta(anchor: anchor ?? .bottomCenter))
                }
            default:
                break
            }
        }
        guard !cues.isEmpty else { throw SubtitleParseError.emptyInput }
        return ASSParseResult(cues: cues, meta: meta, playResX: playResX, playResY: playResY)
    }

    /// "H:MM:SS.cc" centisecond timestamps; MM and SS must be < 60.
    static func parseASSTime(_ ts: String, raw: String) throws -> Double {
        let main = ts.components(separatedBy: ".")
        guard main.count == 2,
              main[1].count == 2,
              main[1].allSatisfy({ $0.isNumber }),
              let cs = Int(main[1])
        else { throw SubtitleParseError.malformedTimeRange(raw) }
        let hms = main[0].components(separatedBy: ":")
        guard hms.count == 3,
              hms[1].count == 2, hms[2].count == 2,
              hms.allSatisfy({ field in !field.isEmpty && field.allSatisfy({ $0.isNumber }) }),
              let h = Int(hms[0]), let m = Int(hms[1]), let s = Int(hms[2]),
              m < 60, s < 60
        else { throw SubtitleParseError.malformedTimeRange(raw) }
        return Double(h) * 3600 + Double(m) * 60 + Double(s) + Double(cs) / 100
    }

    /// Removes {...} override blocks, captures the first \anN alignment,
    /// converts \N and \n to real newlines. Text outside braces is verbatim.
    static func stripOverrides(_ text: String) -> (String, CueAnchor?) {
        var output = ""
        var anchor: CueAnchor?
        var depth = 0
        var tagBuffer = ""
        for ch in text {
            if depth == 0 {
                if ch == "{" {
                    depth = 1
                    tagBuffer = ""
                } else {
                    output.append(ch)
                }
            } else {
                if ch == "}" {
                    depth = 0
                    if anchor == nil, let found = scanAnchor(tagBuffer) { anchor = found }
                } else {
                    tagBuffer.append(ch)
                }
            }
        }
        let withNewlines = output
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
        return (withNewlines, anchor)
    }

    static func scanAnchor(_ tag: String) -> CueAnchor? {
        let chars = Array(tag)
        var i = 0
        while i + 3 < chars.count {
            if chars[i] == "\\", chars[i + 1] == "a", chars[i + 2] == "n",
               let d = chars[i + 3].wholeNumberValue, (1...9).contains(d) {
                return CueAnchor(rawValue: d)
            }
            i += 1
        }
        return nil
    }
}
