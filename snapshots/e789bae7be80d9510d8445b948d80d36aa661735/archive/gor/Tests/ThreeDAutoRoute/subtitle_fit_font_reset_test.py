#!/usr/bin/env python3
"""Compiled production font policy and committed-frame reset setter with boundary spies."""

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
import tempfile,subprocess,os,sys,traceback
def _fixture_excepthook(t,v,tb):
 print('FIXTURE-FAILURE-TRACEBACK:',flush=True);traceback.print_exception(t,v,tb);traceback.print_exception(t,v,tb,file=sys.stdout)
 sys.exit(1)
sys.excepthook=_fixture_excepthook
def swiftc_checked(args,out):
 r=subprocess.run([os.environ.get('SWIFTC','swiftc'),*args,'-o',str(out)],capture_output=True,text=True)
 if r.returncode:
  print('FIXTURE-COMPILE-FAIL rc=%d:'%r.returncode,' '.join(map(str,args)),flush=True)
  print('--- swiftc stdout ---\n'+r.stdout+'--- swiftc stderr ---\n'+r.stderr,flush=True)
  r.check_returncode()
root=Path(__file__).resolve().parents[2];s=_sub_read(root/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
def method(sig):
 a=s.index(sig);i=s.index('{',a)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private func','func')+'\n'
main='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
struct M {var m41:CGFloat=0};func CATransform3DMakeTranslation(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->M {M(m41:x)}
class Layer {var sublayerTransform=M();var instanceCount=2,mask:Int?=1,masksToBounds=true}
enum PhotonFont {static func buildSVVars(signal0T:Double,signal1T:Double,signal2T:Double)->Int {0};static func ct(vars:Int,size:CGFloat)->Int {0}}
enum SubtitlePresentation {
'''+method('    static func fitFontCompensation(')+method('    static func fontSize(')+method('    static func pipFontSize(')+'''
}
class Probe {
var committedSubtitleFrame:[String:Double]?,committedSubtitleOrigin=CGPoint.zero,committedSubtitleOutput=CGSize.zero
var committedGlyphCompensation=1.0,targetWght=0.0,appliedSize=0.0,targetRota=0.0,targetFontSize=25.0,needsLayout=false,vrSubtitleOn=false
var subtitleTiltReplica=(shift:CGFloat(320),left:CGFloat(2),offset:CGFloat(-4))
let vrSubtitleContainer=Layer(),vrSubtitleReplicator=Layer()
func applySVFont(_ f:Int,fontSize:CGFloat)->Bool{true}
func applyTrackedSubtitleTilt(){}
'''+method('    func setCommittedFilmFrame(')+'''
}
for height in [540.0,1080] {for scale in [0.3,0.5,0.8,1,1.25] {for user in [0.8,1,1.4] {
let p=Probe();p.setCommittedFilmFrame(["scale":scale],origin:.zero,output:CGSize(width:height*16/9,height:height))
let base=SubtitlePresentation.fontSize(userScale:user,proximity:0.4,windowHeight:height)
precondition(abs(base*p.committedGlyphCompensation*scale-base)<1e-10)
p.setCommittedFilmFrame(nil,origin:.zero,output:.zero)
precondition(p.committedGlyphCompensation==1 && p.vrSubtitleContainer.sublayerTransform.m41==0 && p.vrSubtitleReplicator.instanceCount==1 && p.vrSubtitleContainer.mask==nil && !p.vrSubtitleContainer.masksToBounds)
}}}
let a=SubtitlePresentation.fontSize(userScale:1,proximity:0.4,windowHeight:540),b=SubtitlePresentation.fontSize(userScale:1,proximity:0.4,windowHeight:1080)
precondition(a==b)
print("PASS30 compiled production font/reset cases: same physical point size in window/fullscreen, user sub-scale preserved, fit cancels only itself, Off clears replica/mask/matrix")
'''
assert 'subtitleFontScale*committedGlyphCompensation' in s
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main);swiftc_checked([str(p/'main.swift')],p/'test');subprocess.run([str(p/'test')],check=True)
