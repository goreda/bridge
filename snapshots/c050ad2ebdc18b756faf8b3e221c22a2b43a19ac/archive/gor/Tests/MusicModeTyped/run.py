from pathlib import Path
import os,shutil,subprocess,json,hashlib
here=Path(__file__).resolve().parent
import tempfile
workspace=tempfile.TemporaryDirectory(prefix='music-mode-actual-')
r=Path(workspace.name)
for name in ['pre-MusicModeController.swift','PlayerMusicModeOperations.swift.fragment']:shutil.copy(here/name,r/name)
root=here.parents[1]
(r/'MusicModeController.swift').write_bytes((root/'Sources/gor/Modes/MusicModeController.swift').read_bytes())
assert (r/'PlayerMusicModeOperations.swift.fragment').read_text().strip() in (root/'Sources/gor/Engine/MPVCommand.swift').read_text()
swift=os.environ.get('SWIFTC') or shutil.which('swiftc');assert swift
def function(text,sig):
 a=text.index(sig);b=text.index('{',a);depth=1;i=b+1
 while depth:depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[a:i]
new=(r/'MusicModeController.swift').read_text();old=(r/'pre-MusicModeController.swift').read_text();toggle=function(new,'    func toggleMusicMode()');legacy=function(old,'    func toggleMusicMode()')
prefix=r'''import Foundation
var trace:[String]=[]
class NSView {var bounds=CGRect.zero;func addSubview(_ panel:MusicPanel) {trace.append("attach")}}
final class MusicController {func start() {trace.append("start")};func stop() {trace.append("stop-controller")}}
final class MusicPanel {var isHidden=false;var frame=CGRect.zero;var needsLayout=false;func removeFromSuperview() {trace.append("detach")}}
final class SidebarUI {var isListMode=true}
final class SpineUI {func setTitle(_ value:String) {trace.append("title:"+value)}}
enum PPController {static var gorFitScriptActive=false}
enum GorVideoFit {static let openBaselineFraction=0.5,musicExitBaselineFraction=0.38}
BACKEND
final class Host {
 var isMusicMode=false;var musicController:MusicController?=MusicController();var hostView:NSView?=NSView();var musicPanel:MusicPanel?=MusicPanel()
 let sidebarUI=SidebarUI(),spineUI=SpineUI()
 var commands:[String]=[];var sizes:[Double]=[];var marks:[Double]=[];var frames=0,windows=0
 var playback:PlayerMusicModeOperations {PlayerMusicModeOperations(command:ipcCommand)}
 func ipcCommand(_ value:String) {commands.append(value);trace.append("command")}
 func setVideoDisplaySize(_ w:Double,_ h:Double) {precondition(w==h);sizes.append(w);trace.append("size")}
 func markOpeningFitPending(_ x:Double) {marks.append(x);trace.append("mark")}
 func setAppliedVideoFrame(_ x:CGRect) {precondition(x == .zero);frames+=1;trace.append("frame")}
 func setAppliedVideoFrameWindowSize(_ x:CGSize) {precondition(x == .zero);windows+=1;trace.append("window")}
 func panelFrame()->CGRect {CGRect(x:1,y:2,width:3,height:4)}
TOGGLE
}
'''.replace('BACKEND',(r/'PlayerMusicModeOperations.swift.fragment').read_text())
tests=r'''
var checks=0
func check(_ value:Bool,_ why:String) {checks+=1;precondition(value,why)}
for fit in [false,true] {
 PPController.gorFitScriptActive=fit
 let h=Host();trace=[]
 h.toggleMusicMode()
 check(h.isMusicMode,"entry state toggled")
 check(h.sizes==[820],"820 before entry")
 check(h.commands==[#"{"command":["stop"]}"#,#"{"command":["set","vid","auto"]}"#,#"{"command":["set","geometry","820x820"]}"#,#"{"command":["set","keepaspect","no"]}"#],"exact entry bytes/order")
 check(trace==["size","command","command","command","command","start","title:","detach","attach","frame","window"],"entry effects ordered")
 check(h.frames==1 && h.windows==1 && h.marks.isEmpty,"entry reset count")
 check(h.musicPanel!.frame==h.panelFrame() && !h.musicPanel!.isHidden && h.musicPanel!.needsLayout,"panel entry state")
 trace=[];h.commands=[];h.toggleMusicMode()
 let expected=[#"{"command":["stop"]}"#,#"{"command":["set","vid","auto"]}"#]+(fit ? []:[#"{"command":["set","geometry","38%+50%+50%"]}"#])+[#"{"command":["set","keepaspect","yes"]}"#]
 check(h.commands==expected,"exit exact bytes/fit guard")
 check(trace==Array(repeating:"command",count:expected.count)+["size","mark","frame","window","stop-controller","title:","frame","window"],"exit ordered effects")
 check(!h.isMusicMode && h.musicPanel!.isHidden && !h.sidebarUI.isListMode,"exit mode/UI state")
 check(h.marks==[fit ? 0.5:0.38] && h.sizes==[820,0],"exit fit baseline")
 check(h.frames==3 && h.windows==3,"exit resets preserved")
}
for missingHost in [true,false] {
 let h=Host();if missingHost {h.hostView=nil} else {h.musicController=nil};trace=[];h.toggleMusicMode()
 check(trace.isEmpty && h.commands.isEmpty && !h.isMusicMode,"missing prerequisite inert")
}
let h=Host();h.musicPanel=nil;trace=[];h.toggleMusicMode();check(h.isMusicMode && h.commands.count==4,"optional panel unchanged")
print("PASS \(checks) actual MusicMode toggle/command checks")
'''
mutants={'fit-inverted':prefix.replace('if !scriptedFit','if scriptedFit'),'geometry800':prefix.replace('let musicSize = 820','let musicSize = 800'),'wrong-aspect':prefix.replace('"keepaspect","no"','"keepaspect","yes"'),'start-before-enter':prefix.replace('            playback.enter(size:musicSize)\n            mc.start()','            mc.start()\n            playback.enter(size:musicSize)'),'stop-omitted':prefix.replace('            mc.stop()',''),'no-fit-mark':prefix.replace('            markOpeningFitPending(PPController.gorFitScriptActive ? GorVideoFit.openBaselineFraction : GorVideoFit.musicExitBaselineFraction)','')}
correct=prefix.replace('TOGGLE',toggle);legacyCode=prefix.replace('TOGGLE',legacy)
mutants={k:v.replace('TOGGLE',toggle) for k,v in mutants.items()}
# Body mutations must be applied after inserting actual toggle.
mutants['geometry800']=correct.replace('let musicSize = 820','let musicSize = 800')
mutants['start-before-enter']=correct.replace('            playback.enter(size:musicSize)\n            mc.start()','            mc.start()\n            playback.enter(size:musicSize)')
mutants['stop-omitted']=correct.replace('            mc.stop()','')
mutants['no-fit-mark']=correct.replace('            markOpeningFitPending(PPController.gorFitScriptActive ? GorVideoFit.openBaselineFraction : GorVideoFit.musicExitBaselineFraction)','')
records=[]
for name,code in [('corrected',correct),('legacy-equivalence',legacyCode)]+list(mutants.items()):
 src=r/(name+'.swift');src.write_text(code+tests)
 for opt in ['-Onone','-O']:
  p=subprocess.run([swift,'-swift-version','5',opt,str(src),'-o',str(r/'test')],capture_output=True,text=True);assert p.returncode==0,(name,p.stderr)
  p=subprocess.run([str(r/'test')],capture_output=True,text=True);assert (p.returncode==0)==(name in ['corrected','legacy-equivalence']),(name,p.stdout,p.stderr)
  records.append({'case':name,'opt':opt,'exit':p.returncode,'output':p.stdout.strip(),'sha256':hashlib.sha256(src.read_bytes()).hexdigest()})
(r/'receipts.json').write_text(json.dumps(records,indent=2));print(json.dumps(records,indent=2))
assert function(new,'    func showCoverPreview(')==function(old,'    func showCoverPreview(')
assert function(new,'    func hideCoverPreview(')==function(old,'    func hideCoverPreview(')
