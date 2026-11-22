#!/usr/bin/env python3
"""s40 pins: mac_log_check per-family verdicts on a synthetic Mac-like
good log and on mutants (missing family / bad format / policy breach).

Box-independent (no models, no clips): the good log is embedded.
Run: python3 Tests/DepthAnalysis/test_mac_log_check.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))
import mac_log_check as mlc  # noqa: E402

EXP = json.load(open(mlc.stc.EXPECTED))

GOOD = """[2026-11-09T10:00:00] gor3d-selftest v1 begin gor3d\\ndev\\nM1\\nselftest
[2026-11-09T10:00:00] gor3d-selftest v1 note key=clip value=640x360 36f @24.0 live
[2026-11-09T10:00:01] gor3d-selftest v1 stage name=clip_write ms=1200.0 n=1 max_ms=1200.0
[2026-11-09T10:00:30] gor3d-selftest v1 stage name=prepare_total ms=29000.0 n=1 max_ms=29000.0
[2026-11-09T10:00:32] gor3d-selftest v1 stage name=render_shot ms=4100.0 n=1 max_ms=4100.0
[2026-11-09T10:00:32] gor3d-selftest v1 note key=moge_precision value=fp16_used=3 fp32_used=0 fp16_rejected=0
[2026-11-09T10:00:32] gor3d-selftest v1 depth min=0.5 max=98000.0 nan=0 inf=0 count=1436400
[2026-11-09T10:00:32] gor3d-selftest v1 note key=first_3d_frame_sha256 value=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
[2026-11-09T10:00:32] gor3d-selftest v1 note key=rt_config value=fps=24.0 vr180=false depth_rate=24.0 surround_opt=false
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=vda ms=9.5 n=36 max_ms=14.2
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=moge ms=31.0 n=3 max_ms=35.8
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=upsample ms=0.004 n=36 max_ms=0.01
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=surround ms=0.41 n=36 max_ms=0.9
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=render ms=0.012 n=36 max_ms=0.03
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=vt_decode ms=1.3 n=36 max_ms=2.2
[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=vt_encode ms=1.1 n=36 max_ms=1.9
[2026-11-09T10:00:33] gor3d-selftest v1 thermal level=0 t_ms=0
[2026-11-09T10:00:33] gor3d-selftest v1 thermal level=1 t_ms=25000
[2026-11-09T10:00:33] gor3d-selftest v1 thermal_peak level=1 transitions=1
[2026-11-09T10:00:33] gor3d-selftest v1 note key=jitter_rel value=0.009 (healthy)
[2026-11-09T10:00:33] gor3d-selftest v1 note key=render_key_v4 value=v4|mlbw_l2_inpaint_video|comfort|ipd0.063|sf1.0|vr180|2.0|720|hevc|True|75.0|True|abcdef123456
[2026-11-09T10:00:33] 3dfsm from=INIT ev=probe_ok to=PREPARING_FLAT act=act_play_flat|act_prepare_start note=playback starts in 2D immediately
[2026-11-09T10:00:33] 3dfsm from=READY_STEREO ev=playhead_uncovered to=LGD_HOLD act=act_hold_lgd note=hold
[2026-11-09T10:00:33] gor3d-selftest v1 end errors=0
"""


def statuses(log):
    fams = mlc.check_log(log.splitlines(), EXP)[0]
    return {f.name.split(" ")[0]: f.status for f in fams}


def fam(log, prefix):
    fams = mlc.check_log(log.splitlines(), EXP)[0]
    return [f for f in fams if f.name.startswith(prefix)][0]


# good log: every family PASS
st = statuses(GOOD)
assert all(v == "PASS" for v in st.values()), st
print(f"PASS good log: {len(st)} families all PASS")

# mutant: rtstage surround missing -> family 4+5 MISSING, rest PASS
m = GOOD.replace("[2026-11-09T10:00:33] gor3d-selftest v1 rtstage name=surround ms=0.41 n=36 max_ms=0.9\n", "")
st = statuses(m)
assert st["4+5"] == "MISSING" and st["1"] == "PASS" and st["8"] == "PASS", st
print("PASS mutant: missing rtstage family -> MISSING")

# mutant: depth line absent -> MISSING; wrong count -> FAIL; nan -> FORMAT/FAIL
m = GOOD.replace("[2026-11-09T10:00:32] gor3d-selftest v1 depth min=0.5 max=98000.0 nan=0 inf=0 count=1436400\n", "")
assert statuses(m)["8"] == "MISSING"
m = GOOD.replace("count=1436400", "count=1400000")
assert statuses(m)["8"] == "FAIL"
m = GOOD.replace("min=0.5", "min=-0.5")
assert statuses(m)["8"] == "FAIL"
print("PASS mutant: depth missing / wrong count / negative min")

# mutant: sha uppercase -> FORMAT-BUG; absent -> MISSING
m = GOOD.replace("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                 "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF")
assert statuses(m)["9"] == "FORMAT-BUG"
m = "\n".join(l for l in GOOD.splitlines() if "first_3d_frame_sha256" not in l)
assert statuses(m)["9"] == "MISSING"
print("PASS mutant: sha format / absent")

# mutant: thermal peak 2 -> FAIL (s19 policy); thermal_peak absent -> MISSING
m = GOOD.replace("thermal_peak level=1 transitions=1", "thermal_peak level=2 transitions=2")
assert statuses(m)["6"] == "FAIL"
m = "\n".join(l for l in GOOD.splitlines() if "thermal_peak" not in l)
assert statuses(m)["6"] == "MISSING"
print("PASS mutant: thermal policy breach / absent")

# mutant: no 3dfsm -> MISSING; broken 3dfsm line -> FORMAT-BUG
m = "\n".join(l for l in GOOD.splitlines() if "3dfsm " not in l)
assert statuses(m)["12"] == "MISSING"
m = GOOD.replace("3dfsm from=INIT ev=probe_ok to=PREPARING_FLAT",
                 "3dfsm from=INIT to=PREPARING_FLAT")
assert statuses(m)["12"] == "FORMAT-BUG"
m = GOOD.replace("ev=probe_ok", "ev=bogus_event")
assert statuses(m)["12"] == "FORMAT-BUG"
print("PASS mutant: 3dfsm missing / broken / unknown event")

# mutant: render key malformed; jitter absent; precision all zero
m = GOOD.replace("v4|mlbw_l2_inpaint_video|comfort|ipd0.063|sf1.0|vr180|2.0|720|hevc|True|75.0|True|abcdef123456",
                 "v2|comfort|vr180")
assert statuses(m)["11"] == "FORMAT-BUG"
m = "\n".join(l for l in GOOD.splitlines() if "jitter_rel" not in l)
assert statuses(m)["10"] == "MISSING"
m = GOOD.replace("fp16_used=3 fp32_used=0", "fp16_used=0 fp32_used=0")
assert statuses(m)["7"] == "FAIL"
print("PASS mutant: render key / jitter / precision")

# mutant: an error line buckets and FAILs family 13
m = GOOD.replace("gor3d-selftest v1 end errors=0",
                 "gor3d-selftest v1 error i=0 msg=kit_manifest content_sha256 mismatch\n"
                 "[2026-11-09T10:00:34] gor3d-selftest v1 end errors=1")
st = statuses(m)
assert st["13"] == "FAIL" and st["1"] == "PASS", st
f13 = fam(m, "13")
assert any("error[kit]" in l for l in f13.lines), f13.lines
print("PASS mutant: error line buckets [kit], lifecycle stays PASS")

# mutant: end errors mismatch -> lifecycle FAIL
m = GOOD.replace("end errors=0", "end errors=2")
assert statuses(m)["1"] == "FAIL"
print("PASS mutant: truncated-error lifecycle")

# CLI smoke: rc 0 on good, rc 1 on mutant, rc 2 on empty
d = tempfile.mkdtemp(prefix="s40_")
g = os.path.join(d, "good.log")
open(g, "w").write(GOOD)
CHK = os.path.join(HERE, "..", "..", "tools", "depth_analysis", "mac_log_check.py")
r = subprocess.run([sys.executable, CHK, g], capture_output=True, text=True)
assert r.returncode == 0 and "MAC-LOG PASS" in r.stdout, r.stdout
assert "4+5 rtstage" in r.stdout and "ratio" in r.stdout  # numbers shown
bad = os.path.join(d, "bad.log")
open(bad, "w").write(GOOD.replace("thermal_peak level=1 transitions=1",
                                  "thermal_peak level=3 transitions=2"))
r = subprocess.run([sys.executable, CHK, bad], capture_output=True, text=True)
assert r.returncode == 1 and "MAC-LOG FAIL" in r.stdout, r.stdout
empty = os.path.join(d, "empty.log")
open(empty, "w").write("[2026-11-09T10:00:00] ordinary gor log line\n")
r = subprocess.run([sys.executable, CHK, empty], capture_output=True, text=True)
assert r.returncode == 2, r.stdout
print("PASS CLI smoke (rc 0 / 1 / 2, numbers in output)")

print("PASS test_mac_log_check")
