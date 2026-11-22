#!/usr/bin/env python3
"""Fix C (arch-199ai): an automatic reRect may widen the applied crop, never narrow it; manual is unchanged.

Delivered-3973842 behaviour (owner session 261120-120833): the early rect 350,278-3422,1842 applied, the
finished scan measured 24,278-3820,1858 (wider), and the guard kept the early rect
("[crop-guard] kept applied crop: auto re-rect"). The fix lets an automatic reRect land when it widens the
applied rect (less crop); automatic narrowing still keeps the applied crop, and manual reRect is unchanged.
Replay fixture per the assignment: 350..3422 then 24..3820 on 3840x2160, final width must be >= 3796."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
PC = (ROOT / 'Sources/gor/Player/PPController.swift').read_text()
MQ = (ROOT / 'Sources/gor/Player/PPControllerMenuQueries.swift').read_text()
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if ok == False: fails.append(name)

# -- static ----------------------------------------------------------------------------------------------------------
check("widening predicate present at the reRect gate",
      "let widensAppliedCrop = rect.minX <= current.minX && rect.minY <= current.minY && rect.maxX >= current.maxX && rect.maxY >= current.maxY" in PC)
check("gate is mayChange(manual:) OR widening",
      'guard CropInvariant.mayChange(manual: manual) || widensAppliedCrop else { suppress(CropInvariant.keptLine("auto re-rect")); return }' in PC)
check("invariant itself unchanged (auto paths keep the crop unless manual)",
      "static func mayChange(manual: Bool) -> Bool { manual }" in MQ)
check("revert path unchanged (auto revert still kept)",
      'guard CropInvariant.mayChange(manual: manual) else { suppress(CropInvariant.keptLine("auto revert")); return }' in PC)
check("manual same-rect retrigger block untouched", "if sameCrop(current, rect) {" in PC and "explicit Redetect re-triggers the physical chain" in PC)

# -- python mirror of the gate ---------------------------------------------------------------------------------------
def rerect(current, rect, manual):
    widens = rect[0] <= current[0] and rect[1] <= current[1] and rect[2] >= current[2] and rect[3] >= current[3]
    return rect if (manual or widens) else current
W, H = 3840.0, 2160.0
def norm(b): return (b[0]/W, b[1]/H, b[2]/W, b[3]/H)
early = norm((350, 278, 3422, 1842))     # applied by the old early path (kept as state here)
wider = norm((24, 278, 3820, 1858))      # finished scan, wider
final = rerect(early, wider, manual=False)
check("replay: automatic wider reRect lands", final == wider)
check("replay: final width >= 3796 (owner fixture)", round(final[2]*W - final[0]*W) >= 3796)
narrower = norm((500, 400, 3300, 1700))
check("automatic narrowing still keeps the applied crop", rerect(early, narrower, manual=False) == early)
check("manual narrowing applies unchanged", rerect(early, narrower, manual=True) == narrower)
check("manual widening applies unchanged", rerect(early, wider, manual=True) == wider)
partial_wider = norm((300, 300, 3820, 1858))   # wider on x, narrower on y -> not a widen
check("mixed rect (wider one axis, narrower the other) stays kept", rerect(early, partial_wider, manual=False) == early)

print("FAILURES: %d" % len(fails))
sys.exit(1 if fails else 0)
