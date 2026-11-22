#!/usr/bin/env python3
"""photon.lua owner option vr-cheap-chroma (real source, Lua 5.1 stub): OFF by default means set_property is never called;
ON + VR window sets cscale=bilinear once; switching off or leaving VR restores the original filter.
Pixel cost of the option is measured separately on mpv 0.42 (Linux): see the PR text, chroma-only change, luma max diff 20 on a test pattern."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
m = re.search(r"^COST\.cc = \{.*?^function COST\.vr_cheap_chroma_tick\(\).*?^end\n", src, re.S | re.M); assert m
lua = lua51.LuaRuntime()
lua.execute("""
sets = {}; props = {cscale = "lanczos"}; ud = nil; VR = false; opt = nil
COST = {}; function COST.vr_window() return VR end
mp = { get_property_native = function(n) if n == "user-data/gor/vr-cheap-chroma" then return ud end end,
       get_opt = function(n) if n == "gor-vr-cheap-chroma" then return opt end end,
       get_property = function(n) return props[n] end,
       set_property = function(n, v) sets[#sets+1] = n .. "=" .. v; props[n] = v; return true end }
""" + m.group(0))
def tick(): lua.execute("COST.vr_cheap_chroma_tick()")
n = lambda: lua.eval("#sets")
for _ in range(5): tick()
default_calls = n()
lua.execute("VR = true");  [tick() for _ in range(5)]; vr_flag_off = n()
lua.execute("ud = true");  [tick() for _ in range(5)]; on_calls = n(); on_val = lua.eval("props.cscale")
lua.execute("ud = false"); tick(); off_val = lua.eval("props.cscale")
lua.execute("ud = true");  tick(); lua.execute("VR = false"); tick(); close_val = lua.eval("props.cscale"); close_calls = n()
lua.execute("ud = nil; VR = false"); tick()
lua.execute("opt = 'no'; VR = true"); [tick() for _ in range(3)]; opt_no = n()
lua.execute("opt = 'yes'"); tick(); opt_yes_val = lua.eval("props.cscale"); lua.execute("opt = nil"); tick(); opt_off_val = lua.eval("props.cscale")
print("script-opt: no=%d extra sets, yes=%s, removed=%s" % (opt_no - close_calls, opt_yes_val, opt_off_val))
print("default calls=%d, VR with flag off=%d, ON sets=%d (%s), flag off restores=%s, VR close restores=%s" % (default_calls, vr_flag_off, on_calls, on_val, off_val, close_val))
ok = default_calls == 0 and vr_flag_off == 0 and on_calls == 1 and on_val == "bilinear" and off_val == "lanczos" and close_val == "lanczos" and opt_no == close_calls and opt_yes_val == "bilinear" and opt_off_val == "lanczos"
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
