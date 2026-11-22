#!/usr/bin/env python3
"""199az delta piece: a paused player is never scanned. fireWTCropRetry re-checks isPlaying at fire
time: a timer armed while playing that fires after a pause re-arms (+30 s, no budget charge, no scan)
instead of scanning. Static anchors on PPController.swift; behaviour check is a Python mirror."""
import pathlib, sys
PP = (pathlib.Path(__file__).resolve().parents[2] / 'Sources/gor/Player/PPController.swift').read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)
helper = PP.split("private func fireWTCropRetry(_ scheduled: String,token:Int) {", 1)[1].split("\n    }", 1)[0]
check("fire-time isPlaying re-check: paused re-arms +30s and never scans",
      "if !isPlaying" in helper and "retry re-armed: playback paused, no scan" in helper
      and ".now() + 30" in helper and "self.fireWTCropRetry(scheduled,token:token)" in helper)
check("the paused re-arm keeps the scheduled file identity guard",
      "guard let self, self.currentFilePath == scheduled else { return }" in helper)
check("the paused re-arm never re-charges the per-file attempt count", "wtCropRetry" not in helper)
check("thermal defer still intact below the pause check", "if HeatTelemetry.thermalPressure" in helper)
# mirror: schedule while playing, pause before the fire
def delay(n): return 2 if n <= 1 else 5 if n == 2 else 10 if n == 3 else 30
class Retry:
    def __init__(self):
        self.playing = True; self.hot = False; self.n = 0; self.scans = 0; self.armed = None
    def schedule(self):
        self.n += 1; self.armed = delay(self.n)
    def fire(self):
        if self.armed is None: return "none"
        self.armed = None
        if not self.playing: self.armed = 30; return "re-armed(paused)"
        if self.hot: self.armed = 30; return "re-armed(hot)"
        self.scans += 1; return "scan"
r = Retry(); r.schedule()            # indecisive while playing: attempt 1 fires in +2s
r.playing = False                    # the user pauses before it fires
outcomes = [r.fire(), r.fire()]
check("mirror: paused fires only re-arm (+30s), zero scans, attempt count untouched",
      outcomes == ["re-armed(paused)", "re-armed(paused)"] and r.scans == 0 and r.n == 1 and r.armed == 30)
r.playing = True
check("mirror: after the resume the same retry scans, still attempt 1", r.fire() == "scan" and r.scans == 1)
r.hot = True; r.schedule()
check("mirror: hot fire still defers (thermal path untouched)", r.fire() == "re-armed(hot)" and r.scans == 1)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
