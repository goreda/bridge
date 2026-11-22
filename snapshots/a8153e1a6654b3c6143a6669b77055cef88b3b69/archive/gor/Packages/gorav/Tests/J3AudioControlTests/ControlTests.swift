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

private final class PauseSource: FrameSource, @unchecked Sendable {
    var index = 0
    var pump: FramePump?
    let world: FakeWorld
    let policy: AudioPacingPolicy
    init(_ world: FakeWorld, _ policy: AudioPacingPolicy) { self.world = world; self.policy = policy }
    func nextEvent() async -> SourceEvent {
        index += 1
        if index == 1 { return .frame(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "before")) }
        if index == 2 {
            XCTAssertTrue(policy.pause(atHost: world.host))
            await pump?.pause()
            let frozen = policy.wallEpochValue(atHost: world.host)
            world.host += 10 // device counter deliberately HELD
            XCTAssertEqual(policy.wallEpochValue(atHost: world.host), frozen)
            XCTAssertEqual(policy.seekReset(atHost: world.host), .ok)
            XCTAssertEqual(policy.wallEpochValue(atHost: world.host), frozen)
            world.consumed = 0 // seek resets ring counter while preserving paused epoch
            XCTAssertTrue(policy.resume(consumedFrames: UInt64(world.consumed), atHost: world.host))
            await pump?.resume()
            return .frame(SourceFrame(ptsSeconds: 0.04, durationSeconds: 0.04, digest: "after"))
        }
        return .ended(.endOfStream)
    }
}

final class J3AudioControlTests: XCTestCase {
    func testActualFrozenMasterResumeNoDoubleCount() async {
        let w = FakeWorld(), display = RecordingSink()
        let p = makePolicy(w)
        XCTAssertEqual(p.sessionStart(consumedFrames: 0, atHost: w.host), .ok)
        let clock = AudioMasterPacingClock(policy: p, hostClock: { w.host })
        let source = PauseSource(w, p)
        let pump = FramePump(source: source, sink: display, clock: clock, onWait: { seconds in w.advance(seconds); return true })
        source.pump = pump
        let stats = await pump.run()
        XCTAssertEqual(stats.shown, 2)
        XCTAssertEqual(stats.dropped, 0)
        XCTAssertEqual(stats.pauses, 1)
        XCTAssertEqual(p.counters.pauseTransitions, 1)
        XCTAssertEqual(p.counters.resumeTransitions, 1)
        XCTAssertEqual(stats.endReason, .endOfStream)
    }
    func testActualFrozenSeekWhilePausedValue() async {
        let w = FakeWorld()
        let p = makePolicy(w)
        XCTAssertEqual(p.sessionStart(consumedFrames: 0, atHost: 100), .ok)
        XCTAssertTrue(p.pause(atHost: 101))
        let frozen = p.wallEpochValue(atHost: 101)
        XCTAssertEqual(p.seekReset(atHost: 105), .ok)
        XCTAssertEqual(p.wallEpochValue(atHost: 110), frozen)
        XCTAssertTrue(p.resume(consumedFrames: 0, atHost: 110))
        XCTAssertEqual(p.counters.pauseTransitions, 1)
        XCTAssertEqual(p.counters.resumeTransitions, 1)
        XCTAssertEqual(p.counters.seekGenerationResets, 1)
    }

    func testActualMasterLossFailsClosed() async {
        let w = FakeWorld(), display = RecordingSink()
        let p = makePolicy(w)
        XCTAssertEqual(p.sessionStart(consumedFrames: 0, atHost: w.host), .ok)
        let clock = AudioMasterPacingClock(policy: p, hostClock: { w.host })
        p.sessionStop()
        let source = ScriptedSource([.frame(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "never")), .ended(.endOfStream)])
        let pump = FramePump(source: source, sink: display, clock: clock, onWait: { _ in true })
        let stats = await pump.run()
        XCTAssertEqual(stats.shown, 0)
        XCTAssertEqual(stats.endReason, .failed(-93))
        XCTAssertTrue(clock.masterLost)
    }
}
