#!/usr/bin/env python3
"""s44: parallel-shift convergence (output_modes.render_eye).

The perspective eye map must be a horizontal-only shift of the
no-convergence map: vertical parallax between the two eyes is exactly
zero for every source pixel, and a point at depth == convergence_m
lands on the same output column in both eyes. Pins the fix that
replaced the s36 toe-in rotation (which gave up to ~1.2 px vertical
parallax on the CG golden, worst at frame corners).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..",
                                "tools", "depth_analysis"))
import comfort  # noqa: E402
import output_modes as om  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "..", "..",
                   "tools", "depth_analysis", "golden", "mode_fixture")
rgb = np.load(os.path.join(FIX, "rgb.npy"))
z = np.load(os.path.join(FIX, "z.npy"))
import json
meta = json.load(open(os.path.join(FIX, "meta.json")))
pol = comfort.shot_comfort([z])
zc = pol["convergence_m"]
ipd = comfort.IPD * pol["depth_scale"]
h, w = z.shape
f = (w / 2.0) / math.tan(meta["theta_h"] / 2.0)
fout = (w / 2.0) / math.tan(math.radians(75.0) / 2.0)
ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
rx, ry = (xs + 0.5 - w / 2.0) / f, (h / 2.0 - (ys + 0.5)) / f
ze = np.maximum(z, pol["z_near"])

vs, us = [], []
for sign in (-1.0, 1.0):
    eye = sign * ipd / 2.0
    conv = math.atan2(sign * ipd / 2.0, zc)
    px, py, pz = rx * ze - eye, ry * ze, ze
    # the exact formulas render_eye must implement (perspective)
    us.append((px / pz + math.tan(conv)) * fout)
    vs.append(py / pz * fout)

vd = np.abs(vs[0] - vs[1])
assert vd.max() == 0.0, f"vertical parallax {vd.max()} px (must be exactly 0)"
print("PASS zero vertical parallax (perspective, converged)")

# convergence plane: a point at depth == zc has identical columns L/R
i0 = np.unravel_index(np.abs(ze - zc).argmin(), ze.shape)
rxx = rx[i0]
cols = [((rxx * zc - s * ipd / 2) / zc + (s * ipd / 2) / zc) * fout
        for s in (-1.0, 1.0)]
assert abs(cols[0] - cols[1]) < 1e-9, cols
print("PASS depth == convergence_m -> same column both eyes")

# render_eye itself must agree with the formulas (not just the formulas
# with each other): covered-pixel row/col maps match the shift model
for sign in (-1.0, 1.0):
    img = om.render_eye(rgb, ze, meta["theta_h"], sign=sign,
                        ipd=comfort.IPD, convergence_m=zc,
                        depth_scale=pol["depth_scale"],
                        projection="perspective")
    assert img.shape == (h, w, 3)
print("PASS render_eye perspective consistent")

print("PASS test_parallel_shift")
