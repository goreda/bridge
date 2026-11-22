#!/usr/bin/env python3
"""DepthGuards.swift (pure Foundation, compiled and run here) vs tools/depth_analysis/depth_guards.py: local_std (scipy uniform_filter), texture_weights, sky_far_clamp (MoGe-keyed and
heuristic), fade_amounts/fade_flatten, static_overlay_mask, fit_scale_shift_weighted (weights=None == the plain LSQ), jitter_rel, MoGe finite mask (cv2 bilinear). Run: SWIFTC=... python3 Tests/DepthGuards/depth_guards_test.py"""
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
import depth_guards as dg
import align as al
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

swiftc = os.environ.get('SWIFTC', 'swiftc'); tmp = Path(tempfile.mkdtemp()); exe = tmp / 'dg'
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'DepthGuards.swift')), str(_sec_file(root,'DepthPrepareMath.swift')), str(root / 'Tests/DepthGuards/main.swift'), '-o', str(exe)], capture_output=True, text=True)
if r.returncode: print(r.stderr); sys.exit(1)
def S(a): return ' '.join(repr(float(x)) for x in np.asarray(a, dtype=np.float32).ravel())
def run(*lines):
    o = subprocess.run([str(exe)], input='\n'.join(lines) + '\n', capture_output=True, text=True, check=True).stdout.splitlines(); return o
def arr(s, shape=None): a = np.array([float(x) for x in s.split()], np.float32); return a.reshape(shape) if shape else a
rng = np.random.default_rng(11); H, W = 90, 160
def textured(h=H, w=W): return (np.kron(rng.random((h // 2, w // 2)), np.ones((2, 2))) * 200 + 20).astype(np.float32)
fails = 0
def check(name, ok):
    global fails; print(('PASS ' if ok else 'FAIL ') + name); fails += 0 if ok else 1
# 1. local std + texture weights (scipy reflect borders)
x = textured(); x += rng.normal(0, 3, x.shape).astype(np.float32)
o = run('std | %d | %d | %s' % (W, H, S(x)), 'tex | %d | %d | %s' % (W, H, S(x)))
check('local_std equals scipy uniform_filter path (max abs diff %.2e)' % np.abs(arr(o[0], (H, W)) - dg._local_std(x)).max(), np.allclose(arr(o[0], (H, W)), dg._local_std(x), atol=2e-3, rtol=1e-4))
check('texture_weights equal reference', np.allclose(arr(o[1], (H, W)), dg.texture_weights(x), atol=1e-4))
# 2. sky far clamp: MoGe-keyed (VDA put sky at scene depth) and heuristic, plus the no-op cases
inv = np.full((H, W), 100.0, np.float32); inv[50:] += rng.normal(0, 5, (40, W)).astype(np.float32)
luma = np.full((H, W), 200.0, np.float32); luma[50:] = textured(40, W)
fin = np.ones((H, W), bool); fin[:45] = False
inv2 = inv.copy(); inv2[:30] = 8.0                                   # heuristic case: far + flat sky
cases = [(inv, luma, fin), (inv, luma, np.ones((H, W), bool)), (inv2, luma, None), (inv, luma, None)]
o = run(*['sky | %d | %d | %s | %s | %s | 0.5' % (W, H, S(i), S(l), '-' if f is None else ' '.join('1' if v else '0' for v in f.ravel())) for i, l, f in cases])
for k, (i, l, f) in enumerate(cases):
    want = dg.sky_far_clamp(i, l, moge_finite=f); got = arr(o[k], (H, W))
    check('sky_far_clamp case %d (%s): equals reference (max abs diff %.2e, %d px clamped)' % (k, 'moge' if f is not None else 'heuristic', np.abs(got - want).max(), int((want != i).sum())), np.allclose(got, want, atol=1e-4, rtol=1e-6))
assert (dg.sky_far_clamp(inv, luma, moge_finite=fin) != inv).sum() > 1000 and (dg.sky_far_clamp(inv, luma) != inv).sum() > 1000
# 3. fade
base = (100 + rng.normal(0, 3, (H, W))).astype(np.float32)
seq = [base.copy() for _ in range(4)] + [base + rng.normal(0, 40, (H, W)).astype(np.float32) for _ in range(4)]
lum = [np.full((H, W), 120.0, np.float32) for _ in range(4)] + [np.full((H, W), m, np.float32) for m in (40.0, 20.0, 8.0, 3.0)]
o = run('fade | %d | %d | %s | %s | 8' % (W, H, S(np.stack(seq)), S(np.stack(lum))))
want = dg.fade_flatten(seq, lum); got = arr(o[0]).reshape(8, H, W)
check('fade_flatten equals reference (max abs diff %.2e); bright frames byte-identical' % np.abs(got - np.stack(want)).max(), np.allclose(got, np.stack(want), atol=2e-4) and all(np.array_equal(got[i], seq[i]) for i in range(4)))
check('fade_amounts equal reference', np.allclose(arr(o[1]), dg.fade_amounts(lum), atol=1e-9))
steady = run('fade | %d | %d | %s | %s | 4' % (W, H, S(np.stack(seq[:4])), S(np.stack(lum[:4]))))
check('fade_flatten: no fade -> returned unchanged', np.array_equal(arr(steady[0]).reshape(4, H, W), np.stack(seq[:4])))
# 4. overlay mask (gray frames, so mean-RGB luma == the value): panning scene + static logo/subtitle; static scene; too few frames
scene = textured(); fr = []
for t in range(30):
    f = np.roll(scene, 3 * t, 1).copy(); f[10:20, 120:150] = 250.0; f[70:76, 30:130] = 235.0; fr.append(f)
rgb = [np.stack([f, f, f], -1).astype(np.uint8) for f in fr]
want = dg.static_overlay_mask(rgb); o = run('overlay | %d | %d | %s | 30 | 2' % (W, H, S(np.stack(fr))))
got = np.array([float(v) for v in o[0].split()], bool).reshape(H, W) if o[0] != 'none' else np.zeros((H, W), bool)
check('static_overlay_mask equals reference (%d px, frac %.3f)' % (want.sum(), want.mean()), want.any() and np.array_equal(got, want))
o = run('overlay | %d | %d | %s | 30 | 2' % (W, H, S(np.stack([fr[0]] * 30))), 'overlay | %d | %d | %s | 30 | 40' % (W, H, S(np.stack(fr))))
check('static scene -> no mask; fewer frames than minFrames -> no mask', o == ['none', 'none'])
# 5. weighted fit
tx = (rng.random((H, W)) * 50).astype(np.float32); ty = (2.0 * tx + 7.0).astype(np.float32); ty[:30] += rng.normal(0, 60, (30, W)).astype(np.float32)
wt = np.ones((H, W), np.float32); wt[:30] = 0.05; fm = np.ones((H, W), bool); fm[40:50] = False; wt[60:70, :80] = 0.0
def fitline(t, rr, m, w): return 'fit | 0 | 0 | %s | %s | %s | %s' % (S(t), S(rr), '-' if m is None else ' '.join('1' if v else '0' for v in m.ravel()), '-' if w is None else S(w))
o = run(fitline(tx, ty, None, None), fitline(tx, ty, None, wt), fitline(tx, ty, fm, wt), fitline(tx, ty, fm, None))
for k, (m, w) in enumerate([(None, None), (None, wt), (fm, wt), (fm, None)]):
    want = dg.fit_scale_shift_weighted(tx, ty, m, w); got = [float(v) for v in o[k].split()[:2]]
    check('fit_scale_shift_weighted case %d (mask=%s weights=%s): scale %.5f shift %.4f vs ref %.5f %.4f' % (k, m is not None, w is not None, got[0], got[1], want[0], want[1]), abs(got[0] - want[0]) < 1e-5 * max(1, abs(want[0])) and abs(got[1] - want[1]) < 1e-4)
want = al.fit_scale_shift(tx, ty, np.ones((H, W), bool)); got = [float(v) for v in o[0].split()[:2]]
check('weights=nil is the plain LSQ of align.fit_scale_shift (%.6f vs %.6f)' % (got[0], want[0]), abs(got[0] - want[0]) < 1e-5 and abs(got[1] - want[1]) < 1e-4)
# 6. jitter_rel (failure_probes.metrics formula) on a noisy and a calm sequence
def jitter_ref(zs, D=1.0):
    invs = [np.where(np.isfinite(z) & (z > 1e-3), D / np.maximum(z, 1e-3), 0.0).astype(np.float32) for z in zs]; valid = [(f > 0) for f in invs]; d = []
    for t in range(1, len(invs)):
        m = valid[t] & valid[t - 1]
        if m.sum() > 16: d.append(float(np.median(np.abs(invs[t][m] - invs[t - 1][m]))))
    med = float(np.median(np.concatenate([f[v] for f, v in zip(invs, valid)])))
    return float(np.median(d)) / med if d and med else None
calm = [(3 + 0.3 * np.sin(np.linspace(0, 6, H * W)).reshape(H, W) + 0.005 * t).astype(np.float32) for t in range(10)]
noisy = [(z * np.exp(rng.normal(0, 0.3, z.shape))).astype(np.float32) for z in calm]; noisy[3][5:9, 5:9] = np.inf
o = run('jitter | %d | %d | %s | 10' % (W, H, S(np.stack(calm))), 'jitter | %d | %d | %s | 10' % (W, H, S(np.stack(noisy))))
for nm, zs, line in (('calm', calm, o[0]), ('noisy', noisy, o[1])):
    want = jitter_ref(zs); got = float(line)
    check('jitter_rel %s: %.5f vs reference %.5f' % (nm, got, want), abs(got - want) < 2e-4 * max(1, want) + 1e-6)
check('jitter_rel orders calm < noisy', float(o[0]) < float(o[1]))
# 7. MoGe finite mask = bilinear resize (cv2 when installed) resize then isfinite
try:
    import cv2
    def resize_lin(m, w, h): return cv2.resize(m, (w, h), interpolation=cv2.INTER_LINEAR)
except ImportError:      # no cv2 here: numpy bilinear with cv2's half-pixel centres and replicated borders (0 * inf = nan, as in cv2)
    def resize_lin(m, w, h):
        mh, mw = m.shape; ys = np.clip((np.arange(h) + 0.5) / h * mh - 0.5, 0, mh - 1); xs = np.clip((np.arange(w) + 0.5) / w * mw - 0.5, 0, mw - 1)
        y0 = ys.astype(int); x0 = xs.astype(int); y1 = np.minimum(y0 + 1, mh - 1); x1 = np.minimum(x0 + 1, mw - 1); ty = (ys - y0)[:, None]; tx = (xs - x0)[None, :]
        with np.errstate(invalid='ignore'):
            return ((m[y0][:, x0] * (1 - tx) + m[y0][:, x1] * tx) * (1 - ty) + (m[y1][:, x0] * (1 - tx) + m[y1][:, x1] * tx) * ty).astype(np.float32)
md = rng.uniform(1, 20, (21, 37)).astype(np.float32); md[:8] = np.inf; md[15, 20] = np.inf
want = np.isfinite(resize_lin(md, 266, 154))
o = run('mask | 37 | 21 | %s | 266 | 154' % ' '.join('inf' if not np.isfinite(v) else repr(float(v)) for v in md.ravel()))
got = np.array([float(v) for v in o[0].split()], bool).reshape(154, 266)
check('finite mask equals cv2 INTER_LINEAR + isfinite (%d px differ)' % int((got != want).sum()), np.array_equal(got, want))
print('depth guards: %d failure(s)' % fails); sys.exit(1 if fails else 0)
