"""Session path-only move: actual prior-owner overlay, quarantine and rollback."""
from pathlib import Path
import hashlib, importlib.util, json, os, shutil, subprocess, tempfile
R=Path(__file__).resolve().parents[2];OBJECT_REPO=Path(os.environ.get('GOR_OBJECT_REPO',str(R)))
BASE='13a4a7195ed0548c3656d4de6114b1e92aaaa935'
spec=importlib.util.spec_from_file_location('session_provenance',R/'tools/gor_provenance.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
names=['PlayerSessionBarrierAdapter','PlayerSessionContext','PlayerSessionDrainPlan','PlayerSessionFileTransport','PlayerSessionNativeSink','PlayerSessionPipeDrain','PlayerRuntimeResources','PlayerTorrentEndpoint','RealtimeProbe','Diag']
moves={f'Sources/gor/{"Core" if n in ["Build","Diag"] else "GorPlatformMac"}/{n}.swift':f'Sources/gor/Session/{n}.swift' for n in names}
moves['Sources/gor/GorPlatformMac/RealtimeProbe.swift']='Sources/gor/Stereo/RealtimeProbe.swift'
old={k:subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/'+k]) for k in moves}
for a,b in moves.items():assert old[a]==(R/b).read_bytes()
current={str(q.relative_to(R)):q.read_bytes() for q in (R/'Sources').rglob('*.swift')}
assert len(current)==88
previous={k:v for k,v in current.items() if k not in moves.values()}|old
ledger=json.loads((R/'Tests/Structure/retirements.json').read_text())
for a,b in moves.items():
 h=hashlib.sha256(old[a]).hexdigest();assert p.UPDATE_RETIREMENTS[a]==(h,(b,))
 assert next(e for e in ledger['entries'] if e['path']==a)['replacements']=={b:h}
def snapshot(root):return {str(q.relative_to(root)):q.read_bytes() for q in (root/'Sources').rglob('*.swift')}
for kind in ('green','edited-old','wrong-replacement'):
 with tempfile.TemporaryDirectory() as td:
  td=Path(td);repo=td/'repo';r=repo/'archive/gor';r.mkdir(parents=True)
  data=current|{'Package.swift':b'// fixture\n','build.sh':b'echo fixture\n','Packages/p/Package.swift':b'// fixture\n'}
  for rel,body in data.items():q=r/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(body)
  env=dict(os.environ,GIT_AUTHOR_NAME='test',GIT_AUTHOR_EMAIL='test@localhost',GIT_COMMITTER_NAME='test',GIT_COMMITTER_EMAIL='test@localhost')
  def run(*args):return subprocess.check_output(args,env=env,stderr=subprocess.STDOUT)
  run('git','init','-q','-b','main',str(repo));run('git','-C',str(repo),'add','.');run('git','-C',str(repo),'commit','-qm','fixture');run('git','-C',str(repo),'update-ref','refs/remotes/origin/main','HEAD')
  project=td/'project';shutil.copytree(r,project)
  for rel,body in old.items():q=project/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(body)
  backup=project/'.gor-backups/261122-210000-pre-update';backup.mkdir(parents=True)
  (backup/'changes.txt').write_text(''.join('added\t'+rel+'\n' for rel in moves.values()))
  if kind!='green':
   rel=next(iter(moves)) if kind=='edited-old' else next(iter(moves.values()))
   q=project/rel;q.write_bytes(q.read_bytes()+b'\n// mutant\n')
  before=snapshot(project)
  try:p.record_delivery(repo,project,'main')
  except p.Refusal:
   assert kind!='green';assert snapshot(project)==before;assert not (project/p.RECORD).exists();print('PASS',kind,'refused before source mutation');continue
  assert kind=='green';assert snapshot(project)==current
  park=next((project/'.gor-backups').glob('*-pre-update-retire'))
  for rel,body in old.items():assert not (project/rel).exists();assert (park/'quarantined-inputs'/rel).read_bytes()==body;assert (park/rel).read_bytes()==body
  assert (project/'Sources/gor/App/Build.swift').is_file()
  p.verify_installed(repo,run('git','-C',str(repo),'rev-parse','HEAD').decode().strip(),project)
  p.record_delivery(repo,project,'main')
  for line in (park/'changes.txt').read_text().splitlines():
   kind2,rel=line.split('\t');q=project/rel
   if kind2=='added':q.unlink()
   else:q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(park/rel,q)
  assert snapshot(project)==previous
  print('PASS actual prior-owner overlay: 10 exact old paths quarantined, 88 unique Swift files, receipt/idempotence, Build at App/ (temporary Core resolved by App tail), exact whole-source rollback')
print('SESSION_MOVE_GATE PASS; Darwin/native not run by this test')
