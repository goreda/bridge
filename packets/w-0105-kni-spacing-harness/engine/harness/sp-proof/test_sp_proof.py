#!/usr/bin/env python3
"""Unit tests for sp_proof.py. Synthetic fixtures only: a minimal OTTO/CFF1
writer (same layout the engine's cff_container emits) builds tiny fonts in
tmp dirs; no real tiles, no repo paths, KNI_G_FIXTURES untouched."""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SP = os.path.join(HERE, "sp_proof.py")
sys.path.insert(0, HERE)
import sp_proof


# ---- minimal CFF/OTTO writer (test fixture builder, mirrors cff_container) --

def _index(objects):
    out = len(objects).to_bytes(2, "big")
    if not objects:
        return out
    out += b"\x01"
    off = 1
    offs = []
    for o in objects:
        offs.append(off)
        off += len(o)
    offs.append(off)
    out += bytes(offs)
    for o in objects:
        out += o
    return out


def _dict_int(v):
    return b"\x1d" + v.to_bytes(4, "big")


def _cff(ps_name, glyphs):
    """glyphs: [(name, charstring_bytes)]; glyphs[0] must be .notdef."""
    name = _index([ps_name.encode("ascii")])
    strings = _index([g[0].encode("ascii") for g in glyphs[1:]])
    subrs = _index([])
    charset = b"\x00" + b"".join((390 + i).to_bytes(2, "big") for i in range(1, len(glyphs)))
    chars = _index([g[1] for g in glyphs])

    def top_index(cs_off, ch_off):
        return _index([_dict_int(cs_off) + b"\x0f" + _dict_int(ch_off) + b"\x11"])

    provisional = top_index(0, 0)  # same encoded length as the final Top DICT
    charset_off = 4 + len(name) + len(provisional) + len(strings) + len(subrs)
    chars_off = charset_off + len(charset)
    top = top_index(charset_off, chars_off)
    assert len(top) == len(provisional)
    return b"\x01\x00\x04\x04" + name + top + strings + subrs + charset + chars


def _otto(ps_name, glyphs):
    cff = _cff(ps_name, glyphs)
    num = 1
    header = b"OTTO" + num.to_bytes(2, "big") + (16).to_bytes(2, "big") + (0).to_bytes(2, "big") + (0).to_bytes(2, "big")
    record = b"CFF " + (0).to_bytes(4, "big") + (12 + 16 * num).to_bytes(4, "big") + len(cff).to_bytes(4, "big")
    pad = (-len(cff)) % 4
    return header + record + cff + b"\x00" * pad


def _cs(seed):
    return bytes([28, 0, seed, 21, 28, 0, seed + 1, 5, 14])


def write_style(root, style_id, glyph_seeds, ledgers=None):
    d = os.path.join(root, style_id)
    os.makedirs(d, exist_ok=True)
    glyphs = [(".notdef", _cs(10))] + [("g%d" % i, _cs(s)) for i, s in enumerate(glyph_seeds, 1)]
    with open(os.path.join(d, "font-%s.otf" % style_id), "wb") as f:
        f.write(_otto("TestPS-%s" % style_id, glyphs))
    for name, body in (ledgers or {}).items():
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(body)


KIT = "style_id\tfamily\tsubfamily\tmanifest\tout\tscope\n"  # header as comment in real kits


def write_kit(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# style_id\tfamily\tsubfamily\tmanifest\tout\tscope\n")
        for r in rows:
            f.write("\t".join(r) + "\n")


def run_cli(argv):
    return subprocess.run([sys.executable, SP] + argv, capture_output=True, text=True)


class CffReadTest(unittest.TestCase):
    def test_names_and_count(self):
        font = _otto("T", [(".notdef", _cs(1)), ("A", _cs(2)), ("B", _cs(3))])
        names, chars, warnings = sp_proof.glyph_charstrings(font)
        self.assertEqual(names, [".notdef", "A", "B"])
        self.assertEqual(len(chars), 3)
        self.assertEqual(warnings, [])

    def test_truncated_refuses(self):
        with self.assertRaises(sp_proof.CffError):
            sp_proof.glyph_charstrings(b"OTTO")


class CompareTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = os.path.join(self.tmp.name, "base")
        self.cand = os.path.join(self.tmp.name, "cand")
        self.kit = os.path.join(self.tmp.name, "kit.tsv")

    def _kit(self, scopes=("off-target",)):
        rows = [("s%d" % i, "Fam", "Sub", "-", "s%d" % i, sc) for i, sc in enumerate(scopes)]
        write_kit(self.kit, rows)
        return [r[0] for r in rows]

    def _report(self):
        rp = os.path.join(self.tmp.name, "report.json")
        proc = run_cli(["compare", "--kit", self.kit,
                        "--base-root", self.base, "--cand-root", self.cand,
                        "--base-label", "basesha", "--cand-label", "candsha",
                        "--report-json", rp])
        report = None
        if os.path.isfile(rp):
            report = json.load(open(rp, encoding="utf-8"))
        return proc, report

    def test_pass_identical(self):
        (sid,) = self._kit()
        for root in (self.base, self.cand):
            write_style(root, sid, [20, 21, 22], {"spacing.tsv": "a\tb\n"})
        proc, report = self._report()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(report["verdict"], "PASS")
        self.assertEqual(report["base_label"], "basesha")
        font = report["styles"][0]["artifacts"][0]
        self.assertEqual(font["status"], "SAME")
        self.assertEqual(font["glyph_count"], 4)

    def test_fail_names_first_diff_glyph(self):
        (sid,) = self._kit()
        write_style(self.base, sid, [20, 21, 22])
        write_style(self.cand, sid, [20, 99, 22])
        proc, report = self._report()
        self.assertEqual(proc.returncode, 4)
        font = report["styles"][0]["artifacts"][0]
        self.assertEqual(font["status"], "DIFF")
        self.assertEqual(font["first_diff_glyph"], {"gid": 2, "name": "g2", "status": "DIFF"})
        self.assertEqual(font["glyph_diff_count"], 1)
        statuses = [m["status"] for m in font["matrix"]]
        self.assertEqual(statuses, ["SAME", "SAME", "DIFF", "SAME"])

    def test_fail_glyph_count_change(self):
        (sid,) = self._kit()
        write_style(self.base, sid, [20, 21])
        write_style(self.cand, sid, [20, 21, 22])
        proc, report = self._report()
        self.assertEqual(proc.returncode, 4)
        font = report["styles"][0]["artifacts"][0]
        self.assertEqual(font["first_diff_glyph"], {"gid": 3, "name": "g3", "status": "CAND-ONLY"})

    def test_fail_ledger_diff(self):
        (sid,) = self._kit()
        write_style(self.base, sid, [20], {"spacing.tsv": "a\t1\n"})
        write_style(self.cand, sid, [20], {"spacing.tsv": "a\t2\n"})
        proc, report = self._report()
        self.assertEqual(proc.returncode, 4)
        sp = next(a for a in report["styles"][0]["artifacts"] if a["name"] == "spacing.tsv")
        self.assertEqual(sp["status"], "DIFF")

    def test_fail_font_missing_one_side(self):
        (sid,) = self._kit()
        write_style(self.base, sid, [20])
        os.makedirs(os.path.join(self.cand, sid))
        proc, report = self._report()
        self.assertEqual(proc.returncode, 4)
        self.assertEqual(report["styles"][0]["artifacts"][0]["status"], "MISSING-CAND")

    def test_fail_font_missing_both(self):
        (sid,) = self._kit()
        os.makedirs(os.path.join(self.base, sid))
        os.makedirs(os.path.join(self.cand, sid))
        proc, report = self._report()
        self.assertEqual(proc.returncode, 4)
        self.assertEqual(report["styles"][0]["artifacts"][0]["status"], "MISSING-BOTH")

    def test_on_target_skipped(self):
        sids = self._kit(("off-target", "on-target"))
        for root in (self.base, self.cand):
            write_style(root, sids[0], [20])
            write_style(root, sids[1], [20])
        # on-target style may differ freely: change candidate's font
        write_style(self.cand, sids[1], [42])
        proc, report = self._report()
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(report["styles"][1]["verdict"], "SKIPPED")

    def test_ledger_absent_both_sides_ok(self):
        (sid,) = self._kit()
        for root in (self.base, self.cand):
            write_style(root, sid, [20])  # no ledgers at all
        proc, report = self._report()
        self.assertEqual(proc.returncode, 0)
        statuses = {a["name"]: a["status"] for a in report["styles"][0]["artifacts"]}
        self.assertEqual(statuses["spacing.tsv"], "NOT-EMITTED")

    def test_refused_bad_kit(self):
        write_kit(self.kit, [("s0", "Fam", "Sub", "-", "s0", "bogus-scope")])
        proc, _ = self._report()
        self.assertEqual(proc.returncode, 3)
        self.assertIn("REFUSED", proc.stderr)

    def test_refused_no_off_target(self):
        self._kit(("on-target",))
        proc, _ = self._report()
        self.assertEqual(proc.returncode, 3)

    def test_refused_missing_root(self):
        (sid,) = self._kit()
        proc = run_cli(["compare", "--kit", self.kit,
                        "--base-root", os.path.join(self.tmp.name, "nope"),
                        "--cand-root", self.cand])
        self.assertEqual(proc.returncode, 3)

    def test_subset_compares_only_named_styles(self):
        sids = self._kit(("off-target", "off-target", "off-target"))
        for root in (self.base, self.cand):
            for sid in sids:
                write_style(root, sid, [20])
        # tamper a style OUTSIDE the subset: must not affect the verdict
        write_style(self.cand, sids[2], [99])
        rp = os.path.join(self.tmp.name, "report.json")
        proc = run_cli(["compare", "--kit", self.kit,
                        "--base-root", self.base, "--cand-root", self.cand,
                        "--styles", sids[0], "--report-json", rp])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.load(open(rp, encoding="utf-8"))
        self.assertEqual([s["style_id"] for s in report["styles"]], [sids[0]])
        self.assertEqual(report["styles_subset"], sids[0])
        # and the subset misses nothing: naming a tampered style FAILs
        proc2 = run_cli(["compare", "--kit", self.kit,
                         "--base-root", self.base, "--cand-root", self.cand,
                         "--styles", sids[2]])
        self.assertEqual(proc2.returncode, 4)

    def test_run_mode_missing_manifest_typed_refusal(self):
        write_kit(self.kit, [("s0", "Fam", "Sub",
                              os.path.join(self.tmp.name, "no-such-manifest.txt"),
                              "s0", "off-target")])
        proc = run_cli(["run", "--kit", self.kit,
                        "--repo", self.tmp.name,
                        "--base-sha", "aaaa", "--cand-sha", "bbbb",
                        "--work", os.path.join(self.tmp.name, "work")])
        self.assertEqual(proc.returncode, 3)
        self.assertIn("EngineManifestMissing", proc.stderr)

    def test_run_mode_kit_relative_manifest_resolution(self):
        # relative manifest, no KNI_G_FIXTURES: resolves next to the kit file;
        # the refusal must then be about the repo, not the manifest.
        man = os.path.join(self.tmp.name, "manifest.txt")
        with open(man, "w", encoding="utf-8") as f:
            f.write("run_mode stage1_only\n")
        write_kit(self.kit, [("s0", "Fam", "Sub", "manifest.txt", "s0", "off-target")])
        os.environ.pop("KNI_G_FIXTURES", None)
        proc = run_cli(["run", "--kit", self.kit,
                        "--repo", os.path.join(self.tmp.name, "no-such-repo"),
                        "--base-sha", "aaaa", "--cand-sha", "bbbb",
                        "--work", os.path.join(self.tmp.name, "work")])
        self.assertEqual(proc.returncode, 3)
        self.assertIn("RepoMissing", proc.stderr)

    def test_markdown_report_on_diff(self):
        (sid,) = self._kit()
        write_style(self.base, sid, [20, 21])
        write_style(self.cand, sid, [20, 99])
        md = os.path.join(self.tmp.name, "report.md")
        proc = run_cli(["compare", "--kit", self.kit,
                        "--base-root", self.base, "--cand-root", self.cand,
                        "--report-md", md])
        self.assertEqual(proc.returncode, 4)
        with open(md, encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("g2", text)
        self.assertIn("FAIL", text)


if __name__ == "__main__":
    unittest.main()
