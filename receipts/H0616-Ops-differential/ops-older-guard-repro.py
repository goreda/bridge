from pathlib import Path
import tempfile,subprocess,os,shutil
r=Path(tempfile.mkdtemp(prefix='H0616-oldguard-'));p=r/'project';(p/'Resources').mkdir(parents=True);(p/'Resources/a').write_text('original');(p/'gor.app').mkdir();(p/'tools').mkdir();(p/'.bk').mkdir();g=Path('/tmp/updater-integrity-native/ci/198s/updater/gor-update-guard.sh');shutil.copy(g,p/'tools/gor-update-guard.sh');env={**os.environ,'GOR_STATE_DIR':str(r/'state')}
q=subprocess.run(['bash',str(g),'backup',str(p),str(p/'.bk')],env=env,capture_output=True,text=True);assert q.returncode==0;bk=Path(next(s.split('=',1)[1] for s in q.stdout.splitlines() if s.startswith('BACKUP_DIR=')))
(bk/'tools').mkdir();(bk/'tools/gor-update-guard.sh').write_text('#!/bin/bash\nprintf "%s\\n" "RESTORED EARLIER GUARD EXECUTED: $*"\nexit 0\n');(bk/'changes.txt').write_text('changed\ttools/gor-update-guard.sh\n');(bk/'resources/a').write_text('CORRUPT')
s=Path('/tmp/updater-integrity-native/ci/198s/updater/build.sh').read_text();f=s[s.index('gor_rollback() {'):s.index('# ── block 176 item 3')];script=r/'exact-rollback.sh';script.write_text('project_root='+str(p)+'\nbackups_dir='+str(p/'.bk')+'\n'+f+'\ngor_rollback '+bk.name+'\n')
# Linux-only adapter for the pre-existing APFS cp -c flag. No safety logic patched.
(r/'bin').mkdir();(r/'bin/cp').write_text('#!/bin/bash\na=(); for x in "$@"; do [ "$x" = -c ] || a+=("$x"); done\nexec /bin/cp "${a[@]}"\n');(r/'bin/cp').chmod(0o755)
q=subprocess.run(['bash',str(script)],env={**env,'PATH':str(r/'bin')+':'+env['PATH']},capture_output=True,text=True);print('exact integrated rollback rc=',q.returncode);print(q.stdout+q.stderr);print('current guard replaced=',(p/'tools/gor-update-guard.sh').read_text().startswith('#!/bin/bash\nprintf'));print('root=',r)
