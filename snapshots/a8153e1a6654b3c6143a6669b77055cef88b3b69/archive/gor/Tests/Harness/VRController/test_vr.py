"""Swift-side VR command/state arithmetic; no camera or render execution."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import math,json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController_Features.swift');s=p.read_text();a=s[s.index('final class VR180Controller'):s.index('final class InputController')]
for t in ['vrYawPitchDegPerPoint: Double = 0.15','vrAutoFullscreen: Bool = false','headTrackingRestFovDeg: Double = 135.0','headLeanNudgeFovDegPerUnit: Double = -150.0','headTranslateMetersPerUnit: Double = 0.20','headZTranslateSign: Double = -1.0','baseIPDLimit: Double = 0.3','guard enabled != headTrackingEnabled else { return }','guard headTrackingEnabled, loadedVideoActive else { return }','static let headDeadZoneRad: Double = 0.004','return x < 0 ? -m : m','let vrChoice=VRRecognition.choose(remembered:nil','if desired.output == .off','let plan=ThreeDPresentationPlan.make(state:state)','if entering { setVRModeEnabled(true) }','guard width > 0, height > 0 else { return }']:assert t in a,t
assert 'vrAutoAspect' not in a and 'video-aspect-override' not in a,'VR no longer sends an aspect override (output fills the drawable; the look script owns keepaspect)'
assert 'HeadTracker.shared.onPoseUpdate = nil' in a and 'HeadTracker.shared.stop()' in a
# Historical command-arithmetic model below is not a port of the store applier.
# Current routing runtime acceptance lives in ThreeDAutoRoute/ThreeDState suites.
class VR:
 def __init__(self):self.vr=False;self.tracking=False;self.auto=False;self.ipd=0;self.events=[]
 def track(self,on):
  if on==self.tracking:return
  self.tracking=on;self.events.append('start' if on else 'stop')
 def enable(self,on):self.vr=on;self.track(on)
 def toggle_track(self):
  if not self.vr:return False
  self.track(not self.tracking);return self.tracking
 def reset(self):
  if self.vr:self.enable(False)
  self.auto=False
 def detect(self,kind):  # kind = VRRecognition.choose result kind; recognition itself is covered elsewhere, not here
  if kind=='mono':
   if self.vr:self.enable(False)
   self.auto=True;return
  if not self.vr:self.enable(True)
  self.auto=True
 def adjust(self,d):
  if self.vr:self.ipd=max(-.3,min(.3,self.ipd+d))
controls=[]
x=VR();assert not x.toggle_track() and not x.events;controls.append('tracking toggle inactive outside VR')
x.enable(True);x.track(True);assert x.events==['start'];x.enable(False);x.track(False);assert x.events==['start','stop'];controls.append('tracking start/stop idempotence')
x=VR();x.detect('sbs');assert x.vr and x.auto;x.reset();assert not x.vr and not x.tracking and not x.auto;controls.append('stereo auto enable + file reset stops tracking')
x=VR();x.detect('mono');assert not x.vr and not x.events;x.enable(True);x.detect('mono');assert not x.vr;controls.append('mono decision never enables VR and turns an auto-entered VR off')
x=VR();x.enable(True)
for _ in range(100):x.adjust(.02)
assert x.ipd==.3
for _ in range(100):x.adjust(-.02)
assert x.ipd==-.3;controls.append('base IPD clamp ±0.3')
for delta in [-100,0,100]:assert math.isclose(delta*.15*math.pi/180,math.radians(delta*.15));controls.append('mouse degree-per-point to radian mapping')
def soft(v):
 m=max(0.0,abs(v)-.004);return -m if v<0 else m
assert soft(.003)==0 and soft(-.003)==0 and math.isclose(soft(.02),.016) and math.isclose(soft(-.02),-.016);controls.append('soft dead zone: subtractive 0.004 rad, sign preserved')
assert 135-150*.1==120;controls.append('rest FOV 135 and -150 deg per unit lean')
reds=[]
assert 'width >= 4000' not in a and '>= 4000' not in a;controls.append('dimension-ratio auto-enable heuristic is gone from VR180Controller; the decision comes from VRRecognition.choose')
print(json.dumps({'result':'PASS Swift-side controls and policy characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['script consumer/clamp/reset parity','native pose sign/camera validity/units','VR auto-detection owner intent','actual projection/rendering/stereo/fullscreen/aspect pixels'],'scope':'Python state/arithmetic port + current Swift guards only; no Lua engine, camera, mpv, Swift or UI execution'},indent=2))
