#!/usr/bin/env python3
"""Actual provenance retirement for the three exact current Display preimages.

Closed Git-object fixture, real production host and old-unit bytes, no Swift
compilation or installed-machine claim. Historical pre-Display replay is separate.
"""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=load('display_provenance',ROOT/'tools/gor_provenance.py')
pp=load('display_provenance_source',ROOT/'Tests/Structure/pp_split.py')
legacy=load('display_provenance_restore',ROOT/'Tests/Structure/migrate.py')
meta=json.loads((ROOT/'Tests/Structure/199u-display-map.json').read_text());host=next(iter(meta['hosts']))
old={u['old']:pp.part_text(ROOT,name).encode() for name,u in meta['sections'].items()}
for rel,body in old.items():assert p.UPDATE_RETIREMENTS[rel]==(hashlib.sha256(body).hexdigest(),(host,))
assert host in p.UPDATE_RETIREMENTS['Sources/gor/gor/PPController_Features.swift'][1]

def write(root,rel,body):q=root/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(body)
def sources(root):return {str(q.relative_to(root)):q.read_bytes() for q in (root/'Sources').rglob('*.swift')}
def all_files(root):return {str(q.relative_to(root)):q.read_bytes() for q in root.rglob('*') if q.is_file()}
env=dict(os.environ,GIT_AUTHOR_NAME='Display Fixture',GIT_AUTHOR_EMAIL='fixture@localhost',GIT_COMMITTER_NAME='Display Fixture',GIT_COMMITTER_EMAIL='fixture@localhost')
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],env=env,stderr=subprocess.STDOUT)
for mode in ('exact','edited-controller','edited-cache','edited-dimming','wrong-host','unknown-extra','missing-backup','source-symlink'):
 with tempfile.TemporaryDirectory(prefix='display-provenance-') as td:
  d=Path(td);repo=d/'repo';root=repo/'archive/gor';root.mkdir(parents=True)
  # Thin but real-byte fixture for the identity algorithm. No app compile claim.
  for rel in ('Package.swift','build.sh',host):write(root,rel,(ROOT/rel).read_bytes())
  git(repo,'init','-q','-b','main');git(repo,'add','.');git(repo,'commit','-qm','Actual Display host identity fixture');git(repo,'update-ref','refs/remotes/origin/main','HEAD')
  tip=git(repo,'rev-parse','HEAD').decode().strip();project=d/'installed';shutil.copytree(root,project)
  for rel,body in old.items():write(project,rel,body)
  backup=project/'.gor-backups/261122-140000-pre-update';backup.mkdir(parents=True);(backup/'changes.txt').write_text('added\t'+host+'\n')
  if mode.startswith('edited-'):
   rel=list(old)[('edited-controller','edited-cache','edited-dimming').index(mode)];q=project/rel;q.write_bytes(q.read_bytes()+b'\n// local source edit\n')
  elif mode=='wrong-host':q=project/host;q.write_text(q.read_text().replace('import AppKit\n','',1))
  elif mode=='unknown-extra':write(project,'Sources/gor/LocalUnknown.swift',b'// unrecognized local input\n')
  elif mode=='missing-backup':(backup/'changes.txt').rename(d/'saved-journal')
  elif mode=='source-symlink':q=project/next(iter(old));q.rename(d/'original-source');q.symlink_to(d/'original-source')
  before=all_files(project);before_sources=sources(project)
  try:receipt=p.record_delivery(repo,project,'main')
  except p.Refusal:
   assert mode!='exact',mode
   assert all_files(project)==before and not (project/p.RECORD).exists(),('refusal mutated project',mode)
   if mode=='source-symlink':assert (project/next(iter(old))).is_symlink()
   print('PASS actual provenance refusal before any project/receipt change:',mode);continue
  assert mode=='exact',('mutant accepted',mode)
  assert all(not (project/rel).exists() for rel in old)
  assert receipt['source_commit']==tip and p.identity(repo,project)['verification']==p.VERIFIED
  p.verify_installed(repo,tip,project)
  prior_receipt=(project/p.RECORD).read_bytes();p.record_delivery(repo,project,'main');assert (project/p.RECORD).read_bytes()==prior_receipt
  parked=next((project/'.gor-backups').glob('*-pre-update-retire'))
  for rel,body in old.items():assert (parked/rel).read_bytes()==body
  rows=legacy.entries(parked/'changes.txt');assert len(rows)==4 and {rel for kind,rel in rows if kind=='deleted'}==set(old)
  legacy.restore(project,parked,rows,d/'parked-new')
  expected={k:v for k,v in before_sources.items() if k!=host};assert sources(project)==expected
  assert (d/'parked-new'/host).read_bytes()==(ROOT/host).read_bytes()
  print('PASS actual current Display provenance: three exact retirements, backup readback, receipt/closed-input verification, idempotence and source rollback')
print('DISPLAY_PROVENANCE_GATE PASS: 1 exact + 7 refusal cases; native app/full old-installed replay NOT_RUN')
