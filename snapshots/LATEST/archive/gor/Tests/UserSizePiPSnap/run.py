from pathlib import Path
import os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/MenuActions.swift').read_text();actual=''
for name in ['PlayerWindowPlacement','PlayerPictureInPicture','PlayerWindowSizing']:
 a=s.index('enum '+name+' {');b=s.find('\nextension AppDelegate {',a);actual+=s[a:b if b>=0 else len(s)]+'\n'
a=(r/'Sources/gor/App/AppDelegate.swift').read_text();start=a.index('    func snapPictureInPicture(');end=a.index('    private var pipRestoreFrame',start);snap=a[start:end]
code='''import Foundation
struct Mask {static let borderless=0}
extension Int {static let borderless=0}
class NSScreen {static var main:NSScreen?;var frame=CGRect(x:-1920,y:0,width:1920,height:1080)}
class Window {var screen:NSScreen?=NSScreen();var frame=CGRect(x:-600,y:0,width:500,height:300)}
enum GorOpeningFit {static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Int)->String?{"gor-fit"}}
'''+actual+'''
let screen=CGRect(x:-1920,y:0,width:1920,height:1080),video=CGSize(width:1280,height:720)
var scale=1.0
for mode in ["smaller","smaller","larger","smaller","larger"] {
 scale=PlayerWindowSizing.nextScale(scale,mode:mode)
 let size=PlayerWindowSizing.frame(mode:mode,current:.zero,screen:screen,video:video,resetDefault:true,userScale:scale)
 for corner in ["top-left","top-right","bottom-left","bottom-right","center"] {
  let moved=PlayerWindowPlacement.frame(mode:corner,current:size,visible:screen)
  precondition(moved.size==size.size)
 }
}
precondition(abs(scale-0.8)<0.000001)
let ordinary=PlayerWindowSizing.frame(mode:"center",current:.zero,screen:screen,video:video,resetDefault:true)
let scaled=PlayerWindowSizing.frame(mode:"center",current:.zero,screen:screen,video:video,resetDefault:true,userScale:scale)
precondition(abs(scaled.width/ordinary.width-0.8)<0.000001)
final class Owner {var pictureInPictureActive=true;var windowGeometryTransitionActive=false;var pipWindowFrame:CGRect?;var pipPreferredFrame:CGRect?;var overlayWin:Window?=Window();var writes:[CGRect]=[]
func issueFencedGeometry(_ geom:String,before:CGRect,target:CGRect){precondition(geom=="gor-fit");writes.append(target)}
'''+snap+'''
}
let owner=Owner()
for point in [CGPoint(x:-1800,y:800),CGPoint(x:-400,y:800),CGPoint(x:-1800,y:0),CGPoint(x:-400,y:0)] {
 let candidate=CGRect(origin:point,size:CGSize(width:500,height:300))
 owner.snapPictureInPicture(candidate)
 let target=owner.writes.last!
 precondition(target.size==candidate.size)
 precondition(target.minX==screen.minX || target.maxX==screen.maxX)
 precondition(target.minY==screen.minY || target.maxY==screen.maxY)
}
owner.pictureInPictureActive=false;let count=owner.writes.count;owner.snapPictureInPicture(.zero);precondition(owner.writes.count==count)
print("PASS actual size policy: repeated smaller/larger persists scale across all corners/center; default only scale1. Actual PiP snap routes4 nearest corners via gor fence, keeps size, inactive no-op")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
start=a.index('    func moveMpv(');end=a.index('    private func initializeOverlayDragPosition',start);drag=a[start:end]
assert drag.index('if pictureInPictureActive')<drag.index('writePendingOverlayPosition')
assert 'return // No free AX move in PiP' in drag
assert 'snapPictureInPicture(candidate)' in a[a.index('    func resetMpvPositionCache()'):]
assert 'pipRestoreFrame=nil;pipRestoreOnTop=nil;pipDragCandidate=nil' in a
assert 'UserDefaults.standard.set(windowUserSizeScale' in a
print('PASS static: PiP drag accumulates candidate only/no free AX write, release snaps; PiP corners keep size, exit clears drag constraint; native macOS drag/landing unverified')
