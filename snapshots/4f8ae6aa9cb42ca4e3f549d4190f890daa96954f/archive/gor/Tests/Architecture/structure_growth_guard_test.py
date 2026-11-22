#!/usr/bin/env python3
"""Exercise the arch-198y guard against committed temporary Git trees."""
from pathlib import Path
import subprocess
import sys
import tempfile

GUARD = Path(__file__).resolve().parents[2] / 'tools/structure_growth_guard.py'
SOURCE = 'archive/gor/Sources/gor/'
BASELINE = 'archive/gor/architecture/arch-baseline.tsv'
checks = 0
with tempfile.TemporaryDirectory() as directory:
    repo = Path(directory)
    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.PIPE).decode().strip()
    def write(path, text):
        target = repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    def commit(message):
        git('add', '.')
        git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', message)
        return git('rev-parse', 'HEAD')
    def expect(name, base, head, ok, marker=''):
        global checks
        result = subprocess.run([sys.executable, str(GUARD), '--repo', str(repo), '--base', base, '--head', head], capture_output=True, text=True)
        assert (result.returncode == 0) == ok, (name, result.stdout, result.stderr)
        assert marker in result.stdout, (name, result.stdout)
        print('PASS ' + name)
        checks += 1
    git('init', '-q')
    git('config', 'user.name', 'Structure Test')
    git('config', 'user.email', 'structure@test.invalid')
    write(SOURCE + 'main.swift', '// main\n')
    write(SOURCE + 'Existing.swift', '// inherited debt\n')
    write(BASELINE, 'path\trule\tcount\nExisting.swift\tedge\t2\n')
    base = commit('fixture baseline')
    expect('inherited root debt is not retro-failed', base, base, True)
    write(SOURCE + 'Existing.swift', '// changed in place\n')
    changed = commit('ordinary product edit')
    expect('in-place product edit accepted', base, changed, True)
    write(SOURCE + 'New.swift', '// forbidden root\n')
    root = commit('arch-198y does not exempt root growth')
    expect('new root and count growth rejected even with arch id', changed, root, False, 'new root Swift file')
    (repo / (SOURCE + 'New.swift')).unlink()
    removed = commit('remove root addition')
    expect('intermediate violation still rejected after removal', changed, removed, False)
    git('reset', '--hard', changed)
    write(SOURCE + 'GorUI/New.swift', '// count growth\n')
    nested = commit('add nested source')
    expect('nested source count growth rejected', changed, nested, False, 'Swift file count grew')
    git('reset', '--hard', changed)
    (repo / (SOURCE + 'GorUI')).mkdir(exist_ok=True)
    git('mv', SOURCE + 'Existing.swift', SOURCE + 'GorUI/Existing.swift')
    moved = commit('station move')
    expect('pure station move accepted', changed, moved, True)
    git('reset', '--hard', changed)
    write(BASELINE, 'path\trule\tcount\nExisting.swift\tedge\t3\n')
    debt = commit('increase debt')
    expect('baseline increase without id rejected', changed, debt, False, 'baseline count grew')
    git('reset', '--hard', changed)
    write(BASELINE, 'path\trule\tcount\nExisting.swift\tedge\t3\n')
    named = commit('arch-198y record exact debt')
    expect('baseline increase with arch id accepted', changed, named, True)
    write(BASELINE, 'path\trule\tcount\nExisting.swift\tedge\t1\n')
    decreased = commit('reduce baseline')
    expect('baseline decrease accepted without id', named, decreased, True)
    write(BASELINE, 'path\trule\tcount\nExisting.swift\tedge\t1\nOther.swift\tedge\t1\n')
    newrow = commit('new debt row')
    expect('new positive baseline row rejected without id', decreased, newrow, False)
    write(BASELINE, 'path\trule\tcount\nExisting.swift\tedge\tbroken\n')
    malformed = commit('malformed baseline')
    expect('malformed counts fail closed', newrow, malformed, False, 'invalid range or unreadable inventory')
    expect('invalid reference fails closed', 'missing-ref', changed, False)
    expect('reverse range fails closed', changed, base, False)
print('STRUCTURE_GROWTH_TEST PASS checks=%d' % checks)
