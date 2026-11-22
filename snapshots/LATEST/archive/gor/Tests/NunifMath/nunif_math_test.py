#!/usr/bin/env python3
"""190w W3: NunifMath (pad to 96 + crop, bilinear align_corners upsample) vs numpy references, compiled with swiftc on Linux."""
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
root = pathlib.Path(__file__).resolve().parents[2]
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swiftc or not os.path.exists(swiftc): print('SKIPPED: no swiftc'); sys.exit(0)
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / 'main.swift').write_text('''import Foundation
let a = CommandLine.arguments, h = Int(a[1])!, w = Int(a[2])!, th = Int(a[3])!, tw = Int(a[4])!
var x = [Float](); for i in 0..<(2*h*w) { x.append(Float((i * 37) % 101) / 7) }
let p = NunifMath.padReplicate(x, c: 2, h: h, w: w)!
let c = NunifMath.crop(p.data, c: 2, ph: p.h, pw: p.w, h: h, w: w)!
print(p.h, p.w, c == x ? 1 : 0)
print(p.data.map { String($0) }.joined(separator: ","))
let up = NunifMath.resizeBilinearAligned(Array(x[0..<(h*w)]), h: h, w: w, toH: th, toW: tw)
print(up.map { $0.map { String($0) }.joined(separator: ",") } ?? "nil")
print(NunifMath.resizeBilinearAligned(x, h: h, w: w, toH: 1, toW: 1) == nil ? "nil" : "bad")
''')
np_full = (lambda _b: _b[_b.index('// BEGIN relocated '+'NunifPipeline.swift'+' '):_b.index('// END relocated '+'NunifPipeline.swift'+'\n')])((_threed_split().path(root)).read_text())
np_full = np_full[:np_full.index('// BEGIN relocated ThreeDSynthCurrent.swift (195y G2, behavior unchanged)')] + np_full[np_full.index('// END relocated ThreeDSynthCurrent.swift'):]  # 195y G2: span needs ThreeDModels, out of scope here
tmp.joinpath('NunifPipeline.swift').write_text(np_full)
r = subprocess.run([swiftc, '-O', str(tmp / 'NunifPipeline.swift'), str(tmp / 'main.swift'), '-o', str(tmp / 's')], capture_output=True, text=True)
check('compiles', r.returncode == 0)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
for h, w, th, tw in ((5, 7, 11, 13), (96, 96, 192, 100), (100, 200, 100, 200)):
    o = subprocess.run([str(tmp / 's'), str(h), str(w), str(th), str(tw)], capture_output=True, text=True, check=True).stdout.strip().split('\n')
    ph, pw, same = map(int, o[0].split())
    x = np.array([(i * 37) % 101 / 7 for i in range(2 * h * w)], dtype=np.float32).reshape(2, h, w)
    ref = np.pad(x, ((0, 0), (0, ph - h), (0, pw - w)), mode='edge')
    got = np.array([float(v) for v in o[1].split(',')], dtype=np.float32).reshape(2, ph, pw)
    check('%dx%d: padded to %dx%d (multiple of 96), replicate == np.pad edge, crop round-trips' % (h, w, ph, pw), ph % 96 == 0 and pw % 96 == 0 and np.array_equal(ref, got) and same == 1)
    up = np.array([float(v) for v in o[2].split(',')], dtype=np.float64).reshape(th, tw)
    p = x[0].astype(np.float64)
    ys = np.linspace(0, h - 1, th); xs = np.linspace(0, w - 1, tw)
    y0 = np.floor(ys).astype(int); y1 = np.minimum(y0 + 1, h - 1); x0 = np.floor(xs).astype(int); x1 = np.minimum(x0 + 1, w - 1)
    ty = (ys - y0)[:, None]; tx = (xs - x0)[None, :]
    ref = (p[y0][:, x0] * (1 - tx) + p[y0][:, x1] * tx) * (1 - ty) + (p[y1][:, x0] * (1 - tx) + p[y1][:, x1] * tx) * ty
    check('%dx%d -> %dx%d bilinear align_corners matches numpy (max err %.1e)' % (h, w, th, tw, np.abs(up - ref).max()), np.abs(up - ref).max() < 1e-4)
check('down-scale refused (antialias not implemented)', o[3] == 'nil')
(tmp / 'm2.swift').write_text('''import Foundation
for n in [1, 5, 6, 7, 12, 13, 25] {
    let w = NunifMath.videoWindows(frameCount: n)
    print(n, w.map { "\\($0.input.map(String.init).joined(separator: ","))|\\($0.keep.lowerBound)-\\($0.keep.upperBound)" }.joined(separator: ";"))
}
print(NunifMath.holeMask(prob: [0.1, 0.15, 0.16, 0.9]).map { String($0) }.joined(separator: ","))
print(NunifMath.maskedInput(x: [1, 2, 3, 4, 5, 6], mask: [0, 1, 0.5], c: 2)!.map { String($0) }.joined(separator: ","))
''')
(tmp / 'main2.swift').write_text((tmp / 'm2.swift').read_text())
os.makedirs(tmp / 'b', exist_ok=True); (tmp / 'b' / 'main.swift').write_text((tmp / 'm2.swift').read_text())
r2 = subprocess.run([swiftc, '-O', str(tmp / 'NunifPipeline.swift'), str(tmp / 'b' / 'main.swift'), '-o', str(tmp / 's2')], capture_output=True, text=True)
check('video windows compile', r2.returncode == 0)
if r2.returncode: print(r2.stderr[-600:]); sys.exit(1)
o2 = subprocess.run([str(tmp / 's2')], capture_output=True, text=True, check=True).stdout.strip().split('\n')
for line in o2[:7]:
    n, rest = line.split(' ', 1); n = int(n); keeps = []; ok = True
    for w in rest.split(';'):
        ins, kp = w.split('|'); ins = [int(v) for v in ins.split(',')]; a, b = map(int, kp.split('-'))
        ok &= len(ins) == 12 and all(0 <= v < n for v in ins)
        for k in range(a, b): ok &= ins[k - a + 3] == k       # kept frame k sits at window position k - start + 3
        keeps += list(range(a, b))
    check('n=%d: windows of 12, kept frames cover 0..n-1 once, inputs clamped in range' % n, ok and keeps == list(range(n)))
check('hole mask threshold 0.15 (strictly greater), masked input x*(1-m)', o2[7] == '0.0,0.0,1.0,1.0'.replace('0.0','0.0') or o2[7] == '0.0,0.0,1.0,1.0')
check('masked input values', o2[8] == '1.0,0.0,1.5,4.0,0.0,3.0')
print('nunif math: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
