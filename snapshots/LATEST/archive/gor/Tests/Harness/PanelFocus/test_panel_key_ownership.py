#!/usr/bin/env python3
"""PanelFocus key-ownership harness.

Ports PanelKeyOwnership (archive/gor/Sources/gor/GorPlatformMac/PanelFocusTraversal.swift) and
replays the Cmd+M search-panel focus scenario against a pre-fix model (the
shipped behavior at 3c48acac) and the fixed model. Source anchors read the
current Swift tree directly, like the Crop harness; no old-source fallback.

PASS means: the ownership rule rejects every automatic player re-key while an
input panel is open, allows the intentional key return on close, and the Swift
sources carry the guarded call sites plus the [panel-focus] diagnostics. It
does NOT exercise AppKit, a real window server, or the owner's Mac build.
"""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
import os
import re
import sys

CELL = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(CELL, "..", "..", "..", "Sources", "gor"))

failures = []


def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f" - {detail}" if detail else ""))
    if not ok:
        failures.append(name)


def read_source(name):
    return _plat_read(_PlatPath(SRC) / name)


# ---------------------------------------------------------------------------
# Port of PanelKeyOwnership (keep semantics token-identical to the Swift).
# ---------------------------------------------------------------------------
class PanelKeyOwnership:
    def __init__(self):
        self.open_panels = []

    def register(self, token):
        if token not in self.open_panels:
            self.open_panels.append(token)

    def unregister(self, token):
        self.open_panels = [t for t in self.open_panels if t != token]

    @property
    def panel_owns_key(self):
        return len(self.open_panels) > 0

    def may_key_player_window(self):
        return not self.panel_owns_key


# ---------------------------------------------------------------------------
# Focus world model. key_holder is "player", "panel" or "mpv" (mpv is a
# separate process: when it holds key, gor's local monitors never run, so
# typing AND esc are dead for gor no matter what).
# ---------------------------------------------------------------------------
class World:
    def __init__(self, fixed):
        self.fixed = fixed
        self.ownership = PanelKeyOwnership()
        self.key_holder = "player"
        self.panel_visible = False
        self.log = []

    # -- events -----------------------------------------------------------
    def open_panel(self, gor_was_active):
        self.panel_visible = True
        self.ownership.register("panel-1")          # GORInputPanel.makeKeyAndOrderFront
        self.key_holder = "panel"                   # panel's own assert
        if not gor_was_active:
            # NSApp.activate in openMagnetSearch/assertKeyAndFocus posts the
            # didActivateApplicationNotification; the o2 beat lands after.
            self.activation_beat_o2()

    def activation_beat_o2(self):
        # AppDelegate o2: gor activated -> overlayWin.makeKeyAndOrderFront
        if self.fixed:
            if self.ownership.may_key_player_window():
                self.key_holder = "player"
            else:
                self.log.append("o2 re-key refused (panel owns key)")
        else:
            self.key_holder = "player"              # unconditional pre-fix steal

    def mpv_activated(self):
        # Click-through at an overlay edge, or mpv raising its own window at
        # stream start: the mpv PROCESS takes key, then o1 re-activates gor.
        self.key_holder = "mpv"
        if self.fixed:
            if self.ownership.may_key_player_window():
                self.key_holder = "player"
            else:
                # gor re-activates; macOS restores the panel (key before the
                # mpv episode) as gor's key window.
                self.key_holder = "panel"
                self.log.append("o1 re-key refused (panel owns key)")
        else:
            self.key_holder = "player"              # o1 re-keys the overlay

    def overlay_click(self):
        # PPController.claimFocusForClick + DraggableOverlayWindow.sendEvent
        if self.fixed:
            if self.ownership.may_key_player_window():
                self.key_holder = "player"
            else:
                self.log.append("overlay click re-key refused (panel owns key)")
        else:
            self.key_holder = "player"

    def esc_pressed(self):
        # escMonitor is a gor-local monitor: it only runs when a gor window
        # is key. mpv holding key -> esc never reaches gor at all.
        if self.key_holder == "mpv":
            return "dead"
        if self.key_holder == "panel":
            return "panel-cancel"
        return "dismiss-search" if self.panel_visible else "player-esc"

    def typing(self):
        if self.key_holder == "panel":
            return "field-text"
        if self.key_holder == "mpv":
            return "dead"
        return "player-keys"  # forwarded to mpv; nothing visible in the field

    def close_panel(self):
        self.panel_visible = False
        self.ownership.unregister("panel-1")        # GORInputPanel.close
        # MagnetBrowser.closeSearch: intentional key return to the player.
        if self.ownership.may_key_player_window():
            self.key_holder = "player"


print("== characterization: pre-fix behavior at 3c48acac ==")
w = World(fixed=False)
w.open_panel(gor_was_active=False)   # o2 beat steals key a moment after open
check("pre-fix reproduces 'focus changed for a moment': o2 steals key after open",
      w.panel_visible and w.key_holder == "player", f"key={w.key_holder}")
check("pre-fix: typing reaches the player path, not the field",
      w.typing() == "player-keys")
w2 = World(fixed=False)
w2.open_panel(gor_was_active=True)
w2.mpv_activated()                   # mpv window steals key
check("pre-fix reproduces mpv-window steal: gor re-keys the overlay",
      w2.key_holder == "player")
w3 = World(fixed=False)
w3.open_panel(gor_was_active=True)
w3.key_holder = "mpv"                # mpv holds key, o1 not yet fired
check("pre-fix: with mpv key, esc AND keyboard are dead for gor",
      w3.esc_pressed() == "dead" and w3.typing() == "dead")
w4 = World(fixed=False)
w4.open_panel(gor_was_active=True)
w4.overlay_click()                   # one click missing the 54pt bar
check("pre-fix: a stray overlay click tears key from the panel",
      w4.key_holder == "player" and w4.panel_visible)

print("== fixed behavior ==")
f = World(fixed=True)
f.open_panel(gor_was_active=False)
check("fixed: o2 activation beat cannot steal key from the opening panel",
      f.key_holder == "panel" and any("o2" in m for m in f.log))
check("fixed: typing lands in the search field", f.typing() == "field-text")
f.overlay_click()
check("fixed: overlay click keeps its action but cannot steal key",
      f.key_holder == "panel")
f.mpv_activated()
check("fixed: mpv activation recovery leaves the panel key",
      f.key_holder == "panel")
check("fixed: esc reaches the panel's cancel path", f.esc_pressed() == "panel-cancel")
f.close_panel()
check("fixed: close releases ownership and returns key to the player",
      f.key_holder == "player" and not f.ownership.panel_owns_key)
f2 = World(fixed=True)
f2.ownership.register("panel-1")
f2.ownership.register("panel-2")
f2.ownership.unregister("panel-1")
check("fixed: with two open panels, closing one keeps ownership",
      f2.ownership.panel_owns_key and not f2.ownership.may_key_player_window())
f2.ownership.register("panel-2")     # idempotent re-register
check("fixed: register is idempotent", f2.ownership.open_panels == ["panel-2"])
f2.ownership.unregister("panel-2")
f2.ownership.unregister("panel-2")   # idempotent unregister (close+deinit)
check("fixed: unregister is idempotent and unknown tokens are a no-op",
      not f2.ownership.panel_owns_key and f2.ownership.may_key_player_window())

print("== source anchors (current Swift tree) ==")
traversal = read_source("PanelFocusTraversal.swift")
check("PanelKeyOwnership lives in PanelFocusTraversal.swift",
      "final class PanelKeyOwnership" in traversal)
check("ownership exposes register/unregister/mayKeyPlayerWindow",
      all(s in traversal for s in ("func register(_ token:ObjectIdentifier)",
                                   "func unregister(_ token:ObjectIdentifier)",
                                   "func mayKeyPlayerWindow() -> Bool")))
check("ownership type is AppKit-free (Foundation/stdlib only)",
      "import AppKit" not in traversal and "NSWindow" not in traversal)

focus = read_source("PanelFocus.swift")
check("GORInputPanel registers on key claims and releases on close/orderOut/deinit",
      all(s in focus for s in ("PanelKeyOwnership.shared.register(ObjectIdentifier(self))",
                               "releaseKeyOwnership();super.close()",
                               "releaseKeyOwnership();super.orderOut(sender)",
                               "deinit {PanelKeyOwnership.shared.unregister")))
check("[panel-focus] diagnostics at open-assert/became-key/resigned-key/post-loss",
      all(s in focus for s in ('[panel-focus]', '"open-assert"', '"became-key"',
                               '"resigned-key"', '"post-loss"')))

app = read_source("AppDelegate.swift")
guard_count = app.count("PanelKeyOwnership.shared.mayKeyPlayerWindow()")
check("AppDelegate retains original four guards and adds attach/AX-raise/tap guards",
      guard_count == 7, f"count={guard_count}")
for m in re.finditer(re.escape("makeKeyAndOrderFront(nil)"), app):
    ctx = app[max(0, m.start() - 260):m.start()]
    is_setup = "win.makeKeyAndOrderFront(nil)" in app[m.start()-4:m.end()]
    check("every AppDelegate makeKeyAndOrderFront(nil) is guarded or initial setup",
          "mayKeyPlayerWindow()" in ctx or is_setup,
          f"offset={m.start()}")

import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
ppc = _plat_read(_pp_split().path(os.path.dirname(os.path.dirname(SRC)), "PPController.swift"),encoding="utf-8")
check("PPController.claimFocusForClick is guarded",
      ppc.count("PanelKeyOwnership.shared.mayKeyPlayerWindow()") == 1)

mb = read_source("MagnetBrowser.swift")
check("MagnetBrowser.closeSearch keeps the intentional key return on close",
      "parent?.makeKeyAndOrderFront(nil)" in mb)

print()
if failures:
    print(f"RESULT: FAIL ({len(failures)} failing checks)")
    sys.exit(1)
print("RESULT: PASS (characterization + fixed invariants + source anchors)")
