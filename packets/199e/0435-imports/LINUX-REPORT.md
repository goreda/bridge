# Independent ten-row replay

Engineering validation only. No refs changed. Swift 6.0.3, explicit -Onone and -O. Latest Ops materialization is authoritative. All ten source-only patches apply cleanly and reproduce the fixed materialized source bytes exactly. This is extracted production/helper testing with each returned config's support and test source, not a full native/AppKit application build. A28 excludes AppKit. A27 thermal support remains fixed false. A30 tests valid, non-cyclic deep trees only.

## Main returned tests

Both modes have identical outcomes. Every baseline compiles. All fixed tests pass. All selected production mutants compile and fail semantically.

| Row | Baseline | Fixed passing checks | Selected mutant |
| --- | --- | --- | --- |
| A21 | 8 failed | 17 | CRLF omission, 8 failed |
| A22 | trap -4 | 36 | reject topBottom, 3 failed |
| A23 | 4 failed | 14 | wrong export parameter value acceptance, 2 failed |
| A24 | 4 failed | 10 | bypass smoothForAxis invalid guard, 4 failed |
| A25 | 42 failed | 47 | disallow zero gap, 1 failed |
| A26 | 51 failed | 55 | omit CR stripping, 51 failed |
| A27 | 5 failed | 13 | permit infinite timestamp, 5 failed |
| A28 | 9 failed | 35 | minimum short side 2, 2 failed |
| A29 | 4 failed | 11 | truncate record to start, 3 failed |
| A30 | segfault -11 | 311 | reverse traversal child order, 284 failed |

A30 prints an aggregate check count rather than a PASS line per check; RESULTS.json's PASS-line count is therefore zero, not zero executed checks.

## Additional boundary findings

These are gaps in the fixed sources despite GREEN returned tests, measured in both modes. No fix is introduced here.

- A25 leadingFrames: finite left and width both greatestFiniteMagnitude, ink=0 and gap=0 return one rectangle with finite origin and width but infinite maxX. The leading placement guard checks ink advance, not the width-derived right edge. This violates a broad finite-rectangle interpretation.
- A24: greatestFiniteMagnitude level with dt=0.016 passes the finite input guard. Internal agcVariance becomes infinity on the first sample, NaN on the next negative-huge sample. Axis output is about 1.15e215 initially and stays out of [0,1] after ordinary level=0.4 samples. The standard positive count remains exactly 10. Derived-state snapshots are in extra-boundaries/A24/*-state.log and the exact generating main.swift is present.

## Controls and scope limits

Earlier controls are retained separately as coverage evidence, not used to conceal survivors: A24 held-output-to-zero and a dt threshold mutation survived; A28 finite-input-only guard removal survived downstream checks. A29's initial self-assignment mutant was compile-RED, so the main table instead uses a compiling semantic truncation mutant. Earlier A25 lacked its hoverFrame extraction marker and was compile-RED; that incomplete extraction is not accepted evidence. The latest full config supplies the marker and all 47 tests pass.

Six earlier source byte comparisons differed only in surrounding whitespace after strip comparison (A23/24/25/26/29/30). The latest exact bytes were still replayed for all ten rows, not substituted. Earlier-comparison.json records this. Raw source hashes are in RESULTS.json.

A23/24/29 archived SHA256SUMS files contain an invalid self-entry holding the empty-file digest. All other entries checked match. The self-entry is excluded explicitly; this is not a full-manifest integrity PASS. See manifest-check.json.

## Evidence

ops-replay/ contains full baseline/fixed/mutant sources, exact configs, extracted production, test mains, raw compiler argv/logs and runtime logs for every mode. source-apply/ contains the exact patched source used for the byte equality assertion. replay-ops.py asserts patch application and records replay results. Earlier-controls/ retains prior raw test evidence. extra-boundaries.py generates boundary probes; the inspected state-snapshot variant is preserved as the generated A24/main.swift. All outer carrier hashes had been checked before extraction. This packet is validation evidence, not product acceptance or owner approval.
