import XCTest
@testable import SubtitleLayout

/// Deterministic XCTest suite for packet P-A3.
/// Fixed cell 10 x 20, 5% safe area, viewport 384 x 288 unless noted.
/// Expected values are the hand-computed tables in EXPECTED.md.
final class SubtitleLayoutTests: XCTestCase {

    private func assertBox(_ box: CueBox, cue: Int, x: Double, y: Double, w: Double, h: Double,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(box.cue, cue, file: file, line: line)
        XCTAssertEqual(box.x, x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(box.y, y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(box.width, w, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(box.height, h, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: Parse: exact track/times/text

    func testParseBasicSRT() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("basic.srt"), format: "srt")
        XCTAssertEqual(cues, [
            Cue(start: 0, end: 1, text: "hello", track: 0),
            Cue(start: 1, end: 2, text: "world", track: 0),
        ])
    }

    func testParseOverlapSRT() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("overlap.srt"), format: "srt")
        XCTAssertEqual(cues, [
            Cue(start: 0, end: 1, text: "hello", track: 0),
            Cue(start: 0.5, end: 1.5, text: "second", track: 0),
            Cue(start: 1, end: 2, text: "world", track: 0),
        ])
    }

    func testParseBasicASSCommasAndHardBreak() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("basic.ass"), format: "ass")
        XCTAssertEqual(cues, [
            Cue(start: 0, end: 1, text: "hello", track: 0),
            Cue(start: 1, end: 2, text: "world, with commas\nsecond line", track: 0),
        ])
    }

    func testParseAlignmentASSStripsOverrides() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("alignment.ass"), format: "ass")
        XCTAssertEqual(cues.map(\.text), ["bottom left", "middle center", "top right"])
        XCTAssertEqual(cues.map(\.start), [0, 0, 0])
        XCTAssertEqual(cues.map(\.end), [1, 1, 1])
        XCTAssertEqual(cues.map(\.track), [0, 0, 0])
    }

    // MARK: Unicode round-trip

    func testUnicodeRoundTrip() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("unicode.srt"), format: "srt")
        XCTAssertEqual(cues.count, 2)
        // Turkish dotted I / dotless i.
        XCTAssertEqual(cues[0].text, "I\u{131} \u{130}i")
        XCTAssertEqual(cues[0].text.count, 5)
        // Combining accents stay attached to their base characters.
        XCTAssertEqual(cues[1].text, "cafe\u{301} nai\u{308}ve")
        XCTAssertEqual(cues[1].text.count, 10)
    }

    // MARK: Active: half-open intervals, overlap preserved

    func testActiveHalfOpenIntervals() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("overlap.srt"), format: "srt")
        XCTAssertEqual(layout.active(cues: cues, at: 0), [0])
        XCTAssertEqual(layout.active(cues: cues, at: 0.25), [0])
        XCTAssertEqual(layout.active(cues: cues, at: 0.5), [0, 1])
        XCTAssertEqual(layout.active(cues: cues, at: 0.75), [0, 1])
        XCTAssertEqual(layout.active(cues: cues, at: 1.0), [1, 2])
        XCTAssertEqual(layout.active(cues: cues, at: 1.5), [2])
        XCTAssertEqual(layout.active(cues: cues, at: 2.0), [])
        XCTAssertEqual(layout.active(cues: cues, at: -1), [])
    }

    // MARK: Layout: deterministic boxes

    func testLayoutBasicSRTBottomCenter() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("basic.srt"), format: "srt")
        let boxes = try layout.layout(cues: cues, active: [0], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 167.0, y: 253.6, w: 50, h: 20)
    }

    func testLayoutOverlapStacksUpward() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("overlap.srt"), format: "srt")
        let active = layout.active(cues: cues, at: 0.75)
        let boxes = try layout.layout(cues: cues, active: active, viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 2)
        assertBox(boxes[0], cue: 0, x: 167.0, y: 253.6, w: 50, h: 20)
        assertBox(boxes[1], cue: 1, x: 162.0, y: 233.6, w: 60, h: 20)
    }

    func testLayoutASSMultiLine() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("basic.ass"), format: "ass")
        let boxes = try layout.layout(cues: cues, active: [1], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 1)
        // 18-char longest line, 2 lines.
        assertBox(boxes[0], cue: 1, x: 102.0, y: 233.6, w: 180, h: 40)
    }

    func testLayoutASSPlayResScaling() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("basic.ass"), format: "ass")
        // Viewport is exactly 2x PlayRes (384 x 288), so the cell doubles.
        let boxes = try layout.layout(cues: cues, active: [0], viewportWidth: 768, viewportHeight: 576)
        XCTAssertEqual(boxes.count, 1)
        assertBox(boxes[0], cue: 0, x: 334.0, y: 507.2, w: 100, h: 40)
    }

    func testLayoutASSAnchors() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("alignment.ass"), format: "ass")
        let boxes = try layout.layout(cues: cues, active: [0, 1, 2], viewportWidth: 384, viewportHeight: 288)
        XCTAssertEqual(boxes.count, 3)
        assertBox(boxes[0], cue: 0, x: 19.2, y: 253.6, w: 110, h: 20)   // \an1 bottom-left
        assertBox(boxes[1], cue: 1, x: 127.0, y: 134.0, w: 130, h: 20)   // \an5 middle-center
        assertBox(boxes[2], cue: 2, x: 274.8, y: 14.4, w: 90, h: 20)     // \an9 top-right
    }

    func testLayoutBoxesFiniteAndNonnegative() throws {
        let layout = FixedCellSubtitleLayout()
        for name in ["basic.srt", "overlap.srt", "unicode.srt", "basic.ass", "alignment.ass"] {
            let format = name.hasSuffix(".srt") ? "srt" : "ass"
            let cues = try layout.parse(text: FixtureLoading.string(name), format: format)
            let active = layout.active(cues: cues, at: 0.75)
            let boxes = try layout.layout(cues: cues, active: active, viewportWidth: 384, viewportHeight: 288)
            for box in boxes {
                XCTAssertTrue(box.x.isFinite && box.y.isFinite && box.width.isFinite && box.height.isFinite, name)
                XCTAssertGreaterThanOrEqual(box.width, 0, name)
                XCTAssertGreaterThanOrEqual(box.height, 0, name)
                XCTAssertGreaterThanOrEqual(box.x, 0, name)
                XCTAssertGreaterThanOrEqual(box.y, 0, name)
            }
        }
    }

    // MARK: Errors

    func testMalformedTimeRangeThrowsNamedError() throws {
        let layout = FixedCellSubtitleLayout()
        XCTAssertThrowsError(try layout.parse(text: FixtureLoading.string("invalid.srt"), format: "srt")) { error in
            guard case SubtitleParseError.malformedTimeRange(let raw) = error else {
                XCTFail("expected SubtitleParseError.malformedTimeRange, got \(error)")
                return
            }
            XCTAssertTrue(raw.contains("AA"))
        }
    }

    func testEndNotAfterStartThrowsMalformedTimeRange() {
        let layout = FixedCellSubtitleLayout()
        let text = "1\n00:00:01,000 --> 00:00:01,000\nzero length\n"
        XCTAssertThrowsError(try layout.parse(text: text, format: "srt")) { error in
            guard case SubtitleParseError.malformedTimeRange = error else {
                XCTFail("expected SubtitleParseError.malformedTimeRange, got \(error)")
                return
            }
        }
    }

    func testUnsupportedFormatThrowsNamedError() {
        let layout = FixedCellSubtitleLayout()
        XCTAssertThrowsError(try layout.parse(text: "x", format: "vtt")) { error in
            guard case SubtitleParseError.unsupportedFormat(let format) = error else {
                XCTFail("expected SubtitleParseError.unsupportedFormat, got \(error)")
                return
            }
            XCTAssertEqual(format, "vtt")
        }
    }

    func testEmptyInputThrowsNamedError() {
        let layout = FixedCellSubtitleLayout()
        XCTAssertThrowsError(try layout.parse(text: "", format: "srt")) { error in
            guard case SubtitleParseError.emptyInput = error else {
                XCTFail("expected SubtitleParseError.emptyInput, got \(error)")
                return
            }
        }
    }

    func testInvalidViewportThrowsNamedError() throws {
        let layout = FixedCellSubtitleLayout()
        let cues = try layout.parse(text: FixtureLoading.string("basic.srt"), format: "srt")
        XCTAssertThrowsError(try layout.layout(cues: cues, active: [0], viewportWidth: 0, viewportHeight: 288)) { error in
            guard case SubtitleLayoutError.invalidViewport = error else {
                XCTFail("expected SubtitleLayoutError.invalidViewport, got \(error)")
                return
            }
        }
    }
}
