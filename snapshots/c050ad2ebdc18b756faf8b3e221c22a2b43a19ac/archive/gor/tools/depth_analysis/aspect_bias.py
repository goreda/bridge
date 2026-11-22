"""VDA 154x266 stream aspect policy: measure stretch bias (contract s22).

The stream preprocess (vda_stream_common.preprocess) is a plain
cv2.resize to 266x154 - a STRETCH for any source that is not ~16:9.
This tool measures the bias that stretch introduces on VR180-square
(1:1) and scope (2.39:1) content, against the aspect-correct
letterbox treatment, using the CG clip (known geometry, GT depth).

Treatments on the 640x360 CG frames:
  A16    original 16:9 (control; stretch to 266x154 is near-neutral,
         1.778 -> 1.727)
  SQ-s   central 360x360 square, stretched (current policy)
  SQ-l   same square letterboxed into the 16:9 canvas (aspect-correct)
  W-s    central 2.39:1 (640x268) crop, stretched
  W-l    same crop letterboxed into 16:9 (aspect-correct)

Letterbox content sits at the SAME pixel scale in the stream as the
16:9 control (canvas is the source canvas), so SQ-l/W-l depth should
match A16 on the common region; SQ-s/W-s deviation from A16 is the
stretch bias. Metrics: median inverse-depth ratio (scale shift) and
log-depth Pearson r on the common region, medians over post-warmup
frames.
"""
import json
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from onnx_stream import OnnxVdaStream
from vda_stream_common import EXPORT_H, EXPORT_W

MODELS = os.environ.get("GOR_MODELS_DIR", os.path.expanduser("~/s4/models"))
CG_FRAMES = os.environ.get("GOR_CG_FRAMES", "/tmp/benchcg/frames.npy")
WARMUP = 12          # stream cache warmup frames to skip
N_FRAMES = 24        # frames per treatment


def treatments(frames):
    sq = frames[:, :, 140:500]                       # 360x360
    wide = frames[:, 46:314, :]                      # 640x268 = 2.39:1
    sq_l = np.zeros_like(frames); sq_l[:, :, 140:500] = sq
    w_l = np.zeros_like(frames); w_l[:, 46:314, :] = wide
    return {"A16": frames, "SQ-s": sq, "SQ-l": sq_l,
            "W-s": wide, "W-l": w_l}


def run_stream(model_dir, frames):
    stream = OnnxVdaStream(model_dir)
    out = []
    for f in frames[:N_FRAMES]:
        out.append(stream.process_frame(f).astype(np.float32))
    return np.stack(out[WARMUP:])                    # [t,154,266]


def region(shape_src, crop, out_hw):
    """Source crop (y0,y1,x0,x1) in 640x360 -> output pixel region."""
    y0, y1, x0, x1 = crop
    oh, ow = out_hw
    sy, sx = oh / shape_src[0], ow / shape_src[1]
    return (slice(int(round(y0 * sy)), int(round(y1 * sy))),
            slice(int(round(x0 * sx)), int(round(x1 * sx))))


def compare(a, b):
    """Median inv-depth ratio + log Pearson r over valid px, per frame."""
    ratios, rs = [], []
    for fa, fb in zip(a, b):
        va, vb = fa > 0, fb > 0
        v = va & vb
        if v.sum() < 32:
            continue
        ratios.append(float(np.median(fa[v] / np.maximum(fb[v], 1e-9))))
        la, lb = np.log(fa[v]), np.log(fb[v])
        rs.append(float(np.corrcoef(la, lb)[0, 1]))
    return {"ratio_med": float(np.median(ratios)),
            "ratio_p95": float(np.percentile(ratios, 95)),
            "logr_med": float(np.median(rs))}


def main():
    frames = np.load(CG_FRAMES)
    assert frames.shape[1:] == (360, 640, 3)
    ts = treatments(frames)
    depths = {name: run_stream(MODELS, fr) for name, fr in ts.items()}
    sq_reg = region((360, 640), (0, 360, 140, 500), (EXPORT_H, EXPORT_W))
    w_reg = region((360, 640), (46, 314, 0, 640), (EXPORT_H, EXPORT_W))
    a_sq = depths["A16"][:, sq_reg[0], sq_reg[1]]
    a_w = depths["A16"][:, w_reg[0], w_reg[1]]
    res = {}
    # letterbox vs control on the common region: should be ~1.0 / ~1.0
    res["SQ-l vs A16"] = compare(
        depths["SQ-l"][:, sq_reg[0], sq_reg[1]], a_sq)
    res["W-l vs A16"] = compare(
        depths["W-l"][:, w_reg[0], w_reg[1]], a_w)
    # stretch bias: full-frame stretched vs the control common region,
    # resampled to the same grid
    sq_s = np.stack([cv2.resize(d, (a_sq.shape[2], a_sq.shape[1]),
                                interpolation=cv2.INTER_CUBIC)
                     for d in depths["SQ-s"]])
    w_s = np.stack([cv2.resize(d, (a_w.shape[2], a_w.shape[1]),
                               interpolation=cv2.INTER_CUBIC)
                    for d in depths["W-s"]])
    res["SQ-s vs A16 (stretch bias)"] = compare(sq_s, a_sq)
    res["W-s vs A16 (stretch bias)"] = compare(w_s, a_w)
    print(json.dumps(res, indent=2))
    return res


if __name__ == "__main__":
    main()
