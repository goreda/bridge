#!/usr/bin/env python3
"""Conservative vector edge table. Measurement, not production certification.

Uses all contours, decomposes components and TrueType implied points via BasePen.
No raster sampling, Unicode category overrides, foreign pool or silent fallback.
OPEN/serif/terminal semantics are not inferred: ambiguous sides are unclassified.
"""
import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.misc.bezierTools import calcCubicBounds, calcQuadraticBounds

HEADER = ['glyph', 'codepoint', 'category', 'kind', 'ncomp', 'class_left', 'class_right',
          'raw_left', 'raw_right', 'reason_left', 'reason_right', 'W', 'H']


class Segments(BasePen):
    def __init__(self, glyph_set):
        super().__init__(glyph_set)
        self.segments = []
        self.start = None
        self.closed = 0

    def _moveTo(self, p):
        self.start = p

    def _lineTo(self, p):
        self.segments.append(('line', (self._getCurrentPoint(), p)))

    def _curveToOne(self, a, b, c):
        self.segments.append(('cubic', (self._getCurrentPoint(), a, b, c)))

    def _qCurveToOne(self, a, b):
        self.segments.append(('quad', (self._getCurrentPoint(), a, b)))

    def _closePath(self):
        p = self._getCurrentPoint()
        if p != self.start:
            self.segments.append(('line', (p, self.start)))
        self.closed += 1

    def _endPath(self):
        raise ValueError('open contour: no class assignment')


def side_class(segments, extreme, side, min_flat):
    # Numeric comparison only, not a visual/shape tuning parameter.
    near = lambda x: math.isclose(x, extreme, rel_tol=0, abs_tol=1e-7)
    flats = []
    curves = False
    oblique = False
    for kind, pts in segments:
        if kind == 'line':
            a, b = pts
            if near(a[0]) and near(b[0]) and a[1] != b[1]:
                flats.append(abs(b[1] - a[1]))
            elif a[0] != b[0] and (near(a[0]) or near(b[0])):
                oblique = True
        else:
            bounds = (calcCubicBounds(*pts) if kind == 'cubic'
                      else calcQuadraticBounds(*pts))
            edge = bounds[0 if side == 'left' else 2]
            # Interior extrema or endpoint extrema with a vertical tangent.
            # Merely ending at an extreme is insufficient.
            interior = not near(pts[0][0]) and not near(pts[-1][0])
            smooth_start = (near(pts[0][0]) and near(pts[1][0])
                            and pts[0][1] != pts[1][1])
            smooth_end = (near(pts[-1][0]) and near(pts[-2][0])
                          and pts[-1][1] != pts[-2][1])
            if near(edge) and any(not near(p[0]) for p in pts) and (interior or smooth_start or smooth_end):
                curves = True
    if flats and max(flats) >= min_flat and not curves:
        return 'flat_stem', 'vertical extreme segment meets explicit minimum'
    if curves and not flats and not oblique:
        return 'round', 'Bezier x-extremum with vertical tangent'
    return 'unclassified', 'ambiguous or unsupported edge semantics'


def measure(font, min_flat_em):
    if not math.isfinite(min_flat_em) or not 0 < min_flat_em <= 1:
        raise ValueError('min-flat-em must be finite in (0,1]')
    gs = font.getGlyphSet()
    upm = font['head'].unitsPerEm
    if upm <= 0:
        raise ValueError('invalid unitsPerEm')
    rows = []
    for name in font.getGlyphOrder():
        pen = Segments(gs)
        gs[name].draw(pen)
        bounds_pen = BoundsPen(gs)
        gs[name].draw(bounds_pen)
        if bounds_pen.bounds is None:
            left = right = 'empty'
            lr = rr = 'no outline'
            w = h = 0
        else:
            x0, y0, x1, y1 = bounds_pen.bounds
            if not all(math.isfinite(v) for v in (x0, y0, x1, y1)):
                raise ValueError('nonfinite geometry: ' + name)
            w, h = x1 - x0, y1 - y0
            left, lr = side_class(pen.segments, x0, 'left', min_flat_em * upm)
            right, rr = side_class(pen.segments, x1, 'right', min_flat_em * upm)
        if any(c in name for c in '\t\r\n') or not name:
            raise ValueError('invalid glyph identifier')
        rows.append([name, '', '', 'vector', str(pen.closed), left, right,
                     left, right, lr, rr, format(w, '.17g'), format(h, '.17g')])
    if len({r[0] for r in rows}) != len(rows):
        raise ValueError('duplicate glyph identifiers')
    return rows


def table_bytes(rows):
    out = io.StringIO(newline='')
    writer = csv.writer(out, delimiter='\t', lineterminator='\n')
    writer.writerow(HEADER)
    writer.writerows(rows)
    return out.getvalue().encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('font', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--min-flat-em', type=float, required=True,
                        help='explicit provisional threshold, e.g. draft 0.30; not ratified')
    args = parser.parse_args()
    # Parse/hash the same input bytes, no path re-read for provenance.
    source = args.font.read_bytes()
    with TTFont(io.BytesIO(source), lazy=False) as font:
        rows = measure(font, args.min_flat_em)
    payload = table_bytes(rows)
    # Exclusive publication: no overwrite of another table.
    with args.output.open('xb') as out:
        out.write(payload)
    counts = {}
    for row in rows:
        for c in row[5:7]:
            counts[c] = counts.get(c, 0) + 1
    print(json.dumps({'schema': 'auto-sb-edge-table-v1', 'font_sha256': hashlib.sha256(source).hexdigest(),
                      'table_sha256': hashlib.sha256(payload).hexdigest(), 'glyph_rows': len(rows),
                      'side_counts': counts, 'min_flat_em': args.min_flat_em,
                      'production_accepted': False}, sort_keys=True))


if __name__ == '__main__':
    main()
