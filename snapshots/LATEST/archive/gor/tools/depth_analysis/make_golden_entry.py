"""Build the committed mini parity fixture (CONTRACT-190v section 11):
tools/depth_analysis/golden/entry_mini/ - a complete prepared-shot entry
(depth mp4 + sidecar, source proxy mp4, fov_track.json) plus the golden
SBS manifest, all from crafted deterministic content. The Mac lane runs
its real pipeline on these exact bytes; no model weights or footage
needed. Deterministic: seeded rng content; the depth mp4 is x265 lossless
(bit-stable) and the source proxy bytes are committed (never re-encoded
for parity).

Usage: PYTHONPATH=tools/depth_analysis python3 tools/depth_analysis/make_golden_entry.py
"""
import json
import math
import os
import subprocess

import numpy as np

from prepare_film import D_SCALE, V_INV_MAX, write_depth_hevc, write_source_hevc
from reference_render import golden_manifest, render_shot_sbs

H, W, T, FPS = 36, 64, 2, 24.0
OUT = os.path.join(os.path.dirname(__file__), "golden", "entry_mini")


def craft():
    rng = np.random.default_rng(190)
    z = np.zeros((H, W))
    z[:, :] = 1.0 + (np.add.outer(np.arange(H), np.arange(W)) % 17) * 0.25
    z[4:8, 4:12] = 0.0           # masked block
    z[20:, 40:] = 0.4            # near foreground corner
    rgb = rng.integers(0, 256, (H, W, 3), dtype=np.uint8)
    return z, rgb


def main():
    os.makedirs(OUT, exist_ok=True)
    z, rgb = craft()
    inv = np.where(z > 0, D_SCALE / np.maximum(z, 1e-9), 0.0)
    inv = np.clip(inv, 0, V_INV_MAX).astype(np.float32)

    # source proxy: deterministic crafted video, committed bytes
    src = os.path.join(OUT, "_src_raw.mp4")
    raw = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-f", "rawvideo", "-s", f"{W}x{H}",
         "-pix_fmt", "rgb24", "-framerate", str(int(FPS)), "-i", "-",
         "-frames:v", str(T), "-vf", "format=yuv420p", "-c:v", "libx265",
         "-preset", "fast", "-crf", "18", "-y", src], stdin=subprocess.PIPE)
    raw.communicate(np.stack([rgb] * T).tobytes())
    assert raw.returncode == 0

    write_depth_hevc(os.path.join(OUT, "depth_shot_00000.mp4"),
                     np.stack([inv] * T), fps=FPS, start_frame=0)
    json.dump({"depth_width": W, "depth_height": H, "frames": T,
               "start_frame": 0, "fps": FPS, "start_pts": 0.0,
               "source_width": W, "source_height": H},
              open(os.path.join(OUT, "depth_shot_00000.json"), "w"), indent=2)
    write_source_hevc(os.path.join(OUT, "source_shot_00000.mp4"), src,
                      0, T, FPS)
    os.remove(src)
    json.dump({"shots": [{"shot": 0, "start": 0, "end": T, "frames": T,
                          "median_hfov_deg": 90.0, "hfov_deg": 90.0,
                          "confidence": 1.0}]},
              open(os.path.join(OUT, "fov_track.json"), "w"), indent=2)

    # golden SBS with Mac-default render params (contract 11), generated
    # through the SAME decode path the Mac uses (render_shot_sbs reads the
    # 10-bit depth mp4, so the manifest matches quantized depth exactly)
    frames, info = render_shot_sbs(OUT, 0, ipd=0.063, convergence_m=2.0,
                                   swap_eyes=True)
    n = info["eye_n"] if "eye_n" in info else info["out_w"]
    man = golden_manifest(frames, info)
    man["provenance"] = ("crafted deterministic entry (make_golden_entry.py, "
                         "rng seed 190); Mac-default render params")
    man["parity_params"] = {"ipd": 0.063, "depth_scale": 1.0,
                            "screen_deg": 75.0, "convergence_m": 2.0,
                            "swap_eyes": True, "eye_n": n}
    json.dump(man, open(os.path.join(OUT, "manifest.json"), "w"), indent=2)
    print("entry_mini written:", OUT, "seq", man["sequence_sha256"][:16])


if __name__ == "__main__":
    main()
