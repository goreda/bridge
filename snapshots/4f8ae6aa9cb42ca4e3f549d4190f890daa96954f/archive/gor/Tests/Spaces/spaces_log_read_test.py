#!/usr/bin/env python3
"""Tests for Tests/Spaces/spaces_log_read.py: synthetic [spaces] logs for every verdict code, plus pins that the Swift writer
(OverlaySpaceGate.swift) still emits the exact line shapes the reader parses. Linux text model; nothing runs on a Mac."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
import pathlib, sys
here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here))
import spaces_log_read as R
SW = _plat_read(here.parents[1] / "Sources/gor/GorPlatformMac/OverlaySpaceGate.swift")
fails = 0
def check(n, ok):
    global fails; print(("ok   " if ok else "FAIL ") + n); fails += 0 if ok else 1
def L(t, m): return "%s [spaces] %s" % (t, m)
ENV = L("10:00:00.100", "env macOS=Version_15.8.2_(Build_24G325) sym_main=1 sym_copy=1 sym_active=1 sym_move=1 pid=4242 overlayWin=77 behavior=272 level=4")
def codes(*lines): return [c for c, _ in R.diagnose("\n".join(lines))]
check("no [spaces] line -> NO_LOG", codes("12:00:00.000 [diag] something") == ["NO_LOG"])
check("missing symbol -> SYM_MISSING", "SYM_MISSING" in codes(L("10:00:00.100", ENV.split("] ")[1].replace("sym_move=1", "sym_move=0"))))
check("mpvWin=none -> NO_MPV_WIN", "NO_MPV_WIN" in codes(ENV, L("10:00:01.000", "spaces mpvWin=none pid=4242")))
check("NOT done -> MOVE_UNAVAILABLE", "MOVE_UNAVAILABLE" in codes(ENV, L("10:00:02.000", "move overlay 77 to space 5 NOT done: CGSMoveWindowsToManagedSpace or CGSMainConnectionID unavailable")))
check("moved ... ok=false -> MOVE_INEFFECTIVE", "MOVE_INEFFECTIVE" in codes(ENV, L("10:00:02.000", "moved overlay 77 from [3] to mpv space 5 now=[3] ok=false")))
check("STUCK line -> STUCK", "STUCK" in codes(ENV, L("10:00:05.000", "STUCK mpv=[5] overlay=[3] active=5 alpha=1.0 visible=true onActive=false for=1.6s")))
check("converged after 2.40 s -> SLOW; 0.30 s -> OK", "SLOW" in codes(ENV, L("10:00:05.000", "converged after 2.40s mpv=[5] overlay=[5]")) and codes(ENV, L("10:00:05.000", "converged after 0.30s mpv=[5] overlay=[5]")) == ["OK"])
check("6 moves in 10 s -> FLAP; 5 moves -> not FLAP", "FLAP" in codes(ENV, *[L("10:00:%02d.000" % (10 + i), "moved overlay 77 from [3] to mpv space 5 now=[5] ok=true") for i in range(6)]) and "FLAP" not in codes(ENV, *[L("10:00:%02d.000" % (10 + i), "moved overlay 77 from [3] to mpv space 5 now=[5] ok=true") for i in range(5)]))
check("gate hide while mpv's Space is the active one -> HIDDEN_WHILE_MPV_HERE", "HIDDEN_WHILE_MPV_HERE" in codes(ENV, L("10:00:09.000", "gate hide onScreen=false active=5 overlay=[5] mpv=[3, 5]")) and "HIDDEN_WHILE_MPV_HERE" not in codes(ENV, L("10:00:09.000", "gate hide onScreen=false active=2 overlay=[5] mpv=[5]")))
check("clean follow -> OK", codes(ENV, L("10:00:03.000", "spaces mpvWin=9 mpv=[5] overlay=[3] active=5"), L("10:00:03.200", "moved overlay 77 from [3] to mpv space 5 now=[5] ok=true"), L("10:00:03.210", "converged after 0.21s mpv=[5] overlay=[5]")) == ["OK"])
check("a capture with no Space change says so instead of OK", codes(ENV, L("10:00:03.000", "spaces mpvWin=9 mpv=[3] overlay=[3] active=3")) == ["NO_SPACE_CHANGE_SEEN"])
# Writer pins: the format strings the reader depends on are present in the Swift source.
check("diverge ended without converging is NOT a follow -> NOT_CONVERGED", codes(ENV, L("10:00:05.000", "diverge ended NOT converged after 1.20s mpv=[5] overlay=[3] active=2")) == ["NOT_CONVERGED"])
check("...but a later real converged still gives OK", codes(ENV, L("10:00:05.000", "diverge ended NOT converged after 1.20s mpv=[5] overlay=[3] active=2"), L("10:00:09.000", "converged after 0.30s mpv=[5] overlay=[5]")) == ["OK"])
check("Swift: converged is logged only when sameSpace, else a distinct NOT converged line", 'if sameSpace { Self.log("converged after' in SW and 'Self.log("diverge ended NOT converged after' in SW)
for name, needle in [("env line", 'Self.log("env macOS='), ("symbol report", "sym_main=") , ("mpvWin=none", 'spaces mpvWin=none pid='), ("STUCK line", 'Self.log("STUCK mpv='), ("converged line", 'Self.log("converged after '), ("moved line with now= ok=", 'now=\\(after) ok=\\(after.contains(target))'), ("NOT done line", "NOT done: CGSMoveWindowsToManagedSpace"), ("gate line", 'Self.log("gate \\(d) onScreen=')]:
    check("Swift writes the %s the reader parses" % name, needle in SW)
check("STUCK threshold is 1.5 s and SLOW threshold in the reader is 1.0 s (reader flags what the writer calls late)", "now - t0 > 1.5" in SW and "float(c[1]) > 1.0" in open(here / "spaces_log_read.py").read())
check("writer logs only state changes (STUCK once per episode, env once)", "!stuckLogged" in SW and "!envLogged" in SW and SW.count('Self.log("env ') == 1)
check("no behavior change: the move/order-front calls are still the same two", SW.count("Self.moveWindow(mine, to: target)") == 1 and SW.count("win.collectionBehavior.insert(.moveToActiveSpace)") == 1)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
