#!/usr/bin/env python3
"""Item: a new magnet search replaces the one in flight.

The 20s throttle that rejected a second search is gone; the generation
token that cancels the old search and drops its stale callbacks is
untouched. Structural checks plus a replicated cancel-replace model.

Linux: RUN. Mac/AppKit: NOT_RUN.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "Sources", "gor", "MagnetBrowser.swift")

fails = []
def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (" - " + detail if detail else ""))
    if not ok:
        fails.append(name)

src = open(SRC, encoding="utf-8").read()

check("throttle state removed", "throttledUntil" not in src)
check("throttle status removed", "wait before searching again" not in src)
check("empty/short guard kept",
      'guard !q.isEmpty, q.count <= 120 else { panel.setStatus("enter a shorter search"); return }' in src)
check("generation bump kept", "generation += 1; parseSerial += 1; let token = generation" in src)
check("stale-callback guards kept (>=6)", src.count("self.generation == token") >= 6,
      "count=%d" % src.count("self.generation == token"))
check("stop() still cancels tasks", "tasks.forEach { $0.cancel() }; tasks.removeAll()" in src)
check("stop() still cancels sessions", "sessions.forEach { $0.invalidateAndCancel() }; sessions.removeAll()" in src)
check("stop() still cancels tracker queue", "trackerQueue.cancelAllOperations()" in src)

class Controller:
    # Port of the generation-token rule: a callback lands only while it
    # still carries the current generation.
    def __init__(self):
        self.generation = 0
        self.rows = []
    def search(self, q):
        self.generation += 1
        return self.generation
    def callback(self, token, rows):
        if token != self.generation:
            return False
        self.rows = rows
        return True

c = Controller()
a = c.search("first")
b = c.search("second")
check("in-flight search callback is rejected after a newer search",
      c.callback(a, ["old-row"]) == False and c.rows == [])
check("new search callback is accepted",
      c.callback(b, ["new-row"]) == True and c.rows == ["new-row"])

print(("%d check(s) failed" % len(fails)) if fails else "all checks passed")
sys.exit(1 if fails else 0)
