#!/usr/bin/env python3
"""Execute the shipped log helper's sampler with deterministic process snapshots."""
from pathlib import Path
import subprocess,sys,tempfile,types
r=Path(__file__).resolve().parents[2]
build=(r/'build.sh').read_text()
helper=build.split("<<'GOR_SESSION_HELPER'",1)[1].split('\nGOR_SESSION_HELPER',1)[0]
namespace={};exec(compile(helper.split("if sys.argv[1]=='arm':",1)[0],'actual-helper','exec'),namespace)
record=dict(pid=11,identity='owner-birth',bundle='/Applications/gor.app')
expected='/Applications/gor.app/Contents/MacOS/gor --camera-helper --gor-owner-pid 11'
class Fake:
 def __init__(self,mode):self.mode=mode;self.calls=[];self.sampled=False
 def check_output(self,args,**kw):
  if args[:3]==['/bin/ps','-axo','pid=,ppid=,command=']:
   rows=['22 11 '+expected,'23 99 '+expected,'24 11 /other/gor --camera-helper --gor-owner-pid 11','25 11 '+expected+' --extra','26 11 /Applications/gor.app/Contents/MacOS/gor --prepare']
   if self.mode=='absent':rows=rows[1:]
   if self.mode=='multiple':rows+=['27 11 '+expected]
   return ('\n'.join(rows)).encode()
  if args[-1]=='lstart=':
   pid=args[2]
   if pid=='11':return b'owner-birth' if self.mode!='owner-reused' else b'other-owner'
   return b'child-birth' if not (self.sampled and self.mode=='child-reused') else b'other-child'
  if args[-1]=='comm=':return b'/other/gor' if self.mode=='wrong-executable' else b'/Applications/gor.app/Contents/MacOS/gor'
  if args[-1]=='ppid=,command=':
   return (('99' if self.sampled and self.mode=='reparented' else '11')+' '+expected).encode()
  raise AssertionError(args)
 def run(self,args,**kw):
  assert args[:3]==['/usr/bin/sample','22','2'] and kw['timeout']==8
  self.calls.append(args);self.sampled=True
  if self.mode=='timeout':raise subprocess.TimeoutExpired(args,8)
  Path(args[-1]).write_bytes(b'actual sample fixture')
  return types.SimpleNamespace(returncode=1 if self.mode=='failure' else 0)
for mode in ['good','wrong-executable','absent','multiple','owner-reused','child-reused','reparented','timeout','failure']:
 fake=Fake(mode);namespace['subprocess']=types.SimpleNamespace(check_output=fake.check_output,run=fake.run,DEVNULL=subprocess.DEVNULL,SubprocessError=subprocess.SubprocessError)
 entries,status=namespace['camera_helper_evidence'](record)
 if mode=='good':
  assert entries=={'gor_camera_helper_sample.txt':b'actual sample fixture'} and 'sampled pid=22 owner_pid=11' in status[0]
 else:
  assert not entries and 'NOT_RUN' in status[0],(mode,entries,status)
 if mode in ['absent','multiple','owner-reused']:assert not fake.calls
 print('PASS actual sampler '+mode)
assert "if not final:\n        extra,helper_status=camera_helper_evidence(record);entries.update(extra);status+=helper_status" in helper
assert "elif sys.argv[1]=='snapshot-current':" in helper
assert 'os.kill' not in helper and 'pkill' not in helper
print('PASS exact-owned helper sample admission, PID-reuse/reparent/absence/failure/timeout guards; no recovery or signal')
