#!/usr/bin/env python3
"""CONTRACT-190v s20 r3 + s28/s28b r4 port: SurroundGeometry (Swift, compiled and run here) against tools/depth_analysis/reference_render.py, plus a Python model of the MSL
colour kernels (s3d_sur_pre / gather / boxh / boxv, s3d_fill edge-run) checked against the reference render. Metal itself is not run (no Mac): the model
shows the kernel DECOMPOSITION is the reference algorithm; GPU float32 deviation is unmeasured."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import math, os, pathlib, shutil, subprocess, sys, tempfile
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root / 'tools/depth_analysis'))
import reference_render as rr
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

sys.path.insert(0, str(root / 'tools')); import vr180_render_ref as _vref
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift6/usr/bin/swiftc'
tmp = pathlib.Path(tempfile.mkdtemp()); exe = tmp / 'geo'
shutil.copy(root / 'Tests/Stereo3DKernel/surround_geo_main.swift', tmp / 'main.swift')       # top-level code needs the file to be named main.swift
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'SurroundGeometry.swift')), str(tmp / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('SurroundGeometry compiles on Linux (Foundation only)', r.returncode == 0)
if r.returncode: print(r.stderr[-1500:]); sys.exit(1)
def geo(w, h, th, conv, ow, oh):
    f = (w / 2.0) / math.tan(th / 2.0); d = tmp / ('g%d_%d_%d_%d' % (w, ow, oh, int(conv * 1e4) + 10000)); d.mkdir(exist_ok=True)
    subprocess.run([str(exe), w, h, repr(f), repr(conv), ow, oh, d], check=True, capture_output=True) if False else subprocess.run([str(exe)] + [str(x) for x in (w, h, repr(f), repr(conv), ow, oh, d)], check=True, capture_output=True)
    return (np.fromfile(d / 'inside.u8', np.uint8).reshape(oh, ow).astype(bool), np.fromfile(d / 'src.i32', np.int32).reshape(oh, ow), np.fromfile(d / 'wb4.f32', np.float32).reshape(oh, ow, 4), np.fromfile(d / 'near.i32', np.int32).reshape(oh, ow), [int(x) for x in (d / 'box.txt').read_text().split()])
def ref_extension(inside):
    """The reference's extension loop run on an index map (values copied, never mixed)."""
    oh, ow = inside.shape; filled = inside.copy(); work = np.where(inside, np.arange(oh * ow).reshape(oh, ow), -1).astype(np.int64)
    while True:
        todo = ~filled
        if not todo.any(): break
        progressed = False
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0: continue
                nb = np.zeros((oh, ow), bool)
                ys = slice(max(0, dy), oh + min(0, dy)); xs = slice(max(0, dx), ow + min(0, dx)); yd = slice(max(0, -dy), oh + min(0, -dy)); xd = slice(max(0, -dx), ow + min(0, -dx))
                nb[yd, xd] = filled[ys, xs]; take = todo & nb & ~filled
                if not take.any(): continue
                vals = np.roll(np.roll(work, -dy, 0), -dx, 1); work[take] = vals[take]; filled |= take; progressed = True
        if not progressed: break
    return work
def ref_bfs(inside, steps=121):
    """reference_render._surround_soft_vec r4 nearest-footprint BFS, copied verbatim: (flat index, L1 dist)."""
    out_h, out_w = inside.shape
    dist = np.full((out_h, out_w), 1e9); iy = np.zeros((out_h, out_w), np.int64); ix = np.zeros((out_h, out_w), np.int64)
    dist[inside] = 0.0; yy = np.arange(out_h)[:, None].repeat(out_w, 1); xx = np.arange(out_w)[None, :].repeat(out_h, 0); iy[inside] = yy[inside]; ix[inside] = xx[inside]
    for _ in range(steps):
        changed = False
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ys = slice(max(0, dy), out_h + min(0, dy)); xs = slice(max(0, dx), out_w + min(0, dx)); yd = slice(max(0, -dy), out_h + min(0, -dy)); xd = slice(max(0, -dx), out_w + min(0, -dx))
            rd = dist[ys, xs] + 1.0; dst = dist[yd, xd]; take = rd < dst
            if not take.any(): continue
            dst[take] = rd[take]; iy[yd, xd][take] = iy[ys, xs][take]; ix[yd, xd][take] = ix[ys, xs][take]; changed = True
        if not changed: break
    return iy * out_w + ix, dist
def ref_wb(inside, D2=40.0, D3=120.0):
    oh, ow = inside.shape; _, dist = ref_bfs(inside); cyy, cxx = np.where(inside); cy, cx = float(cyy.mean()), float(cxx.mean())
    vert = np.abs(np.arange(oh)[:, None] - cy) >= np.abs(np.arange(ow)[None, :] - cx)
    return np.stack([np.clip((dist - 1.0) / (D2 - 1.0), 0, 1), np.clip((dist - D2) / (D3 - D2), 0, 1), np.clip(1.0 - dist / 24.0, 0, 1), vert.astype(np.float64)], -1)
def sliding(a, R, axis, dt):
    """The kernel's clamped running-sum box along `axis` (one thread per line; same add-enter / subtract-leave order), vectorised over the other axis."""
    a = np.moveaxis(a, axis, 0); n = a.shape[0]; out = np.empty_like(a)
    s = sum((a[min(max(i, 0), n - 1)] for i in range(-R, R + 1)), np.zeros_like(a[0]))
    for x in range(n):
        out[x] = s / dt(2 * R + 1); s = s + a[min(max(x + 1 + R, 0), n - 1)] - a[min(max(x - R, 0), n - 1)]
    return np.moveaxis(out, 0, axis)
def model_surround(img_u8, inside, src, wb, near, dt=np.float64, box=None):
    """Python model of the four r4 MSL kernels (dt = float64 or float32)."""
    oh, ow = inside.shape; work = img_u8.astype(dt) / dt(255) if dt is np.float32 else img_u8.astype(dt)
    scale = dt(255) if dt is np.float32 else dt(1)
    truth = work; cur = work
    if box is not None: bx0, by0, bw_, bh_ = box; bm = np.zeros(inside.shape, bool); bm[by0:by0 + bh_, bx0:bx0 + bw_] = True     # s31 (d): pre-blur dispatched over the footprint box only; pixels outside keep stale values
    for it in range(32):                                        # s3d_sur_pre
        acc = np.where(inside[..., None], cur, dt(0)); cnt = inside.astype(dt)
        for j in (-1, 0, 1):
            for i in (-1, 0, 1):
                if i == 0 and j == 0: continue
                nbin = np.roll(np.roll(inside, -j, 0), -i, 1); acc = acc + np.where((inside & (nbin | (it == 0)))[..., None], np.roll(np.roll(cur, -j, 0), -i, 1), dt(0)); cnt = cnt + np.roll(np.roll(inside.astype(dt), -j, 0), -i, 1)
        cur = np.where(inside[..., None], acc / np.maximum(cnt, dt(1))[..., None], dt(0))
        if box is not None: cur = np.where(bm[..., None], cur, np.full_like(cur, dt(7)))      # garbage outside the box: must never be read
    flat = cur.reshape(-1, 3); tflat = truth.reshape(-1, 3)                                                 # s3d_sur_gather (r4)
    wk = np.where((src >= 0)[..., None], flat[np.maximum(src, 0)], dt(0))
    nr = np.maximum(near.reshape(-1), 0); delta = (tflat[nr] - flat[nr]).reshape(oh, ow, 3)
    wk = wk + np.where((near >= 0)[..., None], delta * wb[..., 2:3].astype(dt), dt(0))
    wk = np.where(inside[..., None], truth, wk)
    rows = [sliding(wk, R, 1, dt) for R in (16, 96, 256, 64)]                                              # s3d_sur_boxh
    b1 = sliding(rows[0], 16, 0, dt); b2 = sliding(rows[1], 96, 0, dt); bw = sliding(rows[2], 64, 0, dt); bt = sliding(rows[3], 256, 0, dt)   # s3d_sur_boxv
    b3 = np.where(wb[..., 3:4] != 0, bw, bt)
    t1 = wb[..., 0:1].astype(dt); t2 = wb[..., 1:2].astype(dt); v = b1 + (b2 - b1) * t1; v = v + (b3 - v) * t2
    out = img_u8.copy(); out[~inside] = np.floor(v * scale)[~inside].astype(np.uint8); return out
rng = np.random.default_rng(20)
cases = [(48, 32, math.radians(63), 0.0, 96, 64), (48, 32, math.radians(63), 0.05, 96, 64), (64, 64, math.radians(90), -0.04, 80, 80), (40, 24, math.radians(40), 0.0, 64, 48)]
for (w, h, th, conv, ow, oh) in cases:
    tag = '%dx%d fov %d conv %+.2f -> %dx%d' % (w, h, round(math.degrees(th)), conv, ow, oh)
    inside, src, wb, near, box = geo(w, h, th, conv, ow, oh)
    refmask = rr.footprint_mask(np.zeros((h, w, 3)), th, conv, ow, oh)
    check('%s: footprint mask equals reference footprint_mask (%d inside px)' % (tag, refmask.sum()), (inside == refmask).all() and refmask.any())
    ext = ref_extension(refmask)
    check('%s: extension source map equals the reference loop on an index map (every outside px copies the same footprint px)' % tag, (src.reshape(-1).astype(np.int64) == ext.reshape(-1)).all())
    rn, _ = ref_bfs(refmask)
    check('%s: nearest-footprint BFS index equals the reference slice-shift BFS (r4 s28b)' % tag, (near.astype(np.int64) == rn).all())
    check('%s: weights (t1, t2, wcorr, vert) equal the reference (BFS dist, 24 px fade, centroid side)' % tag, np.abs(wb - ref_wb(refmask)).max() < 1e-6)
    img = np.zeros((oh, ow, 3), np.uint8); img[refmask] = rng.integers(0, 256, (int(refmask.sum()), 3), dtype=np.uint8)
    want = rr._surround_soft_vec(np.zeros((h, w, 3)), th, conv, ow, oh, img.copy())
    for dt, name, tol in ((np.float64, 'float64', 1), (np.float32, 'float32', 2)):
        got = model_surround(img, refmask, src, wb, near, dt, box); d = np.abs(got.astype(int) - want.astype(int))
        check('%s: kernel-decomposition model (%s) vs reference _surround_soft_vec: max dev %d LSB, %.4f%% px exact, footprint untouched' % (tag, name, d.max(), 100 * (d == 0).mean()), d.max() <= tol and (got[refmask] == img[refmask]).all())
# E-G loop reference (tools/vr180_render_ref.surround_soft) and the vectorised reference must agree byte for byte (s28b shared algorithm)
_w, _h, _th = 48, 32, math.radians(63); _ins = rr.footprint_mask(np.zeros((_h, _w, 3)), _th, 0.02, 96, 64); _img = np.zeros((64, 96, 3), np.uint8); _img[_ins] = rng.integers(0, 256, (int(_ins.sum()), 3), dtype=np.uint8)
check('vr180_render_ref.surround_soft (E-G) == reference_render._surround_soft_vec (r4), max dev %d LSB' % np.abs(_vref.surround_soft(np.zeros((_h, _w, 3), np.uint8), _th, 0.02, 96, 64, _img.copy()).astype(int) - rr._surround_soft_vec(np.zeros((_h, _w, 3)), _th, 0.02, 96, 64, _img.copy()).astype(int)).max(),
      np.abs(_vref.surround_soft(np.zeros((_h, _w, 3), np.uint8), _th, 0.02, 96, 64, _img.copy()).astype(int) - rr._surround_soft_vec(np.zeros((_h, _w, 3)), _th, 0.02, 96, 64, _img.copy()).astype(int)).max() <= 1)
# edge-run fill model (s3d_fill r2) vs the reference loop, on random coverage with the Swift footprint
def model_edge(img, cov, fp):
    out = img.copy(); oh, ow = cov.shape
    for r in range(oh):
        cols = np.flatnonzero(cov[r])
        if not len(cols): continue
        first, a = cols[0], cols[-1]; fpx = np.flatnonzero(fp[r])
        if not len(fpx): continue
        lo, hi = fpx[0], fpx[-1]
        if first > lo:
            g = first - lo
            out[r, lo:first] = _vref._vavg(img, cov, r, first) if g > _vref.SHORT_RUN_K else img[r, first]
        if a < hi:
            g = hi - a
            out[r, a + 1:hi + 1] = _vref._vavg(img, cov, r, a) if g > _vref.SHORT_RUN_K else img[r, a]
    return out
inside, src, wb, near, box = geo(48, 32, math.radians(63), 0.0, 96, 64)
cov = np.zeros((64, 96), bool); cov[:, 44:52] = rng.random((64, 8)) < 0.5; img = rng.integers(0, 256, (64, 96, 3), dtype=np.uint8) * cov[..., None]
check('edge-run fill model equals reference_render edge loop on random coverage (fp from SurroundGeometry)', (model_edge(img, cov, inside) == _vref.fill_edge_runs(img, cov, inside)).all() and (model_edge(img, cov, inside) != img).any())
# the pin: reference render, surround off then my surround model == surround soft, whole frame, both eyes
H, W = 36, 64; z = 1.0 + (np.add.outer(np.arange(H), np.arange(W)) % 17) * 0.25; z[4:8, 4:12] = 0.0; z[20:, 40:] = 0.4
rgb = rng.integers(0, 256, (H, W, 3), dtype=np.uint8); th = math.radians(75)
for conv_m in (None, 2.0):
    off = rr.render_frame_sbs(rgb, z, th, convergence_m=conv_m, out_w=72, out_h=72, surround='off'); on = rr.render_frame_sbs(rgb, z, th, convergence_m=conv_m, out_w=72, out_h=72, surround='soft')
    dev = 0
    for e, sign in enumerate((-1.0, 1.0)):
        conv = math.atan2(sign * 0.063 / 2, conv_m) if conv_m else 0.0; ins, s_, wb_, nr_, _bx = geo(W, H, th, conv, 72, 72)
        got = model_surround(off[:, e * 72:(e + 1) * 72], ins, s_, wb_, nr_, np.float64); dev = max(dev, int(np.abs(got.astype(int) - on[:, e * 72:(e + 1) * 72].astype(int)).max()))
    check('full reference render (convergence %s): edge-fill output + surround kernel model equals surround=soft, max dev %d LSB (inside footprint exact)' % (conv_m, dev), dev <= 1)
swift = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(root)).read_text())
check('MSL pins: r3 kernels, 32 pre-blur passes, R=16/96/256 running-sum boxes, lerp blend, floor truncation, edge-run fill, fp buffer', all(x in swift for x in (
    'kernel void s3d_sur_pre', 'kernel void s3d_sur_gather', 'kernel void s3d_sur_boxh', 'kernel void s3d_sur_boxv', 'const int R[4] = {16, 96, 256, 64};', 'const int R[4] = {16, 96, 64, 256};', 'w.w != 0.0f ? s[2] / D[2] : s[3] / D[3]', 'v = v + (b3 - v) * w.y;', 'constant uint4& box [[buffer(6)]]', 'constant uint& pass0 [[buffer(7)]]', 'if (pass0 != 0) acc +=', 'enc.setBytes(&bx, length: MemoryLayout<SIMD4<UInt32>>.size, index: 6)', 'wb[i].z', 'device const int* near [[buffer(5)]]',
    'floor(v * 255.0f) / 255.0f', 'for k in 0..<32', 'r2 edge-run fill', 'device const uchar* fp [[buffer(2)]]', 'if (first > lo)', 'if (a < hi)')) and 's3d_surround(' not in swift)
shutil.rmtree(tmp, ignore_errors=True)
print('surround r4: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
