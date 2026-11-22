import XCTest
@testable import gor

/// P24 (arch-195b): transition-table tests for the route state machine moved
/// out of vr180-look.lua. Each test names the pre-move Lua behavior it pins.
final class ThreeDRouteMachineTests: XCTestCase {

    private func context(enabled: Bool = true, layout: Int = 1, pack: Int = 2) -> ThreeDRouteContext {
        ThreeDRouteContext(enabled: enabled, layout: layout, pack: pack,
                           output: "sbs", engine: "flat2d3d", generation: "7",
                           file: "film.mp4", appPID: "4242")
    }

    private func receipt(layout: Int = 1, pack: Int = 2, enabled: Bool = true,
                         revision: UInt64? = 5, completed: UInt64? = 5) -> ThreeDAppliedRouteState {
        ThreeDAppliedRouteState(sourceLayout: layout, flatPack: pack, enabled: enabled,
                                revision: revision, completedRevision: completed)
    }

    // store-revision: sender ~= store-applier is ignored.
    func testOpenBatchForeignSenderIgnored() {
        var m = ThreeDRouteMachine()
        XCTAssertEqual(m.openBatch(revision: 5, kind: "flat-sbs", sender: "someone-else", context: context()), .ignoredForeign)
        XCTAssertNil(m.currentRevision)
    }

    // store-revision: n < store_revision is ignored (monotone mirror).
    func testOpenBatchStaleRevisionIgnored() {
        var m = ThreeDRouteMachine()
        XCTAssertEqual(m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context()), .opened)
        XCTAssertEqual(m.openBatch(revision: 4, kind: "flat-sbs", sender: "store-applier", context: context()), .ignoredStale)
        XCTAssertEqual(m.currentRevision, 5)
    }

    // store-revision: a new revision clears completed_revision.
    func testNewRevisionClearsCompletion() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        XCTAssertEqual(m.complete(receipt: receipt()), .pass)
        XCTAssertEqual(m.completedRevision, 5)
        XCTAssertEqual(m.openBatch(revision: 6, kind: "flat-sbs", sender: "store-applier", context: context()), .opened)
        XCTAssertNil(m.completedRevision)
    }

    // store-revision: the same revision refreshes kind/context and keeps completion.
    func testSameRevisionRefreshKeepsCompletion() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        _ = m.complete(receipt: receipt())
        XCTAssertEqual(m.openBatch(revision: 5, kind: "flat-tb", sender: "store-applier", context: context()), .refreshed)
        XCTAssertEqual(m.completedRevision, 5)
        XCTAssertEqual(m.storeKind, "flat-tb")
    }

    // gate: sender ~= store-applier rejects with reason=revision.
    func testDecisionForeignSender() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        let d = m.decision(message: "vr180-look-set-pack", firstArgument: "2", revision: 5, sender: "console")
        XCTAssertFalse(d.admit)
        XCTAssertEqual(d.reason, "revision")
    }

    // gate: no open batch rejects with reason=revision.
    func testDecisionWithoutBatch() {
        let m = ThreeDRouteMachine()
        let d = m.decision(message: "vr180-look-set-enabled", firstArgument: "true", revision: 5, sender: "store-applier")
        XCTAssertFalse(d.admit)
        XCTAssertEqual(d.reason, "revision")
    }

    // gate: revision ~= store_revision rejects with reason=revision.
    func testDecisionStaleCommandRevision() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        let d = m.decision(message: "vr180-look-set-pack", firstArgument: "2", revision: 4, sender: "store-applier")
        XCTAssertFalse(d.admit)
        XCTAssertEqual(d.reason, "revision")
    }

    // gate: a projection whose kind ~= store_kind rejects; on a non-flat kind
    // the reason is store_kind (flat_engine only applies to flat batches).
    func testDecisionProjectionKindMismatchNonFlat() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "vr180", sender: "store-applier", context: context())
        let d = m.decision(message: "vr180-look-set-projection", firstArgument: "flat-sbs", revision: 5, sender: "store-applier")
        XCTAssertFalse(d.admit)
        XCTAssertEqual(d.reason, "store_kind")
    }

    // gate: flat batch + projection kind mismatch reports flat_engine
    // (sequential overwrite: flat_engine wins over store_kind and revision).
    func testDecisionProjectionKindMismatchFlat() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        let d = m.decision(message: "vr180-look-set-projection", firstArgument: "flat-tb", revision: 5, sender: "store-applier")
        XCTAssertFalse(d.admit)
        XCTAssertEqual(d.reason, "flat_engine")
    }

    // gate: kind check applies to set-projection only; other messages with the
    // current revision admit even when their first argument differs.
    func testDecisionNonProjectionAdmits() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        XCTAssertTrue(m.decision(message: "vr180-look-set-pack", firstArgument: "3", revision: 5, sender: "store-applier").admit)
        XCTAssertTrue(m.decision(message: "vr180-look-set-projection", firstArgument: "flat-sbs", revision: 5, sender: "store-applier").admit)
    }

    // gate: 3D-REJECTED is recorded once per (sender, message, values) key.
    func testRejectionDedupe() {
        var m = ThreeDRouteMachine()
        XCTAssertTrue(m.recordRejection(sender: "console", message: "vr180-look-set-pack", values: "2,9,console"))
        XCTAssertFalse(m.recordRejection(sender: "console", message: "vr180-look-set-pack", values: "2,9,console"))
        XCTAssertTrue(m.recordRejection(sender: "console", message: "vr180-look-set-pack", values: "3,9,console"))
    }

    // route-complete: applied readback matching the batch context -> PASS.
    func testCompletePass() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context(enabled: true, layout: 1, pack: 2))
        XCTAssertEqual(m.complete(receipt: receipt(layout: 1, pack: 2, enabled: true)), .pass)
        XCTAssertEqual(m.completedRevision, 5)
    }

    // route-complete: any mismatch of enabled/layout/pack -> FAIL.
    func testCompleteFailOnMismatch() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context(enabled: true, layout: 1, pack: 2))
        XCTAssertEqual(m.complete(receipt: receipt(layout: 0, pack: 2, enabled: true)), .fail)
    }

    // route-complete: without batch context the verdict is UNVERIFIED.
    func testCompleteUnverifiedWithoutContext() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: nil)
        XCTAssertEqual(m.complete(receipt: receipt()), .unverified)
    }

    // route-complete: a republish of an already-completed batch records no
    // second verdict (no duplicate 3D-VERIFIED).
    func testCompleteOnlyOncePerBatch() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        XCTAssertEqual(m.complete(receipt: receipt()), .pass)
        XCTAssertNil(m.complete(receipt: receipt()))
    }

    // route-complete: a receipt whose completed_revision is not the current
    // batch (stale echo, or mid-batch publish with completed=null) is ignored.
    func testCompleteStaleOrEmptyReceiptIgnored() {
        var m = ThreeDRouteMachine()
        _ = m.openBatch(revision: 5, kind: "flat-sbs", sender: "store-applier", context: context())
        XCTAssertNil(m.complete(receipt: receipt(completed: 4)))
        XCTAssertNil(m.complete(receipt: receipt(completed: nil)))
        XCTAssertNil(m.completedRevision)
    }

    // Receipt parsing: mpv delivers the property as a JSON string or a native
    // object; both decode, and JSON null becomes nil (wire shape unchanged).
    func testAppliedStateDecoding() {
        let json = #"{"source_layout":1,"flat_pack":2,"enabled":true,"revision":5,"completed_revision":null}"#
        let fromString = ThreeDAppliedRouteState(json)
        XCTAssertEqual(fromString, ThreeDAppliedRouteState(sourceLayout: 1, flatPack: 2, enabled: true, revision: 5, completedRevision: nil))
        let native: [String: Any] = ["source_layout": 3, "flat_pack": 0, "enabled": false, "revision": 7, "completed_revision": 7]
        let fromNative = ThreeDAppliedRouteState(native)
        XCTAssertEqual(fromNative, ThreeDAppliedRouteState(sourceLayout: 3, flatPack: 0, enabled: false, revision: 7, completedRevision: 7))
        XCTAssertNil(ThreeDAppliedRouteState("not json"))
        XCTAssertNil(ThreeDAppliedRouteState(["flat_pack": 0])) // missing source_layout/enabled
    }
}
