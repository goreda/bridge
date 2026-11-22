"""Compile production reducer, keymap, menu dispatch, applier and Lua sender.
Only platform boundaries are stubs. Returns the actual emitted command bytes.
"""
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
import ast,json,os,subprocess,tempfile
from pathlib import Path
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

ROOT=Path(__file__).resolve().parents[2]
def commands():
 text=(ROOT/'Tests/ThreeDAutoRoute/explicit_sbs_lua_test.py').read_text()
 tree=ast.parse(text)
 unlock=(ROOT/'Sources/gor/Stereo/LookToolsRoute.swift').read_text().split('    func releaseProjectionLock()',1)[1].split('\n',1)[0]
 def literal_string(node):
  if isinstance(node,ast.Constant) and isinstance(node.value,str):return node.value
  if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Add):return literal_string(node.left)+literal_string(node.right)
  if isinstance(node,ast.Name) and node.id=='unlock':return unlock
  raise ValueError('unsupported fixture expression')
 stubs=next(literal_string(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='stubs' for t in n.targets))
 features=(_pp_split().path(ROOT,'PPController_Features.swift')).read_text()
 sender=features[features.index('    func sendRaw(_ original: String)'):features.index('    var singleSwitchActive',features.index('    func sendRaw(_ original: String)'))]
 stubs=stubs.replace(' func sendRaw(_ text:String) {commands.append(text)}',' func ipcCommand(_ text:String) {commands.append(text)}\n'+sender)
 def method(name,end=None):
  start=features.index('    func '+name+'(')
  stop=features.index(end,start) if end else features.index('\n    func ',start+10)
  return features[start:stop]
 applier=method('applyThreeDState','    /// Read-only receipt')
 projection=method('publishProjection')
 enabled=method('setVRModeEnabled','    /// GOR_TRACE_GEOM=1 only:')
 start=stubs.index('func setVRModeEnabled(');a=stubs.index('{',start);level=1;b=a+1
 while level:level+=(stubs[b]=='{')-(stubs[b]=='}');b+=1
 stubs=stubs[:start]+enabled+stubs[b:]
 stubs=stubs.replace('func releaseProjectionLock() {}','func releaseProjectionLock() {sendRaw(#"{"command":["script-message-to","vr180_look","vr180-look-plan-lock","off"]}"#)}')
 stubs=stubs.replace('func resetFilmView() {}','func resetFilmView() {sendRaw(#"{"command":["script-message-to","vr180_look","vr180-look-full-fit"]}"#)}')
 stubs+='''
 static let vrAutoFullscreen=false
 func noteManualEnabled(_ value:Bool) {}
 func sendSwapEyes() {};func sendPersistedBaseIPD() {}
 func traceCameraState(_ value:String) {};func updateCameraTraceHeartbeat() {}
'''
 stubs=stubs.replace('final class TestController {','final class ScreenCaptureEngine {static let shared=ScreenCaptureEngine();var vrModeActive=false}\nfinal class TestController {')
 menu=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(ROOT)).read_text());start=menu.index('    static func dispatch(');end=menu.index('        case .filmAuto:',start)
 menu='@MainActor enum ThreeDMenu {\n'+menu[start:end]+'        default: break\n        }\n    }\n}\n'
 pp=(_pp_split().path(ROOT,'PPController.swift')).read_text()
 pp=pp[pp.index('    func setVRModeEnabled(_ enabled: Bool) {',pp.index('private var vr180Controller')):pp.index('    func selectManualSource(',pp.index('    private func offReset()'))]
 pp_stubs=r'''enum AspectPreset {case defaultAR,other}
final class AppDelegate {var currentAspectPreset=AspectPreset.other}
final class Application {var delegate:AnyObject?=AppDelegate()}
let NSApp=Application()
final class CropDetector {var stereoSBS=false,stereoTopBottom=false,viewportOnly=false;func cancel() {};func resetLastFile() {}}
final class TestPP {
 var vr180Controller:TestController?=TestController()
 var vrModeEnabled:Bool {vr180Controller?.vrModeEnabled ?? false}
 var stereoManualAspect:Double?=1,stereoGeometryKey="old",stereoRestorePending=true,stereoProjectionBaseAspect:Double?=1
 var sourceCropPropertyActive=true,cropDetector=CropDetector(),appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero,bounds=CGRect.zero
 var menuCropOwnsSelection=false,headTrackingEnabled=false;var manualMenuCropAspect:Double?
 func startAutomaticCropDetection(needsRedetect:Bool=false) {}
 var resets=0,crops:[CGRect]=[]
 func ipcCommand(_ s:String) {}
 func clearOwnedCropFromMenu() {resets+=1}
 func requestRealCrop(_ r:CGRect) {crops.append(r)}
 func clearStereoMenuCrop(refit:Bool) {}
 func restoreStereoMenuFrame() {}
 func refreshStereoMenuGeometry(force:Bool) {}
 func refreshEffectiveGap() {}
 func applyVideoFrame(bounds:CGRect) {}
'''
 stubs=stubs.replace(' var recognitionIdentity=', ''' var isTopBottom=false;var cropSourcePacking:(stereo:Bool,topBottom:Bool) {(false,false)}
 func applySourceOutput(_ value:String) {}
 var recognitionIdentity=''')
 pp_test=r'''let pp=TestPP()
 var offState=ThreeDReducer.reduce(ThreeDState(),.open(FilmID(rawValue:"191t-applier"),ThreeDEvidence())).0
 offState=ThreeDReducer.reduce(offState,.setOutput(.off)).0
 pp.applyThreeDState(offState,[.reapply]);pp.applyThreeDState(offState,[.reapply])
 precondition(pp.resets==2,"explicit repeated Off must still run the real PP reset")
 pp.applyThreeDState(offState,[]);precondition(pp.resets==2,"ordinary Off-state effect must stay live")
 pp.setVRModeManually(false);pp.select3DOutput("off");pp.setVRModeEnabled(false)
 precondition(pp.resets==5 && pp.crops.count==5 && pp.crops.allSatisfy {$0==CGRect(x:0,y:0,width:1,height:1)})
 precondition(pp.stereoManualAspect==nil && pp.stereoGeometryKey.isEmpty && pp.stereoProjectionBaseAspect==nil && !pp.sourceCropPropertyActive)
'''
 main='''import Foundation
MainActor.assumeIsolated {
 let store=ThreeDStore.shared,controller=TestController(),id=FilmID(rawValue:"191t-applier")
 store.subscribe(ownerID:"off-regression") {state,effects in controller.applyThreeDState(state,effects)}
 for source:ThreeDSource.Format in [.flat2D,.sbsFull,.tbFull,.vr180SBS,.vr180TB] {
  for route in ["menu-off","key-toggle","key-vr180","store-off","repeat-off","relaunch"] {
   store.dispatch(.open(id,ThreeDEvidence(metadata:ThreeDSource(source))))
   store.dispatch(.setSource(ThreeDSource(source)))
   ThreeDMenu.dispatch(.viewSBS)
   if route == "key-vr180" {ThreeDMenu.dispatch(.viewVR180)}
   controller.commands=[]
   if route == "key-toggle" {
    let act=ThreeDKeymap.match(charactersIgnoringModifiers:"d",keyCode:2,shift:true,option:false,control:false,command:false)!
    precondition(act == .toggle3D);ThreeDMenu.dispatch(act)
   } else if route == "key-vr180" {
    let act=ThreeDKeymap.match(charactersIgnoringModifiers:"v",keyCode:9,shift:true,option:false,control:false,command:false)!
    precondition(act == .viewVR180);ThreeDMenu.dispatch(act)
   } else if route == "menu-off" {ThreeDMenu.dispatch(.viewOff)}
   else {store.dispatch(.setOutput(.off))}
   if route == "repeat-off" {ThreeDMenu.dispatch(.viewOff)}
   if route == "relaunch" {store.dispatch(.open(id,ThreeDEvidence(metadata:ThreeDSource(source))))}
   precondition(store.snapshot.current.output == .off)
   let commands=controller.commands.compactMap {$0.data(using:.utf8)}.compactMap {try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}.compactMap {$0["command"]}
   print(String(data:try! JSONSerialization.data(withJSONObject:["route":route,"source":source.rawValue,"commands":commands]),encoding:.utf8)!)
  }
 }
 let modes:[(String,ThreeDSource.Format,ThreeDOutput)]=[("off",.flat2D,.off),("SBS",.sbsFull,.sbs),("TB",.tbFull,.tb),("2D-to-SBS",.flat2D,.sbs),("2D-to-VR180",.flat2D,.vr180),("nativeVR180SBS",.vr180SBS,.vr180),("nativeVR180TB",.vr180TB,.vr180)]
 for from in modes {for to in modes {
  var state=ThreeDReducer.reduce(ThreeDState(),.open(id,ThreeDEvidence(metadata:ThreeDSource(from.1)))).0
  state=ThreeDReducer.reduce(state,.setSource(ThreeDSource(from.1))).0
  state=ThreeDReducer.reduce(state,.setOutput(from.2)).0
  let live=TestController();live.applyThreeDState(state,[.reapply]);let before=live.commands;live.commands=[]
  state=ThreeDReducer.reduce(state,.setSource(ThreeDSource(to.1))).0
  state=ThreeDReducer.reduce(state,.setOutput(to.2)).0
  live.applyThreeDState(state,[.reapply])
  var restored=state;restored.currentFilm=nil
  restored=ThreeDReducer.reduce(restored,.open(id,ThreeDEvidence(metadata:ThreeDSource(to.1)))).0
  precondition(restored.current.output == state.current.output,"live output must equal persisted fresh open")
  let fresh=TestController();fresh.applyThreeDState(restored,[.present])
  func parsed(_ lines:[String])->[Any] {lines.compactMap {$0.data(using:.utf8)}.compactMap {try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}.compactMap {$0["command"]}}
  print(String(data:try! JSONSerialization.data(withJSONObject:["matrix":true,"from":from.0,"to":to.0,"before":parsed(before),"live":parsed(live.commands),"fresh":parsed(fresh.commands)]),encoding:.utf8)!)
 }}
}
'''
 with tempfile.TemporaryDirectory(prefix='gor-off-swift-') as folder:
  p=Path(folder);(p/'Controller.swift').write_text(stubs+applier+projection+'}\n'+menu+pp_stubs+pp+'}\n');(p/'main.swift').write_text(main+'\nMainActor.assumeIsolated {\n'+pp_test+'\n}\n')
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(ROOT,'ThreeDState.swift')),str(_sec_file(ROOT,'ThreeDKeymap.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'routes')],check=True)
  return [json.loads(l) for l in subprocess.check_output([str(p/'routes')],text=True).splitlines() if l.startswith('{')]
if __name__=='__main__':
 for row in commands():print(json.dumps(row))
