"""3D comfort: disparity distribution + convergence/clamp policy (contract s25).

Angular screen disparity of a point at metric depth z, eyes at +-B/2,
convergence plane at z_c (both eyes rotated so z_c lands at zero
disparity), screen-centre approximation (exact on the optical axis,
stated as such; off-axis adds < 5% within the 75 deg screen):

    disp_deg(z) = deg( 2*atan(B / (2 z)) - 2*atan(B / (2 z_c)) )

  disp > 0: crossed (nearer than the screen) - comfort budget ~2 deg
  disp < 0: uncrossed (divergent, beyond the screen) - budget ~1 deg
(Budgets: standard stereo comfort rules of thumb - divergence is the
hard limit because eyes must not diverge past parallel.)

Convergence default: the shot's MEDIAN depth (the typical surface sits
at screen depth). Computed ONCE per shot - per-frame convergence would
pump; a step is allowed at shot cuts (the cut masks it).

Near clamp: z_eff = max(z, z_near) with z_near from the crossed budget:
    2*atan(B/(2 z_near)) - 2*atan(B/(2 z_c)) <= NEAR_BUDGET
Far check: z -> infinity gives -2*atan(B/(2 z_c)) >= -FAR_BUDGET, i.e.
z_c >= B / (2 tan(FAR_BUDGET/2)). With B = 0.063 and 1 deg: z_c >= 3.61 m.
Shots whose median is nearer need a smaller effective baseline -
that is the default policy (shot_comfort): keep z_c at the shot median
and shrink the baseline via depth_scale so infinity sits exactly at
the far budget:
    B_eff = min(IPD, 2 * z_c * tan(FAR_BUDGET/2));  depth_scale = B_eff/IPD
Both budgets then hold BY CONSTRUCTION on every shot (measured s25:
CG 16:9 z_c 1.14 m scale 0.31 -> [-0.17, +0.92] deg; live z_c 2.64 m
scale 0.73 -> [-0.69, +2.00] deg with 3.3% of pixels near-clamped).
"""
import numpy as np

IPD = 0.063                 # default baseline (m)
NEAR_BUDGET = 2.0           # deg, crossed
FAR_BUDGET = 1.0            # deg, uncrossed (divergence limit)


def disp_deg(z, z_c, ipd=IPD):
    """Angular screen disparity (deg); + crossed / - uncrossed."""
    z = np.maximum(np.asarray(z, np.float64), 1e-9)
    return np.degrees(2 * np.arctan(ipd / (2 * z))
                      - 2 * np.arctan(ipd / (2 * z_c)))


def near_clamp(z_c, ipd=IPD, budget=NEAR_BUDGET):
    """z_near: nearest allowed depth; closer content is clamped to it."""
    t = np.tan(np.radians(budget) / 2 + np.arctan(ipd / (2 * z_c)))
    return ipd / (2 * t)


def far_overflow(z_c, ipd=IPD, budget=FAR_BUDGET):
    """Divergence of infinity beyond budget (deg; <= 0 is compliant)."""
    return np.degrees(2 * np.arctan(ipd / (2 * z_c))) - budget


def min_convergence(ipd=IPD, budget=FAR_BUDGET):
    """Nearest convergence plane that keeps infinity inside budget."""
    return ipd / (2 * np.tan(np.radians(budget) / 2))


def distribution(z, z_c=None, ipd=IPD, z_near=None):
    """Percentile stats of disp_deg over valid depth; z_c defaults to
    the shot median (the per-shot constant-convergence rule)."""
    v = z[np.isfinite(z) & (z > 0)]
    if v.size == 0:
        return None
    if z_near is None:
        z_c = float(np.median(v)) if z_c is None else z_c
        z_near = near_clamp(z_c, ipd)
    vc = np.maximum(v, z_near)
    d = disp_deg(vc, z_c, ipd)
    return {"z_med": float(np.median(v)), "z_c": float(z_c),
            "z_near": float(z_near),
            "p01": float(np.percentile(d, 1)),
            "p50": float(np.percentile(d, 50)),
            "p99": float(np.percentile(d, 99)),
            "max_crossed": float(d.max()), "max_uncrossed": float(d.min()),
            "clamped_frac": float((v < z_near).mean()),
            "far_overflow_deg": far_overflow(z_c, ipd)}


def shot_convergence(z_frames):
    """Per-shot constant convergence: the median over ALL valid pixels
    of the shot (not per frame)."""
    v = np.concatenate([f[np.isfinite(f) & (f > 0)].ravel()
                        for f in z_frames])
    return float(np.median(v)) if v.size else None


def shot_comfort(z_frames, ipd=IPD):
    """The default per-shot comfort policy. Returns convergence_m,
    depth_scale (render_frame_sbs parameters) and z_near so that the
    crossed budget (2 deg) and the divergence budget (1 deg at
    infinity) both hold by construction:
      z_c         = shot median depth (screen-depth plane)
      B_eff       = min(ipd, 2*z_c*tan(FAR_BUDGET/2)); scale = B_eff/ipd
      z_near      = near_clamp(z_c, B_eff)  (render clamps z to z_near)
    Renderers apply z_near as max(z, z_near) before projecting."""
    z_c = shot_convergence(z_frames)
    if z_c is None:
        return None
    b_eff = min(ipd, 2.0 * z_c * np.tan(np.radians(FAR_BUDGET) / 2.0))
    return {"convergence_m": z_c, "ipd_eff": float(b_eff),
            "depth_scale": float(b_eff / ipd),
            "z_near": float(near_clamp(z_c, b_eff)),
            "far_overflow_deg": 0.0 if b_eff < ipd else
            far_overflow(z_c, ipd)}


# --- F3 (190v): scale-invariant comfort gain from the shot's disparity
# quantiles - mirror of Sources/gor/gor/ThreeD.swift ShotComfort.swift section (ShotComfortSpan span, 195y G2).
# The renderer wiring calls the Swift fn; this is the numeric reference.
# The render key and test_render_key_matrix change WITH the wiring.

SPAN_MIN_GAIN = 0.25
SPAN_MAX_GAIN = 3.0


def quantile_frames(z_frames, q):
    """Linear-interpolation quantile over the valid depth values (z > 0,
    finite) of any number of frames; None if none. Matches
    ShotComfortSpan.quantile (numpy-default interpolation)."""
    v = np.concatenate([np.asarray(f, np.float64).ravel() for f in z_frames])
    v = v[np.isfinite(v) & (v > 0)]
    if v.size == 0:
        return None
    return float(np.percentile(v, q * 100.0))


def shot_comfort_span_values(z_near, z_far, z_c, ipd=IPD):
    """Mirror of ShotComfortSpan.make: the largest gain s in
    [SPAN_MIN_GAIN, SPAN_MAX_GAIN] with disp_deg(z_near, z_c, ipd*s) <=
    NEAR_BUDGET and disp_deg(z_far, z_c, ipd*s) >= -FAR_BUDGET (60-iteration
    bisection on the exact formula, ok(lo) invariant); clamped=True when
    either gain bound is hit. span_before_deg is the span under the
    default shot_comfort baseline (depth_scale from the median) so the
    wiring can report the change in depth feel. None for invalid input
    (non-finite, z_near <= 0, z_far < z_near, z_c <= 0)."""
    if not all(np.isfinite(v) for v in (z_near, z_far, z_c)):
        return None
    if not (z_near > 0 and z_far >= z_near and z_c > 0):
        return None
    def ok(s):
        return (disp_deg(z_near, z_c, ipd * s) <= NEAR_BUDGET
                and disp_deg(z_far, z_c, ipd * s) >= -FAR_BUDGET)
    def span(s):
        return float(disp_deg(z_near, z_c, ipd * s)
                     - disp_deg(z_far, z_c, ipd * s))
    if ok(SPAN_MAX_GAIN):
        g = SPAN_MAX_GAIN
    elif not ok(SPAN_MIN_GAIN):
        g = SPAN_MIN_GAIN
    else:
        lo, hi = SPAN_MIN_GAIN, SPAN_MAX_GAIN
        for _ in range(60):
            m = (lo + hi) / 2.0
            if ok(m):
                lo = m
            else:
                hi = m
        g = lo
    base = min(1.0, 2.0 * z_c * np.tan(np.radians(FAR_BUDGET) / 2.0) / ipd)
    return {"z_near": float(z_near), "z_far": float(z_far), "z_c": float(z_c),
            "near_clamp_m": float(near_clamp(z_c, ipd * g)),
            "gain": float(g), "ipd_eff": float(ipd * g),
            "near_deg": float(disp_deg(z_near, z_c, ipd * g)),
            "far_deg": float(disp_deg(z_far, z_c, ipd * g)),
            "span_deg": span(g), "span_before_deg": span(base),
            "clamped": bool(g == SPAN_MIN_GAIN or g == SPAN_MAX_GAIN)}


def shot_comfort_span(z_frames, ipd=IPD):
    """Frame-level form of the mirror: z_near/z_far = p5/p95 of the shot's
    valid depth, z_c = the shot median over the same frames."""
    z_near = quantile_frames(z_frames, 0.05)
    z_far = quantile_frames(z_frames, 0.95)
    z_c = shot_convergence(z_frames)
    if z_near is None or z_far is None or z_c is None:
        return None
    return shot_comfort_span_values(z_near, z_far, z_c, ipd)
