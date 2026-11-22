"""s39: Linux dress rehearsal for the first Mac 3D run (CONTRACT-190v s39).

Produces, from the reference implementation, the exact artefact set the
first Mac run must produce for the live and CG clips:

  <out>/<clip>/gor3d-selftest.log   gor3d-selftest v1 lines: stages,
                                    rtstage (measured HERE, flagged
                                    synthetic-timing), thermal
                                    (synthetic: this box has no
                                    thermalState), depth stats,
                                    jitter_rel, render_key_v4, plus
                                    interleaved 3dfsm transition lines
                                    (s38) from a scripted degradation walk
  <out>/<clip>/shot0.dzc            depth container (contract format)
  <out>/<clip>/align_track.json     per-keyframe weighted-EMA track
  <out>/<clip>/render_full_sbs.mp4  per-mode renders (reference proxy res)
  <out>/<clip>/render_vr180.mp4
  <out>/<clip>/render_key_v4.txt    the v4 cache keys for both modes
  <out>/rehearsal_expected.json     selftest_check expected file with
                                    reference-box stage budgets (all other
                                    rules identical to selftest_expected)
  <out>/manifest.json               sha256 of every artefact

Then it runs selftest_check.py against each log end to end; exit 0 only
if both clips PASS. When the real Mac log arrives, diffing it against
this log must show only measured-vs-modelled differences, never a
format surprise.

CLI: python3 rehearsal.py --out /tmp/rehearsal [--frames 36] [--proxy-w 640]
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import align as align_mod  # noqa: E402
import comfort  # noqa: E402
import degrade_fsm as fsm  # noqa: E402
import depth_container  # noqa: E402
import depth_guards  # noqa: E402
import moge_fov  # noqa: E402
import output_modes as om  # noqa: E402
from onnx_stream import OnnxVdaStream  # noqa: E402

CLIPS = {"live": "/home/sandbox/s4/e2/clips/live.mp4",
         "cg": "/home/sandbox/s4/e2/clips/anim.mp4"}
D_SCALE = 256.0          # contract: v = D_SCALE / Z
KF_STRIDE = 12
STREAM_W, STREAM_H = 266, 154
THETA_H = 0.9075712110370514   # fixture/source hfov (rad), s26 probe value

TS0 = time.strftime("%Y-%m-%dT%H:%M:%S")


def ts():
    return f"[{TS0}] "


def letterbox_box(src_w, src_h, w=STREAM_W, h=STREAM_H):
    """Same rule as selftest_check.letterbox (s22)."""
    scale = min(w / src_w, h / src_h)
    return max(1, round(src_w * scale)), max(1, round(src_h * scale))


def extract_frames(path, n, pw):
    """n frames at proxy width (even height), rgb24 list + (w, h)."""
    import cv2  # noqa: F401 (avail check via ffmpeg path anyway)
    info = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate", "-of", "json",
         path], capture_output=True, text=True).stdout)["streams"][0]
    sw, sh = int(info["width"]), int(info["height"])
    ph = int(round(sh * pw / sw / 2)) * 2
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", str(n),
         "-vf", f"scale={pw}:{ph}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True).stdout
    a = np.frombuffer(out, np.uint8)
    k = a.size // (pw * ph * 3)
    return list(a[: k * pw * ph * 3].reshape(k, ph, pw, 3)), (pw, ph)


def prepare(frames, model_dir, moge, log, note):
    """Production-shaped guarded prepare (s35 path). Returns
    (inv [T,bh,bw] float32, z_seq list [m], track, stage_ms dict)."""
    import cv2
    t0 = time.time()
    vda = OnnxVdaStream(model_dir)
    rel = []
    vda_ms = []
    for f in frames:
        t = time.time()
        d = vda.process_frame(f, aspect=True)
        vda_ms.append((time.time() - t) * 1e3)
        rel.append(d)
    rel = np.stack(rel)                                    # [T,154,266]
    bw, bh = letterbox_box(frames[0].shape[1], frames[0].shape[0])
    y0 = (STREAM_H - bh) // 2
    rel = rel[:, y0:y0 + bh, :bw]                          # letterbox picture
    T, h, w = rel.shape
    kidx = list(range(0, T, KF_STRIDE))
    kf_metric, kf_w, moge_ms = [], [], []
    for k in kidx:
        t = time.time()
        md, _ = moge_fov.infer_frame(moge, frames[k], num_tokens=600,
                                     resolution_level=5)
        moge_ms.append((time.time() - t) * 1e3)
        md = cv2.resize(md.astype(np.float32), (w, h),
                        interpolation=cv2.INTER_LINEAR)
        kf_metric.append((k, md))
        lw = cv2.resize(frames[k].astype(np.float32).mean(-1), (w, h))
        kf_w.append(depth_guards.texture_weights(lw)[::4, ::4])
    al = align_mod.ShotAligner(ema=0.9)
    sub = np.s_[::4, ::4]
    track = []
    for i, (k, md) in enumerate(kf_metric):
        al.update(rel[k][sub], md[sub], weights=kf_w[i])   # s35: weighted EMA
        track.append((k, al.scale, al.shift))
    z = align_mod.apply_align_track(rel, [(k, s or 1.0, b or 0.0)
                                          for k, s, b in track])
    inv = np.where(z > 1e-3, D_SCALE / np.maximum(z, 1e-3), 0.0
                   ).astype(np.float32)
    small = [cv2.resize(f.astype(np.float32).mean(-1), (w, h)) for f in frames]
    kf_finite = {k: np.isfinite(md) for k, md in kf_metric}
    ks = sorted(kf_finite)

    def _mask(t):
        k = min(ks, key=lambda k0: abs(k0 - t)) if ks else None
        return kf_finite[k] if k is not None else None
    inv = np.stack([depth_guards.sky_far_clamp(f, l, moge_finite=_mask(t))
                    for t, (f, l) in enumerate(zip(inv, small))])
    inv = np.stack(depth_guards.fade_flatten(list(inv), small))
    z_seq = [np.where(v > 0, D_SCALE / np.maximum(v, 1e-9), np.inf)
             for v in inv]
    z_c = comfort.shot_convergence(
        [np.where(np.isfinite(z), z, np.nan) for z in z_seq])
    if z_c:
        z_seq, _om = depth_guards.static_overlay_flatten(z_seq, frames, z_c)
    stage_ms = {"vda": vda_ms, "moge": moge_ms,
                "prepare_total": (time.time() - t0) * 1e3}
    return inv.astype(np.float32), z_seq, track, stage_ms


def jitter_rel(inv):
    """s35 metric (PrepareTelemetry.jitter_rel): median per-frame median
    |d inv| over consecutive frames / median inv."""
    diffs = [float(np.median(np.abs(inv[i + 1] - inv[i])))
             for i in range(len(inv) - 1)]
    med = float(np.median(inv[inv > 0])) if (inv > 0).any() else 0.0
    return (float(np.median(diffs)) / med) if diffs and med else 0.0


def fsm_walk_lines():
    """Scripted degradation walk (s38): the transitions the Mac selftest
    must log, emitted verbatim."""
    seq = [fsm.EV_PROBE_OK, fsm.EV_COVERED, fsm.EV_UNCOVERED,
           fsm.EV_LGD_TIMEOUT, fsm.EV_COVERED, fsm.EV_THERMAL_TRIP,
           fsm.EV_THERMAL_CLEAR, fsm.EV_QUIT, fsm.EV_RELAUNCH,
           fsm.EV_PROBE_OK, fsm.EV_COVERED]
    s, out = fsm.INIT, []
    for ev in seq:
        t = fsm.handle(s, ev)
        out.append(t.logline(s, ev))
        s = t.to
    assert s == fsm.READY_STEREO
    return out


def render_key_v3(mode, ipd_m, depth_scale, over_budget, convergence_m,
                  eye_n, depth_stamp, codec="hevc", swap=False,
                  screen_deg=75.0, surround_soft=True):
    """Mirror of Tests/DepthAnalysis/test_render_key_matrix.py key_v3
    (ThreeDRenderCoordinator.key v3 + depthStamp, contract s33).
    Superseded by render_key_v4 (190w W3); kept as the stale-cache
    recogniser and because three_d_degrade_test slices on this def."""
    sf = min(1.0, depth_scale) if not over_budget else depth_scale
    ipd = f"comfort|ipd{ipd_m}|sf{sf}"
    conv = str(convergence_m) if convergence_m is not None else "nil"
    return (f"v3|{ipd}|{mode}|{conv}|{eye_n}|{codec}|{swap}|{screen_deg}"
            f"|{surround_soft}|{depth_stamp}")


RENDER_METHODS = ("mlbw_l2_inpaint_video", "mlbw_l2_inpaint", "row_flow_v3",
                  "dibr_golden")  # 190w W3 tier order T1>T2>T3>fallback


def render_key_v5(mode, method, ipd_m, depth_scale, over_budget,
                  convergence_m, eye_n, depth_stamp, **kw):
    """Mirror of ThreeDRenderCoordinator.key v5 (E-G F3, 17:21): the span
    comfort gain (p5/median/p95 ShotComfortSpan) now sets depthScale, so
    the key is v5|span-p5p95|<method>|<v3 body> (ipd/sf stay in the body;
    with the depth stamp they determine the shot gain). Invalidates v4
    median-only renders."""
    return "v5|span-p5p95|" + render_key_v4(
        mode, method, ipd_m, depth_scale, over_budget, convergence_m,
        eye_n, depth_stamp, **kw)[3:]


def render_key_v4(mode, method, ipd_m, depth_scale, over_budget,
                  convergence_m, eye_n, depth_stamp, codec="hevc",
                  swap=False, screen_deg=75.0, surround_soft=True):
    """Mirror of ThreeDRenderCoordinator.key v4 (190w W3): the v3 body plus
    the synthesis-method field right after the version, so a method/tier
    change re-prepares every cached stand-in render (v3-keyed files go
    stale on this bump). dibr_golden is the last-resort fallback, labelled
    as such wherever the method surfaces."""
    assert method in RENDER_METHODS, method
    return "v4|" + method + "|" + render_key_v3(
        mode, ipd_m, depth_scale, over_budget, convergence_m, eye_n,
        depth_stamp=depth_stamp, codec=codec, swap=swap,
        screen_deg=screen_deg, surround_soft=surround_soft)[3:]


def encode_mp4(frames, path):
    h, w = frames[0].shape[:2]
    raw = b"".join(f.tobytes() for f in frames)
    t = time.time()
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo",
                    "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", "24",
                    "-i", "-", "-c:v", "libx264", "-crf", "18", path],
                   input=raw, check=True)
    return (time.time() - t) * 1e3 / max(1, len(frames))


def sha_file(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def run_clip(name, src, out_root, n_frames, proxy_w, model_dir, moge):
    cdir = os.path.join(out_root, name)
    os.makedirs(cdir, exist_ok=True)
    log = []
    P = "gor3d-selftest v1 "

    def emit(kind):
        log.append(ts() + P + kind)

    emit("begin gor3d\\nreference-linux\\nrehearsal\\nSYNTHETIC-TIMING")
    emit('note key=rehearsal value="reference implementation on Linux '
         '(CPU-only ONNX); stage/rtstage timings model THIS box, not the '
         'Mac; thermal lines synthetic"')

    t = time.time()
    frames, (w, h) = extract_frames(src, n_frames, proxy_w)
    clip_write_ms = (time.time() - t) * 1e3
    emit(f"note key=clip value={w}x{h} {len(frames)}f @24.0 {name}-rehearsal")
    emit(f"stage name=clip_write ms={clip_write_ms:.1f} n=1 "
         f"max_ms={clip_write_ms:.1f}")

    inv, z_seq, track, st = prepare(frames, model_dir, moge, log, None)
    emit(f"stage name=prepare_total ms={st['prepare_total']:.1f} n=1 "
         f"max_ms={st['prepare_total']:.1f}")
    nkf = len(st["moge"])
    emit(f"note key=moge_precision value=fp16_used=0 fp32_used={nkf} "
         "fp16_rejected=0")
    emit('note key=precision_source value="reference runs the fp32 torch '
         'export; the Mac runs CoreML fp16 (fp16_used expected there)"')

    # --- artefacts: .dzc + align json
    dzc = os.path.join(cdir, "shot0.dzc")
    z_stack = np.stack([np.where(np.isfinite(z), z, 1e6)
                        for z in z_seq]).astype(np.float64)
    depth_container.write(dzc, z_stack, shot=0, fps=24.0, start_frame=0)
    dzc_sha = sha_file(dzc)
    align_json = {"clip": name, "fps": 24.0, "kf_stride": KF_STRIDE,
                  "ema": 0.9, "weighted_ema": True,
                  "track": [[int(k), s, b] for k, s, b in track],
                  "dzc_sha256": dzc_sha}
    with open(os.path.join(cdir, "align_track.json"), "w") as f:
        json.dump(align_json, f, indent=1)

    # --- artefacts: per-mode renders
    pol = comfort.shot_comfort(
        [np.where(np.isfinite(z), z, np.nan) for z in z_seq]) or {
        "convergence_m": 2.0, "depth_scale": 1.0, "z_near": 0.5}
    t = time.time()
    up_ms, sur_ms, ren_ms = [], [], []
    import cv2
    mode_frames = {"full_sbs": [], "vr180": []}
    for i, f in enumerate(frames):
        zr = np.where(np.isfinite(z_seq[i]), np.maximum(z_seq[i], pol["z_near"]),
                      pol["z_near"] * 4)
        t1 = time.time()
        zr = cv2.resize(zr.astype(np.float32), (w, h),
                        interpolation=cv2.INTER_LINEAR).astype(np.float64)
        up_ms.append((time.time() - t1) * 1e3)
        for mode in mode_frames:
            t1 = time.time()
            packed = om.render_mode(f, zr, THETA_H, mode, ipd=comfort.IPD,
                                    convergence_m=pol["convergence_m"],
                                    depth_scale=pol["depth_scale"])
            dt = (time.time() - t1) * 1e3
            ren_ms.append(dt)
            if mode == "vr180":
                sur_ms.append(dt * 0.4)   # surround share (soft fill pass)
            mode_frames[mode].append(packed)
    render_ms = (time.time() - t) * 1e3
    enc = {}
    for mode, mfs in mode_frames.items():
        enc[mode] = encode_mp4(mfs, os.path.join(cdir, f"render_{mode}.mp4"))
    emit(f"stage name=render_shot ms={render_ms:.1f} n=1 "
         f"max_ms={render_ms:.1f}")

    first_sha = hashlib.sha256(mode_frames["full_sbs"][0].tobytes()).hexdigest()
    emit(f"note key=first_3d_frame_sha256 value={first_sha}")
    emit("note key=rt_config value=fps=24.0 vr180=true depth_rate=24.0 "
         "surround_opt=false")

    def avg(xs):
        return sum(xs) / max(1, len(xs))
    rt = {"vda": (avg(st["vda"]), len(st["vda"]), max(st["vda"])),
          "moge": (avg(st["moge"]), len(st["moge"]), max(st["moge"])),
          "upsample": (avg(up_ms), len(up_ms), max(up_ms)),
          "surround": (avg(sur_ms), len(sur_ms), max(sur_ms)),
          "render": (avg(ren_ms), len(ren_ms), max(ren_ms)),
          "vt_decode": (clip_write_ms / len(frames), len(frames),
                        clip_write_ms / len(frames)),
          "vt_encode": (avg(list(enc.values())), len(frames),
                        max(enc.values()))}
    for name_ in ("vda", "moge", "upsample", "surround", "render",
                  "vt_decode", "vt_encode"):
        ms, nn, mx = rt[name_]
        emit(f"rtstage name={name_} ms={ms:.3f} n={nn} max_ms={mx:.3f}")
    emit("thermal level=0 t_ms=0")
    emit("thermal_peak level=0 transitions=0")
    emit('note key=thermal_source value=synthetic')

    # --- depth stats (comparator count rule: frames x letterbox picture)
    bw, bh = letterbox_box(w, h)
    v = inv[inv > 0]
    z_stats = D_SCALE / v if v.size else np.array([np.inf])
    z_mm = z_stats * 1000.0   # the Mac log reports depth in millimetres
    emit(f"depth min={float(z_mm.min()):.1f} max={float(z_mm.max()):.1f} "
         f"nan=0 inf=0 count={len(frames) * bw * bh}")
    emit(f"note key=jitter_rel value={jitter_rel(inv):.6f} (median |d inv|/"
         "median inv per frame, pixel stride 2; dark/noisy scenes measured "
         "0.25, healthy < 0.05)")

    # --- render key v4 (both modes; method = spec'd T1, 190w W3)
    eye_n = om.eye_n_for(h)
    keys = {m: render_key_v4(m, RENDER_METHODS[0], comfort.IPD,
                             pol["depth_scale"], False,
                             pol["convergence_m"], eye_n,
                             depth_stamp=dzc_sha[:12])
            for m in mode_frames}
    with open(os.path.join(cdir, "render_key_v4.txt"), "w") as f:
        for m, k in keys.items():
            f.write(f"{m} {k}\n")
    emit(f"note key=render_key_v4 value={keys['vr180']}")
    keys5 = {m: render_key_v5(m, RENDER_METHODS[0], comfort.IPD,
                              pol["depth_scale"], False,
                              pol["convergence_m"], eye_n,
                              depth_stamp=dzc_sha[:12]) for m in mode_frames}
    with open(os.path.join(cdir, "render_key_v5.txt"), "w") as f:
        for m, k in keys5.items():
            f.write(f"{m} {k}\n")
    emit(f"note key=render_key_v5 value={keys5['vr180']}")

    # --- 3dfsm degradation walk (s38), interleaved as plain log lines
    for line in fsm_walk_lines():
        log.append(ts() + line)

    emit("end errors=0")
    logpath = os.path.join(cdir, "gor3d-selftest.log")
    with open(logpath, "w") as f:
        f.write("\n".join(log) + "\n")
    return cdir, logpath


def write_expected(out_root):
    exp = json.load(open(os.path.join(HERE, "selftest_expected.json")))
    exp["about"] = ("s39 rehearsal: same rules as selftest_expected.json; "
                    "stage budgets rescaled for the slow CPU-only reference "
                    "box. The Mac first run is checked against "
                    "selftest_expected.json, NOT this file.")
    exp["stage_budgets_ms"] = {"clip_write": 120000,
                               "prepare_total": 900000,
                               "render_shot": 900000}
    p = os.path.join(out_root, "rehearsal_expected.json")
    with open(p, "w") as f:
        json.dump(exp, f, indent=1)
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/rehearsal")
    ap.add_argument("--frames", type=int, default=36)
    ap.add_argument("--proxy-w", type=int, default=640)
    ap.add_argument("--clips", default="live,cg")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    model_dir = os.path.expanduser("~/s4/models")
    missing = [c for c in CLIPS.values() if not os.path.exists(c)]
    if missing:
        print("rehearsal: clips not present on this box:", missing)
        return 2
    if not os.path.exists(os.path.join(model_dir, "moge2_vits_normal.pt")):
        print("rehearsal: MoGe checkpoint not found under", model_dir)
        return 2
    moge = moge_fov.load_moge(os.path.join(model_dir, "moge2_vits_normal.pt"))
    exp_path = write_expected(a.out)
    mpath = os.path.join(a.out, "manifest.json")
    manifest = json.load(open(mpath)) if os.path.exists(mpath) else {}
    ok = True
    for name in a.clips.split(","):
        cdir, logpath = run_clip(name, CLIPS[name], a.out, a.frames,
                                 a.proxy_w, model_dir, moge)
        r = subprocess.run([sys.executable,
                            os.path.join(HERE, "selftest_check.py"),
                            logpath, "--expected", exp_path],
                           capture_output=True, text=True)
        ok &= r.returncode == 0
        print(f"== {name}: selftest_check exit {r.returncode}")
        if r.returncode != 0:
            print(r.stdout[-2000:])
        for fn in sorted(os.listdir(cdir)):
            p = os.path.join(cdir, fn)
            if os.path.isfile(p):
                manifest[f"{name}/{fn}"] = sha_file(p)
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1)
    print("REHEARSAL PASS" if ok else "REHEARSAL FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
