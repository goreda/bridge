import Foundation
func expect(_ b:Bool,_ s:String){precondition(b,s);print("PASS "+s)}
// Synthetic luma: eye views share content with a 3 px disparity, as Block185 fixtures do.
let width=320,height=90
func sbs()->Data {
 var a=[UInt8](repeating:0,count:width*height)
 for y in 0..<height {for x in 0..<width {let ex=x%(width/2),eye=x/(width/2);let sx=ex-(eye==1 ? 3:0)
  a[y*width+x]=UInt8(30+(((sx+width)%width)*37+y*19+(((sx+width)%width)*y)%67)%200)}}
 return Data(a)
}
let frames=(0..<8).map{_ in sbs()}
func probeAspect(_ w:Double,_ h:Double,_ name:String)->Double? {
 var r=VRProjectionProbe.Result(status:"x");r.stereoSBS=true
 let meta=try! JSONSerialization.data(withJSONObject:["streams":[["width":w,"height":h,"sample_aspect_ratio":"1:1"]]])
 VRProjectionProbe.applyGeometry(&r,frames:frames,metadata:meta,filename:name)
 return r.eyeAspect
}
// Frame-layout fallback keeps existing results.
expect(abs(probeAspect(1920,1080,"movie.mkv")!-16/9)<0.001,"half-sbs 16:9 no token: eye 16:9")
expect(abs(probeAspect(3840,1080,"movie.mkv")!-16/9)<0.001,"full-sbs 32:9 no token: eye 16:9")
// Explicit token must agree with SBSGeometry.resolve (probe used to ignore it).
for (w,h,name) in [(3840.0,1080.0,"movie.hsbs.mkv"),(1920.0,1080.0,"movie.fsbs.mkv"),(3840.0,1080.0,"movie.full.sbs.mkv"),(1920.0,1080.0,"movie.half-sbs.mkv")] {
 let g=SBSGeometry.resolve(width:w,height:h,pixelAspect:1,filename:name,stereoProven:true)!.aspect
 let p=probeAspect(w,h,name)!
 expect(abs(g-p)<0.001,"probe equals SBSGeometry for \(name): \(p) vs \(g)")
}
expect(SBSGeometry.packing(width:3840,height:1080,filename:"x.hsbs.mkv").full==false,"hsbs token wins over 32:9 shape")
expect(SBSGeometry.packing(width:1920,height:1080,filename:"x.fsbs.mkv").full==true,"fsbs token wins over 16:9 shape")
expect(SBSGeometry.packing(width:1920,height:1080,filename:"x.mkv").basis=="block185FrameLayout","no token uses frame layout")
// Mono and unrelated halves stay negative.
var seed:UInt64=12345
func noise()->Data {Data((0..<width*height).map{_ in seed=seed&*6364136223846793005&+1442695040888963407;return UInt8(30+(seed>>33)%200)})}
expect(SBSPairEvidence.classify((0..<8).map{_ in noise()},width:width,height:height).layout==nil,"uncorrelated halves (mono) negative")
