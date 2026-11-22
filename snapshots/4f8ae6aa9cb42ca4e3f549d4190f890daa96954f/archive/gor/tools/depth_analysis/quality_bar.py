"""s45: visible-quality bar - what a viewer would see, measured on the e2
clips through the Linux reference pipeline.

Five viewer-facing metrics per clip, each with a before/after ablation
mapped to the commit that introduced the fix (the "s25-s35 baseline" is
exercised by turning the fix OFF via its documented parameter, which is
what those commits added - the old code paths no longer exist):

  flicker      temporal depth flicker: median/p95 relative inverse-depth
               second difference (flicker.depth_jitter) + rendered
               disparity jitter in canvas px (flicker.disparity_jitter)
  disocc       edge/disocclusion artifact area: pair+edge-run fill px as
               a share of covered px, black px inside the footprint
               (render_frame_sbs stats; surround soft vs off = s28)
  comfort      comfort violations: % pixels outside the [-1, +2] deg
               budget per frame, at the s25 policy vs renderer defaults
               (conv=0, full IPD, no clamp)
  cut          cut-adjacent depth jumps: the e2 clips are single-shot;
               the metric lives on the golden two-shot fixture and is
               pinned by test_comfort.py's shot-cut tier (reported n/a)
  logo         subtitle/logo: overlay_disparity of the canonical stamp
               (0 px = screen depth by construction) + temporal z
               stability inside the stamp region post-pipeline
  align        (s30) eased vs instant keyframe application: keyframe-pop
               flicker
  ema          (s35) weighted vs unweighted align EMA + sky clamp on/off

Pipeline determinism: ONNX VDA (CPU) and torch MoGe-2 (CPU, fixed
inputs) are deterministic on a given box, so the regression baseline
carries TIGHT margins (10% rel or a small abs floor); a code change
that worsens a viewer metric trips it.

CLI:
  python3 quality_bar.py prepare --clip live --work /tmp/qbar [--frames 24]
  python3 quality_bar.py measure --work /tmp/qbar [--md docs/190v-quality-bar.md]
  python3 quality_bar.py check --work /tmp/qbar --baseline BASELINE.json
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import align as align_mod  # noqa: E402
import comfort  # noqa: E402
import depth_guards  # noqa: E402
import flicker  # noqa: E402
import reference_render  # noqa: E402
from rehearsal import (CLIPS, D_SCALE, KF_STRIDE, extract_frames,  # noqa: E402
                       letterbox_box, STREAM_H)

THETA_75 = math.radians(75.0)
LOGO_BOX_FRAC = (0.82, 0.90, 0.30, 0.70)   # the comfort_e2e stamp region


def spool_path(work, clip):
    return os.path.join(work, clip + ".spool.npz")


def cmd_prepare(a):
    """Run the guarded prepare ONCE per clip and spool every intermediate
    the ablations need (raw VDA rel, MoGe keyframes, texture weights,
    luma). Mirrors rehearsal.prepare's code path exactly."""
    import cv2
    import moge_fov
    from onnx_stream import OnnxVdaStream

    # --clip names an entry of rehearsal.CLIPS, or a direct mp4 path
    # (named by its basename, e.g. dark.mp4 -> 'dark').
    if a.clip in CLIPS:
        src = str(CLIPS[a.clip])
    elif os.path.exists(a.clip):
        src = a.clip
        a.clip = os.path.splitext(os.path.basename(src))[0]
    else:
        raise SystemExit("unknown clip " + a.clip)
    model_dir = a.models
    frames, (w, h) = extract_frames(src, a.frames, a.proxy_w)
    vda = OnnxVdaStream(model_dir)
    rel = np.stack([vda.process_frame(f, aspect=True) for f in frames])
    bw, bh = letterbox_box(frames[0].shape[1], frames[0].shape[0])
    y0 = (STREAM_H - bh) // 2
    rel = rel[:, y0:y0 + bh, :bw].astype(np.float32)
    moge = moge_fov.load_moge(os.path.join(model_dir, "moge2_vits_normal.pt"))
    kidx = list(range(0, len(frames), KF_STRIDE))
    kf, kfw = [], []
    for k in kidx:
        md, _ = moge_fov.infer_frame(moge, frames[k], num_tokens=600,
                                     resolution_level=5)
        md = cv2.resize(md.astype(np.float32), (rel.shape[2], rel.shape[1]),
                        interpolation=cv2.INTER_LINEAR)
        kf.append(md)
        lw = cv2.resize(frames[k].astype(np.float32).mean(-1),
                        (rel.shape[2], rel.shape[1]))
        kfw.append(depth_guards.texture_weights(lw)[::4, ::4])
    small = np.stack([cv2.resize(f.astype(np.float32).mean(-1),
                                 (rel.shape[2], rel.shape[1]))
                      for f in frames])
    os.makedirs(a.work, exist_ok=True)
    np.savez_compressed(spool_path(a.work, a.clip), rel=rel,
                        kf=np.stack(kf).astype(np.float32),
                        kidx=np.array(kidx), kfw=np.stack(kfw),
                        small=small.astype(np.float32),
                        proxy=np.array([frames[0].shape[1],
                                        frames[0].shape[0]]))
    print(f"spooled {a.clip}: T={len(frames)} rel={rel.shape} kf={len(kf)}")


def build_z(sp, weighted=True, sky=True, eased=True):
    """Reconstruct the z sequence from the spool under one ablation."""
    rel, kf, kidx = sp["rel"], sp["kf"], [int(k) for k in sp["kidx"]]
    sub = np.s_[::4, ::4]
    al = align_mod.ShotAligner(ema=0.9)
    track = []
    for i, k in enumerate(kidx):
        w = sp["kfw"][i] if weighted else None
        al.update(rel[k][sub], kf[i][sub], weights=w)
        track.append((k, al.scale, al.shift))
    if eased:
        z = align_mod.apply_align_track(rel, [(k, s or 1.0, b or 0.0)
                                              for k, s, b in track])
    else:  # instant switch at each keyframe (pre-s30 behaviour)
        z = np.empty_like(rel, dtype=np.float64)
        ks = [k for k, _, _ in track] + [rel.shape[0]]
        for i, (k, s, b) in enumerate(track):
            z[k:ks[i + 1]] = rel[k:ks[i + 1]] * (s or 1.0) + (b or 0.0)
    inv = np.where(z > 1e-3, D_SCALE / np.maximum(z, 1e-3), 0.0
                   ).astype(np.float32)
    if sky:
        kf_finite = {k: np.isfinite(kf[i]) for i, k in enumerate(kidx)}
        ks = sorted(kf_finite)

        def _mask(t):
            k = min(ks, key=lambda k0: abs(k0 - t)) if ks else None
            return kf_finite[k] if k is not None else None
        inv = np.stack([depth_guards.sky_far_clamp(f, l, moge_finite=_mask(t))
                        for t, (f, l) in enumerate(zip(inv, sp["small"]))])
    inv = np.stack(depth_guards.fade_flatten(list(inv), list(sp["small"])))
    z_seq = [np.where(v > 0, D_SCALE / np.maximum(v, 1e-9), np.inf)
             for v in inv]
    return inv, z_seq, track


def comfort_viol_pct(z_seq, pol):
    """Mean % of pixels per frame outside the [-1, +2] deg budget."""
    out = []
    for z in z_seq:
        zz = np.where(np.isfinite(z), np.maximum(z, pol["z_near"]), np.nan)
        d = comfort.disp_deg(zz, pol["convergence_m"],
                             ipd=pol.get("ipd_eff", comfort.IPD))
        v = np.isfinite(d)
        # 1e-3 deg slack: content clamped exactly AT the budget plane
        # (z_near by construction) is not a violation
        out.append(float(((d[v] > 2.0 + 1e-3) |
                          (d[v] < -1.0 - 1e-3)).mean() * 100.0))
    return float(np.mean(out))


def render_stats(z_seq, frames_small, surround):
    """Fill/black instrumentation over 6 sampled frames. Returns
    (fill/covered, black-in-footprint px, black fraction of the whole
    canvas). The canvas-black term is what the s28 soft surround fixes:
    with surround off, everything outside the film footprint renders
    black (a visible band at the edge of view)."""
    cov = fill = black = canvas = canvas_black = 0
    for i in np.linspace(0, len(z_seq) - 1, min(6, len(z_seq))).astype(int):
        z = np.where(np.isfinite(z_seq[i]), z_seq[i], 0.0)
        st = {}
        img = reference_render.render_frame_sbs(
            np.repeat(frames_small[i][:, :, None], 3, axis=2).astype(np.uint8),
            z, THETA_75, surround=surround, stats=st)
        for eye in st["eyes"]:
            cov += eye["covered"]
            fill += eye["pair_filled"] + eye["edge_filled"]
            black += eye["footprint_black"]
        canvas += img.shape[0] * img.shape[1]
        canvas_black += int((img.sum(axis=2) == 0).sum())
    return (fill / max(cov, 1), float(black),
            canvas_black / max(canvas, 1))


def measure_clip(work, clip):
    sp = np.load(spool_path(work, clip))
    res = {"clip": clip}
    # --- current pipeline (all fixes on)
    inv, z_seq, track = build_z(sp, weighted=True, sky=True, eased=True)
    z_stack = np.stack([np.where(np.isfinite(z), z, 0.0) for z in z_seq])
    pol = comfort.shot_comfort(
        [np.where(np.isfinite(z), z, np.nan) for z in z_seq])
    dj = flicker.depth_jitter(inv)
    pj = flicker.disparity_jitter(z_stack, THETA_75,
                                  ipd=pol["ipd_eff"])
    res["flicker"] = {"rel_med": dj["median"], "rel_p95": dj["p95"],
                      "disp_px_med": pj["median"], "disp_px_p95": pj["p95"]}
    res["comfort"] = {"policy": pol, "viol_pct": comfort_viol_pct(z_seq, pol)}
    res["comfort"]["viol_pct_default"] = comfort_viol_pct(
        [np.where(np.isfinite(z), z, np.nan) for z in z_seq],
        {"convergence_m": comfort.shot_convergence(
            [np.where(np.isfinite(z), z, np.nan) for z in z_seq]) or 2.0,
         "ipd_eff": comfort.IPD, "z_near": 1e-3})
    fill_on, black_on, cb_on = render_stats(z_seq, sp["small"], "soft")
    fill_off, black_off, cb_off = render_stats(z_seq, sp["small"], "off")
    res["disocc"] = {"fill_ratio": fill_on, "black_px": black_on,
                     "canvas_black": cb_on,
                     "fill_ratio_nosurround": fill_off,
                     "black_px_nosurround": black_off,
                     "canvas_black_nosurround": cb_off}
    # --- logo: stamp disparity (0 by construction) + z stability in the
    # stamp region over time
    from comfort_e2e import overlay_disparity, overlay_stamp
    z0 = np.where(np.isfinite(z_seq[0]), z_seq[0], 0.0)
    st = {}
    sbs = reference_render.render_frame_sbs(
        np.repeat(sp["small"][0][:, :, None], 3, axis=2).astype(np.uint8),
        z0, THETA_75, convergence_m=pol["convergence_m"],
        depth_scale=pol["depth_scale"], stats=st)
    stamped, box = overlay_stamp(sbs)
    h, w = z0.shape
    r0, r1, c0, c1 = (int(h * LOGO_BOX_FRAC[0]), int(h * LOGO_BOX_FRAC[1]),
                      int(w * LOGO_BOX_FRAC[2]), int(w * LOGO_BOX_FRAC[3]))
    reg = np.stack([np.where(np.isfinite(z[r0:r1, c0:c1]),
                             z[r0:r1, c0:c1], np.nan) for z in z_seq])
    med = np.nanmedian(reg)
    res["logo"] = {"stamp_disparity_px": overlay_disparity(stamped, box),
                   "region_z_p95_rel": float(np.nanpercentile(
                       np.abs(reg - med) / max(med, 1e-9), 95))}
    # --- ablation s30: eased vs instant keyframe application
    inv_i, _, _ = build_z(sp, weighted=True, sky=True, eased=False)
    dj_i = flicker.depth_jitter(inv_i)
    res["align"] = {"eased_p95": dj["p95"], "instant_p95": dj_i["p95"]}
    # --- ablation s35: unweighted EMA, no sky clamp
    inv_u, _, _ = build_z(sp, weighted=False, sky=False, eased=True)
    dj_u = flicker.depth_jitter(inv_u)
    res["ema"] = {"weighted_p95": dj["p95"], "unweighted_p95": dj_u["p95"]}
    res["cut"] = "n/a (single-shot clip; pinned by test_comfort shot-cut tier)"
    return res


MARGINS = {  # regression margins: rel for jitter/flicker, abs for the rest
    "flicker.rel_med": ("rel", 0.10), "flicker.rel_p95": ("rel", 0.10),
    "flicker.disp_px_med": ("rel", 0.10), "flicker.disp_px_p95": ("rel", 0.10),
    "comfort.viol_pct": ("abs", 0.05),
    "disocc.fill_ratio": ("abs", 0.002), "disocc.black_px": ("abs", 0.0),
    "disocc.canvas_black": ("abs", 0.002),
    "logo.stamp_disparity_px": ("abs", 0.0), "logo.region_z_p95_rel": ("rel", 0.15),
    "align.eased_p95": ("rel", 0.10), "ema.weighted_p95": ("rel", 0.10),
}


def flatten(res):
    out = {}
    for k, v in res.items():
        if isinstance(v, dict):
            for k2, v2 in v.items():
                if isinstance(v2, (int, float)):
                    out[k + "." + k2] = v2
    return out


def cmd_measure(a):
    clips = [c[:-10] for c in sorted(os.listdir(a.work))
             if c.endswith(".spool.npz")]
    results = [measure_clip(a.work, c) for c in clips]
    base = {"clips": {r["clip"]: flatten(r) for r in results}}
    bpath = os.path.join(a.work, "quality_baseline.json")
    with open(bpath, "w") as f:
        json.dump(base, f, indent=1, sort_keys=True)
    lines = ["# 190v visible-quality bar (s45, Linux reference pipeline)",
             "",
             "Metrics: what a viewer sees. Baseline = fix OFF via its s25-s35",
             "parameter (the old code paths no longer exist). Pipeline is",
             "deterministic on this box; regression margins in quality_baseline.json",
             "(10% rel / small abs).", ""]
    for r in results:
        c = r["clip"]
        lines += [f"## {c}",
                  f"- flicker: rel med {r['flicker']['rel_med']:.4f} / p95 {r['flicker']['rel_p95']:.4f}; rendered disparity jitter p95 {r['flicker']['disp_px_p95']:.3f} px",
                  f"- comfort: {r['comfort']['viol_pct']:.3f}% px out of budget with the s25 policy vs {r['comfort']['viol_pct_default']:.2f}% at renderer defaults (conv0/full IPD/no clamp); z_c={r['comfort']['policy']['convergence_m']:.2f} m, scale={r['comfort']['policy']['depth_scale']:.2f}",
                  f"- disocclusion: fill {r['disocc']['fill_ratio']:.5f} of covered px, black-in-footprint {r['disocc']['black_px']:.0f} px; canvas black {r['disocc']['canvas_black']:.4f} with soft surround vs {r['disocc']['canvas_black_nosurround']:.4f} off (s28)",
                  f"- align (s30): flicker p95 eased {r['align']['eased_p95']:.4f} vs instant {r['align']['instant_p95']:.4f}",
                  f"- ema (s35): flicker p95 weighted {r['ema']['weighted_p95']:.4f} vs unweighted {r['ema']['unweighted_p95']:.4f}",
                  f"- logo: stamp disparity {r['logo']['stamp_disparity_px']:.1f} px (0 = screen depth); stamp-region z p95 rel {r['logo']['region_z_p95_rel']:.4f}",
                  f"- cut: {r['cut']}", ""]
    lines += [
        "## s45 notes",
        "- s45 fix shipped from this table: depth_guards.texture_weights now",
        "  blends toward uniform on whole-frame low-texture frames (night/",
        "  noise). dark flicker p95 0.0819 -> 0.0776 (the unweighted floor is",
        "  0.0773); live/cg unchanged (blend factor a = 1 there). Swift mirror",
        "  DepthGuards.swift textureWeights updated to match.",
        "- dark align eased vs instant (+3.7%) and weighted vs unweighted EMA",
        "  (+0.4%) are within the 10% noise margin on a 24f / 2-keyframe probe;",
        "  the s30 pop evidence is on the full 36f rehearsal commits.",
        "- comfort counts a pixel only when it is past the budget by > 1e-3",
        "  deg: content clamped exactly AT the z_near budget plane is compliant",
        "  by construction, not a violation.",
        "- canvas-black is the s28 surround metric: with the surround off,",
        "  ~88-90% of the 75-deg canvas renders black (band outside the film",
        "  footprint); the soft surround brings it to 0.", ""]
    md = "\n".join(lines)
    if a.md:
        with open(a.md, "w") as f:
            f.write(md)
    print(md)
    print("baseline -> " + bpath)


def cmd_check(a):
    base = json.load(open(a.baseline))["clips"]
    bad = 0
    for clip in base:
        res = flatten(measure_clip(a.work, clip))
        for key, (kind, margin) in MARGINS.items():
            if key not in base[clip] or key not in res:
                continue
            old, new = base[clip][key], res[key]
            over = (new > old * (1 + margin) if kind == "rel"
                    else new > old + margin)
            if over:
                print(f"REGRESS {clip} {key}: {old} -> {new} "
                      f"(margin {kind} {margin})")
                bad += 1
    print("quality bar: " + ("REGRESSIONS" if bad else "all within margins"))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--clip", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--frames", type=int, default=24)
    p.add_argument("--proxy-w", type=int, default=640)
    p.add_argument("--models", default=os.path.expanduser("~/s4/models"))
    m = sub.add_parser("measure")
    m.add_argument("--work", required=True)
    m.add_argument("--md", default=None)
    c = sub.add_parser("check")
    c.add_argument("--work", required=True)
    c.add_argument("--baseline", required=True)
    a = ap.parse_args(argv)
    if a.cmd == "prepare":
        cmd_prepare(a)
    elif a.cmd == "measure":
        cmd_measure(a)
    else:
        return cmd_check(a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
