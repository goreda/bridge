import Foundation
import BridgeDemux

/// Software fallback stub, available on every platform. It owns no decoder
/// and refuses with a typed `.unsupportedBackend` on open for ANY codec -
/// it never fabricates frames, so a non-Mac run is typed, not green.
public struct SoftwareStubDecoder: FrameDecoder {
    public init() {}
    public mutating func open(codec: String, configuration: CodecConfiguration) throws {
        throw DecoderError.unsupportedBackend("software stub has no decoder for codec \(codec)")
    }
    public mutating func decode(_ packet: DemuxPacket) throws -> [DecodedFrame] {
        throw DecoderError.unsupportedBackend("software stub cannot decode")
    }
    public mutating func flush() throws -> [DecodedFrame] {
        throw DecoderError.unsupportedBackend("software stub cannot flush")
    }
}
