#!/usr/bin/env python3
"""block182 constant-mm route: VRDistanceModel.swift witness test.

Mirror/pin test in the crop-suite style: every constant, reason string,
formula and trace key order is PARSED from the real sources (the Swift
file under test and the pinned Lua model), never retyped unchecked;
scenario behavior is computed by a Python mirror driven by the parsed
values; the mutant table proves each mutation of the Swift source turns
a pin or a scenario red. Limits: Swift is compiled on CI only, never run
here; Lua is the pinned source of truth for the formulas.

Run from anywhere: it resolves the gor tree from its own location
(archive/gor/Tests/StereoLook/vr_distance_model_test.py)."""
import json, math, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LUA = (ROOT / "Resources/vendor/mpv/scripts/vr180-look.lua").read_text()
SWIFT_PATH = ROOT / "Sources/gor/Stereo/VRDistanceModel.swift"

checks = []
def check(name, ok):
    checks.append((name, bool(ok)))
    print(("ok  " if ok else "RED ") + name)

def lua_const(name):
    m = re.search(r"local %s\s*=\s*([0-9.eE+-]+)" % re.escape(name), LUA)
    assert m, "Lua constant missing: " + name
    return float(m.group(1))

def swift_const(src, name):
    m = re.search(r"static let %s\s*=\s*([^\n]+)" % re.escape(name), src)
    assert m, "Swift constant missing: " + name
    return eval(m.group(1).strip(), {"__builtins__": {}}, {})

def lua_reasons():
    return set(re.findall(r'"((?:no-input|ok|hold-last-d|no-face-hold-expired|no-osd-size|fov-unavailable))"', LUA))

def mirror(src, scen):
    C = {k: swift_const(src, k) for k in
         ("defaultIpdMM", "referenceDistanceMM", "distanceHoldS", "holdOkBoundaryS",
          "todayBaseIpdMM", "macbookMMPerPx", "shaderShiftLimit", "zoomReferenceFovDeg")}
    # formula pins: the exact expressions must be present in the source
    need = ["shift - excess - ipdNudge",
            "* (ipdEff + sToday) - ipdEff",
            "ipdEff + sTotal <= (d / VRLookDistanceModel.referenceDistanceMM) * (ipdEff + sToday) + 1e-9",
            'age <= VRLookDistanceModel.distanceHoldS',
            'age <= VRLookDistanceModel.holdOkBoundaryS ? "ok" : "hold-last-d"',
            '"no-face-hold-expired"',
            'distInReason = "no-input"',
            '{"k":"vrDistance","reason":"no-osd-size","applied":false}',
            '"CGDisplayScreenSize" : "macbook-227ppi"',
            'var mmPerPxSource = "macbook-227ppi"',
            'd > 0',
            'let m = mmPerPx']
    missing = [n for n in need if n not in src]
    assert not missing, "formula pins missing: %r" % missing
    # trace key order: Swift format literal vs Lua format string
    sw = re.search(r'#"\{"k":"vrDistance","d_mm":.*?\}"#', src, re.S)
    swkeys = re.findall(r'"([a-z_]+)":', sw.group(0)) if sw else None
    lf = re.search(r"'\{\"k\":\"vrDistance\",\"d_mm\":.*?\}'", LUA, re.S)
    lkeys = re.findall(r'"([a-z_]+)":', lf.group(0)) if lf else None
    if not (swkeys and lkeys and swkeys == lkeys):
        raise AssertionError("trace key order mismatch: %r vs %r" % (swkeys, lkeys))

    st = dict(d=None, at=None, reason="no-input", mmpx=None)
    for a in scen.get("accept", []):
        dm, rs, mx, nw = a
        if dm is not None and dm > 0:
            st.update(d=dm, at=nw, reason="ok")
        elif rs and rs != "ok":
            st.update(d=None, reason=rs)
        if mx is not None:
            st["mmpx"] = mx
    osd = scen["osd"]
    if osd <= 0:
        # width<=0 reason mapping PARSED from the Swift source: an explicit
        # reason set in the early-return block wins; otherwise the Outcome
        # default applies. A literal here hid the real Swift difference once.
        g = re.search(r"guard osdWidth > 0 else \{([^}]*)\}", src, re.S)
        assert g, "no-osd-size guard missing in Swift source"
        rset = re.search(r'\.reason\s*=\s*"([a-z-]+)"', g.group(1))
        if rset:
            early_reason = rset.group(1)
        else:
            dflt = re.search(r'public var reason = "([a-z-]+)"', src)
            assert dflt, "Outcome default reason missing in Swift source"
            early_reason = dflt.group(1)
        return dict(applied=None, reason=early_reason, trace='{"k":"vrDistance","reason":"no-osd-size","applied":false}')
    have = (st["mmpx"] or 0) > 0
    mmpx = st["mmpx"] if have else C["macbookMMPerPx"]
    eye = osd / 2 * mmpx; half = eye / 2
    excess = 0.0
    if scen["parallax"]:
        mag = math.tan(math.radians(C["zoomReferenceFovDeg"]) * 0.5) / math.tan(
            math.radians(min(max(scen["fov"] + scen["manual"], scen["fmin"]), scen["fmax"])) * 0.5)
        excess = scen["disp"] * (mag - 1.0) * scen["strength"]
    nudge = scen["nudge"]
    offset = scen["offset"] or 0.0
    s_today = (excess + nudge + 0.0) * half + C["todayBaseIpdMM"] + offset
    ipd_eff = C["defaultIpdMM"] + offset
    d, reason = None, st["reason"]
    if st["d"] is not None and st["at"] is not None:
        age = scen["now"] - st["at"]
        if age <= C["distanceHoldS"]:
            d = st["d"]
            reason = "ok" if age <= C["holdOkBoundaryS"] else "hold-last-d"
        else:
            reason = "no-face-hold-expired"
    s_req, capped, s_cap = s_today, False, None
    if d is not None:
        s_cap = (d / C["referenceDistanceMM"]) * (ipd_eff + s_today) - ipd_eff
        if s_cap < s_today: s_req, capped = s_cap, True
    shift = s_req / half
    infeasible = abs(shift) > C["shaderShiftLimit"]
    if infeasible: shift = min(max(shift, -C["shaderShiftLimit"]), C["shaderShiftLimit"])
    s_total = shift * half
    cap_met = True if d is None else (ipd_eff + s_total <= (d / C["referenceDistanceMM"]) * (ipd_eff + s_today) + 1e-9)
    applied = (shift - excess - nudge) if scen["offset"] is not None else None
    return dict(applied=applied, d=d, reason=reason, capped=capped, s_cap=s_cap,
                infeasible=infeasible, cap_met=cap_met, s_today=s_today,
                s_total=s_total, mmpx=mmpx, src="CGDisplayScreenSize" if have else "macbook-227ppi")

BASE = dict(osd=2560.0, fov=100.0, manual=0.0, fmin=45.0, fmax=120.0,
            nudge=0.0, offset=0.0, parallax=True, disp=-0.4, strength=0.4, now=1000.0)
SCEN = [
    ("macOS constant-mm: no input, verbatim reason, macbook scale", {}, {"accept": []},
     lambda r: r["d"] is None and r["reason"] == "no-input" and r["src"] == "macbook-227ppi"
               and not r["capped"] and r["cap_met"]
               and abs(r["s_today"] - 1.8435921730975418) < 1e-9
               and abs(r["mmpx"] - 25.4/227.0) < 1e-12
               and abs(r["applied"]) < 1e-9),
    ("fov-unavailable clears d and keeps the reason verbatim", {}, {"accept": [(None, "fov-unavailable", None, 999.0)]},
     lambda r: r["d"] is None and r["reason"] == "fov-unavailable"),
    ("fresh d=600 within 0.5 s: ok, no cap (cap above today)", {}, {"accept": [(600.0, None, None, 999.8)]},
     lambda r: r["d"] == 600.0 and r["reason"] == "ok" and not r["capped"]
               and abs(r["s_cap"] - 14.812310607717052) < 1e-9),
    ("ok boundary: age 0.3 s still reads ok (holdOkBoundaryS pin)", {}, {"accept": [(600.0, None, None, 999.7)]},
     lambda r: r["d"] == 600.0 and r["reason"] == "ok"),
    ("close d=300: clamp reduces s, capped, cap_met", {}, {"accept": [(300.0, None, None, 999.8)]},
     lambda r: r["capped"] and r["s_cap"] is not None and r["s_cap"] < r["s_today"] and r["cap_met"]
               and abs(r["s_cap"] + 24.093844696141474) < 1e-9),
    ("hold: 1.0 s reads hold-last-d; 2.5 s reads no-face-hold-expired", {}, {"accept": [(600.0, None, None, 999.0)]},
     lambda r: r["reason"] == "hold-last-d"),
    ("hold boundary: age exactly 2.0 s still holds", {"now": 1001.0}, {"accept": [(600.0, None, None, 999.0)]},
     lambda r: r["d"] == 600.0 and r["reason"] == "hold-last-d"),
    ("hold expired: 2.5 s falls back to the constant-mm rule", {"now": 1001.5}, {"accept": [(600.0, None, None, 999.0)]},
     lambda r: r["d"] is None and r["reason"] == "no-face-hold-expired"),
    ("capped below -0.8: shift clamps and cap_met goes false", {"offset": 500.0}, {"accept": [(200.0, None, None, 999.8)]},
     lambda r: r["capped"] and r["infeasible"] and not r["cap_met"]
               and abs(r["s_cap"] + 137.06256313076096) < 1e-9
               and abs(r["s_total"] + 57.28986784140969) < 1e-9),
    ("sampled display scale selects CGDisplayScreenSize label", {}, {"accept": [(None, None, 0.2, 999.0)]},
     lambda r: r["src"] == "CGDisplayScreenSize" and abs(r["mmpx"] - 0.2) < 1e-12),
    ("mmpx 0 means unavailable: macbook constant", {}, {"accept": [(None, None, 0.0, 999.0)]},
     lambda r: r["src"] == "macbook-227ppi"),
    ("no osd size: early trace, nothing applied", {"osd": 0.0}, {"accept": []},
     lambda r: r["applied"] is None and r["reason"] == "no-osd-size"),
    ("applied base nil without a dial value", {"offset": None}, {"accept": []},
     lambda r: r["applied"] is None),
    ("zero offset and nudge: applied base lands at 0 (shift == excess, l.398)", {}, {"accept": []},
     lambda r: r["applied"] is not None and abs(r["applied"]) < 1e-9),
]

MUTANTS = [
    ("reference distance 500 -> 450", "referenceDistanceMM = 500.0", "referenceDistanceMM = 450.0"),
    ("hold window 2.0 -> 1.0", "distanceHoldS = 2.0", "distanceHoldS = 1.0"),
    ("ok boundary 0.5 -> 0.25", "holdOkBoundaryS = 0.5", "holdOkBoundaryS = 0.25"),
    ("macbook 227 -> 224 ppi", "25.4 / 227.0", "25.4 / 224.0"),
    ("shift limit 0.8 -> 1.0", "shaderShiftLimit = 0.8", "shaderShiftLimit = 1.0"),
    ("default ipd 63 -> 65", "defaultIpdMM = 63.0", "defaultIpdMM = 65.0"),
    ("hold-last-d renamed", '? "ok" : "hold-last-d"', '? "ok" : "hold"'),
    ("cap loses -ipdEff", "* (ipdEff + sToday) - ipdEff", "* (ipdEff + sToday)"),
    ("applied drops - nudge sign", "shift - excess - ipdNudge", "shift - excess + ipdNudge"),
    ("hold boundary <=  ->  <", "age <= VRLookDistanceModel.distanceHoldS", "age < VRLookDistanceModel.distanceHoldS"),
    ("trace key renamed", '"s_today_mm":', '"s_mm":'),
    ("mmpx source label changed", 'var mmPerPxSource = "macbook-227ppi"', 'var mmPerPxSource = "macbook"'),
    ("no-osd early reason renamed", 'o.reason = "no-osd-size"', 'o.reason = "no-input"'),
]

def run(src, label):
    ok_before = len(checks)
    # cross-pins: Swift constants equal the pinned Lua values
    pairs = [("defaultIpdMM", "VR_DEFAULT_IPD_MM"), ("referenceDistanceMM", "VR_REFERENCE_DISTANCE_MM"),
             ("distanceHoldS", "VR_DISTANCE_HOLD_S"), ("macbookMMPerPx", None),
             ("shaderShiftLimit", "VR_SHADER_SHIFT_LIMIT"), ("zoomReferenceFovDeg", "VR_ZOOM_REFERENCE_FOV_DEG")]
    for sw, lu in pairs:
        v = swift_const(src, sw)
        if lu: check("pin %s == Lua %s (%.6f)" % (sw, lu, v), abs(v - lua_const(lu)) < 1e-9)
        else:  check("pin macbookMMPerPx == 25.4/227 (Lua l.349)", abs(v - 25.4/227.0) < 1e-12)
    lua_rs = lua_reasons()
    for r in ("no-input", "ok", "hold-last-d", "no-face-hold-expired", "no-osd-size"):
        check('reason "%s" verbatim in Swift and present in the Lua model' % r,
              ('"%s"' % r) in src and r in lua_rs)
    for name, over, acc, pred in SCEN:
        scen = dict(BASE); scen.update(over); scen["accept"] = acc["accept"]
        try: r = mirror(src, scen)
        except AssertionError as e:
            check("scenario: " + name, False); continue
        check("scenario: " + name, pred(r))
    return len(checks) - ok_before, all(c for _, c in checks[ok_before:])

src = SWIFT_PATH.read_text()
n, allok = run(src, "real")
print("total %d checks: %d green, %d red" % (len(checks), sum(1 for _, c in checks if c), sum(1 for _, c in checks if not c)))
survivors = []
for name, old, new in MUTANTS:
    assert old in src, "mutant base missing: " + name
    checks.clear()
    try:
        run(src.replace(old, new, 1), name)
        caught = not all(c for _, c in checks)
    except AssertionError:
        caught = True
    print(("ok   mutant caught: " if caught else "RED  mutant SURVIVED: ") + name)
    if not caught: survivors.append(name)
print("PASS" if allok and not survivors else "FAIL", "| mutants survived: %d" % len(survivors))
sys.exit(0 if allok and not survivors else 1)
