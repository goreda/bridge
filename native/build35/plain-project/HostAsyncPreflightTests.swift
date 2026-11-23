// Plain AppKit capture capability diagnostic. No gor module or resources.
import AppKit
import XCTest

final class PlainCaptureCapabilityTests: XCTestCase {
    @MainActor func testNaturalPlainFieldDisplayAndWindow() async throws {
        guard let path = ProcessInfo.processInfo.environment["GOR_INLINE_FILE_SEARCH_EVIDENCE"] else { throw XCTSkip("evidence root required") }
        let out = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func save(_ row: [String: Any], _ name: String) throws {
            try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent(name + ".json"))
        }
        func png(_ image: CGImage?, _ name: String) throws -> Bool {
            guard let image, let bytes = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
            try bytes.write(to: out.appendingPathComponent(name + ".png")); return true
        }
        let preflight = CGPreflightScreenCaptureAccess()
        try save(["screenCapturePreflight": preflight, "permissionChanges": false,
                  "boundary": "no request/picker/settings change; mouse cursor is not insertion caret"], "permission-preflight")
        guard preflight else {
            try save(["result": "NOT_ESTABLISHED", "reason": "existing display capture access unavailable; stopped without requesting"], "capability-result")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 30, y: 80, width: 500, height: 25)); window.contentView?.addSubview(field)
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        let accepted = window.makeFirstResponder(field)
        guard accepted, window.isKeyWindow, let editor = field.currentEditor() as? NSTextView, window.firstResponder === editor else {
            try save(["result": "NOT_ESTABLISHED", "reason": "plain field focus/key/editor not established"], "capability-result"); return
        }
        let screens = NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "visibleFrame": NSStringFromRect($0.visibleFrame), "scale": String($0.backingScaleFactor)] }
        var frames: [[String: Any]] = []
        for index in 0..<16 {
            var range = NSRange(location: NSNotFound, length: 0)
            let rect = editor.firstRect(forCharacterRange: NSRange(location: editor.selectedRange().location, length: 0), actualRange: &range)
            let first = NSPoint(x: rect.minX, y: rect.minY); let last = NSPoint(x: rect.minX, y: rect.maxY)
            func lineContained(_ bounds: NSRect) -> Bool {
                // Inclusive endpoint checks handle zero-width insertion-line geometry.
                [first,last].allSatisfy { $0.x >= bounds.minX && $0.x <= bounds.maxX && $0.y >= bounds.minY && $0.y <= bounds.maxY }
            }
            let color = editor.insertionPointColor?.usingColorSpace(.deviceRGB)
            let rgba: [String: Any] = color.map { ["available": true, "r": $0.redComponent, "g": $0.greenComponent, "b": $0.blueComponent, "a": $0.alphaComponent] } ?? ["available": false]
            let start = ProcessInfo.processInfo.systemUptime
            let own = try png(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming]), "window-\(index)")
            // All current onscreen windows, not single-window backing image. No exclusive display capture.
            let display = try png(CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]), "full-onscreen-\(index)")
            frames.append(["index": index, "start": start, "end": ProcessInfo.processInfo.systemUptime,
                "windowSaved": own, "displaySaved": display, "insertionScreenRect": NSStringFromRect(rect),
                "windowFrame": NSStringFromRect(window.frame), "lineEndpointsContainedInWindow": lineContained(window.frame),
                "lineEndpointsContainedInScreen": NSScreen.screens.contains { lineContained($0.frame) },
                "selection": NSStringFromRange(editor.selectedRange()), "shouldDrawInsertionPoint": editor.shouldDrawInsertionPoint,
                "insertionRGBA": rgba, "key": window.isKeyWindow, "firstResponderIsEditor": window.firstResponder === editor])
            try save(["frames": frames, "screens": screens, "boundary": "sequential window/display samples, no synthesized or overlaid caret; human pixel review required"], "paired-samples")
            if index<15 { try? await Task.sleep(nanoseconds: 200_000_000) }
        }
        let paired = frames.filter { ($0["windowSaved"] as? Bool) == true && ($0["displaySaved"] as? Bool) == true }.count
        try save(["result": paired > 0 ? "PAIRED_CAPTURES_REQUIRE_PIXEL_REVIEW" : "NOT_ESTABLISHED", "frames": frames.count,
                  "successfulPairedCount": paired,
                  "missingWindowCount": frames.filter { ($0["windowSaved"] as? Bool) != true }.count,
                  "missingOnscreenCompositeCount": frames.filter { ($0["displaySaved"] as? Bool) != true }.count,
                  "boundary": "capture availability not proof caret visible; no product acceptance"], "capability-result")
    }
}
