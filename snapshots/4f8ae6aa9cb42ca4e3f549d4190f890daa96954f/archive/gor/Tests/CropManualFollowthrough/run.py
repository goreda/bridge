from pathlib import Path
import subprocess,json,hashlib,os
import tempfile
fixture=Path(__file__).resolve().parent
repo=fixture.parents[1]
scratch=tempfile.TemporaryDirectory(prefix='crop-manual-followthrough-')
root=Path(scratch.name)
swift=os.environ.get('SWIFTC','swiftc')
def method(s,name):
 a=s.index(name);b=s.index('{',a);depth=1;i=b+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]
source=(repo/'Sources/gor/Player/PPController.swift').read_text()
detector=(repo/'Sources/gor/Picture/CropDetector.swift').read_text()
detect=method(detector,'    func detect(filePath:')
start=source.index('        cropDetector.onResult = ')
end=source.index('        cropDetector.onStatus = ',start)
callback=source[start:end]
helpers=source[source.index('    // One manual request'):source.index('    private var cropMeasurementEpoch')]
redetect=method(source,'    func reDetectCrop()')
preamble=r'''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
struct CropAcceptPolicy { static var allow=true; static func accepts(rect:CGRect?,stereo:Bool,startPlayhead:Double,nowPlayhead:Double,stream:Bool,manual:Bool)->Bool {allow} }
struct CropScanGuard { static let shared=CropScanGuard();var startPlayhead:Double{0} }
struct WTCropSamples { static func positions(path:String,mainIPCPath:String?,manual:Bool,widenLevel:Int)->[Double]{[manual ? 9:0]} }
final class Scanner {
 var drops=0;var scans:[Bool]=[];var completion:((CGRect?,Bool,Double)->Void)?
 func dropCarry(){drops+=1}
 func scan(path:String,duration:Double,stereo:Bool,topBottom:Bool,viewportOnly:Bool,caller:String,fresh:Bool,positions:()->[Double],interim:@escaping(CGRect?,Double)->Void,completion:@escaping(CGRect?,Bool,Double)->Void){scans.append(fresh);self.completion=completion;_ = positions()}
 func finish(_ rect:CGRect?,_ decisive:Bool,_ confidence:Double){let c=completion;completion=nil;c?(rect,decisive,confidence)}
}
final class CropDetector {
 var isPending=false;var hasScanProgress=true;var retryGeneration=0;var retryToken:Int{retryGeneration}
 var lastDetectedFile="";var automaticWidenLevel=0;var stereoSBS=false;var stereoTopBottom=false;var viewportOnly=false;var perEyeAspect:Double?;var mainIPCPath:String?
 var onResult:((CGRect?,Bool,Double)->Void)?;let sourceScanner=Scanner();var cancels=0
 static func isWTPlayback(_ p:String)->Bool{p.hasPrefix("wt:")}
 func nextAutomaticWidenLevel(path:String,manual:Bool)->Int{automaticWidenLevel}
 func reportStatus(_ s:String?){}
 func cancel(){cancels+=1;retryGeneration+=1;isPending=false}
 func resetLastFile(){lastDetectedFile=""}
'''
controller=r'''}
enum CropTransition {case apply(CGRect),reRect(CGRect),revert}
final class Controller {
 let cropDetector=CropDetector();var currentFilePath="wt:movieA";var cropSourceOpening:UInt64=1;var cropMeasurementEpoch:UInt64=1
 var manualRedetectInFlight=false;var menuCropOwnsSelection=false;var presentationIsQuitting=false;var cropDetectionStopped=false;var mediaTransitionPending=false
 var rejectedCropRetryAvailable=false;var cropPacketTokenAttempts=0;var embeddedBackend=false;var embeddedSourceCrop:Int?;var manualMenuCropAspect:Double?;var stereoRestorePending=false
 var videoDisplayW=1920.0;var videoDisplayH=1080.0;var duration=1000.0;var currentTime=0.0;var isPlaying=true;var cropSearchOwnsSelection=false
 var wtCropRetry:[String:(n:Int,t:Double,end:Double)]=[:];var lastSeekableEnd=100.0;var cropRect:CGRect?;var transitions:[Bool]=[];var rejected=0
 static func wtCropRetryDelay(attempt:Int)->Double{3600}
 func fireWTCropRetry(_ path:String,token:Int){}
 func showCropDetectOSD(_ text:String){}
 func refuseEmbedded(_ text:String)->Bool{false}
 func refreshCropSourcePacking(){}
 func recoverRejectedAutomaticCrop(early:Bool,manual:Bool){rejected+=1}
 func transitionCrop(_ t:CropTransition,confidence:Double,manual:Bool){transitions.append(manual)}
 func install(){
'''
post='    }\n'
tests=r'''
 static func runTests(){
  var checks=0;var failures=0
  func ck(_ ok:Bool,_ text:String){checks+=1;if !ok {failures+=1;print("FAIL "+text)}}
  func started()->Controller{let c=Controller();c.install();c.cropDetector.detect(filePath:c.currentFilePath,videoW:1920,videoH:1080,fallbackDuration:1000);return c}
  let rect=CGRect(x:0.1,y:0,width:0.8,height:1)
  do {let c=started();c.reDetectCrop();c.reDetectCrop();c.reDetectCrop();ck(c.cropDetector.cancels==0,"join never cancels active scan");ck(c.cropDetector.sourceScanner.scans==[false],"join never restarts active scan");ck(!c.manualRedetectInFlight,"auto batch not relabelled manual");c.cropDetector.sourceScanner.finish(nil,false,0);ck(c.cropDetector.sourceScanner.scans==[false,true],"terminal indecisive starts exactly one fresh manual");ck(c.cropDetector.sourceScanner.drops==1,"manual invocation drops carried votes");ck(c.cropDetector.isPending && c.manualRedetectInFlight,"manual invocation starts after old pending clears");c.reDetectCrop();c.reDetectCrop();c.cropDetector.sourceScanner.finish(nil,false,0);ck(c.cropDetector.sourceScanner.scans==[false,true],"fresh indecisive and repeated clicks do not self-loop");ck(!c.manualRedetectInFlight,"fresh terminal clears manual state");ck(c.wtCropRetry[c.currentFilePath] != nil,"ordinary automatic retry bookkeeping preserved")}
  do {let c=started();c.reDetectCrop();c.cropDetector.sourceScanner.finish(rect,true,0.9);ck(c.cropDetector.sourceScanner.scans==[false],"decisive auto satisfies join without extra pass");ck(c.transitions==[false],"decisive old batch retains automatic policy")}
  do {let c=started();c.reDetectCrop();c.cropDetector.onResult?(rect,true,-0.9);ck(c.cropDetector.sourceScanner.scans==[false],"early usable never restarts active scan");c.cropDetector.sourceScanner.finish(nil,false,0);ck(c.cropDetector.sourceScanner.scans==[false],"usable early result discharges queued request")}
  for fence in 0..<8 {let c=started();c.reDetectCrop();switch fence {case 0:c.currentFilePath="wt:movieB";case 1:c.cropSourceOpening+=1;case 2:c.cropMeasurementEpoch+=1;case 3:c.cropDetector.cancel();case 4:c.cropDetectionStopped=true;case 5:c.presentationIsQuitting=true;case 6:c.mediaTransitionPending=true;default:c.menuCropOwnsSelection=true};c.cropDetector.isPending=false;c.cropDetector.onResult?(nil,false,0);ck(c.cropDetector.sourceScanner.scans==[false],"stale continuation fenced case \(fence)")}
  do {let c=started();c.reDetectCrop();c.cropDetector.cancel();c.cropDetector.sourceScanner.finish(nil,false,0);ck(c.cropDetector.sourceScanner.scans==[false],"cancel fences actual stale detector completion")}
  do {let c=started();c.reDetectCrop();CropAcceptPolicy.allow=false;c.cropDetector.sourceScanner.finish(nil,false,0);CropAcceptPolicy.allow=true;ck(c.cropDetector.sourceScanner.scans==[false,true],"policy early-return still completes indecisive continuation")}
  do {let c=Controller();c.install();c.reDetectCrop();ck(c.cropDetector.sourceScanner.scans==[true],"idle manual stays immediately fresh")}
  print("checks=\(checks) failures=\(failures)");if failures>0{exit(1)}
 }
}
Controller.runTests()
'''
full=preamble+detect+'\n'+controller+callback+post+helpers+redetect+'\n'+tests
(root/'Continuation.swift').write_text(full)
base=(fixture/'baseline.txt').read_text()
begin=base.index('        cropDetector.onResult = ')
finish=base.index('        cropDetector.onStatus = ',begin)
baseline=preamble+detect+'\n'+controller+base[begin:finish]+post+method(base,'    func reDetectCrop()')+'\n'+tests
variants={'baseline':baseline,'fixed':full,'removed-continuation':full.replace('defer {self.finishQueuedManualCrop(terminal:confidence>=0,decisive:decisive,usable:usableQueuedResult)}',''),'unfenced-token':full.replace('queued.epoch==cropMeasurementEpoch,queued.token==cropDetector.retryToken','queued.epoch==cropMeasurementEpoch'),'no-coalescing':full.replace('if !manualRedetectInFlight {','if true {'),'auto-labelled-manual':full.replace('queuedManualCrop=(currentFilePath','manualRedetectInFlight=true;queuedManualCrop=(currentFilePath')}
results=[]
for variant,body in variants.items():
 f=root/(variant+'.swift');f.write_text(body)
 for mode in ['-Onone','-O']:
  binary=root/(variant+mode)
  build=subprocess.run([swift,mode,str(f),'-o',str(binary)],capture_output=True,text=True)
  if build.returncode:print(build.stderr);raise SystemExit('compile failed '+variant)
  run=subprocess.run([str(binary)],capture_output=True,text=True)
  results.append({'variant':variant,'mode':mode,'exit':run.returncode,'output':run.stdout,'stderr':run.stderr})
  print(variant,mode,run.returncode,run.stdout.splitlines()[-1])
  if (variant=='fixed')!=(run.returncode==0):raise SystemExit('unexpected execution outcome')
(root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
