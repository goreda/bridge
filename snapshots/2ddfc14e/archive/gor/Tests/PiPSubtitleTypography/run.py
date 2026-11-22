
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
import os,subprocess,tempfile,sys,traceback
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
root=Path(__file__).resolve().parents[2]
s=_sub_read(root/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');a=_sub_read(root/'Sources/gor/App/AppDelegate.swift')
def method(signature):
 b=s.index(signature);i=s.index('{',b)+1;n=1
 while n:
  if s[i]=='{':n+=1
  if s[i]=='}':n-=1
  i+=1
 return s[b:i].replace('private func','func')
actual=s[s.index('enum SubtitlePresentation {'):]
program='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
final class CTFont {let size:CGFloat;let vars:[Int:Double];init(_ size:CGFloat,_ vars:[Int:Double]){self.size=size;self.vars=vars}}
func CTFontCreateCopyWithAttributes(_ font:CTFont,_ size:CGFloat,_ matrix:Int?,_ attrs:Int?)->CTFont{CTFont(size,font.vars)}
enum PhotonFont {
static func buildSVVars(signal0T:Double,signal1T:Double,signal2T:Double)->[Int:Double]{[0:signal0T,1:signal1T,2:signal2T]}
static func ct(vars:[Int:Double],size:CGFloat)->CTFont{CTFont(size,vars)}
}
enum CATransaction {static func begin(){};static func commit(){};static func setDisableActions(_ value:Bool){}}
final class Layer {var font:CTFont?;var fontSize:CGFloat=10;func setNeedsDisplay(){}}
'''+actual+'''
class ViewBoundary {
var bounds=CGRect(x:0,y:0,width:480,height:270)
var subtitleFontScale=1.0,committedGlyphCompensation=1.0
var pictureInPictureTypography=false
var userPosRatio=CGPoint(x:0.5,y:1);var lastSubtitlePosition:Double?;var normalSubtitlePosition:(ratio:CGPoint,property:Double?)?;var pipSubtitlePosition:(ratio:CGPoint,property:Double?)?
var normalTypographyBeforePiP:(fontSize:Double,size:Double)?
var targetFontSize=11.0;var targetSize=70.0;var targetWght=0.4;var targetRota=0.0
var appliedSize=70.0;var appliedRota=0.0;var userScale:CGFloat=1;var needsLayout=false
var textLayer=Layer();var frozen=true;var commits=0
var lastAppliedRequestedFont:CTFont?,lastAppliedQuantizedSize:CGFloat = -1
var fadeProgress=0.5
struct Config {static let fontVariationWithFade=true}
func unfreezeOutgoingGeometry(){frozen=false}
func refreshTextLayerString(){commits+=1}
'''+method('    func setPictureInPictureTypography(')+'\n'+method('    private func applySVFont(')+'\n'+method('    private func applyVariationDuringFade(')+'''
}
let view=ViewBoundary()
view.setPictureInPictureTypography(true)
precondition(view.textLayer.fontSize==21.6 && view.appliedSize==0 && !view.frozen && view.needsLayout)
precondition(view.textLayer.font!.size==21.6 && view.textLayer.font!.vars[1]==0)
let oldCommits=view.commits
view.setPictureInPictureTypography(true);precondition(view.commits==oldCommits)
for scale in [0.1,0.25,1.0,2.0,4.0] {
 view.userScale=scale
 let expected=SubtitlePresentation.pipFontSize(userScale:scale)
 for pointer in stride(from:0.0,through:3000.0,by:5.0) {
  let proximity=SubtitlePresentation.proximity(distance:pointer)
  let pip=SubtitlePresentation.fontSize(userScale:scale,proximity:proximity,pictureInPicture:true)
  precondition(pip==expected && pip>=21.6)
  precondition(SubtitlePresentation.sizeAxis(pointerValue:pointer,enabled:true,pictureInPicture:true)==0)
  let normal=SubtitlePresentation.fontSize(userScale:scale,proximity:proximity)
  let original=max(1,25*scale+12*(1-pow(proximity,2.2)*scale))
  precondition(normal==original)
  view.applySVFont(CTFont(1,[1:pointer]),fontSize:1)
  precondition(view.textLayer.fontSize==expected && view.textLayer.font!.size==expected)
  precondition(view.textLayer.font!.vars[1]==0)
  view.targetFontSize=1;view.targetSize=pointer
  view.applyVariationDuringFade()
  precondition(view.textLayer.fontSize==expected && view.appliedSize==0)
 }
}
for height in [150.0,200,270,400,600] {
 view.bounds.size.height=height;view.userScale=1
 view.applySVFont(CTFont(1,[:]),fontSize:1)
 precondition(view.textLayer.fontSize==max(12,height*0.08))
}
view.setPictureInPictureTypography(false)
precondition(view.textLayer.fontSize==11 && view.textLayer.font!.vars[1]==70)
precondition(view.normalTypographyBeforePiP==nil)
for fit in [0.3,0.5,0.8,1.0,1.25] {for subScale in [0.65,1.0,1.4] {
 view.committedGlyphCompensation=SubtitlePresentation.fitFontCompensation(scale:fit)
 view.subtitleFontScale=subScale
 view.applySVFont(CTFont(30,[:]),fontSize:30)
 precondition(abs(Double(view.textLayer.fontSize)*fit-30*subScale)<1e-10)
 precondition(view.textLayer.font!.size==view.textLayer.fontSize)
}}
view.committedGlyphCompensation=1
print("PASS15 actual production font-writer counter-fit cases: physical glyph size and user scale preserved")
print("PASS production policy + setter/font-write/fade methods:3005 pointer/scale cases; PiP height-based21.6pt-at270, constant independent of mouse/app activation; normal formula unchanged; paused entry immediate; outgoing ink unfrozen/reflowed; exit restores prior normal state")
'''
with tempfile.TemporaryDirectory() as t:
 t=Path(t);(t/'main.swift').write_text(program)
 swiftc_checked([str(t/'main.swift')],t/'run')
 subprocess.run([str(t/'run')],check=True)
assert 'proximity:p,pictureInPicture:pictureInPictureTypography,windowHeight:Double(bounds.height))' in s
assert 'if pictureInPictureTypography {' in method('    override func layout(')
assert 'windowHeight*0.08' in s
assert 'sizeAxis(pointerValue:rawSize,enabled:Config.axisSizeEnabled,pictureInPicture:pictureInPictureTypography)' in s
assert 'ctrl.synchronizeSubtitlePresentation(pictureInPicture:pictureInPictureActive && !windowGeometryTransitionActive)'  in a
assert 'controller?.synchronizeSubtitlePresentation(pictureInPicture:pictureInPictureActive && !windowGeometryTransitionActive)' in a[a.index('didSet {'):a.index('private weak var cropDetectMenuItem')]
print('PASS source mode routing: PiP enter/exit + controller replacement; no app-active, hover or control visibility dependency; window height drives PiP only in PiP typography policy')
print('Linux only: AppKit/CoreText painting and installed PiP window pixels unverified; boundary spies test production writes, not native rendering')
