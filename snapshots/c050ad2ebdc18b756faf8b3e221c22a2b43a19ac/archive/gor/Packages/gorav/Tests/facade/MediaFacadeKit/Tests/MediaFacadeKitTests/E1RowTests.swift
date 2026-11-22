import XCTest
@testable import MediaFacadeKit

/// One named XCTest per approved E1 row (facade-rows.tsv posted at bridge commit
/// 0fe957bed27c486a58b19f5515cce7d662cabae5; 22 rows). Each test proves exact
/// forwarding of name/typed arguments and return-or-error through Facade into
/// FakeEngine; observer rows prove registration/callback/removal. Row-to-test
/// mapping: ROW-MAP.tsv at the package root.
final class E1RowTests: XCTestCase {

    private var table: RowTable!
    private var engine: FakeEngine!
    private var facade: Facade!

    override func setUpWithError() throws {
        table = try RowTable.parse(tsv: RowTableTests.fixtureText("facade-rows.tsv"))
        engine = FakeEngine()
        facade = Facade(engine: engine, rows: table)
    }

    private func assertOnlyCall(_ op: FakeEngine.RecordedCall.Op, _ name: String, _ arguments: [MediaValue], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(engine.calls.count, 1, file: file, line: line)
        XCTAssertEqual(engine.calls.first, FakeEngine.RecordedCall(op: op, name: name, arguments: arguments), file: file, line: line)
    }

    // MARK: command rows (command-result-or-error: result passthrough, errors preserved)

    func testRow01_command_loadfile() throws {
        XCTAssertEqual(try facade.command("loadfile", arguments: [.text("clip.mp4")]), .none)
        assertOnlyCall(.command, "loadfile", [.text("clip.mp4")])
        // optional arguments append in declared order and forward verbatim
        _ = try facade.command("loadfile", arguments: [.text("clip.mp4"), .text("replace"), .number(2), .object(["demuxer": .text("mkv")])])
        XCTAssertEqual(engine.calls.last?.arguments, [.text("clip.mp4"), .text("replace"), .number(2), .object(["demuxer": .text("mkv")])])
        // missing required url, surplus argument, and wrong type are rejected before the engine
        let before = engine.calls.count
        XCTAssertThrowsError(try facade.command("loadfile", arguments: [])) { XCTAssertTrue($0 is MediaError) }
        XCTAssertThrowsError(try facade.command("loadfile", arguments: [.text("a"), .text("b"), .number(1), .object([:]), .number(0)])) { XCTAssertTrue($0 is MediaError) }
        XCTAssertThrowsError(try facade.command("loadfile", arguments: [.number(3)])) { XCTAssertTrue($0 is MediaError) }
        XCTAssertEqual(engine.calls.count, before)
        // errors are preserved, not swallowed
        engine.scriptError("command:loadfile", .engineFailure("open failed"))
        XCTAssertThrowsError(try facade.command("loadfile", arguments: [.text("clip.mp4")])) {
            XCTAssertEqual($0 as? MediaError, .engineFailure("open failed"))
        }
    }

    func testRow02_command_seek() throws {
        XCTAssertEqual(try facade.command("seek", arguments: [.number(10.5)]), .none)
        assertOnlyCall(.command, "seek", [.number(10.5)])
        _ = try facade.command("seek", arguments: [.number(10.5), .text("absolute")])
        XCTAssertEqual(engine.calls.last?.arguments, [.number(10.5), .text("absolute")])
        XCTAssertThrowsError(try facade.command("seek", arguments: [])) { XCTAssertTrue($0 is MediaError) }
        XCTAssertThrowsError(try facade.command("seek", arguments: [.text("10")])) { XCTAssertTrue($0 is MediaError) }
        engine.scriptError("command:seek", .engineFailure("seek failed"))
        XCTAssertThrowsError(try facade.command("seek", arguments: [.number(1)])) {
            XCTAssertEqual($0 as? MediaError, .engineFailure("seek failed"))
        }
    }

    func testRow03_command_stop() throws {
        XCTAssertEqual(try facade.command("stop", arguments: []), .none)
        assertOnlyCall(.command, "stop", [])
        _ = try facade.command("stop", arguments: [.text("keep-playlist")])
        XCTAssertEqual(engine.calls.last?.arguments, [.text("keep-playlist")])
        XCTAssertThrowsError(try facade.command("stop", arguments: [.number(1)])) { XCTAssertTrue($0 is MediaError) }
    }

    // MARK: property-get rows

    func testRow04_propertyGet_pause() throws {
        let engine = FakeEngine(initialProperties: ["pause": .bool(true)])
        let facade = Facade(engine: engine, rows: table)
        XCTAssertEqual(try facade.get("pause"), .bool(true))
        XCTAssertEqual(engine.calls.first, FakeEngine.RecordedCall(op: .get, name: "pause", arguments: []))
    }

    func testRow05_propertyGet_timePos() throws {
        let engine = FakeEngine(initialProperties: ["time-pos": .number(61.25)])
        let facade = Facade(engine: engine, rows: table)
        XCTAssertEqual(try facade.get("time-pos"), .number(61.25))
        // "-or-unavailable": .none passes through as unavailable, never fabricated
        XCTAssertEqual(try facade.get("duration"), .none)
    }

    func testRow06_propertyGet_duration() throws {
        let engine = FakeEngine(initialProperties: ["duration": .number(2.0)])
        let facade = Facade(engine: engine, rows: table)
        XCTAssertEqual(try facade.get("duration"), .number(2.0))
    }

    func testRow07_propertyGet_trackList() throws {
        let tracks: MediaValue = .list([.object(["id": .number(1), "type": .text("video")]), .object(["id": .number(2), "type": .text("audio")])])
        let engine = FakeEngine(initialProperties: ["track-list": tracks])
        let facade = Facade(engine: engine, rows: table)
        XCTAssertEqual(try facade.get("track-list"), tracks)
        XCTAssertEqual(try Facade(engine: FakeEngine(), rows: table).get("track-list"), .none, "unavailable track-list is .none")
    }

    // MARK: property-set rows

    func testRow08_propertySet_pause() throws {
        try facade.set("pause", value: .bool(false))
        assertOnlyCall(.set, "pause", [.bool(false)])
        XCTAssertThrowsError(try facade.set("pause", value: .text("no"))) {
            guard case .invalidValueType = ($0 as? MediaError) else { return XCTFail("expected invalidValueType, got \($0)") }
        }
        XCTAssertEqual(engine.calls.count, 1, "rejected set must not reach the engine")
    }

    func testRow09_propertySet_speed() throws {
        try facade.set("speed", value: .number(1.5))
        assertOnlyCall(.set, "speed", [.number(1.5)])
        XCTAssertThrowsError(try facade.set("speed", value: .text("fast"))) { XCTAssertTrue($0 is MediaError) }
    }

    func testRow10_propertySet_volume() throws {
        try facade.set("volume", value: .number(80))
        assertOnlyCall(.set, "volume", [.number(80)])
        XCTAssertThrowsError(try facade.set("volume", value: .bool(true))) { XCTAssertTrue($0 is MediaError) }
    }

    func testRow11_propertySet_sid() throws {
        try facade.set("sid", value: .number(2))
        try facade.set("sid", value: .text("auto"))
        try facade.set("sid", value: .text("no"))
        XCTAssertEqual(engine.calls.map(\.arguments), [[.number(2)], [.text("auto")], [.text("no")]])
        XCTAssertThrowsError(try facade.set("sid", value: .bool(true))) {
            guard case .invalidValueType = ($0 as? MediaError) else { return XCTFail("expected invalidValueType, got \($0)") }
        }
        XCTAssertEqual(engine.calls.count, 3)
    }

    // MARK: property-mutate rows (facade get/set contract)

    private func assertMutateBoolean(_ property: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(try facade.get(property), .none, file: file, line: line)
        try? facade.set(property, value: .bool(true))
        XCTAssertEqual(try facade.get(property), .bool(true), file: file, line: line)
        try? facade.set(property, value: .bool(false))
        XCTAssertEqual(try facade.get(property), .bool(false), file: file, line: line)
        XCTAssertThrowsError(try facade.set(property, value: .number(1)), file: file, line: line) { XCTAssertTrue($0 is MediaError, file: file, line: line) }
    }

    func testRow12_propertyMutate_pause() { assertMutateBoolean("pause") }
    func testRow13_propertyMutate_mute() { assertMutateBoolean("mute") }

    func testRow14_propertyMutate_speed() throws {
        try facade.set("speed", value: .number(0.5))
        XCTAssertEqual(try facade.get("speed"), .number(0.5))
        XCTAssertThrowsError(try facade.set("speed", value: .text("2"))) { XCTAssertTrue($0 is MediaError) }
    }

    func testRow15_propertyMutate_volume() throws {
        try facade.set("volume", value: .number(55))
        XCTAssertEqual(try facade.get("volume"), .number(55))
    }

    func testRow16_propertyMutate_audio() throws {
        try facade.set("audio", value: .number(1))
        XCTAssertEqual(try facade.get("audio"), .number(1))
        try facade.set("audio", value: .text("auto"))
        XCTAssertEqual(try facade.get("audio"), .text("auto"))
        XCTAssertThrowsError(try facade.set("audio", value: .bool(false))) { XCTAssertTrue($0 is MediaError) }
    }

    func testRow17_propertyMutate_sub() throws {
        try facade.set("sub", value: .text("no"))
        XCTAssertEqual(try facade.get("sub"), .text("no"))
        try facade.set("sub", value: .number(0))
        XCTAssertEqual(try facade.get("sub"), .number(0))
    }

    // MARK: property-observe rows (registration, callback, removal)

    // Client-settable observables (a property-set/-mutate row exists): change driven via facade.set.
    private func assertObserve(_ property: String, value: MediaValue, file: StaticString = #filePath, line: UInt = #line) {
        var received: [MediaValue] = []
        do { try facade.observe(property, token: 100) { received.append($0) } } catch { XCTFail("observe threw: \(error)", file: file, line: line); return }
        try? facade.set(property, value: value)
        XCTAssertEqual(received, [value], file: file, line: line)
        facade.unobserve(token: 100)
        try? facade.set(property, value: .none)
        XCTAssertEqual(received, [value], "no callback after unobserve", file: file, line: line)
    }

    // Read-only observables (property-get + property-observe rows only): change driven by an
    // engine-originated change; facade.set is correctly rejected for these names.
    private func assertObserveSimulated(_ property: String, value: MediaValue, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try facade.set(property, value: value), "no set row for \(property): facade.set must be rejected", file: file, line: line) {
            XCTAssertEqual($0 as? MediaError, .unsupportedProperty(property), file: file, line: line)
        }
        var received: [MediaValue] = []
        do { try facade.observe(property, token: 100) { received.append($0) } } catch { XCTFail("observe threw: \(error)", file: file, line: line); return }
        engine.simulateChange(property, value: value)
        XCTAssertEqual(received, [value], file: file, line: line)
        facade.unobserve(token: 100)
        engine.simulateChange(property, value: .none)
        XCTAssertEqual(received, [value], "no callback after unobserve", file: file, line: line)
    }

    func testRow18_propertyObserve_pause() { assertObserve("pause", value: .bool(true)) }

    func testRow19_propertyObserve_timePos() {
        assertObserveSimulated("time-pos", value: .number(12.5))
        // unavailable (.none) is a deliverable notification, not an error
        var received: [MediaValue] = []
        try? facade.observe("time-pos", token: 200) { received.append($0) }
        engine.simulateChange("time-pos", value: .none)
        XCTAssertEqual(received, [.none])
    }

    func testRow20_propertyObserve_duration() { assertObserveSimulated("duration", value: .number(2.0)) }
    func testRow21_propertyObserve_mute() { assertObserve("mute", value: .bool(false)) }
    func testRow22_propertyObserve_volume() { assertObserve("volume", value: .number(90)) }

    // MARK: names outside the approved set

    // MARK: - Posted typed domains (strict TSV domain vs engine-level policy)

    // number(0.01..100): explicit posted bounds on speed (rows 9 and 14) - enforced.
    private func assertSpeedBounds(_ set: (MediaValue) throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try set(.number(0.01)), file: file, line: line)
        XCTAssertNoThrow(try set(.number(100)), file: file, line: line)
        for bad: MediaValue in [.number(0.005), .number(0.0099), .number(100.01), .number(100.5), .number(0), .number(.nan), .number(.infinity), .text("fast")] {
            XCTAssertThrowsError(try set(bad), file: file, line: line) {
                XCTAssertEqual($0 as? MediaError, .invalidValueType(property: "speed", expected: "number(0.01..100)"), file: file, line: line)
            }
        }
    }

    func testDomain_speedSetBounds() { assertSpeedBounds { try facade.set("speed", value: $0) } }
    func testDomain_speedMutateBounds() {
        assertSpeedBounds { newValue in
            try facade.set("speed", value: newValue) // mutate row uses the same get/set contract
        }
    }

    // number(percent): "percent" is a unit annotation with no posted bounds - the facade
    // enforces the numeric type only and does not invent a 0..100 range (documented).
    func testDomain_volumePercentIsUnitNotRange() throws {
        try facade.set("volume", value: .number(-5))
        try facade.set("volume", value: .number(1000))
        XCTAssertThrowsError(try facade.set("volume", value: .text("loud"))) {
            XCTAssertEqual($0 as? MediaError, .invalidValueType(property: "volume", expected: "number(percent)"))
        }
    }

    // integer|string(auto|no): explicit posted string enum on sid / audio / sub - enforced.
    private func assertIntegerOrEnum(_ property: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try facade.set(property, value: .number(2)), file: file, line: line)
        XCTAssertNoThrow(try facade.set(property, value: .number(-3)), file: file, line: line)
        XCTAssertNoThrow(try facade.set(property, value: .number(0)), file: file, line: line)
        XCTAssertNoThrow(try facade.set(property, value: .text("auto")), file: file, line: line)
        XCTAssertNoThrow(try facade.set(property, value: .text("no")), file: file, line: line)
        // The integer branch means finite integral: fractions and non-finite are rejected.
        for bad: MediaValue in [.number(1.5), .number(-0.5), .number(.nan), .number(.infinity), .number(-.infinity), .text("bogus"), .text("AUTO"), .bool(true)] {
            XCTAssertThrowsError(try facade.set(property, value: bad), "\(property) must reject \(bad)", file: file, line: line) {
                XCTAssertEqual($0 as? MediaError, .invalidValueType(property: property, expected: "integer|string(auto|no)"), file: file, line: line)
            }
        }
    }

    func testDomain_sidEnum() { assertIntegerOrEnum("sid") }
    func testDomain_audioEnum() { assertIntegerOrEnum("audio") }
    func testDomain_subEnum() { assertIntegerOrEnum("sub") }

    // Rejected values must never reach the engine.
    func testDomain_loadfileIntegerIndex() throws {
        try facade.command("loadfile", arguments: [.text("clip.mp4"), .text("replace"), .number(2)])
        for bad: MediaValue in [.number(0.5), .number(1.5), .number(.nan), .number(.infinity), .text("2")] {
            XCTAssertThrowsError(try facade.command("loadfile", arguments: [.text("clip.mp4"), .text("replace"), bad])) {
                XCTAssertEqual(($0 as? MediaError)?.isInvalidArguments, true)
            }
        }
    }

    // Unspecified posted semantics, labeled not assumed: plain "number" tokens are
    // type-only, so NaN/infinity pass on unconstrained numbers (seek target).
    func testDomain_plainNumberFinitenessUnspecified() throws {
        try facade.command("seek", arguments: [.number(.nan)])
        try facade.command("seek", arguments: [.number(.infinity)])
        // Ranged tokens reject non-finite implicitly (comparisons fail).
        XCTAssertThrowsError(try facade.set("speed", value: .number(.nan)))
        XCTAssertThrowsError(try facade.set("speed", value: .number(.infinity)))
    }

    func testDomain_rejectedValuesDoNotReachEngine() {
        let before = engine.calls.count
        try? facade.set("sid", value: .text("bogus"))
        try? facade.set("speed", value: .number(1000))
        XCTAssertEqual(engine.calls.count, before)
    }

    func testUnapprovedNamesThrowWithRowsInstalled() {
        XCTAssertThrowsError(try facade.command("screenshot", arguments: [])) {
            XCTAssertEqual($0 as? MediaError, .unsupportedCommand("screenshot"))
        }
        XCTAssertThrowsError(try facade.get("aid")) { XCTAssertEqual($0 as? MediaError, .unsupportedProperty("aid")) }
        XCTAssertThrowsError(try facade.set("brightness", value: .number(1))) { XCTAssertTrue($0 is MediaError) }
        XCTAssertThrowsError(try facade.observe("speed", token: 1) { _ in }) {
            XCTAssertEqual($0 as? MediaError, .unsupportedProperty("speed"))
        }
    }
}
