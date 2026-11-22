"""Rmdir-only Sources cleanup, including an older updater's new-helper call."""
from pathlib import Path
import errno, hashlib, importlib.util, os, shutil, subprocess, tempfile
R=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('p',R/'tools/gor_provenance.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
with tempfile.TemporaryDirectory() as td:
 t=Path(td);root=t/'project';src=root/'Sources';src.mkdir(parents=True)
 for rel in ['gor/GorCore','gor/GorSubtitles','gor/GorSubtitlesUI','nested/empty/child','odd names/-dash/line\nbreak']:(src/rel).mkdir(parents=True)
 for rel in ['gor/Session/Build.swift','hidden/.keep','nonempty/owner-note.txt']:
  f=src/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b'keep bytes\n')
 outside=t/'outside';(outside/'empty').mkdir(parents=True)
 (src/'external-link').symlink_to(outside,target_is_directory=True)
 (src/'file-link').symlink_to(src/'gor/Session/Build.swift')
 (root/'.gor-backups/empty').mkdir(parents=True);(root/'record-dir/empty').mkdir(parents=True)
 before={str(f.relative_to(src)):f.read_bytes() for f in src.rglob('*') if f.is_file()}
 removed=p.prune_empty_source_directories(root)
 assert src.is_dir() and not (src/'nested').exists() and not (src/'odd names').exists()
 assert all(not (src/'gor'/n).exists() for n in ['GorCore','GorSubtitles','GorSubtitlesUI'])
 assert before=={str(f.relative_to(src)):f.read_bytes() for f in src.rglob('*') if f.is_file()}
 assert (outside/'empty').is_dir() and (src/'external-link').is_symlink() and (src/'file-link').is_symlink()
 assert (root/'.gor-backups/empty').is_dir() and (root/'record-dir/empty').is_dir()
 assert p.prune_empty_source_directories(root)==[]
 print('PASS nested/odd/hidden/nonempty/files/symlinks/root/backups/idempotence')
 (src/'refused').mkdir();original=os.rmdir
 def fail(name,*a,**kw):
  if name=='refused':raise PermissionError(errno.EACCES,'injected rmdir refusal')
  return original(name,*a,**kw)
 os.rmdir=fail
 try:
  try:p.prune_empty_source_directories(root)
  except p.Refusal as error:assert 'rmdir failed' in str(error) and 'refused' in str(error)
  else:raise AssertionError('failed rmdir was silently successful')
 finally:os.rmdir=original
 assert (src/'refused').is_dir()
 print('PASS failed rmdir reported, files and refused directory preserved')
 alias=t/'alias';alias.mkdir();(alias/'Sources').symlink_to(outside,target_is_directory=True)
 try:p.prune_empty_source_directories(alias)
 except p.Refusal:pass
 else:raise AssertionError('Sources symlink traversed')
 assert (outside/'empty').is_dir();print('PASS Sources symlink refused without traversal')
# Faithful legacy entrypoint: the old shell calls the newly overlaid helper.
with tempfile.TemporaryDirectory() as td:
 t=Path(td);repo=t/'repo';r=repo/'archive/gor';r.mkdir(parents=True)
 data={'Package.swift':b'// fixture\n','build.sh':b'echo fixture\n','Sources/gor/App/Build.swift':(R/'Sources/gor/App/Build.swift').read_bytes(),'Packages/p/Package.swift':b'// fixture\n'}
 for rel,b in data.items():f=r/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b)
 env=dict(os.environ,GIT_AUTHOR_NAME='test',GIT_AUTHOR_EMAIL='test@localhost',GIT_COMMITTER_NAME='test',GIT_COMMITTER_EMAIL='test@localhost')
 def run(*args):return subprocess.check_output(args,env=env,stderr=subprocess.STDOUT)
 run('git','init','-qb','main',str(repo));run('git','-C',str(repo),'add','.');run('git','-C',str(repo),'commit','-qm','new overlay');run('git','-C',str(repo),'update-ref','refs/remotes/origin/main','HEAD')
 project=t/'project';shutil.copytree(r,project)
 spec=importlib.util.spec_from_file_location('core',R/'Tests/Structure/core_source.py');core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)
 old=core.unit_text('BuildID.swift',R).encode();rel='Sources/gor/GorCore/BuildID.swift'
 assert hashlib.sha256(old).hexdigest()==p.UPDATE_RETIREMENTS[rel][0]
 f=project/rel;f.parent.mkdir(parents=True);f.write_bytes(old)
 (project/'Sources/gor/GorSubtitles').mkdir();(project/'Sources/gor/GorSubtitlesUI').mkdir()
 backup=project/'.gor-backups/261122-213100-pre-update';backup.mkdir(parents=True);(backup/'changes.txt').write_text('added\tSources/gor/App/Build.swift\n')
 output=run('python3',str(R/'tools/gor_provenance.py'),'record-delivery',str(repo),str(project),'main').decode()
 assert 'provenance: verified' in output and (project/p.RECORD).is_file()
 assert all(not (project/'Sources/gor'/n).exists() for n in ['GorCore','GorSubtitles','GorSubtitlesUI'])
 park=next((project/'.gor-backups').glob('*-pre-update-retire'))
 assert (park/rel).read_bytes()==old and (park/'quarantined-inputs'/rel).read_bytes()==old
 assert 'prune-empty-sources' in (R/'build.sh').read_text()
 print('PASS old-updater new-helper bootstrap: retirement quarantines old source, then empty parents pruned, receipt verified')
print('PASS empty Sources cleanup, no files deleted and no backup/root-record changes')
