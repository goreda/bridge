import Foundation
func expect(_ b:Bool,_ s:String){precondition(b,s);print("PASS "+s)}
let width=320,height=90
func frame(_ layout:String,shift:Int=3,letterbox:Bool=false)->Data {
 var a=[UInt8](repeating:0,count:width*height)
 func value(_ x:Int,_ y:Int,_ eye:Int)->UInt8 {if letterbox && (y<12 || y>=78){return 0};return UInt8(30+((x*37+y*19+(x*y)%67+eye*71)%200))}
 for y in 0..<height {for x in 0..<width {
  let tb=layout=="tb",eye=tb ? y/(height/2):x/(width/2)
  let ex=tb ? x:x%(width/2),ey=tb ? y%(height/2):y
  let sx=ex-(eye==1 ? shift:0)
  a[y*width+x]=value((sx+width)%width,ey,layout=="mono" ? eye:0)
 }}
 return Data(a)
}
for (name,w,h,letter) in [("half-sbs16:9",1920.0,1080.0,false),("full-sbs32:9",3840,1080,false),("half-sbs-letterbox2.39",1920,1080,true)] {
 let frames=(0..<8).map{_ in frame("sbs",letterbox:letter)},v=SBSPairEvidence.classify(frames,width:width,height:height)
 expect(v.layout=="side-by-side" && v.nonzero>=3 && v.median>=0.85,name+" classifier")
 let ar=SBSEyeCrop.eyeAspect(frames,width:width,height:height,codedWidth:w,codedHeight:h,sar:1,full:w/h>=3)!
 expect(ar>1.7 && ar<2.5,name+" measured crop aspect \(ar)")
}
for name in ["mono16:9","mono32:9-panorama"] {let v=SBSPairEvidence.classify((0..<8).map{_ in frame("mono")},width:width,height:height);expect(v.layout==nil,name+" negative")}
expect(SBSPairEvidence.classify((0..<8).map{_ in frame("sbs",shift:0)},width:width,height:height).layout==nil,"duplicate zero-shift negative")
expect(SBSPairEvidence.classify((0..<8).map{_ in Data(repeating:0,count:width*height)},width:width,height:height).layout==nil,"black no NaN/disparity")
expect(SBSPairEvidence.classify((0..<8).map{_ in frame("tb")},width:width,height:height).layout=="top-bottom","top-bottom twin classifier")
let sarAspect=SBSEyeCrop.eyeAspect((0..<8).map{_ in frame("sbs")},width:width,height:height,codedWidth:1440,codedHeight:1080,sar:4/3,full:false)!
expect(abs(sarAspect-16/9)<0.001,"actual measured per-half crop SAR once")
expect(VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:false,filename:"plain.mkv",width:3840,height:1080).kind=="flat-sbs","32to9 full-width shape auto-SBS")
expect(VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:false,filename:"plain.mkv",width:3840,height:1920).kind=="mono","2to1 no metadata/profile is not VR")
var left=IntentionalEyeClosure(),right=IntentionalEyeClosure()
for i in 0..<20 {_=left.feed(t:Double(i)/30,left:0.3,right:nil,reliable:true);_=right.feed(t:Double(i)/30,left:0.3,right:nil,reliable:true)}
for i in 20..<30 {_=left.feed(t:Double(i)/30,left:0.01,right:nil,reliable:true);_=right.feed(t:Double(i)/30,left:0.3,right:nil,reliable:true)}
expect(left.amount==1 && right.amount==0,"per-eye detector left closed right open independently")
expect(left.feed(t:1.1,left:nil,right:nil,reliable:false)==0,"uncertainty commands fail-open target; renderer eases200ms")
func commandTrace(_ kind:String,uncertain:Bool=false,misses:Int=1)->[Int] {
 var d=EyeGestureCommands(),t=0.0,events:[Int]=[]
 func f(_ l:Double,_ r:Double,_ n:Int,_ reliable:Bool=true){for _ in 0..<n{t+=1/30;if let event=d.feed(t:t,left:l,right:r,reliable:reliable){events.append(event)}}}
 f(0.3,0.3,20)
 for cycle in 0..<2 {
  if kind=="left" {f(0.01,0.3,4)}
  else if kind=="right" {f(0.3,0.01,4)}
  else if kind=="asyncBoth" {f(0.01,0.3,1);f(0.01,0.01,3)}
  else {f(0.01,0.01,4)}
  if uncertain && cycle==0 {f(0.3,0.3,misses,false)}
  f(0.3,0.3,4)
 }
 return events
}
// Owner 19:20 layout: Swift owns bilateral double +120 only; bilateral holds do nothing.
expect(commandTrace("left").isEmpty,"left-eye double emits no command")
expect(commandTrace("right").isEmpty,"right-eye double emits no command")
expect(commandTrace("both")==[120],"bilateral double seeks +120 exactly once")
expect(commandTrace("asyncBoth")==[120],"slightly asynchronous bilateral double seeks +120, never a wink command")
// cc45c008 (2026-11-08) EyeGestureCommands.robust holds a series across up to toleratedMisses fresh unreliable frames.
// The older expectation here (any uncertainty cancels) is now measured only beyond that tolerance. Possible policy change, flagged.
expect(commandTrace("both",uncertain:true)==[120],"one unreliable frame between blinks keeps the series (robust policy)")
expect(commandTrace("both",uncertain:true,misses:EyeGestureCommands.toleratedMisses+1).isEmpty,"more than toleratedMisses consecutive unreliable frames cancel the sequence")
var held=EyeGestureCommands(),holdT=0.0,holdEvents:[Int]=[]
func holdFeed(_ l:Double,_ r:Double,_ n:Int,_ reliable:Bool=true){for _ in 0..<n{holdT+=1/30;if let v=held.feed(t:holdT,left:l,right:r,reliable:reliable){holdEvents.append(v)}}}
holdFeed(0.3,0.3,20)
holdFeed(0.01,0.01,59)
expect(holdEvents.isEmpty,"bilateral hold below two seconds emits no Swift command")
holdFeed(0.01,0.01,65)
expect(holdEvents.isEmpty,"long bilateral hold emits no Swift pause toggle; no hold action")
holdFeed(0.3,0.3,6)
expect(holdEvents.isEmpty,"hold release emits no Swift seek or toggle")
holdFeed(0.01,0.01,70);holdFeed(0.3,0.3,6)
expect(holdEvents.isEmpty,"second hold still emits no Swift toggle; no hold action anywhere")
holdFeed(0.01,0.3,90);holdFeed(0.3,0.3,6)
expect(holdEvents.isEmpty,"long unilateral closure emits no command")
holdFeed(0.01,0.01,30);holdFeed(0.01,0.01,1,false);holdFeed(0.01,0.01,35);holdFeed(0.3,0.3,6)
expect(holdEvents.isEmpty,"uncertainty interrupts held closure, no stale Swift command")

for packing in ["half-sbs","full-sbs","flat-tb","vr180"] {
 let p=StereoMenuGeometry.plan(sourceAspect:2.39,aspectOverride:nil,cropAspect:16/9,gap:0)!
 expect(abs(p.scaleX-(16/9)/2.39)<0.00001 && p.scaleY==1,"\(packing) crop cuts eye x, not packed seam")
 expect(abs(p.windowAspect-32/9)<0.00001,"\(packing) window follows cropped eye pair")
 let a=StereoMenuGeometry.plan(sourceAspect:2.39,aspectOverride:4/3,cropAspect:nil,gap:0.02)!
 expect(a.scaleX==1 && a.scaleY==1 && abs(a.eyeAspect-4/3)<0.00001,"\(packing) aspect override changes display, not crop bounds")
 let reset=StereoMenuGeometry.plan(sourceAspect:2.39,aspectOverride:nil,cropAspect:nil,gap:0)!
 expect(reset.scaleX==1 && reset.scaleY==1 && reset.windowAspect==4.78,"\(packing) identity/reset restores source geometry")
}
expect(StereoMenuGeometry.plan(sourceAspect:0,aspectOverride:nil,cropAspect:nil,gap:0)==nil,"invalid geometry never produces a resize")
// Stationary scale hold at the RAW detector boundary, before FOV/Z gain.
var stableScale=StationaryScaleHold()
var seed:UInt64=7
func noise()->Double {
 seed=seed &* 6364136223846793005 &+ 1442695040888963407
 return (Double(seed>>11)/9007199254740992.0-0.5)*0.02
}
var still=[Double]()
for i in 0..<5400 { still.append(stableScale.accept(noise()+0.007*sin(Double(i)/150))) }
expect((still.max()! - still.min()!)<1e-10,"stationary noisy scale does not pump film zoom")
var lean=[Double]()
for _ in 0..<120 {lean.append(stableScale.accept(0.15+noise()))}
expect(lean.max()!>0.12,"coherent forward/back scale remains live")
var rotationalScale=RollInvariantFaceScale()
_ = rotationalScale.z(width:0.2,height:0.3,roll:0)
for i in 0..<900 {
 let yaw=0.6*sin(Double(i)/80),pitch=0.3*cos(Double(i)/60),roll=Double(i)/120
 let c=abs(cos(roll)),s=abs(sin(roll)),cy=abs(cos(yaw)),cp=abs(cos(pitch))
 let w=c*0.2*cy+s*0.3*cp,h=s*0.2*cy+c*0.3*cp
 expect(abs(rotationalScale.z(width:w,height:h,roll:roll,yaw:yaw,pitch:pitch))<1e-10,"ideal rotation changes no scale")
}
