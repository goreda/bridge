#!/usr/bin/env python3
"""Compile real policy/lifecycle mutants; a compile error never counts as RED."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
policy = root / 'Sources/GorAVPlaybackCore/MenuCapabilityPolicy.swift'
plane = root / 'Sources/GorAVPlaybackCore/PlayerControlPlane.swift'
tests = root / 'Tests/MenuCapabilityParity/MenuCapabilityPolicyTests.swift'
compiler = os.environ.get('SWIFTC', 'swiftc')
mutants = [
    ('pause-from-paused', 'plane', 'case (.playing, .pause):', 'case (.paused, .pause):'),
    ('resume-from-playing', 'plane', 'case (.paused, .resume):', 'case (.playing, .resume):'),
    ('seek-while-seeking', 'plane', 'case (.playing, .beginSeek), (.paused, .beginSeek):', 'case (.playing, .beginSeek), (.paused, .beginSeek), (.seeking, .beginSeek):'),
    ('seek-missing-paused', 'plane', 'case (.playing, .beginSeek), (.paused, .beginSeek):', 'case (.playing, .beginSeek):'),
    ('fence-ignored', 'policy', 'if s.fenced || s.tornDown', 'if s.tornDown'),
    ('teardown-ignored', 'policy', 'if s.fenced || s.tornDown', 'if s.fenced'),
    ('handoff-ignored', 'policy', 'if s.handoffPending {', 'if false {'),
    ('dependency-ignored', 'policy', 'guard s.available.contains(action) else', 'guard true else'),
    ('prepared-seek-allowed', 'policy', 'if s.preparedTimeline {', 'if false {'),
]
with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    for name, target, before, after in mutants:
        sources = {'policy': policy.read_text(), 'plane': plane.read_text()}
        assert sources[target].count(before) == 1, name + ': mutation anchor changed'
        sources[target] = sources[target].replace(before, after)
        for key, text in sources.items():
            (work / (key + '.swift')).write_text(text)
        built = subprocess.run([compiler, '-parse-as-library', str(work/'plane.swift'),
                                str(work/'policy.swift'), str(tests), '-o', str(work/'test')],
                               capture_output=True, text=True)
        if built.returncode:
            raise SystemExit(name + ': COMPILE_ERROR, not a killed mutant\n' + built.stderr)
        ran = subprocess.run([str(work/'test')], capture_output=True, text=True)
        if ran.returncode == 0:
            raise SystemExit(name + ': SURVIVED')
        if 'Precondition failed:' not in ran.stderr:
            raise SystemExit(name + ': non-assertion failure, not accepted as RED')
        print('RED ' + name + ': compiled, assertion rejected mutant')
print('PASS mutation set: 9/9 killed at runtime')
