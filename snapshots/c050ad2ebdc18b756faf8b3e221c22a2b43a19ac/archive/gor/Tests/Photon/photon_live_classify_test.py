#!/usr/bin/env python3
"""photon.lua classify_live (real source, Lua 5.1): magnet streams on the WT port are live without the set-live IPC;
other sources keep their explicit setting; a stale explicit false cannot turn a WT stream into VOD."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
m = re.search(r"^SDR_STATE\.WT_PORT = .*?^SDR_STATE\.classify_live = function.*?^end\n", src, re.S | re.M); assert m
lua = lua51.LuaRuntime(); lua.execute("SDR_STATE = {}\n" + m.group(0))
c = lua.eval("SDR_STATE.classify_live")
def run(path, explicit):
    r = c(path, explicit)
    return (r[0], r[1]) if isinstance(r, tuple) else (r, None)
cases = [
 ("magnet localhost, no explicit (lost IPC)", "http://localhost:2222/stream/0", None, True, "wt-port"),
 ("magnet 127.0.0.1, no explicit", "http://127.0.0.1:2222/stream/0", None, True, "wt-port"),
 ("magnet bare port", "http://localhost:2222", None, True, "wt-port"),
 ("magnet explicit true", "http://localhost:2222/stream/0", True, True, "explicit"),
 ("magnet stale explicit false", "http://localhost:2222/stream/0", False, True, "wt-port"),
 ("other loopback port 2223 not live", "http://localhost:2223/x", None, None, "unknown"),
 ("port 22220 not live", "http://localhost:22220/x", None, None, "unknown"),
 ("remote https unknown", "https://example.com/a.mp4", None, None, "unknown"),
 ("remote IPTV explicit true", "https://iptv.example/ch1", True, True, "explicit"),
 ("remote explicit false", "https://example.com/a.mp4", False, False, "explicit"),
 ("local file", "/Users/x/film.mkv", None, None, "unknown"),
 ("empty", "", None, None, "unknown"),
]
bad = [(n, run(p, e), (v, s)) for n, p, e, v, s in cases if run(p, e) != (v, s)]
print("FAIL", bad) if bad else print("PASS %d cases" % len(cases))
sys.exit(1 if bad else 0)
