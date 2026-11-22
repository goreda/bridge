#!/usr/bin/env python3
"""Repro for A-D: upstream MoGe solve_optimal_focal_shift (scipy least_squares method='lm', ftol=1e-3, x0=0) stalls near shift 0 on exact-geometry scenes.
Scene: pinhole, hfov known, Z(x,y)=3+2 sin(linspace(0,6,w))[None,:]+cos(linspace(0,4,h))[:,None] metres, uv = normalized_view_plane_uv,
xy = uv*Z/focal, predicted z' = Z - shift (shift_true). Same 64x64 nearest downsample as recover_focal_shift. Prints scipy vs the truth (needs numpy+scipy)."""
import numpy as np
from scipy.optimize import least_squares
def uv_grid(w, h):
    a = w / h; sx, sy = a / (1 + a * a) ** .5, 1 / (1 + a * a) ** .5
    return np.stack(np.meshgrid(np.linspace(-sx * (w - 1) / w, sx * (w - 1) / w, w), np.linspace(-sy * (h - 1) / h, sy * (h - 1) / h, h), indexing='xy'), -1)
def solve(uv, xyz):
    uv, xy, z = uv.reshape(-1, 2), xyz[..., :2].reshape(-1, 2), xyz[..., 2].reshape(-1)
    def fn(s):
        p = xy / (z + s)[:, None]; f = (p * uv).sum() / (p * p).sum(); return (f * p - uv).ravel()
    sol = least_squares(fn, x0=0, ftol=1e-3, method='lm'); s = float(np.squeeze(sol['x'])); p = xy / (z + s)[:, None]
    return s, float((p * uv).sum() / (p * p).sum()), sol
for h, w, fov, shift in ((72, 128, 60.0, 1.3), (96, 96, 90.0, 0.4), (80, 192, 38.0, 2.5)):
    a = w / h; focal = 0.5 / np.tan(np.radians(fov) / 2) * 2 * a / (1 + a * a) ** .5
    Z = 3.0 + 2.0 * np.sin(np.linspace(0, 6, w))[None, :] + np.cos(np.linspace(0, 4, h))[:, None]
    uv = uv_grid(w, h); pts = np.concatenate([uv * Z[..., None] / focal, (Z - shift)[..., None]], -1)
    iy = np.minimum(h - 1, np.arange(64) * h // 64); ix = np.minimum(w - 1, np.arange(64) * w // 64)
    s, f, sol = solve(uv[iy][:, ix], pts[iy][:, ix])
    print('hfov %.0f shift_true %.2f -> scipy shift %.4f (status %d, nfev %d)' % (fov, shift, s, sol.status, sol.nfev))
