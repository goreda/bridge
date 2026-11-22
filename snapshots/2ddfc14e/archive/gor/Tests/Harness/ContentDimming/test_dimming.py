"""Numeric/state source port only; no luminance capture or display write."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,math,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().part_host(root,'ContentAdaptiveDimming.swift');s=_pp_split().part_text(root,'ContentAdaptiveDimming.swift');a=s
for t in ['contentTargetFloor: Float = 0.75','lumaDarkThreshold:   CGFloat = 0.13','lumaBrightThreshold: CGFloat = 0.55','lumaSmoothing: Float = 0.12','backlightInertiaDark: Float = 0.88','backlightInertiaBright: Float = 0.88','cutThresholdBase:  CGFloat = 0.14','cutThresholdScale: CGFloat = 2.2','sceneTickInterval: TimeInterval = 0.4','let isCut = hasFreshSample && cutCandidate && cutPending','ambientSceneTBoost: Double = 0.35','maxCaptureInterval = 4','calmTicksToWiden = 3','guard self.microStepGeneration == generation else { timer.invalidate(); return }','guard self.runtimeEnabled, !self.isBrightnessFading(),','guard elapsed <= self.sceneTickInterval else { return }','let inertia = target < current ? self.backlightInertiaBright : self.backlightInertiaDark','let alpha = 1.0 - pow(Double(inertia), elapsed / self.sceneTickInterval)','let lumaAlpha = hasFreshSample','// Failed capture is not a second observation of cached content.']:assert t in a,t
# the retired design (cut snap, 20 callback-count micro steps, adaptive cut duration) must stay gone
for t in ['cutMicroStepDurationFloor','cutAdaptiveSaturationInterval','if !isFading { self.setBrightness(end) }','cutMicroStep(']:assert t not in a,'retired cut micro-step design is back; review model: '+t
runtime=a[a.index('var runtimeEnabled:'):a.index('private func updateAmbientCameraFallback')]
assert 'microStepTimer?.invalidate()' not in runtime and 'microStepGeneration' not in runtime,'disable semantics changed; review model'
T=.4;INERTIA_DARK=.88;INERTIA_BRIGHT=.88
def smooth(x):
 t=min(1,max(0,(x-.13)/(.55-.13)));return t*t*(3-2*t)
def threshold(x):return .14*(.5+min(max(x,0),.6)*2.2)
def target(luma,ambient=None):return 1-max(0,smooth(luma)-(ambient*.35 if ambient is not None else 0))*.25
controls=[]
for luma in [i/100 for i in range(101)]:
 for ambient in [None,0,.5,1]:assert .75-1e-12<=target(luma,ambient)<=1
assert target(0)==1 and target(1)==.75;controls.append('404 normalized luma/ambient target bounds and endpoints')
values=[target(i/100) for i in range(101)];assert all(b<=a for a,b in zip(values,values[1:]));controls.append('more content luma never raises target under current policy')
for l in [.1,.3,.8]:assert target(l,1)>=target(l,0);controls.append('ambient support never dims further')
assert threshold(-1)==.07 and math.isclose(threshold(2),.2548);controls.append('cut threshold clamp endpoints')
class Scene:
 """Port of ContentAdaptiveDimming.tickScene luma path: time-based smoothing on fresh samples only; a cut is an observation, never a snap."""
 def __init__(self):self.luma=None;self.pending=False;self.cached=None
 def tick(self,raw,fresh=True,fresh_elapsed=T):
  if fresh:self.cached=raw
  if self.cached is None:return None
  r=self.cached;prev=self.luma if self.luma is not None else r
  cand=fresh and abs(r-prev)>threshold(prev);cut=fresh and cand and self.pending
  if fresh:self.pending=cand
  alpha=1-(1-.12)**(fresh_elapsed/T) if fresh else 0.0
  self.luma=prev+(r-prev)*alpha;return self.luma,cut
 def reset(self):self.luma=None;self.pending=False;self.cached=None
x=Scene();x.tick(0);_,cut=x.tick(1);assert not cut;_,cut=x.tick(1);assert cut;controls.append('two-candidate cut confirmation')
x=Scene();x.tick(.4);_,cut=x.tick(.4);assert not cut;controls.append('steady scene no cut')
x=Scene();x.tick(0);x.tick(1);l,cut=x.tick(1);assert cut and 0<l<.25;controls.append('confirmed cut does not snap luma; it moves by the smoothing alpha only (source: cuts are observations)')
x=Scene();x.tick(0);l1,_=x.tick(1,True,T);y=Scene();y.tick(0);l2,_=y.tick(1,True,2*T);assert l2>l1 and math.isclose(l2,1-(1-.12)**2);controls.append('luma smoothing is time-based: a double-length fresh interval equals two reference ticks')
x=Scene();x.tick(0);x.tick(.5);before=x.luma;l,_=x.tick(.9,False);assert l==before or math.isclose(l,before);controls.append('no fresh sample means zero luma alpha (held)')
class Actuator:
 def __init__(self,current):self.current=current;self.generation=0;self.writes=[];self.runtime=True;self.fading=False;self.alive=True
 def start(self):
  self.generation+=1;gen=self.generation
  def tick(target,elapsed):
   if self.generation!=gen:return 'old-generation'
   if not self.runtime or self.fading:self.alive=False;return 'invalidated'
   if elapsed>T:return 'stalled-skip'
   inertia=INERTIA_BRIGHT if target<self.current else INERTIA_DARK
   alpha=1-inertia**(elapsed/T);self.current=self.current+(target-self.current)*alpha;self.writes.append(self.current);return 'write'
  return tick
for start,end in [(.8,1.0),(1.0,.8)]:
 x=Actuator(start);tick=x.start()
 for _ in range(200):assert tick(end,T)=='write'
 assert all(min(start,end)-1e-12<=w<=max(start,end)+1e-12 for w in x.writes)
 assert all((b>=a-1e-12 if end>start else b<=a+1e-12) for a,b in zip(x.writes,x.writes[1:]));assert abs(x.current-end)<1e-6
controls.append('continuous actuator converges monotonically without overshoot in both directions')
x=Actuator(.8);tick=x.start();tick(1.0,T);up=x.current-.8;y=Actuator(1.0);t2=y.start();t2(.8,T);down=1.0-y.current;assert math.isclose(up,down) and INERTIA_BRIGHT==INERTIA_DARK;controls.append('symmetric response: up and down steps of equal span are equal (inertia .88 both directions)')
x=Actuator(.8);tick=x.start();assert tick(1.0,3*T)=='stalled-skip' and not x.writes;controls.append('stalled callback never compresses a ramp into one write')
x=Actuator(.8);old=x.start();new=x.start();assert old(1.0,T)=='old-generation' and not x.writes;assert new(1.0,T)=='write';controls.append('replaced actuator generation suppresses the old timer')
x=Actuator(.8);tick=x.start();x.fading=True;assert tick(1.0,T)=='invalidated' and not x.writes and not x.alive;controls.append('external brightness fade invalidates the timer and writes nothing')
x=Actuator(.8);tick=x.start();x.runtime=False;assert tick(1.0,T)=='invalidated' and not x.writes;controls.append('runtime disable invalidates an active actuator (source guard now tests runtimeEnabled)')
x=Scene();x.tick(.5);x.reset();assert x.cached is None and x.luma is None and not x.pending;controls.append('failed capture resets tracking; cached luma is not reused as a second observation')
reds=[]
reds.append({'case':'capture cadence widens under calm content','observed':'up to 4 scene ticks between captures, using cached content on intervening ticks (no fresh sample, zero luma alpha)','scope':'designed bounded policy; not a defect or thermal claim'})
reds.append({'case':'actuator inertia policy','observed':'bright and dark inertia are both .88; source comment calls it policy and says visual smoothness and native timing need field verification','scope':'introduced in source at 95121ce4 (2026-10-29); this harness pinned .12 until now'})
print(json.dumps({'result':'PASS bounded numeric controls and expected state characterizations (continuous-actuator model)','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(a.encode()).hexdigest(),'scope':'Python arithmetic/state port + current Swift source guards, not captured pixels/native timers/brightness hardware/UI/performance'},indent=2))
