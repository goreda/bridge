# W-gdb-198z-in2tinct-05 - Relocated fixture consumer vtt-parser-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-05",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/vtt-parser-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer vtt-parser-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/vtt-parser-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-05.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-05",
    "paths": [
      "Sources/vtt-parser-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-05.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-05.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.549539+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/vtt-parser-tests/main.swift",
        "block": "source1",
        "sha256": "247c48d0f929a5794bec200809077470bfcd6a45bbebb85e92c8d420bcfe4851"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-05.py",
        "block": "fixtures1",
        "sha256": "d9c48b004a6c96d1af2f2cbbf88aa1e3c58798c5ce174be3893c7ca006cd7d1d"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "cc28b6ccdacbd99c1b1928c1b7ea9c88fe375596e90088ffd89086ec82b0317b",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-05; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "7d2c7f182129c44f1d0f8cc6187a55b10653f4653335f1319138cd2875ce6577"
  }
}
```

```swift id=source1
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

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/vtt-parser-tests/main.swift').read_bytes()).hexdigest()=='247c48d0f929a5794bec200809077470bfcd6a45bbebb85e92c8d420bcfe4851'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-05; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-05; baseline only, product change and semantic test still required
```

secret scan: clean
