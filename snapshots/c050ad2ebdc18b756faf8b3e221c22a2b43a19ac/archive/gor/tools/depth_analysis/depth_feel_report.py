#!/usr/bin/env python3
"""Depth-feel baseline vs span-gain measurement (owner 17:07, 190v).

For each real shot: the CURRENT default comfort policy (shot_comfort:
baseline derived from the shot median alone) vs the F3 span policy
(ShotComfortSpan: gain from the shot's own disparity quantiles, mirror
of Sources/gor/gor/ThreeD.swift ShotComfort.swift section, ShotComfortSpan span). Both keep the same comfort
budgets (crossed <= 2 deg, uncrossed >= -1 deg); the span policy makes
flat shots USE the budget instead of leaving it empty.

Metric per shot (analytic, exact atan formula over the full metric
depth maps - no rendering):
  scale/gain      effective baseline as a fraction/multiple of the IPD
  span_deg        p5..p95 disparity span on screen (the depth feel)
  crossed_max     max crossed disparity (deg) at the near clamp
  clamped_frac    fraction of pixels the near clamp touches
Run: python3 tools/depth_analysis/depth_feel_report.py
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import comfort
import numpy as np

GOLD = os.path.join(HERE, "golden", "entry_cg_vr180")


def load_golden():
    from prepare_film import D_SCALE, read_depth_hevc
    meta = json.load(open(os.path.join(GOLD, "depth_shot_00000.json")))
    inv, _ = read_depth_hevc(os.path.join(GOLD, "depth_shot_00000.mp4"),
                             size=(meta["depth_height"], meta["depth_width"]))
    z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
    return z, meta


def shot_row(name, z):
    base = comfort.shot_comfort([z.reshape(-1, z.shape[-2], z.shape[-1])[i]
                                 for i in range(0, z.shape[0], 8)]) \
        if z.ndim == 3 else comfort.shot_comfort([z])
    frames = [z] if z.ndim == 2 else list(z)
    span = comfort.shot_comfort_span(frames)
    zc = base["convergence_m"]
    zb = np.where(z > 0, np.maximum(z, base["z_near"]), 0.0)
    zs = np.where(z > 0, np.maximum(z, span["near_clamp_m"]), 0.0)
    d_base = comfort.disp_deg(zb[zb > 0], zc, base["ipd_eff"])
    d_span = comfort.disp_deg(zs[zs > 0], zc, span["ipd_eff"])
    row = {"shot": name, "z_c": zc,
           "base_scale": base["depth_scale"], "span_gain": span["gain"],
           "span_clamped": span["clamped"],
           "base_span_deg": span["span_before_deg"],
           "span_span_deg": span["span_deg"],
           "meas_base_p95": float(np.percentile(d_base, 95)
                                  - np.percentile(d_base, 5)),
           "meas_span_p95": float(np.percentile(d_span, 95)
                                  - np.percentile(d_span, 5)),
           "base_crossed_max": float(d_base.max()),
           "span_crossed_max": float(d_span.max()),
           "span_uncrossed_min": float(d_span.min()),
           "base_clamped_frac": float((z > 0).any() and
                                      (z < base["z_near"]).mean()),
           "span_clamped_frac": float((z < span["near_clamp_m"]).mean())}
    return row


def fmt(r):
    return ("| {shot} | {z_c:.2f} | {base_scale:.2f} | {span_gain:.2f} | "
            "{base_span_deg:.2f} | {span_span_deg:.2f} | "
            "{meas_base_p95:.2f} | {meas_span_p95:.2f} | "
            "{span_crossed_max:+.2f} | {span_uncrossed_min:+.2f} | "
            "{span_clamped_frac:.3f} |".format(**r))


def main():
    rows = []
    z, meta = load_golden()
    rows.append(shot_row("CG golden 48f 640x360", z))
    live = os.environ.get("GOR_LIVE_ENTRY", "/tmp/bench190v/entry")
    if os.path.isdir(live):
        import subprocess
        from prepare_film import D_SCALE, V_INV_MAX
        m = json.load(open(os.path.join(live, "depth_shot_00000.json")))
        w, h = m["depth_width"], m["depth_height"]
        mp4 = os.path.join(live, "depth_shot_00000.mp4")
        d = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", mp4, "-vf", "fps=3",
             "-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-"],
            capture_output=True)
        pr = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height", "-of", "json", mp4],
            capture_output=True, text=True)
        i0 = json.loads(pr.stdout)["streams"][0]
        wp, hp = int(i0["width"]), int(i0["height"])
        raw = np.frombuffer(d.stdout, dtype=np.uint16)
        words = hp * wp + 2 * (hp // 2) * (wp // 2)
        n = raw.size // words
        zl = np.empty((n, h, w), np.float32)
        for i in range(n):
            yy = raw[i * words:i * words + hp * wp].reshape(hp, wp)[:h, :w]
            yy = yy.astype(np.float32) / 1023.0 * V_INV_MAX
            zl[i] = np.where(yy > 0, D_SCALE / np.maximum(yy, 1e-9), 0.0)
        rows.append(shot_row("live 207f 720p (fps=3)", zl))
    hdr = ("| shot | z_c m | base scale | span gain | span base deg | "
           "span new deg | meas p5-95 base | meas p5-95 span | crossed max "
           "| uncrossed min | near-clamped |")
    sep = "|" + "---|" * 11
    print("\n".join([hdr, sep] + [fmt(r) for r in rows]))
    for r in rows:
        assert r["span_gain"] >= r["base_scale"], r
        assert r["span_crossed_max"] <= comfort.NEAR_BUDGET + 0.05, r
        assert r["span_uncrossed_min"] >= -comfort.FAR_BUDGET - 0.05, r
    return rows


if __name__ == "__main__":
    main()
