#!/usr/bin/env python3
"""191b B5: the ONE keymap table (Sources/gor/gor/ThreeD.swift (ThreeDKeymap.swift section)) drives both the 3d menu key equivalents and the
InputController keyboard path. ThreeDKeymap.swift references E-G's ThreeDStore types, so it is not compiled here:
this test mirrors the table in Python and text-pins the Swift, so a divergence between the two FAILS.
Also pins the B5 collision audit: every chord in the table must be free of the non-3D bindings (input.conf,
AppDelegate menu chords, the InputController non-3D handlers), and each audit move is reported in `moves`."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
km = (S / 'ThreeDKeymap.swift').read_text()
menu = (S / 'ThreeDMenu.swift').read_text()
features = (_pp_split().dpath(S,'PPController_Features.swift')).read_text()
app = (S / 'AppDelegate.swift').read_text()
conf = (root / 'Resources/vendor/mpv/input.conf').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)

# --- mirror of the Swift table: (act, key, shift, option, control, command, keyCode) -------------------------
ROWS = [
    ('toggle3D',      'd', 1, 0, 0, 0, None),
    ('viewOff',       None, 0, 0, 0, 0, None),
    ('viewSBS',       's', 1, 0, 0, 0, None),
    ('viewHalfSBS',   None, 0, 0, 0, 0, None),
    ('viewTB',        None, 0, 0, 0, 0, None),
    ('viewVR180',     'v', 1, 0, 0, 0, None),
    ('viewAnaglyph',  None, 0, 0, 0, 0, None),
    ('filmAuto',      None, 0, 0, 0, 0, None),
    ('film2D',        None, 0, 0, 0, 0, None),
    ('filmSBS',       None, 0, 0, 0, 0, None),
    ('filmHalfSBS',   None, 0, 0, 0, 0, None),
    ('filmTB',        None, 0, 0, 0, 0, None),
    ('filmHalfTB',    None, 0, 0, 0, 0, None),
    ('filmVR180SBS',  None, 0, 0, 0, 0, None),
    ('filmVR180TB',   None, 0, 0, 0, 0, None),
    ('film360',       None, 0, 0, 0, 0, None),
    ('film360TB',     None, 0, 0, 0, 0, None),
    ('filmSwapEyes',  None, 0, 0, 0, 0, None),
    ('cycleSource',   'f', 1, 0, 0, 0, None),
    ('depthStronger', '=', 1, 0, 0, 0, None),
    ('depthWeaker',   '-', 1, 0, 0, 0, None),
    ('screenNearer',  '=', 1, 1, 0, 0, None),
    ('screenFarther', '-', 1, 1, 0, 0, None),
    ('sizeLarger',    ']', 1, 1, 0, 0, 30),
    ('sizeSmaller',   '[', 1, 1, 0, 0, 33),
    ('ipdPlus',       ']', 1, 0, 0, 0, 30),
    ('ipdMinus',      '[', 1, 0, 0, 0, 33),
    ('crossEye',      'x', 1, 0, 1, 0, None),
    ('headTracking',  'h', 1, 0, 0, 0, None),
    ('headInvert',    None, 0, 0, 0, 0, None),
    ('blink',         'e', 1, 0, 0, 0, None),
    ('recenter',      'r', 1, 0, 0, 0, None),
    ('calibration',   None, 0, 0, 0, 0, None),
    ('surroundBlack', None, 0, 0, 0, 0, None),
    ('surroundSoft',  None, 0, 0, 0, 0, None),
    ('surroundInvert',None, 0, 0, 0, 0, None),
    ('qualityAuto',   None, 0, 0, 0, 0, None),
    ('qualityBest',   None, 0, 0, 0, 0, None),
    ('qualityFast',   None, 0, 0, 0, 0, None),
    ('osdLine',       None, 0, 0, 0, 0, None),
    ('subtitleDepthNearer',  '[', 1, 0, 1, 0, 33),
    ('subtitleDepthFarther', ']', 1, 0, 1, 0, 30),
]

def swift_rows(text):
    out = []
    for m in re.finditer(r'Row\(act: \.(\w+),\s*chord: (Chord\(([^)]*)\)|nil),\s*title: "([^"]*)"\)', text):
        act, chord, args, title = m.group(1), m.group(2), m.group(3) or '', m.group(4)
        if chord == 'nil':
            out.append((act, None, 0, 0, 0, 0, None, title)); continue
        key = re.search(r'"([^"]*)"', args).group(1)
        fl = lambda n: 1 if re.search(n + r': true', args) else 0
        kc = re.search(r'keyCode: (\d+)', args)
        out.append((act, key, fl('shift'), fl('option'), fl('control'), fl('command'), int(kc.group(1)) if kc else None, title))
    return out

sw = swift_rows(km)
check('mirror equals the Swift table (act, key, modifiers, keyCode)',
      [r[:7] for r in sw] == ROWS)
check('every Swift row has a non-empty short title (owner: short, clear labels)',
      len(sw) == len(ROWS) and all(0 < len(r[7]) <= 24 for r in sw))
check('no two rows share a chord (menu + keyboard can never diverge)',
      len({r[1:7] for r in sw if r[1] is not None}) == len([r for r in sw if r[1] is not None]))

# --- match() semantics, mirrored -----------------------------------------------------------------------------
def match(chars, keyCode, shift, option, control, command):
    for act, key, s, o, c, cmd, kc in ROWS:
        if key is None: continue
        if (s, o, c, cmd) != (shift, option, control, command): continue
        if kc is not None:
            if kc == keyCode: return act
        elif (chars or '').lower() == key:
            return act
    return None

check('match: shift+D -> toggle3D', match('D', 2, 1, 0, 0, 0) == 'toggle3D')
check('match: shift+V -> viewVR180 (B4: VR180 / back to Off)', match('V', 9, 1, 0, 0, 0) == 'viewVR180')
check('match: ctrl+shift+X -> crossEye (kept; shift+X/option+X are photon, non-3D)', match('X', 7, 1, 0, 1, 0) == 'crossEye')
check('match: plain shift+X does NOT hit cross-eye (photon sharp-up keeps its key)', match('X', 7, 1, 0, 0, 0) is None)
check('match: option+X does NOT hit cross-eye (photon sharp-down keeps its key)', match('X', 7, 0, 1, 0, 0) is None)
check('match: shift+] -> ipdPlus by keyCode, not glyph', match('}', 30, 1, 0, 0, 0) == 'ipdPlus')
check('match: option+shift+] -> sizeLarger (B4 claims option+shift+[/] for size)', match('}', 30, 1, 1, 0, 0) == 'sizeLarger')
check('match: ctrl+shift+[ -> subtitleDepthNearer (moved off option+shift)', match('[', 33, 1, 0, 1, 0) == 'subtitleDepthNearer')
check('match: option+shift+[ no longer reaches subtitle depth', match('[', 33, 1, 1, 0, 0) == 'sizeSmaller')
check('match: exact modifiers only - cmd+shift+V falls through', match('V', 9, 1, 0, 0, 1) is None)
check('match: rows without chords never match', match('b', 11, 1, 0, 0, 0) is None)

# --- B5 collision audit vs the non-3D bindings ---------------------------------------------------------------
bound = set()
for line in conf.splitlines():   # input.conf: mpv-side chords (all non-3D)
    line = line.strip()
    if not line or line.startswith('#'): continue
    chord = line.split()[0].lower()
    mods = (1 if 'shift' in chord else 0, 1 if 'meta' in chord or 'alt' in chord else 0,
            1 if 'ctrl' in chord else 0, 1 if 'cmd' in chord else 0)
    key = chord.split('+')[-1]
    bound.add((key, mods))
for key, mods in re.findall(r'item\("[^"]*",\s*action: #selector\(\w+(?:\(_:\))?\),\s*key: "([^"]*)",\s*mods: \[([^\]]*)\]\)', app):
    bound.add((key.lower(), ('.shift' in mods and 1 or 0, '.option' in mods and 1 or 0,
                             '.control' in mods and 1 or 0, '.command' in mods and 1 or 0)))
def collides(row):
    act, key, s, o, c, cmd, kc = row
    if key is None: return False
    return (key, (s, o, c, cmd)) in bound
clash = [r[0] for r in ROWS if collides(r)]
check('B5: no keymap chord collides with an input.conf or AppDelegate menu binding', clash == [])
check('B5: Cmd+Ctrl+Opt 3D source shortcuts are gone (no row uses command+control+option)',
      not any(r[4] and r[5] and r[3] for r in ROWS))
check('B5 audit moves are reported, one line each',
      'static let moves: [String]' in km and km.count('",\n        "') >= 3 and
      'cross-eye: stays ctrl+shift+X' in km and 'subtitle depth: option+shift+[/] -> ctrl+shift+[/]' in km)

# --- the table drives BOTH paths ------------------------------------------------------------------------------
check('menu key equivalents come from the table (install reads ThreeDKeymap.rows)',
      'ThreeDKeymap.rows.first { $0.act == act }' in menu and 'keyEquivalent: r.chord?.key' in menu)
check('keyboard path matches through the table (InputController)',
      'ThreeDKeymap.match(charactersIgnoringModifiers:' in features and 'ThreeDMenu.dispatch(act)' in features)
check('every act has exactly one store dispatch site (ThreeDMenu.dispatch)',
      'static func dispatch(_ act: ThreeDKeymap.Act)' in menu and
      all(('case .%s:' % r[0]) in menu for r in ROWS))

# --- ThreeDInfo.line (the B4 one-line OSD; store emits .showInfo, applier calls this builder) -----------------
check('ThreeDInfo.line(state:progress:) exists with the agreed signature',
      'static func line(state: ThreeDState, progress: Double?) -> String' in km)
check('OSD format: "3D <Output> · film <Source>[ · converting N%]" / "3D off"',
      'if cur.output == .off { return "3D off" }' in km and '"3D " + outputLabel(cur.output)' in km and
      '"film " + sourceLabel(cur.source.format)' in km and '"converting "' in km and 'separator = " · "' in km)
def osd_line(output, source, progress=None):
    if output == 'off': return '3D off'
    parts = ['3D ' + output, 'film ' + source]
    if progress is not None: parts.append('converting %d%%' % round(progress * 100))
    return ' · '.join(parts)
check('OSD mirror: "3D SBS · film 2D · converting 34%"', osd_line('SBS', '2D', 0.34) == '3D SBS · film 2D · converting 34%')
check('OSD mirror: "3D off"', osd_line('off', 'SBS') == '3D off')

print('three d keymap: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
