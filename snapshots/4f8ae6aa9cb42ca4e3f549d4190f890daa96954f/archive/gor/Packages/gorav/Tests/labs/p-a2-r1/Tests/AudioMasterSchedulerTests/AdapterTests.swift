import Foundation
import XCTest
@testable import AudioMasterScheduler

final class AdapterTests: XCTestCase {
    func testIdenticalPTSUnseenOldFrameAndFreshFrame() {
        var adapter = EnqueueGenerationAdapter()
        adapter.reset(audioTime: 10, hostTime: 0)
        let old = adapter.enqueue(videoPTS: 10)
        // No decision on old before seek. Waiting-PTS filtering cannot help.
        adapter.seek(to: 10, hostTime: 1)
        let fresh = adapter.enqueue(videoPTS: 10)
        XCTAssertEqual(old.pts, fresh.pts)
        XCTAssertNotEqual(old.generation, fresh.generation)
        XCTAssertEqual(adapter.decide(frame: old, hostTime: 1), .drop)
        XCTAssertEqual(adapter.decide(frame: fresh, hostTime: 1), .present)
        // Repeated calls never silently retag an old value.
        XCTAssertEqual(adapter.decide(frame: old, hostTime: 1), .drop)
    }
    func testWaitingFrameIsNotRetaggedAtDecisionTime() {
        var adapter = EnqueueGenerationAdapter()
        adapter.reset(audioTime: 0, hostTime: 0)
        let pending = adapter.enqueue(videoPTS: 1)
        XCTAssertEqual(adapter.decide(frame: pending, hostTime: 0), .wait)
        adapter.seek(to: 1, hostTime: 3)
        let fresh = adapter.enqueue(videoPTS: 1)
        XCTAssertEqual(adapter.decide(frame: pending, hostTime: 3), .drop)
        XCTAssertEqual(adapter.decide(frame: fresh, hostTime: 3), .present)
    }
    func testResetAlsoInvalidatesQueuedFrame() {
        var adapter = EnqueueGenerationAdapter()
        adapter.reset(audioTime: 2, hostTime: 0)
        let old = adapter.enqueue(videoPTS: 2)
        adapter.reset(audioTime: 2, hostTime: 1)
        XCTAssertEqual(adapter.decide(frame: old, hostTime: 1), .drop)
        XCTAssertEqual(adapter.decide(frame: adapter.enqueue(videoPTS: 2), hostTime: 1), .present)
    }
    func testProtocolRemainsUsableButCannotIdentifyOldFrames() {
        var scheduler: any AudioMasterScheduler = EnqueueGenerationAdapter()
        scheduler.reset(audioTime: 10, hostTime: 0)
        scheduler.seek(to: 10, hostTime: 1)
        XCTAssertEqual(scheduler.decide(videoPTS: 10, hostTime: 1), .present)
        XCTAssertEqual(scheduler.mediaTime(at: 1), 10)
    }
    func testFiveSeeksEnqueueAdapter600Seconds() throws {
        struct Seek: Decodable { let hostTick: Int; let mediaSeconds: Double; let pendingLeadSeconds: Double }
        struct Fixture: Decodable {
            let durationTicks: Int; let tickSeconds: Double
            let audioEveryTicks: Int; let videoEveryTicks: Int
            let jitterTicks: [Int]; let seeks: [Seek]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "clock-five-seeks", withExtension: "json", subdirectory: "Fixtures"))
        let input = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let byTick = Dictionary(uniqueKeysWithValues: input.seeks.map { ($0.hostTick, $0) })
        var adapter = EnqueueGenerationAdapter()
        adapter.reset(audioTime: 0, hostTime: 0)
        var originTick = 0, originMedia = 0.0, frameIndex = 0, segment = 0
        var next = adapter.enqueue(videoPTS: 0)
        var oldFrames: [EnqueuedVideoFrame] = []
        var samples: [[String: Any]] = [], seekSamples: [[String: Any]] = []
        var offsets: [[Double]] = [[]], staleChecks = 0, waits = 0, drops = 0
        for tick in 0...input.durationTicks {
            let host = Double(tick) * input.tickSeconds
            if let seek = byTick[tick] {
                let before = adapter.mediaTime(at: host-input.tickSeconds)
                let pending = adapter.enqueue(videoPTS: adapter.mediaTime(at: host)+seek.pendingLeadSeconds)
                XCTAssertEqual(adapter.decide(frame: pending, hostTime: host), .wait)
                let identicalOld = adapter.enqueue(videoPTS: seek.mediaSeconds)
                oldFrames.append(contentsOf: [next, pending, identicalOld])
                adapter.seek(to: seek.mediaSeconds, hostTime: host)
                XCTAssertEqual(adapter.mediaTime(at: host), seek.mediaSeconds, accuracy: 0.001)
                let fresh = adapter.enqueue(videoPTS: seek.mediaSeconds)
                XCTAssertEqual(identicalOld.pts, fresh.pts)
                XCTAssertNotEqual(identicalOld.generation, fresh.generation)
                XCTAssertEqual(adapter.decide(frame: fresh, hostTime: host), .present)
                for old in oldFrames {
                    XCTAssertEqual(adapter.decide(frame: old, hostTime: host), .drop)
                    // Force an otherwise-present timing point, proving generation rejection.
                    XCTAssertEqual(adapter.decide(frame: old, hostTime: host+old.pts-seek.mediaSeconds), .drop)
                    staleChecks += 2
                }
                seekSamples.append(["tick": tick, "before": before,
                    "after": adapter.mediaTime(at: host), "next": adapter.mediaTime(at: host+input.tickSeconds),
                    "target": seek.mediaSeconds, "pendingPTS": pending.pts,
                    "oldGeneration": identicalOld.generation, "freshGeneration": fresh.generation])
                originTick = tick; originMedia = seek.mediaSeconds; frameIndex = 0
                segment += 1; offsets.append([]); next = fresh
            } else if tick % input.audioEveryTicks == 0 {
                let jitter = input.jitterTicks[(tick/input.audioEveryTicks) % input.jitterTicks.count]
                adapter.updateAudio(mediaTime: originMedia+Double(tick-originTick+jitter)*input.tickSeconds, hostTime: host)
            }
            while true {
                let decision = adapter.decide(frame: next, hostTime: host)
                if decision == .wait { waits += 1; break }
                if decision == .drop { drops += 1 } else {
                    let master = adapter.mediaTime(at: host), offset = next.pts-master
                    XCTAssertLessThanOrEqual(abs(offset), 0.040+1e-9)
                    let anchorTick = max(originTick, tick-tick%input.audioEveryTicks)
                    let jitter = anchorTick == originTick && originTick != 0 ? 0 : input.jitterTicks[(anchorTick/input.audioEveryTicks)%input.jitterTicks.count]
                    XCTAssertEqual(master, originMedia+Double(tick-originTick+jitter)*input.tickSeconds, accuracy: 1e-10)
                    offsets[segment].append(offset)
                    samples.append(["tick": tick, "segment": segment, "pts": next.pts,
                                    "master": master, "offset": offset, "generation": next.generation])
                }
                frameIndex += 1
                next = adapter.enqueue(videoPTS: originMedia+Double(frameIndex*input.videoEveryTicks)*input.tickSeconds)
            }
        }
        XCTAssertEqual(seekSamples.count, 5)
        XCTAssertEqual(staleChecks, 90)
        XCTAssertEqual(drops, 0)
        XCTAssertEqual(samples.count, 15000)
        let drifts = offsets.map { abs($0.last!-$0.first!) }
        let maxOffset = offsets.flatMap { $0 }.map { abs($0) }.max()!
        for drift in drifts { XCTAssertLessThanOrEqual(drift, 0.040+1e-9) }
        let evidence: [String: Any] = ["ticks": input.durationTicks+1, "presentations": samples.count,
            "drops": drops, "waits": waits, "staleChecks": staleChecks,
            "maxAbsOffset": maxOffset, "segmentDrifts": drifts, "seeks": seekSamples, "samples": samples]
        print("ADAPTER MEASURED ticks=\(input.durationTicks+1) presentations=\(samples.count) staleChecks=\(staleChecks) maxAbsOffset=\(maxOffset) segmentDrifts=\(drifts)")
        if let dir = ProcessInfo.processInfo.environment["R1_EVIDENCE_DIR"] {
            try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]).write(to:
                URL(fileURLWithPath: dir).appendingPathComponent("adapter-five-seeks.evidence.json"))
        }
    }
}
