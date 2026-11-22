#!/usr/bin/env python3
"""Execute production pipe/deadline/client against two owned child workers, no camera."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import subprocess,tempfile,shutil
r=Path(__file__).resolve().parents[3]
s=_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift')
ipc='// BEGIN camera-helper IPC'+_s3read(r/'Sources/gor/Camera/HeadPose.swift').split('// BEGIN camera-helper IPC',1)[1].split('// END camera-helper IPC',1)[0]
transport=s[s.index('private struct CameraVisionPacket:'):s.index('// No AVCaptureSession, AVCaptureDevice or CameraHelperEngine instance')].replace('private ','')
program='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Glibc)
import Glibc
#endif
'''+ipc+'''
final class Pixels {let pointer=UnsafeMutableRawPointer.allocate(byteCount:16,alignment:8);init(){pointer.initializeMemory(as:UInt8.self,repeating:42,count:16)}}
typealias CVPixelBuffer=Pixels
struct Flags:OptionSet {let rawValue:Int;static let readOnly=Flags(rawValue:1)}
func CVPixelBufferGetBytesPerRow(_ p:Pixels)->Int {8}
func CVPixelBufferGetHeight(_ p:Pixels)->Int {2}
func CVPixelBufferGetBaseAddress(_ p:Pixels)->UnsafeMutableRawPointer? {p.pointer}
func CVPixelBufferLockBaseAddress(_ p:Pixels,_ f:Flags){}
func CVPixelBufferUnlockBaseAddress(_ p:Pixels,_ f:Flags){}
struct QuitChildKiller {static let shared=QuitChildKiller();func register(_ p:Process){}}
struct PrepareProcessLifetime {static let ownerFlag="--gor-owner-pid"}
struct CameraVisionWorkerCLI {static let flag="--camera-vision-worker"}
struct StagedRunPaths {static func tmp(_ p:String)->String {"/tmp/gor-worker-test-unused"}}
struct BoundedDiskWriter {static func append(_ d:Data,to u:URL,cap:UInt64)->Bool {true}}
'''+transport+'''
if CommandLine.arguments.contains(CameraVisionWorkerCLI.flag) {
 let o=FileHandle.standardOutput,i=FileHandle.standardInput
 try! o.write(contentsOf:CameraHelperIPC.encode(CameraHelperIPC.Event(ev:"hello",version:CameraHelperIPC.protocolVersion,pid:getpid())))
 while true {
  do {
   let p=try JSONDecoder().decode(CameraVisionPacket.self,from:CameraVisionWire.line(i))
   let data=try CameraVisionWire.read(i,count:p.bytes)
   precondition(data==Data(repeating:42,count:16),"raw frame pixels changed")
   if p.kind=="blink" {Thread.sleep(forTimeInterval:30)}
   var f=p.frame;f.delivery=p.kind;f.processed=p.kind != "failed"
   try o.write(contentsOf:CameraHelperIPC.encode(CameraHelperIPC.Event(ev:"frame",frame:f)))
  } catch {exit(0)}
 }
}
let f=CameraHelperIPC.Frame(generation:7,window:3,now:100,pts:100,age:0,pixelWidth:2,pixelHeight:2,ambientOnly:false,settled:true,consecutiveSettled:3,seenFirstSettled:true,ambientSettled:true,processed:false,visionFailed:false,visionMS:0,exposureChanging:0)
let pixels=Pixels(),head=CameraVisionWorkerClient(kind:"head"),blink=CameraVisionWorkerClient(kind:"blink")
let done=DispatchSemaphore(value:0)
DispatchQueue.global().async {precondition(blink.infer(pixels,frame:f,log:{_ in})==nil);done.signal()}
Thread.sleep(forTimeInterval:0.15)
for _ in 0..<4 {let result=head.infer(pixels,frame:f,log:{_ in});precondition(result?.delivery=="head" && result?.processed==true)}
precondition(done.wait(timeout:.now()+8)==.success,"blink timeout must finish without blocking head")
precondition(blink.infer(pixels,frame:f,log:{_ in})==nil)
let start=Date();precondition(blink.infer(pixels,frame:f,log:{_ in})==nil);precondition(Date().timeIntervalSince(start)<0.2,"second failure is terminal for this generation")
head.stop();blink.stop()
let failed=CameraVisionWorkerClient(kind:"failed")
precondition(failed.infer(pixels,frame:f,log:{_ in})==nil)
precondition(failed.infer(pixels,frame:f,log:{_ in})==nil)
let rejectedStart=Date();precondition(failed.infer(pixels,frame:f,log:{_ in})==nil)
precondition(Date().timeIntervalSince(rejectedStart)<0.02,"failed worker reply is terminal after one retry")
failed.stop()
print("PASS actual lossless worker pipe, PID/version handshake, independent head while blink blocks, bounded timeout, one retry then terminal")
'''
# Swift parser needs whitespace around equality following an enum contextual member.
program=program.replace(')==.success',') == .success')
validity=_s3read(r/'Sources/gor/Camera/PoseMeasurementValidity.swift')
program+='\n'+validity+'''
let box=CGRect(x:0.1,y:0.1,width:0.4,height:0.4)
precondition(PoseMeasurementValidity.rectangleReason(faceCount:1,angles:[0,0,0],box:box)==0)
precondition(PoseMeasurementValidity.rectangleReason(faceCount:2,angles:[0,0,0],box:box) != 0)
precondition(PoseMeasurementValidity.rectangleReason(faceCount:1,angles:[0,Double.nan,0],box:box) != 0)
precondition(PoseMeasurementValidity.reason(faceCount:1,landmarkFaceCount:0,angles:[0,0,0],box:box,pupils:[],landmarkConfidence:0) != 0)
print("PASS actual rectangle-only pose validity; full pupil/gaze/landmark validity remains strict")
''' 
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(program)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=30)
# Product boundary and routing, not source text presented as hardware proof.
worker=s[s.index('enum CameraVisionWorkerCLI {'):s.index('/// The capture engine that used to live')]
assert 'AVCaptureSession(' not in worker and 'AVCaptureDevice.' not in worker and 'CameraHelperEngine(sink:' not in worker
assert 'try cpu(request)' in worker and 'CameraVisionDeadline(request)' in worker
assert 'packet.kind=="head" ? VNDetectFaceRectanglesRequest():VNDetectFaceLandmarksRequest()' in worker
parent=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
assert 'f.delivery == "blink" || (f.delivery == nil && f.processed)' in parent and 'PoseMeasurementValidity.rectangleReason' in parent
assert 'rectangleOnly ? nil:eyeApertures' in parent
print('PASS capture-free worker CPU/deadline and honest rectangle-only parent routing')

# Block the actual production sink writer while independent lanes coalesce.
sink=s[s.index("final class CameraHelperSink {"):s.index("// Capture-free inference boundary.")]
sinkProgram='''import Foundation
struct CameraHelperIPC {
struct Frame {var delivery:String?}
struct Event {var ev:String;var frame:Frame?;var value:Int}
static func encode(_ e:Event)->Data {Data("\\(e.ev):\\(e.frame?.delivery ?? "-"):\\(e.value)".utf8)}
}
final class FileHandle {
let started=DispatchSemaphore(value:0),resume=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
var rows:[String]=[]
func write(contentsOf data:Data)throws {if rows.isEmpty {started.signal();resume.wait()};rows.append(String(decoding:data,as:UTF8.self));if rows.count==5 {done.signal()}}
}
'''+sink+'''
let h=FileHandle(),s=CameraHelperSink(out:h)
s.send(.init(ev:"log",frame:nil,value:0));precondition(h.started.wait(timeout:.now()+2) == .success)
for n in 1...1000 {for kind in ["head","blink","ambient"] {s.send(.init(ev:"frame",frame:.init(delivery:kind),value:n))}}
s.send(.init(ev:"state",frame:nil,value:1));h.resume.signal();precondition(h.done.wait(timeout:.now()+2) == .success)
precondition(h.rows==["log:-:0","state:-:1","frame:head:1000","frame:blink:1000","frame:ambient:1000"],String(describing:h.rows))
print("PASS actual sink blocked-writer regression: 3000 frames coalesce to independent head/blink/ambient slots; state FIFO preserved")
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(sinkProgram)
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10)

# Execute the actual independent distance branch: each landmark calibrates once,
# head ticks reuse a bounded fresh reading without re-teaching the sensor.
engine=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
branch=engine[engine.index('        var distanceReady=false,zRelative='):engine.index('        lastBoundingBox = box;lastAngles=',engine.index('private func applyObservation'))]
models=_s3read(r/'Sources/gor/Camera/Pose192d.swift')
auxProgram='#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n'+models+'''
final class AuxFixture {
 var lastTracedPose=[Double](repeating:0,count:6)
 var independentDistance:(at:Double,relative:Double,ready:Bool)?
 var pupilDistanceScale=PupilDistanceScale(),poseDistanceConsistency=PoseDistanceConsistency()
 var samples=0,ready=false,z=0.0
 func feed(_ independentHead:Bool,_ auxiliaryOnly:Bool,_ capturedAt:Double,_ span:Double=20) {
 let capturedAt:Double?=capturedAt
 let pupilLeft:(Double,Double)?=(0,0),pupilRight:(Double,Double)?=(span,0)
 let landmarkKind="pupil",eyeGeometry=[0.0,0,span,0],eyeWidths=[span/2,span/2],yaw=0.0,pitch=0.0,box=CGRect(x:0,y:0,width:1,height:1)
'''+branch.replace('return}', 'samples+=1;return}')+'''
 ready=distanceReady;z=zRelative
 }
}
let a=AuxFixture()
for n in 1...34 {a.feed(false,true,Double(n)/30);for j in 0..<4 {a.feed(true,false,Double(n)/30+Double(j)/1000)}}
precondition(a.samples==34 && a.independentDistance!.ready && a.ready)
a.feed(false,true,1.2,24);a.feed(true,false,1.21);precondition(a.ready && a.z>0)
a.feed(true,false,1.5);precondition(!a.ready)
print("PASS actual auxiliary distance branch: one calibration sample per landmark, head ticks do not reteach, later landmark retained, stale distance held")
'''
# This branch uses the production relative-distance/consistency models.
auxProgram=auxProgram.replace('CACurrentMediaTime()','0.0')
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(auxProgram)
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10)
assert 'f.delivery == "blink" ? latestLandmarkFrame:latestPoseFrame' in engine
assert 'if !rectangleOnly {self.onGazeUpdate?(gaze)}' in engine
assert 'if f.delivery != "blink" {guard f.now>=lastHelperPoseTime' in engine
print('PASS independent landmark main slot and gaze delivery, no head timestamp starvation')
