#!/usr/bin/env python3
"""Swift FilmPrepareStatus must format exactly like PrepareFilm.status() (source pins + Python reference). Swift uncompiled."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'FilmPrepareStatus.swift'+' '):_b.index('// END relocated '+'FilmPrepareStatus.swift'+'\n')])((_threed_split().path(root)).read_text())
py = (root/'tools/depth_analysis/prepare_film.py').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('python format string', 'f"3D prepared: {prepared}/{n_frames} frames"' in py and '"3D prepared: full film"' in py)
check('swift format strings identical', '"3D prepared: \\(prepared)/\\(total) frames"' in sw and '"3D prepared: full film"' in sw)
check('swift condition matches (prepared < total)', 'prepared < total ?' in sw and 'prepared < n_frames' in py)
check('inclusive range sum', '$1[1] - $1[0] + 1' in sw and 'b - a + 1' in py)
check('pointer keys', all(k in sw for k in ('current-film.json','progress_path','n_frames','prepared')))
def ref(ranges, n):
    p = sum(b-a+1 for a, b in ranges); return f"3D prepared: {p}/{n} frames" if p < n else "3D prepared: full film"
check('reference examples', ref([[0,15]],32) == '3D prepared: 16/32 frames' and ref([[0,31]],32) == '3D prepared: full film')
pp = (_pp_split().path(root,'PPController.swift')).read_text()
contract = (root/'tools/depth_analysis/CONTRACT-190v.md').read_text()
check('cache root is Application Support/gor/depth-cache', 'appendingPathComponent("gor/depth-cache"' in sw and 'applicationSupportDirectory' in sw)
check('render-prefs.json path + atomic replace', 'render-prefs.json' in sw and 'replaceItemAt' in sw and 'render-prefs.json' in contract)
check('render-prefs keys match contract', all(k in sw for k in ('"mode"','"depth_scale"','"ipd_m"','"convergence_m"')) and all(k in contract for k in ('"mode"','"depth_scale"','"ipd_m"','"convergence_m"')))
check('modes match contract', 'modes = ["off", "sbs", "full_sbs", "half_sbs", "over_under", "anaglyph", "vr180"]' in sw and '"off" | "sbs" | "vr180"' in contract and 'full_sbs' in contract)
check('defaults match contract (1.0, 0.063, null)', 'depthScale: Double = 1.0' in sw and 'ipdM: Double = 0.063' in sw and 'convergenceM: Double? = nil' in sw)
check('OSD goes through mpv show-text and only on change', 'showCropDetectOSD(t)' in pp and 'show-text' in pp and 't != self.lastShown' in sw)
check('OSD started once from PPController, file stays net 0 lines', 'FilmPrepareOSD.shared.start' in pp and len(pp.splitlines()) <= 6234)
check('app never writes the analysis cache', 'current-film.json' in sw and 'progress.json' in sw and 'write(to' not in sw.split('enum RenderPrefs')[0])
sys.exit(1 if fails else 0)

sw2 = sw
check('render-prefs writer: optional screen_deg, 0 or 20...150 else refuse, key omitted when nil', 'screenDeg: Double? = nil' in sw2 and 'o["screen_deg"] = d' in sw2 and 'd >= 20 && d <= 150' in sw2)
