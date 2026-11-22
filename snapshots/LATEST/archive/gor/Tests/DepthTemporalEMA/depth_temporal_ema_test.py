#!/usr/bin/env python3
"""195h B: DepthTemporalEMA per-shot depth-range normalisation, default off. SYNTHETIC breathing scene; no owner baseline and no
measurement on a real film. Linux swiftc, Foundation only."""
import os, pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw and os.path.exists(sw):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'dte'
    ema = (S / 'DepthGuards.swift').read_text().split('// BEGIN relocated DepthTemporalEMA.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthTemporalEMA.swift')[0]  # 195y G2
    tmp_ema = pathlib.Path(tempfile.mkdtemp()) / 'DepthTemporalEMA.swift'; tmp_ema.write_text('import Foundation\n' + ema)
    r = subprocess.run([sw, '-O', str(tmp_ema), str(root / 'Tests/DepthTemporalEMA/main.swift'), '-o', str(exe)], capture_output=True, text=True)
    check('DepthTemporalEMA compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-500:]); sys.exit(1)
    o = subprocess.run([str(exe)], capture_output=True, text=True).stdout
    check('driver enables the flag through the locked mutator (review r1)', 'default off true' in o and 'enabled after toggle true' in o)
    raw, ema = map(float, re.search(r'breathing range jitter raw (\S+) ema (\S+)', o).groups())
    check('SYNTHETIC breathing range jitter (tail 20): raw %.4f -> ema %.4f (at least 2x lower)' % (raw, ema), ema * 2 <= raw)
    check('invalid (0, nan) pass through, valid values remapped onto the EMA range', 'invalid zero 0.0 nankept true mapped true' in o)
    check('flag off: byte-identical passthrough, state never primes', 'flagoff identical true primed true' in o)
    check('persisted state restores primed exactly (review r3-3)', 'restore exact primed true lo true hi true' in o)
else: print('SKIPPED numeric (no swiftc)')
sa = (S / 'ShotPrepareAssembly.swift').read_text()
check('wired in ShotPrepareAssembly after TemporalDepth.smooth and BEFORE overlay flatten and the container append',
      sa.index('rangeEMA.apply(metres)') > sa.index('TemporalDepth.smooth') and sa.index('rangeEMA.apply(metres)') < sa.index('flattenOverlay(z: metres'))
check('state is per prepare job, frozen from the job snapshot (shot-boundary reset)', 'var rangeEMA = DepthTemporalEMA.State(active: expOptions.depthRangeEMA)' in sa and 'let expOptions = job.experiments' in sa)
check('assembly never reads the raw statics', 'DepthTemporalEMA.enabled' not in sa and 'DepthTemporalEMA.isEnabled()' not in sa)
ps = (S / 'PrepareSupport.swift').read_text()
check('per-CONTAINER mode marker, written after the writer holds the container (r3-2)', 'appendingPathExtension("options.json")' in sa and '"depth_range_ema": options.depthRangeEMA' in ps and 'writeJSON(PrepareSupport.prepareIdentity(expOptions), to: modeMarker)' in sa)
check('resume restores the persisted state exactly; lost state -> exact spool replay, never an approximate prime (Delivery 7)', 'DepthTemporalEMA.State(active: true, lo: Float(lo), hi: Float(hi), primed: pr)' in sa and 'appendingPathExtension("ema.json")' in sa and 'spool short in the EMA replay' in sa)
check('EMA state persisted after the append with frame count and primed (r3-3)', 'writeJSON(["lo": rangeEMA.lo, "hi": rangeEMA.hi, "primed": rangeEMA.primed, "frames": fi + 1]' in sa)
co = (S / 'ThreeDRenderCoordinator.swift').read_text()
check('coordinator checks the mode per container before using the cache (r2-4/5)', 'PrepareSupport.optionsMatch(dzc: hit.depth, options: expOpts)' in co)
check('render key carries the options component (review r2)', 'options.renderKeyComponent.map { $0 + "|" }' in co)
w = (S / 'RenderShotWriter.swift').read_text()
check('render shot writer passes the per-shot snapshot to render()', 'output: plan.output, options: options' in w)
menu = (S / 'ThreeDExperimentMenu.swift').read_text()
check('switch defaults OFF', 'static var enabled = false' in (S / 'DepthGuards.swift').read_text().split('// BEGIN relocated DepthTemporalEMA.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthTemporalEMA.swift')[0])
check('menu row tag 10 wired', '(10,"B depth range EMA")' in menu and 'case 10: DepthTemporalEMA.toggleEnabled();onExperimentChange();return' in menu)
print('depth temporal ema: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
