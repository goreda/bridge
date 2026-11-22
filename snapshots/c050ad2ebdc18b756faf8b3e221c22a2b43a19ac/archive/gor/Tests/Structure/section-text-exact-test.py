#!/usr/bin/env python3
"""Exact text lookup preserves LF/CRLF and blank-line boundaries.

The legacy section_text/pinned_bytes normalization is deliberately untouched.
"""
from pathlib import Path
import importlib.util
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('exact_section_fixture', ROOT / 'Tests/Structure/section_source.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)

with tempfile.TemporaryDirectory(prefix='section-exact-') as folder:
    root = Path(folder)
    source = root / 'Sources/gor'
    source.mkdir(parents=True)
    first = source / 'First.swift'
    carrier = source / 'Station.swift'
    for ending in ('\n', '\r\n'):
        body = ('import Foundation' + ending + '// MARK: - Internal topic' + ending
                + 'enum First {}' + ending * 3)
        first.write_bytes(body.encode())
        assert s.section_text_exact(root, 'First.swift') == body
        carrier.write_bytes(('// MARK: - First.swift' + ending + body
                             + '// MARK: - Next.swift' + ending + 'enum Next {}' + ending).encode())
        # Exact MARK wins even while the old standalone remains during overlap.
        first.write_text('enum Stale {}\n')
        assert s.section_text_exact(root, 'First.swift') == body
        first.unlink()
        assert s.section_text_exact(root, 'First.swift') == body
        # Legacy pins keep their original normalization rather than inheriting
        # the reconstruction API's extra blank lines and CRLF preservation.
        assert s.section_text(root, 'First.swift') == body.replace('\r\n', '\n').rstrip('\n') + '\n\n'
        carrier.unlink()
    first.write_text('enum First {}')
    assert s.section_text_exact(root, 'First.swift') == 'enum First {}'
    first.unlink()
    carrier.write_text('// MARK: - First.swift\nenum First {}\n// MARK: - First.swift\nenum FirstAgain {}\n')
    try:
        s.section_text_exact(root, 'First.swift')
    except KeyError:
        pass
    else:
        raise AssertionError('duplicate same-file unit was accepted')
print('PASS exact unit text: standalone/MARK precedence, LF/CRLF, trailing blanks, EOF and duplicate rejection')
