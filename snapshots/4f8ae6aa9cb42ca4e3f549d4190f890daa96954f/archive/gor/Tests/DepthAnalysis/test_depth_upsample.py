"""Depth box upsample pins (contract s24).

Ungated:
- canonical inverse-plane bilinear == the parity fixture exactly
- canonical == cv2.INTER_LINEAR on the inverse plane (fp32 tolerance)
- semantics: invalid tap = far, constant field exact, identity exact
- the letterboxed CG golden re-renders to its pinned hash (depth
  stored at the 266x150 box, upsampled in the render path)
Gated (GOR_FULL_GOLDEN + GOR_LIVE_ENTRY): live operator comparison
medians for the canonical operator stay sub-LSB (rel_med <= 0.003,
edge band <= 0.012, SBS diff <= 1.0 LSB on frame 0).

Run: python3 Tests/DepthAnalysis/test_depth_upsample.py
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))


def main():
    import cv2
    import depth_upsample as du

    fx = json.load(open(os.path.join(HERE, "parity", "depth_upsample.json")))
    z = np.array(fx["box"])
    out = du.upsample(z, fx["out_w"], fx["out_h"])
    assert np.allclose(out, np.array(fx["out"]), atol=1e-6), "fixture"

    rng = np.random.default_rng(7)
    z2 = rng.uniform(0.5, 40, (150, 266))
    z2[3:6, 10:20] = 0.0
    a, b = du.upsample(z2, 640, 360), du.upsample_cv2(z2, 640, 360)
    m = (a > 0) & (b > 0)
    assert np.max(np.abs(a[m] - b[m]) / b[m]) < 1e-4, "cv2 parity"
    assert bool(((a == 0) == (b == 0)).all()), "zero regions"
    assert np.allclose(du.upsample(np.full((9, 16), 3.0), 33, 19), 3.0)
    assert np.allclose(du.upsample(z2[:8, :8], 8, 8), z2[:8, :8])
    far = du.upsample(np.array([[2.0, 0.0]]), 4, 1)
    assert far[0, 1] > 2.0 and du.upsample(np.zeros((1, 2)), 4, 1).max() == 0
    assert du.compatible(266, 150, 640, 360) \
        and not du.compatible(266, 154, 640, 360) \
        and not du.compatible(640, 360, 266, 150)
    print("depth_upsample: fixture + cv2 parity + semantics [PASS]")

    gold = os.path.join(HERE, "..", "..", "tools", "depth_analysis",
                        "golden", "entry_cg_letterbox")
    man = json.load(open(os.path.join(gold, "render_manifest.json")))
    meta = json.load(open(os.path.join(gold, "depth_shot_00000.json")))
    assert (meta["depth_width"], meta["depth_height"]) == (266, 150)
    assert (meta["source_width"], meta["source_height"]) == (640, 360)
    from reference_render import golden_manifest, render_shot_sbs
    full = os.environ.get("GOR_FULL_GOLDEN") == "1"
    sbs, info = render_shot_sbs(gold, 0, max_frames=None if full else 1)
    man2 = golden_manifest(sbs, info)
    if full:
        assert man2["sequence_sha256"] == man["sequence_sha256"]
    assert man2["frame_sha256"][0] == man["frame_sha256"][0]
    print(f"letterboxed golden: hash-locked re-render [PASS] "
          f"(seq {man['sequence_sha256'][:16]})")

    entry = os.environ.get("GOR_LIVE_ENTRY", "/tmp/bench190v/entry")
    if not (full and os.path.isdir(entry)):
        print("live operator tier SKIPPED (GOR_FULL_GOLDEN + entry)")
        return
    # live canonical-operator medians stay sub-LSB (measured: rel_med
    # 0.0013, edge 0.0058, SBS 0.49-0.86 LSB on f0/103/206)
    import math
    import subprocess
    from prepare_film import D_SCALE, V_INV_MAX
    from reference_render import render_frame_sbs, theta_h_for, eye_n_for
    meta = json.load(open(os.path.join(entry, "depth_shot_00000.json")))
    W, H = meta["source_width"], meta["source_height"]
    ft = json.load(open(os.path.join(entry, "fov_track.json")))
    th = theta_h_for(75.0, math.radians(ft["shots"][0]["hfov_deg"]), W / H)
    ow = eye_n_for(H)

    def grab(mp4, k, pix):
        return subprocess.run(
            ["ffmpeg", "-v", "error", "-i", os.path.join(entry, mp4),
             "-vf", f"select=eq(n\\,{k})", "-frames:v", "1", "-f",
             "rawvideo", "-pix_fmt", pix, "-"], capture_output=True).stdout
    raw = np.frombuffer(grab("depth_shot_00000.mp4", 0, "yuv420p10le"),
                        dtype=np.uint16)
    inv = raw[:H * W].reshape(H, W).astype(np.float64) / 1023.0 * V_INV_MAX
    z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
    raw = np.frombuffer(grab("source_shot_00000.mp4", 0, "yuv420p"),
                        dtype=np.uint8)
    rgb = cv2.cvtColor(raw.reshape(H * 3 // 2, W), cv2.COLOR_YUV2RGB_I420)
    zb = du.downsample_to_box(z, 266, 150)
    zup = du.upsample(zb, W, H)
    vref, vup = du.inv_of(z), du.inv_of(zup)
    vmed = max(np.median(vref[vref > 0]), 1e-9)
    rel = np.abs(vup - vref) / vmed
    emag = np.hypot(*np.gradient(vref))
    band = emag > np.percentile(emag, 90)
    ref = render_frame_sbs(rgb, z, th, out_w=ow, out_h=ow, surround="soft")
    sbs = render_frame_sbs(rgb, zup, th, out_w=ow, out_h=ow, surround="soft")
    d = float(np.abs(sbs.astype(float) - ref.astype(float)).mean())
    assert np.median(rel) <= 0.003 and np.median(rel[band]) <= 0.012
    assert d <= 1.0, d
    print(f"live canonical: rel {np.median(rel):.4f}, edge "
          f"{np.median(rel[band]):.4f}, SBS {d:.3f} LSB [PASS]")


if __name__ == "__main__":
    main()
