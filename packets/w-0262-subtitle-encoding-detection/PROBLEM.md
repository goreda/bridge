# Subtitle encoding detection + typed fallback

## Problem
SubtitleTrack.load (Sources/GorAVSubtitles/SubtitleTrack.swift, pin
2d8f7373c332b9c99cbe2002c2af5d4db2cd8ea8, function at line ~42) decodes
every file as UTF-8 only:

    guard let data = ..., let text = String(data: data, encoding: .utf8)
    else { throw LoadError.unreadable(path: path) }

Real-world SRT files are frequently Windows-125x / Latin-x single-byte
encodings. Today such a file throws LoadError.unreadable - indistinguishable
from "not a subtitle file at all". The player cannot tell the user (or its
own diagnostics) WHICH failure happened.

## Current contract (do not break silently)
- Track is the value type produced by load; it is hashed into the subtitle
  plan (SubtitlePlan.swift feeds track fields into plan hashes) and consumed
  by the provider surface. Any interface change must be ADDITIVE and
  explicitly versioned/reviewed; no silent breaking of the public shape.
- SRT: styles [], unsupportedOverrides [], playRes nil (see load()).
- Anything unresolved is a TYPED REFUSAL, never a silent default.

## Candidate design directions (PROPOSALS - ground them in the current
contracts; nothing here is owner-approved architecture)
1. Detection policy: BOM check -> strict UTF-8 validity -> declared
   single-byte fallback ORDER (which encodings, in which order, is a policy
   decision the packet must justify, not assume).
2. Typed outcome: either (a) a receipt/field naming the encoding actually
   used, or (b) a typed refusal naming the ambiguity. An ambiguous file MUST
   NOT be silently guessed as some 125x variant; the refusal-policy
   qualification (when ambiguity refuses vs when a fallback is justified) is
   part of the deliverable. No "universally correct detection" claim - that
   claim is false for single-byte encodings in general.
3. Charset-conversion errors (undecodable byte sequences in the chosen
   encoding) need their own typed path, distinct from unknownFormat and
   unreadable.

## Task
Design + reference implementation + tests for encoding handling at
SubtitleTrack.load, with a generic synthetic corpus (fixtures/ contains
starter samples: utf8, utf8+BOM, windows-1254, latin-1; extend with edge
cases - empty file, truncated multibyte, mixed line endings, wrong-extension
bytes). All fixtures synthetic/generic; no real user subtitle files.

## Acceptance
1. Every corpus file yields the declared typed outcome (loaded-with-receipt
   or typed refusal), asserted in tests on Linux.
2. No silent fallbacks: each load names its encoding evidence.
3. Interface change is additive and called out explicitly in the report.

## Role
Solver: design + implementation + corpus. Reviewer (separate lab): attack
the corpus (new adversarial encodings), verify no silent path exists.
