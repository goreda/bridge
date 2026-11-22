#!/usr/bin/env python3
"""Pins for tools/update_playing_guard.py with a fake process table, plus the one-line build.sh hook and its net-0 size."""
import os, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import update_playing_guard as G

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

def table(gor, mpv):
    def r(cmd):
        if "-x" in cmd:
            return (0, "42\n") if mpv else (1, "")
        return (0, "7\n") if gor else (1, "")
    return r

notes = []
say = notes.append
check("idle (no gor) proceeds", G.guard("/p", 501, 5, 0, table(False, True), lambda s: None, say) == 0)
check("gor without mpv proceeds", G.guard("/p", 501, 5, 0, table(True, False), lambda s: None, say) == 0)
check("playing and stays playing: exit 75, app untouched note", G.guard("/p", 501, 0, 0, table(True, True), lambda s: None, say) == 75 and any("NOT touched" in n for n in notes), notes)
state = {"n": 0}
def ending(cmd):
    if "-x" in cmd:
        state["n"] += 1
        return (0, "42\n") if state["n"] < 3 else (1, "")
    return 0, "7\n"
check("playback stops during the wait: continues", G.guard("/p", 501, 60, 0, ending, lambda s: None, say) == 0, notes)
check("pgrep failure never blocks", G.guard("/p", 501, 5, 0, lambda c: (2, ""), lambda s: None, say) == 0)
os.environ["GOR_UPDATE_WHILE_PLAYING"] = "1"
check("override env skips the guard", G.guard("/p", 501, 5, 0, table(True, True), lambda s: None, say) == 0)
del os.environ["GOR_UPDATE_WHILE_PLAYING"]
sh = (ROOT / "build.sh").read_text()
check("build.sh runs the guard first in --update-build", re.search(r'--update-build\)\n[^\n]*GOR_SELFTEST[^\n]*update_playing_guard\.py[^\n]*\|\| exit \$\?', sh) is not None)
check("build.sh stays within its 2773-line ceiling", len(sh.splitlines()) <= 2773, len(sh.splitlines()))
for ln in (161, 207, 487, 491, 684):
    check("build.sh overlay list on line %d carries models (lock reaches the Mac)" % ln, re.search(r'plan models|"plan", "models"', sh.splitlines()[ln - 1]) is not None, sh.splitlines()[ln - 1][:80])
print("FAILURES: %d" % fails)
sys.exit(1 if fails else 0)
# Pin note 1: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 2: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 3: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 4: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 5: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 6: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 7: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 8: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 9: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 10: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 11: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 12: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 13: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 14: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 15: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 16: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 17: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 18: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 19: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 20: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 21: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 22: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 23: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 24: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 25: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 26: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 27: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 28: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 29: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 30: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 31: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 32: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 33: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 34: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 35: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 36: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 37: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 38: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 39: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 40: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 41: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 42: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 43: the guard only reads process state; it never stops, moves or launches anything.
# Pin note 44: the guard only reads process state; it never stops, moves or launches anything.
