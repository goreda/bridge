import Foundation

/// Mirrors photon-common.lua push_params numeric formatting and five-decimal
/// deduplication. Feed it raw owner Double values. Do not upload the owner's
/// raw parameters directly: the mpv path actually receives six-decimal text.
public struct PhotonParameterPublisher:Sendable {
 public enum Error:Swift.Error {case invalid(String)}
 private var lastComparison:String?
 private var lastUploaded:[String:Double]=[:]
 public init(){}
 public var current:[String:Double]{lastUploaded}
 private static let integers:Set<String>=["PHOTON_SHARP_ALGO","PHOTON_SHARP_CONTENT_ADAPT","PHOTON_SHARP_MEDIUM_BAND_ACTIVE","PHOTON_SHARP_COARSE_BAND_ACTIVE","STOCK_PRESET","RES_ADAPT","GR_MONO_MODE","GRAIN_DEBUG_VISUALIZE"]
 private func formatted(_ value:Double,_ digits:Int)->String{
  String(format:"%.*f",digits,value)
 }
 /// nil means no new full-map upload, exactly like common.push_params false.
 /// Keep a separate instance for each family's active prefix/temporal mode.
 public mutating func publish(_ raw:[String:Double],force:Bool=false)throws->[String:Double]?{
  var parts:[String]=[],uploaded:[String:Double]=[:]
  for name in raw.keys.sorted(){
   let v=raw[name]!
   guard v.isFinite else{throw Error.invalid(name)}
   if Self.integers.contains(name){
    guard v.rounded(.towardZero)==v else{throw Error.invalid(name)}
    let str=formatted(v,0);parts.append(name+"="+str);uploaded[name]=Double(str)!
   }else{parts.append(name+"="+formatted(v,5));uploaded[name]=Double(formatted(v,6))!}
  }
  let comparison=parts.joined(separator:",")
  guard force || comparison != lastComparison else{return nil}
  lastComparison=comparison;lastUploaded=uploaded;return uploaded
 }
 /// The grain source-frame bucket uses its separate actual bucket-only path,
 /// not the five-decimal full-map cache. It leaves that cache unchanged.
 public mutating func grainBucket(_ value:Double)throws->Double{
  guard value.isFinite else{throw Error.invalid("GR_ANIM_BUCKET")}
  let v=Double(formatted(value,6))!;lastUploaded["GR_ANIM_BUCKET"]=v;return v
 }
}
