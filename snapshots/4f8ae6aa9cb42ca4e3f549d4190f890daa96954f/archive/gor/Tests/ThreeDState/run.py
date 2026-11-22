"""Compile and execute the production pure reducer on Linux or Mac. No Python policy mirror."""
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
from pathlib import Path
import os, subprocess, tempfile
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
overlay='#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n'
with tempfile.TemporaryDirectory() as folder:
    binary=Path(folder)/'state-test'
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(Path(__file__).with_name('main.swift')),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)
    production=_sec_file(root,'ThreeDState.swift')
    guard='if output != .off, film.output == output, film.explicitOutput == output { return (state, []) }'
    mutant=production.read_text();assert guard in mutant
    production.write_text(mutant.replace(guard,''))
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(production),str(Path(__file__).with_name('main.swift')),'-o',str(binary)],check=True)
    rejected=subprocess.run([str(binary)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=20)
    assert rejected.returncode != 0, 'same-output crop-reset mutant escaped'
    print('PASS repeated-output crop-reset negative control rejected')


# 191t T1: execute the production geometry body with real circular-frame pixels.
with tempfile.TemporaryDirectory() as folder:
    p=Path(folder)
    source=(root/'Sources/gor/Stereo/StereoDetection.swift').read_text()
    (p/'Geometry.swift').write_text(overlay+source[:source.index('    static func inspect')]+'}\n')
    (p/'StereoGeometry.swift').write_text(overlay+(root/'Sources/gor/Stereo/StereoGeometry.swift').read_text())
    (p/'main.swift').write_text(r'''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
let meta=Data(#"{"streams":[{"width":3840,"height":1920}]}"#.utf8)
var pixels=[UInt8](repeating:0,count:320*90)
for y in 0..<90 {for x in 0..<320 {
 let eyeX=Double(x%160)/160-0.5,eyeY=Double(y)/90-0.5
 if eyeX*eyeX+eyeY*eyeY<0.21 {pixels[y*320+x]=180}
}}
let frames=Array(repeating:Data(pixels),count:4)
precondition(SBSEyeCrop.circularEdge(frames,width:320,height:90))
var mono=VRProjectionProbe.Result(status:"metadataAbsent")
VRProjectionProbe.applyGeometry(&mono,frames:frames,metadata:meta)
precondition(mono.circularProfile && mono.projection == nil && mono.suggestedLayout == "vr180?")
var pair=VRProjectionProbe.Result(status:"metadataAbsent");pair.suggestedLayout="side-by-side"
VRProjectionProbe.applyGeometry(&pair,frames:frames,metadata:meta)
precondition(pair.circularProfile && pair.projection == "vr180")
var tagged=VRProjectionProbe.Result(status:"projectionMetadata");tagged.projection="vr360-mono"
VRProjectionProbe.applyGeometry(&tagged,frames:frames,metadata:meta)
precondition(tagged.projection == "vr360-mono")
print("PASS 191t T1 actual circular geometry alone is advisory, matched SBS promotes, metadata preserved")
''')
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'Geometry.swift'),str(p/'StereoGeometry.swift'),str(p/'main.swift'),'-o',str(p/'geometry')],check=True)
    subprocess.run([str(p/'geometry')],check=True)

# Live effects must not reach the coordinator hard-load path, but same-output
# explicit recovery remains available. Compile the production method verbatim.
co=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(root)).read_text())
a=co.index('    func applyStoreOutput(');b=co.index('    func start()',a)
method=co[a:b]
transition=co[co.index('    func setMediaTransitionPending('):co.index('    private var storeOutput=')]
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)
 source='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
final class ThreeDSubtitleDepth {static let shared=ThreeDSubtitleDepth();func end(){}}
final class RevisionProbe {var count=0;func invalidate(){count += 1}}
final class Probe {
let revision=RevisionProbe()
var boundFilmID:FilmID?,lastGood:[Int:Int]=[:],showing:Int?,showingURL:URL?,lastFilm:URL?,indexCache:Int?,renderPrefs:Int?,observedDepthKeys:[Int:Int]=[:],lastPTS:Double?
var cachePin:Int?,cachePinKey:String?
var mediaTransitionPending=false
var preparedLoadTask:Task<Void,Never>?,preparedLoadID=UUID(),preparedLoadPending=false
var storeOutput=ThreeDOutput.off,cancelFlag=false,loads=0
var film2D:URL?=URL(fileURLWithPath:"/fixture")
func playhead()->Double? {1}
func backTo2D(_ value:Double,filmURL:URL?) {loads += 1}
''' + method + transition + '''
}
let c=Probe()
let id=FilmID(rawValue:"live")
var state=ThreeDReducer.reduce(ThreeDState(),.open(id,ThreeDEvidence())).0
state=ThreeDReducer.reduce(state,.setOutput(.sbs)).0
c.applyStoreOutput(.sbs)
let initial=c.loads
for key in ThreeDEffectKey.allCases {
 let (next,effects)=ThreeDReducer.reduce(state,.setEffect(key,.number(1.2)))
 state=next;c.applyStoreOutput(state.current.output,reapply:effects.contains(.reapply))
 precondition(c.loads==initial,"parameter edit caused hard media reload")
}
let (_,effects)=ThreeDReducer.reduce(state,.setOutput(.sbs))
c.applyStoreOutput(.sbs,reapply:effects.contains(.reapply))
precondition(c.loads==initial,"same-output prepared recovery reloaded mid-shot")
c.applyStoreOutput(.off)
precondition(c.loads==initial+1,"Off no longer returns the original")
c.applyStoreOutput(.sbs,filmID:FilmID(rawValue:"new-film"))
precondition(c.boundFilmID==FilmID(rawValue:"new-film") && c.lastGood.isEmpty && c.showing==nil,"new-film invalidation lost")
let oldID=c.preparedLoadID
c.preparedLoadPending=true;c.showing=3;c.lastGood=[3:1]
c.setMediaTransitionPending(true)
precondition(c.mediaTransitionPending && !c.preparedLoadPending && c.preparedLoadID != oldID && c.showing==nil && c.lastGood.isEmpty)
c.setMediaTransitionPending(false);precondition(!c.mediaTransitionPending)
print("PASS actual reducer/coordinator effects, media transition invalidates tasks/cache, release keeps generations retired")
'''
 (p/'main.swift').write_text(source)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'main.swift'),'-o',str(p/'live')],check=True)
 subprocess.run([str(p/'live')],check=True)

def _swiftc_run(folder,name,files,timeout=20):
    import os, subprocess
    binary=Path(folder)/name
    subprocess.run([os.environ.get('SWIFTC','swiftc')]+[str(f) for f in files]+['-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=timeout)

def _swiftc_expect_fail(folder,name,files,timeout=20):
    import os, subprocess
    binary=Path(folder)/name
    subprocess.run([os.environ.get('SWIFTC','swiftc')]+[str(f) for f in files]+['-o',str(binary)],check=True)
    rejected=subprocess.run([str(binary)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=timeout)
    assert rejected.returncode != 0, name + ' mutant escaped'

# 196c: the AppKit wrapper's VR->2D ordering, executed with the real wrapper
# method. offReset must run after leaving VR so its crop request never takes
# the stereo early return; an explicit non-off reapply still resets first;
# a plain effect edit resets nothing.
wrapper=(_pp_split().path(root,'PPController.swift')).read_text()
a=wrapper.index('    func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect])')
wrapmethod='    private var applyingThreeDWrapper=false\n'+wrapper[a:wrapper.index('    func select3DOutput',a)]
assert 'applyingThreeDWrapper=true;defer {applyingThreeDWrapper=false}' in wrapmethod
wrapshell='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
var EVENTS=[String]()
final class CropDetectorProbe {func cancel(){};func resetLastFile(){EVENTS.append("cropReset")}}
final class VR180Probe {
 var vrModeEnabled=false
 func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect]){EVENTS.append("controllerApply");vrModeEnabled = ThreeDPresentationPlan.make(state:state).output != .off}
}
final class PP {
 var vr180Controller:VR180Probe?=VR180Probe()
 var vrModeEnabled:Bool {vr180Controller?.vrModeEnabled ?? false}
 let cropDetector=CropDetectorProbe()
 var menuCropOwnsSelection=false,stereoRestorePending=false,stereoGeometryKey=""
 var appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero,bounds=CGRect.zero
 func offReset(){EVENTS.append("offReset(vr=\\(vrModeEnabled))")}
 func redetectCropAfter3DOff(){EVENTS.append("redetect")}
 func startAutomaticCropDetection(needsRedetect:Bool){EVENTS.append("cropDetect")}
 func refreshStereoMenuGeometry(force:Bool){EVENTS.append("stereoGeom")}
 func applyVideoFrame(bounds:CGRect){EVENTS.append("videoFrame")}
'''
wrapmain='''
let p=PP()
let open=ThreeDReducer.reduce(ThreeDState(),.open(FilmID(rawValue:"f"),ThreeDEvidence())).0
let offState=ThreeDReducer.reduce(open,.setOutput(.off)).0
let sbsState=ThreeDReducer.reduce(open,.setOutput(.sbs)).0
// VR -> 2D, no explicit reapply: the controller leaves VR first; the
// reset then observes vrModeEnabled == false, redetect follows.
p.vr180Controller!.vrModeEnabled=true
EVENTS=[];p.applyThreeDState(offState,[.present])
precondition(EVENTS==["controllerApply","offReset(vr=false)","redetect"],"VR->2D order: \\(EVENTS)")
precondition(!EVENTS.contains("offReset(vr=true)"),"reset ran while VR was still enabled")
// Explicit reapply to a non-off output: reset first, then the apply,
// then the geometry refresh; never a redetect.
p.vr180Controller!.vrModeEnabled=false
EVENTS=[];p.applyThreeDState(sbsState,[.present,.reapply])
precondition(EVENTS==["offReset(vr=false)","controllerApply","cropReset","cropDetect","stereoGeom","videoFrame"],"explicit non-off order: \\(EVENTS)")
// Plain effect edit while presenting: no reset, no redetect, no crop restart.
p.vr180Controller!.vrModeEnabled=true
EVENTS=[];p.applyThreeDState(sbsState,[.present])
precondition(EVENTS==["controllerApply"],"plain effect edit reset the surface: \\(EVENTS)")
print("PASS wrapper VR->2D reset observes VR already off; explicit non-off resets first; plain effect edit resets nothing")
'''
with tempfile.TemporaryDirectory() as folder:
    pth=Path(folder)
    (pth/'a').mkdir();(pth/'a/main.swift').write_text(wrapshell+wrapmethod+'}\n'+wrapmain)
    _swiftc_run(folder,'wrap',[_sec_file(root,'ThreeDState.swift'),pth/'a/main.swift'])
    # Reorder negative control: resetting before leaving VR observes
    # vrModeEnabled == true (the stereo early return the lane fix removes).
    moved=wrapmethod.replace("""vr180Controller?.applyThreeDState(state,effects)
        if targetOff {if wasEnabled || explicitPresentation {offReset();redetectCropAfter3DOff()};return}""","""if targetOff {if wasEnabled || explicitPresentation {offReset();redetectCropAfter3DOff()};return}
        vr180Controller?.applyThreeDState(state,effects)""")
    assert moved!=wrapmethod
    (pth/'b').mkdir();(pth/'b/main.swift').write_text(wrapshell+moved+'}\n'+wrapmain)
    _swiftc_expect_fail(folder,'moved',[_sec_file(root,'ThreeDState.swift'),pth/'b/main.swift'])
    print('PASS reset-before-leaving-VR ordering mutant rejected')

# 196c: final-state-only VR mode notification. The real
# VR180Controller.applyThreeDState + setVRModeEnabled run against doubled
# boundaries; the notification must fire once per presentation change with
# the FINAL mode, even when the route toggles the mode mid-apply.
feat=(_pp_split().path(root,'PPController_Features.swift')).read_text()
ctrlmethod=feat[feat.index('    func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect],revision:UInt64?=nil) {'):feat.index('    /// Read-only receipt of the applied 3D route')]
setmethod=feat[feat.index('    func setVRModeEnabled(_ enabled: Bool) {'):feat.index('    /// GOR_TRACE_GEOM=1 only: 1 Hz settled-state samples')]
assert 'if presentationChanged || projectionKey != previousProjectionKey {onVRModeApplied?(vrModeEnabled)}' in ctrlmethod
ctrlshell='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
var NOTES=[Bool]()
enum Diag {static func mediaRecord(_ s:String){}}
final class ScreenCaptureEngine {static let shared=ScreenCaptureEngine();var vrModeActive=false}
enum ThreeDRecognitionBridge {static func filmID(path:String)->FilmID? {FilmID(rawValue:path)}}
enum ThreeDAutoRoute {static func previewParams(mode:String,strength:Double,screenDepthM:Double,screenDeg:Double,surround:String)->(gain:String,conv:String,zoom:String,soft:String) {("1","1","1","1")}}
final class VR180Controller {
 static var vrAutoFullscreen=false;static let ndcToMM=1.0
 var applyingStore=false,routeRevision:UInt64=0
 var recognitionPath="/fixture",recognitionGeneration:UInt64=1,recognitionIdentity="id1"
 var pendingRouteRevision:UInt64?,pendingRouteOutput:ThreeDOutput?,droppedRouteKey=""
 var projectionKey="k0"
 var appliedPlan:ThreeDPresentationPlan?,appliedThreeD:FilmThreeD?,appliedInternal=false,appliedEffects:ThreeDGlobalEffects?
 var vrModeEnabled=false,vrModeSetByAutoDetect=false,flatStereoFile=false,autoFitEntry="",latestProbeStatus="",swapEyes=false
 var latestWidth=0,latestHeight=0
 var onVRModeApplied:((Bool)->Void)?
 func sendRaw(_ s:String){}
 func knownEyeAspect(kind:String,filename:String,width:Int,height:Int)->Double {1.78}
 func releaseProjectionLock(){}
 func publishProjection(_ kind:String,aspect:Double,reason:String){}
 func setSwapEyes(_ on:Bool){}
 func simulatePoseIfRequested(){}
 func setHeadTrackingEnabled(_ v:Bool,remember:Bool){}
 func setBlinkControlEnabled(_ v:Bool,osd:Bool,remember:Bool)->Bool {true}
 func publishBaseIPD(_ v:Double,persist:Bool){}
 func resetFilmView(smooth:Bool){};func resetFilmView(){}
 func recenterHeadTracking(){}
 func publishThreeDAppliedState(plan:ThreeDPresentationPlan){}
 func noteManualEnabled(_ v:Bool){}
 func sendSwapEyes(){};func sendPersistedBaseIPD(){}
 func traceCameraState(_ s:String){};func updateCameraTraceHeartbeat(){}
'''
ctrlmain='''
let c=VR180Controller()
c.onVRModeApplied={v in NOTES.append(v)}
let open=ThreeDReducer.reduce(ThreeDState(),.open(FilmID(rawValue:"/fixture"),ThreeDEvidence())).0
let sbs=ThreeDReducer.reduce(open,.setOutput(.sbs)).0
c.applyThreeDState(sbs,[.present])
precondition(NOTES==[true],"off->sbs notified \\(NOTES)")
let tb=ThreeDReducer.reduce(sbs,.setOutput(.tb)).0
c.applyThreeDState(tb,[.present])
precondition(NOTES==[true,true],"3D->3D route must notify once with the final mode, got \\(NOTES)")
precondition(!NOTES.contains(false),"intermediate false reached an observer (offReset/redetect would fire early)")
c.applyThreeDState(tb,[.present])
precondition(NOTES==[true,true],"identical re-apply must stay silent, got \\(NOTES)")
let off=ThreeDReducer.reduce(tb,.setOutput(.off)).0
c.applyThreeDState(off,[.present])
precondition(NOTES==[true,true,false],"off notified \\(NOTES)")
print("PASS final-state-only VR mode notification: one callback per presentation change, final value, no intermediate false")
'''
with tempfile.TemporaryDirectory() as folder:
    pth=Path(folder)
    (pth/'a').mkdir();(pth/'a/main.swift').write_text(ctrlshell+ctrlmethod+setmethod+'}\n'+ctrlmain)
    _swiftc_run(folder,'ctrl',[_sec_file(root,'ThreeDState.swift'),pth/'a/main.swift'])
    # Intermediate-false negative control: notifying from the setter (the
    # reviewed-and-rejected defer design) publishes false then true on a
    # 3D->3D route and must fail.
    injected=setmethod.replace('vrModeEnabled = enabled','vrModeEnabled = enabled;onVRModeApplied?(enabled)')
    assert injected!=setmethod
    (pth/'b').mkdir();(pth/'b/main.swift').write_text(ctrlshell+ctrlmethod+injected+'}\n'+ctrlmain)
    _swiftc_expect_fail(folder,'injected',[_sec_file(root,'ThreeDState.swift'),pth/'b/main.swift'])
    print('PASS setter-notification intermediate false->true mutant rejected')

# 196c: mediaTransition flush replays only the FINAL mode's parked fit.
flush=wrapper[wrapper.index('    private func finishMediaTransition() {'):wrapper.index('    private func refreshStereoMenuGeometry(force: Bool = false) {')]
assert "Replay only the final mode's fit." in flush
flush=flush.replace('    private func finishMediaTransition() {','    func finishMediaTransition() {')
flushshell='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
var EVENTS=[String]()
final class ThreeDRenderCoordinator {func setMediaTransitionPending(_ b:Bool){EVENTS.append("coord(\\(b))")}}
enum ThreeDRuntime {static var coordinator:Any?=ThreeDRenderCoordinator()}
final class VR180Probe {var vrModeEnabled=false}
final class PP {
 var vr180Controller:VR180Probe?=VR180Probe()
 var vrModeEnabled:Bool {vr180Controller?.vrModeEnabled ?? false}
 var mediaTransitionPending=false,mediaTransitionNeedsFit=false
 var deferredWindowRefitAspect:Double?,stereoGeometryKey=""
 var appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero,bounds=CGRect.zero
 func ipcCommand(_ s:String){EVENTS.append("ipc")}
 func refreshStereoMenuGeometry(force:Bool){EVENTS.append("stereoGeom")}
 func applyVideoFrame(bounds:CGRect){EVENTS.append("videoFrame")}
 func refitWindowForCrop(aspect:Double){EVENTS.append("refit(\\(aspect))")}
'''
flushmain='''
let p=PP()
// VR final mode with a parked 2D aspect: stereo refresh only, never the stale 2D refit.
p.vr180Controller!.vrModeEnabled=true;p.deferredWindowRefitAspect=1.5
EVENTS=[];p.finishMediaTransition()
precondition(EVENTS.contains("stereoGeom") && EVENTS.contains("videoFrame"),"VR flush missing stereo refresh: \\(EVENTS)")
precondition(!EVENTS.contains("refit(1.5)"),"VR flush replayed the stale 2D aspect: \\(EVENTS)")
// 2D final mode with a parked aspect: exactly one deferred refit, no stereo refresh.
p.vr180Controller!.vrModeEnabled=false;p.deferredWindowRefitAspect=1.5
EVENTS=[];p.finishMediaTransition()
precondition(EVENTS==["coord(false)","ipc","refit(1.5)"],"2D flush: \\(EVENTS)")
precondition(p.deferredWindowRefitAspect==nil,"parked aspect not consumed")
// 2D final mode with nothing parked: no geometry replay at all.
EVENTS=[];p.finishMediaTransition()
precondition(EVENTS==["coord(false)","ipc"],"unparked 2D flush replayed geometry: \\(EVENTS)")
print("PASS mediaTransition flush replays only the final mode fit: VR stereo refresh XOR 2D deferred refit")
'''
with tempfile.TemporaryDirectory() as folder:
    pth=Path(folder)
    (pth/'a').mkdir();(pth/'a/main.swift').write_text(flushshell+flush+'}\n'+flushmain)
    _swiftc_run(folder,'flush',[_sec_file(root,'ThreeDState.swift'),pth/'a/main.swift'])
    # Stale-2D-then-VR negative control: running both branches replays the
    # stale aspect into the VR refresh and must fail.
    both=flush.replace('} else if let a=deferredWindowRefitAspect','}; if let a=deferredWindowRefitAspect')
    assert both!=flush
    (pth/'b').mkdir();(pth/'b/main.swift').write_text(flushshell+both+'}\n'+flushmain)
    _swiftc_expect_fail(folder,'both',[_sec_file(root,'ThreeDState.swift'),pth/'b/main.swift'])
    print('PASS stale-2D-aspect-then-VR-refresh mutant rejected')

# 196c gap 5: execute actual parked opening refit and drain; reject lost-work mutants.
refit=wrapper[wrapper.index('    private func refitWindowForCrop(aspect: Double?, settledFrame: NSRect? = nil) {'):wrapper.index('    private func transitionCrop(')]
armfit=wrapper[wrapper.index('    private func applyOpeningFitIfArmed(videoW: Double, videoH: Double) {'):wrapper.index('    private var lastShownMPVOSD')]
PARK=';if openingFitPending { deferredWindowRefitAspect = a; return }'
DRAIN='        defer {if let aspect=deferredWindowRefitAspect {refitWindowForCrop(aspect:aspect)}}\n'
assert PARK in refit and DRAIN in armfit
refitpatched=refit;armfitpatched=armfit
g5shell='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
typealias NSRect = CGRect
var EVENTS=[String]();var LASTASPECT=0.0
struct GorFitRect {var x=0.0,y=0.0,w=0.0,h=0.0}
enum GorVideoFit {static let openBaselineFraction=0.5}
enum GorCropPlan {static func refitFrame(frame:GorFitRect,aspect:Double,chromeW:Double,chromeH:Double,avail:GorFitRect)->GorFitRect? {LASTASPECT=aspect;return GorFitRect(x:0,y:0,w:320,h:180)}}
enum GorOpeningFit {
 static let mpvWindowMask=0
 static func openingGeometry(videoW:Double,videoH:Double,screen:NSScreen?,floorFraction:Double)->String? {"geom"}
 static func clampGeometry(frame:NSRect,screen:NSScreen)->String? {"geom"}
}
enum MPVCommand {static func make(_ c:[String])->String {"cmd"}}
enum CropInvariant {static func transitionLine(_ s:String,crop:CGRect?,display:(Double,Double))->String {""}}
extension CGRect {func isAlmostEqual(to o:CGRect,epsilon:Double)->Bool {false}}
final class NSScreen {
 static var screens:[NSScreen]=[NSScreen()];static var main:NSScreen?=NSScreen()
 var frame=NSRect(x:0,y:0,width:1920,height:1080);var visibleFrame:NSRect {frame}
}
final class NSWindow {
 var frame=NSRect(x:0,y:0,width:640,height:360);var screen:NSScreen?=NSScreen()
 static func frameRect(forContentRect r:NSRect,styleMask m:Int)->NSRect {NSRect(x:0,y:0,width:104,height:122)}
}
final class AppDelegate {
 var windowGeometryTransitionActive=false,pictureInPictureActive=false,playerFullscreenState=false
 func refitPictureInPicture(aspect:Double){}
 func issueFencedGeometry(_ geom:String,before:NSRect,target:NSRect){EVENTS.append("applied")}
}
final class NSAppProbe {var delegate:AnyObject?=AppDelegate() as AnyObject}
let NSApp=NSAppProbe()
final class PP {
 static var gorFitScriptActive=true
 var cropRect:CGRect?=nil,appliedSourceCropAspect:Double?=nil
 var videoDisplayW=16.0,videoDisplayH=9.0
 var mediaTransitionPending=false,deferredWindowRefitAspect:Double?
 var openingFitArmedOpen:Int?,currentFilePath="/f"
 var openingFitPendingFraction=GorVideoFit.openBaselineFraction,openingFitNonBaselineApplied=false
 var openingFitPending:Bool {openingFitArmedOpen != nil}
 var window:NSWindow?=NSWindow(),windowRefitAnchorFrame:NSRect?
 func ipcCommand(_ s:String){EVENTS.append("ipc")}
 func sendGeometryUntracked(_ s:String){EVENTS.append("applied")}
'''
g5main='''
let p=PP()
// Armed opening: the crop refit parks instead of being dropped.
p.openingFitArmedOpen=1
p.refitWindowForCrop(aspect:1.7)
precondition(p.deferredWindowRefitAspect==1.7 && EVENTS.isEmpty,"armed opening must park, not drop: \\(EVENTS)")
// Consuming the arm (baseline gor_fit early-return path) drains the parked refit through the same function.
p.applyOpeningFitIfArmed(videoW:16,videoH:9)
precondition(p.openingFitArmedOpen==nil && p.deferredWindowRefitAspect==nil,"parked aspect not drained on arm consumption")
precondition(EVENTS==["applied"] && LASTASPECT==1.7,"drained refit must apply with the parked aspect: \\(EVENTS)")
// Media still pending at drain time: the drain re-parks, nothing is lost.
p.openingFitArmedOpen=2;EVENTS=[];LASTASPECT=0
p.refitWindowForCrop(aspect:1.7)
p.mediaTransitionPending=true
p.applyOpeningFitIfArmed(videoW:16,videoH:9)
precondition(EVENTS.isEmpty && p.deferredWindowRefitAspect==1.7,"drain must re-park while media pending: \\(EVENTS)")
print("PASS armed opening parks the crop refit; arm consumption drains it; media-pending re-parks")
'''
with tempfile.TemporaryDirectory() as folder:
    pth=Path(folder)
    (pth/'a').mkdir()
    (pth/'a/main.swift').write_text(g5shell+refitpatched.replace('    private func refitWindowForCrop','    func refitWindowForCrop')+armfitpatched.replace('    private func applyOpeningFitIfArmed','    func applyOpeningFitIfArmed')+'}\n'+g5main)
    _swiftc_run(folder,'gap5',[_sec_file(root,'ThreeDState.swift'),pth/'a/main.swift'])
    # Lost-work negative control: the CURRENT production text drops the
    # aspect at the armed guard and never drains it.
    (pth/'b').mkdir()
    (pth/'b/main.swift').write_text(g5shell+refit.replace(PARK, ';if openingFitPending { return }').replace('    private func refitWindowForCrop','    func refitWindowForCrop')+armfit.replace(DRAIN,'').replace('    private func applyOpeningFitIfArmed','    func applyOpeningFitIfArmed')+'}\n'+g5main)
    _swiftc_expect_fail(folder,'gap5-current',[_sec_file(root,'ThreeDState.swift'),pth/'b/main.swift'])
    print('PASS current behavior drops the armed-opening crop refit (lost-work negative control)')

# 196d: preserve the same head-mode crop fit when mpv acknowledges clearing video-crop.
req=wrapper[wrapper.index('    private func requestRealCrop(_ rect: CGRect) {'):wrapper.index('    /// P4: one read-only vf-list query')].replace('    private func','    func',1)
a=wrapper.index('        if let crop = results["video-crop"] as? String {')
b=wrapper.index('        // File-path handling above can reset this flag',a)
observe='    func observe(_ results:[String:Any]) {\n'+wrapper[a:b]+'    }\n'
headshell='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
enum CropInvariant {static func fits(x:Int,y:Int,w:Int,h:Int,srcW:Int,srcH:Int)->Bool {true};static func keptLine(_ s:String)->String {s}}
enum SBSGeometry {static func parseCrop(_ s:String)->(Double,Double)? {nil}}
final class Detector {var sourcePixelWidth=1920,sourcePixelHeight=1080}
final class VR {func clearMeasuredEyeAspect(){}}
final class PP {
 var vrModeEnabled=false,headTrackingEnabled=true,menuCropOwnsSelection=false
 var surfaceToolsEnabled:Bool {headTrackingEnabled}
 var sourceCropPropertyRequested=false,sourceCropPropertyActive=true,lastSourceCropValue="1456x1080+232+0"
 var cropRect: CGRect?=CGRect(x:0.12,y:0,width:0.76,height:1)
 let cropDetector=Detector();var vr180Controller:VR?=VR()
 var nativeVideoAspect:Double?=1920.0/1080,stereoManualAspect:Double?,manualMenuCropAspect:Double?
 var appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero,bounds=CGRect.zero
 var drawable=true,fits=[Double](),commands=[String](),published=0
 func ipcCommand(_ s:String){commands.append(s)}
 func refreshStereoMenuGeometry(force:Bool){}
 func publishSurfaceWindowCrop(x:Double,y:Double,cx:Double,cy:Double)->Bool {published += 1;return drawable}
 func refitWindowForCrop(aspect:Double?){if let aspect {fits.append(aspect)}}
 func applyVideoFrame(bounds:CGRect){}
'''
headmain='''
let p=PP();let crop=p.cropRect!,expected=(1920.0/1080)*Double(crop.width/crop.height)
p.requestRealCrop(crop);precondition(p.fits.count==1 && abs(p.fits.last!-expected)<0.000001)
p.observe(["video-crop":""])
precondition(p.fits.count==2 && p.fits.allSatisfy{abs($0-expected)<0.000001},"clear receipt undid crop fit: \\(p.fits)")
p.drawable=false;p.fits=[];p.requestRealCrop(crop)
precondition(p.fits.count==1 && abs(p.fits[0]-expected)<0.000001,"waiting drawable dropped independent window fit")
p.menuCropOwnsSelection=true;p.manualMenuCropAspect=1.5;p.lastSourceCropValue="old";p.fits=[]
p.observe(["video-crop":""]);precondition(p.fits==[1.5],"manual crop precedence changed")
print("PASS actual head crop request+mpv-clear receipt preserve aspect; drawable wait does not lose fit; manual menu wins")
'''
with tempfile.TemporaryDirectory() as folder:
 pth=Path(folder);(pth/'a').mkdir();(pth/'a/main.swift').write_text(headshell+req+observe+'}\n'+headmain)
 _swiftc_run(folder,'headcrop',[pth/'a/main.swift'])
 old='if surfaceToolsEnabled, !menuCropOwnsSelection, let rect=cropRect {requestRealCrop(rect)} else {refitWindowForCrop(aspect:stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect)}'
 assert old in observe
 mutant=observe.replace(old,'refitWindowForCrop(aspect:stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect)')
 (pth/'b').mkdir();(pth/'b/main.swift').write_text(headshell+req+mutant+'}\n'+headmain)
 _swiftc_expect_fail(folder,'headclear',[pth/'b/main.swift'])
 old='if surfaceToolsEnabled { _=publishSurfaceWindowCrop(x:Double(rect.width),y:Double(rect.height),cx:Double(rect.midX),cy:Double(rect.midY)) }'
 assert old in req
 mutant=req.replace(old,'if surfaceToolsEnabled {guard publishSurfaceWindowCrop(x:Double(rect.width),y:Double(rect.height),cx:Double(rect.midX),cy:Double(rect.midY)) else {return}}')
 (pth/'c').mkdir();(pth/'c/main.swift').write_text(headshell+mutant+observe+'}\n'+headmain)
 _swiftc_expect_fail(folder,'headdrawable',[pth/'c/main.swift'])
 print('PASS head crop clear-receipt and missing-drawable lost-fit negative controls rejected')
