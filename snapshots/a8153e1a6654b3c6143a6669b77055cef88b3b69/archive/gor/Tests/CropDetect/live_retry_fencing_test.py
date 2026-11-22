#!/usr/bin/env python3
"""Execute current production detector and PP retry/manual methods, never historical fixtures.
Only services and the timer queue are doubled, so stale callbacks are fired deliberately.
"""
from pathlib import Path
import os, shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
cd=(root/'Sources/gor/Picture/CropDetector.swift').read_text()
pp=(root/'Sources/gor/Player/PPController.swift').read_text()
def method(s, signature):
    a=s.index(signature);b=s.index('\n    }',a)+6
    return s[a:b]
detect=method(cd,'    func detect(filePath:')
cancel=method(cd,'    func cancel()')
reset=method(cd,'    func resetLastFile()')
retry=method(pp,'    private func fireWTCropRetry(').replace('private func','func').replace('DispatchQueue.main','TestQueue.main')
manual=method(pp,'    func reDetectCrop()')
header=r'''
import Foundation
final class SourcePixelCropScanner {
 var completions:[(CGRect?,Bool,Double)->Void]=[]
 func cancel(){}
 func dropCarry(){}
 func scan(path:String,duration:Double,stereo:Bool,topBottom:Bool,viewportOnly:Bool,caller:String,fresh:Bool,positions:(()->[Double]?)?,interim:((CGRect,Double)->Void)?,completion:@escaping(CGRect?,Bool,Double)->Void){completions.append(completion)}
}
enum WTCropSamples {static func positions(path:String,mainIPCPath:String?,manual:Bool)->[Double]?{nil}}
enum HeatTelemetry {static var thermalPressure=false}
struct Deadline {static func now()->Deadline{Deadline()};static func +(a:Deadline,b:Int)->Deadline{a}}
final class TestQueue {
 static let main=TestQueue();var work:[()->Void]=[]
 func asyncAfter(deadline:Deadline,execute:@escaping()->Void){work.append(execute)}
 func fire(){let f=work.removeFirst();f()}
}
final class CropDetector {
 let sourceScanner=SourcePixelCropScanner();var retryGeneration=0
 var retryToken:Int{retryGeneration};var isPending=false;var lastDetectedFile=""
 var stereoSBS=false,stereoTopBottom=false,viewportOnly=false,hasScanProgress=false
 var mainIPCPath:String?;var onResult:((CGRect?,Bool,Double)->Void)?
 let detectionLock=NSLock();var detectionGeneration=0;var detectionFile=""
 func terminateAllActive(){};func reportStatus(_ text:String?){}
 static func isWTPlayback(_ path:String)->Bool{path.hasPrefix("wt:")}
'''
host=r'''
}
final class Host {
 let cropDetector=CropDetector();var currentFilePath="wt:a";var menuCropOwnsSelection=false
 var isPlaying=true
 var embeddedBackend=false;var embeddedSourceCrop:((String,CGRect)->String?)?
 var manualMenuCropAspect:Double?;var stereoRestorePending=false;var manualRedetectInFlight=false
 var videoDisplayW=1920.0,videoDisplayH=1080.0,duration=600.0
 var starts=0;var needsRedetectSeen=false
 func startAutomaticCropDetection(needsRedetect:Bool=false){starts += 1;needsRedetectSeen=needsRedetect;cropDetector.detect(filePath:currentFilePath,videoW:videoDisplayW,videoH:videoDisplayH,fallbackDuration:duration)}
 func refreshCropSourcePacking(){};func refuseEmbedded(_ text:String)->Bool{false};func showCropDetectOSD(_ text:String){}
'''
cases=r'''
}
func fire(_ h:Host,_ t:Int){h.fireWTCropRetry(h.currentFilePath,token:t)}
let h=Host();var delivered=0;h.cropDetector.onResult={_,_,_ in delivered += 1}
let initial=h.cropDetector.retryToken
fire(h,initial);precondition(h.starts==1 && h.needsRedetectSeen)
let oldCallback=h.cropDetector.sourceScanner.completions[0]
let prior=h.cropDetector.retryToken;h.cropDetector.cancel();fire(h,prior);precondition(h.starts==1)
oldCallback(nil,true,1);precondition(delivered==0 && !h.cropDetector.isPending)
// A manual click cancels/restarts a stale scan; its old completion cannot clear pending.
h.startAutomaticCropDetection();let stale=h.cropDetector.sourceScanner.completions.last!;let beforeManual=h.cropDetector.retryToken
h.reDetectCrop();precondition(h.cropDetector.retryToken>beforeManual && h.cropDetector.isPending && h.manualRedetectInFlight)
stale(nil,true,1);precondition(h.cropDetector.isPending && delivered==0)
fire(h,beforeManual);precondition(h.starts==2)
h.cropDetector.sourceScanner.completions.last!(nil,true,1);precondition(!h.cropDetector.isPending && delivered==1)
// Fresh progress joins rather than restarting; old retry remains suppressed while pending.
h.cropDetector.resetLastFile();h.startAutomaticCropDetection();h.cropDetector.hasScanProgress=true
let joined=h.cropDetector.retryToken;let scans=h.cropDetector.sourceScanner.completions.count;h.reDetectCrop()
precondition(h.cropDetector.retryToken==joined && scans==h.cropDetector.sourceScanner.completions.count)
fire(h,joined);precondition(h.starts==3)
h.cropDetector.cancel();h.cropDetector.hasScanProgress=false
// File switch discards the captured retry even if its token has not changed.
let fileToken=h.cropDetector.retryToken;h.currentFilePath="wt:b";h.fireWTCropRetry("wt:a",token:fileToken);precondition(h.starts==3)
// Thermal deferral preserves the same token and budget; cooling triggers exactly once.
HeatTelemetry.thermalPressure=true;fire(h,fileToken);precondition(TestQueue.main.work.count==1 && h.starts==3)
TestQueue.main.fire();precondition(TestQueue.main.work.count==1 && h.starts==3)
HeatTelemetry.thermalPressure=false;TestQueue.main.fire();precondition(h.starts==4 && TestQueue.main.work.isEmpty)
h.cropDetector.cancel();let hotToken=h.cropDetector.retryToken;HeatTelemetry.thermalPressure=true;fire(h,hotToken)
h.reDetectCrop();h.cropDetector.sourceScanner.completions.last!(nil,true,1);HeatTelemetry.thermalPressure=false
TestQueue.main.fire();precondition(h.starts==4 && TestQueue.main.work.isEmpty)
h.cropDetector.cancel();let menuToken=h.cropDetector.retryToken;h.menuCropOwnsSelection=true;fire(h,menuToken);precondition(h.starts==4)
let native=Host();native.embeddedBackend=true;native.reDetectCrop();precondition(native.cropDetector.sourceScanner.completions.isEmpty)
native.embeddedSourceCrop={_,_ in nil};native.reDetectCrop();precondition(native.cropDetector.sourceScanner.completions.count==1)
print("PASS live detector completion fencing, cancel, manual restart/join, file switch, thermal same-token defer/cool, menu ownership, native adapter admission")
'''
variants={'green':(detect,cancel,retry),
 'red-completion-token':(detect.replace('guard let self, self.retryGeneration==token else','guard let self else'),cancel,retry),
 'red-cancel-token':(detect,cancel.replace('retryGeneration += 1',''),retry),
 'red-retry-token':(detect,cancel,retry.replace('cropDetector.retryToken==token,','')),
 'red-file-fence':(detect,cancel,retry.replace('currentFilePath==scheduled,','')),
 'red-thermal-token':(detect,cancel,retry.replace('self.fireWTCropRetry(scheduled,token:token)','self.fireWTCropRetry(scheduled,token:self.cropDetector.retryToken)'))}
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-install/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as td:
 t=Path(td)
 for name,(d,c,r) in variants.items():
  text=header+d+'\n'+c+'\n'+reset+host+r+'\n'+manual+cases
  p=t/'main.swift';p.write_text(text);out=t/name
  cp=subprocess.run([swift,'-swift-version','5',str(p),'-o',str(out)],capture_output=True,text=True)
  assert cp.returncode==0,(name,cp.stderr)
  rp=subprocess.run([str(out)],capture_output=True,text=True,timeout=5)
  if name=='green':assert rp.returncode==0,rp.stderr;print(rp.stdout.strip())
  else:assert rp.returncode!=0,'mutant survived: '+name;print('PASS semantic mutant runtime RED: '+name)
