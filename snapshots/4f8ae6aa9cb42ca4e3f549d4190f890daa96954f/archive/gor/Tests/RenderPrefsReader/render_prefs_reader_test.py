#!/usr/bin/env python3
"""RenderPrefsReader.swift (190t E-G): Python mirror of RenderPrefsValue.parse plus text pins; keys/defaults must equal the writer (FilmPrepareStatus.swift) and CONTRACT-190v s4. Swift not compiled here."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import json, pathlib, sys, math
r = pathlib.Path(__file__).resolve().parents[2]
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'RenderPrefsReader.swift'+' '):_b.index('// END relocated '+'RenderPrefsReader.swift'+'\n')])((_threed_split().path(r)).read_text()); wr = (lambda _b: _b[_b.index('// BEGIN relocated '+'FilmPrepareStatus.swift'+' '):_b.index('// END relocated '+'FilmPrepareStatus.swift'+'\n')])((_threed_split().path(r)).read_text())
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def parse(b):
    D = dict(mode='off', depth_scale=1.0, ipd_m=0.063, convergence_m=None)
    try: o = json.loads(b); assert isinstance(o, dict)
    except Exception: return D
    if o.get('mode') not in ('off', 'sbs', 'full_sbs', 'half_sbs', 'over_under', 'anaglyph', 'vr180'): return D
    v = dict(D, mode=o['mode'])
    for k, ok in (('depth_scale', lambda x: x >= 0), ('ipd_m', lambda x: x > 0), ('convergence_m', lambda x: x > 0)):
        x = o.get(k)
        if isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and ok(x): v[k] = float(x)
    return v
check('keys + defaults match the writer', all(k in sw and k in wr for k in ('"mode"', '"depth_scale"', '"ipd_m"', '"convergence_m"')) and 'ipdM = 0.063' in sw and 'ipdM: Double = 0.063' in wr)
check('reads only (no write APIs)', 'write(' not in sw and 'replaceItem' not in sw)
check('mtime-gated re-read', 'm != mtime' in sw)
check('absent/garbage -> defaults', parse(b'') == parse(b'x') == dict(mode='off', depth_scale=1.0, ipd_m=0.063, convergence_m=None))
check('bad mode -> all defaults', parse(b'{"mode":"x","ipd_m":0.07}')['ipd_m'] == 0.063)
p = parse(b'{"mode":"vr180","depth_scale":1.5,"ipd_m":0.065,"convergence_m":null}')
check('valid vr180 parsed, null convergence', p == dict(mode='vr180', depth_scale=1.5, ipd_m=0.065, convergence_m=None))
check('invalid ipd/scale keep defaults', parse(b'{"mode":"sbs","ipd_m":-1,"depth_scale":-2}') == dict(mode='sbs', depth_scale=1.0, ipd_m=0.063, convergence_m=None))
check('effective ipd = ipd*scale pinned', 'ipdM * depthScale' in sw)

# --- virtual screen (screen_deg): thetaH from canvas design, depth untouched
def theta_h(screen_deg, shot, aspect):
    if screen_deg <= 0 or not aspect > 0: return shot
    h = math.radians(min(max(screen_deg, 20.0), 150.0)); vmax = math.radians(150.0)
    return min(h, 2 * math.atan(math.tan(vmax / 2) * aspect))
check('screen_deg pins in Swift', all(p in sw for p in ('defaultScreenDeg = 75.0', 'o["screen_deg"]', 'maxVerticalDeg = 150.0', 'func thetaH(shotThetaH: Double, aspect: Double)')))
check('screen 75 deg, 16:9: thetaH = 75 deg', abs(theta_h(75.0, math.radians(51), 16 / 9) - math.radians(75)) < 1e-12)
check('screen_deg 0 = legacy shot fov', theta_h(0.0, math.radians(51), 16 / 9) == math.radians(51))
check('tall 1:1 screen at 150 deg is capped vertically (<=150 deg)', theta_h(150.0, 1.0, 1.0) <= math.radians(150.0) + 1e-12)
def lon_of(gx, w, f, z, eye):
    rx = (gx + .5 - w / 2) / f; return math.atan2(rx * z - eye, z)
w, z, eye = 1920, 3.0, 0.0315
fs = (w / 2) / math.tan(math.radians(51) / 2); fn = (w / 2) / math.tan(math.radians(75) / 2)
ext51 = 2 * (lon_of(w - .5, w, fs, z, 0.0))
ext75 = 2 * (lon_of(w - .5, w, fn, z, 0.0))
check('canvas share: shot fov 51 -> %.0f%% of 180, screen 75 -> %.0f%%' % (ext51 / math.pi * 100, ext75 / math.pi * 100), 0.28 < ext51 / math.pi < 0.29 and 0.41 < ext75 / math.pi < 0.42)
d = lambda f: lon_of(w / 2 - .5, w, f, z, -eye) - lon_of(w / 2 - .5, w, f, z, eye)
check('centre disparity at real depth is independent of screen size (depth not rescaled)', abs(d(fs) - d(fn)) < 1e-9 and abs(d(fn) - 2 * math.atan2(eye, z)) < 1e-6)
check('surround key pinned (default soft, off selectable)', all(x in sw for x in ('var surroundSoft = true', 'o["surround"] as? String', 'sv == "off" || sv == "soft"')))
print('render prefs reader: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
