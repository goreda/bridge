#!/usr/bin/env python3
"""Reads the [spaces] lines of /tmp/gor_diag.log (written by OverlaySpaceGate) and names the cause of an overlay/Space problem
WITHOUT asking the owner anything. Usage: spaces_log_read.py gor_diag.log   (or a capture zip's extracted log)
Verdict codes, in the order they are checked (first match is the primary cause; all matches are printed):
  NO_LOG      no [spaces] line at all: build without the Space code, or the overlay never started
  SYM_MISSING the env line shows a private CGS symbol did not resolve on this macOS (direct follow cannot work)
  NO_MPV_WIN  'mpvWin=none': the mpv window id was never found (pid wrong, or window list empty)
  MOVE_UNAVAILABLE  'NOT done': CGSMoveWindowsToManagedSpace could not be called
  MOVE_INEFFECTIVE  'moved overlay ... ok=false': the call ran but the overlay is still on the old Space (macOS ignores it)
  STUCK       'STUCK' line: mpv was on the active Space and the overlay was not for > 1.5 s (fields say why)
  SLOW        'converged after X s' with X > 1.0 (follows, but late)
  FLAP        >= 6 'moved overlay' lines inside any 10 s window (overlay and mpv fight over the Space)
  HIDDEN_WHILE_MPV_HERE  'gate hide' while mpv's Space list contains the active Space (on-screen detection wrong)
  NOT_CONVERGED 'diverge ended NOT converged' and no real follow (converged / moved ok=true)
  OK          mpv Space changes were followed (>= 1 converged/moved ok line) and none of the above
Swift side of the contract is pinned by Tests/Spaces/spaces_log_read_test.py. Linux text analysis, no Mac needed."""
import re, sys
LINE = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d{3}) \[spaces\] (.*)$")
def parse(text):
    out = []
    for l in text.splitlines():
        m = LINE.match(l.strip())
        if m: out.append((int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3]) + int(m[4]) / 1000.0, m[5]))
    return out
def diagnose(text):
    ev = parse(text); v = []
    if not ev: return [("NO_LOG", "no [spaces] line")]
    for t, m in ev:
        if m.startswith("env ") and re.search(r"sym_\w+=0", m): v.append(("SYM_MISSING", m))
    for t, m in ev:
        if "mpvWin=none" in m: v.append(("NO_MPV_WIN", m)); break
    for t, m in ev:
        if "NOT done" in m: v.append(("MOVE_UNAVAILABLE", m)); break
    for t, m in ev:
        if m.startswith("moved overlay") and "ok=false" in m: v.append(("MOVE_INEFFECTIVE", m)); break
    for t, m in ev:
        if m.startswith("STUCK"): v.append(("STUCK", m)); break
    for t, m in ev:
        c = re.match(r"converged after ([\d.]+)s", m)
        if c and float(c[1]) > 1.0: v.append(("SLOW", m)); break
    moves = [t for t, m in ev if m.startswith("moved overlay")]
    for i in range(len(moves)):
        if sum(1 for x in moves if moves[i] <= x < moves[i] + 10) >= 6: v.append(("FLAP", "%d moves within 10 s from %.1f" % (sum(1 for x in moves if moves[i] <= x < moves[i] + 10), moves[i]))); break
    for t, m in ev:
        h = re.match(r"gate hide onScreen=false active=(\d+) overlay=\[[^\]]*\] mpv=\[([^\]]*)\]", m)
        if h and h[1] in [x.strip() for x in h[2].split(",") if x.strip()]: v.append(("HIDDEN_WHILE_MPV_HERE", m)); break
    unconv = [m for t, m in ev if m.startswith("diverge ended NOT converged")]
    followed = any(m.startswith("converged") or (m.startswith("moved overlay") and "ok=true" in m) for t, m in ev)
    if not v and unconv and not followed: v.append(("NOT_CONVERGED", unconv[0] + " (mpv left the active Space; this does not show a follow)"))
    if not v: v.append(("OK" if followed else "NO_SPACE_CHANGE_SEEN", "mpv Space changes followed" if followed else "no Space change in this capture: ask for nothing, wait for the next capture that contains a desktop move"))
    return v
if __name__ == "__main__":
    for code, e in diagnose(open(sys.argv[1], errors="replace").read()): print(code, "|", e)
