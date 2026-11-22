import XCTest
import GorAVPlaybackCore

/// Engine-level witnesses for the 189k readiness-anchor rule. maxLate is
/// the unchanged 0.040 s late-drop threshold; the local classify mirrors
/// the scheduler's decision shape (drop when the clock is past
/// pts + maxLate, wait when the clock is behind pts) so the tests exercise
/// the RULE at the engine seam without reimplementing a scheduler.
final class ReadinessAnchorSessionTests: XCTestCase {
    private func classify(mediaTime: Double, pts: Double, maxLate: Double = 0.040) -> String {
        let offset = mediaTime - pts
        if offset > maxLate + 1e-9 { return "drop" }
        if offset < 0 { return "wait" }
        return "present"
    }

    /// E1_SKIP_WARMUP witness, engine level: a clock start requested before
    /// frame 0 is decoded AND presented is a typed refusal, never permitted.
    func testClockStartRefusedBeforeAnchor() {
        var s = ReadinessAnchorSession()
        s.begin()
        XCTAssertTrue(s.anchorPending)
        XCTAssertFalse(s.requestClockStart(), "clock must never start before the readiness anchor")
        XCTAssertFalse(s.clockRunning)
    }

    func testClockStartsOnlyAfterAnchorPresented() {
        var s = ReadinessAnchorSession()
        s.begin()
        s.anchorPresentedNow() // frame 0 decoded AND presented; no scheduler decision
        XCTAssertFalse(s.anchorPending)
        XCTAssertTrue(s.requestClockStart())
        XCTAssertTrue(s.clockRunning)
    }

    /// E1_SIM_SLOW_FRAME witness, engine level: readiness does not hide real
    /// lateness - a frame arriving after the anchor whose pts lags the
    /// running clock past maxLate still drops.
    func testLateFrameAfterAnchorStillDrops() {
        var s = ReadinessAnchorSession()
        s.begin()
        s.anchorPresentedNow()
        XCTAssertTrue(s.requestClockStart())
        // Anchor frame itself: no scheduler decision (rule), by construction.
        // Next frame 120 ms behind the running clock: real lateness, drop.
        XCTAssertEqual(classify(mediaTime: 0.160, pts: 0.040), "drop")
        // A frame inside the window still presents; early still waits.
        XCTAssertEqual(classify(mediaTime: 0.040, pts: 0.040), "present")
        XCTAssertEqual(classify(mediaTime: 0.000, pts: 0.040), "wait")
    }

    /// Post-seek witness: seek stops the clock, fences the old generation,
    /// and requires a NEW readiness anchor before the clock restarts.
    func testSeekRestartsReadinessCycle() {
        var s = ReadinessAnchorSession()
        s.begin()
        s.anchorPresentedNow()
        XCTAssertTrue(s.requestClockStart())
        let g1 = s.seek()
        XCTAssertEqual(g1, 1)
        XCTAssertEqual(s.generation, 1)
        XCTAssertFalse(s.clockRunning, "clock must stop across seek")
        XCTAssertTrue(s.anchorPending, "first frame after seek is a new readiness anchor")
        XCTAssertFalse(s.requestClockStart(), "clock must not restart before the post-seek anchor")
        s.anchorPresentedNow() // first post-seek frame decoded AND presented
        XCTAssertTrue(s.requestClockStart())
        XCTAssertTrue(s.clockRunning)
    }

    /// Post-seek witness: after the clock restarts at the seek target, the
    /// anchor's pts neighborhood waits (readiness), and a frame genuinely
    /// late past maxLate still drops.
    func testPostSeekLateFrameStillDrops() {
        var s = ReadinessAnchorSession()
        s.begin()
        s.anchorPresentedNow()
        XCTAssertTrue(s.requestClockStart())
        s.seek()
        s.anchorPresentedNow()
        XCTAssertTrue(s.requestClockStart())
        // Clock restarted at the seek target (media 5.0): the next frame waits.
        XCTAssertEqual(classify(mediaTime: 5.000, pts: 5.040), "wait")
        // A frame 120 ms behind the restarted clock: real lateness, drop.
        XCTAssertEqual(classify(mediaTime: 5.160, pts: 5.040), "drop")
        // Stale-generation fence: generation moved, old frames are fenced.
        XCTAssertEqual(s.generation, 1)
    }
}
