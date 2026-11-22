"""VDA stream aspect policy pins (contract s22).

Gated on GOR_MODELS=1 + the ONNX fp16 stream export + the CG clip
(not committed). Runs the five aspect treatments through the real
154x266 stream and pins the measured policy facts:

- letterbox is near-neutral: SQ-l and W-l inverse-depth scale vs the
  16:9 control within [0.95, 1.12], log-depth Pearson r >= 0.95
- the plain stretch is measurably biased on square sources: SQ-s
  median ratio <= 0.93 (measured 0.859) AND spatially non-uniform
  (3x3 grid spread >= 0.10, measured 0.78..1.01) - a distortion
  per-shot alignment cannot absorb, which is why the kit manifest
  mandates letterbox (vda_aspect_rule)
- 2.39:1 stretch bias stays mild: |W-s ratio - 1| <= 0.05 (1.017)

Run: GOR_MODELS=1 python3 Tests/DepthAnalysis/test_aspect_bias.py
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))


def main():
    if os.environ.get("GOR_MODELS") != "1":
        print("test_aspect_bias: SKIPPED (set GOR_MODELS=1; needs the "
              "ONNX stream export + CG frames)")
        return
    import cv2
    import aspect_bias as ab

    frames = np.load(ab.CG_FRAMES)
    ts = ab.treatments(frames)
    depths = {n: ab.run_stream(ab.MODELS, f) for n, f in ts.items()}
    sq_reg = ab.region((360, 640), (0, 360, 140, 500),
                       (ab.EXPORT_H, ab.EXPORT_W))
    w_reg = ab.region((360, 640), (46, 314, 0, 640),
                      (ab.EXPORT_H, ab.EXPORT_W))
    a_sq = depths["A16"][:, sq_reg[0], sq_reg[1]]
    a_w = depths["A16"][:, w_reg[0], w_reg[1]]

    sq_l = ab.compare(depths["SQ-l"][:, sq_reg[0], sq_reg[1]], a_sq)
    w_l = ab.compare(depths["W-l"][:, w_reg[0], w_reg[1]], a_w)
    assert 0.95 <= sq_l["ratio_med"] <= 1.12 and sq_l["logr_med"] >= 0.95, sq_l
    assert 0.95 <= w_l["ratio_med"] <= 1.12 and w_l["logr_med"] >= 0.95, w_l

    sq_s = np.stack([cv2.resize(d, (a_sq.shape[2], a_sq.shape[1]),
                                interpolation=cv2.INTER_CUBIC)
                     for d in depths["SQ-s"]])
    w_s = np.stack([cv2.resize(d, (a_w.shape[2], a_w.shape[1]),
                               interpolation=cv2.INTER_CUBIC)
                    for d in depths["W-s"]])
    s_sq = ab.compare(sq_s, a_sq)
    s_w = ab.compare(w_s, a_w)
    assert s_sq["ratio_med"] <= 0.93, s_sq
    assert abs(s_w["ratio_med"] - 1.0) <= 0.05, s_w

    r = np.median(sq_s / np.maximum(a_sq, 1e-9), axis=0)
    h, w = r.shape
    grid = [float(np.median(r[gy * h // 3:(gy + 1) * h // 3,
                             gx * w // 3:(gx + 1) * w // 3]))
            for gy in range(3) for gx in range(3)]
    assert max(grid) - min(grid) >= 0.10, grid  # non-uniform distortion

    print(f"test_aspect_bias: PASS (letterbox SQ-l {sq_l['ratio_med']:.3f}/"
          f"r {sq_l['logr_med']:.3f}, W-l {w_l['ratio_med']:.3f}/r "
          f"{w_l['logr_med']:.3f}; stretch SQ-s {s_sq['ratio_med']:.3f} "
          f"grid {min(grid):.2f}..{max(grid):.2f}, W-s "
          f"{s_w['ratio_med']:.3f})")


if __name__ == "__main__":
    main()
