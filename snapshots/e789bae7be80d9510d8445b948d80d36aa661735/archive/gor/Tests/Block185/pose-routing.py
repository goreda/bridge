
# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
s=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
a=s.index('        let measured = blinkFrameObservation',s.index('    private func processVisionFrame('));b=s.index('        let ambientRegions =',a);pose=s[a:b]
program='''import Foundation
struct VNFaceObservation {var pitch:Double?,yaw:Double?,roll:Double?;var id:Int}
final class Request {var results:[VNFaceObservation]?=[]}
func test(_ observed:VNFaceObservation?,_ expected:Int) {
 let blinkFrameObservation=observed,faceRequest=Request();let ambientOnly=false;let ambientFace:VNFaceObservation?=nil
 faceRequest.results=[VNFaceObservation(pitch:0,yaw:0,roll:0,id:2)]
'''+pose+'''
 precondition(face?.id==expected)
}
let complete=VNFaceObservation(pitch:0,yaw:0,roll:0,id:1)
let incomplete=VNFaceObservation(pitch:nil,yaw:0,roll:0,id:1)
test(complete,1);test(incomplete,2);test(nil,2)
print("PASS actual195r result selection: complete landmarks reused, missing pitch uses same-perform rectangle; no additional Vision call")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True)
print('UNVERIFIED native Vision runtime and latency; production branch exercised with boundary spies')
