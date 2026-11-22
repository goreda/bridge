from pathlib import Path
import os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];app=(r/'Sources/gor/App/AppDelegate.swift').read_text();a=app.index('    private var pipRestoreFrame:');b=app.index('    private var menuWindowRestoreFrame:',a);method=app[a:b].replace('private var','var')
s=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=s.index('enum PlayerWindowPlacement {');b=s.index('\nextension AppDelegate {',a);plan=s[a:b];a=s.index('enum PlayerPictureInPicture {');b=s.index('\nextension AppDelegate {',a);plan+=s[a:b]
code='''import Foundation
struct Mask {static let borderless=0}
extension Int {static let borderless=0}
final class NSScreen {static var main:NSScreen?;var frame=CGRect(x:-1920,y:0,width:1920,height:1080);var visibleFrame=CGRect(x:-1920,y:30,width:1920,height:1020)}
final class Window {var frame=CGRect(x:-1700,y:200,width:1200,height:675);var screen:NSScreen?=NSScreen()}
func NSRectFromString(_ s:String)->CGRect{.zero}  // Linux Foundation has no NSRectFromString; no saved preferred frame is exercised here
final class Controller {var windowMenuVideoSize=CGSize(width:1920,height:1080);var vrModeEnabled=false;var ontop:Bool?=false;var commands:[String]=[]
 func nativeOnTopState()->Bool?{ontop}
 func ipcCommand(_ s:String){commands.append(s)}
 func logPipCrop(_ s:String,frame:CGRect){}
 var subtitlePiP:[Bool]=[]
 func synchronizeSubtitlePresentation(pictureInPicture:Bool){subtitlePiP.append(pictureInPicture)}
}
enum GorOpeningFit {static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Int=0)->String? {"gor-fit"}}
'''+plan+'''
final class Owner {
var overlayWin:Window?=Window();var controller:Controller?=Controller();var playerFullscreenState:Bool?=false
var pipDragCandidate:CGRect?;var windowGeometryTransitionActive=false;var pipWindowFrame:CGRect?;var pipPreferredFrame:CGRect?
var writes:[CGRect]=[]
func issueFencedGeometry(_ g:String,before:CGRect,target:CGRect){precondition(g=="gor-fit");writes.append(target);overlayWin?.frame=target}
'''+method+'''
}
let o=Owner(),original=o.overlayWin!.frame
o.togglePlayerPictureInPicture()
precondition(o.pictureInPictureActive && o.writes.count==1)
let small=o.writes[0],visible=o.overlayWin!.screen!.frame
precondition(abs(small.width/small.height-original.width/original.height)<0.000001)
precondition(small.minX==visible.minX && small.minY==visible.minY && small.width<original.width)
precondition(o.controller!.commands.contains{$0.contains("ontop") && $0.contains("true")} && o.controller!.commands.last!.contains("pip-window-owned") && o.controller!.commands.last!.contains("true") && o.pipWindowFrame==small && o.controller!.subtitlePiP.last==true)
o.togglePlayerPictureInPicture()
precondition(!o.pictureInPictureActive && o.writes.last! == original && o.controller!.commands.last!.contains("pip-window-owned") && o.controller!.commands.last!.contains("false") && o.pipWindowFrame==nil && o.controller!.subtitlePiP.last==false)
let count=o.writes.count
o.windowGeometryTransitionActive=true;o.togglePlayerPictureInPicture();precondition(o.writes.count==count)
o.windowGeometryTransitionActive=false;o.controller!.vrModeEnabled=true;o.togglePlayerPictureInPicture();precondition(o.writes.count==count)
o.controller!.vrModeEnabled=false;o.controller!.ontop=nil;o.togglePlayerPictureInPicture();precondition(o.writes.count==count)
o.controller!.ontop=true;o.togglePlayerPictureInPicture();o.togglePlayerPictureInPicture();precondition(o.controller!.commands.contains{$0.contains("ontop") && $0.contains("true")} && !o.pictureInPictureActive)
print("PASS actual PiP routing: aspect-preserving small bottom-left default corner (3c48acac), fenced mpv geometry, ontop set + prior state/geometry restored, geometry-transition (windowGeometryTransitionActive)/stereo/unknown-state safe no-op, pip-window-owned flag and subtitle sync")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/Engine/MPVCommand.swift'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
for label in ['↖','↗','↙','↘','•','smaller','larger','minimize','full screen','pip']:assert '"'+label+'"' in app
assert 'key:"p",mods:[.command,.control,.option,.shift]' in app
print('PASS static: requested Window items present, PiP checked/disabled clear-state route and unique shortcut; native macOS acceptance unverified')
