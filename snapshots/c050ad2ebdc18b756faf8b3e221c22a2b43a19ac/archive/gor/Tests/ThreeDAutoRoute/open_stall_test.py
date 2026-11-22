#!/usr/bin/env python3
"""Production open receipt + production drawable accessor. Linux timing, not a Mac8K claim."""
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
import os,subprocess,tempfile,json
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
source=(root/'Sources/gor/Player/PPControllerMenuQueries.swift').read_text();a=source.index('    func surfaceDrawableReceipt()');b=source.index('    /// Absolute sub-pos',a);method=source[a:b]
swift='''import Foundation
final class Surface {
 var surfaceDrawableSnapshot:(Double,Double)?=(1920,1080)
 var queries=0
 func queryMenuPayload(_ x:String)->[String:Any] {queries+=1;Thread.sleep(forTimeInterval:0.3);return [:]}
'''+method+'''}
@main struct Test {
 @MainActor static func main() {
 let defaults=UserDefaults(suiteName:"gor-open-stall-test")!;defaults.removePersistentDomain(forName:"gor-open-stall-test")
 let store=ThreeDStore(defaults:defaults);let id=FilmID(rawValue:"native-film");var callbacks=0
 store.subscribe(ownerID:"timing") {_,_ in callbacks+=1};callbacks=0
 var gate=ThreeDOpenReceipt();let evidence=ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))
 let start=ProcessInfo.processInfo.systemUptime
 for _ in 0..<10000 {if gate.accept(evidence) {store.dispatch(.open(id,evidence))}}
 let elapsed=ProcessInfo.processInfo.systemUptime-start
 precondition(callbacks==1,"duplicate opens reached applier")
 gate.reset();if gate.accept(evidence) {store.dispatch(.open(id,evidence))};precondition(callbacks==2,"real reopen lost")
 let changed=ThreeDEvidence(metadata:ThreeDSource(.vr180TB));if gate.accept(changed) {store.dispatch(.open(id,changed))};precondition(callbacks==3,"changed metadata lost")
 let surface=Surface();let t=ProcessInfo.processInfo.systemUptime
 for _ in 0..<10000 {precondition(surface.surfaceDrawableReceipt()!.0==1920)}
 let cached=ProcessInfo.processInfo.systemUptime-t;precondition(surface.queries==0)
 surface.surfaceDrawableSnapshot=nil;precondition(surface.surfaceDrawableReceipt()==nil)
 print("MEAS duplicate_open_count=10000 callback_count=1 elapsed_s=\\(elapsed)")
 print("MEAS drawable_reads=10000 socket_queries=\\(surface.queries) elapsed_s=\\(cached)")
 print("PASS changed metadata and structural same-file reopen are applied")
 print("BOUNDARY Linux production-method timing; owner8K Mac frame pacing unmeasured")
 defaults.removePersistentDomain(forName:"gor-open-stall-test")
 }
}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'test.swift').write_text(swift)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'test.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
f=(_pp_split().path(root,'PPController_Features.swift')).read_text();pp=(_pp_split().path(root,'PPController.swift')).read_text()
assert 'guard openReceipt.accept(input) else {' in f and 'if geometryChanged {MainActor.assumeIsolated {applyThreeDState(ThreeDStore.shared.snapshot,[.present])}}' in f
assert 'vr180Controller?.invalidateOpenReceipt()' in pp
assert 'surfaceDrawableSnapshot=(w,h)' in pp and 'surfaceDrawableSnapshot=nil' in pp
assert 'surfaceCropAwaitingDrawable=false;DispatchQueue.main.async' in pp
print('PASS production wiring: invalidate at structural start; accepted feed; retry missing receipt asynchronously')
