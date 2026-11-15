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
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
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
  "branch": "ohal/gorav",
  "paths": [
   "kits/crop-atlas/",
   "Sources/crop-tests/main.swift"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
auto-crop decisions come from TapCropDetector feeding CropStage; the detector exists but has no synthetic threshold atlas proving its black-bar/noise behavior, so a threshold regression ships as visible crop jitter or wrong crop on letterboxed content.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
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
