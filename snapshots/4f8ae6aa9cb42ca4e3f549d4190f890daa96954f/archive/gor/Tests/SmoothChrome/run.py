"""Compile actual geometry font fanout with boundary-only font/view stubs."""
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
s=(r/'Sources/gor/UI/PhotonFont.swift').read_text()
def block(key):
 a=s.index(key);i=s.index('{',a);n=1;j=i+1
 while n:n+=(s[j]=='{')-(s[j]=='}');j+=1
 return s[a:j]
code='''import Foundation
final class WeakBox {var isAlive=true;init(_ value:AnyObject){}}
final class VariationBroadcaster {static let shared=VariationBroadcaster();var seen:[Double]=[];func poke(){seen.append(Double(PhotonFont.chromeScale))}}
'''+block('final class LayoutEngine {')+'''
enum PhotonFont {static var chromeScale:CGFloat=1
'''+block('    static func setChromeLayoutScale(')+'''
}
var callbacks:[Double]=[]
LayoutEngine.shared.addObserver {callbacks.append(Double(PhotonFont.chromeScale))}
for scenario in ["fullscreen-entry","fullscreen-exit","window-resize","SBS-rail","crop-fit"] {
 for scale in stride(from:0.98,through:0.20,by:-0.02) {
  let before=callbacks.count
  PhotonFont.setChromeLayoutScale(CGFloat(scale))
  precondition(callbacks.count==before+1,"geometry font layout deferred")
  precondition(abs(callbacks.last!-scale)<0.00001)
  precondition(abs(VariationBroadcaster.shared.seen.last!-scale)<0.00001,"font paint deferred")
 }
 print("PASS actual synchronous layout/font broadcast on every "+scenario+" frame")
}
let before=callbacks.count
PhotonFont.setChromeLayoutScale(PhotonFont.chromeScale)
precondition(callbacks.count==before,"unchanged scale causes redundant fanout")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
a=(r/'Sources/gor/App/AppDelegate.swift').read_text()
b=a[a.index('private func commitOverlayFrame('):a.index('    func syncOverlay()')]
assert 'setDisableActions(true)' in b and 'layoutSubtreeIfNeeded()' in b and 'displayIfNeeded()' in b
p=(_pp_split().path(r,'PPController.swift')).read_text()
assert 'if mediaTransitionPending {deferredWindowRefitAspect=a;return}' in p
assert 'if cropPackingNeedsRedetect {startAutomaticCropDetection(needsRedetect:true)}' in p
assert 'if dw>0 && dh>0 {applyOpeningFitIfArmed(videoW:finalW,videoH:finalH)}' in p
print('PASS source wiring: one no-animation overlay transaction; refit intent retained; same-dimension opening and packing retries')
print('NOT_RUN AppKit render timing and native fullscreen pixels')
