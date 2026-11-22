import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/MenuActions.swift').read_text();actual=''
for name in ['PlayerWindowPlacement','PlayerPictureInPicture']:
 a=s.index('enum '+name+' {');b=s.index('\nextension AppDelegate {',a);actual+=s[a:b]+'\n'
a=(r/'Sources/gor/App/AppDelegate.swift').read_text();start=a.index('    func refitPictureInPicture(');end=a.index('    private var pipDragCandidate:',start);method=a[start:end]
a0=s.index('struct VideoFormat {');b0=s.index('\nextension AppDelegate {',a0);actual+=s[a0:b0]+'\n'
code='''import Foundation
extension Int {static let borderless=0}
class NSScreen {static var main:NSScreen?;static var screens:[NSScreen]=[];var frame=CGRect(x:-1920,y:0,width:1920,height:1080)}
class Window {var screen:NSScreen?=NSScreen();var frame=CGRect(x:-600,y:0,width:576,height:324)}
enum GorOpeningFit {static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Int)->String?{"gor-fit"}}
'''+actual+'''
final class Owner {var pictureInPictureActive=true;var windowGeometryTransitionActive=false;var pipWindowFrame:CGRect?;var overlayWin:Window?=Window();var writes:[CGRect]=[]
func issueFencedGeometry(_ g:String,before:CGRect,target:CGRect){precondition(g=="gor-fit");writes.append(target);overlayWin!.frame=target}
'''+method+'''
}
let owner=Owner(),before=owner.overlayWin!.frame
owner.refitPictureInPicture(aspect:4.0/3.0)
let crop=owner.writes.last!
precondition(abs(crop.width/crop.height-4.0/3.0)<0.000001)
precondition(crop.width==before.width && crop.maxX==0 && crop.minY==0)
owner.refitPictureInPicture(aspect:16.0/9.0)
precondition(owner.writes.last!.size==before.size)
for format in VideoFormatCatalog.formats {
 owner.refitPictureInPicture(aspect:format.ratio)
 precondition(abs(owner.writes.last!.width/owner.writes.last!.height-format.ratio)<0.000001)
 owner.refitPictureInPicture(aspect:16.0/9)
 precondition(abs(owner.writes.last!.width/owner.writes.last!.height-16.0/9)<0.000001)
}
print("PASS all 27 catalog crops + reset through actual PiP refit method; geometry-only, not native window pixels")
owner.pictureInPictureActive=false;let count=owner.writes.count;owner.refitPictureInPicture(aspect:4.0/3.0);precondition(owner.writes.count==count)
let initial=PlayerPictureInPicture.croppedFrame(current:CGRect(x:0,y:0,width:1280,height:720),screen:CGRect(x:0,y:0,width:1920,height:1080),aspect:4.0/3.0)
precondition(abs(initial.width/initial.height-4.0/3.0)<0.000001)
print("PASS actual PiP crop refit routing:16:9 container ->4:3 OAR keeps PiP width/corner, uncrop restores aspect; crop-before-entry shapes correctly; non-PiP no-op")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
p=(_pp_split().path(r,'PPController.swift')).read_text();start=p.index('    private func refitWindowForCrop(');body=p[start:p.index('    private func transitionCrop(',start)]
assert body.index('delegate.refitPictureInPicture(aspect:a)')<body.index('windowRefitAnchorFrame')
assert 'aspect=stereoManualAspect ?? manualMenuCropAspect ?? appliedSourceCropAspect ?? cropMPV.displayedFilter.map { GorCropPlan.effectiveAspect($0) }' in p
assert 'let video=ctrl.windowMenuVideoSize' in a
print('PASS static: committed crop filter drives entry/menu aspect; crop action refit diverts to PiP before normal anchor/center; detector success on owner file unverified')
