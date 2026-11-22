#!/usr/bin/env python3
"""s36 player-side pins: half_sbs eye aspect reaches the look shader intact, anaglyph turns the look shader off, the plan's look is re-asserted after load.
Python model + text pins on uncompiled Swift/Lua; nothing run on a Mac."""
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
lua = (root / 'Resources/vendor/mpv/scripts/vr180-look.lua').read_text(); mpv = (lambda _b: _b[_b.index('// BEGIN relocated '+'RenderedShotMPV.swift'+' '):_b.index('// END relocated '+'RenderedShotMPV.swift'+'\n')])((_threed_split().path(root)).read_text())
pl = (lambda _b: _b[_b.index('// BEGIN relocated '+'RenderedShotPlan.swift'+' '):_b.index('// END relocated '+'RenderedShotPlan.swift'+'\n')])((_threed_split().path(root)).read_text()); co = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(root)).read_text()); om = (lambda _b: _b[_b.index('// BEGIN relocated '+'OutputModes.swift'+' '):_b.index('// END relocated '+'OutputModes.swift'+'\n')])((_threed_split().path(root)).read_text())
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
# model of the aspect the shader uses (vr180-look.lua line: source_aspect = override>0 ? override : vr_eye_aspect; fallback = HOOKED half width / height)
def shader_aspect(eye, override, tex_w, tex_h, mono=False): return override if override > 0 else (eye if eye > 0 else tex_w * (1 if mono else .5) / tex_h)
W, H = 1920, 1080
check('model: half_sbs packed file is W x H; with the plan eye aspect W/H the shader shows 16:9, the fallback (aspect 0) would show half-width 8:9', abs(shader_aspect(W / H, 0, W, H) - 16 / 9) < 1e-9 and abs(shader_aspect(0, 0, W, H) - 8 / 9) < 1e-9)
check('lua: set-projection stores the aspect arg into flat_eye_aspect and pushes it as vr_eye_aspect; shader prefers override, then eye aspect', 'flat_eye_aspect = math.max(0, tonumber(aspect) or 0)' in lua and 'vr_eye_aspect=%.6f' in lua and 'float source_aspect = vr_aspect_override > 0.0 ? vr_aspect_override : vr_eye_aspect;' in lua)
check('Swift: the plan sends srcW/srcH (full eye aspect) for full_sbs AND half_sbs, srcW/srcH for over_under; vr180 sends 0', 'case .fullSBS, .halfSBS: return ("flat-sbs", a); case .overUnder: return ("flat-tb", a)' in pl and 'let a = srcH > 0 ? Double(srcW) / Double(srcH) : 0' in pl)
check('half_sbs SAR stretch is NOT applied in the shader path (the eye aspect already carries the 2:1 un-squeeze; a second stretch would double it)', 'playbackSARStretch' not in mpv and 'playbackSARStretch' not in co and 'video-aspect-override' not in mpv)
check('anaglyph route is data only; applier owns disabling the look', 'plan.output == .anaglyph ? .flat2D' in mpv and 'vr180-look-set-enabled' not in mpv)
check('anaglyph has no projection and no stereo-mode tag (nothing for the player auto-detect to pick up)', 'case .anaglyph: return nil' in pl and 'case .anaglyph: return nil' in om)
check('coordinator publishes planned look data to store after load, with aspect', 'let look=RenderedShotMPV.plannedLook(plan:plan)' in co and 'send(cmd); showing = hit.shot' in co and '.generated(id,look.source,look.output,aspect:look.aspect)' in co and 'send(message)' not in co)
check('no player-socket words in new lines', not any(re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', l, 2) for l in (co + mpv).split('\n') if 'look' in l or 'anaglyph' in l))
sys.exit(1 if bad else 0)
