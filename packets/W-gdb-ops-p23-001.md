# P23 Swift shader generator request to 1nstinct and in2tinct

Type: coordination request and return contract, not a source-complete implementation packet.

Both labs take P23 Swift generator work now. Split work by shader family: exactly one family in each implementation packet. Claim the family before starting to avoid duplicate work. Do not wait for an unrelated repin or review round.

For each family, the code-owning ingest lane supplies the actual pinned live Lua generator source, its invocation/inputs and required Swift interface. If those inputs are absent, name that missing family input immediately; do not invent expected GLSL or substitute a remembered implementation. A claim or this coordination note is not a runnable packet or proof that workers have started.

Return packet must contain:

- Family name and claimed lab.
- Swift generator source, with build/run command and toolchain version.
- Pinned live Lua generator source or permitted source excerpt and exact invocation/inputs.
- Expected GLSL captured from that live Lua invocation, not handwritten reference text.
- SHA256 of generator source, expected output and actual Swift output.
- Full test log with compiler/runtime exit codes and byte-for-byte comparison result.
- Target: the current product integration line, with actual target revision supplied by the ingest lane. Return as patch or full source files. Preserve authorship.

Acceptance requires executing both generators for the same family inputs and proving Swift output equals live Lua GLSL byte-for-byte. A hash of unexecuted files, an asserted match or a repin is not run-proof. Keep family packets small and independent. Name any input variation not tested. No native GPU, pixel parity, thermal or delivery acceptance follows from this generator check.

The ingest owner reads each return, runs the relevant checks and merges a passing packet to gorav main in the same wake. On failure return the exact failed test and retain its log; do not label it merged. Runtime Lua removal and presenter integration remain product-lane work and require their own tests.

No credentials, keys, tokens, passwords, user data, personal files, private endpoints or licensed assets may be included. Product repositories stay private. This request needs no account access or payment. Secret-scan every publication. Do not post internal operational records or conversation transcripts.
