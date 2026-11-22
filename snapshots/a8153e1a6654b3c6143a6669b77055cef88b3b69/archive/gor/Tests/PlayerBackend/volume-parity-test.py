from pathlib import Path
import subprocess,json,os,resource
import tempfile
resource.setrlimit(resource.RLIMIT_CORE,(0,0));work=tempfile.TemporaryDirectory(prefix='volume-actual-');r=Path(work.name);source=Path(__file__).resolve().parents[2];swift=os.environ.get('SWIFTC','swiftc')
def method(s,k):
 a=s.index(k);b=s.index('{',a);i=b+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
hp='Sources/gor/Engine/GorAVPlayerHost.swift';pp='Sources/gor/Player/PPController.swift';sp='Packages/gorav/Sources/GorAVMacShell/AudioUnitSink.swift'
h=(source/hp).read_text();p=_pp_split().path(source,'PPController.swift').read_text();s=(source/sp).read_text()
pre='''import Foundation
@MainActor var checks=0
@MainActor var failures=0
@MainActor func check(_ v:Bool,_ label:String) {checks+=1;if !v {failures+=1;print("FAIL "+label)}}
enum EmbeddedEvent {case opened,firstFrame,paused,resumed,seekCommitted(seconds:Double),ended(reason:String),failed(String),audioUnbound,durationKnown(seconds:Double),timePos(seconds:Double,generation:Int),volumeChanged(Float)}
struct EngineObservedState {var idleActive:Bool?;var eofReached:Bool?;var paused:Bool?;var timePos:Double?;var duration:Double?}
@MainActor final class EngineObservationCenter {static let shared=EngineObservationCenter();func ingest(_ s:EngineObservedState) {}}
@MainActor final class Spine {func showMPVOSD(_ s:String,force:Bool) {}}
@MainActor final class TextField {var stringValue=""}
@MainActor final class Sidebar {var values:[Float]=[];func update(currentTime:Double,duration:Double,progress:Double,volume:Float) {values.append(volume)}}
@MainActor final class Chrome {
 var spineUI=Spine();var embeddedBackend=true;var volume:Float=1;var sidebarUI=Sidebar();var currentTime=0.0;var duration=0.0
 func currentProgress()->Double {0};func acceptEmbedded(_ s:EngineObservedState,source:URL?) {}
'''+method(p,'    func acceptEmbeddedVolume(')+'''\n}
@MainActor final class Session {var values:[Float]=[];var accepts=true;func setVolume(_ v:Float)->Bool {values.append(v);return accepts};func seek(toSeconds:Double) async throws {};func setPaused(_ p:Bool) async throws {};func setAudioDelay(seconds:Double) throws {};func setSubtitleDelay(_ d:Double,slot:Slot)->String? {nil};enum Slot {case primary}}
@MainActor final class Window {var level=0}
@MainActor final class HostWindow {var fullscreen=false;func setOnTop(_ b:Bool) {};func zoom(_ v:Double) {};func move(dx:Double,dy:Double) {};func hold(dx:Double,dy:Double,dz:Double) {};func resetPicture() {};func fit() {}}
extension Int {static var floating:Int {1}}
@MainActor final class AppDelegate {func launchMPV(file:String) {}}
@MainActor final class Application {var delegate:Any?;func terminate(_ x:Any?) {}}
@MainActor let NSApp=Application()
@MainActor final class Host {
 enum Refusal:Error {case unsupportedCapability(String)}
 var onPostOpenFailure:((String)->Void)?;let postOpenFallback=GorAVPostOpenFallback();var session:Session?;var volume:Float=1;var muted=false;var volumeSessionReady=false;var observed=EngineObservedState();var gateFailureCount=0;var gateTerminalCount=0;var status=TextField();var chrome:Chrome?=Chrome();var sourceURL:URL?;var onObservation:((EngineObservedState)->Void)?;var hostWindow:HostWindow?;var window:Window?;var gateControlTask:Task<Void,Never>?
 func applySubtitleVisible(_ v:Bool) {};func selectTextSubtitle(path:String,candidateIndex:Int?=nil) {};func cycleTextSubtitle(forward:Bool) {};func cycleAudioTrack(forward:Bool) {};var subtitleVisible=true
 func fail(_ e:Error) {gateFailureCount+=1};func togglePause() {};func setFullscreen(_ b:Bool) {};func closeSession() {volumeSessionReady=false}
'''
keys=['    private func consume(','    func handleChromeCommand(','    static func chromeSeekTarget(','    private func applyVolume(','    @objc private func toggleMute(']
body='\n'.join(method(h,k).replace('@objc ','').replace('private func','func') for k in keys)
prod=pre+body+'\n}\n'+(source/'Sources/gor/Engine/GorAVPostOpenFallback.swift').read_text()
tests='''import Foundation
@main struct Tests {@MainActor static func main() async {
 func cmd(_ h:Host,_ c:[Any]) {let b=try! JSONSerialization.data(withJSONObject:["command":c]);h.handleChromeCommand(String(data:b,encoding:.utf8)!)}
 let h=Host();let s=Session()
 cmd(h,["set_property","volume",23]);cmd(h,["add","volume",9]);check(h.gateFailureCount==0,"pre-session values queued without refusal");check(abs(h.volume-0.32)<0.001,"latest pre-session intent retained")
 h.session=s;cmd(h,["set_property","mute",true]);check(s.values.isEmpty,"unready sink not called");h.consume(.opened);check(s.values==[0],"mute applied once at opened");check(h.chrome?.volume==h.volume,"accepted desired volume acked")
 cmd(h,["set_property","mute",false]);check(abs(s.values.last!-0.32)<0.001,"unmute restores saved level")
 cmd(h,["cycle","mute"]);check(s.values.last==0,"cycle mute applies zero");cmd(h,["add","volume",5]);cmd(h,["cycle","mute"]);check(abs(s.values.last!-0.37)<0.001,"level edit while muted preserved")
 let n=s.values.count;cmd(h,["set_property","volume","nan"]);cmd(h,["set_property","volume","inf"]);check(s.values.count==n,"nonfinite volume rejected")
 let ack=h.chrome!.sidebarUI.values.count;s.accepts=false;cmd(h,["set_property","volume",48]);check(h.gateFailureCount==1,"live rejection reported");check(h.chrome!.sidebarUI.values.count==ack,"rejected sink not acknowledged")
 s.accepts=true;cmd(h,["set_property","volume",48]);check(abs(h.chrome!.volume-0.48)<0.001,"retry accepted and UI updated");let count=s.values.count
 h.consume(.ended(reason:"eof"));cmd(h,["set_property","volume",17]);check(s.values.count==count,"ended session not called");check(abs(h.volume-0.17)<0.001,"ended intent retained")
 h.volumeSessionReady=true;h.closeSession();cmd(h,["set_property","volume",19]);check(s.values.count==count,"close prevents sink mutation")
 let c=Chrome();c.embeddedBackend=false;c.acceptEmbeddedVolume(0.2);check(c.volume==1,"mpv UI unaffected");c.embeddedBackend=true;c.acceptEmbeddedVolume(.nan);c.acceptEmbeddedVolume(2);check(c.volume==1,"invalid acknowledgements refused")
 print("checks=\\(checks) failures=\\(failures)");if failures>0 {exit(1)}
}}
'''
variants={'fixed':prod,'baseline-volume':prod.replace(method(h,'    private func applyVolume(').replace('private func','func'),method((source/'Tests/PlayerBackend/volume-baseline'/'Sources/gor/GorAVBackend/GorAVPlayerHost.swift').read_text(),'    private func applyVolume(').replace('private func','func')),'no-open-flush':prod.replace('            applyVolume()',''),'unready-call':prod.replace('guard volumeSessionReady, let session else','guard let session else'),'wrong-mute-value':prod.replace('session.setVolume(muted ? 0 : volume)','session.setVolume(volume)'),'no-ui-ack':prod.replace('chrome?.acceptEmbeddedVolume(volume)',''),'ignore-live-refusal':prod.replace('guard session.setVolume(muted ? 0 : volume) else','guard session.setVolume(muted ? 0 : volume) || true else')}
rows=[]
for name,text in variants.items():
 d=r/'work'/name;d.mkdir(parents=True,exist_ok=True);(d/'Production.swift').write_text(text);(d/'Tests.swift').write_text(tests)
 for opt in ['-Onone','-O']:
  q=subprocess.run([swift,'-swift-version','5',opt,str(d/'Production.swift'),str(d/'Tests.swift'),'-o',str(d/'test')],capture_output=True,text=True);(d/(opt+'-compile.log')).write_text(q.stdout+q.stderr);assert q.returncode==0,q.stderr
  q=subprocess.run([str(d/'test')],capture_output=True,text=True);(d/(opt+'-run.log')).write_text(q.stdout+q.stderr);print(name,opt,q.returncode,q.stdout[-30:]);rows.append({'variant':name,'mode':opt,'exit':q.returncode,'output':q.stdout});assert (q.returncode==0)==(name=='fixed'),name
# Exact sink setVolume method with two distinct API recorders.
sinkpre='''import Foundation
var api="";var scopeSeen:UInt32=99;var valueSeen:Float = -1;var status:Int32=0
let noErr:Int32=0;let kHALOutputParam_Volume:UInt32=14;let kAudioUnitScope_Output:UInt32=2;let kAudioUnitScope_Global:UInt32=0
func AudioUnitSetProperty(_ u:Int,_ p:UInt32,_ s:UInt32,_ b:UInt32,_ v:UnsafeRawPointer,_ n:UInt32)->Int32 {api="property";scopeSeen=s;return status}
func AudioUnitSetParameter(_ u:Int,_ p:UInt32,_ s:UInt32,_ b:UInt32,_ v:Float,_ offset:UInt32)->Int32 {api="parameter";scopeSeen=s;valueSeen=v;return status}
enum State {case active,closed}
struct Lifecycle {var current:State = .active}
final class Sink {var stateLock=NSLock();var lifecycle=Lifecycle();var unit:Int?=1
'''
sinktests='''import Foundation
@main struct Tests {static func main() {var failures=0;func ck(_ b:Bool) {if !b {failures+=1}};let s=Sink();ck(s.setVolume(0.42));ck(api=="parameter");ck(scopeSeen==kAudioUnitScope_Global);ck(abs(valueSeen-0.42)<0.001);status = -1;ck(!s.setVolume(0.2));status=0;api="";ck(!s.setVolume(-1));ck(!s.setVolume(2));ck(!s.setVolume(.nan));ck(api.isEmpty);s.unit=nil;ck(!s.setVolume(0.2));s.unit=1;s.lifecycle.current = .closed;ck(!s.setVolume(0.2));print("sink checks=11 failures=\\(failures)");if failures>0 {exit(1)}}}
'''
for name,text in [('sink-fixed',s),('sink-baseline',(source/'Tests/PlayerBackend/volume-baseline'/sp).read_text()),('sink-wrong-scope',s.replace('kAudioUnitScope_Global, 0,','kAudioUnitScope_Output, 0,'))]:
 d=r/'work'/name;d.mkdir(parents=True,exist_ok=True);(d/'Production.swift').write_text(sinkpre+method(text,'    public func setVolume(').replace('public func','func')+'\n}\n');(d/'Tests.swift').write_text(sinktests)
 for opt in ['-Onone','-O']:
  q=subprocess.run([swift,opt,str(d/'Production.swift'),str(d/'Tests.swift'),'-o',str(d/'test')],capture_output=True,text=True);(d/(opt+'-compile.log')).write_text(q.stdout+q.stderr);assert q.returncode==0,q.stderr
  q=subprocess.run([str(d/'test')],capture_output=True,text=True);(d/(opt+'-run.log')).write_text(q.stdout+q.stderr);print(name,opt,q.returncode,q.stdout);rows.append({'variant':name,'mode':opt,'exit':q.returncode,'output':q.stdout});assert (q.returncode==0)==(name=='sink-fixed')
(r/'results.json').write_text(json.dumps({'scope':'exact extracted production host/PP ack/sink methods with recorder UI/session/AudioUnit API substitutes; not native audio acceptance','rows':rows},indent=2)+'\n')
