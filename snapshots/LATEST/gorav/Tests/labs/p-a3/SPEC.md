# P-A3 Specification: SRT/ASS parsing and deterministic fixed-cell layout

Packet: P-A3 | E3 | lab-a (goreda/bridge GROUP-INBOX.md). Clean-room
implementation. No renderer, no Metal/UI work, no font measurement anywhere.

## Public contract

```swift
public struct Cue: Sendable { public let start: Double; public let end: Double; public let text: String; public let track: Int }
public struct CueBox: Sendable { public let cue: Int; public let x: Double; public let y: Double; public let width: Double; public let height: Double }
public protocol SubtitleLayout {
    func parse(text: String, format: String) throws -> [Cue]
    func active(cues: [Cue], at seconds: Double) -> [Int]
    func layout(cues: [Cue], active: [Int], viewportWidth: Double, viewportHeight: Double) throws -> [CueBox]
}
```

Implementation: `FixedCellSubtitleLayout` (Foundation only). Public inits are
added to `Cue`/`CueBox` (memberwise inits are internal in Swift); this does
not change the contract's stored properties.

## Parsing

- `format` is case-insensitive; `"srt"` and `"ass"`/`"ssa"` are accepted,
  anything else throws `SubtitleParseError.unsupportedFormat`.
- Line endings are normalized (`\r\n` / `\r` -> `\n`).

### SRT
- Blocks are separated by blank lines. Block grammar: integer sequence line,
  timing line, one or more text lines. Text lines are joined with `\n`.
- Timestamp grammar: `HH:MM:SS,mmm --> HH:MM:SS,mmm`; hours may exceed two
  digits, minutes and seconds must be two digits and < 60, milliseconds
  exactly three digits.
- `track` is 0 for every SRT cue.

### ASS
- `[Script Info]`: `PlayResX` / `PlayResY` are recorded when present.
- `[Events]`: the `Format:` line defines the column order; `Dialogue:` lines
  are split into exactly that many fields, so the `Text` field keeps its
  commas verbatim.
- Timestamp grammar: `H:MM:SS.cc` (centiseconds); minutes/seconds < 60.
- `track` is the integer `Layer` column (0 when absent or non-integer).
- Override blocks `{...}` are removed from the text; the first `\anN`
  (N in 1...9) inside them sets the cue anchor (default: `\an2`
  bottom-center). `\N` and `\n` become real newlines.

### Errors (all named)
- `SubtitleParseError.malformedTimeRange(String)`: bad timestamp, bad timing
  line, or `end <= start`. Carries the offending line.
- `SubtitleParseError.malformedCue(String)`: structurally broken block/line.
- `SubtitleParseError.emptyInput`: no parseable cue content.
- `SubtitleLayoutError.invalidViewport`, `.invalidCellSize`: non-finite or
  non-positive geometry inputs.

## Active cues

Half-open intervals: cue `i` is active at `t` when `start <= t < end`.
`active` returns every matching index in cue order, preserving overlap.

## Layout

- Coordinate system: origin at the viewport top-left, y grows downward.
- Safe area: inset by `safeAreaFraction` (default 5%) on every side.
- Fixed cell, no font measurement: every grapheme cluster occupies one cell
  (`cellWidth` x `cellHeight`, default 10 x 20 as supplied for tests), each
  text line occupies one cell height. Combining marks do not add cells.
- Box size: `min(longestLineCells * cellWidth, safeWidth)` x
  `min(lineCount * cellHeight, safeHeight)`; always finite and non-negative.
- Anchor position inside the safe area: horizontal left/center/right and
  vertical top/middle/bottom follow the ASS numpad anchor
  (`\an1` = bottom-left, `\an5` = middle-center, `\an9` = top-right).
- PlayRes scaling: when the last parse was ASS with explicit
  `PlayResX`/`PlayResY`, cell sizes scale by `viewport / PlayRes` before
  measuring; positions follow the scaled cells. SRT cues use scale 1.
- Stacking: cues sharing one anchor stack away from the anchor edge in
  active order (bottom anchors upward, middle/top anchors downward), so
  overlapping cues never share a box. Boxes are clamped into the viewport.
- Layout metadata (anchor, PlayRes) comes from the most recent `parse` call
  on the instance; a foreign cue array falls back to bottom-center, scale 1.

## Fixtures (literal files under Tests/SubtitleLayoutTests/Fixtures)

- `basic.srt`: cues [0,1) "hello", [1,2) "world".
- `overlap.srt`: adds [0.5,1.5) "second".
- `unicode.srt`: Turkish dotted/dotless i (`Iı İi`) and combining accents
  (`café naïve`).
- `basic.ass`: PlayResX 384 / PlayResY 288; Dialogue text with commas and a
  `\N` hard break.
- `alignment.ass`: `\an1`, `\an5`, `\an9` dialogues with explicit PlayRes.
- `invalid.srt`: malformed time range (`00:00:AA,000 --> ...`).

Expected parse and layout tables: EXPECTED.md.
