#!/usr/bin/env python3
"""199az delta piece 6: restartPendingWTCropSearch's guard is widened to the p2 seek pattern. The old
guard required a pending retry entry AND no scan in flight, so a track switch during the FIRST scan
(entry still nil) or during a RETRY scan (isPending true) did nothing and the old track's scan kept
running (gdb compiled the verbatim body on Swift 6.0.3: entry=false/isPending=true -> cancel 0/start 0;
entry=true/isPending=true -> cancel 0/start 0). Now the guard is (entry OR isPending) with cropRect and
manual ownership preserved, and the cancel bumps the retry generation so the old scan's delayed
completion dies on its token guard.

The behavior scenarios below are driven by flags PARSED from the real guard in
Sources/gor/Player/PPController.swift, so a mutant of the guard or body turns a scenario red; the mutant
table at the bottom proves each mutation is caught. Mirrors only - no Swift compiler here."""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
PP = (ROOT / 'Sources/gor/Player/PPController.swift').read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)

def helper_of(text):
    return text.split("private func restartPendingWTCropSearch(_ why: String) {", 1)[1].split("\n    }", 1)[0]

def flags(helpText):
    return dict(
        pos="wtCropRetry[currentFilePath] != nil || cropDetector.isPending" in helpText,
        neg="!cropDetector.isPending else" in helpText,
        cropgate="cropRect == nil" in helpText,
        mengate="!menuCropOwnsSelection" in helpText,
        cancel="cropDetector.cancel()" in helpText,
        resetlast="cropDetector.resetLastFile()" in helpText)

H = helper_of(PP); F = flags(H)
check("guard is widened: pending entry OR scan in flight", F["pos"])
check("the old negative isPending guard is gone", not F["neg"])
check("cropRect and manual ownership guards preserved", F["cropgate"] and F["mengate"])
check("the reset kills the old scan (cancel generation) and clears the latch", F["cancel"] and F["resetlast"])
check("buffer-growth call site intact", 'restartPendingWTCropSearch("buffer-growth")' in PP)
check("track-switch call site intact", 'restartPendingWTCropSearch("track-switch")' in PP)

def scenarios(F):
    """Fixture mirror of the helper driven only by the parsed flags."""
    gen = [0]; scans = []; cancels = []
    def restart(entry, pending, crop=False, menu=False):
        if F["cropgate"] and crop: return "untouched(crop)"
        if F["mengate"] and menu: return "untouched(manual)"
        if not (entry or (F["pos"] and pending)): return "no-op"
        if F["neg"] and pending: return "no-op"          # the old guard: in-flight never restarts
        if F["cancel"]: gen[0] += 1; cancels.append(1)
        scans.append("fresh"); return "restarted"
    def old_completion_lands(applied):
        # a delayed completion is applied only if the generation never bumped after its scan started
        applied.append("stale")
    out = []
    # first scan in flight (entry nil, isPending true)
    r = restart(entry=False, pending=True)
    out.append(("first-scan in-flight: track switch cancels and restarts", r == "restarted" and len(cancels) == 1))
    # retry scan in flight (entry set, isPending true)
    r = restart(entry=True, pending=True)
    out.append(("retry-scan in-flight: track switch cancels and restarts", r == "restarted" and len(cancels) == 2))
    # settled crop untouched even with a scan somehow pending
    r = restart(entry=True, pending=True, crop=True)
    out.append(("settled crop untouched", r == "untouched(crop)" and len(cancels) == 2))
    # manual crop ownership untouched
    r = restart(entry=True, pending=True, menu=True)
    out.append(("manual crop ownership untouched", r == "untouched(manual)" and len(cancels) == 2))
    # nothing pending at all: no-op
    r = restart(entry=False, pending=False)
    out.append(("no entry and no scan: no-op", r == "no-op" and len(cancels) == 2))
    # cancel generation: a delayed old-scan completion dies after a restart
    applied = []
    if not F["cancel"]: old_completion_lands(applied)     # without the cancel the stale result lands
    out.append(("cancel generation: the old track's delayed result never lands", applied == []))
    # latch: a decisive result earlier latched lastDetectedFile; only resetLastFile lets the fresh scan run
    last_file = "F"
    if F["resetlast"]: last_file = ""
    out.append(("latch: the restart's fresh scan is not blocked by lastDetectedFile", last_file == ""))
    return out

base = scenarios(F)
for n, ok in base: check("fixture: " + n, ok)

def green(text):
    try: return all(ok for _, ok in scenarios(flags(helper_of(text))))
    except Exception: return False

H_full = H  # helper text inside PP; mutants operate on the full source
mutants = {
    "guard narrowed back to entry-only": ("wtCropRetry[currentFilePath] != nil || cropDetector.isPending, cropRect == nil,", "wtCropRetry[currentFilePath] != nil, cropRect == nil,"),
    "old negative isPending guard restored": ("wtCropRetry[currentFilePath] != nil || cropDetector.isPending, cropRect == nil,\n              !menuCropOwnsSelection else { return }", "wtCropRetry[currentFilePath] != nil, cropRect == nil,\n              !menuCropOwnsSelection, !cropDetector.isPending else { return }"),
    "cropRect guard dropped": (" || cropDetector.isPending, cropRect == nil,", " || cropDetector.isPending,"),
    "manual ownership guard dropped": ("              !menuCropOwnsSelection else { return }", "              true else { return }"),
    "cancel removed (old scan survives)": ("cropDetector.cancel(); cropDetector.resetLastFile()", "cropDetector.resetLastFile()"),
    "resetLastFile removed (latch survives)": ("cropDetector.cancel(); cropDetector.resetLastFile()", "cropDetector.cancel()"),
}
for name, (a, b) in mutants.items():
    assert a in PP, name
    is_red = not green(PP.replace(a, b, 1))
    print(("ok   mutant caught: " if is_red else "FAIL mutant SURVIVED: ") + name)
    if not is_red: fails.append("survivor " + name)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
