from pathlib import Path
import os,tempfile,subprocess,json
r=Path(tempfile.mkdtemp(prefix='h0609-path-edge-'));g='/tmp/h0614-review/gor-update-guard.sh'
for name,mode in [('space dir','plain'),('line\nbreak','plain'),('tab\tpath','plain'),('ancestor','ancestor'),('trailing','trailing'),('relative-mpv-link','mpv')]:
 t=r/name.replace('\n','N').replace('\t','T');p=t/'p';(p/'Resources').mkdir(parents=True);(p/'gor.app').mkdir();(p/'.bk').mkdir();state=t/name;state.mkdir();(state/'a').write_text('oldstate');env={**os.environ,'GOR_STATE_DIR':str(state)}
 if mode=='ancestor':
  (t/'alias').symlink_to('.',target_is_directory=True);env['GOR_STATE_DIR']=str(t/'alias'/name)
 if mode=='trailing':env['GOR_STATE_DIR']=str(state)+'/'
 if mode=='mpv':
  (t/'link').symlink_to(name,target_is_directory=True);env.pop('GOR_STATE_DIR');env.update(MPV_HOME='link',HOME=str(t/'home'))
 q=subprocess.run(['bash',g,'backup',str(p),str(p/'.bk')],env=env,cwd=t,capture_output=True,text=True);print(repr(name),'backup',q.returncode,q.stderr.strip())
 if q.returncode==0:
  bk=Path(next(x.split('=',1)[1] for x in q.stdout.splitlines() if x.startswith('BACKUP_DIR=')));m=json.loads((bk/'update-manifest.json').read_text());print(' state_roots',m['state_roots'],'entries',len(m['state']));q=subprocess.run(['bash',g,'audit-backup',str(bk)],env=env,cwd=t,capture_output=True,text=True);print(' audit',q.returncode,q.stdout.strip())
