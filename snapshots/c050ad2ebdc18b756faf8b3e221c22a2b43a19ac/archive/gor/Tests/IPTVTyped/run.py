from pathlib import Path
import subprocess,json,hashlib
import os,shutil
here=Path(__file__).resolve().parent
import tempfile
workspace=tempfile.TemporaryDirectory(prefix='iptv-actual-')
r=Path(workspace.name)
for name in ['pre-IPTVModeController.swift','pre-MPVCommand.swift','PlayerIPTVOperations.swift.fragment']:
 shutil.copy(here/name,r/name)
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
assert swift,'NOT_RUN executable Swift required'
def function(text,sig):
 a=text.index(sig);b=text.index('{',a);depth=1;i=b+1
 while depth:
  depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[a:i]
root=here.parents[1]
actual=(root/'Sources/gor/Modes/IPTVModeController.swift').read_text()
(r/'IPTVModeController.swift').write_text(actual)
realbackend=(root/'Sources/gor/Engine/MPVCommand.swift').read_text()
assert (r/'PlayerIPTVOperations.swift.fragment').read_text().strip() in realbackend
s=(r/'IPTVModeController.swift').read_text();pre=(r/'pre-IPTVModeController.swift').read_text();backend=(r/'PlayerIPTVOperations.swift.fragment').read_text()
setup=function(s,'    private func setupIPTVPanel()').replace('private func','func',1)
resolver=function(pre,'    static func resolveHLSVariant(');assert resolver==function(s,'    static func resolveHLSVariant(')
make=function((r/'pre-MPVCommand.swift').read_text(),'    static func make(')
prefix='''import Foundation
enum MPVCommand {MAKE}
BACKEND
final class NSView {var added:[IPTVPanel]=[];func addSubview(_ panel:IPTVPanel) {added.append(panel)}}
final class SpineUI {var titles:[String]=[];func setTitle(_ value:String) {titles.append(value)}}
final class IPTVPanel {
 struct Mask:OptionSet {let rawValue:Int;static let width=Mask(rawValue:1);static let height=Mask(rawValue:2)}
 var isHidden=false;var autoresizingMask:Mask=[]
 var onPlayURL:((String,String)->Void)?;var onClose:(()->Void)?;var onSwitchURL:((String)->Void)?
 var cleared=0;var shown:[([IPTVModeController.HLSVariant],String)]=[]
 init(frame:CGRect) {}
 func clearQualityVariants() {cleared+=1}
 func showQualityVariants(_ variants:[IPTVModeController.HLSVariant],currentURL:String) {shown.append((variants,currentURL))}
}
final class IPTVModeController {
 struct HLSVariant {let bandwidth:Int;let resolution:String;let url:String}
 static var resolves:[(String,(String,[HLSVariant])->Void)]=[]
 static func resolveHLSVariant(masterURL:String,completion:@escaping (String,[HLSVariant])->Void) {resolves.append((masterURL,completion))}
 var iptvChannelTitle="" {didSet {if iptvChannelTitle.isEmpty {iptvLoadGeneration &+= 1}}}
 var iptvLoadGeneration=0;var hostView:NSView?=NSView();let spineUI=SpineUI();var iptvPanel:IPTVPanel?
 var playback:PlayerIPTVOperations;var closeMusicModeIfActive:()->Void;var applyIPTVProfile:()->Void;var photonEnabled:()->Bool
 func iptvPanelFrame()->CGRect {.zero}
 var toggles=0;func toggleIptvMode() {toggles+=1}
 init(playback:PlayerIPTVOperations,close:@escaping ()->Void,profile:@escaping ()->Void,photon:@escaping ()->Bool) {self.playback=playback;closeMusicModeIfActive=close;applyIPTVProfile=profile;photonEnabled=photon}
SETUP
}
'''.replace('MAKE',make).replace('BACKEND',backend).replace('SETUP',setup)
tests=r'''
var checks=0
func check(_ value:Bool,_ why:String) {checks+=1;precondition(value,why)}
func command(_ line:Substring)->[Any] {(try! JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any])["command"] as! [Any]}
for enabled in [true,false] {
 var batches:[String]=[]
 let ops=PlayerIPTVOperations(batch:{batches.append($0)})
 for path in ["https://example.invalid/live.m3u8","https://example.invalid/a\"b\\c\n雪.m3u8"] {
  ops.load(url:path,photonEnabled:enabled)
  let lines=batches.last!.split(separator:"\n");check(lines.count==3,"one escaped three-line batch")
  check(String(lines[0])==#"{"command":["script-message-to","photon","set-live","true"]}"#,"exact live first bytes")
  check(String(lines[1])=="{\"command\":[\"script-message-to\",\"photon\",\"set-user-enabled\",\"\(enabled ? "true":"false")\"]}","exact enabled second bytes")
  check((command(lines[2]) as NSArray).isEqual(to:["loadfile",path]),"load third exact argv escaping")
  check(!batches.last!.hasSuffix("\n"),"no extra newline")
 }
 check(batches.count==2,"exactly one batch per load")
}
var events:[String]=[],batches:[String]=[],enabled=true
let host=IPTVModeController(playback:PlayerIPTVOperations(batch:{events.append("load");batches.append($0)}),close:{events.append("close")},profile:{events.append("profile")},photon:{events.append("enabled");return enabled})
host.setupIPTVPanel();let panel=host.iptvPanel!
check(panel.isHidden && panel.autoresizingMask==[.width,.height],"panel setup")
check(host.hostView!.added.count==1,"panel attached")
panel.onPlayURL!("master1","first")
check(events==["close"] && batches.isEmpty,"no early load before resolve")
check(host.spineUI.titles==["first"] && panel.cleared==1,"title/variant clear before resolve")
check(IPTVModeController.resolves.last!.0=="master1","resolver URL unchanged")
let stale=IPTVModeController.resolves.last!.1
panel.onPlayURL!("master2","second");let current=IPTVModeController.resolves.last!.1
stale("stale",[]);check(batches.isEmpty,"old generation refused")
let variant=IPTVModeController.HLSVariant(bandwidth:5,resolution:"1080x720",url:"best")
current("best",[variant]);check(events.suffix(3)==["enabled","load","profile"],"admitted callback order")
check(panel.shown.count==1 && panel.shown[0].1=="best","variants shown after admitted load")
check((command(batches.last!.split(separator:"\n")[2]) as NSArray).isEqual(to:["loadfile","best"]),"resolved URL loaded")
panel.onPlayURL!("master3","third");let cancelled=IPTVModeController.resolves.last!.1
host.iptvChannelTitle="";let count=batches.count;cancelled("late",[variant]);check(batches.count==count,"title clear retires generation")
panel.onPlayURL!("plain","");IPTVModeController.resolves.last!.1("plain",[])
check(host.spineUI.titles==["first","second","third"],"empty title not written")
check(panel.shown.count==1,"empty variants no display")
let before=host.iptvLoadGeneration;enabled=false;events=[]
panel.onSwitchURL!("switch")
check(events==["enabled","load","profile"],"switch same order")
check(host.iptvLoadGeneration==before,"switch generation unchanged")
check(String(batches.last!.split(separator:"\n")[1]).contains("false"),"switch reads live preference")
panel.onClose!();check(host.toggles==1,"close unchanged")
print("PASS \(checks) actual IPTV backend/callback checks")
'''
# Product-boundary witness: original host necessarily retains raw serialization.
assert 'MPVCommand.make(["loadfile",' in pre and 'MPVCommand' not in s and '"command"' not in s
legacy=prefix.replace(setup,function(pre,'    private func setupIPTVPanel()').replace('private func','func',1)).replace(' var playback:PlayerIPTVOperations;', ' var batchIPC:(String)->Void {playback.batch}; var playback:PlayerIPTVOperations;')
mutants={'reverse-order':prefix.replace('            MPVCommand.make(["loadfile",url]),','',1).replace('        let payload = [','        let payload = [MPVCommand.make(["loadfile",url]),',1),'stale-generation':prefix.replace('guard let self, self.iptvLoadGeneration == generation else','guard let self else',1),'omit-profile':prefix.replace('                self.applyIPTVProfile()','',1),'drop-variants':prefix.replace('                    self.iptvPanel?.showQualityVariants(variants, currentURL: resolvedURL)','',1),'wrong-enabled':prefix.replace('photonEnabled ? "true" : "false"','photonEnabled ? "false" : "true"',1)}
receipts=[]
for name,code in [('corrected',prefix),('legacy-equivalence',legacy)]+list(mutants.items()):
 src=r/(name+'.swift');src.write_text(code+tests)
 for opt in ['-Onone','-O']:
  binary=r/'test';p=subprocess.run([swift,'-swift-version','5',opt,str(src),'-o',str(binary)],capture_output=True,text=True);assert p.returncode==0,(name,p.stderr)
  p=subprocess.run([str(binary)],capture_output=True,text=True);assert (p.returncode==0)==(name in ['corrected','legacy-equivalence']),(name,p.stdout,p.stderr)
  receipts.append({'case':name,'opt':opt,'exit':p.returncode,'output':p.stdout.strip(),'sha256':hashlib.sha256(src.read_bytes()).hexdigest()})
(r/'receipts.json').write_text(json.dumps(receipts,indent=2));print(json.dumps(receipts,indent=2))
