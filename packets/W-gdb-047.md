# W-gdb-047 195b-B2 VobSub subtitles: consuming pin
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-047

```packet-json
{
 "packet_id": "W-gdb-047",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "pinned anchor: SubtitleCue timing contract; additive shared bitmap cue (W-gdb-046 shape) + VobSub fields { paletteSource: idx-sidecar, forced: Bool, x, y, strideBytes }",
  "types": "idx palette 16 x RGBA UInt8; pixels row-major indices; timing Double seconds",
  "ownership_lifetime": "cue owns its pixels; palette copied per cue from the sidecar; no aliasing",
  "caller": "subtitle rendering seam (controller), additive",
  "callee": "the lab VobSub decoder producing bitmap cue rows"
 },
 "test": {
  "command": "python3 kits/b2-vobsub-pin/check.py kits/b2-vobsub-pin/fixtures.json",
  "expected": "exit 0; stdout 'b2-vobsub-pin: 3/3 rows PASS'; missing idx palette refuses typed; truncated control sequence refuses typed",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVSubtitles/",
   "kits/b2-vobsub-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
VobSub subtitles (195b-B2) share the PGS bitmap problem plus an .idx palette/placement sidecar; without the pinned shape a decoder invents palette or placement.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0282/B2; the lab module implements against the pinned interface below.

## expected behaviour
a VobSub decoder producing the same additive bitmap-cue shape as the PGS pin (W-gdb-046): timing per the pinned SubtitleCue contract; palette comes from the .idx sidecar (16 RGBA entries) and is never defaulted; placement/stride/alignment fields are explicit on the cue; the forced-display flag is carried typed; malformed control sequences degrade to typed refusal rows.

## exact call site and interface
SubtitleCue.swift (pinned excerpt) is the timing anchor; the additive bitmap cue type is shared with W-gdb-046 (one type, both parsers); delivery under Sources/GorAVSubtitles/ + kits/b2-vobsub-pin/.

## behaviour that must not change
SubtitleCue untouched; no palette invention: missing .idx palette is a typed refusal, not a default.

## acceptance test (from the product repo)
python3 kits/b2-vobsub-pin/check.py kits/b2-vobsub-pin/fixtures.json exits 0; golden .idx/.sub pairs match their decoded cue rows; truncated control sequences refuse typed.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSubtitles/SubtitleCue.swift (sha256 2311ed30, lines 1-32 of 32)
```swift id=source1
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
solver lab: in2tinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"stream": "idx palette 16 entries + one sub", "expect": "bitmap cue rows; palette from .idx, never invented"}, {"stream": "forced display flag set", "expect": "forced flag carried on the cue row"}, {"stream": "control sequence truncated", "expect": "typed refusal row, no partial cue"}]
```
