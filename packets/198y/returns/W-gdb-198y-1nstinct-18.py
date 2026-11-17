#!/usr/bin/env python3
"""Source-only S1 relocation characterization. No Swift runtime/build claim.
Run from any directory. --self-test runs isolated temporary mutation fixtures.
Production sources are read only; no shared helper dependency.
"""
from pathlib import Path
import argparse
import hashlib
import re
import tempfile
import sys
PACKET = 'W-gdb-198y-1nstinct-18'
PIN = 'bb3e0ea0b839d1b90179b0c95c93257ca3685fb8'
FILENAME = 'PanelFocus.swift'
STATION = 'GorPlatformMac'
EXPECTED_SHA256 = '617b617586a9f12900bed807f162cd0000d86bd082fa06fa3754a91ffe3374a5'
DECLARATIONS = {'class GORInputPanel': 1}
TOKENS = ['GORInputPanel', 'registerKeyOwnership', 'releaseKeyOwnership', 'logFocus', 'rememberFocus', 'firstEditable', 'restorePanelFocus', 'closeAllForQuit']

class CharacterizationError(Exception):
    pass


def swift_code(text):
    """Mask comments and string literals, retaining newlines and offsets.

    This is a lexical filter, not a Swift parser. It handles nested block
    comments and ordinary, multiline and hash-delimited Swift strings.
    """
    out = list(text)
    i, size = 0, len(text)
    def mask(a, b):
        for j in range(a, b):
            if out[j] != '\n':
                out[j] = ' '
    while i < size:
        start = i
        if text.startswith('//', i):
            end = text.find('\n', i)
            i = size if end < 0 else end
        elif text.startswith('/*', i):
            depth = 1
            i += 2
            while i < size and depth:
                if text.startswith('/*', i): depth += 1; i += 2
                elif text.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
        else:
            q = i
            while q < size and text[q] == '#': q += 1
            hashes = q-i
            if q >= size or text[q] != '"':
                i += 1
                continue
            quote = '"""' if text.startswith('"""', q) else '"'
            endmark = quote + '#'*hashes
            i = q+len(quote)
            while i < size:
                if text.startswith('\\'+'#'*hashes, i):
                    i += hashes+2
                elif text.startswith(endmark, i):
                    i += len(endmark)
                    break
                else: i += 1
        mask(start, min(i, size))
    return ''.join(out)


def declaration_count(code, declaration):
    kind, name = declaration.split()
    return len(re.findall(r'\b'+kind+r'\s+'+re.escape(name)+r'\b', code))


def validate_declarations(raw):
    try:
        code = swift_code(raw.decode('utf-8'))
    except UnicodeDecodeError as exc:
        raise CharacterizationError('source is not UTF-8') from exc
    for declaration, expected in DECLARATIONS.items():
        actual = declaration_count(code, declaration)
        if actual != expected:
            raise CharacterizationError('declaration count: '+declaration+
                                        ' expected '+str(expected)+' got '+str(actual))
    for token in TOKENS:
        if not re.search(r'\b'+re.escape(token)+r'\b', code):
            raise CharacterizationError('missing executable-source token: '+token)


def check_tree(root):
    sources = root/'archive/gor/Sources'
    old = sources/'gor'/FILENAME
    moved = sources/STATION/FILENAME
    # lexists equivalent: broken links must not be mistaken for absence.
    present = [p for p in (old, moved) if p.exists() or p.is_symlink()]
    if len(present) != 1:
        raise CharacterizationError('station cardinality: expected exactly one old/new source')
    selected = present[0]
    if not selected.is_file() or selected.is_symlink():
        raise CharacterizationError('station source is not a regular non-symlink file')
    if any(p.is_symlink() for p in selected.parents if p != root.parent):
        raise CharacterizationError('station source has a symlink ancestor')
    for p in sources.rglob(FILENAME):
        if p != selected:
            raise CharacterizationError('same filename in wrong/duplicate station: '+str(p))
    raw = selected.read_bytes()
    validate_declarations(raw)
    if hashlib.sha256(raw).hexdigest() != EXPECTED_SHA256:
        raise CharacterizationError('pinned byte drift: explicit rebase/review required')
    # A differently named copy is still a duplicate. Extensions are legal,
    # but a repeated owned method (packet 17) is not.
    for p in sources.rglob('*.swift'):
        if p == selected or not p.is_file(): continue
        if p.is_symlink():
            raise CharacterizationError('symlink Swift source prevents reliable duplicate scan')
        try: other = swift_code(p.read_text(encoding='utf-8'))
        except UnicodeDecodeError as exc:
            raise CharacterizationError('cannot inspect Swift file: '+str(p)) from exc
        for declaration in DECLARATIONS:
            if declaration_count(other, declaration):
                raise CharacterizationError('duplicate owned declaration: '+declaration+' in '+str(p))
    return selected.relative_to(root).as_posix(), raw


def self_test(raw):
    """Exercise the real validator on fixture trees, not checksum tautologies."""
    cases = 0
    def run_case(name, setup, error=None):
        nonlocal cases
        with tempfile.TemporaryDirectory(prefix='198y-') as tmp:
            root = Path(tmp)
            old = root/'archive/gor/Sources/gor'/FILENAME
            new = root/'archive/gor/Sources'/STATION/FILENAME
            old.parent.mkdir(parents=True)
            old.write_bytes(raw)
            def put(path, data):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            setup(root, old, new, put)
            try:
                check_tree(root)
            except CharacterizationError as exc:
                if error is None or error not in str(exc):
                    raise AssertionError(name+': unexpected rejection: '+str(exc)) from exc
            else:
                if error is not None: raise AssertionError(name+': mutant survived')
            cases += 1
            print('MUTATION_PASS '+name+' '+('ACCEPT' if error is None else 'REJECT'))
    noop = lambda *args: None
    def move(root, old, new, put):
        put(new, raw); old.unlink()
    run_case('old-only', noop)
    run_case('station-only', move)
    run_case('old-and-new', lambda r,o,n,p: p(n,raw), 'cardinality')
    run_case('both-missing', lambda r,o,n,p: o.unlink(), 'cardinality')
    def wrong(root, old, new, put):
        old.unlink(); put(root/'archive/gor/Sources/WrongStation'/FILENAME,raw)
    run_case('wrong-station-only', wrong, 'cardinality')
    run_case('wrong-station-extra', lambda r,o,n,p: p(r/'archive/gor/Sources/WrongStation'/FILENAME,raw), 'same filename')
    run_case('renamed-duplicate', lambda r,o,n,p: p(n.parent/'UnexpectedCopy.swift',raw), 'duplicate owned')
    def moved_duplicate(root, old, new, put):
        move(root,old,new,put);put(old.parent/'RenamedCopy.swift',raw)
    run_case('moved-plus-renamed-old-duplicate', moved_duplicate, 'duplicate owned')
    run_case('trailing-byte-drift', lambda r,o,n,p: o.write_bytes(raw+b'\n'), 'byte drift')
    run_case('line-ending-drift', lambda r,o,n,p: o.write_bytes(raw.replace(b'\n',b'\r\n')), 'byte drift')
    first = next(iter(DECLARATIONS))
    kind, name = first.split()
    changed = re.sub(rb'\b'+name.encode()+rb'\b',name.encode()+b'Mutant',raw)
    run_case('declaration-rename', lambda r,o,n,p: o.write_bytes(changed), 'declaration count')
    run_case('truncated-file', lambda r,o,n,p: o.write_bytes(b''), 'declaration count')
    run_case('same-file-declaration-duplicate', lambda r,o,n,p: o.write_bytes(raw+b'\n'+(first+' {}').encode()), 'declaration count')
    def directory(root, old, new, put): old.unlink();old.mkdir()
    run_case('directory-as-source', directory, 'regular')
    def symlink(root, old, new, put):
        put(root/'outside.swift', raw); old.unlink();old.symlink_to(root/'outside.swift')
    run_case('symlink-source', symlink, 'regular')
    declarations = '\n'.join(d+' {}' for d in DECLARATIONS)
    decoy = ('// '+declarations.replace('\n','\n// ')+'\n/* outer /* nested */ '+declarations+' */\n'+
             'let a = "'+declarations.replace('\n',' ')+'"\n'+
             'let b = #"'+declarations.replace('\n',' ')+'"#\n'+
             'let c = """\n'+declarations+'\n"""\n').encode()
    run_case('comments-and-strings-not-declarations',lambda r,o,n,p: p(n.parent/'Decoys.swift',decoy))
    for index, declaration in enumerate(DECLARATIONS):
        # Duplicate declaration probe in a different source, independently
        # of the identity check on the selected file.
        stub = (declaration+' {}\n').encode()
        run_case('duplicate-declaration-'+str(index),lambda r,o,n,p,s=stub:p(n.parent/'Duplicate.swift',s),'duplicate owned')
    print('MUTATION_TOTAL '+str(cases))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[5])
    parser.add_argument('--self-test', action='store_true', help='explicitly run the default mutation suite')
    parser.add_argument('--check-only', action='store_true', help='skip isolated mutation fixtures')
    args = parser.parse_args()
    try:
        selected, raw = check_tree(args.root.resolve())
        count = 0 if args.check_only else self_test(raw)
    except (CharacterizationError, OSError, AssertionError) as exc:
        print('CHARACTERIZATION_FAIL '+PACKET+': '+str(exc), file=sys.stderr)
        return 1
    print('CHARACTERIZATION_PASS '+PACKET+': station='+selected+
          '; pinned_bytes=PASS; declarations=PASS; duplicates=PASS; mutations='+str(count)+
          '; source-only; Swift_runtime=NOT_RUN; package_build=NOT_RUN')
    return 0

if __name__ == '__main__':
    sys.exit(main())
