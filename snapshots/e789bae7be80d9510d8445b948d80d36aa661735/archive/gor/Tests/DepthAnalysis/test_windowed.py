"""Test the shot-aware windowed VDA-S runner against the real vits checkpoint:
two synthetic shots, small input size, then a resume run that must skip."""
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

import cache as cache_mod
import vda_windowed

MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
CKPT = os.path.join(MODELS, "video_depth_anything_vits.pth")
if not os.path.exists(CKPT):
    print("SKIP: checkpoint not found at", CKPT, "(set S4_MODELS)")
    sys.exit(0)
_repo = os.environ.get("VDA_REPO", os.path.expanduser("~/s4/190t/vda"))
if not os.path.exists(_repo):
    print("SKIP: VDA_REPO clone not found (set VDA_REPO)")
    sys.exit(0)


def make_video(path):
    subprocess.run([
        "ffmpeg", "-y", "-v", "error",
        "-f", "lavfi", "-i", "testsrc2=s=140x84:r=8:d=2",
        "-f", "lavfi", "-i", "color=c=blue:s=140x84:r=8:d=2",
        "-filter_complex", "[0:v][1:v]concat=n=2:v=1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


def main():
    d = tempfile.mkdtemp()
    vid = os.path.join(d, "t.mp4")
    make_video(vid)
    c = cache_mod.Cache(os.path.join(d, "cache"))
    shots = [(0, 15), (16, 31)]  # inclusive, per cuts.py
    done, total = vda_windowed.prepare_film(
        vid, shots, c, CKPT, input_size=84)  # tiny input size for CPU test
    assert (done, total) == (2, 2), (done, total)
    entry = c.entry(vid)
    for i in range(2):
        z = np.load(entry.path(f"vda_raw_shot_{i:05d}.npz"))
        dep, s, e = z["depth"], int(z["start"]), int(z["end"])
        assert dep.shape == (e - s + 1, 84, 140), dep.shape
        assert dep.dtype == np.float16 and float(dep.max()) > 0
        print(f"shot {i}: frames [{s},{e}) depth max {float(dep.max()):.3f}")
    assert entry.prepared_ranges() == [[0, 31]], entry.prepared_ranges()  # adjacent shots merge
    assert entry.is_prepared(20) and entry.is_prepared(0) and not entry.is_prepared(31 + 1)
    # resume: everything prepared -> no model load, no work
    done2, _ = vda_windowed.prepare_film(vid, shots, c, CKPT, input_size=84)
    assert done2 == 2
    print("PASS windowed runner + resume (VDA-S vits checkpoint, fp32 CPU)")


if __name__ == "__main__":
    main()
