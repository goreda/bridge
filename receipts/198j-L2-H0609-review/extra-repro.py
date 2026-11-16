from pathlib import Path
import subprocess,tempfile,os
r=Path(tempfile.mkdtemp(prefix='h0609-extra-'));p=r/'p';(p/'Resources').mkdir(parents=True);(p/'gor.app').mkdir();(p/'.bk').mkdir();(p/'Resources/a').write_text('orig');state=r/'state';state.mkdir();(state/'a').write_text('original-state');g='/tmp/h0609-fixed/gor-update-guard.sh';env={**os.environ,'GOR_STATE_DIR':str(state)}
def run(*a):return subprocess.run(['bash',g,*map(str,a)],env=env,capture_output=True,text=True)
q=run('backup',p,p/'.bk');assert q.returncode==0,q.stderr;bk=Path(next(x.split('=',1)[1] for x in q.stdout.splitlines() if x.startswith('BACKUP_DIR=')))
(p/'Resources').rename(p/'Resources.actual');(p/'Resources').symlink_to('Resources.actual',target_is_directory=True);q=run('verify',bk,p);print('ROOT_DIRECTORY_REPLACED_SYMLINK verify',q.returncode,q.stdout)
# Only temp roots: manifest state target vs unchecked sidecar target disagreement.
other=r/'other';other.mkdir();(other/'important').write_text('do-not-touch');(bk/'state-roots.txt').write_text('0\t'+str(other)+'\n');q=run('audit-backup',bk);print('ALTERED_STATE_ROOT_SIDECAR audit',q.returncode,q.stdout);q=run('rollback',p,bk);print('rollback',q.returncode,'OTHER_IMPORTANT_EXISTS',(other/'important').exists(),'OTHER_STATE_EXISTS',(other/'a').exists(),q.stdout,q.stderr)
