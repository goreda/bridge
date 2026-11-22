//  VRDistanceModel.swift
//  gor — block 182 item 2 (distance -> base_ipd model), macOS constant-mm route.
//
//  Faithful Swift port of the pinned Lua model
//  archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua@c6e1d3a7
//  (SHA256 c455d945...) lines 339-405 (model) and 1036-1058 (input slots).
//  Formula-for-formula; every constant is the Lua's value, every reason
//  string verbatim. The block 182 rules this encodes (owner order item 2):
//    - distance is used ONLY as a clamp (vergence demand capped at today's
//      value at d = 500 mm; at closer distances s is reduced)
//    - fov unavailable -> no distance term (constant-mm rule only)
//    - CGDisplayScreenSize = 0 -> the macbook mm_per_px (25.4/227)
//    - no face -> hold the last d for 2 s, then the constant-mm rule
//    - no owner calibration step, ever (this type has no calibration entry)
//  On macOS no permitted source produces a positive d (the order's own
//  missing-inputs rule), so the clamp path is implemented but unexercised
//  at runtime there; constant-mm is the contract-mandated route, not a
//  chosen exclusion. Display identity/backing-pixel custody is NOT solved
//  here: the sampled mmPerPx arrives as an input slot exactly like the Lua
//  message; this type never probes a display itself.
//
//  Pure value type, Foundation only: no camera, no display, no IPC.
//  Additive file; wires into nothing yet (embedded entry/tune dispatch is
//  a separate piece pending the Ops required-behavior evaluation).

import Foundation

public struct VRLookDistanceModel {

    // MARK: - Contract constants (Lua lines 339-346, 117-129, 167-168)

    /// Lua l.339: owner block 182 default IPD.
    public static let defaultIpdMM = 63.0
    /// Lua l.340: the cap is today's value at this distance.
    public static let referenceDistanceMM = 500.0
    /// Lua l.341: no face -> hold the last d this long.
    public static let distanceHoldS = 2.0
    /// Lua l.386-387: age <= 0.5 s reads "ok", then "hold-last-d".
    public static let holdOkBoundaryS = 0.5
    /// Lua l.345-346: today's base_ipd default is 0.0 (NDC, session-only),
    /// so its mm value is 0 mm; the dial is now the ipd offset in mm.
    public static let todayBaseIpdMM = 0.0
    /// Lua l.349: MacBook Air M1 13.3in panel, 2560 px at 227 ppi.
    public static let macbookMMPerPx = 25.4 / 227.0
    /// Lua l.350: the shader's clamp(combined_horizontal_shift, -0.8, 0.8).
    public static let shaderShiftLimit = 0.8
    /// Lua l.117: zoom/parallax reference fov.
    public static let zoomReferenceFovDeg = 90.0

    // MARK: - Input custody (Lua l.351: dist_in_d/reason/at/mmpx)

    /// Last accepted positive distance sample in mm (nil = no valid d).
    public private(set) var distInD: Double? = nil
    /// Why there is no valid d; verbatim Lua reasons.
    public private(set) var distInReason = "no-input"
    /// Timestamp (same clock as evaluate's `now`) of the last d sample.
    public private(set) var distInAt: Double? = nil
    /// Last received display mm/px; 0 means CGDisplayScreenSize
    /// unavailable -> the MacBook constant (Lua l.1057).
    public private(set) var distInMmPerPx: Double? = nil

    public init() {}

    /// Mirror of the set-orientation distance slots (Lua l.1053-1057):
    /// a positive d refreshes the sample and its timestamp and marks the
    /// reason "ok"; a non-ok reason without d clears the sample and keeps
    /// the reason; omitted slots stay untouched. mmPerPx is stored as
    /// received; 0/unset selects the MacBook constant at evaluation.
    public mutating func acceptDistance(dMM: Double?, reason: String?, mmPerPx: Double?, now: Double) {
        if let d = dMM, d > 0 {
            distInD = d
            distInAt = now
            distInReason = "ok"
        } else if let r = reason, !r.isEmpty, r != "ok" {
            distInD = nil
            distInReason = r
        }
        if let m = mmPerPx {
            distInMmPerPx = m
        }
    }

    // MARK: - Evaluation (Lua vr_update_distance l.364-405)

    public struct Outcome {
        /// vr_ipd_applied_base: nil while no dial value is applied
        /// (Lua l.365 resets before every evaluation).
        public var appliedBase: Double? = nil
        public var dMM: Double? = nil
        public var sTodayMM = 0.0
        public var sCapMM: Double? = nil
        public var sTotalMM = 0.0
        public var sRequestedMM = 0.0
        public var offsetMM = 0.0
        public var ipdEffMM = 0.0
        public var capped = false
        public var infeasible = false
        public var capMet = true
        public var reason = "no-input"
        public var mmPerPx = VRLookDistanceModel.macbookMMPerPx
        /// "CGDisplayScreenSize" or "macbook-227ppi" (verbatim labels).
        public var mmPerPxSource = "macbook-227ppi"
        public var eyeWidthMM = 0.0
        /// The Lua-identical geom trace line (l.399-404 formats), or the
        /// no-osd-size early form (l.368-371).
        public var trace = #"{"k":"vrDistance","reason":"no-osd-size","applied":false}"#
    }

    /// - Parameters:
    ///   - osdWidth: output width in px (mpv osd-width; <= 0 -> no-osd-size).
    ///   - vrFov, manualFov: current fov terms in degrees, summed and
    ///     clamped to [fovMinDeg, fovMaxDeg] exactly like the Lua.
    ///   - ipdNudge: today's head-nudge term (NDC fraction), per frame.
    ///   - ipdOffsetMM: the canonical dial; nil -> no applied base change
    ///     (vr_apply_ipd_mm returns early, Lua l.357-358).
    ///   - parallaxEnabled / disparity / strength: the parallax excess
    ///     terms (VR_PARALLAX_CORRECTION_*; tune overrides already resolved
    ///     by the caller, like vr_tune.* ?? defaults).
    ///   - now: same clock the samples were stamped with.
    public func evaluate(osdWidth: Double,
                         vrFov: Double, manualFov: Double,
                         fovMinDeg: Double, fovMaxDeg: Double,
                         ipdNudge: Double,
                         ipdOffsetMM: Double?,
                         parallaxEnabled: Bool,
                         parallaxDisparity: Double,
                         parallaxStrength: Double,
                         now: Double) -> Outcome {
        var o = Outcome()
        guard osdWidth > 0 else {
            o.reason = "no-osd-size"
            return o
        } // l.367-371 early trace form

        let haveMmpx = (distInMmPerPx ?? 0) > 0
        let mmpx = haveMmpx ? distInMmPerPx! : VRLookDistanceModel.macbookMMPerPx
        let eyeWMM = (osdWidth / 2.0) * mmpx
        let halfW = eyeWMM / 2.0

        var excess = 0.0
        if parallaxEnabled {
            // l.378: tan(rad(90)*0.5) / tan(rad(clamp(fov))*0.5)
            let mag = tan(VRLookDistanceModel.zoomReferenceFovDeg * .pi / 180.0 * 0.5)
                    / tan(Self.clamp(vrFov + manualFov, fovMinDeg, fovMaxDeg) * .pi / 180.0 * 0.5)
            excess = parallaxDisparity * (mag - 1.0) * parallaxStrength
        }

        let todayNorm = excess + ipdNudge + 0.0 // l.381: 0.0 = today's base_ipd default
        // vr_apply_ipd_mm (l.356-361): base_ipd = offset / halfW, so
        // offset_mm = base_ipd * half_w = the dial value, kept in the
        // Lua's two-step form for reviewability.
        let baseIpd = (ipdOffsetMM ?? 0) / halfW
        let offsetMM = baseIpd * halfW
        let sToday = todayNorm * halfW + VRLookDistanceModel.todayBaseIpdMM + offsetMM
        let ipdEff = VRLookDistanceModel.defaultIpdMM + offsetMM

        var d: Double? = nil
        var reason = distInReason
        if let sample = distInD, let at = distInAt {
            let age = now - at
            if age <= VRLookDistanceModel.distanceHoldS {
                d = sample
                reason = age <= VRLookDistanceModel.holdOkBoundaryS ? "ok" : "hold-last-d"
            } else {
                reason = "no-face-hold-expired"
            }
        }

        var sRequested = sToday
        var capped = false
        var sCap: Double? = nil
        if let d = d {
            let cap = (d / VRLookDistanceModel.referenceDistanceMM) * (ipdEff + sToday) - ipdEff
            sCap = cap
            if cap < sToday { sRequested = cap; capped = true }
        }

        var shift = sRequested / halfW
        let infeasible = abs(shift) > VRLookDistanceModel.shaderShiftLimit
        if infeasible {
            shift = Self.clamp(shift, -VRLookDistanceModel.shaderShiftLimit, VRLookDistanceModel.shaderShiftLimit)
        }
        let sTotal = shift * halfW // actual separation after the renderer limit
        let capMet: Bool
        if let d = d {
            capMet = ipdEff + sTotal <= (d / VRLookDistanceModel.referenceDistanceMM) * (ipdEff + sToday) + 1e-9
        } else {
            capMet = true
        }
        // l.398: shader total = clamp(excess + base + nudge): choose base
        // so the total is exactly `shift`.
        let applied = shift - excess - ipdNudge

        o.appliedBase = ipdOffsetMM == nil ? nil : applied
        o.dMM = d
        o.sTodayMM = sToday
        o.sCapMM = sCap
        o.sTotalMM = sTotal
        o.sRequestedMM = sRequested
        o.offsetMM = offsetMM
        o.ipdEffMM = ipdEff
        o.capped = capped
        o.infeasible = infeasible
        o.capMet = capMet
        o.reason = reason
        o.mmPerPx = mmpx
        o.mmPerPxSource = haveMmpx ? "CGDisplayScreenSize" : "macbook-227ppi"
        o.eyeWidthMM = eyeWMM
        o.trace = String(format:
            #"{"k":"vrDistance","d_mm":%@,"s_today_mm":%.4f,"s_cap_mm":%@,"s_total_mm":%.4f,"s_requested_mm":%.4f,"offset_mm":%.4f,"ipd_eff_mm":%.4f,"capped":%@,"infeasible":%@,"cap_met":%@,"reason":"%@","mm_per_px":%.6f,"mm_per_px_src":"%@","eye_w_mm":%.3f}"#,
            d.map { String(format: "%.2f", $0) } ?? "null",
            sToday,
            sCap.map { String(format: "%.4f", $0) } ?? "null",
            sTotal, sRequested, offsetMM, ipdEff,
            capped ? "true" : "false",
            infeasible ? "true" : "false",
            capMet ? "true" : "false",
            reason, mmpx, o.mmPerPxSource, eyeWMM)
        return o
    }

    /// Lua l.167 clamp.
    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        return max(lo, min(hi, v))
    }
}
