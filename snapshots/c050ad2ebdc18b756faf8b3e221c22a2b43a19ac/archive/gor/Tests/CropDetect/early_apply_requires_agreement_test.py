#!/usr/bin/env python3
"""Fix A (arch-199ai, v2): an automatic crop decision needs >=3 agreeing non-black frames, never a time budget.

Delivered-3973842 behaviour (owner session 261120-120833, 3840x2160 HDR magnet stream): after 5 samples with
2 non-black members that did not agree, the scan applied the union of the two ("time budget reached, best
available"), cutting into the picture (bounds 350,278-3422,1842 of 3840x2160). v2 removes the time-budget
fallback from the early path AND gates the automatic stream final path the same way: consistent()
(earlyMinCount=3, earlyTolerance=8) is the only automatic decision rule; with no agreement the result is
indecisive, the file stays at the full frame, and the player-side wt retry keeps scanning as the cache grows.
Manual Detect (fresh) keeps the union rule; non-stream sources are unchanged. Static checks run against
Sources/gor/Stereo/Source.swift (relocated SourcePixelCrop.swift section); the replay is a Python mirror."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
SP_ALL = (ROOT / 'Sources/gor/Stereo/Source.swift').read_text()
SP = SP_ALL[SP_ALL.index('// BEGIN relocated SourcePixelCrop.swift '):SP_ALL.index('// END relocated SourcePixelCrop.swift\n')]
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails.append(name)

# -- static: early path ----------------------------------------------------------------------------------------------
check("no time-budget fallback constant", "fallbackMinCount" not in SP)
check("no firstApplyBudget budget for early apply", "firstApplyBudget" not in SP)
check("no 'time budget reached, best available' wording", "time budget reached" not in SP)
check("early consensus comes only from consistent(members)",
      "let consensus: SourcePixelBounds.Bounds? = SourcePixelBounds.consistent(members)" in SP
      and "if best == nil, late," not in SP)
check("overcut guard composes immutably (no best=nil mutation)",
      "let best: SourcePixelBounds.Bounds? = window > 0 && covered < 0.5 * window ? nil : consensus" in SP
      and "{ best = nil }" not in SP)
check("early apply still requires the interim gate (wt, non-stereo, once)",
      "if wt, !stereo, !rgbVeto, !interimSent, let interim, let u0 = best {" in SP)
check("agreement rule unchanged (3 frames, tolerance 8)",
      "static let earlyMinCount = 3" in SP and "static let earlyTolerance = 8" in SP)
check("interim still marked early with confidence < 0", "interim(ir, -1)" in SP)
check("union of all measured frames stays the floor of the early rect (only widens)",
      "let u: SourcePixelBounds.Bounds = all.map { $0.union(u0) } ?? u0" in SP)

# -- static: final path (ops review finding 3) ------------------------------------------------------------------------
check("automatic stream final path is agreement-gated",
      "if wt, !stereo, !rgbVeto, !fresh, SourcePixelBounds.consistent(members) == nil {" in SP)
check("no agreement finishes indecisive (full frame kept, retry keeps scanning)",
      'finish(nil,false,"no agreement among \\(members.count) non-black frames");return' in SP)
check("manual Detect is exempt from the gate (fresh)", "!fresh" in SP)
check("gate sits before the crop rect is built (outward not yet called)",
      SP.index("SourcePixelBounds.consistent(members) == nil {") < SP.index("let c = SourcePixelBounds.outward(b,width:w,height:h,stereo:stereo,topBottom:topBottom)"))

# -- python mirror of the decision ------------------------------------------------------------------------------------
TOL = int(re.search(r"static let earlyTolerance = (\d+)", SP).group(1))
MINC = int(re.search(r"static let earlyMinCount = (\d+)", SP).group(1))
def union(a, b): return (min(a[0],b[0]), min(a[1],b[1]), max(a[2],b[2]), max(a[3],b[3]))
def consistent(members, tol=TOL, minc=MINC):
    if len(members) < minc: return None
    u = members[0]
    for m in members[1:]: u = union(u, m)
    for m in members:
        if abs(m[0]-u[0]) > tol or abs(m[1]-u[1]) > tol or abs(m[2]-u[2]) > tol or abs(m[3]-u[3]) > tol: return None
    return u
def auto_final(members):  # wt, non-stereo, non-rgb, fresh=False
    return None if consistent(members) is None else "apply"

dark_opening = [(350, 278, 3422, 1842), (520, 400, 3300, 1700)]
check("log scenario: 2 non-agreeing members produce no early rect", consistent(dark_opening) is None)
check("log scenario: automatic final is indecisive too (full frame, keep scanning)", auto_final(dark_opening) is None)
body = [(24, 278, 3820, 1858), (26, 280, 3818, 1856), (22, 276, 3822, 1860)]
u = consistent(body)
check("3 agreeing body frames produce a rect", u == (22, 276, 3822, 1860))
check("3 agreeing body frames let the automatic final apply", auto_final(body) == "apply")
check("a single dark first-seconds frame never decides", consistent([(600, 500, 3200, 1600)]) is None)

print("FAILURES: %d" % len(fails))
sys.exit(1 if fails else 0)
