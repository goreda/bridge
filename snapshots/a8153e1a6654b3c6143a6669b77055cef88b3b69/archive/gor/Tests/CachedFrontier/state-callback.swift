import Foundation
// Actual r4 positions callback, with controlled positions supplier and lock scheduler seams.
// Not the full CropDetector or PP lifecycle.
final class GateLock {
 let lockValue=NSLock(), reached=DispatchSemaphore(value:0), release=DispatchSemaphore(value:0)
 var arm=false
 func lock(){if arm && Thread.current.name == "old-worker" {reached.signal();release.wait()};lockValue.lock()}
 func unlock(){lockValue.unlock()}
}
enum WTCropSamples {
 static var supplied: (plan:[Double]?,rawFrontierEnd:Double?)=([1,2,3],24)
 static func positions(path:String,mainIPCPath:String?,manual:Bool,widenLevel:Int)->(plan:[Double]?,rawFrontierEnd:Double?){supplied}
}
final class CropDetector {
 var retryGeneration=1
 let autoPlanLock=GateLock()
 var lastAutoDispatchFrontier:Double?
 var autoDispatchToken=1
 var autoDispatchPath="old-path"
 var mainIPCPath:String?=nil
    static func planProvesCoverage(_ ps: [Double]) -> Bool { ps.allSatisfy { $0.isFinite && $0 >= 0 } && Set(ps).count >= 3 }   // aligned with scanner admission: every position finite and non-negative, not merely 3 finite ones among rejects
 func callback(manualPriority:Bool=false)->()->[Double]? {
 let filePath="old-path",widenLevel=0,token=retryGeneration
 return { [weak self] in let r = WTCropSamples.positions(path:filePath,mainIPCPath:self?.mainIPCPath,manual:manualPriority,widenLevel:widenLevel); if !manualPriority, let fe = r.rawFrontierEnd, let ps = r.plan, CropDetector.planProvesCoverage(ps), let self = self { self.autoPlanLock.lock(); if self.autoDispatchToken == token, self.autoDispatchPath == filePath { self.lastAutoDispatchFrontier = fe }; self.autoPlanLock.unlock() }; return r.plan }
 }
 func newDispatch(){retryGeneration += 1;autoPlanLock.lock();lastAutoDispatchFrontier=nil;autoDispatchToken=retryGeneration;autoDispatchPath="new-path";autoPlanLock.unlock()}
 func invalidate(){autoPlanLock.lock();lastAutoDispatchFrontier=nil;autoDispatchToken = -1;autoDispatchPath="";autoPlanLock.unlock()}
}
let f=CropDetector();let old=f.callback();f.autoPlanLock.arm=true
let done=DispatchSemaphore(value:0)
DispatchQueue.global().async {Thread.current.name="old-worker";_=old();done.signal()}
precondition(f.autoPlanLock.reached.wait(timeout:.now()+2) == .success)
f.newDispatch();precondition(f.lastAutoDispatchFrontier == nil)
f.autoPlanLock.release.signal();precondition(done.wait(timeout:.now()+2) == .success)
print("old token frontier after new dispatch = \(f.lastAutoDispatchFrontier as Any)")
if f.lastAutoDispatchFrontier != nil {print("FAIL old-token callback wrote stale frontier");exit(1)}
for plan:[Double]? in [nil,[],[1,1,1],[Double.nan,1,2],[1,2,3,Double.nan],[-1,2,3]] {
 let g=CropDetector();WTCropSamples.supplied=(plan,24);_=g.callback()();precondition(g.lastAutoDispatchFrontier == nil)
}
let g=CropDetector();WTCropSamples.supplied=([1,2,3],24);_=g.callback()();precondition(g.lastAutoDispatchFrontier == 24)
let manual=CropDetector();_=manual.callback(manualPriority:true)();precondition(manual.lastAutoDispatchFrontier == nil)
let cancelled=CropDetector();let cb=cancelled.callback();cancelled.invalidate();_=cb();precondition(cancelled.lastAutoDispatchFrontier == nil)
print("PASS actual callback interleaving rejects old token; nil/empty/degenerate/manual/cancelled write nothing; valid current plan writes24")
