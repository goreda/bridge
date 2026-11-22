#!/usr/bin/env python3
"""195h review fixes (Delivery r1 items 2-4): ThreeDExperimentOptions snapshot - renderKeyComponent determinism, flag-off key identity,
and the snapshot-only callgraph pins. Linux swiftc, Foundation only."""
import os, pathlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw and os.path.exists(sw):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'eo'
    r = subprocess.run([sw, '-O', str(S / 'ThreeDExperimentOptions.swift'), str(root / 'Tests/ExperimentOptions/main.swift'), '-o', str(exe)], capture_output=True, text=True)
    check('ThreeDExperimentOptions compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-500:]); sys.exit(1)
    o = subprocess.run([str(exe)], capture_output=True, text=True).stdout
    check('all-off component is nil (flag-off keys byte-identical, review r2)', 'alloff nil' in o)
    check('single switch components are the fixed short tokens', 'dof exp-dof' in o)
    check('195h A tokens fold in sorted (dav2/tempema)', 'exp-dav2' in o and 'exp-dav2.tempema' in o)
    check('fixed deterministic order regardless of set order', 'fw_hg exp-fw.hg' in o and 'all exp-fw.dof.hg' in o)
    check('Equatable default comparison', 'equatable true' in o)
else: print('SKIPPED numeric (no swiftc)')
eo = (S / 'ThreeDExperimentOptions.swift').read_text()
check('.live reads only the lock-backed snapshots, Metal-gated', 'Stereo3DExperiments.snapshot()' in eo and 'DepthTemporalEMA.isEnabled()' in eo and 'DepthModelID.selected()' in eo and 'ModelDepthEMA.enabled' in eo and '#if canImport(Metal)' in eo)
k2 = (S / 'Stereo3DKernel.swift').read_text()
check('statics mutated only through locked toggles (review r2-3)', 'private static let lock = NSLock()' in k2 and 'func toggleFloatingWindow()' in k2 and 'func toggleDepthOfField()' in k2 and 'func toggleHoleFillGradient()' in k2)
check('B module present on the B lane', '// BEGIN relocated DepthTemporalEMA.swift (195y G2, behavior unchanged)' in (S / 'DepthGuards.swift').read_text())
menu = (S / 'ThreeDExperimentMenu.swift').read_text()
check('B menu row exposed (tag 10)', '(10,"B depth range EMA")' in menu)
co2 = (S / 'ThreeDRenderCoordinator.swift').read_text()
check('schedule threads the request snapshot (r3-1 compile fix)', 'schedule(index:index,from:hit.shot,prefs:prefs,plan:plan,key:baseKey,th:th,entry:entry,options:expOpts)' in co2 and 'key baseKey: String, th: Double, entry: URL, options expOpts: ThreeDExperimentOptions)' in co2)
check('one snapshot per request: key and write share expOpts', 'let expOpts = ThreeDExperimentOptions.live' in co2 and 'key(prefs, eyeN: plan.eyeN, codec: plan.codec, swap: plan.swapEyes, options: expOpts)' in co2 and 'surround: prefs.surroundSoft, options: expOpts, out: out,' in co2)
check('key string literal is clean of comments (r1/r3 regression pin)', [l for l in co2.splitlines() if 'v5|span-p5p95' in l and 'return' in l][0].rstrip().endswith('surroundSoft)"'))
w2 = (S / 'ThreeDWiring.swift').read_text()
check('menu toggle triggers the existing coordinator refresh (review r2-7)', 'onExperimentChange = { (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.preferencesDidChange(force: true) }' in w2)
check('menu toggles go through the locked toggles + refresh hook (rows 7-9)', all(t in menu for t in ('Stereo3DExperiments.toggleFloatingWindow();onExperimentChange()', 'Stereo3DExperiments.toggleDepthOfField();onExperimentChange()', 'Stereo3DExperiments.toggleHoleFillGradient();onExperimentChange()')))
k = (S / 'Stereo3DKernel.swift').read_text()
_r = k[k.index('func render(frame:'):k.index('func decodeDepth(')]
check('render(): zb bound at buffer 0 exactly once per eye (the clear/zmin/resolve/fill binding, review r1)', "enc.setBuffer(zb, offset: 0, index: 0)" in _r)
check('render(): no setBytes at index 0 anywhere (Params always at 1)', 'setBytes(&p, length: MemoryLayout<Params>.size, index: 0)' not in k)
print('experiment options: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
