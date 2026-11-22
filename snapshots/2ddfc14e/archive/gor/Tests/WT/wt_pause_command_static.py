#!/usr/bin/env python3
"""wt_pause_command_static.py - static red/green harness for the WT sender row.

Semantic execution belongs to wt_pause_command_run.sh (swiftc, Delivery).
This script is the structural half that runs anywhere: it reads the actual
product file and decides, from the code text itself, which command (if any)
each (isPlaying, playbackEnded) pair produces on the resume/pause edges.

RED  = the resume edge is gated (pre-fix base: one guard swallows both
       commands) or the fixed seam's truth table is wrong.
GREEN = resume never gated, automatic keep-open EOF pause still suppressed.
"""
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

failures = []

def expect(name, cond, detail):
    status = "PASS" if cond else "FAIL"
    if not cond:
        failures.append(name)
    print(f"{status} {name}: {detail}")

seam = re.search(
    r"static func wtPauseCommand\(isPlaying: Bool, playbackEnded: Bool\) -> String\? \{(.*?)\n    \}",
    src, re.S)

if seam is None:
    # Pre-fix base: locate the old sender and confirm the single guard gates
    # both PAUSE and RESUME.
    old = re.search(
        r"func sendPauseStateToWTServer\(isPlaying: Bool\) \{(.*?)\n    \}",
        src, re.S)
    if old and "guard !wtPlaybackEnded else { return }" in old.group(1) \
            and 'isPlaying ? "RESUME" : "PAUSE"' in old.group(1):
        expect("resume-while-latched", False,
               "gated: guard !wtPlaybackEnded swallows RESUME (pre-fix base)")
        expect("resume-clear-latch", True,
               "ungated on base: RESUME posts when the latch is clear")
        expect("user-pause-clear-latch", True,
               "ungated on base: PAUSE posts when the latch is clear")
        expect("automatic-eof-pause", True,
               "suppressed on base: latch swallows the automatic EOF pause")
    else:
        expect("sender-located", False,
               "sendPauseStateToWTServer not found in expected pre-fix shape")
else:
    body = seam.group(1)
    expect("resume-while-latched",
           'if isPlaying { return "RESUME" }' in body,
           "RESUME returned before the latch is consulted")
    expect("resume-clear-latch",
           'if isPlaying { return "RESUME" }' in body,
           "same branch covers the clear-latch resume")
    expect("user-pause-clear-latch",
           'return playbackEnded ? nil : "PAUSE"' in body,
           "PAUSE returned when the latch is clear")
    expect("automatic-eof-pause",
           'return playbackEnded ? nil : "PAUSE"' in body,
           "nil (suppressed) when the latch is set")
    sender = re.search(
        r"func sendPauseStateToWTServer\(isPlaying: Bool\) \{(.*?)\n    \}",
        src, re.S)
    sb = sender.group(1) if sender else ""
    expect("resume-clears-latch",
           "wtPlaybackEnded = false" in sb and "if isPlaying" in sb,
           "resume edge clears the stale latch so later pauses reach WT")
    expect("pause-side-keeps-eof-event-guard",
           'sendWTPlaybackEvent("pause")' in sb
           and "Self.wtPauseCommand(isPlaying: isPlaying, playbackEnded: wtPlaybackEnded)" in sb,
           "pause event only fires when the command seam did not suppress")

print(f"RESULT: {'FAIL ' + str(len(failures)) if failures else 'PASS'}"
      f" ({len(failures)} failing checks)")
sys.exit(1 if failures else 0)
