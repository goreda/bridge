#!/usr/bin/env python3
"""s36: Python float32 mirror of the NEW Metal paths in Sources/gor/gor/ThreeD.swift (Stereo3DKernel.swift section): the s3d_map perspective branch (mode 1) with the parallel-shift source-frustum footprint edge-run fill,
and the s3d_pack kernel (full/half/over-under/anaglyph), checked against tools/depth_analysis/output_modes.py on the golden mode_fixture (96x54).
half_sbs tolerance: 1 code (the GPU rounds the float average, INTER_AREA rounds half up). Swift/Metal compile happens on the owner's build; render() returns false (2D path) when packPipe is nil."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import math, pathlib, sys
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools/depth_analysis')); sys.path.insert(0, str(root/'tools'))
import types
try: import cv2  # noqa  (only pack_half_sbs needs it; this test uses its own 2:1 area average)
except ImportError: sys.modules['cv2'] = types.ModuleType('cv2')
import output_modes as om
swift = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(root)).read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
f32 = np.float32; INF = np.float32(np.inf)
for pin in ('if (p.mode == 1u) {', 'if (!(z > 0.0f)) return false;', 'float uu = px / pz + tan(p.conv), vv = py / pz;',
            'o = int2((int)floor(uu * p.fout + (float)p.ow * 0.5f), (int)floor((float)p.oh * 0.5f - vv * p.fout));',
            'uint hw = ow / 2; bool isL = gid.x < hw;', 'left.read(uint2(2u * x, gid.y)).rgb', '(a + b) * 0.5f',
            'outTex.write(gid.y < oh ? left.read(gid) : right.read(uint2(gid.x, gid.y - oh)), gid);',
            'floor(clamp(a, 0.0f, 255.0f)) / 255.0f', 'renderer.packPipe = pipe("s3d_pack")', 'enc.setBuffer(flat ? flatFP : gb.fp, offset: 0, index: 2)',
            'mode: flat ? 1 : 0, fout: flat ? Float(foutD) : 0', 'let surround = surround && !flat', 'var packMode = output.packCode'):
    check('pinned: ' + pin[:64], pin in swift)
def model_eye(rgb, z, theta, sign, ipd=0.063, conv_m=None, screen_deg=75.0):
    h, w = z.shape; f = f32((w / 2.0) / math.tan(theta / 2.0)); fout = f32((w / 2.0) / math.tan(math.radians(screen_deg) / 2.0))
    eye = f32(sign * ipd / 2.0); conv = f32(math.atan2(sign * ipd / 2.0, conv_m)) if conv_m else f32(0)
    zb = np.full((h, w), INF, f32); mp = {}
    for y in range(h):
        for x in range(w):
            zz = f32(z[y, x]); rx = (f32(x) + f32(.5) - f32(w) * f32(.5)) / f; ry = (f32(h) * f32(.5) - (f32(y) + f32(.5))) / f
            px = rx * zz - eye; py = ry * zz; pz = zz
            if not zz > 0: continue
            ox = int(np.floor((px / pz + np.tan(conv)) * fout + f32(w) * f32(.5))); oy = int(np.floor(f32(h) * f32(.5) - py / pz * fout))
            if 0 <= ox < w and 0 <= oy < h: mp[(y, x)] = (ox, oy); zb[oy, ox] = min(zb[oy, ox], zz)
    rendered = np.zeros((h, w, 3), np.uint8)
    for (y, x), (ox, oy) in mp.items():
        if zb[oy, ox] == f32(z[y, x]): rendered[oy, ox] = rgb[y, x]
    import vr180_render_ref as fillref
    cov = zb != INF
    res, _ = fillref.fill_rows(rendered, cov, zb, eye)
    yy,xx=np.mgrid[0:h,0:w].astype(float)
    uu=(xx+.5-w/2)/float(fout)-math.tan(float(conv)); vv=(h/2-(yy+.5))/float(fout)
    sx=float(f)*uu+w/2; sy=h/2-float(f)*vv
    fp=(sx>=0)&(sx<w)&(sy>=0)&(sy<h)
    res = fillref.fill_edge_runs(res, cov, fp)
    return res
def model_pack(L, R, mode):
    h, w = L.shape[:2]
    if mode == 0: return np.concatenate([L, R], 1)
    if mode == 2: return np.concatenate([L, R], 0)
    if mode == 1:
        sq = lambda im: np.floor((im[:, 0::2].astype(f32) + im[:, 1::2].astype(f32)) * f32(.5) + f32(.5)).astype(np.uint8)
        return np.concatenate([sq(L)[:, :w // 2], sq(R)[:, :w // 2]], 1)
    l = L.astype(f32); r = R.astype(f32)
    a = l @ om.DUBOIS_L.astype(f32).T + r @ om.DUBOIS_R.astype(f32).T + f32(.5)
    return np.floor(np.clip(a, 0, 255)).astype(np.uint8)
fx = root/'tools/depth_analysis/golden/mode_fixture/'
rgb = np.load(fx/'rgb.npy'); z = np.load(fx/'z.npy'); th = 0.9075712110370514
for conv_m in (None, 2.5):
    for swap in (False, True):
        s = [1.0, -1.0] if swap else [-1.0, 1.0]
        ref = [om.render_eye(rgb, z, th, sign=g, convergence_m=conv_m) for g in s]
        mod = [model_eye(rgb, z, th, g, conv_m=conv_m) for g in s]
        bad = max(float((a != b).any(axis=2).mean()) for a, b in zip(ref, mod))
        check(f'perspective eyes conv={conv_m} swap={swap}: float32 model vs float64 reference differ on {bad*100:.2f}% pixels (< 1.5%)', bad < 0.015)
        for name, code, fn in (('full_sbs', 0, om.pack_full_sbs), ('over_under', 2, om.pack_over_under), ('anaglyph', 3, om.anaglyph_dubois)):
            d = np.abs(model_pack(ref[0], ref[1], code).astype(int) - fn(ref[0], ref[1]).astype(int)).max()
            check(f'pack {name} conv={conv_m} swap={swap}: max code diff {d} (<= {1 if code == 3 else 0})', d <= (1 if code == 3 else 0))
        h, w = ref[0].shape[:2]
        hs = model_pack(ref[0], ref[1], 1)
        exp = np.concatenate([np.floor((im[:, 0::2].astype(float) + im[:, 1::2]) / 2 + .5).astype(int) for im in ref], 1)
        check(f'pack half_sbs conv={conv_m} swap={swap}: within 1 code of the 2:1 area average', np.abs(hs.astype(int) - exp).max() <= 1 and hs.shape == (h, w, 3))
print('output_modes kernel: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
