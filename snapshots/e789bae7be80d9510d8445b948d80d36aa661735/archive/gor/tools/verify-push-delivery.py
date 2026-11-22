#!/usr/bin/env python3
"""Fail closed on the exact outgoing gor commit, including non-HEAD refs."""
import hashlib, io, csv, subprocess, sys

def check(ref):
    def git(*args):
        return subprocess.check_output(['git', *args])
    # Anchor every pathspec at the repo ROOT: relative pathspecs resolve
    # against the CWD, and from archive/gor 'archive/gor/' matched NOTHING,
    # which made the build.sh probe below a silent no-op PASS (native111:
    # conflict markers shipped past this script from a subdirectory).
    root = git('rev-parse', '--show-toplevel').decode().strip()
    prefix = 'archive/gor/'
    files = git('-C', root, 'ls-tree', '-r', '--name-only', ref, prefix).decode().splitlines()
    if prefix + 'build.sh' not in files:
        return
    manifest = git('show', ref + ':' + prefix + 'architecture/delivery.tsv').decode()
    # Fail CLOSED with a named error on unresolved merge conflict markers:
    # as TSV rows they used to die later as an opaque git exit 128.
    for lineno, line in enumerate(manifest.splitlines(), 1):
        if line.startswith(('<<<<<<<', '=======', '>>>>>>>')):
            raise RuntimeError('conflict marker in delivery.tsv line %d: %s' % (lineno, line[:40]))
    rows = list(csv.DictReader(io.StringIO(manifest), delimiter='\t'))
    listed = set()
    for row in rows:
        name = prefix + row['path']; listed.add(name)
        blob = git('show', ref + ':' + name)
        if hashlib.sha256(blob).hexdigest() != row['sha256']:
            raise RuntimeError('stale delivery checksum: ' + name)
        mode = git('-C', root, 'ls-tree', ref, name).decode().split()[0]
        if bool(int(mode, 8) & 0o111) != bool(int(row['mode'], 8) & 0o111):
            raise RuntimeError('stale delivery mode: ' + name)
    for name in files:
        rel = name[len(prefix):]
        if '__pycache__' in rel or rel.endswith('.pyc'): continue
        if (rel.startswith(('Sources/', 'tools/', 'Tests/', 'Resources/')) or rel in ('build.sh', 'Package.swift')) and name not in listed:
            raise RuntimeError('missing delivery row: ' + name)
    subprocess.run([sys.executable, __file__.replace('verify-push-delivery.py', 'structure-freeze.py'), '--root', git('rev-parse', '--show-toplevel').decode().strip() + '/archive/gor', '--ref', ref], check=True)
    print('pre-push delivery PASS', ref, len(rows), 'rows')

if __name__ == '__main__':
    try:
        refs = sys.argv[1:]
        if not refs:
            refs = [line.split()[1] for line in sys.stdin if len(line.split()) == 4 and set(line.split()[1]) != {'0'}]
        for ref in set(refs): check(ref)
    except Exception as error:
        print('PRE-PUSH BLOCKED:', error, file=sys.stderr)
        sys.exit(1)
