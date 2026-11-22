import Foundation
import XCTest
@testable import AudioMasterScheduler

final class ClockTests: XCTestCase {
    struct Seek: Codable { let hostTick: Int; let mediaSeconds: Double; let pendingLeadSeconds: Double }
    struct Run: Codable {
        let durationTicks: Int; let tickSeconds: Double
        let audioEveryTicks: Int; let videoEveryTicks: Int
        let jitterTicks: [Int]; let seeks: [Seek]
    }
    struct Sample: Codable {
        let tick: Int; let segment: Int; let pts: Double; let master: Double; let offset: Double
    }
    struct SeekSample: Codable {
        let tick: Int; let before: Double; let after: Double; let next: Double
        let target: Double; let pendingPTS: Double; let oldGeneration: UInt64; let newGeneration: UInt64
    }
    struct Evidence: Codable {
        let fixture: String; let ticks: Int; let presentations: Int
        let drops: Int; let waits: Int; let maxAbsOffset: Double
        let segmentDrifts: [Double]; let seeks: [SeekSample]; let samples: [Sample]
    }
    func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    func simulate(_ name: String, tagged: Bool = false) throws {
        let run = try load(name, as: Run.self)
        XCTAssertEqual(run.durationTicks, 600000)
        XCTAssertEqual(run.tickSeconds, 0.001)
        XCTAssertEqual(run.audioEveryTicks, 10)
        XCTAssertEqual(run.videoEveryTicks, 40)
        XCTAssertEqual(run.jitterTicks, [-2,0,2,0])
        var clock = AudioMasterClock(); clock.reset(audioTime: 0, hostTime: 0)
        var originTick = 0, originMedia = 0.0, frame = 0, segment = 0
        var samples: [Sample] = [], seekSamples: [SeekSample] = []
        var waits = 0, drops = 0
        let seekMap = Dictionary(uniqueKeysWithValues: run.seeks.map { ($0.hostTick, $0) })
        for tick in 0...run.durationTicks {
            let host = Double(tick) * run.tickSeconds
            if let seek = seekMap[tick] {
                let before = clock.mediaTime(at: Double(tick-1) * run.tickSeconds)
                let pending = clock.mediaTime(at: host) + seek.pendingLeadSeconds
                let old = clock.generation
                XCTAssertEqual(clock.decide(videoPTS: pending, hostTime: host), .wait)
                clock.seek(to: seek.mediaSeconds, hostTime: host)
                let after = clock.mediaTime(at: host)
                XCTAssertEqual(after, seek.mediaSeconds, accuracy: 0.001)
                XCTAssertEqual(clock.decide(videoPTS: pending, hostTime: host), .drop)
                // Probe at exactly the old frame's PTS, where a mere timing filter would present.
                XCTAssertEqual(clock.decide(videoPTS: pending, hostTime: host + pending - after), .drop)
                XCTAssertEqual(clock.decide(videoPTS: pending, hostTime: host + pending - after, generation: old), .drop)
                seekSamples.append(SeekSample(tick: tick, before: before, after: after,
                    next: clock.mediaTime(at: host + run.tickSeconds), target: seek.mediaSeconds,
                    pendingPTS: pending, oldGeneration: old, newGeneration: clock.generation))
                originTick = tick; originMedia = seek.mediaSeconds; frame = 0; segment += 1
            } else if tick % run.audioEveryTicks == 0 {
                let jitter = run.jitterTicks[(tick / run.audioEveryTicks) % run.jitterTicks.count]
                let trueMedia = originMedia + Double(tick-originTick) * run.tickSeconds
                clock.updateAudio(mediaTime: trueMedia + Double(jitter) * run.tickSeconds, hostTime: host)
            }
            // Drain due frames in decode order; retain early frames until the next tick.
            while true {
                let pts = originMedia + Double(frame * run.videoEveryTicks) * run.tickSeconds
                let decision = tagged ? clock.decide(videoPTS: pts, hostTime: host, generation: clock.generation) : clock.decide(videoPTS: pts, hostTime: host)
                if decision == .wait { waits += 1; break }
                if decision == .drop { drops += 1 } else {
                    let master = clock.mediaTime(at: host), offset = pts-master
                    XCTAssertLessThanOrEqual(abs(offset), 0.040 + 1e-9)
                    // Independent clock oracle derived directly from input events.
                    let audioTick = max(originTick, tick - tick % run.audioEveryTicks)
                    let jitter = audioTick == originTick && originTick != 0 ? 0 : run.jitterTicks[(audioTick / run.audioEveryTicks) % run.jitterTicks.count]
                    let oracle = originMedia + Double(tick-originTick+jitter) * run.tickSeconds
                    XCTAssertEqual(master, oracle, accuracy: 1e-10)
                    samples.append(Sample(tick: tick, segment: segment, pts: pts, master: master, offset: offset))
                }
                frame += 1
            }
        }
        let drifts = (0...segment).map { index -> Double in
            let part = samples.filter { $0.segment == index }
            XCTAssertFalse(part.isEmpty)
            return abs(part.last!.offset - part.first!.offset)
        }
        for drift in drifts { XCTAssertLessThanOrEqual(drift, 0.040 + 1e-9) }
        XCTAssertEqual(seekSamples.count, run.seeks.count)
        XCTAssertGreaterThan(samples.count, 14000)
        let maxOffset = samples.map { abs($0.offset) }.max()!
        let evidenceName = name + (tagged ? "-tagged" : "")
        let evidence = Evidence(fixture: evidenceName, ticks: run.durationTicks+1, presentations: samples.count,
            drops: drops, waits: waits, maxAbsOffset: maxOffset, segmentDrifts: drifts,
            seeks: seekSamples, samples: samples)
        print("MEASURED \(evidenceName): presentations=\(samples.count) drops=\(drops) waits=\(waits) maxAbsOffset=\(maxOffset) segmentDrifts=\(drifts)")
        if let dir = ProcessInfo.processInfo.environment["EVIDENCE_DIR"] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(evidence).write(to: URL(fileURLWithPath: dir).appendingPathComponent(evidenceName+".evidence.json"))
        }
    }
    func test600Seconds() throws { try simulate("clock-600s-25fps") }
    func testFiveSeeks() throws { try simulate("clock-five-seeks") }
    func test600SecondsTagged() throws { try simulate("clock-600s-25fps", tagged: true) }
    func testFiveSeeksTagged() throws { try simulate("clock-five-seeks", tagged: true) }
    func testBoundary() throws {
        struct Boundary: Decodable {
            struct Case: Decodable { let pts: Double; let expected: String }
            let hostSeconds: Double; let audioSeconds: Double; let cases: [Case]
        }
        let fixture = try load("clock-boundary40ms", as: Boundary.self)
        var clock = AudioMasterClock(); clock.reset(audioTime: fixture.audioSeconds, hostTime: fixture.hostSeconds)
        for item in fixture.cases {
            let actual = clock.decide(videoPTS: item.pts, hostTime: fixture.hostSeconds)
            XCTAssertEqual(String(describing: actual), item.expected, "pts=\(item.pts)")
        }
    }
    func testEpochDisambiguatesIdenticalPTSAndUnseenStaleFrame() {
        var clock = AudioMasterClock(); clock.reset(audioTime: 10, hostTime: 0)
        let old = clock.generation
        clock.seek(to: 10, hostTime: 1)
        // This untagged call can mean either an unseen old frame or a new frame.
        XCTAssertEqual(clock.decide(videoPTS: 10, hostTime: 1), .present)
        XCTAssertEqual(clock.decide(videoPTS: 10, hostTime: 1, generation: old), .drop)
        XCTAssertEqual(clock.decide(videoPTS: 10, hostTime: 1, generation: clock.generation), .present)
    }
    func testKnownPendingPTSIsInvalidatedUntilReset() {
        var clock = AudioMasterClock(); clock.reset(audioTime: 0, hostTime: 0)
        XCTAssertEqual(clock.decide(videoPTS: 1, hostTime: 0), .wait)
        clock.seek(to: 1, hostTime: 10)
        XCTAssertEqual(clock.decide(videoPTS: 1, hostTime: 10), .drop)
        clock.reset(audioTime: 1, hostTime: 10)
        XCTAssertEqual(clock.decide(videoPTS: 1, hostTime: 10), .present)
    }
    func testExtrapolationAndInvalidInput() {
        var clock = AudioMasterClock(); clock.reset(audioTime: 12, hostTime: 5)
        XCTAssertEqual(clock.mediaTime(at: 5.5), 12.5)
        clock.updateAudio(mediaTime: 20, hostTime: 6)
        XCTAssertEqual(clock.mediaTime(at: 7), 21)
        XCTAssertEqual(clock.decide(videoPTS: .nan, hostTime: 7), .drop)
        XCTAssertEqual(clock.decide(videoPTS: 21, hostTime: .infinity), .drop)
        clock.seek(to: .nan, hostTime: 7)
        XCTAssertEqual(clock.mediaTime(at: 7), 21)
    }
}
