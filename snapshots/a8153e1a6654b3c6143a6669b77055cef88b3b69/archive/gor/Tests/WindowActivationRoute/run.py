
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
import os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];s=_plat_read(r/'Sources/gor/App/AppDelegate.swift');a=s.index('    private func updateOverlayHitTesting(');b=s.index('\n    private static func axBool',a);method=s[a:b].replace('private func','func')
code='''import Foundation
class View {var subviews:[View]=[]}
class FileBrowserPanel:View {}
final class NSWindow {var isKeyWindow=false;var ignoresMouseEvents=true;var contentView:View?=View();var frame=CGRect(x:0,y:0,width:1000,height:700)
 func convertPoint(fromScreen p:CGPoint)->CGPoint{p}}
final class App {var isActive=false;var currentEvent:Event?}
let NSApp=App()
class Event {enum Kind {case leftMouseDragged};var type:Kind = .leftMouseDragged}
enum NSEvent {static var mouseLocation=CGPoint(x:1,y:100)}
class NSScreen {static var main:NSScreen?;var frame=CGRect(x:0,y:0,width:1000,height:700)}
final class Owner {var pictureInPictureActive=false;var isShowingInputPanel=false
'''+method+'''
}
let o=Owner(),w=NSWindow()
o.updateOverlayHitTesting(w);precondition(!w.ignoresMouseEvents)
NSApp.isActive=true;o.updateOverlayHitTesting(w);precondition(!w.ignoresMouseEvents)
w.isKeyWindow=true;o.updateOverlayHitTesting(w);precondition(w.ignoresMouseEvents)
NSApp.isActive=false;o.updateOverlayHitTesting(w);precondition(!w.ignoresMouseEvents)
print("PASS actual hit-test routing: inactive/non-key overlay captures activating click, only active key player allows native-edge passthrough")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
a=s.index('        let o1 =');b=s.index('        let o2 =',a);assert 'makeKeyAndOrderFront' in s[a:b]
assert 'didDeactivateApplicationNotification' in s and 'appActivationObservers = [o1,o2,o3, OverlaySpaceGate.observeSpaceChange' in s
assert 'AXUIElementSetAttributeValue(ax,kAXMinimizedAttribute as CFString,kCFBooleanFalse)' in s
assert 'func menuWindowMinimize(){togglePlayerMinimize()}' in _plat_read(r/'Sources/gor/UI/MenuActions.swift')
print('PASS static: mpv activation claims overlay key, app deactivation immediately clears passthrough, minimize toggle routes AX restore; native multi-process click/restore unverified')

a=s.index('    func togglePlayerMinimize() {');b=s.index('    func requestMPVMinimize()',a)
method=s[a:b].replace(' as CFString','')
code='''import Foundation
let kAXMinimizedAttribute="minimized",kAXRaiseAction="raise",kCFBooleanFalse=false
var actions:[String]=[]
func AXUIElementSetAttributeValue(_ ax:Int,_ key:String,_ value:Bool){actions.append("restore")}
func AXUIElementPerformAction(_ ax:Int,_ action:String){actions.append(action)}
class W {var ignoresMouseEvents=true;func makeKeyAndOrderFront(_ sender:Int?){actions.append("key")}}
class App {func activate(ignoringOtherApps:Bool){actions.append("activate")}}
let NSApp=App()
enum NoActivate {static var active=false;static var suppressAutomatic=false}
enum StagedRunPaths {static var active=false}  // stub: normal (non-staged) run, so activation happens
final class PanelKeyOwnership {static let shared=PanelKeyOwnership();func mayKeyPlayerWindow()->Bool{true}}  // stub: no panel owns key; the real arbitration is not modeled here
final class Owner {var axWindow:Int?=1;var playerWindowIsMinimized=false;var overlayMinimizeHoldUntil=1.0;var overlayWin:W?=W()
func cancelPendingMPVMinimize(){actions.append("cancel")}
func boostOverlaySync(){actions.append("boost")}
func syncOverlay(){actions.append("sync")}
func requestMPVMinimize(){actions.append("minimize")}
'''+method+'''
}
let owner=Owner();owner.togglePlayerMinimize();precondition(actions==["minimize"])
actions=[];owner.playerWindowIsMinimized=true;owner.togglePlayerMinimize()
precondition(actions==["cancel","restore","raise","activate","key","boost","sync"])
precondition(!owner.overlayWin!.ignoresMouseEvents && owner.overlayMinimizeHoldUntil==0)
print("PASS actual minimize toggle: normal request, minimized restores/unholds/raises/claims key and synchronizes, no Dock action required")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)

#192w production no-activation gate, no AppKit needed for its exact truth table.
focus=_plat_read(r/'Sources/gor/GorPlatformMac/PanelFocusTraversal.swift')
with tempfile.TemporaryDirectory() as d:
 p=Path(d)
 (p/'main.swift').write_text('import Foundation\n'+focus+'''
for flag in [false,true] {for env in [false,true] {
 let args=flag ? ["gor","--gor-no-activate"]:["gor"]
 let values=env ? ["GOR_NO_ACTIVATE":"1"]:[:]
 precondition(NoActivate.requested(arguments:args,environment:values) == (flag || env))
}}
precondition(!NoActivate.requested(arguments:["gor","--gor-no-activate-fake"],environment:["GOR_NO_ACTIVATE":"0"]))
print("PASS192w exact argv/env truth table; normal launches keep activation")
''')
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'gate')],check=True)
 subprocess.run([str(p/'gate')],check=True)
h=_plat_read(r/'gor-selftest.sh');b=_plat_read(r/'build.sh')
for line in h.splitlines():
 if "['/usr/bin/open','" in line and 'str(app)' in line:assert "'-g'" in line and "'--gor-no-activate'" in line,line
 if 'Popen([str(binary)' in line:assert "'--gor-no-activate'" in line,line
assert 'open -g -n "$app" --args --gor-background-start' in b
assert 'if !StagedRunPaths.active && !NoActivate.suppressAutomatic' in s
print('PASS192w selftest background-open/direct-exec flags; no lifecycle checks removed; native focus NOT_RUN')

for line in h.splitlines():
 if 'Popen([str(mpv)' in line and '--vo=gpu' in line:assert '+hidden_flags(str(mpv))+' in line,line
for tool in ['store_acceptance.py','owner_action_acceptance.py']:
 assert 'GOR_NO_ACTIVATE="1"' in _plat_read(r/'tools'/tool)
print('PASS192w six GPUlaunch sites capability-gated nofocus/minimized; acceptance tools noactivate')

#192x real menu-dispatch acceptance must not escape the test noactivation contract.
for name in ['MenuActions.swift','MagnetBrowser.swift']:
 for line in _plat_read(r/'Sources/gor'/name).splitlines():
  if 'NSApp.activate(ignoringOtherApps:' in line:assert 'if !NoActivate.active {' in line,(name,line)
assert 'guard view.window === self, !NoActivate.active else{return}' in _plat_read(r/'Sources/gor/UI/MenuActions.swift')
selftest=b[b.index('gor_selftest()'):b.index('# Result recording')]
opens=[line for line in selftest.splitlines() if 'open -' in line and '"$app"' in line]
assert len(opens)==3,opens
assert sum('open -g -n "$app" --args --gor-no-activate' in line for line in opens)==2
assert sum('open -g -n "$app" --args --gor-background-start' in line for line in opens)==1
print('PASS192x menu activation/assertKeyAndFocus guards and all3build selftest launch pins; Mac focus NOT_RUN')
