#!/usr/bin/env python3
"""Actual Swift applier/sender -> actual Lua, late zero/wrong geometry refresh.
The macOS recognition wrapper has an ordering check, not a fake native verdict.
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
import json,tempfile,subprocess,os,runpy
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
t=(root/'Tests/ThreeDAutoRoute/explicit_sbs_lua_test.py').read_text()
f=(_pp_split().path(root,'PPController_Features.swift')).read_text()
a=t.index('features=(root/');b=t.index('scenario=r',a)
ns={'root':root};exec(t[a:b],ns)
stubs=ns['stubs'].replace('func knownEyeAspect(kind:String,filename:String,width:Double,height:Double)->Double {16/9}','func knownEyeAspect(kind:String,filename:String,width:Double,height:Double)->Double {width>0 && height>0 ? width/height:0}')
stubs=stubs.replace(' func sendRaw(_ text:String) {commands.append(text)}',' func ipcCommand(_ text:String) {commands.append(text)}\n'+ns['sender'])
main=r'''import Foundation
MainActor.assumeIsolated {
 for (initialW,initialH) in [(0.0,0.0),(960.0,540.0),(1080.0,720.0)] {
 let c=TestController();c.latestWidth=initialW;c.latestHeight=initialH
 var s=ThreeDState();s.currentFilm=FilmID(rawValue:"191t-applier")
 s.films["191t-applier"]=FilmThreeD();s.films["191t-applier"]!.output = .sbs
 c.applyThreeDState(s,[.present],revision:1)
 let first=c.commands;c.commands=[]
 c.latestWidth=1080;c.latestHeight=720
 c.applyThreeDState(s,[.present],revision:1)
 let refresh=c.commands
 let changed=initialH==0 || abs(initialW/initialH-1.5)>1e-8
 precondition(refresh.contains{$0.contains("vr180-look-set-projection") && $0.contains("1.5")} == changed,"real applier retained stale aspect instead of fresh1080x720")
 if initialW>0 && initialH>0 {precondition(!refresh.contains{$0.contains("vr180-look-set-enabled") || $0.contains("vr180-look-set-output") || $0.contains("loadfile")},"geometry refresh rebuilt route/media or reset head pose")}
 else {precondition(!first.contains{$0.contains("vr180-look-set-projection")},"unready geometry published zero projection")}
 c.commands=[];c.applyThreeDState(s,[.present],revision:1)
 precondition(!c.commands.contains{$0.contains("vr180-look-set-projection")},"unchanged geometry republishes each poll")
 print(String(data:try! JSONSerialization.data(withJSONObject:["initialW":initialW,"initialH":initialH,"first":first,"refresh":refresh]),encoding:.utf8)!)
 }
}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'Controller.swift').write_text(stubs+ns['applier']+ns['projection']+'}\n');(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'probe')],check=True)
 rows=[json.loads(s) for s in subprocess.check_output([str(p/'probe')],text=True).splitlines() if s.startswith('{')]
Replay=runpy.run_path(str(root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py'))['Replay']
for row in rows:
 r=Replay(flat=True)
 def replay(encoded):
  c=json.loads(encoded)['command']
  if c[:2]==['script-message-to','vr180_look']:r.g.handlers[c[2]](*map(str,c[3:]))
 for x in row['first']:replay(x)
 r.pose(roll=.35)
 if row['initialH']==0:assert not any('vr180-look-set-projection' in x for x in row['first'])
 for x in row['refresh']:replay(x)
 r.pose(roll=.35)
 frame=r.g.props['user-data/vr180-look/film-frame']
 assert frame is not False and abs(frame['angle']+.35)<1e-9
 assert abs(r.values()['vr_eye_aspect']-1.5)<1e-6
 print('PASS actual Swift sender -> Lua: initial',row['initialW'],row['initialH'],'fresh1080x720 yields aspect1.5, tilt-.35 and a committed film frame')
a=f.index('    func autoDetectFromVideoParams(');b=f.index('    /// GOR_VR_SIM_POSE',a);method=f[a:b]
assert method.index('latestWidth = width') < method.index('if recognitionPath != filename') < method.index('if pendingRouteRevision != nil')
assert 'if geometryChanged {MainActor.assumeIsolated {applyThreeDState(ThreeDStore.shared.snapshot,[.present])}}' in method
print('PASS recognition ordering and unchanged-evidence geometry refresh wiring; full AppKit wrapper uncompiled')
