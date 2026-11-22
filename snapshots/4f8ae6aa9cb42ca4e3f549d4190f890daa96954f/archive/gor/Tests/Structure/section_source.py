"""arch-199u STEP0: symbol-/MARK-section source lookup, path- and position-independent.

Every harness consumer that extracts or compiles Swift locates its target by
logical name (original file stem, MARK section, or declaration symbol), never
by a pinned path or by a position inside a file. A 199u station move places a
unit's bytes under `// MARK: - <OriginalFileName>` in its station file; these
lookups keep resolving the same bytes whichever file hosts them.

Lookup order for a logical unit name `Foo`:
  1. a standalone file Sources/gor/**/Foo.swift (current pre-move tree),
  2. a `// MARK: - Foo` section inside any Sources/gor/**/*.swift
     (post-move tree): bytes from the line after the MARK header up to the
     next `// MARK:` line or end of file,
  3. nowhere: KeyError, callers fail closed.

Symbols (class/struct/enum/actor/extension/func) are found tree-wide and
extracted with balanced braces, so a declaration that is no longer the last
thing in its file is still bounded exactly (the S3 98f4b423b tail-extraction
defect class). Brace counting is lexical (strings/comments not parsed), the
same convention as the existing harness block() helpers.

Test-only. Never imported by the app or by build.sh product paths.
"""
from pathlib import Path
import re

MARK = '// MARK: - '
# A 199u unit section ends only at the next unit header: `// MARK: - <OriginalFileName>`,
# which always carries the .swift extension. Internal `// MARK: - <topic>` comments
# inside a unit never terminate it.
UNIT_MARK = re.compile(r'^// MARK: - .+\.swift\s*$')


def _stem(name):
    return name[:-len('.swift')] if name.endswith('.swift') else name


def _mark_names(name):
    """A 199u MARK header carries the original file name (`// MARK: - Foo.swift`).
    The bare-stem variant is only tried for units named without an extension: a
    suffixless `// MARK: - Foo` inside another file is a topic mark, not a unit."""
    if name.endswith('.swift'):
        return [name]
    return [name + '.swift', name]


def source_root(root):
    return Path(root) / 'Sources/gor'


def swift_files(root):
    base = source_root(root)
    # regular files only: a symlinked carrier is not a source unit (pin hardening)
    return sorted(p for p in base.rglob('*.swift') if p.is_file() and not p.is_symlink())


def _files(root):
    root = Path(root)
    if (root / 'Sources/gor').is_dir():
        return swift_files(root)
    # tolerate callers passing the archive/gor directory's parent styles
    raise KeyError('Sources/gor not under %s' % root)


def section_file(root, name):
    """The file hosting logical unit `name`. The unit's exact MARK section
    (`// MARK: - <name>`) is the strongest anchor and wins during migration
    overlap, when a retired pre-move copy still sits next to the station file.
    Otherwise the standalone Foo.swift. Ambiguity (two differing MARK carriers,
    or two differing standalones with no MARK) fails closed."""
    needles = [MARK + n for n in _mark_names(name)]
    def carriers(nk):
        out = []
        for p in files:
            for line in p.read_text().splitlines():
                if any(line.startswith(n) and line[len(n):].rstrip() == '' for n in nk):
                    out.append(p)
                    break
        return out
    files = _files(root)
    marks = carriers(needles[:1]) or carriers(needles[1:])
    if len(marks) > 1:
        raise KeyError('ambiguous MARK section %s: %s' % (name, [str(x) for x in marks]))
    if marks:
        return marks[0]
    standalone = [p for p in files if p.stem == _stem(name)]
    if standalone:
        first = standalone[0].read_text()
        for p in standalone[1:]:
            if p.read_text() != first:
                raise KeyError('ambiguous unit %s: %s' % (name, [str(x) for x in standalone]))
        return standalone[0]
    raise KeyError('no file or MARK section named %s' % name)


def section_text(root, name):
    """Exact bytes of logical unit `name`: the whole standalone file, or the
    section under its `// MARK: - <name>` header (header line excluded)."""
    p = section_file(root, name)
    if p.stem == _stem(name) and not any(UNIT_MARK.match(l) for l in p.read_text().split('\n')):
        return p.read_text()
    needles = [MARK + n for n in _mark_names(name)]
    lines = p.read_text().split('\n')
    for i, line in enumerate(lines):
        if any(line.startswith(n) and line[len(n):].rstrip() == '' for n in needles):
            out = []
            for rest in lines[i + 1:]:
                if UNIT_MARK.match(rest):
                    break
                out.append(rest)
            text = '\n'.join(out)
            if text.endswith('\n'):
                text = text[:-1]
            return text + '\n'
    raise KeyError('MARK section vanished for %s' % name)


_DECL = re.compile(
    r'^(?P<indent>[ \t]*)[^\S\n]*(?:(?:public|private|internal|fileprivate|open|final|static|indirect|nonisolated|isolated)\s+)*'
    r'(?P<kind>class|struct|enum|actor|extension|protocol)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b')


def _balanced(lines, start, first_line_offset):
    """Balanced-brace bounded slice starting at line `start`; first_line_offset is
    the column where scanning begins on the first line. Returns (end_index, text)."""
    depth = 0
    seen = False
    for i in range(start, len(lines)):
        line = lines[i]
        seg = line[first_line_offset:] if i == start else line
        for ch in seg:
            if ch == '{':
                depth += 1
                seen = True
            elif ch == '}':
                depth -= 1
                if seen and depth == 0:
                    return i, '\n'.join(lines[start:i + 1])
    raise KeyError('unbalanced braces from line %d' % (start + 1))


def symbol_decl(root, name, kind=None):
    """Locate the declaration of symbol `name` tree-wide. Returns
    (path, line_index, line). `kind` optionally pins class/struct/enum/actor/extension/protocol."""
    for p in _files(root):
        lines = p.read_text().split('\n')
        for i, line in enumerate(lines):
            m = _DECL.match(line)
            if m and m.group('name') == name and (kind is None or m.group('kind') == kind):
                return p, i, line
    raise KeyError('no declaration of %s (kind=%s)' % (name, kind))


def symbol_text(root, name, kind=None):
    """Bounded declaration bytes for symbol `name`: from the first modifier of
    its declaration line through the closing brace. Never a tail to end-of-file."""
    p, i, line = symbol_decl(root, name, kind)
    lines = p.read_text().split('\n')
    _, text = _balanced(lines, i, 0)
    return text


def func_text(root, signature_substr, within=None):
    """Bounded func bytes: the declaration line containing `signature_substr`
    through its closing brace. `within` optionally restricts to the file hosting
    that MARK section or logical unit name."""
    files = [section_file(root, within)] if within else _files(root)
    for p in files:
        lines = p.read_text().split('\n')
        for i, line in enumerate(lines):
            if signature_substr in line and 'func ' in line:
                _, text = _balanced(lines, i, 0)
                return text
    raise KeyError('no func matching %r' % signature_substr)


def host_text(root, marker):
    """Full text of the single Sources/gor file containing `marker`
    (legacy block()-style consumers that then slice by symbol)."""
    hits = [p for p in _files(root) if marker in p.read_text()]
    assert len(hits) == 1, (marker, hits)
    return hits[0].read_text()


def pinned_bytes(root, relative):
    """Bytes named by a retirement-style pin `path` or `path#Unit.swift`: the whole
    file when the literal path exists, else the named unit's MARK section in the
    composed station file. arch-199u: re-moved units pin their section bytes.
    Raises (fail closed) when neither resolves."""
    root = Path(root)
    rel, _, unit = str(relative).partition('#')
    if unit:
        # Fail closed on the declared host: safe-relative, present, regular,
        # non-symlink, and it must BE the resolved carrier of the unit's MARK
        # section - a same-named section in any other file is not this pin.
        rel_p = Path(rel)
        if rel_p.is_absolute() or '..' in rel_p.parts:
            raise KeyError('unsafe pin host path: %s' % relative)
        host = root / rel_p
        if not host.is_file() or host.is_symlink():
            raise KeyError('pin host missing or not a regular file: %s' % relative)
        resolved = section_file(root, unit)
        if resolved != host:
            raise KeyError('pin host mismatch for %s: declared %s, carrier %s'
                           % (unit, rel, resolved.relative_to(root)))
        return section_text(root, unit).encode()
    p = root / rel
    if p.is_file() and not p.is_symlink():
        return p.read_bytes()
    raise KeyError('pin path missing and no unit given: %s' % relative)


def section_text_exact(root, name):
    """Raw logical-unit text for source-reconstruction fixtures.

    Unlike section_text's historical pin normalization, preserve every newline
    between this unit header and the next unit header. Existing retirement pins
    keep their original section_text behavior.
    """
    p = section_file(root, name)
    text = p.read_bytes().decode('utf-8')
    needles = [MARK + n for n in _mark_names(name)]
    lines = text.splitlines(keepends=True)
    start = None
    for i, line in enumerate(lines):
        bare = line.rstrip('\r\n')
        if any(bare.startswith(n) and bare[len(n):].rstrip() == '' for n in needles):
            if start is not None:
                raise KeyError('duplicate MARK unit %s' % name)
            start = i + 1
    if start is None:
        if p.stem == _stem(name):
            return text
        raise KeyError('MARK section vanished for %s' % name)
    end = next((i for i in range(start, len(lines))
                if UNIT_MARK.match(lines[i].rstrip('\r\n'))), len(lines))
    return ''.join(lines[start:end])
