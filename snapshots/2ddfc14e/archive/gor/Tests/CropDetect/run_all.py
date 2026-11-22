#!/usr/bin/env python3
"""Runs every *_test.py in this directory (glob, so a new or existing test cannot be omitted) and fails if any fails or none are found."""
import pathlib, subprocess, sys
here = pathlib.Path(__file__).resolve().parent
tests = sorted(p for p in here.glob("*_test.py"))
bad = []
for t in tests:
    r = subprocess.run([sys.executable, str(t)], capture_output=True, text=True, timeout=300)
    last = (r.stdout.strip().splitlines() or [""])[-1]
    print("%-34s rc=%d %s" % (t.name, r.returncode, last[:60]))
    if r.returncode: bad.append(t.name)
print("%d tests, %d failed%s" % (len(tests), len(bad), (": " + ", ".join(bad)) if bad else ""))
sys.exit(1 if bad or not tests else 0)
