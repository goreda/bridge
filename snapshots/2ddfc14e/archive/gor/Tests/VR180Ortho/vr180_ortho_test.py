#!/usr/bin/env python3
"""190t G: pins the orthoscopic VR180 geometry reference (tools/vr180_ortho_ref.py). Linux-only; the Metal kernel is checked against these."""
import math, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools'))
import vr180_ortho_ref as g
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
W, H = 1920, 800
for deg in (40, 63, 90, 120):
    th = math.radians(deg)
    # film horizontal edge sits at lon = +-theta_h/2 exactly (no stretch): u = 0.5 +- theta_h/(2 pi)
    ue = 0.5 + th / (2 * math.pi); r = g.equirect_to_frame(ue - 1e-9, 0.5, W, H, th); l = g.equirect_to_frame(1 - ue + 1e-9, 0.5, W, H, th)
    check('theta_h=%d edge maps to frame edge' % deg, r and abs(r[0] - W) < 1e-3 and l and abs(l[0]) < 1e-3)
    check('theta_h=%d just outside the film is black' % deg, g.equirect_to_frame(ue + 0.01, 0.5, W, H, th) is None)
    c = g.equirect_to_frame(0.5, 0.5, W, H, th); check('theta_h=%d centre -> frame centre (yaw 0 pitch 0)' % deg, abs(c[0] - W/2) < 1e-6 and abs(c[1] - H/2) < 1e-6)
    # round trip, mono: frame -> equirect(infinity) -> frame
    ok = True
    for (x, y) in ((100, 50), (960, 400), (1800, 700), (5, 790)):
        u, v = g.frame_to_equirect(x, y, W, H, th); b = g.equirect_to_frame(u, v, W, H, th)
        ok &= b is not None and abs(b[0] - x) < 1e-6 and abs(b[1] - y) < 1e-6
    check('theta_h=%d mono round trip exact' % deg, ok)
# vertical extent follows aspect (derived, not set): tan(theta_v/2) = (H/W) tan(theta_h/2)
th = math.radians(63); f = g.focal(W, th)
check('focal length from theta_h', abs(f - (W/2)/math.tan(th/2)) < 1e-9)
check('vertical edge consistent with aspect (centre column)', g.equirect_to_frame(0.5, 0.5 - math.atan((H/2)/f)/math.pi + 1e-9, W, H, th)[1] < 1e-3 and g.equirect_to_frame(0.5, 0.5 - math.atan((H/2)/f)/math.pi - 1e-6, W, H, th) is None)
# stereo: infinity -> zero disparity; near object -> positive crossed disparity, monotone in nearness, scales with IPD
d_inf = g.frame_to_equirect(960, 400, W, H, th, None, -0.0315)[0] - g.frame_to_equirect(960, 400, W, H, th, None, 0.0315)[0]
check('infinity has zero disparity', abs(d_inf) < 1e-12)
ds = [g.disparity_px(960, 400, W, H, th, z, 4096) for z in (50.0, 10.0, 3.0, 1.0)]
check('nearer -> larger disparity (monotone)', all(a < b for a, b in zip(ds, ds[1:])) and ds[0] > 0)
check('centre pixel disparity ~ ipd/z in radians (small angle)', abs(ds[2] - (0.063 / 3.0) / math.pi * 4096) / ds[2] < 0.01)
check('disparity scales linearly with IPD', abs(g.disparity_px(960, 400, W, H, th, 3.0, 4096, 0.126) / ds[2] - 2.0) < 0.01)
check('parallax does not move the vertical position at the centre row', abs(g.frame_to_equirect(960, 400, W, H, th, 2.0, 0.0315)[1] - 0.5) < 1e-12)
print('vr180 ortho: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
