#!/usr/bin/env python3
"""s36: output modes (CONTRACT-190v s36).

Golden pin per mode on a committed synthetic fixture
(tools/depth_analysis/golden/mode_fixture/): frame 0 hashes for
full_sbs, half_sbs, over_under, anaglyph (Dubois), vr180, plus eye-swap.
Geometry/comfort/packing rules asserted; hashes regenerate with:
    python3 Tests/DepthAnalysis/test_output_modes.py --relock
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))
import comfort  # noqa: E402
import output_modes as om  # noqa: E402
import reference_render as rr  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "..", "..",
                   "tools", "depth_analysis", "golden", "mode_fixture")
LOCK = os.path.join(FIX, "mode_hashes.json")


def load_fixture():
    rgb = np.load(os.path.join(FIX, "rgb.npy"))
    z = np.load(os.path.join(FIX, "z.npy"))
    meta = json.load(open(os.path.join(FIX, "meta.json")))
    return rgb, z, meta


def sha(img):
    return hashlib.sha256(img.tobytes()).hexdigest()


def render_all(rgb, z, meta):
    pol = comfort.shot_comfort([z])
    z_eff = np.maximum(z, pol["z_near"])
    kw = dict(ipd=comfort.IPD, convergence_m=pol["convergence_m"],
              depth_scale=pol["depth_scale"], screen_deg=75.0)
    out = {}
    for mode in om.MODES:
        out[mode] = om.render_mode(rgb, z_eff, meta["theta_h"], mode, **kw)
    out["full_sbs_swap"] = om.render_mode(rgb, z_eff, meta["theta_h"],
                                          "full_sbs", swap=True, **kw)
    return out, pol


rgb, z, meta = load_fixture()
frames, pol = render_all(rgb, z, meta)

# geometry: canvas sizes
w, h = meta["width"], meta["height"]
assert frames["full_sbs"].shape == (h, 2 * w, 3)
assert frames["half_sbs"].shape == (h, w, 3)
assert frames["over_under"].shape == (2 * h, w, 3)
assert frames["anaglyph"].shape == (h, w, 3)
n = om.eye_n_for(h)
assert frames["vr180"].shape == (n, 2 * n, 3)
assert om.canvas_size("full_sbs", w, h) == (2 * w, h)
assert om.canvas_size("vr180", w, h) == (2 * n, n)
print("PASS canvas geometry")

# packing: full_sbs halves are the two eyes; swap exchanges them
L = frames["full_sbs"][:, :w]; R = frames["full_sbs"][:, w:]
Ls = frames["full_sbs_swap"][:, :w]; Rs = frames["full_sbs_swap"][:, w:]
assert np.array_equal(L, Rs) and np.array_equal(R, Ls), "eye-swap must exchange the halves"
assert not np.array_equal(L, R), "eyes identical: no disparity?"
# over_under top = full_sbs left eye
assert np.array_equal(frames["over_under"][:h], L)
# half_sbs left half = horizontally squeezed L
sq = np.array(frames["half_sbs"][:, : w // 2]).astype(np.int16)
ref = L.reshape(h, w // 2, 2, 3).mean(2)
assert np.abs(sq - ref).max() <= 1, "half_sbs squeeze must be box-average"
print("PASS packing + eye-swap")

# anaglyph: Dubois keeps luminance balanced; grey input region stays grey-ish
g = frames["anaglyph"].astype(np.int16)
mid = g[h // 3:2 * h // 3, w // 3:2 * w // 3]
assert mid.std() > 0, "anaglyph not a flat field"
# comfort identical across modes: same depth content, so the same policy
# applies; assert the policy numbers that produced these frames
assert pol["convergence_m"] > 0 and 0 < pol["depth_scale"] <= 1.0
print("PASS anaglyph + comfort policy")

# vr180 eye parity with the legacy path (covered pixels): the s36
# equirect180 eye must match render_frame_sbs's eye where both cover
z_eff = np.maximum(z, pol['z_near'])
legacy = rr.render_frame_sbs(rgb, z_eff, meta["theta_h"], ipd=comfort.IPD,
                             convergence_m=pol["convergence_m"],
                             depth_scale=pol["depth_scale"], surround="off")
n = om.eye_n_for(h)
newL = om.render_eye(rgb, z_eff, meta["theta_h"], sign=-1.0, ipd=comfort.IPD,
                     convergence_m=pol["convergence_m"],
                     depth_scale=pol["depth_scale"], projection="equirect180",
                     out_w=w, out_h=h)
legL = legacy[:, :w]
both = (legL.sum(-1) > 0) & (newL.sum(-1) > 0)
agree = (np.abs(legL.astype(np.int16) - newL.astype(np.int16)).max(-1) <= 1)[both].mean()
assert agree > 0.99, f"equirect180 parity {agree}"
print("PASS equirect180 == legacy eye (covered pixels)")

hashes = {k: sha(v) for k, v in frames.items()}
if "--relock" in sys.argv:
    json.dump({"meta": meta, "hashes": hashes}, open(LOCK, "w"), indent=1)
    print("relocked", LOCK)
else:
    exp = json.load(open(LOCK))["hashes"]
    for k, v in exp.items():
        assert hashes.get(k) == v, f"{k} golden drift: {hashes.get(k)} != {v}"
    print(f"PASS golden pins ({len(exp)} modes)")

print("PASS test_output_modes")
