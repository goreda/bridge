# W-gdb-198y-in2tinct-02
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/CropStage.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-02.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-02",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/CropStage.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/CropStage.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: CropGeometry, CropStageError, CropStage, resolve, pixel, CropSuggestion, CropDetecting, suggest, NullCropDetector, suggest, CropController, AutoVerdict",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-02.py",
    "callee": "Sources/GorAVPlaybackCore/CropStage.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-02.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-02.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-02.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:16.269586+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CropStage.swift",
        "block": "source1",
        "sha256": "f42207d0d730a7469a4cbf3ea7f2a6d2423301ee49c96df733fcc73b319362bb"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-02.py",
        "block": "fixtures1",
        "sha256": "7a22baf9eef54ea7c1b41a72457cd63821c05ca21a7a7a8f0ce0eb812b4efdc0"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7c63ed0e61a3dfd5f4cd1a7ae8261aa3211e18334ecb3b71a11fdeea738df896",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-02: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "18d820024688e4182dbab77c3fd9b4f2f84769ad5bb379c263235534834f7530"
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

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/CropStage.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='f42207d0d730a7469a4cbf3ea7f2a6d2423301ee49c96df733fcc73b319362bb', 'pinned source changed: rebase and review, never bless silently'
for token in ['CropGeometry', 'CropStageError', 'CropStage', 'resolve', 'pixel', 'CropSuggestion', 'CropDetecting', 'suggest', 'NullCropDetector', 'suggest', 'CropController', 'AutoVerdict']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='f42207d0d730a7469a4cbf3ea7f2a6d2423301ee49c96df733fcc73b319362bb'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-02: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-02: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
