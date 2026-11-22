import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

import generate_roll_markers as gen


def decode_png(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise AssertionError('PNG signature')
    offset, payload, dims = 8, bytearray(), None
    while offset < len(data):
        length = struct.unpack('>I', data[offset:offset+4])[0]
        kind = data[offset+4:offset+8]
        body = data[offset+8:offset+8+length]
        crc = struct.unpack('>I', data[offset+8+length:offset+12+length])[0]
        if zlib.crc32(kind+body) & 0xffffffff != crc:
            raise AssertionError('PNG CRC')
        if kind == b'IHDR':
            dims = struct.unpack('>IIBBBBB', body)
        if kind == b'IDAT':
            payload.extend(body)
        offset += length + 12
    w, h, depth, color, compression, filtering, interlace = dims
    assert (depth, color, compression, filtering, interlace) == (8, 2, 0, 0, 0)
    raw = zlib.decompress(payload)
    assert len(raw) == (w*3+1)*h
    assert all(raw[y*(w*3+1)] == 0 for y in range(h))
    rgb = b''.join(raw[y*(w*3+1)+1:(y+1)*(w*3+1)] for y in range(h))
    return w, h, rgb


class MarkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.tmp.name)
        cls.manifest = gen.generate(cls.root / 'a', 400, 240, 8)
        cls.other = gen.generate(cls.root / 'b', 400, 240, 8)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_byte_reproducibility(self):
        self.assertEqual(self.manifest, self.other)
        a = self.root / 'a'
        b = self.root / 'b'
        self.assertEqual({str(p.relative_to(a)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in a.rglob('*') if p.is_file()},
                         {str(p.relative_to(b)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in b.rglob('*') if p.is_file()})

    def test_frozen_hash_regression(self):
        frozen = json.loads((Path(__file__).parent / 'golden-small-hashes.json').read_text())
        actual = {str(p.relative_to(self.root/'a')): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in (self.root/'a').rglob('*') if p.is_file()}
        self.assertEqual(actual, frozen)

    def test_dimensions_hashes_and_png_bytes(self):
        expected = {'sbs': (800, 240), 'half_sbs': (400, 240),
                    'top_bottom': (400, 480), 'mono': (400, 240),
                    'native_vr180': (800, 240)}
        for fixture in self.manifest['fixtures']:
            with self.subTest(fixture=fixture['id']):
                path = self.root / 'a' / fixture['path']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), fixture['sha256'])
                w, h, rgb = decode_png(path)
                self.assertEqual((w, h), expected[fixture['mode']])
                self.assertEqual((w, h), (fixture['width'], fixture['height']))
                self.assertEqual(hashlib.sha256(rgb).hexdigest(), fixture['pixel_rgb_sha256'])

    def test_marker_correspondences_and_signed_disparity(self):
        self.assertEqual(len(self.manifest['fixtures']), 13)
        for fixture in self.manifest['fixtures']:
            self.assertEqual(len(fixture['markers']), 9)
            self.assertEqual(len({m['id'] for m in fixture['markers']}), 9)
            self.assertEqual({tuple(m['base_eye_uv']) for m in fixture['markers']},
                             {(u, v) for u in (.2, .5, .8) for v in (.2, .5, .8)})
            for marker in fixture['markers']:
                pos = marker['positions']
                if fixture['mode'] == 'mono':
                    self.assertEqual(set(pos), {'mono'})
                    self.assertEqual(marker['disparity_fraction'], 0)
                    continue
                self.assertEqual(set(pos), {'left', 'right'})
                self.assertAlmostEqual(pos['right']['eye_uv'][0] - pos['left']['eye_uv'][0],
                                       fixture['signed_disparity_fraction'])
                self.assertEqual(pos['right']['eye_uv'][1], pos['left']['eye_uv'][1])
        for mode in gen.MODES:
            disparities = {f['signed_disparity_fraction'] for f in self.manifest['fixtures'] if f['mode'] == mode}
            self.assertEqual(disparities, {0} if mode == 'mono' else {-.02, 0, .02})

    def test_half_sbs_coordinate_conversion(self):
        for f in self.manifest['fixtures']:
            if f['mode'] != 'half_sbs':
                continue
            self.assertEqual(f['sample_aspect_ratio'], [2, 1])
            for m in f['markers']:
                for eye, pos in m['positions'].items():
                    u, v = pos['eye_uv']
                    x, y = pos['source_pixel_xy']
                    self.assertAlmostEqual(x, (0 if eye == 'left' else 200) + u*200 - .5)
                    self.assertAlmostEqual(y, v*240 - .5)

    def test_top_bottom_coordinate_conversion(self):
        for f in self.manifest['fixtures']:
            if f['mode'] != 'top_bottom':
                continue
            for m in f['markers']:
                for eye, pos in m['positions'].items():
                    u, v = pos['eye_uv']
                    x, y = pos['source_pixel_xy']
                    self.assertAlmostEqual(x, u*400 - .5)
                    self.assertAlmostEqual(y, (0 if eye == 'left' else 240) + v*240 - .5)

    def test_native_mapping(self):
        for f in self.manifest['fixtures']:
            if f['mode'] == 'native_vr180':
                for m in f['markers']:
                    for p in m['positions'].values():
                        u, v = p['eye_uv']
                        lon, lat = p['longitude_latitude_deg']
                        self.assertAlmostEqual(lon, 180*(u-.5))
                        self.assertAlmostEqual(lat, 180*(.5-v))

    def test_templates_are_exact_subimages_and_nonoverlapping(self):
        for fixture in self.manifest['fixtures']:
            w, h, rgb = decode_png(self.root / 'a' / fixture['path'])
            boxes = []
            for m in fixture['markers']:
                for eye, p in m['positions'].items():
                    x, y, pw, ph = p['bbox_xywh']
                    tw, th, patch = decode_png(self.root / 'a' / p['template_path'])
                    self.assertEqual((tw, th), (pw, ph))
                    self.assertEqual(hashlib.sha256((self.root / 'a' / p['template_path']).read_bytes()).hexdigest(), p['template_sha256'])
                    self.assertTrue(0 <= x < x+pw <= w and 0 <= y < y+ph <= h)
                    actual = b''.join(rgb[((y+i)*w+x)*3:((y+i)*w+x+pw)*3] for i in range(ph))
                    self.assertEqual(actual, patch)
                    for a, b, c, d in boxes:
                        self.assertTrue(x+pw <= a or a+c <= x or y+ph <= b or b+d <= y)
                    boxes.append((x, y, pw, ph))

    def test_invalid_sizes(self):
        for width, height in [(0,240), (-1,240), (201,240), (400,0), (400,119),
                              (400.5,240), (True,240), (400,False), (10000,240), (8192,8192)]:
            with self.subTest(size=(width,height)), self.assertRaises(ValueError):
                gen.generate(self.root / 'invalid', width, height, 8)
        self.assertFalse((self.root / 'invalid').exists())

    def test_overlapping_or_unresolvable_rejected(self):
        for radius in (0, 4, 7.9, 36, 1000, float('inf'), float('nan')):
            with self.subTest(radius=radius), self.assertRaises(ValueError):
                gen.generate(self.root / 'invalid', 200, 120, radius)

    def test_invalid_modes(self):
        for modes in ((), ('oops',), ('sbs','sbs')):
            with self.assertRaises(ValueError):
                gen.generate(self.root / 'invalid', 400, 240, 8, modes)

    def test_cli_invalid_is_nonzero(self):
        result = subprocess.run([sys.executable, str(Path(gen.__file__)), '--output',
                                 str(self.root/'badcli'), '--eye-width', '201'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('generator_error:', result.stderr)
        self.assertFalse((self.root/'badcli').exists())

    def test_fractional_centroid_is_preserved(self):
        # This case catches rounding centres to integer source pixels.
        for center in (20.1, 20.25, 20.5, 20.9):
            bbox, patch = gen.marker_patch(center, 20.3, 12, 12, gen.PALETTE[0])
            x0, y0, w, h = bbox
            weights = [(x0+x, y0+y, sum(patch[(y*w+x)*3:(y*w+x+1)*3])-36)
                       for y in range(h) for x in range(w)]
            total = sum(p[2] for p in weights)
            self.assertLess(abs(sum(x*v for x,y,v in weights)/total-center), .01)
            self.assertLess(abs(sum(y*v for x,y,v in weights)/total-20.3), .01)

    def test_manifest_is_path_and_time_independent(self):
        self.assertNotIn(str(self.root), json.dumps(self.manifest))
        self.assertEqual(gen.canonical(self.manifest), (self.root/'a'/'manifest.json').read_bytes())


if __name__ == '__main__':
    unittest.main()
