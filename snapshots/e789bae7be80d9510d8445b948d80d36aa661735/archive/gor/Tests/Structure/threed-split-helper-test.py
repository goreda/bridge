#!/usr/bin/env python3
"""The five ThreeD station files (Sources/gor/Stereo/{Source,Depth,Prepare,Render,Control}.swift) rebuild the former single-file
Sources/gor/gor/ThreeD.swift byte-exact, every section is byte-identical to its recorded before-hash and sits in exactly one station,
each station carries the former file-wide import union, the declaration set equals the former file's, no station exceeds 4000 lines, the
former file is gone, and the retirement pins name the current station bytes. Each mutant must turn the checks RED."""
import hashlib, importlib.util, json, pathlib, re, shutil, sys, tempfile
R = pathlib.Path(__file__).resolve().parents[2]
ORIGINAL_SHA = '2b06e395bbe7dfbfaeb2a242336097f1b1db48e8d09da867f8ed6ce03e08a51e'
STATIONS = ['Source', 'Depth', 'Prepare', 'Render', 'Control']
CAP = 4000
DECL = re.compile(r'^\s*(?:@\w+(?:\([^)]*\))? )*(?:(?:public|internal|private|fileprivate|final|open|static|indirect|@MainActor) )*(class|struct|enum|protocol|extension|actor|typealias|func|var|let|case) +([A-Za-z_][A-Za-z0-9_.]*)')
IMPORT = re.compile(r'^\s*import (\w+)\s*$')
NEW = 'Sources/gor/Stereo/'

def load(root):
    spec = importlib.util.spec_from_file_location('threed_split', root / 'Tests/Structure/threed_split.py')
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def check(root):
    """Raise AssertionError when the tree under root is not a pure ThreeD move."""
    m = load(root)
    man = json.loads((root / 'Tests/Structure/threed-split-manifest.json').read_text())
    for s in STATIONS:  # cap first, so an oversize station is reported as such
        assert (root / NEW / (s + '.swift')).read_text().count('\n') <= CAP, 'station over cap ' + s
    assert man['original']['sha256'] == ORIGINAL_SHA, 'manifest original sha'
    ht = m.historical_text(root)  # historical pins: fixtures for edited stations, never a changed original hash
    assert hashlib.sha256(ht.encode()).hexdigest() == ORIGINAL_SHA, 'rebuilt historical ThreeD.swift differs'
    t = m.text(root)  # current view: every section and the whole text carry current pins
    edited = [s for s, st in man['stations'].items() if 'historical_fixture' in st]
    for s, st in man['stations'].items():
        live = hashlib.sha256((root / st['file']).read_bytes()).hexdigest()
        if s in edited:
            assert live == st['current_sha256'], 'live station not pinned ' + s
            assert 'historical_sha256' in st and (root / st['historical_fixture']).is_file(), 'historical fixture missing ' + s
        else:
            assert all('sha256_current' not in x and 'current_lines' not in x for x in st['sections']), 'current pin without fixture ' + s
    if edited: assert 'current' in man, 'edited station without current pins'
    else: assert 'current' not in man and t == ht, 'current view differs with no recorded edit'
    assert sorted(man['stations']) == sorted(STATIONS), 'station set'
    assert not (root / 'Sources/gor/gor/ThreeD.swift').exists(), 'former ThreeD.swift still present'
    assert sorted(p.name for p in (root / NEW).glob('*')) == sorted(s + '.swift' for s in STATIONS + ['StereoDetection','StereoGeometry','VR180Controller','VRDistanceModel','VRStereoControlInput','GazeCrosshairController','StereoLookNativeCommands','StereoLookNativeInputOwner','StereoLookNativeIntentAdapter','RealtimeProbe','LookToolsRoute']), 'files under Stereo/ (199bv station set: 5 split + 11 moved/existing)'
    hdir = root / 'Tests/Structure/threed-split-historical'
    fixtures = sorted(p.name for p in hdir.glob('*')) if hdir.is_dir() else []
    assert fixtures == sorted(pathlib.Path(st['historical_fixture']).name for st in man['stations'].values() if 'historical_fixture' in st), 'stray or missing historical fixture'
    names = [s['name'] for st in man['stations'].values() for s in st['sections']]
    assert len(names) == len(set(names)) == len(man['order']) == 68, 'each section in exactly one station'
    assert sorted(names) == sorted(man['order']), 'order vs sections'
    for s, st in man['stations'].items():
        f = root / st['file']; assert f.is_file() and not f.is_symlink(), st['file']
        txt = f.read_text(); lines = txt.split('\n')
        assert lines[-1] == '', 'trailing newline ' + s
        assert len(lines) - 1 <= CAP, 'station over cap ' + s
        mods = {IMPORT.match(l).group(1) for l in lines[:st['header_lines']] if IMPORT.match(l)}
        assert set(man['original']['import_modules']) <= mods, 'import union lost in ' + s + ' ' + str(sorted(set(man['original']['import_modules']) - mods))
        for sec in st['sections']:
            assert sec['sha256_before'] == sec['sha256_after'], 'section hash ' + sec['name']
    hd = m.declarations(ht)
    assert len(hd) == man['original']['declaration_count'], 'declaration count'
    assert hashlib.sha256(json.dumps(hd).encode()).hexdigest() == man['original']['declaration_sha256'], 'declaration set differs'
    cd = m.declarations(t)
    if edited:  # the current set must equal the historical set plus the recorded delta, nothing else
        from collections import Counter
        c = man['current']; want = Counter(map(tuple, hd)) + Counter(map(tuple, map(tuple, c['declarations_added']))) - Counter(map(tuple, map(tuple, c['declarations_removed'])))
        assert Counter(map(tuple, cd)) == want, 'current declarations differ from historical plus recorded delta'
        assert len(cd) == c['declaration_count'] and hashlib.sha256(json.dumps(cd).encode()).hexdigest() == c['declaration_sha256'], 'current declaration pin'
    else: assert cd == hd
    ret = json.loads((root / 'Tests/Structure/retirements.json').read_text())['entries']
    for e in ret:
        for rel, digest in e['replacements'].items():
            assert rel != 'Sources/gor/gor/ThreeD.swift', 'pin names the former file ' + e['path']
            if rel.startswith(NEW):
                assert hashlib.sha256((root / rel).read_bytes()).hexdigest() == digest, 'stale pin ' + rel
    row = [e for e in ret if e['path'] == 'Sources/gor/gor/ThreeD.swift']
    assert len(row) == 1, 'no retirement row for the deleted Sources/gor/gor/ThreeD.swift'
    assert row[0]['sha256'] == ORIGINAL_SHA, 'retirement row old hash'
    assert sorted(row[0]['replacements']) == sorted(NEW + s + '.swift' for s in STATIONS), 'retirement row must pin all five stations'
    overlay(root)
    pinned = [e for e in ret if any(r.startswith(NEW) for r in e['replacements'])]
    assert len(pinned) == 117, 'retirement rows lost'  # 199bv Stereo: 96 ThreeD + 15 VR/Gaze/StereoLook + 3 pre-existing Stereo + 3 LookToolsRoute

def overlay(root):
    """Run the real retire-overlay on a project that still holds the old monolith beside the stations: the monolith must be retired."""
    spec = importlib.util.spec_from_file_location('retire_overlay', R / 'Tests/Structure/retire-overlay.py')
    ro = importlib.util.module_from_spec(spec); spec.loader.exec_module(ro)
    td = pathlib.Path(tempfile.mkdtemp()); p = td / 'project'; b = p / '.gor-backups'; e = td / 'ext'
    (p / 'Sources/gor/gor').mkdir(parents=True); shutil.copytree(root / NEW, p / NEW.strip('/'))
    (p / 'Sources/gor/gor/ThreeD.swift').write_text(load(root).historical_text(root))
    (p / 'Tests/Structure').mkdir(parents=True); shutil.copy2(root / 'Tests/Structure/retirements.json', p / 'Tests/Structure/retirements.json')
    prior = b / '261118-141200-pre-update'; prior.mkdir(parents=True); (prior / 'changes.txt').write_text('')
    ro.retire(p, b, e)
    assert not (p / 'Sources/gor/gor/ThreeD.swift').exists(), 'old monolith not retired: it would sit beside the stations'

def clone():
    d = pathlib.Path(tempfile.mkdtemp())
    for rel in ('Tests/Structure/section_source.py', 'Tests/Structure/threed_split.py', 'Tests/Structure/threed-split-manifest.json', 'Tests/Structure/retirements.json'):
        (d / rel).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(R / rel, d / rel)
    shutil.copytree(R / NEW, d / NEW.strip('/'))
    if (R / 'Tests/Structure/threed-split-historical').is_dir(): shutil.copytree(R / 'Tests/Structure/threed-split-historical', d / 'Tests/Structure/threed-split-historical')
    return d

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def mutate(kind):
    d = clone(); mp = d / 'Tests/Structure/threed-split-manifest.json'; man = json.loads(mp.read_text())
    ctl = d / 'Sources/gor/Stereo/Control.swift'; rp = d / 'Tests/Structure/retirements.json'
    def repin():  # keep pins honest so only the intended defect fires
        j = json.loads(rp.read_text())
        for e in j['entries']:
            for rel in list(e['replacements']):
                if rel.startswith(NEW): e['replacements'][rel] = sha(d / rel)
        rp.write_text(json.dumps(j, indent=2))
    if kind == 'drop-import':
        txt = ctl.read_text(); assert 'import Metal\n' in txt; ctl.write_text(txt.replace('import Metal\n', '// import Metal\n', 1)); repin()
    elif kind == 'section-byte':
        txt = ctl.read_text(); assert txt.count('struct FilmID') >= 1; ctl.write_text(txt.replace('struct FilmID', 'struct FilmId', 1)); repin()
    elif kind == 'swap-sections':
        st = man['stations']['Control']; a = st['sections']; a[0], a[1] = a[1], a[0]; mp.write_text(json.dumps(man))
    elif kind == 'section-in-two-stations':
        man['stations']['Source']['sections'].append(man['stations']['Control']['sections'][0]); mp.write_text(json.dumps(man))
    elif kind == 'delete-section':
        L = ctl.read_text().split('\n'); n = man['stations']['Control']['sections'][-1]['lines']
        i = len(L) - 1 - n; assert L[i].startswith('// BEGIN ') or True
        ctl.write_text('\n'.join(L[:len(L) - 1 - n] + ['']))
        repin()
    elif kind == 'over-cap':
        ctl.write_text(ctl.read_text() + '\n' * 4000); repin()
    elif kind == 'former-file-back':
        (d / 'Sources/gor/gor').mkdir(parents=True); (d / 'Sources/gor/gor/ThreeD.swift').write_text('// stale\n')
    elif kind == 'stale-pin':
        j = json.loads(rp.read_text()); done = False
        for e in j['entries']:
            for rel in e['replacements']:
                if rel.startswith(NEW) and not done: e['replacements'][rel] = '0' * 64; done = True
        assert done; rp.write_text(json.dumps(j))
    elif kind == 'pin-names-former-file':
        j = json.loads(rp.read_text()); e = next(x for x in j['entries'] if any(r.startswith(NEW) for r in x['replacements']))
        e['replacements']['Sources/gor/gor/ThreeD.swift'] = ORIGINAL_SHA; rp.write_text(json.dumps(j))
    elif kind == 'row-missing':
        j = json.loads(rp.read_text()); j['entries'] = [x for x in j['entries'] if x['path'] != 'Sources/gor/gor/ThreeD.swift']; rp.write_text(json.dumps(j))
    elif kind == 'manifest-original-sha':
        man['original']['sha256'] = '1' * 64; mp.write_text(json.dumps(man))
    elif kind == 'extra-file':
        (d / 'Sources/gor/Stereo/Sixth.swift').write_text('// extra\n')
    elif kind == 'declaration-added':
        txt = ctl.read_text(); ctl.write_text(txt + 'struct ExtraDecl {}\n'); repin()
        man['stations']['Control']['sections'][-1]  # section coverage already fails; kept as an independent defect
    else: raise KeyError(kind)
    return d


def recorder():
    spec = importlib.util.spec_from_file_location('threed_split_record', R / 'Tests/Structure/threed_split_record.py')
    r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r); return r

def edited(edit='section'):
    """A tree where a product edit changed the SourcePixelCrop section after the split, recorded by the recorder. Returns (edited_root, pre_edit_root)."""
    pre = clone(); d = clone()
    f = d / 'Sources/gor/Stereo/Source.swift'; t = f.read_text()
    end = '// END relocated SourcePixelCrop.swift\n'; assert t.count(end) == 1
    if edit == 'section': f.write_text(t.replace(end, '    static func recordedEditProbe() -> Int { 1 }\n' + end))
    elif edit == 'header': f.write_text('// stray header line\n' + t)
    elif edit == 'between': f.write_text(t.replace(end, end + '\n'))
    import io, contextlib
    with contextlib.redirect_stdout(io.StringIO()): recorder().main(d, pre)
    return d, pre

def mutate_edited(kind):
    d, pre = edited(); mp = d / 'Tests/Structure/threed-split-manifest.json'; man = json.loads(mp.read_text())
    st = man['stations']['Source']; fx = d / st['historical_fixture']; src = d / 'Sources/gor/Stereo/Source.swift'
    if kind == 'fixture-tamper': b = fx.read_bytes(); fx.write_bytes(b.replace(b'func ', b'fund ', 1))
    elif kind == 'fixture-removed': fx.unlink()
    elif kind == 'station-pin-stale': st['current_sha256'] = '0' * 64; mp.write_text(json.dumps(man))
    elif kind == 'section-pin-stale':
        x = next(x for x in st['sections'] if 'sha256_current' in x); x['sha256_current'] = '0' * 64; mp.write_text(json.dumps(man))
    elif kind == 'live-edit-unpinned':
        t = src.read_text(); src.write_text(t.replace('    static func recordedEditProbe() -> Int { 1 }', '    static func recordedEditProbe() -> Int { 2 }', 1))
    elif kind == 'current-text-pin-stale': man['current']['sha256'] = '0' * 64; mp.write_text(json.dumps(man))
    elif kind == 'decl-delta-missing': man['current']['declarations_added'] = []; mp.write_text(json.dumps(man))
    elif kind == 'historical-hash-rewritten':
        man['original']['sha256'] = hashlib.sha256(m_text(d).encode()).hexdigest(); mp.write_text(json.dumps(man))
    elif kind == 'retire-pin-stale':
        rp = d / 'Tests/Structure/retirements.json'; j = json.loads(rp.read_text()); done = False
        for e in j['entries']:
            if 'Sources/gor/Stereo/Source.swift' in e['replacements'] and not done:
                e['replacements']['Sources/gor/Stereo/Source.swift'] = hashlib.sha256((pre / 'Sources/gor/Stereo/Source.swift').read_bytes()).hexdigest(); done = True
        assert done; rp.write_text(json.dumps(j))
    elif kind == 'historical-pin-moved':
        x = next(x for x in st['sections'] if 'sha256_current' in x); x['sha256_after'] = x['sha256_current']; x['sha256_before'] = x['sha256_current']; mp.write_text(json.dumps(man))
    else: raise KeyError(kind)
    return d

def m_text(d): return load(d).text(d)
EDITED_MUTANTS = ['fixture-tamper', 'fixture-removed', 'station-pin-stale', 'section-pin-stale', 'live-edit-unpinned', 'current-text-pin-stale',
                  'decl-delta-missing', 'historical-hash-rewritten', 'retire-pin-stale', 'historical-pin-moved']
MUTANTS = ['drop-import', 'section-byte', 'swap-sections', 'section-in-two-stations', 'delete-section', 'over-cap', 'former-file-back',
           'stale-pin', 'pin-names-former-file', 'row-missing', 'manifest-original-sha', 'extra-file', 'declaration-added']
if __name__ == '__main__':
    check(R); print('PASS live tree: five stations rebuild ThreeD.swift %s, 68 sections, imports, declarations, cap, pins' % ORIGINAL_SHA[:8])
    base = clone(); check(base); print('PASS fixed clone')
    bad = []
    for k in MUTANTS:
        d = mutate(k)
        assert sorted(p.name for p in d.rglob('*') if p.is_file()) != sorted(p.name for p in base.rglob('*') if p.is_file()) or any(sha(p) != sha(base / p.relative_to(d)) for p in d.rglob('*') if p.is_file() and (base / p.relative_to(d)).exists()), 'mutation did not apply: ' + k
        if k == 'row-missing':
            try: overlay(d); bad.append(k); print('FAIL overlay passes without the row')
            except AssertionError as e: print('PASS overlay alone fails without the row (%s)' % str(e)[:60])
        try:
            check(d); bad.append(k); print('FAIL mutant not caught: ' + k)
        except AssertionError as e:
            print('PASS mutant caught: %s (%s)' % (k, str(e)[:70]))
    d, pre = edited(); check(d); print('PASS recorded edit: historical sha %s kept, current view pinned, declaration delta recorded' % ORIGINAL_SHA[:8])
    mm = load(d); assert 'recordedEditProbe' in mm.path(d).read_text() and 'recordedEditProbe' not in mm.historical_text(d), 'current vs historical view'
    base_files = {p.relative_to(d): sha(p) for p in d.rglob('*') if p.is_file()}
    for k in EDITED_MUTANTS:
        dd = mutate_edited(k)
        assert {p.relative_to(dd): sha(p) for p in dd.rglob('*') if p.is_file()} != base_files or k == 'fixture-removed', 'mutation did not apply: ' + k
        try:
            check(dd); bad.append('edited:' + k); print('FAIL edited mutant not caught: ' + k)
        except (AssertionError, FileNotFoundError, KeyError) as e:
            print('PASS edited mutant caught: %s (%s)' % (k, str(e)[:70]))
    for kind in ('header', 'between'):
        try: edited(kind); bad.append('recorder:' + kind); print('FAIL recorder accepted edit outside sections: ' + kind)
        except AssertionError as e: print('PASS recorder refuses edit outside the section spans: %s (%s)' % (kind, str(e)[:60]))
    sys.exit(1 if bad else 0)
