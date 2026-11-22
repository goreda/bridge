
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
import json,os,subprocess,tempfile,sys,traceback
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
r=Path(__file__).resolve().parents[2];p=_sub_read(_pp_split().path(r,'PPController.swift'));m=_sub_read(r/'Sources/gor/UI/MenuActions.swift');a=_sub_read(r/'Sources/gor/App/AppDelegate.swift');s=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
def method(text,key):
 i=text.index(key);j=text.index('{',i)+1;n=1
 while n:
  n+=(text[j]=='{')-(text[j]=='}');j+=1
 return '\n'+text[i:j].replace('@objc ','').replace('private func','func')+'\n'
base=_sub_read(r/'Tests/PiPSubtitleTypography/run.py');scope={'__file__':str(r/'Tests/PiPSubtitleTypography/run.py')}
exec(base[:base.index('with tempfile.TemporaryDirectory()')],scope)
font=scope['program'].split('let view=ViewBoundary()')[0]
font=font.replace('var pictureInPictureTypography=false','var subtitleDelay=0.0;var lastCueProbeTime:Double?=3;var cleared=0;\nfunc show(text:String,duration:Double,at:Double){precondition(text.isEmpty);cleared+=1}\nvar pictureInPictureTypography=false',1)
font=font.replace('var bounds=CGRect', 'func convert(_ rect:CGRect,to:Int?)->CGRect {rect}\nclass Window {func convertToScreen(_ rect:CGRect)->CGRect{CGRect(x:960-rect.width/2,y:540-rect.height/2,width:rect.width,height:rect.height)}}\nvar window:Window?=Window()\nvar bounds=CGRect',1)
font=font.replace('struct Config {static let fontVariationWithFade=true}','struct Config {static let fontVariationWithFade=true;static let initialScale:CGFloat=1}',1)
font=font.replace('enum PhotonFont {','class NSScreen {static var main:NSScreen?=NSScreen();var frame=CGRect(x:0,y:0,width:1920,height:1080)}\nenum NSEvent {static var mouseLocation=CGPoint(x:960,y:540)}\nenum PhotonFont {',1)
needle='\n}\n'
idx=font.rfind(needle)
font=font[:idx]+method(s,'    func setSubtitleFontScale(')+method(s,'    func resetSubtitleFontSize(')+method(s,'    func setSubtitleDelay(')+method(s,'    func setSubtitlePosition(')+font[idx:]
font+='''
for pip in [false,true] {
 for scale in [0.5,0.9,1.0,1.1,2.0] {
  let v=ViewBoundary();v.setPictureInPictureTypography(pip)
  v.setSubtitleFontScale(scale)
  for distance in stride(from:0.0,through:1200,by:10) {
   let size=SubtitlePresentation.fontSize(userScale:1,proximity:SubtitlePresentation.proximity(distance:distance),pictureInPicture:pip)
   v.targetFontSize=size
   v.applySVFont(CTFont(size,[0:0.4,1:0]),fontSize:size)
   precondition(abs(v.textLayer.fontSize-size*scale)<0.000001,"menu scale multiplies whole proximity envelope")
   v.applyVariationDuringFade()
   precondition(abs(v.textLayer.fontSize-size*scale)<0.000001,"fade cannot discard menu scale")
  }
  v.userScale=2.5;v.resetSubtitleFontSize()
  precondition(v.subtitleFontScale==1 && v.userScale==(pip ? 2.5:1))
  precondition(abs(v.textLayer.fontSize-(pip ? 54 : 25))<0.000001,"reset immediately restores original base")
 }
}
let v=ViewBoundary();v.userPosRatio=CGPoint.zero;v.setSubtitleDelay(0);precondition(v.cleared==0)
v.setSubtitleDelay(2);precondition(v.cleared==1 && v.subtitleDelay==2)
v.setSubtitleDelay(2);precondition(v.cleared==1)
v.setSubtitleDelay(-1);precondition(v.cleared==2)
v.setSubtitlePosition(100);precondition(v.userPosRatio.y==0,"initial poll preserves preexisting layout")
v.setSubtitlePosition(99,force:true);precondition(v.userPosRatio.y==0.99)
v.userPosRatio.y=0.5;v.setSubtitlePosition(99);precondition(v.userPosRatio.y==0.5,"unchanged polling must not undo drag/random position")
v.setSubtitlePosition(99,force:true);precondition(v.userPosRatio.y==0.99,"explicit reset must restore even unchanged mpv position")
for delay in [-2.0,0,2] {
 let w=SubtitleMenuTiming.displayWindow(start:2,end:4,delay:delay)
 precondition(w.start==2+delay && w.end==4+delay)
 precondition(SubtitleMenuTiming.lookupTime(playbackTime:3+delay,delay:delay,external:true)==3)
 precondition(SubtitleMenuTiming.lookupTime(playbackTime:3+delay,delay:delay,external:false)==3+delay)
}
print("PASS actual renderer setters/final font writer/fade/reset:1210 scale/proximity cases, PiP height-based21.6pt at270 default, proportional font adjustment, paused reset, cue invalidation, independent position and exactly-once delayed clocks")
'''
controller='''import Foundation
class View {var scale=1.0;var delay=0.0;var pos=100.0;var resets=0
func setSubtitleFontScale(_ v:Double){scale=v};func resetSubtitleFontSize(){scale=1;resets+=1}
func setSubtitleDelay(_ v:Double){delay=v};func setSubtitlePosition(_ v:Double,force:Bool){pos=v}}
class Spine {var messages:[String]=[];var durations:[Double]=[];func showMPVOSD(_ v:String,duration:Double=3,force:Bool=false){messages.append(v);durations.append(duration);precondition(force && duration==1.5)}}
class IPCClient {
var values=["sub-scale":1.0,"sub-delay":0.0,"sub-pos":100.0,"audio-delay":0.0];var commands:[[Any]]=[];var failure=false
func queryBatch(_ text:String,timeout:Double)->[String]{
var replies:[String]=[]
for line in text.split(separator:"\\n") {
 let o=try! JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any];let c=o["command"] as! [Any];commands.append(c)
 let name=c[0] as! String,key=c[1] as! String
 var r:[String:Any]=["error":failure ? "error":"success"]
 if name=="get_property" {r["data"]=values[key]!}
 else if !failure {let value=(c[2] as! NSNumber).doubleValue;values[key]=name=="add" ? values[key]!+value : value}
 replies.append(String(data:try! JSONSerialization.data(withJSONObject:r),encoding:.utf8)!)
};return replies}
static func parseFirst(_ lines:[String])->[String:Any]{for line in lines{let o=try! JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any];if o["data"] != nil{return o}};return [:]}
}
class Controller {var subtitleModeScale=SubtitleModeScale(normal:1,pip:1);var pendingSubtitleModeScale:Double?;var pendingSubtitleModePosition:Double?;let ipcClient=IPCClient(),subtitleView=View(),spineUI=Spine()
'''+'@discardableResult\n'+method(p,'    func adjustSubtitleProperty(')+method(p,'    func resetSubtitles(')+'''
}
class Menu {var controller:Controller?=Controller()
'''+''.join(method(m,'    @objc func '+name+'(') for name in ['menuSubDelayP','menuSubDelayM','menuSubDelayReset','menuSubSizeUp','menuSubSizeDown','menuSubSizeReset','menuSubUp','menuSubDown','menuSubtitlesReset','menuAudioDelayP','menuAudioDelayM','menuAudioDelayReset'])+'''
}
let menu=Menu(),c=menu.controller!
menu.menuSubSizeUp();precondition(abs(c.subtitleView.scale-1.1)<0.000001)
menu.menuSubSizeDown();menu.menuSubSizeReset();precondition(c.subtitleView.scale==1 && c.subtitleView.resets==1)
menu.menuSubDelayP();precondition(c.subtitleView.delay==0.1 && c.spineUI.messages.last=="subtitle delay: +0.1s")
menu.menuSubDelayM();menu.menuSubDelayM();precondition(c.subtitleView.delay == -0.1)
menu.menuSubDelayReset();precondition(c.subtitleView.delay==0 && c.spineUI.messages.last=="subtitle delay: +0.0s")
menu.menuSubUp();precondition(c.subtitleView.pos==99);menu.menuSubDown();precondition(c.subtitleView.pos==100)
let initialAudio=c.ipcClient.values["audio-delay"]!
menu.menuAudioDelayP();precondition(c.ipcClient.values["audio-delay"]==initialAudio+0.1 && c.spineUI.messages.last=="audio delay: +0.1s")
menu.menuAudioDelayM();menu.menuAudioDelayReset();precondition(c.ipcClient.values["audio-delay"]==0)
menu.menuSubSizeUp();menu.menuSubDelayP();menu.menuSubUp();menu.menuSubtitlesReset()
precondition(c.ipcClient.values["sub-scale"]==1 && c.ipcClient.values["sub-delay"]==0 && c.ipcClient.values["sub-pos"]==100)
precondition(c.spineUI.messages.last=="subtitles reset")
c.ipcClient.failure=true;menu.menuSubDelayP();precondition(c.spineUI.messages.last=="subtitle control unavailable" && c.subtitleView.delay==0)
print("PASS actual menu handlers -> canonical mpv command/readback -> renderer and app OSD; plus/minus/reset, position, failure cannot report success")
print("COMMANDS "+String(data:try! JSONSerialization.data(withJSONObject:c.ipcClient.commands),encoding:.utf8)!)
'''
with tempfile.TemporaryDirectory() as tmp:
 t=Path(tmp)
 for name,program in [('font',font),('controller',controller)]:
  program=program.replace('import Foundation','import Foundation\n#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif',1)
  d=t/name;d.mkdir();(d/'main.swift').write_text(program)
  files=[str(d/'main.swift')]
  if name=='controller':
   commandSource=_sub_read(r/'Sources/gor/Engine/MPVCommand.swift')
   commandSource='import Foundation\n'+commandSource[commandSource.index('enum MPVCommand {'):commandSource.index('// Backend admission seam.')]
   (d/'Command.swift').write_text(commandSource)
   files=[str(d/'Command.swift'),str(_sub_compile_input(r/'Sources/gor/Subtitles/SubtitlePreferences.swift'))]+files
  swiftc_checked(files,d/'run')
  result=subprocess.check_output([str(d/'run')],text=True)
  print(result.split('COMMANDS ')[0].strip())
  if 'COMMANDS ' in result:print('COMMANDS',result.split('COMMANDS ')[1].strip())
assert 'subtitle font size reset' in a and 'reset subtitles' in a
assert 'key: String(UnicodeScalar(NSRightArrowFunctionKey)!)' in a
assert 'key: String(UnicodeScalar(NSLeftArrowFunctionKey)!)' in a
for prop in ['sub-scale','sub-delay','sub-pos']:
 assert p.count('"'+prop+'"')>=5
assert 'cueStart:window.start,cueEnd:window.end' in p
assert 'SubtitleMenuTiming.lookupTime(' in s
print('PASS integration: font reset adjacent, real AppKit arrow key equivalents, fast polling + property observations, mpv cue window vs external-cue delay clock; no double delay')
sp=_sub_read(r/'Sources/gor/UI/SpineUI.swift')
assert 'guard force || alphaValue > 0.1' in sp and 'withTimeInterval: duration' in sp
assert 'duration:1.5,force:true' in p
print('Linux only; no native AppKit menu-click/CoreText bitmap acceptance')

# Execute production track selection against wire/view doubles.
trackProgram='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
class NSMenuItem {var representedObject:Any?}
struct Track {let id:Int}
enum NativeTrackMenu {
 static func rows(_ list:[[String:Any]],type:String)->[Track] {list.compactMap{($0["type"] as? String)==type ? ($0["id"] as? Int).map{Track(id:$0)}:nil} + [Track(id:-1)]}
 static func property(_ type:String)->String {type=="audio" ? "aid":type=="video" ? "vid":"sid"}
}
class Controller {
 class View {var isHidden=true};var subtitleView=View(),sent:[String]=[]
 func nativeTrackSnapshot()->(path:String,tracks:[[String:Any]]) {("movie",[["id":5,"type":"sub"],["id":2,"type":"audio"]])}
 func ipcCommand(_ s:String){sent.append(s)}
}
class App {var controller:Controller?=Controller()
'''+method(m,'    @objc func menuSelectTrack(')+'''
}
let app=App(),item=NSMenuItem();item.representedObject=["type":"sub","id":"5","path":"movie"]
app.menuSelectTrack(item);let c=app.controller!
let commands=c.sent.map{try! JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}.map{$0["command"] as! [Any]}
precondition(commands.count==3 && commands[0][1] as? String=="sid")
precondition(commands[1][1] as? String=="sub-visibility" && commands[1][2] as? Bool==false)
precondition(commands[2][1] as? String=="secondary-sub-visibility" && commands[2][2] as? Bool==false)
precondition(!c.subtitleView.isHidden)
let count=c.sent.count;item.representedObject=["type":"sub","id":"5","path":"old"];app.menuSelectTrack(item);precondition(c.sent.count==count)
print("PASS actual menu selection: gor renderer, both native sources off, stale-file pick rejected")
'''
spine=_sub_read(r/'Sources/gor/UI/SpineUI.swift')
# Use method extractor on the override, then remove AppKit override at the seam.
scrollMethod=method(spine,'    override func scrollWheel(with e: NSEvent)').replace('override ','')
scrollProgram='''import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
struct NSEvent {var scrollingDeltaY:CGFloat;var hasPreciseScrollingDeltas:Bool}
class ScrollFixture {
var ROW:CGFloat=20,scrollAccum:CGFloat=0,topIndex=0,totalRows=40
var frame=CGRect(x:0,y:0,width:200,height:100)
func layoutRows(){}
'''+scrollMethod+'''
}
let wheel=ScrollFixture();wheel.scrollWheel(with:.init(scrollingDeltaY:-1,hasPreciseScrollingDeltas:false));precondition(wheel.topIndex>0)
for _ in 0..<100 {wheel.scrollWheel(with:.init(scrollingDeltaY:-1,hasPreciseScrollingDeltas:false))};precondition(wheel.topIndex==35)
for _ in 0..<100 {wheel.scrollWheel(with:.init(scrollingDeltaY:1,hasPreciseScrollingDeltas:false))};precondition(wheel.topIndex==0)
let pad=ScrollFixture();pad.scrollWheel(with:.init(scrollingDeltaY:-2,hasPreciseScrollingDeltas:true));precondition(pad.topIndex==0)
pad.scrollWheel(with:.init(scrollingDeltaY:-8,hasPreciseScrollingDeltas:true));precondition(pad.topIndex==1)
print("PASS actual dropdown scroll: line wheel and precise pixels, reach final row and return, clamp")
'''
for name,source in [('track-selection',trackProgram),('dropdown-scroll',scrollProgram)]:
 with tempfile.TemporaryDirectory() as td:
  folder=Path(td);(folder/'main.swift').write_text(source)
  swiftc_checked([str(folder/'main.swift')],folder/'test')
  subprocess.run([str(folder/'test')],check=True)
fetch=p[p.index('    func fetchTrackList('):p.index('    // MARK: - Commands',p.index('    func fetchTrackList('))]
assert 'trackListCache' not in fetch and 'self.currentFilePath==requestedPath' in fetch
assert p.index('if spineUI.scrollTrackDropdownIfNeeded(with:event)')<p.index('        if vrModeEnabled {',p.index('if spineUI.scrollTrackDropdownIfNeeded(with:event)'))
assert 'self.onSubVisibilityChanged?(true)' in spine
print('PASS fresh track query on every open; stale async rejection; dropdown before VR wheel; spine selects gor')

# Native AppKit pixels of the actual dropdown layout. Text/row paint is a simple
# boundary; the production populate, clipping and scroll methods are unmodified.
if sys.platform=='darwin':
 dropdown=spine[spine.index('final class DropdownList:'):spine.index('// ================================================================\n//  DropRow - dropdown row')]
 native='''import AppKit
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
enum PhotonFont {
static let chromeLineH:CGFloat=24,chromePad:CGFloat=4,chromeCharW:CGFloat=8,chromeGap:CGFloat=4
static func chromeNs()->NSFont{.monospacedSystemFont(ofSize:15,weight:.regular)}
}
final class DropRow:NSView {
let title:String;var onTap:((Int)->Void)?,onHoverEnter:(()->Void)?,onHoverExit:(()->Void)?
init(text:String,idx:Int,height:CGFloat){title=text;super.init(frame:.zero)}
required init?(coder:NSCoder){fatalError()}
static func makeLiveCaptionRow(showBullet:Bool,idx:Int,height:CGFloat,showLabel:Bool,model:String,language:String?)->DropRow{DropRow(text:"live",idx:idx,height:height)}
func setToggleStyle(){};func setEnabled(_ b:Bool){};func setSelected(_ b:Bool){};func setDimmed(_ b:Bool){};func setBulletOpacity(_ v:CGFloat){};func addBullet(height:CGFloat){};func removeBullet(){};func setLiveCaptionLabel(model:String,language:String?,showLabel:Bool){}
override func draw(_ rect:NSRect){NSColor(calibratedWhite:0.12,alpha:1).setFill();bounds.fill();(title as NSString).draw(at:NSPoint(x:8,y:4),withAttributes:[.font:PhotonFont.chromeNs(),.foregroundColor:NSColor.white])}
}
'''+dropdown+'''
let root=NSView(frame:NSRect(x:0,y:0,width:480,height:288))
let drop=DropdownList(frame:.zero);root.addSubview(drop)
drop.populate((1...40).map{(id:$0,title:"Subtitle track \\($0)")},type:"sub",maxH:288)
drop.frame.origin=.zero
func capture(_ name:String){root.layoutSubtreeIfNeeded();let rep=root.bitmapImageRepForCachingDisplay(in:root.bounds)!;root.cacheDisplay(in:root.bounds,to:rep);try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]+"/"+name+".png"))}
capture("dropdown-first")
let evt=CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:1,wheel1:-100,wheel2:0,wheel3:0)!
drop.scrollWheel(with:NSEvent(cgEvent:evt)!)
precondition(drop.subviews.compactMap{$0 as? DropRow}.filter{!$0.isHidden}.contains{$0.title=="Subtitle track 40"})
capture("dropdown-last")
print("PASS native actual AppKit dropdown clipping and wheel reaches final track; paint stub, not font acceptance")
'''
 with tempfile.TemporaryDirectory() as td:
  folder=Path(td);(folder/'main.swift').write_text(native.replace('origin=.zero','origin = .zero'))
  swiftc_checked([str(folder/'main.swift')],folder/'test')
  subprocess.run([str(folder/'test'),os.environ['GOR_SUBTITLE_PIXEL_DIR']],check=True)
