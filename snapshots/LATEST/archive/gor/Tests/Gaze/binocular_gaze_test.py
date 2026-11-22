#!/usr/bin/env python3
"""Actual production Swift: pupil model, calibration, loss/staleness, no head fallback."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import tempfile,subprocess,os
root=Path(__file__).resolve().parents[2]
src=root/'Sources/gor/Camera/BinocularGaze.swift'
assert src.exists(),'RED: no binocular gaze model exists in 194o'
main=r'''
import Foundation
func near(_ x:Double,_ y:Double){precondition(abs(x-y)<1e-6,"\(x) != \(y)")}
let p=[12.0,10,32,10],e=[10.0,10,30,10]
let a=BinocularGazeSample.measure(t:1,pupils:p,eyes:e,widths:[10,10],apertures:[0.3,0.3],yaw:0,pitch:0)!
near(a.x,0.2);near(a.y,0)
// Joint translation, scale, roll do not turn head displacement into eye gaze.
func transform(_ v:[Double])->[Double] {
 var r:[Double]=[];let c=cos(0.7),s=sin(0.7)
 for i in stride(from:0,to:v.count,by:2){r += [30+3*(c*v[i]-s*v[i+1]),60+3*(s*v[i]+c*v[i+1])]};return r
}
let b=BinocularGazeSample.measure(t:1,pupils:transform(p),eyes:transform(e),widths:[30,30],apertures:[0.3,0.3],yaw:0,pitch:0)!
near(b.x,a.x);near(b.y,a.y)
precondition(BinocularGazeSample.measure(t:1,pupils:[],eyes:e,widths:[10,10],apertures:[0.3,0.3],yaw:0,pitch:0)==nil)
precondition(BinocularGazeSample.measure(t:1,pupils:p,eyes:e,widths:[10,10],apertures:[0,0.3],yaw:0,pitch:0)==nil)
var m=BinocularGazeCalibration();m.start();var t=0.0
for (i,target) in BinocularGazeCalibration.targets.enumerated() {
 precondition(m.state == .calibrating(i))
 for _ in 0..<48 {
  t += 1.0/30
  let sample=BinocularGazeSample(t:t,x:(Double(target.x)-0.5)*0.3,y:(Double(target.y)-0.5)*0.2,yaw:0,pitch:0)
  _=m.feed(sample,now:t)
  if m.state != .calibrating(i){break}
 }
}
precondition(m.state == .tracking)
t += 0.1
let result=m.feed(BinocularGazeSample(t:t,x:0.06,y:-0.04,yaw:0,pitch:0),now:t)!
near(Double(result.x),0.7);near(Double(result.y),0.3)
precondition(m.feed(nil,now:t+0.1)==nil)
precondition(m.feed(BinocularGazeSample(t:t,x:0,y:0,yaw:0,pitch:0),now:t+1)==nil)
t += 2
precondition(m.feed(BinocularGazeSample(t:t,x:0,y:0,yaw:0.3,pitch:0),now:t)==nil)
t += 0.1
precondition(m.feed(BinocularGazeSample(t:t,x:1,y:1,yaw:0,pitch:0),now:t)==nil)
m.stop();precondition(m.state == .off)
// Constant pupil data cannot pretend to learn screen coordinates.
m.start();t=0
for _ in 0..<400 {t += 1.0/30;_=m.feed(BinocularGazeSample(t:t,x:0,y:0,yaw:0,pitch:0),now:t)}
precondition(m.state == .failed)
print("PASS actual Swift binocular model: eye geometry invariance, paired/open requirement, five-target solve, singular rejection, loss/stale/head-away/outside suppression, stop")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(src),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
engine=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
overlay=_s3read(root/'Sources/gor/Stereo/GazeCrosshairController.swift')
view=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDCornerTune.swift'+' '):_b.index('// END relocated '+'ThreeDCornerTune.swift'+'\n')])(_s3read(_threed_split().path(root)))
assert 'onGazeUpdate?(gaze)' in engine and 'pupils:pairedPupilCoordinates' in engine
assert 'onGazeUpdate?(nil)' in engine and 'onPoseUpdate?(filtered)' in engine
assert 'HeadTracker.shared.onPoseUpdate' not in overlay
assert 'HeadTracker.shared.start(' not in overlay and 'HeadTracker.shared.stop(' not in overlay
assert 'HeadTracker.shared.isRequested' in overlay and 'view.isHiddenOrHasHiddenAncestor' in overlay and 'NSApp.isActive' in overlay
assert 'CACurrentMediaTime()-self.lastFrame>0.2' in overlay and 'marker.isHidden = !visible' in overlay
assert 'gazeCrosshair.toggle();return' in view and 'gazeCrosshair.stop()' in view
assert 'CGWarpMouseCursorPosition' not in overlay
print('PASS source integration: borrowed camera callback without independent hardware ownership, paired raw pupils only, no pose or cursor fallback, stale marker hidden, click and cleanup wired. Native AppKit/camera NOT_RUN')

# Execute actual controller toggle/stop and timer guards with AppKit boundaries doubled.
methods=overlay[overlay.index('    func toggle() {'):overlay.index('    private func render() {')]
program=r'''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
func CACurrentMediaTime()->Double{ProcessInfo.processInfo.systemUptime}
final class View {var window:Int?=1;var isHiddenOrHasHiddenAncestor=false}
final class App {var isActive=true};let NSApp=App()
final class HeadTracker {static let shared=HeadTracker();var isRequested=false;var onGazeUpdate:((Double)->Void)?}
struct Model {mutating func start(){};mutating func stop(){};mutating func feed(_ x:Double?,now:Double)->CGPoint?{nil}}
final class Gaze {
 var view:View?=View(),geometry=CGRect.zero,point:CGPoint?,model=Model(),ownsCamera=false,lastFrame=0.0,timer:Timer?
 func screenGeometry(_ v:View)->CGRect{.zero};func render(){}
'''+methods+r'''
}
let g=Gaze(),h=HeadTracker.shared
func tick(){RunLoop.main.run(until:Date().addingTimeInterval(0.15))}
g.toggle();precondition(!g.ownsCamera && h.onGazeUpdate==nil)
h.isRequested=true;g.toggle();precondition(g.ownsCamera && h.onGazeUpdate != nil)
h.isRequested=false;tick();precondition(!g.ownsCamera && h.onGazeUpdate==nil && g.timer==nil)
for mode in 0..<3 {
 h.isRequested=true;g.view!.window=1;g.view!.isHiddenOrHasHiddenAncestor=false;NSApp.isActive=true
 g.toggle();precondition(g.ownsCamera)
 if mode==0 {g.view!.isHiddenOrHasHiddenAncestor=true}
 if mode==1 {g.view!.window=nil}
 if mode==2 {NSApp.isActive=false}
 tick();precondition(!g.ownsCamera && h.onGazeUpdate==nil && g.timer==nil)
}
print("PASS actual gaze toggle/stop: no camera acquisition; no-owner,hidden,removed,inactive all clear borrowed callback/timer")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=5)
