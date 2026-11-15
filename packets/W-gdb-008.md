# W-gdb-008 B10 audio-only/artwork state model (rewrites W-0287)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-008

```packet-json
{
 "packet_id": "W-gdb-008",
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
   "excerpt_block": "source2"
  },
  {
   "path": "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "excerpt_block": "source2_1"
  }
 ],
 "interface": {
  "signatures": "snapshot() -> EmbeddedSnapshot (additive audioOnly/artwork/renderBackground); artwork detection via MediaInventory.Track.isAttachedPicture",
  "types": "ArtworkInfo { trackIndex: Int, codec: String, byteCount: Int? }; RenderBackground { black, artwork(trackIndex: Int), hostManaged }",
  "ownership_lifetime": "engine carries artwork IDENTITY only (trackIndex/codec/byteCount); image bytes stay host-side",
  "caller": "host music screen + gate harness via session.snapshot()",
  "callee": "EmbeddedSnapshot additive audioOnly/artwork/renderBackground (pinned below); artwork detection via MediaInventory.Track.isAttachedPicture"
 },
 "test": {
  "command": "swift run audio-only-model-tests",
  "expected": "exit 0; final line matches '^audio-only-model-tests: [1-9][0-9]* PASS, 0 FAIL$'; corrupt/absent-artwork rows assert the typed fallbacks",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/audio-only-model-tests/",
   "Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
an audio-only source (music file/stream) currently has no engine-facing state: no audio-only mode, no artwork extraction/selection, no render-background state - the host cannot show a proper music screen and the engine may keep video machinery alive for nothing.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
- real source: Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, 78639B) - open/session surface; Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift (sha256 49cbf0b3, 51723B) - the audio path; Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, 75946B) - pump states.
- real test command: returned model runs portable tests on Linux; session wiring stays integrator-side.

## expected behaviour
an audio-only state model: typed audio-only mode detection, artwork extraction/selection ABI (image lifetime/fallback), and a render-background state the host consumes; portable model + tests with synthetic metadata fixtures (embedded image blocks in documented binary form, absent/corrupt/multiple artwork cases).

## exact call site and interface
session open surface + snapshot (additive optional fields, same style as the pin's audio counters); the artwork/state ABI is pinned below (integrator decision).

## pinned ABI decisions (integrator, 2026-11-15)
additive ABI (same optional-never-placeholder style as the pin's audio counters):
  public var audioOnly: Bool?                  // true once the open inventory shows no .video track; nil before inventory
  public var artwork: ArtworkInfo?             // nil = no artwork, typed; never a placeholder
  public var renderBackground: RenderBackground?
  public struct ArtworkInfo: Equatable, Sendable { public let trackIndex: Int; public let codec: String; public let byteCount: Int? }  // detected via MediaInventory.Track.isAttachedPicture (pinned field); image BYTES stay host-side, the engine carries identity only
  public enum RenderBackground: Equatable, Sendable { case black; case artwork(trackIndex: Int); case hostManaged }
grounding at the pin: MediaInventory.Track { kind: TrackKind (.video/.audio/.subtitle/.data/.other), isAttachedPicture: Bool, codec: String }; audio surface FFmpegSoftwareAudioDecoder.swift; pump states PlaybackCore.swift. audioOnly == true => the video machinery idles; exact pump wiring stays integrator-side as the packet states.

## behaviour that must not change
normal A/V playback behavior and the pause contract; session/artwork ABI pinned before host wiring; no assumed private UI access.

## acceptance test (from the product repo)
model tests PASS on Linux including the corrupt/artwork-absent typed fallbacks; a negative control (dropped fallback) fails; the integrator maps each state to the pinned session without inventing signals.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 375-400 of 1537)
```swift id=source1
    public func open(path: String) async throws {
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.state == .idle, session == nil else { throw EmbeddedRefusal.alreadyOpen }
        guard FileManager.default.fileExists(atPath: path), !path.contains("://") else {
            throw EmbeddedRefusal.unsupportedSource("v0 admits local files only")
        }
        applyOrReport(.beginLoad)
        do {
            // S4 identity order: issued BEFORE audio.start; the audio leg
            // SHARES the one identity (no second mint).
            guard let issued = PlaybackIdentityAuthority.shared.issue() else {
                throw EmbeddedRefusal.identityExhausted
            }
            session = issued
            let clock = ShellClock()
            self.clock = clock
            guard let audio = AudioUnitSink() else { throw EmbeddedRefusal.audioRefused }
            self.audio = audio
            audio.ledgerSession = issued.epoch
            guard audio.attachPacing(hostClock: { clock.rawWallSeconds() }) else {
                throw EmbeddedRefusal.pacingRefused
            }
            clock.attachAudioMaster(audio.pacingClock)
            try audio.start()
            // R6: re-apply the persisted user delay on the fresh pacing policy.
            if audioDelaySeconds != 0 { audio.pacingPolicy?.setDelay(seconds: audioDelaySeconds) }
```

### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 127-146 of 1537)
```swift id=source2
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

### Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, lines 148-150 of 1537)
```swift id=source2_1
    public var shown: Int?
    public var dropped: Int?
    public var waits: Int?
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"inventory":{"tracks":[{"index":0,"kind":"audio","codec":"flac"},{"index":1,"kind":"video","codec":"mjpeg","isAttachedPicture":true}]},"expect":{"audioOnly":true,"artwork":{"trackIndex":1,"codec":"mjpeg"},"renderBackground":"artwork(1)"}}
```
