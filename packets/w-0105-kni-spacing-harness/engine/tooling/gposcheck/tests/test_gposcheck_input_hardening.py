"""Input hardening, CLI exit codes, ValueFormat mask, LookupFlag, ReqFeatureIndex, FeatureParams and ClassDef range."""
import io
import json
import os
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from fontTools.ttLib import TTFont  # noqa: E402
from gposcheck import check, Declared, synth  # noqa: E402
from gposcheck.__main__ import main  # noqa: E402

FEA = "pos A V -80;\npos V A -30;"
PAIRS = [Declared("A", "V", -80, -80, "written"), Declared("V", "A", -30, -30, "written")]


UNSET = object()


def codes(findings):
    return [f[0] for f in findings]


def patch_gpos(font_bytes, fn):
    f = TTFont(io.BytesIO(font_bytes))
    data = bytearray(f.reader["GPOS"])
    fn(data)
    return synth.standin_write_raw(font_bytes, bytes(data))


class Base(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.standin_write(self.orig, FEA)

    def run_check(self, declared=UNSET, orig=UNSET, out=UNSET, **kw):
        text, findings, _ = check(self.orig if orig is UNSET else orig, self.out if out is UNSET else out,
                                  PAIRS if declared is UNSET else declared, **kw)
        return text, codes(findings)


class DeclaredInput(Base):
    def test_clean_pass(self):
        text, c = self.run_check()
        self.assertEqual(c, [], text)

    def test_bad_containers_and_rows(self):
        for bad in (None, 5, {"left": "A"}, "AV"):
            text, c = self.run_check(declared=bad)
            self.assertIn("declared_input_unusable", c)
            self.assertIn("verdict=FAIL", text)
        rows = [{"left": "A", "right": "V", "requested": -80, "written": -80, "status": "written"},
                {"left": "V", "right": "A"}, 7, None, ["A", "V"],
                {"left": ["A"], "right": "V", "requested": 1, "written": 1, "status": "written"}]
        text, c = self.run_check(declared=rows)
        self.assertEqual(c.count("declared_row_unusable"), 5, text)
        self.assertNotIn("roundtrip_value_mismatch", c)

    def test_huge_integers_do_not_raise(self):
        for req, wr in ((10 ** 400, -80), (-80, 10 ** 400), (10 ** 400, 10 ** 400), (10 ** 5000, 10 ** 5000)):
            d = [Declared("A", "V", req, wr, "rounded"), PAIRS[1]]
            text, c = self.run_check(declared=d)
            self.assertIn("verdict=FAIL", text)
            self.assertNotIn("check_aborted", c)

    def test_huge_requested_is_unusable_and_status_mismatch(self):
        d = [Declared("A", "V", 10 ** 400, -80, "written"), PAIRS[1]]
        _, c = self.run_check(declared=d)
        self.assertIn("declared_value_unusable", c)
        self.assertIn("status_mismatch", c)


class ParseFailures(Base):
    def test_corrupt_original(self):
        text, c = self.run_check(orig=b"not a font")
        self.assertEqual(c, ["original_parse_failure"], text)

    def test_corrupt_output(self):
        text, c = self.run_check(out=b"not a font")
        self.assertEqual(c, ["parse_failure"], text)

    def test_both_and_non_bytes(self):
        _, c = self.run_check(orig=b"x", out=b"y")
        self.assertEqual(c, ["original_parse_failure", "parse_failure"])
        _, c = self.run_check(orig=None)
        self.assertIn("original_parse_failure", c)

    def test_corrupt_output_gpos_truncated(self):
        f = TTFont(io.BytesIO(self.out))
        raw = f.reader["GPOS"]
        bad = synth.standin_write_raw(self.orig, raw[:20])
        text, c = self.run_check(out=bad)
        self.assertTrue("parse_failure" in c or "gpos_raw_structure_unreadable" in c, c)
        self.assertIn("verdict=FAIL", text)

    def test_corrupt_original_gpos_with_compare(self):
        bad = synth.standin_write_raw(self.orig, b"\x00\x01\x00\x00\xff\xff\xff\xff\xff\xff")
        text, c = self.run_check(orig=bad, compare_original=True)
        self.assertIn("original_parse_failure", c, text)
        self.assertIn("verdict=FAIL", text)

    def test_sequence_input(self):
        _, c = self.run_check(sequences=[5, {"text": 3}, {"nope": 1}])
        self.assertEqual(c.count("sequence_input_unusable"), 3)
        _, c = self.run_check(sequences=7)
        self.assertIn("sequence_input_unusable", c)


class CliExitCodes(Base):
    def _files(self, declared_text):
        d = tempfile.mkdtemp()
        paths = {}
        for k, v in (("orig", self.orig), ("out", self.out)):
            paths[k] = os.path.join(d, k + ".ttf")
            open(paths[k], "wb").write(v)
        paths["decl"] = os.path.join(d, "d.json")
        open(paths["decl"], "w").write(declared_text)
        paths["rcpt"] = os.path.join(d, "r.txt")
        return paths

    def _main(self, p, *extra):
        buf = io.StringIO()
        old, sys.stdout = sys.stdout, buf
        try:
            rc = main(["--original", p["orig"], "--output", p["out"], "--declared", p["decl"], "--receipt", p["rcpt"], *extra])
        finally:
            sys.stdout = old
        return rc, buf.getvalue()

    def test_exit_codes(self):
        good = json.dumps([{"left": "A", "right": "V", "requested": -80, "written": -80, "status": "written"},
                           {"left": "V", "right": "A", "requested": -30, "written": -30, "status": "written"}])
        rc, _ = self._main(self._files(good))
        self.assertEqual(rc, 0)
        bad_value = good.replace('"written": -80', '"written": -79')
        rc, _ = self._main(self._files(bad_value))
        self.assertEqual(rc, 1)
        for text in ("{not json", '{"a": 1}', ""):
            p = self._files(text)
            rc, out = self._main(p)
            self.assertEqual(rc, 2, text)
            self.assertIn("verdict=INPUT_ERROR", out)
            self.assertIn("declared_file_unusable", open(p["rcpt"]).read())
        p = self._files(good)
        os.remove(p["orig"])
        rc, out = self._main(p)
        self.assertEqual(rc, 2)
        self.assertIn("input_file_unreadable", out)
        rc, _ = self._main(self._files("[1, null]"))
        self.assertEqual(rc, 1)

    def test_giant_integer_in_file(self):
        txt = '[{"left": "A", "right": "V", "requested": 1%s, "written": -80, "status": "written"}]' % ("0" * 400)
        rc, out = self._main(self._files(txt))
        self.assertEqual(rc, 1)
        self.assertIn("declared_value_unusable", out)


class StructureChecks(Base):
    def test_value_format_bit_outside_mask(self):
        def m(d):
            # first PairPos subtable: set a reserved bit in ValueFormat1
            i = bytes(d).find(b"\x00\x01\x00\x0c\x00\x00")  # format 1, offset, ValueFormat1=0x0004? locate by scan below
            for o in range(len(d) - 8):
                if d[o:o + 2] == b"\x00\x01" and d[o + 4:o + 6] == b"\x00\x04" and d[o + 6:o + 8] == b"\x00\x00":
                    d[o + 4] |= 0x01
                    return
            raise AssertionError("PairPos not found")
        bad = patch_gpos(self.out, m)
        text, c = self.run_check(out=bad)
        self.assertIn("value_format_reserved_bits", c, text)

    def test_output_value_format_must_be_x_advance_only(self):
        out = synth.standin_write(self.orig, "pos A V <10 0 0 0>;\npos V A -30;")
        text, c = self.run_check(declared=[Declared("A", "V", 10, 10, "written"), PAIRS[1]], out=out)
        self.assertIn("value_format1_not_x_advance_only", c, text)
        def m(t):
            from fontTools.ttLib.tables.otTables import ValueRecord
            st = t.LookupList.Lookup[0].SubTable[0]
            st.ValueFormat2 = 0x0004
            for ps in st.PairSet:
                for r in ps.PairValueRecord:
                    r.Value2 = ValueRecord()
                    r.Value2.XAdvance = 5
        out = synth.standin_write_mutated(self.orig, "pos A V -80;", m)
        _, c = self.run_check(declared=[Declared("A", "V", -80, -80, "written")], out=out)
        self.assertIn("value_format2_not_zero", c)

    def test_original_other_format_is_information_only(self):
        orig = synth.standin_write(self.orig, "pos A V <0 0 0 -50>;")
        text, c = self.run_check(orig=orig, compare_original=True)
        self.assertEqual(c, [], text)
        self.assertIn("original_value_format info=differs_from_output_contract lookup=0 format=1 ValueFormat1=0x0008", text)
        text2, c2 = self.run_check(compare_original=True, orig=self.orig)
        self.assertNotIn("original_value_format", text2)

    def test_lookup_flag_req_feature_and_params(self):
        def m(t):
            t.LookupList.Lookup[0].LookupFlag = 8
            ls = t.ScriptList.ScriptRecord[0].Script.DefaultLangSys
            ls.ReqFeatureIndex = 0
        out = synth.standin_write_mutated(self.orig, FEA, m)
        text, c = self.run_check(out=out)
        self.assertIn("lookup_flag_nonstandard", c, text)
        self.assertIn("req_feature_index_set", c, text)

    def test_feature_params_raw(self):
        def m(d):
            fl = struct.unpack(">H", d[6:8])[0]
            ft = fl + struct.unpack(">H", d[fl + 6:fl + 8])[0]
            d[ft:ft + 2] = struct.pack(">H", 4)
        text, c = self.run_check(out=patch_gpos(self.out, m))
        self.assertEqual(c.count("feature_params_present"), 1, text)

    def test_lookup_index_out_of_range(self):
        def m(t):
            t.FeatureList.FeatureRecord[0].Feature.LookupListIndex.append(9)
            t.FeatureList.FeatureRecord[0].Feature.LookupCount = 2
        out = synth.standin_write_mutated(self.orig, FEA, m)
        text, c = self.run_check(out=out)
        self.assertIn("lookup_index_out_of_range", c, text)
        self.assertNotIn("check_aborted", c)

    def test_classdef_class_out_of_range(self):
        fea = "@L = [A];\n@R = [V];\npos @L @R -80;"
        out = synth.standin_write(self.orig, fea)

        def m(t):
            st = t.LookupList.Lookup[0].SubTable[0]
            st.ClassDef1.classDefs["A"] = 3
        out = synth.standin_write_mutated(self.orig, fea, m)
        d = [Declared("A", "V", -80, -80, "written")]
        text, c = self.run_check(declared=d, out=out)
        self.assertIn("classdef_class_out_of_range", c, text)
        self.assertIn("skipped_class_index_out_of_range", text)
        self.assertNotIn("hb_value_mismatch", c)


TWO = "lookup l_a { pos A V -80; } l_a;\nlookup l_b { pos V A -30; } l_b;"


def add_langsys(t, lookups):
    import copy
    from fontTools.ttLib.tables import otTables as ot
    fl = t.FeatureList
    f0 = fl.FeatureRecord[0]
    f0.Feature.LookupListIndex = [0]
    f0.Feature.LookupCount = 1
    f1 = copy.deepcopy(f0)
    f1.Feature.LookupListIndex = list(lookups)
    f1.Feature.LookupCount = len(lookups)
    fl.FeatureRecord.append(f1)
    fl.FeatureCount = 2
    sr = t.ScriptList.ScriptRecord[0]
    lr = ot.LangSysRecord()
    lr.LangSysTag = "TRK "
    lr.LangSys = copy.deepcopy(sr.Script.DefaultLangSys)
    lr.LangSys.FeatureIndex = [1]
    lr.LangSys.FeatureCount = 1
    sr.Script.LangSysRecord.append(lr)
    sr.Script.LangSysCount = len(sr.Script.LangSysRecord)


class LookupAndLanguageSystem(Base):
    def test_structure_line_for_one_lookup(self):
        text, c = self.run_check()
        self.assertEqual(c, [])
        self.assertIn("gpos_structure lookups=1 features=1 kern_features=1 language_systems=1 distinct_kern_lookup_sets=1", text)

    def test_output_with_two_lookups_is_a_finding(self):
        out = synth.standin_write_mutated(self.orig, TWO, lambda t: None)
        text, c = self.run_check(out=out)
        self.assertIn("output_lookup_count_not_one", c, text)
        self.assertIn("gpos_structure lookups=2", text)
        self.assertNotIn("language_system_mismatch", c)

    def test_original_with_two_lookups_is_information_only(self):
        orig = synth.standin_write_mutated(self.orig, TWO, lambda t: None)
        text, c = self.run_check(orig=orig, compare_original=True)
        self.assertEqual(c, [], text)
        self.assertIn("original_gpos_structure lookups=2", text)

    def test_language_system_with_other_kern_lookup_is_a_mismatch(self):
        out = synth.standin_write_mutated(self.orig, TWO, lambda t: add_langsys(t, [1]))
        text, c = self.run_check(out=out)
        self.assertIn("language_system_mismatch", c, text)
        self.assertIn("language_systems=2 distinct_kern_lookup_sets=2", text)
        detail = [d for code, d in check(self.orig, out, PAIRS)[1] if code == "language_system_mismatch"][0]
        self.assertIn("pairs differ", detail)

    def test_language_systems_with_the_same_lookups_do_not_mismatch(self):
        out = synth.standin_write_mutated(self.orig, TWO, lambda t: add_langsys(t, [0]))
        text, c = self.run_check(out=out)
        self.assertNotIn("language_system_mismatch", c, text)
        self.assertIn("language_systems=2 distinct_kern_lookup_sets=1", text)

if __name__ == "__main__":
    unittest.main()
