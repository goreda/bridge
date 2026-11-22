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
# Reuse the GeometryTransitions boundary stubs, then extend the window stub so the
# PRODUCTION atomic commit handler runs against order-recording frame/layout spies.
existing=(r/'Tests/GeometryTransitions/run.py').read_text();scope={'__file__':str(r/'Tests/GeometryTransitions/run.py')}
exec(existing[:existing.index('with tempfile.TemporaryDirectory()')],scope)
code=scope['code'].split('var cases=0')[0]
code=code.replace('''final class NSWindow {
 var frame:CGRect;var screen:NSScreen?;init(_ f:CGRect,_ s:NSScreen){frame=f;screen=s}
 static func frameRect(forContentRect r:CGRect,styleMask:Int)->CGRect{r}
}''','''var order:[String]=[]
enum CATransaction {
 static var disabled=false
 static func begin(){order.append("begin")}
 static func setDisableActions(_ value:Bool){disabled=value}
 static func commit(){order.append("commit");disabled=false}
}
final class View {
 var needsLayout=false
 func layoutSubtreeIfNeeded(){precondition(CATransaction.disabled && needsLayout);order.append("layout")}
}
final class NSWindow {
 var frame:CGRect;var screen:NSScreen?;var contentView:View?=View()
 init(_ f:CGRect,_ s:NSScreen){frame=f;screen=s}
 static func frameRect(forContentRect r:CGRect,styleMask:Int)->CGRect{r}
 func setFrame(_ f:CGRect,display:Bool,animate:Bool){precondition(CATransaction.disabled && !animate);frame=f;order.append("frame")}
}''')
code=code.replace('func commitOverlayFrame(_ frame:CGRect,window:NSWindow){window.frame=frame}',method(a,'private func commitOverlayFrame('))
code=code.replace('func refitPictureInPicture(aspect:Double){preconditionFailure("normal-mode test cannot refit PiP")}',method(a,'func refitPictureInPicture('))
code=code.replace('func restorePictureInPictureAfterFullscreen(){preconditionFailure("normal-mode test cannot restore PiP")}',method(a,'func restorePictureInPictureAfterFullscreen('))
code=code.replace('writes.append(target);controller?.window?.frame=target','writes.append(target);controller?.window?.frame=target')
code=code.replace('var pictureInPictureActive=false;var overlayWin:NSWindow?','var pictureInPictureActive=false;var overlayWin:NSWindow?;var pipWindowFrame:CGRect?')
m=(r/'Sources/gor/UI/MenuActions.swift').read_text();helpers=''
for name in ['PlayerWindowPlacement','PlayerPictureInPicture']:
 i=m.index('enum '+name+' {');j=m.index('\nextension AppDelegate {',i);helpers+=m[i:j]+'\n'
code=code.replace('var NSApp=App()','var NSApp=App()\n'+helpers)
code=code.replace('static let mpvWindowMask=0;static func clampGeometry(frame:CGRect,screen:NSScreen)->String?', 'static let mpvWindowMask=0;static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Int=0)->String?')
code=code.replace('import Foundation','import Foundation\nextension Int {static let borderless=0}',1)
code+='''
NSScreen.screens=[NSScreen(CGRect(x:0,y:0,width:1920,height:1080)),NSScreen(CGRect(x:-2560,y:100,width:2560,height:1440))]
var count=0
for screen in NSScreen.screens {
 for aspect in [16.0/9,9.0/16,2.39] {
  for corner in ["top-left","top-right","bottom-left","bottom-right"] {
   let d=AppDelegate(),c=PPController();NSApp.delegate=d;d.controller=c;d.pictureInPictureActive=true
   let pip=PlayerWindowPlacement.frame(mode:corner,current:CGRect(x:0,y:0,width:480,height:270/aspect*16.0/9.0),visible:screen.frame)
   d.pipWindowFrame=pip;d.mpvWindowedFrame=pip;d.lastFrame=pip
   let win=NSWindow(pip,screen);c.window=win;d.overlayWin=win
   // ENTRY tick: the first fullscreen receipt resizes overlay+HUDs immediately.
   d.mpvObservedFullscreen=true
   order=[]
   d.sample(screen.frame,true)
   precondition(win.frame==screen.frame,"entry transition tick: overlay must equal the fullscreen receipt at once, got \\(win.frame)")
   precondition(order.firstIndex(of:"frame") != nil && order.firstIndex(of:"layout") != nil &&
                order.firstIndex(of:"frame")! < order.firstIndex(of:"layout")!,
                "entry tick commits geometry and HUD/content layout in one atomic transaction")
   precondition(d.writes.isEmpty,"fullscreen entry never issues a geometry write")
   // EXIT tick with HUD open: mpv returns to the PiP frame at once while the
   // overlay is still fullscreen-sized. One sample = the transition tick.
   d.mpvObservedFullscreen=false
   order=[]
   d.sample(pip,false)
   precondition(win.frame==pip,"REGRESSION GUARD fullscreen->PiP: after the transition tick the overlay must equal the mpv receipt, got \\(win.frame) expected \\(pip)")
   precondition(order.firstIndex(of:"frame") != nil && order.firstIndex(of:"layout") != nil &&
                order.firstIndex(of:"frame")! < order.firstIndex(of:"layout")!,
                "exit tick commits geometry and HUD/content layout in one atomic transaction")
   // Settle window completes bookkeeping only: at most one final intent write,
   // none here because native already restored the saved PiP frame.
   ProcessInfo.processInfo.systemUptime += 0.8
   d.sample(pip,false)
   precondition(d.writes.count<=1,"settled exit issues at most one final PiP target write")
   precondition(d.pipWindowFrame==pip,"saved PiP target unchanged by the fullscreen round trip")
   precondition(win.frame==pip,"overlay stays on the PiP frame through the settle gate")
   count+=1
  }
 }
}
print("PASS \\(count) fullscreen<->PiP transition-tick cases: geometry equality after the transition tick (entry and exit, HUD layout spy committed in the same atomic transaction), no fullscreen writes, at most one settled intent write, saved PiP target preserved")
'''
with tempfile.TemporaryDirectory() as t:
 t=Path(t);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(t/'main.swift'),'-o',str(t/'run')],check=True)
 subprocess.run([str(t/'run')],check=True)
# Source invariants: the transition-tick commit precedes the restore settle gate in
# production trackMPVFullscreen, and the transition diagnostics are present.
track=method(a,'private func trackMPVFullscreen(')
assert track.index('commitOverlayFrame')<track.index('guard now - mpvRestoreStableSince'),'transition-tick commit must precede the settle gate'
assert track.count('commitOverlayFrame')>=3,'entry tick, exit tick and settled restore all commit through the atomic handler'
for marker in ['[window-sync] transition receipt entry','[window-sync] transition receipt exit','[window-sync] restore settled']:
 assert marker in a,'missing diagnostic '+marker
print('PASS source invariants: transition commits precede the settle gate; overlay-vs-mpv frame diagnostics at entry, exit and settled restore')
print('Linux only: boundary spies, not native AppKit/AX windows; absolute native timing and pixels remain unverified')
