import Foundation

// in2tinct lab, W-gdb-053. Spatial module seam written against the pinned
// Types.swift (sha256 15d90863, gorav @ 2112af0d). Foundation contract ONLY.
// NOT_RUN: Swift compile. Claims no HDR/EDR/FEL, rendering or presentation.
// nil = not signaled, never invented. Fields are copied verbatim.

public extension PresentationFrame {
    /// Presentation shape from a decoded frame's signaled fields. The caller
    /// supplies the buffer and format; no digest is carried, no value invented.
    init(from frame: DecodedFrame, pixelBuffer: PresentationBuffer, pixelFormat: String) {
        self.init(pixelBuffer: pixelBuffer, pixelFormat: pixelFormat,
                  colorPrimaries: frame.colorPrimaries, transferFunction: frame.transferFunction,
                  colorMatrix: frame.colorMatrix, colorRange: frame.colorRange,
                  chromaLocation: frame.chromaLocation, hdrStaticMetadata: frame.hdrStaticMetadata,
                  hdrDynamicMetadata: frame.hdrDynamicMetadata, stereoView: frame.stereoView,
                  projection: frame.projection)
    }
}

public enum SpatialContract {
    /// dovi configuration comes only from container configuration bytes.
    public static func doviConfiguration(containerBytes: Data) -> CodecConfiguration {
        .dovi(containerBytes)
    }
    /// Backends that cannot run dovi refuse typed; never fabricate frames.
    public static func refuseUnsupported(_ what: String) -> DecoderError {
        .unsupportedBackend(what)
    }
}
