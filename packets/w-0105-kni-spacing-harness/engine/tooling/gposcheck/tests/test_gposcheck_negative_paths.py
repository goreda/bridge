"""Negative-path tests for gposcheck: each case feeds a checker input that must be reported.
Only paths that report today are covered; known gaps are tracked separately and have no test here."""
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from fontTools.ttLib import TTFont  # noqa: E402
from gposcheck import check, Declared  # noqa: E402
from gposcheck import synth  # noqa: E402


def write_font(font):
    b = io.BytesIO()
    font.save(b)
    return b.getvalue()


def codes_for(orig, out, declared):
    _, findings, _ = check(orig, out, declared)
    return [f[0] for f in findings]


AV = [Declared("A", "V", -80, -80, "written")]


class KernReachability(unittest.TestCase):
    def test_kern_feature_not_reached_by_any_script(self):
        orig = synth.make_original()
        out = TTFont(io.BytesIO(synth.standin_write(orig, "pos A V -80;")))
        t = out["GPOS"].table
        t.ScriptList.ScriptRecord = []
        t.ScriptList.ScriptCount = 0
        codes = codes_for(orig, write_font(out), AV)
        self.assertIn("kern_feature_unreachable", codes)
        self.assertIn("roundtrip_value_mismatch", codes)

    def test_non_pair_lookup_inside_kern_is_reported(self):
        orig = synth.make_original()
        from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
        tmp = TTFont(io.BytesIO(orig))
        addOpenTypeFeaturesFromString(tmp, "feature kern {\n pos A <0 0 10 0>;\n} kern;")
        out = TTFont(io.BytesIO(orig))
        out["GPOS"] = tmp["GPOS"]
        codes = codes_for(orig, write_font(out), [])
        self.assertIn("unsupported_lookup_type_in_kern", codes)


class ValueFields(unittest.TestCase):
    def test_x_placement_is_reported(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "pos A V <10 0 -80 0>;")
        codes = codes_for(orig, out, AV)
        self.assertIn("unexpected_value_fields", codes)

    def test_second_value_record_is_reported(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "pos A <0 0 -80 0> V <0 0 5 0>;")
        codes = codes_for(orig, out, AV)
        self.assertIn("unexpected_value_fields", codes)

    def test_y_advance_is_reported(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "pos A V <0 0 -80 7>;")
        self.assertIn("unexpected_value_fields", codes_for(orig, out, AV))


class DeclaredInputs(unittest.TestCase):
    def test_declared_glyph_missing_from_font(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "pos A V -80;")
        codes = codes_for(orig, out, AV + [Declared("A", "Q", -10, -10, "written")])
        self.assertIn("unknown_glyph", codes)

    def test_nan_requested_declared_written_is_a_status_mismatch(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "pos A V -80;")
        codes = codes_for(orig, out, [Declared("A", "V", float("nan"), -80, "written")])
        self.assertIn("status_mismatch", codes)

    def test_written_value_differs_from_font_in_class_cell(self):
        # class cell value read back from the font must equal the declared value of every glyph pair in it
        orig = synth.make_original()
        out = synth.standin_write(orig, "@L = [A B];\n@R = [V W];\npos @L @R -30;")
        d = [Declared(l, r, -30, -30, "written") for l in "AB" for r in "VW"]
        d[3] = Declared("B", "W", -30, -20, "rounded")
        self.assertIn("roundtrip_value_mismatch", codes_for(orig, out, d))

    def test_class_cell_pair_missing_from_declared_list(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "@L = [A B];\n@R = [V W];\npos @L @R -30;")
        d = [Declared(l, r, -30, -30, "written") for l in "AB" for r in "VW" if (l, r) != ("B", "W")]
        self.assertIn("undeclared_nonzero_pair", codes_for(orig, out, d))

    def test_zero_declared_over_class_value(self):
        orig = synth.make_original()
        out = synth.standin_write(orig, "@L = [A B];\n@R = [V W];\npos @L @R -30;")
        d = [Declared(l, r, -30, -30, "written") for l in "AB" for r in "VW"]
        d[3] = Declared("B", "W", 0, 0, "written")
        self.assertIn("roundtrip_value_mismatch", codes_for(orig, out, d))


if __name__ == "__main__":
    unittest.main()
