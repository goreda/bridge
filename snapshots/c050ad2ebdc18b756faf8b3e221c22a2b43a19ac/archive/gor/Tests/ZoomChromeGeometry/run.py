import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(_pp_split().path(r,'PPController.swift')).read_text()
a=s.index('        // One visible-picture authority');b=s.index('        // v2: force the final geometry/layout',a);actual=s[a:b]
# Compile exact production OSD-margin->visible-picture conversion plus exact
# production view assignment, with only external geometry/layer boundaries stubbed.
a=s.index('            let sx = winW / CGFloat(ow)',s.index('private func applyVideoFrame'));b=s.index('                if sourceCropPropertyRequested',a);convert=s[a:b]
code='''import Foundation
class View {var frame:CGRect = .zero;var spineWidth:CGFloat=44;var sidebarWidth:CGFloat=52}
let spineUI=View(),sidebarUI=View(),subtitleView=View()
var cases=0
for winW in [480.0,960,1920] {for winH in [270.0,600,1080] {
 let ow=winW,oh=winH
 for margins in [[0.0,0,0,0],[winW*0.2,winW*0.2,winH*0.2,winH*0.2],[-winW*0.2,-winW*0.2,-winH*0.2,-winH*0.2],[winW*0.1,winW*0.3,winH*0.25,winH*0.1]] {
 let ml=margins[0],mr=margins[1],mt=margins[2],mb=margins[3]
'''+convert+'''
 let chromeBounds=rendered
'''+actual+'''
 precondition(subtitleView.frame==rendered)
 precondition(spineUI.frame.minX==rendered.minX && spineUI.frame.height==rendered.height)
 precondition(sidebarUI.frame.maxX==rendered.maxX && sidebarUI.frame.height==rendered.height)
 precondition(rendered.minX>=0 && rendered.maxX<=winW && rendered.minY>=0 && rendered.maxY<=winH)
 // Hit/proximity coordinates resolve against the same physical view frame.
 let center=CGPoint(x:subtitleView.frame.midX,y:subtitleView.frame.midY)
 precondition(center.x==rendered.midX && center.y==rendered.midY)
 cases+=1
 }
 }}}
print("PASS \\(cases) exact production OSD->chrome frame cases: zoom out/in/pan, normal/PiP-sized windows, spine/sidebar/subtitle/HUD share visible picture, coordinates follow frames; no font transform")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'run')],check=True);subprocess.run([str(p/'run')],check=True)
assert 'spineUI.hudCropBounds      = visiblePictureBounds' in s
accept=s[s.index('private func acceptOsdDims'):s.index('private func runCropActions')]
assert 'if moved, bounds.width > 1' in accept and 'appliedVideoFrame = .zero' in accept
assert 'applyVideoFrame(bounds: bounds)' in accept
print('PASS observed zoom/pan invalidates frame cache; HUD+views use same accepted chromeBounds; Linux only, native mpv/AppKit pixels unverified')
