import XCTest
import SubtitleLayout
@testable import SubtitleLayoutStrict

/// P-A3-R1 deterministic suite: separate-instance/cross-parse metadata
/// regression and nonfinite configuration failures. Fixed cell 10 x 20,
/// 5% safe area, viewport 384 x 288 unless noted. Expected values are the
/// hand-computed tables in EXPECTED-R1.md.
final class StrictSubtitleLayoutTests: XCTestCase {

    private func assertBox(_ box: CueBox, cue: Int, x: Double, y: Double, w: Double, h: Double,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(box.cue, cue, file: file, line: line)
        XCTAssertEqual(box.x, x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(box.y, y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(box.width, w, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(box.height, h, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: Cross-parse metadata regression (same instance)

    func testCrossParseAnchorMetadataDropped() throws {
        let layout = try StrictSubtitleLayout()
        let cuesA = try layout.parse(text: FixtureLoading.string("alignment.ass"), format: "ass")
        _ = try layout.parse(text: FixtureLoading.string("basic.srt"), format: "srt")
        // cuesA predates the most recent parse: anchors must NOT apply.
        let boxes = try layout.layout(cues: cuesA, active: [0], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        // Default bottom-center, NOT the recorded \an1 (which would be x=19.2).
        assertBox(boxes[0], cue: 0, x: 137.0, y: 253.6, w: 110, h: 20)
    }

    func testCrossParsePlayResScalingDropped() throws {
        let layout = try StrictSubtitleLayout()
        _ = try layout.parse(text: FixtureLoading.string("basic.ass"), format: "ass") // PlayRes 384x288
        let cuesB = try layout.parse(text: FixtureLoading.string("basic.srt"), format: "srt")
        // Viewport 2x the old PlayRes: if PlayRes leaked, the cell would double.
        let boxes = try layout.layout(cues: cuesB, active: [0], viewportWidth: 768, viewportHeight: 576)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 359.0, y: 527.2, w: 50, h: 20)
    }

    // MARK: Separate-instance metadata regression

    func testSeparateInstanceHasNoMetadata() throws {
        let instanceA = try StrictSubtitleLayout()
        let instanceB = try StrictSubtitleLayout()
        let cuesA = try instanceA.parse(text: FixtureLoading.string("alignment.ass"), format: "ass")
        // Instance B never parsed anything: defaults apply to A's cues.
        let boxes = try instanceB.layout(cues: cuesA, active: [0], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 137.0, y: 253.6, w: 110, h: 20)
    }

    func testOwningInstanceStillUsesMetadata() throws {
        // Control: metadata works when cues come from the instance's own
        // most recent parse. Same numbers as the P-A3 anchor test.
        let layout = try StrictSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("alignment.ass"), format: "ass")
        let boxes = try layout.layout(cues: cues, active: [0, 1, 2], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 3)
        assertBox(boxes[0], cue: 0, x: 19.2, y: 253.6, w: 110, h: 20)
        assertBox(boxes[1], cue: 1, x: 127.0, y: 134.0, w: 130, h: 20)
        assertBox(boxes[2], cue: 2, x: 274.8, y: 14.4, w: 90, h: 20)
    }

    func testForeignCueArrayUsesDefaults() throws {
        let layout = try StrictSubtitleLayout()
        let foreign = [Cue(start: 0, end: 1, text: "hello", track: 0)]
        let boxes = try layout.layout(cues: foreign, active: [0], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 167.0, y: 253.6, w: 50, h: 20)
    }

    // MARK: Nonfinite / invalid cell and safe-area configuration

    func testNonFiniteCellSizeThrows() {
        XCTAssertThrowsError(try StrictSubtitleLayout(cellWidth: .nan)) { error in
            guard case SubtitleConfigError.nonFiniteCellSize = error else {
                XCTFail("expected nonFiniteCellSize, got \(error)"); return
            }
        }
        XCTAssertThrowsError(try StrictSubtitleLayout(cellHeight: .infinity)) { error in
            guard case SubtitleConfigError.nonFiniteCellSize = error else {
                XCTFail("expected nonFiniteCellSize, got \(error)"); return
            }
        }
    }

    func testNonPositiveCellSizeThrows() {
        XCTAssertThrowsError(try StrictSubtitleLayout(cellWidth: 0)) { error in
            guard case SubtitleConfigError.nonPositiveCellSize = error else {
                XCTFail("expected nonPositiveCellSize, got \(error)"); return
            }
        }
        XCTAssertThrowsError(try StrictSubtitleLayout(cellHeight: -20)) { error in
            guard case SubtitleConfigError.nonPositiveCellSize = error else {
                XCTFail("expected nonPositiveCellSize, got \(error)"); return
            }
        }
    }

    func testNonFiniteSafeAreaFractionThrows() {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try StrictSubtitleLayout(safeAreaFraction: bad)) { error in
                guard case SubtitleConfigError.nonFiniteSafeAreaFraction = error else {
                    XCTFail("expected nonFiniteSafeAreaFraction, got \(error)"); return
                }
            }
        }
    }

    func testOutOfRangeSafeAreaFractionThrows() {
        for bad in [0.5, 0.9, -0.1] {
            XCTAssertThrowsError(try StrictSubtitleLayout(safeAreaFraction: bad)) { error in
                guard case SubtitleConfigError.outOfRangeSafeAreaFraction = error else {
                    XCTFail("expected outOfRangeSafeAreaFraction, got \(error)"); return
                }
            }
        }
    }

    func testValidConfigurationsPass() throws {
        _ = try StrictSubtitleLayout()
        _ = try StrictSubtitleLayout(cellWidth: 8, cellHeight: 16, safeAreaFraction: 0)
        _ = try StrictSubtitleLayout(safeAreaFraction: 0.49)
    }

    // MARK: Nonfinite / invalid PlayRes configuration

    func testNonFinitePlayResThrowsNamedError() {
        let layout = try! StrictSubtitleLayout()
        XCTAssertThrowsError(try layout.parse(text: FixtureLoading.string("nonfinite-playres.ass"), format: "ass")) { error in
            guard case SubtitleConfigError.nonFinitePlayRes(let rawX, let rawY) = error else {
                XCTFail("expected nonFinitePlayRes, got \(error)"); return
            }
            XCTAssertEqual(rawX, "nan")
            XCTAssertEqual(rawY, "288")
        }
    }

    func testNonPositivePlayResThrowsNamedError() {
        let layout = try! StrictSubtitleLayout()
        XCTAssertThrowsError(try layout.parse(text: FixtureLoading.string("nonpositive-playres.ass"), format: "ass")) { error in
            guard case SubtitleConfigError.nonPositivePlayRes(let rawX, let rawY) = error else {
                XCTFail("expected nonPositivePlayRes, got \(error)"); return
            }
            XCTAssertEqual(rawX, "0")
            XCTAssertEqual(rawY, "288")
        }
    }

    /// Documents the base-engine behavior the strict layer replaces: the P-A3
    /// engine silently ignores a nonfinite PlayRes (scale 1 fallback) instead
    /// of failing. R1 callers use StrictSubtitleLayout to fail explicitly.
    func testBaseEngineSilentlyFallsBackOnNonfinitePlayRes() throws {
        let base = FixedCellSubtitleLayout()
        let cues = try base.parse(text: FixtureLoading.string("nonfinite-playres.ass"), format: "ass")
        let boxes = try base.layout(cues: cues, active: [0], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 167.0, y: 253.6, w: 50, h: 20) // scale 1 fallback
    }

    // MARK: Strict wrapper parity with P-A3 on valid input

    func testStrictMatchesBaseOnValidInput() throws {
        let strict = try StrictSubtitleLayout()
        let cues = try strict.parse(text: FixtureLoading.string("basic.srt"), format: "srt")
        XCTAssertEqual(cues, [
            Cue(start: 0, end: 1, text: "hello", track: 0),
            Cue(start: 1, end: 2, text: "world", track: 0),
        ])
        let boxes = try strict.layout(cues: cues, active: [0], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 167.0, y: 253.6, w: 50, h: 20)
    }
}
