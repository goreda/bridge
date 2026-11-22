"""Actual pre-199u compiled-input delta, safe overlay retirement and retry rollback."""
from pathlib import Path
import hashlib, importlib.util, json, os, shutil, subprocess, tempfile
R=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('p',R/'tools/gor_provenance.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
REPO=os.environ.get('GOR_OBJECT_REPO',str(R));OLD='9784ad73b';DELIVERED='7dfde8b9e'
def obj(*args):return subprocess.check_output(['git','-C',REPO,*args])
def paths(ref):return set(obj('ls-tree','--full-tree','-r','--name-only',ref+':archive/gor').decode().splitlines())
extras=sorted(x for x in paths(OLD)-paths(DELIVERED) if p.is_compiled_input(x))
assert len(extras)==18
stale={x:obj('show',OLD+':archive/gor/'+x) for x in extras}
for rel,data in stale.items():assert hashlib.sha256(data).hexdigest()==p.UPDATE_RETIREMENTS[rel][0],rel
replacements={x for rel in extras for x in p.UPDATE_RETIREMENTS[rel][1]}
ENV=dict(os.environ,GIT_AUTHOR_NAME='test',GIT_AUTHOR_EMAIL='test@localhost',GIT_COMMITTER_NAME='test',GIT_COMMITTER_EMAIL='test@localhost')
def run(*args):return subprocess.check_output(args,env=ENV,stderr=subprocess.STDOUT)
def case(mode):
 with tempfile.TemporaryDirectory() as td:
  td=Path(td);repo=td/'repo';root=repo/'archive/gor';root.mkdir(parents=True)
  data={x:(R/x).read_bytes() for x in replacements}
  data.update({'Package.swift':b'// closed fixture\n','build.sh':b'echo fixture\n','Packages/p/Package.swift':b'// package\n'})
  for rel,b in data.items():f=root/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b)
  run('git','init','-qb','main',str(repo));run('git','-C',str(repo),'add','.');run('git','-C',str(repo),'commit','-qm','closed current station fixture');run('git','-C',str(repo),'update-ref','refs/remotes/origin/main','HEAD')
  project=td/'project';shutil.copytree(root,project)
  for rel,b in stale.items():f=project/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b)
  original=project/'.gor-backups/261122-201609-pre-update';original.mkdir(parents=True)
  original_journal=''.join('added\t'+x+'\n' for x in sorted(replacements))
  (original/'changes.txt').write_text(original_journal)
  if mode=='retry':
   retry=project/'.gor-backups/261122-202000-pre-update';retry.mkdir();(retry/'changes.txt').write_text('')
  if mode=='edited':(project/extras[0]).write_bytes(b'local edit\n')
  if mode=='unknown':(project/'Sources/gor/unknown.swift').write_bytes(b'let unknown=1\n')
  if mode=='symlink':
   f=project/extras[0];f.rename(td/'symlink-original');f.symlink_to(td/'symlink-original')
  if mode=='missing-foundation':(original/'changes.txt').write_text('')
  def state():return {str(f.relative_to(project)):f.read_bytes() for f in project.rglob('*') if f.is_file()}
  before=state();ok=mode in ('clean','retry')
  try:rec=p.record_delivery(repo,project,'main')
  except p.Refusal:
   assert not ok,mode
   assert before==state(),(mode,'mutation on refusal')
   print('PASS',mode,'refused without mutation');return
  assert ok,mode
  backup=next((project/'.gor-backups').glob('*-pre-update-retire'))
  for rel,b in stale.items():
   assert not (project/rel).exists(),rel
   assert (backup/rel).read_bytes()==b
   assert (backup/'quarantined-inputs'/rel).read_bytes()==b
  assert (original/'changes.txt').read_text()==original_journal
  saved=(project/p.RECORD).read_bytes();p.record_delivery(repo,project,'main');assert (project/p.RECORD).read_bytes()==saved
  # Existing rollback's journal contract restores every old source and parks additions.
  parked=td/'rollback-added'
  for line in (backup/'changes.txt').read_text().splitlines():
   kind,rel=line.split('\t');f=project/rel
   if kind=='added' and f.exists():q=parked/rel;q.parent.mkdir(parents=True,exist_ok=True);f.rename(q)
   elif kind=='deleted':f.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(backup/rel,f)
  assert all((project/x).read_bytes()==b for x,b in stale.items())
  assert all(not (project/x).exists() for x in replacements)
  print('PASS',mode,'18 exact historical inputs quarantined; backup, idempotence, one-step full rollback')
for mode in ['clean','retry','edited','unknown','symlink','missing-foundation']:case(mode)
print('PASS whole pre-199u delta: 18/18 exact paths covered, no owner diagnostics or deletes')
