# W-gdb-002 observation counters portable model + tests
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-002

```packet-json
{
 "packet_id": "W-gdb-002",
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
  },
  {
   "path": "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "snapshot() -> EmbeddedSnapshot (additive optionals pinned in prose); model notify onChange(ObservationChange)",
  "types": "ObservationChange { videoParams, displayGeometry, fps, dropCount }; additive optionals videoCodec/videoPixelFormat/codedWidth/codedHeight/displayWidth/displayHeight/containerFPS/measuredFPS/droppedFrameCount",
  "ownership_lifetime": "model owns no media references; all values copied; nil = honest absence",
  "caller": "host UI + gate harness via session.snapshot()",
  "callee": "EmbeddedSnapshot additive optional fields + ObservationChange notify (pinned below)"
 },
 "test": {
  "command": "swift run observation-model-tests",
  "expected": "exit 0; final line matches '^observation-model-tests: [1-9][0-9]* PASS, 0 FAIL$' (suite prints one FAIL line per failed check)",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/observation-model-tests/",
   "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the embedded playback snapshot gained presented/audio counters at this pin, but the classic observation fields are still missing: per-stream video-params (codec, pixel format, coded w/h), display width/height after aspect+crop (dwidth/dheight), container fps + measured fps, and cumulative frame-drop-count. without them the host cannot show what is actually playing, and the gate harness cannot assert presentation health.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
- real source: Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, 78639B) - EmbeddedSnapshot and snapshot(); Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, 75946B) - FramePump presented/drop accounting; Sources/GorAVMetalPresenter/core/MetalPresenter.swift (available at the same pin) - where display geometry lives.
- real test command (Linux): swift build + the package's cue-output-tests/seek-composition-tests stay green; the returned model runs its own portable tests.

## expected behaviour
a portable (Swift or C/Python) observation-surface model with typed fields for video-params, dwidth/dheight, fps (container + measured), frame-drop-count, plus change notification; deterministic synthetic fixtures drive open/param-change/resize/drop-burst transitions and tests assert exact notify sequences and values. the integrator wires the model to the real session.

## exact call site and interface
EmbeddedSnapshot (additive optional fields, same style as presentedFrames/audioCallbacks at this pin) and snapshot(); the property/notify ABI is pinned below (integrator decision); the deliverable implements exactly it.

## pinned ABI decisions (integrator, 2026-11-15)
additive snapshot fields (same optional-never-placeholder style as presentedFrames/audioCallbacks at the pin):
  public var videoCodec: String?            // e.g. "h264"; nil until the inventory knows it
  public var videoPixelFormat: String?      // e.g. "yuv420p"
  public var codedWidth: Int?
  public var codedHeight: Int?
  public var displayWidth: Int?             // after aspect+crop; pairs with effectiveVideo
  public var displayHeight: Int?
  public var containerFPS: Double?
  public var measuredFPS: Double?
  public var droppedFrameCount: UInt64?     // cumulative; pairs with terminal PumpStats.dropped
notify ABI (the deliverable's model): enum ObservationChange: Equatable { case videoParams, displayGeometry, fps, dropCount } - one notify per actual change, never per poll (the TimePosGate emit-on-change rule, PlayheadObservers.swift, same pin). field sources at the pin: codec/kind from MediaInventory.Track (MediaInventory.swift), drops from PumpStats.dropped, geometry from EmbeddedSnapshot.effectiveVideo.

## behaviour that must not change
existing snapshot fields and their semantics at the pin stay; pause-contract witnesses (silence advances, presented frozen) stay exact; no new dependency.

## acceptance test (from the product repo)
model tests PASS on Linux; a negative control (drop a notify) fails; the integrator can map each model field to a real source in the pinned files without inventing values.

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

### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 1210-1225 of 1537)
```swift id=source2
    public func snapshot() async -> EmbeddedSnapshot {
        var s = EmbeddedSnapshot()
        s.seekTrace = seekTrace
        s.audioFirstAdmissionWallSeconds = landingBoxes.compactMap { $0.admissionWall }
        s.audioLandingFirstSampleSeconds = landingBoxes.flatMap { box in
            box.admittedAll.map { Double($0.firstSample.value) / Double($0.firstSample.timescale) }
        }
        s.durationSeconds = durationSeconds
        s.effectiveVideo = presenter?.effectiveVideo()
        if plane.state != .seeking { s.timePositionSeconds = tracker.read(clockNow: trackerClockNow(), durationSeconds: durationSeconds) }
        s.lifecycle = plane.state
        s.generation = plane.generation
        if let pump {
            s.isPaused = await pump.isPaused
            s.anchorMediaSeconds = await pump.currentPaceAnchor?.mediaSeconds
            s.presentedFrames = await pump.livePresentedCount
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"transition":"open","expect":{"videoCodec":"h264","codedWidth":1920,"codedHeight":1080,"notify":["videoParams","displayGeometry"]}},
 {"transition":"resize","expect":{"displayWidth":1280,"displayHeight":720,"notify":["displayGeometry"]}},
 {"transition":"drop-burst","expect":{"droppedFrameCount":7,"notify":["dropCount"]}}]
```
