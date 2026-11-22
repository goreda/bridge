#!/usr/bin/env python3
"""CONTRACT-190v v2 depth decode (s3d_depth10): 10-bit luma sample -> metric Z. Python mirror of the MSL, float32, plus text pins. Swift/MSL not compiled here."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, sys, numpy as np
src = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('kernel pinned', 'kernel void s3d_depth10' in src and '256.0f / v' in src and 'w10 == 0u ? 0.0f' in src and '/ 1023.0f * 1024.0f' in src)
def z_of(r16, shift):
    w10 = np.uint32(np.round(np.float32(r16) * np.float32(65535.0))) >> np.uint32(shift)
    v = np.float32(w10) / np.float32(1023.0) * np.float32(1024.0)
    return np.float32(0.0) if w10 == 0 else np.float32(256.0) / v
for shift, enc in ((6, lambda w: w << 6), (0, lambda w: w)):
    ok = True
    for w in (0, 1, 100, 512, 1023):
        r = np.float32(enc(w)) / np.float32(65535.0)
        got = z_of(r, shift); want = 0.0 if w == 0 else 256.0 / (w / 1023.0 * 1024.0)
        ok &= abs(float(got) - want) <= 1e-4 * max(1.0, want)
    check('shift %d: samples decode to contract Z (w10=0 masked)' % shift, ok)
check('w10=1023 -> Z=0.25 m (v=1024)', abs(float(z_of(np.float32(1023 << 6) / 65535.0, 6)) - 0.25) < 1e-5)
check('decodeDepth guards size, shift<=6, nil pipeline', 'shift <= 6' in src and 'luma.width == metric.width' in src and 'guard let pipe = depth10' in src)
print('depth10: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
