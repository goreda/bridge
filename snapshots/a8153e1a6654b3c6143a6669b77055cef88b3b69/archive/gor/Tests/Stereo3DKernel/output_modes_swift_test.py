#!/usr/bin/env python3
"""s36: Sources/gor/gor/ThreeD.swift (OutputModes.swift section) (pure Foundation, compiled and run on Linux) vs tools/depth_analysis/output_modes.py: canvas_size, eye_n_for, MODE_METADATA
(mpv stereo-mode, SAR stretch, spherical), legacy "sbs" alias and the menu defaults (flat full_sbs, headset vr180)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, shutil, subprocess, sys, tempfile, types
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root/'tools/depth_analysis'))
try: import cv2  # noqa
except ImportError: sys.modules['cv2'] = types.ModuleType('cv2')
import output_modes as om
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift6/usr/bin/swiftc'
tmp = pathlib.Path(tempfile.mkdtemp()); exe = tmp/'om'
shutil.copy(root/'Tests/Stereo3DKernel/output_modes_main.swift', tmp/'main.swift')
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'OutputModes.swift')), str(tmp/'main.swift'), '-o', str(exe)], capture_output=True, text=True)
if r.returncode: print(r.stderr[-1500:]); sys.exit(1)
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
for w, h in ((1920, 1080), (96, 54), (3840, 2160), (640, 200), (1280, 5000)):
    out = subprocess.run([str(exe), str(w), str(h)], capture_output=True, text=True, check=True).stdout.split('\n')
    rows = {l.split()[0]: l.split() for l in out if l}
    for m in om.MODES:
        t = rows[m]; md = om.MODE_METADATA[m]
        check(f'{m} {w}x{h} canvas', (int(t[1]), int(t[2])) == om.canvas_size(m, w, h))
        n = om.eye_n_for(h)
        check(f'{m} {w}x{h} eye size', (int(t[3]), int(t[4])) == ((w, h) if m != 'vr180' else (n, n)))
        sm = md['stereo_mode']; exp = 'sbsl' if sm.startswith('sbsl') else ('abl' if sm == 'abl' else '-')
        check(f'{m} stereo mode {t[5]} == {exp}', t[5] == exp)
        check(f'{m} SAR stretch', float(t[6]) == (2.0 if md['sar'].startswith('2:1') else 1.0))
        check(f'{m} spherical only vr180', (t[7] == 'true') == ('spherical' in sm))
    check(f'{w}x{h} eyeN', int(rows['vr180'][3]) == om.eye_n_for(h))
check('legacy sbs alias -> full_sbs, vr180 parses, bogus nil', subprocess.run([str(exe), '96', '54'], capture_output=True, text=True).stdout.count('parse full_sbs vr180 nil') == 1)
check('defaults: flat full_sbs, headset vr180', 'default full_sbs vr180' in subprocess.run([str(exe), '96', '54'], capture_output=True, text=True).stdout)
print('output_modes swift: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
