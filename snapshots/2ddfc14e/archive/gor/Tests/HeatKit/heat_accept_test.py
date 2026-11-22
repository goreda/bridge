#!/usr/bin/env python3
"""Acceptance tool test: the 02:33 owner run (gor 22/86/60/42 %) must FAIL the caps; a within-cap report passes; missing stage = rc2."""
import importlib.util, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('acc', root/'tools/gor-heat-accept.py'); acc = importlib.util.module_from_spec(spec); spec.loader.exec_module(acc)
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
v2 = '''[real-1-playing] gor cpu=22.0% mpv cpu=0.4% win=25.0s
[real-2-playing-mouse-moving] gor cpu=85.9% mpv cpu=0.7% win=25.1s
[real-3-paused] gor cpu=59.7% mpv cpu=1.0% win=20.0s
[real-4-seeking] gor cpu=42.1% mpv cpu=0.8% win=18.2s
'''
rc, rows = acc.verdict(v2); print('\n'.join(rows))
check('owner 02:33 baseline is over every cap (rc>=1) - the fix is not proven until a run passes', rc >= 1 and sum(r.startswith('FAIL') for r in rows) == 4)
good = '\n'.join('[%s] gor cpu=%s%% mpv cpu=0.5%%' % (k, c/2) for k, c in acc.CAPS.items())
check('within caps passes', acc.verdict(good)[0] == 0)
check('one stage over cap fails', acc.verdict(good.replace('real-3-paused] gor cpu=2.5', 'real-3-paused] gor cpu=9.0'))[0] == 1)
check('missing stage is rc 2', acc.verdict('[real-1-playing] gor cpu=3.0%')[0] == 2)
sys.exit(1 if fails else 0)
