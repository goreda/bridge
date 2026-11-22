"""Stall-safe MoGe focal/shift recovery (contract s15).

Upstream solve_optimal_focal_shift / solve_optimal_shift (moge utils
geometry_numpy, scipy least_squares method='lm', x0=0, ftol=1e-3) stalls on
exact-geometry scenes with a large shift/z ratio: it returns shift ~0 after
5-9 nfev (ftol stop) while the true shift is 0.4-2.5. Confirmed on E-G's
repro scenes (hfov 60/90/38, NOT only 175-180) and absent on small-shift
content (production anim/live converge identically from every start).

Fix (verified on all three failing scenes): multistart over
{0, .5, 1, 2, 4} and pick the minimum-cost solution. Stalled starts sit at
cost ~1.3e3 vs ~1e-20-0.35 for the truth - a >3-orders separation, so
min-cost selection is unambiguous. Residuals and the closed-form focal are
identical to upstream; only the starting point and selection change.

Production hook: moge_fov monkey-patches
moge.utils.geometry_torch.solve_optimal_focal_shift with the multistart
version below, so MoGeModel.infer() uses it transparently. E-G's Swift port
should implement the same multistart selection (its single-start run
happened to converge; the fixture pins truth on the stall scenes).
"""
import numpy as np
from scipy.optimize import least_squares

STARTS = (0.0, 0.5, 1.0, 2.0, 4.0)


def _residual(uv, xy, z):
    def fn(s):
        p = xy / (z + s)[:, None]
        f = (p * uv).sum() / (p * p).sum()
        return (f * p - uv).ravel()
    return fn


def solve_optimal_focal_shift(uv, xyz):
    """Multistart drop-in for moge.utils.geometry_numpy.solve_optimal_focal_shift.

    uv [N,2], xyz [N,3] -> (shift, focal). Same upstream solver per start.
    """
    uv = np.asarray(uv, np.float64).reshape(-1, 2)
    xyz = np.asarray(xyz, np.float64).reshape(-1, 3)
    xy, z = xyz[:, :2], xyz[:, 2]
    fn = _residual(uv, xy, z)
    best = None
    for x0 in STARTS:
        sol = least_squares(fn, x0=np.array([x0]), ftol=1e-3, method='lm')
        s = float(np.squeeze(sol['x']))
        cost = float((fn(s) ** 2).sum())
        if best is None or cost < best[0]:
            best = (cost, s)
    _, shift = best
    p = xy / (z + shift)[:, None]
    focal = float((p * uv).sum() / (p * p).sum())
    return shift, focal


def solve_optimal_shift(uv, xyz, focal):
    """Multistart drop-in for solve_optimal_shift (focal known)."""
    uv = np.asarray(uv, np.float64).reshape(-1, 2)
    xyz = np.asarray(xyz, np.float64).reshape(-1, 3)
    xy, z = xyz[:, :2], xyz[:, 2]

    def fn(s):
        return (float(focal) * xy / (z + s)[:, None] - uv).ravel()

    best = None
    for x0 in STARTS:
        sol = least_squares(fn, x0=np.array([x0]), ftol=1e-3, method='lm')
        s = float(np.squeeze(sol['x']))
        cost = float((fn(s) ** 2).sum())
        if best is None or cost < best[0]:
            best = (cost, s)
    return best[1]


def patch_moge():
    """Make MoGeModel.infer use the multistart solvers."""
    import moge.utils.geometry_torch as gt
    gt.solve_optimal_focal_shift = solve_optimal_focal_shift
    gt.solve_optimal_shift = solve_optimal_shift
