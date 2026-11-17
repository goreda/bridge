# W-gdb-070 P28 move/hold picture motion (M2-picture/window lane)
> rev 2026-11-18-r4: English-only owner order (2026-11-18 01:46 +03 via main): replaced the one non-ASCII character in the packet (plus-minus sign -> "+/-" in the FitHoldMotion doc comment). No semantic change, no excerpt or hash change, pin unchanged (a34e2cd).

> rev 2026-11-16-r3: pin rolled 8786bfe3 -> a34e2cd (arch-197e item 5 self-decision; the delta is docs/LEDGER.tsv only, every excerpt body re-verified byte-identical and excerpt_sha256_8 unchanged). Supersedes the r2 receipts once a fresh gate-flow run_proof binds at a34e2cd.


New stock from open product work (arch-196z item 3, P28): the gor-fit
click-step and held-key picture motion ported to Swift as
`GorAVPlaybackCore/FitMotion.swift`. Semantics cited by lua line number only
(internal source, not reproduced): MOVE_OMEGA=20 spring, 1.5-step lead clamp
off the CURRENT value, PiP zoom floor 0, per-property settle thresholds,
HOLD_TAU=0.045 s speed easing, pan/zoom limits. Harness: 7 checks (M1-M5),
vectors fixed by an independent Python port.
v2 (2026-11-16): mid-motion cap mutation row M6 - a nudge after 5 in-flight steps clamps to the live cur + 1.5 steps (vector from the Python port).
v3 (2026-11-16): speed-cap-binding mutation row M7.

```packet-json
{
  "packet": "W-gdb-070",
  "code_owner": "gdb gorav integrator (M2-picture/window lane)",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "a34e2cd96b6825932a196424a17cc62962e910a7",
  "touched_files": [
    {
      "path": "PLAN.md",
      "excerpt_block": "ex_plan",
      "lines": "35-35"
    }
  ],
  "excerpt_sha256_8": {
    "ex_plan": "c6934240"
  },
  "interface": {
    "signatures": "NEW product API: FitMoveSpring(cur:eps:targetFloor:), nudge(delta:step:), step(dt:) -> Bool, cur/vel/tgt, moveOmega=20; FitHoldMotion(cur:speed:lower:upper:eps:), step(dt:direction:), holdTau=0.045.",
    "types": "FitMoveSpring, FitHoldMotion (Equatable, Sendable) in GorAVPlaybackCore/FitMotion.swift.",
    "ownership_lifetime": "Value types only; the caller owns property application.",
    "caller": "picture-motion-tests top-level script; future: the gor host-window (P28) menu-item and held-key pan/zoom.",
    "callee": "Foundation.exp only."
  },
  "test": {
    "command": "swift run picture-motion-tests",
    "expected": "Exit 0 and stdout ends with the line \"picture-motion-tests: all pass\" after 10 PASS lines (M1-M7, M2 and M4 have two each). Any FAIL line exits 1.",
    "fixture_block": "fx_picture_motion_tests",
    "note": "Run by the integrator on Linux. Vectors fixed by an independent Python port: 10 nudges clamp at 0.075, settle in 25 frames, hold reaches 0.5786 u/s in 0.15 s, release stops in 16 frames, limit clamp at 1.5. v2: mid-motion cap mutation row M6 (nudge after 5 in-flight steps clamps to live cur + 1.5 steps; vector from the Python port). v3: speed-cap-binding mutation row M7 (mid-flight vel 0.3148 capped to omega*|d| 0.1036682742334983; settles in 10 steps, never crosses)."
  },
  "target": {
    "branch": "lane/gdb-196z-picture (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
    "paths": [
      "Sources/GorAVPlaybackCore/FitMotion.swift",
      "Sources/picture-motion-tests/main.swift",
      "Package.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "merged_package"
      },
      {
        "path": "Sources/GorAVPlaybackCore/FitMotion.swift",
        "block": "fx_fit_motion"
      },
      {
        "path": "Sources/picture-motion-tests/main.swift",
        "block": "fx_picture_motion_tests"
      }
    ]
  }
}
```

## excerpts (verbatim from product_sha)

```swift id=ex_plan
P28 (arch-195b) | Host window: gor owns the window and its motion; the gor-fit.lua spring sizing, keepaspect handling, pip zoom and held-key pan/zoom move to Swift; the CGWindowList lookup of mpv's window and the overlay-over-mpv window retire on gorav | gor-fit.lua@d8b677b; AppDelegate overlayWin | decided | architect | none
```

## run recipe files

```swift id=fx_fit_motion
// P28 held-key / click-step picture motion, ported from gor-fit.lua@d8b677b
// (internal source, not bridged). Semantics by source line: click-step spring
// with MOVE_OMEGA = 20 rad/s and the same critically damped integrator as the
// window motion (lines 273-274, 303-317), the lead clamp so the target never
// runs more than 1.5 steps ahead of the shown value (lines 269-270, 321-324),
// the PiP zoom floor at 0 (line 325, 455-460), per-property settle thresholds
// (line 279, 312-314), held-key speed easing with HOLD_TAU = 0.045 s
// (lines 366-367, 384-394), and the pan/zoom limits and speeds
// (lines 368-369). Pure Swift, no AppKit. AUTHORED NEW 2026-11-16,
// M2-picture/window lane (arch-196z item 3).
import Foundation

/// Click-step spring for one picture property (video-pan-x / video-pan-y /
/// video-zoom / panscan): nudges move the TARGET; the value follows with the
/// critically damped spring, so a rapid key run never queues backlog.
public struct FitMoveSpring: Equatable, Sendable {
    public static let moveOmega = 20.0
    public static let maxStepSeconds = 0.05

    public private(set) var cur: Double
    public private(set) var vel: Double
    public private(set) var tgt: Double
    /// Settle thresholds for this property (distance / velocity x8).
    public let eps: Double
    /// Hard floor for the target (PiP zoom: 0).
    public let targetFloor: Double?

    public init(cur: Double, eps: Double, targetFloor: Double? = nil) {
        self.cur = cur; self.vel = 0; self.tgt = cur
        self.eps = eps; self.targetFloor = targetFloor
    }

    /// One menu-item step: the target moves by delta, clamped to within
    /// 1.5 steps of the CURRENT value (never of the target), then the
    /// toward-target speed is capped at omega * remaining distance.
    public mutating func nudge(delta: Double, step: Double) {
        let lead = 1.5 * step
        var t = tgt + delta
        if t > cur + lead { t = cur + lead }
        if t < cur - lead { t = cur - lead }
        if let f = targetFloor { t = max(f, t) }
        tgt = t
        let d = cur - tgt
        if d > 0 { vel = max(vel, -Self.moveOmega * d) }
        else if d < 0 { vel = min(vel, -Self.moveOmega * d) }
        else { vel = 0 }
    }

    /// Advance one frame. Returns false once settled (cur snapped to tgt).
    @discardableResult
    public mutating func step(dt rawDt: Double) -> Bool {
        let dt = min(Self.maxStepSeconds, max(0, rawDt))
        let e = Foundation.exp(-Self.moveOmega * dt)
        let d = cur - tgt
        let b = vel + Self.moveOmega * d
        let nd = (d + b * dt) * e
        vel = (vel - Self.moveOmega * b * dt) * e
        cur = tgt + nd
        if abs(nd) < eps && abs(vel) < eps * 8 {
            cur = tgt; vel = 0
            return false
        }
        return true
    }
}

/// Held-key motion for one property: the value runs at a steady eased speed
/// while the key is down and eases to zero on release. No target is queued.
public struct FitHoldMotion: Equatable, Sendable {
    public static let holdTau = 0.045
    public static let maxStepSeconds = 0.05

    public private(set) var cur: Double
    public private(set) var vel: Double
    /// Units per second at full hold (pan 0.6, zoom 1.0 in the source).
    public let speed: Double
    /// Hard limits for the value (pan +/-1.5, zoom -1...4 in the source).
    public let lower: Double, upper: Double
    public let eps: Double

    public init(cur: Double, speed: Double, lower: Double, upper: Double, eps: Double) {
        self.cur = cur; self.vel = 0
        self.speed = speed; self.lower = lower; self.upper = upper; self.eps = eps
    }

    /// Advance one frame with the current held direction (-1, 0, 1).
    public mutating func step(dt rawDt: Double, direction: Double) {
        let dt = min(Self.maxStepSeconds, max(0, rawDt))
        let k = 1 - Foundation.exp(-dt / Self.holdTau)
        vel = vel + (direction * speed - vel) * k
        if direction == 0 && abs(vel) < eps * 4 { vel = 0 }
        var nxt = cur + vel * dt
        if nxt < lower { nxt = lower; vel = 0 }
        if nxt > upper { nxt = upper; vel = 0 }
        cur = nxt
    }
}

```

```swift id=fx_picture_motion_tests
// Sources/picture-motion-tests/main.swift  (exit 0 = all pass)
// M2-picture/window lane (arch-196z item 3): P28 move/hold motion harness
// against GorAVPlaybackCore/FitMotion.swift. Vectors fixed by an independent
// Python port of the same integrators.
import GorAVPlaybackCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

var failures = 0
func check(_ n: String, _ ok: Bool) { print(ok ? "PASS \(n)" : "FAIL \(n)"); if !ok { failures += 1 } }
func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

// M1: the target never runs more than 1.5 steps ahead of the shown value.
var m = FitMoveSpring(cur: 0, eps: 5e-4)
for _ in 0..<10 { m.nudge(delta: 0.05, step: 0.05) }
check("M1 ten rapid nudges clamp the target at cur + 1.5 steps", near(m.tgt, 0.075) && near(m.cur, 0))

// M2: the spring follows and settles exactly on the target.
var busy = true
var steps = 0
while busy && steps < 1200 { busy = m.step(dt: 1.0/60.0); steps += 1 }
check("M2 settles exactly on the clamped target", !busy && near(m.cur, 0.075) && near(m.vel, 0))
check("M2 settle frame count matches the reference (25)", steps == 25)

// M3: the PiP zoom floor holds at 0.
var pz = FitMoveSpring(cur: 0.02, eps: 3e-3, targetFloor: 0)
for _ in 0..<5 { pz.nudge(delta: -0.05, step: 0.1) }
check("M3 pip zoom floor clamps the target at 0", near(pz.tgt, 0))

// M4: held key eases to steady speed; release eases to a stop.
var hm = FitHoldMotion(cur: 0, speed: 0.6, lower: -1.5, upper: 1.5, eps: 5e-4)
for _ in 0..<9 { hm.step(dt: 1.0/60.0, direction: 1) }
check("M4 held key reaches ~steady speed in 0.15 s", near(hm.vel, 0.5786, 1e-3) && hm.cur > 0.06 && hm.cur < 0.07)
var rsteps = 0
while hm.vel != 0 && rsteps < 600 { hm.step(dt: 1.0/60.0, direction: 0); rsteps += 1 }
check("M4 release eases to a full stop", hm.vel == 0 && rsteps == 16)

// M5: the limit clamp stops the value and the speed.
var hl = FitHoldMotion(cur: 0, speed: 0.6, lower: -1.5, upper: 1.5, eps: 5e-4)
for _ in 0..<600 { hl.step(dt: 1.0/60.0, direction: 1) }
check("M5 held pan stops at the limit", near(hl.cur, 1.5) && near(hl.vel, 0))

// M6: a mid-motion nudge clamps to the LIVE cur + 1.5 steps, not to the old
// target or a stale position (lab-review coverage). Vector fixed by the
// independent Python port of the same integrator.
var mm = FitMoveSpring(cur: 0, eps: 5e-4)
for _ in 0..<3 { mm.nudge(delta: 0.05, step: 0.05) }
for _ in 0..<5 { _ = mm.step(dt: 1.0/60.0) }
mm.nudge(delta: 0.05, step: 0.05)
check("M6 mid-motion nudge clamps to live cur + 1.5 steps", near(mm.cur, 0.037224879432487624) && near(mm.tgt, 0.11222487943248763))

// M7: the toward-target speed cap BINDS when a nudge shrinks the remaining
// distance below vel/omega mid-flight (lab-review G0822 coverage; vectors
// from the independent Python port).
var mc = FitMoveSpring(cur: 0, eps: 5e-4)
mc.nudge(delta: 0.05, step: 0.05)
for _ in 0..<5 { _ = mc.step(dt: 1.0/60.0) }
mc.nudge(delta: -0.02, step: 0.05)
check("M7 speed cap binds mid-flight", near(mc.cur, 0.024816586288325088) && near(mc.tgt, 0.03) && near(mc.vel, 0.1036682742334983))
var mcSteps = 0
var mcBusy = true
var mcCrossed = false
while mcBusy && mcSteps < 1200 { mcBusy = mc.step(dt: 1.0/60.0); mcSteps += 1; if mc.cur > mc.tgt + 1e-12 { mcCrossed = true } }
check("M7 capped spring settles on the new target without crossing", !mcBusy && mcSteps == 10 && near(mc.cur, 0.03) && !mcCrossed)

print(failures == 0 ? "picture-motion-tests: all pass" : "picture-motion-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

```swift id=merged_package
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "picture-motion-tests", targets: ["picture-motion-tests"]), .executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "timepos-vector-tests", targets: ["timepos-vector-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "vtt-parser-tests", targets: ["vtt-parser-tests"]), .executable(name: "l3-convert-matrix-tests", targets: ["l3-convert-matrix-tests"]), .executable(name: "avsync-golden-tests", targets: ["avsync-golden-tests"]), .executable(name: "transport-vector-tests", targets: ["transport-vector-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"]), .executable(name: "e1-shapes-tests", targets: ["e1-shapes-tests"]), .executable(name: "parity-pixel-tests", targets: ["parity-pixel-tests"]), .executable(name: "untagged-color-tests", targets: ["untagged-color-tests"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
        .executableTarget(name: "picture-motion-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/picture-motion-tests"),
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
        .executableTarget(name: "timepos-vector-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-vector-tests"),
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
        .target(name: "GorAVSubtitles", path: "Sources/GorAVSubtitles", sources: ["ASSParser.swift", "SRTParser.swift", "VTTParser.swift", "SubtitleCue.swift", "SubtitlePlan.swift", "SubtitleSchedule.swift", "SubtitleTrack.swift", "SubtitleAutoLoad.swift", "SubtitleController.swift", "SubtitleCueOutput.swift", "SubtitleCueDelivery.swift", "SubtitleSidecarSession.swift"]),
        .executableTarget(name: "vtt-parser-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/vtt-parser-tests"),
        .executableTarget(name: "avsync-golden-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/avsync-golden-tests"),
        .executableTarget(name: "transport-vector-tests", path: "Sources/transport-vector-tests"),
        .executableTarget(name: "parity-pixel-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                          path: "Sources/parity-pixel-tests"),
        .executableTarget(name: "untagged-color-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/untagged-color-tests"),
        .executableTarget(name: "l3-convert-matrix-tests", dependencies: ["GorAVFFmpegAdapter"],
                          path: "Sources/l3-convert-matrix-tests",
                          swiftSettings: [.define("L3_PROVIDER")]),
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
        .executableTarget(name: "e1-shapes-tests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), .target(name: "GorAVMetalPresenter", condition: .when(platforms: [.macOS])), .target(name: "GorAVPlaybackCore", condition: .when(platforms: [.macOS]))], path: "Sources/e1-shapes-tests"),
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
