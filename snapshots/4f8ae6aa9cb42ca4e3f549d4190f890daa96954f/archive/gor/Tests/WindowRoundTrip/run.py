from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=s.index('enum PlayerWindowSizing {');b=s.index('\n}',a)+2;sizing=s[a:b];a=s.index('enum PlayerWindowPlacement {');b=s.index('\nextension AppDelegate {',a);placement=s[a:b]
code='import Foundation\n'+placement+sizing+'''
let screen=CGRect(x:-1920,y:-200,width:1920,height:1080),video=CGSize(width:1920,height:1080)
var current=CGRect(x:-1800,y:0,width:800,height:450)
let expected=PlayerWindowSizing.frame(mode:"fill",current:current,screen:screen,video:video,resetDefault:false)
for _ in 0..<100 {
 let base=PlayerWindowSizing.frame(mode:"fill",current:current,screen:screen,video:video,resetDefault:false)
 current=PlayerWindowPlacement.frame(mode:"fill",current:base,visible:screen)
 precondition(abs(current.width-expected.width)<0.000001 && abs(current.height-expected.height)<0.000001)
}
for mode in ["top-left","top-right","bottom-left","bottom-right","center"] {
 let base=PlayerWindowSizing.frame(mode:mode,current:current,screen:screen,video:video,resetDefault:true)
 let placed=PlayerWindowPlacement.frame(mode:mode,current:base,visible:screen)
 precondition(abs(placed.width-GorVideoFit.proposedOpenSize(videoW:1920,videoH:1080,screenW:1920).w)<0.001 && abs(placed.width/placed.height-16.0/9.0)<0.000001)
 if mode.contains("top"){precondition(placed.maxY==screen.maxY)}
 if mode.contains("bottom"){precondition(placed.minY==screen.minY)}
 if mode.contains("left"){precondition(placed.minX==screen.minX)}
 if mode.contains("right"){precondition(placed.maxX==screen.maxX)}
 if mode=="center"{precondition(placed.midX==screen.midX && placed.midY==screen.midY)}
}
print("PASS actual content sizing + GorVideoFit opening default:100 repeated fills identical;4 corners/center reset resolution-sensitive opening default; full negative-origin screen edges, no menu/Dock reservation")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
a=(r/'Sources/gor/App/AppDelegate.swift').read_text()
assert '_HIHideMenuBar' not in a
start=a.index('    private var pipRestoreFrame:');end=a.index('    func buildMenuBar()',start)
import re
seg=a[start:end]
assert seg.count('.visibleFrame')==seg.count('PlayerWindowPlacement.usableFrame(screen:screen.frame,visible:screen.visibleFrame,menuAutoHides:false)')>=1  # be940fd4 (2026-11-08): corners are of the usable area; visibleFrame is only read through usableFrame, and PiP owns true screen corners
assert 'pictureInPictureActive ? screen.frame' in seg
assert 'chromeStyleMask:.borderless' in a[start:end]
assert 'menuItem.title=playerWindowIsMinimized ? "restore" : "minimize"' in a
assert 'AXUIElementSetAttributeValue(ax,kAXMinimizedAttribute as CFString,kCFBooleanFalse)' in a
assert 'main.insertItem(photonItem,at:main.index(of:subItem)+1)' in a
print('PASS static: content-based borderless geometry, full-screen metrics except window corners (usableFrame, be940fd4), live minimize/restore route + menu state, Photon after Subtitles; native Mac landing unverified')
