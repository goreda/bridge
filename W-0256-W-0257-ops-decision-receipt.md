# W-0257 / W-0256 Ops decision receipt (2026-11-01)

Decided by: gdb, delegated Q1-Q5 interface decision owner (owner block 168 scope).
Scope: subtitle layout unit (Q5) and cue-selection unit (Q4) decisions only. UNIT-ONLY acceptance: the Q4 selector unit (sha256 6756c76bb35d215ce28454a11fcf48ee24b5e69fd676ba8b94f2eef246b80b86) is accepted as a unit; the Q5 layout unit is accepted as an UNCHANGED candidate unit. Blinding of the reviewer freeze remains unproven; acceptance rests on independent execution over pinned bytes. No Mac, native, or product-adoption claim is made or implied. Remaining: producer/shim callsite readback when the provider lands, host-integration cycle, owner acceptance.

## Source pins
- SubtitleLayout.swift sha256 1b8cc11047c38d3c4faee047b471991ea1524e18784080eaa015655390fda42f
- AspectFit.swift sha256 f677d4fa45f25af0ea127613524025507c62a5b02e9df7720305b6c4b3a17266
- Packet venue main sha256 4479c28a9b4508d6150ccec0f74e05da3866f7f4c38bad4c9359b9c1e4637a6d
- Blind suite sha256 af8a992bd20c8793a4d9a29e4eaa4cf9fb2f250ed935d5f1fe220292a28cc208
- Solver readback archive sha256 1268813aa0f21c3dfcd70a96a8e1b586819de5274834f86e24538d4a1d8256c0 (18266 B)
- Q4 selector unit SubtitleCueSelection.swift sha256 6756c76bb35d215ce28454a11fcf48ee24b5e69fd676ba8b94f2eef246b80b86

## Independent execution (our venue, Linux Swift 5.10.1, exact pinned bytes)
- Packet venue: 6/6 PASS, exit 0.
- Blind suite: 26/26 PASS, exit 0, incl. BF-22 fuzz (1780 checked, 220 degenerate-nil, 1569 pulled, 1 FP-noise pull, 0 failures).
- Q4 selector: 9/9 venue, 21/21 adversarial incl. 200k fuzz, negative control exactly 1 expected FAIL; optional solver extra 19/19.

## Decisions
1. Silent unscaled on drawableHeight <= 0 or playResY <= 0: INTENDED, locked. Consumers take font metrics only from valid scaleFontSize calls. No typed refusal (that would be a semantic change).
2. declaredDefaultRect placeholders (scaledFontSize = 0.0, usedDefaultPlayRes = false): unconsumed by contract, locked. No Optional change.
3. Non-finite inputs: locked observed behavior, not a typed refusal. NaN origin composites at the clamped edge with pulled = true and the NaN carried in the receipt (in-bounds, no crash). NaN size, negative size, and zero size (including -0.0) return nil and are indistinguishable at the caller. No new filtering or refusal layer. Renderer contract: real cue geometry must be finite; the receipt covers anomalies.
4. Typed-nil wording: behavior kept; the TEXT is corrected. Nil conditions, stated precisely: nil iff (a) the fit pixelRect is zero-size or a frame dimension is zero, or (b) the scaled/clamped width or height fails > 0 (zero including -0.0, negative, or NaN). A finite positive-size rect with a non-degenerate fit and frame never returns nil; the earlier zero fit/frame guard can still return nil for any rect.
5. Doc-only corrections CONFIRMED (no behavioral meaning, lab owns the edits): enum case comment "candidate default, pending Q5 answer"; drawableToFrameRect doc comment "nil when the rect lies fully in the letterbox border" (the implementation nils only on degenerate input, per decision 4).
6. Q4-selector wording correction: the phrase "nonfinite and degenerate seconds never activate" is WRONG. Correct wording: "NaN and degenerate intervals never activate; infinite bounds remain valid half-open endpoints." The shipped selector (pin above) already implements exactly this via plain comparisons; no code change. No generic nonfinite filter is to be introduced anywhere in the cue path.
