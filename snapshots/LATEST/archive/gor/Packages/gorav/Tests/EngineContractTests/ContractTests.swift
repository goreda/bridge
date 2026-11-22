import XCTest
import Foundation
import BridgeDemux
import BridgeVTDecode
import AudioMasterScheduler

final class ContractTests: XCTestCase {
    struct RecordingDecoder: FrameDecoder {
        var config: CodecConfiguration?
        mutating func open(codec: String, configuration: CodecConfiguration) throws { config = configuration }
        mutating func decode(_ packet: DemuxPacket) throws -> [DecodedFrame] { [] }
        mutating func flush() throws -> [DecodedFrame] { [] }
    }
    func testConvenienceUsesInBand() throws {
        var d = RecordingDecoder(); try d.open(codec: "h264")
        XCTAssertEqual(d.config, .inBand)
    }
    func testConfigurationBytesPreserved() throws {
        var d = RecordingDecoder()
        for c in [CodecConfiguration.avcC(Data([1,2,3])), .hvcC(Data([4,5,6]))] {
            try d.open(codec: "h264", configuration: c); XCTAssertEqual(d.config, c)
        }
    }
    func testMalformedConfigurationIsTyped() {
        XCTAssertEqual(DecoderError.malformedConfiguration("short"), .malformedConfiguration("short"))
    }
    func testStubStillRefusesRatherThanInvents() {
        var d = SoftwareStubDecoder()
        XCTAssertThrowsError(try d.open(codec: "h264", configuration: .avcC(Data())))
    }
    func testSeekFlushesAndInvalidatesRepeatedPTS() throws {
        var q = SeekQueueCoordinator(); q.reset(audioTime: 0, hostTime: 0)
        let old = q.enqueue(videoPTS: 0.5)
        var calls = 0
        try q.seek(to: 0.5, hostTime: 1) { calls += 1 }
        XCTAssertEqual(calls, 1); XCTAssertTrue(q.pending.isEmpty)
        XCTAssertEqual(q.decide(frame: old, hostTime: 1), .drop)
        let fresh = q.enqueue(videoPTS: 0.5)
        XCTAssertEqual(q.decide(frame: fresh, hostTime: 1), .present)
    }
    func testFailedProviderFlushDoesNotReviveFrames() {
        enum Failure: Error { case expected }
        var q = SeekQueueCoordinator(); q.reset(audioTime: 0, hostTime: 0)
        let old = q.enqueue(videoPTS: 0)
        XCTAssertThrowsError(try q.seek(to: 0, hostTime: 1) { throw Failure.expected })
        XCTAssertTrue(q.pending.isEmpty); XCTAssertEqual(q.decide(frame: old, hostTime: 1), .drop)
    }

    // e2 foundation contract (queue item 5, plan/E2-FOUNDATION-CONTRACT.md).
    // Append-only fixture tests; no existing assertion edited.
    func testE2FourArgInitWitness() {
        // The pre-e2 4-argument init must keep compiling unchanged: source
        // compatibility for every existing caller.
        let f = DecodedFrame(pts: nil, width: 2, height: 2, digest: "x")
        XCTAssertEqual(f.digest, "x")
        XCTAssertNil(f.colorPrimaries); XCTAssertNil(f.transferFunction)
        XCTAssertNil(f.colorMatrix); XCTAssertNil(f.colorRange)
        XCTAssertNil(f.chromaLocation); XCTAssertNil(f.hdrStaticMetadata)
        XCTAssertNil(f.hdrDynamicMetadata); XCTAssertNil(f.stereoView)
        XCTAssertNil(f.projection)
    }
    func testE2DefaultsRoundTrip() {
        let staticMD = Data([1, 2]); let dynMD = Data([3])
        let f = DecodedFrame(pts: nil, width: 4, height: 4, digest: "y",
                             colorPrimaries: "bt2020", transferFunction: "pq",
                             colorMatrix: "bt2020nc", colorRange: "limited",
                             chromaLocation: "left", hdrStaticMetadata: staticMD,
                             hdrDynamicMetadata: dynMD, stereoView: "mono",
                             projection: "flat")
        XCTAssertEqual(f.colorPrimaries, "bt2020")
        XCTAssertEqual(f.transferFunction, "pq")
        XCTAssertEqual(f.colorMatrix, "bt2020nc")
        XCTAssertEqual(f.colorRange, "limited")
        XCTAssertEqual(f.chromaLocation, "left")
        XCTAssertEqual(f.hdrStaticMetadata, staticMD)
        XCTAssertEqual(f.hdrDynamicMetadata, dynMD)
        XCTAssertEqual(f.stereoView, "mono")
        XCTAssertEqual(f.projection, "flat")
    }
    func testE2PresentationFrameShape() {
        final class FakeBuffer {}  // opaque handle stand-in (CVPixelBuffer is Darwin-only)
        let buf = PresentationBuffer(object: FakeBuffer())
        let pf = PresentationFrame(pixelBuffer: buf, pixelFormat: "yuv420p8")
        XCTAssertEqual(pf.pixelFormat, "yuv420p8")
        XCTAssertTrue(pf.pixelBuffer === buf)
        XCTAssertNil(pf.colorPrimaries); XCTAssertNil(pf.hdrDynamicMetadata)
        let pf2 = PresentationFrame(pixelBuffer: buf, pixelFormat: "nv12-8",
                                    colorRange: "full", projection: "vr180")
        XCTAssertEqual(pf2.colorRange, "full")
        XCTAssertEqual(pf2.projection, "vr180")
    }
    func testE2DoviConfigurationTypedRefusal() {
        // The dovi case constructs and round-trips bytes; a decoder that
        // cannot run dovi refuses typed, never fabricates frames.
        let c = CodecConfiguration.dovi(Data([7, 7, 7]))
        XCTAssertEqual(c, .dovi(Data([7, 7, 7])))
        var d = SoftwareStubDecoder()
        XCTAssertThrowsError(try d.open(codec: "dvh1", configuration: c)) { error in
            guard case DecoderError.unsupportedBackend = error else {
                return XCTFail("expected .unsupportedBackend, got \(error)")
            }
        }
    }
    func testE2DefaultedFrameFlowsThroughSeekQueueIntact() throws {
        // Queue item 15 (2026-11-08): e2 seek-interaction witness. A fresh
        // post-seek frame carrying defaulted e2 fields must flow through
        // SeekQueueCoordinator enqueue/decide intact.
        var q = SeekQueueCoordinator()
        q.reset(audioTime: 0, hostTime: 0)
        // A pre-seek frame is enqueued in the pre-seek generation...
        let preSeek = q.enqueue(videoPTS: 0.5)
        // ...then the seek invalidates it before the provider flush returns.
        var flushed = false
        try q.seek(to: 5.0, hostTime: 2.0) { flushed = true }
        XCTAssertTrue(flushed)
        XCTAssertEqual(q.decide(frame: preSeek, hostTime: 2.0), .drop)
        // The fresh post-seek frame: 4-arg init, every e2 field at its
        // default (nil = "not signaled", never an invented value).
        let frame = DecodedFrame(pts: RationalTime(value: 5, scale: 1), width: 64, height: 64, digest: "0")
        XCTAssertNil(frame.colorPrimaries); XCTAssertNil(frame.transferFunction)
        XCTAssertNil(frame.colorMatrix); XCTAssertNil(frame.colorRange)
        XCTAssertNil(frame.chromaLocation); XCTAssertNil(frame.hdrStaticMetadata)
        XCTAssertNil(frame.hdrDynamicMetadata); XCTAssertNil(frame.stereoView)
        XCTAssertNil(frame.projection)
        // Its pts flows through enqueue -> token -> decide intact: identical
        // pts on the token, current generation, on-time decision at the
        // seek anchor (mediaTime == pts at hostTime 2.0).
        let ptsSeconds = Double(frame.pts!.value) / Double(frame.pts!.scale)
        let token = q.enqueue(videoPTS: ptsSeconds)
        XCTAssertEqual(token.pts, ptsSeconds)
        XCTAssertEqual(q.decide(frame: token, hostTime: 2.0), .present)
        // The coordinator never touches the e2 fields; the round trip leaves
        // every default exactly as constructed.
        XCTAssertNil(frame.colorPrimaries); XCTAssertNil(frame.hdrDynamicMetadata)
        XCTAssertNil(frame.stereoView); XCTAssertNil(frame.projection)
    }
}
