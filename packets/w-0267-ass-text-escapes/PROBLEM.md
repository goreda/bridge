# ASS text escapes \N and \h (BACKLOG - not active)

## Problem
ASS cue text carries \N (hard line break) and \h (hard space) OUTSIDE {...}
override blocks, so the override-stripper never touches them. Verified by
sweep on pin e399471bc25ec4a3f1299ad79a1675b3fb818588: zero handling
anywhere in GorAVSubtitles or the presenter core (grep for the escapes is
empty) - the literal backslash sequences render as visible text.

## Current contract
- Override blocks {...}: detected, stripped, reported (169j/W-0263 surface).
  \N/\h are NOT override tags; they are text-level escapes - different class.
- SubtitleCue.lines is [String]; a \N inside one Dialogue text implies a
  MULTI-LINE cue - this changes the lines array shape, which feeds
  LayoutDecision and the W-0264 wrap policy. Composition must be named, not
  assumed.
- Anything unresolved is reported, never silent.

## Candidate design directions (PROPOSALS - not owner-approved architecture)
1. Parser-level expansion: \N splits into separate lines entries, \h becomes
   a declared space character; report counts per cue.
2. Seam-level expansion: keep parser verbatim, expand at the provider/seam
   boundary with findings.
Pick ONE, justify against the current contracts, state which surface owns
the finding. \n (lowercase, soft break) and unknown backslash sequences need
declared outcomes too.

## Task
Implementation + tests on Linux; fixtures (starter: fixtures/escapes.ass;
extend: trailing \N, \N at text start, consecutive \N\N, \h at line edges).

## Acceptance
1. Every fixture's declared lines array + findings asserted.
2. Zero change for escape-free cues (regression assert on the plain line).
3. Composition with W-0263 (override strip) and W-0264 (wrap) named
   explicitly: escape expansion order vs override strip is specified.

## Role
Solver + separate reviewer. Integration internal; labs do not merge.
Batch activation: the whole W-0265..0268 batch starts only AFTER the current W-0261..264 batch completes (owner's order); no rolling per-slot substitution.
