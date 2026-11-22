// Sources/GorAVPlaybackCore/PlayheadPosition.swift  (step 2; replaces step 1b file)
// G6: pure time-pos arithmetic and tracker. No clock reads, no I/O. Linux only / Mac NOT_RUN.

/// Pure position: anchor + elapsed play time, clamped. nil if anything is non-finite
/// or there is no anchor. Never publishes a non-finite value, never invents zero.
public func playheadSeconds(anchor: Double?, playedSeconds: Double, durationSeconds: Double?) -> Double? {
    guard let a = anchor, a.isFinite else { return nil }
    var e = playedSeconds
    if !e.isFinite || e < 0 { e = 0 }
    var t = a + e
    if !t.isFinite { return nil }
    if t < 0 { t = 0 }
    if let d = durationSeconds, d.isFinite, d > 0, t > d { t = d }
    return t
}

/// Tracks one session's playhead against ONE clock (the caller passes that clock's seconds to every
/// call; mixing clock sources breaks the arithmetic). Pause freezes the position (played time is
/// carried). The pause intent is remembered across a seek and before the first frame. A non-finite
/// clock sample (lost audio master) never publishes NaN: the run start is adopted from the next
/// finite sample.
public struct PlayheadTracker: Sendable {
    public private(set) var generation: Int = 0
    public private(set) var paused: Bool = false
    private var anchor: Double?
    private var carriedPlayed: Double = 0      // play time accumulated before the current run
    private var running = false                // playing with an anchor
    private var runStartClock: Double?         // nil while running means: adopt the next finite clock
    private var lastValue: Double?
    public init() {}

    /// First frame of generation `generation`, decided at media time `anchor`.
    /// Ignored (returns false, no state change) unless `generation` equals the tracker's
    /// current generation: a late first frame from before a seek, or from a generation the
    /// tracker has not been told about, never binds the wrong anchor. One per generation.
    /// Starts running only if not paused.
    @discardableResult
    public mutating func firstFrame(anchor: Double, clockNow: Double, generation: Int) -> Bool {
        guard generation == self.generation, self.anchor == nil else { return false }
        self.anchor = anchor
        carriedPlayed = 0
        running = !paused
        runStartClock = (running && clockNow.isFinite) ? clockNow : nil
        lastValue = nil
        return true
    }
    public mutating func pause(clockNow: Double) {
        paused = true
        guard running else { return }
        if let s = runStartClock {
            let d = clockNow - s
            if d.isFinite, d > 0 { carriedPlayed += d }
        }
        running = false
        runStartClock = nil
    }
    public mutating func resume(clockNow: Double) {
        paused = false
        guard anchor != nil, !running else { return }
        running = true
        runStartClock = clockNow.isFinite ? clockNow : nil
    }
    /// Committed seek: new generation. `anchor` nil = reads nil until the next
    /// firstFrame(generation: new). The pause state at seek entry is carried.
    public mutating func seekCommitted(anchor: Double?, clockNow: Double, wasPaused: Bool) {
        generation += 1
        paused = wasPaused
        self.anchor = anchor
        carriedPlayed = 0
        running = anchor != nil && !wasPaused
        runStartClock = (running && clockNow.isFinite) ? clockNow : nil
        lastValue = nil
    }
    /// nil before the first frame. Monotonic within a generation; duration cap wins.
    public mutating func read(clockNow: Double, durationSeconds: Double?) -> Double? {
        if running, runStartClock == nil, clockNow.isFinite { runStartClock = clockNow }
        var played = carriedPlayed
        if running, let s = runStartClock {
            let d = clockNow - s
            if d.isFinite, d > 0 { played += d }
        }
        guard let v = playheadSeconds(anchor: anchor, playedSeconds: played, durationSeconds: durationSeconds) else { return nil }
        var out = v
        if let l = lastValue, v < l { out = l }
        if let d = durationSeconds, d.isFinite, d > 0, out > d { out = d }
        lastValue = out
        return out
    }
}
