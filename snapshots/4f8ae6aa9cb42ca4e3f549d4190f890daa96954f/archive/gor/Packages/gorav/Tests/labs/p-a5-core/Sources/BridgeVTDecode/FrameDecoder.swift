import Foundation
import BridgeDemux

/// One decoded video frame. `pts` uses the P-A1 RationalTime contract
/// (nil is preserved, never zero). `digest` is the deterministic
/// per-machine pixel digest (PixelDigest); it is recorded, asserted stable
/// across two runs on the same host, and NOT asserted across hosts.
public struct DecodedFrame: Sendable {
    public let pts: RationalTime?      // from the P-A1 RationalTime contract
    public let width: Int
    public let height: Int
    public let digest: String          // deterministic pixel digest, recorded
    public init(pts: RationalTime?, width: Int, height: Int, digest: String) {
        self.pts = pts
        self.width = width
        self.height = height
        self.digest = digest
    }
}

/// Typed decoder errors. A backend that cannot run refuses with
/// `.unsupportedBackend` and never fabricates frames.
public enum DecoderError: Error, Equatable, Sendable {
    case unsupportedBackend(String)
    case missingConfiguration(String)
    case unknownCodec(String)
    case decodeFailed(String)
}

/// Packet-in, frame-out decoder. `codec` is "h264" or "hevc"; packets
/// arrive in decode (demux) order. `flush` drains reorder; the stream is
/// at EOS afterwards.
public protocol FrameDecoder {
    mutating func open(codec: String) throws
    mutating func decode(_ packet: DemuxPacket) throws -> [DecodedFrame]
    mutating func flush() throws -> [DecodedFrame]
}
