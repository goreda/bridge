#!/usr/bin/env python3
"""R2 (photon queue): GS.look_file / look_bounds / load_look / save_look from the real photon.lua source (Lua 5.1; LOGIC ONLY,
Lua-stub with REAL files on disk, not native). Checks: a stored look outside [legacy_min^2, legacy_max^2] is ignored and the file is
byte- and mtime-identical afterwards; in-range and boundary values are accepted; empty, non-numeric and missing files change nothing;
save_look writes %.4f and round-trips through load_look; no look -> no file written; a failing expand-path disables both; the clamped low bound 0.1600 round-trips (float tolerance)."""
import os, pathlib, re, sys, tempfile
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
i = src.index("function GS.look_file()"); j = src.index("\nGS.load_look()\n", i) + 1
body = src[i:j]
tmp = pathlib.Path(tempfile.mkdtemp()); path = tmp / "gor_look.txt"
def mk(expand_ok=True):
    lua = lua51.LuaRuntime()
    lua.globals().LOOKPATH = str(path) if expand_ok else None
    lua.execute("""
GS = { legacy_min = 0.40, legacy_max = 1.25, look_R = nil, look_path = nil }
WARN = {}
mp = { msg = { warn = function(m) WARN[#WARN + 1] = m end, info = function() end },
       command_native = function(c) if LOOKPATH then return LOOKPATH end; error("no expand-path") end }
""" + body)
    return lua
def state(lua): return lua.eval("GS.look_R"), lua.eval("GS.look_rejected"), lua.eval("#WARN")
ok = True
def chk(c, t):
    global ok
    if not c: ok = False; print("FAIL", t)
lo, hi = mk().eval("GS.look_bounds")()
chk(abs(lo - 0.16) < 1e-9 and abs(hi - 1.5625) < 1e-9, "bounds %s %s" % (lo, hi))
for text, label in (("4.027\n", "stale high 4.027"), ("0.05\n", "low 0.05"), ("1.5626\n", "just above hi"), ("0.1599\n", "just below lo")):
    path.write_text(text); b0, m0 = path.read_bytes(), path.stat().st_mtime_ns
    l = mk(); l.execute("GS.load_look()"); R, rej, nw = state(l)
    chk(R is None and rej is not None and nw == 1, label + ": ignored, rejected, warned")
    chk(path.read_bytes() == b0 and path.stat().st_mtime_ns == m0, label + ": file untouched")
for text, label, want in (("1.0\n", "in range 1.0", 1.0), ("0.1601\n", "just above lo", 0.1601), ("1.5625\n", "boundary hi", 1.5625), ("0.9100", "no newline", 0.91)):
    path.write_text(text); l = mk(); l.execute("GS.load_look()"); R, rej, nw = state(l)
    chk(R is not None and abs(R - want) < 1e-9 and rej is None and nw == 0, label + ": accepted")
# Float edge (fixed): look_bounds() lo = 0.4*0.4 = 0.16000000000000003, and a look clamped to the low bound is saved as 0.1600.
# Both bounds written by save_look must load back; values beyond the 1e-9 tolerance are still rejected.
for text, label, want in (("0.1600\n", "saved lower bound 0.1600", 0.16), ("1.5625\n", "saved upper bound 1.5625", 1.5625)):
    path.write_text(text); l = mk(); l.execute("GS.load_look()"); R, rej, nw = state(l)
    chk(R is not None and abs(R - want) < 1e-9 and rej is None, label + ": accepted")
l = mk(); l.execute("GS.look_R = GS.look_bounds(); GS.save_look()"); l2 = mk(); l2.execute("GS.load_look()")
chk(l2.eval("GS.look_R") is not None, "a look clamped to the low bound survives save then load")
path.write_text("0.1599\n"); l = mk(); l.execute("GS.load_look()"); chk(l.eval("GS.look_R") is None, "0.1599 still rejected")
for text, label in (("", "empty"), ("abc\n", "non-numeric"), ("\n", "blank line")):
    path.write_text(text); l = mk(); l.execute("GS.load_look()"); R, rej, nw = state(l)
    chk(R is None and rej is None and nw == 0 and path.read_text() == text, label + ": no change, file untouched")
path.unlink(); l = mk(); l.execute("GS.load_look()"); chk(state(l) == (None, None, 0), "missing file: no change")
l = mk(); l.execute("GS.save_look()"); chk(not path.exists(), "no look: nothing written")
l = mk(); l.execute("GS.look_R = 1.23456789; GS.save_look()")
chk(path.read_text() == "1.2346\n", "save format %r" % (path.read_text() if path.exists() else None))
l2 = mk(); l2.execute("GS.load_look()"); chk(abs(l2.eval("GS.look_R") - 1.2346) < 1e-9, "round trip")
l = mk(expand_ok=False); l.execute("GS.look_R = 1.0; GS.save_look(); GS.load_look()")
chk(l.eval("GS.look_path") is False and path.read_text() == "1.2346\n", "expand-path failure: save and load are no-ops")
print("rows checked against real files in", tmp); print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
