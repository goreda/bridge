#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif
import GorAVPlaybackCore

// W-gdb-033 time-position tracker vector checker.
// Command (from package root): swift run timepos-vector-tests
// Expected: exit 0; final line "timepos-tests: all pass".
//
// Replays kits/timepos-vectors/vectors.json against the candidate
// PlayheadTracker (PlayheadTracker.swift) and asserts:
//   - anchor re-arm at first presented frame
//   - exact freeze-while-paused
//   - monotonic-in-generation clamp (no backwards movement; the only drift guard)
//   - duration cap at EOF, applied AFTER the monotonic clamp (cap wins)
//   - nil-until-first-frame after seekCommitted
// Then runs the negative controls: each seeded fault must FAIL replay;
// a negative control that replays green is a checker failure.

// MARK: - Seeded-fault trackers (negative controls)

enum Fault {
    case none            // reference candidate (PlayheadTracker semantics)
    case seededDrift     // subtracts 0.25 media-s per read: drift beyond the cap (cap = 0 backwards movement)
    case noMonotonicClamp// full pinned semantics (pause, duration, seek) minus the monotonic guard
    case pauseLeak       // pure freeze break: pause/resume ops are ignored; everything else reference
    case noDurationCap   // monotonic guard intact; only the EOF cap is removed
    case staleAfterSeek  // keeps emitting the old value instead of nil after a null-anchor seekCommitted
}

/// Full pinned semantics EXCEPT the monotonic guard. Backs the
/// noMonotonicClamp control so that control differs from pauseLeak only
/// in the missing clamp - pause and duration handling stay honest.
struct RawTracker {
    private var anchor: Double? = nil
    private var anchorClock: Double = 0
    private var playedBase: Double = 0
    private var running: Bool = true

    mutating func firstFrame(anchor a: Double, t: Double, playing: Bool) {
        anchor = a; anchorClock = t; playedBase = 0; running = playing
    }
    mutating func pause(t: Double) {
        if running, anchor != nil { playedBase += t - anchorClock; anchorClock = t }
        running = false
    }
    mutating func resume(t: Double) { anchorClock = t; running = true }
    mutating func seek(anchor a: Double?, t: Double, playing: Bool) {
        anchor = a; anchorClock = t; playedBase = 0; running = playing
    }
    func read(t: Double, duration: Double?) -> Double? {
        guard let a = anchor else { return nil }
        var v = a + playedBase + (running ? t - anchorClock : 0)
        if let d = duration, v > d { v = d }
        return v
    }
}

struct CandidateTracker {
    var inner = PlayheadTracker()  // reference candidate
    var raw = RawTracker()         // clamp-less mirror, kept in lockstep
    let fault: Fault

    private var stale: Double? = nil
    private var lastValue: Double? = nil
    private var driftReads: Int = 0

    init(fault: Fault) { self.fault = fault }

    mutating func firstFrame(anchor: Double, t: Double, playing: Bool) {
        inner.firstFrame(anchorMediaSeconds: anchor, clockNow: t, playing: playing)
        raw.firstFrame(anchor: anchor, t: t, playing: playing)
    }
    mutating func pause(t: Double) {
        if fault != .pauseLeak { inner.pause(clockNow: t) } // pauseLeak: pause op ignored (pure freeze break)
        raw.pause(t: t)
    }
    mutating func resume(t: Double) {
        if fault != .pauseLeak { inner.resume(clockNow: t) } // pauseLeak: resume op ignored
        raw.resume(t: t)
    }
    mutating func seekCommitted(anchor: Double?, t: Double, playing: Bool) {
        inner.seekCommitted(anchorMediaSeconds: anchor, clockNow: t, playing: playing)
        raw.seek(anchor: anchor, t: t, playing: playing)
        if fault == .staleAfterSeek, anchor == nil { stale = lastValue }
    }

    mutating func read(t: Double, duration: Double?) -> Double? {
        switch fault {
        case .none:
            let v = inner.read(clockNow: t, durationSeconds: duration)
            lastValue = v
            return v
        case .seededDrift:
            // reference value (probe copy, so the drift does not poison inner),
            // then walk backwards 0.25 media-s per read: beyond the zero cap
            var probe = inner
            let base = probe.read(clockNow: t, durationSeconds: duration)
            guard let b = base else { lastValue = nil; return nil }
            driftReads += 1
            var v = b - 0.25 * Double(driftReads)
            if let d = duration, v > d { v = d }
            lastValue = v
            return v
        case .noMonotonicClamp:
            let v = raw.read(t: t, duration: duration)
            lastValue = v
            return v
        case .pauseLeak:
            let v = inner.read(clockNow: t, durationSeconds: duration)
            lastValue = v
            return v
        case .noDurationCap:
            let v = inner.read(clockNow: t, durationSeconds: nil)
            lastValue = v
            return v
        case .staleAfterSeek:
            let v = inner.read(clockNow: t, durationSeconds: duration)
            if v == nil, let s = stale { return s }
            stale = nil
            lastValue = v
            return v
        }
    }
}

// MARK: - Replay

struct RowFailure {
    let vector: String
    let opIndex: Int
    let detail: String
}

func replay(_ vector: Vector, fault: Fault) -> [RowFailure] {
    var tracker = CandidateTracker(fault: fault)
    var failures: [RowFailure] = []
    for (i, op) in vector.ops.enumerated() {
        switch op {
        case .firstFrame(let anchor, let t, let playing):
            tracker.firstFrame(anchor: anchor, t: t, playing: playing)
        case .seekCommitted(let anchor, let t, let playing):
            tracker.seekCommitted(anchor: anchor, t: t, playing: playing)
        case .pause(let t):
            tracker.pause(t: t)
        case .resume(let t):
            tracker.resume(t: t)
        case .read(let t, let expect, let durOverride):
            let duration: Double?
            switch durOverride {
            case .inherit: duration = vector.duration
            case .value(let d): duration = d
            }
            let got = tracker.read(t: t, duration: duration)
            switch (got, expect) {
            case (nil, nil):
                break
            case let (g?, e?):
                if g != e { // exact comparison: vector values are chosen bit-exact
                    failures.append(RowFailure(vector: vector.name, opIndex: i,
                        detail: "read t=\(t): got \(g), expect \(e)"))
                }
            default:
                let gotStr = got.map { String($0) } ?? "nil"
                let expectStr = expect.map { String($0) } ?? "nil"
                failures.append(RowFailure(vector: vector.name, opIndex: i,
                    detail: "read t=\(t): got \(gotStr), expect \(expectStr)"))
            }
        }
    }
    return failures
}

// MARK: - Locate vectors.json

func fileExists(_ path: String) -> Bool {
    let f = fopen(path, "rb")
    if let f = f { fclose(f); return true }
    return false
}

func sourceDir(_ filePath: String) -> String {
    guard let idx = filePath.lastIndex(of: "/") else { return "." }
    return String(filePath[filePath.startIndex..<idx])
}

func findVectorsFile() -> String? {
    let candidates = [
        "kits/timepos-vectors/vectors.json",
        // fallback: relative to this source file (Sources/timepos-tests/main.swift)
        sourceDir(#filePath) + "/../../kits/timepos-vectors/vectors.json",
    ]
    return candidates.first { fileExists($0) }
}

// MARK: - Main

guard let path = findVectorsFile() else {
    print("timepos-tests: FAIL - kits/timepos-vectors/vectors.json not found")
    exit(1)
}
let vectors: [Vector]
do {
    vectors = try loadVectors(from: path)
} catch {
    print("timepos-tests: FAIL - \(error)")
    exit(1)
}

var exitCode: Int32 = 0

print("timepos-tests: \(vectors.count) vectors from \(path)")

// 1) Reference replay: every vector must be green.
var totalFailures = 0
for v in vectors {
    let failures = replay(v, fault: .none)
    if failures.isEmpty {
        print("  PASS \(v.name)")
    } else {
        totalFailures += failures.count
        for f in failures { print("  FAIL \(f.vector) op[\(f.opIndex)]: \(f.detail)") }
    }
}
// 1b) Product replay: the same vectors against the REAL
// GorAVPlaybackCore.PlayheadTracker (W-gdb-033 KNOWN GAP closure: the lab
// candidate was written against the prose pin; divergence from the real
// tracker must be reported, not guessed around).
struct ProductTracker {
    var inner = GorAVPlaybackCore.PlayheadTracker()
    var lastValue: Double?
    mutating func firstFrame(anchor: Double, t: Double, playing: Bool) {
        if !playing { inner.pause(clockNow: t) }
        _ = inner.firstFrame(anchor: anchor, clockNow: t, generation: inner.generation)
    }
    mutating func seekCommitted(anchor: Double?, t: Double, playing: Bool) {
        inner.seekCommitted(anchor: anchor, clockNow: t, wasPaused: !playing)
    }
    mutating func pause(t: Double) { inner.pause(clockNow: t) }
    mutating func resume(t: Double) { inner.resume(clockNow: t) }
    mutating func read(t: Double, duration: Double?) -> Double? {
        let v = inner.read(clockNow: t, durationSeconds: duration)
        lastValue = v
        return v
    }
}

func replayProduct(_ vector: Vector) -> [RowFailure] {
    var tracker = ProductTracker()
    var failures: [RowFailure] = []
    for (i, op) in vector.ops.enumerated() {
        switch op {
        case .firstFrame(let anchor, let t, let playing):
            tracker.firstFrame(anchor: anchor, t: t, playing: playing)
        case .seekCommitted(let anchor, let t, let playing):
            tracker.seekCommitted(anchor: anchor, t: t, playing: playing)
        case .pause(let t):
            tracker.pause(t: t)
        case .resume(let t):
            tracker.resume(t: t)
        case .read(let t, let expect, let durOverride):
            let duration: Double?
            switch durOverride {
            case .inherit: duration = vector.duration
            case .value(let d): duration = d
            }
            let got = tracker.read(t: t, duration: duration)
            switch (got, expect) {
            case (nil, nil):
                break
            case let (g?, e?):
                if g != e {
                    failures.append(RowFailure(vector: vector.name, opIndex: i,
                        detail: "read t=\(t): got \(g), expect \(e)"))
                }
            default:
                let gotStr = got.map { String($0) } ?? "nil"
                let expectStr = expect.map { String($0) } ?? "nil"
                failures.append(RowFailure(vector: vector.name, opIndex: i,
                    detail: "read t=\(t): got \(gotStr), expect \(expectStr)"))
            }
        }
    }
    return failures
}

var productFailures = 0
for v in vectors {
    let failures = replayProduct(v)
    if failures.isEmpty {
        print("  PRODUCT PASS \(v.name)")
    } else {
        productFailures += failures.count
        for f in failures { print("  PRODUCT FAIL \(f.vector) op[\(f.opIndex)]: \(f.detail)") }
    }
}
if productFailures > 0 {
    print("timepos-vector-tests: FAIL - \(productFailures) vector row(s) red against the REAL PlayheadTracker (divergence from prose pin - report, do not guess)")
    exit(1)
}
print("timepos-vector-tests: real PlayheadTracker matches the pinned semantics on all vectors")

if totalFailures > 0 {
    print("timepos-tests: FAIL - \(totalFailures) vector row(s) red against the candidate tracker")
    exit(1)
}

// 2) Negative controls (packet acceptance: "a seeded drift beyond the cap fails").
// Each seeded fault must produce at least one replay failure; a fault that
// replays green means the vectors do not guard the pinned behaviour.
let negativeControls: [(Fault, String)] = [
    (.seededDrift,      "seeded drift beyond the cap (0 backwards movement)"),
    (.noMonotonicClamp, "monotonic clamp removed (pause/duration handling kept honest)"),
    (.pauseLeak,        "pure freeze break: pause/resume ops ignored, elapsed keeps accruing"),
    (.noDurationCap,    "duration cap removed (no EOF clamp)"),
    (.staleAfterSeek,   "stale value after null-anchor seekCommitted (nil-until-first-frame broken)"),
]
var controlsOk = 0
for (fault, label) in negativeControls {
    var controlFailures = 0
    var firstRed: RowFailure? = nil
    for v in vectors {
        let fs = replay(v, fault: fault)
        if !fs.isEmpty {
            controlFailures += fs.count
            if firstRed == nil { firstRed = fs[0] }
        }
    }
    if controlFailures > 0, let r = firstRed {
        controlsOk += 1
        print("  NEG-CTRL PASS [\(label)]: replay red as required (\(controlFailures) row(s); first: \(r.vector) op[\(r.opIndex)] \(r.detail))")
    } else {
        exitCode = 1
        print("  NEG-CTRL FAIL [\(label)]: seeded fault replayed GREEN - vectors do not catch it")
    }
}

if exitCode == 0 {
    print("timepos-tests: all pass")
} else {
    print("timepos-tests: FAIL - negative control(s) did not trip")
}
exit(exitCode)
