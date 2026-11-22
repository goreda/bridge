#!/usr/bin/env python3
"""R4(a): HUD row-count and row-width bound from the real photon-hud.lua draw_hud (Lua 5.1 stub; LOGIC ONLY, Lua-stub).
This is NOT a layout-inside-the-picture test: placement, font and crop are decided by the Swift overlay (reserved), not by this script.
Bounds (written before the first run): fully expanded HUD <= 36 rows; every row <= 72 characters after the "section<TAB>" key
(characters, not bytes); folded HUD = the 6 section title rows in order (photon, bright, sharp, grain, chrome, negativ) plus at most one extra row, the explicit photon no-data reason row (the first run assumed exactly 6; with no photon data the HUD shows its reason row by design); no row is empty, and no row shows nan/inf/nil/error text."""
import pathlib, sys
from lupa import lua51
root = pathlib.Path(__file__).resolve().parents[2]
D = root / "Resources/vendor/mpv/scripts"
src = (D / "photon-hud.lua").read_text(encoding="utf-8")
def render(revealed, direction):
    lua = lua51.LuaRuntime()
    lua.execute("""package.path='%s/?.lua;'..package.path
OUT={} print=function(s) OUT[#OUT+1]=s end
local noop=function() end
mp={register_script_message=noop,register_event=noop,observe_property=noop,add_key_binding=noop,
 add_periodic_timer=function() return {kill=noop} end,add_timeout=function() return {kill=noop} end,
 get_time=function() return 100 end,get_opt=function() return nil end,get_property_number=function() return nil end,
 get_property_bool=function() return nil end,get_property_native=function() return nil end,get_property=function() return nil end,
 msg=setmetatable({},{__index=function() return noop end}),command=noop,commandv=noop,set_property=noop,utils={}}""" % D)
    lua.globals().SRC = src + "\n__draw=draw_hud __st=HUD_STATE __fold=hud_fold_state"
    lua.execute("local f,e=loadstring(SRC,'=hud'); assert(f,e); f()")
    lua.execute("__st.enabled=true; for k,v in pairs(__fold) do v.revealed=%d v.direction=%d end __draw()" % (revealed, direction))
    out = list(lua.eval("OUT").values())
    assert out and out[-1].startswith("gor-osd:"), out
    return out[-1][len("gor-osd:"):].split("‖")
ok = True
def chk(c, t):
    global ok
    if not c: ok = False; print("FAIL", t)
full = render(99, 1)
chk(len(full) <= 36, "expanded rows %d > 36" % len(full))
widths = []
for r in full:
    key, _, body = r.partition("\t")
    widths.append(len(body))
    chk(len(body) <= 72, "row %r is %d chars > 72" % (r, len(body)))
    chk(r.strip() != "", "empty row")
    low = r.lower()
    for bad in ("nan", "inf ", "nil", "error", "traceback"):
        chk(bad not in low.replace("info", "").replace("fine", "").replace("inertia", ""), "row %r contains %r" % (r, bad))
fold = render(0, -1)
keyed = [r for r in fold if "\t" in r]
extra = [r for r in fold if "\t" not in r]
chk([r.split("\t")[0] for r in keyed] == ["photon", "bright", "sharp", "grain", "chrome", "negativ"], "folded HUD must have the 6 section titles in order, got %r" % fold)
chk(len(extra) <= 1 and all("waiting for photon.lua" in r for r in extra), "folded HUD allows one extra row only: the photon no-data reason row; got %r" % extra)
print("expanded rows=%d max_width=%d; folded rows=%d" % (len(full), max(widths), len(fold)))
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
