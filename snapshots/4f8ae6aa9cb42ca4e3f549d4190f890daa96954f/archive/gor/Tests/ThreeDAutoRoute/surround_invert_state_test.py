"""Production state/keymap and menu toggle expression; real Lua revision handler.
No AppKit UI or owner-device claim.
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
from pathlib import Path
import subprocess,tempfile,re
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
menu=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(root)).read_text())
line=next(l for l in menu.splitlines() if 'case .surroundInvert: store.dispatch(' in l)
toggle=line.split(': ',1)[1]
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text('''import Foundation
@MainActor func boolOf(_ v:ThreeDEffectValue?)->Bool {if case let .bool(b)?=v{return b};return false}
MainActor.assumeIsolated {
let defaults=UserDefaults(suiteName:"surround-invert-"+UUID().uuidString)!
let store=ThreeDStore(defaults:defaults)
precondition(!boolOf(store.snapshot.effects[.surroundInvert]))
store.dispatch(.open(FilmID(rawValue:"film"),ThreeDEvidence(metadata:ThreeDSource(.flat2D))))
let film=store.snapshot.current,old=store.snapshot.effects
'''+toggle+'''
precondition(boolOf(store.snapshot.effects[.surroundInvert]))
precondition(store.snapshot.current==film)
for key in ThreeDEffectKey.allCases where key != .surroundInvert {precondition(store.snapshot.effects[key]==old[key])}
let reloaded=ThreeDStore(defaults:defaults)
precondition(boolOf(reloaded.snapshot.effects[.surroundInvert]))
'''+toggle+'''
precondition(!boolOf(store.snapshot.effects[.surroundInvert]))
precondition(ThreeDKeymap.rows.filter {$0.act == .surroundInvert}.count==1)
precondition(ThreeDKeymap.rows.first {$0.act == .surroundInvert}?.chord==nil)
precondition(ThreeDRouteEnvelope.messages.contains("vr180-look-surround-invert"))
print("PASS production menu toggle/reducer/persistence: default-off, live toggle, no film/other setting mutation")
}
''')
 subprocess.run(['swiftc',str(_sec_file(root,'ThreeDState.swift')),str(_sec_file(root,'ThreeDKeymap.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
r=ns['Replay'](flat=True)
h=r.g.handlers
h['vr180-look-store-revision']('12','flat-2d3d','store-applier')
h['vr180-look-surround-invert']('1','11','store-applier')
assert r.values()['vr_pk_surround_invert']==0,'stale message accepted'
h['vr180-look-surround-invert']('1','12','store-applier')
assert r.values()['vr_pk_surround_invert']==1
h['vr180-look-surround-invert']('0','12','other')
assert r.values()['vr_pk_surround_invert']==1,'wrong sender accepted'
h['vr180-look-surround-invert']('0','12','store-applier')
assert r.values()['vr_pk_surround_invert']==0
assert 'case .surroundInvert: i.state = Self.boolOf(s.effects[.surroundInvert])' in menu
assert 'ThreeDKeymap.Act.surroundBlack, .surroundSoft, .surroundInvert]' in menu
assert 'vr180-look-surround-invert' in (_pp_split().path(root,'PPController_Features.swift')).read_text()
print('PASS real Lua uniform handler: current-revision only, sender enforced, invert off recovery')
