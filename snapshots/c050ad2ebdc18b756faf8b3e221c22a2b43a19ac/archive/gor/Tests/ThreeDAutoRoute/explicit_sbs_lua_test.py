"""Production Swift reducer/plan -> real Lua handlers, no modeled route decision."""
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
from pathlib import Path
import json,os,subprocess,tempfile
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(os.environ.get('GOR_ROOT',Path(__file__).resolve().parents[2]))
main='''import Foundation
for saved in [false,true] {
 for initialNative in [false,true] {
    let id=FilmID(rawValue:"owner-flat")
    var state=ThreeDState()
    if saved {var old=FilmThreeD();old.userTouched=true;old.output = .vr180;old.lastOutput = .vr180;state.films[id.rawValue]=old}
    state=ThreeDReducer.reduce(state,.open(id,ThreeDEvidence(metadata:ThreeDSource(initialNative ? .vr180SBS:.flat2D)))).0
    state=ThreeDReducer.reduce(state,.setOutput(.sbs)).0
    // In-session enable callback with stale in-memory lastOutput must honor
    // the fresh SBS action, not restore twoDVR180. No process reopen here.
    var film=state.current;film.lastOutput = .vr180;state.films[id.rawValue]=film
    state=ThreeDReducer.reduce(state,.setOutput(ThreeDPresentationPlan.restoredOutput(for:state))).0
    for evidence in [ThreeDSource(.sbsFull),ThreeDSource(.vr180SBS),ThreeDSource(.vr180TB)] {
        state=ThreeDReducer.reduce(state,.open(id,ThreeDEvidence(metadata:evidence))).0
        let plan=ThreeDPresentationPlan.make(state:state)
        let row:[String:Any]=["saved":saved,"initialNative":initialNative,"source":plan.luaKind,"output":plan.output.rawValue,"pack":plan.pack,"engine":plan.engine.rawValue]
        print(String(data:try! JSONSerialization.data(withJSONObject:row),encoding:.utf8)!)
    }
 }
}
'''
# Multi-step same-process flat-film route changes, with repeated metadata
# arriving between actions. Native evidence for SBS is covered above. Never rely on reopen to make the next action work.
main += r'''
let id=FilmID(rawValue:"in-session")
var session=ThreeDReducer.reduce(ThreeDState(),.open(id,ThreeDEvidence())).0
for output in [ThreeDOutput.off,.sbs,.vr180,.sbs,.off,.sbs,.vr180,.off,.sbs] {
    session=ThreeDReducer.reduce(session,.setOutput(output)).0
    session=ThreeDReducer.reduce(session,.open(id,ThreeDEvidence(metadata:ThreeDSource(.flat2D)))).0
    let plan=ThreeDPresentationPlan.make(state:session)
    let row:[String:Any]=["sequence":true,"output":plan.output.rawValue,"source":plan.luaKind,"pack":plan.pack,"engine":plan.engine.rawValue,"expected":output.rawValue]
    print(String(data:try! JSONSerialization.data(withJSONObject:row),encoding:.utf8)!)
}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'main.swift'),'-o',str(p/'plans')],check=True)
 rows=[json.loads(x) for x in subprocess.check_output([str(p/'plans')],text=True).splitlines() if x.startswith('{')]
ns={'__file__':str(root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py')}
text=Path(ns['__file__']).read_text().split('# Independent seeded',1)[0]
exec(compile(text,ns['__file__'],'exec'),ns)
sequence=ns['Replay']()
for row in rows:
 r=sequence if row.get('sequence') else ns['Replay']()
 r.msg('vr180-look-plan-lock','off')
 r.msg('vr180-look-set-projection',row['source'],16/9)
 r.msg('vr180-look-set-output','full_sbs' if row['engine']=='twoDVR180' else row['output']);r.msg('vr180-look-set-pack',row['pack'],1,.5,1,0)
 r.msg('vr180-look-set-enabled','false' if row['output']=='off' else 'true')
 v=r.values()
 if row.get('sequence'):
  assert row['output']==row['expected'],row
  assert row['pack']==(0 if row['output']=='off' else 3),row
  if row['output']!='off' or row['source'].startswith('flat-'):assert v.get('vr_pack')==(0 if row['output']=='off' else 3),(row,v)
  # Native shader uniforms may retain the prior pack while disabled. Off is plain playback, not a live shader verdict.
  assert r.g.props['user-data/vr180-look/enabled']==(row['output']!='off'),row
  print('PASS same-process action '+row['output']+' applied pack='+str(v.get('vr_pack')))
  continue
 if row['source'].startswith('vr180'):
  assert row['engine']=='flat_full_sbs' and row['pack']==3 and v['vr_source_layout'] in (1,2) and v['vr_pack']==3 and v['vr_flat_mono']==0,row
  print('PASS native source explicitSBS uses flatpackedeyes layout',v['vr_source_layout'])
 else:
  assert row['output']=='full_sbs' and row['engine']=='flat_full_sbs',row
  assert v.get('vr_source_layout') in (0,1,2) and v.get('vr_pack')==3,(row,v)
  print('PASS explicit SBS Swift->Lua saved=%s initiallyNative=%s layout=%s pack3' % (row['saved'],row['initialNative'],v['vr_source_layout']))

print('PASS all explicit SBS route scenarios through actual Swift plan and Lua')

pp=(_pp_split().path(root,'PPController_Features.swift')).read_text()
assert 'enabled ? ThreeDPresentationPlan.restoredOutput(for:store.snapshot):.off' in pp

# 191t T5: production applyThreeDState AND publishProjection, not a route model.
features=(_pp_split().path(root,'PPController_Features.swift')).read_text()
applier=features[features.index('    func applyThreeDState('):features.index('    /// Read-only receipt',features.index('    func applyThreeDState('))]
projection=features[features.index('    func publishProjection('):features.index('\n    func ',features.index('    func publishProjection(')+10)]
unlock=(root/'Sources/gor/Stereo/LookToolsRoute.swift').read_text().split('    func releaseProjectionLock()',1)[1].split('\n',1)[0]
sender=features[features.index('    func sendRaw(_ original: String)'):features.index('    var singleSwitchActive',features.index('    func sendRaw(_ original: String)'))]
stubs=r'''import Foundation
final class HeadTracker {static let shared=HeadTracker();var nativeMotionResponsive=false}
enum Diag {static func log(_ value:String) {};static func mediaRecord(_ value:String) {}}
enum GeomTrace {static func log(_ k:String,_ v:String) {};static func logChanged(_ k:String,_ v:String) {}}
enum ThreeDRecognitionBridge {static func filmID(path:String)->FilmID {FilmID(rawValue:"191t-applier")}}
enum ThreeDAutoRoute {
 static func previewParams(mode:String,strength:Double,screenDepthM:Double,screenDeg:Double,surround:String)->(gain:Double,conv:Double,zoom:Double,soft:Double) {(1,0,1,0)}
}
final class TestController {
 var recognitionIdentity="test",recognitionPath="public-fixture",projectionKey="",projectionKind="mono",latestProbeStatus="test"
 var routeRevision:UInt64=0,pendingRouteRevision:UInt64?;var droppedRouteKey="";var pendingRouteOutput:ThreeDOutput?
 var recognitionGeneration=0;var autoFitEntry=""
 var applyingStore=false,appliedThreeD:FilmThreeD?,appliedPlan:ThreeDPresentationPlan?,appliedEffects:ThreeDGlobalEffects?,appliedInternal:Bool?
 var latestWidth=320.0,latestHeight=180.0,vrModeEnabled=false,vrModeSetByAutoDetect=false,flatStereoFile=false,flatAutoEyeAspect=0.0
 static let ndcToMM=1.0
 var commands:[String]=[]
 func sendRaw(_ text:String) {commands.append(text)}
'''+ ' func releaseProjectionLock()'+unlock+r'''
 func setVRModeEnabled(_ value:Bool) {vrModeEnabled=value;sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-enabled\",\"\(value ? "true":"false")\"]}")}
 func setSwapEyes(_ value:Bool) {}
 func knownEyeAspect(kind:String,filename:String,width:Double,height:Double)->Double {16/9}
 func simulatePoseIfRequested() {}
 func setHeadTrackingEnabled(_ value:Bool,remember:Bool) {}
 func setBlinkControlEnabled(_ value:Bool,osd:Bool,remember:Bool)->Bool {
  sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-tools-active\",\"\(value ? "true":"false")\"]}");return value
 }
 func publishBaseIPD(_ value:Double,persist:Bool) {}
 func resetFilmView(smooth:Bool=false) {};func recenterHeadTracking() {}
 func publishThreeDAppliedState(plan:ThreeDPresentationPlan) {}
'''
scenario=r'''
let suite="191t-applier-"+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
MainActor.assumeIsolated {
 let store=ThreeDStore(defaults:defaults),controller=TestController()
 store.subscribe(ownerID:"191t") {state,effects in controller.applyThreeDState(state,effects,revision:store.revision)}
 store.dispatch(.open(FilmID(rawValue:"191t-applier"),ThreeDEvidence()))
 controller.commands=[]
 store.dispatch(.setOutput(.sbs));store.dispatch(.setOutput(.sbs))
 let output=controller.commands.filter {$0.contains("vr180-look-set-output")}
 let projection=controller.commands.filter {$0.contains("vr180-look-set-projection")}
 precondition(output.count == 2 && projection.count == 2,"same output must resend output and projection twice")
 for command in controller.commands {print(command)}
 controller.commands=[]
 for (key,value) in [(ThreeDEffectKey.ipd,ThreeDEffectValue.number(2)),(.screenDepth,.number(1.8)),(.screenSize,.number(80)),(.strength,.number(1.5))] {store.dispatch(.setEffect(key,value))}
 let effectCommands=controller.commands
 precondition(!effectCommands.contains{$0.contains("vr180-look-set-enabled") && $0.contains("false")},"effect reapply passed through Off")
 precondition(!effectCommands.contains{$0.contains("vr180-look-set-output") || $0.contains("vr180-look-set-projection") || $0.contains("loadfile")},"live parameter change rebuilt the route/media")
 print("EFFECT_BEGIN")
 for command in effectCommands {print(command)}
 print("EFFECT_END")
 controller.commands=[];store.dispatch(.setOutput(.off))
 precondition(controller.commands.contains{$0.contains("vr180-look-set-enabled") && $0.contains("false")},"actual Off cleanup lost")
 controller.commands=[];store.dispatch(.setEffect(.head,.bool(true)))
 precondition(!controller.commands.contains{$0.contains("vr180-look-set-enabled") && $0.contains("false")},"plain2D head effect passed through outputOff cleanup")
 controller.commands=[];store.dispatch(.setEffect(.screenSize,.number(81)))
 precondition(!controller.commands.contains{$0.contains("vr180-look-set-enabled") && $0.contains("false")},"plain2D same-route effect wiped active tools")
 controller.commands=[];store.dispatch(.setOutput(.off))
 precondition(controller.commands.contains{$0.contains("vr180-look-set-enabled") && $0.contains("false")},"repeated explicitOff lost cleanup")
 store.dispatch(.open(FilmID(rawValue:"191t-applier"),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
 store.dispatch(.setOutput(.vr180))
 controller.commands=[];store.dispatch(.setOutput(.off))
 print("OFF_BEGIN")
 for command in controller.commands {print(command)}
 print("OFF_END")
 print("PASS plain2D independent head/effect actions preserve tools, repeated explicitOff still cleans")
 print("PASS 191t T5 repeated SBS sent output twice and projection twice through actual applier and projection sender")
}
defaults.removePersistentDomain(forName:suite)
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Controller.swift').write_text(stubs.replace(' func sendRaw(_ text:String) {commands.append(text)}',' func ipcCommand(_ text:String) {commands.append(text)}\n'+sender)+applier+projection+'}\n');(p/'main.swift').write_text('import Foundation\n'+scenario)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'applier')],check=True)
 output=subprocess.check_output([str(p/'applier')],text=True)
 sent=[];effectSent=[];offSent=[];inEffect=False;inOff=False
 for line in output.splitlines():
  if line=="OFF_BEGIN":inOff=True;continue
  if line=="OFF_END":inOff=False;continue
  if line=="EFFECT_BEGIN":inEffect=True;continue
  if line=="EFFECT_END":inEffect=False;continue
  if line.startswith('{'):
   command=json.loads(line)['command']
   if not inOff:sent.append(command)
   if inEffect:effectSent.append(command)
   if inOff:offSent.append(command)
  elif line.startswith('PASS'):print(line)
 # Replay only actual script-message-to bytes captured from the production sender.
 replay=ns['Replay']()
 for command in sent:
  if command[:2]==['script-message-to','vr180_look']:
   replay.msg(command[2],*command[3:])
 assert replay.values().get('vr_source_layout')==0 and replay.values().get('vr_pack')==3
 print('PASS 191t T5 actual resends replay through Lua as flat source pack3')
 replay.msg('vr180-look-set-orientation',.1,-.2,120,.3,.012,.01,-.02,0,'none','fov-unavailable',0,.4,.4)
 initial=replay.values()
 for command in effectSent:
  if command[:2]==['script-message-to','vr180_look']:replay.msg(command[2],*command[3:])
 after=replay.values()
 for key in ['vr_fov','vr_roll','vr_head_roll','vr_head_x','vr_head_y','vr_head_z','vr_ipd_nudge']:assert after[key]==initial[key],key
 print('PASS actual compiled applier4effect changes -> exact Lua bytes preserve tracked pose; explicit same-output recovery and actualOff retained')

# Replay native->Off actual callback order: persisted blinkON sends toolsON after initial cleanup.
native=ns['Replay']();native.msg('vr180-look-set-projection','vr180',1);native.msg('vr180-look-set-output','vr180');native.msg('vr180-look-set-enabled','true')
for command in offSent:
 if command[:2]==['script-message-to','vr180_look']:native.msg(command[2],*command[3:])
assert any(c[2:4]==['vr180-look-tools-active','true'] for c in offSent if c[:2]==['script-message-to','vr180_look']),'fixture omitted persistedblink callback'
assert native.g.props['user-data/vr180-look/enabled'] is False
assert len(native.g.props['glsl-shaders'])==0,'nativeOff reinstalled look shader via persistedblink callback'
native.msg('vr180-look-tools-active','true');native.msg('vr180-look-set-orientation',0,0,135,.2,0,0,0,0)
assert native.values()['vr_plain']==1 and len(native.g.props['glsl-shaders'])==1,'explicit independent tools afterOff must still work'
print('PASS192y actual compiled nativeOff callback sequence leaves zero look shaders; subsequent explicit2D tools still work')

# A fresh false -> false request must still publish its read-only state receipt.
fresh=ns['LuaRuntime'](unpack_returned_tuples=True);fresh.execute(ns['mock'])
fresh.execute((root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
g=fresh.globals();g.handlers['vr180-look-store-revision']('0','flat-2d3d','store-applier');g.handlers['vr180-look-set-enabled']('false','0','store-applier')
assert g.props['user-data/vr180-look/enabled'] is False,'initial Off must publish false, not property-not-found'
print('PASS fresh Lua explicit Off publishes enabled=false even when state was already false')

#193a real filename/packing recognition -> persisted Film-is restore -> native Lua.
bridge=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRecognitionBridge.swift'+' '):_b.index('// END relocated '+'ThreeDRecognitionBridge.swift'+'\n')])((_threed_split().path(root)).read_text())
recognition=bridge[bridge.index('    static func source('):bridge.index('    static func internalMedia(')]
routeCases=r'''import Foundation
let id=FilmID(rawValue:"193a-film")
for prior in [ThreeDSource.Format.flat2D,.sbsFull,.vr180SBS] {
 for (filename,projection,expected) in [("movie.VR180.SBS.mp4","flat-sbs",ThreeDSource.Format.vr180SBS),("movie.VR180.OU.mp4","flat-tb",.vr180TB),("movie.SBS.mp4","flat-sbs",.sbsFull)] {
  let source=ThreeDRecognitionBridge.source(projection:projection,sbs:true,tb:projection == "flat-tb",filename:filename)!
  precondition(source.format == expected,"filename sphere lost to generic packing")
  var saved=FilmThreeD();saved.source=ThreeDSource(prior);saved.userSource=true;saved.userTouched=true;saved.output = .sbs;saved.lastOutput = .sbs;saved.explicitOutput = .sbs
  var state=ThreeDState();state.films[id.rawValue]=saved
  state=ThreeDReducer.reduce(state,.open(id,ThreeDEvidence(metadata:source,filenameTag:ThreeDRecognitionBridge.filename(filename)))).0
  precondition(state.current.source.format == expected,"persisted Film-is masked fresh detected source")
  let p=ThreeDPresentationPlan.make(state:state)
  precondition(p.engine == .flat(.sbs))
  print(String(data:try! JSONSerialization.data(withJSONObject:["source":p.luaKind,"output":p.output.rawValue,"pack":p.pack,"native":expected != .sbsFull]),encoding:.utf8)!)
  state=ThreeDReducer.reduce(state,.setOutput(.off)).0
  state=ThreeDReducer.reduce(state,.toggle3D).0
  precondition(ThreeDPresentationPlan.make(state:state).engine == p.engine)
  // Fresh deliberate Film-is choice still works, and metadata refresh cannot undo it.
  state=ThreeDReducer.reduce(state,.setSource(ThreeDSource(.flat2D))).0
  state=ThreeDReducer.reduce(state,.open(id,ThreeDEvidence(metadata:source))).0
  precondition(state.current.source.format == .flat2D)
  let next=FilmID(rawValue:"other-film")
  state=ThreeDReducer.reduce(state,.open(next,ThreeDEvidence(metadata:ThreeDSource(.sbsFull)))).0
  state=ThreeDReducer.reduce(state,.open(id,ThreeDEvidence(metadata:source))).0
  precondition(state.current.source.format == expected,"old session source leaked into reopened film")
 }
}
precondition(ThreeDRecognitionBridge.source(projection:"vr360-mono",sbs:true,tb:false,filename:"movie.VR180.SBS.mp4")!.format == .vr360Mono)
precondition(ThreeDRecognitionBridge.source(projection:"unsupported",sbs:true,tb:false,filename:"movie.VR180.SBS.mp4") == nil)
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Bridge.swift').write_text('import Foundation\nenum ThreeDRecognitionBridge {\n'+recognition+'}\n');(p/'main.swift').write_text(routeCases)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Bridge.swift'),str(p/'main.swift'),'-o',str(p/'routes')],check=True)
 routes=[json.loads(x) for x in subprocess.check_output([str(p/'routes')],text=True).splitlines() if x.startswith('{')]
for route in routes:
 r=ns['Replay']();r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-set-projection',route['source'],0);r.msg('vr180-look-set-output',route['output']);r.msg('vr180-look-set-enabled','true');r.msg('vr180-look-set-pack',route['pack'],1,.5,1,0)
 values=r.values()
 assert values['vr_source_layout']==({'flat-tb':2,'flat-sbs':1}[route['source']]),route
 assert values['vr_pack']==3,route
 assert values['vr_flat_mono']==0,route
 assert values['vr_flat_sbs']==1,route
print('PASS193h recognition retainsnativeSOURCE, explicitSBSusesflatSBS/TBeyespack3; livechoicesretained')

#193b actual production applier + actual plannedLook values, sequential revisions.
sequence=r'''import Foundation
let suite="193b-sequence-"+UUID().uuidString, id=FilmID(rawValue:"191t-applier")
MainActor.assumeIsolated {
 let store=ThreeDStore(defaults:UserDefaults(suiteName:suite)!),controller=TestController()
 store.subscribe(ownerID:"193b") {state,effects in controller.applyThreeDState(state,effects,revision:store.revision)}
 @MainActor func phase(_ name:String,_ action:ThreeDAction) {
  controller.commands=[];store.dispatch(action)
  print(String(data:try! JSONSerialization.data(withJSONObject:["phase":name,"revision":store.revision,"commands":controller.commands]),encoding:.utf8)!)
 }
 phase("open",.open(id,ThreeDEvidence(metadata:ThreeDSource(.flat2D))))
 phase("sbs",.setOutput(.sbs))
 let stale=RenderedShotMPV.plannedLook(plan:RenderedShotPlan.make(eyeN:256,decoders:["hevc"],output:.vr180)!)
 phase("stale-render",.generated(id,stale.source,stale.output,aspect:stale.aspect))
 let plan=RenderedShotPlan.make(eyeN:256,decoders:["hevc"],output:.fullSBS,srcW:320,srcH:180)!
 let look=RenderedShotMPV.plannedLook(plan:plan)
 precondition(look.source.format == .sbsFull && look.output == .sbs)
 phase("rendered-load",.generated(id,look.source,look.output,aspect:look.aspect))
 phase("off",.setOutput(.off))
 phase("sbs-again",.setOutput(.sbs))
 phase("reopen",.open(id,ThreeDEvidence(metadata:ThreeDSource(.flat2D))))
}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Controller.swift').write_text(stubs.replace(' func sendRaw(_ text:String) {commands.append(text)}',' func ipcCommand(_ text:String) {commands.append(text)}\n'+sender)+applier+projection+'}\n');(p/'main.swift').write_text(sequence)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),*[str(root/'Sources/gor'/x) for x in ['ThreeDState.swift','OutputModes.swift','RenderedShotPlan.swift','RenderedShotMPV.swift']],str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'sequence')],check=True)
 rows=[json.loads(x) for x in subprocess.check_output([str(p/'sequence')],text=True).splitlines() if x.startswith('{')]
r=ns['Replay']();logs=[];sequence_pixels=[]
r.g.mp.msg.warn=lambda line:logs.append(str(line));r.g.mp.msg.info=lambda line:logs.append(str(line))
for row in rows:
 for encoded in row['commands']:
  c=json.loads(encoded)['command']
  if len(c)>2 and c[2] in ('vr180-look-set-projection','vr180-look-set-output','vr180-look-set-pack','vr180-look-set-enabled','vr180-look-plan-lock'):
   assert c[-2:]==[str(row['revision']),'store-applier'],(row,c)
  if c[:2]==['script-message-to','vr180_look']:r.g.handlers[c[2]](*map(str,c[3:]))
 actual=json.loads(r.g.props['user-data/vr180-look/applied-state'])
 assert actual['source_layout']<3,(row,actual)
 assert actual['revision']==row['revision'] and actual['completed_revision']==row['revision'],('193d missing completed route barrier',row,actual)
 if row['phase'] not in ('open','off'):
  v=r.values();assert v['vr_flat_mono']==(0 if row['phase']=='rendered-load' else 1),(row,v)
  assert v['vr_pack']==3 and actual['enabled']
  if row['phase']=='rendered-load':assert abs(v['vr_eye_aspect']-320/180)<1e-6,'prepared full eye aspect lost in singlewriter transfer'
 if row['phase'] not in ('open','off'):
  installed=r.g.props['glsl-shaders'];shader=Path(installed[len(installed)]).read_text()
  sequence_pixels.append((row['phase'],dict(r.values()),shader))
 else:
  assert len(r.g.props['glsl-shaders'])==0,'Off retained look shader'
  sequence_pixels.append((row['phase'],dict(r.values()),None))
 before=dict(r.values());receipt=r.g.props['user-data/vr180-look/applied-state']
 for attack in [('vr180-look-set-projection',['vr180','0']),('vr180-look-set-projection',['vr180','0',str(row['revision']-1),'old-store']),('vr180-look-set-projection',['vr180','0',str(row['revision']),'store-applier']),('vr180-look-set-pack',['4','1','.5','1','0'])]:
  for repeat in range(2):r.g.handlers[attack[0]](*attack[1])
 assert r.g.props['user-data/vr180-look/applied-state']==receipt,'foreign/stale message changed current flat route'
 assert r.values()==before
 print('PASS193b actual sequence',row['phase'],'revision',row['revision'],'layout',actual['source_layout'],'enabled',actual['enabled'])
assert any('3D-REJECTED' in line and 'sender=old-store' in line for line in logs)
assert any('3D-LUA' in line and 'revision=' in line for line in logs)
rejections=[x for x in logs if '3D-REJECTED' in x]
assert len(rejections)==len(set(rejections)),'identical rejected message logged twice'
print('PASS193b stale/unversioned/wrong-kind route messages rejected without state changes; accepted resulting state logged')

#193e crossfile boundaries execute the production unlock, not an empty stub.
# Names below are public/synthetic fixture names, never attributed to owner files.
crossfile_main=r'''import Foundation
MainActor.assumeIsolated {
 let store=ThreeDStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),c=TestController()
 store.subscribe(ownerID:"crossfile") {state,effects in c.applyThreeDState(state,effects,revision:store.revision)}
 @MainActor func phase(_ name:String,_ action:ThreeDAction) {
  c.commands=[];store.dispatch(action)
  print(String(data:try! JSONSerialization.data(withJSONObject:["phase":name,"commands":c.commands]),encoding:.utf8)!)
 }
 c.recognitionPath="/synthetic/Native.VR180.SBS.mp4"
 phase("native-open",.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
 phase("native-on",.setOutput(.vr180))
 c.recognitionPath="/synthetic/Ordinary.2D.mp4";c.appliedThreeD=nil;c.appliedPlan=nil;c.appliedEffects=nil
 phase("new-2D-open",.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:ThreeDSource(.flat2D))))
 phase("2D-to-3D",.setOutput(ThreeDPresentationPlan.restoredOutput(for:store.snapshot)))
 phase("SBS",.setOutput(.sbs))
 phase("Off",.setOutput(.off))
}
'''
crossfile_stubs=stubs.replace('FilmID(rawValue:"191t-applier")','FilmID(rawValue:path)').replace(' func sendRaw(_ text:String) {commands.append(text)}',' func ipcCommand(_ text:String) {commands.append(text)}\n'+sender)
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Controller.swift').write_text(crossfile_stubs+applier+projection+'}\n');(p/'main.swift').write_text(crossfile_main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'crossfile')],check=True)
 crossfile_rows=[json.loads(x) for x in subprocess.check_output([str(p/'crossfile')],text=True).splitlines() if x.startswith('{')]
for runtime in ['lupa.luajit21','lupa.lua51','lupa.lua54']:
 from importlib import import_module
 l=import_module(runtime).LuaRuntime(unpack_returned_tuples=True);l.execute(ns['mock']);g=l.globals();g.props['config-dir']=tempfile.mkdtemp(prefix='193e-crossfile-');g.props['osd-width']=960;g.props['osd-height']=600;l.execute((root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
 for row in crossfile_rows:
  for encoded in row['commands']:
   c=json.loads(encoded)['command']
   if c[:2]==['script-message-to','vr180_look']:g.handlers[c[2]](*map(str,c[3:]))
  receipt=json.loads(g.props['user-data/vr180-look/applied-state'])
  if row['phase'] in ('2D-to-3D','SBS'):assert receipt['source_layout']==0 and receipt['flat_pack']==3 and receipt['enabled'],receipt
  if row['phase'] in ('new-2D-open','Off'):assert not receipt['enabled'] and len(g.props['glsl-shaders'])==0,receipt
  assert receipt['completed_revision']==receipt['revision']
 print('PASS193e productionunlock/appliernative→different2D→2D3D→SBS→Off',runtime)

# Negative control is the exact shipped193dscript; native cleanup must reproduce
# the old fatal assertion before changing the guard, with the production unlock.
from lupa.luajit21 import LuaRuntime as LuaJIT193e
old=subprocess.check_output(['git','show','7d2f306:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
l=LuaJIT193e(unpack_returned_tuples=True);l.execute(ns['mock']);g=l.globals();g.props['config-dir']=tempfile.mkdtemp(prefix='193e-negative-');l.execute(old)
try:
 for row in crossfile_rows:
  for encoded in row['commands']:
   c=json.loads(encoded)['command']
   if c[:2]==['script-message-to','vr180_look'] and g.handlers[c[2]] is not None:g.handlers[c[2]](*map(str,c[3:]))
 raise AssertionError('193dnegativecontrol did not reproduce')
except Exception as error:
 assert row['phase']=='new-2D-open' and 'flat store kind crossed native engine' in str(error),str(error)
 print('PASS193e negativecontrol193dactualproductionunlockfailsnative→2DbeforeOff/projection')

#193f delayed identity: Off bypasses the guard; pending SBS reapplies on bind.
# Execute actual production applier with real 2s delay, no modeled route methods.
delayed_main=r'''import Foundation
MainActor.assumeIsolated {
 let store=ThreeDStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),c=TestController()
 c.recognitionPath="/synthetic/Native.VR180.SBS.mp4"
 store.subscribe(ownerID:"delayed") {state,effects in c.applyThreeDState(state,effects,revision:store.revision)}
 @MainActor func phase(_ name:String,_ action:ThreeDAction) {
  c.commands=[];store.dispatch(action)
  print(String(data:try! JSONSerialization.data(withJSONObject:["phase":name,"commands":c.commands]),encoding:.utf8)!)
 }
 phase("native",.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
 c.recognitionPath="/synthetic/Ordinary.2D.mp4";c.recognitionIdentity=""
 phase("unbound-open",.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:ThreeDSource(.flat2D))))
 phase("unbound-SBS",.setOutput(.sbs))
 phase("unbound-Off",.setOutput(.off))
 phase("unbound-2D3D",.setOutput(.sbs))
 precondition(c.pendingRouteRevision==store.revision && c.pendingRouteOutput == .sbs)
 Thread.sleep(forTimeInterval:2)
 c.recognitionIdentity="bound";c.commands=[]
 c.applyThreeDState(store.snapshot,[.reapply],revision:store.revision)
 precondition(c.pendingRouteRevision==nil)
 print(String(data:try! JSONSerialization.data(withJSONObject:["phase":"bound-2D3D","commands":c.commands]),encoding:.utf8)!)
 phase("Off",.setOutput(.off))
 c.recognitionPath="/synthetic/Native2.VR180.SBS.mp4"
 phase("native2",.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
}
'''
delayed_stubs=crossfile_stubs.replace('static func mediaRecord(_ value:String) {}','static func mediaRecord(_ value:String) {if value.hasPrefix("3D-DROPPED") {print(value)}}')
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Controller.swift').write_text(delayed_stubs+applier+projection+'}\n');(p/'main.swift').write_text(delayed_main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'delayed')],check=True)
 text=subprocess.check_output([str(p/'delayed')],text=True)
 assert text.count('3D-DROPPED reason=identityEmpty')==1,text
 delayed_rows=[json.loads(x) for x in text.splitlines() if x.startswith('{')]
replay=ns['Replay']()
for row in delayed_rows:
 if row['phase']=='unbound-open':
  replay.g.props['path']='/synthetic/Ordinary.2D.mp4';replay.g.events['start-file']()
  receipt=json.loads(replay.g.props['user-data/vr180-look/applied-state'])
  assert not receipt['enabled'] and receipt['source_layout']==0 and len(replay.g.props['glsl-shaders'])==0
 for encoded in row['commands']:
  c=json.loads(encoded)['command']
  if c[:2]==['script-message-to','vr180_look']:replay.g.handlers[c[2]](*map(str,c[3:]))
 receipt=json.loads(replay.g.props['user-data/vr180-look/applied-state'])
 if row['phase'] in ('unbound-open','unbound-SBS','unbound-Off','unbound-2D3D','Off'):assert not receipt['enabled'] and receipt['source_layout']==0,receipt
 if row['phase']=='bound-2D3D':assert receipt['enabled'] and receipt['source_layout']==0 and receipt['flat_pack']==3,receipt
 if row['phase']=='native2':assert receipt['enabled'] and receipt['source_layout']==3 and receipt['flat_pack']==0,receipt
 print('PASS193f delayedrecognition',row['phase'],receipt['source_layout'],receipt['enabled'])

# Execute the production recognition handoff tail with an OLD store identity,
# so a click before new params does not disappear when .open creates the new film.
a=features.index('        MainActor.assumeIsolated {\n            let store=ThreeDStore.shared',features.index('let pendingChoice=pendingRouteOutput'))
b=features.index('\n\n    }',a)
bind_tail=features[a:b]
binding_main=r'''import Foundation
MainActor.assumeIsolated {
 let store=ThreeDStore.shared,c=TestController()
 c.recognitionPath="/synthetic/old.VR180.mp4"
 store.subscribe(ownerID:"binding") {state,effects in c.applyThreeDState(state,effects,revision:store.revision)}
 store.dispatch(.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
 c.recognitionPath="";c.recognitionIdentity=""
 store.dispatch(.setOutput(.off));store.dispatch(.setOutput(.sbs))
 precondition(c.pendingRouteOutput == .sbs)
 c.recognitionPath="/synthetic/new.2D.mp4";c.recognitionIdentity="bound"
 c.bind(ThreeDEvidence(metadata:ThreeDSource(.flat2D)))
 precondition(store.snapshot.currentFilm == FilmID(rawValue:c.recognitionPath))
 precondition(store.snapshot.current.source.format == .flat2D && store.snapshot.current.output == .sbs)
 precondition(c.pendingRouteOutput==nil && c.pendingRouteRevision==nil)
 print("PASS193f actualrecognitionhandoff preservespendingSBSacrossoldFilmID→newFilmID withoutcopyingnativesource")
}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Controller.swift').write_text(crossfile_stubs+applier+projection+'\n func bind(_ input:ThreeDEvidence) {let pendingChoice=pendingRouteOutput;pendingRouteOutput=nil\n'+bind_tail+'\n}\n}\n');(p/'main.swift').write_text(binding_main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'binding')],check=True)
 subprocess.run([str(p/'binding')],check=True)

#193g startup no-film reapply must NOT create an Off intent for a later film.
startup_main=r'''import Foundation
MainActor.assumeIsolated {
 let store=ThreeDStore.shared,c=TestController()
 c.recognitionPath="";c.recognitionIdentity=""
 c.applyThreeDState(store.snapshot,[.reapply],revision:store.revision)
 precondition(c.pendingRouteOutput==nil)
 c.recognitionPath="/synthetic/tagged_public_vr180.mp4";c.recognitionIdentity="bound"
 store.subscribe(ownerID:"startup") {state,effects in c.applyThreeDState(state,effects,revision:store.revision)}
 c.bind(ThreeDEvidence(metadata:ThreeDSource(.vr180SBS)))
 store.dispatch(.setOutput(.vr180))
 c.bind(ThreeDEvidence(metadata:ThreeDSource(.vr180SBS)))
 precondition(store.snapshot.current.output == .vr180 && c.pendingRouteOutput==nil)
 print("PASS193g emptystartupreapplydoesnotcacheOff; repeatedmetadataretainsnativeVR180")
}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Controller.swift').write_text(crossfile_stubs+applier+projection+'\n func bind(_ input:ThreeDEvidence) {let pendingChoice=pendingRouteOutput;pendingRouteOutput=nil\n'+bind_tail+'\n}\n}\n');(p/'main.swift').write_text(startup_main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'startup')],check=True)
 subprocess.run([str(p/'startup')],check=True)

#193k full production Swift command bytes -> real mpv, every output mode,
# native/ordinary films, same-film reopen and a second fresh player process.
# Fixture names match observed owner names, bytes are public test pixels only.
if os.environ.get('MPV_RUNTIME_BIN') and os.environ.get('MPV_RUNTIME_FIXTURE'):
 import socket,time,shutil,re
 all_modes_main=r'''import Foundation
 MainActor.assumeIsolated {
  let store=ThreeDStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),c=TestController()
  store.subscribe(ownerID:"193k") {state,effects in c.applyThreeDState(state,effects,revision:store.revision)}
  @MainActor func phase(_ name:String,_ action:ThreeDAction) {
   c.commands=[];store.dispatch(action)
   print(String(data:try! JSONSerialization.data(withJSONObject:["phase":name,"file":URL(fileURLWithPath:c.recognitionPath).lastPathComponent,"commands":c.commands]),encoding:.utf8)!)
  }
  for (name,source) in [("SIVR-416-B.mp4",ThreeDSource(.vr180SBS)),("Eden West.mp4",ThreeDSource(.flat2D)),("Eden West.mp4",ThreeDSource(.flat2D)),("SIVR-416-B.mp4",ThreeDSource(.vr180SBS))] {
   c.recognitionPath="/synthetic/"+name;c.recognitionGeneration+=1;c.appliedThreeD=nil;c.appliedPlan=nil;c.appliedEffects=nil
   phase("open",.open(FilmID(rawValue:c.recognitionPath),ThreeDEvidence(metadata:source)))
   for mode in [ThreeDOutput.vr180,.off,.sbs,.halfSBS,.tb,.anaglyph,.off] {phase(mode.rawValue,.setOutput(mode))}
  }
 }
 '''
 with tempfile.TemporaryDirectory(prefix='193k-prod-real-') as folder:
  p=Path(folder);(p/'Controller.swift').write_text(crossfile_stubs+applier+projection+'}\n');(p/'main.swift').write_text(all_modes_main)
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'allmodes')],check=True)
  modes_rows=[json.loads(x) for x in subprocess.check_output([str(p/'allmodes')],text=True).splitlines() if x.startswith('{')]
  script=p/'vr180-look.lua';script.write_text((root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
  for name in ('SIVR-416-B.mp4','Eden West.mp4'):shutil.copyfile(os.environ['MPV_RUNTIME_FIXTURE'],p/name)
  for restart in range(2):
   sock=str(p/('ipc'+str(restart)));log=p/('log'+str(restart));request_id=0
   with log.open('w') as f:
    player=subprocess.Popen([os.environ['MPV_RUNTIME_BIN'],'--no-config','--idle=yes','--vo=null','--ao=null','--pause','--loop-file=inf','--script='+str(script),'--input-ipc-server='+sock],stdout=f,stderr=f)
    try:
     for _ in range(100):
      if Path(sock).exists():break
      time.sleep(.02)
     def real_ipc(command):
      global request_id
      request_id+=1
      with socket.socket(socket.AF_UNIX) as client:
       client.settimeout(2);client.connect(sock);client.sendall((json.dumps({'command':command,'request_id':request_id})+'\n').encode())
       incoming=b''
       while True:
        incoming+=client.recv(65536)
        lines=incoming.split(b'\n');incoming=lines.pop()
        for line in lines:
         response=json.loads(line)
         if response.get('request_id')==request_id:
          assert response.get('error')=='success' or (command[:1]==['set_property'] and str(command[1]).startswith('user-data/gor/') and response.get('error')=='property not found'),(command,response)
          return response.get('data')
     verified=0
     for row in modes_rows:
      if row['phase']=='open':
       real_ipc(['stop']);real_ipc(['loadfile',str(p/row['file']),'replace']);time.sleep(.06)
      for encoded in row['commands']:
       real_ipc(json.loads(encoded)['command'])
      # IPC success is NOT acceptance. This old Linux mpv lacks user-data
      # properties, so read the actual Lua completion record, not the declared
      # Swift receipt and not an IPC success response.
      complete=[json.loads(c)['command'] for c in row['commands'] if 'vr180-look-route-complete' in c]
      wanted=int(complete[-1][3]) if complete else None
      actual=None
      for _ in range(100):
       lines=[line for line in log.read_text().splitlines() if '3D-VERIFIED ' in line and 'revision='+str(wanted)+' ' in line]
       if lines:
        actual=dict(re.findall(r'([a-z_]+)=([^ ]+)',lines[-1].strip()));break
       time.sleep(.01)
      assert wanted is not None and actual and actual['verdict']=='PASS',(row,actual)
      assert lines[-1].strip().endswith('playing_file='+row['file']),(row,lines[-1])
      ctx=next(json.loads(c)['command'] for c in row['commands'] if 'vr180-look-store-revision' in c)
      assert (actual['enabled'],int(actual['layout']),int(actual['pack']))==(ctx[6],int(ctx[7]),int(ctx[8])),(row,actual,ctx)
      verified+=1
     time.sleep(.05)
    finally:player.terminate();player.wait(timeout=5)
   text=log.read_text();lines=[line for line in text.splitlines() if '3D-VERIFIED ' in line]
   assert len(lines)==verified==32 and all('verdict=PASS ' in line for line in lines),(restart,verified,lines)
   assert 'Lua error' not in text and 'verdict=FAIL ' not in text,text
   assert text.count('3D-CLOSE ')>=4,text
   print('PASS193k PRODUCTIONSwift->REALmpv32/32all6outputs native/ordinary/samefilmreopen/differentfilm freshprocess',restart)
else:print('NOT_RUN193k productionSwift->realmpv requires MPV_RUNTIME_BIN+MPV_RUNTIME_FIXTURE')
