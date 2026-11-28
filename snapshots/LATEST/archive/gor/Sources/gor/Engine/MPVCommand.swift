// Engine/MPVCommand.swift
// Safe mpv IPC command construction with real JSON escaping.
// Uses: AppKit, CoreFoundation, Foundation, GorAVEmbeddedShell, Metal, Camera, Player, Session, UI
// Engine: both
import Foundation
import CoreFoundation
#if canImport(GorAVEmbeddedShell) && canImport(Metal)
import GorAVEmbeddedShell
import Metal
#endif

// ================================================================
//  MPVCommand - safe mpv IPC command construction
//  Owns: building mpv IPC command lines with real JSON escaping.
//  Contract: never hand-interpolate paths/URLs/titles into a JSON
//  command again - quote-only escaping breaks on backslashes,
//  newlines, and control characters (pass-5 #5).
// ================================================================

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


// Look/motion wire text: input wire owner. LookToolsRoute keeps its own copy (duplicate compatibility, not touched here).
enum LookMotionWire {
    static func json(kind: String, x: Int = 0, y: Int = 0, z: Int = 0, projection: Bool) -> String {
        if projection {return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-motion\",\"\(kind)\",\"\(x)\",\"\(y)\",\"\(z)\"]}"}
        if kind=="hold" {return "{\"command\":[\"script-message-to\",\"gor_fit\",\"hold\",\"\(x)\",\"\(y)\",\"\(z)\"]}"}
        return "{\"command\":[\"script-message-to\",\"gor_fit\",\"zoom\",\"\(z)\"]}"
    }
}

enum ClipboardShortcutKey: String { case c, g, z, x, o, f }
enum PhotonGrainTrim: String {
    case up = "photon-grain-size-trim-up", down = "photon-grain-size-trim-down", reset = "photon-grain-size-trim-reset"
}

// Subtitle menu operations (Next Channel, Load SRT). The mpv wire text is built here, in the Engine station, and nowhere else;
// callers send a typed operation. The embedded host interprets the same lines, so its path is unchanged.
fileprivate enum SubtitleMenuWire {
    static let nextChannel = #"{"command":["cycle","sub"]}"#
    static func loadFile(_ path: String) -> String { MPVCommand.make(["sub-add", path]) }
}
// Composition-boundary repair for these two operations only: the controller is held weakly through the narrow transport protocol
// (PlayerCommandTransport, declared below), so the same ipcCommand path runs and a released controller makes both a no-op.
@MainActor struct SubtitleMenuCommands {
    private weak var transport: PlayerCommandTransport?
    init(transport: PlayerCommandTransport) { self.transport = transport }
    func nextChannel() { transport?.ipcCommand(SubtitleMenuWire.nextChannel) }
    func loadFile(_ path: String) { transport?.ipcCommand(SubtitleMenuWire.loadFile(path)) }
}

// Keyboard-driven player commands for the input controller: typed operations only.
struct InputKeyCommands {
    // The controller's existing weak ipc closure, injected by the composition root; no actor annotation.
    private let ipcCommand: (String) -> Void
    private let projectionActive: () -> Bool  // read at the call, where the caller read vrModeEnabled before
    init(ipcCommand: @escaping (String) -> Void, projectionActive: @escaping () -> Bool) {
        self.ipcCommand = ipcCommand
        self.projectionActive = projectionActive
    }
    func clipboardShortcut(_ key: ClipboardShortcutKey) {
        ipcCommand("{\"command\":[\"keypress\",\"Meta+Alt+\(key.rawValue)\"]}")
    }
    func grainSizeTrim(_ trim: PhotonGrainTrim) {
        ipcCommand("{\"command\":[\"script-message-to\",\"photon_grain\",\"\(trim.rawValue)\"]}")
    }
    func cyclePause() { ipcCommand(#"{"command":["cycle","pause"]}"#) }
    /// Forwards one mpv key name; backslash and quote are escaped here, as the caller did before.
    func forwardKey(_ mpvKey: String) {
        let escaped = mpvKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        ipcCommand("{\"command\":[\"keypress\",\"\(escaped)\"]}")
    }
    func motionHold(x: Int, y: Int, z: Int) {
        ipcCommand(LookMotionWire.json(kind: "hold", x: x, y: y, z: z, projection: projectionActive()))
    }
    func addSubtitle(_ path: String) { ipcCommand(SubtitleMenuWire.loadFile(path)) }
    func appendPlay(_ path: String) { ipcCommand(MPVCommand.make(["loadfile", path, "append-play"])) }
    func motionStep(z: Int) {
        ipcCommand(LookMotionWire.json(kind: "step", z: z, projection: projectionActive()))
    }
}

// VR180 look wire text, one closed case per semantic operation. Payload types are the ones the controller already
// interpolates; Double and UInt64 go through string interpolation exactly as the old text did.
enum VR180LookWire {
    case setOutput(String)
    case planLockOn
    case planLockOff
    case routeComplete(revision: UInt64)
    case setEnabled(Bool)
    case setSwapEyes(Bool)
    case viewingCross(Bool)
    case surroundInvert(Bool)
    case setIPDmm(Double)
    case sourceEyeCrop(x: Double, y: Double, w: Double, h: Double)
    case setProjection(kind: String, aspect: Double)
    case nudge(yawRad: Double, pitchRad: Double, rollRad: Double)
    case nudgeFov(Double)
    case fullscreen(Bool)
    case internalMedia(Bool)
    case blinkLids(left: Double, right: Double, uncertain: Bool)
    case blinkAnalog(Bool)
    case seekRelative(Int)
    case cyclePause
    case setPause(Bool)
    case toolsActive(Bool)
    case fullFit(smooth: Bool)
    case resetOrientation
    case testVRModeReset
    case setPack(pack: Int, gain: Double, conv: Double, zoom: Double, soft: Double)
    case setOrientation(yaw: Double, pitch: Double, fov: Double, roll: Double, ipdNudge: Double, headX: Double, headY: Double, headZ: Double,
                        distArg: String, distReason: String, mmPerPx: Double, fusionRoll: Double, nativeRawRoll: Double, ordered: Bool)

    var json: String {
        switch self {
        case .setOutput(let o): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-output\",\"\(o)\"]}"
        case .planLockOn: return #"{"command":["script-message-to","vr180_look","vr180-look-plan-lock","on","true"]}"#
        case .planLockOff: return #"{"command":["script-message-to","vr180_look","vr180-look-plan-lock","off"]}"#
        case .routeComplete(let r): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-route-complete\",\"\(r)\",\"store-applier\"]}"
        case .setEnabled(let e): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-enabled\",\"\(e ? "true" : "false")\"]}"
        case .setSwapEyes(let s): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-swap-eyes\",\"\(s ? "1" : "0")\"]}"
        case .viewingCross(let v): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-viewing-cross\",\"\(v ? "1":"0")\"]}"
        case .surroundInvert(let v): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-surround-invert\",\"\(v ? "1":"0")\"]}"
        case .setIPDmm(let mm): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-ipd-mm\",\"\(mm)\"]}"
        case .sourceEyeCrop(let x, let y, let w, let h): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-source-eye-crop\",\"\(x)\",\"\(y)\",\"\(w)\",\"\(h)\"]}"
        case .setProjection(let k, let a): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-projection\",\"\(k)\",\"\(a)\"]}"
        case .nudge(let yaw, let pitch, let roll): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-nudge\",\"\(yaw)\",\"\(pitch)\",\"0\",\"\(roll)\"]}"
        case .nudgeFov(let f): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-nudge\",\"0\",\"0\",\"\(f)\"]}"
        case .fullscreen(let on): return on ? #"{"command":["set","fullscreen","yes"]}"# : #"{"command":["set","fullscreen","no"]}"#
        case .setPack(let pack, let gain, let conv, let zoom, let soft): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-pack\",\"\(pack)\",\"\(gain)\",\"\(conv)\",\"\(zoom)\",\"\(soft)\"]}"
        case .setOrientation(let yaw, let pitch, let fov, let roll, let ipdNudge, let headX, let headY, let headZ, let distArg, let distReason, let mmPerPx, let fusionRoll, let nativeRawRoll, let ordered):
            return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-orientation\",\"\(yaw)\",\"\(pitch)\",\"\(fov)\",\"\(roll)\",\"\(ipdNudge)\",\"\(headX)\",\"\(headY)\",\"\(headZ)\",\"\(distArg)\",\"\(distReason)\",\"\(mmPerPx)\",\"\(fusionRoll)\",\"\(nativeRawRoll)\"]\(ordered ? ",\"request_id\":194" : "")}"
        case .blinkLids(let left, let right, let uncertain): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-lids\",\"\(left)\",\"\(right)\",\"\(uncertain)\"]}"
        case .blinkAnalog(let on): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-blink-analog\",\"\(on)\"]}"
        case .seekRelative(let seconds): return "{\"command\":[\"seek\",\(seconds),\"relative\"]}"
        case .cyclePause: return #"{"command":["cycle","pause"]}"#
        case .setPause(let paused): return "{\"command\":[\"set_property\",\"pause\",\(paused)]}"
        case .toolsActive(let active): return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-tools-active\",\"\(active ? "true" : "false")\"]}"
        case .fullFit(let smooth): return smooth ? #"{"command":["script-message-to","vr180_look","vr180-look-smooth-fit"]}"# : #"{"command":["script-message-to","vr180_look","vr180-look-full-fit"]}"#
        case .resetOrientation:
            let args = ["0", "0", "135", "0", "0", "0", "0", "0"].map { "\"\($0)\"" }.joined(separator: ",")
            return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-orientation\",\(args)],\"request_id\":194}"
        case .testVRModeReset: return #"{"command":["set_property","user-data/gor-test-vr-mode",0]}"#
        case .internalMedia(let b): return "{\"command\":[\"set_property\",\"user-data/gor/3d-internal\",\(b)]}"
        }
    }
}

// Typed look operations for the VR180 controller. The Engine owns the wire; the controller keeps the
// measurement (points to radians) and holds this service, not a command-building closure call site.
// The send closure weak-captures the controller's typed command channel: a released
// owner turns sends into typed no-ops (the same contract the creator-captured ipc slot had).
struct VR180LookOperations {
    private let send: (String) -> Void
    init(send: @escaping (String) -> Void) { self.send = send }
    func nudge(yawRad: Double, pitchRad: Double, rollRad: Double) { send(VR180LookWire.nudge(yawRad: yawRad, pitchRad: pitchRad, rollRad: rollRad).json) }
    func nudgeFov(_ deltaFovDegrees: Double) { send(VR180LookWire.nudgeFov(deltaFovDegrees).json) }
}

extension VR180LookOperations {
    /// The channel-bound construction: the weak capture and the main-actor hop live here in
    /// the backend owner, so the Stereo controller never wires the send closure itself.
    init(channel: PlayerCommandTransport) {
        self.init(send: { [weak channel] json in
            MainActor.assumeIsolated { channel?.ipcCommand(json) }
        })
    }
}

/// Applied-command record surface for the store-applier egress; ThreeDStore's conformance
/// lives in the backend owner region, so the Stereo controller never wires the recorder.
@MainActor protocol VR180AppliedCommandRecorder: AnyObject {
    func recordAppliedCommand(_ command: String)
}

/// Store-applier command egress: the typed operation owns the raw command record and the
/// dispatch hop in their original order (record first, then send). The controller ships the
/// stamped JSON and keeps admission, revision and wire policy; a released channel turns the
/// dispatch into a typed no-op with the record intact.
struct VR180StoreCommandOperations {
    private weak var channel: (any PlayerCommandTransport)?
    private weak var recorder: (any VR180AppliedCommandRecorder)?
    init(channel: PlayerCommandTransport, recorder: VR180AppliedCommandRecorder) {
        self.channel = channel
        self.recorder = recorder
    }
    @MainActor func ship(_ json: String) {
        recorder?.recordAppliedCommand(json)
        channel?.ipcCommand(json)
    }
}

// VR180 look messages that were already built through JSONSerialization (so the output may be nil, as before).
enum VR180LookSerializedWire {
    case storeRevision(revision: UInt64, luaKind: String, vrEnabled: Bool, expectedLayout: Int, pack: Int, output: String, engine: String,
                       generation: UInt64, filename: String, pid: Int32)
    case parentFilmID(String)
    case showText(String, durationMs: Int)

    var json: String? {
        let object: [String: Any]
        switch self {
        case .storeRevision(let revision, let luaKind, let vrEnabled, let expectedLayout, let pack, let output, let engine, let generation, let filename, let pid):
            let command: [Any] = ["script-message-to", "vr180_look", "vr180-look-store-revision", String(revision), luaKind, "store-applier", String(vrEnabled), String(expectedLayout), String(pack), output, engine, String(generation), filename, String(pid)]
            object = ["command": command]
        case .parentFilmID(let film):
            object = ["command": ["set_property", "user-data/gor/3d-parent-film-id", film]]
        case .showText(let text, let durationMs):
            object = ["command": ["show-text", text, durationMs]]
        }
        return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

// Music-mode enter/leave command sequences, in the order the mode controller has always sent them.
// The transport is the controller's existing weak closure, handed in by the composition root, and
// the fit-script flag is read through a closure at the point the controller always read it (after stop and vid).
struct MusicModeCommands {
    private let ipcCommand: (String) -> Void
    private let gorFitScriptActive: () -> Bool
    init(ipcCommand: @escaping (String) -> Void, gorFitScriptActive: @escaping () -> Bool) {
        self.ipcCommand = ipcCommand
        self.gorFitScriptActive = gorFitScriptActive
    }
    func leaveMusicMode() {
        ipcCommand(#"{"command":["stop"]}"#)
        ipcCommand(#"{"command":["set","vid","auto"]}"#)
        if !gorFitScriptActive() { ipcCommand(#"{"command":["set","geometry","38%+50%+50%"]}"#) }
        ipcCommand(#"{"command":["set","keepaspect","yes"]}"#)
    }
    func enterMusicMode(size: Int) {
        ipcCommand(#"{"command":["stop"]}"#)
        ipcCommand(#"{"command":["set","vid","auto"]}"#)
        ipcCommand("{\"command\":[\"set\",\"geometry\",\"\(size)x\(size)\"]}")
        ipcCommand(#"{"command":["set","keepaspect","no"]}"#)
    }
}

// Typed media-file commands for the music panel drop target. The transport is a narrow
// protocol so the caller holds a service with two operations, not a command channel.
@MainActor protocol PlayerCommandTransport: AnyObject {
    func ipcCommand(_ json: String)
}

/// Engine-owned dispatch for the look-capture request line: the weak typed channel replaces the
/// raw sendScriptMessageLine bridge. send runs on the main actor (callers hop there); a released
/// controller is a typed refusal (false), never a write into a dead socket.
final class PhotonLookCaptureDispatch {
    private weak var transport: (any PlayerCommandTransport)?
    init(transport: PlayerCommandTransport) { self.transport = transport }
    @MainActor func send(_ line: String) -> Bool {
        guard let transport else { return false }
        transport.ipcCommand(line)
        return true
    }
}

@MainActor struct PlayerMediaFileCommands {
    private weak var transport: PlayerCommandTransport?
    init(transport: PlayerCommandTransport) { self.transport = transport }
    func addSubtitle(_ path: String) { transport?.ipcCommand(MPVCommand.make(["sub-add", path])) }
    func loadFile(_ path: String) { transport?.ipcCommand(MPVCommand.make(["loadfile", path])) }
}

// Live-channel start batch: photon live flags, then loadfile. One newline-joined frame for batchIPC.
enum IPTVPlaybackBatch {
    static func load(_ url: String, photonEnabled: Bool) -> String {
        [
            #"{"command":["script-message-to","photon","set-live","true"]}"#,
            #"{"command":["script-message-to","photon","set-user-enabled","\#(photonEnabled ? "true" : "false")"]}"#,
            MPVCommand.make(["loadfile", url]),
        ].joined(separator: "\n")
    }
}

// Wire text for the menu query operations; the Engine station owns command construction.
enum PlayerMenuQueryCommand {
    /// video-crop, dwidth and dheight, one command per line, in the order the pip crop log reads them back.
    static var cropDiagnosticPayload: String {
        MPVCommand.make(["get_property", "video-crop"]) + "\n" + MPVCommand.make(["get_property", "dwidth"]) + "\n" + MPVCommand.make(["get_property", "dheight"])
    }

    /// Set sub-pos, then read it back.
    static func subtitlePositionPresetPayload(_ pos: Int) -> String {
        MPVCommand.make(["set_property", "sub-pos", pos]) + "\n" + MPVCommand.make(["get_property", "sub-pos"])
    }
}

// BEGIN PlayerMenuQueryOperations.swift (r117: moved into the canonical backend owner region;
// the standalone file is retired. One intentional delta from the old file: query is
// fileprivate so the exportColourProbe composition below can bind the typed query seam
// without re-opening it to the UI.)
/// Synchronous menu query transport, held weakly: IPCClient owns socket
/// deadlines, write/read framing and the reply buffer. A released client turns
/// queries into empty replies, and every method keeps its empty-reply fallback
/// instead of blocking on a dead socket.
protocol PlayerMenuQueryChannel: AnyObject {
    func queryBatch(_ payload: String, timeout: TimeInterval) -> [String]
}
#if canImport(AppKit)
extension IPCClient: PlayerMenuQueryChannel {}

/// Station-owned synchronous menu query boundary. Callers retain UI state,
/// embedded-backend decisions and OSD. Transport and reply selection preserve
/// the existing per-call deadlines and wire order, including path fencing.
/// Reply parsing is the Engine-owned IPCClient.parseFirst.
struct PlayerMenuQueryOperations {
    private weak var channel: (any PlayerMenuQueryChannel)?

    init(channel: PlayerMenuQueryChannel) { self.channel = channel }

    fileprivate func query(_ payload: String, timeout: TimeInterval) -> [String] {
        channel?.queryBatch(payload, timeout: timeout) ?? []
    }

    func payload(_ payload: String, requiringWriteSuccess: Bool = false) -> [String: Any] {
        let lines = query(payload, timeout: 0.3)
        if requiringWriteSuccess {
            let replies = lines.compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            guard replies.first?["error"] as? String == "success" else { return [:] }
        }
        return IPCClient.parseFirst(lines)
    }

    func onTop() -> Bool? {
        IPCClient.parseFirst(query(#"{"command":["get_property","ontop"]}"#, timeout: 0.15))["data"] as? Bool
    }

    func tracks() -> (path: String, tracks: [[String: Any]]) {
        let path = IPCClient.parseFirst(query(#"{"command":["get_property","path"]}"#, timeout: 0.15))["data"] as? String ?? ""
        let tracks = IPCClient.parseFirst(query(#"{"command":["get_property","track-list"]}"#, timeout: 0.15))["data"] as? [[String: Any]] ?? []
        let after = IPCClient.parseFirst(query(#"{"command":["get_property","path"]}"#, timeout: 0.15))["data"] as? String ?? ""
        return path == after ? (path, tracks) : ("", [])
    }

    func audioDevices() -> (current: String, devices: [(name: String, label: String)]) {
        let current = IPCClient.parseFirst(query(#"{"command":["get_property","audio-device"]}"#, timeout: 0.15))["data"] as? String ?? "auto"
        let raw = IPCClient.parseFirst(query(#"{"command":["get_property","audio-device-list"]}"#, timeout: 0.15))["data"] as? [[String: Any]] ?? []
        let devices = raw.compactMap { entry -> (name: String, label: String)? in
            guard let name = entry["name"] as? String else { return nil }
            return (name, entry["description"] as? String ?? name)
        }
        return (current, devices)
    }

    func cropDiagnosticValues(_ payload: String) -> [String] {
        query(payload, timeout: 0.3).compactMap { IPCClient.parseFirst([$0])["data"] }.map { "\($0)" }
    }

    /// video-crop, dwidth and dheight in that order: the payload the pip crop log reads back.
    func cropDiagnosticValues() -> [String] {
        cropDiagnosticValues(PlayerMenuQueryCommand.cropDiagnosticPayload)
    }

    /// Set sub-pos then read it back; the reply only counts when the write succeeded.
    func subtitlePositionPresetReply(_ pos: Int) -> [String: Any] {
        payload(PlayerMenuQueryCommand.subtitlePositionPresetPayload(pos), requiringWriteSuccess: true)
    }
}
#endif
// END PlayerMenuQueryOperations.swift

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
    /// True only on the scripted token-bound crop-packet arm: the Lua receiver fences that arm by
    /// (token,path,intent,motion,sequence), so its intermediates may skip the reply wait. The raw
    /// set_property fallback has no receiver fence and keeps the reply wait on every packet.
    let receiverFenced:Bool
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
        guard scripted else {return PlayerCropPacket(lines:lines,crop:nil,receiverFenced:false)}
        // Keep the old serialization path and refusal, including first-command
        // shape, so packet framing and acceptance identity do not drift.
        guard let token,let rowsData=("["+lines.joined(separator:",")+"]").data(using:.utf8),
              let rows=try? JSONSerialization.jsonObject(with:rowsData) as? [[String:Any]],
              let command=rows.first?["command"] as? [String],command.count==3 else{return nil}
        sequence &+= 1
        let envelope:[String:Any]=["commands":rows,"intent":String(intent),"motion":String(motion),"sequence":String(sequence),"final":final]
        guard let bytes=try? serialize(envelope),let payload=String(data:bytes,encoding:.utf8) else{return nil}
        return PlayerCropPacket(lines:[MPVCommand.make(["script-message-to","gor_fit","crop-packet",payload,source,token])],crop:command[2],receiverFenced:true)
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
// Weak typed channels replace the closure tuple: each backend path is one
// narrow protocol, so a released controller or connection turns the operation
// into a no-op instead of a send into a dead socket. The command channel is
// the same PlayerCommandTransport the subtitle menu service uses: PPController's
// main-thread ipcCommand keeps its stop/loadfile fencing for every line here.
protocol PlayerPersistentWriteChannel: AnyObject {
    func write(_ payload: String)
}
protocol PlayerCropPacketChannel: AnyObject {
    func sendCropPacket(_ lines: [String], generation: UInt64, final: Bool, receiverFenced: Bool)
    func resetCropPackets(_ generation: UInt64)
}
struct PlayerPlaybackOperations {
    private weak var command: (any PlayerCommandTransport)?
    private weak var persistent: (any PlayerPersistentWriteChannel)?
    private weak var packet: (any PlayerCropPacketChannel)?
    init(command: PlayerCommandTransport, persistent: PlayerPersistentWriteChannel, packet: PlayerCropPacketChannel) {
        self.command = command
        self.persistent = persistent
        self.packet = packet
    }
    @MainActor func publish(_ sample: PlayerCropSample) { command?.ipcCommand(sample.line) }
    func deliver(_ value: PlayerCropPacket, generation: UInt64, final: Bool) { packet?.sendCropPacket(value.lines, generation: generation, final: final, receiverFenced: value.receiverFenced) }
    func resetCrop(_ generation: UInt64) { packet?.resetCropPackets(generation) }
    func fenceCropIntent() { persistent?.write(MPVCommand.make(["script-message-to", "gor_fit", "crop-intent-fence"])) }
    func fenceCropSeek() { persistent?.write(MPVCommand.make(["script-message-to", "gor_fit", "crop-seek-fence"])) }
    @MainActor func fitAnchor(_ anchor: String) { command?.ipcCommand(MPVCommand.make(["set_property", "user-data/gor/fit-anchor", anchor])) }
    @MainActor func pause() { command?.ipcCommand(MPVCommand.make(["set_property", "pause", true])) }
    @MainActor func photonLive() { command?.ipcCommand(#"{"command":["script-message-to","photon","set-live","true"]}"#) }
}
#if canImport(AppKit)
extension PersistentEventConnection: PlayerPersistentWriteChannel {}
extension IPCClient: PlayerCropPacketChannel {}
extension ThreeDStore: VR180AppliedCommandRecorder {}

/// The controller's typed surface to the persistent event connection: exactly the members
/// the controller uses (writes come through the refined PlayerPersistentWriteChannel), so
/// the controller holds a typed channel instead of the concrete handle. Construction stays
/// on the connection's existing owner path in the controller's attach sequence.
protocol PlayerPersistentEventChannel: PlayerPersistentWriteChannel {
    var onLine: (([String: Any]) -> Void)? { get set }
    var isConnected: Bool { get }
    var onConnected: (() -> Void)? { get set }
    var onDisconnected: (() -> Void)? { get set }
    var onExportEntryDropped: ((PersistentEventConnection.ExportCommandTag, String) -> Void)? { get set }
    var workQueue: DispatchQueue { get }
    func start()
    func stop()
    func dropExportRun(_ runId: String)
    func writeAdmitted(_ payload: String) -> Bool
    func noteExportLoad(session: String, opening: UInt64)
    func enqueueExportLine(_ payload: String, session: String, opening: UInt64, runId: String?, attempt: UInt64?) -> Bool
}
extension PersistentEventConnection: PlayerPersistentEventChannel {}
#endif
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
#if canImport(AppKit)
enum HoverPreviewTransport {
    static func quit(socketPath: String) {
        _ = IPCClient.socketRoundtrip(path: socketPath, payload: "{\"command\":[\"quit\"]}\n", timeout: 0.25, sendOnly: true)
    }
}
#endif
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
    struct Packet { let payload:String; let generation:UInt64; let final:Bool; let at:Double; let receiverFenced:Bool }
    private let lock=NSLock()
    private var generation:UInt64=0
    private var pending:Packet?
    private var running=false
    private var finalOffered=false
    func reset(_ next:UInt64) {
        lock.lock();defer {lock.unlock()}
        generation=next;pending=nil;finalOffered=false
    }
    func offer(_ payload:String,generation next:UInt64,final:Bool,receiverFenced:Bool)->Bool {
        lock.lock();defer {lock.unlock()}
        guard generation==next,!finalOffered else {return false}
        pending=Packet(payload:payload,generation:next,final:final,at:ProcessInfo.processInfo.systemUptime,receiverFenced:receiverFenced)
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
            // The reply wait is head-of-line blocking on this serial queue. It is skipped only where a
            // receiver-side fence makes a superseded packet harmless: scripted crop-packet intermediates
            // (receiverFenced, not final). Finals and the raw fallback keep the existing reply wait;
            // cross-socket application order is not claimed.
            let began=ProcessInfo.processInfo.systemUptime
            _=IPCClient.socketRoundtrip(path:path,payload:packet.payload,timeout:0.5,sendOnly:!packet.final && packet.receiverFenced)
            let end=ProcessInfo.processInfo.systemUptime
            CommandLatencyTrace.shared.record(kind:"crop",queuedMS:(began-packet.at)*1000,sendMS:(end-began)*1000)
        }
        // Re-enqueue, never loop here: discrete commands already queued keep their order.
        if let next=cropPacketSlot.finish() {IPCClient.cmdQueue.async { [weak self] in self?.drainCropPacket(scheduled:next) }}
    }
    func sendCropPacket(_ lines:[String],generation:UInt64,final:Bool,receiverFenced:Bool) {
        guard !lines.isEmpty else{return}
        let payload=lines.joined(separator:"\n")+"\n"
        if cropPacketSlot.offer(payload,generation:generation,final:final,receiverFenced:receiverFenced) {
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

extension IPCClient {
    /// One get_property read: the "data" field of the first reply, nil when mpv gave none.
    func propertyValue(_ name: String, timeout: TimeInterval) -> Any? {
        IPCClient.parseFirst(queryBatch(MPVCommand.make(["get_property", name]), timeout: timeout))["data"]
    }
}
#endif
// END relocated IPCClient

// BEGIN relocated PersistentEventConnection (from PPController.swift, 195y G3, behavior unchanged)
#if canImport(AppKit)
// ================================================================
//  PersistentEventConnection - persistent mpv IPC event stream
// ================================================================
/// Weak back-reference for the outbox transport closure built inside PersistentEventConnection.init (see there).
private final class WeakConnectionBox { weak var owner: PersistentEventConnection? }

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
    /// Owner queue. The export seal query client's reply sink (ExportSealQueryClient.handleReply): true = the reply belonged to the seal range and was consumed.
    /// Unbound by default: the live product keeps no seal channel (activation is a separate step).
    var sealReplySink: (([String: Any]) -> Bool)?
    private(set) var isConnected = false
    var onConnected: (() -> Void)?
    /// Fired on the owner queue when a live connection goes down (read/write failure, teardown, stop): the composition binds export attempt abandonment
    /// and any per-connection cleanup here. Not fired for a connect attempt that never came up.
    var onDisconnected: (() -> Void)?
    /// EVERY queued export entry that will never be written gets one typed terminal result here (connection lost, stopped, stale generation). State is
    /// updated and the outbox drained BEFORE the callback runs, so a reentrant callback never sees the dead entry as live.
    var onExportEntryDropped: ((ExportCommandTag, String) -> Void)?
    /// Drains the outbox with a typed terminal result per entry. Caller holds no lock; state must already reflect the terminal condition.
    /// (Superseded by the outbox core's cancelAll; kept private call sites migrated.)
    var workQueue: DispatchQueue { queue }
    /// The ONE write cursor for the shared socket: export lines AND ordinary commands are admitted here (bounded, tagged) and written by the
    /// owner-turn drain. A partial line is finished or killed before any other line is attempted: no writer can interleave into a partial
    /// export line and corrupt the JSON stream.
    private let exportOutboxCore: ExportWireOutboxCore
    private var exportFlushScheduled = false
    /// Ordinary writes refused by a full outbox (never silent: counted; logged first and every 64th).
    private var ordinaryWriteDrops = 0
    private var connectionSerial: UInt64 = 0
    /// Maps one Darwin.write on the live NONBLOCKING fd onto the core's typed write result. EINTR is surfaced (the core bounds its continue),
    /// EAGAIN is terminal at the core (never retried here), anything else is a dead peer.
    private func socketWrite(_ bytes: [UInt8]) -> Result<Int, ExportWireWriteFailure> {
        let n: Int = bytes.withUnsafeBufferPointer { buf in Darwin.write(fd, buf.baseAddress!, buf.count) }
        if n >= 0 { return .success(n) }
        if errno == EINTR { return .failure(.interrupted) }
        if errno == EAGAIN || errno == EWOULDBLOCK { return .failure(.wouldBlock) }
        return .failure(.peerClosed)
    }
    init(path: String) {
        self.path = path
        OwnerQueue.install(queue)   // reentrancy-safe owner-queue reads (OwnerQueue.sync)
        // The transport needs `self`, but a closure may not capture `self` (not even weakly) until every stored property is set, and exportOutboxCore is the last one.
        // So it captures a weak box that is bound right after the assignment: same behaviour as `[weak self]` (a write after deallocation is a dead peer), no retain cycle,
        // and nothing can write through it before the binding because the outbox is only drained from the owner queue after init returns.
        let writeTarget = WeakConnectionBox()
        exportOutboxCore = ExportWireOutboxCore(epoch: 0, transport: { b in writeTarget.owner?.socketWrite(b) ?? .failure(.peerClosed) })
        writeTarget.owner = self
        exportOutboxCore.onTerminal = { [weak self] e, r in
            self?.onExportEntryDropped?(ExportCommandTag(connection: e.connectionEpoch, session: e.loadSession, opening: e.loadOpening, runId: e.runId, attempt: e.attempt), r)
        }
        exportOutboxCore.onDead = { [weak self] in self?.teardown(); self?.scheduleReconnect() }
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
            self.exportOutboxCore.cancelAll("stopped")   // terminal: every queued entry gets its typed result, nothing survives an explicit stop
            self.teardown()
        }
    }
    // MARK: - Export wire persistent enqueue
    /// The binding of ONE queued export line: the connection generation it was queued on, the owner load (session+opening), the prepared run and the
    /// settlement attempt it serves. A line is never carried across a reconnect: teardown drops the whole outbox, flush drops any entry whose tag is not
    /// the live generation, and enqueue refuses while disconnected. A stale queued request never runs on a new load; the attempt is notified through
    /// onDisconnected (the composition binds it to the settlement tracker's abandon) and the seam demands a fresh prepare.
    struct ExportCommandTag: Equatable {
        let connection: UInt64
        let session: String
        let opening: UInt64
        let runId: String?
        let attempt: UInt64?
    }
    /// The export wire's real enqueue binding: the line ENTERS the connection-owned outbox first (FIFO, tagged), then a drain is scheduled as its own owner-queue item.
    /// Bool = the line entered the outbox ("queued"), never "delivered" and never "accepted by the scripts". Enqueue-only contract: no reply wait, no callback into
    /// the caller, no socket I/O before the return, so the lease source may call it while holding its condition lock (admission refusals are delivered as typed
    /// terminals on the next owner drain turn, never synchronously). The outbox is bounded: a full outbox refuses (false) rather than growing unbounded or
    /// dropping silently. A disconnected or reconnecting socket REFUSES: export commands never survive a reconnect. A tag from a new load purges the old
    /// load's still-queued lines (typed "load-changed"): a stale queued request never runs on a new load.
    /// The live connection generation for tag building (reentrancy-safe owner-queue read).
    var exportConnectionSerial: UInt64 { OwnerQueue.sync(queue) { connectionSerial } }
    func enqueueExportLine(_ payload: String, tag: ExportCommandTag) -> Bool {
        OwnerQueue.sync(queue) { self.admitExportLine(payload, tag: tag) }
    }
    /// ONE owner-queue turn (the single enqueue transaction): the caller's tag is CLAIM, never scope authority; it is validated against the
    /// connection's trusted scope (set by the real owner load-change path via noteExportLoad, and by setTransport at connect). A mismatch
    /// refuses fail-closed; it never mutates the scope. Must run on the owner queue.
    private func admitExportLine(_ payload: String, tag: ExportCommandTag) -> Bool {
        guard !self.stopped, self.isConnected, tag.connection == self.connectionSerial,
              tag.session == self.exportOutboxCore.loadSession, tag.opening == self.exportOutboxCore.loadOpening else { return false }
        let accepted = self.exportOutboxCore.enqueue(ExportWireOutboxCore.Entry(connectionEpoch: tag.connection, loadSession: tag.session,
                                                                                loadOpening: tag.opening, runId: tag.runId, attempt: tag.attempt, line: payload))
        if accepted { self.scheduleExportFlush() }
        return accepted
    }
    /// The owner's real load-change path (PollEngine's file-loaded handling): the trusted load scope advances and the old load's still-queued

    /// Run invalidation for still-queued lines of a dead run (typed "run-invalidated"); an already-sent line's cancellation is the run
    /// invalidation upstream, never an un-send.
    /// Composition proof of the owner-queue identity (d): the export composition binds its owner-queue work (queued-run purge, owned commit,
    /// reset emit) to THIS queue instance, sourced from the engine object itself, never from a caller-supplied queue.
    var exportOwnerQueue: DispatchQueue { queue }

    func dropExportRun(_ runId: String) {
        OwnerQueue.sync(queue) { self.exportOutboxCore.dropRun(runId) }
    }
    /// The export emitter's Engine-owned mint: the caller hands engine-neutral scope legs (owner session/opening, run, attempt) with the line;
    /// the ExportCommandTag type and the connection serial never leave Engine — Player never mints or names a tag. Same enqueue contract as the
    /// tag-taking overload (admission-only, typed terminals on a later owner turn).
    func enqueueExportLine(_ payload: String, session: String, opening: UInt64, runId: String?, attempt: UInt64?) -> Bool {
        // ONE owner-queue transaction (tek-transaction enqueue merge): the connection serial is read and the tag validated+admitted in the
        // SAME owner turn. The two-hop shape (serial read, then admission) let a reconnect land between them, minting a tag the admission
        // then refused fail-closed; merged, mint and admission are atomic.
        OwnerQueue.sync(queue) {
            self.admitExportLine(payload, tag: ExportCommandTag(connection: self.connectionSerial, session: session, opening: opening, runId: runId, attempt: attempt))
        }
    }
    /// The seal-query request-id range. Derived from a survey of every request-id allocation in this tree: 1122 (osd-dims ack), 1_000_000..<2_000_000 (clamp fence),
    /// 2_000_000..<3_000_000 (crop MPV), >= 3_000_001 open-ended (OSD chain, launch-monotonic from 3_000_001), 9_194_001..<9_195_000 and 9_195_001 (film),
    /// 9_196_000_001..<9_197_000_000 (crop packet), 9_197_000_001..<10_197_000_000 (PollEngine). The first block above every bounded allocation is chosen. The OSD chain counter is now explicitly bounded
    /// (PPController.osdQueryIdRange = 3_000_001..<9_000_000, exhaustion refuses, no reuse), so the seal block is partitioned from it by construction, not by "unreachable".
    /// The seal block's upper bound is exclusive; 10_198_000_000 is unassigned and 10_198_000_001..<11_198_000_000 is the observation-ACK space (PollEngine.ownsObservationAck).
    static let sealQueryIdRange = 10_197_000_000..<10_198_000_000
    /// The chain-dirty read's request ids: its own exclusive block directly above the OSD chain block (PPController.osdQueryIdRange ends at 9_000_000) and far below the film block
    /// (9_194_001...). Disjoint from every other allocation above; launch-monotonic in the client, exhaustion refuses.
    static let sealDirtyQueryIdRange = 9_000_000..<9_100_000
    /// ONE tagged get_property of user-data/photon/chain-dirty ("yes"/"no", photon.lua), same export outbox/scope tag legs as the seal poll. Enqueue-only.
    func enqueueSealDirtyPoll(queryId: Int, session: String, opening: UInt64, runId: String?, attempt: UInt64?) -> Bool {
        guard Self.sealDirtyQueryIdRange.contains(queryId) else { return false }
        return enqueueExportLine("{\"command\":[\"get_property\",\"user-data/photon/chain-dirty\"],\"request_id\":\(queryId)}", session: session, opening: opening, runId: runId, attempt: attempt)
    }
    /// ONE tagged get_property of the owner-side chain-seal property, through the SAME export outbox as the request line (typed purge on load change / run
    /// invalidation / reconnect; never replayed). Enqueue-only: Bool = entered the outbox, never delivered. Same scope tag legs as enqueueExportLine.
    func enqueueSealPoll(queryId: Int, session: String, opening: UInt64, runId: String?, attempt: UInt64?) -> Bool {
        guard Self.sealQueryIdRange.contains(queryId) else { return false }
        return enqueueExportLine("{\"command\":[\"get_property\",\"user-data/photon/chain-seal\"],\"request_id\":\(queryId)}", session: session, opening: opening, runId: runId, attempt: attempt)
    }
    private func scheduleExportFlush() {
        guard !exportFlushScheduled else { return }
        exportFlushScheduled = true
        queue.async { [weak self] in
            guard let self else { return }
            self.exportFlushScheduled = false
            self.flushExportOutbox()
        }
    }
    /// lines die typed ("load-changed") — a stale queued request never runs on a new load. This is the ONLY scope authority.
    func noteExportLoad(session: String, opening: UInt64) {
        OwnerQueue.sync(queue) { self.exportOutboxCore.noteLoad(session: session, opening: opening) }
    }
    /// Owner queue only, its own turn: delivers deferred admission terminals, then writes queued lines FIFO over the live NONBLOCKING socket under the
    /// core's per-turn budget. EAGAIN mid-line is terminal at the core (typed, naming the offset; the socket latches dead; nothing is replayed): the
    /// onDead hook tears the connection down. A budgeted yield re-schedules the next turn instead of occupying the owner.
    private func flushExportOutbox() {
        guard isConnected, fd >= 0 else { return }
        exportOutboxCore.drain()
        if exportOutboxCore.pendingCount > 0 { scheduleExportFlush() }
    }
    func write(_ payload: String) {
        queue.async { [weak self] in
            guard let self, self.isConnected, self.fd >= 0 else {
                // A control line that arrives while disconnected never entered the wire: never silent.
                self?.ordinaryWriteDrops &+= 1
                if let s = self, s.ordinaryWriteDrops == 1 || s.ordinaryWriteDrops % 64 == 0 {
                    NSLog("[ipc] ordinary write dropped (disconnected), total=\(s.ordinaryWriteDrops)")
                }
                return
            }
            // Every writer of the shared socket goes through the ONE outbox cursor: a partial export line is finished or killed before any other line
            // is attempted, so an ordinary command can never interleave into a partial export line and corrupt the JSON stream. Ordinary lines carry
            // the current scope (no run/attempt) and the same typed terminals on purge.
            let e = ExportWireOutboxCore.Entry(connectionEpoch: self.exportOutboxCore.connectionEpoch, loadSession: self.exportOutboxCore.loadSession,
                                               loadOpening: self.exportOutboxCore.loadOpening, runId: nil, attempt: nil, line: payload)
            // Ordinary control/subscription writes must make progress in THIS owner
            // turn, before the next queued load callback can purge the outbox.
            // Keep the single FIFO cursor: never write directly around an export.
            // Drain bounded work first if the shared queue is full; a dead socket
            // still refuses and never replays into a new connection.
            if self.exportOutboxCore.pendingCount >= self.exportOutboxCore.maxPending {
                self.flushExportOutbox()
            }
            guard self.isConnected, self.fd >= 0 else { return }
            if self.exportOutboxCore.enqueue(e) { self.flushExportOutbox() }
            else {
                // The pre-outbox writes never lost a control line silently; keep a full outbox visible (bounded log).
                self.ordinaryWriteDrops &+= 1
                if self.ordinaryWriteDrops == 1 || self.ordinaryWriteDrops % 64 == 0 {
                    NSLog("[ipc] ordinary write dropped (outbox full), total=\(self.ordinaryWriteDrops)")
                }
            }
        }
    }
    /// Synchronous admission for fence-tracked commands: true ONLY when the line provably entered the outbox
    /// under the live scope, so the caller's ACK expectation is real. false = nothing was queued (disconnected
    /// or full): the caller must fall back NOW instead of waiting on an ACK that can never arrive. Runs the
    /// ONE enqueue transaction on the owner queue (reentrancy-safe read); the write itself still drains later.
    func writeAdmitted(_ payload: String) -> Bool {
        OwnerQueue.sync(queue) {
            guard self.isConnected, self.fd >= 0 else { return false }
            let e = ExportWireOutboxCore.Entry(connectionEpoch: self.exportOutboxCore.connectionEpoch, loadSession: self.exportOutboxCore.loadSession,
                                               loadOpening: self.exportOutboxCore.loadOpening, runId: nil, attempt: nil, line: payload)
            let admitted = self.exportOutboxCore.enqueue(e)
            if admitted { self.scheduleExportFlush() }
            return admitted
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
        guard ok else {
            Darwin.close(newFd)
            scheduleReconnect()
            return
        }
        // The live socket stays NONBLOCKING (set for the connect handshake above) and the mode is verified, not assumed: a blocking Darwin.write on the
        // owner queue could park the ACK reads this same queue serves. SIGPIPE is suppressed on the ACTUAL socket and verified: a broken peer must never
        // kill the process mid-write. A socket that cannot prove either is refused (fail closed).
        let liveFlags = fcntl(newFd, F_GETFL, 0)
        var noSigPipe: Int32 = 1
        guard liveFlags >= 0, (liveFlags & O_NONBLOCK) != 0,
              setsockopt(newFd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            Darwin.close(newFd)
            scheduleReconnect()
            return
        }
        fd = newFd
        isConnected = true
        connectionSerial &+= 1   // a new connection generation: every previously queued tag is now stale
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
        // Nothing is flushed here: export commands never survive a reconnect (teardown purged the outbox typed; the core purges again defensively).
        // A fresh prepare issues fresh lines under the new connection generation.
        exportOutboxCore.setTransport(epoch: connectionSerial, loadSession: exportOutboxCore.loadSession, loadOpening: exportOutboxCore.loadOpening,
                                      transport: { [weak self] b in self?.socketWrite(b) ?? .failure(.peerClosed) })
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
            // Seal-query replies are consumed HERE, on the connection's own queue, before the generic handler chain: they never reach the broad request-id
            // fallbacks in onLine. The sink answers true only for an id inside the seal range; everything else flows on unchanged. nil sink = nothing consumed.
            if let sink = sealReplySink, sink(obj) { continue }
            onLine?(obj)
        }
    }
    private func teardown() {
        let wasConnected = isConnected
        readSource?.cancel()
        readSource = nil
        isConnected = false
        fd = -1
        exportOutboxCore.cancelAll("connection-lost")   // export commands never survive a disconnect; state first, then the typed terminal results
        if wasConnected { onDisconnected?() }
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
    /// The producer receipt bound to the HOST REQUEST epoch it was read in (tagged get_property at accept time;
    /// stale replies dropped by the opening guard). Never fed by the observed property. This proves the reply
    /// belongs to that request epoch; it does NOT prove the producer's load had settled at query time - the
    /// receipt stays a floor hint, never a load-freshness claim. Cleared on every purge.
    private var acceptedReceipt:(opening:UInt64,receipt:PhotonProducerReceipt)?
    private func issueReceiptQueryOnQueue() {
        guard nextQueryId<10_197_000_000 else{return} // fail closed on launch-monotonic exhaustion
        let id=nextQueryId;nextQueryId+=1
        pendingQueries[id]=("user-data/photon/load-generation",currentOpening(),nil)
        connection.write("{\"command\":[\"get_property\",\"user-data/photon/load-generation\"],\"request_id\":\(id)}")
    }
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
        // v12m: the producer receipt is bound to THIS accepted identity's HOST REQUEST epoch: the read goes out
        // as a tagged get_property in the same queue turn as the accepted challenge echo, and handleLine's opening
        // guard drops a reply landing after any later purge/reconnect. The binding ties the reply to the request
        // epoch only; it is not proof the producer load had settled at query time. The observed property stays a
        // diagnostic floor hint and never feeds this binding.
        issueReceiptQueryOnQueue()
        // The identity is current from this accept until the next purge / start-file / reconnect /
        // ready=false. A stale fire is harmless: listeners re-read activeLoadIdentity() and revalidate.
        DispatchQueue.main.async { [weak self] in self?.onActiveIdentity?() }
    }
    /// The ONE accepted active load identity, backed only by the receiver owner's accepted ready=true
    /// load state (session + challenge echo + opening + path equal to the polled current path, no
    /// pre-fence advance). nil between purge / start-file / reconnect / ready=false and the next
    /// accepted ready=true. Read on the work queue; safe to call from any other queue.
    var onActiveIdentity:(()->Void)?
    func activeLoadIdentity()->(session:String,opening:UInt64,path:String)? {
        OwnerQueue.sync(connection.workQueue) {
            guard layoutReady,loadStateOpening>0,!loadStateSession.isEmpty,
                  let path=store["path"] as? String,!path.isEmpty else{return nil}
            return (loadStateSession,loadStateOpening,path)
        }
    }
    /// The accepted identity and the producer's load receipt (v12m) in ONE work-queue turn. The receipt is the
    /// epoch-tagged query response bound at accept time (issueReceiptQueryOnQueue), not the observed property:
    /// the reply is tied to the accepted identity's HOST REQUEST epoch (stale replies dropped), which says
    /// nothing about whether the producer load had settled at query time. receipt nil = no v12m peer, nothing
    /// published, or the epoch-bound answer has not landed yet: explicit unknown, never a freshness claim.
    /// loadPath is display only; identity here is (session, opening, challenge epoch), never the sanitized path.
    func acceptedLoadAndReceipt()->(session:String,opening:UInt64,path:String,receipt:PhotonProducerReceipt?)? {
        OwnerQueue.sync(connection.workQueue) {
            guard layoutReady,loadStateOpening>0,!loadStateSession.isEmpty,
                  let path=store["path"] as? String,!path.isEmpty else{return nil}
            let r=acceptedReceipt?.opening==currentOpening() ? acceptedReceipt?.receipt : nil
            return (loadStateSession,loadStateOpening,path,r)
        }
    }
    /// Bumped on the owner queue at every file-loaded, purge (start-file, reconnect): the connection/load epoch an export wire message is labelled with.
    private var exportConnectionEpoch:UInt64=0
    /// Fired on the owner queue after an epoch-bound load receipt is accepted.
    var onExportReceiptOnQueue:(()->Void)?
    /// Fired on the owner queue at every purge (start-file AND reconnect): any prepared or pending export run is invalid.
    var onExportPurgeOnQueue:(()->Void)?
    /// The accepted load state plus the connection epoch, in ONE read. Inline when already on the owner queue (a script-message observer), sync otherwise.
    func exportOwnerSnapshot()->ExportOwnerSnapshot? {
        OwnerQueue.sync(connection.workQueue) {
            guard layoutReady,loadStateOpening>0,!loadStateSession.isEmpty,
                  let path=store["path"] as? String,!path.isEmpty else{return nil}
            let r=acceptedReceipt?.opening==currentOpening() ? acceptedReceipt?.receipt.runId : nil
            return ExportOwnerSnapshot(session:loadStateSession,opening:loadStateOpening,path:path,receiptRunId:r,connectionEpoch:exportConnectionEpoch)
        }
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
        exportConnectionEpoch &+= 1
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
        // v12m: DIAGNOSTIC floor hint only. The binding path for the producer receipt is the epoch-tagged
        // query issued at accept time (issueReceiptQueryOnQueue); this observed value never feeds it.
        132: "user-data/photon/load-generation",
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
        // file-scoped like the load it names: a purge must not let the previous file's receipt survive.
        "user-data/photon/load-generation",
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
        if query.key=="user-data/photon/load-generation" {
            // Only replies that passed the opening guard above reach here: bind to that request epoch.
            // A malformed value binds nothing (parse drops, never guesses) and keeps the floor unknown.
            if obj["error"] as? String=="success",let r=PhotonLoadGeneration.parse(obj["data"] as? String) {acceptedReceipt=(query.opening,r);onExportReceiptOnQueue?()}
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
        exportConnectionEpoch &+= 1
        onExportPurgeOnQueue?()
        openingLock.lock();openingGeneration &+= 1;openingLock.unlock()
        pendingQueries.removeAll();pendingLayout.removeAll();pendingLayoutTags.removeAll()
        activeLayoutReadbackTag=nil;committedLayoutTag=nil
        acceptedReceipt=nil // a receipt bound to the revoked epoch must not survive the purge
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

// BEGIN typed composition factories (r117/r118): concrete channel wiring lives in the
// backend owner; UI code reads typed capabilities only.
#if canImport(AppKit)
extension PPController {
    // Typed backend composition only; wire format and decoding remain backend-owned.
    var playbackOperations: PlayerPlaybackOperations {
        PlayerPlaybackOperations(command: self, persistent: persistentConnection, packet: ipcClient)
    }
    var menuQueryOperations: PlayerMenuQueryOperations {
        PlayerMenuQueryOperations(channel: ipcClient)
    }
    /// Typed decoded-colour probe operation: the Engine station owns query content, parsing and the fence; the transport is the controller's existing typed query seam. The App never sees the client.
    var exportColourProbe: PlayerColourProbeOperations {
        PlayerColourProbeOperations(query: menuQueryOperations.query, ownerSnapshot: { [self] in exportOwnerSnapshot() })
    }
    func makeVR180Controller() -> VR180Controller {
        VR180Controller(lookOperations: VR180LookOperations(channel: self),
                        storeCommands: VR180StoreCommandOperations(channel: self, recorder: ThreeDStore.shared))
    }
    /// Backend-owned construction of the persistent event pipeline: the concrete connection
    /// and its poll engine are paired at the composition owner, and the controller receives
    /// the typed channel plus the poll capability as an init-time pair. Same thread and
    /// lifetime as the controller's own init (the caller), so attach order is unchanged.
    static func makePersistentEventPipeline(path ipcPath: String) -> (channel: any PlayerPersistentEventChannel, poll: PollEngine) {
        let connection = PersistentEventConnection(path: ipcPath)
        return (connection, PollEngine(connection: connection, receiverSession: { PPController.cropPacketSession }))
    }
}
#endif
// END typed composition factories
// ================================================================
// Opened-file CANDIDATE observation of the gor-spawned mpv process: the kernel's
// vnode data behind mpv's OWN descriptors, never a stat(path) on our side. This
// is NOT the active decoder's identity: it only says that at probe time some
// descriptor of this process holds an open vnode whose path matches. A caller
// must bind the observation itself: the pid must come from the owning
// controller's typed backend/session (not a global process handle), and the
// owner session, opening generation, path and process identity must read the
// same before and after the probe; any change = unknown. Nothing in the App
// wires this observation to a decision today; playingSourceIdentity stays nil
// and the Start fence stays closed. Closing the active-decoder binding is OPEN:
// claim+kernel cross-checks and native scenario runs do not establish it; it
// needs the load owner's fd/file-identity witness bound to the load token at
// open, or an mpv-side report of the opened source's identity.
// ================================================================

/// One candidate vnode identity behind mpv's descriptors, or .unknown for every
/// failure and every ambiguity the probe can detect (fail-closed: a truncated
/// descriptor list, an fd closed mid-probe, a missing vnode answer, an
/// unterminated path buffer, an invalid inode/size, and any set of matching
/// descriptors that do not agree on a single identity all yield .unknown, never
/// a guess). Undetectable by design: a listed fd that is closed and reopened to
/// another vnode under the same fd number before its query, where that query
/// then succeeds, is invisible to this single pass; only a witness held by the
/// load owner at open (or an mpv-side report of the opened source's identity)
/// can bind the active decoder, and this observation never claims to.
enum MPVOpenFileCandidate: Equatable {
    case candidate(device: UInt64, inode: UInt64, bytes: Int64, mtimeNs: Int64, resolvedPath: String)
    case unknown
}

enum MPVOpenFileCandidateProbe {
    /// Collect EVERY vnode descriptor of `pid` whose path matches `mediaPath` (the path is
    /// only the matcher, symlinks resolved; the identity fields come from the vnode via
    /// proc_pidfdinfo/PROC_PIDFDVNODEPATHINFO, so a file replaced after the open still
    /// yields the opened vnode's dev/inode/bytes/mtime). One agreeing identity across all
    /// matches = .candidate; zero matches, a dead pid, a truncated descriptor list, or
    /// disagreeing matches = .unknown. Non-file media (streams) match nothing = .unknown.
    static func candidate(pid: Int32, mediaPath: String) -> MPVOpenFileCandidate {
        #if canImport(Darwin)
        guard pid > 0, !mediaPath.isEmpty else { return .unknown }
        let wanted = URL(fileURLWithPath: mediaPath).resolvingSymlinksInPath().path
        guard !wanted.isEmpty else { return .unknown }
        let fdSize = MemoryLayout<proc_fdinfo>.size
        // The descriptor list can grow between sizing and reading: a full buffer means a
        // possibly truncated list; grow once, then fail closed.
        var fds = [proc_fdinfo]()
        var truncated = true
        for _ in 0..<2 {
            let count = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard count > 0 else { return .unknown }
            fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(count) / fdSize + 8)
            let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * fdSize))
            guard got > 0 else { return .unknown }
            if Int(got) < fds.count * fdSize { fds = Array(fds.prefix(Int(got) / fdSize)); truncated = false; break }
        }
        guard !truncated else { return .unknown }
        let vnodeSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        var found: MPVOpenFileCandidate?
        for fd in fds where fd.proc_fdtype == PROX_FDTYPE_VNODE {
            var info = vnode_fdinfowithpath()
            // A missing answer for a listed vnode fd (closed mid-probe) fails closed; a
            // same-number reuse that still answers is undetectable here (see enum doc).
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, vnodeSize) == vnodeSize else { return .unknown }
            let vnodePath = withUnsafeBytes(of: &info.pvip.vip_path) { raw -> String in
                guard let base = raw.baseAddress, raw.firstIndex(of: 0) != nil else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            guard !vnodePath.isEmpty else { return .unknown }
            guard vnodePath == wanted else { continue }
            let st = info.pvip.vip_vi.vi_stat
            let (secNs, o1) = st.vst_mtime.multipliedReportingOverflow(by: 1_000_000_000)
            let (mtimeNs, o2) = secNs.addingReportingOverflow(st.vst_mtimensec)
            guard st.vst_ino != 0, st.vst_size >= 0, !o1, !o2, mtimeNs > 0 else { return .unknown }
            let this = MPVOpenFileCandidate.candidate(device: UInt64(st.vst_dev), inode: st.vst_ino,
                                                      bytes: st.vst_size, mtimeNs: mtimeNs, resolvedPath: vnodePath)
            // No first-match return: disagreeing matches (a replaced or twice-opened file) are ambiguous.
            if let prev = found, prev != this { return .unknown }
            found = this
        }
        return found ?? .unknown
        #else
        return .unknown
        #endif
    }
}

// ================================================================
// Opened-file snapshot + candidate agreement helpers. DIAGNOSTICS ONLY: no call
// sites, playingSourceIdentity stays nil, the Start fence stays closed. These
// helpers produce and compare two independent OBSERVATIONS: the owner's own
// open+fstat snapshot of a path, and MPVOpenFileCandidateProbe's path-filtered
// kernel candidate of a process's descriptors. Agreement is NOT proof that the
// active decoder reads that file: a decoder holding a vnode whose path no
// longer matches (rename/unlink after open) is invisible to the path filter,
// while a prefetch or second open of the matching path makes the agreement true
// without the active decoder being that file. No load-token, binding, or
// decoder-confirmation semantics live here; the correct product answer for the
// playing source's identity remains nil/unknown.
// ================================================================

/// The owner's own open+fstat snapshot of a path at one instant. An observation,
/// never evidence about which open instance a decoder consumes.
struct MPVOpenFileSnapshot: Equatable {
    let device: UInt64, inode: UInt64, bytes: Int64, mtimeNs: Int64, resolvedPath: String
}

enum MPVOpenFileSnapshotProbe {
    /// open(O_RDONLY|O_CLOEXEC) + fstat + symlink resolution of `mediaPath`; nil on
    /// any failure (missing file, no access, overflow, invalid inode/size/mtime).
    /// O_CLOEXEC: the descriptor must never leak into a spawned child. The fd is
    /// closed before return: a snapshot, not a held descriptor.
    static func capture(mediaPath: String) -> MPVOpenFileSnapshot? {
        #if canImport(Darwin)
        guard !mediaPath.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: mediaPath).resolvingSymlinksInPath().path
        guard !resolved.isEmpty else { return nil }
        let fd = open(resolved, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        let (secNs, o1) = Int64(st.st_mtimespec.tv_sec).multipliedReportingOverflow(by: 1_000_000_000)
        let (mtimeNs, o2) = secNs.addingReportingOverflow(Int64(st.st_mtimespec.tv_nsec))
        guard !o1, !o2, mtimeNs > 0, st.st_ino != 0, st.st_size >= 0 else { return nil }
        return MPVOpenFileSnapshot(device: UInt64(st.st_dev), inode: UInt64(st.st_ino),
                                   bytes: Int64(st.st_size), mtimeNs: mtimeNs, resolvedPath: resolved)
        #else
        return nil
        #endif
    }

    /// True when the path-filtered candidate of `pid` agrees with `snapshot` on
    /// device+inode, corroborated by bytes+mtimeNs. A diagnostic comparison of two
    /// observations; agreement is not decoder-source proof (see the banner above).
    static func candidateAgrees(with snapshot: MPVOpenFileSnapshot, pid: Int32) -> Bool {
        guard case .candidate(let device, let inode, let bytes, let mtimeNs, _) =
                MPVOpenFileCandidateProbe.candidate(pid: pid, mediaPath: snapshot.resolvedPath)
        else { return false }
        return device == snapshot.device && inode == snapshot.inode
            && bytes == snapshot.bytes && mtimeNs == snapshot.mtimeNs
    }
}

// MARK: - Crop probe capability (backend-owned)

/// Opaque prepared screenshot command, built and consumed by the backend
/// owner only. CropProbeTransport holds and hands back the token; it cannot
/// read or shape the payload (the json stays fileprivate to this file).
struct CropProbePreparedCommand {
    fileprivate let json: String
}

/// The only mpv surface crop detection gets: typed entries for duration,
/// seeking, pause, path, time, format, seek and screenshot. No socket path,
/// no IPCClient and no raw JSON cross this boundary.
struct CropProbeCapability {
    let fileDuration: (_ timeout: TimeInterval) -> Double?
    let isSeeking: (_ timeout: TimeInterval) -> Bool?
    let isPaused: () -> Bool?
    let currentPath: () -> String?
    let timePosition: () -> Double?
    let screenshotFormat: () -> String
    let seekAbsolute: (_ seconds: Int) -> Void
    let prepareScreenshot: (_ path: String) -> CropProbePreparedCommand?
    let sendPrepared: (_ command: CropProbePreparedCommand) -> Void
    /// True means the command was built and handed to the socket; it is not
    /// write-success proof - the screenshot file is the evidence of capture.
    let screenshotVideo: (_ path: String) -> Bool
}

// IPCClient is AppKit-hosted (see its own platform guard above), so the
// construction that funnels it sits under the same canImport(AppKit) guard:
// Linux typechecks of this file drop the client-touching factory, while the
// typed surface above stays visible to CropProbeTransport on every platform.
#if canImport(AppKit)
extension MPVCommand {
    /// The backend owner's crop-probe factory: the socket path, the IPCClient
    /// and every command shape (the property funnel, the seek, the
    /// screenshot-to-file) live HERE. Semantics-preserving against the
    /// pre-refactor inline calls: decoded commands, timeouts, call order and
    /// refusal results (nil exactly where an empty parseFirst object yielded
    /// nil) are unchanged; the wire differs only by JSONSerialization's slash
    /// escaping on the screenshot sends. The seek target stays a JSON string,
    /// as the old inline command had it.
    static func cropProbe(socketPath: String) -> CropProbeTransport {
        let client = IPCClient(path: socketPath)
        func property(_ name: String, _ timeout: TimeInterval) -> Any? {
            let lines = client.queryBatch(MPVCommand.make(["get_property", name]), timeout: timeout)
            return IPCClient.parseFirst(lines)["data"]
        }
        func prepare(_ path: String) -> CropProbePreparedCommand? {
            let command = MPVCommand.make(["screenshot-to-file", path, "video"])
            return command.isEmpty ? nil : CropProbePreparedCommand(json: command)
        }
        func send(_ command: CropProbePreparedCommand) {
            _ = client.queryBatch(command.json)
        }
        return CropProbeTransport(capability: CropProbeCapability(
            fileDuration: { property("duration", $0) as? Double },
            isSeeking: { property("seeking", $0) as? Bool },
            isPaused: { property("pause", 0.8) as? Bool },
            currentPath: { property("path", 0.8) as? String },
            timePosition: { (property("time-pos", 0.8) as? NSNumber)?.doubleValue },
            screenshotFormat: { (property("screenshot-format", 0.8) as? String) ?? "png" },
            seekAbsolute: { _ = client.queryBatch(MPVCommand.make(["seek", String($0), "absolute"])) },
            prepareScreenshot: prepare,
            sendPrepared: send,
            screenshotVideo: { path in
                guard let command = prepare(path) else { return false }
                send(command)
                return true
            }))
    }
}
#endif

#if canImport(AppKit)
extension PPController {
    /// Typed crop-detector composition. The MPV backend owner builds the probe
    /// transport here (MPVCommand.cropProbe), so PPController only receives a
    /// finished CropDetector and never names the backend capability.
    /// PARSE-ONLY DRAFT: not compiled in this tree (Mac-only extension).
    static func makeCropDetector(mpvPath: String) -> CropDetector {
        CropDetector(mpvPath: mpvPath, probeFactory: MPVCommand.cropProbe)
    }
}
#endif
