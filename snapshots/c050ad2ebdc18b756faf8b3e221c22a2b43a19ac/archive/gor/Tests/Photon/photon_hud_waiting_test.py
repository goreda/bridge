#!/usr/bin/env python3
"""HUD must never sit on a bare "waiting". Runs the real HUD_STATE.wait_text / sdr_mode_text from photon-hud.lua (Lua 5.1).
Per source type: local file, magnet stream, live stream, seek miss, and photon.lua not running."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon-hud.lua").read_text(encoding="utf-8")
m = re.search(r"^HUD_STATE\.WAIT_FAIL_S.*?^end\n.*?^end\n", src, re.S | re.M); assert m, "helpers not found"
lua = lua51.LuaRuntime()
lua.execute('HUD_INDENT = string.rep(" ", 6)\nHUD_STATE = {}\n' + m.group(0))
wait, mode = lua.eval("HUD_STATE.wait_text"), lua.eval("HUD_STATE.sdr_mode_text")
def pst(**kw):
    d = dict(is_live=False, live_calib_ready=False, live_calib_samples=0, live_calib_frames=8, sdr_neutral=12.0, radar_buffer_len=0, radar_buffer_miss=False)
    d.update(kw); return lua.table_from(d)
bad = []
def has(name, text, *needles):
    for n in needles:
        if n not in text: bad.append((name, n, text))
has("fresh", wait(1.0), "waiting for photon.lua")
has("not running", wait(6.0), "not running", "mpv log")
if "waiting" in wait(6.0): bad.append(("still says waiting after timeout", wait(6.0)))
has("local file", mode(pst(radar_buffer_len=40), 3.0), "radar  40 frames")
has("local file late", mode(pst(radar_buffer_len=40), 500.0), "radar  40 frames")
has("magnet warming", mode(pst(), 5.0), "probe (warming up)")
has("magnet stalled", mode(pst(), 25.0), "probe stalled 25 s", "no frame data")
has("seek", mode(pst(radar_buffer_miss=True), 99.0), "seek")
has("live calib", mode(pst(is_live=True, live_calib_samples=3), 99.0), "calib: 3/8")
has("live ready", mode(pst(is_live=True, live_calib_ready=True), 99.0), "calib: 12")
print("FAIL", bad) if bad else print("PASS")
sys.exit(1 if bad else 0)
