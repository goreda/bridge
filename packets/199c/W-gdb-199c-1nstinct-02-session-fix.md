# W-gdb-199c-1nstinct-02-session-fix - Preserve original subtitle selection context
state: OPEN / requires session-API lease coordination
lab: 1nstinct

Make selection receipts originate from the original selection operation/context, never by accepting an arbitrary old selection and stamping live sourcePath/generation. Add a context-bound result/receipt API that captures original source revision, request ticket and slot before any await and returns the receipt atomically with the selection result. Refuse stale receipts after source replacement, seek/reset, close and superseding same-slot selection. Preserve normal source selection, real SRT parsing and primary/secondary isolation. Do not assert caller discipline as API enforcement. If retaining selectionReceipt(for:) for compatibility, document it as unsafe legacy conversion and ensure consumers cannot mistake its output for a proven current selection receipt; explain migration explicitly.

Session-API scope: this defect is in SubtitleSidecarSession.swift, not the open02 SubtitleTrack serialization fix or03 SubtitleController generation fix. This packet requests a separate coordinator-approved session-file lease. Do not concurrently edit that file under old A02. SubtitleTrack, SubtitleController, host call sites and receipt-schema consumers are read-only dependencies, not edit leases. If actual enforcement needs a caller or another file, return the exact proposed interface/path and stop that extension for coordination. A model-only session patch cannot claim end-to-end producer adoption.

The starter deliberately reproduces the old unsafe conversion using real pinned discovery, SRT parser and cue producer, not lab fixtures. It creates A media plus A.srt, obtains actual A selection, replaces with B, and demonstrates that restamping old outcome returns a receipt that claims current B. The fix writer must bind this scenario to the new context-preserving API, plus async replacement, seek/reset/close and slot-isolation tests. Do not merely change the reproducer or compare file paths in place of preserving origin.

PATH-CONTRACT: fixtures -> Tests/Fixtures, kits -> archive/kits. No directory moves; no host, native, serialization or controller edits. Test-only returns count0. No production/delivery ref changes. English only. G0901 was an untrusted lab lead, independently reproduced here against the exact imported02 source pin. Full-provider package/native/UI/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-02-session-fix",
  "lab": "1nstinct",
  "product_repo": "goreda/gorav",
  "product_sha": "4c70ecfc3b03de936723a6cc65700458136690e0",
  "scope": "product-fix",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
      "excerpt_block": "source10"
    }
  ],
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-1nstinct-02-session-fix.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1; writer must replace free restamping with context-bound receipt API and adapt test to preserved original context. Full source module build and producer integration still required."
  },
  "target": {
    "branch": "lane/lab-a-W-gdb-199c-1nstinct-02-session-fix",
    "paths": [
      "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
      "Tests/Architecture/199c/W-gdb-199c-1nstinct-02-session-fix.py",
      "Tests/Architecture/199c/W-gdb-199c-1nstinct-02-session-fix.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "4c70ecfc3b03de936723a6cc65700458136690e0",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-1nstinct-02-session-fix.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "whole-subtitle-source-set semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "FAIL old A selection restamped as current B",
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/ASSParser.swift",
        "block": "source1",
        "sha256": "4c16b99f1e1e78c7bd84346b35b0be6d670dff2df193bc9f69ac2a0ddc7d18f6",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SRTParser.swift",
        "block": "source2",
        "sha256": "49ab4d1258dc63529700a6e560ff1cefb6e287f65e267fc3f9befcafb0f5a653",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleAutoLoad.swift",
        "block": "source3",
        "sha256": "bdf2a96b5fd4b1a09f7a7cd269304d8dcff479215cd7e75d360f1e8e8d4f36e0",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleController.swift",
        "block": "source4",
        "sha256": "7695cee46f59b071b8f315019ad42f15dec6ceab6975a0ddc3bd1e81f2db1897",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
        "block": "source5",
        "sha256": "2311ed3052c4a66f2d7942d23624b693faa52dc509354e22fbff148aa3abaa40",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCueDelivery.swift",
        "block": "source6",
        "sha256": "c0def67c2c6320c899be4b612cb30e4ba4f23a327e6c05d9608e3a048cf7a6e4",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCueOutput.swift",
        "block": "source7",
        "sha256": "c25b9d57173dcd41582d116ef3c480917444fa53bdd2dc80132e76b8148e6457",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitlePlan.swift",
        "block": "source8",
        "sha256": "ab71ef7425c33dfbbe93e558b8797139260fa1aff449369724fcad45b9dce696",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleSchedule.swift",
        "block": "source9",
        "sha256": "dd2afbc48525765a33777c758cb10df4b1629dfc85fd11e69fbbd896f12b2f22",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
        "block": "source10",
        "sha256": "8a3c2d081d4ef43600986a3fbf4f8023390f2f0788fa2839c5fed9f642f0d719",
        "read_only_dependency": false
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleTrack.swift",
        "block": "source11",
        "sha256": "ce40f8a2a0276b340224dd5bebacd286b72778795d7aed2ef8c4fe27a0cba554",
        "read_only_dependency": true
      },
      {
        "path": "Sources/GorAVSubtitles/VTTParser.swift",
        "block": "source12",
        "sha256": "3354ef321604169f9b3f4c926565be5e7869d54712d287d70aa53b46b0f0425f",
        "read_only_dependency": true
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-1nstinct-02-session-fix.py",
        "block": "fixtures1",
        "sha256": "c22d91cea929a580a5bd4370d811635f62769534914b678a0f3b4b380f717b9e"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-1nstinct-02-session-fix.json",
        "block": "fixtures2",
        "sha256": "d298ae4dfc0fef40ac551548f1d617d04d37cb1d2cee5ad4e040ca345a1764bb"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "2c14d1e77a6958bfe1fdfe174ebcd29159a2b41fdf11988ba50500aa5cc2d305",
    "last_5_lines": [
      "compile_exit=0",
      "",
      "semantic_exit=1",
      "FAIL old A selection restamped as current B",
      ""
    ],
    "receipt_sha256": "2024380fc5c3f6c5aba9da67432b323ae850ca8d5a871278efa2221fbf3ebf9d"
  }
}
```

```swift id=source1
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

```

```swift id=source2
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

```

```swift id=source3
import Foundation

/// R7 (arch-195b): external subtitle auto-load discovery. Given a playing
/// video's local path, finds sibling sidecar files: exact-basename matches
/// (movie.srt next to movie.mp4) and language-tagged matches (movie.en.srt).
/// Deterministic order: exact basename first, then tagged matches sorted by
/// tag. Unknown extensions are never returned (they fail at load time as
/// typed refusals via SubtitleTrack.load). Discovery only; no parsing here.
public enum SubtitleAutoLoad {

    public static let extensions: Set<String> = ["srt", "ass", "ssa"]

    public struct Candidate: Equatable, Sendable {
        public let path: String
        /// nil for an exact-basename match; otherwise the tag between the
        /// video basename and the extension (usually a language code).
        public let tag: String?
        public let format: String
        public init(path: String, tag: String?, format: String) {
            self.path = path
            self.tag = tag
            self.format = format
        }
    }

    /// Deterministic candidates for `videoPath`. Returns [] when the video
    /// path has no usable basename or the directory cannot be listed; an
    /// empty result is a fact (no sidecars), never an error.
    public static func discover(forVideoPath videoPath: String) -> [Candidate] {
        let ns = videoPath as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.deletingPathExtension as NSString
        let baseName = base.lastPathComponent
        guard !baseName.isEmpty else { return [] }
        let listDir = dir.isEmpty ? "." : dir
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: listDir) else { return [] }
        var exact: [Candidate] = []
        var tagged: [Candidate] = []
        for entry in entries {
            let e = entry as NSString
            let ext = e.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            let nameNoExt = e.deletingPathExtension
            let full = listDir == "." ? entry : (listDir as NSString).appendingPathComponent(entry)
            let format = ext == "ssa" ? "ass" : ext
            if nameNoExt == baseName {
                exact.append(Candidate(path: full, tag: nil, format: format))
            } else if nameNoExt.hasPrefix(baseName + ".") {
                let tag = String(nameNoExt.dropFirst(baseName.count + 1))
                guard !tag.isEmpty else { continue }
                tagged.append(Candidate(path: full, tag: tag, format: format))
            }
        }
        return exact.sorted { $0.path < $1.path } + tagged.sorted { $0.path < $1.path }
    }
}

```

```swift id=source4
import Foundation

/// R7 (arch-195b): primary/secondary text cue selection with per-slot delay,
/// across seeks and reset. The schedule lookup is stateless, so a seek needs
/// no reload: cue identity (trackContentID, cue.index) survives any number of
/// seeks because the track content never changes under the controller.
public struct SubtitleController: Equatable, Sendable {

    public enum Slot: Equatable, Sendable { case primary, secondary }

    /// Identity of the currently displayed cue: stable across seeks, changes
    /// only when track content changes (a different file or a reload).
    public struct CueIdentity: Equatable, Sendable {
        public let trackContentID: UInt64
        public let cueIndex: Int
        public init(trackContentID: UInt64, cueIndex: Int) {
            self.trackContentID = trackContentID
            self.cueIndex = cueIndex
        }
    }

    public private(set) var primary: SubtitleTrack.Track?
    public private(set) var secondary: SubtitleTrack.Track?
    /// Seconds added to the cue timeline per slot: a positive delay shows cues
    /// later (query time minus delay). Default 0.
    public private(set) var primaryDelay: Double = 0
    public private(set) var secondaryDelay: Double = 0
    /// Set false to hide a slot without unloading it (mpv sub-visibility).
    public private(set) var primaryVisible = true
    public private(set) var secondaryVisible = true

    private var primaryContentID: UInt64 = 0
    private var secondaryContentID: UInt64 = 0
    private var primarySchedule: SubtitleSchedule?
    private var secondarySchedule: SubtitleSchedule?

    public init() {}

    public mutating func selectPrimary(_ track: SubtitleTrack.Track) {
        primary = track
        primarySchedule = SubtitleSchedule(cues: track.cues)
        primaryContentID = SubtitlePlanContentID.compute(cues: track.cues, styles: track.styles, playResX: track.playResX, playResY: track.playResY, unsupportedOverrides: track.unsupportedOverrides, skippedStyles: track.skippedStyles)
        primaryVisible = true
    }

    public mutating func selectSecondary(_ track: SubtitleTrack.Track) {
        secondary = track
        secondarySchedule = SubtitleSchedule(cues: track.cues)
        secondaryContentID = SubtitlePlanContentID.compute(cues: track.cues, styles: track.styles, playResX: track.playResX, playResY: track.playResY, unsupportedOverrides: track.unsupportedOverrides, skippedStyles: track.skippedStyles)
        secondaryVisible = true
    }

    public mutating func setDelay(_ seconds: Double, slot: Slot) {
        guard seconds.isFinite else { return }
        switch slot {
        case .primary: primaryDelay = seconds
        case .secondary: secondaryDelay = seconds
        }
    }

    public mutating func setVisible(_ visible: Bool, slot: Slot) {
        switch slot {
        case .primary: primaryVisible = visible
        case .secondary: secondaryVisible = visible
        }
    }

    /// Reset selection state: secondary unloaded, delays zeroed, both slots
    /// visible. The primary track stays loaded (mpv sub-reset semantics: the
    /// current external file remains the selected one).
    public mutating func reset() {
        secondary = nil
        secondarySchedule = nil
        secondaryContentID = 0
        primaryDelay = 0
        secondaryDelay = 0
        primaryVisible = true
        secondaryVisible = true
    }

    /// Active cue for one slot at film time `t` (delay applied). nil when the
    /// slot is empty, hidden, or no cue covers the shifted time.
    public func activeCue(at t: Double, slot: Slot) -> SubtitleCue? {
        switch slot {
        case .primary:
            guard primaryVisible, let s = primarySchedule else { return nil }
            return s.activeCue(at: t - primaryDelay)
        case .secondary:
            guard secondaryVisible, let s = secondarySchedule else { return nil }
            return s.activeCue(at: t - secondaryDelay)
        }
    }

    /// Identity of the active cue for one slot at film time `t`.
    public func activeCueIdentity(at t: Double, slot: Slot) -> CueIdentity? {
        guard let cue = activeCue(at: t, slot: slot) else { return nil }
        let tid = slot == .primary ? primaryContentID : secondaryContentID
        return CueIdentity(trackContentID: tid, cueIndex: cue.index)
    }
}

```

```swift id=source5
import Foundation

/// One timed subtitle cue over the half-open interval [startSeconds, endSeconds).
/// Format-neutral: produced by the SRT (L5) and ASS (L6) parsers and consumed
/// by the future presenter hook (trunk-owned wiring, block-78 L8 allocation:
/// Sources/GorAVSubtitles is a new path; no trunk files touched here).
public struct SubtitleCue: Equatable, Sendable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let lines: [String]
    /// ASS Dialogue Style association, preserved for the future renderer.
    /// nil for SRT and for ASS events whose Format carries no Style field.
    /// This is an association record, not styling support.
    public let styleName: String?

    public init(index: Int, startSeconds: Double, endSeconds: Double, lines: [String], styleName: String? = nil) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.lines = lines
        self.styleName = styleName
    }

    /// Cue text with original line breaks.
    public var text: String { lines.joined(separator: "\n") }

    /// Membership test on the half-open interval; inverted cues hold nothing.
    public func contains(seconds t: Double) -> Bool {
        t >= startSeconds && t < endSeconds
    }
}

```

```swift id=source6
import Foundation

/// A delivery unit, fenced by source session and seek generation. Reset is an
/// unconditional clear, even when the helper has no remembered active cue.
public struct SubtitleCueBatch: Equatable, Sendable {
    public let session: UInt64
    public let generation: UInt64
    public let sequence: UInt64
    public let reset: Bool
    public let closed: Bool
    public let events: [CueOutputEvent]
    public init(session: UInt64, generation: UInt64, sequence: UInt64, reset: Bool,
                closed: Bool = false, events: [CueOutputEvent]) {
        self.session = session; self.generation = generation; self.sequence = sequence
        self.reset = reset; self.closed = closed; self.events = events
    }
}

/// Producer used by the embedded session's real film-clock observer. Calls are
/// serialized by that session; an await must capture and recheck generation.
public struct SubtitleCueProducer: Sendable {
    public let session: UInt64
    public private(set) var generation: UInt64 = 0
    private var output: SubtitleCueOutput
    private var sequence: UInt64 = 0
    private var closed = false
    public init(session: UInt64) { self.session = session; output = SubtitleCueOutput(session: session) }
    public mutating func sample(session: UInt64, generation: UInt64, filmTime: Double,
                                controller: SubtitleController) -> SubtitleCueBatch? {
        guard !closed, session == self.session, generation == self.generation, filmTime.isFinite else { return nil }
        let events = output.sample(session: session, clock: filmTime, controller: controller)
        guard !events.isEmpty else { return nil }
        return batch(reset: false, events: events)
    }
    /// Seek/reset/replace clears are returned for immediate delivery, not discarded.
    /// Refuses generation exhaustion rather than wrapping into a stale identity.
    public mutating func advance() -> SubtitleCueBatch? {
        guard !closed, generation < UInt64.max else { return nil }
        generation += 1
        return batch(reset: true, events: output.reset())
    }
    public mutating func close() -> SubtitleCueBatch? {
        guard !closed else { return nil }
        let events = output.reset(); closed = true
        return batch(reset: true, events: events, terminal: true)
    }
    private mutating func batch(reset: Bool, events: [CueOutputEvent], terminal: Bool = false) -> SubtitleCueBatch? {
        guard sequence < UInt64.max else { return nil }
        sequence += 1
        return SubtitleCueBatch(session: session, generation: generation, sequence: sequence,
                                reset: reset, closed: terminal, events: events)
    }
}

/// Render-side state, used directly by MetalPresenter before its text-view update.
/// Future generations must begin with a reset clear. Stale disappear events never
/// clear a newer cue with a different identity. Close permanently fences a session.
public struct SubtitleCueConsumer: Sendable {
    public struct Active: Equatable, Sendable {
        public let identity: SubtitleController.CueIdentity
        public let cue: SubtitleCue
    }
    public let session: UInt64
    public private(set) var generation: UInt64 = 0
    public private(set) var primary: Active?
    public private(set) var secondary: Active?
    private var sequence: UInt64 = 0
    private var closed = false
    public init(session: UInt64) { self.session = session }
    @discardableResult
    public mutating func consume(_ batch: SubtitleCueBatch) -> Bool {
        guard !closed, batch.session == session, batch.generation >= generation,
              batch.sequence > sequence, batch.generation == generation || batch.reset else { return false }
        if batch.reset { primary = nil; secondary = nil }
        generation = batch.generation; sequence = batch.sequence
        for event in batch.events {
            switch event {
            case .appeared(let slot, let id, let cue):
                let value = Active(identity: id, cue: cue)
                if slot == .primary { primary = value } else { secondary = value }
            case .disappeared(let slot, let id):
                if slot == .primary, primary?.identity == id { primary = nil }
                if slot == .secondary, secondary?.identity == id { secondary = nil }
            }
        }
        if batch.closed { primary = nil; secondary = nil; closed = true }
        return true
    }
}

```

```swift id=source7
import Foundation

// Row 195b-56 (arch-195b): clock/session-fenced subtitle cue output. Sits
// Cue transition helper. SubtitleCueDelivery adds generation-tagged transport;
// the embedded session samples its film clock and MetalPresenter consumes batches.
// Sits between SubtitleController (selection state) and the renderer: per clock
// sample it emits typed appear/disappear events, emit-on-change only, fenced
// to one session, with the same one-clock rule as the timePos gate (a
// non-finite clock sample never advances or corrupts output state).

public enum CueOutputEvent: Equatable, Sendable {
    /// A cue became active for the slot. Carries the cue for direct render.
    case appeared(slot: SubtitleController.Slot, identity: SubtitleController.CueIdentity, cue: SubtitleCue)
    /// The slot's active cue ended (left its window) or was replaced.
    case disappeared(slot: SubtitleController.Slot, identity: SubtitleController.CueIdentity)
}

public struct SubtitleCueOutput: Sendable {

    public struct Counters: Equatable, Sendable {
        public var appeared = 0
        public var disappeared = 0
        /// Samples refused because the clock was non-finite.
        public var skippedNonFiniteClock = 0
        /// Samples refused because they carried another session.
        public var fencedSamples = 0
        /// Samples that changed nothing (steady state, no events).
        public var steady = 0
        /// reset() transitions that emitted clears for active slots.
        public var resets = 0
        public init() {}
    }

    public let session: UInt64
    public private(set) var counters = Counters()
    private var currentPrimary: SubtitleController.CueIdentity?
    private var currentSecondary: SubtitleController.CueIdentity?

    public init(session: UInt64) { self.session = session }

    /// Return explicit clears before dropping state. The caller must deliver
    /// these to its consumer or an old cue can remain visible through a seek.
    @discardableResult
    public mutating func reset() -> [CueOutputEvent] {
        var events: [CueOutputEvent] = []
        if let currentPrimary { events.append(.disappeared(slot: .primary, identity: currentPrimary)) }
        if let currentSecondary { events.append(.disappeared(slot: .secondary, identity: currentSecondary)) }
        counters.disappeared += events.count
        currentPrimary = nil
        currentSecondary = nil
        counters.resets += 1
        return events
    }

    /// One clock sample -> zero or more events. Order within a sample:
    /// disappeared events precede the appeared event that replaces them.
    @discardableResult
    public mutating func sample(session: UInt64, clock: Double,
                                controller: SubtitleController) -> [CueOutputEvent] {
        guard session == self.session else {
            counters.fencedSamples += 1
            return []
        }
        guard clock.isFinite else {
            counters.skippedNonFiniteClock += 1
            return []
        }
        var events: [CueOutputEvent] = []
        for slot in [SubtitleController.Slot.primary, .secondary] {
            let now = controller.activeCueIdentity(at: clock, slot: slot)
            let was = slot == .primary ? currentPrimary : currentSecondary
            guard now != was else { continue }
            if let was {
                events.append(.disappeared(slot: slot, identity: was))
                counters.disappeared += 1
            }
            if let now, let cue = controller.activeCue(at: clock, slot: slot) {
                events.append(.appeared(slot: slot, identity: now, cue: cue))
                counters.appeared += 1
            }
            if slot == .primary { currentPrimary = now } else { currentSecondary = now }
        }
        if events.isEmpty { counters.steady += 1 }
        return events
    }
}

```

```swift id=source8
import Foundation

/// TIMED-PLAN IMPLEMENTATION (u8r2) - gorav lanes L5/L6 producer side.
///
/// Status: IMPLEMENTATION of the accepted interface. gdb's Q1-Q5 engineering
/// decision was relayed 2026-11-01 ~02:25 +03 in two parts via coordination -
/// peer-attributed content, NOT verified by us against an authenticated gdb
/// record; an ENGINEERING decision by gdb's side as relayed, NOT an
/// owner/architect ruling; no deploy/live/default change is implied.
/// Split unchanged: gdb owns the CoreText rasterizer and the host/presenter
/// binding; this lane owns the timed plan, plan revision and source cue/style
/// data. SHARED L5/L6 completion holds until real rendering is verified.
///
/// Decisions as relayed via coordination (peer-attributed throughout,
/// unverified by us against an authenticated gdb record) and where this
/// unit implements them:
/// Q1 The revision PAIR is authoritative: contentID (FNV-1a-64 over the
///    length-prefixed canonical serialization) + producer-owned monotonic
///    generation with typed exhaustion. Implemented by SubtitlePlanRevision,
///    SubtitlePlanContentID, SubtitlePlanProducer (carried from p5).
/// Q2 The presenter seam echoes GENERATION ONLY over the existing three
///    points - verified at landed main 261b58e09531cc8ca3505424c760b3af592b0247:
///    PresenterOverlay.subtitlePlanRevision: UInt64?
///    (SurfaceContract.swift:395), setSubtitlePlanAuthority((FrameIdentity)
///    -> UInt64?)? (MetalPresenter.swift:462),
///    OverlayCompositeReceipt.compositedPlanRevision: UInt64?
///    (MetalRenderer.swift:169). contentID stays plan-side; a same-contentID
///    new generation is a NEW revision and must re-admit. This unit exposes
///    plan.presenterEchoRevision for exactly that echo; the seam itself is
///    gdb's and is NOT widened.
/// Q3 OPTION A evictThenBareNotify: presenter-side mechanics (verified
///    present in landed MetalRenderer.swift: typed stale eviction, bare
///    re-render). Producer-side obligation is only what this file already
///    guarantees: generations never reused within a lineage, exhaustion
///    typed-refused, reissue = new pair.
/// Q4 Half-open [start,end); single active render = latest-starting cue; a
///    typed finding reports the SUPPRESSED cue indices - no silent stacking
///    or line merging. Implemented: OverlayAnswer.cue carries
///    suppressedCueIndices.
/// Q5 PlayRes reference metrics: absent PlayRes uses the DECLARED default
///    384x288 and the plan reports usedDefaultPlayRes (receipt edge is
///    presenter-side). Layout/drawable-pixel scaling, margins and frame
///    pull-in are renderer-side (gdb). Implemented: plan.effectivePlayResX/Y
///    + plan.usedDefaultPlayRes. NOTE: contentID still hashes the RAW PlayRes
///    presence/values (P5-1); the declared default is render-time data, not
///    identity. Written against the CANDIDATE SurfaceContract seam
/// (l3-metal-presenter-r7-landing @ 3dfe096a, PresenterOverlay L383-398) -
/// NOT adopted, NOT bound; that candidate is on HOLD at gdb (Mac compile
/// errors, respin 7069096 pending review, also not canonical). The canonical
/// pin and the overlay-staleness ruling are still open. Nothing here reduces
/// the real ASS delivery scope: the requirements below name exactly what the
/// renderer must honor and what stays explicitly UNSUPPORTED.
///
/// p5 revision (2026-11-01): gdb bounded review of p4 (peer-attributed via
/// coordination, NOT ratified, tests are not a ruling):
/// - P5-1 PlayRes is render-relevant but was outside the identity: a
///   PlayRes-only change left contentID unchanged. PlayRes PRESENCE and
///   VALUES are now hashed (per-axis: present flag + exact value).
/// - P5-2 styleName nil and "" collapsed to the same hash (public init can
///   reach both; the parser normalizes empty to nil). Presence is now hashed
///   explicitly: nil and "" are DIFFERENT identities, no silent collision.
///
/// p4 revision (2026-11-01): independent-review scrutiny on the proposed
/// canonical identity (peer-attributed via coordination, NOT ratified):
/// - S1 Length-prefixed text fields: the p3 NUL-terminator framing was not
///   prefix-free for text containing embedded NULs; fields are now hashed as
///   byte-count + bytes, unambiguous for arbitrary UTF-8.
/// - S2 fontSize was rounded to centipoints, collapsing real differences;
///   it is now hashed as its exact Double bitPattern. PRECISION BOUNDARY,
///   explicit: cue start/end are hashed at MILLISECOND resolution (lossless
///   for SRT millisecond and ASS centisecond sources); fontSize and colour
///   are exact. Sub-millisecond cue-time differences are outside the parsed
///   data model and intentionally not identity.
/// - S3 SubtitlePlanProducer confinement documented (single producer per
///   plan lineage, no thread-safety promise, restart seeding contract).
///
/// p3 revision (2026-11-01): incorporates PEER-ATTRIBUTED gdb engineering
/// notes relayed via coordination - engineering feedback, NOT ratified
/// design and NOT an owner ruling:
/// - F1 A pure content hash is only a content IDENTITY: an A->B->A edit
///   sequence returns to the same hash, so an already-invalidated revision
///   could be reused. p3 splits the revision into content identity plus a
///   producer-owned monotonic instance generation; the echoed pair is the
///   authoritative revision.
/// - F2 The canonical serialization previously omitted the
///   unsupportedOverrides and skippedStyles findings; they are now hashed,
///   so a findings change is a content change.
/// - F3 gdb noted the existing OverlayCompositeReceipt.compositedPlanRevision
///   MIGHT be reused as the echo field - noted, review pending at gdb, no
///   binding here. The staleness no-authority gate (render gate passes on
///   receipts alone when no authority is registered) is UNRESOLVED; this
///   proposal takes no position and assumes no candidate.
///
/// Boundary rules (from the candidate seam, verified):
/// - subtitlePlanRevision is PRODUCER-owned and opaque to the presenter; it is
///   echoed in receipts so this lane can verify WHICH plan was composited.
/// - subtitlePlanRevision is NEVER FrameIdentity.trackRevision (decoder/source
///   track semantics); the two fields stay distinct.
/// - The only overlay representation today is sdrRGBA8Premultiplied, valid
///   ONLY against an sdrRGBA8 surface contract. HDR playback has NO valid
///   subtitle overlay representation: it must be refused typed, never
///   misrendered. gdb describes the typed refusal as engineering harm
///   prevention on its side (peer-attributed via coordination, unverified
///   by us, pending canonical pin) - NOT an owner choice and NOT an M4
///   waiver.

/// Producer-owned revision of one issued plan. PROPOSED shape (p3), pending
/// gdb acceptance:
/// - contentID: FNV-1a 64 over the canonical serialization (PlayRes presence
///   + values per axis; cue count, then per cue: index, start/end
///   MILLISECONDS, style name PRESENCE + value, lines; then the
///   style table in file order with EXACT fontSize bitPattern and colour;
///   then the override findings; then the skipped-style findings). Text
///   fields are length-prefixed (byte count + bytes), unambiguous for
///   arbitrary UTF-8 including embedded NULs. Deterministic, content-derived,
///   no timestamps. IDENTITY ONLY - A->B->A returns to the same contentID
///   (gdb note F1).
/// - generation: producer-owned monotonic instance counter, issued by
///   SubtitlePlanProducer, never reused within a producer. The PAIR is the
///   authoritative echoed revision: identical contentID with a newer
///   generation is a NEW revision, so an invalidated revision can never be
///   resurrected by editing back to old content.
public struct SubtitlePlanRevision: Equatable, Sendable {
    public let contentID: UInt64
    public let generation: UInt64
    public init(contentID: UInt64, generation: UInt64) {
        self.contentID = contentID
        self.generation = generation
    }
}

/// Canonical content identity behind SubtitlePlanRevision.contentID.
public enum SubtitlePlanContentID {
    public static func compute(cues: [SubtitleCue], styles: [ASSParser.Style],
                               playResX: Int?, playResY: Int?,
                               unsupportedOverrides: [ASSParser.OverrideReport],
                               skippedStyles: [ASSParser.SkippedStyle]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func feed(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        func feedText(_ s: String) { feed(UInt64(s.utf8.count)); for b in s.utf8 { feed(UInt64(b)) } }
        func feedOptText(_ s: String?) { feed(s == nil ? 0 : 1); if let s { feedText(s) } }
        func feedOptInt(_ v: Int?) { feed(v == nil ? 0 : 1); if let v { feed(UInt64(bitPattern: Int64(v))) } }
        // PlayRes is render-relevant identity (gdb review P5-1): presence AND
        // values, per axis.
        feedOptInt(playResX)
        feedOptInt(playResY)
        feed(UInt64(cues.count))
        for c in cues {
            feed(UInt64(bitPattern: Int64(c.index)))
            feed(UInt64(bitPattern: Int64((c.startSeconds * 1000).rounded())))
            feed(UInt64(bitPattern: Int64((c.endSeconds * 1000).rounded())))
            // nil and "" are DISTINCT identities (gdb review P5-2).
            feedOptText(c.styleName)
            for line in c.lines { feedText(line) }
        }
        for s in styles {
            feedText(s.name); feedText(s.fontName)
            feed(s.fontSize.bitPattern)
            feed(UInt64(s.primaryColourARGB))
        }
        // Findings are part of the identity (gdb note F2): a plan whose
        // overrides or skipped styles differ is different content.
        feed(UInt64(unsupportedOverrides.count))
        for o in unsupportedOverrides {
            feed(UInt64(bitPattern: Int64(o.cueIndex)))
            feed(UInt64(o.tags.count))
            for t in o.tags { feedText(t) }
        }
        feed(UInt64(skippedStyles.count))
        for s in skippedStyles {
            feed(UInt64(bitPattern: Int64(s.line)))
            feedText(s.reason)
        }
        return h
    }
}

/// One immutable timed plan: parsed track data plus its producer revision.
public struct SubtitlePlan: Equatable, Sendable {
    public let track: SubtitleTrack.Track
    public let schedule: SubtitleSchedule
    public let planRevision: SubtitlePlanRevision
    /// ASS PlayRes layout reference frame, RAW (nil for SRT / absent). These
    /// raw values are what the contentID hashes (P5-1).
    public var playResX: Int? { track.playResX }
    public var playResY: Int? { track.playResY }
    /// Q5 declared default reference frame when PlayRes is absent.
    public static let defaultPlayResX = 384
    public static let defaultPlayResY = 288
    /// Effective render-reference metrics: raw PlayRes, else the DECLARED
    /// default (Q5 - declared, not parsed; the presenter reports the
    /// usedDefaultPlayRes receipt edge).
    public var effectivePlayResX: Int { track.playResX ?? SubtitlePlan.defaultPlayResX }
    public var effectivePlayResY: Int { track.playResY ?? SubtitlePlan.defaultPlayResY }
    /// True when the effective metrics come from the declared default.
    /// PER-AXIS fallback: if exactly one axis is absent, that axis uses the
    /// declared default while the other keeps its raw value (mixed state),
    /// and this flag is still true.
    public var usedDefaultPlayRes: Bool { track.playResX == nil || track.playResY == nil }
    /// Q2: the generation-only value the presenter seam echoes
    /// (subtitlePlanRevision / compositedPlanRevision). contentID never
    /// crosses the seam.
    public var presenterEchoRevision: UInt64 { planRevision.generation }

    /// Typed plan-level findings: cue-data anomalies a consumer must see
    /// rather than have silently change an answer's meaning.
    public enum PlanFinding: Equatable, Sendable {
        /// Two or more cues share the same index. Parser-assigned indices
        /// are unique monotonic track order, so this is unreachable on
        /// parsed tracks; it guards PUBLIC construction where callers can
        /// supply arbitrary cues. While present, index-based suppression
        /// reporting (OverlayAnswer.cue suppressedCueIndices) is ambiguous
        /// for the listed indices: a non-winner cue sharing the winner's
        /// index is NOT listed as suppressed.
        case duplicateCueIndices([Int])
    }
    public let findings: [PlanFinding]

    public init(track: SubtitleTrack.Track, revision: SubtitlePlanRevision) {
        self.track = track
        self.schedule = SubtitleSchedule(cues: track.cues)
        self.planRevision = revision
        let indices = track.cues.map { $0.index }
        let dups = Dictionary(grouping: indices, by: { $0 })
            .filter { $0.value.count > 1 }.map { $0.key }.sorted()
        // Derived from cues, which the contentID already hashes: no contentID
        // input change (a findings change here IS a cues change upstream).
        self.findings = dups.isEmpty ? [] : [.duplicateCueIndices(dups)]
    }
}

/// Producer that owns the monotonic generation behind plan revisions.
/// Generations are issued strictly increasing and NEVER reused: exhaustion
/// is a typed refusal, not a silent wrap (gdb note F1; the
/// exhaustion/invalid-generation behavior is part of THIS proposal, still
/// open for gdb).
///
/// Restart continuity: a producer that restarts must be seeded with the last
/// generation it issued (startingGeneration:). Seeding with a LOWER value
/// than actually issued violates monotonicity - caller contract, stated
/// because the alternative (silent reuse) is exactly the failure F1 names.
///
/// CONFINEMENT (review note S3): one producer owns one plan lineage. This
/// class is NOT thread-safe: call makePlan/updateTrack from a single
/// serialized execution context. Do NOT run two producers over the same
/// lineage (two counters would issue overlapping generations, silently
/// breaking the pair's uniqueness); after a restart, seed exactly one new
/// producer with the last issued generation.
public final class SubtitlePlanProducer {
    public enum RevisionError: Error, Equatable {
        /// The generation space is exhausted; issuing another revision would
        /// wrap or reuse. Typed refusal - never wraps, never reuses.
        case generationExhausted
    }

    public private(set) var lastGeneration: UInt64
    private var track: SubtitleTrack.Track

    public init(track: SubtitleTrack.Track, startingGeneration: UInt64 = 0) {
        self.track = track
        self.lastGeneration = startingGeneration
    }

    /// Issue a plan for the current track with the next generation.
    public func makePlan() throws -> SubtitlePlan {
        guard lastGeneration < UInt64.max else { throw RevisionError.generationExhausted }
        lastGeneration += 1
        return SubtitlePlan(track: track, revision: SubtitlePlanRevision(
            contentID: SubtitlePlanContentID.compute(
                cues: track.cues, styles: track.styles,
                playResX: track.playResX, playResY: track.playResY,
                unsupportedOverrides: track.unsupportedOverrides,
                skippedStyles: track.skippedStyles),
            generation: lastGeneration))
    }

    /// Replace the track and issue a plan with the next generation.
    public func updateTrack(_ newTrack: SubtitleTrack.Track) throws -> SubtitlePlan {
        track = newTrack
        return try makePlan()
    }
}

/// What the producer answers when the presenter asks what to render for a
/// frame. Typed; the HDR case is a REFUSAL, not a degraded render.
public enum OverlayAnswer: Equatable, Sendable {
    /// No cue active at this pts; presenter composites nothing.
    case empty(planRevision: SubtitlePlanRevision)
    /// The active cue (latest-starting per the Q4 decision) with its plan
    /// revision and the indices of any OTHER cues covering the same pts
    /// (suppressed, never stacked or merged), sorted ascending. Equal-start
    /// ties resolve to first in track order - ALIGNED with
    /// SubtitleSchedule.activeCue (both keep the first maximal); consumers
    /// must not re-derive a winner with a last-wins rule. Style
    /// association, lines and the style table travel on the plan;
    /// override/skipped-style findings travel on the track.
    case cue(SubtitleCue, suppressedCueIndices: [Int], planRevision: SubtitlePlanRevision)
    /// HDR surface contract: no supported overlay representation exists.
    /// Typed refusal - compositing SDR-gamma text into an HDR surface is a
    /// misrender, not a fallback.
    case hdrUnsupported(planRevision: SubtitlePlanRevision)
}

public extension SubtitlePlan {
    /// surfaceIsHDR: the presenter names the surface contract class it is
    /// compositing against (true for nativeHDR / edrRGBA16F; the candidate
    /// contract rejects SDR overlays there typed). Producer-side this is a
    /// boolean proposal input until the canonical pin lands.
    ///
    /// PRECONDITION: cue indices are unique (parser-assigned indices are
    /// monotonic track order, so parsed tracks always satisfy this).
    /// suppressedCueIndices is index-based: a non-winner cue SHARING the
    /// winner's index would not be reported. Public construction with
    /// duplicate indices is not refused but is surfaced as the typed plan
    /// finding SubtitlePlan.PlanFinding.duplicateCueIndices (gdb u8r1
    /// review note 1).
    func overlay(at ptsSeconds: Double, surfaceIsHDR: Bool) -> OverlayAnswer {
        if surfaceIsHDR { return .hdrUnsupported(planRevision: planRevision) }
        // Q4: all cues covering pts (half-open); latest-starting wins, the
        // rest are reported as suppressed - never stacked or merged.
        // TIE RULE (peer-confirmed 2026-11-01 via coordination): among cues
        // with the SAME latest start, the one FIRST IN TRACK ORDER wins; the
        // rest are suppressed. Swift's max(by:) keeps the first maximal
        // element, so the rule is deterministic and track-order-stable.
        // Aligned with SubtitleSchedule.activeCue, which also keeps the FIRST
        // maximal (strictly-greater replacement) - no drift between the two
        // winner paths (gdb u8r1 review note 4, noted not changed).
        let covering = track.cues.filter { $0.startSeconds <= ptsSeconds && ptsSeconds < $0.endSeconds }
        guard let winner = covering.max(by: { $0.startSeconds < $1.startSeconds }) else {
            return .empty(planRevision: planRevision)
        }
        let suppressed = covering.filter { $0.index != winner.index }.map { $0.index }.sorted()
        return .cue(winner, suppressedCueIndices: suppressed, planRevision: planRevision)
    }
}

/// STYLE/RENDER REQUIREMENTS R1-R6 for gdb's rasterizer. Scope label per
/// gdb's own request (peer-attributed via coordination): accepted as gdb
/// MAIN-SIDE ENGINEERING scope, NOT an owner or architect ruling. The parser
/// data behind each is ALREADY shipped and execution-verified:
///
/// R1 Honor the line structure: SubtitleCue.lines are explicit line breaks
///    (SRT newlines; ASS \N and \n both became breaks at parse time; \h is a
///    non-breaking space U+00A0 already materialized in the text).
/// R2 Honor the per-cue style ASSOCIATION (SubtitleCue.styleName) against the
///    plan's style table: name, fontName, fontSize, primaryColourARGB
///    (decoded AARRGGBB from ASS &HAABBGGRR). That is the full parsed style
///    scope - bold/italic/outline/shadow/margins/alignment are NOT parsed and
///    MUST NOT be invented by the renderer.
/// R3 PlayRes (plan.playResX/playResY, carried through the loader) is the
///    layout reference frame; scaling to the drawable is renderer-side.
///    Missing PlayRes: renderer uses its default and says so.
/// R4 UNSUPPORTED, never silently rendered: every cue listed in
///    track.unsupportedOverrides carries ASS override tags (\pos, \move, \fad,
///    \clip, karaoke, drawing, ...) that were reported, not interpreted. The
///    renderer must show the cue's PLAIN TEXT and MUST NOT apply those
///    effects; the not-rendered record stays queryable on the plan.
/// R5 override-only events never reach the plan (typed refusal at parse);
///    malformed styles are visible in track.skippedStyles and are not
///    available to the renderer.
/// R6 Timing is the half-open interval [startSeconds, endSeconds) in media
///    seconds; one active cue per pts (latest-starting wins on overlaps).
///    Multi-cue stacking is OUT of v1 scope (interface question Q4 below).
///
/// INTERFACE QUESTIONS - RESOLVED per gdb's 2026-11-01 engineering decision
/// as relayed via coordination (peer-attributed, unverified by us against an
/// authenticated gdb record; recorded here for traceability):
/// Q1 per the relayed decision: the two-part revision (contentID + producer monotonic
///    generation, typed exhaustion, single-producer restart seeding). A->B->A
///    yields a new generation. Reissue semantics decided: same contentID with
///    a new generation IS a new revision and must re-admit (Q2 text).
/// Q2 per the relayed decision: the existing three-point seam stays UNWIDENED and echoes the
///    GENERATION only; authority registration is session-scoped (sessionID +
///    sessionGeneration); equality is sufficient; contentID stays plan-side;
///    the render cache MAY key on contentID. Verified seam pins cited above.
/// Q3 per the relayed decision: OPTION A evictThenBareNotify (P1 typed whole-present refusal;
///    P2 commit checks the registered authority; P3/P4 typed eviction +
///    counted bare re-render; staleOverlayEvicted receipt edge). Presenter
///    side; producer guarantees noted above. A later override must be an
///    explicit policy; undecided production refuses.
/// Q4 per the relayed decision: half-open [start,end); single active render = latest-starting
///    cue; suppressed cue indices reported as a typed finding; no stacking
///    or line merging (margins/alignment unparsed - stacking would invent
///    geometry; revisit when parsing lands).
/// Q5 per the relayed decision: three spaces - ASS PlayRes reference metrics (declared
///    default 384x288 with usedDefaultPlayRes receipt when absent); layout
///    in drawable pixels (font scales by drawableHeight/playResY; declared
///    default bottom-center, margin fraction 0.05); presenter Int frame
///    pixels via rendererAspectFit with reported placement. Only the
///    PlayRes metrics + default declaration are this lane's; the rest is
///    renderer-side (gdb).

```

```swift id=source9
import Foundation

/// Time-ordered cue schedule with structural validation (lanes L5/L6, u2).
/// Pure model: the presenter hook (peer lane, interface pin pending) consumes
/// activeCue(at:). File order is preserved; structural issues are reported,
/// not silently repaired.
public struct SubtitleSchedule: Equatable, Sendable {

    public enum Issue: Equatable, Sendable {
        case outOfOrder(index: Int)          // start earlier than the previous cue's start
        case overlap(index: Int, previous: Int) // starts inside the previous cue's interval
    }

    public let cues: [SubtitleCue]
    public let issues: [Issue]

    public init(cues: [SubtitleCue]) {
        var found: [Issue] = []
        var maxStart = -Double.infinity
        for i in 0..<cues.count {
            // Out-of-order vs the running maximum start, not just the previous
            // cue: an early cue after several later ones is still flagged.
            if cues[i].startSeconds < maxStart {
                found.append(.outOfOrder(index: cues[i].index))
            }
            maxStart = max(maxStart, cues[i].startSeconds)
            // Overlap against EVERY earlier cue, not only the adjacent one:
            // out-of-order input can hide non-adjacent interval intersections.
            for j in 0..<i where cues[j].startSeconds < cues[i].endSeconds
                    && cues[i].startSeconds < cues[j].endSeconds {
                found.append(.overlap(index: cues[i].index, previous: cues[j].index))
            }
        }
        self.cues = cues
        self.issues = found
    }

    /// The active cue with the LATEST start whose half-open interval holds t,
    /// or nil. File order is irrelevant to the result (overlapping cues resolve
    /// to the latest-starting one; stacked rendering is a presenter decision,
    /// not a model one).
    public func activeCue(at t: Double) -> SubtitleCue? {
        var best: SubtitleCue? = nil
        for cue in cues where cue.contains(seconds: t) {
            if best == nil || cue.startSeconds > best!.startSeconds { best = cue }
        }
        return best
    }
}

```

```swift id=source10
import Foundation

public enum SubtitleSidecarRefusal: Error, Equatable, Sendable {
    case closed, unsupportedSource, sourceUnavailable, notDiscovered, unsupportedASS
    case unreadable, malformed, staleCompletion, invalidDelay
}
public enum SubtitleSidecarSelection: Equatable, Sendable {
    case selected(path: String, slot: SubtitleController.Slot)
    case cleared(slot: SubtitleController.Slot)
    case noExactSidecar
    case refused(SubtitleSidecarRefusal)
}

/// Generation receipt for a selection outcome: the selection plus the source
/// path and producer generation it was made against. Callers reject a receipt
/// whose generation no longer matches the live session.
public struct SubtitleSelectionReceipt: Equatable, Sendable {
    public let selection: SubtitleSidecarSelection
    public let sourcePath: String?
    public let generation: UInt64
    public init(selection: SubtitleSidecarSelection, sourcePath: String?, generation: UInt64) {
        self.selection = selection; self.sourcePath = sourcePath; self.generation = generation
    }
    public func isCurrent(sourcePath: String?, generation: UInt64) -> Bool {
        self.sourcePath == sourcePath && self.generation == generation
    }
}

/// The actual portable selection/clock producer owner. No remote discovery,
/// network I/O, language ranking or guessed tagged default. The host delivers
/// emit synchronously to its render consumer. All completions recheck source
/// revision and per-slot request ticket before changing selection or cues.
@MainActor
public final class SubtitleSidecarSession {
    public typealias Loader = @Sendable (String) async throws -> SubtitleTrack.Track
    public let session: UInt64
    public private(set) var sourcePath: String?
    public private(set) var candidates: [SubtitleAutoLoad.Candidate] = []
    public private(set) var controller = SubtitleController()
    public var generation: UInt64 { producer.generation }
    private var producer: SubtitleCueProducer
    private var sourceRevision: UInt64 = 0
    private var primaryTicket: UInt64 = 0
    private var secondaryTicket: UInt64 = 0
    private var closed = false
    private var filmTime: Double?
    private let emit: (SubtitleCueBatch) -> Void
    private let loader: Loader

    public init(session: UInt64, emit: @escaping (SubtitleCueBatch) -> Void,
                loader: @escaping Loader = { path in
                    try await Task.detached(priority: .utility) { try SubtitleTrack.load(path: path) }.value
                }) {
        self.session = session; self.emit = emit; self.loader = loader
        producer = SubtitleCueProducer(session: session)
    }
    /// Always clears the previous source before admission, including a refused
    /// remote replacement. A missing video is distinct from a valid source with
    /// no sidecars. Source paths and candidate paths are canonical local paths.
    @discardableResult
    public func replaceSource(path: String) -> SubtitleSidecarRefusal? {
        guard !closed else { return .closed }
        invalidateLoads(); clearGeneration(); controller = SubtitleController()
        filmTime = nil; sourcePath = nil; candidates = []
        guard path.hasPrefix("/"), !path.contains("://") else { return .unsupportedSource }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return .sourceUnavailable }
        sourcePath = url.path
        let parent = url.deletingLastPathComponent().path
        candidates = SubtitleAutoLoad.discover(forVideoPath: url.path).filter { candidate in
            let canonical = URL(fileURLWithPath: candidate.path).standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            return canonical.deletingLastPathComponent().path == parent
                && FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }.map { SubtitleAutoLoad.Candidate(path: URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path,
                                          tag: $0.tag, format: $0.format) }
        return nil
    }
    /// Exact SRT only. Tagged files are never selected without an explicit choice.
    public func loadExactPrimary() async -> SubtitleSidecarSelection {
        guard !closed else { return .refused(.closed) }
        guard sourcePath != nil else { return .refused(.sourceUnavailable) }
        if let exact = candidates.first(where: { $0.tag == nil && $0.format == "srt" }) {
            return await select(path: exact.path, slot: .primary)
        }
        if candidates.contains(where: { $0.tag == nil && $0.format == "ass" }) { return .refused(.unsupportedASS) }
        return .noExactSidecar
    }
    public func select(path: String, slot: SubtitleController.Slot) async -> SubtitleSidecarSelection {
        guard !closed else { return .refused(.closed) }
        guard sourcePath != nil, let candidate = candidates.first(where: { $0.path == path }) else { return .refused(.notDiscovered) }
        guard candidate.format == "srt" else { return .refused(.unsupportedASS) }
        let revision = sourceRevision
        bumpTicket(slot)
        let ticket = currentTicket(slot)
        let track: SubtitleTrack.Track
        do { track = try await loader(candidate.path) }
        catch {
            guard isCurrent(revision: revision, slot: slot, ticket: ticket) else { return .refused(.staleCompletion) }
            if Task.isCancelled { return .refused(.staleCompletion) }
            if case SubtitleTrack.LoadError.unreadable = error { return .refused(.unreadable) }
            return .refused(.malformed)
        }
        guard !Task.isCancelled, isCurrent(revision: revision, slot: slot, ticket: ticket) else { return .refused(.staleCompletion) }
        guard track.format == "srt", track.styles.isEmpty, track.unsupportedOverrides.isEmpty,
              track.skippedStyles.isEmpty else { return .refused(.unsupportedASS) }
        clearGeneration()
        if slot == .primary { controller.selectPrimary(track) } else { controller.selectSecondary(track) }
        sampleLastTime()
        return .selected(path: candidate.path, slot: slot)
    }
    @discardableResult
    public func setDelay(_ seconds: Double, slot: SubtitleController.Slot) -> SubtitleSidecarRefusal? {
        guard !closed else { return .closed }
        guard seconds.isFinite else { return .invalidDelay }
        controller.setDelay(seconds, slot: slot); clearGeneration(); sampleLastTime(); return nil
    }
    /// Explicit off for one slot (mpv sub-visibility off), primary, secondary
    /// or off as named selection states. Keeps the track loaded; select or
    /// setVisible(true) turns it back on.
    @discardableResult
    public func setOff(_ slot: SubtitleController.Slot) -> SubtitleSidecarSelection {
        guard !closed else { return .refused(.closed) }
        controller.setVisible(false, slot: slot); clearGeneration(); sampleLastTime()
        return .cleared(slot: slot)
    }
    /// Receipt for any selection outcome, stamped with the live generation.
    public func selectionReceipt(for selection: SubtitleSidecarSelection) -> SubtitleSelectionReceipt {
        SubtitleSelectionReceipt(selection: selection, sourcePath: sourcePath, generation: generation)
    }
    public func setVisible(_ visible: Bool, slot: SubtitleController.Slot) {
        guard !closed else { return }
        controller.setVisible(visible, slot: slot); clearGeneration(); sampleLastTime()
    }
    /// Same semantics as SubtitleController.reset: keep primary; remove secondary,
    /// zero delay and restore visibility. Invalidates pre-reset async loads.
    public func reset() {
        guard !closed else { return }
        invalidateLoads(); clearGeneration(); controller.reset(); sampleLastTime()
    }
    /// Explicit external controller replacement shares the same source/async fence.
    @discardableResult
    public func setController(_ value: SubtitleController) -> Bool {
        guard !closed, sourcePath != nil else { return false }
        for track in [value.primary, value.secondary].compactMap({ $0 }) {
            guard track.format == "srt", track.styles.isEmpty,
                  track.unsupportedOverrides.isEmpty, track.skippedStyles.isEmpty else { return false }
        }
        invalidateLoads(); clearGeneration(); controller = value; sampleLastTime(); return true
    }
    public func sample(session: UInt64, generation: UInt64, filmTime: Double) {
        guard !closed, sourcePath != nil, session == self.session,
              generation == producer.generation, filmTime.isFinite else { return }
        self.filmTime = filmTime
        sampleLastTime()
    }
    public func seekBegan() {
        guard !closed else { return }
        invalidateLoads(); clearGeneration(); filmTime = nil
    }
    public func close() {
        guard !closed else { return }
        invalidateLoads(); closed = true; sourcePath = nil; candidates = []; filmTime = nil
        controller = SubtitleController()
        if let batch = producer.close() { emit(batch) }
    }
    private func sampleLastTime() {
        guard let filmTime, let batch = producer.sample(session: session, generation: producer.generation,
                                                       filmTime: filmTime, controller: controller) else { return }
        emit(batch)
    }
    private func clearGeneration() { if let batch = producer.advance() { emit(batch) } }
    private func currentTicket(_ slot: SubtitleController.Slot) -> UInt64 { slot == .primary ? primaryTicket : secondaryTicket }
    private func bumpTicket(_ slot: SubtitleController.Slot) {
        if slot == .primary { primaryTicket &+= 1 } else { secondaryTicket &+= 1 }
    }
    private func invalidateLoads() { sourceRevision &+= 1; primaryTicket &+= 1; secondaryTicket &+= 1 }
    private func isCurrent(revision: UInt64, slot: SubtitleController.Slot, ticket: UInt64) -> Bool {
        !closed && revision == sourceRevision && ticket == currentTicket(slot)
    }
}

```

```swift id=source11
import Foundation

/// Sidecar subtitle track loader (lanes L5/L6, unit u2): picks the parser by
/// file extension (.srt, .ass, .ssa) and returns cues plus the optional ASS
/// style table. Unknown extensions and unreadable files are typed refusals,
/// never silent fallbacks. Pure loader; no playback or rendering here.
public enum SubtitleTrack {

    public enum LoadError: Error, Equatable {
        case unknownFormat(path: String)
        case unreadable(path: String)
    }

    public struct Track: Equatable, Sendable {
        public let format: String // "srt" or "ass" (.ssa normalizes to "ass")
        public let cues: [SubtitleCue]
        public let styles: [ASSParser.Style]
        /// ASS override blocks detected during load: UNSUPPORTED rendering
        /// instructions, reported, never silently stripped. Empty for SRT.
        public let unsupportedOverrides: [ASSParser.OverrideReport]
        /// ASS Style rows that failed parsing during load: caller-visible at
        /// the loader entry point too, never dropped between parser and
        /// consumer. Empty for SRT.
        public let skippedStyles: [ASSParser.SkippedStyle]
        /// ASS PlayRes layout reference frame; nil for SRT or when absent.
        public let playResX: Int?
        public let playResY: Int?
        /// Stable local-sidecar identifier: FNV-1a over format plus every cue's
        /// timing and text. Stable across reloads of the same file content.
        public let sidecarID: String

        public init(format: String, cues: [SubtitleCue], styles: [ASSParser.Style],
                    unsupportedOverrides: [ASSParser.OverrideReport],
                    skippedStyles: [ASSParser.SkippedStyle], playResX: Int?, playResY: Int?,
                    sidecarID: String? = nil) {
            self.format = format
            self.cues = cues
            self.styles = styles
            self.unsupportedOverrides = unsupportedOverrides
            self.skippedStyles = skippedStyles
            self.playResX = playResX
            self.playResY = playResY
            self.sidecarID = sidecarID ?? SubtitleTrack.stableSidecarID(format: format, cues: cues)
        }
    }

    /// Stable local-sidecar identifier: FNV-1a over the format and the full cue
    /// list (index, start/end milliseconds, text). Content-addressed, so a file
    /// move keeps the ID and a content edit changes it.
    public static func stableSidecarID(format: String, cues: [SubtitleCue]) -> String {
        var hash: UInt64 = 14695981039346656037
        func mix(_ text: String) { for byte in text.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 } }
        mix(format)
        for cue in cues {
            // cue.index is a proven field; String(describing:) covers the full
            // cue value without depending on unexposed timing field names.
            mix("\(cue.index)|")
            mix(String(describing: cue))
        }
        return String(format: "%016llx", hash)
    }

    /// Embedded-subtitle support, distinct from sidecar loading: text-based
    /// embedded codecs are supported; image-based ones are a named refusal.
    public enum EmbeddedSupport: Equatable, Sendable {
        case supported
        case unsupported(codec: String)
    }

    /// Classifies an embedded subtitle codec. Distinguishes unsupported embedded
    /// subtitles (PGS/DVB/DVB teletext-style image codecs) from text ones.
    public static func embeddedSupport(codec: String) -> EmbeddedSupport {
        switch codec.lowercased() {
        case "subrip", "mov_text", "webvtt", "ass", "ssa", "srt", "text", "subviewer", "microdvd":
            return .supported
        default:
            return .unsupported(codec: codec)
        }
    }

    public static func load(path: String) throws -> Track {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "srt" || ext == "ass" || ext == "ssa" else { throw LoadError.unknownFormat(path: path) }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            throw LoadError.unreadable(path: path)
        }
        if ext == "srt" {
            return Track(format: "srt", cues: try SRTParser.parse(text), styles: [],
                         unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        }
        let doc = try ASSParser.parse(text)
        return Track(format: "ass", cues: doc.cues, styles: doc.styles,
                     unsupportedOverrides: doc.unsupportedOverrides, skippedStyles: doc.skippedStyles,
                     playResX: doc.playResX, playResY: doc.playResY)
    }
}

```

```swift id=source12
/// Strict, bounded WebVTT parser. Same role as SRTParser: whole-document text
/// in, `SubtitleCue` values out, typed refusals on malformed input, no guessing
/// and no partial adoption of a broken block.
///
/// Scope (documented boundaries):
/// - Signature line: "WEBVTT" alone or followed by a space/tab and free text.
///   Keywords (WEBVTT, NOTE, STYLE, REGION, setting names) are case-sensitive and
///   matched on Unicode scalars, so no locale or case folding (Turkish dotted /
///   dotless i) can change what a keyword means.
/// - A blank line is an EMPTY line (WebVTT rule, unlike SRT): a whitespace-only
///   line is cue text. Tolerates a UTF-8 BOM and CR/LF/CRLF endings.
/// - Blocks: header block, then NOTE (skipped, typed; keyword + space/tab/EOL),
///   STYLE and REGION (keyword ALONE on the line; "STYLE foo" is a cue identifier),
///   cue blocks. STYLE/REGION after the first cue refuse.
/// - Cue: optional identifier line (must not contain "-->"), timing line
///   "start --> end [settings]" (separator: whitespace, "-->", whitespace),
///   one or more text lines (no "-->"), kept verbatim (inline tags untouched).
/// - Timestamps: [hh:]mm:ss.ttt, hours >= 2 digits, mm/ss two digits < 60,
///   milliseconds exactly three digits, "." only. end must be > start.
/// - Settings: vertical, line, position, size, align, region. Unknown names,
///   bad values, duplicates and unknown region ids refuse (stricter than the
///   spec, which ignores them; chosen to match SRTParser's no-guessing stance).
/// - Overlapping cues are accepted; file order is preserved. `SubtitleCue.index`
///   is the 1-based position of the cue in file order. Identifiers and settings
///   do not fit the pinned SubtitleCue type (unchanged), so they travel in the
///   parallel `VTTDocument.cueInfo` array.
/// - Malformed-input recovery: refuse the whole document with one typed error
///   (no partial adoption of earlier good cues), consistent with SRTParser.
/// - Bounds: input size, line count, cue count, line length (see `Limits`).
public enum VTTParser {

    public enum VTTError: Error, Equatable {
        case emptyDocument
        case inputTooLarge(limit: Int)
        case tooManyLines(limit: Int)
        case lineTooLong(line: Int, limit: Int)
        case tooManyCues(limit: Int)
        case missingSignature(line: Int)
        case badHeader(line: Int)
        case badTimingLine(line: Int)
        case badTimestamp(line: Int)
        case endNotAfterStart(line: Int)
        case missingText(line: Int)
        case textContainsArrow(line: Int)
        case badSetting(line: Int)
        case duplicateSetting(line: Int)
        case unknownRegion(line: Int)
        case badRegion(line: Int)
        case misplacedBlock(line: Int)
        case noteContainsArrow(line: Int)
    }

    public struct Limits: Equatable, Sendable {
        public var maxBytes: Int
        public var maxLines: Int
        public var maxLineScalars: Int
        public var maxCues: Int
        public init(maxBytes: Int = 16 * 1024 * 1024, maxLines: Int = 1_000_000,
                    maxLineScalars: Int = 65_536, maxCues: Int = 200_000) {
            self.maxBytes = maxBytes; self.maxLines = maxLines
            self.maxLineScalars = maxLineScalars; self.maxCues = maxCues
        }
        public static let `default` = Limits()
    }

    public enum Direction: String, Equatable, Sendable { case rl, lr }
    public enum Align: String, Equatable, Sendable { case start, center, end, left, right, lineLeft = "line-left", lineRight = "line-right" }
    public enum LinePosition: Equatable, Sendable {
        case number(Int)
        case percent(Double)
    }

    public struct CueSettings: Equatable, Sendable {
        public var vertical: Direction?
        public var line: LinePosition?
        public var lineAlign: Align?
        public var position: Double?
        public var positionAlign: Align?
        public var size: Double?
        public var align: Align?
        public var region: String?
        public init() {}
    }

    public struct Region: Equatable, Sendable {
        public var id: String
        public var width: Double?
        public var lines: Int?
        public var regionAnchor: (x: Double, y: Double)?
        public var viewportAnchor: (x: Double, y: Double)?
        public var scrollUp: Bool
        public static func == (a: Region, b: Region) -> Bool {
            a.id == b.id && a.width == b.width && a.lines == b.lines && a.scrollUp == b.scrollUp
                && a.regionAnchor?.x == b.regionAnchor?.x && a.regionAnchor?.y == b.regionAnchor?.y
                && a.viewportAnchor?.x == b.viewportAnchor?.x && a.viewportAnchor?.y == b.viewportAnchor?.y
        }
    }

    public struct CueInfo: Equatable, Sendable {
        public var identifier: String?
        public var settings: CueSettings
        /// 1-based line of the timing line.
        public var timingLine: Int
    }

    public enum SkippedKind: Equatable, Sendable { case note, style }
    public struct SkippedBlock: Equatable, Sendable {
        public var kind: SkippedKind
        public var line: Int
        public var lines: [String]
    }

    public struct Document: Equatable, Sendable {
        public var headerText: String
        public var cues: [SubtitleCue]
        /// Parallel to `cues`.
        public var cueInfo: [CueInfo]
        public var regions: [Region]
        public var skipped: [SkippedBlock]
    }

    /// Mirrors SRTParser.parse, with the Result form named by the packet.
    public static func parse(_ text: String) -> Result<[SubtitleCue], VTTError> {
        parse(text, limits: .default)
    }

    public static func parse(_ text: String, limits: Limits) -> Result<[SubtitleCue], VTTError> {
        do { return .success(try parseDocument(text, limits: limits).cues) }
        catch let e as VTTError { return .failure(e) }
        catch { preconditionFailure("unreachable: only VTTError is thrown") }
    }

    /// Throwing form, same shape as `SRTParser.parse`.
    public static func parseThrowing(_ text: String) throws -> [SubtitleCue] {
        try parseDocument(text, limits: .default).cues
    }

    public static func parseDocument(_ content: String, limits: Limits = .default) throws -> Document {
        guard content.utf8.count <= limits.maxBytes else { throw VTTError.inputTooLarge(limit: limits.maxBytes) }
        let lines = try splitLines(content, limits: limits)

        // Signature.
        guard let first = lines.first else { throw VTTError.emptyDocument }
        guard let header = headerText(first) else {
            if lines.allSatisfy({ $0.isEmpty }) { throw VTTError.emptyDocument }
            throw VTTError.missingSignature(line: 1)
        }
        var i = 1
        // Header block continues to the first empty line. It must not hold "-->".
        while i < lines.count && !lines[i].isEmpty {
            if lines[i].contains("-->") { throw VTTError.badHeader(line: i + 1) }
            i += 1
        }

        var doc = Document(headerText: header, cues: [], cueInfo: [], regions: [], skipped: [])
        var regionIDs = Set<String>()

        while i < lines.count {
            while i < lines.count && lines[i].isEmpty { i += 1 }
            guard i < lines.count else { break }
            let start = i
            var block: [String] = []
            while i < lines.count && !lines[i].isEmpty { block.append(lines[i]); i += 1 }
            let startLine = start + 1
            let head = block[0]

            if isKeyword(head, "NOTE") {
                for (k, l) in block.enumerated() where l.contains("-->") { throw VTTError.noteContainsArrow(line: startLine + k) }
                doc.skipped.append(SkippedBlock(kind: .note, line: startLine, lines: block))
                continue
            }
            if head == "STYLE" {
                if !doc.cues.isEmpty { throw VTTError.misplacedBlock(line: startLine) }
                doc.skipped.append(SkippedBlock(kind: .style, line: startLine, lines: block))
                continue
            }
            if head == "REGION" {
                if !doc.cues.isEmpty { throw VTTError.misplacedBlock(line: startLine) }
                let r = try parseRegion(block, startLine: startLine)
                guard !regionIDs.contains(r.id) else { throw VTTError.badRegion(line: startLine) }
                regionIDs.insert(r.id)
                doc.regions.append(r)
                continue
            }

            // Cue block.
            var k = 0
            var identifier: String? = nil
            if !head.contains("-->") {
                identifier = head
                k = 1
            }
            guard k < block.count, block[k].contains("-->") else { throw VTTError.badTimingLine(line: startLine + k) }
            let timingLine = startLine + k
            let (s, e, settings) = try parseTiming(block[k], line: timingLine, regions: regionIDs)
            let textLines = Array(block[(k + 1)...])
            guard !textLines.isEmpty else { throw VTTError.missingText(line: timingLine + 1) }
            for (t, l) in textLines.enumerated() where l.contains("-->") {
                throw VTTError.textContainsArrow(line: timingLine + 1 + t)
            }
            guard doc.cues.count < limits.maxCues else { throw VTTError.tooManyCues(limit: limits.maxCues) }
            doc.cues.append(SubtitleCue(index: doc.cues.count + 1, startSeconds: s, endSeconds: e, lines: textLines))
            doc.cueInfo.append(CueInfo(identifier: identifier, settings: settings, timingLine: timingLine))
        }
        return doc
    }

    // MARK: - Lines

    /// Splits on CRLF / CR / LF over unicode scalars (Swift treats "\r\n" as one
    /// Character, so Character-based splitting is avoided on purpose).
    static func splitLines(_ content: String, limits: Limits) throws -> [String] {
        var scalars = Array(content.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        var curCount = 0
        var j = 0
        func flush() throws {
            out.append(String(cur))
            cur = String.UnicodeScalarView(); curCount = 0
            if out.count > limits.maxLines { throw VTTError.tooManyLines(limit: limits.maxLines) }
        }
        while j < scalars.count {
            let c = scalars[j]
            if c == "\r" {
                try flush()
                if j + 1 < scalars.count && scalars[j + 1] == "\n" { j += 1 }
            } else if c == "\n" {
                try flush()
            } else {
                cur.append(c); curCount += 1
                if curCount > limits.maxLineScalars { throw VTTError.lineTooLong(line: out.count + 1, limit: limits.maxLineScalars) }
            }
            j += 1
        }
        if !cur.isEmpty { try flush() }
        return out
    }

    static func headerText(_ line: String) -> String? {
        let u = Array(line.unicodeScalars)
        let sig = Array("WEBVTT".unicodeScalars)
        guard u.count >= sig.count, Array(u[0..<sig.count]) == sig else { return nil }
        if u.count == sig.count { return "" }
        guard u[sig.count] == " " || u[sig.count] == "\t" else { return nil }
        return String(String.UnicodeScalarView(u[(sig.count + 1)...]))
    }

    /// Keyword followed by end of line, space or tab (scalar comparison).
    static func isKeyword(_ line: String, _ kw: String) -> Bool {
        let u = Array(line.unicodeScalars), k = Array(kw.unicodeScalars)
        guard u.count >= k.count, Array(u[0..<k.count]) == k else { return false }
        return u.count == k.count || u[k.count] == " " || u[k.count] == "\t"
    }

    // MARK: - Timing

    static func isSep(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if isSep(c) { if !cur.isEmpty { out.append(String(cur)); cur = String.UnicodeScalarView() } }
            else { cur.append(c) }
        }
        if !cur.isEmpty { out.append(String(cur)) }
        return out
    }

    static func parseTiming(_ line: String, line number: Int, regions: Set<String>) throws -> (Double, Double, CueSettings) {
        let t = tokens(line)
        guard t.count >= 3, t[1] == "-->" else { throw VTTError.badTimingLine(line: number) }
        // "-->" must be set off by whitespace on both sides.
        guard let start = parseTimestamp(t[0]) else { throw VTTError.badTimestamp(line: number) }
        guard let end = parseTimestamp(t[2]) else { throw VTTError.badTimestamp(line: number) }
        guard end > start else { throw VTTError.endNotAfterStart(line: number) }
        let settings = try parseSettings(Array(t[3...]), line: number, regions: regions)
        return (start, end, settings)
    }

    static func allDigits(_ s: Substring) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    /// [hh:]mm:ss.ttt
    static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var hh = 0
        var idx = 0
        if parts.count == 3 {
            guard parts[0].unicodeScalars.count >= 2, allDigits(parts[0]), let h = Int(parts[0]) else { return nil }
            hh = h; idx = 1
        }
        guard parts[idx].unicodeScalars.count == 2, allDigits(parts[idx]), let mm = Int(parts[idx]), mm < 60 else { return nil }
        let sm = parts[idx + 1].split(separator: ".", omittingEmptySubsequences: false)
        guard sm.count == 2 else { return nil }
        guard sm[0].unicodeScalars.count == 2, allDigits(sm[0]), let ss = Int(sm[0]), ss < 60 else { return nil }
        guard sm[1].unicodeScalars.count == 3, allDigits(sm[1]), let ms = Int(sm[1]) else { return nil }
        return Double(hh) * 3600 + Double(mm) * 60 + Double(ss) + Double(ms) / 1000
    }

    // MARK: - Settings

    static func parsePercent(_ s: Substring) -> Double? {
        guard s.hasSuffix("%") else { return nil }
        let body = s.dropLast()
        guard let v = parseDecimal(body), v >= 0, v <= 100 else { return nil }
        return v
    }

    /// digits[.digits] only (no sign, exponent, inf, nan).
    static func parseDecimal(_ s: Substring) -> Double? {
        let p = s.split(separator: ".", omittingEmptySubsequences: false)
        guard p.count <= 2, allDigits(p[0]) else { return nil }
        if p.count == 2 { guard allDigits(p[1]) else { return nil } }
        return Double(String(s))
    }

    static func parseSettings(_ toks: [String], line: Int, regions: Set<String>) throws -> CueSettings {
        var st = CueSettings()
        var seen = Set<String>()
        for tok in toks {
            let kv = tok.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, !kv[1].isEmpty else { throw VTTError.badSetting(line: line) }
            let key = String(kv[0]), val = kv[1]
            guard ["vertical", "line", "position", "size", "align", "region"].contains(key) else { throw VTTError.badSetting(line: line) }
            guard seen.insert(key).inserted else { throw VTTError.duplicateSetting(line: line) }
            let comma = val.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            switch key {
            case "vertical":
                guard let d = Direction(rawValue: String(val)) else { throw VTTError.badSetting(line: line) }
                st.vertical = d
            case "line":
                let v = comma[0]
                if let p = parsePercent(v) { st.line = .percent(p) }
                else {
                    var digits = v
                    if digits.hasPrefix("-") { digits = digits.dropFirst() }
                    guard allDigits(digits), let n = Int(String(v)) else { throw VTTError.badSetting(line: line) }
                    st.line = .number(n)
                }
                if comma.count == 2 {
                    guard let a = Align(rawValue: String(comma[1])), [.start, .center, .end].contains(a) else { throw VTTError.badSetting(line: line) }
                    st.lineAlign = a
                }
            case "position":
                guard let p = parsePercent(comma[0]) else { throw VTTError.badSetting(line: line) }
                st.position = p
                if comma.count == 2 {
                    guard let a = Align(rawValue: String(comma[1])), [.lineLeft, .center, .lineRight].contains(a) else { throw VTTError.badSetting(line: line) }
                    st.positionAlign = a
                }
            case "size":
                guard let p = parsePercent(val) else { throw VTTError.badSetting(line: line) }
                st.size = p
            case "align":
                guard let a = Align(rawValue: String(val)), [.start, .center, .end, .left, .right].contains(a) else { throw VTTError.badSetting(line: line) }
                st.align = a
            default: // region
                let id = String(val)
                guard regions.contains(id) else { throw VTTError.unknownRegion(line: line) }
                st.region = id
            }
        }
        return st
    }

    // MARK: - Region

    static func parseAnchor(_ s: Substring) -> (x: Double, y: Double)? {
        let p = s.split(separator: ",", omittingEmptySubsequences: false)
        guard p.count == 2, let x = parsePercent(p[0]), let y = parsePercent(p[1]) else { return nil }
        return (x, y)
    }

    static func parseRegion(_ block: [String], startLine: Int) throws -> Region {
        var r = Region(id: "", width: nil, lines: nil, regionAnchor: nil, viewportAnchor: nil, scrollUp: false)
        var seen = Set<String>()
        var haveID = false
        for (k, l) in block.dropFirst().enumerated() {
            let ln = startLine + 1 + k
            for tok in tokens(l) {
                let kv = tok.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard kv.count == 2, !kv[1].isEmpty else { throw VTTError.badRegion(line: ln) }
                let key = String(kv[0]), val = kv[1]
                guard seen.insert(key).inserted else { throw VTTError.badRegion(line: ln) }
                switch key {
                case "id": r.id = String(val); haveID = true
                case "width":
                    guard let p = parsePercent(val) else { throw VTTError.badRegion(line: ln) }
                    r.width = p
                case "lines":
                    guard allDigits(val), let n = Int(String(val)), n > 0 else { throw VTTError.badRegion(line: ln) }
                    r.lines = n
                case "regionanchor":
                    guard let a = parseAnchor(val) else { throw VTTError.badRegion(line: ln) }
                    r.regionAnchor = a
                case "viewportanchor":
                    guard let a = parseAnchor(val) else { throw VTTError.badRegion(line: ln) }
                    r.viewportAnchor = a
                case "scroll":
                    guard val == "up" else { throw VTTError.badRegion(line: ln) }
                    r.scrollUp = true
                default: throw VTTError.badRegion(line: ln)
                }
            }
        }
        guard haveID, !r.id.isEmpty, !r.id.contains("-->") else { throw VTTError.badRegion(line: startLine) }
        return r
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
HERE=Path(__file__).resolve().parent
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift: print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
root=Path(os.environ.get('PRODUCT_ROOT',str(Path(__file__).resolve().parents[3])))
with tempfile.TemporaryDirectory() as td:
 td=Path(td);main=td/'main.swift';main.write_text(cfg['test_source']);exe=td/'test'
 c=subprocess.run([swift]+[str(root/p) for p in cfg['compile_inputs']]+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(c.returncode)

```

```json id=fixtures2
{
  "compile_inputs": [
    "Sources/GorAVSubtitles/ASSParser.swift",
    "Sources/GorAVSubtitles/SRTParser.swift",
    "Sources/GorAVSubtitles/SubtitleAutoLoad.swift",
    "Sources/GorAVSubtitles/SubtitleController.swift",
    "Sources/GorAVSubtitles/SubtitleCue.swift",
    "Sources/GorAVSubtitles/SubtitleCueDelivery.swift",
    "Sources/GorAVSubtitles/SubtitleCueOutput.swift",
    "Sources/GorAVSubtitles/SubtitlePlan.swift",
    "Sources/GorAVSubtitles/SubtitleSchedule.swift",
    "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
    "Sources/GorAVSubtitles/SubtitleTrack.swift",
    "Sources/GorAVSubtitles/VTTParser.swift"
  ],
  "test_source": "import Foundation\nTask { @MainActor in\n let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)\n try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)\n defer {try? FileManager.default.removeItem(at:root)}\n let a=root.appendingPathComponent(\"A.mp4\"),b=root.appendingPathComponent(\"B.mp4\"),sub=root.appendingPathComponent(\"A.srt\")\n try Data().write(to:a);try Data().write(to:b)\n try Data(\"1\\n00:00:00,000 --> 00:00:10,000\\ntext\\n\".utf8).write(to:sub)\n let session=SubtitleSidecarSession(session:1,emit:{_ in})\n guard session.replaceSource(path:a.path) == nil else {print(\"SETUP_FAIL A\");exit(2)}\n let oldOutcome=await session.loadExactPrimary()\n guard case .selected = oldOutcome else {print(\"SETUP_FAIL actual SRT selection\");exit(2)}\n let original=session.selectionReceipt(for:oldOutcome)\n guard original.isCurrent(sourcePath:session.sourcePath,generation:session.generation) else {print(\"SETUP_FAIL initial receipt\");exit(2)}\n guard session.replaceSource(path:b.path) == nil else {print(\"SETUP_FAIL B\");exit(2)}\n let reissued=session.selectionReceipt(for:oldOutcome)\n let staleAccepted=reissued.isCurrent(sourcePath:session.sourcePath,generation:session.generation)\n print(staleAccepted ? \"FAIL old A selection restamped as current B\" : \"PASS old A selection remains stale\")\n session.close()\n exit(staleAccepted ? 1:0)\n}\ndispatchMain()\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL old A selection restamped as current B


```

Session API lease activated 2026-11-18 03:47 Europe/Istanbul through main scope decision; expires after2h without verified progress. Single production file only. Return origin-bound receipt atomically with selection. Preserve legacy API. Sequence integration after the A02serializationfix and A03controllerfix rebase, dependencies read-only. Full producer/host migration not in scope; NONQUALIFIED until measured gates.
