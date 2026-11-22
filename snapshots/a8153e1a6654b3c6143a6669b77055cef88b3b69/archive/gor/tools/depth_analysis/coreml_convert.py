"""Convert VDA-S streaming pieces to CoreML fp16 (190t lane D, Mac-run kit).

Mirrors the vda-stream ONNX split (EmreGneri, upstream 4f5ae23) but targets
CoreML .mlpackage for the gor on-device path. Conversion runs on Linux;
EXECUTION of the .mlpackage requires macOS — outputs here are UNMEASURED and
go to kit/build with that label.

Pieces (all at the 154x266 export resolution):
  encoder   pixels [1,3,154,266]          -> feat1..4 [1,209,384]
  bootstrap feat1..4                       -> depth [1,1,154,266] + cache0..7 (T=1)
  stream    feat1..4 + cache0..7 (T=31)    -> depth + nextCache0..7 (T=1)
"""
import argparse
import os
import sys
import types

import numpy as np
import torch
import torch.nn as nn

if "torchvision" not in sys.modules:  # stub, see torch_stream_ref.py
    _tv = types.ModuleType("torchvision")
    _tvt = types.ModuleType("torchvision.transforms")

    class _Compose:
        def __init__(self, transforms):
            self.transforms = transforms

        def __call__(self, x):
            for t in self.transforms:
                x = t(x)
            return x

    _tvt.Compose = _Compose
    _tv.transforms = _tvt
    sys.modules["torchvision"] = _tv
    sys.modules["torchvision.transforms"] = _tvt

VDA_REPO = os.environ.get("VDA_REPO", os.path.expanduser("~/s4/190t/vda"))
sys.path.insert(0, VDA_REPO)

H, W = 154, 266
NCACHE = 8


def patch_bicubic_for_coreml(model):
    """coremltools lacks upsample_bicubic2d; DINOv2 uses it only for
    positional-embedding interpolation. Substitute bilinear FOR THE COREML
    TRACE ONLY (numerics differ slightly from the PyTorch reference; flagged
    as UNVERIFIED-DEVIATION in the kit, to be measured on the Mac)."""
    import math

    import torch.nn.functional as F

    vit = model.pretrained
    orig = vit.interpolate_pos_encoding

    def bilinear_interpolate_pos_encoding(x, w, h):
        # verbatim copy of upstream interpolate_pos_encoding (dinov2.py:179)
        # with ONLY the mode swapped bicubic -> bilinear
        previous_dtype = x.dtype
        npatch = x.shape[1] - 1
        N = vit.pos_embed.shape[1] - 1
        if npatch == N and w == h:
            return vit.pos_embed
        pos_embed = vit.pos_embed.float()
        class_pos_embed = pos_embed[:, 0]
        patch_pos_embed = pos_embed[:, 1:]
        dim = x.shape[-1]
        w0 = w // vit.patch_size
        h0 = h // vit.patch_size
        w0, h0 = w0 + vit.interpolate_offset, h0 + vit.interpolate_offset
        sqrt_N = math.sqrt(N)
        sx, sy = float(w0) / sqrt_N, float(h0) / sqrt_N
        patch_pos_embed = F.interpolate(
            patch_pos_embed.reshape(1, int(sqrt_N), int(sqrt_N), dim).permute(0, 3, 1, 2),
            scale_factor=(sx, sy),
            mode="bilinear",
            antialias=vit.interpolate_antialias,
        )
        assert int(w0) == patch_pos_embed.shape[-2]
        assert int(h0) == patch_pos_embed.shape[-1]
        patch_pos_embed = patch_pos_embed.permute(0, 2, 3, 1).view(1, -1, dim)
        return torch.cat((class_pos_embed.unsqueeze(0), patch_pos_embed), dim=1).to(previous_dtype)

    vit.interpolate_pos_encoding = bilinear_interpolate_pos_encoding
    return orig


class Encoder(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, pixels):
        feats = self.model.forward_features(pixels.unsqueeze(0))  # list of 4 (x, cls)
        return tuple(f[0] for f in feats)


class Head(nn.Module):
    """bootstrap (no cache) or stream (31-frame cache) head wrapper."""

    def __init__(self, model, with_cache):
        super().__init__()
        self.model = model
        self.with_cache = with_cache

    def forward(self, *args):
        feats = [(args[i], None) for i in range(4)]
        caches = list(args[4:]) if self.with_cache else None
        depth, new_caches = self.model.forward_depth(feats, (1, 1, 3, H, W), caches)
        return (depth,) + tuple(new_caches)


def convert(module, inputs, names_in, names_out, out_path, fp16=True):
    import coremltools as ct

    traced = torch.jit.trace(module, inputs)
    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name=n, shape=t.shape, dtype=np.float32)
                for n, t in zip(names_in, inputs)],
        outputs=[ct.TensorType(name=n) for n in names_out],
        compute_precision=ct.precision.FLOAT16 if fp16 else ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL,
    )
    ml.save(out_path)
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=os.path.expanduser(
        "~/s4/models/video_depth_anything_vits.pth"))
    ap.add_argument("--out", default=os.path.expanduser("~/s4/kit/build/coreml"))
    ap.add_argument("--piece", default="all", choices=["encoder", "bootstrap", "stream", "all"])
    ap.add_argument("--fp32", action="store_true")
    a = ap.parse_args()

    from video_depth_anything.video_depth_stream import VideoDepthAnything

    model = VideoDepthAnything(encoder="vits", features=64,
                               out_channels=[48, 96, 192, 384])
    model.load_state_dict(torch.load(a.checkpoint, map_location="cpu"), strict=True)
    model.eval()
    patch_bicubic_for_coreml(model)

    os.makedirs(a.out, exist_ok=True)
    pixels = torch.rand(1, 3, H, W)
    feats_t = Encoder(model)(pixels)
    cache_shapes = [(209, 31, 192), (209, 31, 192), (60, 31, 384), (60, 31, 384),
                    (209, 31, 64), (209, 31, 64), (836, 31, 64), (836, 31, 64)]
    caches_t = [torch.rand(*s) for s in cache_shapes]
    depth_names = ["depth"] + [f"cache{i}" for i in range(NCACHE)]
    feat_names = [f"feat{i+1}" for i in range(4)]

    pieces = []
    if a.piece in ("encoder", "all"):
        pieces.append(("encoder_fp16.mlpackage", Encoder(model), (pixels,),
                       ["pixels"], feat_names))
    if a.piece in ("bootstrap", "all"):
        pieces.append(("bootstrap_fp16.mlpackage", Head(model, False),
                       tuple(feats_t), feat_names, depth_names))
    if a.piece in ("stream", "all"):
        pieces.append(("stream_fp16.mlpackage", Head(model, True),
                       tuple(feats_t) + tuple(caches_t),
                       feat_names + [f"cache{i}" for i in range(NCACHE)],
                       ["depth"] + [f"nextCache{i}" for i in range(NCACHE)]))

    for fname, mod, ins, ni, no in pieces:
        with torch.no_grad():
            path = convert(mod, ins, ni, no, os.path.join(a.out, fname),
                           fp16=not a.fp32)
        print("wrote", path)


if __name__ == "__main__":
    main()
