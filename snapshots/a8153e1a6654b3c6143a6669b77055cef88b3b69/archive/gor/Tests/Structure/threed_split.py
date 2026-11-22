"""Reads the split ThreeD station files (arch-199s).
historical_text(root) rebuilds the former single-file Sources/gor/gor/ThreeD.swift byte-exactly (sha256 pinned in the manifest) from the five
station files, using a pinned pre-edit fixture for any station that a later product edit changed.
text(root) rebuilds the CURRENT view the same way from the live station bytes: every section carries a pinned current hash, and the
whole current text has its own pinned sha256. path(root) writes the current text to a cache file and returns its Path, so callers keep using
read_text(). span(root,name) returns the current BEGIN-line..END-line slice of one top-level section.
Manifest: stations[S].historical_fixture/historical_sha256/current_sha256 exist only for a station edited after the split; a section edited
after the split carries current_lines and sha256_current next to its unchanged lines/sha256_before/sha256_after (the historical pins).
Falls back to the plain former path when the station files are absent (an older tree)."""
import json,pathlib,hashlib,tempfile,re,importlib.util

def station_text(root,relative):
    """Exact complete logical station, including its recorded header and imports.
    BEGIN/END structure and every historical/current hash remain authoritative.
    Header cleanup is a separate recorded rebaseline, never inferred here.
    """
    root=pathlib.Path(root)
    spec=importlib.util.spec_from_file_location('threed_station_sections',pathlib.Path(__file__).with_name('section_source.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module.section_text_exact(root,pathlib.Path(relative).name)
DECL=re.compile(r'^\s*(?:@\w+(?:\([^)]*\))? )*(?:(?:public|internal|private|fileprivate|final|open|static|indirect|@MainActor) )*(class|struct|enum|protocol|extension|actor|typealias|func|var|let|case) +([A-Za-z_][A-Za-z0-9_.]*)')
def declarations(txt):
    return sorted(m.groups() for m in map(DECL.match,txt.split('\n')) if m)
def _m(root):
    return json.loads((pathlib.Path(root)/'Tests/Structure/threed-split-manifest.json').read_text())
def _sections(root,m,current):
    root=pathlib.Path(root);got={}
    for sname,st in m['stations'].items():
        if 'historical_fixture' in st and not current:
            src=root/st['historical_fixture']
            assert hashlib.sha256(src.read_bytes()).hexdigest()==st['historical_sha256'],('historical fixture',sname)
            content=src.read_text()
        else:
            content=station_text(root,st['file'])
            if 'historical_fixture' in st:
                assert hashlib.sha256(content.encode()).hexdigest()==st['current_sha256'],('live station is not the pinned current bytes',sname)
        L=content.split('\n')[:-1];p=st['header_lines']
        for s in st['sections']:
            n=s['current_lines'] if current and 'current_lines' in s else s['lines']
            want=s['sha256_current'] if current and 'sha256_current' in s else s['sha256_after']
            blk=L[p:p+n];p+=n
            assert len(blk)==n,(sname,s['name'],'section runs past the station file')
            assert blk[0].startswith('// BEGIN ') and blk[-1].startswith('// END '),(sname,s['name'])
            b='\n'.join(blk)+'\n'
            assert hashlib.sha256(b.encode()).hexdigest()==want,('section bytes changed',s['name'])
            got[s['name']]=(s,blk)
        assert p==len(L),(sname,'lines outside the recorded sections')
    return got
def _build(root,current):
    m=_m(root);got=_sections(root,m,current);out=list(m['header'])
    assert sorted(got)==sorted(m['order']),'section set differs'
    for n in m['order']:
        s,blk=got[n];out+=['']*s['pre_blank_lines']+blk
    t='\n'.join(out)+'\n'
    want=m['current']['sha256'] if current and 'current' in m else m['original']['sha256']
    assert hashlib.sha256(t.encode()).hexdigest()==want,('rebuilt current text differs from its pin' if current else 'rebuilt ThreeD.swift differs from the pinned original')
    return t
def historical_text(root): return _build(root,False)
def text(root): return _build(root,True)
def span(root,name):
    s,blk=_sections(root,_m(root),True)[name]
    return '\n'.join(blk[:-1])+'\n'
def path(root):
    root=pathlib.Path(root)
    if not (root/'Tests/Structure/threed-split-manifest.json').exists():
        return root/'Sources/gor/gor/ThreeD.swift'
    t=text(root)
    d=pathlib.Path(tempfile.gettempdir())/('threed_split_'+hashlib.sha256(t.encode()).hexdigest()[:16])/'Sources/gor/gor'
    d.mkdir(parents=True,exist_ok=True)
    f=d/'ThreeD.swift'
    if not f.exists() or f.read_text()!=t: f.write_text(t)
    return f
