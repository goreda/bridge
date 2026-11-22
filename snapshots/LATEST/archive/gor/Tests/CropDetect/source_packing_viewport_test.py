#!/usr/bin/env python3
"""Compiled production geometry and controller refresh, not a Python geometry port."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os,re,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[2]
pc=(_pp_split().path(root,'PPController.swift')).read_text()
def method(signature):
 start=pc.index(signature); a=pc.index('{',start);level=1;i=a+1
 while level:
  level+=(pc[i]=='{')-(pc[i]=='}');i+=1
 return pc[start:i].replace('private func','func')
refresh=method('private func refreshStereoMenuGeometry(')
packing=method('private func refreshCropSourcePacking(')
redetect=method('private func redetectCropAfter3DOff(')
route=method('func applyThreeDState(')
legacy=re.sub(r'        if vrModeEnabled, explicitPresentation \|\| !wasEnabled \{.*?\n        \}\n','',route,flags=re.S).replace('func applyThreeDState(', 'func legacyApplyThreeDState(')
source=(lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(root)).read_text())
bounds=source[source.index('enum SourcePixelBounds'):source.index('final class SourcePixelCropScanner')]
main='''import Foundation
enum ThreeDEffect {case reapply,present}
enum Output {case off,sbs}
struct ThreeDState {let output:Output}
struct ThreeDPresentationPlan {let output:Output;static func make(state:ThreeDState)->Self {Self(output:state.output)}}
struct Gap {let value:Double}
final class VR {var applied:((ThreeDState)->Void)?;func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect]){applied?(state)};var flatUIEyeAspect:Double?=16.0/9;var cropSourcePacking=(stereo:false,topBottom:false)}
final class Detector {var stereoSBS=false,stereoTopBottom=false,viewportOnly=true,cancels=0,resets=0;func cancel(){cancels+=1};func resetLastFile(){resets+=1}}
final class Controller {
 var headTrackingEnabled=false,vrModeEnabled=true,stereoWindowOwned=false,openingFitPending=false,stereoRestorePending=false
 var stereoGeometryKey="",videoLayoutRotation:Double=0
 var vr180Controller:VR?=VR(),stereoProjectionBaseAspect:Double?,nativeVideoAspect:Double?=16.0/9
 var bounds=CGRect(x:0,y:0,width:960,height:540),cropRect:CGRect?,menuCropOwnsSelection=false,manualMenuCropAspect:Double?
 var stereoManualAspect:Double?,stereoMenuCropAspect:Double?,effectiveVrGap:Gap?=Gap(value:0)
 var appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero
 var crops:[(Double,Double,Double,Double)]=[],refits:[Double]=[],commands:[String]=[]
 var cropDetector=Detector(),offCalls=0,scanStarts=0
 func offReset(){offCalls+=1;menuCropOwnsSelection=true;stereoRestorePending=true;cropRect=nil}
 func startAutomaticCropDetection(needsRedetect:Bool=false){refreshCropSourcePacking();if !menuCropOwnsSelection {scanStarts+=1}}
 func ipcCommand(_ s:String){commands.append(s)}
 func publishSurfaceWindowCrop(x:Double,y:Double,cx:Double=0.5,cy:Double=0.5)->Bool {crops.append((x,y,cx,cy));return true}
 func refitWindowForCrop(aspect:Double){refits.append(aspect)}
 func applyVideoFrame(bounds:CGRect){}
'''+refresh+'\n'+packing+'\n'+redetect+'\n'+route+'\n'+legacy+'''
}
let routeControl=Controller();routeControl.vr180Controller!.applied={state in routeControl.vrModeEnabled = state.output != .off}
routeControl.applyThreeDState(ThreeDState(output:.sbs),[.reapply])
assert(!routeControl.menuCropOwnsSelection && !routeControl.stereoRestorePending && routeControl.scanStarts==1)
routeControl.applyThreeDState(ThreeDState(output:.off),[.reapply])
assert(!routeControl.menuCropOwnsSelection && !routeControl.stereoRestorePending && routeControl.scanStarts==2 && routeControl.offCalls>=1)
routeControl.applyThreeDState(ThreeDState(output:.sbs),[.reapply])
assert(!routeControl.menuCropOwnsSelection && !routeControl.stereoRestorePending && routeControl.scanStarts==3)
let broken=Controller();broken.vr180Controller!.applied={state in broken.vrModeEnabled = state.output != .off}
broken.legacyApplyThreeDState(ThreeDState(output:.sbs),[.reapply])
assert(broken.menuCropOwnsSelection && broken.stereoRestorePending && broken.scanStarts==0)
print("PASS actual output route releases detector+refit locks on ON and OFF (194q: OFF re-detects at once); old-route mutant stays locked")
let c=Controller();let rect=CGRect(x:0.1,y:0.15,width:0.7,height:0.6)
c.cropRect=rect;c.refreshStereoMenuGeometry(force:true)
assert(c.crops.last!.0==0.7 && c.crops.last!.1==0.6 && abs(c.crops.last!.2-0.45)<1e-10)
let aspect=c.refits.last!;assert(abs(aspect-(32.0/9*0.7/0.6))<1e-10)
for _ in 0..<100 {c.refreshStereoMenuGeometry(force:true);assert(c.crops.last!.0==0.7 && c.refits.last==aspect)}
print("PASS actual production refresh: 100 polls keep accepted off-centre crop and per-eye/gap window aspect")
c.menuCropOwnsSelection=true;c.stereoMenuCropAspect=4.0/3;c.refreshStereoMenuGeometry(force:true)
assert(c.crops.last!.0==0.75 && c.crops.last!.1==1 && c.crops.last!.2==0.5)
print("PASS manual crop owns viewport; detector never overrides manual selection")
c.menuCropOwnsSelection=false;c.cropRect=nil;c.stereoMenuCropAspect=nil;c.refreshStereoMenuGeometry(force:true)
assert(c.crops.last!.0==1 && c.crops.last!.1==1 && abs(c.refits.last!-32.0/9)<1e-10)
print("PASS reset returns original full viewport and per-eye window aspect")
for kind in ["flat-2d3d","vr360-mono","mono"] {let f=CropSourcePacking.flags(kind);assert(!f.stereo && !f.topBottom)}
for kind in ["flat-sbs","vr180"] {let f=CropSourcePacking.flags(kind);assert(f.stereo && !f.topBottom)}
for kind in ["flat-tb","vr180-tb","vr360-tb"] {let f=CropSourcePacking.flags(kind);assert(f.stereo && f.topBottom)}
c.refreshCropSourcePacking();assert(c.cropDetector.cancels==0)
c.vr180Controller!.cropSourcePacking=(true,true);c.refreshCropSourcePacking();assert(c.cropDetector.cancels==1 && c.cropDetector.resets==1)
c.refreshCropSourcePacking();assert(c.cropDetector.cancels==1)
c.vrModeEnabled=false;c.refreshCropSourcePacking();assert(c.cropDetector.stereoSBS && c.cropDetector.stereoTopBottom)
print("PASS source flags independent of output and VR enable; decoded-layout/viewport-mode changes invalidate old scan, repeated polls do not")
let w=32,h=24;var data=Data(count:w*h*2)
for y in 4..<20 {for x in 6..<26 {data[(y*w+x)*2]=200}}
let b=SourcePixelBounds.scan(data,width:w,height:h,threshold:16)!
let mono=SourcePixelBounds.outward(b,width:w,height:h,stereo:false)
let stereo=SourcePixelBounds.outward(b,width:w,height:h,stereo:true)
assert(mono.x0==6 && mono.x1==26 && mono.y0==4 && mono.y1==20)
assert(stereo.x0==0 && stereo.x1==32)
print("PASS actual pixel scanner removes mono pillarbox+letterbox; old stereo flag demonstrably keeps pillarbox")
for tb in [false,true] {
 let sw=tb ? 32:64,sh=tb ? 48:24
 var frame=Data(count:sw*sh*2)
 // One eye is all black, but the other contains a single nonblack edge pixel.
 frame[(10*sw)*2]=200
 let halves=SourcePixelBounds.scanHalves(frame,width:sw,height:sh,threshold:16,topBottom:tb)!
 let vp=SourcePixelBounds.eyeViewport(halves,width:sw,height:sh,topBottom:tb)!
 assert(vp.minX==0 && vp.minY<=10.0/24 && vp.maxY>=11.0/24)
 let center=SourcePixelBounds.Bounds(x0:8,y0:6,x1:24,y1:18)
 let united=[halves[0].union(center),halves[1].union(center)]
 assert(SourcePixelBounds.eyeViewport(united,width:sw,height:sh,topBottom:tb)!.minX==0)
 let dark=Data(count:sw*sh*2)
 assert(SourcePixelBounds.eyeViewport(SourcePixelBounds.scanHalves(dark,width:sw,height:sh,threshold:16,topBottom:tb)!,width:sw,height:sh,topBottom:tb)==nil)
 print("PASS single bright edge pixel survives other-eye-black frame and later common union, TB",tb)
}
for tb in [false,true] {
 let vw=tb ? 32:64,vh=tb ? 48:24
 let eyes=[b,SourcePixelBounds.Bounds(x0:4,y0:2,x1:28,y1:22)]
 let vp=SourcePixelBounds.eyeViewport(eyes,width:vw,height:vh,topBottom:tb)!
 assert(vp.minX==0.125 && vp.minY==2.0/24 && vp.width==0.75 && abs(vp.height-20.0/24)<1e-10)
 print("PASS common eye viewport preserves both eyes' union and inner-edge bars, TB",tb)
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(bounds+'\n'+main)
 # Imports must precede SourcePixelBounds.
 text=(p/'main.swift').read_text();(p/'main.swift').write_text('import Foundation\n'+text)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(root/'Sources/gor/Stereo/StereoGeometry.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
assert 'vr180Controller?.vrModeEnabled == true' not in pc.split('cropDetector.stereoSBS =')[-1].split('\n')[0]
assert 'self.requestRealCrop(self.cropRect ??' in pc
print('PASS head entry preserves accepted viewport; actual decoded pixels unchanged')
