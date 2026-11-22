"""Execute actual production Swift region and layout with layer stubs.

Geometry fixture only: CoreAnimation/AppKit glyph/shadow pixels remain native.
"""
from pathlib import Path
import os,subprocess,tempfile,json
root=Path(__file__).resolve().parents[2];s=(root/'Sources/gor/UI/SpineUI.swift').read_text()
a=s.index('    private func photonHUDRegion()');b=s.index('    /// Photon HUD frames arrive',a);region=s[a:b].replace('private func','func')
a=s.index('    private func layoutPhotonHUD()');b=s.index('    /// Scrolls the photon HUD',a);layout=s[a:b].replace('private func','func')
assert 'photonHUDScrollIndicator' not in s and 'updatePhotonHUDScrollIndicator' not in s
assert 'func scrollPhotonHUDIfNeeded' in s
# Keep all production capacity, scrolling, frame assignment and fold-target code.
# Swift type-checks the same method; only platform objects are recording stubs.
code=r'''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
enum PhotonFont {static let size:CGFloat=20,charW:CGFloat=12,pad:CGFloat=10;static let chromeSize:CGFloat=20,chromeCharW:CGFloat=12,chromePad:CGFloat=10;static func ct()->String {"font"};static func chromeCt()->String {"font"}}
let PAD:CGFloat=10
class CALayer {var opacity:Float=1;var frame=CGRect.zero;func removeFromSuperlayer(){};func addSublayer(_ l:CALayer){}}
class CATextLayer:CALayer {var fontSize:CGFloat=20;var foregroundColor="";var contentsScale:CGFloat=2;var isWrapped=false;var truncationMode=Mode.end;var font="";var alignmentMode=Mode.left;var shadowColor="";var shadowRadius:CGFloat=0;var shadowOpacity:Float=0;var shadowOffset=CGSize.zero;var string=""}
enum Mode {case end,left}
struct Color {var cgColor:String {"color"};func withAlphaComponent(_ x:CGFloat)->Color{self}}
enum NSColor {static let white=Color(),black=Color()}
struct Screen {var backingScaleFactor:CGFloat=2}
enum NSScreen {static var main:Screen?=Screen()}
enum CATransaction {static func begin(){};static func commit(){};static func setDisableActions(_ x:Bool){}}
enum PPController {static let shadowRadius:CGFloat=0;static let shadowOpacity:Float=0}
enum GeomTrace {static func logChanged(_ k:String,_ s:String){}}
class View {var bounds=CGRect(x:0,y:0,width:1200,height:800);var layer:CALayer?=CALayer()}
class Button {var frame=CGRect(x:0,y:740,width:20,height:26)}
class Spine {
 var frame=CGRect(x:0,y:0,width:100,height:800),hudCropBounds=CGRect.zero
 var btnQ=Button();var superview:View?=View();var hudUpperRowCount=0,magnetGridRowCount=0;var streamControlsVisible=false
 var photonHUDStrings:[String]=[],photonHUDLayers:[CATextLayer]=[],foldableHUDLayers:[(layer:CATextLayer,section:String)]=[]
 var photonHUDMaxScrollRows=0,photonHUDFirstRow=0
 var alphaValue:CGFloat=1;var vrParentChromeContainer:CALayer?
 func applyVariationToOSDLayers(){}
__REGION__
__LAYOUT__
}
var records:[[String:Any]]=[]
for height in [480,1080,2160] {
 for crop in [CGRect(x:0,y:0,width:CGFloat(height)*16/9,height:CGFloat(height)),CGRect(x:72,y:38,width:CGFloat(height)*1.2,height:CGFloat(height)*0.65),CGRect(x:160,y:140,width:100,height:20)] {
  for rows in [0,1,8,36] {for first in [0,100] {
   let p=Spine();p.superview!.bounds=CGRect(x:0,y:0,width:CGFloat(height)*16/9,height:CGFloat(height))
   p.frame=CGRect(x:crop.minX,y:crop.minY,width:70,height:crop.height);p.hudCropBounds=crop
   p.btnQ.frame=CGRect(x:0,y:max(0,crop.height-36),width:20,height:26)
   p.hudUpperRowCount=rows;p.magnetGridRowCount=rows;p.streamControlsVisible=rows>0
   p.photonHUDStrings=(0..<36).map{"photon\trow \($0)"};p.photonHUDFirstRow=first;p.layoutPhotonHUD()
   for l in p.photonHUDLayers {
    precondition(l.frame.minX>=crop.minX && l.frame.maxX<=crop.maxX)
    precondition(l.frame.minY>=crop.minY && l.frame.maxY<=crop.maxY)
    precondition(l.frame.height==26 && l.fontSize==20 && !l.isWrapped && l.truncationMode == .end)
   }
   let r=p.photonHUDRegion();let capacity=Int(max(0,r.top-r.bottom)/r.lineH)
   precondition(p.photonHUDLayers.count==(capacity>=1 && r.width>0 ? min(36,capacity):0))
   if capacity>=1 && r.width>0 {precondition(p.photonHUDFirstRow==min(first,max(0,36-capacity)))}
   // Repeat in-place refresh and hide/recover: production code must not retain spilled layers.
   p.layoutPhotonHUD();let count=p.photonHUDLayers.count
   p.hudCropBounds=CGRect(x:crop.minX,y:crop.minY,width:1,height:1);p.layoutPhotonHUD();precondition(p.photonHUDLayers.isEmpty)
   p.hudCropBounds=crop;p.layoutPhotonHUD();precondition(p.photonHUDLayers.count==count)
   if rows==1 && first==0 {records.append(["height":height,"crop":[Double(crop.minX),Double(crop.minY),Double(crop.width),Double(crop.height)],"frames":p.photonHUDLayers.map{[Double($0.frame.minX),Double($0.frame.minY),Double($0.frame.width),Double($0.frame.height)]}])}
  }}
 }
}
let data=try! JSONSerialization.data(withJSONObject:records,options:[.sortedKeys]);print(String(data:data,encoding:.utf8)!)
'''.replace('__REGION__',region).replace('__LAYOUT__',layout)
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','/tmp/swift6/usr/bin/swiftc'),'-g',str(p/'main.swift'),'-o',str(p/'check')],check=True)
 result=subprocess.run([str(p/'check')],capture_output=True,text=True)
 if result.returncode:print(result.stderr);raise SystemExit(result.returncode)
 records=json.loads(result.stdout)
 if len(os.sys.argv)>1:Path(os.sys.argv[1]).write_text(json.dumps(records,indent=2))
print('PASS actual production Swift photon region/layout: 480/1080/2160, full/crop/collapsed, 0/1/8/36 magnet rows, top/bottom scrolling, in-place refresh and collapse/recovery. All layer frames inside visible picture, exact font size/no transform. Native glyph/shadow pixels NOT_RUN.')
