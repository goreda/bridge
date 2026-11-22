#!/usr/bin/env python3
"""ShotComfort.swift (pure Foundation, compiled and run here) vs tools/depth_analysis/comfort.py: exact pins, shot_comfort on random depth (shrunk and full baseline),
the w10 histogram median vs numpy median of the dequantised values. Run: SWIFTC=... python3 Tests/ShotComfort/shot_comfort_test.py"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'tools/depth_analysis'))
import comfort as C
swiftc = os.environ.get('SWIFTC', 'swiftc'); tmp = Path(tempfile.mkdtemp()); exe = tmp / 'sc'
# 195y G2: ShotComfort.swift also carries the relocated ShotComfortSpan/ShotCuts/ShotComfortShot spans; the ShotComfortShot span needs DZCFile, out of this test's scope
sc = (lambda _b: _b[_b.index('// BEGIN relocated '+'ShotComfort.swift'+' '):_b.index('// END relocated '+'ShotComfort.swift'+'\n')])((_threed_split().path(root)).read_text())
sc = sc[:sc.index('// BEGIN relocated ShotComfortShot.swift (195y G2, behavior unchanged)')] + sc[sc.index('// END relocated ShotComfortShot.swift'):]
tmp_sc = tmp / 'ShotComfort.swift'; tmp_sc.write_text(sc)
r = subprocess.run([swiftc, '-O', str(tmp_sc), str(root / 'Tests/ShotComfort/main.swift'), '-o', str(exe)], capture_output=True, text=True)
if r.returncode: print(r.stderr); sys.exit(1)
rng = np.random.default_rng(7); lines = []; cases = []; scases = []
for zc in (0.4, 1.14, 2.58, 3.6, 8.0, 30.0):
    for st in (0.0, 0.5, 0.75, 1.0, 1.25, 2.0):
        for ob in (0, 1): lines.append('strength %r %r %d' % (zc, st, ob)); scases.append((zc, st, ob))
for scale in (0.4, 1.0, 2.58, 9.0, 40.0):
    fr = [rng.lognormal(np.log(scale), 0.5, (6, 8)).astype(np.float32) for _ in range(3)]
    fr[0][0, 0] = 0; fr[1][1, 1] = np.inf; fr[2][2, 2] = np.nan; fr[2][3, 3] = -1
    w = np.clip(np.rint(256.0 / np.maximum(np.nan_to_num(np.concatenate([f.ravel() for f in fr]), nan=0.0, posinf=0.0, neginf=0.0), 1e-3) / 1024 * 1023), 0, 1023).astype(np.int64)
    w[::17] = 0
    for f in fr: lines.append('frame ' + ' '.join(repr(float(x)) for x in f.ravel()))
    lines.append('w10 ' + ' '.join(str(int(x)) for x in w))
    lines.append('end'); cases.append((fr, w))
out = subprocess.run([str(exe)], input='\n'.join(lines) + '\n', capture_output=True, text=True, check=True).stdout.splitlines()
sout = [l for l in out if l.startswith('strength')]; out = [l for l in out if not l.startswith('strength')]
pins = [float(x) for x in out[0].split()[1:]]
assert abs(pins[0] - 2.6084) < 1e-3 and abs(pins[1] - 3.6095) < 1e-3 and abs(pins[2] - 1.2030) < 1e-3, pins
assert abs(pins[0] - float(C.far_overflow(1.0))) < 1e-9 and abs(pins[1] - C.min_convergence()) < 1e-9 and abs(pins[2] - float(C.near_clamp(3.6095))) < 1e-9
print('pins ok', pins)
for (fr, w), line in zip(cases, out[1:]):
    t = line.split(); want = C.shot_comfort(fr)
    assert abs(float(t[1]) - want['convergence_m']) < 1e-6 * want['convergence_m'], (t, want)
    got = [float(x) for x in t[2:6]]
    for g, k in zip(got, ('ipd_eff', 'depth_scale', 'z_near', 'far_overflow_deg')):
        assert abs(g - want[k]) < 1e-6 * max(1.0, abs(want[k])), (k, g, want[k])
    v = w[w > 0]; zq = 256.0 / (v / 1023.0 * 1024.0)
    assert abs(float(t[-1]) - float(np.median(zq))) < 1e-9 * float(np.median(zq)), (t[-1], np.median(zq))
    print('case ok z_c %.4f scale %.4f z_near %.4f' % (want['convergence_m'], want['depth_scale'], want['z_near']))
for (zc, st, ob), line in zip(scases, sout):
    f, b, near, far = [float(x) for x in line.split()[1:]]
    want_f = 0.0 if st <= 0 else (st if ob else min(st, 1.0)); assert abs(f - want_f) < 1e-12, (zc, st, ob, f)
    sc = C.shot_comfort([np.full((2, 2), zc, np.float64)]); assert abs(b - C.IPD * sc['depth_scale'] * want_f) < 1e-9
    if want_f > 0 and want_f <= 1.0:   # within budget BY CONSTRUCTION, whatever the strength
        assert near <= C.NEAR_BUDGET + 1e-6 and far >= -C.FAR_BUDGET - 1e-6, (zc, st, ob, near, far)
        assert abs(near - float(C.disp_deg(sc['z_near'], zc, b))) < 1e-6
    if want_f > 1.0:                   # explicit over-budget level: allowed to exceed, must not be silently capped
        assert st == f and (near > C.NEAR_BUDGET - 1e-6 or far < -C.FAR_BUDGET + 1e-6 or zc > 3.7), (zc, st, near, far)
print('strength on comfort ok: %d cases (<=1 inside both budgets; >1 capped to 1 unless over_budget)' % len(scases))
print('PASS')
