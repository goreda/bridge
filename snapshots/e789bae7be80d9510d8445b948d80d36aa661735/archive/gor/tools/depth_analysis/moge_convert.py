"""Convert MoGe-2 ViT-S to CoreML fp16 (190t Mac-run kit; contract §13).

Export boundary is MoGeModel.forward (raw network): focal recovery,
projection and metric-scale application are deliberately NOT in the
package - they port to Swift (least squares + grid math), which removes
the utils3d dependency from the Mac. infer() does not convert:
utils3d's meshgrid is unsupported by coremltools (patched here via
expand for anything that still hits it) and recover_focal_shift traces
into a concat with 0 values.

Conversion runs on Linux; EXECUTION of the .mlpackage requires macOS -
outputs are UNMEASURED on the target until the owner-Mac verification
run (contract §13). fp16 robustness was measured at torch level:
rel dev 0.022%, corr 0.999996 on a real frame (measure_fp16_dev.py).
"""
import argparse
import os
import sys

import numpy as np
import torch
import torch.nn as nn

MOGE_REPO = os.environ.get("MOGE_REPO", os.path.expanduser("~/s4/190t/moge"))
sys.path.insert(0, MOGE_REPO)

# Enumerated aspect shapes (contract s13 c3): the runner picks the package
# whose aspect matches the source; square = VR180 per-eye, 518x294 = 16:9.
# Tokens per shape = (W/14)*(H/14); 518 = 37 patches.
SHAPES = {"518x518": (518, 518), "518x294": (518, 294)}

# coremltools 9.0 rejects torch.meshgrid with non-1d traced inputs; the
# expand formulation below is mathematically identical and converts.
_orig_meshgrid = torch.meshgrid


def _safe_meshgrid(a, b, indexing="xy"):
    A = a.reshape(1, -1).expand(b.numel(), a.numel())
    B = b.reshape(-1, 1).expand(b.numel(), a.numel())
    return (A, B) if indexing == "xy" else (B, A)


torch.meshgrid = _safe_meshgrid

# coremltools also lacks upsample_bicubic2d; MoGe-2's DINOv2 backbone uses
# bicubic ONLY for positional-embedding interpolation on non-square token
# grids (518x294). Swap bicubic -> bilinear FOR THE TRACE ONLY (numerics
# differ slightly from the torch reference; flagged UNVERIFIED-DEVIATION
# in the kit, to be measured on the Mac - same class as the VDA-S patch).
_orig_interpolate = torch.nn.functional.interpolate


def _bilinear_for_coreml(*args, **kwargs):
    if kwargs.get("mode") == "bicubic":
        kwargs["mode"] = "bilinear"
    return _orig_interpolate(*args, **kwargs)


class MogeForward(nn.Module):
    """Raw MoGe-2 network at a fixed shape: image -> points/normal/mask/metric_scale."""

    def __init__(self, model, num_tokens):
        super().__init__()
        self.model = model
        self.num_tokens = num_tokens

    def forward(self, image):  # [1,3,H,W], ImageNet-normalised
        out = self.model.forward(image, num_tokens=self.num_tokens)
        return (out["points"], out["normal"], out["mask"].float(),
                out["metric_scale"].float().reshape(1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=os.path.expanduser(
        "~/s4/models/moge2_vits_normal.pt"))
    ap.add_argument("--out", default=None,
                    help="default ~/s4/kit/build/coreml/moge2_vits_<shape>_<prec>.mlpackage")
    ap.add_argument("--fp32", action="store_true")
    ap.add_argument("--shape", default="518x518", choices=sorted(SHAPES))
    a = ap.parse_args()

    w, h = SHAPES[a.shape]
    num_tokens = (w // 14) * (h // 14)
    prec = "fp32" if a.fp32 else "fp16"
    out_path = a.out or os.path.expanduser(
        f"~/s4/kit/build/coreml/moge2_vits_{a.shape}_{prec}.mlpackage")

    from moge.model.v2 import MoGeModel

    model = MoGeModel.from_pretrained(a.checkpoint).eval()
    image = torch.rand(1, 3, h, w)
    torch.nn.functional.interpolate = _bilinear_for_coreml
    try:
        with torch.no_grad():
            traced = torch.jit.trace(MogeForward(model, num_tokens), image)
    finally:
        torch.nn.functional.interpolate = _orig_interpolate

    import coremltools as ct

    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image", shape=(1, 3, h, w), dtype=np.float32)],
        outputs=[ct.TensorType(name=n)
                 for n in ["points", "normal", "mask", "metric_scale"]],
        compute_precision=ct.precision.FLOAT32 if a.fp32 else ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL,
    )
    ml.save(out_path)
    print("wrote", out_path, f"({w}x{h}, {num_tokens} tokens, {prec})")


if __name__ == "__main__":
    main()
