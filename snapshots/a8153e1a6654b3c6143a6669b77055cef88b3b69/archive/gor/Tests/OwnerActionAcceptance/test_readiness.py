"""Execute the production late-bound readiness path on Linux; AppKit stub only."""
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
import os,subprocess,tempfile
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
source=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDOwnerActionAcceptance.swift'+' '):_b.index('// END relocated '+'ThreeDOwnerActionAcceptance.swift'+'\n')])((_threed_split().path(root)).read_text())
prefix=source[source.index('@MainActor enum'):source.index('    private static var steps')]
write=source[source.index('    private static func write'):source.index('    private static func step')]
stubs='''import Foundation
final class PPController {}
@MainActor enum ThreeDStore { static let shared=Store();final class Store {var snapshot=Snapshot()};struct Snapshot {var currentFilm:Int?} }
@MainActor enum ThreeDMenu {static let shared=Menu();final class Menu {var installedMenu:Int?} }
'''
for mode in ('late','controller_missing','current_film_missing','installed_menu_missing'):
    code=stubs+prefix.replace('+35','+0.3')+write+'''    static var starts=0
    private static func step(_ i:Int,root:URL,controller:PPController) {starts+=1}
}
@main struct Test {
    @MainActor static func main() async {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]);setenv("GOR_OWNER_ACTION_DIR",root.path,1)
        var calls=0;let player=PPController()
        let mode=CommandLine.arguments[2]
        if mode != "current_film_missing" {ThreeDStore.shared.snapshot.currentFilm=1}
        if mode != "installed_menu_missing" {ThreeDMenu.shared.installedMenu=1}
        ThreeDOwnerActionAcceptance.startIfRequested(controller:{calls+=1;return mode == "controller_missing" || (mode == "late" && calls==1) ? nil:player})
        try? await Task.sleep(nanoseconds:700_000_000)
        if mode == "late" {precondition(calls>1 && ThreeDOwnerActionAcceptance.starts==1)}
        else {
            precondition(ThreeDOwnerActionAcceptance.starts==0)
            let data=try! Data(contentsOf:root.appendingPathComponent("complete.json"))
            let result=try! JSONSerialization.jsonObject(with:data) as! [String:Any]
            precondition(result["reason"] as? String == "readiness_"+mode)
        }
        print("PASS production bounded readiness "+mode)
    }
}
'''
    with tempfile.TemporaryDirectory() as folder:
        p=Path(folder);(p/'probe.swift').write_text(code)
        subprocess.run([os.environ.get('SWIFTC','swiftc'),'-parse-as-library',str(p/'probe.swift'),'-o',str(p/'probe')],check=True)
        subprocess.run([str(p/'probe'),folder,mode],check=True,timeout=8)
with tempfile.TemporaryDirectory() as folder:
    p=Path(folder)
    (p/'main.swift').write_text('''import Foundation
MainActor.assumeIsolated {
    let defaults=UserDefaults(suiteName:"gor-harness-isolation-"+UUID().uuidString)!
    defaults.set(Data("owner-record".utf8),forKey:ThreeDStore.defaultsKey)
    let before=defaults.data(forKey:ThreeDStore.defaultsKey)
    setenv("GOR_STORE_ACCEPTANCE_DIR","/private/test-only",1)
    let store=ThreeDStore(defaults:defaults)
    precondition(store.snapshot.currentFilm == nil && store.snapshot.migrationComplete)
    store.dispatch(.open(FilmID(rawValue:"test-film"),ThreeDEvidence()))
    store.dispatch(.setOutput(.sbs))
    precondition(store.snapshot.current.output == .sbs)
    precondition(defaults.data(forKey:ThreeDStore.defaultsKey) == before)
    print("PASS production acceptance film storage remains transient")
}
''')
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'main.swift'),'-o',str(p/'isolation')],check=True)
    subprocess.run([str(p/'isolation')],check=True)

# 192z: execute the existing production test-camera gate and consumer rule.
features=(_pp_split().path(root,'PPController_Features.swift')).read_text()
rules=features[features.index('enum CaptureConsumerRules {'):features.index('\nfinal class VR180Controller')]
gate=features[features.index('    static var blinkCameraAllowed: Bool {'):features.index('\n    var onSubtitleTilt:')]
with tempfile.TemporaryDirectory() as folder:
    p=Path(folder)
    (p/'main.swift').write_text('import Foundation\n'+rules+'\nenum Gate {\n'+gate+'''\n}
for optOut in ["0","1"] {
 setenv("GOR_VR_TEST_NO_CAMERA",optOut,1)
 precondition(Gate.blinkCameraAllowed == (optOut != "1"))
 for vr in [false,true] {
  precondition(CaptureConsumerRules.blinkShouldRun(blinkOn:true,vrEnabled:vr,loadedVideoActive:true,cameraAllowed:Gate.blinkCameraAllowed) == (optOut != "1"))
 }
}
precondition(CaptureConsumerRules.headShouldRun(headTrackingEnabled:true,playbackActive:true))
print("PASS192z production blink camera gate suppresses test consumer only; normalblink and head rules unchanged")
''')
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'gate')],check=True)
    subprocess.run([str(p/'gate')],check=True)
"""193d execute production completion barrier, including delayed mpv script queue."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'Sources/gor/Engine/MPVCommand.swift').read_text()
s=s[s.index('enum OwnerActionPlayerProbe {'):s.rfind('#endif')]
# Keep all production methods; only the transport is stubbed.
stub='''import Foundation
enum MPVCommand {static func make(_ v:[Any])->String {"{}"}}
final class IPCClient {
 static var count=0,readyAt=3
 init(path:String) {}
 func send(_ text:String) {}
 func queryBatch(_ text:String,timeout:Double)->[String] {
  Self.count+=1
  let done=Self.count>=Self.readyAt
  let lua:[String:Any] = ["revision":4,"completed_revision":done ? 4:NSNull(),"enabled":done]
  let rows:[[String:Any]] = [
   ["request_id":1,"error":"success","data":["revision":done ? 4:3]],
   ["request_id":2,"error":"success","data":String(data:try! JSONSerialization.data(withJSONObject:lua),encoding:.utf8)!],
   ["request_id":3,"error":"success","data":true]]
  return rows.map {String(data:try! JSONSerialization.data(withJSONObject:$0),encoding:.utf8)!}
 }
}
'''
main='''
let fields=["user-data/gor/3d-applied-state","user-data/vr180-look/applied-state","user-data/vr180-look/enabled"]
let result=OwnerActionPlayerProbe.readCompleted(socket:"test",fields:fields,revision:4,deadline:Date().timeIntervalSince1970+2)
precondition(IPCClient.count==3 && OwnerActionPlayerProbe.completed(result,fields:fields,revision:4))
precondition(!OwnerActionPlayerProbe.completed(result,fields:fields,revision:5))
precondition(OwnerActionPlayerProbe.completed(result,fields:fields,revision:3))
IPCClient.count=0;IPCClient.readyAt=Int.max
let timeout=OwnerActionPlayerProbe.readCompleted(socket:"test",fields:fields,revision:4,deadline:Date().timeIntervalSince1970)
precondition(!timeout.isEmpty && !OwnerActionPlayerProbe.completed(timeout,fields:fields,revision:4))
print("PASS193d actualSwiftbarrier waitsdelayedqueue, rejectswrongrevision andretainstimeoutreceipts")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(stub+s+main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
harness=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDOwnerActionAcceptance.swift'+' '):_b.index('// END relocated '+'ThreeDOwnerActionAcceptance.swift'+'\n')])((_threed_split().path(root)).read_text())
assert '"timestamp":actionStarted' in harness and 'readCompleted(' in harness
print('PASS193d actiontime is menuinvocation not latercapture; actualharnessusesrevisionbarrier')
