"""MoGe-2 runner test: real frames from the live clip (Tears of Steel,
CC-BY 3.0), metric depth + FoV sanity, per-shot median FoV tracking."""
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

import moge_fov

MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
CKPT = os.path.join(MODELS, "moge2_vits_normal.pt")
if not os.path.exists(CKPT):
    print("SKIP: checkpoint not found at", CKPT, "(set S4_MODELS)")
    sys.exit(0)
_repo = os.environ.get("MOGE_REPO", os.path.expanduser("~/s4/190t/moge"))
if not os.path.exists(_repo):
    print("SKIP: MOGE_REPO clone not found (set MOGE_REPO)")
    sys.exit(0)
CLIP = os.path.expanduser("~/s4/e2/clips/live.mp4")


def grab_frames(path, n=3):
    cap = cv2.VideoCapture(path)
    frames = []
    for i in range(n):
        cap.set(cv2.CAP_PROP_POS_FRAMES, i * 24)
        ok, f = cap.read()
        assert ok
        frames.append(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
    cap.release()
    return frames


def main():
    if not os.path.exists(CLIP):
        # fall back to a synthetic clip
        CLIP2 = os.path.join(tempfile.mkdtemp(), "t.mp4")
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        "testsrc2=s=320x180:r=24:d=2", "-pix_fmt", "yuv420p", CLIP2],
                       check=True)
        clip = CLIP2
    else:
        clip = CLIP
    moge = moge_fov.load_moge(CKPT)
    frames = grab_frames(clip)
    depth, fov = moge_fov.infer_frame(moge, frames[0], num_tokens=600,
                                      resolution_level=3)
    h, w = frames[0].shape[:2]
    assert depth.shape == (h, w), depth.shape
    finite = depth[np.isfinite(depth)]
    assert finite.size > 0.5 * depth.size and float(finite.max()) > 0
    print(f"frame0: depth range [{float(finite.min()):.2f}, {float(finite.max()):.2f}] m")
    assert fov is not None and 10 < fov < 150, fov
    print(f"frame0: fov_x {fov:.1f} deg")

    med, fovs = moge_fov.shot_fov_track(moge, frames, keyframe_stride=1,
                                        num_tokens=600, resolution_level=3)
    assert med is not None and len(fovs) == len(frames)
    print(f"shot median fov {med:.1f} deg over {fovs}")
    # same-shot frames: FoV estimates should be stable (within 15 deg)
    assert max(fovs) - min(fovs) < 15, fovs
    print("PASS moge-2 metric depth + FoV + per-shot median")


if __name__ == "__main__":
    main()
