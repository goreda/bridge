// Photon candidate native coverage: host/window close lifecycle.
// Scenarios from the delivery architect: fresh host on a reused NSWindow,
// user/programmatic/concurrent close, and quit joining an in-flight
// owned-panel fade. Real GorAVPlayerHost/GorAVHostWindow/GORInputPanel on a
// real window server; native execution has not yet been performed.
#if canImport(AppKit)
import AppKit
import XCTest
@testable import gor

final class PhotonHostCloseLifecycleTests: XCTestCase {

    @MainActor
    private func makeHost(reusing window: NSWindow? = nil) -> GorAVPlayerHost {
        _ = NSApplication.shared
        return GorAVPlayerHost(inWindowChrome: true, playerWindow: window)
    }

    // A definitive close belongs to the per-host wrapper. A new host on the
    // SAME underlying NSWindow must start with a fresh wrapper lifecycle:
    // delegate rebound, content installed, and its own close barrier working.
    @MainActor
    func testFreshHostOnReusedWindowGetsFreshLifecycle() async throws {
        let host1 = makeHost()
        let window = try XCTUnwrap(host1.window)
        await host1.gateCloseAction()
        XCTAssertNil(window.delegate, "closed host unbinds the window delegate")

        let host2 = makeHost(reusing: window)
        XCTAssertTrue(host2.window === window, "engine swap reuses the chrome window object")
        XCTAssertNotNil(window.delegate, "fresh host rebinds the window delegate")
        XCTAssertNotNil(window.contentView, "fresh host installs its content view")
        // The reused window must not inherit the first host's terminal close:
        // the new host's own close barrier must run and resolve.
        await host2.gateCloseAction()
        XCTAssertNil(window.delegate, "second host closes cleanly on the reused window")
    }

    @MainActor
    func testProgrammaticCloseResolvesEveryWaiter() async throws {
        let host = makeHost()
        let window = try XCTUnwrap(host.window)
        async let first: Void = host.gateCloseAction()
        async let second: Void = host.gateCloseAction()
        _ = await (first, second)
        XCTAssertNil(window.delegate)
    }

    // Raw user close (windowShouldClose path) must drive the same owned-panel
    // fade and resolve a programmatic waiter that joins mid-flight.
    @MainActor
    func testUserCloseThenProgrammaticWaiterJoins() async throws {
        let host = makeHost()
        let window = try XCTUnwrap(host.window)
        let panel = GORInputPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        XCTAssertEqual(window.delegate?.windowShouldClose?(window), false,
                       "AppKit user-close delegate must defer for owned-panel fade")
        await host.gateCloseAction() // programmatic waiter joins in flight
        XCTAssertNil(window.delegate)
        XCTAssertFalse(panel.isVisible, "owned panel is ordered out by the fade")
    }

    // Concurrent programmatic close + user close share one completion; the
    // window closes exactly once and every waiter resolves.
    @MainActor
    func testConcurrentUserAndProgrammaticClose() async throws {
        let host = makeHost()
        let window = try XCTUnwrap(host.window)
        async let waiter: Void = host.gateCloseAction()
        XCTAssertEqual(window.delegate?.windowShouldClose?(window), false)
        await waiter
        XCTAssertNil(window.delegate)
        // A late second close is a no-op that still resolves.
        await host.gateCloseAction()
    }

    // Quit fade during an in-flight owned-panel close fade: both complete,
    // the panel closes once and its pre-fade alpha/input state is restored
    // after terminal orderOut/close.
    @MainActor
    func testQuitFadeJoinsInFlightOwnedPanelFade() async throws {
        let host = makeHost()
        let window = try XCTUnwrap(host.window)
        let panel = GORInputPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        let originalAlpha = panel.alphaValue
        async let closeWait: Void = host.gateCloseAction() // starts owned-panel fade (0.77s)
        try await Task.sleep(nanoseconds: 100_000_000) // let the fade actually start
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            GORInputPanel.fadeAllForQuit(excluding: nil, duration: 0.77) { cont.resume() }
        }
        await closeWait
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, originalAlpha, accuracy: 0.001,
                       "joined fade restores the panel's pre-fade alpha after close")
    }
}
#endif
