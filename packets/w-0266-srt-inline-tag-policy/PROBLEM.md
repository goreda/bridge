# SRT inline-tag rendering policy (BACKLOG - not active)

## Problem
SRTParser keeps inline tags in cue text verbatim by design ("presentation
stripping belongs to the renderer", SRTParser.swift:8-9). Verified by sweep
on pin e399471bc25ec4a3f1299ad79a1675b3fb818588: NOTHING downstream strips
or interprets them - the presenter/rasterizer path renders "<i>word</i>"
literally, angle brackets and all. Common real SRT files carry <i> <b> <u>
<font color>; all of them currently display as visible garbage.

## Current contract
- Parser keeps tags verbatim; typed refusals on malformed blocks only.
- SubtitleCue.lines is [String] - plain strings, no span/attribute model.
- Anything unresolved is reported, never silently dropped (house rule).

## Candidate design directions (PROPOSALS - not owner-approved architecture)
1. Strip-with-receipt at the seam: remove recognized + unrecognized tags,
   emit a per-cue finding naming what was stripped (never silent).
2. Minimal span model: an ADDITIVE cue/line extension carrying italic/bold/
   color spans for the recognized subset, strips+reports the rest.
3. Pass-through with typed finding (status quo visibility, but reported).
Each has a different interface cost; the packet must pick ONE, justify it,
and state how the Mac rasterizer would consume it WITHOUT this packet
claiming any Mac behavior (Linux seam scope only). Composition note: the
chosen shape feeds W-0264 wrap policy (wrapping operates on display text,
not tag bytes) - do not finalize without naming that interaction.

## Task
Design + implementation + tests on Linux; fixtures (starter:
fixtures/inline-tags.srt; extend: nested tags, tags spanning a line break,
angle-bracket text that is not a tag, empty tag <>).

## Acceptance
1. Every fixture's declared display text + findings asserted.
2. Untagged cues byte-identical outcomes (regression assert).
3. Report names what happens to unrecognized/unclosed tags and why.

## Role
Solver + separate reviewer. Integration internal; labs do not merge.
Batch activation: the whole W-0265..0268 batch starts only AFTER the current W-0261..264 batch completes (owner's order); no rolling per-slot substitution.
