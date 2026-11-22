#!/usr/bin/env python3
"""Actual Lua frames -> compiled PPController identity/receipt + actual final consumer.
Both orders, separate window/fullscreen, Movie->Himiko->Movie, later live roll.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,os,json
root=Path(__file__).resolve().parents[2]
f=root/'Tests/SpineUI/ui_tilt_frame_containment_test.py';h=f.read_text()
ctx={'__file__':str(f)};exec(compile(h[:h.index('frames=[]')],str(f),'exec'),ctx)
pp=(_pp_split().path(root,'PPController.swift')).read_text();extract=ctx['extract']
frames=[]
for w,h in [(819,546),(2048,1280)]:
 for order in ['receipt-first','identity-first']:
  for name,iw,ih in [('Movie',1080,720),('Himiko',1920,1080),('Movie',1080,720)]:
   r=ctx['ns']['Replay'](flat=True);r.g.props['path']=name;r.g.props['osd-width']=w;r.g.props['osd-height']=h
   r.msg('vr180-look-set-projection','flat-2d3d',iw/ih);r.msg('vr180-look-set-pack',3,0,.5,1,0)
   if name=='Himiko':r.msg('vr180-look-bar-crop',.12,0,.76,1)
   r.msg('vr180-look-full-fit');r.pose(roll=.25)
   frame=dict(r.g.props['user-data/vr180-look/film-frame'])
   frame={k:float(v) for k,v in frame.items() if isinstance(v,(int,float))};frame['sequence']=len(frames)+100;frame['_receiptFirst']=1 if order=='receipt-first' else 0;frame['_movie']=1 if name=='Movie' else 0
   frames.append(frame)
# Reuse original compiled production final-transform and hit-inverse assertions.
h2=(root/'Tests/SpineUI/ui_tilt_frame_containment_test.py').read_text()
section=h2[h2.index("program='import Foundation"):]
# Replace the harness's direct frame assignment with the production receipt path.
section=section.replace('for frame in cases {','let probe=PPProbe()\nfor frame in cases {').replace('let probe=PPProbe();probe.committedFilmFrame=frame','''probe.filmIdentityPending=true;probe.committedFilmFrame=nil;probe.pendingFilmFrame.removeAll()
 let path=frame["_movie"]==1 ? "Movie":"Himiko"
 probe.currentFilePath="previous-file"
 var incoming:[String:Any]=frame;incoming["path"]=path
 if frame["_receiptFirst"]==1 {probe.noteFilmFrame(incoming);check(probe.committedFilmFrame==nil,"early receipt committed to wrong file");probe.setFilmFrameIdentity(path)}
 else {probe.setFilmFrameIdentity(path);probe.noteFilmFrame(incoming)}
 check(probe.committedFilmFrame?["angle"]==frame["angle"],"receipt-before-identity was lost")
 check(probe.pendingFilmFrame.isEmpty,"pending not consumed")
 // A later orientation publication is not suppressed: it must remain accepted.
 probe.currentFilePath=path;probe.noteFilmFrame(incoming)
 check(probe.committedFilmFrame?["angle"]==frame["angle"],"later nonzero roll publication lost")''')
ctx['frames']=frames;exec(compile(section[:section.index('with tempfile.TemporaryDirectory()')],str(f),'exec'),ctx)
# The default harness runs immediately. Above compiled actual consumer using stored frames;
# now a dedicated lifecycle probe compiles actual noteFilmFrame + set identity methods.
program=ctx['program']
# Already executed baseline final-consumer harness; splice actual methods and rerun with lifecycle.
program=program.replace('var vr180Controller:LegacyProbe?=nil','var vr180Controller:LegacyProbe?=LegacyProbe()')
program=program.replace('class LegacyProbe {var usesLegacyPreviewChrome=false}', 'class LegacyProbe {var usesLegacyPreviewChrome=false,expectsSBSFilmFrame=true}').replace('final class PPProbe {','''final class Connection {var commands:[String]=[];func write(_ s:String){commands.append(s)}}
final class PPProbe {
 var filmFrameSequenceFloor:[String:Double]=[:];var vrModeEnabled=true,currentFilePath="",filmFramePath="",pendingFilmFrame:[String:[String:Any]]=[:]
 var filmIdentityPending=false,filmIdentityAt=Date.distantPast,filmFirstReceiptAt=Date.distantPast
 let persistentConnection=Connection()
 var appliedVideoFrame=CGRect.zero,appliedVideoFrameWindowSize=CGSize.zero
 func applyVideoFrame(bounds:CGRect) {}
'''+extract(pp,'private func clearCommittedFilmFrame(').replace('private func','func')+'\n'+extract(pp,'private func setFilmFrameIdentity(').replace('private func','func')+'\n'+extract(pp,'private func noteFilmFrame(').replace('private func','func'))
# ctx program already includes modified lifecycle test, run after adding methods.
import tempfile
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
old=subprocess.check_output(['git','show','7b9bc2dd7751fae83764432f9d442c6c934e8982:archive/gor/Sources/gor/Player/PPController.swift'],text=True)
oldMethod=extract(old,'private func noteFilmFrame(').replace('private func','func')
currentMethod=extract(pp,'private func noteFilmFrame(').replace('private func','func')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program.replace(currentMethod,oldMethod))
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 result=subprocess.run([str(p/'test')],capture_output=True,text=True)
 assert result.returncode!=0 and 'receipt-before-identity was lost' in result.stdout,'taking194u negative control did not fail early receipt order'
 print('PASS taking194u negative control RED: first early receipt lost; later-roll publication remains in the harness, not artificially suppressed')
print('PASS12 identity-order cases with actual methods, current-path committed receipt, nonzero-roll exact polygon and hit inverse; window/fullscreen separate')

# Identity requests are bounded and safely wrap inside the dispatch-owned range.
assert 'filmIdentityQuery+=1;if filmIdentityQuery>=9_195_000 {filmIdentityQuery=9_194_001}' in pp
assert '(9_194_001..<9_195_000).contains(rid)' in pp
assert 'requestFilmIdentity()' in extract(pp,'private func beginFilmIdentity(')
assert 'setFilmFrameIdentity(p)' in pp
