#!/usr/bin/env python3
"""Real quit routing + real AppKit panels. Pixels are separate evidence, never assumed."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
from pathlib import Path
import os,sys,subprocess,tempfile,platform,json,hashlib
r=Path(__file__).resolve().parents[2]
a=_plat_read(r/'Sources/gor/App/AppDelegate.swift');p=_plat_read(r/'Sources/gor/GorPlatformMac/PanelFocus.swift')
x=a[a.index('    func applicationShouldTerminate('):a.index('    private func armQuitWatchdog(')]
y=p[p.index('    static func fadeAllForQuit('):p.index('    override func cancelOperation')]
def wiring(body,panels):
 assert body.index('NSApp.mainMenu?.cancelTracking()')<body.index('GORInputPanel.fadeAllForQuit')<body.index('beginQuitPlaybackFade(epoch: requestEpoch, group: fadeGroup)')
 assert 'cancelTrackingWithoutAnimation()' not in body
 assert 'duration: 0.77' in body and 'context.duration = 0.77' in body
 assert body.index('quitReplyPending = true')<body.index('fadeAllForQuit')
 assert 'fadeGroup.enter()\n        GORInputPanel.fadeAllForQuit' in body
 assert 'guard !quitApproved, quitRequestEpoch == requestEpoch' in body
 assert 'for panel in NSApp.windows.compactMap({ $0 as? NSPanel })' in panels
 assert 'for child in window.childWindows ?? []' in panels
 assert panels.index('panel.animator().alphaValue = 0')<panels.index('panel.orderOut(nil)')<panels.index('panel.close()')<panels.index('            completion()')
 assert 'window !== overlay' in panels and 'panels.reversed()' in panels
 for timing in ['0.44 / Double(satSteps)','0.66 / Double(volSteps)','0.88 / Double(briSteps)','.now() + 3.0']:
  assert timing in body
wiring(x,y)
for label,body,panels in [('instant',x.replace('context.duration = 0.77','context.duration = 0'),y),('all-input-only',x,y.replace('as? NSPanel','as? GORInputPanel')),('no-child',x,y.replace('for child in window.childWindows ?? []','for child in [] as [NSWindow]')),('panel-orderout-first',x,y.replace('panel.animator().alphaValue = 0','panel.orderOut(nil)')),('no-sentinel',x.replace('fadeGroup.enter()\n        GORInputPanel.fadeAllForQuit','GORInputPanel.fadeAllForQuit'),y)]:
 try:wiring(body,panels)
 except (AssertionError,ValueError):print('PASS wiring mutant RED',label)
 else:raise AssertionError('mutant accepted '+label)
print('PASS production phase wiring; NSPanel/About child coverage; five mutants RED')
if platform.system()!='Darwin':
 print('NOT_RUN AppKit typecheck, native object choreography, composite pixels, owner app/hardware/menu tracking (requires Darwin)');sys.exit(0)
setup=r'''import AppKit
import Foundation
final class Controller {
 var volume:Float = 0.5
 var firstMedia:Double?
 func suspendPresentationForQuit() {}
 func shutDownPlaybackCamera() {}
 func ipcCommand(_ s:String) { if firstMedia == nil {firstMedia=ProcessInfo.processInfo.systemUptime} }
 func fadeToOriginalBrightnessForQuit(_ done:@escaping ()->Void) {DispatchQueue.main.asyncAfter(deadline:.now()+0.88,execute:done)}
}
final class GORInputPanel:NSPanel {
PANEL_METHOD
}
final class Probe:NSObject {
 var pendingRestart=false,quitApproved=false,quitReplyPending=false,isQuittingDeliberately=false
 var quitRequestEpoch:UInt64=0
 var overlayWin:NSWindow?
 var controller:Controller?=Controller()
 var mpvProcess:Process?=Process()
 var checkTimer:Timer?
 var quitDeadlineWorkItem:DispatchWorkItem?
 var completed:Double?
 static func writeQuitToken(epoch:UInt64) {}
 func quitDebug(_ s:String) {print("TRACE",ProcessInfo.processInfo.systemUptime,s)}
 func stopOverlaySync() {}
 func armQuitWatchdog(epoch:UInt64) {}
 func drainQuitMusic(_ done:@escaping ()->Void) {done()}
 func completeQuitRequest(epoch:UInt64,reason:String) {
  guard quitReplyPending,epoch==quitRequestEpoch else{return}
  quitReplyPending=false;quitApproved=true;quitDeadlineWorkItem?.cancel()
  completed=ProcessInfo.processInfo.systemUptime;print("COMPLETE",completed!,reason)
 }
APP_METHODS
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
let probe=Probe()
func window(_ rect:NSRect,_ color:NSColor,_ panel:Bool)->NSWindow {
 let w:NSWindow = panel ? GORInputPanel(contentRect:rect,styleMask:.borderless,backing:.buffered,defer:false) : NSWindow(contentRect:rect,styleMask:.borderless,backing:.buffered,defer:false)
 w.isReleasedWhenClosed=false;w.backgroundColor=color;w.isOpaque=true;w.hasShadow=false;w.makeKeyAndOrderFront(nil);return w
}
let overlay=window(NSRect(x:100,y:100,width:500,height:320),.white,false)
let input=window(NSRect(x:140,y:170,width:100,height:100),.red,true)
let text=NSPanel(contentRect:NSRect(x:260,y:170,width:100,height:100),styleMask:.borderless,backing:.buffered,defer:false)
text.isReleasedWhenClosed=false;text.backgroundColor = .green;text.isOpaque=true;text.hasShadow=false;text.orderFront(nil)
let child=window(NSRect(x:380,y:170,width:100,height:100),.blue,false);input.addChildWindow(child,ordered:.above)
probe.overlayWin=overlay
app.activate(ignoringOtherApps:true)
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.15))
let out=ProcessInfo.processInfo.environment["GOR_QUIT_PIXEL_DIR"].map {URL(fileURLWithPath:$0)}
if let out {try! FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)}
var captures=[Process]()
let start=ProcessInfo.processInfo.systemUptime
func sample(_ t:Double) {
 let elapsed=ProcessInfo.processInfo.systemUptime-start
 print("FRAME",t,"actual",elapsed,"input",input.alphaValue,input.isVisible,"aboutText",text.alphaValue,text.isVisible,"child",child.alphaValue,child.isVisible,"overlay",overlay.alphaValue,overlay.isVisible)
 if let out {
  let capture=Process();capture.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture")
  capture.arguments=["-x",out.appendingPathComponent(String(format:"frame-%04d.png",Int(t*1000))).path]
  do {try capture.run();captures.append(capture)}catch {print("PIXEL_CAPTURE_NOT_RUN",error)}
 }
}
sample(0)
precondition(probe.applicationShouldTerminate(app) == .terminateLater)
precondition(probe.applicationShouldTerminate(app) == .terminateLater,"reentry schedules no second quit")
for t in [0.35,0.8,1.2,1.65] {DispatchQueue.main.asyncAfter(deadline:.now()+t) {sample(t)}}
DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {
 precondition(overlay.isVisible && overlay.alphaValue>0.99,"overlay must wait for panels")
 precondition(probe.controller?.firstMedia == nil,"media must wait for panels")
 precondition(!probe.quitApproved,"phase-one sentinel must hold approval")
}
RunLoop.main.run(until:Date(timeIntervalSinceNow:2.7))
precondition(probe.completed != nil,"quit must finish before existing3sdeadline")
precondition(probe.completed!-start>=1.4,"two ordered fades, never instant")
precondition(!input.isVisible && !text.isVisible && !child.isVisible && !overlay.isVisible,"all captured windows terminally hidden")
precondition(probe.controller!.firstMedia!-start>=0.70,"media starts only after panel phase")
for capture in captures {capture.waitUntilExit();print("PIXEL_CAPTURE_EXIT",capture.terminationStatus)}
print("PASS actual AppKit phase routing, panel+About text+child closure before overlay/media, reentry, no early approval, terminal cleanup")
print("NOT_RUN full application film quit, real hardware brightness, native menu tracking; composite pixels REQUIRE independent visual inspection")
'''
with tempfile.TemporaryDirectory(prefix='quit-fade-') as td:
 t=Path(td);src=t/'main.swift';src.write_text(setup.replace('PANEL_METHOD',y).replace('APP_METHODS',x))
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(src),'-framework','AppKit','-o',str(t/'probe')],check=True,timeout=90)
 subprocess.run([str(t/'probe')],check=True,timeout=20)
