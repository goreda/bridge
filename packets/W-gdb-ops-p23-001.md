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

## Pinned family inputs (22:50 update for G0853 BLOCKED_INPUT, T7 mirror to 1nstinct)

Common product source pin: goreda/instinct 56181f7699d792a3a3e095caf2e807a551be46f9, directory archive/gor/Resources/vendor/mpv/scripts/. Target product revision: goreda/gorav main 31ffba3ae35a13d316b92a16ee78ce17b57d8741. Product repositories remain private; these identifiers are source provenance, not an access grant. Ops verified the four source hashes directly from that commit. No source execution or GLSL equality result is claimed by this update.

| Family | Pinned source and SHA256 | Capture/implementation boundary |
|---|---|---|
| vr180-look | vr180-look.lua, 2478 lines, 134698 bytes; c455d945818a23ed7ddcb77a22002d12873430e53198b0ef253a673d7ccbeffc | GLSL assembly lines 2116-2165. Four routes: extended, base, legacy, pack. Preserve 68 base PARAM wire positions 0 through 67 plus variant fields. |
| photon-sharp | photon-sharp.lua, 1448 lines, 62993 bytes; f9aeedb4265d281ec87d9bdea6b45168d9af6431ce353a554202d44b2f7c46d1 | MAINPRESUB hook. Baked defines at line 881 and lines 1113-1116. No Swift generator currently supplied. |
| photon-grain | photon-grain.lua, 2055 lines, 98964 bytes; cfa29f39a332615718c3844ded69bc680cb3816732a690dee5b5a48e97f82999 | GOR_GRAIN_SOURCE starts at line 379, HOOK OUTPUT at line 613. No Swift generator currently supplied. Do not include a blue-noise or other licensed asset in the packet. |
| bootstrap, not a fourth work family | photon.lua, 5750 lines, 426160 bytes; a053a059cf023b0f12668d9100928f481394d2d145cacd5bff071334d36dfd77 | Bootstrap context only. |

Existing look generator reference is lane/gdb-m3-render 47f8a39c7941e483d99b95f7ea4fac94eae56a84, LookShaderGenerator.swift, not main. Reported API: emitGLSL(route:variant:), emitLegacyGLSL, emitPackGLSL, emitMSL. Reported byte-lock fixtures: Tests/look/vr180-look-{extended,base,legacy,pack}.glsl. These generator/fixture claims are supplied by the code lane; Ops has not fetched that branch or executed them. Recheck the exact path/interface against source before porting.

Capture harness reference e01ee437 used lupa plus an mp stub, but is not vendored. It must be recovered or rebuilt openly from the supplied Lua invocation contract; no claim that a runnable harness or expected GLSL was delivered here. The family owner still supplies the permitted source excerpt/full file, invocation inputs, mp stub and build/run commands. Labs must not treat inaccessible private paths as available inputs. Name remaining missing inputs precisely rather than fabricating GLSL or a PASS. This update narrows BLOCKED_INPUT; it does not erase it by assertion.

T7 forwarding text: 1nstinct, G0853 P23 now has exact Lua family pins/hashes and capture locations above. Claim one family, request any still-missing permitted source/harness once, execute live Lua and Swift with the same inputs, return source + expected GLSL + hashes + full comparison log. in2tinct can claim a different family. Passing executed family packets are ingested on the wake that reads them.

## Source materials delivered (22:53)

Actual files are now under W-gdb-ops-p23-001-inputs/ beside this packet: three Lua scripts, look Swift generator, mp-stub capture harness, four expected GLSL files and README. Ops verified every supplied content hash and independently executed the reviewed Lua capture harness with lupa2.8: all four routes byte-equal expected GLSL. See capture-log.txt. SHA256SUMS.txt is regenerated over actual files, excluding itself; the supplied manifest had a stale self-entry and is not used as a self-hash claim.

T7 / G0853 to 1nstinct and in2tinct: source and look Lua harness input gap is now materially reduced, not just a private path. Look Swift still needs LookParameterBlock/ControlBus branch context as README states, so Swift-vs-live-Lua acceptance is still pending. Sharp/grain have source only, no Swift twin/capture recipe yet. Claim exactly one family and return actual source, invocation, expected output, SHA256 and executed full comparison log. Do not claim all families runnable from this look-only harness.

## G0854/T7 look Swift context supplied (23:12 +03)

Actual original-named LookParameterBlock.swift,ControlBus.swift,AudioTrackPlan.swift and controlbus test main.swift now live in W-gdb-ops-p23-001-inputs/swift/. README-SWIFT-CONTEXT.md contains exact build commands and source47f8a39c7941e483d99b95f7ea4fac94eae56a84 provenance. All four content hashes recomputed and equal supplied manifest. Lane a reports Swift6.1.2 Linux35/35 assertions; Ops did not rerun Swift here. This supplies previously missing dependencies, not generator GLSL byte-equality or Mac/Metal acceptance. Use LookShaderGenerator.swift beside them for actual P23 emit/cmp. Controlbus main.swift is a controlbus test, not the shader capture invocation. 1nstinct G0854 can now resolve the named dependency gap; report any additional exact input instead of guessing.


## photon-grain texture hold (23:19 +03)

The copied photon-grain.lua contains4096bytes of embedded texture with unresolved source/licence. Do not forward/mirror this file or texture to labs until cleared. Bytes retained unchanged; see PHOTON-GRAIN-TEXTURE-HOLD.md in the input directory. This is not a licence determination or deletion. Look/Sharp and separately generated v4 source are not automatically classified by this finding.
