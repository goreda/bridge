"""Subtitle position preset gate (owner, 2026-11-08: "add shift+1,2,3,4,5,6,7,8,9 individually to
subtitle position").

Nine evenly spaced sub-pos presets (10..90), each its own row in
subtitles > position with its own shift+digit chord. sub-pos is mpv's
0..100 vertical subtitle position (the existing move rows nudge it by 1;
100 is the default bottom), so 10..90 step 10 is the even spread inside
the reachable range; shift+0 stays random subtitle position.

Proofs:
1. The nine rows parse 1:1: title <-> chord <-> representedObject value.
2. The handler reads the row's Int and calls one absolute setter.
3. The setter uses the same set-then-read plumbing, mode-follow clearing
   and OSD as the existing delta path (adjustSubtitleProperty).
4. Chord shape: the key equivalent is the unshifted digit with .shift in
   the mask - AppKit matches the physical key, so the row fires on
   shift+<digit> regardless of the symbol the layout prints on it.
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
pp = (_pp_split().path(ROOT,'PPController.swift')).read_text()

# ── 1. rows: title <-> chord <-> value, evenly spaced ─────────────────────
rows = re.findall(r'let sp\d=item\("position (\d+)",action:#selector\(menuSubPosPreset\(_:\)\),'
                  r'key:"(\d)",mods:\.shift\);sp\d\.representedObject=(\d+)', app)
assert rows == [(str(v), str(d), str(v)) for d, v in enumerate(range(10, 91, 10), start=1)], rows
values = [int(v) for v, _, _ in rows]
assert values == sorted(values) and all(b - a == 10 for a, b in zip(values, values[1:])), 'even 10-step spread'
assert all(0 < v < 100 for v in values), 'inside the sub-pos 0..100 domain'

# ── 2. handler ─────────────────────────────────────────────────────────────
handler = actions[actions.index('@objc func menuSubPosPreset'):]
handler = handler[:handler.index('\n    }')]
assert 'guard let pos = sender.representedObject as? Int else { return }' in handler
assert 'controller?.setSubtitlePositionPreset(pos)' in handler

# ── 3. setter mirrors the delta path's plumbing ────────────────────────────
mq = (ROOT / 'Sources/gor/Player/PPControllerMenuQueries.swift').read_text()   # moved out of PPController (line ceiling)
setter = mq[mq.index('func setSubtitlePositionPreset'):]
setter = setter[:setter.index('\n    }')]
assert 'MPVCommand.make(["set_property","sub-pos",pos])' in setter
assert 'MPVCommand.make(["get_property","sub-pos"])' in setter          # read-back like the delta path
helper = mq[mq.index('func queryMenuPayload'):mq.index('func surfaceDrawableReceipt')]
assert re.search(r'queryMenuPayload\(payload(?:,requiringWriteSuccess:true)?\)', setter), 'actual helper call'
assert 'ipcClient.queryBatch(payload,timeout:0.3)' in helper
import subprocess, sys
_semantic = subprocess.run([sys.executable, str(ROOT/'Tests/ConsumerContracts/run.py'), 'subtitle'])
assert _semantic.returncode == 0, 'actual subtitle setter/query Swift execution did not pass'
_refusal = subprocess.run([sys.executable, str(ROOT/'Tests/ConsumerContracts/run.py'), 'subtitle_refusal'])
assert _refusal.returncode == 0, 'write-refusal plus finite OLD readback must be rejected, current product defect'
assert 'pendingSubtitleModePosition=nil' in setter                       # mode-follow state cleared
assert 'subtitleView.setSubtitlePosition(value,force:true)' in setter
assert 'showMPVOSD("subtitle position: "' in setter
assert 'spineUI.showMPVOSD("subtitle control unavailable"' in setter     # same failure answer

# ── 4. chord shape: unshifted digit + .shift mask ─────────────────────────
# (If a row ever carried the shifted symbol (!@#...) AppKit would never
# match it; the digit with .shift in the mask is the only correct form.)
for bad in re.findall(r'key:"([^"]+)"', app):
    assert bad not in '!@#$%^&*(', 'shifted symbol as key equivalent never fires: ' + bad
# The relative move rows and random stay untouched.
assert 'item("↑",       action: #selector(menuSubUp),       key: "r", mods: [])' in app
assert 'item("random subtitle position", action: #selector(menuSubRandomPos), key: "0", mods: [.shift])' in app

print('PASS subtitle position presets: nine rows position 10..90 <-> shift+1..9 <-> sub-pos 10..90,')
print('  absolute setter with read-back/OSD/mode-clear pinned, unshifted-digit chord shape enforced')
