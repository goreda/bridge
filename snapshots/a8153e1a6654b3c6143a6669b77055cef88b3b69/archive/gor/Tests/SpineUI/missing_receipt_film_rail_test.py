#!/usr/bin/env python3
"""Compile production applyVideoFrame chrome selection and missing-receipt helper."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,os
root=Path(__file__).resolve().parents[2];s=(_pp_split().path(root,'PPController.swift')).read_text()
def extract(sig):
 a=s.index(sig);i=s.index('{',a)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private func','func')
a=s.index('        var chromeBounds = hudBounds',s.index('private func applyVideoFrame('));b=s.index('        visiblePictureBounds=chromeBounds',a)
helper=extract('    private func missingFlatFilmBounds(') if '    private func missingFlatFilmBounds(' in s else ''
program='''import Foundation
class VR {
 var presentsFlatSBSGeometry=true,usesLegacyPreviewChrome=false,recognitionPath="Movie",latestWidth=1080.0,latestHeight=720.0
 func knownEyeAspect(kind:String,filename:String,width:Double,height:Double)->Double {width/height}
}
class Probe {
 var cropRect:CGRect?=nil,manualMenuCropAspect:Double?=nil,stereoManualAspect:Double?=nil,stereoMenuCropAspect:Double?=nil
 let vr180Controller:VR?=VR();var committedFilmFrame:[String:Double]?=nil,vrModeEnabled=true,currentFilePath="Movie"
 var effectiveVrGap:(value:Double,source:String)?=(0.0125,"lua")
 func traceFilmUI(_ reason:String,receiptPath:String?=nil){}
 func flatEyeContentBounds(_ r:CGRect)->CGRect {r}
'''+helper+'''
 func rail()->CGRect {
 let winW=2048.0,winH=1280.0
 let bounds=CGRect(x:0,y:0,width:winW,height:winH),displayRect=CGRect(x:0,y:0,width:winW,height:winH),hudBounds=CGRect(x:0,y:0,width:winW,height:winH)
'''+s[a:b]+'''
 return chromeBounds
 }
}
let p=Probe(),r=Probe().rail()
precondition(abs(r.width/r.height-1.5)<1e-9,"nil receipt leaves SBS UI at drawable edges, not current3:2 film")
precondition(r.height<1280 && r.width<1024,"nil receipt rail not film-contained")
p.vr180Controller!.recognitionPath="old-film"
precondition(p.rail().height==1280,"fallback used previous film geometry")
p.vr180Controller!.recognitionPath="Movie";p.vr180Controller!.latestWidth=0
precondition(p.rail().height==1280,"fallback invented unknown source geometry")
print("PASS actual missing-receipt rail selection:3:2 contained in left SBS eye; rejects wrong path and absent dimensions")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
