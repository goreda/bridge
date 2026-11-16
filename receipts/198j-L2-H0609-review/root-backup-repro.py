from pathlib import Path
import subprocess,tempfile,os,json
r=Path(tempfile.mkdtemp(prefix='h0609-fixreview-'));p=r/'p';(p/'Resources').mkdir(parents=True);(p/'.bk').mkdir();(p/'gor.app').mkdir();(p/'Resources/a').write_text('old-resource');g='/tmp/h0609-fixed/gor-update-guard.sh';env={**os.environ,'GOR_STATE_DIR':str(r/'state')}
def run(*a):return subprocess.run(['bash',g,*map(str,a)],env=env,capture_output=True,text=True)
q=run('backup',p,p/'.bk');assert q.returncode==0,q.stderr;bk=Path(next(x.split('=',1)[1] for x in q.stdout.splitlines() if x.startswith('BACKUP_DIR=')));(p/'Resources').chmod(0o700);q=run('verify',bk,p);print('ROOT DIRECTORY0755to0700 verify',q.returncode,q.stdout)
f=p/'Resources/a';f.chmod(0o755);q=run('verify',bk,p);print('FILE MODE0644to0755 verify',q.returncode)
m=json.loads((bk/'update-manifest.json').read_text());m.pop('manifest_version');(bk/'update-manifest.json').write_text(json.dumps(m));f.write_text('overlay');(bk/'resources/a').write_text('CORRUPTED-BACKUP');env['GOR_GATE_DIR']=str(r/'missing');q=run('gate',p,p/'.stage',bk);print('LEGACY/CORRUPTED BACKUP gate',q.returncode,'Resources=',f.read_text(),q.stderr)
