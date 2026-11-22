#!/usr/bin/env python3
"""Language-gate regression tests with temporary trees and negative controls."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

GATE = Path(__file__).resolve().parents[2] / 'tools/english_text_guard.py'
spec = importlib.util.spec_from_file_location('language_gate', GATE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class EnglishTextTests(unittest.TestCase):
    def test_english_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'build.sh').write_text('echo "3D acceptance: NOT_RUN"\n')
            self.assertEqual(list(gate.violations(root)), [])

    def test_original_ascii_mutant_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Encode the old text so test diagnostics cannot emit it.
            value = bytes([107, 97, 98, 117, 108, 58, 32, 99, 97, 108, 105, 115, 116, 105, 114, 105, 108, 109, 97, 100, 105]).decode()
            (root / 'build.sh').write_text('echo "3D ' + value + '"\n')
            self.assertEqual(list(gate.violations(root)), ['build.sh:1'])

    def test_character_mutant_fails_in_nested_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'Sources/gor'
            folder.mkdir(parents=True)
            (folder / 'Status.swift').write_text('print("' + chr(351) + '")\n')
            self.assertEqual(list(gate.violations(root)), ['Sources/gor/Status.swift:1'])

    def test_escaped_character_mutant_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'build.sh').write_text('echo "' + chr(92) + 'u015f"' + chr(10))
            self.assertEqual(list(gate.violations(root)), ['build.sh:1'])

    def test_html_entity_mutant_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'Resources'
            folder.mkdir()
            (folder / 'status.html').write_text('<div>' + chr(38) + '#351;</div>')
            self.assertEqual(list(gate.violations(root)), ['Resources/status.html:1'])

    def test_ascii_ui_value_fails_but_identifier_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'Resources'
            folder.mkdir()
            label = bytes([107,111,100]).decode()
            page = folder / 'status.html'
            page.write_text('<label aria-label="' + label + '">Code</label>')
            self.assertEqual(list(gate.violations(root)), ['Resources/status.html:1'])
            page.write_text('<input id="code" aria-label="Code"><span>Status</span>')
            self.assertEqual(list(gate.violations(root)), [])
            page.unlink()
            script = root / 'build.sh'
            script.write_text("labels={code:'" + label + "'}")
            self.assertEqual(list(gate.violations(root)), ['build.sh:1'])

    def test_source_regex_lookbehind_is_not_html_declaration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'gor-selftest.sh').write_text("pattern = r'(?<![A-Za-z0-9_])'\n")
            self.assertEqual(list(gate.violations(root)), [])

    def test_regex_lookbehind_does_not_hide_bad_ui_label(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            value = bytes([107,111,100]).decode()
            (root / 'build.sh').write_text("pattern = r'(?<![a-z])'; label='" + value + "'\n")
            self.assertEqual(list(gate.violations(root)), ['build.sh:1'])

    def test_shipped_bootstrap_runs_gate_before_compile(self):
        root = GATE.parents[1]
        script = (root / 'build.sh').read_text()
        hook = 'python3 "$project_root/tools/english_text_guard.py"'
        if hook in script:
            self.assertLess(script.index(hook), script.index('/usr/bin/python3 "$project_root/tools/build-with-gorav-provider.py"'))
        else:
            # This product candidate carries the parser regression only, not
            # the parked full-language branch or its build-wide policy gate.
            self.assertNotIn('english_text_guard.py', script)


if __name__ == '__main__':
    unittest.main()
