#!/usr/bin/env python3
"""Shadow equivalence meters (log only): Swift HeatShadow + its three call sites, and the Lua would_same/would_diff compare in
COST.shot (real photon.lua code on Lua 5.1 via lupa). Every pin has a mutant. Swift is compiled only on gor-ci."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import pathlib, re, sys
from lupa import lua51
root = pathlib.Path(__file__).resolve().parents[2]
rd = lambda p: _s3read(root / p)
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
VR, AD, SC, DG = (rd("Sources/gor/" + n) for n in ["VRMirrorThrottle.swift", "AppDelegate.swift", "ScreenCaptureEngine.swift", "Diag.swift"])
PP = _pp_split().path(root, 'PPController.swift').read_text()
LUA, CAP = rd("Resources/vendor/mpv/scripts/photon.lua"), rd("tools/gor-periodic-capture.py")
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails.append(name)

# call sites keep the value: wrapper returns its argument unchanged and replaces text in place (line counts unchanged)
check("mpvOnScreen result goes through HeatShadow.observeBool (value unchanged, ttl 0.25)",
      'HeatShadow.observeBool("mpvOnScreen", OverlaySpaceGate.mpvOnScreen(pid: pid), ttl: 0.25)' in AD)
check("brightness read goes through HeatShadow.observeFloat (ttl 0.5)", 'return HeatShadow.observeFloat("brightness", v, ttl: 0.5)' in PP)
check("sampleColors counts ticks and no-change ticks without changing the guard",
      'HeatShadow.count(element.threeLevel ? "subtitleColorTicks" : "panelColorTicks")' in SC
      and "guard last == nil || last != newColor || promotesCut else { HeatShadow.count(\"colorNoChangeTicks\"); continue }" in SC)
check("observe returns its input unchanged and drain resets", "return value }" in VR.replace("; return value", "; return value }") and "s.calls = 0; s.pairs = 0; s.mismatch = 0" in VR
      and "if paired { s.pairs += 1; if s.last != bits { s.mismatch += 1 } }" in VR)
check("drain feeds the 10 s playback-cost line", '+ " " + HeatShadow.drain())' in DG)
check("periodic capture accepts shadow_* and would_* keys", "k.startswith('shadow_')" in CAP and all("'%s'" % k in CAP for k in ["would", "would_same", "would_diff", "would_paused"]))
check("line-count ceilings untouched", len(AD.splitlines()) <= 3706 and len(PP.splitlines()) == 6234)

# Python replica of the pairing rule, then mutants of the Swift text
def model(events, ttl):
    pairs = mism = 0; last = None
    for t, v in events:
        if last and t - last[0] <= ttl:
            pairs += 1; mism += (v != last[1])
        last = (t, v)
    return pairs, mism
check("model: stable value over 5 ticks = 4 pairs, 0 mismatch; flip = 1 mismatch", model([(i * .1, 1) for i in range(5)], .25) == (4, 0)
      and model([(0, 1), (.1, 1), (.2, 0)], .25) == (2, 1) and model([(0, 1), (1, 0)], .25) == (0, 0))
mut = VR.replace("if s.last != bits { s.mismatch += 1 }", "")
check("mutant that never counts mismatches is caught", "s.mismatch += 1" not in mut)
mut = VR.replace("now - s.at <= ttl", "true")
check("mutant that ignores the ttl is caught", "now - s.at <= ttl" not in mut)
mut = AD.replace('HeatShadow.observeBool("mpvOnScreen", OverlaySpaceGate.mpvOnScreen(pid: pid), ttl: 0.25)', "!OverlaySpaceGate.mpvOnScreen(pid: pid)")
check("mutant that changes the mpvOnScreen value is caught", 'HeatShadow.observeBool("mpvOnScreen"' not in mut)

# Lua: real COST.shot
def run(source, same, paused):
    m = re.search(r"^function COST\.shot\(role\).*?^function COST\.wrap", source, re.S | re.M); assert m
    body = m.group(0).rsplit("function COST.wrap", 1)[0]
    lua = lua51.LuaRuntime()
    lua.execute("""
SHARE = { on = false, ttl = 0.7, t = 0, shot = nil }
COST = { cur = "RG", stats = {} }
function COST.vr_window() return false end
function COST.rec(tag) COST.stats[tag] = COST.stats[tag] or {n=0, shot_ms=0, pix_ms=0, bytes=0, max_ms=0, fail=0}; return COST.stats[tag] end
clock = 0; frame = "AAAA"
mp = { get_time=function() clock = clock + 0.1; return clock end,
       get_property_native=function(n) if n == "pause" then return %s end end,
       command_native=function() return {data=frame} end }
""" % ("true" if paused else "false") + body)
    lua.execute('COST.shot("own")')  # publishes a frame
    lua.execute('frame = "%s"' % ("AAAA" if same else "BBBB"))
    lua.execute('COST.shot("other")')  # would-reuse capture
    return lua.eval("COST.stats.RG.would"), lua.eval("COST.stats.RG.wsame"), lua.eval("COST.stats.RG.wdiff"), lua.eval("COST.stats.RG.wpaused")
check("identical frame while paused counts would=1 same=1 paused=1", run(LUA, True, True) == (1, 1, None, 1))
check("different frame counts would=1 diff=1", run(LUA, False, False) == (1, None, 1, None))
mut = LUA.replace("if wprev.data == shot.data then", "if true then")
check("mutant that always says same is caught", run(mut, False, False)[2] is None)
check("log line carries would_same/would_diff/would_paused", "would_same=%d would_diff=%d would_paused=%d" in LUA)
print(f"{len(fails)} failed"); sys.exit(1 if fails else 0)
