"""CG VR180 end-to-end golden (contract s11 procedure, stall-class content).

Run: python3 Tests/DepthAnalysis/test_cg_vr180_golden.py
Fast tier (default, <30s on 1 CPU): internal consistency, frame-0 hash
re-render, dzc==mp4 frame 0, tear/streak pins. Full tier
(GOR_FULL_GOLDEN=1): all 48 frames, sequence hash, full dzc==mp4.
The Mac lane's Swift renderer must reproduce the same SBS bytes from the
same entry (tolerance per s11: inside-footprint byte-identical, soft
surround outside +-1 LSB; here we require exact, as the reference is
deterministic given the same entry).

Model-side regen (VDA+MoGe multistart on the CG clip) is gated on
GOR_MODELS=1 + local checkpoints and only sanity-checks fov recovery:
median hfov within 10% of the 60.0 deg CG truth and no stall signature
(every keyframe hfov > 20 deg - a stalled recovery collapses fov).
"""
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GOLD = os.path.join(HERE, "..", "..", "tools", "depth_analysis", "golden",
                    "entry_cg_vr180")
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))


def main():
    man = json.load(open(os.path.join(GOLD, "render_manifest.json")))
    prov = json.load(open(os.path.join(GOLD, "provenance.json")))
    ft = json.load(open(os.path.join(GOLD, "fov_track.json")))

    # golden self-consistency
    assert man["frames"] == 48 and man["screen_deg"] == 75.0
    assert man["swap_eyes"] is True and man["surround"] == "soft"
    assert man["out_w"] == man["out_h"] == 360  # eye_n_for(360) square eyes
    shot = ft["shots"][0]
    assert abs(shot["hfov_deg"] - prov["median_hfov_deg"]) < 1e-6
    # fov recovery sanity band vs CG truth (multistart path, s15)
    assert abs(shot["hfov_deg"] - prov["hfov_true_deg"]) / \
        prov["hfov_true_deg"] < 0.10, shot["hfov_deg"]
    assert all(v > 20.0 for _, v in shot["keyframe_values"]), "stall signature"

    # re-render from the committed entry. Fast tier (default, <30s on
    # 1 CPU): frame 0 hash + all non-render pins. Full tier
    # (GOR_FULL_GOLDEN=1): all 48 frames + sequence hash.
    full = os.environ.get("GOR_FULL_GOLDEN") == "1"
    from reference_render import golden_manifest, render_shot_sbs
    sbs, info = render_shot_sbs(GOLD, 0, max_frames=None if full else 1)
    man2 = golden_manifest(sbs, info)
    if full:
        assert man2["sequence_sha256"] == man["sequence_sha256"], \
            (man2["sequence_sha256"], man["sequence_sha256"])
        assert man2["frame_sha256"] == man["frame_sha256"]
    else:
        assert man2["frame_sha256"][0] == man["frame_sha256"][0], \
            (man2["frame_sha256"][0], man["frame_sha256"][0])

    # .dzc container must decode to the same inverse depth the mp4 carries
    import depth_container as dc
    from prepare_film import read_depth_hevc, D_SCALE
    meta = json.load(open(os.path.join(GOLD, "depth_shot_00000.json")))
    inv_mp4 = read_depth_hevc(os.path.join(GOLD, "depth_shot_00000.mp4"),
                              size=(meta["depth_height"], meta["depth_width"]),
                              max_frames=None if full else 1)[0]
    inv_dzc, _, _ = dc.read(os.path.join(GOLD, "depth_shot_00000.dzc"))
    if full:
        assert inv_mp4.shape == inv_dzc.shape
        assert np.array_equal(inv_mp4, inv_dzc), "dzc/mp4 depth disagree"
    else:
        assert np.array_equal(inv_mp4, inv_dzc[:1]), \
            "dzc/mp4 depth disagree (frame 0)"

    # distort pins (contract s20): no disocclusion tear inside the
    # footprint; surround streak energy bounded
    import math
    from reference_render import footprint_mask, render_shot_sbs as _rss
    sbs_off, info = _rss(GOLD, 0, max_frames=1, surround="off")
    for eye in range(2):
        img = sbs_off[0][:, eye * info["out_w"]:(eye + 1) * info["out_w"]]
        fp = footprint_mask(
            np.zeros((meta["source_height"], meta["source_width"], 3),
                     np.uint8),
            math.radians(info["theta_h_deg"]), 0.0,
            info["out_w"], info["out_h"])
        black_inside = int((np.all(img == 0, axis=-1) & fp).sum())
        assert black_inside == 0, f"eye {eye}: {black_inside} tear px"
    sbs_soft, _ = _rss(GOLD, 0, max_frames=1, surround="soft")
    gx = gy_worst = 0.0
    for eye in range(2):
        img = sbs_soft[0][:, eye * info["out_w"]:(eye + 1) * info["out_w"]] \
            .astype(np.float32)
        band = img[10:80, 20:340]  # pole-side surround band
        gx = max(gx, float(np.abs(band[:, 2:] - band[:, :-2]).mean()))
        # side bands: vertical gradient catches horizontal smear (s20 r3)
        fp = footprint_mask(
            np.zeros((meta["source_height"], meta["source_width"], 3),
                     np.uint8),
            math.radians(info["theta_h_deg"]), 0.0,
            info["out_w"], info["out_h"])
        ys, xs = np.where(fp)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        for side in (img[y0:y1, :x0], img[y0:y1, x1 + 1:]):
            if side.size:
                gy_worst = max(gy_worst,
                               float(np.abs(side[2:] - side[:-2]).mean()))
    assert gx < 1.0, f"surround streak energy gx {gx} (was ~4 pre-fix)"
    assert gy_worst < 1.0, \
        f"surround side-band smear gy {gy_worst} (was ~2.7 pre-r3)"

    # halo pin (s20 r3): the 1-8 px surround ring outside the footprint
    # boundary must track the boundary luma - no dark/bright halo from
    # the pre-blur or nearest extension. Per-side delta measured ~1.4
    # LSB on the live shot (source edges genuinely dark); pin 5.
    from scipy.ndimage import distance_transform_edt
    halo_worst = 0.0
    for eye in range(2):
        img = sbs_soft[0][:, eye * info["out_w"]:(eye + 1) * info["out_w"]] \
            .astype(np.float32)
        luma = img @ np.array([0.299, 0.587, 0.114], np.float32)
        fp = footprint_mask(
            np.zeros((meta["source_height"], meta["source_width"], 3),
                     np.uint8),
            math.radians(info["theta_h_deg"]), 0.0,
            info["out_w"], info["out_h"])
        strip = fp & (distance_transform_edt(fp) <= 4)
        ring = ~fp & (distance_transform_edt(~fp) <= 8)
        ys, xs = np.where(fp)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        sides = {
            "L": (slice(None), slice(None, x0)),
            "R": (slice(None), slice(x1 + 1, None)),
            "T": (slice(None, y0), slice(None)),
            "B": (slice(y1 + 1, None), slice(None)),
        }
        inside = {
            "L": (slice(None), slice(None, x0 + 4)),
            "R": (slice(None), slice(x1 - 3, None)),
            "T": (slice(None, y0 + 4), slice(None)),
            "B": (slice(y1 - 3, None), slice(None)),
        }
        for name, sl in sides.items():
            rm = np.zeros_like(ring); rm[sl] = ring[sl]
            sm = np.zeros_like(strip); sm[inside[name]] = strip[inside[name]]
            if rm.any() and sm.any():
                halo_worst = max(halo_worst, abs(
                    float(luma[rm].mean()) - float(luma[sm].mean())))
    # s28: per-content bound derived from boundary luminance. The flat
    # 10 LSB pin was CG-calibrated; on the live shot's thin bright top
    # band even an IDEAL nearest-true-boundary extension scores 15 LSB
    # (the strip catches the glow 1-3 px inside the edge at full
    # strength). Bound = max(8, 1.3 * ideal + 6): the surround must
    # track the boundary as well as the content allows, with margin.
    idx = distance_transform_edt(~fp, return_distances=False,
                                 return_indices=True)
    nearest = luma[idx[0], idx[1]]
    ideal_worst = 0.0
    for name, sl in sides.items():
        rm = np.zeros_like(ring); rm[sl] = ring[sl]
        sm = np.zeros_like(strip); sm[inside[name]] = strip[inside[name]]
        if rm.any() and sm.any():
            ideal_worst = max(ideal_worst, abs(
                float(nearest[rm].mean()) - float(luma[sm].mean())))
    bound = max(8.0, 1.3 * ideal_worst + 6.0)
    assert halo_worst < bound, \
        f"surround/boundary halo {halo_worst:.2f} LSB vs bound {bound:.2f} "\
        f"(ideal {ideal_worst:.2f}; r4 CG ~6.2, live top ~22.4)"
    print("test_cg_vr180_golden: PASS "
          f"({'FULL' if full else 'fast'} tier, hash-locked re-render, "
          f"dzc==mp4, hfov {shot['hfov_deg']:.1f} vs true "
          f"{prov['hfov_true_deg']}, tear 0 px, streak gx {gx:.3f}, "
          f"side gy {gy_worst:.3f}, halo {halo_worst:.2f} LSB)")

    if os.environ.get("GOR_MODELS") == "1":
        _regen_check(prov)


def _regen_check(prov):
    """Model-side: rerun MoGe multistart on the CG clip, fov in band."""
    import moge_fov
    import moge_recovery  # noqa: F401  (patch engages via load_moge)
    import vda_windowed
    models = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
    frames = vda_windowed.read_shot_frames("/tmp/benchcg/slice.mp4", 0, 48)
    moge = moge_fov.load_moge(os.path.join(models, "moge2_vits_normal.pt"))
    _, fv = moge_fov.infer_frame(moge, frames[12], num_tokens=600,
                                 resolution_level=5)
    assert fv is not None and fv > 20.0, "stall signature"
    assert abs(fv - prov["hfov_true_deg"]) / prov["hfov_true_deg"] < 0.15, fv
    print(f"  regen check: kf12 hfov {fv:.1f} (band ok)")


if __name__ == "__main__":
    main()
