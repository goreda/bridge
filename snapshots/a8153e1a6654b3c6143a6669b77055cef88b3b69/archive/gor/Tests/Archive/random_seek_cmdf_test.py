#!/usr/bin/env python3
"""R random-seek + Cmd+F search toggle (owner order 2026-11-15): source-binding
assertions. The event tap, key codes and UI behavior run on the Mac leg; this
test pins the wiring so a later refactor cannot silently unbind either key.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
app = (ROOT / "Sources/gor/App/AppDelegate.swift").read_text()
fb = (ROOT / "Sources/gor/Media/FileBrowser.swift").read_text()
ma = (ROOT / "Sources/gor/UI/MenuActions.swift").read_text()
ab = (ROOT / "Sources/gor/Media/ArchiveBrowser.swift").read_text()
mb = (ROOT / "Sources/gor/Media/MagnetBrowser.swift").read_text()
pc = (_pp_split().path(ROOT,'PPController.swift')).read_text()

failures = []
def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failures.append(name)

# R key: tap branch on plain keyCode 15 (macOS kVK_ANSI_R), no modifier chords,
# dispatching to the playback/playlist router. Panels never see this branch:
# their own local monitor presses the panel random button while the tap is off.
check("tap: plain keyCode 15 (r) branch present, chords excluded",
      "keyCode == 15" in app and ".maskCommand) && !flags.contains(.maskShift)" in app)
check("tap: r dispatches routeRandomKey", "selfPtr.routeRandomKey()" in app)
check("router: playing -> random seek, otherwise -> random playlist entry",
      "func routeRandomKey()" in app and "controller?.isPlaying == true" in app
      and "controller?.randomPlaylistEntry()" in app)
check("randomPlaylistEntry: synchronous playlist-count query + bag draw + playlist-pos",
      'get_property","playlist-count' in pc and "chooseIndex(count: n)" in pc
      and 'set_property","playlist-pos' in pc)
check("panels: file and archive browsers expose pressRandomFromKey",
      "func pressRandomFromKey() { topBar.onRandom?() }" in fb
      and "func pressRandomFromKey() { topBar.onRandom?() }" in ab)
check("panels: local r monitors press the panel random button, search-field keys pass",
      ma.count("pressRandomFromKey()") == 3 and "event.keyCode == 15" in ma
      and "event.window === browser.window" in ma and "event.window === panel.window" in ma)
check("menuRandomSeek: bag draw over 20 duration buckets with the shared session",
      'drawIndex(count: buckets, session: "random-seek")' in app and "let buckets = 20" in app)
check("menuRandomSeek: absolute fraction seek via controller.seek(to:)",
      re.search(r"c\.seek\(to: \(Double\(bucket\) \+ Double\(offset\) / 1000\.0\) / Double\(buckets\)\)", app) is not None)
check("menuRandomSeek: no active player is a no-op", "c.duration > 1" in app)

# Cmd+F: MENU key equivalent, not the event tap (owner report 2026-11-15:
# the tap route beeped, because opening a browser panel sets
# isShowingInputPanel and disables the tap for the panel's whole lifetime).
menu = app.find('"find in panel"')
check("menu: 'find in panel' item with Cmd+F key equivalent",
      menu != -1 and "#selector(menuFindInPanel)" in app and 'key: "f"' in app[menu:menu+200])
check("menu: handler routes to the frontmost searchable panel",
      "func menuFindInPanel()" in ma and "frontmostSearchablePanel()" in ma)
check("handler: toggles all three searchable panels",
      "p.toggleSearchPanelFromKey()" in ma and ma.count("p.toggleSearchFromKey()") == 2)
check("panels: archive and magnet expose a search toggle",
      "func toggleSearchFromKey()" in ab and "func toggleSearchFromKey()" in mb)
check("discovery: recursive scan over ordered windows covers the three panel types",
      "func frontmostSearchablePanel() -> NSView?" in app and "NSApp.orderedWindows" in app
      and "v is FileBrowserPanel || v is ArchiveBrowserPanel || v is MagnetResultsPanel" in app)
check("tap: no Cmd+F branch left in the event tap (menu owns the key)",
      "keyboardEventKeycode) == 3" not in app)

# FileBrowser forwards: panel -> top bar -> existing toggle paths.
check("FileBrowserPanel forwards toggleSearchPanelFromKey to the top bar",
      "func toggleSearchPanelFromKey() { topBar.toggleSearchPanelFromKey() }" in fb)
check("top bar toggle closes a visible field, else runs the search-button path",
      re.search(r"func toggleSearchPanelFromKey\(\) \{\s*if closeSearchPanelIfOpen\(\) \{ return \}\s*handleSearchTap\(\)", fb) is not None)

sys.exit(1 if failures else 0)
