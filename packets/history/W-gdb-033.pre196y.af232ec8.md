# W-gdb-033 time-position tracker vector pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-033

```packet-json
{
  "packet_id": "W-gdb-033",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
      "excerpt_block": "source1_1"
    },
    {
      "path": "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
      "excerpt_block": "source1_2"
    }
  ],
  "interface": {
    "signatures": "read(clockNow: Double, durationSeconds: Double?) -> Double? (monotonic within a generation; duration cap wins)",
    "types": "PlayheadTracker generation semantics (excerpt-level pin); TimePosGate 4/s; NO drift-correction pass exists at the pin - clamp to last value is the only guard",
    "ownership_lifetime": "value tracker; virtual clock; monotonic-within-generation + duration cap are the only guards",
    "caller": "time-pos vector checker",
    "callee": "PlayheadTracker.read(clockNow:durationSeconds:) + seekCommitted + TimePosGate.offer (pinned below)"
  },
  "test": {
    "command": "swift run timepos-tests",
    "expected": "exit 0; final line 'timepos-tests: all pass'; vector rows replay green; a backwards-movement row asserts the monotonic clamp exactly",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/timepos-vectors/",
      "Sources/timepos-tests/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/timepos-tests/main.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run timepos-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:18:24.024356+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "timepos-tests: all pass",
    "inline_files": [
      {
        "path": "Sources/timepos-tests/main.swift",
        "block": "rf1",
        "sha256": "982d540adc725974cb4740c46d8d3e719e0f7bb0bc983992a6ffd011a3ecb886"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "94fc31f75c1aae8c17719baa762c5166a5f90e2a3448c144cd16817b32bdee70",
    "last_5_lines": [
      "PASS V1 first set emits",
      "PASS V2 same value quiet",
      "PASS V3 change emits once",
      "PASS V4 NaN and infinity never emit",
      "timepos-tests: all pass"
    ],
    "receipt_sha256": "6001a78814b9dfcef8b73023c7008b7abb717c3f2398daf568322a1b4df5c63b"
  }
}
```

## problem (what fails for the user)
time-pos must freeze while paused, re-anchor at first presented frame after seek, and clamp at EOF; the snapshot's timePositionSeconds carries this to the user, and a tracker regression shows as a drifting or jumping time display.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4; snapshot fields incl. timePositionSeconds below, lines 127-160).
- real test command: the returned checker runs on Linux against a candidate tracker.

## expected behaviour
vectors: anchor re-arm at first presented frame, freeze while paused, monotonic-in-generation clamp (the pinned drift guard), seek repositioning, EOF clamp; expected time-pos sequences at stated sample instants.

## exact call site and interface
the snapshot's timePositionSeconds + anchor fields (pinned excerpt) are the asserted surface.

## pinned ABI decisions (integrator, 2026-11-15; drift semantics pinned - correction)
there is NO drift-correction pass at the pin, so the atlas does not invent one. the real caps (PlayheadTracker.read, PlayheadPosition.swift, same pin): value = anchor + played elapsed; MONOTONIC within a generation - a computed decrease is clamped to the last emitted value (that clamp is the only drift guard, so "the drift cap" = 0 backwards movement); duration cap wins at EOF (out > durationSeconds clamps to durationSeconds); freeze while paused is exact (running == false adds no elapsed); seekCommitted re-arms: generation += 1, anchor replaced, nil anchor reads nil until the next firstFrame. the earlier "bounded drift correction (cap per interval)" expectation is REPLACED by these pinned rules; vectors assert the monotonic clamp and the duration clamp with exact values.

## behaviour that must not change
freeze-while-paused stays exact (the b-gate B1 contract); virtual clock only.

## acceptance test (from the product repo)
vectors replay green; a seeded drift beyond the cap fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 127-146 of 1537)
```swift id=source1
public struct EmbeddedSnapshot: Sendable, Equatable {
    /// Read-only measured diagnostics. Sequence is local to this session.
    public var seekTrace: [String] = []
    public var audioFirstAdmissionWallSeconds: [Double] = []
    public var audioLandingFirstSampleSeconds: [Double] = []
    /// Pace-anchor media seconds (set at the first frame decision of
    /// the current presentation generation; reset on seek). This is
    /// the actual presentation anchor, not a sampled playhead; nil
    /// before the first frame.
    public var anchorMediaSeconds: Double?
    public var isPaused: Bool?
    /// nil: no honest duration source exists at the pin.
    public var timePositionSeconds: Double?
    /// G3: presented frame size, drawable size and on-screen video rect incl. the host transform.
    /// nil before the first presented frame.
    public var effectiveVideo: EffectiveVideoGeometry?
    public var durationSeconds: Double?
    /// Terminal pump counters from the actual PumpStats of the last
    /// finished pump run (EOS, cancel, failure or windowClosed).
    /// nil while no pump run has ended in this session - never a
```

### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 148-154 of 1537)
```swift id=source1_1
    public var shown: Int?
    public var dropped: Int?
    public var waits: Int?
    /// Real plane state + generation (never a constant).
    public var lifecycle: PlayerLifecycleState = .idle
    public var generation: UInt64 = 0
    /// native87 B-gate LIVE fields (additive; nil = honest absence, never a
```

### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 156-160 of 1537)
```swift id=source1_2
    /// pump while open, the terminal PumpStats.shown once the pump ended.
    public var presentedFrames: Int?
    /// Real AudioUnit render callbacks (every buffer render, all silence
    /// forms included). nil while no audio unit exists.
    public var audioCallbacks: UInt64?
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"duration":60,"ops":[{"firstFrame":{"anchor":10,"t":0}},{"read":{"t":1},"expect":11},{"read":{"t":0.5},"expect":11},{"seekCommitted":{"anchor":null,"t":2}},{"read":{"t":3},"expect":null}],"note":"monotonic clamp + nil-until-first-frame-of-new-generation"}
```

```text id=rf1
// Sources/timepos-tests/main.swift  (step 2; exit 0 = all pass, 1 = any fail)
import GorAVPlaybackCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print(ok ? "PASS \(name)" : "FAIL \(name)")
    if !ok { failures += 1 }
}
func pure(_ a: Double?, _ p: Double, _ d: Double? = nil) -> Double? {
    playheadSeconds(anchor: a, playedSeconds: p, durationSeconds: d)
}

// Pure function (step 1b)
check("P1 zero played gives anchor", pure(2.5, 0) == 2.5)
check("P2 played adds", pure(2.5, 1.5) == 4.0)
check("P3 clamped to duration", pure(9, 5, 10) == 10)
check("P4 unknown duration not clamped", pure(9, 5, nil) == 14)
check("P5 nil anchor gives nil", pure(nil, 5) == nil)
check("P6 negative played counts as 0", pure(1, -3) == 1)
check("P7 NaN played counts as 0", pure(1, Double.nan) == 1)
check("P8 overflow to infinity is never published", pure(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude) == nil)
check("P9 infinite anchor gives nil", pure(Double.infinity, 1) == nil)

// Tracker (step 1b)
var t = PlayheadTracker()
check("K1 nil before first frame", t.read(clockNow: 100, durationSeconds: nil) == nil)
t.firstFrame(anchor: 2.5, clockNow: 100, generation: t.generation)
check("K2 playing advances", t.read(clockNow: 109, durationSeconds: nil) == 11.5)
t.pause(clockNow: 109)
check("K3 first read after pause freezes at 11.5", t.read(clockNow: 150, durationSeconds: nil) == 11.5)
check("K4 still frozen later", t.read(clockNow: 400, durationSeconds: nil) == 11.5)
t.resume(clockNow: 400)
check("K5 resume continues from frozen position", t.read(clockNow: 402, durationSeconds: nil) == 13.5)
var u = PlayheadTracker()
u.firstFrame(anchor: 0, clockNow: 10, generation: u.generation)
u.pause(clockNow: 13)
check("K6 pause with no prior read freezes at 3", u.read(clockNow: 99, durationSeconds: nil) == 3)
var s = PlayheadTracker()
s.firstFrame(anchor: 0, clockNow: 0, generation: s.generation)
_ = s.read(clockNow: 8, durationSeconds: nil)
s.seekCommitted(anchor: 1.0, clockNow: 8, wasPaused: false)
check("K7 seek bumps generation", s.generation == 1)
check("K8 seek may lower the position", s.read(clockNow: 8, durationSeconds: nil) == 1.0)
s.seekCommitted(anchor: 5.0, clockNow: 20, wasPaused: true)
check("K9 paused seek stays at target", s.read(clockNow: 60, durationSeconds: nil) == 5.0)
s.seekCommitted(anchor: nil, clockNow: 61, wasPaused: false)
check("K10 seek without anchor reads nil until first frame", s.read(clockNow: 62, durationSeconds: nil) == nil)
var j = PlayheadTracker()
j.firstFrame(anchor: 0, clockNow: 0, generation: j.generation)
let j1 = j.read(clockNow: 2.0, durationSeconds: nil)
let j2 = j.read(clockNow: 1.0, durationSeconds: nil)
check("K11 backwards clock held within generation", j1 == 2.0 && j2 == 2.0)
var o = PlayheadTracker()
o.firstFrame(anchor: Double.greatestFiniteMagnitude, clockNow: 0, generation: o.generation)
check("K12 tracker never publishes non-finite", o.read(clockNow: Double.greatestFiniteMagnitude, durationSeconds: nil) != Double.infinity)

// Composition: paused seek -> late firstFrame stays frozen (step 2)
var c = PlayheadTracker()
c.firstFrame(anchor: 0, clockNow: 0, generation: c.generation)
c.pause(clockNow: 5)                                   // user pauses at 5
c.seekCommitted(anchor: nil, clockNow: 6, wasPaused: true)  // paused seek, pump anchor not yet set
check("C1 paused seek reads nil before the late first frame", c.read(clockNow: 7, durationSeconds: nil) == nil)
c.firstFrame(anchor: 30, clockNow: 9, generation: c.generation)                  // late first frame while paused
check("C2 late first frame while paused reads the anchor", c.read(clockNow: 9, durationSeconds: nil) == 30)
check("C3 and stays frozen, clock keeps running", c.read(clockNow: 40, durationSeconds: nil) == 30)
c.resume(clockNow: 40)
check("C4 resume advances from the anchor", c.read(clockNow: 42, durationSeconds: nil) == 32)
// pause intent set before the first frame of a fresh open
var f = PlayheadTracker()
f.pause(clockNow: 1)
f.firstFrame(anchor: 0, clockNow: 2, generation: f.generation)
check("C5 pause before first frame is honored", f.read(clockNow: 50, durationSeconds: nil) == 0)
f.resume(clockNow: 50)
check("C6 resume after that advances", f.read(clockNow: 51, durationSeconds: nil) == 1)
// unpaused seek with late first frame runs from the late frame, not from seek time
var n = PlayheadTracker()
n.firstFrame(anchor: 0, clockNow: 0, generation: n.generation)
n.seekCommitted(anchor: nil, clockNow: 3, wasPaused: false)
n.firstFrame(anchor: 20, clockNow: 4, generation: n.generation)
check("C7 unpaused late first frame runs from the frame clock", n.read(clockNow: 6, durationSeconds: nil) == 22)

// Step 1c review items
// (1) paused seek without anchor: late first frame must NOT resume
var r1 = PlayheadTracker()
r1.firstFrame(anchor: 0, clockNow: 0, generation: r1.generation)
r1.seekCommitted(anchor: nil, clockNow: 61, wasPaused: true)
r1.firstFrame(anchor: 5, clockNow: 62, generation: r1.generation)
check("R1 first-frame arrival does not resume a paused seek", r1.read(clockNow: 72, durationSeconds: nil) == 5)
// (2) duplicate firstFrame in one generation is ignored, no rewind
var r2 = PlayheadTracker()
check("R2a first firstFrame accepted", r2.firstFrame(anchor: 0, clockNow: 0, generation: r2.generation) == true)
check("R2b read 10", r2.read(clockNow: 10, durationSeconds: nil) == 10)
check("R2c duplicate firstFrame rejected", r2.firstFrame(anchor: 1, clockNow: 11, generation: r2.generation) == false)
check("R2d no rewind after duplicate", r2.read(clockNow: 11, durationSeconds: nil) == 11)
r2.seekCommitted(anchor: nil, clockNow: 12, wasPaused: false)
check("R2e new generation accepts a firstFrame again", r2.firstFrame(anchor: 3, clockNow: 13, generation: r2.generation) == true)
// (3) duration cap wins over the monotonic hold
var r3 = PlayheadTracker()
r3.firstFrame(anchor: 0, clockNow: 0, generation: r3.generation)
check("R3a read before duration known", r3.read(clockNow: 12, durationSeconds: nil) == 12)
check("R3b duration then known smaller: capped, not held above", r3.read(clockNow: 13, durationSeconds: 10) == 10)
check("R3c stays at the cap", r3.read(clockNow: 14, durationSeconds: 10) == 10)

// Step 3: generation-bound first frame (stale watch callbacks)
var w = PlayheadTracker()
check("W1 gen 0 first frame accepted", w.firstFrame(anchor: 0, clockNow: 0, generation: 0) == true)
check("W2 playing reads 10 at clock 10", w.read(clockNow: 10, durationSeconds: nil) == 10)
w.seekCommitted(anchor: nil, clockNow: 11, wasPaused: false)   // seek in flight, new anchor not yet set
check("W3 stale first frame (gen 0) after seek is ignored", w.firstFrame(anchor: 3, clockNow: 12, generation: 0) == false)
check("W4 stale callback left no anchor: reads nil", w.read(clockNow: 13, durationSeconds: nil) == nil)
check("W5 future generation is ignored too", w.firstFrame(anchor: 9, clockNow: 13, generation: 2) == false && w.read(clockNow: 14, durationSeconds: nil) == nil)
check("W6 current generation first frame accepted", w.firstFrame(anchor: 40, clockNow: 15, generation: 1) == true)
check("W7 timePos follows the NEW anchor", w.read(clockNow: 17, durationSeconds: nil) == 42)
check("W8 a late stale call after acceptance changes nothing", w.firstFrame(anchor: 3, clockNow: 18, generation: 0) == false && w.read(clockNow: 18, durationSeconds: nil) == 43)
// two seeks in a row: first watch (gen 1) must not bind gen 2
var w2 = PlayheadTracker()
w2.firstFrame(anchor: 0, clockNow: 0, generation: 0)
w2.seekCommitted(anchor: nil, clockNow: 1, wasPaused: false)
w2.seekCommitted(anchor: nil, clockNow: 2, wasPaused: false)
check("W9 watch started for gen 1 cannot bind gen 2", w2.firstFrame(anchor: 5, clockNow: 3, generation: 1) == false && w2.read(clockNow: 4, durationSeconds: nil) == nil)
check("W10 gen 2 watch binds", w2.firstFrame(anchor: 8, clockNow: 5, generation: 2) == true && w2.read(clockNow: 6, durationSeconds: nil) == 9)
// stale call while paused seek: still no resume, no anchor
var w3 = PlayheadTracker()
w3.firstFrame(anchor: 0, clockNow: 0, generation: 0)
w3.seekCommitted(anchor: nil, clockNow: 1, wasPaused: true)
check("W11 stale first frame during a paused seek is ignored", w3.firstFrame(anchor: 2, clockNow: 2, generation: 0) == false && w3.read(clockNow: 9, durationSeconds: nil) == nil)
check("W12 later correct first frame stays frozen", w3.firstFrame(anchor: 30, clockNow: 10, generation: 1) == true && w3.read(clockNow: 50, durationSeconds: nil) == 30)
// single-clock contract: a NaN clock (lost audio master) never publishes NaN
var w4 = PlayheadTracker()
w4.firstFrame(anchor: 5, clockNow: 0, generation: 0)
check("W13 NaN clock read holds the last finite value, never NaN", w4.read(clockNow: 2, durationSeconds: nil) == 7 && w4.read(clockNow: Double.nan, durationSeconds: nil) == 7)
var w5 = PlayheadTracker()
w5.firstFrame(anchor: 5, clockNow: Double.nan, generation: 0)
check("W14 NaN clock at first frame: next finite sample is adopted as run start, never NaN", w5.read(clockNow: 3, durationSeconds: nil) == 5 && w5.read(clockNow: 5, durationSeconds: nil) == 7)
var w6 = PlayheadTracker()
w6.firstFrame(anchor: 0, clockNow: 0, generation: 0)
w6.seekCommitted(anchor: 10, clockNow: Double.nan, wasPaused: false)
check("W15 seek with NaN clock heals on the next finite sample", w6.read(clockNow: 4, durationSeconds: nil) == 10 && w6.read(clockNow: 6, durationSeconds: nil) == 12)
var w7 = PlayheadTracker()
w7.firstFrame(anchor: 0, clockNow: 0, generation: 0)
w7.pause(clockNow: 2)
w7.resume(clockNow: Double.nan)
check("W16 resume with NaN clock heals, position continues from the frozen 2", w7.read(clockNow: 10, durationSeconds: nil) == 2 && w7.read(clockNow: 13, durationSeconds: nil) == 5)

// Duration helper (T6 pure part)
check("D1 microseconds to seconds", containerDurationSeconds(ticks: 10_000_000) == 10.0)
check("D2 nil is unknown, not 0", containerDurationSeconds(ticks: nil) == nil)
check("D3 zero is unknown", containerDurationSeconds(ticks: 0) == nil)
check("D4 negative is unknown", containerDurationSeconds(ticks: -5) == nil)
check("D5 Int64.min is unknown", containerDurationSeconds(ticks: Int64.min) == nil)
check("D6 custom tick rate", containerDurationSeconds(ticks: 90_000, ticksPerSecond: 90_000) == 1.0)
check("D7 bad tick rate is unknown", containerDurationSeconds(ticks: 5, ticksPerSecond: 0) == nil)

// timePos gate (4 per second, only on change)
var g = TimePosGate(maxPerSecond: 4)
check("G1 first value emits", g.offer(1.0, clockNow: 0.0) == 1.0)
check("G2 within 0.25 s is quiet", g.offer(1.1, clockNow: 0.1) == nil)
check("G3 after 0.25 s emits", g.offer(1.3, clockNow: 0.26) == 1.3)
check("G4 unchanged value is quiet", g.offer(1.3, clockNow: 5.0) == nil)
check("G5 nil and NaN never emit", g.offer(nil, clockNow: 6) == nil && g.offer(Double.nan, clockNow: 7) == nil)
check("G6 new generation emits immediately", g.offer(0.5, clockNow: 7.01, newGeneration: true) == 0.5)
var rate = TimePosGate(maxPerSecond: 4)
var emitted = 0
for i in 0..<100 { if rate.offer(Double(i), clockNow: Double(i) * 0.01) != nil { emitted += 1 } }
check("G7 100 changes over 1 s emit at most 5", emitted <= 5 && emitted >= 4)

// Adversarial clock (step 1d)
var a = TimePosGate(maxPerSecond: 4)
check("A1 first emits at clock 10", a.offer(1, clockNow: 10) == 1)
check("A2 backwards clock does not bypass the limit", a.offer(2, clockNow: 5) == nil)
check("A3 NaN clock never emits", a.offer(3, clockNow: Double.nan) == nil)
check("A4 infinite clock never emits", a.offer(4, clockNow: Double.infinity) == nil && a.offer(4, clockNow: -Double.infinity) == nil)
check("A5 gate still works after bad samples", a.offer(5, clockNow: 10.3) == 5)
var a2 = TimePosGate(maxPerSecond: 4)
_ = a2.offer(1, clockNow: 100)
var flood = 0
for i in 0..<50 { if a2.offer(Double(i + 2), clockNow: 100 - Double(i) * 0.5) != nil { flood += 1 } }
check("A6 50 backwards-clock samples emit nothing", flood == 0)
check("A7 new generation resets the clock reference, backwards allowed", a2.offer(9, clockNow: 1.0, newGeneration: true) == 9)
check("A8 after reset spacing applies from the new clock", a2.offer(10, clockNow: 1.1) == nil && a2.offer(10, clockNow: 1.3) == 10)
var a3 = TimePosGate(maxPerSecond: 0)
check("A9 zero rate means no spacing limit, still dedupes", a3.offer(1, clockNow: 0) == 1 && a3.offer(1, clockNow: 0) == nil && a3.offer(2, clockNow: 0) == 2)

// volumeChanged gate (T7)
var v = VolumeChangeGate()
check("V1 first set emits", v.offer(0.5) == 0.5)
check("V2 same value quiet", v.offer(0.5) == nil)
check("V3 change emits once", v.offer(0.8) == 0.8 && v.offer(0.8) == nil)
check("V4 NaN and infinity never emit", v.offer(Float.nan) == nil && v.offer(Float.infinity) == nil)

print(failures == 0 ? "timepos-tests: all pass" : "timepos-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-v5oix0z6/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Emitting module GorAVCore
[8/15] Compiling GorAVCore AdmissionTable.swift
[9/15] Compiling GorAVCore Boundary.swift
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/41] Emitting module GorAVPlaybackCore
[22/57] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[23/57] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[24/57] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[25/57] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[26/57] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[27/57] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[28/57] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[29/57] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[30/57] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[31/57] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[32/57] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[33/57] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[34/57] Compiling GorAVPlaybackCore Lane0Contract.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[35/57] Compiling GorAVPlaybackCore LifetimeRegistry.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[36/57] Compiling GorAVPlaybackCore ObservationSurface.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[37/57] Compiling GorAVPlaybackCore PlayArguments.swift
/tmp/packet-proof-v5oix0z6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[38/57] Compiling GorAVPlaybackCore PlaybackCore.swift
[39/57] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[40/57] Compiling GorAVPlaybackCore PlayheadObservers.swift
[41/57] Compiling GorAVPlaybackCore PlayheadPosition.swift
[42/57] Compiling GorAVPlaybackCore PreparedAdoption.swift
[43/57] Compiling GorAVPlaybackCore PreparedShotSession.swift
[44/57] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[45/57] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[46/57] Compiling GorAVPlaybackCore RenderGraph.swift
[47/57] Compiling GorAVPlaybackCore SPSC.swift
[48/57] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[49/57] Compiling GorAVPlaybackCore StageGeometry.swift
[50/57] Compiling GorAVPlaybackCore TapCropDetector.swift
[51/57] Compiling GorAVPlaybackCore TimingLedger.swift
[52/57] Compiling GorAVPlaybackCore UniformPacking.swift
[53/57] Compiling GorAVPlaybackCore WindowModePlan.swift
[54/58] Wrapping AST for GorAVPlaybackCore for debugging
[56/60] Emitting module timepos_tests
[57/60] Compiling timepos_tests main.swift
[58/61] Wrapping AST for timepos-tests for debugging
[59/61] Write Objects.LinkFileList
[60/61] Linking timepos-tests
Build complete! (6.50s)
PASS P1 zero played gives anchor
PASS P2 played adds
PASS P3 clamped to duration
PASS P4 unknown duration not clamped
PASS P5 nil anchor gives nil
PASS P6 negative played counts as 0
PASS P7 NaN played counts as 0
PASS P8 overflow to infinity is never published
PASS P9 infinite anchor gives nil
PASS K1 nil before first frame
PASS K2 playing advances
PASS K3 first read after pause freezes at 11.5
PASS K4 still frozen later
PASS K5 resume continues from frozen position
PASS K6 pause with no prior read freezes at 3
PASS K7 seek bumps generation
PASS K8 seek may lower the position
PASS K9 paused seek stays at target
PASS K10 seek without anchor reads nil until first frame
PASS K11 backwards clock held within generation
PASS K12 tracker never publishes non-finite
PASS C1 paused seek reads nil before the late first frame
PASS C2 late first frame while paused reads the anchor
PASS C3 and stays frozen, clock keeps running
PASS C4 resume advances from the anchor
PASS C5 pause before first frame is honored
PASS C6 resume after that advances
PASS C7 unpaused late first frame runs from the frame clock
PASS R1 first-frame arrival does not resume a paused seek
PASS R2a first firstFrame accepted
PASS R2b read 10
PASS R2c duplicate firstFrame rejected
PASS R2d no rewind after duplicate
PASS R2e new generation accepts a firstFrame again
PASS R3a read before duration known
PASS R3b duration then known smaller: capped, not held above
PASS R3c stays at the cap
PASS W1 gen 0 first frame accepted
PASS W2 playing reads 10 at clock 10
PASS W3 stale first frame (gen 0) after seek is ignored
PASS W4 stale callback left no anchor: reads nil
PASS W5 future generation is ignored too
PASS W6 current generation first frame accepted
PASS W7 timePos follows the NEW anchor
PASS W8 a late stale call after acceptance changes nothing
PASS W9 watch started for gen 1 cannot bind gen 2
PASS W10 gen 2 watch binds
PASS W11 stale first frame during a paused seek is ignored
PASS W12 later correct first frame stays frozen
PASS W13 NaN clock read holds the last finite value, never NaN
PASS W14 NaN clock at first frame: next finite sample is adopted as run start, never NaN
PASS W15 seek with NaN clock heals on the next finite sample
PASS W16 resume with NaN clock heals, position continues from the frozen 2
PASS D1 microseconds to seconds
PASS D2 nil is unknown, not 0
PASS D3 zero is unknown
PASS D4 negative is unknown
PASS D5 Int64.min is unknown
PASS D6 custom tick rate
PASS D7 bad tick rate is unknown
PASS G1 first value emits
PASS G2 within 0.25 s is quiet
PASS G3 after 0.25 s emits
PASS G4 unchanged value is quiet
PASS G5 nil and NaN never emit
PASS G6 new generation emits immediately
PASS G7 100 changes over 1 s emit at most 5
PASS A1 first emits at clock 10
PASS A2 backwards clock does not bypass the limit
PASS A3 NaN clock never emits
PASS A4 infinite clock never emits
PASS A5 gate still works after bad samples
PASS A6 50 backwards-clock samples emit nothing
PASS A7 new generation resets the clock reference, backwards allowed
PASS A8 after reset spacing applies from the new clock
PASS A9 zero rate means no spacing limit, still dedupes
PASS V1 first set emits
PASS V2 same value quiet
PASS V3 change emits once
PASS V4 NaN and infinity never emit
timepos-tests: all pass
```
