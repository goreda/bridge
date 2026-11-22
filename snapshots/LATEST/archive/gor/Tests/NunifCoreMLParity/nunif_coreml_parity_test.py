#!/usr/bin/env python3
"""S2 (A-D parity plan): CoreML-vs-torch per-package parity driver harness (NUNIF-COREML-RUNNER-CONTRACT.md "Parity fixtures").

usage: nunif_coreml_parity_test.py <kitDir>   (kitDir = extracted gor-kit-nunif-coreml tar)

What runs where:
- Linux/Mac: verifies each kit fixture npz sha256 against tools/depth_analysis/kit/nunif-coreml-kit-manifest.json,
  dumps .f32 + manifest.json for the Swift driver, compiles Tests/NunifCoreMLParity/main.swift.
- Mac only: runs the driver against the .mlpackage files and prints the S2 table (package x output x max-abs, PSNR).
- Linux: the numeric run is NOT_RUN (no CoreML runtime on Linux); the compiled driver prints NOT_RUN coreml-unavailable.
No pass threshold is pre-claimed (fp16 packages deviate); the table itself is the evidence.
"""
import hashlib, json, os, pathlib, shutil, subprocess, sys, tempfile
import numpy as np

root = pathlib.Path(__file__).resolve().parents[2]
S = root / 'Sources/gor'
KIT_MANIFEST = root / 'tools/depth_analysis/kit/nunif-coreml-kit-manifest.json'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)

if len(sys.argv) < 2:
    print('usage: nunif_coreml_parity_test.py <kitDir>  (extracted gor-kit-nunif-coreml tar)')
    sys.exit(2)
kit = pathlib.Path(sys.argv[1])
mani = json.load(open(KIT_MANIFEST))

d = pathlib.Path(tempfile.mkdtemp(prefix='nunif-parity-dump-'))
n_fix = 0
for fname, meta in sorted(mani['fixtures'].items()):
    p = kit / fname
    if not p.exists():
        check('fixture present: %s' % fname, False); continue
    h = hashlib.sha256(p.read_bytes()).hexdigest()
    check('fixture sha256 %s' % fname, h == meta['sha256'])
    if h != meta['sha256']: continue
    stem = fname[:-len('_fixture.npz')]
    fx = np.load(p)
    inputs = {k[3:]: {'shape': list(fx[k].shape), 'file': k + '.f32'} for k in fx.files if k.startswith('in_')}
    refs = {k[4:]: {'file': k + '.f32'} for k in fx.files if k.startswith('out_')}
    check('fixture %s has in_*/out_* arrays' % stem, bool(inputs) and bool(refs))
    sub = d / stem; sub.mkdir()
    for k in fx.files:
        np.asarray(fx[k], dtype=np.float32).tofile(sub / (k + '.f32'))
    pkg = stem + '_fp16.mlpackage' if not stem.endswith('_fp16') else stem + '.mlpackage'
    json.dump({'package': pkg, 'inputs': inputs, 'refs': refs}, open(d / (stem + '.json'), 'w'))
    n_fix += 1

sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not (sw and os.path.exists(sw)):
    print('SKIPPED compile+run (no swiftc); fixture dump at %s' % d)
    sys.exit(1 if fails else 0)
exe = d / 'nunif-parity'
np_full = (S / 'NunifPipeline.swift').read_text()
np_full = np_full[:np_full.index('// BEGIN relocated ThreeDSynthCurrent.swift (195y G2, behavior unchanged)')] + np_full[np_full.index('// END relocated ThreeDSynthCurrent.swift'):]  # 195y G2: span needs ThreeDModels, out of scope here
np_tmp = d / 'NunifPipeline.swift'
np_tmp.write_text(np_full)
srcs = [S / 'PrepareSupport.swift', S / 'KitCompiledCache.swift', np_tmp, root / 'Tests/NunifCoreMLParity/main.swift']
r = subprocess.run([sw, '-O'] + [str(s) for s in srcs] + ['-o', str(exe)], capture_output=True, text=True)
check('parity driver compiles', r.returncode == 0)
if r.returncode:
    print(r.stderr[-1500:]); sys.exit(1)
o = subprocess.run([str(exe), str(kit), str(d)], capture_output=True, text=True)
print(o.stdout, end='')
if o.stderr: print(o.stderr[-500:], file=sys.stderr)
if 'NOT_RUN coreml-unavailable' in o.stdout:
    print('S2 numeric run NOT_RUN: no CoreML runtime on this platform (Linux). Re-run on the Mac with the same kit dir to post the S2 table.')
    sys.exit(1 if fails else 0)
for line in o.stdout.splitlines():
    if line.endswith('RUN_FAIL'):
        check('driver ran %s' % line.split()[0], False)
rows = [l for l in o.stdout.splitlines() if ' maxabs ' in l]
check('S2 table rows posted (%d fixture(s) dumped, %d row(s))' % (n_fix, len(rows)), n_fix > 0 and len(rows) > 0)
print('nunif coreml parity: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
