# W-gdb-199au-in2tinct-05 - SRTParser parses and validates the SRT coordinate tail instead of silently ignoring it
state: OPEN / unclaimed
lab: in2tinct
row: GORAV-SUBTITLE-FORMATS (A4)

Patch + tests authored by gdb (Ops, leg A) under arch-199au item 6; in2tinct verifies and ingests per the leg/lab rules. Real production change plus semantic Linux tests, both executed against the pin before publication (run proof below). Support-only: no native/UI/playback/Darwin claims, no gorav main ref change, no paid CI; integration lands on the target lane branch only after lab verification and integrator review.

PROBLEM. The SRT coordinate tail (X1:a X2:b Y1:c Y2:d after the end timestamp) is the only positional data the SRT format carries, and it was silently ignored: positions were lost and malformed tails passed as if valid, against the parser's documented no-guessing stance.

DECISION. Parse the tail as data only (pixel meaning and layout stay renderer-side; the position-bounds policy row is explicitly out of scope). Present-but-malformed tails now refuse typed (badCoordinateTail, whole-document, exact line) - a stated strictness change from silent ignoring. New parseWithCoordinates(_:) returns cues plus a parallel coordinate array; parse(_:) keeps its signature and cue results. Scoped under SUBTITLE-FORMATS; SUBTITLE-POSITION-BOUNDS has its own active row and is not claimed here.

Scope boundaries: this packet touches only the listed files. It does not touch the returned/conflicting paths ABLoopPolicy.swift, SubtitleSelectionPolicy.swift, ASSParser.swift or the CacheAccounting.swift chain, and does not re-open their rows. No generic tooling, no label-only work, no fabricated evidence: every check below ran on this exact patch against the exact pin.

Repo goreda/gorav main pin 087c15cc068daf1e74112d436e63f07b3d254be4. Test toolchain: official Swift 6.2.3 (ubuntu22.04) on PATH, -swift-version 6 strict concurrency. Return full files on target branch lane/199au/srt-coordinate-tail; the patch against the pin is derivable from the inline sources. Keep .build out of git.

```packet-json
{
  "packet_id": "W-gdb-199au-in2tinct-05",
  "lab": "in2tinct",
  "writer": "gdb",
  "code_owner": "gdb (Ops leg A) authored the patch and tests; goreda owns the gorav trunk integration decision; in2tinct verifies and ingests the listed files only",
  "product_repo": "goreda/gorav",
  "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SRTParser.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "SRTParser.CueCoordinates (new value type); SRTParser.parseWithCoordinates(_:) throws -> (cues: [SubtitleCue], coordinates: [CueCoordinates?]); ParseError.badCoordinateTail(line:) (new case); SRTParser.parse(_:) unchanged signature",
    "types": "SRTParser, SubtitleCue (pinned dependency, unmodified)",
    "ownership_lifetime": "Owned production path Sources/GorAVSubtitles/SRTParser.swift only.",
    "caller": "SubtitleTrack.load(path:) SRT branch and any direct SRT consumer; loader unchanged in this packet.",
    "callee": "SubtitleCue value construction (unchanged type)."
  },
  "scope": "product",
  "test": {
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au05 Sources/GorAVSubtitles/SRTParser.swift Sources/GorAVSubtitles/SubtitleCue.swift kits/199au/in2tinct-05/main.swift && /tmp/wgdb199au05",
    "expected": "exit 0; log ends 'SEMANTIC_PASS W-gdb-199au-in2tinct-05 16 checks'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/199au/srt-coordinate-tail",
    "paths": [
      "Sources/GorAVSubtitles/SRTParser.swift",
      "Sources/GorAVSubtitles/SubtitleCue.swift",
      "kits/199au/in2tinct-05/main.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SRTParser.swift",
        "block": "source1"
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
        "block": "source0"
      },
      {
        "path": "kits/199au/in2tinct-05/main.swift",
        "block": "fixtures1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au05 Sources/GorAVSubtitles/SRTParser.swift Sources/GorAVSubtitles/SubtitleCue.swift kits/199au/in2tinct-05/main.swift && /tmp/wgdb199au05",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-20T20:39:46.361004+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "SEMANTIC_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SRTParser.swift",
        "block": "source1",
        "sha256": "07078e3a034ccd37bfa978d61360cac65e4c69ccae58b0b3c3072400756c7de2"
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
        "block": "source0",
        "sha256": "a161f038540bddb463b01a4420c757a0aaecedcecac879d21c71444ac315eddc"
      },
      {
        "path": "kits/199au/in2tinct-05/main.swift",
        "block": "fixtures1",
        "sha256": "8fcb120a1bcdad61b902ae502bfddc7d7f216c5b9050de931e128036a0536ede"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "f5f6d45bda2c422a79e2d4779308977adddf371ee8426a4823ac17943d17cf6f",
    "last_5_lines": [
      "PASS K2 missing text still refuses typed",
      "PASS K3 empty document still refuses typed",
      "PASS K4 BOM and CRLF tolerated, zero coordinates parse",
      "PASS K5 end-before-start still refuses before any tail use",
      "SEMANTIC_PASS W-gdb-199au-in2tinct-05 16 checks"
    ],
    "receipt_sha256": "df61131d8e35aa2fa3b5bb7fde9a2a8623537b47bc7d27ab49c4c29282f8d67c"
  }
}
```

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
        /// 199au (W-gdb-199au-in2tinct-05): a coordinate tail that is present
        /// but malformed. Previously any tail was silently ignored; the
        /// strict no-guessing stance now refuses it typed.
        case badCoordinateTail(line: Int)
    }

    /// 199au (W-gdb-199au-in2tinct-05): the SRT coordinate tail
    /// ("X1:a X2:b Y1:c Y2:d" after the end timestamp), the only positional
    /// data the SRT format carries. Parsed as data only: pixel meaning and
    /// layout are the renderer's, bounds policy is the position-bounds row's;
    /// neither is decided here.
    public struct CueCoordinates: Equatable, Sendable {
        public let x1: Int
        public let x2: Int
        public let y1: Int
        public let y2: Int
        public init(x1: Int, x2: Int, y1: Int, y2: Int) {
            self.x1 = x1; self.x2 = x2; self.y1 = y1; self.y2 = y2
        }
    }

    static func parseCore(_ content: String) throws
        -> (cues: [SubtitleCue], coordinates: [CueCoordinates?]) {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var cues: [SubtitleCue] = []
        var cueCoordinates: [CueCoordinates?] = []
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
            let (start, end, coordinates) = try parseTiming(lines[i], line: timingLine)
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
            cueCoordinates.append(coordinates)
        }
        guard sawAnyBlock else { throw ParseError.emptyDocument }
        return (cues, cueCoordinates)
    }

    /// Parses whole-document SRT text into cues in file order.
    public static func parse(_ content: String) throws -> [SubtitleCue] {
        try parseCore(content).cues
    }

    /// 199au (W-gdb-199au-in2tinct-05): cues plus their coordinate tails,
    /// parallel arrays (nil where a cue carries no tail). Same strict
    /// refusals as parse(_:); a malformed tail refuses the whole document,
    /// never a silently dropped position.
    public static func parseWithCoordinates(_ content: String) throws
        -> (cues: [SubtitleCue], coordinates: [CueCoordinates?]) {
        try parseCore(content)
    }

    static func isPositiveInt(_ s: String) -> Bool {
        guard !s.isEmpty, s.allSatisfy({ $0 >= "0" && $0 <= "9" }), let v = Int(s), v > 0 else { return false }
        return true
    }

    static func parseTiming(_ line: String, line number: Int) throws -> (Double, Double, CueCoordinates?) {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { throw ParseError.badTimingLine(line: number) }
        guard let start = parseTimestamp(parts[0]) else { throw ParseError.badTimestamp(line: number) }
        // Optional coordinate tail after the end timestamp (" X1:a X2:b Y1:c Y2:d").
        let endAndTail = parts[1].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let endToken = String(endAndTail[0])
        guard let end = parseTimestamp(endToken) else { throw ParseError.badTimestamp(line: number) }
        guard end > start else { throw ParseError.endNotAfterStart(line: number) }
        let tail = endAndTail.count == 2 ? String(endAndTail[1]) : ""
        return (start, end, try parseCoordinateTail(tail, line: number))
    }

    /// The tail is either absent (empty) or exactly four space-separated
    /// "X1:a X2:b Y1:c Y2:d" fields with non-negative integer values. This
    /// strictens previous behavior (any tail was ignored): a present but
    /// malformed tail is a typed refusal, consistent with the parser's
    /// documented no-guessing stance.
    static func parseCoordinateTail(_ tail: String, line number: Int) throws -> CueCoordinates? {
        if tail.isEmpty { return nil }
        let fields = tail.components(separatedBy: " ")
        let keys = ["X1", "X2", "Y1", "Y2"]
        guard fields.count == 4 else { throw ParseError.badCoordinateTail(line: number) }
        var values: [Int] = []
        for (field, key) in zip(fields, keys) {
            let kv = field.components(separatedBy: ":")
            guard kv.count == 2, kv[0] == key,
                  !kv[1].isEmpty, kv[1].allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let v = Int(kv[1]) else { throw ParseError.badCoordinateTail(line: number) }
            values.append(v)
        }
        return CueCoordinates(x1: values[0], x2: values[1], y1: values[2], y2: values[3])
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

```swift id=source0
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

```swift id=fixtures1
import Foundation

// W-gdb-199au-in2tinct-05 semantic tests for the SRTParser coordinate tail.
// Compiles against the PATCHED production files (same module, no source-copy
// stage): Sources/GorAVSubtitles/SRTParser.swift and SubtitleCue.swift.
// Exit 0 only when every check passes.

var failures = 0
@MainActor func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " " + info))
    if !ok { failures += 1 }
}

let doc = """
1
00:00:01,000 --> 00:00:02,500
Hello

2
00:00:03,000 --> 00:00:04,000 X1:100 X2:300 Y1:50 Y2:80
Positioned

3
00:00:05,000 --> 00:00:06,000
Plain again
"""

// C-series: coordinate tails parsed as data
do {
    let r = try SRTParser.parseWithCoordinates(doc)
    check("C1 three cues in file order", r.cues.map { $0.index } == [1, 2, 3])
    check("C2 parallel coordinate array", r.coordinates.count == 3)
    check("C3 tail values parsed exactly",
          r.coordinates[1] == SRTParser.CueCoordinates(x1: 100, x2: 300, y1: 50, y2: 80))
    check("C4 cues without a tail carry nil", r.coordinates[0] == nil && r.coordinates[2] == nil)
    check("C5 cue timing/text unchanged by a tail",
          r.cues[1].startSeconds == 3 && r.cues[1].endSeconds == 4 && r.cues[1].lines == ["Positioned"])
} catch { check("C1-C5 parseWithCoordinates", false, "\(error)") }

// B-series: bad tails refuse typed, whole document, correct line
@MainActor func badTail(_ tail: String, _ name: String, expectLine: Int) {
    let bad = "1\n00:00:01,000 --> 00:00:02,000 \(tail)\nText\n"
    do {
        _ = try SRTParser.parse(bad)
        check(name, false, "no throw")
    } catch SRTParser.ParseError.badCoordinateTail(let line) {
        check(name, line == expectLine, "line=\(line)")
    } catch { check(name, false, "\(error)") }
}
badTail("X1:1 X2:2 Y1:3", "B1 three-field tail refuses typed", expectLine: 2)
badTail("X1:1 X2:2 Y1:3 Y2:4 EXTRA:5", "B2 five-field tail refuses typed", expectLine: 2)
badTail("x1:1 X2:2 Y1:3 Y2:4", "B3 lowercase keys refuse typed", expectLine: 2)
badTail("X1:-1 X2:2 Y1:3 Y2:4", "B4 negative coordinate refuses typed", expectLine: 2)
badTail("X1:1.5 X2:2 Y1:3 Y2:4", "B5 non-integer coordinate refuses typed", expectLine: 2)
badTail("X1:1  X2:2 Y1:3 Y2:4", "B6 double space inside tail refuses typed", expectLine: 2)

// K-series: compatibility and strictness preserved
do {
    let cues = try SRTParser.parse(doc)
    check("K1 parse(_:) still drops positions but keeps cues", cues.count == 3 && cues[1].endSeconds == 4)
} catch { check("K1 parse(_:) compatibility", false, "\(error)") }
do {
    _ = try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,000\n\n")
    check("K2 missing text still refuses typed", false, "no throw")
} catch SRTParser.ParseError.missingText(let line) {
    check("K2 missing text still refuses typed", line == 3, "line=\(line)")
} catch { check("K2 missing text still refuses typed", false, "\(error)") }
do {
    _ = try SRTParser.parse("   \n\n")
    check("K3 empty document still refuses typed", false, "no throw")
} catch SRTParser.ParseError.emptyDocument {
    check("K3 empty document still refuses typed", true)
} catch { check("K3 empty document still refuses typed", false, "\(error)") }
do {
    let bom = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,000 X1:0 X2:0 Y1:0 Y2:0\r\nHi\r\n"
    let r = try SRTParser.parseWithCoordinates(bom)
    check("K4 BOM and CRLF tolerated, zero coordinates parse",
          r.cues.count == 1 && r.coordinates[0] == SRTParser.CueCoordinates(x1: 0, x2: 0, y1: 0, y2: 0))
} catch { check("K4 BOM/CRLF tolerated", false, "\(error)") }
do {
    _ = try SRTParser.parse("1\n00:00:02,000 --> 00:00:01,000 X1:0 X2:1 Y1:0 Y2:1\nText\n")
    check("K5 end-before-start still refuses before any tail use", false, "no throw")
} catch SRTParser.ParseError.endNotAfterStart {
    check("K5 end-before-start still refuses before any tail use", true)
} catch { check("K5 end-before-start still refuses", false, "\(error)") }

if failures == 0 {
    print("SEMANTIC_PASS W-gdb-199au-in2tinct-05 16 checks")
} else {
    print("SEMANTIC_FAIL W-gdb-199au-in2tinct-05 \(failures) failures")
    exit(1)
}
```

```text id=actual_run_log
PASS C1 three cues in file order
PASS C2 parallel coordinate array
PASS C3 tail values parsed exactly
PASS C4 cues without a tail carry nil
PASS C5 cue timing/text unchanged by a tail
PASS B1 three-field tail refuses typed
PASS B2 five-field tail refuses typed
PASS B3 lowercase keys refuse typed
PASS B4 negative coordinate refuses typed
PASS B5 non-integer coordinate refuses typed
PASS B6 double space inside tail refuses typed
PASS K1 parse(_:) still drops positions but keeps cues
PASS K2 missing text still refuses typed
PASS K3 empty document still refuses typed
PASS K4 BOM and CRLF tolerated, zero coordinates parse
PASS K5 end-before-start still refuses before any tail use
SEMANTIC_PASS W-gdb-199au-in2tinct-05 16 checks
```
