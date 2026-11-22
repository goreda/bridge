#!/usr/bin/env python3
"""195h E: dynamic floating window (s3d_floatwin, doi 10.1117/1.jei.21.1.011009). Python mirror of the MSL (float32) on synthetic
z-buffers, plus text pins. Swift/MSL not compiled here; Metal parity golden capture is pending on the owner's Mac."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, sys, numpy as np
root = pathlib.Path(__file__).resolve().parents[2]
src = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(root)).read_text())
menu = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDExperimentMenu.swift'+' '):_b.index('// END relocated '+'ThreeDExperimentMenu.swift'+'\n')])((_threed_split().path(root)).read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)

check('kernel pinned', 'kernel void s3d_floatwin' in src and 'p.ow / 8u' in src and '0.5f : 0.0f' in src and 'as_type<float>(z) < zs' in src)
check('switch defaults OFF', 'static var floatingWindow = false, depthOfField = false, holeFillGradient = false' in src)
check('dispatch guarded by the snapshot option', 'if options.floatingWindow {' in src)
check('render() takes one options snapshot (default .live)', 'output: OutputMode = .vr180, options: ThreeDExperimentOptions = .live) -> Bool {' in src)
_r = src[src.index('func render(frame:'):src.index('func decodeDepth(')]
check('render() reads no statics directly (snapshot only, review r4)', 'Stereo3DExperiments.' not in _r)
check('menu row tag 7 wired, toggle returns without the budget message', '(7,"E floating window")' in menu and 'case 7: Stereo3DExperiments.toggleFloatingWindow();onExperimentChange();return' in menu)
check('menu checkmark state via the locked snapshot', 'case 7:let s=Stereo3DExperiments.snapshot();row.state=s.fw ? .on:.off' in menu)

INF = np.uint32(0x7F800000)
def floatwin_row(zb, ow, eye, conv):
    """Python mirror of one s3d_floatwin row. zb: uint32 float-bits of metric z per column (INF = hole)."""
    res = zb.astype(np.float64)                      # stand-in for the row colour (the mask is what is asserted)
    tc = abs(np.tan(conv))
    if not tc > 1e-6:
        return res
    zs = abs(eye) / tc
    maxrun = ow // 8
    ext = 0
    for c in range(maxrun):
        x = c if eye < 0 else ow - 1 - c
        z = zb[x]
        if z != INF and np.uint32(z).view(np.float32) < zs:
            ext = c + 1
    for c in range(ext):
        x = c if eye < 0 else ow - 1 - c
        w = 0.5 if c + 1 == ext else 0.0
        res[x] = res[x] * w
    return res

def bits(z): return np.uint32(np.float32(z).view(np.uint32))

ow = 64
# SYNTHETIC: left eye (eye<0), a near object (z=1m) occupying the first 5 columns, background 5m, screen at 3m
ipd2, conv = 0.0315, np.arctan2(0.0315, 3.0)       # conv for a 3 m screen
row = np.array([bits(1.0)] * 5 + [bits(5.0)] * (ow - 5), dtype=np.uint32)
out = floatwin_row(row, ow, -ipd2, conv)
check('SYNTHETIC left eye: violating outer strip masked incl. feather (cols 0-3 black, col 4 half)', np.all(out[:4] == 0) and out[4] == np.float64(bits(1.0)) * 0.5 and out[5] == np.float64(bits(5.0)))
# right eye: violation lives at the RIGHT edge
row = np.array([bits(5.0)] * (ow - 5) + [bits(1.0)] * 5, dtype=np.uint32)
out = floatwin_row(row, ow, ipd2, conv)
check('SYNTHETIC right eye: outer edge follows the eye shift (cols 60-63 black, col 59 feather)', np.all(out[60:64] == 0) and out[59] == np.float64(bits(1.0)) * 0.5)
# conv 0: no screen distance, plain copy
out = floatwin_row(row, ow, ipd2, 0.0)
check('SYNTHETIC conv 0: no window (row unchanged)', np.all(out == row.astype(np.float64)))
# all far: nothing violated
row = np.array([bits(5.0)] * ow, dtype=np.uint32)
check('SYNTHETIC all-far row unchanged', np.all(floatwin_row(row, ow, -ipd2, conv) == row.astype(np.float64)))
# holes (INF) never count as violations
row = np.array([INF] * 10 + [bits(5.0)] * (ow - 10), dtype=np.uint32)
check('SYNTHETIC holes are not violations', np.all(floatwin_row(row, ow, -ipd2, conv) == row.astype(np.float64)))
# determinism
row = np.array([bits(1.0)] * 5 + [bits(5.0)] * (ow - 5), dtype=np.uint32)
check('deterministic (repeat run identical)', np.all(floatwin_row(row, ow, -ipd2, conv) == floatwin_row(row, ow, -ipd2, conv)))

print('floating window: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
