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
#!/usr/bin/env python3
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
p=(_pp_split().path(r,'PPController.swift')).read_text();m=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=(r/'Sources/gor/App/AppDelegate.swift').read_text()
def method(s,signature):
 start=s.index(signature);b=s.index('{',start);level=1;e=b+1
 while level:
  if s[e]=='{':level+=1
  elif s[e]=='}':level-=1
  e+=1
 return s[start:e].replace('private func','func')
program='''import Foundation
final class Win {var frame=CGRect(x:0,y:0,width:800,height:600)}
final class H {
 var vrModeEnabled=true;var window:Win?=Win();var bounds=CGRect(x:0,y:0,width:800,height:600)
 var stereoMenuOriginalFrame:CGRect?;var stereoProjectionBaseAspect:Double?
 var stereoRestorePending=true;var stereoManualAspect:Double?=2.39;var stereoGeometryKey="stale"
 var manualMenuCropAspect:Double?;var stereoMenuCropAspect:Double?;var nativeVideoAspect:Double?=16.0/9
 var appliedVideoFrame=CGRect.zero;var appliedVideoFrameWindowSize=CGSize.zero
 var plans:[Double]=[];var refits:[Double?]=[]
 func refreshStereoMenuGeometry(force:Bool){
  precondition(!stereoRestorePending)
  let plan=StereoMenuGeometry.plan(sourceAspect:16.0/9,aspectOverride:stereoManualAspect,cropAspect:stereoMenuCropAspect,gap:0.0125)!
  plans.append(plan.eyeAspect)
 }
 func restoreStereoMenuFrame(){stereoRestorePending=true}
 func applyVideoFrame(bounds:CGRect){}
 func refitWindowForCrop(aspect:Double?){refits.append(aspect)}
'''+method(p,'func noteAspectMenuSelection(')+'''
}
let h=H()
for ratio:Double? in [1.33,2.39,1.78,nil,2.2,nil,nil] {
 h.noteAspectMenuSelection(ratio)
 precondition(!h.stereoRestorePending && h.stereoManualAspect==ratio)
 precondition(abs(h.plans.last!-(ratio ?? 16.0/9))<0.000001)
}
print("PASS actual aspect handler repeated changes/reset: latest ratio wins; reset measured 16:9; no restore latch")
h.vrModeEnabled=false;h.noteAspectMenuSelection(2.39);h.noteAspectMenuSelection(nil)
precondition(h.refits[0]==2.39 && h.refits[1]==16.0/9)
print("PASS actual mono handler refits override then resets decoded native aspect")
h.vrModeEnabled=true;h.stereoMenuCropAspect=1.33;h.noteAspectMenuSelection(nil)
precondition(abs(h.plans.last!-1.33)<0.000001)
print("PASS aspect reset preserves independent crop, clearing only display override")
'''
with tempfile.TemporaryDirectory() as d:
 q=Path(d);geometry=(r/'Sources/gor/Stereo/StereoGeometry.swift').read_text()
 (q/'main.swift').write_text('#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n'+geometry+'\n'+program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(q/'main.swift'),'-o',str(q/'test')],check=True)
 subprocess.run([str(q/'test')],check=True)
block=method(m,'func setAspect(')
assert block.index('cmd(')<block.index('noteAspectMenuSelection')
menu=a[a.index('let aspectMenu = group("aspect ratio", in: videoMenu)'):]
assert 'populateVideoFormats(aspectMenu,crop:false)' in menu
catalog=m[m.index('func populateVideoFormats('):]
assert catalog.index('item("reset"')<catalog.index('for format in VideoFormatCatalog.formats')
# Output rows now belong to the store-backed ThreeDMenu, not removed legacy handlers.
three=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(r)).read_text())
assert 'let applied=ThreeDStore.shared.appliedOutput ?? ThreeDPresentationPlan.make(state:s).output' in three
assert 'i.state = applied == want ? .on : .off' in three
for row in ['.viewOff: .off','.viewSBS: .sbs','.viewVR180: .vr180']:assert row in three
for signature in ['private func offReset(', 'func selectVRProjection(', 'private func resetCropForOpening(']:
 b=method(p,signature)
 assert 'currentAspectPreset = .defaultAR' in b and 'video-aspect-override' in b and '"no"' in b
for signature in ['func setVRModeEnabled(', 'func setVRModeManually(']:
 assert 'if !enabled {offReset();redetectCropAfter3DOff();return}' in method(p,signature)
assert 'nativeVideoAspect = Self.rotatedAspect(width:w,height:h,rotation:videoLayoutRotation)' in p
print('PASS static reset first menu position/name, live mode checkmarks, IPC-before-geometry and file/mode reset wiring')
print('UNVERIFIED native AppKit menu pixels and live mpv transition timing; no native claim')

# New-file crop/aspect replay: compile the actual production block.
from pathlib import Path
import subprocess,shutil,tempfile,sys
r=Path(__file__).resolve().parents[2];s=(_pp_split().path(r,'PPController.swift')).read_text()
a=s.index('                if mediaTransitionNeedsFit');z=s.index('                if cropPackingNeedsRedetect',a);block=s[a:z]
pre=r'''import Foundation
final class Harness {
 var mediaTransitionNeedsFit=true,openingFitPending=true,vrModeEnabled=false
 var stereoManualAspect:Double?,manualMenuCropAspect:Double?,nativeVideoAspect:Double?,videoLayoutAspect:Double?
 var calls=[String](),ratios=[Double]()
 func applyOpeningFitIfArmed(videoW:Double,videoH:Double){if videoW>0 && videoH>0 {openingFitPending=false;calls.append("opening")}}
 func refitWindowForCrop(aspect:Double?){if !openingFitPending,let a=aspect {ratios.append(a);calls.append("refit")}}
 func refreshStereoMenuGeometry(force:Bool){precondition(!openingFitPending);calls.append("stereo")}
 func startAutomaticCropDetection(){calls.append("crop")}
 func poll(dw:Double,dh:Double,finalW:Double,finalH:Double){
'''
post=r'''}
}
func check(_ condition:Bool,_ label:String){if !condition {print("FAIL "+label);exit(1)}}
let h=Harness();h.nativeVideoAspect=16.0/9;h.videoLayoutAspect=16.0/9
h.poll(dw:0,dh:0,finalW:1920,finalH:1080)
check(h.mediaTransitionNeedsFit && h.openingFitPending && h.calls.isEmpty,"coded dimensions cannot consume fresh-file refit")
h.poll(dw:1920,dh:1080,finalW:1920,finalH:1080)
check(!h.mediaTransitionNeedsFit && !h.openingFitPending && h.calls==["opening","refit","crop"] && h.ratios==[16.0/9],"fresh display dims refit before detection")
h.poll(dw:1920,dh:1080,finalW:1920,finalH:1080);check(h.ratios.count==1,"later polls do not refit over user resize")
let n=Harness();n.poll(dw:1080,dh:1920,finalW:1080,finalH:1920)
check(n.mediaTransitionNeedsFit && n.calls.isEmpty,"missing new source aspect retains refit")
n.videoLayoutAspect=9.0/16;n.poll(dw:1080,dh:1920,finalW:1080,finalH:1920)
check(n.ratios==[9.0/16] && n.calls.last=="crop","new display aspect works before decoder aspect is available")
let v=Harness();v.vrModeEnabled=true;v.nativeVideoAspect=32.0/9
v.poll(dw:0,dh:0,finalW:3840,finalH:1080);check(v.calls.isEmpty && v.mediaTransitionNeedsFit,"stereo also waits fresh geometry")
v.poll(dw:3840,dh:1080,finalW:3840,finalH:1080);check(v.calls==["opening","stereo","crop"] && v.ratios.isEmpty,"stereo keeps per-eye owner")
print("PASS actual new-file replay block: coded-only/missing-aspect defer; fresh display ratio before crop; one-shot; decoded-aspect fallback; stereo owner")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(pre+block+post)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
