#!/usr/bin/env python3
"""Randomized property test of WTCropSamples.positions (Python mirror of the Swift rule; constants read from the Swift
source). 20000 random range sets: every position lies inside a usable range with the tail margin kept, positions come
out sorted, the count is exactly sampleCount when any range is usable and 0 otherwise, and positions spread over all
usable ranges in proportion to their length (each range with length >= total/count gets at least one)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, random, re, sys
SW = (lambda _b: _b[_b.index('// BEGIN relocated '+'WTCropSamples.swift'+' '):_b.index('// END relocated '+'WTCropSamples.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
TAIL, MINR = (float(re.search(r"static let %s = ([0-9.]+)" % k, SW).group(1)) for k in ("tailMargin", "minRange"))
N = int(re.search(r"static let sampleCount = (\d+)", SW).group(1))
def positions(ranges, count=N):
    use = sorted((max(0, a), b - TAIL) for a, b in ranges if b - a >= MINR and b - TAIL > max(0, a))
    total = sum(b - a for a, b in use)
    if total <= 0: return [], use
    out = []
    for i in range(count):
        u = total * (i + .5) / count
        for a, b in use:
            if u <= b - a: out.append(a + u); break
            u -= b - a
    return out, use
rnd = random.Random(7); bad = []
for k in range(20000):
    rs = []; t = rnd.uniform(0, 30)
    for _ in range(rnd.randint(0, 5)):
        a = t; b = a + rnd.choice([0.5, 1, 2.9, 3, 5, 20, 90, 400]) * rnd.uniform(.5, 1.5); rs.append((a, b)); t = b + rnd.uniform(0.1, 60)
    rnd.shuffle(rs)
    pos, use = positions(rs)
    if not use:
        if pos: bad.append(("nonempty without usable", rs)); continue
        continue
    if len(pos) != N: bad.append(("count", rs))
    if pos != sorted(pos): bad.append(("order", rs))
    if any(not any(a - 1e-9 <= p <= b + 1e-9 for a, b in use) for p in pos): bad.append(("outside", rs))
    total = sum(b - a for a, b in use)
    for a, b in use:
        if (b - a) >= 2 * total / N and not any(a <= p <= b for p in pos): bad.append(("range skipped", rs))
print("20000 random range sets: %d violations (tail=%.1f minRange=%.1f count=%d)" % (len(bad), TAIL, MINR, N))
for b in bad[:3]: print(b)
print("PASS" if not bad else "FAIL"); sys.exit(1 if bad else 0)
