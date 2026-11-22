#!/usr/bin/env python3
"""fd05 original camera restore: byte parity, real methods, blocked-Vision negative control.
Capture/permission/pose UI adapters are not Mac hardware acceptance.
"""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import subprocess,tempfile,shutil,sys,os
r=Path(__file__).resolve().parents[3]
def historical(path,ref='fd05d80'):
 if os.environ.get('GOR_TEST_HISTORY_DIR'):
  return _s3read(Path(os.environ['GOR_TEST_HISTORY_DIR'])/(ref+'-'+Path(path).name))
 return subprocess.check_output(['git','-C',str(r),'show',ref+':archive/gor/'+path],text=True)
def cut(s,a,b):return s[s.index(a):s.index(b,s.index(a))]
if '--r1-only' not in sys.argv:
 # Real IPC value types and the real client event enum; only the
 # helper process/transport boundary is doubled below.
 ipc=cut(_s3read(r/'Sources/gor/Camera/HeadPose.swift'),'enum CameraHelperIPC {','// END camera-helper IPC')
 incoming=cut(_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift'),'    enum Incoming {','    var onIncoming: (Incoming) -> Void')
 helper='''final class CameraHelperClient {
'''+incoming+'''    var onIncoming: (Incoming) -> Void = { _ in }
    // Helper-boundary double: a serial engine queue models the wire
    // order (a stop in flight applies before a later configure), the
    // gate a hung Apple stop, stopResult=false a stop even SIGKILL
    // could not confirm, crash() an unexpected child exit.
    let engineQueue=DispatchQueue(label:"test.helper.engine")
    var running=false,attached=false,starts=0,stops=0,setConfigs=0
    var lastConfig:(generation:UInt64,window:UInt64,headPose:Bool,blink:Bool,ambientOnly:Bool)?
    var stopGate:DispatchSemaphore?;let stopping=DispatchSemaphore(value:0)
    var stopResult=true;var failNextStart:String?
    func ensureRunning(generation:UInt64,window:UInt64,headPose:Bool,blink:Bool,ambientOnly:Bool){
     lastConfig=(generation,window,headPose,blink,ambientOnly)
     engineQueue.async{
      if let reason=self.failNextStart{self.failNextStart=nil;self.onIncoming(.failed(reason:reason));return}
      if !self.running{self.running=true;self.attached=true;self.starts+=1}
      self.onIncoming(.running(generation:generation))
     }
    }
    func setConfig(generation:UInt64,window:UInt64,headPose:Bool,blink:Bool,ambientOnly:Bool){setConfigs+=1;lastConfig=(generation,window,headPose,blink,ambientOnly)}
    func resetSettling(generation:UInt64,window:UInt64){}
    func stopSession(generation:UInt64,completion:@escaping(Bool)->Void){
     stops+=1
     engineQueue.async{
      self.attached=false;self.stopping.signal();self.stopGate?.wait()
      let off=self.stopResult;if off{self.running=false}
      completion(off)
     }
    }
    func crash(){engineQueue.async{self.running=false;self.attached=false;self.onIncoming(.exited)}}
    func cancelVision(_ token:UInt64){engineQueue.async{self.onIncoming(.visionCancelled(token:token))}}
    func shutdown(){}
   }
'''
 pre='import Foundation\n'+ipc+'\n'+helper+'''final class ScreenCaptureEngine {static let shared=ScreenCaptureEngine();var vrModeActive=false}
func CACurrentMediaTime()->Double {0}
enum Diag { static func mediaRecord(_ s:String){};static func log(_ s:String){} }
enum AVCaptureDevice {
 enum Status {case authorized,notDetermined,denied,restricted};enum Media {case video}
 static var status=Status.authorized;static var completion:((Bool)->Void)?
 static func authorizationStatus(for:Media)->Status{status}
 static func requestAccess(for:Media,completionHandler:@escaping(Bool)->Void){completion=completionHandler}
}
final class PoseTraceRing {static let shared=PoseTraceRing();func append(t:Double,raw:[Double],filtered:[Double],confidence:Int,faceLost:Bool,outlier:Bool,reacquire:Bool,action:String){}}
final class HeadTracker {
 static let shared=HeadTracker()
 var activeConsumers=0;var lifecycleGeneration:UInt64=0
 enum CameraState {case idle,authorizing,starting,running,stopping,failed};var cameraState=CameraState.idle
 var permissionRequestInFlight=false;var hasRequestedAmbientStart=false
 var onPoseUpdate:((Double)->Void)?;var onGazeUpdate:(()->Void)?;var onAmbientFrame:(()->Void)?;var onEyeClosure:((Int,Int,Bool)->Void)?
 var lastTracedPose:[Double]=[];var lastAngles=(0,0,0);var lastBoundingBox:Int?
 let lock=NSLock();var snapshot:(generation:UInt64,requested:Bool,ambientOnly:Bool)=(0,false,false)
 var blinkLogEnabled=false;var blinkBumps=0
 let cameraHelper=CameraHelperClient();let helperQueue=DispatchQueue(label:"test.headtrack.helper")
 var relaunchGeneration:UInt64=0;var ambientWindowID:UInt64=0
 let visionCancelLock=NSLock();var expiredVisionToken:UInt64?
 func currentExpiredVisionToken()->UInt64?{visionCancelLock.lock();defer{visionCancelLock.unlock()};return expiredVisionToken}
 func bumpBlinkEpoch(){blinkBumps+=1}
 func startSimulatedPose(){}
 func traceSessionEvent(_ s:String){};func beginPoseSession(){};func endAmbientReading(){};func stopSimulatedPose(){};func promptForCameraPermission(){}
 func publishLifecycle(){lock.lock();snapshot=(lifecycleGeneration,activeConsumers>0,hasRequestedAmbientStart && activeConsumers==1);lock.unlock();bumpBlinkEpoch()}
 func captureLifecycle()->(generation:UInt64,requested:Bool,ambientOnly:Bool){lock.lock();defer{lock.unlock()};return snapshot}
'''
 source=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift').split('final class HeadTracker:',1)[1]
 # Real production start/stop/ambient consumer bookkeeping, the real
 # beginSession/helper-config plumbing and the real helper event sink.
 methods=cut(source,'    func start() {','    // MARK: - Ambient-only consumer')+cut(source,'    func startAmbientOnly() {','    @MainActor\n    private func promptForCameraPermission')+cut(source,'    private func handleHelperIncoming','    private func handleHelperFrame')
 features=_s3read(_pp_split().path(r,'PPController_Features.swift'))
 rules=cut(features,'enum CaptureConsumerRules {','final class VR180Controller {')
 apply=cut(features,'        headTrackingPreferred=enabled','    /// GOR_TRACE_GEOM=1 only:')
 update=cut(features,'    private func updateCaptureConsumers() {','    /// Automated tests never open the camera')
 reset=cut(features,'    func resetForFileChange() {','    // State is owned by ThreeDStore.')
 # Real apply/update/reset methods with only store-routing, UI and pose delivery doubled.
 vr='''
final class VR {
 var headTrackingEnabled=false,headTrackingPreferred=false,headTrackingCameraActive=false,loadedVideoActive=false,vrModeEnabled=false,blinkCameraActive=false,headOwnsRealCameraConsumer=false
 var onExplorableSurface:(()->Void)?,onSubtitleTilt:((Double,Double)->Void)?,onUITilt:((Double)->Void)?
 static let blinkCameraAllowed=true
 func resetOrientation(){};func refreshToolsActive(){};func applyHeadPose(_ pose:Double){};func traceCameraState(_ s:String){}
 var recognitionPath="",autoFitEntry="",projectionKey="",projectionKind="",recognitionIdentity=""
 var recognitionGeneration:UInt64=0,routeRevision:UInt64=0
 struct Plan {var output=Output();struct Output {var rawValue=""}}
 var appliedPlan:Plan?;var appliedThreeD:String?,appliedEffects:String?,appliedInternal:String?
 var vrModeSetByAutoDetect=false,flatStereoFile=false,probeStarted=false,probeFinished=false,probeStereoSBS=false,probeStereoTB=false
 var manualProjection:String?,probeProjection:String?,openingProjection:String?,probeEyeAspect:Double?,probeEyeCrop:Double?,sourceMeasuredEyeAspect:Double?
 var latestWidth=0,latestHeight=0;var latestStereo:String?
 func invalidateOpenReceipt(){};func resetTestVRProperty(){}
  func setHeadTrackingEnabled(_ enabled:Bool){
'''+apply+update+reset+'''
  func refresh(){updateCaptureConsumers()}
}
'''
 run="""
 func drain(){cameraHelper.engineQueue.sync{};RunLoop.main.run(until:Date().addingTimeInterval(0.01));cameraHelper.engineQueue.sync{};RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
 func handleHelperFrame(_ f:CameraHelperIPC.Frame,generation:UInt64,ambientOnly:Bool){}
}
"""+rules+vr+"""
let t=HeadTracker.shared,v=VR()
v.setHeadTrackingEnabled(true);t.drain();precondition(!t.cameraHelper.running && t.activeConsumers==0 && t.cameraHelper.starts==0)
v.loadedVideoActive=true;v.refresh();t.drain()
precondition(t.cameraHelper.running && t.activeConsumers==1 && t.cameraState == .running && t.cameraHelper.attached)
precondition(t.cameraHelper.lastConfig!.headPose && !t.cameraHelper.lastConfig!.ambientOnly && !t.cameraHelper.lastConfig!.blink)
print("PASS consumer start configures/starts the helper; running only on the hardware-confirmed report")
t.startAmbientOnly();t.drain();precondition(t.cameraHelper.running && t.activeConsumers==2 && !t.cameraHelper.lastConfig!.ambientOnly)
t.stopAmbientOnly();t.drain();precondition(t.cameraHelper.running && t.activeConsumers==1)
t.startAmbientOnly();v.setHeadTrackingEnabled(false);t.drain();precondition(t.cameraHelper.running && t.activeConsumers==1)
precondition(t.cameraHelper.lastConfig!.ambientOnly && !t.cameraHelper.lastConfig!.headPose && t.cameraHelper.setConfigs>0)
print("PASS consumer-shape change mid-session reaches the live helper as reconfigure, no hardware restart")
t.stopAmbientOnly();t.drain();precondition(!t.cameraHelper.running && t.activeConsumers==0)
for _ in 0..<20 {t.startAmbientOnly();t.drain();precondition(t.cameraHelper.running && t.cameraState == .running);t.stopAmbientOnly();t.drain();precondition(!t.cameraHelper.running)}
v.setHeadTrackingEnabled(true);t.drain();precondition(t.cameraHelper.running)
v.loadedVideoActive=false;v.refresh();t.drain();precondition(!t.cameraHelper.running)
v.loadedVideoActive=true;v.refresh();t.drain();precondition(t.cameraHelper.running)
t.blinkLogEnabled=true;v.refresh();v.setHeadTrackingEnabled(false);t.drain();precondition(t.cameraHelper.running && t.activeConsumers==1)
precondition(t.cameraHelper.lastConfig!.blink && t.cameraHelper.lastConfig!.headPose)
t.blinkLogEnabled=false;v.refresh();t.drain();precondition(!t.cameraHelper.running && t.activeConsumers==0)
print("PASS head/ambient/blink/load consumer matrix drives helper start/stop exactly")
// C4: reset reconciles actual state; VR off alone must preserve 2D holders.
v.loadedVideoActive=true;v.setHeadTrackingEnabled(true);t.blinkLogEnabled=true;v.refresh();t.drain()
precondition(t.activeConsumers==2 && t.cameraHelper.running)
v.resetForFileChange();t.drain();precondition(t.activeConsumers==2 && t.cameraHelper.running)
v.headTrackingEnabled=false;t.blinkLogEnabled=false
v.resetForFileChange();t.drain();precondition(t.activeConsumers==0 && !t.cameraHelper.running)
print("PASS C4 actual reset/update: loaded2D holders preserved, head+blink off releases both outside ambient")
// Stop completion, not request, owns the hardware-off state: a hung
// helper stop keeps .stopping (no false idle), the delegate detaches
// at stop entry, hardware reads running until the helper confirms.
t.startAmbientOnly();t.drain();precondition(t.cameraState == .running && t.cameraHelper.running)
let stopGate=DispatchSemaphore(value:0);t.cameraHelper.stopGate=stopGate
while t.cameraHelper.stopping.wait(timeout:.now()) == .success {}
t.stopAmbientOnly();precondition(t.cameraHelper.stopping.wait(timeout:.now()+2) == .success)
precondition(t.activeConsumers==0 && t.cameraState == .stopping && t.cameraHelper.running && !t.cameraHelper.attached)
stopGate.signal();t.drain();t.cameraHelper.stopGate=nil
precondition(t.cameraState == .idle && !t.cameraHelper.running)
print("PASS blocked helper stop stays stopping, no false idle; confirmed stop goes idle")
// Z2: a newer start while the old helper stop blocks must survive the
// old completion; the helper restarts and reattaches its delegate.
t.startAmbientOnly();t.drain();let restartGate=DispatchSemaphore(value:0);t.cameraHelper.stopGate=restartGate
while t.cameraHelper.stopping.wait(timeout:.now()) == .success {}
t.stopAmbientOnly();precondition(t.cameraHelper.stopping.wait(timeout:.now()+2) == .success)
let stoppingGeneration=t.lifecycleGeneration
let startsBefore=t.cameraHelper.starts
t.startAmbientOnly();precondition(t.lifecycleGeneration>stoppingGeneration && t.activeConsumers==1 && t.cameraState == .starting)
restartGate.signal();t.drain();t.cameraHelper.stopGate=nil
precondition(t.cameraState == .running && t.cameraHelper.running && t.cameraHelper.attached && t.cameraHelper.starts==startsBefore+1)
print("PASS Z2 start during blocked helper stop: stale completion rejected, session restarted, delegate reattached")
t.stopAmbientOnly();t.drain()
// A stop the helper cannot confirm (even after SIGKILL) is a truthful
// failure, never a false off.
t.startAmbientOnly();t.drain();precondition(t.cameraState == .running)
t.cameraHelper.stopResult=false
t.stopAmbientOnly();t.drain()
precondition(t.cameraState == .failed && t.cameraHelper.running)
print("PASS unconfirmed stop, even after SIGKILL, reports failed; never a false off")
t.cameraHelper.stopResult=true
// One bounded relaunch per consumer generation on an unexpected exit;
// a second exit goes .failed, no retry loop.
t.startAmbientOnly();t.drain();precondition(t.cameraState == .running)
let liveGeneration=t.lifecycleGeneration
t.cameraHelper.crash();t.drain()
precondition(t.cameraState == .running && t.cameraHelper.running && t.relaunchGeneration==liveGeneration)
t.cameraHelper.crash();t.drain()
precondition(t.cameraState == .failed)
print("PASS unexpected helper exit: single bounded relaunch; second exit failed, no retry loop")
t.stopAmbientOnly();t.drain()
// C2: the helper watchdog's vision-cancelled event stores the expired
// token and bumps the blink epoch (cross-process invalidation).
t.startAmbientOnly();t.drain()
let bumps=t.blinkBumps
t.cameraHelper.cancelVision(7);t.drain()
precondition(t.currentExpiredVisionToken()==7 && t.blinkBumps>bumps)
print("PASS vision-cancelled stores expired token and bumps blink epoch")
t.stopAmbientOnly();t.drain()
// A helper start failure surfaces .failed with consumers still
// requested; never an optimistic running.
t.cameraHelper.failNextStart="unauthorized"
t.startAmbientOnly();t.drain()
precondition(t.cameraState == .failed && t.activeConsumers==1 && !t.cameraHelper.running)
print("PASS helper start failure surfaces failed, no optimistic running")
t.stopAmbientOnly();t.drain()
print("PASS real head/ambient/blink/load/stop lifecycle against helper-boundary doubles")
"""
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/'main.swift').write_text(pre+methods+run)
  subprocess.run([shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc',str(p/'main.swift'),'-o',str(p/'test')],check=True)
  subprocess.run([str(p/'test')],check=True,timeout=30)
  # C4 negative control: reset without reconciliation must fail.
  missing=(pre+methods+run).replace(reset,reset.replace(';updateCaptureConsumers()',''))
  (p/'missing.swift').write_text(missing)
  subprocess.run([shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc',str(p/'missing.swift'),'-o',str(p/'missing')],check=True)
  assert subprocess.run([str(p/'missing')],capture_output=True,timeout=30).returncode!=0
  print('PASS C4 missing-reset-reconciliation mutant rejected')
  # Z3 honesty negative control: an unconfirmed stop reported as idle
  # (a false off) must fail.
  falseoff=(pre+methods+run).replace('self.cameraState = stopped ? .idle : .failed','self.cameraState = .idle')
  assert falseoff!=pre+methods+run
  (p/'falseoff.swift').write_text(falseoff)
  subprocess.run([shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc',str(p/'falseoff.swift'),'-o',str(p/'falseoff')],check=True)
  assert subprocess.run([str(p/'falseoff')],capture_output=True,timeout=30).returncode!=0
  print('PASS false-off stop mutant rejected')
 if '--lifecycle-only' in sys.argv: sys.exit(0)
 assert _s3read(_pp_split().path(r,'PPController_Features.swift'))==historical('Sources/gor/gor/PPController_Features.swift')
 assert (lambda _b,_n='ThreeDMenu.swift': _b[_b.index('// BEGIN relocated '+_n+' (195y owner-order 3D consolidation, behavior unchanged)\n')+len('// BEGIN relocated '+_n+' (195y owner-order 3D consolidation, behavior unchanged)\n'):_b.index('// END relocated '+_n+'\n')])(_s3read(_threed_split().path(r)))==historical('Sources/gor/ThreeDMenu.swift')
 assert not (r/'Sources/gor/CameraPrivacyGate.swift').exists()
 current=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift');assert 'scheduleHardwareStop' not in current and 'cameraPrivacy' not in current
 # Vision-before-ambient predates today's camera changes. This test does NOT
 # claim restoration cures a Vision/AVFoundation stall on the owner's Mac.
 for ref in ['fd05d80','549e366','14b13849']:
  prior=historical('Sources/gor/Camera/ScreenCaptureEngine.swift',ref)
  assert prior.index('try handler.perform([faceRequest])')<prior.index('let ambientLuma: Double?')
 print('PASS scope: original Features/Menu exact; privacy seam retired; Vision-before-ambient still present in every baseline, hardware acceptance NOT_RUN')

# Compile and execute the production diagnostic wrapper with typed Vision
# boundary doubles. Check success/error/slow pairs and unchanged request input.
diag=_s3read(r/'Sources/gor/GorCore/Diag.swift')
diag=diag[diag.index('@available(macOS 12.0, *)\nenum VisionRequestDiag'):]
diag=diag[:diag.index('    static func camera(')]+'}\n'
stubs='''import Foundation
final class VNRequest {
 var revision=3;var usesCPUOnly=false;var preferBackgroundProcessing=false
 var supportedComputeStageDevices:[String:[String]] {get throws { ["main":["CPU","NeuralEngine"]] }}
 func computeDevice(for stage:String)->String? {nil}
}
final class VNImageRequestHandler {
 var calls=0;var captured:[VNRequest]=[];var delay=0.0;var fail=false
 func perform(_ requests:[VNRequest]) throws {
 calls+=1;captured=requests
 if delay>0 {Thread.sleep(forTimeInterval:delay)}
 if fail {throw NSError(domain:"test",code:7)}
 }
}
enum Diag {static let lock=NSLock();static var rows:[String]=[]
 static func mediaRecord(_ s:String){lock.lock();rows.append(s);lock.unlock()}
}
'''
run=r'''
let request=VNRequest(),handler=VNImageRequestHandler()
try VisionRequestDiag.perform(handler,[request],label:"rectangle")
precondition(handler.calls==1 && handler.captured[0] === request)
precondition(request.revision==3 && !request.usesCPUOnly && !request.preferBackgroundProcessing)
handler.delay=3.2;try VisionRequestDiag.perform(handler,[request],label:"landmarks")
handler.delay=0;handler.fail=true
var caught=false;do {try VisionRequestDiag.perform(handler,[request],label:"failure")}catch{caught=true}
precondition(caught && handler.calls==3)
let rows=Diag.rows.joined(separator:"\n")
precondition(rows.contains("start id=1") && rows.contains("end id=1"))
precondition(rows.contains("slow id=2") && rows.contains("threshold_s=2"))
precondition(rows.contains("result=error-test-7"))
precondition(rows.contains("supported=CPU,NeuralEngine") && rows.contains("executed_device=not-exposed"))
print("PASS actual typed diagnostic wrapper: unchanged request identity/revision/CPU/default, start/end/error/2s-slow, supported/configured distinct from executed")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(stubs+diag+run)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10)
 mutant=(stubs+diag+run).replace('do { try handler.perform(requests) }','do { }')
 (p/'mutant.swift').write_text(mutant)
 subprocess.run([swift,str(p/'mutant.swift'),'-o',str(p/'mutant')],check=True,capture_output=True)
 assert subprocess.run([str(p/'mutant')],capture_output=True).returncode!=0
 print('PASS diagnostic wrapper dropped-perform mutant rejected')
# 195r replaces the synchronous face/landmark split with one Vision submission.
s=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
helper=_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift')
# arch-195z Z3 / arch-196b C6: the camera and its Vision calls live in the
# same-executable helper now; the anchors move to the helper engine, and the
# 2 s stop + SIGKILL guarantee is pinned at the client.
assert 'try perform(handler, [faceRequest], label: "head-pose-cpu-default-revision")' in helper
assert 'try perform(handler, [blinkRequest], label: "blink-cpu-default-revision")' in helper
assert 'VISION-DIAG camera' in helper
assert 'final class CameraHelperClient' in helper and 'final class CameraHelperEngine' in helper
assert 'kill(p.processIdentifier, SIGKILL)' in helper
assert 'CameraHelperIPC.Frame' in s and 'cameraHelper.stopSession' in s
# arch-196b C2 ported to the helper: CPU-only compute selection on every
# request, fresh head-path requests per frame, bounded 1s watchdog with
# cancel-once + parent token drop, and the ambient-request guard.
assert 'guard selectVisionCPU(faceRequest), selectVisionCPU(blinkRequest) else { return }' in helper
assert 'guard selectVisionCPU(ambientFaceRequest) else { return }' in helper
assert 'beginVisionWatchdog' in helper and 'cancel_once=true recovery=sample-then-bounded-process-exit' in helper
assert '"vision-cancelled"' in helper and 'case .visionCancelled(let token):' in s
# Split invariants: stop, gaze and ambient semantics unchanged at the
# process boundary (parent side pins; helper engine pins above).
assert 'cameraHelper.stopSession(generation: generation) { stopped in' in s
assert 'cameraHelper.ensureRunning(generation: c.generation, window: c.window,' in s
assert 'cameraHelper.setConfig(generation: c.generation, window: c.window,' in s
assert 'self?.handleHelperFrame(frame, generation: frame.generation, ambientOnly: frame.ambientOnly)' in s
assert 'structureReason==0 && frameAge>=0 && frameAge<0.2' in s
assert 'BinocularGazeSample.measure(t:now,pupils:pairedPupilCoordinates,eyes:eyeGeometry,widths:measuredWidths,apertures:eyeApertures,yaw:rawYaw,pitch:rawPitch,roll:rawRoll)' in s
assert 'armAmbientFallback(luma, generation: generation, epoch: ambientEpoch())' in s
assert 'source: "deadline-full-frame"' in s
assert 'self.publishAmbient(luma, regions: nil, generation: generation, epoch: self.ambientEpoch(), source: "full-frame")' in s
assert 'self.publishAmbient(regions2.combined, regions: regions, generation: generation, epoch: self.ambientEpoch(), source: "face-room")' in s

# Run the actual parent-side ambient reading machinery (epoch, 250 ms scalar
# fallback, single publish, no late overwrite) with every boundary doubled.
# The capture callback itself moved into the camera helper (C6) where it
# cannot compile on Linux; helper_link_test.py owns the process-boundary
# behavior (hello identity, stop<2s, SIGKILL on a hung stop, stale epochs).
src=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift').split('final class HeadTracker:',1)[1]
reading=cut(src,'    private static let ambientClassificationDeadline:','    /// Fresh ambient window:')
reading=reading.replace('private ', '')
program=r"""import Foundation
func CACurrentMediaTime()->Double { ProcessInfo.processInfo.systemUptime }
typealias CFTimeInterval=Double
typealias TimeInterval=Double
struct TwoRegionLuma {var faceLuma=0.0,roomLuma=0.0,combined=0.0}
enum Diag {static let lock=NSLock();static var rows=[String]();static func mediaRecord(_ s:String){lock.lock();rows.append(s);lock.unlock()}}
final class HeadTracker {
 var activeConsumers=1;var lifecycleGeneration:UInt64=1
 var lastAmbientLuma:Double?;var lastAmbientRegions:TwoRegionLuma?
 var onAmbientFrame:(()->Void)?
"""+reading+r"""
}
func pump(_ t:Double=0.01){RunLoop.main.run(until:Date().addingTimeInterval(t))}
let t=HeadTracker();var accepted=0;t.onAmbientFrame={accepted+=1}
t.beginAmbientReading()
t.armAmbientFallback(100,generation:1,epoch:t.ambientEpoch())
t.armAmbientFallback(50,generation:1,epoch:t.ambientEpoch())
pump(0.4)
precondition(t.lastAmbientLuma==100 && t.lastAmbientRegions==nil && accepted==1)
precondition(Diag.rows.contains{$0.contains("source=deadline-full-frame")})
// One publish per window: a late face-room result must not overwrite.
t.publishAmbient(999,regions:TwoRegionLuma(),generation:1,epoch:t.ambientEpoch(),source:"face-room")
precondition(t.lastAmbientLuma==100 && accepted==1)
// A closed window rejects both its pending deadline and stale epochs.
let old=t.ambientEpoch();t.endAmbientReading();pump(0.3)
precondition(t.lastAmbientLuma==100 && accepted==1)
t.publishAmbient(20,regions:TwoRegionLuma(),generation:1,epoch:old,source:"face-room")
precondition(t.lastAmbientLuma==100 && accepted==1)
// Reopened window publishes again; a stale generation never delivers.
t.beginAmbientReading()
t.publishAmbient(20,regions:TwoRegionLuma(),generation:9,epoch:t.ambientEpoch(),source:"face-room")
precondition(t.lastAmbientLuma==100 && accepted==1)
t.publishAmbient(20,regions:TwoRegionLuma(),generation:1,epoch:t.ambientEpoch(),source:"face-room")
precondition(t.lastAmbientLuma==20 && t.lastAmbientRegions != nil && accepted==2)
print("PASS actual ambient reading: 250ms fallback once, single arm, no late overwrite, closed-window and stale-generation/epoch rejection, reopen publishes")
"""
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10)
 # Dropping the deadline publish must fail the fallback assertion.
 mutant=program.replace('self?.publishAmbient(luma, regions: nil, generation: generation, epoch: epoch, source: "deadline-full-frame")','return')
 (p/'mutant.swift').write_text(mutant)
 subprocess.run([swift,str(p/'mutant.swift'),'-o',str(p/'mutant')],check=True,capture_output=True)
 assert subprocess.run([str(p/'mutant')],capture_output=True,timeout=5).returncode!=0
 print('PASS missing-deadline negative control rejected')

# Original behavior pin: same production pixel math, provider calibration and
# brightness/duty-cycle consumer. Test actual Swift BGRA routines, not a port.
import re,hashlib
# Baseline hashes were computed from0aa7181; no Git history needed on deployed Mac.
current=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
def body(text,marker,end):return cut(text,marker,end)
mathStart='    static func averageLumaSingleRegion('
mathEnd='    // Main-thread pose state and callback delivery.'
newMath=body(current,mathStart,mathEnd);oldMath=newMath
assert hashlib.sha256(newMath.encode()).hexdigest()=='bdf626de247f4f2f633a43f2b0b65c77ddbe0ec260ba75fb09cc0b39c351d645','original pixel split,face margin or weighting changed'
def classbody(s,name):
 a=s.index('final class '+name);return s[a:s.index('\n}',a)+2]
def compact(s):return re.sub(r'\s+','',re.sub(r'//[^\n]*','',s))
assert hashlib.sha256(compact(classbody(current,'AmbientLightProvider')).encode()).hexdigest()=='f2b77f1368bab2671d83ec80f6f38b4727230f8c240c3eda52b3a1731bdf45fb'
features=_s3read(_pp_split().path(r,'PPController_Features.swift'))
# Only the two existing window receipt destinations changed, not duty behavior.
windowClass=classbody(features,'ContentAdaptiveDimming')
assert windowClass.count('Diag.mediaRecord("[AmbientDiag] window')==2
windowClass=windowClass.replace('Diag.mediaRecord("[AmbientDiag] window','Diag.log("[AmbientDiag] window')
assert windowClass.count('Diag.mediaRecord("AMBIENT-WINDOW trigger=')==2
windowClass=windowClass.replace('Diag.mediaRecord("AMBIENT-WINDOW trigger=checkpoint fraction=\\(fraction)"); ','').replace('Diag.mediaRecord("AMBIENT-WINDOW trigger=pause"); ','')
assert hashlib.sha256(windowClass.encode()).hexdigest()=='633b7fe7b288e426f8c784d9eb17fca626f8c6d4b78826f1ccfdcae49ef6c56e'
# The ambient luma read moved into the helper with the same selected-face rule.
assert 'frame.lumaFull = frame.lumaFull ?? HeadTracker.averageLumaSingleRegion(of: pixelBuffer)' in helper
assert 'if ambientSettled { frame.lumaFull = HeadTracker.averageLumaSingleRegion(of: pixelBuffer) }' in helper
print('PASS exact0aa7181 pixel math+face/room75/25+margins; providercalibration10..180+EMA0.12; brightnessconsumer/dutyclassBYTEIDENTICALexcept2receiptDestinations')
# Foundation re-exports CGRect's geometry extensions on swift-corelibs, but
# Darwin requires CoreGraphics explicitly for minX/maxX/minY/maxY. Keep the
# production pixel methods byte-identical rather than adapting their math.
pixelStubs=r'''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
final class CVPixelBuffer {
 let w:Int,h:Int,p:UnsafeMutablePointer<UInt8>
 init(_ w:Int,_ h:Int){self.w=w;self.h=h;p = .allocate(capacity:w*h*4);p.initialize(repeating:0,count:w*h*4)}
 deinit{p.deallocate()}
}
struct LockFlags{static let readOnly=LockFlags()}
let kCVPixelFormatType_32BGRA:UInt32=42
func CVPixelBufferGetPixelFormatType(_ b:CVPixelBuffer)->UInt32{42}
func CVPixelBufferLockBaseAddress(_ b:CVPixelBuffer,_ f:LockFlags){}
func CVPixelBufferUnlockBaseAddress(_ b:CVPixelBuffer,_ f:LockFlags){}
func CVPixelBufferGetBaseAddress(_ b:CVPixelBuffer)->UnsafeMutableRawPointer?{UnsafeMutableRawPointer(b.p)}
func CVPixelBufferGetWidth(_ b:CVPixelBuffer)->Int{b.w}
func CVPixelBufferGetHeight(_ b:CVPixelBuffer)->Int{b.h}
func CVPixelBufferGetBytesPerRow(_ b:CVPixelBuffer)->Int{b.w*4}
'''
wrapper=r'''
 static func single(_ b:CVPixelBuffer)->Double?{averageLumaSingleRegion(of:b)}
 static func split(_ b:CVPixelBuffer,_ face:CGRect)->[Double]?{averageLumaTwoRegion(of:b,faceBox:face).map{[$0.faceLuma,$0.roomLuma,$0.combined]}}
}
'''
program=pixelStubs+'enum Original {\n'+oldMath+wrapper+'enum Restored {\n'+newMath+wrapper+r'''
let b=CVPixelBuffer(96,72)
var cases=0
for light in [10,40,120,230] {
 for y in 0..<b.h {for x in 0..<b.w {
  let v=UInt8((x>32 && x<65 && y>20 && y<60) ? light:30)
  for c in 0..<3 {b.p[(y*b.w+x)*4+c]=v};b.p[(y*b.w+x)*4+3]=255
 }}
 for box in [CGRect(x:0.35,y:0.3,width:0.3,height:0.4),CGRect(x:0,y:0,width:0.2,height:0.3),CGRect(x:0.7,y:0.7,width:0.2,height:0.2)] {
  let old=Original.split(b,box)!,new=Restored.split(b,box)!
  precondition(zip(old,new).allSatisfy{abs($0-$1)<1e-12})
  precondition(abs(new[2]-(new[1]*0.75+new[0]*0.25))<1e-12);cases+=1
 }
 precondition(Original.single(b)==Restored.single(b))
}
print("PASS actual Swift original/restored same-frame pixel fixtures \(cases): face/room/combined identical, nofacefallback identical")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)

# Permanent Oct12 V2 /0aa7181 duty gate: execute production methods with only
# camera/ALS and brightness dependencies doubled. Actual timer opens at0.6s.
duty=cut(features,'    // MARK: - Ambient camera duty-cycling','    // MARK: - Dependencies (closures back to PPController')
program=r'''import Foundation
typealias CFTimeInterval=Double
func CACurrentMediaTime()->Double{ProcessInfo.processInfo.systemUptime}
enum Diag{static func log(_ s:String){};static func mediaRecord(_ s:String){}}
final class AmbientLightProvider {static let shared=AmbientLightProvider();var value:Double?;func normalizedLevel()->Double?{value}}
final class HeadTracker {static let shared=HeadTracker();var starts=0,stops=0,running=false;var onAmbientFrame:(()->Void)?
 func resetAmbientSettling(){};func startAmbientOnly(){if !running {starts+=1;running=true}}
 func stopAmbientOnly(){if running {stops+=1;running=false}}
}
final class Duty {
 var runtimeEnabled=true,playbackActive=true;var windows=[Bool]()
 func setAmbientWindowOpen(_ on:Bool){windows.append(on)}
'''+duty+r'''
 func test(){
 let h=HeadTracker.shared,a=AmbientLightProvider.shared
 startAmbientDutyCycle();RunLoop.main.run(until:Date().addingTimeInterval(0.68));precondition(h.running && h.starts==1)
 precondition(Self.firstAmbientWindowDelay==0.6 && Self.ambientFirstWindowCeiling==15 && Self.ambientDutyCycleOnDuration==2 && Self.ambientRetryDelay==7)
 precondition(Self.ambientCheckpointFractions==[0,0.125,0.25,0.5,0.75])
 a.value=0.42;h.onAmbientFrame?();precondition(!h.running && h.stops==1 && a.value==0.42)
 // Pausing a loaded playing film intentionally reopens and reads again.
 handlePlaybackPaused();precondition(h.running && h.starts==2)
 a.value=0.55;h.onAmbientFrame?();precondition(!h.running && h.stops==2 && a.value==0.55)
 handlePlaybackPaused();precondition(h.starts==3 && h.running);h.onAmbientFrame?()
 for progress in [0.125,0.25,0.5,0.75] {let before=h.starts;checkAmbientCheckpoints(currentTime:100*progress,duration:100);precondition(h.starts==before+1 && h.running);h.onAmbientFrame?();precondition(!h.running)}
 let n=h.starts;checkAmbientCheckpoints(currentTime:75,duration:100);precondition(h.starts==n)
 stopAmbientDutyCycle();handlePlaybackPaused();precondition(!h.running && h.starts==n)
 playbackActive=false;openAmbientWindow();precondition(!h.running)
 print("PASS actualOct12V2 duty:0.6sfirst,15/2/7s,12.5/25/50/75checkpoints,pause-transitionnewreading,acceptedframeclose+stop,last-value-retained,stop/idleguards")
 }
}
Duty().test()
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True,timeout=5)
# ALS/camera/n-a order is part of the fixed provider hash above. Keep explicit
# receipts so the gate says which contract it protects rather than only a hash.
provider=classbody(current,'AmbientLightProvider')
assert provider.index('if alsServiceAvailable, let lux = rawLux()') < provider.index('guard let raw = HeadTracker.shared.lastAmbientLuma')
assert 'static let ambientSettleFramesRequired = 3' in helper
print('PASS standing source priority ALS→camera→n/a;3consecutiveAE/AWBsettledframes;no inventeddefault ambient')
