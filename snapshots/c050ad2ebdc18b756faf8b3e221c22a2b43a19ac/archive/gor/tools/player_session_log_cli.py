#!/usr/bin/env python3
"""199bh process interface. No shell invocation, original-path session files.
Native ownership barriers must explicitly invoke closing/drained/finish.
Failures are one plain line on stderr with exit 2: no traceback, no paths.
"""
import argparse,json,sys,os,time,signal,base64
from player_session_logs import Sessions,SessionError,allocate,fanout_app_row,recover_orphans,start_orphan_recovery,report_delivery_failure,delivery_record_from_root
MAX_RECORD=20*1024*1024
p=argparse.ArgumentParser();p.add_argument('--root',default='/tmp');sub=p.add_subparsers(dest='action',required=True)
for name in ['begin','allocate']:
 a=sub.add_parser(name);a.add_argument('token');a.add_argument('pid',type=int);a.add_argument('producers',nargs='+')
a=sub.add_parser('register');a.add_argument('token');a.add_argument('producer')
for name in ['admit','admit-native','cap-native']:
 a=sub.add_parser(name);a.add_argument('token');a.add_argument('name');a.add_argument('producer')
a=sub.add_parser('append');a.add_argument('token');a.add_argument('name')
a=sub.add_parser('app-row') # the row is stdin only: argv is readable by other local users
a=sub.add_parser('watch');a.add_argument('token');a.add_argument('pid',type=int)
for name in ['closing','finish','crash','status']:
 a=sub.add_parser(name);a.add_argument('token')
a=sub.add_parser('drained');a.add_argument('token');a.add_argument('producer')
a=p.parse_args()
def fail(message):
 print('error: '+message,file=sys.stderr);sys.exit(2)
try:
 s=Sessions(a.root)
 if a.action=='allocate':
  allocation=allocate(a.token,a.pid,a.producers)
  try:start_orphan_recovery()
  except BaseException as error:report_delivery_failure(dict(player_id=allocation['player_id'],started=time.time()),'recovery-launch',error)
  print(json.dumps(allocation))
 elif a.action=='app-row':
  # Validate the whole length-framed record before any session is touched.
  header=sys.stdin.buffer.readline(9)
  if not header.endswith(b'\n'):fail('invalid row header')
  digits=header[:-1]
  if not digits or len(digits)>5 or not digits.isdigit():fail('invalid row header')
  count=int(digits)
  if count>65536:fail('row too large')
  payload=sys.stdin.buffer.read(count+1)
  if len(payload)<count:fail('truncated row')
  if len(payload)>count:fail('row length mismatch')
  print(fanout_app_row(payload))
 elif a.action=='begin':print(json.dumps({'state':s.begin(a.token,a.pid,a.producers)['state']}))
 elif a.action=='watch':
  # Separate local process only observes its exact parent lifetime. It writes
  # no logs while app producers are alive, and crash ZIP is always incomplete.
  child=os.fork()
  if child==0:
   os.setsid()
   null=os.open('/dev/null',os.O_RDWR)
   for fd in (0,1,2):os.dup2(null,fd)
   if null>2:os.close(null)
   signal.signal(signal.SIGHUP,signal.SIG_IGN)
   while True:
    try:
     with s.locked():r=s.checked(a.token)
     if r['state'] in ('final','incomplete'):os._exit(0)
     os.kill(a.pid,0)
    except ProcessLookupError:break
    except (SessionError,OSError) as error:
     report_delivery_failure(delivery_record_from_root(a.root),'watch-inspection',error);os._exit(0)
    time.sleep(.5)
   try:s.finish(a.token,crash=True)
   except BaseException as error:report_delivery_failure(delivery_record_from_root(a.root),'watch-crash-finish',error)
   os._exit(0)
 elif a.action=='register':s.register(a.token,a.producer)
 elif a.action=='admit':s.admit_file(a.token,a.name,a.producer)
 elif a.action=='admit-native':print(json.dumps(s.native_admission(a.token,a.name,a.producer)))
 elif a.action=='cap-native':s.native_cap_reached(a.token,a.name,a.producer)
 elif a.action=='append':
  # Full records are framed by the owning process; this protocol is not an
  # invitation for arbitrary bytes to become file names or command arguments.
  data=sys.stdin.buffer.read(MAX_RECORD+1)
  if len(data)>MAX_RECORD:fail('record too large')
  print(json.dumps({'accepted':s.append(a.token,a.name,data)}))
 elif a.action=='closing':s.closing(a.token)
 elif a.action=='drained':s.drained(a.token,a.producer)
 elif a.action=='finish':print(s.finish(a.token))
 elif a.action=='crash':print(s.finish(a.token,crash=True))
 else:
  with s.locked():r=s.checked(a.token)
  r['files']={n:{k:v for k,v in m.items() if k not in ('dev','ino')} for n,m in r['files'].items()}
  print(json.dumps(r))
except SessionError as e:fail(str(e))
except (OSError,ValueError) as e:fail('io failure '+e.__class__.__name__)
