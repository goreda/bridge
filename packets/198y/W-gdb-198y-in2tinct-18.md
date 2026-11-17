# W-gdb-198y-in2tinct-18
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/ColorStage.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-18.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-18",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/ColorStage.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: SourceTRC, ToneMapCurve, GamutMode, SourceSignal, DisplayTarget, ToneMapPlan, ColorStage, defaultPeak, plan",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-18.py",
    "callee": "Sources/GorAVPlaybackCore/ColorStage.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-18.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-18.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-18.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:20.693434+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
        "block": "source1",
        "sha256": "daf6de8af2d598408d621bb687b542d47583dc458f9a462ed4648720193be081"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-18.py",
        "block": "fixtures1",
        "sha256": "fa3a29cf9c00cae7e9b027164fcd964a8402f520b0307d180df76d433b10e4ea"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "97104ac1c406aba2bd78f0a14c7f78807e98ab01b851fa3b2060b6a621cfdce1",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-18: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "e3e7af60910a40e9a1fa37f74dbe4592f2de63971998b980db73da0fe2214f21"
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
p=ROOT/'Sources/GorAVPlaybackCore/ColorStage.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='daf6de8af2d598408d621bb687b542d47583dc458f9a462ed4648720193be081', 'pinned source changed: rebase and review, never bless silently'
for token in ['SourceTRC', 'ToneMapCurve', 'GamutMode', 'SourceSignal', 'DisplayTarget', 'ToneMapPlan', 'ColorStage', 'defaultPeak', 'plan']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='daf6de8af2d598408d621bb687b542d47583dc458f9a462ed4648720193be081'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-18: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-18: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
