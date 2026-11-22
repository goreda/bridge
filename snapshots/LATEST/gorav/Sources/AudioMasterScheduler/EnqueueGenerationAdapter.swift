import Foundation

/// Immutable enqueue-time stamp. Clients retain this value with decoded bytes.
/// There is deliberately no public initializer accepting a generation.
public struct EnqueuedVideoFrame: Equatable, Sendable {
    public let pts: Double
    public let generation: UInt64
    fileprivate init(pts: Double, generation: UInt64) {
        self.pts = pts; self.generation = generation
    }
}

/// Owns the clock so an enqueue stamp is captured before a subsequent seek.
/// Retained frame values are never relabelled. Use decide(frame:hostTime:),
/// not the PTS-only protocol method, for generation-safe delivery.
/// Tokens belong to this adapter instance, not to another independently created
/// adapter. Serialized use and fewer than 2^64 timeline changes are required.
public struct EnqueueGenerationAdapter: AudioMasterScheduler, Sendable {
    private var clock = AudioMasterClock()
    public init() {}
    public mutating func reset(audioTime: Double, hostTime: Double) {
        clock.reset(audioTime: audioTime, hostTime: hostTime)
    }
    public mutating func seek(to seconds: Double, hostTime: Double) {
        clock.seek(to: seconds, hostTime: hostTime)
    }
    public mutating func updateAudio(mediaTime: Double, hostTime: Double) {
        clock.updateAudio(mediaTime: mediaTime, hostTime: hostTime)
    }
    public func mediaTime(at hostTime: Double) -> Double { clock.mediaTime(at: hostTime) }
    public func enqueue(videoPTS: Double) -> EnqueuedVideoFrame {
        EnqueuedVideoFrame(pts: videoPTS, generation: clock.generation)
    }
    public func decide(frame: EnqueuedVideoFrame, hostTime: Double) -> VideoDecision {
        clock.decide(videoPTS: frame.pts, hostTime: hostTime, generation: frame.generation)
    }
    /// Compatibility only: no frame generation is present in this signature.
    @available(*, deprecated, message: "Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity")
    public mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision {
        clock.decide(videoPTS: videoPTS, hostTime: hostTime)
    }
}
