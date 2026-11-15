# W-gdb-029 snapshot consistency property kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-029

```packet-json
{
 "packet_id": "W-gdb-029",
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
  "signatures": "read(clockNow: Double, durationSeconds: Double?) -> Double?; seekCommitted(anchor: Double?, clockNow: Double, wasPaused: Bool); offer(_ value: Double?, clockNow: Double, newGeneration: Bool) -> Double?",
  "types": "PlayheadTracker { generation increments per seek }; TimePosGate(maxPerSecond: 4); EmbeddedSnapshot field set (excerpt in packet)",
  "ownership_lifetime": "value snapshot; virtual clock; nil = honest absence",
  "caller": "snapshot property kit",
  "callee": "EmbeddedSnapshot field surface + PlayheadTracker/TimePosGate semantics (pinned below)"
 },
 "test": {
  "command": "swift run snapshot-property-tests",
  "expected": "exit 0; final line matches '^snapshot-property-tests: [1-9][0-9]* PASS, 0 FAIL$'; every invariant asserted per op step; a seeded counter regression is caught",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/snapshot-property/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
the live snapshot is the gate's evidence surface; if counters can regress, or terminal values change after finish, gate receipts become unfalsifiable.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4; EmbeddedSnapshot below, lines 127-178).
- real test command: the returned property kit runs on Linux against a candidate snapshot surface.

## expected behaviour
a property-test kit: counter monotonicity across pause/seek/close, live-vs-terminal field stability after pump finish, optional fields present exactly when their source exists; randomized op scripts with deterministic seeds; assert every invariant per step.

## exact call site and interface
EmbeddedSnapshot's field set (pinned excerpt) is the asserted surface.

## pinned ABI decisions (integrator, 2026-11-15; op-driver and reset/monotonicity boundary)
- the op driver mutates a candidate surface through the session's real op set: open, pause, resume, seekCommitted, close; the model clock is virtual
- PlayheadTracker (PlayheadPosition.swift, same pin): generation increments on seekCommitted(anchor:clockNow:wasPaused:); read(clockNow:durationSeconds:) is nil before the first frame, MONOTONIC within a generation (a lower candidate clamps to the last emitted value), duration cap wins (out > duration clamps to duration); seek with nil anchor reads nil until the next firstFrame
- TimePosGate (PlayheadObservers.swift): maxPerSecond = 4 (minInterval 0.25s); emit-on-change; a generation change emits the first value immediately and resets the clock reference; a non-finite or backwards clock never emits
- reset/monotonicity boundary (integrator decision, grounded in the pinned fields): cumulative counters (seekCommittedCount, presentedFrames, audio* counters) never decrease within a session and are NOT reset by seeks (a seek bumps generation only); a NEW source open starts a fresh counter set. terminal fields (shown/dropped/waits, pumpEndReason) are written once at pump end and never change afterwards (the snapshot excerpt above).

## behaviour that must not change
the field semantics at the pin stay; nil-when-source-absent stays honest.

## acceptance test (from the product repo)
the kit's invariants hold against a reference driver; a seeded counter regression is caught.

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

### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 156-178 of 1537)
```swift id=source1_2
    /// pump while open, the terminal PumpStats.shown once the pump ended.
    public var presentedFrames: Int?
    /// Real AudioUnit render callbacks (every buffer render, all silence
    /// forms included). nil while no audio unit exists.
    public var audioCallbacks: UInt64?
    /// Intentional-pause silence frames rendered while quiesced (the real
    /// pause contract's own counter, AudioUnitSink.pausedSilenceFrames).
    public var audioIntentionalSilenceFrames: UInt64?
    /// Real ring content frames delivered to the unit (underrun shortfall
    /// excluded). nil while no audio unit exists.
    public var audioNonSilenceFrames: UInt64?
    /// Seeks committed this session. Pair with seekTrace and
    /// audioLandingFirstSampleSeconds for the landing witnesses.
    public var seekCommittedCount: UInt64 = 0
    /// The pump reached its typed endOfStream terminal reason. Never
    /// inferred from counters or playhead position.
    public var eofReached = false
    /// The pump's typed terminal reason (rawValue); nil while running.
    public var pumpEndReason: String?
    public init() {}
}

@MainActor
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"seed":7,"ops":["open","pause","resume","seekCommitted","close"],"invariants":["counters.monotonic_within_session","seek_bumps_generation_not_counters","terminal_fields_frozen_after_pump_end","nil_when_source_absent"]}
```
