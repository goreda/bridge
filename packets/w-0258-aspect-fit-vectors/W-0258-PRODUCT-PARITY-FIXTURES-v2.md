# W-0258 - product-parity fixtures (v2) - 2026-11-01

NEW product-parity fixtures derived from the PINNED product source:
GorVideoFit.swift sha256 213cc50476b7a181000fec4b8028b6c1b9602854d7e4ce54990ae2fb54bfa78a (16848 B).
This is a DISTINCT artifact from the lost original review harness; it does
not recreate, retar or re-execute it. STATUS: AUTHORED by static derivation
from the pinned bytes - NOT executed; no runtime claim.
v2 supersedes v1 (da018cb8...2692): adds F15 and the two-guard-level
distinction (wrapper degenerate = RAW origin; core degenerate = FLOORED
origin). v1's blanket "degenerate -> raw origin" was imprecise.

Notation: fit() is the production-observable surface (rect); the typed
containFit() result is listed where it differs in kind. "empty@(x,y)" =
.ok((x, y, 0, 0)). Refusals map through fit() to (avail.x, avail.y, 0, 0)
using the avail origin AS PASSED (fit()'s refusal branch, lines 169-171).

| #  | Class                        | video w x h     | avail (x, y, w, h)        | typed containFit()                              | fit() observable            |
|----|------------------------------|-----------------|---------------------------|--------------------------------------------------|-----------------------------|
| F1 | positive path, floor inputs  | 1080.7 x 1350.2 | (0.6, 0.2, 1440.9, 790.4) | .ok((404, 0, 632, 790))                          | (404, 0, 632, 790)          |
| F2 | negative fractional origin   | 101 x 50        | (-0.7, -0.2, 2048, 1170)  | .ok((972, 559, 101, 50))                         | (972, 559, 101, 50)         |
| F3 | odd-delta integer centering  | 101 x 50        | (0, 0, 2048, 1170)        | .ok((973, 560, 101, 50))                         | (973, 560, 101, 50)         |
| F4 | zero video side (lab P10)    | 0 x 100         | (5, 7, 2048, 1170)        | .ok empty@(5,7)   [wrapper guard, raw origin]    | (5, 7, 0, 0)                |
| F5 | zero avail side (lab P11)    | 100 x 100       | (5, 7, 0, 1170)           | .ok empty@(5,7)   [wrapper guard, raw origin]    | (5, 7, 0, 0)                |
| F6 | negative video side (lab P12)| -3 x 100        | (5, 7, 2048, 1170)        | .ok empty@(5,7)  [CONFLICT: lab = typed refusal] | (5, 7, 0, 0)                |
| F7 | NaN video side               | NaN x 100       | (5, 7, 2048, 1170)        | .ok empty@(5,7)  [wrapper guard; lab: no case]   | (5, 7, 0, 0)                |
| F8 | mixed zero + negative        | 0 x -3          | (5, 7, 2048, 1170)        | .ok empty@(5,7)  [single conjunction; no order]  | (5, 7, 0, 0)                |
| F9 | degenerate raw origin        | 0 x 100         | (5.5, 7.25, 2048, 1170)   | .ok empty@(5.5,7.25) RAW, unfloored [wrapper]    | (5.5, 7.25, 0, 0)           |
| F10| over Int32.max (lab P13)     | 2147483648 x 100| (0, 0, 2048, 1170)        | .outOfIntegerDomain (payloadless)                | (0, 0, 0, 0)                |
| F11| unrepresentable height       | 100000 x 1      | (0, 0, 2048, 1170)        | .unrepresentable("height", ~64/3125 = 0.02048)   | (0, 0, 0, 0)                |
| F12| unrepresentable width        | 1 x 100000      | (0, 0, 2048, 1170)        | .unrepresentable("width", ~117/10000 = 0.0117)   | (0, 0, 0, 0)                |
| F13| floor boundary (sub-1pt)     | 4096 x 1        | (0, 0, 2048, 1170)        | .unrepresentable("height", 0.5)                  | (0, 0, 0, 0)                |
| F14| exact 1.0 stays              | 2048 x 1        | (0, 0, 2048, 1170)        | .ok((0, 584, 2048, 1))                           | (0, 584, 2048, 1)           |
| F15| positive sub-1pt -> CORE     | 0.4 x 100       | (5.5, 7.25, 2048, 1170)   | .ok empty@(5,7) FLOORED origin [core guard]      | (5, 7, 0, 0)                |

Derivation notes (each row hand-derived from the pinned source):
- F1: floor all six inputs -> 1080x1350 in (0,0,1440,790); height-constrained:
  cw = floor(1080*790/1350) = 632 exact (632*1350 = 853200; the corrected
  reference cell); cx = (1440-632)/2 = 404.
- F2: floor(-0.7) = -1, floor(-0.2) = -1; no upscale; cx = -1 + (2048-101)/2
  = -1 + 973 = 972; cy = -1 + (1170-50)/2 = 559. Shows: negative origins are
  in-domain and the boundary floor is a true floor, not truncation.
- F3: no upscale (101 <= 2048, 50 <= 1170); cx = 1947/2 = 973 (Int64), cy =
  1120/2 = 560. Integer centering, no fractional intermediate.
- F4-F9: the WRAPPER degenerate conjunction (any size non-positive or NaN as
  passed) -> empty at the avail origin AS PASSED; F9 shows the raw-origin
  exception (origin NOT floored on this path).
- F15: 0.4 > 0 passes the wrapper; floors to 0 at conversion; the CORE guard
  (vw > 0) returns the empty rect at the FLOORED avail origin (5, 7) - the
  second degenerate level, distinct from F9.
- F10: 2147483648 > Int32.max (2147483647) -> payloadless typed refusal.
- F11: cw = 2048 assigned; ch = floor(1*2048/100000) = 0 -> refusal. Payload
  is the nearest Double to 2048/100000 = 64/3125 (semantic, not byte-exact).
- F12: ch = 1170 assigned; cw = floor(1*1170/100000) = 0 -> refusal. Payload
  is the nearest Double to 1170/100000 = 0.0117.
- F13: cw = 2048 assigned; ch = floor(1*2048/4096) = 0 -> refusal; the exact
  scaled size 0.5 is below the 1 pt integer grid.
- F14: no upscale (2048 <= 2048, 1 <= 1170); exactly-1.0 stays 1; cy =
  (1170-1)/2 = 584.

Historical freeze (sha256 18206bb5edb18782aa26f4ad213ddf8bdda906bd7281657782df2b612b768ea8)
is preserved unchanged; F6 is the recorded reference-versus-product conflict
and is intentionally kept visible rather than reconciled by edit.
