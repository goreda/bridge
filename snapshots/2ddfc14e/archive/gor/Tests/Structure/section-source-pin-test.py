#!/usr/bin/env python3
"""section_source.pinned_bytes unit-branch hardening: the declared host of a
`host#Unit.swift` pin must be a safe-relative, regular, non-symlink file and must
BE the resolved carrier of the unit's MARK section. Each mutant must go RED."""
import importlib.util, pathlib, shutil, tempfile
R = pathlib.Path(__file__).resolve().parents[2]
_s = importlib.util.spec_from_file_location('section_source', R / 'Tests/Structure/section_source.py')
ss = importlib.util.module_from_spec(_s); _s.loader.exec_module(ss)

HOST = 'Sources/gor/Station/Host.swift'
UNIT_PIN = HOST + '#Unit.swift'


def tree():
    d = pathlib.Path(tempfile.mkdtemp(prefix='sec-pin-'))
    src = d / 'Sources/gor/Station'
    src.mkdir(parents=True)
    (src / 'Host.swift').write_text('import AppKit\n\n// MARK: - Unit.swift\n\nlet unitBytes = 1\n')
    return d


def expect_red(desc, root, pin):
    try:
        ss.pinned_bytes(root, pin)
    except (KeyError, AssertionError):
        return
    raise SystemExit('MUTANT NOT RED: ' + desc)


# positive control: the declared host carries the MARK and the bytes come back
d = tree()
got = ss.pinned_bytes(d, UNIT_PIN)
assert got == b'\nlet unitBytes = 1\n', got
shutil.rmtree(d)

# wronghost: the MARK lives in Host.swift but the pin declares another existing file
d = tree()
(d / 'Sources/gor/Station/WrongHost.swift').write_text('import AppKit\nlet decoy = 0\n')
expect_red('wronghost', d, 'Sources/gor/Station/WrongHost.swift#Unit.swift')
shutil.rmtree(d)

# missinghost: the declared host does not exist at all
d = tree()
expect_red('missinghost', d, 'Sources/gor/Station/Gone.swift#Unit.swift')
shutil.rmtree(d)

# symlink: the declared host is a symlink onto the real carrier
d = tree()
(d / 'Sources/gor/Station/Link.swift').symlink_to('Host.swift')
expect_red('symlink declared host', d, 'Sources/gor/Station/Link.swift#Unit.swift')
# symlink carrier: the MARK is only reachable through a symlinked file
d2 = tree()
(d2 / 'Sources/gor/Station/Host.swift').unlink()
real = d2 / 'Sources/gor/real.txt'
real.write_text('import AppKit\n\n// MARK: - Unit.swift\n\nlet unitBytes = 1\n')
(d2 / 'Sources/gor/Station/Host.swift').symlink_to('../real.txt')
expect_red('symlink carrier', d2, UNIT_PIN)
shutil.rmtree(d)
shutil.rmtree(d2)

# doublecarrier: the same unit MARK in two differing files is ambiguous, never first-wins
d = tree()
(d / 'Sources/gor/Station/Other.swift').write_text('import AppKit\n\n// MARK: - Unit.swift\n\nlet unitBytes = 2\n')
expect_red('doublecarrier', d, UNIT_PIN)
shutil.rmtree(d)

print('PASS section-pin hardening: host must be safe-relative/regular/non-symlink and equal the resolved carrier; wronghost/missinghost/symlink/doublecarrier RED')
