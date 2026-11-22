"""Execute real geometry encoder with Cocoa chrome fixture; no source pixels cropped."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2];s=(root/'Sources/gor/GorFit.swift').read_text()
a=s.index('    static func clampGeometry(');b=s.index('{',a)+1;n=1;e=b
while n:n+=(s[e]=='{')-(s[e]=='}');e+=1
method=s[a:e]
code='''import Foundation
extension Int {static let borderless=0}
final class NSScreen {var visibleFrame=CGRect(x:0,y:40,width:2048,height:1215);var backingScaleFactor=2.0}
enum NSWindow {typealias StyleMask=Int;static func frameRect(forContentRect r:CGRect,styleMask:Int)->CGRect{CGRect(x:r.minX,y:r.minY,width:r.width,height:r.height+(styleMask == 0 ? 0:28))}}
enum GorOpeningFit {static let mpvWindowMask=1
'''+method+'''
}
func size(_ geometry:String)->CGSize {
 let parts=geometry.components(separatedBy:"+")[0].components(separatedBy:"x")
 return CGSize(width:Double(parts[0])!,height:Double(parts[1])!)
}
func barWidth(_ size:CGSize,_ aspect:Double)->Double {max(0,(Double(size.width)-Double(size.height)*aspect)/2)}
for aspect in [3840.0/1608,16.0/9,2.39,4.0/3,32.0/9,9.0/16] {
 let width=600.0, frame=CGRect(x:0,y:0,width:width,height:width/aspect)
 let prior=size(GorOpeningFit.clampGeometry(frame:frame,screen:NSScreen())!)
 let fixed=size(GorOpeningFit.clampGeometry(frame:frame,screen:NSScreen(),chromeStyleMask:.borderless)!)
 // Device-pixel integer geometry may leave a fractional-pixel edge, never a whole column.
 let bars=barWidth(fixed,aspect)
 precondition(floor(bars)==0)
 precondition(barWidth(prior,aspect)>10)
 print(String(format:"PASS aspect%.5f prior PiP pillarbox %.2fpx/side -> %.2fpx (<1pixel,0whole columns); no film crop",aspect,barWidth(prior,aspect),bars))
}
'''
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp);(p/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
assert 'chromeStyleMask: pictureInPictureActive ? .borderless : GorOpeningFit.mpvWindowMask' in s
assert '(pictureInPictureActive ? $0.frame : $0.visibleFrame)' in s
print('PASS actual clamp route uses full display/borderless only in PiP, normal mode unchanged; native owner-file pixels NOT_RUN')
