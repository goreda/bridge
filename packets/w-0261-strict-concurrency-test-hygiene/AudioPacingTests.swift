// AudioPacingTests - M1 (164h) audio-master pacing qualification on the
// CURRENT-main surface (de9a3304): real GorAVAudioClock (C core) through
// the GorAVAudioClockSwift binding, the AudioPacingPolicy epoch mapping,
// and the REAL GorAVPlaybackCore FramePump + AVSyncDecider driven by a
// synthetic sink's device-consumed counter. No guard-v2 / ReadyGate types
// (absent from main, out of M1). Linux comp-scope evidence, NOT Mac
// qualification: the AudioUnit render callback itself is Mac-gated.

import XCTest
import GorAVPlaybackCore
import GorAVAudioClockSwift

/// Synthetic sink: the ONLY media-position authority is its
/// device-consumed frame counter (8.2: submitted-but-unheard never
/// counts). The "host" reading here is a fake shared wall clock, locked
/// to the counter for determinism.
private final class FakeWorld {
    var host: Double = 100.0           // fake shared wall clock (seconds)
    var consumed: Int64 = 0            // device-consumed frames
    let rate: UInt32 = 48000
    func hostNow() -> Double { host }
    /// Advance the wall AND the device in lockstep (perfect correlation).
    func advance(_ seconds: Double) {
        host += seconds
        consumed += Int64((seconds * Double(rate)).rounded())
    }
}

private func makePolicy(_ w: FakeWorld, tol: Double = 0.002) -> AudioPacingPolicy {
    AudioPacingPolicy(hostClock: { w.hostNow() }, sampleRate: w.rate,
                      consistencyTolerance: tol)!
}

private final class ScriptedSource: FrameSource, @unchecked Sendable {
    private var events: [SourceEvent]
    private var index = 0
    init(_ events: [SourceEvent]) { self.events = events }
    func nextEvent() async -> SourceEvent {
        let e = events[min(index, events.count - 1)]
        if index < events.count - 1 { index += 1 }
        return e
    }
}

private final class RecordingSink: FrameSink, @unchecked Sendable {
    private(set) var shownDigests: [String] = []
    var onShow: ((SourceFrame) -> Void)?
    func show(_ frame: SourceFrame) async -> Bool {
        shownDigests.append(frame.digest); onShow?(frame); return true
    }
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        shownDigests.append(frame.digest); onShow?(frame); return true
    }
}

final class AudioPacingTests: XCTestCase {

    /// Anchor at session start: the value is CONTINUOUS with the wall
    /// clock at the switch instant and advances at host rate while the
    /// device tracks (extrapolation between anchors).
    func test01_sessionStartAnchorIsWallContinuous() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        // Pre-anchor: wall fallback, no master, no loss.
        XCTAssertEqual(clock.nowSeconds(), 100.0, accuracy: 1e-9)
        XCTAssertFalse(clock.hasMaster)
        XCTAssertFalse(clock.masterLost)
        // Anchor at host 100, consumed 0.
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        XCTAssertTrue(clock.hasMaster)
        // Continuous at the switch: exactly 100; monotonic across it.
        XCTAssertEqual(clock.nowSeconds(), 100.0, accuracy: 1e-9)
        w.advance(1.0)
        XCTAssertEqual(clock.nowSeconds(), 101.0, accuracy: 1e-9)
        XCTAssertEqual(policy.counters.generation, 1)
        XCTAssertEqual(policy.counters.anchorsAccepted, 1)
        XCTAssertEqual(policy.counters.anchorRefusals, 0)
    }

    /// Same-generation re-anchor within tolerance tracks the device's
    /// actual rate: a 1000 ppm-slow device is measured (driftPPM) and the
    /// re-based offset keeps the value continuous at the re-anchor.
    func test02_driftMeasuredAndReanchorContinuous() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        // Wall advances 1 s; the device consumed only 47,952 (-1 ms).
        w.host = 101.0; w.consumed = 47952
        let before = clock.nowSeconds()   // 101.0 by extrapolation
        XCTAssertEqual(before, 101.0, accuracy: 1e-9)
        XCTAssertEqual(policy.periodicAnchor(consumedFrames: 47952, atHost: 101.0), .ok)
        // Continuous at the re-anchor instant.
        XCTAssertEqual(clock.nowSeconds(), 101.0, accuracy: 1e-9)
        // Between anchors the value extrapolates at host rate from the
        // re-anchored device position (drift is measured by driftPPM and
        // corrected at each re-anchor, never by bending the clock rate):
        // 0.999 s device position + 1.0 s host extrapolation, offset
        // re-based, = 102.0 and continuous at the re-anchor instant.
        w.host = 102.0; w.consumed = 95904
        XCTAssertEqual(clock.nowSeconds(), 102.0, accuracy: 1e-9)
        XCTAssertEqual(policy.periodicAnchor(consumedFrames: 95904, atHost: 102.0), .ok)
        XCTAssertEqual(policy.counters.anchorsAccepted, 3)
        let d = policy.driftPPM()
        XCTAssertEqual(d.status, .ok)
        XCTAssertEqual(d.ppm ?? 1, -1000.0, accuracy: 1.0)
        XCTAssertEqual(policy.counters.anchorsAccepted, 3)
        XCTAssertEqual(policy.counters.anchorRefusals, 0)
    }

    /// Beyond-tolerance re-anchor: typed refusal, counted, previous
    /// anchor and offset stay in force.
    func test03_beyondToleranceReanchorRefused() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.host = 101.0; w.consumed = 46000   // ~41.7 ms behind prediction
        XCTAssertEqual(policy.periodicAnchor(consumedFrames: 46000, atHost: 101.0), .inconsistent)
        XCTAssertEqual(policy.counters.anchorRefusals, 1)
        XCTAssertEqual(policy.counters.lastAnchorStatus, .inconsistent)
        // Previous mapping still in force (extrapolated 101.0).
        XCTAssertEqual(clock.nowSeconds(), 101.0, accuracy: 1e-9)
    }

    /// Typed pause/resume: value frozen while quiesced (repeated reads
    /// equal), resume mints a NEW generation re-anchored on the frozen
    /// consumed counter, value continues from the frozen point (no jump),
    /// the old generation is fenced.
    func test04_pauseFreezeResumeNewGeneration() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(2.0)                       // host 102, consumed 96000
        XCTAssertEqual(clock.nowSeconds(), 102.0, accuracy: 1e-9)
        XCTAssertTrue(policy.pause(atHost: 102.0))
        XCTAssertFalse(policy.pause(atHost: 102.0))   // typed idempotent refusal
        // Quiesced: wall advances, the consumed counter is held; the value
        // is FROZEN (no drift decisions, no extrapolation).
        w.host = 105.0
        XCTAssertEqual(clock.nowSeconds(), 102.0, accuracy: 1e-9)
        XCTAssertEqual(clock.nowSeconds(), 102.0, accuracy: 1e-9)
        // Resume: new generation, anchored on the frozen counter.
        XCTAssertTrue(policy.resume(consumedFrames: 96000, atHost: 105.0))
        XCTAssertEqual(policy.counters.generation, 2)
        XCTAssertEqual(policy.counters.pauseTransitions, 1)
        XCTAssertEqual(policy.counters.resumeTransitions, 1)
        // Continuous from the frozen value; advances from there.
        XCTAssertEqual(clock.nowSeconds(), 102.0, accuracy: 1e-9)
        w.advance(1.0)
        XCTAssertEqual(clock.nowSeconds(), 103.0, accuracy: 1e-9)
        // The old generation is fenced.
        XCTAssertEqual(policy.clock.anchor(generation: 1, consumedSamples: 96000,
                                           sampleRate: 48000, hostTime: 106.0,
                                           consistencyTolerance: 0.002), .staleGeneration)
        XCTAssertFalse(clock.masterLost)
    }

    /// Seek ring reset: new generation, media restarts at 0, the value is
    /// continuous AND monotonic across the reset (the pump re-anchors pts
    /// on arrival); the old generation is fenced.
    func test05_seekResetKeepsValueContinuous() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(10.0)                      // host 110, consumed 480000
        XCTAssertEqual(clock.nowSeconds(), 110.0, accuracy: 1e-9)
        // Ring reset: consumed restarts at 0.
        w.consumed = 0
        XCTAssertEqual(policy.seekReset(atHost: 110.0), .ok)
        XCTAssertEqual(policy.counters.generation, 2)
        XCTAssertEqual(policy.counters.seekGenerationResets, 1)
        // Continuous at the reset instant, monotonic after.
        XCTAssertEqual(clock.nowSeconds(), 110.0, accuracy: 1e-9)
        w.advance(1.0)
        XCTAssertEqual(clock.nowSeconds(), 111.0, accuracy: 1e-9)
        XCTAssertEqual(policy.clock.anchor(generation: 1, consumedSamples: 0,
                                           sampleRate: 48000, hostTime: 111.0,
                                           consistencyTolerance: 0.002), .staleGeneration)
    }

    /// 2.2 no substitution: after teardown the master is fenced, the
    /// reading fails STOP (NaN + masterLost), never a wall fallback.
    func test06_masterLostFailsStopNeverSubstitutes() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(1.0)
        policy.sessionStop()
        XCTAssertTrue(clock.nowSeconds().isNaN)
        XCTAssertTrue(clock.masterLost)
        XCTAssertFalse(clock.hasMaster)
    }

    /// Rate change inside one generation is a typed RATE_CHANGE (a new
    /// generation is the only lawful carrier, 8.5).
    func test07_rateChangeRefusedWithinGeneration() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        XCTAssertEqual(policy.clock.anchor(generation: 1, consumedSamples: 0,
                                           sampleRate: 96000, hostTime: 101.0,
                                           consistencyTolerance: 0.002), .rateChange)
    }

    /// REAL FramePump on the current-main API, clocked by the adapter:
    /// the synthetic sink's consumed counter drives show / wait / drop.
    /// (Candidate scenario ported to the unguarded decider; no
    /// DecisionRefusal/decisionFencedDrops types exist on main.)
    func test08_sinkCounterDrivesRealPumpDecisions() async throws {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(1.0)                       // media 1.0

        let source = ScriptedSource([
            .frame(SourceFrame(ptsSeconds: 1.0, durationSeconds: 0.04, digest: "f1-on-time")),
            .frame(SourceFrame(ptsSeconds: 1.04, durationSeconds: 0.04, digest: "f2-early")),
            .frame(SourceFrame(ptsSeconds: 1.06, durationSeconds: 0.04, digest: "f3-late")),
            .ended(.endOfStream),
        ])
        let display = RecordingSink()
        // f3 arrives after the sink consumed up to media 2.0: 0.94 s late
        // against the audio master -> drop.
        display.onShow = { frame in
            if frame.digest == "f2-early" { w.consumed = 96000; w.host = 102.0 }
        }
        let pump = FramePump(source: source, sink: display, clock: clock,
                             decider: AVSyncDecider(maxWaitSeconds: 1.0, master: .clock),
                             onWait: { seconds in
            w.advance(seconds)               // the sink keeps consuming
            return true
        })
        let stats = await pump.run()
        XCTAssertEqual(stats.endReason, .endOfStream)
        XCTAssertEqual(stats.shown, 2)
        XCTAssertEqual(stats.dropped, 1)
        XCTAssertEqual(stats.digestsShown, ["f1-on-time", "f2-early"])
        XCTAssertFalse(clock.masterLost)
    }

    /// Seek WHILE PAUSED (J3 20:08 finding): the frozen value survives
    /// the reset (resume never refuses on a cleared freeze), resume
    /// anchors the post-seek position (consumed=0) at the frozen value,
    /// and the value stays continuous/monotonic through the whole
    /// sequence. Counters reconcile: 1 pause, 1 seek reset, 1 resume.
    func test10_pausedSeekResumeStaysContinuous() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(4.0)                       // host 104, consumed 192000
        XCTAssertTrue(policy.pause(atHost: 104.0))
        // Seek lands while quiesced: ring resets, consumed restarts at 0.
        w.host = 104.5
        w.consumed = 0
        XCTAssertEqual(policy.seekReset(atHost: 104.5), .ok)
        // Still frozen at the pre-seek value - no jump, no cleared freeze.
        XCTAssertEqual(clock.nowSeconds(), 104.0, accuracy: 1e-9)
        // Resume MUST NOT refuse: new generation anchored at consumed=0,
        // offset re-based at the frozen value.
        w.host = 105.0
        XCTAssertTrue(policy.resume(consumedFrames: 0, atHost: 105.0))
        XCTAssertEqual(clock.nowSeconds(), 104.0, accuracy: 1e-9)
        w.advance(1.0)
        XCTAssertEqual(clock.nowSeconds(), 105.0, accuracy: 1e-9)
        let c = policy.counters
        XCTAssertEqual(c.pauseTransitions, 1)
        XCTAssertEqual(c.seekGenerationResets, 1)
        XCTAssertEqual(c.resumeTransitions, 1)
        XCTAssertEqual(c.anchorRefusals, 0)
        // Both older generations are fenced.
        XCTAssertEqual(policy.clock.anchor(generation: 1, consumedSamples: 0,
                                           sampleRate: 48000, hostTime: 106.0,
                                           consistencyTolerance: 0.002), .staleGeneration)
        XCTAssertEqual(policy.clock.anchor(generation: 2, consumedSamples: 0,
                                           sampleRate: 48000, hostTime: 106.0,
                                           consistencyTolerance: 0.002), .staleGeneration)
        XCTAssertFalse(clock.masterLost)
    }

    /// Concurrency witness (architect 20:09 race verdict): the pump
    /// thread hammers nowSeconds()/counters/hasMaster while the session
    /// owner mutates (pause/resume/seekReset/periodicAnchor/stop) from
    /// another thread. Run under TSan (`swift test --sanitize=thread`):
    /// the policy's internal serialization must make this clean, and the
    /// receipts reconcile exactly at the end.
    func test11_concurrentReadsDuringSessionMutations() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(1.0)

        let stopFlag = AtomicU64(0)!
        let doneFlag = AtomicU64(0)!
        let startedFlag = AtomicU64(0)!
        let reader = Thread {
            startedFlag.store(1)
            while stopFlag.load() == 0 {
                _ = clock.nowSeconds()
                _ = clock.hasMaster
                _ = policy.counters
                _ = policy.driftPPM()
            }
            doneFlag.store(1)
        }
        reader.start()
        // Overlap is REQUIRED for the witness: wait until the reader is
        // inside its hammer loop before mutating.
        while startedFlag.load() == 0 { Thread.sleep(forTimeInterval: 0.0001) }

        // Host/consumed are NOT mutated during the hammer (read-only
        // shared inputs); all policy state mutation is serialized inside
        // the policy. Exact receipt expectations are deterministic.
        // Every successful resume/seek/periodic call lands exactly one
        // accepted anchor; a periodic sample right after a seek (before
        // the next resume re-anchor) is a typed refusal (static host vs
        // reset position). Count both from the actual return values.
        var expectedPauses = 0, expectedResumes = 0, expectedSeeks = 0
        var expectedAnchors = 1, expectedRefusals = 0   // 1 = sessionStart
        for i in 0..<1000 {
            if policy.pause(atHost: w.hostNow()) {
                expectedPauses += 1
                if policy.resume(consumedFrames: UInt64(w.consumed), atHost: w.hostNow()) {
                    expectedResumes += 1
                    expectedAnchors += 1
                }
            }
            if i % 10 == 9 {
                if policy.seekReset(atHost: w.hostNow()) == .ok {
                    expectedSeeks += 1
                    expectedAnchors += 1
                }
            }
            if i % 7 == 6 {
                let st = policy.periodicAnchor(consumedFrames: UInt64(w.consumed),
                                               atHost: w.hostNow())
                if st == .ok { expectedAnchors += 1 }
                else if st != .noMaster { expectedRefusals += 1 }
            }
        }
        stopFlag.store(1)
        while doneFlag.load() == 0 { Thread.sleep(forTimeInterval: 0.001) }
        let c = policy.counters
        XCTAssertEqual(c.pauseTransitions, expectedPauses)
        XCTAssertEqual(c.resumeTransitions, expectedResumes)
        XCTAssertEqual(c.seekGenerationResets, expectedSeeks)
        XCTAssertEqual(c.anchorsAccepted, expectedAnchors)
        XCTAssertEqual(c.anchorRefusals, expectedRefusals)
        XCTAssertEqual(c.pauseTransitions, c.resumeTransitions)
        policy.sessionStop()
        XCTAssertTrue(clock.nowSeconds().isNaN)
        XCTAssertTrue(clock.masterLost)
    }

    /// Admission-core contention (20:17 blocker fix): the SAME
    /// AudioAdmissionState decision code the Mac AudioUnitSink's real
    /// stateLock critical section calls, driven under its admissionLock
    /// by concurrent pause flips + fence advances + admission decisions.
    /// Every decision recorded INSIDE the lock must match the decision
    /// table exactly; TSan must be clean. (The sink's Mac-gated compile
    /// stays Mac-deferred; this is the shared critical-section logic,
    /// not an independent toy model.)
    func test12_admissionCoreContention() {
        let state = AudioAdmissionState()
        let violations = AtomicU64(0)!
        var fence: UInt64 = 1
        let stopFlag = AtomicU64(0)!
        let doneFlag = AtomicU64(0)!
        let startedFlag = AtomicU64(0)!
        let reader = Thread {
            startedFlag.store(1)
            while stopFlag.load() == 0 {
                state.admissionLock.lock()
                let decision = state.refusal(fenceActive: fence, expectedGeneration: fence)
                if state.isPaused {
                    if decision != .paused { violations.fetchAdd(1) }
                } else if decision != nil { violations.fetchAdd(1) }
                // A stale expectation must ALWAYS refuse, paused or not.
                if state.refusal(fenceActive: fence, expectedGeneration: fence &+ 1) != .staleGeneration {
                    violations.fetchAdd(1)
                }
                state.admissionLock.unlock()
            }
            doneFlag.store(1)
        }
        reader.start()
        while startedFlag.load() == 0 { Thread.sleep(forTimeInterval: 0.0001) }
        for _ in 0..<1000 {
            state.admissionLock.lock()
            state.pausedCell?.store(1)
            state.pausedCell?.store(0)
            fence &+= 1
            state.admissionLock.unlock()
        }
        stopFlag.store(1)
        while doneFlag.load() == 0 { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertEqual(violations.load(), 0)
    }

    /// Lifecycle race (20:40): a pause orphaned by teardown must NOT
    /// freeze the next session - sessionStart clears the stale quiesce
    /// and the value advances from the NEW anchor. (The sink clears its
    /// RT cells at the same boundary; that half is Mac-gated, parse-only.)
    func test13_sessionStartClearsOrphanedPause() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(1.0)
        XCTAssertTrue(policy.pause(atHost: 101.0))
        XCTAssertEqual(clock.nowSeconds(), 101.0, accuracy: 1e-9)   // frozen
        policy.sessionStop()                                        // teardown, NO resume
        // New session on the same policy object (the sink reuses it),
        // later in wall time:
        w.host = 200.0
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 200.0), .ok)
        XCTAssertFalse(policy.paused)
        XCTAssertEqual(clock.nowSeconds(), 200.0, accuracy: 1e-9)
        w.advance(0.5)
        XCTAssertEqual(clock.nowSeconds(), 200.5, accuracy: 1e-9)   // NOT stuck at 101
        XCTAssertFalse(clock.masterLost)
        let c = policy.counters
        XCTAssertEqual(c.pauseTransitions, 1)
        XCTAssertEqual(c.resumeTransitions, 0)
        XCTAssertEqual(c.generation, 2)
    }

    /// Transition witnesses (20:22 architect review): pause is REFUSED
    /// without a live current-generation master - before the first
    /// anchor AND after sessionStop (the sink's publication/anchor gap
    /// maps onto this post-fence state) - and accepted only while
    /// anchored. The admitted-pause-then-cleared defect class cannot
    /// recur at policy level.
    func test14_pauseRequiresLiveMaster() {
        let w = FakeWorld()
        let policy = makePolicy(w)
        // Pre-anchor: typed refusal (wall fallback is stationary-correct).
        XCTAssertFalse(policy.pause(atHost: 100.0))
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(0.5)
        XCTAssertTrue(policy.pause(atHost: 100.5))
        XCTAssertTrue(policy.resume(consumedFrames: 24000, atHost: 101.0))
        policy.sessionStop()
        // Post-fence: typed refusal, never a silently-dropped success.
        XCTAssertFalse(policy.pause(atHost: 102.0))
        let c = policy.counters
        XCTAssertEqual(c.pauseTransitions, 1)
        XCTAssertEqual(c.resumeTransitions, 1)
        // The sink-side publication/anchor coherence guard is exercised
        // by the extracted barrier witness test15 (real SessionLifecycle
        // + real policy); the AudioUnit end-to-end run stays Mac-deferred.
    }

    /// Extracted transition witness WITH BARRIER (architect 20:25 +
    /// 20:30 refinement): the sink's EXACT start-tail / stop-fence
    /// discipline - shared stateLock, lifecycle.current checked inside
    /// it, beginStop itself NOT stateLock-serialized (as in the sink) -
    /// replayed on the REAL SessionLifecycle and the REAL
    /// AudioPacingPolicy. stopFirst proves the completed order (fence
    /// before the tail check -> no anchor). anchorFirst proves the
    /// CRITICAL OVERLAP: the anchor thread is PARKED INSIDE stateLock
    /// immediately after the active-generation check passes, the stop
    /// thread runs beginStop in that window and signals it did so
    /// BEFORE touching stateLock, THEN the anchor is released and
    /// applies - and stop's later fence (blocked on stateLock until the
    /// anchor completes) still wins. Terminal invariant in BOTH orders:
    /// the master is fenced (or never created), never resurrected;
    /// pre-anchor pause is refused, and after the fence pause stays
    /// refused (the positive mid-session pause case is test14's). This
    /// is an extraction of
    /// the lock discipline, not the AudioUnit path itself (Mac-gated);
    /// test14 is the policy-level witness, NOT sink interleaving proof.
    func test15_startAnchorVsStopFenceBarrier() {
        for stopFirst in [true, false] {
            let w = FakeWorld()
            let policy = makePolicy(w)
            let lifecycle = SessionLifecycle()
            let sinkLock = NSLock()   // stands in for the sink's stateLock
            guard let g = lifecycle.beginStart() else { return XCTFail("beginStart refused") }
            XCTAssertTrue(lifecycle.commitStart(g))

            // Pre-anchor: pause is refused (typed), both orders.
            XCTAssertFalse(policy.pause(atHost: 100.0), "stopFirst=\(stopFirst)")

            let startBarrier = DispatchSemaphore(value: 0)
            let anchorMayProceed = DispatchSemaphore(value: 0)
            let insideLock = DispatchSemaphore(value: 0)
            let beganStop = DispatchSemaphore(value: 0)
            let releaseAnchor = DispatchSemaphore(value: 0)
            let anchorApplied = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)

            // EXACT sink start-tail sequence (AudioUnitSink.start). In
            // the anchorFirst order the thread PARKS INSIDE stateLock
            // right after the active-generation check, so beginStop
            // lands in the genuine check->anchor window.
            let anchorThread = Thread {
                startBarrier.wait()
                if stopFirst { anchorMayProceed.wait() }
                sinkLock.lock()
                if case .active(let gg) = lifecycle.current, gg == g {
                    if !stopFirst {
                        insideLock.signal()
                        releaseAnchor.wait()   // parked INSIDE stateLock
                    }
                    _ = policy.sessionStart(consumedFrames: 0, atHost: 100.0)
                }
                if !stopFirst { anchorApplied.signal() }
                sinkLock.unlock()
                done.signal()
            }
            // EXACT sink stop sequence: beginStop OUTSIDE the lock, the
            // master fence INSIDE it. In the anchorFirst order beginStop
            // runs while the anchor thread is parked after its check,
            // then the fence blocks on stateLock until the anchor
            // completes - and wins.
            let stopThread = Thread {
                startBarrier.wait()
                if !stopFirst {
                    insideLock.wait()
                    _ = lifecycle.beginStop()   // lands IN the overlap window
                    beganStop.signal()
                    sinkLock.lock()
                    policy.sessionStop()
                    sinkLock.unlock()
                } else {
                    _ = lifecycle.beginStop()
                    sinkLock.lock()
                    policy.sessionStop()
                    sinkLock.unlock()
                    anchorMayProceed.signal()
                }
                done.signal()
            }
            anchorThread.start(); stopThread.start()
            startBarrier.signal(); startBarrier.signal()
            if !stopFirst {
                XCTAssertEqual(beganStop.wait(timeout: .now() + 10), .success)
                // Overlap established: the anchor's check passed BEFORE
                // beginStop, beginStop has now landed, the anchor is not
                // yet applied. Release it; the fence then wins.
                releaseAnchor.signal()
                XCTAssertEqual(anchorApplied.wait(timeout: .now() + 10), .success)
                // NO mid-overlap policy assertions here (architect 20:32):
                // anchorApplied signals inside the lock; once the anchor
                // thread unlocks, the already-waiting stop thread can
                // fence BEFORE any main-thread policy call - and after
                // beginStop a policy-level pause is not a sink-admitted
                // pause anyway (the sink's lifecycle gate is closed).
                // The independent positive pause case stays in test14.
            }
            XCTAssertEqual(done.wait(timeout: .now() + 10), .success)
            XCTAssertEqual(done.wait(timeout: .now() + 10), .success)

            // Terminal invariant, both orders: master fenced/never
            // created, never resurrected.
            XCTAssertFalse(policy.hasMasterProven, "stopFirst=\(stopFirst)")
            XCTAssertNil(policy.wallEpochValue(atHost: 101.0), "stopFirst=\(stopFirst)")
            XCTAssertFalse(policy.pause(atHost: 101.0), "stopFirst=\(stopFirst)")
            XCTAssertFalse(policy.pause(atHost: 101.0), "stopFirst=\(stopFirst)")
            XCTAssertNil(policy.wallEpochValue(atHost: 102.0), "stopFirst=\(stopFirst)")
            let c = policy.counters
            // anchorFirst: exactly 1 anchor (sessionStart), fenced by
            // stop; no pause/resume ever happened in this witness.
            XCTAssertEqual(c.anchorsAccepted, stopFirst ? 0 : 1, "stopFirst=\(stopFirst)")
            XCTAssertEqual(c.pauseTransitions, 0, "stopFirst=\(stopFirst)")
            XCTAssertEqual(c.resumeTransitions, 0, "stopFirst=\(stopFirst)")
        }
    }

    /// Starvation honesty on the real pump: a stalled counter never
    /// substitutes the clock; an early frame waits (clamped) and the
    /// waits are driven purely by the sink's consumption.
    func test09_stalledCounterWaitsNotSubstitutes() async throws {
        let w = FakeWorld()
        let policy = makePolicy(w)
        let clock = AudioMasterPacingClock(policy: policy, hostClock: { w.hostNow() })
        XCTAssertEqual(policy.sessionStart(consumedFrames: 0, atHost: 100.0), .ok)
        w.advance(1.0)
        var waits: [Double] = []
        let source = ScriptedSource([
            .frame(SourceFrame(ptsSeconds: 1.0, durationSeconds: 0.04, digest: "anchor")),
            .frame(SourceFrame(ptsSeconds: 3.5, durationSeconds: 0.04, digest: "far-early")),
            .ended(.endOfStream),
        ])
        let display = RecordingSink()
        let pump = FramePump(source: source, sink: display, clock: clock,
                             decider: AVSyncDecider(maxWaitSeconds: 1.0, master: .clock),
                             onWait: { seconds in
            waits.append(seconds)
            w.advance(seconds)
            return true
        })
        let stats = await pump.run()
        XCTAssertEqual(stats.endReason, .endOfStream)
        XCTAssertEqual(stats.digestsShown, ["anchor", "far-early"])
        // 2.5 s early, clamped: 1.0 + 1.0 + 0.5, re-decided off the audio
        // master after each completed wait.
        XCTAssertEqual(waits, [1.0, 1.0, 0.5])
        XCTAssertFalse(clock.masterLost)
    }
}
