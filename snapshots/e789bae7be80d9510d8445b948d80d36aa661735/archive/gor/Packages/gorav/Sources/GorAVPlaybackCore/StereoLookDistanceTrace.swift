import Foundation

/// full182 (block182 owner order phonemsg-01M6PEZ10K9Y7Q3SGBNAVWTTQJ item 2,
/// owner channel 2026-11-05 21:19): "log d, s, the clamp flag and each
/// fallback reason in the geom trace." This payload carries the native input
/// owner's per-pull distance evaluation (StereoLookBaseEvaluation, owner
/// file StereoLookNativeInputOwner.swift) across the host-input boundary so
/// the presenter can emit the NATIVE geom-trace line. Transport only: every
/// value is the owner's evaluation VERBATIM, never recomputed or repaired at
/// this layer (no second distance authority; the producer's one-euro fD stays
/// the single filter authority, Sensing.swift l.220-221). A nil field is
/// rendered null exactly like the Lua trace (pin c455d945 l.406-413); the
/// four s_total/s_requested/offset/ipd_eff slots stay null until the owner
/// surfaces them (boundary decision D3) - they are never derived here.
public struct StereoLookDistanceTrace: Equatable, Sendable {
    /// d after the fresh-now hold evaluation (lua l.386-394): nil when the
    /// hold expired or no sample ever arrived -> the constant-mm rule ran.
    public var distanceMM: Double?
    public var sTodayMM: Double
    /// Requested separation after the shrink-only vergence cap (D3 slot).
    public var sRequestedMM: Double?
    /// The vergence cap itself; nil when no valid d (lua l.395-398).
    public var sCapMM: Double?
    /// Actual separation after the +/-0.8 shader feasibility clamp (D3 slot).
    public var sTotalMM: Double?
    /// The persistent ipd dial offset in mm (D3 slot).
    public var offsetMM: Double?
    /// 63 + offset (D3 slot).
    public var ipdEffMM: Double?
    /// The clamp flag: the vergence cap actually shrank the separation.
    public var capped: Bool
    /// |shift| exceeded VR_SHADER_SHIFT_LIMIT 0.8 and was clamped.
    public var infeasible: Bool
    /// cap_met diagnostic (lua l.404).
    public var capMet: Bool
    /// The fallback reason, verbatim: "ok", "hold-last-d",
    /// "no-face-hold-expired", "fov-unavailable", "no-input".
    public var reason: String
    public var mmPerPx: Double
    /// "host-display-<id>" or "macbook-227ppi" (Path A scale provenance).
    public var mmPerPxSource: String
    public var eyeWidthMM: Double
    public var halfWidthMM: Double
    /// Dial converted to NDC before the clamp (lua l.361).
    public var baseIpdRaw: Double
    /// The post-clamp applied base actually pushed to lane 53 (lua l.405).
    public var appliedIpdBase: Double

    public init(distanceMM: Double?, sTodayMM: Double,
                sRequestedMM: Double? = nil, sCapMM: Double?,
                sTotalMM: Double? = nil, offsetMM: Double? = nil,
                ipdEffMM: Double? = nil,
                capped: Bool, infeasible: Bool, capMet: Bool,
                reason: String, mmPerPx: Double, mmPerPxSource: String,
                eyeWidthMM: Double, halfWidthMM: Double,
                baseIpdRaw: Double, appliedIpdBase: Double) {
        self.distanceMM = distanceMM; self.sTodayMM = sTodayMM
        self.sRequestedMM = sRequestedMM; self.sCapMM = sCapMM
        self.sTotalMM = sTotalMM; self.offsetMM = offsetMM
        self.ipdEffMM = ipdEffMM
        self.capped = capped; self.infeasible = infeasible; self.capMet = capMet
        self.reason = reason
        self.mmPerPx = mmPerPx; self.mmPerPxSource = mmPerPxSource
        self.eyeWidthMM = eyeWidthMM; self.halfWidthMM = halfWidthMM
        self.baseIpdRaw = baseIpdRaw; self.appliedIpdBase = appliedIpdBase
    }

    /// The Lua geom-trace line (pin c455d945 l.406-413), field-for-field:
    /// {"k":"vrDistance","d_mm":...,"reason":"...","mm_per_px_src":"..."}.
    /// Same formats (%.2f d, %.4f s values, %.6f mm_per_px, %.3f eye_w_mm),
    /// same null rendering for absent d / s_cap, same lowercase booleans.
    public func geomTraceLine() -> String {
        func num(_ v: Double?, _ fmt: String) -> String {
            v.map { String(format: fmt, $0) } ?? "null"
        }
        return "{\"k\":\"vrDistance\""
            + ",\"d_mm\":" + num(distanceMM, "%.2f")
            + ",\"s_today_mm\":" + String(format: "%.4f", sTodayMM)
            + ",\"s_cap_mm\":" + num(sCapMM, "%.4f")
            + ",\"s_total_mm\":" + num(sTotalMM, "%.4f")
            + ",\"s_requested_mm\":" + num(sRequestedMM, "%.4f")
            + ",\"offset_mm\":" + num(offsetMM, "%.4f")
            + ",\"ipd_eff_mm\":" + num(ipdEffMM, "%.4f")
            + ",\"capped\":" + (capped ? "true" : "false")
            + ",\"infeasible\":" + (infeasible ? "true" : "false")
            + ",\"cap_met\":" + (capMet ? "true" : "false")
            + ",\"reason\":\"" + reason + "\""
            + ",\"mm_per_px\":" + String(format: "%.6f", mmPerPx)
            + ",\"mm_per_px_src\":\"" + mmPerPxSource + "\""
            + ",\"eye_w_mm\":" + String(format: "%.3f", eyeWidthMM)
            + "}"
    }
}
