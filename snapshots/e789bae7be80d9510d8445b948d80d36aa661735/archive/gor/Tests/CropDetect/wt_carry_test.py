#!/usr/bin/env python3
"""Owner capture 2026-11-08 09:43-09:44 (build a669c613f), magnet crop detect: the scan DID measure bars ("scan done: sampled=7/12
bounds=0,252-3840,1892 override=true", decisive) but no crop was applied; 5 s later "indecisive result". WT log: from 09:44:04 every
open of byte 0 got no data in 5.15 s (WT_DIAG http-latency ids 72,74-77,79 firstWriteMs=null totalMs~5149; STALL piece=0 stallMs=6002),
so 5 of 12 samples failed and the next scan's metadata probe (id 79, 09:44:32.17-09:44:37.32) failed too. The manual Detect menu item
(reDetectCrop: cancel + detect, no "dimensions ready" line) was the only caller that restarts a scan silently; a cancel landing while the
scan finished made valid(e) false and dropped the decisive rect.
Fix under test: (1) wt scans open with -rw_timeout 30 s and kill after 45 s (was 5 / 20), (2) samples already measured on a stream survive a
cancel (carry), (3) a decisive rect dropped by a cancel is kept and delivered by the next scan of the same file, even if that scan fails,
(4) every finish(nil,false) names its reason and each scan logs its start. Linux model of the carry state machine + text pins on the Swift;
Swift compiled on CI only, not run on a Mac."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
SP = (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
fails = 0
def check(n, ok):
    global fails; print(("ok   " if ok else "FAIL ") + n); fails += 0 if ok else 1
# ---- capture facts (excerpt of the owner's logs) ----
CAP = """[cropdetect] wt samples: ranges=[0-78] positions=12
[cropdetect] scan done: sampled=7/12 bounds=0,252-3840,1892 of 3840x2160 override=true
[cropdetect] indecisive result — crop state unchanged"""
WT = [(72, 5149), (74, 5148), (75, 5149), (76, 5149), (77, 5148), (79, 5150)]   # opens with no first byte (ids), totalMs
STALL_MS = 6002
m = re.search(r"sampled=(\d+)/(\d+) bounds=(\d+),(\d+)-(\d+),(\d+) of (\d+)x(\d+)", CAP)
check("capture: decisive-sized scan (7 of 12, >= min(3,12)) with letterbox bounds 0,252-3840,1892 was NOT applied", int(m[1]) >= min(3, int(m[2])) and (int(m[4]), int(m[6])) == (252, 1892) and "indecisive" in CAP)
check("capture: every failed open waited ~5.15 s, the old rw_timeout was 5 s and the head stall was %d ms" % STALL_MS, all(5.0 * 1000 < t < 5300 for _, t in WT) and STALL_MS > 5000)
to = re.search(r'let rwTimeout: String = wt \? "(\d+)" : "(\d+)"', SP)
check("wt open timeout10s exceeds the observed6s head stall, non-wt unchanged5s", to and int(to[1]) == 10_000_000 and int(to[2]) == 5_000_000 and int(to[1]) / 1000 > STALL_MS)
ka = re.search(r"let killAfter: Double = wt \? (\d+) : (\d+)", SP)
check("wt watchdog12s bounds10s open, non-wt20s unchanged", ka and int(ka[1]) == 12 and int(ka[2]) == 20 and int(ka[1]) > int(to[1])/1e6)
check("no hard-coded 5000000 timeout is left in the ffmpeg/ffprobe argument lists", SP.count('"-rw_timeout","5000000"') == 0 and SP.count('"-rw_timeout",rwTimeout') == 5)
check("all five opens (probe, metadata, sample, two bounded batch paths) pass killAfter and clamp to remaining scan budget", SP.count("killAfter:killAfter)") == 5 and "killAfter: Double = 20" in SP and "killAfter:min(killAfter,remaining)" in SP)
# ---- model of the carry state machine ----
class Scanner:
    def __init__(s): s.epoch = 0; s.carry = None
    def cancel(s): s.epoch += 1
    def start(s, path, wt=True, stereo=False):
        s.cancel(); e = s.epoch
        c0 = s.carry if (wt and s.carry and s.carry["path"] == path and s.carry["stereo"] == stereo) else None
        if wt and c0 is None: s.carry = None
        return {"e": e, "path": path, "wt": wt, "stereo": stereo, "c0": c0}
    def replay(s, sc):  # scan start: undelivered result is replayed before any network
        c0 = sc["c0"]
        if c0 and c0["undelivered"]: return s.finish(sc, c0["rect"], True)
    def sample(s, sc, bounds, sampled_total):
        if sc["wt"] and not sc["stereo"] and s.epoch == sc["e"]:
            s.carry = {"path": sc["path"], "stereo": sc["stereo"], "bounds": bounds, "sampled": sampled_total, "undelivered": False, "rect": None}
    def finish(s, sc, rect, decisive):   # main-thread block; returns delivered (rect, decisive) or None
        if s.epoch == sc["e"]:
            c = s.carry
            if decisive: s.carry = None
            if (not decisive) and sc["wt"] and c and c["path"] == sc["path"] and c["stereo"] == sc["stereo"] and c["undelivered"]:
                s.carry = None; return (c["rect"], True)
            return (rect, decisive)
        if decisive and sc["wt"] and not sc["stereo"]:
            s.carry = {"path": sc["path"], "stereo": sc["stereo"], "bounds": None, "sampled": 0, "undelivered": True, "rect": rect}
        return None
RECT = (0, 252, 3840, 1892)
# 1: the owner's sequence. B decisive, cancelled by a second click before delivery; C starts and replays.
S = Scanner(); B = S.start("con-air"); S.cancel(); check("B's decisive result is dropped by the cancel (as in the capture)", S.finish(B, RECT, True) is None and S.carry["undelivered"])
C = S.start("con-air"); out = S.replay(C); check("next scan of the file returns the measured rect at once (no probe, no ffmpeg)", out == (RECT, True) and S.carry is None)
# 2: C already running when B's dropped result is stored, and C then fails its probe: C's indecisive finish delivers B's rect
S = Scanner(); B = S.start("f"); C = S.start("f"); S.finish(B, RECT, True)   # B finishes after C started (epoch moved): stored
check("C's failed probe (finish nil,false) delivers the rect kept from B instead of 'indecisive'", S.finish(C, None, False) == (RECT, True) and S.carry is None)
# 3: partial progress is kept: 2 samples (< 3) then a restart adds 1 -> total 3
S = Scanner(); A = S.start("f"); S.sample(A, (0, 250, 3840, 1890), 1); S.sample(A, (0, 252, 3840, 1892), 2); r1 = S.finish(A, None, False)
A2 = S.start("f"); carried = A2["c0"]["sampled"]; check("an interrupted scan's samples are carried into the next scan of the same file (carried=%d)" % carried, carried == 2 and r1 == (None, False))
# 4: another file or stereo scan starts clean
S = Scanner(); A = S.start("f"); S.sample(A, RECT, 5); check("a different file starts with no carry", S.start("g")["c0"] is None and S.carry is None)
S = Scanner(); A = S.start("f"); S.sample(A, RECT, 5); check("stereo scans carry nothing (eye halves are not stored)", S.start("f", stereo=True)["c0"] is None)
# 5: a delivered decisive result clears the carry (an explicit re-detect re-measures)
S = Scanner(); A = S.start("f"); S.sample(A, RECT, 5); S.finish(A, RECT, True)
check("delivered decisive result clears the carry", S.carry is None and S.start("f")["c0"] is None)
# 6: a stale scan thread never overwrites a newer scan's carry
S = Scanner(); A = S.start("f"); B = S.start("f"); S.sample(B, RECT, 4); S.sample(A, (0, 0, 1, 1), 99)
check("an old scan thread cannot overwrite the newer scan's progress", S.carry["sampled"] == 4)
# 7: non-wt scans never use the carry or store a dropped result
S = Scanner(); N = S.start("f", wt=False); S.cancel(); S.finish(N, RECT, True)
check("non-stream scans keep no state", S.carry is None)
# ---- text pins that tie the model to the Swift ----
check("Swift: dropped decisive wt result is stored as undelivered", "undelivered: true, rect: rect" in SP and "else if decisive, wt, !stereo" in SP)
check("Swift: an indecisive finish delivers the stored rect (same file, same flags)", "c.undelivered" in SP and "delivering the decisive rect measured earlier" in SP)
check("Swift: replay now happens after a fresh probe confirms the stream geometry (design change in af8a15d3, see wt_pipeline_test)", SP.index("replaying the decisive rect measured earlier") > SP.index("idDims = "))
check("Swift: per-sample progress is stored only for the current epoch, wt, non-stereo", "if wt, !stereo { self.lock.lock(); if self.epoch == e && !(self.carry?.undelivered == true && self.carry?.key == key) { self.carry = Carry(" in SP)
check("Swift: carried bounds and count seed the next scan", "var all: SourcePixelBounds.Bounds? = c0?.bounds; var sampled: Int = c0?.sampled ?? 0" in SP)
check("Swift: a delivered decisive result clears the carry", "if decisive { self.carry = nil; self.lastDeliveredEpoch = e }" in SP)
check("Swift: scan start is logged and every finish(nil,false) carries a reason", "[cropdetect] scan start caller=" in SP and not re.search(r"finish\(nil,\s*false\s*\)", SP) and "finished indecisive:" in SP)
reasons = re.findall(r'finish\(nil,false,"([^"]+)"', SP)
check("Swift: %d distinct failure reasons are named" % len(set(reasons)), len(set(reasons)) >= 6)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
