#!/usr/bin/env python3
"""Thermal acceptance for a gor-heat-kit report: gor-process cpu (% of one core) per real stage against caps.
Usage: gor-heat-accept.py report.txt   (exit 0 = all stages within caps, 1 = a stage is over, 2 = stage missing)
Caps are targets chosen from the 02:33 v2 run (22/86/60/42 %), not a thermal measurement."""
import re, sys
CAPS = {'real-1-playing': 15.0, 'real-2-playing-mouse-moving': 40.0, 'real-3-paused': 5.0, 'real-3b-paused-settled': 5.0, 'real-4-seeking': 30.0}
def parse(text):
    return {m.group(1): float(m.group(2)) for m in re.finditer(r'^\[(real-[^\]]+)\] gor cpu=([\d.]+)%', text, re.M)}
def verdict(text, caps=CAPS):
    got, rows, rc = parse(text), [], 0
    for st, cap in caps.items():
        if st not in got: rows.append('MISSING %s' % st); rc = max(rc, 2); continue
        ok = got[st] <= cap; rows.append('%s %s gor cpu=%.1f%% cap=%.0f%%' % ('PASS' if ok else 'FAIL', st, got[st], cap)); rc = max(rc, 0 if ok else 1)
    return rc, rows
if __name__ == '__main__':
    rc, rows = verdict(open(sys.argv[1]).read()); print('\n'.join(rows)); sys.exit(rc)
