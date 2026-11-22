import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(_pp_split().path(r,'PPController.swift')).read_text()
def method(key):
 st=s.index(key);e=s.index('{',st)+1;n=1
 while n:n+=(s[e]=='{')-(s[e]=='}');e+=1
 return s[st:e].replace('private func','func')+'\n'
code='''import Foundation
enum Preset {case defaultAR}
final class AppDelegate {var currentAspectPreset=Preset.defaultAR}
let NSApp=(delegate:AppDelegate(),unused:0)
final class Window {var frame=CGRect(x:50,y:50,width:800,height:450)}
final class VR {
 var vrModeEnabled=false;var isFlatStereo=false;var isTopBottom=false;var flatUIEyeAspect:Double?
 func setVRModeEnabled(_ v:Bool){vrModeEnabled=v}
 func noteManualEnabled(_ v:Bool){vrModeEnabled=v}
 func selectProjection(_ k:String){vrModeEnabled=true;isFlatStereo=k != "vr180";isTopBottom=k=="flat-tb";flatUIEyeAspect=isFlatStereo ? 16.0/9 : nil}
}
final class Detector {var stereoSBS=false;var stereoTopBottom=false;func cancel(){};func resetLastFile(){}}
final class H {
 var vr180Controller:VR?=VR();var vrModeEnabled:Bool{vr180Controller!.vrModeEnabled}
 var window:Window?=Window();var bounds=CGRect(x:0,y:0,width:800,height:450)
 var manualMenuCropAspect:Double?;var stereoManualAspect:Double?;var stereoGeometryKey="";var stereoRestorePending=false
 var stereoMenuCropAspect:Double?;var stereoProjectionBaseAspect:Double?;var stereoMenuOriginalFrame:CGRect?
 var stereoWindowOwned=false;var openingFitPending=false;var videoLayoutRotation=0.0;var nativeVideoAspect:Double?=2.0
 var effectiveVrGap:(value:Double,dummy:Int)?;var appliedVideoFrame=CGRect.zero;var appliedVideoFrameWindowSize=CGSize.zero
 var cropDetector=Detector();var messages:[String]=[];var refits:[Double?]=[]
 func ipcCommand(_ s:String){messages.append(s)};func refreshEffectiveGap(){};func applyVideoFrame(bounds:CGRect){}
 func startAutomaticCropDetection(needsRedetect:Bool){}
 func refitWindowForCrop(aspect:Double?){refits.append(aspect)}
'''+''.join(method(k) for k in ['func setVRModeEnabled(','func setVRModeManually(','func selectVRProjection(','private func refreshStereoMenuGeometry(','func noteAspectMenuSelection(','private func clearStereoMenuCrop(','private func restoreStereoMenuFrame('])+'''
}
var count=0
let h=H()
for _ in 0..<8 {
 for mode in ["flat-sbs","vr180","flat-tb","normal"] {
  let before=h.refits.count
  if mode == "normal" {h.setVRModeManually(false)} else {h.selectVRProjection(mode)}
  precondition(h.refits.count==before+1,"one mode fit, not intermediate restore plus fit")
  let expected=mode=="normal" ? 2.0 : (mode=="vr180" ? 2.0 : 32.0/9)
  precondition(abs(h.refits.last!!-expected)<0.000001,"mode current content, not old aspect")
  for a:Double? in [1.33,2.39,9.0/16,nil,nil] {
   let before=h.refits.count;h.noteAspectMenuSelection(a)
   precondition(h.refits.count==before+1)
   let eye=a ?? (mode=="normal" ? 2.0 : (mode=="vr180" ? 1.0 : 16.0/9))
   let expected=mode=="normal" ? eye : eye*2
   precondition(abs(h.refits.last!!-expected)<0.000001)
   count+=1
  }
 }
}
// Crop clear during mode-off must not publish an intermediate stereo target.
h.selectVRProjection("flat-sbs");h.stereoMenuCropAspect=1.33
let before=h.refits.count;h.setVRModeEnabled(false)
precondition(h.refits.count==before+1 && h.refits.last!==2.0)
print("PASS \\(count) actual mode/aspect handler sequences plus cropped stereo -> mono: exactly one target, latest effective content aspect, repeated/mixed/reset stable")
print("UNVERIFIED native VR renderer and menu event delivery; downstream window geometry covered by separate production-method harness")
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/Stereo/StereoGeometry.swift'),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test')],check=True)
