import XCTest
@testable import MediaFacadeKit

/// P-B1 mechanics tests: forwarding, failure behavior, fixture sequence, row-table
/// validation path (schema-shaped synthetic example-* rows only - the approved rows
/// are covered row-by-row in E1RowTests).
final class FacadeContractTests: XCTestCase {

    // MARK: forwarding mechanics

    func testCommandForwardsExactNameAndTypedArguments() throws {
        let engine = FakeEngine()
        let facade = Facade(engine: engine)
        let result = try facade.command("loadfile", arguments: [.text("a1-v24.mp4"), .number(0)])
        XCTAssertEqual(result, .none)
        XCTAssertEqual(engine.calls.count, 1)
        XCTAssertEqual(engine.calls[0].op, .command)
        XCTAssertEqual(engine.calls[0].name, "loadfile")
        XCTAssertEqual(engine.calls[0].arguments, [.text("a1-v24.mp4"), .number(0)])
    }

    func testGetAndSetPropertyForwarding() throws {
        let engine = FakeEngine(initialProperties: ["pause": .bool(true)])
        let facade = Facade(engine: engine)
        XCTAssertEqual(try facade.get("pause"), .bool(true))
        try facade.set("pause", value: .bool(false))
        XCTAssertEqual(try facade.get("pause"), .bool(false))
        XCTAssertEqual(engine.calls.map(\.op), [.get, .set, .get])
        XCTAssertEqual(engine.calls[1].name, "pause")
        XCTAssertEqual(engine.calls[1].arguments, [.bool(false)])
    }

    func testObserverRegistrationCallbackAndRemoval() throws {
        let engine = FakeEngine()
        let facade = Facade(engine: engine)
        var received: [MediaValue] = []
        try facade.observe("pause", token: 42) { received.append($0) }
        try facade.set("pause", value: .bool(true))
        XCTAssertEqual(received, [.bool(true)])
        facade.unobserve(token: 42)
        try facade.set("pause", value: .bool(false))
        XCTAssertEqual(received, [.bool(true)], "no callback after unobserve")
        XCTAssertEqual(engine.calls.map(\.op), [.observe, .set, .unobserve, .set])
    }

    // MARK: failure behavior: unsupported names throw, no silent success

    func testUnsupportedCommandThrowsThroughFacadeAndEngine() {
        let engine = FakeEngine()
        let facade = Facade(engine: engine)
        XCTAssertThrowsError(try facade.command("definitely-not-a-command", arguments: [])) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedCommand("definitely-not-a-command"))
        }
        XCTAssertThrowsError(try facade.get("no-such-property")) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("no-such-property"))
        }
        XCTAssertThrowsError(try facade.set("no-such-property", value: .none)) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("no-such-property"))
        }
    }

    func testScriptedErrorSequenceSurfaces() {
        let engine = FakeEngine()
        engine.scriptError("command:seek", .engineFailure("simulated seek failure"))
        let facade = Facade(engine: engine)
        XCTAssertThrowsError(try facade.command("seek", arguments: [.number(10)])) { error in
            XCTAssertEqual(error as? MediaError, .engineFailure("simulated seek failure"))
        }
    }

    // MARK: row-table validation (schema-shaped synthetic rows, NOT approved E1 rows)

    private func syntheticRowTable() throws -> RowTable {
        try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        command\texample-do\texecute\ttextval:string;count?:number\tcommand-result-or-error\tE1-example
        property-get\texample-readable\tread\tnone\tnumber\tE1-example
        property-mutate\texample-prop\tread-write\tvalue:boolean\tboolean\tE1-example
        """)
    }

    func testInstalledRowsGateNamesTypesAndAccess() throws {
        // PassthroughEngine has an open vocabulary so the row table alone gates names/types/access.
        let wide = PassthroughEngine(initialProperties: ["example-prop": .bool(false), "example-readable": .number(3)])
        let facade = Facade(engine: wide, rows: try syntheticRowTable())

        // exact typed forwarding passes (required only, and required + optional)
        _ = try facade.command("example-do", arguments: [.text("x")])
        XCTAssertEqual(wide.calls.last?.name, "example-do")
        _ = try facade.command("example-do", arguments: [.text("x"), .number(1)])
        XCTAssertEqual(wide.calls.last?.arguments, [.text("x"), .number(1)])

        // missing required, wrong type, and surplus arguments rejected before the engine
        let before = wide.calls.count
        XCTAssertThrowsError(try facade.command("example-do", arguments: [])) { error in
            guard case .invalidArguments = (error as? MediaError) else { return XCTFail("expected invalidArguments, got \(error)") }
        }
        XCTAssertThrowsError(try facade.command("example-do", arguments: [.number(1)])) { error in
            guard case .invalidArguments = (error as? MediaError) else { return XCTFail("expected invalidArguments, got \(error)") }
        }
        XCTAssertThrowsError(try facade.command("example-do", arguments: [.text("x"), .number(1), .text("surplus")])) { error in
            guard case .invalidArguments = (error as? MediaError) else { return XCTFail("expected invalidArguments, got \(error)") }
        }
        XCTAssertEqual(wide.calls.count, before, "rejected calls must not reach the engine")

        // name outside the installed table rejected
        XCTAssertThrowsError(try facade.command("other", arguments: [])) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedCommand("other"))
        }
        XCTAssertThrowsError(try facade.get("other")) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("other"))
        }

        // value type and access enforced: property-mutate accepts bool, rejects text;
        // property-get-only name rejects set outright
        XCTAssertThrowsError(try facade.set("example-prop", value: .text("no"))) { error in
            guard case .invalidValueType = (error as? MediaError) else { return XCTFail("expected invalidValueType, got \(error)") }
        }
        XCTAssertThrowsError(try facade.set("example-readable", value: .number(4))) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("example-readable"))
        }
        try facade.set("example-prop", value: .bool(true))
        XCTAssertEqual(try facade.get("example-prop"), .bool(true))
    }

    // MARK: observe gating with installed rows (schema-only synthetic rows)

    private func observeRowTable() throws -> RowTable {
        try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        property-get\texample-readable\tread\tnone\tnumber\tE1-example
        property-set\texample-writeonly\twrite\tvalue:boolean\tboolean\tE1-example
        property-observe\texample-explicit\tobserve\ttoken:uint64;callback(value)\tnumber-or-unavailable\tE1-example
        """)
    }

    func testObserveGatingWithInstalledRows() throws {
        let wide = PassthroughEngine(initialProperties: [:])
        let facade = Facade(engine: wide, rows: try observeRowTable())
        // explicit property-observe row: permitted
        XCTAssertNoThrow(try facade.observe("example-explicit", token: 1) { _ in })
        // a property without a property-observe row is NOT observable, readable or not
        XCTAssertThrowsError(try facade.observe("example-readable", token: 2) { _ in }) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("example-readable"))
        }
        XCTAssertThrowsError(try facade.observe("example-writeonly", token: 3) { _ in }) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("example-writeonly"))
        }
        XCTAssertThrowsError(try facade.observe("example-absent", token: 4) { _ in }) { error in
            XCTAssertEqual(error as? MediaError, .unsupportedProperty("example-absent"))
        }
        XCTAssertEqual(wide.calls.filter { $0.op == "observe" }.count, 1, "only the permitted observation reaches the engine")
    }

    func testUnobserveUnknownTokenIsRecordedNoOp() {
        let engine = FakeEngine()
        let facade = Facade(engine: engine)
        facade.unobserve(token: 999) // never observed: must not throw, crash, or remove anything
        var fired = false
        try? facade.observe("pause", token: 7) { _ in fired = true }
        facade.unobserve(token: 999) // still unknown; token 7 must survive
        try? facade.set("pause", value: .bool(true))
        XCTAssertTrue(fired, "an unobserve of an unknown token must not disturb live observers")
        XCTAssertTrue(engine.calls.contains { $0.op == .unobserve })
    }

    // MARK: generated fixture sequence (empty/load/playback/error)

    private struct EventsFixture: Decodable {
        struct Step: Decodable {
            let step: String
            let action: String
            let name: String?
            let property: String?
            let arguments: [MediaValue]?
            let value: MediaValue?
            let seedProperty: MediaValue?
            struct Expect: Decodable {
                let returns: MediaValue?
                let `throws`: String?
            }
            let expect: Expect
        }
        let sequence: [Step]
    }

    func testFakeEngineEventsFixtureSequence() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: RowTableTests.fixtureURL("fake-engine-events.json").path))
        let fixture = try JSONDecoder().decode(EventsFixture.self, from: data)
        XCTAssertEqual(fixture.sequence.map(\.step), ["empty", "load", "playback", "playback", "error"])

        let engine = FakeEngine()
        let facade = Facade(engine: engine)
        for step in fixture.sequence {
            if let seed = step.seedProperty, let property = step.property {
                try facade.set(property, value: seed)
            }
            switch (step.action, step.expect.`throws`) {
            case ("get", .none):
                XCTAssertEqual(try facade.get(step.property!), step.expect.returns, "step \(step.step)")
            case ("set", .none):
                try facade.set(step.property!, value: step.value!)
            case ("command", .none):
                XCTAssertEqual(try facade.command(step.name!, arguments: step.arguments ?? []), step.expect.returns, "step \(step.step)")
            case ("command", .some(let expectedError)):
                // The fixture's error leg scripts a named engine failure; the assert is that it
                // surfaces through the facade unchanged rather than being swallowed.
                let prefix = "engineFailure: "
                guard expectedError.hasPrefix(prefix) else { return XCTFail("step \(step.step): unknown scripted error '\(expectedError)'") }
                engine.scriptError("command:\(step.name!)", .engineFailure(String(expectedError.dropFirst(prefix.count))))
                XCTAssertThrowsError(try facade.command(step.name!, arguments: step.arguments ?? []), "step \(step.step)") { error in
                    guard case .engineFailure(let message) = (error as? MediaError) else {
                        return XCTFail("step \(step.step): expected engineFailure, got \(error)")
                    }
                    XCTAssertEqual("engineFailure: \(message)", expectedError)
                }
            default:
                XCTFail("step \(step.step): unsupported fixture action \(step.action)")
            }
        }
        XCTAssertEqual(engine.calls.first?.op, .get, "sequence opens on the empty state")
        XCTAssertEqual(engine.calls.last?.name, "seek", "sequence ends on the error leg")
    }

    // MARK: approved rows guard

    /// The approved E1 row set landed (facade-rows.tsv, bridge commit 0fe957be). This
    /// guard keeps the fixture present, schema-valid and complete; the per-row proofs
    /// live in E1RowTests.
    func testApprovedE1RowsPresentSchemaValidAndComplete() throws {
        let tsv = try RowTableTests.fixtureText("facade-rows.tsv")
        XCTAssertTrue(tsv.hasPrefix(RowTable.header + "\n"), "fixture must carry the exact posted header")
        let table = try RowTable.parse(tsv: tsv)
        XCTAssertEqual(table.rows.count, 22, "the posted approved set has 22 rows")
    }
}

/// Engine shim with an open vocabulary for row-validation tests (every name known).
private final class PassthroughEngine: MediaEngine {
    struct Call { var op: String; var name: String; var arguments: [MediaValue] }
    private(set) var calls: [Call] = []
    private var properties: [String: MediaValue]
    init(initialProperties: [String: MediaValue]) { self.properties = initialProperties }
    func command(_ name: String, arguments: [MediaValue]) throws -> MediaValue {
        calls.append(Call(op: "command", name: name, arguments: arguments)); return .none
    }
    func get(_ property: String) throws -> MediaValue {
        calls.append(Call(op: "get", name: property, arguments: [])); return properties[property] ?? .none
    }
    func set(_ property: String, value: MediaValue) throws {
        calls.append(Call(op: "set", name: property, arguments: [value])); properties[property] = value
    }
    func observe(_ property: String, token: UInt64, callback: @escaping (MediaValue) -> Void) throws {
        calls.append(Call(op: "observe", name: property, arguments: []))
    }
    func unobserve(token: UInt64) { calls.append(Call(op: "unobserve", name: "", arguments: [])) }
}
