import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,json,hashlib,resource,os
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
import tempfile
work=tempfile.TemporaryDirectory(prefix='postopen-actual-');r=Path(work.name);c=Path(__file__).resolve().parents[2];base=c/'Tests/PlayerBackend/postopen-baseline'
def method(s,key):
 a=s.index(key);b=s.index('{',a);i=b+1;depth=1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]
h=(c/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text();a=(c/'Sources/gor/App/AppDelegate.swift').read_text();policy=(c/'Sources/gor/Engine/GorAVPostOpenFallback.swift').read_text()
stubs='''import Foundation
@MainActor var checks=0
@MainActor var failures=0
@MainActor func check(_ b:Bool,_ msg:String) { checks += 1; if !b {failures += 1; print("FAIL: "+msg)} }
enum EmbeddedEvent {case opened,firstFrame,paused,resumed,seekCommitted(seconds:Double),ended(reason:String),failed(String),audioUnbound,durationKnown(seconds:Double),timePos(seconds:Double,generation:Int),volumeChanged(Float)}
struct EngineObservedState {var idleActive:Bool?;var eofReached:Bool?;var paused:Bool?;var timePos:Double?;var duration:Double?}
@MainActor final class EngineObservationCenter {static let shared=EngineObservationCenter();func ingest(_ s:EngineObservedState) {}}
@MainActor final class TextField {var stringValue=""}
@MainActor final class Spine {var hud:[String]=[];func showMPVOSD(_ s:String,force:Bool) {hud.append(s)}}
@MainActor final class Chrome {var spineUI=Spine();
 // SOURCE_GENERATED_CHROME_CALLBACKS
 var opens:[String]=[];func openMediaFileOnMPV(_ s:String) {opens.append(s)};func acceptEmbedded(_ s:EngineObservedState,source:URL?) {}}
@MainActor final class HostWindow {func close() {}}
struct EmbeddedCloseReport {var cleanShutdown=false}
enum Lifecycle {case opened,closing,closed}
@MainActor final class Session {
 var lifecycleState:Lifecycle = .opened;var fenceCount=0;var closeCount=0;var hold=false;var early=false
 func fence() {fenceCount+=1}
 func close() async -> EmbeddedCloseReport {closeCount+=1;lifecycleState = .closing;if early {Task {while hold {await Task.yield()};lifecycleState = .closed};return EmbeddedCloseReport(cleanShutdown:false)};while hold {await Task.yield()};lifecycleState = .closed;return EmbeddedCloseReport(cleanShutdown:true)}
}
enum PlayerEngine:String {case mpv,gorav;static let preferenceKey="GORFixtureEngine"}
struct PlayerRouteStatus {var requested:PlayerEngine;var active:PlayerEngine;var fallbackReason:String?}
@MainActor enum Diag {static func mediaRecord(_ s:String) {}}
// Recorder only for the logging call. Actual GorEngineRecord semantics are
// exercised by the separate source-extracted engine/session-record suite.
@MainActor enum GorEngineRecord {
 static var records:[String]=[]
 @discardableResult static func write(event:String,requested:String,active:String,origin:String?=nil,env:String?=nil,saved:String?=nil,menuOverride:String?=nil,fallback:String?=nil)->Bool {
 records.append(event+":"+requested+":"+active+":"+(fallback ?? "none"));return true
 }
}
@MainActor final class Proc {var isRunning=true}
'''
# Recorder callbacks are generated from the actual current source class.
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(c/'Tests/Predispatch'))
from predispatch import generated_slots
stubs=stubs.replace('// SOURCE_GENERATED_CHROME_CALLBACKS',generated_slots(_pp_split().path(c,'PPController.swift'),'PPController'))
hhead='''@MainActor final class GorAVPlayerHost {
 enum Refusal:Error {case unsupportedCapability(String)}
 static let candidate="fixture"
 var onPostOpenFailure:((String)->Void)?;let postOpenFallback=GorAVPostOpenFallback()
 var gateFailureCount=0;var gateTerminalCount=0;var observed=EngineObservedState();var status=TextField();var chrome:Chrome?=Chrome();var sourceURL:URL?;var onObservation:((EngineObservedState)->Void)?
 var volumeSessionReady=false;func applyVolume() {}
 var identity=UUID();var task:Task<Void,Never>?;var gateCloseTask:Task<Void,Never>?;var session:Session?=Session();var preparedPlayback:Int?;var hostWindow:HostWindow?=HostWindow();var gateCloseReport:EmbeddedCloseReport?
'''
he='\n'.join(method(h,k).replace('private func','func') for k in ['    private func consume(', '    func closeSession(', '    func drainForPostOpenFallback(', '    private func beginCloseSession(', '    private func fail('])
ahead='''@MainActor final class App {
 var overlayWin:AnyObject?;var isQuittingDeliberately=false;var engineOpenGeneration:UInt64=1;var goravHost:GorAVPlayerHost?;var activePlayerEngine:PlayerEngine = .gorav;var controller:Chrome?;var mpvProcess:Proc?;var engineRouteStatus=PlayerRouteStatus(requested:.gorav,active:.gorav,fallbackReason:nil);var ready=true;var launches=0
 func launchMPVImplementation(file:String?) {launches+=1;mpvProcess=Proc();if ready {controller=Chrome()}}
'''
ahead+='    private var engineSelectionOverride: PlayerEngine?\n'+method(a,'    var engineSelectionInputs:')+'\n'+method(a,'    var selectedEngineOrigin:')+'\n'
ae=method(a,'    private func fallbackAfterGorAVFailure(').replace('private func','func')
prod=stubs+policy+hhead+he+'\n}\n'+ahead+ae+'\n}\n'
tests='''import Foundation
@main struct Tests {
 @MainActor static func spin(_ n:Int=100) async { for _ in 0..<n {await Task.yield()} }
 @MainActor static func setup(_ replay:(()->Void)?=nil) -> (App,GorAVPlayerHost,Session) {
  let a=App(),h=GorAVPlayerHost();a.goravHost=h;a.controller=h.chrome
  h.onPostOpenFailure = { [weak a,weak h] reason in guard let a,let h else {return};a.fallbackAfterGorAVFailure(host:h,file:"film-A",generation:1,reason:reason,replay:replay) }
  return(a,h,h.session!)
 }
 @MainActor static func main() async {
  do {
   let (a,h,s)=setup();h.consume(.opened);h.consume(.timePos(seconds:23,generation:1));h.consume(.failed("pumpBroken"));h.consume(.failed("duplicate"));await spin()
   check(a.controller?.opens == ["film-A"],"actual failure opens same file once")
   check(s.fenceCount == 1 && s.closeCount == 1 && s.lifecycleState == .closed,"definitive close before replay")
   check(h.gateFailureCount == 1,"duplicate failure dedup")
   check(h.chrome?.spineUI.hud.count == 1,"named failure HUD once")
   check(h.chrome?.spineUI.hud.first?.contains("pumpBroken") == true,"actual reason preserved")
   check(a.engineRouteStatus.fallbackReason == "pumpBroken","route reason preserved")
   check(GorEngineRecord.records == ["switch:gorav:mpv:pump:pumpBroken"],"actual fallback emits bounded record call once")
   h.consume(.failed("later"));await spin();check(a.controller?.opens.count == 1,"no loop after fallback")
  }
  do {let(a,h,_)=setup();h.consume(.failed("preopen"));await spin();check(a.launches == 0,"no pre-open automatic replay")}
  do {let(a,h,_)=setup();h.consume(.opened);h.consume(.ended(reason:"eof"));await spin();check(a.launches == 0,"normal EOF not failure")}
  do {let(a,h,_)=setup();h.consume(.opened);h.consume(.audioUnbound);await spin();check(a.launches == 0,"audio warning not fatal replay");check(h.chrome?.spineUI.hud.count == 1,"audio warning stays visible")}
  do {let(a,h,_)=setup();h.consume(.opened);h.consume(.failed("race"));h.closeSession();await spin();check(a.launches == 0,"close before scheduled fallback cancels replay")}
  do {let(a,h,s)=setup();s.hold=true;h.consume(.opened);h.consume(.failed("race"));await spin();check(a.launches == 0,"no mpv during close await");h.closeSession();s.hold=false;await spin();check(a.launches == 0,"close during drain cancels replay")}
  do {let(a,h,s)=setup();s.hold=true;h.consume(.opened);h.consume(.failed("old"));await spin();a.engineOpenGeneration=2;a.goravHost=GorAVPlayerHost();s.hold=false;await spin();check(a.launches == 0,"newer open fences old fallback");check(a.goravHost !== h,"new host untouched")}
  do {let(a,h,_)=setup();h.consume(.opened);h.consume(.failed("old"));a.goravHost=GorAVPlayerHost();await spin();check(a.launches == 0,"wrong host rejected even same generation")}
  do {let(a,h,s)=setup();s.hold=true;h.consume(.opened);h.consume(.failed("quit"));await spin();a.isQuittingDeliberately=true;s.hold=false;await spin();check(a.launches == 0,"quit during teardown prevents restart")}
  do {var replayCount=0;let(a,h,_)=setup({replayCount+=1});h.consume(.opened);h.consume(.failed("remote"));await spin();check(replayCount == 1,"remote keeps original stream replay closure");check(a.controller?.opens.isEmpty == true,"remote never local stopTorrent load")}
  do {let(a,h,s)=setup();a.ready=false;h.consume(.opened);h.consume(.failed("readiness"));await spin();check(a.launches == 1 && s.lifecycleState == .closed,"launch only after close");a.engineOpenGeneration=2;a.controller=Chrome();try? await Task.sleep(nanoseconds:70_000_000);check(a.controller?.opens.isEmpty == true,"new open during readiness not replayed")}
  do {let(a,h,s)=setup();s.hold=true;h.consume(.opened);h.consume(.failed("earlyHUD"));check(h.chrome?.spineUI.hud.first?.contains("earlyHUD") == true,"feedback precedes teardown suspension");await spin();check(a.launches == 0,"close still pending after feedback");s.hold=false;await spin()}
  do {let p=GorAVPostOpenFallback();check(!p.claim("x"),"claim before open denied");p.opened();check(p.claim("x"),"opened permit claims");check(!p.claim("y"),"one claim");check(p.beginDrain(),"drain claim");check(!p.drained(definitivelyClosed:false),"unverified drain refuses");check(!p.consume(current:true),"unverified closure cannot replay")}
  print("checks=\\(checks) failures=\\(failures)");if failures>0 {exit(1)}
 }
}
'''
tests=tests.replace('.failed("', '.failed("pump:').replace('== "pumpBroken"','== "pump:pumpBroken"')
# Nonfatal source-cache and subtitle failures must not destroy active playback.
tests=tests.replace('  do {let p=GorAVPostOpenFallback();', '''  do {let(a,h,_)=setup();h.consume(.opened);h.consume(.failed("subtitleSidecar:noExactSidecar"));h.consume(.failed("sourceCacheCleanupFailed"));await spin();check(a.launches == 0,"nonterminal feature failures do not replace playback");check(h.chrome?.spineUI.hud.count == 2,"nonterminal reasons remain visible")}
  do {let(a,h,s)=setup();s.early=true;s.hold=true;h.consume(.opened);h.consume(.failed("pump:alreadyClosing"));await spin();check(a.launches == 0,"early alreadyClosed return is not teardown proof");s.hold=false;try? await Task.sleep(nanoseconds:40_000_000);await spin();check(a.controller?.opens == ["film-A"],"replay waits for real lifecycle closed")}
  do {let(a,h,s)=setup();var openingHeld=true;h.task=Task {while openingHeld {await Task.yield()}};h.consume(.opened);h.consume(.failed("pump:opening"));await spin();check(a.launches == 0 && s.closeCount == 0,"open task joined before close");openingHeld=false;await spin();check(a.controller?.opens == ["film-A"],"replay after open task and teardown join")}
  do {let p=GorAVPostOpenFallback();''')
variants={'fixed':prod,'baseline':prod.replace(he,he[:he.index('func consume(')]+method((base/'Sources/gor/GorAVBackend/GorAVPlayerHost.swift').read_text(),'    private func consume(').replace('private func','func')+'\n'+he[he.index('    func closeSession('):]),'no-generation-fence':prod.replace('self.engineOpenGeneration == generation','true'),'no-close-cancel':prod.replace('        postOpenFallback.cancel()',''),'duplicate-claim':prod.replace('guard phase == .opened, !reason.isEmpty else','guard phase != .waiting, !reason.isEmpty else'),'no-close-await':prod.replace('        await gateCloseTask?.value',''),'lost-reason':prod.replace('fallbackReason: String(reason.prefix(192))','fallbackReason: "generic"'),'no-terminal-filter':prod.replace('GorAVPostOpenFallback.isTerminal(reason), ',''),'early-close-proof':prod.replace('while await previous.lifecycleState != .closed, ContinuousClock.now < deadline','while false').replace('report.cleanShutdown = await previous.lifecycleState == .closed','report.cleanShutdown = true'),'remote-local-replay':prod.replace('if let replay { replay() } else { controller.openMediaFileOnMPV(file) }','controller.openMediaFileOnMPV(file)')}
rows=[]
for name,text in variants.items():
 if name not in ('fixed','baseline'):assert text!=prod,name
 d=r/'test-work'/name;d.mkdir(parents=True,exist_ok=True);(d/'Production.swift').write_text(text);(d/'Tests.swift').write_text(tests)
 for opt in ['-Onone','-O']:
  q=subprocess.run([os.environ.get('SWIFTC','swiftc'),'-swift-version','6','-strict-concurrency=complete',opt,str(d/'Production.swift'),str(d/'Tests.swift'),'-o',str(d/'test')],capture_output=True,text=True)
  (d/(opt+'-compile.log')).write_text(q.stdout+q.stderr)
  if q.returncode:raise RuntimeError(name+' '+q.stderr)
  q=subprocess.run([str(d/'test')],capture_output=True,text=True,timeout=15);(d/(opt+'-run.log')).write_text(q.stdout+q.stderr)
  rows.append({'variant':name,'mode':opt,'exit':q.returncode,'output':q.stdout});print(name,opt,q.returncode,q.stdout[-90:])
  if (q.returncode==0)!=(name=='fixed'):raise RuntimeError('unexpected '+name+q.stdout)
print('NOT_RUN full macOS app/live fallback/actual HUD pixels');(r/'results.json').write_text(json.dumps({'scope':'exact extracted production methods with recorder UI and controllable session close; no macOS/native/pixels claim','rows':rows},indent=2)+'\n')
