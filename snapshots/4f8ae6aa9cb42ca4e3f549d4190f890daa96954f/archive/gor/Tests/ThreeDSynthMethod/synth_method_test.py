#!/usr/bin/env python3
"""190w W3: Sources/gor/ThreeDSynthMethod.swift (pure Foundation) compiled and run on Linux: tier selection (T1 video > T2 > T3, dibr_golden labelled fallback), honesty rule (a tier
without a runner is never selected), weight-file presence, and the v4 render key pins in ThreeDRenderCoordinator. No learned runner exists in Swift (weights are .pth): today's choice is dibr_golden."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
co = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(root)).read_text()); sm = (lambda _b: _b[_b.index('// BEGIN relocated '+'NunifPipeline.swift'+' '):_b.index('// END relocated '+'NunifPipeline.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated ThreeDSynthMethod.swift (195y G2, behavior unchanged)')[1].split('// END relocated ThreeDSynthMethod.swift')[0]  # 195y G2
check('render key v4: "v4|\\(method.rawValue)|" + the v3 body, default method = SynthMethod.current', '"v4|\\(method.rawValue)|\\(ipdPart)|' in co and 'method: SynthMethod = SynthMethod.current.method' in co and '"v3|' not in co)
check('announced once: log line "3d-synth:" + OSD note', 'synthTold' in co and '3d-synth:' in co and 'announce(SynthMethod.current.note)' in co)
check('only dibr_golden has a runner today; the label says fallback', 'static let implemented: Set<SynthMethod> = [.dibr_golden]' in sm and '(fallback:' in sm)
check('weight files per tier (nunif manifest names)', all(f in sm for f in ('iw3_mask_mlbw_l2_d1_20250903.pth', 'iw3_light_video_inpaint_v1_20250919.pth', 'iw3_light_inpaint_v1_20250919.pth', 'iw3_row_flow_v3_20250627.pth')))
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swiftc or not os.path.exists(swiftc):
    print('SKIPPED numeric: no swiftc'); print('synth method: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / 'main.swift').write_text('''import Foundation
let a = CommandLine.arguments
let all = Set(SynthMethod.allCases)
if a[1] == "sel" { let pres = Set(a[2].split(separator: ",").compactMap { SynthMethod(rawValue: String($0)) }); let imp = a[3] == "all" ? all : Set(a[3].split(separator: ",").compactMap { SynthMethod(rawValue: String($0)) })
  let c = SynthMethod.select(present: pres, implemented: imp); print(c.method.rawValue); print(c.note) }
if a[1] == "dir" { print(SynthMethod.present(modelsDir: URL(fileURLWithPath: a[2])).map { $0.rawValue }.sorted().joined(separator: ",")) }
''')
exe = tmp / 's'
np_full = (lambda _b: _b[_b.index('// BEGIN relocated '+'NunifPipeline.swift'+' '):_b.index('// END relocated '+'NunifPipeline.swift'+'\n')])((_threed_split().path(root)).read_text())
np_full = np_full[:np_full.index('// BEGIN relocated ThreeDSynthCurrent.swift (195y G2, behavior unchanged)')] + np_full[np_full.index('// END relocated ThreeDSynthCurrent.swift'):]  # 195y G2: span needs ThreeDModels, out of scope here
tmp.joinpath('NunifPipeline.swift').write_text(np_full)
r = subprocess.run([swiftc, '-O', str(tmp / 'NunifPipeline.swift'), str(tmp / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('compiles (Linux, Foundation only)', r.returncode == 0)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
run = lambda *a: subprocess.run([str(exe), *a], capture_output=True, text=True, check=True).stdout.strip().split('\n')
T1, T2, T3, D = 'mlbw_l2_inpaint_video', 'mlbw_l2_inpaint', 'row_flow_v3', 'dibr_golden'
check('all weights + all runners: T1 wins', run('sel', f'{T1},{T2},{T3},{D}', 'all')[0] == T1)
check('T2+T3 present: T2', run('sel', f'{T2},{T3},{D}', 'all')[0] == T2)
check('only T3 present: T3', run('sel', f'{T3},{D}', 'all')[0] == T3)
o = run('sel', D, 'all')
check('no weights: dibr_golden with "fallback" and "no learned weights"', o[0] == D and 'fallback' in o[1] and 'no learned weights' in o[1])
o = run('sel', f'{T1},{T2},{T3},{D}', D)
check('weights present but no runner (today): dibr_golden, note says so (never claims T1)', o[0] == D and 'no runner' in o[1] and 'fallback' in o[1] and T1 not in o[1])
o = run('sel', f'{T1},{T2},{D}', f'{T2},{D}')
check('only T2 has a runner: T2 even though T1 weights exist', o[0] == T2)
d = tmp / 'models'; (d / 'nunif').mkdir(parents=True)
check('empty nunif dir: dibr_golden only', run('dir', str(d))[0] == D)
nd = d / 'nunif'
for f in ('iw3_row_flow_v3_20250627.pth', 'iw3_mask_mlbw_l2_d1_20250903.pth'): (nd / f).write_bytes(b'x')
check('mask alone is not a tier; row_flow file -> T3 only', run('dir', str(d))[0] == f'{D},{T3}')
(nd / 'iw3_light_inpaint_v1_20250919.pth').write_bytes(b'x')
check('mask + light_inpaint -> T2 and T3', run('dir', str(d))[0] == f'{D},{T2},{T3}')
(nd / 'iw3_light_video_inpaint_v1_20250919.pth').write_bytes(b'x')
check('+ light_video_inpaint -> T1, T2, T3', run('dir', str(d))[0] == f'{D},{T2},{T1},{T3}')
print('synth method: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / 'main.swift').write_text('''import Foundation
let a = CommandLine.arguments
let all = Set(SynthMethod.allCases)
if a[1] == "sel" { let pres = Set(a[2].split(separator: ",").compactMap { SynthMethod(rawValue: String($0)) }); let imp = a[3] == "all" ? all : Set(a[3].split(separator: ",").compactMap { SynthMethod(rawValue: String($0)) })
  let c = SynthMethod.select(present: pres, implemented: imp); print(c.method.rawValue); print(c.note) }
if a[1] == "dir" { print(SynthMethod.present(modelsDir: URL(fileURLWithPath: a[2])).map { $0.rawValue }.sorted().joined(separator: ",")) }
''')
exe = tmp / 's'
np_full = (lambda _b: _b[_b.index('// BEGIN relocated '+'NunifPipeline.swift'+' '):_b.index('// END relocated '+'NunifPipeline.swift'+'\n')])((_threed_split().path(root)).read_text())
np_full = np_full[:np_full.index('// BEGIN relocated ThreeDSynthCurrent.swift (195y G2, behavior unchanged)')] + np_full[np_full.index('// END relocated ThreeDSynthCurrent.swift'):]  # 195y G2: span needs ThreeDModels, out of scope here
tmp.joinpath('NunifPipeline.swift').write_text(np_full)
r = subprocess.run([swiftc, '-O', str(tmp / 'NunifPipeline.swift'), str(tmp / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
check('compiles (Linux, Foundation only)', r.returncode == 0)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
run = lambda *a: subprocess.run([str(exe), *a], capture_output=True, text=True, check=True).stdout.strip().split('\n')
T1, T2, T3, D = 'mlbw_l2_inpaint_video', 'mlbw_l2_inpaint', 'row_flow_v3', 'dibr_golden'
check('all weights + all runners: T1 wins', run('sel', f'{T1},{T2},{T3},{D}', 'all')[0] == T1)
check('T2+T3 present: T2', run('sel', f'{T2},{T3},{D}', 'all')[0] == T2)
check('only T3 present: T3', run('sel', f'{T3},{D}', 'all')[0] == T3)
o = run('sel', D, 'all')
check('no weights: dibr_golden with "fallback" and "no learned weights"', o[0] == D and 'fallback' in o[1] and 'no learned weights' in o[1])
o = run('sel', f'{T1},{T2},{T3},{D}', D)
check('weights present but no runner (today): dibr_golden, note says so (never claims T1)', o[0] == D and 'no runner' in o[1] and 'fallback' in o[1] and T1 not in o[1])
o = run('sel', f'{T1},{T2},{D}', f'{T2},{D}')
check('only T2 has a runner: T2 even though T1 weights exist', o[0] == T2)
d = tmp / 'models'; (d / 'nunif').mkdir(parents=True)
check('empty nunif dir: dibr_golden only', run('dir', str(d))[0] == D)
(d / 'nunif' / 'iw3_row_flow_v3_20250627.pth').write_bytes(b'x'); (d / 'nunif' / 'iw3_mlbw_l2_d1_20250627.pth').write_bytes(b'x')
check('weight files found by name -> T2 and T3 present', run('dir', str(d))[0] == f'{D},{T2},{T3}'.replace(f'{D},', 'dibr_golden,'))
print('synth method: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
