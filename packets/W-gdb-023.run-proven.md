# W-gdb-023 ASS override-tag semantics fixture atlas
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-023

```packet-json
{
  "packet_id": "W-gdb-023",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/ASSParser.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "ASSParser.parse -> Document { cues, unsupportedOverrides: [OverrideReport] }",
    "types": "OverrideReport { cueIndex: Int, tags: [String] }; ParseError.overrideOnlyText(line: Int); override rendering semantics UNSUPPORTED: reported + stripped, never interpreted",
    "ownership_lifetime": "documents are value types; override blocks removed from text, never rendered",
    "caller": "atlas runner (reviewer-runnable)",
    "callee": "ASSParser.parse -> Document { cues, unsupportedOverrides: [OverrideReport] } + typed ParseError.overrideOnlyText(line:)"
  },
  "test": {
    "command": "swift run subtitle-ass-tests",
    "expected": "exit 0; existing checks stay green; atlas rows assert exact OverrideReport lists + stripped text; one mutated tag list or unstripped block fails with its row id",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/ass-override-atlas/",
      "Sources/subtitle-ass-tests/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/subtitle-tests/ASSTests.swift",
        "block": "rf1"
      },
      {
        "path": "Sources/subtitle-tests/SRTTests.swift",
        "block": "rf2"
      },
      {
        "path": "Sources/subtitle-tests/SubtitleControllerTests.swift",
        "block": "rf3"
      },
      {
        "path": "Sources/subtitle-tests/SubtitlePlanTests.swift",
        "block": "rf4"
      },
      {
        "path": "Sources/subtitle-tests/SubtitleTrackTests.swift",
        "block": "rf5"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run subtitle-ass-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:18:07.761893+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL_CHECKS_PASS",
    "inline_files": [
      {
        "path": "Sources/subtitle-tests/ASSTests.swift",
        "block": "rf1",
        "sha256": "24e5725df5d8d0d7905f2072e70ebcdeb215bebc155c4c86bdf843d816a988cb"
      },
      {
        "path": "Sources/subtitle-tests/SRTTests.swift",
        "block": "rf2",
        "sha256": "1ee9b6b646fdcf5f402fd289319a90b990af68bbb7919770ac0aabf311217de1"
      },
      {
        "path": "Sources/subtitle-tests/SubtitleControllerTests.swift",
        "block": "rf3",
        "sha256": "7d809e48572e4bf7fef529226163fe7724b074b4ec682f6bc3fe52773bf10572"
      },
      {
        "path": "Sources/subtitle-tests/SubtitlePlanTests.swift",
        "block": "rf4",
        "sha256": "2ee504983febc98948c126c2fa85341ac1f1df2b9180c0df17ea7ad5263d6712"
      },
      {
        "path": "Sources/subtitle-tests/SubtitleTrackTests.swift",
        "block": "rf5",
        "sha256": "5ec765fbf610bc32c7ea9413e5fca581cc005ecd2b5219f0cb850a70aad169c1"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "86f07dbf9a1a3e27ae3ed79004ecd9e212577c1b17c02461263c2619da216735",
    "last_5_lines": [
      "[20/23] Wrapping AST for subtitle-ass-tests for debugging",
      "[21/23] Write Objects.LinkFileList",
      "[22/23] Linking subtitle-ass-tests",
      "Build complete! (2.86s)",
      "ALL_CHECKS_PASS"
    ],
    "receipt_sha256": "74ccfa9c496ce7c7f80ae3fdfcf0508591d765ecdc6c695a1bb200c9641bf68c"
  }
}
```

## problem (what fails for the user)
ASS override tags (pos, an, move, fade, clip) are detected, reported as UNSUPPORTED and stripped by ASSParser, but there is no fixture atlas of that reporting/stripping behavior, so a regression in the typed reporting ships silently (an override block left in rendered text, or a lost OverrideReport).

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVSubtitles/ASSParser.swift (sha256 4c16b99f, 301 lines; first 60 below) - the tag surface; Sources/GorAVSubtitles/SubtitlePlan.swift (same pin) - the layout consumer.
- real test command: swift run subtitle-ass-tests stays green.

## expected behaviour
a fixture atlas over the parser's REAL override surface: literal .ass snippets per override class asserting (a) the override block is removed from cue text, (b) it is reported in Document.unsupportedOverrides as exact OverrideReport(cueIndex, tags) rows, (c) override-only cue text yields the typed overrideOnlyText(line:) outcome; malformed tags degrade typed. no geometry/layout oracle exists at this pin - override rendering semantics are UNSUPPORTED and uninterpreted, and the atlas must not invent one.

## exact call site and interface
ASSParser's tag output (pinned excerpt) is the vocabulary; atlas = fixtures + expected tables + runner.

## pinned ABI decisions (integrator, 2026-11-15; geometry claim corrected)
the parser's REAL override surface (ASSParser.swift excerpt above): override blocks "{...}" are DETECTED, REMOVED from cue text, and REPORTED as UNSUPPORTED - public struct OverrideReport { cueIndex: Int; tags: [String] } collected in Document.unsupportedOverrides; a cue whose text is only override blocks yields the typed .overrideOnlyText(line:) outcome; a block with no backslash tag reports tags == []. NO rendering semantic inside override blocks is interpreted: there is no geometry/layout oracle at this pin, so the atlas asserts REPORTS + STRIPPED TEXT, never geometry. the earlier "expected geometry" framing is replaced accordingly.

## behaviour that must not change
existing ASS checks stay green; no font measurement assumption - the documented fixed cell metrics stand.

## acceptance test (from the product repo)
the atlas replays green against the pinned ASSParser: every override fixture asserts exact OverrideReport rows + stripped text; one mutated tag list or unstripped block fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSubtitles/ASSParser.swift (sha256 4c16b99f, lines 1-60 of 301)
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
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```text id=fixtures1
Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\pos(320,240)\fad(200,100)}Merhaba
# expect: cue text == "Merhaba"; unsupportedOverrides == [OverrideReport(cueIndex: 0, tags: ["\\pos","\\fad"])]
Dialogue: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,{\pos(1,1)}
# expect: typed overrideOnlyText(line: 2)
```

```text id=rf1
import Foundation
import GorAVSubtitles

// L6-u1 ASS parser contract tests (Linux model tests; no FFmpeg, no native
// display). 1 positive document (8 assertions) + 6 negative vectors, typed
// refusals only. Convention: ALL_CHECKS_PASS on success, exit 0/1.
@main
struct ASSTests {
    static var failures = 0
    static func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
    static func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

    static func expectThrows(_ m: String, _ want: ASSParser.ParseError, _ body: String) {
        do {
            _ = try ASSParser.parse(body)
            expect(false, "\(m): malformed input accepted")
        } catch let e as ASSParser.ParseError {
            expect(e == want, "\(m): got \(e), want \(want)")
        } catch {
            expect(false, "\(m): foreign error \(error)")
        }
    }

    static let sample = """
    [Script Info]
    Title: sample
    PlayResX: 384
    PlayResY: 288

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour
    Style: Default,Arial,20,&H00FFFFFF

    [Events]
    Format: Layer, Start, End, Style, Text
    Dialogue: 0,0:00:01.00,0:00:02.50,Default,Hello, world
    Comment: 0,0:00:00.00,0:00:00.10,Default,ignored
    Dialogue: 0,0:00:03.00,0:00:04.00,Default,{\\i1}Styled\\Nline2
    """

    static func main() {
        // p1: minimal document - style table, PlayRes, dialogue cues, comment skipped.
        do {
            let doc = try ASSParser.parse(sample)
            expect(doc.playResX == 384 && doc.playResY == 288, "p1: PlayRes")
            expect(doc.styles.count == 1, "p1: style count \(doc.styles.count)")
            if let s = doc.styles.first {
                expect(s.name == "Default" && s.fontName == "Arial" && s.fontSize == 20, "p1: style fields")
                expect(s.primaryColourARGB == 0x00FFFFFF, "p1: colour decode \(String(s.primaryColourARGB, radix: 16))")
            }
            expect(doc.cues.count == 2, "p1: cue count \(doc.cues.count) (comment must be skipped)")
            if doc.cues.count == 2 {
                let c0 = doc.cues[0]
                expect(c0.index == 1 && c0.startSeconds == 1.0 && c0.endSeconds == 2.5, "p1: cue0 timing")
                expect(c0.text == "Hello, world", "p1: cue0 text [\(c0.text)]")
                let c1 = doc.cues[1]
                expect(c1.index == 2 && c1.startSeconds == 3.0 && c1.endSeconds == 4.0, "p1: cue1 timing")
                expect(c0.styleName == "Default" && c1.styleName == "Default", "p1: style association preserved \(c0.styleName ?? "nil")")
                expect(c1.lines == ["Styled", "line2"], "p1: override strip + \\N split \(c1.lines)")
                expect(doc.unsupportedOverrides == [ASSParser.OverrideReport(cueIndex: 2, tags: ["\\i"])],
                       "p1: override reported UNSUPPORTED \(doc.unsupportedOverrides)")
            }
        } catch { expect(false, "p1: threw \(error)") }

        // p1b: asymmetric colour vector - a BGR/RGB swap bug cannot pass.
        do {
            let d = try ASSParser.parse("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour\nStyle: Asym,Arial,20,&H80112233\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,x\n")
            expect(d.styles.first?.primaryColourARGB == 0x80332211, "p1b: &H80112233 -> 80332211 got \(String(d.styles.first?.primaryColourARGB ?? 0, radix: 16))")
        } catch { expect(false, "p1b: threw \(error)") }

        // p1c: invalid colour length (5 hex digits) refuses - style skipped, no positional misdecode.
        do {
            let d = try ASSParser.parse("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour\nStyle: Bad,Arial,20,&H12345\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,x\n")
            expect(d.styles.isEmpty, "p1c: 5-hex colour refused (style skipped)")
            expect(d.skippedStyles == [ASSParser.SkippedStyle(line: 3, reason: "bad colour")],
                   "p1c: skip is caller-visible \(d.skippedStyles)")
        } catch { expect(false, "p1c: threw \(error)") }

        // p1d: stray "}" outside any block is preserved as text.
        do {
            let d = try ASSParser.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,a}b\n")
            expect(d.cues.first?.text == "a}b", "p1d: stray } preserved got [\(d.cues.first?.text ?? "")]")
        } catch { expect(false, "p1d: threw \(error)") }

        // p2: a document with no override blocks reports none.
        do {
            let clean = try ASSParser.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,plain\n")
            expect(clean.unsupportedOverrides.isEmpty, "p2: no overrides -> empty report")
            expect(clean.cues.count == 1, "p2: plain cue parsed")
        } catch { expect(false, "p2: threw \(error)") }

        // p3: unterminated override block still reported UNSUPPORTED.
        do {
            let d = try ASSParser.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,tail {\\pos(3,4)\n")
            expect(d.unsupportedOverrides == [ASSParser.OverrideReport(cueIndex: 1, tags: ["\\pos"])],
                   "p3: unterminated block reported \(d.unsupportedOverrides)")
        } catch { expect(false, "p3: threw \(error)") }

        // n1: Dialogue before any Format in [Events].
        expectThrows("n1", .dialogueBeforeFormat(line: 2), "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,x\n")
        // n2: no [Events] section at all.
        expectThrows("n2", .missingEventsSection, "[Script Info]\nTitle: x\n")
        // n3: seconds out of range.
        expectThrows("n3", .badTimestamp(line: 3), "[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:61.00,0:00:02.00,x\n")
        // n4: end before start.
        expectThrows("n4", .endNotAfterStart(line: 3), "[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:02.00,0:00:01.00,x\n")
        // n5: fewer fields than the Format declares.
        expectThrows("n5", .badDialogueFieldCount(line: 3), "[Events]\nFormat: Layer, Start, End, Style, Text\nDialogue: 0,0:00:01.00\n")
        // n7: pure override-only event -> explicit typed refusal (evidence kept).
        expectThrows("n7", .overrideOnlyText(line: 3), "[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,{\\pos(10,10)}\n")
        // n6: empty text field.
        expectThrows("n6", .missingText(line: 3), "[Events]\nFormat: Layer, Start, End, Style, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,\n")

        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=rf2
import Foundation
import GorAVSubtitles

// L5-u1 SRT parser contract tests (Linux model tests; no FFmpeg, no native
// display). 4 positive vectors + 7 negative vectors, typed refusals only.
// Convention: ALL_CHECKS_PASS on success, exit 0/1 like the trunk test targets.
@main
struct SRTTests {
    static var failures = 0
    static func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
    static func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

    static func expectThrows(_ m: String, _ want: SRTParser.ParseError, _ body: String) {
        do {
            _ = try SRTParser.parse(body)
            expect(false, "\(m): malformed input accepted")
        } catch let e as SRTParser.ParseError {
            expect(e == want, "\(m): got \(e), want \(want)")
        } catch {
            expect(false, "\(m): foreign error \(error)")
        }
    }

    static func main() {
        // p1: two LF cues, exact timing and text.
        do {
            let cues = try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,500\nHello world\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond line\n")
            expect(cues.count == 2, "p1: cue count \(cues.count)")
            if cues.count == 2 {
                expect(cues[0].index == 1 && cues[0].startSeconds == 1.0 && cues[0].endSeconds == 2.5, "p1: cue0 timing")
                expect(cues[0].lines == ["Hello world"] && cues[0].text == "Hello world", "p1: cue0 text")
                expect(cues[1].index == 2 && cues[1].startSeconds == 3.0 && cues[1].endSeconds == 4.0, "p1: cue1 timing")
            }
        } catch { expect(false, "p1: threw \(error)") }

        // p2: BOM + CRLF, hours > 0.
        do {
            let cues = try SRTParser.parse("\u{FEFF}1\r\n00:10:00,100 --> 01:00:00,000\r\nTitle\r\n")
            expect(cues.count == 1, "p2: cue count")
            if let c = cues.first {
                expect(c.startSeconds == 600.1 && c.endSeconds == 3600.0, "p2: timing \(c.startSeconds)-\(c.endSeconds)")
                expect(c.text == "Title", "p2: text")
            }
        } catch { expect(false, "p2: threw \(error)") }

        // p3: coordinate tail after the end timestamp is ignored.
        do {
            let cues = try SRTParser.parse("3\n00:00:05,000 --> 00:00:06,500 X1:100 X2:200 Y1:10 Y2:20\nPos\n")
            expect(cues.count == 1 && cues[0].endSeconds == 6.5, "p3: coordinate tail")
        } catch { expect(false, "p3: threw \(error)") }

        // p4: multiline cue; inline tags kept verbatim; half-open contains().
        do {
            let cues = try SRTParser.parse("7\n00:00:07,250 --> 00:00:09,000\n<i>one</i>\ntwo & three\n")
            expect(cues.count == 1, "p4: cue count")
            if let c = cues.first {
                expect(c.lines == ["<i>one</i>", "two & three"], "p4: lines \(c.lines)")
                expect(c.text == "<i>one</i>\ntwo & three", "p4: joined text")
                expect(c.startSeconds == 7.25, "p4: start")
                expect(c.contains(seconds: 7.25), "p4: contains start (closed)")
                expect(!c.contains(seconds: 9.0), "p4: excludes end (open)")
                expect(c.contains(seconds: 8.999), "p4: contains interior")
                expect(!c.contains(seconds: 7.249), "p4: excludes before")
            }
        } catch { expect(false, "p4: threw \(error)") }

        // n1: single-dash arrow.
        expectThrows("n1", .badTimingLine(line: 2), "1\n00:00:01,000 -> 00:00:02,000\ntext\n")
        // n2: zero-length cue (end == start).
        expectThrows("n2", .endNotAfterStart(line: 2), "1\n00:00:02,000 --> 00:00:02,000\ntext\n")
        // n3: dot millisecond separator (spec is comma).
        expectThrows("n3", .badTimestamp(line: 2), "1\n00:00:01.000 --> 00:00:02,000\ntext\n")
        // n4: non-numeric index.
        expectThrows("n4", .badIndex(line: 1), "x\n00:00:01,000 --> 00:00:02,000\ntext\n")
        // n5: cue without text.
        expectThrows("n5", .missingText(line: 3), "1\n00:00:01,000 --> 00:00:02,000\n")
        // n8: whitespace-only text line is blank everywhere (symmetric strictness).
        expectThrows("n8", .missingText(line: 3), "1\n00:00:01,000 --> 00:00:02,000\n   \n")
        // n6: empty document.
        expectThrows("n6", .emptyDocument, "  \n\n")
        // n7: text where the timing line must be.
        expectThrows("n7", .badTimingLine(line: 2), "1\ntext\n")

        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=rf3
import Foundation
import GorAVSubtitles

// R7 (arch-195b) witness: external subtitle auto-load discovery, primary/
// secondary selection, per-slot delay, cue identity across seeks, reset.

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

let srt = """
1
00:00:01,000 --> 00:00:03,000
Hello

2
00:00:05,000 --> 00:00:07,000
World

"""

let dir = NSTemporaryDirectory() + "subctl-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let video = dir + "/movie.mp4"
try! Data().write(to: URL(fileURLWithPath: video))
try! srt.write(toFile: dir + "/movie.srt", atomically: true, encoding: .utf8)
try! srt.write(toFile: dir + "/movie.en.srt", atomically: true, encoding: .utf8)
try! srt.write(toFile: dir + "/movie.tr.ass", atomically: true, encoding: .utf8) // not valid ASS; discovery only
try! "junk".write(toFile: dir + "/movie.txt", atomically: true, encoding: .utf8)
try! srt.write(toFile: dir + "/other.srt", atomically: true, encoding: .utf8)

// A-series: auto-load discovery
let found = SubtitleAutoLoad.discover(forVideoPath: video)
check("A1 exact basename first", found.first?.path == dir + "/movie.srt" && found.first?.tag == nil)
check("A2 tagged matches discovered, sorted", found.count == 3 && found[1].tag == "en" && found[2].tag == "tr")
check("A3 non-matching and non-subtitle files excluded", !found.contains { $0.path.contains("other") || $0.path.contains("txt") })
check("A4 missing directory is empty, not an error", SubtitleAutoLoad.discover(forVideoPath: dir + "/nope/v.mp4").isEmpty)
check("A5 ssa normalizes to ass format", SubtitleAutoLoad.discover(forVideoPath: video).allSatisfy { $0.format != "ssa" })

// B-series: selection, delay, identity across seeks, reset
var ctl = SubtitleController()
let track = try! SubtitleTrack.load(path: dir + "/movie.srt")
ctl.selectPrimary(track)
check("B1 primary cue at 2s", ctl.activeCue(at: 2.0, slot: .primary)?.text == "Hello")
check("B2 secondary empty", ctl.activeCue(at: 2.0, slot: .secondary) == nil)
ctl.selectSecondary(track)
check("B3 secondary cue at 2s", ctl.activeCue(at: 2.0, slot: .secondary)?.text == "Hello")

let idBefore = ctl.activeCueIdentity(at: 2.0, slot: .primary)
// Seek far forward and back: identity must be unchanged for the same time.
_ = ctl.activeCue(at: 500.0, slot: .primary)
_ = ctl.activeCue(at: 0.0, slot: .primary)
check("B4 cue identity stable across seeks", ctl.activeCueIdentity(at: 2.0, slot: .primary) == idBefore)
check("B5 identity carries content id and index", idBefore?.cueIndex == 1 && idBefore != nil)

ctl.setDelay(1.5, slot: .primary)
check("B6 positive delay shows cue later", ctl.activeCue(at: 2.0, slot: .primary) == nil && ctl.activeCue(at: 3.0, slot: .primary)?.text == "Hello")
check("B7 delay does not move other slot", ctl.activeCue(at: 2.0, slot: .secondary)?.text == "Hello")
ctl.setDelay(.nan, slot: .primary)
check("B8 non-finite delay ignored", ctl.activeCue(at: 3.0, slot: .primary)?.text == "Hello")

ctl.setVisible(false, slot: .primary)
check("B9 hidden slot reports no cue", ctl.activeCue(at: 3.0, slot: .primary) == nil)
ctl.setVisible(true, slot: .primary)
check("B10 re-shown slot reports again", ctl.activeCue(at: 3.0, slot: .primary)?.text == "Hello")

ctl.reset()
check("B11 reset unloads secondary", ctl.activeCue(at: 2.0, slot: .secondary) == nil)
check("B12 reset zeroes delay", ctl.activeCue(at: 2.0, slot: .primary)?.text == "Hello")
check("B13 reset keeps primary loaded", ctl.primary != nil)

// C-series: content identity differs between tracks
let srt2 = srt.replacingOccurrences(of: "Hello", with: "Hallo")
try! srt2.write(toFile: dir + "/movie.de.srt", atomically: true, encoding: .utf8)
let track2 = try! SubtitleTrack.load(path: dir + "/movie.de.srt")
ctl.selectSecondary(track2)
let idP = ctl.activeCueIdentity(at: 2.0, slot: .primary)
let idS = ctl.activeCueIdentity(at: 2.0, slot: .secondary)
check("C1 same index, different content id across tracks", idP?.cueIndex == idS?.cueIndex && idP?.trackContentID != idS?.trackContentID)

try? FileManager.default.removeItem(atPath: dir)
print(failures == 0 ? "subtitle-controller-tests: all pass" : "subtitle-controller-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

```text id=rf4
import Foundation
import GorAVSubtitles

// Standalone test runner for the SubtitlePlan timed-plan API IMPLEMENTATION (u8r2,
// lanes L5/L6). Q1-Q5 engineering decisions LANDED per gdb's 2026-11-01
// decision as relayed via coordination (peer-attributed, unverified by us
// against an authenticated gdb record); tie rule peer-confirmed. These tests
// lock the decided behavior: content identity vs producer generation,
// findings in the identity, A->B->A regression, exhaustion refusal, typed
// answers, Q4 suppression/tie/boundary semantics, Q5 defaults, Q2 echo.
// ALL_CHECKS_PASS / FAILURES=n, exit 0/1. Run as a SEPARATE consumer module
// (SRTTests/ASSTests convention): build GorAVSubtitles with
// swiftc -emit-module -emit-library -module-name GorAVSubtitles, then compile
// this file against it with -I/-L.

@main
struct SubtitlePlanTests {
    static var failures = 0
    static func check(_ cond: Bool, _ name: String) {
        if cond { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
    }

    static func main() {
        let cues = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "Default"),
                    SubtitleCue(index: 2, startSeconds: 4, endSeconds: 6, lines: ["b"], styleName: "Default")]
        let styles = [ASSParser.Style(name: "Default", fontName: "Arial", fontSize: 20, primaryColourARGB: 0x00FFFFFF)]
        let noFindings: ([ASSParser.OverrideReport], [ASSParser.SkippedStyle]) = ([], [])

        // 1: contentID deterministic
        let c1 = SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                               playResX: nil, playResY: nil, unsupportedOverrides: noFindings.0, skippedStyles: noFindings.1)
        let c2 = SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                               playResX: nil, playResY: nil, unsupportedOverrides: noFindings.0, skippedStyles: noFindings.1)
        check(c1 == c2, "contentID deterministic")

        // 2: contentID changes with content (text, timing, style association, style table)
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a2"], styleName: "Default"), cues[1]], styles: styles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on text change")
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3.5, lines: ["a"], styleName: "Default"), cues[1]], styles: styles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on timing change")
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "Other"), cues[1]], styles: styles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on style association change")
        check(SubtitlePlanContentID.compute(cues: cues, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on style table change")

        // 3: findings are part of the identity (gdb note F2)
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                            playResX: nil, playResY: nil, unsupportedOverrides: [ASSParser.OverrideReport(cueIndex: 1, tags: ["\\b"])],
                                            skippedStyles: []) != c1,
              "contentID changes on override findings")
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                            playResX: nil, playResY: nil, unsupportedOverrides: [],
                                            skippedStyles: [ASSParser.SkippedStyle(line: 3, reason: "bad colour")]) != c1,
              "contentID changes on skipped-style findings")

        // 3b: review note S1 - serialization is unambiguous (length-prefixed):
        // field-boundary ambiguity and embedded NULs must change the identity
        let cueSplit1 = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["ab"], styleName: "D")]
        let cueSplit2 = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a", "b"], styleName: "D")]
        check(SubtitlePlanContentID.compute(cues: cueSplit1, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: cueSplit2, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "line-count boundary unambiguous (ab vs a|b)")
        let cueNul = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a\u{0}b"], styleName: "D")]
        check(SubtitlePlanContentID.compute(cues: cueNul, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: cueSplit1, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "embedded NUL changes identity")
        let styleShift1 = [ASSParser.Style(name: "ab", fontName: "c", fontSize: 20, primaryColourARGB: 0x00FFFFFF)]
        let styleShift2 = [ASSParser.Style(name: "a", fontName: "bc", fontSize: 20, primaryColourARGB: 0x00FFFFFF)]
        check(SubtitlePlanContentID.compute(cues: [], styles: styleShift1, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: [], styles: styleShift2, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "style field boundary unambiguous (ab+c vs a+bc)")

        // 3c: review note S2 - fontSize precision is exact, not rounded
        let styleTiny1 = [ASSParser.Style(name: "D", fontName: "A", fontSize: 20.0, primaryColourARGB: 0x00FFFFFF)]
        let styleTiny2 = [ASSParser.Style(name: "D", fontName: "A", fontSize: 20.0 + 1e-9, primaryColourARGB: 0x00FFFFFF)]
        check(SubtitlePlanContentID.compute(cues: [], styles: styleTiny1, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: [], styles: styleTiny2, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "fontSize 1e-9 difference changes identity (no rounding collapse)")

        // 3d: gdb review P5-1 - PlayRes presence and values are identity
        let base = SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: 640, playResY: 360,
                                                 unsupportedOverrides: [], skippedStyles: [])
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: nil, playResY: nil,
                                            unsupportedOverrides: [], skippedStyles: []) != base,
              "PlayRes presence changes identity")
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: 641, playResY: 360,
                                            unsupportedOverrides: [], skippedStyles: []) != base,
              "PlayRes value change changes identity")
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: 640, playResY: nil,
                                            unsupportedOverrides: [], skippedStyles: []) != base,
              "PlayRes per-axis presence changes identity")

        // 3e: gdb review P5-2 - nil vs empty styleName are distinct identities
        let cueNilStyle = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: nil)]
        let cueEmptyStyle = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "")]
        check(SubtitlePlanContentID.compute(cues: cueNilStyle, styles: [], playResX: nil, playResY: nil,
                                            unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: cueEmptyStyle, styles: [], playResX: nil, playResY: nil,
                                               unsupportedOverrides: [], skippedStyles: []),
              "nil vs empty styleName are distinct identities")

        // 4: A->B->A (gdb note F1): contentID repeats, generation does not
        let trackA = SubtitleTrack.Track(format: "ass", cues: cues, styles: styles,
                                         unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let trackB = SubtitleTrack.Track(format: "ass", cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a2"], styleName: "Default"), cues[1]],
                                         styles: styles, unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let producer = SubtitlePlanProducer(track: trackA)
        guard let planA1 = try? producer.makePlan(),
              let _ = try? producer.updateTrack(trackB),
              let planA2 = try? producer.updateTrack(trackA) else {
            check(false, "A->B->A plans issued"); return
        }
        check(planA1.planRevision.contentID == planA2.planRevision.contentID,
              "A->B->A: contentID returns (identity, not freshness)")
        check(planA1.planRevision.generation < planA2.planRevision.generation,
              "A->B->A: generation advanced")
        check(planA1.planRevision != planA2.planRevision,
              "A->B->A: full revision pair never reused")

        // 5: generation strictly monotonic across issues
        check(planA2.planRevision.generation == planA1.planRevision.generation + 2,
              "generation strictly monotonic")

        // 6: exhaustion is a typed refusal, never a wrap or reuse
        let trackSrt = SubtitleTrack.Track(format: "srt", cues: cues, styles: [],
                                           unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        let hot = SubtitlePlanProducer(track: trackSrt, startingGeneration: UInt64.max - 1)
        guard let lastOK = try? hot.makePlan() else { check(false, "last generation issuable"); return }
        check(lastOK.planRevision.generation == UInt64.max, "generation reaches max")
        do {
            _ = try hot.makePlan()
            check(false, "exhaustion throws typed refusal")
        } catch SubtitlePlanProducer.RevisionError.generationExhausted {
            check(true, "exhaustion throws typed refusal")
        } catch { check(false, "exhaustion throws typed refusal") }
        check(hot.lastGeneration == UInt64.max, "no wrap: counter stays at max after refusal")

        // 7: plan carries PlayRes through the track; srt plan has none
        check(planA1.playResX == 640 && planA1.playResY == 360, "plan carries PlayRes")
        let srtProducer = SubtitlePlanProducer(track: trackSrt)
        guard let srtPlan = try? srtProducer.makePlan() else { check(false, "srt plan issued"); return }
        check(srtPlan.playResX == nil, "srt plan has no PlayRes")

        // 8: plan revision contentID matches compute for its content
        // (trackA carries PlayRes 640/360, so the identity includes it)
        check(planA1.planRevision.contentID == SubtitlePlanContentID.compute(
            cues: cues, styles: styles, playResX: 640, playResY: 360,
            unsupportedOverrides: [], skippedStyles: []), "plan contentID matches compute")

        // 9: typed overlay answers on SDR surface carry the full revision pair
        if case .empty(let rev) = planA1.overlay(at: 0.5, surfaceIsHDR: false) {
            check(rev == planA1.planRevision, "gap -> empty with plan revision")
        } else { check(false, "gap -> empty") }
        if case .cue(let c, let sup, let rev) = planA1.overlay(at: 2, surfaceIsHDR: false) {
            check(c.index == 1 && rev == planA1.planRevision && sup.isEmpty, "active cue with plan revision, no suppression")
        } else { check(false, "active cue answer") }
        if case .empty = planA1.overlay(at: 3, surfaceIsHDR: false) {
            check(true, "end is exclusive at plan level")
        } else { check(false, "end exclusivity") }

        // 10: HDR surface -> typed refusal, never a degraded cue answer
        if case .hdrUnsupported(let rev) = planA1.overlay(at: 2, surfaceIsHDR: true) {
            check(rev == planA1.planRevision, "HDR -> typed refusal with plan revision")
        } else { check(false, "HDR typed refusal") }
        if case .hdrUnsupported = planA1.overlay(at: 0.5, surfaceIsHDR: true) {
            check(true, "HDR refusal even in gaps (no misrender)")
        } else { check(false, "HDR refusal in gap") }

        // 11: Q4 - latest-starting wins; suppressed indices typed, sorted, never stacked
        let overA = SubtitleCue(index: 1, startSeconds: 1, endSeconds: 5, lines: ["a"], styleName: "Default")
        let overB = SubtitleCue(index: 2, startSeconds: 3, endSeconds: 6, lines: ["b"], styleName: "Default")
        let overC = SubtitleCue(index: 3, startSeconds: 4, endSeconds: 8, lines: ["c"], styleName: "Default")
        let overTrack = SubtitleTrack.Track(format: "ass", cues: [overA, overB, overC], styles: styles,
                                            unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let overProducer = SubtitlePlanProducer(track: overTrack)
        guard let overPlan = try? overProducer.makePlan() else { check(false, "overlap plan issued"); return }
        if case .cue(let w, let sup, _) = overPlan.overlay(at: 4.5, surfaceIsHDR: false) {
            check(w.index == 3 && sup == [1, 2], "three-way overlap: latest-starting wins, suppressed [1,2] sorted")
        } else { check(false, "three-way overlap answer") }
        if case .cue(let w2, let sup2, _) = overPlan.overlay(at: 3.5, surfaceIsHDR: false) {
            check(w2.index == 2 && sup2 == [1], "two-way overlap: suppressed [1]")
        } else { check(false, "two-way overlap answer") }
        if case .cue(_, let sup3, _) = overPlan.overlay(at: 1.5, surfaceIsHDR: false) {
            check(sup3.isEmpty, "single coverage: no suppressed indices")
        } else { check(false, "single coverage answer") }

        // 11b: Q4 tie rule (named behavior; decision silent on ties): equal
        // startSeconds -> FIRST IN TRACK ORDER wins, other suppressed
        let tieA = SubtitleCue(index: 1, startSeconds: 2, endSeconds: 5, lines: ["first"], styleName: "Default")
        let tieB = SubtitleCue(index: 2, startSeconds: 2, endSeconds: 6, lines: ["second"], styleName: "Default")
        let tieTrack = SubtitleTrack.Track(format: "ass", cues: [tieA, tieB], styles: styles,
                                           unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let tieProducer = SubtitlePlanProducer(track: tieTrack)
        guard let tiePlan = try? tieProducer.makePlan() else { check(false, "tie plan issued"); return }
        if case .cue(let tw, let tsup, _) = tiePlan.overlay(at: 3, surfaceIsHDR: false) {
            check(tw.index == 1 && tsup == [2], "equal-start tie: first in track order wins")
        } else { check(false, "tie answer") }

        // 11c: half-open boundary - pts == start is INCLUSIVE (gdb u8r1 review note 2)
        let edgeTrack = SubtitleTrack.Track(format: "srt", cues: [SubtitleCue(index: 1, startSeconds: 2, endSeconds: 5, lines: ["edge"], styleName: "Default")],
                                            styles: styles, unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        let edgeProducer = SubtitlePlanProducer(track: edgeTrack)
        guard let edgePlan = try? edgeProducer.makePlan() else { check(false, "edge plan issued"); return }
        if case .cue(let ew, let esup, _) = edgePlan.overlay(at: 2, surfaceIsHDR: false) {
            check(ew.index == 1 && esup.isEmpty, "pts == start inclusive (half-open [start,end))")
        } else { check(false, "start-inclusive answer") }

        // 11d: duplicate cue indices -> typed plan finding; index-based
        // suppression reporting is then ambiguous for the shared index
        // (gdb u8r1 review note 1)
        let dupTrack = SubtitleTrack.Track(format: "srt", cues: [SubtitleCue(index: 7, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "Default"),
                                                               SubtitleCue(index: 7, startSeconds: 2, endSeconds: 4, lines: ["b"], styleName: "Default")],
                                           styles: styles, unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        let dupProducer = SubtitlePlanProducer(track: dupTrack)
        guard let dupPlan = try? dupProducer.makePlan() else { check(false, "dup plan issued"); return }
        if case .cue(let dw, let dsup, _) = dupPlan.overlay(at: 2.5, surfaceIsHDR: false) {
            check(dw.startSeconds == 2 && dsup.isEmpty && dupPlan.findings == [.duplicateCueIndices([7])],
                  "duplicate cue indices -> typed finding; shared-index suppression visibly ambiguous")
        } else { check(false, "duplicate-index answer") }

        // 12: Q5 - declared default PlayRes 384x288 + usedDefaultPlayRes flag
        check(srtPlan.effectivePlayResX == 384 && srtPlan.effectivePlayResY == 288,
              "absent PlayRes -> declared default 384x288")
        check(srtPlan.usedDefaultPlayRes, "usedDefaultPlayRes true when absent")
        check(planA1.effectivePlayResX == 640 && planA1.effectivePlayResY == 360 && !planA1.usedDefaultPlayRes,
              "raw PlayRes used when present, flag false")

        // 13: Q2 - presenter echo is the generation only
        check(planA1.presenterEchoRevision == planA1.planRevision.generation,
              "presenter echo carries generation only")
        check(planA1.presenterEchoRevision != planA2.presenterEchoRevision,
              "echo changes across reissue (same content, new generation)")

        if failures == 0 { print("ALL_CHECKS_PASS") } else { print("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=rf5
import Foundation
import GorAVSubtitles

// Standalone test runner for SubtitleTrack + SubtitleSchedule (lanes L5/L6 u2).
// Self-contained: fixtures are written to a temp directory, no external corpus
// needed. Prints ALL_CHECKS_PASS or FAILURES=<n>; exit 0/1 (CoexistTest
// convention). Run as a SEPARATE consumer module (SRTTests/ASSTests
// convention): build GorAVSubtitles with swiftc -emit-module -emit-library
// -module-name GorAVSubtitles, then compile this file against it with -I/-L.

@main
struct SubtitleTrackTests {
    static var failures = 0
    static func check(_ cond: Bool, _ name: String) {
        if cond { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
    }
    static func main() {

        let tmp = NSTemporaryDirectory() + "tracktests-\(ProcessInfo.processInfo.globallyUniqueString)"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let srtText = "1\n00:00:01,000 --> 00:00:03,000\nfirst\n\n2\n00:00:04,000 --> 00:00:06,000\nsecond\n"
        let assText = """
        [Script Info]
        Title: t
        ScriptType: v4.00+
        PlayResX: 640
        PlayResY: 360

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour
        Style: Default,Arial,28,&H00FFFFFF

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\b1}first\\Nsecond
        """

        let srtPath = tmp + "/a.srt"
        let assPath = tmp + "/b.ass"
        let badPath = tmp + "/c.txt"
        try? srtText.write(toFile: srtPath, atomically: true, encoding: .utf8)
        try? assText.write(toFile: assPath, atomically: true, encoding: .utf8)
        try? "x".write(toFile: badPath, atomically: true, encoding: .utf8)

        // 1: srt sidecar loads
        if let t = try? SubtitleTrack.load(path: srtPath) {
            check(t.format == "srt" && t.cues.count == 2, "load .srt -> 2 cues")
            check(t.playResX == nil && t.playResY == nil, "srt load carries no PlayRes")
            check(t.cues[0].startSeconds == 1 && t.cues[1].startSeconds == 4, "srt cue times")
        } else { check(false, "load .srt -> 2 cues"); check(false, "srt load carries no PlayRes"); check(false, "srt cue times") }

        // 2: ass sidecar loads with styles
        if let t = try? SubtitleTrack.load(path: assPath) {
            check(t.format == "ass" && t.cues.count == 1 && t.styles.count == 1, "load .ass -> 1 cue + 1 style")
            check(t.playResX == 640 && t.playResY == 360, "ass load carries PlayRes through loader")
            check(t.cues[0].lines == ["first", "second"], "ass \\N -> break")
            check(t.unsupportedOverrides == [ASSParser.OverrideReport(cueIndex: 1, tags: ["\\b"])],
                  "ass override surfaced UNSUPPORTED")
        } else { check(false, "load .ass -> 1 cue + 1 style"); check(false, "ass load carries PlayRes through loader"); check(false, "ass \\N -> break") }

        // 3: unknown extension -> typed refusal
        do {
            _ = try SubtitleTrack.load(path: badPath)
            check(false, "unknown ext refused")
        } catch SubtitleTrack.LoadError.unknownFormat { check(true, "unknown ext refused") } catch { check(false, "unknown ext refused") }

        // 4: missing file -> typed refusal
        do {
            _ = try SubtitleTrack.load(path: tmp + "/missing.srt")
            check(false, "missing file refused")
        } catch SubtitleTrack.LoadError.unreadable { check(true, "missing file refused") } catch { check(false, "missing file refused") }

        // 5: clean schedule has no issues; activeCue edges
        let cues = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"]),
                    SubtitleCue(index: 2, startSeconds: 4, endSeconds: 6, lines: ["b"])]
        let sched = SubtitleSchedule(cues: cues)
        check(sched.issues.isEmpty, "clean schedule no issues")
        check(sched.activeCue(at: 0.5) == nil, "before first cue -> nil")
        check(sched.activeCue(at: 1) != nil && sched.activeCue(at: 2.999) != nil, "inside first cue")
        check(sched.activeCue(at: 3) == nil, "end is exclusive")
        check(sched.activeCue(at: 3.5) == nil, "gap between cues -> nil")
        check(sched.activeCue(at: 5)?.index == 2, "inside second cue")
        check(sched.activeCue(at: 6.1) == nil, "after last cue -> nil")

        // 6: overlap + out-of-order detected, not repaired
        let messy = [SubtitleCue(index: 1, startSeconds: 5, endSeconds: 7, lines: ["x"]),
                     SubtitleCue(index: 2, startSeconds: 2, endSeconds: 4, lines: ["y"]),
                     SubtitleCue(index: 3, startSeconds: 6, endSeconds: 8, lines: ["z"])]
        let messySched = SubtitleSchedule(cues: messy)
        check(messySched.issues.contains(.outOfOrder(index: 2)), "out-of-order flagged")
        check(messySched.issues.contains(.overlap(index: 3, previous: 1)), "overlap flagged (non-adjacent earlier cue)")

        // 7: overlapping lookup resolves to latest-starting cue
        let over = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 5, lines: ["a"]),
                    SubtitleCue(index: 2, startSeconds: 3, endSeconds: 6, lines: ["b"])]
        check(SubtitleSchedule(cues: over).activeCue(at: 4)?.index == 2, "overlap -> latest-starting cue wins")

        // 8: UNORDERED input - latest-starting policy holds regardless of file order
        let unordered = [SubtitleCue(index: 1, startSeconds: 3, endSeconds: 6, lines: ["late-start"]),
                         SubtitleCue(index: 2, startSeconds: 1, endSeconds: 5, lines: ["early-start"])]
        check(SubtitleSchedule(cues: unordered).activeCue(at: 4)?.index == 1, "unordered input: latest-starting wins")

        // 9: non-adjacent overlap detected (cue 3 overlaps cue 1 across cue 2)
        let nonAdj = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 8, lines: ["a"]),
                      SubtitleCue(index: 2, startSeconds: 2, endSeconds: 3, lines: ["b"]),
                      SubtitleCue(index: 3, startSeconds: 4, endSeconds: 5, lines: ["c"])]
        let nonAdjIssues = SubtitleSchedule(cues: nonAdj).issues
        check(nonAdjIssues.contains(.overlap(index: 3, previous: 1)), "non-adjacent overlap flagged")
        check(nonAdjIssues.contains(.overlap(index: 2, previous: 1)), "adjacent overlap still flagged")

        // 10: malformed style surfaces through the LOADER, not only the parser
        let badStyleAss = tmp + "/badstyle.ass"
        try? "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour\nStyle: Bad,Arial,20,&H12345\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,x\n".write(toFile: badStyleAss, atomically: true, encoding: .utf8)
        if let t = try? SubtitleTrack.load(path: badStyleAss) {
            check(t.skippedStyles == [ASSParser.SkippedStyle(line: 3, reason: "bad colour")],
                  "loader carries skippedStyles \(t.skippedStyles)")
            check(t.styles.isEmpty, "loader: bad style not adopted")
        } else { check(false, "loader carries skippedStyles"); check(false, "loader: bad style not adopted") }

        try? FileManager.default.removeItem(atPath: tmp)

        if failures == 0 { print("ALL_CHECKS_PASS") } else { print("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=actual_run_log
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-8p74mkxj/tree/Sources/subtitle-tests/SRTTests.swift
Building for debugging...
[0/7] Write sources
[2/7] Write swift-version--9C6B84B6E025C5B.txt
[4/14] Emitting module GorAVSubtitles
[5/19] Compiling GorAVSubtitles ASSParser.swift
[6/19] Compiling GorAVSubtitles SRTParser.swift
[7/19] Compiling GorAVSubtitles SubtitleAutoLoad.swift
[8/19] Compiling GorAVSubtitles SubtitleController.swift
[9/19] Compiling GorAVSubtitles SubtitleCue.swift
[10/19] Compiling GorAVSubtitles SubtitleCueDelivery.swift
[11/19] Compiling GorAVSubtitles SubtitleCueOutput.swift
[12/19] Compiling GorAVSubtitles SubtitlePlan.swift
[13/19] Compiling GorAVSubtitles SubtitleSchedule.swift
[14/19] Compiling GorAVSubtitles SubtitleSidecarSession.swift
[15/19] Compiling GorAVSubtitles SubtitleTrack.swift
[16/20] Wrapping AST for GorAVSubtitles for debugging
[18/22] Emitting module subtitle_ass_tests
[19/22] Compiling subtitle_ass_tests ASSTests.swift
[20/23] Wrapping AST for subtitle-ass-tests for debugging
[21/23] Write Objects.LinkFileList
[22/23] Linking subtitle-ass-tests
Build complete! (2.86s)
ALL_CHECKS_PASS
```
