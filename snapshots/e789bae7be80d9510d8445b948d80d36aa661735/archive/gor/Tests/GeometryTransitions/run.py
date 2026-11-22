import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
a=(r/'Sources/gor/App/AppDelegate.swift').read_text();p=(_pp_split().path(r,'PPController.swift')).read_text()
def method(s,key):
 start=s.index(key);b=s.index('{',start);n=1;e=b+1
 while n:
  n+=(s[e]=='{')-(s[e]=='}');e+=1
 return s[start:e].replace('private func','func')+'\n'
track=method(a,'private func trackMPVFullscreen(')
assert 'AXUIElementSetAttributeValue' not in track
refresh=method(p,'private func refreshStereoMenuGeometry(')
assert 'playerFullscreenState' not in refresh and '(full)' not in refresh
restore=method(p,'private func restoreStereoMenuFrame(')
assert 'issueFencedGeometry' not in restore and 'refitWindowForCrop(aspect: nativeVideoAspect)' in restore
code='''import Foundation
struct ProcessInfo {static var processInfo=ProcessInfo();var systemUptime=0.0}
typealias AXUIElement=Int
extension CGRect {func isAlmostEqual(to other:CGRect,epsilon:Double=1.5)->Bool {abs(minX-other.minX)<epsilon && abs(minY-other.minY)<epsilon && abs(width-other.width)<epsilon && abs(height-other.height)<epsilon}}
enum CropInvariant {static func transitionLine(_ event:String,crop:CGRect?,display:(w:Double,h:Double))->String{"[crop-guard] \(event)"}}  // stub of PPControllerMenuQueries.swift CropInvariant: only the log line, no geometry
final class NSScreen {
 static var screens:[NSScreen]=[];static var main:NSScreen?{screens.first}
 var frame:CGRect;var visibleFrame:CGRect
 init(_ f:CGRect){frame=f;visibleFrame=f}
}
final class NSWindow {
 var frame:CGRect;var screen:NSScreen?;init(_ f:CGRect,_ s:NSScreen){frame=f;screen=s}
 static func frameRect(forContentRect r:CGRect,styleMask:Int)->CGRect{r}
}
struct App {var delegate:AnyObject?};var NSApp=App()
enum GorOpeningFit {static let mpvWindowMask=0;static func clampGeometry(frame:CGRect,screen:NSScreen)->String?{"geometry"}}
final class PPController {
func synchronizeSubtitlePresentation(pictureInPicture:Bool){}
 var mediaTransitionPending=false
 var window:NSWindow?;var openingFitPending=false;var cropRect:CGRect?=nil;var appliedSourceCropAspect:Double?=nil;var videoDisplayW=1920.0;var videoDisplayH=1080.0
 var windowRefitAnchorFrame:CGRect?;var deferredWindowRefitAspect:Double?
 var cancellations=0;var messages:[String]=[]
 func cancelFitAnimation(){cancellations+=1}
 func ipcCommand(_ s:String){messages.append(s)}
 func sendGeometryUntracked(_ s:String){preconditionFailure("unexpected fallback")}
'''+method(p,'func noteUserWindowGeometry(')+method(p,'func finishFullscreenGeometryTransition(')+method(p,'private func refitWindowForCrop(')+'''
}
final class AppDelegate {
 var pictureInPictureActive=false;var overlayWin:NSWindow?
 func commitOverlayFrame(_ frame:CGRect,window:NSWindow){window.frame=frame}
 func refitPictureInPicture(aspect:Double){preconditionFailure("normal-mode test cannot refit PiP")}
 func restorePictureInPictureAfterFullscreen(){preconditionFailure("normal-mode test cannot restore PiP")}
 var controller:PPController?;var mpvWindowedFrame:CGRect?;var mpvWindowedCandidate:CGRect?;var mpvWindowedCandidateSince=0.0
 var mpvObservedFullscreen:Bool?=false;var mpvWasFullscreen=false;var mpvRestoreFrame:CGRect?;var mpvRestoreStarted=0.0
 var mpvRestoreStableFrame:CGRect?;var mpvRestoreStableSince=0.0;var mpvRestoreWritePending=false
 var mpvEntryTarget:CGRect?;var mpvEntryWritePending=false;var cachedMpvPosition:CGPoint?
 var mpvFullscreenEpoch:UInt64=0;var overlayDragGeneration:UInt64=0;var overlayDragActive=false
 var overlayPositionWriteInFlight=false;var overlayPendingPosition:CGPoint?;var overlayBufferedDelta=CGPoint.zero
 var overlayDragSettleUntil=0.0;var lastFrame=CGRect.zero
 var clampFence=GorClampFence()
 static let mpvGeometryTimeout=5.0,mpvGeometryNativeSettle=0.35,mpvGeometryFallbackSettle=0.60
 var playerFullscreenState:Bool?{mpvObservedFullscreen}
 var windowGeometryTransitionActive:Bool {mpvObservedFullscreen == true || mpvWasFullscreen || mpvRestoreFrame != nil}
 var writes:[CGRect]=[]
 func issueFencedGeometry(_ g:String,before:CGRect,target:CGRect){precondition(!windowGeometryTransitionActive);writes.append(target);controller?.window?.frame=target}
 func beginMPVFullscreenEntry(frame:CGRect?,displays:[CGRect]){prepareMPVFullscreenTransition()}
 func settleMPVFullscreenEntry(frame:CGRect,native:Bool?,displays:[CGRect],ax:Int,height:CGFloat,generation:UInt64){}
'''+method(a,'func prepareMPVFullscreenTransition(')+track+'''
 func sample(_ frame:CGRect,_ native:Bool?=false){trackMPVFullscreen(native:native,minimized:false,frame:frame,screenFrames:NSScreen.screens.map{$0.frame},ax:0,screenHeight:1080,generation:1)}
}
var cases=0
let aspects=[1.0,4.0/3,16.0/9,2.39,32.0/9,9.0/16]
let screens=[CGRect(x:0,y:0,width:1920,height:1040),CGRect(x:-2560,y:200,width:2560,height:1400),CGRect(x:1920,y:-900,width:1200,height:1800)]
NSScreen.screens=screens.map{NSScreen($0)}
for (si,screen) in NSScreen.screens.enumerated() {
 for initialAspect in aspects {
  for finalAspect in aspects {
   for mode in ["normal","sbs","vr"] {
    let d=AppDelegate(),c=PPController();d.controller=c;NSApp.delegate=d
    let initial=CGRect(x:screen.frame.minX+80,y:screen.frame.minY+90,width:700,height:700/initialAspect)
    c.window=NSWindow(initial,screen);d.mpvWindowedFrame=initial;d.lastFrame=initial
    // Begin either menu or double-click native entry: old animation is cancelled.
    d.mpvObservedFullscreen=true;d.sample(screen.frame,true)
    let old=d.writes.count
    c.refitWindowForCrop(aspect:finalAspect)
    precondition(d.writes.count==old && c.deferredWindowRefitAspect==finalAspect)
    // Mixed mode/aspect requests while fullscreen: only last intent can survive.
    for a in aspects {c.refitWindowForCrop(aspect:a)}
    c.refitWindowForCrop(aspect:finalAspect)
    d.mpvObservedFullscreen=false
    ProcessInfo.processInfo.systemUptime += 1
    d.sample(screen.frame,false)
    c.refitWindowForCrop(aspect:finalAspect)
    precondition(d.writes.isEmpty,"no intermediate fullscreen-sized refit")
    d.sample(initial,false)
    precondition(d.writes.isEmpty)
    ProcessInfo.processInfo.systemUptime += 0.8
    d.sample(initial,false)
    precondition(!d.windowGeometryTransitionActive && !d.mpvRestoreWritePending)
    precondition(d.writes.count<=1,"single final target")
    let target=d.writes.last ?? initial
    precondition(abs(target.width-finalAspect*target.height)<finalAspect+1,"final content aspect")
    precondition(screen.visibleFrame.contains(target),"screen bounds")
    precondition(abs(target.midX-screen.visibleFrame.midX)<1.5 && abs(target.midY-screen.visibleFrame.midY)<1.5,"settled fullscreen aspect refit not centered like windowed refit")
    // Repeated mixed windowed transitions must return to the same final size, not ratchet smaller.
    for a in aspects+aspects.reversed() {c.refitWindowForCrop(aspect:a)}
    c.refitWindowForCrop(aspect:finalAspect)
    let again=d.writes.last ?? initial
    precondition(abs(again.width-target.width)<1.5 && abs(again.height-target.height)<1.5,"round-trip stable size")
    // A subsequent native toggle without a content change must not add a fit/restore writer.
    let count=d.writes.count
    d.mpvObservedFullscreen=true;d.sample(screen.frame,true)
    d.mpvObservedFullscreen=false;d.sample(target,false)
    ProcessInfo.processInfo.systemUptime += 0.8;d.sample(target,false)
    precondition(d.writes.count==count,"unchanged toggle is native-only")
    precondition(c.cancellations>=2)
    cases+=1
    _=mode;_=si
   }
  }
 }
}
print("PASS \\(cases) production-method routing/math cases: normal/SBS/VR-labelled aspect matrix, 3 screens including negative origins, fullscreen deferral, latest intent, <=1 final write, final aspect/bounds, repeated mixed size stability, native-only unchanged toggles")
// Real user resize replaces the stable width proposal.
let d=AppDelegate(),c=PPController();d.controller=c;NSApp.delegate=d
c.window=NSWindow(CGRect(x:80,y:90,width:900,height:600),NSScreen.screens[0]);c.noteUserWindowGeometry(frame:c.window!.frame)
c.refitWindowForCrop(aspect:1.5);precondition(c.windowRefitAnchorFrame!.width==900)
print("PASS real user resize resets the stable width anchor")
for scenario in ["new-file-same-dimensions","format-change-during-load","failed-load","cancelled-load","quick-reopen"] {
 c.mediaTransitionPending=true;let before=d.writes.count
 for a in [2.39,1.33,1.78] {c.refitWindowForCrop(aspect:a)}
 precondition(d.writes.count==before && c.deferredWindowRefitAspect==1.78,"lost latest pending fit")
 c.mediaTransitionPending=false
 c.refitWindowForCrop(aspect:1.78)
 precondition(c.deferredWindowRefitAspect==nil,"pending fit not consumed")
 print("PASS actual production refit retains latest target during "+scenario)
}
print("UNVERIFIED native AppKit/mpv timing and pixels; mode labels share production refit routing, renderer packing is tested separately")
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test')],check=True)
print('PASS source integration: fullscreen-only stereo key removed; late AX restoration removed; mode-off uses current-content refit')
