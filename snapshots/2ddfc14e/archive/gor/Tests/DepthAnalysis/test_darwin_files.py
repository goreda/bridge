#!/usr/bin/env python3
"""s40: the DarwinTypecheck FILES list must name files that exist on disk
(a typo'd entry makes swiftc fail with 'no such file' and the whole
typecheck harness dies - s40 read found ThreeDDegradeProbe vs the real
ThreeDDegradeProbes.swift). Box-independent.

Run: python3 Tests/DepthAnalysis/test_darwin_files.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
TC = os.path.join(ROOT, "Tests", "DarwinTypecheck", "darwin_typecheck_test.py")

m = re.search(r'^FILES = "([^"]+)"', open(TC).read(), re.M)
assert m, "FILES list not found"
files = m.group(1).split()
missing = [f for f in files
           if not os.path.exists(os.path.join(ROOT, "Sources", "gor", f + ".swift"))]
assert not missing, f"FILES entries with no Sources/gor/<name>.swift: {missing}"
dupes = {f for f in files if files.count(f) > 1}
assert not dupes, f"duplicate FILES entries: {dupes}"
print(f"PASS test_darwin_files ({len(files)} FILES entries all exist, no dupes)")
