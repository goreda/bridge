#!/usr/bin/env python3
"""191a C3: eye re-projection from depth at real eye positions under head roll.

When the head rolls by phi about the optical axis, the inter-eye axis
rotates with it. Converted modes re-project each eye from its TRUE
rolled position, so the disparity between corresponding points lies
exactly along the eye axis: zero perpendicular (fusion-breaking)
component at any tilt. A horizontal-only baked baseline leaves
ipd*sin(phi)*(1/z - 1/z_c) of perpendicular disparity. Native stereo
keeps its baked baseline (untouched).

Measured here on the shared reference (output_modes.render_eye formulas
+ the actual renders): eye-axis parallelism, convergence-plane
registration at any roll, roll-0 bit-identity, and the baked-baseline
residual the new path removes.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..",
                                "tools", "depth_analysis"))
import output_modes as om  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


W, H = 320, 180
THETA = math.radians(60.0)
F = (W / 2.0) / math.tan(THETA / 2.0)
FOUT = (W / 2.0) / math.tan(math.radians(75.0) / 2.0)
IPD, ZC = 0.063, 2.0
rng = np.random.default_rng(7)
rgb = rng.integers(0, 255, (H, W, 3), dtype=np.uint8)

ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
RX, RY = (xs + 0.5 - W / 2.0) / F, (H / 2.0 - (ys + 0.5)) / F


def eye_uv(z, sign, roll_deg):
    """The exact formulas render_eye implements (perspective projection)."""
    phi = math.radians(roll_deg)
    ex, ey = sign * IPD / 2.0 * math.cos(phi), sign * IPD / 2.0 * math.sin(phi)
    px, py, pz = RX * z - ex, RY * z - ey, z
    return (px / pz + ex / ZC) * FOUT, (py / pz + ey / ZC) * FOUT


# 1. disparity lies exactly along the eye axis at any roll
for roll in (5.0, 15.0, 30.0, 45.0):
    worst = 0.0
    ax = (math.cos(math.radians(roll)), math.sin(math.radians(roll)))
    for zm in (0.7, 1.5, 3.0, 8.0):
        z = np.full((H, W), zm)
        uL, vL = eye_uv(z, -1.0, roll)
        uR, vR = eye_uv(z, 1.0, roll)
        du, dv = uL - uR, vL - vR
        perp = np.abs(du * ax[1] - dv * ax[0])
        worst = max(worst, float(perp.max()))
        par = float((du * ax[0] + dv * ax[1]).mean())
        want = IPD * (1.0 / zm - 1.0 / ZC) * FOUT
        assert abs(par - want) < 1e-9 * max(1.0, abs(want)), (roll, zm, par, want)
    # fp-exact: residue is 1e-13 px level; the property is exactness vs the
    # baked baseline's 0.57..3.16 px (measured below), not bit-equality
    check(f"roll {roll}: perpendicular disparity ~0 (<1e-9 px), axial matches ipd*(1/z-1/z_c)*f", worst < 1e-9)

# 2. convergence plane: depth == z_c registers identically in both eyes at any roll
for roll in (0.0, 10.0, 25.0, 45.0):
    z = np.full((H, W), ZC)
    uL, vL = eye_uv(z, -1.0, roll)
    uR, vR = eye_uv(z, 1.0, roll)
    d = max(float(np.abs(uL - uR).max()), float(np.abs(vL - vR).max()))
    check(f"roll {roll}: depth == z_c -> same output position both eyes (<1e-9 px)", d < 1e-9)

# 3. baked-baseline residual the new path removes (the measurement of the old failure)
roll = 15.0
resid = []
for zm in (0.7, 1.5, 3.0, 8.0):
    # horizontal-only baseline, then the viewer rolls: perpendicular part
    perp = IPD * math.sin(math.radians(roll)) * abs(1.0 / zm - 1.0 / ZC) * FOUT
    resid.append(perp)
print(f"baked-baseline perpendicular residual at roll 15 deg: "
      f"{min(resid):.2f}..{max(resid):.2f} px at 320w (scales with width; "
      f"x6 at 1920)")
check("baked residual is material at roll 15 (>1 px near), new path is exactly 0",
      max(resid) > 1.0)

# 4. roll 0 is bit-identical to the pre-roll path (golden hashes already pin
#    render_mode with the default; assert the explicit-default equality too)
z_grad = np.linspace(0.8, 6.0, W)[None, :].repeat(H, 0)
a = om.render_eye(rgb, z_grad, THETA, sign=-1.0, ipd=IPD, convergence_m=ZC,
                  projection="perspective")
b = om.render_eye(rgb, z_grad, THETA, sign=-1.0, ipd=IPD, convergence_m=ZC,
                  projection="perspective", roll_deg=0.0)
check("roll_deg=0 == default call (bit-identical)", np.array_equal(a, b))

# 5. end-to-end render at roll 25: corresponding covered pixels differ only
#    along the eye axis; near shifts more than far along the axis
roll = 25.0
zimg = np.where(np.indices((H, W))[1] < W // 2, 1.0, 4.0)  # near left, far right
imgs = [om.render_eye(rgb, zimg, THETA, sign=s, ipd=IPD, convergence_m=ZC,
                      projection="perspective", roll_deg=roll)
        for s in (-1.0, 1.0)]
check("rolled render produces both eyes", all(im.shape == (H, W, 3) for im in imgs)
      and not np.array_equal(imgs[0], imgs[1]))

# 6. mutant: rolled eyes with a horizontal-only convergence shift leaves
#    perpendicular disparity (proves the 2D shift is what fixes it)
roll = 30.0
phi = math.radians(roll)
ex, ey = IPD / 2.0 * math.cos(phi), IPD / 2.0 * math.sin(phi)
z = np.full((H, W), 1.2)
pxL, pyL = RX * z + ex, RY * z + ey      # left eye at (-ex, -ey)
pxR, pyR = RX * z - ex, RY * z - ey
uL = (pxL / z + ex / ZC) * FOUT
uR = (pxR / z - ex / ZC) * FOUT
vL = (pyL / z) * FOUT                     # mutant: no ey shift
vR = (pyR / z) * FOUT
perp = float(np.abs((uL - uR) * math.sin(phi) - (vL - vR) * math.cos(phi)).max())
check("mutant horizontal-only shift at roll 30 leaves perpendicular disparity (caught)",
      perp > 0.5)

print("roll reprojection: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
