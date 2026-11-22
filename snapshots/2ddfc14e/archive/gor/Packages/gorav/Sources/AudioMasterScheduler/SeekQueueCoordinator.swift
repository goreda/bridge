import Foundation

/// Serialized owner of the presentation queue and enqueue-time tokens.
/// A seek invalidates the prior generation before the provider flush.
/// Callers supply their real decoder/packet-queue flush, not a clock-only reset.
public struct SeekQueueCoordinator: Sendable {
    public private(set) var scheduler = EnqueueGenerationAdapter()
    public private(set) var pending: [EnqueuedVideoFrame] = []
    public init() {}
    public mutating func reset(audioTime: Double, hostTime: Double) {
        pending.removeAll()
        scheduler.reset(audioTime: audioTime, hostTime: hostTime)
    }
    public mutating func enqueue(videoPTS: Double) -> EnqueuedVideoFrame {
        let token = scheduler.enqueue(videoPTS: videoPTS)
        pending.append(token)
        return token
    }
    public mutating func updateAudio(mediaTime: Double, hostTime: Double) {
        scheduler.updateAudio(mediaTime: mediaTime, hostTime: hostTime)
    }
    public func decide(frame: EnqueuedVideoFrame, hostTime: Double) -> VideoDecision {
        scheduler.decide(frame: frame, hostTime: hostTime)
    }
    public mutating func seek(to seconds: Double, hostTime: Double,
                              flushDecoderAndPackets: () throws -> Void) throws {
        // Remove queued decoded frames even when provider flush fails.
        guard seconds.isFinite, seconds >= 0, hostTime.isFinite else {
            throw SeekQueueError.invalidTarget
        }
        pending.removeAll()
        // Invalidate tokens before calling the provider: failed seek cannot make
        // pre-seek frames current again. No frame receives a replacement token.
        scheduler.seek(to: seconds, hostTime: hostTime)
        try flushDecoderAndPackets()
    }
}

public enum SeekQueueError: Error { case invalidTarget }
