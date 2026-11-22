#!/usr/bin/env python3
"""Compile production positive-dimension selector and flat-source aspect function."""
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
import subprocess,tempfile,os
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2];pp=(_pp_split().path(root,'PPController.swift')).read_text();features=(_pp_split().path(root,'PPController_Features.swift')).read_text()
def extract(s,sig):
 a=s.index(sig);i=s.index('{',a)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private static func','static func')
program='''import Foundation
enum SourceFormatChoice {static func get(_ p:String)->String {"flat"}}
enum SBSGeometry {static func resolve(width:Double,height:Double,pixelAspect:Double,filename:String,stereoProven:Bool,fullByContract:Bool,cropWidth:Double?,cropHeight:Double?)->Probe? {nil}}
class Probe {
 var aspect=1.5,latestPixelAspect=1.0,recognitionPath="Movie"
'''+extract(pp,'    private static func flatSourceGeometry(')+'\n'+extract(features,'    func knownEyeAspect(')+'''
}
let p=Probe()
for bad in [0.0,-1.0,Double.nan,Double.infinity] {
 let g=Probe.flatSourceGeometry(["video-dec-params/w":bad,"video-dec-params/h":1080.0,"video-dec-params/dw":1440.0,"video-dec-params/dh":1080.0,"video-dec-params/par":4.0/3.0])
 precondition(g.w==1440 && g.h==1080 && g.par==1,"mixed coded/display pair or double PAR")
 let c=Probe.flatSourceGeometry(["video-dec-params/w":1080.0,"video-dec-params/h":720.0,"video-dec-params/par":bad])
 precondition(c.w*c.par/c.h==1.5,"invalid PAR poisoned coded geometry")
}
let coded=Probe.flatSourceGeometry(["video-dec-params/w":1080.0,"video-dec-params/h":720.0,"video-dec-params/par":2.0,"video-dec-params/dw":1920.0,"video-dec-params/dh":1080.0])
precondition(coded.w==1080 && coded.h==720 && coded.par==2,"valid coded pair/PAR changed")
let unknown=Probe.flatSourceGeometry(["video-dec-params/w":1080.0,"video-params/dh":720.0])
precondition(unknown.w==0 && unknown.h==0,"cross-domain width/height invented")
let overflow=Probe.flatSourceGeometry(["video-dec-params/w":Double.greatestFiniteMagnitude,"video-dec-params/h":1.0,"video-dec-params/par":2.0])
precondition(overflow.w==0,"overflow aspect accepted")
p.latestPixelAspect=2
precondition(p.knownEyeAspect(kind:"flat-2d3d",filename:"Movie",width:1080,height:720)==3,"valid PAR ignored")
p.latestPixelAspect=Double.greatestFiniteMagnitude
precondition(p.knownEyeAspect(kind:"flat-2d3d",filename:"Movie",width:1080,height:720)==0,"nonfinite final aspect published")
print("PASS actual Swift positive-finite source selector and flat aspect:0/negative/NaN/infinity fall through; valid geometry/PAR unchanged; no window or previous-file substitution")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
assert 'let flatGeometry=vr180Controller?.requestsFlatSBSGeometry(for:currentFilePath) == true ? Self.flatSourceGeometry(results):nil' in pp
assert 'if requestedPlan.output == .sbs,requestedPlan.luaKind=="flat-2d3d"' in features
# Compile the actual identity-bound scope decision, not a guessed boolean.
method=extract(features,'    func requestsFlatSBSGeometry(')
program='''import Foundation
enum ThreeDRecognitionBridge {static func filmID(path:String)->FilmID {FilmID(rawValue:path)}}
class ScopeProbe {
'''+method+'''
}
MainActor.assumeIsolated {
 let p=ScopeProbe(),id=FilmID(rawValue:"Movie")
 ThreeDStore.shared.dispatch(.open(id,ThreeDEvidence()))
 ThreeDStore.shared.dispatch(.setSource(ThreeDSource(.flat2D)))
 ThreeDStore.shared.dispatch(.setOutput(.sbs))
 precondition(p.requestsFlatSBSGeometry(for:"Movie"))
 precondition(!p.requestsFlatSBSGeometry(for:"Himiko"),"previous-film plan used for new path")
 precondition(!p.requestsFlatSBSGeometry(for:""))
 for output in [ThreeDOutput.off,.vr180,.tb,.anaglyph] {
  ThreeDStore.shared.dispatch(.setOutput(output))
  precondition(!p.requestsFlatSBSGeometry(for:"Movie"),"new scope leaked to working output")
 }
}
print("PASS actual geometry scope: identity-bound Movie fullSBS only; rejects prior-film plan, empty path, Off/VR180/TB/anaglyph")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDState.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
