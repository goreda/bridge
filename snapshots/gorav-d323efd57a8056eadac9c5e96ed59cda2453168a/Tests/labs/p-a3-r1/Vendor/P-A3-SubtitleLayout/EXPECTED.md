# P-A3 expected parse and layout tables

Hand-computed from SPEC.md rules. Layout uses the fixed cell 10 x 20, 5%
safe area, viewport 384 x 288 unless noted. Safe area: left 19.2, top 14.4,
width 345.6, height 259.2 (bottom edge 273.6, right edge 364.8).
Tests assert these constants with accuracy 1e-9.

## Parse: basic.srt
| cue | start | end | text  | track |
|-----|-------|-----|-------|-------|
| 0   | 0.0   | 1.0 | hello | 0     |
| 1   | 1.0   | 2.0 | world | 0     |

## Parse: overlap.srt
| cue | start | end | text   | track |
|-----|-------|-----|--------|-------|
| 0   | 0.0   | 1.0 | hello  | 0     |
| 1   | 0.5   | 1.5 | second | 0     |
| 2   | 1.0   | 2.0 | world  | 0     |

active(): t=0 -> [0]; t=0.25 -> [0]; t=0.5 -> [0,1]; t=0.75 -> [0,1];
t=1.0 -> [1,2]; t=1.5 -> [2]; t=2.0 -> []; t=-1 -> [].

## Parse: unicode.srt
| cue | start | end | text (round-trips)          | graphemes |
|-----|-------|-----|-----------------------------|-----------|
| 0   | 0.0   | 1.0 | "I U+0131 SPACE U+0130 i"   | 5         |
| 1   | 1.0   | 2.0 | "cafe U+0301 ... nai U+0308 ve" | 10    |

## Parse: basic.ass (PlayResX 384, PlayResY 288)
| cue | start | end | text                                | track |
|-----|-------|-----|-------------------------------------|-------|
| 0   | 0.0   | 1.0 | hello                               | 0     |
| 1   | 1.0   | 2.0 | "world, with commas\nsecond line"   | 0     |

## Parse: alignment.ass (PlayResX 384, PlayResY 288)
| cue | start | end | text          | track | anchor |
|-----|-------|-----|---------------|-------|--------|
| 0   | 0.0   | 1.0 | bottom left   | 0     | an1    |
| 1   | 0.0   | 1.0 | middle center | 0     | an5    |
| 2   | 0.0   | 1.0 | top right     | 0     | an9    |

## Parse: invalid.srt
Throws `SubtitleParseError.malformedTimeRange` carrying the line
`00:00:AA,000 --> 00:00:01,000`.

## Layout: basic.srt, active [0]
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 167.0 | 253.6 | 50    | 20     |

## Layout: overlap.srt at t=0.75, active [0,1] (bottom anchors stack upward)
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 167.0 | 253.6 | 50    | 20     |
| 1   | 162.0 | 233.6 | 60    | 20     |

## Layout: basic.ass, active [1] (18-char longest line, 2 lines)
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 1   | 102.0 | 233.6 | 180   | 40     |

## Layout: basic.ass, active [0], viewport 768 x 576 (2x PlayRes)
Cell scales to 20 x 40; safe area left 38.4, top 28.8, width 691.2,
height 518.4.
| cue | x     | y     | width | height |
|-----|-------|-------|-------|--------|
| 0   | 334.0 | 507.2 | 100   | 40     |

## Layout: alignment.ass, active [0,1,2]
| cue | anchor | x     | y     | width | height |
|-----|--------|-------|-------|-------|--------|
| 0   | an1    | 19.2  | 253.6 | 110   | 20     |
| 1   | an5    | 127.0 | 134.0 | 130   | 20     |
| 2   | an9    | 274.8 | 14.4  | 90    | 20     |
