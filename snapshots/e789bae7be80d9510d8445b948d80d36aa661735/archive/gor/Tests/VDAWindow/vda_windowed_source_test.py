#!/usr/bin/env python3
"""190w W4: Sources/gor/VDAWindowedSource.swift + VDAWindowPlan.swift (pure Foundation) compiled and run on Linux with a FAKE windowed model: each window returns a random affine of the ground-truth depth
of the frames it was fed (so the KEYFRAMES carry-over, padding, sequential reads and the crossfade stitch are all exercised). CoreML (VDAWindowRunner) is parse-only here."""
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
let n = Int(a[1])!, px = 4, first = Int(a[2])!, failAt = Int(a[3])!
func gt(_ f: Int, _ p: Int) -> Float { Float(f) * 0.1 + Float(p) * 0.5 + 1 }
var reads = [Int](), calls = 0, hooks = [Int]()
let src = VDAWindowedSource(frameCount: n, px: px,
    input: { f in reads.append(f); return [Float](repeating: Float(f), count: 3 * px) },
    window: { frames in
        calls += 1; if calls == failAt { return nil }
        let sc = Float(0.5 + Double(calls) * 0.37), sh = Float(Double(calls) * 0.21)
        var out = [Float](); for fr in frames { let f = Int(fr[0]); for p in 0..<px { out.append((gt(f, p) - sh) / sc) } }
        return out })
src.onRead = { hooks.append($0) }
var res = [[Float]]()
for k in first..<n { guard let d = src.depth(frame: k) else { print("FAILED at \\(k)"); break }; res.append(d) }
print(res.map { $0.map { String($0) }.joined(separator: ",") }.joined(separator: ";"))
print(reads.map { String($0) }.joined(separator: ","))
print(hooks.map { String($0) }.joined(separator: ","))
print(calls)
''')
exe = tmp / 's'
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'VDAWindowPlan.swift')), str(tmp / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('compiles (Linux, Foundation only)', r.returncode == 0)
if r.returncode: print(r.stderr[-1200:]); sys.exit(1)
def run(n, first=0, fail=0):
    o = subprocess.run([str(exe), str(n), str(first), str(fail)], capture_output=True, text=True, check=True).stdout.strip().split('\n')
    return o
def gt(n, px=4): return np.array([[f * 0.1 + p * 0.5 + 1 for p in range(px)] for f in range(n)], dtype=np.float64)
for n in (1, 10, 23, 60, 100):
    o = run(n)
    res = np.array([[float(v) for v in row.split(',')] for row in o[0].split(';')])
    reads = [int(x) for x in o[1].split(',')]
    A = np.polyfit(res.ravel(), gt(n).ravel(), 1); err = np.abs(res * A[0] + A[1] - gt(n)).max()
    check('n=%d: %d frames, consistent depth after one global affine (max err %.1e)' % (n, len(res), err), len(res) == n and err < 2e-3)
    check('n=%d: reads strictly ascending 0..n-1 once each; onRead fired per read; windows run lazily (<= ceil(n/22))' % n, reads == list(range(n)) and o[2] == o[1] and 0 < int(o[3]) <= (n + 21) // 22)
o = run(100, first=50)
res = np.array([[float(v) for v in row.split(',')] for row in o[0].split(';')])
check('resume: first request frame 50 recomputes from 0 and returns frames 50..99 identical in shape', len(res) == 50)
o = run(100, fail=2)
check('model failure on window 2 -> the step fails (no substitute depth)', o[0].startswith('FAILED at'))
rn = (lambda _b: _b[_b.index('// BEGIN relocated '+'VDAWindowPlan.swift'+' '):_b.index('// END relocated '+'VDAWindowPlan.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated VDAWindowRunner.swift (195y G2, behavior unchanged)')[1].split('// END relocated VDAWindowRunner.swift')[0]  # 195y G2
check('runner: encoder batch 32 -> feat1..4 -> head -> depth [1,32,H,W]; parity helper; CoreML-gated', 'windowed_encoder_fp16.mlpackage' in rn and 'windowed_head_fp16.mlpackage' in rn and '"feat\\(i)"' in rn and 'func parityError' in rn and '#if canImport(CoreML)' in rn)
print('windowed source: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
