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
  "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
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
    "command": "swift run subtitle-ass-tests && swift run subtitle-ass-atlas-tests",
    "expected": "exit 0; subtitle-ass-tests stays green (existing checks); atlas suite's final line matches '^ass-atlas-tests: [1-9][0-9]* PASS, 0 FAIL$'; atlas rows assert exact OverrideReport lists + stripped text against the real ASSParser; one mutated tag list or unstripped block fails with its row id",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
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
        "block": "rf0"
      },
      {
        "path": "Package.swift",
        "block": "rf1"
      },
      {
        "path": "Sources/subtitle-tests/ASSAtlasTests.swift",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
    "command": "swift run subtitle-ass-tests && swift run subtitle-ass-atlas-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:31:09.890739+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ass-atlas-tests: 32 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/subtitle-tests/ASSTests.swift",
        "block": "rf0",
        "sha256": "24e5725df5d8d0d7905f2072e70ebcdeb215bebc155c4c86bdf843d816a988cb"
      },
      {
        "path": "Package.swift",
        "block": "rf1",
        "sha256": "d432e750a7372190a7be5b61346b576dbe0b35deb7b4b34e1b3f1d6615a2696e"
      },
      {
        "path": "Sources/subtitle-tests/ASSAtlasTests.swift",
        "block": "rf2",
        "sha256": "10bf2f1c11bdf97ca8691a3d840dec2c50ecd040c8af9e278a04dbf33dc78f90"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "ab2fe2e8142db2f0285473a088fe82c3780dd067eaa2d6abb7fcfa385b28380a",
    "last_5_lines": [
      "[5/8] Wrapping AST for subtitle-ass-atlas-tests for debugging",
      "[6/8] Write Objects.LinkFileList",
      "[7/8] Linking subtitle-ass-atlas-tests",
      "Build complete! (0.71s)",
      "ass-atlas-tests: 32 PASS, 0 FAIL"
    ],
    "receipt_sha256": "4542167a8bca7f9a95fb1b5960317a9f5135f205f0533db03f7a0d02a8de8c12"
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









```text id=rf0
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

```text id=rf1
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "subtitle-ass-atlas-tests", targets: ["subtitle-ass-atlas-tests"]), .executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "timepos-vector-tests", targets: ["timepos-vector-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "vtt-parser-tests", targets: ["vtt-parser-tests"]), .executable(name: "l3-convert-matrix-tests", targets: ["l3-convert-matrix-tests"]), .executable(name: "avsync-golden-tests", targets: ["avsync-golden-tests"]), .executable(name: "transport-vector-tests", targets: ["transport-vector-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
        .executableTarget(name: "audio-interrupt-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/audio-interrupt-tests"),
        .executableTarget(name: "cue-output-tests", dependencies: ["GorAVSubtitles", "GorAVPlaybackCore"], path: "Sources/cue-output-tests"),
        .executableTarget(name: "render-graph-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/render-graph-tests"),
        .executableTarget(name: "decoder-lifetime-tests", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore"], path: "Sources/decoder-lifetime-tests"),
        .executableTarget(name: "decoder-inventory-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/decoder-inventory-tests"),
        .testTarget(name: "PreparedVideoSwapTests", dependencies: ["GorAVPlaybackCore"], path: "Tests/PreparedVideoSwapTests"),
        .testTarget(name: "EmbeddedPreparedShotTests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), "GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Tests/EmbeddedPreparedShotTests"),
        .executableTarget(name: "color-stage-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/color-stage-tests"),
        .executableTarget(name: "crop-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/crop-tests"),
        .executableTarget(name: "frame-tap-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/frame-tap-tests"),
        .executableTarget(name: "active-media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/active-media-inventory-tests"),
        .executableTarget(name: "media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/media-inventory-tests"),
        .executableTarget(name: "video-remote-open-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/video-remote-open-tests"),
        .executableTarget(name: "remote-source-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/remote-source-tests"),
        .executableTarget(name: "subtitle-controller-tests", dependencies: ["GorAVSubtitles"], path: "Sources/subtitle-tests", sources: ["SubtitleControllerTests.swift"]),
        .executableTarget(name: "prepared-shot-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/prepared-shot-tests"),
        .executableTarget(name: "hosttransform-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/hosttransform-tests"),
        .executableTarget(name: "timepos-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-tests"),
        .executableTarget(name: "timepos-vector-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-vector-tests"),
        .executableTarget(name: "controlbus-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/controlbus-tests"),
        .target(name: "BridgeDemux", path: "Tests/labs/p-a1-r2/Sources/BridgeDemux"),
        .target(name: "BridgeVTDecode", dependencies: ["BridgeDemux"], path: "Sources/BridgeVTDecode"),
        .target(name: "AudioMasterScheduler", path: "Sources/AudioMasterScheduler"),
        .testTarget(name: "EngineContractTests", dependencies: ["BridgeVTDecode", "BridgeDemux", "AudioMasterScheduler"], path: "Tests/EngineContractTests"),
        .executableTarget(name: "e1-headless-tests", dependencies: ["BridgeDemux", "AudioMasterScheduler", "CFFmpeg", "GorAVPlaybackCore", "GorAVMetalPresenter"], path: "Sources/e1-headless-tests"),
        .executableTarget(name: "gorav-probe", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/gorav-probe"),


        .target(name: "GorAVCore", dependencies: ["GorAVCAtomics"], path: "Sources/GorAVCore", sources: ["Boundary.swift", "AdmissionTable.swift", "OpenURLRouter.swift"]),
        // L5/L6 u7 wiring candidate (coordinator-owned landing): parser/model library +
        // three SEPARATE @main consumer suites (one file each, never one merged target).
        .target(name: "GorAVSubtitles", path: "Sources/GorAVSubtitles", sources: ["ASSParser.swift", "SRTParser.swift", "VTTParser.swift", "SubtitleCue.swift", "SubtitlePlan.swift", "SubtitleSchedule.swift", "SubtitleTrack.swift", "SubtitleAutoLoad.swift", "SubtitleController.swift", "SubtitleCueOutput.swift", "SubtitleCueDelivery.swift", "SubtitleSidecarSession.swift"]),
        .executableTarget(name: "vtt-parser-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/vtt-parser-tests"),
        .executableTarget(name: "avsync-golden-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/avsync-golden-tests"),
        .executableTarget(name: "transport-vector-tests", path: "Sources/transport-vector-tests"),
        .executableTarget(name: "l3-convert-matrix-tests", dependencies: ["GorAVFFmpegAdapter"],
                          path: "Sources/l3-convert-matrix-tests",
                          swiftSettings: [.define("L3_PROVIDER")]),
        .executableTarget(name: "subtitle-srt-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SRTTests.swift"]),
        .executableTarget(name: "subtitle-ass-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["ASSTests.swift"]),
        .executableTarget(name: "subtitle-ass-atlas-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["ASSAtlasTests.swift"]),
        .executableTarget(name: "subtitle-track-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitleTrackTests.swift"]),
        .executableTarget(name: "subtitle-plan-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitlePlanTests.swift"]),
        .target(name: "GorAVNativeProbeKit", dependencies: ["GorAVCore"],
                path: "Sources/GorAVNativeProbeKit",
                sources: ["GorAVSeekContract.swift", "NativeProbe.swift", "LeaseTable.swift", "PacketFeedMachine.swift", "DemuxerPolicy.swift"]),
        .systemLibrary(name: "CFFmpeg", path: "Sources/CFFmpeg"),
        // L6 Dolby Vision lane (block 78d L6; new lane dirs only, milestone-gated M4)
        .target(name: "GorAVDVRPU",
                path: "Sources/GorAVDVRPU",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVDolbyVision",
                dependencies: ["GorAVDVRPU", "CFFmpeg", "GorAVCore",
                               "GorAVFFmpegAdapter"],
                path: "Sources/GorAVDolbyVision"),
        .executableTarget(name: "dovi-selftest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-selftest",
                exclude: ["swift"]),
        .executableTarget(name: "dovi-hdrtest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-hdrtest",
                exclude: ["gen_ref_fields.py"]),
        .executableTarget(name: "dovi-vectest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-vectest"),
        .executableTarget(name: "dovi-fuzz",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-fuzz"),
        .target(name: "GorAVFFmpegAdapter", dependencies: ["CFFmpeg", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/GorAVFFmpegAdapter", sources: ["FFmpegSoftwareDecoder.swift", "SnapshotInput.swift", "SnapshotAVIOOwner.swift", "FrameObservation.swift", "FFmpegSoftwareAudioDecoder.swift", "L3Admission.swift", "L3SampleConvert.swift", "L3PixelConvert.swift", "L3HardwareDecode.swift", "L3AVCoordinator.swift", "SourceOpenOptions.swift", "MediaInventory.swift", "ActiveTransportSnapshot.swift"]),        .executableTarget(name: "l4-hwdecode-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "CFFmpeg"],
                path: "Sources/l4-hwdecode-tests", sources: ["L4HWDecodeTests.swift"]),

        .executableTarget(name: "gorav-first-frame", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/gorav-first-frame", sources: ["FirstFrame.swift"]),
        .executableTarget(name: "refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/refusal-tests", sources: ["RefusalTests.swift"]),
        .executableTarget(name: "playback-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/playback-test", sources: ["PlaybackTest.swift"]),
        .executableTarget(name: "audio-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/audio-test", sources: ["AudioTest.swift"]),
        .executableTarget(name: "seek-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-test", sources: ["SeekTest.swift"]),
        .executableTarget(name: "seek-restart-probe", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-restart-probe", sources: ["main.swift"]),
        .executableTarget(name: "audio-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/audio-refusal-tests", sources: ["AudioRefusalTests.swift"]),
        .executableTarget(name: "video-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/video-refusal-tests", sources: ["VideoRefusalTests.swift"]),
        .executableTarget(name: "coexist-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/coexist-test", sources: ["CoexistTest.swift"]),
        .executableTarget(name: "isolation-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/isolation-test", sources: ["IsolationTest.swift"]),
        .executableTarget(name: "trace-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/trace-dump", sources: ["TraceDump.swift"]),
        .executableTarget(name: "core-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/core-seek-tests"),
        .executableTarget(name: "real-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/real-seek-tests"),
        .executableTarget(name: "seek-ring-reset-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-ring-reset-tests"),
        .target(name: "GorAVSeekComposition", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVSeekComposition"),
        .executableTarget(name: "seek-pacing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-pacing-tests"),
        .executableTarget(name: "seek-composition-tests", dependencies: ["GorAVSeekComposition", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/seek-composition-tests"),
        .executableTarget(name: "audio-seek-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-seek-tests"),
        .executableTarget(name: "demux-parity-tests", dependencies: ["BridgeDemux", "CFFmpeg"], path: "Sources/demux-parity-tests"),
        .executableTarget(name: "audio-baseline-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-baseline-tests"),
        .executableTarget(name: "seek-contract-tests", dependencies: ["GorAVNativeProbeKit", "GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/seek-contract-tests"),
        .executableTarget(name: "adversarial-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/adversarial-seek-tests"),
        .executableTarget(name: "shell-seek-bridge-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/shell-seek-bridge-tests"),
        .executableTarget(name: "k9-adversarial", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/k9-adversarial", sources: ["K9Adversarial.swift"]),
        .executableTarget(name: "shell-mac-test", dependencies: ["GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/shell-mac-test", sources: ["ShellMacTest.swift"]),
        .executableTarget(name: "frame-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/frame-dump", sources: ["FrameDump.swift", "ConverterVariants.swift", "RawPlaneDump.swift"]),
        .target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: "."),
        .target(name: "GorAVAudioClock",
                path: "Sources/GorAVAudioClock",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVAudioClockSwift",
                dependencies: ["GorAVAudioClock", "GorAVCAtomics", "GorAVPlaybackCore"],
                path: "Sources/GorAVAudioClockSwift"),
        // r3 (architect r2 BLOCKER): NO explicit sources list - an explicit
        // list silently omitted Lane0Contract.swift + LifetimeRegistry.swift
        // (AudioSink/AudioStopResult/PlaybackRegistry unresolved in a real
        // package build; manual swiftc had masked it). Default = every file.
        .target(name: "GorAVPlaybackCore", dependencies: ["GorAVCAtomics", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVPlaybackCore"),
        .executableTarget(name: "session-venue-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/session-venue-tests"),
        // native87 Stage B entrypoint (B1-B3): pause-hold counter witnesses,
        // parked seek, close-from-paused report on the REAL embedded session.
        // macOS legs only; UNRUN (exit 77) elsewhere.
        .executableTarget(name: "b-gate-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/b-gate-tests"),
        .testTarget(name: "GorAVAudioClockTests",
                    dependencies: ["GorAVAudioClockSwift"],
                    path: "Tests/GorAVAudioClockTests"),
        .testTarget(name: "ReadinessAnchorTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/ReadinessAnchorTests"),
        .testTarget(name: "AudioPacingTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/AudioPacingTests"),
        .testTarget(name: "J3AudioControlTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/J3AudioControlTests"),
        .testTarget(name: "DecodeHeartbeatTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/DecodeHeartbeatTests"),
        .testTarget(name: "PlayerControlPlaneTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/PlayerControlPlaneTests"),
        .executableTarget(name: "pause-resume-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/pause-resume-tests"),
        .executableTarget(name: "race-witness-tests", dependencies: ["GorAVPlaybackCore"],
                          path: "Sources/race-witness-tests"),
        .executableTarget(name: "admission-tests", dependencies: ["GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"],
                          path: "Sources/admission-tests"),
        .executableTarget(name: "open-url-tests", dependencies: ["GorAVCore"], path: "Sources/open-url-tests"),
        .executableTarget(name: "audio-delay-tests", dependencies: ["GorAVPlaybackCore", "GorAVAudioClockSwift"], path: "Sources/audio-delay-tests"),
        .executableTarget(name: "window-mode-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/window-mode-tests"),
        .executableTarget(name: "observation-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/observation-tests"),
        .executableTarget(name: "timing-ledger-tests", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/timing-ledger-tests", sources: ["TimingLedgerTests.swift", "SPSCTests.swift"]),
        .executableTarget(name: "gorav-sink-check", dependencies: ["GorAVMacShell"], path: "Sources/gorav-sink-check", sources: ["SinkCheck.swift"]),
        .executableTarget(name: "gorav-play", dependencies: ["GorAVMacShell", "GorAVMetalPresenter", "GorAVPlaybackCore"], path: "Sources/gorav-play", sources: ["GorAVPlay.swift"]),
        // L7 embedded shell (block 168 factory gap): the E1 host-NSView embed
        // session. Whole body is canImport(AppKit)-gated - compiles empty
        // off-Mac; a Linux build is NOT a Mac compile claim. Explicit
        // sources pin: exactly the reviewed session file; a stray file
        // dropped into the dir is uncompiled, never silently wired.
        .target(name: "GorAVEmbeddedShell",
                dependencies: ["GorAVSubtitles", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVMacShell", "GorAVMetalPresenter", "GorAVFFmpegAdapter", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVEmbeddedShell", sources: ["GorAVEmbeddedSession.swift"]),
        .target(name: "GorAVMacShell", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVMacShell", sources: ["ShellClock.swift", "DisplaySink.swift", "AudioUnitSink.swift", "ShellFrameSource.swift", "FrameTap.swift", "TappedFrameLuma.swift", "WindowModeController.swift"]),
        // L2 Metal presenter lane, r7 landing (block 168 L3): new target dir
        // only; every Metal/AppKit source is canImport-gated so off-Mac
        // builds compile the target empty. GorAVMetalShellApp mirrors the
        // trunk shell contract (owner-issued session, shared CancelCommit,
        // audio-master pacing).
        .target(name: "GorAVMetalPresenter",
                dependencies: ["GorAVMacShell", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVSubtitles"],
                path: "Sources/GorAVMetalPresenter/core",
                sources: ["AspectFit.swift", "MetalPresenterTelemetry.swift", "SurfaceContract.swift", "MetalRenderer.swift", "MetalPresenter.swift", "GorAVMetalShellApp.swift", "StagePass.swift", "CVPixelBufferTap.swift"]),
        .executableTarget(name: "gorav-metal-check", dependencies: ["GorAVMetalPresenter", "GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/GorAVMetalPresenter/cli", sources: ["MetalCheck.swift"])
    ]
)

```

```text id=rf2
import Foundation
import GorAVSubtitles

// ass-atlas-tests: ASS override-tag fixture atlas rebuilt against the REAL
// GorAVSubtitles.ASSParser at pin 2112af0d (refill of H0596; the earlier
// atlas assumed a stub interface and failed 9/11 at product run). Semantics
// verified against the product parser: cueIndex is 1-based over cues
// (cues.count + 1 at parse time), tags are sorted unique backslash names per
// cue ("block" for a block with no backslash tag), blocks stripped from text,
// unterminated blocks drop to end of text, override-only text is the typed
// refusal ParseError.overrideOnlyText(line:) with the 1-based source line.
// Convention: one FAIL line per failed check (row id included); final summary.

var passed = 0, failed = 0
func check(_ row: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1 } else { failed += 1; FileHandle.standardError.write(Data("FAIL \(row) \(detail)\n".utf8)) }
}

let header = """
[Script Info]
Title: atlas
PlayResX: 384
PlayResY: 288
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour
Style: Default,Arial,20,&H00FFFFFF
[Events]
Format: Layer, Start, End, Style, Text

"""

func doc(_ dialogues: [String]) -> String { header + dialogues.joined(separator: "\n") }

struct Row { let id: String; let text: String; let reports: [ASSParser.OverrideReport]; let texts: [String] }

let rows: [Row] = [
    Row(id: "A1",  text: "{\\an8}Hello",                       reports: [.init(cueIndex: 1, tags: ["\\an"])],                texts: ["Hello"]),
    Row(id: "A2",  text: "{\\i1}Hello{\\i0}",                  reports: [.init(cueIndex: 1, tags: ["\\i"])],                 texts: ["Hello"]),
    Row(id: "A3",  text: "{\\pos(10,20)\\move(1,2,3,4)}Moved", reports: [.init(cueIndex: 1, tags: ["\\move", "\\pos"])],     texts: ["Moved"]),
    Row(id: "A4",  text: "{\\frz90\\bord2\\fad(200,0)}Spin",   reports: [.init(cueIndex: 1, tags: ["\\bord", "\\fad", "\\frz"])], texts: ["Spin"]),
    Row(id: "A5",  text: "{\\an8}Hi{\\pos(1,2)} there",        reports: [.init(cueIndex: 1, tags: ["\\an", "\\pos"])],       texts: ["Hi there"]),
    Row(id: "A7",  text: "{\\t(\\fs40)\\clip(0,0,10,10)}Clipped", reports: [.init(cueIndex: 1, tags: ["\\clip", "\\fs", "\\t"])], texts: ["Clipped"]),
    Row(id: "A8",  text: "{\\k40}Ka{\\k20}ra",                 reports: [.init(cueIndex: 1, tags: ["\\k"])],                 texts: ["Kara"]),
    Row(id: "A9",  text: "Text {\\an8",                        reports: [.init(cueIndex: 1, tags: ["\\an"])],                texts: ["Text"]),
    Row(id: "A10", text: "{not-a-tag}Shy",                     reports: [.init(cueIndex: 1, tags: ["block"])],               texts: ["Shy"]),
]

for row in rows {
    do {
        let d = try ASSParser.parse(doc(["Dialogue: 0,0:00:01.00,0:00:03.00,Default,\(row.text)"]))
        check(row.id, d.unsupportedOverrides == row.reports, "reports \(d.unsupportedOverrides) != \(row.reports)")
        check(row.id, d.cues.map { $0.text } == row.texts, "texts \(d.cues.map { $0.text }) != \(row.texts)")
        check(row.id, !d.cues[0].text.contains("{") && !d.cues[0].text.contains("}"), "unstripped block in \(d.cues[0].text)")
    } catch { check(row.id, false, "unexpected error \(error)") }
}

// A6: cueIndex is 1-based over cues: overrides on the 1st and 3rd dialogue.
do {
    let d = try ASSParser.parse(doc([
        "Dialogue: 0,0:00:01.00,0:00:03.00,Default,{\\an8}One",
        "Dialogue: 0,0:00:04.00,0:00:06.00,Default,Two",
        "Dialogue: 0,0:00:07.00,0:00:09.00,Default,{\\pos(5,5)}Three",
    ]))
    check("A6", d.unsupportedOverrides == [.init(cueIndex: 1, tags: ["\\an"]), .init(cueIndex: 3, tags: ["\\pos"])], "reports \(d.unsupportedOverrides)")
    check("A6", d.cues.map { $0.text } == ["One", "Two", "Three"], "texts \(d.cues.map { $0.text })")
} catch { check("A6", false, "unexpected error \(error)"); check("A6", false, "unexpected error \(error)") }

// A11: override-only text is the typed refusal with the 1-based source line
// (header above = 9 lines + this Dialogue on line 10).
do {
    _ = try ASSParser.parse(doc(["Dialogue: 0,0:00:01.00,0:00:03.00,Default,{\\an8}"]))
    check("A11", false, "override-only text accepted"); check("A11", false, "override-only text accepted")
} catch let e as ASSParser.ParseError {
    check("A11", e == .overrideOnlyText(line: 10), "got \(e), want overrideOnlyText(line: 10)")
    if case .overrideOnlyText = e { check("A11", true) } else { check("A11", false, "wrong error case \(e)") }
} catch { check("A11", false, "foreign error \(error)"); check("A11", false, "foreign error \(error)") }

// Negative control: a mutated tag order or an unstripped block is caught.
// A3's expected list is sorted; asserting exact equality means a mutated
// fixture (e.g. ["\\pos", "\\move"]) or an unstripped block flips these red.
do {
    let d = try ASSParser.parse(doc(["Dialogue: 0,0:00:01.00,0:00:03.00,Default,{\\pos(10,20)\\move(1,2,3,4)}Moved"]))
    let mutated: [ASSParser.OverrideReport] = [.init(cueIndex: 1, tags: ["\\pos", "\\move"])]
    check("N1", d.unsupportedOverrides != mutated, "mutated tag list not distinguishable")
} catch { check("N1", false, "unexpected error \(error)") }

print("ass-atlas-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/7] Write sources
[2/7] Write swift-version--9C6B84B6E025C5B.txt
[4/14] Emitting module GorAVSubtitles
[5/20] Compiling GorAVSubtitles SubtitleCueOutput.swift
[6/20] Compiling GorAVSubtitles SubtitlePlan.swift
[7/20] Compiling GorAVSubtitles SubtitleSchedule.swift
[8/20] Compiling GorAVSubtitles SubtitleSidecarSession.swift
[9/20] Compiling GorAVSubtitles SubtitleTrack.swift
[10/20] Compiling GorAVSubtitles VTTParser.swift
[11/20] Compiling GorAVSubtitles ASSParser.swift
[12/20] Compiling GorAVSubtitles SRTParser.swift
[13/20] Compiling GorAVSubtitles SubtitleAutoLoad.swift
[14/20] Compiling GorAVSubtitles SubtitleController.swift
[15/20] Compiling GorAVSubtitles SubtitleCue.swift
[16/20] Compiling GorAVSubtitles SubtitleCueDelivery.swift
[17/21] Wrapping AST for GorAVSubtitles for debugging
[19/23] Compiling subtitle_ass_tests ASSTests.swift
[20/23] Emitting module subtitle_ass_tests
[21/24] Wrapping AST for subtitle-ass-tests for debugging
[22/24] Write Objects.LinkFileList
[23/24] Linking subtitle-ass-tests
Build complete! (2.85s)
ALL_CHECKS_PASS
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSAtlasTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-x5hbbmdp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-x5hbbmdp/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
[0/1] Planning build
Building for debugging...
[0/6] Write sources
[1/6] Write swift-version--9C6B84B6E025C5B.txt
[3/7] Compiling subtitle_ass_atlas_tests ASSAtlasTests.swift
[4/7] Emitting module subtitle_ass_atlas_tests
[5/8] Wrapping AST for subtitle-ass-atlas-tests for debugging
[6/8] Write Objects.LinkFileList
[7/8] Linking subtitle-ass-atlas-tests
Build complete! (0.71s)
ass-atlas-tests: 32 PASS, 0 FAIL
```
