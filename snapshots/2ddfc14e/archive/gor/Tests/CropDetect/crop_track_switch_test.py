#!/usr/bin/env python3
"""199az delta piece: a video track switch restarts a pending crop search at once. The poll observes
current-tracks/video/id; a real switch (previous id and new id both nonzero, different) calls
restartPendingWTCropSearch("track-switch"), which drops the retry entry, cancels any in-flight scan
and starts a fresh scan with a fresh +2/+5/+10/30s cadence. The first observation of a file (0 -> id)
is not a switch, and a settled file (decisive result, no pending entry) is untouched. Static anchors
on PPController.swift; behaviour checks are Python mirrors."""
import pathlib, sys
PP = (pathlib.Path(__file__).resolve().parents[2] / 'Sources/gor/Player/PPController.swift').read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)
check("track switch restarts a pending search on a current-tracks/video/id change",
      'restartPendingWTCropSearch("track-switch")' in PP
      and 'results["current-tracks/video/id"] as? Int' in PP
      and "private var lastVideoTrackID = 0" in PP)
check("the first observation of a file (0 -> id) is not treated as a switch",
      "let switched = lastVideoTrackID > 0 && vid > 0" in PP)
check("the observed id is stored for the next comparison", "lastVideoTrackID = vid" in PP)
# mirror: restartPendingWTCropSearch + cadence
def delay(n): return 2 if n <= 1 else 5 if n == 2 else 10 if n == 3 else 30
class Search:
    def __init__(self):
        self.entry = None; self.pending = False; self.crop = None; self.menu_owns = False
        self.generation = 0; self.scans = []
    def restart(self):
        if self.entry is None or self.crop is not None or self.menu_owns or self.pending: return False
        self.entry = None
        self.generation += 1
        self.pending = True
        self.scans.append(self.generation)
        return True
    def indecisive(self, scanned_end):
        self.pending = False
        n = self.entry[0] if self.entry else 0
        self.entry = (n + 1, scanned_end)
        return delay(n + 1)
s = Search()
s.indecisive(120)                      # attempt 1 armed
s.entry = (3, 300)                     # two more indecisive rounds: attempt 3 armed, next delay 30s
check("mirror: before the switch the cadence sits at attempt 3 (next delay 30s)", delay(s.entry[0] + 1) == 30)
switched = s.restart()                 # track switch
d2 = s.indecisive(300) if switched else None
check("mirror: track switch restarts the search and the cadence starts fresh at +2s", switched and d2 == 2)
s2 = Search()
check("mirror: a settled file (no pending entry) is untouched by a track switch", not s2.restart())
last_vid = 0; restarts = 0
for vid in (1, 1, 2, 0, 3):            # first sight, same id, real switch, no-video, switch from none
    if vid != last_vid:
        sw = last_vid > 0 and vid > 0
        last_vid = vid
        if sw: restarts += 1
check("mirror: only the real switch (1->2) restarts; first sight, same id and no-video do not", restarts == 1)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
