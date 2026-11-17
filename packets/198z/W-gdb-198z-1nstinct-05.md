# W-gdb-198z-1nstinct-05 - Color/effect parameters
state: OPEN / unclaimed
lab: 1nstinct

Range-checked brightness/contrast/saturation/gamma plus receipt. Grain and sharpness explicitly unsupported unless a real render stage applies them. Do not claim image application from values alone.

Required acceptance: Sources/color-stage-tests/main.swift and Sources/untagged-color-tests/main.swift: identity neutrality and range preservation; actual image delta stays native NOT_RUN unless executed.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-05",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Color/effect parameters; Range-checked brightness/contrast/saturation/gamma plus receipt. Grain and sharpness explicitly unsupported unless a real render stage applies them. Do not claim image application from values alone.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Sources/color-stage-tests/main.swift and Sources/untagged-color-tests/main.swift: identity neutrality and range preservation; actual image delta stays native NOT_RUN unless executed.",
    "callee": "Sources/GorAVPlaybackCore/ColorStage.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-05.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Sources/color-stage-tests/main.swift and Sources/untagged-color-tests/main.swift: identity neutrality and range preservation; actual image delta stays native NOT_RUN unless executed.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-198z-1nstinct-05",
    "paths": [
      "Sources/GorAVPlaybackCore/ColorStage.swift",
      "Tests/Architecture/198z/W-gdb-198z-1nstinct-05.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-05.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.407048+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
        "block": "source1",
        "sha256": "daf6de8af2d598408d621bb687b542d47583dc458f9a462ed4648720193be081"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-1nstinct-05.py",
        "block": "fixtures1",
        "sha256": "9413e9e359dc83db53210bcbb064aa3755003b1a75d90c1d336789ac17406e8f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "8add006d42ac9d4906e23d4b0155613e2f49d7f3b70162b642bd020a2144aad1",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-05; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "7d60680f48b63e85300fa2772d731f0d6727a7d61a3a779d91deab78b9001fcb"
  }
}
```

```swift id=source1
import Foundation

// R9 (arch-195b): unconnected color policy only, not a pixel stage.
// The softwareFallback flag requests a path; it proves no implementation.
// This does not reproduce the shipped DV auto/PQ profile or bt.1886 target.
// Color stage policy. Given a decoded source signal and a
// display target, produce a typed ToneMapPlan: which curve, which peaks,
// saturation, gamut mode, and whether the software fallback path is required.
// Pixel mapping itself is presenter/GPU work; DV RPU parsing already lives in
// GorAVDolbyVision - this stage consumes its verdict, it does not reparse.

public enum SourceTRC: String, Equatable, Sendable {
    case bt709, bt2020PQ, hlg, dolbyVision, unknown
    public var isHDR: Bool { self == .bt2020PQ || self == .hlg || self == .dolbyVision }
}

public enum ToneMapCurve: String, Equatable, Sendable, CaseIterable {
    case none, clip, mobius, hable, reinhard
}

public enum GamutMode: String, Equatable, Sendable {
    case perceptual, relativeColorimetric
}

public struct SourceSignal: Equatable, Sendable {
    public let trc: SourceTRC
    /// Mastering peak luminance in nits when signalled (HDR10 static metadata);
    /// nil means unsignalled - the stage uses the per-TRC default.
    public let sourcePeakNits: Double?
    public init(trc: SourceTRC, sourcePeakNits: Double? = nil) {
        self.trc = trc
        self.sourcePeakNits = sourcePeakNits.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

public struct DisplayTarget: Equatable, Sendable {
    public let targetTRC: SourceTRC
    /// Display peak in nits; EDR headroom is targetPeak/100 for SDR targets.
    public let peakNits: Double
    /// 0...2, 1 = unchanged.
    public let saturation: Double
    public let gamut: GamutMode
    /// Explicit curve override; nil = policy-selected.
    public let curveOverride: ToneMapCurve?
    public init?(targetTRC: SourceTRC, peakNits: Double, saturation: Double = 1.0,
                 gamut: GamutMode = .perceptual, curveOverride: ToneMapCurve? = nil) {
        guard peakNits.isFinite, peakNits > 0,
              saturation.isFinite, (0...2).contains(saturation) else { return nil }
        self.targetTRC = targetTRC; self.peakNits = peakNits
        self.saturation = saturation; self.gamut = gamut
        self.curveOverride = curveOverride
    }
    /// Reference SDR display.
    public static let sdr100 = DisplayTarget(targetTRC: .bt709, peakNits: 100)!
}

public struct ToneMapPlan: Equatable, Sendable {
    public let curve: ToneMapCurve
    public let sourcePeakNits: Double
    public let targetPeakNits: Double
    public let saturation: Double
    public let gamut: GamutMode
    /// True when the plan requires the software tone-map path (no hardware
    /// tone mapper for this pairing, e.g. off-Mac, or DV without HW support).
    public let softwareFallback: Bool
    /// Machine-checkable decision record, one entry per policy rule applied.
    public let receipts: [String]
}

public enum ColorStage {
    /// Default peak per TRC when the source does not signal one.
    public static func defaultPeak(_ trc: SourceTRC) -> Double {
        switch trc {
        case .bt709, .unknown: return 100
        case .hlg: return 1000
        case .bt2020PQ: return 1000
        case .dolbyVision: return 1000
        }
    }

    public static func plan(source: SourceSignal, target: DisplayTarget,
                            hardwareToneMapper: Bool) -> ToneMapPlan {
        var receipts: [String] = []
        let srcPeak = source.sourcePeakNits ?? defaultPeak(source.trc)
        if source.sourcePeakNits == nil { receipts.append("src-peak-default:\(source.trc.rawValue):\(Int(srcPeak))") }

        var curve: ToneMapCurve
        if let o = target.curveOverride {
            curve = o
            receipts.append("curve-override:\(o.rawValue)")
        } else if !source.trc.isHDR && !target.targetTRC.isHDR {
            curve = .none
            receipts.append("sdr-to-sdr:no-tone-map")
        } else if source.trc.isHDR && !target.targetTRC.isHDR {
            curve = .mobius
            receipts.append("hdr-to-sdr:mobius-default")
        } else if !source.trc.isHDR && target.targetTRC.isHDR {
            curve = .none
            receipts.append("sdr-to-hdr:passthrough-no-inverse-tone-map")
        } else {
            curve = srcPeak > target.peakNits ? .mobius : .none
            receipts.append("hdr-to-hdr:\(curve == .none ? "peak-fits" : "mobius-down-map")")
        }

        var software = false
        if curve != .none && !hardwareToneMapper {
            software = true
            receipts.append("no-hw-tone-mapper:software-fallback")
        }
        if source.trc == .dolbyVision && !hardwareToneMapper {
            software = true
            receipts.append("dv-without-hw:software-fallback")
        }

        return ToneMapPlan(curve: curve, sourcePeakNits: srcPeak,
                           targetPeakNits: target.peakNits,
                           saturation: target.saturation, gamut: target.gamut,
                           softwareFallback: software, receipts: receipts)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/GorAVPlaybackCore/ColorStage.swift').read_bytes()).hexdigest()=='daf6de8af2d598408d621bb687b542d47583dc458f9a462ed4648720193be081'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-05; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-05; baseline only, product change and semantic test still required
```

secret scan: clean
