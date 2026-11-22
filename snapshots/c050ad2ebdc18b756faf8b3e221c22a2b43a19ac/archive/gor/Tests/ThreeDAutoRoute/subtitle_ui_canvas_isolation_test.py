#!/usr/bin/env python3
"""Actual SubtitleView overlay method: glyph safety must not move194p UI placement."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2];s=_sub_read(root/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
def method(sig):
 a=s.index(sig);b=s.index('{',a)+1;i=b;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private func','func')
main='''import Foundation
typealias NSPoint=CGPoint
class NSView {}
class Layer {var frame=CGRect(x:30,y:270,width:220,height:38)}
class Probe {
var vrSubtitleOn=true,subtitleTilt=(roll:0.45,pair:0.45),textLayer=Layer()
var subtitleTiltCanvas=CGRect(x:0,y:0,width:620,height:310)
var subtitleUIPlacementCanvas=CGRect(x:-83,y:-67,width:960,height:600)
var subtitleTiltReplica=(shift:CGFloat(320),left:CGFloat(1),offset:CGFloat(-2))
var overlayControlBounds:CGRect?=CGRect(x:0,y:0,width:620,height:310)
func convert(_ p:NSPoint,to host:NSView)->NSPoint {p}
func legacyOverlayInkFrame()->CGRect {textLayer.frame}
'''+method('    func trackedOverlayPlacement(')+'''
}
var cases=0
for (w,h) in [(960.0,640.0),(1920,1080)] {for deg in [-45.0,-25,25,45] {
let p=Probe();p.subtitleTilt.roll=deg*Double.pi/180;p.subtitleTilt.pair=p.subtitleTilt.roll
p.subtitleTiltCanvas=CGRect(x:0,y:0,width:w*0.4,height:h*0.5)
p.subtitleUIPlacementCanvas=CGRect(x:-83,y:-67,width:w,height:h)
let got=p.trackedOverlayPlacement(in:NSView())!.placement
let expected=SubtitleTiltGeometry.place(ink:p.textLayer.frame,screen:p.subtitleUIPlacementCanvas,shift:320,left:1,offset:-2,roll:p.subtitleTilt.roll,pairRoll:p.subtitleTilt.pair)
precondition(abs(got.leftX-expected.leftX)<1e-10 && abs(got.leftY-expected.leftY)<1e-10 && abs(got.replicaX-expected.replicaX)<1e-10,"194p UI placement moved by subtitle safety canvas")
cases+=1
}}
print("PASS",cases,"compiled actual overlay placement preserves194p display canvas separately from cropped subtitle safety, window/fullscreen")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(root/'Sources/gor/Subtitles/SubtitleTiltGeometry.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
