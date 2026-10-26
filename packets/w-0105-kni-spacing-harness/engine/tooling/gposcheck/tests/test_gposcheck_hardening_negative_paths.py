"""Negative-path sweeps for input hardening: malformed declared rows, huge numbers, corrupt GPOS bytes
in the output and in the original, and value format tampering. None of these inputs may raise."""
import contextlib
import io
import json
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from fontTools.ttLib import TTFont  # noqa: E402
from gposcheck import check, Declared, synth  # noqa: E402
from gposcheck.__main__ import main as cli_main  # noqa: E402

FEA = "pos A V -80;\npos V A -30;\npos T o -60;\n@L = [A B];\n@R = [V W];\npos @L @R -20;"
PAIRS = {("A", "V"): -80, ("V", "A"): -30, ("T", "o"): -60}
for _l in "AB":
    for _r in "VW":
        PAIRS.setdefault((_l, _r), -20)
DECL = [Declared(l, r, v, v, "written") for (l, r), v in PAIRS.items()]
ROW = {"left": "A", "right": "V", "requested": -80, "written": -80, "status": "written", "reason": ""}


def codes(findings):
    return [f[0] for f in findings]


def verdict(text):
    m = re.search(r"^verdict=(\w+) findings=(\d+)$", text, re.M)
    return m.groups() if m else None


class Fonts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.orig = synth.make_original()
        cls.out = synth.standin_write(cls.orig, FEA)
        f = TTFont(io.BytesIO(cls.out))
        cls.gpos = f.reader["GPOS"]


class MalformedDeclaredRows(Fonts):
    JUNK = [None, 5, 1.5, True, [], ["A"], {}, {"a": 1}, float("nan"), float("inf"), 10 ** 400, b"A"]

    def test_junk_in_every_field_never_raises_and_always_fails(self):
        base = ROW
        for field in ("left", "right", "requested", "written", "status", "reason"):
            for junk in self.JUNK:
                row = dict(base)
                row[field] = junk
                try:
                    text, findings, _ = check(self.orig, self.out, [dict(row)] + [
                        {"left": l, "right": r, "requested": v, "written": v, "status": "written", "reason": ""}
                        for (l, r), v in PAIRS.items() if (l, r) != ("A", "V")])
                except Exception as e:  # noqa: BLE001
                    self.fail("raised %r for %s=%r" % (e, field, junk))
                v = verdict(text)
                self.assertIsNotNone(v, (field, junk))
                if field == "reason":
                    continue  # a bad reason on a written pair is not a defect by itself
                self.assertEqual(v[0], "FAIL", (field, junk, text))

    def test_missing_key_in_each_position(self):
        for key in ROW:
            if key in ("reason", "written"):
                continue  # both are optional by contract; a missing written means not written
            row = {k: v for k, v in ROW.items() if k != key}
            text, findings, _ = check(self.orig, self.out, [row])
            self.assertIn("declared_row_unusable", codes(findings), key)

    def test_row_types(self):
        for row in (None, 7, "AV", ["A", "V"], 1.5, True):
            text, findings, _ = check(self.orig, self.out, [row])
            self.assertIn("declared_row_unusable", codes(findings), repr(row))

    def test_unhashable_left_does_not_mask_the_other_rows(self):
        rows = [dict(ROW, left=["A"])] + [dict(ROW, left=l, right=r, requested=v, written=v)
                                          for (l, r), v in PAIRS.items() if (l, r) != ("A", "V")]
        text, findings, _ = check(self.orig, self.out, rows)
        c = codes(findings)
        self.assertEqual(c.count("declared_row_unusable"), 1, text)
        self.assertNotIn("roundtrip_value_mismatch", c)

    def test_huge_requested_both_signs_and_float_overflow(self):
        for req in (10 ** 400, -10 ** 400, 10 ** 5000, 2 ** 1024):
            for st in ("written", "rounded"):
                text, findings, _ = check(self.orig, self.out, [Declared("A", "V", req, -80, st)])
                self.assertIn("declared_value_unusable", codes(findings), (req, st))
                self.assertEqual(verdict(text)[0], "FAIL")

    def test_json_literal_that_overflows_to_infinity(self):
        rows = json.loads('[{"left":"A","right":"V","requested":-1e999,"written":-80,"status":"rounded","reason":""}]')
        text, findings, _ = check(self.orig, self.out, rows)
        self.assertIn("declared_value_unusable", codes(findings))


class CliRows(Fonts):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = lambda n: os.path.join(self.tmp.name, n)
        for n, b in (("o.ttf", self.orig), ("n.ttf", self.out)):
            with open(self.p(n), "wb") as f:
                f.write(b)

    def tearDown(self):
        self.tmp.cleanup()

    def cli(self, declared_text):
        with open(self.p("d.json"), "w") as f:
            f.write(declared_text)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli_main(["--original", self.p("o.ttf"), "--output", self.p("n.ttf"),
                           "--declared", self.p("d.json"), "--receipt", self.p("r.txt")])
        with open(self.p("r.txt")) as f:
            return rc, f.read()

    def test_bad_rows_exit_one_with_a_receipt(self):
        for body in ('[{"left":["A"],"right":"V","requested":1,"written":1,"status":"written"}]',
                     '[{"left":"A","right":"V"}]', "[1]", "[null]", '[{"left":null,"right":"V","requested":-80,"written":-80,"status":"written"}]',
                     '[{"left":"A","right":"V","requested":1e999,"written":-80,"status":"rounded"}]'):
            rc, text = self.cli(body)
            self.assertEqual(rc, 1, body)
            self.assertIsNotNone(verdict(text), body)

    def test_top_level_not_a_list_is_exit_two(self):
        for body in ('{"a":1}', '"x"', "5", "null", "{bad", ""):
            rc, text = self.cli(body)
            self.assertEqual(rc, 2, body)
            self.assertIn("verdict=INPUT_ERROR", text)


class CorruptGposSweep(Fonts):
    """Every single-byte change of the GPOS table, in the output and in the original, with the original
    compared. Nothing may raise; a run that still passes must have ValueFormat1 == 4 and ValueFormat2 == 0
    in every pair adjustment subtable (the output contract)."""
    VALUES = (0x00, 0x01, 0x7F, 0x80, 0xFF)

    def mutated(self, base_font, pos, val):
        data = bytearray(self.gpos)
        data[pos] = val
        return synth.standin_write_raw(base_font, bytes(data))

    def formats_of(self, font_bytes):
        t = TTFont(io.BytesIO(font_bytes))["GPOS"].table
        out = []
        for lk in t.LookupList.Lookup:
            for st in lk.SubTable:
                if lk.LookupType == 9:
                    st = st.ExtSubTable
                out.append((getattr(st, "ValueFormat1", None), getattr(st, "ValueFormat2", None)))
        return out

    def test_output_gpos_single_byte_changes(self):
        passed = 0
        for pos in range(len(self.gpos)):
            for val in self.VALUES:
                if self.gpos[pos] == val:
                    continue
                bad = self.mutated(self.orig, pos, val)
                try:
                    text, findings, _ = check(self.orig, bad, DECL, compare_original=True, sequences=["AVA"])
                except Exception as e:  # noqa: BLE001
                    self.fail("raised %r at byte %d value %#x" % (e, pos, val))
                v = verdict(text)
                self.assertIn(v[0], ("PASS", "FAIL"), (pos, val))
                if v[0] == "PASS":
                    passed += 1
                    for vf1, vf2 in self.formats_of(bad):
                        self.assertEqual((vf1, vf2), (4, 0), "PASS with value formats %r at byte %d value %#x" % ((vf1, vf2), pos, val))
        self.assertGreater(passed, 0)  # the sweep must also contain harmless changes, so it is not vacuous

    def test_original_gpos_single_byte_changes_with_comparison(self):
        base_orig = synth.standin_write(self.orig, "pos A V -80;\npos B V -10;")
        raw = TTFont(io.BytesIO(base_orig)).reader["GPOS"]
        failures_typed = 0
        for pos in range(len(raw)):
            for val in self.VALUES:
                if raw[pos] == val:
                    continue
                data = bytearray(raw)
                data[pos] = val
                bad = synth.standin_write_raw(self.orig, bytes(data))
                try:
                    text, findings, _ = check(bad, synth.standin_write(self.orig, "pos A V -80;"),
                                              [Declared("A", "V", -80, -80, "written")], compare_original=True)
                except Exception as e:  # noqa: BLE001
                    self.fail("raised %r at original byte %d value %#x" % (e, pos, val))
                self.assertIsNotNone(verdict(text), (pos, val))
                if "original_parse_failure" in codes(findings):
                    failures_typed += 1
        self.assertGreater(failures_typed, 0)

    def test_truncated_gpos_at_every_length(self):
        for n in range(0, len(self.gpos), 3):
            bad = synth.standin_write_raw(self.orig, bytes(self.gpos[:n]))
            try:
                text, findings, _ = check(self.orig, bad, DECL)
            except Exception as e:  # noqa: BLE001
                self.fail("raised %r at length %d" % (e, n))
            self.assertEqual(verdict(text)[0], "FAIL", n)


class ValueFormatTamper(Fonts):
    def patch(self, off_in_subtable, value):
        data = bytearray(self.gpos)
        i = data.find(b"\x00\x01\x00\x00") if False else None
        for o in range(len(data) - 8):
            if data[o:o + 2] == b"\x00\x01" and data[o + 4:o + 6] == b"\x00\x04":
                data[o + off_in_subtable:o + off_in_subtable + 2] = value.to_bytes(2, "big")
                return synth.standin_write_raw(self.orig, bytes(data))
        self.fail("format 1 subtable not found")

    def test_second_value_format_nonzero_is_never_a_pass(self):
        for vf2 in (0x0001, 0x0004, 0x0100, 0x7F00, 0xFF00, 0xFFFF):
            bad = self.patch(6, vf2)
            text, findings, _ = check(self.orig, bad, DECL)
            self.assertEqual(verdict(text)[0], "FAIL", hex(vf2))
            self.assertTrue(set(codes(findings)) & {"value_format2_not_zero", "value_format_reserved_bits",
                                                    "gpos_raw_structure_unreadable", "parse_failure"}, (hex(vf2), codes(findings)))

    def test_first_value_format_other_than_x_advance_is_never_a_pass(self):
        for vf1 in (0x0000, 0x0001, 0x0005, 0x0104, 0x7F04, 0xFF04, 0x0008, 0xFFFF):
            bad = self.patch(4, vf1)
            text, findings, _ = check(self.orig, bad, DECL)
            self.assertEqual(verdict(text)[0], "FAIL", hex(vf1))

    def test_class_pair_subtable_formats_are_checked_too(self):
        fea = "@L = [A B];\n@R = [V W];\npos @L @R -20;"
        out = synth.standin_write(self.orig, fea)
        raw = bytearray(TTFont(io.BytesIO(out)).reader["GPOS"])
        n = 0
        for o in range(len(raw) - 12):
            if raw[o:o + 2] == b"\x00\x02" and raw[o + 4:o + 6] == b"\x00\x04" and raw[o + 6:o + 8] == b"\x00\x00":
                bad = bytearray(raw)
                bad[o + 6:o + 8] = b"\x01\x00"
                d = [Declared(l, r, -20, -20, "written") for l in "AB" for r in "VW"]
                text, findings, _ = check(self.orig, synth.standin_write_raw(self.orig, bytes(bad)), d)
                self.assertEqual(verdict(text)[0], "FAIL")
                n += 1
        self.assertGreaterEqual(n, 1)


if __name__ == "__main__":
    unittest.main()
