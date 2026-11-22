"""Temporal stability (flicker) metrics (CONTRACT-190v s21).

Frame-to-frame jitter of the prepared (aligned, EMA-smoothed) depth and
of the rendered disparity field. Jitter = second temporal difference
(t-1) - 2*(t) + (t+1): constant and linear motion cancel, so what
remains is high-frequency oscillation - model noise, quantisation
pump, or insufficient EMA smoothing - not scene motion.

Metrics (both per valid-pixel triple, then median over pixels, then
median + p95 over frames):
- depth_jitter: |d2(inv)| / median(inv), relative inverse depth.
- disparity_jitter: |d2(disp)| in CANVAS pixels, where disp is the
  rendered left-right parallax of each source pixel (the exact forward
  map of render_frame_sbs; convergence terms are time-constant and
  cancel in d2).
"""
import math

import numpy as np


def disparity_field(z, theta_h, ipd=0.063, out_w=None):
    """Rendered parallax (canvas px) per source pixel, sign-free."""
    h, w = z.shape
    out_w = out_w or w
    f = (w / 2.0) / math.tan(theta_h / 2.0)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    rx = (xs + 0.5 - w / 2.0) / f
    e = ipd / 2.0
    with np.errstate(invalid="ignore", divide="ignore"):
        lon_l = np.arctan2(rx * z - e, np.where(z > 0, z, 1.0))
        lon_r = np.arctan2(rx * z + e, np.where(z > 0, z, 1.0))
    return (lon_l - lon_r) / math.pi * out_w


def _second_diff_stats(seq, valid):
    """median/p95 over frames of median |d2| per valid triple."""
    d2 = np.abs(seq[2:] - 2.0 * seq[1:-1] + seq[:-2])
    v = valid[2:] & valid[1:-1] & valid[:-2]
    per_frame = []
    for t in range(len(d2)):
        vals = d2[t][v[t]]
        per_frame.append(float(np.median(vals)) if vals.size else np.nan)
    per_frame = np.array(per_frame)
    per_frame = per_frame[~np.isnan(per_frame)]
    if not per_frame.size:
        return {"median": float("nan"), "p95": float("nan"), "frames": 0}
    return {"median": float(np.median(per_frame)),
            "p95": float(np.percentile(per_frame, 95)),
            "frames": int(per_frame.size)}


def depth_jitter(inv_seq):
    """Relative inverse-depth jitter. inv_seq [T,H,W] (>0 valid)."""
    inv = inv_seq.astype(np.float64)
    valid = inv > 0
    med = np.maximum(np.median(inv[valid]), 1e-9)
    d2rel = np.abs(inv[2:] - 2 * inv[1:-1] + inv[:-2]) / med
    # reuse _second_diff_stats plumbing on the normalized field
    v = valid[2:] & valid[1:-1] & valid[:-2]
    per_frame = [float(np.median(d2rel[t][v[t]])) if v[t].any()
                 else np.nan for t in range(len(d2rel))]
    per_frame = np.array([x for x in per_frame if not np.isnan(x)])
    return {"median": float(np.median(per_frame)),
            "p95": float(np.percentile(per_frame, 95)),
            "frames": int(per_frame.size)}


def disparity_jitter(z_seq, theta_h, ipd=0.063, out_w=None):
    """Rendered disparity jitter in canvas px. z_seq [T,H,W] metres."""
    disp = np.stack([disparity_field(z, theta_h, ipd, out_w)
                     for z in z_seq])
    valid = z_seq > 0
    return _second_diff_stats(disp, valid)
