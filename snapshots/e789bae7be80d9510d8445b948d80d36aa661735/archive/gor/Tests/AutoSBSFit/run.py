#!/usr/bin/env python3
"""Exercise actual Lua handlers/timer, not a reimplemented interpolation."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import tempfile
from lupa import LuaRuntime
r=Path(__file__).resolve().parents[2]
s=(r/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py').read_text()
# Reuse its boundary stubs, never its Python geometry model.
setup=s.split("l.execute('''",1)[1].split("''')",1)[0]
l=LuaRuntime(unpack_returned_tuples=True);l.execute(setup)
g=l.globals()
g.mp.get_property_number=l.eval('function(k,d) if props[k]==nil then return d end return props[k] end')
with tempfile.TemporaryDirectory() as d:
    g.props['config-dir']=d;g.props['osd-width']=960;g.props['osd-height']=600
    l.execute((r/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
    def route(name,*args):
        g.handlers['vr180-look-store-revision']('1','flat-2d3d','store-applier')
        g.handlers[name](*map(str,args),'1','store-applier')
    route('vr180-look-set-projection','flat-2d3d',1.777777)
    route('vr180-look-set-pack',3,1,.5,.6,1)
    route('vr180-look-set-enabled','true')
    g.props['video-zoom']=-.4;g.props['video-scale-x']=.8
    g.handlers['vr180-look-motion']('zoom','0','0','-2')
    def tick(t):
        g.clock=t
        # Only drive fit/held-key timer, not unrelated filesystem watchers.
        for i in range(1,len(g.timers)+1):
            # harness timers are safe at deterministic clock.
            g.timers[i]()
    g.handlers['vr180-look-smooth-fit']()
    assert g.props['video-zoom']==-.4
    tick(.15)
    assert abs(g.props['video-zoom']+.2)<1e-8
    assert abs(g.props['video-scale-x']-.9)<1e-8
    tick(.3)
    assert g.props['video-zoom']==0 and g.props['video-scale-x']==1
    # Off during animation cancels, raw state is restored and no late writes.
    g.props['video-zoom']=-.2;g.handlers['vr180-look-smooth-fit']();route('vr180-look-set-enabled','false')
    before=g.props['video-zoom'];tick(.7);assert g.props['video-zoom']==before
    print('PASS actual Lua smooth start/midpoint/endpoint and Off cancellation')
sw=(_pp_split().path(r,'PPController_Features.swift')).read_text()
assert 'fitEntry != autoFitEntry' in sw and 'recognitionGeneration)|' in sw
assert 'plan.filmSource.format == .flat2D' in sw
assert sw.index('resetFilmView(smooth:true)')>sw.index('appliedEffects=state.effects')
print('PASS identity/output dedupe, 2D-only SBS scope, after pack publication pins')
