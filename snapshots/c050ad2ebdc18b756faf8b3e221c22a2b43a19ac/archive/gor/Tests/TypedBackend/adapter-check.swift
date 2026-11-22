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
final class IPCClient {func sendCropPacket(_ lines:[String],generation:UInt64,final:Bool) {};func resetCropPackets(_ generation:UInt64) {}; static func socketRoundtrip(path:String,payload:String,timeout:TimeInterval,sendOnly:Bool)->[String] {[]}}
final class PersistentEventConnection {func write(_ value:String) {}}
final class PPController {let ipcClient=IPCClient();let persistentConnection=PersistentEventConnection();func ipcCommand(_ value:String) {}}
extension PPController {
    var playbackOperations:PlayerPlaybackOperations {
        PlayerPlaybackOperations(command:ipcCommand,persistent:persistentConnection.write,packet:ipcClient.sendCropPacket,reset:ipcClient.resetCropPackets)
    }
    func pausePlayback() {playbackOperations.pause()}
    func enableLivePhoton() {playbackOperations.photonLive()}

}
