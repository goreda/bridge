from pathlib import Path
import subprocess,os
r=Path(__file__).resolve().parent
post=r/os.environ.get('SOURCE_DIR','post')
def method(path,signature):
 s=(post/path).read_text();a=s.index(signature);a=s.rfind('\n',0,a)+1;b=s.index('{',a);depth=1;i=b+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return (s[a:i]+'\n').replace('private ','').replace('public ','').replace('@MainActor ','')
pp='Sources/gor/Player/PPController.swift';host='Sources/gor/Engine/GorAVPlayerHost.swift';session='Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift';presenter='Packages/gorav/Sources/GorAVMetalPresenter/core/MetalPresenter.swift'
layout=(r/'LayoutProjection.swift').read_text().split('@main struct Tests')[0]
code=layout+'''
enum EmbeddedRefusal:Error {case unsupportedCommand(String)}
final class CuePresenter {
 var closed=false;let view=Layout()
'''+method(presenter,'public func setSubtitlePosition(_ percent:Double)')+'''
}
final class Session {
 var tornDown=false,fenced=false;var presenter:CuePresenter?=CuePresenter();var subtitlePosition=100.0
'''+method(session,'public func setSubtitlePosition(_ percent:Double)')+'''
}
final class Host {
 var session:Session?=Session();var volumeSessionReady=true;var chrome:Controller?
'''+method(host,'private func applyChromeSubtitlePosition(')+'''
}
final class OSD {var texts=[String]();func showMPVOSD(_ text:String,duration:Double,force:Bool){texts.append(text)}}
enum MPVCommand {static func make(_ values:[Any])->String {""}}
final class SubtitleView {func setSubtitlePosition(_ value:Double,force:Bool){}}
final class Controller {
 let spineUI=OSD();var embeddedSubPosition=100.0
 var embeddedSubtitlePosition:((Double)->String?)?
 var embeddedSubtitleScale:((Double)->String?)?
 var embeddedDelay:((String,Double)->String?)?
 var embeddedSubScale=1.0,embeddedSubDelay=0.0,embeddedAudioDelay=0.0
 var embeddedBackend=true;var pendingSubtitleModePosition:Double?
 let subtitleView=SubtitleView()
 func refuseEmbedded(_ text:String)->Bool {true}
 func queryMenuPayload(_ text:String)->[String:Any]{[:]}
'''+method(pp,'func acceptEmbeddedSubtitlePosition(')+method(pp,'func applyEmbeddedSubtitlePosition(')+method(pp,'func applyEmbeddedSubtitlePositionPreset(')+method(pp,'private func adjustEmbeddedSubtitleProperty(')+method('Sources/gor/Player/PPControllerMenuQueries.swift','func setSubtitlePositionPreset(')+'''
}
@main struct RouteTests {
 static func main(){
  var n=0
  func check(_ x:Bool,_ name:String){n+=1;if !x{fatalError(name)}}
  let c=Controller(),h=Host();h.chrome=c;c.embeddedSubtitlePosition={h.applyChromeSubtitlePosition($0)}
  let s=h.session!,p=s.presenter!
  check(c.applyEmbeddedSubtitlePosition(30),"route accepted")
  check(c.embeddedSubPosition==30 && s.subtitlePosition==30 && p.view.subtitlePosition==30,"all owners committed accepted value")
  for v in [Double.nan,Double.infinity,-1,101] {check(!c.applyEmbeddedSubtitlePosition(v) && c.embeddedSubPosition==30,"invalid preserves")}
  h.volumeSessionReady=false;check(!c.applyEmbeddedSubtitlePosition(20) && c.embeddedSubPosition==30,"host not ready")
  h.volumeSessionReady=true;s.fenced=true;check(!c.applyEmbeddedSubtitlePosition(20) && s.subtitlePosition==30,"session fenced")
  s.fenced=false;s.tornDown=true;check(!c.applyEmbeddedSubtitlePosition(20) && s.subtitlePosition==30,"session torn down")
  s.tornDown=false;p.closed=true;check(!c.applyEmbeddedSubtitlePosition(20) && s.subtitlePosition==30,"presenter closed")
  p.closed=false;p.view.cueLabel.cell!.measured=1000
  check(!c.applyEmbeddedSubtitlePosition(20) && c.embeddedSubPosition==30 && s.subtitlePosition==30,"unplaceable measured block refuses full chain")
  p.view.cueLabel.cell!.measured=40
  check(c.applyEmbeddedSubtitlePosition(0) && c.applyEmbeddedSubtitlePosition(100),"top and reset bottom")
  check(c.adjustEmbeddedSubtitleProperty("sub-pos",delta:-1,reset:false) && c.embeddedSubPosition==99,"relative menu command actual path")
  check(c.adjustEmbeddedSubtitleProperty("sub-pos",delta:0,reset:true) && c.embeddedSubPosition==100,"reset actual path")
  check(c.setSubtitlePositionPreset(25) && c.embeddedSubPosition==25,"absolute preset actual path")
  let saved=s.subtitlePosition;s.presenter=nil
  check(!c.applyEmbeddedSubtitlePosition(20) && s.subtitlePosition==saved,"absent presenter")
  let fresh=CuePresenter();fresh.view.cueLabel.isHidden=true;fresh.view.secondaryCueLabel.isHidden=true;fresh.view.subtitleVideoRect={nil}
  s.presenter=fresh
  check(c.applyEmbeddedSubtitlePosition(20) && fresh.view.subtitlePosition==20,"pre-cue intent without fake measured frame")
  c.embeddedSubtitlePosition=nil;check(!c.applyEmbeddedSubtitlePosition(40) && c.embeddedSubPosition==20,"missing route no false commit")
  print("PASS \\(n) actual controller host session presenter route projection checks; native NOT_RUN")
 }
}
'''
p=r/'RouteProjection.swift';p.write_text(code)
for opt in os.environ.get('OPTIONS','-Onone -O').split():
 c=subprocess.run([os.environ.get('SWIFTC','swiftc'),'-swift-version','5',opt,str(post/'Packages/gorav/Sources/GorAVSubtitles/SubtitleTypography.swift'),str(p),'-o',str(r/'route-tests')],capture_output=True,text=True)
 if c.returncode:raise SystemExit(c.stderr)
 t=subprocess.run([str(r/'route-tests')],capture_output=True,text=True);print(opt,t.stdout,t.stderr)
 if t.returncode:raise SystemExit(t.returncode)
