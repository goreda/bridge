"""Brightness fade arithmetic/ownership port; never writes a display."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib,math
root=Path(__file__).resolve().parents[3];p=_pp_split().part_host(root,'BrightnessController.swift');s=_pp_split().part_text(root,'BrightnessController.swift');a=s
for t in ['fadeSteps: Int = 36','fadeStepDelay: TimeInterval = 0.05','quitFadeStepDelay: TimeInterval = 1.44 / 36','guard abs(current - target) > 0.02 else','guard self.fadeGeneration == myGeneration else {','if terminal && !self.quitFadeSettled { self.finishQuitFade() }','fadeGeneration += 1','stopFadeForTeardown()','max(0.0, min(1.0, value))']:assert t in a,t
fade=a[a.index('fileprivate func fade(to target: Float, stepCount:'):a.index('func quitFade')]
assert fade.index('guard abs(current - target) > 0.02')<fade.index('fadeGeneration += 1'),'replacement semantics changed, review port'
class Fade:
 def __init__(self,current=.5):self.value=current;self.generation=0;self.active=False;self.steps=[];self.calls=[];self.writes=[]
 def fade(self,target,name,count=36):
  start=self.value
  if abs(start-target)<=.02:self.calls.append(name);return
  self.active=True;self.generation+=1;gen=self.generation
  def tick(i):
   if self.generation!=gen:return
   t=i/count;ease=2*t*t if t<.5 else 1-(-2*t+2)**2/2;self.value=max(0,min(1,start+(target-start)*ease));self.writes.append(self.value)
   if i==count:self.active=False;self.calls.append(name)
  self.steps.append(tick);tick(1)
 def teardown(self):self.active=False;self.generation+=1
controls=[]
for start,target in [(.3,1),(1,.3),(.4,.8)]:
 x=Fade(start);x.fade(target,'done');tick=x.steps[-1]
 for i in range(2,37):tick(i)
 assert math.isclose(x.value,target) and x.calls==['done'] and not x.active
 assert all(min(start,target)<=v<=max(start,target) for v in x.writes)
 assert all((b>=a if target>start else b<=a) for a,b in zip(x.writes,x.writes[1:]))
controls.append('ascending/descending 36-step easing monotonic endpoint/completion')
x=Fade();x.fade(1,'A');old=x.steps[-1];x.fade(.3,'B');before=x.value;old(20);assert x.value==before;new=x.steps[-1]
for i in range(2,37):new(i)
assert x.calls==['B'];controls.append('nontrivial replacement cancels old generation and completion')
x=Fade();x.fade(1,'A');old=x.steps[-1];x.teardown();before=x.value;old(36);assert x.value==before and not x.calls and not x.active;controls.append('teardown generation suppresses future writes/completion')
x=Fade(.5);x.fade(.51,'small');assert not x.steps and x.calls==['small'];controls.append('near-target immediate completion with no active fade')
assert 36*.05==1.8 and math.isclose(36*(1.44/36),1.44);controls.append('scheduled durations source arithmetic, not elapsed timing')
reds=[]
x=Fade(.5);x.fade(1,'A');old=x.steps[-1];near=x.value;x.fade(near,'B');assert x.calls==['B'] and x.active;old(36);assert x.value==1 and x.calls==['B','A'];reds.append({'case':'near-target replacement during existing fade','observed':'B completes without generation invalidation; old A continues to endpoint'})
x=Fade(.5);x.fade(1,'A');old=x.steps[-1];restore=x.value;x.fade(restore,'quit');assert x.calls==['quit'];old(36);assert x.value==1;reds.append({'case':'quit restore within near-target threshold','observed':'quit completion can run while older fade remains active','scope':'requires matching saved/current target; app termination ordering unverified'})
print(json.dumps({'result':'PASS fade controls and early-return ownership counterexamples','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(a.encode()).hexdigest(),'open':['DisplayServices hardware/read failures/display identity','native Dispatch timing/quit teardown ordering','user override/drift monitor integration','Float parity and target ownership'],'scope':'Python arithmetic/generation port + current Swift guards; no Swift/display/timer/UI/hardware execution'},indent=2))
