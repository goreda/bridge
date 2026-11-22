
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
r=Path(__file__).resolve().parents[2]
base=_sub_read(r/'Tests/PiPSubtitleTypography/run.py');scope={'__file__':str(r/'Tests/PiPSubtitleTypography/run.py')};exec(base[:base.index('with tempfile.TemporaryDirectory()')],scope)
code=scope['program'].split('let view=ViewBoundary()')[0]+'''
let defaults=UserDefaults(suiteName:"mode-test-"+UUID().uuidString)!
SubtitleSizePreference.save(0.65,defaults:defaults)
var state=SubtitleModeScale(normal:0.65,pip:1)
let view=ViewBoundary();view.targetFontSize=30
func transition(_ pip:Bool,_ height:Double) {
 if let scale=state.transition(to:pip) {
  view.subtitleFontScale=scale
  view.bounds.size.height=height
  view.setPictureInPictureTypography(pip)
 }
 let size=pip ? SubtitlePresentation.pipFontSize(userScale:1,windowHeight:height):30
 view.targetFontSize=size;view.applySVFont(CTFont(size,[:]),fontSize:size)
 print("pip=\\(pip) normal=\\(state.normal) pipScale=\\(state.pip) point=\\(view.textLayer.fontSize)")
}
transition(false,900);precondition(view.textLayer.fontSize==19.5)
view.lastSubtitlePosition=90
let normalPosition=view.userPosRatio
transition(true,270);precondition(view.textLayer.fontSize==21.6)
view.userPosRatio=CGPoint(x:0.1,y:0.9);view.lastSubtitlePosition=70
let pipPosition=view.userPosRatio
state.accept(0.5);SubtitleSizePreference.save(0.5,defaults:defaults,pictureInPicture:true);view.subtitleFontScale=0.5
view.applySVFont(CTFont(21.6,[:]),fontSize:21.6);precondition(view.textLayer.fontSize==10.8)
transition(false,1080)
precondition(view.userPosRatio==normalPosition && view.lastSubtitlePosition==90)
let near=SubtitlePresentation.fontSize(userScale:1,proximity:1,pictureInPicture:view.pictureInPictureTypography,windowHeight:1080)
let far=SubtitlePresentation.fontSize(userScale:1,proximity:0,pictureInPicture:view.pictureInPictureTypography,windowHeight:1080)
precondition(near==25 && far==37)
precondition(SubtitlePresentation.sizeAxis(pointerValue:100,enabled:true,pictureInPicture:view.pictureInPictureTypography)==100)
precondition(view.textLayer.fontSize==19.5,"fullscreen uses normal size, not1080*0.08")
precondition(SubtitleSizePreference.restored(defaults:defaults)==0.65,"PiP adjustment cannot overwrite normal preference")
transition(true,270);precondition(view.textLayer.fontSize==10.8)
precondition(view.userPosRatio==pipPosition && view.lastSubtitlePosition==70)
for proximity in [0.0,0.5,1] {
 precondition(SubtitlePresentation.fontSize(userScale:1,proximity:proximity,pictureInPicture:view.pictureInPictureTypography,windowHeight:270)==21.6)
 precondition(SubtitlePresentation.sizeAxis(pointerValue:100,enabled:true,pictureInPicture:view.pictureInPictureTypography)==0)
}
transition(false,900);precondition(view.textLayer.fontSize==19.5)
precondition(state.normal==0.65 && state.pip==0.5)
print("PASS production mode policy + font writer normal->PiP->change->fullscreen->PiP->exit: normal preference unchanged, independent PiP preference, no fullscreen-height PiP font")
'''
# Initial normal state needs the stored scale before first unchanged-mode call.
code=code.replace('let view=ViewBoundary();view.targetFontSize=30','let view=ViewBoundary();view.targetFontSize=30;view.subtitleFontScale=state.normal')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code)
 swiftc_checked([str(_sub_compile_input(r/'Sources/gor/Subtitles/SubtitlePreferences.swift')),str(p/'main.swift')],p/'run');subprocess.run([str(p/'run')],check=True)
a=_sub_read(r/'Sources/gor/App/AppDelegate.swift');c=_sub_read(_pp_split().path(r,'PPController.swift'))
assert 'synchronizeSubtitlePresentation(pictureInPicture:false)' in a[a.index('private func beginMPVFullscreenEntry'):a.index('private func settleMPVFullscreenEntry')]
assert 'synchronizeSubtitlePresentation(pictureInPicture:pictureInPictureActive)' in a[a.index('if mpvRestoreFrame != nil'):a.index('func updateOverlayHitTesting')]
assert 'guard abs(expected-value)<0.000001 else{return}' in c
assert '[subtitle-mode]' in c and 'actual=\\(subtitleView.typographyProbe)' in c
print('PASS actual transition proximity normal near/far25/37 and SIZE axis100 in fullscreen; return-PiP constant21.6 and SIZE axis0, normal/PiP positions restored')
print('PASS source mode receipts at fullscreen entry/settled exit; stale old-mode poll cannot overwrite mode state; actual typography probe logged each transition')

# Exercise the actual controller IPC/late-poll route, not only the pure policy.
source=c
def method(key):
 i=source.index(key);j=source.index('{',i)+1;n=1
 while n:n+=(source[j]=='{')-(source[j]=='}');j+=1
 return '\n'+source[i:j].replace('private func','func')
controller='import Foundation\nclass Renderer {var subtitlePositionProperty=100.0;var scale=0.65;var pip=false;var typographyProbe:[String:Any]{["pointScale":scale,"pip":pip]}\nfunc setSubtitleFontScale(_ value:Double){scale=value}\nfunc setPictureInPictureTypography(_ value:Bool){pip=value}}\nenum Diag {static func log(_ s:String){print(s)}}\nclass Controller {var subtitleModeScale=SubtitleModeScale(normal:0.65,pip:1);var pendingSubtitleModeScale:Double?;var pendingSubtitleModePosition:Double?;let subtitleView=Renderer();var commands:[String]=[]\nfunc ipcCommand(_ s:String){commands.append(s)}\n'+method('    func synchronizeSubtitlePresentation(')+method('    private func acceptSubtitleScale(')+'\n}\nlet c=Controller()\nc.synchronizeSubtitlePresentation(pictureInPicture:true)\nc.acceptSubtitleScale(0.65);precondition(c.subtitleView.scale==1,"late normal poll must not become PiP choice")\nc.acceptSubtitleScale(1);c.acceptSubtitleScale(0.5)\nc.synchronizeSubtitlePresentation(pictureInPicture:false)\nc.acceptSubtitleScale(0.5);precondition(c.subtitleView.scale==0.65,"late PiP poll must not become normal choice")\nc.acceptSubtitleScale(0.65)\nc.synchronizeSubtitlePresentation(pictureInPicture:true);precondition(c.subtitleView.scale==0.5)\nc.synchronizeSubtitlePresentation(pictureInPicture:false);precondition(c.subtitleView.scale==0.65)\nprecondition(c.subtitleModeScale.normal==0.65 && c.subtitleModeScale.pip==0.5)\nprint("PASS actual controller mode IPC + stale-poll guards + renderer routes, normal/PiP size never exchanged")\n'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(controller)
 swiftc_checked([str(_sub_compile_input(r/'Sources/gor/Subtitles/SubtitlePreferences.swift')),str(r/'Sources/gor/Engine/MPVCommand.swift'),str(p/'main.swift')],p/'run');subprocess.run([str(p/'run')],check=True)
