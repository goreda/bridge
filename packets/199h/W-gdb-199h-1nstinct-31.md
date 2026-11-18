# W-gdb-199h-1nstinct-31 - One-euro filter holds on invalid samples
state: FIX PROPOSED / verified Swift 6.0.3 Linux (-Onone and -O)
lab: 1nstinct

OneEuro.filter and hold must ignore nonfinite input/time without mutating sample history. Invalid first sample returns finite0 hold; valid sampling then recovers. Preserve finite positive tuning and current dt clamp. Current HeadTracker.euro constructs this filter at189 and smooth uses its instances. Defensive invalid-sample hardening; no live-camera improvement claim.

CALLER SCOPE: Exact OneEuro value type. HeadTracker.euro constructs at189; live smoothing instances use it. Invalid sample hardening, no camera-quality claim.

Selected production declarations are extracted verbatim at compile time from the listed complete pinned source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module.

VERIFICATION (actual runs, Swift 6.0.3 Linux):
- pinned -Onone: compile_exit=0, semantic_exit=1
- pinned -O: compile_exit=0, semantic_exit=1
- fixed -Onone: compile_exit=0, semantic_exit=0
- fixed -O: compile_exit=0, semantic_exit=0

FIX: Reject nonfinite sample or time in OneEuro.filter and hold; return the held output without mutating filter history.

Native AppKit, camera capture, network, IPC, process launch, font rendering and UI are NOT_RUN.

REPRODUCE from the packet materialized root: set SWIFTC to a Swift compiler, then `python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py` for the pinned run, `GOR_SOURCE_ROOT=$PWD/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py` for the fixed run, adding `SWIFTFLAGS=-O` for the optimized run. Missing compiler exits77 NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199h-1nstinct-31",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/Sensing.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "OneEuro.filter and hold must ignore nonfinite input/time without mutating sample history. Invalid first sample returns finite0 hold; valid sampling then recovers. Preserve finite positive tuning and current dt clamp. Current HeadTracker.euro constructs this filter at189 and smooth uses its instances. Defensive invalid-sample hardening; no live-camera improvement claim.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Exact OneEuro value type. HeadTracker.euro constructs at189; live smoothing instances use it. Invalid sample hardening, no camera-quality claim.",
    "callee": "archive/gor/Sources/gor/Camera/Sensing.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py   (pinned);   GOR_SOURCE_ROOT=<packet root>/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py   (fixed);   add SWIFTFLAGS=-O for the optimized run; set SWIFTC to the compiler path",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Pinned source: compile_exit=0 then RED (semantic_exit=1; A35 traps, semantic_exit=-4). Fixed source: compile_exit=0 then GREEN (semantic_exit=0). Both verified in -Onone and -O under Swift 6.0.3 Linux."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199h-1nstinct-31",
    "paths": [
      "archive/gor/Sources/gor/Camera/Sensing.swift",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Camera/Sensing.swift",
        "block": "source1",
        "sha256": "dfad6279e1ebca7c2fbbb902472bddc378bac3d81c780de0653769cf09aab6b1",
        "read_only_dependency": false,
        "role": "Pinned production source at the base pin."
      },
      {
        "path": "archive/gor/Sources/gor/Camera/Sensing.swift (fixed)",
        "block": "fixed_source",
        "sha256": "d9bff0a4830ec5db3d4088c3f1499cf9dfc6c25884d24de8672ba5ec1141e60c",
        "role": "Same production file with only the minimal fix applied."
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py",
        "block": "fixtures1",
        "sha256": "603f6c4ae13e2c890959a85390f5c498d8f8facfbffa6d6b2add19032856390a"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.json",
        "block": "fixtures2",
        "sha256": "77a289bd2ed83f232ee62dd08932e9498cac6896dd999375d67aea84b65db543"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "5624ee319f8812e4e6aa7d2d248521479f9176b35758f372e39d855ef12e3298",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL invalid signal gives finite hold",
      "FAIL invalid signal does not poison history",
      ""
    ],
    "verification": {
      "red_Onone": {
        "log_block": "red_Onone",
        "log_sha256": "cd611ecc2d1ef363f7597a8f7a794c531a0e5cea2ef0b468ac7f01e1b54585e5",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "red_O": {
        "log_block": "red_O",
        "log_sha256": "cd611ecc2d1ef363f7597a8f7a794c531a0e5cea2ef0b468ac7f01e1b54585e5",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "green_Onone": {
        "log_block": "green_Onone",
        "log_sha256": "0d3ca4487106c7b71c9106a2e1ac35a7f54cc72ecc5762113f52ae18078240b9",
        "semantic_exit": 0,
        "compile_exit": 0
      },
      "green_O": {
        "log_block": "green_O",
        "log_sha256": "0d3ca4487106c7b71c9106a2e1ac35a7f54cc72ecc5762113f52ae18078240b9",
        "semantic_exit": 0,
        "compile_exit": 0
      }
    },
    "expected": "fixed source GREEN exit0 in -Onone and -O"
  },
  "state": "FIX PROPOSED - verified Swift 6.0.3 Linux, -Onone and -O",
  "classification": "Exact OneEuro value type. HeadTracker.euro constructs at189; live smoothing instances use it. Invalid sample hardening, no camera-quality claim.",
  "fix": {
    "summary": "Reject nonfinite sample or time in OneEuro.filter and hold; return the held output without mutating filter history.",
    "diff_block": "fix_diff",
    "diff_sha256": "884fd9f08b16ec514792398c7d3a3a9a9c26c09a41f56dfcb63d73677106934a",
    "fixed_block": "fixed_source",
    "fixed_sha256": "d9bff0a4830ec5db3d4088c3f1499cf9dfc6c25884d24de8672ba5ec1141e60c",
    "pinned_sha256": "dfad6279e1ebca7c2fbbb902472bddc378bac3d81c780de0653769cf09aab6b1"
  }
}
```

```swift id=source1
import AppKit
import CoreGraphics
import ScreenCaptureKit
import AVFoundation
import CoreAudio
import Accelerate
import Vision
import CoreML
import IOKit

// ================================================================
// HeadTracker  (VR180 head-tracked look-around)
//
// Webcam head pose consumed by PPController.setHeadTrackingEnabled /
// applyHeadPose; never touches mpv, IPC, or shader opts itself. Separate
// TCC permission (Camera) and opt-in lifecycle, independent of the
// screen/audio capture above.
//
// Pipeline: AVCaptureSession -> VNDetectFaceRectanglesRequest revision 3
//   (roll/pitch/yaw directly, macOS 12+; VNDetectFaceLandmarksRequest does
//   NOT feed pose - per WWDC21 10040 pose is a property of the RECTANGLES
//   request) -> single-pole low-pass (unsmoothed pose visibly jitters the
//   shader's ray direction) -> onPoseUpdate on main.
//
// X/Y/Z is NOT real 6DoF: Vision gives rotation only; xOffset/yOffset/
// zOffset are a boundingBox proxy relative to a recenter() baseline,
// sufficient for small yaw/pitch/fov nudges and no more - don't reuse for
// anything that wants real units.
//
// Sign conventions are unverified against a real camera: isolated into the
// *Sign constants so one flip fixes it once observed.
// ================================================================

/// Recenter()-relative head pose. See the HeadTracker class comment
/// above for exactly what each field does and does not represent.
struct HeadPose {
    /// Radians, Vision's own convention -- see HeadTracker's *Sign
    /// constants for the one place to correct these if a physical
    /// head turn moves the view the wrong way.
    var yaw: Double
    var pitch: Double
    var roll: Double

    /// Unitless, recenter()-relative boundingBox proxy (NOT real
    /// translation -- see the class comment above). Roughly
    /// -0.5...0.5 for normal desk-distance head movement; not
    /// clamped here, the consumer clamps.
    var xOffset: Double
    var yOffset: Double
    var zOffset: Double
    /// Block 182 2: face distance from the box in mm (raw and one-euro filtered); nil with a reason when the
    /// camera field of view is unavailable. Defaults keep every existing HeadPose(...) call valid.
    var distanceRawMM: Double? = nil
    var distanceMM: Double? = nil
    var distanceFallback: String? = nil
    var fusionRoll: Double? = nil
    var nativeRawRoll: Double? = nil
}

/// Block 182 2 distance model, pure. d_mm = f_px * 140 / w_box_px with f_px = (frame_w / 2) / tan(hfov / 2) and
/// w_box_px = box.width * frame_w, so the frame width cancels: d = 70 / (tan(hfov / 2) * box.width).
/// 140 mm is the owner's adult face-width constant; hfov is AVCaptureDevice.activeFormat.videoFieldOfView (deg).
enum VRDistance {
    static let faceWidthMM = 140.0
    static func distanceMM(hfovDeg: Double, boxWidthNorm: Double) -> Double {
        let fPxPerFrameW = 0.5 / tan(hfovDeg * Double.pi / 180.0 / 2.0)   // f_px / frame_w
        return fPxPerFrameW * faceWidthMM / boxWidthNorm
    }
    /// mm per physical pixel of the main display: CGDisplayScreenSize.width / the mode's pixel width.
    /// 0 when either is unavailable (the script then uses the MacBook Air M1 panel constant, 25.4/227).
    static func mmPerPx() -> Double {
        let id = CGMainDisplayID()
        let wmm = CGDisplayScreenSize(id).width
        guard wmm > 0, let px = CGDisplayCopyDisplayMode(id)?.pixelWidth, px > 0 else { return 0 }
        return Double(wmm) / Double(px)
    }
}

@available(macOS 12.0, *)
final class HeadTracker: NSObject {
    static let shared = HeadTracker()
    private override init() { super.init() }
    // MARK: - Public surface
    /// Delivered on the main thread. PPController assigns this once,
    /// when head-tracking is enabled, and clears it on disable --
    /// same ownership shape as PollEngine.onResults in
    /// PPController.swift.
    var onPoseUpdate: ((HeadPose) -> Void)?
    var onGazeUpdate: ((BinocularGazeSample?) -> Void)?
    // Source commentary elided for privacy; historical proof hashes are not rebound.
    private static let yawSign:   Double = 1.0
    private static let pitchSign: Double = -1.0
    private static let rollSign:  Double = 1.0
    // Source commentary elided for privacy; historical proof hashes are not rebound.
    private static let xOffsetSign: Double = -1.0
    /// gor.vr.poseHoldLock (default ON). false removes the 197i hold-lock stage
    /// from the output chain, byte-identical behaviour.
    static var poseHoldLock = true
    private static let yOffsetSign: Double = 1.0
    // MARK: - Smoothing
    /// Single-pole low-pass, same alpha = 1 - exp(-dt/tau) shape
    /// ScreenCaptureEngine.processAudio() already uses above -- but
    /// applied SYMMETRICALLY here (same tau rising and falling),
    /// unlike processAudio's fast-attack/slow-release envelope. That
    /// asymmetry exists there because audio wants peaks to read
    /// instantly and decay slowly; head pose has no equivalent
    /// "peaks matter more than troughs" property, so a plain low-pass
    /// is the right tool here, not a copy of that asymmetric shape.
    ///
    /// Was 0.15/2 == 0.075s (alpha ~= 0.36 per 30fps frame -- each new
    /// frame overwrote over a third of the smoothed value, which is
    /// fast/responsive, not conservative). That value did not come
    /// from a wrong choice of Vision request -- roll/pitch/yaw jitter
    /// is a property of VNDetectFaceRectanglesRequest's own pose
    /// estimate (see this class's pipeline comment above for why
    /// VNDetectFaceLandmarksRequest was tried and reverted; it doesn't
    /// touch pose at all) -- so this constant, not the request type,
    /// is the actual lever. Raised to 0.25s (alpha ~= 0.126/frame) as
    /// a real, if still untested-on-hardware, attempt at less jitter
    /// on a still head: a genuine head turn still reaches ~90% of its
    /// new position within ~0.55s at this tau, which should read as
    /// smoothed rather than laggy, but this trade (less noise, more
    /// lag) is inherent to a low-pass filter -- there's no tau that
    /// removes jitter for free. Raise further if still too wobbly;
    /// lower back toward 0.075-0.15 if look-around starts to feel
    /// delayed. Still a starting point, not derived -- no camera or
    /// real noise floor was available to tune this against.
    private static let poseSmoothingTau: Double = 0.25  // seconds; the pre-stabilization value, kept as the still-head reference below
    //192d D1 first smoothing stage: existing one-euro (Casiez et al., CHI2012).
    struct OneEuro {
        var minCutoff: Double
        var beta: Double
        var dCutoff: Double = 1.0
        private var has = false
        private var xPrev = 0.0, dxPrev = 0.0, tPrev = 0.0, xRawPrev = 0.0
        init(minCutoff: Double, beta: Double) { self.minCutoff = minCutoff; self.beta = beta }
        private static func alpha(_ dt: Double, _ cutoff: Double) -> Double {
            let tau = 1.0 / (2.0 * Double.pi * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }
        mutating func reset() { has = false }
        mutating func hold(at t:Double)->Double {if has {tPrev=t};return xPrev}
        mutating func filter(_ x: Double, at t: Double) -> Double {
            guard has else { has = true; xPrev = x; xRawPrev = x; dxPrev = 0; tPrev = t; return x }
            let dt = min(max(t - tPrev, 1.0 / 240.0), 0.2)
            tPrev = t
            // Speed from the previous RAW sample, as in the reference one-euro filter (Casiez et al. 2012). The
            // earlier (x - previous FILTERED)/dt carried the filter's own lag, so the cutoff stayed high after a
            // stop and noise deviations from the lagging output counted as speed.
            let dx = (x - xRawPrev) / dt
            xRawPrev = x
            dxPrev += Self.alpha(dt, dCutoff) * (dx - dxPrev)
            let cutoff = minCutoff + beta * abs(dxPrev)
            xPrev += Self.alpha(dt, cutoff) * (x - xPrev)
            return xPrev
        }
    }
    // Synthetic 30 fps white-noise study, 12 seeds: relative to the old fixed tau0.25 filter, the shipped
    // adaptive constants yielded 1.37/1.62/2.08x angle jitter at sigma .01/.02/.05 rad. Raw-sample velocity
    // plus these cutoffs gives .81/.86/1.01x, versus the shipped adaptive filter .59/.53/.49x.
    // A 0.5 rad turn at 1 rad/s reaches 90% in .67 s (old fixed .90 s, shipped adaptive .50 s).
    // These are synthetic measurements, not proof that the owner's live-camera wobble is fixed.
    private static let stillCutoffHz = 0.35
    private static let turnCutoffHz = 2.0
    private static let speedFilterCutoffHz = 0.3
    private static func euro(refSpeed: Double) -> OneEuro {
        var f = OneEuro(minCutoff: stillCutoffHz, beta: (turnCutoffHz - stillCutoffHz) / refSpeed)
        f.dCutoff = speedFilterCutoffHz
        return f
    }
    private static let angleRefSpeed = 1.0   // rad/s
    private static let boxRefSpeed = 0.25    // box units/s
    private static let fovTauSeconds = 0.8
    private var fYaw = HeadTracker.euro(refSpeed: HeadTracker.angleRefSpeed), fPitch = HeadTracker.euro(refSpeed: HeadTracker.angleRefSpeed), fRoll = HeadTracker.euro(refSpeed: HeadTracker.angleRefSpeed)
    private var fX = HeadTracker.euro(refSpeed: HeadTracker.boxRefSpeed), fY = HeadTracker.euro(refSpeed: HeadTracker.boxRefSpeed)
    private var fZ = OneEuro(minCutoff: 1.0 / (2.0 * Double.pi * HeadTracker.fovTauSeconds), beta: 0)
    /// Main-thread only (called exclusively from applyObservation below).
    private func smooth(_ raw: HeadPose, at now: CFTimeInterval, distanceValid:Bool=true) -> HeadPose {
        // Native look-around needs faster motion adaptation, not less still filtering.
        let turn=nativeMotionResponsive ? 4.0:Self.turnCutoffHz
        let speed=nativeMotionResponsive ? 0.3:Self.speedFilterCutoffHz
        fYaw.beta=(turn-Self.stillCutoffHz)/Self.angleRefSpeed;fYaw.dCutoff=speed
        fPitch.beta=fYaw.beta;fPitch.dCutoff=speed;fRoll.beta=fYaw.beta;fRoll.dCutoff=speed
        let z=distanceValid ? fZ.filter(raw.zOffset,at:now):fZ.hold(at:now)
        return HeadPose(yaw: fYaw.filter(raw.yaw, at: now), pitch: fPitch.filter(raw.pitch, at: now),
                        roll: fRoll.filter(raw.roll, at: now),
                        xOffset: fX.filter(raw.xOffset, at: now), yOffset: fY.filter(raw.yOffset, at: now),
                        zOffset: z)
    }
    // Distance goes through the same heavy channel as the fov-from-box (tau 0.8 s, beta 0).
    private var fD = OneEuro(minCutoff: 1.0 / (2.0 * Double.pi * HeadTracker.fovTauSeconds), beta: 0)
    private func resetFilters() { fYaw.reset(); fPitch.reset(); fRoll.reset(); fX.reset(); fY.reset(); fZ.reset(); fD.reset() }
    // MARK: - Baseline (recenter) -- main-thread only, see applyObservation
    private var poseContinuity=PoseContinuity(); private var poseSessionStartedAt:Double=0
    private var lastTracedPose=[Double](repeating:0,count:6)
    private var pupilDistanceScale=PupilDistanceScale(); private var baselineBoxSize: CGFloat?
    private var poseEyeGate=PoseEyeMeasurementGate();private var poseNoise=PoseNoiseCalibration();private var poseFollow:PoseBacklashFollow?
    // 197i hold lock: five channels (yaw/pitch/roll angular, x/y box); z already
    // carries the 191a hysteresis. Created lazily so a disabled flag allocates nothing.
    private var poseHoldLocks:[PoseHoldLock]?
    var nativeMotionResponsive=false {didSet {if oldValue != nativeMotionResponsive {poseFollow=nil}}}
    private var poseDistanceConsistency=PoseDistanceConsistency()
    private var previousPoseOutput:[Double]?
    private var independentDistance:(at:Double,relative:Double,ready:Bool)?
    private var baselineBoxCenter: CGPoint?, lastBoundingBox: CGRect?
    private var lastAngles=(yaw:0.0,pitch:0.0,roll:0.0), neutralAngles=(yaw:0.0,pitch:0.0,roll:0.0)
    /// Pose baseline belongs to the head consumer, not the shared camera; seed a fresh observation.
    func beginPoseSession() {
        poseSessionStartedAt=CACurrentMediaTime(); baselineBoxSize=nil;baselineBoxCenter=nil;neutralAngles=(0,0,0)
        independentDistance=nil;pupilDistanceScale.reset();poseEyeGate=PoseEyeMeasurementGate();poseDistanceConsistency=PoseDistanceConsistency()
        poseNoise=PoseNoiseCalibration();poseFollow=nil;previousPoseOutput=nil;poseHoldLocks=nil
        resetFilters();poseContinuity=PoseContinuity();lastTracedPose=[Double](repeating:0,count:6)
    }
    /// Reset distance/look-around immediately; preserve the measured physical eye axis.
    func recenter() {
        beginPoseSession()
        guard lastBoundingBox != nil else { return }
        var aligned=HeadPose(yaw:0,pitch:0,roll:lastAngles.roll,xOffset:0,yOffset:0,zOffset:0)
        aligned.fusionRoll=lastAngles.roll;aligned.nativeRawRoll=lastAngles.roll
        aligned.distanceFallback="fov-unavailable"
        lastTracedPose=[0,0,lastAngles.roll,0,0,0]
        PoseTraceRing.shared.append(t:CACurrentMediaTime(),raw:[],filtered:lastTracedPose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"recenter")
        onPoseUpdate?(aligned)
    }
    // MARK: - Capture session (arch-195z Z3 / arch-196b C6: camera lives in the child helper)
    /// The AVCaptureSession and all camera Vision work run in the same
    /// executable spawned as --camera-helper (CameraHelperClient /
    /// CameraHelperEngine in QuitChildKiller.swift, protocol in
    /// Stereo/HeadPose.swift). This class keeps consumer policy, the
    /// ambient reading epochs, and every downstream math path; the
    /// helper returns typed readings only. Guaranteed camera-off on a
    /// hung Apple stop comes from the 2 s stop deadline + SIGKILL in
    /// the client: process exit releases the device.
    private let cameraHelper = CameraHelperClient()
    /// One automatic helper relaunch per consumer generation on an
    /// unexpected exit (Z3: restart = new helper epoch, no retry loop).
    private var relaunchGeneration: UInt64 = 0
    /// Ambient settle-window id; bumped per fresh window and tagged on
    /// every helper frame, replacing the in-process frameQueue reset.
    private var ambientWindowID: UInt64 = 0
    /// The helper Vision-watchdog token last reported expired (arch-196b
    /// C2): frames carrying it are dropped, the cross-process form of
    /// the in-process visionEpochIsCurrent gate.
    private let visionCancelLock = NSLock()
    private var expiredVisionToken: UInt64?
    private func currentExpiredVisionToken() -> UInt64? {
        visionCancelLock.lock(); defer { visionCancelLock.unlock() }; return expiredVisionToken
    }
    private static let ambientClassificationDeadline: TimeInterval = 0.25
    private let ambientReadingLock = NSLock()
    private var ambientReadingEpoch: UInt64 = 0
    private var ambientReadingOpen = false
    private var ambientReadingArmed = false
    private var ambientReadingPublished = false
    private func ambientEpoch() -> UInt64 {
        ambientReadingLock.lock(); defer { ambientReadingLock.unlock() }
        return ambientReadingEpoch
    }
    private func beginAmbientReading() {
        ambientReadingLock.lock(); defer { ambientReadingLock.unlock() }
        ambientReadingEpoch &+= 1; ambientReadingOpen = true
        ambientReadingArmed = false; ambientReadingPublished = false
    }
    private func endAmbientReading() {
        ambientReadingLock.lock(); defer { ambientReadingLock.unlock() }
        ambientReadingOpen = false; ambientReadingPublished = true
        ambientReadingEpoch &+= 1
    }
    private func armAmbientFallback(_ luma: Double, generation: UInt64, epoch: UInt64) {
        ambientReadingLock.lock()
        let arm = ambientReadingOpen && !ambientReadingArmed && ambientReadingEpoch == epoch
        if arm { ambientReadingArmed = true }
        ambientReadingLock.unlock()
        guard arm else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ambientClassificationDeadline) { [weak self] in
            self?.publishAmbient(luma, regions: nil, generation: generation, epoch: epoch, source: "deadline-full-frame")
        }
    }
    private func publishAmbient(_ luma: Double, regions: TwoRegionLuma?, generation: UInt64, epoch: UInt64, source: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeConsumers > 0, lifecycleGeneration == generation else { return }
        ambientReadingLock.lock()
        let accept = ambientReadingEpoch == epoch && !ambientReadingPublished
        if accept && ambientReadingOpen { ambientReadingPublished = true }
        ambientReadingLock.unlock()
        guard accept else { return }
        lastAmbientLuma = luma; lastAmbientRegions = regions
        Diag.mediaRecord("AMBIENT value=\(luma) generation=\(generation) source=\(source)")
        onAmbientFrame?()
    }
    /// Fresh ambient window: the reading epoch opens here (parent
    /// policy); the settle counters live in the helper, which resets
    /// them on this command and tags every frame with the window id.
    /// A frame from an older window is rejected in handleHelperFrame,
    /// the same stale-read protection the in-process epoch capture gave.
    func resetAmbientSettling() {
        beginAmbientReading()
        ambientWindowID &+= 1
        cameraHelper.resetSettling(generation: lifecycleGeneration, window: ambientWindowID)
    }

    // Main owns consumer bookkeeping. Frame/session queues read a locked
    // snapshot, never the mutable consumer count or ambient request flag.
    private let lifecycleLock = NSLock()
    private var lifecycleSnapshot: (generation: UInt64, requested: Bool, ambientOnly: Bool) = (0, false, false)
    private func captureLifecycle() -> (generation: UInt64, requested: Bool, ambientOnly: Bool) {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return lifecycleSnapshot
    }
    private func publishLifecycle() {
        lifecycleLock.lock()
        lifecycleSnapshot = (lifecycleGeneration, activeConsumers > 0,
                             hasRequestedAmbientStart && activeConsumers == 1)
        lifecycleLock.unlock()
        bumpBlinkEpoch()
    }
    private var isAmbientOnlyActive: Bool { captureLifecycle().ambientOnly }

    // MARK: - Blink measurement (log only; no command is bound to a blink)
    // Phase 2 measurement build: while blinkLogEnabled (VR menu "blink log (measure only)" / shift+e) AND
    // head tracking frames are flowing, a VNDetectFaceLandmarksRequest runs on the SAME frames after the
    // pose has been dispatched, and an eye-contour box aspect (landmark bounding-box height / width per eye;
    // NOT the canonical 6-point EAR) is written to the geom trace as blinkTrace.
    // Purpose: measure the false-accept rate against natural blinking before any binding exists.
    private let blinkLock = NSLock()
    private var blinkLogOn = false
    // Bumped on every blink toggle AND on every consumer/lifecycle publication (publishLifecycle), so a sample
    // scheduled before an off->on toggle, a tracking stop/start or an ambient transition is never published.
    private var blinkEpoch: UInt64 = 0
    private func currentBlinkEpoch() -> UInt64 { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkEpoch }
    private func bumpBlinkEpoch() { blinkLock.lock(); blinkEpoch &+= 1; blinkLock.unlock() }
    var blinkLogEnabled: Bool {
        get { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkLogOn }
        set { blinkLock.lock(); blinkLogOn = newValue; blinkEpoch &+= 1; if !newValue { blinkIndicatorCB = nil; blinkDetectedCB = nil; blinkCloseSessionLocked() } else { blinkBeginSessionLocked() }; blinkLock.unlock(); pushHelperConfig() }
    }
    /// Block 182 3: the bbox proxy is unreliable at large yaw, so frames over this are tagged in the trace.
    static let blinkYawTagDeg: Double = 15.0
    // Runs OFF the capture callback: one in-flight sample at most, a frame that arrives while one is
    // running is skipped (never queued), so the pose cadence and the capture queue are not extended.
    private let blinkQueue = DispatchQueue(label: "gor.headtracker.blink", qos: .utility)
    private var blinkBusy = false
    // Adaptive blink indicator state (measurement only; no command is bound). Touched only on blinkQueue (serial).
    // The two fractions are PROVISIONAL hypotheses, not validated against any recording: an eye counts as
    // "closing" when the aspect falls below blinkClosedFrac of the running open-eye level, and the level is only
    // updated from samples above blinkOpenFrac so a closure does not drag the baseline down.
    private var blinkBase: Double? = nil
    private var blinkPrevT: CFTimeInterval? = nil
    private var blinkStateEpoch: UInt64 = 0
    static let blinkClosedFrac = 0.70
    static let blinkOpenFrac = 0.85
    static let blinkBaseAlpha = 0.05
    /// A blink lasts roughly 100-400 ms. Two samples inside the shortest blink need a gap of at most about half of
    /// it; a larger gap is reported as sparse so "no blink" is never claimed from samples that cannot see one.
    static let blinkMaxGapS = 0.05
    /// Bounded Shift+E session summary: plain counters and a fixed 5-bucket gap histogram, never a per-sample array.
    /// Counts what happened to each offered frame, by reason. It is NOT a detection verdict: "candidates" are closing
    /// edges of an unvalidated ratio and are not blinks. Guarded by blinkLock.
    private struct BlinkSession {
        var id: UInt64 = 0, active = false
        var tFirst: CFTimeInterval? = nil, tLast: CFTimeInterval? = nil
        var offered = 0, skippedBusy = 0, ambientSkipped = 0
        var visionFailed = 0, staleDropped = 0, noFace = 0, noEyes = 0, yawOver = 0, usable = 0
        var candidates = 0, sparse = 0
        var blinksConfirmed = 0, blinksPossible = 0, closuresHeld = 0
        var gapBuckets = [Int](repeating: 0, count: 5)   // <=0.05, <=0.10, <=0.25, <=0.50, >0.50 s
        var gapMax = 0.0
        var baseMin: Double? = nil, baseMax: Double? = nil
    }
    private var blinkSess = BlinkSession()
    private var blinkSessionSeq: UInt64 = 0
    /// Id of the current (or last) blink session; the controller reads it right after turning ON, on the main thread.
    var blinkSessionID: UInt64 { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkSess.id }
    /// Turns the log OFF and closes the session only if `sid` is still the active session. Atomic under blinkLock.
    func stopBlinkLogIfCurrent(session sid: UInt64) -> Bool {
        blinkLock.lock(); defer { blinkLock.unlock() }
        guard blinkLogOn, blinkSess.active, blinkSess.id == sid else { return false }
        blinkLogOn = false; blinkEpoch &+= 1; blinkIndicatorCB = nil; blinkDetectedCB = nil; blinkCloseSessionLocked()
        return true
    }
    /// Closed sessions waiting to be written. Each one is an immutable snapshot taken atomically under blinkLock at the
    /// moment the opt-in ended, so a later opt-in can neither reset nor consume it.
    private var blinkPendingSummaries: [(s: BlinkSession, inFlightAtOff: Bool)] = []
    /// Counters apply only to the session that was active when the frame was offered; a frame offered in a session that has
    /// since closed is not counted anywhere (it is reported as inFlightAtOff in that session's summary).
    private func blinkCount(sid: UInt64, _ f: (inout BlinkSession) -> Void) {
        blinkLock.lock(); if blinkSess.active && blinkSess.id == sid { f(&blinkSess) }; blinkLock.unlock()
    }
    /// Caller holds blinkLock.
    private func blinkCloseSessionLocked() {
        if blinkSess.active {
            blinkPendingSummaries.append((blinkSess, blinkBusy))
            if blinkPendingSummaries.count > 4 { blinkPendingSummaries.removeFirst() }   // bounded
        }
        blinkSess = BlinkSession()
    }
    private func blinkBeginSessionLocked() {
        blinkCloseSessionLocked()
        blinkSessionSeq &+= 1
        blinkSess = BlinkSession(); blinkSess.id = blinkSessionSeq; blinkSess.active = true
    }
    /// Writes one summary row per closed session (oldest first) and at most one OSD line, for the newest, and only if no
    /// newer session is running when it is delivered. If the blink log is full/stopped the row cannot be written and the
    /// OSD says so ("unavailable"); the summary write never stops the log and never re-enters the failure path.
    /// Runs on blinkQueue after any in-flight sample.
    func flushBlinkSummary(osd: ((String) -> Void)?) {
        blinkQueue.async { [weak self] in
            guard let self = self else { return }
            self.blinkLock.lock(); let pending = self.blinkPendingSummaries; self.blinkPendingSummaries = []; self.blinkLock.unlock()
            func f(_ v: Double?) -> String { v.map { String(format: "%.5f", $0) } ?? "null" }
            for (i, item) in pending.enumerated() {
                let s = item.s
                let dur: Double? = (s.tFirst != nil && s.tLast != nil) ? s.tLast! - s.tFirst! : nil
                let row = "{\"k\":\"blinkSummary\",\"session\":\(s.id),\"inFlightAtOff\":\(item.inFlightAtOff),\"sessionS\":\(f(dur)),\"offered\":\(s.offered),\"skippedBusy\":\(s.skippedBusy),\"ambientSkipped\":\(s.ambientSkipped),\"visionFailed\":\(s.visionFailed),\"staleDropped\":\(s.staleDropped),\"noFace\":\(s.noFace),\"noEyes\":\(s.noEyes),\"yawOver\":\(s.yawOver),\"usable\":\(s.usable),\"episodes\":\(s.candidates),\"blinksConfirmed\":\(s.blinksConfirmed),\"blinksPossible\":\(s.blinksPossible),\"closuresHeld\":\(s.closuresHeld),\"sparse\":\(s.sparse),\"gapBuckets\":\(s.gapBuckets),\"gapMaxS\":\(f(s.gapMax)),\"openBaseMin\":\(f(s.baseMin)),\"openBaseMax\":\(f(s.baseMax))}"
                let isNewest = (i == pending.count - 1)
                let text = "blink measurement session \(s.id) ended: offered \(s.offered), usable \(s.usable), no face \(s.noFace), no eyes \(s.noEyes), busy-skipped \(s.skippedBusy), episodes \(s.candidates), blinks \(s.blinksConfirmed) (+\(s.blinksPossible) possible), eye closures \(s.closuresHeld) (provisional rule, unvalidated)"
                let sid = s.id
                GeomTrace.logBlinkSummary(row) { [weak self] reason in
                    guard isNewest, let osd = osd, let self = self else { return }
                    self.blinkLock.lock(); let running = self.blinkLogOn; self.blinkLock.unlock()
                    if !running { osd("blink measurement session \(sid) summary \(reason)") }
                } written: { [weak self] in
                    guard isNewest, let osd = osd, let self = self else { return }
                    self.blinkLock.lock(); let running = self.blinkLogOn; self.blinkLock.unlock()
                    if !running { osd(text) }
                }
            }
        }
    }
    /// Visible feedback for the Shift+E measurement only (no command is bound). Called on the main thread with a short
    /// text on a closing/open edge and, at most once per Shift+E session, when most recent samples are too sparse to see
    /// a blink. Assigned by the controller while the blink log is on and cleared when it is off.
    private var blinkIndicatorCB: ((String) -> Void)?
    var onBlinkIndicator: ((String) -> Void)? {
        get { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkIndicatorCB }
        set { blinkLock.lock(); blinkIndicatorCB = newValue; blinkLock.unlock() }
    }
    /// Typed detection callback (main thread), set by the controller only while the opt-in is on; binds no command.
    private var blinkDetectedCB: ((BlinkDetection) -> Void)?
    var onBlinkDetected: ((BlinkDetection) -> Void)? {
        get { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkDetectedCB }
        set { blinkLock.lock(); blinkDetectedCB = newValue; blinkLock.unlock() }
    }
    private var blinkWasClosing = false
    private var blinkSparseRun = 0
    private var blinkSparseShown = false
    private var episodeTracker = BlinkEpisodeTracker()   // pure bookkeeping at the bottom of this file; touched only on blinkQueue
    static let blinkSparseRunToWarn = 20   // PROVISIONAL: 20 consecutive sparse samples
    private let latestEyeFrame=LatestMainFrame()
    private let latestPoseFrame=LatestMainFrame()
    private let latestLandmarkFrame=LatestMainFrame()
    private let frameLossLatch=FrameLossLatch()
    private let latestAmbientFrame=LatestMainFrame()
    private var controlDetector = BlinkControlDetector()
    private var lastBlinkFrameT:Double?
    private var controlEpoch: UInt64 = 0
    var onBlinkControl: ((BlinkControlDetector.Event) -> Void)?
    var onEyeCommand:((EyeGestureCommands.Command)->Void)?
    private var eyeGestureCommands=EyeGestureCommands()
    private var lastBlinkBoostSent: Double = -1   // 197i: last boost value on the wire
    var onEyeClosure: ((Double,Double,Bool) -> Void)?
    private var intentionalClosure=IntentionalEyeClosure()
    private var intentionalClosureRight=IntentionalEyeClosure()
    /// Blink sampling consumes the helper's typed landmark readings
    /// (arch-195z Z3 / arch-196b C6): Vision itself runs in the helper
    /// now; the epoch, gap, reliability-gate and delivery semantics
    /// below are unchanged from the in-process sampler this replaces.
    private func feedBlinkFrame(_ f: CameraHelperIPC.Frame, generation: UInt64) {
        guard blinkLogEnabled, !isAmbientOnlyActive else { return }
        let epoch = currentBlinkEpoch()
        if controlEpoch != epoch { controlEpoch=epoch; controlDetector.reset();eyeGestureCommands.reset();intentionalClosure.reset();intentionalClosureRight.reset() }
        let now = f.now
        let frameAge = f.age
        guard f.processed, !f.visionFailed else {
            intentionalClosure.reset();intentionalClosureRight.reset()
            _ = controlDetector.feed(t:now,left:nil,right:nil)
            _ = eyeGestureCommands.feed(t:now,left:nil,right:nil,reliable:false)
            latestEyeFrame.submit { [weak self] in
                guard let self,self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else { return };self.onEyeClosure?(0,0,true)
            }
            return
        }
        guard captureLifecycle().generation == generation else { return }
        if f.visionToken != 0, f.visionToken == currentExpiredVisionToken() { return }
        let lm = f.landmarks
        let elapsed = f.visionMS / 1000
        let frameGap=lastBlinkFrameT.map { now-$0 };lastBlinkFrameT=now
        GeomTrace.logBlink("{\"k\":\"blinkCadence\",\"t\":\(now),\"visionMS\":\(elapsed*1000),\"frameGapS\":\(frameGap ?? 0),\"configuredFPS\":30}")
        GeomTrace.logBlink("{\"k\":\"blinkTiming\",\"frameAgeMS\":\(frameAge*1000),\"detectMS\":\(elapsed*1000),\"intervalMS\":\((frameGap ?? 0)*1000),\"gapReset\":\((frameGap ?? 0)>EyeGestureCommands.maxFrameGap),\"stale\":\(frameAge+elapsed>EyeGestureCommands.maxFrameGap)}")
        // EAR from the raw normalized landmark points, exactly the
        // in-process sampler's ear() (no box scaling).
        func ear(_ points: [[Double]]?) -> Double? {
            guard let points, !points.isEmpty else { return nil }
            return EyeAperture.ear(points.map { ($0[0],$0[1]) })
        }
        let left=ear(lm?.leftEye),right=ear(lm?.rightEye)
        // Camera luma is a conservative safety floor in 0...255 encoded units, NOT ambient lux.
        // Missing/dark frames or uncertain landmarks fail open and cannot build a seek gesture.
        let reliable=(f.lumaLandmarkFace.map { $0.face>=24 } ?? false) && (lm?.confidence ?? 0)>=0.8 &&
            (lm?.landmarksConfidence ?? 0)>=0.65 &&
            abs(lm?.yaw ?? 0)<=Double.pi/12 && abs(lm?.pitch ?? 0)<0.5
        GeomTrace.logBlink("{\"k\":\"blinkGate\",\"reliable\":\(reliable),\"hasLeft\":\(left != nil),\"hasRight\":\(right != nil)}")
        let event=controlDetector.feed(t:now,left:reliable ? left:nil,right:reliable ? right:nil)
        let eyeCommand=eyeGestureCommands.feedCommand(t:now,left:left,right:right,reliable:reliable,frameAge:frameAge+elapsed,controlHeld:NSEvent.modifierFlags.contains(.control))
        // 197i: escalate the helper's blink admission while an episode is in
        // flight (closure edge or completed first blink under the thermal
        // stride). 0 clears. Unknown cmd on an old helper is a no-op.
        if EyeGestureCommands.cadenceAdaptive {
            let boost=eyeGestureCommands.blinkBoostUntil ?? 0
            if boost != lastBlinkBoostSent { lastBlinkBoostSent=boost; cameraHelper.blinkBoost(until: boost) }
        }
        if let eyeCommand {
            DispatchQueue.main.async { [weak self] in
                guard let self,self.blinkLogEnabled,self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else{return}
                let deliveryAge=CACurrentMediaTime()-now+frameAge
                GeomTrace.logBlink("{\"k\":\"blinkCommand\",\(eyeCommand.diagnosticFields),\"deliveryAgeMS\":\(deliveryAge*1000)}")
                guard deliveryAge<=EyeGestureCommands.maxFrameGap, eyeCommand != .playPause || NSEvent.modifierFlags.contains(.control) else { return }
                self.onEyeCommand?(eyeCommand)
            }
        }
        let closure=intentionalClosure.feed(t:now,left:left,right:nil,reliable:reliable)
        let closureRight=intentionalClosureRight.feed(t:now,left:right,right:nil,reliable:reliable)
        latestEyeFrame.submit { [weak self] in
            guard let self,self.blinkLogEnabled,self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else { return }
            let age=CACurrentMediaTime()-now+frameAge
            GeomTrace.logBlink("{\"k\":\"blinkDelivery\",\"ageMS\":\(age*1000),\"frameAgeMS\":\(frameAge*1000),\"detectMS\":\(elapsed*1000),\"mainHopMS\":\((age-frameAge-elapsed)*1000),\"lidL\":\(closure),\"lidR\":\(closureRight)}")
            self.onEyeClosure?(age<=EyeGestureCommands.maxFrameGap ? closure:0,age<=EyeGestureCommands.maxFrameGap ? closureRight:0,!reliable || age>EyeGestureCommands.maxFrameGap)
        }
        GeomTrace.logBlink("{\"k\":\"blinkEAR\",\"t\":\(now),\"left\":\(left.map { String($0) } ?? "null"),\"right\":\(right.map { String($0) } ?? "null"),\"event\":\"\(event?.rawValue ?? "none")\"}")
        if let event {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.blinkLogEnabled, self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else { return }
                self.onBlinkControl?(event)
            }
        }
    }

    // MARK: - Permission (Camera -- separate TCC gate from Screen Recording above)

    // Requested consumers and hardware state are separate. All public
    // transitions are main-thread-only; session work runs on sessionQueue.
    private var activeConsumers = 0
    private var lifecycleGeneration: UInt64 = 0
    private enum CameraState { case idle, authorizing, starting, running, stopping, failed }
    private var cameraState: CameraState = .idle {
        didSet { if cameraState != oldValue { traceSessionEvent("state-\(cameraState)") } }
    }
    private var permissionRequestInFlight = false
    var isRequested: Bool { activeConsumers > 0 }
    var isRunning: Bool { cameraState == .running || cameraState == .stopping }
    /// Trace-only attribution (GOR_TRACE_GEOM): consumers = every start() holder;
    /// ambientRequested = the ambient-dimming duty-cycle consumer is one of them.
    /// VR-owned consumers = consumers - (ambientRequested ? 1 : 0).
    var traceConsumers: (consumers: Int, ambientRequested: Bool) { (activeConsumers, hasRequestedAmbientStart) }

    /// GOR_TRACE_GEOM=1 only: every capture-session lifecycle event (any consumer start/stop
    /// and every camera state change) with full consumer attribution, so a brief session is
    /// recorded even between the 1 Hz VR ticks.
    private func traceSessionEvent(_ ev: String) {
        Diag.mediaRecord("HEAD-CAPTURE event=\(ev) consumers=\(activeConsumers) ambient=\(hasRequestedAmbientStart) generation=\(lifecycleGeneration) running=\(isRunning)")
        guard GeomTrace.on else { return }
        let vrOwned = activeConsumers - (hasRequestedAmbientStart ? 1 : 0)
        GeomTrace.log("vrCamera", "{\"k\":\"vrCamera\",\"why\":\"session-\(ev)\",\"sessionRequested\":\(activeConsumers > 0),\"sessionRunning\":\(cameraState == .running),\"consumers\":\(activeConsumers),\"ambient\":\(hasRequestedAmbientStart),\"vrOwned\":\(vrOwned)}")
    }

    // Callers retain their own per-consumer idempotence guards.
    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        if activeConsumers == 0 { lifecycleGeneration &+= 1 }
        activeConsumers += 1
        traceSessionEvent("consumer-start")
        publishLifecycle()
        // A join while the helper already runs changes its pipeline
        // shape (the in-process code read the lifecycle snapshot per
        // frame; cross-process the parent pushes it live).
        pushHelperConfig()
        ensureSessionRequested()
    }

    // Numeric owner IDs:1=head,2=blink,3=ambient. Gaze borrows, never acquires.
    func start(owner: Int) { start(); Diag.mediaRecord("HEAD-CAPTURE event=owner-acquire owner=\(owner) consumers=\(activeConsumers) generation=\(lifecycleGeneration)") }
    func stop(owner: Int) { stop(); Diag.mediaRecord("HEAD-CAPTURE event=owner-release owner=\(owner) consumers=\(activeConsumers) generation=\(lifecycleGeneration)") }

    private func ensureSessionRequested() {
        guard activeConsumers > 0, cameraState != .starting, cameraState != .running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession()
        case .notDetermined:
            cameraState = .authorizing
            guard !permissionRequestInFlight else { return }
            permissionRequestInFlight = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionRequestInFlight = false
                    guard self.activeConsumers > 0 else { return }
                    // Permission applies to the current request, not the old
                    // lifecycle that opened the system prompt.
                    if granted { self.ensureSessionRequested() }
                    else { self.cameraState = .failed }
                }
            }
        case .denied, .restricted:
            cameraState = .failed
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0, self.cameraState == .failed else { return }
                self.promptForCameraPermission()
            }
        @unknown default:
            cameraState = .failed
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeConsumers > 0 else { return }
        activeConsumers -= 1
        traceSessionEvent("consumer-stop")
        if activeConsumers > 0 { publishLifecycle(); pushHelperConfig(); return }
        lifecycleGeneration &+= 1
        cameraState = .stopping
        publishLifecycle()
        beginPoseSession()
        onEyeClosure?(0,0,true)
        PoseTraceRing.shared.append(t:CACurrentMediaTime(),raw:[],filtered:lastTracedPose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"trackingStop")
        lastAngles=(0,0,0)
        lastBoundingBox = nil
        let generation = lifecycleGeneration
        Diag.mediaRecord("HEAD-CAPTURE event=stop-request consumers=0 generation=\(generation)")
        DispatchQueue.main.asyncAfter(deadline: .now()+2) { [weak self] in
            guard let self, self.lifecycleGeneration == generation, self.cameraState == .stopping else { return }
            Diag.mediaRecord("HEAD-CAPTURE event=stop-pending generation=\(generation) elapsed_s=2 consumers=\(self.activeConsumers)")
        }
        // Z3 / 741ef8349, now enforced cross-process: the helper is
        // asked to stop and given 2 s to report hardware-stopped;
        // silence means SIGKILL, and process exit closes the
        // AVFoundation device. The completion reports only the final
        // state; the helper's own delegate/hardware events arrive as
        // relayed log lines.
        cameraHelper.stopSession(generation: generation) { stopped in
            Diag.mediaRecord("HEAD-CAPTURE event=hardware-stopped running=\(!stopped) stopped=\(stopped) generation=\(generation)")
            DispatchQueue.main.async {
                guard self.activeConsumers == 0, self.lifecycleGeneration == generation else { return }
                self.cameraState = stopped ? .idle : .failed
            }
        }
    }

    // MARK: - Ambient-only consumer (no pose delivery)
    // Ambient windows own one idempotent holder, independent of head/blink.
    // Closing the last window releases hardware without awaiting Vision.
    private var hasRequestedAmbientStart = false

    func startAmbientOnly() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !hasRequestedAmbientStart else { return }
        hasRequestedAmbientStart = true
        start(owner: 3)
    }

    func stopAmbientOnly() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasRequestedAmbientStart else { return }
        hasRequestedAmbientStart = false
        endAmbientReading()
        stop(owner: 3)
    }

    private func beginSession() {
        guard cameraState != .starting, cameraState != .running else { return }
        cameraState = .starting
        Diag.mediaRecord("HEAD-CAPTURE event=start-request consumers=\(activeConsumers) generation=\(lifecycleGeneration)")
        installHelperHandlerIfNeeded()
        let c = currentHelperConfig()
        // Session configuration, device selection, 30fps pinning,
        // mirroring off and VisionRequestDiag.camera all moved into
        // the helper (CameraHelperEngine.startIfNeeded); its
        // hardware-started/delegate lines come back as log events.
        cameraHelper.ensureRunning(generation: c.generation, window: c.window,
                                   headPose: c.headPose, blink: c.blink, ambientOnly: c.ambientOnly)
        // .starting -> .running happens on the helper's state=running
        // report (handleHelperIncoming), never optimistically: the
        // running state means the hardware confirmed, as the
        // in-process beginSession's post-startRunning read did.
    }

    /// The helper's one incoming stream is bound once. Frames carry
    /// their own generation and the ambientOnly shape they were
    /// produced under; lifecycle events are guarded against the live
    /// snapshot at handling time.
    private var helperHandlerInstalled = false
    private func installHelperHandlerIfNeeded() {
        guard !helperHandlerInstalled else { return }
        helperHandlerInstalled = true
        cameraHelper.onIncoming = { [weak self] incoming in
            self?.handleHelperIncoming(incoming)
        }
    }

    /// The current consumer shape as helper configuration: any head or
    /// blink consumer runs the full pipeline; a lone ambient consumer
    /// runs the lightweight ambient-only one. The in-process code read
    /// this snapshot per frame; cross-process the parent pushes it and
    /// the helper applies it live (configure on a running session
    /// never restarts hardware).
    private func currentHelperConfig() -> (generation: UInt64, window: UInt64, headPose: Bool, blink: Bool, ambientOnly: Bool) {
        let lifecycle = captureLifecycle()
        return (lifecycle.generation, ambientWindowID, !lifecycle.ambientOnly,
                blinkLogEnabled && !lifecycle.ambientOnly, lifecycle.ambientOnly)
    }
    private func pushHelperConfig() {
        guard activeConsumers > 0 else { return }
        let c = currentHelperConfig()
        cameraHelper.setConfig(generation: c.generation, window: c.window,
                               headPose: c.headPose, blink: c.blink, ambientOnly: c.ambientOnly)
    }

    @MainActor
    private func promptForCameraPermission() {
        let alert = NSAlert()
        alert.messageText = "Camera Access Needed for Tracking"
        alert.informativeText =
            "Gor needs Camera access for eye or head tracking.\n\n" +
            "System Settings -> Privacy & Security -> Camera -> enable Gor, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
            )
        }
    }

    // MARK: - Helper frame handling (arch-195z Z3 / arch-196b C6)

    /// Serial queue consuming the helper's typed readings. Replaces
    /// the frame/vision executor pair: Vision admission, throttling
    /// and the AE/AWB settle gate all run inside the helper now.
    private let helperQueue = DispatchQueue(label: "gor.headtrack.helper", qos: .userInitiated)

    private func handleHelperIncoming(_ incoming: CameraHelperClient.Incoming) {
        switch incoming {
        case .frame(let frame):
            helperQueue.async { [weak self] in
                self?.handleHelperFrame(frame, generation: frame.generation, ambientOnly: frame.ambientOnly)
            }
        case .log(let channel, let message):
            if channel == "diag" { Diag.log(message) } else { Diag.mediaRecord(message) }
        case .running(let generation):
            guard captureLifecycle().generation == generation else { return }
            // A fresh helper restarts its local Vision token at1. Never retain
            // the previous child's cancelled token across process supervision.
            visionCancelLock.lock(); expiredVisionToken=0; visionCancelLock.unlock()
            // Hardware-confirmed start: the in-process code set
            // .running after startRunning returned; cross-process the
            // helper's state report is that confirmation.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0, self.lifecycleGeneration == generation,
                      self.cameraState == .starting else { return }
                self.cameraState = .running
            }
        case .stopped(let generation, let stillRunning):
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifecycleGeneration == generation else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-stopped generation=\(generation) running=\(stillRunning)")
            }
        case .terminatedAfterTimeout:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-kill generation=\(self.lifecycleGeneration)")
            }
        case .visionCancelled(let token):
            // C2: the helper's watchdog cancelled that perform;
            // invalidate in-flight blink deliveries exactly as the
            // in-process bumpBlinkEpoch did.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visionCancelLock.lock(); self.expiredVisionToken = token; self.visionCancelLock.unlock()
                self.bumpBlinkEpoch()
            }
        case .failed(let reason):
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0 else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-failed reason=\(reason) generation=\(self.lifecycleGeneration)")
                self.cameraState = .failed
            }
        case .exited:
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0 else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-exit generation=\(self.lifecycleGeneration)")
                guard self.cameraState != .failed else { return }
                // One bounded automatic relaunch per consumer
                // generation (Z3): a fresh helper epoch, no retry
                // loop. A second unexpected exit goes .failed.
                guard self.relaunchGeneration != self.lifecycleGeneration else {
                    self.cameraState = .failed
                    return
                }
                self.relaunchGeneration = self.lifecycleGeneration
                self.cameraState = .idle
                self.beginSession()
            }
        }
    }

    private var lastHelperPoseTime:Double = 0 // helperQueue sole writer; reject late independent-worker pose.
    private func handleHelperFrame(_ f: CameraHelperIPC.Frame, generation: UInt64, ambientOnly: Bool) {
        let lifecycle = captureLifecycle()
        guard lifecycle.requested, lifecycle.generation == generation else { return }
        let now = f.now
        // C2: a watchdog-expired frame never delivers (the helper drops
        // it before sending; this is the belt-and-suspenders gate for a
        // frame that crossed the cancel notice in flight).
        if f.visionToken != 0, f.visionToken == currentExpiredVisionToken() { return }
        if !ambientOnly, blinkLogEnabled, f.delivery == "blink" || (f.delivery == nil && f.processed) { feedBlinkFrame(f, generation: generation) }
        if f.delivery == "blink",f.landmarks==nil {return}
        // Ambient publish: only frames from the current settle window
        // (resetAmbientSettling bumps the id the helper tags frames
        // with) and only after the helper's settle gate passed. The
        // reading epoch is the parent's own, sampled at handling time;
        // same publish discipline as the in-process code.
        if f.ambientSettled, f.window == ambientWindowID {
            // Face-found rule from the in-process code: ambient-only
            // used the rect face; head mode used the selected face.
            let faceFound = ambientOnly ? (f.rect != nil) : (f.landmarks != nil || f.rect != nil)
            if !faceFound {
                if f.processed, !f.visionFailed, let luma = f.lumaFull {
                    latestAmbientFrame.submit { [weak self] in
                        guard let self else { return }
                        self.publishAmbient(luma, regions: nil, generation: generation, epoch: self.ambientEpoch(), source: "full-frame")
                    }
                }
            } else if let regions2 = f.lumaRectFace {
                let regions = HeadTracker.TwoRegionLuma(faceLuma: regions2.face, roomLuma: regions2.room, combined: regions2.combined)
                latestAmbientFrame.submit { [weak self] in
                    guard let self else { return }
                    self.publishAmbient(regions2.combined, regions: regions, generation: generation, epoch: self.ambientEpoch(), source: "face-room")
                }
            }
            // Scalar fallback arms on every settled throttled frame,
            // including minimal ticks while the Vision slot is busy.
            if let luma = f.lumaFull {
                armAmbientFallback(luma, generation: generation, epoch: ambientEpoch())
            }
        }
        guard !ambientOnly else { return }
        guard f.processed, !f.visionFailed else { return }
        if f.delivery != "blink" {guard f.now>=lastHelperPoseTime else {return};lastHelperPoseTime=f.now}
        // Face selection from the in-process code: the landmark
        // observation when all three pose angles exist, else the
        // rectangle detection.
        let lm = f.landmarks
        let selectedIsLandmarks = lm != nil && lm?.yaw != nil && lm?.pitch != nil && lm?.roll != nil
        guard let selectedBox = selectedIsLandmarks ? lm?.box : f.rect?.box else {
            if !isAmbientOnlyActive {
                frameLossLatch.mark()
                latestPoseFrame.submit { [weak self] in
                    guard let self,self.activeConsumers>0,self.lifecycleGeneration==lifecycle.generation,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil),now>=self.poseSessionStartedAt else { return }
                    _=self.frameLossLatch.consume()
                    self.onGazeUpdate?(nil)
                    self.poseContinuity.faceLost();self.poseNoise.interrupt()
                    PoseTraceRing.shared.append(t:now,raw:[],filtered:self.lastTracedPose,confidence:0,faceLost:true,outlier:false,reacquire:false)
                }
            }
            return
        }
        let selYaw   = selectedIsLandmarks ? lm?.yaw   : f.rect?.yaw
        let selPitch = selectedIsLandmarks ? lm?.pitch : f.rect?.pitch
        let selRoll  = selectedIsLandmarks ? lm?.roll  : f.rect?.roll
        let selConfidence = selectedIsLandmarks ? (lm?.confidence ?? 0) : (f.rect?.confidence ?? 0)

        let pixelWidth = Double(f.pixelWidth), pixelHeight = Double(f.pixelHeight)
        let box = CGRect(x: selectedBox[0], y: selectedBox[1], width: selectedBox[2], height: selectedBox[3])
        // Landmark geometry in image pixels, identical math to the
        // in-process port (points are normalized inside the landmark
        // face box, which is normalized inside the image).
        func eyeCentre(_ points: [[Double]]?) -> (Double,Double)? {
            guard let points, !points.isEmpty, let lm, lm.landmarksConfidence >= 0.65 else { return nil }
            let x = points.reduce(0.0) { $0 + $1[0] } / Double(points.count)
            let y = points.reduce(0.0) { $0 + $1[1] } / Double(points.count)
            return ((lm.box[0]+x*lm.box[2])*pixelWidth,
                    (lm.box[1]+y*lm.box[3])*pixelHeight)
        }
        func aperture(_ points: [[Double]]?) -> Double? {
            guard let points, let lm, lm.landmarksConfidence >= 0.65 else { return nil }
            return EyeAperture.ear(points.map { ($0[0]*lm.box[2]*pixelWidth, $0[1]*lm.box[3]*pixelHeight) })
        }
        func eyeWidth(_ points: [[Double]]?) -> Double? {
            guard let points, points.count > 1, let lm else { return nil }
            let pts = points.map { ($0[0]*lm.box[2]*pixelWidth, $0[1]*lm.box[3]*pixelHeight) }
            var width = 0.0; for a in pts { for b in pts { width = max(width, hypot(a.0-b.0, a.1-b.1)) } }
            return width
        }
        let eyeCentres=[eyeCentre(lm?.leftEye),eyeCentre(lm?.rightEye)]
        let measuredWidths:[Double]=[eyeWidth(lm?.leftEye),eyeWidth(lm?.rightEye)].compactMap{$0}
        let eyeGeometry:[Double]=eyeCentres.flatMap{p in p.map{[$0.0,$0.1]} ?? []}
        let eyeApertures=[aperture(lm?.leftEye),aperture(lm?.rightEye)].compactMap{$0}
        let pupils=(eyeCentre(lm?.leftPupil),eyeCentre(lm?.rightPupil))
        let hasPupils=pupils.0 != nil && pupils.1 != nil
        let pupilLeft=hasPupils ? pupils.0:eyeCentre(lm?.leftEye)
        let pupilRight=hasPupils ? pupils.1:eyeCentre(lm?.rightEye)
        let landmarkKind=hasPupils ? "pupil":"eye"

        let landmarkConfidence:Double=lm?.landmarksConfidence ?? 0
        let frameAge:Double=f.age
        let landmarkFaceCount:Int=lm?.faceCount ?? 0
        let detectedFaceCount:Int=f.rect?.faceCount ?? 0
        let qualityFaceCount:Double=Double(landmarkFaceCount)
        // Head mode always ran the rectangle request alongside the
        // landmark one (blink pass with alsoFace, or the head-pose
        // pass), so poseRan is true here exactly as before.
        let frameQuality:[Double]=[f.quality?.mean ?? -1,f.lumaRectFace?.room ?? -1,f.quality?.contrast ?? -1,f.quality?.clipped ?? -1,landmarkConfidence,frameAge,qualityFaceCount,f.exposureChanging]
        let poseFaceCount:Int=detectedFaceCount
        let measuredAngles:[Double]=[selYaw,selPitch,selRoll].compactMap{$0}
        let measuredPupils:[Double]=[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0}
        let pairedPupilCoordinates:[Double]=[pupils.0?.0,pupils.0?.1,pupils.1?.0,pupils.1?.1].compactMap{$0}
        let rectangleOnly=f.delivery == "head"
        let structureReason=rectangleOnly
            ? PoseMeasurementValidity.rectangleReason(faceCount:poseFaceCount,angles:measuredAngles,box:box)
            : PoseMeasurementValidity.reason(faceCount:poseFaceCount,landmarkFaceCount:landmarkFaceCount,angles:measuredAngles,box:box,pupils:measuredPupils,landmarkConfidence:landmarkConfidence)
        let rawYaw   = Self.yawSign   * (selYaw   ?? 0)
        let rawPitch = Self.pitchSign * (selPitch ?? 0)
        let rawRoll  = Self.rollSign  * (selRoll  ?? 0)
        let observedBox:[Double]=[Double(box.minX)*pixelWidth,Double(box.minY)*pixelHeight,Double(box.width)*pixelWidth,Double(box.height)*pixelHeight]
        let observedLandmarkBox:[Double]=lm.map { [$0.box[0]*pixelWidth,$0.box[1]*pixelHeight,$0.box[2]*pixelWidth,$0.box[3]*pixelHeight] } ?? []
        let signedPoseAngles:[Double]=[rawYaw,rawPitch,rawRoll]
        let poseConfidence:Double=selConfidence
        let frameTimestamp:Double=f.pts.isFinite ? f.pts : -1

        let gaze = structureReason==0 && frameAge>=0 && frameAge<0.2
            ? BinocularGazeSample.measure(t:now,pupils:pairedPupilCoordinates,eyes:eyeGeometry,widths:measuredWidths,apertures:eyeApertures,yaw:rawYaw,pitch:rawPitch,roll:rawRoll):nil
        let deliverySlot=f.delivery == "blink" ? latestLandmarkFrame:latestPoseFrame
        deliverySlot.submit { [weak self] in
            guard let self, self.activeConsumers > 0,
                  self.lifecycleGeneration == lifecycle.generation, self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil), now>=self.poseSessionStartedAt else { return }
            if !rectangleOnly {self.onGazeUpdate?(gaze)}
            if f.delivery != "blink",self.frameLossLatch.consume() {
                self.poseContinuity.faceLost();self.poseNoise.interrupt()
                PoseTraceRing.shared.append(t:now,raw:[],filtered:self.lastTracedPose,confidence:0,faceLost:true,outlier:false,reacquire:false)
            }
            self.applyObservation(box: box, yaw: rawYaw, pitch: rawPitch, roll: rawRoll,confidence:poseConfidence,pupilLeft:pupilLeft,pupilRight:pupilRight,landmarkKind:landmarkKind,eyeApertures:rectangleOnly ? nil:eyeApertures,frameQuality:frameQuality,structureReason:structureReason,pairedPupils:pairedPupilCoordinates,eyeGeometry:eyeGeometry,eyeWidths:measuredWidths,faceBox:observedBox,landmarkBox:observedLandmarkBox,poseAngles:signedPoseAngles,framePTS:frameTimestamp,capturedAt:now,independentHead:rectangleOnly,auxiliaryOnly:f.delivery == "blink")
        }
    }

    // MARK: - Ambient luma (camera-fallback signal for AmbientLightProvider)
    fileprivate var lastAmbientLuma: Double?

    /// itself returned nil) -- it does NOT mean face/room luma were zero,
    /// and a consumer must not render a bare nil as "0%".
    ///
    /// Two independent readers: AmbientLightProvider.normalizedLevel()
    /// (same file) uses only the nil-vs-non-nil distinction to pick
    /// .fullFrame/.roomFace for logSourceChangeIfNeeded/
    /// currentSourceLabel below -- it does not read faceLuma/roomLuma
    /// themselves. PPController_Features.swift's tickScene() (a different
    /// file, see the handoff doc's HUD-richness requirement) reads the
    /// actual faceLuma/roomLuma values to populate the HUD's separate
    /// face/room percentages, independent of and alongside that mode
    /// label -- one is "which path ran", the other is "what it measured".
    ///
    /// internal, not fileprivate like lastAmbientLuma just above: that
    /// field has exactly one reader in this same file. This one is read
    /// from PPController_Features.swift too, a different file, so
    /// fileprivate would not compile there -- internal is the narrowest
    /// access level that still reaches that call site. Same threading
    /// contract as lastAmbientLuma: written only from captureOutput's
    /// main-queue hop, read only on the main thread.
    internal fileprivate(set) var lastAmbientRegions: TwoRegionLuma?

    /// Fires once per frame lastAmbientLuma is updated - lets a
    /// consumer that only wants a single fresh reading (see
    /// ContentAdaptiveDimming's ambient duty-cycle window) close the
    /// session the moment a real frame arrives, rather than waiting out
    /// a fixed worst-case-startup timeout.
    /// Same single-slot shape as onPoseUpdate above, for the same
    /// reason: exactly one current reader, no multiplexing needed yet.
    /// Deliberately separate from onPoseUpdate itself -- an ambient-
    /// only consumer has no interest in pose and must not be coupled
    /// to whatever VR's own onPoseUpdate assignment is doing.
    var onAmbientFrame: (() -> Void)?

    /// Cheap average-luma estimate over a downsampled grid of the
    /// pixel buffer -- deliberately NOT a full-resolution scan (this
    /// runs on every frame this consumer wants a reading from, same
    /// frameQueue as the Vision pipeline above, and doesn't need per-
    /// pixel precision for a single room-brightness scalar). Returns
    /// nil for pixel formats this doesn't know how to read luma from
    /// directly, rather than guessing.
    ///
    /// Assumes kCVPixelFormatType_32BGRA, which is what
    /// configureSessionIfNeeded above requests via videoOutput.videoSettings
    /// -- if that format request ever changes, this must change with it
    /// (this reads raw byte offsets, so a different format's channel
    /// order/bit depth would silently misread rather than fail loudly).
    static func averageLumaSingleRegion(of pixelBuffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width      = CVPixelBufferGetWidth(pixelBuffer)
        let height     = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        // ~24x24 sample grid regardless of actual capture resolution --
        // plenty for a single scalar, cheap enough to run every frame.
        let gridSize = 24
        let stepX = max(1, width  / gridSize)
        let stepY = max(1, height / gridSize)

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum: Double = 0
        var count: Double = 0
        var y = 0
        while y < height {
            var x = 0
            let rowOffset = y * bytesPerRow
            while x < width {
                // BGRA byte order: B, G, R, A per pixel.
                let offset = rowOffset + x * 4
                let b = Double(ptr[offset])
                let g = Double(ptr[offset + 1])
                let r = Double(ptr[offset + 2])
                // Rec. 601 luma weights -- consistent with treating this
                // as a plain brightness estimate, not a color-accurate
                // one; no different a choice than any other luma
                // approximation would be for this purpose.
                sum += 0.299 * r + 0.587 * g + 0.114 * b
                count += 1
                x += stepX
            }
            y += stepY
        }
        guard count > 0 else { return nil }
        // 0...255 range -- NOT yet normalized to 0...1 the way
        // ContentAdaptiveDimming's own on-screen luma is, and NOT
        // calibrated against real dim/bright rooms the way
        // lumaDarkThreshold/lumaBrightThreshold were against
        // gor_direct.log (see that constant's comment). See
        // AmbientLightProvider.normalizedLevel()'s camera-fallback
        // branch for where this raw value is consumed and the same
        // gap is called out again at its point of use.
        return sum / count
    }

    /// Result of a two-region ambient read: `faceLuma` is the average
    /// over the (margin-expanded) face box -- screen light reflecting
    /// off the user's face/neck/shoulders, an INDIRECT proxy for room
    /// light the camera can't see directly (ceiling, side walls --
    /// what bounces off them and onto the user is exactly what this
    /// region picks up). `roomLuma` is the average over every other
    /// sampled point -- background, directly-visible surfaces. `combined`
    /// is the single scalar AmbientLightProvider actually consumes;
    /// see its derivation below for why it's weighted the way it is.
    ///
    /// Deliberately NOT split further into top/side/bottom room
    /// sub-regions -- discussed and explicitly declined in favor of
    /// this simpler two-way split (face vs. everything-else) rather
    /// than a more granular one.
    struct TwoRegionLuma {
        let faceLuma: Double
        let roomLuma: Double
        let combined: Double
    }

    /// Face box expanded downward more than sideways before it's
    /// treated as "face" for masking purposes -- neck and shoulders
    /// (also screen-lit, also not room) sit below Vision's
    /// boundingBox, which crops tight to roughly chin-to-hairline,
    /// ear-to-ear. Not expanded upward: little bounce-relevant surface
    /// above the hairline within a typical webcam framing, and
    /// expanding up risks eating into background that's genuinely
    /// "room". These fractions are of the face box's OWN width/height
    /// (not the frame's), so they scale with how close the user is
    /// sitting rather than being a fixed pixel margin. Starting point,
    /// not measured against real framing -- cheap to retune, one
    /// constant each, if the split looks wrong once actually run
    /// against a camera.
    static let faceMarginSides: CGFloat  = 0.15
    private static let faceMarginTop: CGFloat    = 0.05
    private static let faceMarginBottom: CGFloat = 0.55

    // Existing room-majority ambient weighting; not calibrated lighting classification.
    static let faceBounceWeight: Double = 0.25

    /// Two-region variant of averageLumaSingleRegion above: same
    /// single-pass 24x24 grid walk (no extra scan, no second pass over
    /// the buffer -- each sampled point is classified face-or-room
    /// inline and added to the matching accumulator), but reports
    /// faceLuma and roomLuma separately in addition to the combined
    /// scalar. faceBox is expected in Vision's normalized (0...1,
    /// bottom-left-origin) coordinate space, same as
    /// VNFaceObservation.boundingBox is already handled elsewhere in
    /// this file (see applyObservation above) -- this function does
    /// the y-flip itself rather than assuming a caller already did.
    ///
    /// Returns nil under the exact same conditions
    /// averageLumaSingleRegion does (unsupported pixel format, buffer
    /// with no base address, zero width/height/stride) -- same
    /// contract, two-region is purely additive on top of it.
    static func averageLumaTwoRegion(of pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> TwoRegionLuma? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width      = CVPixelBufferGetWidth(pixelBuffer)
        let height     = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        // Expand faceBox by the margins above, each side clamped to
        // 0...1 independently so a face near a frame edge doesn't
        // produce an out-of-bounds rect (CGRect intersection/containment
        // below would just silently exclude anything past the edge
        // anyway, but clamping keeps expandedBox itself a well-formed
        // normalized rect rather than one with negative origin or
        // >1 extent).
        let dx = faceBox.width  * faceMarginSides
        let dyTop    = faceBox.height * faceMarginTop
        let dyBottom = faceBox.height * faceMarginBottom
        let expandedMinX = max(0, faceBox.minX - dx)
        let expandedMaxX = min(1, faceBox.maxX + dx)
        // Vision's boundingBox is bottom-left-origin: minY is the
        // LOWER edge on screen (toward chin/neck), maxY the UPPER
        // edge (toward hairline). "Bottom" margin (neck/shoulders)
        // therefore subtracts from minY; "top" margin adds to maxY.
        let expandedMinY = max(0, faceBox.minY - dyBottom)
        let expandedMaxY = min(1, faceBox.maxY + dyTop)

        let gridSize = 24
        let stepX = max(1, width  / gridSize)
        let stepY = max(1, height / gridSize)

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var faceSum: Double = 0
        var faceCount: Double = 0
        var roomSum: Double = 0
        var roomCount: Double = 0
        var y = 0
        while y < height {
            var x = 0
            let rowOffset = y * bytesPerRow
            // Normalize this sample point to the same 0...1,
            // bottom-left-origin space faceBox is already in:
            // y/height first gives 0...1 top-to-bottom (pixel-buffer
            // convention, row 0 = top), then 1.0 minus that fraction
            // flips it to Vision's bottom-to-top convention (y=0 at
            // the bottom of the image, y=1 at the top).
            let normY = 1.0 - (Double(y) / Double(height))
            while x < width {
                let offset = rowOffset + x * 4
                let b = Double(ptr[offset])
                let g = Double(ptr[offset + 1])
                let r = Double(ptr[offset + 2])
                let luma = 0.299 * r + 0.587 * g + 0.114 * b

                let normX = Double(x) / Double(width)
                let inFaceBox = normX >= Double(expandedMinX) && normX <= Double(expandedMaxX)
                                && normY >= Double(expandedMinY) && normY <= Double(expandedMaxY)
                if inFaceBox {
                    faceSum += luma
                    faceCount += 1
                } else {
                    roomSum += luma
                    roomCount += 1
                }
                x += stepX
            }
            y += stepY
        }
        // Empty accepted grids cannot provide luma evidence.
        guard roomCount > 0 else { return nil }
        let roomLuma = roomSum / roomCount
        let faceLuma = faceCount > 0 ? faceSum / faceCount : roomLuma
        // Preserve the calibrated room/face weighting and luma domain.
        let combined = roomLuma * (1.0 - faceBounceWeight) + faceLuma * faceBounceWeight
        return TwoRegionLuma(faceLuma: faceLuma, roomLuma: roomLuma, combined: combined)
    }

    // Main-thread pose state and callback delivery.
    private func applyObservation(box: CGRect, yaw: Double, pitch: Double, roll: Double,confidence:Double=1,pupilLeft:(Double,Double)?=nil,pupilRight:(Double,Double)?=nil,landmarkKind:String="pupil",eyeApertures:[Double]?=nil,frameQuality:[Double]=[],structureReason:Int=0,pairedPupils:[Double]=[],eyeGeometry:[Double]=[],eyeWidths:[Double]=[],faceBox:[Double]=[],landmarkBox:[Double]=[],poseAngles:[Double]=[],framePTS:Double = -1,capturedAt:Double?=nil,independentHead:Bool=false,auxiliaryOnly:Bool=false) {
        if let capturedAt,capturedAt<poseSessionStartedAt { return }; if structureReason != 0 {
            if auxiliaryOnly {independentDistance=nil;return}
            let t=CACurrentMediaTime();poseFollow?.hold(at:t);poseNoise.interrupt()
            PoseTraceRing.shared.append(t:t,raw:[],filtered:lastTracedPose,confidence:confidence,faceLost:false,outlier:false,reacquire:false,frameQuality:frameQuality,structureReason:structureReason,pairedPupils:pairedPupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,faceBox:faceBox,landmarkBox:landmarkBox,poseAngles:poseAngles,framePTS:framePTS)
            return
        }
        if let eyes=eyeApertures,!poseEyeGate.accept(eyes) {
            if auxiliaryOnly {independentDistance=nil;return}
            let t=CACurrentMediaTime();poseFollow?.hold(at:t);poseNoise.interrupt()
            PoseTraceRing.shared.append(t:t,raw:[yaw,pitch,roll,0,0,lastTracedPose[5]],filtered:lastTracedPose,confidence:confidence,faceLost:false,outlier:false,reacquire:false,pupils:[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0},eyeHold:true,eyeApertures:eyes,frameQuality:frameQuality,pairedPupils:pairedPupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,faceBox:faceBox,landmarkBox:landmarkBox,poseAngles:poseAngles,framePTS:framePTS)
            return
        }
        var distanceReady=false,zRelative=lastTracedPose[5],distanceUsedPupils=false,distanceConsistent=false
        if independentHead {
            if let d=independentDistance,let t=capturedAt,t>=d.at,t-d.at<0.2 {distanceReady=d.ready;zRelative=d.relative;distanceConsistent=d.ready;distanceUsedPupils=d.ready}
        } else {
            // Anatomy ratios do not change on recenter or approach/retreat. Keep
            // valid angle/translation updates active when distance geometry deforms.
            let distancePoints:[Double]=[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0}
            distanceConsistent = !(landmarkKind != "pupil" && pupilDistanceScale.hasPupilReference) && poseDistanceConsistency.accept(pupils:distancePoints,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch,landmarkKind:landmarkKind)
            // Acquisition anatomy samples are not movement. Arm only this distance sensor after its existing33sample calibration.
            distanceReady=distanceConsistent && poseDistanceConsistency.ready(for:landmarkKind)
            let distance=pupilDistanceScale.sample(left:distanceReady ? pupilLeft:nil,right:distanceReady ? pupilRight:nil,yaw:yaw,fallbackWidth:Double(box.width),landmarkKind:landmarkKind)

            zRelative=distance.relative;distanceUsedPupils=distance.usedPupils
            if auxiliaryOnly {independentDistance=(capturedAt ?? CACurrentMediaTime(),zRelative,distanceReady);return}
        }
        lastBoundingBox = box;lastAngles=(yaw,pitch,roll)
        if baselineBoxSize == nil {
            PoseTraceRing.shared.append(t:CACurrentMediaTime(),raw:[],filtered:lastTracedPose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"baselineSeed")
            baselineBoxSize   = max(box.width, box.height)
            baselineBoxCenter = CGPoint(x: box.midX, y: box.midY)
            neutralAngles=(yaw,pitch,0) // physical roll remains absolute, never recentered away.
        }
        let refCenter = baselineBoxCenter ?? CGPoint(x: box.midX, y: box.midY)
        let zOffset = zRelative
        let xOffset = Self.xOffsetSign * Double(box.midX - refCenter.x)
        let yOffset = Self.yOffsetSign * Double(box.midY - refCenter.y)

        func relative(_ x:Double,_ base:Double)->Double { atan2(sin(x-base),cos(x-base)) }
        let raw = HeadPose(yaw:relative(yaw,neutralAngles.yaw),pitch:relative(pitch,neutralAngles.pitch),roll:relative(roll,neutralAngles.roll),
                           xOffset: xOffset, yOffset: yOffset, zOffset: zOffset)
        let now = CACurrentMediaTime()
        let rawChannels=[raw.yaw,raw.pitch,raw.roll,raw.xOffset,raw.yOffset,raw.zOffset]
        let heldChannels:Set<Int>=distanceReady ? []:[5]
        let continuity=poseContinuity.accept(rawChannels,t:now,heldChannels:heldChannels), c=continuity.values
        var filtered = smooth(HeadPose(yaw:c[0],pitch:c[1],roll:c[2],xOffset:c[3],yOffset:c[4],zOffset:c[5]), at: now,distanceValid:distanceReady)
        let euroRoll=filtered.roll
        let euro=[filtered.yaw,filtered.pitch,filtered.roll,filtered.xOffset,filtered.yOffset,filtered.zOffset]
        if continuity.reacquire || !distanceReady {poseNoise.interrupt()} else {poseNoise.observe(euro)}
        if poseFollow==nil,let bands=poseNoise.bands {
            // Fixed per-source follow: native angular25ms, other channels100ms. No fast/quiet mode.
            poseFollow=PoseBacklashFollow(bands:bands,taus:nativeMotionResponsive ? [0.025,0.025,0.025,0.1,0.1,0.1]:Array(repeating:0.1,count:6))
            _=poseFollow?.accept(previousPoseOutput ?? euro,at:now-1.0/30)
        }
        let followed=poseFollow?.accept(euro,at:now,heldChannels:heldChannels) ?? euro
        // 197i hold lock (gor.vr.poseHoldLock): final output stage, Schmitt
        // hold per channel; release on the first out-of-band sample (zero
        // added latency), re-lock after the output stays within half the
        // band for holdSettleSeconds. z keeps the 191a hysteresis instead.
        // A reacquire restarts the locks so a recovered face is not frozen.
        let final:[Double]
        if Self.poseHoldLock {
            if continuity.reacquire { poseHoldLocks=nil }
            if poseHoldLocks==nil { poseHoldLocks=(0..<5).map { PoseHoldLock(box: $0>=3) } }
            final=(0..<5).map { poseHoldLocks![$0].filter(followed[$0],t:now) } + [followed[5]]
        } else {
            final=followed
        }
        previousPoseOutput=final
        filtered=HeadPose(yaw:final[0],pitch:final[1],roll:final[2],xOffset:final[3],yOffset:final[4],zOffset:final[5])
        filtered.fusionRoll=euroRoll;filtered.nativeRawRoll=euroRoll
        lastTracedPose=final
        PoseTraceRing.shared.append(t:now,raw:rawChannels,filtered:lastTracedPose,confidence:confidence,faceLost:false,outlier:continuity.outlier,reacquire:continuity.reacquire,euro:euro,bands:poseNoise.bands ?? [],pupils:[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0},distanceMode:distanceConsistent ? (distanceUsedPupils ? (landmarkKind=="pupil" ? 1:2):0):3,eyeApertures:eyeApertures ?? [],frameQuality:frameQuality,pairedPupils:pairedPupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,faceBox:faceBox,landmarkBox:landmarkBox,poseAngles:poseAngles,framePTS:framePTS)
        // AVCaptureDevice.Format.videoFieldOfView is unavailable on macOS (confirmed by the native compiler).
        // Do not use KVC or a guessed lens angle: block182 explicitly selects constant-mm when hfov is absent.
        let cameraHFOVDegrees: Double? = nil
        if let fov = cameraHFOVDegrees, fov > 0, box.width > 0 {
            let dRaw = VRDistance.distanceMM(hfovDeg: fov, boxWidthNorm: Double(box.width))
            filtered.distanceRawMM = dRaw
            filtered.distanceMM = fD.filter(dRaw, at: now)
        } else {
            filtered.distanceFallback = "fov-unavailable"   // no camera fov (or no box): constant-mm rule only
        }
        if GeomTrace.on {
            // Raw + filtered pose per camera frame, timestamped, only while head tracking runs
            // (the existing camera lifetime). Order: yaw, pitch, roll, x, y, z.
            GeomTrace.log("poseTrace", String(format: "{\"k\":\"poseTrace\",\"t\":%.4f,\"raw\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f],\"f\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f]}",
                now, raw.yaw, raw.pitch, raw.roll, raw.xOffset, raw.yOffset, raw.zOffset,
                filtered.yaw, filtered.pitch, filtered.roll, filtered.xOffset, filtered.yOffset, filtered.zOffset))
            GeomTrace.log("distTrace", String(format: "{\"k\":\"distTrace\",\"t\":%.4f,\"dRawMM\":%@,\"dFilteredMM\":%@,\"fallback\":\"%@\"}",
                now, filtered.distanceRawMM.map { String(format: "%.2f", $0) } ?? "null",
                filtered.distanceMM.map { String(format: "%.2f", $0) } ?? "null", filtered.distanceFallback ?? "ok"))
        }
        onPoseUpdate?(filtered)
    }

    /// GOR_VR_SIM_POSE=1 only (self-test, no camera): drives the same applyObservation path with a
    /// deterministic synthetic head: 3 s still with jitter, a 0.5 s turn to 0.5 rad, 3 s hold, repeat.
    private var simTimer: DispatchSourceTimer?
    func startSimulatedPose() {
        stopSimulatedPose()
        resetFilters()
        var n = 0
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func noise() -> Double {   // deterministic, roughly uniform in [-1, 1]
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 30) - 1.0
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        t.setEventHandler { [weak self] in
            let sec = Double(n) / 30.0; n += 1
            let phase = sec.truncatingRemainder(dividingBy: 6.5)
            let turn = phase < 3.0 ? 0.0 : min(1.0, (phase - 3.0) / 0.5)
            let w = 0.3 * (1.0 + 0.01 * noise())
            self?.applyObservation(box: CGRect(x: 0.35, y: 0.35, width: w, height: w),
                                   yaw: 0.5 * turn + 0.003 * noise(), pitch: 0.003 * noise(), roll: 0.002 * noise())
        }
        t.resume()
        simTimer = t
    }
    func stopSimulatedPose() { simTimer?.cancel(); simTimer = nil }
}

// ================================================================
//  AmbientLightProvider -- room-light source for
//  ContentAdaptiveDimming (PPController_Features.swift)
//
//  Kept in this file rather than a separate one because its only
//  non-Foundation/IOKit dependency is HeadTracker.lastAmbientLuma
//  just above -- same reasoning as HeadTracker itself living here
//  rather than its own file (see this file's own header). Moving
//  here also let lastAmbientLuma's access level drop from internal
//  back to private (see that property's own comment for why it was
//  internal in the first place): now that both are in the same
//  file, a same-file private is exactly as visible as this class
//  needs and no more.
// ================================================================

/// Single source of truth for "how bright is the room", consumed by
/// ContentAdaptiveDimming's tickScene() (see that file's
/// ambientSceneTBoost comment for exactly how this value is used --
/// a bright room supports MORE backlight on top of what content-luma
/// alone decided, one-directionally, never as a hard dependency, and
/// never past the panel's own ceiling).
///
/// Two sources, preferred in this order:
///   1. A real Apple ambient light sensor (ALS), read via IOKit --
///      preferred because it's a direct lux measurement.
///   2. HeadTracker's camera-fallback average-luma reading, used only
///      when no ALS exists on the running Mac (see isAvailable below).
///      This is a WEAKER signal (auto-exposure compensates for room
///      brightness, so the raw value moves less than true lux would --
///      see HeadTracker.averageLumaSingleRegion/averageLumaTwoRegion's
///      own comments above) but still better than no ambient signal at
///      all on hardware with no ALS.
///
/// NOT calibrated against real hardware. Developed and tested on a Mac
/// with no ALS present at all -- meaning branch 1 below (the real-
/// sensor path) has never actually executed against live data, only
/// been written against Apple's known-but-undocumented ALS IOKit
/// pattern (matching on "AppleLMUController"/"AppleLisSensor"-family
/// services historically used for keyboard backlight + display auto-
/// brightness on machines that have a sensor). If the service name,
/// key name, or units below don't match a real device's ALS, this
/// silently reports isAvailable == false rather than a wrong number
/// -- see rawLux()'s own comment for why that's the deliberate
/// fallback rather than guessing at a plausible-looking value.
final class AmbientLightProvider {
    static let shared = AmbientLightProvider()

    private init() {
        // One-time probe at construction, not per-call: IOKit service
        // matching is not free, and "does this Mac have an ALS" cannot
        // change while the process is running (it's a hardware fact),
        // so there is nothing to gain from re-probing on every
        // normalizedLevel() call the way there would be for a value
        // that can actually change at runtime.
        self.alsServiceAvailable = Self.probeALSService()
        // Logged unconditionally, not just on the "no ALS" branch: a
        // reading later in gor_direct.log has no other way to tell
        // which of the two very different-quality paths (real lux vs.
        // camera auto-exposure proxy -- see normalizedLevel()'s own
        // comment on why these should not be trusted equally)
        // ambient-level numbers in this run's HUD/log actually came
        // from. Without this line, "ambient: 8%" by itself is
        // ambiguous between the two.
        print("[AmbientLightProvider] alsServiceAvailable=\(alsServiceAvailable) -- \(alsServiceAvailable ? "real ALS path" : "camera-fallback path (see HeadTracker)")")
    }

    private let alsServiceAvailable: Bool

    /// SMOOTHING FOR THE CAMERA-FALLBACK PATH ONLY (not the real-ALS
    /// path a few lines below, which reads live hardware every call
    /// and has never needed this) -- see this property's own use in
    /// normalizedLevel() for the full root-cause writeup. Short
    /// version: HeadTracker.lastAmbientLuma is only refreshed on the
    /// ambient duty cycle's own irregular schedule (each
    /// openAmbientWindow()/closeAmbientWindow() pair, gated further by
    /// ambientConsecutiveSettledFrames in HeadTracker -- see that
    /// property's own comment), not once per normalizedLevel() call.
    /// Reading it raw here means whatever cadence/jitter that gate
    /// introduces passes straight through to sceneT/target/inertia in
    /// ContentAdaptiveDimming.tickScene() with zero absorption -- a
    /// single stale-then-fresh jump in lastAmbientLuma becomes a
    /// same-tick jump in backlight target, which can flip
    /// backlightFalling and snap between backlightInertiaBright (0.12)
    /// and backlightInertiaDark (0.88) even while on-screen content
    /// (contentSceneT) is completely stable. This mirrors
    /// ContentAdaptiveDimming's own smoothedLuma/lumaSmoothing for
    /// content-luma and photon.lua's photon_scene_smooth_peak/contrast
    /// for the same class of problem (a value that only refreshes
    /// periodically needs its own EMA before feeding a per-tick
    /// consumer) -- ambientLevel was the one signal in this chain that
    /// skipped it.
    private var smoothedAmbientLevel: Double?

    /// Same shape as ContentAdaptiveDimming.lumaSmoothing (0.12): low
    /// alpha, deliberately slower than a real hardware ALS would need,
    /// BECAUSE the input here refreshes far less often (an ambient duty
    /// cycle window, not every tick) -- smoothing a value that already
    /// only updates a few times a second with too fast an alpha would
    /// barely reduce the jump this exists to absorb. Not tuned against
    /// real duty-cycle-interval data; a conservative starting point
    /// carried over from the content-luma constant it mirrors, and
    /// worth revisiting once ambientLuxFloor/ambientLuxCeiling
    /// themselves get calibrated (see this class's own header on that
    /// still being outstanding).
    private static let ambientLevelSmoothing: Double = 0.12

    /// True iff a real ALS was found on this Mac. Callers (see
    /// ContentAdaptiveDimming.updateAmbientCameraFallback()) use this
    /// to decide whether the camera-fallback consumer is even needed
    /// -- if a real ALS exists, the camera should never be opened for
    /// ambient light purposes at all.
    var isAvailable: Bool { alsServiceAvailable }

    // MARK: - Real ALS path (IOKit)
    //
    // UNVERIFIED AGAINST REAL HARDWARE -- see class header. The
    // service-name and key-name candidates below are the ones publicly
    // documented (via reverse-engineering writeups of
    // AppleALS/AppleLMUController) as used across recent Mac laptops
    // with an ambient light sensor; this has not been confirmed
    // against gor_direct.log or any equivalent real-device log the way
    // lumaDarkThreshold/lumaBrightThreshold were (see that constant's
    // comment in PPController_Features.swift). Do not treat
    // the numbers this path returns as trustworthy until it has been
    // run on real ALS-equipped hardware and its output checked against
    // known room conditions.
    private static let candidateServiceNames = ["AppleLMUController", "AppleALSSensor"]

    /// Returns whether an ALS-matching IOKit service exists on this
    /// Mac. Does NOT attempt to read a value -- existence-only, so a
    /// service name that matches but whose key layout turns out to be
    /// wrong still correctly reports "available" here (the failure
    /// then shows up as rawLux() returning nil on every call, which
    /// normalizedLevel() already treats as "fall through to camera",
    /// rather than this method silently lying about availability).
    private static func probeALSService() -> Bool {
        for name in candidateServiceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            if service != 0 {
                IOObjectRelease(service)
                return true
            }
        }
        return false
    }

    /// Attempts a real lux reading from the matched ALS service.
    /// Returns nil on ANY uncertainty -- wrong key name, unexpected
    /// value type, zero services found -- rather than returning a
    /// number that might be silently wrong. A nil here is exactly as
    /// safe as "no ALS at all" to normalizedLevel()'s caller, because
    /// that caller already treats nil as "fall through to camera or
    /// report no ambient signal this tick" (see tickScene's own `if
    /// let ambientLevel` branch) -- there is no path in this file
    /// where guessing a value would be better than admitting it
    /// doesn't have one.
    ///
    /// KEY NAME PLACEHOLDER: "IOLux0"/"IOLux1" below are candidate
    /// property keys seen in reverse-engineered ALS drivers, NOT
    /// confirmed against this codebase's own hardware. If this
    /// consistently returns nil on a machine confirmed via
    /// System Information to have an ALS, this key name -- not the
    /// surrounding logic -- is the first thing to check.
    private func rawLux() -> Double? {
        for name in Self.candidateServiceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }

            for key in ["IOLux0", "IOLux1", "IOALSSensorReading"] {
                if let cfValue = IORegistryEntryCreateCFProperty(
                    service, key as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() {
                    if let num = cfValue as? NSNumber {
                        return num.doubleValue
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Calibration (real ALS path)
    //
    // PLACEHOLDER -- NOT calibrated against real measurements, exactly
    // the gap tickScene's ambientSceneTBoost comment (in
    // PPController_Features.swift) calls out and says to fix at the
    // same time as this. A real ALS reports raw lux (roughly:
    // candlelight ~1, office ~500, overcast daylight ~1000-10000,
    // direct sun ~30000+) -- these two numbers are a placeholder
    // "plausible indoor range" guess, not derived from any logged
    // reading the way lumaDarkThreshold/lumaBrightThreshold were
    // against gor_direct.log. Do not treat normalizedLevel()'s
    // real-ALS branch as trustworthy until these are replaced with
    // real measured values from a real ALS-equipped Mac in a real dim
    // room and a real bright room.
    private let ambientLuxFloor: Double = 5.0
    private let ambientLuxCeiling: Double = 500.0

    // MARK: - Camera-fallback raw floor/ceiling (0...255 Rec.601 space)
    //
    // ROOT CAUSE (user-reported: ambient reading never climbs past
    // ~65-70% regardless of how brightly the room is actually lit).
    // The camera-fallback path was normalizing raw (0...255) straight
    // through raw/255.0 -- treating the front-facing webcam as if it
    // were a linear, uncalibrated light meter spanning the sensor's
    // full digital range. It is not: the camera's own auto-exposure
    // continuously re-targets the frame toward a mid-gray average
    // (that's what AE *is* -- see any camera ISP documentation on
    // auto-exposure/auto-gain convergence), which is exactly what lets
    // it produce a usable face/room image across a wide range of real
    // room brightness without either blowing out or crushing to black.
    // The side effect: it compresses the top of its own reportable
    // range. A genuinely bright room does not push the sensor's raw
    // reading anywhere near 255 (paper-white) the way a raw/uncalibrated
    // sensor would -- AE has already pulled exposure down to compensate
    // before the frame is even delivered. 255 is the sensor's digital
    // ceiling, not a reachable "very bright room" reading; using it as
    // the normalization ceiling means normalizedLevel() can structurally
    // never report anywhere close to 1.0 through this path, regardless
    // of true room brightness -- matching the reported ~65-70% cap
    // exactly (it's a property of AE-compensated sensor output, not a
    // bug in the averaging math itself, which is a correct, unweighted
    // Rec.601 mean).
    //
    // This branch therefore clamps to the realistic reportable range
    // instead of the sensor's theoretical one, the same floor/ceiling pattern
    // ambientLuxFloor/ambientLuxCeiling already use for the real-ALS
    // path just above -- keeping both branches of this class shaped
    // the same way (raw reading -> clamp to a calibrated
    // [floor, ceiling] -> normalize) rather than one clamped and one
    // raw. Deliberately a FIXED recalibration, not session-adaptive
    // (e.g. auto-ranging against observed min/max): contentSceneT and
    // photon.lua's own avg_pq both reason about scene brightness in
    // absolute terms (see lumaDarkThreshold/lumaBrightThreshold's own
    // comment -- calibrated once against real logged content,
    // not re-derived per session), and ambientLevel is compared
    // directly against contentSceneT in tickScene's sceneT formula --
    // an adaptive ceiling would make ambientLevel a RELATIVE reading
    // ("brighter than this session's own darkest moment so far") being
    // subtracted from an ABSOLUTE one, which stops meaning what the
    // formula assumes it means. It would also start every session
    // under-ranged (first window has no observed spread yet) and stay
    // narrow/noise-prone in the common case of a genuinely stable room
    // (little real spread ever observed to range against) -- the
    // opposite of what a duty cycle built around "room light changes on
    // a timescale of minutes" (see ambientCheckpointFractions's own
    // comment in PPController_Features.swift) should produce.
    //
    // NOT calibrated against a real logged session (no equivalent to
    // gor_direct.log exists yet for raw camera-fallback ambient values
    // specifically -- see this class's own header on that same gap for
    // ambientLuxFloor/Ceiling). 180 is a reasoned placeholder: a
    // genuinely bright, well-lit room read through an AE-compensated
    // webcam typically lands well short of the sensor's 255 ceiling in
    // informal observation of consumer webcam behavior, without a
    // measured figure specific to this codebase's camera path to anchor
    // it more precisely. Revisit together with ambientLuxFloor/Ceiling
    // once real measured readings (dim room vs. bright room, through
    // this actual capture path) exist for either branch -- flagged the
    // same way, for the same reason, rather than left to look more
    // authoritative than it is.
    private let cameraRawFloor: Double = 10.0
    private let cameraRawCeiling: Double = 180.0

    // MARK: - Public read

    // Tracks which branch normalizedLevel() actually used on its most
    // recent call, purely so the print below only fires on a CHANGE --
    // this function runs every tickScene() tick (0.4s cadence), so
    // logging every call would spam gor_direct.log for no benefit; a
    // source change is a rare, meaningful event (ALS driver coming up
    // late, or the very first camera-fallback frame arriving) and is
    // exactly the moment worth recording.
    private enum Source: Equatable { case none, als, fullFrame, roomFace }
    private var lastLoggedSource: Source = .none

    /// Stable string form of lastLoggedSource for consumers outside
    /// this file (writeSceneStateToMPV -> Lua HUD) that want to show
    /// WHICH path produced normalizedLevel()'s most recent non-nil
    /// return, without this file exposing the Source enum itself
    /// (Lua/JSON has no use for a Swift enum, and keeping Source
    /// private preserves the freedom to rename/add cases here without
    /// touching call sites). Reflects lastLoggedSource as of the most
    /// recent normalizedLevel() call -- same one-call-behind relationship
    /// as everything else reading lastLoggedSource; there is no reading
    /// this before normalizedLevel() has been called at least once
    /// (defaults to "none", which is also its true state before the
    /// first call, so no separate "not yet called" case is needed).
    /// These four raw values are a small, deliberately stable contract
    /// with photon.lua's HUD section -- if a case is renamed here, the
    /// Lua-side string match must be updated in the same change.
    var currentSourceLabel: String {
        switch lastLoggedSource {
        case .none:      return "none"
        case .als:       return "als"
        case .fullFrame: return "camera-full_frame"
        case .roomFace:  return "camera-room_face"
        }
    }

    /// Raw, unclamped lux from the most recent successful rawLux()
    /// read -- distinct from normalizedLevel()'s 0...1 return, which
    /// is that same number after ambientLuxFloor/ambientLuxCeiling
    /// clamping. Only ever non-nil when lastLoggedSource == .als;
    /// explicitly reset to nil on every other branch of
    /// normalizedLevel() (camera fallback or no reading) so a caller
    /// reading this after a source change never sees a stale lux
    /// value left over from a previous ALS tick. Exists purely for
    /// the HUD (photon.lua) to show the ALS branch's actual
    /// unnormalized reading next to normalizedLevel()'s calibrated
    /// percentage -- normalizedLevel() itself never reads this back.
    private(set) var lastRawLux: Double?

    /// 0...1, where 0 = darkest reading this provider knows about and
    /// 1 = brightest. nil when no reading is available this call --
    /// see each branch below for exactly when that happens. Prefers
    /// the real ALS; falls through to the camera proxy only when no
    /// ALS was found at construction time.
    func normalizedLevel() -> Double? {
        if alsServiceAvailable, let lux = rawLux() {
            logSourceChangeIfNeeded(.als)
            lastRawLux = lux
            let clamped = min(max(lux, ambientLuxFloor), ambientLuxCeiling)
            return (clamped - ambientLuxFloor) / (ambientLuxCeiling - ambientLuxFloor)
        }
        lastRawLux = nil

        // Camera-fallback branch: only reached when no ALS was found
        // (or, on a machine that IS reporting a matching service name
        // but wrong keys, rawLux() returning nil every time -- also
        // correctly falls through here rather than reporting a bad
        // number). Requires macOS 12+ the same way HeadTracker itself
        // does; on an older OS this returns nil unconditionally and
        // ContentAdaptiveDimming behaves exactly as it did before this
        // provider existed (see that class's own `else` branch).
        guard #available(macOS 12.0, *) else {
            logSourceChangeIfNeeded(.none)
            return nil
        }
        guard let raw = HeadTracker.shared.lastAmbientLuma else {
            logSourceChangeIfNeeded(.none)
            return nil
        }
        // Which of the two averaging paths produced `raw` this tick --
        // read alongside raw itself (both on HeadTracker, both written
        // together in the same main-queue hop in captureOutput, so
        // there's no window where one is stale relative to the other).
        // nil/non-nil is the only thing checked here -- the actual
        // faceLuma/roomLuma values inside lastAmbientRegions are a
        // separate consumer's concern (see that property's own comment).
        logSourceChangeIfNeeded(HeadTracker.shared.lastAmbientRegions != nil ? .roomFace : .fullFrame)

        // raw is 0...255 (see HeadTracker.averageLumaSingleRegion/
        // averageLumaTwoRegion's own comments on why an unnormalized
        // Rec.601 luma sum is returned either way).
        //
        // NOTE: raw here is already the face/room-combined scalar when
        // the two-region path ran this frame (see averageLumaTwoRegion's
        // faceBounceWeight) -- this function has no visibility into
        // whether single- or two-region produced it, by design; that
        // choice and its weighting live entirely in HeadTracker, this
        // stays a single opaque 0...255 reading same as before the
        // two-region split existed.
        //
        // WHY clamp, not raw/255.0: 255 is the AE-compensated sensor's
        // unreachable digital ceiling, not a reachable "very bright
        // room" reading (see cameraRawFloor/cameraRawCeiling above) -
        // raw/255.0 caps this path at ~65-70% regardless of true room
        // brightness. Clamped against the calibrated range, same shape
        // as the real-ALS branch (clamp to [floor, ceiling], then
        // normalize that span to 0...1).
        let normalizedRaw = (min(max(raw, cameraRawFloor), cameraRawCeiling) - cameraRawFloor)
            / (cameraRawCeiling - cameraRawFloor)

        // EMA against the previous smoothed value -- see
        // smoothedAmbientLevel's own comment for why this exists at
        // all. First call (smoothedAmbientLevel == nil, e.g. right
        // after the very first ambient window of a session) snaps
        // straight to the raw reading rather than easing in from some
        // assumed starting point -- there is no "previous" ambient
        // level to glide from yet, matching how ContentAdaptiveDimming
        // seeds smoothedLuma from rawLuma on its own first tick
        // (`smoothedLuma ?? rawLuma`).
        let smoothed = smoothedAmbientLevel.map { prev in
            prev + (normalizedRaw - prev) * Self.ambientLevelSmoothing
        } ?? normalizedRaw
        smoothedAmbientLevel = smoothed
        return smoothed
    }

    private func logSourceChangeIfNeeded(_ source: Source) {
        guard source != lastLoggedSource else { return }
        lastLoggedSource = source
        let label: String
        switch source {
        case .none:     label = "no reading (no ALS, camera not warmed up yet, or macOS < 12)"
        case .als:      label = "real ALS"
        case .fullFrame: label = "camera fallback, whole-frame (no face this frame)"
        case .roomFace:  label = "camera fallback, two-region (face + room split)"
        }
        print("[AmbientLightProvider] source changed -> \(label)")
    }
}


```

```swift id=fixed_source
import AppKit
import CoreGraphics
import ScreenCaptureKit
import AVFoundation
import CoreAudio
import Accelerate
import Vision
import CoreML
import IOKit

// ================================================================
// HeadTracker  (VR180 head-tracked look-around)
//
// Webcam head pose consumed by PPController.setHeadTrackingEnabled /
// applyHeadPose; never touches mpv, IPC, or shader opts itself. Separate
// TCC permission (Camera) and opt-in lifecycle, independent of the
// screen/audio capture above.
//
// Pipeline: AVCaptureSession -> VNDetectFaceRectanglesRequest revision 3
//   (roll/pitch/yaw directly, macOS 12+; VNDetectFaceLandmarksRequest does
//   NOT feed pose - per WWDC21 10040 pose is a property of the RECTANGLES
//   request) -> single-pole low-pass (unsmoothed pose visibly jitters the
//   shader's ray direction) -> onPoseUpdate on main.
//
// X/Y/Z is NOT real 6DoF: Vision gives rotation only; xOffset/yOffset/
// zOffset are a boundingBox proxy relative to a recenter() baseline,
// sufficient for small yaw/pitch/fov nudges and no more - don't reuse for
// anything that wants real units.
//
// Sign conventions are unverified against a real camera: isolated into the
// *Sign constants so one flip fixes it once observed.
// ================================================================

/// Recenter()-relative head pose. See the HeadTracker class comment
/// above for exactly what each field does and does not represent.
struct HeadPose {
    /// Radians, Vision's own convention -- see HeadTracker's *Sign
    /// constants for the one place to correct these if a physical
    /// head turn moves the view the wrong way.
    var yaw: Double
    var pitch: Double
    var roll: Double

    /// Unitless, recenter()-relative boundingBox proxy (NOT real
    /// translation -- see the class comment above). Roughly
    /// -0.5...0.5 for normal desk-distance head movement; not
    /// clamped here, the consumer clamps.
    var xOffset: Double
    var yOffset: Double
    var zOffset: Double
    /// Block 182 2: face distance from the box in mm (raw and one-euro filtered); nil with a reason when the
    /// camera field of view is unavailable. Defaults keep every existing HeadPose(...) call valid.
    var distanceRawMM: Double? = nil
    var distanceMM: Double? = nil
    var distanceFallback: String? = nil
    var fusionRoll: Double? = nil
    var nativeRawRoll: Double? = nil
}

/// Block 182 2 distance model, pure. d_mm = f_px * 140 / w_box_px with f_px = (frame_w / 2) / tan(hfov / 2) and
/// w_box_px = box.width * frame_w, so the frame width cancels: d = 70 / (tan(hfov / 2) * box.width).
/// 140 mm is the owner's adult face-width constant; hfov is AVCaptureDevice.activeFormat.videoFieldOfView (deg).
enum VRDistance {
    static let faceWidthMM = 140.0
    static func distanceMM(hfovDeg: Double, boxWidthNorm: Double) -> Double {
        let fPxPerFrameW = 0.5 / tan(hfovDeg * Double.pi / 180.0 / 2.0)   // f_px / frame_w
        return fPxPerFrameW * faceWidthMM / boxWidthNorm
    }
    /// mm per physical pixel of the main display: CGDisplayScreenSize.width / the mode's pixel width.
    /// 0 when either is unavailable (the script then uses the MacBook Air M1 panel constant, 25.4/227).
    static func mmPerPx() -> Double {
        let id = CGMainDisplayID()
        let wmm = CGDisplayScreenSize(id).width
        guard wmm > 0, let px = CGDisplayCopyDisplayMode(id)?.pixelWidth, px > 0 else { return 0 }
        return Double(wmm) / Double(px)
    }
}

@available(macOS 12.0, *)
final class HeadTracker: NSObject {
    static let shared = HeadTracker()
    private override init() { super.init() }
    // MARK: - Public surface
    /// Delivered on the main thread. PPController assigns this once,
    /// when head-tracking is enabled, and clears it on disable --
    /// same ownership shape as PollEngine.onResults in
    /// PPController.swift.
    var onPoseUpdate: ((HeadPose) -> Void)?
    var onGazeUpdate: ((BinocularGazeSample?) -> Void)?
    // Source commentary elided for privacy; historical proof hashes are not rebound.
    private static let yawSign:   Double = 1.0
    private static let pitchSign: Double = -1.0
    private static let rollSign:  Double = 1.0
    // Source commentary elided for privacy; historical proof hashes are not rebound.
    private static let xOffsetSign: Double = -1.0
    /// gor.vr.poseHoldLock (default ON). false removes the 197i hold-lock stage
    /// from the output chain, byte-identical behaviour.
    static var poseHoldLock = true
    private static let yOffsetSign: Double = 1.0
    // MARK: - Smoothing
    /// Single-pole low-pass, same alpha = 1 - exp(-dt/tau) shape
    /// ScreenCaptureEngine.processAudio() already uses above -- but
    /// applied SYMMETRICALLY here (same tau rising and falling),
    /// unlike processAudio's fast-attack/slow-release envelope. That
    /// asymmetry exists there because audio wants peaks to read
    /// instantly and decay slowly; head pose has no equivalent
    /// "peaks matter more than troughs" property, so a plain low-pass
    /// is the right tool here, not a copy of that asymmetric shape.
    ///
    /// Was 0.15/2 == 0.075s (alpha ~= 0.36 per 30fps frame -- each new
    /// frame overwrote over a third of the smoothed value, which is
    /// fast/responsive, not conservative). That value did not come
    /// from a wrong choice of Vision request -- roll/pitch/yaw jitter
    /// is a property of VNDetectFaceRectanglesRequest's own pose
    /// estimate (see this class's pipeline comment above for why
    /// VNDetectFaceLandmarksRequest was tried and reverted; it doesn't
    /// touch pose at all) -- so this constant, not the request type,
    /// is the actual lever. Raised to 0.25s (alpha ~= 0.126/frame) as
    /// a real, if still untested-on-hardware, attempt at less jitter
    /// on a still head: a genuine head turn still reaches ~90% of its
    /// new position within ~0.55s at this tau, which should read as
    /// smoothed rather than laggy, but this trade (less noise, more
    /// lag) is inherent to a low-pass filter -- there's no tau that
    /// removes jitter for free. Raise further if still too wobbly;
    /// lower back toward 0.075-0.15 if look-around starts to feel
    /// delayed. Still a starting point, not derived -- no camera or
    /// real noise floor was available to tune this against.
    private static let poseSmoothingTau: Double = 0.25  // seconds; the pre-stabilization value, kept as the still-head reference below
    //192d D1 first smoothing stage: existing one-euro (Casiez et al., CHI2012).
    struct OneEuro {
        var minCutoff: Double
        var beta: Double
        var dCutoff: Double = 1.0
        private var has = false
        private var xPrev = 0.0, dxPrev = 0.0, tPrev = 0.0, xRawPrev = 0.0
        init(minCutoff: Double, beta: Double) { self.minCutoff = minCutoff; self.beta = beta }
        private static func alpha(_ dt: Double, _ cutoff: Double) -> Double {
            let tau = 1.0 / (2.0 * Double.pi * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }
        mutating func reset() { has = false }
        mutating func hold(at t:Double)->Double {if has, t.isFinite {tPrev=t};return xPrev}
        mutating func filter(_ x: Double, at t: Double) -> Double {
            guard x.isFinite, t.isFinite else { return has ? xPrev : 0 }
            guard has else { has = true; xPrev = x; xRawPrev = x; dxPrev = 0; tPrev = t; return x }
            let dt = min(max(t - tPrev, 1.0 / 240.0), 0.2)
            tPrev = t
            // Speed from the previous RAW sample, as in the reference one-euro filter (Casiez et al. 2012). The
            // earlier (x - previous FILTERED)/dt carried the filter's own lag, so the cutoff stayed high after a
            // stop and noise deviations from the lagging output counted as speed.
            let dx = (x - xRawPrev) / dt
            xRawPrev = x
            dxPrev += Self.alpha(dt, dCutoff) * (dx - dxPrev)
            let cutoff = minCutoff + beta * abs(dxPrev)
            xPrev += Self.alpha(dt, cutoff) * (x - xPrev)
            return xPrev
        }
    }
    // Synthetic 30 fps white-noise study, 12 seeds: relative to the old fixed tau0.25 filter, the shipped
    // adaptive constants yielded 1.37/1.62/2.08x angle jitter at sigma .01/.02/.05 rad. Raw-sample velocity
    // plus these cutoffs gives .81/.86/1.01x, versus the shipped adaptive filter .59/.53/.49x.
    // A 0.5 rad turn at 1 rad/s reaches 90% in .67 s (old fixed .90 s, shipped adaptive .50 s).
    // These are synthetic measurements, not proof that the owner's live-camera wobble is fixed.
    private static let stillCutoffHz = 0.35
    private static let turnCutoffHz = 2.0
    private static let speedFilterCutoffHz = 0.3
    private static func euro(refSpeed: Double) -> OneEuro {
        var f = OneEuro(minCutoff: stillCutoffHz, beta: (turnCutoffHz - stillCutoffHz) / refSpeed)
        f.dCutoff = speedFilterCutoffHz
        return f
    }
    private static let angleRefSpeed = 1.0   // rad/s
    private static let boxRefSpeed = 0.25    // box units/s
    private static let fovTauSeconds = 0.8
    private var fYaw = HeadTracker.euro(refSpeed: HeadTracker.angleRefSpeed), fPitch = HeadTracker.euro(refSpeed: HeadTracker.angleRefSpeed), fRoll = HeadTracker.euro(refSpeed: HeadTracker.angleRefSpeed)
    private var fX = HeadTracker.euro(refSpeed: HeadTracker.boxRefSpeed), fY = HeadTracker.euro(refSpeed: HeadTracker.boxRefSpeed)
    private var fZ = OneEuro(minCutoff: 1.0 / (2.0 * Double.pi * HeadTracker.fovTauSeconds), beta: 0)
    /// Main-thread only (called exclusively from applyObservation below).
    private func smooth(_ raw: HeadPose, at now: CFTimeInterval, distanceValid:Bool=true) -> HeadPose {
        // Native look-around needs faster motion adaptation, not less still filtering.
        let turn=nativeMotionResponsive ? 4.0:Self.turnCutoffHz
        let speed=nativeMotionResponsive ? 0.3:Self.speedFilterCutoffHz
        fYaw.beta=(turn-Self.stillCutoffHz)/Self.angleRefSpeed;fYaw.dCutoff=speed
        fPitch.beta=fYaw.beta;fPitch.dCutoff=speed;fRoll.beta=fYaw.beta;fRoll.dCutoff=speed
        let z=distanceValid ? fZ.filter(raw.zOffset,at:now):fZ.hold(at:now)
        return HeadPose(yaw: fYaw.filter(raw.yaw, at: now), pitch: fPitch.filter(raw.pitch, at: now),
                        roll: fRoll.filter(raw.roll, at: now),
                        xOffset: fX.filter(raw.xOffset, at: now), yOffset: fY.filter(raw.yOffset, at: now),
                        zOffset: z)
    }
    // Distance goes through the same heavy channel as the fov-from-box (tau 0.8 s, beta 0).
    private var fD = OneEuro(minCutoff: 1.0 / (2.0 * Double.pi * HeadTracker.fovTauSeconds), beta: 0)
    private func resetFilters() { fYaw.reset(); fPitch.reset(); fRoll.reset(); fX.reset(); fY.reset(); fZ.reset(); fD.reset() }
    // MARK: - Baseline (recenter) -- main-thread only, see applyObservation
    private var poseContinuity=PoseContinuity(); private var poseSessionStartedAt:Double=0
    private var lastTracedPose=[Double](repeating:0,count:6)
    private var pupilDistanceScale=PupilDistanceScale(); private var baselineBoxSize: CGFloat?
    private var poseEyeGate=PoseEyeMeasurementGate();private var poseNoise=PoseNoiseCalibration();private var poseFollow:PoseBacklashFollow?
    // 197i hold lock: five channels (yaw/pitch/roll angular, x/y box); z already
    // carries the 191a hysteresis. Created lazily so a disabled flag allocates nothing.
    private var poseHoldLocks:[PoseHoldLock]?
    var nativeMotionResponsive=false {didSet {if oldValue != nativeMotionResponsive {poseFollow=nil}}}
    private var poseDistanceConsistency=PoseDistanceConsistency()
    private var previousPoseOutput:[Double]?
    private var independentDistance:(at:Double,relative:Double,ready:Bool)?
    private var baselineBoxCenter: CGPoint?, lastBoundingBox: CGRect?
    private var lastAngles=(yaw:0.0,pitch:0.0,roll:0.0), neutralAngles=(yaw:0.0,pitch:0.0,roll:0.0)
    /// Pose baseline belongs to the head consumer, not the shared camera; seed a fresh observation.
    func beginPoseSession() {
        poseSessionStartedAt=CACurrentMediaTime(); baselineBoxSize=nil;baselineBoxCenter=nil;neutralAngles=(0,0,0)
        independentDistance=nil;pupilDistanceScale.reset();poseEyeGate=PoseEyeMeasurementGate();poseDistanceConsistency=PoseDistanceConsistency()
        poseNoise=PoseNoiseCalibration();poseFollow=nil;previousPoseOutput=nil;poseHoldLocks=nil
        resetFilters();poseContinuity=PoseContinuity();lastTracedPose=[Double](repeating:0,count:6)
    }
    /// Reset distance/look-around immediately; preserve the measured physical eye axis.
    func recenter() {
        beginPoseSession()
        guard lastBoundingBox != nil else { return }
        var aligned=HeadPose(yaw:0,pitch:0,roll:lastAngles.roll,xOffset:0,yOffset:0,zOffset:0)
        aligned.fusionRoll=lastAngles.roll;aligned.nativeRawRoll=lastAngles.roll
        aligned.distanceFallback="fov-unavailable"
        lastTracedPose=[0,0,lastAngles.roll,0,0,0]
        PoseTraceRing.shared.append(t:CACurrentMediaTime(),raw:[],filtered:lastTracedPose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"recenter")
        onPoseUpdate?(aligned)
    }
    // MARK: - Capture session (arch-195z Z3 / arch-196b C6: camera lives in the child helper)
    /// The AVCaptureSession and all camera Vision work run in the same
    /// executable spawned as --camera-helper (CameraHelperClient /
    /// CameraHelperEngine in QuitChildKiller.swift, protocol in
    /// Stereo/HeadPose.swift). This class keeps consumer policy, the
    /// ambient reading epochs, and every downstream math path; the
    /// helper returns typed readings only. Guaranteed camera-off on a
    /// hung Apple stop comes from the 2 s stop deadline + SIGKILL in
    /// the client: process exit releases the device.
    private let cameraHelper = CameraHelperClient()
    /// One automatic helper relaunch per consumer generation on an
    /// unexpected exit (Z3: restart = new helper epoch, no retry loop).
    private var relaunchGeneration: UInt64 = 0
    /// Ambient settle-window id; bumped per fresh window and tagged on
    /// every helper frame, replacing the in-process frameQueue reset.
    private var ambientWindowID: UInt64 = 0
    /// The helper Vision-watchdog token last reported expired (arch-196b
    /// C2): frames carrying it are dropped, the cross-process form of
    /// the in-process visionEpochIsCurrent gate.
    private let visionCancelLock = NSLock()
    private var expiredVisionToken: UInt64?
    private func currentExpiredVisionToken() -> UInt64? {
        visionCancelLock.lock(); defer { visionCancelLock.unlock() }; return expiredVisionToken
    }
    private static let ambientClassificationDeadline: TimeInterval = 0.25
    private let ambientReadingLock = NSLock()
    private var ambientReadingEpoch: UInt64 = 0
    private var ambientReadingOpen = false
    private var ambientReadingArmed = false
    private var ambientReadingPublished = false
    private func ambientEpoch() -> UInt64 {
        ambientReadingLock.lock(); defer { ambientReadingLock.unlock() }
        return ambientReadingEpoch
    }
    private func beginAmbientReading() {
        ambientReadingLock.lock(); defer { ambientReadingLock.unlock() }
        ambientReadingEpoch &+= 1; ambientReadingOpen = true
        ambientReadingArmed = false; ambientReadingPublished = false
    }
    private func endAmbientReading() {
        ambientReadingLock.lock(); defer { ambientReadingLock.unlock() }
        ambientReadingOpen = false; ambientReadingPublished = true
        ambientReadingEpoch &+= 1
    }
    private func armAmbientFallback(_ luma: Double, generation: UInt64, epoch: UInt64) {
        ambientReadingLock.lock()
        let arm = ambientReadingOpen && !ambientReadingArmed && ambientReadingEpoch == epoch
        if arm { ambientReadingArmed = true }
        ambientReadingLock.unlock()
        guard arm else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ambientClassificationDeadline) { [weak self] in
            self?.publishAmbient(luma, regions: nil, generation: generation, epoch: epoch, source: "deadline-full-frame")
        }
    }
    private func publishAmbient(_ luma: Double, regions: TwoRegionLuma?, generation: UInt64, epoch: UInt64, source: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeConsumers > 0, lifecycleGeneration == generation else { return }
        ambientReadingLock.lock()
        let accept = ambientReadingEpoch == epoch && !ambientReadingPublished
        if accept && ambientReadingOpen { ambientReadingPublished = true }
        ambientReadingLock.unlock()
        guard accept else { return }
        lastAmbientLuma = luma; lastAmbientRegions = regions
        Diag.mediaRecord("AMBIENT value=\(luma) generation=\(generation) source=\(source)")
        onAmbientFrame?()
    }
    /// Fresh ambient window: the reading epoch opens here (parent
    /// policy); the settle counters live in the helper, which resets
    /// them on this command and tags every frame with the window id.
    /// A frame from an older window is rejected in handleHelperFrame,
    /// the same stale-read protection the in-process epoch capture gave.
    func resetAmbientSettling() {
        beginAmbientReading()
        ambientWindowID &+= 1
        cameraHelper.resetSettling(generation: lifecycleGeneration, window: ambientWindowID)
    }

    // Main owns consumer bookkeeping. Frame/session queues read a locked
    // snapshot, never the mutable consumer count or ambient request flag.
    private let lifecycleLock = NSLock()
    private var lifecycleSnapshot: (generation: UInt64, requested: Bool, ambientOnly: Bool) = (0, false, false)
    private func captureLifecycle() -> (generation: UInt64, requested: Bool, ambientOnly: Bool) {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return lifecycleSnapshot
    }
    private func publishLifecycle() {
        lifecycleLock.lock()
        lifecycleSnapshot = (lifecycleGeneration, activeConsumers > 0,
                             hasRequestedAmbientStart && activeConsumers == 1)
        lifecycleLock.unlock()
        bumpBlinkEpoch()
    }
    private var isAmbientOnlyActive: Bool { captureLifecycle().ambientOnly }

    // MARK: - Blink measurement (log only; no command is bound to a blink)
    // Phase 2 measurement build: while blinkLogEnabled (VR menu "blink log (measure only)" / shift+e) AND
    // head tracking frames are flowing, a VNDetectFaceLandmarksRequest runs on the SAME frames after the
    // pose has been dispatched, and an eye-contour box aspect (landmark bounding-box height / width per eye;
    // NOT the canonical 6-point EAR) is written to the geom trace as blinkTrace.
    // Purpose: measure the false-accept rate against natural blinking before any binding exists.
    private let blinkLock = NSLock()
    private var blinkLogOn = false
    // Bumped on every blink toggle AND on every consumer/lifecycle publication (publishLifecycle), so a sample
    // scheduled before an off->on toggle, a tracking stop/start or an ambient transition is never published.
    private var blinkEpoch: UInt64 = 0
    private func currentBlinkEpoch() -> UInt64 { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkEpoch }
    private func bumpBlinkEpoch() { blinkLock.lock(); blinkEpoch &+= 1; blinkLock.unlock() }
    var blinkLogEnabled: Bool {
        get { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkLogOn }
        set { blinkLock.lock(); blinkLogOn = newValue; blinkEpoch &+= 1; if !newValue { blinkIndicatorCB = nil; blinkDetectedCB = nil; blinkCloseSessionLocked() } else { blinkBeginSessionLocked() }; blinkLock.unlock(); pushHelperConfig() }
    }
    /// Block 182 3: the bbox proxy is unreliable at large yaw, so frames over this are tagged in the trace.
    static let blinkYawTagDeg: Double = 15.0
    // Runs OFF the capture callback: one in-flight sample at most, a frame that arrives while one is
    // running is skipped (never queued), so the pose cadence and the capture queue are not extended.
    private let blinkQueue = DispatchQueue(label: "gor.headtracker.blink", qos: .utility)
    private var blinkBusy = false
    // Adaptive blink indicator state (measurement only; no command is bound). Touched only on blinkQueue (serial).
    // The two fractions are PROVISIONAL hypotheses, not validated against any recording: an eye counts as
    // "closing" when the aspect falls below blinkClosedFrac of the running open-eye level, and the level is only
    // updated from samples above blinkOpenFrac so a closure does not drag the baseline down.
    private var blinkBase: Double? = nil
    private var blinkPrevT: CFTimeInterval? = nil
    private var blinkStateEpoch: UInt64 = 0
    static let blinkClosedFrac = 0.70
    static let blinkOpenFrac = 0.85
    static let blinkBaseAlpha = 0.05
    /// A blink lasts roughly 100-400 ms. Two samples inside the shortest blink need a gap of at most about half of
    /// it; a larger gap is reported as sparse so "no blink" is never claimed from samples that cannot see one.
    static let blinkMaxGapS = 0.05
    /// Bounded Shift+E session summary: plain counters and a fixed 5-bucket gap histogram, never a per-sample array.
    /// Counts what happened to each offered frame, by reason. It is NOT a detection verdict: "candidates" are closing
    /// edges of an unvalidated ratio and are not blinks. Guarded by blinkLock.
    private struct BlinkSession {
        var id: UInt64 = 0, active = false
        var tFirst: CFTimeInterval? = nil, tLast: CFTimeInterval? = nil
        var offered = 0, skippedBusy = 0, ambientSkipped = 0
        var visionFailed = 0, staleDropped = 0, noFace = 0, noEyes = 0, yawOver = 0, usable = 0
        var candidates = 0, sparse = 0
        var blinksConfirmed = 0, blinksPossible = 0, closuresHeld = 0
        var gapBuckets = [Int](repeating: 0, count: 5)   // <=0.05, <=0.10, <=0.25, <=0.50, >0.50 s
        var gapMax = 0.0
        var baseMin: Double? = nil, baseMax: Double? = nil
    }
    private var blinkSess = BlinkSession()
    private var blinkSessionSeq: UInt64 = 0
    /// Id of the current (or last) blink session; the controller reads it right after turning ON, on the main thread.
    var blinkSessionID: UInt64 { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkSess.id }
    /// Turns the log OFF and closes the session only if `sid` is still the active session. Atomic under blinkLock.
    func stopBlinkLogIfCurrent(session sid: UInt64) -> Bool {
        blinkLock.lock(); defer { blinkLock.unlock() }
        guard blinkLogOn, blinkSess.active, blinkSess.id == sid else { return false }
        blinkLogOn = false; blinkEpoch &+= 1; blinkIndicatorCB = nil; blinkDetectedCB = nil; blinkCloseSessionLocked()
        return true
    }
    /// Closed sessions waiting to be written. Each one is an immutable snapshot taken atomically under blinkLock at the
    /// moment the opt-in ended, so a later opt-in can neither reset nor consume it.
    private var blinkPendingSummaries: [(s: BlinkSession, inFlightAtOff: Bool)] = []
    /// Counters apply only to the session that was active when the frame was offered; a frame offered in a session that has
    /// since closed is not counted anywhere (it is reported as inFlightAtOff in that session's summary).
    private func blinkCount(sid: UInt64, _ f: (inout BlinkSession) -> Void) {
        blinkLock.lock(); if blinkSess.active && blinkSess.id == sid { f(&blinkSess) }; blinkLock.unlock()
    }
    /// Caller holds blinkLock.
    private func blinkCloseSessionLocked() {
        if blinkSess.active {
            blinkPendingSummaries.append((blinkSess, blinkBusy))
            if blinkPendingSummaries.count > 4 { blinkPendingSummaries.removeFirst() }   // bounded
        }
        blinkSess = BlinkSession()
    }
    private func blinkBeginSessionLocked() {
        blinkCloseSessionLocked()
        blinkSessionSeq &+= 1
        blinkSess = BlinkSession(); blinkSess.id = blinkSessionSeq; blinkSess.active = true
    }
    /// Writes one summary row per closed session (oldest first) and at most one OSD line, for the newest, and only if no
    /// newer session is running when it is delivered. If the blink log is full/stopped the row cannot be written and the
    /// OSD says so ("unavailable"); the summary write never stops the log and never re-enters the failure path.
    /// Runs on blinkQueue after any in-flight sample.
    func flushBlinkSummary(osd: ((String) -> Void)?) {
        blinkQueue.async { [weak self] in
            guard let self = self else { return }
            self.blinkLock.lock(); let pending = self.blinkPendingSummaries; self.blinkPendingSummaries = []; self.blinkLock.unlock()
            func f(_ v: Double?) -> String { v.map { String(format: "%.5f", $0) } ?? "null" }
            for (i, item) in pending.enumerated() {
                let s = item.s
                let dur: Double? = (s.tFirst != nil && s.tLast != nil) ? s.tLast! - s.tFirst! : nil
                let row = "{\"k\":\"blinkSummary\",\"session\":\(s.id),\"inFlightAtOff\":\(item.inFlightAtOff),\"sessionS\":\(f(dur)),\"offered\":\(s.offered),\"skippedBusy\":\(s.skippedBusy),\"ambientSkipped\":\(s.ambientSkipped),\"visionFailed\":\(s.visionFailed),\"staleDropped\":\(s.staleDropped),\"noFace\":\(s.noFace),\"noEyes\":\(s.noEyes),\"yawOver\":\(s.yawOver),\"usable\":\(s.usable),\"episodes\":\(s.candidates),\"blinksConfirmed\":\(s.blinksConfirmed),\"blinksPossible\":\(s.blinksPossible),\"closuresHeld\":\(s.closuresHeld),\"sparse\":\(s.sparse),\"gapBuckets\":\(s.gapBuckets),\"gapMaxS\":\(f(s.gapMax)),\"openBaseMin\":\(f(s.baseMin)),\"openBaseMax\":\(f(s.baseMax))}"
                let isNewest = (i == pending.count - 1)
                let text = "blink measurement session \(s.id) ended: offered \(s.offered), usable \(s.usable), no face \(s.noFace), no eyes \(s.noEyes), busy-skipped \(s.skippedBusy), episodes \(s.candidates), blinks \(s.blinksConfirmed) (+\(s.blinksPossible) possible), eye closures \(s.closuresHeld) (provisional rule, unvalidated)"
                let sid = s.id
                GeomTrace.logBlinkSummary(row) { [weak self] reason in
                    guard isNewest, let osd = osd, let self = self else { return }
                    self.blinkLock.lock(); let running = self.blinkLogOn; self.blinkLock.unlock()
                    if !running { osd("blink measurement session \(sid) summary \(reason)") }
                } written: { [weak self] in
                    guard isNewest, let osd = osd, let self = self else { return }
                    self.blinkLock.lock(); let running = self.blinkLogOn; self.blinkLock.unlock()
                    if !running { osd(text) }
                }
            }
        }
    }
    /// Visible feedback for the Shift+E measurement only (no command is bound). Called on the main thread with a short
    /// text on a closing/open edge and, at most once per Shift+E session, when most recent samples are too sparse to see
    /// a blink. Assigned by the controller while the blink log is on and cleared when it is off.
    private var blinkIndicatorCB: ((String) -> Void)?
    var onBlinkIndicator: ((String) -> Void)? {
        get { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkIndicatorCB }
        set { blinkLock.lock(); blinkIndicatorCB = newValue; blinkLock.unlock() }
    }
    /// Typed detection callback (main thread), set by the controller only while the opt-in is on; binds no command.
    private var blinkDetectedCB: ((BlinkDetection) -> Void)?
    var onBlinkDetected: ((BlinkDetection) -> Void)? {
        get { blinkLock.lock(); defer { blinkLock.unlock() }; return blinkDetectedCB }
        set { blinkLock.lock(); blinkDetectedCB = newValue; blinkLock.unlock() }
    }
    private var blinkWasClosing = false
    private var blinkSparseRun = 0
    private var blinkSparseShown = false
    private var episodeTracker = BlinkEpisodeTracker()   // pure bookkeeping at the bottom of this file; touched only on blinkQueue
    static let blinkSparseRunToWarn = 20   // PROVISIONAL: 20 consecutive sparse samples
    private let latestEyeFrame=LatestMainFrame()
    private let latestPoseFrame=LatestMainFrame()
    private let latestLandmarkFrame=LatestMainFrame()
    private let frameLossLatch=FrameLossLatch()
    private let latestAmbientFrame=LatestMainFrame()
    private var controlDetector = BlinkControlDetector()
    private var lastBlinkFrameT:Double?
    private var controlEpoch: UInt64 = 0
    var onBlinkControl: ((BlinkControlDetector.Event) -> Void)?
    var onEyeCommand:((EyeGestureCommands.Command)->Void)?
    private var eyeGestureCommands=EyeGestureCommands()
    private var lastBlinkBoostSent: Double = -1   // 197i: last boost value on the wire
    var onEyeClosure: ((Double,Double,Bool) -> Void)?
    private var intentionalClosure=IntentionalEyeClosure()
    private var intentionalClosureRight=IntentionalEyeClosure()
    /// Blink sampling consumes the helper's typed landmark readings
    /// (arch-195z Z3 / arch-196b C6): Vision itself runs in the helper
    /// now; the epoch, gap, reliability-gate and delivery semantics
    /// below are unchanged from the in-process sampler this replaces.
    private func feedBlinkFrame(_ f: CameraHelperIPC.Frame, generation: UInt64) {
        guard blinkLogEnabled, !isAmbientOnlyActive else { return }
        let epoch = currentBlinkEpoch()
        if controlEpoch != epoch { controlEpoch=epoch; controlDetector.reset();eyeGestureCommands.reset();intentionalClosure.reset();intentionalClosureRight.reset() }
        let now = f.now
        let frameAge = f.age
        guard f.processed, !f.visionFailed else {
            intentionalClosure.reset();intentionalClosureRight.reset()
            _ = controlDetector.feed(t:now,left:nil,right:nil)
            _ = eyeGestureCommands.feed(t:now,left:nil,right:nil,reliable:false)
            latestEyeFrame.submit { [weak self] in
                guard let self,self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else { return };self.onEyeClosure?(0,0,true)
            }
            return
        }
        guard captureLifecycle().generation == generation else { return }
        if f.visionToken != 0, f.visionToken == currentExpiredVisionToken() { return }
        let lm = f.landmarks
        let elapsed = f.visionMS / 1000
        let frameGap=lastBlinkFrameT.map { now-$0 };lastBlinkFrameT=now
        GeomTrace.logBlink("{\"k\":\"blinkCadence\",\"t\":\(now),\"visionMS\":\(elapsed*1000),\"frameGapS\":\(frameGap ?? 0),\"configuredFPS\":30}")
        GeomTrace.logBlink("{\"k\":\"blinkTiming\",\"frameAgeMS\":\(frameAge*1000),\"detectMS\":\(elapsed*1000),\"intervalMS\":\((frameGap ?? 0)*1000),\"gapReset\":\((frameGap ?? 0)>EyeGestureCommands.maxFrameGap),\"stale\":\(frameAge+elapsed>EyeGestureCommands.maxFrameGap)}")
        // EAR from the raw normalized landmark points, exactly the
        // in-process sampler's ear() (no box scaling).
        func ear(_ points: [[Double]]?) -> Double? {
            guard let points, !points.isEmpty else { return nil }
            return EyeAperture.ear(points.map { ($0[0],$0[1]) })
        }
        let left=ear(lm?.leftEye),right=ear(lm?.rightEye)
        // Camera luma is a conservative safety floor in 0...255 encoded units, NOT ambient lux.
        // Missing/dark frames or uncertain landmarks fail open and cannot build a seek gesture.
        let reliable=(f.lumaLandmarkFace.map { $0.face>=24 } ?? false) && (lm?.confidence ?? 0)>=0.8 &&
            (lm?.landmarksConfidence ?? 0)>=0.65 &&
            abs(lm?.yaw ?? 0)<=Double.pi/12 && abs(lm?.pitch ?? 0)<0.5
        GeomTrace.logBlink("{\"k\":\"blinkGate\",\"reliable\":\(reliable),\"hasLeft\":\(left != nil),\"hasRight\":\(right != nil)}")
        let event=controlDetector.feed(t:now,left:reliable ? left:nil,right:reliable ? right:nil)
        let eyeCommand=eyeGestureCommands.feedCommand(t:now,left:left,right:right,reliable:reliable,frameAge:frameAge+elapsed,controlHeld:NSEvent.modifierFlags.contains(.control))
        // 197i: escalate the helper's blink admission while an episode is in
        // flight (closure edge or completed first blink under the thermal
        // stride). 0 clears. Unknown cmd on an old helper is a no-op.
        if EyeGestureCommands.cadenceAdaptive {
            let boost=eyeGestureCommands.blinkBoostUntil ?? 0
            if boost != lastBlinkBoostSent { lastBlinkBoostSent=boost; cameraHelper.blinkBoost(until: boost) }
        }
        if let eyeCommand {
            DispatchQueue.main.async { [weak self] in
                guard let self,self.blinkLogEnabled,self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else{return}
                let deliveryAge=CACurrentMediaTime()-now+frameAge
                GeomTrace.logBlink("{\"k\":\"blinkCommand\",\(eyeCommand.diagnosticFields),\"deliveryAgeMS\":\(deliveryAge*1000)}")
                guard deliveryAge<=EyeGestureCommands.maxFrameGap, eyeCommand != .playPause || NSEvent.modifierFlags.contains(.control) else { return }
                self.onEyeCommand?(eyeCommand)
            }
        }
        let closure=intentionalClosure.feed(t:now,left:left,right:nil,reliable:reliable)
        let closureRight=intentionalClosureRight.feed(t:now,left:right,right:nil,reliable:reliable)
        latestEyeFrame.submit { [weak self] in
            guard let self,self.blinkLogEnabled,self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else { return }
            let age=CACurrentMediaTime()-now+frameAge
            GeomTrace.logBlink("{\"k\":\"blinkDelivery\",\"ageMS\":\(age*1000),\"frameAgeMS\":\(frameAge*1000),\"detectMS\":\(elapsed*1000),\"mainHopMS\":\((age-frameAge-elapsed)*1000),\"lidL\":\(closure),\"lidR\":\(closureRight)}")
            self.onEyeClosure?(age<=EyeGestureCommands.maxFrameGap ? closure:0,age<=EyeGestureCommands.maxFrameGap ? closureRight:0,!reliable || age>EyeGestureCommands.maxFrameGap)
        }
        GeomTrace.logBlink("{\"k\":\"blinkEAR\",\"t\":\(now),\"left\":\(left.map { String($0) } ?? "null"),\"right\":\(right.map { String($0) } ?? "null"),\"event\":\"\(event?.rawValue ?? "none")\"}")
        if let event {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.blinkLogEnabled, self.currentBlinkEpoch()==epoch,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil) else { return }
                self.onBlinkControl?(event)
            }
        }
    }

    // MARK: - Permission (Camera -- separate TCC gate from Screen Recording above)

    // Requested consumers and hardware state are separate. All public
    // transitions are main-thread-only; session work runs on sessionQueue.
    private var activeConsumers = 0
    private var lifecycleGeneration: UInt64 = 0
    private enum CameraState { case idle, authorizing, starting, running, stopping, failed }
    private var cameraState: CameraState = .idle {
        didSet { if cameraState != oldValue { traceSessionEvent("state-\(cameraState)") } }
    }
    private var permissionRequestInFlight = false
    var isRequested: Bool { activeConsumers > 0 }
    var isRunning: Bool { cameraState == .running || cameraState == .stopping }
    /// Trace-only attribution (GOR_TRACE_GEOM): consumers = every start() holder;
    /// ambientRequested = the ambient-dimming duty-cycle consumer is one of them.
    /// VR-owned consumers = consumers - (ambientRequested ? 1 : 0).
    var traceConsumers: (consumers: Int, ambientRequested: Bool) { (activeConsumers, hasRequestedAmbientStart) }

    /// GOR_TRACE_GEOM=1 only: every capture-session lifecycle event (any consumer start/stop
    /// and every camera state change) with full consumer attribution, so a brief session is
    /// recorded even between the 1 Hz VR ticks.
    private func traceSessionEvent(_ ev: String) {
        Diag.mediaRecord("HEAD-CAPTURE event=\(ev) consumers=\(activeConsumers) ambient=\(hasRequestedAmbientStart) generation=\(lifecycleGeneration) running=\(isRunning)")
        guard GeomTrace.on else { return }
        let vrOwned = activeConsumers - (hasRequestedAmbientStart ? 1 : 0)
        GeomTrace.log("vrCamera", "{\"k\":\"vrCamera\",\"why\":\"session-\(ev)\",\"sessionRequested\":\(activeConsumers > 0),\"sessionRunning\":\(cameraState == .running),\"consumers\":\(activeConsumers),\"ambient\":\(hasRequestedAmbientStart),\"vrOwned\":\(vrOwned)}")
    }

    // Callers retain their own per-consumer idempotence guards.
    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        if activeConsumers == 0 { lifecycleGeneration &+= 1 }
        activeConsumers += 1
        traceSessionEvent("consumer-start")
        publishLifecycle()
        // A join while the helper already runs changes its pipeline
        // shape (the in-process code read the lifecycle snapshot per
        // frame; cross-process the parent pushes it live).
        pushHelperConfig()
        ensureSessionRequested()
    }

    // Numeric owner IDs:1=head,2=blink,3=ambient. Gaze borrows, never acquires.
    func start(owner: Int) { start(); Diag.mediaRecord("HEAD-CAPTURE event=owner-acquire owner=\(owner) consumers=\(activeConsumers) generation=\(lifecycleGeneration)") }
    func stop(owner: Int) { stop(); Diag.mediaRecord("HEAD-CAPTURE event=owner-release owner=\(owner) consumers=\(activeConsumers) generation=\(lifecycleGeneration)") }

    private func ensureSessionRequested() {
        guard activeConsumers > 0, cameraState != .starting, cameraState != .running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession()
        case .notDetermined:
            cameraState = .authorizing
            guard !permissionRequestInFlight else { return }
            permissionRequestInFlight = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionRequestInFlight = false
                    guard self.activeConsumers > 0 else { return }
                    // Permission applies to the current request, not the old
                    // lifecycle that opened the system prompt.
                    if granted { self.ensureSessionRequested() }
                    else { self.cameraState = .failed }
                }
            }
        case .denied, .restricted:
            cameraState = .failed
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0, self.cameraState == .failed else { return }
                self.promptForCameraPermission()
            }
        @unknown default:
            cameraState = .failed
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeConsumers > 0 else { return }
        activeConsumers -= 1
        traceSessionEvent("consumer-stop")
        if activeConsumers > 0 { publishLifecycle(); pushHelperConfig(); return }
        lifecycleGeneration &+= 1
        cameraState = .stopping
        publishLifecycle()
        beginPoseSession()
        onEyeClosure?(0,0,true)
        PoseTraceRing.shared.append(t:CACurrentMediaTime(),raw:[],filtered:lastTracedPose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"trackingStop")
        lastAngles=(0,0,0)
        lastBoundingBox = nil
        let generation = lifecycleGeneration
        Diag.mediaRecord("HEAD-CAPTURE event=stop-request consumers=0 generation=\(generation)")
        DispatchQueue.main.asyncAfter(deadline: .now()+2) { [weak self] in
            guard let self, self.lifecycleGeneration == generation, self.cameraState == .stopping else { return }
            Diag.mediaRecord("HEAD-CAPTURE event=stop-pending generation=\(generation) elapsed_s=2 consumers=\(self.activeConsumers)")
        }
        // Z3 / 741ef8349, now enforced cross-process: the helper is
        // asked to stop and given 2 s to report hardware-stopped;
        // silence means SIGKILL, and process exit closes the
        // AVFoundation device. The completion reports only the final
        // state; the helper's own delegate/hardware events arrive as
        // relayed log lines.
        cameraHelper.stopSession(generation: generation) { stopped in
            Diag.mediaRecord("HEAD-CAPTURE event=hardware-stopped running=\(!stopped) stopped=\(stopped) generation=\(generation)")
            DispatchQueue.main.async {
                guard self.activeConsumers == 0, self.lifecycleGeneration == generation else { return }
                self.cameraState = stopped ? .idle : .failed
            }
        }
    }

    // MARK: - Ambient-only consumer (no pose delivery)
    // Ambient windows own one idempotent holder, independent of head/blink.
    // Closing the last window releases hardware without awaiting Vision.
    private var hasRequestedAmbientStart = false

    func startAmbientOnly() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !hasRequestedAmbientStart else { return }
        hasRequestedAmbientStart = true
        start(owner: 3)
    }

    func stopAmbientOnly() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasRequestedAmbientStart else { return }
        hasRequestedAmbientStart = false
        endAmbientReading()
        stop(owner: 3)
    }

    private func beginSession() {
        guard cameraState != .starting, cameraState != .running else { return }
        cameraState = .starting
        Diag.mediaRecord("HEAD-CAPTURE event=start-request consumers=\(activeConsumers) generation=\(lifecycleGeneration)")
        installHelperHandlerIfNeeded()
        let c = currentHelperConfig()
        // Session configuration, device selection, 30fps pinning,
        // mirroring off and VisionRequestDiag.camera all moved into
        // the helper (CameraHelperEngine.startIfNeeded); its
        // hardware-started/delegate lines come back as log events.
        cameraHelper.ensureRunning(generation: c.generation, window: c.window,
                                   headPose: c.headPose, blink: c.blink, ambientOnly: c.ambientOnly)
        // .starting -> .running happens on the helper's state=running
        // report (handleHelperIncoming), never optimistically: the
        // running state means the hardware confirmed, as the
        // in-process beginSession's post-startRunning read did.
    }

    /// The helper's one incoming stream is bound once. Frames carry
    /// their own generation and the ambientOnly shape they were
    /// produced under; lifecycle events are guarded against the live
    /// snapshot at handling time.
    private var helperHandlerInstalled = false
    private func installHelperHandlerIfNeeded() {
        guard !helperHandlerInstalled else { return }
        helperHandlerInstalled = true
        cameraHelper.onIncoming = { [weak self] incoming in
            self?.handleHelperIncoming(incoming)
        }
    }

    /// The current consumer shape as helper configuration: any head or
    /// blink consumer runs the full pipeline; a lone ambient consumer
    /// runs the lightweight ambient-only one. The in-process code read
    /// this snapshot per frame; cross-process the parent pushes it and
    /// the helper applies it live (configure on a running session
    /// never restarts hardware).
    private func currentHelperConfig() -> (generation: UInt64, window: UInt64, headPose: Bool, blink: Bool, ambientOnly: Bool) {
        let lifecycle = captureLifecycle()
        return (lifecycle.generation, ambientWindowID, !lifecycle.ambientOnly,
                blinkLogEnabled && !lifecycle.ambientOnly, lifecycle.ambientOnly)
    }
    private func pushHelperConfig() {
        guard activeConsumers > 0 else { return }
        let c = currentHelperConfig()
        cameraHelper.setConfig(generation: c.generation, window: c.window,
                               headPose: c.headPose, blink: c.blink, ambientOnly: c.ambientOnly)
    }

    @MainActor
    private func promptForCameraPermission() {
        let alert = NSAlert()
        alert.messageText = "Camera Access Needed for Tracking"
        alert.informativeText =
            "Gor needs Camera access for eye or head tracking.\n\n" +
            "System Settings -> Privacy & Security -> Camera -> enable Gor, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
            )
        }
    }

    // MARK: - Helper frame handling (arch-195z Z3 / arch-196b C6)

    /// Serial queue consuming the helper's typed readings. Replaces
    /// the frame/vision executor pair: Vision admission, throttling
    /// and the AE/AWB settle gate all run inside the helper now.
    private let helperQueue = DispatchQueue(label: "gor.headtrack.helper", qos: .userInitiated)

    private func handleHelperIncoming(_ incoming: CameraHelperClient.Incoming) {
        switch incoming {
        case .frame(let frame):
            helperQueue.async { [weak self] in
                self?.handleHelperFrame(frame, generation: frame.generation, ambientOnly: frame.ambientOnly)
            }
        case .log(let channel, let message):
            if channel == "diag" { Diag.log(message) } else { Diag.mediaRecord(message) }
        case .running(let generation):
            guard captureLifecycle().generation == generation else { return }
            // A fresh helper restarts its local Vision token at1. Never retain
            // the previous child's cancelled token across process supervision.
            visionCancelLock.lock(); expiredVisionToken=0; visionCancelLock.unlock()
            // Hardware-confirmed start: the in-process code set
            // .running after startRunning returned; cross-process the
            // helper's state report is that confirmation.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0, self.lifecycleGeneration == generation,
                      self.cameraState == .starting else { return }
                self.cameraState = .running
            }
        case .stopped(let generation, let stillRunning):
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifecycleGeneration == generation else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-stopped generation=\(generation) running=\(stillRunning)")
            }
        case .terminatedAfterTimeout:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-kill generation=\(self.lifecycleGeneration)")
            }
        case .visionCancelled(let token):
            // C2: the helper's watchdog cancelled that perform;
            // invalidate in-flight blink deliveries exactly as the
            // in-process bumpBlinkEpoch did.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visionCancelLock.lock(); self.expiredVisionToken = token; self.visionCancelLock.unlock()
                self.bumpBlinkEpoch()
            }
        case .failed(let reason):
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0 else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-failed reason=\(reason) generation=\(self.lifecycleGeneration)")
                self.cameraState = .failed
            }
        case .exited:
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeConsumers > 0 else { return }
                Diag.mediaRecord("HEAD-CAPTURE event=helper-exit generation=\(self.lifecycleGeneration)")
                guard self.cameraState != .failed else { return }
                // One bounded automatic relaunch per consumer
                // generation (Z3): a fresh helper epoch, no retry
                // loop. A second unexpected exit goes .failed.
                guard self.relaunchGeneration != self.lifecycleGeneration else {
                    self.cameraState = .failed
                    return
                }
                self.relaunchGeneration = self.lifecycleGeneration
                self.cameraState = .idle
                self.beginSession()
            }
        }
    }

    private var lastHelperPoseTime:Double = 0 // helperQueue sole writer; reject late independent-worker pose.
    private func handleHelperFrame(_ f: CameraHelperIPC.Frame, generation: UInt64, ambientOnly: Bool) {
        let lifecycle = captureLifecycle()
        guard lifecycle.requested, lifecycle.generation == generation else { return }
        let now = f.now
        // C2: a watchdog-expired frame never delivers (the helper drops
        // it before sending; this is the belt-and-suspenders gate for a
        // frame that crossed the cancel notice in flight).
        if f.visionToken != 0, f.visionToken == currentExpiredVisionToken() { return }
        if !ambientOnly, blinkLogEnabled, f.delivery == "blink" || (f.delivery == nil && f.processed) { feedBlinkFrame(f, generation: generation) }
        if f.delivery == "blink",f.landmarks==nil {return}
        // Ambient publish: only frames from the current settle window
        // (resetAmbientSettling bumps the id the helper tags frames
        // with) and only after the helper's settle gate passed. The
        // reading epoch is the parent's own, sampled at handling time;
        // same publish discipline as the in-process code.
        if f.ambientSettled, f.window == ambientWindowID {
            // Face-found rule from the in-process code: ambient-only
            // used the rect face; head mode used the selected face.
            let faceFound = ambientOnly ? (f.rect != nil) : (f.landmarks != nil || f.rect != nil)
            if !faceFound {
                if f.processed, !f.visionFailed, let luma = f.lumaFull {
                    latestAmbientFrame.submit { [weak self] in
                        guard let self else { return }
                        self.publishAmbient(luma, regions: nil, generation: generation, epoch: self.ambientEpoch(), source: "full-frame")
                    }
                }
            } else if let regions2 = f.lumaRectFace {
                let regions = HeadTracker.TwoRegionLuma(faceLuma: regions2.face, roomLuma: regions2.room, combined: regions2.combined)
                latestAmbientFrame.submit { [weak self] in
                    guard let self else { return }
                    self.publishAmbient(regions2.combined, regions: regions, generation: generation, epoch: self.ambientEpoch(), source: "face-room")
                }
            }
            // Scalar fallback arms on every settled throttled frame,
            // including minimal ticks while the Vision slot is busy.
            if let luma = f.lumaFull {
                armAmbientFallback(luma, generation: generation, epoch: ambientEpoch())
            }
        }
        guard !ambientOnly else { return }
        guard f.processed, !f.visionFailed else { return }
        if f.delivery != "blink" {guard f.now>=lastHelperPoseTime else {return};lastHelperPoseTime=f.now}
        // Face selection from the in-process code: the landmark
        // observation when all three pose angles exist, else the
        // rectangle detection.
        let lm = f.landmarks
        let selectedIsLandmarks = lm != nil && lm?.yaw != nil && lm?.pitch != nil && lm?.roll != nil
        guard let selectedBox = selectedIsLandmarks ? lm?.box : f.rect?.box else {
            if !isAmbientOnlyActive {
                frameLossLatch.mark()
                latestPoseFrame.submit { [weak self] in
                    guard let self,self.activeConsumers>0,self.lifecycleGeneration==lifecycle.generation,self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil),now>=self.poseSessionStartedAt else { return }
                    _=self.frameLossLatch.consume()
                    self.onGazeUpdate?(nil)
                    self.poseContinuity.faceLost();self.poseNoise.interrupt()
                    PoseTraceRing.shared.append(t:now,raw:[],filtered:self.lastTracedPose,confidence:0,faceLost:true,outlier:false,reacquire:false)
                }
            }
            return
        }
        let selYaw   = selectedIsLandmarks ? lm?.yaw   : f.rect?.yaw
        let selPitch = selectedIsLandmarks ? lm?.pitch : f.rect?.pitch
        let selRoll  = selectedIsLandmarks ? lm?.roll  : f.rect?.roll
        let selConfidence = selectedIsLandmarks ? (lm?.confidence ?? 0) : (f.rect?.confidence ?? 0)

        let pixelWidth = Double(f.pixelWidth), pixelHeight = Double(f.pixelHeight)
        let box = CGRect(x: selectedBox[0], y: selectedBox[1], width: selectedBox[2], height: selectedBox[3])
        // Landmark geometry in image pixels, identical math to the
        // in-process port (points are normalized inside the landmark
        // face box, which is normalized inside the image).
        func eyeCentre(_ points: [[Double]]?) -> (Double,Double)? {
            guard let points, !points.isEmpty, let lm, lm.landmarksConfidence >= 0.65 else { return nil }
            let x = points.reduce(0.0) { $0 + $1[0] } / Double(points.count)
            let y = points.reduce(0.0) { $0 + $1[1] } / Double(points.count)
            return ((lm.box[0]+x*lm.box[2])*pixelWidth,
                    (lm.box[1]+y*lm.box[3])*pixelHeight)
        }
        func aperture(_ points: [[Double]]?) -> Double? {
            guard let points, let lm, lm.landmarksConfidence >= 0.65 else { return nil }
            return EyeAperture.ear(points.map { ($0[0]*lm.box[2]*pixelWidth, $0[1]*lm.box[3]*pixelHeight) })
        }
        func eyeWidth(_ points: [[Double]]?) -> Double? {
            guard let points, points.count > 1, let lm else { return nil }
            let pts = points.map { ($0[0]*lm.box[2]*pixelWidth, $0[1]*lm.box[3]*pixelHeight) }
            var width = 0.0; for a in pts { for b in pts { width = max(width, hypot(a.0-b.0, a.1-b.1)) } }
            return width
        }
        let eyeCentres=[eyeCentre(lm?.leftEye),eyeCentre(lm?.rightEye)]
        let measuredWidths:[Double]=[eyeWidth(lm?.leftEye),eyeWidth(lm?.rightEye)].compactMap{$0}
        let eyeGeometry:[Double]=eyeCentres.flatMap{p in p.map{[$0.0,$0.1]} ?? []}
        let eyeApertures=[aperture(lm?.leftEye),aperture(lm?.rightEye)].compactMap{$0}
        let pupils=(eyeCentre(lm?.leftPupil),eyeCentre(lm?.rightPupil))
        let hasPupils=pupils.0 != nil && pupils.1 != nil
        let pupilLeft=hasPupils ? pupils.0:eyeCentre(lm?.leftEye)
        let pupilRight=hasPupils ? pupils.1:eyeCentre(lm?.rightEye)
        let landmarkKind=hasPupils ? "pupil":"eye"

        let landmarkConfidence:Double=lm?.landmarksConfidence ?? 0
        let frameAge:Double=f.age
        let landmarkFaceCount:Int=lm?.faceCount ?? 0
        let detectedFaceCount:Int=f.rect?.faceCount ?? 0
        let qualityFaceCount:Double=Double(landmarkFaceCount)
        // Head mode always ran the rectangle request alongside the
        // landmark one (blink pass with alsoFace, or the head-pose
        // pass), so poseRan is true here exactly as before.
        let frameQuality:[Double]=[f.quality?.mean ?? -1,f.lumaRectFace?.room ?? -1,f.quality?.contrast ?? -1,f.quality?.clipped ?? -1,landmarkConfidence,frameAge,qualityFaceCount,f.exposureChanging]
        let poseFaceCount:Int=detectedFaceCount
        let measuredAngles:[Double]=[selYaw,selPitch,selRoll].compactMap{$0}
        let measuredPupils:[Double]=[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0}
        let pairedPupilCoordinates:[Double]=[pupils.0?.0,pupils.0?.1,pupils.1?.0,pupils.1?.1].compactMap{$0}
        let rectangleOnly=f.delivery == "head"
        let structureReason=rectangleOnly
            ? PoseMeasurementValidity.rectangleReason(faceCount:poseFaceCount,angles:measuredAngles,box:box)
            : PoseMeasurementValidity.reason(faceCount:poseFaceCount,landmarkFaceCount:landmarkFaceCount,angles:measuredAngles,box:box,pupils:measuredPupils,landmarkConfidence:landmarkConfidence)
        let rawYaw   = Self.yawSign   * (selYaw   ?? 0)
        let rawPitch = Self.pitchSign * (selPitch ?? 0)
        let rawRoll  = Self.rollSign  * (selRoll  ?? 0)
        let observedBox:[Double]=[Double(box.minX)*pixelWidth,Double(box.minY)*pixelHeight,Double(box.width)*pixelWidth,Double(box.height)*pixelHeight]
        let observedLandmarkBox:[Double]=lm.map { [$0.box[0]*pixelWidth,$0.box[1]*pixelHeight,$0.box[2]*pixelWidth,$0.box[3]*pixelHeight] } ?? []
        let signedPoseAngles:[Double]=[rawYaw,rawPitch,rawRoll]
        let poseConfidence:Double=selConfidence
        let frameTimestamp:Double=f.pts.isFinite ? f.pts : -1

        let gaze = structureReason==0 && frameAge>=0 && frameAge<0.2
            ? BinocularGazeSample.measure(t:now,pupils:pairedPupilCoordinates,eyes:eyeGeometry,widths:measuredWidths,apertures:eyeApertures,yaw:rawYaw,pitch:rawPitch,roll:rawRoll):nil
        let deliverySlot=f.delivery == "blink" ? latestLandmarkFrame:latestPoseFrame
        deliverySlot.submit { [weak self] in
            guard let self, self.activeConsumers > 0,
                  self.lifecycleGeneration == lifecycle.generation, self.currentExpiredVisionToken() != (f.visionToken != 0 ? f.visionToken : nil), now>=self.poseSessionStartedAt else { return }
            if !rectangleOnly {self.onGazeUpdate?(gaze)}
            if f.delivery != "blink",self.frameLossLatch.consume() {
                self.poseContinuity.faceLost();self.poseNoise.interrupt()
                PoseTraceRing.shared.append(t:now,raw:[],filtered:self.lastTracedPose,confidence:0,faceLost:true,outlier:false,reacquire:false)
            }
            self.applyObservation(box: box, yaw: rawYaw, pitch: rawPitch, roll: rawRoll,confidence:poseConfidence,pupilLeft:pupilLeft,pupilRight:pupilRight,landmarkKind:landmarkKind,eyeApertures:rectangleOnly ? nil:eyeApertures,frameQuality:frameQuality,structureReason:structureReason,pairedPupils:pairedPupilCoordinates,eyeGeometry:eyeGeometry,eyeWidths:measuredWidths,faceBox:observedBox,landmarkBox:observedLandmarkBox,poseAngles:signedPoseAngles,framePTS:frameTimestamp,capturedAt:now,independentHead:rectangleOnly,auxiliaryOnly:f.delivery == "blink")
        }
    }

    // MARK: - Ambient luma (camera-fallback signal for AmbientLightProvider)
    fileprivate var lastAmbientLuma: Double?

    /// itself returned nil) -- it does NOT mean face/room luma were zero,
    /// and a consumer must not render a bare nil as "0%".
    ///
    /// Two independent readers: AmbientLightProvider.normalizedLevel()
    /// (same file) uses only the nil-vs-non-nil distinction to pick
    /// .fullFrame/.roomFace for logSourceChangeIfNeeded/
    /// currentSourceLabel below -- it does not read faceLuma/roomLuma
    /// themselves. PPController_Features.swift's tickScene() (a different
    /// file, see the handoff doc's HUD-richness requirement) reads the
    /// actual faceLuma/roomLuma values to populate the HUD's separate
    /// face/room percentages, independent of and alongside that mode
    /// label -- one is "which path ran", the other is "what it measured".
    ///
    /// internal, not fileprivate like lastAmbientLuma just above: that
    /// field has exactly one reader in this same file. This one is read
    /// from PPController_Features.swift too, a different file, so
    /// fileprivate would not compile there -- internal is the narrowest
    /// access level that still reaches that call site. Same threading
    /// contract as lastAmbientLuma: written only from captureOutput's
    /// main-queue hop, read only on the main thread.
    internal fileprivate(set) var lastAmbientRegions: TwoRegionLuma?

    /// Fires once per frame lastAmbientLuma is updated - lets a
    /// consumer that only wants a single fresh reading (see
    /// ContentAdaptiveDimming's ambient duty-cycle window) close the
    /// session the moment a real frame arrives, rather than waiting out
    /// a fixed worst-case-startup timeout.
    /// Same single-slot shape as onPoseUpdate above, for the same
    /// reason: exactly one current reader, no multiplexing needed yet.
    /// Deliberately separate from onPoseUpdate itself -- an ambient-
    /// only consumer has no interest in pose and must not be coupled
    /// to whatever VR's own onPoseUpdate assignment is doing.
    var onAmbientFrame: (() -> Void)?

    /// Cheap average-luma estimate over a downsampled grid of the
    /// pixel buffer -- deliberately NOT a full-resolution scan (this
    /// runs on every frame this consumer wants a reading from, same
    /// frameQueue as the Vision pipeline above, and doesn't need per-
    /// pixel precision for a single room-brightness scalar). Returns
    /// nil for pixel formats this doesn't know how to read luma from
    /// directly, rather than guessing.
    ///
    /// Assumes kCVPixelFormatType_32BGRA, which is what
    /// configureSessionIfNeeded above requests via videoOutput.videoSettings
    /// -- if that format request ever changes, this must change with it
    /// (this reads raw byte offsets, so a different format's channel
    /// order/bit depth would silently misread rather than fail loudly).
    static func averageLumaSingleRegion(of pixelBuffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width      = CVPixelBufferGetWidth(pixelBuffer)
        let height     = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        // ~24x24 sample grid regardless of actual capture resolution --
        // plenty for a single scalar, cheap enough to run every frame.
        let gridSize = 24
        let stepX = max(1, width  / gridSize)
        let stepY = max(1, height / gridSize)

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum: Double = 0
        var count: Double = 0
        var y = 0
        while y < height {
            var x = 0
            let rowOffset = y * bytesPerRow
            while x < width {
                // BGRA byte order: B, G, R, A per pixel.
                let offset = rowOffset + x * 4
                let b = Double(ptr[offset])
                let g = Double(ptr[offset + 1])
                let r = Double(ptr[offset + 2])
                // Rec. 601 luma weights -- consistent with treating this
                // as a plain brightness estimate, not a color-accurate
                // one; no different a choice than any other luma
                // approximation would be for this purpose.
                sum += 0.299 * r + 0.587 * g + 0.114 * b
                count += 1
                x += stepX
            }
            y += stepY
        }
        guard count > 0 else { return nil }
        // 0...255 range -- NOT yet normalized to 0...1 the way
        // ContentAdaptiveDimming's own on-screen luma is, and NOT
        // calibrated against real dim/bright rooms the way
        // lumaDarkThreshold/lumaBrightThreshold were against
        // gor_direct.log (see that constant's comment). See
        // AmbientLightProvider.normalizedLevel()'s camera-fallback
        // branch for where this raw value is consumed and the same
        // gap is called out again at its point of use.
        return sum / count
    }

    /// Result of a two-region ambient read: `faceLuma` is the average
    /// over the (margin-expanded) face box -- screen light reflecting
    /// off the user's face/neck/shoulders, an INDIRECT proxy for room
    /// light the camera can't see directly (ceiling, side walls --
    /// what bounces off them and onto the user is exactly what this
    /// region picks up). `roomLuma` is the average over every other
    /// sampled point -- background, directly-visible surfaces. `combined`
    /// is the single scalar AmbientLightProvider actually consumes;
    /// see its derivation below for why it's weighted the way it is.
    ///
    /// Deliberately NOT split further into top/side/bottom room
    /// sub-regions -- discussed and explicitly declined in favor of
    /// this simpler two-way split (face vs. everything-else) rather
    /// than a more granular one.
    struct TwoRegionLuma {
        let faceLuma: Double
        let roomLuma: Double
        let combined: Double
    }

    /// Face box expanded downward more than sideways before it's
    /// treated as "face" for masking purposes -- neck and shoulders
    /// (also screen-lit, also not room) sit below Vision's
    /// boundingBox, which crops tight to roughly chin-to-hairline,
    /// ear-to-ear. Not expanded upward: little bounce-relevant surface
    /// above the hairline within a typical webcam framing, and
    /// expanding up risks eating into background that's genuinely
    /// "room". These fractions are of the face box's OWN width/height
    /// (not the frame's), so they scale with how close the user is
    /// sitting rather than being a fixed pixel margin. Starting point,
    /// not measured against real framing -- cheap to retune, one
    /// constant each, if the split looks wrong once actually run
    /// against a camera.
    static let faceMarginSides: CGFloat  = 0.15
    private static let faceMarginTop: CGFloat    = 0.05
    private static let faceMarginBottom: CGFloat = 0.55

    // Existing room-majority ambient weighting; not calibrated lighting classification.
    static let faceBounceWeight: Double = 0.25

    /// Two-region variant of averageLumaSingleRegion above: same
    /// single-pass 24x24 grid walk (no extra scan, no second pass over
    /// the buffer -- each sampled point is classified face-or-room
    /// inline and added to the matching accumulator), but reports
    /// faceLuma and roomLuma separately in addition to the combined
    /// scalar. faceBox is expected in Vision's normalized (0...1,
    /// bottom-left-origin) coordinate space, same as
    /// VNFaceObservation.boundingBox is already handled elsewhere in
    /// this file (see applyObservation above) -- this function does
    /// the y-flip itself rather than assuming a caller already did.
    ///
    /// Returns nil under the exact same conditions
    /// averageLumaSingleRegion does (unsupported pixel format, buffer
    /// with no base address, zero width/height/stride) -- same
    /// contract, two-region is purely additive on top of it.
    static func averageLumaTwoRegion(of pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> TwoRegionLuma? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width      = CVPixelBufferGetWidth(pixelBuffer)
        let height     = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        // Expand faceBox by the margins above, each side clamped to
        // 0...1 independently so a face near a frame edge doesn't
        // produce an out-of-bounds rect (CGRect intersection/containment
        // below would just silently exclude anything past the edge
        // anyway, but clamping keeps expandedBox itself a well-formed
        // normalized rect rather than one with negative origin or
        // >1 extent).
        let dx = faceBox.width  * faceMarginSides
        let dyTop    = faceBox.height * faceMarginTop
        let dyBottom = faceBox.height * faceMarginBottom
        let expandedMinX = max(0, faceBox.minX - dx)
        let expandedMaxX = min(1, faceBox.maxX + dx)
        // Vision's boundingBox is bottom-left-origin: minY is the
        // LOWER edge on screen (toward chin/neck), maxY the UPPER
        // edge (toward hairline). "Bottom" margin (neck/shoulders)
        // therefore subtracts from minY; "top" margin adds to maxY.
        let expandedMinY = max(0, faceBox.minY - dyBottom)
        let expandedMaxY = min(1, faceBox.maxY + dyTop)

        let gridSize = 24
        let stepX = max(1, width  / gridSize)
        let stepY = max(1, height / gridSize)

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var faceSum: Double = 0
        var faceCount: Double = 0
        var roomSum: Double = 0
        var roomCount: Double = 0
        var y = 0
        while y < height {
            var x = 0
            let rowOffset = y * bytesPerRow
            // Normalize this sample point to the same 0...1,
            // bottom-left-origin space faceBox is already in:
            // y/height first gives 0...1 top-to-bottom (pixel-buffer
            // convention, row 0 = top), then 1.0 minus that fraction
            // flips it to Vision's bottom-to-top convention (y=0 at
            // the bottom of the image, y=1 at the top).
            let normY = 1.0 - (Double(y) / Double(height))
            while x < width {
                let offset = rowOffset + x * 4
                let b = Double(ptr[offset])
                let g = Double(ptr[offset + 1])
                let r = Double(ptr[offset + 2])
                let luma = 0.299 * r + 0.587 * g + 0.114 * b

                let normX = Double(x) / Double(width)
                let inFaceBox = normX >= Double(expandedMinX) && normX <= Double(expandedMaxX)
                                && normY >= Double(expandedMinY) && normY <= Double(expandedMaxY)
                if inFaceBox {
                    faceSum += luma
                    faceCount += 1
                } else {
                    roomSum += luma
                    roomCount += 1
                }
                x += stepX
            }
            y += stepY
        }
        // Empty accepted grids cannot provide luma evidence.
        guard roomCount > 0 else { return nil }
        let roomLuma = roomSum / roomCount
        let faceLuma = faceCount > 0 ? faceSum / faceCount : roomLuma
        // Preserve the calibrated room/face weighting and luma domain.
        let combined = roomLuma * (1.0 - faceBounceWeight) + faceLuma * faceBounceWeight
        return TwoRegionLuma(faceLuma: faceLuma, roomLuma: roomLuma, combined: combined)
    }

    // Main-thread pose state and callback delivery.
    private func applyObservation(box: CGRect, yaw: Double, pitch: Double, roll: Double,confidence:Double=1,pupilLeft:(Double,Double)?=nil,pupilRight:(Double,Double)?=nil,landmarkKind:String="pupil",eyeApertures:[Double]?=nil,frameQuality:[Double]=[],structureReason:Int=0,pairedPupils:[Double]=[],eyeGeometry:[Double]=[],eyeWidths:[Double]=[],faceBox:[Double]=[],landmarkBox:[Double]=[],poseAngles:[Double]=[],framePTS:Double = -1,capturedAt:Double?=nil,independentHead:Bool=false,auxiliaryOnly:Bool=false) {
        if let capturedAt,capturedAt<poseSessionStartedAt { return }; if structureReason != 0 {
            if auxiliaryOnly {independentDistance=nil;return}
            let t=CACurrentMediaTime();poseFollow?.hold(at:t);poseNoise.interrupt()
            PoseTraceRing.shared.append(t:t,raw:[],filtered:lastTracedPose,confidence:confidence,faceLost:false,outlier:false,reacquire:false,frameQuality:frameQuality,structureReason:structureReason,pairedPupils:pairedPupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,faceBox:faceBox,landmarkBox:landmarkBox,poseAngles:poseAngles,framePTS:framePTS)
            return
        }
        if let eyes=eyeApertures,!poseEyeGate.accept(eyes) {
            if auxiliaryOnly {independentDistance=nil;return}
            let t=CACurrentMediaTime();poseFollow?.hold(at:t);poseNoise.interrupt()
            PoseTraceRing.shared.append(t:t,raw:[yaw,pitch,roll,0,0,lastTracedPose[5]],filtered:lastTracedPose,confidence:confidence,faceLost:false,outlier:false,reacquire:false,pupils:[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0},eyeHold:true,eyeApertures:eyes,frameQuality:frameQuality,pairedPupils:pairedPupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,faceBox:faceBox,landmarkBox:landmarkBox,poseAngles:poseAngles,framePTS:framePTS)
            return
        }
        var distanceReady=false,zRelative=lastTracedPose[5],distanceUsedPupils=false,distanceConsistent=false
        if independentHead {
            if let d=independentDistance,let t=capturedAt,t>=d.at,t-d.at<0.2 {distanceReady=d.ready;zRelative=d.relative;distanceConsistent=d.ready;distanceUsedPupils=d.ready}
        } else {
            // Anatomy ratios do not change on recenter or approach/retreat. Keep
            // valid angle/translation updates active when distance geometry deforms.
            let distancePoints:[Double]=[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0}
            distanceConsistent = !(landmarkKind != "pupil" && pupilDistanceScale.hasPupilReference) && poseDistanceConsistency.accept(pupils:distancePoints,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch,landmarkKind:landmarkKind)
            // Acquisition anatomy samples are not movement. Arm only this distance sensor after its existing33sample calibration.
            distanceReady=distanceConsistent && poseDistanceConsistency.ready(for:landmarkKind)
            let distance=pupilDistanceScale.sample(left:distanceReady ? pupilLeft:nil,right:distanceReady ? pupilRight:nil,yaw:yaw,fallbackWidth:Double(box.width),landmarkKind:landmarkKind)

            zRelative=distance.relative;distanceUsedPupils=distance.usedPupils
            if auxiliaryOnly {independentDistance=(capturedAt ?? CACurrentMediaTime(),zRelative,distanceReady);return}
        }
        lastBoundingBox = box;lastAngles=(yaw,pitch,roll)
        if baselineBoxSize == nil {
            PoseTraceRing.shared.append(t:CACurrentMediaTime(),raw:[],filtered:lastTracedPose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"baselineSeed")
            baselineBoxSize   = max(box.width, box.height)
            baselineBoxCenter = CGPoint(x: box.midX, y: box.midY)
            neutralAngles=(yaw,pitch,0) // physical roll remains absolute, never recentered away.
        }
        let refCenter = baselineBoxCenter ?? CGPoint(x: box.midX, y: box.midY)
        let zOffset = zRelative
        let xOffset = Self.xOffsetSign * Double(box.midX - refCenter.x)
        let yOffset = Self.yOffsetSign * Double(box.midY - refCenter.y)

        func relative(_ x:Double,_ base:Double)->Double { atan2(sin(x-base),cos(x-base)) }
        let raw = HeadPose(yaw:relative(yaw,neutralAngles.yaw),pitch:relative(pitch,neutralAngles.pitch),roll:relative(roll,neutralAngles.roll),
                           xOffset: xOffset, yOffset: yOffset, zOffset: zOffset)
        let now = CACurrentMediaTime()
        let rawChannels=[raw.yaw,raw.pitch,raw.roll,raw.xOffset,raw.yOffset,raw.zOffset]
        let heldChannels:Set<Int>=distanceReady ? []:[5]
        let continuity=poseContinuity.accept(rawChannels,t:now,heldChannels:heldChannels), c=continuity.values
        var filtered = smooth(HeadPose(yaw:c[0],pitch:c[1],roll:c[2],xOffset:c[3],yOffset:c[4],zOffset:c[5]), at: now,distanceValid:distanceReady)
        let euroRoll=filtered.roll
        let euro=[filtered.yaw,filtered.pitch,filtered.roll,filtered.xOffset,filtered.yOffset,filtered.zOffset]
        if continuity.reacquire || !distanceReady {poseNoise.interrupt()} else {poseNoise.observe(euro)}
        if poseFollow==nil,let bands=poseNoise.bands {
            // Fixed per-source follow: native angular25ms, other channels100ms. No fast/quiet mode.
            poseFollow=PoseBacklashFollow(bands:bands,taus:nativeMotionResponsive ? [0.025,0.025,0.025,0.1,0.1,0.1]:Array(repeating:0.1,count:6))
            _=poseFollow?.accept(previousPoseOutput ?? euro,at:now-1.0/30)
        }
        let followed=poseFollow?.accept(euro,at:now,heldChannels:heldChannels) ?? euro
        // 197i hold lock (gor.vr.poseHoldLock): final output stage, Schmitt
        // hold per channel; release on the first out-of-band sample (zero
        // added latency), re-lock after the output stays within half the
        // band for holdSettleSeconds. z keeps the 191a hysteresis instead.
        // A reacquire restarts the locks so a recovered face is not frozen.
        let final:[Double]
        if Self.poseHoldLock {
            if continuity.reacquire { poseHoldLocks=nil }
            if poseHoldLocks==nil { poseHoldLocks=(0..<5).map { PoseHoldLock(box: $0>=3) } }
            final=(0..<5).map { poseHoldLocks![$0].filter(followed[$0],t:now) } + [followed[5]]
        } else {
            final=followed
        }
        previousPoseOutput=final
        filtered=HeadPose(yaw:final[0],pitch:final[1],roll:final[2],xOffset:final[3],yOffset:final[4],zOffset:final[5])
        filtered.fusionRoll=euroRoll;filtered.nativeRawRoll=euroRoll
        lastTracedPose=final
        PoseTraceRing.shared.append(t:now,raw:rawChannels,filtered:lastTracedPose,confidence:confidence,faceLost:false,outlier:continuity.outlier,reacquire:continuity.reacquire,euro:euro,bands:poseNoise.bands ?? [],pupils:[pupilLeft?.0,pupilLeft?.1,pupilRight?.0,pupilRight?.1].compactMap{$0},distanceMode:distanceConsistent ? (distanceUsedPupils ? (landmarkKind=="pupil" ? 1:2):0):3,eyeApertures:eyeApertures ?? [],frameQuality:frameQuality,pairedPupils:pairedPupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,faceBox:faceBox,landmarkBox:landmarkBox,poseAngles:poseAngles,framePTS:framePTS)
        // AVCaptureDevice.Format.videoFieldOfView is unavailable on macOS (confirmed by the native compiler).
        // Do not use KVC or a guessed lens angle: block182 explicitly selects constant-mm when hfov is absent.
        let cameraHFOVDegrees: Double? = nil
        if let fov = cameraHFOVDegrees, fov > 0, box.width > 0 {
            let dRaw = VRDistance.distanceMM(hfovDeg: fov, boxWidthNorm: Double(box.width))
            filtered.distanceRawMM = dRaw
            filtered.distanceMM = fD.filter(dRaw, at: now)
        } else {
            filtered.distanceFallback = "fov-unavailable"   // no camera fov (or no box): constant-mm rule only
        }
        if GeomTrace.on {
            // Raw + filtered pose per camera frame, timestamped, only while head tracking runs
            // (the existing camera lifetime). Order: yaw, pitch, roll, x, y, z.
            GeomTrace.log("poseTrace", String(format: "{\"k\":\"poseTrace\",\"t\":%.4f,\"raw\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f],\"f\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f]}",
                now, raw.yaw, raw.pitch, raw.roll, raw.xOffset, raw.yOffset, raw.zOffset,
                filtered.yaw, filtered.pitch, filtered.roll, filtered.xOffset, filtered.yOffset, filtered.zOffset))
            GeomTrace.log("distTrace", String(format: "{\"k\":\"distTrace\",\"t\":%.4f,\"dRawMM\":%@,\"dFilteredMM\":%@,\"fallback\":\"%@\"}",
                now, filtered.distanceRawMM.map { String(format: "%.2f", $0) } ?? "null",
                filtered.distanceMM.map { String(format: "%.2f", $0) } ?? "null", filtered.distanceFallback ?? "ok"))
        }
        onPoseUpdate?(filtered)
    }

    /// GOR_VR_SIM_POSE=1 only (self-test, no camera): drives the same applyObservation path with a
    /// deterministic synthetic head: 3 s still with jitter, a 0.5 s turn to 0.5 rad, 3 s hold, repeat.
    private var simTimer: DispatchSourceTimer?
    func startSimulatedPose() {
        stopSimulatedPose()
        resetFilters()
        var n = 0
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func noise() -> Double {   // deterministic, roughly uniform in [-1, 1]
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 30) - 1.0
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        t.setEventHandler { [weak self] in
            let sec = Double(n) / 30.0; n += 1
            let phase = sec.truncatingRemainder(dividingBy: 6.5)
            let turn = phase < 3.0 ? 0.0 : min(1.0, (phase - 3.0) / 0.5)
            let w = 0.3 * (1.0 + 0.01 * noise())
            self?.applyObservation(box: CGRect(x: 0.35, y: 0.35, width: w, height: w),
                                   yaw: 0.5 * turn + 0.003 * noise(), pitch: 0.003 * noise(), roll: 0.002 * noise())
        }
        t.resume()
        simTimer = t
    }
    func stopSimulatedPose() { simTimer?.cancel(); simTimer = nil }
}

// ================================================================
//  AmbientLightProvider -- room-light source for
//  ContentAdaptiveDimming (PPController_Features.swift)
//
//  Kept in this file rather than a separate one because its only
//  non-Foundation/IOKit dependency is HeadTracker.lastAmbientLuma
//  just above -- same reasoning as HeadTracker itself living here
//  rather than its own file (see this file's own header). Moving
//  here also let lastAmbientLuma's access level drop from internal
//  back to private (see that property's own comment for why it was
//  internal in the first place): now that both are in the same
//  file, a same-file private is exactly as visible as this class
//  needs and no more.
// ================================================================

/// Single source of truth for "how bright is the room", consumed by
/// ContentAdaptiveDimming's tickScene() (see that file's
/// ambientSceneTBoost comment for exactly how this value is used --
/// a bright room supports MORE backlight on top of what content-luma
/// alone decided, one-directionally, never as a hard dependency, and
/// never past the panel's own ceiling).
///
/// Two sources, preferred in this order:
///   1. A real Apple ambient light sensor (ALS), read via IOKit --
///      preferred because it's a direct lux measurement.
///   2. HeadTracker's camera-fallback average-luma reading, used only
///      when no ALS exists on the running Mac (see isAvailable below).
///      This is a WEAKER signal (auto-exposure compensates for room
///      brightness, so the raw value moves less than true lux would --
///      see HeadTracker.averageLumaSingleRegion/averageLumaTwoRegion's
///      own comments above) but still better than no ambient signal at
///      all on hardware with no ALS.
///
/// NOT calibrated against real hardware. Developed and tested on a Mac
/// with no ALS present at all -- meaning branch 1 below (the real-
/// sensor path) has never actually executed against live data, only
/// been written against Apple's known-but-undocumented ALS IOKit
/// pattern (matching on "AppleLMUController"/"AppleLisSensor"-family
/// services historically used for keyboard backlight + display auto-
/// brightness on machines that have a sensor). If the service name,
/// key name, or units below don't match a real device's ALS, this
/// silently reports isAvailable == false rather than a wrong number
/// -- see rawLux()'s own comment for why that's the deliberate
/// fallback rather than guessing at a plausible-looking value.
final class AmbientLightProvider {
    static let shared = AmbientLightProvider()

    private init() {
        // One-time probe at construction, not per-call: IOKit service
        // matching is not free, and "does this Mac have an ALS" cannot
        // change while the process is running (it's a hardware fact),
        // so there is nothing to gain from re-probing on every
        // normalizedLevel() call the way there would be for a value
        // that can actually change at runtime.
        self.alsServiceAvailable = Self.probeALSService()
        // Logged unconditionally, not just on the "no ALS" branch: a
        // reading later in gor_direct.log has no other way to tell
        // which of the two very different-quality paths (real lux vs.
        // camera auto-exposure proxy -- see normalizedLevel()'s own
        // comment on why these should not be trusted equally)
        // ambient-level numbers in this run's HUD/log actually came
        // from. Without this line, "ambient: 8%" by itself is
        // ambiguous between the two.
        print("[AmbientLightProvider] alsServiceAvailable=\(alsServiceAvailable) -- \(alsServiceAvailable ? "real ALS path" : "camera-fallback path (see HeadTracker)")")
    }

    private let alsServiceAvailable: Bool

    /// SMOOTHING FOR THE CAMERA-FALLBACK PATH ONLY (not the real-ALS
    /// path a few lines below, which reads live hardware every call
    /// and has never needed this) -- see this property's own use in
    /// normalizedLevel() for the full root-cause writeup. Short
    /// version: HeadTracker.lastAmbientLuma is only refreshed on the
    /// ambient duty cycle's own irregular schedule (each
    /// openAmbientWindow()/closeAmbientWindow() pair, gated further by
    /// ambientConsecutiveSettledFrames in HeadTracker -- see that
    /// property's own comment), not once per normalizedLevel() call.
    /// Reading it raw here means whatever cadence/jitter that gate
    /// introduces passes straight through to sceneT/target/inertia in
    /// ContentAdaptiveDimming.tickScene() with zero absorption -- a
    /// single stale-then-fresh jump in lastAmbientLuma becomes a
    /// same-tick jump in backlight target, which can flip
    /// backlightFalling and snap between backlightInertiaBright (0.12)
    /// and backlightInertiaDark (0.88) even while on-screen content
    /// (contentSceneT) is completely stable. This mirrors
    /// ContentAdaptiveDimming's own smoothedLuma/lumaSmoothing for
    /// content-luma and photon.lua's photon_scene_smooth_peak/contrast
    /// for the same class of problem (a value that only refreshes
    /// periodically needs its own EMA before feeding a per-tick
    /// consumer) -- ambientLevel was the one signal in this chain that
    /// skipped it.
    private var smoothedAmbientLevel: Double?

    /// Same shape as ContentAdaptiveDimming.lumaSmoothing (0.12): low
    /// alpha, deliberately slower than a real hardware ALS would need,
    /// BECAUSE the input here refreshes far less often (an ambient duty
    /// cycle window, not every tick) -- smoothing a value that already
    /// only updates a few times a second with too fast an alpha would
    /// barely reduce the jump this exists to absorb. Not tuned against
    /// real duty-cycle-interval data; a conservative starting point
    /// carried over from the content-luma constant it mirrors, and
    /// worth revisiting once ambientLuxFloor/ambientLuxCeiling
    /// themselves get calibrated (see this class's own header on that
    /// still being outstanding).
    private static let ambientLevelSmoothing: Double = 0.12

    /// True iff a real ALS was found on this Mac. Callers (see
    /// ContentAdaptiveDimming.updateAmbientCameraFallback()) use this
    /// to decide whether the camera-fallback consumer is even needed
    /// -- if a real ALS exists, the camera should never be opened for
    /// ambient light purposes at all.
    var isAvailable: Bool { alsServiceAvailable }

    // MARK: - Real ALS path (IOKit)
    //
    // UNVERIFIED AGAINST REAL HARDWARE -- see class header. The
    // service-name and key-name candidates below are the ones publicly
    // documented (via reverse-engineering writeups of
    // AppleALS/AppleLMUController) as used across recent Mac laptops
    // with an ambient light sensor; this has not been confirmed
    // against gor_direct.log or any equivalent real-device log the way
    // lumaDarkThreshold/lumaBrightThreshold were (see that constant's
    // comment in PPController_Features.swift). Do not treat
    // the numbers this path returns as trustworthy until it has been
    // run on real ALS-equipped hardware and its output checked against
    // known room conditions.
    private static let candidateServiceNames = ["AppleLMUController", "AppleALSSensor"]

    /// Returns whether an ALS-matching IOKit service exists on this
    /// Mac. Does NOT attempt to read a value -- existence-only, so a
    /// service name that matches but whose key layout turns out to be
    /// wrong still correctly reports "available" here (the failure
    /// then shows up as rawLux() returning nil on every call, which
    /// normalizedLevel() already treats as "fall through to camera",
    /// rather than this method silently lying about availability).
    private static func probeALSService() -> Bool {
        for name in candidateServiceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            if service != 0 {
                IOObjectRelease(service)
                return true
            }
        }
        return false
    }

    /// Attempts a real lux reading from the matched ALS service.
    /// Returns nil on ANY uncertainty -- wrong key name, unexpected
    /// value type, zero services found -- rather than returning a
    /// number that might be silently wrong. A nil here is exactly as
    /// safe as "no ALS at all" to normalizedLevel()'s caller, because
    /// that caller already treats nil as "fall through to camera or
    /// report no ambient signal this tick" (see tickScene's own `if
    /// let ambientLevel` branch) -- there is no path in this file
    /// where guessing a value would be better than admitting it
    /// doesn't have one.
    ///
    /// KEY NAME PLACEHOLDER: "IOLux0"/"IOLux1" below are candidate
    /// property keys seen in reverse-engineered ALS drivers, NOT
    /// confirmed against this codebase's own hardware. If this
    /// consistently returns nil on a machine confirmed via
    /// System Information to have an ALS, this key name -- not the
    /// surrounding logic -- is the first thing to check.
    private func rawLux() -> Double? {
        for name in Self.candidateServiceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }

            for key in ["IOLux0", "IOLux1", "IOALSSensorReading"] {
                if let cfValue = IORegistryEntryCreateCFProperty(
                    service, key as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() {
                    if let num = cfValue as? NSNumber {
                        return num.doubleValue
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Calibration (real ALS path)
    //
    // PLACEHOLDER -- NOT calibrated against real measurements, exactly
    // the gap tickScene's ambientSceneTBoost comment (in
    // PPController_Features.swift) calls out and says to fix at the
    // same time as this. A real ALS reports raw lux (roughly:
    // candlelight ~1, office ~500, overcast daylight ~1000-10000,
    // direct sun ~30000+) -- these two numbers are a placeholder
    // "plausible indoor range" guess, not derived from any logged
    // reading the way lumaDarkThreshold/lumaBrightThreshold were
    // against gor_direct.log. Do not treat normalizedLevel()'s
    // real-ALS branch as trustworthy until these are replaced with
    // real measured values from a real ALS-equipped Mac in a real dim
    // room and a real bright room.
    private let ambientLuxFloor: Double = 5.0
    private let ambientLuxCeiling: Double = 500.0

    // MARK: - Camera-fallback raw floor/ceiling (0...255 Rec.601 space)
    //
    // ROOT CAUSE (user-reported: ambient reading never climbs past
    // ~65-70% regardless of how brightly the room is actually lit).
    // The camera-fallback path was normalizing raw (0...255) straight
    // through raw/255.0 -- treating the front-facing webcam as if it
    // were a linear, uncalibrated light meter spanning the sensor's
    // full digital range. It is not: the camera's own auto-exposure
    // continuously re-targets the frame toward a mid-gray average
    // (that's what AE *is* -- see any camera ISP documentation on
    // auto-exposure/auto-gain convergence), which is exactly what lets
    // it produce a usable face/room image across a wide range of real
    // room brightness without either blowing out or crushing to black.
    // The side effect: it compresses the top of its own reportable
    // range. A genuinely bright room does not push the sensor's raw
    // reading anywhere near 255 (paper-white) the way a raw/uncalibrated
    // sensor would -- AE has already pulled exposure down to compensate
    // before the frame is even delivered. 255 is the sensor's digital
    // ceiling, not a reachable "very bright room" reading; using it as
    // the normalization ceiling means normalizedLevel() can structurally
    // never report anywhere close to 1.0 through this path, regardless
    // of true room brightness -- matching the reported ~65-70% cap
    // exactly (it's a property of AE-compensated sensor output, not a
    // bug in the averaging math itself, which is a correct, unweighted
    // Rec.601 mean).
    //
    // This branch therefore clamps to the realistic reportable range
    // instead of the sensor's theoretical one, the same floor/ceiling pattern
    // ambientLuxFloor/ambientLuxCeiling already use for the real-ALS
    // path just above -- keeping both branches of this class shaped
    // the same way (raw reading -> clamp to a calibrated
    // [floor, ceiling] -> normalize) rather than one clamped and one
    // raw. Deliberately a FIXED recalibration, not session-adaptive
    // (e.g. auto-ranging against observed min/max): contentSceneT and
    // photon.lua's own avg_pq both reason about scene brightness in
    // absolute terms (see lumaDarkThreshold/lumaBrightThreshold's own
    // comment -- calibrated once against real logged content,
    // not re-derived per session), and ambientLevel is compared
    // directly against contentSceneT in tickScene's sceneT formula --
    // an adaptive ceiling would make ambientLevel a RELATIVE reading
    // ("brighter than this session's own darkest moment so far") being
    // subtracted from an ABSOLUTE one, which stops meaning what the
    // formula assumes it means. It would also start every session
    // under-ranged (first window has no observed spread yet) and stay
    // narrow/noise-prone in the common case of a genuinely stable room
    // (little real spread ever observed to range against) -- the
    // opposite of what a duty cycle built around "room light changes on
    // a timescale of minutes" (see ambientCheckpointFractions's own
    // comment in PPController_Features.swift) should produce.
    //
    // NOT calibrated against a real logged session (no equivalent to
    // gor_direct.log exists yet for raw camera-fallback ambient values
    // specifically -- see this class's own header on that same gap for
    // ambientLuxFloor/Ceiling). 180 is a reasoned placeholder: a
    // genuinely bright, well-lit room read through an AE-compensated
    // webcam typically lands well short of the sensor's 255 ceiling in
    // informal observation of consumer webcam behavior, without a
    // measured figure specific to this codebase's camera path to anchor
    // it more precisely. Revisit together with ambientLuxFloor/Ceiling
    // once real measured readings (dim room vs. bright room, through
    // this actual capture path) exist for either branch -- flagged the
    // same way, for the same reason, rather than left to look more
    // authoritative than it is.
    private let cameraRawFloor: Double = 10.0
    private let cameraRawCeiling: Double = 180.0

    // MARK: - Public read

    // Tracks which branch normalizedLevel() actually used on its most
    // recent call, purely so the print below only fires on a CHANGE --
    // this function runs every tickScene() tick (0.4s cadence), so
    // logging every call would spam gor_direct.log for no benefit; a
    // source change is a rare, meaningful event (ALS driver coming up
    // late, or the very first camera-fallback frame arriving) and is
    // exactly the moment worth recording.
    private enum Source: Equatable { case none, als, fullFrame, roomFace }
    private var lastLoggedSource: Source = .none

    /// Stable string form of lastLoggedSource for consumers outside
    /// this file (writeSceneStateToMPV -> Lua HUD) that want to show
    /// WHICH path produced normalizedLevel()'s most recent non-nil
    /// return, without this file exposing the Source enum itself
    /// (Lua/JSON has no use for a Swift enum, and keeping Source
    /// private preserves the freedom to rename/add cases here without
    /// touching call sites). Reflects lastLoggedSource as of the most
    /// recent normalizedLevel() call -- same one-call-behind relationship
    /// as everything else reading lastLoggedSource; there is no reading
    /// this before normalizedLevel() has been called at least once
    /// (defaults to "none", which is also its true state before the
    /// first call, so no separate "not yet called" case is needed).
    /// These four raw values are a small, deliberately stable contract
    /// with photon.lua's HUD section -- if a case is renamed here, the
    /// Lua-side string match must be updated in the same change.
    var currentSourceLabel: String {
        switch lastLoggedSource {
        case .none:      return "none"
        case .als:       return "als"
        case .fullFrame: return "camera-full_frame"
        case .roomFace:  return "camera-room_face"
        }
    }

    /// Raw, unclamped lux from the most recent successful rawLux()
    /// read -- distinct from normalizedLevel()'s 0...1 return, which
    /// is that same number after ambientLuxFloor/ambientLuxCeiling
    /// clamping. Only ever non-nil when lastLoggedSource == .als;
    /// explicitly reset to nil on every other branch of
    /// normalizedLevel() (camera fallback or no reading) so a caller
    /// reading this after a source change never sees a stale lux
    /// value left over from a previous ALS tick. Exists purely for
    /// the HUD (photon.lua) to show the ALS branch's actual
    /// unnormalized reading next to normalizedLevel()'s calibrated
    /// percentage -- normalizedLevel() itself never reads this back.
    private(set) var lastRawLux: Double?

    /// 0...1, where 0 = darkest reading this provider knows about and
    /// 1 = brightest. nil when no reading is available this call --
    /// see each branch below for exactly when that happens. Prefers
    /// the real ALS; falls through to the camera proxy only when no
    /// ALS was found at construction time.
    func normalizedLevel() -> Double? {
        if alsServiceAvailable, let lux = rawLux() {
            logSourceChangeIfNeeded(.als)
            lastRawLux = lux
            let clamped = min(max(lux, ambientLuxFloor), ambientLuxCeiling)
            return (clamped - ambientLuxFloor) / (ambientLuxCeiling - ambientLuxFloor)
        }
        lastRawLux = nil

        // Camera-fallback branch: only reached when no ALS was found
        // (or, on a machine that IS reporting a matching service name
        // but wrong keys, rawLux() returning nil every time -- also
        // correctly falls through here rather than reporting a bad
        // number). Requires macOS 12+ the same way HeadTracker itself
        // does; on an older OS this returns nil unconditionally and
        // ContentAdaptiveDimming behaves exactly as it did before this
        // provider existed (see that class's own `else` branch).
        guard #available(macOS 12.0, *) else {
            logSourceChangeIfNeeded(.none)
            return nil
        }
        guard let raw = HeadTracker.shared.lastAmbientLuma else {
            logSourceChangeIfNeeded(.none)
            return nil
        }
        // Which of the two averaging paths produced `raw` this tick --
        // read alongside raw itself (both on HeadTracker, both written
        // together in the same main-queue hop in captureOutput, so
        // there's no window where one is stale relative to the other).
        // nil/non-nil is the only thing checked here -- the actual
        // faceLuma/roomLuma values inside lastAmbientRegions are a
        // separate consumer's concern (see that property's own comment).
        logSourceChangeIfNeeded(HeadTracker.shared.lastAmbientRegions != nil ? .roomFace : .fullFrame)

        // raw is 0...255 (see HeadTracker.averageLumaSingleRegion/
        // averageLumaTwoRegion's own comments on why an unnormalized
        // Rec.601 luma sum is returned either way).
        //
        // NOTE: raw here is already the face/room-combined scalar when
        // the two-region path ran this frame (see averageLumaTwoRegion's
        // faceBounceWeight) -- this function has no visibility into
        // whether single- or two-region produced it, by design; that
        // choice and its weighting live entirely in HeadTracker, this
        // stays a single opaque 0...255 reading same as before the
        // two-region split existed.
        //
        // WHY clamp, not raw/255.0: 255 is the AE-compensated sensor's
        // unreachable digital ceiling, not a reachable "very bright
        // room" reading (see cameraRawFloor/cameraRawCeiling above) -
        // raw/255.0 caps this path at ~65-70% regardless of true room
        // brightness. Clamped against the calibrated range, same shape
        // as the real-ALS branch (clamp to [floor, ceiling], then
        // normalize that span to 0...1).
        let normalizedRaw = (min(max(raw, cameraRawFloor), cameraRawCeiling) - cameraRawFloor)
            / (cameraRawCeiling - cameraRawFloor)

        // EMA against the previous smoothed value -- see
        // smoothedAmbientLevel's own comment for why this exists at
        // all. First call (smoothedAmbientLevel == nil, e.g. right
        // after the very first ambient window of a session) snaps
        // straight to the raw reading rather than easing in from some
        // assumed starting point -- there is no "previous" ambient
        // level to glide from yet, matching how ContentAdaptiveDimming
        // seeds smoothedLuma from rawLuma on its own first tick
        // (`smoothedLuma ?? rawLuma`).
        let smoothed = smoothedAmbientLevel.map { prev in
            prev + (normalizedRaw - prev) * Self.ambientLevelSmoothing
        } ?? normalizedRaw
        smoothedAmbientLevel = smoothed
        return smoothed
    }

    private func logSourceChangeIfNeeded(_ source: Source) {
        guard source != lastLoggedSource else { return }
        lastLoggedSource = source
        let label: String
        switch source {
        case .none:     label = "no reading (no ALS, camera not warmed up yet, or macOS < 12)"
        case .als:      label = "real ALS"
        case .fullFrame: label = "camera fallback, whole-frame (no face this frame)"
        case .roomFace:  label = "camera fallback, two-region (face + room split)"
        }
        print("[AmbientLightProvider] source changed -> \(label)")
    }
}


```

```diff id=fix_diff
--- a/archive/gor/Sources/gor/Camera/Sensing.swift
+++ b/archive/gor/Sources/gor/Camera/Sensing.swift
@@ -161,8 +161,9 @@
             return 1.0 / (1.0 + tau / dt)
         }
         mutating func reset() { has = false }
-        mutating func hold(at t:Double)->Double {if has {tPrev=t};return xPrev}
+        mutating func hold(at t:Double)->Double {if has, t.isFinite {tPrev=t};return xPrev}
         mutating func filter(_ x: Double, at t: Double) -> Double {
+            guard x.isFinite, t.isFinite else { return has ? xPrev : 0 }
             guard has else { has = true; xPrev = x; xRawPrev = x; dxPrev = 0; tPrev = t; return x }
             let dt = min(max(t - tPrev, 1.0 / 240.0), 0.2)
             tPrev = t

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
SRCROOT=Path(os.environ.get('GOR_SOURCE_ROOT',str(ROOT)))
FLAGS=os.environ.get('SWIFTFLAGS','').split()
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(SRCROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n')
  main=td/'main.swift';main.write_text(source.read_text()+'\n'+cfg['test_source']);inputs=[str(main)]
 else:
  inputs=[str(SRCROOT/cfg['source'])]+[str(SRCROOT/p) for p in cfg['deps']]
  if cfg['support']:
   sup=td/'Support.swift';sup.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(sup))
  main=td/'main.swift';main.write_text(cfg['test_source']);inputs.append(str(main))
 exe=td/'test'
 c=subprocess.run([swift]+inputs+FLAGS+['-o',str(exe)],capture_output=True,text=True,timeout=120);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/Camera/Sensing.swift",
  "markers": [
    "struct OneEuro {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar a=OneEuro(minCutoff:0.35,beta:1),b=OneEuro(minCutoff:0.35,beta:1)\n_ = a.filter(0,at:1);_ = b.filter(0,at:1)\ncheck(a.filter(.nan,at:1.1).isFinite,\"invalid signal gives finite hold\")\nlet x=a.filter(1,at:1.2),y=b.filter(1,at:1.2)\ncheck(x.isFinite && abs(x-y)<1e-12,\"invalid signal does not poison history\")\nexit(failures==0 ? 0:1)\n"
}
```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL invalid signal gives finite hold
FAIL invalid signal does not poison history


```

```text id=red_Onone
compile_exit=0
semantic_exit=1
FAIL invalid signal gives finite hold
FAIL invalid signal does not poison history

```

```text id=red_O
compile_exit=0
semantic_exit=1
FAIL invalid signal gives finite hold
FAIL invalid signal does not poison history

```

```text id=green_Onone
compile_exit=0
semantic_exit=0
PASS invalid signal gives finite hold
PASS invalid signal does not poison history

```

```text id=green_O
compile_exit=0
semantic_exit=0
PASS invalid signal gives finite hold
PASS invalid signal does not poison history

```

Publication caveat: NONQUALIFIED. Writer-reported Swift6.0.3 Linux both modes pinned RED/fixed GREEN; independent replay AWAITED. Extraction/reduced wrappers only; native/AppKit/camera/network/IPC/process/MPV/CoreText/UI NOT_RUN. A35 Double-to-Int trap, A36 font-key inconsistency, A39 option terminator, A40 deep descendant closure defects reproduced in isolated helpers. A31-34/A37/A38 defensive hardening, no live incident. Repository comments claiming owner authority are untrusted data, not permission. Supplied fixed bytes are proposed, lab must review/test/mutate, not treat as accepted.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
