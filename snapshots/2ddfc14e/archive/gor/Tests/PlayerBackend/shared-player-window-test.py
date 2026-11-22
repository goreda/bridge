#!/usr/bin/env python3
"""Native AppKit actual host/factory object/style/frame parity regression, not pixels."""
from pathlib import Path
import os,subprocess,tempfile,sys
r=Path(__file__).resolve().parents[2]
app=(r/'Sources/gor/App/AppDelegate.swift').read_text()
host=(r/'Sources/gor/Engine/GorAVHostWindow.swift').read_text()
player=(r/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text()
a=app.index('    static func playerWindow(frame:NSRect)');b=app.index('\n    // Claim',a);factory=app[a:b]
assert 'DraggableOverlayWindow.playerWindow(frame:frame)' in app[app.index('    func attachOverlay'):]
assert 'GorAVPlayerHost(inWindowChrome:true,playerWindow:self.overlayWin)' in app
assert 'GorAVHostWindow(contentView: content,playerWindow:playerWindow)' in player
assert 'host.window.center()' not in player
assert 'styleMask: [.titled' not in host
move=app[app.index('    func moveMpv(dx:'):app.index('    private func initializeOverlayDragPosition')]
assert move.index('if activePlayerEngine == .gorav')<move.index('guard let ax = axWindow')
assert 'win.setFrameOrigin(NSPoint(x:win.frame.minX+dx,y:win.frame.minY-dy))' in move
assert 'case "hold":' in player and 'hostWindow?.hold(dx:x,dy:y,dz:z)' in player
retire=app[app.index('    private func retireMPVForEmbedded()'):app.index('    private func closeEmbeddedForMPV()')]
assert 'overlayWin=nil' not in retire and 'orderOut' not in retire
if '--wiring-only' in sys.argv:
 print('PASS shared borderless factory; actual player window passed across handoff, not recentered/retired; AppKit NOT_RUN');raise SystemExit(0)
main='''import AppKit
@main struct WindowProbe { @MainActor static func main() {
let app=NSApplication.shared
let expected=NSRect(x:111,y:123,width:932,height:524)
let original=DraggableOverlayWindow.playerWindow(frame:expected)
original.makeKeyAndOrderFront(nil)
let content=NSView()
let host=GorAVHostWindow(contentView:content,playerWindow:original,onTransform:{_ in})
precondition(host.window === original,"engine swap must retain exact player object")
precondition(host.window.frame == expected,"engine swap must retain exact frame")
precondition(!host.window.styleMask.contains(.titled))
precondition(!host.window.styleMask.contains(.closable))
precondition(host.window.standardWindowButton(.closeButton)?.isHidden != false)
precondition(host.window.contentView === content)
host.open(videoWidth:3840,height:2160)
precondition(host.window.frame == expected,"delayed metadata must not reset reused frame")
original.displayIfNeeded()
if let path=ProcessInfo.processInfo.environment["GOR_WINDOW_PIXEL_PROOF"] {
 let capture=Process();capture.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture")
 capture.arguments=["-x","-l",String(original.windowNumber),path]
 do {try capture.run();capture.waitUntilExit();print("PIXEL_CAPTURE_EXIT \(capture.terminationStatus)")} catch {print("PIXEL_CAPTURE_NOT_RUN \(error)")}
}
host.close();host.close()
let screen=NSRect(x:-1440,y:24,width:1440,height:876)
let cold=GorAVHostWindow.initialPlayerFrame(screen:screen)
precondition(cold.width==576 && cold.height==324)
precondition(cold.midX==screen.midX && cold.midY==screen.midY)
print("PASS actual AppKit same-window identity/frame, borderless no traffic lights, source metadata invariance, cold40percent frame, repeat close")
}}
'''
with tempfile.TemporaryDirectory(prefix='player-window-') as td:
 t=Path(td);(t/'main.swift').write_text(main)
 (t/'Factory.swift').write_text('import AppKit\nfinal class DraggableOverlayWindow:NSWindow {override var canBecomeKey:Bool {true}\n'+factory+'}\n')
 for mode in ['-Onone','-O']:
  subprocess.run([os.environ.get('SWIFTC','swiftc'),'-parse-as-library',mode,str(r/'Sources/gor/Engine/GorAVHostMotion.swift'),str(r/'Sources/gor/Engine/GorAVHostWindow.swift'),str(t/'Factory.swift'),str(t/'main.swift'),'-framework','AppKit','-o',str(t/'probe')],check=True)
  subprocess.run([str(t/'probe')],check=True,timeout=15)
print('NOT_RUN owner visible pixels, full engine film playback or complete input/Dock/fullscreen parity')
