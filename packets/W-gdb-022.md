# W-gdb-022 WebVTT portable parser model + fixtures
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-022

```packet-json
{
 "packet_id": "W-gdb-022",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVSubtitles/SRTParser.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "VTTParser.parse(_ text: String) -> Result<[SubtitleCue], VTTError> mirroring SRTParser (excerpt in packet)",
  "types": "SubtitleCue (pinned excerpt); typed parse errors; NOTE/style blocks skipped typed",
  "ownership_lifetime": "cues are value types; typed errors on malformed input",
  "caller": "subtitle line (SubtitleTrack.load lane)",
  "callee": "WebVTTParser.parse -> [SubtitleCue], signature mirrors SRTParser (excerpt in packet)"
 },
 "test": {
  "command": "swift run vtt-parser-tests",
  "expected": "exit 0; final line matches '^vtt-parser-tests: [1-9][0-9]* PASS, 0 FAIL$'; malformed inputs produce the typed errors in the table; swift run subtitle-srt-tests stays green",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVSubtitles/",
   "Sources/vtt-parser-tests/",
   "kits/vtt-fixtures/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the subtitle line parses SRT and ASS only; WebVTT (the web standard sidecar) has no parser, so VTT sidecars are silently unusable.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVSubtitles/SRTParser.swift (sha256 49ab4d12, 94 lines, whole file below) - the parser ABI to mirror; Sources/GorAVSubtitles/SubtitleCue.swift (sha256 2311ed30) - the cue type.
- real test command: swift run subtitle-srt-tests stays green; the returned parser runs its own portable tests.

## expected behaviour
a bounded WebVTT parser producing the pinned cue type: cue timings with settings, identifiers, regions, NOTE/style blocks skipped typed, malformed-input recovery with typed errors; synthetic fixtures (basic, settings permutations, overlap, unicode incl. Turkish i cases, truncated).

## exact call site and interface
the parser signature mirrors SRTParser's (pinned excerpt) and emits SubtitleCue values; no rendering, no font assumptions.

## behaviour that must not change
existing subtitle suites stay green; the cue type is unchanged.

## acceptance test (from the product repo)
parser tests PASS on Linux; malformed inputs produce the typed errors in the table; existing subtitle suites stay green.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSubtitles/SRTParser.swift (sha256 49ab4d12, lines 1-94 of 94)
```swift id=source1
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

### Sources/GorAVSubtitles/SubtitleCue.swift (sha256 2311ed30, lines 1-32 of 32)
```swift id=source2
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

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```text id=fixtures1
WEBVTT

00:00:01.000 --> 00:00:03.000 line:90%
Merhaba dunya

00:00:04.000 --> 00:00:06.000
Ikinci cue
# expect: 2 cues; timings in seconds; settings preserved typed; NOTE blocks skipped
```
