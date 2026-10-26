#!/usr/bin/env python3
"""Tests for report.py (piece 18). Stdlib only; run: python3 test_report.py"""
import os, tempfile, unittest
import report

def tsv(outcome="ok", total=10.0, phases=(("fitting", 8.0), ("pairs", 1.5)), glyphs=(("A", 4.0), ("b", 4.0)),
        quality=None):
    s = "fit_bench_v1\ncreated_unix\t1\noutcome\t{}\ntotal_s\t{:.6f}\n".format(outcome, total)
    for n, d in phases:
        s += "phase\t{}\t{:.6f}\n".format(n, d)
    s += "glyphs\t{}\nglyph_cpu_sum_s\t{:.6f}\n".format(len(glyphs), sum(d for _, d in glyphs))
    for n, d in sorted(glyphs):
        s += "glyph\t{}\t{:.6f}\n".format(n, d)
    if quality:
        s += "quality_glyphs\t{}\n".format(len(quality))
        for q in sorted(quality):
            name, domain, rings, nodes, fallback, extrema, ink, err = quality[q]
            s += "quality\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.6f}\n".format(
                name, domain, rings, nodes, fallback, extrema, ink, err)
    return s

def write(d, label, text, meta=None):
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, label + ".tsv"), "w") as f:
        f.write(text)
    if meta:
        with open(os.path.join(d, label + ".meta"), "w") as f:
            f.write(meta)

class ReportTests(unittest.TestCase):
    def test_metrics_and_speedups(self):
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv(total=10.0), "style_id\tMarq/Alternate\nengine_git_sha\tabcdef01\n")
            write(a, "s1", tsv(total=5.0, phases=(("fitting", 4.0), ("pairs", 0.5))),
                  "style_id\tMarq/Alternate\nengine_git_sha\t12345678\n")
            rows = report.build_rows(report.load_dir(b), report.load_dir(a))
            self.assertEqual(len(rows), 1)
            r = rows[0]
            self.assertEqual(r["style"], "Marq/Alternate")
            self.assertEqual(r["glyphs"], "2")
            self.assertAlmostEqual(r["fit_before"], 4.0)   # 8.0 s / 2 glyphs
            self.assertAlmostEqual(r["fit_after"], 2.0)
            self.assertEqual(r["fit_x"], "2.00x")
            self.assertEqual(r["pairs_x"], "3.00x")
            self.assertEqual(r["total_x"], "2.00x")

    def test_missing_label_on_one_side(self):
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv())
            rows = report.build_rows(report.load_dir(b), report.load_dir(a))
            self.assertIsNone(rows[0]["fit_after"])
            self.assertEqual(rows[0]["fit_x"], "n/a")
            self.assertIn("MISSING", report.render_markdown(rows))

    def test_absent_phase_reports_missing_not_zero(self):
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv(phases=(("fitting", 8.0),)))   # no pairs row at all
            write(a, "s1", tsv())
            rows = report.build_rows(report.load_dir(b), report.load_dir(a))
            self.assertIsNone(rows[0]["pairs_before"])
            self.assertEqual(rows[0]["pairs_x"], "n/a")
            self.assertIsNotNone(rows[0]["fit_before"])

    def test_bad_header_refused(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "bad", "not_a_bench\n")
            with self.assertRaises(ValueError):
                report.load_dir(d)

    def test_render_tsv_columns(self):
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv(), "engine_git_sha\tabcdef012345\n")
            write(a, "s1", tsv(), "engine_git_sha\t654321fedcba\n")
            rows = report.build_rows(report.load_dir(b), report.load_dir(a))
            t = report.render_tsv(rows)
            self.assertIn("abcdef01", t)
            self.assertIn("654321fe", t)
            self.assertEqual(t.splitlines()[0].count("\t"), 19)

    def test_quality_columns_populated(self):
        q_old = {"A": ("A", "shipped", 1, 20, 0, 0, 100, 50.0),
                 "b": ("b", "shipped", 2, 30, 1, 0, 200, 70.0)}
        q_new = {"A": ("A", "shipped", 1, 12, 0, 0, 100, 20.0),
                 "b": ("b", "shipped", 2, 16, 0, 0, 200, 40.0)}
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv(quality=q_old))
            write(a, "s1", tsv(quality=q_new))
            rows = report.build_rows(report.load_dir(b), report.load_dir(a))
            r = rows[0]
            self.assertEqual(r["nodes_before"], 50)
            self.assertEqual(r["nodes_after"], 28)
            # err/inkpx: 120/300 = 0.4 before, 60/300 = 0.2 after
            self.assertAlmostEqual(r["err_before"], 0.4)
            self.assertAlmostEqual(r["err_after"], 0.2)
            self.assertEqual(r["err_x"], "2.00x")
            self.assertIn("area err/inkpx", report.render_markdown(rows))

    def test_measurement_domain_excluded_from_quality_metrics(self):
        q = {"A": ("A", "shipped", 1, 10, 0, 0, 100, 10.0),
             "A#m": ("A", "measurement", 1, 99, 9, 9, 100, 99.0)}
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv(quality=q))
            write(a, "s1", tsv(quality=q))
            r = report.build_rows(report.load_dir(b), report.load_dir(a))[0]
            self.assertEqual(r["nodes_before"], 10)
            self.assertAlmostEqual(r["err_before"], 0.1)

    def test_tsv_without_quality_rows_reports_missing(self):
        with tempfile.TemporaryDirectory() as b, tempfile.TemporaryDirectory() as a:
            write(b, "s1", tsv())
            write(a, "s1", tsv())
            r = report.build_rows(report.load_dir(b), report.load_dir(a))[0]
            self.assertIsNone(r["nodes_before"])
            self.assertIsNone(r["err_after"])
            self.assertEqual(r["nodes_x"], "n/a")
            self.assertIn("MISSING", report.render_markdown([r]))

if __name__ == "__main__":
    unittest.main()
