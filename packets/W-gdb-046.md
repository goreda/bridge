# W-gdb-046 195b-B1 PGS bitmap subtitles: consuming pin
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-046

```packet-json
{
 "packet_id": "W-gdb-046",
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
  "signatures": "pinned anchor: SubtitleCue { index, startSeconds, endSeconds, lines, styleName?, contains(seconds:) }; additive: PGSBitmapCue { index, startSeconds, endSeconds, width, height, palette: [RGBA], pixels: [UInt8] }",
  "types": "palette entry = 4 x UInt8 RGBA; pixels = one palette index per pixel, row-major; timing Double seconds, contains(seconds:) half-open per the pinned text cue rule",
  "ownership_lifetime": "each cue owns its decoded pixel buffer; cues immutable; no shared mutable palette state",
  "caller": "subtitle rendering seam (controller), additive",
  "callee": "the lab PGS parser producing [PGSBitmapCue]"
 },
 "test": {
  "command": "python3 kits/b1-pgs-pin/check.py kits/b1-pgs-pin/fixtures.json",
  "expected": "exit 0; stdout 'b1-pgs-pin: 3/3 cues PASS'; truncated segment row is a typed refusal, never a partial bitmap",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVSubtitles/",
   "kits/b1-pgs-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
PGS subtitles (195b-B1) are bitmap; the pinned SubtitleCue is text-only, so without an additive pinned shape a lab parser cannot deliver cues the controller can time.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0281/B1; the lab module implements against the pinned interface below.

## expected behaviour
an additive PGSBitmapCue type aligned with the pinned SubtitleCue timing contract: index: Int, startSeconds: Double, endSeconds: Double (contains(seconds:) semantics identical), plus width/height: Int, palette: [(r,g,b,a) UInt8 x4], pixels: [UInt8] palette indices fully RLE-decoded; ownership: each cue owns its pixel buffer; lifetime: cue values are immutable; the lab PGS parser produces [PGSBitmapCue] from a .sup stream; malformed segments degrade to typed refusal rows, never partial bitmaps.

## exact call site and interface
SubtitleCue.swift (pinned excerpt) is the timing/shape anchor; PGSBitmapCue is additive next to it in Sources/GorAVSubtitles/; the composition target stays the subtitle controller seam (SubtitleController, sha256 7695cee4, text-only at this pin - bitmap rendering is a later additive seam, not this packet).

## behaviour that must not change
SubtitleCue and the controller's text path are untouched; the additive type is new, no existing field changes.

## acceptance test (from the product repo)
python3 kits/b1-pgs-pin/check.py kits/b1-pgs-pin/fixtures.json exits 0; fixture cues match golden decoded bitmaps and timing; a truncated segment yields its typed refusal row.

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
[{"cue": "bitmap 720x576, 4-color palette", "expect": "additive PGSBitmapCue row with RLE-decoded indices; timing via contains(seconds:)"}, {"cue": "palette alpha 0 entry", "expect": "transparent pixels stay transparent; palette entries RGBA"}, {"cue": "truncated segment", "expect": "typed parse refusal row, never a partial bitmap"}]
```
