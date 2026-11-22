"""Measure fp16-vs-fp32 deviation on real frames (contract §13).

Two probes:
  vda  - full VDA-S streaming pipeline, ONNX-fp16 (onnxruntime CPU) vs
         torch-fp32 reference, over N sequential frames (streaming cache
         warm-up included). Proxy for the CoreML fp16 packages, which
         share the same quantization; CoreML runtime itself executes on
         macOS only.
  moge - MoGe-2 forward() in full-fp16 (weights+activations) vs fp32 on
         one real frame: depth rel dev, correlation, metric_scale dev.

Both are Linux-runnable measurements of the quantization error; the
backend-lowering risk (CoreML op substitution, e.g. bicubic->bilinear
pos-embed in the VDA encoder) is separate and Mac-verified only.
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def run_vda(frames_path, n_frames):
    from onnx_stream import OnnxVdaStream
    from torch_stream_ref import TorchVdaStream

    frames = np.load(frames_path, mmap_mode="r")
    n_frames = min(n_frames, frames.shape[0])
    ref = TorchVdaStream(os.path.expanduser(
        "~/s4/models/video_depth_anything_vits.pth"))
    onx = OnnxVdaStream(os.path.expanduser("~/s4/models"))
    rels, corrs = [], []
    for i in range(n_frames):
        d_ref = ref.process_frame(np.asarray(frames[i]))
        d_onx = onx.process_frame(np.asarray(frames[i]))
        a = d_ref.astype(np.float64).ravel()
        b = d_onx.astype(np.float64).ravel()
        rels.append(float(np.mean(np.abs(a - b) / (np.abs(a) + np.abs(b) + 1e-12))))
        corrs.append(1.0 - float(np.corrcoef(a, b)[0, 1]))
    rels, corrs = np.array(rels), np.array(corrs)
    print(f"vda N={n_frames} rel dev mean {rels.mean()*100:.3f}% "
          f"p95 {np.percentile(rels, 95)*100:.3f}% max {rels.max()*100:.3f}% "
          f"1-corr mean {corrs.mean()*100:.4f}%")


def run_moge(frames_path, frame_index, tw=518, th=518):
    import torch

    moge_repo = os.environ.get("MOGE_REPO", os.path.expanduser("~/s4/190t/moge"))
    sys.path.insert(0, moge_repo)
    from moge.model.v2 import MoGeModel

    import copy
    from PIL import Image

    frame = np.load(frames_path, mmap_mode="r")[frame_index]
    img = np.asarray(Image.fromarray(np.asarray(frame)).resize((tw, th)))
    x = torch.from_numpy(img[None]).permute(0, 3, 1, 2).float() / 255.0
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    x = (x - mean) / std

    ckpt = os.path.expanduser("~/s4/models/moge2_vits_normal.pt")
    m32 = MoGeModel.from_pretrained(ckpt).eval()
    with torch.no_grad():
        nt = (tw // 14) * (th // 14)
        o32 = m32.forward(x, num_tokens=nt)
    m16 = copy.deepcopy(m32).half()
    del m32
    with torch.no_grad():
        o16 = m16.forward(x.half(), num_tokens=nt)
    z32 = o32["points"][0, ..., 2].double()
    z16 = o16["points"][0, ..., 2].double()
    finite = torch.isfinite(z32) & torch.isfinite(z16)
    a, b = z32[finite], z16[finite]
    rel = ((a - b).abs() / (a.abs() + b.abs() + 1e-9)).mean()
    corr = torch.corrcoef(torch.stack([a.ravel(), b.ravel()]))[0, 1]
    ms32, ms16 = float(o32["metric_scale"]), float(o16["metric_scale"])
    print(f"moge depth rel dev {float(rel)*100:.3f}% corr {float(corr):.6f} "
          f"metric_scale dev {abs(ms32-ms16)/ms32*100:.3f}%")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("probe", choices=["vda", "moge"])
    ap.add_argument("--frames", default="/tmp/bencha/frames.npy")
    ap.add_argument("--n-frames", type=int, default=60)
    ap.add_argument("--frame-index", type=int, default=40)
    ap.add_argument("--shape", default="518x518")
    a = ap.parse_args()
    if a.probe == "vda":
        run_vda(a.frames, a.n_frames)
    else:
        tw, th = (int(v) for v in a.shape.split("x"))
        run_moge(a.frames, a.frame_index, tw, th)


if __name__ == "__main__":
    main()
