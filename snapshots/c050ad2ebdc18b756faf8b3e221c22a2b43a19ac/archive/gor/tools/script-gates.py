"""Ubuntu syntax and existing runner secret tests; vendor/archive are exempt."""
from pathlib import Path
import importlib.util
import py_compile
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('architecture', root / 'tools/architecture.py')
arch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arch)
counts = {'shell': 0, 'python': 0}
with tempfile.TemporaryDirectory() as directory:
    for relative in arch.tracked(root):
        path = root / relative
        if arch.kind(relative) in {'vendor', 'generated'}:
            continue
        if path.suffix == '.sh':
            subprocess.run(['bash', '-n', str(path)], check=True)
            counts['shell'] += 1
            if shutil.which('shellcheck'):
                subprocess.run(['shellcheck', '--severity=error', str(path)], check=True)
        if path.suffix == '.py':
            py_compile.compile(str(path), cfile=str(Path(directory) / str(counts['python'])), doraise=True)
            counts['python'] += 1
subprocess.run(['python3', str(root / 'Tests/Runner/test_auto_install.py')], check=True)
subprocess.run(['python3', str(root / 'Tests/Runner/run.py')], check=True)
print('PASS script syntax: ' + str(counts) + '; shellcheck=' + ('ran' if shutil.which('shellcheck') else 'SKIP not installed'))
print('Credential-touching runner unit tests ran; no native runner/service proof claimed')
