"""Production photon region, AppKit-free fixture. Native Mac pixels are a separate gate."""
from pathlib import Path
import tempfile, subprocess, os
root=Path(__file__).resolve().parents[2]
s=(root/'Sources/gor/UI/SpineUI.swift').read_text()
a=s.index('    private func photonHUDRegion()');b=s.index('    /// Photon HUD frames arrive',a)
method=s[a:b].replace('private func','func')
code='''import Foundation
enum PhotonFont {static let size:CGFloat=20;static let charW:CGFloat=12;static let pad:CGFloat=10}
let PAD:CGFloat=10
class View {var bounds=CGRect(x:0,y:0,width:1200,height:800)}
class Button {var frame=CGRect(x:0,y:740,width:20,height:26)}
class Spine {
 var frame=CGRect(x:0,y:0,width:100,height:800)
 var hudCropBounds=CGRect.zero
 var btnQ=Button();var superview:View?=View()
 var hudUpperRowCount=0,magnetGridRowCount=0
 var streamControlsVisible=false
'''+method+'''
}
let spine=Spine()
for rows in [1,3,8,16] {
 spine.hudUpperRowCount=rows;spine.magnetGridRowCount=rows
 spine.streamControlsVisible=false
 let old=spine.photonHUDRegion()
 spine.streamControlsVisible=true
 let shifted=spine.photonHUDRegion()
 precondition(shifted.top-old.top==old.lineH)
 precondition(shifted.x==old.x && shifted.bottom==old.bottom && shifted.width==old.width)
 print("PASS magnet rows=\(rows): photon top \(old.top)->\(shifted.top), +\(old.lineH)pt exactly one row up")
}
spine.hudUpperRowCount=0;spine.magnetGridRowCount=0
let open=spine.photonHUDRegion();spine.streamControlsVisible=false
precondition(open.top==spine.photonHUDRegion().top)
spine.hudCropBounds=CGRect(x:30,y:50,width:500,height:200)
spine.hudUpperRowCount=1;spine.magnetGridRowCount=1;spine.streamControlsVisible=true
let clamped=spine.photonHUDRegion()
precondition(clamped.top<=250 && clamped.bottom>=50 && clamped.x>=30 && clamped.x+clamped.width<=530)
print("PASS empty/nonmagnet anchor unchanged; four-edge crop clamp retained; font and row height unchanged")
'''
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp);(p/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
