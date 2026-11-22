# P-A3-R1 expected tables

Hand-computed from P-A3 SPEC.md rules. Fixed cell 10 x 20, 5% safe area.
Viewport 384 x 288 safe area: left 19.2, top 14.4, width 345.6,
height 259.2. Viewport 768 x 576 safe area: left 38.4, top 28.8,
width 691.2, height 518.4. Tests assert with accuracy 1e-9.

## Cross-parse anchor metadata dropped (same instance)
Parse alignment.ass, then basic.srt on the same instance; lay out the
alignment.ass cues. Anchors from the earlier parse must not apply;
"bottom left" (11 graphemes) falls to default bottom-center.
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 137.0 | 253.6 | 110   | 20     |

## Cross-parse PlayRes scaling dropped (same instance)
Parse basic.ass (PlayRes 384x288), then basic.srt; lay out the SRT cues at
viewport 768 x 576. Scale must be 1, not 2x.
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 359.0 | 527.2 | 50    | 20     |

## Separate-instance metadata isolation
Instance A parses alignment.ass; fresh instance B lays out A's cues.
Same default as the cross-parse case.
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 137.0 | 253.6 | 110   | 20     |

## Owning-instance control (metadata works when it should)
Same numbers as the P-A3 alignment.ass layout table.
| cue | anchor | x     | y     | width | height |
|-----|--------|-------|-------|-------|--------|
| 0   | an1    | 19.2  | 253.6 | 110   | 20     |
| 1   | an5    | 127.0 | 134.0 | 130   | 20     |
| 2   | an9    | 274.8 | 14.4  | 90    | 20     |

## Foreign (hand-built) cue array
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 167.0 | 253.6 | 50    | 20     |

## Base-engine silent fallback on nonfinite PlayRes (contrast pin)
P-A3 FixedCellSubtitleLayout parses nonfinite-playres.ass without throwing
and lays out "hello" at scale 1.
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 167.0 | 253.6 | 50    | 20     |

## Named-error expectations
| input                                              | error |
|----------------------------------------------------|-------|
| cellWidth .nan / cellHeight .infinity              | SubtitleConfigError.nonFiniteCellSize |
| cellWidth 0 / cellHeight -20                       | SubtitleConfigError.nonPositiveCellSize |
| safeAreaFraction nan / +inf / -inf                 | SubtitleConfigError.nonFiniteSafeAreaFraction |
| safeAreaFraction 0.5 / 0.9 / -0.1                  | SubtitleConfigError.outOfRangeSafeAreaFraction |
| PlayResX: nan (raw "nan", rawY "288")              | SubtitleConfigError.nonFinitePlayRes |
| PlayResX: 0 (raw "0", rawY "288")                  | SubtitleConfigError.nonPositivePlayRes |
