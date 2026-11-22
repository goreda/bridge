import Foundation

// 195c-N6: explicit little-endian byte packing for FrameUniforms. This is the
// exact byte stream the Metal stage pass uploads; the layout is witnessed on
// Linux so the Mac compile (N1) reviews code against an already-green
// contract, not a guess. Reuses the versioned FrameUniformABI payload,
// 16 lanes x 4 bytes = 64 bytes.

extension FrameUniforms {
    public static let packedByteCount = FrameUniformABI.payloadBytes

    /// Byte offset of each field, the single source of truth for both the
    /// Swift packer and the MSL struct declaration.
    public enum Offsets {
        public static let frameWidth = 0, frameHeight = 4, fitModeID = 8, reserved0 = 12
        public static let cropX = 16, cropY = 20, cropW = 24, cropH = 28
        public static let panX = 32, panY = 36, log2Zoom = 40, flags = 44
        public static let toneCurveID = 48, srcPeakNits = 52, dstPeakNits = 56, saturation = 60
    }

    public func packedBytes() -> [UInt8] {
        Array(FrameUniformABI.payload(self))
    }
}
