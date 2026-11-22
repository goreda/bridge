"""Media path-only move: actual prior-owner overlay, quarantine and rollback."""
from pathlib import Path
import csv, hashlib, importlib.util, io, json, os, shutil, subprocess, tempfile
R=Path(__file__).resolve().parents[2];OBJECT_REPO=Path(os.environ.get('GOR_OBJECT_REPO',str(R)))
BASE='9273d61d3945c49fdf68808b995f78ff99332387'
spec=importlib.util.spec_from_file_location('media_provenance',R/'tools/gor_provenance.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
moves={'Sources/gor/GorSources/ArchiveBrowser.swift': 'Sources/gor/Media/ArchiveBrowser.swift', 'Sources/gor/GorSources/ArchiveLibrary.swift': 'Sources/gor/Media/ArchiveLibrary.swift', 'Sources/gor/GorSources/ArchiveRandom.swift': 'Sources/gor/Media/ArchiveRandom.swift', 'Sources/gor/GorSources/CDPSession.swift': 'Sources/gor/Media/CDPSession.swift', 'Sources/gor/GorSources/FileBrowser.swift': 'Sources/gor/Media/FileBrowser.swift', 'Sources/gor/GorSources/IPTV.swift': 'Sources/gor/Media/IPTV.swift', 'Sources/gor/GorSources/MagnetBrowser.swift': 'Sources/gor/Media/MagnetBrowser.swift', 'Sources/gor/GorSources/MegaStreamManager.swift': 'Sources/gor/Media/MegaStreamManager.swift', 'Sources/gor/GorSources/TorrentManager.swift': 'Sources/gor/Media/TorrentManager.swift', 'Sources/gor/GorSources/TransferResolver.swift': 'Sources/gor/Media/TransferResolver.swift', 'Sources/gor/GorSources/TransferTicketContext.swift': 'Sources/gor/Media/TransferTicketContext.swift', 'Sources/gor/GorSources/WTSessionPipeDrain.swift': 'Sources/gor/Media/WTSessionPipeDrain.swift'}
old={k:subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/'+k]) for k in moves}
for a,b in moves.items():assert old[a]==(R/b).read_bytes()
current={str(q.relative_to(R)):q.read_bytes() for q in (R/'Sources').rglob('*.swift')}
assert len(current)==88
baseline_paths=subprocess.check_output(['git','-C',str(OBJECT_REPO),'ls-tree','--full-tree','-r','--name-only',BASE+':archive/gor/Sources']).decode().splitlines()
baseline_sources={'Sources/'+q:subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/Sources/'+q]) for q in baseline_paths if q.endswith('.swift')}
assert len(baseline_sources)==88
assert sorted(hashlib.sha256(v).hexdigest() for v in baseline_sources.values())==sorted(hashlib.sha256(v).hexdigest() for v in current.values())
for source,body in baseline_sources.items():
 if source in moves:assert current[moves[source]]==body
 elif source in current:assert current[source]==body
 else:assert len([q for q,v in current.items() if v==body])==1,('later relocation must preserve exactly one whole source',source)
assert subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/Package.swift'])==(R/'Package.swift').read_bytes()
previous={k:v for k,v in current.items() if k not in moves.values()}|old
ledger=json.loads((R/'Tests/Structure/retirements.json').read_text())
for a,b in moves.items():
 h=hashlib.sha256(old[a]).hexdigest();assert p.UPDATE_RETIREMENTS[a]==(h,(b,))
 assert next(e for e in ledger['entries'] if e['path']==a)['replacements']=={b:h}
def snapshot(root):return {str(q.relative_to(root)):q.read_bytes() for q in (root/'Sources').rglob('*.swift')}
for kind in ('green','edited-old','wrong-replacement','missing-foundation'):
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
  if kind=='missing-foundation':(backup/'changes.txt').write_text('')
  elif kind!='green':
   rel=next(iter(moves)) if kind=='edited-old' else next(iter(moves.values()))
   q=project/rel;q.write_bytes(q.read_bytes()+b'\n// mutant\n')
  before=snapshot(project)
  try:p.record_delivery(repo,project,'main')
  except p.Refusal:
   assert kind!='green';assert snapshot(project)==before;assert not (project/p.RECORD).exists();print('PASS',kind,'refused before source mutation');continue
  assert kind=='green';assert snapshot(project)==current
  park=next((project/'.gor-backups').glob('*-pre-update-retire'))
  for rel,body in old.items():assert not (project/rel).exists();assert (park/'quarantined-inputs'/rel).read_bytes()==body;assert (park/rel).read_bytes()==body
  assert len(list((project/'Sources/gor/Media').glob('*.swift')))==12;assert not (project/'Sources/gor/GorSources').exists()
  p.verify_installed(repo,run('git','-C',str(repo),'rev-parse','HEAD').decode().strip(),project)
  p.record_delivery(repo,project,'main')
  for line in (park/'changes.txt').read_text().splitlines():
   kind2,rel=line.split('\t');q=project/rel
   if kind2=='added':q.unlink()
   else:q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(park/rel,q)
  assert snapshot(project)==previous
  print('PASS actual prior-owner overlay: 12 exact old paths quarantined, 88 unique Swift files, receipt/idempotence, empty GorSources pruned, exact whole-source rollback')
prior_rows=list(csv.reader(io.StringIO(subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/Tests/PlayerBackend/mpv-surface.tsv']).decode()),delimiter='\t'))
base_source_names=set('Sources/'+v for v in subprocess.check_output(['git','-C',str(OBJECT_REPO),'ls-tree','--full-tree','-r','--name-only',BASE+':archive/gor/Sources']).decode().splitlines())
actual_rows=list(csv.reader((R/'Tests/PlayerBackend/mpv-surface.tsv').open(),delimiter='\t'));changed=0;later=0;resolved={}
for row in prior_rows[1:]:
 site,line=row[2].rsplit(':',1);rel=site.removeprefix('archive/gor/')
 if rel in moves:dest=moves[rel];changed+=1
 elif rel in base_source_names and not (R/rel).exists():
  if rel not in resolved:
   body=subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/'+rel])
   matches=[path for path,content in current.items() if content==body]
   assert len(matches)==1,('later relocation is not one exact source',rel,matches)
   resolved[rel]=matches[0]
  dest=resolved[rel];later+=1
 else:continue
 body=subprocess.check_output(['git','-C',str(OBJECT_REPO),'show',BASE+':archive/gor/'+rel])
 assert body==(R/dest).read_bytes()
 assert body.splitlines()[int(line)-1]==(R/dest).read_bytes().splitlines()[int(line)-1]
 row[2]='archive/gor/'+dest+':'+line
assert actual_rows==prior_rows and changed==27
print('PASS inventory:27 station call-site path cells plus',later,'later exact-source relocations; full table equality preserves names/types/line numbers/row order and all unchanged fields')
print('MEDIA_MOVE_GATE PASS; Darwin/native not run by this test')
