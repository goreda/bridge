#!/usr/bin/env python3
"""Run both shipped Lua scripts and their actual message routing. mp API double, not pixels/native."""
from pathlib import Path
from lupa import LuaRuntime
import tempfile, math
root=Path(__file__).resolve().parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''handlers={}; timers={}; props={}; clock=0; script=''; mp={msg={info=function()end,warn=function()end,error=function()end}}
mp.get_property=function(k) return props[k] end
mp.get_property_number=mp.get_property;mp.get_property_native=mp.get_property
mp.set_property=function(k,v) props[k]=v end
mp.set_property_number=mp.set_property;mp.set_property_native=mp.set_property
mp.get_time=function() return clock end
mp.register_script_message=function(k,f) handlers[script..':'..k]=f end
mp.add_periodic_timer=function(t,f) local v={f=f,alive=true};v.kill=function(self)self.alive=false end;timers[#timers+1]=v;return v end
mp.add_hook=function()end;mp.observe_property=function()end
mp.commandv=function(...)local a={...};if a[1]=='change-list' then props.opts=a[4] elseif a[1]=='script-message-to' then local f=handlers[a[2]..':'..a[3]];if f then f(table.unpack(a,4))end end end
function tick(dt) clock=clock+dt;for _,t in ipairs(timers)do if t.alive then t.f()end end end
''')
g=lua.globals();p=g.props
with tempfile.TemporaryDirectory() as d:
 p['config-dir']=d;p['osd-width']=1400;p['keepaspect']=True
 for name in ('vr180-look','gor-fit'):
  g.script=name.replace('-','_');lua.execute((root/'Resources/vendor/mpv/scripts'/f'{name}.lua').read_text())
 def call(script,name,*args):g.handlers[script+':'+name](*map(str,args))
 def orient():call('vr180_look','vr180-look-set-orientation',.01,.02,90,0,0,0,0,0,'none','fov-unavailable',.1118)
 def opts():return {k.split('/')[-1]:float(v) for k,v in (x.split('=') for x in p.opts.split(','))}
 def check(n,b):assert b,n;print(n+' PASS')
 call('vr180_look','vr180-look-set-enabled','true');orient();base=opts()
 for name,args,key in [('zoom',(1,),'vr_fov'),('move',(-1,0),'vr_yaw'),('move',(0,-1),'vr_pitch')]:
  call('gor_fit',name,*args);v=opts();check(name+'-changes-'+key,abs(v[key]-base[key])>.001)
  orient();check(name+'-survives-camera-frame',abs(opts()[key]-v[key])<1e-5)
 call('gor_fit','reset');check('reset-manual-only',all(abs(opts()[k]-base[k])<1e-5 for k in ('vr_yaw','vr_pitch','vr_fov')))
 call('gor_fit','hold',1,1,1)
 for i in range(8):g.tick(.05)
 v=opts();check('held-three-axes',all(abs(v[k]-base[k])>.001 for k in ('vr_yaw','vr_pitch','vr_fov')))
 call('gor_fit','hold',0,0,0);g.tick(.05);check('release-stops',opts()==v)
 call('gor_fit','hold',1,0,0);g.tick(.7);v=opts();g.tick(.1);check('watchdog-stops-lost-keyup',opts()==v)
 call('gor_fit','reset')
 call('vr180_look','vr180-look-set-projection','flat-sbs',16/9)
 check('flat-projection-selected',opts()['vr_flat_sbs']==1 and abs(opts()['vr_eye_aspect']-16/9)<1e-5)
 p['video-aspect-override']='3.0';orient()
 check('polyvision-per-eye-override',opts()['vr_aspect_override']==3)
 call('gor_fit','move',1,0);v=opts();orient()
 check('flat-manual-independent-camera',abs(opts()['vr_manual_yaw']-v['vr_manual_yaw'])<1e-5)
 p['video-aspect-override']='no';orient()
 check('default-clears-aspect-override',opts()['vr_aspect_override']==0)
 call('vr180_look','vr180-look-set-projection','vr180',0)
 check('next-file-projection-reset',opts()['vr_flat_sbs']==0)
 call('gor_fit','reset');call('vr180_look','vr180-look-set-enabled','false')
 p['video-zoom']=0;call('gor_fit','zoom',1)
 for i in range(60):g.tick(.02)
 check('non-VR-ordinary-zoom-unchanged',abs(p['video-zoom']-.1)<.001)
 print('Shipped Lua routing/offset tests only; no shader pixels, AppKit or native input acceptance.')
