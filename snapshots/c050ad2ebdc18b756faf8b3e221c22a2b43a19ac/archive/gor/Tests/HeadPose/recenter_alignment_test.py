#!/usr/bin/env python3
"""Compile the shipped recenter method. No camera or Mac execution."""
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
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
a=s.index('    func beginPoseSession() {',s.index('private var lastAngles='));b=s.index('\n    // MARK: - Capture session',a)
method=s[a:b]
pose=s[s.index('struct HeadPose {'):s.index('/// Block 182 2 distance model')]
main='''import Foundation
func CACurrentMediaTime()->Double {1}
struct Reset {mutating func recenter(){};mutating func reset(){}}
typealias PoseEyeMeasurementGate=Reset
typealias PoseNoiseCalibration=Reset
typealias PoseContinuity=Reset
typealias PoseDistanceConsistency=Reset
class PoseTraceRing {static let shared=PoseTraceRing();func append(t:Double,raw:[Double],filtered:[Double],confidence:Double,faceLost:Bool,outlier:Bool,reacquire:Bool,action:String){}}
'''+pose+'''
class Probe {
var lastBoundingBox:CGRect?=CGRect(x:0.2,y:0.3,width:0.4,height:0.5)
var baselineBoxSize:CGFloat?,baselineBoxCenter:CGPoint?
var lastAngles=(yaw:0.5,pitch:0.2,roll:0.0),neutralAngles=(yaw:0.0,pitch:0.0,roll:0.0)
var poseSessionStartedAt=0.0;var lastTracedPose=[Double](repeating:0,count:6)
var pupilDistanceScale=Reset(),poseEyeGate=Reset(),poseNoise=Reset(),poseContinuity=Reset()
var poseFollow:Int?,previousPoseOutput:[Double]?;var poseDistanceConsistency=Reset()
var onPoseUpdate:((HeadPose)->Void)?
func resetFilters(){}
'''+method+'''
}
for degrees in [-90.0,-45,0,45,90] {
 let p=Probe(),r=degrees*Double.pi/180
 p.lastAngles.roll=r
 var received:HeadPose?
 p.onPoseUpdate={received=$0}
 p.recenter()
 precondition(p.neutralAngles.yaw==0 && p.neutralAngles.pitch==0,"next fresh observation must seed viewing direction")
 precondition(p.neutralAngles.roll==0,"recenter erased the physical eye axis")
 let output=received!
 precondition(output.roll==r && output.nativeRawRoll==r && output.fusionRoll==r)
 precondition(output.yaw==0 && output.pitch==0 && output.zOffset==0 && output.xOffset==0 && output.yOffset==0)
 precondition(p.lastTracedPose==[0,0,r,0,0,0])
 precondition(p.baselineBoxCenter==nil && p.baselineBoxSize==nil,"do not seed a new baseline from the stale previous box")
 print("PASS actual recenter: current physical roll",degrees,"preserved; look-around and distance neutral; immediate publication")
}
let missing=Probe();missing.lastBoundingBox=nil
missing.onPoseUpdate={_ in preconditionFailure("missing observation invented a pose")}
missing.recenter()
print("PASS missing observation produces no invented alignment")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
pp=_s3read(_pp_split().path(root,'PPController_Features.swift'))
part=pp.split('    func recenterHeadTracking() {',1)[1].split('\n    }',1)[0]
assert part.index('resetFilmView()') < part.index('HeadTracker.shared.recenter()')
assert 'roll:relative(roll,neutralAngles.roll)' in s
print('PASS reset precedes current-pose publication; next accepted frame uses the same physical roll basis. Actual AppKit/camera NOT_RUN.')

assert part.index('resetFilmView()') < part.index('recenterPosePublishing=true') < part.index('HeadTracker.shared.recenter()')
assert 'defer {recenterPosePublishing=false}' in part
assert 'recenterPosePublishing ? ",\\"request_id\\":194" : ""' in pp
ipc=_s3read(_pp_split().path(root,'PPController.swift'))
assert 'continuousPose = command[2] as? String == "vr180-look-set-orientation" && object["request_id"] == nil' in ipc
print('PASS aligned pose carries a valid IPC request ID and bypasses the older coalesced slot; reset and aligned pose use the shared FIFO. Physical player ordering NOT_RUN.')

# Reproduce the queued-old-pose race with the actual production send/drain/slot
# methods and an owned Unix socket. The old coalesced aligned publication is a mutant.
import socket,threading,json
ipc=_s3read(_pp_split().path(root,'PPController.swift'))
def extract(text,sig):
 a=text.index(sig);b=text.index('{',a);depth=1;i=b+1
 while depth:depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[a:i]
primitive=ipc[ipc.index('    static func socketRoundtrip('):ipc.index('    // ── Convenience:',ipc.index('    static func socketRoundtrip('))]
primitive=primitive.replace('Darwin.','Glibc.').replace('SOCK_STREAM, 0','Int32(SOCK_STREAM.rawValue), 0').replace('SHUT_WR)','Int32(SHUT_WR))')
slot=_s3read(root/'Sources/gor/Camera/HeadPose.swift');slot=slot[slot.index('final class LatestPoseSlot {'):slot.index('/// Continuous camera/UI state')]
barrier=extract(ipc,'            if name == "script-message-to",command.count>2,command[1] as? String == "vr180_look" {')
barrier_method='''
func route(_ json:String) {
 var continuousPose=false,continuousLids=false
 let object=try! JSONSerialization.jsonObject(with:json.data(using:.utf8)!) as! [String:Any]
 let command=object["command"] as! [Any],name=command[0] as! String
 let ipcClient=self
'''+barrier+'''
 if continuousPose {sendLatestPose(json)} else {send(json)}
 _=continuousLids
}
'''
program='''import Foundation
import Glibc
class CommandLatencyTrace {static let shared=CommandLatencyTrace();func record(kind:String,queuedMS:Double,sendMS:Double){}}
'''+slot+'''
final class IPCClient {
let path:String
init(path:String){self.path=path}
private let poseSlot=LatestPoseSlot()
static let cmdQueue=DispatchQueue(label:"test.real.ipc")
'''+extract(ipc,'    private func drainLatestPose()')+'\n'+extract(ipc,'    func sendLatestPose(')+'\n'+extract(ipc,'    func send(_ json: String)')+'\n'+extract(ipc,'    func cancelLatestPose()')+'\n'+primitive+barrier_method+'''
}
let client=IPCClient(path:CommandLine.arguments[1]),gate=DispatchSemaphore(value:0)
IPCClient.cmdQueue.async {gate.wait()}
client.sendLatestPose(#"{"command":["old-pose"]}"#)
client.route(#"{"command":["script-message-to","vr180_look","vr180-look-full-fit"]}"#)
if CommandLine.arguments[2]=="mutant" {client.sendLatestPose(#"{"command":["aligned-pose"],"request_id":194}"#)}
else {client.send(#"{"command":["aligned-pose"],"request_id":194}"#)}
gate.signal()
IPCClient.cmdQueue.sync{}
if CommandLine.arguments[2]=="ordered" {
 client.route(#"{"command":["script-message-to","vr180_look","vr180-look-set-orientation","0.2","0.1","135","0.5"]}"#)
 IPCClient.cmdQueue.sync{}
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);server=socket.socket(socket.AF_UNIX);server.bind(str(p/'ipc'));server.listen(10);server.settimeout(.2)
 messages=[];stop=False
 def listen():
  while not stop:
   try:conn,_=server.accept()
   except socket.timeout:continue
   with conn:
    payload=b''
    while b'\n' not in payload:
     data=conn.recv(4096)
     if not data:break
     payload+=data
    messages.append(json.loads(payload))
    try:conn.sendall(b'{"error":"success"}\n')
    except BrokenPipeError:pass
 thread=threading.Thread(target=listen);thread.start()
 try:
  (p/'main.swift').write_text(program)
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'probe')],check=True)
  subprocess.run([str(p/'probe'),str(p/'ipc'),'ordered'],check=True,timeout=10)
  subprocess.run([str(p/'probe'),str(p/'ipc'),'mutant'],check=True,timeout=10)
 finally:
  stop=True;thread.join();server.close()
 names=[m['command'][2] if m['command'][0]=='script-message-to' else m['command'][0] for m in messages]
 assert names[:3]==['vr180-look-full-fit','aligned-pose','vr180-look-set-orientation'],names
 assert names[3:]==['aligned-pose','vr180-look-full-fit'],names
 print('PASS actual IPC queued-old-pose race: aligned FIFO follows full-fit; previous coalesced publication mutant runs before full-fit and is rejected')

look=_s3read(root/'Sources/gor/Stereo/LookToolsRoute.swift')
reset=look.split('    static func resetOrientationJSON()',1)[1].split('\n    }',1)[0]
assert '\"request_id\":194' in reset or 'request_id' in reset, 'reset must use ordered IPC, not continuous coalescing'
assert 'let poseBarrier' in ipc and 'if poseBarrier ||' in ipc, 'full-fit/reset IPC must invalidate pre-reset pending pose'
print('PASS reset/full-fit are transport barriers; subsequent fresh continuous pose slot stays reusable')
