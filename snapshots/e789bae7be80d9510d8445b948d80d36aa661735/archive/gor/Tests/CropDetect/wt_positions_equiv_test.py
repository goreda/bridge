#!/usr/bin/env python3
"""Numeric equivalence of the SourcePixelCrop scan rewrite (typed statements) against the original expressions.
Original Swift (24f36be75):
  let positions = samplePositions?() ?? (d > 0 ? (0..<40).map { max(0,min(d-0.001,d * (Double($0)+0.5)/40)) } : [0.0])
  guard sampled >= (samplePositions == nil ? 1 : min(3, positions.count)), ...
Rewrite:
  overridePositions = samplePositions?(); positions = [0.0]; if let op {positions = op} else if d > 0 { map { x = d*(Double(i)+0.5); y = x/40.0; max(0.0, min(d-0.001, y)) } }
  needSamples = samplePositions == nil ? 1 : min(3, positions.count)
Both are modeled with IEEE doubles (Python float == Swift Double: same multiplication/division order, left to right).
Also asserts the Swift source holds exactly the rewritten form. It does NOT assert that the rest of the file is unchanged (that was checked once by git diff 24f36be75..05ec397bc: only these two expressions changed in SourcePixelCrop.swift).
Linux model only: the Swift is compiled natively in CI (zuellue/gor-ci) but never run here."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, random, re, sys
SP = (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
fails = 0
def check(n, ok):
    global fails; print(("ok   " if ok else "FAIL ") + n); fails += 0 if ok else 1
def old_positions(d, sp):
    if sp is not None: return list(sp)
    return [max(0.0, min(d - 0.001, d * (i + 0.5) / 40)) for i in range(40)] if d > 0 else [0.0]
def new_positions(d, sp):
    positions = [0.0]
    if sp is not None: positions = list(sp)
    elif d > 0:
        out = []
        for i in range(40):
            x = d * (float(i) + 0.5); y = x / 40.0; out.append(max(0.0, min(d - 0.001, y)))
        positions = out
    return positions
def old_need(sp, pos): return 1 if sp is None else min(3, len(pos))
def new_need(sp, pos): return 1 if sp is None else min(3, len(pos))
random.seed(7)
ds = [float('inf'), float('-inf'), float('nan'), 0.0, -0.0, -1.0, 0.0009, 0.00100001, 1e-9, 0.0005, 0.001, 0.0011, 1.0, 59.94, 3600.0, 7200.5, 86399.999, 1e7] + [random.uniform(0.0001, 20000) for _ in range(20000)] + [random.choice([29.97, 23.976, 5400.0, 9000.123456789]) * random.random() for _ in range(5000)]
bad = [d for d in ds if repr(old_positions(d, None)) != repr(new_positions(d, None))]
check("default positions: %d durations, bit-identical (incl. d<=0, -0, nan, inf, short-duration clamp d<0.001)" % len(ds), not bad)
ovs = [[], [0.0], [1.5, 2.5], [1.0, 2.0, 3.0, 4.0, 5.0], [9.9] * 40]
check("override positions pass through untouched", all(old_positions(d, o) == new_positions(d, o) for d in (0.0, 100.0) for o in ovs))
check("sample threshold equal for nil and every override length 0..45", all(old_need(sp, old_positions(10.0, sp)) == new_need(sp, new_positions(10.0, sp)) for sp in [None] + [[1.0] * n for n in range(46)]))
check("threshold values: nil->1, 0 pos->0, 1->1, 2->2, 3+->3", [new_need(None, [])] + [new_need([1.0] * n, [1.0] * n) for n in (0, 1, 2, 3, 40)] == [1, 0, 1, 2, 3, 3])
# A deliberately wrong rewrite (d * ((i+.5)/40)) must differ, proving the harness can see operation-order drift.
drift = [d for d in ds if old_positions(d, None) != [max(0.0, min(d - 0.001, d * ((i + 0.5) / 40))) for i in range(40)] and d > 0]
check("harness sensitivity: reassociated multiply/divide differs on %d durations" % len(drift), len(drift) > 0)

# goreda grid: binary64 cross-check, measured (positions bit-compared, max ULP reported)
import math, struct
grid = [0.0, -1.0, float('nan'), 1e-12, 0.0005, 0.001, 0.01, 0.5, 1.0, 24.7, 359.99, 3600.0, 86400.0, 1e6, 1e15]
def bits(x): return struct.unpack('<q', struct.pack('<d', x))[0]
mx = 0; mism = 0
for d in grid:
    o, n = old_positions(d, None), new_positions(d, None)
    if len(o) != len(n): mism += 1; continue
    for a, b in zip(o, n):
        if bits(a) != bits(b): mism += 1; mx = max(mx, abs(bits(a) - bits(b)))
check("goreda grid (15 durations x 40 positions): %d bit mismatches, max ULP %d, NaN falls back to [0.0] in both (%s)" % (mism, mx, old_positions(float('nan'), None)), mism == 0 and old_positions(float('nan'), None) == [0.0] == new_positions(float('nan'), None))
wrong = sum(1 for d in grid if d > 0 for i in range(40) if bits(max(0.0, min(d-0.001, d*(i+0.5)/40))) != bits(max(0.0, min(d-0.001, d*((i+0.5)/40)))))
print("info: the reassociated variant (rejected) differs in %d of %d grid positions" % (wrong, 40 * sum(1 for d in grid if d > 0)))
for sp in (None, [], [0.0], [1.0]*5, [1.0]*40):
    for cnt in range(6):
        pass
check("override absent/empty/[0]/5/40 positions: branch, length and needSamples equal", all(old_need(sp, old_positions(10.0, sp)) == new_need(sp, new_positions(10.0, sp)) and len(old_positions(10.0, sp)) == len(new_positions(10.0, sp)) for sp in (None, [], [0.0], [1.0]*5, [1.0]*40)))
check("Swift source holds the exact modeled rewrite (x = d*(Double(i)+0.5); y = x/40.0; max(0.0, min(d-0.001, y)))", "let x: Double = d * (Double(i) + 0.5); let y: Double = x / 40.0; return max(0.0, min(d - 0.001, y))" in SP)
check("Swift source threshold is the modeled one", "let needSamples: Int = samplePositions == nil ? 1 : min(3, positions.count)" in SP)
check("original combined expressions are gone", "samplePositions?() ?? (d > 0" not in SP and "sampled >= (samplePositions == nil" not in SP)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
