"""3D comfort pins (contract s25) + shot-cut behaviour (s26).

Arithmetic tier (exact): screen disparity
    disp_deg(z) = deg(2*atan(B/2z) - 2*atan(B/2z_c))
zero at the convergence plane, near clamp lands exactly on the 2 deg
crossed budget, min_convergence = B/(2 tan(0.5 deg)) = 3.6095 m.

Policy tier (by construction): shot_comfort -> z_c = shot median,
B_eff = min(IPD, 2*z_c*tan(FAR/2)), z_near from the crossed budget;
then max crossed <= 2 deg and max uncrossed >= -1 deg ALWAYS.

CG golden tier (ungated): measured bands on the committed 48-frame
entry, full frame and 2.39:1 / square crops.

Shot-cut tier (ungated): two-shot clip derived from the CG golden
(shot 1 = shot 0 geometry with depth x2 and a different hfov):
convergence is constant within a shot, steps at the cut, and the
renderer takes each shot's own fov_track hfov (no cross-cut blending).
EMA reset at cuts is pinned in test_align.py ("reset at cut").

Live tier (gated on GOR_LIVE_ENTRY): real footage bands.

Run: python3 Tests/DepthAnalysis/test_comfort.py
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DA = os.path.join(HERE, "..", "..", "tools", "depth_analysis")
GOLD = os.path.join(DA, "golden", "entry_cg_vr180")
sys.path.insert(0, DA)

import comfort
from prepare_film import D_SCALE, read_depth_hevc, write_depth_hevc


def golden_depth(step=1):
    meta = json.load(open(os.path.join(GOLD, "depth_shot_00000.json")))
    inv, _ = read_depth_hevc(os.path.join(GOLD, "depth_shot_00000.mp4"),
                             size=(meta["depth_height"], meta["depth_width"]))
    z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
    return z[::step], meta


def bands_ok(z, sc, label):
    r = comfort.distribution(z, z_c=sc["convergence_m"],
                             ipd=sc["ipd_eff"], z_near=sc["z_near"])
    assert r["max_crossed"] <= comfort.NEAR_BUDGET + 1e-9, (label, r)
    assert r["max_uncrossed"] >= -comfort.FAR_BUDGET - 1e-9, (label, r)
    return r


def main():
    B = comfort.IPD
    # --- arithmetic pins -------------------------------------------------
    assert comfort.disp_deg(1.0, 1.0, B) == 0.0
    # far overflow at z_c=1m: deg(2*atan(0.0315)) - 1 = 2.6073 deg
    assert abs(comfort.far_overflow(1.0, B) - 2.6084) < 1e-3
    assert abs(comfort.min_convergence(B, 1.0) - 3.6095) < 1e-3
    zn = comfort.near_clamp(3.6095, B)
    assert abs(zn - 1.2030) < 1e-3, zn
    assert abs(comfort.disp_deg(zn, 3.6095, B) - comfort.NEAR_BUDGET) < 1e-9
    # infinity sits exactly at -FAR_BUDGET at the min convergence
    assert abs(comfort.disp_deg(1e9, comfort.min_convergence(B), B)
               + comfort.FAR_BUDGET) < 1e-6
    print("PASS arithmetic pins (disp/near_clamp/min_convergence)")

    # --- policy holds by construction on synthetic depth ------------------
    rng = np.random.default_rng(3)
    for zmed in (0.5, 1.14, 2.64, 8.0, 30.0):
        z = rng.lognormal(np.log(zmed), 0.5, (6, 90, 160))
        z[0, :5] = 0.0  # masked pixels
        sc = comfort.shot_comfort(z)
        bands_ok(z, sc, f"synthetic zmed={zmed}")
        assert sc["depth_scale"] <= 1.0
    print("PASS shot_comfort budgets hold by construction (5 scales)")

    # --- CG golden bands (full + crops, measured s25) ---------------------
    z, meta = golden_depth(step=4)
    sc = comfort.shot_comfort(z)
    assert 1.0 < sc["convergence_m"] < 1.3, sc           # measured 1.14
    assert 0.25 < sc["depth_scale"] < 0.4, sc            # measured 0.31
    r = bands_ok(z, sc, "CG 16:9")
    assert r["max_uncrossed"] > -0.5, r                  # measured -0.17
    print(f"PASS CG golden bands: z_c {sc['convergence_m']:.2f} m, "
          f"scale {sc['depth_scale']:.2f}, "
          f"[{r['max_uncrossed']:+.2f}, {r['max_crossed']:+.2f}] deg")
    for name, crop in (("2.39:1", z[:, 46:314, :]), ("square", z[:, :, 140:500])):
        scc = comfort.shot_comfort(crop)
        bands_ok(crop, scc, f"CG {name}")
    print("PASS CG 2.39:1 + square crops inside budgets")

    # --- shot cuts: constant within shot, step at cut, per-shot fov -------
    from reference_render import _read_source_frames, render_shot_sbs
    rgb = _read_source_frames(os.path.join(GOLD, "source_shot_00000.mp4"),
                              640, 360)
    ft = json.load(open(os.path.join(GOLD, "fov_track.json")))
    h0 = ft["shots"][0]["hfov_deg"]
    with tempfile.TemporaryDirectory() as E:
        inv, _ = read_depth_hevc(os.path.join(GOLD, "depth_shot_00000.mp4"),
                                 size=(360, 640))
        zf = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
        write_depth_hevc(os.path.join(E, "depth_shot_00000.mp4"),
                         inv[:24], 24.0, 0)
        write_depth_hevc(os.path.join(E, "depth_shot_00001.mp4"),
                         np.where(zf[24:] > 0, D_SCALE / (zf[24:] * 2.0),
                                  0).astype(np.float32), 24.0, 24)
        for s, st in ((0, 0), (1, 24)):
            p = subprocess.Popen(
                ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo",
                 "-pix_fmt", "rgb24", "-s", "640x360", "-r", "24", "-i", "-",
                 "-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p",
                 os.path.join(E, f"source_shot_{s:05d}.mp4")],
                stdin=subprocess.PIPE)
            p.communicate(rgb[st:st + 24].astype(np.uint8).tobytes())
            json.dump({"depth_width": 640, "depth_height": 360, "frames": 24,
                       "start_frame": st, "fps": 24.0, "start_pts": st / 24.0,
                       "source_width": 640, "source_height": 360},
                      open(os.path.join(E, f"depth_shot_{s:05d}.json"), "w"))
        json.dump({"fps": 24.0, "shots": [
            {"shot": 0, "start": 0, "end": 23, "frames": 24,
             "median_hfov_deg": h0, "hfov_deg": h0, "confidence": 1.0,
             "keyframe_values": []},
            {"shot": 1, "start": 24, "end": 47, "frames": 24,
             "median_hfov_deg": 60.0, "hfov_deg": 60.0, "confidence": 1.0,
             "keyframe_values": []}]},
            open(os.path.join(E, "fov_track.json"), "w"))
        # convergence: constant within a shot, steps at the cut (x2 depth)
        scs = []
        for s in range(2):
            ii, _ = read_depth_hevc(os.path.join(E, f"depth_shot_{s:05d}.mp4"),
                                    size=(360, 640))
            zz = np.where(ii > 0, D_SCALE / np.maximum(ii, 1e-9), 0.0)
            sc = comfort.shot_comfort(zz)
            bands_ok(zz, sc, f"two-shot shot{s}")
            scs.append(sc)
        assert abs(scs[1]["convergence_m"] / scs[0]["convergence_m"] - 2.0) < 0.1, scs
        # per-frame convergence would pump: pin that the per-shot rule is
        # a single value for ALL frames (constant by construction) while
        # per-frame medians vary
        ii, _ = read_depth_hevc(os.path.join(E, "depth_shot_00000.mp4"),
                                size=(360, 640))
        zz = np.where(ii > 0, D_SCALE / np.maximum(ii, 1e-9), 0.0)
        per_frame = [np.median(f[f > 0]) for f in zz]
        assert max(per_frame) - min(per_frame) > 0.01  # pumping exists
        # renderer fov at the cut: each shot's info carries its OWN
        # fov_track hfov; in screen mode (75 deg) the canvas size is the
        # constant screen angle for both shots - nothing to blend, so
        # nothing can pump across the cut (legacy screen_deg=0 mode is
        # the only path where shot hfov sizes the film).
        _, i0 = render_shot_sbs(E, 0, max_frames=1, surround="off")
        _, i1 = render_shot_sbs(E, 1, max_frames=1, surround="off")
        assert i0["shot_hfov_deg"] == h0 and i1["shot_hfov_deg"] == 60.0
        assert i0["theta_h_deg"] == i1["theta_h_deg"] == 75.0
        print(f"PASS shot cuts: z_c steps {scs[0]['convergence_m']:.2f} -> "
              f"{scs[1]['convergence_m']:.2f} m at the cut; per-shot fov "
              f"({i0['shot_hfov_deg']:.1f}/{i1['shot_hfov_deg']:.1f} deg), "
              f"screen canvas constant {i0['theta_h_deg']:.0f} deg")

    # --- F3: ShotComfortSpan mirror (190v, Swift at 41b34019) -------------
    # Same synthetic shots as Tests/ShotComfortSpan/main.swift; the property
    # assertions mirror E-G's Swift-side ones so both pin one formula.
    shots = [("flat distant", 7.5, 9.0, 8.0), ("mid", 2.0, 8.0, 4.0),
             ("close deep", 0.8, 12.0, 2.5), ("far wide", 3.0, 40.0, 12.0),
             ("tiny range", 3.0, 3.05, 3.02)]
    spans = {}
    for n, a, b, c in shots:
        s = comfort.shot_comfort_span_values(a, b, c)
        spans[n] = s
        assert s["near_deg"] <= comfort.NEAR_BUDGET + 1e-9, (n, s)
        assert s["far_deg"] >= -comfort.FAR_BUDGET - 1e-9, (n, s)
    fd, cd, tr = spans["flat distant"], spans["close deep"], spans["tiny range"]
    assert fd["gain"] > 1 and fd["span_deg"] > fd["span_before_deg"], fd
    assert cd["gain"] <= 1.0 + 1e-9 and cd["span_deg"] <= 3.0 + 1e-9, cd
    assert tr["gain"] == comfort.SPAN_MAX_GAIN and tr["clamped"], tr
    for n, s in spans.items():
        print(f"PASS span {n:12s} gain {s['gain']:.2f}, span "
              f"{s['span_before_deg']:.3f} -> {s['span_deg']:.3f} deg "
              f"(near {s['near_deg']:+.2f}, far {s['far_deg']:+.2f}"
              f"{', clamped' if s['clamped'] else ''})")
    # quantile helper: numpy-linear, ignores nan / <= 0, None when empty
    assert comfort.quantile_frames([np.array([1, 2, 3, 4, 5, np.nan, 0])], 0.5) == 3.0
    assert comfort.quantile_frames([np.array([1, 2, 3, 4, 5])], 0.05) == 1.2
    assert comfort.quantile_frames([np.array([])], 0.5) is None
    assert comfort.shot_comfort_span_values(0, 1, 1) is None
    assert comfort.shot_comfort_span_values(2, 1, 1) is None
    # frame-level form: p5/p95 + median over the same frames
    fr_ = np.linspace(2.0, 8.0, 400).reshape(2, 200)
    sf = comfort.shot_comfort_span([fr_])
    sv = comfort.shot_comfort_span_values(
        float(np.percentile(fr_, 5)), float(np.percentile(fr_, 95)),
        float(np.median(fr_)))
    assert sf["gain"] == sv["gain"] and sf["span_deg"] == sv["span_deg"], (sf, sv)
    print("PASS span frame-level form equals the p5/p95/median value form")

    # --- live tier ---------------------------------------------------------
    entry = os.environ.get("GOR_LIVE_ENTRY", "/tmp/bench190v/entry")
    if not os.path.isdir(entry):
        print("live tier SKIPPED (no bench entry; set GOR_LIVE_ENTRY)")
        print("ALL COMFORT TESTS PASS")
        return
    del z, rgb  # free CG-tier arrays before the 720p live decode
    meta = json.load(open(os.path.join(entry, "depth_shot_00000.json")))
    w, h = meta["depth_width"], meta["depth_height"]
    # subsample ~every 8th frame (24 fps -> fps=3): a full 207-frame 720p
    # decode OOMs small boxes. NB: select+rawvideo on ffmpeg 4.x does not
    # drop frames here; fps=3 does.
    d = subprocess.run(
        ["ffmpeg", "-v", "error", "-i",
         os.path.join(entry, "depth_shot_00000.mp4"),
         "-vf", "fps=3", "-f", "rawvideo",
         "-pix_fmt", "yuv420p10le", "-"], capture_output=True)
    pr = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json",
         os.path.join(entry, "depth_shot_00000.mp4")],
        capture_output=True, text=True)
    inf0 = json.loads(pr.stdout)["streams"][0]
    wp, hp = int(inf0["width"]), int(inf0["height"])
    raw = np.frombuffer(d.stdout, dtype=np.uint16)
    words = hp * wp + 2 * (hp // 2) * (wp // 2)
    n = raw.size // words
    from prepare_film import V_INV_MAX
    z = np.empty((n, h, w), np.float32)
    for i in range(n):
        yy = raw[i * words:i * words + hp * wp].reshape(hp, wp)[:h, :w]
        yy = yy.astype(np.float32) / 1023.0 * V_INV_MAX
        z[i] = np.where(yy > 0, D_SCALE / np.maximum(yy, 1e-9), 0.0)
    del raw
    sc = comfort.shot_comfort(z)
    r = bands_ok(z, sc, "live")
    assert r["clamped_frac"] <= 0.05, r          # measured 0.033
    print(f"PASS live bands: z_c {sc['convergence_m']:.2f} m, "
          f"scale {sc['depth_scale']:.2f}, clamped {r['clamped_frac']:.3f}, "
          f"[{r['max_uncrossed']:+.2f}, {r['max_crossed']:+.2f}] deg")
    print("ALL COMFORT TESTS PASS")


if __name__ == "__main__":
    main()
