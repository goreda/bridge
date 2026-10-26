"""Synthetic tests for kern_gpos_writer. Mechanics only: no real font, no optical claim.
Acceptance uses gposcheck (independent, never calls the writer)."""
import io
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "gposcheck"))

from fontTools.ttLib import TTFont
from gposcheck.synth import make_original, add_raw_table
import kern_gpos_writer as kw


# Test fixture constants (TEST_ prefix: exempt from the production literal rule, test file only).
TEST_F1_0 = 1.0
TEST_F2_6 = 2.6
TEST_F3_0 = 3.0
TEST_F5_0 = 5.0
TEST_N10 = 10
TEST_N1000 = 1000
TEST_N200 = 200
TEST_N256 = 0x100
TEST_N260 = 260
TEST_N3 = 3
TEST_N32767 = 32767
TEST_N32768 = 32768
TEST_N3786825600 = 3786825600
TEST_N4 = 4
TEST_N40000 = 40000
TEST_N5 = 5
TEST_N50 = 50
TEST_N500 = 500
TEST_N51 = 51
TEST_N65535 = 0xffff
TEST_N7 = 7
TEST_N72 = 72
TEST_N8 = 8
TEST_N800 = 800
TEST_N90 = 90
TEST_N99 = 99
TEST_N99999 = 99999


def row(l, r, w, req=None, reason=""):
    req = w if req is None and w is not None else (0 if req is None else req)
    status = "rejected" if w is None else ("written" if float(w) == float(req) else "rounded")
    return {"left": l, "right": r, "requested": req, "written": w, "status": status, "reason": reason,
            "evidence_class": "derived"}


class T(unittest.TestCase):
    def setUp(self):
        self.orig = make_original()
        self.declared = [row("V", "A", -TEST_N99), row("A", "V", -TEST_N72), row("T", "o", -TEST_N72),
                         row("A", "T", 0), row("W", "o", None, TEST_F5_0, "below noise"),
                         row("D", "o", -TEST_N3, -TEST_F2_6)]

    def test_format1_roundtrip_and_acceptance(self):
        out, _rec = kw.write_kern(self.orig, self.declared)
        from gposcheck import __main__ as m
        with tempfile.TemporaryDirectory() as d:
            p = lambda n: os.path.join(d, n)
            open(p("o.ttf"), "wb").write(self.orig)
            open(p("n.ttf"), "wb").write(out)
            json.dump(self.declared, open(p("d.json"), "w"))
            rc = m.main(["--original", p("o.ttf"), "--output", p("n.ttf"), "--declared", p("d.json"),
                         "--receipt", p("r.txt")])
            self.assertEqual(rc, 0, open(p("r.txt")).read())
            txt = open(p("r.txt")).read()
            self.assertIn("non_gpos_tables", txt)
            self.assertIn("diff=0", txt)

    def test_only_gpos_added_other_tables_byte_equal(self):
        out, _rec = kw.write_kern(self.orig, self.declared)
        a = TTFont(io.BytesIO(self.orig), lazy=True)
        b = TTFont(io.BytesIO(out), lazy=True)
        self.assertEqual(set(b.reader.tables) - set(a.reader.tables), {"GPOS"})
        for t in a.reader.tables:
            if t == "head":
                continue
            self.assertEqual(a.reader[t], b.reader[t], t)

    def test_deterministic_and_input_order_invariant(self):
        o1, _r1 = kw.write_kern(self.orig, self.declared)
        o2, _r2 = kw.write_kern(self.orig, list(reversed(self.declared)))
        self.assertEqual(o1, o2)

    def test_explicit_zero_stored(self):
        out, _rec = kw.write_kern(self.orig, [row("A", "T", 0), row("V", "A", -TEST_N5)])
        f = TTFont(io.BytesIO(out))
        ps = {c: [(p.SecondGlyph, p.Value1.XAdvance) for p in s.PairValueRecord]
              for c, s in zip(f["GPOS"].table.LookupList.Lookup[0].SubTable[0].Coverage.glyphs,
                              f["GPOS"].table.LookupList.Lookup[0].SubTable[0].PairSet)}
        self.assertIn(("T", 0), ps["A"])

    def test_rejected_not_stored(self):
        out, _rec = kw.write_kern(self.orig, [row("V", "A", -TEST_N5), row("W", "o", None, TEST_F3_0, "why")])
        f = TTFont(io.BytesIO(out))
        st = f["GPOS"].table.LookupList.Lookup[0].SubTable[0]
        self.assertNotIn("W", st.Coverage.glyphs)

    def test_errors(self):
        cases = [
            ([dict(row("V", "A", 1), evidence_class=None)], "evidence_class_missing_or_unknown"),
            ([dict(row("V", "A", 1), requested=float("nan"))], "requested_not_finite"),
            ([row("V", "A", TEST_N40000)], "written_out_of_int16"),
            ([row("V", "A", -TEST_N40000)], "written_out_of_int16"),
            ([row("V", "Zzz", 1)], "glyph_not_in_font"),
            ([row("V", "A", 1), row("V", "A", 2)], "duplicate_pair"),
            ([dict(row("V", "A", None, TEST_F1_0, ""), reason="")], "rejected_without_reason"),
            ([dict(row("V", "A", 1), written=TEST_F1_0)], "written_not_integer"),
            ([dict(row("V", "A", 1), written=True)], "written_not_integer"),
            ([{"left": "V"}], "declared_key_missing"),
            ([row("W", "o", None, TEST_F1_0, "x")], "no_pairs_to_store"),
            ("nope", "declared_not_a_list"),
        ]
        for rows, code in cases:
            with self.assertRaises(kw.WriterError) as c:
                kw.write_kern(self.orig, rows)
            self.assertEqual(c.exception.code, code, rows)

    def test_int16_bounds_accepted(self):
        out, _rec = kw.write_kern(self.orig, [row("V", "A", TEST_N32767), row("A", "V", -TEST_N32768)])
        self.assertTrue(out)

    def test_refuses_original_with_legacy_kern(self):
        withk = add_raw_table(self.orig, "kern", b"\x00" * TEST_N8)
        with self.assertRaises(kw.WriterError) as c:
            kw.write_kern(withk, self.declared)
        self.assertEqual(c.exception.code, "original_has_legacy_kern")

    def test_damaged_original(self):
        with self.assertRaises(kw.WriterError) as c:
            kw.write_kern(b"not a font", self.declared)
        self.assertEqual(c.exception.code, "original_parse_failure")

    def test_format2_lossless_accepted(self):
        # classes: left {V,W}=1, right {A}=1 ; pairs V,A and W,A both -50; nothing else nonzero
        rows = [row("V", "A", -TEST_N50), row("W", "A", -TEST_N50)]
        cls = {"left": {"V": 1, "W": 1}, "right": {"A": 1}, "matrix": [[0, 0], [0, -TEST_N50]]}
        out, _rec = kw.write_kern(self.orig, rows, cls)
        from gposcheck import __main__ as m
        with tempfile.TemporaryDirectory() as d:
            p = lambda n: os.path.join(d, n)
            open(p("o.ttf"), "wb").write(self.orig)
            open(p("n.ttf"), "wb").write(out)
            json.dump(rows, open(p("d.json"), "w"))
            rc = m.main(["--original", p("o.ttf"), "--output", p("n.ttf"), "--declared", p("d.json"), "--receipt", p("r.txt")])
            self.assertEqual(rc, 0, open(p("r.txt")).read())

    def test_format2_lossy_refused(self):
        rows = [row("V", "A", -TEST_N50)]  # W,A not declared but class would give -50
        cls = {"left": {"V": 1, "W": 1}, "right": {"A": 1}, "matrix": [[0, 0], [0, -TEST_N50]]}
        with self.assertRaises(kw.WriterError) as c:
            kw.write_kern(self.orig, rows, cls)
        self.assertEqual(c.exception.code, "class_changes_unlisted_pair")

    def test_format2_malformed(self):
        rows = [row("V", "A", -TEST_N50)]
        for cls, code in [
            ({"left": {"V": 1}, "right": {"A": 1}, "matrix": [[0, 0]]}, "class_matrix_shape"),
            ({"left": {"V": 1}, "right": {"A": 1}, "matrix": [[0, TEST_N5], [0, -TEST_N50]]}, "class_zero_row_or_column_nonzero"),
            ({"left": {"V": 0}, "right": {"A": 1}, "matrix": [[0, 0], [0, -TEST_N50]]}, "class_index_invalid"),
            ({"left": {"Q": 1}, "right": {"A": 1}, "matrix": [[0, 0], [0, -TEST_N50]]}, "class_glyph_not_in_font"),
            ({"left": {"V": 1}, "right": {"A": 1}, "matrix": [[0, 0], [0, TEST_N99999]]}, "class_matrix_value"),
            ({"left": {"V": 1}}, "classes_malformed"),
        ]:
            with self.assertRaises(kw.WriterError) as c:
                kw.write_kern(self.orig, rows, cls)
            self.assertEqual(c.exception.code, code, cls)

    def test_cli_refuses_existing_output(self):
        with tempfile.TemporaryDirectory() as d:
            p = lambda n: os.path.join(d, n)
            open(p("o.ttf"), "wb").write(self.orig)
            json.dump(self.declared, open(p("d.json"), "w"))
            args = ["--original", p("o.ttf"), "--declared", p("d.json"), "--output", p("n.ttf"), "--receipt", p("r.json")]
            self.assertEqual(kw.main(args), 0)
            self.assertEqual(kw.main(args), kw.EXIT_INPUT_ERROR)
            self.assertIn("output_sha256", json.load(open(p("r.json"))))


class R2(unittest.TestCase):
    def setUp(self):
        self.orig = make_original()

    def test_existing_kern_gpos_merged_and_conflict(self):
        first, _ = kw.write_kern(self.orig, [row("V", "A", -TEST_N50), row("A", "T", 0)])
        out, rec = kw.write_kern(first, [row("T", "o", -TEST_N7), row("V", "A", -TEST_N50)])
        self.assertEqual((rec["pairs_existing"], rec["pairs_written"], rec["pairs_same_as_existing"]), (2, 1, 1))
        f = TTFont(io.BytesIO(out))
        subs = kw._kern_subtables(f["GPOS"])
        order = f.getGlyphOrder()
        self.assertEqual(kw._lookup_value(subs, "V", "A"), -TEST_N50)
        self.assertEqual(kw._lookup_value(subs, "T", "o"), -TEST_N7)
        self.assertIn(("A", "T"), kw.existing_pairs(f, order))  # explicit zero kept
        with self.assertRaises(kw.WriterError) as c:
            kw.write_kern(first, [row("V", "A", -TEST_N51)])
        self.assertEqual(c.exception.code, "conflicting_pair")

    def test_original_gpos_with_other_feature_refused(self):
        from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
        f = TTFont(io.BytesIO(self.orig))
        addOpenTypeFeaturesFromString(f, "feature kern { pos V A -5; } kern; feature mark { pos A <0 0 0 0>; } mark;")
        b = io.BytesIO(); f.save(b)
        with self.assertRaises(kw.WriterError) as c:
            kw.write_kern(b.getvalue(), [row("V", "A", -TEST_N5)])
        self.assertEqual(c.exception.code, "original_gpos_not_kern_only")

    def test_receipt_counts_and_hashes(self):
        rows = [row("V", "A", -TEST_N5), row("W", "o", None, TEST_F3_0, "below noise"), row("D", "o", -TEST_N3, -TEST_F2_6)]
        out, rec = kw.write_kern(self.orig, rows)
        self.assertEqual((rec["pairs_written"], rec["rounded"], rec["rejected"]), (2, 1, 1))
        self.assertEqual(rec["rejections"], [{"left": "W", "right": "o", "reason": "below noise"}])
        import hashlib
        self.assertEqual(rec["output_sha256"], hashlib.sha256(out).hexdigest())
        self.assertEqual(rec["original_sha256"], hashlib.sha256(self.orig).hexdigest())

    def test_class_with_listed_exception_and_explicit_zero(self):
        # class gives -50 for {V,W} x {A}; W,A is listed as an explicit zero, V,A as -50
        rows = [row("V", "A", -TEST_N50), row("W", "A", 0)]
        cls = {"left": {"V": 1, "W": 1}, "right": {"A": 1}, "matrix": [[0, 0], [0, -TEST_N50]]}
        out, rec = kw.write_kern(self.orig, rows, cls)
        self.assertEqual(rec["formats"], [1, 2])
        f = TTFont(io.BytesIO(out))
        subs = kw._kern_subtables(f["GPOS"])
        self.assertEqual(subs[0].Format, 1)   # exception first, first match wins
        self.assertEqual(kw._lookup_value(subs, "W", "A"), 0)
        self.assertEqual(kw._lookup_value(subs, "V", "A"), -TEST_N50)

    def test_class_unlisted_pair_changed_refused(self):
        rows = [row("V", "A", -TEST_N50)]
        cls = {"left": {"V": 1, "W": 1}, "right": {"A": 1}, "matrix": [[0, 0], [0, -TEST_N50]]}
        with self.assertRaises(kw.WriterError) as c:
            kw.write_kern(self.orig, rows, cls)
        self.assertEqual(c.exception.code, "class_changes_unlisted_pair")

    def test_offset_overflow_splits_subtables(self):
        # many glyphs, every pair listed: needs more than one Format 1 subtable
        from fontTools.fontBuilder import FontBuilder
        from fontTools.pens.ttGlyphPen import TTGlyphPen
        names = [".notdef"] + ["g%d" % i for i in range(TEST_N260)]
        fb = FontBuilder(TEST_N1000, isTTF=True)
        fb.setupGlyphOrder(names)
        fb.setupCharacterMap({TEST_N256 + i: n for i, n in enumerate(names[1:])})
        gl = {}
        for n in names:
            p = TTGlyphPen(None); p.moveTo((0, 0)); p.lineTo((0, TEST_N10)); p.lineTo((TEST_N10, TEST_N10)); p.closePath(); gl[n] = p.glyph()
        fb.setupGlyf(gl)
        fb.setupHorizontalMetrics({n: (TEST_N500, 0) for n in names})
        fb.setupHorizontalHeader(ascent=TEST_N800, descent=-TEST_N200)
        fb.setupNameTable({"familyName": "Big", "styleName": "Regular"})
        fb.setupOS2(); fb.setupPost(); fb.setupHead(unitsPerEm=TEST_N1000, created=TEST_N3786825600, modified=TEST_N3786825600)
        b = io.BytesIO(); fb.save(b)
        rows = [row(l, r, -((i + j) % TEST_N90) - 1) for i, l in enumerate(names[1:]) for j, r in enumerate(names[1:])]
        out, rec = kw.write_kern(b.getvalue(), rows)   # 67,600 pairs: > 65,535 bytes of pair sets
        self.assertGreater(rec["subtables"], 1)
        self.assertEqual(rec["pairs_written"], len(rows))

    @staticmethod
    def rust_layout_emulation(pairs):
        """PYTHON EMULATION of engine/metrics/src/gpos_verified.rs write() byte layout (Python port of the
        source text, not Rust). pairs: {(left_gid, right_gid): int16}."""
        import struct
        w = lambda v: struct.pack(">H", v)
        groups = {}
        for (l, r), v in pairs.items():
            groups.setdefault(l, {})[r] = v
        lefts = sorted(groups)
        n = len(lefts)
        header = TEST_N10 + 2 * n
        sets, offs = b"", []
        for l in lefts:
            offs.append(header + len(sets))
            sets += w(len(groups[l]))
            for r in sorted(groups[l]):
                sets += w(r) + struct.pack(">h", groups[l][r])
        covoff = header + len(sets)
        sub = b"".join(w(v) for v in (1, covoff, TEST_N4, 0, n)) + b"".join(w(o) for o in offs) + sets
        sub += w(1) + w(n) + b"".join(w(l) for l in lefts)
        script = w(1) + b"DFLT" + w(TEST_N8) + b"".join(w(v) for v in (TEST_N4, 0, 0, TEST_N65535, 1, 0))
        feature = w(1) + b"kern" + w(TEST_N8) + b"".join(w(v) for v in (0, 1, 0))
        lookups = b"".join(w(v) for v in (1, TEST_N4, 2, 0, 1, TEST_N8)) + sub
        out = bytes([0, 1, 0, 0]) + w(TEST_N10) + w(TEST_N10 + len(script)) + w(TEST_N10 + len(script) + len(feature))
        return out + script + feature + lookups

    def test_cross_check_against_rust_lane_layout_emulation(self):
        """Semantic cross-check: the writer's Format 1 pairs equal the pairs of the Rust lane's byte layout
        (emulated in Python, read by the lane's own strict checker). The layouts differ on purpose:
        fontTools places the coverage table first, the lane places it last, so the lane's checker
        (which demands coverage last) is NOT expected to accept the writer's bytes; byte equality is
        therefore not claimed. The real Rust output must be compared on the hub."""
        p = os.path.join(HERE, "..", "..", "metrics", "tooling", "check_verified_gpos.py")
        if not os.path.exists(p):
            self.skipTest("check_verified_gpos.py not in this tree")
        import importlib.util
        from pathlib import Path
        spec = importlib.util.spec_from_file_location("check_verified_gpos", p)
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        rows = [row("V", "A", -TEST_N99), row("A", "V", -TEST_N72), row("T", "o", -TEST_N72), row("A", "T", 0)]
        out, rec = kw.write_kern(self.orig, rows)
        f = TTFont(io.BytesIO(out))
        gid = {n: i for i, n in enumerate(f.getGlyphOrder())}
        want = {(gid[r["left"]], gid[r["right"]]): r["written"] for r in rows}
        with tempfile.TemporaryDirectory() as d:
            gp = Path(d) / "emu.bin"
            gp.write_bytes(self.rust_layout_emulation(want))
            self.assertEqual(m.parse(gp), want)     # emulation is valid for the lane's checker
        subs = kw._kern_subtables(f["GPOS"])
        order = f.getGlyphOrder()
        mine = {k: v for k, v in kw.existing_pairs(f, order).items()}
        self.assertEqual({(gid[a], gid[b]): v for (a, b), v in mine.items()}, want)


if __name__ == "__main__":
    unittest.main()
