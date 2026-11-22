#!/usr/bin/env python3
"""Exact production Lua dial, GS solver and strength receiver. Logic only, not GPU pixels."""
from pathlib import Path
from lupa import lua51
r=Path(__file__).resolve().parents[2]/'Resources/vendor/mpv/scripts'
g=(r/'photon-grain.lua').read_text();p=(r/'photon.lua').read_text()
def chunk(s,a,b): return s[s.index(a):s.index(b,s.index(a))]
# No separate test implementation of the dial, scene baseline or solver.
base=(chunk(g,'local function gr_scene_base_amount()','    -- TIER 1 — density:')+'end\n').replace('local function ', 'function ')
handler=chunk(g,'mp.register_script_message("photon-grain-set-amount",','-- Independent shadow/midtone/highlight')
receiver=chunk(g,'mp.register_script_message("photon-grain-set-strength-mult",','-- 133a epoch-gated proxy path')
blend=chunk(g,'gr_strength_blend_tick = function(now)','local function gr_strength_seek_prior(') if 'local function gr_strength_seek_prior(' in g else ''
solve=chunk(p,'function GS.solve_mult(','function GS.look_file()')
seed=chunk(p,'function GS.seed_look()','function GS.load_look()')
assert p.count('local adapt_t = gs_adapt(GR.amount_gpu)')==2
assert 'gs_adapt(math_max(GR.amount_gpu - GR.user_offset' not in p
setup='''
math_max,math_min=math.max,math.min
function clamp(v,a,b) return math.max(a,math.min(b,v)) end
GS={strength_default=6,accepted_strength=6.25,mult_floor=0,legacy_min=.4,legacy_max=1.25}
GRAIN_BASE_AMOUNT_MIN,GRAIN_BASE_AMOUNT_MAX=.55,1
GRAIN_OFFSET_STEP=.025;GRAIN_OFFSET_MIN,GRAIN_OFFSET_MAX=-1,10
GRAIN_AMOUNT_CLAMP_MIN,GRAIN_AMOUNT_CLAMP_MAX=0,10
GRAIN_STRENGTH_USER_DEFAULT=6;GRAIN_BASE_STRENGTH=6
GRAIN_STRENGTH_HINT_MAX=1.25
gr_user_offset=0;gr_amount=1;gr_amount_rendered=1
gr_control_revision=0;enabled=true;NOW=0
function gr_trace_control() gr_control_revision=gr_control_revision+1 end
function gr_push_params() end;function gr_publish_hud_state() end
function gr_doc_accept(gen,name) return gen=='1' and name=='test' end
function gr_str_log() end
common={trace_record=function() end}
messages={}
mp={register_script_message=function(k,f) messages[k]=f end,
 osd_message=function() end,msg={info=function() end},get_time=function() return NOW end}
'''
for adaptive in (False,True):
 for peak in (0,.25,.5,.75,1):
  for noise in (0,.1,1):
   for motion in (0,.2,1):
    l=lua51.LuaRuntime();l.execute(setup+base+solve+seed+handler+receiver)
    l.globals().gr_frame_peak=peak;l.globals().gr_noise_level=noise;l.globals().gr_motion_level=motion
    l.globals().gr_adaptive_mode=adaptive
    l.execute('gr_resolve_adaptive_params();gr_amount_rendered=gr_amount')
    start=l.eval('gr_amount');dial=l.eval('messages["photon-grain-set-amount"]');recv=l.eval('messages["photon-grain-set-strength-mult"]')
    # Fixed frame model, from clean to grainier-than-target. At current amount,
    # p5_sum and p5_tgt share the exact same basis, including user's dial.
    for source in (0,.05,.5,2):
     l.execute('gr_user_offset=0;gr_resolve_adaptive_params();gr_amount_rendered=gr_amount')
     for direction,limit in ((.5,0),(1.5,10),(.5,0)):
      prev=l.eval('gr_amount_rendered');prevamp=None
      for _ in range(405):
       dial(str(direction));amount=l.eval('gr_amount_rendered')
       delta=amount-prev
       assert abs(delta)<=.025+1e-10,(adaptive,peak,noise,motion,delta)
       assert delta<=1e-10 if direction<1 else delta>=-1e-10
       basis=amount*amount
       mult,_=l.eval('GS.solve_mult')(basis,basis,source,1,adaptive)
       if mult is not None:
        recv(str(mult),'1','test',str(source),'1','5','0',str(l.eval('gr_control_revision')))
       amp=amount*l.eval('GRAIN_BASE_STRENGTH')
       # Restoring amount cannot be cancelled by an inverse GS strength boost.
       if prevamp is not None:
        assert amp<=prevamp+1e-8 if direction<1 else amp>=prevamp-1e-8,(amount,amp,prevamp)
       prevamp=amp;prev=amount
       if abs(amount-limit)<1e-10: break
      assert abs(amount-limit)<1e-10,(amount,limit)
      dial(str(direction));assert abs(l.eval('gr_amount_rendered')-limit)<1e-10
     # From the exact floor, the very next up press must give a fine nonzero step.
     dial('1.5');assert abs(l.eval('gr_amount_rendered')-.025)<1e-10
    # Compatibility toggle, separate from ordinary up/down presses.
    dial('1');assert l.eval('gr_amount_rendered')==0
    dial('1');assert abs(l.eval('gr_amount_rendered')-start)<1e-10
    old=l.eval('GRAIN_BASE_STRENGTH');recv('2','0','test','0','1','5','0','0')
    assert l.eval('GRAIN_BASE_STRENGTH')==old # stale document remains rejected
print('PASS exact dial+GS+receiver sweeps: 90 scene/mode combinations x4 source powers, floor/ceiling saturation, immediate .025 restart, monotonic settled amplitude, no auto compensation, stale document rejected')
# Offset0 keeps identical production target algebra; defaults remain untouched.
assert 'local GRAIN_BASE_STRENGTH    =  6.00' in g
assert 'accepted_strength = 6.25' in p
assert 'local hint = 1.0 + (GRAIN_STRENGTH_HINT_MAX - 1.0) * norm' in g
print('PASS offset0 basis identical, factory6 / GS6.25 / seed1..1.25 unchanged; native visual acceptance NOT_RUN')
