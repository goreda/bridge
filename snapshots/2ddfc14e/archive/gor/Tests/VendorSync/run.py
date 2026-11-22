"""Exercise the repository sync tool on a real miniature source Git repo."""
from pathlib import Path
import tempfile,subprocess,importlib.util,json,hashlib
r=Path(__file__).resolve().parents[2];spec=importlib.util.spec_from_file_location('sync',r/'tools/sync-gorav-vendor.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
 root=Path(d);repo=root/'source';repo.mkdir();dest=root/'vendor';dest.mkdir()
 def g(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.DEVNULL).decode().strip()
 g('init');g('config','user.email','fixture@test.invalid');g('config','user.name','Fixture')
 def put(name,text):
  p=repo/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
 def commit():g('add','.');g('commit','-m','fixture');return g('rev-parse','HEAD')
 put('Package.swift','base target\n');put('Sources/GorAVMacShell/FrameTap.swift','tap\n');put('Sources/core.swift','old\n');base=commit();files=m.tree(repo,base)
 for p,b in files.items():x=dest/p;x.parent.mkdir(parents=True,exist_ok=True);x.write_bytes(b)
 def lock(rev=base):
  (dest/'source-lock.json').write_text(json.dumps({'repository':'local-fixture','revision':rev,'files':{p.relative_to(dest).as_posix():m.sha(p.read_bytes()) for p in dest.rglob('*') if p.is_file() and p.name!='source-lock.json'}}))
 lock();put('Sources/core.swift','new\n');put('Sources/new.swift','added\n');nextrev=commit()
 (dest/'Package.swift').write_text('local p27 target\n');lock()
 before={p.relative_to(dest).as_posix():p.read_bytes() for p in dest.rglob('*') if p.is_file()}
 try:m.refresh(repo,nextrev,dest,write=True);raise AssertionError('missing overlay refusal')
 except ValueError as e:assert 'unapproved local overlay' in str(e)
 assert before=={p.relative_to(dest).as_posix():p.read_bytes() for p in dest.rglob('*') if p.is_file()}
 receipt=m.refresh(repo,nextrev,dest,['Package.swift'],True);assert (dest/'Package.swift').read_text()=='local p27 target\n';assert receipt['p27_unchanged']['Sources/GorAVMacShell/FrameTap.swift'];assert (dest/'Sources/core.swift').read_text()=='new\n'
 first=(dest/'source-lock.json').read_bytes();m.refresh(repo,nextrev,dest,['Package.swift'],True);assert (dest/'source-lock.json').read_bytes()==first,'stable provenance after first rebase'
 put('Package.swift','upstream conflict\n');conflict=commit()
 try:m.refresh(repo,conflict,dest,['Package.swift'],True);raise AssertionError('missing conflict refusal')
 except ValueError as e:assert 'upstream/local conflict' in str(e)
 assert (dest/'source-lock.json').read_bytes()==first
 (dest/'Sources/core.swift').write_text('unrecorded')
 try:m.refresh(repo,nextrev,dest,['Package.swift'],True);raise AssertionError('missing hash refusal')
 except ValueError as e:assert 'drift' in str(e)
 print('PASS actual tool: local Package p27 overlay refused unless explicit, refusal writes nothing, preserved tap, upstream update/new file, drift rejected')
print('PASS source-only vendor sync fixture, not native acceptance')
