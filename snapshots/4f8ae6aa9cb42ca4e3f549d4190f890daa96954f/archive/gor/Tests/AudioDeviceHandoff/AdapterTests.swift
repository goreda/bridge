import Foundation
@main struct Run {
 static func main() {
  var checks=0
  func check(_ c:Bool,_ s:String){checks+=1;if !c{print("FAIL "+s);exit(1)}}
  do {
   runtime.reset();let sink=AudioUnitSink(),oldContext=sink.registration!
   check(sink.selectOutputDevice(uid:"new") == .accepted(currentUID:"new"),"actual accepted")
   check(sink.unit==2 && runtime.units==[2:"new"],"unit handoff")
   check(oldContext.admission.retired && oldContext.ring==nil,"late old callback permanently fenced")
   check(sink.registration !== oldContext && !sink.registration!.admission.retired,"new callback own admission")
   check(runtime.volumes[2]==0.42,"preserve actual volume")
   check(sink.pausedFlag?.load()==0,"restore consuming state")
   check(runtime.events.firstIndex(of:"init2")!<runtime.events.firstIndex(of:"stop1")!,"prepare before old stop")
   check(runtime.events.firstIndex(of:"read2")!<runtime.events.firstIndex(of:"dispose1")!,"read before old dispose")
   runtime.alive=false;sink.reviewSelectedOutputDevice()
   check(sink.deviceTerminal && sink.registration!.admission.retired,"hot unplug silence")
   check(sink.lastDeviceResult != .accepted(currentUID:"new"),"hot unplug not accepted")
  }
  do {
   runtime.reset();let sink=AudioUnitSink()
   check(sink.selectOutputDevice(uid:"new") == .accepted(currentUID:"new"),"bind inventory-only loss")
   sink.reviewSelectedOutputDevice()
   check(!sink.deviceTerminal && sink.explicitDeviceTransaction?.selectedUID=="new","valid review keeps binding")
   runtime.removedNew=true;sink.reviewSelectedOutputDevice()
   check(sink.deviceTerminal && sink.pausedFlag?.load()==1,"removed expected UID despite matching readback terminal")
  }
  for removed in [false,true] {
   runtime.reset();let sink=AudioUnitSink()
   check(sink.selectOutputDevice(uid:"new") == .accepted(currentUID:"new"),"bind adapter UID")
   check(sink.explicitDeviceTransaction?.selectedUID=="new","adapter preserves expected UID")
   runtime.units[2]="old";runtime.removedNew=removed
   sink.reviewSelectedOutputDevice()
   check(sink.deviceTerminal && sink.registration!.admission.retired && sink.pausedFlag?.load()==1,"alive fallback must silence")
   check(sink.explicitDeviceTransaction?.terminal==true,"review persists terminal owner")
   check(sink.lastDeviceResult != .accepted(currentUID:"old"),"never publish fallback")
  }
  do {
   runtime.reset();let sink=AudioUnitSink()
   check(sink.selectOutputDevice(uid:"new") == .accepted(currentUID:"new"),"bind before second selection")
   runtime.units[2]="old"
   if case .terminal=sink.selectOutputDevice(uid:"old"){check(true,"second selection detects identity loss")}else{check(false,"second selection forgot UID")}
   check(sink.deviceTerminal,"second selection terminal silence")
  }
  for step in ["find","new","io2","device2","format2","callback2","volumeRead1","volumeSet2","init2"] {
   runtime.reset();runtime.failed=[step];let sink=AudioUnitSink()
   if case .refused=sink.selectOutputDevice(uid:"new"){check(true,"prepare failure")}else{check(false,step)}
   check(sink.unit==1 && !runtime.events.contains("stop1"),"old untouched "+step)
   check(sink.pausedFlag?.load()==0 && !sink.deviceTerminal,"restore paused "+step)
  }
  for step in ["start2","read2"] {
   runtime.reset();runtime.failed=[step];let sink=AudioUnitSink()
   if case .rolledBack(_,let uid)=sink.selectOutputDevice(uid:"new"){check(uid=="old","actual rollback uid")}else{check(false,step)}
   check(sink.unit==1 && runtime.units==[1:"old"] && !sink.deviceTerminal,"rollback retains old")
   check(runtime.events.contains("stop2") && runtime.events.contains("dispose2") && runtime.events.contains("start1"),"checked rollback")
  }
  for step in ["stop1","dispose1","stop2","dispose2","start1"] {
   runtime.reset();runtime.failed=[step];if ["stop2","dispose2","start1"].contains(step){runtime.failed.insert("start2")}
   let sink=AudioUnitSink();let r=sink.selectOutputDevice(uid:"new")
   if case .terminal=r {check(true,"terminal")}else{check(false,step)}
   check(sink.deviceTerminal && sink.registration!.admission.retired && sink.pausedFlag?.load()==1,"terminal silence")
   check(runtime.events.contains("faultGraph"),"terminal graph")
   let before=runtime.events
   check(sink.selectOutputDevice(uid:"old") == .refused(AudioDeviceFailure(.stopped)),"terminal rejects")
   check(runtime.events==before,"terminal makes no provider call")
  }
  do {
   runtime.reset();runtime.watchFailed=true;let sink=AudioUnitSink()
   if case .refused=sink.selectOutputDevice(uid:"new"){check(true,"watch fail closed")}else{check(false,"watch")}
   check(!runtime.events.contains("stop1"),"watch setup before old stop")
  }
  do {
   runtime.reset();runtime.watchFailed=true;let sink=AudioUnitSink()
   if case .refused=sink.selectOutputDevice(uid:"old"){check(true,"same current watch fail closed")}else{check(false,"same current watch")}
   check(!runtime.events.contains("stop1") && sink.unit==1,"same current does not reconfigure")
  }
  do {
   runtime.reset();let sink=AudioUnitSink()
   check(sink.selectOutputDevice(uid:"old") == .accepted(currentUID:"old"),"explicit current still fixed device")
   check(sink.unit==2 && runtime.events.contains("device2"),"DefaultOutput not mistaken for fixed UID")
  }
  do {
   runtime.reset();let sink=AudioUnitSink();sink.registration!.admission.readers=1
   let result=sink.selectOutputDevice(uid:"new")
   if case .terminal=result {check(true,"reader timeout terminal")}else{check(false,"reader timeout")}
   check(!runtime.events.contains("start2") && !runtime.events.contains("dispose1"),"no consumer switch after drain timeout")
  }
  print("PASS \(checks) actual native-adapter control-flow checks using HAL doubles")
 }
}
