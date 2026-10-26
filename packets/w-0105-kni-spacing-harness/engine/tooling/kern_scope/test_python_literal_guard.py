"""Tests for python_literal_guard. Fixture sources are inline text; nothing is executed."""
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import python_literal_guard as g

TEST_ENGINE_ROOT = os.path.join(HERE, "..", "..")
TEST_MANIFEST = os.path.join(HERE, "fixtures", "python-scope-manifest.tsv")
TEST_HEADER = "\t".join(g.MANIFEST_COLUMNS) + "\n"
TEST_WHY = "reason text"
TEST_LITERAL = 7
TEST_FLOAT = 2.5
TEST_LINE_OF_NINE = 5


def messages(src, structural=(), is_test=False):
    return [m for _, m in g.scan(src, "x.py", set(structural), is_test)]


class Scan(unittest.TestCase):
    def test_named_constants_are_allowed(self):
        self.assertEqual(messages("LIMIT = 40\nMASK = (1 << 15) - 1\nPAIR = (3, 4)\nA, B = 5, 6\n"), [])

    def test_bare_literal_in_code_is_a_finding(self):
        f = messages("LIMIT = 40\ndef f(x):\n    return x + 7\n")
        self.assertEqual(f, ["bare numeric literal 7"])

    def test_float_and_negative_and_hex_are_findings(self):
        src = "def f():\n    return [2.5, -3, 0xFF]\n"
        self.assertEqual(sorted(messages(src)), sorted(["bare numeric literal 2.5", "bare numeric literal 3",
                                                        "bare numeric literal 255"]))

    def test_structural_values_come_from_the_manifest_only(self):
        src = "def f(x):\n    return x[0] + 1\n"
        self.assertEqual(len(messages(src)), 2)
        self.assertEqual(messages(src, {0, 1}), [])
        self.assertEqual(messages("def f():\n    return 2\n", {0, 1}), ["bare numeric literal 2"])

    def test_float_is_never_structural(self):
        self.assertEqual(messages("def f():\n    return 1.0\n", {1}), ["bare numeric literal 1.0"])

    def test_bool_and_strings_are_not_numbers(self):
        self.assertEqual(messages("def f():\n    return True, '12', b'3'\n"), [])

    def test_constant_name_must_be_upper_snake(self):
        self.assertEqual(messages("limit = 40\n"), ["bare numeric literal 40"])
        self.assertEqual(messages("Limit = 40\n"), ["bare numeric literal 40"])

    def test_constant_value_must_be_a_constant_expression(self):
        self.assertEqual(messages("LIMIT = compute(40)\n"), ["bare numeric literal 40"])
        self.assertEqual(messages("OTHER = 3\nLIMIT = OTHER * 2\n"), [])

    def test_only_module_level_assignment_counts(self):
        self.assertEqual(messages("def f():\n    LIMIT = 40\n    return LIMIT\n"), ["bare numeric literal 40"])
        self.assertEqual(messages("class C:\n    LIMIT = 40\n"), ["bare numeric literal 40"])

    def test_default_argument_and_comparison_are_findings(self):
        self.assertEqual(messages("def f(x=9):\n    return x < 5\n"),
                         ["bare numeric literal 9", "bare numeric literal 5"])

    def test_test_prefix_is_exempt_only_in_test_files(self):
        src = "TEST_LIMIT = 40\n"
        self.assertEqual(messages(src, is_test=True), [])
        self.assertEqual(messages(src, is_test=False), ["TEST_ constant outside a test_*.py file"])

    def test_test_prefix_does_not_exempt_code_literals(self):
        self.assertEqual(messages("TEST_A = 3\ndef f():\n    return 4\n", is_test=True), ["bare numeric literal 4"])

    def test_syntax_error_is_not_swallowed(self):
        with self.assertRaises(SyntaxError):
            g.scan("def (:\n", "x.py", set(), False)

    def test_line_numbers(self):
        self.assertEqual(g.scan("LIMIT = 1\n\n\ndef f():\n    return 9\n", "x.py", set(), False), [(TEST_LINE_OF_NINE, "bare numeric literal 9")])


class Manifest(unittest.TestCase):
    def test_header_and_fields(self):
        with self.assertRaises(g.GuardError):
            g.parse_manifest("file\tscope\n")
        with self.assertRaises(g.GuardError):
            g.parse_manifest(TEST_HEADER + "a.py\tscoped\t0\n")

    def test_scope_value_and_reason(self):
        for line in ["a.py\tmaybe\t\t%s" % TEST_WHY, "a.py\tscoped\t0\t ", "a.py\tscoped\tx\t%s" % TEST_WHY,
                     "a.py\tunscoped\t0\t%s" % TEST_WHY]:
            with self.assertRaises(g.GuardError, msg=line):
                g.parse_manifest(TEST_HEADER + line + "\n")

    def test_duplicate_file(self):
        row = "a.py\tscoped\t0\t%s\n" % TEST_WHY
        with self.assertRaises(g.GuardError):
            g.parse_manifest(TEST_HEADER + row + row)

    def test_parsed_values(self):
        m = g.parse_manifest(TEST_HEADER + "a.py\tscoped\t0,1\t%s\nb.py\tunscoped\t\t%s\n" % (TEST_WHY, TEST_WHY))
        self.assertEqual(m["a.py"], ("scoped", {0, 1}))
        self.assertEqual(m["b.py"], ("unscoped", set()))


class Scope(unittest.TestCase):
    def tree(self, files, manifest):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        for name, text in files.items():
            p = os.path.join(d.name, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh:
                fh.write(text)
        return g.run(d.name, TEST_HEADER + manifest)

    def test_clean_tree(self):
        problems, scoped, unscoped = self.tree({"a.py": "LIMIT = 4\n", "b/c.py": "x = 9\n"},
                                               "a.py\tscoped\t\t%s\nb/c.py\tunscoped\t\t%s\n" % (TEST_WHY, TEST_WHY))
        self.assertEqual((problems, scoped, unscoped), ([], 1, 1))

    def test_unlisted_and_missing_files_are_reported(self):
        problems, _, _ = self.tree({"a.py": "LIMIT = 4\n", "new.py": "LIMIT = 4\n"},
                                   "a.py\tscoped\t\t%s\ngone.py\tscoped\t\t%s\n" % (TEST_WHY, TEST_WHY))
        self.assertIn("new.py: python file not listed in the scope manifest", problems)
        self.assertIn("gone.py: listed in the scope manifest but not found", problems)

    def test_bare_literal_in_a_scoped_file_is_reported_with_its_line(self):
        problems, _, _ = self.tree({"a.py": "def f():\n    return 9\n"}, "a.py\tscoped\t\t%s\n" % TEST_WHY)
        self.assertEqual(problems, ["a.py:2: bare numeric literal 9"])

    def test_unscoped_file_is_not_scanned_but_counted(self):
        problems, scoped, unscoped = self.tree({"a.py": "def f():\n    return 9\n"},
                                               "a.py\tunscoped\t\t%s\n" % TEST_WHY)
        self.assertEqual((problems, scoped, unscoped), ([], 0, 1))

    def test_test_file_rule_depends_on_the_file_name(self):
        problems, _, _ = self.tree({"test_a.py": "TEST_X = 3\n", "a.py": "TEST_X = 3\n"},
                                   "a.py\tscoped\t\t%s\ntest_a.py\tscoped\t\t%s\n" % (TEST_WHY, TEST_WHY))
        self.assertEqual(problems, ["a.py:1: TEST_ constant outside a test_*.py file"])

    def test_pycache_is_ignored(self):
        problems, _, _ = self.tree({"a.py": "LIMIT = 4\n", "__pycache__/a.py": "x = 9\n"},
                                   "a.py\tscoped\t\t%s\n" % TEST_WHY)
        self.assertEqual(problems, [])

    def test_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "a.py"), "w") as fh:
                fh.write("def f():\n    return 9\n")
            man = os.path.join(d, "m.tsv")
            with open(man, "w") as fh:
                fh.write(TEST_HEADER + "a.py\tscoped\t\t%s\n" % TEST_WHY)
            self.assertEqual(g.main(["x", d, man]), g.EXIT_FINDINGS)
            self.assertEqual(g.main(["x", d, os.path.join(d, "nope.tsv")]), g.EXIT_INPUT)
            self.assertEqual(g.main(["x"]), g.EXIT_INPUT)


class Roots(unittest.TestCase):
    def make(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        for name in ["in/a.py", "out/b.py"]:
            p = os.path.join(d.name, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh:
                fh.write("def f():\n    return 9\n")
        return d.name

    def test_scan_roots_limit_the_discovered_files(self):
        root = self.make()
        problems, scoped, _ = g.run(root, TEST_HEADER + "in/a.py\tunscoped\t\t%s\n" % TEST_WHY, ("in",))
        self.assertEqual((problems, scoped), ([], 0))
        problems, _, _ = g.run(root, TEST_HEADER + "in/a.py\tunscoped\t\t%s\n" % TEST_WHY)
        self.assertEqual(problems, ["out/b.py: python file not listed in the scope manifest"])

    def test_manifest_entry_outside_the_roots_is_refused(self):
        root = self.make()
        with self.assertRaises(g.GuardError):
            g.run(root, TEST_HEADER + "out/b.py\tunscoped\t\t%s\n" % TEST_WHY, ("in",))

    def test_prefix_is_a_directory_not_a_string_prefix(self):
        self.assertTrue(g.within("in/a.py", ("in",)))
        self.assertFalse(g.within("inner/a.py", ("in",)))

    def test_generate_adds_only_missing_files_as_unscoped(self):
        root = self.make()
        rows = g.generate(root, TEST_HEADER + "in/a.py\tscoped\t\t%s\n" % TEST_WHY)
        self.assertEqual(rows, ["\t".join(g.MANIFEST_COLUMNS), "out/b.py\tunscoped\t\t" + g.GENERATED_REASON])

    def test_generated_manifest_makes_the_tree_pass(self):
        root = self.make()
        problems, scoped, unscoped = g.run(root, "\n".join(g.generate(root, "")) + "\n")
        self.assertEqual((problems, scoped, unscoped), ([], 0, 2))


class CommittedScope(unittest.TestCase):
    def test_the_repository_scope_manifest_holds(self):
        with open(TEST_MANIFEST, encoding="utf-8") as fh:
            problems, scoped, unscoped = g.run(TEST_ENGINE_ROOT, fh.read())
        self.assertEqual(problems, [], "\n".join(problems))
        self.assertGreater(scoped, 0)


if __name__ == "__main__":
    unittest.main()
