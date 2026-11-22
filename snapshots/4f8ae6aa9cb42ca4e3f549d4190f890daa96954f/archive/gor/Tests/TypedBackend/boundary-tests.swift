// ================================================================
//  MPVCommand - safe mpv IPC command construction
//  Owns: building mpv IPC command lines with real JSON escaping.
//  Contract: never hand-interpolate paths/URLs/titles into a JSON
//  command again - quote-only escaping breaks on backslashes,
//  newlines, and control characters (pass-5 #5).
// ================================================================

import Foundation
import CoreFoundation
#if canImport(GorAVEmbeddedShell) && canImport(Metal)
import GorAVEmbeddedShell
import Metal
#endif

enum MPVCommand {
    /// One mpv IPC command as a single JSON line. Strings are escaped by
    /// JSONSerialization, so any path/URL/title survives intact and can
    /// never split the newline-delimited batch frame.
    static func make(_ args: [Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": args]),
              let line = String(data: data, encoding: .utf8) else { return "" }
        return line
    }
}


// Typed crop/fit operations own the wire protocol. The host keeps intent,
// measurement and window lifecycle; transport slots retain their existing order.
enum PlayerCropSample {
    case source(String)
    case window(String, scripted:Bool, final:Bool)
    fileprivate var line:String {
        switch self {
        case .source(let value):return MPVCommand.make(["set_property","video-crop",value])
        case .window(let geometry,let scripted,let final):
            return scripted ? MPVCommand.make(["script-message-to","gor_fit","crop-frame",geometry,final ? "done":"moving"]) : MPVCommand.make(["set_property","geometry",geometry])
        }
    }
}
struct PlayerCropPacket {
    fileprivate let lines:[String]
    let crop:String?
}
struct PlayerCropEpoch {
    let session:String,path:String,count:Int64,seekGeneration:Int64
    static func decode(_ data:Any?)->Self? {
        guard let state=data as? [String:Any],let session=state["session"] as? String,let path=state["path"] as? String,
              let n=state["count"] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              let count=Int64(exactly:n),count>0,count<9_007_199_254_740_990,
              let seek=state["seek_generation"] as? NSNumber,CFGetTypeID(seek) != CFBooleanGetTypeID(),
              let seekGeneration=Int64(exactly:seek) else{return nil}
        return Self(session:session,path:path,count:count,seekGeneration:seekGeneration)
    }
}
struct PlayerCropReceipt {
    let token:String,path:String,intent:String,motion:String,sequence:String,crop:String
    let source:String,geometry:String
    var policySatisfied:Bool {geometry == "accepted" || geometry == "skipped-fullscreen"}
    static func decode(_ data:Any?)->Self? {
        guard let r=data as? [String:Any],let token=r["token"] as? String,let path=r["path"] as? String,
              let intent=r["intent"] as? String,let motion=r["motion"] as? String,let sequence=r["sequence"] as? String,let crop=r["crop"] as? String,
              let final=r["final"] as? NSNumber,CFGetTypeID(final)==CFBooleanGetTypeID(),final.boolValue,
              let source=r["source"] as? String,["accepted","setter-failed","readback-failed"].contains(source),
              let geometry=r["geometry"] as? String,["accepted","none","skipped-fullscreen","skipped-transition","setter-failed","not-attempted"].contains(geometry) else{return nil}
        return Self(token:token,path:path,intent:intent,motion:motion,sequence:sequence,crop:crop,source:source,geometry:geometry)
    }
}
enum PlayerFitProtocol {
    static func packet(_ samples:[PlayerCropSample],scripted:Bool,token:String?,source:String,intent:UInt64,motion:UInt64,sequence:inout UInt64,final:Bool,serialize:([String:Any]) throws->Data = {try JSONSerialization.data(withJSONObject:$0)})->PlayerCropPacket? {
        let lines=samples.map(\.line)
        guard scripted else {return PlayerCropPacket(lines:lines,crop:nil)}
        // Keep the old serialization path and refusal, including first-command
        // shape, so packet framing and acceptance identity do not drift.
        guard let token,let rowsData=("["+lines.joined(separator:",")+"]").data(using:.utf8),
              let rows=try? JSONSerialization.jsonObject(with:rowsData) as? [[String:Any]],
              let command=rows.first?["command"] as? [String],command.count==3 else{return nil}
        sequence &+= 1
        let envelope:[String:Any]=["commands":rows,"intent":String(intent),"motion":String(motion),"sequence":String(sequence),"final":final]
        guard let bytes=try? serialize(envelope),let payload=String(data:bytes,encoding:.utf8) else{return nil}
        return PlayerCropPacket(lines:[MPVCommand.make(["script-message-to","gor_fit","crop-packet",payload,source,token])],crop:command[2])
    }
    static func fitBatch(_ payload:String,metrics:String,anchor:String?)->String {
        let prefix=anchor.map {MPVCommand.make(["set_property","user-data/gor/fit-anchor",$0])+"\n"} ?? ""
        return prefix+MPVCommand.make(["set_property","user-data/gor/fit",metrics])+"\n"+payload
    }
    static func previewPayload(geometry:String,seekPercent:Double?)->String {
        let seek=seekPercent.map {"{\"command\":[\"seek\",\($0),\"absolute-percent\",\"keyframes\"]}\n"} ?? ""
        return seek+"{\"command\":[\"set\",\"geometry\",\"\(geometry)\"]}\n"
    }
}
struct PlayerPlaybackOperations {
    let command:(String)->Void
    let persistent:(String)->Void
    let packet:([String],UInt64,Bool)->Void
    let reset:(UInt64)->Void
    func publish(_ sample:PlayerCropSample) {command(sample.line)}
    func deliver(_ value:PlayerCropPacket,generation:UInt64,final:Bool) {packet(value.lines,generation,final)}
    func resetCrop(_ generation:UInt64) {reset(generation)}
    func fenceCropIntent() {persistent(MPVCommand.make(["script-message-to","gor_fit","crop-intent-fence"]))}
    func fenceCropSeek() {persistent(MPVCommand.make(["script-message-to","gor_fit","crop-seek-fence"]))}
    func fitAnchor(_ anchor:String) {command(MPVCommand.make(["set_property","user-data/gor/fit-anchor",anchor]))}
    func pause() {command(MPVCommand.make(["set_property","pause",true]))}
    func photonLive() {command(#"{"command":["script-message-to","photon","set-live","true"]}"#)}
}
final class LatestCropPacketSlot {
    struct Packet { let payload:String; let generation:UInt64; let final:Bool }
    private let lock=NSLock()
    private var generation:UInt64=0
    private var pending:Packet?
    private var running=false
    private var finalOffered=false
    func reset(_ next:UInt64) {
        lock.lock();defer {lock.unlock()}
        generation=next;pending=nil;finalOffered=false
    }
    func offer(_ payload:String,generation next:UInt64,final:Bool)->Bool {
        lock.lock();defer {lock.unlock()}
        guard generation==next,!finalOffered else {return false}
        pending=Packet(payload:payload,generation:next,final:final)
        if final {finalOffered=true}
        if running {return false};running=true;return true
    }
    func take(scheduled:UInt64? = nil)->Packet? {
        lock.lock();defer {lock.unlock()}
        if let scheduled, pending?.generation != scheduled {return nil}
        let value=pending;pending=nil;return value
    }
    func current(_ value:UInt64)->Bool {
        lock.lock();defer {lock.unlock()};return generation==value
    }
    func finish()->UInt64? {
        lock.lock();defer {lock.unlock()}
        if let pending {return pending.generation};running=false;return nil
    }
}
func prepared(_ samples:[PlayerCropSample],scripted:Bool,token:String?,source:String,intent:UInt64,motion:UInt64,sequence:UInt64,final:Bool)->PlayerCropPacket? {
 var previous=sequence &- 1
 return PlayerFitProtocol.packet(samples,scripted:scripted,token:token,source:source,intent:intent,motion:motion,sequence:&previous,final:final)
}
var checks=0
func check(_ b:Bool,_ name:String) {checks+=1;if !b {fatalError(name)}}
func object(_ line:String)->[String:Any] {try! JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]}
func canonical(_ line:String)->Data {try! JSONSerialization.data(withJSONObject:object(line),options:.sortedKeys)}
func equivalent(_ a:String,_ b:String)->Bool {canonical(a)==canonical(b)}
func legacy(_ samples:[String],token:String?,source:String,intent:UInt64,motion:UInt64,sequence:UInt64,final:Bool)->String? {
 guard let token,let data=("["+samples.joined(separator:",")+"]").data(using:.utf8),let rows=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]],let command=rows.first?["command"] as? [String],command.count==3 else{return nil}
 let envelope:[String:Any]=["commands":rows,"intent":String(intent),"motion":String(motion),"sequence":String(sequence),"final":final]
 let bytes=try! JSONSerialization.data(withJSONObject:envelope);return MPVCommand.make(["script-message-to","gor_fit","crop-packet",String(data:bytes,encoding:.utf8)!,source,token])
}
func packetEqual(_ a:String,_ b:String)->Bool {
 var aa=object(a)["command"] as! [String],bb=object(b)["command"] as! [String]
 guard equivalent(aa[3],bb[3]) else{return false};aa[3]="payload";bb[3]="payload";return aa==bb
}
for crop in ["","1920x800+0+140","path\\\"\n雪"] {
 for scripted in [false,true] {for final in [false,true] {
  let geometry="1280x720+10+20"
  let samples:[PlayerCropSample]=[.source(crop),.window(geometry,scripted:scripted,final:final)]
  let before=[MPVCommand.make(["set_property","video-crop",crop]),scripted ? MPVCommand.make(["script-message-to","gor_fit","crop-frame",geometry,final ? "done":"moving"]) : MPVCommand.make(["set_property","geometry",geometry])]
  for (a,b) in zip(samples.map(\.line),before) {check(equivalent(a,b),"sample argv")}
  let prepared=prepared(samples,scripted:scripted,token:"session:7",source:"/a\\b\n雪",intent:42,motion:91,sequence:17,final:final)!
  if scripted {check(packetEqual(prepared.lines[0],legacy(before,token:"session:7",source:"/a\\b\n雪",intent:42,motion:91,sequence:17,final:final)!),"packet argv/envelope");check(prepared.crop==crop,"receipt crop")}
  else {check(zip(prepared.lines,before).allSatisfy(equivalent),"direct packet order")}
 }}
}
check(prepared([.source("")],scripted:true,token:nil,source:"p",intent:0,motion:0,sequence:0,final:true)==nil,"missing token")
check(prepared([],scripted:true,token:"x",source:"p",intent:0,motion:0,sequence:0,final:true)==nil,"missing first command")
check(prepared([.window("x",scripted:true,final:true)],scripted:true,token:"x",source:"p",intent:0,motion:0,sequence:0,final:true)==nil,"bad first command")
for seek:Double? in [nil,0,42.5,100] {
 let a=PlayerFitProtocol.previewPayload(geometry:"320x180+1+2",seekPercent:seek)
 let b=(seek.map {"{\"command\":[\"seek\",\($0),\"absolute-percent\",\"keyframes\"]}\n"} ?? "")+"{\"command\":[\"set\",\"geometry\",\"320x180+1+2\"]}\n"
 check(a==b,"preview literal bytes/order/newlines")
}
for anchor:String? in [nil,"1280x720+1+2"] {
 let value=PlayerFitProtocol.fitBatch("load\nsecond",metrics:"1920,1080,2",anchor:anchor)
 let lines=value.split(separator:"\n").map(String.init)
 check(lines.suffix(2)==["load","second"],"batch original tail")
 let commands=lines.dropLast(2).map {object($0)["command"] as! [String]}
 check(commands.last==["set_property","user-data/gor/fit","1920,1080,2"],"fit ahead of load")
 check(commands.count==(anchor==nil ? 1:2),"optional anchor")
 if let anchor {check(commands.first==["set_property","user-data/gor/fit-anchor",anchor],"anchor ahead of fit")}
}
var epoch:[String:Any]=["session":"nonce","path":"p","count":7,"seek_generation":3]
check(PlayerCropEpoch.decode(epoch)?.count==7,"epoch valid")
for invalid:Any in [true,0,-1,7.5,9_007_199_254_740_990,"7",NSNull()] {epoch["count"]=invalid;check(PlayerCropEpoch.decode(epoch)==nil,"epoch count refusal")}
epoch["count"]=7
for invalid:Any in [true,3.1,"3",NSNull()] {epoch["seek_generation"]=invalid;check(PlayerCropEpoch.decode(epoch)==nil,"seek decode refusal")}
var receipt:[String:Any]=["token":"s:7","path":"p","intent":"42","motion":"91","sequence":"17","crop":"","final":true,"source":"accepted","geometry":"accepted"]
check(PlayerCropReceipt.decode(receipt)?.policySatisfied==true,"valid receipt")
for final:Any in [false,1,"true",NSNull()] {receipt["final"]=final;check(PlayerCropReceipt.decode(receipt)==nil,"receipt final bool refusal")}
receipt["final"]=true
for source in ["accepted","setter-failed","readback-failed","invalid"] {for geometry in ["accepted","none","skipped-fullscreen","skipped-transition","setter-failed","not-attempted","invalid"] {
 receipt["source"]=source;receipt["geometry"]=geometry
 let result=PlayerCropReceipt.decode(receipt)
 check((result != nil)==(source != "invalid" && geometry != "invalid"),"receipt vocabulary")
 if let result {check(result.policySatisfied==(geometry=="accepted" || geometry=="skipped-fullscreen"),"receipt window policy")}
}}
var events:[String]=[]
let ops=PlayerPlaybackOperations(command:{events.append("command:"+$0)},persistent:{events.append("persistent:"+$0)},packet:{events.append("packet:\($1):\($2):"+$0.joined(separator:"\n")+"\n")},reset:{events.append("reset:\($0)")})
ops.fenceCropIntent();ops.resetCrop(7);ops.publish(.source(""));ops.fenceCropSeek();ops.pause();ops.photonLive()
check(events.count==6,"dispatch count")
check(events[0].hasPrefix("persistent:"),"intent channel")
check(events[1]=="reset:7","generation reset order")
check(events[2].hasPrefix("command:"),"source side-effect path")
check(events[3].hasPrefix("persistent:"),"seek channel before command")
check(equivalent(String(events[4].dropFirst(8)),MPVCommand.make(["set_property","pause",true])),"pause native-compatible argv")
check(events[5]=="command:{\"command\":[\"script-message-to\",\"photon\",\"set-live\",\"true\"]}","Photon literal bytes")
let slot=LatestCropPacketSlot();slot.reset(1)
check(!slot.offer("old",generation:0,final:true),"old generation refused")
check(slot.offer("a",generation:1,final:false),"first schedules")
check(!slot.offer("b",generation:1,final:false),"intermediate replaces no extra schedule")
check(slot.take()?.payload=="b","latest intermediate")
check(!slot.offer("final",generation:1,final:true),"inflight final no extra schedule")
check(!slot.offer("late",generation:1,final:false),"final blocks intermediate")
check(slot.finish()==1,"requeue behind discrete")
check(slot.take(scheduled:1)?.payload=="final","final preserved")
slot.reset(2);check(!slot.current(1),"inflight epoch fenced")
check(slot.take(scheduled:1)==nil,"stale scheduled generation")
check(slot.finish()==nil,"slot idle after reset")
var sequence:UInt64=9
enum EncodingFailure:Error {case injected}
let fail:([String:Any]) throws->Data = {_ in throw EncodingFailure.injected}
check(PlayerFitProtocol.packet([],scripted:true,token:"s:7",source:"p",intent:1,motion:2,sequence:&sequence,final:true,serialize:fail)==nil && sequence==9,"invalid shape consumes none")
check(PlayerFitProtocol.packet([.source("")],scripted:true,token:nil,source:"p",intent:1,motion:2,sequence:&sequence,final:true,serialize:fail)==nil && sequence==9,"missing token consumes none")
check(PlayerFitProtocol.packet([.source("")],scripted:true,token:"s:7",source:"p",intent:1,motion:2,sequence:&sequence,final:true,serialize:fail)==nil && sequence==10,"valid shape encoding failure consumes exactly one")
let success=PlayerFitProtocol.packet([.source("")],scripted:true,token:"s:7",source:"p",intent:1,motion:2,sequence:&sequence,final:true)!
let argv=object(success.lines[0])["command"] as! [String]
check(sequence==11 && object(argv[3])["sequence"] as? String == "11","successful packet identity allocated sequence")
_=PlayerFitProtocol.packet([.source("")],scripted:false,token:nil,source:"p",intent:1,motion:2,sequence:&sequence,final:true,serialize:fail)
check(sequence==11,"nonscripted consumes none")
print("PASS \(checks) portable typed-backend boundary checks")
