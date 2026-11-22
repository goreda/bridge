#!/usr/bin/env python3
"""Actual Photon Lua budget/caller snippets, Lua 5.1 simulation. Not pixels or mpv timing."""
import pathlib, re
from lupa import lua51
root = pathlib.Path(__file__).resolve().parents[2]
src = (root / 'Resources/vendor/mpv/scripts/photon.lua').read_text()
def section(a,b):
    return src.split(a,1)[1].split(b,1)[0]
runner = src[src.index('COST.fence_n = 0'):src.index('function COST.wrap(')]
budget = 'COST.read_budget = ' + section('COST.read_budget = ', 'function COST.vr_capture_tick()')
paced = 'function GS.paced_tick()' + section('function GS.paced_tick()', 'GS.timer = ')
bk = 'local function bk_run_probe()' + section('local function bk_run_probe()', '-- Re-probe:') + '\nrun_bk=bk_run_probe\n'
lua = lua51.LuaRuntime()
lua.execute('''
now=0; reads={}; timers={}; enabled=true; playback_active=true
DOC={active=true,gen=1}; GS={interval=4}; SIZE_GOV={program_on=true}
COST={}; BK={gen=0,count=3,interval=0.3}; finalized=0
mp={get_time=function() return now end, msg={warn=function() end}}
function mp.add_timeout(delay,fn)
 local t={at=now+delay,fn=fn,kill=function(self) self.dead=true end}
 timers[#timers+1]=t; return t
end
function advance(to)
 while true do
  local first=nil
  for _,t in ipairs(timers) do
   if not t.dead and t.at<=to and (not first or t.at<first.at) then first=t end
  end
  if not first then break end
  first.dead=true; now=first.at; first.fn()
 end
 now=to
end
''' + budget + runner + '''
function physical()
 COST.capture_started(); reads[#reads+1]=now
 return {pair=1,quilt=1}
end
function gs_tick()
 physical(); now=now+0.03125; physical()
 GS.samples=(GS.samples or 0)+1
end
bk_sample_frame=physical
function bk_finalize() finalized=#BK.samples end
function bk_schedule_reprobe() end
''' + paced + bk)
# Same-time contention: GS must wait for TWO slots and retry, not reuse a frame.
lua.execute('physical(); GS.paced_tick(); run_bk(); advance(1.01)')
assert lua.eval('GS.samples') == 1
assert lua.eval('#reads') == 3
assert abs(lua.eval('reads[3]-reads[2]') - 0.03125) < 1e-8
lua.execute('advance(4.1)')
assert lua.eval('finalized') == 3  # deferral must not finish a 3-sample probe early
assert lua.eval('#BK.samples') == 3
reads=list(lua.eval('reads').values())
for t in reads:
    assert sum(t <= q < t+1-1e-9 for q in reads) <= 2, reads
# A waiting GS callback must not probe a newly opened document.
lua.execute('now=5; physical(); GS.next_probe_at=nil; GS.paced_tick(); DOC.gen=2; advance(6)')
assert lua.eval('GS.samples') == 1
assert not lua.eval('COST.read_budget.pair_waiting')
# Long mixed burst: group requests stay globally bounded, never per-caller.
lua.execute('COST.read_budget={times={},requests=0,deferred=0}; reads={}; now=10')
for i in range(1000):
    lua.execute(f'now={10+i*0.01}; if COST.capture_room(1) then physical() end')
reads=list(lua.eval('reads').values())
assert len(reads)==20
for t in reads:
    assert sum(t <= q < t+1-1e-9 for q in reads) <= 2
# Physical capture and timer contracts, async callback details covered separately.
assert src.count('pcall(mp.command_native, {"screenshot-raw", "video"})') == 1
assert src.count('pcall(mp.command_native_async, {"screenshot-raw", "video"}') == 2
assert 'if not COST.capture_room(1) then return end\n    COST.capture_started()\n    V.busy' in src
assert src.count('deferred is not a failed/collected sample') == 2
assert 'LIVE_CALIB.capture_interval and COST.capture_room(1)' in src
assert 'if is_network_slow then\n        if not COST.capture_room(1)' in src
assert section('function GS.pair_flicker()', 'local function gs_tick()').count('GS.capture_luma()') == 1
print('PASS global sliding-window cap, two-read GS admission, deferred BK count, document fence')
print('LOGIC ONLY: async fresh-pair callback tests are in photon_async_test.py; no owner drop claim')
