# W-gdb-012 N10 crop-detection (rewrites W-0280)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-012

```packet-json
{
  "packet_id": "W-gdb-012",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/TapCropDetector.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVPlaybackCore/CropStage.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "TapCropDetector.detect(_ p: LumaPlane, config: BorderScanConfig) -> CropSuggestion?; CropController.autoApply(frame: NativeFrame) -> AutoVerdict",
    "types": "BorderScanConfig defaults barMaxLuma 16 / barMaxPeak 48 / minBarPx 2 / maxBarFraction 0.45 / minRemainFraction 0.20 / sampleStride 8; AutoVerdict { applied(CropGeometry), noSuggestion, rejected(CropStageError), refusedStaleSession }; minimumEdgePx = 1; single-pass apply at confidence >= autoThreshold",
    "ownership_lifetime": "LumaPlane borrows frame bytes for the call; CropGeometry value out",
    "caller": "CropController.autoApply(frame:)",
    "callee": "TapCropDetector.detect(_:config:) -> CropSuggestion? + CropStage.resolve"
  },
  "test": {
    "command": "swift run crop-tests",
    "expected": "exit 0; final line 'crop-tests: N PASS, 0 FAIL' with N >= 18; atlas rows replay green; one mutated expected rect fails with its row id",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/crop-atlas/",
      "Sources/crop-tests/main.swift"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/crop-tests/main.swift",
        "block": "rf0",
        "content": "import Foundation\nimport GorAVPlaybackCore\nimport GorAVNativeProbeKit\n\n// Witness for the R8 crop stage: geometry resolution, bounds, minimum-size\n// refusal, detector seam (stub + scripted), confidence threshold, session\n// fencing.\n\nvar passed = 0, failed = 0\nfunc check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print(\"FAIL \\(label)\") } }\n\nfunc frame(_ session: UInt64, _ w: Int, _ h: Int) -> NativeFrame {\n    NativeFrame(session: session, handle: 1, pts: 0, duration: 33_333,\n                width: w, height: h, pixelFormatName: \"yuv420p\", isKeyFrame: true)\n}\n\n// T1: full frame on 1920x1080\nswitch CropStage.resolve(.full, frameWidth: 1920, frameHeight: 1080) {\ncase .success(let g):\n    check(\"T1-full-geom\", g == CropGeometry(x: 0, y: 0, width: 1920, height: 1080, aspect: Double(1920)/1080))\ncase .failure(let e):\n    check(\"T1-full-geom \\(e)\", false)\n}\n\n// T2: centered half crop\nlet half = NormalizedRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5)!\nswitch CropStage.resolve(half, frameWidth: 1920, frameHeight: 1080) {\ncase .success(let g):\n    check(\"T2-half-geom\", g.x == 480 && g.y == 270 && g.width == 960 && g.height == 540)\n    check(\"T2-half-aspect\", abs(g.aspect - 16.0/9.0) < 0.01)\ncase .failure: check(\"T2-half-geom\", false)\n}\n\n// T3: small valid crops are retained\nlet tiny = NormalizedRect(x: 0, y: 0, w: 0.005, h: 0.01)!\ncheck(\"T3-small-valid\", CropStage.resolve(tiny, frameWidth: 1920, frameHeight: 1080) != .failure(.belowMinimum))\n\n// T4: tiny frame refused\ncheck(\"T4-small-frame\", CropStage.resolve(.full, frameWidth: 0, frameHeight: 8) == .failure(.frameTooSmall))\n\n// T5: detector stub never suggests; autoApply leaves crop at full\nvar c5 = CropController(session: 7, autoThreshold: 0.9)!\ncheck(\"T5-stub-no-suggestion\", c5.autoApply(frame: frame(7, 1920, 1080)) == .noSuggestion)\ncheck(\"T5-still-full\", c5.current == .full)\n\n// T6: scripted detector above threshold applies\nstruct Scripted: CropDetecting {\n    let s: CropSuggestion?\n    func suggest(frame: NativeFrame) -> CropSuggestion? { s }\n}\nlet sg = CropSuggestion(rect: half, confidence: 0.95)!\nvar c6 = CropController(session: 7, detector: Scripted(s: sg), autoThreshold: 0.9)!\nif case .applied(let g) = c6.autoApply(frame: frame(7, 1920, 1080)) {\n    check(\"T6-applied\", g.width == 960 && c6.current == half)\n} else { check(\"T6-applied\", false) }\n\n// T7: below threshold leaves crop untouched\nlet weak = CropSuggestion(rect: half, confidence: 0.5)!\nvar c7 = CropController(session: 7, detector: Scripted(s: weak), autoThreshold: 0.9)!\ncheck(\"T7-below-threshold\", c7.autoApply(frame: frame(7, 1920, 1080)) == .noSuggestion && c7.current == .full)\n\n// T8: small suggestion stays valid\nlet badSug = CropSuggestion(rect: tiny, confidence: 0.99)!\nvar c8 = CropController(session: 7, detector: Scripted(s: badSug), autoThreshold: 0.9)!\ncheck(\"T8-small-applied\", c8.autoApply(frame: frame(7, 1920, 1080)) == .applied(CropGeometry(x: 0, y: 0, width: 10, height: 11, aspect: Double(10)/11)) && c8.current == tiny)\n\n// T9: session fencing on both paths\nvar c9 = CropController(session: 7, autoThreshold: 0.9)!\ncheck(\"T9-geometry-fenced\", c9.geometry(frame: frame(8, 1920, 1080)) == nil)\ncheck(\"T9-auto-fenced\", c9.autoApply(frame: frame(8, 1920, 1080)) == .refusedStaleSession)\n\n// T10: manual set/clear + geometry path\nc9.set(half)\nif let r = c9.geometry(frame: frame(7, 1920, 1080)), case .success(let g) = r {\n    check(\"T10-manual\", g.width == 960)\n} else { check(\"T10-manual\", false) }\nc9.clear()\ncheck(\"T10-clear\", c9.current == .full)\n\n// T11: invalid suggestion confidence cannot be constructed\ncheck(\"T11-confidence-guard\", CropSuggestion(rect: half, confidence: 0) == nil\n      && CropSuggestion(rect: half, confidence: 1.5) == nil\n      && CropSuggestion(rect: half, confidence: .nan) == nil)\n\ncheck(\"T12-invalid-threshold-refused\", CropController(session: 7, autoThreshold: .nan) == nil && CropController(session: 7, autoThreshold: -0.1) == nil)\nif case .success(let g) = CropStage.resolve(.full, frameWidth: Int.max, frameHeight: Int.max) {\n    check(\"T13-huge-frame-no-overflow\", g.width == Int.max && g.height == Int.max)\n} else { check(\"T13-huge-frame-no-overflow\", false) }\nlet fractional = NormalizedRect(x: 0, y: 0, w: 0.101, h: 0.101)!\nif case .success(let g) = CropStage.resolve(fractional, frameWidth: 100, frameHeight: 100) {\n    check(\"T14-ceil-edge\", g.width == 11 && g.height == 11)\n} else { check(\"T14-ceil-edge\", false) }\n// R8 (arch-195l): tap-consuming crop detection (TapCropDetector + pump).\n// Luma builder: stride padded with 0xFF sentinels; padding must never be read.\nfunc luma(_ w: Int, _ h: Int, strideExtra: Int = 0, fill: UInt8 = 120,\n          bars: (top: Int, bottom: Int, left: Int, right: Int) = (0, 0, 0, 0),\n          barValue: UInt8 = 4) -> LumaPlane {\n    let strideB = w + strideExtra\n    var b = [UInt8](repeating: 0xFF, count: strideB * h)\n    for y in 0..<h { for x in 0..<w {\n        let inBar = y < bars.top || y >= h - bars.bottom || x < bars.left || x >= w - bars.right\n        b[y * strideB + x] = inBar ? barValue : fill\n    } }\n    return LumaPlane(bytes: b, width: w, height: h, strideBytes: strideB)!\n}\n\n// T15: letterbox detection, exact rect\nif let s = TapCropDetector.detect(luma(320, 180, bars: (20, 20, 0, 0))) {\n    check(\"T15-letterbox\", abs(s.rect.y - 20.0/180.0) < 1e-9 && s.rect.x == 0\n          && abs(s.rect.h - 140.0/180.0) < 1e-9 && s.rect.w == 1\n          && s.confidence > 0.5 && s.confidence <= 1)\n} else { check(\"T15-letterbox\", false) }\n// T16: pillarbox\nif let s = TapCropDetector.detect(luma(320, 180, bars: (0, 0, 30, 30))) {\n    check(\"T16-pillarbox\", abs(s.rect.x - 30.0/320.0) < 1e-9 && abs(s.rect.w - 260.0/320.0) < 1e-9 && s.rect.y == 0 && s.rect.h == 1)\n} else { check(\"T16-pillarbox\", false) }\n// T17: both bar kinds at once\nif let s = TapCropDetector.detect(luma(320, 180, bars: (10, 10, 16, 16))) {\n    check(\"T17-both\", abs(s.rect.x - 16.0/320.0) < 1e-9 && abs(s.rect.y - 10.0/180.0) < 1e-9)\n} else { check(\"T17-both\", false) }\n// T18: no bars -> nil\ncheck(\"T18-nobars\", TapCropDetector.detect(luma(320, 180)) == nil)\n// T19: fully dark frame is dark content, not a crop\ncheck(\"T19-darkframe\", TapCropDetector.detect(luma(320, 180, fill: 4)) == nil)\n// T20: bars beyond maxBarFraction refused\ncheck(\"T20-overcrop\", TapCropDetector.detect(luma(320, 180, bars: (85, 85, 0, 0))) == nil)\n// T21: 1px edge noise below minBarPx is not a bar\ncheck(\"T21-thinbar\", TapCropDetector.detect(luma(320, 180, bars: (1, 1, 1, 1))) == nil)\n// T22: padded stride gives the same result as packed\nlet packed = TapCropDetector.detect(luma(320, 180, bars: (20, 20, 0, 0)))\nlet padded = TapCropDetector.detect(luma(320, 180, strideExtra: 13, bars: (20, 20, 0, 0)))\ncheck(\"T22-stride\", packed?.rect == padded?.rect && padded != nil)\n// T23: invalid plane init refused\ncheck(\"T23-plane-init\", LumaPlane(bytes: [1, 2], width: 10, height: 10, strideBytes: 10) == nil\n      && LumaPlane(bytes: [UInt8](repeating: 0, count: 100), width: 10, height: 10, strideBytes: 9) == nil)\n// T24: pump - rate limit, agreement window, emit once, rect change resets\nvar pump = CropDetectionPump(minInterval: 1.0, requiredAgreement: 3)!\ncheck(\"T24-rate\", pump.poll(clock: 0.0, plane: luma(320, 180, bars: (20, 20, 0, 0))) == nil\n      && pump.poll(clock: 0.5, plane: luma(320, 180, bars: (20, 20, 0, 0))) == nil\n      && pump.counters.suppressedRate == 1)\n// clock 0.0 already counted as detection #1, so the third agreeing tick is clock 2.0\nlet e1 = pump.poll(clock: 1.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))\nlet e2 = pump.poll(clock: 2.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))\nlet e3 = pump.poll(clock: 3.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))\ncheck(\"T24-agreement\", e1 == nil && e2 != nil && pump.counters.emitted == 1)\ncheck(\"T24-stable-no-reemit\", e3 == nil && pump.counters.emitted == 1)\n// T25: changing bars need a fresh agreement run\nlet c1 = pump.poll(clock: 5.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))\nlet c2 = pump.poll(clock: 6.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))\nlet c3 = pump.poll(clock: 7.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))\ncheck(\"T25-change\", c1 == nil && c2 == nil && c3 != nil\n      && c3 != nil && abs(c3!.rect.y - 40.0/180.0) < 1e-9)\n// T26: bars gone -> clear to .full only after the agreement run\nlet n1 = pump.poll(clock: 8.0, plane: luma(320, 180))\nlet n2 = pump.poll(clock: 9.0, plane: luma(320, 180))\nlet n3 = pump.poll(clock: 10.0, plane: luma(320, 180))\ncheck(\"T26-clear\", n1 == nil && n2 == nil && n3?.rect == .full && pump.counters.emittedClears == 1)\n// T27: nil plane (tap empty this tick) neither emits nor disturbs pending\nvar pump2 = CropDetectionPump(minInterval: 0, requiredAgreement: 2)!\n_ = pump2.poll(clock: 0, plane: luma(320, 180, bars: (20, 20, 0, 0)))\n_ = pump2.poll(clock: 1, plane: nil)\nlet afterNil = pump2.poll(clock: 2, plane: luma(320, 180, bars: (20, 20, 0, 0)))\ncheck(\"T27-nil-plane\", afterNil != nil && pump2.counters.framesSeen == 2)\n// T28: invalid pump config refused\ncheck(\"T28-pump-init\", CropDetectionPump(minInterval: .nan) == nil\n      && CropDetectionPump(minInterval: 0, requiredAgreement: 0) == nil\n      && CropDetectionPump(minInterval: 0, requiredAgreement: 1, tolerance: 0) == nil)\n// T29: noisy bar above barMaxPeak is content, not a bar\nvar noisyBytes = [UInt8](repeating: 120, count: 320 * 180)\nfor y in 0..<20 { for x in 0..<320 { noisyBytes[y * 320 + x] = 4 } }\nfor y in 160..<180 { for x in 0..<320 { noisyBytes[y * 320 + x] = 4 } }\nfor y in 0..<20 { noisyBytes[y * 320] = 200 }                       // one bright pixel per bar row\nfor y in 160..<180 { noisyBytes[y * 320] = 200 }                     // same for the bottom bar\nlet noisyPlane = LumaPlane(bytes: noisyBytes, width: 320, height: 180, strideBytes: 320)!\ncheck(\"T29-noisy-bar\", TapCropDetector.detect(noisyPlane) == nil)\n\nprint(\"crop-tests: \\(passed) PASS, \\(failed) FAIL\")\nexit(failed == 0 ? 0 : 1)\n"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
    "command": "swift run crop-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T23:01:59.496693+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "crop-tests: 35 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/crop-tests/main.swift",
        "block": "rf0",
        "sha256": "d674aedd33dd5e64d7eb5b793de7802e3ac3a1f2609ea113ee20e598ad5f78b2"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "cd2b5a7bf5f65e832c5b79f7575e4f00f61b2df84eb167886a2a20e7286375b5",
    "last_5_lines": [
      "[69/72] Wrapping AST for crop-tests for debugging",
      "[70/72] Write Objects.LinkFileList",
      "[71/72] Linking crop-tests",
      "Build complete! (7.21s)",
      "crop-tests: 35 PASS, 0 FAIL"
    ],
    "receipt_sha256": "ae260b7c671ecde2427c4691c30ca17d0d1a3d7f734b87f99812a8c492d70f0d"
  }
}
```

## problem (what fails for the user)
auto-crop decisions come from TapCropDetector feeding CropStage; the detector exists but has no synthetic threshold atlas proving its black-bar/noise behavior, so a threshold regression ships as visible crop jitter or wrong crop on letterboxed content.

## reproducer
- repo: goreda/gorav @ 91a8b69abe9ce61e31188e3d426477a3f8528ede (branch main).
- real source: Sources/GorAVPlaybackCore/TapCropDetector.swift (sha256 648d03d4, 11343B) - the detector; Sources/GorAVPlaybackCore/CropStage.swift (sha256 f42207d0, 5541B) - the consuming stage; Sources/crop-tests/main.swift (same pin) - the existing 18-check suite.
- real test command: swift run crop-tests (18 PASS on Linux, Swift 6.1.2).

## expected behaviour
a per-frame detector + temporal stabilization fixture atlas: synthetic hard black bars, noisy near-black at stated sigma, letterbox+pillarbox combined, mid-stream crop animation, single-frame flashes that must NOT move the stabilized crop; expected crop rectangles per pattern with documented threshold parameters; detector output ABI pinned.

## exact call site and interface
TapCropDetector's detection entry and CropStage's crop consumption (pinned files); the atlas generator + expected tables + runner are the deliverable.

## pinned ABI decisions (integrator, 2026-11-15; thresholds/stabilization now pinned)
- detector ABI: public static func TapCropDetector.detect(_ p: LumaPlane, config: BorderScanConfig = .init()) -> CropSuggestion? (deterministic; nil on invalid config / dark frame / over-aggressive result)
- BorderScanConfig defaults (the pinned thresholds): barMaxLuma = 16, barMaxPeak = 48, minBarPx = 2, maxBarFraction = 0.45, minRemainFraction = 0.20, sampleStride = 8; config.isValid gate
- consumption/stabilization (CropController, same pin): autoThreshold in [0,1] (typed init? refuses out-of-range); ONE detection pass per frame; suggestion.confidence >= autoThreshold replaces the crop and returns .applied(CropGeometry); weaker = .noSuggestion (untouched); stale session = .refusedStaleSession; resolve failure = .rejected(CropStageError); CropStage.minimumEdgePx = 1
- NO temporal accumulation exists at the pin: a single-frame flash moves the crop only when its single suggestion clears autoThreshold. the atlas asserts exactly this single-pass rule (flash rows place confidence below/above the threshold), never an invented temporal filter.

## behaviour that must not change
the 18 existing crop checks stay green; the consuming player's crop convention (threshold/stabilization) is pinned below by the integrator (single-pass apply at confidence >= autoThreshold).

## acceptance test (from the product repo)
the atlas replays green against the pinned detector; one mutated expected rect fails; existing crop-tests stay green.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/TapCropDetector.swift (sha256 648d03d4, lines 80-120 of 235)
```swift id=source1
        return (n > 0 ? sum / n : 0, peak)
    }

    /// Detect letterbox/pillarbox bars. nil = no crop suggestion (no bars,
    /// dark frame, or a degenerate/over-aggressive result). Deterministic:
    /// same plane and config always give the same answer.
    public static func detect(_ p: LumaPlane, config: BorderScanConfig = BorderScanConfig())
        -> CropSuggestion? {
        guard config.isValid else { return nil }
        let step = config.sampleStride
        func isBarRow(_ y: Int) -> Bool {
            let s = scan(p, horizontal: true, index: y, step: step)
            return s.mean <= config.barMaxLuma && s.peak <= config.barMaxPeak
        }
        func isBarColumn(_ x: Int) -> Bool {
            let s = scan(p, horizontal: false, index: x, step: step)
            return s.mean <= config.barMaxLuma && s.peak <= config.barMaxPeak
        }
        var top = 0
        while top < p.height, isBarRow(top) { top += 1 }
        var bottom = 0
        while bottom < p.height - top, isBarRow(p.height - 1 - bottom) { bottom += 1 }
        var left = 0
        while left < p.width, isBarColumn(left) { left += 1 }
        var right = 0
        while right < p.width - left, isBarColumn(p.width - 1 - right) { right += 1 }
        if top < config.minBarPx { top = 0 }
        if bottom < config.minBarPx { bottom = 0 }
        if left < config.minBarPx { left = 0 }
        if right < config.minBarPx { right = 0 }
        guard top + bottom + left + right > 0 else { return nil }
        // Fraction guards: refuse to read a dark scene as bars, and refuse
        // to leave a degenerate sliver.
        if Double(top + bottom) > config.maxBarFraction * Double(p.height) { return nil }
        if Double(left + right) > config.maxBarFraction * Double(p.width) { return nil }
        let innerW = p.width - left - right, innerH = p.height - top - bottom
        guard innerW >= 1, innerH >= 1 else { return nil }
        if Double(innerW) < config.minRemainFraction * Double(p.width) { return nil }
        if Double(innerH) < config.minRemainFraction * Double(p.height) { return nil }
        // Dark-frame guard: an inner region that is itself bar-dark is a dark
        // frame, not a crop.
```

### Sources/GorAVPlaybackCore/CropStage.swift (sha256 f42207d0, lines 1-129 of 129)
```swift id=source2
import Foundation
import GorAVNativeProbeKit

// R8 (arch-195b): crop stage. Turns the ControlBus NormalizedRect crop state
// into concrete pixel geometry on a decoded frame, and defines the crop
// DETECTION seam (stub detector now; N10 letterbox/pillarbox analysis fills
// it later). The render side (sampling the cropped region) is presenter work.

public struct CropGeometry: Equatable, Sendable {
    /// Pixel-space source rectangle inside the decoded frame.
    public let x: Int, y: Int, width: Int, height: Int
    /// Aspect of the cropped region (width/height), always > 0.
    public let aspect: Double
    public init(x: Int, y: Int, width: Int, height: Int, aspect: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.aspect = aspect
    }
}

public enum CropStageError: Error, Equatable, Sendable, CustomStringConvertible {
    case frameTooSmall
    /// Resolved pixel rectangle is empty.
    case belowMinimum
    public var description: String {
        switch self {
        case .frameTooSmall: return "frameTooSmall"
        case .belowMinimum: return "belowMinimum"
        }
    }
}

public enum CropStage {
    public static let minimumEdgePx = 1

    /// Resolve a validated NormalizedRect against a frame. Rounding is
    /// deterministic: origin floors, extents ceil, then clamp to the frame.
    /// The result always lies fully inside the frame.
    public static func resolve(_ rect: NormalizedRect,
                               frameWidth: Int, frameHeight: Int)
        -> Result<CropGeometry, CropStageError> {
        guard frameWidth >= minimumEdgePx, frameHeight >= minimumEdgePx else {
            return .failure(.frameTooSmall)
        }
        func pixel(_ value: Double, limit: Int, rounding: FloatingPointRoundingRule) -> Int {
            let rounded = value.rounded(rounding)
            // Clamp before conversion: Double(Int.max) rounds outside Int's range.
            if rounded >= Double(limit) { return limit }
            return Int(max(0, rounded))
        }
        let x = pixel(rect.x * Double(frameWidth), limit: frameWidth - 1, rounding: .down)
        let y = pixel(rect.y * Double(frameHeight), limit: frameHeight - 1, rounding: .down)
        let right = pixel((rect.x + rect.w) * Double(frameWidth), limit: frameWidth, rounding: .up)
        let bottom = pixel((rect.y + rect.h) * Double(frameHeight), limit: frameHeight, rounding: .up)
        let w = right - x, h = bottom - y
        guard w >= minimumEdgePx, h >= minimumEdgePx else { return .failure(.belowMinimum) }
        return .success(CropGeometry(x: x, y: y, width: w, height: h,
                                     aspect: Double(w) / Double(h)))
    }
}

/// A detector's suggestion for one frame. `confidence` in (0, 1].
public struct CropSuggestion: Equatable, Sendable {
    public let rect: NormalizedRect
    public let confidence: Double
    public init?(rect: NormalizedRect, confidence: Double) {
        guard confidence.isFinite, confidence > 0, confidence <= 1 else { return nil }
        self.rect = rect; self.confidence = confidence
    }
}

/// The N10 seam. Implementations must be cheap enough for the decode cadence
/// and must never retain pixel bytes.
public protocol CropDetecting: Sendable {
    func suggest(frame: NativeFrame) -> CropSuggestion?
}

/// Accepted stub: never suggests. Real letterbox/pillarbox analysis is N10.
public struct NullCropDetector: CropDetecting, Sendable {
    public init() {}
    public func suggest(frame: NativeFrame) -> CropSuggestion? { nil }
}

public struct CropController: Sendable {
    public enum AutoVerdict: Equatable, Sendable {
        case applied(CropGeometry)
        case noSuggestion
        case rejected(CropStageError)
        case refusedStaleSession
    }

    public private(set) var current: NormalizedRect = .full
    public let session: UInt64
    public let detector: any CropDetecting
    /// Auto-suggestions apply only at or above this confidence.
    public let autoThreshold: Double

    public init?(session: UInt64, detector: any CropDetecting = NullCropDetector(),
                autoThreshold: Double) {
        guard autoThreshold.isFinite, (0...1).contains(autoThreshold) else { return nil }
        self.session = session
        self.detector = detector
        self.autoThreshold = autoThreshold
    }

    public mutating func set(_ rect: NormalizedRect) { current = rect }
    public mutating func clear() { current = .full }

    /// Resolve the current crop against a frame of this session.
    public func geometry(frame: NativeFrame) -> Result<CropGeometry, CropStageError>? {
        guard frame.session == session else { return nil }
        return CropStage.resolve(current, frameWidth: frame.width, frameHeight: frame.height)
    }

    /// One detection pass. A suggestion at/above the threshold replaces the
    /// current crop and returns its resolved geometry; anything weaker leaves
    /// the crop untouched.
    public mutating func autoApply(frame: NativeFrame) -> AutoVerdict {
        guard frame.session == session else { return .refusedStaleSession }
        guard let s = detector.suggest(frame: frame), s.confidence >= autoThreshold else {
            return .noSuggestion
        }
        switch CropStage.resolve(s.rect, frameWidth: frame.width, frameHeight: frame.height) {
        case .success(let g):
            current = s.rect
            return .applied(g)
        case .failure(let e):
            return .rejected(e)
        }
    }
}
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"pattern":"hard-black-bars","plane":{"w":1920,"h":1080,"topBarPx":120,"bottomBarPx":120},"config":"defaults","expect":{"rect":{"x":0,"y":120,"w":1920,"h":840},"confidence":">=autoThreshold"}},
 {"pattern":"near-black-noise","sigma":2.0,"config":"defaults","expect":"noSuggestion"}]
```


```text id=rf0
import Foundation
import GorAVPlaybackCore
import GorAVNativeProbeKit

// Witness for the R8 crop stage: geometry resolution, bounds, minimum-size
// refusal, detector seam (stub + scripted), confidence threshold, session
// fencing.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func frame(_ session: UInt64, _ w: Int, _ h: Int) -> NativeFrame {
    NativeFrame(session: session, handle: 1, pts: 0, duration: 33_333,
                width: w, height: h, pixelFormatName: "yuv420p", isKeyFrame: true)
}

// T1: full frame on 1920x1080
switch CropStage.resolve(.full, frameWidth: 1920, frameHeight: 1080) {
case .success(let g):
    check("T1-full-geom", g == CropGeometry(x: 0, y: 0, width: 1920, height: 1080, aspect: Double(1920)/1080))
case .failure(let e):
    check("T1-full-geom \(e)", false)
}

// T2: centered half crop
let half = NormalizedRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5)!
switch CropStage.resolve(half, frameWidth: 1920, frameHeight: 1080) {
case .success(let g):
    check("T2-half-geom", g.x == 480 && g.y == 270 && g.width == 960 && g.height == 540)
    check("T2-half-aspect", abs(g.aspect - 16.0/9.0) < 0.01)
case .failure: check("T2-half-geom", false)
}

// T3: small valid crops are retained
let tiny = NormalizedRect(x: 0, y: 0, w: 0.005, h: 0.01)!
check("T3-small-valid", CropStage.resolve(tiny, frameWidth: 1920, frameHeight: 1080) != .failure(.belowMinimum))

// T4: tiny frame refused
check("T4-small-frame", CropStage.resolve(.full, frameWidth: 0, frameHeight: 8) == .failure(.frameTooSmall))

// T5: detector stub never suggests; autoApply leaves crop at full
var c5 = CropController(session: 7, autoThreshold: 0.9)!
check("T5-stub-no-suggestion", c5.autoApply(frame: frame(7, 1920, 1080)) == .noSuggestion)
check("T5-still-full", c5.current == .full)

// T6: scripted detector above threshold applies
struct Scripted: CropDetecting {
    let s: CropSuggestion?
    func suggest(frame: NativeFrame) -> CropSuggestion? { s }
}
let sg = CropSuggestion(rect: half, confidence: 0.95)!
var c6 = CropController(session: 7, detector: Scripted(s: sg), autoThreshold: 0.9)!
if case .applied(let g) = c6.autoApply(frame: frame(7, 1920, 1080)) {
    check("T6-applied", g.width == 960 && c6.current == half)
} else { check("T6-applied", false) }

// T7: below threshold leaves crop untouched
let weak = CropSuggestion(rect: half, confidence: 0.5)!
var c7 = CropController(session: 7, detector: Scripted(s: weak), autoThreshold: 0.9)!
check("T7-below-threshold", c7.autoApply(frame: frame(7, 1920, 1080)) == .noSuggestion && c7.current == .full)

// T8: small suggestion stays valid
let badSug = CropSuggestion(rect: tiny, confidence: 0.99)!
var c8 = CropController(session: 7, detector: Scripted(s: badSug), autoThreshold: 0.9)!
check("T8-small-applied", c8.autoApply(frame: frame(7, 1920, 1080)) == .applied(CropGeometry(x: 0, y: 0, width: 10, height: 11, aspect: Double(10)/11)) && c8.current == tiny)

// T9: session fencing on both paths
var c9 = CropController(session: 7, autoThreshold: 0.9)!
check("T9-geometry-fenced", c9.geometry(frame: frame(8, 1920, 1080)) == nil)
check("T9-auto-fenced", c9.autoApply(frame: frame(8, 1920, 1080)) == .refusedStaleSession)

// T10: manual set/clear + geometry path
c9.set(half)
if let r = c9.geometry(frame: frame(7, 1920, 1080)), case .success(let g) = r {
    check("T10-manual", g.width == 960)
} else { check("T10-manual", false) }
c9.clear()
check("T10-clear", c9.current == .full)

// T11: invalid suggestion confidence cannot be constructed
check("T11-confidence-guard", CropSuggestion(rect: half, confidence: 0) == nil
      && CropSuggestion(rect: half, confidence: 1.5) == nil
      && CropSuggestion(rect: half, confidence: .nan) == nil)

check("T12-invalid-threshold-refused", CropController(session: 7, autoThreshold: .nan) == nil && CropController(session: 7, autoThreshold: -0.1) == nil)
if case .success(let g) = CropStage.resolve(.full, frameWidth: Int.max, frameHeight: Int.max) {
    check("T13-huge-frame-no-overflow", g.width == Int.max && g.height == Int.max)
} else { check("T13-huge-frame-no-overflow", false) }
let fractional = NormalizedRect(x: 0, y: 0, w: 0.101, h: 0.101)!
if case .success(let g) = CropStage.resolve(fractional, frameWidth: 100, frameHeight: 100) {
    check("T14-ceil-edge", g.width == 11 && g.height == 11)
} else { check("T14-ceil-edge", false) }
// R8 (arch-195l): tap-consuming crop detection (TapCropDetector + pump).
// Luma builder: stride padded with 0xFF sentinels; padding must never be read.
func luma(_ w: Int, _ h: Int, strideExtra: Int = 0, fill: UInt8 = 120,
          bars: (top: Int, bottom: Int, left: Int, right: Int) = (0, 0, 0, 0),
          barValue: UInt8 = 4) -> LumaPlane {
    let strideB = w + strideExtra
    var b = [UInt8](repeating: 0xFF, count: strideB * h)
    for y in 0..<h { for x in 0..<w {
        let inBar = y < bars.top || y >= h - bars.bottom || x < bars.left || x >= w - bars.right
        b[y * strideB + x] = inBar ? barValue : fill
    } }
    return LumaPlane(bytes: b, width: w, height: h, strideBytes: strideB)!
}

// T15: letterbox detection, exact rect
if let s = TapCropDetector.detect(luma(320, 180, bars: (20, 20, 0, 0))) {
    check("T15-letterbox", abs(s.rect.y - 20.0/180.0) < 1e-9 && s.rect.x == 0
          && abs(s.rect.h - 140.0/180.0) < 1e-9 && s.rect.w == 1
          && s.confidence > 0.5 && s.confidence <= 1)
} else { check("T15-letterbox", false) }
// T16: pillarbox
if let s = TapCropDetector.detect(luma(320, 180, bars: (0, 0, 30, 30))) {
    check("T16-pillarbox", abs(s.rect.x - 30.0/320.0) < 1e-9 && abs(s.rect.w - 260.0/320.0) < 1e-9 && s.rect.y == 0 && s.rect.h == 1)
} else { check("T16-pillarbox", false) }
// T17: both bar kinds at once
if let s = TapCropDetector.detect(luma(320, 180, bars: (10, 10, 16, 16))) {
    check("T17-both", abs(s.rect.x - 16.0/320.0) < 1e-9 && abs(s.rect.y - 10.0/180.0) < 1e-9)
} else { check("T17-both", false) }
// T18: no bars -> nil
check("T18-nobars", TapCropDetector.detect(luma(320, 180)) == nil)
// T19: fully dark frame is dark content, not a crop
check("T19-darkframe", TapCropDetector.detect(luma(320, 180, fill: 4)) == nil)
// T20: bars beyond maxBarFraction refused
check("T20-overcrop", TapCropDetector.detect(luma(320, 180, bars: (85, 85, 0, 0))) == nil)
// T21: 1px edge noise below minBarPx is not a bar
check("T21-thinbar", TapCropDetector.detect(luma(320, 180, bars: (1, 1, 1, 1))) == nil)
// T22: padded stride gives the same result as packed
let packed = TapCropDetector.detect(luma(320, 180, bars: (20, 20, 0, 0)))
let padded = TapCropDetector.detect(luma(320, 180, strideExtra: 13, bars: (20, 20, 0, 0)))
check("T22-stride", packed?.rect == padded?.rect && padded != nil)
// T23: invalid plane init refused
check("T23-plane-init", LumaPlane(bytes: [1, 2], width: 10, height: 10, strideBytes: 10) == nil
      && LumaPlane(bytes: [UInt8](repeating: 0, count: 100), width: 10, height: 10, strideBytes: 9) == nil)
// T24: pump - rate limit, agreement window, emit once, rect change resets
var pump = CropDetectionPump(minInterval: 1.0, requiredAgreement: 3)!
check("T24-rate", pump.poll(clock: 0.0, plane: luma(320, 180, bars: (20, 20, 0, 0))) == nil
      && pump.poll(clock: 0.5, plane: luma(320, 180, bars: (20, 20, 0, 0))) == nil
      && pump.counters.suppressedRate == 1)
// clock 0.0 already counted as detection #1, so the third agreeing tick is clock 2.0
let e1 = pump.poll(clock: 1.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
let e2 = pump.poll(clock: 2.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
let e3 = pump.poll(clock: 3.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
check("T24-agreement", e1 == nil && e2 != nil && pump.counters.emitted == 1)
check("T24-stable-no-reemit", e3 == nil && pump.counters.emitted == 1)
// T25: changing bars need a fresh agreement run
let c1 = pump.poll(clock: 5.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))
let c2 = pump.poll(clock: 6.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))
let c3 = pump.poll(clock: 7.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))
check("T25-change", c1 == nil && c2 == nil && c3 != nil
      && c3 != nil && abs(c3!.rect.y - 40.0/180.0) < 1e-9)
// T26: bars gone -> clear to .full only after the agreement run
let n1 = pump.poll(clock: 8.0, plane: luma(320, 180))
let n2 = pump.poll(clock: 9.0, plane: luma(320, 180))
let n3 = pump.poll(clock: 10.0, plane: luma(320, 180))
check("T26-clear", n1 == nil && n2 == nil && n3?.rect == .full && pump.counters.emittedClears == 1)
// T27: nil plane (tap empty this tick) neither emits nor disturbs pending
var pump2 = CropDetectionPump(minInterval: 0, requiredAgreement: 2)!
_ = pump2.poll(clock: 0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
_ = pump2.poll(clock: 1, plane: nil)
let afterNil = pump2.poll(clock: 2, plane: luma(320, 180, bars: (20, 20, 0, 0)))
check("T27-nil-plane", afterNil != nil && pump2.counters.framesSeen == 2)
// T28: invalid pump config refused
check("T28-pump-init", CropDetectionPump(minInterval: .nan) == nil
      && CropDetectionPump(minInterval: 0, requiredAgreement: 0) == nil
      && CropDetectionPump(minInterval: 0, requiredAgreement: 1, tolerance: 0) == nil)
// T29: noisy bar above barMaxPeak is content, not a bar
var noisyBytes = [UInt8](repeating: 120, count: 320 * 180)
for y in 0..<20 { for x in 0..<320 { noisyBytes[y * 320 + x] = 4 } }
for y in 160..<180 { for x in 0..<320 { noisyBytes[y * 320 + x] = 4 } }
for y in 0..<20 { noisyBytes[y * 320] = 200 }                       // one bright pixel per bar row
for y in 160..<180 { noisyBytes[y * 320] = 200 }                     // same for the bottom bar
let noisyPlane = LumaPlane(bytes: noisyBytes, width: 320, height: 180, strideBytes: 320)!
check("T29-noisy-bar", TapCropDetector.detect(noisyPlane) == nil)

print("crop-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-7wtqj2as/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-7wtqj2as/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
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
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-7wtqj2as/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Emitting module crop_tests
[68/71] Compiling crop_tests main.swift
[69/72] Wrapping AST for crop-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking crop-tests
Build complete! (7.21s)
crop-tests: 35 PASS, 0 FAIL
```
