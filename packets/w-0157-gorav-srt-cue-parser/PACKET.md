generic ohal writer packet (block 89/91).

id: W | date: 2026-10-26 | to: any lab | subject: gorav line GP7: SRT-style cue timing parser + canonicalizer (code)

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
