"""Tests for literal_inventory (engine-wide literal ledger tooling, item 9).

Fixture sources are inline text; nothing engine-side is executed. The ledger
freshness test re-extracts the 7 crates' src trees and compares against
tooling/literal-inventory-ledger.tsv row for row.
"""
import csv
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import literal_inventory as li

ENGINE_ROOT = os.path.normpath(os.path.join(HERE, ".."))
LEDGER = os.path.join(HERE, "literal-inventory-ledger.tsv")

# Same input as kern_scope_guard.rs::scanner_self_check.
SELF_CHECK_SRC = r'''
        // 7 in a comment
        /* 8 /* nested 9 */ 10 */
        const A: u8 = 1_000; const B: u32 = 0x1F; const C: f64 = 1e-12; const D: u8 = 2u8;
        const E: f64 = 2.5e3_f64; static F: [u8; 16] = [0u8; 16];
        fn f<'a>(x: &'a str) { let c = '5'; let d = '\n'; let s = "99 {:.3}"; let r = r#"77"#; let t = x.0; }
        macro_rules! m { () => { 33 }; }
        fn g() { for i in 0..10 {} let _ = 4..=6; }
        #[cfg(test)]
        mod tests { const T: i32 = 555; mod inner { const U: i32 = 556; } }
        const AFTER: i32 = 42;
        const Z: f64 = 1.0; const O: i32 = 0;
    '''

SELF_CHECK_WANT = {
    "1000": 1, "0x1f": 1, "1e-12": 1, "2": 1, "2.5e3": 1, "16": 2,
    "33": 1, "10": 1, "4": 1, "6": 1, "42": 1,
}

KNOWN_CLASSES = {
    "trivial", "standard", "definition", "structural", "convention",
    "test_fixture", "test_surface", "covered:threshold-inventory",
    "candidate_font_derived", "candidate_declared",
}


def extract_rows():
    """Fresh engine-wide extraction as (crate, file, line, literal) tuples."""
    rows = []
    for crate in li.CRATES:
        srcdir = os.path.join(ENGINE_ROOT, crate, "src")
        for fn in sorted(os.listdir(srcdir)):
            if not fn.endswith(".rs"):
                continue
            rel = f"{crate}/src/{fn}"
            src = open(os.path.join(srcdir, fn), encoding="utf-8").read()
            for line, lit in li.scan_literals(src):
                rows.append((crate, rel, line, lit))
    return rows


class ScannerSelfCheck(unittest.TestCase):
    def test_matches_rust_scanner_expected_counts(self):
        got = dict(li.counted(SELF_CHECK_SRC))
        self.assertEqual(got, SELF_CHECK_WANT)

    def test_trivial_literals_are_emitted_not_dropped(self):
        lits = [lit for _, lit in li.scan_literals("const A: f64 = 1.0; const B: i32 = 0;")]
        self.assertEqual(sorted(lits), ["0", "1.0"])


class KernScopeParity(unittest.TestCase):
    def test_parity_with_committed_kern_scope_fixture(self):
        self.assertEqual(li.cmd_parity(ENGINE_ROOT), 0)


class Ledger(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(LEDGER) as f:
            cls.rows = list(csv.DictReader(f, delimiter="\t"))

    def test_no_unclassified_rows(self):
        bad = [r for r in self.rows if r["class"] == "UNCLASSIFIED" or not r["class"].strip()]
        self.assertEqual(bad, [])

    def test_class_vocabulary(self):
        for r in self.rows:
            cls = r["class"]
            ok = cls in KNOWN_CLASSES or cls.startswith("covered:kern-scope-literals:")
            self.assertTrue(ok, f"unknown class {cls} at {r['file']}:{r['line']}")

    def test_every_row_has_a_meaning(self):
        bad = [r for r in self.rows if not r["meaning_and_proposal"].strip()]
        self.assertEqual(bad, [])

    def test_ledger_matches_head_extraction(self):
        fresh = sorted(extract_rows())
        committed = sorted(
            (r["crate"], r["file"], int(r["line"]), r["literal"]) for r in self.rows
        )
        self.assertEqual(
            committed, fresh,
            "ledger drifted from the tree: regenerate tooling/literal-inventory-ledger.tsv "
            "with literal_inventory.py and classify the delta",
        )


if __name__ == "__main__":
    unittest.main()
