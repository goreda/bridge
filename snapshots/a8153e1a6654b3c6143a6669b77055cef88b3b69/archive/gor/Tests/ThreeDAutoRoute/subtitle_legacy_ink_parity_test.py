#!/usr/bin/env python3
"""Compile actual legacy ink-metric selector with typography boundary spies, not CoreText."""

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
import tempfile,subprocess,os
root=Path(__file__).resolve().parents[2];s=_sub_read(root/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
a=s.index('    private func legacyOverlayInkFrame(');i=s.index('{',a)+1;d=1
while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
method=s[a:i].replace('private func','func')
main='''import Foundation
class NSFont {var pointSize:CGFloat;var fontDescriptor:Int=7;init(_ size:CGFloat){pointSize=size};init?(descriptor:Int,size:CGFloat){pointSize=size;fontDescriptor=descriptor}}
class Layer {var frame=CGRect(x:20,y:30,width:100,height:40)}
struct Layout {var size:CGSize}
class Probe {
var committedGlyphCompensation=1.0,baseSize:CGFloat=25,userPosRatio=CGPoint(x:0.5,y:0.9),renderedText="Fit text"
var bounds=CGRect(x:0,y:0,width:480,height:270);let textLayer=Layer()
func resolvedFont()->NSFont {NSFont(baseSize*committedGlyphCompensation)}
func wrappingWidth(font:NSFont)->CGFloat {bounds.width/2}
func horizontalMargin(font:NSFont,left:Bool)->CGFloat {font.pointSize*0.5}
func flush(forRatioX x:CGFloat)->CGFloat {x}
func placement(text:String,font:NSFont,width:CGFloat,flush:CGFloat,ratio:CGPoint,useCache:Bool)->(layout:Layout,frameY:CGFloat) {(Layout(size:CGSize(width:font.pointSize*4,height:font.pointSize*2)),bounds.height*ratio.y-font.pointSize*2)}
'''+method+'''
}
var n=0
for size in [CGSize(width:480,height:270),CGSize(width:960,height:540)] {for ratio in [0.0,0.5,1] {for comp in [0.8,1.25,2,3] {
let p=Probe();p.bounds.size=size;p.userPosRatio.x=ratio
let font=NSFont(p.baseSize),width=p.wrappingWidth(font:font),placed=p.placement(text:p.renderedText,font:font,width:width,flush:ratio,ratio:p.userPosRatio,useCache:false)
let x=ratio<0.1 ? p.horizontalMargin(font:font,left:true):ratio>0.9 ? p.bounds.width-width-p.horizontalMargin(font:font,left:false):p.horizontalMargin(font:font,left:true)+max(0,p.bounds.width-width-p.horizontalMargin(font:font,left:true)-p.horizontalMargin(font:font,left:false))*ratio
let expected=CGRect(x:x,y:placed.frameY,width:placed.layout.size.width,height:placed.layout.size.height)
p.textLayer.frame=expected;p.committedGlyphCompensation=comp
precondition(p.legacyOverlayInkFrame()==expected,"counter-fit font changed194p UI ink metric")
n+=1
}}}
print("PASS",n,"compiled actual legacy ink selector cases:194p metrics independent of subtitle counter-fit glyph size;window/fullscreen,left/center/right;CoreText NOT_RUN")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
