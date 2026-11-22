"""Unit tests for the self-test receiving comparator (contract s23).

Synthetic good/bad logs. Run: python3 Tests/DepthAnalysis/test_selftest_check.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))
import selftest_check as sc

EXP = json.load(open(os.path.join(sc.HERE, "selftest_expected.json")))
H64 = "a" * 64

GOOD = [
    "2026-11-09 10:00:01 noise line from the app",
    "gor3d-selftest v1 begin 3D self-test finished",
    "gor3d-selftest v1 stage name=clip_write ms=4210.000 n=1 max_ms=4210.000",
    "gor3d-selftest v1 stage name=prepare_total ms=81200.000 n=1 max_ms=81200.000",
    "gor3d-selftest v1 stage name=render_shot ms=12400.000 n=1 max_ms=12400.000",
    "gor3d-selftest v1 thermal t_ms=0.000 level=0",
    "gor3d-selftest v1 thermal t_ms=30000.000 level=1",
    "gor3d-selftest v1 thermal_peak level=1 transitions=1",
    "gor3d-selftest v1 depth min=0.412 max=38.750 nan=0 inf=0 count=1436400",
    "gor3d-selftest v1 note key=build value=r27 build 1.2",
    "gor3d-selftest v1 note key=clip value=640x360 36f @24.0 synthetic",
    "gor3d-selftest v1 note key=moge_precision value=fp16_used=3 fp16_rejected=0 fp32_used=0",
    "gor3d-selftest v1 note key=compute_plan stream_fp16.mlpackage value=ane=10 gpu=2",
    "gor3d-selftest v1 note key=first_3d_frame_sha256 value=" + H64,
    "gor3d-selftest v1 note key=prepared value=yes",
    "gor3d-selftest v1 end errors=0 total_ms=98120.000",
]

fails = []


def check(name, cond):
    if not cond:
        fails.append(name)
        print("FAIL", name)


# good log passes clean
res = sc.evaluate(GOOD, EXP)
check("good log: one run", len(res) == 1)
check("good log: PASS, no fails", res[0]["verdict"] == "PASS"
      and res[0]["fails"] == [])
check("good log: noise lines ignored", True)

# no self-test lines -> None (CLI exit 2)
check("no lines -> None", sc.evaluate(["hello", "world"], EXP) is None)

# escape round-trip matches the Swift semantics
check("unescape", sc.unescape(r"bad\nthing \\ with = and spaces")
      == "bad\nthing \\ with = and spaces")

# stage over budget
bad = GOOD[:3] + ["gor3d-selftest v1 stage name=prepare_total ms=900000.000 n=1 max_ms=900000.000"] + GOOD[4:]
r = sc.evaluate(bad, EXP)[0]
check("budget fail", r["verdict"] == "FAIL"
      and any("prepare_total" in f and "over budget" in f for f in r["fails"]))

# thermal peak 3
bad = [l if not l.startswith("gor3d-selftest v1 thermal_peak")
       else "gor3d-selftest v1 thermal_peak level=3 transitions=2"
       for l in GOOD]
r = sc.evaluate(bad, EXP)[0]
check("thermal fail", any("thermal peak level 3" in f for f in r["fails"]))

# depth nan + wrong count
bad = [l if not l.startswith("gor3d-selftest v1 depth ")
       else "gor3d-selftest v1 depth min=0.4 max=38.7 nan=5 inf=0 count=1000"
       for l in GOOD]
r = sc.evaluate(bad, EXP)[0]
check("depth fail", any("nan=5" in f for f in r["fails"])
      and any("count 1000 != expected 1436400" in f for f in r["fails"]))

# fp16 rejected -> finding (not fail); no weights at all -> fail
bad = [l.replace("fp16_rejected=0", "fp16_rejected=1") for l in GOOD]
r = sc.evaluate(bad, EXP)[0]
check("fp16 rejected is a note", r["verdict"] == "PASS"
      and any("rejected 1" in f for f in r["findings"]))
bad = [l.replace("fp16_used=3", "fp16_used=0") for l in GOOD]
r = sc.evaluate(bad, EXP)[0]
check("no weights fails", any("no fp16 and no fp32" in f for f in r["fails"]))

# error buckets: gh / kit / coreml load / compute plan / other, verbatim
bad = GOOD[:-1] + [
    "gor3d-selftest v1 error i=0 msg=gh: 403 Bad credentials on releases/download",
    "gor3d-selftest v1 error i=1 msg=kit: content_sha256 mismatch in stream_fp16.mlpackage",
    "gor3d-selftest v1 error i=2 msg=CoreML model load failed: Could not create model",
    "gor3d-selftest v1 error i=3 msg=compute plan: unsupported op on ANE, fallback to GPU",
    "gor3d-selftest v1 error i=4 msg=render: weird<NL>multi-line \\verbatim=",
    "gor3d-selftest v1 end errors=5 total_ms=90000.000",
]
bad = [l.replace("<NL>", "\\n") for l in bad]
r = sc.evaluate(bad, EXP)[0]
got = " | ".join(r["fails"])
check("bucket gh", "error[gh]: gh: 403 Bad credentials" in got)
check("bucket kit", "error[kit]: kit: content_sha256 mismatch" in got)
check("bucket coreml", "error[coreml_load]:" in got)
check("bucket plan", "error[compute_plan]:" in got)
# Swift unescape collapses an unknown escape (\v -> v); \\n -> newline
check("bucket other verbatim", "error[other]: render: weird\nmulti-line verbatim=" in got)

# truncated log: no end line
r = sc.evaluate(GOOD[:-1], EXP)[0]
check("missing end line fails", any("end line" in f for f in r["fails"]))

# hash rule: no recorded reference -> no fail on any 64-hex; recorded
# reference mismatch -> warning only
bad = [l.replace(H64, "b" * 64) for l in GOOD]
r = sc.evaluate(bad, EXP)[0]
check("hash differs without reference: still PASS", r["verdict"] == "PASS")
exp2 = json.loads(json.dumps(EXP))
exp2["first_3d_frame_sha256"]["expect"] = "c" * 64
r = sc.evaluate(bad, exp2)[0]
check("hash differs vs reference: warning not fail", r["verdict"] == "PASS"
      and any("DIFFERS" in f for f in r["findings"]))
bad2 = [l for l in GOOD if "first_3d_frame_sha256" not in l]
r = sc.evaluate(bad2, EXP)[0]
check("hash missing fails", any("sha256 note missing" in f for f in r["fails"]))

# two runs in one log: each evaluated
r = sc.evaluate(GOOD + GOOD, EXP)
check("two runs", len(r) == 2 and all(x["verdict"] == "PASS" for x in r))

# letterbox count derivation: the 16:9 clip crops to 266x150
check("letterbox 640x360 -> 266x150", sc.letterbox(640, 360) == (266, 150))
# square clip: 360x360 -> 154x154; count = 36*154*154
sq = [l.replace("640x360 36f", "360x360 36f") for l in GOOD]
sq = [l.replace("count=1436400", "count=853776") for l in sq]
r = sc.evaluate(sq, EXP)[0]
check("square clip count derived", r["verdict"] == "PASS", )
check("square clip count wrong fails",
      sc.evaluate([l.replace("count=853776", "count=1436400") for l in sq], EXP)[0]["verdict"] == "FAIL")
# no clip note: full-canvas fallback + finding, not a fail
nc = [l for l in GOOD if "note key=clip " not in l]
nc = [l.replace("count=1436400", "count=1474704") for l in nc]
r = sc.evaluate(nc, EXP)[0]
check("no clip note: fallback count + finding", r["verdict"] == "PASS"
      and any("no clip note" in f for f in r["findings"]))

print("test_selftest_check:", "PASS" if not fails else f"{len(fails)} FAIL")
sys.exit(1 if fails else 0)
