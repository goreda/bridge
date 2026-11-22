import Foundation

/// Saturating s16le output boost. Called only on admitted, live render buffers.
/// Unity is a no-op; no allocation, lock, file or callback on the render path.
public enum PCMOutputBoost {
    public static let maximum: Float = 2
    public static func apply(_ gain: Float, bytes: UnsafeMutableRawPointer, count: Int) {
        guard gain.isFinite, gain > 1, gain <= maximum, count >= 2 else { return }
        for offset in stride(from: 0, to: count - 1, by: 2) {
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)
            let sample = Int16(littleEndian: raw)
            let scaled = Int32((Float(sample) * gain).rounded(.towardZero))
            let clipped = Int16(max(Int32(Int16.min), min(Int32(Int16.max), scaled)))
            bytes.storeBytes(of: clipped.littleEndian, toByteOffset: offset, as: Int16.self)
        }
    }
}
