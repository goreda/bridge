# W-gdb-042 195b-N7 tone map / color pass: consuming pin
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-042

```packet-json
{
 "packet_id": "W-gdb-042",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
   "excerpt_block": "source2"
  },
  {
   "path": "Sources/GorAVPlaybackCore/ColorStage.swift",
   "excerpt_block": "source3"
  }
 ],
 "interface": {
  "signatures": "pinned ColorStage surface (excerpts): SourceTRC/ToneMapCurve/GamutMode enums, SourceSignal, DisplayTarget guarded init, ToneMapPlan; module output -> ToneMapPlan-compatible values",
  "types": "SourceSignal { trc: SourceTRC, sourcePeakNits: Double? }; DisplayTarget { targetTRC, peakNits, saturation 0...2, gamut, curveOverride }; ToneMapPlan { curve, sourcePeakNits, targetPeakNits }",
  "ownership_lifetime": "module holds no display state; plan values are immutable value types",
  "caller": "ColorStage consumer (presenter tone-map policy)",
  "callee": "the lab color-pass module + kits/n7-color-pin golden matrix checker"
 },
 "test": {
  "command": "python3 kits/n7-color-pin/check.py kits/n7-color-pin/fixtures.json",
  "expected": "exit 0; stdout 'n7-color-pin: 4/4 rows PASS'; guard rows (peakNits 0/NaN, saturation 2.5) yield nil, never clamped; one mutated expected row fails",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVPlaybackCore/",
   "kits/n7-color-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the tone-map/color pass (195b-N7) needs the pinned color-stage contract: without real parameter domains a lab module ships luminance/transfer/gamut guesses that render wrong colors.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0277/N7; the lab module implements against the pinned interface below.

## expected behaviour
a color-pass module producing a ToneMapPlan-compatible output for the pinned ColorStage types: SourceTRC (isHDR rule pinned), ToneMapCurve (none/clip/mobius/hable/reinhard), GamutMode (perceptual/relativeColorimetric), SourceSignal { trc, sourcePeakNits? }, DisplayTarget { targetTRC, peakNits>0 finite, saturation 0...2, gamut, curveOverride? } with its pinned init guards. Dual-output (C + MSL) generation is allowed; the C reference must replay the golden matrix. Luminance units are nits (DisplayTarget.peakNits; EDR headroom = targetPeak/100 for SDR per the pinned comment); transfer/range follow SourceTRC; curve selection follows the pinned ColorStage.plan policy formula exactly (excerpt source3): sdr-to-sdr -> .none; hdr-to-sdr -> .mobius; sdr-to-hdr -> .none (passthrough, no inverse tone map); hdr-to-hdr -> .mobius iff sourcePeak > targetPeak else .none; an explicit curveOverride wins first. defaultPeak per TRC: bt709/fallback 100, hlg/bt2020PQ/dolbyVision 1000. softwareFallback per the pinned rules; every rule application appends its pinned receipt string.

## exact call site and interface
ColorStage.swift (pinned excerpt): the module's plan must construct DisplayTarget only via its guarded init and name ToneMapCurve/GamutMode by the pinned cases; delivery rides as Sources/GorAVPlaybackCore/ color-pass addition + kits/n7-color-pin/ checker.

## behaviour that must not change
DisplayTarget init guards (finite positive peak, saturation range) and the sdr100 reference target stay as pinned; SourceTRC.isHDR rule untouched.

## acceptance test (from the product repo)
python3 kits/n7-color-pin/check.py kits/n7-color-pin/fixtures.json exits 0; each matrix row matches its golden curve/gamut/guard outcome; one mutated expected row fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/ColorStage.swift (sha256 daf6de8a, lines 1-12 of 120)
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
```
### Sources/GorAVPlaybackCore/ColorStage.swift (sha256 daf6de8a, lines 13-60 of 120)
```swift id=source2
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
```
### Sources/GorAVPlaybackCore/ColorStage.swift (sha256 daf6de8a, lines 60-120 of 120) (policy formula + generator seam: plan() is the golden generator for every fixture row)
```swift id=source3
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


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"source": "bt2020PQ peak 1000", "target": "sdr100", "expect": {"curve": "mobius", "gamut": "perceptual", "receipts_include": ["hdr-to-sdr:mobius-default"], "softwareFallback": "true iff hardwareToneMapper false"}}, {"source": "hlg (peak unsignalled)", "target": "bt2020PQ peak 1000", "expect": {"curve": "none", "receipts_include": ["src-peak-default:hlg:1000", "hdr-to-hdr:peak-fits"]}}, {"target": "DisplayTarget(targetTRC: .bt709, peakNits: 100)", "expect": "init succeeds; equals .sdr100"}, {"target": "peakNits 0 or NaN, saturation 2.5", "expect": "init nil (typed guard), never a clamped target"}]
```
