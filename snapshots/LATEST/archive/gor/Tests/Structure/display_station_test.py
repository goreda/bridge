#!/usr/bin/env python3
"""Display source preservation and current-base overlay proof. No display hardware writes.

Portable Swift compilation covers the actual cache body, not the AppKit host.
Native app, timer/capture behavior and old installed-checkout replay are separate.
"""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
pp=load('display_pp_source',ROOT/'Tests/Structure/pp_split.py')
ss=pp.source_sections(ROOT)
meta=json.loads((ROOT/'Tests/Structure/199u-display-map.json').read_text())
assert meta['station']=='Display' and set(meta['sections'])=={'BrightnessController.swift','BrightnessReadCache.swift','ContentAdaptiveDimming.swift'}
assert list(meta['hosts'])==['Sources/gor/Picture/Brightness.swift']
host,record=next(iter(meta['hosts'].items()));text=(ROOT/host).read_text();assert hashlib.sha256(text.encode()).hexdigest()==record['sha256']
assert 150<=len(text.splitlines())<=4000 and len(text.splitlines())==record['lines']
assert [line for line in text.split('// MARK: - ',1)[0].splitlines() if line.startswith('import ')]==record['imports']
original={}
for name,unit in meta['sections'].items():
 assert not (ROOT/unit['old']).exists(),unit['old']
 body=ss.section_text_exact(ROOT,name);source=pp.part_text(ROOT,name);original[name]=source
 assert hashlib.sha256(body.encode()).hexdigest()==unit['body_sha256']
 assert hashlib.sha256(source.encode()).hexdigest()==unit['source_sha256']
 assert len(source.splitlines())==unit['source_lines']
 assert [e['line'] for e in unit['lifted_import_lines']]==list(range(1,9))
 assert ''.join(e['text'] for e in unit['lifted_import_lines'])==pp.part_prefix(ROOT,name)
 assert source==pp.part_prefix(ROOT,name)+body
expected='// Display station: complete source units, with only unconditional imports lifted.\n'+''.join(x+'\n' for x in record['imports'])+'\n'+''.join('// MARK: - '+name+'\n'+ss.section_text_exact(ROOT,name) for name in record['units'])
assert text==expected,'unrecorded material outside exact complete units'
print('PASS Display: three originals byte-exact through existing PP/section resolver; single complete host/import union pinned; old paths absent')
with tempfile.TemporaryDirectory(prefix='display-mark-') as td:
 d=Path(td);shutil.copytree(ROOT/'Sources',d/'Sources')
 for rel in ('Tests/Structure/section_source.py','Tests/Structure/pp_split.py','Tests/Structure/pp-split-manifest.json'):
  p=d/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p)
 carrier=d/'Sources/gor/Unrelated/ScreenLumaCarrier.swift';carrier.parent.mkdir();(d/host).rename(carrier)
 assert not (d/host).exists()
 for name in original:
  assert not (d/meta['sections'][name]['old']).exists()
  assert pp.part_text(d,name)==original[name]
 print('PASS literal-path seed RED, relocated MARK carrier GREEN for all three original source views')
 before=carrier.read_text()
 for name,unit in meta['sections'].items():
  body=ss.section_text_exact(d,name);carrier.write_text(before.replace('// MARK: - '+name+'\n'+body,'// MARK: - '+name+'\n'+body+'// source mutant\n',1))
  assert hashlib.sha256(pp.part_text(d,name).encode()).hexdigest()!=unit['source_sha256']
  carrier.write_text(before)
 # The existing PP import-union guard, not a new permissive reconstruction path.
 carrier.write_text(before.replace('import IOKit\n','',1))
 for name in original:
  try:pp.part_text(d,name)
  except AssertionError:pass
  else:raise AssertionError('missing carrier import accepted: '+name)
 print('PASS three body mutants change the original pin; all three missing-import views refuse')
retire=load('display_retirement',ROOT/'Tests/Structure/retire-overlay.py')
legacy=load('display_restore',ROOT/'Tests/Structure/migrate.py')
post={str(p.relative_to(ROOT)):p.read_bytes() for p in (ROOT/'Sources').rglob('*.swift')}
pre={k:v for k,v in post.items() if k!=host};pre.update({u['old']:original[n].encode() for n,u in meta['sections'].items()});assert len(pre)==len(post)+2

def setup(d):
 project=d/'project';project.mkdir()
 for rel,body in pre.items():
  p=project/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
 sentinel=project/'Sources/gor/LocalDisplaySentinel.swift';sentinel.write_text('// private fixture local source\n')
 backups=project/'.gor-backups';prior=backups/'261122-140000-pre-update';prior.mkdir(parents=True)
 (prior/'changes.txt').write_text('added\t'+host+'\n')
 p=project/host;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/host).read_bytes())
 q=project/'Tests/Structure';q.mkdir(parents=True)
 for rel in ('retirements.json','section_source.py'):shutil.copy2(ROOT/'Tests/Structure'/rel,q/rel)
 return project,backups,d/'external'
def snapshot(root):return {str(p.relative_to(root)):p.read_bytes() for p in (root/'Sources').rglob('*.swift')}
with tempfile.TemporaryDirectory(prefix='display-overlay-') as td:
 d=Path(td);project,backups,external=setup(d);sentinel={'Sources/gor/LocalDisplaySentinel.swift':b'// private fixture local source\n'}
 assert legacy.retire(project,backups,d/'legacy-external') is None
 backup=retire.retire(project,backups,external);assert snapshot(project)==post|sentinel
 for name,unit in meta['sections'].items():assert (backup/'retired-inputs'/unit['old']).read_bytes()==original[name].encode()
 assert retire.retire(project,backups,external) is None
 legacy.restore(project,backup,legacy.entries(backup/'changes.txt'),d/'parked-new')
 assert snapshot(project)==pre|sentinel
 print('PASS shipped retirement and restore:',len(pre),'->',len(post),'Swift files; all three originals saved, local file retained, idempotence and exact source rollback')
mutants=[('host body',host),('host imports',host)]+[('local edit',u['old']) for u in meta['sections'].values()]
for kind,rel in mutants:
 with tempfile.TemporaryDirectory(prefix='display-retire-red-') as td:
  d=Path(td);project,backups,external=setup(d);p=project/rel
  if kind=='host imports':p.write_text(p.read_text().replace('import AppKit\n','',1))
  else:p.write_bytes(p.read_bytes()+b'\n// altered source\n')
  before=snapshot(project)
  try:retire.retire(project,backups,external)
  except RuntimeError:pass
  else:raise AssertionError('retirement mutant accepted: '+kind+' '+rel)
  assert snapshot(project)==before and not external.exists()
print('PASS actual retirement: two host mutants and three local-edit mutants refuse before any source move or backup')
with tempfile.TemporaryDirectory(prefix='display-cache-swift-') as td:
 d=Path(td);source=d/'BrightnessReadCache.swift';source.write_text('import Foundation\n'+ss.section_text_exact(ROOT,'BrightnessReadCache.swift'))
 main=d/'main.swift';main.write_text('''import Foundation
var cache=BrightnessReadCache()
precondition(cache.fresh(0)==nil && cache.hardwareReads==0)
cache.hardwareRead(0.6,10)
precondition(cache.fresh(10)==Float(0.6) && cache.hardwareReads==1)
precondition(cache.fresh(10.249)==Float(0.6))
precondition(cache.fresh(10.25)==nil && cache.fresh(9.999)==nil)
cache.wrote(0.8,10.1)
precondition(cache.fresh(10.249)==Float(0.8))
precondition(cache.fresh(10.25)==nil && cache.hardwareReads==1)
cache.hardwareRead(0.4,11)
precondition(cache.hardwareReads==2 && cache.fresh(11)==Float(0.4))
precondition(cache.fresh(Double.nan)==nil && cache.fresh(Double.infinity)==nil)
var unseeded=BrightnessReadCache()
unseeded.wrote(0.7,20)
precondition(unseeded.fresh(20)==Float(0.7) && unseeded.hardwareReads==0)
precondition(unseeded.fresh(20.25)==nil)
print("PASS actual moved cache body: TTL boundary, clock reversal, read counts, write timestamp retention, first write and nonfinite time")
''')
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(source),str(main),'-o',str(d/'test')],check=True)
 subprocess.run([str(d/'test')],check=True)
print('DISPLAY_SOURCE_GATE PASS; full Darwin/gorTests/hardware/capture/native timers/old installed replay NOT_RUN')
