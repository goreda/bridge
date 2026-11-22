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
    // e2 foundation (plan/E2-FOUNDATION-CONTRACT.md, owner block 190 queue
    // item 5): additive defaulted fields only. nil means "not signaled",
    // never an invented value; digest semantics are unchanged.
    public let colorPrimaries: String?      // e.g. "bt709", "bt2020"
    public let transferFunction: String?    // e.g. "bt1886", "pq", "hlg"
    public let colorMatrix: String?
    public let colorRange: String?          // "limited"/"full"
    public let chromaLocation: String?
    public let hdrStaticMetadata: Data?     // opaque; interpreted only by tests that name its format
    public let hdrDynamicMetadata: Data?    // opaque; the dovi RPU oracle consumes it in its own lane
    public let stereoView: String?          // e.g. "mono", "left", "right"
    public let projection: String?          // e.g. "flat", "vr180", "equirect"
    public init(pts: RationalTime?, width: Int, height: Int, digest: String,
                colorPrimaries: String? = nil, transferFunction: String? = nil,
                colorMatrix: String? = nil, colorRange: String? = nil,
                chromaLocation: String? = nil, hdrStaticMetadata: Data? = nil,
                hdrDynamicMetadata: Data? = nil, stereoView: String? = nil,
                projection: String? = nil) {
        self.pts = pts
        self.width = width
        self.height = height
        self.digest = digest
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.colorRange = colorRange
        self.chromaLocation = chromaLocation
        self.hdrStaticMetadata = hdrStaticMetadata
        self.hdrDynamicMetadata = hdrDynamicMetadata
        self.stereoView = stereoView
        self.projection = projection
    }
}

/// Opaque presentation buffer reference: a CVPixelBuffer on Darwin, an
/// equivalent opaque handle off-Darwin. Reference-typed because the buffer
/// is owned elsewhere; Sendable by contract of read-only consumption, the
/// same rule the presenter path already applies to frame data.
public final class PresentationBuffer: @unchecked Sendable {
    public let object: AnyObject
    public init(object: AnyObject) { self.object = object }
}

/// e2 presentation frame (plan/E2-FOUNDATION-CONTRACT.md section 1.2): the
/// shape a presenter consumes. It carries NO digest - measurement never
/// rides the presentation path. DecodedFrame stays the measurement/oracle
/// shape; FrameDecoder keeps vending DecodedFrame and no presentation
/// vending interface is added here.
public struct PresentationFrame: Sendable {
    public let pixelBuffer: PresentationBuffer
    public let pixelFormat: String          // e.g. "yuv420p8", "nv12-8", "p010le"
    public let colorPrimaries: String?
    public let transferFunction: String?
    public let colorMatrix: String?
    public let colorRange: String?
    public let chromaLocation: String?
    public let hdrStaticMetadata: Data?
    public let hdrDynamicMetadata: Data?
    public let stereoView: String?
    public let projection: String?
    public init(pixelBuffer: PresentationBuffer, pixelFormat: String,
                colorPrimaries: String? = nil, transferFunction: String? = nil,
                colorMatrix: String? = nil, colorRange: String? = nil,
                chromaLocation: String? = nil, hdrStaticMetadata: Data? = nil,
                hdrDynamicMetadata: Data? = nil, stereoView: String? = nil,
                projection: String? = nil) {
        self.pixelBuffer = pixelBuffer
        self.pixelFormat = pixelFormat
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.colorRange = colorRange
        self.chromaLocation = chromaLocation
        self.hdrStaticMetadata = hdrStaticMetadata
        self.hdrDynamicMetadata = hdrDynamicMetadata
        self.stereoView = stereoView
        self.projection = projection
    }
}

/// Typed decoder errors. A backend that cannot run refuses with
/// `.unsupportedBackend` and never fabricates frames.
public enum DecoderError: Error, Equatable, Sendable {
    case unsupportedBackend(String)
    case missingConfiguration(String)
    case malformedConfiguration(String)
    case unknownCodec(String)
    case decodeFailed(String)
}

/// Packet-in, frame-out decoder. `codec` is "h264" or "hevc"; packets
/// arrive in decode (demux) order. `flush` drains reorder; the stream is
/// at EOS afterwards.
public protocol FrameDecoder {
    mutating func open(codec: String, configuration: CodecConfiguration) throws
    mutating func decode(_ packet: DemuxPacket) throws -> [DecodedFrame]
    mutating func flush() throws -> [DecodedFrame]
}

/// Container decoder records are bytes, never inferred from packet payloads.
public enum CodecConfiguration: Equatable, Sendable {
    case avcC(Data)
    case hvcC(Data)
    case inBand
    /// e2 (spec section 3): the dovi configuration record bytes, as container
    /// records are bytes - never inferred from packet payloads. A decoder
    /// that cannot run dovi refuses with .unsupportedBackend, never
    /// fabricates frames.
    case dovi(Data)
}

public extension FrameDecoder {
    mutating func open(codec: String) throws {
        try open(codec: codec, configuration: .inBand)
    }
}
