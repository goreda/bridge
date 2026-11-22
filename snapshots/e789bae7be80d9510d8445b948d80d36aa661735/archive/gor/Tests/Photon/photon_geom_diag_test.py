#!/usr/bin/env python3
"""photon-cost diag carries the geometry that decides mpv's own scale pass (real photon.lua, Lua 5.1, log-only).
Pixel-neutral: only reads properties; passes list now keeps 10 entries so the lanczos passes are visible."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
m = re.search(r"^function COST\.passes_line\(\).*?^function COST\.diag_on", src, re.S | re.M); assert m
body = m.group(0).rsplit("function COST.diag_on", 1)[0]
lua = lua51.LuaRuntime()
lua.execute("""
COST = {}
props = {["vo-passes"]={fresh={}}, ["video-params/w"]=8192, ["video-params/h"]=4096, ["video-out-params/w"]=1920, ["video-out-params/h"]=1080,
  dwidth=1920, dheight=1080, ["osd-dimensions"]={w=1920,h=1080}, ["video-zoom"]=0, ["video-pan-x"]=0, ["video-pan-y"]=0, ["video-unscaled"]="no", scale="lanczos"}
for i=1,12 do props["vo-passes"].fresh[i] = {desc="pass"..i.." long description padded to exceed forty eight characters", avg=(13-i)*1e6, peak=2e6} end
mp = { get_property_native=function(n) return props[n] end }
""" + body)
line = lua.eval("COST.passes_line()")
n_top = len(re.findall(r"ms\(pk", line))
ok = (n_top == 10 and "n=12" in line and "geom{src=8192x4096 out=1920x1080 disp=1920x1080 osd=1920x1080 zoom=0 pan=0,0 unscaled=no scale=lanczos}" in line
      and "pass1 long description padded to exceed forty" in line and "pass11" not in line)
lua.execute("props['vo-passes'] = nil; props['osd-dimensions'] = nil")
line2 = lua.eval("COST.passes_line()")
ok = ok and line2 == "vo-passes=unavailable"
lua.execute("props['vo-passes'] = {fresh={}}; props['osd-dimensions'] = nil; props['video-out-params/w'] = nil")
line3 = lua.eval("COST.geom_line()")
ok = ok and "out=nilx1080" in line3 and "osd=nilxnil" in line3
print(line[:200]); print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
