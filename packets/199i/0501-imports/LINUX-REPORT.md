# 199i B36/B37 independent replay

Scope: exact host-vendored archive/gor/Packages/gorav sources in the b60352dabc87fe8519832999b4af639f37d786f8 packet, not goravmain cf3. Original outer archive SHA256 3a26ded5fab92e117cddf389193a6c929b2422aea614b614c9b4ebb1b0669a62 verified. All 25 listed internal file digests match. Both unified patches apply without repair and reproduce fixed materialized bytes exactly. No refs changed.

Swift 6.0.3 Linux, explicit -Onone/-O. Both baselines compile and fail assertions; no compile failure counted as semantic RED.

| Row | Baseline | Fixed | Production mutant |
| --- | --- | --- | --- |
| B36 | 6 PASS, 1 FAIL | 7 PASS | remove semicolon checks: 6 PASS, 1 FAIL |
| B37 | 4 PASS, 1 FAIL | 5 PASS | change cap64 to65: 4 PASS, 1 FAIL |

Same results in both modes. Main mutation sources, complete pinned/fixed source, extracted declarations, exact fixture configs, compiler argv, compile logs and runtime logs are under independent/.

## B36 additional production-path coverage

The supplied test extracts only the struct/error/typed-validator declarations. It does not compile goravR3OpenInput, despite the source patch changing that backstop too. A backstop-only production mutant therefore survives the supplied test. This blind spot is retained in EXTRA-RESULTS.json.

Independent extension compiles the actual goravR3OpenInput declaration and serializer along with the actual typed declarations. Only AVFormatContext and gorav_r3_open_input are stubbed to capture the call and header. This is not an actual FFmpeg open or network test. Both modes: baseline RED2, fixed GREEN8, compiling backstop-only mutant RED2. It verifies ';', CR/LF/NUL refusal before the C shim is called, exact Cookie serialization for ordinary/base64 values, and case-insensitive Cookie-header conflict. Thus a validator-only fix cannot pass the extended coverage.

Boundary observation: tab, DEL and an interior quote remain accepted by the typed cookie-value validator. This is outside the narrow semicolon split defect, but is a follow-up grammar-hardening request if strict valid Cookie field values are intended. Percent-encoded ';' is also admitted as literal text; no percent-decoding occurs in this serializer, so this is not shown to create an additional pair. No claim of a semicolon bypass or live incident is made.

## B37 additional coverage and fix request

109 independent checks pass per mode. They verify exact issueTotal and the exact original-order first64 witnesses for n=0/1/2/11/12/100, 100 mixed-order pseudo-random tracks compared with the original quadratic reference, and larger overlapping tracks. issueTotal=4950 for100 identical overlapping cues is verified, unlike the returned test which does not inspect the new total property. Existing half-open cue/selection semantics remain untouched by the patch.

Memory for collected Issue witnesses is bounded64, but the pair enumeration is still quadratic even when cues do not overlap. Measured fixed initialization timings on this venue:

| cues | exact overlapping pairs | -Onone seconds | -O seconds |
| --- | --- | --- | --- |
| 2,000 | 1,999,000 | 0.187 | 0.0020 |
| 4,000 | 7,998,000 | 0.749 | 0.0081 |
| 8,000 | 31,996,000 | 3.023 | 0.0321 |

Doubling input costs approximately four times. If the caller really permits200,000 cues as the packet says, the loops execute exactly19,999,900,000 pair tests. This count is arithmetic, not a200k runtime measurement. Fix request: use an indexed interval/count algorithm if bounded subtitle-load time is required, while preserving exact total and first64 in document order. A bounded witness list alone is not bounded work. Native UI responsiveness and the full upper-bound input were NOT_RUN.

## Scope limits

The complete source files in this exact packet are tested; main tests use returned helper extraction/SubtitleCue support, not the full vendored modules. Other cf3 trees were deliberately not substituted for missing b603 dependencies/callers. Packet prose names remote video/audio/inventory and subtitle controller/plan callers, but those other full files are absent from this archive, so their exact b603 line numbers and full-host wiring are not independently revalidated here. No native/macOS/network/actual FFmpeg open claim. This is source-level fix evidence plus explicit follow-up requests, not owner approval or product import.
