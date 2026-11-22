#!/usr/bin/env python3
"""arch-198y: old checkout plus new overlay must not compile duplicate sources."""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('retire', Path(__file__).with_name('retire-overlay.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
manifest = json.loads(Path(__file__).with_name('retirements.json').read_text())
old = json.loads(Path(__file__).with_name('overlay-old-sources.json').read_text())
rows = [row for row in manifest['entries'] if any(path.startswith('Sources/gor/Gor') and digest == row['sha256'] for path, digest in row['replacements'].items())]
assert len(rows) >= 18
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    project = base / 'project'
    backups = project / '.gor-backups'
    external = base / 'retired'
    for row in rows:
        before = project / row['path']
        before.parent.mkdir(parents=True, exist_ok=True)
        before.write_text(old[row['path']])
    # Overlay behaves like the installed updater: omitted old paths still exist.
    for row in rows:
        for destination in row['replacements']:
            target = project / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / destination, target)
    sources = project / 'Sources/gor'
    assert len(list(sources.rglob('*.swift'))) == 2 * len(rows)
    inventory = project / 'Tests/Structure/retirements.json'
    inventory.parent.mkdir(parents=True)
    inventory.write_text(json.dumps({'schema': 1, 'entries': rows}))
    prior = backups / '261118-021100-pre-update'
    prior.mkdir(parents=True)
    (prior / 'changes.txt').write_text('')
    result = MODULE.retire(project, backups, external)
    assert len(list(sources.rglob('*.swift'))) == len(rows)
    for row in rows:
        assert not (project / row['path']).exists()
        for destination, digest in row['replacements'].items():
            assert hashlib.sha256((project / destination).read_bytes()).hexdigest() == digest
        assert (result / 'retired-inputs' / row['path']).read_text() == old[row['path']]
    assert MODULE.retire(project, backups, external) is None
    # Actual rollback manifest restores every original byte.
    for line in (result / 'changes.txt').read_text().splitlines():
        kind, path = line.split('\t')
        assert kind == 'deleted'
        shutil.copy2(result / path, project / path)
    assert all((project / row['path']).read_text() == old[row['path']] for row in rows)
print('PASS station dirty overlay: %d source copies -> %d unique destinations; exact originals backed up; idempotence and rollback PASS' % (2 * len(rows), len(rows)))
