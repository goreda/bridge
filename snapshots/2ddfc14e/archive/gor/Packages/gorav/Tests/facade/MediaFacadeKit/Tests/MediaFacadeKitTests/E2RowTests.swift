import XCTest
@testable import MediaFacadeKit

/// One named XCTest per approved E2 row (facade-rows-e2.tsv posted at bridge commit
/// 4ae5c0d4c846696fa8c1881050f1ecbf38b0181a, published 2026-11-06T21:53:19Z; 12 rows,
/// e_step E2, sha256 ce6e3ab8bac7050ac041e6da3f2e821de8e950155c4339c44b52f3fdf1384354,
/// byte-identical to the posted block). The E2 table installs additively beside the
/// E1 table (no kind/name key conflicts; E1 rows and aliases unchanged).
/// Row-to-test mapping: ROW-MAP-E2.tsv at the package root.
final class E2RowTests: XCTestCase {

    private var table: RowTable!
    private var engine: FakeEngine!
    private var facade: Facade!

    override func setUpWithError() throws {
        let e1 = try RowTable.parse(tsv: RowTableTests.fixtureText("facade-rows.tsv"))
        let e2 = try RowTable.parse(tsv: RowTableTests.fixtureText("facade-rows-e2.tsv"))
        table = RowTable(rows: e1.rows + e2.rows)
        engine = FakeEngine()
        facade = Facade(engine: engine, rows: table)
    }

    private func assertCommand(_ name: String, _ arguments: [MediaValue], file: StaticString = #filePath, line: UInt = #line) {
        var result: MediaValue?
        XCTAssertNoThrow(result = try facade.command(name, arguments: arguments), file: file, line: line)
        XCTAssertEqual(result, .some(.none), file: file, line: line)
        XCTAssertEqual(engine.calls.last, FakeEngine.RecordedCall(op: .command, name: name, arguments: arguments), file: file, line: line)
    }

    // The combined posted tables: 22 E1 rows + 12 E2 rows = 34 rows, no key conflicts.
    func testE2_installsAdditivelyBesideE1() {
        XCTAssertEqual(table.rows.count, 34)
        XCTAssertEqual(table.rows.filter { $0.eStep == "E2" }.count, 12)
        XCTAssertEqual(table.rows.filter { $0.eStep == "E1" }.count, 22)
    }

    func testE2Row01_command_cycle() {
        assertCommand("cycle", [.text("pause")])
        assertCommand("cycle", [.text("mute"), .text("up")]) // optional value
        XCTAssertThrowsError(try facade.command("cycle", arguments: [.number(1)])) {
            XCTAssertEqual(($0 as? MediaError)?.isInvalidArguments, true)
        }
    }

    func testE2Row01_command_cycle_enginePolicy() {
        // Facade enforces the argument spec only; the (cycle, name) pair's meaning is
        // engine policy: the fake rejects an unknown target name at engine level.
        XCTAssertThrowsError(try facade.command("cycle", arguments: [.text("no-such-property")])) {
            XCTAssertEqual($0 as? MediaError, .unsupportedProperty("no-such-property"))
        }
    }

    func testE2Row02_command_add() {
        assertCommand("add", [.text("speed")])
        assertCommand("add", [.text("volume"), .number(-5)]) // optional numeric value
        XCTAssertThrowsError(try facade.command("add", arguments: [.text("volume"), .text("5")])) {
            XCTAssertEqual(($0 as? MediaError)?.isInvalidArguments, true)
        }
    }

    func testE2Row03_command_frameStep() {
        assertCommand("frame-step", [])
        XCTAssertThrowsError(try facade.command("frame-step", arguments: [.number(1)])) {
            XCTAssertEqual(($0 as? MediaError)?.isInvalidArguments, true)
        }
    }

    func testE2Row04_command_frameBackStep() { assertCommand("frame-back-step", []) }

    func testE2Row05_propertySet_timePos() throws {
        // E2 adds the set row for time-pos (E1 had get/observe only): number(seconds),
        // a unit annotation - type-only, no invented bounds.
        try facade.set("time-pos", value: .number(12.5))
        XCTAssertEqual(engine.calls.last, FakeEngine.RecordedCall(op: .set, name: "time-pos", arguments: [.number(12.5)]))
        XCTAssertThrowsError(try facade.set("time-pos", value: .text("12.5"))) {
            XCTAssertEqual($0 as? MediaError, .invalidValueType(property: "time-pos", expected: "number(seconds)"))
        }
    }

    func testE2Row06_propertyGet_volume() throws {
        var value: MediaValue?
        XCTAssertNoThrow(value = try facade.get("volume"))
        XCTAssertEqual(value, .some(.none)) // unset property: engine returns .none, never fabricated
        XCTAssertEqual(engine.calls.last, FakeEngine.RecordedCall(op: .get, name: "volume", arguments: []))
    }

    func testE2Row07_propertySet_vid() throws {
        try facade.set("vid", value: .number(1))
        try facade.set("vid", value: .text("auto"))
        try facade.set("vid", value: .text("no"))
        for bad: MediaValue in [.number(1.5), .number(.nan), .text("bogus"), .bool(true)] {
            XCTAssertThrowsError(try facade.set("vid", value: bad)) {
                XCTAssertEqual($0 as? MediaError, .invalidValueType(property: "vid", expected: "integer|string(auto|no)"))
            }
        }
    }

    func testE2Row08_propertyMutate_vid() throws {
        // Mutate row uses the facade get/set contract: set domain as row 7, get allowed.
        try facade.set("vid", value: .number(2))
        var value: MediaValue?
        XCTAssertNoThrow(value = try facade.get("vid"))
        XCTAssertEqual(value, .number(2))
    }

    func testE2Row09_propertyGet_aid() throws {
        XCTAssertNoThrow(try facade.get("aid"))
        XCTAssertEqual(engine.calls.last, FakeEngine.RecordedCall(op: .get, name: "aid", arguments: []))
        XCTAssertThrowsError(try facade.set("aid", value: .number(1))) {
            XCTAssertEqual($0 as? MediaError, .unsupportedProperty("aid"))
        }
    }

    func testE2Row10_propertyGet_sid() throws {
        // E1 has the sid set row; E2 adds the sid get row - both dispatch by kind.
        XCTAssertNoThrow(try facade.get("sid"))
        XCTAssertEqual(engine.calls.last, FakeEngine.RecordedCall(op: .get, name: "sid", arguments: []))
        try facade.set("sid", value: .text("no")) // E1 set row still governs set
    }

    func testE2Row11_propertyGet_vid() throws {
        XCTAssertNoThrow(try facade.get("vid"))
        XCTAssertEqual(engine.calls.last, FakeEngine.RecordedCall(op: .get, name: "vid", arguments: []))
    }

    func testE2Row12_propertyObserve_trackList() {
        var received: [MediaValue] = []
        XCTAssertNoThrow(try facade.observe("track-list", token: 300) { received.append($0) })
        let tracks: MediaValue = .list([.object(["id": .number(1), "kind": .text("audio")])])
        engine.simulateChange("track-list", value: tracks)
        XCTAssertEqual(received, [tracks])
        facade.unobserve(token: 300)
        engine.simulateChange("track-list", value: .none) // unavailable is deliverable
        XCTAssertEqual(received, [tracks], "no callback after unobserve")
    }
}
