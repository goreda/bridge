"""Mutate actual v2 manifest/gate inputs; no fabricated compiler isolation."""
import csv
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import os
import shutil

root = Path(__file__).resolve().parents[2]
if not shutil.which('swift'):
    os.environ['ARCH_SWIFT'] = str(root / 'Tests/Architecture/swift-fixture.py')
    print('SUPPLEMENTARY graph fixture replay; swift unavailable; compile NOT_RUN')
script = root / 'tools/architecture.py'
spec = importlib.util.spec_from_file_location('arch', script)
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    (p / 'Sources/gor/gor').mkdir(parents=True)
    (p / 'plan').mkdir()
    (p / 'Tests/MenuStructure').mkdir(parents=True)
    (p / 'Tests/MenuStructure/required-items.json').write_text('{"required":{},"orders":[],"removals":[]}\n')
    (p / 'Sources/gor/gor/ThreeD.swift').write_text('// BEGIN relocated ThreeDMenu.swift fixture\n// fixture menu, no required items in this isolated manifest test\n// END relocated ThreeDMenu.swift\n')
    (p / 'Package.swift').write_text('// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: "gor", targets:[.executableTarget(name:"gor")])\n')
    source = p / 'Sources/gor/App/main.swift'
    source.write_text('import Foundation\nprint("fixture")\n')
    (p / 'plan/QUEUE.md').write_text('## M6 | BLOCKED\n## M5 | BLOCKED\n')
    subprocess.run(['git', 'init', '-q', str(p)], check=True)
    def run(*args, ok=True):
        r = subprocess.run(['python3', str(script), '--root', str(p), *args], capture_output=True, text=True)
        assert (r.returncode == 0) == ok, r.stdout + r.stderr
        return r.stdout
    def approve(path):
        policy = p / 'architecture/policy.tsv'
        if not policy.exists():
            policy.parent.mkdir(exist_ok=True)
            policy.write_text('path\tresponsibility\tplanned target\tallowed-small reason\tbaseline id\tvendor class\n')
        with policy.open('a') as handle:
            handle.write(path + '\tfixture\tgor\t\tM6\t\n')
    for path in ['Tests/MenuStructure/required-items.json', 'Sources/gor/gor/ThreeD.swift', 'Package.swift', 'Sources/gor/App/main.swift', 'plan/QUEUE.md', 'architecture/manifest.tsv', 'architecture/arch-baseline.tsv', 'architecture/delivery.tsv', 'architecture/policy.tsv']:
        approve(path)
    def emit():
        run('--emit', '--report')
        run('--emit', '--report')
    run('--seed-baseline', '--emit')
    emit()
    run('--verify')
    source.write_text(source.read_text() + 'let extra = 1\n')
    assert 'stale manifest' in run('--verify', ok=False)
    assert 'REPORT ONLY' in run('--report')
    source.write_text('import Foundation\nlet ipcCommand = 1\n')
    emit()
    assert 'exceeds active baseline' in run('--verify', ok=False)
    source.write_text('import Foundation\nprint("fixture")\n')
    extra = p / 'Sources/gor/New.swift'
    extra.write_text('struct New {}\n')
    assert 'unmapped=' in run('--verify', ok=False)
    emit()
    assert 'unreviewed policy' in run('--verify', ok=False)
    approve('Sources/gor/New.swift')
    emit()
    assert 'small-file' not in run('--verify')
    extra.unlink()
    source.write_text('import Foundation\nprint("fixture")\n' + '// growth\n' * 800)
    emit()
    assert 'ceiling' not in run('--verify')
    source.write_text('import Foundation\nprint("fixture")\n')
    emit()
    source.write_text('import Foundation\nlet ipcCommand = 1\n')
    run('--seed-baseline', '--emit')
    emit()
    (p / 'plan/QUEUE.md').write_text('## M5 | DONE\n')
    assert 'active baseline' in run('--verify', ok=False)
    # The actual Package.swift dependency graph, not a supplied fake graph.
    (p / 'Sources/GorStereo').mkdir()
    (p / 'Sources/GorStereo/Value.swift').write_text('struct Value {}\n')
    (p / 'Sources/GorFit').mkdir()
    (p / 'Sources/GorFit/Value.swift').write_text('struct Fit {}\n')
    (p / 'Package.swift').write_text('// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name:"gor", targets:[.target(name:"GorStereo",dependencies:["GorFit"]),.target(name:"GorFit")])\n')
    assert 'forbidden dependency' in run('--report')
    targets, errors = a.graph(p)
    assert errors and targets['GorStereo'] == 'Sources/GorStereo'
print('PASS v2 actual gate: stale/unmapped/policy/mpv/closed debt/actual forbidden Package edge; retired file counts do not gate; report-mode rc0')

# D4: real capture transport failure and tracing scrub, dummy values only.
from unittest.mock import patch
import os
spec = importlib.util.spec_from_file_location('capture', root / 'gor-capture-channel.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
with patch.dict(os.environ, {'GIT_TRACE': 'dummy-secret', 'GIT_TRACE2_EVENT': 'dummy-secret', 'GIT_CURL_VERBOSE': '1', 'BASH_ENV': 'dummy-secret'}):
    channel = capture.Channel(root)
    assert all(key not in channel.env for key in ['GIT_TRACE', 'GIT_TRACE2_EVENT', 'GIT_CURL_VERBOSE', 'BASH_ENV'])
    failure = subprocess.CompletedProcess([], 1, b'', b'dummy-secret https://private.invalid')
    with patch.object(capture.subprocess, 'run', return_value=failure) as call:
        try:
            channel.git('fetch', 'origin')
            raise AssertionError('failure expected')
        except RuntimeError as error:
            assert 'dummy-secret' not in str(error) and 'private.invalid' not in str(error)
        assert 'dummy-secret' not in str(call.call_args.args)
print('PASS D4 capture: no dummy credential in argv/failure output; tracing environment scrubbed')

# Execute the sync credential script's real preamble, stopping before all Git,
# filesystem and network actions. Trace variables must be absent at first Git.
sync = (root / 'scripts/sync-now.sh').read_text()
preamble = sync[:sync.index('ROOT=')]
result = subprocess.run(['bash', '-c', preamble + '\nprintf "trace:%s curl:%s" "${GIT_TRACE:-absent}" "${GIT_CURL_VERBOSE:-absent}"'], env={**os.environ, 'GIT_TRACE': 'dummy-secret', 'GIT_CURL_VERBOSE': 'dummy-secret'}, text=True, capture_output=True)
assert result.returncode == 0
assert result.stdout == 'trace:absent curl:absent'
assert 'dummy-secret' not in result.stderr
assert 'CRED_FILE=' in sync and 'credential.helper=store --file $CRED_FILE' in sync
print('PASS D4 sync credential preamble: trace scrub before first Git; credential-file path only in argv')

for path in ['docs/new-product-tool.py', 'engine/NewRuntime.swift', 'docs/new.lua']:
    assert a.reviewed(path, [{'path': 'docs/*'}, {'path': 'engine/*'}]) is None
from unittest.mock import patch
with patch.object(a.subprocess, 'run', side_effect=PermissionError):
    targets, errors = a.graph(root)
    assert any('swift unavailable' in error for error in errors)
with patch.object(a, 'graph', side_effect=AssertionError('integrity must not evaluate package')):
    assert isinstance(a.integrity(root), list)
print('PASS missing/unexecutable Swift diagnostic, integrity graph independence, archive wildcard executable refusal')

with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    (p / 'probe.swift').write_text('import CFFmpeg\nimport GorAVCAtomics\nimport GorAVAudioClock\nimport GorAVDVRPU\n')
    violations = a.violations(p, [['probe.swift', 'swift', 'gor', 'gor', 'probe', '4', 'allowed-small: test']])
    assert all(violations['probe.swift', 'gorav-cmodule:' + name] == 1 for name in ['CFFmpeg', 'GorAVCAtomics', 'GorAVAudioClock', 'GorAVDVRPU'])
print('PASS R10 explicit CFFmpeg/engine Cmodule import bans')

# Exact owner-failure paths: Git100644 accepts non-executable0444/0664,
# while checksums and executable-bit changes must remain hard integrity errors.
import hashlib
with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    names = ['Resources/vendor/mega_relay/mega_relay.mjs', 'Resources/vendor/mpv/input.conf', 'Resources/vendor/wt_server/wt_server.mjs']
    declared = []
    for name in names:
        original = root / name
        target = p / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(original.read_bytes())
        target.chmod(0o444)
        declared.append([name, hashlib.sha256(original.read_bytes()).hexdigest(), '0o644'])
    a.write_tsv(p / a.DELIVERY, ['path', 'sha256', 'mode'], declared)
    assert not a.integrity(p), a.integrity(p)
    for name in names:
        (p / name).chmod(0o664)
    assert not a.integrity(p)
    (p / names[0]).chmod(0o755)
    assert any('executable-bit mismatch' in e for e in a.integrity(p))
    (p / names[0]).chmod(0o644)
    (p / names[1]).write_bytes(b'changed bytes')
    assert any('checksum mismatch' in e for e in a.integrity(p))
    (p / names[2]).unlink()
    assert any('file missing' in e for e in a.integrity(p))
print('PASS exact3 vendor paths:0444/0664 accepted as Git100644; executable-bit/content/missing-file corruption still rejected')

# J2: bulk directory pins close extensionless/JSON runtime admission.
with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    (p / 'archive').mkdir()
    (p / 'archive/old.txt').write_text('historical')
    bulk = {'path': 'archive/*', 'vendor class': 'generated'}
    policy = [bulk]
    bulk['bulk_file_count'], bulk['bulk_tree_sha256'] = a.bulk_measure(p, bulk, policy, ['archive/old.txt'])
    assert not a.bulk_errors(p, policy, ['archive/old.txt'])
    (p / 'archive/runtime.json').write_text('{"new":"runtime"}')
    assert a.bulk_errors(p, policy, ['archive/old.txt', 'archive/runtime.json'])
    (p / 'archive/Product.swift').write_text('struct Product {}')
    assert a.reviewed('archive/Product.swift', policy) is None
    nested = {'path': 'archive/deep/*', 'vendor class': 'generated'}
    assert a.reviewed('archive/deep/file.txt', [bulk, nested]) is nested
    assert a.reviewed('archive/old.txt', []) is None
print('PASS J2 runtime JSON changes bulk pin; archive product requires per-file review; emit alone never supplies policy; longest match')

with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    (p / 'ffmpeg-provider.lock').write_bytes((root / 'ffmpeg-provider.lock').read_bytes())
    assert not a.provider_errors(p)
    (p / 'ffmpeg-provider.lock').write_bytes((root / 'ffmpeg-provider.lock').read_bytes().replace(b'8.0.1', b'8.0.2'))
    assert any('blob mismatch' in e for e in a.provider_errors(p))
    (p / 'ffmpeg-provider.lock').write_bytes((root / 'ffmpeg-provider.lock').read_bytes())
    (p / 'Package.swift').write_text('.package(url: "https://github.com/goreda/gorav", revision: "deadbeef")')
    assert any('pin differs' in e for e in a.provider_errors(p))
print('PASS J1 exact upstream Git blob; changed provider value and mismatched dependency pin reject')

# Emit cannot supply a reviewed policy, including entirely empty initial state.
with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    (p / 'Sources/gor/gor').mkdir(parents=True)
    (p / 'Sources/gor/App/main.swift').write_text('print("test")')
    (p / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package=Package(name:"gor",targets:[.executableTarget(name:"gor")])')
    subprocess.run(['git', 'init', '-q', str(p)], check=True)
    env = {**os.environ, 'ARCH_SWIFT': str(root / 'Tests/Architecture/swift-fixture.py')}
    proc = subprocess.run(['python3', str(script), '--root', str(p), '--emit', '--report'], env=env, text=True, capture_output=True)
    assert proc.returncode == 0 and not (p / a.POLICY).exists()
    verify = subprocess.run(['python3', str(script), '--root', str(p), '--verify'], env=env, text=True, capture_output=True)
    assert verify.returncode and 'unreviewed policy' in verify.stdout
print('PASS J2 real emit-without-policy leaves policy absent; verify rejects')

# Explicit current pin state, plus real multiline matching/mismatching pins.
import contextlib
import io
with tempfile.TemporaryDirectory() as directory:
    p = Path(directory)
    (p / 'ffmpeg-provider.lock').write_bytes((root / 'ffmpeg-provider.lock').read_bytes())
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert not a.provider_errors(p)
    assert 'provider-pin: ABSENT' in output.getvalue() and 'M2b BLOCKED' in output.getvalue()
    source = __import__('re').search(r'gorav_lock_source: goreda/gorav@([0-9a-f]{40}):', (root / 'ffmpeg-provider.lock').read_text())[1]
    package = p / 'Package.swift'
    package.write_text('.package(\n url: "https://github.com/goreda/gorav",\n revision: "' + source + '"\n)')
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert not a.provider_errors(p)
    assert 'provider-pin: MATCH' in output.getvalue()
    package.write_text(package.read_text().replace(source, '0' * 40))
    assert any('pin differs' in e for e in a.provider_errors(p))
print('PASS provider-pin ABSENT explicitly blocked; declared multiline exact pin MATCH; mismatched pin rejected')

# Exercise the exact pre-install update gate against EVERY shipped entry, then
# corrupt one byte in an isolated copy. No hash subset or photon-only exception.
import hashlib
with (root / a.DELIVERY).open() as handle:
    delivery_rows = list(csv.DictReader(handle, delimiter='\t'))
assert delivery_rows and len({row['path'] for row in delivery_rows}) == len(delivery_rows)
for row in delivery_rows:
    path = root / row['path']
    assert path.is_file(), row['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], row['path']
    assert a.same_git_mode(path, row['mode']), row['path']
assert not a.integrity(root)
subprocess.run(['python3', str(script), '--root', str(root), '--integrity-only'], check=True)
with tempfile.TemporaryDirectory() as directory:
    staged = Path(directory)
    (staged / a.DELIVERY).parent.mkdir(parents=True)
    shutil.copy2(root / a.DELIVERY, staged / a.DELIVERY)
    for row in delivery_rows:
        dest = staged / row['path']; dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / row['path'], dest)
    gate = ['python3', str(script), '--root', str(staged), '--integrity-only']
    subprocess.run(gate, check=True)
    changed = staged / 'Resources/vendor/mpv/scripts/photon.lua'
    changed.write_bytes(changed.read_bytes() + b'\n-- isolated checksum fault\n')
    rejected = subprocess.run(gate, capture_output=True, text=True)
    assert rejected.returncode != 0 and 'delivery checksum mismatch: Resources/vendor/mpv/scripts/photon.lua' in rejected.stdout
print(f'PASS all-delivery hash/executable verification: {len(delivery_rows)} entries; real update gate accepts exact source + isolated installed tree, rejects photon one-byte drift')

# Gate wiring: a committed edit to any listed file without its emitted delivery row, or an added file without a row, fails here.
_tree = subprocess.run(['python3', str(root / 'Tests/Architecture/manifest_tree_test.py'), '--head-only'], capture_output=True, text=True)
print(_tree.stdout.strip().splitlines()[-1] if _tree.stdout.strip() else _tree.stderr[-300:])
if _tree.returncode != 0:
    print(_tree.stdout[-1500:])
    raise SystemExit('manifest_tree_test failed: run python3 tools/architecture.py --emit and commit the rows')
