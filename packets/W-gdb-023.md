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
