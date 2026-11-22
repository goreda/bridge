#!/usr/bin/python3
"""Local-only user runner installer. No token arguments, logging or bridge transport."""
import hashlib,json,os,platform,plistlib,shutil,socket,subprocess,sys,tempfile,time,urllib.request,urllib.error
from pathlib import Path
REPO='https://github.com/goreda/gorav'
SETTINGS=REPO+'/settings/actions/runners/new'
VERSION='2.338.2'
URL='https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-osx-arm64-2.338.2.tar.gz'
SHA='25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388'
ROOT=Path.home()/'Library/gor-runner'
MARKER='gor-owned-runner-v1\n'+REPO+'\n'
LABEL='com.gor.gorav-runner'
def owned(root=None):
 root=ROOT if root is None else root
 return not root.is_symlink() and (root/'.gor-owner').is_file() and (root/'.gor-owner').read_text()==MARKER

def property_at(path,prop):
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
  s.settimeout(1);s.connect(str(path));s.sendall((json.dumps({'command':['get_property',prop],'request_id':19})+'\n').encode())
  data=b''
  while len(data)<65536:
   part=s.recv(4096)
   if not part:break
   data+=part
   for line in data.splitlines():
    try:r=json.loads(line)
    except ValueError:continue
    if r.get('request_id')==19:
     if r.get('error')!='success':raise RuntimeError('IPC query failed')
     return r.get('data')
  raise RuntimeError('IPC response missing')

def gor_pids():
 result=subprocess.run(['/bin/ps','-axo','pid=,comm='],capture_output=True,text=True,check=True)
 return [int(line.strip().split(None,1)[0]) for line in result.stdout.splitlines()
         if len(line.strip().split(None,1))==2 and Path(line.strip().split(None,1)[1]).name=='gor']

def playback_busy(pids=None,query=property_at,tmp=None):
 # Unverifiable live gor is busy, not permission to launch a workload.
 try:pids=gor_pids() if pids is None else pids
 except Exception:return True
 for pid in pids:
  try:
   path=Path(tmp or tempfile.gettempdir())/('pp-'+str(pid)+'.sock')
   loaded=query(path,'path');idle=query(path,'idle-active')
   if loaded or idle is not True:return True
  except Exception:return True
 return False

def wait_idle():
 while playback_busy():time.sleep(2)

class ScopeMissing(Exception):
 pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None

def local_env():
 # Never let inherited git/curl tracing log an Authorization header or helper output.
 return {k:v for k,v in os.environ.items() if not k.startswith(('GIT_TRACE','GIT_CURL_','GIT_CONFIG_','ACTIONS_RUNNER_INPUT_')) and k not in ('GIT_ASKPASS','SSH_ASKPASS')}

def api_token(remove=False):
 env=local_env();env.update(GIT_TERMINAL_PROMPT='0',GIT_TRACE='0',GIT_TRACE_CURL='0',GIT_CURL_VERBOSE='0')
 try:
  result=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',capture_output=True,text=True,env=env,timeout=15)
  fields=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
  credential=fields.get('password','')
  if result.returncode or not credential:raise ScopeMissing()
  endpoint='remove-token' if remove else 'registration-token'
  req=urllib.request.Request('https://api.github.com/repos/goreda/gorav/actions/runners/'+endpoint,data=b'',method='POST',headers={'Authorization':'Bearer '+credential,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'})
  # API credentials must never follow a redirect to another host.
  with urllib.request.build_opener(NoRedirect()).open(req,timeout=15) as response:
   token=json.loads(response.read()).get('token','')
  if not token:raise ScopeMissing()
  return token
 except urllib.error.HTTPError as exc:
  if exc.code in (401,403,404):raise ScopeMissing() from None
  raise RuntimeError('Runner token request failed') from None
 except ScopeMissing:raise
 except Exception:raise RuntimeError('Runner credential request unavailable') from None
 finally:
  credential=None;fields=None;result=None;req=None

def config(token,remove=False):
 env=local_env();env['ACTIONS_RUNNER_INPUT_TOKEN']=token
 args=['./config.sh','remove','--unattended'] if remove else ['./config.sh','--unattended','--url',REPO,'--name','gorav-mac-'+socket.gethostname(),'--labels','self-hosted,macOS,gorav-mac','--work','_work']
 try:
  result=subprocess.run(args,cwd=ROOT,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=120)
  if result.returncode:raise RuntimeError('Runner configuration failed; local state preserved')
 finally:env.pop('ACTIONS_RUNNER_INPUT_TOKEN',None)

def registered():return (ROOT/'.runner').is_file()
def service_running():
 result=subprocess.run(['/bin/launchctl','print','gui/'+str(os.getuid())+'/'+LABEL],capture_output=True,text=True)
 return result.returncode==0 and any(line.strip().startswith('pid = ') for line in result.stdout.splitlines())

def setup_service():
 shutil.copy2(__file__,ROOT/'runner.py')
 hook=ROOT/'wait-idle.sh';hook.write_text('#!/bin/bash\nexec /usr/bin/python3 "'+str(ROOT/'runner.py')+'" wait-idle\n');hook.chmod(0o700)
 # Keep upstream configuration; replace only our own job-start hook key.
 envfile=ROOT/'.env';lines=envfile.read_text().splitlines() if envfile.exists() else []
 lines=[line for line in lines if not line.startswith('ACTIONS_RUNNER_HOOK_JOB_STARTED=')]
 envfile.write_text('\n'.join(lines+['ACTIONS_RUNNER_HOOK_JOB_STARTED='+str(hook)])+'\n')
 plist={'Label':LABEL,'ProgramArguments':['/usr/bin/nice','-n','10','/usr/bin/taskpolicy','-b','/usr/bin/python3',str(ROOT/'runner.py'),'serve'],'WorkingDirectory':str(ROOT),'RunAtLoad':True,'KeepAlive':True,'Nice':10,'ProcessType':'Background','LowPriorityIO':True,'StandardOutPath':str(ROOT/'service.log'),'StandardErrorPath':str(ROOT/'service-error.log')}
 with (ROOT/'service.plist').open('wb') as f:plistlib.dump(plist,f)
 subprocess.run(['/bin/launchctl','bootstrap','gui/'+str(os.getuid()),str(ROOT/'service.plist')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)

def install():
 if platform.system()!='Darwin' or platform.machine()!='arm64':raise RuntimeError('Requires macOS arm64')
 if ROOT.exists() or ROOT.is_symlink():
  if not owned():raise RuntimeError('Refusing unowned ~/Library/gor-runner')
  if registered():
   if service_running():return
   subprocess.run(['/bin/launchctl','bootout','gui/'+str(os.getuid()),str(ROOT/'service.plist')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   setup_service();return
 # Acquire before creating anything, so a scope refusal changes no local files.
 token=api_token()
 try:
  if not ROOT.exists():
   ROOT.mkdir(mode=0o700,parents=True);(ROOT/'.gor-owner').write_text(MARKER)
  if not (ROOT/'config.sh').is_file():
   archive=ROOT/'runner.tar.gz'
   with urllib.request.urlopen(URL,timeout=60) as response,archive.open('wb') as f:shutil.copyfileobj(response,f)
   if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA:raise RuntimeError('Official runner checksum mismatch; no code executed')
   import tarfile
   with tarfile.open(archive) as tar:
    for item in tar.getmembers():
     if item.name.startswith('/') or '..' in Path(item.name).parts:raise RuntimeError('Unsafe archive path')
     if (item.issym() or item.islnk()) and (item.linkname.startswith('/') or '..' in Path(item.linkname).parts):raise RuntimeError('Unsafe archive link')
    tar.extractall(ROOT)
  config(token);(ROOT/'.gor-registered').write_text('registered\n');setup_service()
 finally:token=None
 print('runner: registered for goreda/gorav; hosted quota routing keeps it idle until needed')

def on_ac():
 try:
  p=subprocess.run(['/usr/bin/pmset','-g','batt'],capture_output=True,text=True,timeout=5)
  return p.returncode==0 and "'AC Power'" in p.stdout
 except Exception:return False

def serve():
 if not owned():raise RuntimeError('Runner ownership marker missing')
 while True:
  wait_idle()
  # No sleep assertion on battery; plugged-in changes are checked while listening.
  wake=None
  p=subprocess.Popen(['./run.sh','--once'],cwd=ROOT)
  try:
   while p.poll() is None:
    if on_ac():
     if wake is None or wake.poll() is not None:wake=subprocess.Popen(['/usr/bin/caffeinate','-i','-s'])
    elif wake is not None:
     wake.terminate();wake.wait();wake=None
    time.sleep(2)
  finally:
   if wake is not None:wake.terminate();wake.wait()
  time.sleep(3)

def remove():
 if not owned():raise RuntimeError('Refusing removal: folder was not created by this installer')
 token=api_token(remove=True) if registered() else None
 try:
  service=ROOT/'service.plist'
  if service.exists():subprocess.run(['/bin/launchctl','bootout','gui/'+str(os.getuid()),str(service)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  if token:config(token,remove=True)
 finally:token=None
 # Failed unregister raises before deletion. Never remove an unmarked folder.
 if not owned():raise RuntimeError('Ownership changed; refusing removal')
 shutil.rmtree(ROOT)
 print('runner: unregistered; only owned ~/Library/gor-runner removed')

def main():
 os.umask(0o077)
 command=sys.argv[1] if len(sys.argv)==2 else ''
 if command=='install':install()
 elif command=='remove':remove()
 elif command=='serve':serve()
 elif command=='wait-idle':wait_idle()
 else:raise RuntimeError('Expected install/remove/serve/wait-idle')
if __name__=='__main__':
 try:main()
 except ScopeMissing:print('runner: credential scope missing')
 except Exception:
  print('runner: setup unavailable; local state preserved',file=sys.stderr)
  sys.exit(1)
