import AppKit
import Foundation
import XCTest

// Same synthetic test runs through actual host Bundle.load and XCTestSuite.run.
final class HostAsyncPreflightTests: XCTestCase {
    @MainActor func testAsyncMainLoopAndKeyWindow() async throws {
        print("PREFLIGHT_PROGRESS body-entered main=\(Thread.isMainThread)")
        fflush(stdout)
        XCTAssertTrue(Thread.isMainThread)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSTextField(string: "Synthetic host preflight only")
        field.frame = NSRect(x: 20, y: 40, width: 320, height: 28)
        window.contentView?.addSubview(field)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(field)
        var mainLoopCallback = false
        DispatchQueue.main.async {
            print("PREFLIGHT_PROGRESS main-callback")
            fflush(stdout)
            mainLoopCallback = true
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        print("PREFLIGHT_PROGRESS await-returned main=\(Thread.isMainThread)")
        fflush(stdout)
        XCTAssertTrue(mainLoopCallback, "async XCTestSuite must permit main runloop callback")
        XCTAssertTrue(NSApp.isActive)
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(window.firstResponder === field.currentEditor())
        XCTAssertTrue(field.currentEditor() is NSTextView)
        if let directory = ProcessInfo.processInfo.environment["GOR_INLINE_FILE_SEARCH_EVIDENCE"] {
            try "ASYNC_MAIN_KEY_PREFLIGHT_EXECUTED\n".write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("async-preflight-witness.txt"),
                atomically: true, encoding: .utf8)
        }
    }
}
