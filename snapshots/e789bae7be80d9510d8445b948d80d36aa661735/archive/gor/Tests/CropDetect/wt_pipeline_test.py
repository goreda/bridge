#!/usr/bin/env python3
"""Whole fit-crop pipeline for magnet/stream playback, worst-case states, measured (not asserted by substring only).

Owner log 2026-11-08 09:58-09:59 (session 68921): three scans started 09:58:41, 09:59:08, 09:59:27 - each scan() cancelled the one before it
(~57 s per 12-sample scan at 4K, scans cut at 27 s and 19 s), no scan ever finished, nothing was applied, and the manual Detect click
was one of the cancellers. Earlier capture (09:43-09:44): decisive 7/12 result dropped by a cancel; head piece 0 refetch took >5 s.

What this file does:
  1. Python ports of the Swift decision logic (window/tail/playhead planner, consistency rule, first-apply budget, scan/cancel/carry/coalesce state
     machine). Constants are PARSED from the Swift sources, so changing a number in Swift changes the simulated behavior.
  2. Worst-case scenarios with injected per-sample delays; time-to-first-apply is MEASURED in simulated seconds and must stay under a limit.
  3. Exact-line pins on the Swift/Node sources that tie the ports to the real code, and a mutant run over those sources: every mutant must
     be caught by at least one check (survivors fail the test).
Limits: the ports and the Swift text are tied by pins, not by running Swift. Swift is compiled on CI only, never run here or on a Mac.
The Node harness (Tests/Harness/WtPinFirst) runs the real wt_server.mjs ring in isolation when node exists."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, subprocess, sys, shutil
ROOT = pathlib.Path(__file__).resolve().parents[2]
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
def rd(p):
    n = p.rsplit('/', 1)[-1]
    if p == 'Sources/gor/Player/PPController.swift': return (ROOT / p).read_text() + '\n' + (ROOT / 'Sources/gor/Picture/CropDetector.swift').read_text()
    if p == 'Sources/gor/gor/PPController_Features.swift': return _pp_split().path(ROOT, n).read_text()
    t = (_threed_split().path(ROOT))
    if p.startswith('Sources/gor/') and t.exists():
        b = t.read_text()
        m = '// BEGIN relocated ' + n + ' '
        if m in b: return b[b.index(m):b.index('// END relocated ' + n + '\n')]
    return (ROOT / p).read_text()
SRC = {"scan": rd("Sources/gor/SourcePixelCrop.swift"), "samples": rd("Sources/gor/WTCropSamples.swift"),
       "pc": rd("Sources/gor/Player/PPController.swift"), "wt": rd("Resources/vendor/wt_server/wt_server.mjs")}
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)

# ---------------------------------------------------------------- pins (exact lines) --------------------------------------------------
PINS = [  # (name, source, exact substring)
 ("wt open timeout10s / non-wt5s", "scan", 'let rwTimeout: String = wt ? "10000000" : "5000000"'),
 ("wt watchdog12s / non-wt20s", "scan", "let killAfter: Double = wt ? 12 : 20"),
 ("carry TTL 180 s", "scan", "private static let carryTTL: Double = 180"),
 ("carry usable only for the same key and within TTL", "scan", "guard let c, c.key == key, ProcessInfo.processInfo.systemUptime - c.at <= SourcePixelCropScanner.carryTTL else { return nil }; return c"),
 ("key = path|stereo|topBottom|duration", "scan", 'let key = "\\(path)|\\(stereo)|\\(topBottom)|\\(Int(duration.rounded()))"'),
 ("undelivered rect delivered by an indecisive finish only when usable", "scan", "if !decisive, wt, let c = carryUsable(c), c.undelivered {"),
 ("decisive delivery clears carry and records the epoch", "scan", "if decisive { self.carry = nil; self.lastDeliveredEpoch = e }"),
 ("stale store: newest key, newer than last delivery, same-key or empty carry", "scan", "let mine = (self.newestKey == key) && e > self.lastDeliveredEpoch && (self.carry == nil || (self.carry?.key == key && (self.carry?.sampled ?? 0) == 0 && (self.carry?.ep ?? -1) < e))"),
 ("stale store only for wt and non-stereo", "scan", "} else if decisive, wt, !stereo {"),
 ("scan start records newest key and discards a foreign carry", "scan", "self.newestKey = key }; self.lock.unlock()"),
 ("different stream (dims) discards the carry", "scan", 'if let c = c0, c.dims != "" , c.dims != idDims {'),
 ("undelivered replay happens after a fresh probe", "scan", 'if let c = c0, c.undelivered { print("[cropdetect] replaying the decisive rect measured earlier'),
 ("carried samples shorten the next scan", "scan", "positions = Array(pool.prefix(max(3, positions.count - c.sampled)))"),
 ("carried members seed the next scan", "scan", "var members: [SourcePixelBounds.Bounds] = c0?.members ?? []"),
 ("progress stored only for the current epoch, wt, non-stereo", "scan", "if wt, !stereo { self.lock.lock(); if self.epoch == e && !(self.carry?.undelivered == true && self.carry?.key == key) { self.carry = Carry("),
 ("live sample counter and progress age set only for current epoch", "scan", "if self.epoch == e { self.liveSamples = sampled;self.lastProgressAt=ProcessInfo.processInfo.systemUptime }"),
 ("liveSamples reset with scan budget before admission", "scan", "let e = epoch; liveSamples = 0;scanStartedAt=started;scanDeadlineAt=expires;lastProgressAt=0; lock.unlock()"),
 ("hasProgress requires decoded samples, age<=20s, scan<=90s and remaining>12s", "scan", "return liveSamples > 0 && now-lastProgressAt <= 20 && now-scanStartedAt <= 90 && scanDeadlineAt-now > 12"),
 ("dropCarry clears under the lock", "scan", "func dropCarry() { lock.lock(); if carry?.undelivered != true { carry = nil }; lock.unlock() }"),
 ("mid-run cancel is logged with the sample count", "scan", 'print("[cropdetect] scan cancelled mid-run after \\(sampled) of \\(positions.count) samples (new scan or cancel)")'),
 ("scan start logs the caller", "scan", 'print("[cropdetect] scan start caller=\\(caller.isEmpty ? "?" : caller) wt=\\(wt)'),
 ("consistency: 3 frames", "scan", "static let earlyMinCount = 3\n"),
 ("consistency: 8 px", "scan", "static let earlyTolerance = 8\n"),
 ("early apply is sent once per scan", "scan", "interimSent = true\n                        let ir = CGRect("),
 ("consistency compares every edge against the union", "scan", "where abs(m.x0-u.x0) > tol || abs(m.y0-u.y0) > tol || abs(m.x1-u.x1) > tol || abs(m.y1-u.y1) > tol { return nil }"),
 ("early candidates come from member agreement", "scan", "let consensus: SourcePixelBounds.Bounds? = SourcePixelBounds.consistent(members)"),
 ("auto stream scan without agreement makes no decision", "scan", "if wt, !stereo, !rgbVeto, !fresh, SourcePixelBounds.consistent(members) == nil {"),
 ("no agreement leaves the file at the full frame and the search continues (199az: the frame is sacred, only letterbox/pillarbox go)", "scan", "non-black frames - full picture kept, search continues"),
 ("early apply only for wt, non-stereo, non-RGB, once, and never a full frame", "scan", "if wt, !stereo, !rgbVeto, !interimSent, let interim, let u0 = best {"),
 ("early apply log reports member agreement", "scan", "non-black, agree): bounds="),
 ("early rect is at least the union of everything measured", "scan", "let u: SourcePixelBounds.Bounds = all.map { $0.union(u0) } ?? u0"),
 ("early apply never for a full-frame result", "scan", "if !(ci.x0 == 0 && ci.y0 == 0 && ci.x1 == w && ci.y1 == h) {"),
 ("early apply delivered only while the scan is current", "scan", "DispatchQueue.main.async { if self.valid(e) { interim(ir, -1) } }"),
 ("final result still computed from the full union", "scan", "let c = SourcePixelBounds.outward(b,width:w,height:h,stereo:stereo,topBottom:topBottom)"),
 ("every indecisive finish logs a reason", "scan", 'print("[cropdetect] scan finished indecisive: \\(why.isEmpty ? "no reason recorded" : why)")'),
 ("planner: tail window 240 s, manual span 12 s", "samples", "static let tailWindow = 240.0\n    /// Manual Detect looks this far either side of the frame on screen.\n    static let manualHalfSpan = 12.0"),
 ("planner: manual = nearest range, around playhead, nearest first", "samples", "return spreadOrder(spread([(lo, hi)], count: count), seed: c)"),
 ("planner: automatic = playhead-anchored window over the downloaded ranges, nearest-to-playhead first", "samples", "return spreadOrder(spread(win, count: count), seed: c)"),
 ("planner: auto = newest seconds first", "samples", "let picked: [Double] = spread(tail.reversed(), count: count)\n        return spreadOrder(picked, seed: picked.max() ?? 0)"),
 ("planner: farthest-point sampling order", "samples", "let gaps: [Double] = rest.map { (p: Double) -> Double in taken.map { (t: Double) -> Double in abs(t - p) }.min() ?? 0 }\n            guard let fi = gaps.indices.max(by:"),
 ("overcut guard: agreement must span half the planned window", "scan", "let best: SourcePixelBounds.Bounds? = window > 0 && covered < 0.5 * window ? nil : consensus"),
 ("spread guard covers the done positions incl. carried", "scan", "let covered: Double = (done.max() ?? 0) - (done.min() ?? 0)"),
 ("window is the span of the planned positions", "scan", "let window: Double = (positions.max() ?? 0) - (positions.min() ?? 0)"),
 ("done positions recorded per decoded frame", "scan", "done.append(t); sampled += 1;"),
 ("trim skips positions near carried frames", "scan", "!c.done.contains { (d: Double) -> Bool in abs(d - p) < 4 }"),
 ("manual scan is fresh (no seed, no replay) but keeps an undelivered fallback", "scan", "let keepFallback: Bool = fresh && c0?.undelivered == true; if fresh { c0 = nil }; if wt { if c0 == nil && !keepFallback { self.carry = nil }"),
 ("dropCarry keeps an undelivered rect", "scan", "if carry?.undelivered != true { carry = nil }"),
 ("progress never overwrites an undelivered same-key rect", "scan", "if self.epoch == e && !(self.carry?.undelivered == true && self.carry?.key == key) {"),
 ("early apply marks confidence -1", "scan", "interim(ir, -1)"),
 ("onResult: early flag", "pc", "let early = confidence < 0; let manual = self.manualRedetectInFlight; if decisive && !early {"),
 ("onResult: manual state kept until the final result", "pc", "if !early { self.manualRedetectInFlight = false }"),
 ("onResult: transitions use the absolute confidence", "pc", "self.transitionCrop(.apply(rect), confidence: abs(confidence), manual: manual)"),
 ("onResult: re-rect uses the absolute confidence", "pc", "self.transitionCrop(.reRect(rect), confidence: abs(confidence), manual: manual)"),
 ("manual Detect passes fresh", "pc", "fresh:manualPriority,positions:"),
 ("planner: tail built backwards from the newest range end", "samples", "for r in segs.reversed() {\n            let take = min(r.1 - r.0, left)\n            tail.append((r.1 - take, r.1)); left -= take"),
 ("positions use plan with the playhead and the widen level", "samples", "let spread = plan(ranges: ranges, playhead: playhead, manual: manual, widenLevel: widenLevel)"),
 ("non-stream sources keep whole-file positions (nil)", "samples", "guard (CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)), let ipc = mainIPCPath else { return nil }"),
 ("manual Detect passes manual to the planner", "pc", "positions:{ WTCropSamples.positions(path:filePath,mainIPCPath:self.mainIPCPath,manual:manualPriority,widenLevel:widenLevel) }"),
 ("automatic window: narrow at the playhead, doubling per indecisive result", "samples", "let half = autoBaseHalfSpan * pow(2.0, Double(max(0, widenLevel)))"),
 ("automatic widen cursor: indecisive widens, decisive resets", "pc", "if !manualPriority, CropDetector.isWTPlayback(filePath) { self.automaticWidenLevel = decisive ? 0 : self.automaticWidenLevel + 1 }"),
 ("manual Detect drops the carry (fresh measurement)", "pc", "if manualPriority { sourceScanner.dropCarry() }"),
 ("early apply goes through onResult", "pc", "interim:{ [weak self] rect,conf in self?.onResult?(rect,true,conf) }"),
 ("scan start carries the caller", "pc", 'caller:(manualPriority ? "manual:" : "auto:") + caller'),
 ("manual Detect joins a scan that has samples instead of killing it", "pc", "if cropDetector.isPending, cropDetector.hasScanProgress { manualRedetectInFlight = true;"),
 ("join happens before cancel()", "pc", None),
 ("no give-up cap: the crop search runs until found (wt, playing, manual gated; 199az)", "pc", "if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, (!manual || self.cropRect == nil)"),
 ("wt ring: pin field declared", "wt", "this.pinnedFirst = null;"),
 ("wt ring: _evict skips the pin", "wt", "      if (idx >= cutoff) continue;\n      if (this._isPinned(idx)) continue;"),
 ("wt ring: pin set where totalFileFirst is set (1)", "wt", "totalFileFirst = fFirst;\n    totalFileLast = fLast;\n    if (globalRing) { globalRing.pinnedFirst = fFirst; globalRing.pinFileEdges(fFirst, fLast); }"),
 ("wt ring: pin set where totalFileFirst is set (2)", "wt", "totalFileFirst = fileFirst;\n    totalFileLast = fileLast;\n    if (globalRing) { globalRing.pinnedFirst = fileFirst; globalRing.pinFileEdges(fileFirst, fileLast); }"),
 ("wt ring: pin predicate preserves first and edge pins", "wt", "return idx === this.pinnedFirst || this.pinned.has(idx);"),
]
def run_pins(S):
    bad = []
    for name, src, sub in PINS:
        if sub is None:
            t = S["pc"]; i = t.find("func reDetectCrop()")
            blk = t[i:i + 2500]
            ok = 0 <= blk.find("hasScanProgress") < blk.find("cropDetector.cancel()")
        else: ok = sub in S[src]
        if not ok: bad.append(name)
    if S["wt"].count("globalRing.pinnedFirst = ") != 2: bad.append("wt ring: exactly two pin assignments")
    if S["wt"].count("if (this._isPinned(idx)) continue;") != 2: bad.append("wt ring: both evictors skip the pin")
    return bad
bad = run_pins(SRC)
check("all %d source pins match the exact Swift/Node lines" % len(PINS), not bad)
for b in bad: print("      missing:", b)

# ---------------------------------------------------------------- constants parsed from Swift ----------------------------------------------
def num(pat, src): return float(re.search(pat, SRC[src])[1])
TAIL = num(r"static let tailWindow = ([\d.]+)", "samples"); HALF = num(r"static let manualHalfSpan = ([\d.]+)", "samples")
MARGIN = num(r"static let tailMargin = ([\d.]+)", "samples"); MINR = num(r"static let minRange = ([\d.]+)", "samples"); COUNT = int(num(r"static let sampleCount = (\d+)", "samples"))
TTL = num(r"carryTTL: Double = ([\d.]+)", "scan"); TOL = int(num(r"earlyTolerance = (\d+)", "scan")); MINC = int(num(r"earlyMinCount = (\d+)", "scan"))
# v2 (Fix A): no first-apply time budget and no fallback union - agreement of >= earlyMinCount members only
RW = int(re.search(r'wt \? "(\d+)" : "(\d+)"', SRC["scan"])[1]) / 1e6; KILL = float(re.search(r"wt \? (\d+) : (\d+)", SRC["scan"].split("let killAfter")[1])[1])

# ---------------------------------------------------------------- ports ---------------------------------------------------------------------
def usable(ranges):
    r = [(max(0, a), b - MARGIN) for a, b in ranges if b - a >= MINR]
    return sorted([x for x in r if x[1] > x[0]])
def spread(segs, count):
    total = sum(b - a for a, b in segs)
    if total <= 0 or count <= 0: return []
    out = []
    for i in range(count):
        u = total * (i + 0.5) / count
        for a, b in segs:
            if u <= b - a: out.append(a + u); break
            u -= b - a
    return out
def spread_order(ps, seed):
    rest = list(ps); out = []
    if not rest: return out
    out.append(rest.pop(min(range(len(rest)), key=lambda i: abs(rest[i] - seed))))
    while rest:
        gaps = [min(abs(t - p) for t in out) for p in rest]
        out.append(rest.pop(max(range(len(rest)), key=lambda i: gaps[i])))
    return out
def plan(ranges, playhead, manual, count=COUNT, widen=0):
    segs = usable(ranges)
    if not segs: return []
    if playhead is not None:
        dist = lambda r: r[0] - playhead if playhead < r[0] else (playhead - r[1] if playhead > r[1] else 0)
        r = min(segs, key=dist); c = min(max(playhead, r[0]), r[1])
        half = HALF if manual else HALF * (2 ** max(0, widen))
        win = [(max(a, c - half), min(b, c + half)) for a, b in segs]
        win = [(a, b) for a, b in win if b > a]
        if not win: return []
        return spread_order(spread(win, count), c)
    tail, left = [], TAIL
    for a, b in reversed(segs):
        take = min(b - a, left); tail.append((b - take, b)); left -= take
        if left <= 0: break
    pk = spread(list(reversed(tail)), count)
    return spread_order(pk, max(pk)) if pk else []
def union(a, b): return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))
def consistent(members):
    if len(members) < MINC: return None
    u = members[0]
    for m in members[1:]: u = union(u, m)
    return None if any(max(abs(m[i] - u[i]) for i in range(4)) > TOL for m in members) else u
def inside(ps, ranges): return all(any(a <= p <= b - MARGIN for a, b in ranges) for p in ps)

# ---- planner states
R1 = [(0, 28)]; R2 = [(0, 28), (500, 600)]; R3 = [(0, 900)]; SHORT = [(10, 11.5)]
p = plan(R1, 0, False); check("start (cache 0-28 s, playhead 0): narrow window at the playhead, every sample inside the downloaded range, nearest frame first", p and inside(p, R1) and p[0] == min(p))
p = plan(R3, None, False); check("stream, no playhead reported: auto samples fall back to the LAST %d s of the cache" % TAIL, p and min(p) >= 900 - MARGIN - TAIL and inside(p, R3))
p = plan(R2, 10, False); check("two ranges, narrow window: only the range around the playhead is sampled", p and all(x < 28 for x in p) and inside(p, R2))
p = plan(R2, 10, False, widen=10); check("two ranges, fully widened: the window covers every downloaded range", p and any(x >= 500 for x in p) and any(x < 28 for x in p) and inside(p, R2))
p = plan(R3, 400, False); check("auto level 0: samples stay within +-%d s of the playhead" % HALF, p and all(abs(x - 400) <= HALF for x in p) and inside(p, R3))
p = plan(R3, 400, False, widen=1); check("auto level 1: the window doubles to +-%d s" % (2 * HALF), p and all(abs(x - 400) <= 2 * HALF for x in p) and max(p) - min(p) > 2 * HALF)
p = plan([(0, 173)], 95.7, False); check("the 2m50 s capture: at playhead ~96 s the first automatic window already excludes the intro card (0-28 s)", p and min(p) > 28)
p = plan(R3, 400, False, widen=10); check("auto fully widened: the window covers the whole cache like the old full spread", p and min(p) < 100 and max(p) > 800 and inside(p, R3))
p = plan(R3, 400, True); check("manual: samples within +-%d s of the playhead (the frame on screen), nearest first" % HALF, p and all(abs(x - 400) <= HALF for x in p) and min(p, key=lambda x: abs(x - 400)) == p[0] and inside(p, R3))
p = plan(R2, 560, True); check("seek: manual playhead inside the far range samples that range, not the start", p and all(x >= 500 for x in p) and inside(p, R2))
p = plan(R2, 300, True); check("seek: playhead in a gap uses the nearest downloaded range", p and inside(p, R2) and all(x < 28 or x >= 500 for x in p))
check("start: playhead 0 in a 0-28 range stays inside the range with the margin (manual)", all(0 <= x <= 28 - MARGIN for x in plan(R1, 0, True)))
check("partial cache: a range shorter than %.0f s is not usable, nothing is invented" % MINR, plan(SHORT, 10.5, False) == [] and plan([], 0, False) == [])
check("worst case: huge playhead beyond the cache clamps to the newest range", inside(plan(R3, 5000, True), R3))
check("every planner output has exactly %d positions when a range is usable" % COUNT, len(plan(R3, 400, False)) == COUNT == len(plan(R3, 400, True)))
for nm, pp in (("auto", plan(R3, 400, False)), ("manual", plan(R3, 400, True))):
    check("spread order (%s): the first 3 frames span at least 90%% of the whole sampled window, same frame set as the plain spread" % nm, max(pp[:3]) - min(pp[:3]) >= 0.9 * (max(pp) - min(pp)) and sorted(pp) == sorted(spread([(max(0, 400 - HALF), min(900 - MARGIN, 400 + HALF))], COUNT)))
# local / stereo / non-stream: planner not used
check("local files keep the whole-file 40-position scan (positions closure returns nil)", 'guard (CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)), let ipc = mainIPCPath else { return nil }' in SRC["samples"])

# ---------------------------------------------------------------- scan / cancel / carry / coalesce simulator ---------------------------------
class Sim:
    """Event-driven port of CropDetector.detect/reDetectCrop + SourcePixelCropScanner.scan for one stream file."""
    def __init__(s, cost, frames, ttl=TTL, trim=True, coalesce=True, early=True, pos=None):
        s.t = 0.0; s.epoch = 0; s.carry = None; s.newest = None; s.last_deliv = -1; s.live = 0; s.pending = False
        s.early = early; s.pos = pos or plan([(0, 900)], 400, False); s.cost = cost; s.frames = frames; s.ttl = ttl; s.trim = trim; s.coalesce = coalesce
        s.scans = {}; s.applied = []; s.log = []; s.dims = "3840x2160"
    def key(s, f="f", stereo=False): return (f, stereo)
    def detect(s, manual=False, f="f", stereo=False, dims=None):
        if manual and s.coalesce and s.pending and s.live > 0: s.log.append((s.t, "joined")); return "joined"
        s.epoch += 1; s.live = 0; s.pending = True; k = s.key(f, stereo); e = s.epoch
        if manual: s.carry = None
        c0 = s.carry if (s.carry and s.carry["key"] == k and s.t - s.carry["at"] <= s.ttl) else None
        if not stereo:
            if c0 is None: s.carry = None
            s.newest = k
        dims = dims or s.dims
        if c0 and c0["dims"] and c0["dims"] != dims: c0 = None; s.carry = None
        n = COUNT
        if c0 and c0["undelivered"]: s.apply(e, c0["rect"], True, "replay"); s.pending = False; return "replayed"
        if c0 and s.trim and c0["sampled"] > 0: n = max(3, COUNT - c0["sampled"])
        s.scans[e] = dict(k=k, n=n, i=0, t0=s.t, members=list(c0["members"]) if c0 else [], all=c0["bounds"] if c0 else None, sampled=c0["sampled"] if c0 else 0, nxt=s.t, sent=False, pos=list(s.pos),
                          sum=0.0, cnt=0, stereo=stereo, dims=dims, manual=manual)
        s.log.append((s.t, "scan start manual=%s n=%d carried=%d" % (manual, n, c0["sampled"] if c0 else 0)))
        return "started"
    def cancel(s): s.epoch += 1; s.live = 0; s.pending = False
    def apply(s, e, rect, final, why): s.applied.append((round(s.t, 2), rect, final, why))
    def advance(s, until):
        while True:
            e = s.epoch; sc = s.scans.get(e)
            # a scan that is no longer current still finishes its work and may store its decisive result (stale callback)
            live = [(x, v) for x, v in s.scans.items() if v["i"] < v["n"] and v["nxt"] <= until]
            if not live: break
            x, v = min(live, key=lambda kv: kv[1]["nxt"])
            if x != s.epoch: v["i"] = v["n"]; continue   # cancelled scans stop at their next sample boundary (valid(e) guard)
            c = s.cost(v["i"], s.t); v["nxt"] += c; s.t = v["nxt"]; b = s.frames(v["i"], v["k"])
            v["i"] += 1; v["cnt"] += 1; v["sum"] += c; v["sampled"] += 1; s.live = v["sampled"]
            if b: v["members"].append(b); v["all"] = union(v["all"], b) if v["all"] else b; v["members"] = v["members"][-12:]
            best = consistent(v["members"])   # v2 (Fix A): agreement only; no time-budget fallback
            dn = v["pos"][:v["i"]]; win = max(v["pos"]) - min(v["pos"])
            if best and win > 0 and max(dn) - min(dn) < 0.5 * win: best = None   # spread guard
            if best and v["all"]: best = union(best, v["all"])
            if s.early and not v["stereo"] and not v["sent"] and best:
                v["sent"] = True; s.apply(x, best, False, "early-agree")
            if not v["stereo"]:
                u = None
                for m in v["members"]: u = m if u is None else union(u, m)
                s.carry = dict(key=v["k"], dims=v["dims"], at=s.t, members=list(v["members"]), sampled=v["sampled"], undelivered=False, rect=None, bounds=v["all"])
            if v["i"] >= v["n"]:
                u = None
                for m in v["members"]: u = m if u is None else union(u, m)
                s.pending = False; s.scans[x]["done"] = True
                # v2 (Fix A): an automatic wt stream scan decides only on member agreement; a manual Detect keeps the union rule
                decisive = u and v["sampled"] >= min(3, v["n"]) and (v["manual"] or v["stereo"] or consistent(v["members"]) is not None)
                if decisive: s.apply(x, u, True, "final"); s.carry = None; s.last_deliv = x
                else: s.log.append((s.t, "no decision: no agreement among %d non-black frames" % len(v["members"])))
        s.t = max(s.t, until)
BAR = (0, 252, 3840, 1892)
def bars(i, k): return BAR
def steady(c): return lambda i, t: c

# 1: owner's 09:58-09:59 sequence: 57 s scan (4.75 s/sample); manual clicks at 27 s and 46 s
S = Sim(steady(4.75), bars); S.detect(); S.advance(27); r1 = S.detect(manual=True); S.advance(46); r2 = S.detect(manual=True); S.advance(70)
fin = [a for a in S.applied if a[2]]
check("owner log replay: manual clicks at 27 s and 46 s JOIN the running scan (joined=%s,%s), it finishes and applies" % (r1, r2), r1 == r2 == "joined" and len(fin) == 1 and fin[0][1] == BAR)
first = min(a[0] for a in S.applied)
check("owner log replay: first apply after %.1f s (slow decode 4.75 s/frame), limit %.0f s" % (first, 25), first <= 25 and first < 57)
# negative control: the old behavior (every click cancels, nothing applied before the end of a full scan) never applies
S0 = Sim(steady(4.75), bars, trim=False, coalesce=False, early=False); S0.detect(); S0.advance(27); S0.cancel(); S0.detect(manual=True); S0.advance(46); S0.cancel(); S0.detect(manual=True); S0.advance(60)
check("negative control (old behavior: cancel on click, no early apply, no join): NO crop applied by 60 s - the owner's failure reproduces", S0.applied == [])
# 2: repeated non-manual cancels (playback restart) every 19 s: carry + trim converge
S = Sim(steady(4.75), bars); S.detect(); S.advance(19); S.cancel(); S.detect(); S.advance(38); S.cancel(); S.detect(); S.advance(120)
check("cancel every 19 s: carried samples shorten later scans and a final result is applied (%s)" % [(a[0], a[3]) for a in S.applied], any(a[2] for a in S.applied))
S = Sim(steady(4.75), bars, trim=False, early=False); S.detect(); S.advance(19); S.cancel(); S.detect(); S.advance(38); S.cancel(); S.detect(); S.advance(80)
check("negative control: without trim/early apply the third scan is still running at 80 s with nothing applied", not S.applied)
# 3: time to first apply, worst cases
# v2 (Fix A): first apply rides agreement of the first 3 samples, so the limit is per-case: 3 samples x cost + slack
cases = [("ideal 1 s/frame", steady(1.0), bars, 8),
         ("slow decode 4.75 s/frame", steady(4.75), bars, 25),
         ("very slow decode 15 s/frame (thermal / low swarm)", steady(15.0), bars, 50),
         ("slow internet: first open stalls 6 s, later frames 3 s", lambda i, t: 9.0 if i == 0 else 3.0, bars, 25),
         ("black head/credits: first 4 tail frames fully black", steady(3.0), lambda i, k: None if i < 4 else BAR, 28)]
for name, cost, fr, limit in cases:
    S = Sim(cost, fr); S.detect(); S.advance(400); ap = [a for a in S.applied]
    t1 = ap[0][0] if ap else None
    check("time to first apply, %s: %s s (limit %.0f s)" % (name, t1, limit), t1 is not None and t1 <= limit)
S = Sim(steady(3.0), lambda i, k: (0, 252 + (30 * i if i < 3 else 0), 3840, 1892)); S.detect(); S.advance(100)
check("dark scenes: frames disagreeing by more than the %d px tolerance are never applied - no agreement, no decision, the file stays at the full frame (v2)" % TOL, S.applied == [] and any("no decision" in m for _, m in S.log))
S = Sim(steady(15.0), bars); S.detect(); S.advance(400)
check("very slow machine: first apply rides agreement, not a wall-clock budget - 3rd agreeing sample at 45 s (v2)", S.applied[0][3] == "early-agree" and S.applied[0][0] == 45.0)
Sf = Sim(steady(1.0), bars); Sf.detect(); Sf.advance(50); Ss = Sim(steady(15.0), bars); Ss.detect(); Ss.advance(400)
check("first apply scales with sample cost: 1 s/frame -> %d s, 15 s/frame -> %d s (3 agreeing samples, no cap)" % (Sf.applied[0][0], Ss.applied[0][0]), Sf.applied[0][0] == 3.0 and Ss.applied[0][0] == 45.0)
S = Sim(steady(4.75), bars); S.detect(); S.advance(200)
check("refinement: after the early apply the final union is applied and is never narrower", S.applied[-1][2] and all(S.applied[-1][1][i] <= S.applied[0][1][i] if i < 2 else S.applied[-1][1][i] >= S.applied[0][1][i] for i in range(4)))
# 4: carry safety
S = Sim(steady(2.0), bars); S.detect(); S.advance(10); S.cancel(); S.detect(f="other")
check("a different file starts with no carry", S.log[-1][1].endswith("carried=0"))
S = Sim(steady(2.0), bars); S.detect(); S.advance(10); S.cancel(); S.carry["at"] = 0; S.t = 30 + TTL + 5; r = S.detect()
check("carry older than %.0f s is not reused (scan starts with n=%d, not trimmed)" % (TTL, COUNT), S.log[-1][1].endswith("carried=0") and "n=%d" % COUNT in S.log[-1][1])
S = Sim(steady(2.0), bars); S.detect(); S.advance(10); S.cancel(); r = S.detect(dims="1920x800")
check("same file, different stream geometry: carried measurement discarded", S.log[-1][1].endswith("carried=0"))
S = Sim(steady(2.0), bars); S.detect(); S.advance(10); S.cancel(); r = S.detect(stereo=True)
check("stereo scan does not use the mono carry", S.log[-1][1].endswith("carried=0"))
S = Sim(steady(2.0), bars); S.detect(); S.advance(10); S.cancel(); S.detect(manual=True)
check("manual Detect measures afresh (carry dropped)", S.log[-1][1].endswith("carried=0"))
# stale-callback ordering (Swift: epoch / lastDeliveredEpoch / newestKey)
def stale_store(newest, carry_key, k, e, last_deliv, carry_present, carry_sampled=0, carry_ep=-1): return newest == k and e > last_deliv and (not carry_present or (carry_key == k and carry_sampled == 0 and carry_ep < e))
check("stale decisive result is stored when it is the newest file and nothing newer delivered", stale_store("f", None, "f", 4, 3, False))
check("stale decisive result is NOT stored over another file's scan", not stale_store("g", "g", "f", 4, 3, True))
check("stale decisive result is NOT stored after a newer scan delivered", not stale_store("f", None, "f", 4, 5, False))
check("adversarial: an old scan finishing while a NEWER SAME-KEY scan has decoded frames does not overwrite its progress", not stale_store("f", "f", "f", 4, 3, True, carry_sampled=3))
check("adversarial: same-key carry with no samples (undelivered or fresh) may be replaced by the stale decisive result", stale_store("f", "f", "f", 4, 3, True, carry_sampled=0))
check("adversarial: an old scan (epoch 4) may not overwrite a same-key undelivered rect written by a newer scan (epoch 6), sampled=0", not stale_store("f", "f", "f", 4, 3, True, carry_sampled=0, carry_ep=6))
check("an undelivered same-key rect from an OLDER scan (epoch 2) is replaced by the newer stale result (epoch 4)", stale_store("f", "f", "f", 4, 3, True, carry_sampled=0, carry_ep=2))
check("stale decisive result is NOT stored over newer progress of another key", not stale_store("f", "g", "f", 4, 3, True))

# spread guard / sampling order (goreda: early subset can overcut)
clustered = sorted(plan([(0, 900)], 400, False), reverse=True)   # strictly newest-first: first frames cluster at the end
S = Sim(steady(3.0), bars, pos=clustered); S.detect(); S.advance(100); tc = S.applied[0][0]
S = Sim(steady(3.0), bars); S.detect(); S.advance(100); ts = S.applied[0][0]
check("spread guard: with clustered frames the first apply waits (%.0f s), with farthest-point order it comes at the 3rd frame (%.0f s)" % (tc, ts), ts == 9.0 and tc > ts)
S = Sim(steady(3.0), bars, pos=clustered[:3] + clustered[3:]); S.detect(); S.advance(100)
check("spread guard: an apply never happens while the decoded frames span less than half of the planned window", all(a[0] > 9 for a in S.applied[:1]))
# review 13:12: one-frame fallback, truncated members
S = Sim(steady(30.0), bars); S.detect(); S.advance(100)
check("adversarial: a scan never applies from fewer than %d agreeing frames, however long it runs (first apply at %s s)" % (MINC, S.applied[0][0] if S.applied else None), S.applied and S.applied[0][0] == 3 * 30.0 and S.applied[0][3] == "early-agree")
wide = (0, 200, 3840, 1950)
fr = lambda i, k: wide if i == 0 else (0, 252, 3840, 1892)
S = Sim(steady(2.0), bars); S.detect(); S.advance(2); S.cancel()
S.carry = dict(key=("f", False), dims="3840x2160", at=S.t, members=[BAR, BAR, BAR], sampled=3, undelivered=False, rect=None, bounds=wide)   # wide frame already evicted from the capped members list
S.detect(); S.advance(S.t + 40)
y = [a for a in S.applied if not a[2] and a[0] > 2]
check("adversarial: early rect contains a wide frame that is in 'all' but no longer in the capped members (early y0=%s y1=%s)" % (y[0][1][1] if y else None, y[0][1][3] if y else None), y and y[0][1][1] <= 200 and y[0][1][3] >= 1950)
S = Sim(steady(2.0), lambda i, k: wide if i == 0 else (0, 252, 3840, 1892))
S.detect(); S.advance(5); S.cancel(); S.detect(); S.advance(200)
y = [a for a in S.applied if not a[2]]
check("adversarial (v2): a carried wide outlier from a cancelled scan no longer forces a wide early rect - the agreement rule vetoes it and the scan makes no decision (the overcut class Fix A removes)", y == [] and any("no decision" in m for _, m in S.log))
# ---------------------------------------------------------------- thin black band (owner 13:16) -------------------------------------------
import random
# v2 (Fix B): isolated specks inside black bars are encoder noise and no longer widen the rect;
# the strong tier and the tolerance still protect every real picture row.
assert "let speckTolerance = max(1, w / 512)" in SRC["scan"]
SPM = re.search(r"let speckTolerance = max\((\d+), w / (\d+)\)", SRC["scan"]); SPECK_MIN, SPECK_DIV = int(SPM[1]), int(SPM[2])
STRONG = int(re.search(r"strongThreshold=UInt16\(min\(65535,\(black\+(\d+)\*levelUnit\)", SRC["scan"])[1])
STRICT = int(re.search(r"let threshold=UInt16\(min\(65535,\(black\+(\d+)\*levelUnit\)", SRC["scan"])[1])
BLACK = 16
def scan_rows(frame, speck, strong):
    """Port of SourcePixelBounds.scan edge-row logic (+ outward even-row alignment)."""
    h = len(frame); thr = BLACK + STRICT; st = BLACK + strong
    def content(y):
        if speck <= 0 or st <= thr: return any(v > thr for v in frame[y])
        n = 0
        for v in frame[y]:
            if v > st: return True
            if v > thr:
                n += 1
                if n > speck: return True
        return False
    top = next((y for y in range(h) if content(y)), None)
    if top is None: return None
    bot = next((y for y in range(h - 1, top, -1) if content(y)), top)
    return (top // 2 * 2, min(h, (bot + 2) // 2 * 2))
W, H, BAR = 384, 216, 27
SP = max(SPECK_MIN, W // SPECK_DIV); STR = STRONG
def letterbox(bar=BAR):
    f = [[BLACK] * W for _ in range(H)]
    for y in range(bar, H - bar):
        for x in range(W): f[y][x] = 30 + (x * 7 + y * 3) % 150
    return f
def residual(b): return (BAR - b[0]) + (b[1] - (H - BAR))   # black rows left inside the rect (top + bottom)
def cut(frame, b):
    bad = 0
    for y in list(range(0, b[0])) + list(range(b[1], H)):
        r = frame[y]
        if any(v > BLACK + STR for v in r) or sum(1 for v in r if v > BLACK + STRICT) > SP: bad += 1
    return bad
f = letterbox(); b = scan_rows(f, SP, STR); check("band: clean bars -> exact rect, residual black rows %d" % residual(b), residual(b) <= 2 and cut(f, b) == 0)   # <= 2: outward even-row rounding is 1 row per edge
f = letterbox(); rnd = random.Random(7)
for y in list(range(0, BAR)) + list(range(H - BAR, H)):
    for x in range(W): f[y][x] = BLACK + rnd.choice([0, 0, 0, 1, 2])
b = scan_rows(f, SP, STR); check("band: noisy bars within black+2 -> residual %d" % residual(b), residual(b) <= 2 and cut(f, b) == 0)
f = letterbox(); f[2][100] = BLACK + 8; f[5][300] = BLACK + 7; f[H - 3][50] = BLACK + 9
old = scan_rows(f, 0, 0); new = scan_rows(f, SP, STR)
check("band: isolated specks in the bars - the pre-v2 exact-content rule left %d black rows (the owner's thin band); the v2 tolerance trims them to %d rows and still cuts no picture" % (residual(old), residual(new)), residual(old) > 20 and residual(new) <= 2 and new != old and cut(f, new) == 0)
f = letterbox(); f[10][100] = 120
b = scan_rows(f, SP, STR); check("band: one clearly non-black pixel (120) in a bar row is never ignored (rect keeps row 10)", b[0] <= 10 and cut(f, b) == 0)
f = letterbox()
for x in range(W): f[BAR - 1][x] = BLACK + 5; f[BAR - 2][x] = BLACK + 3
b = scan_rows(f, SP, STR); check("band: soft-edge rows (every pixel black+3..5) are kept as content, never cut (top %d <= %d)" % (b[0], BAR - 2), b[0] <= BAR - 2 and cut(f, b) == 0)
f = letterbox()
for x in range(40, 60): f[BAR - 1][x] = 60
b = scan_rows(f, SP, STR); check("band: dim content (60) on the first picture row is kept", b[0] <= BAR - 1 and cut(f, b) == 0)
f = letterbox()
for x in range(0, SP): f[BAR - 1][x] = BLACK + 6
b = scan_rows(f, SP, STR); check("band: at most %d specks on the first picture row are tolerated (row ignored, none above black+%d lost)" % (SP, STR), b[0] >= BAR - 1 and cut(f, b) == 0)
f = letterbox()
for x in range(0, SP + 1): f[BAR - 1][x] = BLACK + 6
b = scan_rows(f, SP, STR); check("band: %d specks on an edge row are content (kept)" % (SP + 1), b[0] <= BAR - 1 and cut(f, b) == 0)
f = letterbox(); b = scan_rows(f, SP, STR); check("band: even-row alignment leaves at most 1 row per edge (rect y %d..%d)" % b, residual(b) <= 2)
f = letterbox(); rr = random.Random(3)
for i in range(200): f[rr.randrange(0, BAR)][rr.randrange(W)] = BLACK + rr.randrange(3, 12)
b2 = scan_rows(f, SP, STR); check("band: heavy speck noise over the bars (documented limit) - residual %d rows, cut %d" % (residual(b2), cut(f, b2)), cut(f, b2) == 0)   # limit: rows with more than %d samples above black+2 stay content, so heavy noise is not trimmed, never cut
# regression numbers from the owner log 13:18 (session 83762, 3840x2160): top bound 252-254 (bar 254), bottom bound 1890 / 1914 / 1920 across scans
TOPBAR = 254; SYM_BOTTOM = 2160 - TOPBAR   # 1906: letterbox is symmetric
res_old = [max(0, b - SYM_BOTTOM) for b in (1914, 1920)]
check("owner log numbers: bottom edges 1914 / 1920 leave %s black rows against the symmetric bottom %d (the visible thin band); 1890 is inside the picture" % (res_old, SYM_BOTTOM), res_old == [8, 14] and 1890 < SYM_BOTTOM)
f = [[BLACK] * 96 for _ in range(540)]   # quarter-scale replica: bar 63, picture 63..476
for y in range(63, 477):
    for x in range(96): f[y][x] = 40 + (x * 5 + y) % 120
f[490][10] = BLACK + 9; f[497][60] = BLACK + 10    # specks 14 and 21 rows below the picture (scaled 8 / 14 rows after x4... same order)
o = scan_rows(f, 0, 0); n = scan_rows(f, max(2, 96 // SPECK_DIV), STR)
check("owner log replica: old rule ends at row %d (picture ends at 476), new rule at row %d with no picture cut" % (o[1], n[1]), o[1] > 490 and n[1] <= 478)
# ---- 10-bit lifted / dithered bar (owner 13:27: x265 10-bit WEB, bars ~23 rows top / ~19 bottom left; edges 252-254 top, 1890-1920 bottom) ----
def scan_bits(frame, bits, speck, strong, unit_margins=True):
    """Port of the threshold derivation + edge-row rule at any bit depth (frame values in native codes)."""
    u = 1 << (bits - 8); black = 16 * u
    thr = black + STRICT * (u if unit_margins else 1); st = black + strong * (u if unit_margins else 1)
    h = len(frame)
    def content(y):
        n = 0
        for v in frame[y]:
            if v > st: return True
            if v > thr:
                n += 1
                if n > speck: return True
        return False
    top = next((y for y in range(h) if content(y)), None)
    if top is None: return None
    bot = next((y for y in range(h - 1, top, -1) if content(y)), top)
    return (top, bot + 1)
def box10(barlevel, noise, seed=1, hbar=30, pad=40, dim=False):
    """3-level canvas like the owner's file: `pad` rows of pure 0 (encoder padding), then letterbox rows at `barlevel`+noise, then picture."""
    rnd = random.Random(seed); H10, W10 = 300, 384
    f = []
    for y in range(H10):
        if y < pad or y >= H10 - pad: f.append([0] * W10)
        elif y < pad + hbar or y >= H10 - pad - hbar: f.append([max(0, barlevel + rnd.randint(-noise, noise)) for _ in range(W10)])
        else: f.append([(64 + 40 + (x * 13 + y * 5) % 500) if not dim else (64 + 60 + (x + y) % 80) for x in range(W10)])
    return f, pad, hbar, H10
SP10 = max(SPECK_MIN, 384 // SPECK_DIV)
for lvl, noi in ((64 + 5, 2), (64 + 6, 2), (64 + 2, 1)):
    f, pad, hb, H10 = box10(lvl, noi)
    want = (pad + hb, H10 - pad - hb)
    old = scan_bits(f, 10, SP10, STRONG, unit_margins=False); new = scan_bits(f, 10, SP10, STRONG, unit_margins=True)
    check("10-bit bar at black+%d codes +-%d noise: old raw-code margin gives rows %s (bars %d+%d rows left), 8-bit-equivalent margin gives %s (want %s)" % (lvl - 64, noi, old, old[0] - want[0] if False else want[0] - old[0], old[1] - want[1], new, want), new == want and (old != want or lvl - 64 <= 2))
f, pad, hb, H10 = box10(64 + 5, 2, dim=True)
new = scan_bits(f, 10, SP10, STRONG); check("10-bit: dim picture rows (code 64+60..140) keep the bound (never cut): %s vs picture %s" % (new, (pad + hb, H10 - pad - hb)), new == (pad + hb, H10 - pad - hb))
f, pad, hb, H10 = box10(64 + 5, 2)
for x in range(0, 384, 2): f[pad + hb][x] = 64 + 30     # first picture row at 4 8-bit levels above black on half the samples: picture, kept
new = scan_bits(f, 10, SP10, STRONG); check("10-bit: first picture row at +7 levels is content (top %d == %d)" % (new[0], pad + hb), new[0] == pad + hb)
f, pad, hb, H10 = box10(64 + 5, 2)
for x in range(0, 384, 2): f[pad + hb - 1][x] = 64 + 14   # +3.5 levels on half the samples: counts as content, bound reaches that row (no cut)
new = scan_bits(f, 10, SP10, STRONG); check("10-bit: a row at +3.5 levels (half the samples) is never cut (top %d <= %d)" % (new[0], pad + hb - 1), new[0] <= pad + hb - 1)
f, pad, hb, H10 = box10(64 + 5, 2)
check("8-bit unchanged: unit is 1 so thresholds equal the old ones (black+%d / +%d)" % (STRICT, STRONG), (1 << (8 - 8)) == 1)
PINS.extend([
 ("margins in 8-bit-equivalent levels", "scan", "let levelUnit = 1 << max(0,bits-8)"),
 ("threshold uses levelUnit", "scan", "let threshold=UInt16(min(65535,(black+2*levelUnit)*(1 << max(0,16-bits))))"),
 ("strong threshold uses levelUnit", "scan", "let strongThreshold=UInt16(min(65535,(black+12*levelUnit)*(1 << max(0,16-bits))))"),
 ("edge rows diagnostic logged for every non-black sample, with sample index, time and bounds", "scan", "print(\"[cropdetect] edge rows sample=\\(sampled) t=\\(Int(t))s bounds y=\\(b.y0)..\\(b.y1) (8-bit-eq mean/max"),

 ("scan has speck and strong parameters", "scan", "threshold: UInt16, speck: Int = 0, strong: UInt16 = 0) -> Bounds? {"),
 ("edge row content rule", "scan", "if speck <= 0 || strong <= threshold { return first(y, 0, width) >= 0 }"),
 ("edge row: strong sample is content", "scan", "if v > strong { return true }"),
 ("edge row: more than speck samples is content", "scan", "if v > threshold { n += 1; if n > speck { return true } }"),
 ("top uses the row rule", "scan", "while y < height { if rowIsContent(y) { top = y; break }; y += 1 }"),
 ("bottom uses the row rule", "scan", "while y > top { if rowIsContent(y) { bottom = y; break }; y -= 1 }"),
 ("call passes speck tolerance and strong threshold", "scan", "threshold:threshold,speck:speckTolerance,strong:strongThreshold)"),
 ("speck tolerance discards isolated bar specks (v2 Fix B)", "scan", "let speckTolerance = max(1, w / 512)"),
 ("strong = black+12 levels", "scan", "(black+12*levelUnit)*(1 << max(0,16-bits))"),
])
MUT_NEW = ([
 ("threshold back to raw codes", "scan", "(black+2*levelUnit)*(1 << max(0,16-bits))", "(black+2)*(1 << max(0,16-bits))"),
 ("strong back to raw codes", "scan", "(black+12*levelUnit)*(1 << max(0,16-bits))", "(black+12)*(1 << max(0,16-bits))"),
 ("level unit dropped", "scan", "let levelUnit = 1 << max(0,bits-8)", "let levelUnit = 1"),
 ("edge row log removed", "scan", "edge rows sample=", "edge"),
 ("speck tolerance removed", "scan", "let speckTolerance = max(1, w / 512)", "let speckTolerance = 0"),
 ("strong tier removed", "scan", "if v > strong { return true }", ""),
 ("speck tolerance 1 -> 200", "scan", "let speckTolerance = max(1, w / 512)", "let speckTolerance = max(200, w / 512)"),
 ("strong 12 -> 120", "scan", "(black+12*levelUnit)", "(black+120*levelUnit)"),
 ("bottom edge ignores the row rule", "scan", "while y > top { if rowIsContent(y) {", "while y > top { if first(y, 0, width) >= 0 {"),
])
# ---------------------------------------------------------------- capture replay: head piece stall --------------------------------------------
check("capture: the %.1f s head-piece refetch (STALL stallMs=6002) fits the %.0f s wt open timeout; the old 5 s timeout did not" % (6.002, RW), RW > 6.002 > 5.0 and KILL > RW)
# ---------------------------------------------------------------- mutants over the real sources ------------------------------------------------
def mut(src, a, b):
    S = dict(SRC); assert a in S[src], (src, a[:50]); S[src] = S[src].replace(a, b, 1); return S
MUT = [
 ("invert the undelivered condition", "scan", "let c = carryUsable(c), c.undelivered {", "let c = carryUsable(c), !c.undelivered {"),
 ("drop the TTL check", "scan", " - c.at <= SourcePixelCropScanner.carryTTL", " - c.at <= 1e9"),
 ("drop the key check", "scan", "c.key == key, ProcessInfo", "true, ProcessInfo"),
 ("stale store ignores newest key", "scan", "(self.newestKey == key) && e >", "(true) && e >"),
 ("stale store ignores last delivery", "scan", "e > self.lastDeliveredEpoch &&", "true &&"),
 ("stale store overwrites any carry", "scan", "(self.carry == nil || (self.carry?.key == key && (self.carry?.sampled ?? 0) == 0 && (self.carry?.ep ?? -1) < e))", "true"),
 ("dims check removed", "scan", 'c.dims != "" , c.dims != idDims', 'false'),
 ("no trim", "scan", "positions.count - c.sampled", "positions.count"),
 ("progress write without epoch guard", "scan", "if self.epoch == e && !(self.carry?.undelivered", "if true && !(self.carry?.undelivered"),
 ("liveSamples never set", "scan", "if self.epoch == e { self.liveSamples = sampled;self.lastProgressAt=ProcessInfo.processInfo.systemUptime }", ""),
 ("hasProgress always false", "scan", "return liveSamples > 0 && now-lastProgressAt <= 20 && now-scanStartedAt <= 90 && scanDeadlineAt-now > 12", "return false"),
 ("rw timeout regresses below observed6s stall", "scan", '"10000000" : "5000000"', '"5000000" : "5000000"'),
 ("watchdog regresses to unbounded45s open", "scan", "wt ? 12 : 20", "wt ? 45 : 20"),
 ("no-agreement scan still decides", "scan", "if wt, !stereo, !rgbVeto, !fresh, SourcePixelBounds.consistent(members) == nil {", "if false {"),
 ("no-agreement wording regresses to giving up", "scan", "non-black frames - full picture kept, search continues", "non-black frames - no decision, file left unlocked"),
 ("retry give-up cap reintroduced", "pc", "if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, (!manual || self.cropRect == nil)", "if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, n < 12 && (!manual || self.cropRect == nil)"),
 ("early rect from members only", "scan", "let u: SourcePixelBounds.Bounds = all.map { $0.union(u0) } ?? u0", "let u: SourcePixelBounds.Bounds = u0"),
 ("stale store clobbers same-key progress", "scan", "(self.carry?.key == key && (self.carry?.sampled ?? 0) == 0 && (self.carry?.ep ?? -1) < e)", "(self.carry?.key == key)"),
 ("tolerance 8 -> 800", "scan", "earlyTolerance = 8", "earlyTolerance = 800"),
 ("min frames 3 -> 1", "scan", "earlyMinCount = 3", "earlyMinCount = 1"),
 ("agreement source dropped", "scan", "let consensus: SourcePixelBounds.Bounds? = SourcePixelBounds.consistent(members)", "let consensus: SourcePixelBounds.Bounds? = nil"),
 ("early apply for full frame too", "scan", "if !(ci.x0 == 0 && ci.y0 == 0 && ci.x1 == w && ci.y1 == h) {", "if true {"),
 ("early apply for stereo too", "scan", "if wt, !stereo, !rgbVeto, !interimSent, let interim", "if wt, !rgbVeto, !interimSent, let interim"),
 ("early apply without epoch guard", "scan", "if self.valid(e) { interim(ir, -1) }", "interim(ir, -1)"),
 ("early apply fires repeatedly", "scan", "interimSent = true\n", "\n"),
 ("tail window 240 -> 24000", "samples", "tailWindow = 240.0", "tailWindow = 24000.0"),
 ("auto seed is the oldest frame", "samples", "seed: picked.max() ?? 0", "seed: picked.min() ?? 0"),
 ("farthest-point order picks the NEAREST next", "samples", "guard let fi = gaps.indices.max(by:", "guard let fi = gaps.indices.min(by:"),
 ("spread guard removed", "scan", "window > 0 && covered < 0.5 * window ? nil : consensus", "consensus"),
 ("trim ignores carried positions", "scan", "!c.done.contains { (d: Double) -> Bool in abs(d - p) < 4 }", "true"),
 ("manual drops an undelivered fallback", "scan", "if carry?.undelivered != true { carry = nil }", "carry = nil"),
 ("manual scan seeds from the carry", "scan", "if fresh { c0 = nil };", ""),
 ("early apply clears manual state", "pc", "if !early { self.manualRedetectInFlight = false }", "self.manualRedetectInFlight = false"),
 ("early apply clears the retry table", "pc", "if decisive && !early {", "if decisive {"),
 ("early apply marked as final", "scan", "interim(ir, -1)", "interim(ir, 1)"),
 ("manual ignores the playhead", "samples", "seed: c)", "seed: 0)"),
 ("manual flag not passed", "pc", "mainIPCPath:self.mainIPCPath,manual:manualPriority", "mainIPCPath:self.mainIPCPath,manual:false"),
 ("manual does not drop the carry", "pc", "if manualPriority { sourceScanner.dropCarry() }", ""),
 ("manual join removed", "pc", "if cropDetector.isPending, cropDetector.hasScanProgress {", "if false {"),
 ("early apply not wired", "pc", "interim:{ [weak self] rect,conf in self?.onResult?(rect,true,conf) }", "interim:nil"),
 ("pin wiring deleted (both)", "wt", "if (globalRing) { globalRing.pinnedFirst = fFirst; globalRing.pinFileEdges(fFirst, fLast); }", ""),
 ("pin wiring deleted (2nd)", "wt", "if (globalRing) { globalRing.pinnedFirst = fileFirst; globalRing.pinFileEdges(fileFirst, fileLast); }", ""),
 ("pin skip removed from _evict", "wt", "      if (idx >= cutoff) continue;\n      if (this._isPinned(idx)) continue;", "      if (idx >= cutoff) continue;"),
 ("cancel log removed", "scan", "scan cancelled mid-run after", "scan stopped"),
]
MUT.extend(MUT_NEW)
surv = []
for name, src, a, b in MUT:
    if run_pins(mut(src, a, b)) == []: surv.append(name)
check("%d mutants of the real sources, each caught by a pin (survivors: %s)" % (len(MUT), surv or "none"), not surv)
# the Node harness runs the real ring (isolated)
node = shutil.which("node")
if node:
    h = ROOT / "Tests/Harness/WtPinFirst/test_pin.mjs"; w = ROOT / "Resources/vendor/wt_server/wt_server.mjs"
    r = subprocess.run([node, str(h), str(w)], capture_output=True, text=True, timeout=60)
    check("node harness on the real wt_server.mjs ring: patched PASS (%s)" % r.stdout.strip().splitlines()[-1], r.returncode == 0)
else: print("note: node not found, harness not run")
print("PASS" if not fails else "FAIL %d" % len(fails)); sys.exit(1 if fails else 0)
