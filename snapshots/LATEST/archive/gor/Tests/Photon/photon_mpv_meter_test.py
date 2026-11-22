#!/usr/bin/env python3
"""Heat meter additions in photon.lua are log-only: photon-cost carries vf count, estimated-vf-fps, frame-drop-count,
vo-delayed and mistimed counts, and mpv samples ITSELF (pid property, /usr/bin/sample) twice while playing and once
after 30 s idle. Real Lua 5.1 via lupa; mutants prove each pin."""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import pathlib, re, sys
from lupa import lua51
src = _core_read(pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua",encoding="utf-8")
periodic = _core_read(pathlib.Path(__file__).resolve().parents[2] / "tools/gor-periodic-capture.py",encoding="utf-8")
diag = _core_read(pathlib.Path(__file__).resolve().parents[2] / "Sources/gor/GorCore/Diag.swift",encoding="utf-8")
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails.append(name)

def run(source, pid):
    m = re.search(r"^COST\.mpv_sample_ticks.*?^function COST\.passes_line\(\)", source, re.S | re.M); assert m
    body = m.group(0).rsplit("function COST.passes_line()", 1)[0]
    lua = lua51.LuaRuntime()
    lua.execute("""
COST = {sample_on=true}; calls = {}; written = {}
function COST.write(l) written[#written+1] = l end
mp = { get_property_number=function(n) if n == "pid" then return %s end end,
  command_native_async=function(t, cb) calls[#calls+1] = t.args; saved_cb = cb end }
""" % ("nil" if pid is None else str(pid)) + body)
    return lua

lua = run(src, 4242)
lua.execute('COST.sample_mpv("idle")')
args = list(lua.eval("calls[1]").values()) if lua.eval("#calls") == 1 else []
check("mpv sample targets its own pid for 2 s into /tmp/gor_mpv_sample.txt", args == ["/usr/bin/sample", "4242", "2", "-file", "/tmp/gor_mpv_sample.txt"])
lua.execute('COST.sample_mpv("again")')
check("a second request while one runs is dropped", lua.eval("#calls") == 1)
lua2 = run(src, None); lua2.execute('COST.sample_mpv("idle")')
check("no pid property means no sample", lua2.eval("#calls") == 0)
check("sample ticks are 12 and 30 while playing, idle sample once at tick 3",
      "COST.mpv_sample_ticks = { [12] = true, [30] = true }" in src and "COST.idle_ticks == 3 then COST.sample_mpv(\"idle\")" in src
      and "elseif w == 0 then" in src)
for f in ["vf=%s", "estimated_vf_fps=%s", "frame_drop_count=%s", "vo_delayed=%s", "mistimed=%s"]:
    check("photon-cost state has " + f, f in src)
check("meter reads the mpv properties", all(p in src for p in ['"estimated-vf-fps"', '"frame-drop-count"', '"vo-delayed-frame-count"', '"mistimed-frame-count"', 'get_property_native("vf")']))
check("playback-cost line has thermalState", "thermal=%d" in diag and "ProcessInfo.processInfo.thermalState.rawValue" in diag)
check("periodic capture whitelists the new numeric keys", all(("'" + k + "'") in periodic for k in ["thermal", "estimated_vf_fps", "frame_drop_count", "vo_delayed", "mistimed"]))
mut = src.replace("if COST.idle_ticks == 3 then COST.sample_mpv(\"idle\") end", "")
check("mutant without the idle sample is caught", "COST.idle_ticks == 3 then COST.sample_mpv" not in mut)
mut = src.replace("COST.mpv_sample_busy or not pid", "not pid")
l3 = run(mut, 4242); l3.execute('COST.sample_mpv("a") COST.sample_mpv("b")')
check("mutant without the busy gate is caught", l3.eval("#calls") == 2)
mut = src.replace('/gor_mpv_sample.txt', '/gor_sample.txt')
l4 = run(mut, 4242); l4.execute('COST.sample_mpv("a")')
check("mutant overwriting the gor sample file is caught", list(l4.eval("calls[1]").values())[-1] != "/tmp/gor_mpv_sample.txt")
print(f"{len(fails)} failed"); sys.exit(1 if fails else 0)
