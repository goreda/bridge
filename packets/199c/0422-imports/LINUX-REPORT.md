# T7 independent replay:11 new rows

Swift6.0.3 Linux. All20 input carrier SHA256 hashes verify. Latest materialized A16/A17/session sources and tests match replayed bytes. B13-20 baseline sources independently match local exact cf3 bytes; production diffs independently apply and yield returned source bytes. Session/launch source patch also independently applies and matches returned bytes. No lab receipt object is acceptance.

## A16

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 6 |
| baseline | -O | 0 | 1 | 6 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 1 |
| mutant | -O | 0 | 1 | 1 |

## A17

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 13 |
| baseline | -O | 0 | 1 | 13 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 15 |
| mutant | -O | 0 | 1 | 15 |

## sessionfix

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 1 | NOT_RUN |  |
| baseline | -O | 1 | NOT_RUN |  |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 1 |
| mutant | -O | 0 | 1 | 1 |

## B13

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 13 |
| baseline | -O | 0 | 1 | 13 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 4 |
| mutant | -O | 0 | 1 | 4 |

## B14

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 6 |
| baseline | -O | 0 | 1 | 6 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 6 |
| mutant | -O | 0 | 1 | 6 |

## B15

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 10 |
| baseline | -O | 0 | 1 | 10 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 0 | 0 |
| mutant | -O | 0 | 0 | 0 |
| mutant2 | -Onone | 0 | 0 | 0 |
| mutant2 | -O | 0 | 0 | 0 |
| mutant3 | -Onone | 0 | 1 |  |
| mutant3 | -O | 0 | 1 |  |

## B16

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 2 |
| baseline | -O | 0 | 1 | 2 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 0 | 0 |
| mutant | -O | 0 | 0 | 0 |
| mutant2 | -Onone | 0 | 1 | 1 |
| mutant2 | -O | 0 | 1 | 1 |

## B17

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 3 |
| baseline | -O | 0 | 1 | 3 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 3 |
| mutant | -O | 0 | 1 | 3 |

## B18

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | -4 | 0 |
| baseline | -O | 0 | -4 | 0 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 4 |
| mutant | -O | 0 | 1 | 4 |

## B19

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 0 | 1 | 9 |
| baseline | -O | 0 | 1 | 9 |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 3 |
| mutant | -O | 0 | 1 | 3 |

## B20

| Condition | Mode | Compile exit | Semantic exit | Fail assertions |
|---|---|---:|---:|---:|
| baseline | -Onone | 1 | NOT_RUN |  |
| baseline | -O | 1 | NOT_RUN |  |
| fixed | -Onone | 0 | 0 | 0 |
| fixed | -O | 0 | 0 | 0 |
| mutant | -Onone | 0 | 1 | 2 |
| mutant | -O | 0 | 1 | 2 |

## Additional grounding and limits

- All11 fixed rows GREEN in explicit -Onone/-O. Each has at least one compiling production mutant RED in both modes. For B15 use mutant3 pump-guard bypass; for B16 use mutant2 full endpoint bypass. Do not discard the surviving earlier mutants below.
- A16 baseline6 assertion failures; A17 baseline13 failures; fixed0, respective mutants1/15 failures. Raw -Onone and -O logs and exact argv included.
- Session returned new atomic API does not exist in baseline, so returned test baseline compile-RED is recorded. Independently adapted legacy-restamping test compiles both sources: baseline semantic1, fixed semantic0 in both modes. Legacy receipts intentionally unproven after fix. New API/currentness/issuer/revision/ticket tests PASS fixed; issuer-bypass mutant fails. Host adoption NOT_RUN, so not a host-level stale-receipt closure.
- B15 lab test embeds NormalizedRect/CropSuggestion stand-ins. Added actual complete58-source PlaybackCore compilation using real production DTOs, with existing actual Core/NativeProbe/CAtomics dependency objects linked: baseline compile0/runtime1(10 failures), fixed0/0, pump-guard mutant0/1(10 failures), both modes. Dependencies were existing debug builds. No full provider/host native claim.
- B15 detector-only invalid-config guard bypass survives because pump guard remains. Counter-only suppression increment removal also survives. Supplied test does not establish invalid-counter correctness or independent detector guard coverage.
- B16 end-finiteness-only bypass survives returned test in both modes. Full endpoint-finiteness bypass fails. This is a test coverage limit, not evidence of a remaining actual-source defect under the fixed guard.
- B17 actual FIFO file named movie.srt is discovered in BOTH optimizations. The change excludes directories and broken links, not every nonregular file. Probe never opens or reads the FIFO. Initial local probe placed mkfifo inside assert, which -O removes; corrected setup calls mkfifo before precondition. Only fifo-final logs are the actual setup-valid evidence.
- B18 baseline compiles but traps signal4(exit-4), not assertion RED. Fixed and deterministic-tag mutant execute normally, with mutant4 assertion failures. Retained finite goldens do not prove collision freedom of variable-length time tagging.
- B20 typed limits API baseline fails compile by design; no baseline semantic execution is claimed. Fixed and bypass-byte-budget mutant compile, fixed passes and mutant fails2 checks. Line/scalar bounds run after the byte-bounded split, not a streaming parser.
- B11/B12 T7 production and test diff fences match prior0358 diffs (whole carrier bytes differ, B12 corrects narrative baseline-count provenance), so no repeated run/import. launch10 replay ran before dedupe instruction: fixedPASS/mutantRED both modes and real unchanged launch/capture routePASS. It is supplemental duplicate evidence, not a new import.
- H0645/H0646 JSON fence LF vs no-LF digest caveat preserved: tests parsed from materialized JSON, no claimed raw-fence digest equivalence. Input transport carrier hashes verified exactly.
- Full host/native/UI acceptance NOT_RUN; no refs touched.
