import XCTest
@testable import ParityCore

final class ParityRunnerTests: XCTestCase {
    let runner = TSVParityRunner()

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func loadStubs(_ name: String) throws -> [StubProbeBackend] {
        try StubProbeBackend.load(fromJSON: fixtureData(name))
    }

    private func rows(_ tsv: String) -> [[String]] {
        tsv.split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast() // trailing newline produces a final empty element
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    // Exact header and one row per backend, in left-then-right order.
    func testHeaderAndRowShape() throws {
        let stubs = try loadStubs("parity-stub-equal")
        let tsv = try runner.run(fixture: "parity-a24.mp4", seekTo: 1.0, left: stubs[0], right: stubs[1])
        let rows = rows(tsv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["fixture", "backend", "frames", "duration_s", "seek_target_s", "seek_landing_s", "av_offset_s", "status"])
        XCTAssertEqual(rows[1].count, 8)
        XCTAssertEqual(rows[2].count, 8)
        XCTAssertEqual(rows[1][1], "stub-a")
        XCTAssertEqual(rows[2][1], "stub-b")
        XCTAssertTrue(tsv.hasSuffix("\n"))
    }

    // Known stub values round-trip numerically through the TSV.
    func testEqualStubsPassAndRoundTrip() throws {
        let stubs = try loadStubs("parity-stub-equal")
        let tsv = try runner.run(fixture: "parity-a24.mp4", seekTo: 1.0, left: stubs[0], right: stubs[1])
        let rows = rows(tsv)
        for i in 1...2 {
            XCTAssertEqual(Int(rows[i][2]), 48)
            XCTAssertEqual(Double(rows[i][3]), 2.0)
            XCTAssertEqual(Double(rows[i][4]), 1.0)
            XCTAssertEqual(Double(rows[i][5]), 1.0416666666666667)
            XCTAssertEqual(Double(rows[i][6]), 0.002)
            XCTAssertEqual(rows[i][7], "pass")
        }
    }

    // Injected differences remain visible and each row carries its own
    // backend's values (two different stubs catch hardcoded equal values).
    func testDifferentStubsStayVisible() throws {
        let stubs = try loadStubs("parity-stub-different")
        let tsv = try runner.run(fixture: "parity-a24.mp4", seekTo: 1.0, left: stubs[0], right: stubs[1])
        let rows = rows(tsv)
        XCTAssertEqual(rows[1][7], "different")
        XCTAssertEqual(rows[2][7], "different")
        // left row carries stub-a values
        XCTAssertEqual(Int(rows[1][2]), 48)
        XCTAssertEqual(Double(rows[1][5]), 1.0416666666666667)
        XCTAssertEqual(Double(rows[1][6]), 0.002)
        // right row carries stub-b values, which must actually differ
        XCTAssertEqual(Int(rows[2][2]), 47)
        XCTAssertEqual(Double(rows[2][5]), 1.0833333333333333)
        XCTAssertEqual(Double(rows[2][6]), -0.017)
        XCTAssertNotEqual(rows[1][2], rows[2][2])
        XCTAssertNotEqual(rows[1][6], rows[2][6])
        // duration agrees, so the row still reports the shared value
        XCTAssertEqual(Double(rows[1][3]), Double(rows[2][3]))
    }

    // Missing values become NA and force a non-pass status on both rows.
    func testMissingValuesBecomeNAAndUnavailable() throws {
        let stubs = try loadStubs("parity-missing")
        let tsv = try runner.run(fixture: "parity-a24.mp4", seekTo: 1.0, left: stubs[0], right: stubs[1])
        let rows = rows(tsv)
        XCTAssertEqual(rows[1][2], "NA") // stub-a frames missing
        XCTAssertEqual(rows[1][5], "NA") // stub-a seek landing missing
        XCTAssertEqual(rows[1][6], "NA") // stub-a av offset missing
        XCTAssertEqual(rows[2][2], "48")
        XCTAssertEqual(rows[2][3], "NA") // stub-b duration missing
        XCTAssertEqual(rows[1][7], "unavailable")
        XCTAssertEqual(rows[2][7], "unavailable")
        // a present value shared by both sides still prints on both rows
        XCTAssertEqual(Double(rows[1][3]), 2.0)
        XCTAssertEqual(Double(rows[2][5]), 1.0416666666666667)
    }

    // Errors are explicit in the status column; the failed backend's
    // measured fields are NA and the surviving peer cannot claim parity.
    func testErrorIsExplicitAndPeerUnavailable() throws {
        let bad = StubProbeBackend(name: "stub-bad", failingWith: "decoder exploded")
        let good = StubProbeBackend(name: "stub-good", probe: PlaybackProbe(frames: 48, duration: 2.0, seekLanding: 1.0, avOffset: 0.0))
        let tsv = try runner.run(fixture: "parity-a24.mp4", seekTo: 1.0, left: bad, right: good)
        let rows = rows(tsv)
        XCTAssertEqual(rows[1][2], "NA")
        XCTAssertEqual(rows[1][3], "NA")
        XCTAssertTrue(rows[1][7].hasPrefix("error("), "status must name the failure, got \(rows[1][7])")
        XCTAssertTrue(rows[1][7].contains("decoder exploded"))
        XCTAssertEqual(rows[2][2], "48")
        XCTAssertEqual(rows[2][7], "unavailable")
    }

    // Tabs, newlines, carriage returns and backslashes in backend or
    // fixture names can never corrupt the row/column structure.
    func testEscapingKeepsRowsIntact() throws {
        let nasty = StubProbeBackend(name: "we\tird\nna\\me", probe: PlaybackProbe(frames: 1))
        let plain = StubProbeBackend(name: "plain", probe: PlaybackProbe(frames: 1))
        let tsv = try runner.run(fixture: "fix\tture\nname", seekTo: 1.0, left: nasty, right: plain)
        let rows = rows(tsv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].count, 8)
        XCTAssertEqual(rows[2].count, 8)
        XCTAssertEqual(rows[1][1], "we\\tird\\nna\\\\me")
        XCTAssertEqual(rows[1][0], "fix\\tture\\nname")
        // no raw control characters anywhere in the output
        XCTAssertFalse(tsv.contains(where: { $0 == "\r" }))
        for line in tsv.split(separator: "\n") {
            XCTAssertEqual(line.filter { $0 == "\t" }.count, 7, "each row must have exactly 8 fields")
        }
        // duration/seekLanding/avOffset are NA here (nil), not zero
        XCTAssertEqual(rows[1][3], "NA")
    }

    // Non-finite seek targets are rejected before any probing.
    func testNonFiniteSeekTargetThrows() throws {
        let stubs = try loadStubs("parity-stub-equal")
        XCTAssertThrowsError(try runner.run(fixture: "f", seekTo: .nan, left: stubs[0], right: stubs[1])) { error in
            XCTAssertEqual(String(describing: error), "seek target must be a finite number")
        }
        XCTAssertThrowsError(try runner.run(fixture: "f", seekTo: .infinity, left: stubs[0], right: stubs[1]))
    }

    // Stub JSON: wrong backend count and malformed JSON fail loudly.
    func testStubFixtureValidation() throws {
        XCTAssertThrowsError(try StubProbeBackend.load(fromJSON: Data("{\"backends\":[]}".utf8))) { error in
            XCTAssertEqual(String(describing: error), "stub fixture must contain exactly two backends, found 0")
        }
        XCTAssertThrowsError(try StubProbeBackend.load(fromJSON: Data("not json".utf8)))
    }

    // Shortest-round-trip formatting: exact bit patterns survive the TSV.
    func testNumberFormattingRoundTrips() throws {
        let samples: [Double] = [0.0, -0.0, 2.0, 0.002, -0.017, 1.0416666666666667, 1e-7, 123456.7890123]
        for v in samples {
            XCTAssertEqual(Double(TSVFormat.double(v)), v)
        }
        XCTAssertEqual(TSVFormat.double(2.5), "2.5") // locale-independent dot, fixed shape
    }

    // Escaping table is exact, including C0 and DEL controls.
    func testSanitizeTable() {
        XCTAssertEqual(TSVEscape.sanitize("a\tb\nc\rd\\e"), "a\\tb\\nc\\rd\\\\e")
        XCTAssertEqual(TSVEscape.sanitize("x\u{01}y\u{7F}"), "x\\u{01}y\\u{7F}")
        XCTAssertEqual(TSVEscape.sanitize("plain"), "plain")
        XCTAssertEqual(TSVEscape.sanitize("türkçe"), "türkçe") // non-control UTF-8 passes through
    }
}
