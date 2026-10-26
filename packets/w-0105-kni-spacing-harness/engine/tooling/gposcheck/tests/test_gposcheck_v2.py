"""Checks for the additions (G-1, G-2, int16, legacy kern, original comparison, sequences)."""
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from gposcheck import check, Declared, synth  # noqa: E402


def decl(pairs):
    return [Declared(l, r, v, v, "written") for (l, r), v in pairs.items()]


def run(orig, out, pairs, **kw):
    text, findings, _ = check(orig, out, decl(pairs), **kw)
    return text, [f[0] for f in findings]


FEA = "pos A V -80;\npos V A -30;\npos T o -60;\npos o T -20;"
PAIRS = {("A", "V"): -80, ("V", "A"): -30, ("T", "o"): -60, ("o", "T"): -20}


class V2(unittest.TestCase):
    def setUp(self):
        self.orig = synth.make_original()
        self.out = synth.standin_write(self.orig, FEA)

    def test_baseline_pass(self):
        text, codes = run(self.orig, self.out, PAIRS)
        self.assertEqual(codes, [], text)
        self.assertIn("format1 subtables=1 pairsets=", text)
        self.assertIn("enumeration glyphs=11 limit=600 limit_class=CONVENTION complete=true", text)
        self.assertIn("legacy_kern present=false original_present=false allowed=false", text)

    def test_g1_unsorted_second_glyph(self):
        def m(t):
            ps = t.LookupList.Lookup[0].SubTable[0].PairSet[0]
            ps.PairValueRecord.reverse()
        out = synth.standin_write_mutated(self.orig, "pos A V -80;\npos A W -50;", m)
        text, codes = run(self.orig, out, {("A", "V"): -80, ("A", "W"): -50})
        self.assertIn("pairset_second_glyph_not_ascending", codes)

    def test_g1_duplicate_second_glyph(self):
        def m(t):
            ps = t.LookupList.Lookup[0].SubTable[0].PairSet[0]
            ps.PairValueRecord.append(ps.PairValueRecord[-1])
            ps.PairValueCount = len(ps.PairValueRecord)
        out = synth.standin_write_mutated(self.orig, "pos A V -80;", m)
        _, codes = run(self.orig, out, {("A", "V"): -80})
        self.assertIn("pairset_duplicate_second_glyph", codes)

    def test_g1_count_mismatch(self):
        def m(t):
            t.LookupList.Lookup[0].SubTable[0].PairSet[0].PairValueCount = 5
        out = synth.standin_write_mutated(self.orig, "pos A V -80;", m)
        text, codes = run(self.orig, out, {("A", "V"): -80})
        # compile recomputes counts; the parsed table must then be consistent
        self.assertNotIn("pairvalue_count_mismatch", codes, text)

    def test_g2_over_limit_is_typed_failure_not_silent(self):
        text, codes = run(self.orig, self.out, PAIRS, enumeration_limit=5)
        self.assertIn("not_enumerated", codes)
        self.assertIn("complete=false", text)
        self.assertIn("limit=5", text)

    def test_int16_declared(self):
        d = decl(PAIRS)
        d[0].written = d[0].requested = 40000
        text, findings, _ = check(self.orig, self.out, d)
        codes = [f[0] for f in findings]
        self.assertIn("written_out_of_int16", codes)
        d[0].written = d[0].requested = -32768
        _, f2, _ = check(self.orig, self.out, d)
        self.assertNotIn("written_out_of_int16", [f[0] for f in f2])
        d[0].written = 1.5
        _, f3, _ = check(self.orig, self.out, d)
        self.assertIn("written_not_integer", [f[0] for f in f3])

    def test_legacy_kern(self):
        out = synth.add_raw_table(self.out, "kern", b"\x00\x00\x00\x00")
        text, codes = run(self.orig, out, PAIRS, allow_diff_tags=("kern",))
        self.assertIn("legacy_kern_table_present", codes)
        text2, codes2 = run(self.orig, out, PAIRS, allow_diff_tags=("kern",), allow_legacy_kern="reason text")
        self.assertEqual(codes2, [], text2)
        self.assertIn("allowed=reason=reason text", text2)
        orig_k = synth.add_raw_table(self.orig, "kern", b"\x00\x00\x00\x00")
        out_k = synth.standin_write(orig_k, FEA)
        text3, codes3 = run(orig_k, out_k, PAIRS)
        self.assertIn("legacy_kern_table_present", codes3)
        self.assertIn("original_present=true", text3)

    def test_original_comparison(self):
        orig = synth.standin_write(self.orig, "pos A V -80;\npos A W -40;\npos B V -10;")
        out = synth.standin_write(self.orig, "pos A V -80;\npos A W -60;\npos B W 0;\npos C V -20;")
        pairs = {("A", "V"): -80, ("A", "W"): -60, ("B", "W"): 0, ("C", "V"): -20}
        text, codes = run(orig, out, pairs, compare_original=True)
        self.assertEqual(codes, [], text)
        self.assertIn("original_nonzero=3 preserved=1 changed=1 dropped=1 added=1 explicit_zero_in_output=1", text)
        self.assertIn("original_pair status=dropped pair=B,V original=-10", text)
        self.assertIn("original_pair status=changed pair=A,W original=-40 output=-60", text)
        self.assertIn("original_pair status=explicit_zero_in_output pair=B,W original=0", text)
        text2, codes2 = run(orig, out, pairs, compare_original=True, original_drop_is_finding=True)
        self.assertEqual(codes2, ["original_pair_dropped"])
        self.assertIn(" mode=dropped_is_finding", text2)
        self.assertIn(" mode=report_only", text)
        text3, codes3 = run(self.orig, self.out, PAIRS, compare_original=True)
        self.assertIn("original_gpos=absent", text3)

    def test_sequences(self):
        seq = ["AVA", {"text": "ToT", "expected_kern": [-60, -20, 0]}]
        text, codes = run(self.orig, self.out, PAIRS, sequences=seq)
        self.assertEqual(codes, [], text)
        self.assertIn("sequences total=2 mismatches=0", text)
        self.assertIn("sequence text=AVA glyphs=A,V,A advances_off=[", text)
        self.assertIn("delta=[-80, -30, 0] table_delta=[-80, -30, 0]", text)
        _, c2 = run(self.orig, self.out, PAIRS, sequences=[{"text": "ToT", "expected_kern": [-1, -20, 0]}])
        self.assertIn("sequence_mismatch", c2)
        _, c3 = run(self.orig, self.out, PAIRS, sequences=["AZA"])
        self.assertIn("sequence_not_shapable", c3)


if __name__ == "__main__":
    unittest.main()
