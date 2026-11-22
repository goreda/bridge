#!/usr/bin/env python3
"""PhotonFont driven-font cache: bigger cap (1024) + O(1) LRU touch. Output identity: the cache only decides how long a font built from a
key is kept; the key function and the font construction are unchanged (pinned below), so a lookup returns the same font either way.
Python port of old (cap 256, array shift per hit) and new (cap 1024, stamp per hit) LRU, 75 listeners x audio oscillation.
Linux/Python model only: no CoreText run, no cycle-time claim."""
import math, pathlib, random, sys, subprocess
root = pathlib.Path(__file__).resolve().parents[2]
pf = (root/'Sources/gor/UI/PhotonFont.swift').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
class Old:
    def __init__(s, cap): s.cap, s.order, s.idx, s.d, s.miss, s.ops = cap, [], {}, {}, 0, 0
    def get(s, key, make):
        if key in s.d:
            i = s.idx[key]; s.order.pop(i); s.order.append(key)
            for j in range(i, len(s.order)): s.idx[s.order[j]] = j; s.ops += 1
            return s.d[key]
        s.miss += 1; f = make(key); s.d[key] = f; s.order.append(key); s.idx[key] = len(s.order)-1
        while len(s.order) > s.cap:
            e = s.order.pop(0)
            for k in list(s.idx): s.idx[k] -= 1; s.ops += 1
            del s.idx[e]; del s.d[e]
        return f
class New:
    def __init__(s, cap): s.cap, s.clock, s.stamp, s.d, s.miss, s.ops = cap, 0, {}, {}, 0, 0
    def get(s, key, make):
        if key in s.d: s.clock += 1; s.stamp[key] = s.clock; s.ops += 1; return s.d[key]
        s.miss += 1; f = make(key); s.d[key] = f; s.clock += 1; s.stamp[key] = s.clock
        while len(s.stamp) > s.cap:
            e = min(s.stamp, key=s.stamp.get); del s.stamp[e]; del s.d[e]
        return f
make = lambda key: ('font', key)                       # pure function of the key, exactly like CTFontCreateWithFontDescriptor(key vars)
def workload(c, fanouts=1500, listeners=75, seed=5):
    r = random.Random(seed); ps = [r.random() for _ in range(listeners)]; ret = []
    for f in range(fanouts):
        a = 0.5 + 0.3*math.sin(f/23.0) + 0.1*math.sin(f/5.0)
        for i, p in enumerate(ps):
            t = max(0.0, min(1.0, a*(0.4+0.6*p)))
            key = '%d:%s|%d' % (i % 3, round(t*128)/128, 4*(10 + i % 4))
            ret.append((key, c.get(key, make)))
    return ret
o, n = Old(256), New(1024); ro, rn = workload(o), workload(n)
check('every lookup returns the same font as the old cache (visual output unchanged)', ro == rn and all(f == make(k) for k, f in rn))
print('misses: old cap256=%d new cap1024=%d of %d lookups; per-hit/evict ops old=%d new=%d' % (o.miss, n.miss, len(rn), o.ops, n.ops))
check('fewer font builds (each is a CoreText typeset init)', n.miss < o.miss*0.6)
check('LRU touch/eviction work is O(1) per hit instead of O(n)', n.ops*10 < o.ops)
class MRU(New):                                         # mutant: evicts the newest -> must be worse, so the test can tell LRU from wrong order
    def get(s, key, make):
        if key in s.d: s.clock += 1; s.stamp[key] = s.clock; return s.d[key]
        s.miss += 1; f = make(key); s.d[key] = f; s.clock += 1; s.stamp[key] = s.clock
        while len(s.stamp) > s.cap:
            e = max((k for k in s.stamp if k != key), key=s.stamp.get); del s.stamp[e]; del s.d[e]
        return f
m = MRU(1024); workload(m); check('mutant MRU eviction is caught', m.miss > n.miss)
small = New(256); workload(small); check('cap matters: 256 with the new LRU still misses more than 1024', small.miss > n.miss)
pin = lambda name, t: check('pin: ' + name, t in pf)
pin('cap 1024', 'private static let CacheMaxEntries = 1024')
pin('key still normalised round(v*steps)/steps', 'let q = (normalized * CacheQuantizationSteps).rounded() / CacheQuantizationSteps')
pin('key still sorted by tag', 'vars.keys.sorted()')
pin('steps default stays 128', 'v.rounded() : 128 }()')
pin('ct font built exactly as before', 'let font = CTFontCreateWithFontDescriptor(desc, s, nil)')
pin('ns font built exactly as before', 'let font = NSFont(descriptor: desc, size: s) ?? base')
pin('O(1) hit', '_cacheIndex[key] = _cacheClock')
pin('eviction drops both caches', '_cache.removeValue(forKey: evict)'); pin('eviction drops ns cache', '_nsCache.removeValue(forKey: evict)')
check('no per-hit array shift remains', 'remove(at: idx)' not in pf and '_cacheOrder' not in pf)
print('INVENTORY PhotonFont lines=%d (not a correctness quota)' % len(pf.splitlines()))
# Actual cacheKey body execution, including nonrepresentable-size safety.
semantic = subprocess.run([sys.executable, str(root/'Tests/ConsumerContracts/run.py'), 'font'])
check('actual extracted cacheKey semantics', semantic.returncode == 0)
print('font cache: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
