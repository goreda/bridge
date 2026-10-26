import contextlib
import copy
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from gposcheck import check, Declared  # noqa: E402
from gposcheck import synth  # noqa: E402
from gposcheck.__main__ import main as cli_main  # noqa: E402

FEA = """
pos A V -80;
pos B W 0;
@L = [A B C];
@R = [V W];
pos @L @R -30;
"""


def declared_base():
    d = []
    for l in "ABC":
        for r in "VW":
            req, w = -30, -30
            if (l, r) == ("A", "V"):
                req, w = -80, -80
            if (l, r) == ("B", "W"):
                req, w = 0, 0
            if (l, r) == ("C", "V"):
                req, w = -29.6, -30
            d.append(Declared(l, r, req, w, "rounded" if (l, r) == ("C", "V") else "written"))
    d.append(Declared("X", "Y", 9999, None, "rejected", "out_of_range"))
    return d


def run(out=None, declared=None, original=None, **kw):
    orig = original or synth.make_original()
    out = out if out is not None else synth.standin_write(orig, FEA)
    text, findings, stats = check(orig, out, declared if declared is not None else declared_base(), **kw)
    return text, [f[0] for f in findings], stats


def patch_table(font_bytes, tag, offset_in_table, new_byte):
    from fontTools.ttLib import TTFont
    f = TTFont(io.BytesIO(font_bytes), lazy=True)
    start = f.reader.tables[tag].offset
    b = bytearray(font_bytes)
    b[start + offset_in_table] = new_byte
    return bytes(b)


class CheckerAcceptsGoodOutput(unittest.TestCase):
    def test_clean_pass_and_counts_come_from_harness(self):
        text, codes, _ = run()
        self.assertEqual(codes, [], text)
        self.assertIn("declared total=7 written=5 rounded=1 rejected=1", text)
        self.assertIn("rounding count=1 max_abs_error=0.3999999999999986", text)
        self.assertIn("verdict=PASS findings=0", text)
        self.assertIn("declared_rejected pair=X,Y requested=9999 reason=out_of_range", text)

    def test_exception_overrides_class_in_font_and_shaping(self):
        text, codes, _ = run()
        self.assertIn("harfbuzz_pair group=declared_written pair=A,V expected=-80 got=-80 ok=true", text)
        self.assertIn("harfbuzz_pair group=declared_written pair=B,W expected=0 got=0 ok=true", text)
        self.assertIn("harfbuzz declared_written_pairs=6 rejected_pairs=1 explicit_undeclared_pairs=0 mismatches=0 not_shapable=0", text)

    def test_receipt_hashes_are_of_the_actual_bytes_and_deterministic(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, FEA)
        t1, _, _ = check(orig, out, declared_base())
        t2, _, _ = check(orig, out, declared_base())
        self.assertEqual(t1, t2)
        self.assertIn("original_sha256=" + hashlib.sha256(orig).hexdigest(), t1)
        self.assertIn("output_sha256=" + hashlib.sha256(out).hexdigest(), t1)
        self.assertIn("non_gpos_tables equal=", t1)
        self.assertIn(" diff=0 ", t1)

    def test_extension_lookup_is_read(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, FEA, extension=True)
        text, codes, _ = check(orig, out, declared_base())
        self.assertEqual([c[0] for c in codes], [], text)
        self.assertNotIn("extension_subtables=0", text)

    def test_deterministic_synthetic_font(self):
        self.assertEqual(synth.make_original(), synth.make_original())


class CheckerRejectsBadOutput(unittest.TestCase):
    def test_declared_value_wrong(self):
        d = declared_base()
        d[0].written = -70
        d[0].requested = -70
        _, codes, _ = run(declared=d)
        self.assertIn("roundtrip_value_mismatch", codes)
        self.assertIn("hb_value_mismatch", codes)

    def test_rejected_pair_present_in_font(self):
        d = declared_base()
        d[0] = Declared("A", "V", -80, None, "rejected", "writer_says_dropped")
        _, codes, _ = run(declared=d)
        self.assertIn("rejected_pair_present", codes)

    def test_undeclared_nonzero_pair(self):
        d = declared_base()[:-2] + declared_base()[-1:]
        _, codes, _ = run(declared=d)
        self.assertIn("undeclared_nonzero_pair", codes)

    def test_status_mismatch(self):
        d = declared_base()
        d[4].status = "written"
        _, codes, _ = run(declared=d)
        self.assertIn("status_mismatch", codes)

    def test_rejected_without_reason(self):
        d = declared_base()
        d[-1].reason = ""
        _, codes, _ = run(declared=d)
        self.assertIn("rejected_without_reason", codes)

    def test_duplicate_declared_pair(self):
        d = declared_base() + [copy.copy(declared_base()[0])]
        _, codes, _ = run(declared=d)
        self.assertIn("duplicate_declared_pair", codes)

    def test_non_gpos_table_changed(self):
        orig = synth.make_original()
        out = patch_table(synth.standin_write(orig, FEA), "hmtx", 6, 0x7F)
        text, codes, _ = run(out=out, original=orig)
        self.assertIn("non_gpos_table_differs", codes)
        self.assertIn("non_gpos_diff tag=hmtx kind=changed", text)

    def test_non_gpos_diff_can_be_allowed_explicitly(self):
        orig = synth.make_original()
        out = patch_table(synth.standin_write(orig, FEA), "hmtx", 6, 0x7F)
        text, codes, _ = run(out=out, original=orig, allow_diff_tags=("hmtx",))
        self.assertEqual(codes, [], text)
        self.assertIn("non_gpos_diff tag=hmtx kind=changed", text)
        self.assertIn("allowed=true", text)

    def test_gpos_missing(self):
        orig = synth.make_original()
        _, codes, _ = run(out=orig, original=orig)
        self.assertIn("gpos_missing", codes)

    def test_glyph_without_cmap_is_counted_not_dropped(self):
        orig = synth.make_original(nocmap=("V",))
        out = synth.standin_write(orig, FEA)
        text, codes, _ = run(out=out, original=orig)
        self.assertIn("hb_not_shapable_no_cmap", codes)
        self.assertIn("result=not_shapable_no_cmap", text)

    def test_unparsable_output(self):
        text, codes, _ = run(out=b"not a font")
        self.assertEqual(codes, ["parse_failure"])

    def test_wrong_feature_tag_is_not_accepted(self):
        orig = synth.make_original()
        from gposcheck.synth import TTFont, addOpenTypeFeaturesFromString, DefaultTable
        tmp = TTFont(io.BytesIO(orig))
        addOpenTypeFeaturesFromString(tmp, "feature dist {\n pos A V -80;\n} dist;")
        f = TTFont(io.BytesIO(orig), lazy=True)
        t = DefaultTable("GPOS")
        t.data = tmp["GPOS"].compile(tmp)
        f["GPOS"] = t
        b = io.BytesIO()
        f.save(b)
        _, codes, _ = run(out=b.getvalue(), original=orig)
        self.assertIn("kern_feature_missing", codes)
        self.assertIn("roundtrip_value_mismatch", codes)


class Cli(unittest.TestCase):
    def test_cli_exit_codes_and_receipt_file(self):
        with tempfile.TemporaryDirectory() as t:
            orig = synth.make_original()
            out = synth.standin_write(orig, FEA)
            p = lambda n: os.path.join(t, n)
            open(p("o.ttf"), "wb").write(orig)
            open(p("n.ttf"), "wb").write(out)
            rows = [d.__dict__ for d in declared_base()]
            json.dump(rows, open(p("d.json"), "w"))
            argv = ["--original", p("o.ttf"), "--output", p("n.ttf"), "--declared", p("d.json"), "--receipt", p("r.txt")]
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(cli_main(argv), 0)
            self.assertTrue(open(p("r.txt")).read().endswith("verdict=PASS findings=0\n"))
            rows[0]["written"] = -1
            json.dump(rows, open(p("d.json"), "w"))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(cli_main(argv), 1)


if __name__ == "__main__":
    unittest.main()
