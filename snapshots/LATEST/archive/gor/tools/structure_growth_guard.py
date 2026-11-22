#!/usr/bin/env python3
"""arch-198y: check each outgoing commit for source and debt growth on Linux."""
import argparse
import csv
import io
from pathlib import Path
import re
import subprocess
import sys

SOURCE = 'archive/gor/Sources/gor/'
BASELINE = 'archive/gor/architecture/arch-baseline.tsv'
ARCH_ID = re.compile(r'\barch-[0-9]{3}[a-z]+\b', re.IGNORECASE)


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.PIPE)


def snapshot(repo, revision):
    paths = git(repo, 'ls-tree', '-r', '-z', '--name-only', revision, '--', SOURCE).decode().split('\0')
    swift = {p for p in paths if p.endswith('.swift')}
    listed = git(repo, 'ls-tree', '--name-only', revision, '--', BASELINE).decode().strip()
    debt = {}
    if listed:
        text = git(repo, 'show', revision + ':' + BASELINE).decode()
        reader = csv.DictReader(io.StringIO(text), delimiter='\t')
        if not {'path', 'rule', 'count'}.issubset(reader.fieldnames or []):
            raise ValueError('invalid architecture baseline columns')
        for row in reader:
            count = int(row['count'])
            if count < 0:
                raise ValueError('negative architecture baseline count')
            key = (row['path'], row['rule'])
            if key in debt:
                raise ValueError('duplicate architecture baseline key')
            debt[key] = count
    return swift, debt


def violations(before, after, message):
    old_files, old_debt = before
    new_files, new_debt = after
    errors = []
    for path in sorted(new_files - old_files):
        relative = path[len(SOURCE):]
        if '/' not in relative and relative not in {'main.swift', 'AppDelegate.swift'}:
            errors.append('new root Swift file: ' + path)
    if len(new_files) > len(old_files):
        errors.append('Swift file count grew: %d -> %d' % (len(old_files), len(new_files)))
    if not ARCH_ID.search(message):
        for key, count in sorted(new_debt.items()):
            previous = old_debt.get(key, 0)
            if count > previous:
                errors.append('baseline count grew without arch id: %s %s %d -> %d' % (*key, previous, count))
    return errors


def check(repo, base, head):
    base = git(repo, 'rev-parse', '--verify', base + '^{commit}').decode().strip()
    head = git(repo, 'rev-parse', '--verify', head + '^{commit}').decode().strip()
    subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', base, head], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    revisions = git(repo, 'rev-list', '--reverse', base + '..' + head).decode().splitlines()
    errors = []
    cache = {}
    def state(ref):
        if ref not in cache:
            cache[ref] = snapshot(repo, ref)
        return cache[ref]
    for revision in revisions:
        parent = git(repo, 'rev-parse', revision + '^1').decode().strip()
        message = git(repo, 'show', '-s', '--format=%B', revision).decode()
        errors.extend(revision[:12] + ' ' + e for e in violations(state(parent), state(revision), message))
    for error in errors:
        print('BLOCK ' + error)
    print('STRUCTURE_GROWTH %s commits=%d violations=%d' % ('FAIL' if errors else 'PASS', len(revisions), len(errors)))
    return bool(errors)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    try:
        return check(args.repo, args.base, args.head)
    except (subprocess.CalledProcessError, ValueError, UnicodeError, KeyError) as error:
        print('STRUCTURE_GROWTH FAIL: invalid range or unreadable inventory (%s)' % type(error).__name__)
        return 1


if __name__ == '__main__':
    sys.exit(main())
