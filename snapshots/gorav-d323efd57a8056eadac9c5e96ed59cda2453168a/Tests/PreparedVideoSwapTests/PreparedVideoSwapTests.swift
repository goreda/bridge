import XCTest
@testable import GorAVPlaybackCore

private struct Clock: PlaybackClock { func nowSeconds() -> Double { 12 } }
private actor Feed: FrameSource {
    let digest: String
    var sent = false
    init(_ digest: String) { self.digest = digest }
    func nextEvent() async -> SourceEvent {
        guard !sent else { return .ended(.endOfStream) }
        sent = true
        return .frame(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: digest))
    }
}
private actor Sink: FrameSink {
    var digests: [String] = []
    func show(_ frame: SourceFrame) async -> Bool { digests.append(frame.digest); return true }
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool { await show(frame) }
}
final class PreparedVideoSwapTests: XCTestCase {
    func testSwapActuallyPullsReplacementAndKeepsClockAnchor() async {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 42)
        let pump = FramePump(source: Feed("old"), sink: sink, clock: Clock(), commit: cell) { _ in true }
        _ = await pump.run()
        let before = await pump.currentPaceAnchor
        let accepted = await pump.replaceVideoSource(Feed("new"))
        XCTAssertTrue(accepted)
        let after = await pump.currentPaceAnchor
        XCTAssertEqual(after, before)
        XCTAssertEqual(cell.revision, 1)
        _ = await pump.run()
        let shown = await sink.digests
        XCTAssertEqual(shown, ["old", "new"])
    }
    func testCancelledSwapDoesNotPublishOrReplace() async {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 43)
        let pump = FramePump(source: Feed("old"), sink: sink, clock: Clock(), commit: cell) { _ in true }
        cell.requestCancel()
        let accepted = await pump.replaceVideoSource(Feed("new"))
        XCTAssertFalse(accepted)
        XCTAssertEqual(cell.revision, 0)
    }
}

private final class ManualClock: PlaybackClock, @unchecked Sendable {
    private let lock = NSLock()
    private var time = 0.0
    func nowSeconds() -> Double { lock.lock(); defer { lock.unlock() }; return time }
    func set(_ t: Double) { lock.lock(); time = t; lock.unlock() }
}
private actor HeldFeed: FrameSource {
    private var count = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isHeld: Bool { continuation != nil }
    func release() { released = true; continuation?.resume(); continuation = nil }
    func nextEvent() async -> SourceEvent {
        count += 1
        if count == 1 { return .frame(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "old0")) }
        if count == 2 {
            if !released { await withCheckedContinuation { continuation = $0 } }
            return .frame(SourceFrame(ptsSeconds: 10, durationSeconds: 0.04, digest: "staleOld10"))
        }
        return .ended(.endOfStream)
    }
}
private actor Frames: FrameSource {
    var frames: [SourceFrame]
    init(_ pts: [Double], digest: String = "new") {
        frames = pts.map { SourceFrame(ptsSeconds: $0, durationSeconds: 0.04, digest: digest) }
    }
    func nextEvent() async -> SourceEvent {
        frames.isEmpty ? .ended(.endOfStream) : .frame(frames.removeFirst())
    }
}
extension PreparedVideoSwapTests {
    func testRefusedValidationIsAtomic() async {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 44)
        let pump = FramePump(source: Feed("old"), sink: sink, clock: Clock(), commit: cell) { _ in true }
        let accepted = await pump.replaceVideoSource(Feed("new"), validating: { false })
        XCTAssertFalse(accepted)
        XCTAssertEqual(cell.revision, 0)
        _ = await pump.run()
        let shown = await sink.digests
        XCTAssertEqual(shown, ["old"])
    }
    func testRevisionExhaustionIsAtomic() async {
        let sink = Sink(), cell = CancelCommit(testSeedAdmissions: 0, revision: 0x7fffffff, sessionEpoch: 44)
        let pump = FramePump(source: Feed("old"), sink: sink, clock: Clock(), commit: cell) { _ in true }
        let accepted = await pump.replaceVideoSource(Feed("new"))
        XCTAssertFalse(accepted)
        _ = await pump.run()
        let shown = await sink.digests
        XCTAssertEqual(shown, ["old"])
    }
    func testOldInFlightPullIsFencedAndAnchorPreserved() async throws {
        let source = HeldFeed(), sink = Sink(), clock = ManualClock()
        let cell = CancelCommit(sessionEpoch: 45)
        let pump = FramePump(source: source, sink: sink, clock: clock, commit: cell) { _ in true }
        let run = Task { await pump.run() }
        for _ in 0..<1000 { if await source.isHeld { break }; try await Task.sleep(nanoseconds: 100_000) }
        let before = await pump.currentPaceAnchor
        let accepted = await pump.replaceVideoSource(Frames([0]))
        XCTAssertTrue(accepted)
        await source.release()
        let stats = await run.value
        XCTAssertGreaterThanOrEqual(stats.seekStalePulls, 1)
        let after = await pump.currentPaceAnchor
        XCTAssertEqual(after, before)
        let shown = await sink.digests
        XCTAssertEqual(shown, ["old0", "new"])
    }
    func testScheduledBoundaryUsesExistingClockAndRejectsOverlap() async throws {
        let source = HeldFeed(), sink = Sink(), clock = ManualClock()
        let cell = CancelCommit(sessionEpoch: 46)
        let pump = FramePump(source: source, sink: sink, clock: clock, commit: cell) { _ in true }
        let run = Task { await pump.run() }
        for _ in 0..<1000 { if await source.isHeld { break }; try await Task.sleep(nanoseconds: 100_000) }
        let replacement = Task { await pump.replaceVideoSource(Frames([10]), atFilmTime: 10) }
        try await Task.sleep(nanoseconds: 5_000_000)
        let overlap = await pump.replaceVideoSource(Feed("overlap"))
        XCTAssertFalse(overlap)
        clock.set(9)
        await source.release()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(cell.revision, 0)
        let notYet = await sink.digests
        XCTAssertEqual(notYet, ["old0"])
        clock.set(10)
        let accepted = await replacement.value
        XCTAssertTrue(accepted)
        let stats = await run.value
        XCTAssertEqual(stats.shown, 2)
        let shown = await sink.digests
        XCTAssertEqual(shown, ["old0", "new"])
        let anchor = await pump.currentPaceAnchor
        XCTAssertEqual(anchor, MediaWallAnchor(mediaSeconds: 0, wallSeconds: 0))
    }
    func testScheduledTaskCancellationHasNoSourceMutation() async throws {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 47), clock = ManualClock()
        let pump = FramePump(source: Feed("old"), sink: sink, clock: clock, commit: cell) { _ in true }
        _ = await pump.run()
        let replacement = Task { await pump.replaceVideoSource(Feed("new"), atFilmTime: 100) }
        try await Task.sleep(nanoseconds: 2_000_000)
        replacement.cancel()
        let accepted = await replacement.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(cell.revision, 0)
        XCTAssertFalse(cell.isCancelled)
    }
    func testScheduledSwapWithoutFilmAnchorRefuses() async {
        let cell = CancelCommit(sessionEpoch: 48)
        let pump = FramePump(source: Feed("old"), sink: Sink(), clock: Clock(), commit: cell) { _ in true }
        let accepted = await pump.replaceVideoSource(Feed("new"), atFilmTime: 10)
        XCTAssertFalse(accepted)
        XCTAssertEqual(cell.revision, 0)
    }
    func testMappedSourcePreservesSpacingAndBufferedFirstFrame() async {
        let source = Frames([6.04])
        let first = SourceFrame(ptsSeconds: 6, durationSeconds: 0.04, digest: "landing")
        let mapped = PreparedVideoFrameSource(source: source, first: first, sourceStart: 6, filmStart: 100)
        guard case .frame(let a) = await mapped.nextEvent(), case .frame(let b) = await mapped.nextEvent() else {
            return XCTFail("missing decoded frames")
        }
        XCTAssertEqual(a.ptsSeconds, 100)
        XCTAssertEqual(b.ptsSeconds, 100.04, accuracy: 1e-9)
        XCTAssertEqual(a.digest, "landing")
        XCTAssertEqual(a.durationSeconds, first.durationSeconds)
        guard case .ended(.endOfStream) = await mapped.nextEvent() else { return XCTFail("terminal lost") }
    }
    func testMappedSourceRejectsNonfinitePTS() async {
        let first = SourceFrame(ptsSeconds: .nan, durationSeconds: 0.04, digest: "bad")
        let mapped = PreparedVideoFrameSource(source: Frames([]), first: first, sourceStart: 0, filmStart: 0)
        guard case .failed(-94) = await mapped.nextEvent() else { return XCTFail("invalid PTS admitted") }
    }
}
extension PreparedVideoSwapTests {
    func testLateTargetRefusesWithoutChangingSource() async {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 49), clock = ManualClock()
        let pump = FramePump(source: Feed("old"), sink: sink, clock: clock, commit: cell) { _ in true }
        _ = await pump.run()
        clock.set(10)
        let accepted = await pump.replaceVideoSource(Feed("new"), atFilmTime: 9)
        XCTAssertFalse(accepted)
        XCTAssertEqual(cell.revision, 0)
    }
    func testAudioBindingLossAtBoundaryDoesNotPublishCandidate() async throws {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 50), clock = ManualClock()
        let pump = FramePump(source: Feed("old"), sink: sink, clock: clock, commit: cell) { _ in true }
        _ = await pump.run()
        let swap = Task { await pump.replaceVideoSource(Feed("new"), atFilmTime: 10, validating: { false }) }
        try await Task.sleep(nanoseconds: 2_000_000)
        clock.set(10)
        let accepted = await swap.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(cell.revision, 0)
        XCTAssertFalse(cell.isCancelled)
    }
}

extension PreparedVideoSwapTests {
    func testUncommittedAdoptionReleaseAfterRefusalLeavesRealPumpUsable() async {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 60)
        let pump = FramePump(source: Feed("original"), sink: sink, clock: Clock(), commit: cell) { _ in true }
        var adoption = PreparedAdoption(); adoption.adopt()
        XCTAssertTrue(adoption.beginOperation())
        XCTAssertEqual(adoption.abortUncommitted(), .operationInFlight)
        let swapped = await pump.replaceVideoSource(Feed("candidate"), validating: { false })
        adoption.finishOperation(didCommit: swapped)
        XCTAssertFalse(swapped)
        XCTAssertEqual(adoption.abortUncommitted(), .released)
        XCTAssertFalse(cell.isCancelled)
        XCTAssertEqual(cell.revision, 0)
        _ = await pump.run()
        let shown = await sink.digests
        XCTAssertEqual(shown, ["original"])
    }
    func testLateFirstSwapAdoptionReleasePreservesAnchorAndSource() async {
        let sink = Sink(), cell = CancelCommit(sessionEpoch: 61), clock = ManualClock()
        let pump = FramePump(source: Feed("original"), sink: sink, clock: clock, commit: cell) { _ in true }
        _ = await pump.run()
        let prior = await pump.currentPaceAnchor
        var adoption = PreparedAdoption(); adoption.adopt(); _ = adoption.beginOperation()
        clock.set(10)
        let swapped = await pump.replaceVideoSource(Feed("late"), atFilmTime: 9)
        adoption.finishOperation(didCommit: swapped)
        XCTAssertEqual(adoption.abortUncommitted(), .released)
        let after = await pump.currentPaceAnchor
        XCTAssertEqual(after, prior)
        XCTAssertEqual(cell.revision, 0)
        XCTAssertFalse(cell.isCancelled)
    }
}
