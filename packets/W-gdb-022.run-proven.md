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
  "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
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
    "branch": "main",
    "paths": [
      "Sources/GorAVSubtitles/",
      "Sources/vtt-parser-tests/",
      "kits/vtt-fixtures/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/vtt-parser-tests/main.swift",
        "block": "rf0",
        "content": "import Foundation\nimport GorAVSubtitles\n\n// Portable tests for VTTParser. Run from the package root: swift run vtt-parser-tests\n// Fixture dir: env VTT_FIXTURES or ./kits/vtt-fixtures. A missing fixture dir is a FAIL, never a skip.\n\nvar pass = 0\nvar fail = 0\nfunc check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = \"\") {\n    if ok { pass += 1 } else { fail += 1; if !name.hasPrefix(\"NEGCTL-selftest\") { print(\"FAIL \\(name) \\(detail())\") } }\n}\ntypealias E = VTTParser.VTTError\n\nfunc errTag(_ e: E) -> String {\n    switch e {\n    case .emptyDocument: return \"emptyDocument\"\n    case .inputTooLarge: return \"inputTooLarge\"\n    case .tooManyLines: return \"tooManyLines\"\n    case .lineTooLong(let l, _): return \"lineTooLong@\\(l)\"\n    case .tooManyCues: return \"tooManyCues\"\n    case .missingSignature(let l): return \"missingSignature@\\(l)\"\n    case .badHeader(let l): return \"badHeader@\\(l)\"\n    case .badTimingLine(let l): return \"badTimingLine@\\(l)\"\n    case .badTimestamp(let l): return \"badTimestamp@\\(l)\"\n    case .endNotAfterStart(let l): return \"endNotAfterStart@\\(l)\"\n    case .missingText(let l): return \"missingText@\\(l)\"\n    case .textContainsArrow(let l): return \"textContainsArrow@\\(l)\"\n    case .badSetting(let l): return \"badSetting@\\(l)\"\n    case .duplicateSetting(let l): return \"duplicateSetting@\\(l)\"\n    case .unknownRegion(let l): return \"unknownRegion@\\(l)\"\n    case .badRegion(let l): return \"badRegion@\\(l)\"\n    case .misplacedBlock(let l): return \"misplacedBlock@\\(l)\"\n    case .noteContainsArrow(let l): return \"noteContainsArrow@\\(l)\"\n    }\n}\nfunc outcome(_ r: Result<[SubtitleCue], E>) -> String {\n    switch r {\n    case .success(let c): return \"ok:\\(c.count)\"\n    case .failure(let e): return \"err:\" + errTag(e)\n    }\n}\nfunc doc(_ s: String) -> VTTParser.Document? { try? VTTParser.parseDocument(s) }\n\n// ---- manifest-driven fixtures\nlet dir = ProcessInfo.processInfo.environment[\"VTT_FIXTURES\"] ?? \"kits/vtt-fixtures\"\nfunc bytes(_ name: String) -> String? {\n    guard let d = FileManager.default.contents(atPath: dir + \"/\" + name) else { return nil }\n    return String(decoding: d, as: UTF8.self)\n}\nif let manifest = bytes(\"expect.tsv\") {\n    var n = 0\n    for row in manifest.split(separator: \"\\n\") {\n        let f = row.split(separator: \"\\t\").map(String.init)\n        guard f.count == 2 else { check(false, \"manifest row\", String(row)); continue }\n        n += 1\n        guard let text = bytes(f[0]) else { check(false, \"fixture readable \\(f[0])\"); continue }\n        let got = outcome(VTTParser.parse(text))\n        check(got == f[1], \"fixture \\(f[0])\", \"expected \\(f[1]) got \\(got)\")\n    }\n    check(n >= 30, \"manifest has >= 30 rows\", \"rows \\(n)\")\n} else {\n    check(false, \"fixtures dir readable\", dir)\n}\n\n// ---- detailed content assertions (fixtures re-read)\nif let t = bytes(\"ok-basic.vtt\"), let d = doc(t) {\n    check(d.cues.count == 2, \"basic count\")\n    check(d.cues[0].startSeconds == 1.0 && d.cues[0].endSeconds == 3.0, \"basic timing\")\n    check(d.cues[0].lines == [\"Merhaba dunya\"], \"basic text\")\n    check(d.cues[0].index == 1 && d.cues[1].index == 2, \"basic indices\")\n    check(d.cueInfo[0].settings.line == .percent(90), \"basic line:90%\")\n    check(d.cueInfo[1].settings == VTTParser.CueSettings(), \"basic no settings\")\n    check(d.cueInfo[0].identifier == nil, \"basic no id\")\n    check(d.cues[0].styleName == nil, \"styleName nil\")\n}\nif let t = bytes(\"ok-header-text-notes-style.vtt\"), let d = doc(t) {\n    check(d.headerText == \"- demo file\", \"header text\", d.headerText)\n    check(d.skipped.map { $0.kind } == [.note, .style, .note], \"skipped kinds typed\")\n    check(d.skipped[0].lines == [\"NOTE this is a comment\", \"over two lines\"], \"note lines kept\")\n    check(d.cueInfo[0].identifier == \"1\", \"numeric id kept\")\n    check(d.cues[0].startSeconds == 1.0 && d.cues[0].endSeconds == 2.5, \"mm:ss.ttt short form\")\n    check(d.cues[1].startSeconds == 3600.0, \"hh form\")\n    check(d.cueInfo[0].timingLine == 11, \"timing line number\", \"\\(d.cueInfo[0].timingLine)\")\n}\nif let t = bytes(\"ok-settings-permutations.vtt\"), let d = doc(t) {\n    check(d.regions.count == 1 && d.regions[0].id == \"r1\" && d.regions[0].width == 40 && d.regions[0].lines == 3 && d.regions[0].scrollUp, \"region parsed\")\n    check(d.regions[0].regionAnchor?.x == 0 && d.regions[0].regionAnchor?.y == 100, \"region anchor\")\n    let a = d.cueInfo[0].settings\n    check(a.vertical == .rl && a.line == .number(-1) && a.position == 10 && a.positionAlign == .lineLeft && a.size == 50 && a.align == .start, \"settings a\", \"\\(a)\")\n    let b = d.cueInfo[1].settings\n    check(b.align == .end && b.line == .percent(0) && b.lineAlign == .center, \"settings b (tab separated)\", \"\\(b)\")\n    let c = d.cueInfo[2].settings\n    check(c.region == \"r1\" && c.position == 50.5 && c.positionAlign == .center && c.align == .left, \"settings c\", \"\\(c)\")\n    let e = d.cueInfo[3].settings\n    check(e.vertical == .lr && e.line == .number(3) && e.size == 100 && e.align == .right && e.position == 0, \"settings d\", \"\\(e)\")\n    check(d.cueInfo.map { $0.identifier } == [\"a\", \"b\", \"c\", \"d\"], \"ids\")\n}\nif let t = bytes(\"ok-overlap.vtt\"), let d = doc(t) {\n    check(d.cues.map { $0.startSeconds } == [1, 2, 2] && d.cues.map { $0.endSeconds } == [5, 3, 5], \"overlap kept in file order\")\n    check(d.cues[0].contains(seconds: 2.5) && d.cues[1].contains(seconds: 2.5) && d.cues[2].contains(seconds: 2.5), \"overlap membership\")\n}\nif let t = bytes(\"ok-unicode-turkish.vtt\"), let d = doc(t) {\n    check(d.cueInfo[0].identifier == \"kimlik-\\u{130}\", \"turkish id verbatim\")\n    check(d.cues[0].lines[0] == \"\\u{130}stanbul \\u{131}\\u{15F}\\u{131}k I\\u{15E}IK iI \\u{131}\\u{130}\", \"turkish text verbatim\")\n    check(Array(d.cues[0].lines[1].unicodeScalars).prefix(2) == [Unicode.Scalar(0x49)!, Unicode.Scalar(0x307)!], \"combining dot preserved, not folded to U+0130\")\n    check(d.cues[1].lines[0].unicodeScalars.contains(Unicode.Scalar(0x1F600)!), \"emoji kept\")\n    check(d.cues[1].lines[0].unicodeScalars.contains(Unicode.Scalar(0x301)!), \"combining acute kept (no NFC)\")\n}\nif let t = bytes(\"ok-crlf-bom.vtt\"), let d = doc(t) {\n    check(d.cues[0].lines == [\"A\", \"B\"] && d.cues[1].lines == [\"C\"], \"crlf/cr lines\")\n}\nif let t = bytes(\"ok-whitespace-line-is-text.vtt\"), let d = doc(t) {\n    check(d.cues[0].lines == [\"A\", \" \", \"B\"], \"whitespace-only line stays cue text\")\n}\nif let t = bytes(\"ok-note-lowercase-is-cue-id.vtt\"), let d = doc(t) {\n    check(d.skipped.isEmpty && d.cueInfo[0].identifier == \"note\" && d.cueInfo[1].identifier == \"NOTES\", \"NOTE keyword is case-sensitive and word-bounded\")\n}\n\n// ---- inline: bounds\nlet tiny = VTTParser.Limits(maxBytes: 20, maxLines: 5, maxLineScalars: 10, maxCues: 1)\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\", limits: tiny)) == \"err:inputTooLarge\", \"maxBytes\")\nlet big = VTTParser.Limits(maxBytes: 1000, maxLines: 4, maxLineScalars: 100, maxCues: 100)\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\na\\n\\nb\\n\\nc\\n\\nd\\n\", limits: big)) == \"err:tooManyLines\", \"maxLines\")\nlet ll = VTTParser.Limits(maxBytes: 1000, maxLines: 100, maxLineScalars: 10, maxCues: 100)\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n\" + String(repeating: \"x\", count: 11), limits: ll)) == \"err:lineTooLong@3\", \"maxLineScalars\")\nlet one = VTTParser.Limits(maxBytes: 1000, maxLines: 100, maxLineScalars: 100, maxCues: 1)\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\\n00:00:03.000 --> 00:00:04.000\\nB\\n\", limits: one)) == \"err:tooManyCues\", \"maxCues\")\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\", limits: one)) == \"ok:1\", \"at limit ok\")\n// a large valid document stays fast and exact\nvar bigDoc = \"WEBVTT\\n\\n\"\nfor k in 0..<5000 { bigDoc += \"00:00:\\(String(format: \"%02d\", k % 60)).000 --> 01:00:00.000\\ncue \\(k)\\n\\n\" }\nif case .success(let c) = VTTParser.parse(bigDoc) { check(c.count == 5000 && c[4999].lines == [\"cue 4999\"], \"5000 cues\") } else { check(false, \"5000 cues parse\") }\n// throwing form agrees with Result form\ncheck((try? VTTParser.parseThrowing(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\"))?.count == 1, \"parseThrowing ok\")\ndo { _ = try VTTParser.parseThrowing(\"\"); check(false, \"parseThrowing empty must throw\") } catch { check((error as? E) == .emptyDocument, \"parseThrowing empty typed\") }\n// partial adoption never happens: one bad block voids the whole parse\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\\n00:00:03.000 --> 00:00:02.000\\nB\\n\")) == \"err:endNotAfterStart@6\", \"no partial adoption\")\nif let t = bytes(\"ok-style-region-heads-exact.vtt\"), let d = doc(t) {\n    check(d.skipped.count == 1 && d.skipped[0].kind == .style && d.skipped[0].line == 3, \"exact STYLE skipped, 'STYLE foo' is not\", \"\\(d.skipped)\")\n    check(d.regions.isEmpty, \"'REGION x' is not a region block\")\n    check(d.cueInfo.map { $0.identifier } == [\"STYLE foo\", \"REGION x\"], \"keyword-like identifiers kept\", \"\\(d.cueInfo.map { $0.identifier })\")\n}\n\n// ---- negative controls on the harness itself\n// (1) a wrong expectation must be detected as a mismatch\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01,000 --> 00:00:02,000\\nA\\n\")) != \"ok:1\", \"NEGCTL comma timestamp must not parse as ok\")\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\")) != \"err:emptyDocument\", \"NEGCTL valid input must not error\")\n// (2) check() really records failures\nlet before = fail\ncheck(false, \"NEGCTL-selftest (expected to fail once)\")\nlet recorded = fail == before + 1\nfail = before // remove the deliberate failure\ncheck(recorded, \"NEGCTL check() records failures\")\n// (3) parse results differ between inputs (parser is not a constant)\ncheck(outcome(VTTParser.parse(\"WEBVTT\\n\\n00:00:01.000 --> 00:00:02.000\\nA\\n\")) != outcome(VTTParser.parse(\"\")), \"NEGCTL parser not constant\")\n\nprint(\"vtt-parser-tests: \\(pass) PASS, \\(fail) FAIL\")\nexit(fail == 0 ? 0 : 1)\n"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
    "command": "swift run vtt-parser-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T23:02:14.916970+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "vtt-parser-tests: 87 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/vtt-parser-tests/main.swift",
        "block": "rf0",
        "sha256": "247c48d0f929a5794bec200809077470bfcd6a45bbebb85e92c8d420bcfe4851"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "dc5dc78cb34d7496a4996e486a7c4a6835c0c8cde2d060baaa89c624bf42d6db",
    "last_5_lines": [
      "[21/24] Wrapping AST for vtt-parser-tests for debugging",
      "[22/24] Write Objects.LinkFileList",
      "[23/24] Linking vtt-parser-tests",
      "Build complete! (3.15s)",
      "vtt-parser-tests: 87 PASS, 0 FAIL"
    ],
    "receipt_sha256": "ae4ec7d63a0a9c29fe5c89582762adce048b75b73337f0d42e4d58c0705cedf4"
  }
}
```

## problem (what fails for the user)
the subtitle line parses SRT and ASS only; WebVTT (the web standard sidecar) has no parser, so VTT sidecars are silently unusable.

## reproducer
- repo: goreda/gorav @ 91a8b69abe9ce61e31188e3d426477a3f8528ede (branch main).
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

## repair note (arch-196x item 4)
vendored vtt-parser-tests target + kits/vtt-fixtures from gorav main; Package.swift wiring added.













































```text id=rf0
import Foundation
import GorAVSubtitles

// Portable tests for VTTParser. Run from the package root: swift run vtt-parser-tests
// Fixture dir: env VTT_FIXTURES or ./kits/vtt-fixtures. A missing fixture dir is a FAIL, never a skip.

var pass = 0
var fail = 0
func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok { pass += 1 } else { fail += 1; if !name.hasPrefix("NEGCTL-selftest") { print("FAIL \(name) \(detail())") } }
}
typealias E = VTTParser.VTTError

func errTag(_ e: E) -> String {
    switch e {
    case .emptyDocument: return "emptyDocument"
    case .inputTooLarge: return "inputTooLarge"
    case .tooManyLines: return "tooManyLines"
    case .lineTooLong(let l, _): return "lineTooLong@\(l)"
    case .tooManyCues: return "tooManyCues"
    case .missingSignature(let l): return "missingSignature@\(l)"
    case .badHeader(let l): return "badHeader@\(l)"
    case .badTimingLine(let l): return "badTimingLine@\(l)"
    case .badTimestamp(let l): return "badTimestamp@\(l)"
    case .endNotAfterStart(let l): return "endNotAfterStart@\(l)"
    case .missingText(let l): return "missingText@\(l)"
    case .textContainsArrow(let l): return "textContainsArrow@\(l)"
    case .badSetting(let l): return "badSetting@\(l)"
    case .duplicateSetting(let l): return "duplicateSetting@\(l)"
    case .unknownRegion(let l): return "unknownRegion@\(l)"
    case .badRegion(let l): return "badRegion@\(l)"
    case .misplacedBlock(let l): return "misplacedBlock@\(l)"
    case .noteContainsArrow(let l): return "noteContainsArrow@\(l)"
    }
}
func outcome(_ r: Result<[SubtitleCue], E>) -> String {
    switch r {
    case .success(let c): return "ok:\(c.count)"
    case .failure(let e): return "err:" + errTag(e)
    }
}
func doc(_ s: String) -> VTTParser.Document? { try? VTTParser.parseDocument(s) }

// ---- manifest-driven fixtures
let dir = ProcessInfo.processInfo.environment["VTT_FIXTURES"] ?? "kits/vtt-fixtures"
func bytes(_ name: String) -> String? {
    guard let d = FileManager.default.contents(atPath: dir + "/" + name) else { return nil }
    return String(decoding: d, as: UTF8.self)
}
if let manifest = bytes("expect.tsv") {
    var n = 0
    for row in manifest.split(separator: "\n") {
        let f = row.split(separator: "\t").map(String.init)
        guard f.count == 2 else { check(false, "manifest row", String(row)); continue }
        n += 1
        guard let text = bytes(f[0]) else { check(false, "fixture readable \(f[0])"); continue }
        let got = outcome(VTTParser.parse(text))
        check(got == f[1], "fixture \(f[0])", "expected \(f[1]) got \(got)")
    }
    check(n >= 30, "manifest has >= 30 rows", "rows \(n)")
} else {
    check(false, "fixtures dir readable", dir)
}

// ---- detailed content assertions (fixtures re-read)
if let t = bytes("ok-basic.vtt"), let d = doc(t) {
    check(d.cues.count == 2, "basic count")
    check(d.cues[0].startSeconds == 1.0 && d.cues[0].endSeconds == 3.0, "basic timing")
    check(d.cues[0].lines == ["Merhaba dunya"], "basic text")
    check(d.cues[0].index == 1 && d.cues[1].index == 2, "basic indices")
    check(d.cueInfo[0].settings.line == .percent(90), "basic line:90%")
    check(d.cueInfo[1].settings == VTTParser.CueSettings(), "basic no settings")
    check(d.cueInfo[0].identifier == nil, "basic no id")
    check(d.cues[0].styleName == nil, "styleName nil")
}
if let t = bytes("ok-header-text-notes-style.vtt"), let d = doc(t) {
    check(d.headerText == "- demo file", "header text", d.headerText)
    check(d.skipped.map { $0.kind } == [.note, .style, .note], "skipped kinds typed")
    check(d.skipped[0].lines == ["NOTE this is a comment", "over two lines"], "note lines kept")
    check(d.cueInfo[0].identifier == "1", "numeric id kept")
    check(d.cues[0].startSeconds == 1.0 && d.cues[0].endSeconds == 2.5, "mm:ss.ttt short form")
    check(d.cues[1].startSeconds == 3600.0, "hh form")
    check(d.cueInfo[0].timingLine == 11, "timing line number", "\(d.cueInfo[0].timingLine)")
}
if let t = bytes("ok-settings-permutations.vtt"), let d = doc(t) {
    check(d.regions.count == 1 && d.regions[0].id == "r1" && d.regions[0].width == 40 && d.regions[0].lines == 3 && d.regions[0].scrollUp, "region parsed")
    check(d.regions[0].regionAnchor?.x == 0 && d.regions[0].regionAnchor?.y == 100, "region anchor")
    let a = d.cueInfo[0].settings
    check(a.vertical == .rl && a.line == .number(-1) && a.position == 10 && a.positionAlign == .lineLeft && a.size == 50 && a.align == .start, "settings a", "\(a)")
    let b = d.cueInfo[1].settings
    check(b.align == .end && b.line == .percent(0) && b.lineAlign == .center, "settings b (tab separated)", "\(b)")
    let c = d.cueInfo[2].settings
    check(c.region == "r1" && c.position == 50.5 && c.positionAlign == .center && c.align == .left, "settings c", "\(c)")
    let e = d.cueInfo[3].settings
    check(e.vertical == .lr && e.line == .number(3) && e.size == 100 && e.align == .right && e.position == 0, "settings d", "\(e)")
    check(d.cueInfo.map { $0.identifier } == ["a", "b", "c", "d"], "ids")
}
if let t = bytes("ok-overlap.vtt"), let d = doc(t) {
    check(d.cues.map { $0.startSeconds } == [1, 2, 2] && d.cues.map { $0.endSeconds } == [5, 3, 5], "overlap kept in file order")
    check(d.cues[0].contains(seconds: 2.5) && d.cues[1].contains(seconds: 2.5) && d.cues[2].contains(seconds: 2.5), "overlap membership")
}
if let t = bytes("ok-unicode-turkish.vtt"), let d = doc(t) {
    check(d.cueInfo[0].identifier == "kimlik-\u{130}", "turkish id verbatim")
    check(d.cues[0].lines[0] == "\u{130}stanbul \u{131}\u{15F}\u{131}k I\u{15E}IK iI \u{131}\u{130}", "turkish text verbatim")
    check(Array(d.cues[0].lines[1].unicodeScalars).prefix(2) == [Unicode.Scalar(0x49)!, Unicode.Scalar(0x307)!], "combining dot preserved, not folded to U+0130")
    check(d.cues[1].lines[0].unicodeScalars.contains(Unicode.Scalar(0x1F600)!), "emoji kept")
    check(d.cues[1].lines[0].unicodeScalars.contains(Unicode.Scalar(0x301)!), "combining acute kept (no NFC)")
}
if let t = bytes("ok-crlf-bom.vtt"), let d = doc(t) {
    check(d.cues[0].lines == ["A", "B"] && d.cues[1].lines == ["C"], "crlf/cr lines")
}
if let t = bytes("ok-whitespace-line-is-text.vtt"), let d = doc(t) {
    check(d.cues[0].lines == ["A", " ", "B"], "whitespace-only line stays cue text")
}
if let t = bytes("ok-note-lowercase-is-cue-id.vtt"), let d = doc(t) {
    check(d.skipped.isEmpty && d.cueInfo[0].identifier == "note" && d.cueInfo[1].identifier == "NOTES", "NOTE keyword is case-sensitive and word-bounded")
}

// ---- inline: bounds
let tiny = VTTParser.Limits(maxBytes: 20, maxLines: 5, maxLineScalars: 10, maxCues: 1)
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n", limits: tiny)) == "err:inputTooLarge", "maxBytes")
let big = VTTParser.Limits(maxBytes: 1000, maxLines: 4, maxLineScalars: 100, maxCues: 100)
check(outcome(VTTParser.parse("WEBVTT\n\na\n\nb\n\nc\n\nd\n", limits: big)) == "err:tooManyLines", "maxLines")
let ll = VTTParser.Limits(maxBytes: 1000, maxLines: 100, maxLineScalars: 10, maxCues: 100)
check(outcome(VTTParser.parse("WEBVTT\n\n" + String(repeating: "x", count: 11), limits: ll)) == "err:lineTooLong@3", "maxLineScalars")
let one = VTTParser.Limits(maxBytes: 1000, maxLines: 100, maxLineScalars: 100, maxCues: 1)
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n\n00:00:03.000 --> 00:00:04.000\nB\n", limits: one)) == "err:tooManyCues", "maxCues")
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n", limits: one)) == "ok:1", "at limit ok")
// a large valid document stays fast and exact
var bigDoc = "WEBVTT\n\n"
for k in 0..<5000 { bigDoc += "00:00:\(String(format: "%02d", k % 60)).000 --> 01:00:00.000\ncue \(k)\n\n" }
if case .success(let c) = VTTParser.parse(bigDoc) { check(c.count == 5000 && c[4999].lines == ["cue 4999"], "5000 cues") } else { check(false, "5000 cues parse") }
// throwing form agrees with Result form
check((try? VTTParser.parseThrowing("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n"))?.count == 1, "parseThrowing ok")
do { _ = try VTTParser.parseThrowing(""); check(false, "parseThrowing empty must throw") } catch { check((error as? E) == .emptyDocument, "parseThrowing empty typed") }
// partial adoption never happens: one bad block voids the whole parse
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n\n00:00:03.000 --> 00:00:02.000\nB\n")) == "err:endNotAfterStart@6", "no partial adoption")
if let t = bytes("ok-style-region-heads-exact.vtt"), let d = doc(t) {
    check(d.skipped.count == 1 && d.skipped[0].kind == .style && d.skipped[0].line == 3, "exact STYLE skipped, 'STYLE foo' is not", "\(d.skipped)")
    check(d.regions.isEmpty, "'REGION x' is not a region block")
    check(d.cueInfo.map { $0.identifier } == ["STYLE foo", "REGION x"], "keyword-like identifiers kept", "\(d.cueInfo.map { $0.identifier })")
}

// ---- negative controls on the harness itself
// (1) a wrong expectation must be detected as a mismatch
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01,000 --> 00:00:02,000\nA\n")) != "ok:1", "NEGCTL comma timestamp must not parse as ok")
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n")) != "err:emptyDocument", "NEGCTL valid input must not error")
// (2) check() really records failures
let before = fail
check(false, "NEGCTL-selftest (expected to fail once)")
let recorded = fail == before + 1
fail = before // remove the deliberate failure
check(recorded, "NEGCTL check() records failures")
// (3) parse results differ between inputs (parser is not a constant)
check(outcome(VTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n")) != outcome(VTTParser.parse("")), "NEGCTL parser not constant")

print("vtt-parser-tests: \(pass) PASS, \(fail) FAIL")
exit(fail == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-09h65du6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-09h65du6/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/7] Write sources
[2/7] Write swift-version--9C6B84B6E025C5B.txt
[4/14] Emitting module GorAVSubtitles
[5/20] Compiling GorAVSubtitles ASSParser.swift
[6/20] Compiling GorAVSubtitles SRTParser.swift
[7/20] Compiling GorAVSubtitles SubtitleAutoLoad.swift
[8/20] Compiling GorAVSubtitles SubtitleController.swift
[9/20] Compiling GorAVSubtitles SubtitleCue.swift
[10/20] Compiling GorAVSubtitles SubtitleCueDelivery.swift
[11/20] Compiling GorAVSubtitles SubtitleCueOutput.swift
[12/20] Compiling GorAVSubtitles SubtitlePlan.swift
[13/20] Compiling GorAVSubtitles SubtitleSchedule.swift
[14/20] Compiling GorAVSubtitles SubtitleSidecarSession.swift
[15/20] Compiling GorAVSubtitles SubtitleTrack.swift
[16/20] Compiling GorAVSubtitles VTTParser.swift
[17/21] Wrapping AST for GorAVSubtitles for debugging
[19/23] Emitting module vtt_parser_tests
[20/23] Compiling vtt_parser_tests main.swift
[21/24] Wrapping AST for vtt-parser-tests for debugging
[22/24] Write Objects.LinkFileList
[23/24] Linking vtt-parser-tests
Build complete! (3.15s)
vtt-parser-tests: 87 PASS, 0 FAIL
```
