#!/usr/bin/env python3
"""DepthUpsample: numpy model of the Metal kernel (scalar per-pixel replica) vs a vectorised bilinear half-pixel/edge-clamp reference on inverse depth, plus pins.
cv2 is not installed here, so cv2.INTER_LINEAR itself is not run; the formula (half-pixel centres, edge clamp) is the documented cv2/torch(align_corners=False) one. Swift uncompiled."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'DepthGuards.swift'+' '):_b.index('// END relocated '+'DepthGuards.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated DepthUpsample.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthUpsample.swift')[0]  # 195y G2; rs = (lambda _b: _b[_b.index('// BEGIN relocated '+'RenderShotWriter.swift'+' '):_b.index('// END relocated '+'RenderShotWriter.swift'+'\n')])((_threed_split().path(root)).read_text())
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def inv(z): return np.where(z > 0, 256.0 / np.where(z > 0, z, 1), 0.0)
def kernel(z, ow, oh):  # scalar replica of s3d_depth_up
    ih, iw = z.shape; out = np.zeros((oh, ow), np.float64)
    for gy in range(oh):
        for gx in range(ow):
            fx = (gx + 0.5) * iw / ow - 0.5; fy = (gy + 0.5) * ih / oh - 0.5
            x0f, y0f = np.floor(fx), np.floor(fy); ax, ay = fx - x0f, fy - y0f
            cl = lambda v, hi: int(min(max(v, 0), hi - 1))
            x0, x1, y0, y1 = cl(x0f, iw), cl(x0f + 1, iw), cl(y0f, ih), cl(y0f + 1, ih)
            v = lambda y, x: 256.0 / z[y, x] if z[y, x] > 0 else 0.0
            vv = (v(y0, x0) * (1 - ax) + v(y0, x1) * ax) * (1 - ay) + (v(y1, x0) * (1 - ax) + v(y1, x1) * ax) * ay
            out[gy, gx] = 256.0 / vv if vv > 0 else 0.0
    return out
def reference(z, ow, oh):  # separable bilinear of the inverse plane, half-pixel centres, edge clamp
    v = inv(z); ih, iw = v.shape
    def axis(n_in, n_out):
        f = (np.arange(n_out) + 0.5) * n_in / n_out - 0.5; i0 = np.floor(f).astype(int); a = f - i0
        return np.clip(i0, 0, n_in - 1), np.clip(i0 + 1, 0, n_in - 1), a
    x0, x1, ax = axis(iw, ow); y0, y1, ay = axis(ih, oh)
    r0 = v[y0][:, x0] * (1 - ax) + v[y0][:, x1] * ax; r1 = v[y1][:, x0] * (1 - ax) + v[y1][:, x1] * ax
    vv = r0 * (1 - ay)[:, None] + r1 * ay[:, None]
    return np.where(vv > 0, 256.0 / np.where(vv > 0, vv, 1), 0.0)
rng = np.random.default_rng(7)
z = rng.uniform(0.5, 40.0, (150, 266)); z[3:6, 10:20] = 0.0                      # a hole of invalid taps
k = kernel(z[:30, :54], 107, 61); r = reference(z[:30, :54], 107, 61)
check('model: kernel replica equals the vectorised reference (non-integer 1.98x/2.03x scales, edges)', np.allclose(k, r, rtol=1e-9, atol=1e-9))
check('model: constant depth stays constant at any scale; identity size is exact', np.allclose(reference(np.full((9, 16), 3.0), 33, 19), 3.0) and np.allclose(reference(z[:8, :8], 8, 8), z[:8, :8]))
check('model: 2x of a ramp interpolates inverse depth (not Z): the midpoint of z=2 and z=4 is 256/((128+64)/2)=2.667', abs(reference(np.array([[2.0, 4.0]]), 4, 1)[0, 1] - 256 / (0.75 * 128 + 0.25 * 64)) < 1e-9)
check('model: an invalid (0) tap counts as far, never as near; all-zero stays 0', reference(np.array([[0.0, 0.0]]), 4, 1).max() == 0 and reference(np.array([[2.0, 0.0]]), 4, 1)[0, 1] > 2.0)
def compatible(d, s):
    return d[0] > 0 and d[1] > 0 and s[0] > 0 and s[1] > 0 and d[0] <= s[0] and d[1] <= s[1] and abs(d[0] / d[1] - s[0] / s[1]) / (s[0] / s[1]) <= 0.02
check('model: compatible boxes (266x150 for 1920x1080, 154x154 square, equal size) and refused ones (wrong aspect, bigger than source)', compatible((266, 150), (1920, 1080)) and compatible((154, 154), (1080, 1080)) and compatible((640, 360), (640, 360)) and not compatible((266, 154), (1920, 800)) and not compatible((2000, 1125), (1920, 1080)))
check('Metal kernel text uses the same formula', all(x in sw for x in ('((float)gid.x + 0.5f) * (float)iw / (float)ow - 0.5f', 'clamp((int)x0f, 0, (int)iw - 1)', '256.0f / z00 : 0.0f', 'v > 0.0f ? 256.0f / v : 0.0f')))
check('Swift compatible() mirrors the model (2%, never larger)', 'abs(a - b) / b <= 0.02' in sw and 'd.w <= s.w, d.h <= s.h' in sw)
check('writer: no equal-size demand any more, upsamples box -> source size, source untouched', 'guard fw == dw, fh == dh' not in rs and 'DepthUpsampleKernel.compatible(depth: (dw, dh), source: (fw, fh))' in rs and 'up.resample(box, into: metric)' in rs and 'crop(padded, to: ftex)' in rs)
check('writer: queue is the renderer\'s non-optional queue (no optional chaining on it)', 'renderer.queue?' not in rs and 'let q = renderer.queue' not in rs)
st = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSelfTest.swift'+' '):_b.index('// END relocated '+'ThreeDSelfTest.swift'+'\n')])((_threed_split().path(root)).read_text())
check('self-test uses committed prepare sidecar dimensions, not fixture storage geometry or padded export canvas', 'ShotSink.sidecarURL(entry, 0)' in st and 'depthSize: geometry.depth, sourceSize: geometry.source' in st and 'srcW: geometry.source.w, srcH: geometry.source.h' in st and 'depthSize: (VDAStream.exportW' not in st)
check('model: square-pixel 640x360 accepts266x150; actual anamorphic ToS prepared431x180 accepts266x111 and rejects266x150', not compatible((266, 154), (640, 360)) and compatible((266, 150), (640, 360)) and compatible((266, 111), (431, 180)) and not compatible((266, 150), (431, 180)))
sys.exit(1 if bad else 0)
