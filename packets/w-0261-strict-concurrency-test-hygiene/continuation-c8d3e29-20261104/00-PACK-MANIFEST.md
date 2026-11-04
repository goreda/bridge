# W-0261 minimal reviewer pack - PUBLIC-designated review continuation
Prepared 2026-11-04. Same work item W-0261 (H-0495/H-0537 review continuation), not a new ID.
Scope: minimal bytes for the H0540 evidence requirements (item 1 acceptance-run logs, item 2 A3 site notes) + the source diff and provenance record. No source change, no rerun performed.

## Contents
1. c8d3e29-w0261-unit-repair.diff - actual 3-file diff of c8d3e29e4ad6bc393031aa63c06d181006790a09 vs its pre-image, limited to Sources/race-witness-tests/RaceArms2.swift, Sources/race-witness-tests/main.swift, Tests/AudioPacingTests/AudioPacingTests.swift.
   sha256 d56a053ec1eadfcce38933ba739085a14e9a5f396a2b7289bca08c70194c3893
   Pre-image pins: this diff applies BYTE-CLEAN to the packet's published baseline files and yields exactly the integrated bytes. Machine-verified 2026-11-04 (git apply against baseline bytes, sha256 of results):
   baseline RaceArms2.swift        sha256 c82882b8ef189d1389108834b00755705e3a218289b4d0beba754e995e03f73f -> 9598a70c3fc3536f207761698656e90c9f69315670fe62fe89a22f86ba4d4ed2
   baseline main.swift             sha256 5667a37dc37eb7598d90267673e369e7194becb977c9d86f838c378626a3d788 -> 818c6aadbb7930d03978ca505fd0a7070e7fdf8f54c91c086dc7c7cf0d618f64
   baseline AudioPacingTests.swift sha256 2ef8056aea209fadc3a5de21378957bd82a82fb6da8eeb564540d3c9af390258 -> 89d31a659143552452a8dc1a3640101f6d09f37d980801aee8e09e9ecd8f8fcc
2. w0261-c8d3e29-a3-site-notes.md - the A3 assertion-preservation site notes (H0540 item 2). sha256 7a04b1d65a7c3fb048d24659489187defc676b1ced031fed60dc0fb082d3a823
3. w0261-c8d3e29-provenance-note.md - provenance record (commit chain, unavailable historical tree, rebuild base pin, byte-identity mapping, evidence coverage/gaps). sha256 0edcc55aafd375aa2e77d75bcc877789dd06343a9e210e09efb321e51a442819
4. logs/ - the 4 executed gate logs, sanitized (mapping below).

## Explicit gaps
- Historical pre-repair tree unavailable: the pre-repair commit 99ecf081c3af2ed1e65317814f72e5cda37d4fbf and range 4bb068cc..e399471 are not in the current repository history; their tree state is unavailable. Current verified rebuild base pin 63a413082e71ec7d3b15be1756048a2e751e253f: its 3 unit files are BYTE-IDENTICAL to the published baselines above (machine-verified). Unavailable: the historical pre-repair whole-tree state. Preserved and in this pack: the executed gate log bytes (logs/) and the current integrated repair diff, which applied to the published baselines yields exactly the integrated bytes (machine-verified above). The A3 notes reference call-graph sites in two integrated-pin package sources beyond the 3 changed files (see callgraph/ below); comment-sanitized derivatives of those sources are included in THIS packet for review; the diff alone is not the full review surface for those references. The four logs are product command output (build/test/run/provenance commands); only venue absolute paths are tokenized per the mapping below.
- Race-witness executable count: 228 check-PASS results (checks 6, 16, 18-69, 77-250), NOT 232. 232 was a raw PASS-string count including footer/ARM-STATUS lines.
- B-T1: no gate log contains an executed swift --version / language-mode probe; header assertions are not promoted to executed version proof anywhere this evidence is used. The actual probe executed historically (original artifact compiler-version-ee406555.log) but its bytes are not part of the current evidence set. Effective mode is SOURCE-DERIVED (Package.swift tools-version 5.9, no swift-version/strict overrides, manifest sha256 ee2bd3a5893fc1f064500b783d0dfa950ef3544a0da2142ab09c3c2a88c19336 recorded in the provenance log), NOT an executed mode probe. Venue facts supported meanwhile by the published TOOLCHAIN-FACTS.md (sha256 4024500c8da68a0e6154f430a4544b47f42d8dadfe88527399aebd0baa30a146) plus the executed logs below, with this byte gap explicit.

5. callgraph/ - comment-sanitized derivatives for the A3 call-graph claims, based on c8d3e29e4ad6bc393031aa63c06d181006790a09. NOT byte-identical source. Only internal review-history labels in whole-line comments changed; executable-bearing lines and line counts are unchanged. Original pin-exact files remain private. Original -> derivative hashes:
   - TimingLedger.swift - full-file derivative, Sources/GorAVPlaybackCore/TimingLedger.swift, 699 lines, original sha256 83d46c306285ec8c87e08b42b59eddd55b2eeeccc73d157213862b075b6a6c7d -> derivative sha256 698b5ddbe685753d1b398f4fe296fdabdf43af9cdd21773110610049e7528bc5. Supports the RW20 clock confinement claim: clock() is invoked only synchronously (init :95, append :117 while holding its NSLock :81); no internal Task/queue/thread.
   - PlaybackCore-FramePump-L531-1088.extract.swift - comment-sanitized extract, Sources/GorAVPlaybackCore/PlaybackCore.swift lines 531-1088 (the complete FramePump actor; no FramePump extension exists elsewhere in the file), original sha256 b256ad99a08d5f4e3265277b33d0824afa0cabb28c8c9fe5a7f35cd17c1ff3aa -> derivative sha256 2e18a4d544bddd991cc1ec903c85cba9725f29618de619c03cc0805b524d9ca7; full-file sha256 584f22a0081afcac6dc0b9966a927161b1dd63ce140174dd8d7f2883ce696354 (1196 lines). Supports the WaitsBox callback-ordering claim: onWait is a private @Sendable async closure (:624) invoked with await inside the actor (:609, :853, :1052); run() :768 is an actor method.
   Other files referencing TimingLedger/FramePump exist at the pin (Mac shell, other test targets) but are not needed for these two claims.

## Sanitization (transparent, original hash mapping)
Replacement rules applied to logs/: the build-root absolute path -> $FFBUILD ; the product-root absolute path -> $GORAV. No other bytes changed. The original/sanitized sha256 mapping below is the transparency record; original runtime absolute paths are not part of this pack.
original sha256 -> sanitized sha256
34c1041784f3dbc45c2be0b025aecaae2049831aff31c97db03ab5c4bafadd7f -> 98d53108bee0cd7f88f6c26490904114406f09e59afcbd2c6bb3bf975316982b  build-tests-ae35565a.log
78972409395d37558cee29a13bb33ce3f2f04c0a9b32ceda24ea4eae110e734d -> f916327afc0f38ace5900da1b23892d29d08d188266372ba3f3b13c8ee1f1eda  swift-test-814a8b69.log
400aab2f730a25c0b79e89386ba7422533a5ecdbea8197db2a30b5c508762ec9 -> 400aab2f730a25c0b79e89386ba7422533a5ecdbea8197db2a30b5c508762ec9  postrun-provenance-815b4de4.log (no venue paths present; unchanged)
702037a3efddfceab69af3d28386ba1927f51ee0f542a34891595472aa6f8df5 -> b20bdef98e554a03736543f82171c714f8c186168c92d546d87d414917e9a9e5  race-witness-runtime-6ebed44a.log

## Log header assertions (verbatim facts, not executed-probe proof)
- build-tests-ae35565a.log: "swift build --build-tests ... (OFFICIAL FULL UNTRIMMED @ c8d3e29e4ad6bc393031aa63c06d181006790a09, Swift 5.10.1 RELEASE x86_64 Linux, FFmpeg 894da5ca bit-identical rebuild)"; build succeeded.
- swift-test-814a8b69.log: "swift test ... (OFFICIAL FULL UNTRIMMED SUITE @ c8d3e29, no filter, no exclusions)"; suite passed.
- postrun-provenance-815b4de4.log: HEAD = c8d3e29e4ad6bc393031aa63c06d181006790a09; Package.swift sha256 ee2bd3a5893fc1f064500b783d0dfa950ef3544a0da2142ab09c3c2a88c19336; clean working tree except .build/.
- race-witness-runtime-6ebed44a.log: "swift run race-witness-tests ... (SUPPLEMENTARY runtime, pure PlaybackCore Linux-safe, @4b93230 = c8d3e29 sources)"; 228 check-PASS results.

## Comment sanitization verification
- TimingLedger.swift: changed whole-line comments at derivative lines 1, 33, 87, 193, 206, 242, 277, 335, 357, 454, 470, 511, 518, 542, 590, 662. Line count preserved. All other lines are byte-identical, including strings and inline comments, so executable tokens are unchanged. Non-comment-line comparison sha256 2e7d1067cd73db21be5900ab50246048a3d48206292a98abc506e1ae8f1b3b59.
- PlaybackCore-FramePump-L531-1088.extract.swift: changed whole-line comments at derivative lines 95, 98, 138, 160, 165, 245, 249, 281, 291, 297, 331, 383, 457, 531. Line count preserved. All other lines are byte-identical, including strings and inline comments, so executable tokens are unchanged. Non-comment-line comparison sha256 b6dff252dc0e7d9814736846dbacf541398f1899482577dd6577055a96251fa9.
- No test, build, version probe, or product run was performed for this continuation. A3 is an analytical claim for reviewer assessment, not acceptance. No reviewer-diff-alone rerun or 171e consumption/closure is established by this packet.
