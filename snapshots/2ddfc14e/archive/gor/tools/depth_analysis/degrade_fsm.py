"""s38: graceful-degradation state machine for the 3D path (CONTRACT-190v s38).

Pure transition table over (player_state, event) -> (next_state, actions,
log line). No I/O, no clocks, no mpv objects: the player feeds events in
and executes the returned actions; everything is pinned by
Tests/DepthAnalysis/test_degrade_fsm.py (every state x event pair, no
dead ends).

Invariants the table encodes (owner rules):
- Playback is NEVER interrupted: no action recreates the mpv instance,
  seeks, pauses, or touches audio. The 3D->2D->3D switches only swap the
  depth input of the render pipeline (filter uniforms / depth texture),
  so a/v sync cannot break and the mpv lifecycle is untouched.
- Tier 1 quality is never lowered: a failure falls back to 2D playback
  or to the last good depth frame, never to cheaper depth.
- Every failure surfaces: badge (transient) and/or menu note
  (persistent), one short OSD line on stereo<->flat switches, never an
  audio cue.
- HDR sources refused for 3D are played back as UNTOUCHED native 2D HDR
  (never tone-clipped, s34 rule).

Log line format (selftest greps this):
  3dfsm from=<STATE> ev=<event> to=<STATE> act=<a1|a2|-> note=<reason>
"""

# ---------------- states ----------------
INIT = "INIT"                      # app start / source (re)probe in flight
UNAVAILABLE_FLAT = "UNAVAILABLE_FLAT"  # 3D impossible for this source; native 2D
PREPARING_FLAT = "PREPARING_FLAT"  # 3D wanted, prepare running, playing 2D
READY_STEREO = "READY_STEREO"      # playhead covered by Tier-1 depth; 3D on
LGD_HOLD = "LGD_HOLD"              # transient gap; holding last good depth
FLAT_DEGRADED = "FLAT_DEGRADED"    # 3D wanted, temporarily flat; prepare runs
PREP_BLOCKED = "PREP_BLOCKED"      # playing flat; prepare paused (disk/thermal)

STATES = (INIT, UNAVAILABLE_FLAT, PREPARING_FLAT, READY_STEREO,
          LGD_HOLD, FLAT_DEGRADED, PREP_BLOCKED)

# ---------------- events ----------------
EV_PROBE_OK = "probe_ok"                    # kit+licence+container all fine
EV_KIT_MISSING = "kit_missing"
EV_KIT_BAD_HASH = "kit_bad_hash"
EV_LICENCE_OFF = "moge_licence_off"         # MoGe licence-gated off
EV_REFUSE_HDR = "refuse_hdr"                # HDR source: 3D refused (no clip)
EV_REFUSE_VFR = "refuse_vfr"                # VFR source: 3D refused
EV_PREPARE_DONE = "prepare_done"
EV_COVERED = "playhead_covered"             # prepared Tier-1 range >= playhead
EV_UNCOVERED = "playhead_uncovered"         # depth not ready at playhead /
                                            # seek beyond prepared range
EV_LGD_RECOVERED = "lgd_recovered"          # depth arrived during the hold
EV_LGD_TIMEOUT = "lgd_timeout"              # hold budget (500 ms) exhausted
EV_SHOT_ERROR = "shot_error"                # prepare threw on a shot (< limit)
EV_SHOT_ERROR_LIMIT = "shot_error_limit"    # retries exhausted; shot failed
EV_DISK_FULL = "disk_full"                  # .dzc write ENOSPC
EV_DISK_FREED = "disk_freed"
EV_THERMAL_TRIP = "thermal_trip"            # thermal gate trips mid-play
EV_THERMAL_CLEAR = "thermal_clear"
EV_SOURCE_CHANGED = "source_changed"        # new file / re-prepare
EV_QUIT = "app_quit"                        # quit mid-prepare (persist)
EV_RELAUNCH = "relaunch"                    # cold start with cache present
EV_USER_DISABLE = "user_disable_3d"
EV_USER_ENABLE = "user_enable_3d"

EVENTS = (EV_PROBE_OK, EV_KIT_MISSING, EV_KIT_BAD_HASH, EV_LICENCE_OFF,
          EV_REFUSE_HDR, EV_REFUSE_VFR, EV_PREPARE_DONE, EV_COVERED,
          EV_UNCOVERED, EV_LGD_RECOVERED, EV_LGD_TIMEOUT, EV_SHOT_ERROR,
          EV_SHOT_ERROR_LIMIT, EV_DISK_FULL, EV_DISK_FREED,
          EV_THERMAL_TRIP, EV_THERMAL_CLEAR, EV_SOURCE_CHANGED, EV_QUIT,
          EV_RELAUNCH, EV_USER_DISABLE, EV_USER_ENABLE)

# ---------------- action vocabulary ----------------
# Playback: act_play_flat / act_play_flat_native_hdr / act_play_stereo /
#           act_hold_lgd swap ONLY the render pipeline's depth input.
# Prepare:  act_prepare_start / pause / resume / retry_shot / abort /
#           mark_shot_failed / persist.
# UX:       act_osd(text) one-line transient, act_badge(text) persistent
#           while in state, act_badge_clear, act_menu_note(text).
# NEVER (pinned by the test): anything that restarts mpv, seeks, pauses,
# or touches audio.
FORBIDDEN_ACTION_SUBSTRINGS = ("mpv_restart", "recreate", "seek",
                               "pause_playback", "audio")

LGD_HOLD_MS = 500          # depth-hitch hold budget before falling to 2D
SHOT_ERROR_LIMIT = 3       # consecutive prepare failures before a shot
                           # is marked failed (its range plays flat)


class Transition:
    __slots__ = ("to", "actions", "note")

    def __init__(self, to, actions=(), note=""):
        self.to, self.actions, self.note = to, tuple(actions), note

    def logline(self, frm, ev):
        # act field is space-free so the line stays trivially greppable
        acts = ("|".join(self.actions) if self.actions else "-").replace(" ", "_")
        return (f"3dfsm from={frm} ev={ev} to={self.to} act={acts}"
                + (f" note={self.note}" if self.note else ""))

    def __eq__(self, o):
        return (self.to, self.actions, self.note) == (o.to, o.actions, o.note)

    def __repr__(self):
        return f"Transition({self.to}, {self.actions}, {self.note!r})"


_OSD_ON = "act_osd(3D on)"
_OSD_FLAT = "act_osd(3D off - playing 2D)"
_PERSIST = "act_persist"           # cache state survives; <=1 in-flight shot lost
_REPROBE = "act_reprobe"
_IGNORE = "-"                      # logged no-op self-loop

_T = {}


def _rule(frm, ev, to, actions=(), note=""):
    _T[(frm, ev)] = Transition(to, actions, note)


# --- INIT: probe outcomes decide ------------------------------------------------
_rule(INIT, EV_PROBE_OK, PREPARING_FLAT,
      ("act_play_flat", "act_prepare_start", "act_badge(3D preparing)"),
      "playback starts in 2D immediately; prepare fills behind the playhead")
_rule(INIT, EV_KIT_MISSING, UNAVAILABLE_FLAT,
      ("act_play_flat", "act_menu_note(3D kit not installed)"),
      "retry on kit_ok (kit download route is owner-Mac)")
_rule(INIT, EV_KIT_BAD_HASH, UNAVAILABLE_FLAT,
      ("act_play_flat", "act_menu_note(3D kit corrupt - re-download)"),
      "hash mismatch: treat as tampered/partial download, never run it")
_rule(INIT, EV_LICENCE_OFF, UNAVAILABLE_FLAT,
      ("act_play_flat", "act_menu_note(3D off: depth-kit licence)"),
      "MoGe-2 licence-gated off; no VDA-only fallback (Tier 1 never lowered)")
_rule(INIT, EV_REFUSE_HDR, UNAVAILABLE_FLAT,
      ("act_play_flat_native_hdr", "act_menu_note(HDR source: 3D off)"),
      "2D path passes HDR through untouched; never silently tone-clipped")
_rule(INIT, EV_REFUSE_VFR, UNAVAILABLE_FLAT,
      ("act_play_flat", "act_menu_note(VFR source: 3D off)"),
      "VFR timestamps rejected (s26 keyframe/PTS contract)")
_rule(INIT, EV_RELAUNCH, INIT, ("act_load_cache", _REPROBE),
      "cold start: prepared .dzc shots survive; re-probe picks the branch")

# --- PREPARING_FLAT -------------------------------------------------------------
_rule(PREPARING_FLAT, EV_COVERED, READY_STEREO,
      ("act_play_stereo", "act_badge_clear", _OSD_ON))
_rule(PREPARING_FLAT, EV_PREPARE_DONE, READY_STEREO,
      ("act_play_stereo", "act_badge_clear", _OSD_ON),
      "whole film prepared; playhead is covered by definition")
_rule(PREPARING_FLAT, EV_SHOT_ERROR, PREPARING_FLAT,
      ("act_prepare_retry_shot",),
      f"backoff retry, attempt < {SHOT_ERROR_LIMIT}")
_rule(PREPARING_FLAT, EV_SHOT_ERROR_LIMIT, PREPARING_FLAT,
      ("act_mark_shot_failed", "act_menu_note(one scene plays in 2D)"),
      "failed shot's range stays uncovered -> flat there, stereo elsewhere")
_rule(PREPARING_FLAT, EV_DISK_FULL, PREP_BLOCKED,
      ("act_prepare_pause", "act_badge(3D prep paused: disk full)"))
_rule(PREPARING_FLAT, EV_THERMAL_TRIP, PREP_BLOCKED,
      ("act_prepare_pause", "act_badge(3D prep paused: thermals)"))
_rule(PREPARING_FLAT, EV_QUIT, INIT, (_PERSIST,),
      "resume on relaunch from last completed shot")

# --- READY_STEREO ---------------------------------------------------------------
_rule(READY_STEREO, EV_UNCOVERED, LGD_HOLD, ("act_hold_lgd",),
      f"depth gap at playhead: hold last good depth up to {LGD_HOLD_MS} ms; "
      "pipeline untouched, a/v sync cannot break")
_rule(READY_STEREO, EV_DISK_FULL, READY_STEREO,
      ("act_prepare_pause", "act_badge(3D prep paused: disk full)"),
      "playback continues 3D on the prepared range")
_rule(READY_STEREO, EV_THERMAL_TRIP, READY_STEREO,
      ("act_prepare_pause", "act_badge(3D prep paused: thermals)"),
      "playback continues 3D on the prepared range")
_rule(READY_STEREO, EV_THERMAL_CLEAR, READY_STEREO,
      ("act_prepare_resume", "act_badge_clear"),
      "gate cleared while playing the prepared range: prepare resumes")
_rule(READY_STEREO, EV_DISK_FREED, READY_STEREO,
      ("act_prepare_resume", "act_badge_clear"))
_rule(READY_STEREO, EV_QUIT, INIT, (_PERSIST,))

# --- LGD_HOLD -------------------------------------------------------------------
_rule(LGD_HOLD, EV_LGD_RECOVERED, READY_STEREO, ("act_play_stereo",),
      "gap closed inside the hold budget; user saw nothing")
_rule(LGD_HOLD, EV_LGD_TIMEOUT, FLAT_DEGRADED,
      ("act_play_flat", _OSD_FLAT, "act_badge(3D catching up)"),
      "hold budget exhausted: drop to 2D rather than stall a frame")
_rule(LGD_HOLD, EV_COVERED, READY_STEREO, ("act_play_stereo",))
_rule(LGD_HOLD, EV_QUIT, INIT, (_PERSIST,))

# --- FLAT_DEGRADED --------------------------------------------------------------
_rule(FLAT_DEGRADED, EV_COVERED, READY_STEREO,
      ("act_play_stereo", "act_badge_clear", _OSD_ON))
_rule(FLAT_DEGRADED, EV_SHOT_ERROR, FLAT_DEGRADED, ("act_prepare_retry_shot",))
_rule(FLAT_DEGRADED, EV_SHOT_ERROR_LIMIT, FLAT_DEGRADED,
      ("act_mark_shot_failed", "act_menu_note(one scene plays in 2D)"))
_rule(FLAT_DEGRADED, EV_DISK_FULL, PREP_BLOCKED,
      ("act_prepare_pause", "act_badge(3D prep paused: disk full)"))
_rule(FLAT_DEGRADED, EV_THERMAL_TRIP, PREP_BLOCKED,
      ("act_prepare_pause", "act_badge(3D prep paused: thermals)"))
_rule(FLAT_DEGRADED, EV_QUIT, INIT, (_PERSIST,))

# --- PREP_BLOCKED ---------------------------------------------------------------
_rule(PREP_BLOCKED, EV_DISK_FREED, PREPARING_FLAT,
      ("act_prepare_resume", "act_badge_clear"))
_rule(PREP_BLOCKED, EV_THERMAL_CLEAR, PREPARING_FLAT,
      ("act_prepare_resume", "act_badge_clear"),
      "auto-retry: prepare resumes when the gate clears")
_rule(PREP_BLOCKED, EV_COVERED, PREPARING_FLAT, ("act_badge_clear",),
      "coverage changed while blocked (external cache fill); resume decision "
      "waits for the unblocking event")
_rule(PREP_BLOCKED, EV_QUIT, INIT, (_PERSIST,))

# --- UNAVAILABLE_FLAT: any condition change re-probes ---------------------------
for ev in (EV_KIT_MISSING, EV_KIT_BAD_HASH, EV_LICENCE_OFF,
           EV_REFUSE_HDR, EV_REFUSE_VFR):
    _rule(UNAVAILABLE_FLAT, ev, UNAVAILABLE_FLAT, ("act_reprobe",),
          "same or new refusal reason; note stays")
_rule(UNAVAILABLE_FLAT, EV_PROBE_OK, PREPARING_FLAT,
      (_REPROBE, "act_play_flat", "act_prepare_start",
       "act_badge(3D preparing)"),
      "condition cleared (kit installed / licence accepted / new source)")

# --- events valid in every state ------------------------------------------------
for s in STATES:
    _rule(s, EV_SOURCE_CHANGED, INIT, ("act_prepare_abort", _REPROBE),
          "new source: all prepare/playback state re-derived; playback of the "
          "new file starts flat, never waits")
    _rule(s, EV_USER_DISABLE, UNAVAILABLE_FLAT,
          ("act_play_flat", "act_prepare_abort", "act_badge_clear"),
          "menu toggle; 2D is instant (depth-input swap only)")
_rule(UNAVAILABLE_FLAT, EV_USER_ENABLE, INIT, (_REPROBE,),
      "menu toggle back on: full re-probe")
_rule(UNAVAILABLE_FLAT, EV_USER_DISABLE, UNAVAILABLE_FLAT, (),
      "already off")


def handle(state, event):
    """Total transition function: every (state, event) pair returns a
    Transition. Unlisted pairs are logged no-op self-loops (event not
    meaningful in this state) - the table has no dead ends by
    construction and the test pins that no pair raises."""
    t = _T.get((state, event))
    if t is None:
        t = Transition(state, (), "ignored")
    return t


def reachable(target=READY_STEREO):
    """BFS over the table (including ignore self-loops excluded): the set
    of states that can reach `target`. Used by the test to prove no
    state is a dead end."""
    seen, frontier = set(), [target]
    while frontier:
        nxt = []
        for (s, _e), t in _T.items():
            if t.to in frontier and s not in seen:
                seen.add(s)
                nxt.append(s)
        frontier = nxt
    return seen | {target}
