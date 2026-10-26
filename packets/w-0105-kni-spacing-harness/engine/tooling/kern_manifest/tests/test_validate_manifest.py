"""Synthetic fixtures for the candidate manifest schema check. No real font data."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import validate_candidate_manifest as v  # noqa: E402

H = "0123456789abcdef" * 4
C = "a" * 40


def row(**kw):
    d = {
        "font": "Synth One (OTF)", "designer": "Nobody", "style": "Sans", "upstream_url": "https://example.invalid/one",
        "version_or_pin": "v1.0", "license": "OFL-1.1", "license_text_url": "https://example.invalid/ofl",
        "license_file": "licenses/L-one.txt", "license_sha256": H, "binary_file": "fonts/One.otf", "binary_sha256": H,
        "binary_source_url": "https://example.invalid/rel/one.zip (file One.otf)", "kern_pairs_explicit": "10",
        "kern_pairs_class_expanded": "20", "hand_kerning_evidence_class": "Structural source evidence",
        "hand_kerning_evidence_source": "Source: kerning.plist at the commit.", "caveats": "none", "status": "Candidate",
    }
    d.update(kw)
    return d


def tsv(rows, cols=v.COLUMNS):
    return "\n".join(["\t".join(cols)] + ["\t".join(r[c] for c in cols) for r in rows]) + "\n"


ARCH = "archive\turl\tbytes\tsha256\none.zip\thttps://example.invalid/rel/one.zip\t100\t" + H + "\n"


def errs(res):
    return [(f["where"], f["field"]) for f in res if f["kind"] == "ERROR"]


class Schema(unittest.TestCase):
    def test_clean_row_has_no_error_and_reports_gaps(self):
        res = v.validate(tsv([row()]), ARCH)
        self.assertEqual(errs(res), [])
        self.assertTrue(any(f["kind"] == "GAP" and f["field"] == "status" for f in res))

    def test_bad_sha_and_url_and_count(self):
        res = v.validate(tsv([row(binary_sha256="xyz", upstream_url="ftp://x", kern_pairs_explicit="-1")]), ARCH)
        self.assertEqual(set(errs(res)), {("manifest row 1", "binary_sha256"), ("manifest row 1", "upstream_url"), ("manifest row 1", "kern_pairs_explicit")})

    def test_uppercase_hex_is_rejected(self):
        self.assertIn(("manifest row 1", "license_sha256"), errs(v.validate(tsv([row(license_sha256=H.upper())]), ARCH)))

    def test_license_and_evidence_class(self):
        res = v.validate(tsv([row(license="GPL", hand_kerning_evidence_class="Hand kerned")]), ARCH)
        self.assertIn(("manifest row 1", "license"), errs(res))
        self.assertIn(("manifest row 1", "hand_kerning_evidence_class"), errs(res))

    def test_written_statement_needs_reference_and_structural_needs_source(self):
        a = v.validate(tsv([row(hand_kerning_evidence_class="Written statement", hand_kerning_evidence_source="trust me")]), ARCH)
        b = v.validate(tsv([row(hand_kerning_evidence_source="no files named")]), ARCH)
        self.assertIn(("manifest row 1", "hand_kerning_evidence_source"), errs(a))
        self.assertIn(("manifest row 1", "hand_kerning_evidence_source"), errs(b))

    def test_no_release_archive_needs_commit(self):
        bad = v.validate(tsv([row(version_or_pin="No release archive. Pinned to nothing")]), ARCH)
        good = v.validate(tsv([row(version_or_pin="No release archive. Pinned to repo commit " + C)]), ARCH)
        self.assertIn(("manifest row 1", "version_or_pin"), errs(bad))
        self.assertEqual(errs(good), [])

    def test_empty_field_duplicate_font_and_absolute_binary_path(self):
        res = v.validate(tsv([row(designer=""), row(binary_file="/abs/One.otf")]), ARCH)
        self.assertIn(("manifest row 1", "designer"), errs(res))
        self.assertIn(("manifest row 2", "font"), errs(res))
        self.assertIn(("manifest row 2", "binary_file"), errs(res))

    def test_header_mismatch_and_wrong_column_count(self):
        self.assertEqual(errs(v.validate(tsv([row()], v.COLUMNS[:-1]), ARCH)), [("manifest", "header")])
        short = "\t".join(v.COLUMNS) + "\n" + "a\tb\n"
        self.assertEqual(errs(v.validate(short, ARCH)), [("manifest row 1", "-")])

    def test_archive_listing_checks(self):
        bad = "archive\turl\tbytes\tsha256\none.zip\thttp://x\t0\tabc\n"
        res = v.validate(tsv([row()]), bad)
        self.assertEqual({e[1] for e in errs(res)}, {"url", "bytes", "sha256"})
        missing = v.validate(tsv([row(binary_source_url="https://example.invalid/rel/other.zip (file x)")]), ARCH)
        self.assertIn(("manifest row 1", "binary_source_url"), errs(missing))

    def test_empty_manifest(self):
        self.assertEqual(errs(v.validate("", ARCH)), [("manifest", "-")])

    def test_output_makes_no_statement_about_fonts(self):
        for f in v.validate(tsv([row()]), ARCH):
            self.assertNotIn("certif", f["message"].lower())


if __name__ == "__main__":
    unittest.main()
