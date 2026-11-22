// Lab color curves (G0738 / 195b-N7, lab: 1nstinct), additive consumer seam:
// scalar Swift port of the mobius tone curve + BT.1886 target EOTF from
// kits/n7-color/gen/spec_shared.h (the lab's single source of truth; the
// generated C/MSL carrier with its 25-check suite stays vendored). These are
// the curves the PINNED ColorStage.plan policy selects (hdr-to-sdr -> mobius,
// hdr-to-hdr mobius iff sourcePeak > targetPeak); this file adds no policy -
// plan() remains the only curve-selection site. Float mirrors C `float`.
// The full ICtCp/gamut pipeline stays in the vendored kit for the Metal path.

import Foundation

public enum LabColorCurves {
    /// Mobius tone curve: passes through (j, j) with slope 1, maps peak -> 1.
    /// Linear below the knee. Ported line-faithful from cp_mobius.
    public static func mobius(_ x: Float, peak: Float, knee j: Float) -> Float {
        if x <= j { return x }
        let a = -j * j * (peak - 1) / (j * j - 2 * j + peak)
        let b = (j * j - 2 * j * peak + peak) / (peak - 1)
        let scale = (b * b + 2 * b * j + j * j) / (b - a)
        return scale * (x + a) / (x + b)
    }

    /// BT.1886 target EOTF coefficients from white/black level (nits).
    /// Ported from cp_bt1886_coef.
    public static func bt1886Coefficients(white lw: Float, black lb: Float) -> (a: Float, b: Float) {
        let vw = pow(lw, 1 / 2.4)
        let vb = pow(lb, 1 / 2.4)
        return (pow(vw - vb, 2.4), vb / (vw - vb))
    }

    /// BT.1886 encode: nits -> code value in [0, 1]. From cp_bt1886_encode.
    public static func bt1886Encode(nits: Float, a: Float, b: Float) -> Float {
        let v = pow(max(nits, 0) / a, 1 / 2.4) - b
        return min(max(v, 0), 1)
    }

    /// BT.1886 decode: code value -> nits. From cp_bt1886_decode.
    public static func bt1886Decode(_ v: Float, a: Float, b: Float) -> Float {
        let x = v + b
        return a * x * pow(x, 1.4) // (v+b)^2.4
    }

    /// Peak-compressed normalized luminance used by the pixel pipeline:
    /// mobius only when srcPeak exceeds the destination (src<=dst: none),
    /// from spec_shared.h line 135.
    public static func toneCompress(normalizedX x: Float, peak: Float, knee: Float) -> Float {
        peak > 1 ? mobius(x, peak: peak, knee: knee) : x
    }
}
