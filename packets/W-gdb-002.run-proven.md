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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "rf0"
      },
      {
        "path": "Sources/observation-model-tests/main.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run observation-model-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:25:10.929569+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "observation-model-tests",
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "rf0",
        "sha256": "a157d262dd3e8ba7253a679d74f5024decfbe44ee68b2fa91efcef2778a54fa6"
      },
      {
        "path": "Sources/observation-model-tests/main.swift",
        "block": "rf1",
        "sha256": "5722d66f67cc5a20b8cfa9eb45ae792c50c6da928dfe9f9e09d4dc5e7ce3e514"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "64499d7e3d5caca333a43aa3dcec0f434924ccf034efad0b3af6aa74ea975790",
    "last_5_lines": [
      "[5/8] Wrapping AST for observation-model-tests for debugging",
      "[6/8] Write Objects.LinkFileList",
      "[7/8] Linking observation-model-tests",
      "Build complete! (2.17s)",
      "observation-model-tests: 13 PASS, 0 FAIL"
    ],
    "receipt_sha256": "7d1e3ad7d57fdb71954a6c63e6c2318d6799ac7f61764145f1b00de857f92161"
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

```text id=rf0
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "observation-model-tests", targets: ["observation-model-tests"]), .executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "observation-model-tests", path: "Sources/observation-model-tests"),
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

// observation-model-tests: portable observation-surface model per the pinned
// additive-optional ABI (W-gdb-002, pin 2112af0d). nil = honest absence;
// one notify per actual change, never per poll. Deterministic synthetic
// fixtures drive open/param-change/resize/drop-burst transitions.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

enum ObservationChange: Equatable { case videoParams, displayGeometry, fps, dropCount }

struct ObservationSnapshot: Equatable {
    var videoCodec: String? = nil
    var videoPixelFormat: String? = nil
    var codedWidth: Int? = nil
    var codedHeight: Int? = nil
    var displayWidth: Int? = nil
    var displayHeight: Int? = nil
    var containerFPS: Double? = nil
    var measuredFPS: Double? = nil
    var droppedFrameCount: UInt64? = nil
}

final class ObservationModel {
    private(set) var snap = ObservationSnapshot()
    private(set) var notified: [ObservationChange] = []
    func snapshot() -> ObservationSnapshot { snap } // poll: never notifies
    private func note(_ c: ObservationChange) { notified.append(c) } // called only on an actual value change: one notify per actual change
    // field-group setters; each group notifies once per actual change
    func setVideoParams(codec: String?, pixelFormat: String?, codedW: Int?, codedH: Int?) {
        let before = (snap.videoCodec, snap.videoPixelFormat, snap.codedWidth, snap.codedHeight)
        snap.videoCodec = codec; snap.videoPixelFormat = pixelFormat; snap.codedWidth = codedW; snap.codedHeight = codedH
        if (snap.videoCodec, snap.videoPixelFormat, snap.codedWidth, snap.codedHeight) != before { note(.videoParams) }
    }
    func setDisplayGeometry(w: Int?, h: Int?) {
        let before = (snap.displayWidth, snap.displayHeight)
        snap.displayWidth = w; snap.displayHeight = h
        if (snap.displayWidth, snap.displayHeight) != before { note(.displayGeometry) }
    }
    func setFPS(container: Double?, measured: Double?) {
        let before = (snap.containerFPS, snap.measuredFPS)
        snap.containerFPS = container; snap.measuredFPS = measured
        if (snap.containerFPS, snap.measuredFPS) != before { note(.fps) }
    }
    func addDroppedFrames(_ n: UInt64) { // cumulative, monotone
        guard n > 0 else { return }
        snap.droppedFrameCount = (snap.droppedFrameCount ?? 0) + n
        note(.dropCount)
    }
}

// fixture 1: open with full inventory -> one videoParams + one displayGeometry + one fps notify, in order
var m = ObservationModel()
_ = m.snapshot(); _ = m.snapshot() // polls never notify
check("open polls silent", m.notified.isEmpty)
m.setVideoParams(codec: "h264", pixelFormat: "yuv420p", codedW: 1920, codedH: 1080)
m.setDisplayGeometry(w: 1920, h: 1080)
m.setFPS(container: 23.976, measured: 0.0)
check("open notify sequence", m.notified == [.videoParams, .displayGeometry, .fps])
check("open values", m.snapshot() == ObservationSnapshot(videoCodec: "h264", videoPixelFormat: "yuv420p", codedWidth: 1920, codedHeight: 1080, displayWidth: 1920, displayHeight: 1080, containerFPS: 23.976, measuredFPS: 0.0, droppedFrameCount: nil))

// fixture 2: no-change re-sets never notify; polls never notify
m.setVideoParams(codec: "h264", pixelFormat: "yuv420p", codedW: 1920, codedH: 1080)
m.setDisplayGeometry(w: 1920, h: 1080)
m.setFPS(container: 23.976, measured: 0.0)
_ = m.snapshot(); _ = m.snapshot(); _ = m.snapshot()
check("idempotent sets silent", m.notified == [.videoParams, .displayGeometry, .fps])

// fixture 3: aspect+crop resize -> displayGeometry only
m.setDisplayGeometry(w: 1440, h: 1080)
check("resize notifies geometry once", m.notified == [.videoParams, .displayGeometry, .fps, .displayGeometry])
check("resize values", m.snapshot().displayWidth == 1440 && m.snapshot().displayHeight == 1080 && m.snapshot().codedWidth == 1920)

// fixture 4: drop burst -> cumulative monotone dropCount, one notify per burst that actually added drops
m.addDroppedFrames(0) // zero burst: no notify
m.addDroppedFrames(7)
m.addDroppedFrames(0)
m.addDroppedFrames(3)
check("drop bursts notify per real burst", m.notified == [.videoParams, .displayGeometry, .fps, .displayGeometry, .dropCount, .dropCount])
check("drop count cumulative", m.snapshot().droppedFrameCount == 10)

// fixture 5: measured fps updates only notify when the value changes
m.setFPS(container: 23.976, measured: 23.9)
m.setFPS(container: 23.976, measured: 23.9)
m.setFPS(container: 23.976, measured: 24.1)
check("fps change-only notify", m.notified == [.videoParams, .displayGeometry, .fps, .displayGeometry, .dropCount, .dropCount, .fps, .fps])

// fixture 6: honest absence before inventory knows params
var m2 = ObservationModel()
m2.setFPS(container: nil, measured: nil) // nothing known, nothing changed
check("nil stays nil, silent", m2.notified.isEmpty && m2.snapshot() == ObservationSnapshot())
m2.setVideoParams(codec: nil, pixelFormat: "yuv420p", codedW: nil, codedH: 1080) // partial knowledge is a real change
check("partial params notify", m2.notified == [.videoParams] && m2.snapshot().videoCodec == nil && m2.snapshot().codedHeight == 1080)

// fixture 7: deterministic mixed script, expected exact sequence
var m3 = ObservationModel()
var expect: [ObservationChange] = []
struct LCG { var s: UInt64; mutating func next(_ n: UInt64) -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888969; return (s >> 33) % n } }
var rng = LCG(s: 0xb10c)
var codec = "h264", cw = 1280, dw = 1280, fps = 25.0, drops: UInt64 = 0
m3.setVideoParams(codec: codec, pixelFormat: "yuv420p", codedW: cw, codedH: 720); expect.append(.videoParams)
m3.setDisplayGeometry(w: dw, h: 720); expect.append(.displayGeometry)
m3.setFPS(container: fps, measured: fps); expect.append(.fps)
for _ in 0..<200 {
    switch rng.next(4) {
    case 0:
        let ncw = Int(rng.next(2)) == 0 ? cw : cw + 640
        if ncw != cw { cw = ncw; expect.append(.videoParams) }
        m3.setVideoParams(codec: codec, pixelFormat: "yuv420p", codedW: cw, codedH: 720)
    case 1:
        let ndw = Int(rng.next(2)) == 0 ? dw : dw + 320
        if ndw != dw { dw = ndw; expect.append(.displayGeometry) }
        m3.setDisplayGeometry(w: dw, h: 720)
    case 2:
        let nf = rng.next(2) == 0 ? fps : fps + 0.5
        if nf != fps { fps = nf; expect.append(.fps) }
        m3.setFPS(container: fps, measured: fps)
    default:
        let nd = rng.next(3)
        if nd > 0 { drops += nd; expect.append(.dropCount) }
        m3.addDroppedFrames(nd)
    }
}
check("scripted notify sequence exact", m3.notified == expect)
check("scripted drops cumulative", m3.snapshot().droppedFrameCount == drops)

print("observation-model-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-0q6fjsqx/tree/Sources/subtitle-tests/SRTTests.swift
Building for debugging...
[0/5] Write sources
[1/5] Write swift-version--9C6B84B6E025C5B.txt
[3/7] Emitting module observation_model_tests
[4/7] Compiling observation_model_tests main.swift
[5/8] Wrapping AST for observation-model-tests for debugging
[6/8] Write Objects.LinkFileList
[7/8] Linking observation-model-tests
Build complete! (2.17s)
observation-model-tests: 13 PASS, 0 FAIL
```
