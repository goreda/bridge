# H-0651 B21/B22 independent replay

Engineering validation only. No refs changed. Swift 6.0.3 Linux with explicit -Onone/-O. Raw markdown is retained as data, not approval.

## Explicit normalization

Both markdown SOURCE hunks pass git apply --check unchanged once extracted from the fence. Applied full-source old/new SHA256 values exactly match both advertised pairs. The malformed part is the JSON fixture diff: hunk lengths plus closing fence fused with the no-newline closing brace. The old JSON hashes match. The intended new JSON hashes match exactly only after preserving the lack of a final newline. Initial newline-bearing materializations and their mismatch records are retained, not concealed. fixture-no-newline-normalized.patch uses diff-generated corrected hunk lengths and the explicit no-newline marker; it applies to the old JSON and reproduces the advertised new bytes exactly. No test text, JSON values, production statements or comments were inferred or repaired. materialize.py and caller-replay.py record each step; NORMALIZATION.json retains the initial newline comparison, while the final hashes are:

B21 source 0f3fa4238a8d7d9e3cff41bf625b20b1f9da28027667720f81f8424bf8c6ead6 -> 0fcc70bdf63c0bc9f334a73f07c137ca843182e9036d7b7f99ed864e385c0409; fixture 3ef6edc02f0fd54c173b72f3381d98cff201d0edd8184d0acc7d102dc13b660c -> 59329df4e8ff7bb2ebb5416e23ef6bd7f907cb4ce223db1e1139d1169b8f9665.

B22 source 1c5ed5f1b1d7a75132b5295d7640736a180d0c63720fd0f5cf7785f30d271d2b -> 5cd518a3433c965ae9ac1846ca0796e14535570fffbce8d205019b130f18d0c1; fixture 74cfea74b63429efa43289ced97821174c995474bdb4a5de7fe0b033c1e233ac -> 5c9fff7b590ea1e999ecdc99dcfff038a7a93c7b5f501c8e61655e7ea0d214fc.

## B21

Both modes: original starter baseline RED 2 checks, fixed GREEN 2; extended baseline RED 4, fixed GREEN 12. A compiling production mutant that removes fragment stripping fails starter and extension in both modes. The complete actual three-source GorAVCore (Boundary, AdmissionTable, OpenURLRouter), with actual C atomics objects instead of fixture SourceDescriptor, repeats baseline RED/fixed GREEN/mutant RED in both modes against the extension.

Caller review: NodeSourcePreparation.prepareImpl at lines 32 onward switches this route, admitting only transfer/mega for preparation and refusing others. EmbeddedSession.open(url:) at 725 onward directs generic remotes to openRemote and torrent/magnet to typed refusal until a bridge exists. The fix prevents fragment-bearing torrents falling into generic remote there, but does not itself implement a bridge. Native embedded macOS open is NOT_RUN. Subject remains the original complete URL; classification only strips fragment then query. Transfer/mega routing code is unchanged.

## B22

On this venue the unextended baseline starter is already RED in both modes (one collision-count failure), unlike the lab's 32 GREEN runs. This variance is kept explicit.

Extended baseline: 7/7 fresh process runs RED in EACH mode. Every one of the 30 barrier rounds fails in all 14 runs (420 failed rounds); ordinary starter checks add one failure in 13 runs and two in one run. Fixed extension: 10/10 fresh processes GREEN in EACH mode, 36 checks each, 600 total barrier rounds and 240,000 barrier publications with no collision/newest-value failure. This strongly reproduces the bug but semaphore-aligned scheduling stress is NOT a mathematical deterministic interleaving proof. The report must not convert repeated stress into such a claim.

Compiling production mutant moves publication outside the instance lock and uses the safe re-locking failure counter again: RED under starter and extension in both modes. This isolates publication serialization rather than creating a data-race-only failure counter. The fixed failure-path check also completes, advances count and increments writeFailures; leaving the old recursive locking there would hang and is not part of the tested fix.

The complete actual 58-source playback core compiles/runs the extension baseline RED, fixed GREEN, production mutant RED in both modes. Actual debug dependency objects are reused for GorAVCore/NativeProbeKit/CAtomics; owned playback sources receive the stated optimization mode. Compiler commands are logged. One command batch timed out during the last optimized mutant compile, so the completed preceding 11 rows were recovered from progress and the final leg was rerun separately and passed compile/failed runtime as intended.

Caller review: ShellFrameSource has one private heartbeat instance initialized from the per-run environment at line 216. Both decoded-event paths call noteDecodedFrame, enveloped at 143 and legacy at 341. The class serializes an INSTANCE, not multiple instances/processes writing one path; per-run path ownership remains required. Fixed calls synchronously include disk IO while locked, with potential decode latency, not a throughput claim. Native decoder callback wiring is source-reviewed only, not executed on Linux. Counter wrap behavior and one-write-per-decoded-frame semantics are unchanged. No timer/batching or wall-clock substitution.

## Evidence and limits

independent/ includes full tested source, mains, compile argv/logs, runtime logs and per-run results. materialized/ includes extracted original/normalized patches, exact source/fixtures and apply checks. Actual-core source dependencies and caller evidence are included separately. Full native app, IPC, UI, network and macOS decoder pipeline are NOT_RUN. No branch/ref/import changed here.
