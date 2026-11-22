#!/usr/bin/env python3
"""photon.lua VR probe path (real source, Lua 5.1; LOGIC ONLY, Lua-stub with a simulated clock, not native-render).
Contract in the VR stereo window (user-data/gor/stereo-window-owned == true):
  - probes never read back on their own: no synchronous screenshot-raw; at most ceil(28/interval) async captures
  - the 17 probe calls of a 28 s window (the measured cadence) get frames from the shared capture: >= 15 of 17 succeed
  - a slow capture (> slow_ms) doubles the pacing interval, capped at max_interval; fast captures step it back
  - paused playback and no-file issue no capture; a seek clears the cached frame; a probe never gets a stale frame
  - VR.mode == "off" restores the plain gate (0 readbacks, 0 ok); normal playback still reads back every call (17/17)."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
sh = re.search(r"^function SHARE\.clear\(\).*?^end\n", src, re.S | re.M); assert sh
g = re.search(r"^-- VR stereo window:.*?^function COST\.shot\(role\)\n    if COST\.vr_window\(\) then.*?^    end\n", src, re.S | re.M); assert g
body = sh.group(0) + g.group(0)
tail = src[src.index(g.group(0)) + len(g.group(0)):]
legacy = tail[:tail.index("    return ok, shot\nend\n") + len("    return ok, shot\nend\n")]
PRE = """
sync_shots = 0; async_n = 0; pending = nil; now = 100; VRW = %s; PAUSED = %s; PATH = "f.mkv"; CAP_MS = %s
mp = { get_time=function() return now end, msg={info=function() end},
  get_property_native=function(n)
    if n=="user-data/gor/stereo-window-owned" then return VRW end
    if n=="pause" then return PAUSED end
    if n=="path" then return PATH end end,
  command_native=function(c) sync_shots = sync_shots + 1; return {data="x", w=1, h=1} end,
  command_native_async=function(c, cb) async_n = async_n + 1; pending = {cb=cb, due=now + CAP_MS/1000}; return true end,
  add_periodic_timer=function(i, f) return {} end }
COST = { media_telemetry=false, cur="t", rec=function(t) return {shot_ms=0, bytes=0, fail=0} end }
local SHARE = { on=false, ttl=0.7, t=0, shot=nil, res=nil }
"""
def mk(vr=True, paused=False, cap_ms=5, mode="sparse"):
    lua = lua51.LuaRuntime()
    lua.execute(PRE % ("true" if vr else "nil", "true" if paused else "false", cap_ms) + body + legacy +
        "\nCOST.VR.mode = '%s'\nokc = 0\nfunction step(dt) now = now + dt; if pending and now >= pending.due then local p = pending; pending = nil; local sv = now; now = p.due; p.cb(true, {data='x', w=1, h=1}); now = sv end; COST.vr_capture_tick() end\n"
        "function probe() local ok = COST.shot('x'); if ok then okc = okc + 1 end end\nSHARE_CLEAR = SHARE.clear" % mode)
    return lua
def window(lua, secs=28.0, probes=17):
    t, nxt, dt = 0.0, 0.0, 0.25
    while t < secs:
        lua.eval("step(%f)" % dt); t += dt
        if t >= nxt: lua.execute("probe()"); nxt += secs / probes
    return lua.eval("sync_shots"), lua.eval("async_n"), lua.eval("okc")
res = {}
l = mk(); res["vr"] = window(l)
res["vr_interval"] = l.eval("COST.VR.interval")
l = mk(cap_ms=90); window(l, 28); res["slow_interval"] = l.eval("COST.VR.interval")
l = mk(cap_ms=90); window(l, 200); res["slow_cap"] = l.eval("COST.VR.interval"); res["slow_async"] = l.eval("async_n")
l = mk(paused=True); res["paused"] = window(l)
l = mk(); window(l, 12); l.execute("SHARE_CLEAR()"); res["after_clear_ok"] = l.eval("(function() local ok = COST.shot('x'); return ok and 1 or 0 end)()")
l = mk(); window(l, 20); l.execute("now = now + 30"); res["stale_ok"] = l.eval("(function() local ok = COST.shot('x'); return ok and 1 or 0 end)()")
l = mk(mode="off"); res["off"] = window(l)
l = mk(vr=False); res["normal"] = window(l)
for k, v in res.items(): print("%-15s %s" % (k, v))
ok = (res["vr"][0] == 0 and res["vr"][1] <= 6 and res["vr"][2] >= 15 and res["vr_interval"] == 5.0
      and res["slow_interval"] > 5.0 and res["slow_cap"] == 30.0 and res["slow_async"] <= 10
      and res["paused"] == (0, 0, 0) and res["after_clear_ok"] == 0 and res["stale_ok"] == 0
      and res["off"] == (0, 0, 0) and res["normal"][0] == 17 and res["normal"][2] == 17)
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
