// gorTests/InlineFileSearchAcceptanceTests.swift
// Opt-in native witness for the actual file browser inline input and navigation.
// Uses: AppKit, XCTest, FileBrowserPanel, FileBrowserTopBar, DraggableOverlayWindow
// Engine: none
#if canImport(AppKit)
import AppKit
import Foundation
import QuartzCore
import XCTest
import ObjectiveC
@testable import gor

final class InlineFileSearchAcceptanceTests: XCTestCase {
    @MainActor private func views(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { views($0) }
    }
    @MainActor private func buttons(_ bar: FileBrowserTopBar) -> [MusicBtn] {
        bar.subviews.compactMap { $0 as? MusicBtn }
    }
    @MainActor private func button(_ glyph: String, in bar: FileBrowserTopBar) throws -> MusicBtn {
        try XCTUnwrap(buttons(bar).first { button in
            button.layer?.sublayers?.contains { (($0 as? CATextLayer)?.string as? String) == glyph } == true
        }, "actual button glyph missing: \(glyph)")
    }
    @MainActor private func click(_ view: NSView) throws {
        let window = try XCTUnwrap(view.window)
        let location = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let root = try XCTUnwrap(window.contentView)
        let hit = root.hitTest(root.convert(location, from: nil))
        let targetMatches = hit === view || ((view as? NSTextField)?.currentEditor() === hit && hit != nil)
        XCTAssertTrue(targetMatches, "requested control/editor must be actual hit-tested target")
        guard targetMatches else { return }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }
    @MainActor private func key(_ characters: String, code: UInt16, in window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        // Native responder key interpretation, NOT field.stringValue assignment.
        // This does not synthesize an OS keyboard/IME session or install app menu monitors.
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.interpretKeyEvents([event])
    }
    @MainActor private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    @MainActor private func diagnose(_ window: NSWindow, field: NSTextField?, name: String, directory: URL) throws {
        let rows: [[String: String]] = NSApp.windows.map { w in
            ["class": String(describing: type(of: w)), "id": String(describing: ObjectIdentifier(w)),
             "number": String(w.windowNumber), "visible": String(w.isVisible), "key": String(w.isKeyWindow),
             "frame": NSStringFromRect(w.frame), "style": String(w.styleMask.rawValue),
             "content": w.contentView.map { String(describing: type(of: $0)) } ?? "nil",
             "responder": w.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"]
        }
        let record: [String: Any] = ["windows": rows, "active": NSApp.isActive,
            "policy": NSApp.activationPolicy().rawValue, "key": window.isKeyWindow,
            "fieldFrame": field.map { NSStringFromRect($0.frame) } ?? "nil",
            "font": field?.font?.fontName ?? "nil", "fontSize": field?.font?.pointSize ?? 0,
            "editor": (field?.currentEditor()).map { String(describing: type(of: $0)) } ?? "nil"]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + "-state.json"))
    }
    @MainActor private func capture(_ view: NSView, name: String, directory: URL) throws {
        view.layoutSubtreeIfNeeded(); CATransaction.flush()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name + ".png"))
        let image = NSImage(size: view.bounds.size); image.addRepresentation(bitmap)
        if let window = view.window {
            let actual = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                CGWindowID(window.windowNumber), [.boundsIgnoreFraming])
            if let actual {
                let rep = NSBitmapImageRep(cgImage: actual)
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent(name + "-compositor.png"))
            } else {
                try "Compositor image unavailable; cached view is NOT caret proof.\n".write(
                    to: directory.appendingPathComponent(name + "-compositor-unavailable.txt"),
                    atomically: true, encoding: .utf8)
            }
        }
        let attachment = XCTAttachment(image: image); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testInlineNativeInputAndFixtureNavigation() async throws {
        guard ProcessInfo.processInfo.environment["GOR_INLINE_FILE_SEARCH_ACCEPTANCE"] == "1" else {
            throw XCTSkip("opt-in key-capable native acceptance only")
        }
        _ = NSApplication.shared
        let originalPolicy = NSApp.activationPolicy()
        _ = NSApp.setActivationPolicy(.regular)
        // These fixture hosts have already received didFinishLaunching before test injection.
        // Ordinary SwiftPM tests have neither fixture delegate and retain finishLaunching.
        let fixtureHostDelegates = ["AcceptanceApplicationDelegate", "SupportedAcceptanceApplication"]
        let isLaunchedFixtureHost = NSApp.delegate.map {
            fixtureHostDelegates.contains(String(describing: type(of: $0)))
        } ?? false
        if !isLaunchedFixtureHost {
            NSApp.finishLaunching()
        }
        defer { _ = NSApp.setActivationPolicy(originalPolicy) }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let first = fixture.appendingPathComponent("first")
        let second = fixture.appendingPathComponent("second")
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("Café river.mp4"))
            try Data().write(to: directory.appendingPathComponent("other.mp4"))
        }
        let output = ProcessInfo.processInfo.environment["GOR_INLINE_FILE_SEARCH_EVIDENCE"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? fixture.appendingPathComponent("evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = DraggableOverlayWindow.playerWindow(frame: NSRect(x: 80, y: 80, width: 1100, height: 600))
        defer { window.close() }
        XCTAssertTrue(window.canBecomeKey, "NoActivate launch cannot qualify inline input")
        let root = try XCTUnwrap(window.contentView)
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor
        // Construct the actual panel at a fixture path, avoiding the normal ~/Movies initial scan.
        let browser = FileBrowserPanel(frame: root.bounds, initialPath: first.path)
        root.addSubview(browser); browser.layoutSubtreeIfNeeded()
        var chosen: [String] = []
        browser.onSelect = { chosen.append($0) }
        let bar = try XCTUnwrap(browser.subviews.compactMap { $0 as? FileBrowserTopBar }.first)
        let field = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSTextField }.first)
        let search = try button("◌", in: bar)
        let random = try button("∞", in: bar)
        func listKey(_ code: UInt16) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            browser.keyDown(with: event)
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        for _ in 0..<20 where !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
            await wait(0.05)
        }
        try diagnose(window, field: field, name: "before-input", directory: output)
        guard window.isKeyWindow else {
            XCTFail("fixture could not establish real key window; input acceptance NOT_RUN")
            throw NSError(domain: "InlineFixtureNotKey", code: 1)
        }
        XCTAssertLessThan(search.frame.minX, random.frame.minX)
        try capture(root, name: "inline-idle", directory: output)
        let existingWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
        // Owner requires direct typing in the original title control, not another surface.
        InlineRuntimeDiagnostics.save(["windows": InlineRuntimeDiagnostics.windowRows()], name: "window-origin-before-first-input", directory: output)
        try click(field)
        try diagnose(window, field: field, name: "after-first-input", directory: output)
        XCTAssertEqual(Set(NSApp.windows.map { ObjectIdentifier($0) }), existingWindows,
                       "inline search must not construct another window or panel")
        XCTAssertTrue(bar.subviews.contains { $0 === field }, "same original title control remains")
        XCTAssertTrue(browser.isSearchPanelOpen)
        XCTAssertTrue(field.isEditable)
        XCTAssertTrue(window.firstResponder === field.currentEditor())
        let titleEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(titleEditor.isEditable)
        XCTAssertTrue(titleEditor.window === window)
        XCTAssertEqual(titleEditor.selectedRange().length, 0, "empty input has insertion caret, no selection")
        try capture(root, name: "inline-direct-title-caret", directory: output)
        InlineRuntimeDiagnostics.editor(field, name: "natural-after-original-caret-capture", directory: output)
        await InlineRuntimeDiagnostics.samples(field, directory: output)
        try key("r", code: 15, in: window)
        XCTAssertEqual(field.stringValue, "r")
        try capture(root, name: "inline-editing", directory: output)
        await wait(0.4)
        // Actual NSTextInputClient composition calls, not an OS input-source/keyboard claim.
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        editor.setMarkedText("ır", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        await wait(0.35)
        XCTAssertTrue(field.isEditable, "composition must not end editing")
        editor.insertText("ır", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(editor.hasMarkedText())
        try key("\r", code: 36, in: window)
        await wait(0.1)
        XCTAssertFalse(field.isEditable)
        XCTAssertFalse(browser.isSearchPanelOpen)
        XCTAssertTrue(field.stringValue.contains("ır"), "Enter restores the launched-query context")
        try capture(root, name: "inline-results-context", directory: output)
        try diagnose(window, field: field, name: "before-reopen", directory: output)
        try click(try button("●", in: bar))
        try diagnose(window, field: field, name: "after-reopen", directory: output)
        let resumed = try XCTUnwrap(field.currentEditor() as? NSTextView)
        resumed.selectAll(nil)
        try key("r", code: 15, in: window)
        // Actual central navigation transition before the pending 250ms timer can fire.
        let selectedBeforePendingNavigation = chosen.count
        browser.loadPath(second.path)
        // No await/runloop turn: completion cannot install fresh rows yet.
        // Previously mounted keyboard selection must not act during this pending state.
        try listKey(125); try listKey(36)
        XCTAssertEqual(chosen.count, selectedBeforePendingNavigation)
        XCTAssertTrue(views(browser).compactMap { $0 as? FileListView }.isEmpty)
        await wait(0.5)
        XCTAssertFalse(field.isEditable)
        XCTAssertEqual(field.stringValue, second.path)
        XCTAssertFalse(browser.isSearchPanelOpen)
        try capture(root, name: "inline-after-navigation", directory: output)
        try click(try button("◌", in: bar))
        let other = DraggableOverlayWindow.playerWindow(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
        other.makeKeyAndOrderFront(nil); await wait(0.1)
        window.makeKeyAndOrderFront(nil); await wait(0.1)
        XCTAssertTrue(window.isKeyWindow)
        // Refocus by an actual field click, no automatic focus-return promise.
        try click(field)
        XCTAssertTrue(window.firstResponder === field.currentEditor())
        other.close()
        browser.removeFromSuperview()
        XCTAssertFalse(PanelKeyOwnership.shared.openPanels.contains(ObjectIdentifier(bar)))
        XCTAssertFalse(field.isEditable, "removing browser drains inline ownership")
        // New default has no floating control route. Esc restores full list/title.
        root.addSubview(browser); browser.layoutSubtreeIfNeeded()
        browser.loadPath(first.path); await wait(0.3)
        try click(try button("◌", in: bar))
        try key("CAFE", code: 0, in: window)
        let selectedBeforePendingSearch = chosen.count
        try key("\r", code: 36, in: window)
        try listKey(125); try listKey(36)
        XCTAssertEqual(chosen.count, selectedBeforePendingSearch)
        XCTAssertTrue(views(browser).compactMap { $0 as? FileListView }.isEmpty)
        await wait(0.4)
        XCTAssertTrue(window.firstResponder === browser)
        try listKey(125); try listKey(36)
        InlineRuntimeDiagnostics.paths(expected: first.appendingPathComponent("Café river.mp4").path, selected: chosen.last, directory: output)
        XCTAssertEqual(chosen.last, first.appendingPathComponent("Café river.mp4").path,
                       "case/diacritic folded filtered list Return uses its actual entry")
        let selectedBeforePendingClear = chosen.count
        XCTAssertTrue(browser.cancelSearchIfNeeded())
        try listKey(125); try listKey(36)
        XCTAssertEqual(chosen.count, selectedBeforePendingClear)
        await wait(0.4)
        XCTAssertEqual(field.stringValue, first.path)
        XCTAssertFalse(field.isEditable)
        // Full list uses identical arrow/Return route.
        try listKey(125); try listKey(36)
        XCTAssertEqual(chosen.count, 2)
        // Exercise actual field-editor cancel command, not a title setter.
        try click(try button("◌", in: bar)); try key("r", code: 15, in: window)
        try XCTUnwrap(field.currentEditor() as? NSTextView).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await wait(0.4)
        XCTAssertEqual(field.stringValue, first.path)
        XCTAssertFalse(field.isEditable)
        try capture(root, name: "inline-esc-restored-full-list", directory: output)
        let coverage = """
        Actual AppKit view/window, hit-tested click, field-editor interpretKeyEvents, NSTextInputClient marked text and commit, Enter, direct central fixture navigation before debounce, close ownership, case/diacritic folded entry, full/filtered arrow-Return and field-editor Esc, rasterized view captures.
        NOT COVERED: OS keyboard or selected system IME, full MenuActions r/Esc monitors, Cmd+F menu route, actual Home /Volumes or Back/directory/random callback UI routes, playback engines/VR, installed app. NoActivate refused. Captures require human pixel inspection before acceptance.
        """
        try coverage.write(to: output.appendingPathComponent("coverage.txt"), atomically: true, encoding: .utf8)
    }
}
// Measurement only. Never sets editor color, appearance, font or selection.
private enum InlineRuntimeDiagnostics {
    @MainActor static func windowRows() -> [[String: String]] {
        NSApp.windows.map { w in
            let image = class_getImageName(type(of: w)).map { String(cString: $0) } ?? "unavailable"
            return ["class": String(describing: type(of: w)), "image": image,
                    "id": String(describing: ObjectIdentifier(w)), "number": String(w.windowNumber),
                    "visible": String(w.isVisible), "key": String(w.isKeyWindow),
                    "frame": NSStringFromRect(w.frame), "style": String(w.styleMask.rawValue)]
        }
    }
    static func fileRow(_ path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return ["raw": path, "unicodeScalars": path.unicodeScalars.map { $0.value },
                "standardized": url.standardizedFileURL.path,
                "resolved": url.resolvingSymlinksInPath().path,
                "exists": FileManager.default.fileExists(atPath: path),
                "device": (attributes?[.systemNumber] as? NSNumber)?.stringValue ?? "unavailable",
                "inode": (attributes?[.systemFileNumber] as? NSNumber)?.stringValue ?? "unavailable"]
    }
    static func paths(expected: String, selected: String?, directory: URL) {
        let row: [String: Any] = ["expected": fileRow(expected),
            "selected": selected.map { fileRow($0) } ?? ["missing": true],
            "boundary": "raw assertion unchanged; filesystem identity is separate measurement"]
        save(row, name: "selected-file-identity", directory: directory)
    }
    static func save(_ row: [String: Any], name: String, directory: URL) {
        do { try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json")) }
        catch { try? String(describing: error).write(to: directory.appendingPathComponent(name + "-diagnostic-error.txt"), atomically: true, encoding: .utf8) }
    }
    @MainActor static func rgba(_ color: NSColor?) -> [String: Any] {
        guard let color, let rgb = color.usingColorSpace(.deviceRGB) else { return ["available": false] }
        return ["available": true, "red": rgb.redComponent, "green": rgb.greenComponent,
                "blue": rgb.blueComponent, "alpha": rgb.alphaComponent]
    }
    @MainActor static func editor(_ field: NSTextField, name: String, directory: URL) {
        guard let editor = field.currentEditor() as? NSTextView else {
            save(["editor": "absent", "windows": windowRows()], name: name, directory: directory); return
        }
        var actual = NSRange(location: NSNotFound, length: 0)
        let rect = editor.firstRect(forCharacterRange: NSRange(location: editor.selectedRange().location, length: 0), actualRange: &actual)
        let row: [String: Any] = ["editor": String(describing: type(of: editor)),
            "editorImage": class_getImageName(type(of: editor)).map { String(cString: $0) } ?? "unavailable",
            "insertionPointColor": String(describing: editor.insertionPointColor),
            "insertionRGBA": rgba(editor.insertionPointColor),
            "textRGBA": rgba(editor.textColor), "backgroundRGBA": rgba(editor.backgroundColor),
            "shouldDrawInsertionPoint": editor.shouldDrawInsertionPoint,
            "rectNonempty": !rect.isEmpty,
            "rectIntersectsWindow": field.window.map { !$0.frame.intersection(rect).isEmpty } ?? false,
            "rectWindowIntersection": field.window.map { NSStringFromRect($0.frame.intersection(rect)) } ?? "unavailable",
            "textColor": String(describing: editor.textColor), "backgroundColor": String(describing: editor.backgroundColor),
            "drawsBackground": editor.drawsBackground, "appearance": editor.effectiveAppearance.name.rawValue,
            "font": editor.font?.fontName ?? "nil", "fontDescriptor": String(describing: editor.font?.fontDescriptor.fontAttributes),
            "selectedRange": NSStringFromRange(editor.selectedRange()), "actualRange": NSStringFromRange(actual),
            "insertionScreenRect": NSStringFromRect(rect), "editorFrame": NSStringFromRect(editor.frame),
            "editorBounds": NSStringFromRect(editor.bounds), "windows": windowRows(),
            "creationOrigin": "image path only; creation stack not captured; no class allowlist inference",
            "time": ProcessInfo.processInfo.systemUptime]
        save(row, name: name, directory: directory)
    }
    @MainActor static func samples(_ field: NSTextField, directory: URL) async {
        for index in 0..<5 {
            editor(field, name: "natural-caret-\(index)", directory: directory)
            if let w = field.window,
               let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming]),
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: directory.appendingPathComponent("natural-caret-\(index)-compositor.png"))
            }
            if index < 4 { try? await Task.sleep(nanoseconds: 200_000_000) }
        }
    }
}

// Separate test invocation only AFTER original acceptance. Cannot prewarm acceptance.
final class InlinePlatformInputControlTests: XCTestCase {
    @MainActor func testSeparatePlainFieldControl() async throws {
        guard ProcessInfo.processInfo.environment["GOR_INLINE_FILE_SEARCH_ACCEPTANCE"] == "1",
              let path = ProcessInfo.processInfo.environment["GOR_INLINE_FILE_SEARCH_EVIDENCE"] else { throw XCTSkip("diagnostic control only") }
        let output = URL(fileURLWithPath: path).appendingPathComponent("platform-control")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 30, y: 80, width: 500, height: 25))
        window.contentView?.addSubview(field)
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        InlineRuntimeDiagnostics.save(["windows": InlineRuntimeDiagnostics.windowRows(), "boundary": "plain AppKit field after original acceptance in separate test invocation"], name: "before-focus", directory: output)
        let focusAccepted = window.makeFirstResponder(field)
        let editor = field.currentEditor() as? NSTextView
        let established = focusAccepted && window.isKeyWindow && editor != nil && window.firstResponder === editor
        InlineRuntimeDiagnostics.save(["result": established ? "ESTABLISHED" : "NOT_ESTABLISHED",
            "focusAccepted": focusAccepted, "key": window.isKeyWindow, "editorPresent": editor != nil,
            "firstResponderIsEditor": editor != nil && window.firstResponder === editor,
            "active": NSApp.isActive], name: "control-establishment", directory: output)
        InlineRuntimeDiagnostics.editor(field, name: "after-focus", directory: output)
        await InlineRuntimeDiagnostics.samples(field, directory: output)
    }
}

#endif
