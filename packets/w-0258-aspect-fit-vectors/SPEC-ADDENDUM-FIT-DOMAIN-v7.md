# Fit-domain addendum (project ruling, v7 FINAL) - 2026-11-01
Scope: source and cases only. No opening-policy change, no bounds-floor change,
no Mac claims. Supersedes the float-derived expected value of one reference
cell (correction record 00-CORRECTION-20261101-0508-27e68893).

## Ruling
The contain-fit function maps to the integer grid with floor rounding and
preserved aspect. Its valid domain is exactly the inputs where BOTH fitted
sides floor to >= 1 whole point.

- Inside the domain: `.ok(w, h)`.
- Outside it (a free side scales below 1pt): a TYPED refusal
  `.unrepresentable(limitingAxis, trueScaledSize)`. A 100000x1 content in
  2048x1170 scales to 2048x0.02048: no aspect-true integer window exists
  (an exact aspect-true pair would need availW >= 100000). Returning
  2048x1 via a min-1 floor silently distorts the aspect ~49x and conflicts
  with the >=1-each invariant. The typed refusal is the answer, not a
  distorted rect.
- A min-1 (or any) fallback floor is allowed ONLY as a caller-selected,
  declared policy with an explicit receipt. No caller in scope needs one.

## Exact arithmetic: true Int64 (no epsilon, floor rule unchanged)
Never materialize the scale factor s and re-multiply: the exact-fit boundary
then lands one point short (1350 * fl(79/135) = 789.9999999999999 -> 789;
this is what produced the corrected cell). The rule runs in INTEGER
arithmetic under an explicit contract:

- Integer domain: video and avail sizes are whole points/pixels with
  0 < size <= Int32.max (products stay <= 2^62 < Int64.max, so no overflow
  inside the domain; origins may be negative within the same magnitude).
- Conversion policy: floating-point call sites FLOOR each input at the
  boundary before the integer rule runs. Sub-point precision is outside
  this contract (video dims are whole pixels; screen frames whole points in
  practice; the conversion matches the old float pipeline to <1pt).
- Exact rule: constrained axis assigned from avail directly; free axis =
  exact rational floor(freeVideo * availDim / videoDim) in Int64. Axis
  choice by Int64 cross-multiplied compare. No epsilon, no tolerance.
- Results: .ok(rect) | .unrepresentable(limitingAxis, trueScaledSize)
  | .outOfIntegerDomain (typed, never a trap and never a silent floor).
- Resize lock (separate, order preserved): the same integer treatment, and
  because the projected pair lies on the video ray the drag dimension
  cancels in the composed shrink ratio, so the bound is also ONE exact
  Int64 division (floor(availH * videoW / videoH)); the derivation order
  (bounded drag axis first, other axis derived from the floored width) is
  byte-identical to the old pipeline.
- The sqrt opening chooser (proposedOpenSize) is an independent float
  POLICY layer - unchanged.

## Cases
- 100000x1 @ 2048x1170  -> unrepresentable(height, scaled 0.02048)
- 1x100000 @ 2048x1170  -> unrepresentable(width, scaled 0.0117)
- 4096x1   @ 2048x1170  -> unrepresentable(height, scaled 0.5)  (floor boundary)
- 2048x1   @ 2048x1170  -> ok(2048x1)                           (exactly 1.0 stays)
- 1x1000   @ 2048x819   -> unrepresentable(width, scaled 0.819) (old reference
                            shipped 1x819 via the floor; that is the distortion
                            class this ruling removes)
- Zero-size video or avail: degenerate, empty rect at avail origin (unchanged).

## Reference table
The 18-cell table in the correction record stands as exact-rational expected
values, with cell 1080x1350 @ (0,0,1440,790) corrected to (404,0,632,790).
The prior "18 PASS" is withdrawn as exact proof (it was float
self-consistency); 17/18 cells were and remain identical.

## Relation to the gor production pipeline (514 v7)
Extreme-refusal policy unchanged; actual fitted pixels corrected for
off-by-one boundary losses. The reviewer's independent v5-compare (2016
cases) found 7 true boundary losses, so "all production behavior unchanged"
would be false: the refusal policy is unchanged, while those boundary cells
now fit one point larger (the exact-rational value). The backend minimum
window (mpv Cocoa minSize 160x90; its setFrame rejects smaller frames)
refuses every sub-90pt result long before the integer-grid boundary is
reached, and opening()/lockedResize() already type that as no-legal-set
(zero rect / untouched window). The typed refusal at the grid boundary is
the same convention, one layer down. The resize-lock derivation order
(drag axis bounded, other axis derived from the floored width) is
preserved, so settled sizes are byte-identical except the true
boundary-loss cells.

## Regression cells delivered (Linux harness, section 12)
The full 18-cell exact table with literal expectations; the five
typed-domain cases above; fit()->zero-rect mapping; opening() refusal
propagation for a sliver video; and a resize-lock bind cell proving the
exact 632x790 where the materialized-scale form shipped 631x788.
Harness: ALL PASS, sections 1-12 incl. integer-domain enforcement cells
(out-of-domain typed, fractional floor conversion, sub-1pt no-op, 2^31-1
edge exact).

## Reviewer evidence (architect, 05:15:02, independent runs)
- 29,029 independent rational cases: 0 mismatches.
- 4,536 invariant cases: 0 violations.
- 2016 v5-compare cases: 7 true boundary losses (the corrected off-by-ones
  named above); everything else identical.
- Reviewer-measured pins matched the writer's pins byte-for-byte.

## Final pins (v7)
- GorVideoFit.swift : 213cc50476b7a181000fec4b8028b6c1b9602854d7e4ce54990ae2fb54bfa78a
- harness main.swift : ae255101667e43267e8c29041c7acaec61f5996bc397bd0ab838a66ddfccc3b8
- test-output7.txt : 0856ac793c87304520cae695b4471c36f8f4ad186219b18fcca27eed6877f9d7
- this addendum : (self-hash omitted; see bundle HASHES)
- bundle v7 tar.gz : recorded in the delivery report (a tar
  cannot embed its own hash); verify every member against HASHES.txt
(v6 tar was the float-fused intermediate - SUPERSEDED; do not reference it
as current. v5 bundles remain frozen history.)
Mac: UNRUN. Installed-build baseline gap unchanged; owner Mac run is the
only Mac proof. Linux harness only, writer's toolchain.
