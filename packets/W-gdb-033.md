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
