"""Shot-aware windowed VDA-S depth runner (Tier-1 prepare-film analysis).

Uses the non-streaming VideoDepthAnything (windowed temporal inference,
INFER_LEN=32 with keyframe alignment) from upstream commit 4f5ae23, fp32 on
CPU. Per shot: depth is inferred independently (state resets at cuts, per
190u) and stored as fp16 .npz in the content-keyed cache (cache.py), so
prepare-film runs are resumable: existing shot files are skipped.

Model: depth-anything/Video-Depth-Anything-Small, Apache-2.0,
checkpoint video_depth_anything_vits.pth (sha256 recorded in 190t/README.md).
"""
import json
import os
import sys
import types

import cv2
import numpy as np

from cache import Cache  # noqa: F401  (re-exported for callers)

if "torchvision" not in sys.modules:  # see torch_stream_ref.py
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

import torch

VDA_REPO = os.environ.get("VDA_REPO", os.path.expanduser("~/s4/190t/vda"))
sys.path.insert(0, VDA_REPO)


def load_model(checkpoint):
    from video_depth_anything.video_depth import VideoDepthAnything

    m = VideoDepthAnything(encoder="vits", features=64,
                           out_channels=[48, 96, 192, 384])
    m.load_state_dict(torch.load(checkpoint, map_location="cpu"), strict=True)
    return m.eval()


def read_shot_frames_normalized(video_path, start, end, probe):
    """s34: frames [start, end) as uint8 RGB [T,H,W,3] at DISPLAY geometry.

    For rotated/anamorphic sources (colorprobe verdict fix): ffmpeg decodes
    with input autorotation (on by default), scales to square display
    pixels, and applies the explicit untagged-matrix rule so the depth
    input pairs pixel-for-pixel with the source proxy (write_source_hevc
    normalize). Plain sources keep using read_shot_frames (cv2) so existing
    numerics are untouched."""
    import subprocess
    import colorprobe
    w, h = colorprobe.normalized_size(probe)
    vf = (f"select='gte(n\\,{start})',setpts=PTS-STARTPTS,"
          f"scale={w}:{h}:flags=bicubic,setsar=1,"
          + colorprobe.rgb_decode_scale(probe))
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", video_path,
                          "-vf", vf, "-frames:v", str(end - start),
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True)
    a = np.frombuffer(out.stdout, dtype=np.uint8)
    n = a.size // (w * h * 3)
    if n == 0:
        return np.empty((0,))
    return a[:n * w * h * 3].reshape(n, h, w, 3)


def read_shot_frames(video_path, start, end):
    """Frames [start, end) as uint8 RGB array [T,H,W,3] via OpenCV."""
    cap = cv2.VideoCapture(video_path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, start)
    frames = []
    for _ in range(end - start):
        ok, f = cap.read()
        if not ok:
            break
        frames.append(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
    cap.release()
    return np.stack(frames) if frames else np.empty((0,))


@torch.no_grad()
def infer_shot_depth(model, frames, input_size=518):
    """Windowed temporal depth for one shot; returns float32 [T,H,W]."""
    return model.infer_video_depth(frames, 24, input_size=input_size,
                                   device="cpu", fp32=True)[0]


def prepare_film(video_path, shots, cache, checkpoint, input_size=518,
                 max_shots=None, progress=None):
    """Infer depth for every shot into the cache entry for video_path.

    shots: list of (first, last) INCLUSIVE from cuts.py. Resumable: shots already
    present in the cache entry are skipped. Returns (done, total).
    """
    entry = cache.entry(video_path, create=True)
    existing = set(os.listdir(entry.dir))
    model = None
    done = 0
    for i, (s, e) in enumerate(shots):
        name = f"vda_raw_shot_{i:05d}.npz"  # raw VDA relative depth, NOT the contract depth_shot_*.mp4
        if name in existing:
            done += 1
            continue
        if model is None:
            model = load_model(checkpoint)
        frames = read_shot_frames(video_path, s, e + 1)  # inclusive last
        if len(frames) == 0:
            continue
        depth = infer_shot_depth(model, frames, input_size=input_size)
        tmp = entry.path(name + ".tmp.npz")  # savez appends .npz itself
        np.savez_compressed(tmp, depth=depth.astype(np.float16),
                            start=s, end=e, input_size=input_size)
        os.replace(tmp, entry.path(name))
        entry.mark_prepared(s, e)  # inclusive, resume-safe
        done += 1
        if progress:
            progress(i, len(shots))
        if max_shots and done >= max_shots:
            break
    entry.touch_meta(model="Video-Depth-Anything-Small (Apache-2.0)",
                     checkpoint=os.path.basename(checkpoint),
                     window=32, mode="windowed-per-shot", shots=len(shots))
    return done, len(shots)
