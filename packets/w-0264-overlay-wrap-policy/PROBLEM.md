# Long-line overlay wrap policy at the subtitle seam

## Problem
The subtitle seam has NO declared wrapping contract. Verified by sweep on
pin e399471bc25ec4a3f1299ad79a1675b3fb818588 (branch l3-subtitle-overlay-m2,
not yet merged to main): SubtitleLayout models PlayRes scaling, margins and
destination rects only; there is no wrap/bidi/line-breaking logic anywhere in
Sources/GorAVMetalPresenter/core or Sources/GorAVSubtitles. The Mac
rasterizer (SubtitleRasterizerCoreText.rasterize, Darwin-gated) hands text
to CTFramesetter with a max size - platform default behavior, not a declared
policy. Result: long-line behavior (max width, line cap, growth direction,
what happens on overflow) is undefined at the seam level and cannot be
tested off-Mac.

## Current contract
- LayoutDecision { scaledFontSize, usedDefaultPlayRes, destinationRect,
  coordinateSpace, placementWasDeclaredDefault } - additive changes only.
- Anything unresolved is a TYPED REFUSAL or a reported finding, never a
  silent default (house rule across the seam).
- Mac rasterizer stays the pixel authority on-device; this packet is the
  seam-level policy it will consume - Linux-verifiable pure functions only,
  no Mac claims.

## Candidate design directions (PROPOSALS - not owner-approved architecture)
1. Wrap policy as a pure function: (lines, scaledFont, available width) ->
   wrapped lines + per-line widths + overflow finding. Word boundaries,
   hyphenless scripts, and Turkish locale behavior must be stated, not
   assumed.
2. Overflow semantics: when wrapped lines exceed the available height the
   outcome must be declared - candidates: typed refusal, shrink-to-fit with
   floor, or top-crop with receipt. Pick ONE, justify it, name the losers.
3. Interaction with bottom-margin placement (destinationRect growth
   direction) must be explicit.

## Task
Spec + reference implementation of the wrap policy as pure functions against
the current LayoutDecision shape, with generic fixtures (starter:
fixtures/long-lines.srt incl. a Turkish long line; extend: single word wider
than the box, empty cue, cue that exactly fits, N-line cap boundary).

## Acceptance
1. Linux tests assert every fixture's declared wrapped output + overflow
   outcome.
2. No Mac/rasterizer claim - seam policy only, labeled as such.
3. Report names every policy decision and each rejected alternative.

## Role
Solver: spec + implementation + fixtures. Reviewer (separate lab):
typographic review (line-breaking correctness, locale traps), adversarial
fixtures. Integration stays internal; labs do not merge.
