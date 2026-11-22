// Photon font-resource native coverage (block 190m font repair).
// The harness (Tests/Photon/photon-native-check.py) stages the repo's REAL
// Resources/fonts into a unique test-owned root and exports
// GOR_TEST_RESOURCE_ROOT, and runs each of these tests as its OWN
// swift-test process (strict steps before the feature suites). Tests reset
// font state explicitly at start and end; no shared-state restore is
// pretended. No substitute fixture: the committed payload itself is tested.
#if canImport(AppKit)
import AppKit
import XCTest
@testable import gor

final class PhotonFontResourceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PhotonFont.resetFontLoadStateForTest()
    }

    override func tearDown() {
        PhotonFont.resetFontLoadStateForTest()
        super.tearDown()
    }

    /// Every committed file the automatic random pool may pick (374c:
    /// two variable ttf under sixa/ + one woff2 at root). All are claimed
    /// eligible by pickRandomFontURL, so all must register - including the
    /// woff2 conversion path - deterministically.
    private static let committedFonts = [
        "sixa/Exposure-VAR.ttf",
        "sixa/Milling-TriplexVAR.ttf",
        "DMTLLVIPWeb-Regular-6a47c86c.woff2",
    ]

    /// Staged intended layout resolves, and EVERY committed eligible
    /// candidate registers from it. An UNSTAGED run fails here - that
    /// absence is exactly the run9/run10 hole, so this never skips.
    func testStagedFontsResolveAndRegister() throws {
        let root = try XCTUnwrap(
            GORResources.testResourceRootOverride,
            "harness must stage the intended Resources layout and export GOR_TEST_RESOURCE_ROOT")
        let fonts = try XCTUnwrap(
            GORResources.fonts(),
            "staged fonts/ must resolve through GORResources")
        // Deterministic root check: if a REAL bundled/sibling layout ever
        // outranks the override, say so instead of assuming the override won.
        XCTAssertTrue(fonts.path.hasPrefix(root),
                      "resolution must come from the staged intended layout, got \(fonts.path)")
        for rel in Self.committedFonts {
            let url = fonts.appendingPathComponent(rel)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "committed font missing from staged layout: \(rel)")
            let attemptsBefore = PhotonFont.registrationAttemptCount
            XCTAssertTrue(PhotonFont.loadFromURL(url),
                          "registration failed for committed eligible font \(rel)")
            XCTAssertEqual(PhotonFont.registrationAttemptCount, attemptsBefore + 1,
                           "one registration call per successful load")
            XCTAssertNotEqual(PhotonFont.fontName, "Menlo-Regular",
                              "fallback must not serve when the intended layout is staged")
        }
    }

    /// The ACTUAL automatic first-load route (randomFontOnStartup ->
    /// recursive pickRandomFontURL -> loadFromURL), strict: the FIRST
    /// startup access must select and register a real staged font with
    /// exactly one registration call. Deterministic because the staged
    /// test above proves every eligible candidate loads; a failure here
    /// means pool eligibility and host capability diverge - a real
    /// finding, not a retry-loop matter.
    func testAutomaticStartupSelectsStagedFont() throws {
        _ = try XCTUnwrap(GORResources.fonts(), "staged fonts/ must resolve")
        let before = PhotonFont.registrationAttemptCount
        let name = PhotonFont.fontName
        XCTAssertNotEqual(name, "Menlo-Regular",
                          "first automatic startup load must select a real staged font")
        XCTAssertEqual(PhotonFont.registrationAttemptCount - before, 1,
                       "first automatic load is exactly one registration call")
    }

    /// Deliberately ABSENT layout: the override points at a real root with
    /// no fonts/ inside (an EMPTY fonts dir would be a valid resolution -
    /// the miss requires the layout itself to be absent). The fallback
    /// must stay usable and the failure exactly bounded: one controlled
    /// registration attempt, then the latch serves Menlo without retries.
    func testMissingResourceFallsBackBounded() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("photon-font-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let savedRoot = GORResources.testResourceRootOverride
        defer {
            GORResources.testResourceRootOverride = savedRoot
            try? FileManager.default.removeItem(at: empty)
        }
        GORResources.testResourceRootOverride = empty.path
        // Caveat: this nil assertion also proves the test host has no real
        // bundled/sibling Resources/fonts - true for the toolchain runner.
        XCTAssertNil(GORResources.fonts(), "absent staged layout must not resolve a fonts dir")
        let before = PhotonFont.registrationAttemptCount
        XCTAssertEqual(PhotonFont.fontName, "Menlo-Regular",
                       "missing resource must yield the usable fallback")
        for _ in 0..<100 { _ = PhotonFont.fontName }
        XCTAssertEqual(PhotonFont.fontName, "Menlo-Regular",
                       "fallback remains usable across repeated access")
        XCTAssertEqual(PhotonFont.registrationAttemptCount - before, 1,
                       "bounded fallback: EXACTLY one controlled attempt - zero proves nothing, more is the run9 storm")
    }
}
#endif
