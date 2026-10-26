"""Tests for the CONC integration harness. Pure stdlib; no engine build needed.

Run from the engine root:  python3 -m unittest discover -s tools/conc/tests -v
"""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

CONC_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, CONC_DIR)

import conc_conflicts
import conc_gate
import conc_queue
import diffpaths

GIT_DIFF = """diff --git a/metrics/src/spacing_oohh.rs b/metrics/src/spacing_oohh.rs
new file mode 100644
--- /dev/null
+++ b/metrics/src/spacing_oohh.rs
@@ -0,0 +1 @@
+// layer
diff --git a/pipeline/src/main.rs b/pipeline/src/main.rs
--- a/pipeline/src/main.rs
+++ b/pipeline/src/main.rs
@@ -1 +1,2 @@
 fn main() {}
+// call site
"""

PLAIN_DIFF = """--- old/name.rs
+++ new/name.rs
@@ -1 +1 @@
-a
+b
"""

DELETE_DIFF = """diff --git a/gone.rs b/gone.rs
deleted file mode 100644
--- a/gone.rs
+++ /dev/null
@@ -1 +0,0 @@
-x
"""

RENAME_DIFF = """diff --git a/before.rs b/after.rs
similarity index 90%
rename from before.rs
rename to after.rs
--- a/before.rs
+++ b/after.rs
@@ -1 +1 @@
-x
+y
"""


def write(tmp, name, text):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def quiet(fn, *a, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fn(*a, **kw)
    return buf.getvalue()


class TestDiffPaths(unittest.TestCase):
    def test_git_diff_new_and_modified(self):
        self.assertEqual(
            diffpaths.extract_touched_files(GIT_DIFF),
            ["metrics/src/spacing_oohh.rs", "pipeline/src/main.rs"])

    def test_plain_diff(self):
        self.assertEqual(diffpaths.extract_touched_files(PLAIN_DIFF), ["new/name.rs"])

    def test_deleted_file_keeps_old_path(self):
        self.assertEqual(diffpaths.extract_touched_files(DELETE_DIFF), ["gone.rs"])

    def test_rename_reports_both_sides(self):
        self.assertEqual(diffpaths.extract_touched_files(RENAME_DIFF),
                         ["before.rs", "after.rs"])

    def test_non_diff_refused(self):
        with self.assertRaises(ValueError):
            diffpaths.extract_touched_files("not a diff\n")


class QueueCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.qdir = os.path.join(self.tmp, "queue")
        self.diff = write(self.tmp, "w7.diff", GIT_DIFF)

class TestQueue(QueueCase):
    def test_intake_stores_diff_and_event(self):
        quiet(conc_queue.main, ["intake", "--queue", self.qdir, "--writer", "W7",
                                "--base-sha", "a7f891e4", "--diff", self.diff])
        events = conc_queue.read_ledger(self.qdir)
        self.assertEqual(len(events), 1)
        ev = events[0]
        self.assertEqual(ev["seq"], 1)
        self.assertEqual(ev["writer"], "W7")
        self.assertEqual(ev["files"], ["metrics/src/spacing_oohh.rs", "pipeline/src/main.rs"])
        stored = os.path.join(self.qdir, ev["diff_path"])
        with open(stored, "rb") as fh:
            import hashlib
            self.assertEqual(hashlib.sha256(fh.read()).hexdigest(), ev["diff_sha256"])

    def test_seq_increments(self):
        for _ in range(2):
            quiet(conc_queue.main, ["intake", "--queue", self.qdir, "--writer", "W9",
                                    "--base-sha", "a7f891e4", "--diff", self.diff])
        seqs = [ev["seq"] for ev in conc_queue.read_ledger(self.qdir)]
        self.assertEqual(seqs, [1, 2])

    def test_resolve_then_order(self):
        quiet(conc_queue.main, ["intake", "--queue", self.qdir, "--writer", "W7",
                                "--base-sha", "a7f891e4", "--diff", self.diff])
        quiet(conc_queue.main, ["resolve", "--queue", self.qdir, "--seq", "1",
                                "--outcome", "merged"])
        out = quiet(conc_queue.main, ["order", "--queue", self.qdir, "--json"])
        rows = [json.loads(line) for line in out.splitlines() if line.strip()]
        self.assertEqual([r["seq"] for r in rows], [1])
        self.assertEqual(rows[0]["writer"], "W7")

    def test_double_resolve_refused(self):
        quiet(conc_queue.main, ["intake", "--queue", self.qdir, "--writer", "W7",
                                "--base-sha", "a7f891e4", "--diff", self.diff])
        quiet(conc_queue.main, ["resolve", "--queue", self.qdir, "--seq", "1",
                                "--outcome", "rejected"])
        with self.assertRaises(SystemExit) as cm:
            quiet(conc_queue.main, ["resolve", "--queue", self.qdir, "--seq", "1",
                                    "--outcome", "merged"])
        self.assertNotEqual(cm.exception.code, 0)

    def test_unknown_seq_refused(self):
        with self.assertRaises(SystemExit) as cm:
            quiet(conc_queue.main, ["resolve", "--queue", self.qdir, "--seq", "9",
                                    "--outcome", "merged"])
        self.assertNotEqual(cm.exception.code, 0)

    def test_non_diff_intake_refused(self):
        bad = write(self.tmp, "bad.diff", "hello\n")
        with self.assertRaises(SystemExit) as cm:
            quiet(conc_queue.main, ["intake", "--queue", self.qdir, "--writer", "W7",
                                    "--base-sha", "a7f891e4", "--diff", bad])
        self.assertNotEqual(cm.exception.code, 0)


MAP = {
    "schema": "kni-conc-module-map/1",
    "root_prefix": "",
    "shared": ["pipeline/src/main.rs"],
    "writers": {
        "W7": {"paths": ["metrics/src/spacing_oohh.rs"], "globs": []},
        "W9": {"paths": [], "globs": ["**/fit_objective.rs"]},
        "WX": {"paths": [], "globs": []},
    },
}


class TestConflicts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.map_path = os.path.join(self.tmp, "map.json")
        with open(self.map_path, "w", encoding="utf-8") as fh:
            json.dump(MAP, fh)

    def check(self, diffs):
        return conc_conflicts.check(MAP, diffs, "")

    def test_clean(self):
        report = self.check({"W7": ["metrics/src/spacing_oohh.rs"],
                             "W9": ["pipeline/src/fit_objective.rs"]})
        self.assertTrue(report["ok"])
        self.assertEqual(report["conflicts"], [])
        self.assertEqual(report["violations"], [])

    def test_out_of_map_violation(self):
        report = self.check({"W7": ["metrics/src/other.rs"]})
        self.assertFalse(report["ok"])
        self.assertEqual(report["violations"][0]["path"], "metrics/src/other.rs")

    def test_cross_writer_conflict(self):
        report = self.check({"W7": ["metrics/src/spacing_oohh.rs"],
                             "W9": ["metrics/src/spacing_oohh.rs"]})
        self.assertFalse(report["ok"])
        self.assertEqual(report["conflicts"][0]["writers"], ["W7", "W9"])

    def test_shared_touch_is_informational(self):
        report = self.check({"W7": ["metrics/src/spacing_oohh.rs", "pipeline/src/main.rs"]})
        self.assertTrue(report["ok"])
        self.assertEqual(len(report["shared_touches"]), 1)

    def test_unmapped_writer_flagged_not_violation(self):
        report = self.check({"WX": ["anything.rs"]})
        self.assertTrue(report["ok"])
        self.assertEqual(report["unmapped"][0]["path"], "anything.rs")

    def test_unknown_writer_is_violation(self):
        report = self.check({"W99": ["x.rs"]})
        self.assertFalse(report["ok"])

    def test_root_prefix_stripped(self):
        report = conc_conflicts.check(
            MAP, {"W7": ["kni-kit/out8-runkit-v2/engine/metrics/src/spacing_oohh.rs"]},
            "kni-kit/out8-runkit-v2/engine/")
        self.assertTrue(report["ok"])

    def test_cli_queue_mode(self):
        qdir = os.path.join(self.tmp, "q")
        diff = write(self.tmp, "w7.diff", GIT_DIFF)
        quiet(conc_queue.main, ["intake", "--queue", qdir, "--writer", "W7",
                                "--base-sha", "a7f891e4", "--diff", diff])
        with self.assertRaises(SystemExit) as cm:
            quiet(conc_conflicts.main,
                  ["--module-map", self.map_path, "--queue", qdir])
        self.assertEqual(cm.exception.code, 0)


class TestGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = os.path.join(self.tmp, "base")
        os.makedirs(self.root)
        write(self.root, "code.txt", "line one\n")
        self.diff = write(self.tmp, "ok.diff", """--- a/code.txt
+++ b/code.txt
@@ -1 +1,2 @@
 line one
+gate-marker
""")

    def gate(self, check_cmd="true", test_cmd="true"):
        work = os.path.join(self.tmp, "work")
        argv = ["--engine-root", self.root, "--diff", self.diff,
                "--work-dir", work, "--base-sha", "a7f891e4",
                "--check-cmd", check_cmd, "--test-cmd", test_cmd]
        code = None
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            try:
                conc_gate.main(argv)
            except SystemExit as exc:
                code = exc.code
        return code, json.loads(buf.getvalue())

    def test_pass_receipt(self):
        code, receipt = self.gate(test_cmd="grep -q gate-marker code.txt")
        self.assertEqual(code, 0)
        self.assertEqual(receipt["schema"], "kni-conc-gate/1")
        self.assertEqual(receipt["outcome"], "PASS")
        self.assertEqual(receipt["base_verified"], "declared")

    def test_failing_test_fails_gate(self):
        code, receipt = self.gate(test_cmd="grep -q absent-marker code.txt")
        self.assertEqual(code, 1)
        self.assertEqual(receipt["outcome"], "FAIL")
        self.assertEqual(receipt["stage"], "test")

    def test_failing_check_skips_test(self):
        code, receipt = self.gate(check_cmd="false")
        self.assertEqual(code, 1)
        self.assertEqual(receipt["stage"], "check")
        self.assertNotIn("test", receipt)

    def test_unappliable_diff_fails(self):
        write(self.tmp, "ok.diff", "--- a/code.txt\n+++ b/code.txt\n@@ -1 +1 @@\n-nope\n+yes\n")
        code, receipt = self.gate()
        self.assertEqual(code, 1)
        self.assertEqual(receipt["stage"], "apply")


if __name__ == "__main__":
    unittest.main()
