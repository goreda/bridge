"""Keyframe-boundary depth pops + causal eased alignment (contract s30).

Re-aligning VDA relative depth to MoGe metric per keyframe (stride 12)
and SWITCHING the affine at the keyframe pops rendered disparity past
the comfort band on real content: measured p95 max 2.64 deg (live,
kf12) / 1.75 deg (CG fixture below) at the 75 deg screen vs budgets of
2 deg crossed / 1 deg divergence. The reference therefore eases the
per-keyframe EMA value in linearly over the frames AFTER each keyframe
(align.apply_align_track): continuous, causal, deterministic from the
shot's stored keyframe track; cuts reset the EMA (ShotAligner.reset).

Pins (CG fixture: tools/depth_analysis/golden/align_fixture, 48f CG
slice, real VDA-S rel depth ::8 + real MoGe-2 keyframe fits):
- step application boundary pop p95 max 1.7487 deg (> 1 deg divergence
  band: the problem), eased 0.0179 deg (< 0.05 deg pin: the fix);
- disparity jitter p95 (s21 metric): step 0.3007 px -> eased 0.0122 px;
- fast-seek: params at any frame derive from track entries <= its
  keyframe only - a mid-shot landing with no prior state reproduces the
  sequential depth exactly.

Run: python3 Tests/DepthAnalysis/test_keyframe_align.py
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))

from align import ShotAligner, apply_align_track, fit_scale_shift  # noqa: E402

IPD = 0.063
F_PX_360 = (360 / 2) / math.tan(math.radians(75) / 2)  # CG eye at 75 deg


def _ema_track(fits, ema=0.9):
    out, s, b = [], None, None
    for k, fs, fb in fits:
        if s is None:
            s, b = fs, fb
        else:
            s, b = ema * s + (1 - ema) * fs, ema * b + (1 - ema) * fb
        out.append((k, s, b))
    return out


def _pop_p95_deg(vda, param_fn, f_px):
    pops = []
    for f in range(1, vda.shape[0]):
        s0, b0 = param_fn(f - 1)
        s1, b1 = param_fn(f)
        if abs(s1 - s0) < 1e-12 and abs(b1 - b0) < 1e-12:
            continue
        v = vda[f]
        zo, zn = s0 * v + b0, s1 * v + b1
        m = (zo > 0.3) & (zn > 0.3)
        pop = np.abs(IPD * f_px / np.maximum(zn[m], 1e-6)
                     - IPD * f_px / np.maximum(zo[m], 1e-6))
        pops.append(float(np.percentile(pop, 95)))
    return float(np.max(pops)) / f_px * 180 / math.pi


def test_synthetic_known_jump():
    """Synthetic 60f shot with a true affine jump at kf24: step pops past
    the comfort band, eased stays under the pin; seek exact."""
    rng = np.random.default_rng(11)
    base = rng.uniform(0.5, 3.0, (32, 32))
    drift = np.linspace(0, 0.05, 60)[:, None, None]
    vda = base[None] + drift + rng.normal(0, 0.005, (60, 32, 32))
    # true metric affine: 2.0/5.0 up to kf24, then jumps to 3.2/7.0
    fits = []
    for k in range(0, 60, 12):
        true_s, true_b = (2.0, 5.0) if k < 24 else (3.2, 7.0)
        moge = vda[k] * true_s + true_b
        s, b = fit_scale_shift(vda[k], moge)
        fits.append((k, s, b))
    track = _ema_track(fits)

    def step_params(f):
        i = max(j for j, (k, _, _) in enumerate(fits) if k <= f)
        return fits[i][1], fits[i][2]

    def ease_params(f):
        ks = [k for k, _, _ in track]
        i = max(j for j, k in enumerate(ks) if k <= f)
        k0, s0, b0 = track[i]
        if i == 0:
            return s0, b0
        kp, sp, bp = track[i - 1]
        t = min(1.0, (f - k0) / (k0 - kp))
        return sp + (s0 - sp) * t, bp + (b0 - bp) * t

    step_deg = _pop_p95_deg(vda, step_params, F_PX_360)
    ease_deg = _pop_p95_deg(vda, ease_params, F_PX_360)
    assert step_deg > 0.1, step_deg  # the test can detect a real pop
    assert ease_deg < 0.05, ease_deg
    print(f"PASS synthetic: step pop {step_deg:.3f} deg > band, "
          f"eased {ease_deg:.4f} deg < 0.05 pin")

    # apply_align_track matches the eased params exactly, and a mid-shot
    # seek (params from track entries <= f only) reproduces it
    z = apply_align_track(vda, track)
    for f in (1, 7, 13, 25, 37, 59):
        s, b = ease_params(f)
        np.testing.assert_allclose(z[f], vda[f] * s + b, rtol=1e-9,
                                   atol=1e-9, err_msg=f"frame {f}")
    print("PASS fast-seek: track-only params == sequential depth (exact)")


def test_cg_fixture_pins():
    """Real-content pins (48f CG slice, real VDA rel + MoGe kf fits)."""
    gd = os.path.join(HERE, "..", "..", "tools", "depth_analysis",
                      "golden", "align_fixture")
    vda = np.load(os.path.join(gd, "vda_rel_cg_sub8.npy")).astype(np.float64)
    fits = [tuple(r) for r in json.load(
        open(os.path.join(gd, "keyframe_fits_cg.json")))["fits"]]
    track = _ema_track(fits)
    T = vda.shape[0]

    def step_params(f):
        i = max(j for j, (k, _, _) in enumerate(fits) if k <= f)
        return fits[i][1], fits[i][2]

    def ease_params(f):
        ks = [k for k, _, _ in track]
        i = max(j for j, k in enumerate(ks) if k <= f)
        k0, s0, b0 = track[i]
        if i == 0:
            return s0, b0
        kp, sp, bp = track[i - 1]
        t = min(1.0, (f - k0) / (k0 - kp))
        return sp + (s0 - sp) * t, bp + (b0 - bp) * t

    step_deg = _pop_p95_deg(vda, step_params, F_PX_360)
    ease_deg = _pop_p95_deg(vda, ease_params, F_PX_360)
    assert abs(step_deg - 1.7487) < 0.05, step_deg  # problem size pinned
    assert abs(ease_deg - 0.0179) < 0.005, ease_deg  # fix pinned
    assert ease_deg < 0.05
    print(f"PASS CG fixture: step {step_deg:.4f} deg (pin 1.7487), "
          f"eased {ease_deg:.4f} deg (pin 0.0179)")

    # flicker (s21 metric): eased jitter p95 far below step
    import flicker
    z_step = np.empty_like(vda)
    for i, (k, fs, fb) in enumerate(fits):
        hi = fits[i + 1][0] if i + 1 < len(fits) else T
        z_step[k:hi] = vda[k:hi] * fs + fb
    z_ease = apply_align_track(vda, track)
    m = dict(median=None)
    j_step = flicker.disparity_jitter(np.where(z_step > 0.3, z_step, 0),
                                      math.radians(75), IPD, 360)
    j_ease = flicker.disparity_jitter(np.where(z_ease > 0.3, z_ease, 0),
                                      math.radians(75), IPD, 360)
    assert abs(j_step["p95"] - 0.3007) < 0.02, j_step
    assert abs(j_ease["p95"] - 0.0122) < 0.005, j_ease
    print(f"PASS flicker: jitter p95 step {j_step['p95']:.4f} -> "
          f"eased {j_ease['p95']:.4f} px (pins 0.3007 / 0.0122)")


def test_cut_reset_and_fallback():
    """Cuts reset the EMA; empty/degenerate track falls back cleanly."""
    al = ShotAligner(ema=0.9)
    rng = np.random.default_rng(3)
    v = rng.uniform(0, 1, (20, 20))
    al.update(v, v * 5.0 + 2.0)
    assert al.scale is not None
    al.reset()
    assert al.scale is None and al.shift is None
    v2 = rng.uniform(0, 1, (20, 20))
    out = al.update(v2, v2 * 9.0 - 1.0)
    np.testing.assert_allclose(out, v2 * 9.0 - 1.0, atol=1e-6)
    # empty track -> default affine; None state -> default
    vda = rng.uniform(0.5, 2.0, (5, 8, 8))
    z = apply_align_track(vda, [], default=(2.0, 1.0))
    np.testing.assert_allclose(z, vda * 2.0 + 1.0)
    z = apply_align_track(vda, [(0, None, None)], default=(2.0, 1.0))
    np.testing.assert_allclose(z, vda * 2.0 + 1.0)
    print("PASS cut reset + empty/None track fallback")


def main():
    test_synthetic_known_jump()
    test_cg_fixture_pins()
    test_cut_reset_and_fallback()
    print("ALL KEYFRAME ALIGN TESTS PASS")


if __name__ == "__main__":
    main()
