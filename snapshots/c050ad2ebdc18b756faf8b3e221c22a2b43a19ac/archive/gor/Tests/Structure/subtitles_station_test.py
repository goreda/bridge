#!/usr/bin/env python3
"""Subtitles pure-move, compiler-source, current-base overlay and rollback proof.

Portable execution covers the actual tilt, size/mode and bounded-reader units.
It does not compile the AppKit host or replace native UI/audio/capture acceptance.
"""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
source=load('subtitles_station_view',ROOT/'Tests/Structure/subtitles_source.py')
ss=source._sections
meta=json.loads((ROOT/'Tests/Structure/199u-subtitles-map.json').read_text())
assert meta['station']=='Subtitles' and set(meta['sections'])==source._NAMES
assert set(meta['hosts'])=={'Sources/gor/Subtitles/SubtitleView.swift','Sources/gor/Subtitles/LiveCaption.swift'}
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
 expected='// Subtitles station: complete source units, with only unconditional imports lifted.\n'+''.join(x+'\n' for x in record['imports'])+'\n'+''.join('// MARK: - '+name+'\n'+ss.section_text_exact(ROOT,name) for name in record['units'])
 assert text==expected,'material outside exact complete source units'
assert '#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n' in ss.section_text_exact(ROOT,'SubtitlePreferences.swift')
assert len(meta['sections']['SubtitlePreferences.swift']['lifted_import_lines'])==2
print('PASS five original units and compiler inputs byte-exact; two complete hosts pinned; conditional network import and relocated-download body retained')
with tempfile.TemporaryDirectory(prefix='subtitles-mark-') as td:
 d=Path(td);shutil.copytree(ROOT/'Sources',d/'Sources')
 p=d/'Tests/Structure';p.mkdir(parents=True)
 for name in ('section_source.py','199u-subtitles-map.json'):shutil.copy2(ROOT/'Tests/Structure'/name,p/name)
 carriers={}
 for i,host in enumerate(meta['hosts']):
  carrier=d/'Sources/gor/GhostStation'/('Carrier'+str(i)+'.swift');carrier.parent.mkdir(exist_ok=True);(d/host).rename(carrier);carriers[host]=carrier
  assert not (d/host).exists()
 for name in original:assert source.unit_text(name,d)==original[name]
 print('PASS all five views with both planned host paths absent and arbitrary MARK carriers')
 for name,unit in meta['sections'].items():
  carrier=carriers[unit['host']];before=carrier.read_text();body=ss.section_text_exact(d,name)
  carrier.write_text(before.replace('// MARK: - '+name+'\n'+body,'// MARK: - '+name+'\n'+body+'// source mutant\n',1))
  try:source.unit_text(name,d)
  except ValueError:pass
  else:raise AssertionError('body mutant accepted: '+name)
  carrier.write_text(before)
 for host,carrier in carriers.items():
  before=carrier.read_text();line=meta['hosts'][host]['imports'][0]+'\n';assert before.count(line)>=1
  carrier.write_text(before.replace(line,'',1))
  for name in meta['hosts'][host]['units']:
   try:source.unit_text(name,d)
   except ValueError:pass
   else:raise AssertionError('missing host import accepted: '+name)
  carrier.write_text(before)
 # Duplicate unit headers and symlinked carriers are refused by the shared resolver.
 name='SubtitleTiltGeometry.swift';carrier=carriers[meta['sections'][name]['host']];before=carrier.read_text()
 carrier.write_text(before+'// MARK: - '+name+'\n')
 try:source.unit_text(name,d)
 except KeyError:pass
 else:raise AssertionError('duplicate MARK accepted')
 carrier.write_text(before);park=d/'saved-carrier';carrier.rename(park);carrier.symlink_to(park)
 try:source.unit_text(name,d)
 except KeyError:pass
 else:raise AssertionError('symlink carrier accepted')
 print('PASS five body, two host-import, duplicate-MARK and symlink-carrier negative controls')
retire=load('subtitles_current_retirement',ROOT/'Tests/Structure/retire-overlay.py')
legacy=load('subtitles_current_restore',ROOT/'Tests/Structure/migrate.py')
post={str(p.relative_to(ROOT)):p.read_bytes() for p in (ROOT/'Sources').rglob('*.swift')}
pre={k:v for k,v in post.items() if k not in meta['hosts']};pre.update({u['old']:original[n].encode() for n,u in meta['sections'].items()});assert len(pre)==len(post)+3

def setup(d):
 project=d/'project';project.mkdir()
 for rel,body in pre.items():
  p=project/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
 p=project/'Sources/gor/LocalSubtitlesSentinel.swift';p.write_text('// private fixture local source\n')
 backups=project/'.gor-backups';prior=backups/'261122-140000-pre-update';prior.mkdir(parents=True)
 (prior/'changes.txt').write_text(''.join('added\t'+host+'\n' for host in meta['hosts']))
 for host in meta['hosts']:
  p=project/host;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/host).read_bytes())
 q=project/'Tests/Structure';q.mkdir(parents=True)
 for name in ('retirements.json','section_source.py'):shutil.copy2(ROOT/'Tests/Structure'/name,q/name)
 return project,backups,d/'external'
def snapshot(root):return {str(p.relative_to(root)):p.read_bytes() for p in (root/'Sources').rglob('*.swift')}
with tempfile.TemporaryDirectory(prefix='subtitles-overlay-') as td:
 d=Path(td);project,backups,external=setup(d);sentinel={'Sources/gor/LocalSubtitlesSentinel.swift':b'// private fixture local source\n'}
 assert legacy.retire(project,backups,d/'legacy-external') is None
 backup=retire.retire(project,backups,external);assert snapshot(project)==post|sentinel
 for name,unit in meta['sections'].items():assert (backup/'retired-inputs'/unit['old']).read_bytes()==original[name].encode()
 assert retire.retire(project,backups,external) is None
 legacy.restore(project,backup,legacy.entries(backup/'changes.txt'),d/'parked-new')
 assert snapshot(project)==pre|sentinel
 print('PASS actual current-base retirement and rollback:',len(pre),'->',len(post),'Swift files; five originals saved; local source and one coherent add/delete journal retained; idempotence')
for kind,rel in [('host mutation',host) for host in meta['hosts']]+[('local edit',u['old']) for u in meta['sections'].values()]:
 with tempfile.TemporaryDirectory(prefix='subtitles-retire-red-') as td:
  d=Path(td);project,backups,external=setup(d);p=project/rel;p.write_bytes(p.read_bytes()+b'\n// altered source\n');before=snapshot(project)
  try:retire.retire(project,backups,external)
  except RuntimeError:pass
  else:raise AssertionError('retirement mutant accepted: '+kind+' '+rel)
  assert snapshot(project)==before and not external.exists()
print('PASS actual retirement refuses both changed hosts and all five local-source edits before any move or backup')
with tempfile.TemporaryDirectory(prefix='subtitles-actual-swift-') as td:
 d=Path(td)
 for name in ('SubtitleTiltGeometry.swift','SubtitlePreferences.swift'):(d/name).write_text(original[name])
 (d/'main.swift').write_text('''import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
let defaults=UserDefaults(suiteName:"subtitles-station-"+UUID().uuidString)!
let state=URL(fileURLWithPath:CommandLine.arguments[1])
try JSONSerialization.data(withJSONObject:["build":"prior-app","pid":9,"sub-scale":0.65,"sub-delay":2]).write(to:state)
precondition(SubtitleSizePreference.restored(defaults:defaults,stateURL:state)==0.65)
SubtitleSizePreference.save(0.5,defaults:defaults,pictureInPicture:true)
precondition(SubtitleSizePreference.restored(defaults:defaults,stateURL:state)==0.65)
precondition(SubtitleSizePreference.restoredPiP(defaults:defaults)==0.5)
SubtitleSizePreference.save(Double.nan,defaults:defaults)
precondition(SubtitleSizePreference.restored(defaults:defaults,stateURL:state)==0.65)
var mode=SubtitleModeScale(normal:0.65,pip:0.5)
precondition(mode.transition(to:false)==nil)
precondition(mode.transition(to:true)==0.5)
mode.accept(0.75);mode.accept(-1)
precondition(mode.transition(to:false)==0.65 && mode.pip==0.75)
precondition(defaults.object(forKey:"sub-delay")==nil)
let rect=CGRect(x:40,y:200,width:360,height:86),screen=CGRect(x:0,y:0,width:960,height:600)
for deg in [-30.0,-20,-10,0,10,20,30] {
 let angle=deg*Double.pi/180
 let placement=SubtitleTiltGeometry.place(ink:rect,screen:screen,shift:483,left:1,offset:-2,roll:angle,pairRoll:angle)
 precondition(abs(placement.angle+angle)<1e-12)
 precondition(placement.leftX.isFinite && placement.leftY.isFinite && placement.replicaX.isFinite && placement.replicaY.isFinite)
}
var called=0
BoundedSubtitleDownload.fetch(URLRequest(url:URL(string:"http://127.0.0.1:1/not-requested")!),limit:0){ data in precondition(data==nil);called+=1 }
precondition(called==1 && BoundedSubtitleDownload.subtitleLimit==32*1024*1024)
print("PASS actual moved tilt and full preference/download units: seven tilt signs, normal/PiP transitions, persisted-size recovery, invalid values, no delay migration and zero-limit synchronous HTTP refusal")
''')
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(d/'SubtitleTiltGeometry.swift'),str(d/'SubtitlePreferences.swift'),str(d/'main.swift'),'-o',str(d/'test')],check=True)
 subprocess.run([str(d/'test'),str(d/'state.json')],check=True)
print('SUBTITLES_SOURCE_GATE PASS; native UI/audio/capture/inference and historical old-installed replay NOT_RUN')
