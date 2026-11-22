#!/usr/bin/env python3
"""Current store-applier blink lifecycle, extracted verbatim. No camera or AppKit.
Historical main.swift covers the retired pre-store entry/default policy and is not current acceptance.
"""
import importlib.util as _iu
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
_spec=_iu.spec_from_file_location('blink_route_sections',root/'Tests/Structure/section_source.py')
_sections=_iu.module_from_spec(_spec);_spec.loader.exec_module(_sections)
def block(marker):
 s=_sections.host_text(root,marker)
 assert s.count(marker)==1,marker
 a=s.index(marker);b=s.index('{',a);depth=1;e=b+1
 while depth:
  if s[e]=='{':depth+=1
  elif s[e]=='}':depth-=1
  e+=1
 return s[a:e]
header='''import Foundation
struct HeadPose {}
final class HeadTracker {
 static let shared=HeadTracker()
 static var poseHoldLock=true
 var blinkLogEnabled=false, simulatedPoseRunning=false
 var onBlinkIndicator:Any?,onBlinkDetected:Any?,onBlinkControl:Any?
 var onEyeClosure:((Double,Double,Bool)->Void)?,onEyeCommand:((EyeGestureCommands.Command)->Void)?,onPoseUpdate:((HeadPose)->Void)?
 var blinkSessionID="probe"
 var consumers=0,startCalls=0,stopCalls=0,poseSessionStarts=0
 var owners=Set<Int>()
 func beginPoseSession(){poseSessionStarts+=1}
 func start(owner:Int){precondition(owners.insert(owner).inserted);consumers+=1;startCalls+=1}
 func stop(owner:Int){precondition(owners.remove(owner) != nil);precondition(consumers>0);consumers-=1;stopCalls+=1}
 func startSimulatedPose(){simulatedPoseRunning=true}
 func stopSimulatedPose(){simulatedPoseRunning=false}
 func flushBlinkSummary(osd:String?){}
}
enum NSEvent {static var modifierFlags:Set<Flag>=[];enum Flag {case command,control}}
enum GeomTrace {
 static var handler:((String,String)->Void)?
 static func beginBlinkLog(session:String,_ h:@escaping(String,String)->Void){handler=h}
}
enum IntentionalEyeClosure {static var analog=false}
enum EyeGestureCommands {static var robust=false,cadenceAdaptive=false;enum Command {case seek(Int),playPause}}
enum ThreeDRouteEnvelope {static let messages=Set<String>()}
enum Diag {static func log(_ s:String){}}
final class ThreeDStore {
 static let shared=ThreeDStore()
 enum Effect {case blink,head};enum Value {case bool(Bool)}
 enum Action {case setEffect(Effect,Value)}
 var actions=0
 func dispatch(_ a:Action){actions+=1}
 func recordAppliedCommand(_ s:String){}
}
'''
methods=['func setHeadTrackingEnabled(', 'func setBlinkControlEnabled(', 'private func blinkControlDidStop(', 'private func updateCaptureConsumers()', 'static var blinkCameraAllowed:', 'private func showBlinkOSD(', 'func sendRaw(_ original: String)']
program=header+block('enum BlinkCommandRoute {')+'\n'+block('enum CaptureConsumerRules {')+'''
final class Probe {
 var loadedVideoActive=false,vrModeEnabled=false,headTrackingEnabled=false
 var headTrackingCameraActive=false,headOwnsRealCameraConsumer=false,blinkCameraActive=false
 var applyingStore=true;var routeRevision=1;var blinkControlPreferred=false;var headTrackingPreferred=false
 var onExplorableSurface:(()->Void)?
 func resetOrientation(){}
 var onSubtitleTilt:((Double,Double)->Void)?,onUITilt:((Double)->Void)?
 var commands=[String]()
 func ipcCommand(_ s:String){commands.append(s)}
 func traceCameraState(_ s:String){}
 func refreshToolsActive(){}
 func applyHeadPose(_ pose:HeadPose){}
 func reconcile(){updateCaptureConsumers()}
'''+ '\n'.join(block(m) for m in methods)+'''
}
func check(_ ok:Bool,_ name:String){precondition(ok,name);print("PASS "+name)}
let p=Probe(),t=HeadTracker.shared
p.loadedVideoActive=true
_ = p.setBlinkControlEnabled(true,osd:false,remember:false)
check(t.blinkLogEnabled && t.onEyeClosure != nil && t.onEyeCommand != nil,"applier installs closure/seek callbacks")
let camera=Probe.blinkCameraAllowed
check(t.consumers == (camera ? 1:0),"loaded paused film gets blink consumer unless no-camera test mode")
p.vrModeEnabled=false;p.reconcile()
check(t.blinkLogEnabled && t.consumers == (camera ? 1:0),"projection OFF does not stop independent blink")
p.setHeadTrackingEnabled(true,remember:false)
check(t.poseSessionStarts==1,"new head consumer seeds its own baseline while blink camera stays alive")
p.setHeadTrackingEnabled(true,remember:false);check(t.poseSessionStarts==1,"unchanged head consumer does not reset baseline repeatedly")
let headConsumer=ProcessInfo.processInfo.environment["GOR_VR_SIM_POSE"] == "1" ? 0:1
check(t.consumers == (camera ? 1:0)+headConsumer,"head and blink consumers remain independently owned")
p.setHeadTrackingEnabled(false,remember:false)
check(t.consumers == (camera ? 1:0),"stopping head does not release blink consumer")
let before=t.startCalls
_ = p.setBlinkControlEnabled(true,osd:false,remember:false)
check(t.startCalls==before,"idempotent ON does not acquire twice")
t.onEyeClosure?(0.3,0.4,false)
check(p.commands.last == BlinkCommandRoute.lidsIPC(0.3,0.4,false),"actual closure callback uses lids IPC")
t.onEyeCommand?(.seek(60))
check(p.commands.last == BlinkCommandRoute.seekIPC(60,commandHeld:false),"actual seek callback uses seek IPC")
NSEvent.modifierFlags=[.command];t.onEyeCommand?(.seek(60));NSEvent.modifierFlags=[]
check(p.commands.last==BlinkCommandRoute.seekIPC(60,commandHeld:true),"Cmd double-blink rewind remains unchanged")
let beforePause=p.commands.count
t.onEyeCommand?(.playPause);check(p.commands.count==beforePause,"unmodified callback does not toggle pause")
NSEvent.modifierFlags=[.control];t.onEyeCommand?(.playPause);NSEvent.modifierFlags=[]
check(p.commands.last==BlinkCommandRoute.playPauseIPC,"actual Control single-blink callback toggles pause")
p.loadedVideoActive=false;NSEvent.modifierFlags=[.control];let beforeClosed=p.commands.count;t.onEyeCommand?(.playPause);NSEvent.modifierFlags=[]
check(p.commands.count==beforeClosed,"unloaded file cannot toggle pause");p.loadedVideoActive=true
GeomTrace.handler?("stale","log failed")
check(t.blinkLogEnabled,"stale diagnostic failure cannot stop control")
GeomTrace.handler?(t.blinkSessionID,"log failed")
check(t.blinkLogEnabled && t.onEyeClosure != nil,"current diagnostic failure keeps live control")
p.loadedVideoActive=false;p.reconcile()
check(t.consumers==0 && t.blinkLogEnabled,"file close releases camera, preserves effect state")
p.loadedVideoActive=true;p.reconcile()
check(t.consumers == (camera ? 1:0),"next loaded film reacquires consumer")
_ = p.setBlinkControlEnabled(false,osd:false,remember:false)
check(t.consumers==0 && !t.blinkLogEnabled && t.onEyeClosure==nil && t.onEyeCommand==nil,"explicit OFF clears callbacks and consumer")
check(p.commands.contains(BlinkCommandRoute.lidsClearedIPC),"explicit OFF clears shader lids")
p.applyingStore=false
_ = p.setBlinkControlEnabled(true,osd:false)
check(ThreeDStore.shared.actions==1 && !t.blinkLogEnabled,"public entry dispatches store, not parallel state")
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)

# Execute production EyeGestureCommands with both user-selectable robustness policies.
recognizer=_sections.symbol_text(root,'EyeGestureCommands',kind='struct')
control_fixture=r'''
// Compiled against the actual production recognizer, not a port.
import Foundation
func check(_ value:Bool,_ label:String) { precondition(value,label); print("PASS "+label) }
func trace(_ mode:String, robust:Bool=true)->[EyeGestureCommands.Command] {
 EyeGestureCommands.robust=robust
 var d=EyeGestureCommands(),t=0.0,out:[EyeGestureCommands.Command]=[]
 func f(_ l:Double?,_ r:Double?,_ n:Int,ctrl:Bool?=nil,reliable:Bool=true,age:Double=0) {
  for _ in 0..<n { t+=1/30; if let event=d.feedCommand(t:t,left:l,right:r,reliable:reliable,frameAge:age,controlHeld:ctrl ?? (mode != "ordinary")) { out.append(event) } }
 }
 f(0.3,0.3,20)
 if mode=="stale" {f(0.01,0.01,4,age:1);f(0.3,0.3,4);return out}
 if mode=="wink" {f(0.01,0.3,4);f(0.3,0.3,4);return out}
 if mode=="hold" {f(0.01,0.01,30);f(0.3,0.3,4);return out}
 if mode=="modifier-change" {f(0.01,0.01,4,ctrl:false);f(0.3,0.3,4);return out}
 f(0.01,0.01,4)
 if mode=="dropout" {f(nil,nil,4,reliable:false)}
 f(0.3,0.3,4)
 if mode=="double" || mode=="ordinary" {f(0.01,0.01,4);f(0.3,0.3,4)}
 if mode=="switch" {f(0.3,0.3,4,ctrl:false);f(0.01,0.01,4,ctrl:false);f(0.3,0.3,4,ctrl:false)}
 return out
}
check(EyeGestureCommands.Command.seek(60).diagnosticFields==#""seconds":60"#,"seek diagnostic schema unchanged")
for robust in [true,false] {
 check(trace("ordinary",robust:robust)==[.seek(60)],"ordinary double blink still seeks (robust=\(robust))")
 check(trace("single",robust:robust)==[.playPause],"Control single toggles once (robust=\(robust))")
 check(trace("double",robust:robust)==[.playPause,.playPause],"Control doubles never seek (robust=\(robust))")
 for invalid in ["wink","hold","stale","dropout","modifier-change"] {check(trace(invalid,robust:robust).isEmpty,invalid+" cannot toggle")}
 check(trace("switch",robust:robust)==[.playPause],"Control series cannot leak into ordinary seek")
}

'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'main.swift';p.write_text(recognizer+'\n'+control_fixture)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p),'-o',tmp+'/control-test'],check=True)
 subprocess.run([tmp+'/control-test'],check=True)
