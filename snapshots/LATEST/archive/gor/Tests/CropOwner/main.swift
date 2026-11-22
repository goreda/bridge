import Foundation
func require(_ b: @autoclosure () -> Bool, _ s: String) { if !b() {fatalError(s)} }
func commands(_ a:[GorCropMPV.Action])->[String] {a.compactMap {if case .send(let s)=$0{return s};return nil}}
var s=GorCropMPV()
let req=GorCropRequest(fx:0.125,fy:0.125,fw:0.75,fh:0.75)
_ = s.request(req)
let probe=s.awaitedId!
let add=s.reply(id:probe,ok:true,data:["w":640,"h":480,"dw":640,"dh":480,"rotate":0])
require(commands(add).first!.contains("@gorcrop:crop="),"owned add")
let aid=s.awaitedId!
require(s.clear().isEmpty,"clear queues during add")
_ = s.reply(id:aid,ok:true,data:nil)
let f=GorCropFilter(w:480,h:360,x:80,y:60)
_ = s.reply(id:s.awaitedId!,ok:true,data:[["label":"gorcrop","name":"crop","params":["w":"480","h":"360","x":"80","y":"60"]]])
let done=s.reply(id:s.awaitedId!,ok:true,data:["w":f.w,"h":f.h])
require(commands(done).contains(where:{$0.contains("\"remove\",\"@gorcrop\"")}),"late add then clear removes only owned label")
_ = s.reply(id:s.awaitedId!,ok:true,data:nil)
require(s.awaitedId==nil && s.activeFilter==nil,"settled")
require(s.clear().isEmpty,"idle clear idempotent")
require(!commands(add+done).contains(where:{$0.contains("\"clr\"") || $0.contains("\"set\"")}),"no chain replacement")
print("PASS actual GorCropMPV: clear during add, late readback, labelled removal, idle reset")

let wide = GorCropPlan.centeredManualRequest(aspectW:4,aspectH:3,displayW:1920,displayH:1080)!
require(abs(wide.fx-0.125)<0.000001 && wide.fy==0 && abs(wide.fw-0.75)<0.000001 && wide.fh==1,"centered pillar crop")
let tall = GorCropPlan.centeredManualRequest(aspectW:16,aspectH:9,displayW:1440,displayH:1080)!
require(tall.fx==0 && abs(tall.fy-0.125)<0.000001 && tall.fw==1 && abs(tall.fh-0.75)<0.000001,"centered letter crop")
require(GorCropPlan.centeredManualRequest(aspectW:Double.nan,aspectH:1,displayW:1,displayH:1)==nil,"reject nan")
require(GorCropPlan.centeredManualRequest(aspectW:1,aspectH:0,displayW:1,displayH:1)==nil,"reject zero")
require(GorCropPlan.codedSizeIfEligible(videoParams:["w":720,"h":576,"dw":1024,"dh":576])==nil,"anamorphic refusal")
require(GorCropPlan.codedSizeIfEligible(videoParams:["w":640,"h":480,"dw":640,"dh":480,"rotate":90])==nil,"rotated refusal")
require(GorCropPlan.codedSizeIfEligible(videoParams:["w":640,"h":480,"dw":640,"dh":480,"rotate":0]) != nil,"square unrotated eligible")
print("PASS manual intent centered geometry + invalid/anamorphic/rotation eligibility refusal")
