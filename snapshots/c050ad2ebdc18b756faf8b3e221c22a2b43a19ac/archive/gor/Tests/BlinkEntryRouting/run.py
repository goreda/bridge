#!/usr/bin/env python3
"""191b B4/B5: blink and the old vr-tools entries route through the one keymap into the store. The pre-191b executed-body
routing (menuVRToggle/menuVRBlinkLog -> controller closures) was retired with those selectors (191b owner order);
AppKit/native acceptance stays with 191b-T on the owner's Mac."""
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
from pathlib import Path
root = Path(__file__).resolve().parents[2]
menu = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(root)).read_text())
km = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDKeymap.swift'+' '):_b.index('// END relocated '+'ThreeDKeymap.swift'+'\n')])((_threed_split().path(root)).read_text())
features = (_pp_split().path(root,'PPController_Features.swift')).read_text()
app = (root / 'Sources/gor/App/AppDelegate.swift').read_text()
ma = (root / 'Sources/gor/UI/MenuActions.swift').read_text()

# Blink: Shift+E sits once in the keymap table and dispatches the .blink effect toggle (read .bool, dispatch the negation).
assert 'Row(act: .blink,         chord: Chord("e", shift: true)' in km
assert 'case .blink:         store.dispatch(.setEffect(.blink, .bool(!boolOf(store.snapshot.effects[.blink]))))' in menu
assert 'i.state = Self.boolOf(s.effects[.blink]) ? .on : .off' in menu   # checkmark reads the store, only in validateMenuItem
print('PASS blink row is one keymap entry -> one store effect toggle; state check comes from the store snapshot')

# The old entry points are gone everywhere (no parallel path that could diverge from the menu).
for dead in ('menuVRBlinkLog', 'menuVRSwapEyes', 'menuHeadTracking', 'menuHeadRecenter', 'menuIPDPlus', 'menuIPDMinus', 'menuVRToggle', 'toggleFromKeyboard'):
    assert dead not in app and dead not in ma and dead not in features, dead
assert 'vrMenu' not in app and app.count('ThreeDMenu.shared.install(in: videoMenu)') == 1
print('PASS old vr-tools selectors and the extra menu are deleted; one install call remains')

# The keyboard path matches Shift+E through the same table (exact modifiers; nothing hand-codes blink any more).
assert 'ThreeDKeymap.match(charactersIgnoringModifiers:' in features and 'ThreeDMenu.dispatch(act)' in features
assert 'toggleBlinkLog()' not in features.split('func handleSpecialKeyCommands')[1].split('private func grainSizeTrimMessage')[0]
print('PASS Shift+E reaches the store only through ThreeDKeymap.match -> ThreeDMenu.dispatch')

print('UNVERIFIED native AppKit event delivery, camera permission/frames, blink recognition and rendered response; 191b-T owns Mac acceptance')
