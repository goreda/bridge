import importlib.util
import math
from pathlib import Path
import unittest
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

spec = importlib.util.spec_from_file_location('table', Path(__file__).parents[1] / 'auto_sb_class_table.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def font_fixture():
    rect = TTGlyphPen(None)
    rect.moveTo((0, 0)); rect.lineTo((200, 0)); rect.lineTo((200, 600)); rect.lineTo((0, 600)); rect.closePath()
    circle = TTGlyphPen(None)
    circle.moveTo((100, 0)); circle.qCurveTo((300, 0), (300, 600), (100, 600)); circle.qCurveTo((-100, 600), (-100, 0), (100, 0)); circle.closePath()
    implied = TTGlyphPen(None)
    implied.qCurveTo((0, 0), (200, 0), (200, 200), (0, 200), None); implied.closePath()
    empty = TTGlyphPen(None)
    stem = rect.glyph()
    comp = TTGlyphPen({'stem': stem})
    comp.addComponent('stem', (1, 0, 0, 1, 50, 0))
    glyphs = {'.notdef': empty.glyph(), 'stem': stem, 'round': circle.glyph(), 'implied': implied.glyph(), 'composite': comp.glyph()}
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(list(glyphs)); fb.setupCharacterMap({65:'stem',66:'round'})
    fb.setupGlyf(glyphs); fb.setupHorizontalMetrics({g:(500,0) for g in glyphs})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({'familyName':'Fixture','styleName':'Regular'}); fb.setupOS2(); fb.setupPost(); fb.setupMaxp()
    return fb.font


class TestTable(unittest.TestCase):
    def test_flat_round_empty_composite_and_implied(self):
        rows = {r[0]:r for r in m.measure(font_fixture(), .3)}
        self.assertEqual(rows['stem'][5:7], ['flat_stem','flat_stem'])
        self.assertEqual(rows['round'][5:7], ['round','round'])
        self.assertEqual(rows['.notdef'][5:7], ['empty','empty'])
        self.assertEqual(rows['composite'][5:7], ['flat_stem','flat_stem'])
        self.assertNotEqual(rows['implied'][5], 'empty')

    def test_deterministic_and_engine_columns(self):
        f = font_fixture()
        a = m.table_bytes(m.measure(f,.3)); b = m.table_bytes(m.measure(f,.3))
        self.assertEqual(a,b)
        self.assertEqual(len(a.decode().splitlines()),6)
        self.assertEqual(a.decode().splitlines()[0].split('\t')[5:7],['class_left','class_right'])

    def test_threshold_explicit_invalid(self):
        for v in (0,-1,2,math.nan, math.inf):
            with self.assertRaises(ValueError): m.measure(font_fixture(),v)

    def test_diagonal_is_not_round_or_flat(self):
        self.assertEqual(m.side_class([('line',((0,0),(100,600)))],0,'left',300)[0],'unclassified')

    def test_cubic_extremum(self):
        curves=[('cubic',((100,0),(-100,0),(-100,600),(100,600)))]
        x=m.calcCubicBounds(*curves[0][1])[0]
        self.assertEqual(m.side_class(curves,x,'left',300)[0],'round')

    def test_open_contour_refused(self):
        p=m.Segments(None);p.moveTo((0,0));p.lineTo((1,1))
        with self.assertRaises(ValueError):p.endPath()



class TestBindingAudit(unittest.TestCase):
    def data(self):
        import sys
        sys.path.insert(0, str(Path(__file__).parents[1]))
        import auto_sb_binding_audit as audit
        import hashlib
        f = font_fixture(); stream=__import__('io').BytesIO(); f.save(stream)
        manifest=b'glyph 0x41 stem tile.png\n'
        receipt=('manifest_pin\t'+hashlib.sha256(manifest).hexdigest()+'\nglyph\tstem\tcp\t0x41\nfallback\tstem\tline_spans\t0\n').encode()
        return audit, stream.getvalue(), m.table_bytes(m.measure(f,.3)), manifest, receipt

    def test_matching_ids_do_not_mint_solved_or_execution_binding(self):
        audit, *data=self.data(); r=audit.audit(*data)
        self.assertTrue(r['manifest_pin_matches_receipt'])
        self.assertTrue(r['manifest_matches_receipt_glyph_ids'])
        self.assertTrue(r['table_matches_font_glyph_ids'])
        self.assertTrue(r['a2_solved_population'].startswith('UNMAPPED'))
        self.assertFalse(r['production_accepted'])
        self.assertEqual(r['pool_publication'],'NOT_PERFORMED')

    def test_duplicate_manifest_and_bad_table_refused(self):
        audit,font,table,manifest,receipt=self.data()
        with self.assertRaises(ValueError):audit.audit(font,table,manifest+manifest,receipt)
        with self.assertRaises(ValueError):audit.audit(font,b'wrong\theader\n',manifest,receipt)

    def test_manifest_pin_mismatch_and_unknown_glyph_visible(self):
        audit,font,table,manifest,receipt=self.data()
        r=audit.audit(font,table,manifest.replace(b'stem',b'foreign'),receipt)
        self.assertFalse(r['manifest_pin_matches_receipt'])
        self.assertFalse(r['manifest_matches_receipt_glyph_ids'])
        self.assertEqual(r['manifest_missing_in_table'],['foreign'])

if __name__ == '__main__': unittest.main()
