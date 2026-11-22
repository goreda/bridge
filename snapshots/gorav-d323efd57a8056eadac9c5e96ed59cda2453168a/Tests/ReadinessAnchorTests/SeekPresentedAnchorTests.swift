import XCTest
import GorAVPlaybackCore

private struct FixedSeekClock: PlaybackClock {
    func nowSeconds() -> Double { 17 }
}
private actor SeekFrames: FrameSource {
    private var index = 0
    func nextEvent() async -> SourceEvent {
        guard index < 2 else { return .ended(.endOfStream) }
        defer { index += 1 }
        return .frame(SourceFrame(ptsSeconds: 8.0 + Double(index) * 0.04,
                                  durationSeconds: 0.04, digest: "seek-\(index)"))
    }
}
private actor SeekSink: FrameSink {
    let accepts: Bool
    private(set) var calls = 0
    init(accepts: Bool) { self.accepts = accepts }
    func show(_ frame: SourceFrame) async -> Bool { calls += 1; return accepts }
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        await show(frame)
    }
}

final class SeekPresentedAnchorTests: XCTestCase {
    func testRefusedShowsNeverPublishReadiness() async {
        let pump = FramePump(source: SeekFrames(), sink: SeekSink(accepts: false), clock: FixedSeekClock()) { _ in true }
        let reset = await pump.resetPresentation(seekLandingTarget: 8)
        XCTAssertTrue(reset)
        let stats = await pump.run()
        let anchor = await pump.currentPaceAnchor
        XCTAssertNil(anchor)
        XCTAssertEqual(stats.shown, 0)
        XCTAssertEqual(stats.fencedShows, 2)
        XCTAssertEqual(stats.waits, 0)
        XCTAssertEqual(stats.dropped, 0)
    }

    func testSeekWakesAlreadyParkedPauseForExactlyOneArrivalFrame() async {
        let sink = SeekSink(accepts: true)
        let pump = FramePump(source: SeekFrames(), sink: sink, clock: FixedSeekClock()) { _ in
            do { try await Task.sleep(nanoseconds: 1_000_000); return true } catch { return false }
        }
        await pump.pause()
        let task = Task { await pump.run() }
        try? await Task.sleep(nanoseconds: 20_000_000) // enter the existing pause park
        let reset = await pump.resetPresentation(seekLandingTarget: 8)
        XCTAssertTrue(reset)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            if await pump.currentPaceAnchor != nil { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let anchor = await pump.currentPaceAnchor
        let paused = await pump.isPaused
        XCTAssertEqual(anchor?.mediaSeconds, 8) // first actual frame at the landing target
        XCTAssertEqual(anchor?.wallSeconds, 17)
        XCTAssertTrue(paused)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let calls = await sink.calls
        XCTAssertEqual(calls, 1, "frame0+1 must remain parked")
        task.cancel()
        let stats = await task.value
        XCTAssertEqual(stats.shown, 1)
        XCTAssertEqual(stats.waits, 0)
        XCTAssertEqual(stats.dropped, 0)
    }
}
