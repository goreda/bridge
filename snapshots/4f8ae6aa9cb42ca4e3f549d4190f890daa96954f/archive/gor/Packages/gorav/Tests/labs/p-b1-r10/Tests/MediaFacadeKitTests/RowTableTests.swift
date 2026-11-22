import XCTest
@testable import MediaFacadeKit

/// Schema tests for the approved E1 TSV as actually posted (kind,name,access,
/// argument_types,value_type,e_step) at bridge commit 0fe957be (INBOX-IN2TINCT.md).
final class RowTableTests: XCTestCase {

    func testApprovedFixtureParsesAllRows() throws {
        let tsv = try Self.fixtureText("facade-rows.tsv")
        let table = try RowTable.parse(tsv: tsv)
        // Merged vendored table per fa31ade: 22 E1 + 12 E2 = 34 rows.
        XCTAssertEqual(table.rows.count, 34)
        XCTAssertEqual(table.rows.filter { $0.kind == .command }.count, 7)
        XCTAssertEqual(table.rows.filter { $0.kind == .propertyGet }.count, 8)
        XCTAssertEqual(table.rows.filter { $0.kind == .propertySet }.count, 6)
        XCTAssertEqual(table.rows.filter { $0.kind == .propertyMutate }.count, 7)
        XCTAssertEqual(table.rows.filter { $0.kind == .propertyObserve }.count, 6)
        XCTAssertEqual(table.rows.filter { $0.eStep == "E1" }.count, 22)
        XCTAssertEqual(table.rows.filter { $0.eStep == "E2" }.count, 12)
        let loadfile = table.row(kind: .command, name: "loadfile")
        XCTAssertEqual(loadfile?.arguments, [
            ArgumentSpec(name: "url", type: "string", optional: false, raw: "url:string"),
            ArgumentSpec(name: "flags", type: "string", optional: true, raw: "flags?:string"),
            ArgumentSpec(name: "index", type: "integer", optional: true, raw: "index?:integer"),
            ArgumentSpec(name: "options", type: "object", optional: true, raw: "options?:object"),
        ])
        XCTAssertEqual(table.row(kind: .propertyObserve, name: "pause")?.arguments, [
            ArgumentSpec(name: "token", type: "uint64", optional: false, raw: "token:uint64"),
            ArgumentSpec(name: "callback(value)", type: nil, optional: false, raw: "callback(value)"),
        ])
        XCTAssertEqual(table.row(kind: .propertySet, name: "sid")?.valueType.raw, "integer|string")
        XCTAssertTrue(table.row(kind: .propertyGet, name: "time-pos")?.valueType.allowsUnavailable ?? false)
    }

    static func fixtureURL(_ name: String) -> URL {
        Bundle.module.bundleURL.appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    static func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: fixtureURL(name), encoding: .utf8)
    }

    func testCRLFTerminatedTableParsesLikeLF() throws {
        // Regression: "\r\n" is one Character in Swift, so splitting raw CRLF input on
        // "\n" glued all lines together (reproduced on swift-5.10.1-RELEASE before the fix).
        let lf = "kind\tname\taccess\targument_types\tvalue_type\te_step\ncommand\texample-do\texecute\targ:string\tnone\tE1\nproperty-get\texample-prop\tread\tnone\tboolean\tE1\n"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let fromLF = try RowTable.parse(tsv: lf)
        let fromCRLF = try RowTable.parse(tsv: crlf)
        XCTAssertEqual(fromCRLF, fromLF)
        XCTAssertEqual(fromCRLF.rows.count, 2)
    }

    func testDuplicateKindNameRowRejected() {
        XCTAssertThrowsError(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        property-get\texample-prop\tread\tnone\tboolean\tE1
        property-get\texample-prop\tread\tnone\tnumber\tE1
        """)) { error in
            guard case .rowTableMalformed(let detail) = (error as? MediaError) else { return XCTFail("expected rowTableMalformed, got \(error)") }
            XCTAssertTrue(detail.contains("duplicate (kind,name)"), detail)
        }
        // same name under a different kind is not a duplicate
        XCTAssertNoThrow(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        property-get\texample-prop\tread\tnone\tboolean\tE1
        property-observe\texample-prop\tobserve\ttoken:uint64;callback(value)\tboolean-or-unavailable\tE1
        """))
    }

    func testMissingHeaderThrows() {
        XCTAssertThrowsError(try RowTable.parse(tsv: "command\tx\texecute\tnone\tnone\tE1\n")) { error in
            guard case .rowTableMalformed = (error as? MediaError) else { return XCTFail("expected rowTableMalformed, got \(error)") }
        }
    }

    func testWrongColumnCountThrows() {
        XCTAssertThrowsError(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        command\tonly-three\tcols
        """)) { error in
            guard case .rowTableMalformed(let detail) = (error as? MediaError) else { return XCTFail("expected rowTableMalformed, got \(error)") }
            XCTAssertTrue(detail.contains("6 tab-separated columns"), detail)
        }
    }

    func testUnknownKindAndAccessThrow() {
        XCTAssertThrowsError(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        wat\tx\texecute\tnone\tnone\tE1
        """)) { error in guard case .rowTableMalformed = (error as? MediaError) else { return XCTFail() } }
        XCTAssertThrowsError(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        command\tx\tEXECUTE\tnone\tnone\tE1
        """)) { error in guard case .rowTableMalformed = (error as? MediaError) else { return XCTFail() } }
    }

    func testKindAccessMismatchThrows() {
        XCTAssertThrowsError(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        property-get\tx\twrite\tnone\tboolean\tE1
        """)) { error in
            guard case .rowTableMalformed(let detail) = (error as? MediaError) else { return XCTFail("expected rowTableMalformed, got \(error)") }
            XCTAssertTrue(detail.contains("wrong access"), detail)
        }
    }

    func testBadArgumentSpecThrows() {
        XCTAssertThrowsError(try RowTable.parse(tsv: """
        kind\tname\taccess\targument_types\tvalue_type\te_step
        command\tx\texecute\tnotypehere\tnone\tE1
        """)) { error in guard case .rowTableMalformed = (error as? MediaError) else { return XCTFail() } }
    }

    func testEmptyTableWithHeaderOnlyIsValid() throws {
        let table = try RowTable.parse(tsv: "kind\tname\taccess\targument_types\tvalue_type\te_step\n")
        XCTAssertTrue(table.rows.isEmpty)
    }
    func testSetRowWithoutValueSpecIsMalformed() {
        let tsv = RowTable.header + "\n"
            + "property-set\tvolume\twrite\tnone\tnumber\tE1\n"
        XCTAssertThrowsError(try RowTable.parse(tsv: tsv)) {
            guard case .rowTableMalformed = $0 as? MediaError else {
                return XCTFail("expected rowTableMalformed, got \($0)")
            }
        }
        let tsv2 = RowTable.header + "\n"
            + "property-mutate\tmute\tread-write\tlevel:boolean\tboolean\tE1\n"
        XCTAssertThrowsError(try RowTable.parse(tsv: tsv2)) {
            guard case .rowTableMalformed = $0 as? MediaError else {
                return XCTFail("expected rowTableMalformed, got \($0)")
            }
        }
    }

    /// Byte-pin regression (fa31ade: "the 22 E1 lines are not edited"; the E2 lines
    /// are appended byte-exactly as posted). The merged vendored facade-rows.tsv is
    /// proven to be: the byte-pinned E1 fixture (sha256 eb153202...b8e7) followed by
    /// the byte-pinned E2 block's 12 data lines (block sha256 ce6e3ab8...4354).
    func testMergedFixtureBytePinnedSlices() throws {
        let merged = try Self.fixtureText("facade-rows.tsv")
        let e1 = try Self.fixtureText("facade-rows-e1-pinned.tsv")
        let e2 = try Self.fixtureText("facade-rows-e2-pinned.tsv")
        func lines(_ s: String) -> [String] {
            var parts = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            while parts.last == "" { parts.removeLast() }
            return parts
        }
        let mergedLines = lines(merged)
        let e1Lines = lines(e1)
        let e2Lines = lines(e2)
        XCTAssertEqual(mergedLines.count, 35)
        XCTAssertEqual(Array(mergedLines.prefix(23)), e1Lines, "E1 slice must be byte-identical")
        XCTAssertEqual(Array(mergedLines.suffix(12)), Array(e2Lines.dropFirst()), "E2 data lines must be byte-identical")
        XCTAssertEqual(mergedLines.first, e2Lines.first, "same posted header")
    }

}
