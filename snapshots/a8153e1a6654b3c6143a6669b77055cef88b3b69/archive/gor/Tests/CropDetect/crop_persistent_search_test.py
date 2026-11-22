#!/usr/bin/env python3
"""199az persistent crop search: a crop is searched until found; a crop that gives up is unacceptable.

The wt no-agreement outcome keeps the full picture (the frame is sacred; only letterbox/pillarbox are
removed) and the player re-scans +2s, +5s, +10s, then every 30s while playing, with no give-up count.
Seek, resolution/aspect change, track switch and cache growth past the scanned range restart the search
at once with a fresh cadence. Automatic application still needs consistent() agreement, re-rect stays
widen-only, auto never overrides a manual crop (CropInvariant), and only rows/cols at the black
threshold are ever removed. Static anchors against Sources/gor/Player/PPController.swift and
Sources/gor/Stereo/Source.swift; behaviour checks are Python mirrors."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
PP = (ROOT / 'Sources/gor/Player/PPController.swift').read_text()
SRC = (ROOT / 'Sources/gor/Stereo/Source.swift').read_text()
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails.append(name)

# -- static: the schedule ---------------------------------------------------------------------------------------------
check("retry cadence is +2s, +5s, +10s, then every 30s",
      "static func wtCropRetryDelay(attempt n: Int) -> Double { n <= 1 ? 2 : n == 2 ? 5 : n == 3 ? 10 : 30 }" in PP)
check("no give-up count on the automatic search (searched until found)",
      "n < 12" not in PP)
check("the 30s cadence runs only while playing",
      'if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, (!manual || self.cropRect == nil)' in PP)
check("each schedule records the scanned range end for the buffer-growth trigger",
      "self.wtCropRetry[self.currentFilePath] = (n + 1, ProcessInfo.processInfo.systemUptime, self.lastSeekableEnd)" in PP)
check("thermal defer re-arms on the cadence, never drops the search",
      'retry deferred: thermal pressure"); DispatchQueue.main.asyncAfter(deadline: .now() + 30)' in PP)

# -- static: immediate restarts -----------------------------------------------------------------------------------------
check("restart helper guards: search armed for retry or scan in flight, no crop yet, no manual ownership",
      "wtCropRetry[currentFilePath] != nil || cropDetector.isPending, cropRect == nil," in PP
      and "!menuCropOwnsSelection else { return }" in PP)
check("cache growth past the scanned range restarts the search",
      'end > pending.scannedEnd + 2' in PP and 'restartPendingWTCropSearch("buffer-growth")' in PP)
check("seek resets the search cadence",
      'print("[cropdetect] seek - crop search restarts with a fresh cadence")' in PP)
check("resolution/aspect change re-measures with a search pending, not only with a crop applied",
      "cropRect != nil || wtCropRetry[currentFilePath] != nil {" in PP)

# -- static: the sacred guards stay -------------------------------------------------------------------------------------
check("no-agreement keeps the full picture and says the search continues",
      'full picture kept, search continues' in SRC)
check("the no-agreement finish line is byte-pinned by gate test 1 and unchanged",
      'finish(nil,false,"no agreement among \\(members.count) non-black frames");return' in SRC)
check("automatic apply still needs consistent() agreement",
      "SourcePixelBounds.consistent(members) == nil" in SRC)
check("re-rect stays widen-only with manual unchanged (199al/199ai.1 kept)",
      "let widensAppliedCrop = rect.minX <= current.minX" in PP
      and "guard CropInvariant.mayChange(manual: manual) || widensAppliedCrop" in PP)
check("black-threshold floor machinery untouched (+2 / +12 level rule present)",
      "let threshold=UInt16(min(65535,(black+2*levelUnit)*(1 << max(0,16-bits))))" in SRC
      and "let strongThreshold=UInt16(min(65535,(black+12*levelUnit)*(1 << max(0,16-bits))))" in SRC)

# -- (a) mirror: a no-agreement source is still being searched after 60s simulated ---------------------------------------
def delay(n): return 2 if n <= 1 else 5 if n == 2 else 10 if n == 3 else 30
fires = []
t = 0.0; n = 0
while True:
    d = delay(n + 1)
    if t + d > 60: break
    t += d; n += 1; fires.append(t)
check("(a) retries fire at +2,+5,+10,+30... cumulative 2,7,17,47 within 60s", fires == [2, 7, 17, 47])
check("(a) at t=60s a further retry is still pending (no give-up)", n >= 4 and t + delay(n + 1) > 60)

# -- (b) mirror: late bars after a seek are detected ---------------------------------------------------------------------
TOL = 8; MINC = 3
def union(a, b): return (min(a[0],b[0]), min(a[1],b[1]), max(a[2],b[2]), max(a[3],b[3]))
def consistent(members, tol=TOL, minc=MINC):
    if len(members) < minc: return None
    u = members[0]
    for m in members[1:]: u = union(u, m)
    for m in members:
        if abs(m[0]-u[0]) > tol or abs(m[1]-u[1]) > tol or abs(m[2]-u[2]) > tol or abs(m[3]-u[3]) > tol: return None
    return u
pre_seek = [(0, 0, 3840, 2160), (0, 0, 3838, 2162)]            # dark opening: no bars measurable
check("(b) before the seek there is no agreement (search stays open)", consistent(pre_seek) is None)
post_seek = [(0, 278, 3840, 1842), (0, 280, 3840, 1840), (0, 276, 3840, 1844)]  # seek lands on barred scene
u = consistent(post_seek)
check("(b) after the seek the late bars agree and apply", u == (0, 276, 3840, 1844))

# -- (c) mirror: a picture-content edge is never cropped ------------------------------------------------------------------
BLACK, LEVEL = 16, 1          # 8-bit-equivalent luma
THRESH, STRONG = BLACK + 2*LEVEL, BLACK + 12*LEVEL
def row_is_content(pixels, speck):
    if any(p >= STRONG for p in pixels): return True
    return sum(1 for p in pixels if p > THRESH) > max(speck, 0)
W = 1920; speck = max(1, W // 512)
bar_row = [BLACK + 1] * W                       # near-black letterbox bar
noise_bar = [BLACK + 1] * W; noise_bar[7] = BLACK + 2   # one speck pixel inside a bar
edge_row = [BLACK + 3] * W                      # dim picture edge: every pixel above the floor
bright_edge = [60] * W                          # normal picture edge
rows = [bar_row, bar_row, noise_bar, edge_row, bright_edge]
first_content = next(i for i, r in enumerate(rows) if row_is_content(r, speck))
check("(c) bar rows incl. single-speck noise stay bar", all(not row_is_content(r, speck) for r in rows[:3]))
check("(c) a dim picture edge row is content (bound lands at the bar/picture step)", first_content == 3)
check("(c) the crop never enters the picture (bound row == first content row)", first_content == 3 and not row_is_content(rows[2], speck))

# -- (d) mirror: a manual crop survives every retry ----------------------------------------------------------------------
def schedules_retry(wt, playing, manual, crop_rect, menu_owns):
    if menu_owns: return False                                   # onResult top guard
    return wt and playing and (not manual or crop_rect is None)  # scheduling guard
check("(d) applied manual crop: no automatic retry is scheduled", not schedules_retry(True, True, True, (0, .1, 1, .8), False))
check("(d) menu-owned selection: result ignored before any scheduling", not schedules_retry(True, True, False, None, True))
check("(d) manual detect with no crop yet may still retry (not enough downloaded)", schedules_retry(True, True, True, None, False))

print("FAILURES: %d" % len(fails))
sys.exit(1 if fails else 0)
