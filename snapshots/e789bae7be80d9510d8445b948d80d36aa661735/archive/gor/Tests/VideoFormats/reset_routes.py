"""Execute production reset methods and reset transition body with boundary spies.
Does not simulate a macOS click or claim native pixels.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];p=(_pp_split().path(r,'PPController.swift')).read_text();m=(r/'Sources/gor/UI/MenuActions.swift').read_text()
def method(text,signature):
 a=text.index(signature);b=text.index('{',a);i=b+1;n=1
 while n:
  if text[i]=='{':n+=1
  if text[i]=='}':n-=1
  i+=1
 return text[a:i]
a=m.index('struct VideoFormat {');b=m.index('\nextension AppDelegate {',a)
a0=p.index('        case .reset:',p.index('private func transitionCrop('));b0=p.index('        case .apply(',a0)
code='''import Foundation
class Detector {var canceled=false;func cancel(){canceled=true}}
class VR {func clearMeasuredEyeAspect(){}}
class Owner {
var cropDetector=Detector();var manualRedetectInFlight=true;var menuCropOwnsSelection=false
var stereoMenuCropAspect:Double?=4.0/3;var stereoManualAspect:Double?;var nativeVideoAspect:Double?=16.0/9
var cropRect:CGRect?=CGRect(x:0.1,y:0,width:0.8,height:1);var manualMenuCropAspect:Double?=4.0/3
var cropAutoRetries=1;var lastCropTransitionAt=Date();var filterMayExist=false;var osdFilterUncertain=false;var osdMutationGen=0;var removingGen=0
var sourceCropPropertyRequested=true;var cropMPV=GorCropMPV();var vr180Controller:VR?=VR()
var appliedVideoFrame=CGRect(x:1,y:1,width:1,height:1);var appliedVideoFrameWindowSize=CGSize(width:1,height:1);var bounds=CGRect.zero
var commands:[String]=[];var refits:[Double?]=[];var pip=false;var pipRefits:[Double?]=[]
func clearStereoMenuCrop(){stereoMenuCropAspect=nil}
func ipcCommand(_ command:String){commands.append(command)}
func runCropActions(_ actions:[GorCropMPV.Action]){for action in actions {if case .send(let command)=action {commands.append(command)}}}
func refitWindowForCrop(aspect:Double?){if pip{pipRefits.append(aspect)}else{refits.append(aspect)}}
func applyVideoFrame(bounds:CGRect){}
enum Transition {case reset}
func transitionCrop(_ transition:Transition,manual:Bool) {switch transition {
'''+p[a0:b0]+'''}}
'''+method(p,'    func clearOwnedCropFromMenu()')+'\n'+method(p,'    func resetCrop()')+'''
}
'''+m[a:b]+'''
for pip in [false,true] {
 for format in VideoFormatCatalog.formats {
  for ar in VideoFormatCatalog.formats {
  for route in 0...1 {
   let owner=Owner();owner.pip=pip;owner.manualMenuCropAspect=format.ratio;owner.stereoManualAspect=ar.ratio
   if route==0 {owner.resetCrop()} else {owner.clearOwnedCropFromMenu()}
   precondition(owner.cropDetector.canceled && !owner.manualRedetectInFlight && owner.menuCropOwnsSelection)
   precondition(owner.cropRect==nil && owner.manualMenuCropAspect==nil && owner.stereoMenuCropAspect==nil)
   precondition(!owner.sourceCropPropertyRequested)
   precondition(owner.commands.contains(#"{"command":["set_property","video-crop",""]}"#))
   precondition((pip ? owner.pipRefits : owner.refits).last! == ar.ratio)
   precondition(owner.appliedVideoFrame == .zero && owner.appliedVideoFrameWindowSize == .zero)
  }
  }
 }
}
print("PASS production two reset methods + reset transition: 27 crops x 27 ARs x 2 routes x PiP on/off =2916 resets; detector canceled/held, source video-crop cleared, independent AR preserved; boundary spies, not native clicks")
'''
with tempfile.TemporaryDirectory() as t:
 t=Path(t);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(t/'main.swift'),'-o',str(t/'run')],check=True)
 subprocess.run([str(t/'run')],check=True)
