// ThreeD/Control.swift - 3D station "Control": 3D state, route, menus, experiment options, wiring and self-test.
// Move-only split of the former ThreeD.swift (arch-199s). The sections below are byte-identical to their former BEGIN/END spans,
// in their original relative order. The import list is the union of the former file (a deliberate superset; narrow it only with a Darwin compile).
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Accelerate)
import Accelerate
#endif
import AppKit
#if canImport(Compression)
import Compression
#endif
import CoreGraphics
#if canImport(CoreML)
import CoreML
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Darwin
import Foundation
#if canImport(Glibc)
import Glibc
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Metal)
import Metal
#endif
import QuartzCore
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(VideoToolbox)
import VideoToolbox
#endif
#if canImport(Vision)
import Vision
#endif

// BEGIN relocated ThreeDState.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

struct FilmID: RawRepresentable, Codable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

/// 191d D1: identity inputs are platform facts, resolution is pure and Linux-testable.
struct ThreeDFilmIdentity: Codable, Equatable {
    var volume: String?, fileID: String?, infohash: String?, fileIndex: Int?
    var basename: String, finalSize: Int64?, normalizedURL: String?
    var aliases: [String]?
    var primary: String? {
        if let volume,let fileID {return "file|\(volume)|\(fileID)"}
        if let infohash,let fileIndex {return "torrent|\(infohash.lowercased())|\(fileIndex)"}
        guard let url=normalizedURL,let size=finalSize,size>0 else {return nil}
        return "stream|\(url)|\(size)"
    }
    static func resolve(_ input:Self,records:[String:Self],freshID:String)->FilmID {
        if let key=input.primary,let hit=records.first(where:{$0.value.primary==key || ($0.value.aliases ?? []).contains(key)}) {return FilmID(rawValue:hit.key)}
        if let hash=input.infohash,let index=input.fileIndex,let hit=records.first(where:{$0.value.infohash?.lowercased()==hash.lowercased() && $0.value.fileIndex==index}) {return FilmID(rawValue:hit.key)}
        // A basename alone is never enough. Ambiguity is checked across ALL same-name entries.
        let sameName=records.filter {$0.value.basename==input.basename}
        if sameName.count==1,let size=input.finalSize,size>0,let hit=sameName.first,hit.value.finalSize==size {return FilmID(rawValue:hit.key)}
        return FilmID(rawValue:input.primary ?? freshID)
    }
}

struct ThreeDSource: Codable, Equatable {
    enum Format: String, Codable, CaseIterable {
        case auto, flat2D, sbsFull, sbsHalf, tbFull, tbHalf, vr180SBS, vr180TB, vr360Mono, vr360TB
    }
    var format: Format
    var swap = false
    init(_ format: Format, swap: Bool = false) { self.format = format; self.swap = swap }
    var nativeVR: Bool { [.vr180SBS, .vr180TB, .vr360Mono, .vr360TB].contains(format) }
    var projection: String {
        switch format {
        case .auto, .flat2D: return "flat-2d3d"
        case .sbsFull, .sbsHalf: return "flat-sbs"
        case .tbFull, .tbHalf: return "flat-tb"
        case .vr180SBS: return "vr180"
        case .vr180TB: return "vr180-tb"
        case .vr360Mono: return "vr360-mono"
        case .vr360TB: return "vr360-tb"
        }
    }
}

enum ThreeDOutput: String, Codable, CaseIterable {
    case off, sbs = "full_sbs", halfSBS = "half_sbs", tb = "over_under", vr180, anaglyph
}

// One presentation decision. Off overrides every engine without changing source.
enum ThreeDEngine: Equatable {
    case nativeVR180, flat(ThreeDOutput), twoDVR180
    var rawValue: String {
        switch self {
        case .nativeVR180: return "nativeVR180"
        case .flat(let output): return "flat_\(output.rawValue)"
        case .twoDVR180: return "twoDVR180"
        }
    }
    static func resolve(source:ThreeDSource,output:ThreeDOutput)->Self {
        if output == .off {return .flat(.off)}
        if output == .vr180 {return [.vr180SBS,.vr180TB].contains(source.format) ? .nativeVR180:.twoDVR180}
        return .flat(output)
    }
}

struct FilmThreeD: Codable, Equatable {
    var source = ThreeDSource(.flat2D)
    var output = ThreeDOutput.off
    var lastOutput = ThreeDOutput.sbs
    var userTouched = false
    var explicitOutput: ThreeDOutput? // nil for older records and automatic opens
    var userSource: Bool? // nil in older records: re-resolve evidence, not a user choice
}

enum ThreeDEffectKey: String, Codable, CaseIterable {
    case head, headInvert, blink, crossEye, ipd, strength, screenDepth, screenSize, surround, surroundInvert, quality, osdLine
}

enum ThreeDEffectValue: Codable, Equatable {
    case bool(Bool), number(Double), text(String)
}

struct ThreeDGlobalEffects: Codable, Equatable {
    var values: [ThreeDEffectKey: ThreeDEffectValue] = [
        .head: .bool(false), .blink: .bool(false), .crossEye: .bool(true), .ipd: .number(0),
        .strength: .number(1), .screenDepth: .number(1.5), .screenSize: .number(75),
        .surround: .text("soft"), .surroundInvert: .bool(false), .quality: .text("auto"), .osdLine: .bool(true)
    ]
    subscript(_ key: ThreeDEffectKey) -> ThreeDEffectValue? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

struct ThreeDEvidence: Equatable {
    var metadata: ThreeDSource?
    var filenameTag: ThreeDSource?
    var suggestion: String?
    init(metadata: ThreeDSource? = nil, filenameTag: ThreeDSource? = nil, suggestion: String? = nil) {
        self.metadata = metadata; self.filenameTag = filenameTag; self.suggestion = suggestion
    }
}

/// A metadata refresh is not a new opening. Structural start-file resets this receipt.
struct ThreeDOpenReceipt {
    private var evidence:ThreeDEvidence?
    mutating func reset() { evidence=nil }
    mutating func accept(_ input:ThreeDEvidence)->Bool {
        guard evidence != input else {return false}
        evidence=input;return true
    }
}

/// Per-opening projection evidence. A generic stereo layout is weaker than a
/// confirmed spherical verdict, and a later generic layout must not erase the
/// opening's confirmed native projection while the probe has no verdict.
enum ThreeDProjectionMemory {
    static func resolve(current: String?, evidence: String?, probe: String?) -> String? {
        if let probe, isProbeVerdict(probe) { return probe }
        if let evidence, isProbeVerdict(evidence) { return evidence }
        if let current, isProbeVerdict(current), let candidate = evidence ?? probe, isGenericFlat(candidate) { return current }
        return evidence ?? probe ?? current
    }
    private static func isGenericFlat(_ projection: String) -> Bool {
        projection == "flat-sbs" || projection == "flat-tb"
    }
    private static func isSpherical(_ projection: String) -> Bool {
        ["vr180", "vr180-tb", "vr360-mono", "vr360-tb"].contains(projection)
    }
    private static func isProbeVerdict(_ projection: String) -> Bool {
        isSpherical(projection) || projection == "unsupported"
    }
}

struct ThreeDPresentationPlan: Equatable {
    let filmSource: ThreeDSource
    let engine: ThreeDEngine
    let luaKind: String
    let luaAspect: Double
    let output: ThreeDOutput
    let pack: Int
    let vrEnabled: Bool

    static func make(state: ThreeDState) -> ThreeDPresentationPlan {
        let current = state.current
        let detected = state.detectedSource
        let resolvedSource = current.source.format == .auto ? detected : current.source
        let filmSource = resolvedSource // SOURCE is retained; selected OUTPUT owns the presentation engine.
        let engine = ThreeDEngine.resolve(source:filmSource,output:current.output)
        let output = current.output
        let renderedApplies = state.renderedOutput == output && engine != .twoDVR180 && engine != .nativeVR180
        var luaSource = renderedApplies ? (state.renderedSource ?? filmSource) : filmSource
        if engine != .nativeVR180 {
            if luaSource.format == .vr180SBS {luaSource=ThreeDSource(.sbsFull,swap:luaSource.swap)}
            if luaSource.format == .vr180TB {luaSource=ThreeDSource(.tbFull,swap:luaSource.swap)}
        }
        let pack = (engine == .nativeVR180 || output == .off) ? 0 : 3
        return ThreeDPresentationPlan(
            filmSource: filmSource,
            engine: engine,
            luaKind: luaSource.projection,
            luaAspect: renderedApplies ? (state.renderedAspect ?? 0):0,
            output: output,
            pack: pack,
            vrEnabled: output != .off
        )
    }

    static func restoredOutput(for state: ThreeDState) -> ThreeDOutput {
        if state.current.explicitOutput == .sbs {return .sbs}
        let detected = state.detectedSource
        let filmSource = state.current.source.format == .auto ? detected : state.current.source
        let nativeVR180 = filmSource.format == .vr180SBS || filmSource.format == .vr180TB
        let stored = state.current.lastOutput
        if stored == .vr180 && !nativeVR180 { return .sbs }
        return stored
    }
}

struct ThreeDState: Codable, Equatable {
    var identities: [String:ThreeDFilmIdentity]?
    var currentFilm: FilmID?
    var films: [String: FilmThreeD] = [:]
    var order: [String] = []
    var effects = ThreeDGlobalEffects()
    var blinkExplicitChoice: Bool?
    var crossEyeExplicitChoice: Bool? // nil: inherited default; explicit toggles survive future default repairs
    mutating func restoreViewingDefault() {
        effects[.crossEye] = .bool(crossEyeExplicitChoice ?? true)
    }
    var migrationComplete = false
    var suggestion: String?
    var detectedSource = ThreeDSource(.flat2D)
    var sourceChoiceThisSession: FilmID? // Live Film-is choice, never restored from disk.
    var renderedSource: ThreeDSource?
    var renderedOutput: ThreeDOutput?
    var renderedAspect: Double?
    var presentationSource: ThreeDSource { renderedSource ?? (current.source.format == .auto ? detectedSource:current.source) }
    var current: FilmThreeD { currentFilm.flatMap { films[$0.rawValue] } ?? FilmThreeD() }
}

enum ThreeDAction {
    case open(FilmID, ThreeDEvidence)
    case setSource(ThreeDSource), setOutput(ThreeDOutput), toggle3D, cycleSource
    case setEffect(ThreeDEffectKey, ThreeDEffectValue), resetView
    case generated(FilmID, ThreeDSource, ThreeDOutput, aspect:Double = 0), original
}

enum ThreeDEffect: Equatable {
    case present, resetView, showInfo, persist, reapply
}

enum ThreeDReducer {
    static func opening(saved: FilmThreeD?, evidence: ThreeDEvidence, liveSourceChoice: Bool = false) -> FilmThreeD {
        var film = saved ?? FilmThreeD()
        let evidenceSource = evidence.metadata ?? evidence.filenameTag ?? ThreeDSource(.flat2D)
        // A past Film-is choice cannot reclassify a newly detected file. Keep a
        // live manual choice through metadata refresh, not across a new opening.
        let savedNative=[ThreeDSource.Format.vr180SBS,.vr180TB].contains(film.source.format)
        let nativeEvidence=[evidence.metadata,evidence.filenameTag].compactMap {$0}.contains { [.vr180SBS,.vr180TB].contains($0.format) }
        if film.userSource != true || (!liveSourceChoice && ((savedNative && !nativeEvidence) || evidence.metadata != nil || evidence.filenameTag != nil)) {
            film.source = evidenceSource;film.userSource = false
        }
        let resolvedSource = film.source.format == .auto ? evidenceSource : film.source
        let nativeVR180 = resolvedSource.format == .vr180SBS || resolvedSource.format == .vr180TB
        // 196u: a detected native flat-stereo source opens in its own presentation, the
        // same way native VR180 does. Detection is authority only until the owner touches
        // the film: an explicit Off keeps winning on every later open.
        let nativeFlatStereo: ThreeDOutput?
        switch resolvedSource.format {
        case .sbsFull: nativeFlatStereo = .sbs
        case .sbsHalf: nativeFlatStereo = .halfSBS
        case .tbFull, .tbHalf: nativeFlatStereo = .tb
        default: nativeFlatStereo = nil
        }
        if !film.userTouched {
            film.output = nativeVR180 ? .vr180 : (nativeFlatStereo ?? .off)
            film.lastOutput = nativeVR180 ? .vr180 : (nativeFlatStereo ?? .sbs)
        }
        // Old inferred VR180 records are corrected without deleting film history.
        if !nativeVR180 && film.output == .vr180 && film.explicitOutput != .vr180 {film.output = nativeFlatStereo ?? .sbs}
        if !nativeVR180 && film.lastOutput == .vr180 {film.lastOutput = nativeFlatStereo ?? .sbs}
        return film
    }

    static func reduce(_ state: ThreeDState, _ action: ThreeDAction) -> (ThreeDState, [ThreeDEffect]) {
        var next = state
        var effects: [ThreeDEffect] = [.present, .persist]
        switch action {
        case let .open(id, evidence):
            if next.currentFilm != id {next.renderedSource=nil;next.renderedOutput=nil;next.renderedAspect=nil;next.sourceChoiceThisSession=nil}
            let sessionOutput = next.currentFilm == id && next.current.userTouched && next.current.explicitOutput == next.current.output ? next.current.output : nil
            next.currentFilm = id
            next.films[id.rawValue] = opening(saved: next.films[id.rawValue], evidence: evidence,liveSourceChoice:next.sourceChoiceThisSession == id)
            // Metadata refresh is not a relaunch. Keep the current explicit View,
            // but still rebuild inferred SOURCE above and sanitize durable restore.
            if let sessionOutput {next.films[id.rawValue]?.output = sessionOutput}
            next.order.removeAll { $0 == id.rawValue }; next.order.append(id.rawValue)
            next.suggestion = evidence.suggestion
            next.detectedSource = evidence.metadata ?? evidence.filenameTag ?? ThreeDSource(.flat2D)
        case let .generated(parent, source, planOutput,aspect):
            guard parent == next.currentFilm else {
                print("DIAG 3D-GUARD generated ignored reason=parent_mismatch parent=\(parent.rawValue) current=\(next.currentFilm?.rawValue ?? "none")")
                return (state,[])
            }
            guard planOutput == next.current.output else {
                print("DIAG 3D-GUARD generated ignored reason=output_mismatch parent=\(parent.rawValue) current=\(next.currentFilm?.rawValue ?? "none") output=\(planOutput.rawValue) currentOutput=\(next.current.output.rawValue)")
                return (state,[])
            }
            next.renderedSource=source;next.renderedOutput=planOutput;next.renderedAspect=aspect
        case .original: next.renderedSource=nil;next.renderedOutput=nil;next.renderedAspect=nil
        case let .setEffect(key, value):
            if key == .crossEye, case let .bool(v) = value {next.crossEyeExplicitChoice=v}
            if key == .blink, case let .bool(v) = value {next.blinkExplicitChoice=v}
            next.effects[key] = value; effects.append(.showInfo) // Live parameters never request a media/route rebuild.
        case .resetView: return (next, [.resetView, .showInfo])
        default:
            guard let id = next.currentFilm else { return (state, []) }
            var film = next.current
            switch action {
            case let .setSource(source):
                next.sourceChoiceThisSession=id
                next.renderedSource=nil;next.renderedOutput=nil;next.renderedAspect=nil
                film.source = source;film.userSource = true
                film.explicitOutput = nil // A new explicit source choice supersedes the output pin.
                if [.vr180SBS,.vr180TB].contains(source.format) {film.output = .vr180;film.lastOutput = .vr180}
                if [.sbsFull,.sbsHalf].contains(source.format) {film.output = source.format == .sbsHalf ? .halfSBS:.sbs;film.lastOutput=film.output}
                if [.tbFull,.tbHalf].contains(source.format) {film.output = .tb;film.lastOutput = .tb}
                if source.format == .flat2D {film.lastOutput = .sbs;if film.output == .vr180 {film.output = .sbs}}
            case let .setOutput(output):
                // Re-selecting the output already presented (shift+s while in SBS) is a no-op. Without this the
                // action still carried .reapply, which made PPController.applyThreeDState reset and re-measure the crop.
                if output != .off, film.output == output, film.explicitOutput == output { return (state, []) }
                if output != .off {film.explicitOutput = output}
                film.output = output
                // Every output-changing action replaces the currently presented generated shot.
                next.renderedSource=nil;next.renderedOutput=nil;next.renderedAspect=nil
                let detected = next.detectedSource
                let filmSource = film.source.format == .auto ? detected : film.source
                let nativeVR180 = filmSource.format == .vr180SBS || filmSource.format == .vr180TB
                if output != .off && (output != .vr180 || nativeVR180) { film.lastOutput = output }
            case .toggle3D:
                film.output = film.output == .off ? ThreeDPresentationPlan.restoredOutput(for:next) : .off
                next.renderedSource=nil;next.renderedOutput=nil;next.renderedAspect=nil
            case .cycleSource:
                next.sourceChoiceThisSession=id
                film.userSource = true
                let nativeEvidence=[next.detectedSource.format].contains { [.vr180SBS,.vr180TB].contains($0) }
                let all = ThreeDSource.Format.allCases.filter {nativeEvidence || ![.vr180SBS,.vr180TB].contains($0)}
                let i = all.firstIndex(of: film.source.format) ?? 0
                film.source = ThreeDSource(all[(i + 1) % all.count], swap: film.source.swap)
            default: break
            }
            film.userTouched = true
            next.films[id.rawValue] = film
            effects.append(.showInfo);effects.append(.reapply)
        }
        while next.order.count > 2000 {
            let evicted=next.order.removeFirst();next.films.removeValue(forKey:evicted);next.identities?.removeValue(forKey:evicted)
        }
        // VR entry starts blink by the owner's default; independent explicit OFF wins.
        if next.current.output != .off && next.blinkExplicitChoice == nil {next.effects[.blink] = .bool(true)}
        return (next, effects)
    }
}

/// One state writer. Consumers receive values and desired effects, never mutable storage.
@MainActor final class ThreeDStore {
    static let shared = ThreeDStore()
    static let defaultsKey = "gor.3d.films.v2"
    private(set) var revision: UInt64 = 0
    var appliedOutput:ThreeDOutput?
    private(set) var snapshot: ThreeDState
    private let defaults: UserDefaults
    private let transient: Bool
    private var sourceIDs: [String:FilmID] = [:]
    func bindSource(path:String,id:FilmID) {sourceIDs[path]=id}
    func unbindSource(path:String) {sourceIDs.removeValue(forKey:path)}
    func resolveIdentity(path:String,input:ThreeDFilmIdentity)->FilmID {
        let id=ThreeDFilmIdentity.resolve(input,records:snapshot.identities ?? [:],freshID:"new|"+UUID().uuidString)
        if snapshot.identities == nil {snapshot.identities=[:]}
        var record=input;let prior=snapshot.identities?[id.rawValue]
        record.aliases=Array(Set((prior?.aliases ?? [])+[prior?.primary,input.primary].compactMap {$0}))
        snapshot.identities?[id.rawValue]=record;sourceIDs[path]=id;save();return id
    }
    func id(for path:String)->FilmID? {sourceIDs[path]}
    private(set) var appliedCommands: [String] = []
    func recordAppliedCommand(_ command:String) {appliedCommands.append(command);if appliedCommands.count>4000 {appliedCommands.removeFirst(appliedCommands.count-4000)}}
    private var subscribers: [String: (ThreeDState, [ThreeDEffect]) -> Void] = [:]
    private var isDispatching = false
    private var pendingActions: [ThreeDAction] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transient = ProcessInfo.processInfo.environment["GOR_STORE_ACCEPTANCE_DIR"] != nil || ProcessInfo.processInfo.environment["GOR_OWNER_ACTION_DIR"] != nil
        snapshot = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(ThreeDState.self, from: $0) } ?? ThreeDState()
        snapshot.restoreViewingDefault()
        if transient { snapshot=ThreeDState();snapshot.migrationComplete=true }
        snapshot.sourceChoiceThisSession=nil
        snapshot.currentFilm=nil // A new process has not opened a film yet; durable records remain.
    }
    /// Called once by the platform adapter. The reducer/store never guesses which legacy values were explicit.
    func migrateExplicit(_ entries: [FilmID: FilmThreeD]) {
        guard !snapshot.migrationComplete else { return }
        for (id, film) in entries where film.userTouched {
            if snapshot.films[id.rawValue] == nil { snapshot.films[id.rawValue] = film; snapshot.order.append(id.rawValue) }
        }
        while snapshot.order.count > 2000 { snapshot.films.removeValue(forKey: snapshot.order.removeFirst()) }
        snapshot.migrationComplete = true
        save()
    }
    private func save() {
        if transient { return } // Test fixtures never read/write the owner's durable film records.
        var durable=snapshot;durable.renderedSource=nil;durable.renderedOutput=nil;durable.renderedAspect=nil;durable.sourceChoiceThisSession=nil
        if let data = try? JSONEncoder().encode(durable) { defaults.set(data, forKey: Self.defaultsKey) }
    }
    func subscribe(ownerID: String, handler: @escaping (ThreeDState, [ThreeDEffect]) -> Void) {
        subscribers[ownerID] = handler
        handler(snapshot, [.present])
    }
    func unsubscribe(ownerID: String) { subscribers.removeValue(forKey: ownerID) }
    func dispatch(_ action: ThreeDAction) {
        if isDispatching { pendingActions.append(action); return }
        isDispatching = true
        defer { isDispatching = false }
        var queued = [action]
        var index = 0
        while index < queued.count {
            let currentAction = queued[index];index += 1
            let (next, effects) = ThreeDReducer.reduce(snapshot, currentAction)
            let opening:Bool;if case .open = currentAction {opening=true} else {opening=false}
            guard next != snapshot || effects.contains(.resetView) || effects.contains(.showInfo) || effects.contains(.reapply) || opening else { continue }
            revision &+= 1
            snapshot = next
            if effects.contains(.persist) { save() }
            for handler in Array(subscribers.values) { handler(next, effects) }
            if !pendingActions.isEmpty {queued.append(contentsOf:pendingActions);pendingActions.removeAll()}
        }
    }
    func output(for film: FilmID) -> ThreeDOutput { snapshot.films[film.rawValue]?.output ?? .off }
}

/// Engine route mutations are authored only by applyThreeDState.
enum ThreeDRouteEnvelope {
    static let messages:Set<String> = ["vr180-look-set-projection","vr180-look-set-output","vr180-look-set-pack","vr180-look-surround-invert","vr180-look-set-enabled","vr180-look-plan-lock"]
}
// END relocated ThreeDState.swift
// BEGIN relocated ThreeDRoute.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// P24 (arch-195b), ISOLATED per arch-195c N3: a route state machine and
/// revision store for the GORAV engine side. This component is NOT wired
/// into the mpv path: the shipped vr180-look.lua (byte-identical to shipped
/// 975da1d4) owns mpv-path route admission, the 3D-REJECTED record and the
/// 3D-VERIFIED verdict, exactly as shipped. Nothing in the mpv player host
/// calls ThreeDRouteCenter; the machine below is available to the gorav
/// route where no Lua gate exists. Do not re-attach it to the mpv wire
/// without an owner/architect ruling.
///
/// Semantics mirror the pre-move Lua machine 1:1:
/// - openBatch: foreign sender ignored; a lower revision ignored; a new
///   revision clears the completed stamp; the same revision refreshes kind
///   and context without clearing completion.
/// - decision: reason precedence is sequential overwrite, exactly as the Lua
///   computed it: "revision" first, then "store_kind" for a projection whose
///   kind differs from the batch kind, then "flat_engine" when the batch is
///   a flat engine kind.
/// - 3D-REJECTED is recorded once per (sender, message, values) key.
/// - The verdict is computed when the applied-state receipt's
///   completed_revision reaches the current batch revision, once per batch.

struct ThreeDRouteContext: Equatable {
    var enabled: Bool
    var layout: Int
    var pack: Int
    var output: String
    var engine: String
    var generation: String
    var file: String
    var appPID: String
}

enum ThreeDRouteVerdict: String {
    case pass = "PASS"
    case fail = "FAIL"
    case unverified = "UNVERIFIED"
}

enum ThreeDRouteOpen: Equatable {
    case opened
    case refreshed
    case ignoredForeign
    case ignoredStale
}

struct ThreeDRouteDecision: Equatable {
    var admit: Bool
    var reason: String?
}

/// Parsed user-data/vr180-look/applied-state receipt. The Lua publish shape
/// is unchanged by the move; revision/completed_revision stay verbatim
/// echoes of the mirror stamps. mpv delivers the property either as a JSON
/// string or as a native object.
struct ThreeDAppliedRouteState: Equatable {
    var sourceLayout: Int
    var flatPack: Int
    var enabled: Bool
    var revision: UInt64?
    var completedRevision: UInt64?

    init(sourceLayout: Int, flatPack: Int, enabled: Bool, revision: UInt64?, completedRevision: UInt64?) {
        self.sourceLayout = sourceLayout
        self.flatPack = flatPack
        self.enabled = enabled
        self.revision = revision
        self.completedRevision = completedRevision
    }

    init?(_ data: Any?) {
        let object: [String: Any]
        if let dict = data as? [String: Any] {
            object = dict
        } else if let string = data as? String,
                  let parsed = (try? JSONSerialization.jsonObject(with: Data(string.utf8))) as? [String: Any] {
            object = parsed
        } else {
            return nil
        }
        guard let layout = (object["source_layout"] as? NSNumber)?.intValue,
              let pack = (object["flat_pack"] as? NSNumber)?.intValue,
              let enabled = object["enabled"] as? Bool else { return nil }
        self.init(sourceLayout: layout, flatPack: pack, enabled: enabled,
                  revision: (object["revision"] as? NSNumber)?.uint64Value,
                  completedRevision: (object["completed_revision"] as? NSNumber)?.uint64Value)
    }
}

/// The route state machine. Pure value type: no I/O, no mpv, fully testable
/// off-device.
struct ThreeDRouteMachine {
    static let applierSender = "store-applier"
    static let projectionMessage = "vr180-look-set-projection"
    static let flatKinds: Set<String> = ["flat-2d3d", "flat-sbs", "flat-tb"]

    private(set) var currentRevision: UInt64?
    private(set) var storeKind: String?
    private(set) var completedRevision: UInt64?
    private(set) var context: ThreeDRouteContext?
    private var rejected: Set<String> = []

    var isFlat: Bool { storeKind.map { Self.flatKinds.contains($0) } ?? false }

    mutating func openBatch(revision n: UInt64, kind: String, sender: String, context newContext: ThreeDRouteContext?) -> ThreeDRouteOpen {
        guard sender == Self.applierSender else { return .ignoredForeign }
        if let current = currentRevision, n < current { return .ignoredStale }
        let isNew = n != currentRevision
        if isNew { completedRevision = nil }
        currentRevision = n
        storeKind = kind
        context = newContext
        return isNew ? .opened : .refreshed
    }

    func decision(message name: String, firstArgument: String?, revision: UInt64?, sender: String) -> ThreeDRouteDecision {
        var reason: String? = nil
        if sender != Self.applierSender || currentRevision == nil || revision != currentRevision { reason = "revision" }
        if name == Self.projectionMessage && firstArgument != storeKind { reason = "store_kind" }
        if isFlat && name == Self.projectionMessage && firstArgument != storeKind { reason = "flat_engine" }
        return ThreeDRouteDecision(admit: reason == nil, reason: reason)
    }

    /// True when this (sender, message, values) rejection is new and the
    /// caller should record it; false on a repeat of a recorded rejection.
    mutating func recordRejection(sender: String, message name: String, values: String) -> Bool {
        rejected.insert(sender + name + values).inserted
    }

    /// Stamp the batch complete from the applied-state receipt. Returns the
    /// verdict only on the first completion of the current batch, so a later
    /// republish of the same receipt cannot record a duplicate 3D-VERIFIED.
    mutating func complete(receipt applied: ThreeDAppliedRouteState) -> ThreeDRouteVerdict? {
        guard let completed = applied.completedRevision,
              let current = currentRevision,
              completed == current else { return nil }
        guard completedRevision != current else { return nil }
        completedRevision = current
        guard let c = context else { return .unverified }
        return (applied.enabled == c.enabled && applied.sourceLayout == c.layout && applied.flatPack == c.pack) ? .pass : .fail
    }
}

/// Main-actor home of the route machine on the store side. Records the route
/// evidence lines with the exact pre-move formats: 3D-REJECTED on the first
/// rejection of a key, 3D-VERIFIED when a batch's receipt completes.
@MainActor
final class ThreeDRouteCenter {
    static let shared = ThreeDRouteCenter()
    private(set) var machine = ThreeDRouteMachine()
    private var playingFile = "none"
    private init() {}

    func notePlayingFile(_ path: String) {
        guard !path.isEmpty else { return }
        playingFile = (path as NSString).lastPathComponent
    }

    /// Open (or refresh) the machine's batch from the applier's envelope.
    /// applyThreeDState calls this immediately before the store-revision
    /// envelope goes on the wire.
    func openBatch(revision: UInt64, kind: String, enabled: Bool, layout: Int, pack: Int, output: String, engine: String, generation: String, file: String, appPID: String) {
        let context = ThreeDRouteContext(enabled: enabled, layout: layout, pack: pack, output: output, engine: engine, generation: generation, file: file, appPID: appPID)
        _ = machine.openBatch(revision: revision, kind: kind, sender: ThreeDRouteMachine.applierSender, context: context)
        notePlayingFile(file)
    }

    /// Admission for a stamped route command, decided one layer above the
    /// wire where the Lua gate used to drop it. A rejected command is
    /// recorded once per (sender, message, values) and never sent.
    func admitRoute(name: String, firstArgument: String?, values: String, revision: UInt64, sender: String = ThreeDRouteMachine.applierSender) -> Bool {
        let d = machine.decision(message: name, firstArgument: firstArgument, revision: revision, sender: sender)
        guard let reason = d.reason else { return true }
        if machine.recordRejection(sender: sender, message: name, values: values) {
            Diag.mediaRecord("3D-REJECTED sender=\(sender) message=\(name) values=\(values) revision=\(revision) reason=\(reason)")
        }
        return false
    }

    /// Applied-state receipt ingest (observed
    /// user-data/vr180-look/applied-state). Completing the current batch
    /// records the readback verdict with the exact pre-move 3D-VERIFIED
    /// line format.
    func ingestAppliedState(_ data: Any?) {
        guard let applied = ThreeDAppliedRouteState(data) else { return }
        guard let verdict = machine.complete(receipt: applied), let revision = machine.completedRevision else { return }
        let c = machine.context
        let line = "3D-VERIFIED file=\(c?.file ?? playingFile) generation=\(c?.generation ?? "none") revision=\(revision) output=\(c?.output ?? "none") engine=\(c?.engine ?? "none") verdict=\(verdict.rawValue) verification=route_state layout=\(applied.sourceLayout) pack=\(applied.flatPack) enabled=\(applied.enabled) expected_layout=\(c.map { String($0.layout) } ?? "none") expected_pack=\(c.map { String($0.pack) } ?? "none") expected_enabled=\(c.map { String($0.enabled) } ?? "none") app_pid=\(c?.appPID ?? "none") playing_file=\(playingFile)"
        Diag.mediaRecord(line)
    }
}
// END relocated ThreeDRoute.swift
// BEGIN relocated ThreeDAutoRoute.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// Owner 2026-11-09 14:45 (fix it, make it automatic) and 15:05 (the old vr menu 2d to 3d used to work, now it does not): picking the old video>vr "2d film to 3d" on a 2D film
/// (1) turns the real 3D pipeline on (ThreeDMenu mode full_sbs, automatic prepare + render) AND (2) keeps the old pseudo-3D (vr180-look flat_mono, depth = 0.7*y + 0.3*luma) running as a PREVIEW, labelled on the OSD,
/// until a rendered shot is ready. When the coordinator loads a rendered shot the preview is switched off first (`onShown`, no stacking); when it falls back to the 2D film (seek to an unrendered shot) the preview
/// is selected again (`onBack2D`). Any other vr menu choice ends the preview (`endPreview`). sbs / vr180 on a film the probe does not call stereo keep the old behaviour and get a one-line OSD hint.
/// The pseudo-3D is the owner-visible stop-gap, not a depth render: the label says so. Pure decision + closure runner (Linux-tested); Mac glue is same-line edits.
enum ThreeDAutoRoute {
    struct Plan: Equatable {
        var mode: String? = nil, osd: String? = nil, preview = false
    }
    static let routedMode = "full_sbs"
    static let routedOSD = "pseudo-3D preview, real render preparing"
    static let hintOSD = "this film is not stereo: for real depth use video > 3d (2d film to 3d)"
    static func plan(kind: String, filmLooksStereo: Bool) -> Plan {
        switch kind {
        case "flat-2d3d": return Plan(mode: routedMode, osd: routedOSD, preview: true)
        case "flat-sbs", "vr180": return filmLooksStereo ? Plan() : Plan(osd: hintOSD)
        default: return Plan()
        }
    }
    /// True while the old pseudo-3D preview is the owner's choice (set by the 2d3d menu item, cleared by any other vr choice or mode off).
    static func masterActive(mode: String, projectionOn: Bool, previewOn: Bool) -> Bool { previewOn || projectionOn }
    static var previewActive = false
    /// Wired by ThreeDWiring: switch the old projection off / select flat-2d3d again.
    static var stopPreview: () -> Void = {}, resumePreview: () -> Void = {}
    static func endPreview() { previewActive = false }
    /// Owner 15:26: the 3d menu switch and the vr "2d film to 3d" item are ONE state. 3d off (menu mode off or the "2d to 3d" entry) clears the vr flat-2d3d state too.
    static func turnOff() { previewActive = false; stopPreview() }
    /// The vr "mono" item (vr off) while the 3d switch is on: the 3d mode goes off with it, so either item toggles the other.
    static func vrChoseOff(setMode: (String) -> Void) { setMode("off"); previewActive = false }
    /// What the no-models preview draws for the current 3D menu settings. Every row maps to a visible change (vr180-look.lua pack variant, pack_eye):
    /// pack: 3 side by side (sbs, half sbs), 4 vr180 (equirect-180 warp, side by side), 1 top/bottom, 2 anaglyph (red/cyan). gain: strength 0...2 x base disparity. conv: depth that sits on the screen plane (screen depth row).
    /// zoom: film size on screen (screen size row, 75 deg = 1). soft: 1 = edge-extended fill of the area a smaller film leaves, 0 = black (surround row).
    struct PreviewParams: Equatable { var pack = 3, gain = 1.0, conv = 0.5, zoom = 1.0, soft = 1.0 }
    static func pack(mode: String) -> Int { switch mode { case "over_under": return 1; case "anaglyph": return 2; case "vr180": return 4; default: return 3 } }
    static func previewGain(strength: Double) -> Double { strength.isFinite ? min(2, max(0, strength)) : 1 }
    static func previewConv(screenDepthM: Double?) -> Double { guard let m = screenDepthM, m.isFinite, m > 0 else { return 0.5 }; return min(0.85, max(0.15, 0.5 - 0.15 * log2(m / 1.5))) }
    static func previewZoom(screenDeg: Double?) -> Double { guard let d = screenDeg, d.isFinite, d > 0 else { return 1 }; return min(1.6, max(0.5, d / 75.0)) }
    static func previewParams(mode: String, strength: Double, screenDepthM: Double?, screenDeg: Double?, surround: String) -> PreviewParams {
        PreviewParams(pack: pack(mode: mode), gain: previewGain(strength: strength), conv: previewConv(screenDepthM: screenDepthM), zoom: previewZoom(screenDeg: screenDeg), soft: surround == "soft" ? 1 : 0)
    }
    /// source row: "flat" = treat as 2d (make 3d), "auto" = the probe decides, any layout = the file is already 3d (no 2d-to-3d preview).
    static func effectiveStereo(probe: Bool, source: String) -> Bool { source == "flat" ? false : (source == "auto" ? probe : true) }
    /// quality row: an explicit state while the real render path (CoreML kit) is not running; the preview always uses its fallback depth.
    static func qualityState(quality: String, kitReady: Bool) -> String {
        let t = quality == "auto" ? "auto" : quality.replacingOccurrences(of: "tier", with: "tier ")
        return "3D quality \(t): " + (quality == "auto" ? "fallback only" : "not implemented") + "; selection changes no processing; preview uses fallback depth"
    }
    static var kitReady: () -> Bool = { false }
    /// Wired by ThreeDWiring to the mpv script message; called on every menu change.
    static var packOut: (PreviewParams) -> Void = { _ in }
    /// Owner 15:20: ANY 3d mode picked from the 3d menu on a mono film shows the pseudo-3D preview at once (needs no models, no prepared range); the real render swaps in later.
    static var filmStereo: () -> Bool = { false }, osdOut: (String) -> Void = { _ in }
    static func beginPreview() { if filmStereo() { return }; previewActive = true; resumePreview(); osdOut(routedOSD) }
    /// Runs the plan; the caller then ALWAYS continues with the old selectVRProjection (nothing is skipped any more).
    static func run(kind: String, filmLooksStereo: Bool, setMode: (String) -> Void, osd: (String) -> Void) {
        let p = plan(kind: kind, filmLooksStereo: filmLooksStereo)
        previewActive = p.preview
        if let m = p.mode { setMode(m) }
        if let t = p.osd { osd(t) }
    }
}
// END relocated ThreeDAutoRoute.swift
// BEGIN relocated ThreeDWiring.swift (195y owner-order 3D consolidation, behavior unchanged)
import AppKit

/// 190t I: the one place that hands the existing player plumbing to ThreeDRenderCoordinator as closures. `cmd` is AppDelegate's existing
/// player command helper, the playhead is the controller's current time and the film path is its current file; no new socket code.
/// Idle until the owner picks sbs or vr180 in video > vr > 3d (the coordinator's tick returns at once while mode is off).
enum ThreeDRuntime { static var coordinator: AnyObject?;static var lastRenderState:ThreeDState? }

enum ThreeDPrepareRuntime { static var launcher: ThreeDPrepareLauncher?, timer: Timer? }

extension AppDelegate {
    /// Subscription is replaced when a player arrives; the store outlives every controller.
    func installThreeDSourceResolution() {
        MainActor.assumeIsolated {
        ThreeDRecognitionBridge.migrate()
        ThreeDExperimentMenu.shared.send = { [weak self] in self?.cmd($0) }
        ThreeDExperimentMenu.shared.onExperimentChange = { (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.preferencesDidChange(force: true) }   // 195h r2-7: an experiment toggle runs the existing re-render/re-prepare refresh
        // Owner order 2026-11-15: the 3D experiment master defaults ON at launch,
        // applied through the same setAll path as pressing the master row. One-shot:
        // this wiring runs per player arrival and must never override a manual OFF.
        if !ThreeDExperimentMenu.launchMasterApplied { ThreeDExperimentMenu.launchMasterApplied = true; ThreeDExperimentMenu.shared.setAll(true) }
        ThreeDExperimentMenu.shared.reapplyIfEnabled()
        ThreeDStore.shared.subscribe(ownerID:"player-applier") { [weak self] state,effects in
            if let controller=self?.controller, controller.usesEmbeddedThreeDIntent {
                controller.applyThreeDState(state,effects)
                return // Native entry never invokes the mpv/prepared coordinator.
            }
            (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.applyStoreOutput(state.current.output,reapply:effects.contains(.reapply),filmID:state.currentFilm)
            self?.controller?.applyThreeDState(state,effects)
            let fx=state.effects
            func number(_ k:ThreeDEffectKey,_ fallback:Double)->Double {if case let .number(v)?=fx[k] {return v};return fallback}
            let strength=number(.strength,1),depth=number(.screenDepth,1.5),size=number(.screenSize,75)
            let soft=fx[.surround] != .text("black")
            if ThreeDRuntime.lastRenderState?.current != state.current || ThreeDRuntime.lastRenderState?.effects != state.effects {
            RenderPrefs.write(mode:state.current.output.rawValue,depthScale:strength,convergenceM:depth,screenDeg:size,surroundSoft:soft,overBudget:strength>1)
            (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.preferencesDidChange(force:ThreeDRuntime.lastRenderState?.effects[.quality] != fx[.quality])
            ThreeDRuntime.lastRenderState=state
            }
            ThreeDPrepareRuntime.launcher?.setPaused(state.current.output == .off)
            if effects.contains(.showInfo),fx[.osdLine] != .bool(false) {self?.controller?.osdLine(ThreeDInfo.line(state:state,progress:nil))}
            if effects.contains(.resetView) {self?.controller?.recenterHeadTracking()}
        }
        }
    }
    func startThreeDCoordinator() {
        MainActor.assumeIsolated {
        ThreeDOwnerActionAcceptance.startIfRequested(controller:{ [weak self] in self?.controller })
        StoreAcceptance.startIfRequested(send: { [weak self] in self?.cmd($0) })   // 191b-T: env-gated store acceptance runner; idle without GOR_STORE_ACCEPTANCE_DIR
        ThreeDSubtitleDepth.shared.changed = { [weak self] in self?.controller?.applySubtitleDepthOffset() }
        #if canImport(AppKit)
        if ThreeDPrepareRuntime.launcher == nil {
            // spawn is looked up at every update (late-bound): nil until E-G's native runner registers itself in ThreeDRunnerRegistry: the launcher then says so once and the film stays 2D
            let l = ThreeDPrepareLauncher(spawn: { ThreeDPrepareSpawn.make(runner: ThreeDRunnerRegistry.runner) }, report: { [weak self] t in
                if let d = try? JSONSerialization.data(withJSONObject: ["command": ["show-text", t, 4000]]), let j = String(data: d, encoding: .utf8) { self?.cmd(j) } })
            ThreeDPrepareRuntime.launcher = l
            ThreeDPrepareRuntime.timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                if ProcessInfo.processInfo.environment["GOR_191B_ACCEPTANCE_DIR"] != nil || ProcessInfo.processInfo.environment["GOR_STORE_ACCEPTANCE_DIR"] != nil || ProcessInfo.processInfo.environment["GOR_OWNER_ACTION_DIR"] != nil {return} // menu/pixel matrix must not launch model preparation
                if self?.controller?.mediaTransitionPending == true {l.setPaused(true);return}
                let state=MainActor.assumeIsolated {ThreeDStore.shared.snapshot}
                let film = (self?.controller?.sourceFilmPath).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                let osd: (String) -> Void = { t in if let d = try? JSONSerialization.data(withJSONObject: ["command": ["show-text", t, 4000]]), let j = String(data: d, encoding: .utf8) { self?.cmd(j) } }
                // s37: an already-3D source never goes through 2D->3D depth (it plays as the file is); nil = still deciding, nothing starts yet
                var mode = state.current.output.rawValue
                if mode != "off", let f = film {
                    #if canImport(AVFoundation) && canImport(CoreGraphics)
                    if let g = StereoSourceGate.shared.route(for: f) { if g.route != .depth { mode = "off"; if !g.note.isEmpty, StereoSourceGate.shared.once(film: f, note: g.note) { osd(g.note) } } } else { mode = "off" }
                    #endif
                }
                let wantsModels = mode != "off" && film != nil && ThreeDPreflight.shared.reason == nil
                let dav2Depth = ThreeDExperimentOptions.live.dav2Depth   // 195h A (Delivery A-5): the verify gate follows the selected depth model
                if wantsModels { dav2Depth ? ThreeDModels.shared.ensureDAV2(report: osd) : ThreeDModels.shared.ensure(report: osd) }       // first 3D enable: fetch + verify, stays 2D until verified
                let modelWait = wantsModels && !(dav2Depth ? ThreeDModels.shared.verifiedDAV2 : ThreeDModels.shared.verified)
                let kitWait = wantsModels && !modelWait && !ThreeDKit.register(report: osd)       // runner registers late-bound once the CoreML kit is complete
                if wantsModels, !modelWait, !kitWait { ThreeDKit.maybeSelfTest(enabled: true, filmPreparing: l.isPreparing) }
                l.update(mode: mode, film: film, playhead: self?.controller?.currentTime, info: film.flatMap { ThreeDFilmInfo.shared.info(for: $0) },
                         quality: {if case let .text(q)?=state.effects[.quality] {return q};return "auto"}(), experiments: ThreeDExperimentOptions.live.prepareComponent, preflightReason: ThreeDPreflight.shared.reason ?? (modelWait ? "models not verified yet" : (kitWait ? "CoreML kit missing" : nil)))
            }
        }
        #endif
        ThreeDPreflight.shared.start(mpvExecutable: { [weak self] in self?.mpvProcess?.executableURL })
        #if canImport(AVFoundation) && canImport(Metal) && canImport(CoreVideo)
        guard ThreeDRuntime.coordinator == nil else { return }
        let c = ThreeDRenderCoordinator(
            send: { [weak self] json in self?.cmd(json) },
            mpvExecutable: { [weak self] in self?.mpvProcess?.executableURL },
            playhead: { [weak self] in
                if ProcessInfo.processInfo.environment["GOR_191B_ACCEPTANCE_DIR"] != nil || ProcessInfo.processInfo.environment["GOR_STORE_ACCEPTANCE_DIR"] != nil || ProcessInfo.processInfo.environment["GOR_OWNER_ACTION_DIR"] != nil {return nil} // do not replace the paused acceptance fixture with a cached shot
                let value = self?.activePlayerEngine == .gorav ? self?.goravCurrentTime : self?.controller?.currentTime
                guard let t = value, t.isFinite, t >= 0 else { return nil }
                return t
            },
            film: { [weak self] in
                if self?.activePlayerEngine == .gorav { return self?.goravSourceURL }
                guard let p = self?.controller?.currentFilePath, !p.isEmpty else { return nil }
                return URL(fileURLWithPath: p)
            },
            activeEngine: { [weak self] in self?.activePlayerEngine ?? .mpv },
            preparedSession: { [weak self] in self?.goravPreparedPlayback },
            goravDecoders: { [] }) // actual native decoder-admission API not landed; never borrow mpv probes
        c.start(); ThreeDRuntime.coordinator = c
        #if canImport(AppKit)
        installThreeDSourceResolution()
        StereoSourceGate.shared.resolvedSource = { [weak self] url in
            guard self?.controller?.currentFilePath==url.path else{return nil}
            return self?.controller?.detectedSourceLabel
        }
        ThreeDMenu.shared.detectedSource = { [weak self] in self?.controller?.sourceSuggestion ?? "unknown" }
        ThreeDMenu.shared.subtitleDepth = { [weak self] d in self?.controller?.adjustSubtitleDepth(by:d) }
        ThreeDMenu.shared.calibrationMarker = { [weak self] on in
            guard let root = self?.controller as? NSView else { return }
            ThreeDCornerTuneView.shared.setCalibration(on, in: root)
        }
        #endif
        #endif
        }
    }
}
// END relocated ThreeDWiring.swift
// BEGIN relocated ThreeDStoreAcceptance.swift (195y owner-order 3D consolidation, behavior unchanged)
import AppKit
import Foundation

/// 191b-T (owner 22:08, architect block 191b; E-G store contract 22:13 + lane/eg-191b 3cfd0fe4):
/// in-app acceptance runner for the 3D store redesign. Triggered when GOR_STORE_ACCEPTANCE_DIR is
/// set; the Python driver (tools/store_acceptance.py) spawns the installed app, owns the deadline,
/// and re-validates every artifact from outside.
///
/// Per case it: dispatches store actions AND drives the real "3D" menu row via
/// NSMenu.performActionForItem (rows are matched by their ThreeDKeymap act rawValue - the B4 titles
/// "SBS"/"Half SBS"/"Top/Bottom" exist in both the View and Film-is sections), snapshots the store
/// before/after, records the applier's applied commands, grabs one frame, and writes verdict.txt.
/// Assertions read the LIVE store (ThreeDStore.shared.snapshot.current), never text pins.
/// One directory per case under the env dir; complete.json lands last.
@MainActor enum StoreAcceptance {
    /// Matrix spellings: ThreeDSource.Format and ThreeDOutput case names are the B1 spellings.
    private static let sourceFormats: [ThreeDSource.Format] = ThreeDSource.Format.allCases
    private static let outputCases: [ThreeDOutput] = ThreeDOutput.allCases

    struct CaseResult { let name:String; let verdict:String }

    private static var sendCommand: (String) -> Void = { _ in }

    /// Entry: called from the wiring layer once the main menu exists and the env dir is set;
    /// `send` is the existing player command closure (same pattern as the retired axes runner).
    static func startIfRequested(send: @escaping (String) -> Void) {
        guard let dir = ProcessInfo.processInfo.environment["GOR_STORE_ACCEPTANCE_DIR"], !dir.isEmpty else { return }
        sendCommand = send
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        awaitReady(root:root,deadline:Date().timeIntervalSince1970+35)
    }

    private static func awaitReady(root:URL,deadline:Double) {
        if ThreeDStore.shared.snapshot.currentFilm != nil,ThreeDMenu.shared.installedMenu != nil {runAll(into:root);return}
        if Date().timeIntervalSince1970 >= deadline {
            write("NOT_RUN readiness_film_or_menu_missing\n",to:root.appendingPathComponent("readiness.txt"))
            write("{\"complete\":false,\"reason\":\"readiness_film_or_menu_missing\"}",to:root.appendingPathComponent("complete.json"));return
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {MainActor.assumeIsolated {awaitReady(root:root,deadline:deadline)}}
    }

    /// Menu row for a keymap act, found by representedObject (never by title).
    private static func findRow(_ act: ThreeDKeymap.Act) -> (NSMenu, Int)? {
        guard let menu = ThreeDMenu.shared.installedMenu else { return nil }
        for (index, item) in menu.items.enumerated() {
            if (item.representedObject as? String) == act.rawValue { return (menu, index) }
        }
        return nil
    }

    /// Drive a real menu row: NSMenu.performActionForItem, as the block mandates.
    private static func perform(_ act: ThreeDKeymap.Act, log: inout [String]) -> Bool {
        guard let (menu, index) = findRow(act) else {
            log.append("menu row NOT FOUND act=\(act.rawValue)")
            return false
        }
        log.append("menu performActionForItem act=\(act.rawValue)")
        menu.performActionForItem(at: index)
        return true
    }

    private static func write(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func snapshotJSON() -> String {
        let snap = ThreeDStore.shared.snapshot
        guard let data = try? JSONEncoder().encode(snap), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private static func commandsJSON() -> String {
        let cmds = ThreeDStore.shared.appliedCommands
        guard let data = try? JSONSerialization.data(withJSONObject: cmds, options: .prettyPrinted),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func grab(into dir: URL) {
        if let data = try? JSONSerialization.data(withJSONObject: ["command": ["screenshot-to-file", dir.appendingPathComponent("frame.png").path, "window"]]),
           let s = String(data: data, encoding: .utf8) { sendCommand(s) }
    }

    private static func sourceAct(_ format: ThreeDSource.Format) -> ThreeDKeymap.Act {
        switch format {
        case .auto: return .filmAuto; case .flat2D: return .film2D; case .sbsFull: return .filmSBS
        case .sbsHalf: return .filmHalfSBS; case .tbFull: return .filmTB; case .tbHalf: return .filmHalfTB
        case .vr180SBS: return .filmVR180SBS; case .vr180TB: return .filmVR180TB
        case .vr360Mono: return .film360; case .vr360TB: return .film360TB
        }
    }
    /// Case-directory spellings stay the B1 block's (the driver enumerates them); raw values differ.
    private static func b1(_ output: ThreeDOutput) -> String {
        switch output {
        case .off: return "off"; case .sbs: return "sbs"; case .halfSBS: return "halfSBS"
        case .tb: return "tb"; case .vr180: return "vr180"; case .anaglyph: return "anaglyph"
        }
    }
    private static func outputAct(_ output: ThreeDOutput) -> ThreeDKeymap.Act {
        switch output {
        case .off: return .viewOff; case .sbs: return .viewSBS; case .halfSBS: return .viewHalfSBS
        case .tb: return .viewTB; case .vr180: return .viewVR180; case .anaglyph: return .viewAnaglyph
        }
    }

    /// One case: direct dispatch cross-check, then the menu drive; settle, snapshot, grab, verdict.
    private static func runCase(_ name: String, into root: URL,
                                actions: (inout [String]) -> Bool, expect: (ThreeDState) -> String) -> CaseResult {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var log: [String] = []
        write(snapshotJSON(), to: dir.appendingPathComponent("store-before.json"))
        let drove = actions(&log)
        write(log.joined(separator: "\n") + "\n", to: dir.appendingPathComponent("action.log"))
        let after = ThreeDStore.shared.snapshot
        write(snapshotJSON(), to: dir.appendingPathComponent("store-after.json"))
        write(commandsJSON(), to: dir.appendingPathComponent("commands.json"))
        grab(into: dir)
        let verdict = drove ? expect(after) : "FAIL menu_row_missing"
        write(verdict + "\n", to: dir.appendingPathComponent("verdict.txt"))
        return CaseResult(name: name, verdict: verdict)
    }

    private static func runAll(into root: URL) {
        var results: [CaseResult] = []
        let selected=ProcessInfo.processInfo.environment["GOR_STORE_ACCEPTANCE_CASE"]
        func wants(_ name:String)->Bool {selected == nil || selected == name}
        // Matrix: every Source x Output. Direct dispatch first (the store path), then the real menu
        // row for the same pair (the menu path); both must land on the same live state.
        for source in sourceFormats {
            for output in outputCases {
                let name = "matrix_\(source.rawValue)__\(b1(output))"
                guard wants(name) else {continue}
                results.append(runCase(name, into: root, actions: { log in
                    ThreeDStore.shared.dispatch(.setSource(ThreeDSource(source)))
                    ThreeDStore.shared.dispatch(.setOutput(output))
                    log.append("dispatch setSource(\(source.rawValue)) setOutput(\(output.rawValue))")
                    guard ThreeDStore.shared.snapshot.current.output == output else {log.append("direct dispatch output mismatch");return false}
                    var ok = perform(sourceAct(source), log: &log)
                    // View VR180 is a toggle; enter it from Off rather than toggle our
                    // direct-dispatch target back Off. Final assertion remains unchanged.
                    if output == .vr180 {ok = perform(.viewOff, log: &log) && ok}
                    ok = perform(outputAct(output), log: &log) && ok
                    return ok
                }, expect: { after in
                    let cur = after.current
                    guard cur.source.format == source else { return "FAIL source=\(cur.source.format.rawValue)" }
                    guard cur.output == output else { return "FAIL output=\(cur.output.rawValue)" }
                    return "PASS state_applied"
                }))
            }
        }
        if wants("seq1_open2d_sbs_stable") {results.append(sequence1(into: root))}
        if wants("seq2_vr180_off_reopen") {results.append(sequence2(into: root))}
        if wants("seq3_native_vr180_off_flat") {results.append(sequence3(into: root))}
        if wants("seq4_magnet_2d") {results.append(sequence4(into: root))}
        if wants("seq5_keys_table") {results.append(sequence5(into: root))}
        let summary: [String: Any] = ["complete": true, "pixel_verdict": "DRIVER_OWNS",
            "cases": results.map { ["case": $0.name, "verdict": String($0.verdict.prefix(80))] }]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted) {
            try? data.write(to: root.appendingPathComponent("complete.json"), options: .atomic)
        }
    }

    // Sequences 1-5 from the 191b block. Timing legs (render-shot swaps, 2-minute playback,
    // close/reopen) are noted in the action log; the driver owns wall-clock and pixel checks.
    private static func sequence1(into root: URL) -> CaseResult {
        // Plain film opens 2D; View SBS must stay SBS through 3 render-shot swaps + 2 min playback.
        // The owner regression leg first presents a generated VR180 shot, then selects View SBS: the
        // explicit output action must replace the stale generated presentation immediately.
        runCase("seq1_open2d_sbs_stable", into: root, actions: { log in
            var ok = perform(.viewVR180, log: &log)
            if let id = ThreeDStore.shared.snapshot.currentFilm {
                ThreeDStore.shared.dispatch(.generated(id, ThreeDSource(.vr180SBS), ThreeDStore.shared.snapshot.current.output))
                log.append("generated VR180 presentation source=\(ThreeDStore.shared.snapshot.presentationSource.format.rawValue)")
            } else { log.append("generated VR180 NOT_RUN no current film"); ok = false }
            ok = perform(.viewSBS, log: &log) && ok
            log.append("assert opened 2D; View SBS holds through 3 render-shot swaps and 120s playback")
            return ok
        }, expect: { after in
            guard after.current.output == .sbs else { return "FAIL output=\(after.current.output.rawValue)" }
            guard after.presentationSource.format == .flat2D else { return "FAIL presentationSource=\(after.presentationSource.format.rawValue)" }
            return "PASS stayed_sbs"
        })
    }
    private static func sequence2(into root: URL) -> CaseResult {
        // SBS -> VR180 -> Off -> close -> reopen: Off persists and pixels equal the source.
        runCase("seq2_vr180_off_reopen", into: root, actions: { log in
            var ok = perform(.viewSBS, log: &log)
            ok = perform(.viewVR180, log: &log) && ok
            ok = perform(.toggle3D, log: &log) && ok
            log.append("close + reopen film; Off must persist; the driver compares reopen pixels to the source")
            return ok
        }, expect: { after in after.current.output == .off ? "PASS off_persisted" : "FAIL output=\(after.current.output.rawValue)" })
    }
    private static func sequence3(into root: URL) -> CaseResult {
        // Native VR180 metadata fixture opens VR180; Shift+D gives the exact equirect frame flat.
        runCase("seq3_native_vr180_off_flat", into: root, actions: { log in
            log.append("native VR180 metadata fixture must open VR180; toggle gives the equirect frame flat")
            return perform(.toggle3D, log: &log)
        }, expect: { after in after.current.output == .off ? "PASS equirect_flat" : "FAIL output=\(after.current.output.rawValue)" })
    }
    private static func sequence4(into root: URL) -> CaseResult {
        // The owner's converted magnet file: opens 2D, Off works, Film is shows 2D. Path arrives via
        // GOR_STORE_ACCEPTANCE_MAGNET (env override or the driver's Downloads/Movies discovery rule).
        guard ProcessInfo.processInfo.environment["GOR_STORE_ACCEPTANCE_MAGNET"] != nil else {
            let dir = root.appendingPathComponent("seq4_magnet_2d", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            write("NOT_RUN owner_file_not_provided\n", to: dir.appendingPathComponent("verdict.txt"))
            return CaseResult(name: "seq4_magnet_2d", verdict: "NOT_RUN owner_file_not_provided")
        }
        return runCase("seq4_magnet_2d", into: root, actions: { log in
            log.append("fresh child opened the magnet file through the normal CLI load path before readiness; must stay 2D")
            return true
        }, expect: { after in after.current.source.format == .flat2D ? "PASS opened_2d" : "FAIL source=\(after.current.source.format.rawValue)" })
    }
    private static func sequence5(into root: URL) -> CaseResult {
        // Every B4 key row: the installed menu row's key equivalent IS the keymap chord (one table
        // drives both), and dispatching the act lands the same store transition as the menu drive.
        runCase("seq5_keys_table", into: root, actions: { log in
            var mismatches = 0
            for row in ThreeDKeymap.rows where row.chord != nil {
                if row.act == .subtitleDepthNearer || row.act == .subtitleDepthFarther {
                    // These are keyboard-only by the existing keymap/menu contract.
                    let chord=row.chord!
                    if !chord.matches(charactersIgnoringModifiers:chord.key,keyCode:chord.keyCode ?? 0,shift:chord.shift,option:chord.option,control:chord.control,command:chord.command) {mismatches += 1}
                    log.append("keyboard-only chord checked act=\(row.act.rawValue)");continue
                }
                guard let (menu, index) = findRow(row.act) else { log.append("missing row act=\(row.act.rawValue)"); mismatches += 1; continue }
                let item = menu.items[index]
                if item.keyEquivalent.lowercased() != row.chord!.key {
                    log.append("key mismatch act=\(row.act.rawValue) menu=\(item.keyEquivalent) table=\(row.chord!.key)"); mismatches += 1
                }
            }
            log.append("chorded rows checked against the installed menu; mismatches=\(mismatches)")
            return mismatches == 0
        }, expect: { _ in "PASS keys_match_menu" })
    }
}
// END relocated ThreeDStoreAcceptance.swift
// BEGIN relocated ThreeDOwnerActionAcceptance.swift (195y owner-order 3D consolidation, behavior unchanged)
import AppKit
import Foundation

/// Isolated, environment-gated Mac action receipt. Never runs on the interactive owner's process.
@MainActor enum ThreeDOwnerActionAcceptance {
    private static var requested = false
    static func readinessReason(controller:Bool,film:Bool,menu:Bool) -> String? {
        if !controller {return "controller_missing"}
        if !film {return "current_film_missing"}
        if !menu {return "installed_menu_missing"}
        return nil
    }
    static func startIfRequested(controller: @escaping () -> PPController?) {
        guard let path=ProcessInfo.processInfo.environment["GOR_OWNER_ACTION_DIR"],!requested else {return}
        requested=true
        let root=URL(fileURLWithPath:path,isDirectory:true)
        awaitReady(root:root,controller:controller,deadline:Date().timeIntervalSince1970+35)
    }
    private static func awaitReady(root:URL,controller:@escaping () -> PPController?,deadline:Double) {
        let player=controller()
        let reason=readinessReason(controller:player != nil,film:ThreeDStore.shared.snapshot.currentFilm != nil,menu:ThreeDMenu.shared.installedMenu != nil)
        write(["ready":reason == nil,"reason":reason ?? "ready","timestamp":Date().timeIntervalSince1970],root.appendingPathComponent("readiness.json"))
        if let player,reason == nil {step(0,root:root,controller:player);return}
        if Date().timeIntervalSince1970 >= deadline {
            write(["complete":false,"verdict":"NOT_RUN","reason":"readiness_"+(reason ?? "unknown")],root.appendingPathComponent("complete.json"));return
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {MainActor.assumeIsolated {awaitReady(root:root,controller:controller,deadline:deadline)}}
    }
    private static var steps:[(String,[ThreeDKeymap.Act])] {
        if ProcessInfo.processInfo.environment["GOR_OWNER_ACTION_NATIVE"] == "1" {return [("native_vr180",[.filmAuto,.viewOff,.viewVR180]),("native_off",[.viewOff]),("native_reenable",[.viewVR180]),("roll_zero",[]),("roll_legacy",[]),("roll_extended",[])]}
        return [("ordinary_off",[.film2D,.viewOff]),("twoD_to_threeD",[.toggle3D]),("sbs",[.viewSBS]),("vr180",[.viewVR180]),("sbs_return",[.viewSBS]),("off",[.viewOff])]
    }
    private static func write(_ value:Any,_ url:URL) {
        guard JSONSerialization.isValidJSONObject(value),let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]) else {return}
        try? data.write(to:url,options:.atomic)
    }
    private static func step(_ index:Int,root:URL,controller:PPController) {
        if index==steps.count {write(["complete":true,"pid":ProcessInfo.processInfo.processIdentifier],root.appendingPathComponent("complete.json"));return}
        let (name,actions)=steps[index],dir=root.appendingPathComponent(name,isDirectory:true)
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let actionStarted=Date().timeIntervalSince1970
        var drove=true
        for action in actions {
            guard let menu=ThreeDMenu.shared.installedMenu,let row=menu.items.firstIndex(where:{($0.representedObject as? String)==action.rawValue}) else {drove=false;continue}
            menu.performActionForItem(at:row)
        }
        let revision=ThreeDStore.shared.revision
        if name.hasPrefix("roll_") {
            OwnerActionPlayerProbe.setRoll(socket:controller.ipcPath,extended:name == "roll_extended",roll:name == "roll_zero" ? "0":"0.174532925")
        }
        // Readiness is a revision barrier, not a shader-speed-dependent sleep.
        DispatchQueue.main.asyncAfter(deadline:.now()+(name.hasPrefix("roll_") ? 0.1:1.5)) {MainActor.assumeIsolated {
            let snapshot=ThreeDStore.shared.snapshot
            let encoded=(try? JSONEncoder().encode(snapshot)).flatMap {try? JSONSerialization.jsonObject(with:$0)} ?? [:]
            let receipt:[String:Any]=["step":name,"actions":actions.map {$0.rawValue},"menu_driven":drove,
                "pid":ProcessInfo.processInfo.processIdentifier,"build":BuildID.value(),"timestamp":actionStarted,"revision":revision,
                "source":snapshot.current.source.format.rawValue,"output":snapshot.current.output.rawValue,
                "vr_mode":controller.vrModeEnabled,"store":encoded,"commands":ThreeDStore.shared.appliedCommands]
            write(receipt,dir.appendingPathComponent("action.json"))
            let socket=controller.ipcPath
            let fields=["path","video-params/stereo-in","video-params/spherical-mapping","glsl-shaders","glsl-shader-opts",
                "user-data/vr180-look/enabled","user-data/gor/3d-internal","user-data/gor/3d-parent-film-id",
                "user-data/gor/3d-applied-state","user-data/vr180-look/applied-state"]
            DispatchQueue.global(qos:.utility).async {
                let values=OwnerActionPlayerProbe.readCompleted(socket:socket,fields:fields,revision:revision,deadline:actionStarted+60)
                DispatchQueue.main.async {MainActor.assumeIsolated {
                    write(["fields":fields,"replies":values,"timestamp":Date().timeIntervalSince1970],dir.appendingPathComponent("ipc.json"))
                    OwnerActionPlayerProbe.frame(socket:controller.ipcPath,path:dir.appendingPathComponent("frame.png").path)
                    if name == "roll_extended" {OwnerActionPlayerProbe.restoreVariant(socket:controller.ipcPath)}
                    step(index+1,root:root,controller:controller)
                }}
            }
        }}
    }
}
// END relocated ThreeDOwnerActionAcceptance.swift
// BEGIN relocated ThreeDDegrade.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// CONTRACT-190v s38 player side of the graceful-degradation FSM. The transition table is DegradeTable (generated from tools/depth_analysis/degrade_fsm.py,
/// pinned by Tests/ThreeDDegrade). This class owns only what the contract leaves to the Mac: the clocks (500 ms last-good-depth hold, 3-strike shot limit)
/// and turning observed player facts into events. It never restarts the player, seeks, pauses or touches audio: an action that names any of those is dropped
/// before it reaches the executor, and every executor action is a depth-input swap, an OSD line or a prepare-side effect. Each transition is logged verbatim:
///   3dfsm from=<S> ev=<e> to=<S2> act=<a1|a2|-> note=<reason>
/// Not compiled or run on a Mac.
final class ThreeDDegrade {
    struct Step: Equatable { var from: String, event: String, to: String, actions: [String], note: String }
    static let forbidden = ["mpv_restart", "recreate", "seek", "pause_playback", "audio"]

    private let lock = NSLock()
    private let log: (String) -> Void, exec: (String) -> Void
    private(set) var state = "INIT"
    private var holdSince: Double?, strikes: [Int: Int] = [:], modeOn: Bool?, lastProbe: String?, quitObserver: NSObjectProtocol?

    init(log: @escaping (String) -> Void = { print($0); fflush(stdout) }, exec: @escaping (String) -> Void = { _ in }) {
        self.log = log; self.exec = exec
        quitObserver = NotificationCenter.default.addObserver(forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: nil) { [weak self] _ in self?.quit() }   // app_quit: nothing is flushed here, prepare persists per shot already
    }
    deinit { if let o = quitObserver { NotificationCenter.default.removeObserver(o) } }

    /// Pure: the log line for one transition, same format as degrade_fsm.Transition.logline (act field has no spaces).
    static func line(_ s: Step) -> String {
        let acts = s.actions.isEmpty ? "-" : s.actions.joined(separator: "|").replacingOccurrences(of: " ", with: "_")
        return "3dfsm from=\(s.from) ev=\(s.event) to=\(s.to) act=\(acts)" + (s.note.isEmpty ? "" : " note=\(s.note)")
    }
    /// Pure: total transition function; an unlisted pair is a logged self-loop "ignored".
    static func handle(_ state: String, _ event: String) -> Step {
        guard let r = DegradeTable.rules[state + "|" + event] else { return Step(from: state, event: event, to: state, actions: [], note: "ignored") }
        return Step(from: state, event: event, to: r.to, actions: r.actions, note: r.note)
    }
    static func allowed(_ action: String) -> Bool { !forbidden.contains { action.contains($0) } }

    /// The scripted degradation walk the first-Mac-run self-test log must contain (CONTRACT s39 item 12; same events as rehearsal.fsm_walk_lines), from a fresh instance.
    static let walkEvents = ["probe_ok", "playhead_covered", "playhead_uncovered", "lgd_timeout", "playhead_covered", "thermal_trip", "thermal_clear", "app_quit", "relaunch", "probe_ok", "playhead_covered"]
    static func walkLines() -> [String] {
        var s = "INIT", out: [String] = []
        for e in walkEvents { let t = handle(s, e); out.append(line(t)); s = t.to }
        return out
    }

    @discardableResult
    func feed(_ event: String, now: Double = ProcessInfo.processInfo.systemUptime) -> Step {
        lock.lock()
        let s = Self.handle(state, event); state = s.to
        if s.to == "LGD_HOLD" && s.from != "LGD_HOLD" { holdSince = now } else if s.to != "LGD_HOLD" { holdSince = nil }
        lock.unlock()
        log(Self.line(s))
        s.actions.filter(Self.allowed).forEach(exec)
        return s
    }

    /// Coverage of the playhead by Tier-1 depth, called every tick with the clock. Feeds an event only on a change the table cares about.
    func observe(covered: Bool, now: Double) {
        lock.lock(); let st = state, since = holdSince; lock.unlock()
        switch st {
        case "READY_STEREO": if !covered { feed("playhead_uncovered", now: now) }
        case "LGD_HOLD":
            if covered { feed("lgd_recovered", now: now) }
            else if let t = since, (now - t) * 1000 >= Double(DegradeTable.lgdHoldMs) { feed("lgd_timeout", now: now) }
        case "PREPARING_FLAT", "FLAT_DEGRADED": if covered { feed("playhead_covered", now: now) }
        default: break
        }
    }
    /// 3-strike limit per shot: a prepare/render failure feeds shot_error until the third, then shot_error_limit (the shot's range plays flat).
    func shotFailed(_ shot: Int) {
        lock.lock(); let n = (strikes[shot] ?? 0) + 1; strikes[shot] = n; lock.unlock()
        feed(n >= DegradeTable.shotErrorLimit ? "shot_error_limit" : "shot_error")
    }
    func shotSucceeded(_ shot: Int) { lock.lock(); strikes[shot] = nil; lock.unlock() }
    func sourceChanged() { lock.lock(); strikes = [:]; lastProbe = nil; lock.unlock(); feed("source_changed") }
    /// Menu toggle: off from any state, on only from UNAVAILABLE_FLAT; then a re-probe outcome (`probe`) moves it on.
    /// Only on a CHANGE of the menu mode (a per-tick call must not re-enter INIT every tick); the first call records the mode, and an initial "off" disables.
    func userMode(on: Bool) {
        lock.lock(); let st = state, prev = modeOn; modeOn = on; lock.unlock()
        guard prev != on else { return }
        lock.lock(); lastProbe = nil; lock.unlock()
        if on { if st == "UNAVAILABLE_FLAT" { feed("user_enable_3d") } } else if st != "UNAVAILABLE_FLAT" { feed("user_disable_3d") }
    }
    /// Probe outcome while INIT (or UNAVAILABLE_FLAT after a condition change): one of probe_ok, kit_missing, kit_bad_hash, moge_licence_off, refuse_hdr, refuse_vfr.
    /// The same refusal again in UNAVAILABLE_FLAT is not re-fed (it would log a reprobe every tick); a different outcome is.
    func probe(_ event: String) {
        lock.lock(); let st = state, last = lastProbe; if st == "INIT" || st == "UNAVAILABLE_FLAT" { lastProbe = event }; lock.unlock()
        guard st == "INIT" || st == "UNAVAILABLE_FLAT", !(st == "UNAVAILABLE_FLAT" && last == event) else { return }
        feed(event)
    }
    /// Thermal trip/clear and disk full/freed from the existing hooks (ThreeDThermalGate suspend/resume, writer ENOSPC).
    func thermal(trip: Bool) { feed(trip ? "thermal_trip" : "thermal_clear") }
    func disk(full: Bool) { feed(full ? "disk_full" : "disk_freed") }
    func quit() { feed("app_quit") }
}

// BEGIN relocated ThreeDDegradeProbes.swift (195y G2, behavior unchanged)
/// CONTRACT-190v s38 event sources for ThreeDDegrade: what the kit, the source file and the disk say, turned into FSM events. The decisions are pure (and pinned in
/// Tests/ThreeDDegrade); only the AVFoundation read and the volume query touch the system. Not compiled or run on a Mac.
enum ThreeDDegradeProbe {
    /// Kit outcome while INIT: nil = not decided yet (verification still running), else one of probe_ok / kit_missing / kit_bad_hash / moge_licence_off.
    /// MoGe-2 being the only missing package is the licence gate (its lock row is off), exactly as ThreeDKit.message words it.
    static func kitEvent(missing: [String], verified: Bool, verifyFailed: [String]?, verifying: Bool = false) -> String? {
        if missing == ["moge2_vits_*.mlpackage"] { return "moge_licence_off" }
        if !missing.isEmpty { return "kit_missing" }
        if verifyFailed != nil { return "kit_bad_hash" }
        if verified { return "probe_ok" }
        return nil        // not verified, not failed (hash check running or not started): stay INIT, playing 2D, until it answers
    }
    /// Source outcome: HDR transfer or Dolby Vision -> refuse_hdr (native 2D HDR passthrough, never tone-clipped); VFR -> refuse_vfr; else nil. Same verdicts as SourceFormat.refuseReasons.
    static func sourceEvent(_ f: SourceFacts) -> String? {
        if SourceFormat.hdrTransfers.contains(f.transfer) || f.dolbyVision { return "refuse_hdr" }
        if SourceFormat.isVFR(f) { return "refuse_vfr" }
        return nil
    }
    /// ENOSPC as Foundation reports it: NSCocoaError 640 (NSFileWriteOutOfSpaceError) or POSIX 28.
    static func isNoSpace(domain: String, code: Int) -> Bool { (domain == NSCocoaErrorDomain && code == 640) || (domain == NSPOSIXErrorDomain && code == 28) }
    static let minHeadroomBytes: Int64 = 2 << 30      // disk_freed once the cache volume has 2 GiB free again (a technical call, not an owner figure)

    private static let lock = NSLock()
    private static var diskFullFlag = false, sourceCache: [String: String] = [:], sourcePending = Set<String>()
    /// Called from the .dzc writer's catch sites.
    static func noteWriteError(_ e: Error) { let n = e as NSError; if isNoSpace(domain: n.domain, code: n.code) { lock.lock(); diskFullFlag = true; lock.unlock() } }
    /// true once per ENOSPC occurrence.
    static func takeDiskFull() -> Bool { lock.lock(); defer { lock.unlock() }; let f = diskFullFlag; diskFullFlag = false; return f }
    static func headroomOK(at url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? Int64.max) >= minHeadroomBytes
    }
    /// Cached per film path. "" = looked, no refusal; nil = not read yet (the read runs once on a utility queue).
    static func sourceEvent(film: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = sourceCache[film.path] { return c }
        #if canImport(AVFoundation) && canImport(CoreMedia)
        if sourcePending.insert(film.path).inserted {
            DispatchQueue.global(qos: .utility).async {
                let e = SourceFormatProbe.facts(url: film).flatMap { sourceEvent($0) } ?? ""
                lock.lock(); sourceCache[film.path] = e; lock.unlock()
            }
            return nil
        }
        return nil
        #else
        return ""
        #endif
    }
}
// END relocated ThreeDDegradeProbes.swift

// BEGIN relocated ThreeDDegradeTable.swift (195y G2, behavior unchanged)
// GENERATED from tools/depth_analysis/degrade_fsm.py by Tests/ThreeDDegrade/gen_table.py (CONTRACT-190v s38). Do not edit by hand; the pin test regenerates and diffs.
// Pure data: (state, event) -> next state, action strings, note. Unlisted pairs are logged "ignored" self-loops (DegradeTable.handle).
// Not compiled or run on a Mac.

enum DegradeTable {
    static let lgdHoldMs = 500, shotErrorLimit = 3
    static let states: [String] = ["INIT", "UNAVAILABLE_FLAT", "PREPARING_FLAT", "READY_STEREO", "LGD_HOLD", "FLAT_DEGRADED", "PREP_BLOCKED"]
    static let events: [String] = ["probe_ok", "kit_missing", "kit_bad_hash", "moge_licence_off", "refuse_hdr", "refuse_vfr", "prepare_done", "playhead_covered", "playhead_uncovered", "lgd_recovered", "lgd_timeout", "shot_error", "shot_error_limit", "disk_full", "disk_freed", "thermal_trip", "thermal_clear", "source_changed", "app_quit", "relaunch", "user_disable_3d", "user_enable_3d"]
    /// "state|event" -> (to, actions, note)
    static let rules: [String: (to: String, actions: [String], note: String)] = [
        "FLAT_DEGRADED|app_quit": ("INIT", ["act_persist"], ""),
        "FLAT_DEGRADED|disk_full": ("PREP_BLOCKED", ["act_prepare_pause", "act_badge(3D prep paused: disk full)"], ""),
        "FLAT_DEGRADED|playhead_covered": ("READY_STEREO", ["act_play_stereo", "act_badge_clear", "act_osd(3D on)"], ""),
        "FLAT_DEGRADED|shot_error": ("FLAT_DEGRADED", ["act_prepare_retry_shot"], ""),
        "FLAT_DEGRADED|shot_error_limit": ("FLAT_DEGRADED", ["act_mark_shot_failed", "act_menu_note(one scene plays in 2D)"], ""),
        "FLAT_DEGRADED|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "FLAT_DEGRADED|thermal_trip": ("PREP_BLOCKED", ["act_prepare_pause", "act_badge(3D prep paused: thermals)"], ""),
        "FLAT_DEGRADED|user_disable_3d": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_prepare_abort", "act_badge_clear"], "menu toggle; 2D is instant (depth-input swap only)"),
        "INIT|kit_bad_hash": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_menu_note(3D kit corrupt - re-download)"], "hash mismatch: treat as tampered/partial download, never run it"),
        "INIT|kit_missing": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_menu_note(3D kit not installed)"], "retry on kit_ok (kit download route is owner-Mac)"),
        "INIT|moge_licence_off": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_menu_note(3D off: depth-kit licence)"], "MoGe-2 licence-gated off; no VDA-only fallback (Tier 1 never lowered)"),
        "INIT|probe_ok": ("PREPARING_FLAT", ["act_play_flat", "act_prepare_start", "act_badge(3D preparing)"], "playback starts in 2D immediately; prepare fills behind the playhead"),
        "INIT|refuse_hdr": ("UNAVAILABLE_FLAT", ["act_play_flat_native_hdr", "act_menu_note(HDR source: 3D off)"], "2D path passes HDR through untouched; never silently tone-clipped"),
        "INIT|refuse_vfr": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_menu_note(VFR source: 3D off)"], "VFR timestamps rejected (s26 keyframe/PTS contract)"),
        "INIT|relaunch": ("INIT", ["act_load_cache", "act_reprobe"], "cold start: prepared .dzc shots survive; re-probe picks the branch"),
        "INIT|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "INIT|user_disable_3d": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_prepare_abort", "act_badge_clear"], "menu toggle; 2D is instant (depth-input swap only)"),
        "LGD_HOLD|app_quit": ("INIT", ["act_persist"], ""),
        "LGD_HOLD|lgd_recovered": ("READY_STEREO", ["act_play_stereo"], "gap closed inside the hold budget; user saw nothing"),
        "LGD_HOLD|lgd_timeout": ("FLAT_DEGRADED", ["act_play_flat", "act_osd(3D off - playing 2D)", "act_badge(3D catching up)"], "hold budget exhausted: drop to 2D rather than stall a frame"),
        "LGD_HOLD|playhead_covered": ("READY_STEREO", ["act_play_stereo"], ""),
        "LGD_HOLD|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "LGD_HOLD|user_disable_3d": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_prepare_abort", "act_badge_clear"], "menu toggle; 2D is instant (depth-input swap only)"),
        "PREPARING_FLAT|app_quit": ("INIT", ["act_persist"], "resume on relaunch from last completed shot"),
        "PREPARING_FLAT|disk_full": ("PREP_BLOCKED", ["act_prepare_pause", "act_badge(3D prep paused: disk full)"], ""),
        "PREPARING_FLAT|playhead_covered": ("READY_STEREO", ["act_play_stereo", "act_badge_clear", "act_osd(3D on)"], ""),
        "PREPARING_FLAT|prepare_done": ("READY_STEREO", ["act_play_stereo", "act_badge_clear", "act_osd(3D on)"], "whole film prepared; playhead is covered by definition"),
        "PREPARING_FLAT|shot_error": ("PREPARING_FLAT", ["act_prepare_retry_shot"], "backoff retry, attempt < 3"),
        "PREPARING_FLAT|shot_error_limit": ("PREPARING_FLAT", ["act_mark_shot_failed", "act_menu_note(one scene plays in 2D)"], "failed shot's range stays uncovered -> flat there, stereo elsewhere"),
        "PREPARING_FLAT|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "PREPARING_FLAT|thermal_trip": ("PREP_BLOCKED", ["act_prepare_pause", "act_badge(3D prep paused: thermals)"], ""),
        "PREPARING_FLAT|user_disable_3d": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_prepare_abort", "act_badge_clear"], "menu toggle; 2D is instant (depth-input swap only)"),
        "PREP_BLOCKED|app_quit": ("INIT", ["act_persist"], ""),
        "PREP_BLOCKED|disk_freed": ("PREPARING_FLAT", ["act_prepare_resume", "act_badge_clear"], ""),
        "PREP_BLOCKED|playhead_covered": ("PREPARING_FLAT", ["act_badge_clear"], "coverage changed while blocked (external cache fill); resume decision waits for the unblocking event"),
        "PREP_BLOCKED|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "PREP_BLOCKED|thermal_clear": ("PREPARING_FLAT", ["act_prepare_resume", "act_badge_clear"], "auto-retry: prepare resumes when the gate clears"),
        "PREP_BLOCKED|user_disable_3d": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_prepare_abort", "act_badge_clear"], "menu toggle; 2D is instant (depth-input swap only)"),
        "READY_STEREO|app_quit": ("INIT", ["act_persist"], ""),
        "READY_STEREO|disk_freed": ("READY_STEREO", ["act_prepare_resume", "act_badge_clear"], ""),
        "READY_STEREO|disk_full": ("READY_STEREO", ["act_prepare_pause", "act_badge(3D prep paused: disk full)"], "playback continues 3D on the prepared range"),
        "READY_STEREO|playhead_uncovered": ("LGD_HOLD", ["act_hold_lgd"], "depth gap at playhead: hold last good depth up to 500 ms; pipeline untouched, a/v sync cannot break"),
        "READY_STEREO|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "READY_STEREO|thermal_clear": ("READY_STEREO", ["act_prepare_resume", "act_badge_clear"], "gate cleared while playing the prepared range: prepare resumes"),
        "READY_STEREO|thermal_trip": ("READY_STEREO", ["act_prepare_pause", "act_badge(3D prep paused: thermals)"], "playback continues 3D on the prepared range"),
        "READY_STEREO|user_disable_3d": ("UNAVAILABLE_FLAT", ["act_play_flat", "act_prepare_abort", "act_badge_clear"], "menu toggle; 2D is instant (depth-input swap only)"),
        "UNAVAILABLE_FLAT|kit_bad_hash": ("UNAVAILABLE_FLAT", ["act_reprobe"], "same or new refusal reason; note stays"),
        "UNAVAILABLE_FLAT|kit_missing": ("UNAVAILABLE_FLAT", ["act_reprobe"], "same or new refusal reason; note stays"),
        "UNAVAILABLE_FLAT|moge_licence_off": ("UNAVAILABLE_FLAT", ["act_reprobe"], "same or new refusal reason; note stays"),
        "UNAVAILABLE_FLAT|probe_ok": ("PREPARING_FLAT", ["act_reprobe", "act_play_flat", "act_prepare_start", "act_badge(3D preparing)"], "condition cleared (kit installed / licence accepted / new source)"),
        "UNAVAILABLE_FLAT|refuse_hdr": ("UNAVAILABLE_FLAT", ["act_reprobe"], "same or new refusal reason; note stays"),
        "UNAVAILABLE_FLAT|refuse_vfr": ("UNAVAILABLE_FLAT", ["act_reprobe"], "same or new refusal reason; note stays"),
        "UNAVAILABLE_FLAT|source_changed": ("INIT", ["act_prepare_abort", "act_reprobe"], "new source: all prepare/playback state re-derived; playback of the new file starts flat, never waits"),
        "UNAVAILABLE_FLAT|user_disable_3d": ("UNAVAILABLE_FLAT", [], "already off"),
        "UNAVAILABLE_FLAT|user_enable_3d": ("INIT", ["act_reprobe"], "menu toggle back on: full re-probe"),
    ]
}
// END relocated ThreeDDegradeTable.swift
// END relocated ThreeDDegrade.swift
// BEGIN relocated VRMirrorThrottle.swift (195y owner-order 3D consolidation, behavior unchanged)
import AppKit
import Foundation
import QuartzCore

/// Decides when a VR right-eye control mirror must be re-rendered (cacheDisplay of a live AppKit view is the
/// expensive part: CATextLayer typesetting on the main thread, ten times a second per visible control).
/// A mirror is re-rendered when its content stamp changed, when the user is interacting, when the source
/// behind this mirror slot changed, or at the latest every `heartbeat` seconds. Pixels of the mirror are
/// always rendered by the same cacheDisplay call as before; only unchanged repeats are skipped.
///
/// Idle cost model (3 visible controls, 10 Hz timer): before 30 renders/s, now about 6/s (heartbeat 2/s per slot).
/// During interaction (`noteInteraction`, held 1.5 s) every tick renders, so hover and drag stay as live as before.
/// The Python model Tests/VRCost/vr_cost_model_test.py replays this exact decision rule.
struct VRMirrorThrottle {
    /// Idle re-render cap per mirror slot. Under thermal pressure the cap
    /// stretches 0.5s -> 2s (owner 2026-11-15, 95 C report): interaction and
    /// content-stamp changes still render on the very next tick, only the
    /// forced idle repaint slows.
    static var heartbeat: TimeInterval { HeatTelemetry.thermalPressure ? 2.0 : 0.5 }
    static let interactionHold: TimeInterval = 1.5
    private var last: [Int: (id: ObjectIdentifier, stamp: Int, at: TimeInterval)] = [:]
    private(set) var interactiveUntil: TimeInterval = 0
    private(set) var skipped = 0
    private(set) var rendered = 0

    mutating func noteInteraction(now: TimeInterval) { interactiveUntil = now + Self.interactionHold }

    mutating func shouldRender(slot: Int, id: ObjectIdentifier, stamp: Int, hasContents: Bool, now: TimeInterval) -> Bool {
        let prior = last[slot]
        let due = !hasContents || prior == nil || prior!.id != id || prior!.stamp != stamp
            || now < interactiveUntil || now - prior!.at >= Self.heartbeat
        if due { last[slot] = (id, stamp, now); rendered += 1 } else { skipped += 1 }
        return due
    }

    mutating func reset() { last.removeAll(); skipped = 0; rendered = 0 }
}

/// Cheap content signature of a control view tree (geometry, text, colours, image identity). Not a pixel hash:
/// anything it misses is caught by the 0.5 s heartbeat and by the interaction hold in VRMirrorThrottle.
enum VRMirrorStamp {
    static func of(_ view: NSView) -> Int {
        var h = Hasher()
        func layerStamp(_ l: CALayer, _ depth: Int) {
            h.combine(l.bounds.size.width); h.combine(l.bounds.size.height)
            h.combine(l.position.x); h.combine(l.position.y)
            h.combine(l.opacity); h.combine(l.isHidden)
            if let c = l.backgroundColor { h.combine(c.hashValue) }
            if let c = l.contents { h.combine(ObjectIdentifier(c as AnyObject)) }
            if let t = l as? CATextLayer {
                if let s = t.string as? String { h.combine(s) }
                else if let a = t.string as? NSAttributedString { h.combine(a.string) }
                if let c = t.foregroundColor { h.combine(c.hashValue) }
            }
            if let sh = l as? CAShapeLayer, let p = sh.path { h.combine(p.boundingBoxOfPath.width) }
            if depth < 12, let subs = l.sublayers { for s in subs { layerStamp(s, depth + 1) } }
        }
        func viewStamp(_ v: NSView, _ depth: Int) {
            h.combine(v.frame.origin.x); h.combine(v.frame.origin.y)
            h.combine(v.frame.size.width); h.combine(v.frame.size.height)
            h.combine(v.isHidden); h.combine(v.alphaValue)
            if let c = v as? NSControl { h.combine(c.stringValue); h.combine(c.doubleValue) }
            if let l = v.layer { layerStamp(l, 0) }
            if depth < 12 { for s in v.subviews { viewStamp(s, depth + 1) } }
        }
        viewStamp(view, 0)
        return h.finalize()
    }
}

// Counters `skipped` and `rendered` are for diagnostics and tests only; they never gate behaviour.
// Slots are mirror layer indices: when the source behind a slot changes identity the slot renders at once.
// Nothing here touches video, shaders or mpv: it only decides when UI chrome pixels are redrawn.
// A hidden or fully transparent source is handled by the caller (its mirror stays hidden) before this runs.
//
// Why a heartbeat and not pure change detection: the stamp reads geometry, text, colours and image identity of the
// layer tree, which covers every control the mirror shows today. A control that redraws through a path the stamp does
// not read (custom drawRect with the same geometry) still refreshes within 0.5 s, and at once while the pointer is used.
// Tuning: raise `heartbeat` for less CPU, lower it for faster pickup of unstamped changes. Interaction hold covers drags.
// The mirror is the VR right-eye copy of the on-screen controls; the left-eye originals are never throttled here.
// If the decision ever looks wrong in the field, `reset()` forces the next tick to render every slot.
// (slot reset: see reset())
// (slot reset: see reset())
// (slot reset: see reset())
// (slot reset: see reset())
// (slot reset: see reset())

// MARK: - Main-thread load governor (2026-11-08 VR heat)
//
// Evidence (sample of a hot 8K60 HEVC VR session, 1971 ms): main thread 1971/1971 samples busy, 1596 of them inside
// CA::Transaction::commit, 1419 in -[CATextLayer drawInContext:] (typesetting 1281). Every audio-driven variable-font
// change re-typesets every visible CATextLayer, and the 60 Hz VariationBroadcaster timer only slowed down because the
// main run loop was saturated (14.6 ticks/s, 12 fan-outs/s over 141 listeners in the log).
// FanoutGovernor keeps the fan-out exactly as before while the main loop has headroom (gap 0 below `loadFloor`),
// and only when the loop is busy spaces AUDIO-ONLY fan-outs apart (at most 1/maxGap per second at saturation).
// Pointer-driven fan-outs (mouse moved) are never delayed, so hover/drag feel and the idle-light-load look are unchanged.
// DEFAULT OFF (owner: zero feature loss; it spaces audio-driven text updates under load). Opt in: `defaults write <bundle id> gorHeatGovernor -bool YES`.
struct FanoutGovernor {
    static let loadFloor = 0.45
    static let loadCeil = 0.90
    static let maxGap: TimeInterval = 0.125
    private(set) var lastFanout: TimeInterval = 0
    private(set) var governed = 0
    static func gap(load: Double) -> TimeInterval {
        let k = min(1, max(0, (load - loadFloor) / (loadCeil - loadFloor)))
        return k * maxGap
    }
    mutating func allow(now: TimeInterval, audioOnly: Bool, load: Double) -> Bool {
        if !audioOnly || now - lastFanout >= Self.gap(load: load) { lastFanout = now; return true }
        governed += 1
        return false
    }
}


/// Audio-only variable-font fan-out gate. The 60 Hz broadcaster tick can
/// carry a slightly different smoothAudio every tick; only a change in the
/// same quantized bucket used by PhotonFont's font cache can change a driven
/// font, and bucket changes are coalesced to 8 Hz so CATextLayer typesetting
/// cannot share every video-frame commit. Pointer-driven fan-outs bypass this
/// gate and call noteFanout so they also absorb the latest audio bucket.
struct AudioFanoutCoalescer {
    static let minGap: TimeInterval = 0.125
    private(set) var lastBucket: Int?
    private(set) var lastFanout: TimeInterval = 0
    private(set) var sameBucketSkips = 0
    private(set) var coalesced = 0

    static func quantizedBucket(_ smoothAudio: Double) -> Int {
        Int((smoothAudio * PhotonFont.CacheQuantizationSteps).rounded())
    }

    func hasBucketChange(_ smoothAudio: Double) -> Bool {
        Self.quantizedBucket(smoothAudio) != lastBucket
    }

    mutating func allow(now: TimeInterval, smoothAudio: Double) -> Bool {
        let bucket = Self.quantizedBucket(smoothAudio)
        guard bucket != lastBucket else { sameBucketSkips &+= 1; return false }
        guard now - lastFanout >= Self.minGap else { coalesced &+= 1; return false }
        lastBucket = bucket
        lastFanout = now
        return true
    }

    mutating func noteFanout(now: TimeInterval, smoothAudio: Double) {
        lastBucket = Self.quantizedBucket(smoothAudio)
        lastFanout = now
    }
}

/// Fraction of wall time the main run loop spends awake (afterWaiting .. beforeWaiting), smoothed over ~0.5 s.
/// Cheap: two observer callbacks per loop turn, no allocation.
final class MainLoopLoad {
    static let shared = MainLoopLoad()
    private(set) var load = 0.0
    private var awakeAt: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var busy: CFTimeInterval = 0
    private var observer: CFRunLoopObserver?
    func start() {
        guard Thread.isMainThread, observer == nil else { return }
        let acts = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, acts, true, Int.max) { [weak self] _, act in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if act == .afterWaiting { self.awakeAt = now; if self.windowStart == 0 { self.windowStart = now }; return }
            if self.awakeAt > 0 { self.busy += now - self.awakeAt; self.awakeAt = 0 }
            let span = now - self.windowStart
            if span >= 0.5 { self.load = min(1, self.busy / span); self.busy = 0; self.windowStart = now }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

enum HeatTelemetry {
    // Default ON (owner 2026-11-15, 95 C report): the governor only throttles
    // audio-only font fan-outs once MainLoopLoad passes 0.45, so a cool or
    // idle machine behaves exactly as before; gorHeatGovernor=false still
    // forces it off.
    static var governorEnabled: Bool { UserDefaults.standard.object(forKey: "gorHeatGovernor") as? Bool ?? true }
    /// True while the system reports serious/critical thermal pressure. One
    /// cheap syscall per read; callers are 0.5-10 Hz timers, never per-frame.
    static var thermalPressure: Bool { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
    private static var last: (wall: CFTimeInterval, cpu: Double)?
    /// Head-tracker Vision frame interval: owner knob `gorHeadTrackFPS` (10...60), unset = 30 fps = unchanged.
    /// Under thermal pressure (owner 2026-11-15, 95 C report) the admission floor is 10 fps: the pose pipeline
    /// keeps tracking, the Vision face-request rate drops by up to 3x. A cool machine is byte-identical.
    static var headTrackInterval: CFTimeInterval {
        let base = 1.0 / min(60, max(10, UserDefaults.standard.object(forKey: "gorHeadTrackFPS") as? Double ?? 30))
        return thermalPressureCached ? max(base, 0.1) : base
    }
    /// thermalPressure is documented "callers are 0.5-10 Hz timers, never per-frame"; the camera admission path
    /// reads the interval per captured frame, so it goes through this 1 s cache (thermal state moves far slower
    /// than a second). The lock keeps the off-main capture callback from racing the tuple write.
    private static let thermalCacheLock = NSLock()
    private static var thermalCache: (at: CFTimeInterval, value: Bool) = (0, false)
    static var thermalPressureCached: Bool {
        thermalCacheLock.lock(); defer { thermalCacheLock.unlock() }
        let now = CACurrentMediaTime()
        if now - thermalCache.at >= 1 { thermalCache = (now, thermalPressure) }
        return thermalCache.value
    }
    /// Vision face requests issued (diagnostic only, read by the [heat] line).
    static var visionFrames = 0
    // Main-thread only (PhotonFont.setIfChanged is UI code; the [VB] timer reads it on main); asserted in debug builds.
    private static var fontSites: [Int: (name: String, changed: Int, same: Int)] = [:]
    /// Per call-site tally of PhotonFont.setIfChanged: `changed` = a new font was applied (CATextLayer re-typesets), `same` = skipped.
    /// Key = literal address of the #fileID StaticString and the line: no String work on the hot path, the name is built once per site.
    static func noteFont(changed: Bool, _ file: StaticString, _ line: Int) {
        assert(Thread.isMainThread, "HeatTelemetry font tally is main-thread only")
        let k = Int(bitPattern: file.utf8Start) &* 1_000_003 &+ line
        if fontSites[k] == nil { fontSites[k] = ("\(String(describing: file).split(separator: "/").last ?? ""):\(line)", 0, 0) }
        if changed { fontSites[k]!.changed &+= 1 } else { fontSites[k]!.same &+= 1 }
    }
    /// "site=changed/same" for the four sites that re-typeset most since the last call; resets the tally.
    static func fontSiteSummary() -> String {
        assert(Thread.isMainThread, "HeatTelemetry font tally is main-thread only")
        let top = fontSites.values.sorted { $0.changed > $1.changed }.prefix(4).map { "\($0.name)=\($0.changed)/\($0.same)" }
        for k in fontSites.keys { fontSites[k] = (fontSites[k]!.name, 0, 0) }
        return top.joined(separator: ",")
    }
    private static var mpvLast: (pid: Int32, wall: CFTimeInterval, ns: Double)?
    /// mpv child CPU in percent of one core since the previous call ("n/a" when there is no live mpv). Main thread only.
    static func mpvCPUPercent() -> String {
        guard let proc = (NSApp.delegate as? AppDelegate)?.mpvProcess, proc.isRunning else { mpvLast = nil; return "n/a" }
        let pid = proc.processIdentifier
        var ri = rusage_info_current()
        let rc = withUnsafeMutablePointer(to: &ri) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
        }
        guard rc == 0 else { return "n/a" }
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        let ns = Double(ri.ri_user_time &+ ri.ri_system_time) * Double(tb.numer) / Double(tb.denom)
        let wall = CACurrentMediaTime()
        defer { mpvLast = (pid, wall, ns) }
        guard let l = mpvLast, l.pid == pid, wall > l.wall else { return "n/a" }
        let elapsedCPU: Double = (ns - l.ns) / 1e9
        let elapsedWall: Double = wall - l.wall
        let percent: Double = elapsedCPU / elapsedWall * 100
        return String(format: "%.0f", percent)
    }
    /// Whole-process CPU in percent of one core since the previous call (user+system via getrusage).
    static func processCPUPercent() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        let cpu = Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        let wall = CACurrentMediaTime()
        defer { last = (wall, cpu) }
        guard let l = last, wall > l.wall else { return 0 }
        return (cpu - l.cpu) / (wall - l.wall) * 100
    }
}

/// Shadow equivalence meter (log only, changes no value). Each observe() returns its input unchanged and compares it with
/// the previous value of the same site when that one is at most `ttl` seconds old: pairs = comparisons made, mismatch =
/// the cached value would have been wrong. A skip or cache is only worth turning on when mismatch stays 0 over many
/// pairs on the real machine. count() is a plain tick counter (calls). Thread-safe; drained into the 10 s playback-cost line.
enum HeatShadow {
    private struct Site { var calls = 0, pairs = 0, mismatch = 0, last: Int64 = 0, at: TimeInterval = -1e9 }
    private static let lock = NSLock()
    private static var sites: [String: Site] = [:]

    @discardableResult static func observe(_ name: String, bits: Int64, ttl: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        var s = sites[name] ?? Site()
        s.calls += 1
        let paired = now - s.at <= ttl
        if paired { s.pairs += 1; if s.last != bits { s.mismatch += 1 } }
        s.last = bits; s.at = now; sites[name] = s
        return paired
    }
    static func observeBool(_ name: String, _ value: Bool, ttl: TimeInterval) -> Bool { observe(name, bits: value ? 1 : 0, ttl: ttl); return value }
    static func observeFloat(_ name: String, _ value: Float, ttl: TimeInterval) -> Float { observe(name, bits: Int64(value.bitPattern), ttl: ttl); return value }
    static func count(_ name: String) { lock.lock(); sites[name, default: Site()].calls += 1; lock.unlock() }

    /// "shadow_<site>_calls=N shadow_<site>_pairs=N shadow_<site>_mismatch=N ..." for the window, then resets the counters.
    static func drain() -> String {
        lock.lock(); defer { lock.unlock() }
        var parts: [String] = []
        for name in sites.keys.sorted() {
            guard var s = sites[name], s.calls > 0 else { continue }
            parts.append("shadow_\(name)_calls=\(s.calls) shadow_\(name)_pairs=\(s.pairs) shadow_\(name)_mismatch=\(s.mismatch)")
            s.calls = 0; s.pairs = 0; s.mismatch = 0; sites[name] = s
        }
        return parts.joined(separator: " ")
    }
}
// END relocated VRMirrorThrottle.swift
// BEGIN relocated ThreeDMenu.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AppKit)
import AppKit

/// 191b B4: ONE "3d" menu - short labels, the state always visible, every row a store dispatch. The menu NEVER writes defaults,
/// never calls setVRModeEnabled/publishProjection/select3DOutput, and reads the store only in validateMenuItem (B1). Rows and key
/// equivalents come from ThreeDKeymap.rows (B5: one table for menu + keyboard). Numeric submenus and the Cmd+Ctrl+Opt source
/// shortcuts are gone; depth/screen/size are live steps with an OSD value (the owner tunes by eye, never numbers).
/// Quality rows: Auto always; Best/Fast only when this build has a learned runner (B4: unbuilt tiers are HIDDEN, not labelled).
/// Store API (E-G, relayed 22:11): ThreeDStore.shared.snapshot/.dispatch/.subscribe;
/// ThreeDEffectValue = .bool/.number/.text; steps READ the number, add the step, dispatch. ThreeDSource(_ format:, swap:).
@MainActor final class ThreeDMenu: NSObject, NSMenuItemValidation, NSMenuDelegate {
    static let shared = ThreeDMenu()
    private(set) var installedMenu: NSMenu?
    /// Read-only display hook wired by ThreeDWiring (never a store write): the detected source label for the "Auto" row.
    var detectedSource: () -> String = { "unknown" }
    /// Subtitle depth is a subtitle render offset, not 3D output state (not in B1's effect list): the only non-store dispatch.
    var subtitleDepth: (Double) -> Void = { _ in }

    /// 21:28/Main 22:17: the calibration crosshair is the AppKit "+" marker (ThreeDCornerTuneView),
    /// not the retired green shader mark. Wired by ThreeDWiring.
    var calibrationMarker: (Bool) -> Void = { _ in }
    private var calibrationOn=false

    // MARK: - live steps (B4: tune by eye; defaults from E-G: strength 1, screenDepth 1.5, screenSize 75, ipd 0)
    static let strengthStep = 0.25, strengthRange = 0.0...2.0          // the old 0/50/75/100/125/150/200% grid
    static let screenDepthFactor = 1.5, screenDepthRange = 0.25...8.0  // covers the old 0.5/1/2/4 m choices
    static let screenSizeStep = 5.0, screenSizeRange = 20.0...150.0    // degrees; old choices were 50/60/90/110/75
    static let ipdStep = VR180Controller.baseIPDStep * VR180Controller.ndcToMM, ipdRange = (-VR180Controller.baseIPDLimit * VR180Controller.ndcToMM)...(VR180Controller.baseIPDLimit * VR180Controller.ndcToMM)  // the app's existing IPD step (0.02), +/-10 steps

    /// Local accessors over E-G's ThreeDEffectValue (.bool/.number/.text).
    private static func num(_ v: ThreeDEffectValue?) -> Double? { if case .number(let n) = v { return n }; return nil }
    private static func boolOf(_ v: ThreeDEffectValue?) -> Bool { if case .bool(let b) = v { return b }; return false }
    private static func text(_ v: ThreeDEffectValue?) -> String { if case .text(let t) = v { return t }; return "" }
    private static func stepped(_ key: ThreeDEffectKey, _ delta: Double, _ range: ClosedRange<Double>, _ store: ThreeDStore) -> ThreeDEffectValue {
        .number(min(max((num(store.snapshot.effects[key]) ?? 0) + delta, range.lowerBound), range.upperBound))
    }
    private static func scaled(_ key: ThreeDEffectKey, _ factor: Double, _ range: ClosedRange<Double>, _ store: ThreeDStore, _ fallback: Double) -> ThreeDEffectValue {
        .number(min(max((num(store.snapshot.effects[key]) ?? fallback) * factor, range.lowerBound), range.upperBound))
    }

    // MARK: - store dispatch (the ONLY place ThreeDKeymap.Act becomes a ThreeDAction; menu rows AND the keyboard path use it, B1)
    static func dispatch(_ act: ThreeDKeymap.Act) {
        let store = ThreeDStore.shared
        switch act {
        case .toggle3D:      store.dispatch(.toggle3D)
        case .viewOff:       store.dispatch(.setOutput(.off))
        case .viewSBS:       store.dispatch(.setOutput(.sbs))
        case .viewHalfSBS:   store.dispatch(.setOutput(.halfSBS))
        case .viewTB:        store.dispatch(.setOutput(.tb))
        case .viewVR180:
            // B4: Shift+V means View VR180, and toggles back to Off if already VR180.
            store.dispatch(.setOutput(store.snapshot.current.output == .vr180 ? .off : .vr180))
        case .viewAnaglyph:  store.dispatch(.setOutput(.anaglyph))
        case .filmAuto:      store.dispatch(.setSource(ThreeDSource(.auto)))
        case .film2D:        store.dispatch(.setSource(ThreeDSource(.flat2D)))
        case .filmSBS:       store.dispatch(.setSource(ThreeDSource(.sbsFull)))
        case .filmHalfSBS:   store.dispatch(.setSource(ThreeDSource(.sbsHalf)))
        case .filmTB:        store.dispatch(.setSource(ThreeDSource(.tbFull)))
        case .filmHalfTB:    store.dispatch(.setSource(ThreeDSource(.tbHalf)))
        case .filmVR180SBS:  store.dispatch(.setSource(ThreeDSource(.vr180SBS)))
        case .filmVR180TB:   store.dispatch(.setSource(ThreeDSource(.vr180TB)))
        case .film360:       store.dispatch(.setSource(ThreeDSource(.vr360Mono)))
        case .film360TB:     store.dispatch(.setSource(ThreeDSource(.vr360TB)))
        case .filmSwapEyes:
            let cur = store.snapshot.current.source
            store.dispatch(.setSource(ThreeDSource(cur.format, swap: !cur.swap)))
        case .cycleSource:   store.dispatch(.cycleSource)
        case .depthStronger: store.dispatch(.setEffect(.strength, stepped(.strength, +strengthStep, strengthRange, store)))
        case .depthWeaker:   store.dispatch(.setEffect(.strength, stepped(.strength, -strengthStep, strengthRange, store)))
        case .screenNearer:  store.dispatch(.setEffect(.screenDepth, scaled(.screenDepth, 1.0 / screenDepthFactor, screenDepthRange, store, 1.5)))
        case .screenFarther: store.dispatch(.setEffect(.screenDepth, scaled(.screenDepth, screenDepthFactor, screenDepthRange, store, 1.5)))
        case .sizeLarger:    store.dispatch(.setEffect(.screenSize, stepped(.screenSize, +screenSizeStep, screenSizeRange, store)))
        case .sizeSmaller:   store.dispatch(.setEffect(.screenSize, stepped(.screenSize, -screenSizeStep, screenSizeRange, store)))
        case .ipdPlus:       store.dispatch(.setEffect(.ipd, stepped(.ipd, +ipdStep, ipdRange, store)))
        case .ipdMinus:      store.dispatch(.setEffect(.ipd, stepped(.ipd, -ipdStep, ipdRange, store)))
        case .crossEye:      store.dispatch(.setEffect(.crossEye, .bool(!boolOf(store.snapshot.effects[.crossEye]))))
        case .headTracking:  store.dispatch(.setEffect(.head, .bool(!boolOf(store.snapshot.effects[.head]))))
        case .headInvert:    store.dispatch(.setEffect(.headInvert, .bool(!boolOf(store.snapshot.effects[.headInvert]))))
        case .blink:         store.dispatch(.setEffect(.blink, .bool(!boolOf(store.snapshot.effects[.blink]))))
        case .recenter:      store.dispatch(.resetView)
        case .calibration:   shared.calibrationOn.toggle();shared.calibrationMarker(shared.calibrationOn)
        case .surroundBlack: store.dispatch(.setEffect(.surround, .text("black")))
        case .surroundSoft:  store.dispatch(.setEffect(.surround, .text("soft")))
        case .surroundInvert: store.dispatch(.setEffect(.surroundInvert, .bool(!boolOf(store.snapshot.effects[.surroundInvert]))))
        case .qualityAuto:   store.dispatch(.setEffect(.quality, .text("auto")))
        case .qualityBest:   store.dispatch(.setEffect(.quality, .text("best")))
        case .qualityFast:   store.dispatch(.setEffect(.quality, .text("fast")))
        case .osdLine:       store.dispatch(.setEffect(.osdLine, .bool(!boolOf(store.snapshot.effects[.osdLine]))))
        case .subtitleDepthNearer: shared.subtitleDepth(-VR180Controller.subtitleDepthStep)
        case .subtitleDepthFarther: shared.subtitleDepth(+VR180Controller.subtitleDepthStep)
        }
    }

    // MARK: - install
    /// Builds the one "3d" submenu under `parent` (one call from AppDelegate; no extra headset menu - those rows are native now).
    func install(in parent: NSMenu) {
        let item = NSMenuItem(title: "3d", action: nil, keyEquivalent: "")
        let m = NSMenu(title: "3d"); item.submenu = m; m.delegate = self; parent.addItem(item); installedMenu = m
        // status line (B4): "3D: <Output> · <Source>", disabled, always current. A disabled item with a nil action is NOT
        // guaranteed a validateMenuItem call from AppKit, so the title is refreshed in menuNeedsUpdate (delegate below).
        let status = NSMenuItem(title: "3D: off", action: nil, keyEquivalent: ""); status.isEnabled = false; status.tag = -1; m.addItem(status)
        func row(_ act: ThreeDKeymap.Act, in menu: NSMenu = m) -> NSMenuItem {
            let r = ThreeDKeymap.rows.first { $0.act == act }!
            let i = NSMenuItem(title: r.title, action: #selector(rowTapped(_:)), keyEquivalent: r.chord?.key ?? "")
            if let c = r.chord {
                var mods: NSEvent.ModifierFlags = []
                if c.control { mods.insert(.control) }; if c.option { mods.insert(.option) }; if c.shift { mods.insert(.shift) }; if c.command { mods.insert(.command) }
                i.keyEquivalentModifierMask = mods
            }
            i.target = self; i.representedObject = act.rawValue; menu.addItem(i); return i
        }
        // B4 block layout: labelled sections (View / Film is / Depth / Screen / Size (VR180) / Eyes / Surround / Quality),
        // headers disabled; separators exactly where the block draws them (after 3D On/Off and after Film is).
        func header(_ title: String) { let h = NSMenuItem(title: title, action: nil, keyEquivalent: ""); h.isEnabled = false; h.tag = -2; m.addItem(h) }
        row(.toggle3D)
        m.addItem(.separator())
        header("View")
        for a in [ThreeDKeymap.Act.viewOff, .viewSBS, .viewHalfSBS, .viewTB, .viewVR180, .viewAnaglyph] { _ = row(a) }
        header("Film is")
        _ = row(.filmAuto)
        for a in [ThreeDKeymap.Act.film2D, .filmSBS, .filmHalfSBS, .filmTB, .filmHalfTB, .filmVR180SBS, .filmVR180TB, .film360, .film360TB, .filmSwapEyes, .cycleSource] { _ = row(a) }
        m.addItem(.separator())
        header("Depth")
        for a in [ThreeDKeymap.Act.depthStronger, .depthWeaker] { _ = row(a) }
        header("Screen")
        for a in [ThreeDKeymap.Act.screenNearer, .screenFarther] { _ = row(a) }
        header("Size (VR180)")
        for a in [ThreeDKeymap.Act.sizeLarger, .sizeSmaller] { _ = row(a) }
        header("Eyes")
        for a in [ThreeDKeymap.Act.ipdPlus, .ipdMinus, .crossEye] { _ = row(a) }
        for a in [ThreeDKeymap.Act.headTracking, .headInvert, .blink, .recenter, .calibration] { _ = row(a) }
        header("Surround")
        for a in [ThreeDKeymap.Act.surroundBlack, .surroundSoft, .surroundInvert] { _ = row(a) }
        header("Quality")
        // B4: quality rows for tiers this build cannot run are HIDDEN, not labelled. Auto always shows; Best/Fast appear once a
        // learned runner registers (the CoreML kit via ThreeDRunnerRegistry). validateMenuItem re-evaluates on every menu open.
        _ = row(.qualityAuto)
        _ = row(.qualityBest); _ = row(.qualityFast)
        _ = row(.osdLine)
        ThreeDExperimentMenu.shared.install(in:m)
    }

    /// The status line is a disabled item with a nil action: AppKit is not required to validate it, so refresh its title here
    /// (menuNeedsUpdate fires on every menu open, tracking and key-equivalent matching) instead of relying on validateMenuItem.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === installedMenu, let status = menu.items.first(where: { $0.tag == -1 }) else { return }
        status.title = Self.statusTitle()
    }
    static func statusTitle() -> String {
        let cur = ThreeDStore.shared.snapshot.current
        return "3D: " + ThreeDInfo.outputLabel(cur.output) + ThreeDInfo.separator + ThreeDInfo.sourceLabel(cur.source.format)
    }

    @objc func rowTapped(_ i: NSMenuItem) {
        guard let raw = i.representedObject as? String, let act = ThreeDKeymap.Act(rawValue: raw) else { return }
        Self.dispatch(act)
    }

    // MARK: - state display (validateMenuItem ONLY; B1)
    private func act(_ i: NSMenuItem) -> ThreeDKeymap.Act? { (i.representedObject as? String).flatMap(ThreeDKeymap.Act.init(rawValue:)) }
    private var outputMismatchKey=""
    func validateMenuItem(_ i: NSMenuItem) -> Bool {
        if i.tag == -1 {   // status line: "3D: <Output> · <Source>" (also refreshed in menuNeedsUpdate - see install)
            i.title = Self.statusTitle()
            return false
        }
        guard let a = act(i) else { return true }
        let s = ThreeDStore.shared.snapshot, cur = s.current
        switch a {
        case .calibration: i.state = calibrationOn ? .on:.off
        case .toggle3D: i.state = cur.output != .off ? .on : .off
        case .viewOff, .viewSBS, .viewHalfSBS, .viewTB, .viewVR180, .viewAnaglyph:
            let want: ThreeDOutput = [.viewOff: .off, .viewSBS: .sbs, .viewHalfSBS: .halfSBS, .viewTB: .tb, .viewVR180: .vr180, .viewAnaglyph: .anaglyph][a]!
            let applied=ThreeDStore.shared.appliedOutput ?? ThreeDPresentationPlan.make(state:s).output
            let key=cur.output.rawValue+":"+applied.rawValue
            if cur.output != applied && outputMismatchKey != key {outputMismatchKey=key;Diag.log("3D-MENU-MISMATCH requested=\(cur.output.rawValue) applied=\(applied.rawValue)")}
            if cur.output == applied {outputMismatchKey=""}
            i.state = applied == want ? .on : .off
        case .filmAuto:
            i.title = "Auto (" + detectedSource() + ")"; i.state = cur.source.format == .auto ? .on : .off
        case .film2D, .filmSBS, .filmHalfSBS, .filmTB, .filmHalfTB, .filmVR180SBS, .filmVR180TB, .film360, .film360TB:
            let want: ThreeDSource.Format = [.film2D: .flat2D, .filmSBS: .sbsFull, .filmHalfSBS: .sbsHalf, .filmTB: .tbFull, .filmHalfTB: .tbHalf, .filmVR180SBS: .vr180SBS, .filmVR180TB: .vr180TB, .film360: .vr360Mono, .film360TB: .vr360TB][a]!
            i.state = cur.source.format == want ? .on : .off
        case .filmSwapEyes: i.state = cur.source.swap ? .on : .off
        case .cycleSource, .recenter, .subtitleDepthNearer, .subtitleDepthFarther: i.state = .off
        case .depthStronger, .depthWeaker:
            i.title = ThreeDKeymap.rows.first { $0.act == a }!.title + " (" + Self.fmt(Self.num(s.effects[.strength]) ?? 1, "×") + ")"; i.state = .off
        case .screenNearer, .screenFarther:
            i.title = ThreeDKeymap.rows.first { $0.act == a }!.title + " (" + Self.fmt(Self.num(s.effects[.screenDepth]) ?? 1.5, " m") + ")"; i.state = .off
        case .sizeLarger, .sizeSmaller:
            i.title = ThreeDKeymap.rows.first { $0.act == a }!.title + " (" + Self.fmt(Self.num(s.effects[.screenSize]) ?? 75, "°") + ")"; i.state = .off
        case .ipdPlus, .ipdMinus:
            i.title = ThreeDKeymap.rows.first {$0.act == a}!.title + " (" + Self.fmt(Self.num(s.effects[.ipd]) ?? 0, " mm") + ")";i.state = .off
        case .crossEye: i.state = Self.boolOf(s.effects[.crossEye]) ? .on : .off
        case .headTracking: i.state = Self.boolOf(s.effects[.head]) ? .on : .off
        case .headInvert: i.state = Self.boolOf(s.effects[.headInvert]) ? .on : .off
        case .blink: i.state = Self.boolOf(s.effects[.blink]) ? .on : .off
        case .osdLine: i.state = Self.boolOf(s.effects[.osdLine]) ? .on : .off
        case .surroundBlack: i.state = Self.text(s.effects[.surround]) == "black" ? .on : .off
        case .surroundSoft: i.state = Self.text(s.effects[.surround]) == "soft" ? .on : .off
        case .surroundInvert: i.state = Self.boolOf(s.effects[.surroundInvert]) ? .on : .off
        case .qualityAuto: let q = Self.text(s.effects[.quality]); i.state = (q.isEmpty || q == "auto") ? .on : .off
        case .qualityBest, .qualityFast:
            i.isHidden = ThreeDRunnerRegistry.runner == nil   // B4: unbuilt tiers are hidden, re-checked every menu open
            i.state = Self.text(s.effects[.quality]) == (a == .qualityBest ? "best" : "fast") ? .on : .off
        }
        return true
    }
    private static func fmt(_ v: Double, _ unit: String) -> String {
        (v.rounded() == v ? String(Int(v)) : String(format: "%.2f", v)) + unit
    }
}
#endif
// END relocated ThreeDMenu.swift
// BEGIN relocated ThreeDExperimentMenu.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// In-memory experiments. Never changes owner defaults or the launch environment.
struct ThreeDExperimentState: Equatable {
    var budgetOn = false
    var convergence = 0.0
    var compression = 0.35
    /// Affine disparity gain: a sloped preview plane stays a plane, not a curved sheet.
    mutating func useDepthPreset() { convergence = 0; compression = 0.35 }
    mutating func stepConvergence(_ delta: Double) { convergence = max(-0.5,min(0.5,convergence+delta)) }
    mutating func stepCompression(_ delta: Double) { compression = max(0,min(1,compression+delta)) }
    var budgetMessage: String {
        "on=\(budgetOn ? "yes":"no") conv=\(convergence) comp=\(compression)"
    }
    var budgetCommand: String {
        let value: [String: Any] = ["command":["script-message-to","vr180_look","gor3d-budget",budgetMessage]]
        return String(data:try! JSONSerialization.data(withJSONObject:value),encoding:.utf8)!
    }
}

#if canImport(AppKit)
import AppKit
@MainActor final class ThreeDExperimentMenu: NSObject, NSMenuItemValidation {
    static let shared = ThreeDExperimentMenu()
    /// One-shot guard for the launch-time master default (owner order 2026-11-15):
    /// installThreeDSourceResolution runs on every player wiring; the default ON
    /// applies once and never re-fires over a manual toggle.
    static var launchMasterApplied = false
    private(set) var state = ThreeDExperimentState()
    var send: (String) -> Void = { _ in }
    /// 195h r2-7: fired after an experiment row toggles; ThreeDWiring points it at the coordinator's existing re-render/re-prepare refresh.
    var onExperimentChange: () -> Void = {}
    private var captionsOn = false
    private var allOn: Bool {
        let s = Stereo3DExperiments.snapshot()
        return state.budgetOn && captionsOn && s.fw && s.dof && s.hg && DepthTemporalEMA.isEnabled()
            && DepthModelID.selected() == .dav2_small_coreml && ModelDepthEMA.enabled && s.deep
    }
    /// One action, one D command, one render invalidation. No per-row toggle chain or transient prepare jobs.
    func setAll(_ on: Bool) {
        state.budgetOn = on
        if on { state.useDepthPreset() }
        captionsOn = on; ThreeDSubtitleDepth.setExperimental(on)
        Stereo3DExperiments.setAll(on)
        DepthTemporalEMA.setEnabled(on)
        DepthModelID.select(on ? .dav2_small_coreml : .luma_y_prior)
        ModelDepthEMA.setEnabled(on)
        send(state.budgetCommand)
        onExperimentChange()
        receipt("master")
        let text = on ? "3D experiments ON requested; depth effects need a prepared shot" : "3D experiments OFF: returning to baseline"
        let body: [String: Any] = ["command": ["show-text", text, 4000]]
        if let d = try? JSONSerialization.data(withJSONObject: body), let j = String(data:d,encoding:.utf8) { send(j) }
    }
    private func receipt(_ reason: String) {
        let o = ThreeDExperimentOptions.live
        print("3D-EXPERIMENT requested reason=\(reason) D=\(state.budgetOn) F=\(captionsOn) options=\(o.renderKeyComponent ?? "off") conv=\(state.convergence) comp=\(state.compression) dofOverridden=\(o.deepVolume && o.depthOfField) evidence=request_only prepared_effects=await_render_load")
        fflush(stdout)
    }
    func reapplyIfEnabled() { if state.budgetOn { send(state.budgetCommand) } }
    func install(in parent: NSMenu) {
        let item=NSMenuItem(title:"Experiments (default on)",action:nil,keyEquivalent:"")
        let menu=NSMenu(title:item.title);item.submenu=menu;parent.addItem(item)
        let master=NSMenuItem(title:"All experiments on/off",action:#selector(tap(_:)),keyEquivalent:"e")
        master.keyEquivalentModifierMask=[.command,.control,.option];master.target=self;master.tag=100;menu.addItem(master)
        menu.addItem(.separator())
        for (tag,title) in [(1,"D disparity budget"),(2,"D convergence nearer"),(3,"D convergence farther"),(4,"D compression more"),(5,"D compression less"),(6,"F prepared subtitle depth"),(7,"E floating window"),(8,"G depth defocus (Held-Banks)"),(9,"hole-fill gradient (deterministic)"),(10,"B depth range EMA"),(11,"A depth model: DAV2 CoreML (needs models fetch)"),(12,"A DAV2 temporal EMA"),(13,"Deeper volume")] {
            let row=NSMenuItem(title:title,action:#selector(tap(_:)),keyEquivalent:"")
            row.target=self;row.tag=tag;menu.addItem(row)
        }
    }
    @objc func tap(_ row:NSMenuItem) {
        if row.tag == 100, NSApp.currentEvent?.isARepeat == true { return }
        switch row.tag {
        case 100: setAll(!allOn);return
        case 1: state.budgetOn.toggle()
        case 2: state.stepConvergence(-0.05)
        case 3: state.stepConvergence(0.05)
        case 4: state.stepCompression(0.05)
        case 5: state.stepCompression(-0.05)
        case 6:
            captionsOn.toggle();ThreeDSubtitleDepth.setExperimental(captionsOn);receipt("F");return
        case 7: Stereo3DExperiments.toggleFloatingWindow();onExperimentChange();receipt("row-\(row.tag)");return
        case 8: Stereo3DExperiments.toggleDepthOfField();onExperimentChange();receipt("row-\(row.tag)");return
        case 9: Stereo3DExperiments.toggleHoleFillGradient();onExperimentChange();receipt("row-\(row.tag)");return
        case 10: DepthTemporalEMA.toggleEnabled();onExperimentChange();receipt("row-\(row.tag)");return
        case 11: DepthModelID.select(DepthModelID.selected() == .dav2_small_coreml ? .luma_y_prior : .dav2_small_coreml);onExperimentChange();receipt("row-\(row.tag)");return   // 195h A: prepare identity carries the model, so both directions re-prepare through the container guard
        case 12: ModelDepthEMA.toggle();onExperimentChange();receipt("row-\(row.tag)");return
        case 13: Stereo3DExperiments.toggleDeepVolume();onExperimentChange();receipt("row-\(row.tag)");return
        default:return
        }
        send(state.budgetCommand)
        receipt("D")
    }
    func validateMenuItem(_ row:NSMenuItem)->Bool {
        switch row.tag {
        case 100:row.state=allOn ? .on:.off
        case 1:row.state=state.budgetOn ? .on:.off
        case 2,3:row.title=(row.tag==2 ? "D convergence nearer":"D convergence farther")+String(format:" (%.2f)",state.convergence)
        case 4,5:row.title=(row.tag==4 ? "D compression more":"D compression less")+String(format:" (%.2f)",state.compression)
        case 6:row.state=captionsOn ? .on:.off
        case 7:let s=Stereo3DExperiments.snapshot();row.state=s.fw ? .on:.off
        case 8:let s=Stereo3DExperiments.snapshot();row.state=s.dof ? .on:.off
        case 9:let s=Stereo3DExperiments.snapshot();row.state=s.hg ? .on:.off
        case 10:row.state=DepthTemporalEMA.isEnabled() ? .on:.off
        case 11:row.state=DepthModelID.selected() == .dav2_small_coreml ? .on:.off
        case 12:row.state=ModelDepthEMA.enabled ? .on:.off
        case 13:row.state=Stereo3DExperiments.snapshot().deep ? .on:.off
        default:break
        }
        return true
    }
}
#endif
// END relocated ThreeDExperimentMenu.swift
// BEGIN relocated ThreeDExperimentOptions.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 195h review fix (Delivery r1 items 3/4): one immutable snapshot of the 3D experiment switches, taken at job start. The Experiments menu
/// toggles the statics; render and prepare workers only ever read a snapshot, so a mid-job toggle can neither race a worker nor mix modes
/// inside one shot render or one depth container. All-off is the pre-195h behavior everywhere: keys, cache paths and output stay
/// byte-identical (renderKeyComponent is nil).
struct ThreeDExperimentOptions: Equatable {
    /// 195h A (Delivery: trace the boundary): the worker's parse of the launcher request's `experiments` string - ONE real function,
    /// compiled by production and the Linux driver, never an inline re-derivation.
    init(experiments: String) {
        let p = experiments.split(separator: ".")
        self.init(depthRangeEMA: p.contains("ema"), dav2Depth: p.contains("dav2"), dav2TemporalEMA: p.contains("tempema"))
    }
    /// Explicit memberwise (the custom init above suppresses the synthesized one); all defaults = the pre-195h all-off identity.
    init(floatingWindow: Bool = false, depthOfField: Bool = false, holeFillGradient: Bool = false, depthRangeEMA: Bool = false, dav2Depth: Bool = false, dav2TemporalEMA: Bool = false, deepVolume: Bool = false) {
        self.floatingWindow = floatingWindow; self.depthOfField = depthOfField; self.holeFillGradient = holeFillGradient
        self.depthRangeEMA = depthRangeEMA; self.dav2Depth = dav2Depth; self.dav2TemporalEMA = dav2TemporalEMA; self.deepVolume = deepVolume
    }
    var floatingWindow = false, depthOfField = false, holeFillGradient = false, depthRangeEMA = false
    var deepVolume = false
    var dav2Depth = false, dav2TemporalEMA = false   // 195h A: depth-model identity (DAV2-Small CoreML) + its temporal EMA
    /// render-key component: nil when every switch is off, so flag-off keys stay byte-identical with the pre-195h strings. Sorted, fixed order.
    var renderKeyComponent: String? {
        let on = [("fw", floatingWindow), ("dof", depthOfField), ("hg", holeFillGradient), ("ema", depthRangeEMA), ("dav2", dav2Depth), ("tempema", dav2TemporalEMA), ("deep2", deepVolume)].filter { $0.1 }.map { $0.0 }   // B's integrated order preserved byte-for-byte; A's tokens append after it
        return on.isEmpty ? nil : "exp-" + on.joined(separator: ".")
    }
    /// 195h r3 + Delivery 5: identity of the switches that change PREPARED depth (B today; item A adds the depth model). Render-only
    /// switches (E/G/hole) are absent: they re-render through the render key, never re-prepare. This is the launcher request's
    /// `experiments` value and the mismatch-nudge identity.
    /// 195h A (Delivery A-1): the DAV2 producer needs no VDA/MoGe kit - loadModels, the windowed probe and the kit gate all key off this.
    /// Override only the render snapshot. The selected row 8 state and key remain intact.
    var renderOptions: ThreeDExperimentOptions { var o = self; if deepVolume { o.depthOfField = false }; return o }
    var requiresVDAMoGeKit: Bool { !dav2Depth }
    var prepareComponent: String {
        let on = [("dav2", dav2Depth), ("ema", depthRangeEMA), ("tempema", dav2TemporalEMA)].filter { $0.1 }.map { $0.0 }   // 195h A: model+smoother folded in (Delivery: one identity, no parallel scheme)
        return on.joined(separator: ".")
    }
}
#if canImport(Metal)
extension ThreeDExperimentOptions {
    /// Current menu state as one snapshot. The ONLY read of the experiment statics outside the menu itself; callers pass the snapshot on.
    static var live: ThreeDExperimentOptions {
        let s = Stereo3DExperiments.snapshot()   // lock-backed; workers never read the raw statics (195h r2-3)
        return ThreeDExperimentOptions(floatingWindow: s.fw, depthOfField: s.dof, holeFillGradient: s.hg, depthRangeEMA: DepthTemporalEMA.isEnabled(),
                                           dav2Depth: DepthModelID.selected() == .dav2_small_coreml, dav2TemporalEMA: ModelDepthEMA.enabled, deepVolume: s.deep)   // lock-backed reads (195h r2-3)
    }
}
#endif
// END relocated ThreeDExperimentOptions.swift
// BEGIN relocated ThreeDKeymap.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 191b B4/B5: the ONE keymap table for 3D. It drives BOTH the menu key equivalents (ThreeDMenu.install) and the keyboard path
/// (InputController), so they can never diverge. Pure Foundation, no AppKit: modifiers are plain booleans, the AppKit side translates.
/// Linux-tested (Tests/ThreeDKeymap).
///
/// Collision audit (B5; input.conf + AppDelegate + InputController + MenuActions at 0d0f37b9):
/// - shift+X is photon sharp-up and option+X is photon sharp-down (input.conf, both non-3D): cross-eye KEEPS its existing ctrl+shift+X
///   (the B5 option-fallback is also taken; zero non-3D feature loss wins over the block's printed shift+X).
/// - option+shift+[/] was subtitle depth (InputController): B4 claims those chords for VR180 screen size, so subtitle depth moves to
///   ctrl+shift+[/] (free everywhere). Reported in `moves`.
/// - shift+V was the old single-switch toggle (InputController -> menuVRToggle): B4 makes it View VR180 / back-to-Off; same key, the
///   store now decides. shift+D stays 3D On/Off (was the quick toggle). Cmd+Ctrl+Opt+M/S/V (old source submenu) are REMOVED per B4.
/// Every other B4 chord was free (checked against input.conf, the AppDelegate menu table, and the InputController keyboard path).
enum ThreeDKeymap {

    /// A physical chord. `key` is the lowercased typed character; `keyCode` pins the PHYSICAL key where Shift/Option change the glyph
    /// (brackets: ANSI 30 = ']', 33 = '['). Matching uses exact modifier equality, then keyCode when set, else the character.
    struct Chord: Equatable {
        let key: String
        let shift: Bool
        let option: Bool
        let control: Bool
        let command: Bool
        let keyCode: Int?
        init(_ key: String, shift: Bool = false, option: Bool = false, control: Bool = false, command: Bool = false, keyCode: Int? = nil) {
            self.key = key; self.shift = shift; self.option = option; self.control = control; self.command = command; self.keyCode = keyCode
        }
        /// Menu-column display, macOS order: control, option, shift, command, key.
        var display: String {
            (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
        }
        func matches(charactersIgnoringModifiers chars: String?, keyCode: Int, shift: Bool, option: Bool, control: Bool, command: Bool) -> Bool {
            guard self.shift == shift, self.option == option, self.control == control, self.command == command else { return false }
            if let kc = self.keyCode { return kc == keyCode }
            return chars?.lowercased() == key
        }
    }

    /// Every 3D action the menu or keyboard can trigger. The store dispatch for each lives in ThreeDMenu.dispatch (one place).
    enum Act: String, CaseIterable {
        case toggle3D, viewOff, viewSBS, viewHalfSBS, viewTB, viewVR180, viewAnaglyph
        case filmAuto, film2D, filmSBS, filmHalfSBS, filmTB, filmHalfTB, filmVR180SBS, filmVR180TB, film360, film360TB, filmSwapEyes, cycleSource
        case depthStronger, depthWeaker, screenNearer, screenFarther, sizeLarger, sizeSmaller
        case ipdPlus, ipdMinus, crossEye
        case headTracking, headInvert, blink, recenter, calibration
        case surroundBlack, surroundSoft, surroundInvert
        case qualityAuto, qualityBest, qualityFast
        case osdLine
        case subtitleDepthNearer, subtitleDepthFarther    // no menu row (not in B4); keys kept for zero feature loss
    }

    struct Row: Equatable {
        let act: Act
        let chord: Chord?        // nil = no shortcut
        let title: String
    }

    /// The table. Menu order IS this order; validateMenuItem state and the keyboard matcher both read it.
    static let rows: [Row] = [
        Row(act: .toggle3D,      chord: Chord("d", shift: true),                    title: "3D On/Off"),
        Row(act: .viewOff,       chord: nil,                                        title: "Off"),
        Row(act: .viewSBS,       chord: Chord("s", shift: true),                    title: "SBS"),
        Row(act: .viewHalfSBS,   chord: nil,                                        title: "Half SBS"),
        Row(act: .viewTB,        chord: nil,                                        title: "Top/Bottom"),
        Row(act: .viewVR180,     chord: Chord("v", shift: true),                    title: "VR180"),
        Row(act: .viewAnaglyph,  chord: nil,                                        title: "Anaglyph"),
        Row(act: .filmAuto,      chord: nil,                                        title: "Auto"),
        Row(act: .film2D,        chord: nil,                                        title: "2D"),
        Row(act: .filmSBS,       chord: nil,                                        title: "SBS"),
        Row(act: .filmHalfSBS,   chord: nil,                                        title: "Half SBS"),
        Row(act: .filmTB,        chord: nil,                                        title: "Top/Bottom"),
        Row(act: .filmHalfTB,    chord: nil,                                        title: "Half T/B"),
        Row(act: .filmVR180SBS,  chord: nil,                                        title: "VR180 SBS"),
        Row(act: .filmVR180TB,   chord: nil,                                        title: "VR180 T/B"),
        Row(act: .film360,       chord: nil,                                        title: "360"),
        Row(act: .film360TB,     chord: nil,                                        title: "360 T/B"),
        Row(act: .filmSwapEyes,  chord: nil,                                        title: "Swap eyes"),
        Row(act: .cycleSource,   chord: Chord("f", shift: true),                    title: "Cycle film-is"),
        Row(act: .depthStronger, chord: Chord("=", shift: true),                    title: "stronger"),
        Row(act: .depthWeaker,   chord: Chord("-", shift: true),                    title: "weaker"),
        Row(act: .screenNearer,  chord: Chord("=", shift: true, option: true),      title: "nearer"),
        Row(act: .screenFarther, chord: Chord("-", shift: true, option: true),      title: "farther"),
        Row(act: .sizeLarger,    chord: Chord("]", shift: true, option: true, keyCode: 30), title: "larger"),
        Row(act: .sizeSmaller,   chord: Chord("[", shift: true, option: true, keyCode: 33), title: "smaller"),
        Row(act: .ipdPlus,       chord: Chord("]", shift: true, keyCode: 30),       title: "IPD +"),
        Row(act: .ipdMinus,      chord: Chord("[", shift: true, keyCode: 33),       title: "IPD −"),
        Row(act: .crossEye,      chord: Chord("x", shift: true, control: true),     title: "Cross-eye"),
        Row(act: .headTracking,  chord: Chord("h", shift: true),                    title: "Head tracking"),
        Row(act: .headInvert,    chord: nil,                                        title: "Invert head motion"),
        Row(act: .blink,         chord: Chord("e", shift: true),                    title: "Blink"),
        Row(act: .recenter,      chord: Chord("r", shift: true),                    title: "Recenter / full fit"),
        Row(act: .calibration,   chord: nil,                                       title: "Eye-centre crosshairs"),
        Row(act: .surroundBlack, chord: nil,                                        title: "Black"),
        Row(act: .surroundSoft,  chord: nil,                                        title: "Soft"),
        Row(act: .surroundInvert, chord: nil,                                       title: "Invert"),
        Row(act: .qualityAuto,   chord: nil,                                        title: "Auto"),
        Row(act: .qualityBest,   chord: nil,                                        title: "Best"),
        Row(act: .qualityFast,   chord: nil,                                        title: "Fast"),
        Row(act: .osdLine,       chord: nil,                                        title: "Show 3D info on screen"),
        Row(act: .subtitleDepthNearer, chord: Chord("[", shift: true, control: true, keyCode: 33), title: "subtitle depth nearer"),
        Row(act: .subtitleDepthFarther, chord: Chord("]", shift: true, control: true, keyCode: 30), title: "subtitle depth farther"),
    ]

    /// Keyboard path: the chord matching this event, if any. Exact modifier equality; keyCode beats the typed character.
    static func match(charactersIgnoringModifiers chars: String?, keyCode: Int, shift: Bool, option: Bool, control: Bool, command: Bool) -> Act? {
        rows.first { $0.chord?.matches(charactersIgnoringModifiers: chars, keyCode: keyCode, shift: shift, option: option, control: control, command: command) == true }?.act
    }

    /// B5 one-line move reports (surfaced in the commit message and the acceptance log).
    static let moves: [String] = [
        "cross-eye: stays ctrl+shift+X (shift+X = photon sharp-up, option+X = photon sharp-down; both non-3D, B5 keeps them)",
        "subtitle depth: option+shift+[/] -> ctrl+shift+[/] (B4 gives option+shift+[/] to VR180 screen size)",
        "view VR180: shift+V now means View VR180 / back to Off (was the single-switch toggle; the store owns the decision)",
        "removed: cmd+ctrl+opt+M/S/V (old source submenu shortcuts, B4)",
        "removed: numeric 3D submenus (strength %, screen depth m, screen size deg); live steps with OSD values replace them (B4)",
    ]
}

/// 191b B4: the one-line OSD every 3D change shows. Pure function, signature agreed with E-G (the store emits .showInfo; the applier
/// calls this builder and sends the OSD). Format per the block: "3D SBS · film 2D · converting 34%" / "3D off".
/// The owner tunes by eye and is never asked for numbers.
enum ThreeDInfo {
    static let separator = " · "
    static func outputLabel(_ o: ThreeDOutput) -> String {
        switch o {
        case .off: return "off"
        case .sbs: return "SBS"
        case .halfSBS: return "Half SBS"
        case .tb: return "Top/Bottom"
        case .vr180: return "VR180"
        case .anaglyph: return "Anaglyph"
        }
    }
    static func sourceLabel(_ f: ThreeDSource.Format) -> String {
        switch f {
        case .auto: return "auto"
        case .flat2D: return "2D"
        case .sbsFull: return "SBS"
        case .sbsHalf: return "Half SBS"
        case .tbFull: return "Top/Bottom"
        case .tbHalf: return "Half T/B"
        case .vr180SBS: return "VR180 SBS"
        case .vr180TB: return "VR180 T/B"
        case .vr360Mono: return "360"
        case .vr360TB: return "360 T/B"
        }
    }
    /// progress: 0...1 prepare progress while a conversion runs, nil otherwise.
    static func line(state: ThreeDState, progress: Double?) -> String {
        let cur = state.current
        if cur.output == .off { return "3D off" }
        var parts = ["3D " + outputLabel(cur.output), "film " + sourceLabel(cur.source.format)]
        if let p = progress { parts.append("converting " + String(Int((p * 100).rounded())) + "%") }
        return parts.joined(separator: separator)
    }
}
// END relocated ThreeDKeymap.swift
// BEGIN relocated ThreeDCornerTune.swift (195y owner-order 3D consolidation, behavior unchanged)
import AppKit

/// 191k: sidebar-V "3D" corner fine-tune overlay (owner order 00:53; reworked owner 17:33
/// phonemsg-01M72Y1GHHQT93RMMN87H3JZJZ: controls must click, subs removed, word in the corner, value
/// beside it, +/- diagonal inward; owner 21:28-21:29 phonemsg-01M73BG6BQ7DP7BGPR2FWA3TXP,
/// -01M73BH406Z70HP50CPE0AM8QN, -01M73BH6YT8MCB2K30PYDPAJAK: center crosshair in the UI font,
/// controls hide with the UI, never clipped, both eyes; owner 21:43
/// phonemsg-01M73CAZKZPD2MW75E9HM03G0S: window->fullscreen must not break placement, all gaps
/// equal, no re-render churn on clicks; 22:23-22:26 phonemsg-01M73EN9MK2FP8JX3EMDX9DGP5,
/// -01M73ES5GY2NGCM48D6W7GP1A5, -01M73ESDM65XZHT1E0ESN9KDWJ: match the target mockup's measured
/// columns/rows with mirrored corners and equal diagonal steps; 22:28
/// phonemsg-01M73EX09GEDHCQQ5V1YMJ5K8Y: titles are single letters with a spine-style typewriter
/// hover; owner 2026-11-12 12:40 phonemsg-01M77J3HXZ7YVVH77Y28CX426Q: pad x 2 grid in the layout
/// file, depth/size pinned at the right edge while the word types out leftward with no positional
/// shift, and the 3D dropdown row sits directly under V). Typographic cells in the UI font
/// (PhotonFont); each element gets its own layer and each glyph cell its own hit area. Every glyph
/// cell dispatches the SAME ThreeDMenu.dispatch act the 3d menu rows use, so behavior is identical
/// to the menu; toggles stay in the 3d menu. Layout math lives in ThreeDCornerTuneLayout.swift
/// (pure, Linux-measured by Tests/ThreeDCornerTune); this file only renders and forwards clicks.
/// Uncompiled, Mac-pending.
final class ThreeDCornerTuneView: NSView {
    static let shared = ThreeDCornerTuneView()

    /// Optional subtitle reservation in view coordinates (bottom-left origin). Unwired by default:
    /// subtitles render bottom-center and corner lines sit at the side pads, so they do not meet in
    /// practice; the layout shifts bottom lines above the band the moment a provider is attached.
    var subtitleBandProvider: (() -> CornerTuneRect?)?

    private let gazeCrosshair=GazeCrosshairController()
    private var controls: [CornerTuneControl] = []
    private var layers: [CATextLayer] = []
    private var valueLayers: [String: CATextLayer] = [:]
    /// Title layers keyed by full word, with their one-letter base frames: owner 22:28
    /// (phonemsg-01M73EX09GEDHCQQ5V1YMJ5K8Y) titles show as one letter and hover types the word.
    private var titleLayers: [String: (layer: CATextLayer, base: CornerTuneRect)] = [:]
    private var titleAreas: [NSTrackingArea] = []
    private var hoverWord: String?
    private var hoverTimer: Timer?
    private var hoverShown = 1
    private var placedFrame: CGRect = .zero
    private var lastChrome: CGRect = .zero

    private func chromeFrame(in rootView: NSView) -> CGRect {
        guard let pc = rootView as? PPController else { return rootView.bounds }
        if pc.controlChromeBounds != .zero { return pc.controlChromeBounds }
        return pc.visiblePictureBounds != .zero ? pc.visiblePictureBounds : rootView.bounds
    }

    func setChromeAlpha(_ alpha: CGFloat, duration: TimeInterval) {
        guard duration > 0 else { alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup {
            $0.duration = duration
            self.animator().alphaValue = alpha
        }
    }
    private var lastSignature = ""
    /// Menu calibration mode (owner 21:28: the menu-opened crosshair follows the same rules and is
    /// NOT green; Main 22:17 split: A-D owns it). The shader's green calibration_mark is retired;
    /// the marker is this same AppKit "+" cell - font-sized, hides with the UI, reacts to mouse and
    /// sound. calibrationOnly shows ONLY the crosshair; the full overlay wins while it is open.
    private var calibrationActive = false
    private var calibrationOnly = false
    private var refreshTimer: Timer?
    private var subscribed = false
    private var variationSubscribed = false

    private let store = ThreeDStore.shared

    private var cornerLayout: CornerTuneLayout {
        CornerTuneLayout(charW: Double(PhotonFont.chromeCharW), lineH: Double(PhotonFont.chromeLineH), pad: Double(PhotonFont.chromePad))
    }

    /// Acts keyed by corner word, far cell (second diagonal step) first, near cell second. For
    /// scr (owner 2026-11-12 13:47, phonemsg-01M77NX7459XYMH8W2B3VR9N01) the cells are "→" (near,
    /// screen farther: 8m -> 9.5m) then "←" (far, screen nearer).
    private static let acts: [String: (ThreeDKeymap.Act, ThreeDKeymap.Act)] = [
        "depth":  (.depthWeaker, .depthStronger),
        "ipd":    (.ipdMinus, .ipdPlus),
        "scr":    (.screenNearer, .screenFarther),
        "size":   (.sizeSmaller, .sizeLarger),
    ]

    private func rawValue(_ key: String) -> Double? {
        guard let k = ThreeDEffectKey(rawValue: key), let v = store.snapshot.effects[k],
              case .number(let n) = v else { return nil }
        return n
    }

    private func refresh() {
        // Ride the PPController chrome layout bounds: the cropped film frame in
        // 2D, letterboxed windows and SBS. In SBS the left band remains the source
        // and the mirror route carries it to the other eye.
        // Re-place only when that chrome rect changes; autoresizing and mirror depth shifts must not
        // move the controls or block the next placement.
        if let rootView = superview {
            let chromeBounds = chromeFrame(in: rootView)
            if chromeBounds != .zero, chromeBounds != lastChrome {
                lastChrome = chromeBounds
                frame = chromeBounds; placedFrame = frame
            }
        }
        let values = Dictionary(uniqueKeysWithValues: CornerTuneLayout.spec.map {
            ($0.key, CornerTuneLayout.format(key: $0.key, raw: rawValue($0.key)))
        })
        let full = CornerTuneRect(x: 0, y: 0, w: Double(bounds.width), h: Double(bounds.height))
        let chrome = (superview?.subviews ?? []).filter { $0 is SpineUI || $0 is SidebarUI }.map { view -> CornerTuneRect in
            let r=convert(view.bounds,from:view)
            return CornerTuneRect(x:Double(r.minX),y:Double(r.minY),w:Double(r.width),h:Double(r.height))
        }
        // The opened controls and the calibration marker both follow the chrome idle fade;
        // hitTest already rejects the faded overlay.
        let uiAlpha = CGFloat(CornerTuneLayout.overlayAlpha(calibrationOnly: calibrationOnly,
            chromeAlpha: Double((superview as? PPController)?.spineUI.alphaValue ?? 1)))
        if alphaValue != uiAlpha { alphaValue = uiAlpha }
        let content = CornerTuneLayout.clearContent(full,chrome:chrome,pad:Double(PhotonFont.chromePad))
        controls = calibrationOnly ? [] : cornerLayout.controls(in: content, subtitleBand: subtitleBandProvider?(), values: values)
        let crosshair = CornerTuneLayout.crosshairFrame(in: full, charW: Double(PhotonFont.chromeCharW), lineH: Double(PhotonFont.chromeLineH))
        // Frames are value-independent (fixed-width fields, owner 21:31), so the signature covers
        // GEOMETRY ONLY: a value change never rebuilds. Owner 21:43: constant re-rendering made
        // every click a glitch and hid what changed - now a value change retexts one layer in
        // place and the per-click change is exactly the value text (plus the render effect).
        let signature = "\(controls.map { $0.frames })|\(crosshair)|\(bounds.size)|\(PhotonFont.chromeScale)"
        guard signature != lastSignature else {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for c in controls { if let l = valueLayers[c.word], (l.string as? String) != c.value { l.string = c.value } }
            CATransaction.commit()
            applyVariation(); return
        }
        lastSignature = signature
        layers.forEach { $0.removeFromSuperlayer() }
        layers = []
        valueLayers = [:]
        titleLayers = [:]
        titleAreas.forEach { removeTrackingArea($0) }
        titleAreas = []
        hoverTimer?.invalidate(); hoverTimer = nil; hoverWord = nil
        // Every element gets its own layer: the title letter and value are read-only (the title
        // only expands on hover), the two glyph cells are the buttons (their own hit areas in
        // mouseDown below), plus the center crosshair. Values CENTER in their fixed-width fields
        // (owner 21:43: all gaps equal), so a value change never moves a button.
        for c in controls {
            var elementIndex = 0
            for (text, f) in [(c.letter, c.wordFrame), (c.value, c.valueFrame), (c.glyphA, c.cellA), (c.glyphB, c.cellB)] {
                let l = addTextLayer(text, f)
                if elementIndex == 0 { titleLayers[c.word] = (l, f) }
                if elementIndex == 1 { l.alignmentMode = CATextLayerAlignmentMode.center; valueLayers[c.word] = l }
                elementIndex += 1
            }
            let area = NSTrackingArea(rect: CGRect(x: c.wordFrame.x, y: c.wordFrame.y, width: c.wordFrame.w, height: c.wordFrame.h),
                                      options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: ["word": c.word])
            addTrackingArea(area)
            titleAreas.append(area)
        }
        let marker=addTextLayer("+", crosshair)
        gazeCrosshair.bind(view:self,marker:marker)
        applyVariation()
    }

    /// Owner 22:28: hovering a title letter types the full word like the spine buttons' typewriter
    /// (MusicBtn's 0.04 s per char), the letter pinned at the corner's outer edge; leaving types it
    /// back. Values and +/- symbols never move.
    override func mouseEntered(with event: NSEvent) {
        guard let word = event.trackingArea?.userInfo?["word"] as? String, titleLayers[word] != nil else { return }
        hoverTimer?.invalidate()
        hoverWord = word
        hoverShown = 1
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self = self, let (l, base) = self.titleLayers[word] else { t.invalidate(); return }
            self.hoverShown = min(self.hoverShown + 1, word.count)
            self.setTitle(layer: l, base: base, text: String(word.prefix(self.hoverShown)))
            if self.hoverShown == word.count { t.invalidate() }
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard let word = event.trackingArea?.userInfo?["word"] as? String, word == hoverWord else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self = self, let (l, base) = self.titleLayers[word] else { t.invalidate(); return }
            self.hoverShown = max(self.hoverShown - 1, 1)
            self.setTitle(layer: l, base: base, text: String(word.prefix(self.hoverShown)))
            if self.hoverShown == 1 { t.invalidate(); self.hoverWord = nil }
        }
    }

    /// Left titles grow left-to-right, right titles right-to-left (MusicBtn's expandsLeftToRight
    /// pattern), so the visible letter never shifts while the word types out. Owner 2026-11-12
    /// 12:40 (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q): depth/size must stay pinned at the right edge
    /// and type out LEFTWARD with no positional shift. The frame math alone is not enough: a
    /// default left-aligned CATextLayer keeps the glyph at the frame's left edge while the frame
    /// grows left, so the alignment mode must pin the same edge as the frame.
    private func setTitle(layer: CATextLayer, base: CornerTuneRect, text: String) {
        let leftPinned = base.x + base.w / 2 < Double(bounds.width) / 2
        let w = Double(max(text.count, 1)) * Double(PhotonFont.chromeCharW)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.string = text
        layer.alignmentMode = leftPinned ? CATextLayerAlignmentMode.left : CATextLayerAlignmentMode.right
        layer.frame = CGRect(x: leftPinned ? base.x : base.x + base.w - w, y: base.y, width: w, height: base.h)
        CATransaction.commit()
    }

    @discardableResult
    private func addTextLayer(_ text: String, _ f: CornerTuneRect) -> CATextLayer {
        let l = CATextLayer()
        l.string = text
        l.font = PhotonFont.ctFace()
        l.fontSize = PhotonFont.chromeSize
        l.foregroundColor = NSColor(white: 1, alpha: 0.85).cgColor
        l.frame = CGRect(x: f.x, y: f.y, width: f.w, height: f.h)
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(l)
        layers.append(l)
        return l
    }

    private func applyVariation() {
        guard superview != nil else {return}
        let audio=Double(ScreenCaptureEngine.shared.currentAudioLevel)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for text in layers {
            let proximity=VariationBroadcaster.shared.proximity(to:text,in:self,radius:100)
            let p=0.5+(1.0-Double(proximity))*0.75
            let blend=max(0.0,min(1.0,(p+audio)/2.0))
            PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p:CGFloat(p),t_audio:blend,size:nil),on:text)
        }
        CATransaction.commit()
    }

    override func layout() {super.layout(); refresh()}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func hitTest(_ point:NSPoint)->NSView? {
        guard alphaValue > 0.5 else { return nil }   // hidden or marker-only: no hit areas
        let p=convert(point,from:superview)
        return gazeCrosshair.hitFrame.insetBy(dx:-PhotonFont.chromeCharW,dy:-4).contains(p) || (!calibrationOnly && controls.contains { c in c.frames.contains { $0.contains(Double(p.x), Double(p.y)) } }) ? self:nil
    }

    /// The menu's calibration crosshair (Shift+3 row): same "+" marker, nothing else.
    func setCalibration(_ on: Bool, in rootView: NSView) {
        calibrationActive = on
        if on {
            if superview == nil { calibrationOnly = true; attach(to: rootView) }
            refresh()
        } else if calibrationOnly {
            calibrationOnly = false; hide()
        }
    }

    func toggle(in rootView: NSView) {
        if superview != nil && !calibrationOnly { hide(); if calibrationActive { calibrationOnly = true; attach(to: rootView); refresh() }; return }
        if superview == nil { attach(to: rootView) }
        calibrationOnly = false
        refresh()
    }

    private func attach(to rootView: NSView) {
        frame = chromeFrame(in: rootView)
        if frame == .zero { frame = rootView.bounds }
        placedFrame = frame; lastChrome = frame
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.zPosition = 4000   // below DropdownList's 5000, above the video surface
        rootView.addSubview(self)
        if !subscribed {
            subscribed = true
            store.subscribe(ownerID: "corner-tune") { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        if !variationSubscribed {
            variationSubscribed=true
            VariationBroadcaster.shared.addListener(weakLifetime:self) { [weak self] in self?.applyVariation() }
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()   // key-path changes do not all flow through the store
        }
    }

    override func viewDidMoveToSuperview() {super.viewDidMoveToSuperview();if superview==nil {gazeCrosshair.stop()}}

    func hide() {
        gazeCrosshair.stop()
        refreshTimer?.invalidate(); refreshTimer = nil
        hoverTimer?.invalidate(); hoverTimer = nil; hoverWord = nil
        titleAreas.forEach { removeTrackingArea($0) }; titleAreas = []
        removeFromSuperview()
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if gazeCrosshair.hitFrame.insetBy(dx:-PhotonFont.chromeCharW,dy:-4).contains(pt) {gazeCrosshair.toggle();return}
        for c in controls {
            guard let acts = ThreeDCornerTuneView.acts[c.word] else { continue }
            if c.cellA.contains(Double(pt.x), Double(pt.y)) { ThreeDMenu.dispatch(acts.0); refresh(); return }
            if c.cellB.contains(Double(pt.x), Double(pt.y)) { ThreeDMenu.dispatch(acts.1); refresh(); return }
        }
        // Labels and values keep the surface pinned; only selecting 3D again closes it.
    }

    override var acceptsFirstResponder: Bool { true }
}

/// Sidebar-V wiring (owner order 00:53: V between OSD and Audio, hover "Video", click opens a side
/// dropdown with one "3D" row). Kept out of SpineUI.swift itself: that file is at its architecture
/// ceiling, so only net-0 one-line hooks ride existing lines there.
extension SpineUI {
    func showVideoDropdown() {
        activeDropdown?.removeFromSuperview(); activeDropdown = nil
        guard let window = self.window, let rootView = window.contentView else { return }
        let pad = PhotonFont.chromePad, btnW = PhotonFont.chromeCharW + PhotonFont.chromeGap
        let anchorInRoot = convert(CGPoint(x: pad + btnW + PhotonFont.chromeValue(6), y: CGFloat(CornerTuneLayout.dropdownTop(videoMinY:Double(btnVid.frame.minY),lineH:Double(PhotonFont.chromeLineH)))), to: rootView)
        let drop = DropdownList(frame: .zero)
        drop.wantsLayer = true
        drop.layer?.zPosition = 5000
        drop.populate([(id: -2000, title: "3D")], type: "video", maxH: anchorInRoot.y)
        let availableW = rootView.bounds.width - anchorInRoot.x - 4
        drop.frame.size.width = min(drop.frame.width, max(availableW, 80))
        drop.frame.origin = CGPoint(x: anchorInRoot.x, y: anchorInRoot.y - drop.frame.height)
        btnV.isBlocked = true
        drop.onDismissed = { [weak self] in self?.btnV.isBlocked = false }
        drop.onSelect = { [weak self] trackId in
            guard trackId == -2000, let self = self, let root = self.window?.contentView else { return }
            self.activeDropdown?.removeFromSuperview(); self.activeDropdown = nil
            self.btnV.isBlocked = false
            ThreeDCornerTuneView.shared.toggle(in: root)
        }
        rootView.addSubview(drop)
        activeDropdown = drop
    }
}
// END relocated ThreeDCornerTune.swift
// BEGIN relocated ThreeDCornerTuneLayout.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 191k: geometry for the sidebar-V "3D" corner fine-tune controls. Pure value math, no
/// AppKit/CoreGraphics, so Tests/ThreeDCornerTune compiles and measures it on Linux. The AppKit
/// view (ThreeDCornerTune.swift) renders exactly what this returns and nothing more.
///
/// Owner 17:33 (phonemsg-01M72Y1GHHQT93RMMN87H3JZJZ), English paraphrase: the controls must be
/// clickable, not plain text; remove subs; labels sit IN the corners, values beside them, and the
/// +/- cells march diagonally inward. Owner 22:23 mockup (phonemsg-01M73EN9MK2FP8JX3EMDX9DGP5)
/// revised 22:25 (phonemsg-01M73ES5GY2NGCM48D6W7GP1A5), rows corrected 22:26
/// (phonemsg-01M73ESDM65XZHT1E0ESN9KDWJ): titles sit tight at the corner margin, the value sits at
/// a fixed column beside the title, and the two cells march from the value column inward in EQUAL
/// diagonal steps; the four corners are exact left/right and top/bottom mirrors. Owner 2026-11-12
/// 12:40 (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q) replaced the hand-drawn mockup's measured columns
/// with the pad grid pinned below (gaps halved to pad x 1 at 13:47,
/// phonemsg-01M77NX7459XYMH8W2B3VR9N01); Tests/ThreeDCornerTune measures that grid. Owner 22:28
/// (phonemsg-01M73EX09GEDHCQQ5V1YMJ5K8Y): titles show as ONE letter (i/s/d/s); hovering a title
/// types out the full word like the spine buttons' typewriter; values and symbols never move.

/// Plain rect so the layout never touches CoreGraphics (Linux has none in Foundation).
struct CornerTuneRect: Equatable {
    var x: Double, y: Double, w: Double, h: Double
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    func intersects(_ o: CornerTuneRect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }
    func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < maxX && py >= y && py < maxY }
    func offsetBy(dx: Double, dy: Double) -> CornerTuneRect { CornerTuneRect(x: x + dx, y: y + dy, w: w, h: h) }
}

/// One corner control: the single-letter title, the value, and the two tappable glyph cells as
/// separate frames, so the view can give every element its own layer and its own hit area. `word`
/// is the full title the hover typewriter expands to (owner 22:28); `letter` is what is drawn.
struct CornerTuneControl: Equatable {
    var letter: String
    var word: String
    var value: String
    var glyphA: String   // far cell (second diagonal step): weaker side
    var glyphB: String   // near cell (first diagonal step): stronger side
    var corner: CornerTuneCorner
    var wordFrame: CornerTuneRect
    var valueFrame: CornerTuneRect
    var cellA: CornerTuneRect
    var cellB: CornerTuneRect
    var frames: [CornerTuneRect] { [wordFrame, valueFrame, cellA, cellB] }
}

enum CornerTuneCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct CornerTuneLayout {
    var charW: Double
    var lineH: Double
    var pad: Double
    init(charW: Double, lineH: Double, pad: Double) {
        self.charW = charW; self.lineH = lineH; self.pad = pad
    }

    /// The four exposed fine-tunes, one per corner (subs removed, owner 17:33; titles single-letter
    /// 22:28). Owner 2026-11-12 13:47 (phonemsg-01M77NX7459XYMH8W2B3VR9N01): the screen-distance
    /// cells are left/right arrows, not "+" and a right arrow - near cell "→" pushes the screen
    /// farther, far cell "←" brings it nearer; every other control stays "+/-".
    static let spec: [(corner: CornerTuneCorner, letter: String, word: String, key: String, glyphA: String, glyphB: String)] = [
        (.topLeft,     "i", "ipd",   "ipd",         "-", "+"),
        (.topRight,    "d", "depth", "strength",    "-", "+"),
        (.bottomLeft,  "s", "scr",   "screenDepth", "←", "→"),
        (.bottomRight, "s", "size",  "screenSize",  "-", "+"),
    ]

    /// Owner 2026-11-12 12:40 (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q), English paraphrase: the
    /// title's outer edge sits at a fixed pad distance from the spine/sidebar edge; the value
    /// column is ONE shared column reserved from the longest title ("depth"), so shorter titles
    /// expanding on hover never move a value and the grid never breaks. The first line box starts
    /// rowPadLines from the corner edge and each element sits one line further in; the four
    /// corners remain exact left/right and top/bottom mirrors. Owner 13:47
    /// (phonemsg-01M77NX7459XYMH8W2B3VR9N01) halved every pad x 2 gap to ONE pad: titleMarginPads
    /// is 0, so the title sits at the cleared content edge (pad x 1 from the chrome edge via
    /// clearContent), and the title-value, value-cell and cell-cell gaps are all pad x 1
    /// edge-to-edge (the title-value air halved as ordered). These constants supersede the
    /// 22:23-22:26 hand-drawn mockup's measured char tokens.
    static let titleMarginPads = 0.0
    static let gridGapPads = 1.0
    static let titleReserveChars = 5   // "depth", the longest corner title
    static let valueFieldChars = 6     // widest value field (screenDepth "0.667m"): one shared column
    static let rowPadLines = 0.5

    // Reserve the existing chrome edges, keeping the final glyph frame two pads away.
    static func clearContent(_ content: CornerTuneRect, chrome: [CornerTuneRect], pad: Double) -> CornerTuneRect {
        var left=content.x, right=content.maxX
        for rect in chrome where rect.h > 0 && rect.w > 0 {
            if rect.x+rect.w/2 < content.x+content.w/2 {left=max(left,rect.maxX+pad)}
            else {right=min(right,rect.x-pad)}
        }
        return CornerTuneRect(x:left,y:content.y,w:max(0,right-left),h:content.h)
    }
    // Owner 2026-11-12 12:40 (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q): the 3D dropdown row sits on
    // the row directly below Video - top edge at Video's minY, so its bottom edge clears Video by
    // one full typography row. Bottom-left coordinates.
    static func dropdownTop(videoMinY: Double, lineH: Double) -> Double {max(lineH,videoMinY)}

    // The explicitly opened control surface and the calibration marker both follow
    // ordinary chrome visibility. Toggling remains the way the surface is dismissed.
    static func overlayAlpha(calibrationOnly: Bool, chromeAlpha: Double) -> Double {
        chromeAlpha
    }

    /// The center crosshair cell (owner 21:28 phonemsg-01M73BG6BQ7DP7BGPR2FWA3TXP: when the 3D
    /// overlay opens, a crosshair exactly at center in the current UI font and its size). One
    /// char wide, one line high, centered on the content rect to the half point.
    static func crosshairFrame(in content: CornerTuneRect, charW: Double, lineH: Double) -> CornerTuneRect {
        CornerTuneRect(x: content.x + (content.w - charW) / 2, y: content.y + (content.h - lineH) / 2, w: charW, h: lineH)
    }

    /// Fixed value-field widths in chars (owner 21:31 phonemsg-01M73BN8SNRMNC3TGGTK18NJEV: when a
    /// value changes, e.g. 0.5 -> 0.75, the buttons must NOT move). Each width covers the longest
    /// string `format` can emit for that key's reachable set: strength 0...2 by 0.25 ("0.25"),
    /// screenDepth 1.5 x/:/1.5 clamped 0.25...8 at %.3g ("0.667m"), screenSize 20...150 by 5
    /// ("150\u{00B0}"), ipd +/-0.2 by 0.02 with %+.1f ("+0.2"). A stored out-of-set value
    /// widens its own field only.
    static let valueMaxChars: [String: Int] = ["ipd": 4, "strength": 4, "screenDepth": 6, "screenSize": 4]
    // Owner 2026-11-12 12:40: valueFieldChars above is max(valueMaxChars) - one shared field for
    // every row, so the +/- cells form a single grid column too. This supersedes the 22:13 per-key
    // field widths.

    private func control(_ entry: (corner: CornerTuneCorner, letter: String, word: String, key: String, glyphA: String, glyphB: String),
                         value: String, in content: CornerTuneRect) -> CornerTuneControl {
        // Inward direction from the corner: x marches away from the nearest side, y away from the
        // nearest edge (bottom-left origin).
        let dx: Double = (entry.corner == .topLeft || entry.corner == .bottomLeft) ? 1 : -1
        let dy: Double = (entry.corner == .topLeft || entry.corner == .topRight) ? -1 : 1
        let sideX = dx > 0 ? content.x : content.maxX
        // Pair line box starts half a line from the corner edge; each element one line further in.
        let rowY = dy < 0 ? content.maxY - (CornerTuneLayout.rowPadLines + 1) * lineH
                          : content.y + CornerTuneLayout.rowPadLines * lineH
        let gap = CornerTuneLayout.gridGapPads * pad
        let titleMargin = CornerTuneLayout.titleMarginPads * pad
        let titleReserve = Double(CornerTuneLayout.titleReserveChars) * charW
        // Title: one letter cell, outer edge titleMarginPads from the cleared content edge
        // (pad x 1 from the spine/sidebar edge via clearContent's pad, owner 13:47); hover expands
        // it in place.
        let wordX = dx > 0 ? sideX + titleMargin
                           : sideX - titleMargin - charW
        let wordFrame = CornerTuneRect(x: wordX, y: rowY, w: charW, h: lineH)
        // Value: ONE shared fixed-width field starting pad x 1 after the reserved title column
        // (owner 2026-11-12 12:40: the title reservation is the longest title and the field is the
        // widest value, so every row shares one value column and the +/- cells form one grid).
        // Values center in the field (21:43); an out-of-set stored value widens only its own
        // field (21:31).
        let valueW = Double(max(value.count, CornerTuneLayout.valueFieldChars)) * charW
        let valueX = dx > 0 ? sideX + titleMargin + titleReserve + gap
                            : sideX - titleMargin - titleReserve - gap - valueW
        let valueFrame = CornerTuneRect(x: valueX, y: rowY, w: valueW, h: lineH)
        // Cells march diagonally inward after the value field with pad x 1 edge gaps
        // everywhere (owner 13:47): value -> near cell (stronger, one line in) -> far cell
        // (weaker, two lines in).
        let cellBX = dx > 0 ? valueFrame.maxX + gap
                            : valueFrame.x - gap - charW
        let cellB = CornerTuneRect(x: cellBX, y: rowY + lineH * dy, w: charW, h: lineH)
        let cellAX = dx > 0 ? cellB.maxX + gap
                            : cellB.x - gap - charW
        let cellA = CornerTuneRect(x: cellAX, y: rowY + 2 * lineH * dy, w: charW, h: lineH)
        return CornerTuneControl(letter: entry.letter, word: entry.word, value: value, glyphA: entry.glyphA, glyphB: entry.glyphB,
                                 corner: entry.corner, wordFrame: wordFrame, valueFrame: valueFrame,
                                 cellA: cellA, cellB: cellB)
    }

    /// All corner controls inside `content` (bottom-left origin). Bottom controls never intersect
    /// `subtitleBand`: when they would, the whole diagonal stack shifts up above the band with one
    /// pad of air.
    func controls(in content: CornerTuneRect, subtitleBand: CornerTuneRect?,
                  values: [String: String]) -> [CornerTuneControl] {
        var out: [CornerTuneControl] = []
        for entry in CornerTuneLayout.spec {
            let value = values[entry.key] ?? "-"
            var c = control(entry, value: value, in: content)
            if let band = subtitleBand, c.frames.contains(where: { $0.intersects(band) }) {
                let shift = band.maxY + pad - c.wordFrame.y
                c.wordFrame = c.wordFrame.offsetBy(dx: 0, dy: shift)
                c.valueFrame = c.valueFrame.offsetBy(dx: 0, dy: shift)
                c.cellA = c.cellA.offsetBy(dx: 0, dy: shift)
                c.cellB = c.cellB.offsetBy(dx: 0, dy: shift)
            }
            out.append(c)
        }
        return out
    }

    /// Value formatting shared by the view and the test: short, no trailing zeros, units attached.
    static func format(key: String, raw: Double?) -> String {
        guard let raw else { return "-" }
        switch key {
        case "screenDepth": return String(format: "%.3gm", raw)
        case "screenSize":  return String(format: "%g\u{00B0}", raw)
        case "ipd":         return String(format: "%+.1f", raw)
        default:            return String(format: "%g", raw)
        }
    }
}
// END relocated ThreeDCornerTuneLayout.swift
