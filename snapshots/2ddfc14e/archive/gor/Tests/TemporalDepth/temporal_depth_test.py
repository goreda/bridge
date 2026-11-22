#!/usr/bin/env python3
"""F2b (A-D 14:41): temporal depth smoothing. SYNTHETIC static scene with injected noise; there is NO owner baseline and no measurement on a real film. Linux swiftc, Foundation only."""
import os, pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw and os.path.exists(sw):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'td'
    td = (S / 'DepthGuards.swift').read_text().split('// BEGIN relocated TemporalDepth.swift (195y G2, behavior unchanged)')[1].split('// END relocated TemporalDepth.swift')[0]  # 195y G2
    tmp_td = pathlib.Path(tempfile.mkdtemp()) / 'TemporalDepth.swift'; tmp_td.write_text('import Foundation\n' + td)
    r = subprocess.run([sw, '-O', str(tmp_td), str(root / 'Tests/TemporalDepth/main.swift'), '-o', str(exe)], capture_output=True, text=True)
    check('TemporalDepth compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-500:]); sys.exit(1)
    o = subprocess.run([str(exe)], capture_output=True, text=True).stdout
    raw, sm = map(float, re.search(r'static jitter raw (\S+) smooth (\S+)', o).groups())
    check('SYNTHETIC static scene d2 jitter p95 (relative): raw %.4f -> smoothed %.4f (at least 2x lower)' % (raw, sm), sm * 2 <= raw)
    e20, e21 = map(float, re.search(r'frame20 err (\S+) frame21 (\S+)', o).groups())
    check('SYNTHETIC 25%% depth step passes through the motion gate at once (err %.4f at the step frame, %.4f after)' % (e20, e21), e20 < 1e-6 and e21 < 1e-6)
    lag = float(re.search(r'ramp lag worst (\S+)', o).group(1))
    check('SYNTHETIC slow ramp (0.4%%/frame): worst lag %.4f stays under 1%%' % lag, lag < 0.01)
    check('invalid (<=0, nan) pass through unchanged, size mismatch returns cur', 'invalid [3.0, 0.0, 2.0] mismatch [1.0, 2.0]' in o)
else: print('SKIPPED numeric (no swiftc)')
sa = (S / 'ShotPrepareAssembly.swift').read_text()
check('wired in ShotPrepareAssembly phase 2 after skyClamped and BEFORE overlay flatten and the container append', sa.index('TemporalDepth.smooth') > sa.index('var metres = skyClamped') and sa.index('TemporalDepth.smooth') < sa.index('flattenOverlay(z: metres') and sa.index('flattenOverlay(z: metres') < sa.index('w.append(zMetres: metres)'))
print('temporal depth: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
