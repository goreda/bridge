import io
import unittest
import tempfile
from types import SimpleNamespace
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
import benchmark as b


def fixture():
    fb=FontBuilder(1000,isTTF=True)
    fb.setupGlyphOrder(['.notdef','A','V','space'])
    fb.setupCharacterMap({65:'A',86:'V',32:'space'})
    glyphs={}
    for name in ['.notdef','A','V','space']:
        p=TTGlyphPen(None)
        if name!='space':
            p.moveTo((20,0));p.lineTo((420,0));p.lineTo((420,700));p.lineTo((20,700));p.closePath()
        glyphs[name]=p.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n:(500,20) if n!='space' else (250,0) for n in glyphs})
    fb.setupHorizontalHeader(ascent=800,descent=-200)
    fb.setupNameTable({'familyName':'Synthetic','styleName':'Regular','uniqueFontIdentifier':'fixture','fullName':'Synthetic Regular','psName':'Synthetic-Regular'})
    fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    fb.setupPost();fb.setupMaxp()
    return b.save_bytes(fb.font)


class Tests(unittest.TestCase):
    def setUp(self):
        self.original=fixture()
        self.stripped,_=b.strip_reference(self.original)
        self.response='G\t.notdef\t30\t40\t470\nG\tA\t30\t40\t470\nG\tV\t30\t40\t470\nK\tA\tV\t-50\nS\tready\t1\n'
    def test_strip_zeroes_both_sides_and_space(self):
        f=b.TTFont(io.BytesIO(self.stripped))
        self.assertEqual(f['hmtx']['A'],(400,0));self.assertEqual(f['hmtx']['space'],(0,0))
    def test_original_unchanged(self):
        self.assertEqual(b.TTFont(io.BytesIO(self.original))['hmtx']['A'],(500,20))
    def test_gpos_shaped_width(self):
        data,_=b.apply_engine(self.stripped,self.response)
        self.assertEqual(b.width(data,'AV'),(890,2))
    def test_calibration_changes_spacing_not_pairs(self):
        data,_=b.apply_engine(self.stripped,self.response,10)
        self.assertEqual(b.width(data,'AV'),(910,2))
    def test_missing_glyph_refused(self):
        with self.assertRaises(ValueError): b.width(self.original,'Z')
    def test_missing_engine_coverage_refused(self):
        with self.assertRaises(ValueError): b.apply_engine(self.stripped,self.response.replace('G\tV\t30\t40\t470\n',''))
    def test_unknown_output_refused(self):
        with self.assertRaises(ValueError): b.apply_engine(self.stripped,self.response+'UNKNOWN\n')
    def test_nonfinite_refused(self):
        with self.assertRaises(ValueError): b.apply_engine(self.stripped,self.response.replace('30','nan'))
    def test_duplicate_pair_refused(self):
        with self.assertRaises(ValueError): b.apply_engine(self.stripped,self.response+'K\tA\tV\t-50\n')
    def test_frame_mismatch_refused(self):
        with self.assertRaises(ValueError): b.apply_engine(self.stripped,self.response.replace('470','490'))
    def test_wrong_reference_pin_refused_before_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'reference.ttf';p.write_bytes(self.original)
            with self.assertRaisesRegex(ValueError,'SHA256 mismatch'):
                b.run(SimpleNamespace(reference=str(p)))
    def test_out_of_range_kern_refused(self):
        with self.assertRaises(ValueError): b.apply_engine(self.stripped,self.response.replace('-50','-40000'))
    def test_protocol_full_population(self):
        wire,excluded=b.protocol(self.stripped,.25)
        self.assertEqual(sum(l.startswith('G\t') for l in wire.splitlines()),3)
        self.assertEqual(excluded,['space'])
    def test_protocol_explicit_population(self):
        wire,excluded=b.protocol(self.stripped,.25,{65,86})
        self.assertEqual(sum(l.startswith('G\t') for l in wire.splitlines()),2)
        self.assertIn('.notdef',excluded)


if __name__=='__main__': unittest.main()
