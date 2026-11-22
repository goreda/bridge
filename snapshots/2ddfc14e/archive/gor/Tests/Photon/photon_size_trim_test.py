#!/usr/bin/env python3
"""R3 (photon queue): grain-size governor at SD (frame_h 480) from the real photon.lua SIZE_GOV.propose (Lua 5.1; LOGIC ONLY, Lua-stub, not native).
Checks, over 300 deterministic proposal sequences (raw 0.05..8, assorted share/vote) at frame_h 480:
  - a committed size hint is always inside the product rails [hard_min, hard_max] = [0.70, 1.80] and never above 1.5 (the SD class rule: raw > 1.5 at frame_h < 700 is held)
  - every proposal writes exactly one PROPOSE line and ends in exactly one terminal line (COMMIT/HOLD) with source= and a non-empty reason=, so the trim log names where
    every value came from; each COMMIT line's next= equals the hint published to the receiver (4 decimals)
  - raw > 1.5 at frame_h 480 -> HOLD reason=sdclass; the same at 700 is not held by sdclass (class boundary)
  - non-live sources, adaptive off, and invalid values (nan, 0, negative, inf) never publish and log unmeasured-source / adaptive-off / invalid."""
import os, pathlib, re, sys, tempfile
from lupa import lua51
os.environ["HOME"] = tempfile.mkdtemp()
src = (pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts/photon.lua").read_text(encoding="utf-8")
i = src.index("local SIZE_GOV = {"); j = src.index("function SIZE_GOV.propose("); k = src.index("\nend\n", src.index("SIZE_GOV.applied = next_hint", j)) + 5
chunk = src[i:k].replace("local SIZE_GOV = {", "SIZE_GOV = {", 1)
def mk(program_on=True):
    lua = lua51.LuaRuntime()
    lua.execute("""
math_max, math_min, math_abs, math_floor = math.max, math.min, math.abs, math.floor
LINES, SENT = {}, {}
mp = { commandv=function(...) local a={...}; if a[2]=="photon-grain-set-size-hint" then SENT[#SENT+1]=a[3] end end,
       msg={warn=function() end,info=function() end}, get_opt=function() return nil end, get_property_number=function() return 0 end,
       get_property=function() return "" end, get_time=function() return 0 end, command_native=function() return nil end }
COST = { media_telemetry=false, trace_record=function() end, diag_mirror=function(n, l) if n == "grain-size.log" then LINES[#LINES+1] = l end end }
""" + chunk.replace('mp.get_opt("photon-adaptive-program") ~= "false"', "true" if program_on else "false"))
    lua.execute("SIZE_GOV.program_on = %s" % ("true" if program_on else "false"))
    return lua
LINE = re.compile(r"\b(PROPOSE|HOLD|SEED|COMMIT) source=(\S+) proposed=(\S+) prev=(\S+) next=(\S+) share=(\S+) vote=(\S+) reason=(.*)$")
def propose(lua, seq, frame_h, share, vote, source="live"):
    lua.execute("LINES = {} SENT = {} SIZE_GOV.seed=nil SIZE_GOV.applied=nil SIZE_GOV.hist={} SIZE_GOV.hold_rep={key=nil,n=0}")
    prop = lua.eval("SIZE_GOV.propose"); per = []
    for r in seq:
        n0 = len(list(lua.eval("LINES").values()))
        prop(source, r, lua.table(share=share, vote=vote, frame_h=frame_h, window=5))
        L = list(lua.eval("LINES").values())[n0:]
        per.append([LINE.search(x).groups() + (x,) for x in L if LINE.search(x)])
    sent = [float(x) for x in lua.eval("SENT").values()]
    return per, sent
ok = True; nfail = 0
def chk(c, t):
    global ok, nfail
    if not c:
        ok = False; nfail += 1
        if nfail < 15: print("FAIL", t)
seed = 12345
def rnd():
    global seed; seed = (seed * 1103515245 + 12345) % (2 ** 31); return seed / 2 ** 31
lua = mk(); commits = holds = 0; reasons = {}
for n in range(300):
    seq = [round(0.05 + rnd() ** 2 * 7.95, 3) for _ in range(8)]
    if n % 3 == 0: seq = [seq[0]] * 8                       # steady stream
    share, vote = [0.9, 0.6, 0.3, 0.9][n % 4], [0.1, 0.1, 0.5, 0.3][n % 4]
    per, sent = propose(lua, seq, 480, share, vote)
    ci = 0
    for r, lines in zip(seq, per):
        kinds = [l[0] for l in lines]
        chk(kinds.count("PROPOSE") == 1, "one PROPOSE per proposal %s" % kinds)
        term = [l for l in lines if l[0] in ("COMMIT", "HOLD")]
        chk(len(term) == 1, "exactly one terminal line, got %s for raw=%s" % (kinds, r))
        if not term: continue
        kind, source, proposed, prev, nxt, sh, vo, reason, _ = term[0]
        chk(source == "live" and reason.strip() not in ("", "-"), "terminal line names source and reason: %s" % (term[0][-1][-120:]))
        reasons[reason.split()[0]] = reasons.get(reason.split()[0], 0) + 1
        if kind == "COMMIT":
            commits += 1; v = float(nxt)
            chk(0.70 - 1e-9 <= v <= 1.50 + 1e-9, "commit %s outside [0.70,1.50] at SD (raw=%s)" % (v, r))
            chk(ci < len(sent) and abs(sent[ci] - v) < 5e-5, "published hint equals logged next (%s vs %s)" % (sent[ci] if ci < len(sent) else None, v)); ci += 1
        else:
            holds += 1
            if r > 1.5 and r == r: chk(reason.split()[0] == "sdclass", "raw %s > 1.5 at 480 must be HOLD sdclass, got %s" % (r, reason))
    chk(ci == len(sent), "no hint published without a COMMIT line")
print("300 sequences at frame_h 480: commits=%d holds=%d reasons=%s" % (commits, holds, dict(sorted(reasons.items()))))
chk(commits > 100 and "sdclass" in reasons, "sweep exercises both commits and the SD hold")
# class boundary: 1.6 at 699 is held as sdclass, at 700 it is not
for h, held in ((699, True), (700, False)):
    per, sent = propose(lua, [1.6] * 3, h, 0.9, 0.1)
    why = [l[7].split()[0] for p in per for l in p if l[0] == "HOLD"]
    chk(("sdclass" in why) == held, "frame_h %d raw 1.6: sdclass hold expected=%s got %s" % (h, held, why))
# invalid values, non-live source, adaptive off
for seq in ([float("nan")], [0.0], [-1.0], [float("inf")]):
    per, sent = propose(lua, seq, 480, 0.9, 0.1)
    chk(sent == [] and any(l[0] == "HOLD" and l[7].startswith("invalid") for l in per[0]), "invalid %s -> HOLD invalid, no publish" % seq)
per, sent = propose(lua, [1.0], 480, 0.9, 0.1, source="neutral")
chk(sent == [] and any(l[7].startswith("unmeasured-source") for l in per[0]), "non-live source: unmeasured-source, no publish")
off = mk(program_on=False); per, sent = propose(off, [1.0, 1.1], 480, 0.9, 0.1)
chk(sent == [] and all(any(l[7].startswith("adaptive-off") for l in p) for p in per), "adaptive off: no publish, logged adaptive-off")
print("PASS" if ok else "FAIL (%d)" % nfail); sys.exit(0 if ok else 1)
