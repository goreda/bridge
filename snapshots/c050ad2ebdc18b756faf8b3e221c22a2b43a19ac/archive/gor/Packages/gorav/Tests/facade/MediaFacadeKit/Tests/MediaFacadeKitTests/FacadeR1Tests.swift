import XCTest
@testable import MediaFacadeKit

/// P-B1-R1 strengthening proofs (integrator note at bridge commit a0bdf13,
/// published 2026-11-06T21:33:56Z): isolated dispatch for rows sharing names
/// (set vs mutate), exact observer tokens UInt64.max and 2^53+1, removal proof
/// using a valid typed mutation, and exact engine API tokens in the call log
/// (not Double-converted).
final class FacadeR1Tests: XCTestCase {

    private var table: RowTable!
    private var engine: FakeEngine!
    private var facade: Facade!

    override func setUpWithError() throws {
        table = try RowTable.parse(tsv: RowTableTests.fixtureText("facade-rows.tsv"))
        engine = FakeEngine()
        facade = Facade(engine: engine, rows: table)
    }

    // MARK: (a) Isolated proof for rows sharing names (set vs mutate)

    /// Synthetic table where one name carries divergent set/mutate domains:
    /// dispatch must stay kind-separated - set() uses the property-set row only,
    /// the property-mutate row's domain never leaks in, and vice versa for
    /// mutate-only and get-only names.
    func testR1_kindSeparatedDispatchOnSharedNames() throws {
        let tsv = RowTable.header + "\n"
            + "property-set\tspeed\twrite\tvalue:number(0.01..100)\tnumber\tE1\n"
            + "property-mutate\tspeed\tread-write\tvalue:boolean\tboolean\tE1\n"
            + "property-mutate\tmute\tread-write\tvalue:boolean\tboolean\tE1\n"
            + "property-get\tpause\tread\tnone\tboolean\tE1\n"
        let facade = Facade(engine: FakeEngine(), rows: try RowTable.parse(tsv: tsv))

        // Shared name: the property-set row's domain governs set().
        XCTAssertNoThrow(try facade.set("speed", value: .number(1)))
        XCTAssertThrowsError(try facade.set("speed", value: .bool(true))) {
            XCTAssertEqual($0 as? MediaError, .invalidValueType(property: "speed", expected: "number(0.01..100)"),
                           "mutate row's boolean domain must not leak into set dispatch")
        }
        // Mutate-only name: the mutate row governs (fallback), its boolean domain applies.
        XCTAssertNoThrow(try facade.set("mute", value: .bool(true)))
        XCTAssertThrowsError(try facade.set("mute", value: .number(1))) {
            XCTAssertEqual($0 as? MediaError, .invalidValueType(property: "mute", expected: "boolean"))
        }
        // Get-only name: set is unsupported, get works via the get row.
        XCTAssertThrowsError(try facade.set("pause", value: .bool(true))) {
            XCTAssertEqual($0 as? MediaError, .unsupportedProperty("pause"))
        }
        // Get dispatch: get row first, mutate row as fallback (get/set contract).
        XCTAssertNoThrow(try facade.get("pause"))
        XCTAssertNoThrow(try facade.get("mute"))
    }

    /// The real fixture's shared names (pause, speed, volume have both property-set
    /// and property-mutate rows) dispatch and forward; set-only (sid) and
    /// mutate-only (mute, audio, sub) names resolve their single row.
    func testR1_fixtureSharedAndSingleRowNamesForward() throws {
        for (name, value): (String, MediaValue) in [("pause", .bool(true)), ("speed", .number(2)), ("volume", .number(50)),
                                                    ("sid", .text("auto")), ("mute", .bool(true)),
                                                    ("audio", .text("no")), ("sub", .number(3))] {
            XCTAssertNoThrow(try facade.set(name, value: value), name)
        }
        XCTAssertEqual(engine.calls.map(\.op), Array(repeating: .set, count: 7))
        XCTAssertEqual(Set(engine.calls.map(\.name)), ["pause", "speed", "volume", "sid", "mute", "audio", "sub"])
    }

    // MARK: (b) + (d) Exact observer tokens UInt64.max and 2^53+1, recorded natively

    func testR1_exactObserverTokens() {
        for token: UInt64 in [.max, 9_007_199_254_740_993] { // UInt64.max and 2^53+1
            // The hazard this guards: neither token survives a Double round-trip.
            XCTAssertNotEqual(UInt64(exactly: Double(token)), token, "precondition: Double cannot represent \(token)")

            var received: [MediaValue] = []
            XCTAssertNoThrow(try facade.observe("pause", token: token) { received.append($0) })
            XCTAssertEqual(engine.calls.last,
                           FakeEngine.RecordedCall(op: .observe, name: "pause", arguments: [], token: token),
                           "observe must record the exact UInt64 token")
            engine.simulateChange("pause", value: .bool(true))
            XCTAssertEqual(received, [.bool(true)])

            facade.unobserve(token: token)
            XCTAssertEqual(engine.calls.last,
                           FakeEngine.RecordedCall(op: .unobserve, name: "pause", arguments: [], token: token),
                           "unobserve must record the exact UInt64 token")
            engine.simulateChange("pause", value: .bool(false))
            XCTAssertEqual(received, [.bool(true)], "no callback after unobserve of the exact token")
        }
    }

    // MARK: (c) Removal proof using a valid typed mutation

    /// After unobserve, a VALID typed mutation that really reaches the engine
    /// must still not fire the removed observer - removal is real, not a
    /// swallowed or rejected call.
    func testR1_removalProofValidTypedMutation() throws {
        var received: [MediaValue] = []
        try facade.observe("volume", token: 7) { received.append($0) }
        facade.unobserve(token: 7)

        try facade.set("volume", value: .number(50)) // valid per row 10 (number(percent))
        XCTAssertEqual(engine.propertySnapshot["volume"], .number(50), "mutation really reached the engine")
        XCTAssertEqual(engine.calls.map(\.op), [.observe, .unobserve, .set])
        XCTAssertEqual(received, [], "removed observer must not fire on a valid engine mutation")
    }
}
