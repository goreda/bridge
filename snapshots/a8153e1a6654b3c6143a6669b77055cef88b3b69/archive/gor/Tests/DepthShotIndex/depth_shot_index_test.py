#!/usr/bin/env python3
"""DepthShotIndex vs prepare_film.find_shot_at_pts on a fixture (Python model of the Swift logic; Swift uncompiled)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import json, os, pathlib, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
import ast, types
# prepare_film imports torch at module level: lift only find_shot_at_pts out of its source.
_src = (root / 'tools/depth_analysis/prepare_film.py').read_text()
_fn = next(n for n in ast.parse(_src).body if isinstance(n, ast.FunctionDef) and n.name == 'find_shot_at_pts')
prepare_film = types.SimpleNamespace(); _ns = {'json': json, 'os': os}
exec(compile(ast.Module([_fn], []), 'prepare_film', 'exec'), _ns); prepare_film.find_shot_at_pts = _ns['find_shot_at_pts']
s = (lambda _b: _b[_b.index('// BEGIN relocated '+'DepthContainerWriter.swift'+' '):_b.index('// END relocated '+'DepthContainerWriter.swift'+'\n')])((_threed_split().path(root)).read_text()).split('// BEGIN relocated DepthShotIndex.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthShotIndex.swift')[0]  # 195y G2
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def dzc_complete(p):  # DZCFile.isComplete: header ok, size fits n_frames, trailer last
    try: b = open(p, 'rb').read()
    except OSError: return False
    if len(b) < 72 or b[:8] != b'GORDZ001': return False
    n = int.from_bytes(b[52:56], 'little'); return n > 0 and len(b) >= 64 + n * 8 + 8 and b[-8:] == b'GORDZEND'
def mk_dzc(p, complete=True):
    h = bytearray(64); h[:8] = b'GORDZ001'; h[52:56] = (1).to_bytes(4, 'little')
    rec = bytes(8); open(p, 'wb').write(bytes(h) + rec + ((64).to_bytes(8, 'little') + b'GORDZEND' if complete else b''))
def model(entry, pts):  # same steps as DepthShotIndex.find
    cuts = json.load(open(entry + '/cuts.json')); fps = json.load(open(entry + '/fov_track.json'))['fps']
    f = round(pts * fps)
    for i, (a, b) in enumerate(cuts['shots']):
        if a <= f <= b:
            p = f'{entry}/depth_shot_{i:05d}.dzc'; q = f'{entry}/source_shot_{i:05d}.mp4'
            return None if not (dzc_complete(p) and os.path.exists(q)) else (i, f, f - a)
    return None
with tempfile.TemporaryDirectory() as d:
    json.dump({'cuts': [30], 'shots': [[0, 29], [30, 59], [60, 89]]}, open(d + '/cuts.json', 'w'))
    json.dump({'fps': 24.0, 'shots': []}, open(d + '/fov_track.json', 'w'))
    for i in (0, 2):
        open(f'{d}/depth_shot_{i:05d}.mp4', 'wb').close(); mk_dzc(f'{d}/depth_shot_{i:05d}.dzc'); open(f'{d}/source_shot_{i:05d}.mp4', 'wb').close()   # .mp4 only feeds the Python reference
    open(f'{d}/depth_shot_00001.mp4', 'wb').close(); mk_dzc(f'{d}/depth_shot_00001.dzc', complete=False)   # shot 1: depth only, proxy missing
    ok = True
    for pts in [0.0, 0.5, 1.2, 1.25, 1.3, 2.5, 3.0, 3.7, 99.0, -1.0, 0.0208, 0.0625]:
        r = prepare_film.find_shot_at_pts(d, pts); m = model(d, pts)
        if r is not None and r.get('source_mp4') is None: r = None   # Swift (stricter than the Python, by design): no source proxy = not prepared -> 2D
        ok &= (r is None and m is None) or (r is not None and m == (r['shot'], r['frame'], r['frame_in_shot']))
    check('model equals find_shot_at_pts (hits, unprepared shot, out of range, half-even rounding)', ok)
check('fov matched by start_pts/end_pts, not position', 'start_pts' in s and 'tracks[i]' not in s)
check('Swift rounds half to even like Python round()', '.toNearestOrEven' in s)
check('Swift requires source proxy too', 'source_shot_%05d.mp4' in s)
check('Swift file name pattern depth_shot_%05d.dzc and completeness check', 'depth_shot_%05d.dzc' in s and 'DZCFile.isComplete(dz)' in s and '.mp4", i))\n' not in s.split('let src')[0].split('let dz')[1])
check('inclusive ranges', 'r[0] <= f && f <= r[1]' in s)
check('fov guard 1..179 degrees, radians out', 't.hfovDeg > 1, t.hfovDeg < 179' in s and 't.hfovDeg * .pi / 180' in s)
sys.exit(1 if fails else 0)
