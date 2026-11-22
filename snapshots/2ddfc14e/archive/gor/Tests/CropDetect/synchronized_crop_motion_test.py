#!/usr/bin/env python3
"""Execute live crop transition methods with only window/IPC/clock/timer services doubled.
This is not native AppKit/Metal pixel acceptance.
"""
from pathlib import Path
import os, subprocess, tempfile, shutil
root=Path(__file__).resolve().parents[2]
pp=(root/'Sources/gor/Player/PPController.swift').read_text();cd=(root/'Sources/gor/Picture/CropDetector.swift').read_text()
def method(sig):
 a=pp.index(sig);return pp[a:pp.index('\n    }',a)+6].replace('private func','func')
clock=cd[cd.index('struct CropMotionClock {'):cd.index('\nfinal class CropDetector')]
methods='\n'.join(method(s) for s in ['    private func requestRealCrop(','    private func cancelCropMotion(','    func interruptCropMotion(','    private func cropWindowAspect(','    private func applyCropPresentation('])
methods=methods.replace('ProcessInfo.processInfo.systemUptime','TestTime.now').replace('Timer(','TestTimer(').replace('RunLoop.main','TestLoop.main')
head=r'''
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
typealias NSRect=CGRect
final class AppDelegate {var pictureInPictureActive=false;func refitPictureInPicture(aspect:Double){}}
enum NSApp {static var delegate:AnyObject?}
final class NSScreen {static let main:NSScreen?=NSScreen()}
final class Window {var frame=CGRect(x:0,y:0,width:800,height:450);var screen=NSScreen.main}
enum TestTime {static var now=0.0}
final class TestTimer {
 let body:(TestTimer)->Void;var valid=true
 init(timeInterval:Double,repeats:Bool,block:@escaping(TestTimer)->Void){body=block}
 func invalidate(){valid=false}
 func fire(){body(self)}
}
final class TestLoop {
 static let main=TestLoop();var timers:[TestTimer]=[]
 enum Mode {case common}
 func add(_ timer:TestTimer,forMode:Mode){timers.append(timer)}
}
enum GorOpeningFit {enum Mask {case borderless};static let mpvWindowMask=Mask.borderless;static func clampGeometry(frame:CGRect,screen:NSScreen,chromeStyleMask:Mask)->String?{"\(frame.minX),\(frame.minY),\(frame.width),\(frame.height)"}}
enum MPVCommand {static func make(_ items:[String])->String{items.joined(separator:"|")}}
enum CropInvariant {static func fits(x:Int,y:Int,w:Int,h:Int,srcW:Int,srcH:Int)->Bool{x>=0 && y>=0 && x+w<=srcW && y+h<=srcH}}
final class Detector {var sourcePixelWidth=1920,sourcePixelHeight=1080}
final class Spine {func showMPVOSD(_ text:String,force:Bool){}}
final class VR {var flatUIEyeAspect:Double?;func clearMeasuredEyeAspect(){}}
enum StereoMenuGeometry {
 struct Plan{}
 struct Viewport {let windowAspect:Double}
 static func plan(sourceAspect:Double,aspectOverride:Double?,cropAspect:Double?,gap:Double)->Plan?{Plan()}
 static func viewport(_ p:Plan,detected:CGRect?,menuOwns:Bool)->Viewport{Viewport(windowAspect:1.8)}
}
struct Gap {let value:Double}
final class CropIPCStub {
 let record:([String])->Void
 var offered:[([String],UInt64,Bool)]=[]
 init(_ record:@escaping([String])->Void){self.record=record}
 func resetCropPackets(_ generation:UInt64){}
 func sendCropPacket(_ lines:[String],generation:UInt64,final:Bool){offered.append((lines,generation,final));record(lines)}
}
final class PPController {
 static let fullSourceCrop=CGRect(x:0,y:0,width:1,height:1)
 static var gorFitScriptActive=true
 var currentFilePath="file-a";var cropRect:CGRect?
 var cropMotionTimer:TestTimer?;var cropMotionGeneration:UInt64=0;var cropMotionActive=false,cropMotionPlanning=false
 var cropGeometryOwnedUntil=0.0
 var cropMotionWindowTarget:CGRect?;var cropMotionTargetRect:CGRect?;var cropPresentationRect=fullSourceCrop
 var visualCropRect:CGRect?{cropMotionActive ? cropPresentationRect:cropRect}
 var window:Window?=Window();var embeddedBackend=false;var embeddedSourceCrop:((String,CGRect)->String?)?
 var embeddedCropWindow:((CGRect,Double,Bool)->Bool)?
 var menuCropOwnsSelection=false,vrModeEnabled=false,surfaceToolsEnabled=false,surfaceCropAwaitingDrawable=false,drawableAvailable=true
 var vr180Controller:VR?=VR();var stereoProjectionBaseAspect:Double?;var nativeVideoAspect:Double?=16.0/9
 var stereoManualAspect:Double?;var stereoMenuCropAspect:Double?;var manualMenuCropAspect:Double?
 var effectiveVrGap:Gap?;var videoLayoutRotation=0.0;let cropDetector=Detector();let spineUI=Spine()
 lazy var ipcClient=CropIPCStub { [weak self] in self?.commands.append(contentsOf:$0) }
 var sourceCropPropertyRequested=false;var commands:[String]=[];var surfaceSamples:[CGRect]=[];var stereoSamples:[CGRect]=[]
 var appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero;var bounds=CGRect.zero
 func refuseEmbedded(_ text:String)->Bool{true}
 func surfaceDrawableReceipt()->(Int,Int)?{drawableAvailable ? (800,450):nil}
 func refitWindowForCrop(aspect:Double?){if cropMotionPlanning{cropMotionWindowTarget=CGRect(x:100,y:100,width:800,height:400)}}
 func cancelFitAnimation(){}
 func ipcCommand(_ command:String){commands.append(command)}
 func applyVideoFrame(bounds:CGRect){}
 func refreshStereoMenuGeometry(force:Bool){stereoSamples.append(visualCropRect!)}
 func publishSurfaceWindowCrop(x:Double,y:Double,cx:Double,cy:Double)->Bool {
  surfaceSamples.append(CGRect(x:cx-x/2,y:cy-y/2,width:x,height:y));return drawableAvailable
 }
'''
cases=r'''
}
func close(_ a:CGFloat,_ b:CGFloat)->Bool{abs(a-b)<0.000001}
let full=PPController.fullSourceCrop,target=CGRect(x:0,y:0.1,width:1,height:0.8)
let native=PPController();native.embeddedBackend=true;var crops:[CGRect]=[];var windows:[CGRect]=[]
native.embeddedSourceCrop={source,rect in precondition(source=="file-a");crops.append(rect);return nil}
native.embeddedCropWindow={frame,aspect,done in windows.append(frame);return true}
native.cropRect=target;native.requestRealCrop(target);let first=native.cropMotionTimer!
precondition(crops.last==full && windows.last==native.window!.frame)
TestTime.now=0.21;first.fire();precondition(close(crops.last!.minY,0.05) && close(windows.last!.minX,50))
TestTime.now=0.42;first.fire();precondition(crops.last==target && windows.last==CGRect(x:100,y:100,width:800,height:400) && !native.cropMotionActive)
// Supersession starts at the currently displayed rect; a stale timer cannot cancel or advance its replacement.
TestTime.now=1;native.cropRect=full;native.requestRealCrop(full);let old=native.cropMotionTimer!
TestTime.now=1.21;old.fire();let midpoint=crops.last!
let next=CGRect(x:0.1,y:0,width:0.8,height:1);native.cropRect=next;native.requestRealCrop(next);let newer=native.cropMotionTimer!
precondition(crops.last==midpoint);old.fire();precondition(native.cropMotionTimer === newer && native.cropMotionActive)
TestTime.now=1.64;newer.fire();precondition(crops.last==next && !native.cropMotionActive)
// Path fence cancels future samples without applying to a replacement source.
TestTime.now=2;native.cropRect=full;native.requestRealCrop(full);let fenced=native.cropMotionTimer!,count=crops.count
native.currentFilePath="file-b";TestTime.now=2.21;fenced.fire();precondition(crops.count==count && !native.cropMotionActive)
// mpv: actual physical source crop and per-frame window geometry, no delayed animate endpoint.
let mpv=PPController();TestTime.now=3;mpv.cropRect=target;mpv.requestRealCrop(target)
TestTime.now=3.21;mpv.cropMotionTimer!.fire()
precondition(mpv.commands.contains(where:{$0=="set_property|video-crop|1920x972+0+54"}))
let parts=mpv.commands.last!.split(separator:"|");precondition(parts[2]=="crop-frame" && parts.last=="moving")
let values=parts[3].split(separator:",").map{Double($0)!}
precondition(zip(values,[50.0,50.0,800.0,425.0]).allSatisfy{abs($0-$1)<0.000001})
// Reset owns the menu but must still morph the physical crop instead of clearing it immediately.
mpv.menuCropOwnsSelection=true;mpv.cropRect=nil;mpv.requestRealCrop(full)
TestTime.now=3.42;mpv.cropMotionTimer!.fire()
precondition(mpv.commands.contains(where:{$0=="set_property|video-crop|1920x1026+0+27"}))
TestTime.now=3.64;mpv.cropMotionTimer!.fire();precondition(mpv.commands.contains("set_property|video-crop|"))
TestTime.now=3.8;mpv.cropRect=target;mpv.requestRealCrop(target);let cancelled=mpv.cropMotionTimer!
mpv.currentFilePath="file-b";TestTime.now=3.9;cancelled.fire()
precondition(mpv.commands.last=="script-message-to|gor_fit|cancel")
// VR/surface receive this sample, not the committed endpoint.
let vr=PPController();vr.vrModeEnabled=true;TestTime.now=4;vr.cropRect=target;vr.requestRealCrop(target)
TestTime.now=4.21;vr.cropMotionTimer!.fire();precondition(close(vr.stereoSamples.last!.minY,0.05))
let surface=PPController();surface.surfaceToolsEnabled=true;TestTime.now=5;surface.cropRect=target;surface.requestRealCrop(target)
TestTime.now=5.21;surface.cropMotionTimer!.fire();precondition(close(surface.surfaceSamples.last!.minY,0.05))
let held=PPController();held.surfaceToolsEnabled=true;held.drawableAvailable=false;held.cropRect=target;held.requestRealCrop(target)
precondition(held.cropMotionTimer==nil && held.surfaceCropAwaitingDrawable && held.cropRect==target)
// Timer service retention does not retain the controller. Native close can release it.
weak var weakHost:PPController?
do {let h=PPController();weakHost=h;TestTime.now=6;h.cropRect=target;h.requestRealCrop(target)}
precondition(weakHost==nil)
precondition(mpv.ipcClient.offered.contains{let lines=$0.0;return lines.count==2 && lines[0].hasPrefix("set_property|video-crop|") && lines[1].hasPrefix("script-message-to|gor_fit|crop-frame|")})
precondition(mpv.ipcClient.offered.contains{$0.2})
print("PASS actual shared-clock crop/window methods: native and mpv half/endpoints, supersession/stale timer, source fence, VR/surface sample, drawable deferral, lifetime")
'''
variants={'green':methods,
 'red-native-endpoint-jump':methods.replace('CropMotionClock.mix(from,rect,phase)','rect'),
 'red-independent-window-endpoint':methods.replace('CropMotionClock.mix(a,b,phase)','b'),
 'red-stale-timer-cancels-new':methods.replace('guard self.cropMotionGeneration==generation else{return}','guard self.cropMotionGeneration==generation else{self.cancelCropMotion();return}'),
 'red-cancel-keeps-lua-ownership':methods.replace('if cropMotionActive,!embeddedBackend,Self.gorFitScriptActive','if false'),
 'red-path-fence':methods.replace('guard self.currentFilePath==source else {self.cancelCropMotion();return}','').replace('guard host.cropMotionGeneration==generation,host.currentFilePath==source else{return}','guard host.cropMotionGeneration==generation else{return}')}
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-install/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as td:
 t=Path(td)
 for name,m in variants.items():
  p=t/'main.swift';p.write_text(head+clock+m+cases);out=t/name
  if name=='green':Path('/tmp/crop-motion-generated.swift').write_text(p.read_text())
  c=subprocess.run([swift,'-swift-version','5',str(p),'-o',str(out)],capture_output=True,text=True)
  assert c.returncode==0,(name,c.stderr)
  v=subprocess.run([str(out)],capture_output=True,text=True,timeout=5)
  if name=='green':assert v.returncode==0,v.stderr;print(v.stdout.strip())
  else:assert v.returncode!=0,'mutant survived: '+name;print('PASS runtime RED: '+name)

# Execute the actual pure production slot/counter, not a Python reimplementation.
ipc=(root/'Sources/gor/Engine/MPVCommand.swift').read_text()
a=ipc.index('struct IPCResponseCounter {')
b=ipc.index('// BEGIN relocated IPCClient',a)
transport=ipc[a:b]
transport_cases=r'''
func bytes(_ text:String)->Data{Data(text.utf8)}
let slot=LatestCropPacketSlot();slot.reset(1)
precondition(slot.offer("source-a\nwindow-a",generation:1,final:false))
for i in 0..<100 {precondition(!slot.offer("source-\(i)\nwindow-\(i)",generation:1,final:false))}
precondition(slot.take()!.payload=="source-99\nwindow-99")
// A blocked sender has at most one pending packet; final replaces intermediate and is sticky.
precondition(!slot.offer("source-final\nwindow-final",generation:1,final:true))
precondition(!slot.offer("late-intermediate",generation:1,final:false))
precondition(!slot.offer("duplicate-final",generation:1,final:true))
precondition(slot.finish() != nil);let final=slot.take()!
precondition(final.final && final.payload=="source-final\nwindow-final" && slot.current(final.generation))
precondition(slot.finish()==nil)
// Source/new-transition barrier cancels queued prior-generation state, including a pending final.
slot.reset(2);precondition(slot.offer("old-final",generation:2,final:true));slot.reset(3)
precondition(slot.take()==nil && !slot.current(2))
precondition(!slot.offer("stale",generation:2,final:true))
precondition(!slot.offer("new-final",generation:3,final:true));precondition(slot.finish() != nil)
precondition(slot.take()!.payload=="new-final");precondition(slot.finish()==nil)
// A worker scheduled before a discrete source/cancel barrier cannot consume the new generation.
slot.reset(4);precondition(slot.offer("old",generation:4,final:false));slot.reset(5)
precondition(!slot.offer("new-after-barrier",generation:5,final:true))
precondition(slot.take(scheduled:4)==nil)
precondition(slot.finish()==5)
precondition(slot.take(scheduled:5)!.payload=="new-after-barrier")
precondition(slot.finish()==nil)
var replies=IPCResponseCounter(expected:2)
precondition(!replies.consume(bytes("{\"event\":\"property-change\"}\n")))
precondition(!replies.consume(bytes("{\"event\":\"end-file\",\"error\":\"loading failed\"}\n")))
precondition(!replies.consume(bytes("{\"error\":\"success\",\"data\":1")))
precondition(!replies.consume(bytes("}\ninvalid\n")))
precondition(replies.count==1)
precondition(replies.consume(bytes("{\"error\":\"property unavailable\"}\n")))
precondition(replies.count==2) // Error responses also complete a command; not proof of applied crop.
var empty=IPCResponseCounter(expected:0);precondition(!empty.consume(bytes("{\"error\":\"success\"}\n")))
print("PASS actual production crop slot: 100-to-one, paired payload, sticky final, source barrier; batch reply counter: chunks/events/invalid/error/empty")
'''
mutants={
 'green':transport,
 'red-final-replaced':transport.replace('guard generation==next,!finalOffered','guard generation==next'),
 'red-stale-generation':transport.replace('guard generation==next,!finalOffered','guard !finalOffered'),
 'red-reset-keeps-pending':transport.replace('generation=next;pending=nil;finalOffered=false','generation=next;finalOffered=false'),
 'red-old-worker-crosses-barrier':transport.replace('if let scheduled, pending?.generation != scheduled {return nil}',''),
 'red-event-as-reply':transport.replace('object["event"] == nil, object["error"] is String','!object.isEmpty'),
 'red-error-event-as-reply':transport.replace('object["event"] == nil, ',''),
 'red-no-chunk-buffer':transport.replace('buffer.append(chunk)','buffer=chunk')}
with tempfile.TemporaryDirectory() as td:
 t=Path(td)
 for name,body in mutants.items():
  p=t/'main.swift';p.write_text('import Foundation\n'+body+transport_cases);out=t/name
  c=subprocess.run([swift,'-swift-version','5',str(p),'-o',str(out)],capture_output=True,text=True)
  assert c.returncode==0,(name,c.stderr)
  v=subprocess.run([str(out)],capture_output=True,text=True,timeout=5)
  if name=='green':assert v.returncode==0,v.stderr;print(v.stdout.strip())
  else:assert v.returncode!=0,'mutant survived: '+name;print('PASS transport runtime RED: '+name)


# Exercise the real IPCClient publication/drain methods on their actual serial queue.
# Only the socket peer is a recording double; no AppKit/window substitute is used here.
a=ipc.index('    private let cropPacketSlot=LatestCropPacketSlot()')
b=ipc.index('    // MARK: - Queries',a)
sender=ipc[a:b]
queue_head=r"""
import Foundation
final class IPCClient {
 static let cmdQueue=DispatchQueue(label:"crop.test.commands")
 let path="/tmp"
 static let sent=DispatchSemaphore(value:0)
 static var writes:[String]=[]
 static func socketRoundtrip(path:String,payload:String,timeout:TimeInterval)->[String] {
  writes.append(payload);sent.signal();return []
 }
"""
queue_case=r"""
}
let client=IPCClient(),blocked=DispatchSemaphore(value:0)
IPCClient.cmdQueue.async {blocked.wait()}
client.resetCropPackets(1)
client.sendCropPacket(["old-source","old-window"],generation:1,final:false)
IPCClient.cmdQueue.async {IPCClient.writes.append("load-barrier")}
client.resetCropPackets(2)
for i in 0..<100 {client.sendCropPacket(["source-\(i)","window-\(i)"],generation:2,final:false)}
client.sendCropPacket(["new-final-source","new-final-window"],generation:2,final:true)
blocked.signal()
precondition(IPCClient.sent.wait(timeout:.now()+2) == .success)
IPCClient.cmdQueue.sync {}
precondition(IPCClient.writes==["load-barrier","new-final-source\nnew-final-window\n"])
print("PASS actual IPCClient queue: blocked sender 100 samples coalesce to final pair after discrete source barrier")
"""
# Raw Python strings must still give Swift the intended interpolation/newline escapes.
queue_case=queue_case.replace('\\\\','\\')
for name,methods in {'green':sender,'red-wrong-scheduled-generation':sender.replace('take(scheduled:scheduled)','take()')}.items():
 with tempfile.TemporaryDirectory() as td:
  p=Path(td)/'main.swift';p.write_text('import Foundation\n'+transport+queue_head+methods+queue_case);out=Path(td)/'queue'
  c=subprocess.run([swift,'-swift-version','5',str(p),'-o',str(out)],capture_output=True,text=True)
  assert c.returncode==0,(name,c.stderr)
  v=subprocess.run([str(out)],capture_output=True,text=True,timeout=5)
  if name=='green':assert v.returncode==0,v.stderr;print(v.stdout.strip())
  else:assert v.returncode!=0,'queue mutant survived: '+name;print('PASS queue runtime RED: '+name)


# A real Darwin Unix socket peer keeps its write side open after both replies.
# Extract the production POSIX function verbatim, so an EOF-wait mutant must time out.
if os.uname().sysname=='Darwin':
 a=ipc.index('    static func socketRoundtrip(')
 b=ipc.index('    // ── Convenience:',a)
 roundtrip=ipc[a:b]
 socket_case=r"""
let path="/tmp/crop-"+String(UUID().uuidString.prefix(8))+".sock"
let server=socket(AF_UNIX,SOCK_STREAM,0);precondition(server>=0)
defer {Darwin.close(server);unlink(path)}
var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
path.withCString {src in withUnsafeMutablePointer(to:&address.sun_path) {$0.withMemoryRebound(to:CChar.self,capacity:104) {_=strncpy($0,src,103)}}}
let bound=withUnsafePointer(to:address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {Darwin.bind(server,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
precondition(bound==0 && listen(server,1)==0)
let release=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
DispatchQueue.global().async {
 let peer=accept(server,nil,nil);precondition(peer>=0)
 defer {Darwin.close(peer);done.signal()}
 var request=Data(),buffer=[UInt8](repeating:0,count:1024)
 while request.filter({$0==10}).count<2 {let n=Darwin.read(peer,&buffer,buffer.count);precondition(n>0);request.append(contentsOf:buffer.prefix(n))}
 let messages=["{\"event\":\"property-change\"}\n{\"error\":\"suc", "cess\",\"data\":1}\n{\"error\":\"success\",\"data\":2}\n"]
 for message in messages {message.utf8CString.withUnsafeBufferPointer {p in precondition(Darwin.write(peer,p.baseAddress!,p.count-1)==p.count-1)};Thread.sleep(forTimeInterval:0.01)}
 // Do not send EOF until the caller has returned. The old read-until-EOF path waits 1.5s.
 _=release.wait(timeout:.now()+4)
}
let began=ProcessInfo.processInfo.systemUptime
let result=IPCClient.socketRoundtrip(path:path,payload:"{\"command\":[\"get_property\",\"a\"]}\n{\"command\":[\"get_property\",\"b\"]}\n",timeout:1.5)
let elapsed=ProcessInfo.processInfo.systemUptime-began
release.signal();precondition(done.wait(timeout:.now()+2) == .success)
precondition(elapsed<1.0 && result.count==3)
print("PASS actual production socketRoundtrip returns after replies with peer open, elapsed=\(elapsed)")
"""
 # Normalize only the test string escaping, not extracted production code.
 socket_case=socket_case.replace('\\\\','\\')
 for name,method in {'green':roundtrip,'red-read-until-eof':roundtrip.replace('if responses.consume(chunk) {break}','_ = responses.consume(chunk)')}.items():
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'main.swift';p.write_text('import Foundation\nimport Darwin\n'+transport+'\nenum IPCClient {\n'+method+'\n}\n'+socket_case);out=Path(td)/'socket'
   c=subprocess.run([swift,'-swift-version','5',str(p),'-o',str(out)],capture_output=True,text=True)
   assert c.returncode==0,(name,c.stderr)
   v=subprocess.run([str(out)],capture_output=True,text=True,timeout=8)
   if name=='green':assert v.returncode==0,v.stderr;print(v.stdout.strip())
   else:assert v.returncode!=0,'socket mutant survived: '+name;print('PASS socket runtime RED: '+name)
else:
 print('Darwin socketRoundtrip execution NOT_RUN on this platform')
