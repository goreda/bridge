"""Convert VDA-S WINDOWED (non-streaming) to CoreML fp16 (190w W4).

The windowed model is the upstream Video-Depth-Anything-Small forward
(video_depth.py, NOT the streaming fork): one call depth-processes a
32-frame window - [1,32,3,H,W] -> [1,32,H,W], H,W fixed at the kit grid
154x266 (the same letterbox grid as the streaming kit, so prepared
(windowed) and live (streaming) ranges share geometry and depth scale).

Windowing convention (upstream video_depth.py, the Mac runner mirrors it):
  INFER_LEN=32, OVERLAP=10, step=22; window i+1's first 10 input frames are
  replaced by window i's KEYFRAMES [0,12,24..31] frames; the tail is padded
  by repeating the last frame.

Conversion runs on Linux; EXECUTION of the .mlpackage requires macOS -
outputs here are UNMEASURED. Reference fixture (windowed_ref_fixture.npz)
carries one deterministic input window + the torch fp32 output so the Mac
verifies the package against the Linux reference before first use.

Run: PYTHONPATH=~/s4/190t/vda python3 tools/depth_analysis/windowed_convert.py
"""
import argparse
import os
import sys

import numpy as np
import torch
import torch.nn as nn

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coreml_convert import convert, patch_bicubic_for_coreml  # noqa: E402

H, W, T = 154, 266, 32          # kit grid + upstream INFER_LEN
OVERLAP = 10                    # upstream OVERLAP (step 22)
KEYFRAMES = [0, 12, 24, 25, 26, 27, 28, 29, 30, 31]  # upstream KEYFRAMES


class Windowed(nn.Module):
    """[1,32,3,H,W] -> [1,32,H,W] single-package form. OOMs the 2GB
    Linux converter at trace time (batch-32 DINO fp32); kept for Mac-side
    repackaging attempts."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, window):
        return self.model(window)


class WindowedEncoder(nn.Module):
    """Per-frame DINO encoder: pixels [B,3,H,W] -> feat1..4 [B,209,384].
    Traced at B=1, exposed as flexible batch 1..32 (trace at B=32 OOMs the
    Linux box); the Mac runner batches the window's 32 frames through it."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, pixels):
        idx = self.model.intermediate_layer_idx[self.model.encoder]
        feats = self.model.pretrained.get_intermediate_layers(
            pixels, idx, return_class_token=True)
        return tuple(f[0] for f in feats)


class WindowedHead(nn.Module):
    """Temporal head: feat1..4 [32,209,384] -> depth [1,32,H,W]."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, *args):
        feats = [(args[i], None) for i in range(4)]
        depth = self.model.head(feats, H // 14, W // 14, T)[0]
        import torch.nn.functional as F
        depth = F.interpolate(depth, size=(H, W), mode="bilinear",
                              align_corners=True)
        return torch.relu(depth).squeeze(1).unflatten(0, (1, T))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=os.path.expanduser(
        "~/s4/models/video_depth_anything_vits.pth"))
    ap.add_argument("--out", default=os.path.expanduser("~/s4/kit/build/coreml"))
    ap.add_argument("--piece", default="all",
                    choices=["encoder", "head", "windowed", "all"])
    ap.add_argument("--fp32", action="store_true")
    a = ap.parse_args()

    from video_depth_anything.video_depth import VideoDepthAnything

    model = VideoDepthAnything(encoder="vits", features=64,
                               out_channels=[48, 96, 192, 384])
    model.load_state_dict(torch.load(a.checkpoint, map_location="cpu"),
                          strict=True)
    model.eval()
    patch_bicubic_for_coreml(model)

    os.makedirs(a.out, exist_ok=True)
    feat_names = [f"feat{i+1}" for i in range(4)]
    if a.piece in ("encoder", "all"):
        import coremltools as ct
        enc = WindowedEncoder(model)
        traced = torch.jit.trace(enc, (torch.rand(1, 3, H, W),))
        ml = ct.convert(
            traced,
            inputs=[ct.TensorType(
                name="pixels",
                shape=ct.Shape((ct.RangeDim(1, T), 3, H, W)),
                dtype=np.float32)],
            outputs=[ct.TensorType(name=n) for n in feat_names],
            compute_precision=(ct.precision.FLOAT32 if a.fp32
                               else ct.precision.FLOAT16),
            minimum_deployment_target=ct.target.macOS14,
            compute_units=ct.ComputeUnit.ALL)
        p = os.path.join(a.out, "windowed_encoder_fp16.mlpackage")
        ml.save(p)
        print("wrote", p)
    if a.piece in ("head", "all"):
        feats_t = [torch.rand(T, 209, 384) for _ in range(4)]
        with torch.no_grad():
            p = convert(WindowedHead(model), tuple(feats_t), feat_names,
                        ["depth"],
                        os.path.join(a.out, "windowed_head_fp16.mlpackage"),
                        fp16=not a.fp32)
        print("wrote", p)

    # Linux-reference fixture for the Mac parity check: deterministic input
    # window (seeded) + torch fp32 reference output.
    g = torch.Generator().manual_seed(190)
    fix_in = torch.rand(1, T, 3, H, W, generator=g)
    with torch.no_grad():
        fix_out = model(fix_in)
    np.savez_compressed(os.path.join(a.out, "windowed_ref_fixture.npz"),
                        window=fix_in.numpy().astype(np.float32),
                        depth=fix_out.numpy().astype(np.float32),
                        h=H, w=W, t=T, overlap=OVERLAP,
                        keyframes=np.array(KEYFRAMES))
    print("wrote", os.path.join(a.out, "windowed_ref_fixture.npz"),
          "depth range", float(fix_out.min()), float(fix_out.max()))


if __name__ == "__main__":
    main()
