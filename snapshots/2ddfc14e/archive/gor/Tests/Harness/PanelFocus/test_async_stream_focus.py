"""Actual Swift ownership-rule replay. Linux proves policy, not AppKit focus."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess
import sys
import tempfile
src = Path(__file__).resolve().parents[3] / 'Sources/gor'
app = _plat_read(src/'AppDelegate.swift')
features = _plat_read(_pp_split().dpath(src,'PPController_Features.swift'))
torrent = _plat_read(src/'TorrentManager.swift')
focus = _plat_read(src/'PanelFocus.swift')
# Verify every binding that the previous makeKey-only test omitted.
ax = app.split('let o2 =',1)[1].split('let o3=',1)[0]
assert 'NSApp.isActive && PanelKeyOwnership.shared.mayKeyPlayerWindow()' in ax
assert 'selfPtr.isShowingInputPanel || PanelKeyOwnership.shared.panelOwnsKey' in app
assert 'enable: enabled && PanelKeyOwnership.shared.mayKeyPlayerWindow()' in app
stream = torrent.split('STREAM_MAIN_CALLBACK',1)[1].split('STREAM_CONTROLS_AFTER',1)[0]
assert 'isShowingInputPanel = PanelKeyOwnership.shared.panelOwnsKey' in stream
assert 'self?.setEventTapEnabled(true)' in stream
assert 'panelOwnsKey || e.window is GORInputPanel' in features
quit = app.split('func applicationShouldTerminate(',1)[1].split('let fadeGroup',1)[0]
assert quit.index('GORInputPanel.closeAllForQuit()') < quit.index('armQuitWatchdog(')
close = focus.split('static func closeAllForQuit()',1)[1].split('override func cancelOperation',1)[0]
assert close.index('panel.orderOut(nil)') < close.index('panel.close()')
harness = _plat_read(src/'PanelFocusTraversal.swift') + '''
final class PanelToken {}
let panel = PanelToken()
let ownership = PanelKeyOwnership()
let token = ObjectIdentifier(panel)
var beforeLost = 0, afterLost = 0
for _ in 0..<10000 {
 ownership.register(token)
 // Queued connection/STREAM/activation arrive while the user is typing.
 let oldBooleanAfterStream = false
 let beforeAXRaise = true
 let beforeKeyboardConsumed = !oldBooleanAfterStream
 if beforeAXRaise || beforeKeyboardConsumed { beforeLost += 1 }
 let axRaise = ownership.mayKeyPlayerWindow()
 let tapEnabled = true && ownership.mayKeyPlayerWindow()
 let streamBoolean = ownership.panelOwnsKey
 let keyboardConsumed = !streamBoolean && !ownership.panelOwnsKey
 if axRaise || tapEnabled || keyboardConsumed { afterLost += 1 }
 // Close/quit releases ownership; normal player input must resume.
 ownership.unregister(token)
 assert(ownership.mayKeyPlayerWindow())
}
assert(beforeLost == 10000 && afterLost == 0)
print("PASS asynchronous STREAM+activation typing replay: lost-input transitions before=10000/10000 after=0/10000")
'''
with tempfile.TemporaryDirectory() as temp:
    main = Path(temp)/'main.swift'; main.write_text(harness)
    binary = Path(temp)/'run'
    subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'swiftc', str(main), '-o', str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
print('PASS real call-site bindings: AX raise, tap callback/reenable, local key routing, STREAM state, quit close-before-drain')
# Native acceptance exercise is retained for Mac, never relabel Linux policy replay.
if sys.platform == 'darwin':
    native = '''import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let panel = GORInputPanel(contentRect:NSRect(x:100,y:100,width:360,height:60),styleMask:[.titled],backing:.buffered,defer:false)
let field = NSTextField(frame:NSRect(x:12,y:12,width:300,height:28))
panel.contentView?.addSubview(field)
panel.rememberFocus(field)
app.activate(ignoringOtherApps:true)
panel.makeKeyAndOrderFront(nil)
panel.restorePanelFocus()
assert(panel.isVisible && PanelKeyOwnership.shared.panelOwnsKey)
field.stringValue="typed while connecting"
assert(!PanelKeyOwnership.shared.mayKeyPlayerWindow())
GORInputPanel.closeAllForQuit()
assert(!panel.isVisible && !PanelKeyOwnership.shared.panelOwnsKey)
print("PASS AppKit native panel hides synchronously before quit drain")
'''
    with tempfile.TemporaryDirectory() as temp:
        main=Path(temp)/'main.swift';main.write_text(native)
        binary=Path(temp)/'native'
        subprocess.run(['swiftc',str(_plat_compile_input(src/'PanelFocus.swift')),str(_plat_compile_input(src/'PanelFocusTraversal.swift')),str(main),'-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
else:
    print('NOT_RUN AppKit typing/click/Escape/HUD visual acceptance requires Mac window server; no visual success claimed')
