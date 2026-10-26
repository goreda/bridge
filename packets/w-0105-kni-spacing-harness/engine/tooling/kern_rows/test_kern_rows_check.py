import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kern_rows_check import *

A, B = "a" * 64, "b" * 64
H = "\t".join(COLUMNS)
MH = "name\tlabel\tclass\tunit\tmethod\tvalue\tderivation\n"
MAN = (MH + "tolerance\twall_tol\tCONVENTION\tfont_units\tanalytic_root_solve\t0.25\twritten derivation\n")
MAN_FLAT = (MH + "tolerance\twall_tol\tCONVENTION\tfont_units\tflatten\t0.25\twritten derivation\n"
            "flatten\tflat\tCONVENTION\tfont_units\tflatten\t4\twritten derivation\n")


def row(**kw):
    d = dict(font_sha256=A, left="A", right="V", outline_source=NA, outline_sha256=NA, upm=NA, gap_after=NA,
             gap_target=NA, y_lo=NA, y_hi=NA, error_bound_method=NA, error_bound_value=NA, tol=NA, tolerance_label=NA, status=NA, reason="missing_outline_evidence")
    d.update(kw)
    return "\t".join(d[c] for c in COLUMNS)


def meas(after, target, tol, status, **kw):
    d = dict(outline_source="extract_quadratic", outline_sha256=B, upm="1000", gap_after=after, gap_target=target, y_lo="0.0", y_hi="700.0",
             error_bound_method="analytic_root_solve", error_bound_value="0.125", tol=tol,
             tolerance_label="wall_tol", status=status, reason="")
    d.update(kw)
    return row(**d)


class T(unittest.TestCase):
    def run_rows(self, *rows, man=MAN):
        return check_rows("".join(l + "\n" for l in (H,) + rows), parse_manifest(man))

    def bad(self, *rows, man=MAN):
        with self.assertRaises(RowError):
            self.run_rows(*rows, man=man)

    def test_counts_and_boundary(self):
        self.assertEqual(self.run_rows(), (0, 0, 0))
        r = self.run_rows(meas("10.0", "10.5", "0.5", "VERIFIED"),
                          meas("10.0", "10.75", "0.5", "FAIL", right="W"), row(right="X"))
        self.assertEqual(r, (1, 1, 1))
        # exact boundary: off by exactly tol is VERIFIED; a one-digit excess is FAIL
        self.assertEqual(self.run_rows(meas("0.3", "0.1", "0.2", "VERIFIED")), (1, 0, 0))
        self.assertEqual(self.run_rows(meas("0.3", "0.1", "0.19999999999999999999", "FAIL")), (0, 1, 0))
        self.bad(meas("0.3", "0.1", "0.19999999999999999999", "VERIFIED"))

    def test_status_must_follow_measurement(self):
        self.bad(meas("10.0", "11.0", "0.5", "VERIFIED"))
        self.bad(meas("10.0", "10.1", "0.5", "FAIL"))

    def test_na_rules(self):
        self.bad(row(gap_after="0"))
        self.bad(row(reason="pass"))
        self.bad(row(reason=""))
        self.bad(row(tol="0"))
        self.bad(row(outline_source="extract_cff"))
        self.bad(row(outline_source="extract_cff", outline_sha256=B))  # missing_outline_evidence with outline
        self.bad(row(reason="no_vertical_overlap"))  # no outline
        self.run_rows(row(outline_source="extract_cff", outline_sha256=B, reason="no_vertical_overlap"))
        for why in ("tolerance_missing", "numerical_unresolved", "missing_wall_evidence"):
            self.run_rows(row(reason=why))
            self.run_rows(row(outline_source="extract_cff", outline_sha256=B, reason=why))

    def test_measured_rows_need_everything(self):
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", outline_source=NA))
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", outline_sha256="x"))
        self.bad(meas("nan", "1.0", "0.5", "VERIFIED"))
        self.bad(meas("1.0", "inf", "0.5", "VERIFIED"))
        self.bad(meas("1.0", "1.0", NA, "VERIFIED"))
        self.bad(meas("1.0", "1.0", "-0.5", "VERIFIED"))
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", tolerance_label="nope"))
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", reason="x"))
        self.bad(meas("1.0", "1.0", "0.5", "pass"))

    def test_manifest_rules(self):
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", error_bound_method="flatten"), man=MAN_FLAT.split("flatten\tflat\t")[0])
        self.run_rows(meas("1.0", "1.0", "0.5", "VERIFIED", error_bound_method="flatten"), man=MAN_FLAT)
        for m in (MH + "tolerance\tx\tdefinition\tfont_units\tflatten\t1\td\n",
                  MH + "tolerance\tx\tCONVENTION\tpx\tflatten\t1\td\n",
                  MH + "tolerance\tx\tCONVENTION\tfont_units\tguess\t1\td\n",
                  MH + "tolerance\tx\tCONVENTION\tfont_units\tflatten\t0\td\n",
                  MH + "tolerance\tx\tCONVENTION\tfont_units\tflatten\tnan\td\n",
                  MH + "tolerance\tx\tCONVENTION\tfont_units\tflatten\t1\t\n",
                  MH + "flatten\tx\tCONVENTION\tfont_units\tanalytic_root_solve\t1\td\n",
                  MH + "other\tx\tCONVENTION\tfont_units\tflatten\t1\td\n",
                  MAN + MAN.split("\n")[1] + "\n", "bad\n"):
            with self.assertRaises(RowError):
                parse_manifest(m)

    def test_error_bound_rules(self):
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", error_bound_value="0.0"))
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", error_bound_value="0.5"))   # exceeds manifest bound 0.25
        self.bad(meas("1.0", "1.0", "0.1", "VERIFIED", error_bound_value="0.125"))  # tol below error bound
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", y_lo="9.0", y_hi="1.0"))
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", y_hi=NA))
        self.bad(row(error_bound_value="0.125"))   # n/a row must hold n/a
        self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", error_bound_method="flatten"))  # differs from manifest method

    def test_upm_and_na_columns(self):
        for u in ("0", "-1", "+5", "1000.5", "abc", NA, "", " 5", "5 ", "\uff15", "4294967296", "1e3"):
            self.bad(meas("1.0", "1.0", "0.5", "VERIFIED", upm=u))
        for c in ("upm", "error_bound_method", "tolerance_label", "y_lo"):
            self.bad(row(**{c: "0"}))

    def test_keys_and_shape(self):
        self.bad(row(), row())
        self.bad(row(font_sha256="A" * SHA_HEX_LEN))
        self.bad(row(left=""))
        self.bad(row() + "\textra")
        with self.assertRaises(RowError):
            check_rows("x\n", parse_manifest(MAN))

    def test_decimal_grammar(self):
        for bad in ("1e3", "1E3", "+1", ".5", "1.", "-", "", "1_0", "\uff11", "\u0661", " 1", "1 ", "1.2.3",
                    "--1", "0x1", "NaN", "inf", "1,5", "1\n"):
            self.bad(meas(bad, bad, "0.5", "VERIFIED"))
            self.bad(meas("1.0", "1.0", bad, "VERIFIED"))
        for good in ("0", "-0", "7", "-7.25", "007.500", "123456.789"):
            self.run_rows(meas(good, good, "0.5", "VERIFIED"))
        with self.assertRaises(RowError):
            parse_manifest(MAN.replace("0.25", "1e-1"))

    def test_overflow_is_refused(self):
        huge = "9" * SHA_HEX_LEN
        with self.assertRaises(RowError) as c:
            self.run_rows(meas(huge, "1.0", "0.5", "VERIFIED"))
        self.assertIn("overflow", str(c.exception))
        deep = "0." + "0" * SHA_HEX_LEN + "1"
        with self.assertRaises(RowError) as c:
            self.run_rows(meas("1.0", deep, "0.5", "VERIFIED"))
        self.assertIn("overflow", str(c.exception))

    def test_one_font_one_upm(self):
        y = meas("1.0", "1.0", "0.5", "VERIFIED", right="Y")
        z = meas("1.0", "1.0", "0.5", "VERIFIED", right="Z", upm="2048")
        self.bad(y, z)
        other = meas("1.0", "1.0", "0.5", "VERIFIED", right="Y", upm="2048", font_sha256=B)
        self.run_rows(y, other)

    def test_strict_byte_order(self):
        y = meas("1.0", "1.0", "0.5", "VERIFIED", right="Y")
        z = meas("1.0", "1.0", "0.5", "VERIFIED", right="Z")
        self.run_rows(y, z)
        self.bad(z, y)
        left_b = meas("1.0", "1.0", "0.5", "VERIFIED", right="Y", left="B")
        self.bad(left_b, y)
        self.run_rows(y, left_b)
        font_b = meas("1.0", "1.0", "0.5", "VERIFIED", right="Y", font_sha256=B)
        self.bad(font_b, y)
        self.run_rows(y, font_b)


if __name__ == "__main__":
    unittest.main()
