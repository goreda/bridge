#!/usr/bin/env python3
"""Random repeat fix (owner order 2026-11-15): statistical repeat test for the
session shuffle bag, plus the single-algorithm binding assertion.

Part 1 mirrors ArchiveRandom.drawIndex in Python (os.urandom word source; the
Swift leg runs on Mac): no immediate repeats including bag boundaries, full-
cycle permutation coverage, chi-square uniformity. Part 2 reads the product
sources and asserts every panel random button routes to the same bag draw.
"""
import math, os, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def word():
    return int.from_bytes(os.urandom(4), "big")

def choose_index(count):
    limit = 2**32 // count * count
    while True:
        v = word()
        if v < limit:
            return v % count

class Bag:
    def __init__(self):
        self.order, self.cursor = [], 0

    def draw(self, count):
        if len(self.order) == count and self.cursor < len(self.order):
            i = self.order[self.cursor]; self.cursor += 1
            return i
        order = list(range(count))
        for i in range(count - 1, 0, -1):
            j = choose_index(i + 1)
            order[i], order[j] = order[j], order[i]
        if count > 1 and self.order and order[0] == self.order[-1]:
            order[0], order[1] = order[1], order[0]
        self.order, self.cursor = order, 1
        return order[0]

failures = []
def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failures.append(name)

for count in (2, 3, 7, 25, 250):
    bag = Bag()
    draws = [bag.draw(count) for _ in range(120_000 if count <= 25 else 40_000)]
    check(f"n={count}: zero immediate repeats across {len(draws)} draws incl. bag boundaries",
          all(a != b for a, b in zip(draws, draws[1:])))
    cycles = len(draws) // count
    coverage = all(sorted(draws[c * count:(c + 1) * count]) == list(range(count)) for c in range(cycles))
    check(f"n={count}: every full cycle is an exact permutation", coverage)
    # Marginal frequencies are degenerate for a bag (exactly uniform over full
    # cycles), so uniformity is tested on the shuffle itself: for each position
    # in the cycle the value distribution must be uniform. Only run where the
    # expected per-cell count (cycles/count) supports a chi-square.
    if cycles // count >= 5:
        total, df = 0.0, 0
        for p in range(count):
            col = [draws[c * count + p] for c in range(cycles)]
            exp = cycles / count
            total += sum((col.count(v) - exp) ** 2 / exp for v in range(count))
            df += count - 1
        lo, hi = df - 6 * math.sqrt(2 * df), df + 6 * math.sqrt(2 * df)
        check(f"n={count}: per-position shuffle uniformity chi2={total:.1f} within 6-sigma band ({lo:.1f}..{hi:.1f})", lo <= total <= hi)

binding = {
    "Sources/gor/Media/ArchiveBrowser.swift": 'ArchiveRandom.shared.drawIndex(count: self.randomActions.count, session: "archive-browser")',
    "Sources/gor/Media/FileBrowser.swift": 'ArchiveRandom.shared.drawIndex(count: choices.count, session: "file-browser")',
    "Sources/gor/Media/IPTV.swift": 'ArchiveRandom.shared.drawIndex(count: count, session: "iptv")',
}
for rel, needle in binding.items():
    src = (ROOT / rel).read_text()
    check(f"{rel}: random button bound to the shared bag draw", needle in src)
    stale = re.findall(r"ArchiveRandom\.shared\.chooseIndex", src)
    check(f"{rel}: no random button left on the with-replacement draw", not stale)

sys.exit(1 if failures else 0)
