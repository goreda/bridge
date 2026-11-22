#!/usr/bin/env python3
"""Runs production Lua strength tick bodies with inert mpv I/O. Requires lupa.
Usage: python3 grain_strength_window_test.py PHOTON_LUA
Not a GPU/pixel/estimator-accuracy test.
"""
import sys
from pathlib import Path
from lupa.lua51 import LuaRuntime
p=Path(sys.argv[1]).read_text()
def between(a,b): return p[p.index(a):p.index(b,p.index(a))]
# Compile the complete production file without executing its mpv dependencies.
lua=LuaRuntime(unpack_returned_tuples=True)
assert lua.eval('loadstring')(p) is not None
prefix='''
local math_max,math_min,math_abs=math.max,math.min,math.abs
local enabled,playback_active=true,true
local DOC={gen=1,active=true,name='test',append=function() end}
local GR={control_revision=1,enabled=true,strength=6,ts=0,soft_rendered=1,size_rendered=1}
local GS={window=5,mhist={},hist={},strength_default=6,mult_floor=0,mult_slew=.1,mult_deadband=.05,
legacy_min=.4,legacy_max=1.25,src_share_min=.1,luma_jump=.35,seed_look=function() return 1.54 end,
log_sample_contract=function() end,publish_probe=function() end}
local COST={media_telemetry=false}
local SIZE_GOV={program_on=true,hold=function() end}
local RADAR_STATE={stream_frozen=function() return false end}
local common={trace_record=function() end}
local position=0; local sent={}; local sample_mult=0; local sample_luma=100
local mp={get_time=function() return position end,get_property_number=function() position=position+1; return position end,
commandv=function(...) table.insert(sent,{...}) end,msg={info=function() end},register_script_message=function() end}
local gs_median=function(t) local r={}; for i,v in ipairs(t) do r[i]=v end; table.sort(r); return r[math.ceil(#r/2)] end
local gs_sample_frame=function() return nil,sample_mult,1746,sample_luma,.81,607.6717 end
'''
tick=between('local function gs_tick()', '-- No queued catch-up work after a slow ON sample/vote.')
checks='''
local function reset(on,strength)
 SIZE_GOV.program_on=on; GR.strength=strength or 6; GS.mhist={};GS.hist={};GS.last_mult=nil;GS.r_total=nil
 GS.prev_luma=nil;GS.look_learn=nil;GS.last_pos=nil;sent={};sample_mult=0;sample_luma=100
end
reset(true)
for i=1,4 do gs_tick();assert(#sent==0,'adaptive warmup sent early') end
gs_tick();assert(#sent==1 and math.abs(tonumber(sent[1][3])-.9)<1e-8,'first zero did not slew from rendered strength')
assert(sent[1][8]=='5','strength window count not five')
GR.strength=5.4;gs_tick();assert(math.abs(tonumber(sent[2][3])-.8)<1e-8,'subsequent slew changed')
-- Same trim-state reset as production: retained committed strength, fresh samples.
GS.mhist={};GS.hist={};GS.pair=nil;sent={};GR.strength=4.8
for i=1,4 do gs_tick();assert(#sent==0,'trim bypassed warmup') end
gs_tick();assert(math.abs(tonumber(sent[1][3])-.7)<1e-8,'trim did not retain prior')
reset(true,3)
for i=1,5 do gs_tick() end
assert(math.abs(tonumber(sent[1][3])-.4)<1e-8,'first slew ignored current rendered strength')
reset(false);gs_tick();assert(#sent==1 and tonumber(sent[1][3])==.4,'legacy first apply changed')
reset(false);sample_mult=2;gs_tick();assert(tonumber(sent[1][3])==1.25,'legacy ceiling changed')
reset(true);sample_mult=nil;for i=1,8 do gs_tick() end;assert(#sent==0 and #GS.mhist==0,'invalid samples counted')
reset(true);sample_mult=0;gs_tick();sample_luma=200;gs_tick();assert(#GS.mhist==1,'luma step counted')
reset(true);sample_mult=1;for i=1,5 do gs_tick() end;assert(#sent==0,'unchanged current strength emitted')
print('PASS: warmup, first slew, continued slew, trim rewarmup/prior, rendered prior, legacy floor/ceiling, invalid sample, luma step, unchanged target')
'''
lua.execute(prefix+tick+checks)
