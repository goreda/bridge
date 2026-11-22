import Foundation
// Only external boundaries are fake: Metal encoder, player, kit/thermal/preflight.
// The coordinator, index, prefs, revision, presentation, keys and player JSON are real.
enum DepthCachePaths {static var root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["TEST_CACHE"]!)}
enum RenderPrefs {static let modes=["off","full_sbs","half_sbs","over_under","anaglyph","vr180"]}
enum DZCFile {static func isComplete(_ url:URL)->Bool {FileManager.default.fileExists(atPath:url.path)}}
enum SourceFormatChoice {static var mode="full_sbs";static func output(_ path:String)->String {mode}}
enum TestRoute {case depth}
struct TestRouteValue {let route=TestRoute.depth}
final class StereoSourceGate {static let shared=StereoSourceGate();func route(for url:URL)->TestRouteValue? {TestRouteValue()}}
final class ThreeDPreflight {static let shared=ThreeDPreflight();var reason:String?=nil}
struct ThermalDutyPolicy {enum Step {case suspend,resume,none};mutating func step(rank:Int,now:Double)->Step {.none}}
extension ProcessInfo {enum Thermal {case nominal;var rawValue:Int {0}};var thermalState:Thermal {.nominal}}
final class ThreeDDegrade {
 var state="READY_STEREO";init(exec:@escaping(String)->Void) {}
 func sourceChanged() {};func userMode(on:Bool) {};func thermal(trip:Bool) {};func probe(_ s:String) {};func feed(_ s:String) {};func disk(full:Bool) {};func observe(covered:Bool,now:Double) {};func shotSucceeded(_ s:Int) {};func shotFailed(_ s:Int) {}
}
enum ThreeDKit {static func probeState()->(missing:Bool,verified:Bool,failed:Bool,verifying:Bool) {(false,true,false,false)}}
enum ThreeDDegradeProbe {static func sourceEvent(film:URL)->String? {nil};static func kitEvent(missing:Bool,verified:Bool,verifyFailed:Bool,verifying:Bool)->String? {nil};static func takeDiskFull()->Bool {false};static func headroomOK(at:URL)->Bool {true}}
enum CacheKeyMemo {static func key(path:String)->String? {nil}}
enum SynthMethod:String {case fixture;static let current=(method:SynthMethod.fixture,note:"fixture encoder")}
enum ShotComfortShot {static func compute(depth:URL,ipd:Double)->ShotComfort? {nil}}
enum ThreeDShotPlayLog {static func logOSD(_ s:String) {};static func logShot(shot:Int,pts:Double,menuMode:String,key:String) {};static func shotEnded() {}}
final class ThreeDSubtitleDepth {
 static let shared=ThreeDSubtitleDepth()
 func begin(depth:URL,pts:Double,thetaH:Double,params:()->Int) {_=params()}
 func refreshPrepared(pts:Double) {}
 func end() {}
 static func params(ipdM:Double,effectiveIPD:Double,convergenceM:Double?,comfort:ShotComfort?,comfortIPD:Double?)->Int {0}
}
final class RenderShotWriter {
 static let lock=NSLock();static var starts:[String]=[];static var cancelledCount=0;static var delay=0.08
 init?() {}
 func write(source:URL,depth:URL,depthSize:(w:Int,h:Int)?,sourceSize:(w:Int,h:Int)?,thetaH:Double,plan:RenderedShotPlan,ipd:Double,convergence:Double?,zNear:Double?,surround:Bool,out:URL,cancelled:()->Bool)throws->URL {
  Self.lock.lock();Self.starts.append(out.lastPathComponent);Self.lock.unlock()
  let end=ProcessInfo.processInfo.systemUptime+Self.delay
  while ProcessInfo.processInfo.systemUptime<end {
   if cancelled() {Self.lock.lock();Self.cancelledCount+=1;Self.lock.unlock();throw NSError(domain:"cancelled",code:1)}
   Thread.sleep(forTimeInterval:0.005)
  }
  try Data("stereo ipd=\(ipd) conv=\(convergence ?? 0)".utf8).write(to:out)
  return out
 }
}
