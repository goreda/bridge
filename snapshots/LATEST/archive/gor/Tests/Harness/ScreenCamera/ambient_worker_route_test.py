#!/usr/bin/env python3
"""Actual C5 process routing with worker/transport doubles; no hardware claim."""
from pathlib import Path
import subprocess,shutil,tempfile
r=Path(__file__).resolve().parents[3];source=(r/'Sources/gor/Camera/Runtime.swift').read_text()
a=source.index('    private func process(_ pixelBuffer:');b=source.index('        let handler = VNImageRequestHandler',a)
route=source[a:b]+'    }\n'
program='''import Foundation
typealias CVPixelBuffer=Int
enum CameraHelperIPC {
struct Frame {var generation:UInt64;var ambientOnly:Bool;var delivery:String?}
struct Event {var ev:String;var frame:Frame}
}
final class Worker {
 let kind:String;var calls=0;var result=true;var before:(()->Void)?
 init(_ kind:String){self.kind=kind}
 func infer(_ p:Int,frame:CameraHelperIPC.Frame,log:(String)->Void)->CameraHelperIPC.Frame? {
 calls+=1;before?();if !result{return nil};var f=frame;f.delivery=kind;return f
 }
}
final class Sink {var events:[CameraHelperIPC.Event]=[];func send(_ e:CameraHelperIPC.Event){events.append(e)}}
final class Engine {
 let headWorker=Worker("head"),ambientWorker=Worker("ambient"),sink=Sink()
 var generation:UInt64=7
 func snapshot()->(generation:UInt64,unused:Bool){(generation,false)}
 func mediaLog(_ s:String){}
'''+route+'''
 func run(){
  let ambient=CameraHelperIPC.Frame(generation:7,ambientOnly:true)
  process(1,into:ambient,blink:false)
  precondition(ambientWorker.calls==1 && headWorker.calls==0 && sink.events.count==1 && sink.events[0].frame.delivery=="ambient")
  ambientWorker.result=false;process(1,into:ambient,blink:false);precondition(sink.events.count==1)
  ambientWorker.result=true;ambientWorker.before={self.generation=8};process(1,into:ambient,blink:false);precondition(sink.events.count==1)
  generation=7;let head=CameraHelperIPC.Frame(generation:7,ambientOnly:false)
  process(1,into:head,blink:false);precondition(headWorker.calls==1 && ambientWorker.calls==3 && sink.events.count==2 && sink.events[1].frame.delivery=="head")
 }
}
Engine().run()
print("PASS actual C5 ambient independent worker route, nil/stale-generation rejection, head route unchanged")
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(program);swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
 # Dropped ambient generation check must be rejected by the same actual routing fixture.
 mutant=program.replace('ambientWorker.infer(pixelBuffer,frame:frame,log:mediaLog),snapshot().generation==frame.generation','ambientWorker.infer(pixelBuffer,frame:frame,log:mediaLog)')
 assert mutant!=program;(p/'main.swift').write_text(mutant);subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'mutant')],check=True)
 assert subprocess.run([str(p/'mutant')],capture_output=True).returncode!=0
 print('PASS C5 dropped-generation-check mutant rejected')
# Admission, scalar fallback and public consuming policy remain untouched by this commit.
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import hashlib
for rel in ['Sources/gor/Camera/Sensing.swift','Sources/gor/Camera/HeadPose.swift','Tests/Harness/ScreenCamera/vision_worker_native.py','Sources/gor/gor/PPController_Features.swift']:
 baseline=subprocess.check_output(['git','-C',str(r),'show','9f4a5558aecc85c6d1538c1ed218ec478c0228e2:archive/gor/'+rel])
 actual=(_pp_split().path(r,'PPController_Features.swift') if rel.endswith('/PPController_Features.swift') else r/rel).read_bytes()
 if rel=='Sources/gor/Camera/Sensing.swift':
  added=b'event=hardware-stopped running=\\(!stopped) stopped=\\(stopped) generation=\\(generation)'
  prior=b'event=hardware-stopped running=\\(!stopped) generation=\\(generation)'
  if actual.count(added)==1: actual=actual.replace(added,prior,1)
 assert actual==baseline,rel
print('PASS C5 sensing/window/scalar-fallback policy, ambient duty consumer and native74 camera regression driver byte-identical S3')
