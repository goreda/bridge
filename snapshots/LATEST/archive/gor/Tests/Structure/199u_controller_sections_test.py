#!/usr/bin/env python3
"""arch-199u Controller station gate: moved units sit under `// MARK: - <OriginalFileName>`
in their station file with the pinned section bytes; the old flat paths are gone.
Declaration-set and token-multiset equality against the pre-move base are proven by
the candidate's recorded gate run; this test is the standing per-section witness."""
import importlib.util as _iu
import hashlib
import json
from pathlib import Path

_r = next(p for p in Path(__file__).resolve().parents if (p / 'Tests/Structure/section_source.py').exists())
_s = _iu.spec_from_file_location('section_source', _r / 'Tests/Structure/section_source.py')
ss = _iu.module_from_spec(_s)
_s.loader.exec_module(ss)

pins = json.loads((_r / 'Tests/Structure/199u-controller-map.json').read_text())
assert pins['station'] == 'Controller'

OLD = ['Sources/gor/gor/InputController.swift', 'Sources/gor/gor/DragDropHandler.swift']
for rel in OLD:
    assert not (_r / rel).exists(), rel + ': pre-move path still present'

for name, pin in sorted(pins['sections'].items()):
    body = ss.section_text(_r, name)
    assert hashlib.sha256(body.encode()).hexdigest() == pin['sha256'], name + ': section bytes changed'
    assert body.count('\n') == pin['lines'], name + ': section line count changed'
host = {name: ss.section_file(_r, name).relative_to(_r).as_posix() for name in pins['sections']}
for name, pin in pins['sections'].items():
    assert host[name] == pin['host'], (name, host[name], pin['host'])
print('PASS 199u Controller: %d units byte-exact in Sources/gor/Controller (MARK sections); old paths absent' % len(pins['sections']))
