#!/usr/bin/env python3
"""Execute shipped Lua with a small mp API double. Not an mpv or native app test."""
from pathlib import Path
import json, math, tempfile
from lupa import LuaRuntime
root=Path(__file__).resolve().parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''handlers={}; props={}; clock=0; timer=nil; mp={msg={info=function()end,warn=function()end,error=function()end}};
mp.get_property=function(k) return props[k] end
mp.get_property_number=mp.get_property
mp.get_property_native=mp.get_property
mp.set_property=function(k,v) props[k]=v end
mp.set_property_native=mp.set_property
mp.get_time=function() return clock end
mp.observe_property=function()end
mp.register_script_message=function(k,f) handlers[k]=f end
mp.add_periodic_timer=function(t,f) timer=f end
mp.commandv=function(...) local a={...}; if a[1]=='change-list' then props['opts']=a[4] end end
''')
g=lua.globals();p=g.props;h=g.handlers
with tempfile.TemporaryDirectory() as d:
 p['config-dir']=d;p['osd-width']=1400;p['keepaspect']=True
 lua.execute((root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
 def call(n,*v): h['vr180-look-'+n](*map(str,v))
 def orient(d='none',reason='fov-unavailable',scale=.1118,nudge=0,fov=135):
  call('set-orientation',0,0,fov,0,nudge,0,0,0,d,reason,scale)
  return json.loads(p['user-data/vr180-look/distance-trace'])
 def check(n,c):
  assert c,n
  print(n+' PASS')
 call('set-enabled','true');call('set-ipd-mm',0)
 first=json.loads(p['user-data/vr180-look/distance-trace']);call('set-ipd-mm',3);second=json.loads(p['user-data/vr180-look/distance-trace'])
 check('pre-camera-anatomical-dial',first['reason']=='no-input' and abs(second['s_total_mm']-first['s_total_mm'])<.001 and abs(second['ipd_eff_mm']-66)<.001)
 call('set-ipd-mm',0)
 t=orient();base=t['s_total_mm'];check('fallback',t['reason']=='fov-unavailable' and not t['capped'])
 call('set-ipd-mm',3)
 for scale in [.1118,.2,.05]:
  t=orient(scale=scale);check('mm-offset-'+str(scale),abs(t['offset_mm']-3)<.001 and abs(t['ipd_eff_mm']-66)<.001)
 t=orient();check('dial-not-screen-fallback',abs(t['s_total_mm']-base)<.001)
 for d in [800,500,400,300,200,40]:
  t=orient(d,'ok');half=t['eye_w_mm']/2
  opts=dict(x.split('=') for x in p['opts'].split(','));val=lambda k:float(next(v for n,v in opts.items() if n.endswith('/'+k)))
  excess=-.4*(math.tan(math.pi/4)/math.tan(math.radians(135)/2)-1)*.4
  actual=max(-.8,min(.8,excess+val('vr_base_ipd')+val('vr_ipd_nudge')))*half
  check('actual-render-input-'+str(d),abs(actual-t['s_total_mm'])<.001)
  demand=lambda s,dd:2*math.atan((t['ipd_eff_mm']+s)/(2*dd))
  met=demand(actual,d)<=demand(t['s_today_mm'],500)+1e-6
  check('cap-truth-'+str(d),met==t['cap_met'])
  if d==40:check('infeasible-honest',t['infeasible'] and not met and abs(t['s_requested_mm']-actual)>1)
 t=orient(300,'ok');cap=t['s_cap_mm'];call('set-ipd-mm',0);t=orient(300,'ok');check('dial-cap-delta',abs(cap-t['s_cap_mm']+1.2)<.001)
 g.clock=1;g.timer();t=json.loads(p['user-data/vr180-look/distance-trace']);check('hold-1s',t['reason']=='hold-last-d')
 g.clock=2.1;g.timer();t=json.loads(p['user-data/vr180-look/distance-trace']);check('hold-expiry',t['reason']=='no-face-hold-expired' and not t['capped'])
 t=orient(scale=0);check('screen-fallback',t['mm_per_px_src']=='macbook-227ppi')
 call('set-ipd-mm',3);p['osd-width']=0;g.timer();t=json.loads(p['user-data/vr180-look/distance-trace']);check('no-osd',t['reason']=='no-osd-size' and not t['applied'])
 print('Actual shipped Lua executed. mp API double only; no shader pixels, Swift, camera or app lifecycle coverage.')
