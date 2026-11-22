#!/usr/bin/env python3
"""photon.lua global ffmpeg subprocess manager (real source, Lua 5.1; LOGIC ONLY, Lua-stub with fake async jobs).
Burst of 20 ffmpeg spawns (what the grain-size sampler + radar + calibration can issue at once): never more than
FF.cap (3) running; all 20 complete in FIFO order; start-file aborts the running jobs and drops the queue; the sh
command gets `exec` so a kill reaches ffmpeg; non-ffmpeg subprocess calls (ps) bypass the cap; a callback error still pumps."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
m = re.search(r"^COST\.ffw_n, COST\.ffw_ms = 0, 0\n.*?^local is_network_slow", src, re.S | re.M); assert m
body = m.group(0).rsplit("local is_network_slow", 1)[0]
lua = lua51.LuaRuntime()
lua.execute("""
now = 0; nid = 0; running = {}; maxrun = 0; order = {}; aborted_ids = {}; events = {}; timeouts = {}
mp = { get_time=function() return now end, get_property=function(k,d) return d end,
  register_event=function(n, f) events[n] = f end,
  add_periodic_timer=function(i, f) pump_timer = f; return {} end,
  add_timeout=function(t, f) timeouts[#timeouts+1] = f; return {} end,
  abort_async_command=function(id) aborted_ids[#aborted_ids+1] = id; local j = running[id]; running[id] = nil; if j then j.cb(false, nil, 'killed') end end,
  command_native_async=function(t, cb) nid = nid + 1; running[nid] = {t=t, cb=cb, tag=t.args[3]}; local c = 0; for _ in pairs(running) do c = c + 1 end; if c > maxrun then maxrun = c end; return nid end }
COST = {}
VR = false
function COST.vr_window() return VR end
""" + body + """
function finish_one() local id; for k in pairs(running) do if not id or k < id then id = k end end; local j = running[id]; running[id] = nil; order[#order+1] = j.tag; j.cb(true, {stdout=''}) end
function spawn(tag, prog) mp.command_native_async({name='subprocess', args={'sh','-c', prog .. ' ' .. tag}}, function(ok, res) if tag == 'boom' then error('cb failed') end end) end
""")
for i in range(20): lua.execute("spawn('j%d', '\"/x/ffmpeg\" -i a')" % i)
r = {}
r["queued_at_burst"] = lua.eval("#COST.FF.queue"); r["max_running_burst"] = lua.eval("maxrun")
r["exec_prefix"] = lua.eval("(function() for _, j in pairs(running) do return j.t.args[3]:sub(1,5) end end)()")
for i in range(20): lua.execute("finish_one()")
r["completed"] = lua.eval("COST.ffw_n"); r["max_running_total"] = lua.eval("maxrun"); r["cur_end"] = lua.eval("COST.FF.cur"); r["fifo"] = lua.eval("(function() for i = 1, 20 do if order[i]:sub(-#('j'..(i-1))) ~= 'j'..(i-1) then return false end end return true end)()")
for i in range(8): lua.execute("spawn('k%d', '\"/x/ffmpeg\" -i a')" % i)
lua.execute("events['start-file']()")
r["aborted"] = lua.eval("#aborted_ids"); r["dropped"] = lua.eval("COST.FF.dropped"); r["queue_after_abort"] = lua.eval("#COST.FF.queue"); r["cur_after_abort"] = lua.eval("COST.FF.cur")
lua.execute("spawn('boom', '\"/x/ffmpeg\"'); for i=1,4 do spawn('m'..i, '\"/x/ffmpeg\"') end")
lua.execute("for id, j in pairs(running) do if j.tag == 'boom' then running[id] = nil; pcall(j.cb, true, {}) end end")
r["pump_after_cb_error"] = lua.eval("maxrun <= 3 and COST.FF.cur")
lua.execute("n0 = nid; mp.command_native_async({name='subprocess', args={'ps','-ax'}}, function() end); for i=1,5 do mp.command_native_async({name='subprocess', args={'ps'}}, function() end) end")
r["non_ffmpeg_bypass"] = lua.eval("nid - n0")
# VR window: cap 0 - nothing starts, a running job is aborted by the 1 s pump, the queue is kept and drains after close
lua.execute("events['start-file'](); for id in pairs(running) do running[id] = nil end; COST.FF.cur = 0; maxrun = 0; VR = false")
for i in range(2): lua.execute("spawn('r%d', '\"/x/ffmpeg\" -i a')" % i)   # two jobs already running when VR opens
lua.execute("VR = true; started0 = COST.FF.started; ab0 = #aborted_ids")
for i in range(6): lua.execute("spawn('v%d', '\"/x/ffmpeg\" -i a')" % i)
r["vr_running"] = lua.eval("COST.FF.cur - 2"); r["vr_queued"] = lua.eval("#COST.FF.queue")
r["vr_started_in_window"] = lua.eval("COST.FF.started - started0")
lua.execute("pump_timer()")
r["vr_aborted_running"] = lua.eval("#aborted_ids - ab0"); r["vr_cur_after_abort"] = lua.eval("COST.FF.cur"); r["vr_queue_kept"] = lua.eval("#COST.FF.queue")
lua.execute("VR = false; COST.ff_pump()")
r["after_close_running"] = lua.eval("COST.FF.cur")
r["after_close_prefix"] = lua.eval("(function() local best; for id, j in pairs(running) do if not best or id > best then best = id end end; return running[best].t.args[3]:sub(1,5) end)()")
for k, v in r.items(): print("%-20s %s" % (k, v))
ok = (r["queued_at_burst"] == 17 and r["max_running_burst"] == 3 and r["exec_prefix"] == "exec " and r["completed"] == 20
      and r["max_running_total"] == 3 and r["cur_end"] == 0 and r["fifo"] and r["aborted"] == 3 and r["dropped"] == 5
      and r["queue_after_abort"] == 0 and r["cur_after_abort"] == 0 and r["pump_after_cb_error"] == 3 and r["non_ffmpeg_bypass"] == 6
      and r["vr_running"] == 0 and r["vr_queued"] == 6 and r["vr_started_in_window"] == 0
      and r["vr_aborted_running"] == 2 and r["vr_cur_after_abort"] == 0 and r["vr_queue_kept"] == 6
      and r["after_close_running"] == 3 and r["after_close_prefix"] == "exec ")
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
