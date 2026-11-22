#!/usr/bin/env python3
"""195h: deterministic depth-guided gradient hole fill (s3d_fillgrad), a drop-in variant of s3d_fill behind an experiment switch.
Python mirror of the MSL row algorithm on synthetic rows, plus text pins. Swift/MSL not compiled here; Metal parity golden
capture is pending on the owner's Mac."""
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

check('kernel pinned', 'kernel void s3d_fillgrad' in src and 'GRAD_RUN = 32u' in src and 'bool nearLeft' in src)
check('short-run blend and edge runs identical to s3d_fill', src.count('SHORT_RUN_K') >= 4 and 's3d_vavg' in src)
check('switch defaults OFF', 'static var floatingWindow = false, depthOfField = false, holeFillGradient = false' in src)
check('dispatch guarded by the switch with fallback to s3d_fill', 'options.holeFillGradient ? (fillGradPipe ?? fill) : fill' in src)
check('menu row tag 9 wired', '(9,"hole-fill gradient (deterministic)")' in menu and 'case 9: Stereo3DExperiments.toggleHoleFillGradient();onExperimentChange();return' in menu)

SHORT_RUN_K, GRAD_RUN, INF = 16, 32, np.uint32(0x7F800000)
def rnd(num, den): return (2 * num + den) // (2 * den)          # s3d_round, integer-exact
def fill_row(zbits, rgb, variant):
    """Mirror of one s3d_fill/s3d_fillgrad row. zbits: uint32 float-bits (INF = hole). rgb: uint8 gray per column."""
    ow = len(zbits); out = np.zeros(ow, dtype=np.uint64)
    a, first = -1, -1
    for c in range(ow):
        if zbits[c] == INF: continue
        if a >= 0 and c - a > 1:
            g = c - a - 1
            if g <= SHORT_RUN_K:
                A, B = int(rgb[a]), int(rgb[c])
                for k in range(1, g + 1): out[a + k] = rnd(A * (g + 1 - k) + B * k, g + 1)
            else:
                za, zc = np.uint32(zbits[a]).view(np.float32), np.uint32(zbits[c]).view(np.float32)
                if variant == 'fill':
                    s = a if za >= zc else c
                    for k in range(a + 1, c): out[k] = int(rgb[s])
                else:
                    near_left = za < zc
                    far_c, near_c = (c, a) if near_left else (a, c)
                    A, B = int(rgb[near_c]), int(rgb[far_c])
                    for k in range(1, g + 1):
                        d = k if near_left else g + 1 - k
                        out[a + k] = B if d >= GRAD_RUN else rnd(A * (GRAD_RUN + 1 - d) + B * d, GRAD_RUN + 1)
        out[c] = int(rgb[c])
        if first < 0: first = c
        a = c
    return out

def bits(z): return np.float32(z).view(np.uint32)

ow = 96
z = np.array([INF] * ow, dtype=np.uint32)
z[10], z[60] = bits(1.0), bits(6.0)                            # long gap (49 px): left near, right far
rgb = np.zeros(ow, dtype=np.uint8); rgb[10], rgb[60] = 200, 40
g = fill_row(z, rgb, 'grad'); f = fill_row(z, rgb, 'fill')
check('SYNTHETIC long gap: fill holds the flat far colour, gradient ramps near->far over 32 px then holds far',
      f[11] == 40 and g[11] == rnd(200 * 32 + 40 * 1, 33) and g[41] == rnd(200 * 2 + 40 * 31, 33) and g[42] == 40 and g[59] == 40)
check('gradient reaches the far colour exactly past GRAD_RUN px and stays deterministic', g[11 + GRAD_RUN] == 40 and np.array_equal(g, fill_row(z, rgb, 'grad')))
z2 = z.copy(); z2[10], z2[60] = bits(6.0), bits(1.0)           # mirrored: near on the right
g2 = fill_row(z2, rgb, 'grad')
check('SYNTHETIC mirrored gap ramps from the right (near) endpoint', g2[59] == rnd(40 * 32 + 200 * 1, 33) and g2[11] == 200)
z3 = np.array([INF] * 30, dtype=np.uint32); z3[5], z3[15] = bits(1.0), bits(6.0)
rgb3 = np.zeros(30, dtype=np.uint8); rgb3[5], rgb3[15] = 200, 40
check('SYNTHETIC short gap (<=16): gradient variant is byte-identical to s3d_fill', np.array_equal(fill_row(z3, rgb3, 'grad'), fill_row(z3, rgb3, 'fill')))
check('valid pixels are always copied through', g[10] == 200 and g[60] == 40)

print('hole-fill gradient: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
