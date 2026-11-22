import Foundation

// MARK: - Blink episode bookkeeping (pure, no Vision/AppKit/clock)

struct BlinkEpisodeTracker {
    struct Event {
        let end: String            // "reopened" or "abandoned" (closed longer than abandonS)
        let t0: Double
        let t1: Double?            // time of the reopening sample; nil when abandoned
        let durS: Double           // first closed sample -> reopening sample (or last sample when abandoned)
        let closedSpanS: Double    // first -> last closed sample
        let nClosed: Int           // closed samples inside the episode
        let minRatio: Double
        let maxGapS: Double        // largest gap between consecutive USABLE samples, from the one before the first closed sample to the reopening one
        let unusableInside: Int    // unusable samples (no eyes / yaw over limit) seen while the episode was open
        let tBefore: Double?       // time of the last usable (open) sample before the first closed one; nil if none
        let baselineYoung: Bool    // fewer than youngBaseline usable samples had been seen before the episode started
        /// Duration alone: reopen within 0.10...0.40 s of the first closed sample (literature range for a spontaneous blink).
        let inBlinkRange: Bool
        /// The cadence could see the shape: enough closed samples, no gap above maxGapS, no unusable sample inside.
        var sampledWell: Bool { nClosed >= BlinkEpisodeTracker.minClosedSamples && maxGapS <= BlinkEpisodeTracker.maxGapLimitS && unusableInside == 0 }
        /// Quality only, never a detection verdict: duration in range AND sampled well AND baseline not young.
        var qualityOK: Bool { end == "reopened" && inBlinkRange && sampledWell && !baselineYoung }
    }

    static let abandonS = 0.6          // PROVISIONAL
    static let maxGapLimitS = 0.05     // PROVISIONAL: half of the shortest 100 ms blink
    static let minClosedSamples = 3    // PROVISIONAL
    static let youngBaseline = 10      // PROVISIONAL: usable samples before the open baseline counts as established

    private var usableSeen = 0
    private var prevUsableT: Double? = nil
    private var t0: Double? = nil
    private var lastClosedT = 0.0
    private var n = 0
    private var minR = 1.0
    private var maxGap = 0.0
    private var unusable = 0
    private var youngAtStart = true
    private var abandoned = false
    private var tBeforeStart: Double? = nil

    mutating func reset() { self = BlinkEpisodeTracker() }

    /// Feed one sample. `ratio` and `closing` are nil together when the sample is unusable. Returns whether a new
    /// episode started on this sample and the finished event, if this sample ended one.
    mutating func feed(t: Double, ratio: Double?, closing: Bool?) -> (started: Bool, event: Event?) {
        guard let r = ratio, let c = closing else {
            if t0 != nil { unusable += 1 }
            return (false, nil)
        }
        let gap = prevUsableT.map { t - $0 } ?? 0
        let prevT = prevUsableT
        prevUsableT = t
        usableSeen += 1
        if c {
            if abandoned { return (false, nil) }          // long closure: wait for a reopen
            var started = false
            if t0 == nil {
                t0 = t; tBeforeStart = prevT; n = 0; minR = r; maxGap = gap; unusable = 0; youngAtStart = (usableSeen - 1) < Self.youngBaseline; started = true
            }
            n += 1; minR = min(minR, r); lastClosedT = t; maxGap = max(maxGap, gap)
            if let s = t0, t - s > Self.abandonS {
                let e = makeEvent(end: "abandoned", t1: nil, now: t)
                t0 = nil; abandoned = true
                return (started, e)
            }
            return (started, nil)
        }
        if abandoned { abandoned = false; return (false, nil) }
        guard let s = t0 else { return (false, nil) }
        maxGap = max(maxGap, gap)
        let e = makeEvent(end: "reopened", t1: t, now: t)
        _ = s; t0 = nil
        return (false, e)
    }

    private func makeEvent(end: String, t1: Double?, now: Double) -> Event {
        let s = t0 ?? now
        let dur = (t1 ?? now) - s
        return Event(end: end, t0: s, t1: t1, durS: dur, closedSpanS: lastClosedT - s, nClosed: n, minRatio: minR,
                     maxGapS: maxGap, unusableInside: unusable, tBefore: tBeforeStart, baselineYoung: youngAtStart,
                     inBlinkRange: dur >= 0.10 && dur <= 0.40)
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Blink recognizer (pure). Turns one finished episode into a detection, aware of the sampling cadence. It binds no
// command. Every number is either the literature blink range already used above or a PROVISIONAL hypothesis; none is
// validated on a real recording, so a detection here is "the provisional rule fired", not a measured accuracy.
struct BlinkDetection {
    enum Kind: String {
        case confirmed = "confirmed"   // >= 2 closed samples, nothing unusable inside, baseline established, duration compatible
        case possible = "possible"     // compatible duration but a single closed sample, an unusable sample inside or a young baseline
        case held = "held"             // eye stayed closed past the blink range (>= 2 closed samples): an eye closure, not a blink
    }
    let kind: Kind
    let t0: Double
    let durMinS: Double                // conservative bound: point samples alone prove no continuous duration
    let durMaxS: Double                // longest it can have been (previous open sample -> reopening sample)
    let nClosed: Int
    let minRatio: Double
}

enum BlinkRecognizer {
    static let blinkMinS = 0.10        // literature range, same as BlinkEpisodeTracker.Event.inBlinkRange
    static let blinkMaxS = 0.40
    static let maxConfirmedGapS = 0.15 // provisional upper bound; sparse episodes remain possible, never confirmed
    static let minClosedForConfirmed = 2   // PROVISIONAL: one dipping sample cannot be told from landmark jitter

    /// Cadence-aware PROVISIONAL rule. Closed-span continuity is a heuristic, not a physical lower bound:
    /// an unseen reopening may occur between point samples. durMinS remains zero. The enum name
    /// confirmed means only that this stricter heuristic fired, never validated camera ground truth.
    static func classify(_ e: BlinkEpisodeTracker.Event) -> BlinkDetection? {
        if e.end == "abandoned" {
            guard e.nClosed >= minClosedForConfirmed, e.unusableInside == 0, !e.baselineYoung, e.maxGapS <= maxConfirmedGapS else { return nil }
            return BlinkDetection(kind: .held, t0: e.t0, durMinS: 0, durMaxS: e.durS, nClosed: e.nClosed, minRatio: e.minRatio)
        }
        guard let t1 = e.t1 else { return nil }
        let dMin = e.closedSpanS
        let dMax = e.tBefore.map { t1 - $0 } ?? e.durS
        guard dMin <= blinkMaxS, dMax >= blinkMinS else { return nil }
        let sure = e.nClosed >= minClosedForConfirmed && e.unusableInside == 0 && !e.baselineYoung
            && e.maxGapS <= maxConfirmedGapS && dMin >= blinkMinS && dMax <= blinkMaxS
        return BlinkDetection(kind: sure ? .confirmed : .possible, t0: e.t0, durMinS: 0, durMaxS: dMax, nClosed: e.nClosed, minRatio: e.minRatio)
    }
}

