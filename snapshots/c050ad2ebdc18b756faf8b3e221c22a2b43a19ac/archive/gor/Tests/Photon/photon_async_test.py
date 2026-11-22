#!/usr/bin/env python3
"""Production readback/runner snippets under delayed callbacks on LuaJIT and Lua5.1."""
from pathlib import Path
from importlib import import_module
r=Path(__file__).resolve().parents[2];s=(r/'Resources/vendor/mpv/scripts/photon.lua').read_text()
a=s.index('function COST.shot(role)');b=s.index('function COST.wrap(',a)
budget=s[s.index('COST.read_budget = '):s.index('function COST.vr_capture_tick()')]
clear=s[s.index('function SHARE.clear()'):s.index('-- VR stereo window:')]
for runtime in ['lupa.luajit21','lupa.lua51']:
 l=import_module(runtime).LuaRuntime(unpack_returned_tuples=True)
 l.execute('''now=0;pending={};done=0;sync=0;requests=0
mp={get_time=function()return now end,msg={warn=function()end},get_property_native=function()return false end,
command_native=function()sync=sync+1;return {data='sync',w=1,h=1}end,
command_native_async=function(c,cb)requests=requests+1;pending[#pending+1]=cb;return requests end}
COST={cur='t',media_telemetry=false,stats={},vr_window=function()return false end}
function COST.rec(t)if not COST.stats[t]then COST.stats[t]={shot_ms=0,fail=0,bytes=0}end;return COST.stats[t]end
SHARE={on=false,ttl=.7,t=0}
'''+budget+s[a:b]+clear+'''
function finish(data) local cb=table.remove(pending,1);now=now+.1;cb(true,{data=data,w=1,h=1})end
function probe()local ok,shot=COST.shot('own');if ok then value=shot.data end;done=done+1 end
''')
 l.execute("COST.spawn('GS',probe);assert(done==0 and requests==1 and sync==0);assert(not COST.capture_room(1));assert(not COST.spawn('GS',probe));finish('first');assert(value=='first' and done==1);assert(COST.capture_room(1))")
 l.execute("COST.spawn('RG',probe);SHARE.clear();finish('old');assert(value=='first' and done==1 and SHARE.shot==nil);assert(COST._active.RG==nil)")
 l.execute("COST.spawn('GS',function()local a,b=COST.shot('own');pair1=b.data;local c,d=COST.shot('own');pair2=d.data end);finish('pair-a');assert(pair1=='pair-a' and pair2==nil and not COST.capture_room(1));finish('pair-b');assert(pair2=='pair-b')")
 assert l.eval('sync')==0
 print('PASS',runtime,'park/resume, collision, two fresh GS callbacks, reserved slots, stale lifetime never resumes body')
assert 'mp.add_periodic_timer(UPDATE_INTERVAL, update_hdr)' in s
assert 'COST.spawn("HDRHUE", function()' in s
print('PASS HDR10Hz body unparked; only hue screenshot uses async coroutine')
