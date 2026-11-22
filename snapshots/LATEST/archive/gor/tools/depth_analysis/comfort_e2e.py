"""End-to-end comfort pipeline metrics (contract s27).

Runs the full reference chain on a prepared entry - depth -> shot
comfort -> render SBS (soft surround r3) - under two parameter sets:

  "default": the pre-comfort renderer defaults (convergence_m=None,
             depth_scale=1, no near clamp) - what the committed goldens
             pin (renderer mechanics).
  "comfort": comfort.shot_comfort(z_shot): z_c = shot median,
             B_eff = min(IPD, 2*z_c*tan(0.5 deg)) via depth_scale,
             z clamped to z_near (crossed-budget clamp).

Metrics per mode (before/after comparison):
  fill_frac       disocclusion artifact area: (pair_fill + edge_run_fill)
                  / footprint px, averaged over eyes and frames.
  footprint_black black pixels left inside the footprint (must be 0).
  halo_lsb        worst per-side |ring(1-8px outside footprint) luma
                  - boundary(4px strip inside) luma| (s20 r3 metric).
  disp_jitter     s21 rendered-disparity second-difference jitter (px),
                  computed on the disparity field of the mode's own
                  parameters (B_eff / clamped z for comfort).

Subtitle/overlay rule (s27 audit): overlays composite POST-render at
identical canvas coordinates in both eyes. Zero angular disparity =
the element sits at the convergence plane (screen depth) by
construction; never route overlay content through the depth map or
render_frame_sbs scene input. overlay_stamp() is the canonical recipe
pinned by Tests/DepthAnalysis/test_comfort_e2e.py.
"""
import json
import math
import os

import numpy as np

import comfort
from flicker import disparity_jitter
from reference_render import (footprint_mask, render_frame_sbs,
                              render_shot_sbs, theta_h_for)


def _shot_depth(entry_dir, shot, max_frames=None):
    from prepare_film import D_SCALE, read_depth_hevc
    meta = json.load(open(os.path.join(entry_dir,
                                       f"depth_shot_{shot:05d}.json")))
    inv, _ = read_depth_hevc(
        os.path.join(entry_dir, f"depth_shot_{shot:05d}.mp4"),
        size=(meta["depth_height"], meta["depth_width"]),
        max_frames=max_frames)
    return np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0), meta


def _halo_lsb(sbs, source_wh, theta_h_deg, convs, out_w, out_h,
              per_side=None):
    """s20 r3 halo: worst per-side ring-vs-boundary luma delta (LSB).
    convs: per-eye convergence angles (rad) used for the footprint."""
    from scipy.ndimage import distance_transform_edt
    sw, sh = source_wh
    worst = 0.0
    for eye in range(2):
        fp = footprint_mask(np.zeros((sh, sw, 3), np.uint8),
                            math.radians(theta_h_deg), convs[eye],
                            out_w, out_h)
        strip = fp & (distance_transform_edt(fp) <= 4)
        ring = ~fp & (distance_transform_edt(~fp) <= 8)
        ys, xs = np.where(fp)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        sides = {"L": (slice(None), slice(None, x0)),
                 "R": (slice(None), slice(x1 + 1, None)),
                 "T": (slice(None, y0), slice(None)),
                 "B": (slice(y1 + 1, None), slice(None))}
        inside = {"L": (slice(None), slice(None, x0 + 4)),
                  "R": (slice(None), slice(x1 - 3, None)),
                  "T": (slice(None, y0 + 4), slice(None)),
                  "B": (slice(y1 - 3, None), slice(None))}
        img = sbs[:, eye * out_w:(eye + 1) * out_w].astype(np.float32)
        luma = img @ np.array([0.299, 0.587, 0.114], np.float32)
        for name, sl in sides.items():
            rm = np.zeros_like(ring); rm[sl] = ring[sl]
            sm = np.zeros_like(strip); sm[inside[name]] = strip[inside[name]]
            if rm.any() and sm.any():
                d = abs(float(luma[rm].mean()) - float(luma[sm].mean()))
                if per_side is not None:
                    per_side[f"eye{eye}:{name}"] = d
                worst = max(worst, d)
    return worst


def run_case(entry_dir, shot=0, mode="comfort", max_frames=None,
             screen_deg=75.0):
    """Full reference chain on one shot. Returns (sbs, info, metrics)."""
    assert mode in ("default", "comfort")
    z, meta = _shot_depth(entry_dir, shot, max_frames)
    ft = json.load(open(os.path.join(entry_dir, "fov_track.json")))
    th = theta_h_for(screen_deg,
                     math.radians(ft["shots"][shot]["hfov_deg"]),
                     meta["source_width"] / meta["source_height"])
    if mode == "comfort":
        sc = comfort.shot_comfort(z)
        conv_m, ds, z_near = (sc["convergence_m"], sc["depth_scale"],
                              sc["z_near"])
        z_render = np.where(z > 0, np.maximum(z, z_near), 0.0)
        ipd = comfort.IPD * ds
    else:
        conv_m, ds, z_near, z_render, ipd = None, 1.0, None, z, comfort.IPD
    stats_list = []
    sbs, info = render_shot_sbs(entry_dir, shot, convergence_m=conv_m,
                                depth_scale=ds, max_frames=max_frames,
                                screen_deg=screen_deg, z_near=z_near,
                                stats_list=stats_list)
    ow, oh = info["out_w"], info["out_h"]
    fill_frac = float(np.mean([
        sum(e["pair_filled"] + e["edge_filled"] for e in st["eyes"])
        / sum(e["footprint_px"] for e in st["eyes"])
        for st in stats_list]))
    black = int(max(sum(e["footprint_black"] for e in st["eyes"])
                    for st in stats_list))
    ipd_eff = comfort.IPD * ds
    convs = [math.atan2(s * ipd_eff / 2.0, conv_m)
             if conv_m and conv_m > 0 else 0.0
             for s in ([1.0, -1.0] if info["swap_eyes"] else [-1.0, 1.0])]
    per_side = {}
    halo = _halo_lsb(sbs[0], (meta["source_width"], meta["source_height"]),
                     info["theta_h_deg"], convs, ow, oh, per_side)
    dj = disparity_jitter(z_render, th, ipd=ipd, out_w=ow)
    metrics = {"mode": mode, "fill_frac": fill_frac,
               "footprint_black": black,
               "halo_lsb": float(halo),
               "halo_per_side": per_side,
               "disp_jitter": dj,
               "convergence_m": conv_m, "depth_scale": ds,
               "z_near": z_near}
    return sbs, info, metrics


def overlay_stamp(sbs, text_like=True):
    """Canonical overlay recipe: stamp at IDENTICAL canvas coordinates
    in both eyes (zero angular disparity = screen depth at z_c).
    Post-render: the depth map, near clamp and convergence never touch
    the stamp. Returns (stamped_sbs, (r0, r1, c0, c1) eye-local box)."""
    out = sbs.copy()
    oh, ow2 = sbs.shape[0], sbs.shape[1] // 2
    r0, r1 = int(oh * 0.82), int(oh * 0.90)
    c0, c1 = int(ow2 * 0.30), int(ow2 * 0.70)
    for eye in range(2):
        block = out[r0:r1, eye * ow2 + c0:eye * ow2 + c1]
        if text_like:  # glyph-like vertical bars, ~subtitle texture
            block[...] = 32
            block[:, ::8] = 235
            block[:, 3::8] = 200
        else:
            block[...] = 255
    return out, (r0, r1, c0, c1)


def overlay_disparity(sbs, box):
    """Measured L/R shift (canvas px) of an overlay in box: cross-
    correlate the row-mean luma profiles. 0 px = screen depth."""
    r0, r1, c0, c1 = box
    ow = sbs.shape[1] // 2
    l = sbs[r0:r1, c0:c1, :].mean(axis=2).mean(axis=0)
    r = sbs[r0:r1, ow + c0:ow + c1, :].mean(axis=2).mean(axis=0)
    l = l - l.mean(); r = r - r.mean()
    xc = np.correlate(np.pad(l, 16), r, "valid")
    return float(np.argmax(xc) - 16)
