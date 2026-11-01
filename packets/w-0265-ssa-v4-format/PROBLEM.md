# SSA v4 format: real support or typed refusal (BACKLOG - not active)

## Problem
SubtitleTrack.load accepts .ssa and normalizes it to format "ass"
(SubtitleTrack.swift:15,44), but ASSParser only recognizes the [V4+ Styles]
section (ASSParser.swift:4). A real SSA v4 file uses [V4 Styles] with a
DIFFERENT field order (PrimaryColour/SecondaryColour/OutlineColour/
ShadowColour positions, AlphaLevel, Encoding) and a different Events Format
(Marked/Name/Effect columns). Outcome today: the style table parses as zero
styles, so every named-style cue hits the 169j named-absent typed refusal -
the file is effectively dead while claiming to be a supported extension.

## Current contract
- format is "srt" or "ass"; .ssa normalizes to "ass" (public comment, pin
  e399471bc25ec4a3f1299ad79a1675b3fb818588).
- 169j: a named-but-absent style is a TYPED REFUSAL, never a default.
- Findings (skippedStyles) are reported, never silent.

## Candidate design directions (PROPOSALS - not owner-approved architecture)
Pick ONE, justify, name the loser:
1. Real v4 support: parse [V4 Styles] with its own Format mapping (colour
   order differs - v4 has no alpha in the same positions; state the exact
   colour conversion), Events Format mapping, and record format "ssa" (or
   normalize with a declared note). 
2. Typed refusal: .ssa files carrying [V4 Styles] refuse with a distinct
   typed error naming the format version, replacing today's silent
   zero-styles degradation.
Either way the normalization comment and the format field must stop
misdescribing the outcome.

## Task
Design + implementation + tests on Linux; generic fixtures (starter:
fixtures/sample-v4.ssa; extend: v4 with corrupt style row, v4+ file renamed
.ssa, mixed/unknown section names).

## Acceptance
1. Every fixture's declared outcome asserted (parsed v4 styles + cue, or the
   exact typed refusal).
2. Zero behavior change for .ass/.srt inputs (regression asserts).
3. Report names the colour-mapping decision explicitly.

## Role
Solver + separate reviewer. Integration internal; labs do not merge.
Batch activation: the whole W-0265..0268 batch starts only AFTER the current W-0261..264 batch completes (owner's order); no rolling per-slot substitution.
