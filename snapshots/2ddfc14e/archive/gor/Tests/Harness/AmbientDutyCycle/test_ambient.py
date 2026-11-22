"""Clock-free ambient duty-cycle source port. No camera or scheduled callbacks."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController_Features.swift');s=p.read_text();a=s[s.index('// MARK: - Ambient camera duty-cycling'):s.index('// MARK: - Dependencies (closures back to PPController',s.index('// MARK: - Ambient camera duty-cycling'))]
for t in ['ambientCheckpointFractions: [Double] = [0, 0.125, 0.25, 0.50, 0.75]','ambientDutyCycleOnDuration: TimeInterval = 2.0','ambientFirstWindowCeiling: TimeInterval = 15.0','ambientRetryDelay: TimeInterval = 7.0','guard !ambientDutyCycleActive else { return }','guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }','firstAmbientWindowWorkItem?.cancel()','HeadTracker.shared.startAmbientOnly()','HeadTracker.shared.stopAmbientOnly()','guard fromCeiling,','guard AmbientLightProvider.shared.normalizedLevel() == nil else { return }']:assert t in a,t
opening=a[a.index('private func openAmbientWindow'):];assert 'generation' not in opening and opening.lstrip().split('\n',1)[1].lstrip().startswith('guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }'),'window ownership semantics changed; review port'
class Ambient:
 def __init__(self):self.active=False;self.runtime=True;self.fired=set();self.opened=False;self.window=0;self.retries=[];self.events=[]
 def start(self):
  if self.active:return
  self.active=True;self.events.append('first-scheduled')
 def first(self):self.fired.add(0);self.open(True)
 def stop(self):self.active=False;self.close(False);self.retries=[]
 def open(self,first=False):
  if not self.runtime or not self.active:return self.window
  self.window+=1;self.opened=True;self.events.append(('open',self.window,15 if first else 2));return self.window
 def checkpoint(self,time,duration):
  if not self.runtime or not self.active or duration<=0:return
  for i,f in enumerate([0,.125,.25,.5,.75]):
   if i not in self.fired and time/duration>=f:self.fired.add(i);self.open();return
 def close(self,ceiling,available=False):
  self.opened=False;self.events.append('close')
  if ceiling and not available:self.retries.append('retry')
controls=[]
x=Ambient();x.start();x.start();assert x.events==['first-scheduled'];x.first();assert x.opened and 0 in x.fired;controls.append('idempotent start/first window 15s source ceiling')
x.checkpoint(12.5,100);assert x.fired=={0,1} and x.events[-1][2]==2;controls.append('checkpoint normal window 2s source ceiling')
x.close(True);assert x.retries==['retry'];controls.append('ceiling without ambient schedules retry')
x=Ambient();x.close(True,True);assert not x.retries;x.close(False);assert not x.retries;controls.append('available ambient/frame close does not retry')
x=Ambient();x.checkpoint(50,100);assert not x.opened;x.start();x.runtime=False;x.checkpoint(50,100);assert not x.opened;controls.append('checkpoint runtime/active guard')
x=Ambient();x.start();x.first();x.stop();assert not x.active and not x.opened and not x.retries;controls.append('stop closes window and cancels pending work under successful cancellation assumption')
reds=[]
x=Ambient();x.start();x.first();old=x.window;x.open();new=x.window;x.close(False);assert new>old and not x.opened;reds.append({'case':'old ambient frame closure after replacement','observed':'close has no window identity and can stop new window','scope':'adversarial retained callback, native HeadTracker delivery ordering unverified'})
x=Ambient();x.start();x.first();x.stop();x.open(True);assert not x.active and not x.opened;controls.append('open itself is gated on runtime/playback/active: a begun first/retry callback after stop opens nothing (source guard at the top of openAmbientWindow)')
x=Ambient();x.start();x.first()
for _ in range(4):x.checkpoint(90,100)
assert x.fired=={0,1,2,3,4};reds.append({'case':'seek past checkpoints','observed':'one overdue checkpoint per call, four successive opens','scope':'current policy characterization, not necessarily defect'})
print(json.dumps({'result':'PASS duty-cycle controls and scoped ownership characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['actual DispatchWorkItem cancellation/native frame ordering','camera settling and consumer balance','ambient fallback source reliability','scheduled duration/thermal/privacy/UI effects'],'scope':'Python state port + current source guards, no camera/timer/Dispatch/native/UI/hardware execution'},indent=2))
