#!/usr/bin/env python3
"""arch-198y: real base-source overlay, exact retirement and coherent rollback."""
from pathlib import Path
import importlib.util
import io
import json
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = 'bb3e0ea0b'
spec = importlib.util.spec_from_file_location('retirement', ROOT / 'Tests/Structure/retire-overlay.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    project = Path(directory) / 'project'
    project.mkdir()
    archive = subprocess.check_output(['git', '-C', str(ROOT.parents[1]), 'archive', BASE, 'archive/gor/Sources'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(Path(directory) / 'base', filter='data')
    shutil.copytree(Path(directory) / 'base/archive/gor/Sources', project / 'Sources')
    originals = {str(p.relative_to(project)): p.read_bytes() for p in (project / 'Sources').rglob('*.swift')}
    assert len(originals) == 66
    current = {str(p.relative_to(ROOT)): p.read_bytes() for p in (ROOT / 'Sources').rglob('*.swift')}
    # Use the exact updater overlay model: current source replaces existing paths,
    # absent paths remain until the shipped retirement helper accepts them.
    shutil.copytree(ROOT / 'Sources', project / 'Sources', dirs_exist_ok=True)
    shutil.copytree(ROOT / 'Tests/Structure', project / 'Tests/Structure')
    backups = project / '.gor-backups'
    prior = backups / '261118-021800-pre-update'
    prior.mkdir(parents=True)
    changes = []
    for path, body in current.items():
        if path in originals:
            if originals[path] != body:
                changes.append(('changed', path))
                saved = prior / path
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_bytes(originals[path])
        else:
            changes.append(('added', path))
    (prior / 'changes.txt').write_text(''.join(kind + '\t' + path + '\n' for kind, path in changes))
    result = module.retire(project, backups, Path(directory) / 'external')
    actual = {str(p.relative_to(project)): p.read_bytes() for p in (project / 'Sources').rglob('*.swift')}
    assert actual == current, 'overlay has duplicate/missing/changed sources'
    assert module.retire(project, backups, Path(directory) / 'external') is None
    # Replay the updater rollback manifest, including removal of added paths.
    for line in (result / 'changes.txt').read_text().splitlines():
        kind, path = line.split('\t')
        target = project / path
        if kind == 'added':
            target.unlink()
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(result / path, target)
    rolled_back = {str(p.relative_to(project)): p.read_bytes() for p in (project / 'Sources').rglob('*.swift')}
    assert rolled_back == originals, 'rollback did not restore exact complete old tree'
print('PASS full base overlay: 66 original Swift files -> 65 exact candidate paths, no duplicate copies; idempotence; rollback restores all 66 original blobs and removes new paths')
