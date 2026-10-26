"""Negative-path tests for the v2 checker additions. Each case feeds an input that must be reported."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from gposcheck import check, Declared, synth  # noqa: E402
from gposcheck.__main__ import main as cli_main  # noqa: E402

FEA = "pos A V -80;\npos V A -30;\npos T o -60;\npos o T -20;"
PAIRS = {("A", "V"): -80, ("V", "A"): -30, ("T", "o"): -60, ("o", "T"): -20}


def decl(pairs):
    return [Declared(l, r, v, v, "written") for (l, r), v in pairs.items()]


def run(orig, out, pairs, **kw):
    text, findings, _ = check(orig, out, decl(pairs), **kw)
    return text, [f[0] for f in findings]


class Int16Declared(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.standin_write(self.orig, FEA)

    def codes(self, value):
        d = decl(PAIRS)
        d[0].requested, d[0].written = value, value
        _, findings, _ = check(self.orig, self.out, d)
        return [f[0] for f in findings]

    def test_just_outside_the_range_both_ends(self):
        self.assertIn("written_out_of_int16", self.codes(32768))
        self.assertIn("written_out_of_int16", self.codes(-32769))

    def test_range_ends_are_not_reported_as_out_of_range(self):
        self.assertNotIn("written_out_of_int16", self.codes(32767))
        self.assertNotIn("written_out_of_int16", self.codes(-32768))

    def test_non_integer_written_value(self):
        for v in (0.5, -0.25, 1e-9):
            self.assertIn("written_not_integer", self.codes(v), repr(v))


class MalformedFormat1(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()

    def test_pairset_missing_for_a_coverage_glyph(self):
        def m(t):
            st = t.LookupList.Lookup[0].SubTable[0]
            st.PairSet.pop()
            st.PairSetCount = len(st.PairSet)
        out = synth.standin_write_mutated(self.orig, "pos A V -80;\npos V A -30;", m)
        _, codes = run(self.orig, out, {("A", "V"): -80, ("V", "A"): -30})
        self.assertIn("pairset_count_mismatch", codes)

    def test_unsorted_coverage(self):
        def m(t):
            st = t.LookupList.Lookup[0].SubTable[0]
            st.Coverage.glyphs = list(reversed(st.Coverage.glyphs))
            st.PairSet = list(reversed(st.PairSet))
        try:
            out = synth.standin_write_mutated(self.orig, "pos A V -80;\npos V A -30;", m)
        except Exception as e:
            self.skipTest("compiler refuses the mutation: %r" % (e,))
        _, codes = run(self.orig, out, {("A", "V"): -80, ("V", "A"): -30})
        self.assertIn("coverage_unsorted_or_unknown", codes)


class Enumeration(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.standin_write(self.orig, FEA)

    def test_limit_equal_to_glyph_count_is_complete(self):
        text, codes = run(self.orig, self.out, PAIRS, enumeration_limit=11)
        self.assertEqual(codes, [], text)
        self.assertIn("complete=true", text)

    def test_one_below_glyph_count_fails(self):
        text, codes = run(self.orig, self.out, PAIRS, enumeration_limit=10)
        self.assertIn("not_enumerated", codes)
        self.assertIn("complete=false", text)

    def test_original_over_limit_is_reported_in_comparison(self):
        orig = synth.standin_write(self.orig, "pos A V -80;")
        out = synth.standin_write(self.orig, "pos A V -80;")
        text, codes = run(orig, out, {("A", "V"): -80}, compare_original=True, enumeration_limit=5)
        self.assertGreaterEqual(codes.count("not_enumerated"), 1)


class LegacyKern(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.add_raw_table(synth.standin_write(self.orig, FEA), "kern", b"\x00\x00\x00\x00")

    def test_added_legacy_kern_is_a_finding_even_when_the_diff_tag_is_allowed(self):
        _, codes = run(self.orig, self.out, PAIRS, allow_diff_tags=("kern",))
        self.assertIn("legacy_kern_table_present", codes)

    def test_empty_reason_does_not_allow_it(self):
        _, codes = run(self.orig, self.out, PAIRS, allow_diff_tags=("kern",), allow_legacy_kern="")
        self.assertIn("legacy_kern_table_present", codes)

    def test_added_kern_without_diff_allowance_also_fails_as_table_diff(self):
        _, codes = run(self.orig, self.out, PAIRS)
        self.assertIn("non_gpos_table_differs", codes)
        self.assertIn("legacy_kern_table_present", codes)


class OriginalComparison(unittest.TestCase):
    def setUp(self):
        self.base = synth.make_original()
        self.orig = synth.standin_write(self.base, "pos A V -80;\npos B V -10;")
        self.out = synth.standin_write(self.base, "pos A V -80;")
        self.pairs = {("A", "V"): -80}

    def test_dropped_pair_is_only_reported_without_the_flag(self):
        text, codes = run(self.orig, self.out, self.pairs, compare_original=True)
        self.assertNotIn("original_pair_dropped", codes)
        self.assertIn("status=dropped pair=B,V original=-10", text)
        self.assertIn("mode=report_only", text)

    def test_dropped_pair_is_a_finding_with_the_flag(self):
        text, codes = run(self.orig, self.out, self.pairs, compare_original=True, original_drop_is_finding=True)
        self.assertEqual(codes, ["original_pair_dropped"])
        self.assertIn("mode=dropped_is_finding", text)

    def test_drop_flag_without_comparison_prints_no_comparison_line(self):
        text, codes = run(self.orig, self.out, self.pairs, original_drop_is_finding=True)
        self.assertNotIn("original_effective", text)

    def test_every_dropped_pair_gets_its_own_finding(self):
        orig = synth.standin_write(self.base, "pos A V -80;\npos B V -10;\npos C W -5;\npos D Y -7;")
        _, codes = run(orig, self.out, self.pairs, compare_original=True, original_drop_is_finding=True)
        self.assertEqual(codes.count("original_pair_dropped"), 3)

    def test_changed_pair_is_listed_with_both_values(self):
        out = synth.standin_write(self.base, "pos A V -70;\npos B V -10;")
        text, _ = run(self.orig, out, {("A", "V"): -70}, compare_original=True, original_drop_is_finding=True)
        self.assertIn("status=changed pair=A,V original=-80 output=-70", text)

    def test_added_pair_is_listed(self):
        out = synth.standin_write(self.base, "pos A V -80;\npos B V -10;\npos C W -5;")
        text, _ = run(self.orig, out, {("A", "V"): -80, ("C", "W"): -5}, compare_original=True)
        self.assertIn("status=added pair=C,W output=-5", text)

    def test_original_gpos_defect_is_reported_with_the_original_prefix(self):
        def m(t):
            ps = t.LookupList.Lookup[0].SubTable[0].PairSet[0]
            ps.PairValueRecord.reverse()
        orig = synth.standin_write_mutated(self.base, "pos A V -80;\npos A W -50;", m)
        out = synth.standin_write(self.base, "pos A V -80;\npos A W -50;")
        _, codes = run(orig, out, {("A", "V"): -80, ("A", "W"): -50}, compare_original=True)
        self.assertIn("original_pairset_second_glyph_not_ascending", codes)


class Sequences(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.standin_write(self.orig, FEA)

    def test_expected_kern_wrong_on_one_position(self):
        _, codes = run(self.orig, self.out, PAIRS, sequences=[{"text": "AVA", "expected_kern": [-80, 0, 0]}])
        self.assertEqual(codes, ["sequence_mismatch"])

    def test_expected_kern_wrong_length(self):
        _, codes = run(self.orig, self.out, PAIRS, sequences=[{"text": "AVA", "expected_kern": [-80, -30]}])
        self.assertIn("sequence_mismatch", codes)

    def test_single_character_sequence_is_not_shapable(self):
        _, codes = run(self.orig, self.out, PAIRS, sequences=["A"])
        self.assertIn("sequence_not_shapable", codes)

    def test_character_without_cmap_entry(self):
        orig = synth.make_original(nocmap=("V",))
        out = synth.standin_write(orig, FEA)
        _, codes = run(orig, out, PAIRS, sequences=["AVA"])
        self.assertIn("sequence_not_shapable", codes)

    def test_each_bad_sequence_counts_once(self):
        text, codes = run(self.orig, self.out, PAIRS,
                          sequences=["AVA", {"text": "ToT", "expected_kern": [0, 0, 0]}, "A"])
        self.assertIn("sequences total=3 mismatches=2", text)


class CliModes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        base = synth.make_original()
        self.p = lambda n: os.path.join(t, n)
        self.write("o.ttf", synth.standin_write(base, "pos A V -80;\npos B V -10;"), "wb")
        self.write("n.ttf", synth.standin_write(base, "pos A V -80;"), "wb")
        self.write("d.json", json.dumps([{"left": "A", "right": "V", "requested": -80, "written": -80,
                                         "status": "written", "reason": ""}]), "w")
        self.argv = ["--original", self.p("o.ttf"), "--output", self.p("n.ttf"), "--declared", self.p("d.json"),
                     "--receipt", self.p("r.txt")]

    def write(self, name, data, mode):
        with open(self.p(name), mode) as f:
            f.write(data)

    def tearDown(self):
        self.tmp.cleanup()

    def cli(self, extra):
        with contextlib.redirect_stdout(io.StringIO()):
            rc = cli_main(self.argv + extra)
        with open(self.p("r.txt")) as f:
            return rc, f.read()

    def test_report_only_comparison_exits_zero(self):
        rc, text = self.cli(["--compare-original"])
        self.assertEqual(rc, 0, text)
        self.assertIn("mode=report_only", text)

    def test_drop_is_finding_exits_one_and_names_the_mode(self):
        rc, text = self.cli(["--compare-original", "--original-drop-is-finding"])
        self.assertEqual(rc, 1)
        self.assertIn("mode=dropped_is_finding", text)
        self.assertTrue(text.endswith("verdict=FAIL findings=1\n"))

    def test_enumeration_limit_option_fails_the_run(self):
        rc, text = self.cli(["--enumeration-limit", "3"])
        self.assertEqual(rc, 1)
        self.assertIn("not_enumerated", text)

    def test_sequences_file_mismatch_exits_one(self):
        self.write("s.json", json.dumps([{"text": "AVA", "expected_kern": [1, 0, 0]}]), "w")
        rc, text = self.cli(["--sequences", self.p("s.json")])
        self.assertEqual(rc, 1)
        self.assertIn("sequence_mismatch", text)

    def test_receipt_version_line(self):
        _, text = self.cli([])
        self.assertEqual(text.splitlines()[0], "gposcheck-receipt-v2")


if __name__ == "__main__":
    unittest.main()
