#!/usr/bin/env python3
"""Tests for gen_manifest.py (piece 18). Stdlib only; run: python3 test_gen_manifest.py"""
import hashlib, os, struct, subprocess, sys, tempfile, unittest, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen_manifest.py")

def png(path, w=1485, h=1050):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)
    raw = b"\x00" + b"\xff" * w
    idat = zlib.compress(raw * h)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

class GenTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        d = self.d.name
        self.tiles = os.path.join(d, "tiles"); os.mkdir(self.tiles)
        for i, cp in enumerate((0x41, 0x42, 0x48, 0xC9)):
            png(os.path.join(self.tiles, "%05d__%04X__%012x.png" % (i, cp, cp)))
        # a sequence tile (two codepoints) must be excluded
        png(os.path.join(self.tiles, "00004__0041_0057__abcdefabcdef.png"))
        open(os.path.join(self.tiles, "notes.txt"), "w").write("x")
        self.tmpl = os.path.join(d, "tmpl")
        with open(self.tmpl, "w") as f:
            f.write("vendor NONE\nupm 1000\nrdp_epsilon 0.25\nfit_tolerance_policy derived_source_quantization\n"
                    "fit_squared_error 0.25\nfit_max_refits 8\nflatten_tolerance 0.5\n"
                    "glyph 0x0041 A @TILEDIR@/a.png\nglyph 0x0042 B @TILEDIR@/b.png\n")
        self.scales = os.path.join(d, "scales.tsv")
        with open(self.scales, "w") as f:
            f.write("style\tscale\tframe\nT/Style\t2.0\t1485x1050\n")
        self.out = os.path.join(d, "m.txt")

    def run_gen(self, *extra):
        r = subprocess.run([sys.executable, GEN, "--tiledir", self.tiles, "--style", "T/Style",
                            "--template", self.tmpl, "--scales", self.scales, "--out", self.out, *extra],
                           capture_output=True, text=True)
        return r

    def test_pin_matches_engine_rule(self):
        r = self.run_gen()
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = open(self.out).read().splitlines()
        rows = {}
        for l in lines:
            p = l.split()
            if p[:1] == ["glyph"]:
                rows[int(p[1], 16)] = p[2]
        # sequence tile excluded, template names used, uniXXXX fallback for 0xC9
        self.assertEqual(rows, {0x41: "A", 0x42: "B", 0x48: "uni0048", 0xC9: "uni00C9"})
        expect = hashlib.sha256("".join(sorted("%x:%s\n" % (cp, n) for cp, n in rows.items())).encode()).hexdigest()
        declared = [l.split()[1] for l in lines if l.startswith("population_sha256 ")][0]
        self.assertEqual(declared, expect)
        self.assertIn("scale 2.0", lines)
        self.assertIn("capture_cohort T/Style", lines)
        self.assertIn("max_pairs 12", lines)

    def test_limit_keeps_h(self):
        r = self.run_gen("--limit", "2")
        self.assertEqual(r.returncode, 0, r.stderr)
        cps = [int(l.split()[1], 16) for l in open(self.out) if l.startswith("glyph ")]
        self.assertIn(0x48, cps)          # H always kept (declared-convention binding)
        self.assertEqual(len(cps), 3)

    def test_whitespace_tile_prefix_refused(self):
        r = self.run_gen("--tile-prefix", "/tmp/has space/tiles")
        self.assertEqual(r.returncode, 3)
        self.assertIn("WhitespaceInTilePath", r.stderr)

    def test_missing_style_scale_refused(self):
        os.rename(self.scales, self.scales + ".bak")
        with open(self.scales, "w") as f:
            f.write("Other/Style\t2.0\n")
        r = self.run_gen()
        self.assertEqual(r.returncode, 3)
        self.assertIn("StyleScaleMissing", r.stderr)

    def tearDown(self):
        self.d.cleanup()

if __name__ == "__main__":
    unittest.main()
