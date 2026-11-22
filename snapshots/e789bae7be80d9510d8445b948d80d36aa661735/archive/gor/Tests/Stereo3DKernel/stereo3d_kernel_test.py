#!/usr/bin/env python3
"""190t E/F/G: Python mirror of every Metal kernel in Sources/gor/gor/ThreeD.swift (Stereo3DKernel.swift section) (clear, zmin, resolve, fill, sbs), float32 like the GPU
(fast-math off), checked against tools/vr180_render_ref.py (float64 geometry, same fill rule) and pinned to the Swift/MSL text.
Swift/Metal compile happens on the owner's build; the renderer returns nil (2D path) if the runtime Metal compile fails."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import math, pathlib, re, sys
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools'))
import vr180_render_ref as ref
swift = (lambda _b: _b[_b.index('// BEGIN relocated '+'Stereo3DKernel.swift'+' '):_b.index('// END relocated '+'Stereo3DKernel.swift'+'\n')])((_threed_split().path(root)).read_text())
msl = swift[swift.index('static let text = """'):]; msl = msl[:msl.index('\n    """\n')]
fails = []
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
f32 = np.float32; INF = np.float32(np.inf)
# --- text pins: the model below is only valid while the kernel text says exactly this
for pin in ('float rx = ((float)g.x + 0.5f - (float)p.w * 0.5f) / p.f;', 'float ry = ((float)p.h * 0.5f - ((float)g.y + 0.5f)) / p.f;',
            'float px = rx * z - p.eye, py = ry * z, pz = z;', 'float lon = atan2(px, pz) + p.conv, lat = asin(py / n);',
            'float u = lon / M_PI_F + 0.5f, v = 0.5f - lat / M_PI_F;', 'o = int2((int)floor(u * (float)p.ow), (int)floor(v * (float)p.oh));',
            'return z > 0.0f && o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;', 'constant uint S3D_INF = 0x7F800000u;',
            'atomic_fetch_min_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], as_type<uint>(z)', '!= as_type<uint>(z)) return;',
            'uint src = (as_type<float>(za) >= as_type<float>(zc)) ? (uint)a : c;', 'sbs.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);',
            'options.fastMathEnabled = false', 'return nil'):
    check('pinned: ' + pin[:60], pin in swift)
for pin in ('constant uint SHORT_RUN_K = 16u, VERT_HALF = 16u;', '(2u * num + den) / (2u * den)', 'sum += s3d_codes(rendered.read(uint2(col, r)))', 'A * (g + 1u - k) + B * k', 's3d_vavg(zb, p, rendered, row, src)', '(uint)(first - lo) > SHORT_RUN_K', '(uint)(hi - a) > SHORT_RUN_K'):
    check('F1 integer-exact MSL pin: ' + pin, pin in swift)
check('kernels present: clear zmin resolve fill sbs', all(('kernel void s3d_' + k) in msl for k in ('clear', 'zmin', 'resolve', 'fill', 'sbs')))
fill_src = swift[swift.index('kernel void s3d_fill'):swift.index('kernel void s3d_depth10')]
check('s3d_fill is total: it writes zeros to the whole row before any early return (owner log 14:37 / A-D F2a: rows of a fresh result texture were left undefined); model starts from zeros', fill_src.index('result.write(float4(0.0f)') < fill_src.index('if (a < 0) return;') and 'np.zeros_like(rendered)' in open(__file__).read())
check('flat playback never references the renderer', all('Stereo3D' not in (_pp_split().path(root, n) if n == 'PPController.swift' else root/'Sources/gor'/n).read_text() for n in ('PPController.swift', 'AppDelegate.swift', 'MenuActions.swift')))
check('all Metal use is behind canImport(Metal)', swift.count('#if canImport(Metal)') == 1 and swift.rstrip().endswith('#endif'))
# --- model of the kernels
def smap(gx, gy, P, z):
    rx = (f32(gx) + f32(.5) - f32(P['w']) * f32(.5)) / P['f']; ry = (f32(P['h']) * f32(.5) - (f32(gy) + f32(.5))) / P['f']
    px = rx * z - P['eye']; py = ry * z; pz = z
    n = np.sqrt(px * px + py * py + pz * pz)
    lon, lat = np.arctan2(px, pz) + f32(P.get('conv', 0.0)), np.arcsin(py / n)
    u = lon / f32(math.pi) + f32(.5); v = f32(.5) - lat / f32(math.pi)
    ox, oy = int(np.floor(u * f32(P['ow']))), int(np.floor(v * f32(P['oh'])))
    return (ox, oy) if z > 0 and 0 <= ox < P['ow'] and 0 <= oy < P['oh'] else None
def model_eye(frame, depth, theta, eye, ow, oh):
    h, w = depth.shape; P = dict(f=f32((w / 2.0) / math.tan(theta / 2.0)), eye=f32(eye), w=w, h=h, ow=ow, oh=oh)
    zb = np.full((oh, ow), INF, f32); rendered = np.zeros((oh, ow, 3), np.uint8)               # s3d_clear
    mp = {}
    for y in range(h):
        for x in range(w):
            o = smap(x, y, P, f32(depth[y, x]))
            if o: mp[(y, x)] = o; zb[o[1], o[0]] = min(zb[o[1], o[0]], f32(depth[y, x]))        # s3d_zmin (atomic min)
    for (y, x), o in mp.items():
        if zb[o[1], o[0]] == f32(depth[y, x]): rendered[o[1], o[0]] = frame[y, x]               # s3d_resolve
    result = np.zeros_like(rendered)
    for row in range(oh):                                                                        # s3d_fill F1 (s27): blend runs <= SHORT_RUN_K, far-column vertical average above, integer-exact round-half-up
        a = -1
        for c in range(ow):
            if zb[row, c] == INF: continue
            if a >= 0 and c - a > 1:
                g = c - a - 1
                if g <= ref.SHORT_RUN_K:
                    A = rendered[row, a].astype(np.uint64); B = rendered[row, c].astype(np.uint64)
                    for k in range(1, g + 1):
                        num = A * (g + 1 - k) + B * k
                        result[row, a + k] = ((2 * num + (g + 1)) // (2 * (g + 1))).astype(np.uint8)
                else:
                    src = a if zb[row, a] >= zb[row, c] else c
                    lo, hi = max(0, row - ref.VERT_HALF), min(oh - 1, row + ref.VERT_HALF)
                    col = [rendered[rr, src] for rr in range(lo, hi + 1) if zb[rr, src] != INF]
                    if col:
                        s = np.asarray(col, np.uint64).sum(axis=0); n = len(col)
                        result[row, a + 1:c] = ((2 * s + n) // (2 * n)).astype(np.uint8)
                    else:
                        result[row, a + 1:c] = rendered[row, src]
            result[row, c] = rendered[row, c]; a = c
    return rendered, zb, result
def model_sbs(L, R):
    oh, ow = L.shape[:2]; out = np.zeros((oh, ow * 2, 3), np.uint8)
    for y in range(oh):
        for x in range(ow * 2): out[y, x] = L[y, x] if x < ow else R[y, x - ow]
    return out
rng = np.random.default_rng(3); W, H, OW, OH, TH = 24, 12, 48, 24, math.radians(63)
frame = rng.integers(1, 255, (H, W, 3), dtype=np.uint8); depth = rng.uniform(1.5, 12.0, (H, W)); depth[4:8, 8:14] = 0.9
res = {}
for eye in (-0.0315, 0.0315):
    rendered, zb, result = model_eye(frame, depth, TH, eye, OW, OH)
    ri, rc, rz = ref.render_eye(frame, depth, TH, eye, OW, OH)
    cov_m = zb != INF
    agree = (cov_m == rc).mean(); same = (rendered[cov_m & rc] == ri[cov_m & rc]).all(axis=1).mean()
    check('eye %+.4f: float32 kernel coverage matches float64 reference (%.3f)' % (eye, agree), agree >= 0.97)
    check('eye %+.4f: matching cells hold the same colour (%.3f)' % (eye, same), same >= 0.97)
    fi, fc = ref.fill_rows(rendered, cov_m, np.where(cov_m, zb, np.inf).astype(np.float64), eye)
    check('eye %+.4f: s3d_fill equals the reference fill on identical input' % eye, (fi == result).all() or (fi[fc] == result[fc]).all())
    check('eye %+.4f: fill never changes a covered cell' % eye, (result[cov_m] == rendered[cov_m]).all())
    res[eye] = result
sb = model_sbs(res[-0.0315], res[0.0315])
check('sbs: left image in the left half, right image in the right half', (sb[:, :OW] == res[-0.0315]).all() and (sb[:, OW:] == res[0.0315]).all() and sb.shape == (OH, 2 * OW, 3))
check('near block shifts opposite ways in the two eyes', not (res[-0.0315] == res[0.0315]).all())

# --- F1 fill metrics on a staged depth step (s27): a near block (z=1) over a VOID
# left half (no far content remaps into its disocclusion band -> long runs) and a mid
# strip (z=3) over a far plane (z=8, right half) -> short runs; exaggerated eye offset
# (0.9 m) and 2x upscale so both fill tiers appear at 192 px.
rng2 = np.random.default_rng(11); H2, W2, OW2, OH2 = 48, 96, 192, 96
frame2 = rng2.integers(0, 256, (H2, W2, 3), dtype=np.uint8)
depth2 = np.zeros((H2, W2)); depth2[:, 44:] = 8.0
depth2[4:22, 30:44] = 1.0; depth2[26:44, 60:63] = 3.0
rd2, zb2, res2 = model_eye(frame2, depth2, math.radians(90), 0.9, OW2, OH2)
cov2 = zb2 != INF
fi2, fc2 = ref.fill_rows(rd2, cov2, np.where(cov2, zb2, np.inf).astype(np.float64), 0.9)
check('staged step: model fill equals the F1 reference on identical input', (fi2 == res2).all() or (fi2[fc2] == res2[fc2]).all())
check('staged step: fill never changes a covered cell', (res2[cov2] == rd2[cov2]).all() and (fi2[cov2] == rd2[cov2]).all())
lens = ref.fill_run_lengths(cov2, fc2)
check('staged step: fill runs present in both tiers (long >K and short <=K)', lens.size > 0 and lens.max() > ref.SHORT_RUN_K and (lens <= ref.SHORT_RUN_K).any())
old2 = rd2.copy()                                   # the s5 constant-far fill, inline, as the before/after baseline
for r in range(OH2):
    cols = np.flatnonzero(cov2[r])
    for a, b in zip(cols[:-1], cols[1:]):
        if b - a > 1: old2[r, a + 1:b] = rd2[r, a if zb2[r, a] >= zb2[r, b] else b]
mask2 = fc2 & ~cov2
fo, fn = ref.flat_fraction(old2, mask2), ref.flat_fraction(fi2, mask2)
vo, vn = ref.vstep_mean(old2, mask2), ref.vstep_mean(fi2, mask2)
p95 = float(np.percentile(lens, 95)) if lens.size else 0.0
print('F1 staged-step metrics: fill-run p95 %.1f px, max %d px | flat-frac %.3f -> %.3f | vstep %.2f -> %.2f (old -> F1)' % (p95, lens.max() if lens.size else 0, fo, fn, vo, vn))
check('F1: flat-fraction within fills drops below the constant-fill rule', fn < fo)
check('F1: fill band is vertically smoother than the constant-fill rule (at least halved)', vn < 0.5 * vo)
# Exact Metal uint32 arithmetic vs Python uint64 on ties, extreme codes and
# all short-run lengths. UNORM conversion recovers every original byte.
check('F1: float32 UNORM read recovers all 256 byte codes exactly', np.array_equal(np.floor(np.arange(256,dtype=f32)/f32(255)*f32(255)+f32(.5)).astype(np.uint32),np.arange(256,dtype=np.uint32)))
rg = np.random.default_rng(917)
for g in range(1,17):
    A=rg.integers(0,256,(71,4),dtype=np.uint32); B=rg.integers(0,256,(71,4),dtype=np.uint32)
    for k in range(1,g+1):
        num=A*(g+1-k)+B*k
        got=(2*num+g+1)//(2*(g+1))
        assert np.array_equal(got,ref._round_half_up(A.astype(np.uint64)*(g+1-k)+B.astype(np.uint64)*k,g+1))
check('F1: all run lengths 1..16 uint32 blend bit-exact to uint64 reference',True)
for n in range(1,34):
    col=rg.integers(0,256,(n,4),dtype=np.uint32); sm=col.sum(axis=0,dtype=np.uint32)
    assert np.array_equal((2*sm+n)//(2*n),ref._round_half_up(col.sum(axis=0,dtype=np.uint64),n))
check('F1: every covered-column count 1..33 uint32 average bit-exact to uint64 reference',True)
# convergence_m: screen distance C has zero parallax (left and right land on the same column), default conv=0 is unchanged
C = 2.0; Pc = dict(f=f32(1000.0), w=64, h=64, ow=256, oh=256)
cols = []
for sg in (-1, 1):
    e = 0.063 / 2 * sg; q = dict(Pc, eye=f32(e), conv=float(math.atan2(e, C))); cols.append(smap(40, 30, q, f32(C)))
check('convergence_m: depth == C lands on the same column for both eyes', cols[0] and cols[1] and abs(cols[0][0] - cols[1][0]) <= 1)
off = [smap(40, 30, dict(Pc, eye=f32(0.063 / 2 * sg)), f32(C)) for sg in (-1, 1)]
check('without convergence the same point has parallax', off[0] and off[1] and abs(off[0][0] - off[1][0]) >= 2)
check('convergence param pinned in Swift', 'atan2(sign * ipd / 2.0, $0)' in swift and 'convergence: Double? = nil' in swift)
check('swapEyes explicit: halves exchange eye offsets, default order unchanged', 'swapEyes ? [1.0, -1.0] : [-1.0, 1.0]' in swift and 'swapEyes: Bool = false' in swift)

# --- soft surround: pins + behaviour of the reference (MSL s3d_surround mirrors it line for line)
import importlib.util
_sp = importlib.util.spec_from_file_location('vr180_render_ref', str(root / 'tools/vr180_render_ref.py')); _ref = importlib.util.module_from_spec(_sp); _sp.loader.exec_module(_ref)
check('surround params pinned (r2 kernels are pinned in surround_r2_test.py)', all(x in swift for x in ('kernel void s3d_sur_pre', 'surround: Bool = false', 'device const uchar* fp [[buffer(2)]]')))
# s20 r2: the surround extends the RENDERED canvas content (footprint
# already filled by the forward warp), not raw source taps. Emulate the
# render by sampling the source at each footprint pixel's projection.
fr = (np.arange(48 * 64 * 3).reshape(48, 64, 3) % 251).astype(np.float64); canvas = np.zeros((32, 32, 3)); inside = np.zeros((32, 32), bool)
f_ = (64 / 2.0) / math.tan(math.radians(60) / 2)
for oy in range(32):
    for ox in range(32):
        lon = ((ox + .5) / 32 - .5) * math.pi; lat = (.5 - (oy + .5) / 32) * math.pi
        dz = math.cos(lon) * math.cos(lat); sx = f_ * math.sin(lon) * math.cos(lat) / max(dz, 1e-4) + 32; sy = 24 - f_ * math.sin(lat) / max(dz, 1e-4)
        inside[oy, ox] = dz > 0 and 0 <= sx < 64 and 0 <= sy < 48
        if inside[oy, ox]: canvas[oy, ox] = fr[min(int(sy), 47), min(int(sx), 63)]
out = _ref.surround_soft(fr, math.radians(60), 0.0, 32, 32, canvas.copy())
check('surround leaves every pixel inside the film footprint untouched', (out[inside] == canvas[inside]).all() and inside.any())
check('surround fills every pixel outside the footprint with picture colour', (out[~inside] != 0).any(axis=1).mean() > 0.95 and (~inside).any())
check('surround values stay inside the source value range (blur of source only)', out.max() <= fr.max() and out.min() >= 0)
flat_canvas = np.zeros((32, 32, 3)); flat_canvas[inside] = 100.0
same = _ref.surround_soft(np.full((48, 64, 3), 100.0), math.radians(60), 0.0, 32, 32, flat_canvas)
check('flat source: surround is exactly that colour', (same[~inside] == 100.0).all())
print('stereo3d kernel: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
