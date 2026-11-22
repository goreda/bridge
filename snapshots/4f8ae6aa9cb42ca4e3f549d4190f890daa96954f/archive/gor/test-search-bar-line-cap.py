#!/usr/bin/env python3
"""Item: search bars grow one line per wrapped line up to a 4-line cap.

Structural checks on SearchBarFit plus a Python port of the fit() height
math. AppKit text measurement is Mac-only, so the wrapped-line count is
fed to the port as an input (replicated logic).

Linux: RUN. Mac/AppKit (real NSTextField sizing): NOT_RUN.
"""
import math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "Sources", "gor", "MagnetBrowser.swift")

fails = []
def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (" - " + detail if detail else ""))
    if not ok:
        fails.append(name)

src = open(SRC, encoding="utf-8").read()

check("maxLines constant is 4", "static let maxLines = 4" in src)
check("fit() clamps wrapped lines at maxLines",
      "lines = maxLines > 0 ? min(maxLines, wrapped) : wrapped" in src)
check("install routes the field line limit through maxLines",
      "field.maximumNumberOfLines = maxLines" in src)
check("magnet search field routes through maxLines",
      "field.maximumNumberOfLines = SearchBarFit.maxLines" in src)

def panel_h(single, max_width, min_width, measured_h, line_h, max_lines):
    # Port of SearchBarFit.fit(): the height-relevant part only.
    width = min(max_width, max(min_width, single))
    lines = 1
    if single > max_width:
        wrapped = max(1, math.ceil(measured_h / line_h))
        lines = min(max_lines, wrapped) if max_lines > 0 else wrapped
    field_h = max(28, 28 + (lines - 1) * line_h)
    return 54 + (field_h - 28)

CAP = 4
for n in (1, 2, 3, 4):
    a = panel_h(2000, 800, 300, n * 15.0, 15.0, CAP)
    b = panel_h(2000, 800, 300, n * 15.0, 15.0, 0)
    check("wrapped lines=%d unchanged by cap" % n, a == b, "capped=%r uncapped=%r" % (a, b))
four = panel_h(2000, 800, 300, 4 * 15.0, 15.0, CAP)
for n in (5, 6, 10):
    a = panel_h(2000, 800, 300, n * 15.0, 15.0, CAP)
    u = panel_h(2000, 800, 300, n * 15.0, 15.0, 0)
    check("wrapped lines=%d held at 4-line height" % n, a == four and u > a,
          "capped=%r four=%r uncapped=%r" % (a, four, u))
a = panel_h(300, 800, 300, 15.0, 15.0, CAP)
b = panel_h(300, 800, 300, 15.0, 15.0, 0)
check("single-line unchanged", a == b, "capped=%r uncapped=%r" % (a, b))

print(("%d check(s) failed" % len(fails)) if fails else "all checks passed")
sys.exit(1 if fails else 0)
