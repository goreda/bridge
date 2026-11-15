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
  "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
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
    "branch": "main",
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
        "block": "rf0",
        "content": "// Sources/timepos-tests/main.swift  (step 2; exit 0 = all pass, 1 = any fail)\nimport GorAVPlaybackCore\n#if canImport(Glibc)\nimport Glibc\n#else\nimport Darwin\n#endif\n\nvar failures = 0\nfunc check(_ name: String, _ ok: Bool) {\n    print(ok ? \"PASS \\(name)\" : \"FAIL \\(name)\")\n    if !ok { failures += 1 }\n}\nfunc pure(_ a: Double?, _ p: Double, _ d: Double? = nil) -> Double? {\n    playheadSeconds(anchor: a, playedSeconds: p, durationSeconds: d)\n}\n\n// Pure function (step 1b)\ncheck(\"P1 zero played gives anchor\", pure(2.5, 0) == 2.5)\ncheck(\"P2 played adds\", pure(2.5, 1.5) == 4.0)\ncheck(\"P3 clamped to duration\", pure(9, 5, 10) == 10)\ncheck(\"P4 unknown duration not clamped\", pure(9, 5, nil) == 14)\ncheck(\"P5 nil anchor gives nil\", pure(nil, 5) == nil)\ncheck(\"P6 negative played counts as 0\", pure(1, -3) == 1)\ncheck(\"P7 NaN played counts as 0\", pure(1, Double.nan) == 1)\ncheck(\"P8 overflow to infinity is never published\", pure(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude) == nil)\ncheck(\"P9 infinite anchor gives nil\", pure(Double.infinity, 1) == nil)\n\n// Tracker (step 1b)\nvar t = PlayheadTracker()\ncheck(\"K1 nil before first frame\", t.read(clockNow: 100, durationSeconds: nil) == nil)\nt.firstFrame(anchor: 2.5, clockNow: 100, generation: t.generation)\ncheck(\"K2 playing advances\", t.read(clockNow: 109, durationSeconds: nil) == 11.5)\nt.pause(clockNow: 109)\ncheck(\"K3 first read after pause freezes at 11.5\", t.read(clockNow: 150, durationSeconds: nil) == 11.5)\ncheck(\"K4 still frozen later\", t.read(clockNow: 400, durationSeconds: nil) == 11.5)\nt.resume(clockNow: 400)\ncheck(\"K5 resume continues from frozen position\", t.read(clockNow: 402, durationSeconds: nil) == 13.5)\nvar u = PlayheadTracker()\nu.firstFrame(anchor: 0, clockNow: 10, generation: u.generation)\nu.pause(clockNow: 13)\ncheck(\"K6 pause with no prior read freezes at 3\", u.read(clockNow: 99, durationSeconds: nil) == 3)\nvar s = PlayheadTracker()\ns.firstFrame(anchor: 0, clockNow: 0, generation: s.generation)\n_ = s.read(clockNow: 8, durationSeconds: nil)\ns.seekCommitted(anchor: 1.0, clockNow: 8, wasPaused: false)\ncheck(\"K7 seek bumps generation\", s.generation == 1)\ncheck(\"K8 seek may lower the position\", s.read(clockNow: 8, durationSeconds: nil) == 1.0)\ns.seekCommitted(anchor: 5.0, clockNow: 20, wasPaused: true)\ncheck(\"K9 paused seek stays at target\", s.read(clockNow: 60, durationSeconds: nil) == 5.0)\ns.seekCommitted(anchor: nil, clockNow: 61, wasPaused: false)\ncheck(\"K10 seek without anchor reads nil until first frame\", s.read(clockNow: 62, durationSeconds: nil) == nil)\nvar j = PlayheadTracker()\nj.firstFrame(anchor: 0, clockNow: 0, generation: j.generation)\nlet j1 = j.read(clockNow: 2.0, durationSeconds: nil)\nlet j2 = j.read(clockNow: 1.0, durationSeconds: nil)\ncheck(\"K11 backwards clock held within generation\", j1 == 2.0 && j2 == 2.0)\nvar o = PlayheadTracker()\no.firstFrame(anchor: Double.greatestFiniteMagnitude, clockNow: 0, generation: o.generation)\ncheck(\"K12 tracker never publishes non-finite\", o.read(clockNow: Double.greatestFiniteMagnitude, durationSeconds: nil) != Double.infinity)\n\n// Composition: paused seek -> late firstFrame stays frozen (step 2)\nvar c = PlayheadTracker()\nc.firstFrame(anchor: 0, clockNow: 0, generation: c.generation)\nc.pause(clockNow: 5)                                   // user pauses at 5\nc.seekCommitted(anchor: nil, clockNow: 6, wasPaused: true)  // paused seek, pump anchor not yet set\ncheck(\"C1 paused seek reads nil before the late first frame\", c.read(clockNow: 7, durationSeconds: nil) == nil)\nc.firstFrame(anchor: 30, clockNow: 9, generation: c.generation)                  // late first frame while paused\ncheck(\"C2 late first frame while paused reads the anchor\", c.read(clockNow: 9, durationSeconds: nil) == 30)\ncheck(\"C3 and stays frozen, clock keeps running\", c.read(clockNow: 40, durationSeconds: nil) == 30)\nc.resume(clockNow: 40)\ncheck(\"C4 resume advances from the anchor\", c.read(clockNow: 42, durationSeconds: nil) == 32)\n// pause intent set before the first frame of a fresh open\nvar f = PlayheadTracker()\nf.pause(clockNow: 1)\nf.firstFrame(anchor: 0, clockNow: 2, generation: f.generation)\ncheck(\"C5 pause before first frame is honored\", f.read(clockNow: 50, durationSeconds: nil) == 0)\nf.resume(clockNow: 50)\ncheck(\"C6 resume after that advances\", f.read(clockNow: 51, durationSeconds: nil) == 1)\n// unpaused seek with late first frame runs from the late frame, not from seek time\nvar n = PlayheadTracker()\nn.firstFrame(anchor: 0, clockNow: 0, generation: n.generation)\nn.seekCommitted(anchor: nil, clockNow: 3, wasPaused: false)\nn.firstFrame(anchor: 20, clockNow: 4, generation: n.generation)\ncheck(\"C7 unpaused late first frame runs from the frame clock\", n.read(clockNow: 6, durationSeconds: nil) == 22)\n\n// Step 1c review items\n// (1) paused seek without anchor: late first frame must NOT resume\nvar r1 = PlayheadTracker()\nr1.firstFrame(anchor: 0, clockNow: 0, generation: r1.generation)\nr1.seekCommitted(anchor: nil, clockNow: 61, wasPaused: true)\nr1.firstFrame(anchor: 5, clockNow: 62, generation: r1.generation)\ncheck(\"R1 first-frame arrival does not resume a paused seek\", r1.read(clockNow: 72, durationSeconds: nil) == 5)\n// (2) duplicate firstFrame in one generation is ignored, no rewind\nvar r2 = PlayheadTracker()\ncheck(\"R2a first firstFrame accepted\", r2.firstFrame(anchor: 0, clockNow: 0, generation: r2.generation) == true)\ncheck(\"R2b read 10\", r2.read(clockNow: 10, durationSeconds: nil) == 10)\ncheck(\"R2c duplicate firstFrame rejected\", r2.firstFrame(anchor: 1, clockNow: 11, generation: r2.generation) == false)\ncheck(\"R2d no rewind after duplicate\", r2.read(clockNow: 11, durationSeconds: nil) == 11)\nr2.seekCommitted(anchor: nil, clockNow: 12, wasPaused: false)\ncheck(\"R2e new generation accepts a firstFrame again\", r2.firstFrame(anchor: 3, clockNow: 13, generation: r2.generation) == true)\n// (3) duration cap wins over the monotonic hold\nvar r3 = PlayheadTracker()\nr3.firstFrame(anchor: 0, clockNow: 0, generation: r3.generation)\ncheck(\"R3a read before duration known\", r3.read(clockNow: 12, durationSeconds: nil) == 12)\ncheck(\"R3b duration then known smaller: capped, not held above\", r3.read(clockNow: 13, durationSeconds: 10) == 10)\ncheck(\"R3c stays at the cap\", r3.read(clockNow: 14, durationSeconds: 10) == 10)\n\n// Step 3: generation-bound first frame (stale watch callbacks)\nvar w = PlayheadTracker()\ncheck(\"W1 gen 0 first frame accepted\", w.firstFrame(anchor: 0, clockNow: 0, generation: 0) == true)\ncheck(\"W2 playing reads 10 at clock 10\", w.read(clockNow: 10, durationSeconds: nil) == 10)\nw.seekCommitted(anchor: nil, clockNow: 11, wasPaused: false)   // seek in flight, new anchor not yet set\ncheck(\"W3 stale first frame (gen 0) after seek is ignored\", w.firstFrame(anchor: 3, clockNow: 12, generation: 0) == false)\ncheck(\"W4 stale callback left no anchor: reads nil\", w.read(clockNow: 13, durationSeconds: nil) == nil)\ncheck(\"W5 future generation is ignored too\", w.firstFrame(anchor: 9, clockNow: 13, generation: 2) == false && w.read(clockNow: 14, durationSeconds: nil) == nil)\ncheck(\"W6 current generation first frame accepted\", w.firstFrame(anchor: 40, clockNow: 15, generation: 1) == true)\ncheck(\"W7 timePos follows the NEW anchor\", w.read(clockNow: 17, durationSeconds: nil) == 42)\ncheck(\"W8 a late stale call after acceptance changes nothing\", w.firstFrame(anchor: 3, clockNow: 18, generation: 0) == false && w.read(clockNow: 18, durationSeconds: nil) == 43)\n// two seeks in a row: first watch (gen 1) must not bind gen 2\nvar w2 = PlayheadTracker()\nw2.firstFrame(anchor: 0, clockNow: 0, generation: 0)\nw2.seekCommitted(anchor: nil, clockNow: 1, wasPaused: false)\nw2.seekCommitted(anchor: nil, clockNow: 2, wasPaused: false)\ncheck(\"W9 watch started for gen 1 cannot bind gen 2\", w2.firstFrame(anchor: 5, clockNow: 3, generation: 1) == false && w2.read(clockNow: 4, durationSeconds: nil) == nil)\ncheck(\"W10 gen 2 watch binds\", w2.firstFrame(anchor: 8, clockNow: 5, generation: 2) == true && w2.read(clockNow: 6, durationSeconds: nil) == 9)\n// stale call while paused seek: still no resume, no anchor\nvar w3 = PlayheadTracker()\nw3.firstFrame(anchor: 0, clockNow: 0, generation: 0)\nw3.seekCommitted(anchor: nil, clockNow: 1, wasPaused: true)\ncheck(\"W11 stale first frame during a paused seek is ignored\", w3.firstFrame(anchor: 2, clockNow: 2, generation: 0) == false && w3.read(clockNow: 9, durationSeconds: nil) == nil)\ncheck(\"W12 later correct first frame stays frozen\", w3.firstFrame(anchor: 30, clockNow: 10, generation: 1) == true && w3.read(clockNow: 50, durationSeconds: nil) == 30)\n// single-clock contract: a NaN clock (lost audio master) never publishes NaN\nvar w4 = PlayheadTracker()\nw4.firstFrame(anchor: 5, clockNow: 0, generation: 0)\ncheck(\"W13 NaN clock read holds the last finite value, never NaN\", w4.read(clockNow: 2, durationSeconds: nil) == 7 && w4.read(clockNow: Double.nan, durationSeconds: nil) == 7)\nvar w5 = PlayheadTracker()\nw5.firstFrame(anchor: 5, clockNow: Double.nan, generation: 0)\ncheck(\"W14 NaN clock at first frame: next finite sample is adopted as run start, never NaN\", w5.read(clockNow: 3, durationSeconds: nil) == 5 && w5.read(clockNow: 5, durationSeconds: nil) == 7)\nvar w6 = PlayheadTracker()\nw6.firstFrame(anchor: 0, clockNow: 0, generation: 0)\nw6.seekCommitted(anchor: 10, clockNow: Double.nan, wasPaused: false)\ncheck(\"W15 seek with NaN clock heals on the next finite sample\", w6.read(clockNow: 4, durationSeconds: nil) == 10 && w6.read(clockNow: 6, durationSeconds: nil) == 12)\nvar w7 = PlayheadTracker()\nw7.firstFrame(anchor: 0, clockNow: 0, generation: 0)\nw7.pause(clockNow: 2)\nw7.resume(clockNow: Double.nan)\ncheck(\"W16 resume with NaN clock heals, position continues from the frozen 2\", w7.read(clockNow: 10, durationSeconds: nil) == 2 && w7.read(clockNow: 13, durationSeconds: nil) == 5)\n\n// Duration helper (T6 pure part)\ncheck(\"D1 microseconds to seconds\", containerDurationSeconds(ticks: 10_000_000) == 10.0)\ncheck(\"D2 nil is unknown, not 0\", containerDurationSeconds(ticks: nil) == nil)\ncheck(\"D3 zero is unknown\", containerDurationSeconds(ticks: 0) == nil)\ncheck(\"D4 negative is unknown\", containerDurationSeconds(ticks: -5) == nil)\ncheck(\"D5 Int64.min is unknown\", containerDurationSeconds(ticks: Int64.min) == nil)\ncheck(\"D6 custom tick rate\", containerDurationSeconds(ticks: 90_000, ticksPerSecond: 90_000) == 1.0)\ncheck(\"D7 bad tick rate is unknown\", containerDurationSeconds(ticks: 5, ticksPerSecond: 0) == nil)\n\n// timePos gate (4 per second, only on change)\nvar g = TimePosGate(maxPerSecond: 4)\ncheck(\"G1 first value emits\", g.offer(1.0, clockNow: 0.0) == 1.0)\ncheck(\"G2 within 0.25 s is quiet\", g.offer(1.1, clockNow: 0.1) == nil)\ncheck(\"G3 after 0.25 s emits\", g.offer(1.3, clockNow: 0.26) == 1.3)\ncheck(\"G4 unchanged value is quiet\", g.offer(1.3, clockNow: 5.0) == nil)\ncheck(\"G5 nil and NaN never emit\", g.offer(nil, clockNow: 6) == nil && g.offer(Double.nan, clockNow: 7) == nil)\ncheck(\"G6 new generation emits immediately\", g.offer(0.5, clockNow: 7.01, newGeneration: true) == 0.5)\nvar rate = TimePosGate(maxPerSecond: 4)\nvar emitted = 0\nfor i in 0..<100 { if rate.offer(Double(i), clockNow: Double(i) * 0.01) != nil { emitted += 1 } }\ncheck(\"G7 100 changes over 1 s emit at most 5\", emitted <= 5 && emitted >= 4)\n\n// Adversarial clock (step 1d)\nvar a = TimePosGate(maxPerSecond: 4)\ncheck(\"A1 first emits at clock 10\", a.offer(1, clockNow: 10) == 1)\ncheck(\"A2 backwards clock does not bypass the limit\", a.offer(2, clockNow: 5) == nil)\ncheck(\"A3 NaN clock never emits\", a.offer(3, clockNow: Double.nan) == nil)\ncheck(\"A4 infinite clock never emits\", a.offer(4, clockNow: Double.infinity) == nil && a.offer(4, clockNow: -Double.infinity) == nil)\ncheck(\"A5 gate still works after bad samples\", a.offer(5, clockNow: 10.3) == 5)\nvar a2 = TimePosGate(maxPerSecond: 4)\n_ = a2.offer(1, clockNow: 100)\nvar flood = 0\nfor i in 0..<50 { if a2.offer(Double(i + 2), clockNow: 100 - Double(i) * 0.5) != nil { flood += 1 } }\ncheck(\"A6 50 backwards-clock samples emit nothing\", flood == 0)\ncheck(\"A7 new generation resets the clock reference, backwards allowed\", a2.offer(9, clockNow: 1.0, newGeneration: true) == 9)\ncheck(\"A8 after reset spacing applies from the new clock\", a2.offer(10, clockNow: 1.1) == nil && a2.offer(10, clockNow: 1.3) == 10)\nvar a3 = TimePosGate(maxPerSecond: 0)\ncheck(\"A9 zero rate means no spacing limit, still dedupes\", a3.offer(1, clockNow: 0) == 1 && a3.offer(1, clockNow: 0) == nil && a3.offer(2, clockNow: 0) == 2)\n\n// volumeChanged gate (T7)\nvar v = VolumeChangeGate()\ncheck(\"V1 first set emits\", v.offer(0.5) == 0.5)\ncheck(\"V2 same value quiet\", v.offer(0.5) == nil)\ncheck(\"V3 change emits once\", v.offer(0.8) == 0.8 && v.offer(0.8) == nil)\ncheck(\"V4 NaN and infinity never emit\", v.offer(Float.nan) == nil && v.offer(Float.infinity) == nil)\n\nprint(failures == 0 ? \"timepos-tests: all pass\" : \"timepos-tests: \\(failures) FAIL\")\nexit(failures == 0 ? 0 : 1)\n"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
    "command": "swift run timepos-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T23:02:38.361013+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "timepos-tests: all pass",
    "inline_files": [
      {
        "path": "Sources/timepos-tests/main.swift",
        "block": "rf0",
        "sha256": "982d540adc725974cb4740c46d8d3e719e0f7bb0bc983992a6ffd011a3ecb886"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "289c73b7b9f1c43d51f27a9101623a3352647b72fa7d201b75cc7f28c88673a1",
    "last_5_lines": [
      "PASS V1 first set emits",
      "PASS V2 same value quiet",
      "PASS V3 change emits once",
      "PASS V4 NaN and infinity never emit",
      "timepos-tests: all pass"
    ],
    "receipt_sha256": "09f858be795a2c89772894c64efbca2042f702bb5b69da5d03a1c9ea018f6a06"
  }
}
```

## problem (what fails for the user)
time-pos must freeze while paused, re-anchor at first presented frame after seek, and clamp at EOF; the snapshot's timePositionSeconds carries this to the user, and a tracker regression shows as a drifting or jumping time display.

## reproducer
- repo: goreda/gorav @ 91a8b69abe9ce61e31188e3d426477a3f8528ede (branch main).
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


```text id=rf0
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
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-45r349nz/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-45r349nz/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Compiling GorAVCore AdmissionTable.swift
[8/15] Compiling GorAVCore Boundary.swift
[9/15] Emitting module GorAVCore
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-45r349nz/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Compiling timepos_tests main.swift
[68/71] Emitting module timepos_tests
[69/72] Wrapping AST for timepos-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking timepos-tests
Build complete! (7.24s)
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
