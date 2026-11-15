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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "rf0"
      },
      {
        "path": "Sources/audio-only-model-tests/main.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run audio-only-model-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:25:36.487510+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "audio-only-model-tests",
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "rf0",
        "sha256": "fc4cca5ee9c92f1d39a75a570c73b696e73c73f70b1ec911f5943233d9282722"
      },
      {
        "path": "Sources/audio-only-model-tests/main.swift",
        "block": "rf1",
        "sha256": "2c3423cb79faa9ca4bcbe440f4d4ab576b217d65c7f4d030ac19aeceea2e1d65"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "c3b1832ed4732161d51b50e671c47369a8c4b05a94157fd0ca92be44249a434c",
    "last_5_lines": [
      "[5/8] Wrapping AST for audio-only-model-tests for debugging",
      "[6/8] Write Objects.LinkFileList",
      "[7/8] Linking audio-only-model-tests",
      "Build complete! (2.35s)",
      "audio-only-model-tests: 10 PASS, 0 FAIL"
    ],
    "receipt_sha256": "30d98f4e2232dbd7901cfa1310da6c8f694059faa9631566428345d3687a167c"
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

```text id=rf0
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "audio-only-model-tests", targets: ["audio-only-model-tests"]), .executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "audio-only-model-tests", path: "Sources/audio-only-model-tests"),
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
        .executableTarget(name: "audio-interrupt-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/audio-interrupt-tests"),
        .executableTarget(name: "cue-output-tests", dependencies: ["GorAVSubtitles", "GorAVPlaybackCore"], path: "Sources/cue-output-tests"),
        .executableTarget(name: "render-graph-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/render-graph-tests"),
        .executableTarget(name: "decoder-lifetime-tests", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore"], path: "Sources/decoder-lifetime-tests"),
        .executableTarget(name: "decoder-inventory-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/decoder-inventory-tests"),
        .testTarget(name: "PreparedVideoSwapTests", dependencies: ["GorAVPlaybackCore"], path: "Tests/PreparedVideoSwapTests"),
        .testTarget(name: "EmbeddedPreparedShotTests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), "GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Tests/EmbeddedPreparedShotTests"),
        .executableTarget(name: "color-stage-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/color-stage-tests"),
        .executableTarget(name: "crop-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/crop-tests"),
        .executableTarget(name: "frame-tap-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/frame-tap-tests"),
        .executableTarget(name: "active-media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/active-media-inventory-tests"),
        .executableTarget(name: "media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/media-inventory-tests"),
        .executableTarget(name: "video-remote-open-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/video-remote-open-tests"),
        .executableTarget(name: "remote-source-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/remote-source-tests"),
        .executableTarget(name: "subtitle-controller-tests", dependencies: ["GorAVSubtitles"], path: "Sources/subtitle-tests", sources: ["SubtitleControllerTests.swift"]),
        .executableTarget(name: "prepared-shot-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/prepared-shot-tests"),
        .executableTarget(name: "hosttransform-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/hosttransform-tests"),
        .executableTarget(name: "timepos-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-tests"),
        .executableTarget(name: "controlbus-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/controlbus-tests"),
        .target(name: "BridgeDemux", path: "Tests/labs/p-a1-r2/Sources/BridgeDemux"),
        .target(name: "BridgeVTDecode", dependencies: ["BridgeDemux"], path: "Sources/BridgeVTDecode"),
        .target(name: "AudioMasterScheduler", path: "Sources/AudioMasterScheduler"),
        .testTarget(name: "EngineContractTests", dependencies: ["BridgeVTDecode", "BridgeDemux", "AudioMasterScheduler"], path: "Tests/EngineContractTests"),
        .executableTarget(name: "e1-headless-tests", dependencies: ["BridgeDemux", "AudioMasterScheduler", "CFFmpeg", "GorAVPlaybackCore", "GorAVMetalPresenter"], path: "Sources/e1-headless-tests"),
        .executableTarget(name: "gorav-probe", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/gorav-probe"),


        .target(name: "GorAVCore", dependencies: ["GorAVCAtomics"], path: "Sources/GorAVCore", sources: ["Boundary.swift", "AdmissionTable.swift", "OpenURLRouter.swift"]),
        // L5/L6 u7 wiring candidate (coordinator-owned landing): parser/model library +
        // three SEPARATE @main consumer suites (one file each, never one merged target).
        .target(name: "GorAVSubtitles", path: "Sources/GorAVSubtitles", sources: ["ASSParser.swift", "SRTParser.swift", "SubtitleCue.swift", "SubtitlePlan.swift", "SubtitleSchedule.swift", "SubtitleTrack.swift", "SubtitleAutoLoad.swift", "SubtitleController.swift", "SubtitleCueOutput.swift", "SubtitleCueDelivery.swift", "SubtitleSidecarSession.swift"]),
        .executableTarget(name: "subtitle-srt-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SRTTests.swift"]),
        .executableTarget(name: "subtitle-ass-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["ASSTests.swift"]),
        .executableTarget(name: "subtitle-track-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitleTrackTests.swift"]),
        .executableTarget(name: "subtitle-plan-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitlePlanTests.swift"]),
        .target(name: "GorAVNativeProbeKit", dependencies: ["GorAVCore"],
                path: "Sources/GorAVNativeProbeKit",
                sources: ["GorAVSeekContract.swift", "NativeProbe.swift", "LeaseTable.swift", "PacketFeedMachine.swift", "DemuxerPolicy.swift"]),
        .systemLibrary(name: "CFFmpeg", path: "Sources/CFFmpeg"),
        // L6 Dolby Vision lane (block 78d L6; new lane dirs only, milestone-gated M4)
        .target(name: "GorAVDVRPU",
                path: "Sources/GorAVDVRPU",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVDolbyVision",
                dependencies: ["GorAVDVRPU", "CFFmpeg", "GorAVCore",
                               "GorAVFFmpegAdapter"],
                path: "Sources/GorAVDolbyVision"),
        .executableTarget(name: "dovi-selftest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-selftest",
                exclude: ["swift"]),
        .executableTarget(name: "dovi-hdrtest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-hdrtest",
                exclude: ["gen_ref_fields.py"]),
        .executableTarget(name: "dovi-vectest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-vectest"),
        .executableTarget(name: "dovi-fuzz",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-fuzz"),
        .target(name: "GorAVFFmpegAdapter", dependencies: ["CFFmpeg", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/GorAVFFmpegAdapter", sources: ["FFmpegSoftwareDecoder.swift", "SnapshotInput.swift", "SnapshotAVIOOwner.swift", "FrameObservation.swift", "FFmpegSoftwareAudioDecoder.swift", "L3Admission.swift", "L3SampleConvert.swift", "L3PixelConvert.swift", "L3HardwareDecode.swift", "L3AVCoordinator.swift", "SourceOpenOptions.swift", "MediaInventory.swift", "ActiveTransportSnapshot.swift"]),        .executableTarget(name: "l4-hwdecode-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "CFFmpeg"],
                path: "Sources/l4-hwdecode-tests", sources: ["L4HWDecodeTests.swift"]),

        .executableTarget(name: "gorav-first-frame", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/gorav-first-frame", sources: ["FirstFrame.swift"]),
        .executableTarget(name: "refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/refusal-tests", sources: ["RefusalTests.swift"]),
        .executableTarget(name: "playback-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/playback-test", sources: ["PlaybackTest.swift"]),
        .executableTarget(name: "audio-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/audio-test", sources: ["AudioTest.swift"]),
        .executableTarget(name: "seek-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-test", sources: ["SeekTest.swift"]),
        .executableTarget(name: "seek-restart-probe", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-restart-probe", sources: ["main.swift"]),
        .executableTarget(name: "audio-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/audio-refusal-tests", sources: ["AudioRefusalTests.swift"]),
        .executableTarget(name: "video-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/video-refusal-tests", sources: ["VideoRefusalTests.swift"]),
        .executableTarget(name: "coexist-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/coexist-test", sources: ["CoexistTest.swift"]),
        .executableTarget(name: "isolation-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/isolation-test", sources: ["IsolationTest.swift"]),
        .executableTarget(name: "trace-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/trace-dump", sources: ["TraceDump.swift"]),
        .executableTarget(name: "core-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/core-seek-tests"),
        .executableTarget(name: "real-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/real-seek-tests"),
        .executableTarget(name: "seek-ring-reset-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-ring-reset-tests"),
        .target(name: "GorAVSeekComposition", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVSeekComposition"),
        .executableTarget(name: "seek-pacing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-pacing-tests"),
        .executableTarget(name: "seek-composition-tests", dependencies: ["GorAVSeekComposition", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/seek-composition-tests"),
        .executableTarget(name: "audio-seek-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-seek-tests"),
        .executableTarget(name: "demux-parity-tests", dependencies: ["BridgeDemux", "CFFmpeg"], path: "Sources/demux-parity-tests"),
        .executableTarget(name: "audio-baseline-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-baseline-tests"),
        .executableTarget(name: "seek-contract-tests", dependencies: ["GorAVNativeProbeKit", "GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/seek-contract-tests"),
        .executableTarget(name: "adversarial-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/adversarial-seek-tests"),
        .executableTarget(name: "shell-seek-bridge-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/shell-seek-bridge-tests"),
        .executableTarget(name: "k9-adversarial", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/k9-adversarial", sources: ["K9Adversarial.swift"]),
        .executableTarget(name: "shell-mac-test", dependencies: ["GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/shell-mac-test", sources: ["ShellMacTest.swift"]),
        .executableTarget(name: "frame-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/frame-dump", sources: ["FrameDump.swift", "ConverterVariants.swift", "RawPlaneDump.swift"]),
        .target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: "."),
        .target(name: "GorAVAudioClock",
                path: "Sources/GorAVAudioClock",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVAudioClockSwift",
                dependencies: ["GorAVAudioClock", "GorAVCAtomics", "GorAVPlaybackCore"],
                path: "Sources/GorAVAudioClockSwift"),
        // r3 (architect r2 BLOCKER): NO explicit sources list - an explicit
        // list silently omitted Lane0Contract.swift + LifetimeRegistry.swift
        // (AudioSink/AudioStopResult/PlaybackRegistry unresolved in a real
        // package build; manual swiftc had masked it). Default = every file.
        .target(name: "GorAVPlaybackCore", dependencies: ["GorAVCAtomics", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVPlaybackCore"),
        .executableTarget(name: "session-venue-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/session-venue-tests"),
        // native87 Stage B entrypoint (B1-B3): pause-hold counter witnesses,
        // parked seek, close-from-paused report on the REAL embedded session.
        // macOS legs only; UNRUN (exit 77) elsewhere.
        .executableTarget(name: "b-gate-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/b-gate-tests"),
        .testTarget(name: "GorAVAudioClockTests",
                    dependencies: ["GorAVAudioClockSwift"],
                    path: "Tests/GorAVAudioClockTests"),
        .testTarget(name: "ReadinessAnchorTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/ReadinessAnchorTests"),
        .testTarget(name: "AudioPacingTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/AudioPacingTests"),
        .testTarget(name: "J3AudioControlTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/J3AudioControlTests"),
        .testTarget(name: "DecodeHeartbeatTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/DecodeHeartbeatTests"),
        .testTarget(name: "PlayerControlPlaneTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/PlayerControlPlaneTests"),
        .executableTarget(name: "pause-resume-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/pause-resume-tests"),
        .executableTarget(name: "race-witness-tests", dependencies: ["GorAVPlaybackCore"],
                          path: "Sources/race-witness-tests"),
        .executableTarget(name: "admission-tests", dependencies: ["GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"],
                          path: "Sources/admission-tests"),
        .executableTarget(name: "open-url-tests", dependencies: ["GorAVCore"], path: "Sources/open-url-tests"),
        .executableTarget(name: "audio-delay-tests", dependencies: ["GorAVPlaybackCore", "GorAVAudioClockSwift"], path: "Sources/audio-delay-tests"),
        .executableTarget(name: "window-mode-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/window-mode-tests"),
        .executableTarget(name: "observation-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/observation-tests"),
        .executableTarget(name: "timing-ledger-tests", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/timing-ledger-tests", sources: ["TimingLedgerTests.swift", "SPSCTests.swift"]),
        .executableTarget(name: "gorav-sink-check", dependencies: ["GorAVMacShell"], path: "Sources/gorav-sink-check", sources: ["SinkCheck.swift"]),
        .executableTarget(name: "gorav-play", dependencies: ["GorAVMacShell", "GorAVMetalPresenter", "GorAVPlaybackCore"], path: "Sources/gorav-play", sources: ["GorAVPlay.swift"]),
        // L7 embedded shell (block 168 factory gap): the E1 host-NSView embed
        // session. Whole body is canImport(AppKit)-gated - compiles empty
        // off-Mac; a Linux build is NOT a Mac compile claim. Explicit
        // sources pin: exactly the reviewed session file; a stray file
        // dropped into the dir is uncompiled, never silently wired.
        .target(name: "GorAVEmbeddedShell",
                dependencies: ["GorAVSubtitles", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVMacShell", "GorAVMetalPresenter", "GorAVFFmpegAdapter", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVEmbeddedShell", sources: ["GorAVEmbeddedSession.swift"]),
        .target(name: "GorAVMacShell", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVMacShell", sources: ["ShellClock.swift", "DisplaySink.swift", "AudioUnitSink.swift", "ShellFrameSource.swift", "FrameTap.swift", "TappedFrameLuma.swift", "WindowModeController.swift"]),
        // L2 Metal presenter lane, r7 landing (block 168 L3): new target dir
        // only; every Metal/AppKit source is canImport-gated so off-Mac
        // builds compile the target empty. GorAVMetalShellApp mirrors the
        // trunk shell contract (owner-issued session, shared CancelCommit,
        // audio-master pacing).
        .target(name: "GorAVMetalPresenter",
                dependencies: ["GorAVMacShell", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVSubtitles"],
                path: "Sources/GorAVMetalPresenter/core",
                sources: ["AspectFit.swift", "MetalPresenterTelemetry.swift", "SurfaceContract.swift", "MetalRenderer.swift", "MetalPresenter.swift", "GorAVMetalShellApp.swift", "StagePass.swift", "CVPixelBufferTap.swift"]),
        .executableTarget(name: "gorav-metal-check", dependencies: ["GorAVMetalPresenter", "GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/GorAVMetalPresenter/cli", sources: ["MetalCheck.swift"])
    ]
)

```

```text id=rf1
import Foundation

// audio-only-model-tests: B10 audio-only/artwork state model per the pinned ABI
// (W-gdb-008, pin 2112af0d). Typed audio-only detection, artwork selection with
// fallbacks, render-background state. Synthetic metadata fixtures in documented
// binary form (see FixtureImage); absent/corrupt/multiple artwork cases assert
// the typed fallbacks. Engine carries artwork IDENTITY only; bytes stay host-side.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

struct ArtworkInfo: Equatable { let trackIndex: Int; let codec: String; let byteCount: Int? }
enum RenderBackground: Equatable { case black, artwork(trackIndex: Int), hostManaged }

// documented binary form for fixture artwork blocks:
//   bytes 0..4  magic "GIMG"
//   byte  4     codec tag: 1=png, 2=jpeg (anything else = unsupported/corrupt)
//   bytes 5..8  declared byte count, little-endian UInt32 (0 = unknown)
//   bytes 9...  payload (corrupt when shorter than declared or magic absent)
struct FixtureImage {
    static func make(codec: UInt8, payloadBytes: Int, declared: UInt32? = nil) -> [UInt8] {
        var b: [UInt8] = [0x47, 0x49, 0x4D, 0x47, codec]
        let d = declared ?? UInt32(payloadBytes)
        b += [UInt8(d & 0xff), UInt8((d >> 8) & 0xff), UInt8((d >> 16) & 0xff), UInt8((d >> 24) & 0xff)]
        b += [UInt8](repeating: 0xAB, count: payloadBytes)
        return b
    }
    static func parse(_ b: [UInt8]) -> (codec: String, byteCount: Int?)? {
        guard b.count >= 9, b[0] == 0x47, b[1] == 0x49, b[2] == 0x4D, b[3] == 0x47 else { return nil }
        let codec: String
        switch b[4] { case 1: codec = "png"; case 2: codec = "jpeg"; default: return nil }
        let d = UInt32(b[5]) | UInt32(b[6]) << 8 | UInt32(b[7]) << 16 | UInt32(b[8]) << 24
        if d > 0, b.count - 9 < Int(d) { return nil } // truncated payload = corrupt
        return (codec, d > 0 ? Int(d) : nil)
    }
}

struct Track {
    let index: Int
    let isAudio: Bool
    let isVideo: Bool
    let isAttachedPicture: Bool
    var artworkBlock: [UInt8]? = nil // raw bytes, host-side
}

struct AudioOnlySnapshot: Equatable {
    var audioOnly: Bool
    var artwork: ArtworkInfo?
    var renderBackground: RenderBackground
}

enum AudioOnlyModel {
    static func snapshot(tracks: [Track], hostManagedBackground: Bool = false) -> AudioOnlySnapshot {
        let audioOnly = tracks.contains { $0.isAudio } && !tracks.contains { $0.isVideo && !$0.isAttachedPicture }
        let candidates = tracks.filter { $0.isAttachedPicture }
        var info: ArtworkInfo? = nil
        for t in candidates { // first parseable artwork wins; corrupt ones fall through
            if let block = t.artworkBlock, let (codec, n) = FixtureImage.parse(block) {
                info = ArtworkInfo(trackIndex: t.index, codec: codec, byteCount: n)
                break
            }
        }
        let bg: RenderBackground = hostManagedBackground ? .hostManaged
            : (info != nil ? .artwork(trackIndex: info!.trackIndex) : .black)
        return AudioOnlySnapshot(audioOnly: audioOnly, artwork: info, renderBackground: bg)
    }
}

// fixture 1: plain audio file, no artwork -> audioOnly, no artwork, black
let s1 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false)])
check("audio-only plain", s1 == AudioOnlySnapshot(audioOnly: true, artwork: nil, renderBackground: .black))

// fixture 2: audio + valid png artwork -> artwork identity, background=.artwork(trackIndex)
let png = FixtureImage.make(codec: 1, payloadBytes: 1200)
let s2 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: png)])
check("artwork selected", s2.audioOnly && s2.artwork == ArtworkInfo(trackIndex: 1, codec: "png", byteCount: 1200) && s2.renderBackground == .artwork(trackIndex: 1))

// fixture 3: corrupt artwork (bad magic) -> typed fallback: no artwork, black
let bad = [UInt8]([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
let s3 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: bad)])
check("corrupt artwork falls back", s3.audioOnly && s3.artwork == nil && s3.renderBackground == .black)

// fixture 4: truncated payload (declared 5000, present 10) -> corrupt -> fallback
let trunc = FixtureImage.make(codec: 2, payloadBytes: 10, declared: 5000)
let s4 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 2, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: trunc)])
check("truncated artwork falls back", s4.artwork == nil && s4.renderBackground == .black)

// fixture 5: multiple artwork tracks, first corrupt second valid -> first parseable wins
let jpeg = FixtureImage.make(codec: 2, payloadBytes: 640)
let s5 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: bad),
                                          Track(index: 3, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: jpeg)])
check("multiple artwork: first parseable wins", s5.artwork == ArtworkInfo(trackIndex: 3, codec: "jpeg", byteCount: 640) && s5.renderBackground == .artwork(trackIndex: 3))

// fixture 6: artwork with unknown byte count (declared 0) -> identity with nil byteCount
let unknown = FixtureImage.make(codec: 1, payloadBytes: 42, declared: 0)
let s6 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: unknown)])
check("unknown byte count is nil", s6.artwork == ArtworkInfo(trackIndex: 1, codec: "png", byteCount: nil))

// fixture 7: real video track present -> not audio-only; attached-picture flag still yields artwork
let s7 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: false),
                                          Track(index: 2, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: png)])
check("video present: not audio-only", !s7.audioOnly && s7.artwork != nil && s7.renderBackground == .artwork(trackIndex: 2))

// fixture 8: host-managed background overrides artwork
let s8 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                          Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: png)], hostManagedBackground: true)
check("host-managed wins", s8.renderBackground == .hostManaged && s8.artwork != nil)

// fixture 9: no audio at all -> not audio-only (an empty/video-less non-audio source is not music mode)
let s9 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: false, isVideo: false, isAttachedPicture: false)])
check("no audio: not audio-only", !s9.audioOnly)

// fixture 10: unsupported codec tag -> corrupt -> fallback
let unsupported = FixtureImage.make(codec: 9, payloadBytes: 100)
let s10 = AudioOnlyModel.snapshot(tracks: [Track(index: 0, isAudio: true, isVideo: false, isAttachedPicture: false),
                                           Track(index: 1, isAudio: false, isVideo: true, isAttachedPicture: true, artworkBlock: unsupported)])
check("unsupported codec falls back", s10.artwork == nil && s10.renderBackground == .black)

print("audio-only-model-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-mu6v02yn/tree/Sources/subtitle-tests/SRTTests.swift
Building for debugging...
[0/5] Write sources
[1/5] Write swift-version--9C6B84B6E025C5B.txt
[3/7] Compiling audio_only_model_tests main.swift
[4/7] Emitting module audio_only_model_tests
[5/8] Wrapping AST for audio-only-model-tests for debugging
[6/8] Write Objects.LinkFileList
[7/8] Linking audio-only-model-tests
Build complete! (2.35s)
audio-only-model-tests: 10 PASS, 0 FAIL
```
