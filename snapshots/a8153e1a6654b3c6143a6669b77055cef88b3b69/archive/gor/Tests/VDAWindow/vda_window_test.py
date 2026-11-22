#!/usr/bin/env python3
"""190w W4: Sources/gor/gor/ThreeD.swift (VDAWindowPlan.swift section) (pure Foundation) compiled and run on Linux against numpy: window coverage/padding, least-squares fit, stitch of
windows that each carry their own affine of one ground-truth depth. CoreML windowed model NOT exercised (package does not exist yet); the constants (32/10/8) are unverified vs upstream."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, shutil, subprocess, sys, tempfile
import numpy as np
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root = pathlib.Path(__file__).resolve().parents[2]
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swiftc or not os.path.exists(swiftc):
    print('SKIPPED: no swiftc'); sys.exit(0)
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / 'main.swift').write_text('''import Foundation
let a = CommandLine.arguments
if a[1] == "win" { let n = Int(a[2])!; print(VDAWindowPlan.windowCount(frameCount: n)); for f in VDAWindowPlan.inputFrames(frameCount: n) { print(f.map { String($0) }.joined(separator: ",")) } }
if a[1] == "fit" { let r = a[2].split(separator: ",").map { Float($0)! }, c = a[3].split(separator: ",").map { Float($0)! }; let f = VDAWindowPlan.fit(ref: r, cur: c); print(f.scale, f.shift) }
if a[1] == "stitch" { let n = Int(a[2])!, px = Int(a[3])!
  let raw = try! String(contentsOfFile: a[4]).split(separator: ",").map { Float($0)! }; let per = VDAWindowPlan.inferLen * px
  let outs = (0..<VDAWindowPlan.windowCount(frameCount: n)).map { Array(raw[($0 * per)..<(($0 + 1) * per)]) }
  print(VDAWindowPlan.stitch(outputs: outs, frameCount: n, px: px).map { String($0) }.joined(separator: ",")) }
''')
exe = tmp / 'w'
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'VDAWindowPlan.swift')), str(tmp / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('compiles (Linux, Foundation only)', r.returncode == 0)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
run = lambda *a: subprocess.run([str(exe), *map(str, a)], capture_output=True, text=True, check=True).stdout.strip().split('\n')
KF = [0, 12, 24, 25, 26, 27, 28, 29, 30, 31]
# --- numpy mirror of upstream infer_video_depth (as remembered): input frames + post-process
def np_inputs(n):
    out, prev = [], None
    for k in range((n + 21) // 22):
        f = [min(22 * k + i, n - 1) for i in range(32)]
        if prev is not None: f[:10] = [prev[j] for j in KF]
        out.append(f); prev = f
    return out
def np_stitch(outs, n):
    kf = KF[:2]; al = []; ref = []
    for k, o in enumerate(outs):
        if k == 0:
            al = [o[i].copy() for i in range(32)]; ref = [o[i].copy() for i in kf]; continue
        cur = np.concatenate([o[i] for i in range(2)]); rf = np.concatenate(ref)
        A = np.stack([cur, np.ones_like(cur)], 1); sc, sh = np.linalg.lstsq(A, rf, rcond=None)[0]
        post = [np.maximum(0, o[i] * sc + sh) for i in range(2, 10)]
        w = np.linspace(0, 1, 8)
        for i in range(8): al[-8 + i] = al[-8 + i] * (1 - w[i]) + post[i] * w[i]
        for j in range(10, 32): al.append(np.maximum(0, o[j] * sc + sh))
        ref = [ref[0]] + [np.maximum(0, o[x] * sc + sh) for x in kf[1:]]
    return np.stack(al[:n])
r0 = run('win', 100)
check('100 frames: 5 windows (range(0, n, 22)); window 0 = frames 0..31, padded tail = frame 99', r0[0] == '5' and r0[1].split(',') == [str(i) for i in range(32)] and r0[5].split(',')[-1] == '99')
w1 = r0[2].split(','); 
check('window 1 positions 0..9 = window 0 input at KEYFRAMES (0,12,24..31); position 10.. = video frames 32..', w1[:10] == [str(x) for x in KF] and w1[10] == '32' and w1[31] == '53')
check('python mirror of the input frames == Swift for n in 1,10,22,23,32,33,100', all([l.split(',') for l in run('win', n)[1:]] == [[str(x) for x in f] for f in np_inputs(n)] for n in (1, 10, 22, 23, 32, 33, 100)))
check('window counts: 22 -> 1, 23 -> 2, 32 -> 2, 33 -> 2, 45 -> 3, 0 -> none', [run('win', n)[0] for n in (22, 23, 32, 33, 45)] == ['1', '2', '2', '2', '3'] and run('win', 0)[0] == '0')
f = list(map(float, run('fit', '1,2,3,4', '10,20,30,40')[0].split()))
check('fit recovers scale/shift (cur*0.1 + 0)', abs(f[0] - 0.1) < 1e-5 and abs(f[1]) < 1e-4)
f = list(map(float, run('fit', '5,7,9', '1,2,3')[0].split()))
check('fit recovers affine 2x+3', abs(f[0] - 2) < 1e-5 and abs(f[1] - 3) < 1e-4)
f = list(map(float, run('fit', '1,2,3', '4,4,4')[0].split()))
check('flat cur: scale 1, shift = mean difference', abs(f[0] - 1) < 1e-6 and abs(f[1] + 2) < 1e-5)
# --- stitch vs the numpy mirror on random window outputs, and vs a fake model with per-window affines
rng = np.random.default_rng(1)
for n, px in ((100, 6), (23, 4), (60, 5)):
    nw = (n + 21) // 22
    outs = [rng.uniform(0.2, 3, (32, px)).astype(np.float32) for _ in range(nw)]
    rawf = tmp / 'raw.txt'; rawf.write_text(','.join(repr(float(v)) for o in outs for v in o.ravel()))
    sw = np.array(run('stitch', n, px, rawf)[0].split(','), dtype=np.float32).reshape(n, px)
    ref = np_stitch([o.astype(np.float64) for o in outs], n)
    check('stitch n=%d == numpy mirror (max diff %.1e)' % (n, np.abs(sw - ref).max()), sw.shape == ref.shape and np.abs(sw - ref).max() < 1e-3)
n, px = 100, 6
gt = (np.linspace(1, 3, px)[None, :] + np.linspace(0, 1, n)[:, None]).astype(np.float32)
fr = np_inputs(n); outs = []
for k, f in enumerate(fr):
    a, b = rng.uniform(0.5, 2), rng.uniform(0, 1)
    outs.append(((gt[f] - b) / a).astype(np.float32))      # model: affine of the depth of the frame it was fed
rawf = tmp / 'raw.txt'; rawf.write_text(','.join(repr(float(v)) for o in outs for v in o.ravel()))
res = np.array(run('stitch', n, px, rawf)[0].split(','), dtype=np.float32).reshape(n, px)
A = np.polyfit(res.ravel(), gt.ravel(), 1); err = np.abs(res * A[0] + A[1] - gt).max()
check('stitch: fake model = per-window affine of the fed frames -> one consistent depth (max err %.1e after one global affine)' % err, err < 2e-3)
check("stitch input shape sanity: 100 frames x 6 px = 5 windows accepted", len(run("stitch", 100, 6, rawf)[0].split(",")) == 600)
print('vda window: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
