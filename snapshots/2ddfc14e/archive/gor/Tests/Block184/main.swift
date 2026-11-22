import Foundation
func pass(_ s:String) { print("PASS "+s) }
// PCA rotation invariance, no landmark indices.
let open=(0..<12).map { i -> (Double,Double) in let a=Double(i)*Double.pi/6;return (cos(a),0.3*sin(a)) }
let cs:Double=cos(0.7), sn:Double=sin(0.7)
let rotated:[(Double,Double)]=open.map { pt in let x=pt.0,y=pt.1;return (x*cs-y*sn,x*sn+y*cs) }
precondition(abs(EyeAperture.ear(open)!-EyeAperture.ear(rotated)!)<1e-9);pass("184-5 index-free EAR rotation")
var det=BlinkControlDetector(),t=0.0
func feed(_ closed:Bool,_ count:Int) -> [BlinkControlDetector.Event] {
 var events:[BlinkControlDetector.Event]=[]
 for _ in 0..<count { t+=1/30; if let e=det.feed(t:t,left:closed ? 0.10:0.3,right:closed ? 0.10:0.3) {events.append(e)} };return events
}
_ = feed(false,20);_ = feed(true,4);precondition(feed(false,1)==[.blink]);_ = feed(false,3);_ = feed(true,4);precondition(feed(false,1)==[.doubleBlink]);pass("184-5 intentional double blink 700ms; >=60ms")
_ = feed(false,30);_ = feed(true,16);precondition(feed(false,1)==[.deliberate]);pass("184-5 deliberate 450ms")
_ = feed(false,30);_ = feed(true,1);precondition(feed(false,1).isEmpty);pass("184-5 sub60ms rejected")
// Actual decoded luma fixture input, produced by ffmpeg in run.sh.
let plain=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
let bright=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
let a=SourcePixelBounds.scan(plain,width:128,height:96,threshold:18*256)!
let b=SourcePixelBounds.scan(bright,width:128,height:96,threshold:18*256)!
precondition(a.y0==20 && a.y1==76);precondition(b.y0<=2)
let outward=SourcePixelBounds.outward(b,width:128,height:96,stereo:true)
precondition(outward.x0==0 && outward.x1==128 && outward.y0<=2);pass("184-7 letterbox crop and single bright bar pixel preserved, SBS union")
let d=StereoDepth.placeDepth(disparityPX:-20,distanceMM:500,mmPerPX:0.1,swapEyes:false)
let swapped=StereoDepth.placeDepth(disparityPX:-20,distanceMM:500,mmPerPX:0.1,swapEyes:true)
precondition(d.left==10 && d.right == -10 && swapped.left == -10);pass("184-4 crossed-eye sign and swap")
let clamped=StereoDepth.placeDepth(disparityPX:-10000,distanceMM:300,mmPerPX:0.2,swapEyes:false)
precondition(abs(2*atan(abs(clamped.disparity)*0.2/600)*180/Double.pi-1)<1e-8);pass("184-4 one degree clamp")
var continuity=PoseContinuity()
for i in 0..<20 { _ = continuity.accept([0,0,0,0,0,0],t:Double(i)/30) }
let impulse=continuity.accept([1,0,0,0,0,0],t:20.0/30)
precondition(impulse.outlier && impulse.values[0]==0);pass("184-6 single-frame impulse dropped")
continuity.faceLost();let reacq=continuity.accept([1,0,0,0,0,0],t:1)
precondition(reacq.reacquire && reacq.values[0]==0)
let landed=continuity.accept([1,0,0,0,0,0],t:1.16)
precondition(!landed.reacquire && landed.values[0]==1);pass("184-6 reacquire held pose to150ms ease")

// A flattened closed contour can have exactly zero aperture and is valid evidence, not missing.
var zero=BlinkControlDetector()
for i in 0..<20 { _=zero.feed(t:Double(i)/30,left:0.3,right:0.3) }
for i in 20..<24 { _=zero.feed(t:Double(i)/30,left:0,right:0) }
precondition(zero.feed(t:24.0/30,left:0.3,right:0.3) == .blink)
pass("184-5 zero aperture closure accepted")
// Actual production latest-value slot, exercised with a slow owned transport and discrete controls.
let slot=LatestPoseSlot(),q=DispatchQueue(label:"test.slow.transport"),guardLock=NSLock()
var delivered:[String]=[],keyIndex:Int?,maxPending=0
let group=DispatchGroup()
func drain() {
 if let v=slot.take(),slot.current(v.epoch) {Thread.sleep(forTimeInterval:0.010);guardLock.lock();delivered.append(v.payload);guardLock.unlock()}
 if slot.finish() {q.async {drain()}} else {group.leave()}
}
group.enter()
for i in 0..<500 {
 if slot.offer("pose-\(i)",at:Double(i)) {q.async {drain()}}
 if i==100 {q.async {guardLock.lock();keyIndex=delivered.count;delivered.append("key-pause");guardLock.unlock()}}
}
precondition(group.wait(timeout:.now()+5) == .success)
q.sync {}
guardLock.lock();let deliveredCopy=delivered,ki=keyIndex;guardLock.unlock()
precondition(deliveredCopy.contains("pose-499") && ki != nil && ki!<=2 && deliveredCopy.count<10)
pass("184 input slow-transport latest-only500poses bounded, discrete key interleaved, latest delivered")
_ = slot.offer("stale-after-stop",at:501);slot.clear()
precondition(slot.take()==nil);_ = slot.finish()
pass("184 input clear invalidates pending pose before teardown")

slot.close();precondition(!slot.offer("after-quit",at:502));precondition(slot.take()==nil)
pass("184 input quit rejects future poses")

let lossLatch=FrameLossLatch()
lossLatch.mark() // the lost-frame callback can be replaced by a found frame before main runs
precondition(lossLatch.consume());precondition(!lossLatch.consume())
var coalescedPose=PoseContinuity()
_ = coalescedPose.accept([0,0,0,0,0,0],t:0)
lossLatch.mark()
if lossLatch.consume() {coalescedPose.faceLost()}
let coalescedFound=coalescedPose.accept([1,1,1,1,1,1],t:1)
precondition(coalescedFound.reacquire && coalescedFound.values[0]==0)
pass("184 sticky loss survives found-frame coalescing, reacquire starts at held pose")
let mainFrames=LatestMainFrame(),mainLatch=FrameLossLatch()
var finalMainFrame = -1,lossReachedMain=false
for i in 0..<500 {
 if i==100 {mainLatch.mark()}
 mainFrames.submit { finalMainFrame=i; if mainLatch.consume(){lossReachedMain=true} }
}
let mainUntil=Date(timeIntervalSinceNow:0.1)
while finalMainFrame<499 && Date()<mainUntil {RunLoop.main.run(until:Date(timeIntervalSinceNow:0.005))}
precondition(finalMainFrame==499 && lossReachedMain)
pass("184 actual main-frame flood coalesces500->latest, sticky loss delivered")
let halves=SourcePixelBounds.scanHalves(bright,width:128,height:96,threshold:18*256)!
precondition(halves[0].y0<=2 && halves[1].y0==20)
precondition(halves[0].union(halves[1]).y0<=2)
pass("185 original16bit per-half single bright pixel preserved by union")
