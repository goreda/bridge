"""Per-stage timing + quality bench on real footage (VDA Small / MoGe-2
only). Checkpointed per stage so long CPU stages can run one invocation at
a time; numbers land in CONTRACT-190v.md section 10.

Usage (in order, same --work dir):
  python3 bench_prepare.py --stage prep  --video live.mp4 --seconds 10 --fps 24 --work W
  python3 bench_prepare.py --stage vda   --work W --vda-from 0 --vda-to 80
  python3 bench_prepare.py --stage moge  --work W
  python3 bench_prepare.py --stage finish --work W

Stages timed: cut detect, frame decode, VDA Small depth (one-time model
load recorded once), MoGe-2 FoV keyframes, depth HEVC encode, source proxy
encode. Cache size = bytes of the written entry per minute of film.
"""
import argparse
import json
import os
import subprocess
import time

import numpy as np

MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
VDA_CKPT = os.path.join(MODELS, "video_depth_anything_vits.pth")
MOGE_CKPT = os.path.join(MODELS, "moge2_vits_normal.pt")


def _dir_bytes(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            total += os.path.getsize(os.path.join(root, f))
    return total


def _state(work):
    p = os.path.join(work, "bench_state.json")
    return json.load(open(p)) if os.path.exists(p) else {"stage_seconds": {}}


def _save_state(work, st):
    json.dump(st, open(os.path.join(work, "bench_state.json"), "w"), indent=2)


def stage_prep(a):
    import cuts as cuts_mod
    import vda_windowed
    st = _state(a.work)
    n_frames = int(round(a.seconds * a.fps))
    st.update(video=a.video, seconds=a.seconds, fps=a.fps,
              frames=n_frames, input_size=a.input_size)
    sl = os.path.join(a.work, "slice.mp4")
    t0 = time.perf_counter()
    subprocess.run(["ffmpeg", "-v", "error", "-i", a.video, "-t",
                    str(a.seconds), "-an", "-c:v", "libx264", "-preset",
                    "veryfast", "-crf", "23", "-y", sl], check=True)
    st["stage_seconds"]["slice"] = time.perf_counter() - t0
    t0 = time.perf_counter()
    cut_list = cuts_mod.detect_cuts(sl, a.fps)
    shots = cuts_mod.shots_from_cuts(n_frames, cut_list)
    st["stage_seconds"]["cut_detect"] = time.perf_counter() - t0
    s, e = max(shots, key=lambda q: q[1] - q[0])
    st["bench_shot"] = [s, e]
    st["shots"] = [list(x) for x in shots]
    t0 = time.perf_counter()
    frames = vda_windowed.read_shot_frames(sl, s, e + 1)
    st["stage_seconds"]["decode"] = time.perf_counter() - t0
    np.save(os.path.join(a.work, "frames.npy"), frames)
    st["shot_frames"] = int(len(frames))
    _save_state(a.work, st)
    print(f"prep done: shot [{s},{e}) = {len(frames)} frames, "
          f"cuts={cut_list}")


def stage_vda(a):
    import vda_windowed
    st = _state(a.work)
    frames = np.load(os.path.join(a.work, "frames.npy"), mmap_mode="r")
    lo, hi = a.vda_from, min(a.vda_to, len(frames))
    frames = np.array(frames[lo:hi])  # materialise only this chunk
    t0 = time.perf_counter()
    model = vda_windowed.load_model(VDA_CKPT)
    load_s = time.perf_counter() - t0
    st["stage_seconds"].setdefault("vda_load_one_time", load_s)
    t0 = time.perf_counter()
    part = vda_windowed.infer_shot_depth(model, frames,
                                         input_size=st["input_size"])
    dt = time.perf_counter() - t0
    st["stage_seconds"]["vda_depth"] = \
        st["stage_seconds"].get("vda_depth", 0.0) + dt
    np.save(os.path.join(a.work, f"depth_{lo:04d}_{hi:04d}.npy"),
            part.astype(np.float16))
    _save_state(a.work, st)
    print(f"vda [{lo},{hi}): {dt:.1f}s ({dt / (hi - lo):.3f}s/frame), "
          f"load {load_s:.1f}s")


def stage_moge(a):
    import moge_fov
    from prepare_film import FOV_KEYFRAME_STRIDE
    st = _state(a.work)
    frames = np.load(os.path.join(a.work, "frames.npy"), mmap_mode="r")
    t0 = time.perf_counter()
    moge = moge_fov.load_moge(MOGE_CKPT)
    st["stage_seconds"]["moge_load_one_time"] = time.perf_counter() - t0
    t0 = time.perf_counter()
    kidx = list(range(0, len(frames), FOV_KEYFRAME_STRIDE))
    fovs = []
    for k in kidx:
        _, fv = moge_fov.infer_frame(moge, np.array(frames[k]), num_tokens=600,
                                     resolution_level=5)
        if fv is not None:
            fovs.append(float(fv))
    st["stage_seconds"]["moge_fov"] = time.perf_counter() - t0
    st["moge_keyframes"] = len(kidx)
    st["median_hfov_deg"] = float(np.median(fovs)) if fovs else None
    st["hfov_spread_deg"] = float(np.std(fovs)) if fovs else None
    _save_state(a.work, st)
    print(f"moge: {len(kidx)} keyframes in "
          f"{st['stage_seconds']['moge_fov']:.1f}s, "
          f"median hfov {st['median_hfov_deg']}")


def stage_finish(a):
    from prepare_film import (D_SCALE, V_INV_MAX, write_depth_hevc,
                              write_source_hevc)
    st = _state(a.work)
    s, e = st["bench_shot"]
    fps = st["fps"]
    n = st["shot_frames"]
    part_files = sorted(f for f in os.listdir(a.work)
                        if f.startswith("depth_") and f.endswith(".npy"))
    sample = np.load(os.path.join(a.work, part_files[0]))
    inv = np.empty((n,) + sample.shape[1:], np.float32)
    off = 0
    for f in part_files:  # stream part by part to keep peak RAM low
        d = np.load(os.path.join(a.work, f)).astype(np.float32)
        take = min(len(d), n - off)
        np.maximum(d[:take], 1e-3, out=d[:take])
        np.divide(np.float32(D_SCALE), d[:take], out=d[:take])
        np.clip(d[:take], 0, V_INV_MAX, out=d[:take])
        inv[off:off + take] = d[:take]
        off += take
    assert off == n, (off, n)
    entry = os.path.join(a.work, "entry"); os.makedirs(entry, exist_ok=True)
    t0 = time.perf_counter()
    write_depth_hevc(os.path.join(entry, "depth_shot_00000.mp4"), inv,
                     fps=fps, start_frame=s)
    st["stage_seconds"]["depth_encode"] = time.perf_counter() - t0
    t0 = time.perf_counter()
    write_source_hevc(os.path.join(entry, "source_shot_00000.mp4"),
                      os.path.join(a.work, "slice.mp4"), s, e, fps)
    st["stage_seconds"]["source_encode"] = time.perf_counter() - t0
    cache_bytes = _dir_bytes(entry)
    scale = fps * 60.0 / n
    ss = st["stage_seconds"]
    rep = {"video": st["video"], "seconds": st["seconds"], "fps": fps,
           "input_size": st["input_size"], "bench_shot_frames": n,
           "shots": st["shots"], "moge_keyframes": st.get("moge_keyframes"),
           "median_hfov_deg": st.get("median_hfov_deg"),
           "hfov_spread_deg": st.get("hfov_spread_deg"),
           "stage_seconds": ss,
           "per_minute_of_film": {
               "decode_s": ss["decode"] * scale,
               "vda_depth_s": ss["vda_depth"] * scale,
               "moge_fov_s": ss["moge_fov"] * scale,
               "depth_encode_s": ss["depth_encode"] * scale,
               "source_encode_s": ss["source_encode"] * scale,
               "total_steady_s": (ss["decode"] + ss["vda_depth"]
                                  + ss["moge_fov"] + ss["depth_encode"]
                                  + ss["source_encode"]) * scale,
               "cache_bytes": cache_bytes * scale,
               "cache_mib": cache_bytes * scale / 1048576.0},
           "one_time_loads_s": {"vda": ss.get("vda_load_one_time"),
                                "moge": ss.get("moge_load_one_time")}}
    out = os.path.join(a.work, "bench_report.json")
    json.dump(rep, open(out, "w"), indent=2)
    _save_state(a.work, st)
    print(json.dumps(rep, indent=2))
    print("wrote", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", required=True,
                    choices=["prep", "vda", "moge", "finish"])
    ap.add_argument("--video")
    ap.add_argument("--seconds", type=float, default=10.0)
    ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--work", required=True)
    ap.add_argument("--input-size", type=int, default=252)
    ap.add_argument("--vda-from", type=int, default=0)
    ap.add_argument("--vda-to", type=int, default=10**9)
    a = ap.parse_args()
    os.makedirs(a.work, exist_ok=True)
    {"prep": stage_prep, "vda": stage_vda, "moge": stage_moge,
     "finish": stage_finish}[a.stage](a)


if __name__ == "__main__":
    main()
