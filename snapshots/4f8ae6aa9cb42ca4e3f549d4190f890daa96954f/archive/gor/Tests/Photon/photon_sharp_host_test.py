#!/usr/bin/env python3
"""photon-sharp host-side amount by source/output raster (real ps_refresh_adaptive, Lua 5.1; logic only, not native).
Characterizes the 118g rule with the 189p P3 cap for sources under 1440 (480: 0.675, 720: 0.55, 1080: 0.40) and asserts its invariants: native size = 1.0, multiplier within rails [0.5,2.0],
monotonic in output/source ratio, adaptive OFF = 1.0. Prints the baked AMOUNT range and the 480p/4K ratio the owner
question (118g vs P3) turns on."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon-sharp.lua").read_text(encoding="utf-8")
def num(name):
    return float(re.search(r"local %s\s*=\s*([0-9.]+)" % name, src).group(1))
bmin, bmax = num("PHOTON_SHARP_BASE_AMOUNT_MIN"), num("PHOTON_SHARP_BASE_AMOUNT_MAX")
m = re.search(r"local ps_adaptive_mode = .*?^end\n", src, re.S | re.M); assert m
lua = lua51.LuaRuntime()
lua.execute('mp = { get_opt = function() return nil end }\nSRC, OUT = 0, 0\ncommon = { adaptive_rasters = function() return SRC, OUT, "t", OUT, 0, 0 end }\n' + m.group(0).replace('mp.get_opt("photon-adaptive-program") ~= "false"', "true") + "\nfunction mult(s, o, on) SRC, OUT = s, o; ps_adaptive_mode = on; ps_refresh_adaptive(); return ps_multiplier end")
mult = lua.eval("mult")
ok = True
def chk(c, t):
    global ok
    if not c: ok = False; print("FAIL", t)
def headroom(h): return 1.15 if h < 720 else (1.10 if h <= 1088 else 1.05)
rows = {}
print("%-8s %-8s %-6s %-22s" % ("src", "out", "mult", "AMOUNT x headroom (bright..dark)"))
for s in (480, 720, 1080, 2160):
    for o in (720, 1080, 2160):
        k = mult(s, o, True); rows[(s, o)] = k
        print("%-8d %-8d %-6.3f %.2f .. %.2f" % (s, o, k, bmin * k * headroom(s), bmax * k * headroom(s)))
        if s >= 1440: chk(0.5 <= k <= 2.0, "rails %d->%d" % (s, o))   # sources under 1440 sit under their P3 ceilings (189p, R1)
for s in (480, 720, 1080, 2160):
    cap = 0.675 if s < 720 else (0.55 if s < 1080 else (0.40 if s < 1440 else None))   # 189p + R1 P3 ceilings
    if cap is None: chk(abs(mult(s, s, True) - 1.0) < 1e-9, "native size must be 1.0 (%d)" % s)
    else: chk(all(abs(mult(s, o, True) - cap) < 1e-9 for o in (720, 1080, 2160)), "source %d capped at its P3 ceiling %.3f" % (s, cap))
    chk(mult(s, 720, True) <= mult(s, 1080, True) <= mult(s, 2160, True), "monotonic in output (%d)" % s)
    chk(mult(s, s, False) == 1.0, "adaptive off must be 1.0")
a480 = bmin * rows[(480, 1080)] * headroom(480); a4k = bmin * rows[(2160, 2160)] * headroom(2160)
print("480p@1080 vs 4K@2160 amount ratio (bright floor): %.2f" % (a480 / a4k))
chk(rows[(480, 2160)] == 0.675, "480p on 2160 output is capped by P3 (189p), not the 2.0 rail")
chk(rows[(720, 2160)] == 0.55 and rows[(1080, 2160)] == 0.40, "720p/1080p are capped by the R1 P3 ceilings (sharp_outcome_r1.tsv), not the 118g response")
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
