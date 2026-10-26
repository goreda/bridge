#!/usr/bin/env python3
"""Synthetic tests for extract_quadratic: two explicit refusals and a positive control."""
import io, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_quadratic as ex

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPM = 1000


def base_builder():
    fb = FontBuilder(UPM, isTTF=True)
    order = ['.notdef', 'A', 'comp']
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({0x41: 'A'})
    fb.setupGlyf({})
    fb.setupHorizontalMetrics({n: (500, 0) for n in order})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupOS2()
    fb.setupNameTable({'familyName': 'synthetic', 'styleName': 'Regular'})
    fb.setupPost()
    fb.setupMaxp()
    return fb


def simple_square(pen, dx=0):
    pen.moveTo((dx + 0, 0))
    pen.lineTo((dx + 200, 0))
    pen.lineTo((dx + 200, 200))
    pen.lineTo((dx + 0, 200))
    pen.closePath()


def build_all_off_curve_font():
    """Glyph 'A' with a single all-off-curve (superellipse) contour."""
    fb = base_builder()
    glyf = {}
    pen = TTGlyphPen(None)  # .notdef empty
    glyf['.notdef'] = pen.glyph()
    pen = TTGlyphPen(None)
    pen.qCurveTo((0, 100), (100, 200), (200, 100), (100, 0), None)
    pen.closePath()
    glyf['A'] = pen.glyph()
    pen = TTGlyphPen(None)
    simple_square(pen, 300)
    glyf['comp'] = pen.glyph()
    fb.setupGlyf(glyf)
    buf = io.BytesIO()
    fb.save(buf)
    return buf.getvalue()


def build_anchor_matched_font():
    """Composite 'comp' whose component is positioned by anchor matching
    (component flags without ARGS_ARE_XY_VALUES)."""
    fb = base_builder()
    glyf = {}
    pen = TTGlyphPen(None)
    glyf['.notdef'] = pen.glyph()
    pen = TTGlyphPen(None)
    simple_square(pen)
    glyf['A'] = pen.glyph()
    pen = TTGlyphPen({'.notdef': glyf['.notdef'], 'A': glyf['A']})
    pen.addComponent('A', (1, 0, 0, 1, 500, 0))  # component 0: parent points
    pen.addComponent('A', (1, 0, 0, 1, 0, 0))    # component 1 -> anchor-matched
    comp_glyph = pen.glyph()
    glyf['comp'] = comp_glyph
    fb.setupGlyf(glyf)
    # Flip component 1 to anchor-point matching (firstPt/secondPt args):
    # its point 1 anchors to parent accumulated point 1 (from component 0).
    g = fb.font['glyf']['comp']
    comp = g.components[1]
    del comp.x, comp.y
    comp.firstPt = 1
    comp.secondPt = 1
    buf = io.BytesIO()
    fb.save(buf)
    return buf.getvalue()


class RefusalTests(unittest.TestCase):
    def _extract_records(self, data):
        with tempfile.NamedTemporaryFile(suffix='.ttf', delete=False) as f:
            f.write(data)
            path = f.name
        try:
            lines, upm, inst, counts = ex.extract(path)
        finally:
            os.unlink(path)
        import json as _json
        return [_json.loads(l) for l in lines], counts

    def test_all_off_curve_contour_refused(self):
        recs, counts = self._extract_records(build_all_off_curve_font())
        a = next(r for r in recs if r['glyph'] == 'A')
        self.assertEqual(a['contours'], [])
        self.assertEqual(a['refused']['reason'], 'all_off_curve_contour')
        self.assertEqual(counts.get('all_off_curve_contour'), 1)

    def test_anchor_matched_component_refused(self):
        recs, counts = self._extract_records(build_anchor_matched_font())
        comp = next(r for r in recs if r['glyph'] == 'comp')
        self.assertEqual(comp['contours'], [])
        self.assertEqual(comp['refused']['reason'], 'anchor_matched_component')
        self.assertEqual(comp['refused']['anchor_points'], [[1, 1]])
        self.assertEqual(counts.get('anchor_matched_component'), 1)

    def test_normal_composite_xy_offset_extracts(self):
        """Positive control: xy-offset composite extracts with translated points."""
        fb = base_builder()
        glyf = {}
        pen = TTGlyphPen(None)
        glyf['.notdef'] = pen.glyph()
        pen = TTGlyphPen(None)
        simple_square(pen)
        glyf['A'] = pen.glyph()
        pen = TTGlyphPen({'.notdef': None, 'A': None, 'comp': None})
        pen.addComponent('A', (1, 0, 0, 1, 300, 40))
        glyf['comp'] = pen.glyph()
        fb.setupGlyf(glyf)
        buf = io.BytesIO(); fb.save(buf)
        recs, counts = self._extract_records(buf.getvalue())
        comp = next(r for r in recs if r['glyph'] == 'comp')
        self.assertNotIn('refused', comp)
        self.assertEqual(counts, {})
        xs = sorted(p[0] for c in comp['contours'] for p in c)
        self.assertEqual((min(xs), max(xs)), (300, 500))


if __name__ == '__main__':
    unittest.main()
