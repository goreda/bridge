# W-gdb-198z-in2tinct-06 - Relocated fixture consumer cue-output-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-06",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/cue-output-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer cue-output-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/cue-output-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-06.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-06",
    "paths": [
      "Sources/cue-output-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-06.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-06.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.569219+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/cue-output-tests/main.swift",
        "block": "source1",
        "sha256": "afbc53191abd1c96cde81b70b8c9e41e5513090722f0e63917f03fadf718b944"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-06.py",
        "block": "fixtures1",
        "sha256": "b552a7fd7624d606c5aded0fb17a3f0a9a2f8ac9faf0876763f617f72279480b"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9368cb1f05119a16e7b4b3898f1daf4050dd75761d1e1376404f1fa14071abea",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-06; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "4812b1212bc01fe11bd1a9477b12dd1413145da6ad8344642b32feb90d89f845"
  }
}
```

```swift id=source1
import Foundation
import GorAVSubtitles
import GorAVPlaybackCore

// Witness for row 195b-56: emit-on-change, appear/disappear ordering, both
// slots, session fencing, non-finite clock skip, reset without leak, counters.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func track(_ id: UInt64 = 1) -> SubtitleTrack.Track {
    SubtitleTrack.Track(format: "srt",
        cues: [SubtitleCue(index: 0, startSeconds: 1, endSeconds: 3, lines: ["first"]),
               SubtitleCue(index: 1, startSeconds: 4, endSeconds: 6, lines: ["second"])],
        styles: [], unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
}

var ctl = SubtitleController()
ctl.selectPrimary(track())

// T1: first appearance emits appeared with the cue
var out = SubtitleCueOutput(session: 7)
let e1 = out.sample(session: 7, clock: 2.0, controller: ctl)
if case .appeared(let slot, let id, let cue)? = e1.first, e1.count == 1 {
    check("T1-appeared", slot == .primary && id.cueIndex == 0 && cue.text == "first")
} else { check("T1-appeared \(e1)", false) }

// T2: steady state emits nothing, countered
check("T2-steady", out.sample(session: 7, clock: 2.5, controller: ctl).isEmpty && out.counters.steady == 1)

// T3: cue end emits disappeared
let e3 = out.sample(session: 7, clock: 3.5, controller: ctl)
if case .disappeared(let slot, let id)? = e3.first, e3.count == 1 {
    check("T3-disappeared", slot == .primary && id.cueIndex == 0)
} else { check("T3-disappeared", false) }

// T4: gap between cues emits nothing
check("T4-gap", out.sample(session: 7, clock: 3.7, controller: ctl).isEmpty)

// T5: cue switch emits disappeared-then-appeared (sampled across the boundary)
let e5 = out.sample(session: 7, clock: 5.0, controller: ctl)
check("T5-switch", e5.count == 1)   // no prior cue active, only appeared
if case .appeared(_, let id, _)? = e5.first { check("T5-cue1", id.cueIndex == 1) } else { check("T5-cue1", false) }

// T6: direct switch without a gap: seek back into cue0 then forward into cue1
_ = out.sample(session: 7, clock: 2.0, controller: ctl)  // re-appear cue0... clock moved back; allowed (clock gate only checks finite)
_ = out.sample(session: 7, clock: 3.5, controller: ctl)  // disappear cue0
let e6 = out.sample(session: 7, clock: 5.0, controller: ctl)
check("T6", e6.count == 1)

// T7: direct overlap switch: a track with adjacent cues, sampled across
func track2() -> SubtitleTrack.Track {
    SubtitleTrack.Track(format: "srt",
        cues: [SubtitleCue(index: 0, startSeconds: 0, endSeconds: 2, lines: ["a"]),
               SubtitleCue(index: 1, startSeconds: 2, endSeconds: 4, lines: ["b"])],
        styles: [], unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
}
var ctl2 = SubtitleController(); ctl2.selectPrimary(track2())
var out2 = SubtitleCueOutput(session: 7)
_ = out2.sample(session: 7, clock: 1.0, controller: ctl2)
let e7 = out2.sample(session: 7, clock: 3.0, controller: ctl2)
check("T7-order", e7.count == 2)
if e7.count == 2, case .disappeared(_, let d) = e7[0], case .appeared(_, let a, _) = e7[1] {
    check("T7-seq", d.cueIndex == 0 && a.cueIndex == 1)
} else { check("T7-seq", false) }

// T8: session fencing - wrong session yields nothing, state untouched
let before = out2.counters
check("T8-fenced", out2.sample(session: 9, clock: 1.0, controller: ctl2).isEmpty
      && out2.counters.fencedSamples == before.fencedSamples + 1)

// T9: non-finite clock skipped, state untouched
let beforeA = out2.counters.appeared
check("T9-nan", out2.sample(session: 7, clock: .nan, controller: ctl2).isEmpty
      && out2.counters.skippedNonFiniteClock == 1 && out2.counters.appeared == beforeA)

// T10: reset drops state silently; the same clock then re-emits appeared (no leak, no stale disappear)
let clears = out2.reset()
check("T10-reset-clears-active", clears.count == 1)
check("T10-reset-counter", out2.counters.resets == 1)
let e10 = out2.sample(session: 7, clock: 3.0, controller: ctl2)
check("T10-reemit", e10.count == 1)
if case .appeared(_, let id, _)? = e10.first { check("T10-id", id.cueIndex == 1) } else { check("T10-id", false) }

// T11: secondary slot independent
var ctl3 = SubtitleController(); ctl3.selectPrimary(track()); ctl3.selectSecondary(track2())
var out3 = SubtitleCueOutput(session: 7)
let e11 = out3.sample(session: 7, clock: 1.5, controller: ctl3)
check("T11-both-slots", e11.count == 2)
check("T11-slots", e11.contains { if case .appeared(let s, _, _) = $0 { return s == .primary } else { return false } }
      && e11.contains { if case .appeared(let s, _, _) = $0 { return s == .secondary } else { return false } })

let bothClears = out3.reset()
check("T12-reset-both-slots", bothClears.count == 2 && out3.counters.disappeared == 2)
check("T12-reset-idempotent", out3.reset().isEmpty)


// Session delivery uses the same PlayheadTracker as the real embedded observer,
// not a free-running wall timer or a fake cue timestamp.
var live = SubtitleCueProducer(session: 71)
var render = SubtitleCueConsumer(session: 71)
var controller = SubtitleController(); controller.selectPrimary(track()); controller.selectSecondary(track())
controller.setDelay(0.5, slot: .secondary)
var clock = PlayheadTracker()
check("D1-no-anchor-no-time", clock.read(clockNow: 100, durationSeconds: nil) == nil)
_ = clock.firstFrame(anchor: 1.1, clockNow: 100, generation: clock.generation)
let firstBatch = live.sample(session: 71, generation: 0, filmTime: clock.read(clockNow: 100, durationSeconds: nil)!, controller: controller)!
check("D2-consume-primary", render.consume(firstBatch) && render.primary?.cue.text == "first" && render.secondary == nil)
clock.pause(clockNow: 100)
check("D3-paused-film-clock", live.sample(session: 71, generation: 0, filmTime: clock.read(clockNow: 110, durationSeconds: nil)!, controller: controller) == nil)
clock.resume(clockNow: 110)
let secondBatch = live.sample(session: 71, generation: 0, filmTime: clock.read(clockNow: 110.5, durationSeconds: nil)!, controller: controller)!
check("D4-delay-second-slot", render.consume(secondBatch) && render.primary != nil && render.secondary != nil)
check("D5-sequence-replay", !render.consume(firstBatch))
check("D6-source-session-fence", live.sample(session: 72, generation: 0, filmTime: 2, controller: controller) == nil)
check("D7-nan-fence", live.sample(session: 71, generation: 0, filmTime: .nan, controller: controller) == nil)
let reset = live.advance()!
check("D8-seek-clear-delivery", reset.reset && reset.generation == 1 && render.consume(reset) && render.primary == nil && render.secondary == nil)
check("D9-stale-batch-after-seek", !render.consume(secondBatch))
check("D10-stale-sample-after-seek", live.sample(session: 71, generation: 0, filmTime: 2, controller: controller) == nil)
clock.seekCommitted(anchor: nil, clockNow: 111, wasPaused: true)
check("D11-seek-awaits-anchor", clock.read(clockNow: 115, durationSeconds: nil) == nil)
_ = clock.firstFrame(anchor: 4.6, clockNow: 115, generation: clock.generation)
let landed = live.sample(session: 71, generation: 1, filmTime: clock.read(clockNow: 120, durationSeconds: nil)!, controller: controller)!
check("D12-paused-seek-landing-both", render.consume(landed) && render.primary?.cue.index == 1 && render.secondary?.cue.index == 1)
let replace = live.advance()!
controller = SubtitleController()
check("D13-replace-explicit-clear", render.consume(replace) && render.primary == nil && render.secondary == nil)
check("D14-replace-unloaded", live.sample(session: 71, generation: 2, filmTime: 4.6, controller: controller) == nil)
controller.selectPrimary(track())
let reselected = live.sample(session: 71, generation: 2, filmTime: 4.6, controller: controller)!
check("D15-reselection", render.consume(reselected) && render.primary?.cue.index == 1)
let closed = live.close()!
check("D16-close-clear-delivery", closed.closed && render.consume(closed) && render.primary == nil && render.secondary == nil)
check("D17-producer-sealed", live.sample(session: 71, generation: 2, filmTime: 2, controller: controller) == nil && live.advance() == nil && live.close() == nil)
check("D18-consumer-sealed", !render.consume(reselected) && !render.consume(closed))
var freshRender = SubtitleCueConsumer(session: 72)
check("D19-consumer-other-session", !freshRender.consume(firstBatch))
var fence = SubtitleCueConsumer(session: 71)
let unannounced = SubtitleCueBatch(session: 71, generation: 4, sequence: 99, reset: false, events: firstBatch.events)
check("D20-future-needs-reset", !fence.consume(unannounced))
let emptyReset = SubtitleCueBatch(session: 71, generation: 4, sequence: 100, reset: true, events: [])
_ = fence.consume(firstBatch)
check("D21-empty-reset-accepted", fence.consume(emptyReset) && fence.primary == nil && fence.secondary == nil)
let staleReset = SubtitleCueBatch(session: 71, generation: 3, sequence: 101, reset: true, events: [])
check("D22-old-generation-reset-refused", !fence.consume(staleReset))


// Actual temporary sidecars -> discovery -> parser -> selection -> producer -> consumer.
let sidecarDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: sidecarDirectory) }
func file(_ name: String, _ text: String) throws -> String {
    let p = sidecarDirectory.appendingPathComponent(name)
    try text.write(to: p, atomically: true, encoding: .utf8)
    return p.path
}
let videoPath = try file("film.mp4", "local fixture marker")
let exactSRT = try file("film.srt", "1\n00:00:01,000 --> 00:00:03,000\nexact cue\n")
let taggedSRT = try file("film.zz.srt", "1\n00:00:02,000 --> 00:00:04,000\ntagged cue\n")
let assPath = try file("film.ass", "[Script Info]\n")
_ = try file("film_other.srt", "not a matching sibling")
let secondVideo = try file("next.mp4", "local fixture marker")
let taggedOnlyVideo = try file("tagged.mp4", "local fixture marker")
_ = try file("tagged.en.srt", "1\n00:00:00,000 --> 00:00:10,000\ntagged only\n")
@MainActor final class Capture {
    var batches: [SubtitleCueBatch] = []
    var render: SubtitleCueConsumer
    init(_ session: UInt64) { render = SubtitleCueConsumer(session: session) }
    func accept(_ batch: SubtitleCueBatch) { batches.append(batch); _ = render.consume(batch) }
}
let capture = Capture(81)
let owner = SubtitleSidecarSession(session: 81, emit: { capture.accept($0) })
check("S1-local-source", owner.replaceSource(path: videoPath) == nil)
check("S2-stable-exact-tagged-discovery", owner.candidates.map { ($0.path as NSString).lastPathComponent } == ["film.ass", "film.srt", "film.zz.srt"])
check("S3-select-exact-SRT-not-ASS", await owner.loadExactPrimary() == .selected(path: exactSRT, slot: .primary))
owner.sample(session: 81, generation: owner.generation, filmTime: 1.5)
check("S4-real-parsed-cue-delivered", capture.render.primary?.cue.text == "exact cue")
check("S5-explicit-tag-secondary", await owner.select(path: taggedSRT, slot: .secondary) == .selected(path: taggedSRT, slot: .secondary))
owner.sample(session: 81, generation: owner.generation, filmTime: 2.5)
check("S6-both-real-slots", capture.render.primary?.cue.text == "exact cue" && capture.render.secondary?.cue.text == "tagged cue")
check("S7-delay-valid", owner.setDelay(2, slot: .secondary) == nil && capture.render.secondary == nil)
check("S8-delay-invalid-refused", owner.setDelay(.nan, slot: .secondary) == .invalidDelay)
owner.setVisible(false, slot: .primary)
check("S9-hide-clears", capture.render.primary == nil)
owner.reset()
check("S10-reset-keeps-primary-clears-secondary-delay", capture.render.primary?.cue.text == "exact cue" && capture.render.secondary == nil && owner.controller.secondaryDelay == 0)
check("S11-ASS-typed-refusal", await owner.select(path: assPath, slot: .primary) == .refused(.unsupportedASS))
check("S12-nondiscovered-refusal", await owner.select(path: "/tmp/not-discovered.srt", slot: .primary) == .refused(.notDiscovered))
let priorBatch = capture.batches.last!
owner.seekBegan()
check("S13-seek-clear", capture.render.primary == nil && capture.batches.last?.reset == true)
check("S14-old-batch-after-seek", !capture.render.consume(priorBatch))
owner.sample(session: 81, generation: owner.generation, filmTime: 2)
check("S15-postseek-cue", capture.render.primary?.cue.text == "exact cue")
check("S16-source-replace-clear", owner.replaceSource(path: secondVideo) == nil && capture.render.primary == nil && owner.controller.primary == nil)
check("S17-no-exact-is-not-error", await owner.loadExactPrimary() == .noExactSidecar)
_ = owner.replaceSource(path: taggedOnlyVideo)
check("S18-no-language-default", await owner.loadExactPrimary() == .noExactSidecar && owner.controller.primary == nil)
check("S19-remote-source-refused", owner.replaceSource(path: "https://example.invalid/film.mp4") == .unsupportedSource && owner.candidates.isEmpty)

// Controlled suspended loader proves late async completion fences; data still
// comes from the actual SubtitleTrack loader after the continuation is released.
actor HeldSidecarLoader {
    private var waiting: CheckedContinuation<Void, Never>?
    private var started = false
    private var released = false
    func load(_ path: String) async throws -> SubtitleTrack.Track {
        started = true
        await withCheckedContinuation { cont in
            if released { cont.resume() } else { waiting = cont }
        }
        return try SubtitleTrack.load(path: path)
    }
    func isWaiting() -> Bool { started && (waiting != nil || released) }
    func release() { released = true; waiting?.resume(); waiting = nil }
}
func waitForLoader(_ loader: HeldSidecarLoader) async {
    for _ in 0..<1000 { if await loader.isWaiting() { return }; await Task.yield() }
}
let held = HeldSidecarLoader(), heldCapture = Capture(82)
let delayed = SubtitleSidecarSession(session: 82, emit: { heldCapture.accept($0) }, loader: { try await held.load($0) })
_ = delayed.replaceSource(path: videoPath)
let pending = Task { await delayed.loadExactPrimary() }
await waitForLoader(held)
_ = delayed.replaceSource(path: secondVideo)
await held.release()
check("S20-replace-stale-completion", await pending.value == .refused(.staleCompletion) && delayed.controller.primary == nil && heldCapture.render.primary == nil)
let closeLoader = HeldSidecarLoader(), closeCapture = Capture(83)
let closing = SubtitleSidecarSession(session: 83, emit: { closeCapture.accept($0) }, loader: { try await closeLoader.load($0) })
_ = closing.replaceSource(path: videoPath)
let pendingClose = Task { await closing.loadExactPrimary() }
await waitForLoader(closeLoader)
closing.close(); await closeLoader.release()
check("S21-close-stale-completion", await pendingClose.value == .refused(.staleCompletion) && closeCapture.batches.last?.closed == true && closing.controller.primary == nil)
let seekLoader = HeldSidecarLoader()
let seeking = SubtitleSidecarSession(session: 84, emit: { _ in }, loader: { try await seekLoader.load($0) })
_ = seeking.replaceSource(path: videoPath)
let pendingSeek = Task { await seeking.loadExactPrimary() }
await waitForLoader(seekLoader)
seeking.seekBegan(); await seekLoader.release()
check("S22-seek-stale-completion", await pendingSeek.value == .refused(.staleCompletion) && seeking.controller.primary == nil)
let cancelLoader = HeldSidecarLoader()
let cancelling = SubtitleSidecarSession(session: 85, emit: { _ in }, loader: { try await cancelLoader.load($0) })
_ = cancelling.replaceSource(path: videoPath)
let pendingCancel = Task { await cancelling.loadExactPrimary() }
await waitForLoader(cancelLoader)
pendingCancel.cancel(); await cancelLoader.release()
check("S23-task-cancel-refuses-adoption", await pendingCancel.value == .refused(.staleCompletion) && cancelling.controller.primary == nil)
// Deterministic latch probe: release BEFORE the loader ever runs must not
// deadlock (old unlatched release() was a no-op here and parked the loader
// forever). Under the latch the arm-time check resumes immediately.
let preReleased = HeldSidecarLoader()
await preReleased.release()
let preSession = SubtitleSidecarSession(session: 88, emit: { _ in }, loader: { try await preReleased.load($0) })
_ = preSession.replaceSource(path: videoPath)
check("S23b-release-before-arm", await preSession.loadExactPrimary() == .selected(path: exactSRT, slot: .primary))
_ = owner.replaceSource(path: videoPath); _ = await owner.loadExactPrimary()
owner.sample(session: 81, generation: owner.generation, filmTime: 2)
owner.close()
check("S24-active-close-clear", capture.render.primary == nil && capture.batches.last?.closed == true)
check("S25-closed-select-refuses", await owner.loadExactPrimary() == .refused(.closed))

let malformedVideo = try file("broken.mp4", "marker")
let malformedPath = try file("broken.srt", "not a valid SRT")
let typed = SubtitleSidecarSession(session: 86, emit: { _ in })
_ = typed.replaceSource(path: malformedVideo)
check("S26-malformed-refusal", await typed.loadExactPrimary() == .refused(.malformed))
try FileManager.default.removeItem(atPath: malformedPath)
check("S27-discovered-now-unreadable", await typed.loadExactPrimary() == .refused(.unreadable))
let assOnlyVideo = try file("styled.mp4", "marker")
_ = try file("styled.ass", "[Script Info]\n")
_ = typed.replaceSource(path: assOnlyVideo)
check("S28-exact-ASS-not-silently-parsed", await typed.loadExactPrimary() == .refused(.unsupportedASS))
let resetLoader = HeldSidecarLoader()
let resetting = SubtitleSidecarSession(session: 87, emit: { _ in }, loader: { try await resetLoader.load($0) })
_ = resetting.replaceSource(path: videoPath)
let pendingReset = Task { await resetting.loadExactPrimary() }
await waitForLoader(resetLoader)
resetting.reset(); await resetLoader.release()
check("S29-reset-stale-load", await pendingReset.value == .refused(.staleCompletion))
actor FirstHeldLoader {
    let first = HeldSidecarLoader()
    var count = 0
    func load(_ path: String) async throws -> SubtitleTrack.Track {
        count += 1
        if count == 1 { return try await first.load(path) }
        return try SubtitleTrack.load(path: path)
    }
}
let overlapLoader = FirstHeldLoader()
let overlap = SubtitleSidecarSession(session: 88, emit: { _ in }, loader: { try await overlapLoader.load($0) })
_ = overlap.replaceSource(path: videoPath)
let earlierSelection = Task { await overlap.select(path: exactSRT, slot: .primary) }
await waitForLoader(overlapLoader.first)
let laterSelection = await overlap.select(path: taggedSRT, slot: .primary)
await overlapLoader.first.release()
let earlierOutcome = await earlierSelection.value
check("S30-last-selection-wins", laterSelection == .selected(path: taggedSRT, slot: .primary)
      && earlierOutcome == .refused(.staleCompletion) && overlap.controller.primary?.cues.first?.text == "tagged cue")

let outsideDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: outsideDirectory) }
let outsideSidecar = outsideDirectory.appendingPathComponent("outside.srt")
try "1\n00:00:00,000 --> 00:00:03,000\noutside\n".write(to: outsideSidecar, atomically: true, encoding: .utf8)
try FileManager.default.createSymbolicLink(atPath: sidecarDirectory.appendingPathComponent("film.escape.srt").path,
                                         withDestinationPath: outsideSidecar.path)
let bounded = SubtitleSidecarSession(session: 89, emit: { _ in })
_ = bounded.replaceSource(path: videoPath)
check("S31-sibling-symlink-escape-not-discovered", !bounded.candidates.contains { $0.tag == "escape" })
check("S32-nonexistent-video-typed", bounded.replaceSource(path: sidecarDirectory.appendingPathComponent("missing.mp4").path) == .sourceUnavailable)
// arch-196s H0595 (W-gdb-005 + W-gdb-036): fixture row packs wired in by integrator (INTEGRATION.md).
let sidecarRows = SidecarFixtureRows.run(packPath: "kits/sidecar-fixtures/expected")
let cueRows = CueBatchFixtureRows.run(packPath: "kits/cue-batch-fixtures/expected")
let totalPass = passed + sidecarRows.pass + cueRows.pass
let totalFail = failed + sidecarRows.fail + cueRows.fail
print("cue-output-tests: \(totalPass) PASS, \(totalFail) FAIL")
exit(totalFail == 0 ? 0 : 1)

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/cue-output-tests/main.swift').read_bytes()).hexdigest()=='afbc53191abd1c96cde81b70b8c9e41e5513090722f0e63917f03fadf718b944'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-06; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-06; baseline only, product change and semantic test still required
```

secret scan: clean
