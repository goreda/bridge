"""Execute actual qualified-owner source overlay through both shipped retirement paths."""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
R=Path(__file__).resolve().parents[2];OBJECT_REPO=Path(os.environ.get('GOR_OBJECT_REPO',str(R)));BASE='13a4a7195ed0548c3656d4de6114b1e92aaaa935'
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
p=load('batch_provenance',R/'tools/gor_provenance.py');late=load('batch_late_retire',R/'Tests/Structure/retire-overlay.py')
def git(*args):return subprocess.check_output(['git','-C',str(OBJECT_REPO),*args])
paths=git('ls-tree','--full-tree','-r','--name-only',BASE+':archive/gor/Sources').decode().splitlines()
previous={'Sources/'+rel:git('show',BASE+':archive/gor/Sources/'+rel) for rel in paths if rel.endswith('.swift')}
current={str(q.relative_to(R)):q.read_bytes() for q in (R/'Sources').rglob('*.swift')}
assert len(previous)==len(current)==88
for rel in set(previous)&set(current):assert previous[rel]==current[rel],('non-move source change',rel)
retired=set(previous)-set(current);added=set(current)-set(previous)
assert len(retired)==len(added) and len(retired)>0
for old in retired:
 digest,repls=p.UPDATE_RETIREMENTS[old];assert hashlib.sha256(previous[old]).hexdigest()==digest
 assert len(repls)==1 and repls[0] in added and current[repls[0]]==previous[old]
assert set(repl for old in retired for repl in p.UPDATE_RETIREMENTS[old][1])==added
ledger=json.loads((R/'Tests/Structure/retirements.json').read_text())
for old in retired:
 entry=next(e for e in ledger['entries'] if e['path']==old)
 assert entry['sha256']==hashlib.sha256(previous[old]).hexdigest()
 assert entry['replacements']=={p.UPDATE_RETIREMENTS[old][1][0]:entry['sha256']}
def snapshot(root):return {str(q.relative_to(root)):q.read_bytes() for q in (root/'Sources').rglob('*.swift')}
for mode in ('legacy-new-helper','late-json'):
 for variant in ('green','edited-old','wrong-replacement'):
  with tempfile.TemporaryDirectory() as td:
   td=Path(td);repo=td/'repo';r=repo/'archive/gor';r.mkdir(parents=True)
   data=current|{'Package.swift':b'// fixture\n','build.sh':b'echo fixture\n','Packages/p/Package.swift':b'// fixture\n'}
   for rel,body in data.items():q=r/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(body)
   env=dict(os.environ,GIT_AUTHOR_NAME='test',GIT_AUTHOR_EMAIL='test@localhost',GIT_COMMITTER_NAME='test',GIT_COMMITTER_EMAIL='test@localhost')
   def run(*args):return subprocess.check_output(args,env=env,stderr=subprocess.STDOUT)
   run('git','init','-q','-b','main',str(repo));run('git','-C',str(repo),'add','.');run('git','-C',str(repo),'commit','-qm','fixture');run('git','-C',str(repo),'update-ref','refs/remotes/origin/main','HEAD')
   project=td/'project';shutil.copytree(r,project)
   for rel in retired:q=project/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(previous[rel])
   backup=project/'.gor-backups/261122-210000-pre-update';backup.mkdir(parents=True)
   (backup/'changes.txt').write_text(''.join('added\t'+rel+'\n' for rel in sorted(added)))
   if mode=='late-json':
    q=project/'Tests/Structure/retirements.json';q.parent.mkdir(parents=True);shutil.copy2(R/'Tests/Structure/retirements.json',q)
   if variant!='green':
    rel=sorted(retired if variant=='edited-old' else added)[0];q=project/rel;q.write_bytes(q.read_bytes()+b'\n// mutant\n')
   before=snapshot(project)
   try:
    if mode=='legacy-new-helper':p.record_delivery(repo,project,'main');park=next((project/'.gor-backups').glob('*-pre-update-retire'));saved='quarantined-inputs'
    else:park=late.retire(project,project/'.gor-backups',td/'external');p.prune_empty_source_directories(project);saved='retired-inputs'
   except (p.Refusal,RuntimeError):
    assert variant!='green';assert snapshot(project)==before;print('PASS',mode,variant,'refuses before source mutation');continue
   assert variant=='green' and snapshot(project)==current
   for rel in retired:assert not (project/rel).exists();assert (park/saved/rel).read_bytes()==previous[rel]
   assert not any(q.is_dir() and not q.is_symlink() and not any(q.iterdir()) for q in (project/'Sources').rglob('*'))
   if mode=='legacy-new-helper':p.record_delivery(repo,project,'main')
   else:assert late.retire(project,project/'.gor-backups',td/'external') is None
   for line in (park/'changes.txt').read_text().splitlines():
    kind,rel=line.split('\t');q=project/rel
    if kind=='added':q.unlink()
    else:q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(park/rel,q)
   assert snapshot(project)==previous
   print('PASS',mode,'qualified13a4 real-source overlay:',len(retired),'old paths quarantined;88uniqueSwift; no empty dirs; idempotence; byte-exact whole-source rollback')
print('BATCH_OWNER_OVERLAY PASS; source/retirement fixtures, not an owner install or native execution')
