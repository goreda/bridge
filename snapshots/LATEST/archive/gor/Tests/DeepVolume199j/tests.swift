import Foundation
var failures=0,checks=0
func check(_ value:Bool,_ name:String){checks+=1;if !value {failures+=1;print("FAIL "+name)}}
let deep=ThreeDExperimentOptions(deepVolume:true)
func rawSpan(_ p5:Double,_ p95:Double,_ zc:Double,_ ipd:Double)->Double {
 ShotComfort.dispDeg(z:p5,zc:zc,ipd:ipd)-ShotComfort.dispDeg(z:p95,zc:zc,ipd:ipd)
}
func params(_ prefs:RenderPrefsValue,_ raw:ShotComfort?)->ThreeDSubtitleDepth.RenderParams {
 let c=prefs.deepComfort(raw)
 return ThreeDSubtitleDepth.RenderParams(ipd:c.map{prefs.comfortIPD($0)} ?? prefs.effectiveIPD,convergence:c?.convergenceM ?? prefs.convergenceM,zNear:c.map{prefs.comfortZNear($0)})
}
let named:[(Double,Double,Double,Bool)]=[(0.5,2,20,true),(0.3,0.5,2,true),(9,10,11,false)]
for (lo,median,hi,fallback) in named {
 var p=RenderPrefsValue();p.convergenceM=1.5
 let c=ShotDeepGeometry.make(p5:lo,p50:median,p95:hi,ipd:p.ipdM,screenDepth:p.convergenceM,strength:p.depthScale,overBudget:p.overBudget,options:deep)!.comfort
 check(c.todayFallback==fallback,"named mode \(lo)/\(median)/\(hi)")
 check(c.measurement!.mode==(fallback ? "today":"deep"),"named receipt mode")
 if fallback {check(params(p,c)==params(p,nil),"fallback exact cf-nil params")}
 else {check(c.measurement!.seenSpanDeepDeg>=c.measurement!.spanTodayDeg,"deep displayed guard")}
 print(c.measurement!.line(shot:0,model:"dav2",dofOverridden:true))
}
let fixtures:[(Double,Double,Double)]=[(0.25,0.25,0.25),(0.25,0.3,0.5),(0.3,0.5,2),(0.5,2,20),(1,1.5,3),(4,5,100),(9,10,11),(1,20,255),(0.25,20,255)]
var deepCount=0,todayCount=0
for (lo,median,hi) in fixtures {for dial in [1.0,1.5,2.5] {for strength in [0.5,1.0,1.5] {
 var p=RenderPrefsValue();p.convergenceM=dial;p.depthScale=strength
 let g=ShotDeepGeometry.make(p5:lo,p50:median,p95:hi,ipd:p.ipdM,screenDepth:dial,strength:strength,overBudget:false,options:deep)!
 let c=g.comfort,m=c.measurement!,chosen=params(p,c),today=params(p,nil)
 let expectedToday=rawSpan(lo,hi,dial,p.effectiveIPD)
 check(m.spanTodayDeg==expectedToday,"today convergence dial exact equation")
 check(c.convergenceM==median*(dial/1.5),"deep convergence dial")
 check(m.spanDeepDeg==rawSpan(lo,hi,c.convergenceM,p.comfortIPD(c)),"raw span chosen budget gain")
 let seenLo=max(lo,chosen.zNear ?? lo),seenHi=max(hi,chosen.zNear ?? hi)
 let displayed=rawSpan(seenLo,seenHi,chosen.convergence ?? 1.5,chosen.ipd)
 check(displayed+1e-12>=expectedToday,"chosen displayed never shallower")
 let budget=ShotComfortSpan.make(zNear:lo,zFar:hi,zc:c.convergenceM,ipd:p.ipdM,nearBudgetDeg:3,farBudgetDeg:2,maxGain:6)!
 check(c.depthScale==budget.gain,"no gain override")
 if c.todayFallback {todayCount+=1;check(chosen==today,"today exact render params")}
 else {
  deepCount+=1
  check(ShotComfort.dispDeg(z:lo,zc:c.convergenceM,ipd:chosen.ipd)<=3+1e-10,"deep crossed budget")
  check(ShotComfort.dispDeg(z:hi,zc:c.convergenceM,ipd:chosen.ipd)>=(-2-1e-10),"deep uncrossed budget")
 }
 var subtitleCF=p.deepComfort(c);if subtitleCF != nil {subtitleCF!.zNear=p.comfortZNear(subtitleCF!)}
 let subtitle=ThreeDSubtitleDepth.params(ipdM:p.ipdM,effectiveIPD:p.effectiveIPD,convergenceM:p.convergenceM,comfort:subtitleCF,comfortIPD:subtitleCF.map{p.comfortIPD($0)})
 check(subtitle==chosen,"subtitle render exact all parameters")
 check(m.line(shot:1,model:"vda",dofOverridden:false).contains("seenTodayDeg=\(expectedToday)"),"receipt today equation")
}}}
check(deepCount>0 && todayCount>0,"grid exercises both modes")
check(deep.renderKeyComponent=="exp-deep2","retire deep cache token")
check(deep.prepareComponent=="","render-only no prepare invalidation")
var p=RenderPrefsValue();check(p.deepComfort(nil)==nil,"nil helper")
for enabled in [false,true] {for comfort in [false,true] {for explicit in [false,true] {p.comfort=comfort;p.convergenceM=explicit ? 1.5:nil;check(p.comfortActive(ThreeDExperimentOptions(deepVolume:enabled))==(comfort && (!explicit || enabled)),"comfort truth")}}}
DZCFile.planes=[[1023,512,128,0]]
let measured=ShotComfortShot.compute(depth:URL(fileURLWithPath:"/fixture"),options:deep,screenDepth:1.5)!
check(measured.measurement!.sat1023Frac==0.25 && measured.measurement!.zeroFrac==0.25,"streamed measurement preserved")
check(measured.measurement!.mode==(measured.todayFallback ? "today":"deep"),"compute keeps fallback measurement")
print("GRID deep=\(deepCount) today=\(todayCount)")
print("SUMMARY \(checks) checks \(failures) failures; Linux pure, native NOT_RUN")
exit(failures==0 ? 0:1)
