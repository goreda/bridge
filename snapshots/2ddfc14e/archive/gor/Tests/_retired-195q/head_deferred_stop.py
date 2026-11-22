#!/usr/bin/env python3
"""Production stop body with queue/session boundary doubles, not native camera acceptance."""
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
s=(r/'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift').read_text()
a=s.index('    func stop() {',s.index('private enum CameraState'));b=s.index('\n    // MARK: - Ambient-only',a)
stop=s[a:b].strip()
header='''import Foundation
func check(_ b:Bool,_ n:String){precondition(b,n);print("PASS "+n)}
final class Session {var stops=0;func stopRunning(){stops+=1}}
final class PoseTraceRing {static let shared=PoseTraceRing();func append(t:Double,raw:[Int],filtered:Int,confidence:Int,faceLost:Bool,outlier:Bool,reacquire:Bool,action:String){}}
func CACurrentMediaTime()->Double {0}
final class Tracker {
 var activeConsumers=1;var lifecycleGeneration:UInt64=1
 enum State {case idle,running};var cameraState=State.running
 var onEyeClosure:((Int,Int,Bool)->Void)?;var lastTracedPose=0
 var lastAngles=(0,0,0);var lastBoundingBox:Int?
 let session=Session(),frameQueue=DispatchQueue(label:"test.frame"),sessionQueue=DispatchQueue(label:"test.session")
 let lock=NSLock();var snapshot:(generation:UInt64,requested:Bool)=(1,true)
 func traceSessionEvent(_ s:String){};func beginPoseSession(){}
 func publishLifecycle(){lock.lock();snapshot=(lifecycleGeneration,activeConsumers>0);lock.unlock()}
 func captureLifecycle()->(generation:UInt64,requested:Bool){lock.lock();defer{lock.unlock()};return snapshot}
 func start(){activeConsumers+=1;lifecycleGeneration &+= 1;publishLifecycle()}
'''
main='''
}
// The real stop must not enter the session while a delivered frame owns Vision.
let t=Tracker(),entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
t.frameQueue.async {entered.signal();release.wait()}
entered.wait();t.stop();t.sessionQueue.sync{}
check(t.session.stops==0,"stop waits for in-flight Vision frame, not concurrent teardown")
release.signal();t.frameQueue.sync{};t.sessionQueue.sync{}
check(t.session.stops==1,"final consumer teardown proceeds after frame drains")
let n=Tracker(),entered2=DispatchSemaphore(value:0),release2=DispatchSemaphore(value:0)
n.frameQueue.async {entered2.signal();release2.wait()}
entered2.wait();n.stop();n.start();release2.signal();n.frameQueue.sync{};n.sessionQueue.sync{}
check(n.session.stops==0,"new consumer fences deferred old stop")
let shared=Tracker();shared.activeConsumers=2;shared.publishLifecycle();shared.stop();shared.frameQueue.sync{};shared.sessionQueue.sync{}
check(shared.activeConsumers==1 && shared.session.stops==0,"head stop cannot tear down blink or ambient holder")
let idle=Tracker();idle.activeConsumers=0;idle.publishLifecycle();idle.stop();idle.frameQueue.sync{};idle.sessionQueue.sync{}
check(idle.session.stops==0,"repeated stop does not underflow or stop again")
print("UNVERIFIED native AVFoundation/Vision restart and real camera indicator")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(header+stop+main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
