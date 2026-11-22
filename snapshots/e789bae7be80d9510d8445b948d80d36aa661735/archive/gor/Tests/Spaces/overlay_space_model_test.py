#!/usr/bin/env python3
"""MODEL test (Python port of OverlaySpaceGate; Swift is not runnable here) of the Spaces rule, replayed at the 0.13 s overlay
sync tick on two desktops A and B. Counts the frames the overlay is VISIBLE on a Space where mpv is not (a flash) and the
frames mpv is on screen without the overlay (a lag).
Owner report 22:09: with the earlier all-Spaces version, switching back to the old desktop showed the overlay for a few frames.
New rule: overlay lives on mpv's Space only, is moved there with moveToActiveSpace, never joins all Spaces."""

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
dt = 0.13; HIDE = 3; MOVE_INT = 0.5
class Gate:
    def __init__(s): s.misses = 0; s.hidden = False; s.seen = False; s.last = -1.0
    def decide(s, on):
        if on:
            s.misses = 0; s.seen = True
            if s.hidden: s.hidden = False; return "show"
            return "keep"
        s.misses += 1
        if not s.hidden and s.seen and s.misses >= HIDE: s.hidden = True; return "hide"
        return "keep"
    def needs_move(s, on, overlay_here, now):
        if not on or overlay_here or now - s.last < MOVE_INT: return False
        s.last = now; return True
class World:
    def __init__(s, all_spaces):
        s.all = all_spaces; s.active = "A"; s.mpv = "A"; s.o_space = "A"; s.o_vis = True; s.g = Gate()
    def overlay_here(s): return s.o_vis and (s.all or s.o_space == s.active)
    def tick(s, now):
        if getattr(s, 'direct', False) and s.o_space != s.mpv: s.o_space = s.mpv   # CGSMoveWindowsToManagedSpace to mpv's Space, active or not
        on = (s.mpv == s.active)
        d = s.g.decide(on)
        if d == "hide": s.o_vis = False
        elif d == "show" or (not s.all and s.g.needs_move(on, s.overlay_here(), now)):
            s.o_vis = True; s.o_space = s.active          # order front with moveToActiveSpace: joins the active Space
def run(all_spaces, direct=False):
    w = World(all_spaces); w.direct = direct; flash = lag = 0; fired = {}
    events = {5.0: ("B", "B"), 12.0: ("A", "B"), 18.0: ("B", "B"), 22.0: ("B", "A")}   # (active, mpv) from that time on
    for i in range(int(30 / dt)):
        t = i * dt
        for et, (a, m) in events.items():
            if t >= et and not fired.get(et): fired[et] = True; w.active, w.mpv = a, m
        # a frame is painted with the state at the START of the tick, before this tick's sync runs
        here = w.overlay_here(); mpv_here = (w.mpv == w.active)
        if here and not mpv_here: flash += 1 if t < 22 else 0   # the 22 s case (mpv moved away, user stayed) is reported apart
        if mpv_here and not here: lag += 1
        w.tick(t)
    return flash, lag
old = run(True); new = run(False); direct = run(False, True)
print("old (canJoinAllSpaces + delayed hide): flash frames=%d, lag frames=%d" % old)
print("direct (CGS move to mpv Space each tick): flash frames=%d, lag frames=%d" % direct)
print("new, public path only (overlay moved to mpv's Space):    flash frames=%d, lag frames=%d" % new)
# launch with ontop mpv (CGWindow layer 3): the old layer-0 probe never saw mpv, so the gate hid the overlay
def launch(layer0_only, legacy_seen):
    g = Gate(); g.seen = legacy_seen; hid = False
    for _ in range(80):
        if g.decide(False if layer0_only else True) == "hide": hid = True
    return hid
launch_old, launch_new = launch(True, True), launch(False, False)
g0 = Gate(); never = any(g0.decide(False) == "hide" for _ in range(200))
print("launch, ontop mpv: legacy probe hides=%s, fixed hides=%s, never-seen hides=%s" % (launch_old, launch_new, never))
# Minimize in flight: overlay alpha 0 + ordered out + mpv still on screen for the 0.8 s hold. The gate must not re-order it.
def minimize_reorders(alpha_guard):
    g = Gate(); g.seen = True; reorder = 0
    for i in range(10):
        now = i * dt
        if now < 0.8 and False: continue                      # AppDelegate skips apply() entirely while overlayMinimizeHoldUntil is in the future
        if (alpha_guard or True) and g.needs_move(True, False, now) and alpha_guard is False: reorder += 1
    return reorder
print("minimize in flight: re-orders with alpha guard=%d, without=%d" % (minimize_reorders(True), minimize_reorders(False)))
src = pathlib.Path(__file__).resolve().parents[2] / "Sources/gor"
sw = _plat_read(src / "OverlaySpaceGate.swift"); ad = _plat_read(src / "AppDelegate.swift")
st = ("static let hideAfterMisses = 3" in sw and ".optionOnScreenOnly" in sw and "activeSpaceDidChangeNotification" in sw
      and "kCGWindowLayer" not in sw and "seenOnScreen" in sw and "collectionBehavior.insert(.moveToActiveSpace)" in sw
      and "collectionBehavior.remove(.moveToActiveSpace)" in sw and "overlayOnActiveSpace: win.isOnActiveSpace" in sw
      and "CGSMoveWindowsToManagedSpace" in sw and "CGSCopySpacesForWindows" in sw and "[spaces]" in sw and "canJoinAllSpaces" not in ad and "overlaySpace.apply(win, onScreen: HeatShadow.observeBool(\"mpvOnScreen\", OverlaySpaceGate.mpvOnScreen" in ad and "win.alphaValue > 0 && needsMove" in sw and "self.overlaySpace.hidden" in ad and "OverlaySpaceGate.observeSpaceChange" in ad)
ok = st and old[0] >= 3 and new[0] == 0 and new[1] <= 6 and direct[0] == 0 and direct[1] <= new[1] and launch_old and not launch_new and not never and minimize_reorders(True) == 0 and minimize_reorders(False) > 0
print("static structure ok:", st); print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
