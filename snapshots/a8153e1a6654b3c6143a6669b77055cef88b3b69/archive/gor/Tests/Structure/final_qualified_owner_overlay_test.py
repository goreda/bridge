from pathlib import Path
import os,subprocess,tempfile,shutil,importlib.util
R=Path(__file__).resolve().parents[2];OBJECT_REPO=Path(os.environ.get('GOR_OBJECT_REPO',str(R)));S='374c2b9e14bfbf1614091767c83ce4ce3f07bac8'
spec=importlib.util.spec_from_file_location('actual_prov',R/'tools/gor_provenance.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
oldnames=subprocess.check_output(['git','-C',str(OBJECT_REPO),'ls-tree','--full-tree','-r','--name-only',S+':archive/gor/Sources']).decode().splitlines()
old={'Sources/'+p:subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',S+':archive/gor/Sources/'+p]) for p in oldnames if p.endswith('.swift')}
current={str(p.relative_to(R)):p.read_bytes() for p in (R/'Sources').rglob('*.swift')}
assert len(old)==len(current)==88
assert set(p.name for p in (R/'Sources/gor').iterdir() if p.is_dir() and any(p.iterdir()))=={'App','Player','Engine','Media','Picture','Stereo','Camera','Subtitles','UI','Modes','Session','Platform'}
def snap(r):return {str(p.relative_to(r)):p.read_bytes() for p in (r/'Sources').rglob('*.swift')}
for kind in ['exact','edited-qualified-app','missing-foundation','wrong-current']:
 with tempfile.TemporaryDirectory() as t:
  t=Path(t);repo=t/'repo';r=repo/'archive/gor';r.mkdir(parents=True)
  for rel,b in current.items():p=r/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
  for rel,b in {'Package.swift':b'//fixture','build.sh':b'echo fixture','Packages/p/Package.swift':b'//fixture'}.items():p=r/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
  env=dict(os.environ,GIT_AUTHOR_NAME='test',GIT_AUTHOR_EMAIL='test@localhost',GIT_COMMITTER_NAME='test',GIT_COMMITTER_EMAIL='test@localhost')
  def git(*a):return subprocess.check_output(['git',*a],env=env,stderr=subprocess.STDOUT)
  git('init','-q','-b','main',str(repo));git('-C',str(repo),'add','.');git('-C',str(repo),'commit','-qm','fixture');git('-C',str(repo),'update-ref','refs/remotes/origin/main','HEAD')
  project=t/'project';shutil.copytree(r,project)
  for rel,b in old.items():p=project/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
  stale=set(old)-set(current);added=set(current)-set(old);back=project/'.gor-backups/261122-210000-pre-update';back.mkdir(parents=True)
  for rel in set(old)&set(current):p=back/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(old[rel])
  rows=[('added',p) for p in sorted(added)]+[('changed',p) for p in sorted(set(old)&set(current))]
  (back/'changes.txt').write_text(''.join(k+'\t'+p+'\n' for k,p in rows) if kind!='missing-foundation' else '')
  # Source updater overwrites still-current files before record_delivery, while moved old paths remain.
  for rel,b in current.items():(project/rel).write_bytes(b)
  if kind=='edited-qualified-app':p=project/'Sources/gor/AppDelegate.swift';p.write_bytes(p.read_bytes()+b'//edited')
  if kind=='wrong-current':p=project/'Sources/gor/App/AppDelegate.swift';p.write_bytes(p.read_bytes()+b'//wrong')
  before=snap(project)
  try:m.record_delivery(repo,project,'main')
  except m.Refusal:
   assert kind!='exact';assert snap(project)==before;print('PASS',kind,'refusal before mutation');continue
  assert kind=='exact';assert snap(project)==current and len(current)==88
  assert len(list((project/'Sources/gor').iterdir()))==12
  park=next((project/'.gor-backups').glob('*-pre-update-retire'))
  for rel in stale:assert (park/'quarantined-inputs'/rel).read_bytes()==old[rel]
  m.record_delivery(repo,project,'main')
  for line in (park/'changes.txt').read_text().splitlines():
   k,rel=line.split('\t');p=project/rel
   if k=='added':p.unlink()
   else:p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(park/rel,p)
  assert snap(project)==old
  print('PASS exact374cpriorowner entire88source overlay,',len(stale),'staleinputs quarantined,88unique finalSwift/12stations,receipt/idempotence and exactwholeoldtree rollback')
