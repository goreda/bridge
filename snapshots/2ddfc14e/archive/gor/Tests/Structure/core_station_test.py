#!/usr/bin/env python3
"""Core-only byte preservation, relocation, actual overlay and rollback controls.

No native compile, SDK, installed-updater replay or behavior acceptance claim.
"""
from pathlib import Path
import collections,hashlib,importlib.util,json,shutil,tempfile
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
core=load('core_gate_source',ROOT/'Tests/Structure/core_source.py')
ss=core._sections
pins=json.loads((ROOT/'Tests/Structure/199u-core-map.json').read_text())
assert pins['station']=='Core' and len(pins['sections'])==6 and len(pins['hosts'])==2
checks=0
for name,p in pins['sections'].items():
 assert not (ROOT/p['old']).exists(),('old Core path remains',p['old'])
 exact=core.unit_text(name);assert hashlib.sha256(exact.encode()).hexdigest()==p['source_sha256']
 assert len(exact.splitlines())==p['source_lines']
 assert hashlib.sha256(ss.section_text_exact(ROOT,name).encode()).hexdigest()==p['body_sha256']
 assert ss.section_file(ROOT,name)==ROOT/p['host']
 checks+=1
for host,p in pins['hosts'].items():
 f=ROOT/host;text=f.read_text();assert hashlib.sha256(f.read_bytes()).hexdigest()==p['sha256']
 assert 150<=len(text.splitlines())<=4000 and len(text.splitlines())==p['lines']
 top=text.split('// MARK: - ',1)[0];assert sorted(line for line in top.splitlines() if line.startswith('import '))==p['imports']
 assert [line[len('// MARK: - '):] for line in text.splitlines() if ss.UNIT_MARK.match(line)]==p['units']
 expected='// Core station: source units below retain their complete non-lifted bytes.\n'+''.join(x+'\n' for x in p['imports'])+'\n'+''.join('// MARK: - '+name+'\n'+ss.section_text_exact(ROOT,name) for name in p['units'])
 assert text==expected,'host has unrecorded material outside exact source units'
 checks+=1
print('PASS six complete source units reconstruct byte-exact; two exact hosts/import unions; no old paths; line band')
# Positive relocation: no second resolver and no hard-coded host dependency.
with tempfile.TemporaryDirectory(prefix='core-mark-') as d:
 d=Path(d);shutil.copytree(ROOT/'Sources',d/'Sources')
 for rel in ('Tests/Structure/core_source.py','Tests/Structure/section_source.py','Tests/Structure/199u-core-map.json'):
  p=d/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p)
 expected={name:core.unit_text(name) for name in pins['sections']}
 carrier=d/'Sources/gor/Scratch/CoreCarrier.swift';carrier.parent.mkdir();carrier.write_text(''.join(x+'\n' for x in sorted({x for h in pins['hosts'].values() for x in h['imports']}))+'\n'+''.join('// MARK: - '+name+'\n'+ss.section_text_exact(d,name) for name in pins['sections']))
 for host in pins['hosts']:(d/host).unlink() # This private fixture only.
 moved=load('core_relocated_source',d/'Tests/Structure/core_source.py')
 assert all(moved.unit_text(name,d)==text for name,text in expected.items())
 assert all(not (d/p['old']).exists() for p in pins['sections'].values())
 print('PASS seed RED old paths absent; moved GREEN all six exact compiler/source views from one unrelated MARK carrier')
 checks+=6
 # Guard mutants retain an actual source name but lose its original bytes.
 original=carrier.read_text()
 for name,pin in pins['sections'].items():
  body=moved._sections.section_text_exact(d,name)
  assert body
  carrier.write_text(original.replace('// MARK: - '+name+'\n'+body,'// MARK: - '+name+'\n'+body+'// changed Core body\n',1))
  try:moved.unit_text(name,d)
  except ValueError:pass
  else:raise AssertionError('Core body mutant escaped: '+name)
  carrier.write_text(original);checks+=1
 print('PASS six source-body mutants refused')
 original_map=(d/'Tests/Structure/199u-core-map.json').read_text()
 for name in pins['sections']:
  changed=json.loads(original_map);changed['sections'][name]['lifted_import_lines'][0]['text']='import BrokenCoreImport\n'
  (d/'Tests/Structure/199u-core-map.json').write_text(json.dumps(changed))
  try:moved.unit_text(name,d)
  except ValueError:pass
  else:raise AssertionError('Core import reconstruction mutant escaped: '+name)
  (d/'Tests/Structure/199u-core-map.json').write_text(original_map);checks+=1
 print('PASS six import-reconstruction mutants refused')
# Actual shipped retirement helper, real current source bytes, no deletion model.
retire=load('core_gate_retire',ROOT/'Tests/Structure/retire-overlay.py')
post={str(p.relative_to(ROOT)):p.read_bytes() for p in (ROOT/'Sources').rglob('*.swift')}
pre={k:v for k,v in post.items() if k not in pins['hosts']}
pre.update({p['old']:core.unit_text(name).encode() for name,p in pins['sections'].items()})
assert len(pre)==len(post)+4

def setup(d):
 project=d/'project';project.mkdir()
 for rel,body in pre.items():
  p=project/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
 sentinel=project/'Sources/gor/LocalCoreSentinel.swift';sentinel.write_text('// private fixture local source must survive\n')
 backups=project/'.gor-backups';prior=backups/'261122-140000-pre-update';prior.mkdir(parents=True)
 changes=[]
 for rel,body in post.items():
  p=project/rel;p.parent.mkdir(parents=True,exist_ok=True)
  if rel not in pre:changes.append(('added',rel))
  elif pre[rel]!=body:
   changes.append(('changed',rel));q=prior/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(pre[rel])
  p.write_bytes(body)
 (prior/'changes.txt').write_text(''.join(k+'\t'+v+'\n' for k,v in changes))
 q=project/'Tests/Structure';q.mkdir(parents=True)
 for rel in ('retirements.json','section_source.py'):shutil.copy2(ROOT/'Tests/Structure'/rel,q/rel)
 return project,backups,d/'external'
def snapshot(project):return {str(p.relative_to(project)):p.read_bytes() for p in (project/'Sources').rglob('*.swift')}
with tempfile.TemporaryDirectory(prefix='core-overlay-') as d:
 d=Path(d);project,backups,external=setup(d);sentinel={'Sources/gor/LocalCoreSentinel.swift':b'// private fixture local source must survive\n'}
 result=retire.retire(project,backups,external);assert snapshot(project)==post|sentinel
 assert retire.retire(project,backups,external) is None
 for name,p in pins['sections'].items():assert (result/'retired-inputs'/p['old']).read_bytes()==pre[p['old']]
 # Replay the real retirement backup manifest, including both added Core hosts.
 parked=d/'rollback-parked';parked.mkdir()
 for line in (result/'changes.txt').read_text().splitlines():
  kind,rel=line.split('\t');target=project/rel
  if kind=='added':shutil.move(str(target),str(parked/target.name))
  else:target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(result/rel,target)
 assert snapshot(project)==pre|sentinel
 print('PASS actual current-checkout overlay',len(pre),'->',len(post),'Swift files, six originals saved, local source retained, idempotence and exact whole-source rollback')
 checks+=1
for kind,paths in (('replacement',list(pins['hosts'])),('local-edit',[p['old'] for p in pins['sections'].values()])):
 for rel in paths:
  with tempfile.TemporaryDirectory(prefix='core-retire-red-') as d:
   d=Path(d);project,backups,external=setup(d);p=project/rel;p.write_bytes(p.read_bytes()+b'\n// injected changed bytes\n');before=snapshot(project)
   try:retire.retire(project,backups,external)
   except RuntimeError:pass
   else:raise AssertionError('retirement mutant escaped: '+kind+' '+rel)
   assert snapshot(project)==before and not external.exists()
   checks+=1
print('PASS two replacement and six local-edit mutants refuse before any source move or backup')
for rel in pins['hosts']:
 with tempfile.TemporaryDirectory(prefix='core-import-red-') as d:
  d=Path(d);project,backups,external=setup(d);p=project/rel;before=p.read_text();after=before.replace('import AppKit\n','',1);assert before!=after;p.write_text(after);snapshot_before=snapshot(project)
  try:retire.retire(project,backups,external)
  except RuntimeError:pass
  else:raise AssertionError('whole-host import mutant escaped: '+rel)
  assert snapshot(project)==snapshot_before and not external.exists();checks+=1
print('PASS both whole-host import-union mutants refuse before any source move or backup')
print('CORE_SOURCE_GATE PASS checks='+str(checks)+'; historical installed checkout/Darwin/gorTests NOT_RUN')
