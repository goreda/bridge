from pathlib import Path
import importlib.util,tempfile,socket,threading,json
r=Path(__file__).resolve().parents[2];path=r/'Tests/Runner/runner.py'
spec=importlib.util.spec_from_file_location('runner',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
assert m.playback_busy(pids=[]) is False
for loaded,idle,busy in [('',True,False),('movie.mp4',False,True),('paused.mp4',True,True),('',False,True)]:
 assert m.playback_busy(pids=[99],query=lambda p,k:loaded if k=='path' else idle)==busy
assert m.playback_busy(pids=[99],query=lambda p,k:(_ for _ in ()).throw(OSError()))
with tempfile.TemporaryDirectory() as td:
 t=Path(td);assert not m.owned(t);(t/'.gor-owner').write_text(m.MARKER);assert m.owned(t)
 (t/'.gor-owner').write_text('other');assert not m.owned(t)
 sock=t/'ipc'
 def server():
  with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
   s.bind(str(sock));s.listen();conn,_=s.accept()
   with conn:
    req=json.loads(conn.recv(4096));conn.sendall((json.dumps({'request_id':req['request_id'],'error':'success','data':'movie.mp4'})+'\n').encode())
 thread=threading.Thread(target=server);thread.start()
 import time
 while not sock.exists():time.sleep(.001)
 assert m.property_at(sock,'path')=='movie.mp4';thread.join()
s=path.read_text();build=(r/'build.sh').read_text()
assert build.index('--install-runner|--remove-runner')<build.index('_gor_git_bin')<build.index('exec >')
assert "env['ACTIONS_RUNNER_INPUT_TOKEN']=token" in s and "'--token'" not in s
assert "['git','credential','fill']" in s and "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL" in s
assert "'ACTIONS_RUNNER_HOOK_JOB_STARTED='" in s
assert "['/bin/launchctl','bootstrap','gui/'" in s and 'sudo' not in s
assert 'hashlib.sha256' in s and m.URL.startswith('https://github.com/actions/runner/releases/')
print('PASS Linux: production playback gate idle/loaded/paused/fail-closed, real Unix IPC, owned-folder guard, token non-argv/local-credential path, checksum pin, user launchd and pre-log build flags')
print('NOT RUN native macOS install/remove/service, live registration token, GitHub jobs or t1/l1-l4')
