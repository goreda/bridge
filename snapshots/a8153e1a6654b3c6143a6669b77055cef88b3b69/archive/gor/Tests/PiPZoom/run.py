"""Execute the shipped Lua 5.1 mode/motion callbacks, not a port of their policy."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
from lupa import lua51

root = Path(__file__).resolve().parents[2]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
props = {fullscreen=false, ["video-zoom"]=0, ["video-pan-x"]=0, ["video-pan-y"]=0, panscan=0}
handlers, observers, hooks, timers, writes = {}, {}, {}, {}, {}
clock = 0
mp = {msg={info=function()end, warn=function()end, verbose=function()end}}
mp.get_property = function(k) return props[k] end
mp.get_property_number = function(k, fallback) if props[k]==nil then return fallback end return props[k] end
mp.get_property_native = mp.get_property
mp.get_property_bool = function(k, fallback) if props[k]==nil then return fallback end return props[k] end
mp.get_opt = function() return nil end
mp.get_time = function() return clock end
mp.set_property = function(k,v)
  props[k]=v; writes[#writes+1]={k,v}
  if observers[k] then observers[k](k,v) end
end
mp.set_property_number = mp.set_property
mp.set_property_native = mp.set_property
mp.observe_property = function(k,t,f) observers[k]=f end
mp.register_script_message = function(k,f) handlers[k]=f end
mp.add_hook = function(k,priority,f) hooks[k..priority]=f end
mp.commandv = function() end
mp.add_periodic_timer = function(t,f)
  local timer={callback=f,active=true}
  timer.kill=function() timer.active=false end
  timers[#timers+1]=timer
  return timer
end
function tick(n)
 for i=1,n do
  clock=clock+1/60
  local count=#timers
  for j=1,count do if timers[j].active then timers[j].callback() end end
 end
end
''')
lua.execute((root / 'Resources/vendor/mpv/scripts/gor-fit.lua').read_text())
g = lua.globals()
count = 0
for zoom in [-1, -0.5, -0.1, 0, 0.5, 2]:
    for destination in ['window', 'fullscreen']:
        g.mp.set_property_number('video-zoom', zoom)
        g.mp.set_property_number('video-pan-x', 0.2)
        g.handlers['pip-mode']('yes')
        assert g.props['video-zoom'] == max(0, zoom)
        assert g.props['video-pan-x'] == 0.2
        g.handlers['pip-mode']('yes')
        g.tick(120)
        assert g.props['video-zoom'] == max(0, zoom), 'duplicate callback cannot overwrite suspended normal zoom'
        g.handlers['pip-mode']('no')
        assert g.props['video-zoom'] == zoom, destination
        g.tick(120)
        assert g.props['video-zoom'] == zoom, 'old timer cannot undo restored zoom'
        count += 1
# In-flight click target is retained, rather than a fractional spring sample.
g.mp.set_property_number('video-zoom', -0.2)
g.handlers.zoom('-1')
g.handlers['pip-mode']('yes')
assert g.props['video-zoom'] == 0
g.tick(120)
g.handlers['pip-mode']('no')
assert abs(g.props['video-zoom'] + 0.3) < 1e-9
# Active hold must not continue shrinking after transition.
g.handlers.hold('0', '0', '-1')
g.tick(4)
before = g.props['video-zoom']
g.handlers['pip-mode']('yes')
g.tick(120)
assert g.props['video-zoom'] == 0
g.handlers['pip-mode']('no')
assert g.props['video-zoom'] == before
# Manual reset in PiP discards the suspended normal value permanently.
g.handlers['pip-mode']('yes')
g.handlers.reset()
g.tick(120)
g.handlers['pip-mode']('no')
assert g.props['video-zoom'] == 0
# PiP negative writes and repeated click/hold inputs are clamped, normal state intact.
g.mp.set_property_number('video-zoom', -0.7)
g.handlers['pip-mode']('yes')
g.mp.set_property_number('video-zoom', -0.4)
for _ in range(8):
    g.handlers.zoom('-1')
    g.tick(12)
g.handlers.hold('0', '0', '-1')
g.tick(120)
assert g.props['video-zoom'] == 0
g.handlers['pip-mode']('no')
assert g.props['video-zoom'] == -0.7
# A newly loaded playback in PiP captures only that file's current zoom.
g.handlers['pip-mode']('yes')
g.mp.set_property_number('video-zoom', 0.4)
g.hooks.on_preloaded60()
g.handlers['pip-mode']('no')
assert g.props['video-zoom'] == 0.4
print(f'PASS actual Lua5.1: {count} signed-zoom normal/PiP/window/fullscreen-labelled round trips, duplicate receipts, active click/hold fencing, PiP no-shrink, reset invalidation, new-playback isolation; pan unchanged')
# Structural routing only: actual native mode receipt timing remains a Mac gate.
source = (_pp_split().path(root,'PPController.swift')).read_text()
a = source.index('    func synchronizeSubtitlePresentation(')
b = source.index('    private func acceptSubtitleScale', a)
assert source[a:b].index('"pip-mode"') < source[a:b].index('guard let scale=')
assert 'visiblePictureBounds=chromeBounds' in source
assert 'applyVideoFrame(bounds: bounds)' in source[source.index('private func acceptOsdDims'):source.index('private func runCropActions')]
print('PASS same effective displayed-mode receipt drives zoom; actual mpv property changes feed accepted OSD/one visible-picture authority, not a second frame calculator. Native pixels unverified.')
