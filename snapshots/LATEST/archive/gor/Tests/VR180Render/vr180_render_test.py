#!/usr/bin/env python3
"""190t G: pins tools/vr180_render_ref.py against the scalar reference tools/vr180_ortho_ref.py (geometry) and checks z-buffer, coverage, parallax sign and hole fill."""
import math, pathlib, sys
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools'))
import vr180_ortho_ref as g, vr180_render_ref as r
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
W, H, OW, OH, TH = 64, 32, 256, 128, math.radians(63)
rng = np.random.default_rng(7)
frame = rng.integers(0, 255, (H, W, 3), dtype=np.uint8); depth = rng.uniform(1.5, 20.0, (H, W))
# 1. vectorised geometry equals the scalar reference at every pixel centre (max abs diff in output pixels)
worst = 0.0
for eye in (-0.0315, 0.0315):
    iu, iv, ok = r.eye_geometry(W, H, TH, depth, eye, OW, OH)
    for (y, x) in ((0, 0), (5, 60), (16, 32), (31, 63), (10, 20)):
        u, v = g.frame_to_equirect(x + 0.5, y + 0.5, W, H, TH, float(depth[y, x]), eye)
        worst = max(worst, abs(math.floor(u * OW) - iu[y, x]), abs(math.floor(v * OH) - iv[y, x]))
check('vector geometry == scalar reference (max diff %d px)' % worst, worst == 0)
# 2. film occupies exactly its span: coverage only inside theta_h columns, black outside
img, cov, zb = r.render_eye(frame, np.full((H, W), 1e6), TH, 0.0, OW, OH)
cols = np.flatnonzero(cov.any(axis=0)); lo, hi = (0.5 - TH / (2 * math.pi)) * OW, (0.5 + TH / (2 * math.pi)) * OW
check('coverage spans exactly theta_h columns', cols.min() >= math.floor(lo) - 1 and cols.max() <= math.ceil(hi) and abs(cols.min() - lo) < 2 and abs(cols.max() - hi) < 2)
check('outside the film is black', not img[:, :int(lo) - 1].any() and not img[:, int(hi) + 2:].any())
# 3. z-buffer: two pixels landing on one output cell, the nearer wins
iu, iv, ok = r.eye_geometry(W, H, TH, depth, 0.0, 16, 8); img4, cov4, zb4 = r.render_eye(frame, depth, TH, 0.0, 16, 8)
best = {}
for y in range(H):
    for x in range(W):
        if ok[y, x]:
            k = (iv[y, x], iu[y, x])
            if k not in best or depth[y, x] < best[k][0]: best[k] = (depth[y, x], tuple(frame[y, x]))
check('z-buffer: every cell holds its nearest sample (%d cells, many-to-one)' % len(best), all(zb4[k] == v[0] and tuple(img4[k]) == v[1] for k, v in best.items()) and len(best) < ok.sum())
# 4. parallax sign and size: a near block moves opposite ways in the two eyes by disparity_px
d3 = np.full((H, W), 50.0); d3[12:20, 28:36] = 1.0; f3 = np.zeros((H, W, 3), np.uint8); f3[12:20, 28:36] = 255
L = r.render_eye(f3, d3, TH, -0.0315, 1024, 512); R = r.render_eye(f3, d3, TH, 0.0315, 1024, 512)
cl, cr = np.flatnonzero((L[0][:, :, 0] == 255).any(axis=0)).mean(), np.flatnonzero((R[0][:, :, 0] == 255).any(axis=0)).mean()
exp = g.disparity_px(32, 16, W, H, TH, 1.0, 1024)
check('near block: left-eye image right of right-eye image by disparity_px (got %.1f, ref %.1f)' % (cl - cr, exp), cl > cr and abs((cl - cr) - exp) / exp < 0.15)
# 5. hole fill takes the far (background) side and leaves covered pixels untouched
fi, fc = r.fill_rows(L[0], L[1], L[2], -0.0315)[0], r.fill_rows(L[0], L[1], L[2], -0.0315)[1]
check('fill never overwrites covered pixels', (fi[L[1]] == L[0][L[1]]).all())
rr = int(L[1].sum(axis=1).argmax()); row = np.flatnonzero(L[1][rr]); inside = fc[rr, row.min():row.max() + 1]
check('fill closes every hole inside the film span on a row', inside.all())
print('vr180 render: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
