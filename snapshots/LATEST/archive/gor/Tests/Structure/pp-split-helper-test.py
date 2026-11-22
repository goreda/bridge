#!/usr/bin/env python3
"""The split PPController files rebuild the former PPController.swift and PPController_Features.swift byte-exact,
every split file carries the former file-wide import union, every former top-level declaration exists exactly once,
and the retirement pins name the current part bytes. Each mutant must turn the checks RED."""
import hashlib, importlib.util, json, pathlib, re, shutil, sys, tempfile
R = pathlib.Path(__file__).resolve().parents[2]
ORIGINAL = {'PPController.swift': 'c0c02953aa3fa870afcc6a27358323b6e46bb492689f4d424437039fbdc12b71',
            'PPController_Features.swift': 'ef8fc46feeb8bff1ae6b18bdd058c3a210fc028550f61ebf04feb0fd0b21e683'}
G = 'Sources/gor/gor/'
IMPORT = re.compile(r'^(@\w+ )?import ')
DECL = re.compile(r'^(?:@\w+ )*(?:(?:public|internal|private|fileprivate|final|open) )*(class|struct|enum|protocol|extension|actor|typealias) +([A-Za-z_][A-Za-z0-9_.]*)')

def load(root):
    spec = importlib.util.spec_from_file_location('pp_split', root / 'Tests/Structure/pp_split.py')
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def check(root):
    """Raise AssertionError when the split tree under root is not a pure move."""
    m = load(root)
    man = json.loads((root / 'Tests/Structure/pp-split-manifest.json').read_text())['files']
    assert sorted(man) == sorted(ORIGINAL), 'manifest files'
    seen = {}
    for name, want in ORIGINAL.items():
        t = m.text(root, name)
        assert hashlib.sha256(t.encode()).hexdigest() == want, 'rebuilt ' + name + ' differs'
        assert man[name]['sha256'] == want, 'manifest sha ' + name
        union = {l for l in t.split('\n') if IMPORT.match(l)}
        decls = sorted(DECL.match(l).groups() for l in t.split('\n') if DECL.match(l))
        got = []
        for p in man[name]['parts']:
            f = m.part_host(root,p['file'])
            assert f.is_file() and not f.is_symlink(), p['file']
            assert p['file'] not in seen, 'part listed twice ' + p['file']
            seen[p['file']] = name
            current = m.part_text(root,p['file'])
            lines = current.split('\n')
            assert lines[-1] == '', 'no trailing newline ' + p['file']
            if 'historical_fixture' in p:
                assert hashlib.sha256(current.encode()).hexdigest() == p['current_sha256'], 'stale current pin ' + p['file']
            fu = {l for l in lines if IMPORT.match(l)}
            assert union <= fu, 'import union lost in ' + p['file'] + ' ' + str(sorted(union - fu))
            got += [DECL.match(l).groups() for l in lines if DECL.match(l)]
        assert sorted(got) == decls, 'declaration set differs for ' + name
    assert not (root / G / 'PPController_Features.swift').exists(), 'stale Features file'
    for part in seen:
        carrier=m.part_host(root,part)
        assert carrier.is_file() and not carrier.is_symlink(),part
    ret = json.loads((root / 'Tests/Structure/retirements.json').read_text())['entries']
    pins = {e['path']: e['replacements'] for e in ret}
    for src, name in (('Sources/gor/PPController.swift', 'PPController.swift'), ('Sources/gor/PPController_Features.swift', 'PPController_Features.swift')):
        want=set()
        for part in man[name]['parts']:
            host=m.part_host(root,part['file'])
            key=str(host.relative_to(root))
            # Core and Display pin complete hosts, including their lifted import unions.
            if host!=root/G/part['file'] and part['file'] not in {'GeomTrace.swift','SeededRandomNumberGenerator.swift','BrightnessController.swift','BrightnessReadCache.swift','ContentAdaptiveDimming.swift'}:key+='#'+part['file']
            want.add(key)
        assert set(pins[src]) == want, 'retirement set ' + src
    for e in ret:
        for rel, digest in e['replacements'].items():
            assert hashlib.sha256(m.source_sections(root).pinned_bytes(root,rel)).hexdigest() == digest, 'stale pin ' + rel

def clone():
    d = pathlib.Path(tempfile.mkdtemp())
    for rel in ('Tests/Structure/section_source.py', 'Tests/Structure/pp_split.py', 'Tests/Structure/core_source.py', 'Tests/Structure/199u-core-map.json', 'Tests/Structure/pp-split-manifest.json', 'Tests/Structure/retirements.json'):
        (d / rel).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(R / rel, d / rel)
    (d / G).mkdir(parents=True)
    for p in (R / G).glob('*.swift'): shutil.copy2(p, d / G / p.name)
    shutil.copytree(R / 'Tests/Structure/pp-split-historical', d / 'Tests/Structure/pp-split-historical')
    for e in json.loads((R / 'Tests/Structure/retirements.json').read_text())['entries']:
        for reference in e['replacements']:
            rel=reference.partition('#')[0]
            (d / rel).parent.mkdir(parents=True, exist_ok=True)
            if not (d / rel).exists(): shutil.copy2(R / rel, d / rel)
    return d

def edit_part(root,name,transform):
    module=load(root);sections=module.source_sections(root);host=module.part_host(root,name)
    before=sections.section_text_exact(root,name);after=transform(before)
    assert before!=after,('mutation did not change part',name)
    content=host.read_text()
    assert content.count(before)==1,('part edit is ambiguous',name)
    host.write_text(content.replace(before,after,1))

def mutate(kind):
    d = clone(); man_p = d / 'Tests/Structure/pp-split-manifest.json'; man = json.loads(man_p.read_text())
    ps = man['files']['PPController.swift']['parts']; fs = man['files']['PPController_Features.swift']['parts']
    if kind == 'byte-flip':
        edit_part(d,ps[1]['file'],lambda text:text.replace('func ','fund ',1))
    elif kind == 'header-lines':
        ps[1]['header_lines'] += 1; man_p.write_text(json.dumps(man))
    elif kind == 'drop-part':
        fs.pop(); man_p.write_text(json.dumps(man))
    elif kind == 'import-drop':
        f = load(d).part_host(d,fs[0]['file']); t = f.read_text(); n = t.replace('import IOKit\n', '', 1); assert n != t; f.write_text(n)
    elif kind == 'duplicate-type':
        declaration=load(d).part_text(d,ps[1]['file']).split('\n')[ps[1]['header_lines']]
        edit_part(d,ps[1]['file'],lambda text:text+declaration+'\n')
    elif kind == 'stale-features':
        (d / G / 'PPController_Features.swift').write_text(load(d).part_text(d,ps[0]['file']))
    elif kind == 'stale-pin':
        j = json.loads((d / 'Tests/Structure/retirements.json').read_text())
        e = next(x for x in j['entries'] if x['path'] == 'Sources/gor/PPController.swift')
        k = next(iter(e['replacements'])); e['replacements'][k] = '0' * 64
        (d / 'Tests/Structure/retirements.json').write_text(json.dumps(j))
    elif kind == 'old-pin-set':
        j = json.loads((d / 'Tests/Structure/retirements.json').read_text())
        e = next(x for x in j['entries'] if x['path'] == 'Sources/gor/PPController_Features.swift')
        e['replacements'] = {G + 'PPController_Features.swift': ORIGINAL['PPController_Features.swift']}
        (d / 'Tests/Structure/retirements.json').write_text(json.dumps(j))
    elif kind == 'fixture-tamper':
        f = d / 'Tests/Structure/pp-split-historical/InputController.swift.ea5cd9d8.txt'; b = f.read_bytes(); n = b.replace(b'func ', b'fund ', 1); assert n != b; f.write_bytes(n)
    elif kind == 'fixture-removed':
        (d / 'Tests/Structure/pp-split-historical/InputController.swift.ea5cd9d8.txt').unlink()
    elif kind == 'current-pin-stale':
        for e in man['files'].values():
            for p in e['parts']:
                if 'current_sha256' in p: p['current_sha256'] = '0' * 64
        man_p.write_text(json.dumps(man))
    elif kind == 'live-edit-unpinned':
        f = load(d).part_host(d,'InputController.swift'); text=f.read_text()
        needle='final class InputController {';assert text.count(needle)==1
        f.write_text(text.replace(needle,needle+'\n// unrecorded current edit',1))
    return d

check(R)
KINDS = ['byte-flip', 'header-lines', 'drop-part', 'import-drop', 'duplicate-type', 'stale-features', 'stale-pin', 'old-pin-set', 'fixture-tamper', 'fixture-removed', 'current-pin-stale', 'live-edit-unpinned']
for k in KINDS:
    d = mutate(k)
    try:
        check(d)
    except (AssertionError, KeyError, ValueError, FileNotFoundError, IndexError, StopIteration):
        pass
    else:
        raise AssertionError('mutant accepted: ' + k)
    finally:
        shutil.rmtree(d, ignore_errors=True)
print('PASS pp split: 2 former files rebuild byte-exact from %d parts; import union, declaration set and retirement pins hold; %d mutants RED' % (sum(len(e['parts']) for e in json.loads((R / 'Tests/Structure/pp-split-manifest.json').read_text())['files'].values()), len(KINDS)))
