from pathlib import Path
r=Path(__file__).resolve().parents[2];s=(r/'Packages/gorav/Sources/GorAVMacShell/AudioUnitSink.swift').read_text();out=Path(__file__).resolve().parent/'results';out.mkdir(exist_ok=True)
def block(a):
 p=s.index(a);q=s.index('{',p);n=0
 for i in range(q,len(s)):
  n+=(s[i]=='{')-(s[i]=='}')
  if n==0:return s[p:i+1]
 raise ValueError(a)
parts=[block('    public func selectOutputDevice('),block('    private func reviewSelectedOutputDevice(').replace('private func','func',1),block('    private final class DeviceHandoff:').replace('private final class','final class',1)]
prefix='''import Foundation
struct AudioComponentDescription {var componentType:Int;var componentSubType:Int;var componentManufacturer:Int;var componentFlags:Int;var componentFlagsMask:Int}
struct AudioStreamBasicDescription {
 var mSampleRate:Double;var mFormatID:Int;var mFormatFlags:Int;var mBytesPerPacket:Int;var mFramesPerPacket:Int
 var mBytesPerFrame:Int;var mChannelsPerFrame:Int;var mBitsPerChannel:Int;var mReserved:Int
}
typealias AudioUnit=Int
typealias AudioDeviceID=UInt32
typealias AudioUnitParameterValue=Float
struct AURenderCallbackStruct {var unused:Int=0}
let kAudioUnitType_Output=1,kAudioUnitSubType_HALOutput=2,kAudioUnitManufacturer_Apple=3,kAudioOutputUnitProperty_EnableIO=4
let kAudioUnitScope_Output=5,kAudioUnitScope_Input=6,kAudioOutputUnitProperty_CurrentDevice=7,kAudioUnitScope_Global=8
let kAudioUnitProperty_StreamFormat=9,kAudioFormatLinearPCM=10,kAudioFormatFlagIsSignedInteger=1,kAudioFormatFlagIsPacked=2
let kAudioUnitProperty_SetRenderCallback=11,kHALOutputParam_Volume=12
let noErr:Int32=0
final class Runtime:@unchecked Sendable {
 var events=[String](),failed:Set<String>=[],units:[Int:String]=[1:"old"],volumes:[Int:Float]=[1:0.42],next=2
 var removedNew=false;var alive=true,wrongRead=false,watchFailed=false,targetUID="new"
 func step(_ s:String)->Int32 {events.append(s);return failed.contains(s) ? -77:0}
 func reset(){removedNew=false;events=[];failed=[];units=[1:"old"];volumes=[1:0.42];next=2;alive=true;wrongRead=false;watchFailed=false;targetUID="new"}
}
let runtime=Runtime()
func AudioComponentFindNext(_ ignored:Int?,_ desc:inout AudioComponentDescription)->Int? {runtime.step("find")==0 ? 1:nil}
func AudioComponentInstanceNew(_ c:Int,_ u:inout Int?)->Int32 {let s=runtime.step("new");if s==0 {u=runtime.next;runtime.next+=1};return s}
func AudioUnitSetProperty(_ u:Int,_ prop:Int,_ scope:Int,_ element:Int,_ data:UnsafeRawPointer,_ size:UInt32)->Int32 {
 let name=prop==kAudioOutputUnitProperty_CurrentDevice ? "device":prop==kAudioUnitProperty_StreamFormat ? "format":prop==kAudioUnitProperty_SetRenderCallback ? "callback":"io"
 let s=runtime.step(name+String(u));if s==0 && name=="device"{runtime.units[u]=runtime.targetUID};return s
}
func AudioUnitGetParameter(_ u:Int,_ p:Int,_ scope:Int,_ e:Int,_ v:inout Float)->Int32 {let s=runtime.step("volumeRead"+String(u));v=runtime.volumes[u] ?? 0;return s}
func AudioUnitSetParameter(_ u:Int,_ p:Int,_ scope:Int,_ e:Int,_ v:Float,_ offset:Int)->Int32 {let s=runtime.step("volumeSet"+String(u));runtime.volumes[u]=v;return s}
func AudioUnitInitialize(_ u:Int)->Int32 {runtime.step("init"+String(u))}
func AudioUnitUninitialize(_ u:Int)->Int32 {runtime.step("uninit"+String(u))}
func AudioComponentInstanceDispose(_ u:Int)->Int32 {let s=runtime.step("dispose"+String(u));if s==0 {runtime.units.removeValue(forKey:u)};return s}
func AudioOutputUnitStop(_ u:Int)->Int32 {runtime.step("stop"+String(u))}
func AudioOutputUnitStart(_ u:Int)->Int32 {runtime.step("start"+String(u))}
func CACurrentMediaTime()->Double {ProcessInfo.processInfo.systemUptime}
final class Cell {var value:UInt64=0;func load()->UInt64{value};func store(_ v:UInt64){value=v}}
final class Admission {var readers=0;var retired=false;func retire(){retired=true}}
struct Token {let id:UInt64}
typealias RegistrationToken=Token
final class PlaybackRegistry {
 struct Reservation {let n:UInt64}
 enum State {case active,tombstone,fault}
 var next:UInt64=20
 func reserve(_ s:State)->Result<Reservation,AudioDeviceFailure> {.success(.init(n:next))}
 func register(root:AnyObject,token:Reservation)->Token? {next+=1;return Token(id:token.n)}
 func rollback(_ token:Reservation){}
 func reclassify(_ token:Token,to:State)->Bool {true}
}
final class Policy {
 var stopped=false;func sessionStop(){stopped=true}
 func pause(atHost:Double)->Bool {true}
 func resume(consumedFrames:UInt64,atHost:Double)->Bool {true}
 func notePausedSilence(_ n:UInt64){}
}
final class Ring {var consumedFrames=Cell()}
enum CoreAudioOutputInventory {
 static func resolve(uid:String)throws->AudioDeviceID {runtime.targetUID=uid;if !runtime.alive{throw AudioDeviceFailure(.unavailable)};return 99}
 static func snapshot(currentUID:String?=nil)throws->AudioOutputDeviceInventory {
  .init(devices:runtime.alive ? [.init(uid:"old",name:"old",isAlive:true),.init(uid:"new",name:"new",isAlive:!runtime.removedNew)]:[],defaultUID:"old",currentUID:currentUID)
 }
 static func currentUID(unit:Int)throws->String {
  let s=runtime.step("read"+String(unit));if s != 0 {throw AudioDeviceFailure(.readback,status:s)}
  guard let uid=runtime.units[unit] else{throw AudioDeviceFailure(.readback)}
  return runtime.wrongRead && unit==2 ? "wrong":uid
 }
}
final class CoreAudioOutputWatch {
 init(device:UInt32,changed:@escaping @Sendable ()->Void)throws {if runtime.watchFailed{throw AudioDeviceFailure(.inventory)}}
}
final class AudioUnitSink:@unchecked Sendable {
 final class CallbackContext {
 let admission=Admission();let generation:UInt64
 var ring:Ring?=Ring(),events:Cell?=Cell()
 init(){generation=7}
 init?(generation:UInt64,sink:AudioUnitSink,ring:Ring,events:Cell) {self.generation=generation;self.ring=ring;self.events=events}
 func detach(){ring=nil;events=nil}
}
 enum State {case active(UInt64),idle}
 final class Lifecycle {var current=State.active(7)}
 func hostSeconds()->Double {0}
 var ringStorage:Ring?=Ring(),pausedSilenceRT:Cell?=Cell()
 let registry=PlaybackRegistry()
 let stateLock=NSLock(),deviceOperationLock=NSRecursiveLock(),lifecycle=Lifecycle()
 var deviceTerminal=false,unit:Int?=1,registration:CallbackContext?=CallbackContext(),pausedFlag:Cell?=Cell()
 var outputDeviceWatch:CoreAudioOutputWatch?,explicitDeviceTransaction:AudioOutputDeviceTransaction?
 var retainedDeviceUnits=[Int](),lastDeviceResult:AudioDeviceSelectionResult?,registrationToken:Token?=Token(id:17),pacingPolicy:Policy?=Policy()
 func deviceCallback(_ c:CallbackContext)->AURenderCallbackStruct {.init()}
 @discardableResult func retainFaultGraph(token:Token?,unit:Int?,generation:UInt64,stopStatus:Int32?,uninitStatus:Int32?,disposeStatus:Int32?,readersDrained:Bool,producerWitnessed:Bool,cause:String)->Bool {runtime.events.append("faultGraph");return true}
'''
(out/'ActualAdapter.swift').write_text(prefix+'\n'.join(parts)+'\n}\n')
