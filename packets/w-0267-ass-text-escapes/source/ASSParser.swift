import Foundation

/// Minimal strict ASS/SSA parser (lane L6, unit u1): text subtitles with a
/// style table. Parses [Script Info] (PlayRes only), [V4+ Styles] (Style rows
/// via their own Format), [Events] (Format + Dialogue; Comment rows skipped).
/// Cue text: override blocks "{...}" are detected, reported as UNSUPPORTED
/// (Document.unsupportedOverrides, per-cue tag list) and removed from the
/// plain-text cue lines only. "\N"/"\n" are converted to line breaks, "\h"
/// to a non-breaking space. Karaoke timing, vector drawing and every other
/// rendering semantic inside override blocks are NOT interpreted or rendered:
/// unsupported means unsupported, never silently dropped without record.
/// Typed refusals on malformed structure; a malformed Style row is skipped
/// (cosmetic) while a malformed Dialogue row refuses (content).
public enum ASSParser {

    public enum ParseError: Error, Equatable {
        case missingEventsSection
        case missingEventsFormat(line: Int)
        case dialogueBeforeFormat(line: Int)
        case badTimestamp(line: Int)
        case endNotAfterStart(line: Int)
        case badDialogueFieldCount(line: Int)
        case missingText(line: Int)
        /// The event's text is ONLY override blocks: after (reported) removal
        /// nothing renderable remains. Typed refusal so the event is an
        /// explicit not-rendered record, never silently erased.
        case overrideOnlyText(line: Int)
    }

    public struct Style: Equatable, Sendable {
        public let name: String
        public let fontName: String
        public let fontSize: Double
        /// ASS stores &HAABBGGRR; this is the decoded AARRGGBB value.
        public let primaryColourARGB: UInt32

        public init(name: String, fontName: String, fontSize: Double, primaryColourARGB: UInt32) {
            self.name = name
            self.fontName = fontName
            self.fontSize = fontSize
            self.primaryColourARGB = primaryColourARGB
        }
    }

    /// One cue's unsupported rendering instructions: the override tag names
    /// (e.g. "\\pos", "\\fad") found in its "{...}" blocks. tags is empty when
    /// the block carried no backslash tag (e.g. a drawing-only block).
    public struct OverrideReport: Equatable, Sendable {
        public let cueIndex: Int
        public let tags: [String]

        public init(cueIndex: Int, tags: [String]) {
            self.cueIndex = cueIndex
            self.tags = tags
        }
    }

    /// A Style row that failed to parse: caller-visible, never a silent drop.
    /// reason: "field count", "missing required field", "bad fontsize",
    /// "bad colour".
    public struct SkippedStyle: Equatable, Sendable {
        public let line: Int
        public let reason: String

        public init(line: Int, reason: String) {
            self.line = line
            self.reason = reason
        }
    }

    public struct Document: Equatable, Sendable {
        public let styles: [Style]
        public let cues: [SubtitleCue]
        public let playResX: Int?
        public let playResY: Int?
        /// Every cue that carried override blocks; unsupported, reported.
        public let unsupportedOverrides: [OverrideReport]
        /// Style rows that failed parsing (cosmetic, but on record).
        public let skippedStyles: [SkippedStyle]
    }

    public static func parse(_ content: String) throws -> Document {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var section = ""
        var sawEvents = false
        var styleFields: [String] = []
        var eventFields: [String] = []
        var haveEventFormat = false
        var styles: [Style] = []
        var cues: [SubtitleCue] = []
        var overrideReports: [OverrideReport] = []
        var skippedStyles: [SkippedStyle] = []
        var playResX: Int? = nil
        var playResY: Int? = nil

        for (idx, raw) in lines.enumerated() {
            let lineNo = idx + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
                if section == "events" { sawEvents = true }
                continue
            }
            let lowered = line.lowercased()
            switch section {
            case "script info":
                if let v = infoValue(line, key: "PlayResX") { playResX = Int(v) }
                if let v = infoValue(line, key: "PlayResY") { playResY = Int(v) }
            case "v4+ styles", "v4 styles":
                if lowered.hasPrefix("format:") {
                    styleFields = splitFields(String(line.dropFirst(7)))
                } else if lowered.hasPrefix("style:") {
                    switch parseStyle(String(line.dropFirst(6)), fields: styleFields) {
                    case .ok(let s): styles.append(s)
                    case .skipped(let reason): skippedStyles.append(SkippedStyle(line: lineNo, reason: reason))
                    }
                }
            case "events":
                if lowered.hasPrefix("format:") {
                    eventFields = splitFields(String(line.dropFirst(7)))
                    guard eventFields.contains("start"), eventFields.contains("end"), eventFields.contains("text") else {
                        throw ParseError.missingEventsFormat(line: lineNo)
                    }
                    haveEventFormat = true
                } else if lowered.hasPrefix("dialogue:") {
                    guard haveEventFormat else { throw ParseError.dialogueBeforeFormat(line: lineNo) }
                    let (cue, report) = try parseDialogue(String(line.dropFirst(9)), fields: eventFields, line: lineNo, index: cues.count + 1)
                    cues.append(cue)
                    if let report { overrideReports.append(report) }
                } else if lowered.hasPrefix("comment:") {
                    continue
                }
            default:
                continue
            }
        }
        guard sawEvents else { throw ParseError.missingEventsSection }
        return Document(styles: styles, cues: cues, playResX: playResX, playResY: playResY,
                        unsupportedOverrides: overrideReports, skippedStyles: skippedStyles)
    }

    static func infoValue(_ line: String, key: String) -> String? {
        guard line.lowercased().hasPrefix(key.lowercased() + ":") else { return nil }
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    static func splitFields(_ s: String) -> [String] {
        s.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    enum StyleResult {
        case ok(Style)
        case skipped(reason: String)
    }

    static func parseStyle(_ body: String, fields: [String]) -> StyleResult {
        guard !fields.isEmpty else { return .skipped(reason: "no style Format") }
        let values = body.split(separator: ",", maxSplits: fields.count - 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.count == fields.count else { return .skipped(reason: "field count") }
        guard let ni = fields.firstIndex(of: "name"),
              let fi = fields.firstIndex(of: "fontname"),
              let si = fields.firstIndex(of: "fontsize"),
              let ci = fields.firstIndex(of: "primarycolour") else { return .skipped(reason: "missing required field") }
        guard let size = Double(values[si]) else { return .skipped(reason: "bad fontsize") }
        guard let argb = parseColour(values[ci]) else { return .skipped(reason: "bad colour") }
        return .ok(Style(name: values[ni], fontName: values[fi], fontSize: size, primaryColourARGB: argb))
    }

    /// "&HAABBGGRR" (8 hex digits) or "&HBBGGRR" (6) -> AARRGGBB.
    static func parseColour(_ s: String) -> UInt32? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("&h") else { return nil }
        t = String(t.dropFirst(2))
        // Exactly 6 (&HBBGGRR) or 8 (&HAABBGGRR) hex digits; any other length
        // refuses instead of misdecoding positionally.
        guard t.count == 6 || t.count == 8, t.allSatisfy({ $0.isHexDigit }), let v = UInt32(t, radix: 16) else { return nil }
        let aa: UInt32 = t.count <= 6 ? 0 : (v >> 24) & 0xff
        let bb = (v >> 16) & 0xff
        let gg = (v >> 8) & 0xff
        let rr = v & 0xff
        return (aa << 24) | (rr << 16) | (gg << 8) | bb
    }

    static func parseDialogue(_ body: String, fields: [String], line: Int, index: Int) throws -> (SubtitleCue, OverrideReport?) {
        let parts = body.split(separator: ",", maxSplits: fields.count - 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == fields.count else { throw ParseError.badDialogueFieldCount(line: line) }
        func field(_ name: String) -> String { parts[fields.firstIndex(of: name)!] }
        guard let start = parseTimestamp(field("start").trimmingCharacters(in: .whitespaces)) else { throw ParseError.badTimestamp(line: line) }
        guard let end = parseTimestamp(field("end").trimmingCharacters(in: .whitespaces)) else { throw ParseError.badTimestamp(line: line) }
        guard end > start else { throw ParseError.endNotAfterStart(line: line) }
        let rawText = field("text")
        let (cleaned, tags) = cleanText(rawText)
        if cleaned.isEmpty {
            // Distinguish an empty text field from a pure override-only event:
            // the override-only case keeps its tags in the refusal's line
            // context instead of vanishing into a generic missingText.
            if rawText.contains("{") { throw ParseError.overrideOnlyText(line: line) }
            throw ParseError.missingText(line: line)
        }
        // Per-cue style association is preserved, never discarded: it is the
        // link a future renderer needs between cue text and the style table.
        let styleName = fields.contains("style") ? field("style").trimmingCharacters(in: .whitespaces) : nil
        let cue = SubtitleCue(index: index, startSeconds: start, endSeconds: end,
                              lines: cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                              styleName: styleName?.isEmpty == true ? nil : styleName)
        return (cue, tags.isEmpty ? nil : OverrideReport(cueIndex: index, tags: tags))
    }

    /// "H:MM:SS.cc" - hours any non-negative integer, mm/ss two digits < 60,
    /// centiseconds exactly two digits.
    static func parseTimestamp(_ s: String) -> Double? {
        let hms = s.split(separator: ":", omittingEmptySubsequences: false)
        guard hms.count == 3 else { return nil }
        guard !hms[0].isEmpty, hms[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let hh = Int(hms[0]) else { return nil }
        guard hms[1].count == 2, hms[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let mm = Int(hms[1]), mm >= 0, mm < 60 else { return nil }
        let sc = hms[2].split(separator: ".", omittingEmptySubsequences: false)
        guard sc.count == 2 else { return nil }
        guard sc[0].count == 2, sc[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let ss = Int(sc[0]), ss >= 0, ss < 60 else { return nil }
        guard sc[1].count == 2, sc[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let cs = Int(sc[1]) else { return nil }
        return Double(hh) * 3600 + Double(mm) * 60 + Double(ss) + Double(cs) / 100
    }

    /// Removes "{...}" override blocks (non-nested, unterminated block drops to
    /// end of text), converts "\N"/"\n" to line breaks and "\h" to NBSP.
    /// Returns the cleaned text plus the sorted unique override tag names found
    /// inside the blocks (reported UNSUPPORTED by the caller; a block with no
    /// backslash tag contributes "block").
    static func cleanText(_ s: String) -> (String, [String]) {
        var out = ""
        var tags = Set<String>()
        var depth = 0
        var blockStart = String.Index?.none
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { if depth == 0 { blockStart = i }; depth += 1; i = s.index(after: i); continue }
            if c == "}", depth > 0 {
                depth -= 1
                if depth == 0, let b = blockStart {
                    let content = s[s.index(after: b)..<i]
                    let found = extractTags(String(content))
                    tags.formUnion(found.isEmpty ? ["block"] : found)
                    blockStart = nil
                }
                i = s.index(after: i); continue
            }
            // A "}" at depth 0 has no matching block: it is ordinary text and
            // is preserved, not silently dropped.
            if depth == 0 {
                if c == "\\" {
                    let n = s.index(after: i)
                    if n < s.endIndex {
                        let d = s[n]
                        if d == "N" || d == "n" { out.append("\n"); i = s.index(after: n); continue }
                        if d == "h" { out.append("\u{00A0}"); i = s.index(after: n); continue }
                    }
                }
                out.append(c)
            }
            i = s.index(after: i)
        }
        if depth > 0, let b = blockStart {
            // Unterminated block: content to end of text is still reported.
            let content = s[s.index(after: b)..<s.endIndex]
            let found = extractTags(String(content))
            tags.formUnion(found.isEmpty ? ["block"] : found)
        }
        return (out.trimmingCharacters(in: .whitespaces), tags.sorted())
    }

    /// Backslash tag names inside one override block, e.g. "\\pos(1,2)\\fad(0,0)"
    /// -> ["\\fad", "\\pos"]. Stops each tag at the first non-letter character.
    static func extractTags(_ block: String) -> [String] {
        var found = Set<String>()
        var i = block.startIndex
        while i < block.endIndex {
            if block[i] == "\\" {
                var j = block.index(after: i)
                var name = "\\"
                while j < block.endIndex, block[j].isLetter {
                    name.append(block[j])
                    j = block.index(after: j)
                }
                if name.count > 1 { found.insert(name) }
                i = j
            } else {
                i = block.index(after: i)
            }
        }
        return found.sorted()
    }
}
