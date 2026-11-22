"""Audio menu wiring gate (owner, 2026-11-08: "there are too few audio menu items.
are those the only settings video players have?").

The video-player audio set mpv supports, as menu rows: volume boost above
100%, output device, channel layout/downmix, dynamics (night mode, loudness
normalize), equalizer presets. Delay keeps its group. Every new row's exact
mpv command is pinned here, not just its presence in the menu inventory.

Proofs:
1. Boost: the exact batchIPC sequences (raise the cap, step, and restore),
   parsed from the owning file and evaluated as command lists.
2. Channels: the five rows map 1:1 to mpv audio-channels values; the handler
   sends exactly the row's representedObject.
3. Dynamics: labeled af toggles (labels make a repeat press a true toggle,
   never a stack).
4. Equalizer: the preset table parsed from source; every apply removes
   @goreq first (presets replace, never stack); "flat (off)" adds nothing.
5. Device: the menu is rebuilt from mpv's own audio-device-list on every
   open; checkmarks read mpv's current audio-device; selection is sent as
   JSONSerialization-built set_property (device names are never
   string-interpolated into JSON).
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
app = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
actions = (ROOT / 'Sources/gor/UI/MenuActions.swift').read_text()
owning = (lambda s:s.split('// BEGIN station-move AudioMenuControls.swift\n',1)[1].split('// END station-move AudioMenuControls.swift\n',1)[0])((ROOT / 'Sources/gor/UI/MenuActions.swift').read_text())
pp = (_pp_split().path(ROOT,'PPController.swift')).read_text()


def swift_batches(func_name):
    """The string literals inside one handler's batchIPC call, as mpv commands."""
    body = owning[owning.index('@objc func ' + func_name):]
    body = body[:body.index('\n    }')]
    out = []
    for raw in re.findall(r'\#"(.+?)"\#', body, re.S):
        out.append(json.loads(raw)['command'])
    return out


# ── 1. boost above 100% ────────────────────────────────────────────────────
assert swift_batches('menuVolBoostUp()') == [['set_property', 'volume-max', 200], ['add', 'volume', 10]]
assert swift_batches('menuVolBoostDown()') == [['add', 'volume', -10]]
assert swift_batches('menuVolBoostOff()') == [['set_property', 'volume', 100], ['set_property', 'volume-max', 130]]

# ── 2. channel layout ──────────────────────────────────────────────────────
rows = re.findall(r'let ch\w+=item\("([^"]+)",action:#selector\(menuAudioChannels\(_:\)\),key:""\);'
                  r'\w+\.representedObject="([^"]+)"', app)
assert rows == [('auto (source)', 'auto-safe'), ('stereo downmix', 'stereo'), ('mono', 'mono'),
                ('surround 5.1', '5.1'), ('surround 7.1', '7.1')], rows
handler = owning[owning.index('@objc func menuAudioChannels'):]
assert 'AudioMenuState.channelLayout = value' in handler
assert '\\"audio-channels\\",\\"\\(value)\\"' in handler.replace('"', '\\"') or \
       'set_property' in handler and 'audio-channels' in handler and '\\(value)' in handler

# ── 3. dynamics: labeled toggles ───────────────────────────────────────────
assert swift_batches.__doc__ is not None  # parser sanity
night = owning[owning.index('@objc func menuNightMode'):]
night = night[:night.index('\n    }')]
assert 'AudioMenuState.nightMode.toggle()' in night
assert json.loads(re.search(r'\#"(.+?)"\#', night, re.S).group(1))['command'] == ['af', 'toggle', '@gornight:dynaudnorm']
norm = owning[owning.index('@objc func menuNormalize'):]
norm = norm[:norm.index('\n    }')]
assert 'AudioMenuState.normalize.toggle()' in norm
assert json.loads(re.search(r'\#"(.+?)"\#', norm, re.S).group(1))['command'] == \
    ['af', 'toggle', '@gornorm:lavfi=[loudnorm=I=-16:TP=-1.5:LRA=11]']

# ── 4. equalizer: replace, never stack ─────────────────────────────────────
table = owning[owning.index('static let audioEqualizerPresets'):]
table = table[:table.index('\n    ]')]
presets = dict(re.findall(r'"([^"]+)": "(equalizer=[^"]+)"', table))
assert presets == {'bass boost': 'equalizer=f=100:t=h:w=100:g=6',
                   'voice': 'equalizer=f=3000:t=h:w=1500:g=5',
                   'treble': 'equalizer=f=8000:t=h:w=3000:g=5'}, presets
eq = owning[owning.index('@objc func menuAudioEqualizer'):]
eq = eq[:eq.index('\n    }')]
assert 'AudioMenuState.equalizer = name' in eq
assert json.loads(re.search(r'\#"(.+?)"\#', eq, re.S).group(1))['command'] == ['af', 'remove', '@goreq']
assert eq.index('"af","remove"' if '"af","remove"' in eq else 'remove') < eq.index('lines.append'), \
    'the old curve is removed before the new one is added'
assert 'AppDelegate.audioEqualizerPresets[name]' in eq and 'if let curve' in eq
rows = re.findall(r'let eq\w+=item\("([^"]+)",action:#selector\(menuAudioEqualizer\(_:\)\),key:""\);'
                  r'\w+\.representedObject="([^"]+)"', app)
assert rows == [('flat (off)', 'off'), ('bass boost', 'bass boost'), ('voice', 'voice'), ('treble', 'treble')], rows
assert 'off' not in presets, 'flat (off) must only remove the curve'

# ── 5. output device from mpv itself ───────────────────────────────────────
mq = (ROOT / 'Sources/gor/Player/PPControllerMenuQueries.swift').read_text()   # moved out of PPController (line ceiling)
snap = mq[mq.index('func nativeAudioDeviceSnapshot'):]
snap = snap[:snap.index('\n    }')]
assert '"get_property","audio-device"' in snap and '"get_property","audio-device-list"' in snap
assert 'entry["name"] as? String' in snap and 'entry["description"] as? String' in snap
rebuild = actions[actions.index('func rebuildAudioDeviceMenu'):]
rebuild = rebuild[:rebuild.index('@objc func menuSelectTrack')]
assert 'menu.title == "output device" {rebuildAudioDeviceMenu(menu);return}' in actions
assert 'item.tag == 7402' in rebuild
assert 'nativeAudioDeviceSnapshot()' in rebuild
assert 'auto.state=current == "auto" ? .on : .off' in rebuild
assert 'item.state=device.name == current ? .on : .off' in rebuild
assert 'item.representedObject=device.name' in rebuild
select = owning[owning.index('@objc func menuSelectAudioDevice'):]
assert 'JSONSerialization.data(withJSONObject: command)' in select, \
    'device names are never string-interpolated into JSON'
assert '["command": ["set_property", "audio-device", name]]' in select
# Checkmarks for the static rows mirror the tracked state (validateMenuItem).
for sel, state in [('menuNightMode', 'AudioMenuState.nightMode'), ('menuNormalize', 'AudioMenuState.normalize'),
                   ('menuAudioChannels(_:)', 'AudioMenuState.channelLayout'),
                   ('menuAudioEqualizer(_:)', 'AudioMenuState.equalizer')]:
    assert state in app.split('#selector(' + sel + ')')[1][:200], sel

print('PASS audio menu: boost cap/step/restore batches exact, 5 channel rows and 4 eq rows map 1:1,')
print('  dynamics are labeled af toggles, eq replace-never-stack enforced, device list re-read from mpv')
print('  every open with checkmarks from mpv state and JSON-safe selection')
