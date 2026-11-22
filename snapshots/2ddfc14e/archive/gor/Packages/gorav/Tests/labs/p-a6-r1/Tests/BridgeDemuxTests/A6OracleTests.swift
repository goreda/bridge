import Foundation
import XCTest
@testable import BridgeDemux

/// No skips or permitted divergences: compares every field in per-track order.
final class A6OracleTests: XCTestCase {
    private func bytes(_ name: String) throws -> [UInt8] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return Array(try Data(contentsOf: url))
    }
    private func compare(_ name: String) throws {
        let oracle = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes(name+".ffprobe.json"))) as? [String: Any])
        let streams = try XCTUnwrap(oracle["streams"] as? [[String: Any]])
        let expected = try XCTUnwrap(oracle["packets"] as? [[String: Any]])
        var demuxer = Demuxer()
        let tracks = try demuxer.open(bytes(name))
        var packets: [DemuxPacket] = []
        while let p = try demuxer.next() { packets.append(p) }
        XCTAssertNil(try demuxer.next())
        var mismatches: [[String: String]] = []
        func check(_ actual: String, _ wanted: String, _ field: String) {
            if actual != wanted { mismatches.append(["fixture": name, "field": field, "actual": actual, "expected": wanted]) }
        }
        check(String(tracks.count), String(streams.count), "trackCount")
        check(String(packets.count), String(expected.count), "totalPacketCount")
        var counts: [[String: Any]] = []
        for s in streams {
            let id = try XCTUnwrap(s["index"] as? NSNumber).intValue
            let t = try XCTUnwrap(tracks.first { $0.id == id })
            check(t.kind, try XCTUnwrap(s["codec_type"] as? String), "track[\(id)].kind")
            check(t.codec, try XCTUnwrap(s["codec_name"] as? String), "track[\(id)].codec")
            let tb = try XCTUnwrap(s["time_base"] as? String).split(separator: "/")
            let numerator = try XCTUnwrap(Int64(tb[0])), denominator = try XCTUnwrap(Int64(tb[1]))
            let wanted = expected.filter { ($0["stream_index"] as? NSNumber)?.intValue == id }
            let actual = packets.filter { $0.trackID == id }
            check(String(actual.count), String(wanted.count), "track[\(id)].packetCount")
            counts.append(["track": id, "codec": t.codec, "actual": actual.count, "expected": wanted.count])
            func rational(_ time: RationalTime?) -> String {
                guard let time = time else { return "nil" }
                // Normalize exact rationals by Euclidean gcd, not floating point.
                var a = time.value, b = time.scale
                while b != 0 { let rem = a % b; a = b; b = rem }
                let g = abs(a)
                return "\(time.value/g)/\(time.scale/g)"
            }
            for (index, pair) in zip(actual, wanted).enumerated() {
                let p = pair.0, e = pair.1
                for (field, value) in [("pts", p.pts), ("dts", p.dts), ("duration", p.duration)] {
                    let expectTime = (e[field] as? NSNumber).map { RationalTime(value: $0.int64Value*numerator, scale: denominator) }
                    check(rational(value), rational(expectTime), "track[\(id)].packet[\(index)].\(field)")
                }
                check(String(p.bytes.count), try XCTUnwrap(e["size"] as? String), "track[\(id)].packet[\(index)].size")
            }
        }
        let report: [String: Any] = ["fixture": name, "tracks": counts,
            "actualPackets": packets.count, "expectedPackets": expected.count,
            "mismatchCount": mismatches.count, "mismatches": mismatches]
        if let dir = ProcessInfo.processInfo.environment["A6_EVIDENCE_DIR"] {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to:
                URL(fileURLWithPath: dir).appendingPathComponent(name+".comparison.json"))
        }
        print("A6 MEASURED \(name) actual=\(packets.count) expected=\(expected.count) mismatches=\(mismatches.count)")
        XCTAssertTrue(mismatches.isEmpty, "\(name): \(mismatches.count) exact mismatches; first=\(String(describing: mismatches.first)); full comparison JSON recorded")
    }
    func testHEVCEAC3ExactOracle() throws { try compare("a6-hevc-eac3.mkv") }
    func testHEVCEAC3NonzeroCodecDelayExactOracle() throws { try compare("a6-hevc-eac3-delay.mkv") }
    func testH264AACExactOracle() throws { try compare("a6-h264-aac.mp4") }
    func testA6EmptyAndTruncatedInputsThrow() throws {
        var demuxer = Demuxer()
        XCTAssertThrowsError(try demuxer.open([])) { XCTAssertEqual($0 as? DemuxError, .emptyInput) }
        for name in ["a6-hevc-eac3.mkv", "a6-h264-aac.mp4", "a6-hevc-eac3-delay.mkv"] {
            let data = try bytes(name)
            for length in [1, 4, 16, data.count/2, data.count-1] {
                XCTAssertThrowsError(try demuxer.open(Array(data.prefix(length))), "\(name) truncated length \(length)") { error in
                    XCTAssertTrue(error is DemuxError, "\(name): unnamed error \(error)")
                }
            }
        }
    }
    func testNonzeroDelaySubtractsFromBothTracksAndPreservesPayload() throws {
        func drain(_ name: String) throws -> [DemuxPacket] {
            var demuxer = Demuxer(); _ = try demuxer.open(bytes(name))
            var out: [DemuxPacket] = []
            while let p = try demuxer.next() { out.append(p) }
            return out
        }
        let original = try drain("a6-hevc-eac3.mkv")
        let delayed = try drain("a6-hevc-eac3-delay.mkv")
        XCTAssertEqual(original.count, delayed.count)
        for (a,b) in zip(original, delayed) {
            XCTAssertEqual(a.bytes, b.bytes)
            XCTAssertEqual(a.trackID, b.trackID)
            XCTAssertEqual(a.duration, b.duration)
            let delay: Int64 = a.trackID == 0 ? 10 : 32
            if let pts = a.pts { XCTAssertEqual(b.pts, RationalTime(value: pts.value-delay, scale: pts.scale)) }
            if let dts = a.dts { XCTAssertEqual(b.dts, RationalTime(value: dts.value-delay, scale: dts.scale)) }
            else { XCTAssertNil(b.dts) }
        }
    }
    func testA6AACPrimingIsNegativeNotZero() throws {
        var demuxer = Demuxer()
        _ = try demuxer.open(bytes("a6-h264-aac.mp4"))
        var first: DemuxPacket?
        while let p = try demuxer.next() { if p.trackID == 1 { first = p; break } }
        XCTAssertEqual(first?.pts, RationalTime(value: -1024, scale: 48000))
        XCTAssertEqual(first?.dts, RationalTime(value: -1024, scale: 48000))
    }
}
