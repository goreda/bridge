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
s=(r/'Sources/gor/App/AppDelegate.swift').read_text();a=s.index('    private func commitOverlayFrame(');b=s.index('\n    func syncOverlay()',a);method=s[a:b].replace('private func','func')
code='''import Foundation
var order:[String]=[]
enum CATransaction {
 static var disabled=false
 static func begin(){order.append("begin")}
 static func setDisableActions(_ value:Bool){disabled=value;order.append("disable")}
 static func commit(){order.append("commit");disabled=false}
}
class View {
 var needsLayout=false
 func layoutSubtreeIfNeeded(){precondition(CATransaction.disabled && needsLayout);order.append("layout")}
}
class NSWindow {
 var contentView:View?=View()
 func setFrame(_ f:NSRect,display:Bool,animate:Bool){precondition(CATransaction.disabled && !animate);order.append("frame")}
}
final class Owner {
'''+method+'''
}
let owner=Owner(),window=NSWindow()
owner.commitOverlayFrame(CGRect(x:100,y:200,width:1200,height:700),window:window)
precondition(order==["begin","disable","frame","layout","commit"])
window.contentView=nil;order=[]
owner.commitOverlayFrame(.zero,window:window)
precondition(order==["begin","disable","frame","commit"])
print("PASS actual receipt handler: disable geometry animations before frame, synchronous descendant layout before commit, no delayed work; no-content safe")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
p=(_pp_split().path(r,'PPController.swift')).read_text();a=p.index('    private func applyVideoFrame(bounds: CGRect)');body=p[a:p.index('\n    // MARK:',a)]
assert body.index('setDisableActions(true)')<body.index('vrChromeReplicator.frame')
assert 'defer { CATransaction.commit() }' in body
sp=(r/'Sources/gor/UI/SpineUI.swift').read_text();a=sp.index('    override func layout() {',sp.index('final class SpineUI:'))
assert sp[a:].index('setDisableActions(true)')<sp[a:].index('vrChromeReplicator.frame')
assert 'overlayWin?.setFrame' not in s
print('PASS static: all overlay receipt routes use atomic handler, PPController + SpineUI HUD parent geometry share disabled-actions transactions; native pixels/motion unverified')
