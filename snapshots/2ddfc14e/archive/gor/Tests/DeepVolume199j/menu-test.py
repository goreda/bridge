import json, subprocess,os,tempfile,re,argparse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--allow-failure',action='store_true');a=p.parse_args();s=a.source.read_text();r=Path(__file__).parent;a.out.mkdir(parents=True,exist_ok=True)
def decl(marker):
 b=s.index(marker);i=s.index('{',b)+1;depth=1
 while depth:depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[b:i]
# Same Foundation pure types and container double as the geometry driver.
head='''import Foundation
struct DZCFile {static var planes:[[UInt16]]=[];init?(url:URL){};var count:Int{Self.planes.count};func plane(_ i:Int)->[UInt16]?{Self.planes[i]}}
enum RenderPrefs {static let modes:Set<String>=["off","sbs","over_under","anaglyph","vr180"]}
enum ThreeDSubtitleDepth {struct RenderParams:Equatable {var ipd:Double,convergence:Double?,zNear:Double?}
'''+decl('    static func params(ipdM:')+'\n}\n'
markers=['struct ShotComfort:','struct ShotComfortSpan:','enum ShotDeepGeometry {','enum ShotComfortShot {','struct ThreeDExperimentOptions:','struct RenderPrefsValue:','enum Stereo3DExperiments {','enum OutputMode:']
text=head+'\n'.join(decl(m) for m in markers)+'\n'+(r/'host-stubs.swift').read_text()
text+='\nenum ActualRenderKey {\n'+decl('    static func key(_ p:')+'\n}\n'
# Only compile adaptations: ObjC selectors/attributes cannot run on Linux, live
# snapshot is taken out of its Metal conditional. No key/menu body rewrite.
menu=decl('@MainActor final class ThreeDExperimentMenu:')
menu=re.sub(r'#selector\(tap\(_:\)\)', 'nil',menu).replace('@objc ','')
text+='\n'+menu+'\nextension ThreeDExperimentOptions {\n'+decl('    static var live: ThreeDExperimentOptions')+'\n}\n'
text+='''
var failures=0,checks=0
func check(_ value:Bool,_ label:String){checks+=1;if !value {failures+=1;print("FAIL "+label)}}
@MainActor func menuChecks(){
 let menu=ThreeDExperimentMenu();var invalidations=0;menu.onExperimentChange={invalidations+=1};let host=NSMenu(title:"test");menu.install(in:host)
 let rows=host.items[0].submenu!.items;check(rows.filter{$0.tag==13}.count==1 && rows.first{$0.tag==13}!.title=="Deeper volume","row13 installed once")
 let master=rows.first{$0.tag==100}!,deep=rows.first{$0.tag==13}!,dof=rows.first{$0.tag==8}!
 menu.setAll(true);_ = menu.validateMenuItem(master);_ = menu.validateMenuItem(deep);_ = menu.validateMenuItem(dof)
 check(master.state == .on && deep.state == .on && dof.state == .on,"master includes deep, row8 selected")
 check(ThreeDExperimentOptions.live.deepVolume && !ThreeDExperimentOptions.live.renderOptions.depthOfField,"live snapshot deep and DOF override")
 menu.tap(deep);_ = menu.validateMenuItem(master);_ = menu.validateMenuItem(deep);_ = menu.validateMenuItem(dof)
 check(master.state == .off && deep.state == .off && dof.state == .on,"deep toggle breaks allOn, leaves row8")
 menu.tap(master);_ = menu.validateMenuItem(master);check(master.state == .on && Stereo3DExperiments.snapshot().deep,"master restores deep")
 menu.setAll(false);_ = menu.validateMenuItem(master);_ = menu.validateMenuItem(deep);check(master.state == .off && deep.state == .off && !ThreeDExperimentOptions.live.deepVolume,"master off clears deep")
 check(invalidations==4,"one invalidation per action")
}
MainActor.assumeIsolated {menuChecks()}
for convergence:Double? in [nil,1.5,3] {for strength in [0.25,1,2] {for mode in ["sbs","vr180","anaglyph"] {
 var p=RenderPrefsValue();p.mode=mode;p.depthScale=strength;p.convergenceM=convergence
 let off=ActualRenderKey.key(p,eyeN:1080,codec:.hevc,swap:false,options:ThreeDExperimentOptions())
 let deep=ActualRenderKey.key(p,eyeN:1080,codec:.hevc,swap:false,options:ThreeDExperimentOptions(deepVolume:true))
 check(off != deep,"deep always changes real render key")
 if convergence == nil {check(deep.replacingOccurrences(of:"exp-deep2|",with:"")==off,"automatic key differs only deep token")}
 else {check(off.contains("fixed|ipd") && deep.contains("comfort|ipd"),"explicit convergence changes fixed to comfort identity")}
 let expected="v5|span-p5p95|dibr_golden|"+(convergence == nil ? "comfort|ipd0.063|sf\\(min(strength,1.0))":"fixed|ipd\\(p.effectiveIPD)")+"|\\(OutputMode.parse(p.mode)!.rawValue)|\\(convergence.map{String($0)} ?? "nil")|1080|hevc|false|75.0|true"
 check(off==expected,"off exact prior key")
}}}
print("SUMMARY \\(checks) checks \\(failures) failures; extracted menu+key with host doubles")
exit(failures==0 ? 0:1)
'''
for mode in ['-Onone','-O']:
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);(root/'main.swift').write_text(text);c=subprocess.run([os.environ['SWIFTC'],'-swift-version','5',mode,str(root/'main.swift'),'-o',str(root/'test')],capture_output=True,text=True);(a.out/('compile'+mode+'.log')).write_text(c.stdout+c.stderr);assert c.returncode==0,c.stderr
  q=subprocess.run([str(root/'test')],capture_output=True,text=True,timeout=15);(a.out/('run'+mode+'.log')).write_text(q.stdout+q.stderr);print(mode,q.stdout)
  if not a.allow_failure:assert q.returncode==0
