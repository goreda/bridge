import tempfile,subprocess,pathlib,os
source=(pathlib.Path(__file__).resolve().parents[2]/'build.sh').read_text()
guard=source.split("<<'GOR_LOCAL_FILES'\n",1)[1].split('\nGOR_LOCAL_FILES',1)[0]
with tempfile.NamedTemporaryFile(mode='w',suffix='.py',delete=False) as f:
 f.write(guard);guardPath=f.name
for mode in ['known','unexpected','collision','symlink','tracked','staged']:
 with tempfile.TemporaryDirectory() as d:
  def g(*a):return subprocess.check_output(['git','-C',d,*a],stderr=subprocess.STDOUT)
  g('init','-q');g('config','user.name','test');g('config','user.email','test@test');pathlib.Path(d+'/source').write_text('old');g('add','.');g('commit','-qm','base');base=g('rev-parse','HEAD').decode().strip();g('branch','remote')
  if mode=='collision':
   g('checkout','-q','remote');pathlib.Path(d+'/sync.sh').write_text('remote');g('add','.');g('commit','-qm','collision');g('checkout','-q','master')
  if mode=='symlink':os.symlink('/tmp',d+'/sync.sh')
  else:pathlib.Path(d+'/sync.sh').write_text('local preserved')
  if mode=='known':
   for p in ['capture.log','build-r6-candidate.sh','sync.sh.install-prev','sync.sh.pre-r61-backup']:pathlib.Path(d+'/'+p).write_bytes(b'private local bytes')
  if mode=='unexpected':pathlib.Path(d+'/new').write_text('preserved')
  if mode in ['tracked','staged']:
   pathlib.Path(d+'/source').write_text('edit')
   if mode=='staged':g('add','source')
  before={str(p.relative_to(d)):p.read_bytes() for p in pathlib.Path(d).iterdir() if p.is_file() and not p.is_symlink()}
  r=subprocess.run(['python',guardPath,d,'remote'],capture_output=True,text=True)
  assert (r.returncode==0)==(mode=='known'),(mode,r.stdout,r.stderr)
  after={str(p.relative_to(d)):p.read_bytes() for p in pathlib.Path(d).iterdir() if p.is_file() and not p.is_symlink()};assert before==after
  print('PASS operational guard',mode,'accepted' if r.returncode==0 else 'refused, bytes preserved')

os.unlink(guardPath)
