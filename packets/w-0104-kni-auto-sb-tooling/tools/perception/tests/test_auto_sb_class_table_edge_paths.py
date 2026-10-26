"""Card 20261024-363-kni: tests for currently untested paths of the auto-sb
class table generator. No classification or threshold changes: every expected
class below follows the semantics already documented in AUTO-SB-CLASS-TABLE.md
and asserted by the original nine tests."""
import contextlib
import importlib.util
import io
import math
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTLibError

spec = importlib.util.spec_from_file_location('table', Path(__file__).parents[1] / 'auto_sb_class_table.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def rect_glyph(x0=0, y0=0, x1=200, y1=600):
    pen = TTGlyphPen(None)
    pen.moveTo((x0, y0)); pen.lineTo((x1, y0)); pen.lineTo((x1, y1)); pen.lineTo((x0, y1)); pen.closePath()
    return pen.glyph()


def font_with(glyphs, upm=1000, cmap=None):
    fb = FontBuilder(upm, isTTF=True)
    fb.setupGlyphOrder(list(glyphs))
    fb.setupCharacterMap(cmap or {})
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({g: (500, 0) for g in glyphs})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({'familyName': 'Fixture', 'styleName': 'Regular'})
    fb.setupOS2(); fb.setupPost(); fb.setupMaxp()
    return fb.font


def empty_font(upm=1000):
    return font_with({'.notdef': TTGlyphPen(None).glyph()}, upm)


class TestEmptyRows(unittest.TestCase):
    def test_empty_row_full_fields(self):
        # An outline-less glyph: empty class on both sides, explicit reason,
        # zero contours and zero width/height - never a geometry class.
        rows = {r[0]: r for r in m.measure(empty_font(), .3)}
        r = rows['.notdef']
        self.assertEqual(r[5:7], ['empty', 'empty'])
        self.assertEqual(r[9:11], ['no outline', 'no outline'])
        self.assertEqual(r[4], '0')
        self.assertEqual(r[11:13], ['0', '0'])

    def test_empty_not_silently_promoted(self):
        # Unclassified and empty are distinct tokens; an empty glyph must not
        # pick up flat/round/unclassified geometry semantics.
        rows = {r[0]: r for r in m.measure(empty_font(), .3)}
        self.assertNotIn(rows['.notdef'][5], ('flat_stem', 'round', 'unclassified'))


class TestFlatRows(unittest.TestCase):
    def test_flat_exactly_at_threshold_classifies(self):
        # Boundary is inclusive (>=): a segment exactly at the minimum counts.
        seg = [('line', ((0, 0), (0, 300)))]
        self.assertEqual(m.side_class(seg, 0, 'left', 300)[0], 'flat_stem')
        seg = [('line', ((0, 0), (0, 299)))]
        self.assertEqual(m.side_class(seg, 0, 'left', 300)[0], 'unclassified')

    def test_flat_reason_and_longest_segment_wins(self):
        segs = [('line', ((0, 0), (0, 200))), ('line', ((0, 200), (0, 700)))]
        cls, reason = m.side_class(segs, 0, 'left', 300)
        self.assertEqual(cls, 'flat_stem')
        self.assertEqual(reason, 'vertical extreme segment meets explicit minimum')

    def test_flat_suppressed_by_competing_curve(self):
        # A qualifying flat plus a curve extremum at the same side: neither
        # flat_stem (curve competes) nor round (flat competes); stays unclassified.
        curve = ('cubic', ((100, 0), (-100, 0), (-100, 600), (100, 600)))
        xmin = m.calcCubicBounds(*curve[1])[0]
        segs = [curve, ('line', ((xmin, 100), (xmin, 500)))]
        self.assertEqual(m.side_class(segs, xmin, 'left', 300)[0], 'unclassified')

    def test_zero_length_line_at_extreme_not_flat(self):
        segs = [('line', ((0, 100), (0, 100)))]
        self.assertEqual(m.side_class(segs, 0, 'left', 300)[0], 'unclassified')

    def test_flat_left_round_right_mixed_sides(self):
        # D-shaped glyph: vertical left stem, curved right bowl. Each side is
        # classified independently.
        pen = TTGlyphPen(None)
        pen.moveTo((0, 0)); pen.lineTo((300, 0))
        pen.qCurveTo((450, 300), (300, 600))
        pen.lineTo((0, 600)); pen.closePath()
        rows = {r[0]: r for r in m.measure(font_with({'.notdef': TTGlyphPen(None).glyph(), 'd': pen.glyph()}), .3)}
        self.assertEqual(rows['d'][5:7], ['flat_stem', 'round'])
        self.assertEqual(rows['d'][9], 'vertical extreme segment meets explicit minimum')
        self.assertEqual(rows['d'][10], 'Bezier x-extremum with vertical tangent')


class TestRoundRows(unittest.TestCase):
    def test_endpoint_extremum_without_vertical_tangent_not_round(self):
        # Documented semantics: merely ending at an extreme is insufficient.
        curve = ('cubic', ((100, 0), (0, 100), (50, 200), (0, 300)))
        xmin = m.calcCubicBounds(*curve[1])[0]
        self.assertTrue(math.isclose(xmin, 0.0, rel_tol=0, abs_tol=1e-7))
        self.assertEqual(m.side_class([curve], xmin, 'left', 300)[0], 'unclassified')

    def test_endpoint_extremum_with_vertical_tangent_is_round(self):
        curve = ('cubic', ((100, 0), (20, 100), (0, 200), (0, 300)))
        xmin = m.calcCubicBounds(*curve[1])[0]
        self.assertTrue(math.isclose(xmin, 0.0, rel_tol=0, abs_tol=1e-7))
        self.assertEqual(m.side_class([curve], xmin, 'left', 300)[0], 'round')

    def test_round_suppressed_by_oblique_line(self):
        curve = ('cubic', ((100, 0), (-100, 0), (-100, 600), (100, 600)))
        xmin = m.calcCubicBounds(*curve[1])[0]
        segs = [curve, ('line', ((xmin, 0), (xmin + 100, 600)))]
        self.assertEqual(m.side_class(segs, xmin, 'left', 300)[0], 'unclassified')

    def test_curve_entirely_at_extreme_not_round(self):
        # A degenerate curve with every point at the extreme carries no
        # interior geometry; it must not classify as round.
        curve = ('cubic', ((0, 0), (0, 100), (0, 200), (0, 300)))
        self.assertEqual(m.side_class([curve], 0, 'left', 300)[0], 'unclassified')


class TestMalformedInputs(unittest.TestCase):
    def test_invalid_glyph_identifier_refused(self):
        f = font_with({'.notdef': TTGlyphPen(None).glyph(), 'bad\tname': rect_glyph()})
        with self.assertRaises(ValueError):
            m.measure(f, .3)

    def test_duplicate_glyph_identifiers_refused(self):
        f = font_with({'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph()})
        f.setGlyphOrder(['.notdef', 'stem', 'stem'])
        with self.assertRaises(ValueError):
            m.measure(f, .3)

    def test_open_contour_refused_through_measure(self):
        # Any source that draws an open contour is refused by measure instead
        # of being silently closed. (fontTools' own CFF replay closes contours,
        # so this uses a minimal open-contour glyph source.)
        class OpenGlyph:
            def draw(self, pen):
                pen.moveTo((0, 0)); pen.lineTo((100, 0)); pen.lineTo((100, 100)); pen.endPath()

        class OpenGlyphSet(dict):
            def __getitem__(self, name):
                return OpenGlyph()

        class OpenFont:
            def getGlyphSet(self):
                return OpenGlyphSet()

            def getGlyphOrder(self):
                return ['open']

            def __getitem__(self, tag):
                assert tag == 'head'
                return type('Head', (), {'unitsPerEm': 1000})()

        with self.assertRaises(ValueError):
            m.measure(OpenFont(), .3)

    def test_non_font_bytes_refused(self):
        with tempfile.TemporaryDirectory() as d:
            bad = Path(d) / 'not-a-font.bin'
            bad.write_bytes(b'this is not a font')
            out = Path(d) / 't.tsv'
            argv = ['auto_sb_class_table.py', str(bad), str(out), '--min-flat-em', '0.3']
            with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(TTLibError):
                    m.main()
            self.assertFalse(out.exists())

    def test_existing_output_never_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            fpath = Path(d) / 'f.ttf'
            font_with({'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph()}).save(fpath)
            out = Path(d) / 't.tsv'
            argv = ['auto_sb_class_table.py', str(fpath), str(out), '--min-flat-em', '0.3']
            with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                m.main()
            first = out.read_bytes()
            with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(FileExistsError):
                    m.main()
            self.assertEqual(out.read_bytes(), first)

    def test_missing_threshold_argument_refused(self):
        with tempfile.TemporaryDirectory() as d:
            fpath = Path(d) / 'f.ttf'
            font_with({'.notdef': TTGlyphPen(None).glyph()}).save(fpath)
            argv = ['auto_sb_class_table.py', str(fpath), str(Path(d) / 't.tsv')]
            with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    m.main()


class TestUnitsHandling(unittest.TestCase):
    def test_invalid_units_per_em_refused(self):
        for bad_upm in (0, -1000):
            f = font_with({'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph()})
            f['head'].unitsPerEm = bad_upm
            with self.assertRaises(ValueError):
                m.measure(f, .3)

    def test_threshold_is_em_relative_scales_with_upm(self):
        # Same 500-unit stem: qualifies at UPM 1000 (threshold 300) but not at
        # UPM 2048 (threshold 614.4). The em ratio, not the raw unit count, governs.
        glyphs = {'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph(0, 0, 500, 500)}
        rows_1000 = {r[0]: r for r in m.measure(font_with(glyphs, 1000), .3)}
        self.assertEqual(rows_1000['stem'][5], 'flat_stem')
        glyphs = {'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph(0, 0, 500, 500)}
        rows_2048 = {r[0]: r for r in m.measure(font_with(glyphs, 2048), .3)}
        self.assertEqual(rows_2048['stem'][5], 'unclassified')

    def test_width_height_reported_in_font_units(self):
        rows = {r[0]: r for r in m.measure(font_with({'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph()}), .3)}
        self.assertEqual(rows['stem'][11:13], ['200', '600'])

    def test_threshold_boundary_value_one_accepted(self):
        # (0,1] boundary: 1 is a valid explicit value; with threshold = upm no
        # real stem reaches it, so geometry stays unclassified rather than erroring.
        rows = {r[0]: r for r in m.measure(font_with({'.notdef': TTGlyphPen(None).glyph(), 'stem': rect_glyph()}), 1)}
        self.assertEqual(rows['stem'][5], 'unclassified')


if __name__ == '__main__':
    unittest.main()
