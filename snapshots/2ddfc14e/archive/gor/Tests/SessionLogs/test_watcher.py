import tempfile,subprocess,os,json,time,sys,zipfile
from pathlib import Path
from player_session_logs import Sessions
with tempfile.TemporaryDirectory() as d:
 home=Path(d);env=dict(os.environ,HOME=d)
 owner=subprocess.Popen([sys.executable,'-c','import time;time.sleep(1)'])
 cli=Path(__file__).resolve().parents[2]/'tools'/'player_session_log_cli.py'
 a=json.loads(subprocess.check_output([sys.executable,str(cli),'allocate','1'*32,str(owner.pid),'diagnostic'],env=env,text=True))
 s=Sessions(a['root']);s.admit_file('1'*32,'gor_diag.log','diagnostic');s.append('1'*32,'gor_diag.log',b'crash-evidence\n')
 subprocess.run([sys.executable,str(cli),'--root',a['root'],'watch','1'*32,str(owner.pid)],check=True,env=env,timeout=3)
 owner.wait(timeout=3)
 end=time.monotonic()+5
 while time.monotonic()<end and Path(a['root']).exists():time.sleep(.05)
 zips=list((home/'Library/Logs/gor').glob('*.zip'))
 assert len(zips)==1 and not Path(a['root']).exists()
 with zipfile.ZipFile(zips[0]) as z:
  assert b'crash-evidence' in z.read('gor_diag.log')
  assert json.loads(z.read('STATUS.json'))['status']=='INCOMPLETE'
 print('PASS actual detached watcher observes exact live parent death then emits one INCOMPLETE ZIP and removes only own raw')
