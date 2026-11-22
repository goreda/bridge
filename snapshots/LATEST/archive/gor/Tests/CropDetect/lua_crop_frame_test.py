#!/usr/bin/env python3
"""Run the actual gor-fit Lua callback with fake mpv property/timer services."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
lua=shutil.which('lua') or shutil.which('texlua')
_rt=None
if lua is None:
    try:
        from lupa import LuaRuntime as _LR
        _rt=_LR()   # CI installs PythonLupa; the lupa Lua runtime runs the same callback
    except Exception:
        _rt=None
assert lua or _rt is not None,'Lua interpreter (lua/texlua binary or the lupa Python package) required for actual gor-fit crop-frame callback'
source=(root/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text()
pre=r'''
local handlers,observers,props,timers={},{},{['keepaspect-window']='yes'},0
mp={msg={info=function()end,warn=function()end},
 get_property=function(k)return props[k]end,
 get_property_native=function(k)return props[k]end,
 get_property_bool=function(k,d)if props[k]==nil then return d else return props[k]end end,
 get_property_number=function(k,d)return tonumber(props[k]) or d end,
 get_opt=function()return nil end,
 get_time=function()return 0 end,
 set_property=function(k,v)props[k]=v end,
 set_property_native=function(k,v)props[k]=v end,
 set_property_number=function(k,v)props[k]=v end,
 register_script_message=function(k,f)handlers[k]=f end,
 observe_property=function(k,t,f)observers[k]=f end,
 add_hook=function()end,
 add_periodic_timer=function()timers=timers+1;return {kill=function()end}end}
'''
post=r'''
assert(handlers['crop-frame'])
handlers['crop-frame']('800x425+50+50','moving')
assert(props.geometry=='800x425+50+50' and props['keepaspect-window']=='no' and timers==0)
props['video-params']={dw=1920,dh=1080}
observers['video-params']('video-params',props['video-params'])
assert(timers==0 and props.geometry=='800x425+50+50')
handlers['crop-frame']('800x400+100+100','done')
assert(props.geometry=='800x400+100+100' and props['keepaspect-window']=='yes' and timers==0)
handlers['crop-frame']('not geometry','moving');assert(props.geometry=='800x400+100+100')
props.fullscreen=true;handlers['crop-frame']('900x400+0+0','moving');assert(props.geometry=='800x400+100+100')
props.fullscreen=false;handlers['crop-frame']('800x420+50+50','moving')
handlers.cancel();assert(props['keepaspect-window']=='yes')
print('PASS actual gor-fit crop-frame: no independent timer, exact per-sample geometry, aspect unlock/restore, observer suppression, invalid/fullscreen/cancel')
'''
variants={'green':source,
 'red-no-geometry':source.replace('  apply_now(g)\n  if state == "done"','  -- no geometry\n  if state == "done"'),
 'red-no-aspect-restore':source.replace('if state == "done" then crop_owned = false; restore_kaw() end','if state == "done" then crop_owned = false end')}
def run_variant(name, src):
 if lua:
  p=Path(tempfile.mkdtemp())/'test.lua';p.write_text(src)
  v=subprocess.run([lua,str(p)],capture_output=True,text=True,timeout=10)
  return v.returncode, v.stdout, v.stderr
 import io, contextlib
 buf=io.StringIO()
 try:
  with contextlib.redirect_stdout(buf): _rt.execute(src)
  return 0, buf.getvalue(), ''
 except Exception as e:
  return 1, buf.getvalue(), str(e)
for name,s in variants.items():
 rc,out,err=run_variant(name, pre+s+post)
 if name=='green':assert rc==0,err+out;print(out.strip())
 else:assert rc!=0,'survived '+name;print('PASS actual Lua runtime RED: '+name)
