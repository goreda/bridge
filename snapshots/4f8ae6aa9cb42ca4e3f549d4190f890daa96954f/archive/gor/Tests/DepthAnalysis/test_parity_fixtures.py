"""Verify the Python reference against the parity fixtures (contract s15).

Run: python3 Tests/DepthAnalysis/test_parity_fixtures.py
The Swift ports run the same JSONs on the Mac; this test pins the fixture
to the Python implementation so the two cannot drift apart.
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PAR = os.path.join(HERE, "parity")
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))


def close(a, b, rel=None, abs_=None):
    a, b = float(a), float(b)
    if rel is not None and abs(a - b) > rel * max(1.0, abs(b)):
        raise AssertionError(f"{a} vs {b} (rel {rel})")
    if abs_ is not None and abs(a - b) > abs_:
        raise AssertionError(f"{a} vs {b} (abs {abs_})")


def test_moge_recovery():
    import moge_recovery as mr
    import make_parity_fixtures as gen

    g = json.load(open(os.path.join(PAR, "moge_recovery.json")))
    a = np.array  # shorthand
    assert np.allclose(gen.normalized_uv(4,3),a(g['uv_pin_w4_h3']),rtol=0,atol=1e-12), 'uv grid fixture changed'
    for case in ("case_known", "case_noisy"):
        c = g[case]
        pts = a(c["points"], dtype=np.float64).reshape(-1, 3)
        h, w = c["h"], c["w"]
        uv = gen.normalized_uv(w, h).reshape(-1, 2)
        shift, focal = mr.solve_optimal_focal_shift(uv, pts)
        close(shift, c["expect"]["shift"], abs_=c["tolerance"]["shift_abs"])
        close(focal, c["expect"]["focal"], rel=c["tolerance"]["focal_rel"])
    c = g["case_given_focal"]
    pts = a(c["points"], dtype=np.float64).reshape(-1, 3)
    uv = gen.normalized_uv(c["w"], c["h"]).reshape(-1, 2)
    s = mr.solve_optimal_shift(uv, pts, c["focal"])
    close(s, c["expect"]["shift"], abs_=c["tolerance"]["shift_abs"])
    # stall scenes: regenerate, solve, must hit truth (s15)
    for sc in g["stall_cases"]:
        uv, pts, _f = gen.moge_recovery_scene(sc["h"], sc["w"],
                                              sc["hfov_deg"],
                                              sc["shift_true"])
        shift, focal = mr.solve_optimal_focal_shift(uv, pts)
        close(shift, sc["expect_shift"], abs_=sc["tol_shift"])
        close(focal, sc["expect_focal"], rel=sc["tol_focal_rel"])
    ms = g["metric_scale"]
    got = a(ms["depth"]) * ms["metric_scale"]
    assert np.allclose(got, a(ms["expect_scaled"]), rtol=ms["tolerance_rel"])
    print("  moge_recovery: PASS")


def test_align():
    from align import ShotAligner

    g = json.load(open(os.path.join(PAR, "align.json")))
    vda = np.array(g["vda"], dtype=np.float64)
    moge = np.array(g["moge"], dtype=np.float64)
    moge = np.where(moge >= g["moge_inf_marker"], np.inf, moge)
    al = ShotAligner(ema=g["ema"])
    for k, exp in enumerate(g["expect_frames"]):
        out = al.update(vda[k], moge[k])
        close(al.scale, exp["scale"], rel=g["tolerance_rel"])
        close(al.shift, exp["shift"], rel=g["tolerance_rel"])
        assert al.skipped == exp["skipped_total"], (k, al.skipped)
        assert np.allclose(out[0], np.array(exp["aligned_row0"]),
                           rtol=g["tolerance_rel"], atol=1e-9), k
    print("  align: PASS")


def test_depth_quant():
    # Read the real production constants without importing model inference.
    # No hard-coded replacement values: a production change still hits fixtures.
    import ast
    tree=ast.parse(open(os.path.join(HERE,'../../tools/depth_analysis/prepare_film.py')).read())
    constants={n.targets[0].id:ast.literal_eval(n.value) for n in tree.body
               if isinstance(n,ast.Assign) and len(n.targets)==1 and isinstance(n.targets[0],ast.Name)
               and n.targets[0].id in ('D_SCALE','V_INV_MAX')}
    D_SCALE,V_INV_MAX=constants['D_SCALE'],constants['V_INV_MAX']

    g = json.load(open(os.path.join(PAR, "depth_quant.json")))
    for row in g["cases"]:
        z = row["z"]
        v = D_SCALE / z if z > 0 else 0.0
        w10 = int(np.clip(np.rint(np.float32(v) / V_INV_MAX * 1023.0),
                          0, 1023))
        assert w10 == row["w10"], (z, w10, row["w10"])  # exact integer pin
        inv = w10 / 1023.0 * V_INV_MAX
        close(inv, row["inv_roundtrip"], abs_=1e-4)
        if row["z_roundtrip"] is not None:
            close(D_SCALE / inv, row["z_roundtrip"], abs_=1e-4)
    print("  depth_quant: PASS")


def test_cut_detect():
    from cuts import SCDET_THRESHOLD, shots_from_cuts

    g = json.load(open(os.path.join(PAR, "cut_detect.json")))
    assert g["spec"]["threshold"] == SCDET_THRESHOLD
    c = g["case"]
    frames = sorted({int(t * c["fps"] + 0.5) for t in c["times_s"]})
    assert frames == c["expect_cut_frames"], frames
    got = [list(r) for r in shots_from_cuts(c["n_frames"], frames)]
    assert got == c["expect_ranges"], got
    for e in g["edge_cases"]:
        fr = sorted({int(t * e["fps"] + 0.5) for t in e["times_s"]})
        got = [list(r) for r in shots_from_cuts(e["n_frames"], fr)]
        assert got == e["expect_ranges"], (e, got)
    print("  cut_detect: PASS")


if __name__ == "__main__":
    test_moge_recovery()
    test_align()
    test_depth_quant()
    test_cut_detect()
    print("test_parity_fixtures: PASS")
