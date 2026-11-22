#!/usr/bin/env python3
"""s37: float32 numpy mirror of the s3d_remap Metal kernel (Sources/gor/gor/ThreeD.swift (Stereo3DKernel.swift section)) vs tools/depth_analysis/stereo_probe.place_on_vr180 / vr180_to_perspective.
cv2 is absent: the reference's cv2.remap is shimmed with scipy map_coordinates(order=1, cval=0) (true bilinear; cv2 uses 5-bit fixed point, so the tolerance is 2 codes).
Swift/MSL compile happens on the owner's build; this pins the kernel text and checks its arithmetic."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import math, pathlib, sys, types
import numpy as np
from scipy.ndimage import map_coordinates
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools/depth_analysis'))
cv2 = types.ModuleType('cv2'); cv2.INTER_LINEAR = 1; cv2.INTER_CUBIC = 2
def remap(img, mx, my, interp):
    return np.stack([map_coordinates(img[..., c].astype(np.float64), [my.astype(np.float64), mx.astype(np.float64)], order=1, mode='constant', cval=0.0) for c in range(3)], -1).round().astype(np.uint8)
cv2.remap = remap; sys.modules['cv2'] = cv2
import stereo_probe as sp
swift = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(root)).read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
for pin in ('kernel void s3d_remap', 'float lon = ((float)gid.x + 0.5f) / n * M_PI_F - M_PI_F * 0.5f, lat = M_PI_F * 0.5f - ((float)gid.y + 0.5f) / n * M_PI_F;',
            'mx = tan(lon) * p.f + (float)p.srcW * 0.5f; my = (float)p.srcH * 0.5f - tan(lat) * p.f;',
            'inside = mx >= 0.0f && mx < (float)p.srcW && my >= 0.0f && my < (float)p.srcH;',
            'float lon = atan(((float)gid.x + 0.5f - (float)p.outW * 0.5f) / p.f), lat = atan(((float)p.outH * 0.5f - (float)gid.y - 0.5f) / p.f);',
            'mx = (lon + M_PI_F * 0.5f) / M_PI_F * n - 0.5f; my = (M_PI_F * 0.5f - lat) / M_PI_F * n - 0.5f;', 'x >= (int)t.get_width()'):
    check('pinned: ' + pin[:70], pin in swift)
import re
msl_fields = re.findall(r'(uint|float) (\w+);', re.search(r'struct S3DRemap \{([^}]*)\}', swift).group(1))
sw_fields = re.findall(r'var (\w+): (UInt32|Float)', re.search(r'struct S3DRemapParams \{([^}]*)\}', swift).group(1))
check('S3DRemap (MSL) and S3DRemapParams (Swift) have the same 7 fields in the same order/types', len(msl_fields) == 7 and [(n, 'UInt32' if t == 'uint' else 'Float') for t, n in msl_fields] == [(n, t) for n, t in sw_fields])
for pin in ('renderer.remapPipe = pipe("s3d_remap")', 'func passthrough(left: MTLTexture, right: MTLTexture, sourceIsVR180: Bool, output: OutputMode, swap: Bool, sbsOut: MTLTexture) -> Bool',
            '!(sourceIsVR180 && output == .vr180)', '!needsRemap || remapPipe != nil, !needsPack || packPipe != nil', 'remap(e, t, mode: 0, f: f)', 'remap(e, t, mode: 1, f: (Double(ew) / 2.0) / half)'):
    check('pinned: ' + pin[:70], pin in swift)
f32 = np.float32
def model(src, mode, outW, outH, f):
    h, w = src.shape[:2]; ys, xs = np.mgrid[0:outH, 0:outW].astype(f32); pi = f32(math.pi)
    if mode == 0:
        n = f32(outW); lon = (xs + f32(.5)) / n * pi - pi * f32(.5); lat = pi * f32(.5) - (ys + f32(.5)) / n * pi
        mx = np.tan(lon) * f32(f) + f32(w) * f32(.5); my = f32(h) * f32(.5) - np.tan(lat) * f32(f)
        inside = (mx >= 0) & (mx < w) & (my >= 0) & (my < h)
    else:
        n = f32(w); lon = np.arctan((xs + f32(.5) - f32(outW) * f32(.5)) / f32(f)); lat = np.arctan((f32(outH) * f32(.5) - ys - f32(.5)) / f32(f))
        mx = (lon + pi * f32(.5)) / pi * n - f32(.5); my = (pi * f32(.5) - lat) / pi * n - f32(.5); inside = np.ones((outH, outW), bool)
    out = np.zeros((outH, outW, 3), np.float32)
    for c in range(3):
        out[..., c] = map_coordinates(src[..., c].astype(np.float32), [my, mx], order=1, mode='constant', cval=0.0)
    out[~inside] = 0
    return out.round().astype(np.uint8)
rng = np.random.default_rng(5)
from scipy.ndimage import gaussian_filter as gf
def tex(h, w): a = gf(rng.random((h, w, 3)), (2, 2, 0)); return (255 * (a - a.min()) / (a.max() - a.min())).astype(np.uint8)
L = tex(54, 96); R = tex(54, 96); th = 0.9075712110370514; n = 128
ref = sp.place_on_vr180(L, R, n, th); f_out = (96 / 2.0) / math.tan(th / 2.0)
mod = np.concatenate([model(L, 0, n, n, f_out), model(R, 0, n, n, f_out)], 1)
d = np.abs(ref.astype(int) - mod.astype(int)); check(f'place_on_vr180: max code diff {d.max()} (<= 2), mean {d.mean():.4f}', d.max() <= 2)
check('place_on_vr180: screen present and outside black', (ref[:, :n].sum(-1) > 0).mean() > 0.03 and (ref[:, :n].sum(-1) == 0).mean() > 0.5)
vr = np.concatenate([tex(n, n), tex(n, n)], 1); ow, oh = 96, 54
ref2 = sp.vr180_to_perspective(vr, ow, oh); f2 = (ow / 2.0) / math.tan(math.radians(75.0) / 2.0)
mod2 = [model(vr[:, :n], 1, ow, oh, f2), model(vr[:, n:], 1, ow, oh, f2)]
d2 = max(np.abs(a.astype(int) - b.astype(int)).max() for a, b in zip(ref2, mod2)); check(f'vr180_to_perspective: max code diff {d2} (<= 2)', d2 <= 2)
print('stereo remap kernel: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
