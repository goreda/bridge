#!/usr/bin/env python3
"""Execute production lifecycle methods against deterministic capture/permission adapters."""
from pathlib import Path
import subprocess,tempfile,shutil
r=Path(__file__).resolve().parents[3];source=(r/'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift').read_text().split('final class HeadTracker:',1)[1]
# Take the real methods verbatim, not a parallel lifecycle model.
def between(a,b):return source[source.index(a):source.index(b)]
methods=between('    func start() {','    // MARK: - Ambient-only consumer')+between('    func startAmbientOnly() {','    // Failure is retryable')
pre='''import Foundation
func CACurrentMediaTime()->Double {0}
enum Diag { static func mediaRecord(_ s:String){} }
enum AVCaptureDevice {
 enum Status {case authorized,notDetermined,denied,restricted};enum Media {case video}
 static var status=Status.authorized;static var completion:((Bool)->Void)?
 static func authorizationStatus(for:Media)->Status{status}
 static func requestAccess(for:Media,completionHandler:@escaping(Bool)->Void){completion=completionHandler}
}
final class Session {var isRunning=false;var starts=0;var stops=0
 func startRunning(){starts+=1;isRunning=true};func stopRunning(){stops+=1;isRunning=false}}
final class PoseTraceRing {static let shared=PoseTraceRing();func append(t:Double,raw:[Double],filtered:[Double],confidence:Int,faceLost:Bool,outlier:Bool,reacquire:Bool,action:String){}}
final class Tracker {
 var activeConsumers=0;var cameraPrivacy=CameraPrivacyGate();var lifecycleGeneration:UInt64=0
 enum CameraState {case idle,authorizing,starting,running,failed};var cameraState=CameraState.idle
 var permissionRequestInFlight=false;var hasRequestedAmbientStart=false
 var onPoseUpdate:(()->Void)?;var onGazeUpdate:(()->Void)?;var onAmbientFrame:(()->Void)?;var onEyeClosure:((Int,Int,Bool)->Void)?
 var lastTracedPose:[Double]=[];var lastAngles=(0,0,0);var lastBoundingBox:Int?
 let session=Session();let sessionQueue=DispatchQueue(label:"test.session");let frameQueue=DispatchQueue(label:"test.frame")
 let lock=NSLock();var snapshot:(generation:UInt64,requested:Bool)=(0,false)
 func traceSessionEvent(_ s:String){};func beginPoseSession(){};func stopSimulatedPose(){};func promptForCameraPermission(){}
 func configureSessionIfNeeded()->Bool{true}
 func publishLifecycle(){lock.lock();snapshot=(lifecycleGeneration,activeConsumers>0 && cameraPrivacy.permitsRequests);lock.unlock()}
 func captureLifecycle()->(generation:UInt64,requested:Bool){lock.lock();defer{lock.unlock()};return snapshot}
'''
post='''
 func drain(){frameQueue.sync{};sessionQueue.sync{};RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
 func check(){
  // Queued hardware start cannot survive OFF, including another paused holder.
  sessionQueue.suspend();start();setCameraPrivacyPaused(true);start();sessionQueue.resume();drain()
  precondition(!session.isRunning && session.starts==0 && activeConsumers==2)
  setCameraPrivacyPaused(false);drain();precondition(session.isRunning)
  startAmbientOnly();precondition(hasRequestedAmbientStart)
  setCameraPrivacyPaused(true);drain();precondition(!session.isRunning)
  stopAmbientOnly();startAmbientOnly();precondition(!hasRequestedAmbientStart)
  // Repeated OFF stays inert; explicit resume restores surviving head/blink owners.
  setCameraPrivacyPaused(true);setCameraPrivacyPaused(false);drain();precondition(session.isRunning)
  stopForQuit();drain();precondition(!session.isRunning && activeConsumers==0)
  start();setCameraPrivacyPaused(false);startAmbientOnly();drain();precondition(!session.isRunning && activeConsumers==0)
 }
 func checkPermission(){
  AVCaptureDevice.status = .notDetermined;start();precondition(permissionRequestInFlight)
  setCameraPrivacyPaused(true);AVCaptureDevice.status = .authorized;AVCaptureDevice.completion?(true)
  RunLoop.main.run(until:Date().addingTimeInterval(0.02));drain();precondition(!session.isRunning && session.starts==0)
  setCameraPrivacyPaused(false);drain();precondition(session.isRunning)
  stopForQuit();drain();precondition(!session.isRunning)
 }
}
Tracker().check();Tracker().checkPermission()
print("PASS real lifecycle methods: queued start/OFF, paused consumers, ambient retry blocked, explicit resume, late permission/OFF, permanent quit; capture adapter only, native hardware NOT_RUN")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(pre+methods+post)
 subprocess.run([shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc',str(r/'Sources/gor/CameraPrivacyGate.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=15)
