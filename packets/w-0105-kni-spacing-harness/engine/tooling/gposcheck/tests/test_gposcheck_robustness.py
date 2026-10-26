"""Unusable declared numbers and hand-damaged GPOS fixtures."""
import os
import struct
import sys
import types
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from gposcheck import check, Declared, synth  # noqa: E402
from gposcheck import core  # noqa: E402


def u16(b, o):
    return struct.unpack(">H", b[o:o + 2])[0]


def sub0(data):
    """Offset of the first subtable of the first lookup (plain, non-extension GPOS built by the stand-in)."""
    ll = u16(data, 8)
    lk = ll + u16(data, ll + 2)
    return lk + u16(data, lk + 6)


def patch(data, off, val):
    b = bytearray(data)
    b[off:off + 2] = struct.pack(">H", val)
    return bytes(b)


def run(orig, out, declared, **kw):
    text, findings, _ = check(orig, out, declared, **kw)
    return text, [f[0] for f in findings]


class UnusableDeclared(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.standin_write(self.orig, "pos A V -80;")

    def test_unusable_written_does_not_crash(self):
        for bad in (float("nan"), float("inf"), float("-inf"), "x", True, 10 ** 400):
            d = [Declared("A", "V", -80, bad, "written")]
            text, codes = run(self.orig, self.out, d)
            self.assertIn("declared_value_unusable", codes, repr(bad))
            self.assertIn("declared total=1 written=0 rounded=0 rejected=0 invalid=1", text)
            self.assertIn("declared_invalid pair=A,V", text)
            self.assertNotIn("roundtrip_value_mismatch", codes)
            self.assertNotIn("hb_value_mismatch", codes)

    def test_unusable_requested_keeps_the_status_mismatch_and_adds_a_finding(self):
        for bad in (float("nan"), float("inf"), "x"):
            d = [Declared("A", "V", bad, -80, "written")]
            text, codes = run(self.orig, self.out, d)
            self.assertIn("declared_value_unusable", codes, repr(bad))
            self.assertIn("status_mismatch", codes, repr(bad))
            self.assertIn("declared total=1 written=0 rounded=1 rejected=0 invalid=0", text)
            self.assertNotIn("roundtrip_value_mismatch", codes)

    def test_invalid_pair_is_excluded_not_hidden(self):
        # the font does contain A,V = -80; the invalid declaration keeps it from being compared, and the verdict fails
        text, codes = run(self.orig, self.out, [Declared("A", "V", -80, float("nan"), "written")])
        self.assertTrue(text.rstrip().split("\n")[-1].startswith("verdict=FAIL"))


class DamagedFixtures(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()

    def test_pairset_unknown_second_glyph(self):
        data = synth.standin_gpos_bytes(self.orig, "pos A V -80;")
        s0 = sub0(data)
        self.assertEqual(u16(data, s0), 1)
        ps = s0 + u16(data, s0 + 10)
        bad = patch(data, ps + 2, 99)            # first record's second glyph id: beyond the glyph order
        out = synth.standin_write_raw(self.orig, bad)
        _, codes = run(self.orig, out, [Declared("A", "V", -80, -80, "written")])
        self.assertIn("pairset_unknown_second_glyph", codes)

    def test_class_count_mismatch(self):
        data = synth.standin_gpos_bytes(self.orig, "@L = [A B];\n@R = [V W];\npos @L @R -30;")
        s0 = sub0(data)
        self.assertEqual(u16(data, s0), 2)
        bad = patch(data, s0 + 14, u16(data, s0 + 14) + 1)   # Class2Count one too large
        out = synth.standin_write_raw(self.orig, bad)
        text, codes = run(self.orig, out, [Declared(l, r, -30, -30, "written") for l in "AB" for r in "VW"])
        self.assertIn("class_count_mismatch", codes)
        self.assertEqual(text.rstrip().split("\n")[-1][:12], "verdict=FAIL")

    def test_unsupported_pairpos_format_bytes(self):
        data = synth.standin_gpos_bytes(self.orig, "pos A V -80;")
        bad = patch(data, sub0(data), 3)
        out = synth.standin_write_raw(self.orig, bad)
        text, codes = run(self.orig, out, [Declared("A", "V", -80, -80, "written")])
        self.assertIn("unsupported_pairpos_format", codes)
        self.assertEqual(text.rstrip().split("\n")[-1][:12], "verdict=FAIL")


class HandBuiltObjects(unittest.TestCase):
    """Paths the parser cannot reach from bytes (values are signed 16 bit when read, unknown formats may be refused
    earlier): exercised with hand-built subtable objects."""

    def gp(self):
        g = object.__new__(core._Gpos)
        g.gid = {".notdef": 0, "A": 1, "V": 2}
        g.f1_subtables = g.f1_pairsets = g.f1_records = 0
        g.explicit_zero = set()
        g.findings = []
        g.explicit_pairs = set()
        return g

    def test_unsupported_format_object(self):
        g = self.gp()
        st = types.SimpleNamespace(Format=3, Coverage=types.SimpleNamespace(glyphs=["A"]))
        g._index_subtable(st)
        self.assertIn("unsupported_pairpos_format", [f[0] for f in g.findings])

    def test_value_out_of_int16_object(self):
        g = self.gp()
        v = types.SimpleNamespace(XAdvance=40000)
        rec = types.SimpleNamespace(SecondGlyph="V", Value1=v, Value2=None)
        ps = types.SimpleNamespace(PairValueRecord=[rec], PairValueCount=1)
        st = types.SimpleNamespace(Format=1, Coverage=types.SimpleNamespace(glyphs=["A"]), PairSet=[ps], PairSetCount=1)
        g._index_subtable(st)
        self.assertEqual([f[0] for f in g.findings], ["value_out_of_int16"])
        self.assertIn("A,V XAdvance=40000", g.findings[0][1])

    def test_value_out_of_int16_class_object(self):
        g = self.gp()
        c2 = types.SimpleNamespace(Value1=types.SimpleNamespace(XAdvance=-40000), Value2=None)
        st = types.SimpleNamespace(
            Format=2, Coverage=types.SimpleNamespace(glyphs=["A"]), Class1Count=1, Class2Count=1,
            Class1Record=[types.SimpleNamespace(Class2Record=[c2])],
            ClassDef1=types.SimpleNamespace(classDefs={}), ClassDef2=types.SimpleNamespace(classDefs={}))
        g._index_subtable(st)
        self.assertEqual([f[0] for f in g.findings], ["value_out_of_int16"])


if __name__ == "__main__":
    unittest.main()
