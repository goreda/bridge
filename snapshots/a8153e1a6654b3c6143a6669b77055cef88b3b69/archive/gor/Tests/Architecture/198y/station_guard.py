"""S2 lexical ownership guards. Not Swift typechecking or runtime acceptance.
Comments/strings are masked. Nested nominal names are qualified, not global.
No source content hashes: additive merged owner content is allowed.
"""
from pathlib import Path
import argparse
import csv
import re
import tempfile
from collections import Counter
from functools import lru_cache

class Rejected(Exception):
    pass

def require(ok, message):
    if not ok:
        raise Rejected(message)

@lru_cache(maxsize=256)
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
            string = re.compile(r'(\#*)("""|")').match(source, i)
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
                word = re.compile(r'`[A-Za-z_][A-Za-z_0-9]*`|[A-Za-z_][A-Za-z_0-9]*|\S').match(source, i)
                if word:
                    result.append(word.group().strip('`'))
                    i += len(word.group())
                else:
                    i += 1
    return result

@lru_cache(maxsize=256)
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


@lru_cache(maxsize=256)
def qualified_nominals(source):
    """Qualify nested names by their nominal/extension scope, not local spelling."""
    stream = tokens(source)
    stack, pending, found = [], None, []
    for index, word in enumerate(stream):
        if word in ('struct', 'enum', 'class', 'protocol', 'actor', 'typealias') and index + 1 < len(stream):
            name = stream[index + 1]
            if name in ('func', 'var', 'let', 'subscript'):
                continue
            owners = [part for part in stack if part]
            qualified = '.'.join(owners + [name])
            found.append(qualified)
            if word != 'typealias':
                pending = name
        elif word == 'extension' and index + 1 < len(stream):
            pending = stream[index + 1]
        if word == '{':
            stack.append(pending)
            pending = None
        elif word == '}':
            require(bool(stack), 'unbalanced scope')
            stack.pop()
    require(not stack, 'unbalanced scope')
    return found


def owner_source(root, source, relative, config):
    """Acquire an exact moved Platform unit, or retain the original owner path.

    The original policy row still describes the logical pre-move unit. This
    adapter does not review a new policy path or approve a different station.
    All lexical ownership checks below continue to see the same original unit.
    """
    selected = root / 'archive/gor' / relative
    mapping = root / 'archive/gor/Tests/Structure/199u-platform-map.json'
    if not selected.exists() and not selected.is_symlink() and mapping.is_file():
        import importlib.util
        import json
        meta = json.loads(mapping.read_text())
        record = meta.get('sections', {}).get(config['filename'])
        if record and record['old'] == relative.as_posix():
            require(meta['station'] == 'Platform', 'moved unit station map changed')
            project = root / 'archive/gor'
            spec = importlib.util.spec_from_file_location('platform_owner_source', project / 'Tests/Structure/platform_source.py')
            view = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(view)
            text = view.unit_text(config['filename'], project)
            import hashlib
            carrier = view._sections.section_file(project, config['filename'])
            require(hashlib.sha256(carrier.read_bytes()).hexdigest() == meta['hosts'][record['host']]['sha256'], 'moved carrier bytes changed')
            selected = view._sections.section_file(project, config['filename'])
            require(selected.is_relative_to(source), 'moved owner outside source root')
            require(selected.is_file() and not any(p.is_symlink() for p in [selected, *selected.parents]), 'owner must be regular, not symlink')
            matches = list(source.rglob(config['filename']))
            expected = [selected] if selected.name == config['filename'] else []
            require(matches == expected, 'duplicate/misplaced owner filename')
            return selected, text
    require(selected.is_file() and not any(p.is_symlink() for p in [selected, *selected.parents]), 'owner must be regular, not symlink')
    matches = list(source.rglob(config['filename']))
    require(matches == [selected], 'duplicate/misplaced owner filename')
    return selected, selected.read_text()


def check_tree(root, config):
    source = root / 'archive/gor/Sources/gor'
    policy = root / 'archive/gor/architecture/policy.tsv'
    require(source.is_dir() and not source.is_symlink(), 'source root missing or symlink')
    rows = list(csv.DictReader(policy.open(), delimiter='\t'))
    rows = [row for row in rows if row['path'].startswith('Sources/gor/') and Path(row['path']).name == config['filename']]
    require(len(rows) == 1, 'one explicit owner policy row required')
    row = rows[0]
    require(row['planned target'] == config['station'], 'reviewed station changed')
    relative = Path(row['path'])
    require(not relative.is_absolute() and '..' not in relative.parts, 'unsafe owner path')
    require(relative.parts[:3] == ('Sources', 'gor', config['station']), 'owner not in policy station folder')
    selected, text = owner_source(root, source, relative, config)
    own_types, own_methods = declarations(text)
    require(set(config['required_types']).issubset(own_types), 'required top-level declaration missing')
    require(set(config.get('required_extensions', [])).issubset(own_methods), 'required qualified extension signature missing')
    lexical = tokens(text)
    require(all(token in lexical for token in config['required_tokens']), 'required source symbol missing')
    owned = qualified_nominals(text)
    require(all(n == 1 for n in Counter(owned).values()), 'duplicate qualified declaration in owner')
    require(len(own_methods) == len(set(own_methods)), 'duplicate extension signature in owner')
    require(own_types or own_methods, 'empty owner boundary')
    for other in source.rglob('*.swift'):
        if other == selected:
            continue
        require(not other.is_symlink(), 'Swift source symlink')
        data = other.read_text()
        if not any(name.split('.')[-1] in data for name in owned) and not any(m[1] in data for m in own_methods):
            continue
        foreign = qualified_nominals(data)
        _, methods = declarations(data)
        require(not set(owned).intersection(foreign), 'qualified owner redeclared elsewhere')
        require(not set(own_methods).intersection(methods), 'owned extension signature redeclared elsewhere')
    return selected, text, own_types, own_methods


def mutation_suite(config, text, own_types, own_methods):
    cases = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory).resolve()
        def setup():
            import shutil
            if (root / 'archive').exists():
                shutil.rmtree(root / 'archive')
            owner = root / 'archive/gor/Sources/gor' / config['station'] / config['filename']
            owner.parent.mkdir(parents=True)
            owner.write_text(text)
            policy = root / 'archive/gor/architecture/policy.tsv'
            policy.parent.mkdir()
            policy.write_text('path\tplanned target\nSources/gor/' + config['station'] + '/' + config['filename'] + '\t' + config['station'] + '\n')
            return owner
        def case(name, expected, mutate):
            owner = setup()
            mutate(owner)
            try:
                check_tree(root, config)
                actual = True
            except (Rejected, OSError, UnicodeError):
                actual = False
            require(actual == expected, 'mutation misclassified: ' + name)
            cases.append(name)
        def duplicate(owner, body):
            (owner.parent / 'RenamedDuplicate.swift').write_text(body)
        case('station-owner', True, lambda p: None)
        case('additive-owner-comments-whitespace', True, lambda p: p.write_text(text + '\n// additive owner comment\n'))
        case('merged-additive-declaration', True, lambda p: p.write_text(text + '\nstruct NewMergedOwnershipValue {}\n'))
        case('missing-owner', False, lambda p: p.unlink())
        def symlink_owner(p):
            held = p.with_suffix('.held')
            p.rename(held)
            p.symlink_to(held)
        case('symlink-owner', False, symlink_owner)
        case('wrong-station', False, lambda p: p.rename(p.parent.parent / config['filename']))
        case('renamed-full-copy', False, lambda p: duplicate(p, text))
        case('duplicate-owner-basename', False, lambda p: (p.parent.parent / config['filename']).write_text(text))
        if own_types:
            name = config['required_types'][0] if config['required_types'] else own_types[0]
            case('qualified-top-level-duplicate', False, lambda p: duplicate(p, 'struct ' + name + ' {}\n'))
            case('nested-name-is-not-global', True, lambda p: duplicate(p, 'struct UnrelatedScope { struct ' + name + ' {} }\n'))
            case('comment-string-not-declaration', True, lambda p: duplicate(p, '// struct ' + name + ' {}\nlet note = "struct ' + name + ' {}"\n'))
            case('drop-required-owner', False, lambda p: p.write_text('import Foundation\n'))
        else:
            require(bool(own_methods), 'extension guard requires signatures')
            owner, name, args = own_methods[0]
            params = ', '.join(label + ' value' + str(i) + ': ' + ' '.join(typ) for i, (label, typ) in enumerate(args))
            case('duplicate-extension-signature', False, lambda p: duplicate(p, 'extension ' + owner + ' { func ' + name + '(' + params + ') {} }\n'))
        case('drop-all-owner-declarations', False, lambda p: p.write_text('import Foundation\n'))
        return cases


def main(config):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-root', type=Path)
    args = parser.parse_args()
    root = args.check_root.resolve() if args.check_root else Path(__file__).resolve().parents[5]
    selected, text, types, methods = check_tree(root, config)
    cases = [] if args.check_root else mutation_suite(config, text, types, methods)
    print('PASS ' + config['id'] + ' owner=' + str(selected.relative_to(root)) + ' cases=' + str(len(cases)) + ' lexical-only; Swift/native/runtime NOT_RUN')
