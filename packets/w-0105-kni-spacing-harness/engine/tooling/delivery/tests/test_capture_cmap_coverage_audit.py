import sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture_cmap_coverage_audit as t


def make(root, tiles):
    g = Path(root) / 'F' / 'S' / 'glyph'
    g.mkdir(parents=True)
    for i, (cp, data) in enumerate(tiles):
        (g / f'{i:05d}__{cp:04X}__x.png').write_bytes(data)
    return g


REQ = t.parse_codepoints('U+00E7,U+011E-U+011F,U+015E')


class T(unittest.TestCase):
    def test_classes(self):
        with tempfile.TemporaryDirectory() as d:
            ph = b'same'
            make(d, [(0xE7, b'a'), (0x11E, ph), (0x11F, ph), (0x41, ph), (0x42, b'b')])
            r = t.audit_collection(d, REQ)['F/S']['status']
            self.assertEqual(r['U+00E7'], 'PRESENT')
            self.assertEqual(r['U+011E'], 'PLACEHOLDER')
            self.assertEqual(r['U+015E'], 'ABSENT')

    def test_no_repeat_means_no_placeholder(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, [(0xE7, b'a'), (0x11E, b'b')])
            r = t.audit_collection(d, REQ)['F/S']['status']
            self.assertEqual(r['U+011E'], 'PRESENT')

    def test_parse(self):
        self.assertEqual(t.parse_codepoints('U+41-U+43, U+0061'), [0x41, 0x42, 0x43, 0x61])

    def test_cmap_check(self):
        from fontTools.fontBuilder import FontBuilder
        fb = FontBuilder(1000, isTTF=True)
        fb.setupGlyphOrder(['.notdef', 'ccedilla', 'gbreve'])
        fb.setupCharacterMap({0xE7: 'ccedilla', 0x11E: 'gbreve'})
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'f.ttf'
            fb.setupGlyf({n: __import__('fontTools.pens.ttGlyphPen', fromlist=['x']).TTGlyphPen(None).glyph() for n in fb.font.getGlyphOrder()})
            fb.setupHorizontalMetrics({n: (500, 0) for n in fb.font.getGlyphOrder()})
            fb.setupHorizontalHeader(); fb.setupNameTable({'familyName': 'T', 'styleName': 'R'})
            fb.setupOS2(); fb.setupPost(); fb.save(p)
            bad = t.check_cmap({'U+00E7': 'PRESENT', 'U+011E': 'PLACEHOLDER', 'U+0131': 'PRESENT'}, p)
            self.assertEqual(len(bad), 2)

if __name__ == '__main__':
    unittest.main()
