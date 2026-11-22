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
// IPTV owns a single ordered batch, not three independent sends.
// Host load-generation admission precedes this operation; existing batchIPC
// retains transport and embedded dispatch ownership.
struct PlayerIPTVOperations {
    let batch:(String)->Void
    func load(url:String,photonEnabled:Bool) {
        let payload = [
            #"{"command":["script-message-to","photon","set-live","true"]}"#,
            #"{"command":["script-message-to","photon","set-user-enabled","\#(photonEnabled ? "true" : "false")"]}"#,
            MPVCommand.make(["loadfile",url]),
        ].joined(separator:"\n")
        batch(payload)
    }
}

struct PlayerPlaybackOperations {
    let command:(String)->Void
    let persistent:(String)->Void
    let packet:([String],UInt64,Bool)->Void
    let reset:(UInt64)->Void
    func addSubtitle(path:String) {command(MPVCommand.make(["sub-add",path]))}
    func openMedia(path:String) {command(MPVCommand.make(["loadfile",path]))}
    func publish(_ sample:PlayerCropSample) {command(sample.line)}
    func deliver(_ value:PlayerCropPacket,generation:UInt64,final:Bool) {packet(value.lines,generation,final)}
    func resetCrop(_ generation:UInt64) {reset(generation)}
    func fenceCropIntent() {persistent(MPVCommand.make(["script-message-to","gor_fit","crop-intent-fence"]))}
    func fenceCropSeek() {persistent(MPVCommand.make(["script-message-to","gor_fit","crop-seek-fence"]))}
    func fitAnchor(_ anchor:String) {command(MPVCommand.make(["set_property","user-data/gor/fit-anchor",anchor]))}
    func pause() {command(MPVCommand.make(["set_property","pause",true]))}
    func photonLive() {command(#"{"command":["script-message-to","photon","set-live","true"]}"#)}
}
#if canImport(AppKit)
enum PlayerPreviewOperations {
    static func update(socket:String,geometry:String,seekPercent:Double?) {
        _=IPCClient.socketRoundtrip(path:socket,payload:PlayerFitProtocol.previewPayload(geometry:geometry,seekPercent:seekPercent),timeout:0.05,sendOnly:true)
    }
}
#endif

// Backend admission seam. Keep this Foundation-only so the exact selection and
// rollback path can be exercised without an AppKit or GorAV dependency.
enum PlayerEngine: String, CaseIterable {
    case mpv, gorav
    static let preferenceKey = "gor.player.engine"
    static func selected(environment: [String: String], saved: String?) -> PlayerEngine {
        if let override = environment["GOR_ENGINE"], let engine = PlayerEngine(rawValue: override) { return engine }
        return saved.flatMap(PlayerEngine.init(rawValue:)) ?? .mpv
    }
}

enum PlayerProcessExitPolicy {
    static func shouldTerminate(current:AnyObject?,exited:AnyObject,quitting:Bool)->Bool {
        !quitting && current === exited
    }
}

enum PlayerBackendAdmission: Equatable {
    case ready
    case unavailable(String)
}
protocol PlayerBackend {
    var engine: PlayerEngine { get }
    func admission() -> PlayerBackendAdmission
}
struct MPVBackend: PlayerBackend {
    let engine = PlayerEngine.mpv
    func admission() -> PlayerBackendAdmission { .ready }
}
struct GorAVBackend: PlayerBackend {
    let engine = PlayerEngine.gorav
    // Feature admission only. Native qualification remains a separate receipt.
    func admission() -> PlayerBackendAdmission {
#if canImport(GorAVEmbeddedShell) && canImport(Metal)
        return MTLCreateSystemDefaultDevice() == nil ? .unavailable("gorav requires a Metal device") : .ready
#else
        return .unavailable("gorav package or native Metal runtime unavailable")
#endif
    }
}
struct PlayerBackendRoute: Equatable {
    let requested: PlayerEngine
    let active: PlayerEngine
    let fallbackReason: String?
    static func resolve(_ engine: PlayerEngine) -> PlayerBackendRoute {
        let backend: any PlayerBackend = engine == .mpv ? MPVBackend() : GorAVBackend()
        switch backend.admission() {
        case .ready: return PlayerBackendRoute(requested: engine, active: engine, fallbackReason: nil)
        case .unavailable(let reason): return PlayerBackendRoute(requested: engine, active: .mpv, fallbackReason: reason)
        }
    }
    func launch(file: String?, gorav: ((String?) -> Void)? = nil, mpv: (String?) -> Void) {
        // Dispatch once. Once a gorav open begins, a runtime refusal never
        // replays media on mpv; only pre-open admission can select fallback.
        if active == .mpv { mpv(file) } else { gorav?(file) }
    }
}

struct PlayerRouteStatus:Equatable {
    var requested:PlayerEngine = .mpv
    var active:PlayerEngine = .mpv
    var fallbackReason:String?
    /// Only an actual fallback is retained in the HUD. Diagnostic route text stays transient.
    var refusalHUDLine:String? {
        guard requested == .gorav,active == .mpv,let reason=fallbackReason,!reason.isEmpty else {return nil}
        if reason.hasPrefix("expected at most one audio stream, found ") ||
           reason.hasPrefix("expected_at_most_one_audio_stream__found_") {
            return "gorav to mpv: multiple audio tracks are not supported yet"
        }
        // Other refusal families retain their existing route until separately mapped.
        return nil
    }
    var line:String {
        var text="engine requested=\(requested.rawValue) active=\(active.rawValue)"
        if let fallbackReason {text+="; \(fallbackReason)"}
        else if requested != active {text+="; applies on next open"}
        return text
    }
    /// Normal playback is quiet. Keep actual fallback reasons visible and
    /// expose engine routing only when diagnostics were explicitly requested.
    func osdLine(environment:[String:String] = ProcessInfo.processInfo.environment)->String? {
        if environment["GOR_DEBUG_ENGINE_OSD"] == "1" {return line}
        guard let reason=fallbackReason,!reason.isEmpty else {return nil}
        return "gorav: \(reason) -> mpv"
    }
}

/// mpv visibility flags are preferences, not proof that a subtitle is being drawn.
enum SubtitleRendererOwnership {
    static func nativeVisible(primaryVisible: Bool, secondaryVisible: Bool,
                              primaryID: Any?, secondaryID: Any?) -> Bool {
        func selected(_ value: Any?) -> Bool {
            if let n = value as? Int { return n > 0 }
            if let s = value as? String, let n = Int(s) { return n > 0 }
            return false
        }
        return (primaryVisible && selected(primaryID)) || (secondaryVisible && selected(secondaryID))
    }
}

#if canImport(AppKit)
/// Typed acceptance operations remain in the player backend boundary, not UI test code.
/// Inert unless the isolated owner-action runner calls them.
enum OwnerActionPlayerProbe {
    static func setRoll(socket:String,extended:Bool,roll:String="0.261799388") {
        let client=IPCClient(path:socket)
        // Test-only barrier: both commands precede the receipt read on this connection.
        // Async sends let the 100ms sampler outrun the shared queue's EOF wait.
        let commands=[MPVCommand.make(["script-message-to","vr180_look","vr180-look-tools-active",extended ? "true":"false"]),
                      MPVCommand.make(["script-message-to","vr180_look","vr180-look-set-orientation","0","0","135",roll,"0","0","0","0"])]
        _=client.queryBatch(commands.joined(separator:"\n")+"\n",timeout:1)
    }
    static func restoreVariant(socket:String) {
        let client=IPCClient(path:socket)
        client.send(MPVCommand.make(["script-message-to","vr180_look","vr180-look-tools-active","false"]))
    }
    static func frame(socket:String,path:String) {
        let client=IPCClient(path:socket)
        client.send(MPVCommand.make(["screenshot-to-file",path,"window"]))
    }
    static func completed(_ replies:[Any],fields:[String],revision:UInt64)->Bool {
        var values:[String:Any]=[:]
        for case let row as [String:Any] in replies {
            guard row["error"] as? String == "success",let id=row["request_id"] as? Int,id>0,id<=fields.count else {continue}
            values[fields[id-1]]=row["data"]
        }
        func object(_ key:String)->[String:Any]? {
            if let value=values[key] as? [String:Any] {return value}
            return (values[key] as? String)?.data(using:.utf8).flatMap {try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
        }
        guard let swift=object("user-data/gor/3d-applied-state"),let lua=object("user-data/vr180-look/applied-state"),
              let applied=(swift["revision"] as? NSNumber)?.uint64Value,applied >= revision,
              (lua["revision"] as? NSNumber)?.uint64Value == applied,
              (lua["completed_revision"] as? NSNumber)?.uint64Value == applied,
              let enabled=lua["enabled"] as? Bool,values["user-data/vr180-look/enabled"] as? Bool == enabled else {return false}
        return true
    }
    static func readCompleted(socket:String,fields:[String],revision:UInt64,deadline:Double)->[Any] {
        var replies:[Any]=[]
        repeat {
            replies=read(socket:socket,fields:fields)
            if completed(replies,fields:fields,revision:revision) {return replies}
            Thread.sleep(forTimeInterval:0.1)
        } while Date().timeIntervalSince1970 < deadline
        return replies // Retain the actual incomplete receipts; evaluator must reject them.
    }
    static func read(socket:String,fields:[String])->[Any] {
        let lines=fields.enumerated().compactMap {i,field -> String? in
            guard let data=try? JSONSerialization.data(withJSONObject:["command":["get_property",field],"request_id":i+1]) else {return nil}
            return String(data:data,encoding:.utf8)
        }
        return IPCClient(path:socket).queryBatch(lines.joined(separator:"\n")+"\n",timeout:2).compactMap {
            $0.data(using:.utf8).flatMap {try? JSONSerialization.jsonObject(with:$0)}
        }
    }
}

#endif

// BEGIN relocated PlayerProtocol.swift (195y G3, behavior unchanged)
#if canImport(AppKit)
// ================================================================
//  PlayerProtocol.swift - player view protocol for SidebarUI and SpineUI
//  Owns: the playerView contract both panels call through
//  Contract: PlayerViewStub and the real PlayerView implement this
// ================================================================
import AppKit

@objc protocol PlayerProtocol: AnyObject {
    var isPlaying:  Bool  { get }
    var volume:     Float { get set }
    var spineUI:    SpineUI { get }

    func togglePlay()
    func seekRelative(_ s: Double)
    func seek(to p: Double)
    func currentTime() -> Double
    func currentProgress() -> Double
    func osdString() -> String
    func showSubtitleMenu(from v: NSView)
    func closeWindow()
    func miniaturizeWindow()
    func toggleFullScreen()
    func reloadStream()
    func resumeStream()
    func rewindowStream()
    func stopStream()
}
#endif
// END relocated PlayerProtocol.swift

// BEGIN hover preview quit transport (arch-198y)
enum HoverPreviewTransport {
    static func quit(socketPath: String) {
        _ = IPCClient.socketRoundtrip(path: socketPath, payload: "{\"command\":[\"quit\"]}\n", timeout: 0.25, sendOnly: true)
    }
}
// END hover preview quit transport

// A per-socket command batch is complete after one JSON error/result response per line.
// Events and partial/invalid lines cannot complete the batch.
struct IPCResponseCounter {
    let expected:Int
    private var buffer=Data()
    private(set) var count=0
    // Explicit internal initializer: private buffer suppresses the synthesized caller access.
    init(expected:Int) { self.expected=expected }
    mutating func consume(_ chunk:Data)->Bool {
        buffer.append(chunk)
        while let newline=buffer.firstIndex(of:10) {
            let line=Data(buffer[..<newline]);buffer.removeSubrange(...newline)
            if let object=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],
               object["event"] == nil, object["error"] is String {count += 1}
        }
        return expected>0 && count>=expected
    }
}

// Crop samples keep ordered command barriers but replace pending intermediate state.
// The final packet is never replaced by an intermediate packet of the same generation.
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

// BEGIN relocated IPCClient (from PPController.swift, 195y G3, behavior unchanged)
#if canImport(AppKit)
final class IPCClient {
    let path: String
    init(path: String) { self.path = path }
    private let cropPacketSlot=LatestCropPacketSlot()
    func resetCropPackets(_ generation:UInt64) {cropPacketSlot.reset(generation)}
    private func drainCropPacket(scheduled:UInt64) {
        if let packet=cropPacketSlot.take(scheduled:scheduled),cropPacketSlot.current(packet.generation),
           FileManager.default.fileExists(atPath:path) {
            _=IPCClient.socketRoundtrip(path:path,payload:packet.payload,timeout:0.5)
        }
        // Re-enqueue, never loop here: discrete commands already queued keep their order.
        if let next=cropPacketSlot.finish() {IPCClient.cmdQueue.async { [weak self] in self?.drainCropPacket(scheduled:next) }}
    }
    func sendCropPacket(_ lines:[String],generation:UInt64,final:Bool) {
        guard !lines.isEmpty else{return}
        let payload=lines.joined(separator:"\n")+"\n"
        if cropPacketSlot.offer(payload,generation:generation,final:final) {
            IPCClient.cmdQueue.async { [weak self] in self?.drainCropPacket(scheduled:generation) }
        }
    }
    // MARK: - Queries
    // ── Batch query (synchronous) ───────────────────────────────────────────
    func queryBatch(_ payload: String, timeout: TimeInterval = 0.8) -> [String] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return IPCClient.socketRoundtrip(path: path, payload: payload, timeout: timeout)
    }
    private let poseSlot=LatestPoseSlot()
    private func drainLatestPose() {
        if let value=poseSlot.take(),poseSlot.current(value.epoch),FileManager.default.fileExists(atPath:path) {
            let began=ProcessInfo.processInfo.systemUptime
            _=IPCClient.socketRoundtrip(path:path,payload:value.payload+"\n",timeout:0.5,sendOnly:true)
            let end=ProcessInfo.processInfo.systemUptime
            CommandLatencyTrace.shared.record(kind:"pose",queuedMS:(began-value.at)*1000,sendMS:(end-began)*1000)
        }
        if poseSlot.finish() {IPCClient.cmdQueue.async { [weak self] in self?.drainLatestPose() }}
    }
    func sendLatestPose(_ json:String) {
        if poseSlot.offer(json,at:ProcessInfo.processInfo.systemUptime) {
            IPCClient.cmdQueue.async { [weak self] in self?.drainLatestPose() }
        }
    }
    // Lids are continuous state, not FIFO commands. One independent pending slot
    // prevents pose updates from replacing lids or stale lids delaying a gesture.
    private let lidSlot=LatestPoseSlot()
    private func drainLatestLids() {
        if let value=lidSlot.take(),lidSlot.current(value.epoch),FileManager.default.fileExists(atPath:path) {
            let began=ProcessInfo.processInfo.systemUptime
            _=IPCClient.socketRoundtrip(path:path,payload:value.payload+"\n",timeout:0.1,sendOnly:true)
            let end=ProcessInfo.processInfo.systemUptime
            CommandLatencyTrace.shared.record(kind:"lids",queuedMS:(began-value.at)*1000,sendMS:(end-began)*1000)
            GeomTrace.logBlink("{\"k\":\"blinkIPC\",\"queueMS\":\((began-value.at)*1000),\"sendMS\":\((end-began)*1000)}")
        }
        if lidSlot.finish() {IPCClient.cmdQueue.async { [weak self] in self?.drainLatestLids() }}
    }
    func sendLatestLids(_ json:String) {
        if lidSlot.offer(json,at:ProcessInfo.processInfo.systemUptime) {
            IPCClient.cmdQueue.async { [weak self] in self?.drainLatestLids() }
        }
    }
    func cancelLatestPose() {poseSlot.clear()}
    // Only irrevocable quit intent closes this per-controller slot; file/stop/VR-off merely clear it.
    func closeLatestPose() {poseSlot.close();lidSlot.close()}
    // ── Fire-and-forget command ─────────────────────────────────────────────
    static let cmdQueue = DispatchQueue(label: "gor.ipc.cmd", qos: .utility)
    func send(_ json: String) {
        let p = path
        let enqueued=ProcessInfo.processInfo.systemUptime
        IPCClient.cmdQueue.async {
            let diagnosticOldThreadName = Thread.current.name
            Thread.current.name = "ipc.cmd"
            defer { Thread.current.name = diagnosticOldThreadName }
            guard FileManager.default.fileExists(atPath: p) else { return }
            let began=ProcessInfo.processInfo.systemUptime
            _ = IPCClient.socketRoundtrip(path: p, payload: json + "\n", timeout: 0.5)
            let end=ProcessInfo.processInfo.systemUptime
            CommandLatencyTrace.shared.record(kind:"discrete",queuedMS:(began-enqueued)*1000,sendMS:(end-began)*1000)
        }
    }
    // ── Core POSIX primitive ────────────────────────────────────────────────
    static func socketRoundtrip(path: String, payload: String, timeout: TimeInterval, sendOnly: Bool = false) -> [String] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }
        let sec  = Int(timeout)
        let usec = suseconds_t((timeout - Double(sec)) * 1_000_000)
        var tv   = timeval(tv_sec: sec, tv_usec: usec)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr  = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 108) {
                    _ = strncpy($0, src, 107)
                }
            }
        }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connectResult: Int32 = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        var ok = false
        if connectResult == 0 {
            ok = true
        } else if errno == EINPROGRESS {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let timeoutMs = Int32(max(0, timeout) * 1000)
            let pollResult = poll(&pfd, 1, timeoutMs)
            if pollResult > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                var soError: Int32 = 0
                var soErrorLen = socklen_t(MemoryLayout<Int32>.size)
                let gotOpt = getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &soErrorLen)
                ok = (gotOpt == 0 && soError == 0)
            }
        }
        _ = fcntl(fd, F_SETFL, flags)
        guard ok else { return [] }
        let toSend = payload.hasSuffix("\n") ? payload : payload + "\n"
        // A stream write may accept only part of a JSON line. Never close
        // the request side until every byte has been written.
        let sentAll = toSend.utf8CString.withUnsafeBufferPointer { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            let byteCount = bytes.count - 1 // do not send the C terminator
            var offset = 0
            while offset < byteCount {
                let n = Darwin.write(fd, base.advanced(by: offset), byteCount - offset)
                if n > 0 { offset += n; continue }
                if n < 0 && errno == EINTR { continue }
                return false // timeout or peer closed; do not read a partial request
            }
            return true
        }
        guard sentAll else { return [] }
        // Lid-only publication needs no response. Waiting for EOF here previously
        // could spend the receive timeout on every camera frame.
        if sendOnly { return [] }
        Darwin.shutdown(fd, SHUT_WR)
        var buf = [UInt8](repeating: 0, count: 4096)
        var raw = Data()
        var responses=IPCResponseCounter(expected:payload.split(separator:"\n").count)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { break }
            let chunk=Data(buf.prefix(n))
            raw.append(chunk)
            if responses.consume(chunk) {break}
        }
        guard let str = String(data: raw, encoding: .utf8) else { return [] }
        return str.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    // ── Convenience: parse first response with a "data" field ───────────────
    static func parseFirst(_ lines: [String]) -> [String: Any] {
        for line in lines {
            guard let jd  = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
                  obj["data"] != nil
            else { continue }
            return obj
        }
        return [:]
    }
}
#endif
// END relocated IPCClient

// BEGIN relocated PersistentEventConnection (from PPController.swift, 195y G3, behavior unchanged)
#if canImport(AppKit)
// ================================================================
//  PersistentEventConnection - persistent mpv IPC event stream
// ================================================================
final class PersistentEventConnection {
    private let path: String
    private let queue = DispatchQueue(label: "gor.ipc.persistent", qos: .utility)
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var lineBuffer = Data()
    private var reconnectWorkItem: DispatchWorkItem?
    private var stopped = false
    private var reconnectDelay: TimeInterval = 0.25
    private static let maxReconnectDelay: TimeInterval = 5.0
    var onLine: (([String: Any]) -> Void)?
    private(set) var isConnected = false
    var onConnected: (() -> Void)?
    var workQueue: DispatchQueue { queue }
    init(path: String) {
        self.path = path
    }
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = false
            self.connect()
        }
    }
    func stop() {
        queue.async { [self] in
            self.stopped = true
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.teardown()
        }
    }
    func write(_ payload: String) {
        queue.async { [weak self] in
            guard let self, self.isConnected, self.fd >= 0 else { return }
            let toSend = payload.hasSuffix("\n") ? payload : payload + "\n"
            let sent: Int = toSend.withCString { Darwin.write(self.fd, $0, strlen($0)) }
            if sent < 0 || sent < toSend.utf8.count {
                self.teardown()
                self.scheduleReconnect()
            }
        }
    }
    // MARK: - Connection lifecycle
    private func connect() {
        guard !stopped else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            scheduleReconnect()
            return
        }
        let newFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard newFd >= 0 else { scheduleReconnect(); return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 108) {
                    _ = strncpy($0, src, 107)
                }
            }
        }
        let flags = fcntl(newFd, F_GETFL, 0)
        _ = fcntl(newFd, F_SETFL, flags | O_NONBLOCK)
        let connectResult: Int32 = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(newFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        var ok = false
        if connectResult == 0 {
            ok = true
        } else if errno == EINPROGRESS {
            var pfd = pollfd(fd: newFd, events: Int16(POLLOUT), revents: 0)
            if poll(&pfd, 1, 2000) > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                var soError: Int32 = 0
                var soErrorLen = socklen_t(MemoryLayout<Int32>.size)
                ok = (getsockopt(newFd, SOL_SOCKET, SO_ERROR, &soError, &soErrorLen) == 0 && soError == 0)
            }
        }
        _ = fcntl(newFd, F_SETFL, flags)
        guard ok else {
            Darwin.close(newFd)
            scheduleReconnect()
            return
        }
        fd = newFd
        isConnected = true
        reconnectDelay = 0.25
        lineBuffer.removeAll(keepingCapacity: true)
        var sndTimeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = setsockopt(newFd, SOL_SOCKET, SO_SNDTIMEO, &sndTimeout, socklen_t(MemoryLayout<timeval>.size))
        let src = DispatchSource.makeReadSource(fileDescriptor: newFd, queue: queue)
        src.setEventHandler { [weak self] in self?.handleReadable() }
        // I44: the cancel handler must close the captured fd; teardown() resets self.fd before it runs.
        src.setCancelHandler { Darwin.close(newFd) }
        src.resume()
        readSource = src
        onConnected?()
    }
    private func handleReadable() {
        let diagnosticOldThreadName = Thread.current.name
        Thread.current.name = "ipc.read"
        defer { Thread.current.name = diagnosticOldThreadName }
        guard fd >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &buf, buf.count)
        if n <= 0 {
            teardown()
            scheduleReconnect()
            return
        }
        lineBuffer.append(contentsOf: buf.prefix(n))
        drainCompleteLines()
    }
    private func drainCompleteLines() {
        // All onLine callbacks run synchronously on this one serial queue.
        // Their main.async playback updates preserve mpv event order.
        while let newlineIdx = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineIdx)
            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineIdx)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            onLine?(obj)
        }
    }
    private func teardown() {
        readSource?.cancel()
        readSource = nil
        isConnected = false
        fd = -1
    }
    private func scheduleReconnect() {
        guard !stopped else { return }
        isConnected = false
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
        reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)
    }
}
#endif
// END relocated PersistentEventConnection

// BEGIN relocated PollEngine (from PPController.swift, 195y G3, behavior unchanged)
#if canImport(AppKit)
// ================================================================
//  PollEngine - mpv property store and poll cadence
// ================================================================
final class PollEngine {
    private let connection: PersistentEventConnection
    private var source: DispatchSourceTimer?
    private var store = [String: Any]()
    private let openingLock=NSLock()
    private var openingGeneration:UInt64=0
    private var nextQueryId=9_197_000_001
    private var pendingQueries=[Int:(key:String,opening:UInt64,batch:UInt64?)]()
    private var receiverSession:()->String
    private let loadChallengeNamespace=UUID().uuidString
    private var loadChallenge:String {receiverSession()+":"+loadChallengeNamespace+":"+String(currentOpening())}
    private var loadStateSession=""
    private var loadStateOpening:UInt64=0
    private func acceptLoadState(_ data:Any?) {
        let session=receiverSession()
        guard !session.isEmpty,let state=data as? [String:Any],state["session"] as? String==session,
              state["challenge"] as? String==loadChallenge,
              let n=state["opening"] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              let opening=UInt64(exactly:n),opening>0,opening<9_007_199_254_740_990,
              let readyValue=state["ready"] as? NSNumber,CFGetTypeID(readyValue)==CFBooleanGetTypeID(),
              let path=state["path"] as? String,!path.isEmpty,store["path"] as? String==path else{return}
        if loadStateSession != session {loadStateSession=session;loadStateOpening=0}
        guard opening>=loadStateOpening else{return}
        let receiverAdvanced=opening>loadStateOpening
        loadStateOpening=opening
        if layoutReady && receiverAdvanced {
            purgeFileStateOnQueue() // a missed local start cannot retain the previous source geometry
            return // require a new challenge echo after revocation, not this pre-fence response
        }
        if !readyValue.boolValue {
            if layoutReady {purgeFileStateOnQueue()} // revoke queued snapshots and live layout together
            return
        }
        if !layoutReady {noteFileLoadedOnQueue()}
    }
    private var layoutReady=true // reconnect to existing playback need not emit file-loaded again
    private var layoutBatch:UInt64=0
    private var pendingLayout=[UInt64:[String:Any]]()
    private var activeLayoutReadbackTag:String?
    private var pendingLayoutTags=[UInt64:String]()
    private var committedLayoutTag:String?
    func requestCropLayoutReadback(_ tag:String) {
        connection.workQueue.async { [weak self] in
            guard let self else{return}
            self.activeLayoutReadbackTag=tag
            guard self.layoutReady else{return}
            self.writeQueries(Self.slowProps)
        }
    }
    private static let layoutKeys:Set<String>=["video-params/dw","video-params/dh","video-params/rotate","video-dec-params/dw","video-dec-params/dh","video-dec-params/w","video-dec-params/h","video-dec-params/par","video-crop","dwidth","dheight","path"]
    func noteFileLoadedOnQueue() {
        // Cancel any query issued before this decoder-load boundary, including same-path reopen.
        pendingQueries.removeAll();pendingLayout.removeAll();layoutReady=true
        installObservations(fileOnly:true)
    }
    private var nextObservationId=10_198_000_001
    private var activeObservations=[String:Int]()
    static func ownsQueryReply(_ id:Int)->Bool {(9_197_000_001..<10_197_000_000).contains(id)}
    static func ownsObservationAck(_ id:Int)->Bool {(10_198_000_001..<11_198_000_000).contains(id)}
    private func currentOpening()->UInt64 {openingLock.lock();defer{openingLock.unlock()};return openingGeneration}
    private func writeQueries(_ props:KeyValuePairs<Int,String>) {
        var lines=[String]()
        if pendingQueries.count>4096 {pendingQueries.removeAll();pendingLayout.removeAll()} // bounded, fail closed
        let isLayoutBatch=props.contains{$0.value=="video-params/dw"}
        if isLayoutBatch {
            // Fresh echo, not a retained publication, qualifies reconnect readiness.
            connection.write(MPVCommand.make(["script-message-to","gor_fit","crop-load-challenge",loadChallenge]))
            layoutBatch &+= 1;pendingLayout.removeAll();pendingLayoutTags.removeAll()
            if layoutReady {pendingLayout[layoutBatch]=[:];pendingLayoutTags[layoutBatch]=activeLayoutReadbackTag}
        }
        for (_,key) in props {
            if Self.layoutKeys.contains(key) && !layoutReady {continue}
            guard nextQueryId<10_197_000_000 else{break} // fail closed on launch-monotonic exhaustion
            let id=nextQueryId;nextQueryId+=1
            pendingQueries[id]=(key,currentOpening(),isLayoutBatch && Self.layoutKeys.contains(key) ? layoutBatch:nil)
            lines.append("{\"command\":[\"get_property\",\"\(key)\"],\"request_id\":\(id)}")
        }
        if !lines.isEmpty {connection.write(lines.joined(separator:"\n"))}
    }
    private func installObservations(fileOnly:Bool) {
        for (legacyId,key) in Self.observedProps {
            if fileOnly && !Self.fileScopedKeys.contains(key) {continue}
            if let old=activeObservations[key] {connection.write(MPVCommand.make(["unobserve_property",old]))}
            guard nextObservationId<11_198_000_000 else {activeObservations[key]=nil;continue}
            let id=nextObservationId;nextObservationId+=1;activeObservations[key]=id
            // osd-dimensions keeps its established availability ACK correlation.
            let ack=legacyId==122 ? 1122:id
            connection.write("{\"command\":[\"observe_property\",\(id),\"\(key)\"],\"request_id\":\(ack)}")
        }
    }
    // P4 (card 713): socket ARRIVAL order metadata. Arrival order only - it is
    // never a physical-causality proof. Mutated ONLY on the connection queue
    // (setStore funnel for stored keys, noteArrival for bypassing lines);
    // flush snapshots it atomically with the store.
    private var arrivalSeq: UInt64 = 0
    private var keySeq = [String: UInt64]()
    // P4: bumped at every (re)connect's subscription install (I34/I36 site).
    private var connGen: UInt64 = 0
    private var state: State = .paused
    private var tickCount: UInt64 = 0
    private var pendingKicks = 0
    private var enabled = false
    /// P4: per-flush metadata: key -> socket arrival seq, and the connection
    /// generation. Captured atomically with the store snapshot.
    struct Meta {
        let keySeq: [String: UInt64]
        let connGen: UInt64
        let openingGeneration:UInt64
        let layoutReadbackTag:String?
    }
    var onResults: (([String: Any], Meta) -> Void)?
    var onLayoutInvalidated:(()->Void)?
    // G4: optional engine-neutral sink, fired from the same flush with the
    // same snapshot, translated. Additive - onResults consumers unchanged.
    var onObservation: ((EngineObservedState, Meta) -> Void)?
    init(connection: PersistentEventConnection,receiverSession:@escaping ()->String) {
        self.connection = connection
        self.receiverSession=receiverSession
        connection.onConnected = { [weak self] in self?.subscribeObservations() }
    }
    func start() {
        connection.workQueue.async { [weak self] in
            guard let self else { return }
            self.enabled = true
            guard self.source == nil else { return }
            self.state = self.currentState()
            if self.state != .idle { self.startTimer() }
        }
    }
    func stop() {
        connection.workQueue.async { [self] in
            self.enabled = false
            self.source?.cancel()
            self.source = nil
        }
    }
    // MARK: - Poll state
    // ── Tier tables ─────────────────────────────────────────────────────────
    private static let fastProps: KeyValuePairs<Int, String> = [
        1: "time-pos",
        2: "sub-text",
        3: "sub-start",
        4: "sub-end",
        5: "sub-delay",
        6: "sub-scale",
        7: "sub-pos",
    ]
    private static let slowProps: KeyValuePairs<Int, String> = [
        45: "user-data/gor/crop-load-state",
        11: "video-params/dw",
        12: "video-params/dh",
        13: "video-params/stereo-in",
        41: "metadata",
        24: "video-dec-params/dw",
        25: "video-dec-params/dh",
        38: "video-dec-params/w",
        39: "video-dec-params/h",
        40: "video-dec-params/par",
        26: "video-crop",
        27: "secondary-sub-visibility",
        28: "avsync",
        29: "total-avsync-change",
        30: "frame-drop-count",
        31: "decoder-frame-drop-count",
        32: "vo-delayed-frame-count",
        33: "mistimed-frame-count",
        34: "video-sync",
        35: "audio-delay",
        36: "estimated-vf-fps",
        37: "display-fps", 42: "demuxer-cache-duration", 43: "paused-for-cache",
        // G4 (arch-195b): hwdec-current joins the slow tier (1 Hz) so the
        // engine-neutral observation surface can report the active hardware
        // decoder. The name comes from the EngineProperty mapping, never a
        // literal here. Additive poll line only; cadence unchanged.
        44: EngineProperty.hwdecCurrent.mpvName,
        14: "dwidth",
        15: "dheight",
        16: "path",
        17: "current-tracks/video/id",
        18: "current-tracks/video/albumart",
        19: "current-tracks/video/image",
        20: "video-params/rotate",
        // Block 180: polled on the slow cadence (1 Hz) because the
        // observe_property feed for osd-dimensions never delivered on the
        // real install - the Mac capture showed zero acceptances. Listed LAST
        // so its reply stamps after the geometry keys in every batch, which
        // keeps the accept-time postdate guard (arrival order) satisfied.
        // The id-122 subscription stays as a second feed.
        22: "osd-dimensions",
    ]
    private static let cacheProps: KeyValuePairs<Int, String> = [
        21: "demuxer-cache-state",
    ]
    private static let observedProps: KeyValuePairs<Int, String> = [
        101: "pause",
        102: "volume",
        103: "path",
        104: "media-title",
        105: "duration",
        106: "eof-reached",
        107: "idle-active",
        108: "current-tracks/sub/codec",
        109: "osd-width",
        110: "osd-height",
        111: "ytdl_is_live",
        112: "user-data/adaptive-brightness-enabled",
        113: "osd-msg1",
        114: "demuxer-via-network",
        115: "sub-visibility",
        116: "seeking",
        117: "current-tracks/video/id",
        118: "current-tracks/video/albumart",
        119: "current-tracks/video/image",
        120: "fullscreen",
        121: "mute",
        // P4 (card 713): mpv's own rendered-picture rect (margins include
        // video-zoom/pan/panscan/align; under a verified @gorcrop they
        // describe the cropped picture). HUD bounds only - see applyVideoFrame.
        122: "osd-dimensions",
        // 180d: the shader's live effective gap, published by vr180-look.lua
        // on init and every tune; chrome geometry must follow it mid-session.
        123: "user-data/vr180-look/physical-gap-frac",
        124: "current-tracks/sub/id",
        125: "secondary-sid",
        126: "sub-delay",
        127: "sub-scale",
        128: "sub-pos", 129: "container-fps", 130: "estimated-frame-count",
        131: "user-data/vr180-look/film-frame",
    ]
    // arch-195c N3: the applied-state receipt is NOT polled here. The shipped
    // Lua owns mpv-path route admission and the 3D-VERIFIED record; the
    // isolated Swift route store (ThreeDRoute.swift, gorav-side) is not fed
    // from the mpv path, so no extra observe reaches the shipped player.
    private static let fileScopedKeys: [String] = [
        "video-crop", "osd-dimensions", "time-pos", "duration", "sub-text", "sub-start", "sub-end",
        "video-dec-params/w", "video-dec-params/h", "video-dec-params/par", "video-dec-params/dw", "video-dec-params/dh", "video-params/dw", "video-params/dh", "video-params/stereo-in", "video-params/rotate",
        "dwidth", "dheight", "path", "metadata", "container-fps", "estimated-frame-count",
        "demuxer-cache-state", "demuxer-cache-duration", "paused-for-cache", "eof-reached", "ytdl_is_live",
        "current-tracks/sub/codec", "current-tracks/video/id",
        "current-tracks/video/albumart", "current-tracks/video/image",
    ]
    private static let fastIntervalMs = 200
    private static let slowEveryTicks: UInt64 = 5
    // ── Wiring from the connection (runs on its queue) ──────────────────────
    func handleLine(_ obj: [String: Any]) {
        guard let rid=obj["request_id"] as? Int,let query=pendingQueries.removeValue(forKey:rid),
              query.opening==currentOpening() else{return}
        if query.key=="user-data/gor/crop-load-state" {
            if obj["error"] as? String=="success" {acceptLoadState(obj["data"])}
            return
        }
        if let batch=query.batch {
            guard layoutReady,pendingLayout[batch] != nil else{return}
            pendingLayout[batch]![query.key]=(obj["error"] as? String)=="success" ? (obj["data"] ?? NSNull()):NSNull()
            if pendingLayout[batch]!.count==Self.layoutKeys.count,let values=pendingLayout.removeValue(forKey:batch) {
                guard let path=values["path"] as? String,!path.isEmpty,
                      store["path"] as? String==path else{return}
                for key in Self.layoutKeys {setStore(key,values[key])}
                committedLayoutTag=pendingLayoutTags.removeValue(forKey:batch)
                flush()
            }
            return
        }
        setStore(query.key,(obj["error"] as? String)=="success" ? obj["data"]:nil)
        if ["sub-end","current-tracks/video/image","demuxer-cache-state"].contains(query.key) {flush()}
    }
    func handlePropertyChange(_ obj: [String: Any]) {
        guard let name=obj["name"] as? String,let id=obj["id"] as? Int,activeObservations[name]==id else{return}
        if !layoutReady && (Self.layoutKeys.contains(name) && name != "path" || name=="osd-dimensions") {return}
        setStore(name,obj["data"])
        updateState()
        flush()
    }
    // I35 / TRAP-10: purge file-scoped values on the connection queue before later events.
    func purgeFileStateOnQueue(renewObservations:Bool=true,awaitingLoad:Bool=true) {
        openingLock.lock();openingGeneration &+= 1;openingLock.unlock()
        pendingQueries.removeAll();pendingLayout.removeAll();pendingLayoutTags.removeAll()
        activeLayoutReadbackTag=nil;committedLayoutTag=nil
        layoutReady=false // every reconnect/opening must requalify, even if a start event was missed
        let revokedGeneration=currentOpening()
        DispatchQueue.main.async { [weak self] in
            guard let self,self.currentOpening()==revokedGeneration else{return}
            self.onLayoutInvalidated?()
        }
        for key in PollEngine.fileScopedKeys {
            store.removeValue(forKey: key)
            keySeq.removeValue(forKey: key)
        }
        if renewObservations {installObservations(fileOnly:true)}
    }
    func primeDims() {
        connection.workQueue.async { [weak self] in
            self?.writeQueries(PollEngine.slowProps)
        }
    }
    func kick() {
        connection.workQueue.async { [weak self] in
            guard let self, self.source != nil else { return }
            self.pendingKicks = 2
            self.writeQueries(PollEngine.fastProps)
        }
    }
    // ── State machine ───────────────────────────────────────────────────────
    private enum State { case idle, paused, playing }
    private func currentState() -> State {
        if store["idle-active"] as? Bool == true { return .idle }
        if store["pause"] as? Bool ?? true { return .paused }
        return .playing
    }
    private func updateState() {
        let newState = currentState()
        guard newState != state else { return }
        state = newState
        guard enabled else { return }
        switch newState {
        case .idle:             parkTimer()
        case .paused, .playing: startTimer()
        }
    }
    // ── Store ───────────────────────────────────────────────────────────────
    private func setStore(_ key: String, _ value: Any?) {
        // P4: every stored change is stamped in socket arrival order.
        arrivalSeq &+= 1
        keySeq[key] = arrivalSeq
        if let value, !(value is NSNull) {
            store[key] = value
        } else {
            store.removeValue(forKey: key)
        }
    }
    // Flush after complete fast, video-identity slow and cache batches; never in fire().
    private func flush() {
        guard !store.isEmpty else { return }
        let snapshot = store
        let meta = Meta(keySeq: keySeq, connGen: connGen, openingGeneration:currentOpening(),layoutReadbackTag:committedLayoutTag)
        DispatchQueue.main.async { [weak self] in
            guard let self,self.currentOpening()==meta.openingGeneration else{return}
            self.onResults?(snapshot, meta)
            if let onObservation = self.onObservation {
                onObservation(EngineObservationTranslator.translate(snapshot), meta)
            }
        }
    }
    /// P4: barrier stamp for lines that bypass the store (GorCrop replies,
    /// chain readbacks). Connection queue only - never call from main.
    func noteArrival() -> UInt64 {
        arrivalSeq &+= 1
        return arrivalSeq
    }
    // ── Timer ───────────────────────────────────────────────────────────────
    private func startTimer() {
        guard source == nil else { return }
        let src = DispatchSource.makeTimerSource(queue: connection.workQueue)
        let pims = PollEngine.fastIntervalMs
        src.schedule(deadline: .now(), repeating: .milliseconds(pims), leeway: .milliseconds(pims / 2))
        src.setEventHandler { [weak self] in self?.fire() }
        src.resume()
        source = src
    }
    private func parkTimer() {
        source?.cancel()
        source = nil
    }
    // I34 I36: no time-pos observation; reinstall subscriptions after each socket reconnect.
    private func subscribeObservations() {
        connGen &+= 1
        purgeFileStateOnQueue(renewObservations:false,awaitingLoad:false)
        installObservations(fileOnly:false)
    }
    // I37 I42: poll demuxer-cache-state at 1Hz for loaded local and network files, paused too.
    private func fire() {
        guard enabled else { return }
        guard connection.isConnected else { return }
        tickCount &+= 1
        let slowDue = tickCount % PollEngine.slowEveryTicks == 0
        switch state {
        case .idle:
            return
        case .paused:
            guard slowDue || pendingKicks > 0 else { return }
            writeQueries(PollEngine.fastProps)
            if slowDue {
                writeQueries(PollEngine.slowProps)
                writeQueries(PollEngine.cacheProps)
            }
        case .playing:
            writeQueries(PollEngine.fastProps)
            if slowDue {
                writeQueries(PollEngine.slowProps)
                writeQueries(PollEngine.cacheProps)
            }
        }
        if pendingKicks > 0 { pendingKicks -= 1 }
    }
}
#endif
// END relocated PollEngine
