import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from sweepaudit import audit, Config  # noqa: E402
from sweepaudit.__main__ import main  # noqa: E402

KEYS = ["fontA", "fontB", "fontC", "fontD"]
CFG = dict(key_regex=r"^(?P<key>font[A-Z])/", result_patterns=["content:\"status\": \"ok\""],
           refusal_patterns=["content:\"refusal\": \""], refusal_type_regex=r"\"refusal\": \"(?P<type>[a-z_]+)\"")


def make(root, files):
    for rel, text in files.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)


GOOD = {
    "fontA/out.json": '{"status": "ok"}',
    "fontB/out.json": '{"status": "ok"}',
    "fontC/out.json": '{"refusal": "cap_exceeded"}',
    "fontD/out.json": '{"refusal": "no_outline"}',
}


def run(files, keys=KEYS, **over):
    with tempfile.TemporaryDirectory() as d:
        make(d, files)
        cfg = Config(**{**CFG, **over})
        return audit(d, "\n".join(keys) + "\n", cfg)


class Audit(unittest.TestCase):
    def test_complete(self):
        text, s = run(GOOD)
        self.assertTrue(s["complete"], text)
        self.assertIn("per_expected_key one_result=2 one_refusal=2 missing=0 doubled=0 result_and_refusal=0 no_record_file=0", text)
        self.assertIn("refusal_types cap_exceeded=1 no_outline=1 untyped_refusal_records=0", text)

    def test_missing_key(self):
        f = dict(GOOD); del f["fontB/out.json"]
        text, s = run(f)
        self.assertEqual(s["missing"], ["fontB"])
        self.assertFalse(s["complete"])
        self.assertIn("list missing fontB", text)

    def test_doubled_record(self):
        f = dict(GOOD); f["fontA/again.json"] = '{"status": "ok"}'
        text, s = run(f)
        self.assertEqual(s["doubled"], ["fontA"])
        self.assertFalse(s["complete"])

    def test_result_and_refusal_for_one_key(self):
        f = dict(GOOD); f["fontA/refusal.json"] = '{"refusal": "late_refusal"}'
        _, s = run(f)
        self.assertEqual(s["conflict"], ["fontA"])

    def test_single_file_matching_both_patterns(self):
        f = dict(GOOD); f["fontA/out.json"] = '{"status": "ok", "refusal": "x"}'
        _, s = run(f)
        self.assertEqual(s["conflict"], ["fontA"])

    def test_key_with_only_other_files(self):
        f = dict(GOOD); f["fontA/out.json"] = "log only"
        text, s = run(f)
        self.assertEqual(s["unclassified"], ["fontA"])
        self.assertIn("key fontA records=0 aux=1", text)

    def test_unexpected_and_unkeyed(self):
        f = dict(GOOD); f["fontZ/out.json"] = '{"status": "ok"}'; f["stray.txt"] = "x"
        text, s = run(f)
        self.assertEqual(s["unexpected"], ["fontZ"])
        self.assertEqual(s["unkeyed"], ["stray.txt"])
        self.assertFalse(s["complete"])

    def test_empty_file_and_untyped_refusal(self):
        f = dict(GOOD); f["fontC/out.json"] = '{"refusal": "Bad Type"}'; f["fontA/empty.log"] = ""
        text, s = run(f)
        self.assertEqual(s["empty"], ["fontA/empty.log"])
        self.assertEqual(s["untyped"], ["fontC/out.json"])
        self.assertIn("untyped_refusal_records=1", text)

    def test_duplicate_in_expected_list(self):
        text, s = run(GOOD, keys=KEYS + ["fontA"])
        self.assertIn("duplicate_in_list=1", text)
        self.assertFalse(s["complete"])

    def test_expected_count_mismatch(self):
        text, s = run(GOOD, expected_count=68)
        self.assertIn("expected_count_matches_list=false", text)
        self.assertFalse(s["complete"])

    def test_partial_sweep_counts_progress(self):
        f = {k: v for k, v in GOOD.items() if k in ("fontA/out.json", "fontB/out.json")}
        text, s = run(f)
        self.assertEqual(s["missing"], ["fontC", "fontD"])
        self.assertIn("one_result=2 one_refusal=0 missing=2", text)

    def test_path_pattern_and_truncated_read(self):
        f = {"fontA/ok.json": "x" * 50, "fontB/refused.json": "y"}
        text, s = run(f, keys=["fontA", "fontB"], result_patterns=["path:/ok\\.json$"], refusal_patterns=["path:/refused\\.json$"],
                      refusal_type_regex=None, max_read=10)
        self.assertEqual((s["one_result"], s["one_refusal"]), (1, 1))
        self.assertIn("truncated_read=1", text)

    def test_hashes_are_of_the_bytes_and_receipt_deterministic(self):
        t1, _ = run(GOOD)
        t2, _ = run(GOOD)
        self.assertEqual(t1, t2)
        h = hashlib.sha256(b'{"status": "ok"}').hexdigest()
        self.assertIn("file path=fontA/out.json bytes=16 sha256=%s key=fontA kind=result" % h, t1)

    def test_symlink_is_listed_not_followed(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, GOOD)
            os.symlink(os.path.join(d, "fontA/out.json"), os.path.join(d, "fontA/link.json"))
            text, s = audit(d, "\n".join(KEYS), Config(**CFG))
        self.assertIn("list symlink fontA/link.json", text)
        self.assertFalse(s["complete"])
        self.assertIn("symlinks=1", text)

    def test_unreadable_file_listed(self):
        if os.geteuid() == 0:
            self.skipTest("root can read everything")
        with tempfile.TemporaryDirectory() as d:
            make(d, GOOD)
            p = os.path.join(d, "fontA/out.json")
            os.chmod(p, 0)
            text, s = audit(d, "\n".join(KEYS), Config(**CFG))
            os.chmod(p, 0o644)
        self.assertEqual(s["unreadable"], ["fontA/out.json"])

    def test_config_errors(self):
        with self.assertRaises(ValueError):
            run(GOOD, key_regex=r"^font[A-Z]/")
        with self.assertRaises(ValueError):
            run(GOOD, result_patterns=[], refusal_patterns=[])

    def test_cli_and_strict(self):
        with tempfile.TemporaryDirectory() as d:
            root = os.path.join(d, "out"); os.makedirs(root)
            make(root, GOOD)
            with open(os.path.join(d, "keys.txt"), "w") as f:
                f.write("\n".join(KEYS))
            cfgp = os.path.join(d, "cfg.json")
            with open(cfgp, "w") as f:
                json.dump(CFG, f)
            argv = ["--root", root, "--expected", os.path.join(d, "keys.txt"), "--config", cfgp,
                    "--receipt", os.path.join(d, "r.txt"), "--strict"]
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(argv), 0)
                os.remove(os.path.join(root, "fontA/out.json"))
                self.assertEqual(main(argv), 1)
                self.assertEqual(main(argv[:-1]), 0)
            with open(os.path.join(d, "r.txt")) as f:
                self.assertIn("complete=false", f.read())



class KeyFromExpectedTests(unittest.TestCase):
    def _tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            fp = os.path.join(d, rel)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as f:
                f.write(text)
        return d

    def test_prefix_keys_and_row_checks(self):
        tsv = "font\tpath_label\tsymdiff\tnote\na\t\t\tkontur yok\na\tok\t1\t\na\tok\t\t\n"
        d = self._tree({"ab.done": "", "ab-out-a/glyphs.tsv": tsv, "a.done": "", "runner.log": "x"})
        cfg = Config(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"],
                     sweep_level_regex="^runner\\.log$", empty_ok_regex="\\.done$",
                     required_templates=["{key}.prep.json"], allowed_templates=["{key}.done", "{key}-out-a/glyphs.tsv"],
                     tsv_checks=[{"path_regex": "glyphs\\.tsv$", "label_column": "path_label", "refusal_value": "",
                                  "metric_columns": ["symdiff"], "note_column": "note"}])
        rec, summ = audit(d, "a\nab\nc\n", cfg)
        self.assertIn("key ab records=1", rec)
        self.assertIn("key a records=1", rec)
        self.assertIn("list missing c", rec)
        self.assertIn("list sweep_level runner.log", rec)
        self.assertIn("list required_missing a a.prep.json", rec)
        self.assertIn("rows=3 refusal_rows=1 refusal_rows_without_note=0 refusal_rows_with_metric=0 non_refusal_rows_with_empty_metric=1", rec)
        self.assertIn("notes=kontur yok:1", rec)

    def _exception_tree(self):
        files = {}
        for k in ("a", "b"):
            files[k + ".done"] = ""
            files[k + ".static.txt"] = "x"
        return self._tree(files)

    def test_required_exception_accepted(self):
        d = self._exception_tree()
        os.remove(os.path.join(d, "b.static.txt"))
        cfg = Config(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                     required_templates=["{key}.static.txt"], allowed_templates=["{key}.done"], required_exceptions={"{key}.static.txt": ["b"]})
        rec, summ = audit(d, "a\nb\n", cfg)
        self.assertIn("required_files missing=0 exceptions=1", rec)
        self.assertIn("list required_exception b b.static.txt", rec)
        self.assertNotIn("list required_missing", rec)

    def test_required_file_missing_outside_exception(self):
        d = self._exception_tree()
        os.remove(os.path.join(d, "a.static.txt"))
        cfg = Config(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                     required_templates=["{key}.static.txt"], allowed_templates=["{key}.done"], required_exceptions={"{key}.static.txt": ["b"]})
        rec, summ = audit(d, "a\nb\n", cfg)
        self.assertIn("required_files missing=1 exceptions=1", rec)
        self.assertIn("list required_missing a a.static.txt", rec)
        self.assertNotIn("list required_missing b", rec)


class PairCheckTests(unittest.TestCase):
    PAIR = [{"a_regex": "^(?P<key>[^/]+)-out-a/(?P<rest>.+)$", "b_template": "{key}-out-b/{rest}", "b_regex": "-out-b/"}]
    TSV = "font\tcodepoint\tpath_label\tsymdiff\tnote\nx\t0\tempty\t\tkontur yok\nx\t65\tok\t1\t\n"

    def _tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            fp = os.path.join(d, rel)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as f:
                f.write(text)
        return d

    def _cfg(self, **kw):
        return Config(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                      allowed_templates=["{key}.done", "{key}-out-a/glyphs.tsv", "{key}-out-b/glyphs.tsv", "{key}-out-b/other.tsv"],
                      pair_checks=self.PAIR, **kw)

    def test_equal_copies(self):
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": self.TSV, "a-out-b/glyphs.tsv": self.TSV})
        rec, _ = audit(d, "a\n", self._cfg())
        self.assertIn("pair_check a_regex=", rec)
        self.assertIn("pairs=1 equal=1", rec)
        self.assertIn("pairs differ=0 b_missing=0 b_without_a=0", rec)
        self.assertIn("result=equal", rec)

    def test_one_byte_difference_is_listed(self):
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": self.TSV, "a-out-b/glyphs.tsv": self.TSV.replace("kontur", "kontuR")})
        rec, _ = audit(d, "a\n", self._cfg())
        self.assertIn("pairs=1 equal=0", rec)
        self.assertIn("list pair_differ a-out-a/glyphs.tsv a-out-b/glyphs.tsv", rec)
        self.assertIn("complete=false", rec)

    def test_missing_b_and_b_without_a(self):
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": self.TSV, "a-out-b/other.tsv": self.TSV})
        rec, _ = audit(d, "a\n", self._cfg())
        self.assertIn("list pair_b_missing a-out-a/glyphs.tsv a-out-b/glyphs.tsv", rec)
        self.assertIn("list pair_b_without_a a-out-b/other.tsv", rec)

    def test_tsv_row_checks_on_the_b_path_alone(self):
        tsv_b = self.TSV + "x\t66\tok\t\t\n"
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": self.TSV, "a-out-b/glyphs.tsv": tsv_b})
        cfg = self._cfg(tsv_checks=[{"path_regex": "-out-b/glyphs\\.tsv$", "label_column": "path_label", "refusal_value": "empty",
                                    "metric_columns": ["symdiff"], "note_column": "note"}])
        rec, _ = audit(d, "a\n", cfg)
        self.assertIn("tsv_files checked=1", rec)
        self.assertIn("tsv path=a-out-b/glyphs.tsv key=a rows=3 refusal_rows=1 refusal_rows_without_note=0 refusal_rows_with_metric=0 non_refusal_rows_with_empty_metric=1", rec)
        self.assertNotIn("tsv path=a-out-a", rec)

    def test_no_pair_lines_without_config(self):
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": self.TSV, "a-out-b/glyphs.tsv": self.TSV})
        rec, _ = audit(d, "a\n", Config(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                                        allowed_templates=["{key}.done", "{key}-out-a/glyphs.tsv", "{key}-out-b/glyphs.tsv"]))
        self.assertNotIn("pair", rec)


class SafetyTests(unittest.TestCase):
    BASE = dict(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                required_templates=["{key}.done"])

    def _tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            fp = os.path.join(d, rel)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as f:
                f.write(text)
        return d

    def _cfg(self, **kw):
        return Config(**dict(self.BASE, **kw))

    def _cli(self, argv):
        err, old = io.StringIO(), sys.stderr
        out, oldout = io.StringIO(), sys.stdout
        sys.stderr, sys.stdout = err, out
        try:
            rc = main(argv)
        finally:
            sys.stderr, sys.stdout = old, oldout
        return rc, out.getvalue(), err.getvalue()

    def test_s1_control_characters_cannot_forge_receipt_lines(self):
        d = self._tree({"a.done": ""})
        with open(os.path.join(d, "a.done\nlist missing zzz"), "w") as f:
            f.write("x")
        rec, _ = audit(d, "a\n", self._cfg())
        self.assertNotIn("\nlist missing zzz", rec)
        self.assertIn("\\x0a", rec)
        self.assertTrue(all(ln.isprintable() for ln in rec.splitlines()))

    def test_s2_unreadable_subdirectory(self):
        if os.geteuid() == 0:
            self.skipTest("root can read everything")
        d = self._tree({"a.done": "", "sub/x.txt": "x"})
        os.chmod(os.path.join(d, "sub"), 0)
        try:
            rec, summ = audit(d, "a\n", self._cfg())
        finally:
            os.chmod(os.path.join(d, "sub"), 0o755)
        self.assertIn("kind=unreadable_dir", rec)
        self.assertEqual(summ["unreadable"], ["sub"])
        self.assertFalse(summ["complete"])

    def test_s3_key_match_is_exact(self):
        d = self._tree({"a.done": "", "a-sans.done": ""})
        rec, summ = audit(d, "a\n", self._cfg())
        self.assertIn("list unexpected_file a-sans.done", rec)
        self.assertEqual(summ["unexpected_files"], ["a-sans.done"])
        self.assertFalse(summ["complete"])
        rec2, summ2 = audit(self._tree({"a.done": ""}), "a\n", self._cfg())
        self.assertTrue(summ2["complete"], rec2)

    def test_s4_symlinked_directory_is_counted_and_not_scanned(self):
        outside = self._tree({"inner.done": ""})
        d = self._tree({"a.done": ""})
        os.symlink(outside, os.path.join(d, "link"))
        rec, summ = audit(d, "a\n", self._cfg())
        self.assertIn("kind=symlink_dir", rec)
        self.assertNotIn("inner.done", rec)
        self.assertEqual(summ["symlinks"], ["link"])
        self.assertFalse(summ["complete"])

    def test_s5_undecodable_file_name(self):
        d = self._tree({"a.done": ""})
        bad = os.path.join(os.fsencode(d), b"\xff\xfe.txt")
        with open(bad, "wb") as f:
            f.write(b"x")
        rec, summ = audit(d, "a\n", self._cfg())
        rec.encode("utf-8")
        self.assertIn("\\udcff", rec)
        self.assertFalse(summ["complete"])

    def test_s6_missing_root_is_an_input_error(self):
        with self.assertRaises(ValueError):
            audit(os.path.join(tempfile.mkdtemp(), "nope"), "a\n", self._cfg())
        t = tempfile.mkdtemp()
        keys = os.path.join(t, "k.txt")
        with open(keys, "w") as f:
            f.write("a\n")
        rc, out, err = self._cli(["--root", os.path.join(t, "nope"), "--expected", keys, "--key-from-expected", "--result", "path:\\.done$"])
        self.assertEqual(rc, 2)
        self.assertIn("INPUT_ERROR", err)

    def test_s7_complete_needs_no_empty_truncated_changed_unreadable_unexpected(self):
        rec, summ = audit(self._tree({"a.done": ""}), "a\n", self._cfg())
        self.assertTrue(summ["complete"])
        d = self._tree({"a.done": "", "a.txt": ""})
        rec, summ = audit(d, "a\n", self._cfg(allowed_templates=["{key}.txt"]))
        self.assertIn("list empty a.txt", rec)
        self.assertFalse(summ["complete"])
        d = self._tree({"a.done": "", "a.txt": "x" * 50})
        rec, summ = audit(d, "a\n", self._cfg(allowed_templates=["{key}.txt"], max_read=10))
        self.assertIn("list truncated_read a.txt", rec)
        self.assertFalse(summ["complete"])
        rec, summ = audit(self._tree({"a.done": "", "b.done": ""}), "a\n", self._cfg())
        self.assertEqual(summ["unkeyed"], ["b.done"])
        self.assertFalse(summ["complete"])

    def test_s8_config_sha256_in_receipt(self):
        d = self._tree({"a.done": ""})
        r1, s1 = audit(d, "a\n", self._cfg())
        r2, s2 = audit(d, "a\n", self._cfg())
        r3, s3 = audit(d, "a\n", self._cfg(max_read=99))
        self.assertRegex(r1, r"\nconfig_sha256=[0-9a-f]{64} ")
        self.assertEqual(s1["config_sha256"], s2["config_sha256"])
        self.assertNotEqual(s1["config_sha256"], s3["config_sha256"])
        self.assertEqual(hashlib.sha256(json.dumps(__import__("dataclasses").asdict(self._cfg()), sort_keys=True, ensure_ascii=True).encode()).hexdigest(), s1["config_sha256"])

    def test_s9_bom_in_expected_list_and_config(self):
        d = self._tree({"a.done": ""})
        rec, summ = audit(d, "\ufeffa\n", self._cfg())
        self.assertTrue(summ["complete"], rec)
        self.assertEqual(summ["expected_list_sha256"], hashlib.sha256("\ufeffa\n".encode()).hexdigest())
        t = tempfile.mkdtemp()
        keys, cfgp = os.path.join(t, "k.txt"), os.path.join(t, "c.json")
        with open(keys, "wb") as f:
            f.write(b"\xef\xbb\xbfa\n")
        with open(cfgp, "wb") as f:
            f.write(b"\xef\xbb\xbf" + json.dumps(self.BASE).encode())
        rc, out, err = self._cli(["--root", d, "--expected", keys, "--config", cfgp, "--strict"])
        self.assertEqual(rc, 0, err)
        with open(keys, "wb") as f:
            f.write(b"a\xff\n")
        rc, out, err = self._cli(["--root", d, "--expected", keys, "--config", cfgp])
        self.assertEqual(rc, 2)
        self.assertIn("INPUT_ERROR", err)


class HardeningTests(unittest.TestCase):
    BASE = dict(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                required_templates=["{key}.done", "{key}-out-a/glyphs.tsv"])
    TSV = "font\tpath_label\tsymdiff\tnote\nx\tempty\t\tkontur yok\nx\tok\t1.5\t\n"

    def _tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            fp = os.path.join(d, rel)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as f:
                f.write(text)
        return d

    def _cfg(self, tsv=True, **kw):
        c = dict(self.BASE, **kw)
        if tsv:
            c["tsv_checks"] = [{"path_regex": "-out-a/glyphs\\.tsv$", "label_column": "path_label", "refusal_value": "empty",
                               "metric_columns": ["symdiff"], "note_column": "note"}]
        return Config(**c)

    def _tsv_run(self, text):
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": text})
        return audit(d, "a\n", self._cfg())

    def test_baseline_tsv_is_complete(self):
        rec, summ = self._tsv_run(self.TSV)
        self.assertTrue(summ["complete"], rec)
        self.assertEqual(summ["tsv_anomalies"], [])

    def test_x1_redos_pattern_times_out_and_run_continues(self):
        import time
        d = self._tree({"a.done": "a" * 31 + "b", "b.done": "ok"})
        cfg = Config(key_from_expected=True, result_patterns=["content:(a+)+$"], pattern_timeout_seconds=0.3,
                     required_templates=["{key}.done"])
        t0 = time.time()
        rec, summ = audit(d, "a\nb\n", cfg)
        self.assertLess(time.time() - t0, 5)
        self.assertIn("kind=pattern_timeout", rec)
        self.assertEqual(summ["pattern_timeout"], ["a.done result_pattern"])
        self.assertFalse(summ["complete"])
        self.assertIn("limit_class=CONVENTION", rec)

    def test_x1_timeout_setting_must_be_positive(self):
        d = self._tree({"a.done": ""})
        for bad in (0, -1, "x", None):
            with self.assertRaises(ValueError):
                audit(d, "a\n", self._cfg(pattern_timeout_seconds=bad))

    def test_x1_unsupported_platform_is_a_typed_refusal(self):
        import signal
        d = self._tree({"a.done": ""})
        saved = signal.setitimer
        del signal.setitimer
        try:
            with self.assertRaises(ValueError) as cm:
                audit(d, "a\n", self._cfg())
        finally:
            signal.setitimer = saved
        self.assertIn("pattern_timeout_unsupported", str(cm.exception))

    def test_x2_every_tsv_anomaly_is_listed_and_blocks_complete(self):
        cases = {
            "header_missing": "",
            "missing_columns": "font\tpath_label\tnote\nx\tok\t\n",
            "refusal_without_note": "font\tpath_label\tsymdiff\tnote\nx\tempty\t\t\n",
            "refusal_with_metric": "font\tpath_label\tsymdiff\tnote\nx\tempty\t1\tkontur yok\n",
            "short_rows": "font\tpath_label\tsymdiff\tnote\nx\tok\t1\n",
            "non_refusal_empty_metric": "font\tpath_label\tsymdiff\tnote\nx\tok\t\t\n",
        }
        for code, text in cases.items():
            rec, summ = self._tsv_run(text)
            self.assertTrue(any(code in a for a in summ["tsv_anomalies"]), (code, summ["tsv_anomalies"]))
            self.assertIn("list tsv_anomaly", rec)
            self.assertFalse(summ["complete"], code)

    def test_x3_hash_lines_are_counted(self):
        rec, summ = self._tsv_run("# comment\n" + self.TSV + "# tail\n")
        self.assertEqual(summ["tsv_skipped_hash_lines"], 2)
        self.assertIn("skipped_hash_lines=2", rec)
        self.assertFalse(summ["complete"])

    def test_x4_duplicate_header_and_long_rows(self):
        rec, summ = self._tsv_run("font\tpath_label\tsymdiff\tsymdiff\tnote\nx\tok\t1\t2\t\n")
        self.assertTrue(any("duplicate_header" in a for a in summ["tsv_anomalies"]))
        self.assertFalse(summ["complete"])
        rec, summ = self._tsv_run("font\tpath_label\tsymdiff\tnote\nx\tok\t1\t\textra\n")
        self.assertTrue(any("long_rows=1" in a for a in summ["tsv_anomalies"]), summ["tsv_anomalies"])
        self.assertFalse(summ["complete"])

    def test_x5_metric_syntax_is_strict(self):
        for bad in (" ", "NaN", "abc", "1e5", "inf", "1,5", "\u0661", "1" * 400):
            rec, summ = self._tsv_run("font\tpath_label\tsymdiff\tnote\nx\tok\t%s\t\n" % bad)
            self.assertTrue(any("metric_invalid=1" in a for a in summ["tsv_anomalies"]), (bad, summ["tsv_anomalies"]))
            self.assertFalse(summ["complete"])
        for good in ("0", "-1", "+2.5", ".5", "10.25"):
            rec, summ = self._tsv_run("font\tpath_label\tsymdiff\tnote\nx\tok\t%s\t\n" % good)
            self.assertTrue(summ["complete"], (good, summ["tsv_anomalies"]))

    def test_x5_refusal_label_is_case_sensitive(self):
        rec, summ = self._tsv_run("font\tpath_label\tsymdiff\tnote\nx\tEmpty\t\tkontur yok\n")
        self.assertTrue(any("non_refusal_empty_metric=1" in a for a in summ["tsv_anomalies"]))

    def test_x6_unmatched_exceptions(self):
        d = self._tree({"a.done": "", "a-out-a/glyphs.tsv": self.TSV})
        for exc in ({"{key}.nothing": ["a"]}, {"{key}.done": ["zzz"]}, {"{key}.done": ["b"]}):
            rec, summ = audit(d, "a\nb\n", self._cfg(required_exceptions=exc))
            self.assertTrue(summ["unmatched_exceptions"], exc)
            self.assertIn("list unmatched_exception", rec)
            self.assertFalse(summ["complete"])
        rec, summ = audit(d, "a\n", self._cfg(required_exceptions={"{key}.done": ["a"]}))
        self.assertEqual(summ["unmatched_exceptions"], [])

    def test_x7_key_does_not_cross_a_slash(self):
        d = self._tree({"a.done": "", "a/b.done": ""})
        rec, summ = audit(d, "a\n", self._cfg(tsv=False, required_templates=["{key}.done"]))
        self.assertEqual(summ["unkeyed"], ["a/b.done"])
        self.assertFalse(summ["complete"])

    def test_x8_max_read_below_one(self):
        d = self._tree({"a.done": ""})
        for bad in (0, -5):
            with self.assertRaises(ValueError):
                audit(d, "a\n", self._cfg(max_read=bad))
        t = tempfile.mkdtemp()
        keys = os.path.join(t, "k.txt")
        with open(keys, "w") as f:
            f.write("a\n")
        err, old = io.StringIO(), sys.stderr
        sys.stderr = err
        try:
            rc = main(["--root", d, "--expected", keys, "--key-from-expected", "--result", "path:\\.done$", "--max-read", "0"])
        finally:
            sys.stderr = old
        self.assertEqual(rc, 2)
        self.assertIn("INPUT_ERROR", err.getvalue())

    def test_unknown_config_key_is_an_input_error(self):
        from sweepaudit.core import config_from_dict
        with self.assertRaises(ValueError):
            config_from_dict({"key_from_expected": True, "pattern_timout_seconds": 1})


class CounterAndLoaderTests(unittest.TestCase):
    BASE = dict(key_from_expected=True, result_patterns=["path:^[^/]+\\.done$"], empty_ok_regex="\\.done$",
                required_templates=["{key}.done"], sweep_level_regex="^runner\\.log$")

    def _tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            fp = os.path.join(d, rel)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as f:
                f.write(text)
        return d

    @staticmethod
    def _sum(summ):
        return (summ["keyed"] + len(summ["unkeyed"]) + len(summ["sweep_level"]) + summ["unreadable_files"] + len(summ["symlinks"]))

    def test_v5_classes_are_disjoint_in_each_scenario(self):
        cfg = dict(self.BASE, allowed_templates=["{key}.done.x"])
        outside = self._tree({"inner.done": ""})
        cases = []
        d = self._tree({"a.done": ""})
        hidden = os.path.join(d, "a.done.x")
        with open(hidden, "w") as f:
            f.write("x")
        os.chmod(hidden, 0)
        cases.append(("unreadable", d, dict(keyed=1, unreadable_files=1), hidden))
        cases.append(("sweep_level", self._tree({"a.done": "", "FAIL.log": "x"}), dict(keyed=1, sweep_level=1), None))
        d = self._tree({"a.done": ""})
        os.symlink(outside, os.path.join(d, "dl"))
        cases.append(("dirlink", d, dict(keyed=1, symlinks=1), None))
        cases.append(("empty", self._tree({"a.done": "", "a-empty.done": ""}), dict(keyed=2), None))
        for name, d, want, hid in cases:
            if hid and os.geteuid() == 0:
                continue
            try:
                rec, summ = audit(d, "a\n", Config(**dict(cfg, sweep_level_regex="^FAIL\\.log$")))
            finally:
                if hid:
                    os.chmod(hid, 0o644)
            got = dict(keyed=summ["keyed"], unkeyed=len(summ["unkeyed"]), sweep_level=len(summ["sweep_level"]),
                       unreadable_files=summ["unreadable_files"], symlinks=len(summ["symlinks"]))
            exp = dict(keyed=0, unkeyed=0, sweep_level=0, unreadable_files=0, symlinks=0)
            exp.update(want)
            self.assertEqual(got, exp, name)
            self.assertEqual(sum(got.values()), summ["files_total"], name)
            self.assertIn("sweep_level=%d unreadable_files=%d" % (exp["sweep_level"], exp["unreadable_files"]), rec)

    def _cli(self, argv):
        err, old = io.StringIO(), sys.stderr
        out, oldout = io.StringIO(), sys.stdout
        sys.stderr, sys.stdout = err, out
        try:
            rc = main(argv)
        finally:
            sys.stderr, sys.stdout = old, oldout
        return rc, out.getvalue(), err.getvalue()

    def test_n1_counters_add_up_with_every_kind_of_entry(self):
        outside = self._tree({"inner.done": ""})
        d = self._tree({"a.done": "", "a-x.done": "", "runner.log": "x", "loose.txt": "x", "sub/deep.txt": "x"})
        os.symlink(outside, os.path.join(d, "dirlink"))
        os.symlink(os.path.join(d, "a.done"), os.path.join(d, "filelink"))
        if os.geteuid() != 0:
            with open(os.path.join(d, "a.hidden"), "w") as f:
                f.write("x")
            os.chmod(os.path.join(d, "a.hidden"), 0)
        try:
            rec, summ = audit(d, "a\n", Config(**self.BASE, allowed_templates=["{key}.hidden"]))
        finally:
            if os.geteuid() != 0:
                os.chmod(os.path.join(d, "a.hidden"), 0o644)
        self.assertEqual(sorted(summ["symlinks"]), ["dirlink", "filelink"])
        self.assertGreaterEqual(summ["keyed"], 0)
        self.assertEqual(self._sum(summ), summ["files_total"], rec)
        line = [ln for ln in rec.splitlines() if ln.startswith("files total=")][0]
        import re as _re
        n = {k: int(v) for k, v in _re.findall(r"(\w+)=(\d+)", line)}
        self.assertEqual(n["keyed"] + n["unkeyed"] + n["sweep_level"] + n["unreadable_files"] + n["symlinks"], n["total"], line)
        self.assertEqual(n["symlinks"], 2)

    def test_n1_only_a_symlinked_directory(self):
        outside = self._tree({"inner.done": ""})
        d = self._tree({"a.done": ""})
        os.symlink(outside, os.path.join(d, "dirlink"))
        rec, summ = audit(d, "a\n", Config(**self.BASE))
        self.assertEqual((summ["files_total"], summ["keyed"], len(summ["symlinks"])), (2, 1, 1))

    def test_n2_key_from_expected_needs_templates(self):
        d = self._tree({"a.done": ""})
        for kw in ({}, {"required_templates": []}, {"required_templates": ["x/{key}.done"]}):
            base = dict(self.BASE)
            base.pop("required_templates")
            with self.assertRaises(ValueError) as cm:
                audit(d, "a\n", Config(**dict(base, **kw)))
            self.assertIn("key_from_expected needs templates", str(cm.exception))
        t = tempfile.mkdtemp()
        keys = os.path.join(t, "k.txt")
        with open(keys, "w") as f:
            f.write("a\n")
        rc, out, err = self._cli(["--root", d, "--expected", keys, "--key-from-expected", "--result", "path:\\.done$"])
        self.assertEqual(rc, 2)
        self.assertIn("key_from_expected needs templates", err)
        audit(d, "a\n", Config(**dict(self.BASE, allowed_templates=["{key}.done"])))

    def test_x1b_key_regex_catastrophic_pattern_is_a_timeout_finding(self):
        d = self._tree({"a" * 32 + "!.txt": "x"})
        cfg = Config(key_regex="((a+)+)$", result_patterns=["path:\\.txt$"], pattern_timeout_seconds=0.2)
        rec, summ = audit(d, "a\n", cfg)
        self.assertEqual(len(summ["pattern_timeout"]), 1, rec)
        self.assertIn("key_regex", summ["pattern_timeout"][0])
        self.assertIn("kind=pattern_timeout", rec)
        self.assertFalse(summ["complete"])
        self.assertEqual(self._sum(summ), summ["files_total"])

    def test_x1b_every_config_pattern_goes_through_the_limited_search(self):
        import re as _re
        with open(os.path.join(os.path.dirname(__file__), "..", "sweepaudit", "core.py")) as fh:
            src = fh.read()
        body = src.split("def _search", 1)[1].split("\n\n\n", 1)[1]
        self.assertEqual(_re.findall(r"\b\w+\.(?:search|match|fullmatch)\(", body.replace("_NUMBER.fullmatch(", "")), [])

    def test_v3_strict_loader_refuses_duplicates_and_nonfinite(self):
        from sweepaudit.core import load_json_strict
        self.assertEqual(load_json_strict(b'\xef\xbb\xbf{"a": 1}'), {"a": 1})
        for bad in ('{"a": 1, "a": 2}', '{"x": {"a": 1, "a": 1}}', '{"a": NaN}', '[Infinity]'):
            with self.assertRaises(ValueError):
                load_json_strict(bad)

    def test_v3_cli_config_with_duplicate_key_is_an_input_error(self):
        d = self._tree({"a.done": ""})
        t = tempfile.mkdtemp()
        keys, cfgp = os.path.join(t, "k.txt"), os.path.join(t, "c.json")
        with open(keys, "w") as f:
            f.write("a\n")
        with open(cfgp, "w") as f:
            f.write('{"key_from_expected": true, "allowed_templates": ["{key}.done"], "result_patterns": ["path:\\\\.done$"], "max_read": 5, "max_read": 6}')
        rc, out, err = self._cli(["--root", d, "--expected", keys, "--config", cfgp])
        self.assertEqual(rc, 2)
        self.assertIn("DUPLICATE_JSON_KEY", err)

if __name__ == "__main__":
    unittest.main()
