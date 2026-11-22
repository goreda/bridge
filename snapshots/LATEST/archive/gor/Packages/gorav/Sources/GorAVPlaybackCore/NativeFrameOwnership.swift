import Foundation

/// Native frame origin is captured at producer admission, never reconstructed
/// from the consumer's current generation after an await.
public struct NativeFrameProvenance: Equatable, Sendable {
    public let source: SourceSession
    public let ptsSeconds: Double
    public let durationSeconds: Double
    public init(source: SourceSession, ptsSeconds: Double, durationSeconds: Double) {
        self.source = source; self.ptsSeconds = ptsSeconds; self.durationSeconds = durationSeconds
    }
    public func admits(source expected: SourceSession, ptsSeconds pts: Double, durationSeconds duration: Double) -> Bool {
        source.session != 0 && source == expected && pts.isFinite && duration.isFinite && duration > 0
            && ptsSeconds.isFinite && durationSeconds.isFinite && durationSeconds > 0
            && ptsSeconds == pts && durationSeconds == duration
    }
}

/// Shared read-only native ownership. Darwin stores a CVPixelBuffer here;
/// portable tests use a deinit-counted object. The final owner releases it
/// exactly once. No explicit release may invalidate another GPU/slot reader.
public final class NativeFrameOwnership: @unchecked Sendable {
    private let retainedObject: AnyObject
    public let provenance: NativeFrameProvenance
    public init(retaining object: AnyObject, provenance: NativeFrameProvenance) {
        retainedObject = object; self.provenance = provenance
    }
}

/// A small recycle seam shared by renderer slots and the portable lifetime
/// test. The renderer's lock guards mutation. A GPU callback keeps its own
/// strong reference, so recycling a slot cannot release an in-flight image.
public struct NativeFrameSlot {
    public private(set) var ownership: NativeFrameOwnership?
    public init() {}
    public mutating func replace(with ownership: NativeFrameOwnership?) { self.ownership = ownership }
    public mutating func recycle() { ownership = nil }
}

public enum NativeFrameProducerError: Error, Equatable, Sendable {
    case staleSession
    case staleGeneration
    case missingFrame
    case unsupportedFormat
    case hardwareFailure(Int)
}

#if canImport(CoreVideo)
/// Decoder integration contract. The mixed decoder implementation is not
/// part of this patch. nil means the admitted frame is software, not EOS.
/// Throwing a hardware error must enter the bounded fresh software reopen.
public protocol NativeVideoFrameProducer: Sendable {
    /// Execute under the decoder's frame-table owner. Verify handle, real
    /// session, original frame generation and PTS before retaining the
    /// CVPixelBuffer from the hardware AVFrame. Never relabel an old frame
    /// with the caller's current generation. The returned payload owns its
    /// native reference after AVFrame release, until all slot/GPU owners drop.
    func retainNativeFrame(handle: UInt64, provenance: NativeFrameProvenance) async throws -> VTFramePayload?
}
#endif
