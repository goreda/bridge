#!/usr/bin/env python3
"""Release dependency snapshot: hashes, no-history scope and fresh offline SwiftPM graph."""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
local = root / 'Packages/gorav'
lock = json.loads((local / 'source-lock.json').read_text())
assert re.fullmatch(r'[0-9a-f]{40}', lock['revision']), 'exact source revision required'
actual = {p.relative_to(local).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in local.rglob('*') if p.is_file() and p.name != 'source-lock.json'}
assert actual == lock['files'], 'dependency snapshot drift or unlisted file'
assert all(p in {'Package.swift', 'tools/p27-frame-tap-test.py'} or p.startswith(('Sources/', 'Tests/', 'Shaders/')) for p in actual)
assert not any(p.is_symlink() for p in local.rglob('*'))
assert '.package(name: "gorav", path: "Packages/gorav")' in (root / 'Package.swift').read_text()
assert 'https://github.com/goreda/gorav.git' not in (root / 'Package.swift').read_text()
swift = shutil.which(os.environ.get('SWIFT', 'swift'))
assert swift, 'swift required; offline dependency graph NOT_RUN'
with tempfile.TemporaryDirectory(prefix='gor-offline-dependency-') as tmp:
    tmp = Path(tmp)
    # A literal fresh update overlay: no .git, .build, Package.resolved or shared caches.
    project = tmp / 'project'
    project.mkdir()
    shutil.copy2(root / 'Package.swift', project / 'Package.swift')
    for directory in ['Sources', 'Tests', 'Packages']:
        shutil.copytree(root / directory, project / directory,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.build', '.git'))
    no_git = tmp / 'bin'
    no_git.mkdir()
    calls = tmp / 'git-calls'
    git = no_git / 'git'
    git.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$GOR_TEST_GIT_CALLS"
exit 99
''')
    git.chmod(0o755)
    env = dict(os.environ, PATH=str(no_git) + ':' + os.environ['PATH'],
               GOR_TEST_GIT_CALLS=str(calls), GIT_TERMINAL_PROMPT='0')
    args = [swift, 'package', '--package-path', str(project), '--scratch-path', str(tmp / 'build'),
            '--cache-path', str(tmp / 'cache'), '--config-path', str(tmp / 'config'),
            '--security-path', str(tmp / 'security'), '--disable-dependency-cache']
    for attempt in range(3):
        if attempt == 2:
            (project / 'Package.resolved').write_text(json.dumps({'version': 2, 'pins': [
                {'identity': 'gorav', 'kind': 'remoteSourceControl',
                 'location': lock['repository'], 'state': {'revision': lock['revision']}}
            ]}))
        graph = subprocess.run(args + ['show-dependencies', '--format', 'json'],
                               env=env, capture_output=True, text=True, timeout=60)
        assert graph.returncode == 0, graph.stderr
        data = json.loads(graph.stdout)
        dependencies = data['dependencies']
        assert len(dependencies) == 1, dependencies
        dependency = dependencies[0]
        assert dependency['identity'] == 'gorav', dependency
        assert Path(dependency['path']).resolve() == (project / 'Packages/gorav').resolve(), dependency
        assert not dependency['dependencies'], dependency
        probes = calls.read_text().splitlines() if calls.exists() else []
        assert all(' describe --exact-match --tags' in p or ' rev-parse --verify HEAD' in p for p in probes), probes
        # SwiftPM may ask local Git for version metadata. The failing shim forbids
        # any clone/fetch and the graph must still succeed with empty caches.

        assert not (tmp / 'build/repositories').exists() or not list((tmp / 'build/repositories').iterdir())
        print('PASS fresh/repeat/stale-lock offline graph', attempt, 'local gorav, Git unavailable, no network operations or remote repositories')
    if (project / 'Package.resolved').exists():
        assert not json.loads((project / 'Package.resolved').read_text()).get('pins'), 'obsolete remote pin retained'
print('PASS exact hash-locked source snapshot (native acceptance separate):', len(actual), 'files; source pin', lock['revision'])
