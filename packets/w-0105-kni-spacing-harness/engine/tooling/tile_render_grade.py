#!/usr/bin/env python3
"""tile-vs-render grading gate (engine/tooling/tile_render_grade.py).

After a font is built, grade every glyph against its source tile:
per-glyph shift dx/dy (font units, y up) and overlap IoU at tile scale.
Verdicts per glyph: BLOCK fails the gate (exit 1), WARN is listed
before delivery but passes. Every manifest glyph gets a typed TSV row;
unverifiable rows (missing tile, missing outline, empty mask) are typed
and count as BLOCK - no silent drops.

Dependencies: fontTools and Pillow as pinned in
tooling/delivery/requirements-ci.txt, plus numpy (already used across
engine tooling). Python 3, no engine build required.

Thresholds are DERIVED FROM THE FONT ITSELF: the tile->font transform
(K_X, K_Y, OX, OY) is solved as the population median over the font's own
glyphs, and per-metric flag limits use the Hampel rule on the font's own
residual population: median +/- 3 * 1.4826 * MAD.
DECLARED CONVENTIONS (provenance): the Hampel identifier, standard
robust-outlier convention (Hampel 1974); the multiplier 3 is the
conventional Hampel gate. Frame band: each tile's candidate band is
measured per tile by the engine's own measure_frame_band rule
(continuity floor 1/2 of the outermost line's ink fraction, single
contiguous run); the applied band is then the per-side POPULATION
MINIMUM across the tile set - a frame is uniform across the set, so
anything beyond the set-consistent band is letterform evidence (the
engine rule's stated intent), never frame.
"""
import argparse, os, re, sys
import numpy as np
from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen

def measure_frame_band(a):
    # Port of engine capture_dispatch::measure_frame_band (same rule).
    h, w = a.shape
    def frac_row(y): return a[y].mean()
    def frac_col(x): return a[:, x].mean()
    def nruns(r):
        if r.size == 0: return 0
        return int(r[0]) + int((r[1:] & ~r[:-1]).sum())
    def runs_row(y): return nruns(a[y])
    def runs_col(x): return nruns(a[:, x])
    def band(frac, runs, limit):
        f0 = frac(0)
        if f0 < 0.5 or runs(0) != 1: return 0
        floor = 0.5 * f0; b = 1
        while b < limit and frac(b) >= floor and runs(b) == 1: b += 1
        return b
    t = band(frac_row, runs_row, max(h // 2, 1))
    b = band(lambda y: frac_row(h - 1 - y), lambda y: runs_row(h - 1 - y), max(h // 2, 1))
    l = band(frac_col, runs_col, max(w // 2, 1))
    r = band(lambda x: frac_col(w - 1 - x), lambda x: runs_col(w - 1 - x), max(w // 2, 1))
    return t, b, l, r

def tile_mask(path, band=None):
    a = np.asarray(Image.open(path).convert("L")) < 128
    t, b, l, r = band if band is not None else measure_frame_band(a)
    h, w = a.shape
    m = a.copy()
    if t: m[:t] = False
    if b: m[h - b:] = False
    if l: m[:, :l] = False
    if r: m[:, w - r:] = False
    return m, (t, b, l, r)

def glyph_polygons(gs, gname):
    pen = RecordingPen(); gs[gname].draw(pen)
    contours = []; cur = []
    for op, args in pen.value:
        if op == "moveTo":
            if cur: contours.append(cur)
            cur = [tuple(map(float, args[0]))]
        elif op == "lineTo": cur.append(tuple(map(float, args[0])))
        elif op == "curveTo":
            p0 = cur[-1]; c1, c2, e = [tuple(map(float, a)) for a in args]
            for t in np.linspace(1/16, 1.0, 16):
                mt = 1 - t
                cur.append((mt**3*p0[0] + 3*mt*mt*t*c1[0] + 3*mt*t*t*c2[0] + t**3*e[0],
                            mt**3*p0[1] + 3*mt*mt*t*c1[1] + 3*mt*t*t*c2[1] + t**3*e[1]))
        elif op in ("closePath", "endPath"):
            if cur: contours.append(cur); cur = []
    if cur: contours.append(cur)
    return contours

def signed_area(poly):
    return sum(x0*y1 - x1*y0 for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1])) / 2

def raster(gs, gname, W, H, KX, KY, OX, OY):
    acc = np.zeros((H, W), dtype=np.int16)
    for poly in glyph_polygons(gs, gname):
        if len(poly) < 3: continue
        sgn = 1 if signed_area(poly) > 0 else -1
        layer = Image.new("L", (W, H), 0)
        px = [((x - OX) / KX, (OY - y) / KY) for x, y in poly]
        ImageDraw.Draw(layer).polygon(px, fill=1, outline=1)
        acc += sgn * np.asarray(layer, dtype=np.int16)
    return acc != 0

def hampel(v):
    med = np.median(v); mad = np.median(np.abs(v - med))
    return med, 1.4826 * mad

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out-tsv")
    a = ap.parse_args()
    mdir = os.path.dirname(os.path.abspath(a.manifest))
    glyphs = []
    for line in open(a.manifest):
        m = re.match(r"glyph\s+(0x[0-9A-Fa-f]+)\s+(\S+)\s+(\S+)", line.strip())
        if m:
            path = m.group(3)
            if not os.path.isabs(path): path = os.path.join(mdir, path)
            glyphs.append((int(m.group(1), 16), m.group(2), path))
    if not glyphs: print("grade: no glyph lines in manifest", file=sys.stderr); return 2
    font = TTFont(a.font)
    cmap = font.getBestCmap(); gs = font.getGlyphSet()
    # pass 1: bboxes for transform solve
    # population frame band: per-side minimum of per-tile engine-rule bands
    cand = []
    raw = {}
    for cp, name, path in glyphs:
        if not os.path.exists(path): continue
        arr = np.asarray(Image.open(path).convert("L")) < 128
        bd = measure_frame_band(arr)
        raw[cp] = bd
        cand.append(bd)
    pop_band = tuple(min(c[i] for c in cand) for i in range(4)) if cand else (0, 0, 0, 0)
    overeat = [raw[cp] for cp in raw if raw[cp] != pop_band]
    skips = []
    recs = []
    for cp, name, path in glyphs:
        if cp not in cmap:
            skips.append((cp, name, "NO_GLYPH: codepoint absent from font cmap")); continue
        if not os.path.exists(path):
            skips.append((cp, name, "NO_TILE: tile path missing")); continue
        tm, band = tile_mask(path, pop_band)
        ys, xs = np.nonzero(tm)
        if len(xs) == 0:
            skips.append((cp, name, "EMPTY_TILE: no ink after frame strip")); continue
        from fontTools.pens.boundsPen import BoundsPen
        pen = BoundsPen(gs)
        try: gs[cmap[cp]].draw(pen)
        except Exception:
            skips.append((cp, name, "NO_OUTLINE: glyph draw failed")); continue
        if pen.bounds is None:
            skips.append((cp, name, "NO_OUTLINE: glyph has no bounds")); continue
        recs.append((cp, cmap[cp], path, tm, pen.bounds))
    if not recs: print("grade: no comparable glyphs", file=sys.stderr); return 2
    H, W = recs[0][3].shape
    kxs, kys, oxs, oys = [], [], [], []
    for cp, gn, path, tm, fb in recs:
        ys, xs = np.nonzero(tm)
        tw, th = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
        fw, fh = fb[2] - fb[0], fb[3] - fb[1]
        if tw > 0 and fh != 0 and fw != 0 and th > 0:
            kxs.append(fw / tw); kys.append(fh / th)
    KX = float(np.median(kxs)); KY = float(np.median(kys))
    for cp, gn, path, tm, fb in recs:
        ys, xs = np.nonzero(tm)
        oxs.append(fb[0] - KX * xs.min()); oys.append(fb[3] + KY * ys.min())
    OX = float(np.median(oxs)); OY = float(np.median(oys))
    # pass 2: per-glyph grade
    rows = []
    for cp, gn, path, tm, fb in recs:
        ys, xs = np.nonzero(tm)
        ex0 = KX * xs.min() + OX; ey1 = -KY * ys.min() + OY
        dx = fb[0] - ex0; dy = fb[3] - ey1
        fm = raster(gs, gn, W, H, KX, KY, OX, OY)
        inter = int(np.logical_and(tm, fm).sum()); union = int(np.logical_or(tm, fm).sum())
        iou = inter / union if union else 1.0
        tcx, tcy = xs.mean(), ys.mean()
        fys, fxs = np.nonzero(fm)
        cdx = (fxs.mean() - tcx) * KX if len(fxs) else 0.0
        cdy = -(fys.mean() - tcy) * KY if len(fys) else 0.0
        rows.append((cp, gn, dx, dy, cdx, cdy, iou))
    medx, limx = hampel([r[4] for r in rows])
    medy, limy = hampel([r[5] for r in rows])
    medi, limi = hampel([r[6] for r in rows])
    # Two tiers, both Hampel gates on the font's own population:
    #  BLOCK - shape no longer overlaps its tile: IoU below
    #    median - 3 robust-sigmas. This is the shift defect class
    #    (a glyph placed off its tile loses overlap; measured IoU
    #    0.00-0.26 on the defective Paul New export). Skipped
    #    (unverifiable) manifest rows are also BLOCK.
    #  WARN - placement outlier with overlap intact: centroid shift
    #    beyond 3 robust-sigmas from the population median. Listed
    #    before delivery, does not fail the gate.
    #  When the population is exact (sigma 0) any deviation flags.
    def verdict(r):
        fi = (medi - r[6]) > 3 * limi if limi > 0 else r[6] != medi
        if fi: return "BLOCK"
        fx = abs(r[4] - medx) > 3 * limx if limx > 0 else r[4] != medx
        fy = abs(r[5] - medy) > 3 * limy if limy > 0 else r[5] != medy
        return "WARN" if (fx or fy) else "ok"
    out = ["cp\tglyph\tdx_bbox\tdy_bbox\tdx_centroid\tdy_centroid\tiou\tverdict"]
    blocked, warned = [], []
    for r in sorted(rows):
        v = verdict(r)
        if v == "BLOCK": blocked.append(r[1])
        elif v == "WARN": warned.append(r[1])
        out.append(f"0x{r[0]:04X}\t{r[1]}\t{r[2]:.2f}\t{r[3]:.2f}\t{r[4]:.2f}\t{r[5]:.2f}\t{r[6]:.4f}\t{v}")
    for cp, name, why in skips:
        blocked.append(name)
        out.append(f"0x{cp:04X}\t{name}\t\t\t\t\t\tBLOCK ({why})")
    tsv = "\n".join(out) + "\n"
    if a.out_tsv:
        open(a.out_tsv, "w").write(tsv)
    print(f"grade: {len(rows)} glyphs; transform K_X={KX:.6f} K_Y={KY:.6f} OX={OX:.2f} OY={OY:.2f} (font-derived medians)")
    print(f"grade: frame band applied={pop_band} (population minimum of engine-rule bands; {len(overeat)} tiles had larger candidate bands)")
    print(f"grade: robust sigma dx={limx:.3f} dy={limy:.3f} iou={limi:.4f}; BLOCK {len(blocked)} WARN {len(warned)}")
    if warned:
        print("WARN (listed, gate passes): " + " ".join(warned))
    if blocked:
        print("BLOCK (gate fails): " + " ".join(blocked))
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
