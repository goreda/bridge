#!/usr/bin/env python3
"""photon.lua probe_sdr_frame (real source, Lua 5.1): in the VR window with FF.vr_cap==0 it must queue nothing and not run
the watchdog (before: one queued job per 10 s retry, seen in the owner's VR log as 'sdr probe watchdog ... retrying' x11);
outside VR it reaches the watchdog as before. Counts the watchdog/queue calls per 60 simulated 1 s ticks."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
m = re.search(r"^local function probe_sdr_frame\(\)\n(.*?)    -- v14: don't probe", src, re.S | re.M); assert m
lua = lua51.LuaRuntime()
lua.execute("""
VR=false; warns=0; reached=0
RADAR_STATE={live_buffer={}, buffer_miss=true, stream_frozen=function() reached=reached+1; return true end}
SDR_STATE={ffmpeg_running=true, ffmpeg_started=0}
is_network_slow=false
COST={FF={vr_cap=0}}; function COST.vr_window() return VR end
now=0
mp={get_time=function() return now end, msg={warn=function() warns=warns+1 end}}
""" + "local function probe_sdr_frame()\n" + m.group(1) + "    if RADAR_STATE.stream_frozen() then return end\nend\nprobe=probe_sdr_frame")
def run(vr):
    lua.execute("VR=%s; warns=0; reached=0; SDR_STATE.ffmpeg_running=true; SDR_STATE.ffmpeg_started=0" % ("true" if vr else "false"))
    for t in range(1, 61):
        lua.execute("now=%d; probe()" % (t * 1))
        lua.execute("SDR_STATE.ffmpeg_running=true; SDR_STATE.ffmpeg_started=now - 20")
    return lua.eval("warns"), lua.eval("reached")
vr = run(True); nonvr = run(False)
print("vr (watchdog warns, probes reaching spawn path):", vr, " non-vr:", nonvr)
ok = vr == (0, 0) and nonvr[0] > 0
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
