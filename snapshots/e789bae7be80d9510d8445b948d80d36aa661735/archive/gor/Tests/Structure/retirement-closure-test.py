#!/usr/bin/env python3
"""Validate every replacement pin even when the clean checkout has no old roots."""
from pathlib import Path
import hashlib, importlib.util, json, shutil, tempfile
R=Path(__file__).resolve().parents[2]
D=R/'Tests/Structure'
j=json.loads((D/'retirements.json').read_text())
spec_ss=importlib.util.spec_from_file_location('section_source',D/'section_source.py')
ss=importlib.util.module_from_spec(spec_ss);spec_ss.loader.exec_module(ss)
count=0
for row in j['entries']:
    for relative,expected in row['replacements'].items():
        if '#' in relative:
            # arch-199u: re-moved unit pins its MARK section bytes in the station file.
            assert hashlib.sha256(ss.pinned_bytes(R,relative)).hexdigest()==expected,relative
        else:
            p=R/relative
            assert p.is_file() and not p.is_symlink(),relative
            assert hashlib.sha256(p.read_bytes()).hexdigest()==expected,relative
        count+=1
spec=importlib.util.spec_from_file_location('retirement',D/'retire-overlay.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
old=json.loads((D/'overlay-old-sources.json').read_text())
row=next(x for x in j['entries'] if x['path']=='Sources/gor/GorAVPlayerHost.swift')
replacement=next(iter(row['replacements']))
with tempfile.TemporaryDirectory() as td:
    root=Path(td);p=root/'project';b=p/'.gor-backups';e=root/'gor-bbu'
    for relative,text in [(row['path'],old[row['path']])]:
        q=p/relative;q.parent.mkdir(parents=True,exist_ok=True);q.write_text(text)
    if '#' in replacement:
        # arch-199u: a section pin is a symbolic reference (host#Unit.swift), not a
        # file path. Materialize the MARK section in a minimal station file plus
        # the resolver the retirement flow needs.
        host,_,unit=replacement.partition('#')
        hp=p/host;hp.parent.mkdir(parents=True,exist_ok=True)
        hp.write_text('// MARK: - '+unit+'\n'+ss.section_text(R,unit))
        ssp=p/'Tests/Structure/section_source.py';ssp.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(D/'section_source.py',ssp)
    else:
        q=p/replacement;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/replacement,q)
    inventory=p/'Tests/Structure/retirements.json';inventory.parent.mkdir(parents=True,exist_ok=True)
    prior=b/'261118-141200-pre-update';prior.mkdir(parents=True);(prior/'changes.txt').write_text('')
    stale=json.loads(json.dumps(row));stale['replacements'][replacement]='9a99f0d13f4b3f17cef456aab70243477661bab9a7be4435f1995e14b7a95208'
    inventory.write_text(json.dumps({'schema':1,'entries':[stale]}))
    try:
        m.retire(p,b,e)
        raise AssertionError('D1 stale replacement pin unexpectedly accepted')
    except RuntimeError as error:
        assert 'replacement mismatch' in str(error)
    assert (p/row['path']).is_file() and not e.exists()
    inventory.write_text(json.dumps({'schema':1,'entries':[row]}))
    backup=m.retire(p,b,e)
    assert not (p/row['path']).exists()
    assert (backup/row['path']).read_text()==old[row['path']]
    shutil.copy2(backup/row['path'],p/row['path'])
    assert (p/row['path']).read_text()==old[row['path']]
print('PASS retirement closure: %d replacement references; owner D1 stale-host failure reproduced; exact current replacement accepted; rollback restores original' % count)
