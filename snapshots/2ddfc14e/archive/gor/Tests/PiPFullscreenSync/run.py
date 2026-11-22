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
# Reuse existing AppKit/AX boundary types, but compile the current production methods.
existing=(r/'Tests/GeometryTransitions/run.py').read_text();scope={'__file__':str(r/'Tests/GeometryTransitions/run.py')}
exec(existing[:existing.index('with tempfile.TemporaryDirectory()')],scope)
method=scope['method'];code=scope['code'].split('var cases=0')[0]
code=code.replace('var pictureInPictureActive=false;var overlayWin:NSWindow?','var pictureInPictureActive=false;var overlayWin:NSWindow?;var pipWindowFrame:CGRect?;var events:[String]=[]')
code=code.replace('func commitOverlayFrame(_ frame:CGRect,window:NSWindow){window.frame=frame}','func commitOverlayFrame(_ frame:CGRect,window:NSWindow){events.append("receipt");window.frame=frame}')
code=code.replace('func refitPictureInPicture(aspect:Double){preconditionFailure("normal-mode test cannot refit PiP")}',method(a,'func refitPictureInPicture('))
code=code.replace('func restorePictureInPictureAfterFullscreen(){preconditionFailure("normal-mode test cannot restore PiP")}',method(a,'func restorePictureInPictureAfterFullscreen('))
code=code.replace('writes.append(target);controller?.window?.frame=target','events.append("write");writes.append(target);controller?.window?.frame=target')
# Production pure PiP geometry helpers.
m=(r/'Sources/gor/UI/MenuActions.swift').read_text();helpers=''
for name in ['PlayerWindowPlacement','PlayerPictureInPicture']:
 i=m.index('enum '+name+' {');j=m.index('\nextension AppDelegate {',i);helpers+=m[i:j]+'\n'
code=code.replace('var NSApp=App()','var NSApp=App()\n'+helpers)
code=code.replace('static let mpvWindowMask=0;static func clampGeometry(frame:CGRect,screen:NSScreen)->String?', 'static let mpvWindowMask=0;static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Int=0)->String?')
code=code.replace('import Foundation','import Foundation\nextension Int {static let borderless=0}',1)
code+='''
NSScreen.screens=[NSScreen(CGRect(x:0,y:0,width:1920,height:1080)),NSScreen(CGRect(x:-1920,y:0,width:1920,height:1080))]
var count=0
for screen in NSScreen.screens {
 for aspect in [1.0,4.0/3,16.0/9,2.39,9.0/16] {
  for change in [false,true] {
   for nativeCorrect in [false,true] {
   for corner in ["top-left","top-right","bottom-left","bottom-right"] {
    let d=AppDelegate(),c=PPController();NSApp.delegate=d;d.controller=c;d.pictureInPictureActive=true
    let pip=PlayerWindowPlacement.frame(mode:corner,current:CGRect(x:0,y:0,width:480,height:270),visible:screen.frame)
    d.pipWindowFrame=pip;d.mpvWindowedFrame=pip;d.lastFrame=pip
    let win=NSWindow(pip,screen);c.window=win;d.overlayWin=win
    // Enter fullscreen: physical frame becomes screen-sized, but PiP intent does not.
    d.mpvObservedFullscreen=true;win.frame=screen.frame;d.sample(screen.frame,true)
    if change {c.refitWindowForCrop(aspect:aspect)}
    precondition(d.writes.isEmpty && d.pipWindowFrame==pip,"fullscreen must not mutate PiP proposal")
    precondition(c.deferredWindowRefitAspect==(change ? aspect : nil))
    // Native mpv returns an old normal window, not PiP. No writer during intermediate frames.
    d.mpvObservedFullscreen=false;d.sample(screen.frame,false)
    let normal=nativeCorrect ? pip : CGRect(x:screen.frame.minX+100,y:100,width:1000,height:600)
    win.frame=normal;d.sample(normal,false)
    precondition(d.writes.isEmpty)
    ProcessInfo.processInfo.systemUptime += 0.8;d.sample(normal,false)
    let expectedEvents = nativeCorrect && !change ? ["receipt"] : ["receipt","write"]
    precondition(d.events==expectedEvents,"commit actual exit receipt before at most one final PiP target")
    let target=d.writes.last ?? normal
    let expected=change ? PlayerPictureInPicture.croppedFrame(current:pip,screen:screen.frame,aspect:aspect) : pip
    precondition(target==expected && d.pipWindowFrame==expected,"keep saved PiP size/corner, not fullscreen budget")
    // Late normal/fullscreen intent cannot change the PiP anchor, nor trigger another exit restore.
    let n=d.writes.count;d.sample(target,false);ProcessInfo.processInfo.systemUptime += 0.8;d.sample(target,false)
    precondition(d.writes.count==n && d.pipWindowFrame==expected)
    count+=1
   }
   }
  }
 }
}
print("PASS \\(count) current production fullscreen/refit/PiP methods: exact saved corner/size, latest aspect intent, no fullscreen writes, receipt before one target, stale normal-frame isolation; boundary spies, not native windows")
'''
with tempfile.TemporaryDirectory() as t:
 t=Path(t);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/GorFit.swift'),str(t/'main.swift'),'-o',str(t/'run')],check=True)
 subprocess.run([str(t/'run')],check=True)
refit=method(p,'private func refitWindowForCrop(')
assert refit.index('windowGeometryTransitionActive')<refit.index('delegate.pictureInPictureActive')
sync=method(a,'func syncOverlay(')
assert '!self.mpvRestoreWritePending' not in sync and '!self.mpvEntryWritePending' not in sync
assert '!frame.isAlmostEqual(to: win.frame,epsilon:0.1)' in sync
assert sync.index('guard fullscreenEpoch == self.mpvFullscreenEpoch')<sync.index('self.commitOverlayFrame(frame,window:win)')
assert 'if !self.windowGeometryTransitionActive' in sync
lua=(r/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text()
follow=lua[lua.index('local function follow_display_aspect()'):]
assert follow.index('user-data/gor/pip-window-owned')<follow.index('local p = mp.get_property_native("video-params")')
print('PASS receipt source invariants: follow physical frames during entry/exit; compare actual overlay frame not bookkeeping cache; stale-epoch rejection; keep geometry writer fence; Lua follower yields to PiP owner')
print('Linux only: no native AppKit/AX motion or absolute timing/pixel-sync acceptance claim')

# Source bisection anchors: distinguish the later PiP regression from the older receipt bug.
old42=subprocess.check_output(['git','show','42c45e80:archive/gor/Sources/gor/Player/PPController.swift'],text=True)
old122=subprocess.check_output(['git','show','f122d588:archive/gor/Sources/gor/Player/PPController.swift'],text=True)
pre=method(old42,'private func refitWindowForCrop(');post=method(old122,'private func refitWindowForCrop(')
assert 'delegate.refitPictureInPicture' not in pre
assert post.index('delegate.refitPictureInPicture')<post.index('windowGeometryTransitionActive')
prior=subprocess.check_output(['git','show','52940e87:archive/gor/Sources/gor/App/AppDelegate.swift'],text=True)
priorSync=method(prior,'func syncOverlay(')
assert '!self.mpvRestoreWritePending' in priorSync and '!frame.isAlmostEqual(to: self.lastFrame)' in priorSync
priorTrack=method(prior,'private func trackMPVFullscreen(')
assert 'lastFrame = frame' in priorTrack and 'commitOverlayFrame' not in priorTrack
print('PASS source-bisection witnesses: f122 introduced PiP-before-transition routing after42c45; pre-fix exit marked lastFrame without visual commit while sync suppressed restore receipts')
