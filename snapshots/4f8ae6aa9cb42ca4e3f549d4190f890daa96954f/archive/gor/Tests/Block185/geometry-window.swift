import Foundation
func check(_ v:Bool,_ label:String){precondition(v,label);print("PASS "+label)}
for mode in ["half-sbs","full-sbs","flat-tb","vr180"] {
 for target in [1.0,4.0/3,16.0/9,2.39] {
  let p=StereoMenuGeometry.plan(sourceAspect:2.39,aspectOverride:nil,cropAspect:target,gap:0.02)!
  let f=GorCropPlan.refitFrame(frame:GorFitRect(x:200,y:120,w:900,h:600),aspect:p.windowAspect,chromeW:0,chromeH:28,avail:GorFitRect(x:0,y:0,w:1440,h:900))!
  check(abs(f.w/(f.h-28)-p.windowAspect)<0.02,"\(mode) menu\(target) production window frame follows eye pair")
  check(f.x>=0 && f.y>=0 && f.x+f.w<=1440 && f.y+f.h<=900,"\(mode) screen clamp")
 }
}
