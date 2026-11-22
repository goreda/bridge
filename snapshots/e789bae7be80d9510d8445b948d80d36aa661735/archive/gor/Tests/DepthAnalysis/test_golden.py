"""Golden-harness test: synthetic stereo scene + real clip frames."""
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

import dibr_golden as G

rng = np.random.default_rng(3)


def textured(h=120, w=160):
    return (rng.uniform(0, 255, (h, w, 3))).astype(np.uint8)


def main():
    # 1) flat scene: no occlusion -> coverage must be ~1.0
    rgb = textured()
    depth = np.full((120, 160), 0.5, dtype=np.float32)
    nrm = G.DepthNormalizer()
    sbs, cov = G.sbs_frame(rgb, depth, nrm)
    assert sbs.shape == (120, 320, 3)
    assert cov > 0.995, cov
    print(f"PASS flat scene coverage {cov:.4f}")

    # 2) step depth (near square on far background): holes must fill, coverage high
    depth2 = np.full((120, 160), 0.2, dtype=np.float32)
    depth2[40:80, 60:100] = 0.9
    nrm2 = G.DepthNormalizer()
    sbs2, cov2 = G.sbs_frame(rgb, depth2, nrm2)
    assert cov2 > 0.97, cov2
    print(f"PASS occluding-square coverage {cov2:.4f}")

    # 3) cut reset: normalizer state must not leak across shots
    nrm3 = G.DepthNormalizer()
    G.sbs_frame(rgb, np.full((120, 160), 100.0, dtype=np.float32), nrm3)
    assert nrm3.lo is not None
    G.sbs_frame(rgb, np.full((120, 160), 5.0, dtype=np.float32), nrm3, is_cut=True)
    assert abs(nrm3.lo - 5.0) < 1e-6, nrm3.lo
    print("PASS cut reset")

    # 4) real frames from the live clip (Tears of Steel, CC-BY 3.0) with VDA
    #    windowed depth: end-to-end golden run
    clip = os.path.expanduser("~/s4/e2/clips/live.mp4")
    ckpt = os.path.join(os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models")),
                        "video_depth_anything_vits.pth")
    if os.path.exists(clip) and os.path.exists(ckpt):
        import vda_windowed
        model = vda_windowed.load_model(ckpt)
        frames = vda_windowed.read_shot_frames(clip, 100, 108)  # 8 real frames
        depth = vda_windowed.infer_shot_depth(model, frames, input_size=252)
        nrm4 = G.DepthNormalizer()
        covs = [G.sbs_frame(frames[i], depth[i], nrm4, is_cut=(i == 0))[1]
                for i in range(len(frames))]
        mean_cov = float(np.mean(covs))
        print(f"real 8-frame coverage: mean {mean_cov*100:.3f}% min {min(covs)*100:.3f}%")
        assert mean_cov > 0.98, mean_cov
        print("PASS golden run on real frames (VDA-S depth)")
    print("ALL GOLDEN HARNESS TESTS PASS")


if __name__ == "__main__":
    main()
