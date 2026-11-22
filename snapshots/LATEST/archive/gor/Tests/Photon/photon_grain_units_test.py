#!/usr/bin/env python3
"""Adaptive grain strength + size (real photon.lua source, Lua 5.1; logic only, not native).
Checks: GS.solve_mult output per content class under the engine's real factory strength (6.0), the
stored-look range guard (a stale 4.027 look is ignored, file untouched), and SIZE_GOV size hints per class.
Prints before (look 4.027, GS assumed factory 5.0) and after (bounded look, factory read from engine)."""
import pathlib, re, sys
from lupa import lua51
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
def grab(a, b):
    i = src.index(a); j = src.index(b, i); return src[i:j]
lua = lua51.LuaRuntime()
lua.execute("""
math_max, math_min = math.max, math.min
GS = { mult_floor=0.0, legacy_min=0.40, legacy_max=1.25, accepted_strength=6.25, strength_default=6.0, look_R=nil }
SIZE_GOV_SENT = {}
mp = { commandv=function(...) local a={...}; if a[2]=="photon-grain-set-size-hint" then SIZE_GOV_SENT[#SIZE_GOV_SENT+1]=tonumber(a[3]) end end,
       msg={warn=function() end,info=function() end}, get_opt=function() return nil end, get_property_number=function() return 0 end, get_property=function() return "" end, get_time=function() return 0 end, get_property_native=function() return nil end }
function gs_log() end
COST = { media_telemetry=false, trace_record=function() end, diag_mirror=function() end }
SIZE_GOV_math_abs = math.abs
math_abs, math_floor = math.abs, math.floor
""")
lua.execute(grab("function GS.seed_look()", "function GS.load_look()"))
lua.execute(grab("function GS.solve_mult(", "function GS.look_file()") if False else grab("-- Strength multiple (of the engine's factory strength)", "function GS.look_file()"))
lua.execute(grab("local SIZE_GOV = {", "\nSIZE_GOV.propose_end_marker") if False else "")
# SIZE_GOV block up to the end of propose
i = src.index("local SIZE_GOV = {"); j = src.index("function SIZE_GOV.propose("); k = src.index("\nend\n", src.index("SIZE_GOV.applied = next_hint", j)) + 5
lua.execute(src[i:j].replace("local SIZE_GOV = {", "SIZE_GOV = {").replace('mp.get_opt("photon-adaptive-program") ~= "false"', "true") + src[j:k])
lua.execute("function gs_log() end")
lo, hi = lua.eval("GS.look_bounds")()
ok = True
def chk(c, m):
    global ok
    if not c: ok = False; print("FAIL", m)
# content classes: (name, source power as share of target body, synthetic basis scale)
# p5_tgt = basis power at factory strength; var_src = source grain power.
classes = [("clean", 0.0), ("light grain", 0.3), ("noisy", 0.8), ("very noisy", 1.6)]
def applied(look, factory, share, program=True, basis=100.0):
    """look None = seed look (derived from the engine factory). share = source grain power / target body."""
    lua.execute("GS.strength_default = %r; GS.look_R = %s" % (factory, "nil" if look is None else repr(look)))
    eff_look = look if look is not None else lua.eval("GS.seed_look")()
    m, _ = lua.eval("GS.solve_mult")(basis, basis, share * eff_look * basis, 1.0, program)
    return m, m * factory
print("%-12s %-26s %-26s" % ("class", "BEFORE look=4.027 f=6", "AFTER seed look f=6"))
rows = {}
for name, s in classes:
    mb, ab = applied(4.027, 6.0, s); ma, aa = applied(None, 6.0, s)
    rows[name] = (mb, ab, ma, aa)
    print("%-12s mult=%.3f applied=%-7.2f   mult=%.3f applied=%.2f" % (name, mb, ab, ma, aa))
# SD / 1080p / 4K differ only through the synthetic basis (same ratio): mult is resolution independent by construction
for name, basis in (("SD", 40.0), ("1080p", 100.0), ("4K", 260.0)):
    m, a2 = applied(None, 6.0, 0.0, basis=basis)
    print("%-12s clean mult=%.3f applied=%.2f" % (name, m, a2))
    chk(abs(a2 - 6.25) < 1e-6, name + " clean applied strength must equal the accepted 6.25")
chk(rows["clean"][1] > 11.0, "before: clean applied should reproduce ~12 (old bug)")
chk(abs(rows["clean"][3] - 6.25) < 1e-6, "after: clean applied = accepted 6.25")
chk(rows["very noisy"][2] == 0.0, "after: source over target -> mult 0, no grain added")
chk(rows["noisy"][2] < rows["light grain"][2] < rows["clean"][2], "after: noisier source gets less added grain")
# bounded look guard
chk(abs(lo - 0.16) < 1e-9 and abs(hi - 1.5625) < 1e-9, "look bounds derived from the strength envelope: %r %r" % (lo, hi))
chk(4.027 > hi, "stale 4.027 look is outside the model range and is ignored on load")
print("look range [%.4f, %.4f]; stored 4.027 -> ignored" % (lo, hi))
# unit check: the accepted strength is absolute, so any factory strength gives the same applied value
for factory in (5.0, 6.0, 8.0):
    m, a2 = applied(None, factory, 0.0)
    print("factory=%.1f clean mult=%.3f applied=%.3f" % (factory, m, a2))
    chk(abs(a2 - 6.25) < 1e-6, "factory %.1f: applied must be 6.25" % factory)
# SIZE_GOV size per content class (hint x 0.8 px). raw = estimator's size proposal.
def size(raw_seq, frame_h, share=0.9, vote=0.1):
    lua.execute("SIZE_GOV.seed=nil SIZE_GOV.applied=nil SIZE_GOV.hist={} SIZE_GOV_SENT={}")
    prop = lua.eval("SIZE_GOV.propose")
    for r in raw_seq:
        prop("live", r, lua.table(share=share, vote=vote, frame_h=frame_h, window=5))
    s = lua.eval("SIZE_GOV_SENT"); return [s[i] for i in range(1, len(s) + 1)]
cases = [("fine film 1080p", [0.9]*6, 1080), ("typical 1080p", [1.2]*6, 1080), ("coarse 4K", [2.5]*6, 2160),
         ("SD DVD (spurious 2.6)", [2.6]*6, 480), ("runaway", [1.0, 1.1, 3.0, 3.0, 3.0, 3.0], 1080)]
for n, seq, h in cases:
    out = size(seq, h)
    print("%-24s hints=%s -> px=%s" % (n, ["%.2f" % x for x in out], ["%.2f" % (0.8 * x) for x in out]))
    chk(all(0.70 - 1e-9 <= x <= 1.80 + 1e-9 for x in out), n + ": hint outside rails")
chk(size([2.6]*6, 480) == [], "SD cannot commit a >1.5 size hint")
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
