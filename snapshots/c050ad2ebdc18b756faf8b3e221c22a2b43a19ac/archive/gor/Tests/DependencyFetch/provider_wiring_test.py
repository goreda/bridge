#!/usr/bin/env python3
"""Provider wiring and fail-closed input checks; actual compile is a separate gate."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parents[2]
helper = root / 'tools/build-with-gorav-provider.py'
spec = importlib.util.spec_from_file_location('provider', helper)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
lock = json.loads((m.PROVIDER / 'ffmpeg-provider-source-lock.json').read_text())
for name, key in [('ffmpeg-flags.txt', 'flags_sha256'), ('ffmpeg-894da5ca-refetch.tar.xz', 'tarball_sha256')]:
    assert hashlib.sha256((m.PROVIDER / name).read_bytes()).hexdigest() == lock[key]
script = (root / 'build.sh').read_text()
assert '"$project_root/tools/build-with-gorav-provider.py" --package-path "$project_root" --scratch-path "$build_dir" -c debug --product "$app_name"' in script
assert len(script.splitlines()) == 2773
assert 'No system/Homebrew FFmpeg' in (root / 'Packages/gorav/Sources/CFFmpeg/shim.h').read_text()
with tempfile.TemporaryDirectory() as temp:
    bad = Path(temp)
    (bad / 'ffmpeg-provider-source-lock.json').write_text(json.dumps(lock))
    (bad / 'ffmpeg-flags.txt').write_text('untrusted flags')
    (bad / 'ffmpeg-894da5ca-refetch.tar.xz').write_bytes(b'untrusted tar')
    with patch.object(m, 'PROVIDER', bad), patch.object(m.subprocess, 'check_output', side_effect=AssertionError('tools must not run')):
        try:
            m.provision()
            raise AssertionError('bad tar accepted')
        except RuntimeError as error:
            assert 'input mismatch' in str(error)
# Exact Swift invocation contract, no ambient include/lib fallback.
with tempfile.TemporaryDirectory() as temp:
    source = Path(temp)
    calls = []
    class Exit:
        returncode = 0
    with patch.object(m, 'provision', return_value=source), patch.object(m.sys, 'argv', ['helper', '--product', 'gor']), patch.object(m.subprocess, 'run', side_effect=lambda args: calls.append(args) or Exit()):
        assert m.main() == 0
    expected = ['swift', 'build', '--product', 'gor', '-Xcc', '-I' + str(source)]
    for name in m.LIBRARIES:
        expected += ['-Xlinker', '-L' + str(source / name)]
    assert calls == [expected]
print('PASS provider exact inputs, fail-closed mutation, normal updater wiring, 2773-line ceiling, private include + five link paths')
