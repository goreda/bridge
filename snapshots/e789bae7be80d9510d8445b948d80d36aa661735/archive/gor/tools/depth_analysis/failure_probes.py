"""s35: depth failure-mode probes on the REAL VDA-S (fp16 ONNX stream,
same checkpoint as production) + MoGe-2.

Eight synthetic probe clips, each targeting one failure mode:
  sky, glass (reflection double-motion), fast_pan (+motion blur),
  dark_noise, overlay (burned-in subtitles + logo + letterbox bars),
  fade (to black), screen_in_screen, tiny_faces.

For each: run the production pipeline (VDA stream -> MoGe keyframes ->
weighted/unweighted align fit -> eased track -> metric z) and measure:
  moge_invalid_ratio  non-finite fraction of MoGe keyframe depth
  align_resid         keyframe LSQ RMSE / std(MoGe valid depth)
  jitter              median |inv_t - inv_{t-1}| / median(inv) over valid
  hole_frac           quantised w10 == 0 (masked) fraction
  comfort             shot_comfort policy -> disparity stats vs budgets
  sky_leak            (sky probe) sky inverse depth vs far percentile

Run baseline and guarded (depth_guards) and report both.
CLI: python3 failure_probes.py [out_dir]   (writes report.json + npy)
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import align as align_mod  # noqa: E402
import comfort  # noqa: E402
import depth_guards  # noqa: E402
import moge_fov  # noqa: E402
from onnx_stream import OnnxVdaStream  # noqa: E402

W, H, T = 160, 90, 16
D_SCALE = 256.0
KF_STRIDE = 12


# ---------------- synthetic clips (deterministic) ----------------

def _texture(rng, h=H, w=W, scale=24):
    base = rng.random(((h + 3) // 4, (w + 3) // 4))
    tex = np.kron(base, np.ones((4, 4)))[:h, :w]
    return (tex * 255 * 0.6 + 40).astype(np.float32)


def _shift(img, dx, dy=0):
    return np.roll(np.roll(img, dy, 0), dx, 1)


def _rgb(y, tint=(1.0, 1.0, 1.0)):
    return np.clip(y[..., None] * np.array(tint), 0, 255).astype(np.uint8)


def clip_sky():
    rng = np.random.default_rng(1)
    ground = _texture(rng, H - 50, W)
    out = []
    for t in range(T):
        frame = np.zeros((H, W), np.float32)
        for j in range(50):  # smooth sky gradient, slightly brighter up
            frame[j] = 200 - j
        frame[50:] = ground
        out.append(_rgb(_shift(frame, t // 4), (0.85, 0.95, 1.05)))  # slow pan
    return out


def clip_glass():
    rng = np.random.default_rng(2)
    bg, refl = _texture(rng), _texture(rng)
    out = []
    for t in range(T):
        f = _shift(bg, t)                       # scene pans right
        r = _shift(refl, -t)                    # reflection pans left
        f[:, : W // 2] = 0.65 * f[:, : W // 2] + 0.35 * r[:, : W // 2]
        out.append(_rgb(f))
    return out


def clip_fast_pan():
    rng = np.random.default_rng(3)
    bg = _texture(rng, H, W * 2)
    out = []
    for t in range(T):
        x = t * 8
        blur = (_shift(bg, x) + _shift(bg, x + 1) + _shift(bg, x + 2)) / 3
        out.append(_rgb(blur[:, :W]))
    return out


def clip_dark_noise():
    rng = np.random.default_rng(4)
    bg = _texture(rng) * 0.06 + 8
    return [_rgb(np.clip(bg + rng.normal(0, 6, (H, W)), 0, 255)) for _ in range(T)]


def clip_overlay():
    rng = np.random.default_rng(5)
    bg = _texture(rng)
    out = []
    for t in range(T):
        f = _shift(bg, t).copy()
        f[:8] = 0; f[-8:] = 0                    # letterbox bars
        f[8 + 60:8 + 66, 20:140] = 235           # burned-in subtitle line
        f[12:24, 128:152] = 250                  # logo block
        out.append(_rgb(f))
    return out


def clip_fade():
    rng = np.random.default_rng(6)
    bg = _texture(rng)
    ramp = np.linspace(1.0, 0.02, T)
    return [_rgb(bg * ramp[t]) for t in range(T)]


def clip_screen_in_screen():
    rng = np.random.default_rng(7)
    outer, inner = _texture(rng), _texture(rng, 40, 80)
    out = []
    for t in range(T):
        f = _shift(outer, t).copy()
        f[22:62, 40:120] = _shift(inner, -2 * t)[:40, :80]
        f[21, 39:121] = 255; f[62, 39:121] = 255   # bezel
        f[21:63, 39] = 255; f[21:63, 120] = 255
        out.append(_rgb(f))
    return out


def clip_tiny_faces():
    rng = np.random.default_rng(8)
    wall = _texture(rng) * 0.5 + 90
    out = []
    for t in range(T):
        f = wall.copy()
        for r in range(3):
            for c in range(10):
                cy, cx = 20 + r * 22 + (t % 2), 12 + c * 14
                f[cy:cy + 7, cx:cx + 6] = 180        # face blob
                f[cy + 2, cx + 1] = 40; f[cy + 2, cx + 4] = 40  # eyes
        out.append(_rgb(f))
    return out


PROBES = {"sky": clip_sky, "glass": clip_glass, "fast_pan": clip_fast_pan,
          "dark_noise": clip_dark_noise, "overlay": clip_overlay,
          "fade": clip_fade, "screen_in_screen": clip_screen_in_screen,
          "tiny_faces": clip_tiny_faces}


# ---------------- pipeline ----------------

def run_pipeline(frames, moge, model_dir, guarded=False):
    """Production-shaped pipeline over one probe clip.
    Returns dict(inv_seq (metric inverse depth [T,h,w]), moge_invalid,
    align_resid, z_c, depth_scale, masks). A FRESH VDA stream per call:
    the sliding window is stateful across a shot."""
    vda = OnnxVdaStream(model_dir)
    rel = np.stack([vda.process_frame(f) for f in frames])          # [T,h,w]
    h, w = rel.shape[1:]
    kidx = list(range(0, len(frames), KF_STRIDE))
    kf_metric, kf_w = [], []
    invalid = []
    for k in kidx:
        md, _ = moge_fov.infer_frame(moge, frames[k], num_tokens=600,
                                     resolution_level=5)
        if md is None:
            continue
        import cv2
        md = cv2.resize(md.astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
        invalid.append(float((~np.isfinite(md)).mean()))
        kf_metric.append((k, md))
        if guarded:
            lw = cv2.resize(frames[k].astype(np.float32).mean(-1), (w, h))
            kf_w.append(depth_guards.texture_weights(lw)[::4, ::4])
    al = align_mod.ShotAligner(ema=0.9)
    sub = np.s_[::4, ::4]
    track, resids = [], []
    kf_finite = {k: np.isfinite(md) for k, md in kf_metric}
    for i, (k, md) in enumerate(kf_metric):
        tgt, ref = rel[k][sub], md[sub]
        finite = np.isfinite(tgt) & np.isfinite(ref)
        if finite.sum() < 16:
            continue
        if guarded:
            s, b = depth_guards.fit_scale_shift_weighted(tgt, ref, finite, kf_w[i])
        else:
            s, b = align_mod.fit_scale_shift(tgt, ref, finite)
        pred = s * tgt[finite] + b
        resids.append(float(np.sqrt(np.mean((pred - ref[finite]) ** 2))
                          / (np.std(ref[finite]) + 1e-9)))
        # the EMA must fit with the SAME weights as the residual fit
        # above, or the guarded track diverges from the Swift port
        al.update(rel[k][sub], md[sub], weights=kf_w[i] if guarded else None)
        track.append((k, al.scale, al.shift))
    z = align_mod.apply_align_track(rel, [(k, s if s is not None else 1.0,
                                           b if b is not None else 0.0)
                                          for k, s, b in track])
    inv = np.where(z > 1e-3, D_SCALE / np.maximum(z, 1e-3), 0.0).astype(np.float32)
    if guarded:
        small = [cv2.resize(f.astype(np.float32).mean(-1), (w, h)) for f in frames]
        ks = sorted(kf_finite)
        def _kf_mask(t):
            k = min(ks, key=lambda k0: abs(k0 - t)) if ks else None
            return kf_finite[k] if k is not None else None
        inv = [depth_guards.sky_far_clamp(f, l, moge_finite=_kf_mask(t))
               for t, (f, l) in enumerate(zip(inv, small))]
        inv = depth_guards.fade_flatten(list(inv), small)
    z_seq = [np.where(v > 0, D_SCALE / np.maximum(v, 1e-9), np.inf) for v in inv]
    z_c = comfort.shot_convergence([np.where(np.isfinite(z), z, np.nan) for z in z_seq])
    if guarded and z_c:
        z_seq, om = depth_guards.static_overlay_flatten(z_seq, frames, z_c)
    else:
        om = np.zeros((H, W), bool)
    return {"inv": inv, "z": z_seq, "z_c": z_c,
            "moge_invalid": float(np.mean(invalid)) if invalid else None,
            "align_resid": float(np.mean(resids)) if resids else None,
            "rel_shape": list(rel.shape), "overlay_mask_frac": float(om.mean())}


def metrics(res, frames, name):
    inv = res["inv"]
    valid = [np.isfinite(f) & (f > 0) for f in inv]
    diffs = []
    for t in range(1, len(inv)):
        m = valid[t] & valid[t - 1]
        if m.sum() > 16:
            diffs.append(float(np.median(np.abs(inv[t][m] - inv[t - 1][m]))))
    med_inv = float(np.median(np.concatenate([f[v] for f, v in zip(inv, valid)]))) if any(v.any() for v in valid) else 0.0
    w10_0 = float(np.mean([float((f <= 0).mean()) for f in inv]))
    pol = comfort.shot_comfort([np.where(np.isfinite(z), z, np.inf) for z in res["z"]])
    dist = None
    if pol:
        z_c, scale, z_near = pol["convergence_m"], pol["depth_scale"], pol["z_near"]
        zeff = [np.where(np.isfinite(z), np.maximum(z, z_near), np.nan) for z in res["z"]]
        dist = comfort.distribution(np.concatenate([z.ravel() for z in zeff]),
                                    z_c=z_c, ipd=comfort.IPD * scale, z_near=z_near)
    out = {"moge_invalid": res["moge_invalid"], "align_resid": res["align_resid"],
           "jitter": float(np.median(diffs)) if diffs else None,
           "jitter_rel": (float(np.median(diffs)) / med_inv) if diffs and med_inv else None,
           "hole_frac": w10_0,
           "comfort": dist, "overlay_mask_frac": res["overlay_mask_frac"]}
    if name == "sky":
        f = inv[0]
        sky = f[:44][f[:44] > 0]
        out["sky_leak"] = float(np.median(sky) / med_inv) if sky.size and med_inv else None
        far = np.percentile(f[f > 0], 5) if (f > 0).any() else 0.0
        out["sky_near_frac"] = float((f[:44] > 2 * far).mean()) if far > 0 else None
    return out


def main(out_dir="/tmp/s35"):
    os.makedirs(out_dir, exist_ok=True)
    model_dir = os.path.expanduser("~/s4/models")
    moge = moge_fov.load_moge(os.path.join(model_dir, "moge2_vits_normal.pt"))
    report = {}
    for name, gen in PROBES.items():
        frames = gen()
        row = {}
        for mode in ("baseline", "guarded"):
            res = run_pipeline(frames, moge, model_dir, guarded=(mode == "guarded"))
            row[mode] = metrics(res, frames, name)
            np.save(os.path.join(out_dir, f"{name}_{mode}_inv.npy"),
                    np.stack(res["inv"]).astype(np.float32))
        report[name] = row
        print(f"== {name}\n  baseline {json.dumps(row['baseline'], default=str)}\n  guarded  {json.dumps(row['guarded'], default=str)}", flush=True)
        with open(os.path.join(out_dir, "report.json"), "w") as f:
            json.dump(report, f, indent=1, default=str)
    print("wrote", os.path.join(out_dir, "report.json"))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/s35")
