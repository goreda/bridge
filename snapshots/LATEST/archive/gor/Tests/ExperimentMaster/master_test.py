#!/usr/bin/env python3
"""Real menu action body + state/setters under Foundation test UI stubs; not AppKit pixel acceptance."""
from pathlib import Path
import os,re,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=r/'Sources/gor'
sw=os.environ.get('SWIFTC','/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc')
menu=(s/'ThreeDExperimentMenu.swift').read_text()
# Compile the exact production action methods. Only UI declarations/selector syntax are substituted.
ui=menu.replace('#if canImport(AppKit)','').replace('import AppKit','').replace('@MainActor ','').replace('@objc ','').replace('#selector(tap(_:))','"tap"').replace('#endif','').replace('if row.tag == 100, NSApp.currentEvent?.isARepeat == true { return }','')
ui=ui.replace('let o = ThreeDExperimentOptions.live','let o = ThreeDExperimentOptions()')
kernel=(s/'Stereo3DKernel.swift').read_text();flags=kernel[kernel.index('enum Stereo3DExperiments {'):kernel.index('\nfinal class Stereo3DRenderer')]
stubs='''import Foundation
struct Mods:OptionSet {let rawValue:Int;static let command=Mods(rawValue:1),control=Mods(rawValue:2),option=Mods(rawValue:4)}
protocol NSMenuItemValidation {}
class NSMenu {init(title:String){};func addItem(_ x:NSMenuItem){} }
class NSMenuItem {enum State {case on,off};var title:String;var state:State = .off;var submenu:NSMenu?;var target:AnyObject?;var tag=0;var keyEquivalentModifierMask:Mods=[];init(title:String,action:String?,keyEquivalent:String){self.title=title};static func separator()->NSMenuItem{NSMenuItem(title:"",action:nil,keyEquivalent:"")}}
class ThreeDSubtitleDepth {static var experimentalOn=false;static func setExperimental(_ on:Bool){experimentalOn=on}}
'''
main='''import Foundation
func chk(_ b:Bool,_ n:String){precondition(b,n);print("PASS",n)}
let m=ThreeDExperimentMenu.shared
var sent:[String]=[], refresh=0
m.send={sent.append($0)};m.onExperimentChange={refresh+=1}
chk(!m.state.budgetOn && !DepthTemporalEMA.isEnabled() && !ModelDepthEMA.enabled,"default off")
m.setAll(true)
let f=Stereo3DExperiments.snapshot()
chk(m.state.budgetOn && ThreeDSubtitleDepth.experimentalOn && f.fw && f.dof && f.hg && DepthTemporalEMA.isEnabled() && ModelDepthEMA.enabled && DepthModelID.selected() == .dav2_small_coreml,"ALL actual setters on")
chk(refresh==1 && sent.filter{$0.contains("gor3d-budget")}.count==1,"one command one refresh")
chk(m.state.convergence == 0 && m.state.compression == 0.35,"depth preset")
m.setAll(false)
let off=Stereo3DExperiments.snapshot()
chk(!m.state.budgetOn && !ThreeDSubtitleDepth.experimentalOn && !off.fw && !off.dof && !off.hg && !DepthTemporalEMA.isEnabled() && !ModelDepthEMA.enabled && DepthModelID.selected() == .luma_y_prior,"ALL actual setters off")
chk(refresh==2,"off one refresh")
m.setAll(true);m.setAll(true)
chk(Stereo3DExperiments.snapshot().fw && DepthTemporalEMA.isEnabled(),"repeated ON does not toggle off")
Stereo3DExperiments.toggleFloatingWindow()
let row=NSMenuItem(title:"",action:nil,keyEquivalent:"");row.tag=100;m.tap(row)
chk(Stereo3DExperiments.snapshot().fw && DepthTemporalEMA.isEnabled(),"mixed state master goes all ON")
m.tap(row)
chk(!Stereo3DExperiments.snapshot().fw && !DepthTemporalEMA.isEnabled(),"master shortcut action goes all OFF")
var starts=0
let launcher=ThreeDPrepareLauncher(spawn:{ { _,_ in starts+=1;return nil } },report:{_ in })
launcher.settleDelay=0
let film=URL(fileURLWithPath:"/fixture.mp4")
func update(_ e:String){launcher.update(mode:"full_sbs",film:film,playhead:0,info:(24,100),quality:"full",experiments:e,preflightReason:nil)}
update("");update("")
chk(starts==1,"failed prepare does not retry every tick")
update("new-model");update("new-model")
chk(starts==2,"changed prepare identity clears failed latch once")
update("")
chk(starts==3,"returning to baseline clears failed latch once")
let a=URL(fileURLWithPath:"/a"), b=URL(fileURLWithPath:"/b")
chk(RenderContinuity.shouldLoad(showing:1,next:1,seeked:false,showingURL:a,candidateURL:b),"same shot new render reloads")
chk(!RenderContinuity.shouldLoad(showing:1,next:1,seeked:false,showingURL:a,candidateURL:a),"same shot same render no reload")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'UI.swift').write_text(stubs+flags+'\n'+ui);(p/'main.swift').write_text(main)
 subprocess.run([sw,str(p/'UI.swift'),*[str(s/(x+'.swift')) for x in ['ModelDepthEMA','CoreMLDepthRunner','ThreeDExperimentOptions','RenderRevision','PrepareSupport','FovTrackBuilder','VDAStreamRunner','DepthGuards','ThreeDPrepareLauncher']],str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
assert 'keyEquivalent:"e"' in menu and 'master.keyEquivalentModifierMask=[.command,.control,.option]' in menu
assert 'Chord("e", command: true, control: true, option: true)' not in (s/'ThreeDKeymap.swift').read_text()
assert 'evidence=request_only' in menu
print('PASS shortcut declaration and request-only receipts; native AppKit visuals NOT_RUN')
