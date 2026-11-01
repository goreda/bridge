# Bidi / mixed-script display order at the seam (BACKLOG - not active)

## Problem
Verified by sweep on pin e399471bc25ec4a3f1299ad79a1675b3fb818588: no bidi,
script-run, or display-order logic anywhere in Sources/GorAVSubtitles or
Sources/GorAVMetalPresenter/core. Cue lines are handed to the rasterizer as
raw logical-order strings. IMPORTANT PRECISION: the Mac rasterizer delegates
to CoreText, which may ALREADY shape/reorder bidi text correctly - the
absence of a custom algorithm in the seam does NOT prove a visible bug.
The verified gap is a POLICY gap: no declared display-order contract, no
receipts, no off-Mac testability - actual renderer behavior is unexamined.
A visible-reorder bug is UNPROVEN until someone reads the real CoreText
output for mixed-script input.

## Current contract
- SubtitleCue.lines: logical-order strings; no direction metadata.
- Mac rasterizer is the pixel authority on-device; this packet is seam
  policy it will consume - Linux-verifiable pure functions, NO Mac claims.
- House rule: unresolved = typed finding, never silent fallback.

## Candidate design directions (PROPOSALS - not owner-approved architecture)
1. FIRST: ground the actual renderer behavior (what CoreText does with
   mixed-script logical input; documented evidence, not assumption). Then:
   declared display pipeline - either (a) CoreText's reordering is adopted
   as the DECLARED authority and the seam only records receipts, or (b) the
   seam resolves display order itself (UAX#9 or declared bounded subset).
   NEVER both: resolving order in the seam AND letting CoreText reorder is
   double-reordering, a worse bug than either alone.
2. Findings: lines whose resolved order differs from logical order emit a
   receipt; unresolvable cases (explicit embedding controls, isolate
   overrides) get a typed outcome - support or refuse, declared.
3. Composition with W-0266 (inline tags) and W-0267 (\N expansion): bidi
   resolution operates on final display text - order of operations must be
   specified in the packet, not left to the implementer.

## Task
Spec + reference implementation of the display-order function + tests on
Linux; fixtures (starter: fixtures/mixed-lines.txt with expected-outcome
placeholders to fill per the chosen policy; extend: RTL-only line, neutral
characters at boundaries, digits at run edges).

## Acceptance
1. Every fixture's declared display order asserted.
2. Pure-LTR and pure-RTL lines are provably identity (regression asserts).
3. Report names every UAX#9 deviation taken and why.

## Role
Solver + separate reviewer. Integration internal; labs do not merge.
Batch activation: the whole W-0265..0268 batch starts only AFTER the current W-0261..264 batch completes (owner's order); no rolling per-slot substitution.
