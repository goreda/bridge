#!/usr/bin/env python3
"""Deterministic vector generator for P-A4 (no randomness). Expected values
are computed with exact Python big-int math, independently of the Swift
implementation, replicating the checked-naive contract semantics:
rescale = (v*dst +/- src/2) / src with truncating division, where the
multiply AND the rounding addition must each fit Int64 or the result is the
typed error overflow."""
import os

I64_MIN = -(2**63)
I64_MAX = 2**63 - 1
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "../Tests/BridgeTimeMathTests/Fixtures")

def fits(x): return I64_MIN <= x <= I64_MAX

def trunc_div(a, b):  # Swift-style truncation toward zero
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q

def rescale(v, src, dst):
    if src <= 0 or dst <= 0: return "nonPositiveScale"
    p = v * dst
    if not fits(p): return "overflow"
    half = src // 2
    r = p + half if v >= 0 else p - half
    if not fits(r): return "overflow"
    return str(trunc_div(r, src))

def split(total, parts):
    if parts <= 0: return "nonPositiveParts"
    q = trunc_div(total, parts)
    r = total - q * parts
    if r < 0:
        q -= 1
        r += parts
    return ";".join(str(q + 1 if i < r else q) for i in range(parts))

def addsub(a, b, op):
    r = a + b if op == "add" else a - b
    return str(r) if fits(r) else "overflow"

M = I64_MAX
m = I64_MIN

rescale_rows = [
    # regression: rescale-overflow-at-rounding-addition
    # v*dst = 9223372036854775806 fits; the +src/2 = 2 addition overflows.
    ("4611686018427387903", 4, 2),
    # negative symmetry of the regression edge: product fits, addition fits
    ("-4611686018427387903", 4, 2),
    # negative side one past it: the -src/2 subtraction overflows
    ("-4611686018427387904", 4, 2),
    # Int64.max / Int64.min inputs
    (str(M), 1, 1), (str(m), 1, 1),
    (str(M), 1, 2), (str(m), 1, 2),      # product overflows
    (str(M), 2, 1), (str(m), 2, 1),      # product fits, +/-1 addition overflows
    (str(M), 1000000, 1),                # product fits, +500000 overflows
    (str(m), 1000000, 1),                # product fits, -500000 overflows
    # scale coverage: 1, 1000, 48000, 12288, 90000, 1000000 (as src and dst)
    ("0", 1, 1000000), ("0", 1000000, 1),
    ("90000", 1, 1000), ("90000", 1000, 1),
    ("12288", 1, 12288), ("12288", 12288, 1),
    ("90000", 90000, 1), ("90000", 1, 90000),
    ("48000", 48000, 48000),
    ("1024", 48000, 1000), ("-1024", 48000, 1000),
    ("33", 48000, 1000), ("-33", 48000, 1000),
    ("512", 12288, 48000), ("-512", 12288, 48000),
    ("1000000", 90000, 12288),
    # halves away from zero
    ("3", 2, 1), ("-3", 2, 1), ("5", 2, 1), ("-5", 2, 1),
    ("1", 2, 1), ("-1", 2, 1), ("1", 4, 1), ("-1", 4, 1),
    # just-fitting product, exact half
    ("4611686018427387903", 2, 1), ("-4611686018427387903", 2, 1),
    ("4611686018427387903", 2, 4), ("-4611686018427387903", 2, 4),
    # non-positive scales
    ("1", 0, 1), ("1", -48000, 1), ("1", 1, 0), ("1", 1, -1000),
]

split_rows = [
    # regression: split-int64max-3-parts (exact-sum shares)
    (str(M), 3),
    (str(m), 3),                          # Int64.min input, negative total
    (str(M), 2), (str(m), 2),
    ("2", 5), ("-2", 5),                  # parts > total (both signs)
    (str(M), 1), (str(m), 1), ("0", 1),   # single-part identity
    ("10", 3), ("-10", 3),                # negative totals
    ("0", 7),
    ("1", 2), ("-1", 2),
    ("7", 7),
    ("100", 0), ("100", -3), ("0", 0),    # non-positive parts
]

addsub_rows = [
    (str(M), "1", "add"), (str(m), "-1", "add"),
    (str(m), "1", "sub"), (str(M), "-1", "sub"),
    (str(M), "0", "add"), (str(m), "0", "sub"),
    ("0", "0", "add"), ("0", "0", "sub"),
    ("48000", "1024", "add"), ("90000", "-45000", "add"),
    ("-90000", "45000", "sub"), ("12288", "12288", "sub"),
    (str(M), str(m), "add"),              # == -1, exact
    (str(m), str(M), "sub"),              # overflow
    (str(M), str(M), "sub"),              # == 0
    (str(m), str(m), "sub"),              # == 0
    ("1", str(m), "sub"),                 # overflow
    ("-1", str(m), "sub"),                # == Int64.max, exact
    ("4611686018427387903", "4611686018427387903", "add"),  # overflow
    ("4611686018427387903", "4611686018427387904", "add"),  # == Int64.max
]

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "rescale-vectors.csv"), "w") as f:
    f.write("# P-A4 rescale vectors: v,src_scale,dst_scale,expected (value or error)\n")
    f.write("# regression: rescale-overflow-at-rounding-addition\n")
    f.write("v,src_scale,dst_scale,expected\n")
    for i, (v, s, d) in enumerate(rescale_rows):
        if i == 3:
            f.write("# regression: negative-symmetry-edge\n")
        f.write(f"{v},{s},{d},{rescale(int(v), s, d)}\n")
with open(os.path.join(OUT, "split-vectors.csv"), "w") as f:
    f.write("# P-A4 split vectors: total,parts,expected (semicolon shares or error)\n")
    f.write("# regression: split-int64max-3-parts\n")
    f.write("total,parts,expected\n")
    for t, p in split_rows:
        f.write(f"{t},{p},{split(int(t), p)}\n")
with open(os.path.join(OUT, "addsub-vectors.csv"), "w") as f:
    f.write("# P-A4 addsub vectors: a,b,op,expected (value or error)\n")
    f.write("a,b,op,expected\n")
    for a, b, op in addsub_rows:
        f.write(f"{a},{b},{op},{addsub(int(a), int(b), op)}\n")
print("vectors written:", len(rescale_rows), "rescale,", len(split_rows), "split,", len(addsub_rows), "addsub")
