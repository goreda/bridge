#!/usr/bin/env python3
"""195h G: depth-guided defocus (s3d_dof, Held & Banks 2012 blur+disparity). Python mirror of the MSL (float32) on synthetic
frames, plus text pins. Swift/MSL not compiled here; Metal parity golden capture is pending on the owner's Mac."""
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

check('kernel pinned', 'kernel void s3d_dof' in src and '28.0f * fabs(1.0f / z - 1.0f / zf)' in src and 'clamp(' in src and ', 12.0f)' in src)
check('switch defaults OFF', 'static var floatingWindow = false, depthOfField = false, holeFillGradient = false' in src)
check('dispatch guarded by the snapshot option', 'if options.depthOfField {' in src)
check('review r1: dof reads Params at buffer 1; buffer 0 stays the z-buffer', 'constant S3DParams& p [[buffer(1)]], uint2 gid [[thread_position_in_grid]]' in src and 'setBytes(&p, length: MemoryLayout<Params>.size, index: 0)' not in src)
check('resolve reads the blurred source only via srcFrame', 'enc.setTexture(srcFrame, index: 0); enc.setTexture(depth, index: 1); enc.setTexture(rendered, index: 2); dispatch(resolve, src)' in src)
check('menu row tag 8 wired', '(8,"G depth defocus (Held-Banks)")' in menu and 'case 8: Stereo3DExperiments.toggleDepthOfField();onExperimentChange();return' in menu)

TAPS = [(1,0),(-1,0),(0,1),(0,-1),(np.sqrt(.5),np.sqrt(.5)),(-np.sqrt(.5),np.sqrt(.5)),(np.sqrt(.5),-np.sqrt(.5)),(-np.sqrt(.5),-np.sqrt(.5)),(0.5,0.866),(-0.5,0.866),(0.5,-0.866),(-0.5,-0.866)]
def radius(z, zf, znear=0.0):
    z = np.float32(z)
    if z > 0: z = max(z, np.float32(znear))
    if not z > 0: return 0.0
    return float(np.clip(np.float32(28.0) * abs(np.float32(1.0)/z - np.float32(1.0)/np.float32(zf)), np.float32(0), np.float32(12.0)))
def dof(frame, depth, eye, conv):
    """Python mirror of s3d_dof. frame/depth: HxW arrays (gray). Returns blurred frame."""
    h, w = frame.shape
    tc = abs(np.tan(conv))
    if not tc > 1e-6: return frame.copy()
    zf = abs(eye) / tc
    out = frame.copy()
    for y in range(h):
        for x in range(w):
            r = radius(depth[y, x], zf)
            if r < 0.5: continue
            acc, n = frame[y, x], 1.0
            for tx, ty in TAPS:
                sx = min(w - 1, max(0, int(round(x + tx * r)))); sy = min(h - 1, max(0, int(round(y + ty * r))))
                acc += frame[sy, sx]; n += 1.0
            out[y, x] = acc / n
    return out

zf_m, ipd2 = 3.0, 0.0315
conv = np.arctan2(ipd2, zf_m)
check('radius 0 at the focus plane', radius(zf_m, zf_m) == 0.0)
check('radius grows with |1/z - 1/zf| (near vs nearer)', radius(1.5, zf_m) > radius(2.5, zf_m) > 0)
check('radius grows behind the plane too', radius(6.0, zf_m) > radius(4.0, zf_m) > 0)
check('radius clamped at 12', radius(0.3, zf_m) == 12.0)
check('invalid depth (z<=0) gets radius 0', radius(0.0, zf_m) == 0.0)

rng = np.random.default_rng(7)
frame = rng.random((24, 32))
flat = np.full((24, 32), zf_m)
check('SYNTHETIC frame at the focus plane passes through unchanged', np.allclose(dof(frame, flat, ipd2, conv), frame))
depth = np.full((24, 32), zf_m); depth[8, 16] = 0.75              # one very near pixel -> max blur
blurred = dof(frame, depth, ipd2, conv)
nb = [blurred[8+dy, 16+dx] for dx, dy in [(0,0),(12,0),(-12,0),(0,12),(0,-12)]]
orig = [frame[8+dy, 16+dx] for dx, dy in [(0,0),(12,0),(-12,0),(0,12),(0,-12)]]
check('SYNTHETIC near pixel blurs itself and 13-tap neighbours', any(abs(a-b) > 1e-9 for a, b in zip(nb, orig)))
far = np.full((24, 32), zf_m); far[8, 16] = 0.75
check('SYNTHETIC focus-plane pixels far from the near one stay sharp', blurred[0, 0] == frame[0, 0] and blurred[20, 4] == frame[20, 4])
check('conv 0: plain copy (no focus plane defined)', np.array_equal(dof(frame, depth, ipd2, 0.0), frame))
check('deterministic (repeat run identical)', np.array_equal(dof(frame, depth, ipd2, conv), dof(frame, depth, ipd2, conv)))

print('depth defocus: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
