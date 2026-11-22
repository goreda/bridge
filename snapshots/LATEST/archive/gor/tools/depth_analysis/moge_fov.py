"""MoGe-2 metric depth + FoV runner (190t analysis lane C).

Model: Ruicheng/moge-2-vits-normal (MIT, repo sha 26b477f4), checkpoint
moge2_vits_normal.pt (sha256 recorded in 190t/README.md). Runs keyframes of a
shot, returns per-frame metric depth + horizontal FoV, and a per-shot median
FoV. Per 190t, FoV is tracked per shot (median), state resets at cuts.
"""
import os
import sys

import numpy as np
import torch

MOGE_REPO = os.environ.get("MOGE_REPO", os.path.expanduser("~/s4/190t/moge"))
sys.path.insert(0, MOGE_REPO)

# Stall-safe recovery: upstream scipy lm(x0=0, ftol=1e-3) stalls on
# exact-geometry scenes with large shift/z (contract s15). Patch before infer.
from moge_recovery import patch_moge  # noqa: E402



def load_moge(checkpoint):
    from moge.model.v2 import MoGeModel

    patch_moge()
    return MoGeModel.from_pretrained(checkpoint).eval()  # local .pt path, no network


@torch.no_grad()
def infer_frame(moge, frame_rgb, num_tokens=1200, resolution_level=5):
    """One RGB uint8 frame -> (metric depth [H,W] float32, fov_x degrees)."""
    img = torch.from_numpy(frame_rgb).permute(2, 0, 1).float() / 255.0
    out = moge.infer(img, num_tokens=num_tokens, resolution_level=resolution_level,
                     use_fp16=False)
    depth = out["depth"].float().cpu().numpy()
    fov_x = None
    if "intrinsics" in out and out["intrinsics"] is not None:
        K = out["intrinsics"].float().cpu().numpy()
        h, w = depth.shape
        fx = float(K[0, 0]) * w if K[0, 0] < 10 else float(K[0, 0])
        fov_x = float(np.degrees(2 * np.arctan(w / (2 * fx))))
    return depth, fov_x


def shot_fov_track(moge, frames, keyframe_stride=12, **kw):
    """Median FoV over a shot's keyframes; returns (median_fov, [fovs])."""
    fovs = []
    for i in range(0, len(frames), keyframe_stride):
        _, f = infer_frame(moge, frames[i], **kw)
        if f is not None:
            fovs.append(f)
    return (float(np.median(fovs)) if fovs else None), fovs
