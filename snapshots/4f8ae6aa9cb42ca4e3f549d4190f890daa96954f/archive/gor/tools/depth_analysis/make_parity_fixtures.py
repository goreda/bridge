"""Generate numeric parity fixtures for the Swift ports (contract s15).

Each JSON under Tests/DepthAnalysis/parity/ pins one algorithm the Mac
side re-implements: exact inputs, expected outputs, and a tolerance.
The Python reference is verified against the fixtures by
Tests/DepthAnalysis/test_parity_fixtures.py, so a fixture can never
drift from the implementation it pins; the Swift port runs the same
JSON on the Mac. Tolerances are set generously enough for a different
LAPACK/optimizer (Accelerate, a hand-rolled LM) and tightly enough to
catch sign, axis and order bugs.

Domains:
  moge_recovery.json  focal/shift recovery from a point map (MoGe-2
                      post-processing, utils3d_moge semantics) + the
                      metric-scale application
  align.json          ShotAligner LSQ + EMA + inf-sky skipping
  depth_quant.json    depth <-> 10-bit luma quantisation (v = 256/z,
                      w10 = clip(rint(v/1024*1023), 0, 1023))
  cut_detect.json     scdet threshold constant + time->frame rounding +
                      shot-range derivation
"""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Tests", "DepthAnalysis", "parity")

MOGE_REPO = os.environ.get("MOGE_REPO", os.path.expanduser("~/s4/190t/moge"))


def r6(x):
    return np.round(np.asarray(x, dtype=np.float64), 6).tolist()


def moge_recovery():
    import sys
    sys.path.insert(0, MOGE_REPO)
    sys.path.insert(0, HERE)
    from moge.utils.geometry_numpy import normalized_view_plane_uv_numpy
    # s15: the pinned solver is the MULTISTART reference (upstream lm(x0=0)
    # stalls on exact-geometry large-shift scenes - see stall_cases below)
    from moge_recovery import (solve_optimal_focal_shift,
                               solve_optimal_shift)

    # uv-grid pin: 4 wide x 3 high (small enough to eyeball in a diff)
    uv_pin = normalized_view_plane_uv_numpy(width=4, height=3).astype(np.float64)

    rng = np.random.default_rng(42)
    h, w = 12, 16
    uv = normalized_view_plane_uv_numpy(width=w, height=h).astype(np.float64)
    z = rng.uniform(0.5, 4.0, (h, w))
    focal_true, shift_true = 1.35, 0.25
    xy = uv * (z + shift_true)[..., None] / focal_true
    points = np.concatenate([xy, z[..., None]], axis=-1)

    uv_flat = uv.reshape(-1, 2)
    pts_flat = points.reshape(-1, 3)
    shift, focal = solve_optimal_focal_shift(uv_flat, pts_flat)
    shift_given = solve_optimal_shift(uv_flat, pts_flat,
                                      np.float32(focal_true))

    rng2 = np.random.default_rng(7)
    noisy = points.copy()
    noisy[..., :2] += rng2.normal(0, 0.005, (h, w, 2))
    shift_n, focal_n = solve_optimal_focal_shift(uv_flat, noisy.reshape(-1, 3))

    depth = np.array([[1.0, 2.5, 4.0], [0.5, 8.0, 16.0]])
    metric_scale = 1.74
    return {
        "spec": {
            "model": "uv = focal * xy / (z + shift); solve min|focal*xy/(z+shift)-uv|",
            "solver": "Levenberg-Marquardt on shift only, MULTISTART "
                      "x0 in {0,.5,1,2,4} (ftol=1e-3), min-cost selection "
                      "(contract s15; upstream single-start x0=0 stalls on "
                      "exact-geometry large-shift scenes), then focal = "
                      "sum(xy_proj*uv)/sum(xy_proj^2) in closed form",
            "uv_grid": "span_x = ar/sqrt(1+ar^2), span_y = 1/sqrt(1+ar^2), "
                       "ar = w/h; u = linspace(-span_x*(w-1)/w, +.., w), "
                       "v = linspace(-span_y*(h-1)/h, +.., h), meshgrid xy",
            "pipeline_note": "production path downsamples points+uv to 64x64 "
                             "NEAREST before solving; fixtures pin the solver",
        },
        "uv_pin_w4_h3": r6(uv_pin),
        "case_known": {
            "h": h, "w": w, "points": r6(points),
            "expect": {"focal": float(focal), "shift": float(shift)},
            "true": {"focal": focal_true, "shift": shift_true},
            "tolerance": {"focal_rel": 2e-3, "shift_abs": 2e-3},
        },
        "case_given_focal": {
            "h": h, "w": w, "points": r6(points), "focal": focal_true,
            "expect": {"shift": float(shift_given)},
            "tolerance": {"shift_abs": 1e-3},
        },
        "case_noisy": {
            "h": h, "w": w, "points": r6(noisy),
            "expect": {"focal": float(focal_n), "shift": float(shift_n)},
            "tolerance": {"focal_rel": 5e-3, "shift_abs": 5e-3},
        },
        "metric_scale": {
            "depth": r6(depth), "metric_scale": metric_scale,
            "expect_scaled": r6(depth * metric_scale),
            "tolerance_rel": 1e-6,
        },
        # E-G stall scenes (contract s15): exact geometry, large shift/z -
        # single-start lm(x0=0) returns shift ~0 here; the multistart solver
        # must recover truth. Scenes regenerate from params, no stored grids:
        # Z = 3 + 2*sin(linspace(0,6,w)) rows + cos(linspace(0,4,h)) cols,
        # focal from hfov per the uv_grid spec, point map = [uv*Z/f, Z-shift],
        # downsampled to 64x64 (arange(h)*64//h indexing) as production does.
        "stall_cases": [
            {"name": n, "h": hh, "w": ww, "hfov_deg": fv,
             "shift_true": st, "expect_shift": st,
             "expect_focal": 0.5 / math.tan(math.radians(fv) / 2) * 2 *
             (ww / hh) / (1 + (ww / hh) ** 2) ** .5,
             "tol_shift": 0.02, "tol_focal_rel": 0.01}
            for n, hh, ww, fv, st in [
                ("eg_hfov60", 72, 128, 60.0, 1.3),
                ("eg_hfov90", 96, 96, 90.0, 0.4),
                ("eg_hfov38", 80, 192, 38.0, 2.5),
                ("small_shift", 72, 128, 55.0, 0.05)]
        ],
    }


def normalized_uv(w, h):
    """The pinned uv grid (spec.uv_grid in moge_recovery.json)."""
    # Formula is recorded verbatim in the existing fixture's spec.uv_grid.
    # This numeric helper needs no model, weights or upstream inference package.
    aspect=w/h;span_x=aspect/math.sqrt(1+aspect*aspect);span_y=1/math.sqrt(1+aspect*aspect)
    x=np.linspace(-span_x*(w-1)/w,span_x*(w-1)/w,w)
    y=np.linspace(-span_y*(h-1)/h,span_y*(h-1)/h,h)
    return np.stack(np.meshgrid(x,y),axis=-1)


def moge_recovery_scene(h, w, hfov_deg, shift):
    """Regenerate a stall-scene point map (shared with the verifier test)."""
    a = w / h
    focal = 0.5 / math.tan(math.radians(hfov_deg) / 2) * 2 * a / (1 + a * a) ** .5
    Z = 3.0 + 2.0 * np.sin(np.linspace(0, 6, w))[None, :] + \
        np.cos(np.linspace(0, 4, h))[:, None]
    uv = normalized_uv(w,h)
    pts = np.concatenate([uv * Z[..., None] / focal, (Z - shift)[..., None]], -1)
    iy = np.minimum(h - 1, np.arange(64) * h // 64)
    ix = np.minimum(w - 1, np.arange(64) * w // 64)
    u64, p64 = uv[iy][:, ix], pts[iy][:, ix]
    return u64.reshape(-1, 2), p64.reshape(-1, 3), focal


def align():
    from align import ShotAligner

    rng = np.random.default_rng(11)
    h, w = 6, 8
    true_s, true_b = -0.6, 7.2
    vda = rng.uniform(0.2, 0.9, (4, h, w))
    moge = vda * true_s + true_b + rng.normal(0, 0.001, (4, h, w))
    moge[2, h // 2:, :] = np.inf          # sky half: fit on the rest
    moge[3, :, :] = np.inf
    moge[3, 0, :8] = np.linspace(5.0, 6.4, 8)  # only 8 finite: <16, skipped
    al = ShotAligner(ema=0.9)
    frames = []
    for k in range(4):
        out = al.update(vda[k], moge[k])
        frames.append({"scale": r6(al.scale), "shift": r6(al.shift),
                       "skipped_total": al.skipped,
                       "aligned_row0": r6(out[0])})
    return {
        "spec": {
            "fit": "least squares min||scale*vda + shift - moge||^2 over "
                   "finite pairs, >=16 pairs required else frame skipped",
            "ema": "scale = 0.9*scale + 0.1*new (shift likewise); first fit "
                   "seeds; skipped frames apply the running estimate",
        },
        "ema": 0.9,
        "vda": r6(vda),
        "moge": r6(np.where(np.isfinite(moge), moge, 9.9e99)),
        "moge_inf_marker": 9.9e99,
        "expect_frames": frames,
        "tolerance_rel": 1e-6,
    }


def depth_quant():
    from prepare_film import D_SCALE, V_INV_MAX

    z = [0.1, 0.25, 0.5, 1.0, 2.0, 3.7, 10.0, 33.33, 100.0, 1000.0,
         1.0e6, 0.0, -1.0]
    rows = []
    for zz in z:
        v = D_SCALE / zz if zz > 0 else 0.0
        w10 = int(np.clip(np.rint(np.float32(v) / V_INV_MAX * 1023.0),
                          0, 1023))
        inv_back = w10 / 1023.0 * V_INV_MAX
        rows.append({"z": zz, "v": r6(v), "w10": w10,
                     "inv_roundtrip": r6(inv_back),
                     "z_roundtrip": r6(D_SCALE / inv_back) if w10 > 0 else None})
    return {
        "spec": {
            "encode": "v = 256/z (z<=0 masked -> 0); w10 = clip(round(v/1024*1023), 0, 1023)",
            "decode": "inv = w10/1023*1024; z = 256/inv (w10==0 -> masked)",
            "container": "w10 rides LUMA of yuv420p10le, chroma constant 512",
        },
        "cases": rows,
        "tolerance": {"w10_abs": 0, "note": "integer quantisation must match exactly"},
    }


def cut_detect():
    from cuts import SCDET_THRESHOLD, shots_from_cuts

    times = [1.04, 2.00, 3.999]
    fps, n = 24, 120
    frames = sorted({int(t * fps + 0.5) for t in times})
    return {
        "spec": {
            "detector": "ffmpeg -vf scdet=threshold=12.0; parse lavfi.scd.time",
            "threshold": SCDET_THRESHOLD,
            "semantics": "hard cuts only; fades stay uncut BY DESIGN "
                         "(measured on ToS/Caminandes). A Mac port using "
                         "another detector must reproduce these boundaries "
                         "on the calibration clips, not scdet internals.",
            "time_to_frame": "frame = int(t*fps + 0.5), dedup, sort",
            "ranges": "bounds [0]+cuts(0<c<n)+[n]; shot i = (b[i], b[i+1]-1)",
        },
        "case": {"times_s": times, "fps": fps, "n_frames": n,
                 "expect_cut_frames": frames,
                 "expect_ranges": [list(r) for r in shots_from_cuts(n, frames)]},
        "edge_cases": [
            {"times_s": [0.0], "fps": 24, "n_frames": 48,
             "expect_ranges": [[0, 47]]},
            {"times_s": [2.0], "fps": 24, "n_frames": 48,
             "expect_ranges": [[0, 47]]},
        ],
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("moge_recovery", moge_recovery), ("align", align),
                     ("depth_quant", depth_quant), ("cut_detect", cut_detect)]:
        path = os.path.join(OUT, name + ".json")
        json.dump(fn(), open(path, "w"), indent=1)
        print("wrote", path)


if __name__ == "__main__":
    main()
