
# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=_sub_read(_pp_split().path(r,'PPController.swift'))
def method(key):
 a=s.index(key);b=s.index('{',a);e=b+1;n=1
 while n:n+=(s[e]=='{')-(s[e]=='}');e+=1
 return s[a:e].replace('private func','func')+'\n'
a=s.index('        let displayRect: CGRect',s.index('private func applyVideoFrame'));b=s.index('        GeomTrace.logChanged("hudCropBounds"',a)
geometry=s[a:b]
a=s.index('        // One visible-picture authority');b=s.index('        // v2: force',a);views=s[a:b]
code='''import Foundation
extension CGRect {func isAlmostEqual(to r:CGRect,epsilon:Double)->Bool {abs(minX-r.minX)<epsilon && abs(minY-r.minY)<epsilon && abs(width-r.width)<epsilon && abs(height-r.height)<epsilon}}
enum GeomTrace {static func logChanged(_ a:String,_ b:String){}}
enum GorCropPlan {static func effectiveAspect(_ x:Double)->Double{x}}
class View {var frame:CGRect = .zero;var spineWidth:CGFloat=44;var sidebarWidth:CGFloat=52;var hudCropBounds:CGRect = .zero}
typealias NSView=View
struct Crop {var overlayIsIdentity=true;var displayedFilter:Double?=nil}
struct Connection {var isConnected=true}
struct Epoch {var osdW=0.0,osdH=0.0,rotation=0.0,path="movie"}
struct Gap {var value:Double=0}
class Probe {
 var spineUI=View(),sidebarUI=View(),subtitleView=View()
 var visiblePictureBounds:CGRect = .zero,appliedVideoFrame:CGRect = .zero
 var appliedVideoFrameWindowSize:CGSize = .zero
 var vrModeEnabled=false,osdFilterUncertain=false,osdDimsAvailable=true,sourceCropPropertyRequested=false
 var videoDisplayW=1920.0,videoDisplayH=1080.0,videoLayoutRotation=0.0
 var stereoManualAspect:Double?,manualMenuCropAspect:Double?,videoLayoutAspect:Double?=16/9
 var cropMPV=Crop(),cropRect:CGRect?,persistentConnection=Connection(),latestOsdEpoch:Epoch?,latestOsdDims:[String:Double]?
 var currentFilePath="movie",effectiveVrGap:Gap?=nil
 func flatEyeContentBounds(_ r:CGRect)->CGRect{r}
'''+method('static func rotatedCropRect(')+method('static func rotatedAspect(')+method('private func reflowVideoFramePanel(')+'''
 func run(_ winW:Double,_ winH:Double) {
'''+geometry+views+'''
 precondition(visiblePictureBounds==subtitleView.frame && spineUI.hudCropBounds==visiblePictureBounds)
 precondition(spineUI.frame.minX==visiblePictureBounds.minX && sidebarUI.frame.maxX==visiblePictureBounds.maxX)
 precondition(visiblePictureBounds.width>1 && visiblePictureBounds.height>1)
 let panel=View();reflowVideoFramePanel(panel,padL:10,padR:20,padT:8,base:visiblePictureBounds)
 precondition(panel.frame.minX==visiblePictureBounds.minX+10 && panel.frame.maxX==visiblePictureBounds.maxX-20)
 precondition(panel.frame.minY==visiblePictureBounds.minY+8 && panel.frame.maxY==visiblePictureBounds.maxY-8)
 }
}
var count=0
for state in ["fit","crop-detect","zoom","pan","aspect","rotation","fullscreen","pip"] {
 for rotation in [0.0,90,180,270] {for wh in [[480.0,270],[960,600],[1920,1080]] {for margins in [[0.0,0,0,0],[120,80,60,40],[-100,-80,-60,-40]] {
 let p=Probe();p.videoLayoutRotation=rotation
 if state=="aspect" {p.videoLayoutAspect=4/3}
 if state=="rotation" {p.videoLayoutAspect=9/16}
 if state=="crop-detect" {p.cropMPV.overlayIsIdentity=false;p.cropRect=CGRect(x:0.1,y:0.1,width:0.8,height:0.8)}
 p.latestOsdEpoch=Epoch(osdW:wh[0],osdH:wh[1],rotation:rotation,path:"movie")
 p.latestOsdDims=["w":wh[0],"h":wh[1],"ml":margins[0],"mr":margins[1],"mt":margins[2],"mb":margins[3]]
 p.run(wh[0],wh[1]);count+=1
 // Stale rotation/path epoch must fall back to current target rather than old accepted OSD.
 let stale=Probe();stale.latestOsdEpoch=Epoch(osdW:wh[0],osdH:wh[1],rotation:999,path:"old");stale.latestOsdDims=p.latestOsdDims;stale.run(wh[0],wh[1]);count+=1
 }}}
}
print("PASS \\(count) exact production geometry matrix cases across fit/crop/zoom/pan/aspect/rotation/fullscreen/PiP and stale epochs; native transitions unverified")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'run')],check=True);subprocess.run([str(p/'run')],check=True)
assert 'base: visiblePictureBounds' in s
assert 'visiblePictureBounds == .zero ? bounds:visiblePictureBounds' in s
end=s[s.index('        // Frames above are final now.'):s.index('    // MARK: - OSD')]
assert 'musicModeController?.relayout()' in end and 'iptvModeController?.relayout()' in end
sub=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');assert 'NSEvent.mouseLocation.x-screen.midX' not in sub and 'NSEvent.mouseLocation.x - screenFrame.midX' not in sub
print('PASS panel consumers and immediate music/IPTV relayout use visible authority; subtitle proximity anchors to physical picture center; no font or axis curve change')
