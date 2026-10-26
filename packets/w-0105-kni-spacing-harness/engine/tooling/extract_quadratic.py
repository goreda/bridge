#!/usr/bin/env python3
"""TrueType quadratic-contour extractor.

Captures glyf point streams as-is: on/off-curve flags preserved, composites
decomposed with their transforms applied (points remain TrueType quadratic;
no cubic conversion, no flattening, implied on-curve points NOT materialized
- the consumer applies the TrueType midpoint rule). Variable fonts are
instantiated at wght=400 before reading.

Output per font: JSONL, one line per glyph, in glyph order:
{"glyph": name, "gid": int, "advance": int, "contours": [[[x, y, on], ...], ...]}
Coordinates in font units; advance from hmtx; upm returned to the caller.

Explicit per-glyph refusals (typed, counted, never silent): the glyph is
emitted with empty contours and a "refused" object {"reason": ..., ...}.
Reasons:
- "all_off_curve_contour": fontTools emits qCurveTo(..., None) with no
  preceding moveTo for a contour with no on-curve point.
- "anchor_matched_component": a composite component positioned by anchor-
  point matching (detected via the decompiled `firstPt`/`secondPt`
  attributes; fontTools strips the raw flag bits on load and its
  getComponentInfo() would fail on such components). The offending
  (firstPt, secondPt) pairs are recorded.
- "cubic_segment": a cubic segment in a TrueType outline (kept from v1).
- "composite_recursion_depth": deeper than 32.
Real anchor resolution (parent/child anchor-point delta after transforms)
is a separate, tested follow-up version - not implemented here.
"""
import sys, json, hashlib
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.basePen import AbstractPen
from fontTools.pens.transformPen import TransformPen



class Refused(Exception):
    """Per-glyph extraction refusal with a machine-readable reason."""
    def __init__(self, reason, detail=None):
        super().__init__(reason if detail is None else f'{reason}: {detail}')
        self.reason = reason
        self.detail = detail


class QuadraticCapturePen(AbstractPen):
    """Raw glyf point capture: qCurveTo recorded without cubic decomposition;
    implied on-curve points are NOT materialized. Composites arrive already
    transformed via the glyph set's TransformPen."""
    def __init__(self, glyphSet, _depth=0):
        self._gs = glyphSet
        self._depth = _depth
        self.contours = []
        self._cur = None
    def addComponent(self, glyphName, transformation):
        if self._depth > 32:
            raise Refused('composite_recursion_depth')
        tp = TransformPen(self, transformation)
        self._gs[glyphName].draw(tp)
    def moveTo(self, p):
        self._cur = [[p[0], p[1], 1]]
        self.contours.append(self._cur)
    def lineTo(self, p):
        self._cur.append([p[0], p[1], 1])
    def qCurveTo(self, *points):
        if self._cur is None:
            raise Refused('all_off_curve_contour',
                          'qCurveTo with None terminator and no preceding moveTo')
        for p in points[:-1]:
            self._cur.append([p[0], p[1], 0])
        if points[-1] is not None:
            self._cur.append([points[-1][0], points[-1][1], 1])
    def curveTo(self, *points):
        raise Refused('cubic_segment')
    def closePath(self):
        pass
    def endPath(self):
        pass


def anchor_matched_components(font, name):
    """Return (firstPt, secondPt) pairs of anchor-point-matched components.

    fontTools' decompile strips the ARG_1_AND_2_ARE_WORDS / ARGS_ARE_XY_VALUES
    flag bits and instead exposes anchor-matched components via `firstPt` /
    `secondPt` attributes (xy-offset components get `x` / `y`). Presence of
    `firstPt` is therefore the reliable post-load discriminator."""
    glyf = font['glyf']
    glyph = glyf[name]
    if not glyph.isComposite():
        return []
    glyph.expand(glyf)
    return [(c.firstPt, c.secondPt) for c in glyph.components if hasattr(c, 'firstPt')]


def extract(path):
    font = TTFont(path)
    inst = 'fvar' in font
    if inst:
        font = instantiateVariableFont(font, {'wght': 400})
    if 'glyf' not in font:
        raise ValueError('not a TrueType-outline font')
    gs = font.getGlyphSet()
    hmtx = font['hmtx']
    upm = font['head'].unitsPerEm
    lines = []
    refused_counts = {}
    for gid, name in enumerate(font.getGlyphOrder()):
        rec = {'glyph': name, 'gid': gid, 'advance': round(hmtx[name][0])}
        bad_flags = anchor_matched_components(font, name)
        if bad_flags:
            rec['contours'] = []
            rec['refused'] = {'reason': 'anchor_matched_component',
                              'anchor_points': [list(p) for p in bad_flags]}
        else:
            pen = QuadraticCapturePen(gs)
            try:
                gs[name].draw(pen)
                rec['contours'] = pen.contours
            except Refused as r:
                rec['contours'] = []
                rec['refused'] = {'reason': r.reason}
                if r.detail:
                    rec['refused']['detail'] = r.detail
        if 'refused' in rec:
            refused_counts[rec['refused']['reason']] = refused_counts.get(rec['refused']['reason'], 0) + 1
        lines.append(json.dumps(rec, separators=(',', ':'), sort_keys=True))
    return lines, upm, inst, refused_counts


def main():
    path, out = sys.argv[1], sys.argv[2]
    lines, upm, inst, refused_counts = extract(path)
    body = '\n'.join(lines) + '\n'
    with open(out, 'w') as f:
        f.write(body)
    npts = sum(len(c) for l in lines for c in json.loads(l)['contours'])
    refused = sum(refused_counts.values())
    print(f"glyphs={len(lines)} points={npts} upm={upm} instantiated={'wght400' if inst else 'static'} "
          f"refused={refused} refused_by_reason={json.dumps(refused_counts, sort_keys=True)} "
          f"sha256={hashlib.sha256(body.encode()).hexdigest()}")


if __name__ == '__main__':
    main()
