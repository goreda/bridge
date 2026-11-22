#!/usr/bin/env python3
"""Compile controller canvas selection + production safety placement, not AppKit playback."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=_sub_read(_pp_split().path(root,'PPController.swift'))
selector=next(line.strip() for line in s.splitlines() if 'let subtitleFilmCanvas =' in line)
main='import Foundation\nvar cases=0\n'+'''for layout in [0.0,1,2,3] {for deg in [-45.0,-25,25,45] {for bottom in [false,true] {
let committedFilmFrame:[String:Double]?=["layout":layout]
let chromeBounds=CGRect(x:83,y:67,width:620,height:310),displayRect=CGRect(x:0,y:0,width:960,height:600)
'''+selector+'''
precondition(subtitleFilmCanvas==CGRect(x:0,y:0,width:620,height:310))
let ink=CGRect(x:18,y:bottom ? 260:4,width:220,height:38),r=deg*Double.pi/180
let p=SubtitleTiltGeometry.place(ink:ink,screen:subtitleFilmCanvas,shift:320,left:1,offset:-2,roll:r,pairRoll:r)
let c=cos(p.angle),sn=sin(p.angle)
for side in [0.0,1] {for x in [ink.minX,ink.maxX] {for y in [ink.minY,ink.maxY] {
let xx=ink.midX+c*(x-ink.midX)-sn*(y-ink.midY)+p.leftX+side*p.replicaX
let yy=ink.midY+sn*(x-ink.midX)+c*(y-ink.midY)+p.leftY+side*p.replicaY
precondition(xx >= -1e-8 && xx <= 620+1e-8 && yy >= -1e-8 && yy <= 310+1e-8)
}}}
cases+=1
}}}
print("PASS",cases,"compiled cropped-canvas controller selections + production both-eye four-corner placements across plain/SBS/TB/anaglyph; native AppKit NOT_RUN")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(root/'Sources/gor/Subtitles/SubtitleTiltGeometry.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
