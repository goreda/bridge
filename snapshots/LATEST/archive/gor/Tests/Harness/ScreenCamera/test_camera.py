
# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import json,hashlib
s=_s3read(Path(__file__).resolve().parents[3]/'Sources/gor/Camera/ScreenCaptureEngine.swift')
for token in ['cameraState == .running','guard !permissionRequestInFlight','self.lifecycleGeneration == generation','snapshot.generation == generation','session.removeInput(input)']: assert token in s,token
checks=[]
def ok(name,value):
 assert value,name
 checks.append(name)
class Camera:
 def __init__(self):self.n=0;self.g=0;self.state='idle';self.auth='authorized';self.permission=False;self.jobs=[];self.hardware=False;self.ambient=False;self.begins=0;self.setup=True
 def ensure(self):
  if not self.n or self.state in ['starting','running']:return
  if self.auth=='authorized':self.state='starting';self.jobs.append(('start',self.g));self.begins+=1
  elif self.auth=='pending':self.state='authorizing';self.permission=True
  else:self.state='failed'
 def start(self):
  if not self.n:self.g+=1
  self.n+=1;self.ensure()
 def stop(self):
  if not self.n:return
  self.n-=1
  if self.n:return
  self.g+=1;self.state='idle';self.jobs.append(('stop',self.g))
 def grant(self):self.auth='authorized';self.permission=False;self.ensure()
 def drain(self):
  while self.jobs:
   op,g=self.jobs.pop(0)
   if op=='stop':self.hardware=False
   elif self.n and self.g==g:self.hardware=self.setup;self.state='running' if self.setup else 'failed'
 def ambient_start(self):
  if self.ambient:return
  self.ambient=True;self.start()
 def ambient_stop(self):
  if not self.ambient:return
  self.ambient=False;self.stop()
x=Camera();x.auth='denied';x.start();ok('denied not running',x.n==1 and x.state=='failed')
x.auth='authorized';x.start();x.drain();ok('second consumer retries denied',x.hardware and x.n==2)
x.stop();x.drain();ok('one consumer retains session',x.hardware);x.stop();x.drain();ok('last stop closes',not x.hardware)
x=Camera();x.auth='pending';x.start();ok('pending not running',x.state=='authorizing');x.stop();x.grant();x.drain();ok('grant after last stop no start',not x.hardware)
x=Camera();x.auth='pending';x.start();x.stop();x.start();x.grant();x.drain();ok('replacement consumes permission exactly once',x.begins==1 and x.hardware)
x=Camera();x.start();x.stop();x.start();x.drain();ok('queued start stop start identity',x.hardware and x.state=='running')
x=Camera();x.setup=False;x.start();x.drain();ok('failed setup not running',x.state=='failed');x.setup=True;x.start();x.drain();ok('second consumer retries setup',x.hardware)
x=Camera();x.ambient_start();x.ambient_start();x.drain();ok('duplicate ambient start',x.n==1);x.ambient_stop();x.ambient_stop();x.drain();ok('duplicate ambient stop',x.n==0 and not x.hardware)
x=Camera();x.start();g=x.g;x.stop();x.start();ok('stale camera observation rejected',g!=x.g)

print(json.dumps({'result':'PASS','checks':checks,'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'scope':'Python camera request/state model, no Swift AVCapture or hardware execution'},indent=2))
