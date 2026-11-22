from pathlib import Path
import tempfile
from lupa import LuaRuntime
r=Path(__file__).resolve().parents[2]
l=LuaRuntime(unpack_returned_tuples=True)
l.execute('''props={pause=false};handlers={};observers={};timers={};clock=0;writes={};mp={msg={info=function()end,warn=function()end,error=function()end}}
mp.get_property=function(k)return props[k]end;mp.get_property_number=mp.get_property;mp.get_property_native=mp.get_property
mp.set_property=function(k,v)props[k]=v;if k=="pause" then writes[#writes+1]=v;if observers[k] then observers[k](k,v)end end end;mp.set_property_number=mp.set_property;mp.set_property_native=mp.set_property
mp.get_time=function()return clock end;mp.register_script_message=function(k,f)handlers[k]=f end
mp.add_periodic_timer=function(t,f)timers[#timers+1]=f;return {kill=function()end}end;mp.add_hook=function()end
mp.observe_property=function(k,t,f)observers[k]=f end;mp.commandv=function(...)return true end
''')
g=l.globals()
with tempfile.TemporaryDirectory() as d:
 g.props['config-dir']=d;g.props['osd-width']=960;l.execute((r/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
 def msg(*args):g.handlers[args[0]](*map(str,args[1:]))
 def sample(t,left=1,right=1,uncertain='false'):g.clock=t;msg('vr180-look-set-lids',left,right,uncertain)
 def reset(paused=False):msg('vr180-look-manual-playback');g.props.pause=paused;l.execute('writes={}')
 msg('vr180-look-set-enabled','true')
 for left,right in [(1,1),(1,0),(0,1)]:
  for i in range(150):sample(i/30,left,right)
 assert len(g.writes)==0
 print('PASS actual Lua: bilateral holds and unilateral holds never write pause; gesture ownership is Swift only')
 msg('vr180-look-set-enabled','false');msg('vr180-look-set-enabled','true')
 for i in range(150):sample(10+i/30)
 assert len(g.writes)==0
 print('PASS mode re-entry does not restore a removed hold-pause action')
