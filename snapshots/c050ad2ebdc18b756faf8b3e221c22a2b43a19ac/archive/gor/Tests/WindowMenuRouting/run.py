from pathlib import Path
import os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];app=(r/'Sources/gor/App/AppDelegate.swift').read_text();a=app.index('    private var menuWindowRestoreFrame:');b=app.index('    func buildMenuBar()',a);method=app[a:b].replace('private var','var')
s=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=s.index('enum PlayerWindowPlacement {');b=s.index('\nextension AppDelegate {',a);plan=s[a:b];a=s.index('enum PlayerWindowSizing {');plan+=s[a:s.index('\nstruct VideoFormat {',a)];a=s.index('enum PlayerPictureInPicture {');b=s.index('\nextension AppDelegate {',a);plan+=s[a:b]
code='''import Foundation
struct Mask {static let borderless=0}
extension Int {static let borderless=0}
final class NSScreen {static var main:NSScreen?;var frame=CGRect(x:-1600,y:0,width:1600,height:1000);var visibleFrame=CGRect(x:-1600,y:30,width:1600,height:950)}
final class Controller {var windowMenuVideoSize=CGSize(width:1920,height:1080)}
final class Window {var frame=CGRect(x:-1400,y:100,width:800,height:450);var screen:NSScreen?=NSScreen()}
enum GorOpeningFit {static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Int=0)->String? {"gor-fit"}}
'''+plan+'''
final class Owner {
var overlayWin:Window?=Window();var playerFullscreenState:Bool?=false;var controller:Controller?=Controller()
var windowUserSizeScale:Double=1;var pictureInPictureActive=false;var windowGeometryTransitionActive=false;var pipWindowFrame:CGRect?
var writes:[CGRect]=[]
func issueFencedGeometry(_ g:String,before:CGRect,target:CGRect){precondition(g=="gor-fit");writes.append(target)}
'''+method+'''
}
let o=Owner()
for mode in ["top-left","top-right","bottom-left","bottom-right","center","smaller","larger","fill","zoom"] {
 let before=o.overlayWin!.frame;o.placePlayerWindow(mode)
 precondition(o.writes.count>0)
 let target=o.writes.last!
 precondition(abs(target.width/target.height-before.width/before.height)<0.000001)
}
for mode in ["smaller","smaller","larger"] {
 o.placePlayerWindow(mode);let chosen=o.writes.last!.size
 o.overlayWin!.frame=o.writes.last!
 for corner in ["top-left","top-right","bottom-left","bottom-right","center"] {
  o.placePlayerWindow(corner)
  precondition(abs(o.writes.last!.width-chosen.width)<0.000001 && abs(o.writes.last!.height-chosen.height)<0.000001)
  o.overlayWin!.frame=o.writes.last!
 }
}
let count=o.writes.count;o.windowGeometryTransitionActive=true;o.placePlayerWindow("center");precondition(o.writes.count==count)
print("PASS actual placePlayerWindow:9 actions use GorFit encoder + fenced mpv route, preserve aspect; fullscreen/geometry-transition no-op (windowGeometryTransitionActive replaced playerFullscreenState in b00eef38), no NSWindow resize selector")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
assert 'NSApp.windowsMenu=windowMenu' not in app
for sel in ['performZoom','zoom(_','tileWindow','moveWindowTo']:assert sel not in method
print('PASS static: AppKit automatic Window-menu injection removed; native macOS mpv geometry acceptance unverified')
