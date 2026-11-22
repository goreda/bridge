// GorAVAudioClockTests - XCTest mirror of the C suite
// GorAVAudioClock/tests/test_audio_clock.c (r2, groups 1-10 incl. 8b),
// driven THROUGH the GorAVAudioClockSwift binding. Each test method names
// the C group it mirrors; expectations are the same values as the C suite.
//
// Scope: Linux SwiftPM compile+run is COMP-SCOPE evidence only (Swift
// 6.1.2 Linux), NOT Mac qualification.

import XCTest
@testable import GorAVAudioClockSwift

private final class FakeClock {
    var now: Double
    init(_ now: Double) { self.now = now }
}

final class GorAVAudioClockTests: XCTestCase {

    private func makeClock(_ now: Double = 100.0) -> (AudioClock, FakeClock) {
        let fake = FakeClock(now)
        let clock = AudioClock(hostClock: { fake.now })
        return (clock!, fake)
    }

    // C group 1: no master: every query refuses, no system-clock substitution
    func test01_noMasterRefusesAllQueries() {
        let (c, _) = makeClock()
        XCTAssertEqual(c.mediaTime(atHost: 100.0).status, .noMaster)
        XCTAssertNil(c.mediaTime(atHost: 100.0).mediaTime)
        XCTAssertEqual(c.expectedSamples(atHost: 100.0).status, .noMaster)
        let r = c.classifyFrame(pts: 5.0, nowHost: 100.0, latency: 0.02,
                                earlyWindow: 0.005, lateThreshold: 0.040)
        XCTAssertEqual(r.status, .noMaster)
        XCTAssertNil(r.decision)
    }

    // C group 2: anchor + exact media/host mapping
    func test02_anchorAndExactMapping() {
        let (c, _) = makeClock()
        // 1.0 s of audio at t=100
        XCTAssertEqual(c.anchor(generation: 1, consumedSamples: 48000, sampleRate: 48000,
                                hostTime: 100.0, consistencyTolerance: 0.002), .ok)
        XCTAssertTrue(c.hasMaster)
        let mt = c.mediaTime(atHost: 101.0)
        XCTAssertEqual(mt.status, .ok)
        XCTAssertEqual(mt.mediaTime!, 2.0, accuracy: 1e-9)
        let es = c.expectedSamples(atHost: 101.5)
        XCTAssertEqual(es.status, .ok)
        XCTAssertEqual(es.samples, 120000)
    }

    // C group 3: stale generation rejected
    func test03_staleGenerationRejected() {
        let (c, _) = makeClock()
        XCTAssertEqual(c.anchor(generation: 1, consumedSamples: 48000, sampleRate: 48000,
                                hostTime: 100.0, consistencyTolerance: 0.002), .ok)
        // same gen, earlier host time: no proof
        XCTAssertEqual(c.anchor(generation: 1, consumedSamples: 48000, sampleRate: 48000,
                                hostTime: 90.0, consistencyTolerance: 0.002), .inconsistent)
        c.fence(generation: 1)
        XCTAssertEqual(c.anchor(generation: 1, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 102.0, consistencyTolerance: 0.002), .staleGeneration)
        XCTAssertFalse(c.hasMaster)
        XCTAssertEqual(c.mediaTime(atHost: 102.0).status, .noMaster)
    }

    // C group 4: same-generation re-anchor: consistent accepted, inconsistent rejected
    func test04_sameGenerationReanchor() {
        let (c, _) = makeClock(200.0)
        XCTAssertEqual(c.anchor(generation: 2, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 200.0, consistencyTolerance: 0.002), .ok)
        // at t=201 prediction is 48000 samples; 48096 is +2ms: exactly at tol
        XCTAssertEqual(c.anchor(generation: 2, consumedSamples: 48096, sampleRate: 48000,
                                hostTime: 201.0, consistencyTolerance: 0.002), .ok)
        // +208ms off
        XCTAssertEqual(c.anchor(generation: 2, consumedSamples: 97000, sampleRate: 48000,
                                hostTime: 202.0, consistencyTolerance: 0.002), .inconsistent)
        // clock still anchored on the consistent value
        let mt = c.mediaTime(atHost: 202.0)
        XCTAssertEqual(mt.status, .ok)
        XCTAssertEqual(mt.mediaTime!, 2.002, accuracy: 1e-9)
    }

    // C group 5: same-generation rate change is a timeline reset; new gen ok
    func test05_rateChangeIsTimelineReset() {
        let (c, _) = makeClock(202.0)
        XCTAssertEqual(c.anchor(generation: 2, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 200.0, consistencyTolerance: 0.002), .ok)
        XCTAssertEqual(c.anchor(generation: 2, consumedSamples: 96000, sampleRate: 44100,
                                hostTime: 202.0, consistencyTolerance: 0.002), .rateChange)
        XCTAssertEqual(c.anchor(generation: 3, consumedSamples: 0, sampleRate: 44100,
                                hostTime: 202.0, consistencyTolerance: 0.002), .ok)
        XCTAssertEqual(c.currentGeneration, 3)
        let mt = c.mediaTime(atHost: 203.0)
        XCTAssertEqual(mt.status, .ok)
        XCTAssertEqual(mt.mediaTime!, 1.0, accuracy: 1e-9)
    }

    // C group 6: latency: unknown stays unknown; known shifts the deadline
    func test06_latencyUnknownStaysUnknown() {
        let (c, _) = makeClock(202.0)
        XCTAssertEqual(c.anchor(generation: 3, consumedSamples: 0, sampleRate: 44100,
                                hostTime: 202.0, consistencyTolerance: 0.002), .ok)
        XCTAssertEqual(c.hostDeadline(pts: 5.0, latency: AudioClock.latencyUnknown).status,
                       .latencyUnknown)
        let hd = c.hostDeadline(pts: 5.0, latency: 0.050)
        XCTAssertEqual(hd.status, .ok)
        // media 0 @ host 202; pts 5 -> 207 - 0.05
        XCTAssertEqual(hd.hostDeadline!, 206.95, accuracy: 1e-9)
    }

    // C group 7: drift from two same-generation anchors; 1 anchor = insufficient (NOT lost master)
    func test07_driftMeasurement() {
        let (c, _) = makeClock(300.0)
        XCTAssertEqual(c.anchor(generation: 4, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 300.0, consistencyTolerance: 0.01), .ok)
        // +0.4% = +4000 ppm; prediction error 4ms <= 10ms tol
        XCTAssertEqual(c.anchor(generation: 4, consumedSamples: 48192, sampleRate: 48000,
                                hostTime: 301.0, consistencyTolerance: 0.010), .ok)
        let d = c.driftPPM()
        XCTAssertEqual(d.status, .ok)
        XCTAssertEqual(d.ppm!, 4000.0, accuracy: 1.0)
        // single anchor: insufficient anchors, master intact
        let (c2, _) = makeClock(300.0)
        XCTAssertEqual(c2.anchor(generation: 1, consumedSamples: 0, sampleRate: 48000,
                                 hostTime: 300.0, consistencyTolerance: 0.002), .ok)
        XCTAssertEqual(c2.driftPPM().status, .insufficientAnchors)
        XCTAssertTrue(c2.hasMaster)
    }

    // C group 8: classify: WAIT early, SHOW in window, DROP_LATE past threshold
    func test08_classify() {
        let (c, _) = makeClock(400.0)
        XCTAssertEqual(c.anchor(generation: 5, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 400.0, consistencyTolerance: 0.002), .ok)
        // media 0 @ host 400; pts 1.0, now 400: deadline 401 (no latency); early by 1s -> WAIT
        var r = c.classifyFrame(pts: 1.0, nowHost: 400.0, latency: 0.0,
                                earlyWindow: 0.005, lateThreshold: 0.040)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.decision, .wait)
        XCTAssertEqual(r.waitUntilHost!, 401.0, accuracy: 1e-9)
        // now 400.999: inside 5ms early window -> SHOW
        r = c.classifyFrame(pts: 1.0, nowHost: 400.999, latency: 0.0,
                            earlyWindow: 0.005, lateThreshold: 0.040)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.decision, .show)
        // now 401.100: media 1.1 > pts+0.040 -> DROP_LATE
        r = c.classifyFrame(pts: 1.0, nowHost: 401.100, latency: 0.0,
                            earlyWindow: 0.005, lateThreshold: 0.040)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.decision, .dropLate)
        // latency shifts the deadline later
        r = c.classifyFrame(pts: 1.0, nowHost: 400.950, latency: 0.100,
                            earlyWindow: 0.005, lateThreshold: 0.040)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.decision, .show)
        XCTAssertEqual(r.waitUntilHost!, 400.9, accuracy: 1e-9)
    }

    // C group 8b: classify rejects invalid policy thresholds
    func test08b_classifyRejectsInvalidThresholds() {
        let (c, _) = makeClock(400.0)
        XCTAssertEqual(c.anchor(generation: 5, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 400.0, consistencyTolerance: 0.002), .ok)
        XCTAssertEqual(c.classifyFrame(pts: 1.0, nowHost: 400.0, latency: 0.0,
                                       earlyWindow: -0.001, lateThreshold: 0.040).status,
                       .invalidArgument)
        XCTAssertEqual(c.classifyFrame(pts: 1.0, nowHost: 400.0, latency: 0.0,
                                       earlyWindow: 0.005, lateThreshold: -0.040).status,
                       .invalidArgument)
        XCTAssertEqual(c.classifyFrame(pts: 1.0, nowHost: 400.0, latency: 0.0,
                                       earlyWindow: .nan, lateThreshold: 0.040).status,
                       .invalidArgument)
    }

    // C group 9: invalid arguments
    func test09_invalidArguments() {
        let (c, _) = makeClock(500.0)
        XCTAssertEqual(c.anchor(generation: 6, consumedSamples: 0, sampleRate: 0,
                                hostTime: 500.0, consistencyTolerance: 0.002), .invalidArgument)
        XCTAssertEqual(c.anchor(generation: 6, consumedSamples: -5, sampleRate: 48000,
                                hostTime: 500.0, consistencyTolerance: 0.002), .invalidArgument)
        XCTAssertEqual(c.mediaTime(atHost: .nan).status, .invalidArgument)
    }

    // C group 10: fence current generation: master lost until re-anchor (8.5 K3 path)
    func test10_fenceLosesMasterUntilReanchor() {
        let (c, _) = makeClock(500.0)
        XCTAssertEqual(c.anchor(generation: 5, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 400.0, consistencyTolerance: 0.002), .ok)
        c.fence(generation: 5)
        XCTAssertEqual(c.mediaTime(atHost: 500.0).status, .noMaster)
        XCTAssertEqual(c.anchor(generation: 6, consumedSamples: 0, sampleRate: 48000,
                                hostTime: 500.0, consistencyTolerance: 0.002), .ok)
        XCTAssertEqual(c.mediaTime(atHost: 500.0).status, .ok)
    }
}
