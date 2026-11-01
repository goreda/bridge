# ASS override-tag support matrix: bounded subset (\an, \pos)

## Problem
ASSParser (Sources/GorAVSubtitles/ASSParser.swift, pin
e399471bc25ec4a3f1299ad79a1675b3fb818588, branch l3-subtitle-overlay-m2 -
NOTE: branch code, not yet merged to main) detects every {...} override
block, strips it from cue text, and reports ALL override tags as UNSUPPORTED
(Document.unsupportedOverrides, per-cue OverrideReport). SubtitlePlan.swift
documents that these cues render without their overrides and the finding is
hashed/reported. \an (alignment) and \pos (explicit placement) are the two
most common tags in real files; today even they are stripped.

## Current contract (do not break silently)
- Override detection/strip/report behavior stays for every tag NOT in the
  supported subset. "Unsupported means unsupported, never silently dropped
  without record" (ASSParser.swift header).
- LayoutDecision / OverlayRect / OverlayCoordinateSpace (SubtitleLayout.swift,
  same branch pin) are the presenter-side layout interface.
- Q4 overlap-stacking and Q5 coordinate-mapping are accepted as SOURCE UNITS
  (lab packets W-0256/W-0257; Q5 accepted as the unchanged candidate unit).
  Their blind freeze and provider/host integration remain OPEN - only the
  units' decided rules are settled: do not reopen or redo them; a cue's
  placement output composes WITH those rules, it does not replace them.

## Candidate design directions (PROPOSALS - not owner-approved architecture)
1. \anN: map alignment 1-9 to the declared placement model; output composes
   with the existing LayoutDecision fields (or an additive extension).
2. \pos(x,y): explicit anchor in PlayRes coordinates; must state how it
   composes with PlayRes scaling and the Q5 coordinate mapping.
3. Per-cue applied-vs-unsupported receipt: a cue using \an must be
   distinguishable from a cue whose \fad was stripped; mixed blocks
   ({\an8\fad(...)}) need explicit partial-application semantics - what is
   applied, what is reported unsupported, never silent.

## Task
Implement \an + \pos against the current contracts, per-tag
applied/unsupported reporting, generic ASS fixtures (starter:
fixtures/sample-an-pos-fad.ass; extend with edge cases - out-of-range \an,
negative \pos, malformed blocks, multiple blocks per cue). Everything not in
the subset keeps the existing typed-unsupported path.

## Acceptance
1. Linux tests: each fixture cue asserts its declared outcome (applied
   placement fields + exact unsupported-tag report contents).
2. Zero change in behavior for cues without \an/\pos (regression assert
   against the plain-line fixture).
3. Report names every ASS-semantics decision taken and each one it left open.

## Role
Solver: implementation + fixtures. Reviewer (separate lab): ASS-semantics
review against a reference ASS spec, adversarial malformed-block fixtures.
Integration stays internal; labs do not merge.
