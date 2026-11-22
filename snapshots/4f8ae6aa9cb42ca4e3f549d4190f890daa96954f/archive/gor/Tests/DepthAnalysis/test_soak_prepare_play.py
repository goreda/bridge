#!/usr/bin/env python3
"""s41 step 3 pins: the prepare->play soak holds on the committed generated
table, and CATCHES a corrupted table (mutants), and the emitted 3dfsm lines
feed the Mac-side log checker. Box-independent.

Run: python3 Tests/DepthAnalysis/test_soak_prepare_play.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))
import degrade_fsm as F  # noqa: E402
import soak_prepare_play as sp  # noqa: E402

rules = sp.parse_swift_table()
assert rules, "no rules parsed from committed ThreeDDegradeTable.swift"
assert sp.table_parity(rules), "committed Swift table drifted from degrade_fsm"
print(f"PASS parity: Swift table == degrade_fsm._T ({len(rules)} rules)")

# good table: every seed holds all invariants, all 7 states visited
for seed in (11, 22, 33):
    visits, lines = sp.soak(rules, seed, 4000)
    assert set(v for v, n in visits.items() if n) == set(F.STATES), visits
print("PASS soak 3 seeds x 4000 steps: invariants hold, all 7 states visited")

# mutant 1: a rule targets a bogus state -> I1 catches it
bad = dict(rules)
bad[(F.READY_STEREO, F.EV_UNCOVERED)] = F.Transition("BOGUS", (), "x")
try:
    for seed in range(1, 60):
        sp.soak(bad, seed, 4000)
    raise AssertionError("mutant-1 not caught")
except sp.Violation as v:
    assert "I1" in str(v), v
print("PASS mutant bogus-state: caught (I1)")

# mutant 2: a forbidden action (would interrupt playback) -> I2 catches it
bad = dict(rules)
bad[(F.LGD_HOLD, F.EV_LGD_TIMEOUT)] = F.Transition(
    F.FLAT_DEGRADED, ("act_mpv_restart",), "x")
try:
    for seed in range(1, 60):
        sp.soak(bad, seed, 4000)
    raise AssertionError("mutant-2 not caught")
except sp.Violation as v:
    assert "I2" in str(v), v
print("PASS mutant forbidden-action: caught (I2)")

# mutant 3: stereo action landing flat -> I3 catches it
bad = dict(rules)
bad[(F.PREPARING_FLAT, F.EV_COVERED)] = F.Transition(
    F.FLAT_DEGRADED, ("act_play_stereo",), "x")
try:
    for seed in range(1, 60):
        sp.soak(bad, seed, 4000)
    raise AssertionError("mutant-3 not caught")
except sp.Violation as v:
    assert "I3" in str(v), v
print("PASS mutant stereo-landing-flat: caught (I3)")

# mutant 4: sever the prepare->ready edges -> I5 liveness catches it
bad = {k: v for k, v in rules.items()
       if k not in ((F.PREPARING_FLAT, F.EV_COVERED),
                    (F.PREPARING_FLAT, F.EV_PREPARE_DONE),
                    (F.PREP_BLOCKED, F.EV_PREPARE_DONE))}
try:
    for seed in range(1, 60):
        sp.soak(bad, seed, 4000)
    raise AssertionError("mutant-4 not caught")
except sp.Violation as v:
    assert "I5" in str(v), v
print("PASS mutant no-recovery: caught (I5)")

# I4: soak lines feed mac_log_check's fsm family cleanly
visits, lines = sp.soak(rules, 7, 3000)
fam = sp.mlc.f_fsm("run", lines, None)
assert fam.status == "PASS", fam.lines[:3]
print(f"PASS I4: {len(lines)} emitted lines -> f_fsm PASS")

# CLI smoke: rc 0 on the real table
rc = sp.main(["--steps", "2000", "--seeds", "1"])
assert rc == 0, rc
print("PASS CLI rc 0")

print("soak_prepare_play: all pins hold")
