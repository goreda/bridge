import Foundation

public enum VideoDecision: Equatable, Sendable { case wait, present, drop }

public protocol AudioMasterScheduler {
    mutating func reset(audioTime: Double, hostTime: Double)
    mutating func seek(to seconds: Double, hostTime: Double)
    mutating func updateAudio(mediaTime: Double, hostTime: Double)
    func mediaTime(at hostTime: Double) -> Double
    mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision
}

/// Rate-one extrapolation of the most recent audio sample, in seconds.
/// Finite timestamps are required. Invalid decisions fail closed with drop;
/// invalid anchors are ignored. reset starts a new timeline and clears counters.
/// The PTS-only API tracks waiting PTS across seek, but has no frame identity.
/// Use the generation overload for complete stale-frame discrimination.
public struct AudioMasterClock: AudioMasterScheduler, Sendable {
    public static let maxLate = 0.040
    public static let tolerance = 1e-9
    public private(set) var generation: UInt64 = 0
    private var audio = 0.0
    private var host = 0.0
    private var waiting: Set<Double> = []
    private var stalePTS: Set<Double> = []
    public init() {}

    public mutating func reset(audioTime: Double, hostTime: Double) {
        guard audioTime.isFinite, hostTime.isFinite else { return }
        generation &+= 1
        waiting.removeAll(); stalePTS.removeAll()
        audio = audioTime; host = hostTime
    }
    public mutating func seek(to seconds: Double, hostTime: Double) {
        guard seconds.isFinite, hostTime.isFinite else { return }
        generation &+= 1
        stalePTS.formUnion(waiting); waiting.removeAll()
        audio = seconds; host = hostTime
    }
    public mutating func updateAudio(mediaTime: Double, hostTime: Double) {
        guard mediaTime.isFinite, hostTime.isFinite else { return }
        audio = mediaTime; host = hostTime
    }
    public func mediaTime(at hostTime: Double) -> Double {
        audio + (hostTime - host)
    }
    public mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision {
        guard videoPTS.isFinite, hostTime.isFinite else { return .drop }
        if stalePTS.contains(videoPTS) { return .drop }
        let result = classify(videoPTS: videoPTS, hostTime: hostTime)
        if result == .wait { waiting.insert(videoPTS) } else { waiting.remove(videoPTS) }
        return result
    }
    /// Capture generation when a frame is enqueued, not when it is evaluated.
    /// All pre-seek frames drop, including unseen or repeated-PTS frames.
    /// This additive overload leaves the packet's protocol unchanged.
    public func decide(videoPTS: Double, hostTime: Double, generation frameGeneration: UInt64) -> VideoDecision {
        guard frameGeneration == generation else { return .drop }
        return classify(videoPTS: videoPTS, hostTime: hostTime)
    }
    private func classify(videoPTS: Double, hostTime: Double) -> VideoDecision {
        guard videoPTS.isFinite, hostTime.isFinite else { return .drop }
        let offset = mediaTime(at: hostTime) - videoPTS
        guard offset.isFinite else { return .drop }
        if offset > Self.maxLate + Self.tolerance { return .drop }
        if offset < 0 { return .wait }
        return .present
    }
}
