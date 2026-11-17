# W-gdb-198z-1nstinct-04 - Crop/aspect output
state: OPEN / unclaimed
lab: 1nstinct

Source-normalized crop/aspect, explicit refusals, effective geometry separate from coded size. Preserve current code paths.

Required acceptance: Sources/crop-tests/main.swift: portrait, SAR, rotation, odd dimensions, exact corners and rectangles.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-04",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/CropStage.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVPlaybackCore/StageGeometry.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "Crop/aspect output; Source-normalized crop/aspect, explicit refusals, effective geometry separate from coded size. Preserve current code paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Sources/crop-tests/main.swift: portrait, SAR, rotation, odd dimensions, exact corners and rectangles.",
    "callee": "Sources/GorAVPlaybackCore/CropStage.swift, Sources/GorAVPlaybackCore/StageGeometry.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-04.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Sources/crop-tests/main.swift: portrait, SAR, rotation, odd dimensions, exact corners and rectangles.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-198z-1nstinct-04",
    "paths": [
      "Sources/GorAVPlaybackCore/CropStage.swift",
      "Sources/GorAVPlaybackCore/StageGeometry.swift",
      "Tests/Architecture/198z/W-gdb-198z-1nstinct-04.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-04.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.387375+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CropStage.swift",
        "block": "source1",
        "sha256": "f42207d0d730a7469a4cbf3ea7f2a6d2423301ee49c96df733fcc73b319362bb"
      },
      {
        "path": "Sources/GorAVPlaybackCore/StageGeometry.swift",
        "block": "source2",
        "sha256": "c0ea88134197de55ca8fae38b691df90bb70dc65c9d128cfe9c8a640c98457df"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-1nstinct-04.py",
        "block": "fixtures1",
        "sha256": "7d750b18a461392eb579c992a865a9428028de3f07ebfcc7564038a8f7b53d69"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "1de2c92517ec72cad1d748de5ec52f4f5e4108b2d69a9c9b40d38c450fe4be42",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-04; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "5714586fa71e03bf635ff207d1af90c190b14fadc1a5870c73caee2626070371"
  }
}
```

```swift id=source1
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

```swift id=source2
import Foundation

/// Screen-space output geometry shared by native stage and presenter.
/// UV crop does not change pan units. Unset means aspect-fit, never stretch.
public enum StageGeometry {
    public static func quad(uniforms u: FrameUniforms, drawableWidth: Int, drawableHeight: Int) -> [Float]? {
        guard FrameUniformABI.valid(u), drawableWidth > 0, drawableHeight > 0,
              let transform = HostTransform(panX: Double(u.panX), panY: Double(u.panY),
                                            log2Zoom: Double(u.log2Zoom)),
              let fit = FrameUniformABI.FitID(rawValue: u.fitModeID) else { return nil }
        let w = Double(u.frameWidth) * Double(u.cropW)
        let h = Double(u.frameHeight) * Double(u.cropH)
        let dw = Double(drawableWidth), dh = Double(drawableHeight)
        let scale: Double
        switch fit {
        case .unset, .fit: scale = min(dw / w, dh / h)
        case .fill: scale = max(dw / w, dh / h)
        case .stretch: scale = 1
        }
        let sx = fit == .stretch ? 1 : w * scale / dw
        let sy = fit == .stretch ? 1 : h * scale / dh
        var q = hostTransformQuad(scaleX: sx, scaleY: sy, transform)
        let x = u.cropX, y = u.cropY, r = x + u.cropW, b = y + u.cropH
        q[2] = x; q[3] = y; q[6] = x; q[7] = b
        q[10] = r; q[11] = y; q[14] = r; q[15] = b
        return q.allSatisfy(\.isFinite) ? q : nil
    }
}

/// These flags describe intent, not an implemented color transform.
public enum StageColorRefusal: Error, Equatable, Sendable {
    case invalidPayload
    case p12PixelMappingUnavailable
    case gamutConversionUnavailable
    case softwareToneMapperUnavailable
}
public enum StageColorAdmission {
    /// An off/identity plan must preserve extended values, including HDR.
    /// Bit 1 requests relative-colorimetric gamut conversion, not a no-op.
    /// Bit 0 requests an actual software mapper, not a Metal fallback.
    public static func identity(_ u: FrameUniforms) -> Result<Void, StageColorRefusal> {
        guard FrameUniformABI.valid(u) else { return .failure(.invalidPayload) }
        if u.flags & 1 != 0 { return .failure(.softwareToneMapperUnavailable) }
        if u.flags & 2 != 0 { return .failure(.gamutConversionUnavailable) }
        guard u.toneCurveID == 0, u.saturation == 1 else { return .failure(.p12PixelMappingUnavailable) }
        return .success(())
    }
}

/// P12 source policy, not a pixel implementation. Source: shipped mpv.conf
/// 975da1d4, SHA256 b7f7e571f43c67cbda1439ee2c5bd713825a9011b1c67b3901ac6cd587d397cd.
/// No transition/knee or target peak is invented from a profile name.
public enum P12Profile: Equatable, Sendable {
    case sdr, hdr, dolbyVision
    public var toneMapping: String { switch self { case .sdr: return "inherited"; case .hdr: return "mobius"; case .dolbyVision: return "auto" } }
    public var targetTransfer: String? { switch self { case .sdr: return nil; case .hdr: return "bt.1886"; case .dolbyVision: return "pq" } }
    public var computeDynamicPeak: Bool { false }
    public var saturationAdjustment: Int? { self == .hdr ? -10 : nil }
    public var gamutMapping: String? { self == .hdr ? "perceptual" : nil }
    /// DV ICC is expressly excluded by P12 until verified.
    public var requiresICC: Bool { self == .hdr }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/GorAVPlaybackCore/CropStage.swift').read_bytes()).hexdigest()=='f42207d0d730a7469a4cbf3ea7f2a6d2423301ee49c96df733fcc73b319362bb'
assert hashlib.sha256((ROOT/'Sources/GorAVPlaybackCore/StageGeometry.swift').read_bytes()).hexdigest()=='c0ea88134197de55ca8fae38b691df90bb70dc65c9d128cfe9c8a640c98457df'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-04; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-04; baseline only, product change and semantic test still required
```

secret scan: clean
