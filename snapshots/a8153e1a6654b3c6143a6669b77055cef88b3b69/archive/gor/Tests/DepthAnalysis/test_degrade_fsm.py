#!/usr/bin/env python3
"""s38 pins: degrade_fsm transition table (CONTRACT-190v s38).

Total-table pin (every state x event), no dead ends, the mpv-lifecycle
invariant (no action ever restarts/seeks/pauses playback), the log-line
format for selftest, and the scripted failure scenarios from s38."""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))
import degrade_fsm as fsm  # noqa: E402

LOG_RE = re.compile(r"^3dfsm from=[A-Z_]+ ev=[a-z_0-9]+ to=[A-Z_]+ act=\S+( note=.*)?$")

# 1. totality + log format + invariant, over EVERY state x event pair
for s in fsm.STATES:
    for e in fsm.EVENTS:
        t = fsm.handle(s, e)                      # must never raise
        assert t.to in fsm.STATES, (s, e, t)
        assert LOG_RE.match(t.logline(s, e)), t.logline(s, e)
        for a in t.actions:
            low = a.lower()
            assert not any(b in low for b in fsm.FORBIDDEN_ACTION_SUBSTRINGS), (s, e, a)
print(f"PASS total table {len(fsm.STATES)}x{len(fsm.EVENTS)} "
      f"({len(fsm.STATES) * len(fsm.EVENTS)} pairs), log format, mpv invariant")

# 2. no dead ends: every state reaches READY_STEREO
assert fsm.reachable(fsm.READY_STEREO) == set(fsm.STATES)
print("PASS no dead ends (every state reaches READY_STEREO)")

# 3. explicit pins on the meaningful pairs
P = fsm.handle
assert P(fsm.INIT, fsm.EV_KIT_MISSING).to == fsm.UNAVAILABLE_FLAT
assert P(fsm.INIT, fsm.EV_KIT_BAD_HASH).to == fsm.UNAVAILABLE_FLAT
assert P(fsm.INIT, fsm.EV_LICENCE_OFF).to == fsm.UNAVAILABLE_FLAT
t = P(fsm.INIT, fsm.EV_REFUSE_HDR)
assert t.to == fsm.UNAVAILABLE_FLAT and "act_play_flat_native_hdr" in t.actions
assert P(fsm.INIT, fsm.EV_REFUSE_VFR).to == fsm.UNAVAILABLE_FLAT
assert P(fsm.INIT, fsm.EV_PROBE_OK).to == fsm.PREPARING_FLAT
assert P(fsm.PREPARING_FLAT, fsm.EV_COVERED).to == fsm.READY_STEREO
assert P(fsm.READY_STEREO, fsm.EV_UNCOVERED).to == fsm.LGD_HOLD
assert "act_hold_lgd" in P(fsm.READY_STEREO, fsm.EV_UNCOVERED).actions
assert P(fsm.LGD_HOLD, fsm.EV_LGD_TIMEOUT).to == fsm.FLAT_DEGRADED
assert P(fsm.LGD_HOLD, fsm.EV_LGD_RECOVERED).to == fsm.READY_STEREO
assert P(fsm.FLAT_DEGRADED, fsm.EV_COVERED).to == fsm.READY_STEREO
assert P(fsm.PREPARING_FLAT, fsm.EV_DISK_FULL).to == fsm.PREP_BLOCKED
assert P(fsm.PREP_BLOCKED, fsm.EV_DISK_FREED).to == fsm.PREPARING_FLAT
assert P(fsm.PREP_BLOCKED, fsm.EV_THERMAL_CLEAR).to == fsm.PREPARING_FLAT
# thermal/disk mid-play in stereo: playback stays 3D, only prepare pauses;
# the clearing event resumes it
for ev in (fsm.EV_THERMAL_TRIP, fsm.EV_DISK_FULL):
    t = P(fsm.READY_STEREO, ev)
    assert t.to == fsm.READY_STEREO and "act_prepare_pause" in t.actions, (ev, t)
for ev in (fsm.EV_THERMAL_CLEAR, fsm.EV_DISK_FREED):
    t = P(fsm.READY_STEREO, ev)
    assert t.to == fsm.READY_STEREO and "act_prepare_resume" in t.actions, (ev, t)
# retries before a shot is abandoned
assert P(fsm.PREPARING_FLAT, fsm.EV_SHOT_ERROR).to == fsm.PREPARING_FLAT
t = P(fsm.PREPARING_FLAT, fsm.EV_SHOT_ERROR_LIMIT)
assert t.to == fsm.PREPARING_FLAT and any("mark_shot_failed" in a for a in t.actions)
# quit anywhere persists; relaunch re-probes
for s in fsm.STATES:
    assert P(s, fsm.EV_QUIT).to in (fsm.INIT, s), s
    assert P(s, fsm.EV_SOURCE_CHANGED).to == fsm.INIT
    assert P(s, fsm.EV_USER_DISABLE).to == fsm.UNAVAILABLE_FLAT
assert P(fsm.UNAVAILABLE_FLAT, fsm.EV_USER_ENABLE).to == fsm.INIT
print("PASS explicit pair pins")

# 4. scripted scenarios: sequences produce the pinned state walk + log lines
def walk(seq):
    s, log = fsm.INIT, []
    for ev in seq:
        t = fsm.handle(s, ev)
        log.append(t.logline(s, ev))
        s = t.to
    return s, log

# happy path: open -> prepare -> covered -> stereo
s, _ = walk([fsm.EV_PROBE_OK, fsm.EV_COVERED])
assert s == fsm.READY_STEREO
# seek beyond prepared range: LGD hold -> timeout -> flat -> catch up -> stereo
s, log = walk([fsm.EV_PROBE_OK, fsm.EV_COVERED, fsm.EV_UNCOVERED,
               fsm.EV_LGD_TIMEOUT, fsm.EV_COVERED])
assert s == fsm.READY_STEREO
assert any("to=LGD_HOLD act=act_hold_lgd" in l for l in log)
# thermal trip mid-play: 3D keeps playing, prepare pauses, clears, resumes
s, log = walk([fsm.EV_PROBE_OK, fsm.EV_COVERED, fsm.EV_THERMAL_TRIP])
assert s == fsm.READY_STEREO
s, log = walk([fsm.EV_PROBE_OK, fsm.EV_THERMAL_TRIP, fsm.EV_THERMAL_CLEAR,
               fsm.EV_COVERED])
assert s == fsm.READY_STEREO
# disk full mid-prepare -> freed -> resume -> covered
s, _ = walk([fsm.EV_PROBE_OK, fsm.EV_DISK_FULL, fsm.EV_DISK_FREED,
             fsm.EV_COVERED])
assert s == fsm.READY_STEREO
# shot throws 3x: retries then failed-shot, still reaches stereo elsewhere
s, log = walk([fsm.EV_PROBE_OK] + [fsm.EV_SHOT_ERROR] * 2
              + [fsm.EV_SHOT_ERROR_LIMIT, fsm.EV_COVERED])
assert s == fsm.READY_STEREO
# kit missing -> flat native; kit installed later -> re-probe -> stereo
s, _ = walk([fsm.EV_KIT_MISSING, fsm.EV_PROBE_OK, fsm.EV_COVERED])
assert s == fsm.READY_STEREO
# HDR refusal: 2D HDR untouched, stereo never engaged
s, log = walk([fsm.EV_REFUSE_HDR, fsm.EV_COVERED])
assert s == fsm.UNAVAILABLE_FLAT
assert any("act_play_flat_native_hdr" in l for l in log)
# quit mid-prepare -> relaunch -> cache re-probe -> stereo
s, _ = walk([fsm.EV_PROBE_OK, fsm.EV_QUIT, fsm.EV_RELAUNCH,
             fsm.EV_PROBE_OK, fsm.EV_COVERED])
assert s == fsm.READY_STEREO
# user toggle off mid-stereo: instant flat, no prepare remnant
s, log = walk([fsm.EV_PROBE_OK, fsm.EV_COVERED, fsm.EV_USER_DISABLE])
assert s == fsm.UNAVAILABLE_FLAT
assert any("act_prepare_abort" in l for l in log)
print("PASS scenario walks (seek/thermal/disk/shot-error/kit/HDR/quit-resume/toggle)")

# 5. one golden log line pinned verbatim for the selftest contract
line = fsm.handle(fsm.READY_STEREO, fsm.EV_UNCOVERED).logline(fsm.READY_STEREO, fsm.EV_UNCOVERED)
assert line == ("3dfsm from=READY_STEREO ev=playhead_uncovered to=LGD_HOLD "
                "act=act_hold_lgd note=depth gap at playhead: hold last good "
                "depth up to 500 ms; pipeline untouched, a/v sync cannot break"), line
print("PASS golden log line")

print("PASS test_degrade_fsm")
