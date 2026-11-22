"""Aspect/crop format cycle gate (owner, 2026-11-08: "add a shortcut to cycle between aspect ratio and crop
formats").

The cycle walks the shared VideoFormatCatalog list the two menus show: no
override first, then every format in menu order, then back to no override.
⌃⌥⌘A steps the aspect override, ⇧⌃⌥⌘A the crop.

Proofs:
1. Catalog parsed from the Swift source; a full simulated walk from "no
   override" visits every format exactly once, in menu order, then wraps.
2. Resume semantics (mirrored logic): an exact match (menu's own 0.005
   tolerance) continues after that format; a manual or fine-nudged value
   continues at the first wider format; past the widest it wraps to -1.
3. Source pins: the Swift implementation carries the exact branches the mirror
   simulates, both handlers wire state/OSD/wrap to the same sources the menu
   checkmarks read (currentAspectPreset / selectedMenuCropAspect), and the
   cycle item sits at the top of populateVideoFormats in both submenus.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / 'Sources/gor/UI/MenuActions.swift').read_text()
cycle = (lambda s:s.split('// BEGIN station-move VideoFormatCycle.swift\n',1)[1].split('// END station-move VideoFormatCycle.swift\n',1)[0])((ROOT / 'Sources/gor/UI/MenuActions.swift').read_text())   # the feature's owning file

# ── catalog from source ────────────────────────────────────────────────────
block = actions[actions.index('static let formats'):]
block = block[block.index('=[') + 2:block.index(']\n')]
formats = []
for title, ratio in re.findall(r'VideoFormat\(title:"([^"]+)",ratio:([^)]+)\)', block):
    formats.append((title, eval(ratio, {}, {})))   # numeric literals only (9.0/16, 1.37, 2)
assert len(formats) == 27 and formats[0][0] == '9:16' and formats[-1][0] == '8:1'
assert all(b[1] > a[1] for a, b in zip(formats, formats[1:])), 'catalog must stay ordered narrow to wide'


def next_index(current, formats):
    """Mirror of AppDelegate.VideoFormatCycle.nextIndex — keep in sync."""
    if not formats:
        return -1
    if current is None:
        return 0
    for i, (_, ratio) in enumerate(formats):
        if abs(ratio - current) < 0.005:
            return i + 1 if i + 1 < len(formats) else -1
    for i, (_, ratio) in enumerate(formats):
        if ratio > current:
            return i
    return -1


# ── 1. full walk: default -> every format in menu order -> default ─────────
walk, idx = [], None
while True:
    nxt = next_index(walk[-1][1] if walk else None, formats)
    if nxt == -1:
        break
    walk.append(formats[nxt])
assert [t for t, _ in walk] == [t for t, _ in formats], 'walk must visit the catalog in menu order'
assert len(walk) == len(formats), 'every format visited exactly once before wrap'

# ── 2. resume semantics ────────────────────────────────────────────────────
sixteen_nine = next(i for i, (t, _) in enumerate(formats) if t == '16:9')
r = 16.0 / 9
assert next_index(r, formats) == sixteen_nine + 1          # exact value continues
assert next_index(r + 0.004, formats) == sixteen_nine + 1  # within 0.005 still resumes here
assert next_index(r + 0.006, formats) == sixteen_nine + 1  # 1.783... first wider is 1.85
assert next_index(1.9, formats) == next(i for i, (t, _) in enumerate(formats) if t == '2:1')
assert next_index(8.5, formats) == -1                       # past the widest wraps
assert next_index(None, formats) == 0                       # no override starts at the top
assert next_index(None, []) == -1
last = next_index(formats[-1][1], formats)
assert last == -1                                           # widest wraps to no override

# ── 3. source pins: the Swift carries exactly these branches ───────────────
body = cycle[cycle.index('enum VideoFormatCycle'):]
body = body[:body.index('private func osdFormat')]
for pin in ['static func nextIndex(current: Double?, formats: [VideoFormat]) -> Int',
            'guard !formats.isEmpty else { return -1 }',
            'guard let current else { return 0 }',
            'abs(format.ratio - current) < 0.005',
            'return i + 1 < formats.count ? i + 1 : -1',
            'where format.ratio > current { return i }',
            'return -1']:
    assert pin in body, pin

# Handlers: state sources match the checkmarks (validateMenuItem reads the
# same currentAspectPreset / selectedMenuCropAspect), OSD on every step,
# wrap returns to default/off, crop success clears the stale aspect override.
aspect = cycle[cycle.index('@objc func menuCycleAspect()'):]
aspect = aspect[:aspect.index('@objc func menuCycleCrop()')]
assert 'if case .ratio(let value) = currentAspectPreset { current = value } else { current = nil }' in aspect
assert 'setAspect(.defaultAR)' in aspect and 'osdFormat("aspect: default")' in aspect
assert 'setAspect(.ratio(formats[next].ratio))' in aspect
assert 'osdFormat("aspect: \\(formats[next].title)")' in aspect

crop = cycle[cycle.index('@objc func menuCycleCrop()'):]
assert 'VideoFormatCycle.nextIndex(current: ctrl.selectedMenuCropAspect' in crop
assert 'ctrl.resetCrop()' in crop and 'osdFormat("crop: off")' in crop
assert 'ctrl.applyMenuCrop(aspect: formats[next].ratio)' in crop
assert 'setAspect(.defaultAR)' in crop
assert 'osdFormat("crop: \\(formats[next].title)")' in crop
assert 'osdFormat("crop unavailable' in crop   # a repeat chord never raises a modal

# OSD goes through mpv show-text, like the other toggles.
osd = cycle[cycle.index('private func osdFormat'):]
assert 'show-text' in osd.split('\n')[2]

# Menu wiring: the cycle item leads populateVideoFormats (both submenus),
# before reset; chords are ⌃⌥⌘A (aspect) and ⇧⌃⌥⌘A (crop).
pop = actions[actions.index('func populateVideoFormats'):]
cycle_pos = pop.index('item("cycle"')
reset_pos = pop.index('item("reset"')
assert cycle_pos < reset_pos
assert '#selector(menuCycleCrop) : #selector(menuCycleAspect)' in pop
assert 'mods:crop ? [.command, .control, .option, .shift] : [.command, .control, .option]' in pop

# The checkmark path and the cycle read the same crop state (no drift).
validate = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
assert 'active=controller?.selectedMenuCropAspect' in validate

print('PASS format cycle: catalog 27 formats parsed from source; walk = default -> menu order -> default;')
print('  resume: exact match continues, manual/nudged resumes at first wider, widest wraps;')
print('  Swift branches pinned 1:1, handlers wired to checkmark state + mpv OSD, cycle item leads both menus')
