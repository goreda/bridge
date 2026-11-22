"""s36: suggested 3d mode from the existing projection state. Python model of ThreeDDefaultMode + text pins on the wiring. Linux only, Swift not compiled."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import re, sys
r = Path(__file__).resolve().parents[2]
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(r)).read_text()); menu = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(r)).read_text()); wire = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDWiring.swift'+' '):_b.index('// END relocated '+'ThreeDWiring.swift'+'\n')])((_threed_split().path(r)).read_text())
bad = 0
def check(n, ok):
    global bad
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: bad += 1
def pick(vr, flat): return 'vr180' if vr and not flat else 'full_sbs'
def suffix(mode, cur, sug): return ' (suggested)' if mode == sug and cur == 'off' else ''
check('model: headset projection -> vr180; flat stereo file or no vr shader -> full_sbs', pick(True, False) == 'vr180' and pick(True, True) == 'full_sbs' and pick(False, False) == 'full_sbs' and pick(False, True) == 'full_sbs')
check('model: only the suggested entry is marked, and only while 3d is off', suffix('vr180', 'off', 'vr180') == ' (suggested)' and suffix('full_sbs', 'off', 'vr180') == '' and suffix('vr180', 'vr180', 'vr180') == '')
check('swift mirrors the model', 'vrModeOn && !flatStereoFile ? "vr180" : "full_sbs"' in sw and 'mode == suggested && current == "off" ? " (suggested)" : ""' in sw)
check('menu: title suffix only, stored mode and default "off" untouched', 'var mode = "off"' in menu and 'ThreeDDefaultMode.suffix' in menu and 'settings.mode = ' not in menu.split('ThreeDDefaultMode.suffix')[0].split('func validateMenuItem')[1])
check('wiring reads the existing controller state (vrModeEnabled, isFlatStereoMode)', 'controller?.vrModeEnabled' in wire and 'controller?.isFlatStereoMode' in wire)
print('default mode: ' + ('all pins hold' if not bad else f'{bad} FAIL')); sys.exit(1 if bad else 0)
