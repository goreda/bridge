import copy
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import verify  # noqa: E402

SCHEMA = HERE / "sweep-record.schema.json"
CONFIG = {"key_from_expected": True, "result_patterns": ["path:^[^/]+\\.done$"], "empty_ok_regex": "\\.done$",
          "required_templates": ["{key}.done", "{key}-out-a/g.tsv", "{key}-out-b/g.tsv"],
          "pair_checks": [{"a_regex": "^(?P<key>[^/]+)-out-a/(?P<rest>.+)$", "b_template": "{key}-out-b/{rest}", "b_regex": "-out-b/"}]}


def make_tree(b_text="x\n", with_b=True):
    d = tempfile.mkdtemp()
    for rel, text in {"k1.done": "", "k1-out-a/g.tsv": "x\n", "k1-out-b/g.tsv": b_text}.items():
        if rel.startswith("k1-out-b") and not with_b:
            continue
        fp = os.path.join(d, rel)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        Path(fp).write_text(text)
    return d


def run(root, expected="k1\n", strict=False, schema=SCHEMA):
    t = tempfile.mkdtemp()
    paths = {"exp": os.path.join(t, "e.txt"), "cfg": os.path.join(t, "c.json"), "out": os.path.join(t, "out")}
    Path(paths["exp"]).write_text(expected)
    Path(paths["cfg"]).write_text(json.dumps(CONFIG))
    argv = ["--root", root, "--expected", paths["exp"], "--config", paths["cfg"], "--schema", str(schema), "--out", paths["out"]]
    if strict:
        argv.append("--strict")
    buf, old = io.StringIO(), sys.stdout
    sys.stdout = buf
    try:
        rc = verify.main(argv)
    finally:
        sys.stdout = old
    return rc, buf.getvalue(), paths["out"]


class VerifyTests(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads(SCHEMA.read_text())

    def record(self, **kw):
        rc, _, out = run(make_tree(**kw))
        return json.loads((Path(out) / "record.json").read_text())

    def test_schema_is_valid(self):
        from jsonschema import Draft202012Validator
        Draft202012Validator.check_schema(self.schema)

    def test_complete_tree_is_valid_and_bound(self):
        rc, text, out = run(make_tree())
        self.assertEqual(rc, 0, text)
        self.assertIn("SCHEMA_VALID_DESCRIPTIVE_ONLY", text)
        rec = json.loads((Path(out) / "record.json").read_text())
        self.assertTrue(rec["complete"])
        self.assertEqual(rec["counts"]["one_result"], 1)
        import hashlib
        self.assertEqual(rec["receipt_sha256"], hashlib.sha256((Path(out) / "receipt.txt").read_bytes()).hexdigest())

    def test_incomplete_sweep_is_valid_record_and_strict_fails(self):
        rc, _, out = run(make_tree(b_text="y\n"))
        self.assertEqual(rc, 0)
        rec = json.loads((Path(out) / "record.json").read_text())
        self.assertFalse(rec["complete"])
        self.assertEqual(rec["lists"]["pair_differ"], ["k1-out-a/g.tsv k1-out-b/g.tsv"])
        rc, _, _ = run(make_tree(b_text="y\n"), strict=True)
        self.assertEqual(rc, 1)

    def test_missing_b_and_missing_key(self):
        rec = self.record(with_b=False)
        self.assertEqual(rec["lists"]["pair_b_missing"], ["k1-out-a/g.tsv k1-out-b/g.tsv"])
        rc, _, out = run(make_tree(), expected="k1\nk2\n")
        rec = json.loads((Path(out) / "record.json").read_text())
        self.assertEqual(rec["lists"]["missing"], ["k2"])

    def test_schema_rejections(self):
        base = self.record()
        cases = {
            "mode": lambda r: r.update(mode="PASS"),
            "extra_winner": lambda r: r.update(winner=True),
            "bad_sha": lambda r: r.update(receipt_sha256="abc"),
            "threshold": lambda r: r.update(threshold_policy="p<0.05"),
            "complete_with_missing": lambda r: r["lists"].update(missing=["k2"]),
            "complete_with_pair_differ": lambda r: r["lists"].update(pair_differ=["a b"]),
            "no_lists": lambda r: r.pop("lists"),
            "negative_count": lambda r: r["counts"].update(files_total=-1),
            "complete_with_symlink": lambda r: r["lists"].update(symlinks=["l"]),
            "complete_with_unexpected_file": lambda r: r["lists"].update(unexpected_files=["a-x.done"]),
            "complete_with_empty": lambda r: r["lists"].update(empty=["e"]),
            "complete_with_truncated": lambda r: r["lists"].update(truncated=["t"]),
            "bad_config_sha": lambda r: r.update(config_sha256="x"),
            "no_config_sha": lambda r: r.pop("config_sha256"),
            "complete_with_tsv_anomaly": lambda r: r["lists"].update(tsv_anomalies=["p x"]),
            "complete_with_timeout": lambda r: r["lists"].update(pattern_timeout=["p x"]),
            "complete_with_unmatched": lambda r: r["lists"].update(unmatched_exceptions=["t"]),
            "complete_with_hash_lines": lambda r: r["counts"].update(tsv_skipped_hash_lines=1),
        }
        for name, change in cases.items():
            r = copy.deepcopy(base)
            change(r)
            self.assertTrue(verify.validate(r, self.schema), name)
        self.assertEqual(verify.validate(base, self.schema), [])

    def test_input_errors_exit_2(self):
        rc, _, _ = run(make_tree(), schema=HERE / "does-not-exist.json")
        self.assertEqual(rc, 2)
        t = tempfile.mkdtemp()
        bad = os.path.join(t, "s.json")
        Path(bad).write_text('{"a": NaN}')
        rc, _, _ = run(make_tree(), schema=bad)
        self.assertEqual(rc, 2)
        d = make_tree()
        rc1, _, out = run(d)
        self.assertEqual(rc1, 0)
        argv = ["--root", d, "--expected", os.path.join(os.path.dirname(out), "e.txt"), "--config", os.path.join(os.path.dirname(out), "c.json"),
                "--schema", str(SCHEMA), "--out", out]
        self.assertEqual(verify.main(argv), 2)

    def test_missing_root_exit_2(self):
        rc, _, _ = run(os.path.join(tempfile.mkdtemp(), "nope"))
        self.assertEqual(rc, 2)

    def test_binding_failure_exit_1(self):
        orig = verify.build_record

        def tampered(text, summary):
            r = orig(text, summary)
            r["receipt_sha256"] = "0" * 64
            return r
        verify.build_record = tampered
        try:
            rc, text, _ = run(make_tree())
        finally:
            verify.build_record = orig
        self.assertEqual(rc, 1)
        self.assertIn("does not match receipt.txt", text)


class RobustnessTests(unittest.TestCase):
    def _call(self, root, cfg_text=None, schema_path=SCHEMA, out_rel="out"):
        t = tempfile.mkdtemp()
        e, c = os.path.join(t, "e.txt"), os.path.join(t, "c.json")
        Path(e).write_text("k1\n")
        Path(c).write_text(cfg_text if cfg_text is not None else json.dumps(CONFIG))
        out = os.path.join(t, out_rel)
        err, old, olde = io.StringIO(), sys.stdout, sys.stderr
        sys.stdout, sys.stderr = io.StringIO(), err
        try:
            rc = verify.main(["--root", root, "--expected", e, "--config", c, "--schema", str(schema_path), "--out", out])
        finally:
            sys.stdout, sys.stderr = old, olde
        return rc, err.getvalue(), out

    def test_duplicate_key_in_config_is_input_error(self):
        dup = json.dumps(CONFIG)[:-1] + ', "empty_ok_regex": "x"}'
        rc, err, out = self._call(make_tree(), dup)
        self.assertEqual(rc, 2)
        self.assertIn("DUPLICATE_JSON_KEY", err)
        self.assertFalse(os.path.exists(out))

    def test_duplicate_key_in_schema_is_input_error(self):
        t = tempfile.mkdtemp()
        sp = os.path.join(t, "s.json")
        Path(sp).write_text('{"type": "object", "type": "array"}')
        rc, err, out = self._call(make_tree(), schema_path=sp)
        self.assertEqual(rc, 2)
        self.assertIn("DUPLICATE_JSON_KEY", err)

    def test_missing_output_parent_is_input_error(self):
        rc, err, out = self._call(make_tree(), out_rel="nope/out")
        self.assertEqual(rc, 2)
        self.assertIn("parent directory", err)
        self.assertFalse(os.path.exists(os.path.dirname(out)))

    def test_counts_match_lists_and_total(self):
        d = make_tree()
        os.symlink(d, os.path.join(d, "dl"))
        rc, err, out = self._call(d)
        rec = json.loads((Path(out) / "record.json").read_text())
        c = rec["counts"]
        self.assertEqual(sum(c[k] for k in ("keyed", "unkeyed", "sweep_level", "unreadable_files", "symlinks")), c["files_total"])
        self.assertEqual(c["symlinks"], len(rec["lists"]["symlinks"]))
        self.assertFalse(rec["complete"])

    def test_disjoint_classes_in_record(self):
        d = make_tree()
        Path(d, "runner.log").write_text("x")
        hidden = Path(d, "k1.done.x")
        hidden.write_text("x")
        hidden.chmod(0)
        cfg = dict(CONFIG, sweep_level_regex="^runner\\.log$", allowed_templates=["{key}.done.x"])
        t = tempfile.mkdtemp()
        e, c, out = os.path.join(t, "e.txt"), os.path.join(t, "c.json"), os.path.join(t, "out")
        Path(e).write_text("k1\n")
        Path(c).write_text(json.dumps(cfg))
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            verify.main(["--root", d, "--expected", e, "--config", c, "--schema", str(SCHEMA), "--out", out])
        finally:
            sys.stdout = old
            hidden.chmod(0o644)
        rec = json.loads((Path(out) / "record.json").read_text())
        c = rec["counts"]
        if os.geteuid() != 0:
            self.assertEqual((c["sweep_level"], c["unreadable_files"]), (1, 1))
        self.assertEqual(rec["lists"]["sweep_level"], ["runner.log"])
        self.assertEqual(sum(c[k] for k in ("keyed", "unkeyed", "sweep_level", "unreadable_files", "symlinks")), c["files_total"])
        r = copy.deepcopy(rec)
        r["counts"]["sweep_level"] += 1
        self.assertTrue(verify.validate(r, json.loads(SCHEMA.read_text())))

    def test_semantic_count_mismatch_is_reported(self):
        d = make_tree()
        rc, err, out = self._call(d)
        rec = json.loads((Path(out) / "record.json").read_text())
        schema = json.loads(SCHEMA.read_text())
        self.assertEqual(verify.validate(rec, schema), [])
        rec["counts"]["pattern_timeouts"] = 3
        rec["counts"]["keyed"] += 1
        errs = verify.validate(rec, schema)
        self.assertEqual(len(errs), 2, errs)

    def test_tsv_anomaly_and_timeout_lists_block_complete_in_schema(self):
        d = make_tree()
        rc, err, out = self._call(d)
        rec = json.loads((Path(out) / "record.json").read_text())
        schema = json.loads(SCHEMA.read_text())
        for lk in ("tsv_anomalies", "unmatched_exceptions", "pattern_timeout"):
            r = copy.deepcopy(rec)
            r["complete"] = True
            r["lists"][lk] = ["x"]
            self.assertTrue(verify.validate(r, schema), lk)

    def test_failed_validation_still_writes_output(self):
        t = tempfile.mkdtemp()
        sp = os.path.join(t, "s.json")
        Path(sp).write_text('{"type": "array"}')
        rc, err, out = self._call(make_tree(), schema_path=sp)
        self.assertEqual(rc, 1)
        self.assertTrue(os.path.exists(os.path.join(out, "record.json")))

if __name__ == "__main__":
    unittest.main()
