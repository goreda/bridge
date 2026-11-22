#!/usr/bin/env python3
"""Verify the exact PreviewGuard fold plus real dirty-overlay rollback."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = '6f57576c2c89f87d66aad5dcfbefd75e1aa8e887'
def old(path):
    # Exact original sources already travel with the retirement characterization.
    # A CI mirror does not own the product repository's commit history.
    data = json.loads((ROOT / 'Tests/Structure/overlay-old-sources.json').read_text())
    return data[path].encode()
host_path = 'Sources/gor/Platform/QuitChildKiller.swift'
host = (ROOT / host_path).read_bytes()
guard = old('Sources/gor/PreviewGuard.swift')
fold = old('Sources/gor/QuitChildKiller.swift') + b'\n// BEGIN station-move PreviewGuard.swift\n' + guard + b'// END station-move PreviewGuard.swift\n'
# The fold fixture is the original pre-P01 characterization and stays pinned by
# retirements.json. P01-P04 edited the folded helper afterwards, so the live
# helper is the fold plus exactly these expected transforms, each applied once.
# Labels follow the commit history: P01 ipc args and path sentinel, P02 drain,
# P03 ESRCH-only gone check, P04 monotonic clock (P03 and P04 share one hunk).
TRANSFORMS = (
    ('P02 drain read handling (EINTR/EAGAIN/EWOULDBLOCK)',
     b'            if n <= 0 { source.cancel() }\n',
     b'            if n == 0 || (n < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) { source.cancel() }\n'),
    ('P01 ipc args inserted before option terminator',
     b'        process.arguments = (process.arguments ?? []) + ["--input-ipc-client=fd://0", "--no-input-terminal"]\n',
     b'        var args = process.arguments ?? []\n'
     b'        let boundary = args.firstIndex(of: "--") ?? args.count\n'
     b'        args.insert(contentsOf: ["--input-ipc-client=fd://0", "--no-input-terminal"], at: boundary)\n'
     b'        process.arguments = args\n'),
    ('P01 option terminator before path',
     b'            "--input-ipc-server=\\(socketPath)", path\n',
     b'            "--input-ipc-server=\\(socketPath)", "--", path\n'),
    ('P03+P04 waitGone: ESRCH-only gone check and monotonic clock (one hunk)',
     b'        let deadline = Date().addingTimeInterval(seconds)\n'
     b'        while Date() < deadline {\n'
     b'            if kill(pid, 0) != 0 { return true }\n'
     b'            usleep(10_000)\n'
     b'        }\n'
     b'        return kill(pid, 0) != 0\n',
     b'        let deadline = ProcessInfo.processInfo.systemUptime + seconds\n'
     b'        while ProcessInfo.processInfo.systemUptime < deadline {\n'
     b'            if kill(pid, 0) != 0 && errno == ESRCH { return true }\n'
     b'            usleep(10_000)\n'
     b'        }\n'
     b'        return kill(pid, 0) != 0 && errno == ESRCH\n'),
)
def transformed(base, skip=None):
    out = base
    for name, before, after in TRANSFORMS:
        if name == skip:
            continue
        assert out.count(before) == 1, name
        out = out.replace(before, after)
    return out
assert host == transformed(fold)
# Mutants: dropping any one expected transform must no longer match the live helper.
for name, _, _ in TRANSFORMS:
    assert transformed(fold, skip=name) != host, name
assert hashlib.sha256(host).hexdigest() == 'ffbea2bab58dc393d3d0d74fad7752afef587c181c9f426013b4080b70fe607a'
assert len(host.splitlines()) < 800
assert not (ROOT / 'Sources/gor/PreviewGuard.swift').exists()
assert not (ROOT / 'Sources/gor/GorPlatformMac/PreviewGuard.swift').exists()
manifest = json.loads((ROOT / 'Tests/Structure/retirements.json').read_text())
rows = [r for r in manifest['entries'] if r['path'] in {'Sources/gor/PreviewGuard.swift', 'Sources/gor/QuitChildKiller.swift'}]
assert len(rows) == 2
spec = importlib.util.spec_from_file_location('retire', ROOT / 'Tests/Structure/retire-overlay.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    project = Path(directory) / 'project'
    for row in rows:
        p = project / row['path']
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(old(row['path']))
    target = project / host_path
    target.parent.mkdir(parents=True)
    target.write_bytes(host)
    inventory = project / 'Tests/Structure/retirements.json'
    inventory.parent.mkdir(parents=True)
    inventory.write_text(json.dumps({'schema': 1, 'entries': rows}))
    backups = project / '.gor-backups'
    prior = backups / '261118-021500-pre-update'
    prior.mkdir(parents=True)
    (prior / 'changes.txt').write_text('')
    result = module.retire(project, backups, Path(directory) / 'external')
    for row in rows:
        assert not (project / row['path']).exists()
        assert (result / 'retired-inputs' / row['path']).read_bytes() == old(row['path'])
        assert row['replacements'] == {host_path: hashlib.sha256(host).hexdigest()}
    assert target.read_bytes() == host
    assert module.retire(project, backups, Path(directory) / 'external') is None
print('PASS PreviewGuard exact fold: 744 lines with P01-P04 transforms, source count -1, both old overlay copies backed up and retired, repeated run no-op')
