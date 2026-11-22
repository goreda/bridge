from pathlib import Path
import tempfile,subprocess,os
s=(Path(__file__).resolve().parents[2]/'build.sh').read_text();a=s.index('    [ "$(git -C "$sync_dir" symbolic-ref',s.index('gor_update_run()'));b=s.index('    local src_root=',a);block=s[a:b]
for mode in ['empty','nonempty','wrongmessage','merge','dirty','wrongbranch','ahead','prior-merge','later-remote','evil-source-merge','changed-merge-tree']:
 with tempfile.TemporaryDirectory() as d:
  def g(*args):return subprocess.check_output(['git','-C',d,*args],stderr=subprocess.STDOUT,text=True).strip()
  g('init','-q');g('config','user.name','test');g('config','user.email','test@test');g('checkout','-qb','owner');Path(d+'/source').write_text('base');g('add','.');g('commit','-qm','base');base=g('rev-parse','HEAD');g('branch','remote-source');
  if mode=='nonempty':Path(d+'/source').write_text('local')
  g('add','.');g('commit','--allow-empty','-qm','other' if mode=='wrongmessage' else 'gor-update capture');cap=g('rev-parse','HEAD')
  if mode=='evil-source-merge':
   Path(d+'/private-source').write_text('local change');g('add','.');g('commit','-qm','local source');cap=g('rev-parse','HEAD')
  if mode=='merge':
   g('branch','other',base);g('checkout','-q','other');g('commit','--allow-empty','-qm','gor-update other');g('checkout','-q','owner');g('merge','--no-ff','--no-edit','other')
  g('checkout','-q','remote-source');Path(d+'/source').write_text('remote');g('commit','-qam','remote');remote=g('rev-parse','HEAD');g('update-ref','refs/remotes/origin/owner',remote);g('checkout','-q','owner')
  if mode=='ahead':
   g('update-ref','refs/remotes/origin/owner',base);remote=base
  if mode in ['prior-merge','later-remote','evil-source-merge','changed-merge-tree']:g('merge','--no-edit',remote)
  if mode=='changed-merge-tree':
   Path(d+'/changed').write_text('new');g('add','.');g('commit','--amend','--no-edit')
  if mode=='later-remote':
   g('checkout','-q','remote-source');Path(d+'/source').write_text('remote-newer');g('commit','-qam','remote-newer');remote=g('rev-parse','HEAD');g('update-ref','refs/remotes/origin/owner',remote);g('checkout','-q','owner')
  if mode=='dirty':Path(d+'/dirty').write_text('x')
  if mode=='wrongbranch':g('checkout','-qb','different')
  p=subprocess.run(['bash','-c','set -e\nfunction verify() {\nsync_dir="$1";branch=owner\n'+block+'\n}\nverify \"$1\"','test',d],capture_output=True,text=True)
  if mode in ['empty','ahead','prior-merge','later-remote']:
   assert p.returncode==0,p.stderr+p.stdout;g('merge-base','--is-ancestor',cap,'HEAD');g('diff','--quiet','HEAD',remote,'--')
   before=g('rev-parse','HEAD')
   again=subprocess.run(['bash','-c','set -e\nfunction verify() {\nsync_dir=\"$1\";branch=owner\n'+block+'\n}\nverify \"$1\"','test',d],capture_output=True,text=True)
   assert again.returncode==0 and g('rev-parse','HEAD')==before,(mode,again.stdout,again.stderr)
  else:assert p.returncode!=0,(mode,p.stdout)
  print('PASS actual updater block',mode,'accepted' if p.returncode==0 else 'refused-preserved')
