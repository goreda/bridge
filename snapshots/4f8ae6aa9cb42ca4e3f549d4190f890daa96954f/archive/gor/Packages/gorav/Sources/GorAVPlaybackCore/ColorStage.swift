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
