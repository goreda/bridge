import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('selftest.sh')

class E1EntryPointContract(unittest.TestCase):
    def test_missing_root_fails_closed(self):
        with tempfile.TemporaryDirectory() as root:
            result = subprocess.run(['sh', str(SCRIPT)], env={**os.environ, 'GORAV_ENGINE_ROOT': root}, text=True, capture_output=True)
            self.assertEqual(result.returncode, 77)
            self.assertIn('UNRUN', result.stderr)
            self.assertNotIn('geometry prerequisite: PASS', result.stderr)

    def test_non_mac_never_reports_e1_pass(self):
        if os.uname().sysname == 'Darwin':
            self.skipTest('non-Mac refusal test')
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root/'Tests/presenter').mkdir(parents=True)
            (root/'Package.swift').write_text('// synthetic path preflight only\n')
            (root/'Tests/presenter/run-native.sh').write_text('exit 99\n')
            result = subprocess.run(['sh', str(SCRIPT)], env={**os.environ, 'GORAV_ENGINE_ROOT': str(root)}, text=True, capture_output=True)
            self.assertEqual(result.returncode, 77)
            self.assertIn('requires macOS', result.stderr)
            self.assertNotIn('PASS', result.stderr)

if __name__ == '__main__':
    unittest.main()
