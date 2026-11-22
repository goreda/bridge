import tempfile,pathlib,subprocess,importlib.util,os
s=importlib.util.spec_from_file_location('channel',str(pathlib.Path(__file__).resolve().parents[2]/'gor-capture-channel.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d);repo=p/'mac';origin=p/'origin.git';subprocess.run(['git','init','-q','--bare',str(origin)],check=True);subprocess.run(['git','init','-q',str(repo)],check=True)
 def g(*a):return subprocess.check_output(['git','-C',str(repo),*a],text=True).strip()
 g('config','user.name','fixture');g('config','user.email','fixture@example.invalid');(repo/'source').write_text('source');g('add','.');g('commit','-qm','source');g('branch','-M','source-branch');g('remote','add','origin',str(origin));g('push','-q','origin','source-branch');base=g('rev-parse','HEAD')
 for i in range(2):g('commit','--allow-empty','-qm',f'gor-update 261106-16500{i} rc=0\nagainst: fixture\nPASS capture{i}')
 tips=g('rev-parse','HEAD');old=[subprocess.check_output(['git','-C',str(repo),'show','-s','--format=%B',c]).decode() for c in g('rev-list',base+'..HEAD').splitlines()]
 names=['build-r6-candidate.sh','capture.log','sync.sh','sync.sh.install-prev','sync.sh.pre-r61-backup']
 for n in names:(repo/n).write_bytes(('untouched-'+n).encode())
 ch=m.Channel(repo);ch.migrate('source-branch',repo/'.git/gor-capture-pending')
 assert g('rev-parse','HEAD')==base
 assert all((repo/n).read_bytes()==('untouched-'+n).encode() for n in names)
 remote=ch.fetch_tip(m.BRANCH);files=g('ls-tree','-r','--name-only',remote).splitlines();assert len(files)==2
 assert all(ch.git('show',remote+':'+f).stdout.decode() in old for f in files)
 assert g('rev-parse','refs/gor-preserved/pre185-'+tips)==tips
 print('PASS actual production capture migration: two historical bytes readback, source ff-only, preserved old tip and five untracked sidecars')
# Production send failure paths against a real local bare origin, with transport seam interception.
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d);repo=p/'mac';origin=p/'origin.git';subprocess.run(['git','init','-q','--bare',str(origin)],check=True);subprocess.run(['git','init','-q',str(repo)],check=True)
 def g(*a):return subprocess.check_output(['git','-C',str(repo),*a],text=True).strip()
 g('config','user.name','fixture');g('config','user.email','fixture@example.invalid');(repo/'source').write_text('source');g('add','.');g('commit','-qm','source');g('remote','add','origin',str(origin));base=g('rev-parse','HEAD')
 f=p/'261106-165101.txt';f.write_bytes(b'capture exact bytes\n')
 class Race(m.Channel):
  attempts=0
  def git(self,*a,**kw):
   if a and a[0]=='push':
    self.attempts+=1
    if self.attempts==1:
     # A second Mac operation wins: real remote advancement before our stale push.
     blob=super().git('hash-object','-w','--stdin',input=b'other capture\n').stdout.decode().strip()
     env=self.env.copy();env['GIT_INDEX_FILE']=str(p/'other-index')
     super().git('read-tree','--empty',env=env);super().git('update-index','--add','--cacheinfo','100644,'+blob+',captures/261106-165100.txt',env=env)
     tree=super().git('write-tree',env=env).stdout.decode().strip();env.update(GIT_AUTHOR_NAME='fixture',GIT_AUTHOR_EMAIL='f@example.invalid',GIT_COMMITTER_NAME='fixture',GIT_COMMITTER_EMAIL='f@example.invalid')
     commit=super().git('commit-tree',tree,input=b'competing capture\n',env=env).stdout.decode().strip();super().git('push','origin',commit+':refs/heads/'+m.BRANCH)
   return super().git(*a,**kw)
 ch=Race(repo);ch.send(f);assert ch.attempts==2 and g('rev-parse','HEAD')==base;assert f.read_bytes()==b'capture exact bytes\n';print('PASS production nonFF refetch/rebuild next tip and source unchanged')
 class Outage(m.Channel):
  def git(self,*a,**kw):
   if a and a[0]=='push':return subprocess.CompletedProcess(a,1,b'',b'network unavailable')
   return super().git(*a,**kw)
 queued=p/'261106-165102.txt';queued.write_bytes(b'retained after failed send\n')
 try:Outage(repo).send(queued);raise AssertionError('should fail')
 except RuntimeError:pass
 assert queued.read_bytes()==b'retained after failed send\n' and g('rev-parse','HEAD')==base
 m.Channel(repo).send(queued);print('PASS outage retains exact local bytes, next send ACK, source unchanged')
