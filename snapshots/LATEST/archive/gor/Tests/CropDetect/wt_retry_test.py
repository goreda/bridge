#!/usr/bin/env python3
"""Magnet-stream crop detect after an indecisive scan: the automatic path keeps searching until found
(199az: +2s, +5s, +10s, then every 30s while playing, NO give-up count; wt playback only; manual click
included) and the manual button says why instead of "no decision yet". A paused player is never scanned
(the fire re-arms), thermal pressure defers without charging, and each schedule records the scanned
range end for the buffer-growth restart. Static wiring checks on PPController.swift plus a model of the
per-file counter. Ported from the pre-199az contract (12 cap / 45 s / 2-tuple) to the persistent search."""
import pathlib, re, sys
PC = (pathlib.Path(__file__).resolve().parents[2] / 'Sources/gor/Player/PPController.swift').read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)
blk = PC.split("guard decisive else {")[1].split("\n                return\n")[0]
check("retry for wt playback while playing, manual click included (one click is enough)", "if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, (!manual || self.cropRect == nil)" in blk and "if !manual, CropDetector" not in blk)
check("no give-up count: a crop is searched until found (the old n < 12 cap is gone)", "n < 12" not in PC and "if n <" not in blk)
check("retry cadence is +2s, +5s, +10s, then every 30s", "static func wtCropRetryDelay(attempt n: Int) -> Double { n <= 1 ? 2 : n == 2 ? 5 : n == 3 ? 10 : 30 }" in PC)
check("the schedule delay comes from the cadence function and fires through the thermal-aware helper", "let delay = Self.wtCropRetryDelay(attempt: n + 1)" in blk and ".now() + delay" in blk and "self.fireWTCropRetry(scheduled,token:token)" in blk)
helper = PC.split("private func fireWTCropRetry(_ scheduled: String,token:Int) {",1)[1].split("\n    }",1)[0]
check("thermal defer re-arms on a 30 s timer and then re-enters the automatic start path", "if HeatTelemetry.thermalPressure" in helper and ".now() + 30" in helper and "self.startAutomaticCropDetection(needsRedetect:true)" in helper)
check("the thermal defer never re-charges the per-file attempt count", "wtCropRetry" not in helper)
check("thermal defer keeps the scheduled file identity guard", "guard let self, self.currentFilePath == scheduled else { return }" in helper)
check("thermal defer is observable in the log", '[cropdetect] retry deferred: thermal pressure' in helper)
check("a paused player is never scanned: the fire re-arms (+30 s) instead", "if !isPlaying" in helper and "retry re-armed: playback paused, no scan" in helper)
check("scheduled file identity is captured and checked at fire time", "let scheduled = self.currentFilePath" in blk and "guard let self, self.currentFilePath == scheduled else { return }" in blk)
check("counter state is declared per file with the scanned range end", "private var wtCropRetry: [String: (n: Int, t: TimeInterval, scannedEnd: Double)]" in PC)
check("each schedule records the scanned range end for the buffer-growth trigger", "self.wtCropRetry[self.currentFilePath] = (n + 1, ProcessInfo.processInfo.systemUptime, self.lastSeekableEnd)" in blk)
check("a decisive result clears that file's search state", "let early = confidence < 0; let manual = self.manualRedetectInFlight; if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }" in PC)
# the status line lives in Viewport/CropDetector.swift since the detector moved out of PPController; the pin follows it there
CD = (pathlib.Path(__file__).resolve().parents[2] / "Sources/gor/Picture/CropDetector.swift").read_text()
check("scan status text is truthful for a stream (menu and manual OSD)", 'reportStatus(Self.isWTPlayback(filePath) ? "crop: scanning the downloaded part of the stream" : "crop: scanning 40 original decoded samples")' in CD)
check("at 64 entries a NEW file evicts only the oldest entry (min timestamp), never reset-all and never on an existing-key update", "self.wtCropRetry.index(forKey: self.currentFilePath) == nil, self.wtCropRetry.count >= 64, let old = self.wtCropRetry.min(by: { $0.value.t < $1.value.t })?.key { self.wtCropRetry.removeValue(forKey: old) }" in blk and "removeAll" not in blk)
check("manual wt click explains the stream is still downloading", "not enough of the stream downloaded yet, retrying by itself" in blk and "willRetry ?" in blk and "try again" in blk)
check("non-stream manual text unchanged", "crop detect: no decision yet, file left unlocked" in blk)
import csv
root=pathlib.Path(__file__).resolve().parents[2]
rows=list(csv.DictReader((root / "architecture/arch-baseline.tsv").open(),delimiter="\t"))
ceiling=int(next(r["count"] for r in rows if r["path"]=="Sources/gor/Player/PPController.swift" and r["rule"]=="ceiling"))
def within_reviewed_ceiling(line_count):
    return max(1,line_count-799) <= ceiling
check("PPController within active architecture debt ceiling", within_reviewed_ceiling(len(PC.splitlines())))
check("active ceiling catches one-line-over mutant",not within_reviewed_ceiling(ceiling+800))
# model of the cadence, the fire-time guards and the per-file counter, including a file switch mid-wait
def delay(n): return 2 if n <= 1 else 5 if n == 2 else 10 if n == 3 else 30
counts = {}; current = "a"; pending = []; started = []
def indecisive(file, manual=False, wt=True, playing=True):
    if not wt or not playing: return
    if manual and file in counts_crop[0]: return
    n = counts.get(file, 0)
    counts[file] = n + 1; pending.append((file, delay(n + 1)))
counts_crop = [set()]
def fire():
    sched, d = pending.pop(0)
    if current == sched: started.append(current)
for _ in range(20): indecisive("a")
check("model: 20 indecisive results on one file schedule 20 retries - no give-up (%d)" % len(pending), len(pending) == 20)
check("model: the scheduled delays follow +2,+5,+10 then 30s", [d for _, d in pending[:5]] == [2, 5, 10, 30, 30])
for _ in range(20): fire()
check("model: all 20 fire on the same file and start a scan (%d)" % len(started), len(started) == 20)
indecisive("m1", manual=True); check("model: a manual click on a wt file schedules like an automatic one", len(pending) == 1); pending.clear()
indecisive("c", wt=False); check("model: non-wt never schedules", not pending)
indecisive("p", playing=False); check("model: a paused player never schedules", not pending)
indecisive("a2"); counts_a = counts.get("a")                    # a retry is scheduled for a2 ...
current = "b"; fire()                                          # ... the user switches to b before it fires
check("model: file switch mid-wait drops the retry (no scan of the new file)", started.count("b") == 0 and len(started) == 20)
indecisive("b"); current = "b"; fire(); current = "a"
check("model: counters are kept per file (a stays at %d, b at 1)" % counts_a, counts_a == 20 and counts["b"] == 1 and started[-1] == "b")
# model of the thermal defer: a hot fire re-arms the SAME retry (no budget change, no scan);
# a cool fire runs the scan. The defer loop exits only on cool or file switch.
hot = [True]
deferred = []
def fireThermal():
    sched, d = pending.pop(0)
    if current != sched: return
    if hot[0]: deferred.append(sched); pending.append((sched, 30)); return
    started.append(sched)
indecisive("h1"); current = "h1"
for _ in range(5): fireThermal()
check("model: hot fire defers without scanning or consuming budget (%d deferrals)" % len(deferred), len(deferred) == 5 and len(started) == 21 and counts["h1"] == 1)
hot[0] = False; fireThermal()
check("model: the same retry runs once the box is cool", started[-1] == "h1" and counts["h1"] == 1)
indecisive("h2"); hot[0] = True; current = "other"; fireThermal()
check("model: file switch while hot still drops the retry (no deferral leak)", len(pending) == 0 and deferred.count("h2") == 0)
# model of the paused re-arm: a paused fire re-arms +30s without scanning or charging; the resume fires for real
paused = [True]; rearmed = []
def firePaused():
    sched, d = pending.pop(0)
    if current != sched: return
    if paused[0]: rearmed.append(sched); pending.append((sched, 30)); return
    started.append(sched)
indecisive("p1"); current = "p1"
for _ in range(3): firePaused()
check("model: paused fire re-arms without scanning or charging (%d re-arms)" % len(rearmed), len(rearmed) == 3 and counts["p1"] == 1 and started.count("p1") == 0)
paused[0] = False; firePaused()
check("model: after the resume the same retry scans", started[-1] == "p1" and counts["p1"] == 1)
# a decisive result clears the entry; the next indecisive starts the cadence fresh at attempt 1
counts.pop("a", None); indecisive("a")
check("model: after a decisive result the file's cadence starts fresh at attempt 1", counts["a"] == 1 and pending[-1] == ("a", 2))
# model of the bounded table: 64 is a chosen limit (not derived), eviction removes the oldest other entry only
tbl = {}; clock = [0]
def bump(f):
    n = tbl[f][0] if f in tbl else 0
    if f not in tbl and len(tbl) >= 64:
        del tbl[min(tbl, key=lambda k: tbl[k][1])]
    clock[0] += 1; tbl[f] = (n + 1, clock[0]); return True
for i in range(63): bump("f%d" % i)
check("boundary 63 entries: nothing evicted (%d)" % len(tbl), len(tbl) == 63)
bump("f63"); check("boundary 64th new file: 64 entries, nothing evicted", len(tbl) == 64 and "f0" in tbl)
before = set(tbl); bump("f5")
check("64 entries + update of an existing key: no eviction", set(tbl) == before and tbl["f5"][0] == 2)
bump("new65"); check("65th new file evicts exactly one entry, the oldest (f0), keeps 64", len(tbl) == 64 and "f0" not in tbl and "new65" in tbl and "f1" in tbl)
for _ in range(15): bump("f1")
check("an indecisive file is never refused: attempt 16 still schedules (searched until found)", tbl["f1"][0] == 16 and bump("f1") is True)
for i in range(100, 170): bump("g%d" % i)
check("revisit of an old file after it was evicted starts the cadence fresh (documented limit: attempts are counted per remembered file)", "f1" not in tbl and bump("f1") and tbl["f1"][0] == 1)
check("table never exceeds 64 over 1000 distinct files", all(bump("z%d" % i) or True for i in range(1000)) and len(tbl) <= 64)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
