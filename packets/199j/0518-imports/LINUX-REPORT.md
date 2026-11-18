# 199j A41-A44 independent replay

Input is the adapted published bundle only, with neutralized attribution comments and refreshed hashes. Host b603 source scope. No earlier unsanitized packet substituted. All37 SHA256SUMS entries match. All four patches apply and reproduce the adapted fixed bytes exactly after ONLY replacing absolute temporary diff file headers with repository-relative a/ and b/ headers. Original and normalized patches retained. Hunk contents/counts are unchanged. No refs touched.

## Main semantic replay

Swift6.0.3 Linux, explicit -Onone/-O. Same results in both modes:

| Row | baseline compile/runtime | fixed compile/runtime | compiling production mutant runtime |
| --- | --- | --- | --- |
| A41 | 0 / 1 | 0 / 0 | 1, undo container decode-before-encode |
| A42 | 0 / 1 | 0 / 0 | 1, omit vrEnabled |
| A43 | 0 / -4 trap | 0 / 0 | -4 trap, omit pid upper-bound guard |
| A44 | 0 / 1 | 0 / 0 | 1, bypass CR/LF replacement |

Supplied tests stop at the first failure, so failure counts are not expanded into claims about all assertions on a RED leg. Direct compiler/binary results are recorded, not just harness exit. The original supplied runner was separately run for every baseline/fixed/mode: its process exit is0 in ALL16 legs, including semantic1 and-4. RUNNER-RESULTS.json records the parsed compile_exit/semantic_exit correctly. A green harness process is not accepted as a green test.

## Boundary fix request: A41 container path structure

Both modes reproduce:

- Encoded container filename a%2Fb.zip is emitted as the different path a/b.zip. Decode-segments then join with allowed slash loses the original segment boundary.
- Container prefix %2e%2e is decoded and emitted as a literal ../ component. Member-side traversal checks do not validate container components.
- Ordinary %20 container/member names now roundtrip as the patch intended.
- Member ..%2F traversal refuses; member a%2Fb remains admitted as nested member path under the existing documented behavior.

Request: validate decoded container segments too, and preserve each segment's delimiter semantics during encoding. Do not change an encoded slash inside a filename to a URL hierarchy delimiter. This is a source-level routing/identity finding, not proof of server filesystem traversal or native archive extraction exploit.

## A42 exhaustive truth table

All16 combinations of blinkOn/vrEnabled/loadedVideoActive/cameraAllowed exactly match the four-input conjunction in both modes. No new gap found in this pure helper. Camera/native runtime NOT_RUN.

## Boundary fix request: A43 strict numeric parsing

Both modes reproduce fixed readQuitToken accepting:

- epoch18446744073709551616 (2^64) as epoch0;
- epoch1.5 as epoch1;
- JSON true as numeric epoch1 and pid1.

The existing NSNumber.intValue fallback wraps/truncates before the range guard; it does not establish exact integer representability or distinguish booleans from numbers. epochUInt64.max rejects while2^64 wraps to0 and accepts. pid0 rejects, pidInt32.max with epochInt64.max accepts. Request strict exact integer parsing and range/type validation before conversion, refusing booleans/fractions/out-of-range values. This is not a claim that any process was quit: tests use the pure token reader against its fixture file only.

## A44 line protocol

CR, LF and CRLF probes each emit exactly one final LF command delimiter after replacement; CRLF yields two spaces as expected by the supplied test. NUL and Unicode U+2028 remain literal in the byte stream, with no added LF. Their downstream parser behavior is untested, so no extra-command claim is made. Actual music process NOT_RUN.

## Scope and evidence

Verbatim selected production declarations from adapted complete source, returned wrapper/support, exact test mains, mutation sources as extracted production, normalized source patches, hashes, compiler argv/logs, runtime logs, runner logs and boundary probes are included under independent/. No full native module/AppKit/camera/network/music-process/archive-decoder/quit lifecycle runtime claim. Exact full-source hashes are per row in RESULTS.json. All work remains engineering validation, not owner approval/import.
