#!/usr/bin/env python3
"""S1 (A-D parity plan): Swift NunifPipeline vs nunif_pipeline_fixture.npz, max-abs per tensor (Linux swiftc). The fixture inputs are regenerated from the reference's own seeded RNG (rng 190, same draw order as its main())."""
import os, pathlib, re, shutil, subprocess, sys, tempfile
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'; K = root / 'tools/depth_analysis/kit'
sys.path.insert(0, str(K))
import nunif_pipeline_reference as ref
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
fx = np.load(K / 'nunif_pipeline_fixture.npz')
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not (sw and os.path.exists(sw)): print('SKIPPED numeric (no swiftc)'); sys.exit(0)
rng = np.random.default_rng(190); h, w = 24, 48
depth = rng.random((h, w), dtype=np.float32); frame = rng.random((1, 3, h, w), dtype=np.float32)
logits = rng.standard_normal((1, 1, h, w)).astype(np.float32) * 2.0; mask = (rng.random((1, 1, h, w), dtype=np.float32) > 0.7).astype(np.float32)
dx = rng.standard_normal((1, 2, h, w)).astype(np.float32) * 0.5; lw = rng.random((1, 2, h, w), dtype=np.float32)
check('regenerated inputs reproduce the fixture through the numpy reference (warp_out, mask_post)', np.abs(ref.apply_mlbw_delta_weight(frame, dx, lw, 2) - fx['warp_out']).max() < 1e-6 and (ref.postprocess_hole_mask(logits, (h, w), 0.15, 1, 1).astype(np.uint8) == fx['mask_post']).all())
d = pathlib.Path(tempfile.mkdtemp())
for n, a in dict(in_depth=depth, in_frame=frame, in_logits=logits, in_mask=mask, in_delta_x=dx, in_lw=lw, **{k: fx[k] for k in fx.files}).items():
    np.asarray(a, dtype=np.float32).tofile(d / (n + '.f32'))
tos = np.load(K / 'x2_tos_reference/tos_depth_minmax_320x180_fp16.npz')['depth'].astype(np.float32)
mins = [float(f.min()) for f in tos]; maxs = [float(f.max()) for f in tos]
check('A-D ToS depth fixture is per-frame minmax (all 48 frames: min %.4f..%.4f, max %.4f..%.4f)' % (min(mins), max(mins), min(maxs), max(maxs)), max(mins) < 6e-3 and min(maxs) > 0.99)   # the fixture is normalised at 266x462 and THEN bilinear-resized + fp16, so the extremes shrink slightly
tos[0].reshape(-1).tofile(d / 'tos_frame0.f32')
exe = d / 'np'
np_full = (S / 'NunifPipeline.swift').read_text()
np_full = np_full[:np_full.index('// BEGIN relocated ThreeDSynthCurrent.swift (195y G2, behavior unchanged)')] + np_full[np_full.index('// END relocated ThreeDSynthCurrent.swift'):]  # 195y G2: span needs ThreeDModels, out of scope here
d.joinpath('NunifPipeline.swift').write_text(np_full)
r = subprocess.run([sw, '-O', str(d / 'NunifPipeline.swift'), str(root / 'Tests/NunifPipeline/main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('NunifPipeline compiles (Linux)', r.returncode == 0)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
o = subprocess.run([str(exe), str(d)], capture_output=True, text=True)
if o.returncode: print(o.stderr[-500:])
res = {m.group(1): float(m.group(2)) for m in re.finditer(r'^(\w+) (\S+)$', o.stdout, re.M) if m.group(1) != 'plan48'}
print('S1 per-tensor max-abs vs fixture (Swift float32 vs numpy float32):')
for k, v in res.items(): print('   %-22s %.3g' % (k, v))
for k in fx.files:
    tol = 0 if k in ('mask_post', 'windows_26f', 'windows_26f_emit') else 1e-5
    check('%s max-abs %.3g <= %g' % (k, res.get(k, 1e9), tol), res.get(k, 1e9) <= tol)
mm = re.search(r'^minmax (\S+) (\S+) (\S+) (\S+) flat \[(.*?)\] fix (\S+)$', o.stdout, re.M)
check('per-frame minmax: raw VDA range 0.045..16.6 -> 0..1 (mid 8.0 -> %s), nan -> 0, flat frame -> zeros, ToS fixture frame idempotent (max-abs %s)' % (mm.group(3), mm.group(6)), float(mm.group(1)) == 0 and float(mm.group(2)) == 1 and abs(float(mm.group(3)) - (8.0 - 0.045) / (16.6 - 0.045)) < 1e-6 and float(mm.group(4)) == 0 and mm.group(5) == '0.0, 0.0, 0.0' and float(mm.group(6)) < 6e-3)
p48 = re.search(r'^plan48 (.*)$', o.stdout, re.M).group(1)
pr = ref.video_windows(48)
check('48-frame window starts and emit slices equal the reference plan (S3 boundary table): %s' % p48, p48 == ' '.join('%d:%d-%d' % (p[0][0], p[1][0], p[1][1]) for p in pr))
print('nunif pipeline: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
