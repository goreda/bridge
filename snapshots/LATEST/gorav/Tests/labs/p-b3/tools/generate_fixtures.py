#!/usr/bin/env python3
# P-B3 fixture generator and numeric assert runner.
# Deterministic: IEEE-754 double math, no wall clock, no RNG, no I/O beyond writing fixtures.
# This script is the authoritative numeric reference mirror of the Swift scalar
# implementation (Sources/HDRReference/HDRReference.swift). The matrix constants
# below are derived from published primaries by tools/derive_matrix.py; the
# derivation is reproduced here so fixtures and spec stay self-consistent.
import csv, hashlib, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FIX = os.path.join(ROOT, "fixtures")

# ---- ST 2084 (PQ) constants, SMPTE ST 2084-2014 / ITU-R BT.2100-2 ----
M1 = 2610.0 / 16384.0
M2 = 2523.0 / 4096.0 * 128.0
C1 = 3424.0 / 4096.0
C2 = 2413.0 / 4096.0 * 32.0
C3 = 2392.0 / 4096.0 * 32.0
PQ_PEAK_NITS = 10000.0

def pq_eotf(n):
    # PQ signal [0,1] -> absolute luminance nits. ST 2084 eq (inverse OETF).
    n = min(1.0, max(0.0, n))
    p = n ** (1.0 / M2)
    num = max(p - C1, 0.0)
    den = C2 - C3 * p
    return PQ_PEAK_NITS * (num / den) ** (1.0 / M1)

def pq_oetf_inv(L):
    # absolute luminance nits -> PQ signal [0,1]. ST 2084 / BT.2100.
    y = min(1.0, max(0.0, L / PQ_PEAK_NITS))
    ym1 = y ** M1
    return ((C1 + C2 * ym1) / (1.0 + C3 * ym1)) ** M2

# ---- BT.709 OETF, ITU-R BT.709-6 ----
def bt709_oetf(L):
    if L < 0.018:
        return 4.5 * L
    return 1.099 * (L ** 0.45) - 0.099

# ---- Matrix derived from published primaries (full double precision) ----
# BT.2020 primaries (ITU-R BT.2020-2): R(0.708,0.292) G(0.170,0.797) B(0.131,0.046)
# BT.709 primaries (ITU-R BT.709-6):  R(0.640,0.330) G(0.300,0.600) B(0.150,0.060)
# D65 white both: (0.3127, 0.3290)
D65 = (0.3127, 0.3290)
P2020 = ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046))
P709 = ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060))

def prim_to_rgb2xyz(prims, white):
    xs = [p[0] for p in prims]; ys = [p[1] for p in prims]
    cols = [(x / y, 1.0, (1.0 - x - y) / y) for x, y in prims]
    P = [[cols[c][r] for c in range(3)] for r in range(3)]
    w = (white[0] / white[1], 1.0, (1.0 - white[0] - white[1]) / white[1])
    det = (P[0][0]*(P[1][1]*P[2][2]-P[1][2]*P[2][1])
         - P[0][1]*(P[1][0]*P[2][2]-P[1][2]*P[2][0])
         + P[0][2]*(P[1][0]*P[2][1]-P[1][1]*P[2][0]))
    s = [0.0]*3
    for r in range(3):  # Cramer: solve P * s = w
        Q = [[P[i][j] for j in range(3)] for i in range(3)]
        for i in range(3): Q[i][r] = w[i]
        dq = (Q[0][0]*(Q[1][1]*Q[2][2]-Q[1][2]*Q[2][1])
            - Q[0][1]*(Q[1][0]*Q[2][2]-Q[1][2]*Q[2][0])
            + Q[0][2]*(Q[1][0]*Q[2][1]-Q[1][1]*Q[2][0]))
        s[r] = dq / det
    return [[P[r][c]*s[c] for c in range(3)] for r in range(3)]

def inv3(A):
    det = (A[0][0]*(A[1][1]*A[2][2]-A[1][2]*A[2][1])
         - A[0][1]*(A[1][0]*A[2][2]-A[1][2]*A[2][0])
         + A[0][2]*(A[1][0]*A[2][1]-A[1][1]*A[2][0]))
    C = [[0.0]*3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            rows = [r for r in range(3) if r != j]
            cols = [c for c in range(3) if c != i]
            minor = A[rows[0]][cols[0]]*A[rows[1]][cols[1]] - A[rows[0]][cols[1]]*A[rows[1]][cols[0]]
            C[i][j] = ((-1.0) ** (i + j)) * minor / det
    return C

def matmul(A, B):
    return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

A2020 = prim_to_rgb2xyz(P2020, D65)
A709 = prim_to_rgb2xyz(P709, D65)
M_2020_TO_709 = matmul(inv3(A709), A2020)

# ---- Tone map pipeline (mirror of the Swift scalar reference) ----
# BT.2020 luma coefficients (ITU-R BT.2100-2): 0.2627, 0.6780, 0.0593 (sum = 1.0)
LUMA2020 = (0.2627, 0.6780, 0.0593)

def tone_map(pq_rgb, source_peak, target_peak):
    if source_peak <= 0.0 or target_peak <= 0.0:
        raise ValueError("peaks must be positive")
    for v in pq_rgb:
        if not (0.0 <= v <= 1.0):
            raise ValueError("PQ input out of [0,1]")
    L = tuple(pq_eotf(v) for v in pq_rgb)                       # nits, BT.2020 linear
    Y = LUMA2020[0]*L[0] + LUMA2020[1]*L[1] + LUMA2020[2]*L[2]
    yn = Y / source_peak                                        # normalized source luminance
    yt = yn / (1.0 + yn)                                        # Reinhard (2002) tone curve
    Lt = yt * target_peak                                       # target nits
    s = (Lt / Y) if Y > 0.0 else 0.0
    Lm = (L[0]*s, L[1]*s, L[2]*s)                               # tone-mapped, BT.2020 linear
    out = []
    for r in range(3):
        c = M_2020_TO_709[r][0]*Lm[0] + M_2020_TO_709[r][1]*Lm[1] + M_2020_TO_709[r][2]*Lm[2]
        v = c / target_peak
        v = min(1.0, max(0.0, v))                               # hard clip per BT.2407-0 simple conversion
        out.append(bt709_oetf(v))
    return tuple(out)

def to8(v):
    x = int(round(min(1.0, max(0.0, v)) * 255.0))
    return min(255, max(0, x))

def f17(v):
    return "%.17g" % v

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()

def write_ppm(path, width, height, rgb8):
    # rgb8: list of rows, each row list of (r,g,b) ints, len == width
    with open(path, "wb") as f:
        f.write(("P6\n%d %d\n255\n" % (width, height)).encode("ascii"))
        for row in rgb8:
            for (r, g, b) in row:
                f.write(bytes((r, g, b)))

def main():
    os.makedirs(FIX, exist_ok=True)
    src_peak, tgt_peak = 1000.0, 1000.0  # set per fixture below
    src_peak, tgt_peak = 1000.0, 100.0

    # ---- matrix printout for spec provenance ----
    print("M_2020_TO_709 (derived from published primaries):")
    for row in M_2020_TO_709:
        print("  " + "  ".join("%.17g" % v for v in row))
    for r in range(3):
        print("  row%d sum = %.17g" % (r, sum(M_2020_TO_709[r])))

    # ---- fixture 1: pq-gray-ramp.csv ----
    ramp_nits = [0.0, 0.1, 1.0, 10.0, 100.0, 400.0, 1000.0]
    ramp_rows = []
    for nits in ramp_nits:
        code = pq_oetf_inv(nits)
        o = tone_map((code, code, code), src_peak, tgt_peak)
        ramp_rows.append((nits, code, o))
    p1 = os.path.join(FIX, "pq-gray-ramp.csv")
    with open(p1, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["input_nits", "pq_code", "out_r", "out_g", "out_b"])
        for nits, code, o in ramp_rows:
            w.writerow([f17(nits), f17(code), f17(o[0]), f17(o[1]), f17(o[2])])

    # ---- fixture 2: hdr-primary-patches.csv ----
    patches = [("red", (1000.0, 0.0, 0.0)),
               ("green", (0.0, 1000.0, 0.0)),
               ("blue", (0.0, 0.0, 1000.0)),
               ("white", (1000.0, 1000.0, 1000.0))]
    patch_rows = []
    for name, lin in patches:
        code = tuple(pq_oetf_inv(v) for v in lin)
        o = tone_map(code, src_peak, tgt_peak)
        patch_rows.append((name, lin, code, o))
    p2 = os.path.join(FIX, "hdr-primary-patches.csv")
    with open(p2, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["patch", "in_r_nits", "in_g_nits", "in_b_nits",
                    "pq_r", "pq_g", "pq_b", "out_r", "out_g", "out_b"])
        for name, lin, code, o in patch_rows:
            w.writerow([name, f17(lin[0]), f17(lin[1]), f17(lin[2]),
                        f17(code[0]), f17(code[1]), f17(code[2]),
                        f17(o[0]), f17(o[1]), f17(o[2])])

    # ---- fixture 3: gray-ramp-reference.ppm (7 cells of 64x64 -> 448x64) ----
    cell = 64
    p3 = os.path.join(FIX, "gray-ramp-reference.ppm")
    rows = []
    for y in range(cell):
        row = []
        for nits, code, o in ramp_rows:
            px = (to8(o[0]), to8(o[1]), to8(o[2]))
            row.extend([px] * cell)
        rows.append(row)
    write_ppm(p3, cell * len(ramp_rows), cell, rows)

    # ---- fixture 4: color-patches-reference.ppm (4 cells of 64x64 -> 256x64) ----
    p4 = os.path.join(FIX, "color-patches-reference.ppm")
    rows = []
    for y in range(cell):
        row = []
        for name, lin, code, o in patch_rows:
            px = (to8(o[0]), to8(o[1]), to8(o[2]))
            row.extend([px] * cell)
        rows.append(row)
    write_ppm(p4, cell * len(patch_rows), cell, rows)

    # ================= numeric asserts (the runnable evidence) =================
    fails = []

    # A1: PQ round-trip, relative error <= 1e-6 where positive.
    # Dense sweep 0.001..10000 nits plus the ramp values.
    samples = [ramp_nits[i] for i in range(len(ramp_nits))]
    dense = []
    for i in range(1001):
        # log-spaced 0.001 .. 10000
        import math
        dense.append(0.001 * (10.0 ** (7.0 * i / 1000.0)))
    max_rt = 0.0
    for L in samples + dense:
        if L > 0.0:
            L2 = pq_eotf(pq_oetf_inv(L))
            rel = abs(L2 - L) / L
            max_rt = max(max_rt, rel)
    print("A1 PQ round-trip max relative error (1008 samples): %.3e" % max_rt)
    if not (max_rt <= 1e-6):
        fails.append("A1 round-trip %.3e > 1e-6" % max_rt)

    # A2: neutral ramp outputs neutral within 1e-6, finite, monotonic.
    max_neutral = 0.0
    prev = -1.0
    mono = True
    finite = True
    import math as _m
    for nits, code, o in ramp_rows:
        spread = max(o) - min(o)
        max_neutral = max(max_neutral, spread)
        for v in o:
            if not _m.isfinite(v):
                finite = False
        if o[0] < prev:
            mono = False
        prev = o[0]
    print("A2 neutral max channel spread: %.3e, finite=%s, monotonic=%s" % (max_neutral, finite, mono))
    if not (max_neutral <= 1e-6 and finite and mono):
        fails.append("A2 neutrality/finite/monotonic")

    # A3: black maps black (exact zero).
    o_black = tone_map((0.0, 0.0, 0.0), src_peak, tgt_peak)
    print("A3 black -> (%r, %r, %r)" % o_black)
    if o_black != (0.0, 0.0, 0.0):
        fails.append("A3 black not exact zero")

    # A4: all fixture outputs within [0,1].
    in_range = True
    for nits, code, o in ramp_rows:
        for v in o:
            if not (0.0 <= v <= 1.0):
                in_range = False
    for name, lin, code, o in patch_rows:
        for v in o:
            if not (0.0 <= v <= 1.0):
                in_range = False
    print("A4 all fixture outputs in [0,1]: %s" % in_range)
    if not in_range:
        fails.append("A4 range")

    # A5: PPM pixel values equal 8-bit quantization of CSV oracle (self-consistency).
    print("A5 reference images are generated artifacts (8-bit PPM from same pipeline), not visual validation")

    # ---- hashes ----
    print("\nsha256:")
    paths = [p1, p2, p3, p4]
    for p in paths:
        print("  %s  %s" % (sha256(p), os.path.relpath(p, ROOT)))

    if fails:
        print("\nFAIL: " + "; ".join(fails))
        sys.exit(1)
    print("\nALL NUMERIC ASSERTS PASS (A1-A4)")

if __name__ == "__main__":
    main()
