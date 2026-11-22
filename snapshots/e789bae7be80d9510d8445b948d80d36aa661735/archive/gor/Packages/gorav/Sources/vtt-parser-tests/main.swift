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
