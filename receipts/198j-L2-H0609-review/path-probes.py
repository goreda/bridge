from pathlib import Path
import tempfile,subprocess,os
r=Path(tempfile.mkdtemp(prefix='h0609-paths-'));g='/tmp/h0609-fixed/gor-update-guard.sh'
def case(name,kind):
 t=r/name;p=t/'p';(p/'Resources').mkdir(parents=True);(p/'gor.app').mkdir();(p/'.bk').mkdir();(p/'Resources/a').write_text('orig');env={**os.environ};cwd=t
 if kind=='relative':
  (t/'state').mkdir();(t/'state/a').write_text('origstate');env['GOR_STATE_DIR']='state'
 elif kind=='symlink':
  (t/'actual').mkdir();(t/'actual/a').write_text('origstate');(t/'state').symlink_to('actual',target_is_directory=True);env['GOR_STATE_DIR']=str(t/'state')
 elif kind=='inside':env['GOR_STATE_DIR']=str(p/'Resources')
 elif kind=='overlap':
  home=t/'home';(home/'.config/mpv/child').mkdir(parents=True);(home/'.config/mpv/a').write_text('origstate');(home/'.config/mpv/child/b').write_text('origchild');env.update(HOME=str(home),MPV_HOME=str(home/'.config/mpv/child'))
 def run(*a):return subprocess.run(['bash',g,*map(str,a)],env=env,cwd=cwd,capture_output=True,text=True)
 q=run('backup',p,p/'.bk');print(name,'backup',q.returncode)
 if q.returncode:print(q.stderr);return
 bk=Path(next(x.split('=',1)[1] for x in q.stdout.splitlines() if x.startswith('BACKUP_DIR=')));q=run('audit-backup',bk);print(name,'audit',q.returncode,q.stdout.strip())
 if kind=='relative':
  cwd=t/'other';cwd.mkdir();(cwd/'state').mkdir();(cwd/'state/important').write_text('untouched')
 q=run('rollback',p,bk);print(name,'rollback',q.returncode,q.stdout[-600:],q.stderr[-300:])
 if kind=='relative':print('relative victim exists',(cwd/'state/important').exists())
 if kind=='symlink':print('state link preserved',(t/'state').is_symlink())
for k in ['relative','symlink','inside','overlap']:case(k,k)
