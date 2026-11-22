import Foundation
var failures=0,total=0
func check(_ name:String,_ ok:Bool) {total+=1;if !ok {failures+=1};print("\(name) \(ok ? "PASS":"FAIL")")}
let choice=VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:true,filename:"untagged.mp4",width:3840,height:1920)
check("pair-proven-square-remains-flat",choice.kind=="flat-sbs")
check("plain-square-not-native",VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:false,filename:"untagged.mp4",width:3840,height:1920).kind=="mono")
check("flat-wide-stays-flat",VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:true,filename:"untagged.mp4",width:3840,height:1080).kind=="flat-sbs")
check("explicit-mono-preserved",VRRecognition.choose(remembered:"mono",projection:nil,stereoSBS:true,filename:"untagged.mp4",width:3840,height:1920).kind=="mono")
let evidence=ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))
check("native-auto-output",ThreeDReducer.opening(saved:nil,evidence:evidence).output == .vr180)
var off=FilmThreeD();off.source=ThreeDSource(.vr180SBS);off.output = .off;off.userTouched=true
check("explicit-off-survives-late-probe",ThreeDReducer.opening(saved:off,evidence:evidence).output == .off)
var seed:UInt64=7
var pixels=[UInt8](repeating:0,count:320*90)
for y in 0..<90 {for x in 0..<160 {seed=seed &* 6364136223846793005 &+ 1;pixels[y*320+x]=UInt8((seed >> 32) & 255)}}
for y in 0..<90 {for x in 0..<160 {pixels[y*320+160+x]=pixels[y*320+max(0,x-2)]}}
let frames=Array(repeating:Data(pixels),count:8)
let pair=SBSPairEvidence.classify(frames,width:320,height:90)
check("actual-eight-frame-pair",pair.layout=="side-by-side" && pair.nonzero==8)
var probe=VRProjectionProbe.Result(status:"metadataAbsent");probe.suggestedLayout=pair.layout
let metadata=Data(#"{"streams":[{"width":3840,"height":1920}]}"#.utf8)
VRProjectionProbe.applyGeometry(&probe,frames:frames,metadata:metadata)
check("metadata-free-pair-not-spherical",probe.projection==nil && !probe.circularProfile)
var plain=VRProjectionProbe.Result(status:"metadataAbsent")
VRProjectionProbe.applyGeometry(&plain,frames:[],metadata:metadata)
check("dimensions-alone-not-promoted",plain.projection==nil)
print("total=\(total) green=\(total-failures) red=\(failures)")
if failures>0 {exit(1)}
