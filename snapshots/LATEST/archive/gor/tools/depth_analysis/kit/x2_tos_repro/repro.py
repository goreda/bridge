#!/usr/bin/env python3
"""X2 goreda lane: independent Linux reproduction of the iw3 ToS reference renders (T1/T2/T3).

Inputs:
  --frames  raw rgb24 file with the 48 input frames at 320x180 (cut: ToS 720p frames 1440-1487,
            i.e. t=60.0s at 24fps; see README.md for the ffmpeg cut command)
  --depth   committed fixture ../x2_tos_reference/tos_depth_minmax_320x180_fp16.npz
  --tier    t1 | t2 | t3 | all
Environment: iw3 checkout at nagadomi/nunif b1548e8 on sys.path (NUNIF env or ./nunif),
torch CPU fp32, weights resolved by nunif load_model from the nunif release tag 0.0.0 URLs
(sha256-pinned in models/models.lock.tsv; verified 7/7 by independent download, see
../X2-VERIFY-20261109-goreda.md). One local compat edit for py3.10: typing.Self ->
typing_extensions.Self in iw3/base_inpaint.py.
Synthesis parameters (same as the A-D reference): divergence 2.0, convergence 1.0, steps 1,
synthetic_view="both", preserve_screen_border=False, inner/outer_dilation 0, enable_amp=False.
"""
import argparse, os, sys, subprocess, resource
import numpy as np
import torch

W, H, N = 320, 180, 48

def load_frames(path):
    a = np.fromfile(path, np.uint8).reshape(-1, H, W, 3)
    return torch.from_numpy(a.copy()).permute(0, 3, 1, 2).float() / 255.0

def save_sbs(left, right, out_rgb, out_final):
    sbs = torch.cat([left, right], dim=3)
    arr = (sbs.permute(0, 2, 3, 1).clamp(0, 1) * 255).byte().numpy()
    arr.tofile(out_rgb)
    b = arr.shape[0]
    if out_final.endswith(".png"):
        subprocess.run(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "640x180",
                        "-i", out_rgb, out_final, "-y"], check=True)
    else:
        subprocess.run(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "640x180",
                        "-framerate", "24", "-i", out_rgb, "-c:v", "libx264", "-crf", "18",
                        "-pix_fmt", "yuv420p", out_final, "-y"], check=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", required=True)
    ap.add_argument("--depth", required=True)
    ap.add_argument("--tier", required=True, choices=["t1", "t2", "t3", "all"])
    ap.add_argument("--outdir", default=".")
    a = ap.parse_args()
    sys.path.insert(0, os.environ.get("NUNIF", "./nunif"))
    from iw3.stereo_model_factory import create_stereo_model
    from iw3.backward_warp import apply_divergence_nn_LR
    frames = load_frames(a.frames)
    depth = torch.from_numpy(np.load(a.depth)["depth"].astype(np.float32))
    DIV, CONV = 2.0, 1.0
    if a.tier in ("t3", "all"):
        rf = create_stereo_model("row_flow_v3", divergence=DIV, device_id=-1)
        lefts, rights = [], []
        with torch.inference_mode():
            for i in range(N):
                l, r = apply_divergence_nn_LR(rf, frames[i:i+1], depth[i:i+1], DIV, CONV, 1,
                                              synthetic_view="both", preserve_screen_border=False,
                                              enable_amp=False)
                lefts.append(l); rights.append(r)
        save_sbs(torch.cat(lefts), torch.cat(rights),
                 f"{a.outdir}/t3_sbs.rgb", f"{a.outdir}/tos_t3_row_flow_v3_goreda.mp4")
        print("t3 done", flush=True)
        del rf, lefts, rights
    if a.tier in ("t1", "all"):
        mi = create_stereo_model("mlbw_l2_inpaint", divergence=DIV, device_id=-1)
        mi.set_mode("video")
        lefts, rights = [], []
        with torch.inference_mode():
            for i in range(N):
                ret = mi.infer(frames[i:i+1], depth[i:i+1], divergence=DIV, convergence=CONV,
                               preserve_screen_border=False, synthetic_view="both",
                               inner_dilation=0, outer_dilation=0, max_width=None,
                               enable_amp=False, alpha=None)
                if ret[0] is not None:
                    lefts.append(ret[0]); rights.append(ret[1])
            ret = mi.flush(enable_amp=False)
            if ret[0] is not None:
                lefts.append(ret[0]); rights.append(ret[1])
        save_sbs(torch.cat(lefts), torch.cat(rights),
                 f"{a.outdir}/t1_sbs.rgb", f"{a.outdir}/tos_t1_mlbw_l2_inpaint_video_goreda.mp4")
        print("t1 done, frames:", torch.cat(lefts).shape[0], flush=True)
        del mi, lefts, rights
    if a.tier in ("t2", "all"):
        mi2 = create_stereo_model("mlbw_l2_inpaint", divergence=DIV, device_id=-1)
        mi2.set_mode("image")
        with torch.inference_mode():
            ret = mi2.infer(frames[0:1], depth[0:1], divergence=DIV, convergence=CONV,
                            preserve_screen_border=False, synthetic_view="both",
                            inner_dilation=0, outer_dilation=0, max_width=None,
                            enable_amp=False, alpha=None)
        l, r = ret[0], ret[1]
        if l.ndim == 3: l = l.unsqueeze(0)
        if r.ndim == 3: r = r.unsqueeze(0)
        save_sbs(l, r, f"{a.outdir}/t2_sbs.rgb", f"{a.outdir}/tos_t2_mlbw_l2_inpaint_image_goreda.png")
        print("t2 done", flush=True)
    print(f"peakRSS={resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1024:.0f}MB", flush=True)

if __name__ == "__main__":
    main()
