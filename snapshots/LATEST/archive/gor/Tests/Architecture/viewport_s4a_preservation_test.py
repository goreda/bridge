#!/usr/bin/env python3
"""S4a strict placement evidence. Product bytes, not equivalent rewritten logic.

Default mode: full-product integration (uses git, unchanged assertions).
`--fixture` mode: portable byte-preservation check on embedded sanitized
excerpts (fixture source pin 8f025463a48f3e01b0fff950fb70fe5a847751a7).
The fixture mode does not verify the full product move.
"""
from pathlib import Path
import json,subprocess,hashlib,sys

def sha(text):return hashlib.sha256(text.encode()).hexdigest()

def check_current(hist,live,mv,where,pin='current_sha256',ekey='edit'):
 """Historical/current rule. hist is the byte-exact pure-move result; live is the file in the tree.
 An unedited move needs live==hist and current_sha256==sha(hist). An edited move must carry a recorded edit:
 hunks (line spans of hist, line spans of live, sha of the live replacement text). Every line outside the hunks
 must equal hist, each replacement must hash to its pin, each hunk must really change its span, and the live
 file must hash to current_sha256. Historical pins are never read or relaxed here."""
 assert mv.get(pin),where+': '+pin+' missing'
 assert sha(live)==mv[pin],where+': live bytes differ from the current pin'
 edit=mv.get(ekey)
 if edit is None:
  assert live==hist,where+': unrecorded edit (live differs from the pure move, no recorded edit)'
  return
 hunks=edit.get('hunks');assert hunks,where+': edit recorded without hunks'
 assert live!=hist,where+': edit recorded but live file is the pure move'
 hl=hist.splitlines(True);ll=live.splitlines(True);i=j=0
 for h in hunks:
  (oa,ob),(na,nb)=h['old'],h['new']
  assert i<=oa<=ob<=len(hl) and j<=na<=nb<=len(ll),where+': hunk span order'
  assert hl[i:oa]==ll[j:na],where+': bytes changed outside the recorded edit'
  seg=''.join(ll[na:nb]);assert sha(seg)==h['new_sha256'],where+': replacement bytes differ from the recorded edit'
  assert ''.join(hl[oa:ob])!=seg,where+': hunk changes nothing'
  i,j=ob,nb
 assert hl[i:]==ll[j:],where+': bytes changed after the last recorded edit'

def check_split(old,current,new,prefix,start,end,rstart,rend,sha256,where,mv=None):
 """Shared strict check. No newline normalization, trimming or semantic compare."""
 a=old.index(start);b=old.index(end,a);body=old[a:b]
 if mv is None:assert new==prefix+body,where+': moved bytes'
 else:check_current(prefix+body,new,mv,where)
 ra=old.index(rstart);rb=old.index(rend,ra)
 if mv is not None and 'residual_current_sha256' in mv:check_current(old[:ra]+old[rb:],current,mv,where+' residual','residual_current_sha256','residual_edit')
 else:assert current==old[:ra]+old[rb:],where+': residual'
 assert hashlib.sha256(body.encode()).hexdigest()==sha256,where+': body hash'
 return body

import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
def base_text(r,spec,m):
 """Historical bytes of the moved file at spec['base'], pinned by base_blob_sha256. Read from git; S4A_BLOB_DIR may
 supply the same blob as <dir>/<old file name> when no history is present. The pin is checked either way."""
 import os
 rel='archive/gor/Sources/gor/'+m['old'];d=os.environ.get('S4A_BLOB_DIR')
 if d:text=(Path(d)/m['old']).read_text()
 else:text=subprocess.check_output(['git','-C',str(r),'show',spec['base']+':'+rel],text=True)
 assert m.get('base_blob_sha256'),m['old']+': base_blob_sha256 missing'
 assert sha(text)==m['base_blob_sha256'],m['old']+': base blob does not match its pin'
 return text

def integration():
 r=Path(__file__).resolve().parents[2];spec=json.loads((r/'Tests/Architecture/viewport-s4a-map.json').read_text());s=r/'Sources/gor'
 for m in spec['moves']:
  old=base_text(r,spec,m)
  new=(s/m['new']).read_text()
  if 'start' in m:
   current=(_pp_split().path(r,'PPController.swift') if m['old']=='PPController.swift' else s/m['old']).read_text()
   check_split(old,current,new,m['prefix'],m['start'],m['end'],m['residual_start'],m['residual_end'],m['sha256'],m['new'],m)
  else:
   body=old;check_current(old,new,m,m['new']);assert not (s/m['old']).exists()
   assert hashlib.sha256(body.encode()).hexdigest()==m['sha256']
 print('PASS S4a exact source bytes preserved, old residual byte-identical')

BASE = '// sanitized base fixture\nstruct GorFitSize: Equatable {\n    var w: Double\n    var h: Double\n}\n\nstruct GorFitRect: Equatable {\n    var x: Double\n    var y: Double\n    var w: Double\n    var h: Double\n}\n\n// BEGIN MOVE\n    func currentMainPlayback() -> Int? {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive ? mainPlaybackGeneration : nil\n    }\n    func isMainPlaybackCurrent(_ generation: Int) -> Bool {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive && mainPlaybackGeneration == generation\n    }\n// END MOVE\n// residual sentinel\n'
POST = '// sanitized base fixture\nstruct GorFitSize: Equatable {\n    var w: Double\n    var h: Double\n}\n\nstruct GorFitRect: Equatable {\n    var x: Double\n    var y: Double\n    var w: Double\n    var h: Double\n}\n\n// residual sentinel\n'
MOVED = '    func currentMainPlayback() -> Int? {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive ? mainPlaybackGeneration : nil\n    }\n    func isMainPlaybackCurrent(_ generation: Int) -> Bool {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive && mainPlaybackGeneration == generation\n    }\n'
PREFIX = "// relocated excerpt\n"
NEW = PREFIX + MOVED


BODY_SHA='5376f09eb96c2b52afc503647436cfe1fafd754be8809ef27b17902afc100dc2'
def verify(base,post,new):
 """AssertionError on any byte drift. Body starts at the first func line (marker excluded); residual drops BEGIN..END marker block."""
 check_split(base,post,new,PREFIX,"    func currentMainPlayback()","// END MOVE\n","// BEGIN MOVE\n","// residual sentinel\n",BODY_SHA,'fixture')

def fixture():
 verify(BASE,POST,NEW)
 for name,b,p,n in [
  ("body mutation",BASE,POST,NEW.replace("mainPlaybackActive","wrong",1)),
  ("residual mutation",BASE,POST+"x",NEW),
  ("lost newline",BASE,POST,NEW.rstrip()),
 ]:
  try: verify(b,p,n)
  except AssertionError: print("CAUGHT",name)
  else: raise RuntimeError("uncaught mutant: "+name)
 print("PASS portable byte-preservation fixture and 3 negative controls")
 edit_fixture()

def make_edit(hist,live):
 """Hunks for live relative to hist, as the recorder writes them."""
 import difflib
 hl=hist.splitlines(True);ll=live.splitlines(True);hunks=[]
 for tag,a,b,c,d in difflib.SequenceMatcher(None,hl,ll,autojunk=False).get_opcodes():
  if tag!='equal':hunks.append({'old':[a,b],'new':[c,d],'new_sha256':sha(''.join(ll[c:d]))})
 return hunks

def edit_fixture():
 """Historical/current rule: GREEN for pure, recorded and re-recorded edits; RED for each mutant."""
 hist=''.join('line %d\n'%n for n in range(30))
 live=hist.replace('line 5\n','line 5 edited\nline 5b\n').replace('line 20\n','')
 pure={'current_sha256':sha(hist)}
 rec={'current_sha256':sha(live),'edit':{'hunks':make_edit(hist,live)}}
 check_current(hist,hist,pure,'pure');check_current(hist,live,rec,'edited')
 import copy
 def mut(name,h,l,mv):
  try:check_current(h,l,mv,name)
  except AssertionError:print("CAUGHT",name);return
  raise RuntimeError("uncaught mutant: "+name)
 mut("unrecorded edit",hist,live,{'current_sha256':sha(live)})
 mut("edit recorded on pure file",hist,hist,{'current_sha256':sha(hist),'edit':rec['edit']})
 mut("stale current pin",hist,live,dict(rec,current_sha256=sha(hist)))
 mut("missing current pin",hist,live,{'edit':rec['edit']})
 mut("edit without hunks",hist,live,{'current_sha256':sha(live),'edit':{'hunks':[]}})
 l2=live.replace('line 12\n','line twelve\n')
 mut("change outside recorded span",hist,l2,dict(rec,current_sha256=sha(l2)))
 l3=live.replace('line 5b\n','line 5c\n')
 mut("edited bytes differ from recorded hash",hist,l3,dict(rec,current_sha256=sha(l3)))
 r4=copy.deepcopy(rec);r4['edit']['hunks'][0]['old']=[6,7];r4['edit']['hunks'][0]['new']=[6,8]
 mut("hunk span moved",hist,live,r4)
 r5=copy.deepcopy(rec);r5['edit']['hunks'].append({'old':[29,30],'new':[27,28],'new_sha256':sha(live.splitlines(True)[27])})
 mut("no-op hunk",hist,live,r5)
 l6=live+"tail\n"
 mut("change after last hunk",hist,l6,dict(rec,current_sha256=sha(l6)))
 print("PASS historical/current edit rule and 10 negative controls")

if __name__=='__main__':
 fixture() if '--fixture' in sys.argv[1:] else integration()
