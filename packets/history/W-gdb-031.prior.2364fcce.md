# W-gdb-031 pause/resume atomic receipt vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-031

```packet-json
{
  "packet_id": "W-gdb-031",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PlaybackCore.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "resume() -> ResumeReceipt",
    "types": "ResumeReceipt { changedState: Bool, paceAnchorCleared: Bool }",
    "ownership_lifetime": "value receipt; idempotent; real clock preserved",
    "caller": "resume-receipt checker",
    "callee": "FramePump.resume() -> ResumeReceipt { changedState: Bool, paceAnchorCleared: Bool } (excerpt in packet)"
  },
  "test": {
    "command": "swift run pause-resume-tests",
    "expected": "exit 0; the 5 existing checks stay green; matrix rows replay green; a dropped paceAnchorCleared flag fails the affected vector",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/resume-receipt/",
      "Sources/pause-resume-tests/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/pause-resume-tests/PauseResumeTests.swift",
        "block": "rf0"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
    "command": "swift run pause-resume-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:30:27.751568+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL_CHECKS_PASS",
    "inline_files": [
      {
        "path": "Sources/pause-resume-tests/PauseResumeTests.swift",
        "block": "rf0",
        "sha256": "d11614dc35dc5af2f43181716c9f8103ab136d97458facc3c9bd84c090b74b82"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7b956940849678fe8fb1043a234d0854bdd2c15227311a383c7b9737aef0897b",
    "last_5_lines": [
      "cancelPaused: endReason=cancelled shown=[0.0, 0.04]",
      "seekPaused: shown=[0.0, 0.04, 5.0, 5.04] fenced=0",
      "close: endReason=cancelled windowClosed=true",
      "closePaused: endReason=cancelled",
      "ALL_CHECKS_PASS"
    ],
    "receipt_sha256": "336a00fe240ec8a4063e63ab895c591e573906a1cf8b4a7cde434a2df97538a8"
  }
}
```

## problem (what fails for the user)
FramePump.resume returns an atomic receipt (state-changed, old-anchor-cleared) replacing a racy two-step read; without vectors over the full op matrix (repeated resume, cancel-while-paused, seek-while-paused), a receipt regression reintroduces the race invisibly.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51; ResumeReceipt excerpt below); pause-resume-tests suite (5 checks, Linux per the harness map).
- real test command: swift run pause-resume-tests stays green.

## expected behaviour
vectors for the full operation matrix with expected receipt fields per sequence and the exact anchor re-establishment point; deterministic model clock; checker scores a candidate implementation's receipts.

## exact call site and interface
ResumeReceipt's fields (pinned excerpt) are the asserted vocabulary.

## behaviour that must not change
the 5 existing checks stay green; idempotence and the real clock are preserved.

## acceptance test (from the product repo)
the matrix replays green; a dropped anchor-cleared flag fails the affected vector.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 641-660 of 1382)
```swift id=source1
    public struct ResumeReceipt: Sendable, Equatable {
        public let changedState: Bool
        public let paceAnchorCleared: Bool
    }
    @discardableResult
    public func resume() -> ResumeReceipt {
        guard paused, let began = pauseBeganWall else {
            return ResumeReceipt(changedState: false, paceAnchorCleared: false)
        }
        let pausedWall = Swift.max(0, ProcessInfo.processInfo.systemUptime - began)
        paused = false
        pauseBeganWall = nil
        pausedWallTotal += pausedWall
        paceAnchorPts = nil
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .pauseResumed,
                       note: "pausedWall_s=\(pausedWall)")
        return ResumeReceipt(changedState: true, paceAnchorCleared: paceAnchorPts == nil)
    }
    /// The park loop: while paused, wait in bounded cancellable slices and
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"seq":["resume"],"pausedBefore":true,"expect":{"changedState":true,"paceAnchorCleared":true}},
 {"seq":["resume","resume"],"expect":[{"changedState":true,"paceAnchorCleared":true},{"changedState":false,"paceAnchorCleared":false}]}]
```


```text id=rf0
// M1 pause/resume/close tests (Linux): proves the typed pause contract on
// the ACTUAL FramePump - freeze with held frame un-admitted, cancel-safe
// park, resume arrival reanchor without lurch, seek-while-paused stale fence,
// window-close observer typed end. Pure Swift fakes; no FFmpeg.
// Deterministic: a WaitGate traps the pump inside a pacing wait when the
// test needs a HELD frame (fake clock otherwise outruns real sleeps).
import GorAVPlaybackCore
import Foundation

var failures = 0
func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

final class FakeClock: PlaybackClock, @unchecked Sendable { var t: Double = 0; func nowSeconds() -> Double { t } }
final class Recorder: FrameSink, @unchecked Sendable {
    private let l = NSLock(); var shown: [Double] = []; var showWalls: [Double] = []
    let clock: FakeClock
    init(_ c: FakeClock) { clock = c }
    func show(_ f: SourceFrame) async -> Bool { l.lock(); shown.append(f.ptsSeconds); showWalls.append(clock.t); l.unlock(); return true }
    func show(_ f: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool { await show(f) }
    func snapshot() -> ([Double], [Double]) { l.lock(); defer { l.unlock() }; return (shown, showWalls) }
}
final class ScriptedSource: FrameSource, @unchecked Sendable {
    private let l = NSLock()
    private var script: [Double] = []; private var idx = 0; private var endWhenDrained = false
    var pulls = 0
    func setScript(_ pts: [Double], end: Bool) { l.lock(); script = pts; idx = 0; endWhenDrained = end; l.unlock() }
    func pullCount() -> Int { l.lock(); defer { l.unlock() }; return pulls }
    func finish() { l.lock(); endWhenDrained = true; l.unlock() }
    func nextEvent() async -> SourceEvent {
        l.lock()
        defer { l.unlock() }
        pulls += 1
        guard idx < script.count else { return endWhenDrained ? .ended(.endOfStream) : .temporarilyUnavailable }
        let pts = script[idx]; idx += 1
        return .frame(SourceFrame(ptsSeconds: pts, durationSeconds: 0.04, digest: "d\(pts)"))
    }
}
/// Test-controlled wait gate: OPEN = advance fake time immediately;
/// CLOSED = block in real 1ms slices (traps the pump inside a long wait).
final class WaitGate: @unchecked Sendable {
    private let l = NSLock(); private var open = true
    func set(_ v: Bool) { l.lock(); open = v; l.unlock() }
    func isOpen() -> Bool { l.lock(); defer { l.unlock() }; return open }
}
func makeWait(_ clock: FakeClock, _ gate: WaitGate) -> @Sendable (Double) async -> Bool {
    { seconds in
        while !gate.isOpen() { try? await Task.sleep(nanoseconds: 1_000_000) }
        try? await Task.sleep(nanoseconds: 100_000)
        clock.t += seconds
        return true
    }
}
func realSleep(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
final class ClosedFlag: @unchecked Sendable {
    private let l = NSLock(); private var v = false
    func set() { l.lock(); v = true; l.unlock() }
    func value() -> Bool { l.lock(); defer { l.unlock() }; return v }
}

@main struct PauseResumeTests {
    static func main() async {
        // Exact argv positions, including legacy and sentinel truth table.
        do {
            let legacy = try PlayArguments(["p", "clip"])
            expect(legacy.holdSeconds == 4 && legacy.seekAtSeconds == nil, "argv: legacy")
            let pause = try PlayArguments(["p", "clip", "0", "-1", "-1", "1", "2"])
            expect(pause.pauseAtSeconds == 1 && pause.seekAtSeconds == nil, "argv: pause-only sentinel")
            let close = try PlayArguments(["p", "clip", "4", "-1", "-1", "-1", "-1", "3"])
            expect(close.closeAtSeconds == 3 && close.pauseAtSeconds == nil, "argv: close-only sentinel")
            let zero = try PlayArguments(["p", "clip", "4", "1", "0"])
            expect(zero.seekTargetSeconds == 0, "argv: target zero valid")
        } catch { expect(false, "argv: valid rejected \(error)") }
        for bad in [
            ["p"], ["p", "clip", "1e300"], ["p", "clip", "-1"], ["p", "clip", "nan"],
            ["p", "clip", "4", "1"], ["p", "clip", "4", "-1", "0"],
            ["p", "clip", "4", "-1", "-1", "2", "1"],
            ["p", "clip", "4", "-1", "-1", "1", "1"],
            ["p", "clip", "4", "-1", "-1", "1", "2", "inf"],
            ["p", "clip", "4", "-1", "-1", "1", "2", "3", "extra"]
        ] {
            do { _ = try PlayArguments(bad); expect(false, "argv: malformed accepted \(bad)") } catch { }
        }
        expect(!PlaySeekAcceptance.accepts(attempted: true, video: "committedAndReset", audio: "refusedMuted"), "combined: muted seek rejected")
        expect(!PlaySeekAcceptance.accepts(attempted: true, video: "committedAndReset", audio: "closeRequired"), "combined: close required rejected")
        expect(PlaySeekAcceptance.accepts(attempted: true, video: "committedAndReset", audio: "nativeReady"), "combined: both legs ready")
        // 1. HELD FRAME + ARRIVAL REANCHOR: a frame trapped in its pacing wait
        // is NOT admitted while paused; after resume it shows exactly once,
        // dropped==0, and resume selects a fresh arrival anchor.
        var case1Shown: [Double] = []
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource(); let gate = WaitGate()
            src.setScript([0, 0.04], end: false)
            let pump = FramePump(source: src, sink: rec, clock: clock, onWait: makeWait(clock, gate))
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { await realSleep(2) }
            gate.set(false)
            src.setScript([5.0, 5.04], end: false)
            await realSleep(10)                       // pump holds 5.0 inside the blocked pacing wait
            let anchorBefore = await pump.currentPaceAnchor
            await pump.pause()
            let _ = clock.t
            gate.set(true)                            // wait completes; pause gate parks the held frame
            await realSleep(40)
            expect(rec.snapshot().0.count == 2, "held: no show while paused (got \(rec.snapshot().0))")
            expect(await pump.isPaused, "held: isPaused observable")
            let pullsParked = src.pullCount()
            await realSleep(20)
            expect(src.pullCount() == pullsParked, "held: pulls frozen while paused")
            let resumeReceipt = await pump.resume()
            let _ = clock.t
            expect(await pump.pauseCount == 1, "held: exactly one pause recorded")
            expect(anchorBefore != nil, "held: pre-pause anchor exists")
            expect(resumeReceipt.changedState && resumeReceipt.paceAnchorCleared,
                   "held: atomic resume clears old arrival anchor, no double count")
            src.finish()                            // EOS after the queued pulls drain; no index reset
            // pump already consumed the pre-pause 5.0 as HELD; it re-decides and shows post-resume
            let stats = await run.value
            let (shown, _) = rec.snapshot()
            case1Shown = shown
            expect(shown == [0, 0.04, 5.0, 5.04], "held: shown \(shown) complete after resume, no loss")
            expect(stats.dropped == 0, "held: zero drops (got \(stats.dropped))")
            expect(stats.pauses == 1 && stats.pausedWallSeconds > 0, "held: receipts pauses=\(stats.pauses) pausedWall=\(stats.pausedWallSeconds)")
            expect(stats.pausedWallSeconds > 0.04 && stats.pausedWallSeconds < 1, "held: real monotonic pause duration")
            expect(stats.endReason == .endOfStream, "held: clean EOS (got \(stats.endReason.rawValue))")
            log("held: shown=\(shown) drops=\(stats.dropped) pausedWall=\(stats.pausedWallSeconds)")
        }
        expect(case1Shown == [0, 0.04, 5.0, 5.04], "held: final shown exact (got \(case1Shown))")
        // 2. IDEMPOTENCE: double pause / double resume count once.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource(); let gate = WaitGate()
            src.setScript([0, 0.04], end: false)
            let pump = FramePump(source: src, sink: rec, clock: clock, onWait: makeWait(clock, gate))
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { await realSleep(2) }
            await pump.pause(); await pump.pause()
            await realSleep(10)
            let firstResume = await pump.resume(), secondResume = await pump.resume()
            expect(firstResume.changedState && firstResume.paceAnchorCleared, "idem: first atomic receipt")
            expect(!secondResume.changedState && !secondResume.paceAnchorCleared, "idem: repeated resume no mutation")
            expect(await pump.pauseCount == 1, "idem: pause+pause counts once (got \(await pump.pauseCount))")
            src.setScript([], end: true)
            let stats = await run.value
            expect(stats.endReason == .endOfStream, "idem: EOS after resume (got \(stats.endReason.rawValue))")
            log("idem: pauseCount=1 EOS ok")
        }
        // 3. CANCEL WHILE PAUSED: typed cancelled end, no hang, no more shows.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource(); let gate = WaitGate()
            src.setScript([0, 0.04], end: false)
            let commit = CancelCommit(sessionEpoch: 42)
            let pump = FramePump(source: src, sink: rec, clock: clock, commit: commit, onWait: makeWait(clock, gate))
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { await realSleep(2) }
            await pump.pause()
            await realSleep(20)                        // parked at the top-of-loop gate
            commit.requestCancel()
            let stats = await run.value
            let pausedBeforeCancelledResume = await pump.isPaused
            let cancelResume = await pump.resume()
            expect(cancelResume.changedState == pausedBeforeCancelledResume,
                   "cancelPaused: atomic changed-state matches paused control state")
            expect(!cancelResume.changedState || cancelResume.paceAnchorCleared,
                   "cancelPaused: changed resume clears anchor atomically")
            expect(stats.cancelled && stats.endReason == .cancelled, "cancelPaused: typed cancelled (got \(stats.endReason.rawValue))")
            expect(rec.snapshot().0.count == 2, "cancelPaused: no show after cancel (got \(rec.snapshot().0))")
            log("cancelPaused: endReason=\(stats.endReason.rawValue) shown=\(rec.snapshot().0)")
        }
        // 4. SEEK WHILE PAUSED: held frame stale-fenced on resume (existing
        // admission path); post-seek frames show; never a live rewind.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource(); let gate = WaitGate()
            src.setScript([0, 0.04], end: false)
            let commit = CancelCommit(sessionEpoch: 43)
            let pump = FramePump(source: src, sink: rec, clock: clock, commit: commit, onWait: makeWait(clock, gate))
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { await realSleep(2) }
            gate.set(false)
            src.setScript([5.0], end: false)
            await realSleep(10)                        // pump holds 5.0 in the blocked wait
            await pump.pause()
            gate.set(true)                             // wait completes; pause gate parks the held frame
            await realSleep(30)
            expect(rec.snapshot().0.count == 2, "seekPaused: still held pre-seek (got \(rec.snapshot().0))")
            let ok = await pump.resetPresentation(seekLandingTarget: 5.0)
            expect(ok, "seekPaused: resetPresentation accepted while paused")
            src.setScript([5.0, 5.04], end: true)
            let seekResume = await pump.resume()
            expect(seekResume.changedState && seekResume.paceAnchorCleared, "seekPaused: atomic resume reanchor")
            let stats = await run.value
            let (shown, _) = rec.snapshot()
            expect(shown == [0, 0.04, 5.0, 5.04], "seekPaused: shown \(shown)")
            expect(stats.fencedShows >= 1 || stats.seekStalePulls >= 1,
                   "seekPaused: pre-seek held frame fenced typed (fenced=\(stats.fencedShows) stalePulls=\(stats.seekStalePulls))")
            log("seekPaused: shown=\(shown) fenced=\(stats.fencedShows)")
        }
        // 5. WINDOW CLOSE OBSERVER: close mid-run ends typed, no EOS lie.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource(); let gate = WaitGate()
            src.setScript([0, 0.04, 0.08, 0.12], end: false)
            let closed = ClosedFlag()
            let commit = CancelCommit(sessionEpoch: 44)
            let pump = FramePump(source: src, sink: rec, clock: clock, commit: commit,
                                 closeRequested: { await closed.value() }, onWait: makeWait(clock, gate))
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { await realSleep(2) }
            await closed.set()
            let stats = await run.value
            expect(stats.windowClosed && stats.endReason == .cancelled,
                   "close: typed windowClosed terminal (got \(stats.endReason.rawValue) windowClosed=\(stats.windowClosed))")
            expect(commit.isCancelled, "close: shared authority cancelled through teardown")
            log("close: endReason=\(stats.endReason.rawValue) windowClosed=\(stats.windowClosed)")
        }
        // 6. CLOSE WHILE PAUSED: the park honors close, typed end, no hang.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource(); let gate = WaitGate()
            src.setScript([0, 0.04, 5.0], end: false)
            let closed = ClosedFlag()
            let commit = CancelCommit(sessionEpoch: 45)
            let pump = FramePump(source: src, sink: rec, clock: clock, commit: commit,
                                 closeRequested: { await closed.value() }, onWait: makeWait(clock, gate))
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { await realSleep(2) }
            await pump.pause()
            await realSleep(20)
            await closed.set()
            let stats = await run.value
            expect(stats.windowClosed && stats.endReason == .cancelled, "closePaused: typed end while parked (got \(stats.endReason.rawValue))")
            log("closePaused: endReason=\(stats.endReason.rawValue)")
        }
        // 7. NaN master loss: actual pump must never admit a frame.
        do {
            let clock = FakeClock(); clock.t = .nan
            let rec = Recorder(clock); let src = ScriptedSource()
            src.setScript([0, 0.04], end: true)
            let pump = FramePump(source: src, sink: rec, clock: clock, onWait: makeWait(clock, WaitGate()))
            let stats = await pump.run()
            expect(stats.endReason == .failed(-93), "clock: typed fail-stop on nonfinite clock")
            expect(stats.shown == 0 && rec.snapshot().0.isEmpty, "clock: no NaN admission flood")
        }
        // 8. Pause is already PARKED before seek creates the landing exception.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource()
            src.setScript([8, 8.04], end: true)
            let pump = FramePump(source: src, sink: rec, clock: clock) { _ in
                try? await Task.sleep(nanoseconds: 1_000_000)
                return !Task.isCancelled
            }
            await pump.pause()
            let run = Task { await pump.run() }
            await realSleep(30)
            expect(src.pullCount() == 0, "parkedSeek: pause actually parked before seek")
            let reset = await pump.resetPresentation(seekLandingTarget: 8)
            expect(reset, "parkedSeek: reset accepted")
            let deadline = Date().addingTimeInterval(1)
            while rec.snapshot().0.isEmpty && Date() < deadline { await realSleep(1) }
            let paused = await pump.isPaused
            expect(paused && rec.snapshot().0 == [8], "parkedSeek: landing presented still paused")
            await realSleep(30)
            expect(rec.snapshot().0 == [8] && src.pullCount() == 1, "parkedSeek: frame0+1 re-frozen")
            run.cancel()
            _ = await run.value
        }
        // 8. RED-FIRST (arch-195a queue item 1, G2): paused seek 8.0 -> the
        // landing frame 8.0 presents WHILE STILL PAUSED; pre-target catch-up
        // frames never show; frame0+1 parks again.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource()
            src.setScript([7.92, 7.96, 8.0, 8.04], end: true)
            let commit = CancelCommit(sessionEpoch: 46)
            let pump = FramePump(source: src, sink: rec, clock: clock, commit: commit) { _ in
                try? await Task.sleep(nanoseconds: 1_000_000)
                return !Task.isCancelled
            }
            await pump.pause()
            let run = Task { await pump.run() }
            await realSleep(30)
            expect(src.pullCount() == 0, "item1-pausedSeek: pause parked before seek (pulls=\(src.pullCount()))")
            let reset = await pump.resetPresentation(seekLandingTarget: 8.0)
            expect(reset, "item1-pausedSeek: reset accepted")
            let deadline = Date().addingTimeInterval(1)
            while !rec.snapshot().0.contains(8.0) && Date() < deadline { await realSleep(2) }
            expect(rec.snapshot().0 == [8.0],
                   "item1-pausedSeek: frame0 8.0 presented while paused, pre-target 7.92/7.96 dropped (shown \(rec.snapshot().0))")
            await realSleep(30)
            expect(rec.snapshot().0 == [8.0] && src.pullCount() == 3,
                   "item1-pausedSeek: frame0+1 re-frozen while paused (shown \(rec.snapshot().0) pulls=\(src.pullCount()))")
            commit.requestCancel()
            _ = await run.value
        }
        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-tkkx1rvs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-tkkx1rvs/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Emitting module GorAVCore
[8/15] Compiling GorAVCore AdmissionTable.swift
[9/15] Compiling GorAVCore Boundary.swift
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Compiling pause_resume_tests PauseResumeTests.swift
/tmp/packet-proof-tkkx1rvs/tree/Sources/pause-resume-tests/PauseResumeTests.swift:204:52: warning: no 'async' operations occur within 'await' expression
                                 closeRequested: { await closed.value() }, onWait: makeWait(clock, gate))
                                                   ^
/tmp/packet-proof-tkkx1rvs/tree/Sources/pause-resume-tests/PauseResumeTests.swift:207:13: warning: no 'async' operations occur within 'await' expression
            await closed.set()
            ^
/tmp/packet-proof-tkkx1rvs/tree/Sources/pause-resume-tests/PauseResumeTests.swift:221:52: warning: no 'async' operations occur within 'await' expression
                                 closeRequested: { await closed.value() }, onWait: makeWait(clock, gate))
                                                   ^
/tmp/packet-proof-tkkx1rvs/tree/Sources/pause-resume-tests/PauseResumeTests.swift:226:13: warning: no 'async' operations occur within 'await' expression
            await closed.set()
            ^
[68/71] Emitting module pause_resume_tests
[69/72] Wrapping AST for pause-resume-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking pause-resume-tests
Build complete! (8.45s)
held: shown=[0.0, 0.04, 5.0, 5.04] drops=0 pausedWall=0.060227412999893204
idem: pauseCount=1 EOS ok
cancelPaused: endReason=cancelled shown=[0.0, 0.04]
seekPaused: shown=[0.0, 0.04, 5.0, 5.04] fenced=0
close: endReason=cancelled windowClosed=true
closePaused: endReason=cancelled
ALL_CHECKS_PASS
```
