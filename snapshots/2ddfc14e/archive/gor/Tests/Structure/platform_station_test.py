#!/usr/bin/env python3
"""Platform pure-move, compiler-source, current-base overlay and rollback proof.

Portable execution covers the actual traversal, activation and ownership unit.
It does not compile Windowing against AppKit or replace native focus/Spaces acceptance.
"""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
source=load('platform_station_view',ROOT/'Tests/Structure/platform_source.py')
ss=source._sections
meta=json.loads((ROOT/'Tests/Structure/199u-platform-map.json').read_text())
assert meta['station']=='Platform' and set(meta['sections'])==source._NAMES
assert set(meta['hosts'])=={'Sources/gor/Platform/QuitChildKiller.swift','Sources/gor/Platform/Windowing.swift'}
original={}
for name,unit in meta['sections'].items():
 assert not (ROOT/unit['old']).exists(),unit['old']
 body=ss.section_text_exact(ROOT,name);text=source.unit_text(name);original[name]=text
 assert hashlib.sha256(body.encode()).hexdigest()==unit['body_sha256']
 assert hashlib.sha256(text.encode()).hexdigest()==unit['source_sha256']
 assert len(text.splitlines())==unit['source_lines']
 assert source.read_bytes(ROOT/unit['old'])==text.encode()
 assert source.compile_input(ROOT/unit['old']).read_bytes()==text.encode()
for host,record in meta['hosts'].items():
 text=(ROOT/host).read_text()
 assert hashlib.sha256(text.encode()).hexdigest()==record['sha256']
 assert 150<=len(text.splitlines())<=4000 and len(text.splitlines())==record['lines']
 expected='// Platform station: complete source units, with only unconditional imports lifted.\n'+''.join(x+'\n' for x in record['imports'])+'\n'+''.join('// MARK: - '+name+'\n'+ss.section_text_exact(ROOT,name) for name in record['units'])
 if record['standalone']:expected=original[record['units'][0]]
 assert text==expected,'material outside exact complete source units'
print('PASS four original units and compiler inputs byte-exact; two complete hosts pinned; standalone child-killer and nested preview fold retained')
with tempfile.TemporaryDirectory(prefix='platform-mark-') as td:
 d=Path(td);shutil.copytree(ROOT/'Sources',d/'Sources')
 p=d/'Tests/Structure';p.mkdir(parents=True)
 for name in ('section_source.py','199u-platform-map.json'):shutil.copy2(ROOT/'Tests/Structure'/name,p/name)
 carriers={}
 for i,host in enumerate(meta['hosts']):
  carrier=d/'Sources/gor/GhostStation'/(Path(host).name if meta['hosts'][host]['standalone'] else 'Carrier'+str(i)+'.swift');carrier.parent.mkdir(exist_ok=True);(d/host).rename(carrier);carriers[host]=carrier
  assert not (d/host).exists()
 for name in original:assert source.unit_text(name,d)==original[name]
 print('PASS all four views with both planned host paths absent; logical standalone filename and arbitrary Windowing MARK carrier')
 for name,unit in meta['sections'].items():
  carrier=carriers[unit['host']];before=carrier.read_text();body=ss.section_text_exact(d,name)
  changed=before+'// source mutant\n' if meta['hosts'][unit['host']]['standalone'] else before.replace('// MARK: - '+name+'\n'+body,'// MARK: - '+name+'\n'+body+'// source mutant\n',1)
  assert changed!=before
  carrier.write_text(changed)
  try:source.unit_text(name,d)
  except ValueError:pass
  else:raise AssertionError('body mutant accepted: '+name)
  carrier.write_text(before)
 for host,carrier in carriers.items():
  if not meta['hosts'][host]['imports']:continue
  before=carrier.read_text();line=meta['hosts'][host]['imports'][0]+'\n';assert before.count(line)>=1
  carrier.write_text(before.replace(line,'',1))
  for name in meta['hosts'][host]['units']:
   try:source.unit_text(name,d)
   except ValueError:pass
   else:raise AssertionError('missing host import accepted: '+name)
  carrier.write_text(before)
 # Duplicate unit headers and symlinked carriers are refused by the shared resolver.
 name='PanelFocusTraversal.swift';carrier=carriers[meta['sections'][name]['host']];before=carrier.read_text()
 carrier.write_text(before+'// MARK: - '+name+'\n')
 try:source.unit_text(name,d)
 except KeyError:pass
 else:raise AssertionError('duplicate MARK accepted')
 carrier.write_text(before);park=d/'saved-carrier';carrier.rename(park);carrier.symlink_to(park)
 try:source.unit_text(name,d)
 except KeyError:pass
 else:raise AssertionError('symlink carrier accepted')
 print('PASS four body, one host-import, duplicate-MARK and symlink-carrier negative controls')
retire=load('platform_current_retirement',ROOT/'Tests/Structure/retire-overlay.py')
legacy=load('platform_current_restore',ROOT/'Tests/Structure/migrate.py')
post={str(p.relative_to(ROOT)):p.read_bytes() for p in (ROOT/'Sources').rglob('*.swift')}
pre={k:v for k,v in post.items() if k not in meta['hosts']};pre.update({u['old']:original[n].encode() for n,u in meta['sections'].items()});assert len(pre)==len(post)+2

def setup(d):
 project=d/'project';project.mkdir()
 for rel,body in pre.items():
  p=project/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
 p=project/'Sources/gor/LocalPlatformSentinel.swift';p.write_text('// private fixture local source\n')
 backups=project/'.gor-backups';prior=backups/'261122-140000-pre-update';prior.mkdir(parents=True)
 (prior/'changes.txt').write_text(''.join('added\t'+host+'\n' for host in meta['hosts']))
 for host in meta['hosts']:
  p=project/host;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/host).read_bytes())
 q=project/'Tests/Structure';q.mkdir(parents=True)
 for name in ('retirements.json','section_source.py'):shutil.copy2(ROOT/'Tests/Structure'/name,q/name)
 return project,backups,d/'external'
def snapshot(root):return {str(p.relative_to(root)):p.read_bytes() for p in (root/'Sources').rglob('*.swift')}
with tempfile.TemporaryDirectory(prefix='platform-overlay-') as td:
 d=Path(td);project,backups,external=setup(d);sentinel={'Sources/gor/LocalPlatformSentinel.swift':b'// private fixture local source\n'}
 assert legacy.retire(project,backups,d/'legacy-external') is None
 backup=retire.retire(project,backups,external);assert snapshot(project)==post|sentinel
 for name,unit in meta['sections'].items():assert (backup/'retired-inputs'/unit['old']).read_bytes()==original[name].encode()
 assert retire.retire(project,backups,external) is None
 legacy.restore(project,backup,legacy.entries(backup/'changes.txt'),d/'parked-new')
 assert snapshot(project)==pre|sentinel
 print('PASS actual current-base retirement and rollback:',len(pre),'->',len(post),'Swift files; four originals saved; local source and one coherent add/delete journal retained; idempotence')
for kind,rel in [('host mutation',host) for host in meta['hosts']]+[('local edit',u['old']) for u in meta['sections'].values()]:
 with tempfile.TemporaryDirectory(prefix='platform-retire-red-') as td:
  d=Path(td);project,backups,external=setup(d);p=project/rel;p.write_bytes(p.read_bytes()+b'\n// altered source\n');before=snapshot(project)
  try:retire.retire(project,backups,external)
  except RuntimeError:pass
  else:raise AssertionError('retirement mutant accepted: '+kind+' '+rel)
  assert snapshot(project)==before and not external.exists()
print('PASS actual retirement refuses both changed hosts and all four local-source edits before any move or backup')
with tempfile.TemporaryDirectory(prefix='platform-actual-swift-') as td:
 d=Path(td);(d/'PanelFocusTraversal.swift').write_text(original['PanelFocusTraversal.swift'])
 (d/'main.swift').write_text('import Foundation\nfinal class Node { let id:Int; var visible:Bool; var children:[Node]; init(_ id:Int,_ visible:Bool=true,_ children:[Node]=[]){self.id=id;self.visible=visible;self.children=children} }\nlet hidden=Node(2,false,[Node(3)]), target=Node(4), root=Node(1,true,[hidden,target])\nlet found:Node?=PanelFocusTraversal.first(in:root,children:{$0.children},visible:{$0.visible},accept:{$0.id==3 || $0.id==4 ? $0 : nil})\nprecondition(found === target)\nprecondition(NoActivate.requested(arguments:["--gor-no-activate"],environment:[:]))\nprecondition(NoActivate.requested(arguments:[],environment:["GOR_NO_ACTIVATE":"1"]))\nprecondition(!NoActivate.requested(arguments:[],environment:[:]))\nlet owner=PanelKeyOwnership(), token=ObjectIdentifier(target)\nfor _ in 0..<10000 { owner.register(token);precondition(owner.panelOwnsKey && !owner.mayKeyPlayerWindow());owner.register(token);owner.unregister(token);precondition(!owner.panelOwnsKey && owner.mayKeyPlayerWindow()) }\nprint("PASS actual moved traversal, explicit activation inputs and 10000 ownership transitions")\n')
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(d/'PanelFocusTraversal.swift'),str(d/'main.swift'),'-o',str(d/'test')],check=True)
 subprocess.run([str(d/'test')],check=True)
print('PLATFORM_SOURCE_GATE PASS; native AppKit focus/Spaces, old-installed and full Darwin build NOT_RUN')
