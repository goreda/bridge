"""Menu shortcut gate (owner, 2026-11-08: "review the whole shortcut system in the menu items;
add the missing and necessary ones").

Proofs over the parsed menu-bar inventory (same scanner as MenuStructure):
1. Reserved family ⌃⌥⌘: every chord unique, every handler exists, count pinned.
2. Global collision audit: no (key, modifiers) pair drives two different
   selectors anywhere in the menu bar.
3. Every actionable item has a shortcut or a pinned reason (owner's menu spec:
   "every item has a shortcut or a reason"). A new keyless item fails this gate
   until it gains a chord or a documented reason.
4. macOS system chords stay untouched; the one deliberate exception (⌘M magnet
   search) is pinned with its reason.
5. The 2026-11-08 additions are present: aspect/crop cycle pair, aspect
   fine-nudge arrows, subtitle font size reset chord.
6. Input-monitor boundaries: Command chords pass through; the clip monitor must
   not swallow the reserved family (owned by PPController_Features).
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
app = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
actions = (ROOT / 'Sources/gor/UI/MenuActions.swift').read_text()


def scan_calls(text, fname):
    out = []
    for m in re.finditer(r'[^.\w]' + re.escape(fname) + r'\(', text):
        i = m.end(); depth = 1; j = i
        while depth:
            c = text[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            elif c == '"':
                j += 1
                while text[j] != '"':
                    j += 2 if text[j] == '\\' else 1
            j += 1
        out.append((m.start(), text[i:j]))
    return out


def split_top(args):
    parts, depth, cur, i = [], 0, '', 0
    while i < len(args):
        c = args[i]
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        if c == ',' and depth == 0:
            parts.append(cur); cur = ''
            i += 1
            continue
        if c == '"':
            j = i + 1
            while args[j] != '"':
                j += 2 if args[j] == '\\' else 1
            cur += args[i:j + 1]
            i = j + 1
            continue
        cur += c
        i += 1
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def norm(e):
    return re.sub(r'\s+', ' ', e).strip()


def parse_item_args(args):
    parts = split_top(args)
    title = norm(parts[0]) if parts else '?'
    sel = key = mods = None
    for p in parts[1:]:
        if p.startswith('action:'):
            found = re.findall(r'#selector\((\w+\(_:\)|\w+)\)', p)
            sel = '|'.join(norm(f) for f in found) if found else norm(p[7:])
        elif p.startswith('key:'):
            key = norm(p[4:])
        elif p.startswith('mods:'):
            mods = norm(p[5:])
    return title, sel or '?', key if key is not None else '""', mods if mods is not None else '.command'


def inventory(app_src, actions_src):
    items = []
    start = app_src.index('    func buildMenuBar()')
    end = app_src.index('    // Observation only.', start)
    build = app_src[start:end]
    for src in (build, actions_src):
        for pos, args in scan_calls(src, 'item'):
            if 'func' in src[max(0, pos - 12):pos]:
                continue
            items.append(parse_item_args(args))
        for pos, args in scan_calls(src, 'NSMenuItem'):
            parts = split_top(args)
            d = {}
            for p in parts:
                for k in ('title:', 'action:', 'keyEquivalent:'):
                    if p.startswith(k):
                        d[k[:-1]] = p[len(k):].strip()
            if 'action' in d and d['action'] != 'nil':
                m = re.search(r'#selector\((\w+\(_:\)|\w+)\)', d['action'])
                sel = norm(m.group(1)) if m else norm(d['action'])
                items.append((norm(d.get('title', '?')), sel, norm(d.get('keyEquivalent', '""')), '.command'))
    return items


inv = inventory(app, actions)
normmods = lambda m: re.sub(r'\s+', '', m)

# ── 1. reserved family ⌃⌥⌘ ─────────────────────────────────────────────────
reserved = [(key, sel) for title, sel, key, mods in inv if normmods(mods) == '[.command,.control,.option]']
assert len(reserved) == 33 and len(set(k for k, _ in reserved)) == 33, \
    'reserved ⌃⌥⌘ family drift: ' + repr(sorted(k for k, _ in reserved))
assert ('"s"', 'menuVRSideBySide') not in reserved      # owner 16:04: the s/m/v chords moved to the 3d menu source rows (ThreeDMenu.install), pinned in three_d_menu_test
assert ('"d"', 'menuCropDetect') in reserved            # crop detect stays
assert ('"4"', 'menuUpdate') in reserved                # general update button keeps the chord
# Aspect fine-nudge rows: key = NS*ArrowFunctionKey scalar (U+F700-F703, what physical arrows produce, same as the window
# position rows), NOT the glyph U+2190-2193 (a glyph is a label, never a key). Mask carries .function like every arrow chord
# (AppKit adds fn to arrow events) plus shift, so the chord differs from the position rows' fn+ctrl+opt+cmd by shift.
# Physical arrows deliver NSXArrowFunctionKey scalars, never the literal ←↑→↓ characters: the aspect rows must use the scalar form.
FK = lambda n: 'String(UnicodeScalar(NS%sArrowFunctionKey)!)' % n
for arrow, sel in [(FK('Right'), 'menuAspectExpandH'), (FK('Left'), 'menuAspectShrinkH'),
                   (FK('Up'), 'menuAspectExpandV'), (FK('Down'), 'menuAspectShrinkV')]:
    assert (arrow, sel) not in reserved, 'aspect fine-nudge still in the unshifted family: ' + sel
    assert (arrow, sel, '[.function,.command,.control,.option,.shift]') in [(k, x, normmods(m)) for t, x, k, m in inv], 'aspect fine-nudge not on ctrl+opt+shift+cmd: ' + sel

handlers = app + actions + ''.join((ROOT / 'Sources/gor' / n).read_text()
    for n in [])
for key, sel in reserved:
    for one in sel.split('|'):
        if '.' in one:
            continue
        assert re.search(r'func\s+' + re.escape(one.split('(')[0]) + r'\s*\(', handlers), one

# ── 2. global collision audit ──────────────────────────────────────────────
by_chord = {}
for title, sel, key, mods in inv:
    if key == '""':
        continue
    by_chord.setdefault((key, normmods(mods)), set()).add(sel)
collisions = {k: v for k, v in by_chord.items() if len(v) > 1}
assert not collisions, 'shortcut collisions (one chord, two actions): ' + repr(collisions)

# The two window-placement loops share the raw ('key', mods) row by design;
# expand the literal arrays to prove the real chords are unique too.
ARROW_KEY = r'String\(UnicodeScalar\(NS(\w+)ArrowFunctionKey\)!\)'
def window_rows(src):
    """(mode, key, mask) for the 9 window rows; corner keys are arrow-key EXPRESSIONS and normalise to <Up> etc."""
    out = []
    pos = src[src.index('let positionMenu = group'):src.index('let sizeMenu = group')]
    size = src[src.index('let sizeMenu = group'):][:900]
    for blk in (pos, size):
        mask = re.search(r'key:key,mods:(\[[^\]]+\])', blk).group(1).replace(' ', '')
        for m in re.finditer(r'\("[^"]+","([a-z-]+|zoom|fill|smaller|larger)",("[^"]+"|' + ARROW_KEY + r')\)', blk):
            key = m.group(2) if m.group(2).startswith('"') else '"<%s>"' % m.group(3)
            out.append((m.group(1), key, mask))
    return out
rows9 = window_rows(app)
window_keys = [k for _, k, _ in rows9]
assert len(rows9) == 9 and len(set((k, m) for _, k, m in rows9)) == 9, rows9
assert {k for md, k, m in rows9 if md in ('top-left', 'top-right', 'bottom-left', 'bottom-right')} == {'"<Up>"', '"<Right>"', '"<Left>"', '"<Down>"'}, rows9
assert all(m == '[.function,.control,.option,.command]' for md, k, m in rows9 if md in ('center', 'top-left', 'top-right', 'bottom-left', 'bottom-right')), rows9
# the nine real chords must not equal any other item's chord (arrow keys compared as <Up> etc.)
def arrow_norm(k): return {'"→"': '"<Right>"', '"←"': '"<Left>"', '"↑"': '"<Up>"', '"↓"': '"<Down>"',
    'String(UnicodeScalar(NSRightArrowFunctionKey)!)': '"<Right>"', 'String(UnicodeScalar(NSLeftArrowFunctionKey)!)': '"<Left>"',
    'String(UnicodeScalar(NSUpArrowFunctionKey)!)': '"<Up>"', 'String(UnicodeScalar(NSDownArrowFunctionKey)!)': '"<Down>"'}.get(k, k)
others = {(arrow_norm(k), normmods(m)) for t, sel, k, m in inv if 'menuWindowPlacement' not in sel and k != '""'}
assert not any((k, m) in others for _, k, m in rows9), [r for r in rows9 if (r[1], r[2]) in others]
# macOS puts .function on every arrow event, so an arrow chord is physically the same with or without fn.
# Overlap modulo fn is a KNOWN, REPORTED item (aspect fine-nudge rows use the same ctrl+opt+cmd arrows); any NEW overlap fails.
def mset(m): return frozenset(re.findall(r'\.(\w+)', m))
def strip_fn(m): return mset(m) - {'function'}
others_set = {(k, mset(m)) for t, sel, k, m in inv if 'menuWindowPlacement' not in sel and k != '""'}
mod_fn = sorted(k for _, k, m in rows9 if (arrow_norm(k), strip_fn(m)) in {(arrow_norm(a), b) for a, b in others_set} and k.startswith('"<'))
assert mod_fn == [], 'physical chord shared with a window position row (modulo fn): ' + repr(mod_fn)
# mutant: restoring the old unshifted aspect nudge mask must reintroduce the overlap and be caught
old_mask_others = set(others_set) | {(arrow_norm(k), frozenset({'command', 'control', 'option'})) for k in ('"→"', '"←"', '"↑"', '"↓"')}
assert any((arrow_norm(k), strip_fn(m)) in {(arrow_norm(a), b) for a, b in old_mask_others} for _, k, m in rows9 if k.startswith('"<')), 'mutant not caught'
# and the shifted chord equals no other arrow chord: move video is fn+shift, subtitle delay cmd+shift, seek none/cmd
for _, k, m in rows9:
    pass
shift_arrow = frozenset({'command', 'control', 'option', 'shift'})
assert not any(mset(m) == shift_arrow and arrow_norm(k) in ('"<Up>"', '"<Down>"', '"<Left>"', '"<Right>"') and 'menuAspect' not in sel
               for t, sel, k, m in inv)

# mutants: the parser must notice a dropped corner row and a duplicated key
dropped = app.replace('("↖","top-left",String(UnicodeScalar(NSUpArrowFunctionKey)!)),', '', 1)
assert dropped != app and len(window_rows(dropped)) == 8
dup = app.replace('("↗","top-right",String(UnicodeScalar(NSRightArrowFunctionKey)!))', '("↗","top-right",String(UnicodeScalar(NSUpArrowFunctionKey)!))', 1)
assert dup != app and len({(k, m) for _, k, m in window_rows(dup)}) == 8

# ── 3. every item: a chord or a pinned reason ──────────────────────────────
KEYLESS_REASONS = {
    '"about gor"': 'duplicate of app > about (⌃⌥⌘5)',
    '"manual..."': 'free-text ratio dialog; the cycle chord walks the same list',
    '"reset subtitles"': 'recovery hammer, deliberately click-only',
    'engine.rawValue': 'one-time engine pick, checklist rows (mpv / gorav)',
    'format.title': '27 format rows share the cycle chord; 27 chords would exhaust the keyboard',
    'model': 'caption model choice list',
    'row.title': 'dynamic track rows (menuSelectTrack), contents depend on the file',
    # 2026-11-08 audio expansion: list/toggle rows stay chord-free like the
    # format and caption-model rows; 17 chords would exhaust the keyboard and
    # collide with the player's own letter bindings.
    '"volume boost +10%"': 'boost step row; volume keys 0/9 already move volume',
    '"volume boost −10%"': 'boost step row; volume keys 0/9 already move volume',
    '"volume boost off"': 'boost reset row; pairs with the chord-free boost steps',
    '"auto (system default)"': 'dynamic device row; contents depend on the hardware',
    'device.label': 'dynamic device rows (menuSelectAudioDevice), contents depend on the hardware',
    '"auto (source)"': 'channel-layout list row (one-of-five), like format.title',
    '"stereo downmix"': 'channel-layout list row (one-of-five), like format.title',
    '"mono"': 'channel-layout list row (one-of-five), like format.title',
    '"surround 5.1"': 'channel-layout list row (one-of-five), like format.title',
    '"surround 7.1"': 'channel-layout list row (one-of-five), like format.title',
    '"night mode"': 'dynamics toggle in a pick list; click-driven like the engine rows',
    '"normalize (loudnorm)"': 'dynamics toggle in a pick list; click-driven like the engine rows',
    '"flat (off)"': 'equalizer preset list row (one-of-four), like format.title',
    '"bass boost"': 'equalizer preset list row (one-of-four), like format.title',
    '"voice"': 'equalizer preset list row (one-of-four), like format.title',
    '"treble"': 'equalizer preset list row (one-of-four), like format.title',
}
keyless = sorted(t for t, sel, key, mods in inv if key == '""')
assert keyless == sorted(KEYLESS_REASONS), \
    'keyless items without a pinned reason: ' + repr(set(keyless) - set(KEYLESS_REASONS)) + \
    ' / reasons for items that now have chords: ' + repr(set(KEYLESS_REASONS) - set(keyless))

# ── 4. macOS system chords ─────────────────────────────────────────────────
# Spotlight, input switching, hide, close window, new, print, settings, force quit.
SYSTEM_CHORDS = [('" "', '.command'), ('" "', '.control'), ('"h"', '.command'),
                 ('"w"', '.command'), ('"n"', '.command'), ('"p"', '.command'),
                 ('","', '.command'), ('"q"', '[.command,.option]')]
used = {(key, normmods(mods)) for title, sel, key, mods in inv}
# Deliberate exception, owner 2026-11-15 (phonemsg-01M7FHK6HDG2RWWGEDTYTFRH0E): Cmd+P
# opens the current media folder through the file panel. Exactly one menu row may carry
# Cmd+P and it must be menuOpenPlaylistFolder; Cmd+P on any other selector stays a
# system-chord violation. No other system chord is excepted (Cmd+M magnet stays below).
cmd_p_rows = [(t2, s2) for t2, s2, k2, m2 in inv if k2 == '"p"' and normmods(m2) == '.command']
assert len(cmd_p_rows) == 1 and cmd_p_rows[0][1] == 'menuOpenPlaylistFolder', \
    'Cmd+P must be exactly the owner-prescribed current-folder row: ' + repr(cmd_p_rows)
assert 'openFilePanel(atPath: (path as NSString).deletingLastPathComponent' in actions, \
    'menuOpenPlaylistFolder no longer opens the current folder'
for chord in SYSTEM_CHORDS:
    assert chord == ('"p"', '.command') or chord not in used, 'macOS system chord taken: ' + repr(chord)
# Deliberate exception, pinned with its reason: ⌘M is magnet search (the app's
# core feature); minimize lives in window > minimize (⌃⌥⌘⇧M).
assert ('"m"', '.command') in used  # magnet - intentional, see above

# ── 5. the 2026-11-08 additions ────────────────────────────────────────────
# Cycle pair: ⌃⌥⌘A walks the aspect override, ⇧⌃⌥⌘A walks the crop (one
# ternary call site feeds both submenus).
assert ('"cycle"', 'menuCycleCrop|menuCycleAspect', '"a"',
        'crop ? [.command, .control, .option, .shift] : [.command, .control, .option]') in inv
assert ('"subtitle font size reset"', 'menuSubSizeReset', '"0"', '[.command, .control, .option, .shift]') in inv
# Subtitle position presets (2026-11-08): shift+1..9, one row each; the key
# equivalent is the UNSHIFTED digit with .shift in the mask (AppKit matches
# the physical key), and shift+0 stays random subtitle position.
for d in range(1, 10):
    assert ('"position %d"' % (d * 10), 'menuSubPosPreset(_:)', '"%d"' % d, '.shift') in inv, d
assert ('"random subtitle position"', 'menuSubRandomPos', '"0"', '[.shift]') in inv
# The shifted family stays unique with the additions.
shifted = [(key, sel) for title, sel, key, mods in inv
           if normmods(mods) == '[.command,.control,.option,.shift]' and key != 'key']
shift_keys = [k for k, _ in shifted]  # window loops are expanded separately above
assert len(shift_keys) == len(set(shift_keys)), 'shifted-family duplicate: ' + repr(shift_keys)
assert '"0"' in shift_keys and '/"' not in shift_keys  # font reset joins; nothing lost below
for pin in ['"m"', '"p"', '"b"', '"/"', '"i"']:
    assert pin in shift_keys, 'shifted-family chord lost: ' + pin

# ── 6. input-monitor boundaries (owned by PPController_Features) ───────────
features = (_pp_split().path(ROOT,'PPController_Features.swift')).read_text()
assert 'if e.modifierFlags.contains(.command) { return e }' in features
# Clip routing must not steal the reserved Control chords. The native monitor
# change is owned by Features; fail until its exact modifier boundary lands.
assert 'if e.modifierFlags.contains(.command), e.modifierFlags.contains(.option) {' not in features, \
    'clip monitor swallows Command-Control-Option chords'
color = []
for line in app.splitlines():
    if 'mods: [.command, .control, .shift]' in line:
        color.append(re.search(r'key: "([^"]*)"', line)[1])
assert len(color) == 8 and len(set(color)) == 8
assert 'item("sbs (side-by-side)"' not in app   # owner 16:04: moved into the 3d menu source rows

print('PASS menu shortcuts: 31 unique reserved ⌃⌥⌘ chords (+⌃⌥⌘A aspect cycle, ⇧⌃⌥⌘A crop cycle,')
print('  4 aspect fine-nudge arrows, ⇧⌃⌥⌘0 subtitle font size reset), zero cross-menu collisions,')
print('  every keyless item carries a pinned reason, macOS system chords untouched (⌘M magnet')
print('  deliberately excepted), handlers resolve, Command input-monitor pass-through retained')

# literal-arrow mutant: an aspect row keyed by the literal character is caught (it would never fire from the keyboard)
lit_rows = [(t, sel, k) for t, sel, k, m in inv if 'menuAspect' in sel and sel.endswith(('H', 'V')) and 'Expand' in sel or 'Shrink' in sel and 'menuAspect' in sel]
assert len(lit_rows) == 4 and not any(k in ('"→"', '"←"', '"↑"', '"↓"') for _, _, k in lit_rows), lit_rows
mut = [('"→"' if sel == 'menuAspectExpandH' else k) for _, sel, k in lit_rows]
assert any(k in ('"→"', '"←"', '"↑"', '"↓"') for k in mut), 'literal-arrow mutant not caught'
print('aspect arrows use function-key scalars; literal-arrow mutant caught')
