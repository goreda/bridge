from pathlib import Path
import tempfile,subprocess,os,json,shutil
r=Path(tempfile.mkdtemp(prefix='H0614-review-'));g=Path('/downloads/gor-update-guard-5ddcc504.sh')
def run(*a,env=None):return subprocess.run(['bash',str(g),*map(str,a)],env={**os.environ,'GOR_STATE_DIR':str(r/'state'),**(env or {})},capture_output=True,text=True)
def fixture(name):
 p=r/name;(p/'Resources').mkdir(parents=True);(p/'gor.app/Contents/MacOS').mkdir(parents=True);(p/'.bk').mkdir();(p/'gor.app/Contents/MacOS/gor').write_text('EXE');(p/'Resources/a').write_text('original');return p
def backup(p,env=None):
 q=run('backup',p,p/'.bk',env=env);assert q.returncode==0,q.stderr;return Path(next(s.split('=',1)[1] for s in q.stdout.splitlines() if s.startswith('BACKUP_DIR=')))
# Exact patched build gor_rollback restores source added entries before guard audit.
p=fixture('integration');bk=backup(p);(p/'tools').mkdir();shutil.copy(g,p/'tools/gor-update-guard.sh');(p/'new-source.swift').write_text('CURRENT SOURCE');(bk/'changes.txt').write_text('added\tnew-source.swift\n');(bk/'resources/a').write_text('TAMPERED BACKUP')
s=Path('/tmp/h0616-review/patchcheck/build.sh').read_text();f=s[s.index('gor_rollback() {'):s.index('# ── block 176 item 3')]
script=r/'exact-rollback.sh';script.write_text('project_root='+str(p)+'\nbackups_dir='+str(p/'.bk')+'\n'+f+'\ngor_rollback '+bk.name+'\n')
q=subprocess.run(['bash',str(script)],env={**os.environ,'GOR_STATE_DIR':str(r/'state')},capture_output=True,text=True);print('INTEGRATED ROLLBACK corrupt backup rc=',q.returncode,'source removed before failed audit=',not (p/'new-source.swift').exists());print(q.stdout+q.stderr)
# Direct opt-out is recorded in supplied C1 raw carrier, contradicts every path audits.
p=fixture('token');bk=backup(p);(bk/'resources/a').write_text('TAMPERED BACKUP');q=run('restore-resources',p,bk,'--gor-audited');print('DIRECT TOKEN audit bypass rc=',q.returncode,'resource=',(p/'Resources/a').read_text())
# Missing default candidate becomes present between same-ts captures.
p=fixture('new-candidate');home=r/'home';(home/'.config/mpv').mkdir(parents=True);(home/'.config/mpv/learned').write_text('state1')
env={**os.environ,'HOME':str(home),'GOR_UPDATE_TS':'same'}
for k in ['GOR_STATE_DIR','MPV_HOME','XDG_STATE_HOME']:env.pop(k,None)
q=subprocess.run(['bash',str(g),'backup',str(p),str(p/'.bk')],env=env,capture_output=True,text=True);assert q.returncode==0,q.stderr;bk=Path(next(s.split('=',1)[1] for s in q.stdout.splitlines() if s.startswith('BACKUP_DIR=')))
(home/'.local/state/mpv').mkdir(parents=True);(home/'.local/state/mpv/new-learned').write_text('NEW CANDIDATE')
q=subprocess.run(['bash',str(g),'backup',str(p),str(p/'.bk')],env=env,capture_output=True,text=True);print('NEWLY PRESENT CANDIDATE same-ts rc=',q.returncode,'reuses=', 'reusing' in q.stdout,'manifest roots=',json.load(open(bk/'update-manifest.json'))['state_roots']);print(q.stdout+q.stderr)
# Cleanup sweeps all same-index old state dirs, not just its own aside.
p=fixture('cleanup');state=r/'state';state.mkdir(exist_ok=True);(state/'learned').write_text('safe');bk=backup(p);victim=r/'state.guard-old-preserve-0';victim.mkdir();(victim/'precious').write_text('KEEP')
q=run('rollback',p,bk);print('ROLLBACK OLD-DIR SWEEP rc=',q.returncode,'unrelated old-dir deleted=',not victim.exists())
print('repro root=',r)
