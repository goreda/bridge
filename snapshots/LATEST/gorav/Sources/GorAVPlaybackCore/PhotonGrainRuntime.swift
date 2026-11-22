import Foundation

public enum PhotonGrainRuntimeError:Error { case invalidValue, invalidTime, unsupportedCommand(String) }
/// Current photon-grain.lua consumer. Does not invent the producer's GS probe.
public struct PhotonGrainRuntime:Sendable {
 public private(set) var enabled=false,targetEnabled=true,adaptive=true
 public var clock=PhotonGrainClock()
 public private(set) var revision=0,seekEpoch=0
 public private(set) var weightShift=0.0
 public var documentIdentity:(generation:Double,name:String){(documentGeneration,documentName)}
 public var measurementMirror:MeasurementMirror {
  MeasurementMirror(enabled:enabled,amount:p["GR_AMOUNT"]!,gpuAmount:cl(p["GR_AMOUNT"]!,0,10),
   strength:p["BASE_STRENGTH"]!,factoryStrength:6,size:p["GRAIN_SIZE"]!,softness:p["GRAIN_SOFTNESS"]!,
   development:p["DEVELOPMENT"]!,weightShift:weightShift,userOffset:amount-baseAmount(),
   sizeCoefficient:p["GR_SIZE_COEFFICIENT"]!,renderDensity:p["GR_RENDER_DENSITY"]!,
   adaptive:adaptive,revision:revision,seekEpoch:seekEpoch,documentGeneration:documentGeneration)
 }
 public struct MeasurementMirror:Sendable {
  public let enabled:Bool
  public let amount:Double,gpuAmount:Double,strength:Double,factoryStrength:Double,size:Double,softness:Double,development:Double,weightShift:Double,userOffset:Double,sizeCoefficient:Double,renderDensity:Double
  public let adaptive:Bool
  public let revision:Int,seekEpoch:Int
  public let documentGeneration:Double
 }
 private let learningSession=UUID().uuidString
 private var learningSequence=0
 public struct ManualEvent:Sendable {
  public let parameter:String,eventID:String
  public let value:Double
  public let adaptive:Bool,documentGeneration:Double,documentName:String
 }
 private var manualEvents:[ManualEvent]=[]
 public mutating func drainManualEvents()->[ManualEvent]{let result=manualEvents;manualEvents.removeAll(keepingCapacity:true);return result}
 private mutating func manualEvent(_ parameter:String,_ value:Double){
  guard value.isFinite,value>0 else{return};learningSequence+=1
  let wire=Double(String(format:"%.9g",value))!
  manualEvents.append(ManualEvent(parameter:parameter,eventID:learningSession+"-"+String(learningSequence),value:wire,adaptive:adaptive,documentGeneration:documentGeneration,documentName:documentName))
 }
 private var p:[String:Double] = ["GR_FRAME_PEAK":0.5,"GR_SCENE_CONTRAST":0.35,"GR_NOISE_LEVEL":0.1,"GR_MOTION_LEVEL":0.2,"GR_AMOUNT":1,"GR_IS_HDR":0,"GR_SCENE_HUE":0,"GR_HUE_MOD_STRENGTH":0,"GR_SIZE_COEFFICIENT":0,"GR_RENDER_DENSITY":0,"GRAIN_SIZE":0.8,"GRAIN_SOFTNESS":50,"CHROMA_SPLIT":1,"DEVELOPMENT":0.4,"FINE_WEIGHT":0.25,"CRYSTAL_WEIGHT":0.4,"CLOUD_WEIGHT":0.45,"BASE_STRENGTH":6,"FINE_SIZE_RATIO":0.5,"CLOUD_SIZE_RATIO":2.2,"SKEW_STRENGTH":0,"GR_SHADOW_SENSITIVITY":1.8,"GR_MIDTONE_SENSITIVITY":1.5,"GR_HIGHLIGHT_SENSITIVITY":2.7,"STOCK_PRESET":5,"RES_ADAPT":1,"GR_MONO_MODE":0,"GRAIN_DEBUG_VISUALIZE":0]
 private var bases:[String:Double]=["GRAIN_SIZE":0.8,"GRAIN_SOFTNESS":50,"CHROMA_SPLIT":1,"DEVELOPMENT":0.4,"FINE_WEIGHT":0.25,"CRYSTAL_WEIGHT":0.4,"CLOUD_WEIGHT":0.45]
 private struct Character:Sendable {
  var signal:Double,committed:Double,rendered:Double,dwell:Double?
  init(_ v:Double){signal=v;committed=v;rendered=v}
  mutating func track(_ raw:Double,_ now:Double,_ dt:Double,_ cut:Bool)->Double {
   signal += (1-exp(-dt/9))*(raw-signal)
   if abs(signal-committed)<=0.12 && !cut {dwell=nil} else {if dwell==nil{dwell=now};if cut || now-dwell!>=2.5 {committed=signal;dwell=nil}}
   rendered += (1-exp(-dt/(cut ? 0.8:3)))*(committed-rendered);return rendered
  }
 }
 private var chars=[Character(0.5),Character(0.1),Character(0.2),Character(0.35),Character(0.5)]
 private var amountTime=0.0,charTime=0.0,ratio=1.0,learnedAmount=1.0,amount=1.0
 private var manualAmount=false,manualSize=false,manualStrength=false,hueKnown=false
 private var sizeTrim=1.0,sizeHint:Double?
 private var savedStock:Double?,savedSoftness:Double?
 private var documentGeneration=0.0,documentName="-",multApplied=false,measuredSinceSeek=false
 private var blend:(from:Double,target:Double,start:Double)?
 private var sourceH:Double?,sourceW:Double?,outputW:Double?
 public let floor480:Double,ceiling480:Double
 public init(floor480:Double=0.25,ceiling480:Double=8) {
  self.floor480=floor480.isFinite && floor480>0 ? floor480:0.25
  self.ceiling480=ceiling480.isFinite && ceiling480>=self.floor480 ? ceiling480:8
 }
 private func cl(_ x:Double,_ a:Double,_ b:Double)->Double{max(a,min(b,x))}
 private var floorSize:Double { (sourceH ?? 1080)<=480 ? floor480:0.15 }
 private func ceiling(_ escape:Bool)->Double { ((sourceH ?? 1080)<=480 ? ceiling480:8)*(escape ? 2:1) }
 public mutating func setRaster(sourceWidth:Double?,sourceHeight:Double?,outputPictureWidth:Double?)throws {
  for v in [sourceWidth,sourceHeight,outputPictureWidth].compactMap({$0}) {guard v.isFinite,v>0 else{throw PhotonGrainRuntimeError.invalidValue}}
  sourceW=sourceWidth;sourceH=sourceHeight;outputW=outputPictureWidth;refreshAdaptive()
 }
 public mutating func setAdaptive(_ enabled:Bool){adaptive=enabled;refreshAdaptive()}
 private mutating func refreshAdaptive(){
  p["GR_SIZE_COEFFICIENT"]=0;p["GR_RENDER_DENSITY"]=0
  guard adaptive,let sw=sourceW,let sh=sourceH,let ow=outputW else{return}
  let r=ow/sw,h=max(sh,sw*9/16)
  p["GR_SIZE_COEFFICIENT"]=0.8*cl(r,0.75,2.5)
  var k=1.0
  if h<1080 {if h<=480{k=0.70}else{let lo=h<=720 ? 480.0:720,hi=h<=720 ? 720.0:1080,lv=h<=720 ? 0.70:0.93,hv=h<=720 ? 0.93:1.0;k=cl(floor((lv+log(h/lo)/log(hi/lo)*(hv-lv))*100+0.5)/100,0.70,1)}}
  k *= r>1 ? max(0.80,pow(r,-0.25)):1
  p["GR_RENDER_DENSITY"]=cl(k,0.55,1)
 }
 private func baseAmount()->Double {(0.55+0.45*(1-p["GR_FRAME_PEAK"]!))*(1-0.35*cl(p["GR_NOISE_LEVEL"]!,0,1))*(1-0.15*cl(p["GR_MOTION_LEVEL"]!,0,1))*learnedAmount}
 private mutating func resolve(_ now:Double,cut:Bool=false){
  amount=cl(baseAmount()*ratio,0,10)
  let dt=min(now-(amountTime>0 ? amountTime:now-0.1),12);amountTime=now
  p["GR_AMOUNT"]! += (1-exp(-dt/(cut ? 0.3:7.5)))*(amount-p["GR_AMOUNT"]!)
  tickBlend(now)
  let cdt=min(now-(charTime>0 ? charTime:now-0.1),12);charTime=now
  let inputs=[cl(1-p["GR_FRAME_PEAK"]!,0,1),cl(p["GR_NOISE_LEVEL"]!,0,1),cl(p["GR_MOTION_LEVEL"]!,0,1),cl(p["GR_SCENE_CONTRAST"]!,0,1),cl(1-p["GR_FRAME_PEAK"]!,0,1)]
  var v:[Double]=[];for i in 0..<5 {v.append(chars[i].track(inputs[i],now,cdt,cut))}
  p["GRAIN_SIZE"]=cl(bases["GRAIN_SIZE"]!*(0.925+0.15*v[0]),floorSize,ceiling(manualSize || sizeTrim>2))
  let soft=bases["GRAIN_SOFTNESS"]!;p["GRAIN_SOFTNESS"]=soft>=1 ? cl(1-0.30*v[1],0.7,1):cl(soft*(1-0.25*v[1])*(1+0.1*v[0]),0.05,1)
  p["CHROMA_SPLIT"]=cl(bases["CHROMA_SPLIT"]!*(1-0.5*v[2]),0,0.55)
  p["DEVELOPMENT"]=cl(bases["DEVELOPMENT"]!*(0.80+0.45*v[3]),0.1,1.5)
  let shift=0.30*(v[4]-0.5)*2;weightShift=shift
  let fine=cl(bases["FINE_WEIGHT"]!-shift*0.5,0.05,1),crystal=cl(bases["CRYSTAL_WEIGHT"]!,0.05,1),cloud=cl(bases["CLOUD_WEIGHT"]!+shift*0.5,0.05,1)
  let total=bases["FINE_WEIGHT"]!+bases["CRYSTAL_WEIGHT"]!+bases["CLOUD_WEIGHT"]!,sum=fine+crystal+cloud,renorm=sum>0.0001 ? total/sum:1
  p["FINE_WEIGHT"]=fine*renorm;p["CRYSTAL_WEIGHT"]=crystal*renorm;p["CLOUD_WEIGHT"]=cloud*renorm
 }
 public mutating func fileLoaded(now:Double)throws{
  guard now.isFinite,now>=0 else{throw PhotonGrainRuntimeError.invalidTime}
  clock.fileLoaded();p["GR_SCENE_HUE"]=0;p["GR_HUE_MOD_STRENGTH"]=0;hueKnown=false
  ratio=1;learnedAmount=1;manualAmount=false;manualSize=false;sizeHint=nil
  bases["GRAIN_SIZE"]=cl(0.8*sizeTrim,floorSize,ceiling(sizeTrim>2));p["GRAIN_SIZE"]=bases["GRAIN_SIZE"]
  manualStrength=false;p["BASE_STRENGTH"]=6;multApplied=false;blend=nil;seekEpoch=0;measuredSinceSeek=false
  p["GR_FRAME_PEAK"]=0.5;p["GR_SCENE_CONTRAST"]=0.35;p["GR_NOISE_LEVEL"]=0.1;p["GR_MOTION_LEVEL"]=0.2
  resolve(now);p["GR_AMOUNT"]=amount;chars=[Character(0.5),Character(0.1),Character(0.2),Character(0.35),Character(0.5)]
  enabled=targetEnabled;refreshAdaptive()
 }
 public mutating func setTarget(_ value:Bool){targetEnabled=value;enabled=value}
 public mutating func sceneFeed(_ f:PhotonSceneFeed,now:Double,position:Double?,estimatedFrameNumber:Double?,cachePaused:Bool)throws{
  guard now.isFinite,now>=0 else{throw PhotonGrainRuntimeError.invalidTime}
  for (key,v) in [("GR_FRAME_PEAK",f.smoothPeak),("GR_SCENE_CONTRAST",f.smoothContrast),("GR_NOISE_LEVEL",f.smoothNoise),("GR_MOTION_LEVEL",f.motion)] {if v.isFinite,v>=0,v<=1{p[key]=v}}
  clock.sceneFeed(fps:f.fps,isCut:f.isCut,position:position,frame:estimatedFrameNumber,cachePaused:cachePaused)
  p["GR_IS_HDR"]=f.isHDR ? 1:0
  if let h=f.hue,h.isFinite,h>=0,h<=1 {
   let raw=h*360
   if hueKnown {var d=h-p["GR_SCENE_HUE"]!/360;if d>0.5{d-=1};if d < -0.5{d+=1};let x=p["GR_SCENE_HUE"]!/360+0.08*d;p["GR_SCENE_HUE"]=(x-floor(x))*360}
   else{p["GR_SCENE_HUE"]=raw};hueKnown=true;p["GR_HUE_MOD_STRENGTH"]=0.12
  }
  resolve(now,cut:f.isCut)
 }
 private mutating func acceptDoc(_ gen:Double?,_ name:String?)->Bool{
  guard let gen else{return true};if gen<documentGeneration{return false};if gen>documentGeneration{documentGeneration=gen;documentName=name ?? "-";multApplied=false};return true
 }
 public mutating func tickBlend(_ now:Double){guard let b=blend else{return};let x=cl((now-b.start)/2,0,1),e=x*x*(3-2*x);p["BASE_STRENGTH"]=x>=1 ? b.target:b.from+(b.target-b.from)*e;if x>=1{blend=nil}}
 public mutating func seek(){seekEpoch+=1;measuredSinceSeek=false;if manualStrength{blend=nil;return};if multApplied{return};blend=nil;p["BASE_STRENGTH"]=6}
 public var parameters:[String:Double]{var result=p;result["GR_ANIM_BUCKET"]=clock.bucket;return result}
 /// Returns false for unknown messages. Extra args preserve the actual doc /
 /// revision / epoch gates of asynchronous GS strength callbacks.
 @discardableResult public mutating func command(_ name:String,value:Double?=nil,now:Double,
  document:Double?=nil,filename:String?=nil,epoch:Int?=nil,measured:Bool=false,expectedRevision:Int?=nil)throws->Bool {
  guard now.isFinite,now>=0 else{throw PhotonGrainRuntimeError.invalidTime}
  if let value,!value.isFinite{throw PhotonGrainRuntimeError.invalidValue}
  let traced=["photon-grain-set-amount","photon-grain-set-strength","photon-grain-set-size"]
  if traced.contains(name){revision+=1}
  switch name {
  case "photon-grain-toggle":revision+=1;targetEnabled.toggle();enabled=targetEnabled
  case "photon-grain-doc":_ = acceptDoc(document,filename)
  case "photon-grain-learned-amount":
   guard document==documentGeneration,filename==documentName,!manualAmount,let value,value>0,value<=64 else{return true}
   learnedAmount=value;resolve(now)
  case "photon-grain-strength-resume":if adaptive && acceptDoc(document,filename){manualStrength=false}
  case "photon-grain-set-strength-hint":
   guard let value,acceptDoc(document,filename),!multApplied,!manualStrength else{return true}
   p["BASE_STRENGTH"]=6*cl(1+0.25*cl(value,0,1),1,1.25)
  case "photon-grain-set-strength-mult","photon-grain-proxy-strength":
   guard var v=value,acceptDoc(document,filename),expectedRevision==nil || expectedRevision==revision else{return true}
   let proxy=name=="photon-grain-proxy-strength"
   guard !proxy || epoch==seekEpoch,!manualStrength else{return true}
   if adaptive || proxy {guard v>=0,v<=8 else{return true}}else{v=cl(v,0.40,1.25)}
   if measured || proxy {blend=(p["BASE_STRENGTH"]!,6*v,now);measuredSinceSeek=true}
   else if v==1 && measuredSinceSeek{return true}
   else{blend=nil;p["BASE_STRENGTH"]=6*v}
   multApplied=true
  case "photon-grain-set-amount":
   guard let value else{return true};let base=baseAmount(),current=cl(base*ratio,0,10)
   var target=abs(value-1)<0.001 ? (current>0 ? 0:base):cl(current+(value>1 ? 0.025:-0.025),0,10)
   if target<1e-9{target=0};ratio=base>0 ? target/base:1;resolve(now);p["GR_AMOUNT"]=amount;manualAmount=true;manualEvent("amount",base>0 ? p["GR_AMOUNT"]!*learnedAmount/base:0)
  case "photon-grain-set-strength":guard let value else{return true};p["BASE_STRENGTH"]=cl(value,0,60);blend=nil;manualStrength=true;manualEvent("strength",p["BASE_STRENGTH"]!/6)
  case "photon-grain-set-size":guard let value else{return true};bases["GRAIN_SIZE"]=cl(value,min(0.5,floorSize),max(16,ceiling(true)));p["GRAIN_SIZE"]=bases["GRAIN_SIZE"];manualSize=true;manualEvent("size",bases["GRAIN_SIZE"]!/0.8)
  case "photon-grain-set-size-hint":guard let value,!manualSize else{return true};sizeHint=value;bases["GRAIN_SIZE"]=cl(0.8*value*sizeTrim,floorSize,ceiling(sizeTrim>2));p["GRAIN_SIZE"]=bases["GRAIN_SIZE"]
  case "photon-grain-size-trim-up","photon-grain-size-trim-down","photon-grain-size-trim-reset":
   let next=cl(name.hasSuffix("up") ? sizeTrim*1.12:(name.hasSuffix("down") ? sizeTrim/1.12:1),0.25,4)
   if next==sizeTrim{return true};revision+=1;sizeTrim=next
   if !manualSize{bases["GRAIN_SIZE"]=cl(0.8*(sizeHint ?? 1)*sizeTrim,floorSize,ceiling(sizeTrim>2));p["GRAIN_SIZE"]=bases["GRAIN_SIZE"];manualEvent("size",bases["GRAIN_SIZE"]!/0.8)}
  case "photon-grain-set-stock":guard let value else{return true};p["STOCK_PRESET"]=floor(cl(value,0,5))
  case "photon-grain-set-res-adapt":guard let value else{return true};p["RES_ADAPT"]=value != 0 ? 1:0
  case "photon-grain-debug-visualize":guard let value else{return true};p["GRAIN_DEBUG_VISUALIZE"]=value != 0 ? 1:0
  default:
   let knobs:[String:(String,Double,Double,Bool)]=[
    "photon-grain-set-shadow-sensitivity":("GR_SHADOW_SENSITIVITY",0,2,false),
    "photon-grain-set-midtone-sensitivity":("GR_MIDTONE_SENSITIVITY",0,2,false),
    "photon-grain-set-highlight-sensitivity":("GR_HIGHLIGHT_SENSITIVITY",0,2,false),
    "photon-grain-set-chroma-split":("CHROMA_SPLIT",0,0.5,true),
    "photon-grain-set-development":("DEVELOPMENT",0.1,1.5,true),
    "photon-grain-set-skew":("SKEW_STRENGTH",0,0.7,false),
    "photon-grain-set-dye-halo":("GRAIN_SOFTNESS",0.20,30.75,true),
    "photon-grain-set-softness":("GRAIN_SOFTNESS",0.20,30.75,true),
    "photon-grain-set-fine":("FINE_WEIGHT",0,1,true),
    "photon-grain-set-mid":("CRYSTAL_WEIGHT",0,1,true),
    "photon-grain-set-coarse":("CLOUD_WEIGHT",0,1,true),
    "photon-grain-set-cloud-size-ratio":("CLOUD_SIZE_RATIO",1.4,4,false),
    "photon-grain-set-fine-size-ratio":("FINE_SIZE_RATIO",0.15,0.90,false)]
   guard let (key,lo,hi,isBase)=knobs[name] else{return false}
   if let value{p[key]=cl(value,lo,hi);if isBase{bases[key]=p[key]}}
  }
  return true
 }
 public mutating func setMono(_ value:Bool){
  guard value != (p["GR_MONO_MODE"]==1) else{return};p["GR_MONO_MODE"]=value ? 1:0
  if value {savedStock=p["STOCK_PRESET"];savedSoftness=bases["GRAIN_SOFTNESS"];p["STOCK_PRESET"]=4;bases["GRAIN_SOFTNESS"]=cl(bases["GRAIN_SOFTNESS"]!*0.5,0.20,30.75);p["GRAIN_SOFTNESS"]=bases["GRAIN_SOFTNESS"]}
  else{if let savedStock{p["STOCK_PRESET"]=savedStock};if let savedSoftness{bases["GRAIN_SOFTNESS"]=savedSoftness;p["GRAIN_SOFTNESS"]=savedSoftness};savedStock=nil;savedSoftness=nil}
 }
}
