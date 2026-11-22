"""s41 step 3: Linux soak of the full prepare->play state path.

Drives the degradation FSM through long randomized fault-injected event
streams using THE COMMITTED GENERATED TABLE (Sources/gor/
the DegradeTable span inside ThreeDDegrade.swift, parsed back) - not the Python source - so any
drift between the shipped Swift table and degrade_fsm.py is caught here.

Environment model (fault injector): playhead coverage, LGD hold timer,
shot-error streak, disk (ENOSPC), thermal gate, user 3D toggle, source
changes, quit/relaunch, kit/probe outcomes. Events are generated
consistent with the model; the table (plus the documented "unlisted pair
= ignored self-loop" rule) produces transitions and actions.

Invariants measured every step:
  I1 state is always one of STATES
  I2 no forbidden action (mpv_restart/recreate/seek/pause_playback/audio)
     is ever emitted - playback is never interrupted
  I3 act_play_stereo only when landing in READY_STEREO;
     act_play_flat* only when landing in a flat/hold state
  I4 every emitted 3dfsm log line reparses through mac_log_check's f_fsm
     (the Mac-side checker must read what the soak emits)
  I5 READY_STEREO stays reachable from the current state with all faults
     cleared (liveness: recovery is never designed out)
  I6 committed Swift table == degrade_fsm._T (parity, checked once)

CLI: python3 soak_prepare_play.py [--steps N] [--seeds S [S ...]]
Exit 0 = all invariants held; 1 = a violation (prints the first).
"""
import argparse
import random
import re
import sys
from collections import deque
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import degrade_fsm as F  # noqa: E402
import mac_log_check as mlc  # noqa: E402

SWIFT_TABLE = HERE.parent.parent / "Sources" / "gor" / "ThreeDDegrade.swift"  # 195y G2: the generated DegradeTable lives here as a relocated span; _RULE_RE skips the markers

_RULE_RE = re.compile(
    r'^\s*"([A-Z_]+)\|([a-z_0-9]+)": \("([A-Z_]+)", \[(.*?)\], "(.*?)"\),$')


def parse_swift_table(path=SWIFT_TABLE):
    """Parse the committed generated Swift table -> {(state, ev): Transition}."""
    rules = {}
    for line in Path(path).read_text().splitlines():
        m = _RULE_RE.match(line)
        if not m:
            continue
        frm, ev, to, acts, note = m.groups()
        actions = tuple(a.strip().strip('"') for a in acts.split(",") if a.strip())
        rules[(frm, ev)] = F.Transition(to, actions, note)
    return rules


def table_parity(rules):
    """Committed Swift table must equal degrade_fsm._T exactly."""
    if set(rules) != set(F._T):
        return False
    return all(rules[k] == F._T[k] for k in F._T)


FLAT_STATES = {F.UNAVAILABLE_FLAT, F.PREPARING_FLAT, F.FLAT_DEGRADED,
               F.PREP_BLOCKED}
PLAY_ACTIONS = ("act_play_stereo", "act_play_flat", "act_play_flat_native_hdr",
                "act_hold_lgd")


class Env:
    """Fault injector + playhead/prepare model."""

    def __init__(self, rng):
        self.rng = rng
        self.disk_full = False
        self.thermal = False
        self.user_off = False
        self.covered = False
        self.prepare_done = False

    def events(self, state):
        """Candidate events consistent with the model, weighted."""
        r = self.rng
        pool = []
        def w(ev, n):
            pool.extend([ev] * n)
        if state == F.INIT:
            w(F.EV_PROBE_OK, 60)
            w(F.EV_KIT_MISSING, 6)
            w(F.EV_KIT_BAD_HASH, 2)
            w(F.EV_LICENCE_OFF, 3)
            w(F.EV_REFUSE_HDR, 5)
            w(F.EV_REFUSE_VFR, 3)
            w(F.EV_RELAUNCH, 8)
        else:
            if not self.prepare_done:
                w(F.EV_PREPARE_DONE, 8)
                w(F.EV_SHOT_ERROR, 10)
                w(F.EV_SHOT_ERROR_LIMIT, 2)
            if not self.covered:
                w(F.EV_COVERED, 25)
            else:
                w(F.EV_UNCOVERED, 12)   # seek past prepared range / depth gap
            if state == F.LGD_HOLD:
                w(F.EV_LGD_RECOVERED, 45)
                w(F.EV_LGD_TIMEOUT, 30)
            if not self.disk_full:
                w(F.EV_DISK_FULL, 3)
            else:
                w(F.EV_DISK_FREED, 40)
            if not self.thermal:
                w(F.EV_THERMAL_TRIP, 3)
            else:
                w(F.EV_THERMAL_CLEAR, 40)
            w(F.EV_SOURCE_CHANGED, 3)
            w(F.EV_QUIT, 2)
            if not self.user_off:
                w(F.EV_USER_DISABLE, 2)
            else:
                w(F.EV_USER_ENABLE, 30)
        return pool

    def apply(self, ev):
        if ev in (F.EV_PROBE_OK, F.EV_KIT_MISSING, F.EV_KIT_BAD_HASH,
                  F.EV_LICENCE_OFF, F.EV_REFUSE_HDR, F.EV_REFUSE_VFR,
                  F.EV_RELAUNCH):
            pass  # probe outcomes move the table, not the model
        elif ev == F.EV_PREPARE_DONE:
            self.prepare_done, self.covered = True, True
        elif ev == F.EV_COVERED:
            self.covered = True
        elif ev == F.EV_UNCOVERED:
            self.covered = False
        elif ev == F.EV_LGD_RECOVERED:
            self.covered = True
        elif ev == F.EV_DISK_FULL:
            self.disk_full = True
        elif ev == F.EV_DISK_FREED:
            self.disk_full = False
        elif ev == F.EV_THERMAL_TRIP:
            self.thermal = True
        elif ev == F.EV_THERMAL_CLEAR:
            self.thermal = False
        elif ev == F.EV_USER_DISABLE:
            self.user_off = True
        elif ev == F.EV_USER_ENABLE:
            self.user_off = False
        elif ev == F.EV_SOURCE_CHANGED:
            self.covered = self.prepare_done = False
        elif ev == F.EV_QUIT:
            pass  # cache persists; relaunch event re-enters


def faults_cleared(env):
    return not (env.disk_full or env.thermal or env.user_off)


RECOVERY_EVENTS = (F.EV_PROBE_OK, F.EV_PREPARE_DONE, F.EV_COVERED,
                   F.EV_LGD_RECOVERED, F.EV_USER_ENABLE, F.EV_DISK_FREED,
                   F.EV_THERMAL_CLEAR, F.EV_SOURCE_CHANGED, F.EV_RELAUNCH)


def reachable(rules, start, events):
    """BFS over (table transitions + ignored self-loops) restricted to events."""
    seen = {start}
    q = deque([start])
    while q:
        s = q.popleft()
        for ev in events:
            t = rules.get((s, ev))
            nxt = t.to if t else s
            if nxt not in seen:
                seen.add(nxt)
                q.append(nxt)
    return seen


class Violation(Exception):
    pass


def soak(rules, seed, steps):
    rng = random.Random(seed)
    env = Env(rng)
    state = F.INIT
    visits = {s: 0 for s in F.STATES}
    lines = []
    # Precompute full-event reachability of READY_STEREO once.
    all_reach = reachable(rules, F.INIT, F.EVENTS)
    for step in range(steps):
        pool = env.events(state)
        ev = rng.choice(pool)
        t = rules.get((state, ev))
        to, actions = (t.to, t.actions) if t else (state, ())
        # I1
        if to not in F.STATES:
            raise Violation(f"I1 step {step}: bad state {to!r} from "
                            f"{state}|{ev}")
        # I2
        for a in actions:
            for bad in F.FORBIDDEN_ACTION_SUBSTRINGS:
                if bad in a:
                    raise Violation(f"I2 step {step}: forbidden action {a!r} "
                                    f"on {state}|{ev}")
        # I3
        if "act_play_stereo" in actions and to != F.READY_STEREO:
            raise Violation(f"I3 step {step}: stereo action landing in {to} "
                            f"on {state}|{ev}")
        if any(a.startswith("act_play_flat") for a in actions) \
                and to not in FLAT_STATES:
            raise Violation(f"I3 step {step}: flat action landing in {to} "
                            f"on {state}|{ev}")
        # I4: the emitted line must be greppable by the Mac-side checker
        line = (t.logline(state, ev) if t else
                f"3dfsm from={state} ev={ev} to={state} act=- note=ignored")
        lines.append(line)
        # I5: liveness with faults cleared (spot-check every 64 steps;
        # BFS over the full event set is the static floor)
        if F.READY_STEREO not in all_reach:
            raise Violation("I5: READY_STEREO unreachable from INIT")
        if step % 64 == 0 and faults_cleared(env):
            rec = reachable(rules, to, RECOVERY_EVENTS)
            if F.READY_STEREO not in rec:
                raise Violation(f"I5 step {step}: READY_STEREO unreachable "
                                f"from {to} with faults cleared")
        env.apply(ev)
        state = to
        visits[state] += 1
    return visits, lines


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=20000)
    ap.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3, 4, 5])
    args = ap.parse_args(argv)

    rules = parse_swift_table()
    if not rules:
        print("FAIL: no rules parsed from " + str(SWIFT_TABLE))
        return 1
    if not table_parity(rules):
        print("FAIL I6: committed DegradeTable span (ThreeDDegrade.swift) != degrade_fsm._T "
              "(regenerate via Tests/ThreeDDegrade/gen_table.py)")
        return 1
    print(f"parity: Swift table == degrade_fsm._T ({len(rules)} rules)")

    total_lines = []
    for seed in args.seeds:
        try:
            visits, lines = soak(rules, seed, args.steps)
        except Violation as v:
            print(f"FAIL seed {seed}: {v}")
            return 1
        total_lines.extend(lines)
        cov = ", ".join(f"{s}={n}" for s, n in visits.items() if n)
        print(f"seed {seed}: {args.steps} steps OK; visits {cov}")

    # I4 batch: replay every emitted line through the Mac-side fsm checker
    fam = mlc.f_fsm("run", total_lines, None)
    if fam.status != "PASS":
        print("FAIL I4: mac_log_check.f_fsm rejected soak lines:")
        for l in fam.lines[:5]:
            print(l)
        return 1
    print(f"I4: {len(total_lines)} emitted 3dfsm lines all parse via "
          "mac_log_check.f_fsm")
    print("SOAK PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
