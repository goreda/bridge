"""Temporal stability pins (contract s21).

CG golden tier (ungated, <30s): the committed 48-frame entry must stay
at the 10-bit quantisation floor - depth second-difference median
<= 0.6% relative, rendered disparity second-difference median
<= 0.03 px / p95 <= 0.04 px (measured 0.44% / 0.018 / 0.026).

Live tier (gated on the bench entry, GOR_LIVE_ENTRY): real footage must
stay sub-pixel: depth median <= 2.0% / p95 <= 6%, disparity median
<= 0.12 px / p95 <= 0.35 px at 720 canvas (measured 1.6% / 4.8% /
0.081 / 0.249). 0.5 px disparity is the visible-flicker line.

Run: python3 Tests/DepthAnalysis/test_flicker.py
"""
import json
import math
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GOLD = os.path.join(HERE, "..", "..", "tools", "depth_analysis", "golden",
                    "entry_cg_vr180")
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))


def entry_theta(entry_dir, meta):
    import json as _json
    from reference_render import theta_h_for
    ft = _json.load(open(os.path.join(entry_dir, "fov_track.json")))
    return theta_h_for(75.0, math.radians(ft["shots"][0]["hfov_deg"]),
                       meta["source_width"] / meta["source_height"])


def main():
    import flicker
    from prepare_film import D_SCALE, read_depth_hevc
    from reference_render import eye_n_for

    meta = json.load(open(os.path.join(GOLD, "depth_shot_00000.json")))
    inv, _ = read_depth_hevc(
        os.path.join(GOLD, "depth_shot_00000.mp4"),
        size=(meta["depth_height"], meta["depth_width"]))
    z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
    th = entry_theta(GOLD, meta)
    ow = eye_n_for(meta["source_height"])
    dj = flicker.depth_jitter(inv)
    pj = flicker.disparity_jitter(z, th, out_w=ow)
    assert dj["median"] <= 0.006, dj
    assert pj["median"] <= 0.03 and pj["p95"] <= 0.04, pj
    print(f"CG: depth {dj['median']:.5f} rel, disparity "
          f"{pj['median']:.4f}/{pj['p95']:.4f} px - at quant floor [PASS]")

    entry = os.environ.get("GOR_LIVE_ENTRY", "/tmp/bench190v/entry")
    if not os.path.isdir(entry):
        print("live tier SKIPPED (no bench entry; set GOR_LIVE_ENTRY)")
        return
    meta = json.load(open(os.path.join(entry, "depth_shot_00000.json")))
    w, h = meta["depth_width"], meta["depth_height"]
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams",
                         "v:0", "-show_entries", "stream=width,height",
                         "-of", "json",
                         os.path.join(entry, "depth_shot_00000.mp4")],
                        capture_output=True, text=True)
    inf = json.loads(pr.stdout)["streams"][0]
    wp, hp = int(inf["width"]), int(inf["height"])
    from prepare_film import V_INV_MAX
    d = subprocess.run(["ffmpeg", "-v", "error", "-i",
                        os.path.join(entry, "depth_shot_00000.mp4"),
                        "-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-"],
                       capture_output=True)
    raw = np.frombuffer(d.stdout, dtype=np.uint16)
    words = hp * wp + 2 * (hp // 2) * (wp // 2)
    n = raw.size // words
    th = entry_theta(entry, meta)
    ow = eye_n_for(meta["source_height"])
    win, d2d, d2p = [], [], []
    for i in range(n):
        y = raw[i * words: i * words + hp * wp].reshape(hp, wp)[:h, :w]
        inv = y.astype(np.float32) / 1023.0 * V_INV_MAX
        z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
        disp = flicker.disparity_field(z, th, out_w=ow).astype(np.float32)
        win.append((inv, disp, inv > 0))
        if len(win) == 3:
            v = win[0][2] & win[1][2] & win[2][2]
            if v.any():
                med = max(np.median(win[1][0][win[1][0] > 0]), 1e-9)
                d2d.append(float(np.median(
                    np.abs(win[0][0] - 2 * win[1][0] + win[2][0])[v])) / med)
                d2p.append(float(np.median(
                    np.abs(win[0][1] - 2 * win[1][1] + win[2][1])[v])))
            win.pop(0)
    dm, dp95 = float(np.median(d2d)), float(np.percentile(d2d, 95))
    pm, pp95 = float(np.median(d2p)), float(np.percentile(d2p, 95))
    assert dm <= 0.02 and dp95 <= 0.06, (dm, dp95)
    assert pm <= 0.12 and pp95 <= 0.35, (pm, pp95)
    print(f"LIVE: depth {dm:.5f}/{dp95:.5f} rel, disparity "
          f"{pm:.4f}/{pp95:.4f} px ({n} frames) - sub-pixel [PASS]")


if __name__ == "__main__":
    main()
