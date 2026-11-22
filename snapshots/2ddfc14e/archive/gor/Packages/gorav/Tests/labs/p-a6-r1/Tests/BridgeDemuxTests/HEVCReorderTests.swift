import XCTest
@testable import BridgeDemux
final class HEVCReorderTests: XCTestCase {
    private func config(depth: Int) -> [UInt8] {
        var bits = Array(repeating: 0, count: 4+3+1+96)
        func ue(_ value: Int) {
            let binary = String(value+1, radix: 2).map { Int(String($0))! }
            bits += Array(repeating: 0, count: binary.count-1)+binary
        }
        ue(0); ue(1); ue(64); ue(64)
        bits.append(0) // no conformance window
        ue(0); ue(0); ue(4)
        bits.append(0) // highest sub-layer only
        ue(depth); ue(depth); ue(0)
        while bits.count % 8 != 0 { bits.append(0) }
        var raw: [UInt8] = []
        for i in stride(from: 0, to: bits.count, by: 8) {
            raw.append(UInt8(bits[i..<i+8].reduce(0) { $0*2+$1 }))
        }
        var escaped: [UInt8] = [], zeros = 0
        for b in raw {
            if zeros >= 2 && b <= 3 { escaped.append(3); zeros = 0 }
            escaped.append(b); zeros = b == 0 ? zeros+1 : 0
        }
        let nal: [UInt8] = [66,1]+escaped
        var header = Array(repeating: UInt8(0), count: 23)
        header[0] = 1; header[22] = 1
        return header+[33,0,1,UInt8(nal.count >> 8),UInt8(nal.count & 255)]+nal
    }
    func testDepthParsedFromSPSNotHardcoded() throws {
        for depth in [0,1,2,4,16] { XCTAssertEqual(try HEVCReorder.depth(hvcc: config(depth: depth)), depth) }
    }
    func testAllTruncatedConfigPrefixesThrowWithoutTrap() {
        let full = config(depth: 2)
        for length in 0..<full.count {
            XCTAssertThrowsError(try HEVCReorder.depth(hvcc: Array(full.prefix(length)))) { XCTAssertTrue($0 is DemuxError) }
        }
    }
    func testOversizeDepthAndMissingSPSThrow() {
        XCTAssertThrowsError(try HEVCReorder.depth(hvcc: config(depth: 17)))
        var empty = Array(repeating: UInt8(0), count: 23); empty[0] = 1
        XCTAssertThrowsError(try HEVCReorder.depth(hvcc: empty))
    }
}
