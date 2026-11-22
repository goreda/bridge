#!/usr/bin/env python3
"""ThreeDPrepareLauncher: Python model of the pure decide() rule + text pins (Swift uncompiled, nothing run on a Mac)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
def sec(n):   # 195y: the satellite files are BEGIN/END relocated spans inside Sources/gor/gor/ThreeD.swift
    b = (_threed_split().path(root)).read_text()
    for tag in (' (195y owner-order 3D consolidation, behavior unchanged)', ' (195y G2, behavior unchanged)'):
        s = '// BEGIN relocated ' + n + '.swift' + tag + '\n'
        if s in b: return b[b.index(s) + len(s):b.index('// END relocated ' + n + '.swift\n')]
    raise KeyError(n)
sw = sec('ThreeDPrepareLauncher')
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def decide(mode, film, playhead, info, quality, reason, running, failed_for, has_runtime):
    wanted = mode != 'off' and reason is None and film is not None
    if running is not None: return 'stop' if (not wanted or film != running) else 'none'
    if not wanted: return 'none'
    if failed_for == film: return 'none'
    if not info or info[0] <= 0 or info[1] <= 0: return 'none'
    if not has_runtime: return 'report'
    return ('start', film, info[0], info[1], max(0, playhead or 0), quality)
I = (24.0, 1000)
check('off / no film / preflight reason: nothing starts', decide('off', 'a', 1, I, 'auto', None, None, None, True) == 'none' and decide('vr180', None, 1, I, 'auto', None, None, None, True) == 'none' and decide('vr180', 'a', 1, I, 'auto', 'no x265', None, None, True) == 'none')
check('on + film + info + runtime: start from the playhead', decide('vr180', 'a', 12.5, I, 'tier2', None, None, None, True) == ('start', 'a', 24.0, 1000, 12.5, 'tier2'))
check('no runtime: report, never start', decide('vr180', 'a', 1, I, 'auto', None, None, None, False) == 'report')
check('film change or mode off while running: stop', decide('vr180', 'b', 1, I, 'auto', None, 'a', None, True) == 'stop' and decide('off', 'a', 1, I, 'auto', None, 'a', None, True) == 'stop' and decide('vr180', 'a', 1, I, 'auto', None, 'a', None, True) == 'none')
check('failed film does not retry in a loop', decide('vr180', 'a', 1, I, 'auto', None, None, 'a', True) == 'none' and decide('vr180', 'b', 1, I, 'auto', None, None, 'a', True) != 'none')
check('unknown fps/frames: wait', decide('vr180', 'a', 1, None, 'auto', None, None, None, True) == 'none' and decide('vr180', 'a', 1, (0, 5), 'auto', None, None, None, True) == 'none')
check('spawn injected, runtime open; progress from render-ready.json n_shots/n_ready/n_failed', 'typealias Spawn' in sw and 'init(spawn: @escaping () -> Spawn?' in sw and 'let sp = spawn()' in sw and 'render-ready.json' in sw and '"n_ready"' in sw and '"n_failed"' in sw)
check('failure clears on film change or mode toggle (no loop), exit handled on main', 'failedFor = nil' in sw and 'DispatchQueue.main.async' in sw)
check('no player-socket words', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', sw, re.I))
sys.exit(1 if bad else 0)
