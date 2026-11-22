import XCTest
@testable import BridgeVTDecode
import BridgeDemux

/// P-A5 E2/E4: VT decoder wrapper tests.
///
/// What is asserted where (labeled, per packet):
///  - This package owns (owner split, P-A5 two workers): the protocol
///    surface (FrameDecoder/DecodedFrame/DecoderError), SoftwareStubDecoder,
///    PixelDigest, the fixtures/oracles, the demux->decoder pipeline tests
///    and the digest assertions. VTFrameDecoder, the avcC/hvcC extraction
///    helper and the .missingConfiguration refusal are the sibling worker's
///    package; the shared protocol surface was passed to them verbatim.
///  - This host (Linux): typed stub refusal everywhere, demux->decoder
///    pipeline boundary, fixtures vs ffprobe packet/frame oracles (exact
///    rationals), reorder grounding, digest-function determinism. No
///    native decode is claimed or counted.
final class VTDecodeTests: XCTestCase {

    private let fixtures: [(name: String, codec: String)] = [
        ("a5-h264-24fps.mp4", "h264"),
        ("a5-hevc-24fps.mp4", "hevc"),
        ("a5-h264-bframes.mp4", "h264"),
    ]

    // MARK: - fixture/oracle loading

    private func fixtureBytes(_ name: String) -> [UInt8] {
        [UInt8](try! Data(contentsOf: url(name)))
    }

    private func url(_ name: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    private func oracle(_ name: String) -> [String: Any] {
        let d = try! Data(contentsOf: url(name))
        return try! JSONSerialization.jsonObject(with: d) as! [String: Any]
    }

    /// (num, den) from ffprobe "1/12288" style time_base.
    private func timeBase(_ stream: [String: Any]) -> Int64 {
        let tb = stream["time_base"] as! String
        return Int64(tb.split(separator: "/")[1])!
    }

    private func eqRational(_ v1: Int64, _ s1: Int64, _ rt: RationalTime?, _ ctx: String) {
        guard let rt else { XCTFail("\(ctx): nil timestamp, want \(v1)/\(s1)"); return }
        XCTAssertEqual(rt.value * s1, v1 * rt.scale, ctx)
    }

    // MARK: - 1. Software stub: typed refusal everywhere

    func testStubThrowsUnsupportedBackendEverywhere() throws {
        for codec in ["h264", "hevc", "vp9", "av1", ""] {
            var d = SoftwareStubDecoder()
            do {
                try d.open(codec: codec)
                XCTFail("stub open(\(codec)) succeeded")
            } catch let e as DecoderError {
                guard case .unsupportedBackend = e else {
                    return XCTFail("stub open(\(codec)): \(e), want .unsupportedBackend")
                }
            }
        }
        // decode/flush also refuse - on a fresh stub and after failed open.
        var d = SoftwareStubDecoder()
        XCTAssertThrowsError(try d.decode(DemuxPacket(trackID: 0, pts: nil, dts: nil, duration: nil, bytes: [0]))) {
            guard case DecoderError.unsupportedBackend = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try d.flush()) {
            guard case DecoderError.unsupportedBackend = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: - 2. Fixtures: demux side matches the ffprobe packet oracle exactly

    func testDemuxFixturesMatchPacketOracle() throws {
        for f in fixtures {
            let o = oracle(f.name + ".ffprobe.json")
            let streams = o["streams"] as! [[String: Any]]
            XCTAssertEqual(streams.count, 1, f.name)
            XCTAssertEqual(streams[0]["codec_name"] as? String, f.codec, f.name)
            let scale = timeBase(streams[0])
            let op = (o["packets"] as! [[String: Any]]).filter { ($0["stream_index"] as! Int) == 0 }

            var d = Demuxer()
            let tracks = try d.open(fixtureBytes(f.name))
            XCTAssertEqual(tracks.count, 1, f.name)
            XCTAssertEqual(tracks[0].kind, "video", f.name)
            XCTAssertEqual(tracks[0].codec, f.codec, f.name)
            var packets: [DemuxPacket] = []
            while let p = try d.next() { packets.append(p) }
            XCTAssertEqual(packets.count, op.count, "\(f.name): packet count vs oracle")
            for (i, (p, q)) in zip(packets, op).enumerated() {
                let ctx = "\(f.name) packet \(i)"
                eqRational(Int64(q["pts"] as! Int), scale, p.pts, ctx + " pts")
                eqRational(Int64(q["dts"] as! Int), scale, p.dts, ctx + " dts")
                eqRational(Int64(q["duration"] as! Int), scale, p.duration, ctx + " duration")
            }
        }
    }

    // MARK: - 3. Frame oracle: count/size/presentation pts; reorder grounding

    func testFrameOracleAndReorderGrounding() throws {
        for f in fixtures {
            let fo = oracle(f.name + ".ffprobe-frames.json")
            let frames = fo["frames"] as! [[String: Any]]
            XCTAssertEqual(frames.count, 48, f.name)  // 2 s at 24 fps, oracle-verified
            for (i, fr) in frames.enumerated() {
                XCTAssertEqual(fr["width"] as? Int, 64, "\(f.name) frame \(i)")
                XCTAssertEqual(fr["height"] as? Int, 64, "\(f.name) frame \(i)")
            }
            // Presentation order is monotonic.
            let pts = frames.map { $0["best_effort_timestamp"] as! Int }
            XCTAssertEqual(pts, pts.sorted(), "\(f.name): frames not in presentation order")

            // Presentation-order pts sequence must equal the SORTED demux
            // packet pts sequence as exact rationals (decoder input/output
            // relationship, checked without a decoder).
            var d = Demuxer()
            _ = try d.open(fixtureBytes(f.name))
            var packetPts: [(v: Int64, s: Int64)] = []
            while let p = try d.next() {
                if let r = p.pts { packetPts.append((r.value, r.scale)) }
            }
            let scale = timeBase((oracle(f.name + ".ffprobe.json")["streams"] as! [[String: Any]])[0])
            // Sort packet pts as exact rationals (cross-multiplied compare).
            let sortedPackets = packetPts.sorted { $0.v * $1.s < $1.v * $0.s }
            XCTAssertEqual(sortedPackets.count, pts.count, f.name)
            for (i, sp) in sortedPackets.enumerated() {
                XCTAssertEqual(sp.v * scale, Int64(pts[i]) * sp.s,
                               "\(f.name): presentation pts \(i) mismatch")
            }
            // The reorder fixtures must genuinely reorder (decode-order pts
            // is NOT already sorted); otherwise the reorder assert is void.
            if f.name != "a5-h264-24fps.mp4" {
                let inOrder = packetPts.enumerated().allSatisfy { i, e in
                    i == 0 || packetPts[i - 1].v * e.s <= e.v * packetPts[i - 1].s
                }
                XCTAssertFalse(inOrder, "\(f.name): fixture does not exercise reorder")
            }
        }
    }

    // MARK: - 4. Pipeline boundary: every demuxed packet hits the typed refusal

    func testPipelineReachesDecoderBoundaryWithTypedRefusal() throws {
        for f in fixtures {
            var demux = Demuxer()
            _ = try demux.open(fixtureBytes(f.name))
            var fed = 0
            var dec: SoftwareStubDecoder? = SoftwareStubDecoder()
            XCTAssertThrowsError(try dec!.open(codec: f.codec)) {
                guard case DecoderError.unsupportedBackend = $0 else { return XCTFail("\($0)") }
            }
            while let p = try demux.next() {
                fed += 1
                XCTAssertThrowsError(try dec!.decode(p), "\(f.name) packet \(fed)") {
                    guard case DecoderError.unsupportedBackend = $0 else { return XCTFail("\($0)") }
                }
            }
            XCTAssertEqual(fed, 48, f.name)
            XCTAssertThrowsError(try dec!.flush()) {
                guard case DecoderError.unsupportedBackend = $0 else { return XCTFail("\($0)") }
            }
            dec = nil
        }
    }

    // MARK: - 5. Digest function determinism

    func testPixelDigestDeterminism() {
        // sha256("") and sha256("abc") golden values.
        XCTAssertEqual(PixelDigest.hex([]),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(PixelDigest.hex(Array("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let frame = [UInt8](repeating: 0x5A, count: 64 * 64 * 3 / 2)
        let a = PixelDigest.hex(frame)
        let b = PixelDigest.hex(frame)
        XCTAssertEqual(a, b, "digest must be stable across two computations")
        XCTAssertEqual(a.count, 64)
    }


}
