// W-gdb-033 candidate PlayheadTracker, implemented against the prose pin only.
//
// Pin (packet "pinned ABI decisions", integrator 2026-11-15; PlayheadTracker.read,
// PlayheadPosition.swift @ 2112af0d60df16c5473173b664903f76ce54173e, prose-only):
//   - value = anchor + played elapsed
//   - MONOTONIC within a generation: a computed decrease is clamped to the last
//     emitted value (the only drift guard; drift cap = 0 backwards movement)
//   - duration cap wins at EOF: out > durationSeconds clamps to durationSeconds
//   - freeze while paused is exact: running == false adds no elapsed
//   - seekCommitted re-arms: generation += 1, anchor replaced; nil anchor reads
//     nil until the next firstFrame
//
// KNOWN GAP (per task): these semantics are pinned in prose, not in a source
// excerpt. This is a candidate implementation of that prose; any divergence from
// the real PlayheadPosition.swift must be reported, not guessed around.

/// Candidate value tracker with a virtual clock.
/// Monotonic-within-generation + duration cap are the only guards.
public struct PlayheadTracker {
    public private(set) var generation: UInt64 = 0

    private var anchorMedia: Double?   // nil before first frame of the generation
    private var anchorClock: Double = 0
    private var playedBase: Double = 0 // elapsed accumulated before current running segment
    private var running: Bool = true
    private var lastEmitted: Double?   // monotonic guard, per generation

    public init() {}

    /// First presented frame of the current generation (re-)arms the anchor.
    public mutating func firstFrame(anchorMediaSeconds: Double, clockNow: Double, playing: Bool = true) {
        anchorMedia = anchorMediaSeconds
        anchorClock = clockNow
        playedBase = 0
        running = playing
    }

    /// running == false adds no elapsed (freeze-while-paused is exact).
    public mutating func pause(clockNow: Double) {
        if running, anchorMedia != nil {
            playedBase += clockNow - anchorClock
            anchorClock = clockNow
        }
        running = false
    }

    public mutating func resume(clockNow: Double) {
        anchorClock = clockNow
        running = true
    }

    /// seekCommitted re-arms: generation += 1, anchor replaced.
    /// A nil anchor reads nil until the next firstFrame.
    public mutating func seekCommitted(anchorMediaSeconds: Double?, clockNow: Double, playing: Bool = true) {
        generation &+= 1
        anchorMedia = anchorMediaSeconds
        anchorClock = clockNow
        playedBase = 0
        running = playing
        lastEmitted = nil // monotonic guard is within a generation only
    }

    /// read(clockNow:durationSeconds:) -> Double?
    /// Monotonic within a generation; duration cap wins.
    public mutating func read(clockNow: Double, durationSeconds: Double?) -> Double? {
        guard let anchor = anchorMedia else { return nil } // nil-until-first-frame
        var value = anchor + playedBase + (running ? clockNow - anchorClock : 0)
        if let last = lastEmitted, value < last {
            value = last // monotonic clamp: the only drift guard (0 backwards movement)
        }
        if let d = durationSeconds, value > d {
            value = d // duration cap wins at EOF
        }
        lastEmitted = value
        return value
    }
}
