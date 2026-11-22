import XCTest
@testable import BridgeTimeMath

/// P-A4 E2: checked time-math vectors. Every expectation comes from the
/// deterministic CSV fixtures (Python big-int oracle, tools/make_vectors.py),
/// never from the implementation under test. The suite asserts typed
/// results or typed errors for every vector, exact conservation for every
/// split vector, and the presence of the two named regression vectors.
/// `swift test` and `swift test -c release` run the identical vectors;
/// agreement is recorded in TEST-LOG.txt.
final class TimeMathTests: XCTestCase {

    typealias TM = Int64TimeMath

    private func lines(_ name: String) -> [String] {
        let url = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        let text = try! String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map(String.init).filter {
            !$0.hasPrefix("#") && !$0.isEmpty
        }
    }

    private func expectError<T>(_ expected: String, _ body: () throws -> T,
                                _ context: String) {
        do {
            let v = try body()
            XCTFail("\(context): expected \(expected), got value \(v)")
        } catch let e as TimeMathError {
            XCTAssertEqual(e, TimeMathError(raw: expected), context)
        } catch {
            XCTFail("\(context): non-TimeMathError thrown: \(error)")
        }
    }

    // MARK: - rescale vectors

    func testRescaleVectors() {
        var count = 0
        for line in lines("rescale-vectors.csv").dropFirst() {  // header
            let f = line.split(separator: ",").map(String.init)
            XCTAssertEqual(f.count, 4, line)
            let v = Int64(f[0])!, src = Int64(f[1])!, dst = Int64(f[2])!
            let ctx = "rescale(\(v), from: \(src), to: \(dst))"
            if let expected = Int64(f[3]) {
                XCTAssertEqual(try TM.rescale(v, from: src, to: dst), expected, ctx)
            } else {
                expectError(f[3], { try TM.rescale(v, from: src, to: dst) }, ctx)
            }
            count += 1
        }
        XCTAssertGreaterThanOrEqual(count, 40)
    }

    /// The named regression vector must be present and must throw the typed
    /// .overflow at the rounding addition (product fits).
    func testNamedRescaleRegressionVector() throws {
        let v: Int64 = 4611686018427387903
        let (product, mulOf) = v.multipliedReportingOverflow(by: 2)
        XCTAssertFalse(mulOf)
        XCTAssertEqual(product, 9223372036854775806)
        XCTAssertThrowsError(try TM.rescale(v, from: 4, to: 2)) {
            XCTAssertEqual($0 as? TimeMathError, .overflow)
        }
        let raw = try String(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/rescale-vectors.csv"), encoding: .utf8)
        XCTAssertTrue(raw.contains("# regression: rescale-overflow-at-rounding-addition"))
        XCTAssertTrue(raw.contains("4611686018427387903,4,2,overflow"))
    }

    // MARK: - split vectors

    func testSplitVectors() {
        var count = 0
        for line in lines("split-vectors.csv").dropFirst() {
            let f = line.split(separator: ",").map(String.init)
            XCTAssertEqual(f.count, 3, line)
            let total = Int64(f[0])!, parts = Int64(f[1])!
            let ctx = "splitDuration(total: \(total), parts: \(parts))"
            if f[2] == "nonPositiveParts" || f[2] == "overflow" {
                expectError(f[2], { try TM.splitDuration(total: total, parts: parts) }, ctx)
                continue
            }
            let expected = f[2].split(separator: ";").map { Int64($0)! }
            let got = (try? TM.splitDuration(total: total, parts: parts)) ?? []
            XCTAssertEqual(got, expected, ctx)
            // Conservation: exact sum for every vector.
            var sum: Int64 = 0
            for s in got {
                let (acc, of) = sum.addingReportingOverflow(s)
                XCTAssertFalse(of, "\(ctx): share sum overflowed")
                sum = acc
            }
            XCTAssertEqual(sum, total, "\(ctx): shares do not sum to total")
            // Each share is floor or floor+1 of the equal share.
            if !got.isEmpty {
                let lo = got.min()!, hi = got.max()!
                XCTAssertTrue(hi == lo || hi == lo + 1, "\(ctx): shares not floor/floor+1")
            }
            count += 1
        }
        XCTAssertGreaterThanOrEqual(count, 15)
    }

    /// The named regression vector: Int64.max into 3 exact-sum shares.
    func testNamedSplitRegressionVector() throws {
        let shares = try TM.splitDuration(total: Int64.max, parts: 3)
        XCTAssertEqual(shares, [3074457345618258603, 3074457345618258602, 3074457345618258602])
        var sum: Int64 = 0
        for s in shares {
            let (acc, of) = sum.addingReportingOverflow(s)
            XCTAssertFalse(of)
            sum = acc
        }
        XCTAssertEqual(sum, Int64.max)
        let raw = try String(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/split-vectors.csv"), encoding: .utf8)
        XCTAssertTrue(raw.contains("# regression: split-int64max-3-parts"))
        XCTAssertTrue(raw.contains("9223372036854775807,3,3074457345618258603;3074457345618258602;3074457345618258602"))
    }

    // MARK: - add/subtract vectors

    func testAddSubVectors() {
        var count = 0
        for line in lines("addsub-vectors.csv").dropFirst() {
            let f = line.split(separator: ",").map(String.init)
            XCTAssertEqual(f.count, 4, line)
            let a = Int64(f[0])!, b = Int64(f[1])!
            let op = f[2]
            let ctx = "\(a) \(op) \(b)"
            let body = { op == "add" ? try TM.add(a, b) : try TM.subtract(a, b) }
            if let expected = Int64(f[3]) {
                XCTAssertEqual(try body(), expected, ctx)
            } else {
                expectError(f[3], body, ctx)
            }
            count += 1
        }
        XCTAssertGreaterThanOrEqual(count, 18)
    }
}

private extension TimeMathError {
    init?(raw: String) {
        switch raw {
        case "overflow": self = .overflow
        case "nonPositiveScale": self = .nonPositiveScale
        case "nonPositiveParts": self = .nonPositiveParts
        default: return nil
        }
    }
}
