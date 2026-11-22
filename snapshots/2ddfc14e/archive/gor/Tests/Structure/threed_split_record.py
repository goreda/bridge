#!/usr/bin/env python3
"""Records a product edit made to station files after the split, without touching the historical pins.
Usage: threed_split_record.py ROOT PRE_EDIT_ROOT
  ROOT is the tree whose Sources/gor/Stereo/*.swift carry the edit; PRE_EDIT_ROOT holds the pre-edit stations (the delivered split).
For each station whose live bytes differ from the pre-edit bytes it: stores the pre-edit file as Tests/Structure/threed-split-historical/<Station>.swift.<sha8>.txt
(refusing to overwrite a different fixture), writes historical_fixture/historical_sha256/current_sha256 for the station, scans BEGIN/END markers to write
current_lines and sha256_current for every section whose bytes changed, refuses any change outside the marker spans (header, new or removed sections)
unless it is a header import change, and writes manifest.current.sha256 (the rebuilt current text). It never edits original, sha256_before or sha256_after.
It then repins retirements.json station replacements to the live bytes. It prints what changed; run threed-split-helper-test.py afterwards."""
import hashlib,json,pathlib,re,shutil,sys
sh=lambda b:hashlib.sha256(b).hexdigest()
def main(root,pre):
    root,pre=pathlib.Path(root),pathlib.Path(pre)
    mp=root/'Tests/Structure/threed-split-manifest.json';m=json.loads(mp.read_text())
    pm=json.loads((pre/'Tests/Structure/threed-split-manifest.json').read_text())
    assert pm['original']==m['original'],'pre-edit manifest original differs'
    report=[]
    for s,st in m['stations'].items():
        live=(root/st['file']).read_bytes();old=(pre/st['file']).read_bytes()
        if 'historical_fixture' in st:  # already edited once: the pre-edit bytes of THIS record are the previous current bytes; the fixture stays the first historical
            assert sh(old)==st['current_sha256'],('pre-edit tree is not the pinned current bytes',s)
        if live==old: continue
        L=live.decode().split('\n')[:-1]
        # scan markers
        starts={};ends={};order=[]
        for i,l in enumerate(L):
            mm=re.match(r'^// BEGIN (?:relocated|station-move) (\S+\.swift)',l)
            if mm and mm.group(1) in {x['name'] for x in st['sections']}: starts[mm.group(1)]=i;order.append(mm.group(1))
            me=re.match(r'^// END (?:relocated|station-move) (\S+\.swift)$',l)
            if me and me.group(1) in {x['name'] for x in st['sections']}: ends[me.group(1)]=i
        assert order==[x['name'] for x in st['sections']],('section order or set changed',s)
        hl=st['header_lines'];pos=hl
        for x in st['sections']:
            assert starts[x['name']]==pos,('lines between sections or header grew',s,x['name']);pos=ends[x['name']]+1
        assert pos==len(L),('lines after the last section',s)
        if 'historical_fixture' not in st:
            fx=pathlib.Path('Tests/Structure/threed-split-historical')/f"{pathlib.Path(st['file']).name}.{sh(old)[:8]}.txt"
            (root/fx).parent.mkdir(parents=True,exist_ok=True)
            if (root/fx).exists(): assert (root/fx).read_bytes()==old,'fixture exists with other bytes'
            (root/fx).write_bytes(old)
            st['historical_fixture']=str(fx);st['historical_sha256']=sh(old)
            st['note']='Live file is not a pure move: product edit after the split. Historical rebuild uses the fixture, the live bytes are pinned separately.'
        st['current_sha256']=sh(live)
        for x in st['sections']:
            blk=L[starts[x['name']]:ends[x['name']]+1];b=('\n'.join(blk)+'\n').encode()
            if sh(b)==x['sha256_after']:
                x.pop('current_lines',None);x.pop('sha256_current',None)
            else:
                x['current_lines']=len(blk);x['sha256_current']=sh(b);report.append((s,x['name'],x['lines'],len(blk)))
    mp.write_text(json.dumps(m,indent=1))
    sys.path.insert(0,str(root/'Tests/Structure'))
    import importlib;ts=importlib.import_module('threed_split')
    m['current']={'sha256':'0'*64};mp.write_text(json.dumps(m,indent=1))
    try: ts.text(root)
    except AssertionError: pass
    # compute current text sha without the pin
    mm=json.loads(mp.read_text());got=ts._sections(root,mm,True);out=list(mm['header'])
    for n in mm['order']:
        sec,blk=got[n];out+=['']*sec['pre_blank_lines']+blk
    m['current']={'sha256':sh(('\n'.join(out)+'\n').encode())};mp.write_text(json.dumps(m,indent=1))
    hist=ts.declarations(ts.historical_text(root));cur=ts.declarations(ts.text(root))
    from collections import Counter
    ch,hh=Counter(map(tuple,cur)),Counter(map(tuple,hist))
    m['current'].update(declaration_count=len(cur),declaration_sha256=sh(json.dumps(cur).encode()),
        declarations_added=sorted(list(k) for k in (ch-hh).elements()),declarations_removed=sorted(list(k) for k in (hh-ch).elements()))
    mp.write_text(json.dumps(m,indent=1))
    print('declarations added:',m['current']['declarations_added'],'removed:',m['current']['declarations_removed'])
    # repin retirements
    rp=root/'Tests/Structure/retirements.json';j=json.loads(rp.read_text());n=0
    for e in j['entries']:
        for rel in list(e['replacements']):
            if rel.startswith('Sources/gor/Stereo/'):
                d=sh((root/rel).read_bytes())
                if e['replacements'][rel]!=d: e['replacements'][rel]=d;n+=1
    rp.write_text(json.dumps(j,indent=2)+'\n')
    print('edited sections:',report);print('retirement pins repinned:',n)
if __name__=='__main__': main(*sys.argv[1:3])
