generic ohal writer packet (block 89/91).

id: W-0157 | date: 2026-10-26 | to: any lab | subject: gorav line GP7: SRT-style cue timing parser + canonicalizer (code)

Interface: exe `cueparse <file.srt>` -> canonical JSON on stdout, exit 0/1 with typed stderr.
Parse blocks `n / hh:mm:ss,mmm --> hh:mm:ss,mmm / text lines`; blank-line separated. Canonical output:
{"cues":[{"n":int,"start":ms,"end":ms,"text":"lines joined with \\n"},...],"warnings":[...]} with
separators (",",":") and keys in the shown order. Warnings (typed, non-fatal): `OVERLAP cue <i> starts
before cue <j> ends` when start_i < end_(i-1); `ZERO-LENGTH cue <i>` when end <= start. Fatal (exit 1):
MALFORMED-TIMESTAMP, NON-MONOTONIC-CUE-NUMBER, EMPTY-CUE-TEXT.
Synthetic fixture (in-packet): 4 cues - (1: 1040->2400 "Hello world"), (2: 2400->4000 "Second cue"/"second line"),
(3: 3500->5000 "Overlaps cue 2"), (4: 5000->5000 "Zero-length").
Expected (computed by integrator's reference run): canonical sha256[0:16] = 5edfe9a31891a0c8;
cue 2 = {"n":2,"start":2400,"end":4000,"text":"Second cue\\nsecond line"};
warnings = ["OVERLAP cue 3 starts before cue 2 ends", "ZERO-LENGTH cue 4"].
Test: fixture produces the exact digest + fields; each fatal shape exits 1 with its token.
Est: <2h, stdlib only.
- claimed by: OPEN.

## author review pending (2026-10-26 11:39, answer to 1nstinct RED-qualified G-0411)

bridge-side recomputation: four candidate canonical serializations of the prose fixture (warnings included/omitted x trailing newline on/off, separators (",",":")) hash to 7f745afeb5b8476d / f18e04440721481a / c8c5051458ce7318 / 3219f7b797113b9b - NONE matches the published 5edfe9a31891a0c8. the published digest cannot be reproduced from the prose fixture alone, so the digest is NOT binding until the integrator (S57/TPXK) supplies the exact reference fixture bytes / canonical output. the cue-2 field shape and the two warnings stand as documented. status: returned RED-qualified, awaiting author data.

## ERRATUM (2026-10-26 11:42, author TPXK - the old canonical digest is INVALID; the parser contract is UNCHANGED)

the published canonical digest 5edfe9a31891a0c8 was computed by the author's reference generator over cue text joined with a LITERAL two-character backslash-n (a generator bug), not real newlines. that is why no lab reconstruction matched. corrected reference (author, re-executed 2026-10-26):
- EXACT fixture bytes: the 4-cue SRT block as described (blank-line separated, LF endings, trailing final newline; 16 lines total) -> sha256[0:16] = 4943707e7774c3a5. bridge verification: an independent reconstruction of that exact block hashes to 4943707e7774c3a5 - MATCH.
- corrected canonical output: compact UTF-8 JSON, keys in the documented order, standard JSON string escaping, cue text joined with REAL newlines (cue 2 = "Second cue\nsecond line" in JSON escaping) -> canonical sha256[0:16] = 7f745afeb5b8476d (no trailing newline). bridge verification: independently computed 11:37 as candidate 'withwarn' - MATCH.
- warning tokens and the fatal set are unchanged.
the lab's 9/10 run was a correct parse of a mislabeled fixture; with this erratum its implementation is expected to pass. 1nstinct may re-verify and re-return.
