"""nunif iw3 synthesis weights -> CoreML fp16 kit (190w W3 tiers).

Converts the four gor-kit-nunif weights (owner-private Mac build only,
190w W1 licence ruling) into .mlpackage packages plus torch reference
fixtures, mirroring the windowed_convert.py kit contract:

  T3 row_flow_v3            [1,3,H,W] -> delta [1,2,H,W]
  T1/T2 mask_mlbw_l2_d1     [1,3,H,W] -> delta, layer_weight, hole_mask_logits
  T2  light_inpaint_v1      x,mask [1,·,H,W] -> out [1,3,H,W]
  T1  light_video_inpaint_v1 x,mask [12,·,H,W] -> out [12,3,H,W] (SEQ_LEN=12)

Boundaries (see kit_manifest.json for the runner contract):
- warp input x = (depth, divergence_feature, convergence_feature) per
  iw3.backward_warp.make_input_tensor(c=None); divergence/convergence are
  baked into the feature channels runner-side, never model inputs.
- inpaint packages sit at model.forward(x, mask, skip_i2i_offset=True);
  upstream preprocess (hole closing/dilation + gaussian mask blur) and
  cross-window overlap (BaseVideoInpaint, 3+3) stay runner-side.
- inputs must be pre-padded (replication) to multiples of 96; upstream
  always pads one full block and negative-crops, which CoreML rejects, so
  tracing runs with a slice-crop F.pad shim (numerically identical).

Conversion hosts:
- 768x1344 (720p + pad) fits a 2GB Linux box for the three small models
  with torch.inference_mode() tracing (autograd bookkeeping otherwise OOMs
  mask_mlbw).
- light_video_inpaint_v1 peaks ~1.74GB for a fp32 forward at 768x1344 and
  tracing doubles that; on this box it converts at 288x480, tracing in a
  separate process from fixture generation. On the owner Mac re-convert at
  production resolution:  python3 nunif_convert.py --only video --shape 768x1344

Usage:
  python3 nunif_convert.py [--out DIR] [--only TAG] [--shape HxW]
Tags: row_flow | mlbw | inpaint | video
"""
import argparse
import gc
import hashlib
import json
import os
import sys

import numpy as np
import torch
import torch.nn.functional as F

# --- trace-safe pad shim: negative "pad" (crop) -> slicing ----------------
_orig_pad = F.pad


def _pad_trace_safe(x, pad, mode="constant", value=0.0):
    pad = list(pad)
    if any(p < 0 for p in pad):
        assert mode == "constant", mode
        dims = x.dim()
        idx = [slice(None)] * dims
        pos_pad = []
        for i in range(len(pad) // 2):
            l, r = pad[2 * i], pad[2 * i + 1]
            d = dims - 1 - i
            if l < 0 or r < 0:
                idx[d] = slice((-l) if l < 0 else 0,
                               (x.shape[d] + r) if r < 0 else x.shape[d])
            pos_pad += [max(l, 0), max(r, 0)]
        x = x[tuple(idx)]
        if any(p > 0 for p in pos_pad):
            x = _orig_pad(x, pos_pad, mode=mode, value=value)
        return x
    return _orig_pad(x, pad, mode=mode, value=value)


F.pad = _pad_trace_safe
torch.nn.functional.pad = _pad_trace_safe

NUNIF = os.environ.get("NUNIF_SRC", os.path.expanduser("~/s4/190t/nunif"))
sys.path.insert(0, NUNIF)
os.chdir(NUNIF)  # nunif looks up resources relative to its root
import iw3.models  # noqa: E401  registers sbs.*/inpaint.* model names
from nunif.models import load_model  # noqa: E401

WEIGHTS = os.environ.get("GOR_NUNIF_WEIGHTS", os.path.expanduser("~/s4/models/nunif"))

MOD = 96  # LCM of the models' alignment (mlbw 32, row_flow 96, inpaints 64*4)


def _load(fname):
    return load_model(os.path.join(WEIGHTS, fname), weights_only=True,
                      device_ids=[-1])[0].eval()


def _delta_model(fname):
    m = _load(fname)
    m.delta_output = True
    return m


def _wrap_video(m):
    class Wrap(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x, mask):
            return self.m(x, mask, skip_i2i_offset=True)

    return Wrap(m)


MODELS = {
    # tag: (weights file, builder, n_batch, input kind)
    "row_flow": ("iw3_row_flow_v3_20250627.pth",
                 lambda: _delta_model("iw3_row_flow_v3_20250627.pth"), 1, "warp"),
    "mlbw": ("iw3_mask_mlbw_l2_d1_20250903.pth",
             lambda: _delta_model("iw3_mask_mlbw_l2_d1_20250903.pth"), 1, "warp"),
    "inpaint": ("iw3_light_inpaint_v1_20250919.pth",
                lambda: _wrap_video(_load("iw3_light_inpaint_v1_20250919.pth")), 1, "inpaint"),
    "video": ("iw3_light_video_inpaint_v1_20250919.pth",
              lambda: _wrap_video(_load("iw3_light_video_inpaint_v1_20250919.pth")),
              12, "inpaint"),
}
OUT_NAMES = {
    "row_flow": ["delta"],
    "mlbw": ["delta", "layer_weight", "hole_mask_logits"],
    "inpaint": ["out"],
    "video": ["out"],
}
DEFAULT_SHAPES = {"row_flow": (768, 1344), "mlbw": (768, 1344),
                  "inpaint": (768, 1344), "video": (288, 480)}


def make_inputs(tag, n, h, w, seed=190):
    g = torch.Generator().manual_seed(seed)
    if MODELS[tag][3] == "warp":
        x = torch.rand(n, 3, h, w, generator=g)
        return (x,), ["x"]
    x = torch.rand(n, 3, h, w, generator=g)
    mask = (torch.rand(n, 1, h, w, generator=g) > 0.8).float()
    return (x, mask), ["x", "mask"]


def convert(tag, out_dir, h, w):
    import coremltools as ct

    fname, builder, n, _ = MODELS[tag]
    model = builder()
    inputs, in_names = make_inputs(tag, n, h, w)
    out_names = OUT_NAMES[tag]

    with torch.inference_mode():
        outs = model(*inputs)
    if not isinstance(outs, (tuple, list)):
        outs = (outs,)
    fx = os.path.join(out_dir, f"nunif_{tag}_fp16_fixture.npz")
    np.savez_compressed(fx,
                        **{f"in_{n_}": t.numpy() for t, n_ in zip(inputs, in_names)},
                        **{f"out_{n_}": t.detach().numpy() for t, n_ in zip(outs, out_names)})
    del outs
    gc.collect()

    with torch.inference_mode():
        tr = torch.jit.trace(model, inputs, strict=False)
    del model
    gc.collect()

    ml = ct.convert(
        tr,
        inputs=[ct.TensorType(shape=t.shape, name=n_) for t, n_ in zip(inputs, in_names)],
        outputs=[ct.TensorType(name=n_) for n_ in out_names],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )
    del tr
    gc.collect()
    pkg = os.path.join(out_dir, f"nunif_{tag}_fp16.mlpackage")
    ml.save(pkg)
    return pkg, fx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/kit-nunif-coreml")
    ap.add_argument("--only", choices=list(MODELS), default=None)
    ap.add_argument("--shape", default=None,
                    help="HxW override (multiples of 96), e.g. 768x1344")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    tags = [args.only] if args.only else list(MODELS)
    for tag in tags:
        h, w = DEFAULT_SHAPES[tag]
        if args.shape:
            h, w = (int(v) for v in args.shape.split("x"))
        assert h % MOD == 0 and w % MOD == 0, f"shape must be a multiple of {MOD}"
        pkg, fx = convert(tag, args.out, h, w)
        print(f"{tag}: {pkg} + {fx}")
    print("done. Build kit_manifest.json with tools/depth_analysis/kit_hash.py "
          "content_sha256 values (see windowed_convert.py for the manifest shape).")


if __name__ == "__main__":
    main()
