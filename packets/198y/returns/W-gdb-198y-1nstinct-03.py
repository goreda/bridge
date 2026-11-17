"""Read-only source-boundary characterization; Swift compile/runtime NOT_RUN.

Default checks the repository and runs isolated filesystem mutants. --check-root
checks a supplied tree only, allowing CI to discriminate real invalid trees.
No production writes. The Swift scanner is lexical, not a compiler/typechecker.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import tempfile

CONFIG = {'id': 'W-gdb-198y-1nstinct-03', 'filename': 'ArchiveLibrary.swift', 'station': 'GorSources', 'sha256': '772942f9057fe2486eac455c145f544e7101238dc52e1693e0aee32cf5a6f1a3', 'nominal_types': ['ArchiveLibrary'], 'source_product_pin_sender_reported': 'bb3e0ea0b839d1b90179b0c95c93257ca3685fb8'}

class Rejected(Exception):
    pass

def require(ok, message):
    if not ok:
        raise Rejected(message)

def tokens(source):
    """Drop comments and Swift quoted strings before declaration inspection.

    Supports nested block comments, multiline/raw quoted strings and escapes.
    Conditional compilation is deliberately conservative: all branches scanned.
    Regex literal and full Swift macro semantics are not characterized here.
    """
    result = []
    i = 0
    while i < len(source):
        if source.startswith('//', i):
            end = source.find('\n', i + 2)
            i = len(source) if end < 0 else end + 1
        elif source.startswith('/*', i):
            depth = 1
            i += 2
            while i < len(source) and depth:
                if source.startswith('/*', i):
                    depth += 1
                    i += 2
                elif source.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            require(depth == 0, 'unterminated block comment')
        else:
            string = re.match(r'(\#*)("""|")', source[i:])
            if string:
                hashes, quote = string.groups()
                i += len(string.group())
                ending = quote + hashes
                while i < len(source):
                    if source.startswith('\\' + hashes, i):
                        i += len(hashes) + 2
                    elif source.startswith(ending, i):
                        i += len(ending)
                        break
                    else:
                        i += 1
                else:
                    raise Rejected('unterminated quoted string')
                result.append('STRING')
            else:
                word = re.match(r'`[A-Za-z_][A-Za-z_0-9]*`|[A-Za-z_][A-Za-z_0-9]*|\S', source[i:])
                if word:
                    result.append(word.group().strip('`'))
                    i += len(word.group())
                else:
                    i += 1
    return result

def declarations(source):
    t = tokens(source)
    depth = 0
    nominals = []
    methods = []
    extension = None
    pending_extension = None
    for i, word in enumerate(t):
        if depth == 0 and word in ('class', 'struct', 'enum', 'protocol', 'actor', 'typealias'):
            # Ignore class func/var modifiers.
            if i + 1 < len(t) and t[i + 1] not in ('func', 'var', 'let', 'subscript'):
                nominals.append(t[i + 1])
        if depth == 0 and word == 'extension' and i + 1 < len(t):
            pending_extension = t[i + 1]
        if extension and depth == 1 and word == 'func' and i + 2 < len(t):
            name = t[i + 1]
            k = i + 2
            if t[k] == '(':
                k += 1
                args = []
                arg = []
                nested = 0
                while k < len(t):
                    v = t[k]
                    if v == ')' and nested == 0:
                        if arg:
                            args.append(arg)
                        break
                    if v == ',' and nested == 0:
                        args.append(arg)
                        arg = []
                    else:
                        arg.append(v)
                        if v in ('(', '[', '<'):
                            nested += 1
                        elif v in (')', ']', '>'):
                            nested -= 1
                    k += 1
                signature = []
                for arg in args:
                    if ':' in arg:
                        colon = arg.index(':')
                        type_tokens = arg[colon + 1:]
                        if '=' in type_tokens:
                            type_tokens = type_tokens[:type_tokens.index('=')]
                        signature.append((arg[0], tuple(type_tokens)))
                methods.append((extension, name, tuple(signature)))
        if word == '{':
            if depth == 0:
                extension = pending_extension
                pending_extension = None
            depth += 1
        elif word == '}':
            depth -= 1
            require(depth >= 0, 'unbalanced closing brace')
            if depth == 0:
                extension = None
    require(depth == 0, 'unbalanced brace structure')
    return nominals, methods

def locations(root):
    base = root / 'archive/gor/Sources'
    return base, list(dict.fromkeys([base / 'gor' / CONFIG['filename'],
                                    base / CONFIG['station'] / CONFIG['filename']]))

def check_tree(root):
    base, allowed = locations(root)
    require(base.is_dir() and not base.is_symlink(), 'source root missing or symlink')
    present = [p for p in allowed if p.exists() or p.is_symlink()]
    require(len(present) == 1, 'expected exactly one legacy/station owner')
    selected = present[0]
    require(selected.is_file() and not any(x.is_symlink() for x in [selected, *selected.parents] if x != root.parent), 'owner path must be a regular non-symlink file')
    data = selected.read_bytes()
    require(hashlib.sha256(data).hexdigest() == CONFIG['sha256'], 'pinned source byte drift')
    own_types, own_methods = declarations(data.decode('utf-8'))
    require(own_types == CONFIG['nominal_types'], 'nominal declaration boundary drift')
    require(len(own_types) == len(set(own_types)), 'duplicate nominal declarations in owner')
    # Same-basename copies are forbidden anywhere in Sources, including wrong station.
    for other in base.rglob(CONFIG['filename']):
        require(other == selected, 'duplicate or misplaced source basename: ' + str(other.relative_to(base)))
    # Reject nominal redeclarations under another filename in old/new ownership roots.
    # Nested local type names are not global types. Comments/strings are not declarations.
    scope = set([base / 'gor', base / CONFIG['station']])
    for directory in sorted(scope):
        if not directory.exists():
            continue
        require(not directory.is_symlink(), 'station directory symlink')
        for other in directory.rglob('*.swift'):
            if other == selected:
                continue
            require(not other.is_symlink(), 'Swift source symlink')
            text = other.read_text(encoding='utf-8')
            # Avoid parsing unrelated Swift dialect features unless owned names occur.
            if not any(name in text for name in own_types) and not any(m[1] in text for m in own_methods):
                continue
            found_types, found_methods = declarations(text)
            require(not set(own_types).intersection(found_types), 'duplicate owned nominal type: ' + str(other.relative_to(base)))
            require(not set(own_methods).intersection(found_methods), 'duplicate owned extension signature: ' + str(other.relative_to(base)))
    return selected, data, own_types, own_methods

def mutation_suite(data, own_types, own_methods):
    results = []
    with tempfile.TemporaryDirectory(prefix='198y-characterization-') as temp:
        root = Path(temp)
        base, allowed = locations(root)
        def reset():
            # Only remove test-created files, never product files.
            import shutil
            if base.exists():
                shutil.rmtree(base)
            base.mkdir(parents=True)
        def put(path, value):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        def expect(label, okay, setup):
            reset()
            setup()
            try:
                check_tree(root)
                actual = True
            except (Rejected, OSError, UnicodeError):
                actual = False
            require(actual == okay, 'self-test misclassified: ' + label)
            results.append({'case': label, 'expected': 'PASS' if okay else 'REJECT', 'observed': 'PASS' if actual else 'REJECT'})
        old = allowed[0]
        new = allowed[-1]
        expect('legacy-exact', True, lambda: put(old, data))
        expect('station-exact', True, lambda: put(new, data))
        expect('missing-owner', False, lambda: None)
        expect('byte-drift', False, lambda: put(old, data + b'\n'))
        expect('same-size-byte-drift', False, lambda: put(new, bytes([data[0] ^ 1]) + data[1:]))
        wrong = base / 'WrongStation' / CONFIG['filename']
        expect('wrong-station-only', False, lambda: put(wrong, data))
        expect('wrong-station-extra-copy', False, lambda: (put(old, data), put(wrong, data)))
        if old != new:
            expect('old-new-double-owner', False, lambda: (put(old, data), put(new, data)))
        else:
            results.append({'case': 'old-new-double-owner', 'expected': 'NOT_APPLICABLE_station_is_gor', 'observed': 'NOT_APPLICABLE_station_is_gor'})
        expect('owner-symlink', False, lambda: (put(base / 'held.swift', data), old.parent.mkdir(parents=True, exist_ok=True), old.symlink_to(base / 'held.swift')))
        targets = list(dict.fromkeys([base / 'gor', base / CONFIG['station']]))
        for index, directory in enumerate(targets):
            duplicate = directory / 'RenamedDuplicate.swift'
            if own_types:
                for name in own_types:
                    expect('nominal-duplicate-' + str(index) + '-' + name, False,
                           lambda name=name: (put(new, data), put(duplicate, ('struct ' + name + ' {}\n').encode())))
                harmless = ('// struct ' + own_types[0] + ' {}\nlet note = "struct ' + own_types[0] + ' {}"\nstruct Unrelated { struct ' + own_types[0] + ' {} }\n').encode()
                expect('comments-strings-nested-nominal-' + str(index), True,
                       lambda: (put(new, data), put(duplicate, harmless)))
            else:
                # This packet owns extensions, not nominal types; use real extension
                # signatures extracted from its exact bytes, not invented types.
                for owner, name, args in own_methods:
                    params = ', '.join(label + ' p' + str(k) + ': ' + ' '.join(typ)
                                       if label != '_' else '_ p' + str(k) + ': ' + ' '.join(typ)
                                       for k, (label, typ) in enumerate(args))
                    extension = ('extension ' + owner + ' { func ' + name + '(' + params + ') {} }\n').encode()
                    expect('extension-duplicate-' + str(index) + '-' + owner + '.' + name, False,
                           lambda extension=extension: (put(new, data), put(duplicate, extension)))
                expect('unrelated-extension-' + str(index), True,
                       lambda: (put(new, data), put(duplicate, b'extension SpineUI { func unrelated198y() {} }\n')))
                expect('distinct-extension-overload-' + str(index), True,
                       lambda: (put(new, data), put(duplicate, b'extension SpineUI { func applyAdaptiveColor(_ value: Int) {} }\n')))
                expect('comment-and-string-extension-' + str(index), True,
                       lambda: (put(new, data), put(duplicate, b'/* extension SpineUI { func applyAdaptiveColor(_ c: NSColor) {} } */\nlet note = #"extension SpineUI { func applyAdaptiveColor(_ c: NSColor) {} }"#\n')))
    return results

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-root', type=Path, help='check this tree only; no mutation self-tests')
    args = parser.parse_args()
    root = args.check_root.resolve() if args.check_root else Path(__file__).resolve().parents[5]
    selected, data, own_types, own_methods = check_tree(root)
    if not args.check_root:
        cases = mutation_suite(data, own_types, own_methods)
        for case in cases:
            print(json.dumps(case, sort_keys=True))
    else:
        cases = []
    print('CHARACTERIZATION_PASS ' + CONFIG['id'] + ': ' + str(selected.relative_to(root)) +
          '; filesystem cases=' + str(len(cases)) + '; source-only; Swift compile/runtime NOT_RUN; clean_checkout not asserted')

if __name__ == '__main__':
    try:
        main()
    except (Rejected, OSError, UnicodeError) as exc:
        print('CHARACTERIZATION_FAIL ' + CONFIG['id'] + ': ' + str(exc), file=sys.stderr)
        sys.exit(1)
