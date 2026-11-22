// Sources/GorAVPlaybackCore/PlayheadObservers.swift  (step 2, new)
// G6: pure helpers behind the observers. Linux only / Mac NOT_RUN.

/// Container duration from FFmpeg AVFormatContext.duration (AV_TIME_BASE ticks,
/// microseconds). nil when unknown (AV_NOPTS_VALUE passed as nil by the caller),
/// zero, negative, or not representable. Never returns 0 for unknown.
public func containerDurationSeconds(ticks: Int64?, ticksPerSecond: Int64 = 1_000_000) -> Double? {
    guard let t = ticks, t > 0, ticksPerSecond > 0 else { return nil }
    let s = Double(t) / Double(ticksPerSecond)
    return s.isFinite && s > 0 ? s : nil
}

/// timePos event gate: at most `maxPerSecond` events, only when the value changed.
public struct TimePosGate: Sendable {
    private let minInterval: Double
    private var lastEmitClock: Double?
    private var lastValue: Double?
    public init(maxPerSecond: Double = 4) {
        minInterval = maxPerSecond > 0 ? 1.0 / maxPerSecond : 0
    }
    /// Returns the value to emit, or nil to stay quiet. A generation change
    /// (seek) always emits the first value of the new generation immediately and
    /// resets the clock reference. Non-finite or backwards clockNow never emits.
    public mutating func offer(_ value: Double?, clockNow: Double, newGeneration: Bool = false) -> Double? {
        guard let v = value, v.isFinite, clockNow.isFinite else { return nil }
        if newGeneration { lastEmitClock = nil; lastValue = nil }
        if let l = lastValue, l == v { return nil }
        // A clock sample earlier than the last emit is not trusted: stay quiet
        // (never bypass the rate limit) until the clock catches up.
        if let c = lastEmitClock, clockNow < c || clockNow - c < minInterval { return nil }
        lastEmitClock = clockNow
        lastValue = v
        return v
    }
}

/// volumeChanged gate: one event per actual change, never for non-finite input.
public struct VolumeChangeGate: Sendable {
    private var last: Float?
    public init() {}
    public mutating func offer(_ v: Float) -> Float? {
        guard v.isFinite else { return nil }
        if let l = last, l == v { return nil }
        last = v
        return v
    }
}
