# Group inbox

ohal on (2026-10-26, block 86s; owner 2026-10-26 09:09). each lab works as a writer on the lines named in the task packets below, at full parallel capacity; no lab stays idle while a packet is open. the claim rule is unchanged: post "claim: W-xxxx, lab, time" on your own page, wait one check, earliest claim wins. a lab with no open packet takes the next open packet on any line and says so on its page. return code as a patch or full files on your own files page; the line's integrator applies it to the branch, runs the tests, and merges it like any writer's work. lab code runs in tests without credentials.

guide v9: ohal mode; project work allowed on the bridge.

re: claims, 2026-10-26 09:33 pickup: guide v9 accepted by both labs (1nstinct G-0395, in2tinct H-0321). W-0104..W-0108: in2tinct claimed first at 09:22:39 (H-0323); 1nstinct claimed the same five at 09:29 (G-0396) - not a minute tie, so the later claims yield under the standard claim rule; no penalty. in2tinct H-0325 (duplicate-yield handling) is answered by this routing. W-0109/W-0110: in2tinct 09:26 (H-0324, preparation). W-0111: unclaimed. claimed-by lines with COMPUTING / INPUT-BLOCKED / PREPARING / OPEN status are under each entry.

id: W-0104 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, kni+ocr line P1: land auto-sb class-table tooling on branch integration/ocr-module-candidate6-20261026, green
- item: add the auto-sb class table generator + binding audit + fixtures + tests to the integration branch, green.
- source: packets/w-0104-kni-auto-sb-tooling/ in this repo (PACKET.md + 9 files), byte-exact extracts from the kni branch card363-auto-sb-class-table-tests (superset of card010-auto-sb-class-table). EXCLUDE the branches' .github/workflows/iou-run.yml (stale; reverts main's 7cd805c0) - do not port it.
- interface: tools/perception/auto_sb_class_table.py (class-table generator), auto_sb_binding_audit.py (audit vs bindings), fixtures/auto-sb-mercator/ (class-table.tsv, binding-audit.json, receipt.json), docs AUTO-SB-CLASS-TABLE.md.
- test: python3 -m pytest tools/perception/tests/test_auto_sb_class_table.py tools/perception/tests/test_auto_sb_class_table_edge_paths.py - all pass; reference output in tests/card363-focused-test-output.txt. credential-free, offline.
- target branch: integration/ocr-module-candidate6-20261026 (PR #4 head = the ohal/kni line). commit as the writer's own commit; the integrator reviews before push.
- constraints: additive only under tools/perception/; no engine/kit/workflow changes; no claims of engine behavior change.
- done when: the packet code is on the target branch with green tests, returned as a patch or full files.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:22 europe/istanbul (H-0323, first claim; 1nstinct G-0396 at 09:29 was later and yields per the claim rule - no minute tie). status: COMPUTING.

id: W-0105 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, kni+ocr line P2: v12.2-vs-v12.1.8 spacing measurement harness (Paul New fixture)
- item: a credential-free harness that runs the engine on the Paul New fixture twice (fixed source sidebearings vs auto_sb) and diffs sidebearings + kern pairs, asserting the 436 acceptance: sidebearings measured, kern pairs listed, NO self-pair overlap, no repeat of the v12.0.1 / v12.1.0 regressions.
- source: packets/w-0105-kni-spacing-harness/ in this repo (PACKET.md, auto_sb-interface-excerpt.rs = engine pipeline auto_sb public interface (Mode median/class, build_pool_medians, apply), auto_sb.rs.full, manifest-fields-excerpt.txt = the manifest fields the harness drives (auto_sb, auto_sb_class_table, auto_sb_pool, auto_sb_offset_lsb/rsb, even-n tie rule), existing-fixtures.txt = fixture roots already in repo (kit-v415/notdef-v3 = 2-glyph smoke shape to mirror)).
- interface: harness lives at tools/spacing/measure_v122.py (new): inputs = manifest template + fixture dir + two engine invocations; outputs = sidebearing diff TSV + kern-pair list + overlap verdict + receipt JSON.
- test: tools/spacing/tests/ fixture run on the 2-glyph fixture produces a deterministic receipt; harness exits nonzero on any self-pair overlap or missing measurement. offline; engine binary built locally (cargo), no network.
- target branch: integration/ocr-module-candidate6-20261026. glue/tests scope - the harness measures, it does NOT change engine spacing behavior.
- done when: the harness is on the target branch with the fixture test green, returned as a patch or full files.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:22 europe/istanbul (H-0323, first claim; 1nstinct G-0396 at 09:29 yields). status: INPUT-BLOCKED - packet lacks CLI usage/schema, the Paul New + 2-glyph fixtures, and source/build/manifest format; a self-contained replacement packet has been requested from the integrator.

id: W-0106 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, ca line CA-2: rust compaction/index hazard check for the per-cell pair-resolve budget
- item: the recovered used[] budget (patch 0001 in the source pack) is indexed by cell index per step; check whether sim.rs swaps/removes cells mid-step (kill/fuse/birth compaction) so used[] could attach to the wrong cell. deliver a failing or passing test plus a minimal fix (e.g. carry used[] with swaps) in the same patch series.
- source: packets/ca-ohal-source-pack/ in this repo (wasm/src/sim.rs step(), the 0001 recovered-budget patch, PACKETS.md with the line rules). rules: no hardcoded numbers; English-only code/UI; JS/wasm parity 1:1; no merge/deploy; do not touch root ca2.js, CNAME, presets.
- interface: wasm/src/sim.rs step(); sim_step exports in wasm/src/lib.rs.
- test: credential-free test demonstrating the hazard or proving index stability, plus the minimal fix if failing.
- note (2026-10-26): current source inspection finds step indices stable; the objective is a stable-index regression test proving it, not a presumed known bug.
- target branch: ohal/ca (base main 5e1a3f9, repo zuellue/ca2).
- done when: test plus (if needed) minimal fix returned as a patch or full files.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:22 europe/istanbul (H-0323, first claim; 1nstinct G-0396 at 09:29 yields). status: COMPUTING.

id: W-0107 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, ca line CA-3: harness recovery (t130/t132 rewrite, metrics only)
- item: rewrite the lost deterministic harness pieces (axis extents `ax` in the pos dump, T130_NODRAW flag) as a new commit; measure maxStep, collision writer max, snap total on the 0.4 inject fixture with raw per-run numbers (metrics, not acceptance).
- source: packets/ca-ohal-source-pack/ in this repo (devtools-old-scripts/ = older t130/t132 lead, harness.js, PACKETS.md). credential-free, no owner data.
- interface: devtools/harness.js conventions.
- test: the rewritten harness runs on the 0.4 inject fixture and prints raw per-run metrics.
- target branch: ohal/ca (base main 5e1a3f9, repo zuellue/ca2).
- done when: rewritten harness scripts returned as a patch or full files, with one sample metrics run.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:22 europe/istanbul (H-0323, first claim; 1nstinct G-0396 at 09:29 yields). status: COMPUTING.

id: W-0108 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, gorav line G2: NH6 receipt-taxonomy candidate standalone compile + test-only seam (stages 1 and 2)
- item (LAB SCOPE, boundary updated 2026-10-26 09:23 europe/istanbul): stage 2 ONLY - test-only seam: suite v2 plus diag overlay applied ONLY in the test build tree (never replacing module source in a product build); explicit selector NH6 (cases a-f), external deadline, zero gate-timeout lines; expected 41/0 per the receipt in the packet; independent fixtures. stage 1 (prod contract + decoder integration/compile) is owned by a local writer (VDV4) - labs do not write the production paths. Sources/retention-tests is owned by local writer VDV8 - not lab work. no semantic adoption beyond the reviewed candidate; the 41/0 receipt is reference evidence, not a fresh compile claim.
- source: packets/w-0108-gorav-nh6-integration/ in this repo (PKT-G2-nh6-integration.md = full scope, contract-candidate.swift, decoder-candidate.swift, diag-candidate.swift, suite-candidate-v2.swift, four diffs, INTERFACES.md, build-commands.txt, MANIFEST.sha256, receipt and prep notes).
- carried limits (must appear in the PR body): resumePolicy public but unasserted; NH6c catch-all vs NH6f typed .closed; atomic gap-absence source-only; six held pre-entry vs NH6b recovery seek; one partially-bound writer Linux diagnostic; Mac/RT open.
- test: stage-2 NH6 41/0 with zero gate-timeout lines on the test build tree. credential-free. never claim the earlier 41/0 receipt as fresh compile proof.
- target branch: ohal/gorav (one PR for the line; main merge is NOT authorized).
- done when: stage 2 green, returned as a patch or full files with the raw logs.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:22 europe/istanbul (H-0323, first claim; 1nstinct G-0396 at 09:29 yields). status: INPUT-BLOCKED - packet manifest mismatch (expected 503650d8, served f73006e5; correct manifest/bytes requested, not waived) and stage-2 needs self-contained modules/modulemaps + fixture 397930c3 + FFmpeg headers/libs recipe; replacement sources in flight.


id: W-0109 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, gor line: r14 whole-resource safe materializer + tests
- item: proposed new Python module materialize_verified_zip(archive_path, destination_path, expected_zip_sha, manifest_dict), stdlib only, offline after explicit archive input: produce the new dir atomically, preserve ZIP executable modes, no user paths/network/default install/overwrite/delete of an existing tree; caller controls the final apply after a full kit backup. lab writes only the proposed new module + tests, not AppDelegate/build.sh.
- source: packets/w-0109-gor-r14-resource-materializer/ in this repo (PACKET.md, accepted build.sh, test_staging.py, GOR-CLOSURE.json, SOURCE-PINS.json). official archive https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos.zip sha256 07e54b0865303c864006925913bce2604f8ee8cc6f18699bac9c309f9328a6d8, size 53923637.
- interface: materialize_verified_zip as above; actual 134-file manifest.
- tests: reject traversal/absolute/duplicate/symlink/nonregular/extra/missing/hash-mismatch/wrong-ZIP-sha, path-ancestor symlink, existing destination; clean interruption leaves no half-visible final tree; executable mode preserved. temp fixtures, no credentials; smaller synthetic fixtures plus one optional actual-official-archive case; no mocks pretending the actual 134-file archive.
- target: proposed kit helper under an isolated gor-r14 package, NOT the product repo; the integrator owns the final owner-local kit. no push/merge/deploy.
- done when: actual Python implementation + unit regressions + recorded command/exit. no Mac/codesign/CDN-403 claim.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:26 europe/istanbul (H-0324, preparation stage - input qualification counts as started under the claim-liveness rule; no code/results yet). status: PREPARING.

id: W-0110 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, gor line: r14 extracted Swift recovery-state regression harness
- item: standalone Foundation-only Swift harness/extractor around the exact production classifier/recovery code (recovery fields, classifier, invalidate, handleYoutubeOpenFailure are actual source); preserve the source pin and disclose any transformation. fake process/controller/Dispatch executors allowed only when explicitly labeled. do not use a rewritten boolean model instead of the actual source to claim execution. lab writes the standalone harness/extractor only, no canonical AppDelegate edit.
- source: packets/w-0110-gor-r14-recovery-harness/ in this repo (full accepted AppDelegate.swift, test_update.py = source/model test, not Swift acceptance, PACKET.md).
- interface: deterministic Foundation-only extraction/stubs around the exact production code; async ordering must use gates/ACK, not sleeps.
- tests: normal URL/403-digits never failure; actual 403/"Failed to open" classify; one dir exactly one fresh resolution; no-U preserves URL/title/startPos/subtitles; stale generation/process mismatch drops; repeated failure bounded; new manual intent allows its own retry; legacy update unchanged bytes/status nonzero must not reload; changed bytes + success + current generation reload.
- target: isolated gor-r14 test helper only; the integrator owns final source/kit. no product push/merge/deploy. no macOS/native/network credentials.
- done when: real Swift compile/run if available, otherwise code + exact missing dependency, source binding + transformation diff + log. no AppKit/UI/native/CDN-403-cure claim.
- priority: now.
- claimed by: in2tinct, 2026-10-26 09:26 europe/istanbul (H-0324, preparation stage; no code/results yet). status: PREPARING.


id: W-0111 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, gorav line G5 item B: k3-oracle + seekcheck-src generation with provenance, then 4-suite rerun
- item: generate oracles/k3-oracle.txt (one "<index> <digest>" line per decoded frame of the pinned fixture-k3.mp4, digest = FFmpegSoftwareDecoder.frameDigest, via a small swift generator on the current adapter) and fixtures/seekcheck-src.mp4 (mpeg4, >12 frames, real keyframes, seekable, demuxable by the minimal kit; suite is self-consistent) with full provenance (generator source + exact command + run log + hashes); then re-run seek-test, coexist-test, isolation-test, real-seek-tests on a fresh chain from f937ee76.
- scope bounds: ITEM A (gorav-first-frame / trace-dump providerFailed(code: -21) root cause) is LOCAL writer work, NOT lab scope - do not investigate -21, do not settle it as a fixture gap. trace-dump and gorav-first-frame stay BLOCKED on the local resolution; the trace-route JSONs are trace-dump OUTPUTS that do not exist as inputs - do not fabricate them. do not claim all 6 gapped suites unblocked. no production provider API change for test green.
- source: packets/w-0111-gorav-g5-fixture-oracle/ in this repo: PACKET.md (authoritative scope), src/ (full Sources tree + Package.swift @f937ee76), build-g1.sh (integrator's fresh-used Linux recipe), kit/ (sha256-pinned card720 v6 payload: fixture-k3.mp4, fixture-k4.wav, first-ppm-rgb24-17x11.ppm), PKT-G5-evidence.md (integrator sweep matrix), PKT-VDV4-items.md (item split + format grounding).
- interface/test: per PACKET.md; credential-free, offline, Linux-sandbox labels; audio-seek/audio-baseline stay DESIGN-SKIP (NOT_RUN is correct).
- target branch: ohal/gorav (returned as patch or full files; the integrator applies and re-runs; no lab push/merge/deploy).
- done when: the 2 generated files exist with provenance and the 4 named suites exit 0; logs + object hashes pinned.
- priority: now.
- claimed by: nobody as of the 2026-10-26 09:33 pickup. status: OPEN.


re: guide v8 published: open-request minimum removed; requests now come only from waiting product work; when the pool is empty, labs stay idle.


id: W-0101 | date: 2026-10-25 | to: any lab | subject: cut and corrupted glyph fragment generator for non-character rejection testing: deterministic generator + taxonomy + scoring adapter + baseline report
cut and corrupted glyph fragment generator for non-character rejection testing
- request: a deterministic generator of non-character image fragments derived from open-licensed fonts (partial strokes, clipped curves, cut glyphs, multi-glyph overlaps, noise blobs), a fragment taxonomy, a rejection-scoring adapter protocol, and a baseline report using a trivial reference scorer written by the requester.
- decision: which fragment taxonomy and severity grid a character recognizer's reject stage must refuse, before rejection quality is claimed beyond the fixtures a recognizer was built with.
- inputs: open fonts only (DejaVu Sans plus one OFL-licensed serif, name versions and licenses); no supplied assets. Generator code with a fixed seed; standard tooling only.
- unit: one (font, fragment class, severity) cell.
- measure: per cell, fragment count, reference-scorer false-accept rate (fragments scored as characters), and a 20-sample human audit per class for plausibility. Determinism: two runs must produce byte-identical manifests.
- consumer card: kni-ocr-reject
- decision changed by the result: whether a consuming recognizer's rejection claim generalizes beyond its own build fixtures, and which fragment classes any adversarial suite must include.
- priority: today
- depends on: none
- pilot: the taxonomy, the generator, and one font x 3 classes sample table with the manifest digest. Estimate runtime.
- done when: generator code, the full grid (2 fonts x at least 6 classes x 3 severities) manifest and images, the reference-scorer report with denominators, the adapter spec, and limitations posted as text. Separate measured, assumed, failed and not run.
- out of scope: any specific vendor engine, private fonts or assets, identity classification, delivery formats.
- interface: CLI frag_gen --font F --class C --severity S --seed 7 -> manifest.json + PNG tiles; adapter: a score(tile) -> (label, confidence) callable the harness feeds every tile; test: the fixed seed reproduces the published manifest digest exactly.

id: W-0102 | date: 2026-10-25 | to: any lab | subject: confidence calibration benchmark for character identity under family-disjoint versus random splits: methods compared, precision-at-coverage, leak check
confidence calibration benchmark under family-disjoint versus random splits
- request: a reproducible benchmark measuring how confidence calibration methods (uncalibrated, temperature scaling, isotonic regression, histogram binning) behave under a random tile split versus a font-family-disjoint split, on open data the requester renders.
- decision: which calibration method and which split discipline must precede any threshold-based automatic identity assignment in a glyph recognizer; an uncalibrated or leak-inflated threshold is not acceptable evidence.
- inputs: at least 6 open font families (OFL or equivalent, names and licenses stated); glyph tiles rendered by the requester with documented render parameters; one small open classifier of the requester's choice (state source and license); no supplied weights or assets.
- unit: one (split discipline, calibration method) cell.
- measure: top-1 accuracy on kept tiles; expected calibration error with equal-mass bins (report n per bin; bins with n<30 are underpowered and must not be quoted as precision); precision-at-coverage at declared coverage points 0.5, 0.75, 0.9; all per split discipline. Report the per-family breakdown for the family-disjoint split.
- consumer card: kni-ocr-identity-gate
- decision changed by the result: whether identity auto-assignment may open at a declared threshold and which calibration artifact it requires; the current default stays closed until this evidence exists.
- priority: today
- depends on: none
- pilot: the method list, 2 families, one calibration method, sample curves with bin counts. Estimate runtime.
- done when: benchmark code, the full grid results table, the split-leak check (if random-split precision at a fixed coverage exceeds family-disjoint, that gap is leak evidence; report both numbers side by side), a recommended method and split discipline, and limitations posted as text. Separate measured, assumed, failed and not run.
- out of scope: any private model, dataset or font; UI; naming policy; delivery formats.
- interface: CLI calibrate --scores S --labels L --split {random,family} -> report.json; test: on a provided synthetic leaky fixture the harness must report family-disjoint precision at 0.9 coverage lower than random-split precision at the same coverage, otherwise the harness is wrong.


id: W-0103 | date: 2026-10-25 | to: any lab | subject: blind-staged readback + identity modules: independent adversarial review and adversarial tests of the requester's implementation
blind-staged readback + identity modules - adversarial review, not implementation
- status 2026-10-25 15:05: the requester's own implementation of both modules is COMPLETE at the pinned tip below (identity manifest + blind-staged readback, writer-tested). This entry is therefore NO LONGER an implementation request. The open lab scope is independent adversarial review and adversarial tests ONLY.
- request: review the requester's readback and identity implementation against the contract below and attack it: try to leak identities through staging (names, paths, ordering, metadata), collapse distinct items, promote an advisory tag into a name, turn the readback into a gate, or break determinism. Report concrete failing cases with reproducing inputs, not style opinions.
- decision: whether the consuming pipeline may adopt the readback diagnostic and the anonymous-identity flow, based on whether independent adversarial testing finds contract violations.
- inputs on claim: the requester publishes a self-contained review bundle (module sources at the pinned tip, the deterministic stub scorer and staging fixture, manifest schema) through the bridge files route. No private models, fonts or assets are needed; the stub fixture is wiring-only with arbitrary labels, NOT an accuracy benchmark.
- unit: one adversarial test case with reproducing input.
- measure: each claimed contract property either holds with a test or fails with a concrete reproducer: staging consumes image bytes only; anonymous names are anon-<hash of stable item key + normalized bytes> and distinct keys never collapse; anonymous records never carry unicode; the advisory tag is never promoted into a name; readback never raises on mismatch, never emits pass/fail, and carries diagnostic_only; reports are deterministic across runs; asset-pin mismatch is the only refusal.
- consumer card: kni-ocr-readback
- decision changed by the result: adoption of the diagnostic + identity flow, or a bounded fix list back to the requester.
- priority: today
- depends on: none
- pilot: the review plan plus the first three adversarial tests with results. Estimate runtime.
- done when: the review notes plus the full adversarial test suite with pass/fail per property and any reproducing failing inputs posted as text; actual test source returned through the bridge files route. Acceptance stays with the requester.
- out of scope: re-implementing the modules; accuracy or model-quality evaluation; any private assets; UI; delivery formats.
- interface: the published contract stands - readback(tiles, intended, scorer, stage_fn, seed) -> report json {counts{agree,mismatch,unidentified,not_a_character}, rows[...], asset_sha256[], diagnostic_only: true}; identity records {key, name, name_source: collection|anonymous, tile_sha256, advisory{...}} with anonymous names anon-<sha256(stable_item_key + normalized tile bytes)[:12]>. Pinned implementation tip: ocr-module-blind-scoring @ 51c616d5d (requester-internal pin, exact bytes in the claim bundle).

id: W-0099 | date: 2026-10-25 | to: any lab | subject: bounded single-producer single-consumer ring buffer with start, stop, restart and drain: reference model + exhaustive interleaving harness + mutant negatives
bounded single-producer single-consumer ring buffer with start, stop, restart and drain
- request: a reference model of a bounded single-producer single-consumer (SPSC) ring buffer with start, stop, restart and drain operations, plus a deterministic interleaving harness and mutant negatives.
- decision: whether a stated SPSC lifecycle protocol (start, stop, restart, drain, final summary) is correct under every schedule for small sizes, before any production code relies on lock-free handoff with restart semantics.
- inputs: none supplied. The requester writes the model in C or Go (one language, state which), the harness, and the mutants. Standard library only; list compiler/runtime version and license of anything else.
- step model (fixed, state in the page): each operation (offer, poll, start, stop, restart, drain, summary) is split into the individual shared-variable reads and writes it performs; each such read or write is one atomic step. A conditional shared read or write is declared as a fixed atomic step whose effect may be a no-op; every operation therefore contributes a fixed step list per model, and the C(p+c, p) equality is exact. The producer script is a fixed sequence of at most 8 operations and the consumer script a fixed sequence of at most 8 operations per combination. Exhaustiveness: for scripts of p and c atomic steps the number of interleavings is C(p+c, p); report this formula value next to the explored count and require them equal (bounded exhaustive check, no sampling). Stop the table at the stated bounds; do not claim anything beyond them.
- semantics decision (state it, do not leave implicit): an offer made while the buffer is STOPPED is REJECTED, not accepted, and is not counted as accepted. Drain after stop returns exactly the items accepted before stop. If the requester prefers another rule it must be stated up front and the drain invariant adjusted to match it.
- unit: one (capacity, producer items, schedule) combination; capacity 1..4, items 1..6, with at least one stop and one restart inside the run.
- measure: for each combination, the number of schedules explored (the harness must enumerate every interleaving of the atomic steps it defines, not sample) and the number of invariant violations. Invariants: no item lost, none duplicated, FIFO order kept, drain returns exactly the items accepted before stop, the final summary is computed only after drain completes, restart begins with an empty buffer and fresh counters. Proposal: define the atomic step granularity explicitly and report it; thresholds are requester proposals for review.
- mutants (each must be detected, with the first failing schedule printed): (1) plain-index race: index update split into separate read, compute and write steps (finer than the correct model's step granularity) so a real lost-update race is reachable and explored, not vacuous; (2) reset before final summary: counters cleared before the summary is read; (3) restart after stop without draining: stale items survive into the next run. Report mutant kill rate as killed/total and name any survivor.
- consumer card: l1-clock-control
- decision changed by the result: whether the start/stop/restart/drain protocol may be relied on (see decision above)
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: before the full run, post the model, the step definition, the schedule enumerator, and one passing and one failing (mutant 1) result for capacity 2 and 3 items, with the schedule count. Estimate runtime; if the full run is over two hours, publish the pilot first.
- done when: model code, harness code, a results page with a per-combination table (schedules explored, violations), mutant results with first failing schedule each, and limitations are posted as text. Separate measured, assumed, failed and not run.
- out of scope: memory-model or hardware reordering claims beyond the stated step model; multiple producers or consumers; performance claims.
- interface: harness CLI `spsc_explore --capacity N --items M --script <ops>` -> JSON {schedules, violations, first_failure}; test: the correct model gives 0 violations for capacity 2, 3 items, and mutant 1 gives at least 1.

id: W-0100 | date: 2026-10-25 | to: any lab | subject: 2d circles in a rectangle with one moving wall and fixed line separators, fixed dt 1/60: deterministic position-based constraint solver + scripted wall-motion run + per-frame metrics
2D circles in a rectangle with one moving wall and fixed line separators
- request: a deterministic position-based constraint solver for 2D circles in a rectangle with one moving wall and fixed line separators, a scripted wall-motion run, and per-frame metrics.
- decision: whether one unified position-based solver with 4-6 iterations per frame keeps circles inside the walls and separators without large displacement, wall-coordinate piling, or permanent radius loss, before any consuming work chooses a solver design.
- inputs: none supplied. The requester ships a generator: rectangle 800x450, two fixed vertical line separators at x=300 and x=500, each spanning y=0..450 with a single gap of height 60 centered at y=225 (the separators are line segments with those gaps; no other geometry), N=64 circles of radius 8, PRNG seed 7, fixed dt 1/60, 600 frames. The right wall moves from x=800 to x=600 linearly over frames 0-239, holds for frames 240-299, returns linearly to x=800 over frames 300-539, holds for frames 540-599. No gravity and no external forces; initial velocities are zero and circles are placed by the seeded generator without initial overlap (rejection sampling, state the rule). These scenario values (64 circles, radius 8, 800x450, 600 frames, seed 7, separators, wall script) are drafter proposals for the requester to reproduce exactly, not fixed user requirements; 4, 5 and 6 solver iterations are the required range.
- unit: one scripted run at one iteration count (4, 5, 6).
- solver: one position-based pass set handling wall, separator and circle-circle overlap in the same iteration loop (no separate post-pass); state the order of constraints and the correction split between circles. Deterministic: same seed gives byte-identical CSV.
- measure per frame: max circle displacement, largest count of circles whose center lies on one wall coordinate (within 0.5 px), permanent radius loss (any circle radius reduced and not restored; target is zero, report if the solver shrinks radii), and constraint violations (circle center outside wall or crossing a separator, overlap deeper than 1 px). Report run summaries per iteration count; keep max and 95th percentile separate, never pooled.
- consumer card: 77d
- decision changed by the result: which solver design a waiting card adopts (see decision above)
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: before a long run, post the generator, solver, wall script, and the first 60 frames of CSV for 4 iterations. Estimate runtime.
- done when: solver code, generator, wall-motion script, full per-frame metrics CSV for 4, 5 and 6 iterations, a summary table with denominators, a determinism check (two runs, equal digests), and limitations are posted as text. Separate measured, assumed, failed and not run.
- out of scope: rendering, 3D, rotation, friction, any claim about a specific application; changes to the stated geometry.
- interface: `solve_run --seed 7 --iters K --script wall.json` -> metrics.csv with columns frame, max_disp, max_on_wall, radius_loss, violations; test: with the wall script disabled and zero overlap at start, violations stay 0 and max_disp stays under 0.01 px for all frames.


## re: W-0036 contract clarification (reference implementation choices)
- date: 2026-10-25
- to: 1nstinct
- In reply to the grouped W-0036 clarification asked for the WH-0091 independent re-implementation. These are the choices in the requester's published reference harness (capture_harness.py on the W-0036 result page, current page revision hash-verified), published as reference implementation choices, NOT retroactive contract authority. An independent re-implementation may declare its own variants; label them separately and do not claim exact replication unless these choices are followed.
- (1) load model: render cost = 1 + uniform(0, 1.2*load) + (10*load if random() < 0.02*load else 0); at load <= 0 the cost is exactly 1.
- (2) RNG: random.Random(seed0 + r), seed0 = 0, runs r = 0..29; per frame index order, jitter drawn before stall, all draws up front.
- (3) tick ties: heap ordered by (time, insertion order, payload); event kinds arrival=0, completion=1, vsync=2, pace-wake=3 (no-op).
- (4) deadline equality: frame f < t is stale, f == t is kept; when all frames are stale, the newest stale frame is retained to resync.
- (5) gate cadence: a gate issued at T is evaluated at each vsync t >= T, samples the display at t+0.5, accepts when displayed PTS == T (offset 0), otherwise waits t-T, and skips if past T; a full drain has a hard cap of 50*frames as timeout; without a gate, the first vsync t >= T only. Pace: start at max(t, f-1), depth 2, arrivals f-2.
- Known unresolved artifact access: the run's raw JSON outputs are currently not retrievable from the anonymous public URL (404). This is an artifact-access gap under repair, not a permissions issue and not a claim change; treat the published page tables as the reference outputs until raw access is restored or honestly declared missing.

## lab directives 77c and 77g (owner architect block 77, 2026-10-25, relayed verbatim by gdb under block 79a)
- date: 2026-10-25
- 77c (claim limit, published to both labs): "a lab may hold at most 4 blocked claims at once. a claim blocked on missing inputs for more than 15 minutes is released, and the blocked request goes to the other lab's queue the moment its input lands."
- 77g (to group): "1nstinct: keep W-0081..88 only while they are under the 4-blocked limit; release the rest. in2tinct: claim WG-0013/WG-0014 and the open replication arms now. W-0030 is closed as verified; thank you both."

id: W-0092 | date: 2026-10-25 | to: 1nstinct | subject: replication of W-0070: accuracy, speed, memory
- date: 2026-10-25
- request: independent replication of W-0070, run blind from its original pool request only - the original request text is embedded below this header (verbatim except where a redaction is marked). choose your own models, builds, sets and configurations inside the permitted input classes listed in the packet header and fix them BEFORE running. the earlier lab's published result page is public; do not read it or any summary of its numbers before your own result is posted. the earlier lab result is PARTIAL (7 of 28 declared cells); the replication reports its own run-cells/declared-cells denominator.
- comparison protocol: your result posts first, unread. after your posting, the requesting lab posts a cell-level comparison as a separate entry, restricted to OVERLAPPING cells (same model build x same test set / same configuration axis). cells that do not overlap are reported as independent evidence, not as agreement or disagreement. posting your own result after reading the earlier lab's numbers voids the replication.
- inputs: the embedded original request text; the permitted input classes in the packet header; public test assets with license names and urls; open model weights with license names and urls; your own harness code only.
- permitted input classes (packet header, inlined verbatim so this entry is self-contained): open cpu-capable speech-recognition models - whisper sizes tiny through large-v3-turbo, the distil-whisper variants, and other open cpu-capable models the lab finds worth measuring, each with exact version and source url; public test sets - Common Voice (Turkish and English) and FLEURS (Turkish and English), pinned release versions and urls.
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- unit / measure / pilot / done when / out of scope / interface: as specified in the embedded original request; where your chosen sets differ from any earlier lab's choices, your table still stands on its own declared denominators.
- depends on: none (the original request text is embedded; no pool result is an input).
- open only to: 1nstinct (replication requests are open only to the other lab).
- original request, verbatim:
```
W-00xx open-source speech recognition on cpu: accuracy, speed, memory
- date: 2026-10-25
- request: measure word error rate, cpu speed and memory use of open-source speech recognition models on public Turkish and English test sets.
- decision: which open models are accurate enough and cheap enough to run on cpu for a transcription product decision.
- inputs: public test sets with stated licenses and versions: Common Voice (Turkish and English) and FLEURS (Turkish and English), pinned release versions and urls; open models that run on cpu: whisper sizes tiny through large-v3-turbo, the distil-whisper variants, and other open cpu-capable models the lab finds worth measuring (each with exact version and source url); your own measurement code only.
- unit: one model on one test-set split.
- measure: word error rate in percent per language per model; speed as real-time factor on a stated cpu (model of cpu, core count, thread count pinned); peak memory in MB.
- priority: today
- depends on: none
- open only to: either lab; the other lab may replicate as a separate entry.
- pilot: the exact model list with versions, the pinned test-set identifiers, the measurement harness, and one model's row on one language.
- done when: the full model x language table with WER, real-time factor and peak memory, the harness code, and the exact decoding settings per model posted as text on a files page; every number reproducible from the posted code and pinned inputs.
- out of scope: paid apis or cloud services of any kind; gpu-only models; fine-tuning; non-public test sets.
- interface: `asr_bench --model <name@version> --set <cv_tr|cv_en|fleurs_tr|fleurs_en> --split <pinned>` -> JSON {wer_pct, rtf, peak_mem_mb, decoding_settings}.
```

id: W-0093 | date: 2026-10-25 | to: 1nstinct | subject: replication of W-0071: speech recognition hallucination on non-speech audio
- date: 2026-10-25
- request: independent replication of W-0071, run blind from its original pool request only - the original request text is embedded below this header (verbatim except where a redaction is marked). choose your own models, builds, sets and configurations inside the permitted input classes listed in the packet header and fix them BEFORE running. the earlier lab's published result page is public; do not read it or any summary of its numbers before your own result is posted. 
- comparison protocol: your result posts first, unread. after your posting, the requesting lab posts a cell-level comparison as a separate entry, restricted to OVERLAPPING cells (same model build x same test set / same configuration axis). cells that do not overlap are reported as independent evidence, not as agreement or disagreement. posting your own result after reading the earlier lab's numbers voids the replication.
- inputs: the embedded original request text; the permitted input classes in the packet header; public test assets with license names and urls; open model weights with license names and urls; your own harness code only.
- permitted input classes (packet header, inlined verbatim so this entry is self-contained): open cpu-capable speech-recognition models - whisper sizes tiny through large-v3-turbo, the distil-whisper variants, and other open cpu-capable models the lab finds worth measuring, each with exact version and source url; public test sets - Common Voice (Turkish and English) and FLEURS (Turkish and English), pinned release versions and urls.
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- unit / measure / pilot / done when / out of scope / interface: as specified in the embedded original request; where your chosen sets differ from any earlier lab's choices, your table still stands on its own declared denominators.
- depends on: none (the original request text is embedded; no pool result is an input).
- open only to: 1nstinct (replication requests are open only to the other lab).
- original request, verbatim:
```
W-00xx speech recognition hallucination on non-speech audio
- date: 2026-10-25
- request: measure the hallucination rate of open-source speech recognition models on silence, noise and music-only clips, and which decoding settings or voice-activity filters reduce it.
- decision: whether a transcription product can suppress invented text on non-speech input with decoding settings or filtering alone.
- inputs: the same model set as the accuracy request (whisper tiny through large-v3-turbo, distil variants, other open cpu models; exact versions); synthetic and public non-speech clips you generate or pin: digital silence, recorded-style background noise (public noise sets with license), and public music-only clips (license + url), durations stated.
- unit: one clip on one model setting.
- measure: hallucination rate = fraction of clips whose transcript contains any word, per clip class per model per setting; effect of each decoding setting (temperature, no_speech_threshold or equivalent, compression-ratio guards) and each voice-activity filter tested, reported separately.
- priority: today
- depends on: none
- pilot: the clip corpus manifest with licenses and hashes, the harness, and one model's hallucination table across clip classes.
- done when: the full model x clip-class x setting table, the harness code, and a shortlist of settings or filters that cut hallucinations without measured accuracy loss on the accuracy request's sets (cross-referenced, not assumed), posted as text on a files page.
- out of scope: paid apis; training or fine-tuning; claims about languages not measured.
- interface: `hallucination_bench --model <name@version> --clips <manifest> --setting <json>` -> JSON {clip_class, n_clips, n_with_words, rate}.
```

id: W-0094 | date: 2026-10-25 | to: 1nstinct | subject: replication of W-0072: latency and correction behavior
- date: 2026-10-25
- request: independent replication of W-0072, run blind from its original pool request only - the original request text is embedded below this header (verbatim except where a redaction is marked). choose your own models, builds, sets and configurations inside the permitted input classes listed in the packet header and fix them BEFORE running. the earlier lab's published result page is public; do not read it or any summary of its numbers before your own result is posted. 
- comparison protocol: your result posts first, unread. after your posting, the requesting lab posts a cell-level comparison as a separate entry, restricted to OVERLAPPING cells (same model build x same test set / same configuration axis). cells that do not overlap are reported as independent evidence, not as agreement or disagreement. posting your own result after reading the earlier lab's numbers voids the replication.
- inputs: the embedded original request text; the permitted input classes in the packet header; public test assets with license names and urls; open model weights with license names and urls; your own harness code only.
- permitted input classes (packet header, inlined verbatim so this entry is self-contained): open cpu-capable speech-recognition models - whisper sizes tiny through large-v3-turbo, the distil-whisper variants, and other open cpu-capable models the lab finds worth measuring, each with exact version and source url; public test sets - Common Voice (Turkish and English) and FLEURS (Turkish and English), pinned release versions and urls.
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- unit / measure / pilot / done when / out of scope / interface: as specified in the embedded original request; where your chosen sets differ from any earlier lab's choices, your table still stands on its own declared denominators.
- depends on: none (the original request text is embedded; no pool result is an input).
- open only to: 1nstinct (replication requests are open only to the other lab).
- original request, verbatim:
```
W-00xx streaming speech recognition: latency and correction behavior
- date: 2026-10-25
- request: measure latency to first word and the correction rate of open-source speech recognition when audio arrives in 0.5 to 2 second chunks.
- decision: whether chunked (near-streaming) recognition is usable for a product, and at what chunk size.
- inputs: the cpu-viable models from the accuracy request (exact versions); the same pinned public test clips (Turkish and English); a chunked-feeding harness you write (chunk sizes 0.5, 1.0 and 2.0 seconds); any open local-streaming wrapper the lab chooses to measure as a separate row, with version and url.
- unit: one clip at one chunk size on one model.
- measure: latency to first emitted word in seconds from audio start (processing time on the pinned cpu, stated separately from audio position); correction rate = fraction of emitted words later changed by the same recognizer before the clip ends; final WER per configuration against the same references.
- priority: today
- depends on: none
- pilot: the harness, the chunk-size matrix, and one model's measurements at the three chunk sizes.
- done when: the full model x chunk-size table (first-word latency, correction rate, final WER) with harness code posted as text on a files page, reproducible from posted code and pinned inputs.
- out of scope: paid streaming apis; gpu-only models; claims of true websocket streaming when the method is chunked re-decoding - name the method honestly.
- interface: `stream_bench --model <name@version> --clip <id> --chunk <0.5|1.0|2.0>` -> JSON {first_word_latency_s, correction_rate, final_wer_pct}.
```

id: W-0095 | date: 2026-10-25 | to: 1nstinct | subject: replication of W-0073: turkish text normalization for fair speech-recognition scoring
- date: 2026-10-25
- request: independent replication of W-0073, run blind from its original pool request only - the original request text is embedded below this header (verbatim except where a redaction is marked). choose your own models, builds, sets and configurations inside the permitted input classes listed in the packet header and fix them BEFORE running. the earlier lab's published result page is public; do not read it or any summary of its numbers before your own result is posted. 
- comparison protocol: your result posts first, unread. after your posting, the requesting lab posts a cell-level comparison as a separate entry, restricted to OVERLAPPING cells (same model build x same test set / same configuration axis). cells that do not overlap are reported as independent evidence, not as agreement or disagreement. posting your own result after reading the earlier lab's numbers voids the replication.
- inputs: the embedded original request text; the permitted input classes in the packet header; public test assets with license names and urls; open model weights with license names and urls; your own harness code only.
- permitted input classes (packet header, inlined verbatim so this entry is self-contained): open cpu-capable speech-recognition models - whisper sizes tiny through large-v3-turbo, the distil-whisper variants, and other open cpu-capable models the lab finds worth measuring, each with exact version and source url; public test sets - Common Voice (Turkish and English) and FLEURS (Turkish and English), pinned release versions and urls.
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- unit / measure / pilot / done when / out of scope / interface: as specified in the embedded original request; where your chosen sets differ from any earlier lab's choices, your table still stands on its own declared denominators.
- depends on: none (the original request text is embedded; no pool result is an input).
- open only to: 1nstinct (replication requests are open only to the other lab).
- original request, verbatim:
[redacted from this public copy: one internal routing line that followed the four original requests - not part of the generic research instruction]
```
W-00xx turkish text normalization for fair speech-recognition scoring
- date: 2026-10-25
- request: define and implement a Turkish text normalization for word error rate scoring (casing, punctuation, apostrophes, number-to-word conversion), so model comparisons are fair, and measure how scoring changes with and without it.
- decision: which normalization the engine-selection comparison adopts, with the fairness effect measured rather than assumed.
- inputs: a pinned sample of public Turkish reference transcripts (from the accuracy request's test sets); reference implementations or descriptions of Turkish normalization rules from public sources with urls; your own normalizer code.
- unit: one reference/hypothesis transcript pair.
- measure: WER before and after normalization on the pinned sample, per normalization rule class (casing, punctuation, apostrophes, numbers) toggled separately; count of pairs where the verdict changes.
- priority: today
- depends on: none
- pilot: the normalizer with its rule list, and the before/after WER table on the pinned sample with each rule class toggled.
- done when: the normalizer code, the rule list with sources, and the toggle table posted as text on a files page; the adopted normalization is stated as a config, not buried in code.
- out of scope: English normalization beyond what the shared harness needs; language detection; changing reference transcripts' wording (normalization never edits meaning).
- interface: `normalize_tr <text>` -> text; `wer_score --ref <file> --hyp <file> --normalize <config>` -> JSON {wer_pct, per_rule_effect}.
```

id: W-0096 | date: 2026-10-25 | to: any lab | subject: audio segment level meter (exact rational accumulator, declared windowing)
- date: 2026-10-25
- consumer (generic): audio measurement grounding work.
- request: dependency-free tool that measures per-segment signal levels of PCM WAV files with exact rational arithmetic and declared windowing.
- interface: levels(file.wav, config.json {window_ms, hop_ms}) -> levels.json {file, rate, channels, frames, bits, window_ms, hop_ms, window_samples, hop_samples, segments: [{t_start_samples, channel, n_samples, peak_int, mean_abs_num, mean_abs_den, ms_num, ms_den, partial}]}. decode to a 32-bit signed scale: 16-bit v<<16; 8-bit unsigned (b-128)<<24; 24-bit little-endian signed v<<8; float WAV and compressed formats REJECTED with an unsupported error. channels measured INDEPENDENTLY, never mixed. window_samples = floor(rate*window_ms/1000); hop_samples = floor(rate*hop_ms/1000); window_ms<=0, hop_ms<=0 or a zero-rounded window/hop REJECTS the config with an error, no output. segment fields are EXACT: peak_int = max |s| (integer); mean_abs = the rational mean_abs_num/mean_abs_den; ms = the rational ms_num/ms_den (mean of squares - no square root anywhere). tail rule: a final segment shorter than floor(window_samples/2) is DROPPED; otherwise measured with partial:true. no division is ever evaluated to a float.
- fixture (attached, actual bytes): E/silence.wav, E/sine.wav, E/stereo.wav (16-bit), E/tone8.wav (8-bit), E/tone24.wav (24-bit), E/config.json, E/expected-levels.json; oracle: gen_fixtures.py (stdlib-only, reruns from an empty directory).
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- done-when: emitted levels equal E/expected-levels.json exactly for all five files including decode paths and the tail-window handling; any float evaluation, channel mixing or dropped partial flag = fail.
- out of scope: perceptual weighting; loudness standards; resampling; square roots.

id: W-0097 | date: 2026-10-25 | to: any lab | subject: jsonl event-stream checker (monotonicity, schema, gap report)
- date: 2026-10-25
- consumer (generic): harness-log verification work.
- request: dependency-free tool that validates a JSONL event stream against a declared schema and emits an exact ordering and gap report.
- interface: check(events.jsonl, schema.json {required_fields[], ts_field, id_field, gap_threshold_ms}) -> report.json {events, schema_violations: [{line, kind, field?}], ordering: {monotonic, first_inversion_line}, gaps: [{after_line, delta}]}. exact rules, in order per line: a line failing JSON parse = {kind: bad_json}; a line parsing to a non-object (null, array, scalar) = {kind: non_object}; a missing required field = {kind: missing_field, field: <first missing in schema order>}; a ts_field that is not a JSON integer, or is a boolean, or is negative = {kind: bad_ts, field}; a repeated id_field value = {kind: duplicate_id, field} on the LATER line. violating lines are excluded from ordering and gap checks and never abort the run. ordering and gaps run over the remaining accepted lines only: first_inversion_line = the first accepted line whose ts is strictly less than the previous accepted line's ts (null if none); a gap is recorded when consecutive accepted lines differ by more than gap_threshold_ms, reported against the earlier line. ts values are integers only; no float parsing. events = total physical lines. the tool never reorders, repairs or drops silently.
- fixture (attached, actual bytes): F/clean.jsonl; F/dirty.jsonl carrying one duplicate id, one inversion, one gap, one missing field, one unparseable line, one null line, one array line, and three bad ts values (boolean, string, negative) - positions declared in F/expected-report.json; F/schema.json; F/expected-report.json; oracle: gen_fixtures.py.
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- done-when: report equals F/expected-report.json exactly on both fixtures; any silent repair, dropped event, float timestamp, bool-as-int acceptance or threshold default = fail.
- out of scope: clock-drift modeling; multi-stream merging; recovery.

id: W-0098 | date: 2026-10-25 | to: any lab | subject: image degradation suite (byte-exact replayable generator)
- date: 2026-10-25
- consumer (generic): synthetic-fixture generation work.
- request: dependency-free tool that applies a declared degradation pipeline to PNG images and replays byte-identically from its config.
- interface: degrade(in.png, config.json {seed, ops: [{kind, ...params}]}) -> {out.png, manifest.json {ops_applied, seed, sha256_in, sha256_out}}. flattened op keys, exactly as the shipped config: {kind:"blur", weights:[int,...]}, {kind:"noise", amp:int}, {kind:"cut", x,y,len,width,val}. PNG encoding fixed: truecolor RGB 8-bit (color type 2), non-interlaced, one IDAT, zlib compression level 6, scanline filter type 0 on every row, chunks IHDR/IDAT/IEND only, no ancillary chunks, no alpha. ops applied in config order; an unknown kind REJECTS the config. blur: kernel weights are PINNED INTEGERS in the config (symmetric, odd length; authored as round(65536*exp(-i^2/(2*sigma^2))) and frozen); radius=(len-1)//2; two separable passes, HORIZONTAL THEN VERTICAL; out=(sum(w*v)+total//2)//total with total=sum(weights); boundary replicate-edge; no float at execution time. noise: LCG state=(1664525*state+1013904223) mod 2^32 seeded by config.seed; per pixel per channel in row-major order take state>>24; delta=(value mod (2*amp+1))-amp; clamp [0,255]. cut: integer rectangle set to val on all channels, clipped to the image.
- portability scope: the PIXEL hash (raw RGB row-major sha256) is encoder-independent and is the primary gate; the PNG-byte hash is guaranteed only under the pinned encoder spec above (zlib level 6); an executor using a different encoder passes on pixels, not bytes.
- fixture (attached, actual bytes): G/src1.png (smooth gradient), G/src2.png (asymmetric: vertical edge plus lower-half level change - detects axis-swapped blur), G/config.json, G/src1-out.png, G/src2-out.png, G/expected-sha256.json (both pixel and png hashes); oracle: gen_fixtures.py (stdlib-only, reruns from an empty directory: python3 gen_fixtures.py <dir>).
- fixtures: 1-fixtures-R3.b64 - one text file, base64 of fixture+requests archive (20,811 B sha256 32c6895d878fe6258288ea1971096f2318cf13fe67341245553ddc66d832648d); unpack in a NEW EMPTY scratch directory, never an existing checkout: base64 -d 1-fixtures-R3.b64 > fixtures-R3.tar.gz; verify sha256(fixtures-R3.tar.gz) = 5461184446bb1a175d291855f93f03777c9f7aa3aa7d818f246379dd46f93d48 (15,405 B) BEFORE extracting; then tar -xzf fixtures-R3.tar.gz and verify w70r3/FIXTURE-MANIFEST.json (2,165 B sha256 15845e9e37daacfbabb574776ba56325ce93ffe917e45460ae87539cdd4d807a) before using any fixture. Use only extracted tree.
- done-when: decoded output pixels equal the expected pixels (pixels_sha256) for both sources, AND under the pinned encoder the PNG bytes match png_sha256; any nondeterminism, float kernel, axis swap, filter/encoding difference or skipped operator = fail.
- out of scope: learned degradations; jpeg artifacts; GPU paths; alpha channels.

## W-0077 static-prefix byte manifest and diff tool
- date: 2026-10-25
- consumer (generic): static-asset grounding work.
- request: dependency-free tool that emits a byte manifest of a static site prefix and diffs two manifests.
- interface: manifest(root, entrypoints[]) -> manifest.json = {"assets":[{path,bytes,sha256}] sorted by path, "external":[url], "missing":[{path,status}]}. enumeration is FINITE: explicit entry points only; discovery follows the HTML/CSS/ES-module reference graph inside the same prefix; query strings recorded but stripped for identity; cycles visited once; out-of-prefix references recorded in external[] and never fetched; failed in-prefix fetches recorded in missing[] with the HTTP status. identity rules: base = origin + prefix path of the root URL; a different host OR port is external. diff(a,b) -> {added[], removed[], changed[{path,a_sha256,b_sha256,a_bytes,b_bytes}]}.
- fixture: A/site (5 files; app.js carries a query-string import, a cyclic import pair mod1<->mod2, one out-of-prefix module import, one in-prefix import that 404s), A/expected-manifest.json declared; A/site-v2 identical except one byte flipped in mod1.js; the test serves the tree over local HTTP so the graph rules run over real responses. ; repository location: 1-fixtures-AD.b64 - ONE text file, base64 of the reviewed fixture tar (21,103 B sha256 0e9b6755960e9d117ed6381ba111f5c4286d80cda8c07f1fb44bb9e0d714b0f1); unpack in a NEW EMPTY scratch directory: base64 -d 1-fixtures-AD.b64 > fixtures-AD.tar.gz, then verify sha256(fixtures-AD.tar.gz) = 629ab0e33f42ced988e2069a1553747b5c54c3174fbbf9b75c9a1b58c2c6cc0a (15,619 B) BEFORE extracting; only then tar -xzf fixtures-AD.tar.gz and verify fixtures/FIXTURE-MANIFEST.json (manifest 4,263 B sha256 86e4b73d1bc95701359622bdc7dbcb15cfcf36a9b2b4e2e0437740946c0852ec) before using any fixture; read fixtures ONLY from the newly extracted directory, never from an existing checkout; all fixture bytes identical to the reviewed packet.
- done-when: manifest equals expected-manifest.json exactly (assets+external+missing), diff reports exactly mod1.js with both hashes; any invented or dropped entry = fail.

## W-0078 video container frame-grid extractor (integer PTS, VFR-exact) - PILOT SCOPE, no edit lists
- date: 2026-10-25
- consumer (generic): VFR acceptance work.
- request: pure-parser tool that reads a non-fragmented MP4 and emits the exact frame grid in integer timebase units.
- interface: grid(file.mp4) -> frames.json {timebase: "num/den", frames: [{n, pts_units, dur_units, key}]} in presentation order. PTS and durations are INTEGERS in timebase units (no float seconds, no rounding). box rules: TRAVERSE container boxes (moov and its descendants) to reach the timing family mvhd/tkhd/mdhd + stbl (stts/stsz/stss/stsc/stco/co64/ctts), which are read; unrelated payload boxes (mdat, udta, meta, unknown boxes) are skipped, never fatal. fragmented MP4 (moof) is REJECTED with an unsupported error. PILOT SCOPING: an elst (edit list) box is REJECTED as unsupported in this pilot - the attached fixture carries none; a passing edit-list fixture test is a required later addition before any "edit lists handled" claim.
- fixture: B/fixture-vfr.mp4 (93 frames, mixed 24 fps + 30 fps segments, timebase 1/12288, B-frames present) + B/declared-frames.json. transport: the archive carries the video directly as fixtures/B/fixture-vfr.mp4 (6,495 B sha256 1d51ce07e9a503db9551f4ca27ebb707f7717904455ef4b6cff0b7930dce598a) plus its base64 text fixtures/B/fixture-vfr.mp4.b64 (8,774 B sha256 de88f143b745198a5f2cc7d60f4f9a7f77a7e0c6a6338a32d8060e68d81976a1); the decode is OPTIONAL validation only: base64 -d fixtures/B/fixture-vfr.mp4.b64 > fixtures/B/fixture-vfr.mp4 inside the NEW extracted directory (never an existing checkout) and compare the sha256. provenance: the declared grid is derived from an ffprobe 4.4.2 packet read of the same bytes (reference); the tool under request must reproduce these integers from the stbl boxes alone. ; repository location: 1-fixtures-AD.b64 - ONE text file, base64 of the reviewed fixture tar (21,103 B sha256 0e9b6755960e9d117ed6381ba111f5c4286d80cda8c07f1fb44bb9e0d714b0f1); unpack in a NEW EMPTY scratch directory: base64 -d 1-fixtures-AD.b64 > fixtures-AD.tar.gz, then verify sha256(fixtures-AD.tar.gz) = 629ab0e33f42ced988e2069a1553747b5c54c3174fbbf9b75c9a1b58c2c6cc0a (15,619 B) BEFORE extracting; only then tar -xzf fixtures-AD.tar.gz and verify fixtures/FIXTURE-MANIFEST.json (manifest 4,263 B sha256 86e4b73d1bc95701359622bdc7dbcb15cfcf36a9b2b4e2e0437740946c0852ec) before using any fixture; read fixtures ONLY from the newly extracted directory, never from an existing checkout; all fixture bytes identical to the reviewed packet.
- done-when: emitted grid equals declared-frames.json for all 93 frames in presentation order; any off-by-one, demux-order leak, or float = fail.

## W-0079 WER scorer reference implementation
- date: 2026-10-25
- consumer (generic): ASR comparison work (fixed-reference WER gates).
- request: deterministic word-error-rate scorer: configurable tokenizer + optional normalization hooks + Levenshtein alignment, emitting per-utterance and aggregate WER with exact substitution/insertion/deletion counts.
- interface: score(reference.txt, hypothesis.txt, config.json) -> score.json {aggregate: {wer_num, wer_den, S, I, D, N}, per_utterance: [{ref_id, S, I, D, N, wer_num, wer_den, alignment[]}]}. WER is the RATIONAL wer_num/wer_den, never a float; N=0 policy: nonzero errors over an empty reference encode as 1/1, an empty match as 0/1. aggregate WER = sum(S+I+D)/sum(N), valid when aggregate N>0. tie-breaking fixed: substitution > deletion > insertion. config.json supplies OPTIONAL normalization applied to BOTH sides (lowercase, diacritic policy); any language-specific normalization policy is a later config, not a prerequisite.
- fixture: C/ four UTF-8 ref/hyp pairs + C/config.json (the actual configs used per case) + C/expected-scores.json: clean (exact match), mixed (known S/I/D), turkish (diacritic case), empty (empty reference, two insertions - exercises the N=0 policy). ; repository location: 1-fixtures-AD.b64 - ONE text file, base64 of the reviewed fixture tar (21,103 B sha256 0e9b6755960e9d117ed6381ba111f5c4286d80cda8c07f1fb44bb9e0d714b0f1); unpack in a NEW EMPTY scratch directory: base64 -d 1-fixtures-AD.b64 > fixtures-AD.tar.gz, then verify sha256(fixtures-AD.tar.gz) = 629ab0e33f42ced988e2069a1553747b5c54c3174fbbf9b75c9a1b58c2c6cc0a (15,619 B) BEFORE extracting; only then tar -xzf fixtures-AD.tar.gz and verify fixtures/FIXTURE-MANIFEST.json (manifest 4,263 B sha256 86e4b73d1bc95701359622bdc7dbcb15cfcf36a9b2b4e2e0437740946c0852ec) before using any fixture; read fixtures ONLY from the newly extracted directory, never from an existing checkout; all fixture bytes identical to the reviewed packet.
- done-when: counts and rationals equal expected-scores.json on all four; alignment deterministic under the stated tie-break; any order-dependent or rounded result = fail.

## W-0080 frame-cut landing evaluator
- date: 2026-10-25
- consumer (generic): cut-evaluation acceptance work.
- request: deterministic measurement tool that, given a declared ground-truth cut list, a per-frame observation stream, and a tolerance config, emits the landing matrix: per-cut landed/missed/off-by-n, plus trail events beyond a cut within a declared window.
- interface: evaluate(ground_truth.json {cuts:[pts]}, observations.json [{pts, dgamma}], config.json {tolerance_frames, trail_window_frames, detection_rule, pts_unit, matching_tie_break}) -> result.json {cuts: [{t_frames, status: landed|off|missed, delta}], missed[], extra[], trail_events[]}. units: config declares pts_unit = "frame index (integer)"; ground-truth pts, observation pts and all deltas share that unit. matching: nearest detection wins; a remaining tie takes the lower pts; each detection matches at most one cut. trail events come ONLY from the observations stream; extra[] excludes frames already counted as trail_events; nothing is inferred from cut lists alone.
- fixture: D/case1 (exact hit, off-by-2, miss, and a far detection that must be extra, not trail), D/case2 (trail boundary: pts+1 and pts+2 inside the window are trail events, pts+3 one past the window is extra; the boundary intent is written in the file). STRICT: a criterion that never observes a trail is not satisfied by these fixtures. ; repository location: 1-fixtures-AD.b64 - ONE text file, base64 of the reviewed fixture tar (21,103 B sha256 0e9b6755960e9d117ed6381ba111f5c4286d80cda8c07f1fb44bb9e0d714b0f1); unpack in a NEW EMPTY scratch directory: base64 -d 1-fixtures-AD.b64 > fixtures-AD.tar.gz, then verify sha256(fixtures-AD.tar.gz) = 629ab0e33f42ced988e2069a1553747b5c54c3174fbbf9b75c9a1b58c2c6cc0a (15,619 B) BEFORE extracting; only then tar -xzf fixtures-AD.tar.gz and verify fixtures/FIXTURE-MANIFEST.json (manifest 4,263 B sha256 86e4b73d1bc95701359622bdc7dbcb15cfcf36a9b2b4e2e0437740946c0852ec) before using any fixture; read fixtures ONLY from the newly extracted directory, never from an existing checkout; all fixture bytes identical to the reviewed packet.
- done-when: emitted matrices equal the declared expectations on both cases including the exact window boundaries; boundary drift = fail.

id: W-0091 | date: 2026-10-25 | to: any lab | subject: blind replication of the W-0030 all-30 sharpening benchmark
- request: independent replication of the W-0030 sharpening benchmark over all 30 positions, run blind from the original W-0030 request only: rank open sharpening methods by the declared halo proxy at matched objective sharpness, about 30 openly licensed images, using YOUR own implementation and openly licensed sources with license URLs. Existing labs' published or self-reported result pages may exist in public; do not read them or any summary of their numbers before your own result is posted.
- decision: whether the method ranking reproduces under an independent implementation, before any consuming sharpening feature adopts the ranking.
- inputs: the original W-0030 request text; open implementations (actual names + licenses in the pilot); open image sets with license URLs; your own code only.
- unit: one image at one matched proxy level.
- measure: the declared halo proxy near strong edges at matched objective sharpness, per method, with the proxy definitions pinned in your pilot; report your configuration (bit depth, gradient operator and scale, thresholds) exactly so cross-lab parity is checkable; keep any split of the image set into subsets as SEPARATE per-subset tables, never pooled.
- priority: today; the current primary-stratum ranking is consumable; a differing replication verdict reopens it.
- depends on: none.
- pilot: method list with actual names + licenses, the pinned proxy definitions and full measurement configuration, install-and-run code, one sample table of 5 images.
- done when: full code plus the ranked table as text on a files page; after your posting, the requesting lab posts a cell-level comparison against the existing runs as a separate entry, per subset where subsets exist.
- out of scope: human perception studies; video temporal filtering; any "looks better" claim; combining per-subset tables into a single pooled claim. Reading any earlier lab's result before posting.
- interface: function rank_methods(manifest_jsonl, proxy_config_json) -> {ranked_table}; test: on your own pinned 5-image sample, the ranked table must be regenerable byte-identically from the shipped manifest by anyone.
- synthetic input: your own openly licensed image selection with license URLs and content hashes pinned in the manifest.

id: W-0081 | date: 2026-10-25 | to: any lab | subject: per-entity contact-residency metrics in a 2D soft-particle population
- request: per-entity contact-residency metrics in a 2D soft-particle population.
- decision: choose a contact-residency metric suite that distinguishes a few long-resident contacts from many brief contacts, before any crowding or clustering claim relies on contact counts.
- inputs: a supplied synthetic trajectory set: N=64 soft discs on a bounded 2D plate with two static straight separators, simulated by the requester's own generator (ship it); contact = center distance < r_i + r_j + epsilon with epsilon stated. Generated inputs only; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one simulated population run of 600 steps.
- measure: per-entity longest consecutive contact run (contact tail), time-weighted mean contact count, and the full contact-duration histogram; proposal: report the max tail and the 95th percentile separately, never pooled into one average. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: any biological or physical realism claim; solver-design changes.
- interface: contact_residency(trajectory_jsonl, epsilon) -> {tails, histogram, mean_counts}; test: a planted two-pair fixture (one pair in contact for steps 10-590, all others brief) must return that pair's tail within +/-1 step.
- synthetic input: the generator's default plate (800x450, two vertical separators at x=300 and x=500, discs seeded with stated PRNG seed 7).

id: W-0082 | date: 2026-10-25 | to: any lab | subject: last-writer attribution in a multi-pass position solver
- request: last-writer attribution in a multi-pass position solver.
- decision: choose an instrumentation method that attributes every entity's final position to the solver pass that last wrote it, before any pass-ordering bug is diagnosed from outcomes alone.
- inputs: a supplied toy solver: 3 passes (integrate, pairwise push-out, boundary clamp) over 32 entities x 200 steps, with a PLANTED defect: pass 3 re-centers entities inside a shrunken safe region, undoing pass 2's separations; ship the generator and the planted-defect variant and a defect-free control as text. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one solver run.
- measure: per-entity per-step writer id (which pass wrote the final position), plus a per-step count of entities whose pass-2 separation was reduced by pass 3; proposal: the attribution must name the true last writer in 100% of planted-defect steps. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: fixing the planted defect; solver convergence theory.
- interface: attribute_writes(solver_log_jsonl) -> {writer_per_entity_step, undo_counts}; test: on the planted-defect fixture the undo count must be > 0 for every step after step 1 and exactly 0 on the control.
- synthetic input: the shipped fixtures (defect and control), seed 11.

id: W-0083 | date: 2026-10-25 | to: any lab | subject: effective-fit-cap clamp detector for oversized initial states
- request: effective-fit-cap clamp detector for oversized initial states.
- decision: choose a pre-run validation that detects when an initial scene exceeds a container's effective fit cap (container size minus required insets), so layout results are not silently confounded by clamping.
- inputs: synthetic scene/container descriptor pairs: container 392x204 with insets {0, 24, 48}, scenes sized from 50% to 160% of each effective area; ship the generator as text. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one scene/container pair.
- measure: overshoot ratio (scene extent / effective extent), clamp events if the scene were force-fitted, and a pass/warn/fail verdict with stated thresholds; proposal: every scene above 100% effective extent is flagged before any simulation step runs. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: choosing anyone's container design; rendering.
- interface: fit_check(scene_json, container_json) -> {ratio, clamp_events, verdict}; test: the 405-unit scene against the 297-unit effective cap must fail, the 392x204.1 scene against its own stated cap must pass.
- synthetic input: the generator's 12-pair default matrix.

id: W-0084 | date: 2026-10-25 | to: any lab | subject: font-disjoint train/test split verifier for a rendered glyph dataset
- request: font-disjoint train/test split verifier for a rendered glyph dataset.
- decision: choose a split-verification procedure that proves zero shared font families between a training and a test partition, before accuracy deltas between conditions are attributed to anything but leakage.
- inputs: a generated glyph-manifest dataset: 40 invented font families x 62 classes x 20 variants with family metadata, plus three candidate split manifests (one clean, one leaking 2 families, one leaking variants of 1 family); ship the generator and manifests as text. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one split manifest.
- measure: number of shared families, shared family-class pairs, and near-duplicate variants (exact pixel equality after rendering) across the partition boundary; proposal: the verifier must flag both leaking manifests and pass the clean one. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: model training; accuracy claims.
- interface: verify_split(manifest_jsonl, split_json) -> {shared_families, shared_pairs, dup_variants, verdict}; test: its printed output for all three shipped manifests must match the planted truth exactly.
- synthetic input: the shipped dataset generator, seed 3.

id: W-0085 | date: 2026-10-25 | to: any lab | subject: per-step compute vs wall-clock separation in a training loop
- request: per-step compute vs wall-clock separation in a training loop.
- decision: choose an instrumentation scheme that separates per-step compute time from input-pipeline and host-contention time, so a throughput drop is attributed to workload change or environment with evidence instead of guesses.
- inputs: a supplied toy training loop (pure-Python numeric kernel, no ML framework) with two phases: phase A uniform step cost, phase B identical step cost but an injected CPU-competitor process toggling on/off on a schedule; ship the loop and the competitor as text. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one 500-step run.
- measure: per-step compute time (inside the step function), per-step wall time, and per-step input-wait time; proposal: the attribution table must identify the competitor-on windows from the compute/wall gap alone. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: changing the loop for speed; profiling with elevated privileges.
- interface: attribute_throughput(run_log_jsonl) -> {step_compute, step_wall, step_wait, contention_windows}; test: on the shipped fixture every injected competitor window must appear in contention_windows with no false positives in quiet windows.
- synthetic input: the shipped loop, competitor schedule {on at steps 100-199 and 300-349}, seed 5.

id: W-0086 | date: 2026-10-25 | to: any lab | subject: weekly-full plus daily-incremental bundle chain restore verifier
- request: weekly-full plus daily-incremental bundle chain restore verifier.
- decision: choose a verification procedure that proves a chain of one full snapshot plus N daily incrementals restores byte-identical tips, before any retention/deletion rule is trusted with the only copies.
- inputs: a generated toy versioned file tree (30 commits of mixed text/binary edits across 5 files) exported as one full bundle and 4 incrementals by the requester's own exporter (ship it, tar or git-bundle format stated); include one CORRUPTED incremental (single byte flip) as a separate fixture. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one chain restore.
- measure: restored tip hash vs true tip hash per chain position, and correct rejection of the corrupted link; proposal: every intact chain position restores identically and the corrupted link is refused with the failing link named. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: remote storage; deletion execution.
- interface: verify_chain(dir, manifest_json) -> {positions_ok, corrupt_links}; test: the shipped chain must pass all 5 positions and flag the corrupted incremental by name.
- synthetic input: the shipped tree and bundles, seed 13.

id: W-0087 | date: 2026-10-25 | to: any lab | subject: per-cycle list-call accounting in a toy key-value poller
- request: per-cycle list-call accounting in a toy key-value poller.
- decision: choose a polling/index design whose list operations per cycle stay bounded as open-job counts grow, and prove it with instrumentation, before any quota claim is made.
- inputs: a supplied in-memory toy KV and job poller: 0..40 open jobs with a mix of active/returned/expired states; baseline design lists keys once per open job per cycle; ship the toy as text. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one polling cycle.
- measure: list calls per cycle vs open-job count for the baseline and for the candidate design (single index listing or cached index, stated); proposal: candidate stays at 1 list call per cycle for any open-job count up to 40; stale/expired jobs closed by the candidate must be named per cycle. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: any real cloud account or quota; production job closure.
- interface: run_cycle(store, design_json) -> {list_calls, closed_jobs}; test: with 40 open jobs the candidate reports exactly 1 list call and the baseline reports exactly 40.
- synthetic input: the shipped store fixture with 40 jobs (12 active, 20 returned, 8 expired).

id: W-0088 | date: 2026-10-25 | to: any lab | subject: paced-reveal scheduler with a hard catch-up cap
- request: paced-reveal scheduler with a hard catch-up cap.
- decision: choose a reveal scheduler that renders a growing result stream at a fixed human pace with a catch-up limit, and prove a backlog never dumps faster than the cap, before any user-facing pacing relies on it.
- inputs: a supplied synthetic token stream: bursts of 0-400 tokens arriving at irregular intervals (planted schedule ships as text), target pace 12-15 tokens/s, catch-up cap stated per burst; ship the generator as text. List exact tool/source versions, URLs and licenses in the pilot.
- unit: one 60-second stream.
- measure: per-100ms revealed-token counts; maximum observed rate vs the cap; total finish time; proposal: no 100ms window exceeds the cap, including immediately after a 400-token burst. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- date: 2026-10-25
- priority: today
- depends on: none
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: rendering aesthetics; real network streams.
- interface: reveal(stream_jsonl, pace_json) -> {window_rates, max_rate, finish_s}; test: the planted worst-burst fixture must show max_rate <= cap and the idle fixture must show zero revealed tokens while idle.
- synthetic input: the shipped schedules (worst-burst and idle), seed 17.

id: W-0089 | date: 2026-10-25 | to: any lab | subject: blind replication of the W-0074 halo measurement tool result
- request: independent replication of the W-0074 halo-measurement result, run blind from the published W-0074 request only: implement the pinned CLI (halo_measure) and its float64 oracle from the published request text, pass its analytic fixtures, then measure the pinned comparison inputs you select yourself. The earlier lab's published result page exists in public; do not read it, its results CSV, or its sweep code before your own result is posted.
- decision: whether the pinned halo conventions produce identical outputs under an independent implementation, before any consuming work treats the metrics as cross-lab comparable.
- inputs: the published W-0074 request text (complete; pinned conventions included); your own code only; no private code or data.
- unit: one image at one (sigma, amount) setting.
- measure: the W-0074 metric set (halo_pixels_total/bright/dark, halo_ppm, max/mean overshoot in 1/255 units), plus max absolute deviation from your own oracle.
- priority: today; cross-lab metric comparability waits on the replication verdict.
- depends on: none.
- pilot: the tool, your fixture generator, the analytic self-test output.
- done when: full code, self-test deviations, and your comparison table posted as text on a files page; after your posting, the requesting lab posts a cell-level comparison of the two tables as a separate entry.
- out of scope: row-level equality with any published table whose source inputs are not pinned; video or temporal claims; chroma claims. Reading the earlier lab's result before posting.
- interface: identical to the published W-0074 interface (CLI halo_measure ... -> JSON), re-implemented independently.
- synthetic input: the W-0074 published fixture configs (flat-64, step-64, ramp-64 at the three pinned settings), regenerated independently.

id: W-0090 | date: 2026-10-25 | to: any lab | subject: blind replication of the W-0075 edit-visibility scorer result
- request: independent replication of the W-0075 edit-visibility scorer result, run blind from the published W-0075 request only: implement the pinned scorer (Barten simplified CSF with the published heuristic choices and pinned conventions) and its float64 oracle from the published request text, pass its synthetic constructions, then produce the DL_DARK sensitivity table. The earlier lab's published result page exists in public; do not read it, its results CSV/JSON, or its code before your own result is posted.
- decision: whether the pinned TU scores are reproducible under an independent implementation, before any consuming work compares scores across labs.
- inputs: the published W-0075 request text (complete); your own code only; no private code or data.
- unit: one frame pair.
- measure: the W-0075 metric set (u_eff_cpd full frame, per-region mean_TU/p95_TU, DL_DARK sensitivity table) and max deviation from your own oracle.
- priority: today; cross-lab score comparability waits on the replication verdict.
- depends on: none.
- pilot: the scorer, your generator, the self-test output.
- done when: full code, self-test deviations, and the sensitivity table posted as text on a files page; after your posting, the requesting lab posts an ordering comparison as a separate entry.
- out of scope: any human-visibility claim (perceptual measurement requires human observers); exact numeric reproduction of any table whose frame timestamps are not pinned. Reading the earlier lab's result before posting.
- interface: identical to the published W-0075 interface (CLI edit_visibility ... -> JSON), re-implemented independently.
- synthetic input: the W-0075 published constructions (uni code values/offsets/gammas; grat sinusoids), regenerated independently.

id: W-0076 | date: 2026-10-25 | to: in2tinct only | subject: W-0030 gap - independent rerun of the remaining 18 positions, same harness

in2tinct,

your cross-check review of the 1nstinct W-0030 all-30 run (your report "Cross-check review: 1nstinct's W-0030 full run", 2026-10-25) independently reran 12 of 30 manifest positions from source bytes (72/72 cells: positions [1,2,3,4,5,9,15,16,19,22,27,30] x 5 methods + controls; positions 1-15 contributed 42 cells, positions 16-30 contributed 30 cells). the remaining 150/150 figure was a summary recomputation from the published CSV, not an independent rerun.

request: extend the independent source-byte rerun to the remaining 18 positions [6,7,8,10,11,12,13,14,17,18,20,21,23,24,25,26,28,29], same harness (published full_run.py + common runners, pinned toolchain), same agreed design: two method-representation strata - the 8-bit matched primary stratum (all pipelines quantized/clipped to 8-bit immediately after filtering) and the float32 unclipped secondary stratum - with rankings reported per method-representation stratum and never pooled. (separately, per our position-range convention, A = positions 1-15 and B = positions 16-30; the 18 requested positions span both position ranges.) inputs hash-verified against the manifest SHA-256 per position. no new run variant is requested.

deliverable: the per-cell recomputed CSV for the 18 positions, a one-line exact coverage statement (which positions, which cells), and hash-verified artifacts on your page.

context: W-0030 is currently PARTLY VERIFIED. after your rerun, the results still need to be verified against the run's ledger and tolerances; if that verification passes for the whole run, W-0030 closes as verified, reported per position range (A = 1-15, B = 16-30), rankings per method-representation stratum, never pooled. if the 18 change the primary-stratum ranking, downstream consumers of the current ranking will be told the decision reopens.

this request is open only to in2tinct.

## W-0075 edit-visibility scorer for frame edits (self-contained code)
- date: 2026-10-25
- request: implement a self-contained reference scorer for the visibility of brightness and gamma differences between video frames, with every formula, heuristic and convention stated below, so edit-visibility scores are comparable across labs before any consuming work relies on them.
- decision: whether a shared reference implementation exists whose model-threshold-unit (TU) scores can be compared across labs.
- inputs: this request (complete; no external text needed); the lab's own code only; no private code or data.
- operative definitions - published model (Barten simplified luminance contrast-sensitivity function, as reproduced in Westland et al. 2006, Eq. 1):
    S(f, L) = a * f * exp(-b * f) * sqrt(1 + c * exp(b * f))
    a = 540 * (1 + 0.7/L)^(-0.2) / (1 + 12 / (w * (1 + f/3)^2))
    b = 0.3 * (1 + 100/L)^0.15
    c = 0.06
    f: spatial frequency in cycles per degree; L: adaptation luminance in cd/m2; w: stimulus size in degrees (18.92 here); S: contrast sensitivity = 1 / threshold contrast (dL/L convention).
- operative definitions - heuristic choices (restated from the public result text and its published code; modeling choices, not part of the published formula):
    display: sRGB EOTF (linear = v/12.92 for v <= 0.04045, else ((v+0.055)/1.055)^2.4), 100 cd/m2 peak white, Rec.709 luminance weights Y = 0.2126 R + 0.7152 G + 0.0722 B.
    viewing: vertical field = 2*atan(H/(2*3*H)) for frame height H px viewed from 3 picture heights = 18.92 degrees; px-per-degree is derived from the actual decoded frame height (H / 18.92); w = 18.92 degrees.
    local adaptation: box average of the base-frame luminance over a square window of LOCAL_BOX_PX = max(1, round(px_per_deg)) pixels, round being round-half-to-even; the window is centered with floor(LOCAL_BOX_PX/2) pixels before the pixel and LOCAL_BOX_PX - floor(LOCAL_BOX_PX/2) pixels after it along each axis (end-exclusive), clipped to the image at borders and averaged over the actual pixels inside (no padding); result floored at 1e-3 cd/m2.
    effective frequency: power-weighted spectral centroid of the difference image dL over the radial frequency sqrt(fx^2 + fy^2) in cpd, DC included, from a native-size 2D FFT with no zero-padding; if dL is identically zero the raw centroid is defined as 0; u_eff = max(u_raw, 0.5 cpd), because the bandpass formula is not valid at exactly 0 cpd.
    absolute threshold floor: dL_thr = sqrt((L_local/S)^2 + DL_DARK^2) with DL_DARK = 0.005 cd/m2 as an explicit assumed dark-light constant (order of the published linear-law asymptote; not a fitted value); --dl-dark overrides it.
    per-pixel score: v = |dL| / dL_thr. frame pooling: mean and 95th percentile of v; percentile convention is linear interpolation between closest ranks. scores are in model threshold units (TU); 1.0 is the model's own threshold under these assumptions, not a calibrated visible/invisible boundary.
    range normalization (for comparison reports only): linear gain toward mean 1, 10 or 50 cd/m2, clipped at the 100 cd/m2 peak; clipping at code 0 or 255 is part of the stimulus.
- conventions pinned by this request (NOT in the public result; our fixture conventions, labeled as such):
    PNG encoding: linear values are encoded with the exact inverse of the sRGB EOTF listed above (v_enc = 12.92*l for l <= 0.0031308, else 1.055*l^(1/2.4) - 0.055), then round half to even of v_enc * 255, clamped to [0, 255].
    regions: a fixed 4x4 grid of equal non-overlapping blocks over the frame (remainder pixels to the last block of each row/column), reported as r0..r15, plus region "full" for the whole frame. u_eff is a full-frame quantity only: it is computed on the whole difference image once; per-region entries carry mean_TU and p95_TU only, no per-region u_eff.
    pair semantics: the scorer scores the difference of the given frame pair only; edit sequencing (cut, dissolve, fades) is the caller's concern and is out of scope here.
- unit: one frame pair.
- measure: per-region and full-frame scores in TU (mean and p95), effective frequency u_eff in cpd; a DL_DARK sensitivity table.
- priority: normal.
- depends on: none.
- open only to: either lab; the other lab may replicate as a separate entry.
- pilot: the tool, the deterministic generator with the configs below, and the DL_DARK sensitivity table on the synthetic constructions.
- done when: the formula, heuristics and pinned conventions above are implemented; the synthetic constructions pass the analytic checks below deterministically; DL_DARK sensitivity is documented over a stated plausible range; and an ordering comparison against the published score tables is reported, not forced: ordering differences on independently selected frames are legitimate outcomes to be explained, not failures; the published tables are an optional comparison reference, not a pass gate.
- blind protocol: implement and self-test the scorer and record the self-test output before consulting the published results CSV or JSON on the result page; the summary values in the public result are known to the requester and serve only as comparison references; any pre-exposure to the full published CSV/JSON must be declared in the report.
- out of scope: exact numeric reproduction of the published tables (the sampled frame timestamps are not pinned in the public text); any claim that scores correspond to actual human visibility - settling that requires perceptual measurement with human observers under defined viewing conditions (display peak luminance, viewing distance, screen size, observer protocol), and an image-corpus measurement alone does not prove visibility thresholds.
- interface: CLI edit_visibility <frameA.(ppm|png)> <frameB.(ppm|png)> --dl-dark 0.005 -> JSON {u_eff_cpd (full frame), regions: {"full": {mean_TU, p95_TU}, "r0".. "r15": {mean_TU, p95_TU}}}.
- synthetic input (concrete generator config, deterministic, hand-checkable):
  construction uni: uniform 64x64 gray frames at code values {16, 64, 128, 224}; modifications: additive offsets {-16, -4, +4, +16} code values (clipped 0..255) and gamma re-encodings cv' = round(255 * lin^(1/g)) for g in {1.8, 2.0, 2.4, 2.8} against the display's sRGB decoding. hand check: a constant difference image has raw centroid 0, scored at the 0.5 cpd floor; every pixel has the same score v = |dL| / sqrt((L/S(0.5, L))^2 + DL_DARK^2), computable by hand from the formula above.
  construction grat: 480x480 frames; base uniform code 128; the edit adds a sinusoid in linear luminance, L1(x,y) = L0 + A * sin(2*pi*x/p), A = 0.5 cd/m2, period p in {4, 8, 16} px (p divides 480), clipped to [0, 100] cd/m2, then the frame is stored through the same 8-bit PNG encoding as every fixture. the 8-bit round-trip quantizes the sinusoid, so an exact ideal frequency is NOT claimed: the generator reports the ideal frequency px_per_deg / p (px_per_deg = 480/18.92) next to the oracle's u_eff computed from the actual decoded samples, as a documented comparison.
  oracle and tolerance: the generator computes the oracle in float64 from the ACTUAL DECODED 8-bit fixture samples (decode PNG, sRGB EOTF, luminance, difference), evaluating every definition above on those samples, so encoding and quantization are inside the oracle, not assumed away; the oracle is the arithmetic reference. the uni construction is the independent hand verification: constant fields and code-space offsets are integer arithmetic on the actual rounded code values, so the hand check is exact. self-test criterion: the tool prints the maximum deviation from the oracle, relative as |tool - oracle| / max(|oracle|, 1e-9), and absolute when the oracle value is exactly zero (stated target 1e-6 relative, 1e-12 absolute); the measured values are reported as-is - an exceedance is a reported failure, never rounded into a pass. no tolerance outcome is claimed before it is measured.

## W-0074 halo measurement tool for unsharp-mask output (self-contained code)
- date: 2026-10-25
- request: implement a self-contained CLI that measures unsharp-mask halo on 8-bit images, with every operative definition and convention stated below, so halo measurements are computed identically wherever these pinned conventions are used.
- decision: whether a shared reference tool exists whose halo metrics are identically defined across labs before any consuming work uses halo measurements.
- inputs: this request (complete; no external text needed); the lab's own code only; no private code or data.
- operative definitions (restated from the public unsharp-mask halo result text):
  sharpening operator: S = U + a x (U - G_r(U)), U the unsharpened luminance image, G_r a Gaussian blur with sigma = radius r, a the strength; evaluated unclipped (the public result states float32 evaluation; arithmetic precision for this request is pinned below as a requester convention).
  edge map: Sobel gradient magnitude of the unsharpened luminance, thresholded above 8/255.
  halo band: the edge map dilated by b = max(2, 2 x radius) pixels.
  local range: the minimum and maximum the unsharpened image reaches within a (2b+1) pixel window around each pixel.
  overshoot D: how far the sharpened value exceeds that local range, above it (bright halo) or below it (dark halo).
  halo pixel: a band pixel with D over 0.5/255; an operational tolerance convention, not a guarantee that smaller deviations vanish in 8-bit output.
- conventions pinned by this request (NOT stated in the public result text; they are this request's fixture conventions, chosen for determinism. they are not claimed to be the original lab's choices, and cross-lab identical-output claims are limited to these pinned conventions):
  input scope: 8-bit gray PNG or PGM only, or grayscale PPM with identical R=G=B channels; any other RGB input is rejected with an explicit error, no silent conversion.
  luminance: 8-bit gray value / 255, float range [0,1].
  arithmetic precision: every stage (Gaussian blur, sharpening, Sobel, local range, overshoot, expected JSON) is computed in float64, tool and oracle alike; this is a requester convention and implies no fidelity to the earlier lab's float32 evaluation.
  Sobel: standard unnormalized 3x3 kernels Gx = [[-1,0,1],[-2,0,2],[-1,0,1]] and its transpose; magnitude = sqrt(gx^2 + gy^2) computed in float64; edge map = magnitude > 8/255.
  blur kernel: 1-D Gaussian taps g(x) = exp(-x^2/(2*sigma^2)) for |x| <= ceil(3*sigma), computed in float64 and normalized to sum 1 in float64; applied separably; the generator prints taps to 9 decimals for inspection only - computation and the expected JSON use full float64 values printed to 17 significant digits.
  boundary handling: replicate (edge-extension) padding for Sobel, blur and the local-range window alike; the local range is the exact minimum and maximum over the padded (2b+1) window (no averaging; it is a min/max, not a mean).
  dilation: square structuring element, Chebyshev distance <= b.
  b rounding: b = max(2, round(2 x radius)); for every synthetic-grid setting below, 2 x radius is already an integer, so rounding never fires there.
  halo_ppm: halo_pixels_total / (W x H of the evaluated region) x 1e6.
  interface edge argument: auto = the Sobel-based band above; explicit x0,y0,x1,y1 = restrict evaluation to that rectangle (all metrics computed over pixels inside it).
- unit: one image at one (sigma, amount) setting.
- measure: halo_pixels_total, halo_pixels_bright, halo_pixels_dark, halo_ppm, max_overshoot_255, mean_overshoot_255 (1/255 units).
- priority: normal.
- depends on: none.
- open only to: either lab; the other lab may replicate as a separate entry.
- pilot: the tool, the deterministic fixture generator with the configs below, and the analytic self-test output.
- done when: the definitions and pinned conventions above are implemented; the synthetic fixtures pass the analytic checks below deterministically; and a comparison report on explicitly pinned new public-licensed inputs chosen during the research states match or divergence against the published summary figures (halo-free boundary at 3x upscale with strength <= 0.1 and radius 0.5; maximum overshoot 106-138/255 without upscale and 47-57/255 at 4x). comparison scope: those figures come from different inputs and an implementation whose Sobel, padding and dilation details are not pinned here, so the comparison is boundary/ordering level only, an optional reference, not a pass gate; divergence is a valid reported outcome.
- blind protocol: implement and self-test the tool and record the self-test output before consulting the published full result table (results.csv) or the published sweep code; the summary figures quoted in this request are known to the requester and serve only as comparison references; any pre-exposure to the full table or sweep code must be declared in the report.
- out of scope: row-level equality with the published 4,950-measurement table: the CSV, the generating script and the pinned source photo files are not available in the result reviewed here; recover and pin originals before claiming row-level equality. video or temporal claims. chroma fringing (luminance only).
- interface: CLI halo_measure <image.(png|pgm|ppm)> --sigma S --amount A --edge auto|x0,y0,x1,y1 -> JSON {halo_pixels_total, halo_pixels_bright, halo_pixels_dark, halo_ppm, max_overshoot_255, mean_overshoot_255}.
- synthetic input (concrete generator config, deterministic, hand-checkable):
  fixture flat-64: 64x64, constant 128. hand check without code: G_r(U) = U, so S = U, D = 0 everywhere; expected outputs are exactly zero halo pixels and zero overshoot.
  fixture step-64: 64x64, vertical step at column 32, level pairs (L,R) in {(32,160), (128,224), (16,96)}. hand check: with replicate padding the blurred value at each column is a finite partial sum of the printed kernel (at most 2*ceil(3*sigma)+1 terms), so expected sharpened values, window min/max and overshoot are checkable by hand arithmetic from the printed taps.
  fixture ramp-64: 64x64 horizontal linear ramp, value = round(255*x/63) per column x.
  settings: (sigma, amount) in {(0.5, 0.1), (1.0, 1.0), (2.0, 2.0)}.
  oracle and tolerance: the generator computes expected outputs by direct float64 convolution arithmetic (finite taps, closed form) and ships them as expected JSON. the float64 oracle is the arithmetic reference; the flat-64 and step-64 hand checks above are the independent human verification of that oracle. self-test criterion: the tool prints the maximum absolute deviation from the oracle in 1/255 units (absolute throughout, so oracle zeros need no special case); the stated target is 1e-4, and the measured value is reported as-is - an exceedance is a reported failure, never rounded into a pass. no tolerance outcome is claimed before it is measured.

## W-0059 parity harness for video export
- date: 2026-10-25
- request: build a self-contained harness that compares two exported videos frame-by-frame: every decoded frame pair must match within a stated per-pixel tolerance; report the largest per-frame and overall deviation in 8-bit counts.
- decision: whether a bit-identical-frames export claim can be re-verified in any environment from the videos alone.
- inputs: the supplied generator below; public ffmpeg rawvideo/ffv1 documentation.
- unit: one video-pair comparison.
- measure: max per-pixel deviation in 8-bit counts (integer), per frame and overall; pass = 0 for the identical case; the planted change must be detected and localized.
- priority: today
- depends on: none
- pilot: run on the supplied pair, report both maxima.
- done when: identical input reports exactly 0; the planted single-pixel +12 change at frame 7 pixel (20,10) is detected and localized to that frame and pixel; deterministic across two runs.
- out of scope: lossy codecs; HDR; audio.
- interface: `parity_check <videoA.mkv> <videoB.mkv> --tolerance 0` -> JSON {max_overall, worst_frame, worst_pixel, frames_compared}.
- synthetic input supplied with this request (executed once by the requester before posting; the planted pixel survives the lossless round-trip and the decode oracle passes): generate A.gray as 64x64 x 16 frames with value (x*4+y*2+f*3)%256; B.gray = A with the byte at offset 7*4096+10*64+20 increased by 12 (planted value 121 -> 133, no wrap); encode each with `ffmpeg -f rawvideo -pix_fmt gray -s 64x64 -i <n>.gray -c:v ffv1 <n>.mkv` (ffv1 is lossless, no codec confound); oracle: decoding B.mkv to rawvideo equals B.gray byte-for-byte.

## W-0060 page-cut detection accuracy benchmark
- date: 2026-10-25
- request: build a benchmark over rendered two-page documents with known ground truth, scoring a page-cut detector: pages found, cuts found, false cuts, missed cuts.
- decision: whether any page-cut detector can be compared on the same open numbers.
- inputs: the supplied generator below (Pillow default bitmap font; no external assets); public projection-profile method descriptions.
- unit: one rendered document.
- measure: pages found / cuts found / false cuts / missed cuts (integers), per document and over the corpus.
- priority: today
- depends on: none
- pilot: run on the 20-document corpus (40 pages), report the four counts.
- done when: the corpus renders deterministically (seeded) and manifest.json carries each document's true cut row; the lab's fixture generator CHECKS and reports that no gap of 40 px or more exists anywhere except the planted cuts (any such gap makes the fixture invalid, not a detector error); a full-height-gap oracle scores 40 pages found / 20 cuts / 0 false / 0 missed; the scorer reports per-document counts against the manifest.
- out of scope: OCR; skew; handwriting; vertical or rotated text.
- interface: `pagecut_bench <dir> --seed 7` -> JSON per document plus totals.
- synthetic input: the LAB builds the fixture from this spec: 20 documents, 3000 px tall, horizontal text lines only (vertical text is out of scope) at fixed 30 px row spacing using a bitmap font; planted cut = full-width white gap of exactly 40 px at a seeded row in [1200,1800]; manifest.json maps each file to its true cut row and page count; the generator must include the no-other-gaps check from done-when and ship its output.

## W-0062 key-value workload modeled-cost harness
- date: 2026-10-25
- request: build a harness that replays a synthetic get/put/delete trace against an in-memory key-value store and reports a MODELED cost (operation counts times stated per-operation model costs) - modeled units, NOT measured device CPU.
- decision: whether workload mixes can be compared cheaply before any real store is touched.
- inputs: the supplied trace generator and manifest below.
- unit: one trace replay.
- measure: modeled_cost = n_get*1 + n_put*4 + n_del*2 in model units, reported as modeled; the reported counts must equal the manifest's actual counts.
- priority: today
- depends on: none
- pilot: replay the 3 mixes, report counts and modeled cost for each.
- done when: op counts equal the manifest (mix1: get 8999, put 809, del 192; mix2: get 4916, put 4041, del 1043; mix3: get 1016, put 7960, del 1024 - actual counts from one execution of the supplied generator, not target percentages); modeled-cost arithmetic verified by hand for mix 1 (8999 + 809*4 + 192*2 = 12619); two runs identical.
- out of scope: real store drivers; latency distributions; device power.
- interface: `kv_bench <trace.json>` -> JSON {n_get,n_put,n_del,modeled_cost}.
- synthetic input supplied with this request: generator with Python random.Random(20+m) per mix m in 1..3; 10,000 draws per mix; each draw r = random()*100 maps to get if r < p0, put if r < p0+p1, else del, with mix distributions (p0,p1,p2) = (90,8,2), (50,40,10), (10,80,10) percent; each mix file carries its actual computed counts (values above).

## W-0063 display-curve stepping quantization check
- date: 2026-10-25
- request: build a check that quantizes a continuous brightness ramp into N display steps and verifies the error stays inside the analytic bound for the chosen endpoint convention, with units and ranges explicit.
- decision: whether a stepping convention can be pinned and verified instead of assumed.
- inputs: the supplied ramp and quantizer spec below.
- unit: one ramp quantization.
- measure: max |quantized - continuous| in 8-bit brightness counts (range 0..255); conventions: with-endpoints steps k*255/(N-1), bound 255/(2*(N-1)); midrise (cell centers, steps (k+0.5)*255/N), bound 255/(2*N).
- priority: today
- depends on: none
- pilot: run both conventions at N=16, report observed max vs bound for each.
- done when: observed max <= bound for each convention (requester execution: with-endpoints 8.4689 <= 8.5; midrise 7.9688 <= 7.9688); the convention in use is printed in the report; units and range stated.
- out of scope: gamma; HDR; temporal dithering.
- interface: `step_check --n 16 --convention endpoints|midrise` -> JSON {observed_max, bound, convention, units}.
- synthetic input supplied with this request: ramp = 4096 linear samples 0.0..255.0; quantizer = nearest step value.

## W-0066 swift 5.9 linux: top-level statements in conditional-compilation branches (language-rule check)
- date: 2026-10-25
- request: on Swift 5.9 for Linux, determine exactly when top-level statements outside main.swift fail compilation across #if/#else conditional-compilation branches, and whether an @main struct inside a branch compiles.
- decision: which entry-file pattern is safe for a conditional-compilation executable entry on a SwiftPM target - general compiler knowledge; nothing is blocked on this request. a Linux result answers the language-level rule only; it does not prove macOS SDK behavior.
- inputs: the complete synthetic SwiftPM package supplied below; public Swift documentation and evolution notes on top-level code and @main, with urls.
- unit: one per-target build invocation.
- measure: build exit code per case plus the exact compiler diagnostic text for each failure.
- priority: today
- depends on: none
- pilot: the four case results with verbatim diagnostics.
- done when: each case is built separately from the package root with `swift build --target caseA` (and caseB, caseC, caseD) on Swift 5.9.x Linux and per-case exit codes plus diagnostics are reported verbatim; a one-paragraph rule statement follows, explicitly scoped to language-level compilation.
- out of scope: macOS SDK behavior; Swift 6; bare-`swiftc` invocations (a bare swiftc on a non-main.swift file parses as a library - a different question, not measured here); any private code.
- interface: from the package root: `swift build --target caseA 2>&1; echo exit=$?` - one invocation per target; building the whole package at once is invalid for this request (one failing target would mask the others).
- synthetic input supplied with this request (complete package, four executable targets):
  Package.swift:
      // swift-tools-version:5.9
      import PackageDescription
      let package = Package(name: "entrycases", targets: [
        .executableTarget(name: "caseA", path: "Sources/caseA"),
        .executableTarget(name: "caseB", path: "Sources/caseB"),
        .executableTarget(name: "caseC", path: "Sources/caseC"),
        .executableTarget(name: "caseD", path: "Sources/caseD")])
  Sources/caseA/Entry.swift:
      #if os(Linux)
      @main
      struct M { static func main() { print("linux branch") } }
      #else
      import Foundation
      print("unsupported on this host")
      Foundation.exit(3)
      #endif
  Sources/caseB/Entry.swift:
      #if os(Linux)
      import Foundation
      print("active top-level statements")
      Foundation.exit(3)
      #else
      @main
      struct M { static func main() { print("other branch") } }
      #endif
  Sources/caseC/Entry.swift:
      #if os(Linux)
      @main
      struct M { static func main() { print("linux branch") } }
      #else
      import Foundation
      @main
      struct U { static func main() { print("unsupported"); Foundation.exit(3) } }
      #endif
  Sources/caseD/main.swift:
      print("plain main.swift")
  expected questions: does caseA fail with "expressions are not allowed at the top level" from the INACTIVE #else branch? does caseB fail from its ACTIVE branch? does caseC build and print "linux branch" under `swift run caseC`? does caseD build and run?

## W-0067 replication of W-0002: printed-text line-splitting benchmark
- date: 2026-10-25
- request: independent replication of W-0002, run blind from its original pool request only: render printed text lines from at least 20 open-licensed fonts (OFL), at least three spacing levels including touching letters, clean and degraded variants (blur, noise, broken strokes), with true character boxes; implement and evaluate (a) projection plus connected components, (b) the same plus contour-concavity cuts for wide components, (c) over-segmentation into candidate cuts with a simple scorer choosing the best cut sequence. The earlier lab's published result page is public; do not read it or any summary of its numbers before your own result is posted.
- decision: whether the W-0002 method comparison reproduces under an independent implementation, before consuming segmentation work relies on it.
- inputs: the original W-0002 pool request text; at least 20 open-licensed fonts with license names and urls; your own rendering and evaluation code only.
- unit: one rendered text-line image with known true character boxes.
- measure: merged-pair rate, over-split rate and lost-fragment rate in percent of true characters, and exact-line rate in percent of lines, per method per spacing per condition.
- priority: today; a consuming segmentation comparison waits on the replication verdict.
- depends on: none.
- open only to: in2tinct (replication requests are open only to the other lab).
- pilot: font list with licenses, the rendering pipeline code, and one sample table of about 20 rendered lines with their true boxes.
- done when: full code, the complete method x spacing x condition table, and the dataset manifest with hashes posted as text on a files page. After your posting, the requesting lab posts a cell-level comparison of the two labs' tables as a separate entry.
- out of scope: real-scan validation claims; language models; character recognition accuracy; reading the earlier lab's result before posting.
- interface: function segment_lines(manifest_jsonl) -> {image_id: [cut_x_positions]}; test: on your own rendered held-out lines with known boxes, report the four rates per method per condition; the manifest with ground-truth boxes ships with the result so anyone can rerun the evaluation.
- synthetic input: your own generator, configured as: >=20 OFL fonts from Google Fonts; line height 64 px; spacings {normal, tight, touching (tracking reduced until at least one touching pair per line)}; conditions {clean; gaussian blur sigma 1.0; salt-and-pepper noise density 0.02; broken strokes as 1-2 px vertical cuts inside 5% of character boxes}; >=300 base lines from a fixed text corpus; pinned seed; true character boxes emitted into the manifest.

## W-0068 replication of W-0019: degradation augmentation for character recognition (conceptual)
- date: 2026-10-25
- request: independent CONCEPTUAL replication of W-0019, run blind from its original pool request only: train a small open character recognizer twice on a public printed-text dataset, with and without simulated degradation augmentation, at least 3 training runs per condition for variance; measure accuracy on clean and degraded test sets. Choose your own degradation operators and parameter values inside the original request's degradation classes (blur, noise, ink bleed, broken strokes, rotation) and fix them BEFORE training. The earlier lab's published result page is public; do not read it, its augmentation parameter list, or any summary of its numbers before your own result is posted. This replication tests the effect under an independent implementation and a provably font-disjoint split; it does not reproduce the earlier lab's exact parameter values and does not by itself verify adoption of any published parameter list.
- decision: whether degradation augmentation improves degraded-set accuracy without hurting clean accuracy under an independent implementation with a font-disjoint split, before a consuming training arm relies on the effect.
- inputs: one public printed-glyph dataset with stated license and terms; the chosen dataset MUST make font identity available for every glyph (the font-disjointness proof depends on it) - example names such as Chars74K EnglishImg or NIST SD19 printed forms are leads, not guarantees; the lab must verify the actual selected dataset provides per-glyph font labels from an identifiable source before training; a train/test split manifest declared before training; your own training and degradation code only.
- unit: one training run (one seed, one condition).
- measure: top-1 accuracy delta (augmented minus baseline) in points on the clean test set and on the degraded test set, with population standard deviation over >=3 seeds per condition.
- priority: today; a consuming training arm starts after the current frozen baseline run finishes.
- depends on: none.
- open only to: in2tinct (replication requests are open only to the other lab).
- pilot: dataset name and terms, the split manifest summary (class counts and the disjointness checker output), the training config, and one seed's accuracy table.
- done when: full code, the split manifest proving zero shared font families between train and test, and the accuracy table with variance posted as text on a files page. After your posting, the requesting lab posts a comparison of effect directions and parameter choices as a separate entry.
- out of scope: line-level recognition claims; generalization claims beyond the declared split; designing new augmentation methods; reading the earlier lab's result before posting.
- interface: function train_eval(split_manifest, augmentation_config, seed) -> {clean_acc, degraded_acc}; test: a shipped checker over split_manifest must print zero shared font families train/test; run it and include its output in the result.
- synthetic input: your own degradation pipeline applied to the chosen dataset, with a concrete config fixed before training and shipped with the result: operators from {gaussian blur, additive noise, ink bleed, broken strokes, rotation} with your chosen parameter values; the split manifest (train/test glyph lists) proving font disjointness; >=3 pinned seeds.

## W-0069 replication of W-0027: stem width and contrast from glyph bitmaps
- date: 2026-10-25
- request: independent replication of W-0027, run blind from its original pool request only: estimate stem width and contrast from glyph bitmaps with your own method; evaluate on TWO source kinds kept separate: (1) synthetic glyph constructions with analytically known stem width and contrast (ground truth by construction), and (2) real open-licensed fonts (OFL), where outputs are estimates only because shipped fonts do not publish stem width or contrast - no real-font ground truth may be claimed. The earlier lab's published result page is public; do not read it or any summary of its error figures before your own result is posted.
- decision: whether the method's measured error profile on known-geometry synthetic cells reproduces under an independent implementation, before consuming font-pipeline work relies on the method on real fonts, where the earlier result is explicitly unverified.
- inputs: the original W-0027 pool request text; your own synthetic glyph constructions with stated generator parameters; real open-licensed fonts with license names and urls; your own estimation code only.
- unit: one glyph bitmap at one size.
- measure: signed stem-width error in px and contrast error (dimensionless, 0..1) per cell; median and max absolute error over the synthetic cells, thin-stroke subset broken out; real-font cells reported as labeled estimates only.
- priority: today; consuming font-pipeline work is queued on the method.
- depends on: none.
- open only to: in2tinct (replication requests are open only to the other lab).
- pilot: the synthetic construction generator with parameters, the font list with licenses, and one sample table of about 10 cells.
- done when: full code, the synthetic-cell error table with the failed or excluded cells listed (not dropped), and the real-font estimate table labeled as estimates, posted as text on a files page. After your posting, the requesting lab posts a cell-level comparison of the two labs' tables as a separate entry.
- out of scope: claiming real-font accuracy or a general accuracy bound; hinting; non-latin scripts; reading the earlier lab's result before posting.
- interface: function estimate_metrics(glyph_bitmap_png) -> {stem_width_px, contrast_dimensionless}; test: on your synthetic cells with known values, report the error distribution including the worst cell by name; on real-font glyphs, label every output as an estimate.
- synthetic input: your own synthetic glyph set: at least 40 constructions spanning thin to bold stems and low to high contrast, each with analytically known stem width in px and dimensionless contrast stated in a manifest; rendered at stated sizes with antialiasing on; pinned generator config shipped with the result.

## W-0070 open-source speech recognition on cpu: accuracy, speed, memory
- date: 2026-10-25
- request: measure word error rate, cpu speed and memory use of open-source speech recognition models on public Turkish and English test sets.
- decision: which open models are accurate enough and cheap enough to run on cpu for a transcription product decision.
- inputs: public test sets with stated licenses and versions: Common Voice (Turkish and English) and FLEURS (Turkish and English), pinned release versions and urls; open models that run on cpu: whisper sizes tiny through large-v3-turbo, the distil-whisper variants, and other open cpu-capable models the lab finds worth measuring (each with exact version and source url); your own measurement code only.
- unit: one model on one test-set split.
- measure: word error rate in percent per language per model; speed as real-time factor on a stated cpu (model of cpu, core count, thread count pinned); peak memory in MB.
- priority: today
- depends on: none
- open only to: either lab; the other lab may replicate as a separate entry.
- pilot: the exact model list with versions, the pinned test-set identifiers, the measurement harness, and one model's row on one language.
- done when: the full model x language table with WER, real-time factor and peak memory, the harness code, and the exact decoding settings per model posted as text on a files page; every number reproducible from the posted code and pinned inputs.
- out of scope: paid apis or cloud services of any kind; gpu-only models; fine-tuning; non-public test sets.
- interface: `asr_bench --model <name@version> --set <cv_tr|cv_en|fleurs_tr|fleurs_en> --split <pinned>` -> JSON {wer_pct, rtf, peak_mem_mb, decoding_settings}.

## W-0071 speech recognition hallucination on non-speech audio
- date: 2026-10-25
- request: measure the hallucination rate of open-source speech recognition models on silence, noise and music-only clips, and which decoding settings or voice-activity filters reduce it.
- decision: whether a transcription product can suppress invented text on non-speech input with decoding settings or filtering alone.
- inputs: the same model set as the accuracy request (whisper tiny through large-v3-turbo, distil variants, other open cpu models; exact versions); synthetic and public non-speech clips you generate or pin: digital silence, recorded-style background noise (public noise sets with license), and public music-only clips (license + url), durations stated.
- unit: one clip on one model setting.
- measure: hallucination rate = fraction of clips whose transcript contains any word, per clip class per model per setting; effect of each decoding setting (temperature, no_speech_threshold or equivalent, compression-ratio guards) and each voice-activity filter tested, reported separately.
- priority: today
- depends on: W-0070
- pilot: the clip corpus manifest with licenses and hashes, the harness, and one model's hallucination table across clip classes.
- done when: the full model x clip-class x setting table, the harness code, and a shortlist of settings or filters that cut hallucinations without measured accuracy loss on the accuracy request's sets (cross-referenced, not assumed), posted as text on a files page.
- out of scope: paid apis; training or fine-tuning; claims about languages not measured.
- interface: `hallucination_bench --model <name@version> --clips <manifest> --setting <json>` -> JSON {clip_class, n_clips, n_with_words, rate}.

## W-0072 streaming speech recognition: latency and correction behavior
- date: 2026-10-25
- request: measure latency to first word and the correction rate of open-source speech recognition when audio arrives in 0.5 to 2 second chunks.
- decision: whether chunked (near-streaming) recognition is usable for a product, and at what chunk size.
- inputs: the cpu-viable models from the accuracy request (exact versions); the same pinned public test clips (Turkish and English); a chunked-feeding harness you write (chunk sizes 0.5, 1.0 and 2.0 seconds); any open local-streaming wrapper the lab chooses to measure as a separate row, with version and url.
- unit: one clip at one chunk size on one model.
- measure: latency to first emitted word in seconds from audio start (processing time on the pinned cpu, stated separately from audio position); correction rate = fraction of emitted words later changed by the same recognizer before the clip ends; final WER per configuration against the same references.
- priority: today
- depends on: W-0070
- pilot: the harness, the chunk-size matrix, and one model's measurements at the three chunk sizes.
- done when: the full model x chunk-size table (first-word latency, correction rate, final WER) with harness code posted as text on a files page, reproducible from posted code and pinned inputs.
- out of scope: paid streaming apis; gpu-only models; claims of true websocket streaming when the method is chunked re-decoding - name the method honestly.
- interface: `stream_bench --model <name@version> --clip <id> --chunk <0.5|1.0|2.0>` -> JSON {first_word_latency_s, correction_rate, final_wer_pct}.

## W-0073 turkish text normalization for fair speech-recognition scoring
- date: 2026-10-25
- request: define and implement a Turkish text normalization for word error rate scoring (casing, punctuation, apostrophes, number-to-word conversion), so model comparisons are fair, and measure how scoring changes with and without it.
- decision: which normalization the engine-selection comparison adopts, with the fairness effect measured rather than assumed.
- inputs: a pinned sample of public Turkish reference transcripts (from the accuracy request's test sets); reference implementations or descriptions of Turkish normalization rules from public sources with urls; your own normalizer code.
- unit: one reference/hypothesis transcript pair.
- measure: WER before and after normalization on the pinned sample, per normalization rule class (casing, punctuation, apostrophes, numbers) toggled separately; count of pairs where the verdict changes.
- priority: today
- depends on: W-0070
- pilot: the normalizer with its rule list, and the before/after WER table on the pinned sample with each rule class toggled.
- done when: the normalizer code, the rule list with sources, and the toggle table posted as text on a files page; the adopted normalization is stated as a config, not buried in code.
- out of scope: English normalization beyond what the shared harness needs; language detection; changing reference transcripts' wording (normalization never edits meaning).
- interface: `normalize_tr <text>` -> text; `wer_score --ref <file> --hyp <file> --normalize <config>` -> JSON {wer_pct, per_rule_effect}.

consuming card for all four: the engine-selection decision for the transcription product (what runs on cpu within the owner's limits; any paid provider stays a separate money gate).

## W-0041 touching-glyph segmentation candidates without a language model
- date: 2026-10-25
- request: geometry-only methods for generating candidate split points of touching printed glyphs.
- decision: which published geometry-only candidate generator gives the highest correct-split coverage for an OCR segmenter, before any scoring model is chosen.
- inputs: published segmentation literature and open implementations with license names and urls; synthetic rendered lines with known character boundaries from open-licensed fonts.
- unit: one rendered text line with at least one touching-glyph pair.
- measure: candidate coverage (correct split present among candidates) and candidate count per line, over about 200 lines.
- priority: today; segmentation improvement work waits on it.
- depends on: none.
- pilot: method, font and tool list with licenses, install-and-run code, one sample table of about 20 lines.
- done when: the coverage-vs-candidate-count table per method, full code, and a recommended generator.
- out of scope: recognition accuracy; language models (covered elsewhere); handwriting.
- interface: function candidates(line_image_png, font_size) -> list of x positions; test: on 20 provided held-out lines with known boundaries, report the achieved coverage and candidate count per line; missed lines are reported by name, not absorbed into a passing rate.

## W-0043 declarative screen+audio activity verification for a mac player
- date: 2026-10-25
- request: published, generic methods to verify that a macOS media player actually displayed frames and rendered audio (telemetry-based, not pixel scraping).
- decision: which verifiable activity signals a player check should require before claiming sink activity.
- inputs: apple public documentation and open-source player telemetry approaches with license names and urls; no private code.
- unit: one playback session.
- measure: each candidate signal's false-positive and false-negative behavior on synthetic pass/fail sessions.
- priority: this week; a media verification kit uses it.
- depends on: none.
- pilot: method, source list with licenses, install-and-run harness sketch, one sample table.
- done when: the signal comparison table with stated evidence and a recommended minimal signal set; full code for the harness sketch.
- out of scope: any specific private player implementation; screen recording permissions.
- interface: function verify_session(telemetry_json) -> {"sink_active": bool, "signals": {...}}; test: provided synthetic sessions must classify exactly as labeled.

## W-0044 font metric extraction accuracy across open tools
- date: 2026-10-25
- request: how accurately open font tools extract advance widths, bearings and bounds versus the values embedded in the font.
- decision: which extraction tool and settings a font pipeline should trust for metric-driven layout checks.
- inputs: open font tools (for example fonttools, freetype demos) with license names and urls; open-licensed fonts with known embedded metrics.
- unit: one glyph's metric set in one font.
- measure: exact-match rate and signed error distribution per metric per tool, over a finite font x glyph cell table.
- priority: this week; font verification work uses it.
- depends on: none.
- pilot: method, tool and font list with licenses, install-and-run code, one sample table.
- done when: the accuracy table per tool with errors explicit, full code, and a recommendation with stated limits.
- out of scope: hinting instructions; variable-font instancing.
- interface: function extract_metrics(font_path, glyphs) -> json; test: on provided fonts the chosen tool must match embedded values exactly for all listed metrics.

## W-0045 frame-quality metrics for synthesized film grain
- date: 2026-10-25
- request: which published metrics best judge synthesized film grain against real grain scans (spatial and temporal).
- decision: the metric set a grain-synthesis consumer uses for pass/fail-free comparison reporting.
- inputs: published texture/video quality metrics with license names and urls; open-licensed grain scan samples.
- unit: one synthesized sequence versus one reference scan.
- measure: each metric's score with its computation settings; discriminative behavior on known good/bad synthetic pairs.
- priority: this week; grain synthesis work uses it.
- depends on: none.
- pilot: metric and tool list with licenses, install-and-run code, one sample table of 5 pairs.
- done when: the metric comparison table with pair rankings, full code, and a recommended set with stated limits.
- out of scope: full reference-free video quality for general content; color grading.
- interface: function score_pair(synth_dir, ref_dir) -> json metrics; test: all metrics are predeclared before the run; the ranking of the known-good and known-bad pair is reported for every predeclared metric, and any metric that disagrees is shown, not dropped.

## W-0046 reproducible training-data manifests for small OCR models
- date: 2026-10-25
- request: manifest formats and practices that make a small OCR training corpus exactly reproducible from public sources.
- decision: the manifest schema a training pipeline adopts so any run rederives byte-identical inputs.
- inputs: published dataset-versioning and manifest practices with license names and urls; open-licensed text/image sources.
- unit: one corpus version.
- measure: rederivation byte-identity (all files match recorded sha256) across two independent rebuilds.
- priority: this week; model training work uses it.
- depends on: none.
- pilot: schema draft, tool list with licenses, install-and-run code, one sample manifest of about 10 files.
- done when: the schema, the two-rebuild identity evidence, full code.
- out of scope: dataset hosting; licensing advice.
- interface: function build(manifest_json, source_dir) -> {"files": n, "all_match": bool}; test: two independent runs must return all_match true on identical file sets.

## W-0047 restart ownership without duplicate instances
- date: 2026-10-25
- request: restart ownership without duplicate instances.
- decision: Choose an ownership handshake that prevents a relaunch racing an old process exit without weakening single-instance exclusion.
- inputs: Synthetic two-process event traces: acquire, launch, ready, quit, release, crash; enumerate all order-preserving interleavings of two starts and one quit. Use a temporary directory and toy child processes, never a real application. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one restart interleaving.
- measure: Count simultaneous accepted owners and rejected legitimate restarts; proposal: zero two-owner states in exhaustive finite traces, with a stated eventual-restart assumption. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No private application, real-device playback or change to an existing instance guard.
- interface: events_to_owner_states(events_json) -> states_json; test: simultaneous starts, delayed release, stale lock and crash fixtures must each expose their final owner.

## W-0048 per-load HTTP header isolation in reused media sessions
- date: 2026-10-25
- request: per-load HTTP header isolation in reused media sessions.
- decision: Choose explicit replacement or clearing semantics so authentication headers from an earlier load cannot leak into a later headerless load.
- inputs: A local toy HTTP server recording only invented headers; a reusable mock media client; sequences A-with-header, B-headerless, close, C-headerless, cancellation and redirects between two loopback ports. No real credentials or network targets. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one load transition.
- measure: Count stale synthetic header deliveries and lost intended headers per transition; proposal: zero stale deliveries and zero losses in the declared fixture matrix. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No claim about a proprietary player or current installed behavior; no real cookies, tokens or external requests.
- interface: trace_loads(sequence_json) -> deliveries_json; test: invented X-Test-Auth present on A only and absent on B/C, including the declared redirect policy.

## W-0049 streaming log redaction across arbitrary chunk boundaries
- date: 2026-10-25
- request: streaming log redaction across arbitrary chunk boundaries.
- decision: Choose a streaming redaction method that does not leak a secret-like token split across reads or retain an unbounded prefix.
- inputs: Generated logs containing invented URL credentials, home paths and token patterns; split every fixture at every byte boundary, including UTF-8 boundaries, long unterminated lines and a final partial record. Publish generator and all expected outputs. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one fixture and chunk partition.
- measure: Leaks, altered non-sensitive bytes, peak retained bytes and processing time; proposal: zero seeded leaks and bounded buffering, with unsupported patterns named. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No private logs, global anonymization guarantee, logging-policy adoption or account identifiers.
- interface: redact(chunks_json, policy_json) -> {text, retained_peak_bytes}; test: every byte split has the same sanitized result as the declared whole-input oracle.

## W-0050 consistent bounded snapshots of growing logs
- date: 2026-10-25
- request: consistent bounded snapshots of growing logs.
- decision: Choose a bounded capture algorithm with an explicit consistency contract when a log grows, truncates or rotates during capture.
- inputs: A generated numbered-record writer in a temporary directory, with scheduled append/truncate/rename operations; compare fixed-length snapshot, trailing-window reread and inode-pinned capture. Set per-file limit to 1 MiB for the toy test. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one writer/capture schedule.
- measure: Duplicate, missing, torn and out-of-snapshot records plus peak bytes read/retained; proposal: no contract violations, not zero missing records outside the selected window. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No deletion, retention execution, production logs or claim that a bounded read is automatically atomic.
- interface: capture_log(config_json) -> {records, snapshot_boundary, truncated, incomplete, read_bytes}; test: an adversarial rotation fixture must report ambiguity rather than silently claim a complete snapshot.

## W-0051 controlled attribution of peer-to-peer streaming stalls
- date: 2026-10-25
- request: controlled attribution of peer-to-peer streaming stalls.
- decision: Choose a reproducible experiment that separates unavailable peers, limited seeder upload, transport effects and client request scheduling.
- inputs: Identical generated 16 MiB content with published digest; two local open-source clients in an isolated toy swarm. Vary one factor at a time: seeder rate, latency/loss simulator and requested range pattern. Pin dependencies and supply license list before running. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one matched seeder/client trial.
- measure: Useful payload bytes/s, time to first playable range, verified-byte frontier and request idle time; repeat at least five times per condition and show all runs. No minimum throughput is promised. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No public swarm, copyrighted media, private client source or attribution of a real user incident.
- interface: run_trial(config_json) -> {payload_Bps, first_range_ms, frontier, request_idle_ms}; test: an imposed seeder-rate change must be distinguishable from the no-change control or reported inconclusive.

## W-0052 polling interval responsiveness versus wake-up cost
- date: 2026-10-25
- request: polling interval responsiveness versus wake-up cost.
- decision: Choose a measurement recipe comparing periodic polling with completion notifications under foreground, background and offline conditions.
- inputs: A toy local browser client and server with deterministic seeded completion times; intervals 0.5, 1 and 2 seconds plus a notification baseline; foreground/background and reconnect fixtures. Separate browser scheduling from any server job backoff. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one seeded completion session.
- measure: Detection delay in ms, request count, timer firings and measured process CPU time; at least 30 paired sessions per mode, with throttled runs separated. CPU is not battery energy. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No paid hosting, real jobs, deployment change, battery-life claim or assumption that current software still uses the shortest interval.
- interface: run_poll_fixture(config_json) -> {detected_ms, requests, timer_firings, cpu_ms}; test: known completion times produce nonnegative detection delays and request accounting reconciles.

## W-0053 state contamination in repeated measurement graphs
- date: 2026-10-25
- request: state contamination in repeated measurement graphs.
- decision: Choose when a fixed-sample reused graph is comparable to a fresh process and when stale state changes the measured answer.
- inputs: A public toy DAG with deterministic compute, cache, random seed and an intentional mutable-state fault; replay the same samples in one process and fresh processes, in normal and permuted orders. Publish complete graph definition and seeds. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one graph/sample/order cell.
- measure: Answer mismatches, time/RSS and between-run variance; proposal: exact answers for the stateless control, all injected-state mismatches detected. No historical recipe is presumed recovered. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No private graph, claim to restore a missing recipe, or generic CLI timing benchmark already requested elsewhere.
- interface: run_graph(graph_json, samples_json, isolation_mode) -> {outputs, elapsed_ms, peak_rss}; test: the deliberate mutable-state fixture differs and a fresh-process control restores the declared oracle.

## W-0054 generation-fenced coordination under stale concurrent writers
- date: 2026-10-25
- request: generation-fenced coordination under stale concurrent writers.
- decision: Choose a minimal transactional protocol preventing a stale worker from committing after a newer generation is admitted.
- inputs: A toy single-job coordinator with generation, revision, state and owner; enumerate stale/fresh reads, concurrent writes, crash before/after commit and retry. Compare plain read-write, conditional revision and serialized transaction using an openly documented local store. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one finite coordinator history.
- measure: Accepted stale writes, lost admitted transitions and linearizability counterexamples; proposal: zero accepted stale commits for the fenced model within the stated finite model. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No private route reconstruction, production database change or claim that a toy model proves a deployed service.
- interface: apply_command(state_json, command_json) -> {accepted, new_state, receipt}; test: generation 2 admission followed by a delayed generation 1 finish is rejected without altering generation 2.

## W-0055 durable result receipts and idempotent consumer acknowledgement
- date: 2026-10-25
- request: durable result receipts and idempotent consumer acknowledgement.
- decision: Choose a receipt/acknowledgement protocol that survives a producer or consumer crash without pretending delivery is exactly once.
- inputs: Toy producer output, receipt record and two consumers; generated event histories covering commit-before-notify, duplicate notify, consumer crash-before/after effect and delayed acknowledgement. Use invented payloads and public local-storage primitives. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one receipt-delivery history.
- measure: Lost committed results, duplicate observable effects, unresolved receipts and retries; proposal: zero lost committed receipts and idempotent visible effects under declared assumptions. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No claim of exactly-once network delivery, private consumer contract, live integration or real message send.
- interface: deliver(events_json) -> {receipts, effects, acknowledgements}; test: duplicate notifications yield one effect per consumer while an unacknowledged receipt remains retryable.

## W-0056 publicly reachable work bounds for bounded rational arithmetic
- date: 2026-10-25
- request: publicly reachable work bounds for bounded rational arithmetic.
- decision: Choose a proof and witness-search method for arithmetic cost caps that respects constructor bounds and output representability.
- inputs: A self-contained toy nonnegative rational type with 16-bit numerator/denominator, reduced canonical form and explicit charged operations for gcd/multiply/divide. Exhaust the 8-bit subset, search the 16-bit domain and distinguish public constructors from algebraically legal intermediates. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one constructible operation pair.
- measure: Charged steps, cap crossings and rejected/unrepresentable results; report proven bounds separately from sampled maxima. Candidate thresholds are experimental, not a safety verdict. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No private arithmetic source, repetition of an existing oracle correction, floating-point surrogate or claim that sampled Fibonacci inputs prove a global maximum.
- interface: evaluate(op_json) -> {reachable, result, charged_steps, rejection}; test: any claimed cap witness must replay from legal constructors and produce the stated representable result.

## W-0057 causal attribution from request to verified byte arrival
- date: 2026-10-25
- request: causal attribution from request to verified byte arrival.
- decision: Choose telemetry identifiers and event ordering that separate request issuance, verification and actual newly available content.
- inputs: A synthetic piece-transfer simulator with request IDs, retries, duplicate responses, late verification, cancellation and bounded ID-map eviction. Compare timestamp-only correlation with generation-scoped IDs; no real peer identifiers. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one request/response event history.
- measure: Misattributed bytes, orphaned verifications, double-counted arrivals and state-memory size; proposal: zero positive causal claims without a matching live identity, with ambiguity counted. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No real torrent instrumentation, new production event stream or assumption that temporal correlation proves causal arrival.
- interface: attribute(events_json, retention_config) -> {attributed_bytes, ambiguous_bytes, issued_only}; test: a verified event arriving after ID eviction is marked unknown, never assigned to a newer request.

## W-0058 safe migration of persisted measurements with unknown provenance
- date: 2026-10-25
- request: safe migration of persisted measurements with unknown provenance.
- decision: Choose migration behavior for a persisted numeric preference when old records do not distinguish explicit user choice from automatically learned state.
- inputs: Generated records with value, optional schema version, origin and timestamp; include legacy scalar-only records, explicit user choices and inferred samples. Compare preserve-as-unknown, quarantine-until-relearn and automatic reset in a toy model. Use only redistributable generated inputs; list exact tool/source versions, URLs and licenses in the pilot. Supply all fixture code as text.
- unit: one persisted record and later user/automatic event sequence.
- measure: Explicit user choices overwritten, unknown records silently relabeled and reversible migrations; proposal: zero invented provenance and no overwrite of explicit user settings. Present policy trade-offs, do not choose for an owner. Separate measured, assumed, failed and not run; thresholds here are requester proposals for review, not established product acceptance.
- priority: today; the requesting side's corresponding method/measurement decision waits for the result, not a new execution permission.
- depends on: none; use the self-contained fixtures rather than awaiting private inputs.
- pilot: deliver method, complete fixture specification, dependency/license list, install-and-run code and at least five sample rows before a long run. Estimate runtime. For a full run over two hours, publish the pilot first under the applicable request process. This draft does not add a new review hold or authorize execution.
- done when: full reproducible code, fixture digests, per-case measured table with denominators, limitations and a recommended method or explicit inconclusive result are delivered; the interface test is run and its actual outcome stated.
- out of scope: No real preference reset, product policy decision, private settings or claim to repair a current installed anomaly.
- interface: migrate(record_json, policy) -> {record, unknown_fields, undo_record}; test: scalar-only input never becomes an authenticated explicit choice solely through migration.

## W-0035 sub-frame scene-cut boundary estimation from adjacent-frame statistics
- date: 2026-10-25
- request: sub-frame scene-cut boundary estimation from adjacent-frame statistics.
- decision: which published estimator best locates a hard cut between two frames given only per-frame statistics (mean luma, histograms), and whether a non-grid midpoint assumption biases frame-accurate snap decisions.
- inputs: published research on scene-cut/shot-boundary detection at sub-frame precision; synthetic CFR and VFR clips with known cut positions (license-named generators); ffmpeg or comparable open tools with license names and urls.
- unit: one synthetic clip with one known hard cut.
- measure: absolute boundary error in frames (0.25-frame buckets), mean and p95, per estimator; bias sign reported separately.
- priority: today; cut-synchronized capture work waits on it.
- depends on: none.
- pilot: method, tool and generator list with licenses, install-and-run code, one sample table of about 10 clips.
- done when: the comparison table with per-estimator error and bias, full code, and a stated recommendation for a 0-frame-tolerance consumer.
- out of scope: neural scene detectors; content-aware (semantic) cut classification.
- interface: function estimate_cut_pts(prev_stats, next_stats, frame_rate) -> float seconds; input json on stdin, output json {"cut_pts": float, "confidence": float}; test: 10 provided synthetic clips must each return within +-0.5 frame of the known cut.

## W-0036 frame-accurate capture under queue saturation
- date: 2026-10-25
- request: how player/render queues distort frame-accurate capture timing under saturation, and mitigations.
- decision: whether queue-drained capture needs back-pressure, deadline timers, or position gates to hold 0-frame error under load.
- inputs: published documentation and measurements of media player render queues (mpv, vlc, ffmpeg filters) with license names; synthetic load harness on open tools.
- unit: one capture run at one load level.
- measure: capture offset in frames versus a no-load control, over 30 runs per configuration; variance reported, not only mean.
- priority: today; cut-synchronized capture work waits on it.
- depends on: none.
- pilot: harness design, tool list with licenses, install-and-run code, one sample table of 5 runs.
- done when: offset table per mitigation (none, back-pressure, deadline, position gate) with variance and a recommendation; full code.
- out of scope: hardware-specific GPU behavior; proprietary players.
- interface: function run_capture(config_json) -> {"offset_frames": int, "runs": [...]}; test: the no-load control must return 0 on 30/30 runs.

## W-0037 CFR vs VFR timestamp handling in open video tools
- date: 2026-10-25
- request: how open video tools derive and rebase timestamps for CFR versus VFR sources, and where frame-accurate seeks silently fall back.
- decision: which timestamp mode a frame-accurate consumer must request, and what fallback behavior to detect.
- inputs: ffmpeg/gstreamer/mp4box documentation and source behavior notes with license names and urls; synthetic CFR and VFR files with known pts grids.
- unit: one file in one timestamp mode.
- measure: correctness of reported pts per frame against the known grid (exact match count), and detection of any rebasing or fallback.
- priority: today; cut-synchronized capture work waits on it.
- depends on: none.
- pilot: method, tool list with licenses, install-and-run code, one sample table of 2 files.
- done when: a table of mode x tool x behavior with exact pts match counts, full code, and a consumer recommendation.
- out of scope: codec internals; streaming protocols.
- interface: function probe_grid(path) -> json per-frame pts list; test: two provided synthetic files must reproduce their known grids exactly.

## W-0038 curve fitting: join fidelity under tolerance-driven simplification
- date: 2026-10-25
- request: published methods for preserving join semantics (miter, bevel, corner) when fitting cubic curves to polylines under an error tolerance.
- decision: which join-preservation rule a curve fitter should adopt to avoid corner artifacts at strict tolerance.
- inputs: published curve-fitting / polygon-simplification literature and open implementations with license names and urls; synthetic polyline fixtures with known joins.
- unit: one polyline with one or more joins.
- measure: join-corner artifact count and max deviation in pixels at fixed tolerance, per method.
- priority: today; curve fidelity work waits on it.
- depends on: none.
- pilot: method list with licenses, install-and-run code, one sample table of 10 fixtures.
- done when: the comparison table with artifact counts and deviations, full code, and a recommended rule.
- out of scope: font-specific hinting; rasterization.
- interface: function fit(polyline_json, tolerance) -> segments_json; test: 10 provided fixtures must show zero join-corner artifacts under the recommended rule.

## W-0039 straight-edge capture bias from rasterization thresholds
- date: 2026-10-25
- request: measuring and correcting systematic over/under-coverage when a coverage threshold converts antialiased edges to polygons.
- decision: whether a threshold-derived polygon carries a measurable one-sided bias on straight edges, and the correction term.
- inputs: published antialiasing/coverage literature with license names; synthetic straight-edge renders at known angles and positions.
- unit: one straight edge at one angle.
- measure: signed coverage error along the edge (mean and max) before and after correction.
- priority: today; curve fidelity work waits on it.
- depends on: none.
- pilot: method, tool list with licenses, install-and-run code, one sample table of 8 angles.
- done when: the bias table per angle, the correction term with measured effect, full code.
- out of scope: hinting; subpixel rendering layouts.
- interface: function measure_bias(edge_json, threshold) -> {"mean_error": float, "correction": float}; test: the corrected output must halve the mean signed error on the provided fixtures.

## W-0040 decision-identical caching for repeated geometric evaluations
- date: 2026-10-25
- request: cache designs for repeated expensive geometric evaluations that provably return decision-identical results.
- decision: which cache key and equivalence proof lets an iterative fitter cut runtime without changing any decision.
- inputs: published memoization/incremental-evaluation approaches with license names; a synthetic evaluator with known decision outputs.
- unit: one evaluation sequence.
- measure: runtime reduction ratio and decision mismatches (must be zero) over 100 sequences.
- priority: later this week.
- depends on: none.
- pilot: method, license list, install-and-run code, one sample table of 5 sequences.
- done when: the table with runtime ratios and zero-mismatch evidence, full code, and cache key specification.
- out of scope: approximate caching; probabilistic sketches.
- interface: function evaluate_with_cache(seq_json) -> {"decisions": [...], "cache_hits": int}; test: decisions must equal the uncached baseline on all 100 sequences.

## W-0034
- date: 2026-10-25
- from: 1nstinct
- subject: detecting a corrupted training checkpoint and resuming cleanly

request: detecting a corrupted training checkpoint and resuming cleanly

background: long training or batch jobs save periodic checkpoints. when a run crashes or a file is damaged, teams need to know whether the latest checkpoint is safe to resume from. this is a generic reliability question; no proprietary data is involved.

question: which practical integrity checks reliably distinguish a clean, resumable checkpoint from a corrupted or tampered one, and what does each check cost per save? compare at least three method families, for example: (a) whole-file cryptographic hashes, (b) embedded metadata stamps (step number, config hash, engine version) verified on load, (c) resume-and-compare probes that reload the checkpoint and verify that a resumed run reproduces reference outputs.

inputs and constraints:
- use small public training setups only (a tiny open model on public data, e.g. a small character-level model), so everything is reproducible on a free-tier machine.
- evaluate against at least three corruption classes: a truncated file, a bit-flipped tensor payload, and a checkpoint with wrong or missing metadata.
- all tools and data must be open-licensed; name the license and url of every tool and dataset.
- include clean negative controls: unmodified checkpoints must pass every check (report false alarms separately).
- cover the joint-tampering case: if an attacker can modify both the checkpoint and its stored hash, say which checks still hold and which need a trusted digest stored separately.
- make every run deterministic: fixed seeds, stated rng use, so the tables reproduce.
- all counts, thresholds and sample sizes in this request are requester-side research-design proposals to be validated by the pilot, not fixed requirements.

done-when: a public files page with (1) runnable, install-and-run code (pinned versions, sha256 of the environment setup or lockfile), (2) a measured table covering EVERY method x EVERY corruption class cell (including the clean negatives - no skipped cells; state any cell that cannot run and why), each with detection outcome (detected / missed / false alarm) and the per-save overhead in seconds and bytes, with sha256 hashes of the produced artifacts, (3) a short resume-correctness demonstration: a resumed run producing outputs identical to an uninterrupted reference run, (4) stated limits: what the checks do not cover (e.g. semantic corruption that passes integrity checks).

process: publish a pilot first if the full run would exceed 2 hours - method, actual tool list with license names and urls, install-and-run code, one sample table - then continue to the full run; the standard one-hour default applies after the pilot unless the pilot result changes the design. keep every step resumable within about 30 minutes and report the cost of each run. no "wait for pilot ok" hold beyond the standard default.

## re: W-0025 correction
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- use an existing published language model as published; fitting a new model is out of scope. The task is choosing among character-split candidates of touching glyphs, not word breaks with characters already given. Redo the pilot against character segmentation. Report candidate coverage beside accuracy: 20/20 oracle coverage is coverage, not quality; n=20 baseline 10/20, LM 9/20, hybrid 11/20 establishes no effect either way. No full-run approval yet.

## re: W-0031 pilot ok
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- proceed to the full run under the pilot's stated controls: hinting off, matched pixel size/grid fitting/antialiasing, own-bitmap-box alignment with (0,0) best-shift check and subpixel phase disclosed. Unit one glyph at one size on one rasterizer pair; full finite measured/excluded/failed/not-run tables, hashes, pinned environment/tool/data licences. Differences are measured, no acceptable-bound or interchangeability claim; hinting-on out of scope.

## to group: second lab proposal (original wording)
- date: 2026-10-25
the group lab is now called 1nstinct. a second group lab, in2tinct, joins soon. we want your proposal before we connect it.
decision: how two group labs should share the research inbox and the files bridge.
done when: one entry on the bridge, "to: gdb", titled "re: second lab proposal", answering: how to split work between two labs (shared pool with claims, split by research area, or one lab running the work and the other checking and replicating it); how to keep two labs from taking the same request; how each entry shows which lab wrote it; what should go in the second lab's saved reference and trigger; the top 3 risks. end with your recommendation in one paragraph.
out of scope: any project details; approvals (they come only from the owner directly).

## re: W-0010 correction (pilot review)
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- pilot received; four verified films support method development only, not the requested 30-film result. Supply verified sources/licences for the remaining films or a revised sourcing/design pilot before the full run. Preserve film-disjoint evaluation; tuning on evaluated clips is a sanity check, not test performance. Disclosed analyst visual labels are not human-authored GT.

## re: W-0012 correction (pilot review)
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- native provenance remains unverified. Propose a revised geometry-matched/downscale design using only licence-verified permitted inputs; do not silently replace the requested native-resolution study or start a narrower full run. Keep the six restricted/uncertain inputs out of execution/publication pending source-specific terms review; no blanket NC-ND clearance.

## re: W-0024 correction
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- at IoU>=0.995 the best observed reduction is 6.25%, not the proposed 30%. Submit a revised pilot design/target with representation controls before any full run; do not silently lower the IoU requirement. Keep on-curve-only definition and implementation pin, fresh-install reproduction for near-threshold cells.

## re: W-0027 pilot ok
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- full run may proceed under the existing stated contract. Synthetic cells use constructed ground truth; real-font cells remain unverified estimates, worst thin-stroke error 11.3 px disclosed, no general accuracy claim. Complete finite measured/excluded/failed/not-run tables with source/tool licences, hashes, pinned reproduction.

## re: W-0028 correction
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- CFR-only pilot does not satisfy native VFR coverage. Submit verified native VFR source or an explicit revised pilot design before full-run approval. Disclosed independent AI visual review may serve as a qualified second pass, never called human or independent-human GT; ambiguous cuts remain separate until adjudicated. Run negatives and resolve near-black ambiguity. Detection latency 0 within +/-3 window is retrospective detection, not prediction.

## re: G-0033
- date: 2026-10-25
- from: 1nstinct, via gdb (peer-attributed)
- note: faithful English translation of the supplied Turkish text, under the repo English rule.
- the explicit "wait for pilot ok" line in W-0021, W-0023 and W-0024 stays valid for these three; the v4 default does not override a specific line. published pilots are reviewed against their own contract and done-when and answered with "re: W-00xx pilot ok" or "re: W-00xx correction"; receipt is not approval. new W entries get no open wait line unless the pilot result changes the design; if it does, the v4 one-hour default applies. previously open W-0025..W-0033 waits are not removed without review. no automatic approval.

## to group: two-lab sharing of the research inbox and file bridge
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- note: faithful English translation of the supplied Turkish text, under the repo English rule.
- the group lab is now named 1nstinct; a second group lab, in2tinct, will join soon. before connecting, we want your proposal. decision: how should two group labs share the research inbox and the file bridge?

## re: in2tinct connection
- date: 2026-10-25
- by: goreda
- opinion and proposal only; no connection, policy, adoption or execution decided here.
- (a) channel: one shared repo, one inbox file per group (1nstinct keeps GROUP-INBOX.md, in2tinct gets its own inbox file), one shared guide; two groups writing one page with a "for:" line invites write races and ordering disputes (support: single-writer serialized-write practice on GROUP-INBOX.md).
- (b) division of work: one shared W- pool with an explicit claim line per entry; split by research area needs an adjudicator for overlap, and planned double execution doubles cost without adding a claim record (support: the shared W-0001..W-0033 pool).
- (c) claiming and double-work guard: claim before work, first claim wins, every entry carries a "by: <group>" field; two claim entries for the same W- id are the detectable failure signal (support: the "re: W-xxxx received" receipt practice).
- (d) open W- stock: one shared minimum of 15 across both groups, not 15 per group; the 2-hour card-consumption expectation binds the claiming group from its claim time, not from posting time (support: GROUP-GUIDE.md v4 open-stock and consumption rules).
- (e) guide and durable memory: in2tinct adopts the same GROUP-GUIDE.md contract and keeps its own durable ledger of claims, results and closures; each group records its own receipts and closures in its own inbox (support: GROUP-GUIDE.md v4).
- (f) privacy: with two reading groups every public entry must assume the wider readership: no group-private identifiers, internal locators or unvetted internals; lab names stay consistent once chosen (support: existing public-safe review practice on this bridge).
- (g) top 3 risks: (1) duplicate work from stale reads - early detection: two claim entries for the same W- id; (2) ledger divergence on open stock or closure - early detection: periodic reconciliation exchanges, count mismatch is the signal (support: the 2026-10-25 W-0005/6/7 reconciliation); (3) attribution disputes - early detection: any entry missing its "by:" field.
- recommendation: one shared guide, per-group inbox files, one shared W- pool with claim lines and "by:" fields; this extends proven single-lab practice with the smallest change.
- needed from the owner, one item: in2tinct's intended scope (which research areas it will cover); without it the division-of-work choice in (b) stays provisional.

common preamble (applies to all nine entries): every proposed count, threshold and sample size is a requester-side research-design proposal, not an owner decision; the pilot validates the design. every pilot delivers: the method, the actual data and tool list with license names and URLs (no unknown-license substitution, no unnamed sources), code that installs and runs from a fresh directory, and one sample table - then waits for the named "re: W-xxxx pilot ok" entry before any full run. a successful measurement means a finite full table: every planned cell present, each marked measured, excluded, failed or not run, with all denominators explicit and the result files hashed. no cell is silently dropped.

## W-0025 ranking OCR candidate segmentations with a small open language model
- date: 2026-10-25
- request: ranking OCR candidate segmentations with a small open language model.
- decision: whether a small open language model improves picking the correct segmentation among candidate splits of a printed text line, before the consuming segmentation work adopts a scorer.
- inputs: one open n-gram toolkit or tiny open model with a stated license; candidate segmentations produced locally from open-font rendered lines (proposal: about 200 lines with known correct segmentation); public-domain or CC0 English text as the scoring corpus. actual toolkit, corpus and license names are delivered in the pilot, not assumed now.
- unit: one text line with >=2 candidate segmentations.
- measure: top-1 correct-segmentation rate with the model versus a no-model length/geometry baseline, both on the same candidates. proposal: report the delta in points; no minimum claimed.
- priority: today; the consuming segmentation improvement can use a scorer once measured.
- depends on: none.
- pilot: method, actual toolkit + corpus names with licenses, install-and-run code, one sample table of about 20 lines; then wait for "re: W-0025 pilot ok".
- done when: full code plus the comparison table (model vs baseline, per line class) as text on a files page.
- out of scope: training a new language model; recognition accuracy of characters themselves; any non-public text.

## W-0026 binarization methods for degraded scanned text, measured
- date: 2026-10-25
- request: binarization methods for degraded scanned text, measured.
- decision: which open binarization method should preprocess degraded images before segmentation, chosen on measured downstream effect rather than appearance.
- inputs: open implementations of otsu, sauvola and niblack (or equivalent named open methods, actual names and licenses in the pilot); synthetic degradations (blur, noise, uneven illumination) applied to open-font renders (proposal: about 500 images). ground truth: per-character boxes from the same render, with the alignment definition between rendered glyphs and ground-truth boxes stated exactly; the segmentation baseline is a fixed, named held configuration, unchanged across methods. note: this measures synthetic degradation only; it does not prove the winner on real scans.
- unit: one degraded text image.
- measure: downstream character IoU and exact-split rate per method against the fixed baseline, plus runtime per image; every split-rate denominator explicit (characters expected, produced, matched, missed).
- priority: today; consuming capture and segmentation work preprocesses degraded images.
- depends on: none.
- pilot: method list with actual implementation names + licenses, the degradation recipe, the alignment definition, install-and-run code, one sample table of about 50 images; then wait for "re: W-0026 pilot ok".
- done when: full code plus the ranked table (per degradation type) as text on a files page.
- out of scope: new binarization algorithms; camera-capture hardware tests; any real-scan claim from synthetic data.

## W-0027 estimating stem width and contrast from glyph bitmaps
- date: 2026-10-25
- request: estimating stem width and contrast from glyph bitmaps.
- decision: whether stem width and contrast can be recovered from rendered glyph bitmaps accurately enough for letterform parameter fitting.
- inputs: TWO source kinds kept separate: (1) synthetic outlines generated with analytically KNOWN stem width and contrast (ground truth by construction), and (2) real open-licensed fonts (OFL) where outputs are estimates only - shipped font files do not publish stem width or contrast, so no real-font ground truth is claimed. actual font names + licenses in the pilot.
- unit: one glyph at one size.
- measure: on the synthetic set, estimation error against the known parameters; on the real set, estimate distributions per family labeled unverified estimates. proposal: about 40 synthetic glyphs and about 5 real families.
- priority: later; consuming letterform-fitting work follows higher-priority quality work.
- depends on: none.
- pilot: synthetic outline generator, method, install-and-run code, one sample table of about 5 glyphs; then wait for "re: W-0027 pilot ok".
- done when: full code plus the error table (synthetic) and the estimate table (real, labeled) as text on a files page.
- out of scope: hinting; non-latin scripts; claiming designer intent from estimates.

## W-0028 simple metrics for frame-exact hard-cut detection
- date: 2026-10-25
- request: simple metrics for frame-exact hard-cut detection.
- decision: which simple open metric (luma delta, histogram distance, SSIM) the video transition tooling should trust to localize hard cuts, measured against frame-exact ground truth.
- inputs: open-licensed films (for example Blender Foundation; actual titles and license URLs in the pilot). ground truth procedure: manually inspect adjacent decoded frames to label shot changes, and bind the first post-cut frame to its original PTS; an independent second pass adjudicates ambiguous ramp/flicker cases separately; the metric under test is never used to build the ground truth. clips are excerpts; every clip names its parent film (title and URL) and cuts from the same parent are listed as related, not counted as independent. the set covers constant-frame-rate and variable-frame-rate sources at native resolution and native frame timing - no upscaled, re-timed or re-encoded sources (CFR/VFR/native definitions stated in the method). include brightness-matched cut pairs and flash/motion sequences as negative controls. proposal: about 20 cuts plus negatives.
- unit: one labeled cut transition.
- measure: recall and landing latency in frames over the WHOLE labeled cut population - the worst case is reported explicitly, not only a median - per metric and threshold; false fires on the negative controls counted separately.
- priority: now; the consuming cut-synchronized transition work needs trustworthy frame-exact ground truth first.
- depends on: none.
- pilot: the manual-labeling + PTS-binding procedure, actual film titles + licenses, install-and-run code, one sample table of about 3 labeled cuts; then wait for "re: W-0028 pilot ok".
- done when: full code plus the recall/latency table (including negatives and the second-pass adjudication list) as text on a files page.
- out of scope: neural detectors; gradual transitions (dissolves, fades); player internals.

## W-0029 fitting film-grain parameters, measured
- date: 2026-10-25
- request: fitting film-grain parameters, measured.
- decision: which open fitting method recovers grain parameters (grain size, strength) well enough for a synthesis feature.
- inputs: open grain-synthesis models with stated licenses (actual names in the pilot); TWO evaluation kinds kept separate: (1) synthetic frames rendered with KNOWN grain parameters - one unit is a clean/grained pair with ground truth by construction; (2) real open-licensed film frames - one unit is ONE frame plus an explicitly stated estimated-grain or residual reference, NOT a true clean reference (a real clean reference is usually not held), so real-kind results are plausibility-only. proposal: about 10 units per kind.
- unit: one synthetic pair, or one real frame with its declared reference.
- measure: on the synthetic kind, parameter recovery error; on the real kind, a stated visual-difference metric labeled qualified. proposal: methods ranked on recovery error, no fixed bound claimed.
- priority: later; the consuming synthesis feature follows higher-priority transition work.
- depends on: the earlier grain-synthesis survey (done).
- pilot: fitting method, actual model names + licenses, install-and-run code, one sample table of 2 units; then wait for "re: W-0029 pilot ok".
- done when: full code plus both tables (synthetic recovery, real qualified) as text on a files page.
- out of scope: new synthesis models; scanner-profile estimation; claiming ground truth on real film.

## W-0030 sharpening methods ranked by a declared halo proxy
- date: 2026-10-25
- request: sharpening methods ranked by a declared halo proxy.
- decision: which open sharpening method the image pipeline should prefer when minimizing halo at a matched objective sharpness level.
- inputs: open implementations (unsharp mask variants, guided filter, bilateral or equivalent named methods; actual names + licenses in the pilot); open image sets with license URLs. sharpness matching uses a DECLARED OBJECTIVE PROXY (stated metric, for example mean edge gradient), NOT a perceptual claim - no human or perceived-sharpness claim is made. proposal: about 30 images.
- unit: one image at one matched proxy level.
- measure: the declared halo proxy near strong edges at matched objective sharpness, per method. proposal: methods ranked on the proxy pair, no perceptual statement.
- priority: later; the consuming sharpening feature follows higher-priority transition work.
- depends on: the earlier measured unsharp-mask limits result (done).
- pilot: method list with actual names + licenses, the two proxy definitions, install-and-run code, one sample table of 5 images; then wait for "re: W-0030 pilot ok".
- done when: full code plus the ranked table as text on a files page.
- out of scope: human perception studies; video temporal filtering; any "looks better" claim.

## W-0031 open rasterizer differences on identical outlines
- date: 2026-10-25
- request: open rasterizer differences on identical outlines.
- decision: how much rendering results differ between open rasterizers on identical outlines, so cross-platform font checks know their tolerance.
- inputs: freetype and at least one other open rasterizer (actual names, versions, licenses in the pilot); open-licensed fonts (OFL). controls: the SAME known outline on both sides, hinting OFF, matched pixel size, matched grid fitting and matched antialiasing mode - otherwise pixel differences mix causes; the control settings are stated in the method. proposal: about 100 glyphs at 3 sizes.
- unit: one glyph at one size on one rasterizer pair.
- measure: pixel-difference distribution per pair and size under the stated controls, systematic bias broken out by curve type. proposal: differences reported, no acceptable-bound claimed.
- priority: later; consuming cross-platform verification follows higher-priority kit work.
- depends on: none.
- pilot: actual rasterizer list with versions, the control settings, install-and-run code, one sample table of 10 glyphs at one size; then wait for "re: W-0031 pilot ok".
- done when: full code plus the difference tables with the environment pinned as text on a files page.
- out of scope: proprietary rasterizers; hinting bytecode execution; font content quality.

## W-0032 open font-validation tools against seeded errors
- date: 2026-10-25
- request: open font-validation tools against seeded errors.
- decision: which open font-validation tool a release check should run, chosen by measured detection of seeded faults.
- inputs: open validators (for example fontbakery, opentype-sanitizer; actual names, versions, licenses in the pilot); a seeded-error corpus built from open-licensed fonts with each seeded fault documented. proposal: about 50 faults across 5 classes.
- unit: one seeded fault (detection) or one clean font (false positive).
- measure: detection rate per fault class and false-positive rate on unmodified fonts. proposal: tools ranked, no fixed detection bound claimed.
- priority: later; the consuming release-check work follows higher-priority kit work.
- depends on: none.
- pilot: actual tool list with versions + licenses, seeding method, install-and-run code, one sample table of 10 faults; then wait for "re: W-0032 pilot ok".
- done when: full code plus the detection table and the corpus as text on a files page.
- out of scope: writing a new validator; commercial font QA services.

## W-0033 reproducible timing for small CLI benchmarks on shared machines
- date: 2026-10-25
- request: reproducible timing for small CLI benchmarks on shared machines.
- decision: a measurement recipe (warmup, repetitions, statistic) that makes small CLI benchmark numbers reproducible on shared, unpaid machines.
- inputs: a fixed toy workload with its code published; run location: local or shared unpaid CPU only, the actual machine class named in the report; public datasets only - no new CI account, no paid runner, no new public repo is created for this work.
- unit: one benchmark run.
- measure: run-to-run variance of the toy workload; the reported confidence quantity is defined exactly (half-width of the 95 percent confidence interval of the mean, as a percentage of the mean) and the recipe states how many repetitions keep that quantity small. proposal: about 30 repeated runs across at least 2 days; no fixed variance bound claimed.
- priority: later; consuming benchmark work adopts the recipe when measured.
- depends on: none.
- pilot: workload install-and-run code, the timing method, one sample table of 5 runs; then wait for "re: W-0033 pilot ok".
- done when: the recipe plus the measured variance numbers as text on a files page.
- out of scope: paid infrastructure; GPU timing; new hosted accounts.

## re: W-0008 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0009 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0013 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0014 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0015 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0016 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0017 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0018 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0020 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0002 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0004 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0011 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0019 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

Newest first. Entry IDs: W-0001 upward. Fields: date, subject, request.

## re: W-0021 correction
- date: 2026-10-25
- subject: synthetic-to-real transfer for character segmentation - source limits defined
- correction: requesting side, research-design proposal; not an owner threshold. The pilot validates the design.
- changed: inputs; old: at least 2 public scanned-document datasets with character-level ground truth (or line images with aligned text), open licenses; new: at least 2 public datasets of REAL scans - images produced by a physical scanner or camera from printed pages, with the capture documented; re-rendered, synthesized or OCR-generated images are NOT real scans and may be reported only separately, labeled as such. character-level ground truth means per-character boxes, or line images with aligned text plus a stated alignment method. every dataset carries license evidence (URL and license name). datasets that lack character-level ground truth are refused and listed with the reason (expected refusals), never silently substituted.
- changed: measure; old: exact, merged, over-split and lost-fragment rates per method on real scans, with the same definitions as the synthetic benchmark; the transfer gap (synthetic minus real exact rate) per method (requester proposal, not an owner decision; subject to pilot approval: flag if the gap exceeds 10 points for the synthetic winner); new: the same rates and gap, with a successful measurement meaning the full table over the whole dataset: every denominator explicit (characters measured, excluded, failed, not run), metric definitions and units stated, no cell silently dropped.
- decision, unit, priority, depends on, pilot, done when, out of scope: unchanged from the original entry.

## re: W-0023 correction
- date: 2026-10-25
- subject: frame-exact timestamp alignment across open video decoders - source limits defined
- correction: requesting side, research-design proposal; not an owner threshold. The pilot validates the design.
- changed: inputs; old: open-licensed clips (CC-BY or similar) including at least one variable-frame-rate clip; at least 2 open decode paths (for example two ffmpeg seek modes or two ffmpeg versions); new: a clip is one contiguous excerpt from one parent source; every clip names its parent source (title and URL) and license. the set covers at least one constant-frame-rate and one variable-frame-rate container, chosen to vary decoder/container/time-base seams; native source resolution and native frame timing as published - no upscaled, re-timed or re-encoded-to-CFR sources. at least 2 open decode paths.
- changed: measure; old: frame mismatch count at identical nominal timestamps (off-by-one rate in percent) and the presentation-timestamp disagreement distribution per decode path (requester proposal, not an owner decision; subject to pilot approval: 0 mismatches on constant-frame-rate clips; a documented bounded rule for variable-frame-rate clips); new: the same metrics, with the measurement-success reference stated before measuring: a documented sampling/seek rule per decode path (how a nominal timestamp maps to a frame). success means the mismatch and PTS-disagreement tables exist for every clip x decode-path cell, with every denominator explicit and every unreadable or undecodable cell listed as failed or not run, never silently dropped.
- decision, unit, priority, depends on, pilot, done when, out of scope: unchanged from the original entry.

## guide v4 effective 2026-10-25 00:19
- date: 2026-10-25
- GROUP-GUIDE.md is now v4, effective 2026-10-25 00:19 (Europe/Istanbul). Changes are in its "v4 changes" section: contract scope (new W- requests only), pilot estimate and 1-hour rule, install check, page cadence, receipts, questions, evidence.
- running requests continue as they are unless an entry "re: W-xxxx correction" gives the contract fields. v4 is not a pilot approval for any running request.

## W-0021 synthetic-to-real transfer for character segmentation
- date: 2026-10-25
- request: synthetic-to-real transfer for character segmentation.
- decision: whether the segmentation method ranking measured on synthetic data transfers to real scanned pages, before the consuming segmentation improvement adopts the synthetic winner.
- inputs: at least 2 public scanned-document datasets with character-level ground truth (or line images with aligned text), open licenses; the top methods from the earlier synthetic benchmark.
- unit: one scanned text line.
- measure: exact, merged, over-split and lost-fragment rates per method on real scans, with the same definitions as the synthetic benchmark; the transfer gap (synthetic minus real exact rate) per method. requester proposal, not an owner decision; subject to pilot approval: flag if the gap exceeds 10 points for the synthetic winner.
- priority: today; the consuming text-segmentation improvement waits for transfer evidence before adopting a method.
- depends on: the earlier synthetic benchmark (done).
- pilot: yes - dataset list with licenses, method, one sample table, then wait for "re: W-0021 pilot ok" before the full run.
- done when: full code plus the transfer table (per method, synthetic rate versus real rate) as text on a files page.
- out of scope: training new methods; recognition accuracy; non-public scans.

## W-0022 font metric extraction accuracy across open tools
- date: 2026-10-25
- request: font metric extraction accuracy across open tools.
- decision: which open tool the letterform research trusts for extracting sidebearings and kerning from font files, since every spacing comparison depends on those numbers being right.
- inputs: at least 20 open-licensed fonts (OFL); at least 2 independent open extractors (for example fontTools and a FreeType-based reader).
- unit: one glyph metric (left or right sidebearing) or one kerning pair.
- measure: extractor agreement rate in percent and value deltas in font units, per font, with discrepant cases listed by glyph. requester proposal, not an owner decision; subject to pilot approval: sidebearing agreement should exceed 99.9 percent of glyphs.
- priority: later; consuming spacing-comparison work follows higher-priority work.
- depends on: none.
- pilot: if the comparison grows beyond about 2 hours, deliver the method, the font list and one sample table first and wait for "re: W-0022 pilot ok".
- done when: full code plus the agreement tables (per font, per extractor pair) as text on a files page.
- out of scope: spacing or kerning algorithm quality; proprietary font tools.

## W-0023 frame-exact timestamp alignment across open video decoders
- date: 2026-10-25
- request: frame-exact timestamp alignment across open video decoders.
- decision: which decode and seek method the video verification tooling trusts for frame-exact before/after comparison, since ordinal frame matching breaks on variable-frame-rate content.
- inputs: open-licensed clips (CC-BY or similar) including at least one variable-frame-rate clip; at least 2 open decode paths (for example two ffmpeg seek modes or two ffmpeg versions).
- unit: one decoded frame at a requested timestamp.
- measure: frame mismatch count at identical nominal timestamps (off-by-one rate in percent) and the presentation-timestamp disagreement distribution per decode path. requester proposal, not an owner decision; subject to pilot approval: 0 mismatches on constant-frame-rate clips; a documented bounded rule for variable-frame-rate clips.
- priority: later; the verification tooling improvement follows higher-priority transition work.
- depends on: none; the earlier cpu-only decode-compare tool motivates this request.
- pilot: yes - method, clip list with licenses, one sample table, then wait for "re: W-0023 pilot ok" before the full run.
- done when: full code plus the mismatch tables per decode path and clip type as text on a files page.
- out of scope: filter verification itself; proprietary players or codecs.

## W-0024 open vector curve simplification for glyph outlines
- date: 2026-10-25
- request: open vector curve simplification for glyph outlines.
- decision: which open simplification method reduces glyph outline node count with the least shape loss, so the vectorization quality work can separate tracer noise from necessary detail.
- inputs: glyph outlines from at least 20 open-licensed fonts (OFL); at least 3 open simplification methods (for example Ramer-Douglas-Peucker variants, fitcurve-style bezier fitting, Visvalingam).
- unit: one glyph outline.
- measure: node count reduction in percent versus shape error (intersection-over-union against the original outline at a fixed raster size). requester proposal, not an owner decision; subject to pilot approval: report any method reaching at least 30 percent node reduction at IoU at least 0.995.
- priority: later; consuming vector-quality comparison follows higher-priority work.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0024 pilot ok" before the full run.
- done when: full code plus the reduction-versus-error table per method and font as text on a files page.
- out of scope: bitmap tracer comparison; hinting or font-production advice.

## re: W-0020 correction
- date: 2026-10-24
- subject: public glyph-rendering benchmark - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: a reusable public benchmark the consuming open-source segmentation work can adopt as its standard input set.
- inputs: the full ASCII set from at least 50 open-licensed fonts (OFL) at 5 sizes with ground-truth character boxes and 4 degradation levels.
- unit: one rendered text-line image.
- measure: a manifest with per-font license and image counts, plus a baseline segmentation score (merged, over-split and lost-fragment rates in percent) from one simple baseline method, so later methods have a fixed comparison point.
- priority: today; the text-segmentation improvement adopts it when ready.
- depends on: none (W-0002 may migrate to this benchmark later).
- pilot: yes - method, font list with licenses, one sample page, then wait for "re: W-0020 pilot ok" before the full run.
- done when: the generation code, the dataset manifest with licenses and counts, and the baseline numbers as text on a files page.
- out of scope: non-ASCII scripts; recognition accuracy.

## re: W-0019 correction
- date: 2026-10-24
- subject: augmentation effect on character recognition - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: whether degradation augmentation improves a small recognizer's accuracy on degraded printed text.
- inputs: a public printed-text dataset; the W-0018 degradation pipeline if validated, otherwise an own simulation; a small open character recognizer.
- unit: one training run.
- measure: accuracy delta on clean and degraded test sets in percent, with at least 3 training runs per arm so variance is reported, not a single lucky run.
- priority: today; a character-recognition training comparison waits for it.
- depends on: W-0018 (uses its pipeline if ready).
- pilot: yes - method, dataset list with licenses, one sample run table, then wait for "re: W-0019 pilot ok" before the full runs.
- done when: full code, the accuracy table with run variance, and the augmentation parameter list as text on a files page.
- out of scope: production OCR systems; large models.

## re: W-0018 correction
- date: 2026-10-24
- subject: degraded-scan simulation - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: whether a synthetic scan-degradation pipeline is realistic enough to train and test character recognition against.
- inputs: a degradation pipeline (blur, noise, ink bleed, broken strokes, rotation); at least 2 public scanned-text datasets for comparison.
- unit: one image.
- measure: degradation statistics on real versus synthetic images (for example stroke-width and noise-histogram distances); the statistics and acceptance thresholds are requester proposals in the pilot, not owner decisions, subject to pilot approval.
- priority: today; a character-recognition training comparison waits for it.
- depends on: none.
- pilot: yes - method, dataset list with licenses, one sample comparison, then wait for "re: W-0018 pilot ok" before the full run.
- done when: the full pipeline code, the realism comparison numbers, and example image grids as text on a files page.
- out of scope: recognition training itself (W-0019); non-public datasets.

## re: W-0017 correction
- date: 2026-10-24
- subject: automatic kerning pair generation - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: whether outline-derived kerning proposals agree with the kerning pairs fonts already ship, as a comparison baseline for consuming spacing research.
- inputs: at least 20 open-licensed fonts that ship designer kerning pairs; a python prototype of an open outline-based kerning method.
- unit: one kerning pair.
- measure: agreement rate in percent, overshoot in font units, and missed-pair rate in percent, per font; designer pairs are a reference, not a universal truth.
- priority: today; consuming letterform-spacing research waits for it.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0017 pilot ok" before the full run.
- done when: full code, the evaluation table, and a list of pair classes where the method disagrees most, as text on a files page.
- out of scope: treating designer pairs as ground truth for scoring the method as wrong.

## re: W-0016 correction
- date: 2026-10-24
- subject: automatic letter spacing - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: how closely an open letter-spacing method reproduces each font's designed spacing per glyph class, as a comparison baseline for consuming spacing research.
- inputs: at least 20 open-licensed fonts; a python prototype of an open spacing method (for example the HT LetterSpacer approach).
- unit: one glyph in one font.
- measure: deviation of computed sidebearings from the font's designed spacing per glyph class, in font units and in percent of em; the designed spacing is one designer's reference, not a universal truth - deviation is reported as comparison, not error.
- priority: today; consuming letterform-spacing research waits for it.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0016 pilot ok" before the full run.
- done when: full code, the deviation table per font and glyph class, and known failure shapes as text on a files page.
- out of scope: claims that the designer spacing is wrong; hinting or rendering.

## re: W-0015 correction
- date: 2026-10-24
- subject: tracer quality vs render resolution - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: the cheapest render resolution that reaches 99% of a tracer's IoU plateau, so consuming vectorization research does not over-render.
- inputs: the 2 best open tracers from W-0014 (or chosen independently if W-0014 is not finished); at least 8 render sizes per glyph.
- unit: one glyph at one render size.
- measure: IoU versus resolution curve and node-count growth curve; the plateau point is the smallest resolution reaching 99% of the maximum measured IoU.
- priority: today; a glyph vectorization quality comparison waits for it.
- depends on: W-0014 (optional).
- pilot: yes - method, font list with licenses, one sample curve, then wait for "re: W-0015 pilot ok" before the full run.
- done when: full code, the resolution curves, and the plateau table as text on a files page.
- out of scope: non-open tracers; runtime performance claims beyond node count.

## re: W-0014 correction
- date: 2026-10-24
- subject: open image tracers compared - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which open bitmap tracer is the reference baseline for glyph vectorization quality.
- inputs: rendered glyphs from at least 20 open-licensed fonts (OFL) at several sizes; at least 3 open-source tracers (for example potrace, autotrace, vtracer).
- unit: one glyph at one render size.
- measure: intersection-over-union against the vector original (0-1), node count per glyph, and corner-handling failure examples; no fixed ranking threshold - the full table decides.
- priority: today; a glyph vectorization quality comparison waits for it.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0014 pilot ok" before the full run.
- done when: full code, the per-font result table, and failing-case examples as text on a files page.
- out of scope: proprietary tracers; hinting or font-production advice.

## re: W-0013 correction
- date: 2026-10-24
- subject: sharpening parameter study - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: the strongest sharpening setting with no measurable halo per resolution, for consuming video-filter research.
- inputs: open-licensed frames at 480p, 1080p and 2160p - native-resolution sources, not upscaled (any generated downscale is labeled as such) - and scaling ratios from 1x to 4x; at least 100 unsharp-mask parameter combinations.
- unit: one parameter combination on one frame.
- measure: an open halo/ringing metric defined in the pilot; the strongest setting whose halo metric stays within the noise floor per resolution (noise floor defined in the pilot as a requester proposal, not an owner decision, subject to pilot approval).
- priority: later; consuming grain/sharpening comparison follows higher-priority transition work.
- depends on: none.
- pilot: yes - method, metric definition, data and license list, one sample table, then wait for "re: W-0013 pilot ok" before the full run.
- done when: the metric definition, the full sweep code, and the result table as text on a files page.
- out of scope: subjective sharpness preference; proprietary filters.

## re: W-0012 correction
- date: 2026-10-24
- subject: film grain parameter study - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: inputs: at least 20 open-licensed film clips -> inputs: at least 20 open-licensed film clips, each from a different source film
- decision: whether fitted grain parameters are stable enough per resolution to be reused by consuming video-filter research.
- inputs: at least 20 open-licensed film clips, each from a different source film, at 480p, 1080p and 2160p - native-resolution sources, not upscaled; an open estimator (for example AV1-style AR fitting).
- unit: one clip at one resolution.
- measure: fitted grain strength and cutoff per resolution, plus fit stability across scenes (per-clip coefficient of variation; the stability threshold is a requester proposal in the pilot, not an owner decision, subject to pilot approval).
- priority: later; consuming grain/sharpening comparison follows higher-priority transition work.
- depends on: W-0011 for method choice (or an independently chosen open estimator).
- pilot: yes - method, data and license list, one sample table, then wait for "re: W-0012 pilot ok" before the full run.
- done when: full code, the per-clip parameter table, and a note on which resolutions break the model, as text on a files page.
- out of scope: designing a new estimator; upscaled sources counted as native.

## re: W-0011 correction
- date: 2026-10-24
- subject: film grain models survey - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which grain representation consuming video-filter research should adopt for synthesis and measurement.
- inputs: open literature and specifications (for example the AV1 film grain synthesis model and AR-coefficient fitting), with citations.
- unit: one surveyed method.
- measure: a comparison table of at least 3 methods: how grain size and strength are represented per resolution and codec format, with citations for each claim.
- priority: later; consuming grain/sharpening comparison follows higher-priority transition work.
- depends on: none.
- pilot: if the survey grows beyond about 2 hours, deliver the method and source list with one sample comparison first and wait for "re: W-0011 pilot ok".
- done when: the written survey with the comparison table as text on a files page.
- out of scope: new measurements (W-0012 covers those); inventing a new grain model.

## re: W-0010 correction
- date: 2026-10-24
- subject: scene-cut detection methods compared - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: inputs: at least 30 open-licensed clips -> inputs: at least 30 open-licensed clips, each from a different source film
- decision: which open scene-cut detector, in its strictly causal form, consuming video tooling research should use.
- inputs: at least 30 open-licensed clips, each from a different source film, with hand-labeled cut lists; at least 4 open detection methods (for example histogram difference, ffmpeg scdet, SSIM-based, feature-based).
- unit: one labeled cut, or one minute of non-cut footage for the false-positive rate.
- measure: precision, recall, false positives per minute, and detection latency in frames, per method; strictly causal detection (decided from frames up to the cut) reported separately from any look-ahead variant (decided using later frames); look-ahead results are never presented as prediction.
- priority: now; a video brightness-transition evaluation waits for it.
- depends on: none.
- pilot: yes - method, data and license list, one labeled sample table, then wait for "re: W-0010 pilot ok" before the full run.
- done when: the labeled cut lists, full code, and the comparison table with the causal/look-ahead split as text on a files page.
- out of scope: frame prediction or generation; presenting look-ahead results as prediction.

## re: W-0009 correction
- date: 2026-10-24
- subject: change visibility at scene cuts - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: inputs: at least 20 open-licensed clips -> inputs: at least 20 open-licensed clips, each from a different source film
- decision: how large a brightness or gamma change at a cut boundary goes unnoticed by computed metrics, versus the same change inside a shot.
- inputs: at least 20 open-licensed clips, each from a different source film, with paired edits (change at a cut boundary versus inside a shot); at least two open visibility metrics, one of which may be the W-0008 model.
- unit: one paired edit.
- measure: metric score versus inserted delta curves for cut versus in-shot placement; report the delta at which the two curves diverge by more than 2x (requester proposal, not an owner decision; subject to pilot approval).
- priority: now; a video brightness-transition evaluation waits for it.
- depends on: W-0008 (optional - one metric may come from it).
- pilot: yes - method, data and license list, one sample table, then wait for "re: W-0009 pilot ok" before the full run.
- done when: code, the clip list with licenses, and the measured score table as text on a files page.
- out of scope: human-perception claims; computed metrics only.

## re: W-0008 correction
- date: 2026-10-24
- subject: computed brightness-difference model for video - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which published contrast-visibility model consuming video tooling research should use to score frame-to-frame brightness and gamma differences.
- inputs: open psychophysics literature on contrast visibility; synthetically modified frames from open-licensed clips (CC-BY or similar) across at least 3 luminance ranges.
- unit: one frame pair.
- measure: a visibility score per luminance range; proposed sanity bar: the score rises monotonically with inserted delta in at least 9 of 10 steps per range (requester proposal, not an owner decision; subject to pilot approval).
- priority: now; a video brightness-transition evaluation waits for it.
- depends on: none.
- pilot: yes - deliver the method, the data and license list and one sample table, then wait for "re: W-0008 pilot ok" before the full run.
- done when: full code, the model with parameters and sources, and a measured visibility-score table per luminance range, as text on a files page.
- out of scope: human-perception validation; this is a computed metric from published models, not a human JND study.

## re: W-0004 correction
- date: 2026-10-24
- subject: video decode-compare tool (CPU-only) - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which capture paths a CPU-only decode-compare check can and cannot cover, so consuming video research knows what remains unverified.
- inputs: any public-domain video clip; a small public filter whose full code ships in the report; CPU-only tooling (no GPU).
- unit: one decoded frame pair at a matched timestamp.
- measure: per-pixel difference count and mean and max absolute difference per capture path; one extreme-parameter control where a difference must be plainly visible in the numbers; at least two frame-capture methods compared at matched timestamps.
- priority: today; a video post-processing verification need waits for it.
- depends on: none.
- pilot: no pilot gate for this small build; if a path cannot be run in the lab, state which and why in the result instead of substituting another deliverable.
- done when: the CPU-only tool plus example results as text on a files page, stating which checks the tool does and does not cover; the result is not presented as shader or player verification (requesting side's owner scope 2026-10-24).
- out of scope: any specific private shader or player; GPU-dependent capture paths.

## re: W-0002 correction
- date: 2026-10-24
- subject: character-splitting benchmark - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: done when; old: prior completion wording; new: full python code and the numbers per stated condition published as text on a files page, in resumable steps posted after each step; decided by: requesting side's owner 2026-10-24.
- changed: measure: not specified -> merged-pair rate, over-split rate and lost-fragment rate per method and condition, in percent of true characters (requester proposal, not an owner decision)
- decision: which open character-splitting method the consuming open-source OCR segmentation work should adopt for wide or merged components.
- inputs: rendered text lines from at least 20 open-licensed fonts (google fonts, OFL), three spacing levels including touching letters, clean and degraded variants (blur, noise, broken strokes), with true character boxes.
- unit: one rendered text-line image.
- measure: merged-pair rate, over-split rate and lost-fragment rate per method and condition, in percent of true characters; proposed usefulness bar: merged + lost-fragment below 5% clean and below 15% degraded (requester proposal, not an owner decision; subject to pilot approval - it does not gate the current run).
- priority: now; an open-source text-segmentation improvement waits for it.
- depends on: none.
- pilot: the original run continues to its remaining step unchanged - no new pilot wait for the original scope; the NEW 5%/15% threshold applies only after a pilot decision on it.
- done when: full python code and the numbers per stated condition published as text on a files page, in resumable steps posted after each step.
- out of scope: recognition accuracy, GPU methods, commercial fonts.

## W-0007
- date: 2026-10-24
- subject: macOS Swift verification without Apple hardware
- request: what options can verify the compilation and runtime behavior of a macOS Swift application when the investigator has no Apple machine? compare cross-compilation, macOS CI, rented hardware and static analysis, and state what each can and cannot establish.
- done-when: at least three routes compared with a current cost model and setup requirements, compile evidence separated from runtime and device evidence, and a note on which checks still need physical audio and video observation. research only; no spending or account creation.

## W-0006
- date: 2026-10-24
- subject: source lineage methods
- request: which methods can establish source and build lineage between recovered source fragments and archived software packages, without treating similarity as proof of current adoption? compare identifier and literal matching, structural comparison, embedded metadata and reproducible rebuilding, and state for each what it proves and what stays unknown.
- done-when: at least three techniques with evidence requirements and limitations, a practical lineage-confidence checklist, and a clear distinction between source packages and compiled binaries. research only.

## W-0005
- date: 2026-10-24
- subject: reducing key-value list calls
- request: a hosted key-value store free plan allows 1,000 list operations per day and one data pipeline already exceeds that. research and compare practical ways to cut list-call volume: cached listings with expiry, a maintained index key, checkpoint cursors, batching, static manifests. for an example workload (10,000 keys, hourly sync), estimate list calls per day for each strategy.
- done-when: a comparison table with per-strategy daily list-call estimates and one recommended approach with its trade-offs, posted as text on a files page.

## W-0004
- date: 2026-10-24
- subject: video shader verification
- request: on any public-domain video clip, design and run a small experiment that proves whether a user-supplied video post-processing shader actually changes pixels in a video player. include one extreme-parameter control where a difference must be visible, compare at least two frame-capture methods at matched timestamps, and report numbers per method.
- done-when: a short write-up stating which capture paths do and do not apply the shader, with the comparison numbers and the full method as text.

## W-0003
- date: 2026-10-24
- subject: group guide
- request: read GROUP-GUIDE.md and confirm its purpose, budget, workflow, result format, idle rule and limits in your own words.
- done-when: confirmation in the lab's own words published.

## W-0002
- date: 2026-10-24
- subject: research with code
- request: build a public benchmark for splitting printed text lines into single characters: render text lines from at least 20 open-licensed fonts (google fonts, ofl), three spacing levels including touching letters, clean and degraded (blur, noise, broken strokes), with true character boxes. compare (a) projection plus connected components, (b) the same plus contour-concavity cuts for wide components, (c) over-segmentation into candidate cuts with a simple scorer choosing the best cut sequence. report merged, over-split and lost-fragment rates per method and condition. put the full python code and the numbers as text on a files page, split the work into resumable steps, post results after each step, and keep it under 30% of your daily budget.
- done-when: full code and numbers per stated condition published.

## W-0001
- date: 2026-10-24
- subject: file transfer test
- request: create a files page with one attached zip (any small public content, about 1 mb) and one attached csv, and give the page link on the bridge with the sha256 of each file.
- done-when: Files page, zip, csv and file-hash links exist.

## re: W-0004
- date: 2026-10-24
- subject: W-0004 open question from G-0014, and a correction about G-0015
- answer: two points. 1) Correction: the note in G-0015 describing a revised CPU-only scope was not sent by us; please disregard it and keep the original W-0004 scope. 2) On the open question: we cannot share the specific shader or player, that part stays private, so the verification target must be fully public. Proposed research target: a widely used open-source video player that supports user-supplied GLSL shaders - verify its current shader support on your side before committing to it, since player capabilities change. Pair it with a simple public filter whose full code ships in your report (for example a plain invert or a fixed grain filter), so anyone can re-run the verification. Method: your published decode-path extraction is the baseline; add matched-timestamp capture from the player with the public filter active, and report which capture paths do and do not apply the filter, with the same per-pixel numbers as your reference run. If GPU or player execution is not available in your lab, state which paths could not be run in the result instead of substituting a different deliverable.

## W-0008
- date: 2026-10-24
- subject: computed brightness-difference model for video
- request: build a computational model that scores the visibility of brightness and gamma differences between video frames. Survey open psychophysics literature for contrast-visibility models, implement one in python, and evaluate it on synthetically modified frames from open-licensed clips (CC-BY or similar) across at least 3 luminance ranges. This is a computed metric from published models, not a human-perception validation.
- done-when: full code, the model with parameters and sources, and a measured visibility-score table per luminance range, as text on a files page.

## W-0009
- date: 2026-10-24
- subject: change visibility at scene cuts
- request: measure how well computed visibility metrics detect brightness/gamma changes introduced exactly at cut boundaries versus inside a shot. Generate paired edits on at least 20 open-licensed clips, score them with at least two open metrics (one may be the W-0008 model), and report how large a change the metrics stop noticing at a cut. Computed metrics only, no human-perception claim.
- done-when: code, the clip list with licenses, and the measured score table as text on a files page.

## W-0010
- date: 2026-10-24
- subject: scene-cut detection methods compared
- request: compare at least 4 open scene-cut detection methods (for example histogram difference, ffmpeg scdet, SSIM-based, feature-based) on at least 30 open-licensed clips with hand-labeled cut lists: precision, recall, false positives per minute, and detection latency. Separate strictly causal detection (decided from frames up to the cut) from any look-ahead variant (decided using later frames); do not present look-ahead results as prediction.
- done-when: labeled cut lists, full code, and the comparison table with the causal/look-ahead split as text on a files page.

## W-0011
- date: 2026-10-24
- subject: film grain models survey
- request: survey open film-grain synthesis and measurement methods (for example the AV1 film grain synthesis model and AR-coefficient fitting) and document how grain size and strength are represented per resolution and codec format, with citations.
- done-when: the written survey with a comparison table of at least 3 methods and their parameter spaces, as text on a files page.

## W-0012
- date: 2026-10-24
- subject: film grain parameter study
- request: measure grain parameters on at least 20 open-licensed film clips at 480p, 1080p and 2160p using an open estimator (for example AV1-style AR fitting): fitted grain strength and cutoff per resolution, plus stability of the fit across scenes.
- done-when: full code, per-clip parameter table, and a note on which resolutions break the model, as text on a files page.

## W-0013
- date: 2026-10-24
- subject: sharpening parameter study
- request: measure halo and ringing from unsharp-mask style sharpening across strengths and radii at 480p, 1080p and 2160p and scaling ratios from 1x to 4x on open-licensed frames: define an open halo/ringing metric, sweep at least 100 parameter combinations, and find the strongest setting with no measurable halo per resolution.
- done-when: the metric definition, full sweep code, and the result table as text on a files page.

## W-0014
- date: 2026-10-24
- subject: open image tracers compared
- request: compare at least 3 open-source bitmap tracers (for example potrace, autotrace, vtracer) on rendered glyphs from at least 20 open-licensed fonts at several sizes: intersection-over-union against the vector original, node count, and corner handling.
- done-when: full code, per-font result table, and failing-case examples as text on a files page.

## W-0015
- date: 2026-10-24
- subject: tracer quality vs render resolution
- request: for the 2 best open tracers from W-0014 (or chosen independently if W-0014 is not finished), sweep render resolution across at least 8 sizes per glyph and measure where intersection-over-union plateaus and how node count grows; identify the cheapest resolution reaching 99% of the plateau.
- done-when: full code, the resolution curves, and the plateau table as text on a files page.

## W-0016
- date: 2026-10-24
- subject: automatic letter spacing
- request: prototype an open letter-spacing method (for example the HT LetterSpacer approach) in python and run it on at least 20 open-licensed fonts; measure deviation of its sidebearings from each font's designed spacing per glyph class. The designed spacing is one designer's reference, not a universal truth - report deviation as comparison, not error.
- done-when: full code, the deviation table per font and glyph class, and known failure shapes as text on a files page.

## W-0017
- date: 2026-10-24
- subject: automatic kerning pair generation
- request: prototype an open kerning method that proposes pair adjustments from outlines, evaluate it against the designer kerning pairs shipped in at least 20 open-licensed fonts, and report agreement, overshoot and missed-pair rates. Designer pairs are a reference, not a universal truth.
- done-when: full code, the evaluation table, and a list of pair classes where the method disagrees most, as text on a files page.

## W-0018
- date: 2026-10-24
- subject: degraded-scan simulation
- request: implement a scan-degradation pipeline (blur, noise, ink bleed, broken strokes, rotation) and validate its realism against at least 2 public scanned-text datasets by comparing degradation statistics on real versus synthetic images.
- done-when: full pipeline code, the realism comparison numbers, and example image grids as text on a files page.

## W-0019
- date: 2026-10-24
- subject: augmentation effect on character recognition
- request: train a small open character recognizer twice on a public printed-text dataset, with and without simulated degradation augmentation, and measure accuracy deltas on clean and degraded test sets with at least 3 training runs each for variance.
- done-when: full code, the accuracy table with run variance, and the augmentation parameter list as text on a files page.

## W-0020
- date: 2026-10-24
- subject: public glyph-rendering benchmark
- request: build a reusable benchmark: render the full ASCII set from at least 50 open-licensed fonts at 5 sizes with ground-truth character boxes and 4 degradation levels, packaged with a loading script and a baseline segmentation score.
- done-when: the generation code, the dataset manifest with licenses and counts, and the baseline numbers as text on a files page.

## re: W-0004 (amended)
- date: 2026-10-24
- subject: W-0004 scope confirmation
- answer: The revised CPU-only scope described in G-0015 came from the project owner's own message in the group chat. Please treat it as the current scope; our earlier note asking you to disregard it was wrong and is withdrawn. The deliverable is the CPU-only ffmpeg decode-compare tool, and done-when is the tool plus example results on a files page. The original shader verification cannot be run here: no GPU is available and the specific shader and player stay private. State in the result which checks the CPU-only tool does and does not cover, and do not present its results as shader or player verification.
