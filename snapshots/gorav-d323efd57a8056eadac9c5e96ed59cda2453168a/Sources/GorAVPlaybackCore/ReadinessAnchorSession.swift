import Foundation

/// 189k PERMANENT ENGINE RULE (owner block 189k, 2026-11-07 01:50 +03):
/// the audio clock starts only after frame 0 is decoded AND presented;
/// after every seek: flush the queue, present the first frame, then
/// restart the clock. Frame 0 of each generation is the readiness anchor
/// and never receives a scheduler decision. maxLate and all downstream
/// asserts are unchanged by this type; it owns ONLY the ordering state so
/// no harness or shell can reimplement (or skip) the rule.
///
/// The session is deliberately small and platform-neutral (Linux-testable):
/// callers perform the real decode/present/clock work and move the session
/// through its typed gates. A clock start requested before the anchor is
/// presented is REFUSED (typed), never silently permitted.
public struct ReadinessAnchorSession: Sendable, Equatable {
    /// Seek fence: bumped on every seek; frames from older generations are stale.
    public private(set) var generation: UInt64 = 0
    /// True while the current generation's first frame has not been both
    /// decoded and presented. An anchor-pending frame takes NO scheduler
    /// decision: it IS the timeline zero.
    public private(set) var anchorPending = true
    /// True after requestClockStart() succeeded for the current generation.
    public private(set) var clockRunning = false
    public init() {}

    /// Start of playback (generation 0).
    public mutating func begin() {
        generation = 0; anchorPending = true; clockRunning = false
    }

    /// The readiness anchor frame for the current generation was decoded
    /// AND presented. Idempotent within a generation.
    public mutating func anchorPresentedNow() { anchorPending = false }

    /// Typed clock-start gate: succeeds only after the anchor is presented.
    /// Returns false (refusal) when the anchor is still pending.
    public mutating func requestClockStart() -> Bool {
        guard !anchorPending else { return false }
        clockRunning = true
        return true
    }

    /// Seek: the queue is flushed by the caller; the clock stops; the first
    /// frame of the new generation is again a readiness anchor that must be
    /// presented before the clock restarts. Returns the new generation.
    @discardableResult
    public mutating func seek() -> UInt64 {
        generation &+= 1
        anchorPending = true
        clockRunning = false
        return generation
    }
}
