#!/usr/bin/env python3
"""Real production provenance retirement for exact current Subtitles preimages.

Thin local Git-object fixture with actual product bytes. This does not establish
native execution or the historical installed-updater acceptance gate.
"""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=load('subtitles_provenance',ROOT/'tools/gor_provenance.py')
source=load('subtitles_provenance_source',ROOT/'Tests/Structure/subtitles_source.py')
legacy=load('subtitles_provenance_restore',ROOT/'Tests/Structure/migrate.py')
meta=json.loads((ROOT/'Tests/Structure/199u-subtitles-map.json').read_text())
old={u['old']:source.unit_text(name).encode() for name,u in meta['sections'].items()}
for unit in meta['sections'].values():assert p.UPDATE_RETIREMENTS[unit['old']]==(unit['source_sha256'],(unit['host'],))
def write(root,rel,body):q=root/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(body)
def sources(root):return {str(q.relative_to(root)):q.read_bytes() for q in (root/'Sources').rglob('*.swift')}
def all_files(root):return {str(q.relative_to(root)):q.read_bytes() for q in root.rglob('*') if q.is_file()}
env=dict(os.environ,GIT_AUTHOR_NAME='Subtitles Fixture',GIT_AUTHOR_EMAIL='fixture@localhost',GIT_COMMITTER_NAME='Subtitles Fixture',GIT_COMMITTER_EMAIL='fixture@localhost')
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],env=env,stderr=subprocess.STDOUT)
modes=['exact']+['edited-'+str(i) for i in range(5)]+['wrong-view-host','wrong-live-host','unknown-extra','missing-backup','source-symlink']
for mode in modes:
 with tempfile.TemporaryDirectory(prefix='subtitles-provenance-') as td:
  d=Path(td);repo=d/'repo';root=repo/'archive/gor';root.mkdir(parents=True)
  for rel in ('Package.swift','build.sh',*meta['hosts']):write(root,rel,(ROOT/rel).read_bytes())
  git(repo,'init','-q','-b','main');git(repo,'add','.');git(repo,'commit','-qm','Actual Subtitles host identity fixture');git(repo,'update-ref','refs/remotes/origin/main','HEAD')
  tip=git(repo,'rev-parse','HEAD').decode().strip();project=d/'installed';shutil.copytree(root,project)
  for rel,body in old.items():write(project,rel,body)
  backup=project/'.gor-backups/261122-140000-pre-update';backup.mkdir(parents=True);(backup/'changes.txt').write_text(''.join('added\t'+host+'\n' for host in meta['hosts']))
  if mode.startswith('edited-'):
   q=project/list(old)[int(mode.split('-')[1])];q.write_bytes(q.read_bytes()+b'\n// local source edit\n')
  elif mode in ('wrong-view-host','wrong-live-host'):
   host=list(meta['hosts'])[0 if mode=='wrong-view-host' else 1];q=project/host;q.write_bytes(q.read_bytes()+b'\n// altered delivered host\n')
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
  rows=legacy.entries(parked/'changes.txt');assert len(rows)==7 and {rel for kind,rel in rows if kind=='deleted'}==set(old)
  legacy.restore(project,parked,rows,d/'parked-new')
  expected={k:v for k,v in before_sources.items() if k not in meta['hosts']};assert sources(project)==expected
  for host in meta['hosts']:assert (d/'parked-new'/host).read_bytes()==(ROOT/host).read_bytes()
  print('PASS actual Subtitles provenance: five exact retirements, two hosts, backup readback, closed-input identity, idempotence and coherent source rollback')
print('SUBTITLES_PROVENANCE_GATE PASS: 1 exact + 10 refusal cases; native app/historical installed replay NOT_RUN')
