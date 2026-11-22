#!/usr/bin/env python3
"""199az delta piece: the seek reset is real. The old seek branch only nilled the retry entry, so a
scan in flight at seek time kept running and its stale completion could land after the seek. Now the
seek branch drops the entry AND cancels the in-flight scan (cancel bumps the retry generation, so a
delayed old-scan completion dies on the token guard and isPending clears, letting playback-restart
start a fresh scan) and clears the last-file latch (written only on decisive, so an indecisive scan
never latched it). Static anchors on PPController.swift and CropDetector.swift; fixture is a Python
mirror of the generation tokens and timer ordering."""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
PP = (ROOT / 'Sources/gor/Player/PPController.swift').read_text()
CD = (ROOT / 'Sources/gor/Picture/CropDetector.swift').read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)
seek = PP.split('case "seek":', 1)[1].split('pollEngine.kick()', 1)[0]
check("seek drops the retry entry AND cancels the in-flight scan AND clears the last-file latch",
      "self.wtCropRetry[self.currentFilePath] = nil" in seek
      and "self.cropDetector.cancel(); self.cropDetector.resetLastFile()" in seek)
check("seek reset covers a search pending retry OR a scan in flight (never a settled/manual crop)",
      "self.cropRect == nil," in seek
      and "self.wtCropRetry[self.currentFilePath] != nil || self.cropDetector.isPending" in seek)
check("the last-file latch is written only on a decisive result (indecisive never latches)",
      "if decisive { self.lastDetectedFile = filePath }" in CD)
cancel = CD.split("func cancel() {", 1)[1].split("\n    }", 1)[0]
check("cancel bumps the retry generation and clears isPending",
      "retryGeneration += 1" in cancel and "isPending = false" in cancel)
check("a delayed completion is accepted only under its own generation token",
      "guard let self, self.retryGeneration==token else { return }" in CD)
# fixture: delayed old-scan completion and timer ordering
class Detector:
    def __init__(self):
        self.generation = 0; self.pending = False; self.last_file = ""; self.applied = []
    def detect(self, path):
        self.generation += 1; self.pending = True; return self.generation
    def complete(self, token, path, decisive):
        if token != self.generation: return "dropped"
        self.pending = False
        if decisive: self.last_file = path
        self.applied.append(path); return "applied"
    def cancel(self):
        self.generation += 1; self.pending = False
    def reset_last(self): self.last_file = ""
d = Detector()
t1 = d.detect("F")                     # scan of F in flight at seek time
d.cancel(); d.reset_last()             # the seek reset
late = d.complete(t1, "F", True)       # the old scan's completion lands AFTER the seek
check("fixture: a delayed old-scan completion is dropped, never applied", late == "dropped" and d.applied == [])
t2 = d.detect("F")                     # playback-restart: the latch is clear, a fresh scan runs
check("fixture: the fresh scan runs under a new generation", t2 != t1 and d.pending)
def fire(token):
    return "scan" if token == d.generation else "no-op"
stale = fire(t1)                       # a retry timer armed before the seek fires after it
fresh = fire(d.generation)             # the post-restart indecisive result arms with the new token
check("fixture: the pre-seek timer is a no-op after the cancel; only the fresh timer scans",
      stale == "no-op" and fresh == "scan")
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
