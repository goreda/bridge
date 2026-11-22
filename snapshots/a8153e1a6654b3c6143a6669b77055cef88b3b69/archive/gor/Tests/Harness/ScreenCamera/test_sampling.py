"""Current-tree source guards + sampling/face lifecycle model, not CG execution."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import json,hashlib
source=Path(__file__).resolve().parents[3]/'Sources/gor/Camera/ScreenCaptureEngine.swift'
s=_s3read(source)
checks=['stopColorSampling()\n        colorTimer =','withTimeInterval: 2.0','subtitleColorTimer = Timer(timeInterval: 0.1','subtitleFaceTimer = Timer(timeInterval: 0.5','if subtitleOnly && captureBounds.isNull { return }','if image == nil, !captureBounds.isNull, !subtitleOnly','guard last == nil || last != newColor','self.faceLifecycle == lifecycle','CACurrentMediaTime() - sampledAt <= 1.5','self.mpvWindowID == windowID, self.subtitleFaceTimer != nil','snapshot.generation == generation','cameraState == .running','session.removeInput(input)']
for t in checks:assert t in s,t
# Sampling routes: subtitle fast path never escalates to unrestricted capture.
def route(subtitle,bounds,image):
 if subtitle and not bounds:return 'skip'
 if not image and bounds and not subtitle:return 'full-window-fallback'
 return 'restricted' if image and bounds else 'skip'
assert route(True,False,False)=='skip'
assert route(True,True,False)=='skip'
assert route(False,True,False)=='full-window-fallback'
assert route(True,True,True)=='restricted'
# Restricted bounds conversion and independent image scales.
geometry=0
for height in [720,1080,2160]:
 for x,y,w,h in [(5,30,250,75),(80,height//3,100,120)]:
  top=height-y-h
  for factor in [.5,1,2]:
   ox,oy=x-5,top-5;cw,ch=w+10,h+10
   iw,ih=cw*factor,ch*factor
   rect=((x-ox)*iw/cw,(height-y-h-oy)*ih/ch,w*iw/cw,h*ih/ch)
   assert all(abs(a-b)<1e-9 for a,b in zip(rect,(5*factor,5*factor,w*factor,h*factor)));geometry+=1
# Face results need matching generation/window, active interest, timer and freshness.
def accept(g,current,w,window,interest,timer,age):return g==current and w==window and interest and timer and age<=1.5
assert accept(1,1,2,2,True,True,1.5)
for args in [(1,2,2,2,True,True,.1),(1,1,2,3,True,True,.1),(1,1,2,2,False,True,.1),(1,1,2,2,True,False,.1),(1,1,2,2,True,True,1.5001)]:assert not accept(*args)
print(json.dumps({'result':'PASS','source_guards':len(checks),'sampling_routes':4,'geometry_models':geometry,'face_acceptance_models':6,'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'scope':'Python source models, no CGImage pixels/multimonitor/permissions/timing proof'},indent=2))
