"""Parity test: PyTorch streaming reference (fp32, upstream 4f5ae23) vs
vda-stream fp16 ONNX export — same checkpoint, same frames, same window logic.

Runs both drivers over a synthetic 20-frame sequence at the export resolution
and asserts per-frame agreement within fp16 tolerance.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

from onnx_stream import OnnxVdaStream
from torch_stream_ref import TorchVdaStream
from vda_stream_common import EXPORT_H, EXPORT_W

MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
CKPT = os.path.join(MODELS, "video_depth_anything_vits.pth")
if not os.path.exists(CKPT):
    print("SKIP: checkpoint not found at", CKPT, "(set S4_MODELS)")
    sys.exit(0)
_repo = os.environ.get("VDA_REPO", os.path.expanduser("~/s4/190t/vda"))
if not os.path.exists(_repo):
    print("SKIP: VDA_REPO clone not found (set VDA_REPO)")
    sys.exit(0)
N_FRAMES = 20
# fp16 export vs fp32 reference: allow 2% of the reference depth range per frame
REL_TOL = 0.02


def synth_frame(t):
    """Moving gradient + rolling ball, export resolution, uint8 RGB."""
    y, x = np.mgrid[0:EXPORT_H, 0:EXPORT_W].astype(np.float32)
    img = np.stack([(x + 3 * t) % EXPORT_W / EXPORT_W * 255,
                    (y + t) % EXPORT_H / EXPORT_H * 255,
                    np.full_like(x, 64 + (t * 7) % 128)], axis=-1)
    cx, cy, r = 40 + 5 * t, 60 + 2 * t, 18
    img[(x - cx) ** 2 + (y - cy) ** 2 < r * r] = [255, 64, 32]
    return img.astype(np.uint8)


def main():
    onnx_d = OnnxVdaStream(MODELS)
    torch_d = TorchVdaStream(CKPT)
    worst = (0.0, -1)
    for t in range(N_FRAMES):
        f = synth_frame(t)
        d_onnx = onnx_d.process_frame(f)
        d_ref = torch_d.process_frame(f)
        rng = float(d_ref.max()) + 1e-6
        diff = float(np.abs(d_onnx - d_ref).max()) / rng
        worst = max(worst, (diff, t))
        print(f"frame {t:2d}: rel max abs diff {diff:.5f} (ref range {rng:.3f})")
    print(f"worst: {worst[0]:.5f} at frame {worst[1]}")
    assert worst[0] < REL_TOL, f"parity FAIL: rel diff {worst[0]:.5f} >= {REL_TOL}"
    print("PASS onnx vs pytorch-stream parity (same checkpoint, fp16 vs fp32)")


if __name__ == "__main__":
    main()
