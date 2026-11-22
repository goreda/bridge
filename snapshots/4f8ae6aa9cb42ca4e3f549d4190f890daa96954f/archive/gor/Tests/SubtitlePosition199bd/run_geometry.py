from pathlib import Path
import subprocess,os
r=Path(__file__).resolve().parent
s=(r/os.environ.get('SOURCE_DIR','post')/'Packages/gorav/Sources/GorAVMetalPresenter/core/MetalPresenter.swift').read_text()
a=s.index('        v.subtitleVideoRect =');b=s.index('        v.onResize =',a)
closure=s[a:b]
code='''import Foundation
struct Rect {let x:Double,y:Double,w:Double,h:Double}
struct Crop {let width=1.0,height=1.0}
func effectiveVideoRect(drawableW:Int,drawableH:Int,frameW:Int,frameH:Int,_ transform:Int)->Rect? {Rect(x:Double(drawableW)/10,y:Double(drawableH)/10,w:Double(drawableW)*0.8,h:Double(drawableH)*0.8)}
final class Renderer {func lastFrameSize()->(width:Int,height:Int)? {(1920,1080)};func currentSourceCrop()->Crop{Crop()};func currentHostTransform()->Int{0}}
final class View {var bounds=NSRect(x:20,y:30,width:500,height:250);var subtitleVideoRect:(()->NSRect?)?}
final class Presenter {
 let renderer=Renderer();var drawablePixelSize=(w:1000,h:500)
 func install(_ v:View) {
'''+closure+''' }
}
@main struct Tests {
 static func main(){
 let p=Presenter(),v=View();p.install(v)
 var n=0
 func check(_ b:Bool){n+=1;if !b{fatalError("drawable/AppKit coordinate conversion")}}
 let a=v.subtitleVideoRect!()!;check(a==NSRect(x:70,y:55,width:400,height:200))
 p.drawablePixelSize=(500,250);check(v.subtitleVideoRect!()!==a)
 p.drawablePixelSize=(0,0);check(v.subtitleVideoRect!()==nil)
 print("PASS \\(n) actual drawable conversion closure checks; GPU geometry provider stubbed")
 }
}
'''
p=r/'GeometryProjection.swift';p.write_text(code)
for opt in os.environ.get('OPTIONS','-Onone -O').split():
 c=subprocess.run([os.environ.get('SWIFTC','swiftc'),'-parse-as-library','-swift-version','5',opt,str(p),'-o',str(r/'geometry-tests')],capture_output=True,text=True)
 if c.returncode:raise SystemExit(c.stderr)
 t=subprocess.run([str(r/'geometry-tests')],capture_output=True,text=True);print(opt,t.stdout,t.stderr)
 if t.returncode:raise SystemExit(t.returncode)
