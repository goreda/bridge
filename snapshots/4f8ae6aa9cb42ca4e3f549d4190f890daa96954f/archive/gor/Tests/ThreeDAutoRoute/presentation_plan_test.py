#!/usr/bin/env python3
"""191o T1-T6/T8/T9 source-level pins for the pure presentation plan.

The executable Swift coverage lives in Tests/ThreeDState; this file keeps the
Linux gate honest where no Swift toolchain exists. It reads the production
sources and fails on the exact 191o fault patterns.
"""
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
import os, re, sys

ROOT = Path(os.environ.get('GOR_ROOT', Path(__file__).resolve().parents[2]))
state = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDState.swift'+' '):_b.index('// END relocated '+'ThreeDState.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
pp = (_pp_split().path(ROOT,'PPController_Features.swift')).read_text()
coordinator = (lambda _b: _b[_b.index('// BEGIN relocated ThreeDRenderCoordinator.swift '):_b.index('// END relocated ThreeDRenderCoordinator.swift\n')])((_threed_split().path(ROOT)).read_text())
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + ((' ' + detail) if detail else ''))
    if not ok: fails.append(name)

def has(pattern, text=state):
    return re.search(pattern, text, re.S) is not None

check('T1 pure ThreeDPresentationPlan.make(state) exists',
      has(r'struct\s+ThreeDPresentationPlan\b.*static\s+func\s+make\(state:\s*ThreeDState\)'))
check('T1 film source ignores renderedSource',
      has(r'resolvedSource\s*=\s*current\.source\.format\s*==\s*\.auto\s*\?\s*detected\s*:\s*current\.source') and has(r'filmSource\s*=\s*resolvedSource') and
      not has(r'desired\.source\s*=\s*state\.presentationSource', pp))
check('T1 engine resolves film source and current output',
      has(r'ThreeDEngine\.resolve\(source:\s*filmSource\s*,\s*output:\s*current\.output\)'))
check('T1 flat SBS preview plan uses pack 3', has(r'pack\s*=\s*\(engine\s*==\s*\.nativeVR180\s*\|\|\s*output\s*==\s*\.off\)\s*\?\s*0\s*:\s*3'))

check('T2 non-VR stored lastOutput vr180 restores sbs',
      has(r'static\s+func\s+restoredOutput[\s\S]*stored\s*==\s*\.vr180\s*&&\s*!nativeVR180[\s\S]*return\s+\.sbs'))
check('T2 toggle3D uses the sanitized flat restore output',
      has(r'case\s+\.toggle3D:.*restoredOutput', state))
check('T2 plan helper uses FilmThreeD.lastOutput through current',
      'state.current.lastOutput' in state and 'state.lastOutput' not in state)
check('owner regression: opening rebuilds inferred source and sanitizes flat VR180 restore',
      'film.userSource != true' in state and 'film.source = evidenceSource' in state and
      'if !nativeVR180 && film.output == .vr180 && film.explicitOutput != .vr180 {film.output = .sbs}' in state and
      'next.films[id.rawValue] = opening(saved:' in state)
check('reapply forces projection/output resend without discarding applied route',
      'effects.contains(.reapply)' in state and 'let forceReapply=effects.contains(.reapply)' in pp and 'if forceReapply {projectionKey=""}' in pp and 'let presentationChanged=forceReapply || routeChanged' in pp)
check('F3 flat explicit VR180 never teaches lastOutput',
      has(r'output\s*!=\s*\.off\s*&&\s*\(output\s*!=\s*\.vr180\s*\|\|\s*nativeVR180\)'))

check('T3 generated carries plan output', has(r'case\s+generated\(FilmID,\s*ThreeDSource,\s*ThreeDOutput,\s*aspect:Double'))
check('T3 generated is ignored unless plan output equals current output',
      has(r'case\s+let\s+\.generated\(parent,\s*source,\s*planOutput,\s*aspect\).*planOutput\s*==\s*next\.current\.output'))
check('T3 2D View VR180 generated shot stays twoDVR180, never native',
      has(r'engine\s*=\s*ThreeDEngine\.resolve\(source:filmSource,output:current\.output\)') and
      'engine == .twoDVR180 ? "full_sbs"' in pp and
      not has(r'if\s+engine\s*==\s*\.nativeVR180\s*\{desired\.output\s*=\s*\.vr180\}', pp))
check('T3 interim TWO_D_VR180 ignores a generated VR180 Lua kind',
      has(r'renderedApplies\s*=\s*state\.renderedOutput\s*==\s*output\s*&&\s*engine\s*!=\s*\.twoDVR180'))
check('T3 ignored generated shot keeps the measured 2D aspect',
      has(r'luaAspect:\s*renderedApplies\s*\?\s*\(state\.renderedAspect\s*\?\?\s*0\):0'))

check('T4 explicit output change clears renderedSource', has(r'case\s+let\s+\.setOutput\(output\):[\s\S]{0,500}?next\.renderedSource\s*=\s*nil') and not has(r'case\s+let\s+\.setOutput\(output\):[\s\S]{0,500}?if\s+output\s*==\s*\.off\s*\{next\.renderedSource\s*=\s*nil\}'))
check('T4 rendered shot changes only Lua projection while output matches',
      has(r'renderedApplies\s*=\s*state\.renderedOutput\s*==\s*output[\s\S]{0,200}?luaSource\s*=\s*renderedApplies'))
check('T5 toggle3D clears renderedSource on every output change',
      has(r'case\s+\.toggle3D:[\s\S]{0,200}?film\.output\s*=\s*[^\n]+\n\s*next\.renderedSource\s*=\s*nil'))
check('T5 Off plan disables VR and pack', has(r'output\s*==\s*\.off\)\s*\?\s*0\s*:\s*3[\s\S]{0,300}?vrEnabled:\s*output\s*!=\s*\.off'))

check('T6 Swift native VR180 SBS and TB force pack 0',
      has(r'engine\s*==\s*\.nativeVR180\s*\|\|\s*output\s*==\s*\.off\)\s*\?\s*0'))
check('T6 native Off stays Off and disables VR',
      has(r'if\s+output\s*==\s*\.off\s*\{return\s+\.flat\(\.off\)\}') and has(r'let\s+output\s*=\s*current\.output'))
check('T6 native strength/IPD/head changes keep pack 0',
      has(r'publishThreeDAppliedState', pp) and '\\(plan.pack)' in pp and 'plan.engine.rawValue' in pp)
check('T9 native VR180 on a file resolves native',
      has(r'\.vr180SBS,\s*\.vr180TB.*nativeVR180'))

check('T8 store queues re-entrant dispatch and drains final state',
      has(r'isDispatching') and has(r'pendingActions') and has(r'while\s+index\s*<\s*queued\.count'))
check('T8 explicit same-output actions re-present instead of latching',
      has(r'effects\.contains\(\.reapply\)\s*\|\|\s*opening'))
check('T4 original return re-applies a route-only plan change',
      'private var appliedPlan:ThreeDPresentationPlan?' in pp and
      'let planChanged=plan != appliedPlan' in pp and
      'let routeChanged=desired != appliedThreeD || planChanged' in pp and
      'appliedPlan=plan' in pp)

check('F6 interim twoDVR180 uses flat virtual screen, not equirect pack 4',
      'engine == .twoDVR180 ? "full_sbs"' in pp and
      'if prefs.mode == "vr180"' in coordinator and
      has(r'pack\s*=\s*\(engine\s*==\s*\.nativeVR180\s*\|\|\s*output\s*==\s*\.off\)\s*\?\s*0\s*:\s*3'))

check('capture 035341: native projection has a per-opening memory',
      'private var openingProjection: String?' in pp)
check('capture 035341: later stereo-only video params keep opening native projection',
      'openingProjection = ThreeDProjectionMemory.resolve(current: openingProjection, evidence: evidence.projection, probe: probeProjection)' in pp and 'let projection = openingProjection' in pp)
check('recognition memory resets only when the film changes',
      len(re.findall(r'openingProjection\s*=\s*nil',pp)) >= 2 and 'recognitionPath = filename' in pp)
check('projection merge keeps spherical verdicts above generic flat layouts',
      'isProbeVerdict' in state and 'isGenericFlat' in state and 'isSpherical' in state and 'evidence ?? probe ?? current' in state)

print('presentation plan pins: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
