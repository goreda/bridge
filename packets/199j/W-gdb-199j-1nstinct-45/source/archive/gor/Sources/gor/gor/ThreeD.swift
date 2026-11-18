// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
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
        if transient { return } // [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

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
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
    static func masterActive(mode: String, projectionOn: Bool, previewOn: Bool) -> Bool { previewOn || projectionOn }
    static var previewActive = false
    /// Wired by ThreeDWiring: switch the old projection off / select flat-2d3d again.
    static var stopPreview: () -> Void = {}, resumePreview: () -> Void = {}
    static func endPreview() { previewActive = false }
// [attribution comment elided]
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
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import AppKit

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum ThreeDRuntime { static var coordinator: AnyObject?;static var lastRenderState:ThreeDState? }

enum ThreeDPrepareRuntime { static var launcher: ThreeDPrepareLauncher?, timer: Timer? }

extension AppDelegate {
    /// Subscription is replaced when a player arrives; the store outlives every controller.
    func installThreeDSourceResolution() {
        MainActor.assumeIsolated {
        ThreeDRecognitionBridge.migrate()
        ThreeDExperimentMenu.shared.send = { [weak self] in self?.cmd($0) }
        ThreeDExperimentMenu.shared.onExperimentChange = { (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.preferencesDidChange(force: true) }   // 195h r2-7: an experiment toggle runs the existing re-render/re-prepare refresh
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        if !ThreeDExperimentMenu.launchMasterApplied { ThreeDExperimentMenu.launchMasterApplied = true; ThreeDExperimentMenu.shared.setAll(true) }
        ThreeDExperimentMenu.shared.reapplyIfEnabled()
        ThreeDStore.shared.subscribe(ownerID:"player-applier") { [weak self] state,effects in
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
// [attribution comment elided]
// [attribution comment elided]
import AppKit
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import AppKit
import Foundation

// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// Platform evidence and one-time legacy import. No legacy state is used after migrationComplete.
enum ThreeDRecognitionBridge {
    private static var torrentInputs:[String:ThreeDFilmIdentity]=[:]
    @MainActor static func bindTorrent(path:String,infohash:String,index:Int,basename:String,size:Int64) {
        torrentInputs[path]=ThreeDFilmIdentity(volume:nil,fileID:nil,infohash:infohash,fileIndex:index,basename:basename,finalSize:size,normalizedURL:nil)
    }
    @MainActor static func resolveAtOpen(path:String)->FilmID {ThreeDStore.shared.unbindSource(path:path);return filmID(path:path)}
    @MainActor static func filmID(path:String)->FilmID {
        if let bound=ThreeDStore.shared.id(for:path) {return bound}
        if let torrent=torrentInputs[path] {return ThreeDStore.shared.resolveIdentity(path:path,input:torrent)}
        let url=URL(fileURLWithPath:path).resolvingSymlinksInPath().standardizedFileURL
        if !path.contains("://"),!path.lowercased().hasPrefix("magnet:"),
           let values=try? url.resourceValues(forKeys:[.volumeUUIDStringKey]),let volume=values.volumeUUIDString,
           let attrs=try? FileManager.default.attributesOfItem(atPath:url.path),let inode=attrs[.systemFileNumber] as? NSNumber {
            return ThreeDStore.shared.resolveIdentity(path:path,input:ThreeDFilmIdentity(volume:volume,fileID:inode.stringValue,infohash:nil,fileIndex:nil,basename:url.lastPathComponent,finalSize:(attrs[.size] as? NSNumber)?.int64Value,normalizedURL:nil))
        }
        return ThreeDStore.shared.resolveIdentity(path:path,input:ThreeDFilmIdentity(volume:nil,fileID:nil,infohash:nil,fileIndex:nil,basename:url.lastPathComponent,finalSize:nil,normalizedURL:path.contains(":") ? VRRecognition.fileIdentity(path):nil))
    }
    static func source(projection:String?,sbs:Bool,tb:Bool,filename path:String="")->ThreeDSource? {
        // Packing metadata is not a spherical-projection verdict. An explicit
        // VR180 filename survives generic SBS/TB metadata; explicit spherical
        // or unsupported projection metadata still owns its own verdict.
        if projection == nil || projection == "flat-sbs" || projection == "flat-tb",
           let tagged=filename(path), tagged.nativeVR {return tagged}
        switch projection {
        case "vr180": return ThreeDSource(tb ? .vr180TB:.vr180SBS)
        case "vr180-tb": return ThreeDSource(.vr180TB)
        case "vr360-mono": return ThreeDSource(tb ? .vr360TB:.vr360Mono)
        case "vr360-tb": return ThreeDSource(.vr360TB)
        case "unsupported": return nil
        case "flat-sbs": return ThreeDSource(.sbsFull)
        case "flat-tb": return ThreeDSource(.tbFull)
        default: return sbs ? ThreeDSource(.sbsFull):(tb ? ThreeDSource(.tbFull):nil)
        }
    }
    static func filename(_ path:String)->ThreeDSource? {
        let name=URL(fileURLWithPath:path).lastPathComponent.lowercased()
        func tag(_ pattern:String)->Bool {name.range(of:pattern,options:.regularExpression) != nil}
        let tb=tag(#"(?:^|[^a-z0-9])(?:tb|ou|htb|ftb)(?:[^a-z0-9]|$)"#)
        if tag(#"(?:^|[^a-z0-9])(?:vr180|180|3dh)(?:x180|sbs|lr)?(?:[^a-z0-9]|$)"#) {return ThreeDSource(tb ? .vr180TB:.vr180SBS)}
        if tag(#"(?:^|[^a-z0-9])(?:vr360|360)(?:[^a-z0-9]|$)"#) {return ThreeDSource(tb ? .vr360TB:.vr360Mono)}
        if tag(#"(?:^|[^a-z0-9])(?:sbs|hsbs|fsbs|lr)(?:[^a-z0-9]|$)"#) {return ThreeDSource(name.contains("hsbs") ? .sbsHalf:.sbsFull)}
        if tb {return ThreeDSource(.tbFull)}
        return nil
    }
    static func internalMedia(_ path:String)->Bool {
        path.hasPrefix(DepthCachePaths.root.path+"/") && URL(fileURLWithPath:path).lastPathComponent.range(of:#"^(?:render|source)_shot_[0-9]+\.mp4$"#,options:.regularExpression) != nil
    }
    @MainActor static func migrate(_ defaults:UserDefaults = .standard) {
        guard !ThreeDStore.shared.snapshot.migrationComplete else {return}
        var imported:[FilmID:FilmThreeD]=[:]
        // Only provenance-bearing explicit choices are importable. Historical projection caches
        // mixed detection and user writes, so they are deliberately left untouched, not guessed.
        let explicit=defaults.dictionary(forKey:"gor.3d.sourceByFilm.v1.explicitMenuOutput.v2") as? [String:String] ?? [:]
        let sources=defaults.dictionary(forKey:"gor.3d.sourceByFilm.v1") as? [String:String] ?? [:]
        let outputs=defaults.dictionary(forKey:"gor.3d.sourceByFilm.v1.output") as? [String:String] ?? [:]
        for (path,grant) in explicit {
            let value=outputs[path] ?? "off"
            guard value=="off" || value==grant,let output=ThreeDOutput(rawValue:value),!internalMedia(path) else {continue}
            var film=FilmThreeD();film.source=SourceFormatChoice.source(sources[path] ?? "flat")
            film.output=output;film.lastOutput=output == .off ? (ThreeDOutput(rawValue:grant) ?? .sbs):output;film.userTouched=true
            imported[SourceFormatChoice.filmID(path)]=film
        }
        ThreeDStore.shared.migrateExplicit(imported)
        print("3D-DECISION migration=complete imported=\(imported.count) reason=explicit_provenance_only legacy_values_preserved=true")
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// 190t K: first-3D-enable model fetch. Runs the repo's tools/gor-fetch-models.sh (curl to huggingface.co, no account; every file kept only if its
/// sha256 matches models/models.lock.tsv) from the source directory baked at build time, then verifies the same sha256 values itself before 3D may
/// start. Plain OSD lines for progress and failure; until verified the film stays 2D. Nothing is downloaded by build.sh. Not run on a Mac.
final class ThreeDModels {
    static let shared = ThreeDModels()
// [attribution comment elided]
    static var sourceDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["GOR_SOURCE_DIR"] ?? (NSHomeDirectory() + "/Downloads/gor"))
    }
    static var modelsDir: URL {
        ProcessInfo.processInfo.environment["GOR_MODELS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("gor/models", isDirectory: true)
    }

    struct Row: Equatable { let id: String, repo: String, file: String, sha: String }

    /// Pure: the `usable` Apache-2.0/MIT rows of models.lock.tsv (same filter as gor-fetch-models.sh). Header row and others are skipped.
    static func rows(lock: String) -> [Row] {
        lock.split(separator: "\n").compactMap { line -> Row? in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 7, c[0] != "id", c[1] == "usable", ["Apache-2.0", "MIT"].contains(c[2]) else { return nil }
            return Row(id: c[0], repo: c[3].hasPrefix("https://") ? String(c[3].dropFirst(8)) : c[3], file: c[5], sha: c[6])   // local dir = host/path, same as gor-fetch-models.sh
        }
    }
    /// Pure: the OSD text for one script output line ("ok   id", "ok   id (cached)", "skip ...", "FAIL id: reason", "REFUSE ...").
    static func progressText(line: String, done: Int, total: Int) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("ok ") { return "3D: models \(done)/\(total) ready" }
        if t.hasPrefix("FAIL") || t.hasPrefix("REFUSE") { return "3D: model download failed (\(t.prefix(80))), staying 2D" }
        return nil
    }

    /// Only the CoreML kit rows gate "verified" and are fetched (GOR_MODELS_ONLY below): the runtime uses nothing else. The .pth/.onnx/.pt rows stay in the lock as provenance.
    static let onlyID = "coreml-kit"
    static func gated(_ r: Row) -> Bool { r.id.contains(onlyID) }
    /// 195h A (Delivery A-5): a DAV2 request's gate is its own 3 pinned mlpackage parts (plain files; no kit install marker),
    /// never the CoreML kit. A DAV2-only install verifies without VDA/MoGe ever being fetched.
    static let dav2OnlyID = "dav2-small-coreml-f16"
    static func gatedDAV2(_ r: Row) -> Bool { r.id.contains(dav2OnlyID) }
    /// The lock rows gating one request: the CoreML kit for the default producer, just the 3 pinned DAV2 files for dav2_small_coreml.
    static func gatedRows(lock: String, dav2: Bool) -> [Row] { rows(lock: lock).filter { dav2 ? gatedDAV2($0) : gated($0) } }
    /// The GOR_MODELS_ONLY filter the fetch script gets for that gate (it substring-matches row ids).
    static func onlyID(dav2: Bool) -> String { dav2 ? dav2OnlyID : onlyID }
    /// Files of `rows` whose on-disk sha256 differs (or whose kit install marker is missing). Injectable sha256 for tests (Linux has no CryptoKit).
    static func missing(_ rows: [Row], modelsDir: URL = ThreeDModels.modelsDir, sha: (URL) -> String? = ThreeDModels.sha256(of:)) -> [Row] {
        rows.filter { sha(modelsDir.appendingPathComponent($0.repo).appendingPathComponent($0.file)) != $0.sha || !kitInstalled($0, modelsDir: modelsDir) }
    }

    /// Kit rows (id contains coreml-kit) also need their unpacked packages: gor-fetch-models.sh writes <models>/kit/.installed-<id> holding the archive sha256 once every package is in place.
    static func kitInstalled(_ r: Row, modelsDir: URL = ThreeDModels.modelsDir) -> Bool {
        guard r.id.contains("coreml-kit") else { return true }
        return (try? String(contentsOf: modelsDir.appendingPathComponent("kit/.installed-" + r.id), encoding: .utf8)) == r.sha && KitHash.verify(kitDir: modelsDir.appendingPathComponent("kit"), archiveID: r.id).isEmpty
    }

    static func sha256(of url: URL) -> String? {
        #if canImport(CryptoKit)
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let d = try? h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }

    private let lock = NSLock()
    private var running = false, isVerified = false, failedText: String?
    private var runningDAV2 = false, isVerifiedDAV2 = false, failedTextDAV2: String?   // 195h A: the DAV2 gate has its own state
    var verified: Bool { lock.lock(); defer { lock.unlock() }; return isVerified }
    var verifiedDAV2: Bool { lock.lock(); defer { lock.unlock() }; return isVerifiedDAV2 }

    /// Idempotent and cheap to call from a timer: verifies on a utility queue, fetches when something is missing, reports plain progress/failure
    /// once per distinct line. A failed fetch is not retried until the app restarts.
    func ensure(report: @escaping (String) -> Void) { ensure(dav2: false, report: report) }
    /// 195h A (Delivery A-5): the DAV2 request's verify/fetch gate over just the 3 pinned dav2 rows.
    func ensureDAV2(report: @escaping (String) -> Void) { ensure(dav2: true, report: report) }
    private func ensure(dav2: Bool, report: @escaping (String) -> Void) {
        lock.lock()
        if dav2 { if runningDAV2 || isVerifiedDAV2 || failedTextDAV2 != nil { lock.unlock(); return }; runningDAV2 = true }
        else { if running || isVerified || failedText != nil { lock.unlock(); return }; running = true }
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            func finish(_ ok: Bool, _ fail: String?) {
                lock.lock()
                if dav2 { runningDAV2 = false; isVerifiedDAV2 = ok; failedTextDAV2 = fail } else { running = false; isVerified = ok; failedText = fail }
                lock.unlock()
                if let f = fail { DispatchQueue.main.async { report(f) } }
            }
            let lockURL = Self.sourceDir.appendingPathComponent("models/models.lock.tsv")
            guard let text = try? String(contentsOf: lockURL, encoding: .utf8) else {
                return finish(false, "3D: model list not found (\(lockURL.path)), staying 2D")
            }
            let rows = Self.gatedRows(lock: text, dav2: dav2)
            guard !rows.isEmpty else { return finish(false, "3D: no usable models are listed, staying 2D") }
            func missing() -> [Row] { Self.missing(rows) }
            if missing().isEmpty { return finish(true, nil) }
            let script = Self.sourceDir.appendingPathComponent("tools/gor-fetch-models.sh")
            guard FileManager.default.isReadableFile(atPath: script.path) else { return finish(false, "3D: model fetch script not found, staying 2D") }
            DispatchQueue.main.async { report("3D: downloading models (first use), staying 2D until they are verified") }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [script.path]
            var env = ProcessInfo.processInfo.environment; env["GOR_MODELS_DIR"] = Self.modelsDir.path; env["GOR_MODELS_ONLY"] = Self.onlyID(dav2: dav2); p.environment = env
            let out = Pipe(); p.standardOutput = out; p.standardError = out
            var done = 0
            out.fileHandleForReading.readabilityHandler = { h in
                for line in String(decoding: h.availableData, as: UTF8.self).split(separator: "\n") {
                    print("[GOR] 3d-fetch \(line)"); fflush(stdout)       // first Mac log names exactly what failed (gh missing / not signed in / no access)
                    if line.hasPrefix("ok ") { done += 1 }
                    if let t = Self.progressText(line: String(line), done: done, total: rows.count) { DispatchQueue.main.async { report(t) } }
                }
            }
            guard (try? p.run()) != nil else { return finish(false, "3D: could not start the model download, staying 2D") }
            p.waitUntilExit(); out.fileHandleForReading.readabilityHandler = nil
            let left = missing()                                       // our own sha256 check, not the script's exit code alone
            finish(left.isEmpty && p.terminationStatus == 0, left.isEmpty && p.terminationStatus == 0 ? nil : "3D: models not verified (\(left.count) missing or wrong), staying 2D")
        }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t K: the CoreML kit gate. NativePrepareRunner needs the converted packages (encoder/bootstrap/stream fp16 for VDA-S and at least one
/// moge2_vits_WxH_{fp16,fp32}) in one directory (kit_manifest.json names them). This registers the runner in ThreeDRunnerRegistry once they are all present;
/// until then it reports ONE plain OSD line naming what is missing and the film stays 2D. Where the packages come from is an open item (they are converted
/// on Linux and are not in models.lock.tsv); this file only checks and registers. Not compiled or run on a Mac.
enum ThreeDKit {
    /// GOR_KIT_DIR overrides; default <models dir>/kit (next to the files gor-fetch-models.sh writes).
    static var dir: URL {
        ProcessInfo.processInfo.environment["GOR_KIT_DIR"].map { URL(fileURLWithPath: $0) } ?? ThreeDModels.modelsDir.appendingPathComponent("kit", isDirectory: true)
    }
    static let vda = ["encoder_fp16.mlpackage", "bootstrap_fp16.mlpackage", "stream_fp16.mlpackage"]

    /// Pure: the package names still missing given the directory listing ("moge2_vits_*.mlpackage" stands for "any MoGe-2 package").
    static func missing(listing: [String]) -> [String] {
        let have = Set(listing)
        var m = vda.filter { !have.contains($0) }
        if !listing.contains(where: { $0.hasPrefix("moge2_vits_") && $0.hasSuffix(".mlpackage") }) { m.append("moge2_vits_*.mlpackage") }
        return m
    }
    static func missing(dir: URL = ThreeDKit.dir) -> [String] { missing(listing: (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []) }

    /// Pure: the plain OSD line. MoGe-2 alone missing = its kit is not fetched yet (licence approved, 190w W1), so say that instead of "missing".
    static func message(missing m: [String]) -> String {
        m == ["moge2_vits_*.mlpackage"] ? "3D unavailable: the MoGe-2 depth model is not downloaded yet, staying 2D"
                                        : "3D: CoreML kit missing (\(m.joined(separator: ", "))), staying 2D"
    }

    private static let lock = NSLock()
    private static var verifyRunning = false, verifyFailed: [String]?, toldVerify = false
    private static var told = false
    /// Idempotent, cheap (one directory listing). true once a runner is registered. Reports the missing list once per launch.
    @discardableResult
    static func register(report: (String) -> Void) -> Bool {
        if ThreeDRunnerRegistry.runner != nil { return true }
        let m = missing()
        guard m.isEmpty else {
            // 195h A (Delivery A-1): a DAV2-only install (kit absent) still registers when the pinned DAV2 package is present - the DAV2
            // prepare path never touches the kit (NativePrepareRunner skips loadModels for DAV2 jobs).
            #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate)
            if CoreMLDepthRunner.available(modelsDir: ThreeDModels.modelsDir) {
                let r = NativePrepareRunner(kitDir: dir); r.modelsDir = ThreeDModels.modelsDir
                ThreeDRunnerRegistry.runner = r
                print("3d-depth-runtime registered runner=NativePrepareRunner verified_manifest=none depth=DAV2_Small synthesis=\(SynthMethod.current.method.rawValue)"); fflush(stdout)
                return true
            }
            #endif
            if !told { told = true; report(message(missing: m)) }
            return false
        }
        // per-package content_sha256 + size against the kit manifests (KitHash), once per kit version, off the main thread; a verified kit leaves .verified-<manifest sha>
        let tag = KitCompiledCache.manifestSha(kitDir: dir).map { String($0.prefix(16)) } ?? "none"
        let mark = dir.appendingPathComponent(".verified-" + tag)
        if !FileManager.default.fileExists(atPath: mark.path) {
            lock.lock(); let run = verifyRunning, failed = verifyFailed; if !run && failed == nil { verifyRunning = true }; lock.unlock()
            if let f = failed { if !toldVerify { toldVerify = true; report("3D: CoreML kit failed verification (\(f.joined(separator: ", "))), staying 2D") }; return false }
            if !run {
                let kd = dir
                DispatchQueue.global(qos: .utility).async {
                    let bad = KitHash.verify(kitDir: kd)
                    if bad.isEmpty { try? Data("ok".utf8).write(to: mark) }
                    lock.lock(); verifyRunning = false; verifyFailed = bad.isEmpty ? nil : bad; lock.unlock()
                }
            }
            return false
        }
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate)
        let r = NativePrepareRunner(kitDir: dir); r.modelsDir = ThreeDModels.modelsDir     // kit-compiled cache lives under <models>
        ThreeDRunnerRegistry.runner = r
        print("3d-depth-runtime registered runner=NativePrepareRunner verified_manifest=\(tag) depth=VDA_MoGe synthesis=\(SynthMethod.current.method.rawValue)"); fflush(stdout)
        return true
        #else
        return false
        #endif
    }

    /// Snapshot for the degradation FSM probe (ThreeDDegradeProbe.kitEvent); the verified marker is the one register() writes.
    static func probeState() -> (missing: [String], verified: Bool, failed: [String]?, verifying: Bool) {
        let tag = KitCompiledCache.manifestSha(kitDir: dir).map { String($0.prefix(16)) } ?? "none"
        lock.lock(); let f = verifyFailed, r = verifyRunning; lock.unlock()
        return (missing(), FileManager.default.fileExists(atPath: dir.appendingPathComponent(".verified-" + tag).path), f, r)
    }
    private static var selfTestStarted = false
    /// E-G's one-shot self-test (ThreeDSelfTest): once per (kit manifest sha, build), with 3D on, the kit complete and no film preparing, on a utility queue.
    /// The marker (<models>/selftest-<sha12>-<build>.done) is written by run() before the work; `selfTestStarted` stops a second timer tick racing it. Output goes
    /// through print + fflush, i.e. the same stdout the launch log lines use (AppDelegate dup2s stdout/stderr into gor-log-writer).
    static func maybeSelfTest(enabled: Bool, filmPreparing: Bool) {
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Metal)
        guard enabled, ThreeDSelfTest.interactiveRequested(ProcessInfo.processInfo.environment), !selfTestStarted, let runner = ThreeDRunnerRegistry.runner as? NativePrepareRunner else { return }
        let kit = dir, models = ThreeDModels.modelsDir, build = BuildID.value()
        guard let sha = KitCompiledCache.manifestSha(kitDir: kit) else { return }
        let marker = models.appendingPathComponent(ThreeDSelfTest.markerName(manifestSha: sha, build: build))
        guard ThreeDSelfTest.shouldRun(enabled: enabled, kitPresent: missing(dir: kit).isEmpty, markerExists: FileManager.default.fileExists(atPath: marker.path), filmPreparing: filmPreparing) else { return }
        selfTestStarted = true
        DispatchQueue.global(qos: .utility).async { _ = ThreeDSelfTest.run(runner: runner, kitDir: kit, modelsDir: models, build: build, marker: marker) }
        #endif
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// 190v s13: per-package content_sha256 of the CoreML kit, the same algorithm as tools/depth_analysis/kit_hash.py: for every regular file under the .mlpackage,
/// path relative to the package root (UTF-8, '/'-separated, no './'), sorted BYTEWISE, feed path + NUL + file bytes + NUL. Symlinks are an error, dotfiles count.
/// `verify` checks every package named by the kit manifests in the kit dir (content_sha256 and size_bytes). Not compiled or run on a Mac (CryptoKit path).
enum KitHash {
    private struct Hasher {
        #if canImport(CryptoKit)
        private var h = SHA256()
        mutating func update(_ d: Data) { h.update(data: d) }
        func hex() -> String { h.finalize().map { String(format: "%02x", $0) }.joined() }
        #else
        private var h = SHA256Pure.Hasher()
        mutating func update(_ d: Data) { h.update([UInt8](d)) }
        func hex() -> String { var c = h; return c.hex() }
        #endif
    }

    /// Regular files of a package as (relative path, url), bytewise sorted. nil on a symlink or a non-regular entry.
    static func files(package: URL) -> [(rel: String, url: URL)]? {
        let fm = FileManager.default
        func reject(_ reason: String) -> [(rel: String, url: URL)]? {
            print("3d-kit-read FAIL package=\(package.lastPathComponent) reason=\(reason)"); fflush(stdout); return nil
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        let root: URLResourceValues
        do { root = try package.resourceValues(forKeys: keys) } catch {
            let e = error as NSError; return reject("root_resource_\(e.domain)_\(e.code)")
        }
        guard root.isDirectory == true, root.isSymbolicLink != true else { return reject("root_directory_\(String(describing: root.isDirectory))_symlink_\(String(describing: root.isSymbolicLink))") }
        // Check the selected root for symlinks first, then enumerate its canonical URL.
        // Darwin may canonicalize ancestor aliases for enumerated children but not for
        // the original root URL. Mixing the two spellings rejected every package.
        let canonical = package.resolvingSymlinksInPath().standardizedFileURL
        let base = canonical.path
        var enumerationError: NSError?
        guard let en = fm.enumerator(at: canonical, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in
            enumerationError = error as NSError; return false
        }) else { return reject("enumerator_unavailable") }
        var out: [(rel: String, url: URL)] = []
        for case let u as URL in en {
            let v: URLResourceValues
            do { v = try u.resourceValues(forKeys: keys) } catch {
                let e = error as NSError; return reject("entry_resource_\(e.domain)_\(e.code)")
            }
            if v.isSymbolicLink == true { return reject("symlink_entry") }
            if v.isDirectory == true { continue }
            guard v.isRegularFile == true else { return reject("entry_regular_\(String(describing: v.isRegularFile))_directory_\(String(describing: v.isDirectory))_symlink_\(String(describing: v.isSymbolicLink))") }
            let p = u.standardizedFileURL.path
            guard p.hasPrefix(base + "/") else { return reject("relative_prefix_mismatch") }
            out.append((String(p.dropFirst(base.count + 1)), u))
        }
        if let e = enumerationError { return reject("enumeration_error_\(e.domain)_\(e.code)") }
        return out.sorted { Array($0.rel.utf8).lexicographicallyPrecedes(Array($1.rel.utf8)) }
    }

    /// (hex digest, total bytes of the files) or nil.
    static func contentSha256(package: URL) -> (sha: String, size: Int)? {
        guard let fs = files(package: package) else { return nil }
        var h = Hasher(), size = 0
        for f in fs {
            h.update(Data(f.rel.utf8)); h.update(Data([0]))
            let fh: FileHandle
            do { fh = try FileHandle(forReadingFrom: f.url) } catch {
                let e = error as NSError; print("3d-kit-read FAIL package=\(package.lastPathComponent) reason=file_open_\(e.domain)_\(e.code)"); fflush(stdout); return nil
            }
            defer { try? fh.close() }
            do {
                while let d = try fh.read(upToCount: 1 << 20), !d.isEmpty { h.update(d); size += d.count }
            } catch {
                let e = error as NSError; print("3d-kit-read FAIL package=\(package.lastPathComponent) reason=file_read_\(e.domain)_\(e.code)"); fflush(stdout); return nil
            }
            h.update(Data([0]))
        }
        return (h.hex(), size)
    }

    /// Manifest files in the kit dir: the per-archive kit_manifest.<id>.json copies (gor-fetch-models.sh), else kit_manifest.json.
    static func manifests(kitDir: URL) -> [URL] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: kitDir.path)) ?? []).sorted()
        let per = names.filter { $0.hasPrefix("kit_manifest.") && $0.hasSuffix(".json") && $0 != "kit_manifest.json" }
        return (per.isEmpty ? names.filter { $0 == "kit_manifest.json" } : per).map { kitDir.appendingPathComponent($0) }
    }

    /// Package names whose hash or size does not match (or that are missing); empty = verified. A kit dir with no manifest fails with "kit_manifest.json".
    static func verify(kitDir: URL, archiveID: String? = nil) -> [String] {
        let ms = archiveID.map { [kitDir.appendingPathComponent("kit_manifest." + $0 + ".json")] } ?? manifests(kitDir: kitDir)
        guard !ms.isEmpty else { return ["kit_manifest.json"] }
        var bad: [String] = []
        for m in ms {
            guard let d = try? Data(contentsOf: m), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let pk = j["packages"] as? [String: [String: Any]] else { bad.append(m.lastPathComponent); continue }
            for (name, e) in pk.sorted(by: { $0.key < $1.key }) {
                let id = archiveID ?? (m.lastPathComponent == "kit_manifest.json" ? nil : String(m.lastPathComponent.dropFirst("kit_manifest.".count).dropLast(".json".count)))
                if let id, name.hasPrefix("moge2_") != id.hasPrefix("moge2") { continue }
                let want = e["content_sha256"] as? String, size = (e["size_bytes"] as? NSNumber)?.intValue
                let got = contentSha256(package: kitDir.appendingPathComponent(name))
                guard let got, got.sha == want, got.size == size else {
                    print("3d-kit-verify FAIL package=\(name) expected_sha=\(want ?? "missing") actual_sha=\(got?.sha ?? "unreadable") expected_bytes=\(size.map(String.init) ?? "unknown") actual_bytes=\(got.map { String($0.size) } ?? "unknown")"); fflush(stdout)
                    bad.append(name); continue
                }
            }
        }
        return bad
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(CoreML)
import CoreML
import Darwin
#endif

/// Compiled-model cache (Main 09:03 decision c): `<models>/kit-compiled/<manifest sha>/<package>.mlmodelc`. CoreML compiles an .mlpackage into a temp .mlmodelc on every
/// MLModel.compileModel call; the cache keeps one compiled copy per kit version, so a new kit manifest (new sha) never reuses a stale compile, and old versions are pruned.
/// The pure parts (key, path, prune choice) are tested on Linux; the CoreML compile is parse-only.
enum KitCompiledCache {
    /// Set by the runner when it opens a kit: `<models>/kit-compiled/<sha>`. nil = no cache (compile to temp each time, as before).
    static var dir: URL?

    /// sha256 of kit_manifest.json bytes: the cache key.
    static func manifestSha(kitDir: URL) -> String? {
        guard let d = try? Data(contentsOf: kitDir.appendingPathComponent("kit_manifest.json")) else { return nil }
        var h = SHA256Pure.Hasher(); h.update([UInt8](d)); return h.hex()
    }
    static func cacheDir(modelsDir: URL, sha: String) -> URL { modelsDir.appendingPathComponent("kit-compiled", isDirectory: true).appendingPathComponent(sha, isDirectory: true) }
    static func compiledName(_ package: URL) -> String { package.deletingPathExtension().lastPathComponent + ".mlmodelc" }
    /// Version directories to delete: every child of kit-compiled except `keep`.
    static func stale(children: [String], keep: String) -> [String] { children.filter { $0 != keep && !$0.hasPrefix(".") } }
    static func prune(modelsDir: URL, keep sha: String) {
        let root = modelsDir.appendingPathComponent("kit-compiled", isDirectory: true)
        for n in stale(children: (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [], keep: sha) { try? FileManager.default.removeItem(at: root.appendingPathComponent(n)) }
    }

    #if canImport(CoreML)
    static let probeFlag = "--gor-model-load-probe"
    /// Headless one-use child. Owns the model until exit; no app/window/settings/cache mutations.
    static func probeCLI(arguments: [String]) -> Int32? {
        guard let at = arguments.firstIndex(of: probeFlag) else { return nil }
        PrepareProcessLifetime.watchOwner(arguments: arguments)
        guard arguments.count == at + 3 || arguments.count == at + 5 else { return 64 }
        let units: MLComputeUnits
        switch arguments[at + 2] {
        case "all": units = .all
        case "cpuAndGPU": units = .cpuAndGPU
        case "cpuOnly": units = .cpuOnly
        default: return 64
        }
        let cfg = MLModelConfiguration(); cfg.computeUnits = units
        do {
            let model = try MLModel(contentsOf: URL(fileURLWithPath: arguments[at + 1]), configuration: cfg)
            withExtendedLifetime(model) { print("3d-load-probe loaded device=\(arguments[at + 2])"); fflush(stdout) }
            return 0
        } catch { print("3d-load-probe error device=\(arguments[at + 2]) error=\(error)"); fflush(stdout); return 2 }
    }
    /// A child is genuinely killable. Do not touch CoreML in the parent unless this child exited0.
    private static func probe(_ compiled: URL, device: String, seconds: Double = 30) -> Bool {
        guard let exe = Bundle.main.executableURL else { return false }
        let child = Process(); child.executableURL = exe
        child.arguments = [probeFlag, compiled.path, device, PrepareProcessLifetime.ownerFlag, String(ProcessInfo.processInfo.processIdentifier)]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.standardOutput; child.standardError = FileHandle.standardError
        let start = Date()
        do { try child.run() } catch { return false }
        let until = Date().addingTimeInterval(seconds)
        while child.isRunning && Date() < until { Thread.sleep(forTimeInterval: 0.05) }
        if child.isRunning {
            kill(child.processIdentifier, SIGKILL)
            let reapUntil = Date().addingTimeInterval(2)
            while child.isRunning && Date() < reapUntil { Thread.sleep(forTimeInterval: 0.01) }
            print("3d-load-probe timeout device=\(device) limit_s=\(Int(seconds)) killed=yes"); fflush(stdout)
            return false
        }
        let ok = child.terminationReason == .exit && child.terminationStatus == 0
        print("3d-load-probe end device=\(device) elapsed_ms=\(Int(Date().timeIntervalSince(start)*1000)) outcome=\(ok ? "loaded" : "failed")"); fflush(stdout)
        return ok
    }
    private static let loadLock = NSLock()
    private static var timedOutDevices = Set<String>()
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    private static var cpuOnlyFirst = false
    static func preferCPUOnlyFirst() { loadLock.lock(); cpuOnlyFirst = true; loadLock.unlock() }
    /// Each device gets at most one timed-out call per process. Late results never enter the model cache.
    static func model(_ u: URL) -> MLModel? { modelWithDevice(u)?.model }
    /// Same chain as model(_:) plus the device that won, for callers whose inference bound depends on it (DAV2 retire).
    static func modelWithDevice(_ u: URL) -> (model: MLModel, device: String)? {
        let compiled = loadable(u)
        loadLock.lock(); let cpuFirst = cpuOnlyFirst || ProcessInfo.processInfo.environment["GOR_3D_CPU_FIRST"] == "1"; loadLock.unlock()
        let devices: [(String, MLComputeUnits)] = cpuFirst ? [("cpuOnly", .cpuOnly), ("cpuAndGPU", .cpuAndGPU), ("all", .all)] : [("all", .all), ("cpuAndGPU", .cpuAndGPU), ("cpuOnly", .cpuOnly)]
        for (name, units) in devices {
            loadLock.lock(); let skip = timedOutDevices.contains(name); loadLock.unlock()
            if skip { print("3d-load skip device=\(name) reason=previous_timeout"); fflush(stdout); continue }
            guard probe(compiled, device: name) else {
                loadLock.lock(); timedOutDevices.insert(name); loadLock.unlock()
                continue
            }
            let start = Date()
            print("3d-load begin package=\(u.lastPathComponent) device=\(name) limit_s=30"); fflush(stdout)
            let result = ThreeDStageLog.time("load " + u.lastPathComponent + " (computeUnits " + name + ")") {
                BoundedLoad.attempt(seconds: 30) {
                    let cfg = MLModelConfiguration(); cfg.computeUnits = units
                    return try? MLModel(contentsOf: compiled, configuration: cfg)
                }
            }
            print("3d-load end package=\(u.lastPathComponent) device=\(name) elapsed_ms=\(Int(Date().timeIntervalSince(start) * 1000)) outcome=\(result.timedOut ? "timeout" : (result.value == nil ? "error" : "loaded"))"); fflush(stdout)
            if result.timedOut { loadLock.lock(); timedOutDevices.insert(name); loadLock.unlock() }
            if let model = result.value { return (model, name) }
        }
        return nil
    }

    /// The loadable URL for `u`: a non-.mlpackage is returned as is; a package is served from the cache, compiled into it on a miss (compile to temp, copy into
    /// `.part`, rename, so a crash never leaves a half-copied model). Falls back to the temp compile (or the package itself) when the cache is unavailable.
    static func loadable(_ u: URL) -> URL {
        guard u.pathExtension == "mlpackage" else { return u }
        let fm = FileManager.default
        if let d = dir {
            let hit = d.appendingPathComponent(compiledName(u))
            if fm.fileExists(atPath: hit.path) { ThreeDStageLog.done("compile " + u.lastPathComponent + " (cache hit)", ms: 0); return hit }
            if let tmp = ThreeDStageLog.time("compile " + u.lastPathComponent, { try? MLModel.compileModel(at: u) }) {
                try? fm.createDirectory(at: d, withIntermediateDirectories: true)
                let part = d.appendingPathComponent(compiledName(u) + ".part")
                try? fm.removeItem(at: part)
                if (try? fm.copyItem(at: tmp, to: part)) != nil, (try? fm.moveItem(at: part, to: hit)) != nil { return hit }
                return tmp
            }
            return u
        }
        return (try? MLModel.compileModel(at: u)) ?? u
    }
    #endif
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(CoreML)
import CoreML

/// Which compute devices CoreML plans to use for a model (self-test log). Uses MLComputePlan (macOS 14.4+): per operation `deviceUsage(for:)`, summarised as op counts per
/// preferred device. This is the PLAN, not a runtime trace (the public API has no per-prediction device report); the log says "plan". UNVERIFIED on a Mac: the
/// MLComputePlan names below are from memory, so every failure path returns a readable string instead of throwing.
enum ComputeUnitsProbe {
    static func summary(of compiledOrPackage: URL, units: MLComputeUnits = .all) -> String {
        guard #available(macOS 14.4, *) else { return "unavailable (macOS < 14.4)" }
        let u = KitCompiledCache.loadable(compiledOrPackage)
        let cfg = MLModelConfiguration(); cfg.computeUnits = units
        var result = "unavailable (load did not finish)"
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let plan = try await MLComputePlan.load(contentsOf: u, configuration: cfg)
                guard case .program(let program) = plan.modelStructure, let main = program.functions["main"] else { result = "unavailable (not an ML program)"; sem.signal(); return }
                var counts: [String: Int] = [:]
                for op in main.block.operations {
                    let name: String
                    switch plan.deviceUsage(for: op)?.preferred {
                    case .some(let d) where d is MLNeuralEngineComputeDevice: name = "ane"
                    case .some(let d) where d is MLGPUComputeDevice: name = "gpu"
                    case .some(let d) where d is MLCPUComputeDevice: name = "cpu"
                    default: name = "none"
                    }
                    counts[name, default: 0] += 1
                }
                result = "plan ops " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            } catch { result = "unavailable (\(error))" }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 60)
        return result
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 195y G2: the DepthModelID enum lives in THIS file (relocated span below, still pure Foundation, outside the CoreML gate; Delivery A: PrepareSupport needs it without the CoreML gate).


#if canImport(CoreML) && canImport(Vision)
import CoreML
import Vision

/// 195h A: Depth Anything V2 Small (CoreML F16) runner behind DepthModelID.dav2_small_coreml. Loads ONLY when the package exists in the
/// models directory (fetched, sha-verified, never committed); never a build dependency and never loaded by default. The pinned package's
/// spec (Manifest + model description): input "image" (image; shorter side 518, larger a multiple of 14), output "depth" (a grayscale
/// IMAGE - "Estimated depth map, as a grayscale output image"), relative disparity (larger = nearer). UNCOMPILED AND UNRUN here (no Mac):
/// Vision/CoreML calls are parse-only, same convention as NativePrepareRunner/VDAWindowRunner.
final class CoreMLDepthRunner {
    static let packageName = "DepthAnythingV2SmallF16.mlpackage"
    /// Where tools/gor-fetch-models.sh reconstructs the package from the models.lock.tsv rows: <modelsDir>/<repo>/<file>.
    static func packageURL(modelsDir: URL) -> URL { modelsDir.appendingPathComponent("apple/coreml-depth-anything-v2-small").appendingPathComponent(packageName) }
    static func available(modelsDir: URL) -> Bool { FileManager.default.fileExists(atPath: packageURL(modelsDir: modelsDir).path) }
    private let model: MLModel
    private let device: String
    private let deadLock = NSLock()
    /// Set after a bounded inference timeout: a second perform on the same model would race the abandoned thread, so
    /// this runner never touches CoreML again and every frame honestly returns nil.
    private var dead = false
    init?(modelsDir: URL) {
        guard Self.available(modelsDir: modelsDir), let m = KitCompiledCache.modelWithDevice(Self.packageURL(modelsDir: modelsDir)) else { return nil }
        model = m.model; device = m.device
    }
    /// One BGRA pixel buffer -> relative disparity floats (w*h, row-major, larger = nearer), nil on any model failure. The output is
    /// verified to be a grayscale pixel buffer in a layout this runner actually decodes - OneComponent32Float or OneComponent16Half
    /// (the pinned package's declared grayscale image output); ANY other observation kind or pixel format is rejected, never inferred.
    func run(pixelBuffer: CVPixelBuffer) -> (depth: [Float], w: Int, h: Int)? {
        deadLock.lock(); let retired = dead; deadLock.unlock()
        guard !retired,
              model.modelDescription.inputDescriptionsByName.values.contains(where: { $0.type == .image }),
              let vn = try? VNCoreMLModel(for: model) else { return nil }
        var out: (depth: [Float], w: Int, h: Int)?
        let req = VNCoreMLRequest(model: vn) { r, e in
            guard e == nil, let first = r.results?.first as? VNPixelBufferObservation else { return }
            let pb = first.pixelBuffer
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
            let fmt = CVPixelBufferGetPixelFormatType(pb)
            // Verified layouts only: 32-bit float or 16-bit half, one component, row stride from bytesPerRow.
            let elemBytes: Int
            if fmt == kCVPixelFormatType_OneComponent32Float { elemBytes = 4 } else if fmt == kCVPixelFormatType_OneComponent16Half { elemBytes = 2 } else { return }
            CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            var v = [Float](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<w {
                let p = base.advanced(by: y * bpr + x * elemBytes)
                v[y * w + x] = elemBytes == 4 ? p.bindMemory(to: Float.self, capacity: 1).pointee
                                              : HalfFloat.toFloat(p.bindMemory(to: UInt16.self, capacity: 1).pointee)
            } }
            out = (v, w, h)
        }
        req.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        let attempt = BoundedLoad.attempt(seconds: 30) { () -> Bool? in (try? handler.perform([req])) != nil ? true : nil }
        if attempt.timedOut {
            deadLock.lock(); dead = true; deadLock.unlock()
            if device != "cpuOnly" { KitCompiledCache.preferCPUOnlyFirst() }
            print("dav2-infer timeout device=\(device) limit_s=30 action=runner-retired cpuOnly_first=\(device != "cpuOnly")"); fflush(stdout)
            return nil
        }
        guard attempt.value == true else { return nil }
        return out
    }
    /// Mac self-test line (scope-add item 5), wired into ThreeDSelfTest when the DAV2 experiment is selected: runs `frames` once each
    /// and reports "dav2_small_coreml self-test ms/frame <ms> (WxH)". nil when fewer than one frame succeeds.
    func selfTest(frames: [CVPixelBuffer]) -> String? {
        var ok = 0, wh = "", t0 = CFAbsoluteTimeGetCurrent()
        for f in frames { if let r = run(pixelBuffer: f) { ok += 1; wh = "(\(r.w)x\(r.h))" } }
        guard ok > 0 else { return nil }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0 / Double(ok)
        return "dav2_small_coreml self-test ms/frame \(String(format: "%.1f", ms)) \(wh)"
    }
}

/// 195h A (item 1): the DAV2-Small CoreML backend for the prepared-depth producer (ShotPrepareBackend, plugged in NativePrepareRunner,
/// never ThreeDSynthMethod). Per-frame monocular relative depth: disparity -> depth 1/max(d,eps), bilinear-resized onto the job's depth
/// grid (the same letterboxed grid the VDA path emits, so sidecar/render geometry is uniform). Stateless per frame, so its checkpoint
/// `window` carries ONLY the temporal-EMA accumulator (item 3, exact resume through the GORCK003 checkpoint); a fresh backend per shot
/// is the shot-boundary reset. MoGe metric keyframes: none (nil) - ShotPrepareAssembly already degrades honestly when mogeKeyframe
/// returns nil. UNCOMPILED AND UNRUN here (no Mac), same convention as NativeShotBackend.
final class DAV2Backend: ShotPrepareBackend {
    private let runner: CoreMLDepthRunner
    private let pixels: (Int) -> CVPixelBuffer?
    private let outW: Int, outH: Int
    private let ema: ModelDepthEMA?
    init(runner: CoreMLDepthRunner, pixels: @escaping (Int) -> CVPixelBuffer?, outW: Int, outH: Int, ema: ModelDepthEMA?) {
        self.runner = runner; self.pixels = pixels; self.outW = outW; self.outH = outH; self.ema = ema
    }
    var window: VDAWindowState {
        get { var w = VDAWindowState(); w.setState(id: 0, list: ema.map { [$0.stateBundles] } ?? []); return w }
        set { ema?.restore(bundles: newValue.list.first?.first.map { [$0] } ?? []) }
    }
    func vdaStep(frame: Int) -> [Float]? {
        guard let pb = pixels(frame), let r = runner.run(pixelBuffer: pb) else { return nil }
        let depth = DepthMapResize.disparityToDepth(r.depth)
        let sized = DepthMapResize.bilinear(depth, w: r.w, h: r.h, outW: outW, outH: outH)
        return ema?.apply(sized) ?? sized
    }
    func mogeKeyframe(frame: Int) -> MoGeKeyframe? { nil }
}
#endif

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum DepthModelID: String {
    case luma_y_prior, dav2_small_coreml
    private static let lock = NSLock()
    private static var current: DepthModelID = .luma_y_prior
    /// The single selection point (lock-backed, 195h r2-3 convention). Default luma_y_prior: the existing producer, byte-identical behaviour.
    static func selected() -> DepthModelID { lock.lock(); defer { lock.unlock() }; return current }
    static func select(_ m: DepthModelID) { lock.lock(); current = m; lock.unlock() }
}
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// S1 (A-D parity plan 14:50): the nunif iw3 pre/post-model math as pure Foundation Swift, a port of tools/depth_analysis/kit/nunif_pipeline_reference.py (batch 1, float32 like the fixture).
/// Feature values, input channels, backward warp (grid_sample bilinear / border / align_corners), mlbw delta weighting, hole-mask postprocess (closing, resize, sigmoid, 0.15, inner/outer dilation),
/// k15 gaussian (sigma 2.6) + inpaint preprocess, and the video window plan (head edge-clamped x4, tail replicated, emit slices; A-D confirmed against upstream base_inpaint.py).
/// Linux-tested against nunif_pipeline_fixture.npz (max-abs table); NOT yet used by a runner (the CoreML runner stages S2+ need the Mac). Supersedes NunifMath.videoWindows, whose head clamp was my unverified reading.
enum NunifPipeline {
    /// [C,H,W] float32 planar tensor (batch 1).
    struct T { var c: Int, h: Int, w: Int, d: [Float]
        init(c: Int, h: Int, w: Int, fill: Float = 0) { self.c = c; self.h = h; self.w = w; d = [Float](repeating: fill, count: c * h * w) }
        init(c: Int, h: Int, w: Int, data: [Float]) { self.c = c; self.h = h; self.w = w; d = data }
        @inline(__always) func at(_ ch: Int, _ y: Int, _ x: Int) -> Float { d[(ch * h + y) * w + x] }
        @inline(__always) mutating func set(_ ch: Int, _ y: Int, _ x: Int, _ v: Float) { d[(ch * h + y) * w + x] = v }
    }

    // 1. feature values (iw3/backward_warp.py:10-16, image_width = max(H, W)); depth is fed AS-IS (no remap).
    static func featureValues(divergence: Double, convergence: Double, imageWidth: Int) -> (Float, Float) {
        let pix = divergence * 0.5 * 0.01 * Double(imageWidth)
        return (Float(pix / 32.0), Float((-pix * convergence) / 32.0))
    }
    static func inputTensor(depth: [Float], h: Int, w: Int, divergence: Double, convergence: Double) -> T {
        let (dv, cv) = featureValues(divergence: divergence, convergence: convergence, imageWidth: max(h, w))
        var t = T(c: 3, h: h, w: w); t.d.replaceSubrange(0..<(h * w), with: depth)
        for i in 0..<(h * w) { t.d[h * w + i] = dv; t.d[2 * h * w + i] = cv }
        return t
    }

    // 2. warp convention
    static func makeGrid(h: Int, w: Int) -> T {
        var g = T(c: 2, h: h, w: w)
        for y in 0..<h { let gy = h == 1 ? -1.0 : -1.0 + 2.0 * Double(y) / Double(h - 1)
            for x in 0..<w { let gx = w == 1 ? -1.0 : -1.0 + 2.0 * Double(x) / Double(w - 1); g.set(0, y, x, Float(gx)); g.set(1, y, x, Float(gy)) } }
        return g
    }
    /// delta_x [C,H,W] -> [2C,H,W]: channel 2i = delta_x[i], 2i+1 = 0.
    static func padDeltaY(_ dx: T) -> T {
        var o = T(c: dx.c * 2, h: dx.h, w: dx.w)
        for i in 0..<dx.c { o.d.replaceSubrange((2 * i * dx.h * dx.w)..<((2 * i + 1) * dx.h * dx.w), with: dx.d[(i * dx.h * dx.w)..<((i + 1) * dx.h * dx.w)]) }
        return o
    }
    static func deltaScale(width: Int) -> Float { Float(1.0 / Double(width / 2 - 1)) }
    /// F.grid_sample(bilinear, padding border, align_corners True); `grid` [2,H,W] in -1..1.
    static func gridSample(_ c: T, grid: T) -> T {
        var o = T(c: c.c, h: c.h, w: c.w)
        let wm1 = Float(c.w - 1), hm1 = Float(c.h - 1)
        for y in 0..<c.h { for x in 0..<c.w {
            var gx = (grid.at(0, y, x) + 1.0) * wm1 / 2.0, gy = (grid.at(1, y, x) + 1.0) * hm1 / 2.0
            gx = min(max(gx, 0), wm1); gy = min(max(gy, 0), hm1)
            let fx = gx.rounded(.down), fy = gy.rounded(.down)
            let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, c.w - 1), y1 = min(y0 + 1, c.h - 1)
            let wx = gx - fx, wy = gy - fy
            for ch in 0..<c.c {
                let ia = c.at(ch, y0, x0), ib = c.at(ch, y1, x0), ic = c.at(ch, y0, x1), id = c.at(ch, y1, x1)
                o.set(ch, y, x, ia * (1 - wx) * (1 - wy) + ic * wx * (1 - wy) + ib * (1 - wx) * wy + id * wx * wy)
            }
        } }
        return o
    }
    /// iw3 apply_divergence_nn_delta_weight (mlbw): sum_i warp(c, grid + delta_i * scale) * weight_i, clamp 0..1. `layerWeight` [L,H,W].
    static func applyMlbwDeltaWeight(c: T, deltaX: T, layerWeight: T, layers: Int) -> T {
        let delta = padDeltaY(deltaX), grid = makeGrid(h: c.h, w: c.w), ds = deltaScale(width: c.w)
        var z = T(c: c.c, h: c.h, w: c.w)
        for i in 0..<layers {
            var g = grid
            for y in 0..<c.h { for x in 0..<c.w { g.set(0, y, x, g.at(0, y, x) + delta.at(2 * i, y, x) * ds); g.set(1, y, x, g.at(1, y, x) + delta.at(2 * i + 1, y, x) * ds) } }
            let s = gridSample(c, grid: g)
            for ch in 0..<c.c { for y in 0..<c.h { for x in 0..<c.w { z.set(ch, y, x, z.at(ch, y, x) + s.at(ch, y, x) * layerWeight.at(i, y, x)) } } }
        }
        for i in 0..<z.d.count { z.d[i] = min(max(z.d[i], 0), 1) }
        return z
    }

    // 3. hole mask (iw3/backward_warp.py:529-539, iw3/dilation.py)
    static func grayDilate(_ m: T, k: Int = 3) -> T {
        let r = k / 2; var o = m
        for ch in 0..<m.c { for y in 0..<m.h { for x in 0..<m.w {
            var v = -Float.greatestFiniteMagnitude
            for dy in -r...r { for dx in -r...r { v = max(v, m.at(ch, min(max(y + dy, 0), m.h - 1), min(max(x + dx, 0), m.w - 1))) } }
            o.set(ch, y, x, v) } } }
        return o
    }
    static func grayErode(_ m: T) -> T {
        var n = m; for i in 0..<n.d.count { n.d[i] = -n.d[i] }
        var e = grayDilate(n); for i in 0..<e.d.count { e.d[i] = -e.d[i] }
        return e
    }
    // closing = dilate then erode (iw3/dilation.py:63-70)
    static func closingDE(_ m: T) -> T { grayErode(grayDilate(m)) }
    static func resizeBilinearAlignCorners(_ x: T, h th: Int, w tw: Int) -> T {
        if x.h == th && x.w == tw { return x }
        var o = T(c: x.c, h: th, w: tw)
        for ch in 0..<x.c { for y in 0..<th { for xx in 0..<tw {
            let sy = th == 1 ? 0 : Double(y) * Double(x.h - 1) / Double(th - 1), sx = tw == 1 ? 0 : Double(xx) * Double(x.w - 1) / Double(tw - 1)
            let y0 = Int(sy.rounded(.down)), x0 = Int(sx.rounded(.down)), y1 = min(y0 + 1, x.h - 1), x1 = min(x0 + 1, x.w - 1)
            let wy = Float(sy - Double(y0)), wx = Float(sx - Double(x0))
            o.set(ch, y, xx, x.at(ch, y0, x0) * (1 - wy) * (1 - wx) + x.at(ch, y0, x1) * (1 - wy) * wx + x.at(ch, y1, x0) * wy * (1 - wx) + x.at(ch, y1, x1) * wy * wx)
        } } }
        return o
    }
    static func scaledIter(_ n: Int, width: Int, base: Int) -> Int { max(Int((Double(width) / Double(base) * Double(n)).rounded(.toNearestOrEven)), 1) }
    /// inner: m[x] |= m[x+1]; outer: m[x] |= m[x-1] (iw3/dilation.py:73-102).
    static func dilate(_ m: [Bool], h: Int, w: Int, iter: Int, inner: Bool) -> [Bool] {
        var cur = m
        for _ in 0..<iter { var nx = cur
            for y in 0..<h { for x in 0..<w { let nb = inner ? (x + 1 < w ? cur[y * w + x + 1] : false) : (x > 0 ? cur[y * w + x - 1] : false); nx[y * w + x] = cur[y * w + x] || nb } }
            cur = nx }
        return cur
    }
    /// `logits` [1,H,W]; returns the boolean hole mask at (th, tw).
    static func postprocessHoleMask(logits: T, th: Int, tw: Int, threshold: Float = 0.15, innerDilation: Int = 0, outerDilation: Int = 0) -> [Bool] {
        var m = closingDE(logits)
        if th != m.h || tw != m.w { m = resizeBilinearAlignCorners(m, h: th, w: tw) }
        var b = m.d.map { (value: Float) -> Bool in
            let exponential: Float = Float(exp(Double(-value)))
            let probability: Float = 1.0 / (1.0 + exponential)
            return probability > threshold
        }
        if innerDilation > 0 { b = dilate(b, h: th, w: tw, iter: scaledIter(innerDilation, width: tw, base: logits.w), inner: true) }
        if outerDilation > 0 { b = dilate(b, h: th, w: tw, iter: scaledIter(outerDilation, width: tw, base: logits.w), inner: false) }
        return b
    }

    // 4. gaussian k15 + inpaint preprocess (nunif/modules/gaussian_filter.py, iw3/models/light_inpaint_v1.py:91-105)
    static func gaussianKernel1D(_ k: Int = 15) -> [Float] {
        let sigma = Double(k) * 0.15 + 0.35, half = Double(k - 1) * 0.5
        let v: [Double] = (0..<k).map { (index: Int) -> Double in
            let offset: Double = -half + Double(index) * (2 * half) / Double(k - 1)
            let normalized: Double = offset / sigma
            return exp(-0.5 * pow(normalized, 2))
        }
        let s = v.reduce(0, +); return v.map { Float($0 / s) }
    }
    static func gaussianBlur(_ m: T, k: Int = 15) -> T {
        let ker = gaussianKernel1D(k), r = k / 2
        func pass(_ s: T, horizontal: Bool) -> T {
            var o = s
            for ch in 0..<s.c { for y in 0..<s.h { for x in 0..<s.w {
                var acc: Float = 0
                for j in 0..<k { let o_ = j - r
                    let yy = horizontal ? y : min(max(y + o_, 0), s.h - 1), xx = horizontal ? min(max(x + o_, 0), s.w - 1) : x
                    acc += ker[j] * s.at(ch, yy, xx) }
                o.set(ch, y, x, acc) } } }
            return o
        }
        return pass(pass(m, horizontal: true), horizontal: false)
    }
    /// x [3,H,W], mask [1,H,W] in 0..1 (inner/outer dilation 0): returns (x * (1 - m), clamp(blur(m) + m, 0, 1)).
    static func inpaintPreprocess(x: T, mask: T) -> (T, T) {
        var xm = x
        for ch in 0..<x.c { for i in 0..<(x.h * x.w) { xm.d[ch * x.h * x.w + i] = x.d[ch * x.h * x.w + i] * (1 - mask.d[i]) } }
        var b = gaussianBlur(mask)
        for i in 0..<b.d.count { b.d[i] = min(max(b.d[i] + mask.d[i], 0), 1) }
        return (xm, b)
    }

    /// iw3 default depth scaling (utils.py minmax_normalize_chw / SimpleMinMaxScaler, ema_normalize off): each FRAME is min-max normalised to [0,1] on its own before the warp. Raw VDA range (0.045..16.6) fed
    /// as-is gives dense vertical comb striping (A-D X2 README). A flat frame (max == min, or no finite value) maps to zeros; non-finite values map to 0. No cross-frame state, no EMA.
    static func minmaxNormalize(_ z: [Float]) -> [Float] {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in z where v.isFinite { lo = min(lo, v); hi = max(hi, v) }
        guard hi > lo else { return [Float](repeating: 0, count: z.count) }
        let r = hi - lo
        return z.map { $0.isFinite ? min(max(($0 - lo) / r, 0), 1) : 0 }
    }

    // 5. video windows (iw3/base_inpaint.py:407-743 via the reference video_windows)
    static let seqLen = 12, prePad = 3, postPad = 3, step = 6
    static func videoWindows(frames n: Int) -> [(idx: [Int], emit: Range<Int>)] {
        var plan: [(idx: [Int], emit: Range<Int>)] = []
        guard n > 0 else { return plan }
        var q = [Int](repeating: 0, count: prePad + 1); var i = 1
        while i < n { q.append(i); i += 1
            if q.count == seqLen { plan.append((q, prePad..<(seqLen - postPad))); q = Array(q[step...]) } }
        if !q.isEmpty { let pad = seqLen - q.count; while q.count < seqLen { q.append(q[q.count - 1]) }; plan.append((q, prePad..<(seqLen - pad))) }
        return plan
    }
}

// BEGIN relocated NunifMath.swift (195y G2, behavior unchanged)
/// 190w W3: the well-defined runner-side math of the nunif CoreML kit (A-D contract): replicate-pad H,W up to a multiple of 96 and crop back, and the align_corners=True bilinear resize of
/// layer_weight. Pure Foundation, Linux-tested (Tests/NunifMath). Everything model-specific (input channels, hole preprocess, 3+3 video overlap) is NOT here: no runner exists yet.
enum NunifMath {
    static let block = 96
    static func paddedSize(_ n: Int) -> Int { n <= 0 ? 0 : ((n + block - 1) / block) * block }
    /// One CHW plane stack (c planes of h*w) -> c planes of ph*pw, bottom/right replicate (iw3 pads right/bottom; the crop is the top-left h*w).
    static func padReplicate(_ x: [Float], c: Int, h: Int, w: Int) -> (data: [Float], h: Int, w: Int)? {
        guard h > 0, w > 0, c > 0, x.count == c * h * w else { return nil }
        let ph = paddedSize(h), pw = paddedSize(w)
        var out = [Float](repeating: 0, count: c * ph * pw)
        for ch in 0..<c { for y in 0..<ph { let sy = min(y, h - 1); for xx in 0..<pw { out[(ch * ph + y) * pw + xx] = x[(ch * h + sy) * w + min(xx, w - 1)] } } }
        return (out, ph, pw)
    }
    static func crop(_ x: [Float], c: Int, ph: Int, pw: Int, h: Int, w: Int) -> [Float]? {
        guard h <= ph, w <= pw, x.count == c * ph * pw else { return nil }
        var out = [Float](); out.reserveCapacity(c * h * w)
        for ch in 0..<c { for y in 0..<h {
            let start: Int = (ch * ph + y) * pw
            let end: Int = start + w
            out.append(contentsOf: x[start..<end])
        } }
        return out
    }
    /// torch F.interpolate(mode="bilinear", align_corners=True) on one plane (no antialias; A-D's contract also names antialias for downscales: NOT implemented, down-scaling returns nil).
    static func resizeBilinearAligned(_ p: [Float], h: Int, w: Int, toH: Int, toW: Int) -> [Float]? {
        guard h > 0, w > 0, toH >= h, toW >= w, p.count == h * w else { return nil }
        var out = [Float](repeating: 0, count: toH * toW)
        for y in 0..<toH {
            let fy = toH == 1 ? 0 : Float(y) * Float(h - 1) / Float(toH - 1), y0 = Int(fy), y1 = min(y0 + 1, h - 1), ty = fy - Float(y0)
            for x in 0..<toW {
                let fx = toW == 1 ? 0 : Float(x) * Float(w - 1) / Float(toW - 1), x0 = Int(fx), x1 = min(x0 + 1, w - 1), tx = fx - Float(x0)
                let a = p[y0 * w + x0] * (1 - tx) + p[y0 * w + x1] * tx, b = p[y1 * w + x0] * (1 - tx) + p[y1 * w + x1] * tx
                out[y * toW + x] = a * (1 - ty) + b * ty
            }
        }
        return out
    }

    // MARK: video inpaint windows (BaseVideoInpaint, SEQ_LEN 12, pre/post padding 3)
    static let seqLen = 12, pad = 3, centre = seqLen - 2 * pad     // 6 frames kept per window
    /// Windows over n frames: window w runs the model on seqLen frames starting at w*centre - pad (indices clamped to [0, n-1] = edge replication, which also covers the non-multiple-of-12 tail),
    /// and keeps its centre `centre` frames [w*centre, w*centre + centre) (the last window keeps up to n). READING of the contract's "3 + 3 overlap, pre/post padding 3": UNVERIFIED vs upstream BaseVideoInpaint.
    static func videoWindows(frameCount n: Int) -> [(input: [Int], keep: Range<Int>)] {
        guard n > 0 else { return [] }
        return (0..<((n + centre - 1) / centre)).map { w in
            let s = w * centre
            return ((0..<seqLen).map { min(max(s - pad + $0, 0), n - 1) }, s..<min(s + centre, n))
        }
    }
    /// Hole mask binarisation at MASK_MLBW_THRESHOLD (0.15) on a probability map (sigmoid already applied by the caller).
    static let maskThreshold: Float = 0.15
    static func holeMask(prob: [Float]) -> [Float] { prob.map { $0 > maskThreshold ? 1 : 0 } }
    /// Masked-RGB input of the inpaint packages: x * (1 - mask) per channel (mask is 1 plane of h*w, x is c planes).
    static func maskedInput(x: [Float], mask: [Float], c: Int) -> [Float]? {
        guard c > 0, !mask.isEmpty, x.count == c * mask.count else { return nil }
        let n = mask.count; var out = x
        for ch in 0..<c { for i in 0..<n { out[ch * n + i] = x[ch * n + i] * (1 - mask[i]) } }
        return out
    }
}
// END relocated NunifMath.swift

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum SynthMethod: String, CaseIterable {
    case mlbw_l2_inpaint_video, mlbw_l2_inpaint, row_flow_v3, dibr_golden

    /// Weight files per learned tier (nunif manifest, corrected map from A-D 14:09; the ".pth" extension is assumed from nunif, unverified until the v2 kit is unpacked):
    /// T1 video = mask_mlbw_l2_d1 + light_video_inpaint_v1, T2 inpaint = mask_mlbw_l2_d1 + light_inpaint_v1, T3 row_flow_v3. A tier needs ALL its files.
    var weightFiles: [String] {
        switch self {
        case .mlbw_l2_inpaint_video: return ["iw3_mask_mlbw_l2_d1_20250903.pth", "iw3_light_video_inpaint_v1_20250919.pth"]
        case .mlbw_l2_inpaint: return ["iw3_mask_mlbw_l2_d1_20250903.pth", "iw3_light_inpaint_v1_20250919.pth"]
        case .row_flow_v3: return ["iw3_row_flow_v3_20250627.pth"]
        case .dibr_golden: return []
        }
    }
    /// Tiers whose runner exists in this build. Add a case here only together with the code that runs it.
    static let implemented: Set<SynthMethod> = [.dibr_golden]

    struct Choice: Equatable { let method: SynthMethod; let note: String }

    /// Highest tier (T1 > T2 > T3) that is present and implemented; otherwise dibr_golden, with a note that says why it is a fallback.
    static func select(present: Set<SynthMethod>, implemented: Set<SynthMethod> = SynthMethod.implemented) -> Choice {
        for m in [SynthMethod.mlbw_l2_inpaint_video, .mlbw_l2_inpaint, .row_flow_v3] where present.contains(m) && implemented.contains(m) { return Choice(method: m, note: "3D: view synthesis \(m.rawValue)") }
        let learned = present.filter { $0 != .dibr_golden }
        let why = learned.isEmpty ? "no learned weights installed" : "learned weights present but this build has no runner for them"
        return Choice(method: .dibr_golden, note: "3D: view synthesis dibr_golden (fallback: \(why))")
    }

    static func present(modelsDir: URL, fm: FileManager = .default) -> Set<SynthMethod> {
        let nd = modelsDir.appendingPathComponent("nunif")
        var out = Set<SynthMethod>([.dibr_golden])
        for m in allCases where !m.weightFiles.isEmpty && m.weightFiles.allSatisfy({ fm.fileExists(atPath: nd.appendingPathComponent($0).path) }) { out.insert(m) }
        return out
    }
}
// END relocated ThreeDSynthMethod.swift

// BEGIN relocated ThreeDSynthCurrent.swift (195y G2, behavior unchanged)
/// 190w W3: the method this process renders with (see SynthMethod's honesty rule). Cached: the models dir does not change while the app runs.
extension SynthMethod {
    private static var cached: Choice?
    private static let lock = NSLock()
    static var current: Choice {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        let c = select(present: present(modelsDir: ThreeDModels.modelsDir)); cached = c; return c
    }
}
// END relocated ThreeDSynthCurrent.swift

// BEGIN relocated NunifCoreMLRunner.swift (195y G2, behavior unchanged)
#if canImport(CoreML)
import CoreML

/// S2 (A-D parity plan): thin CoreML runner for the iw3-nunif-coreml kit packages (NUNIF-COREML-RUNNER-CONTRACT.md). One package = one MLModel; inputs/outputs are flat float arrays by feature name.
/// CONVERTED on Linux, NEVER EXECUTED: nothing here has run on a Mac. `parity(...)` is the self-test hook: run a package on the fixture's seeded `in_*` and return the max |out - out_ref| per output (and PSNR vs the
/// reference range) so the first Mac run posts the S2 table (package x output x max-abs, PSNR); no pass threshold is claimed (fp16 packages are expected to deviate).
/// NOT wired into rendering: SynthMethod.implemented still lists no learned tier, so every render stays the "fallback" (dibr_golden) label. Pre/post math lives in NunifPipeline (Linux-tested).
final class NunifCoreMLRunner {
    /// Package file names from the kit manifest (`nunif-coreml-kit-manifest.json`); shapes: warp/inpaint packages are fixed 768x1344, the video inpaint package is 288x480 (bring-up only, not a T1 quality claim).
    static let rowFlow = "nunif_row_flow_v3_fp16.mlpackage", maskMLBW = "nunif_mask_mlbw_l2_d1_fp16.mlpackage"
    static let lightInpaint = "nunif_light_inpaint_v1_fp16.mlpackage", lightVideoInpaint = "nunif_light_video_inpaint_v1_fp16.mlpackage"
    static let warpH = 768, warpW = 1344, videoH = 288, videoW = 480

    private let kitDir: URL
    private var models: [String: MLModel] = [:]
    init(kitDir: URL) { self.kitDir = kitDir }
    static func available(kitDir: URL, package: String) -> Bool { FileManager.default.fileExists(atPath: kitDir.appendingPathComponent(package).path) }

    private func model(_ name: String) -> MLModel? {
        if let m = models[name] { return m }
        guard let m = KitCompiledCache.model(kitDir.appendingPathComponent(name)) else { return nil }
        models[name] = m; return m
    }
    private func array(_ values: [Float], shape: [Int], like m: MLModel, name: String) -> MLMultiArray? {
        let want = m.modelDescription.inputDescriptionsByName[name]?.multiArrayConstraint?.dataType ?? .float32
        guard values.count == shape.reduce(1, *), let a = try? MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: want) else { return nil }
        #if arch(arm64)
        if want == .float16 { let p = a.dataPointer.bindMemory(to: Float16.self, capacity: values.count); for i in 0..<values.count { p[i] = Float16(values[i]) }; return a }
        #endif
        if want == .float32 { a.dataPointer.bindMemory(to: Float.self, capacity: values.count).update(from: values, count: values.count); return a }
        for i in 0..<values.count { a[i] = NSNumber(value: values[i]) }
        return a
    }
    private func floats(_ a: MLMultiArray) -> [Float] {          // logical C-order reads when strides are padded (same rule as VDAWindowRunner.floats)
        let n = a.count, shape = a.shape.map { $0.intValue }, st = a.strides.map { $0.intValue }
        var packed = shape.count == st.count, expect = 1
        for i in stride(from: shape.count - 1, through: 0, by: -1) where packed { if shape[i] != 1 && st[i] != expect { packed = false }; expect *= shape[i] }
        if !packed { return (0..<n).map { a[$0].floatValue } }
        if a.dataType == .float32 { return Array(UnsafeBufferPointer(start: a.dataPointer.bindMemory(to: Float.self, capacity: n), count: n)) }
        #if arch(arm64)
        if a.dataType == .float16 { let p = a.dataPointer.bindMemory(to: Float16.self, capacity: n); return (0..<n).map { Float(p[$0]) } }
        #endif
        return (0..<n).map { a[$0].floatValue }
    }
    /// inputs: feature name -> (shape, flat values). Returns output name -> flat values, nil on any model failure.
    func predict(package: String, inputs: [String: (shape: [Int], values: [Float])]) -> [String: [Float]]? {
        guard let m = model(package) else { return nil }
        var feed: [String: MLFeatureValue] = [:]
        for (k, v) in inputs { guard let a = array(v.values, shape: v.shape, like: m, name: k) else { return nil }; feed[k] = MLFeatureValue(multiArray: a) }
        guard let o = try? m.prediction(from: MLDictionaryFeatureProvider(dictionary: feed)) else { return nil }
        var out: [String: [Float]] = [:]
        for name in o.featureNames { if let a = o.featureValue(for: name)?.multiArrayValue { out[name] = floats(a) } }
        return out
    }
    /// Warp packages: x = NunifPipeline.inputTensor (3 channels, replicate-padded by the caller to 768x1344). mask_mlbw -> delta, layer_weight, hole_mask_logits; row_flow -> delta.
    func warpModel(package: String, x: [Float]) -> [String: [Float]]? {
        predict(package: package, inputs: ["x": ([1, 3, Self.warpH, Self.warpW], x)])
    }
    struct ParityRow { var output: String, maxAbs: Float, psnr: Float }
    /// Fixture arrays (flat float32, extracted by the caller from <package>_fixture.npz): `inputs` = in_* by feature name with shapes, `refs` = out_* by output name.
    /// PSNR uses the reference's own dynamic range (max - min, at least 1e-6).
    func parity(package: String, inputs: [String: (shape: [Int], values: [Float])], refs: [String: [Float]]) -> [ParityRow]? {
        guard let o = predict(package: package, inputs: inputs) else { return nil }
        var rows: [ParityRow] = []
        for (name, ref) in refs.sorted(by: { $0.key < $1.key }) {
            guard let got = o[name], got.count == ref.count, !ref.isEmpty else { return nil }
            var mx: Float = 0, se: Double = 0
            for i in 0..<ref.count { let d = abs(got[i] - ref[i]); mx = max(mx, d); se += Double(d) * Double(d) }
            let range = max((ref.max() ?? 0) - (ref.min() ?? 0), 1e-6), mse = se / Double(ref.count)
            rows.append(ParityRow(output: name, maxAbs: mx, psnr: mse > 0 ? Float(20 * log10(Double(range)) - 10 * log10(mse)) : .infinity))
        }
        return rows
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// 190t native prepare: VDA-S streaming over the A-D CoreML kit (tools/depth_analysis/kit/kit_manifest.json, contract s13): encoder_fp16 (pixels [1,3,154,266] -> feat1..4 [1,209,384]),
/// bootstrap_fp16 (feat1..4 -> depth [1,1,154,266] + cache0..7 T=1), stream_fp16 (feat1..4 + cache0..7 T=31 -> depth + nextCache0..7 T=1).
/// Port of tools/depth_analysis/vda_stream_common.py (WindowState, INFER_LEN=32, GAP=41, ImageNet preprocess) and onnx_stream.py. The window state and
/// preprocess are pure and Linux-tested against the Python; CoreML execution is UNVERIFIED on a Mac (parse-checked only).
enum VDAStream {
    static let exportH = 154, exportW = 266, inferLen = 32, gap = 41, ncache = 8
    /// cache{i} is [tokens, T, dim] (coreml_convert.py cache_shapes with T = 31 for the stream head, 1 for what each frame emits).
    static let cacheTokens = [209, 209, 60, 60, 209, 209, 836, 836]
    static let cacheDim = [192, 192, 384, 384, 64, 64, 64, 64]
    static let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
    /// Contract s22 aspect policy (vda_stream_common.preprocess_aspect): the source is letterboxed into the 266x154 stream canvas, uniform scale, black bars.
    /// nw/nh = the scaled picture (Python round(): half to even), x0/y0 its top-left in the canvas.
    struct Box: Equatable { let nw: Int, nh: Int, x0: Int, y0: Int }
    static func letterbox(srcW: Int, srcH: Int, w: Int = exportW, h: Int = exportH) -> Box {
        let scale = min(Double(w) / Double(srcW), Double(h) / Double(srcH))
        let nw = max(1, Int((Double(srcW) * scale).rounded(.toNearestOrEven))), nh = max(1, Int((Double(srcH) * scale).rounded(.toNearestOrEven)))
        return Box(nw: nw, nh: nh, x0: (w - nw) / 2, y0: (h - nh) / 2)
    }
    /// RGBA8 picture of box.nw x box.nh (the caller resizes the film frame to it) -> [3, h, w] ImageNet-normalised canvas; the bars are black PIXELS (0) that are then
    /// normalised like any other pixel, exactly as preprocess_aspect does (zero canvas, then (v / 255 - mean) / std).
    static func chwLetterboxed(rgba: [UInt8], box: Box, w: Int = exportW, h: Int = exportH) -> [Float] {
        let n = w * h; var out = [Float](repeating: 0, count: 3 * n)
        for c in 0..<3 {
            let bar = (0 - mean[c]) / std[c]
            for i in 0..<n { out[c * n + i] = bar }
            for y in 0..<box.nh { for x in 0..<box.nw {
                out[c * n + (box.y0 + y) * w + box.x0 + x] = (Float(rgba[(y * box.nw + x) * 4 + c]) / 255.0 - mean[c]) / std[c]
            } }
        }
        return out
    }
    /// The stream depth [h x w] cropped to the picture area (bars removed): a depth grid with the SOURCE aspect, box.nw x box.nh, row-major.
    static func cropDepth(_ d: [Float], box: Box, w: Int = exportW) -> [Float] {
        var out = [Float](); out.reserveCapacity(box.nw * box.nh)
        for y in 0..<box.nh { let o = (box.y0 + y) * w + box.x0; out.append(contentsOf: d[o..<(o + box.nw)]) }
        return out
    }
    /// RGBA8 at exportW x exportH (the caller resizes the film frame with a bicubic scaler, as cv2.INTER_CUBIC does upstream) -> [3, h, w] ImageNet-normalised.
    static func chw(rgba: [UInt8], w: Int = exportW, h: Int = exportH) -> [Float] {
        let n = w * h; var out = [Float](repeating: 0, count: 3 * n)
        for i in 0..<n { for c in 0..<3 { out[c * n + i] = (Float(rgba[i * 4 + c]) / 255.0 - mean[c]) / std[c] } }
        return out
    }
}

/// Anchor + rolling sliding window over per-frame cache bundles (a bundle is `ncache` flat [tokens, 1, dim] arrays), exactly the upstream frame_cache_list logic.
struct VDAWindowState {
    typealias Bundle = [[Float]]
    private(set) var id = -1
    private(set) var list: [Bundle] = []
    mutating func setState(id: Int, list: [Bundle]) { self.id = id; self.list = list }   // checkpoint restore (s19)
    let tokens: [Int], dims: [Int]
    init(tokens: [Int] = VDAStream.cacheTokens, dims: [Int] = VDAStream.cacheDim) { self.tokens = tokens; self.dims = dims }
    var isFirst: Bool { id < 0 }
    mutating func start(_ first: Bundle) { id = 0; list = Array(repeating: first, count: VDAStream.inferLen) }
    /// 31 frames: the anchor pair list[0..<2] + the newest 29, each cache concatenated on the T axis -> flat [tokens, 31, dim].
    func buildCurCache() -> [[Float]] {
        let cur = Array(list[0..<2]) + Array(list[(list.count - (VDAStream.inferLen - 3))...])
        precondition(cur.count == VDAStream.inferLen - 1)
        return (0..<cur[0].count).map { i in
            let tk = tokens[i], d = dims[i], t = cur.count
            var out = [Float](repeating: 0, count: tk * t * d)
            for (f, b) in cur.enumerated() { let src = b[i]
                for k in 0..<tk { let o = (k * t + f) * d; let s = k * d
                    for j in 0..<d { out[o + j] = src[s + j] } } }
            return out
        }
    }
    mutating func advance(_ b: Bundle) {
        id += 1; list.append(b)
        if id + VDAStream.inferLen > VDAStream.gap + 1 { list.remove(at: 1) }
    }
}

#if canImport(CoreML)
/// One shot = one stream: create a runner per shot (the window restarts at a cut). `process` takes the pre-normalised CHW pixels and returns the relative
/// inverse depth [154 x 266] (the same quantity the Python ONNX driver returns; the shot-level alignment to metric is ShotAlignerSwift).
final class VDAStreamRunner {
    struct Kit { let encoder: URL, bootstrap: URL, stream: URL }
    private let enc: MLModel, boot: MLModel, strm: MLModel
    private var state = VDAWindowState()
    var window: VDAWindowState { get { state } set { state = newValue } }     // thermal checkpoint / resume (s19)
    init?(kit: Kit) {
        func load(_ u: URL) -> MLModel? { KitCompiledCache.model(u) }
        guard let e = load(kit.encoder), let b = load(kit.bootstrap), let s = load(kit.stream) else { return nil }
        enc = e; boot = b; strm = s
    }
    private func array(_ values: [Float], shape: [Int], like model: MLModel, name: String) -> MLMultiArray? {
        let want = model.modelDescription.inputDescriptionsByName[name]?.multiArrayConstraint?.dataType ?? .float32
        guard let a = try? MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: want) else { return nil }
        #if arch(arm64)
        if want == .float16 { let p = a.dataPointer.bindMemory(to: Float16.self, capacity: values.count); for i in 0..<values.count { p[i] = Float16(values[i]) }; return a }
        #endif
        if want == .float32 { a.dataPointer.bindMemory(to: Float.self, capacity: values.count).update(from: values, count: values.count); return a }
        for i in 0..<values.count { a[i] = NSNumber(value: values[i]) }
        return a
    }
    private func floats(_ a: MLMultiArray) -> [Float] {
        let n = a.count
        // review: CoreML OUTPUT arrays may carry padded strides (rows aligned for float16); dataPointer then holds more than n packed elements. Packed = every dim with extent > 1 has the C-order stride.
        let shape = a.shape.map { $0.intValue }, st = a.strides.map { $0.intValue }
        var packed = shape.count == st.count, expect = 1
        for i in stride(from: shape.count - 1, through: 0, by: -1) where packed { if shape[i] != 1 && st[i] != expect { packed = false }; expect *= shape[i] }
        if !packed { return (0..<n).map { a[$0].floatValue } }          // subscript(Int) is the logical C-order linear index whatever the strides (same rule as MoGeKeyframeRunner.floats)
        if a.dataType == .float32 { return Array(UnsafeBufferPointer(start: a.dataPointer.bindMemory(to: Float.self, capacity: n), count: n)) }
        #if arch(arm64)
        if a.dataType == .float16 { let p = a.dataPointer.bindMemory(to: Float16.self, capacity: n); return (0..<n).map { Float(p[$0]) } }
        #endif
        return (0..<n).map { a[$0].floatValue }
    }
    /// Returns nil on any model failure (the caller marks the shot failed; it never substitutes a lower-quality depth).
    func process(chw: [Float]) -> [Float]? {
        let H = VDAStream.exportH, W = VDAStream.exportW
        guard let px = array(chw, shape: [1, 3, H, W], like: enc, name: "pixels"),
              let eo = try? enc.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixels": MLFeatureValue(multiArray: px)])) else { return nil }
        var feed: [String: MLFeatureValue] = [:]
        for i in 1...4 { guard let v = eo.featureValue(for: "feat\(i)") else { return nil }; feed["feat\(i)"] = v }
        let first = state.isFirst
        if !first {
            let cur = state.buildCurCache()
            for i in 0..<VDAStream.ncache {
                guard let a = array(cur[i], shape: [VDAStream.cacheTokens[i], VDAStream.inferLen - 1, VDAStream.cacheDim[i]], like: strm, name: "cache\(i)") else { return nil }
                feed["cache\(i)"] = MLFeatureValue(multiArray: a)
            }
        }
        guard let out = try? (first ? boot : strm).prediction(from: MLDictionaryFeatureProvider(dictionary: feed)),
              let d = out.featureValue(for: "depth")?.multiArrayValue else { return nil }
        var bundle: VDAWindowState.Bundle = []
        for i in 0..<VDAStream.ncache {       // bootstrap emits cache{i}, the stream head emits nextCache{i}
            guard let a = (out.featureValue(for: first ? "cache\(i)" : "nextCache\(i)") ?? out.featureValue(for: first ? "nextCache\(i)" : "cache\(i)"))?.multiArrayValue else { return nil }
            bundle.append(floats(a))
        }
        if first { state.start(bundle) } else { state.advance(bundle) }
        let depth = floats(d); return depth.count == H * W ? depth : nil
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190w W4: planning + stitching for WINDOWED (non-streaming) Video-Depth-Anything-Small in Prepare (streaming stays for the unprepared live range).
/// Pure Foundation, Linux-tested (Tests/VDAWindow). Mirrors upstream video_depth.py infer_video_depth as A-D's windowed_convert.py documents it (INFER_LEN 32, OVERLAP 10, step 22,
/// KEYFRAMES [0,12,24..31], tail padded with the last frame) plus the post-process as REMEMBERED (INTERP_LEN 8, align on KEYFRAMES[:OVERLAP-INTERP_LEN], least squares scale/shift, linear
/// crossfade, clip >= 0): UNVERIFIED against the vendored upstream source and against windowed_ref_fixture.npz (that fixture is a single-window model check; the stitch has no fixture). A-D can diff it.
/// Window k covers video frames [22k, 22k+32). Its input for positions 0..9 is NOT the video at that time: it is window k-1's input frames at KEYFRAMES (context carry-over); the model's output at
/// position j is still treated as the depth of video frame 22k+j (those carried frames are prev frames 24..31 = video 22k+2..22k+9 at positions 2..9).
enum VDAWindowPlan {
    static let inferLen = 32, overlap = 10, interp = 8
    static let keyframes = [0, 12, 24, 25, 26, 27, 28, 29, 30, 31]
    static var step: Int { inferLen - overlap }
    static var alignLen: Int { overlap - interp }

    /// Upstream window count: one window per 22 frames (range(0, n, 22)), at least one. For n <= 32 a second window still exists when n > 22 (it blends frames 24..31).
    static func windowCount(frameCount n: Int) -> Int { n <= 0 ? 0 : (n + step - 1) / step }

    /// frames[k][p] = the VIDEO frame index fed at input position p of window k (padded past the end with the last frame; positions 0..9 of k > 0 are window k-1's input at KEYFRAMES).
    static func inputFrames(frameCount n: Int) -> [[Int]] {
        var out = [[Int]](), prev: [Int]? = nil
        for k in 0..<windowCount(frameCount: n) {
            var f = (0..<inferLen).map { min(k * step + $0, n - 1) }
            if let p = prev { for j in 0..<overlap { f[j] = p[keyframes[j]] } }
            out.append(f); prev = f
        }
        return out
    }

    /// Least squares: cur*scale + shift ~ ref. Degenerate (flat cur) gives scale 1 and the mean difference.
    static func fit(ref: [Float], cur: [Float]) -> (scale: Float, shift: Float) {
        let n = min(ref.count, cur.count)
        guard n > 0 else { return (1, 0) }
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for i in 0..<n { let x = Double(cur[i]), y = Double(ref[i]); sx += x; sy += y; sxx += x * x; sxy += x * y }
        let d = Double(n) * sxx - sx * sx
        if abs(d) < 1e-12 { return (1, Float((sy - sx) / Double(n))) }
        let a = (Double(n) * sxy - sx * sy) / d
        return (Float(a), Float((sy - a * sx) / Double(n)))
    }

    /// Incremental form of the post-process: feed window k's depth (inferLen frames of px floats), get back the frames that are FINAL (the last `interp` aligned frames stay open for the
    /// next window's crossfade; `finish()` releases them). Frame numbers are consecutive from 0.
    struct Stitcher {
        let px: Int
        private var aligned = [[Float]](), ref = [[Float]](), k = 0
        private(set) var emitted = 0
        init(px: Int) { self.px = px }
        private func frame(_ o: [Float], _ j: Int) -> ArraySlice<Float> { o[(j * px)..<((j + 1) * px)] }
        mutating func add(_ o: [Float]) -> [[Float]] {
            guard o.count == inferLen * px else { return [] }
            let kfAlign = Array(keyframes[0..<alignLen])
            if k == 0 {
                aligned = (0..<inferLen).map { Array(frame(o, $0)) }
                ref = kfAlign.map { Array(frame(o, $0)) }
            } else {
                let curr = (0..<alignLen).flatMap { Array(frame(o, $0)) }, rf = ref.flatMap { $0 }
                let f = VDAWindowPlan.fit(ref: rf, cur: curr)
                func adj(_ v: ArraySlice<Float>) -> [Float] { v.map { max(0, $0 * f.scale + f.shift) } }
                let post = (alignLen..<overlap).map { adj(frame(o, $0)) }                  // the crossfade frames
                let base = aligned.count - interp
                for i in 0..<interp {
                    let w = interp == 1 ? Float(1) : Float(i) / Float(interp - 1)      // np.linspace(0, 1, INTERP_LEN)
                    aligned[base + i] = zip(aligned[base + i], post[i]).map { $0 * (1 - w) + $1 * w }
                }
                for j in overlap..<inferLen { aligned.append(adj(frame(o, j))) }
                var nr = [ref[0]]
                for kf in kfAlign.dropFirst() { nr.append(adj(frame(o, kf))) }
                ref = nr
            }
            k += 1
            let final = max(0, aligned.count - interp)
            let out = Array(aligned[emitted..<final]); emitted = final
            return out
        }
        mutating func finish() -> [[Float]] { let out = Array(aligned[emitted...]); emitted = aligned.count; return out }
    }

    /// outputs[k] = window k's depth, inferLen frames of `px` floats each, packed. Returns frameCount * px floats (the first n of the aligned sequence); [] on a shape error.
    static func stitch(outputs: [[Float]], frameCount n: Int, px: Int) -> [Float] {
        guard outputs.count == windowCount(frameCount: n), px > 0, outputs.allSatisfy({ $0.count == inferLen * px }) else { return [] }
        var st = Stitcher(px: px), all = [[Float]]()
        for o in outputs { all += st.add(o) }
        all += st.finish()
        return Array(all.prefix(n).flatMap { $0 })
    }
}

// BEGIN relocated VDAWindowedSource.swift (195y G2, behavior unchanged)
/// 190w W4: in-order per-frame depth out of the WINDOWED VDA model, for one shot. Pure Foundation (the model is a closure), Linux-tested with a fake model (Tests/VDAWindow).
/// `input(f)` = ImageNet-normalised CHW pixels of shot frame f, requested in ascending order (the film reader is sequential); `onRead(f)` fires right after a successful read of f,
/// while the caller's single-frame pixel cache still holds f (the caller uses it to grab that frame's guard luma and, on keyframes, its MoGe input). `window(frames)` = 32 CHW arrays -> 32 * px depth.
/// Memory: the previous window's 32 inputs (the KEYFRAMES carry-over) + the stitcher's open tail; never the whole shot. A request for frame k computes whole windows until k is final,
/// so a resumed shot (first request k0 > 0) recomputes from frame 0 and discards what it does not need.
final class VDAWindowedSource {
    let frameCount: Int, px: Int
    private let input: (Int) -> [Float]?, window: ([[Float]]) -> [Float]?
    var progress: (Int, Int) -> Void = { _, _ in }
    var onRead: (Int) -> Void = { _ in }
    private var stitcher: VDAWindowPlan.Stitcher
    private var prevInputs: [[Float]] = [], nextWindow = 0, lastRead = -1, lastChw: [Float] = []
    private var ready: [Int: [Float]] = [:], produced = 0, finished = false
    init(frameCount: Int, px: Int, input: @escaping (Int) -> [Float]?, window: @escaping ([[Float]]) -> [Float]?) {
        self.frameCount = frameCount; self.px = px; self.input = input; self.window = window; stitcher = VDAWindowPlan.Stitcher(px: px)
    }
    private func chw(_ f: Int) -> [Float]? {
        if f <= lastRead { return f == lastRead ? lastChw : nil }       // padding repeats the last frame (min(.., n-1)), which is the one just read
        guard f == lastRead + 1, let c = input(f) else { return nil }
        lastRead = f; lastChw = c; onRead(f); return c
    }
    /// Runs the next window; false on any failure (a missing frame or a model failure: the shot fails, no substitute depth).
    private func runWindow() -> Bool {
        let w = nextWindow, frames = VDAWindowPlan.inputFrames(frameCount: frameCount)[w]
        var ins = [[Float]](); ins.reserveCapacity(VDAWindowPlan.inferLen)
        for p in 0..<VDAWindowPlan.inferLen {
            if w > 0 && p < VDAWindowPlan.overlap { ins.append(prevInputs[VDAWindowPlan.keyframes[p]]); continue }
            guard let c = chw(frames[p]) else { return false }
            ins.append(c)
        }
        progress(w, VDAWindowPlan.windowCount(frameCount: frameCount))
        guard let out = window(ins), out.count == VDAWindowPlan.inferLen * px else { return false }
        prevInputs = ins; nextWindow += 1
        progress(nextWindow, VDAWindowPlan.windowCount(frameCount: frameCount))
        for fr in stitcher.add(out) { ready[produced] = fr; produced += 1 }
        if nextWindow == VDAWindowPlan.windowCount(frameCount: frameCount) { for fr in stitcher.finish() { ready[produced] = fr; produced += 1 }; finished = true }
        return true
    }
    /// Final depth of frame k (relative inverse depth, the model grid). nil = failure, or k already released (frames below the last request are dropped).
    func depth(frame k: Int) -> [Float]? {
        guard k >= 0, k < frameCount else { return nil }
        while produced <= k && !finished { if !runWindow() { return nil } }
        for key in ready.keys where key < k { ready[key] = nil }
        return ready[k]
    }
}
// END relocated VDAWindowedSource.swift

// BEGIN relocated VDAWindowRunner.swift (195y G2, behavior unchanged)
#if canImport(CoreML)
import CoreML

/// 190w W4: the A-D windowed VDA-S CoreML kit (windowed_encoder_fp16: pixels [B<=32,3,154,266] -> feat1..4 [B,209,384]; windowed_head_fp16: feat1..4 [32,209,384] -> depth [1,32,154,266]).
/// One window = one encoder call with batch 32 + one head call. CONVERTED on Linux, NEVER EXECUTED: parity vs windowed_ref_fixture.npz (torch fp32 window + depth) must be checked on the Mac
/// before first use (`parityError(fixture:)` returns the max abs diff for the self-test). Parse-only on Linux; same array helpers as VDAStreamRunner.
final class VDAWindowRunner {
    static let encoderName = "windowed_encoder_fp16.mlpackage", headName = "windowed_head_fp16.mlpackage"
    private let enc: MLModel, head: MLModel
    static func available(kitDir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: kitDir.appendingPathComponent(encoderName).path) && fm.fileExists(atPath: kitDir.appendingPathComponent(headName).path)
    }
    init?(kitDir: URL) {
        func load(_ n: String) -> MLModel? {
            return KitCompiledCache.model(kitDir.appendingPathComponent(n))
        }
        guard let e = load(Self.encoderName), let h = load(Self.headName) else { return nil }
        enc = e; head = h
    }
    private func array(_ values: [Float], shape: [Int], like model: MLModel, name: String) -> MLMultiArray? {
        let want = model.modelDescription.inputDescriptionsByName[name]?.multiArrayConstraint?.dataType ?? .float32
        guard let a = try? MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: want) else { return nil }
        #if arch(arm64)
        if want == .float16 { let p = a.dataPointer.bindMemory(to: Float16.self, capacity: values.count); for i in 0..<values.count { p[i] = Float16(values[i]) }; return a }
        #endif
        if want == .float32 { a.dataPointer.bindMemory(to: Float.self, capacity: values.count).update(from: values, count: values.count); return a }
        for i in 0..<values.count { a[i] = NSNumber(value: values[i]) }
        return a
    }
    private func floats(_ a: MLMultiArray) -> [Float] {
        let n = a.count
        let shape = a.shape.map { $0.intValue }, st = a.strides.map { $0.intValue }
        var packed = shape.count == st.count, expect = 1
        for i in stride(from: shape.count - 1, through: 0, by: -1) where packed { if shape[i] != 1 && st[i] != expect { packed = false }; expect *= shape[i] }
        if !packed { return (0..<n).map { a[$0].floatValue } }            // padded strides: logical C-order reads (same rule as VDAStreamRunner.floats)
        if a.dataType == .float32 { return Array(UnsafeBufferPointer(start: a.dataPointer.bindMemory(to: Float.self, capacity: n), count: n)) }
        #if arch(arm64)
        if a.dataType == .float16 { let p = a.dataPointer.bindMemory(to: Float16.self, capacity: n); return (0..<n).map { Float(p[$0]) } }
        #endif
        return (0..<n).map { a[$0].floatValue }
    }
    /// frames = 32 CHW arrays (3*154*266 floats each, ImageNet-normalised); returns 32*154*266 relative inverse depth floats, nil on any model failure.
    func run(frames: [[Float]]) -> [Float]? {
        let H = VDAStream.exportH, W = VDAStream.exportW, T = VDAWindowPlan.inferLen, per = 3 * H * W
        guard frames.count == T, frames.allSatisfy({ $0.count == per }),
              let px = array(frames.flatMap { $0 }, shape: [T, 3, H, W], like: enc, name: "pixels"),
              let eo = try? enc.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixels": MLFeatureValue(multiArray: px)])) else { return nil }
        var feed: [String: MLFeatureValue] = [:]
        for i in 1...4 { guard let v = eo.featureValue(for: "feat\(i)") else { return nil }; feed["feat\(i)"] = v }
        guard let ho = try? head.prediction(from: MLDictionaryFeatureProvider(dictionary: feed)), let d = ho.featureValue(for: "depth")?.multiArrayValue else { return nil }
        let out = floats(d); return out.count == T * H * W ? out : nil
    }
    /// Self-test: max |depth - reference| over one deterministic window; `window` is [1,32,3,H,W] flat, `depth` [1,32,H,W] flat (windowed_ref_fixture.npz arrays, extracted by the caller).
    func parityError(window: [Float], depth: [Float]) -> Float? {
        let per = 3 * VDAStream.exportH * VDAStream.exportW
        guard window.count == VDAWindowPlan.inferLen * per else { return nil }
        let frames = (0..<VDAWindowPlan.inferLen).map { Array(window[($0 * per)..<(($0 + 1) * per)]) }
        guard let o = run(frames: frames), o.count == depth.count else { return nil }
        return zip(o, depth).map { abs($0 - $1) }.max()
    }
}
#endif
// END relocated VDAWindowRunner.swift

// BEGIN relocated VDAWindowedBackend.swift (195y G2, behavior unchanged)
#if canImport(CoreML)

/// 190w W4: ShotPrepareBackend over the WINDOWED VDA model (VDAWindowedSource does the windows + stitch). UNCOMPILED on a Mac, CoreML UNEXECUTED.
/// The window source reads frames AHEAD of the step being asked for, so everything the step needs from a frame is captured when that frame is read (`onRead`, called while the caller's
/// single-frame pixel cache still holds it): its guard luma (`lumaOf`) and, on MoGe keyframes (k % keyframeStride == 0), the MoGe input. `window` is a dummy: resume recomputes
/// the shot from frame 0 (costly, correct: nothing is carried in the checkpoint, only the spooled finished frames).
final class VDAWindowedBackend: ShotPrepareBackend {
    private let source: VDAWindowedSource, moge: MoGeKeyframeRunner
    private let crop: VDAStream.Box
    private let mogeInput: (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)?
    private var luma: [Int: [Float]] = [:], mogeIn: [Int: (rgba: [UInt8], shape: MoGeInput.Shape)] = [:], lastStep = -1
    var window = VDAWindowState()
    var progress: (Int, Int) -> Void { get { source.progress } set { source.progress = newValue } }
    var stage: (String, Double) -> Void = { _, _ in }
    /// `lumaAt(k)` = guard luma of the frame just read (call only from the read hook), `px` = VDAStream.exportH * exportW.
    init(runner: VDAWindowRunner, moge: MoGeKeyframeRunner, frameCount: Int, crop: VDAStream.Box, vdaInput: @escaping (Int) -> [Float]?, lumaNow: @escaping () -> [Float]?,
         mogeInput: @escaping (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)?) {
        self.moge = moge; self.crop = crop; self.mogeInput = mogeInput
        source = VDAWindowedSource(frameCount: frameCount, px: VDAStream.exportH * VDAStream.exportW, input: vdaInput, window: { runner.run(frames: $0) })
        source.onRead = { [unowned self] k in
            if let l = lumaNow() { luma[k] = l }
            if k % FovTrackBuilder.keyframeStride == 0, let m = self.mogeInput(k) { mogeIn[k] = m }
        }
    }
    func vdaStep(frame: Int) -> [Float]? {
        let t = DispatchTime.now(); defer { stage("vda_model", Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6) }
        guard let d = source.depth(frame: frame) else { return nil }
        lastStep = frame
        for k in luma.keys where k < frame { luma[k] = nil }
        for k in mogeIn.keys where k < frame { mogeIn[k] = nil }
        return VDAStream.cropDepth(d, box: crop)
    }
    func guardLuma() -> [Float]? { luma[lastStep] }
    func mogeKeyframe(frame: Int) -> MoGeKeyframe? {
        guard let i = mogeIn[frame] ?? mogeInput(frame) else { return nil }          // the fallback re-reads (sequential reader: only correct if frame is still the cached one)
        let t = DispatchTime.now(); defer { stage("moge_model", Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6) }
        return moge.run(rgba: i.rgba, shape: i.shape)
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// 190t native prepare: MoGe-2 ViT-S keyframe runner over the A-D CoreML package (tools/depth_analysis/moge_convert.py: image [1,3,518,518]
/// ImageNet-normalised -> points [1,518,518,3], normal, mask [1,518,518] float, metric_scale [1]). Recovery of focal/shift, metric depth and hfov is
/// MoGeGeometry (DepthPrepareMath.swift). CoreML execution is UNVERIFIED on a Mac; this file is only parse-checked, the pure helpers are tested on Linux.
enum MoGeInput {
    static let size = 518          // square calibration package only
    /// One enumerated-shape package (A-D kit): input [1,3,h,w], multiples of 14. The square 518 package is calibration-only and never picked for film frames.
    struct Shape: Equatable { let w: Int, h: Int; var aspect: Double { Double(w) / Double(h) } }
    /// Pick the shape whose aspect is closest (log ratio) to the source frame's: no letterbox, no stretch beyond that mismatch.
    static func pick(_ shapes: [Shape], srcW: Int, srcH: Int) -> Shape? {
        guard srcW > 0, srcH > 0 else { return nil }
        let a = Double(srcW) / Double(srcH)
        return shapes.min { abs(log($0.aspect / a)) < abs(log($1.aspect / a)) }
    }
    static let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
    /// w x h RGBA8 (the caller resizes the film frame to the picked shape with a high quality scaler) -> CHW float32.
    static func chw(rgba: [UInt8], w: Int = size, h: Int = size) -> [Float] {
        let n = w * h; var out = [Float](repeating: 0, count: 3 * n)
        for i in 0..<n { for c in 0..<3 { out[c * n + i] = (Float(rgba[i * 4 + c]) / 255.0 - mean[c]) / std[c] } }
        return out
    }
}

struct MoGeKeyframe {
    var hfovDeg: Double
    var depth: [Float]          // width x height metres, +inf where masked / invalid
    var validFraction: Double
    var usedFP32: Bool
    var width = MoGeInput.size, height = MoGeInput.size     // the shape this keyframe was run at (depth is width x height)
    var plausible: Bool { hfovDeg.isFinite && hfovDeg > 5 && hfovDeg < 170 && validFraction >= 0.02 && depth.contains { $0.isFinite } }
}

#if canImport(CoreML)
final class MoGeKeyframeRunner {
    struct Package { let shape: MoGeInput.Shape; let fp16: URL?; let fp32: URL? }
    private let packages: [Package]
    /// Precision actually used per keyframe (self-test): fp16 results accepted, fp16 results rejected as implausible, fp32 fallbacks accepted.
    private(set) var fp16Used = 0, fp16Rejected = 0, fp32Used = 0
    private var cache: [String: MLModel] = [:]
    /// Enumerated-shape packages from the kit manifest (compiled .mlmodelc or .mlpackage, compiled here). Models load lazily; fp32 only when needed.
    init?(packages: [Package]) {
        let usable = packages.filter { $0.fp16 != nil || $0.fp32 != nil }
        guard !usable.isEmpty else { return nil }
        self.packages = usable
    }
    func shape(srcW: Int, srcH: Int) -> MoGeInput.Shape? { MoGeInput.pick(packages.map { $0.shape }, srcW: srcW, srcH: srcH) }

    private func model(_ u: URL?) -> MLModel? {
        guard let u else { return nil }
        if let m = cache[u.path] { return m }
        guard let m = KitCompiledCache.model(u) else { return nil }
        cache[u.path] = m; return m
    }

    /// One keyframe at `shape` (RGBA8 w*h, resized by the caller): fp16 first, fp32 when the fp16 result is implausible (non-finite or out-of-range
    /// hfov, <2% valid pixels) or fp16 is absent.
    func run(rgba: [UInt8], shape: MoGeInput.Shape) -> MoGeKeyframe? {
        guard rgba.count == shape.w * shape.h * 4, let pkg = packages.first(where: { $0.shape == shape }) else { return nil }
        let input = MoGeInput.chw(rgba: rgba, w: shape.w, h: shape.h)
        if let m = model(pkg.fp16) { if let k = infer(m, input, shape, fp32: false), k.plausible { fp16Used += 1; return k }; fp16Rejected += 1 }
        if let m = model(pkg.fp32), let k = infer(m, input, shape, fp32: true), k.plausible { fp32Used += 1; return k }
        return nil
    }

    private func floats(_ a: MLMultiArray) -> [Float] {       // linear NSNumber access: element order equals the logical C order for any dtype/strides
        let n = a.count; var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = a[i].floatValue }
        return out
    }
    private func infer(_ model: MLModel, _ chw: [Float], _ sh: MoGeInput.Shape, fp32: Bool) -> MoGeKeyframe? {
        guard let arr = try? MLMultiArray(shape: [1, 3, NSNumber(value: sh.h), NSNumber(value: sh.w)], dataType: .float32) else { return nil }
        chw.withUnsafeBufferPointer { src in arr.dataPointer.copyMemory(from: src.baseAddress!, byteCount: src.count * 4) }
        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: arr)])),
              let p = out.featureValue(for: "points")?.multiArrayValue, let mk = out.featureValue(for: "mask")?.multiArrayValue,
              let ms = out.featureValue(for: "metric_scale")?.multiArrayValue, p.count == sh.w * sh.h * 3, mk.count == sh.w * sh.h, ms.count >= 1 else { return nil }
        let points = floats(p), mask = floats(mk).map { $0 > 0.5 }, scale = Double(ms[0].floatValue)
        let fs = MoGeGeometry.recoverFocalShift(points: points, mask: mask, height: sh.h, width: sh.w)
        let depth = MoGeGeometry.depth(points: points, mask: mask, shift: fs.shift, metricScale: scale)
        let valid = Double(depth.filter { $0.isFinite }.count) / Double(depth.count)
        return MoGeKeyframe(hfovDeg: MoGeGeometry.hfovDegrees(focal: fs.focal, width: sh.w, height: sh.h), depth: depth, validFraction: valid,
                            usedFP32: fp32, width: sh.w, height: sh.h)
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 195h A (item 3): temporal EMA for the DAV2 model's per-frame depth maps, per shot, reset at every shot boundary, default OFF.
/// Pure Foundation, Linux-tested; the DAV2 backend holds one instance per shot and checkpoint-restores its state through the
/// backend `window` contract, so a crash + resume continues the exact same sequence (no approximate re-prime).
final class ModelDepthEMA {
    /// Lock-backed global switch (195h r2-3 convention), default off. Read once per job into the frozen options snapshot, so a
    /// mid-job toggle never mixes smoothed and raw frames inside one depth container.
    private static let lock = NSLock()
    private static var on = false
    static var enabled: Bool { lock.lock(); defer { lock.unlock() }; return on }
    static func setEnabled(_ value: Bool) { lock.lock(); self.on=value; lock.unlock() }
    static func toggle() { lock.lock(); on.toggle(); lock.unlock() }

    let alpha: Float                       // weight of the NEW frame; 0.25 = smooth over roughly the last 4 frames
    private var acc: [Float]?
    init(alpha: Float = 0.25) { self.alpha = alpha }
    /// Shot boundary / explicit reset: the next frame passes through unsmoothed.
    func reset() { acc = nil }
    /// One depth map (w*h row-major). First map of a shot passes through unchanged; later maps blend per pixel.
    func apply(_ m: [Float]) -> [Float] {
        guard let a = acc, a.count == m.count else { acc = m; return m }
        var out = [Float](repeating: 0, count: m.count)
        for i in 0..<m.count { out[i] = alpha * m[i] + (1 - alpha) * a[i] }
        acc = out; return out
    }
    /// Checkpoint contract bridge: the accumulator as one VDA "bundle" ([[Float]]), so ShotCheckpoint (GORCK003) persists and
    /// restores it EXACTLY like any other backend state. [] = cold start.
    var stateBundles: [[Float]] { acc.map { [$0] } ?? [] }
    func restore(bundles: [[Float]]) { acc = bundles.first }
}

/// 195h A: half-precision float bit pattern -> Float (IEEE 754 binary16), pure and Linux-tested. The pinned DAV2 package's depth
/// output may arrive as OneComponent16Half; this is the only conversion the runner performs.
enum HalfFloat {
    static func toFloat(_ h: UInt16) -> Float {
        let s = Float((h >> 15) & 1) * -2 + 1, e = Int((h >> 10) & 0x1f), m = Int(h & 0x3ff)
        if e == 0 { return s * Float(m) * pow(2, -14) / 1024 }           // subnormal
        if e == 31 { return m == 0 ? s * Float.infinity : .nan }
        return s * (1 + Float(m) / 1024) * pow(2, Float(e - 15))
    }
}

/// 195h A: bilinear resize of a depth/disparity map (row-major w*h -> outW*outH). The sample coordinate is CLAMPED to the valid
/// range before the low index and weight are taken, so edge pixels replicate the edge instead of blending with a phantom row.
enum DepthMapResize {
    static func bilinear(_ src: [Float], w: Int, h: Int, outW: Int, outH: Int) -> [Float] {
        guard w > 0, h > 0, outW > 0, outH > 0, src.count == w * h else { return [] }
        var out = [Float](repeating: 0, count: outW * outH)
        for y in 0..<outH {
            let fy = max(0, min(Float(h - 1), (Float(y) + 0.5) * Float(h) / Float(outH) - 0.5))
            let y0 = min(h - 1, Int(floor(fy))), y1 = min(h - 1, y0 + 1), wy = fy - floor(fy)
            for x in 0..<outW {
                let fx = max(0, min(Float(w - 1), (Float(x) + 0.5) * Float(w) / Float(outW) - 0.5))
                let x0 = min(w - 1, Int(floor(fx))), x1 = min(w - 1, x0 + 1), wx = fx - floor(fx)
                let a = src[y0 * w + x0], b = src[y0 * w + x1], c = src[y1 * w + x0], d = src[y1 * w + x1]
                out[y * outW + x] = a * (1 - wx) * (1 - wy) + b * wx * (1 - wy) + c * (1 - wx) * wy + d * wx * wy
            }
        }
        return out
    }
    /// DAV2 emits relative disparity (larger = nearer); the pipeline's depth maps store depth (larger = farther). d -> 1/max(d, eps).
    static func disparityToDepth(_ d: [Float], eps: Float = 1e-6) -> [Float] { d.map { 1 / max($0, eps) } }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Gor-owned derived cache only. Unknown/legacy directories are excluded from
/// the managed quota and are never adopted or removed by a budget sweep. Pins are advisory
/// locks outside film directories, shared by playback and every writer process.
enum DepthCacheBudget {
    struct Policy {
        // Optional absolute override is for tests, never the production default.
        var quota: UInt64? = nil
        var volumePercent: UInt64 = 5
        var usablePercent: UInt64 = 10
        var reserve: UInt64 = 5 * 1024 * 1024 * 1024
        var writeHeadroom: UInt64 = 256 * 1024 * 1024
    }
    static var policy = Policy()
    static let marker = ".gor-cache-owned-v1"
    static func validKey(_ s: String) -> Bool { s.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func plainDirectory(_ u: URL) -> Bool {
        var s = stat(); return lstat(u.path, &s) == 0 && (s.st_mode & S_IFMT) == S_IFDIR
    }
    static func plainFile(_ u: URL) -> Bool {
        var s = stat(); return lstat(u.path, &s) == 0 && (s.st_mode & S_IFMT) == S_IFREG && s.st_nlink == 1
    }
    final class Pin {
        fileprivate let fd: Int32
        let entry: URL
        fileprivate init(_ fd: Int32, _ entry: URL) { self.fd = fd; self.entry = entry }
        deinit { _ = flock(fd, LOCK_UN); close(fd) }
    }
    static func withLock<T>(_ root: URL, _ body: () throws -> T) throws -> T {
        guard plainDirectory(root) else { throw Failure.unsafe }
        let fd = open(root.appendingPathComponent(".budget.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw Failure.unsafe }
        defer { _ = flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw Failure.unsafe }
        return try body()
    }
    enum Failure: Error, CustomStringConvertible {
        case unsafe, quota, freeSpace
        var description: String {
            switch self {
            case .unsafe: return "3D: cache safety check failed; staying 2D"
            case .quota: return "3D: depth cache is full; preparation stopped, keeping 2D"
            case .freeSpace: return "3D: disk space is low; preparation stopped, keeping 2D"
            }
        }
    }
// [attribution comment elided]
// [attribution comment elided]
    static func pin(root: URL, key: String, create: Bool = false) throws -> Pin {
        guard validKey(key) else { throw Failure.unsafe }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try withLock(root) {
            let entry = root.appendingPathComponent(key, isDirectory: true)
            let existed = FileManager.default.fileExists(atPath: entry.path)
            if create && !existed {
                try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: false)
                try Data(key.utf8).write(to: entry.appendingPathComponent(marker), options: .withoutOverwriting)
            }
            guard plainDirectory(entry) else { throw Failure.unsafe }
            let fd = open(root.appendingPathComponent(".pin-" + key).path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
            guard fd >= 0 else { throw Failure.unsafe }
            guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { close(fd); throw Failure.unsafe }
            // One stamp per acquisition, not per playback tick.
            if owned(entry) { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: entry.appendingPathComponent(marker).path) }
            return Pin(fd, entry)
        }
    }
    static func quota(capacity: UInt64, available: UInt64, used: UInt64, policy: Policy) -> UInt64 {
        let usable = available + used > policy.reserve ? available + used - policy.reserve : 0
        return policy.quota ?? min(capacity / 100 * policy.volumePercent, usable / 100 * policy.usablePercent)
    }
    static func recordFailure(_ f: Failure, root: URL) {
        let text = f == .freeSpace ? "free" : f == .quota ? "quota" : "unsafe"
        try? Data(text.utf8).write(to:root.appendingPathComponent(".budget-failure"),options:.atomic)
    }
    static func failure(root: URL) -> Failure? {
        guard let s=try? String(contentsOf:root.appendingPathComponent(".budget-failure"),encoding:.utf8) else {return nil}
        switch s {case "free":return .freeSpace;case "quota":return .quota;case "unsafe":return .unsafe;default:return nil}
    }
    static func owned(_ entry: URL) -> Bool {
        let m = entry.appendingPathComponent(marker)
        return validKey(entry.lastPathComponent) && plainDirectory(entry) && plainFile(m) && (try? String(contentsOf: m, encoding: .utf8)) == entry.lastPathComponent
    }
    static func deletable(_ entry: URL) -> Bool {
        guard owned(entry),let files=try? FileManager.default.contentsOfDirectory(at:entry,includingPropertiesForKeys:nil) else {return false}
        let fixed:Set<String>=[marker,"cuts.json","fov_track.json","progress.json","render-ready.json","prepare-input.mp4","prepare-input.part.mp4"]
        let pattern="^(depth_shot_[0-9]{5}\\.(dzc(\\.(options|ema)\\.json)?|json)|source_shot_[0-9]{5}\\.mp4|shot_[0-9]{5}\\.(spool(\\.identity\\.json)?|ck|align\\.json)|render_shot_[0-9]{5}(_[a-f0-9]{64})?\\.(mp4|json)|\\.render-[A-Fa-f0-9-]{36}\\.mp4)$"
        return files.allSatisfy {u in
            guard plainFile(u) else {return false}
            let n=u.lastPathComponent.hasPrefix(".tmp-") ? String(u.lastPathComponent.dropFirst(5)) : u.lastPathComponent
            return fixed.contains(n) || n.range(of:pattern,options:.regularExpression) != nil
        }
    }
    /// Logical byte count is conservative for APFS clones/sparse files. No
    /// symlink traversal. Any enumeration/read failure refuses further writes.
    static func bytes(_ directory: URL) throws -> UInt64 {
        guard plainDirectory(directory) else { throw Failure.unsafe }
        var sum: UInt64 = 0
        for u in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            var s = stat(); guard lstat(u.path, &s) == 0 else { throw Failure.unsafe }
            if (s.st_mode & S_IFMT) == S_IFDIR { sum += try bytes(u) }
            else if (s.st_mode & S_IFMT) == S_IFREG { sum += UInt64(max(0, s.st_size)) }
            else { throw Failure.unsafe }
        }
        return sum
    }
    static func freeBytes(_ root: URL) -> UInt64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber)?.uint64Value
    }
    /// LRU eviction uses nonblocking exclusive pins. A pinned preparing,
    /// rendering or playing entry is never a candidate, even in another process.
    @discardableResult static func enforce(root: URL, policy: Policy = policy, additional: UInt64 = 0, free: (() -> UInt64?)? = nil) throws -> [String] {
        try withLock(root) {
            var removed: [String] = []
            let fm = FileManager.default
            let managed = try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter {owned($0)}
            var total:UInt64=0
            for entry in managed {total += try bytes(entry)}
            guard let available = (free ?? { freeBytes(root) })(),
                  let capacity = (try? fm.attributesOfFileSystem(forPath: root.path)[.systemSize] as? NSNumber)?.uint64Value else { throw Failure.freeSpace }
            // Add back cache occupancy so its own writes do not move the goal.
            // The low-space reserve always binds independently of this quota.
            let quota = quota(capacity:capacity,available:available,used:total,policy:policy)
            let entries = managed.sorted {
                let a = (try? fm.attributesOfItem(atPath: $0.appendingPathComponent(marker).path)[.modificationDate] as? Date) ?? .distantPast
                let b = (try? fm.attributesOfItem(atPath: $1.appendingPathComponent(marker).path)[.modificationDate] as? Date) ?? .distantPast
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
            for entry in entries where total + additional + policy.writeHeadroom > quota {
                let fd = open(root.appendingPathComponent(".pin-" + entry.lastPathComponent).path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
                guard fd >= 0 else { continue }
                defer { _ = flock(fd, LOCK_UN); close(fd) }
                guard flock(fd, LOCK_EX | LOCK_NB) == 0, deletable(entry) else { continue }
                let size = try bytes(entry)
                try fm.removeItem(at: entry)
                total -= size; removed.append(entry.lastPathComponent)
            }
            // Quota is an eviction target, never permission to evict active
            // films or force them to 2D. Only actual volume reserve can stop
            // their writers. Legacy bytes neither gate nor trigger adoption.
            guard let after = (free ?? { freeBytes(root) })(), after >= policy.reserve + additional + policy.writeHeadroom else { throw Failure.freeSpace }
            return removed
        }
    }
    /// Remove only transient files this invocation created, never source proxy
    /// frames needed for seeks or a resumable interrupted shot's spool.
    static func removeTransient(_ file: URL, entry: URL) {
        guard file.deletingLastPathComponent().standardizedFileURL == entry.standardizedFileURL,
              ["prepare-input.mp4", "prepare-input.part.mp4"].contains(file.lastPathComponent), plainFile(file) else { return }
        try? FileManager.default.removeItem(at: file)
    }
    /// Scans run on prepare/render workers, never on the playback timer. Space
    /// checks remain per frame; full cache accounting is at most once a second.
    final class Watch {
        let root: URL
        var next = 0.0, failure: Failure?
        init(root: URL) { self.root = root }
        func allowed(force: Bool = false) -> Bool {
            if failure != nil { return false }
            let now = ProcessInfo.processInfo.systemUptime
            do {
                guard let free = freeBytes(root), free >= policy.reserve + policy.writeHeadroom else { throw Failure.freeSpace }
                if force || now >= next { try enforce(root: root); next = now + 1 }
                return true
            } catch {
                failure = (error as? Failure) ?? .unsafe
                print(failure!.description); fflush(stdout); return false
            }
        }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(Compression)
import Compression
#endif

/// 190v s16: lossless per-shot depth container (.dzc), Swift writer. Spec and reference: tools/depth_analysis/depth_container.py. Layout (little-endian):
/// 64 B header | per frame [u32 payload_len, u32 crc32(plane), LZFSE payload] | n x u64 frame offsets | "GORDZEND". Plane = padded W x H u16 w10 (same quantiser as
/// prepare_film). Index + trailer are written last, so a file without them is incomplete but scannable (leading crc-valid frames). Any valid LZFSE stream is
/// accepted by readers, so the encoder need not be byte-identical to the reference. The layout code is pure Foundation and tested on Linux against the
/// Python reference; the LZFSE calls (Compression framework) are Mac-only and parse-checked.
enum DZC {
    static let magic = Array("GORDZ001".utf8), trailer = Array("GORDZEND".utf8), headerSize = 64
    struct Meta: Equatable {
        var shot: UInt32, fpsNum: UInt32, fpsDen: UInt32, startFrame: UInt64
        var width: UInt32, height: UInt32, depthWidth: UInt32, depthHeight: UInt32, nFrames: UInt32
        var planeBytes: UInt32 { width * height * 2 }
    }
    static func fpsPair(_ fps: Double) -> (UInt32, UInt32) { fps == fps.rounded() ? (UInt32(fps), 1) : (UInt32((fps * 1000).rounded()), 1000) }

    private static let crcTable: [UInt32] = (0..<256).map { n in var c = UInt32(n); for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c }
    static func crc32(_ d: [UInt8]) -> UInt32 { var c: UInt32 = 0xFFFFFFFF; for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }; return c ^ 0xFFFFFFFF }

    /// depth_container.quantise: z metres [h*w] -> edge-padded even plane of w10 (v = 256/z, w10 = clip(rint(v/1024*1023), 0, 1023); z <= 1e-3 or non-finite -> 0).
    static func quantise(z: [Float], h: Int, w: Int) -> (plane: [UInt16], width: Int, height: Int) {
        let wp = w + (w & 1), hp = h + (h & 1); var out = [UInt16](repeating: 0, count: wp * hp)
        for y in 0..<h { for x in 0..<w { out[y * wp + x] = DepthQuant.w10(zMetres: z[y * w + x]) } }
        if wp != w { for y in 0..<h { out[y * wp + w] = out[y * wp + w - 1] } }
        if hp != h { for x in 0..<wp { out[h * wp + x] = out[(h - 1) * wp + x] } }
        return (out, wp, hp)
    }
    static func le(_ v: UInt64, _ n: Int) -> [UInt8] {
        // 195y native#30 sweep: same one-line bitop closure shape as the unpack timeout; explicit loop, identical results.
        var out: [UInt8] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let shift: UInt64 = 8 * UInt64(i)
            out.append(UInt8((v >> shift) & 0xFF))
        }
        return out
    }
    static func rd(_ b: [UInt8], _ o: Int, _ n: Int) -> UInt64 {
        // 195y native#30 sweep: same one-line bitop closure shape as the unpack timeout; explicit loop, identical results.
        var acc: UInt64 = 0
        for i in 0..<n {
            let shift: UInt64 = 8 * UInt64(i)
            acc = acc | (UInt64(b[o + i]) << shift)
        }
        return acc
    }

    static func header(_ m: Meta) -> [UInt8] {
        var h = magic + le(1, 2) + le(1, 2) + le(0, 4) + le(UInt64(m.shot), 4) + le(UInt64(m.fpsNum), 4) + le(UInt64(m.fpsDen), 4) + le(m.startFrame, 8)
        h += le(UInt64(m.width), 4) + le(UInt64(m.height), 4) + le(UInt64(m.depthWidth), 4) + le(UInt64(m.depthHeight), 4) + le(UInt64(m.nFrames), 4) + le(UInt64(m.planeBytes), 4)
        return h + [UInt8](repeating: 0, count: headerSize - h.count)
    }
    static func parseHeader(_ b: [UInt8]) -> Meta? {
        guard b.count >= headerSize, Array(b[0..<8]) == magic, rd(b, 8, 2) == 1, rd(b, 10, 2) == 1 else { return nil }
        return Meta(shot: UInt32(rd(b, 16, 4)), fpsNum: UInt32(rd(b, 20, 4)), fpsDen: UInt32(rd(b, 24, 4)), startFrame: rd(b, 28, 8), width: UInt32(rd(b, 36, 4)),
                    height: UInt32(rd(b, 40, 4)), depthWidth: UInt32(rd(b, 44, 4)), depthHeight: UInt32(rd(b, 48, 4)), nFrames: UInt32(rd(b, 52, 4)))
    }
    static func record(planeLE: [UInt8], compressed: [UInt8]) -> [UInt8] { le(UInt64(compressed.count), 4) + le(UInt64(crc32(planeLE)), 4) + compressed }
    static func tail(offsets: [UInt64]) -> [UInt8] { offsets.flatMap { le($0, 8) } + trailer }
    static func planeBytesLE(_ p: [UInt16]) -> [UInt8] { p.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    /// Leading frames whose record parses, decompresses to plane_bytes and matches its crc; also returns the byte offset after the last valid record.
    static func scanValid(_ f: [UInt8], decompress: ([UInt8], Int) -> [UInt8]?) -> (frames: Int, end: Int, meta: Meta)? {
        guard let m = parseHeader(f) else { return nil }
        var o = headerSize, n = 0
        while o + 8 <= f.count {
            let len = Int(rd(f, o, 4)), crc = UInt32(rd(f, o + 4, 4))
            guard o + 8 + len <= f.count, n < Int(m.nFrames), let raw = decompress(Array(f[(o + 8)..<(o + 8 + len)]), Int(m.planeBytes)), raw.count == Int(m.planeBytes), crc32(raw) == crc else { break }
            o += 8 + len; n += 1
        }
        return (n, o, m)
    }
}

/// Appends frames to a .dzc and finishes it (index + trailer). `resume` keeps the leading valid frames of an interrupted file.
final class DZCWriter {
    typealias Codec = (compress: ([UInt8]) -> [UInt8]?, decompress: ([UInt8], Int) -> [UInt8]?)
    private let url: URL, meta: DZC.Meta, codec: Codec
    private var handle: FileHandle?, offsets: [UInt64] = []
    private(set) var framesWritten = 0

    /// Starts a new file (replaces any existing one) or, with resume, truncates an existing one after its valid prefix. nil on I/O failure or a header mismatch.
    init?(url: URL, meta: DZC.Meta, resume: Bool = false, codec: Codec = DZCWriter.lzfse) {
        self.url = url; self.meta = meta; self.codec = codec
        let fm = FileManager.default
        if resume, let d = try? Data(contentsOf: url), let s = DZC.scanValid([UInt8](d), decompress: codec.decompress), s.meta == meta {
            guard let h = try? FileHandle(forUpdating: url) else { return nil }
            do { try h.truncate(atOffset: UInt64(s.end)); try h.seekToEnd() } catch { return nil }
            handle = h; framesWritten = s.frames
            var o = DZC.headerSize
            for _ in 0..<s.frames { offsets.append(UInt64(o)); o += 8 + Int(DZC.rd([UInt8](d), o, 4)) }
        } else {
            guard fm.createFile(atPath: url.path, contents: Data(DZC.header(meta))), let h = try? FileHandle(forWritingTo: url) else { return nil }
            do { try h.seekToEnd() } catch { return nil }
            handle = h
        }
    }
    /// One frame of metres (depthHeight x depthWidth). False on codec/I/O failure or too many frames.
    func append(zMetres z: [Float]) -> Bool {
        let dh = Int(meta.depthHeight), dw = Int(meta.depthWidth)
        guard let h = handle, z.count == dh * dw, framesWritten < Int(meta.nFrames) else { return false }
        let q = DZC.quantise(z: z, h: dh, w: dw)
        guard q.width == Int(meta.width), q.height == Int(meta.height) else { return false }
        let raw = DZC.planeBytesLE(q.plane)
        guard let comp = codec.compress(raw), let off = try? h.offset() else { return false }
        do { try h.write(contentsOf: Data(DZC.record(planeLE: raw, compressed: comp))) } catch { ThreeDDegradeProbe.noteWriteError(error); return false }
        offsets.append(off); framesWritten += 1; return true
    }
    func synchronize() { try? handle?.synchronize() }
    /// Writes index + trailer. Only valid once every frame is written; the file is incomplete (but scannable) until this returns true.
    func finish() -> Bool {
        guard let h = handle, framesWritten == Int(meta.nFrames) else { return false }
        do { try h.write(contentsOf: Data(DZC.tail(offsets: offsets))); try h.close() } catch { ThreeDDegradeProbe.noteWriteError(error); return false }
        handle = nil; return true
    }

    static let lzfse: Codec = (
        { raw in
            #if canImport(Compression)
            var dst = [UInt8](repeating: 0, count: raw.count + raw.count / 8 + 4096)
            let n = compression_encode_buffer(&dst, dst.count, raw, raw.count, nil, COMPRESSION_LZFSE)
            return n > 0 ? Array(dst[0..<n]) : nil
            #else
            return nil
            #endif
        },
        { comp, expected in
            #if canImport(Compression)
            var dst = [UInt8](repeating: 0, count: expected)
            let n = compression_decode_buffer(&dst, dst.count, comp, comp.count, nil, COMPRESSION_LZFSE)
            return n == expected ? dst : nil
            #else
            return nil
            #endif
        })
}

// BEGIN relocated DepthContainerReader.swift (195y G2, behavior unchanged)
/// 190v s16 read side: opens a finished depth_shot_NNNNN.dzc (header, index, "GORDZEND" trailer) and decodes frames. Pure Foundation; the codec is
/// injected (default: the Compression-framework LZFSE of DZCWriter, Mac only). A file without its index and trailer is incomplete and never opens.
/// Frame i has pts (startFrame + i) / (fpsNum / fpsDen) seconds. Planes are the padded width x height uint16 w10 values (no shift, no chroma).
/// Not compiled or run on a Mac.
final class DZCFile {
    let meta: DZC.Meta
    private let data: Data, offsets: [Int]
    var count: Int { offsets.count }
    var fps: Double { Double(meta.fpsNum) / Double(max(1, meta.fpsDen)) }

    /// True when the file is a complete container: header parses, size agrees with n_frames and the last 8 bytes are the trailer.
    static func isComplete(_ url: URL) -> Bool { DZCFile.layout(url) != nil }

    private static func layout(_ url: URL) -> (meta: DZC.Meta, data: Data, offsets: [Int])? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count >= DZC.headerSize + 8,
              let m = DZC.parseHeader([UInt8](d.prefix(DZC.headerSize))), m.nFrames > 0 else { return nil }
        let n = Int(m.nFrames), tail = n * 8 + 8
        guard d.count >= DZC.headerSize + tail, Array(d.suffix(8)) == DZC.trailer else { return nil }
        let idx = [UInt8](d[(d.count - tail)..<(d.count - 8)])
        let offs = (0..<n).map { Int(DZC.rd(idx, $0 * 8, 8)) }
        guard offs.allSatisfy({ $0 >= DZC.headerSize && $0 + 8 <= d.count - tail }) else { return nil }
        return (m, d, offs)
    }

    init?(url: URL) {
        guard let l = DZCFile.layout(url) else { return nil }
        meta = l.meta; data = l.data; offsets = l.offsets
    }

    func pts(_ i: Int) -> Double { Double(Int(meta.startFrame) + i) / fps }

    /// Index of the first frame at/after `pts` (clamped to the last frame).
    func index(atOrAfter pts: Double) -> Int {
        let i = Int((pts * fps).rounded(.up)) - Int(meta.startFrame)
        return min(max(0, i), count - 1)
    }

    /// The decoded plane (width x height little-endian u16 as [UInt16]); nil when the record does not decompress or fails its crc.
    func plane(_ i: Int, decompress: ([UInt8], Int) -> [UInt8]? = DZCWriter.lzfse.decompress) -> [UInt16]? {
        guard offsets.indices.contains(i) else { return nil }
        let o = offsets[i], head = [UInt8](data[o..<(o + 8)])
        let len = Int(DZC.rd(head, 0, 4)), crc = UInt32(DZC.rd(head, 4, 4))
        guard o + 8 + len <= data.count, let raw = decompress([UInt8](data[(o + 8)..<(o + 8 + len)]), Int(meta.planeBytes)),
              raw.count == Int(meta.planeBytes), DZC.crc32(raw) == crc else { return nil }
        return (0..<(raw.count / 2)).map { (index: Int) -> UInt16 in
            let low: UInt16 = UInt16(raw[index * 2])
            let high: UInt16 = UInt16(raw[index * 2 + 1]) << 8
            return low | high
        }
    }
}
// END relocated DepthContainerReader.swift

// BEGIN relocated DepthShotIndex.swift (195y G2, behavior unchanged)
/// Swift port of tools/depth_analysis/prepare_film.find_shot_at_pts (CONTRACT-190v section 7) plus the per-shot horizontal FoV from
/// fov_track.json. Reads <entry>/cuts.json and <entry>/fov_track.json once; a shot is "prepared" iff its complete depth_shot_NNNNN.dzc (CONTRACT s16) AND source_shot_NNNNN.mp4 exist.
struct DepthShotIndex {
    struct Hit: Equatable { let shot: Int; let depth: URL; let frame: Int; let frameInShot: Int; let shotStartPTS: Double; let shotEndPTS: Double }
    let entry: URL, fps: Double, shots: [[Int]], tracks: [(start: Double, end: Double, hfovDeg: Double)]

    init?(entry: URL) {
        func json(_ n: String) -> [String: Any]? {
            (try? Data(contentsOf: entry.appendingPathComponent(n))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        guard let c = json("cuts.json"), let s = c["shots"] as? [[Int]], let f = json("fov_track.json"),
              let fps = (f["fps"] as? NSNumber)?.doubleValue, fps > 0 else { return nil }
        self.entry = entry; self.fps = fps; self.shots = s
        // fov_track shots carry their own [start_pts, end_pts]; match by PTS, never by position
        self.tracks = ((f["shots"] as? [[String: Any]]) ?? []).compactMap { t -> (start: Double, end: Double, hfovDeg: Double)? in
            guard let a = (t["start_pts"] as? NSNumber)?.doubleValue, let b = (t["end_pts"] as? NSNumber)?.doubleValue,
                  let h = (t["hfov_deg"] as? NSNumber)?.doubleValue else { return nil }
            return (a, b, h)
        }
    }

    /// Frame range [first,last] of the shot holding `pts`, prepared or not (the menu gates its entries on it).
    func shotFrames(pts: Double) -> (Int, Int)? {
        let f = Int((pts * fps).rounded(.toNearestOrEven))
        return shots.first(where: { $0.count == 2 && $0[0] <= f && f <= $0[1] }).map { ($0[0], $0[1]) }
    }

    /// nil when no shot covers the PTS or the shot's depth container (complete: index + trailer) or source proxy mp4 is not written yet.
    func find(pts: Double) -> Hit? {
        let f = Int((pts * fps).rounded(.toNearestOrEven))     // Python round(): half to even
        for (i, r) in shots.enumerated() where r.count == 2 && r[0] <= f && f <= r[1] {
            let dz = entry.appendingPathComponent(String(format: "depth_shot_%05d.dzc", i))
            let src = entry.appendingPathComponent(String(format: "source_shot_%05d.mp4", i))   // proxy-only gap (resume): not prepared -> 2D
            guard DZCFile.isComplete(dz), FileManager.default.fileExists(atPath: src.path) else { return nil }
            return Hit(shot: i, depth: dz, frame: f, frameInShot: f - r[0], shotStartPTS: Double(r[0]) / fps, shotEndPTS: Double(r[1]) / fps)
        }
        return nil
    }

    /// Horizontal FoV in radians for Stereo3DRenderer.render(thetaH:), constant per shot (the track's start_pts..end_pts shot holding `pts`).
    /// nil when the track has no usable value there.
    func thetaH(pts: Double) -> Double? {
        guard let t = tracks.first(where: { $0.start - 1e-6 <= pts && pts <= $0.end + 1.0 / fps }), t.hfovDeg > 1, t.hfovDeg < 179 else { return nil }
        return t.hfovDeg * .pi / 180
    }
}
// END relocated DepthShotIndex.swift

// BEGIN relocated DepthFrameReader.swift (195y G2, behavior unchanged)
#if canImport(Metal)
import Metal

/// CONTRACT-190v s16 depth feed: reads depth_shot_NNNNN.dzc (lossless LZFSE w10 planes, DZCFile) and hands each frame to Metal as an r16Unorm texture holding
/// the raw w10 value (0...1023), so decodeDepth runs with shift 0 (no HEVC range or alignment question remains). Frames are keyed by PTS (film seconds).
/// Not run on a Mac: the LZFSE decode and texture upload are unmeasured.
final class DepthFrameReader {
    struct Frame { let pts: Double; let luma: MTLTexture; let width: Int; let height: Int; let rangeOK: Bool }
    private let file: DZCFile, device: MTLDevice
    private var i = 0, stopped = false

    /// nil when the file is missing, incomplete or not a container (caller stays on the 2D path).
    init?(url: URL, device: MTLDevice) {
        guard let f = DZCFile(url: url) else { return nil }
        file = f; self.device = device
    }

    /// The next frame (PTS ascending), or nil at the end, on a corrupt record or after cancel().
    func next() -> Frame? {
        guard !stopped, i < file.count, let plane = file.plane(i) else { return nil }
        let w = Int(file.meta.width), h = Int(file.meta.height)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead; d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        plane.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w * 2) }
        defer { i += 1 }
        return Frame(pts: file.pts(i), luma: t, width: w, height: h, rangeOK: true)
    }

    /// Decodes one frame to metres through Stereo3DRenderer.decodeDepth (shift 0: the texture already holds w10).
    func decode(_ f: Frame, into metric: MTLTexture, renderer: Stereo3DRenderer) -> Bool {
        renderer.decodeDepth(luma: f.luma, metric: metric, shift: 0)
    }

    func cancel() { stopped = true }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190v s35 port of tools/depth_analysis/depth_guards.py (sky far clamp, fade flatten, static-overlay flatten, texture-weighted align fit) plus the jitter_rel metric of
/// failure_probes.metrics. Pure Foundation: compiled and run on Linux against the Python reference (Tests/DepthGuards). Every guard is a no-op outside its failure mode.
/// Deviations from the reference, all on purpose and recorded in the commit note:
///  - local_std mirrors scipy's uniform_filter (mode 'reflect'), the reference's primary path; the numpy fallback (clipped windows, float32 cumsums) is not ported;
///  - the overlay statistics run on the depth-resolution mean-RGB luma, not the full frame (the thresholds are 0-255 units; a downscale smooths motion a little).
enum DepthGuards {
    static var weightedFit = true            // s35: texture-weighted align fit (A-D probe harness measured it on residuals only; see commit note)
    static var skyClamp = true, overlayFlatten = true

    // MARK: helpers
    /// Local std over a win x win box with reflected borders (scipy.ndimage.uniform_filter semantics: x*x filtered separately, var = max(E[x^2] - E[x]^2, 0)).
    static func localStd(_ x: [Float], w: Int, h: Int, win: Int = 5) -> [Float] {
        func box(_ src: [Double]) -> [Double] {
            let r = win / 2
            func refl(_ i: Int, _ n: Int) -> Int { var j = i; if j < 0 { j = -j - 1 }; if j >= n { j = 2 * n - 1 - j }; return min(max(j, 0), n - 1) }
            var tmp = [Double](repeating: 0, count: w * h), out = tmp
            for y in 0..<h { for xx in 0..<w { var s = 0.0; for d in -r...r { s += src[y * w + refl(xx + d, w)] }; tmp[y * w + xx] = s / Double(win) } }
            for y in 0..<h { for xx in 0..<w { var s = 0.0; for d in -r...r { s += tmp[refl(y + d, h) * w + xx] }; out[y * w + xx] = s / Double(win) } }
            return out
        }
        let v = x.map { Double($0) }
        let m = box(v), m2 = box(v.map { $0 * $0 })
        return (0..<(w * h)).map { (index: Int) -> Float in
            let variance: Double = m2[index] - m[index] * m[index]
            let deviation: Double = max(variance, 0).squareRoot()
            return Float(deviation)
        }
    }
    /// numpy.percentile, linear interpolation.
    static func percentile(_ v: [Double], _ q: Double) -> Double {
        let s = v.sorted(); guard !s.isEmpty else { return .nan }
        let pos = q / 100.0 * Double(s.count - 1), lo = Int(pos.rounded(.down)), hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
    /// Mean-RGB luma of an RGBA8 buffer (the overlay / fade / texture input).
    static func meanLuma(rgba: [UInt8]) -> [Float] {
        var o = [Float](); o.reserveCapacity(rgba.count / 4)
        var i = 0; while i + 3 < rgba.count { o.append(Float(Int(rgba[i]) + Int(rgba[i + 1]) + Int(rgba[i + 2])) / 3.0); i += 4 }
        return o
    }
    /// MoGe depth (mw x mh, +inf masked) -> finite mask on the depth grid. Same rule as the reference harness (cv2 bilinear resize, then isfinite): a pixel is finite only when every
    /// bilinear neighbour (borders replicated) is finite, because inf * 0 is nan.
    static func finiteMask(_ src: [Float], mw: Int, mh: Int, dw: Int, dh: Int) -> [Bool] {
        var out = [Bool](repeating: true, count: dw * dh)
        for y in 0..<dh {
            let fy = min(max((Double(y) + 0.5) / Double(dh) * Double(mh) - 0.5, 0), Double(mh - 1)), y0 = Int(fy), y1 = min(y0 + 1, mh - 1)
            for x in 0..<dw {
                let fx = min(max((Double(x) + 0.5) / Double(dw) * Double(mw) - 0.5, 0), Double(mw - 1)), x0 = Int(fx), x1 = min(x0 + 1, mw - 1)
                out[y * dw + x] = src[y0 * mw + x0].isFinite && src[y0 * mw + x1].isFinite && src[y1 * mw + x0].isFinite && src[y1 * mw + x1].isFinite
            }
        }
        return out
    }
    static func pack(_ m: [Bool]) -> [UInt32] {
        var o = [UInt32](repeating: 0, count: (m.count + 31) / 32); for i in 0..<m.count where m[i] { o[i >> 5] |= 1 << UInt32(i & 31) }; return o
    }
    static func unpack(_ b: [UInt32], count: Int) -> [Bool] {
        // 195y native#30: the one-line map expression blew the type-checker time limit in the merged file; explicit loop, identical results.
        var out: [Bool] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let word: Int = i >> 5
            let bit: UInt32 = UInt32(i & 31)
            let present: Bool = word < b.count && ((b[word] >> bit) & 1) == 1
            out.append(present)
        }
        return out
    }

    // MARK: 1. sky
    /// Sky candidates keyed on the MoGe invalid mask: not finite in MoGe, top `topFrac` rows, local luma std <= texThresh.
    static func skyMaskMoGe(luma: [Float], finite: [Bool], w: Int, h: Int, topFrac: Double = 0.5, texThresh: Float = 3.0) -> [Bool] {
        let tex = localStd(luma, w: w, h: h), rows = Int(Double(h) * topFrac)
        return (0..<(w * h)).map { !finite[$0] && ($0 / w) < rows && tex[$0] <= texThresh }
    }
    /// Heuristic candidates (no MoGe mask): valid, top rows, inv <= far * 1.5, low texture.
    static func skyMaskHeuristic(inv: [Float], luma: [Float], w: Int, h: Int, topFrac: Double = 0.5, texThresh: Float = 3.0, farQ: Double = 5.0) -> [Bool] {
        let valid = inv.map { $0.isFinite && $0 > 0 }, vals = (0..<inv.count).filter { valid[$0] }.map { Double(inv[$0]) }
        guard vals.count >= 16 else { return [Bool](repeating: false, count: inv.count) }
        let far = percentile(vals, farQ), tex = localStd(luma, w: w, h: h), rows = Int(Double(h) * topFrac)
        // 195y native#30 sweep: explicit loop, identical results.
        var out: [Bool] = []
        out.reserveCapacity(inv.count)
        for i in 0..<inv.count {
            let ok: Bool = valid[i] && (i / w) < rows && Double(inv[i]) <= far * 1.5 && tex[i] <= texThresh
            out.append(ok)
        }
        return out
    }
    /// Clamp the masked pixels to the far plane (farQ percentile of valid inverse depth). No-op under 16 valid pixels or under 64 masked pixels.
    static func clampSky(inv: [Float], mask: [Bool], farQ: Double = 5.0) -> [Float] {
        let vals = inv.filter { $0.isFinite && $0 > 0 }.map { Double($0) }
        guard vals.count >= 16, mask.reduce(0, { $0 + ($1 ? 1 : 0) }) >= 64 else { return inv }
        let far = Float(percentile(vals, farQ))
        // 195y native#30 sweep: explicit loop, identical results.
        var out: [Float] = []
        out.reserveCapacity(inv.count)
        for i in 0..<inv.count {
            let v: Float = mask[i] ? far : inv[i]
            out.append(v)
        }
        return out
    }
    static func skyFarClamp(inv: [Float], luma: [Float], w: Int, h: Int, topFrac: Double = 0.5, farQ: Double = 5.0, mogeFinite: [Bool]? = nil) -> [Float] {
        if inv.filter({ $0.isFinite && $0 > 0 }).count < 16 { return inv }
        let m = mogeFinite.map { skyMaskMoGe(luma: luma, finite: $0, w: w, h: h, topFrac: topFrac) } ?? skyMaskHeuristic(inv: inv, luma: luma, w: w, h: h, topFrac: topFrac, farQ: farQ)
        return clampSky(inv: inv, mask: m, farQ: farQ)
    }
    /// The same clamp applied to a metric depth frame (inv = 1/z for z > 1e-3; masked pixels become 1/far). Untouched pixels are byte-identical.
    static func clampSkyMetres(z: [Float], mask: [Bool], farQ: Double = 5.0) -> [Float] {
        var vals = [Double](); vals.reserveCapacity(z.count)
        for v in z where v.isFinite && v > 1e-3 { vals.append(1.0 / Double(v)) }
        guard vals.count >= 16, mask.reduce(0, { $0 + ($1 ? 1 : 0) }) >= 64 else { return z }
        let zFar = Float(1.0 / percentile(vals, farQ))
        // 195y native#30 sweep: explicit loop, identical results.
        var out: [Float] = []
        out.reserveCapacity(z.count)
        for i in 0..<z.count {
            let v: Float = mask[i] ? zFar : z[i]
            out.append(v)
        }
        return out
    }

    // MARK: 2. fade
    static func fadeAmounts(meanLuma m: [Double]) -> [Double] {
        var peak: Double = 1e-6
        return m.map { (value: Double) -> Double in
            peak = max(peak, max(value, 1e-6))
            let amount: Double = 1.0 - value / peak
            if amount >= 0.5 { return amount }
            return 0.0
        }
    }
    static func fadeFlatten(inv: [[Float]], meanLuma: [Double]) -> [[Float]] {
        let a = fadeAmounts(meanLuma: meanLuma)
        guard a.contains(where: { $0 > 0 }), let n = inv.first?.count else { return inv }
        var med = [Float](repeating: 0, count: n); var col = [Float](repeating: 0, count: inv.count)
        for p in 0..<n { for t in 0..<inv.count { col[t] = inv[t][p] }; col.sort(); let c = col.count
            med[p] = c % 2 == 1 ? col[c / 2] : Float((Double(col[c / 2 - 1]) + Double(col[c / 2])) / 2.0) }
        var result: [[Float]] = []
        result.reserveCapacity(inv.count)
        for (t, frame) in inv.enumerated() {
            let amount: Double = a[t]
            if amount > 0 {
                var flattened: [Float] = []
                flattened.reserveCapacity(n)
                for pixel in 0..<n {
                    let sourceTerm: Double = (1 - amount) * Double(frame[pixel])
                    let medianTerm: Double = amount * Double(med[pixel])
                    flattened.append(Float(sourceTerm + medianTerm))
                }
                result.append(flattened)
            } else {
                result.append(frame)
            }
        }
        return result
    }

    // MARK: 3. static overlay
    /// Streaming per-pixel luma statistics over a shot (Welford, population std) plus the mean frame-to-frame change.
    struct OverlayAccumulator {
        let w: Int, h: Int
        private(set) var n = 0
        private var mean: [Double], m2: [Double], prev: [Float] = [], motion = 0.0
        init(w: Int, h: Int) { self.w = w; self.h = h; mean = [Double](repeating: 0, count: w * h); m2 = mean }
        var frames: Int { n }
        mutating func add(luma: [Float]) {
            guard luma.count == w * h else { return }
            n += 1; let nn = Double(n)
            for i in 0..<luma.count { let x = Double(luma[i]), d = x - mean[i]; mean[i] += d / nn; m2[i] += d * (x - mean[i]) }
            if !prev.isEmpty { var s = 0.0; for i in 0..<luma.count { s += abs(Double(luma[i]) - Double(prev[i])) }; motion += s / Double(luma.count) }
            prev = luma
        }
        /// Pixels static in screen space while the scene moves (reference static_overlay_mask). nil = no overlay (static scene, too few frames, or coverage outside [minFrac, maxFrac]).
        func mask(sceneMotionThresh: Double = 4.0, staticThresh: Double = 2.0, minFrac: Double = 0.001, maxFrac: Double = 0.35, minFrames: Int = 2) -> [Bool]? {
            guard n >= max(2, minFrames), motion / Double(n - 1) >= sceneMotionThresh else { return nil }
            let m: [Bool] = (0..<(w * h)).map { (index: Int) -> Bool in
                let variance: Double = m2[index] / Double(n)
                return variance.squareRoot() < staticThresh
            }
            let frac = Double(m.reduce(0) { $0 + ($1 ? 1 : 0) }) / Double(m.count)
            return (frac < minFrac || frac > maxFrac) ? nil : m
        }
    }
    static func flattenOverlay(z: [Float], mask: [Bool], zScreen: Float) -> [Float] {
        // 195y native#30 sweep: explicit loop, identical results.
        var out: [Float] = []
        out.reserveCapacity(z.count)
        for i in 0..<z.count {
            let v: Float = mask[i] ? zScreen : z[i]
            out.append(v)
        }
        return out
    }

    // MARK: 4. weighted align fit
    /// Whole-frame low texture (night/noise) starves the weighted fit, so the
    /// weights blend toward uniform by the frame's mean texture (s45; mirror of
    /// tools/depth_analysis/depth_guards.py texture_weights).
    static func textureWeights(luma: [Float], w: Int, h: Int, lo: Float = 1.0, hi: Float = 8.0) -> [Float] {
        let tex = localStd(luma, w: w, h: h)
        let a = Float(min(1.0, tex.reduce(0.0) { $0 + Double($1) } / Double(tex.count) / Double(hi)))
        return tex.map { 1.0 + a * (min(max($0 / hi, lo / hi), 1.0) - 1.0) }
    }

    // MARK: jitter_rel (failure_probes.metrics)
    /// median over consecutive frame pairs of median |inv_t - inv_(t-1)| over pixels valid in both (> 16 of them), divided by the median valid inverse depth of the whole sequence.
    /// Frames are metric depth; inv = 1/z for finite z > 1e-3 (the ratio does not depend on the D_SCALE the reference multiplies in).
    struct JitterAccumulator {
        private var prev: [Float] = [], diffs: [Double] = [], vals: [Float] = []
        let pixelStride: Int
        init(pixelStride: Int = 1) { self.pixelStride = max(1, pixelStride) }
        mutating func add(z: [Float]) {
            let inv: [Float] = z.map { (value: Float) -> Float in
                if value.isFinite && value > 1e-3 { return 1.0 / value }
                return 0
            }
            var d = [Double]()
            if inv.count == prev.count { for i in stride(from: 0, to: inv.count, by: pixelStride) where inv[i] > 0 && prev[i] > 0 { d.append(abs(Double(inv[i]) - Double(prev[i]))) } }
            let need = pixelStride == 1 ? 16 : 16 / pixelStride
            if d.count > need { diffs.append(median(d)) }
            for i in stride(from: 0, to: inv.count, by: pixelStride) where inv[i] > 0 { vals.append(inv[i]) }
            prev = inv
        }
        var value: Double? {
            guard !diffs.isEmpty, !vals.isEmpty else { return nil }
            let m = median(vals.map { Double($0) }); return m > 0 ? median(diffs) / m : nil
        }
        private func median(_ v: [Double]) -> Double { let s = v.sorted(), c = s.count; return c % 2 == 1 ? s[c / 2] : (s[c / 2 - 1] + s[c / 2]) / 2 }
    }
}

// BEGIN relocated DepthUpsample.swift (195y G2, behavior unchanged)
#if canImport(Metal)
import Metal

/// 190v s22 follow-up: the native prepare stores depth at the letterbox box (e.g. 266x150), the renderer needs depth the size of the source picture. This resamples the
/// decoded metric depth to the source size with bilinear, half-pixel centres, edge clamp (cv2.INTER_LINEAR / torch bilinear align_corners=False), done on INVERSE depth
/// (v = 256/Z, the quantised quantity) so disparity is what gets interpolated, then back to Z. A tap with Z <= 0 (invalid) counts as v = 0 (far), exactly what linear
/// interpolation of the stored w10 plane (0 = invalid) does. The source proxy is never resampled. Not compiled or run on a Mac.
enum DepthUpsampleKernel {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void s3d_depth_up(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = dst.get_width(), oh = dst.get_height(), iw = src.get_width(), ih = src.get_height();
        if (gid.x >= ow || gid.y >= oh) return;
        float fx = ((float)gid.x + 0.5f) * (float)iw / (float)ow - 0.5f, fy = ((float)gid.y + 0.5f) * (float)ih / (float)oh - 0.5f;
        float x0f = floor(fx), y0f = floor(fy), ax = fx - x0f, ay = fy - y0f;
        int x0 = clamp((int)x0f, 0, (int)iw - 1), x1 = clamp((int)x0f + 1, 0, (int)iw - 1), y0 = clamp((int)y0f, 0, (int)ih - 1), y1 = clamp((int)y0f + 1, 0, (int)ih - 1);
        float z00 = src.read(uint2(x0, y0)).r, z10 = src.read(uint2(x1, y0)).r, z01 = src.read(uint2(x0, y1)).r, z11 = src.read(uint2(x1, y1)).r;
        float v00 = z00 > 0.0f ? 256.0f / z00 : 0.0f, v10 = z10 > 0.0f ? 256.0f / z10 : 0.0f, v01 = z01 > 0.0f ? 256.0f / z01 : 0.0f, v11 = z11 > 0.0f ? 256.0f / z11 : 0.0f;
        float v = (v00 * (1.0f - ax) + v10 * ax) * (1.0f - ay) + (v01 * (1.0f - ax) + v11 * ax) * ay;
        dst.write(float4(v > 0.0f ? 256.0f / v : 0.0f, 0.0f, 0.0f, 0.0f), gid);
    }
    """

    /// Pure: may a depth box of `d` stand in for a source picture of `s`? Same aspect within 2% (the letterbox box is rounded to whole pixels), never larger than the source.
    static func compatible(depth d: (w: Int, h: Int), source s: (w: Int, h: Int)) -> Bool {
        guard d.w > 0, d.h > 0, s.w > 0, s.h > 0, d.w <= s.w, d.h <= s.h else { return false }
        let a = Double(d.w) / Double(d.h), b = Double(s.w) / Double(s.h)
        return abs(a - b) / b <= 0.02
    }
}

final class DepthUpsampler {
    private let queue: MTLCommandQueue, pipe: MTLComputePipelineState
    init?(device: MTLDevice, queue: MTLCommandQueue) {
        guard let lib = try? device.makeLibrary(source: DepthUpsampleKernel.source, options: nil), let fn = lib.makeFunction(name: "s3d_depth_up"),
              let p = try? device.makeComputePipelineState(function: fn) else { return nil }
        self.queue = queue; pipe = p
    }
    /// `src` r32Float metric depth (the cropped box) -> `dst` r32Float at the source size. false on any resource failure.
    func resample(_ src: MTLTexture, into dst: MTLTexture) -> Bool {
        guard let cb = queue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return false }
        e.setComputePipelineState(pipe); e.setTexture(src, index: 0); e.setTexture(dst, index: 1)
        e.dispatchThreads(MTLSize(width: dst.width, height: dst.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, dst.height), depth: 1))
        e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return cb.status == .completed
    }
}
#endif
// END relocated DepthUpsample.swift

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum DepthTemporalEMA {
    private static let lock = NSLock()
    static var enabled = false                       // mutated only through toggleEnabled() under lock; read only via isEnabled()
    static func setEnabled(_ value: Bool) { lock.lock(); enabled=value; lock.unlock() }
    static func toggleEnabled() { lock.lock(); enabled.toggle(); lock.unlock() }
    static func isEnabled() -> Bool { lock.lock(); defer { lock.unlock() }; return enabled }
    static let alpha: Float = 0.15, epsilon: Float = 1e-4
    struct State {
        /// Frozen at job start (job.experiments): a mid-prepare menu toggle never changes a running job's mode.
        let active: Bool
        private(set) var lo: Float = 0, hi: Float = 0
        private(set) var primed = false
        init(active: Bool = DepthTemporalEMA.isEnabled()) { self.active = active }
        /// Exact restore of the state persisted next to the container (195h r3-3): lo/hi AND primed come from the file; the caller
        /// has already checked the persisted frame count matches the container.
        init(active: Bool, lo: Float, hi: Float, primed: Bool) { self.active = active; self.lo = lo; self.hi = hi; self.primed = primed }
        /// EMA update from the frame's robust range, then the frame renormalised onto the smoothed range. Invalid values (<= 0 or
        /// non-finite) pass through. Fewer than 16 valid samples or a degenerate range: the frame passes through unchanged.
        mutating func apply(_ cur: [Float], alpha a: Float = DepthTemporalEMA.alpha) -> [Float] {
            guard active else { return cur }
            var v = cur.filter { $0.isFinite && $0 > 0 }
            guard v.count >= 16 else { return cur }
            v.sort()
            let lo = v[max(0, Int(Float(v.count - 1) * 0.01))], hi = v[min(v.count - 1, Int(Float(v.count - 1) * 0.99))]
            guard hi - lo > DepthTemporalEMA.epsilon else { return cur }
            if !primed { self.lo = lo; self.hi = hi; primed = true; return cur }
            self.lo = a * lo + (1 - a) * self.lo
            self.hi = a * hi + (1 - a) * self.hi
            let scale = (self.hi - self.lo) / (hi - lo)
            var out = cur
            for i in 0..<cur.count {
                let z = cur[i]
                guard z.isFinite, z > 0 else { continue }
                out[i] = self.lo + (z - lo) * scale
            }
            return out
        }
    }
}
// END relocated DepthTemporalEMA.swift

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum TemporalDepth {
    static var enabled = true
    static let alpha: Float = 0.6, gate: Float = 0.12
    /// out = prev-weighted blend of 1/z; `prev` = the previous OUTPUT frame (recursive EMA). Sizes must match, otherwise `cur` is returned unchanged.
    static func smooth(prev: [Float], cur: [Float], alpha a: Float = TemporalDepth.alpha, gate g: Float = TemporalDepth.gate) -> [Float] {
        guard enabled, prev.count == cur.count else { return cur }
        var out = cur
        for i in 0..<cur.count {
            let c = cur[i], p = prev[i]
            guard c.isFinite, c > 0, p.isFinite, p > 0 else { continue }
            if abs(c - p) > g * p { continue }
            out[i] = 1 / (a / p + (1 - a) / c)
        }
        return out
    }
}
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t native prepare runner, pure math (no CoreML, no Metal): ports of tools/depth_analysis/align.py (ShotAligner), MoGe-2 recover_focal_shift +
/// metric-scale/mask post-processing (microsoft/MoGe moge/model/v2.py infer + geometry_torch.recover_focal_shift) and prepare_film.py's depth quantiser.
/// Tests/DepthPrepareMath keeps a Python mirror checked against align.py and the scipy reference. Swift is only parse-checked on this host.
enum DepthQuant {
    static let dScale: Float = 256.0, vInvMax: Float = 1024.0
    /// prepare_film.write_depth_hevc: z metres -> 10-bit luma. z <= 1e-3 or non-finite -> 0 (masked / infinity). np.rint = half to even.
    static func w10(zMetres z: Float) -> UInt16 {
        guard z.isFinite, z > 1e-3 else { return 0 }
        let inv = dScale / max(z, 1e-3)
        let q = (inv / vInvMax * 1023.0).rounded(.toNearestOrEven)
        return UInt16(min(max(q, 0), 1023))
    }
}

/// Per-shot VDA-relative -> MoGe-metric alignment: scale*vda + shift, least squares per frame, EMA within the shot, reset at cuts.
final class ShotAlignerSwift {
    static let minPairs = 16
    let ema: Double
    private(set) var scale: Double?, shift: Double?
    private(set) var skipped = 0
    init(ema: Double = 0.9) { self.ema = ema }
    func reset() { scale = nil; shift = nil; skipped = 0 }

    /// Closed-form LSQ of reference ~ scale*target + shift over the pairs where both are finite (and `mask`, when given). nil if degenerate.
    /// `weights` (s35, depth_guards.fit_scale_shift_weighted): per-pair weights clipped at 1e-6; nil = the plain LSQ below, unchanged.
    static func fit(target: [Float], reference: [Float], mask: [Bool]? = nil, weights: [Float]? = nil) -> (scale: Double, shift: Double, pairs: Int)? {
        if let wt = weights, wt.count >= min(target.count, reference.count) {
            var n = 0.0, sw = 0.0, st = 0.0, sr = 0.0, stt = 0.0, str = 0.0
            for i in 0..<min(target.count, reference.count) {
                if let m = mask, !m[i] { continue }
                let t = Double(target[i]), r = Double(reference[i]); if !t.isFinite || !r.isFinite { continue }
                let w = max(Double(wt[i]), 1e-6)
                n += 1; sw += w; st += w * t; sr += w * r; stt += w * t * t; str += w * t * r
            }
            guard n >= 1 else { return nil }
            let den = sw * stt - st * st
            guard den > 0, den.isFinite else { return nil }
            let s = (sw * str - st * sr) / den, b = (sr - s * st) / sw
            return s.isFinite && b.isFinite ? (s, b, Int(n)) : nil
        }
        var n = 0.0, st = 0.0, sr = 0.0, stt = 0.0, str = 0.0
        for i in 0..<min(target.count, reference.count) {
            if let m = mask, !m[i] { continue }
            let t = Double(target[i]), r = Double(reference[i])
            if !t.isFinite || !r.isFinite { continue }
            n += 1; st += t; sr += r; stt += t * t; str += t * r
        }
        guard n >= 1 else { return nil }
        let den = n * stt - st * st
        guard den > 0, den.isFinite else { return nil }
        let s = (n * str - st * sr) / den, b = (sr - s * st) / n
        return s.isFinite && b.isFinite ? (s, b, Int(n)) : nil
    }

    /// align.ShotAligner.update: fit this frame (>= 16 finite pairs), EMA into the running estimate; otherwise keep the previous one (1,0 if none).
    func update(vda: [Float], moge: [Float], mask: [Bool]? = nil, weights: [Float]? = nil) {
        if let f = Self.fit(target: vda, reference: moge, mask: mask, weights: weights), f.pairs >= Self.minPairs {
            if let s0 = scale, let b0 = shift { scale = ema * s0 + (1 - ema) * f.scale; shift = ema * b0 + (1 - ema) * f.shift }
            else { scale = f.scale; shift = f.shift }
        } else { skipped += 1 }
    }
    func apply(_ vda: [Float]) -> [Float] {
        let s = Float(scale ?? 1.0), b = Float(shift ?? 0.0)
        return vda.map { $0 * s + b }
    }
}

/// 190v s30: causal EASED application of the per-keyframe EMA (scale, shift), port of align.apply_align_track. Entry i is the EMA value after keyframe k_i; frame f in
/// [k_i, k_(i+1)) lerps linearly from entry (i-1) to entry i over (k_i - k_(i-1)) frames (t = min(1, (f - k_i) / (k_i - k_(i-1)))), holds entry 0 at and before the first
/// keyframe, and holds the last entry once t reaches 1. Depends only on entries with k <= f (causal), so a seek reconstructs identical parameters from the stored track alone.
struct AlignTrack: Equatable {
    struct Entry: Equatable { var k: Int; var scale: Double; var shift: Double }
    var entries: [Entry]
    /// nil scale/shift (no fit yet at that keyframe) -> `default` (the reference passes the shot's final EMA, 1/0 if none).
    init(keyframes: [(k: Int, scale: Double?, shift: Double?)], defaultScale: Double = 1.0, defaultShift: Double = 0.0) {
        entries = keyframes.map { Entry(k: $0.k, scale: $0.scale ?? defaultScale, shift: $0.shift ?? defaultShift) }
    }
    init(json: [[Double]]) { entries = json.filter { $0.count >= 3 }.map { Entry(k: Int($0[0]), scale: $0[1], shift: $0[2]) } }
    var json: [[Double]] { entries.map { [Double($0.k), $0.scale, $0.shift] } }
    /// (scale, shift) applied at frame f. Empty track: the caller's default.
    func params(at f: Int, defaultScale: Double = 1.0, defaultShift: Double = 0.0) -> (scale: Double, shift: Double) {
        guard !entries.isEmpty else { return (defaultScale, defaultShift) }
        var i = 0
        while i + 1 < entries.count && entries[i + 1].k <= f { i += 1 }          // last entry with k <= f (entry 0 before the first keyframe)
        let e = entries[i]
        if i == 0 { return (e.scale, e.shift) }
        let p = entries[i - 1], span = Double(e.k - p.k)
        let t = span > 0 ? min(1.0, Double(f - e.k) / span) : 1.0
        return (p.scale + (e.scale - p.scale) * t, p.shift + (e.shift - p.shift) * t)
    }
    func apply(_ vda: [Float], frame f: Int, defaultScale: Double = 1.0, defaultShift: Double = 0.0) -> [Float] {
        let q = params(at: f, defaultScale: defaultScale, defaultShift: defaultShift)
        return vda.map { (value: Float) -> Float in
            let scaled: Double = Double(value) * q.scale
            return Float(scaled + q.shift)
        }
    }
}

/// MoGe-2: raw network output (points [H*W*3] x,y,z affine-invariant, mask, metric_scale) -> focal, shift, metric depth, hfov.
enum MoGeGeometry {
    /// normalized_view_plane_uv: linspace over +-span*(n-1)/n; focal is relative to the half image diagonal.
    static func uv(_ width: Int, _ height: Int) -> (u: [Double], v: [Double]) {
        let a = Double(width) / Double(height), sx = a / (1 + a * a).squareRoot(), sy = 1 / (1 + a * a).squareRoot()
        func lin(_ span: Double, _ n: Int) -> [Double] {
            let e: Double = span * Double(n - 1) / Double(n)
            // 195y native#30: same type-checker timeout; explicit loop, identical arithmetic order.
            var out: [Double] = []
            out.reserveCapacity(n)
            for i in 0..<n {
                let v: Double = n == 1 ? -e : -e + 2 * e * Double(i) / Double(n - 1)
                out.append(v)
            }
            return out
        }
        return (lin(sx, width), lin(sy, height))
    }

    /// geometry_torch.recover_focal_shift: nearest downsample to 64x64 (torch 'nearest': src = floor(dst * in / out)), masked points, then
    /// min over shift of | f(shift) * xy / (z + shift) - uv | with f the closed-form optimum (focal == nil) or the given focal.
    static func recoverFocalShift(points: [Float], mask: [Bool]?, height: Int, width: Int, focal: Double? = nil,
                                  down: (h: Int, w: Int) = (64, 64)) -> (focal: Double, shift: Double) {
        let g = uv(width, height)
        var px = [Double](), py = [Double](), pz = [Double](), uu = [Double](), vv = [Double]()
        for dy in 0..<down.h {
            let y = min(height - 1, dy * height / down.h)
            for dx in 0..<down.w {
                let x = min(width - 1, dx * width / down.w), i = y * width + x
                if let m = mask, !m[i] { continue }
                px.append(Double(points[i * 3])); py.append(Double(points[i * 3 + 1])); pz.append(Double(points[i * 3 + 2]))
                uu.append(g.u[x]); vv.append(g.v[y])
            }
        }
        let n = px.count
        if n < 2 { return (1, 0) }
        // residual sum of squares at a shift (focal optimal, or fixed)
        func eval(_ s: Double) -> (rss: Double, f: Double) {
            var num = 0.0, den = 0.0
            for i in 0..<n { let d = pz[i] + s; let a = px[i] / d, b = py[i] / d; num += a * uu[i] + b * vv[i]; den += a * a + b * b }
            let f = focal ?? (den > 0 ? num / den : 1.0)
            var rss = 0.0
            for i in 0..<n { let d = pz[i] + s; let a = f * px[i] / d - uu[i], b = f * py[i] / d - vv[i]; rss += a * a + b * b }
            return (rss, f)
        }
        let minZ = pz.min() ?? 0
        // Levenberg-Marquardt on the scalar shift, numeric derivatives, steps keep z + shift > 0. MULTISTART over x0 in {0, .5, 1, 2, 4}, minimum cost wins
        // (CONTRACT-190v s15: the upstream single start x0 = 0 stalls on exact-geometry scenes with a large shift/z ratio). A start with z + x0 <= 0 is infeasible
        // and moved just inside the feasible region.
        func solve(from x0: Double) -> (s: Double, rss: Double, f: Double) {
            var s = x0; if !(minZ + s > 1e-6) { s = 1e-6 - minZ + 1e-3 }
            var cur = eval(s), lambda = 1e-3
            for _ in 0..<100 {
                let h = max(1e-6, abs(s) * 1e-6)
                let p = eval(s + h).rss, m = eval(s - h).rss
                let grad = (p - m) / (2 * h), hess = max((p - 2 * cur.rss + m) / (h * h), 1e-12)
                var moved = false
                for _ in 0..<20 {
                    let step = -grad / (hess * (1 + lambda)), cand = s + step
                    if minZ + cand > 1e-6 {
                        let e = eval(cand)
                        if e.rss <= cur.rss { s = cand; cur = e; lambda = max(lambda * 0.3, 1e-9); moved = abs(step) > 1e-10 * max(1, abs(s)); break }
                    }
                    lambda *= 10
                }
                if !moved { break }
            }
            return (s, cur.rss, cur.f)
        }
        var best = solve(from: 0)
        for x0 in [0.5, 1.0, 2.0, 4.0] { let r = solve(from: x0); if r.rss < best.rss { best = r } }
        return (best.f, best.s)
    }

    /// infer(): depth = z + shift; mask &= depth > 0; depth *= metric_scale; masked -> +inf (the aligner excludes non-finite).
    static func depth(points: [Float], mask: [Bool]?, shift: Double, metricScale: Double) -> [Float] {
        let n = points.count / 3
        return (0..<n).map { i in
            let z = Double(points[i * 3 + 2]) + shift
            let ok = (mask?[i] ?? true) && z > 0
            return ok ? Float(z * metricScale) : Float.infinity
        }
    }

    /// intrinsics fx (normalized by width) = focal/2 * sqrt(1+a^2)/a;  hfov = 2 atan(0.5 / fx), degrees (moge_fov.infer_frame).
    static func hfovDegrees(focal: Double, width: Int, height: Int) -> Double {
        let a = Double(width) / Double(height), fx = focal / 2 * (1 + a * a).squareRoot() / a
        return 2 * atan(0.5 / fx) * 180 / Double.pi
    }
}
// [attribution comment elided]
// [attribution comment elided]
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
    static let minHeadroomBytes: Int64 = 2 << 30 // [attribution comment elided]

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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// CONTRACT-190v s25 default comfort policy, port of tools/depth_analysis/comfort.py (shot_comfort), float64, pure Foundation.
/// Per shot, constant inside the shot (steps only at cuts): z_c = median of ALL valid depth (z > 0, finite) of the shot, B_eff = min(ipd, 2 z_c tan(FAR/2)),
/// depth_scale = B_eff / ipd, z_near = near_clamp(z_c, B_eff); the renderer clamps z to >= z_near before projecting (positive z only, invalid stays invalid).
struct ShotComfort: Equatable {
    static let ipd = 0.063, nearBudgetDeg = 2.0, farBudgetDeg = 1.0
    var convergenceM: Double, ipdEff: Double, depthScale: Double, zNear: Double, farOverflowDeg: Double

    static func nearClamp(zc: Double, ipd: Double = ShotComfort.ipd, budgetDeg: Double = ShotComfort.nearBudgetDeg) -> Double {
        guard ipd > 0 else { return 0 }
        let t = tan(budgetDeg * Double.pi / 360.0 + atan(ipd / (2.0 * zc)))
        return ipd / (2.0 * t)
    }
    static func farOverflow(zc: Double, ipd: Double = ShotComfort.ipd, budgetDeg: Double = ShotComfort.farBudgetDeg) -> Double {
        2.0 * atan(ipd / (2.0 * zc)) * 180.0 / Double.pi - budgetDeg
    }
    static func minConvergence(ipd: Double = ShotComfort.ipd, budgetDeg: Double = ShotComfort.farBudgetDeg) -> Double {
        ipd / (2.0 * tan(budgetDeg * Double.pi / 360.0))
    }
    /// comfort.py disp_deg: + crossed, - uncrossed.
    static func dispDeg(z: Double, zc: Double, ipd: Double = ShotComfort.ipd) -> Double {
        (2.0 * atan(ipd / (2.0 * max(z, 1e-9))) - 2.0 * atan(ipd / (2.0 * zc))) * 180.0 / Double.pi
    }
    /// Menu "strength" on top of the comfort baseline: final eye offset = ipd * depthScale(B_eff / ipd) * factor. Strength <= 1 only shrinks the baseline, so z_near, z_c and both
    /// budgets (2 deg crossed, 1 deg divergence) keep holding. Above 1 it is capped to 1 unless the user explicitly picked an over-budget level (`overBudget`, labelled in the menu).
    static func strengthFactor(_ strength: Double, overBudget: Bool) -> Double {
        guard strength.isFinite, strength > 0 else { return 0 }
        return overBudget ? strength : min(strength, 1.0)
    }
    /// comfort.py shot_comfort for a given shot median; nil for a non-positive or non-finite median.
    static func make(medianZ zc: Double, ipd: Double = ShotComfort.ipd) -> ShotComfort? {
        guard zc.isFinite, zc > 0 else { return nil }
        let b = min(ipd, 2.0 * zc * tan(farBudgetDeg * Double.pi / 360.0))
        return ShotComfort(convergenceM: zc, ipdEff: b, depthScale: b / ipd, zNear: nearClamp(zc: zc, ipd: b), farOverflowDeg: b < ipd ? 0.0 : farOverflow(zc: zc, ipd: ipd))
    }
    /// Exact median (numpy semantics: mean of the two middle values) over the valid values of any number of frames.
    static func median(_ frames: [[Float]]) -> Double? {
        var v: [Double] = []
        for f in frames { for z in f where z.isFinite && z > 0 { v.append(Double(z)) } }
        return medianSorted(v.sorted())
    }
    private static func medianSorted(_ s: [Double]) -> Double? {
        if s.isEmpty { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2.0
    }

    /// Streaming median over the 10-bit .dzc planes (w10 -> z = 256 / (w10 / 1023 * 1024); w10 == 0 is invalid). 1024 counters, so a whole shot costs no memory.
    /// Exactly the median of the dequantised values (z falls as w10 rises); the quantisation is the container's, not added here.
    struct Histogram {
        private(set) var counts = [Int](repeating: 0, count: 1024)
        private(set) var total = 0
        mutating func add(plane: [UInt16]) { for w in plane { let i = Int(w & 1023); if i > 0 { counts[i] += 1; total += 1 } } }
        static func z(w10: Int) -> Double { 256.0 / (Double(w10) / 1023.0 * 1024.0) }
        func quantile(_ q: Double) -> Double? {
            guard total > 0, q.isFinite, q >= 0, q <= 1 else { return nil }
            func at(_ rank: Int) -> Double {
                var seen = 0
                for w in stride(from: 1023, through: 1, by: -1) { seen += counts[w]; if rank < seen { return Histogram.z(w10: w) } }
                return Histogram.z(w10: 1)
            }
            let pos = q * Double(total - 1), i = Int(pos.rounded(.down)), j = min(i + 1, total - 1)
            return at(i) + (at(j) - at(i)) * (pos - Double(i))
        }
        func median() -> Double? { quantile(0.5) }
    }
}

// BEGIN relocated ShotComfortSpan.swift (195y G2, behavior unchanged)
/// F3 (A-D 14:41): the default comfort budget (ShotComfort.make) is derived from ONE number, the shot median, and keeps the divergence limit true for z -> infinity. A shot whose real depth range is small (a flat distant scene: p5..p95 span a fraction of a degree)
/// gets the same baseline as one that fills the budget, so its depth feel is weak. Scale-invariant variant: derive the eye-offset gain from the shot's OWN disparity quantiles, p5 (near side) and p95 (far side), in degrees relative to the convergence z_c:
/// the largest gain s in [minGain, maxGain] with dispDeg(p5, s*ipd) <= nearBudget (2 deg crossed) and dispDeg(p95, s*ipd) >= -farBudget (1 deg uncrossed). Both ceilings hold at the quantiles by construction (bisection on the exact formula, not a small-angle estimate).
/// Pure Foundation. ShotComfortShot derives these quantiles from the finished container; the renderer uses this gain, not the old median-only baseline.
struct ShotComfortSpan: Equatable {
    static let minGain = 0.25, maxGain = 3.0
    var nearClampM: Double, gain: Double, ipdEff: Double, nearDeg: Double, farDeg: Double, spanDeg: Double, spanBeforeDeg: Double, clamped: Bool
    /// zNear/zFar = shot quantiles p5 / p95 of valid depth (metres), zc = convergence (shot median). nil for invalid input.
    static func make(zNear: Double, zFar: Double, zc: Double, ipd: Double = ShotComfort.ipd, nearBudgetDeg: Double = ShotComfort.nearBudgetDeg, farBudgetDeg: Double = ShotComfort.farBudgetDeg) -> ShotComfortSpan? {
        guard zNear.isFinite, zFar.isFinite, zc.isFinite, zNear > 0, zFar >= zNear, zc > 0 else { return nil }
        func ok(_ s: Double) -> Bool {
            ShotComfort.dispDeg(z: zNear, zc: zc, ipd: ipd * s) <= nearBudgetDeg && ShotComfort.dispDeg(z: zFar, zc: zc, ipd: ipd * s) >= -farBudgetDeg
        }
        func span(_ s: Double) -> Double { ShotComfort.dispDeg(z: zNear, zc: zc, ipd: ipd * s) - ShotComfort.dispDeg(z: zFar, zc: zc, ipd: ipd * s) }
        var g: Double
        if ok(maxGain) { g = maxGain }
        else if !ok(minGain) { g = minGain }
        else {
            var lo = minGain, hi = maxGain                       // ok(lo), !ok(hi)
            for _ in 0..<60 { let m = (lo + hi) / 2; if ok(m) { lo = m } else { hi = m } }
            g = lo
        }
        let base = ShotComfort.make(medianZ: zc, ipd: ipd)?.depthScale ?? 1.0
        return ShotComfortSpan(nearClampM: ShotComfort.nearClamp(zc: zc, ipd: ipd * g, budgetDeg: nearBudgetDeg), gain: g, ipdEff: ipd * g, nearDeg: ShotComfort.dispDeg(z: zNear, zc: zc, ipd: ipd * g), farDeg: ShotComfort.dispDeg(z: zFar, zc: zc, ipd: ipd * g),
                               spanDeg: span(g), spanBeforeDeg: span(base), clamped: g == minGain || g == maxGain)
    }
    /// Quantile of the valid depth values (z > 0, finite) of any number of frames, linear interpolation (numpy default); nil if none.
    static func quantile(_ frames: [[Float]], _ q: Double) -> Double? {
        var v: [Double] = []
        for f in frames { for z in f where z.isFinite && z > 0 { v.append(Double(z)) } }
        guard !v.isEmpty else { return nil }
        v.sort(); let pos = q * Double(v.count - 1), i = Int(pos.rounded(.down)), j = min(i + 1, v.count - 1)
        return v[i] + (v[j] - v[i]) * (pos - Double(i))
    }
}
// END relocated ShotComfortSpan.swift

// BEGIN relocated ShotCuts.swift (195y G2, behavior unchanged)
/// 190t native prepare: shot-cut detection (CONTRACT-190v s18, tools/depth_analysis/cuts.py). The detector is a port of ffmpeg's scdet score on the LUMA plane only
/// (measured against `ffmpeg -vf scdet,metadata=print` on a synthetic clip: luma-only mafd matches to 3 decimals, all-planes does not): mafd = SAD(Y, prevY) * 100 / (w*h) / 256,
/// diff = |mafd - prevMafd|, score = clip(min(mafd, diff), 0, 100), cut when score >= 12.0 (frame 0 scores 0). The ranges / rounding rules are the s18 hard semantics.
/// Pure Foundation: tested on Linux against the A-D parity fixture and ffmpeg. The frame feed (AVAssetReader luma) is the runner's job.
enum ShotCuts {
    static let threshold = 12.0
    /// cuts.py detect_cuts: frame = int(t * fps + 0.5), dedup, sort.
    static func frames(fromTimes times: [Double], fps: Double) -> [Int] { Array(Set(times.map { Int($0 * fps + 0.5) })).sorted() }
    /// cuts.py shots_from_cuts: bounds = [0] + cuts(0 < c < n) + [n]; shot i = (bounds[i], bounds[i+1] - 1) inclusive.
    static func shots(nFrames: Int, cuts: [Int]) -> [[Int]] {
        let b = [0] + cuts.filter { $0 > 0 && $0 < nFrames } + [nFrames]
        return (0..<(b.count - 1)).map { [b[$0], b[$0 + 1] - 1] }
    }
}

/// Streaming scorer: feed tightly packed luma planes (w*h bytes, equal size) in display order.
struct SceneScorer {
    private var prev: [UInt8]? = nil, prevMafd = 0.0
    private(set) var frameIndex = -1
    /// (mafd, score) for this frame (frame 0: 0, 0, as ffmpeg).
    mutating func score(luma: [UInt8]) -> (mafd: Double, score: Double) {
        frameIndex += 1
        defer { prev = luma }
        guard let p = prev, p.count == luma.count, !luma.isEmpty else { prevMafd = 0; return (0, 0) }
        var sad: UInt64 = 0
        for i in 0..<luma.count { let a = Int(luma[i]), b = Int(p[i]); sad += UInt64(a > b ? a - b : b - a) }
        let mafd = Double(sad) * 100.0 / Double(luma.count) / 256.0
        let diff = abs(mafd - prevMafd); prevMafd = mafd
        return (mafd, min(max(min(mafd, diff), 0), 100))
    }
}

extension ShotCuts {
    /// Cut frame indices from a luma feed (`next` returns nil at the end). Frame indices are display-order positions, equal to int(t*fps+0.5) for constant-rate video.
    static func detect(next: () -> [UInt8]?, threshold: Double = ShotCuts.threshold) -> (cuts: [Int], nFrames: Int) {
        var s = SceneScorer(), cuts: [Int] = [], n = 0
        while let f = next() { let r = s.score(luma: f); if n > 0, r.score >= threshold { cuts.append(n) }; n += 1 }
        return (cuts, n)
    }
}
// END relocated ShotCuts.swift

// BEGIN relocated ShotComfortShot.swift (195y G2, behavior unchanged)
/// Per-shot span comfort constants straight from the finished depth_shot_NNNNN.dzc: one streaming pass over every frame's w10 plane (ShotComfort.Histogram), no sidecar,
/// so it cannot disagree with the depth that gets rendered. nil (= fixed-parameter render) when the file is unreadable or has no valid depth.
/// p5, median and p95 use numpy-linear quantiles of the same streamed histogram. The plane includes the container's edge padding (at most a few rows/columns of repeated edge values): a sub-percent effect on the median. Not compiled on a Mac.
enum ShotComfortShot {
    static func compute(depth url: URL, ipd: Double = ShotComfort.ipd) -> ShotComfort? {
        guard let f = DZCFile(url: url) else { return nil }
        var h = ShotComfort.Histogram()
        for i in 0..<f.count { guard let p = f.plane(i) else { return nil }; h.add(plane: p) }
        guard let c = h.median(), let lo = h.quantile(0.05), let hi = h.quantile(0.95),
              let span = ShotComfortSpan.make(zNear: lo, zFar: hi, zc: c, ipd: ipd) else { return nil }
        return ShotComfort(convergenceM: c, ipdEff: span.ipdEff, depthScale: span.gain, zNear: span.nearClampM, farOverflowDeg: ShotComfort.farOverflow(zc: c, ipd: span.ipdEff))
    }
}
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
struct ThermalDutyPolicy {
    enum Action: Equatable { case run, suspend, hold, resume }
    static let suspendRank = 2, resumeRank = 1, minSuspend = 60.0, dwell = 30.0
    private(set) var suspendedAt: Double?, clearSince: Double?
    var isSuspended: Bool { suspendedAt != nil }

    /// `rank`: ProcessInfo.ThermalState raw value (0 nominal, 1 fair, 2 serious, 3 critical). `now`: monotonic seconds.
    mutating func step(rank: Int, now: Double) -> Action {
        guard let s = suspendedAt else {
            if rank >= Self.suspendRank { suspendedAt = now; clearSince = nil; return .suspend }
            return .run
        }
        if rank >= Self.resumeRank { clearSince = nil; return .hold }
        if clearSince == nil { clearSince = now }
        if now - s >= Self.minSuspend, now - (clearSince ?? now) >= Self.dwell { suspendedAt = nil; clearSince = nil; return .resume }
        return .hold
    }
}

final class ThreeDThermalGate {
    private var policy = ThermalDutyPolicy()
    private let rank: () -> Int, now: () -> Double, wait: (Double) -> Void
    private let wake = DispatchSemaphore(value: 0)
    private var observer: NSObjectProtocol?
    private(set) var suspends = 0, resumes = 0     // for the Mac verification log

    init(rank: @escaping () -> Int = { ProcessInfo.processInfo.thermalState.rawValue }, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         wait: ((Double) -> Void)? = nil) {
        self.rank = rank; self.now = now
        self.wait = wait ?? { [wake] s in _ = wake.wait(timeout: .now() + s) }
        if wait == nil { observer = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [wake] _ in wake.signal() } }
    }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    /// Call at a frame or shot boundary, after the current frame is finished. Returns immediately while cool; on the first hot reading it runs `checkpoint`
    /// once, reports `paused(true)` and blocks (polling every second, or on thermalStateDidChange) until the policy resumes. false only when `cancelled()`.
    func boundary(checkpoint: () -> Void, paused: (Bool) -> Void, cancelled: () -> Bool) -> Bool {
        while true {
            if cancelled() { return false }
            switch policy.step(rank: rank(), now: now()) {
            case .run: return true
            case .suspend: suspends += 1; checkpoint(); paused(true)
            case .hold: break
            case .resume: resumes += 1; paused(false); return true
            }
            wait(1)
        }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate)
import AVFoundation
import CoreML
import CoreVideo
import Accelerate

/// 190t/190v native prepare runner: the ShotPrepareRunner the delivery lane's ThreeDRunnerRegistry takes. Composition only; every piece it uses is tested elsewhere
/// (cache_key, cuts and fov_track files in PrepareSupport; ShotCuts; ShotPrepare/ShotCheckpoint; DZC writer). UNCOMPILED AND UNRUN (no Mac): AVAssetReader, vImage, CoreML and
/// VideoToolbox calls here are parse-only. Differences from the Python path, all on purpose and recorded in the commit note:
///  - frames reach VDA (154x266) and MoGe (518x294 / 518x518) through vImage high-quality resampling, not cv2 bicubic (small numeric difference, same geometry);
///  - the source proxy is encoded in a second decode pass after the depth container is complete (the VT encoder cannot resume mid-file), 8-bit video range widened
///    to 10-bit MSB-aligned (v8 << 8), no tone or range change;
///  - no per-film numbers: MoGe shape is picked from the source aspect (MoGeInput.pick), quality-first, fp32 fallback inside MoGeKeyframeRunner.
final class NativePrepareRunner: ShotPrepareRunner {
    struct Failure: Error { let reason: String }
    /// `kitDir` = the directory holding the A-D kit packages named in kit_manifest.json (encoder_fp16, bootstrap_fp16, stream_fp16, moge2_vits_WxH_{fp16,fp32}.mlpackage).
    let kitDir: URL, cacheRoot: URL
    private(set) var vda: VDAStreamRunner?, moge: MoGeKeyframeRunner?
    private var windowed: VDAWindowRunner?                  // 190w W4: nil = streaming prepare (kit lacks the windowed packages, or they failed to load)
    init(kitDir: URL, cacheRoot: URL = DepthCachePaths.root) { self.kitDir = kitDir; self.cacheRoot = cacheRoot }

    /// Compiled-model cache under `modelsDir/kit-compiled/<manifest sha>` (pruned of older kit versions); `modelsDir` = ThreeDModels.modelsDir.
    var modelsDir: URL?
    /// Self-test only: stage timings, depth stats and verbatim shot errors (nil = no cost beyond a nil check).
    var telemetry: PrepareTelemetry?
    var externallyHeldModelLane = false // headless self-test holds through realtime/render probes
    /// arch-196b C3: the cooperative-pause flag, set by the prepare-worker CLI. Checked at every ShotSink frame boundary
    /// (the worker parks there with no in-flight model call); default = never paused.
    var pauseRequested: () -> Bool = { false }
    private func loadModels() throws {
        if let m = modelsDir, let sha = KitCompiledCache.manifestSha(kitDir: kitDir) { KitCompiledCache.dir = KitCompiledCache.cacheDir(modelsDir: m, sha: sha); KitCompiledCache.prune(modelsDir: m, keep: sha) }
        if vda == nil {
            let k = VDAStreamRunner.Kit(encoder: kitDir.appendingPathComponent("encoder_fp16.mlpackage"), bootstrap: kitDir.appendingPathComponent("bootstrap_fp16.mlpackage"),
                                        stream: kitDir.appendingPathComponent("stream_fp16.mlpackage"))
            guard let r = VDAStreamRunner(kit: k) else { throw Failure(reason: "VDA CoreML kit did not load") }
            vda = r
        }
        if moge == nil {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: kitDir.path)) ?? []).filter { $0.hasPrefix("moge2_vits_") && $0.hasSuffix(".mlpackage") }
            var by: [String: (fp16: URL?, fp32: URL?)] = [:]
            for n in names {
                let parts = n.replacingOccurrences(of: ".mlpackage", with: "").split(separator: "_")          // moge2 vits 518x294 fp16
                guard parts.count == 4, parts[2].contains("x") else { continue }
                let key = String(parts[2]), u = kitDir.appendingPathComponent(n); var e = by[key] ?? (nil, nil)
                if parts[3] == "fp16" { e.fp16 = u } else if parts[3] == "fp32" { e.fp32 = u }
                by[key] = e
            }
            let pk: [MoGeKeyframeRunner.Package] = by.compactMap { k, v in
                let wh = k.split(separator: "x").compactMap { Int($0) }; guard wh.count == 2 else { return nil }
                return MoGeKeyframeRunner.Package(shape: MoGeInput.Shape(w: wh[0], h: wh[1]), fp16: v.fp16, fp32: v.fp32)
            }
            guard let r = MoGeKeyframeRunner(packages: pk) else { throw Failure(reason: "MoGe CoreML kit did not load") }
            moge = r
        }
    }

    final class LumaBox { var v: [Float]? }

    // MARK: frames

    /// Sequential decode of frames [first, first + count) of the film. Reopens when asked for a frame out of order (resume from a checkpoint).
    final class FrameReader {
        let asset: AVURLAsset, track: AVAssetTrack, fps: Double, format: OSType
        /// s34: `facts` (colorprobe port) switches the reader to DISPLAY geometry (preferredTransform + SAR) through a video composition when the source needs it; `fallbackFormat` is tried
        /// when the first format cannot start (e.g. 10-bit through a composition). nil facts = storage geometry (the scdet reader).
        let facts: SourceFacts?, fallbackFormat: OSType?
        private var reader: AVAssetReader?, out: AVAssetReaderOutput?
        private(set) var nextFrame = 0, last = 0
        init?(url: URL, fps: Double, format: OSType, facts: SourceFacts? = nil, fallbackFormat: OSType? = nil) {
            let a = AVURLAsset(url: url)
            guard let t = a.tracks(withMediaType: .video).first else { return nil }
            asset = a; track = t; self.fps = fps; self.format = format; self.facts = facts; self.fallbackFormat = fallbackFormat
        }
        var size: (w: Int, h: Int) {
            if let f = facts, f.width > 0 { let n = SourceFormat.normalizedSize(f); return (n.w, n.h) }
            return (Int(abs(track.naturalSize.width).rounded()), Int(abs(track.naturalSize.height).rounded()))
        }
        private func makeOutput(_ fmt: OSType) -> AVAssetReaderOutput {
            let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: fmt]
            guard let f = facts, f.width > 0, SourceFormat.needsNormalization(f) else { return AVAssetReaderTrackOutput(track: track, outputSettings: settings) }
            let n = SourceFormat.normalizedSize(f), pt = track.preferredTransform
            let m = SourceFormat.displayTransform(preferred: (Double(pt.a), Double(pt.b), Double(pt.c), Double(pt.d), Double(pt.tx), Double(pt.ty)), sar: f.sar, width: f.width, height: f.height)
            let comp = AVMutableVideoComposition(); comp.renderSize = CGSize(width: n.w, height: n.h)
            let md = track.minFrameDuration; comp.frameDuration = (md.isValid && md.seconds > 0) ? md : CMTime(seconds: 1.0 / fps, preferredTimescale: 60000)
            let ins = AVMutableVideoCompositionInstruction(); ins.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            li.setTransform(CGAffineTransform(a: CGFloat(m.a), b: CGFloat(m.b), c: CGFloat(m.c), d: CGFloat(m.d), tx: CGFloat(m.tx), ty: CGFloat(m.ty)), at: .zero)
            ins.layerInstructions = [li]; comp.instructions = [ins]
            let o = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: settings); o.videoComposition = comp
            return o
        }
        func open(first: Int, last: Int) -> Bool {
            reader?.cancelReading(); reader = nil; out = nil
            for fmt in [format] + (fallbackFormat.map { [$0] } ?? []) {
                guard let r = try? AVAssetReader(asset: asset) else { return false }
                let o = makeOutput(fmt); o.alwaysCopiesSampleData = false
                let start = CMTime(seconds: (Double(first) - 0.5) / fps, preferredTimescale: 60000)       // CFR only: VFR sources are refused before prepare (s34)
                r.timeRange = CMTimeRange(start: max(.zero, start), duration: CMTime(seconds: Double(last - first + 1) / fps, preferredTimescale: 60000))
                guard r.canAdd(o) else { continue }
                r.add(o); guard r.startReading() else { continue }
                reader = r; out = o; nextFrame = first; self.last = last; return true
            }
            return false
        }
        func frame(_ k: Int, last: Int) -> CVPixelBuffer? {
            if reader == nil || k != nextFrame { guard open(first: k, last: last) else { return nil } }
            guard k <= self.last, let s = out?.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(s) else { return nil }
            nextFrame += 1; return pb
        }
        func close() { reader?.cancelReading(); reader = nil; out = nil }
    }

    /// BGRA pixel buffer -> RGBA8 [w * h * 4] at (w, h), vImage high-quality resampling.
    static func resizeRGBA(_ pb: CVPixelBuffer, w: Int, h: Int) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        var src = vImage_Buffer(data: base, height: vImagePixelCount(CVPixelBufferGetHeight(pb)), width: vImagePixelCount(CVPixelBufferGetWidth(pb)), rowBytes: CVPixelBufferGetBytesPerRow(pb))
        var scaled = [UInt8](repeating: 0, count: w * h * 4), rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = scaled.withUnsafeMutableBytes { (sp: UnsafeMutableRawBufferPointer) -> Bool in rgba.withUnsafeMutableBytes { (rp: UnsafeMutableRawBufferPointer) -> Bool in
            var d = vImage_Buffer(data: sp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            guard vImageScale_ARGB8888(&src, &d, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else { return false }
            var o = vImage_Buffer(data: rp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            let map: [UInt8] = [2, 1, 0, 3]                      // BGRA -> RGBA
            return vImagePermuteChannels_ARGB8888(&d, &o, map, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        } }
        return ok ? rgba : nil
    }

    /// 8-bit 4:2:0 biplanar -> 10-bit biplanar of the SAME range (SourceFormat.widen8To10: video range v8 << 8, full range scaled to 1023), same size. A buffer that is already 10-bit passes through.
    static func widen10(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let pf = CVPixelBufferGetPixelFormatType(src)
        if pf == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || pf == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange { return src }
        let full = pf == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src); var dst: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, full ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, nil, &dst) == kCVReturnSuccess, let d = dst else { return nil }
        CVPixelBufferLockBaseAddress(src, .readOnly); CVPixelBufferLockBaseAddress(d, []); defer { CVPixelBufferUnlockBaseAddress(d, []); CVPixelBufferUnlockBaseAddress(src, .readOnly) }
        for plane in 0..<2 {
            guard let sb = CVPixelBufferGetBaseAddressOfPlane(src, plane), let db = CVPixelBufferGetBaseAddressOfPlane(d, plane) else { return nil }
            let rows = CVPixelBufferGetHeightOfPlane(src, plane), cols = CVPixelBufferGetWidthOfPlane(src, plane) * (plane == 0 ? 1 : 2)
            let ss = CVPixelBufferGetBytesPerRowOfPlane(src, plane), ds = CVPixelBufferGetBytesPerRowOfPlane(d, plane)
            for j in 0..<rows {
                let sr = sb.advanced(by: j * ss).assumingMemoryBound(to: UInt8.self), dr = db.advanced(by: j * ds).assumingMemoryBound(to: UInt16.self)
                for i in 0..<cols { dr[i] = SourceFormat.widen8To10(sr[i], fullRange: full) }
            }
        }
        return d
    }

    /// Luma plane of an 8-bit biplanar buffer as a dense [w * h] array (the scdet input).
    static func luma(_ pb: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0), s = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        guard let b = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return [] }
        var out = [UInt8](repeating: 0, count: w * h)
        for j in 0..<h { out.withUnsafeMutableBufferPointer { p in memcpy(p.baseAddress! + j * w, b.advanced(by: j * s), w) } }
        return out
    }

// [attribution comment elided]
// [attribution comment elided]
    private func prepareReadableSource(_ film: URL, entry: URL, cancelled: () -> Bool) throws -> URL {
        if AVURLAsset(url:film).tracks(withMediaType:.video).first != nil { return film }
        let ready=entry.appendingPathComponent("prepare-input.mp4")
        if AVURLAsset(url:ready).tracks(withMediaType:.video).first != nil { return ready }
        let temp=entry.appendingPathComponent("prepare-input.part.mp4")
        defer { try? FileManager.default.removeItem(at:temp) }
        // Stream-copy can be as large as the source; reserve that full bound
        // before launching, then watch free space while ffmpeg is writing.
        let sourceBytes = ((try? FileManager.default.attributesOfItem(atPath: film.path)[.size]) as? NSNumber)?.uint64Value
        guard let sourceBytes else { throw DepthCacheBudget.Failure.unsafe }
        try DepthCacheBudget.enforce(root: cacheRoot, additional: sourceBytes)
        let p=Process();p.executableURL=URL(fileURLWithPath:GORResources.vendorPath("ffmpeg/bin/ffmpeg"))
        p.arguments=PrepareInputRemux.arguments(source:film.path,destination:temp.path)
        p.standardInput=FileHandle.nullDevice;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.standardError
        print("3d-prepare input=remux begin container=\(film.pathExtension) video=stream-copy");fflush(stdout)
        try p.run()
        while p.isRunning && !cancelled() { Thread.sleep(forTimeInterval:0.1) }
        if p.isRunning { p.terminate();p.waitUntilExit();throw Failure(reason:"input remux cancelled") }
        guard p.terminationStatus==0,AVURLAsset(url:temp).tracks(withMediaType:.video).first != nil else {
            throw Failure(reason:"input has no AVFoundation video track; lossless remux failed (see ffmpeg log)")
        }
        try? FileManager.default.removeItem(at:ready)
        try FileManager.default.moveItem(at:temp,to:ready)
        print("3d-prepare input=remux ready video=stream-copy");fflush(stdout)
        return ready
    }

    // MARK: prepare

    func prepare(_ request: ThreeDPrepareLauncher.Request, cancelled: @escaping () -> Bool) throws {
        guard let key = PrepareSupport.cacheKey(path: request.film.path) else { throw Failure(reason: "cannot read the film for its cache key") }
        let entry = cacheRoot.appendingPathComponent(key, isDirectory: true), fps = request.fps, n = request.nFrames
        let cachePin = try DepthCacheBudget.pin(root: cacheRoot, key: key, create: true)
        defer { withExtendedLifetime(cachePin) {} }
        try? FileManager.default.removeItem(at:cacheRoot.appendingPathComponent(".budget-failure"))
        let diskWatch = DepthCacheBudget.Watch(root: cacheRoot)
        defer {if let failure=diskWatch.failure {DepthCacheBudget.recordFailure(failure,root:cacheRoot)}}
        guard diskWatch.allowed(force: true) else { throw diskWatch.failure! }
        // The same cancellation callback is observed by depth, proxy and cuts.
        let callerCancelled = cancelled
        let cancelled: () -> Bool = { callerCancelled() || !diskWatch.allowed() }
        let lane = externallyHeldModelLane ? nil : PrepareProcessLifetime.acquireLane(root: cacheRoot, cancelled: cancelled)
        if !externallyHeldModelLane && lane == nil { return }
        defer { if let lane { PrepareProcessLifetime.releaseLane(lane) } }
        // Validate/remux the video before paying the CoreML model-load cost.
        let remux = entry.appendingPathComponent("prepare-input.mp4")
        let remuxExisted = FileManager.default.fileExists(atPath: remux.path)
        defer { if !remuxExisted || DepthCacheBudget.owned(entry) { DepthCacheBudget.removeTransient(remux, entry: entry) } }
        let readableFilm = try prepareReadableSource(request.film, entry: entry, cancelled: cancelled)
        // s34: colorprobe port. HDR / Dolby Vision / VFR sources are refused (the film plays 2D); rotation + SAR are normalised to display geometry by the readers below.
        let facts = SourceFormatProbe.facts(url: readableFilm)
        if let f = facts {
            let why = SourceFormat.refuseReasons(f); if !why.isEmpty { throw Failure(reason: why.joined(separator: "; ")) }
            telemetry?.note("source_format", "\(f.width)x\(f.height) rot=\(f.rotation) sar=\(f.sar) bits=\(f.bitDepth) range=\(f.fullRange.map { $0 ? "full" : "video" } ?? "untagged") matrix=\(SourceFormat.matrixKey(f)) transfer=\(f.transfer)")
        }
        // 195h r3 + Delivery 5 + A-1: the frozen prepare identity of the REQUEST is parsed FIRST - the DAV2 path never touches the VDA/MoGe kit.
        let expOptions = ThreeDExperimentOptions(experiments: request.experiments)
        // 195h A (Delivery A-5/A-1): the DAV2 producer is independent - a DAV2-only install (no VDA/MoGe kit) runs it. A requested DAV2 job with a
        // missing package FAILS LOUDLY instead of silently preparing default-mode depth under an experimental request (honesty rule).
        var dav2Runner: CoreMLDepthRunner? = nil
        if expOptions.dav2Depth {
            guard let r = CoreMLDepthRunner(modelsDir: ThreeDModels.modelsDir) else { throw Failure(reason: "dav2-small-coreml package missing; run tools/gor-fetch-models.sh or turn off the DAV2 experiment") }
            dav2Runner = r
        }
        if expOptions.requiresVDAMoGeKit {
            try ThreeDStageLog.time("load models (all kit packages)") { try loadModels() }
            if windowed == nil, VDAWindowRunner.available(kitDir: kitDir) { windowed = VDAWindowRunner(kitDir: kitDir); if windowed == nil { telemetry?.note("vda_mode", "windowed kit present but did not load; streaming") } }
            telemetry?.note("vda_mode", windowed != nil ? "windowed (32/10 overlap)" : "streaming")
        }
        guard expOptions.dav2Depth || (vda != nil && moge != nil) else { throw Failure(reason: "models") }

        // 1. cuts (cached in the entry, like prepare_film._cuts_for)
        var shots = PrepareSupport.readCuts(entry: entry) ?? []
        if shots.isEmpty {
            guard let lr = FrameReader(url: readableFilm, fps: fps, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) else { throw Failure(reason: "no video track") }
            var k = 0, stopped = false
            let tCuts = DispatchTime.now()
            let r = ShotCuts.detect(next: {
                if cancelled() { stopped = true; return nil }
                guard k < n, let pb = lr.frame(k, last: n - 1) else { return nil }
                k += 1; ThreeDStageLog.progress("cuts-frames", done: k, total: n); return NativePrepareRunner.luma(pb)
            })
            ThreeDStageLog.progress("cuts-reader-close", done: 0, total: 1)
            lr.close(); ThreeDStageLog.progress("cuts-reader-close", done: 1, total: 1); telemetry?.add("cuts_detect", ms: Double(DispatchTime.now().uptimeNanoseconds - tCuts.uptimeNanoseconds) / 1e6)
            if stopped { return }
            ThreeDStageLog.progress("cuts-persist", done: 0, total: 1)
            shots = ShotCuts.shots(nFrames: n, cuts: r.cuts)
            guard !shots.isEmpty, PrepareSupport.writeCuts(entry: entry, cuts: r.cuts, shots: shots) else { throw Failure(reason: "cut detection produced no shots") }
            ThreeDStageLog.progress("cuts-persist", done: 1, total: 1)
        }
        ThreeDStageLog.progress("depth-setup", done: 0, total: 1)
        guard let sink = ShotSink(entry: entry, shots: shots, fps: fps) else { throw Failure(reason: "cannot open the cache entry") }
        sink.pauseRequested = pauseRequested
        sink.writeCurrentFilm(root: cacheRoot, key: key, nFrames: n)
        var hooks = ShotPrepareHooks.sink(sink, cancelled: cancelled)
        hooks.progress = { ThreeDStageLog.progress($0, done: $1, total: $2) }
        if let t = telemetry { hooks.stage = { t.add($0, ms: $1); ThreeDStageLog.done("prepare " + $0, ms: $1) }; hooks.depthMetres = { t.depthFrame($0) } }

        // 2. shots, nearest the playhead first
        let fm = FileManager.default
        func ready(_ i: Int) -> Bool { DZCFile.isComplete(ShotSink.depthURL(entry, i)) && PrepareSupport.optionsMatch(dzc: ShotSink.depthURL(entry, i), options: expOptions) && fm.fileExists(atPath: ShotSink.sourceURL(entry, i).path) && fm.fileExists(atPath: ShotSink.sidecarURL(entry, i).path) }   // 195h: a container prepared in another experiment mode is NOT ready
        let done = Set(shots.indices.filter(ready))
        let order = PrepareSupport.pendingOrder(shots: shots, done: done, playheadFrame: Int((request.startPTS * fps).rounded()))
        guard let bgra = FrameReader(url: readableFilm, fps: fps, format: kCVPixelFormatType_32BGRA, facts: facts) else { throw Failure(reason: "no video track") }
        let src = bgra.size
        let mogeShape: MoGeInput.Shape? = expOptions.dav2Depth ? nil : moge!.shape(srcW: src.w, srcH: src.h)   // 195h A: DAV2 needs no MoGe shape
        if !expOptions.dav2Depth, mogeShape == nil { throw Failure(reason: "no MoGe shape for \(src.w)x\(src.h)") }
        let box = VDAStream.letterbox(srcW: src.w, srcH: src.h)           // s22: letterbox into 266x154, depth cropped back to box.nw x box.nh (DAV2 output is resized onto the same grid, so sidecar/render geometry is uniform)
        ThreeDStageLog.progress("depth-setup", done: 1, total: 1)
        for i in order {
            if cancelled() { return }
            let s = shots[i][0], e = shots[i][1], count = e - s + 1
            let alignURL = entry.appendingPathComponent(String(format: "shot_%05d.align.json", i))
            // 2a. depth (VDA stream + MoGe keyframes -> .dzc), resumable; skipped when the container is already complete
            if !DZCFile.isComplete(ShotSink.depthURL(entry, i)) || !PrepareSupport.optionsMatch(dzc: ShotSink.depthURL(entry, i), options: expOptions) {   // 195h r3-2: a mismatched container is re-prepared (rebuilt inside ShotPrepare.run, never resumed)
                if PrepareSupport.containerAction(dzc: ShotSink.depthURL(entry, i), options: expOptions) == .rebuild { try? fm.removeItem(at: alignURL) }   // 195h A (Delivery A-3): the other mode's align track never survives a rebuild
                var cache: (k: Int, pb: CVPixelBuffer)? = nil
                func pixels(_ k: Int) -> CVPixelBuffer? {
                    if let c = cache, c.k == k { return c.pb }
                    guard let pb = (self.telemetry?.time("decode") { bgra.frame(s + k, last: e) } ?? bgra.frame(s + k, last: e)) else { return nil }
                    cache = (k, pb); return pb
                }
                // frame k is read for the VDA step; the MoGe keyframe of the same k reuses the cached buffer (frames are requested strictly in order)
                let lumaBox = LumaBox()          // s35: the depth-resolution luma of the frame the VDA step just consumed (guards: texture weights, sky, overlay)
                let mogeIn: (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)? = { k in mogeShape.flatMap { ms in pixels(k).flatMap { NativePrepareRunner.resizeRGBA($0, w: ms.w, h: ms.h) }.map { (rgba: $0, shape: ms) } } }
                let backend: ShotPrepareBackend
                if let dav2 = dav2Runner {
                    // 195h A: DAV2-Small CoreML producer. One fresh backend per shot = the item-3 EMA's shot-boundary reset; its accumulator
                    // resumes EXACTLY through the checkpointed window. mogeKeyframe is nil by design (monocular model).
                    backend = DAV2Backend(runner: dav2, pixels: pixels, outW: box.nw, outH: box.nh, ema: expOptions.dav2TemporalEMA ? ModelDepthEMA() : nil)
                } else if let wr = windowed {
                    // the window source reads ahead: luma + MoGe input are captured per frame at read time (see VDAWindowedBackend)
                    let cur = LumaBox()
                    let wb = VDAWindowedBackend(runner: wr, moge: moge!, frameCount: count, crop: box,
                        vdaInput: { k in pixels(k).flatMap { NativePrepareRunner.resizeRGBA($0, w: box.nw, h: box.nh) }.map { cur.v = DepthGuards.meanLuma(rgba: $0); return VDAStream.chwLetterboxed(rgba: $0, box: box) } },
                        lumaNow: { cur.v }, mogeInput: mogeIn)
                    wb.progress = { ThreeDStageLog.progress("depth-windows", done: $0, total: $1) }
                    wb.stage = { [weak self] n, v in self?.telemetry?.add(n, ms: v) }
                    backend = wb
                } else {
                    let lumaBox = LumaBox()          // s35: the depth-resolution luma of the frame the VDA step just consumed (guards: texture weights, sky, overlay)
                    let nb = NativeShotBackend(vda: vda!, moge: moge!,
                        vdaInput: { k in pixels(k).flatMap { NativePrepareRunner.resizeRGBA($0, w: box.nw, h: box.nh) }.map { lumaBox.v = DepthGuards.meanLuma(rgba: $0); return VDAStream.chwLetterboxed(rgba: $0, box: box) } },
                        mogeInput: mogeIn)
                    nb.crop = box; nb.lumaSource = { lumaBox.v }
                    nb.stage = { [weak self] n, v in self?.telemetry?.add(n, ms: v) }
                    backend = nb
                }
                var job = ShotPrepareJob(shot: i, startFrame: s, frames: count, fps: fps, dzc: ShotSink.depthURL(entry, i),
                                         spool: entry.appendingPathComponent(String(format: "shot_%05d.spool", i)), checkpointURL: entry.appendingPathComponent(String(format: "shot_%05d.ck", i)))
                job.depthW = box.nw; job.depthH = box.nh
                job.experiments = expOptions   // 195h r3: the frozen snapshot travels with the job
                switch ShotPrepare.runResumable(job: job, backend: backend, hooks: hooks) {
                case .cancelled: bgra.close(); return
                case .suspended: bgra.close(); throw Failure(reason: "unexpected suspension")
                case .failed(let why): telemetry?.error("shot \(i) depth: \(why)"); sink.fail(shot: i, why); continue                        // the film goes on; the shot stays unprepared (2D) and is reported in render-ready.json
                case .done(let r):
                    _ = PrepareSupport.mergeFov(entry: entry, fps: fps, shot: i, r.fov)
                    var al: [String: Any] = [:]; if let a = r.alignScale { al["align_scale"] = a }; if let b = r.alignShift { al["align_shift"] = b }; if !r.alignTrack.isEmpty { al["align_track"] = r.alignTrack }   // s30: render reads baked metres; the track is for seek/audit
                    _ = PrepareSupport.writeJSON(al, to: alignURL)
                    try? fm.removeItem(at: job.spool); try? fm.removeItem(at: job.checkpointURL!)
                }
            }
            // 2b. source proxy (HEVC via VideoToolbox), second decode of the shot; no mid-file resume, so a cancel discards the partial file
            if !fm.fileExists(atPath: ShotSink.sourceURL(entry, i).path) || !fm.fileExists(atPath: ShotSink.sidecarURL(entry, i).path) {
                // s34: the proxy is read at the source's bit depth and range (10-bit sources keep 10 bits; full-range sources stay full range) and tagged like the source
                let full = facts?.fullRange ?? false, deep = (facts?.bitDepth ?? 8) >= 10
                let f8 = full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                let f10 = full ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                guard let yr = FrameReader(url: readableFilm, fps: fps, format: deep ? f10 : f8, facts: facts, fallbackFormat: deep ? f8 : nil) else { telemetry?.error("shot \(i) source: no video track"); sink.fail(shot: i, "no video track"); continue }
                guard let enc = sink.beginSource(shot: i, sourceSize: src, sourceFullRange: full, sourceColor: SourceFormatProbe.colorProperties(url: request.film)) else { telemetry?.error("shot \(i) source: could not open the HEVC encoder"); continue }
                var ok = true; let tSrc = DispatchTime.now()
                for k in 0..<count {
                    if !sink.boundary(checkpoint: {}, cancelled: cancelled) { enc.cancel(); yr.close(); bgra.close(); return }
                    ThreeDStageLog.progress("source-proxy-frames", done: k, total: count)
                    guard let pb = yr.frame(s + k, last: e), let wide = NativePrepareRunner.widen10(pb), enc.appendSource(wide, cancelled: cancelled) else { ok = false; break }
                }
                ThreeDStageLog.progress("source-proxy-frames", done: count, total: count)
                yr.close(); telemetry?.add("source_encode", ms: Double(DispatchTime.now().uptimeNanoseconds - tSrc.uptimeNanoseconds) / 1e6)
                if !ok { telemetry?.error("shot \(i) source: proxy encode failed"); enc.cancel(); if cancelled() { bgra.close(); return }; sink.fail(shot: i, "source proxy encode failed"); continue }
                let extra = ((try? Data(contentsOf: alignURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
                sink.finishSource(shot: i, enc, depthSize: (w: box.nw, h: box.nh), extra: extra)
            }
        }
        bgra.close()
    }
}
#endif

// BEGIN relocated PrepareProcessLifetime.swift (195y G2, behavior unchanged)
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A model probe must not outlive the worker that requested it. Process groups
/// alone are insufficient: Foundation may spawn each Process in its own group.
enum PrepareProcessLifetime {
    static let ownerFlag = "--gor-owner-pid"
    static func watchOwner(arguments: [String]) {
        guard let at = arguments.firstIndex(of: ownerFlag), at + 1 < arguments.count,
              let owner = Int32(arguments[at + 1]), owner > 1 else { return }
        // Check before starting CoreML, then independently of its blocked load.
        guard getppid() == owner else { _exit(125) }
        Thread.detachNewThread {
            while getppid() == owner { Thread.sleep(forTimeInterval: 0.1) }
            _exit(125)
        }
    }

    struct Node { let pid: Int32, parent: Int32; let command: String }
    static func processTable() -> [Node] {
        let p=Process(), out=Pipe(); p.executableURL=URL(fileURLWithPath:"/bin/ps")
        p.arguments=["-axo","pid=,ppid=,command="];p.standardOutput=out;p.standardError=FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
        return String(decoding:data,as:UTF8.self).split(separator:"\n").compactMap { line in
            let parts=line.split(maxSplits:2,whereSeparator:{$0 == " " || $0 == "\t"})
            guard parts.count==3,let pid=Int32(parts[0]),let parent=Int32(parts[1]) else{return nil}
            return Node(pid:pid,parent:parent,command:String(parts[2]))
        }
    }
    static func descendants(of root: Int32, nodes: [Node]) -> [Int32] {
        var result:[Int32]=[], frontier=[root]
        while let parent=frontier.popLast() {
            for node in nodes where node.parent==parent && node.pid != root && !result.contains(node.pid) {
                result.append(node.pid);frontier.append(node.pid)
            }
        }
        return result.reversed()
    }
    static func stopDescendants(of root: Int32) {
        for pid in descendants(of:root,nodes:processTable()) { _ = kill(pid,SIGKILL) }
    }
    /// Upgrade cleanup is restricted to orphaned helper modes of this project,
    /// never an interactive app, another project, or a still-owned worker.
    static func reapOrphanedHelpers(executable: URL) {
        let appRoot=executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let current=executable.path
        let previous=appRoot.appendingPathComponent(".gor-stage/gor.app.last/Contents/MacOS/gor").path
        for node in processTable() where node.parent==1 {
            if [current,previous].contains(where:{node.command.hasPrefix($0+" --gor-model-load-probe ") || node.command.hasPrefix($0+" --gor-prepare-worker ")}) {
                _ = kill(node.pid,SIGKILL)
                print("3d-helper reaped_orphan pid=\(node.pid)");fflush(stdout)
            }
        }
    }

    /// Shared by interactive prepare and the background self-test. Cancellation
    /// while waiting is cheap; neither path can load a second model stack.
    static func acquireLane(root: URL, cancelled: () -> Bool) -> Int32? {
        let fd = open(root.appendingPathComponent(".prepare-model-lane.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { return nil }
        while !cancelled() {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
            Thread.sleep(forTimeInterval: 0.1)
        }
        close(fd); return nil
    }
    static func releaseLane(_ fd: Int32) { _ = flock(fd, LOCK_UN); close(fd) }
}
// END relocated PrepareProcessLifetime.swift

// BEGIN relocated PrepareInputRemux.swift (195y G2, behavior unchanged)
/// A lossless container bridge for AVFoundation's prepare reader. Original
/// audio, subtitles and playback remain on the original file in mpv/gorav.
enum PrepareInputRemux {
    static func arguments(source: String, destination: String) -> [String] {
        ["-hide_banner", "-nostdin", "-y", "-i", source, "-map", "0:v:0", "-c:v", "copy", "-an", "-sn", "-dn", "-movflags", "+faststart", destination]
    }
}
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Pure helpers of the native prepare runner (190t/190v), tested on Linux against the Python they mirror: SHA-256 and cache_key (tools/depth_analysis/cache.py), the
/// nearest-playhead-first shot order (prepare_film.work_chunk), and the cuts.json / fov_track.json entry files (prepare_film._cuts_for / work_chunk).
enum SHA256Pure {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
    struct Hasher {
        private var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        private var buf: [UInt8] = [], total: UInt64 = 0
        mutating func update(_ d: [UInt8]) { total += UInt64(d.count); buf += d; var o = 0; while buf.count - o >= 64 { block(Array(buf[o..<(o + 64)])); o += 64 }; buf.removeFirst(o) }
        mutating func update(_ s: String) { update(Array(s.utf8)) }
        private mutating func block(_ b: [UInt8]) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { w[i] = UInt32(b[4 * i]) << 24 | UInt32(b[4 * i + 1]) << 16 | UInt32(b[4 * i + 2]) << 8 | UInt32(b[4 * i + 3]) }
            func rr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
            for i in 16..<64 { let s0 = rr(w[i - 15], 7) ^ rr(w[i - 15], 18) ^ (w[i - 15] >> 3), s1 = rr(w[i - 2], 17) ^ rr(w[i - 2], 19) ^ (w[i - 2] >> 10); w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1 }
            var a = h[0], b_ = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25), ch = (e & f) ^ (~e & g), t1 = hh &+ S1 &+ ch &+ SHA256Pure.k[i] &+ w[i]
                let S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22), mj = (a & b_) ^ (a & c) ^ (b_ & c), t2 = S0 &+ mj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b_; b_ = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b_; h[2] = h[2] &+ c; h[3] = h[3] &+ d; h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        mutating func hex() -> String {
            let bits = total * 8; var pad: [UInt8] = [0x80]; while (buf.count + pad.count) % 64 != 56 { pad.append(0) }
            for i in (0..<8).reversed() { pad.append(UInt8((bits >> (8 * UInt64(i))) & 0xFF)) }
            let t = total; update(pad); total = t
            return h.map { String(format: "%08x", $0) }.joined()
        }
    }
}

enum PrepareSupport {
    /// cache.py cache_key: sha256 over "size:mtime_ns", the first 1 MiB and (size > 2 MiB) the last 1 MiB. nil when the file cannot be read.
    static func cacheKey(path: String) -> String? {
        var st = stat(); guard stat(path, &st) == 0, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        #if canImport(Darwin)
        let ns = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        #else
        let ns = Int64(st.st_mtim.tv_sec) * 1_000_000_000 + Int64(st.st_mtim.tv_nsec)
        #endif
        var h = SHA256Pure.Hasher(); let size = Int64(st.st_size), mb = 1024 * 1024
        h.update("\(size):\(ns)")
        h.update([UInt8]((try? fh.read(upToCount: mb)) ?? Data()))
        if size > 2 * Int64(mb) { try? fh.seek(toOffset: UInt64(size - Int64(mb))); h.update([UInt8]((try? fh.read(upToCount: mb)) ?? Data())) }
        return h.hex()
    }

    /// prepare_film.work_chunk order: shots missing depth or source, nearest the playhead first (the shot holding it, then by distance, ties to the lower index).
    static func pendingOrder(shots: [[Int]], done: Set<Int>, playheadFrame: Int?) -> [Int] {
        let pending = shots.indices.filter { !done.contains($0) }
        guard let p = playheadFrame else { return pending }
        func dist(_ i: Int) -> Int { let s = shots[i][0], e = shots[i][1]; return (s <= p && p <= e) ? 0 : min(abs(p - s), abs(p - e)) }
        return pending.sorted { (dist($0), $0) < (dist($1), $1) }
    }

    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
    /// 195h r2-5/r3-2 + Delivery block 2: does one prepared depth CONTAINER match this request's PREPARE identity? Prepare identity is the
    /// depth-mode switches alone (today: B depth-range EMA; item A adds the depth model). E/G/hole are render-only: they re-RENDER through
    /// the render key but must never mark a depth container mismatched. An absent marker is pre-195h depth: EMA off, whatever E/G/hole say.
    static func optionsMatch(dzc: URL, options: ThreeDExperimentOptions) -> Bool {
        identityMatch(readJSON(dzc.appendingPathExtension("options.json")), options: options)
    }
    /// 195h A (Delivery A-4): the prepare identity recorded in BOTH markers (the container's options.json and the pre-phase-1
    /// spool identity.json). The marker names the depth MODEL and smoother too; an absent marker is pre-195h work, matching only the all-off identity.
    static func prepareIdentity(_ options: ThreeDExperimentOptions) -> [String: Any] {
        ["depth_range_ema": options.depthRangeEMA,
         "depth_model": options.dav2Depth ? DepthModelID.dav2_small_coreml.rawValue : DepthModelID.luma_y_prior.rawValue,
         "dav2_temporal_ema": options.dav2TemporalEMA]
    }
    static func identityMatch(_ o: [String: Any]?, options: ThreeDExperimentOptions) -> Bool {
        guard let o = o else { return !options.depthRangeEMA && !options.dav2Depth && !options.dav2TemporalEMA }
        return (o["depth_range_ema"] as? Bool ?? false) == options.depthRangeEMA
            && (o["depth_model"] as? String ?? DepthModelID.luma_y_prior.rawValue) == (options.dav2Depth ? DepthModelID.dav2_small_coreml.rawValue : DepthModelID.luma_y_prior.rawValue)
            && (o["dav2_temporal_ema"] as? Bool ?? false) == options.dav2TemporalEMA
    }
    /// 195h r3-2: what the prepare job must do with the container at `dzc`, decided BEFORE the writer opens. .rebuild = a mismatched
    /// existing container is never resumed: the caller removes it and writes a fresh one in the request's mode.
    enum ContainerAction: String { case fresh, resume, rebuild }
    static func containerAction(dzc: URL, options: ThreeDExperimentOptions) -> ContainerAction {
        guard FileManager.default.fileExists(atPath: dzc.path) else { return .fresh }
        return optionsMatch(dzc: dzc, options: options) ? .resume : .rebuild
    }
    /// 195h A (Delivery A-4): the identity marker written BEFORE phase 1 next to the spool/checkpoint it covers. The container's
    /// options.json exists only once phase 2 opened the writer, so a phase-1 interruption leaves per-shot work no container fence can
    /// see; the next job in another mode checks THIS marker before touching that work.
    static func spoolIdentityURL(spool: URL) -> URL { spool.appendingPathExtension("identity.json") }
    /// The same shot's align sidecar (shot_NNNNN.spool -> shot_NNNNN.align.json, NativePrepareRunner).
    static func alignURL(spool: URL) -> URL { spool.deletingPathExtension().appendingPathExtension("align.json") }
    /// What to do with per-shot phase-1 work when NO container exists yet: a mismatched spool/checkpoint is never resumed.
    static func spoolAction(spool: URL, checkpoint: URL?, options: ThreeDExperimentOptions) -> ContainerAction {
        let fm = FileManager.default
        let hasWork = fm.fileExists(atPath: spool.path) || checkpoint.map { fm.fileExists(atPath: $0.path) } == true
        guard hasWork else { return .fresh }
        return identityMatch(readJSON(spoolIdentityURL(spool: spool)), options: options) ? .resume : .rebuild
    }
    static func writeJSON(_ obj: Any, to url: URL) -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return false }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-" + url.lastPathComponent)
        guard (try? d.write(to: tmp)) != nil else { return false }
        try? FileManager.default.removeItem(at: url); return (try? FileManager.default.moveItem(at: tmp, to: url)) != nil
    }
    /// cuts.json = {"cuts": [...], "shots": [[s, e], ...]} (prepare_film._cuts_for). Returns the cached shots when present.
    static func readCuts(entry: URL) -> [[Int]]? {
        guard let d = try? Data(contentsOf: entry.appendingPathComponent("cuts.json")), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let s = o["shots"] as? [[Int]], !s.isEmpty else { return nil }
        return s
    }
    static func writeCuts(entry: URL, cuts: [Int], shots: [[Int]]) -> Bool { writeJSON(["cuts": cuts, "shots": shots], to: entry.appendingPathComponent("cuts.json")) }
    /// fov_track.json = {"fps": fps, "shots": [entry or null per shot]}: set shot `i`, padding with null (work_chunk).
    static func mergeFov(entry: URL, fps: Double, shot i: Int, _ e: FovTrackBuilder.Entry) -> Bool {
        let u = entry.appendingPathComponent("fov_track.json")
        var shots = ((try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["shots"] as? [Any]) ?? []
        while shots.count <= i { shots.append(NSNull()) }
        shots[i] = e.json
        return writeJSON(["fps": fps, "shots": shots], to: u)
    }
}

// BEGIN relocated PrepareWorkerJob.swift (195y G2, behavior unchanged)
/// 195h Delivery (process boundary): the prepare-worker job file contract, isolated pure-Foundation so production AND the Linux test
/// driver compile this exact type (no shadow copy). `experiments` (the prepare-component string, e.g. "ema") is written by
/// PrepareWorker.spawn from req.experiments and read back through `request`; pre-195h job files without the key decode to the default
/// mode (""), never as an error.
struct PrepareWorkerJob: Codable {
    let film: String, fps: Double, frames: Int, start: Double, quality: String
    let kit: String, cache: String, models: String?
    let experiments: String
    /// arch-196b C3: the cooperative-pause flag path (a sibling of this job file). The worker polls it at every frame boundary;
    /// "" = never paused. Pre-C3 job files without the key decode to "", never as an error.
    let pauseFlag: String
    init(film: String, fps: Double, frames: Int, start: Double, quality: String, kit: String, cache: String, models: String?, experiments: String = "", pauseFlag: String = "") {
        self.film = film; self.fps = fps; self.frames = frames; self.start = start; self.quality = quality
        self.kit = kit; self.cache = cache; self.models = models; self.experiments = experiments; self.pauseFlag = pauseFlag
    }
    /// 195h Delivery (process boundary): the prepare-mode identity crosses to the worker in this file; a pre-195h job file without
    /// the key decodes as the default mode (""), never as an error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        film = try c.decode(String.self, forKey: .film); fps = try c.decode(Double.self, forKey: .fps)
        frames = try c.decode(Int.self, forKey: .frames); start = try c.decode(Double.self, forKey: .start)
        quality = try c.decode(String.self, forKey: .quality); kit = try c.decode(String.self, forKey: .kit)
        cache = try c.decode(String.self, forKey: .cache); models = try c.decodeIfPresent(String.self, forKey: .models)
        experiments = try c.decodeIfPresent(String.self, forKey: .experiments) ?? ""
        pauseFlag = try c.decodeIfPresent(String.self, forKey: .pauseFlag) ?? ""
    }
    var request: ThreeDPrepareLauncher.Request { .init(film: URL(fileURLWithPath: film), fps: fps, nFrames: frames, startPTS: start, quality: quality, experiments: experiments) }
}
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 3D self-test telemetry (Main 09:04): stage timings, notes, thermal transitions, depth stats and verbatim errors, rendered as stable `gor3d-selftest` log lines
/// the next iteration parses (`PrepareTelemetry.parse`). Pure Foundation: the format is pinned on Linux. Thread-safe (prepare thread, thermal observer, render).
final class PrepareTelemetry {
    static let tag = "gor3d-selftest", version = 1
    struct Stage: Equatable { var ms = 0.0, n = 0, max = 0.0 }
    struct Thermal: Equatable { var tMs: Double; var level: Int }
    struct DepthStats: Equatable { var min = Double.infinity, max = -Double.infinity, nan = 0, inf = 0, count = 0 }

    private let lock = NSLock()
    private(set) var stages: [(name: String, s: Stage)] = []
    private(set) var notes: [(key: String, value: String)] = []
    private(set) var errors: [String] = []
    private(set) var thermal: [Thermal] = []
    private(set) var depth = DepthStats()
    private let t0 = DispatchTime.now()

    var elapsedMs: Double { Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6 }
    func add(_ name: String, ms: Double) {
        lock.lock(); defer { lock.unlock() }
        if let i = stages.firstIndex(where: { $0.name == name }) { stages[i].s.ms += ms; stages[i].s.n += 1; stages[i].s.max = Swift.max(stages[i].s.max, ms) }
        else { stages.append((name, Stage(ms: ms, n: 1, max: ms))) }
    }
    func time<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let s = DispatchTime.now(); defer { add(name, ms: Double(DispatchTime.now().uptimeNanoseconds - s.uptimeNanoseconds) / 1e6) }
        return try body()
    }
    /// s31 (CONTRACT-190v real-time budget): turns the measured stage totals into per-frame milliseconds beside the ANALYTICAL s31 estimates (VR180 worst: VDA 8.2, MoGe amortised 9.6,
    /// post 0.4, VT ~2 ms/frame; MoGe keyframe burst 114.6 ms), so the first Mac run shows how far the model is off. `frames` = frames the shot's prepare covered. Missing stages are
    /// simply omitted. The render stage is the self-test's small eyeN=256 clip: its per-frame ms is a lower bound, not the 60 fps VR180 post cost.
    func addRealtimeBudget(frames: Int, keyframeStride: Int = 12) {
        guard frames > 0 else { return }
        func st(_ n: String) -> Stage? { lock.lock(); defer { lock.unlock() }; return stages.first(where: { $0.name == n })?.s }
        func ms(_ v: Double) -> String { String(format: "%.2f", v) }
        var model = 0.0, haveModel = false
        if let v = st("vda_step_total"), v.n > 0 { note("rt_vda_ms_per_frame", ms(v.ms / Double(v.n)) + " (s31 est 8.2 VR180)"); model += v.ms / Double(frames); haveModel = true }
        if let m = st("moge_step_total"), m.n > 0 {
            note("rt_moge_ms_per_keyframe", ms(m.ms / Double(m.n)) + " max " + ms(m.max) + " (s31 est 28.6 16:9, 114.6 VR180)")
            note("rt_moge_ms_amortized", ms(m.ms / Double(frames)) + " per frame at stride \(keyframeStride) (s31 est 9.6)"); model += m.ms / Double(frames); haveModel = true
        }
        if let r = st("render_shot") { note("rt_render_ms_per_frame", ms(r.ms / Double(frames)) + " (eyeN 256 clip, lower bound)") }
        if haveModel {
            note("rt_model_ms_per_frame", ms(model) + " (VDA + amortised MoGe)")
            for fps in [24.0, 30.0, 60.0] { note("rt_budget_\(Int(fps))fps", ms(1000 / fps) + " ms/frame: " + (model <= 1000 / fps ? "model pair fits" : "model pair BREAKS")) }
            if let m = st("moge_step_total"), m.n > 0 { note("rt_keyframe_burst_vs_frame_60fps", m.max > 1000.0 / 60 ? "burst exceeds a 60 fps frame (must stay off the playback thread)" : "burst fits a 60 fps frame") }
        }
    }
    /// s32 `rtstage` lines (CONTRACT-190v s32): per-stage real-time ms, `ms` = MEAN per unit (per frame; per keyframe for moge), n units, max_ms the worst one. Emit order = `rtOrder`.
    static let rtOrder = ["vda", "moge", "upsample", "surround", "render", "vt_decode", "vt_encode"]
    private(set) var rtStages: [(name: String, s: Stage)] = []
    func rtStage(_ name: String, meanMs: Double, n: Int, maxMs: Double) {
        lock.lock(); defer { lock.unlock() }
        rtStages.removeAll { $0.name == name }; rtStages.append((name, Stage(ms: meanMs, n: n, max: maxMs)))
    }
    /// Mean-per-unit rtstage from a recorded stage total (vda per frame, moge per keyframe).
    func rtStageFromTotal(_ name: String, stage: String) {
        lock.lock(); let st = stages.first(where: { $0.name == stage })?.s; lock.unlock()
        if let s = st, s.n > 0 { rtStage(name, meanMs: s.ms / Double(s.n), n: s.n, maxMs: s.max) }
    }
    func note(_ key: String, _ value: String) { lock.lock(); notes.append((key, value)); lock.unlock() }
    func error(_ text: String) { lock.lock(); errors.append(text); lock.unlock() }
    /// Records a thermal level (0 nominal ... 3 critical); only changes are kept, the first sample is always kept.
    func thermalSample(level: Int) { lock.lock(); if thermal.last?.level != level { thermal.append(Thermal(tMs: elapsedMs, level: level)) }; lock.unlock() }
    var peakThermal: Int { lock.lock(); defer { lock.unlock() }; return thermal.map { $0.level }.max() ?? -1 }
    private var jitter = DepthGuards.JitterAccumulator(pixelStride: 2)       // s35: depth jitter per frame (failure_probes jitter_rel), reported once in the log
    func depthFrame(_ z: [Float]) {
        var mn = Double.infinity, mx = -Double.infinity, nan = 0, inf = 0
        for v in z { if v.isNaN { nan += 1 } else if v.isInfinite { inf += 1 } else { let d = Double(v); if d < mn { mn = d }; if d > mx { mx = d } } }
        lock.lock(); jitter.add(z: z); depth.min = Swift.min(depth.min, mn); depth.max = Swift.max(depth.max, mx); depth.nan += nan; depth.inf += inf; depth.count += z.count; lock.unlock()
    }

    // MARK: log format. One line per fact: `gor3d-selftest v1 <kind> k=v k=v`; values never contain spaces except `error`/`note` text, which is the line tail after `msg=`/`value=`.
    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") }
    static func unescape(_ s: String) -> String {
        var out = "", it = s.makeIterator()
        while let c = it.next() { if c == "\\", let n = it.next() { out.append(n == "n" ? "\n" : (n == "r" ? "\r" : n)) } else { out.append(c) } }
        return out
    }
    private static func f(_ v: Double) -> String { v.isFinite ? String(format: "%.3f", v) : (v.isNaN ? "nan" : (v > 0 ? "inf" : "-inf")) }

    func lines(header: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let p = "\(Self.tag) v\(Self.version) "
        var out = [p + "begin " + Self.escape(header)]
        for (n, s) in stages { out.append(p + "stage name=\(n) ms=\(Self.f(s.ms)) n=\(s.n) max_ms=\(Self.f(s.max))") }
        for t in thermal { out.append(p + "thermal t_ms=\(Self.f(t.tMs)) level=\(t.level)") }
        out.append(p + "thermal_peak level=\(thermal.map { $0.level }.max() ?? -1) transitions=\(Swift.max(0, thermal.count - 1))")
        out.append(p + "depth min=\(Self.f(depth.min)) max=\(Self.f(depth.max)) nan=\(depth.nan) inf=\(depth.inf) count=\(depth.count)")
        for (k, v) in notes { out.append(p + "note key=\(k) value=" + Self.escape(v)) }
        if let j = jitter.value { out.append(p + "note key=jitter_rel value=" + Self.f(j) + " (median |d inv|/median inv per frame, pixel stride 2; dark/noisy scenes measured 0.25, healthy < 0.05)") }
        for n in Self.rtOrder { if let r = rtStages.first(where: { $0.name == n }) { out.append(p + "rtstage name=\(n) ms=\(Self.f(r.s.ms)) n=\(r.s.n) max_ms=\(Self.f(r.s.max))") } }
        for (i, e) in errors.enumerated() { out.append(p + "error i=\(i) msg=" + Self.escape(e)) }
        out.append(p + "end errors=\(errors.count) total_ms=\(Self.f(elapsedMs))")
        return out
    }

    struct Parsed: Equatable {
        var header = "", stages: [String: Stage] = [:], thermal: [Thermal] = [], peak = -2, transitions = -1, depth = DepthStats(), notes: [String: String] = [:], errors: [String] = [], ended = false, rtstages: [String: Stage] = [:]
    }
    /// Reads back any lines of this version out of a larger log (other lines are ignored).
    static func parse(_ log: [String]) -> Parsed {
        var r = Parsed(); let p = "\(tag) v\(version) "
        func kv(_ s: Substring) -> [String: String] { var d: [String: String] = [:]; for part in s.split(separator: " ") { if let e = part.firstIndex(of: "=") { d[String(part[..<e])] = String(part[part.index(after: e)...]) } }; return d }
        func num(_ s: String?) -> Double { switch s { case "nan": return .nan; case "inf": return .infinity; case "-inf": return -.infinity; default: return Double(s ?? "") ?? .nan } }
        for line in log {
            guard let rng = line.range(of: p) else { continue }
            let rest = line[rng.upperBound...]
            if rest.hasPrefix("begin ") { r.header = unescape(String(rest.dropFirst(6))) }
            else if rest.hasPrefix("stage ") { let d = kv(rest.dropFirst(6)); if let n = d["name"] { r.stages[n] = Stage(ms: num(d["ms"]), n: Int(d["n"] ?? "") ?? 0, max: num(d["max_ms"])) } }
            else if rest.hasPrefix("rtstage ") { let d = kv(rest.dropFirst(8)); if let n = d["name"] { r.rtstages[n] = Stage(ms: num(d["ms"]), n: Int(d["n"] ?? "") ?? 0, max: num(d["max_ms"])) } }
            else if rest.hasPrefix("thermal_peak ") { let d = kv(rest.dropFirst(13)); r.peak = Int(d["level"] ?? "") ?? -2; r.transitions = Int(d["transitions"] ?? "") ?? -1 }
            else if rest.hasPrefix("thermal ") { let d = kv(rest.dropFirst(8)); r.thermal.append(Thermal(tMs: num(d["t_ms"]), level: Int(d["level"] ?? "") ?? -1)) }
            else if rest.hasPrefix("depth ") { let d = kv(rest.dropFirst(6)); r.depth = DepthStats(min: num(d["min"]), max: num(d["max"]), nan: Int(d["nan"] ?? "") ?? 0, inf: Int(d["inf"] ?? "") ?? 0, count: Int(d["count"] ?? "") ?? 0) }
            else if rest.hasPrefix("note key=") { let t = rest.dropFirst(9); if let sp = t.range(of: " value=") { r.notes[String(t[..<sp.lowerBound])] = unescape(String(t[sp.upperBound...])) } }
            else if rest.hasPrefix("error i=") { if let m = rest.range(of: " msg=") { r.errors.append(unescape(String(rest[m.upperBound...]))) } }
            else if rest.hasPrefix("end ") { r.ended = true }
        }
        return r
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// OSD text for "Prepare film" (190u U2). Reads <cacheRoot>/current-film.json
/// {"progress_path","n_frames","cache_key"} and the progress.json it names
/// {"prepared":[[first,last],...]} (inclusive ranges). The string matches
/// PrepareFilm.status() in tools/depth_analysis/prepare_film.py.
/// Not wired to a cache root or an OSD surface yet; pure and side-effect free.
enum FilmPrepareStatus {
    static func text(prepared: Int, total: Int) -> String {
        prepared < total ? "3D prepared: \(prepared)/\(total) frames" : "3D prepared: full film"
    }

    static func preparedFrames(_ ranges: [[Int]]) -> Int {
        ranges.reduce(0) { $0 + (($1.count == 2 && $1[1] >= $1[0]) ? $1[1] - $1[0] + 1 : 0) }
    }

    /// nil when no 3D film is open or the files are unreadable (OSD shows nothing).
    static func read(cacheRoot: URL) -> String? {
        guard let ptrData = try? Data(contentsOf: cacheRoot.appendingPathComponent("current-film.json")),
              let ptr = try? JSONSerialization.jsonObject(with: ptrData) as? [String: Any],
              let path = ptr["progress_path"] as? String, let total = ptr["n_frames"] as? Int, total > 0 else { return nil }
        var ranges: [[Int]] = []
        if let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let r = j["prepared"] as? [[Int]] { ranges = r }
        return text(prepared: min(preparedFrames(ranges), total), total: total)
    }
}

/// CONTRACT-190v section 4. Cache root = Application Support/gor/depth-cache (the analysis lane writes
/// current-film.json and progress.json there; this app only reads them and writes render-prefs.json).
enum DepthCachePaths {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gor/depth-cache", isDirectory: true)
    }
}

/// <cache_root>/render-prefs.json, atomic tmp+rename. Defaults match the contract; E-G re-reads on change.
enum RenderPrefs {
    static let modes = ["off", "sbs", "full_sbs", "half_sbs", "over_under", "anaglyph", "vr180"]   // s36: "sbs" = legacy alias of full_sbs
    static func json(mode: String, depthScale: Double = 1.0, ipdM: Double = 0.063, convergenceM: Double? = nil, screenDeg: Double? = nil, surroundSoft: Bool? = nil, overBudget: Bool = false) -> Data? {
        guard modes.contains(mode), depthScale.isFinite, depthScale >= 0, ipdM.isFinite, ipdM > 0 else { return nil }
        if let d = screenDeg, !(d.isFinite && (d == 0 || (d >= 20 && d <= 150))) { return nil }   // screen_deg: 0 = legacy shot fov, else 20...150
        var o: [String: Any] = ["mode": mode, "depth_scale": depthScale, "ipd_m": ipdM]
        o["convergence_m"] = convergenceM ?? NSNull()
        if let d = screenDeg { o["screen_deg"] = d }
        if let v = surroundSoft { o["surround"] = v ? "soft" : "off" }
        if overBudget { o["over_budget"] = true }
        return try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    }
    @discardableResult
    static func write(mode: String, depthScale: Double = 1.0, ipdM: Double = 0.063, convergenceM: Double? = nil, screenDeg: Double? = nil, surroundSoft: Bool? = nil, overBudget: Bool = false, root: URL = DepthCachePaths.root) -> Bool {
        guard let data = json(mode: mode, depthScale: depthScale, ipdM: ipdM, convergenceM: convergenceM, screenDeg: screenDeg, surroundSoft: surroundSoft, overBudget: overBudget) else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let tmp = root.appendingPathComponent("render-prefs.json.tmp"), dst = root.appendingPathComponent("render-prefs.json")
        do { try data.write(to: tmp); _ = try fm.replaceItemAt(dst, withItemAt: tmp); return true } catch { return false }
    }
}

/// Shows the prepared-range text through mpv show-text, only when it changes. Polls every 2 s on the main run loop;
/// does nothing until current-film.json exists (3D mode open). Reads only; never touches the analysis cache.
final class FilmPrepareOSD {
    static let shared = FilmPrepareOSD()
    private var timer: Timer?
    private var lastShown: String?
    func start(send: @escaping (String) -> Void) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if UserDefaults.standard.object(forKey: "gor.3d.osdLine") != nil, !UserDefaults.standard.bool(forKey: "gor.3d.osdLine") { return }   // menu: osd line off
            guard let self, let t = FilmPrepareStatus.read(cacheRoot: DepthCachePaths.root), t != self.lastShown else { return }
            self.lastShown = t
            send(t)
        }
        timer?.tolerance = 0.5
    }
}

/// CONTRACT-190v section 4 availability: SBS and VR180 are enabled for a frame range iff it lies inside ONE prepared range.
enum PreparedRanges {
    static func covers(_ ranges: [[Int]], first: Int, last: Int) -> Bool {
        last >= first && ranges.contains { $0.count == 2 && $0[0] <= first && last <= $0[1] }
    }
    static func load(cacheRoot: URL) -> [[Int]] {
        guard let p = try? Data(contentsOf: cacheRoot.appendingPathComponent("current-film.json")),
              let ptr = try? JSONSerialization.jsonObject(with: p) as? [String: Any], let path = ptr["progress_path"] as? String,
              let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let r = j["prepared"] as? [[Int]] else { return [] }
        return r
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif

/// 190t preflight: can this machine prepare and play 3D? Runtime check only, no install, no network, no brew, never touches playback.
/// Prepare writes its HEVC files in-app with VideoToolbox (VTShotEncoder), so no ffmpeg/libx265 is needed. Checks: (1) VideoToolbox lists an HEVC
/// encoder; (2) VideoToolbox can hardware-decode HEVC (AVFoundation reads the depth and source files with it); (3) the player lists an HEVC decoder
/// (`<player> --vd=help`, same probe as RenderedShotMPV) to play the render files. When one is missing the 3d mode entries show the plain reason and
/// stay disabled, so playback stays 2D. Probed once, off the main thread. Not compiled or run on a Mac.
final class ThreeDPreflight {
    static let shared = ThreeDPreflight()
    private let lock = NSLock()
    private var started = false
    private var result: String??                          // nil = not probed yet; .some(nil) = fine; .some(reason) = unavailable

    /// nil while unprobed or fine; otherwise the plain reason the 3d modes are off.
    var reason: String? { lock.lock(); defer { lock.unlock() }; if case .some(.some(let r)) = result { return r }; return nil }

    /// Pure decision from the three probe results.
    static func decide(vtEncodesHEVC: Bool, vtDecodesHEVC: Bool, decoders: [String]) -> String? {
        if !vtEncodesHEVC { return "3d needs the HEVC encoder in VideoToolbox (not available), staying 2d" }
        if !vtDecodesHEVC { return "3d needs HEVC decoding in VideoToolbox (not available), staying 2d" }
        if !decoders.contains("hevc") { return "3d needs an HEVC decoder in the player (none listed), staying 2d" }
        return nil
    }

    #if canImport(VideoToolbox)
    static func vtEncodesHEVC() -> Bool {
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr, let items = list as? [[String: Any]] else { return false }
        return items.contains { ($0[kVTVideoEncoderList_CodecType as String] as? UInt32) == kCMVideoCodecType_HEVC }
    }
    static func vtDecodesHEVC() -> Bool { VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) }
    #endif

    /// Idempotent. `mpvExecutable` is the same closure the coordinator uses; called on the probe thread.
    func start(mpvExecutable: @escaping () -> URL?) {
        lock.lock(); if started { lock.unlock(); return }; started = true; lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            #if canImport(VideoToolbox)
            let enc = Self.vtEncodesHEVC(), dec = Self.vtDecodesHEVC()
            #else
            let enc = false, dec = false
            #endif
            // The player process may not exist yet when this starts (wiring runs before the first launch): wait for it, up to 90 s, and never
            // report "no decoder" for a player that was not probed; an unprobed player leaves the modes enabled (reason stays nil).
            var exe = mpvExecutable(), waited = 0
            while exe == nil, waited < 90 { Thread.sleep(forTimeInterval: 1); waited += 1; exe = mpvExecutable() }
            guard let player = exe else { return }
            var pl = RenderedShotMPV.probeDecoders(executable: player)
            if pl.isEmpty { Thread.sleep(forTimeInterval: 2); pl = RenderedShotMPV.probeDecoders(executable: player) }   // one retry for a transient empty read
            let r = Self.decide(vtEncodesHEVC: enc, vtDecodesHEVC: dec, decoders: pl)
            lock.lock(); result = .some(r); lock.unlock()
        }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t A: the app-side seam that starts and stops the prepare step (tools/depth_analysis/prepare_driver.run_prepare) for the open film.
/// Only the RUNTIME is left open: `spawn` is injected (python + checkpoints, a bundled helper, ...). With no spawn the launcher says so once on the OSD
/// and the film stays 2D. It never touches playback. Progress comes from render-ready.json (CONTRACT-190v s8), read by `progress(entry:)`.
final class ThreeDPrepareLauncher {
    struct Request: Equatable { let film: URL; let fps: Double; let nFrames: Int; let startPTS: Double; let quality: String; var experiments = "" }   // 195h r3: the experiment-mode component; a flip restarts prepare
    struct Handle { let stop: () -> Void; var pause: () -> Void = {}; var resume: () -> Void = {} }
    enum Decision: Equatable { case none, stop, start(Request), report(String) }

    /// Pure rule. `running` = the film the current job prepares (nil = none), `failedFor` = a film whose last job exited with failure.
    static func decide(mode: String, film: URL?, playhead: Double?, info: (fps: Double, frames: Int)?, quality: String, experiments: String = "", preflightReason: String?,
                       running: URL?, failedFor: URL?, hasRuntime: Bool) -> Decision {
        let wanted = mode != "off" && preflightReason == nil && film != nil
        if let r = running { return (!wanted || film != r) ? .stop : .none }
        guard wanted, let f = film else { return .none }
        if failedFor == f { return .none }                            // no retry loop; a new film or a mode toggle clears it
        guard let i = info, i.fps > 0, i.frames > 0 else { return .none }
        guard hasRuntime else { return .report("3D: no prepare runtime on this build, staying 2D") }
        return .start(Request(film: f, fps: i.fps, nFrames: i.frames, startPTS: max(0, playhead ?? 0), quality: quality, experiments: experiments))
    }

    /// (ready, failed, total) shots from <entry>/render-ready.json; nil when absent or unreadable.
    static func progress(entry: URL) -> (ready: Int, failed: Int, total: Int)? {
        guard let d = try? Data(contentsOf: entry.appendingPathComponent("render-ready.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let n = o["n_shots"] as? Int, let r = o["n_ready"] as? Int else { return nil }
        return (r, (o["n_failed"] as? Int) ?? 0, n)
    }

    typealias Spawn = (Request, @escaping (Bool) -> Void) -> Handle?
    private let spawn: () -> Spawn?                         // late-bound: the runner may register after wiring
    private let report: (String) -> Void
    private var handle: Handle?, running: URL?, failedFor: URL?, lastMode = "off", told = Set<String>(), runningExperiments = "", lastExperiments = "", generation = 0
    private var pendingIdentity = "", settleAt = 0.0
    var settleDelay = ThreeDPrepareLauncher.settleSeconds
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    static let settleSeconds = 0.5 // same coalescing window as the render lane

    init(spawn: @escaping () -> Spawn?, report: @escaping (String) -> Void) { self.spawn = spawn; self.report = report }

    /// Call from a timer on the main thread with the current state. Idempotent.
    func cancelForMediaTransition() {
        generation += 1
        handle?.stop();handle=nil;running=nil;failedFor=nil
        pendingIdentity="";settleAt=0;pausedAt=nil
    }
    /// arch-196b C3: a cooperative pause parks the worker at a frame boundary holding no in-flight model call. Past this long
    /// parked, the worker is cancelled instead (cancelForMediaTransition path); turning 3D back on starts a fresh job, which
    /// resumes exactly from the persisted GORCK003 checkpoint.
    static let pauseCancelSeconds = 30.0
    private var pausedAt: Double? = nil
    func setPaused(_ paused:Bool) {
        if paused { if pausedAt == nil { pausedAt = clock() }; handle?.pause() }   // transition-only: repeated polls never reset the clock
        else { pausedAt = nil; handle?.resume() }
    }
    var isPreparing: Bool { running != nil }
    /// 195h r3-4 + Delivery block 1: the render lane found a prepared container in another experiment mode and reports the CURRENT mode
    /// (`experiments`). Stop a running job only when it runs in a DIFFERENT mode; a job already preparing the current mode (the rebuild
    /// itself) is never stopped, so the render lane may report on every 250 ms tick while the rebuild runs. With nothing running this is a
    /// no-op: the periodic update() starts the current-mode prepare, which rebuilds mismatched containers (never resumes them).
    func noteModeMismatch(current experiments: String) {
        if running != nil, runningExperiments != experiments { handle?.stop(); handle = nil; running = nil; generation += 1; pausedAt = nil }
    }
    func update(mode: String, film: URL?, playhead: Double?, info: (fps: Double, frames: Int)?, quality: String, experiments: String = "", preflightReason: String?) {
        let identity = (film?.absoluteString ?? "none") + "|" + experiments
        if identity != pendingIdentity { pendingIdentity=identity; settleAt=clock()+settleDelay }
        if experiments != lastExperiments { failedFor=nil; lastExperiments=experiments }
        if running != nil, experiments != runningExperiments { handle?.stop(); handle = nil; running = nil; generation += 1; pausedAt = nil }   // 195h r3-4: a prepare-mode flip stops the old-mode job; decide below starts the current-mode one
        if let t = pausedAt, clock() - t > Self.pauseCancelSeconds { cancelForMediaTransition() }   // C3: parked longer than 30 s -> cancel; the next start resumes from the checkpoint
        if let active=running,film==active,mode=="off" {setPaused(true);lastMode=mode;return}
        if mode != "off",lastMode=="off" {setPaused(false)}
        if mode != lastMode { failedFor = nil; lastMode = mode }
        // Stop stale work immediately, but start only the final settled choice.
        if mode != "off", clock() < settleAt { return }
        let sp = spawn()
        switch Self.decide(mode: mode, film: film, playhead: playhead, info: info, quality: quality, experiments: experiments, preflightReason: preflightReason,
                           running: running, failedFor: failedFor, hasRuntime: sp != nil) {
        case .none: break
        case .stop: handle?.stop(); handle = nil; running = nil; generation += 1; pausedAt = nil
        case .report(let t): if told.insert(t).inserted { report(t) }
        case .start(let req):
            generation += 1; let g = generation   // Delivery 4: the completion of a stopped/older job must never clear or fail the current one
            running = req.film; runningExperiments = req.experiments
            handle = sp?(req) { [weak self] ok in
                DispatchQueue.main.async { guard let self, g == self.generation else { return }; if !ok { self.failedFor = self.running; self.report(DepthCacheBudget.failure(root:DepthCachePaths.root)?.description ?? "3D depth preparation failed; staying on the last good image or 2D (see log)") }; self.running = nil; self.handle = nil }
            }
            if handle == nil { running = nil; failedFor = req.film; report("3D: could not start the prepare step, staying 2D") }
        }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 190t A: the in-app prepare path that replaces the Python driver on the Mac. E-G's native runner (CoreML depth, shot detection, alignment) implements
/// `ShotPrepareRunner`; it must call `ShotSink.boundary(checkpoint:cancelled:)` at every frame boundary and wrap each model request in `runModel` (s19); it calls `ShotSink` per shot, and the sink owns every file the renderer reads: source_shot_NNNNN.mp4 (VTShotEncoder), the depth
/// container (depth_shot_NNNNN.dzc, CONTRACT s16, E-G's DZCWriter; a depth file counts only once complete), the depth_shot_NNNNN.json sidecar, progress.json, render-ready.json (CONTRACT-190v s8) and current-film.json. The runner must
/// supply the cache entry directory and key itself: cache_key is Python-only today. Not compiled or run on a Mac.
protocol ShotPrepareRunner: AnyObject {
    /// Blocking. Call `cancelled()` between shots/frames; throw to fail (the launcher then does not retry this film in a loop).
    func prepare(_ request: ThreeDPrepareLauncher.Request, cancelled: @escaping () -> Bool) throws
}

enum ThreeDRunnerRegistry { static var runner: ShotPrepareRunner? }       // E-G sets this once its runner exists

enum ThreeDPrepareSpawn {
    private final class Flag {
        private let condition=NSCondition();private var cancelled=false,paused=false
        var set:Bool {
            get {condition.lock();defer {condition.unlock()};while paused && !cancelled {condition.wait()};return cancelled}
            set {condition.lock();cancelled=newValue;condition.broadcast();condition.unlock()}
        }
        func pause(_ value:Bool) {condition.lock();paused=value;condition.broadcast();condition.unlock()}
    }


    /// The `spawn` closure for ThreeDPrepareLauncher; nil while no runner is registered (the launcher then reports "no prepare runtime").
    static func make(runner: ShotPrepareRunner?) -> ((ThreeDPrepareLauncher.Request, @escaping (Bool) -> Void) -> ThreeDPrepareLauncher.Handle?)? {
        guard let runner else { return nil }
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate)
        if let native = runner as? NativePrepareRunner { return PrepareWorker.spawn(kit: native.kitDir, cache: native.cacheRoot, models: native.modelsDir) }
        #endif
        return { req, done in
            let cancel = Flag()
            DispatchQueue.global(qos: .utility).async {
                var ok = true
                do { try runner.prepare(req, cancelled: { cancel.set }) } catch { ok = false }
                done(ok && !cancel.set)
            }
            return ThreeDPrepareLauncher.Handle(stop: { cancel.set = true },pause:{cancel.pause(true)},resume:{cancel.pause(false)})
        }
    }
}

/// Whole-prepare subprocess: model state never enters the app; existing cache files are the IPC.
/// Worker alone owns writes/checkpoints under a cache-root flock. Parent only reads them.
enum PrepareWorker {
    static let flag = "--gor-prepare-worker"
    typealias Job = PrepareWorkerJob   // 195h Delivery: the worker boundary contract lives in PrepareWorkerJob.swift (pure Foundation, compiled by production AND the Linux test driver)
    final class Child {
        private let lock = NSLock()
        private var process: Process?, cancelled = false, pauseRequested = false
        /// arch-196b C3: the cooperative-pause flag path (job-file sibling), set by spawn before the job is written.
        var pauseFlag: String?
        func install(_ p: Process) -> Bool { lock.lock(); defer { lock.unlock() }; if cancelled { return false }; process = p; return true }
        func stop() {
            lock.lock(); cancelled = true; let p = process, flag = pauseFlag; lock.unlock()
            #if canImport(Darwin)
            if let p, p.isRunning { PrepareProcessLifetime.stopDescendants(of:p.processIdentifier); kill(-p.processIdentifier, SIGKILL); kill(p.processIdentifier, SIGKILL) }
            #endif
            if let flag { try? FileManager.default.removeItem(atPath: flag) }
        }
        /// arch-196b C3: cooperative pause, never a signal. The flag file is the whole IPC: the worker polls it at the per-frame
        /// boundary (ShotSink.boundary) and waits there with no in-flight model call; removing it resumes. Works before run() too,
        /// and a worker or model-load-probe child is never frozen mid-call (the Neural Engine stall this replaces).
        func paused(_ value:Bool) {
            lock.lock();pauseRequested=value;let flag=pauseFlag;lock.unlock()
            guard let flag else { return }
            if value { try? Data().write(to: URL(fileURLWithPath: flag), options: .atomic) } else { try? FileManager.default.removeItem(atPath: flag) }
        }
        func applyPendingPause() {lock.lock();let value=pauseRequested;lock.unlock();if value {paused(true)}}
        var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    static func spawn(kit: URL, cache: URL, models: URL?) -> ThreeDPrepareLauncher.Spawn {
        return { req, done in
            guard let exe = Bundle.main.executableURL else { return nil }
            let child = Child()
            DispatchQueue.global(qos: .utility).async {
                PrepareProcessLifetime.reapOrphanedHelpers(executable:exe)
                let fm = FileManager.default
                let jobURL = fm.temporaryDirectory.appendingPathComponent("gor-prepare-" + UUID().uuidString + ".json")
                let pauseURL = jobURL.appendingPathExtension("pause")
                child.pauseFlag = pauseURL.path
                defer { try? fm.removeItem(at: jobURL); try? fm.removeItem(at: pauseURL) }
                let job = Job(film: req.film.path, fps: req.fps, frames: req.nFrames, start: req.startPTS, quality: req.quality, kit: kit.path, cache: cache.path, models: models?.path, experiments: req.experiments, pauseFlag: pauseURL.path)   // 195h: the mode identity crosses the process boundary with the job; C3: so does the cooperative-pause flag path
                do {
                    try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
                    let p = Process(); p.executableURL = exe; p.arguments = [flag, jobURL.path, PrepareProcessLifetime.ownerFlag, String(ProcessInfo.processInfo.processIdentifier)]
                    p.standardInput = FileHandle.nullDevice
                    p.standardOutput = FileHandle.standardOutput; p.standardError = FileHandle.standardError
                    guard child.install(p), !child.stopped else { done(false); return }
                    try p.run()
                    #if canImport(Darwin)
                    _ = setpgid(p.processIdentifier, p.processIdentifier)
                    #endif
                    if child.stopped { child.stop() } else {child.applyPendingPause()}
                    let deadline = Date().addingTimeInterval(6 * 3600) // total worker ceiling, never an app wait
                    while p.isRunning && !child.stopped && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
                    if p.isRunning { child.stop() }
                    let reap = Date().addingTimeInterval(2)
                    while p.isRunning && Date() < reap { Thread.sleep(forTimeInterval: 0.01) }
                    let ok = !p.isRunning && !child.stopped && p.terminationReason == .exit && p.terminationStatus == 0
                    print("3d-prepare-worker end outcome=\(ok ? "complete" : "failed_or_cancelled")"); fflush(stdout)
                    done(ok)
                } catch { print("3d-prepare-worker spawn_error=\(error)"); fflush(stdout); done(false) }
            }
            return ThreeDPrepareLauncher.Handle(stop: { child.stop() },pause:{child.paused(true)},resume:{child.paused(false)})
        }
    }
    static func cli(arguments: [String]) -> Int32? {
        guard let at = arguments.firstIndex(of: flag) else { return nil }
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Darwin)
        _ = setpgid(0, 0) // own group; parent cancellation kills model-probe descendants too
        PrepareProcessLifetime.watchOwner(arguments: arguments)
        guard arguments.count == at + 2 || arguments.count == at + 4,
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[at + 1])),
              let job = try? JSONDecoder().decode(Job.self, from: data), job.fps > 0, job.frames > 0 else { return 64 }
        let root = URL(fileURLWithPath: job.cache, isDirectory: true)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { return 2 }
        let fd = open(root.appendingPathComponent(".prepare-worker.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { return 2 }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { print("3d-prepare-worker busy cache_owner_exists"); fflush(stdout); return 75 }
        defer { flock(fd, LOCK_UN) }
        ThreeDStageLog.enabled = true; ThreeDStageLog.start(); defer { ThreeDStageLog.stop() }
        let runner = NativePrepareRunner(kitDir: URL(fileURLWithPath: job.kit), cacheRoot: root)
        runner.modelsDir = job.models.map { URL(fileURLWithPath: $0) }
        if !job.pauseFlag.isEmpty { runner.pauseRequested = { FileManager.default.fileExists(atPath: job.pauseFlag) } }   // C3: cooperative pause, checked at every frame boundary
        do { try runner.prepare(job.request, cancelled: { false }); return DepthCacheBudget.failure(root:root) == nil ? 0 : 2 }
        catch { if let failure=error as? DepthCacheBudget.Failure {DepthCacheBudget.recordFailure(failure,root:root)}; print("3d-prepare-worker error=\(error)"); fflush(stdout); return 2 }
        #else
        return 4
        #endif
    }
}

/// Everything the runner needs to publish a shot. One per film. Not thread-safe: call from the runner's single prepare thread.
final class ShotSink {
    let entry: URL, fps: Double, shots: [[Int]]
    private var failures: [Int: String] = [:]
    /// CONTRACT s19: one model at a time (VDA stream and MoGe keyframes never overlap) and the thermal duty cycle.
    let thermal = ThreeDThermalGate()
    private static let modelLane = NSLock()

    init?(entry: URL, shots: [[Int]], fps: Double) {
        guard fps > 0, !shots.isEmpty, (try? FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)) != nil else { return nil }
        self.entry = entry; self.fps = fps; self.shots = shots
        writeReady()
    }

    /// Runs one model request (a VDA frame or a MoGe keyframe) on the single model lane: never two at once.
    func runModel<T>(_ body: () throws -> T) rethrows -> T { Self.modelLane.lock(); defer { Self.modelLane.unlock() }; return try body() }

    /// arch-196b C3: the cooperative-pause flag, set by the prepare worker's runner. Checked at every frame boundary; default = never paused.
    var pauseRequested: () -> Bool = { false }

    /// Call at EVERY frame boundary (and before each shot) from the prepare thread. Blocks while the machine is hot (thermalState >= .serious): `checkpoint` runs once
    /// on the way in (VDA WindowState + the .dzc resume prefix) and progress.json carries "paused": "thermal" meanwhile. false = cancelled, stop the film.
    /// arch-196b C3: while the cooperative-pause flag is set the worker waits HERE, at the boundary with no in-flight model call
    /// (the app never SIGSTOPs it). `checkpoint` runs once on the way in, so the persisted GORCK003 state is current if the
    /// 30 s pause limit cancels the worker: the next job resumes exactly. progress.json carries "paused": "pause" meanwhile.
    func boundary(checkpoint: () -> Void, cancelled: () -> Bool) -> Bool {
        if pauseRequested() {
            checkpoint()
            setUserPaused(true)
            while pauseRequested() {
                if cancelled() { setUserPaused(false); return false }
                Thread.sleep(forTimeInterval: 0.2)
            }
            setUserPaused(false)
        }
        return thermal.boundary(checkpoint: checkpoint, paused: { [self] p in setPaused(p) }, cancelled: cancelled)
    }

    private func setUserPaused(_ p: Bool) {
        let pj = entry.appendingPathComponent("progress.json")
        var d = ((try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        if p { d["paused"] = "pause" } else { d.removeValue(forKey: "paused") }
        ThreeDStageLog.progress(p ? "prepare-pause" : "prepare-resumed", done: 0, total: 1)
        Self.writeAtomic(d, to: pj)
    }

    private func setPaused(_ p: Bool) {
        let pj = entry.appendingPathComponent("progress.json")
        var d = ((try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        if p { d["paused"] = "thermal" } else { d.removeValue(forKey: "paused") }
        ThreeDStageLog.progress(p ? "thermal-pause" : "thermal-resumed", done: ProcessInfo.processInfo.thermalState.rawValue, total: 3)
        Self.writeAtomic(d, to: pj)
    }

    static func depthURL(_ e: URL, _ i: Int) -> URL { e.appendingPathComponent(String(format: "depth_shot_%05d.dzc", i)) }
    static func sourceURL(_ e: URL, _ i: Int) -> URL { e.appendingPathComponent(String(format: "source_shot_%05d.mp4", i)) }
    static func sidecarURL(_ e: URL, _ i: Int) -> URL { e.appendingPathComponent(String(format: "depth_shot_%05d.json", i)) }

    static func writeAtomic(_ obj: Any, to url: URL) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-" + url.lastPathComponent)
        do { try d.write(to: tmp); _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp) } catch { try? FileManager.default.removeItem(at: tmp) }
    }

    /// Pure: the render-ready.json document (CONTRACT s8) from which files exist and which shots failed.
    static func readyDocument(shots: [[Int]], existing: Set<String>, failures: [Int: String], now: Double) -> [String: Any] {
        var rows: [[String: Any]] = []
        for (i, r) in shots.enumerated() {
            let d = existing.contains(String(format: "depth_shot_%05d.dzc", i)), s = existing.contains(String(format: "source_shot_%05d.mp4", i)), ready = d && s
            let err = failures[i]; let errV: Any = (ready ? nil : err) ?? NSNull()
            rows.append(["shot": i, "start": r[0], "end": r[1], "depth_ready": d, "source_ready": s, "ready": ready,
                         "failed": err != nil && !ready, "error": errV])
        }
        return ["shots": rows, "n_shots": shots.count, "n_ready": rows.filter { $0["ready"] as? Bool == true }.count,
                "n_failed": rows.filter { $0["failed"] as? Bool == true }.count, "updated_at": now]
    }
    /// Pure: merge a [first,last] frame range into progress.json's "prepared" list (sorted, adjacent/overlapping ranges joined).
    static func merge(_ ranges: [[Int]], adding r: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        for x in (ranges + [r]).sorted(by: { $0[0] < $1[0] }) {
            if let l = out.last, x[0] <= l[1] + 1 { out[out.count - 1][1] = max(l[1], x[1]) } else { out.append(x) }
        }
        return out
    }

    private func writeReady() {
        let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: entry.path)) ?? []).filter { !$0.hasSuffix(".dzc") || DZCFile.isComplete(entry.appendingPathComponent($0)) })   // a half-written container is not ready
        Self.writeAtomic(Self.readyDocument(shots: shots, existing: names, failures: failures, now: Date().timeIntervalSince1970), to: entry.appendingPathComponent("render-ready.json"))
    }

    /// Points <cache_root>/current-film.json at this film (the key comes from the runner).
    func writeCurrentFilm(root: URL = DepthCachePaths.root, key: String, nFrames: Int) {
        Self.writeAtomic(["progress_path": entry.appendingPathComponent("progress.json").path, "n_frames": nFrames, "cache_key": key], to: root.appendingPathComponent("current-film.json"))
    }

    #if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VideoToolbox)
    /// Opens the source-proxy encoder for shot `i` (frames shots[i][0]...shots[i][1]). The depth container is written by the runner with E-G's writer.
    func beginSource(shot i: Int, sourceSize: (w: Int, h: Int), sourceFullRange: Bool = false, sourceColor: [String: String]? = nil) -> VTShotEncoder? {
        guard shots.indices.contains(i),
              let s = VTShotEncoder(url: Self.sourceURL(entry, i), width: sourceSize.w, height: sourceSize.h, fps: fps, startFrame: shots[i][0],
                                    sourceFullRange: sourceFullRange, colorProperties: sourceColor) else { fail(shot: i, "could not open the HEVC encoder"); return nil }
        return s
    }

    /// Finishes the proxy, writes the sidecar (sizes + the runner's `extra`, e.g. align_scale) and publishes the shot. The runner must have written the
    /// depth file BEFORE this call (a shot is ready only when depth AND source exist).
    @discardableResult
    func finishSource(shot i: Int, _ enc: VTShotEncoder, depthSize: (w: Int, h: Int), extra: [String: Any] = [:]) -> Bool {
        if let why = enc.finish() { fail(shot: i, why); return false }
        var side = extra
        side["start"] = shots[i][0]; side["end"] = shots[i][1]
        side["depth_width"] = depthSize.w; side["depth_height"] = depthSize.h
        side["source_width"] = enc.width; side["source_height"] = enc.height
        Self.writeAtomic(side, to: Self.sidecarURL(entry, i))      // before ready: a ready shot always has its sidecar
        failures.removeValue(forKey: i)
        let pj = entry.appendingPathComponent("progress.json")
        let cur = ((try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["prepared"] as? [[Int]]) ?? []
        var pd = (try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        pd["prepared"] = Self.merge(cur, adding: [shots[i][0], shots[i][1]]); Self.writeAtomic(pd, to: pj)
        writeReady(); return true
    }
    #endif

    /// Records a failed shot (its source proxy and depth file are removed so the shot is never half-ready); the runner may retry it later.
    func fail(shot i: Int, _ error: String) {
        failures[i] = error
        try? FileManager.default.removeItem(at: Self.depthURL(entry, i)); try? FileManager.default.removeItem(at: Self.sourceURL(entry, i))
        writeReady()
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t/190v native prepare, per-shot assembly (contract s13/s16/s19). Pure Foundation: runs and is tested on Linux with fake model backends; the real CoreML
/// backend adapter is at the bottom (parse-checked only, UNVERIFIED on a Mac).
///
/// Flow per shot (mirrors prepare_film._analyze_shot): phase 1 walks the frames in order, ONE MODEL AT A TIME (VDA-S stream step, then, on every FOV_KEYFRAME_STRIDE-th
/// frame, the MoGe-2 keyframe; never concurrent: s19 rule 1). The raw relative depth of every frame is spooled to disk, the keyframe fov and the (VDA, MoGe)
/// alignment sample pairs are kept. Phase 2 fits the per-shot scale/shift (ShotAlignerSwift, EMA over the keyframes in order), converts the spool to metres and
/// writes the lossless .dzc. The alignment is shot-global (as in Python), so the container cannot be written before phase 1 ends: the spool is what makes phase 1
/// resumable. After every frame the thermal hook may suspend the shot with a serialisable checkpoint (s19 rules 2-4); resuming recomputes nothing.

/// ProcessInfo.ThermalState without the platform dependency in the policy code.
enum ThermalLevel: Int, Comparable { case nominal = 0, fair, serious, critical
    static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
    #if canImport(Darwin)
    static func current() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }
    #endif
}

/// s19 duty cycle: suspend when state >= .fair; resume only after the minimum suspend (60 s) AND state < .fair held for the 30 s dwell. Time is injected.
struct ThermalDutyGate {
    static let minSuspend = 60.0, dwell = 30.0
    private(set) var suspendedAt: Double? = nil, coolSince: Double? = nil
    var isSuspended: Bool { suspendedAt != nil }
    /// Call at every frame boundary (running) or on the delivery lane's resume poll (suspended). true = may run.
    mutating func mayRun(level: ThermalLevel, now: Double) -> Bool {
        if let at = suspendedAt {
            if level >= .fair { coolSince = nil; return false }
            if coolSince == nil { coolSince = now }
            if now - at >= Self.minSuspend, now - coolSince! >= Self.dwell { suspendedAt = nil; coolSince = nil; return true }
            return false
        }
        if level >= .fair { suspendedAt = now; coolSince = nil; return false }
        return true
    }
}

protocol ShotPrepareBackend: AnyObject {
    /// Next VDA-S stream step for `frame` (frames are requested strictly in order from the checkpoint's nextFrame). Relative depth [depthH * depthW].
    func vdaStep(frame: Int) -> [Float]?
    /// The VDA sliding window, for checkpoint/restore.
    var window: VDAWindowState { get set }
    /// MoGe-2 keyframe at `frame` (fp32 fallback inside), or nil when no plausible result.
    func mogeKeyframe(frame: Int) -> MoGeKeyframe?
    /// s35: mean-RGB luma (depth resolution, depthW * depthH) of the frame the LAST vdaStep consumed; nil = no guards (the default, and every test fake).
    func guardLuma() -> [Float]?
}
extension ShotPrepareBackend { func guardLuma() -> [Float]? { nil } }

struct ShotCheckpoint: Equatable {
    var shot: Int, nextFrame: Int, nFrames: Int
    var window: [[[Float]]] = []; var windowID = -1
    var pairsVDA: [[Float]] = [], pairsMoGe: [[Float]] = []
    var fovFrames: [Int] = [], fovValues: [Double] = []
    var pairFrames: [Int] = []          // s30: shot-relative frame of each alignment pair (keyframes whose MoGe step succeeded), for the align track
    var keyframesTried = 0
    var pairWeights: [[Float]] = []     // s35 (GORCK003): per pair, texture weights on the same subsampled grid as pairsVDA ([] = none)
    var pairSky: [[UInt32]] = []        // s35 (GORCK003): per pair, packed sky-candidate bits at depth resolution ([] = no sky guard for that keyframe)

    // Binary (little-endian) so a 32-bundle window (~33 MB) is not text-expanded.
    func encode() -> Data {
        var d = Data("GORCK003".utf8)
        func i(_ v: Int) { var x = Int64(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func f(_ a: [Float]) { i(a.count); a.withUnsafeBufferPointer { p in for v in p { var b = v.bitPattern.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } } } }
        func dbl(_ v: Double) { var b = v.bitPattern.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
        i(shot); i(nextFrame); i(nFrames); i(windowID); i(keyframesTried)
        i(window.count); for b in window { i(b.count); for a in b { f(a) } }
        i(pairsVDA.count); for a in pairsVDA { f(a) }; i(pairsMoGe.count); for a in pairsMoGe { f(a) }
        i(fovFrames.count); for v in fovFrames { i(v) }; i(fovValues.count); for v in fovValues { dbl(v) }
        i(pairFrames.count); for v in pairFrames { i(v) }
        i(pairWeights.count); for a in pairWeights { f(a) }
        i(pairSky.count); for a in pairSky { i(a.count); for v in a { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } } }
        return d
    }
    static func decode(_ data: Data) -> ShotCheckpoint? {
        let b = [UInt8](data); var o = 0
        let magic = b.count >= 8 ? Array(b[0..<8]) : []
        guard magic == Array("GORCK003".utf8) || magic == Array("GORCK002".utf8) || magic == Array("GORCK001".utf8) else { return nil }
        let v3 = magic == Array("GORCK003".utf8), v2 = v3 || magic == Array("GORCK002".utf8)          // 001 (pre-s30) has no pairFrames: derived below as index * keyframe stride
        o = 8; var bad = false
        func raw(_ n: Int) -> UInt64 { guard !bad, o + n <= b.count else { bad = true; return 0 }; var v: UInt64 = 0; for k in 0..<n { v |= UInt64(b[o + k]) << (8 * UInt64(k)) }; o += n; return v }
        func i() -> Int { Int(Int64(bitPattern: raw(8))) }
        func cnt() -> Int { let n = i(); if n < 0 || n > b.count { bad = true; return 0 }; return n }
        func f() -> [Float] { let n = cnt(); var a = [Float](); a.reserveCapacity(n); for _ in 0..<n { a.append(Float(bitPattern: UInt32(raw(4)))) }; return a }
        var c = ShotCheckpoint(shot: i(), nextFrame: i(), nFrames: i())
        c.windowID = i(); c.keyframesTried = i()
        for _ in 0..<cnt() { var bundle: [[Float]] = []; for _ in 0..<cnt() { bundle.append(f()) }; c.window.append(bundle) }
        for _ in 0..<cnt() { c.pairsVDA.append(f()) }; for _ in 0..<cnt() { c.pairsMoGe.append(f()) }
        for _ in 0..<cnt() { c.fovFrames.append(i()) }; for _ in 0..<cnt() { c.fovValues.append(Double(bitPattern: raw(8))) }
        if v2 { for _ in 0..<cnt() { c.pairFrames.append(i()) } } else { c.pairFrames = (0..<c.pairsVDA.count).map { $0 * FovTrackBuilder.keyframeStride } }
        if v3 {
            for _ in 0..<cnt() { c.pairWeights.append(f()) }
            for _ in 0..<cnt() { var a: [UInt32] = []; for _ in 0..<cnt() { a.append(UInt32(truncatingIfNeeded: raw(4))) }; c.pairSky.append(a) }
        }
        return bad ? nil : c
    }
}

struct ShotPrepareJob {
    var shot: Int, startFrame: Int, frames: Int, fps: Double
    var depthW = VDAStream.exportW, depthH = VDAStream.exportH
    var dzc: URL, spool: URL
    var codec: DZCWriter.Codec = DZCWriter.lzfse
    /// 195h B/r3: the frozen experiment snapshot for this job (default all-off = pre-195h bytes). The menu toggle can only change the NEXT job.
    var experiments = ThreeDExperimentOptions()
    var alignSubsample = 8
    /// Where the boundary checkpoint is persisted (atomic replace); nil = in-memory suspension only. A process restart resumes from it with `runResumable`.
    var checkpointURL: URL? = nil
}

struct ShotPrepareResult { var dzc: URL; var fov: FovTrackBuilder.Entry; var alignScale: Double?; var alignShift: Double?; var alignSkipped: Int; var keyframesUsed: Int; var alignTrack: [[Double]] = [] }   // s30: [[k, scale, shift]]
enum ShotPrepareOutcome { case done(ShotPrepareResult), suspended(ShotCheckpoint), cancelled, failed(String) }

/// The delivery lane's ShotSink contract (ThreeDPrepareSpawn.swift): `boundary` is called before the shot and at EVERY frame boundary; it may block while the machine is hot,
/// running `checkpoint` once on the way in, and returns false when cancelled. `lane` wraps every model request (ShotSink.runModel: one model at a time).
struct ShotPrepareHooks {
    var boundary: (_ checkpoint: () -> Void) -> Bool = { _ in true }
    var lane: (() -> Void) -> Void = { $0() }
    var shouldSuspend: (Int) -> Bool = { _ in false }       // return-style suspension (tests, schedulers that re-enter)
    var stage: (String, Double) -> Void = { _, _ in }       // (stage name, milliseconds): self-test telemetry
    var progress: (String, Int, Int) -> Void = { _, _, _ in }
    var depthMetres: ([Float]) -> Void = { _ in }           // each aligned metric frame, before it is quantised (self-test depth stats)
}

enum ShotPrepare {
    /// MoGe metric depth (mw x mh, +inf at masked pixels) sampled on the VDA grid's every `step`-th pixel: bilinear at the pixel centre, NaN when any of the four
    /// neighbours is not finite (an inf must not enter the fit). Same indices as align.update(depth_rel[::8, ::8], md[::8, ::8]).
    static func sampleSub(_ src: [Float], mw: Int, mh: Int, dw: Int, dh: Int, step: Int) -> [Float] {
        var out: [Float] = []
        for y in stride(from: 0, to: dh, by: step) { for x in stride(from: 0, to: dw, by: step) {
            let fx = min(max((Double(x) + 0.5) / Double(dw) * Double(mw) - 0.5, 0), Double(mw - 1)), fy = min(max((Double(y) + 0.5) / Double(dh) * Double(mh) - 0.5, 0), Double(mh - 1))
            let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, mw - 1), y1 = min(y0 + 1, mh - 1), tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
            let a = src[y0 * mw + x0], b = src[y0 * mw + x1], c = src[y1 * mw + x0], d = src[y1 * mw + x1]
            guard a.isFinite, b.isFinite, c.isFinite, d.isFinite else { out.append(.nan); continue }
            out.append((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)
        } }
        return out
    }
    static func subsample(_ v: [Float], w: Int, h: Int, step: Int) -> [Float] {
        var out: [Float] = []; for y in stride(from: 0, to: h, by: step) { for x in stride(from: 0, to: w, by: step) { out.append(v[y * w + x]) } }; return out
    }
    static func rawBytes(_ a: [Float]) -> Data { a.withUnsafeBufferPointer { Data(buffer: $0) } }

    /// Runs (or resumes from `checkpoint`) one shot. `shouldSuspend(frame)` is called after each finished phase-1 frame (the thermal hook: typically
    /// `!gate.mayRun(level: ThermalLevel.current(), now: ...)`); true returns .suspended with the checkpoint to pass back later. Phase 2 (CPU + LZFSE) is not suspended.
    /// Resumes from job.checkpointURL when one is present and matches the job, otherwise starts the shot.
    static func runResumable(job: ShotPrepareJob, backend: ShotPrepareBackend, hooks: ShotPrepareHooks = ShotPrepareHooks()) -> ShotPrepareOutcome {
        // 195h A (Delivery A-3, fixed at the right point): the mode fence runs BEFORE any checkpoint or spool is read. A container written
        // in another mode makes every per-shot artifact of that mode stale; deleting them after phase 1 would be too late (an open fd keeps
        // reading the unlinked spool). Wipe container + mode marker + EMA state + spool + checkpoint here, then decide resume from scratch.
        let fm = FileManager.default
        if PrepareSupport.containerAction(dzc: job.dzc, options: job.experiments) == .rebuild {
            var stale = [job.dzc, job.dzc.appendingPathExtension("options.json"), job.dzc.appendingPathExtension("ema.json"), job.spool,
                         PrepareSupport.spoolIdentityURL(spool: job.spool), PrepareSupport.alignURL(spool: job.spool)]
            if let cku = job.checkpointURL { stale.append(cku) }
            for u in stale where fm.fileExists(atPath: u.path) {
                do { try fm.removeItem(at: u) } catch { return .failed("cannot remove \(u.lastPathComponent) for rebuild") }   // abort; never proceed on a partial wipe
            }
        } else if !fm.fileExists(atPath: job.dzc.path), PrepareSupport.spoolAction(spool: job.spool, checkpoint: job.checkpointURL, options: job.experiments) == .rebuild {
            // 195h A (Delivery A-4): phase 1 was interrupted before the container existed, so the container fence above saw nothing. The
            // spool/checkpoint on disk carry the identity marker written before THEIR phase 1; a mismatch never resumes across modes.
            var stale = [job.spool, PrepareSupport.spoolIdentityURL(spool: job.spool), PrepareSupport.alignURL(spool: job.spool)]
            if let cku = job.checkpointURL { stale.append(cku) }
            for u in stale where fm.fileExists(atPath: u.path) {
                do { try fm.removeItem(at: u) } catch { return .failed("cannot remove \(u.lastPathComponent) for rebuild") }
            }
        }
        // Record THIS job's identity before phase 1 writes a byte, so an interrupted run is recognized by the next job in any mode.
        guard PrepareSupport.writeJSON(PrepareSupport.prepareIdentity(job.experiments), to: PrepareSupport.spoolIdentityURL(spool: job.spool)) else { return .failed("cannot write the prepare identity marker") }
        var ck: ShotCheckpoint? = nil
        if let u = job.checkpointURL, let d = try? Data(contentsOf: u), let c = ShotCheckpoint.decode(d), c.shot == job.shot, c.nFrames == job.frames { ck = c }
        return run(job: job, backend: backend, checkpoint: ck, hooks: hooks)
    }
    private static func persist(_ ck: ShotCheckpoint, job: ShotPrepareJob, backend: ShotPrepareBackend, spool: FileHandle?) {
        guard let u = job.checkpointURL else { return }
        var c = ck; c.windowID = backend.window.id; c.window = backend.window.list
        try? spool?.synchronize()                               // the spool prefix is part of the checkpoint
        let tmp = u.deletingLastPathComponent().appendingPathComponent(".tmp-" + u.lastPathComponent)
        guard (try? c.encode().write(to: tmp)) != nil else { return }
        try? FileManager.default.removeItem(at: u); try? FileManager.default.moveItem(at: tmp, to: u)      // rename; a crash between the two leaves .tmp-, never a torn file
    }

    static func run(job: ShotPrepareJob, backend: ShotPrepareBackend, checkpoint: ShotCheckpoint? = nil, hooks: ShotPrepareHooks = ShotPrepareHooks()) -> ShotPrepareOutcome {
        let fm = FileManager.default, n = job.frames, plane = job.depthW * job.depthH, frameBytes = plane * 4
        var ck = checkpoint ?? ShotCheckpoint(shot: job.shot, nextFrame: 0, nFrames: n)
        guard ck.shot == job.shot, ck.nFrames == n, ck.nextFrame >= 0, ck.nextFrame <= n else { return .failed("checkpoint does not match the job") }
        if checkpoint != nil { var w = backend.window; w.restore(id: ck.windowID, list: ck.window); backend.window = w }
        // spool: keep exactly the finished frames (a crash may have left a partial or extra frame)
        if checkpoint == nil || !fm.fileExists(atPath: job.spool.path) {
            if checkpoint != nil && ck.nextFrame > 0 { return .failed("spool missing for checkpoint") }
            guard fm.createFile(atPath: job.spool.path, contents: nil) else { return .failed("cannot create spool") }
        }
        guard let h = try? FileHandle(forUpdating: job.spool) else { return .failed("cannot open spool") }
        defer { try? h.close() }
        do {
            let size = try h.seekToEnd(); guard size >= UInt64(ck.nextFrame * frameBytes) else { return .failed("spool shorter than checkpoint") }
            try h.truncate(atOffset: UInt64(ck.nextFrame * frameBytes)); try h.seekToEnd()
        } catch { return .failed("spool I/O") }

        let stride_ = FovTrackBuilder.keyframeStride
        var overlay: DepthGuards.OverlayAccumulator? = nil          // s35: not checkpointed (a resumed shot accumulates from its resume point; needs >= 24 frames to act)
        hooks.progress("depth-boundary", ck.nextFrame, n)
        if !hooks.boundary({ persist(ck, job: job, backend: backend, spool: h) }) { return .cancelled }          // before the shot
        while ck.nextFrame < n {
            let k = ck.nextFrame
            hooks.progress("depth-frames", k, n)
            var vdaOut: [Float]? = nil; let tV = DispatchTime.now(); hooks.lane { vdaOut = backend.vdaStep(frame: k) }; hooks.stage("vda_step_total", Double(DispatchTime.now().uptimeNanoseconds - tV.uptimeNanoseconds) / 1e6)
            hooks.progress("depth-frames", k + 1, n)
            guard let d = vdaOut, d.count == plane else { return .failed("VDA step failed at frame \(k)") }
            do { try h.write(contentsOf: rawBytes(d)) } catch { return .failed("spool write at frame \(k)") }
            let lum: [Float]? = { guard let l = backend.guardLuma(), l.count == plane else { return nil }; return l }()
            if let l = lum, DepthGuards.overlayFlatten { if overlay == nil { overlay = DepthGuards.OverlayAccumulator(w: job.depthW, h: job.depthH) }; overlay!.add(luma: l) }
            if k % stride_ == 0 {                                  // serial: the VDA step above has returned before MoGe starts
                hooks.progress("moge-keyframes", k / stride_, (n + stride_ - 1) / stride_)
                ck.keyframesTried += 1
                var kfOut: MoGeKeyframe? = nil; let tM = DispatchTime.now(); hooks.lane { kfOut = backend.mogeKeyframe(frame: k) }; hooks.stage("moge_step_total", Double(DispatchTime.now().uptimeNanoseconds - tM.uptimeNanoseconds) / 1e6)
                hooks.progress("moge-keyframes", k / stride_ + 1, (n + stride_ - 1) / stride_)
                if let kf = kfOut {
                    if kf.hfovDeg.isFinite { ck.fovFrames.append(k); ck.fovValues.append(kf.hfovDeg) }
                    ck.pairFrames.append(k); ck.pairsVDA.append(subsample(d, w: job.depthW, h: job.depthH, step: job.alignSubsample))
                    ck.pairsMoGe.append(sampleSub(kf.depth, mw: kf.width, mh: kf.height, dw: job.depthW, dh: job.depthH, step: job.alignSubsample))
                    var wts: [Float] = [], sky: [UInt32] = []                // s35: texture weights for the fit; MoGe-invalid + flat top-region candidates for the sky clamp
                    if let l = lum {
                        if DepthGuards.weightedFit { wts = subsample(DepthGuards.textureWeights(luma: l, w: job.depthW, h: job.depthH), w: job.depthW, h: job.depthH, step: job.alignSubsample) }
                        if DepthGuards.skyClamp {
                            let fin = DepthGuards.finiteMask(kf.depth, mw: kf.width, mh: kf.height, dw: job.depthW, dh: job.depthH)
                            if fin.contains(false) { let m = DepthGuards.skyMaskMoGe(luma: l, finite: fin, w: job.depthW, h: job.depthH); if m.reduce(0, { $0 + ($1 ? 1 : 0) }) >= 64 { sky = DepthGuards.pack(m) } }
                        }
                    }
                    ck.pairWeights.append(wts); ck.pairSky.append(sky)
                }
            }
            ck.nextFrame = k + 1
            if ck.nextFrame < n {
                if !hooks.boundary({ persist(ck, job: job, backend: backend, spool: h) }) { return .cancelled }        // every frame boundary
                if hooks.shouldSuspend(k) { ck.windowID = backend.window.id; ck.window = backend.window.list; return .suspended(ck) }
            }
        }
        try? h.synchronize()
        // (the spool + container prefix below are recoverable; the phase-1 checkpoint stays valid until the shot is finished)
        if let u = job.checkpointURL { var c = ck; c.windowID = backend.window.id; c.window = backend.window.list; try? c.encode().write(to: u) }

        // phase 2: shot-global alignment, metres, lossless container (resumable through the DZC prefix)
        let al = ShotAlignerSwift(ema: 0.9); let tA = DispatchTime.now()
        var trackRaw: [(k: Int, scale: Double?, shift: Double?)] = []
        let overlayMask: [Bool]? = DepthGuards.overlayFlatten ? overlay?.mask(minFrames: 24) : nil
        var fitMask: [Bool]? = nil          // s35: overlay pixels do not enter the fit (same grid as the pairs)
        if let om = overlayMask { var s: [Bool] = []; for y in Swift.stride(from: 0, to: job.depthH, by: job.alignSubsample) { for x in Swift.stride(from: 0, to: job.depthW, by: job.alignSubsample) { s.append(!om[y * job.depthW + x]) } }; fitMask = s }
        for (idx, (v, m)) in zip(ck.pairsVDA, ck.pairsMoGe).enumerated() {
            let wt: [Float]? = idx < ck.pairWeights.count && ck.pairWeights[idx].count == v.count ? ck.pairWeights[idx] : nil
            al.update(vda: v, moge: m, mask: fitMask, weights: wt)
            trackRaw.append((idx < ck.pairFrames.count ? ck.pairFrames[idx] : idx * stride_, al.scale, al.shift))
        }
        // s30: eased per-keyframe application (nil entries -> the shot's final EMA, as prepare_film passes default=(scale, shift))
        let track = AlignTrack(keyframes: trackRaw, defaultScale: al.scale ?? 1.0, defaultShift: al.shift ?? 0.0)
        hooks.stage("align_fit", Double(DispatchTime.now().uptimeNanoseconds - tA.uptimeNanoseconds) / 1e6)
        // s35 sky clamp: the nearest keyframe's MoGe-invalid candidates (first keyframe on a tie, like min() over the sorted keyframes in the probe harness)
        func nearestPair(_ f: Int) -> Int? { var best: Int? = nil, bd = Int.max; for (i, k) in ck.pairFrames.enumerated() where abs(k - f) < bd { bd = abs(k - f); best = i }; return best }
        func skyClamped(_ z: [Float], frame f: Int) -> [Float] {
            guard DepthGuards.skyClamp, let i = nearestPair(f), i < ck.pairSky.count, !ck.pairSky[i].isEmpty else { return z }
            return DepthGuards.clampSkyMetres(z: z, mask: DepthGuards.unpack(ck.pairSky[i], count: plane))
        }
        func aligned(_ raw: [Float], _ fi: Int) -> [Float] { track.entries.isEmpty ? al.apply(raw) : track.apply(raw, frame: fi, defaultScale: al.scale ?? 1.0, defaultShift: al.shift ?? 0.0) }
        var zScreen: Float? = nil
        if overlayMask != nil {                  // convergence plane of this shot: median metres over every keyframe-stride-th frame (the render lane re-derives its own from the container)
            var sample: [[Float]] = []
            do { for fi in Swift.stride(from: 0, to: n, by: stride_) { try h.seek(toOffset: UInt64(fi * frameBytes)); guard let data = try h.read(upToCount: frameBytes), data.count == frameBytes else { break }
                sample.append(skyClamped(aligned(data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, fi), frame: fi)) } } catch {}
            if let zc = ShotComfort.median(sample) { zScreen = Float(zc) }
        }
        let q = DZC.quantise(z: [Float](repeating: 1, count: plane), h: job.depthH, w: job.depthW)
        let meta = DZC.Meta(shot: UInt32(job.shot), fpsNum: DZC.fpsPair(job.fps).0, fpsDen: DZC.fpsPair(job.fps).1, startFrame: UInt64(job.startFrame),
                            width: UInt32(q.width), height: UInt32(q.height), depthWidth: UInt32(job.depthW), depthHeight: UInt32(job.depthH), nFrames: UInt32(n))
        // 195h r3-2: the container action is decided BEFORE the writer opens, from the per-container mode marker. A mismatched existing
        // container is never resumed: it is removed and rebuilt in this job's mode, and only then marked.
        let expOptions = job.experiments
        var rangeEMA = DepthTemporalEMA.State(active: expOptions.depthRangeEMA)   // 195h B: one state per prepare job = the shot-boundary reset
        let modeMarker = job.dzc.appendingPathExtension("options.json"), emaStateURL = job.dzc.appendingPathExtension("ema.json")
        if PrepareSupport.containerAction(dzc: job.dzc, options: expOptions) == .rebuild {
            do { try fm.removeItem(at: job.dzc) } catch { return .failed("cannot remove the mismatched container for rebuild") }   // Delivery 6: abort; never proceed or mark when the removal failed
            if fm.fileExists(atPath: emaStateURL.path) { do { try fm.removeItem(at: emaStateURL) } catch { return .failed("cannot remove the stale EMA state for rebuild") } }
        }
        guard let w = DZCWriter(url: job.dzc, meta: meta, resume: true, codec: job.codec) else { return .failed("cannot open container") }
        _ = PrepareSupport.writeJSON(PrepareSupport.prepareIdentity(expOptions), to: modeMarker)   // marked only once the writer's container is this job's mode (195h A: model + smoother)
        var prevOut: [Float]? = nil          // F2b: previous output frame of this shot (recursive smoothing); a resumed shot primes it from the previous spooled frame (approximate, no seam beyond the EMA tail)
        do {
            try h.seek(toOffset: UInt64(w.framesWritten * frameBytes))
            if w.framesWritten > 0, TemporalDepth.enabled || rangeEMA.active {
                let savedEMA: DepthTemporalEMA.State? = {   // 195h r3-3: an exact restore requires the container's frame count and restores primed as persisted
                    guard rangeEMA.active, let st = PrepareSupport.readJSON(emaStateURL), let lo = st["lo"] as? Double, let hi = st["hi"] as? Double,
                          let pr = st["primed"] as? Bool, (st["frames"] as? Int) == w.framesWritten else { return nil }
                    return DepthTemporalEMA.State(active: true, lo: Float(lo), hi: Float(hi), primed: pr)
                }()
                if rangeEMA.active, savedEMA == nil {
                    // 195h r3-3 + Delivery 7: no valid persisted state (a crash between append and persist, or a lost file) -> EXACT replay of the
                    // deterministic prefix from the spool (align + sky clamp + F2b smoothing + EMA, frame by frame), never an approximate re-prime.
                    for rfi in 0..<w.framesWritten {
                        try h.seek(toOffset: UInt64(rfi * frameBytes))
                        guard let rd = try h.read(upToCount: frameBytes), rd.count == frameBytes else { return .failed("spool short in the EMA replay") }
                        let rr: [Float] = rd.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                        var rm = skyClamped(aligned(rr, rfi), frame: rfi)
                        if let rp = prevOut { rm = TemporalDepth.smooth(prev: rp, cur: rm) }; prevOut = rm
                        _ = rangeEMA.apply(rm)
                    }
                } else {
                    try h.seek(toOffset: UInt64((w.framesWritten - 1) * frameBytes))
                    if let pd = try h.read(upToCount: frameBytes), pd.count == frameBytes {
                        let pf = skyClamped(aligned(pd.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, w.framesWritten - 1), frame: w.framesWritten - 1)
                        if TemporalDepth.enabled { prevOut = pf }   // F2b's own single-frame prime (its documented approximate resume)
                        if let se = savedEMA { rangeEMA = se }
                    }
                }
                try h.seek(toOffset: UInt64(w.framesWritten * frameBytes))
            }
            for fi in w.framesWritten..<n {
                guard let data = try h.read(upToCount: frameBytes), data.count == frameBytes else { return .failed("spool short in phase 2") }
                let raw: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                let tD = DispatchTime.now(); var metres = skyClamped(aligned(raw, fi), frame: fi)
                if let po = prevOut { metres = TemporalDepth.smooth(prev: po, cur: metres) }; prevOut = metres          // F2b
                metres = rangeEMA.apply(metres)                                                    // 195h B depth-range EMA (default off: unchanged)
                if let om = overlayMask, let zs = zScreen { metres = DepthGuards.flattenOverlay(z: metres, mask: om, zScreen: zs) }
                hooks.depthMetres(metres)
                guard w.append(zMetres: metres) else { return .failed("container append failed") }
                if rangeEMA.active { _ = PrepareSupport.writeJSON(["lo": rangeEMA.lo, "hi": rangeEMA.hi, "primed": rangeEMA.primed, "frames": fi + 1], to: emaStateURL) }   // 195h r3-3: persisted only AFTER the append landed, with the container's new frame count
                hooks.stage("align_apply_dzc_append", Double(DispatchTime.now().uptimeNanoseconds - tD.uptimeNanoseconds) / 1e6)
                if !hooks.boundary({ w.synchronize() }) { return .cancelled }       // the container prefix is its own checkpoint (s16 resume)
            }
        } catch { return .failed("spool read in phase 2") }
        guard w.finish() else { return .failed("container finish failed") }
        try? fm.removeItem(at: job.spool); if let u = job.checkpointURL { try? fm.removeItem(at: u) }
        let fov = FovTrackBuilder.entry(startFrame: job.startFrame, endFrame: job.startFrame + n - 1, fps: job.fps,
                                        keyframes: zip(ck.fovFrames, ck.fovValues).map { (frame: $0.0, fov: $0.1) })
        return .done(ShotPrepareResult(dzc: job.dzc, fov: fov, alignScale: al.scale, alignShift: al.shift, alignSkipped: al.skipped, keyframesUsed: ck.pairsVDA.count, alignTrack: track.json))
    }
}

extension VDAWindowState {
    mutating func restore(id: Int, list: [[[Float]]]) { self.setState(id: id, list: list) }
}

#if canImport(CoreML)
/// Real backend: one VDAStreamRunner + one MoGeKeyframeRunner, frames from the caller (decoded source frames: `vdaChw` 154x266 bicubic-resized and normalised, `mogeRGBA`
/// resized to the picked shape). Both models share this single object, so they can never overlap. UNVERIFIED on a Mac.
final class NativeShotBackend: ShotPrepareBackend {
    private let vda: VDAStreamRunner, moge: MoGeKeyframeRunner
    private let vdaInput: (Int) -> [Float]?, mogeInput: (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)?
    init(vda: VDAStreamRunner, moge: MoGeKeyframeRunner, vdaInput: @escaping (Int) -> [Float]?, mogeInput: @escaping (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)?) {
        self.vda = vda; self.moge = moge; self.vdaInput = vdaInput; self.mogeInput = mogeInput
    }
    var window: VDAWindowState { get { vda.window } set { vda.window = newValue } }
    var stage: (String, Double) -> Void = { _, _ in }       // self-test: "input_prep" (decode + resize + CHW), "vda_model", "moge_model"
    private func ms(_ t: DispatchTime) -> Double { Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6 }
    /// s22: when set, the stream canvas is letterboxed (the vdaInput closure does that) and the output is cropped to the picture area before anything else sees it.
    var crop: VDAStream.Box?
    var lumaSource: () -> [Float]? = { nil }
    func guardLuma() -> [Float]? { lumaSource() }
    func vdaStep(frame: Int) -> [Float]? {
        let t = DispatchTime.now(); guard let c = vdaInput(frame) else { return nil }; stage("input_prep", ms(t))
        let m = DispatchTime.now(); defer { stage("vda_model", ms(m)) }
        guard let d = vda.process(chw: c) else { return nil }
        return crop.map { VDAStream.cropDepth(d, box: $0) } ?? d
    }
    func mogeKeyframe(frame: Int) -> MoGeKeyframe? {
        let t = DispatchTime.now(); guard let i = mogeInput(frame) else { return nil }; stage("input_prep", ms(t))
        let m = DispatchTime.now(); defer { stage("moge_model", ms(m)) }; return moge.run(rgba: i.rgba, shape: i.shape)
    }
}
#endif

#if canImport(Darwin)
extension ShotPrepareHooks {
    /// Binds a film's ShotSink (delivery lane, ThreeDPrepareSpawn.swift): its thermal-aware boundary and its single model lane. UNVERIFIED on a Mac.
    static func sink(_ sink: ShotSink, cancelled: @escaping () -> Bool) -> ShotPrepareHooks {
        var h = ShotPrepareHooks()
        h.boundary = { cp in sink.boundary(checkpoint: cp, cancelled: cancelled) }
        h.lane = { body in sink.runModel { body() } }
        return h
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation) && canImport(Metal) && canImport(CoreVideo)

/// 190t I: decides WHICH shot to render and WHEN, and switches the player between the 2D film and render_shot files. Everything that touches
/// the player is injected (`send` takes one JSON line, `query` sends one JSON line and returns the reply, `playhead` / `film` read player
/// state), so this file has no player-socket code. Idle (mode off, no 3D film open, no Metal) = no timer work beyond a cheap tick.
/// Switching is a hard `loadfile` at the playhead: the 0.5 s crossfade in ThreeDPresentation has no compositing surface yet, so the alpha is
/// computed but not drawn. Not run on a Mac.
final class ThreeDRenderCoordinator {
    private let send: (String) -> Void, mpvExecutable: () -> URL?
    private let playhead: () -> Double?, film: () -> URL?
    // G1 injects the ACTUAL active engine and R4-backed prepared session. Defaults
    // preserve every existing mpv caller. Gorav never invokes mpv decoder probes.
    private let activeEngine: () -> PlayerEngine
    private let preparedSession: @MainActor () -> PreparedShotPlayback?
    private let goravDecoders: () -> [String]
    private var preparedLoadTask: Task<Void, Never>?
    private var preparedLoadID = UUID()
    private var preparedLoadPending = false
    private let prefsReader = RenderPrefsReader()
    private let work = DispatchQueue(label: "gor.3d.render", qos: .utility)
    private var timer: Timer?, presentation = ThreeDPresentation()
    private var decoders: [String]?, writer: RenderShotWriter?, synthTold = false
    private var busy: [Int: UInt64] = [:]
    private let revision = RenderRevision()
    private var renderPrefs: RenderPrefsValue?
    private var showingURL: URL?
    private var lastGood: [Int: (url: URL, prefs: RenderPrefsValue)] = [:]
    private var retired = Set<URL>()
    private var boundFilmID: FilmID?
    private var observedDepthKeys: [Int:String] = [:]
    private var lastPTS: Double?, lastTick = 0.0, showing: Int?       // shot whose render file the player currently plays (nil = 2D)
    private var film2D: URL?                                         // the 2D film's URL (the player's path is the render file while 3D plays)
    private var announced = Set<String>()
    /// s38 degradation FSM: logs every transition (3dfsm lines) and executes only OSD actions; the depth-input swaps it names are already what tick/backTo2D do.
    private(set) lazy var degrade = ThreeDDegrade(exec: { [weak self] a in
        if a.hasPrefix("act_osd("), a.hasSuffix(")") { self?.announce(String(a.dropFirst(8).dropLast())) }
    })
    private var lastFilm: URL?, diskBlocked = false, relaunchChecked = false
    private var duty = ThermalDutyPolicy()      // same suspend/resume rule as the prepare gate, stepped per tick, feeds thermal_trip / thermal_clear
    private var indexCache: (entry: URL, index: DepthShotIndex)?
    /// Frame range of the playhead's shot, kept fresh every tick even while mode is off (the menu reads it to enable sbs/vr180).
    private(set) var shotFrames: (Int, Int)?

    init(send: @escaping (String) -> Void, mpvExecutable: @escaping () -> URL?, playhead: @escaping () -> Double?, film: @escaping () -> URL?,
         activeEngine: @escaping () -> PlayerEngine = { .mpv },
         preparedSession: @escaping @MainActor () -> PreparedShotPlayback? = { nil },
         goravDecoders: @escaping () -> [String] = { [] }) {
        self.send = send; self.mpvExecutable = mpvExecutable; self.playhead = playhead; self.film = film
        self.activeEngine = activeEngine
        self.preparedSession = preparedSession
        self.goravDecoders = goravDecoders
    }

    private var cachePin: DepthCacheBudget.Pin?
    private var cachePinKey: String?
    private var mediaTransitionPending=false
    func setMediaTransitionPending(_ pending:Bool) {
        mediaTransitionPending=pending
        if pending {
            cachePin=nil;cachePinKey=nil
            revision.invalidate();preparedLoadTask?.cancel();preparedLoadTask=nil
            preparedLoadID=UUID();preparedLoadPending=false
            showing=nil;showingURL=nil;film2D=nil;lastFilm=nil;indexCache=nil
            lastGood=[:];lastPTS=nil;ThreeDSubtitleDepth.shared.end()
        }
    }
    private var storeOutput=ThreeDOutput.off
    func applyStoreOutput(_ output:ThreeDOutput,reapply:Bool=false,filmID:FilmID?=nil) {
        if filmID != boundFilmID {
            preparedLoadTask?.cancel(); preparedLoadTask=nil
            preparedLoadID=UUID(); preparedLoadPending=false
            revision.invalidate();boundFilmID=filmID;lastGood=[:]
            showing=nil;showingURL=nil;film2D=nil;lastFilm=nil;indexCache=nil
            renderPrefs=nil;observedDepthKeys=[:];lastPTS=nil;ThreeDSubtitleDepth.shared.end()
        }
        guard output != storeOutput else {return}
        lastGood=[:]
        storeOutput=output
        revision.invalidate()
        if output != .off && showing != nil { backTo2D(playhead() ?? 0,filmURL:film2D) }
        if output == .off {backTo2D(playhead() ?? 0,filmURL:film2D)}
    }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.05
    }

    /// Called by the store subscriber immediately after writing render preferences.
    /// This cancels work now; the timer starts replacements only after debounce.
    func preferencesDidChange(force: Bool = false) {
        let prefs=prefsReader.refresh()
        if force {revision.invalidate()}
        if force || prefs != renderPrefs {
            renderPrefs=prefs
            revision.update(String(describing:prefs),now:ProcessInfo.processInfo.systemUptime)
            print("3D-RENDER v1 event=preferences generation=\(revision.token) debounce_ms=500")
        }
    }

    /// s33 F3: depth content version = the shot's .dzc size + mtime (nanoseconds). A re-prepare (e.g. another quality) rewrites the container, so a stale render_shot file no longer matches.
    static func depthStamp(_ dzc: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: dzc.path)
        let size = (a?[.size] as? NSNumber)?.int64Value ?? -1, t = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "|d\(size)-\(Int64((t*1_000_000_000).rounded()))"
    }
    /// Stable key of everything that changes a render's pixels; stored next to each file so a prefs change re-renders it.
    static func key(_ p: RenderPrefsValue, eyeN: Int, codec: RenderedShotPlan.Codec, swap: Bool, method: SynthMethod = SynthMethod.current.method, options: ThreeDExperimentOptions = .live) -> String {
        // v5: span-p5p95 invalidates median-only comfort renders; the depth stamp fixes shot quantiles.
        // v4 (190w W3): the synthesis method is part of the key, so a tier change re-prepares every stand-in render (v3-keyed files are stale; existing marker-only eviction). Mirror: rehearsal.render_key_v4.
        // v3 (CONTRACT-190v s33): under comfort the render uses ipdM * shotScale * strengthFactor, so key on ipdM and the strength FACTOR (not effectiveIPD = ipdM * strength):
        // fixes F1 (ipdM .063 x2 vs .126 x1 collided) and F2 (strength 2 -> 3 above the cap changed the key, not the pixels). The fixed path renders with effectiveIPD.
        let ipdPart = p.comfortActive ? "comfort|ipd\(p.ipdM)|sf\(ShotComfort.strengthFactor(p.depthScale, overBudget: p.overBudget))" : "fixed|ipd\(p.effectiveIPD)"
        // 195h r2: experiment switches invalidate cached renders through this key; all-off keys stay byte-identical with the pre-195h strings.
        return "v5|span-p5p95|\(method.rawValue)|\(options.renderKeyComponent.map { $0 + "|" } ?? "")\(ipdPart)|\(OutputMode.parse(p.mode)?.rawValue ?? p.mode)|\(p.convergenceM.map { "\($0)" } ?? "nil")|\(eyeN)|\(codec.rawValue)|\(swap)|\(p.screenDeg)|\(p.surroundSoft)"
    }
    /// Eye size: the source picture height (even), at least 256, at most 4096 (an 8192-wide HEVC frame). Never below the source: no thumbnail.
    static func eyeN(sourceHeight: Int) -> Int { max(256, min(4096, sourceHeight - sourceHeight % 2)) }

    private func shotIndex(_ entry: URL) -> DepthShotIndex? {
        if let c = indexCache, c.entry == entry { return c.index }
        guard let i = DepthShotIndex(entry: entry) else { return nil }
        indexCache = (entry, i); return i
    }

    private func announce(_ text: String) {
        ThreeDShotPlayLog.logOSD(text)                           // X1: the log carries the OSD text even when the menu toggle hides it
        guard MainActor.assumeIsolated({ThreeDStore.shared.snapshot.effects[.osdLine] != .bool(false)}) else { return }      // the "osd line" menu toggle
        guard announced.insert(text).inserted, let d = try? JSONSerialization.data(withJSONObject: ["command": ["show-text", text, 4000]]),
              let s = String(data: d, encoding: .utf8) else { return }
        send(s)
    }

    private func tick() {
        guard !mediaTransitionPending else { return }
        preferencesDidChange()
        let prefs = renderPrefs ?? prefsReader.refresh(), now = Date.timeIntervalSinceReferenceDate
        if showing == nil { film2D = film() }                      // while a render file plays, the player's path is the render file, not the film
        // Protect the source film even while 3D output is off. A different
        // worker must not evict it during playback. Key hashing stays async.
        let playingKey = film2D.flatMap { CacheKeyMemo.key(path: $0.path) }
        if playingKey != cachePinKey || cachePin == nil {
            cachePin=nil;cachePinKey=playingKey
            if let key=playingKey {cachePin=try? DepthCacheBudget.pin(root:DepthCachePaths.root,key:key)}
        }
        let mapped = playhead()
        // 191o F6 interim: 2D-to-VR180 stays on the flat virtual-screen path until PIN V V6.
        if prefs.mode == "vr180" {revision.invalidate();backTo2D(mapped ?? 0,filmURL:film2D);lastPTS=nil;return}
        // A2: global render prefs and ready-cache callbacks never overrule this film's OUTPUT.
        // Native SOURCE is re-presented directly, never replaced by a depth-converted shot.
        guard let sourceFilm=film2D,
              SourceFormatChoice.output(sourceFilm.path) != "off",
              SourceFormatChoice.output(sourceFilm.path)==prefs.mode,
              StereoSourceGate.shared.route(for:sourceFilm)?.route == .depth else {
            revision.invalidate();backTo2D(mapped ?? 0,filmURL:film2D);lastPTS=nil;return
        }
        shotFrames = mapped.flatMap { p in currentEntry().flatMap { shotIndex($0) }?.shotFrames(pts: p) }
        // rendered files keep film time (rebase-start-time=no), so the player's time-pos IS film time in both modes
        let unavailable = ThreeDPreflight.shared.reason          // no libx265 ffmpeg / no HEVC decode: a saved sbs/vr180 still stays 2D
        if let why = unavailable, prefs.mode != "off" { announce(why) }
        if film2D != lastFilm {
            revision.invalidate();renderPrefs=nil;preferencesDidChange();lastGood=[:]
            if lastFilm != nil { degrade.sourceChanged() }; lastFilm = film2D
        }
        degrade.userMode(on: prefs.mode != "off")
        switch duty.step(rank: ProcessInfo.processInfo.thermalState.rawValue, now: ProcessInfo.processInfo.systemUptime) { case .suspend: degrade.thermal(trip: true); case .resume: degrade.thermal(trip: false); default: break }
        if prefs.mode != "off", degrade.state == "INIT" || degrade.state == "UNAVAILABLE_FLAT", let f = film2D, StereoSourceGate.shared.route(for: f)?.route == .depth {   // an already-3D film never goes through depth: no probe, no "preparing" badge       // source refusals first (HDR/VFR), then the kit outcome
            let k = ThreeDKit.probeState()
            if let s = ThreeDDegradeProbe.sourceEvent(film: f) {
                if !s.isEmpty { degrade.probe(s) }
                else if let e = ThreeDDegradeProbe.kitEvent(missing: k.missing, verified: k.verified, verifyFailed: k.failed, verifying: k.verifying) { degrade.probe(e) }
            }
        }
        if !relaunchChecked, let f = film2D, CacheKeyMemo.key(path: f.path).map({ FileManager.default.fileExists(atPath: DepthCachePaths.root.appendingPathComponent($0).appendingPathComponent("cuts.json").path) }) == true {
            relaunchChecked = true; if degrade.state == "INIT" { degrade.feed("relaunch") }          // cold start with a prepared cache present
        }
        if ThreeDDegradeProbe.takeDiskFull() { diskBlocked = true; degrade.disk(full: true) }
        else if diskBlocked, ThreeDDegradeProbe.headroomOK(at: DepthCachePaths.root) { diskBlocked = false; degrade.disk(full: false) }
        guard prefs.mode != "off", unavailable == nil, let pts = mapped, let filmURL = film2D else { revision.invalidate(); backTo2D(mapped ?? 0, filmURL: film2D); lastPTS = nil; return }
        let seeked = lastPTS.map { abs(pts - $0) > max(2.0, (now - lastTick) * 2.5) } ?? false
        lastPTS = pts; lastTick = now
        if showing != nil { ThreeDSubtitleDepth.shared.refreshPrepared(pts:pts) }
        let playbackDecoders: [String]
        if activeEngine() == .gorav {
            playbackDecoders = goravDecoders() // Actual native admission, not mpv --vd=help.
        } else {
            if decoders == nil { decoders = mpvExecutable().map { RenderedShotMPV.probeDecoders(executable: $0) } ?? [] }
            playbackDecoders = decoders ?? []
        }
        guard let entry = currentEntry(), let index = shotIndex(entry), let hit = index.find(pts: pts), let th = index.thetaH(pts: pts) else {
            if !holdsEncoded(pts) {presentation.update(now:now,covered:false,shot:nil,seeked:seeked,enabled:true);backTo2D(pts,filmURL:filmURL)}
            return
        }
        let expOpts = ThreeDExperimentOptions.live   // 195h r2-2: ONE snapshot per render request, threaded through the mode check, the key, the writer and render()
        if !PrepareSupport.optionsMatch(dzc: hit.depth, options: expOpts) {   // 195h r3-4: this container was prepared in another experiment mode
            ThreeDPrepareRuntime.launcher?.noteModeMismatch(current: expOpts.prepareComponent)   // stop only an old-mode job; the current-mode rebuild is never cancelled by these 250 ms ticks
            if !holdsEncoded(pts) {presentation.update(now:now,covered:false,shot:hit.shot,seeked:seeked,enabled:true);backTo2D(pts,filmURL:filmURL)}
            return
        }
        guard Self.shotReady(entry: entry, shot: hit.shot) else {   // A-D marks it failed (retried by its next chunk): stay 2D, render nothing
            if !holdsEncoded(pts) {presentation.update(now:now,covered:false,shot:hit.shot,seeked:seeked,enabled:true);backTo2D(pts,filmURL:filmURL)}
            return
        }
        let side = readJSON(entry.appendingPathComponent(String(format: "depth_shot_%05d.json", hit.shot))) ?? [:]
        let sh = (side["source_height"] as? Int) ?? (side["depth_height"] as? Int) ?? 0
        let sw0 = (side["source_width"] as? Int) ?? (side["depth_width"] as? Int) ?? 0
        guard sh > 0, let plan = RenderedShotPlan.make(eyeN: Self.eyeN(sourceHeight: sh), decoders: playbackDecoders, swapEyes: true, output: OutputMode.parse(prefs.mode) ?? .fullSBS, srcW: sw0, srcH: sh) else {
            announce("3D: the player has no HEVC/H.264 decoder for this size, staying 2D"); backTo2D(pts, filmURL: filmURL); return
        }
        if !synthTold { synthTold = true; print("3d-synth: \(SynthMethod.current.method.rawValue)"); fflush(stdout); announce(SynthMethod.current.note) }   // 190w W3: the method that actually runs, "fallback" labelled
        let baseKey = Self.key(prefs, eyeN: plan.eyeN, codec: plan.codec, swap: plan.swapEyes, options: expOpts), key = baseKey + Self.depthStamp(entry.appendingPathComponent(String(format: "depth_shot_%05d.dzc", hit.shot)))
        let depthIdentity=entry.path+Self.depthStamp(hit.depth)
        if let previous=observedDepthKeys[hit.shot], depthIdentity != previous {
            // A rewritten depth container invalidates a job even with identical preferences.
            revision.update("depth:"+depthIdentity+String(describing:prefs),now:ProcessInfo.processInfo.systemUptime)
        }
        observedDepthKeys[hit.shot]=depthIdentity
        let out = entry.appendingPathComponent(RenderRevision.fileName(shot:hit.shot,key:key))
        let side2 = out.deletingPathExtension().appendingPathExtension("json")
        let fresh = FileManager.default.fileExists(atPath: out.path) && (readJSON(side2)?["key"] as? String) == key
        let legacy=entry.appendingPathComponent(RenderedShotPlan.fileName(shot:hit.shot))
        let legacySide=legacy.deletingPathExtension().appendingPathExtension("json")
        if lastGood[hit.shot]==nil, FileManager.default.fileExists(atPath:legacy.path),
           let legacyKey=readJSON(legacySide)?["key"] as? String,
           legacyKey==key {
            // Legacy cache is considered only when it has exactly the current key.
            lastGood[hit.shot]=(legacy,prefs)
        }
        let held=RenderContinuity.holds(showing:showing,next:hit.shot,fileExists:showingURL.map {FileManager.default.fileExists(atPath:$0.path)} ?? false)
        let selected=fresh ? (url:out,prefs:prefs):lastGood[hit.shot]
        let available=held || selected.map {FileManager.default.fileExists(atPath:$0.url.path)} == true
        presentation.update(now:now,covered:available,shot:hit.shot,seeked:seeked,enabled:true)
        degrade.observe(covered:available,now:ProcessInfo.processInfo.systemUptime)
        if let selected, FileManager.default.fileExists(atPath:selected.url.path) {
            let candidate=selected.url
            let selectedKey=(readJSON(candidate.deletingPathExtension().appendingPathExtension("json"))?["key"] as? String) ?? "unknown"
            let prefs=selected.prefs // subtitles follow the actually encoded last-good picture
            if RenderContinuity.shouldLoad(showing:showing,next:hit.shot,seeked:seeked,showingURL:showingURL,candidateURL:candidate) {
                if activeEngine() == .gorav {
                    // Publish look/subtitle state only after native commit, never
                    // from intended state or after a stale film/prefs callback.
                    loadPreparedNative(render: candidate, source: filmURL, start: pts) { [weak self] in
                        guard let self else { return }
                        let look = RenderedShotMPV.plannedLook(plan: plan)
                        print("3D-EXPERIMENT applied route=gorav shot=\(hit.shot) fresh=\(fresh) key=\(selectedKey)"); fflush(stdout)
                        self.showing=hit.shot; self.showingURL=candidate; self.collectRetired()
                        if let id=ThreeDStore.shared.snapshot.currentFilm {
                            ThreeDStore.shared.dispatch(.generated(id,look.source,look.output,aspect:look.aspect))
                        }
                        ThreeDShotPlayLog.logShot(shot:hit.shot,pts:pts,menuMode:prefs.mode,key:Self.key(prefs,eyeN:plan.eyeN,codec:plan.codec,swap:plan.swapEyes))
                        let sw=(side["source_width"] as? Int) ?? (side["depth_width"] as? Int) ?? 0
                        let dz=hit.depth
                        ThreeDSubtitleDepth.shared.begin(depth:dz,pts:pts,thetaH:prefs.thetaH(shotThetaH:th,aspect:Double(max(1,sw))/Double(max(1,sh)))) {
                            let cf=prefs.comfortActive ? ShotComfortShot.compute(depth:dz,ipd:prefs.ipdM).map { c -> ShotComfort in var r=c; r.zNear=prefs.comfortZNear(c); return r } : nil
                            return ThreeDSubtitleDepth.params(ipdM:prefs.ipdM,effectiveIPD:prefs.effectiveIPD,convergenceM:prefs.convergenceM,comfort:cf,comfortIPD:cf.map {prefs.comfortIPD($0)})
                        }
                    }
                } else if let cmd = RenderedShotMPV.load(render: candidate, source: filmURL, start: pts) {
                // Load before publishing the generated source, so the old parent
                // frame never receives the new source layout. Only the applier writes routes.
                let look=RenderedShotMPV.plannedLook(plan:plan)
                print("3D-RENDER v1 event=load generation=\(revision.token) shot=\(hit.shot) fresh=\(fresh) key=\(selectedKey)")
                send(cmd); showing = hit.shot; showingURL=candidate;collectRetired()
                MainActor.assumeIsolated {if let id=ThreeDStore.shared.snapshot.currentFilm {ThreeDStore.shared.dispatch(.generated(id,look.source,look.output,aspect:look.aspect))}}
                ThreeDShotPlayLog.logShot(shot: hit.shot, pts: pts, menuMode: prefs.mode, key: Self.key(prefs,eyeN:plan.eyeN,codec:plan.codec,swap:plan.swapEyes))    // X1: one gor3d-shot line per played shot
                // Recognition skips generated files; revision-owned applier routes reject other senders.
                let sw = (side["source_width"] as? Int) ?? (side["depth_width"] as? Int) ?? 0
                let dz = hit.depth
                ThreeDSubtitleDepth.shared.begin(depth: dz, pts: pts, thetaH: prefs.thetaH(shotThetaH: th, aspect: Double(max(1, sw)) / Double(max(1, sh)))) {
                    let cf = prefs.comfortActive ? ShotComfortShot.compute(depth: dz, ipd: prefs.ipdM).map { c -> ShotComfort in var r = c; r.zNear = prefs.comfortZNear(c); return r } : nil      // same values the render of this shot used
                    return ThreeDSubtitleDepth.params(ipdM: prefs.ipdM, effectiveIPD: prefs.effectiveIPD, convergenceM: prefs.convergenceM, comfort: cf, comfortIPD: cf.map { prefs.comfortIPD($0) })
                }
                }
            }
        } else if !held {
            backTo2D(pts, filmURL: filmURL)
        }
        if fresh {remember(shot:hit.shot,url:out,prefs:prefs)}
        // Render current shot first and then forward. Keep displaying the old
        // encoded shot while its replacement is pending; never flash the parent.
        if revision.ready(now:ProcessInfo.processInfo.systemUptime) {
            schedule(index:index,from:hit.shot,prefs:prefs,plan:plan,key:baseKey,th:th,entry:entry,options:expOpts)
        }
    }

    /// CONTRACT-190v s8: render-ready.json says the shot has depth AND source proxy and its last attempt did not fail. Absent or unreadable sidecar
    /// (older cache) = no objection: the file checks in DepthShotIndex.find still apply.
    static func shotReady(entry: URL, shot: Int) -> Bool {
        guard let d = try? Data(contentsOf: entry.appendingPathComponent("render-ready.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let arr = o["shots"] as? [[String: Any]],
              let e = arr.first(where: { ($0["shot"] as? Int) == shot }) else { return true }
        return (e["ready"] as? Bool) == true && (e["failed"] as? Bool) != true
    }

    private func remember(shot: Int, url: URL, prefs: RenderPrefsValue) {
        if let prior=lastGood[shot]?.url,prior != url {retired.insert(prior)}
        lastGood[shot]=(url,prefs);collectRetired()
    }
    private func collectRetired() {
        let retained=Set(lastGood.values.map { $0.url })
        for url in retired where url != showingURL && !retained.contains(url) {
            try? FileManager.default.removeItem(at:url)
            try? FileManager.default.removeItem(at:url.deletingPathExtension().appendingPathExtension("json"))
            retired.remove(url)
        }
    }

    /// A depth re-prepare may temporarily remove coverage metadata. The old
    /// encoded file still covers its original shot; never carry it across a cut.
    private func holdsEncoded(_ pts: Double) -> Bool {
        guard let shot=showing,let url=showingURL,FileManager.default.fileExists(atPath:url.path),
              let index=indexCache?.index,index.shots.indices.contains(shot),index.shots[shot].count==2 else {return false}
        let range=index.shots[shot]
        return pts>=Double(range[0])/index.fps && pts<Double(range[1]+1)/index.fps
    }

    private func backTo2D(_ pts: Double, filmURL: URL?) {
        guard !mediaTransitionPending else { return }
        if activeEngine() == .gorav {
            guard showing != nil, let f=filmURL else { return }
            loadPreparedNative(render:nil,source:f,start:pts) { [weak self] in
                guard let self else { return }
                self.showing=nil; self.showingURL=nil
                ThreeDShotPlayLog.shotEnded(); ThreeDStore.shared.dispatch(.original)
                ThreeDSubtitleDepth.shared.end()
            }
            return
        }
        guard showing != nil, let f = filmURL, let cmd = RenderedShotMPV.load2D(file: f, start: pts) else { return }
        showing = nil; showingURL=nil; ThreeDShotPlayLog.shotEnded(); MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.original)};send(cmd); ThreeDSubtitleDepth.shared.end()
    }

    /// Native multi-source route. No IPC fallback and no duplicate task per tick.
    /// G1 must supply the current session; nil is a visible capability refusal.
    private func loadPreparedNative(render:URL?,source:URL,start:Double,
                                    committed:@escaping @MainActor () -> Void) {
        guard !preparedLoadPending else { return }
        let id=UUID(), token=revision.token, filmID=boundFilmID
        preparedLoadID=id; preparedLoadPending=true
        preparedLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.preparedLoadID==id {
                    self.preparedLoadPending=false; self.preparedLoadTask=nil
                }
            }
            guard self.activeEngine() == .gorav,
                  let player=self.preparedSession() else {
                print("3D-RENDER native refused=multi-source-unavailable")
                return
            }
            do {
                if let render {
                    _ = try await player.loadPreparedShot(render:render,source:source,start:start)
                } else {
                    _ = try await player.loadSource2D(file:source,start:start)
                }
                guard !Task.isCancelled, self.preparedLoadID==id,
                      self.boundFilmID==filmID, self.activeEngine() == .gorav else { return }
                if !self.revision.isCurrent(token) {
                    // A mode/prefs change can land while the video swap awaits.
                    // Restore source before publishing nothing, otherwise the
                    // engine could show a render that gor thinks is still 2D.
                    if render != nil {
                        _ = try await player.loadSource2D(file:source,start:self.playhead() ?? start)
                        guard !Task.isCancelled, self.preparedLoadID==id,
                              self.boundFilmID==filmID else { return }
                        self.showing=nil; self.showingURL=nil
                        ThreeDShotPlayLog.shotEnded(); ThreeDStore.shared.dispatch(.original)
                        ThreeDSubtitleDepth.shared.end()
                    }
                    return
                }
                committed()
            } catch {
                print("3D-RENDER native refused=prepared-load error=\(error)")
            }
        }
    }

    /// Renders the playhead shot first, then the following ones, one at a time (utility queue); a prefs change or mode off cancels the running one.
    private func schedule(index: DepthShotIndex, from first: Int, prefs: RenderPrefsValue, plan: RenderedShotPlan, key baseKey: String, th: Double, entry: URL, options expOpts: ThreeDExperimentOptions) {   // 195h r3-1: the request snapshot arrives with the call
        let token=revision.token
        for shot in first..<min(first + 3, index.shots.count) where busy[shot] != token {
            let mp4 = entry.appendingPathComponent(String(format: "depth_shot_%05d.dzc", shot)), src = entry.appendingPathComponent(String(format: "source_shot_%05d.mp4", shot))
            guard DZCFile.isComplete(mp4), FileManager.default.fileExists(atPath: src.path), Self.shotReady(entry: entry, shot: shot) else { continue }
            let key = baseKey + Self.depthStamp(mp4)
            let out = entry.appendingPathComponent(RenderRevision.fileName(shot:shot,key:key)), side2 = out.deletingPathExtension().appendingPathExtension("json")
            if FileManager.default.fileExists(atPath:out.path) {
                if (readJSON(side2)?["key"] as? String)==key {continue}
                // A crash can leave a complete file without its key sidecar.
                // Rebuild that orphan, but never unlink a retained/playing file.
                guard out != showingURL,!lastGood.values.contains(where: {$0.url==out}) else {continue}
                try? FileManager.default.removeItem(at:out)
                try? FileManager.default.removeItem(at:side2)
            }
            let side = readJSON(entry.appendingPathComponent(String(format: "depth_shot_%05d.json", shot))) ?? [:]
            let dsz = ((side["depth_width"] as? Int), (side["depth_height"] as? Int)), ssz = ((side["source_width"] as? Int), (side["source_height"] as? Int))
            let shotTheta=index.thetaH(pts:Double(index.shots[shot][0])/index.fps) ?? th
            busy[shot]=token
            work.async { [weak self] in
                guard let self else { return }
                guard self.revision.isCurrent(token) else {
                    DispatchQueue.main.async {if self.busy[shot]==token {self.busy.removeValue(forKey:shot)}}
                    return
                }
                guard let pin=try? DepthCacheBudget.pin(root:entry.deletingLastPathComponent(),key:entry.lastPathComponent) else {
                    DispatchQueue.main.async { if self.busy[shot]==token {self.busy.removeValue(forKey:shot)};self.announce("3D: cache safety check failed; staying 2D") };return
                }
                defer {withExtendedLifetime(pin) {}}
                let diskWatch=DepthCacheBudget.Watch(root:entry.deletingLastPathComponent())
                guard diskWatch.allowed(force:true) else {
                    DispatchQueue.main.async {if self.busy[shot]==token {self.busy.removeValue(forKey:shot)};self.announce(diskWatch.failure!.description)};return
                }
                print("3D-RENDER v1 event=started generation=\(token) shot=\(shot)")
                if self.writer == nil { self.writer = RenderShotWriter() }
                var ok = false
                if let w = self.writer, let dw = dsz.0, let dh = dsz.1 {
                    let sz = (ssz.0 != nil && ssz.1 != nil) ? (w: ssz.0!, h: ssz.1!) : nil
                    let cf = prefs.comfortActive ? ShotComfortShot.compute(depth: mp4, ipd: prefs.ipdM) : nil
                    ok = (try? w.write(source: src, depth: mp4, depthSize: (dw, dh), sourceSize: sz, thetaH: prefs.thetaH(shotThetaH: shotTheta, aspect: Double(sz?.w ?? dw) / Double(max(1, sz?.h ?? dh))), plan: plan, ipd: cf.map { prefs.comfortIPD($0) } ?? prefs.effectiveIPD,
                                       convergence: cf?.convergenceM ?? prefs.convergenceM, zNear: cf.map { prefs.comfortZNear($0) }, surround: prefs.surroundSoft, options: expOpts, out: out, cancelled: { !self.revision.isCurrent(token) || !diskWatch.allowed() })) != nil
                }
                let published:Bool
                if ok {
                    published=(try? self.revision.commit(token) {
                        try JSONSerialization.data(withJSONObject:["key":key]).write(to:side2,options:.atomic)
                    }) ?? false
                } else {published=false}
                print("3D-RENDER v1 event=finished generation=\(token) shot=\(shot) published=\(published) current=\(self.revision.isCurrent(token))")
                if !published && ok {try? FileManager.default.removeItem(at:out);try? FileManager.default.removeItem(at:side2)}
                DispatchQueue.main.async {
                    guard self.revision.isCurrent(token) else {if self.busy[shot]==token {self.busy.removeValue(forKey:shot)};return}
                    if let failure=diskWatch.failure {self.announce(failure.description)}
                    if published {self.remember(shot:shot,url:out,prefs:prefs);self.degrade.shotSucceeded(shot)}
                    else {self.degrade.shotFailed(shot);self.announce("3D: shot \(shot) could not be rendered; keeping available stereo")}
                    if self.busy[shot]==token {self.busy.removeValue(forKey:shot)}
                }
            }
        }
    }

    private func currentEntry() -> URL? {
        guard let p = readJSON(DepthCachePaths.root.appendingPathComponent("current-film.json")), let k = p["cache_key"] as? String else { return nil }
        return DepthCachePaths.root.appendingPathComponent(k, isDirectory: true)
    }
    private func readJSON(_ u: URL) -> [String: Any]? { (try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t I (render path): the fixed rules for render_shot_NNNNN.mp4, the Stereo3DRenderer output that mpv plays through the vr180 path.
/// E-G review conditions (1)-(5) are encoded here so the writer and the player setup cannot drift. Pure; nothing here runs mpv or Metal.
struct RenderedShotPlan: Equatable {
    enum Codec: String, Equatable { case hevc, h264 }
    let eyeN: Int                   // (1) each eye is N x N, so render(outW: N, outH: N) into an sbsOut of 2N x N
    let codec: Codec
    let swapEyes: Bool              // (2) vr_swap_eyes == 1.0 (the default): passed to Stereo3DRenderer.render(swapEyes:), positive ipd
    var output: OutputMode = .vr180 // s36: vr180 (N x N eyes) or a flat mode (eyes at the source size srcW x srcH)
    var srcW = 0, srcH = 0
    var canvas: (w: Int, h: Int) { output.isFlat ? output.canvasSize(srcW: srcW, srcH: srcH) : (eyeN * 2, eyeN) }
    var sbsWidth: Int { canvas.w }
    /// Player projection for the rendered file: vr180 stays vr180; flat modes use the existing flat packings (sbs, tb) with the per-eye aspect (half_sbs: the squeezed halves stretch back to srcW/srcH);
    /// anaglyph is one ordinary 2D picture (nil = no stereo look setup).
    var lookProjection: (kind: String, eyeAspect: Double)? {
        let a = srcH > 0 ? Double(srcW) / Double(srcH) : 0
        switch output { case .vr180: return (RenderedShotPlan.projectionKind, 0); case .fullSBS, .halfSBS: return ("flat-sbs", a); case .overUnder: return ("flat-tb", a); case .anaglyph: return nil }
    }
    static let h264MaxWidth = 4096

    /// (4) `decoders` = names from mpv's `decoder-list` property of the PLAYER mpv. HEVC when present. H.264 only when HEVC is
    /// missing AND the width fits 4096; otherwise nil (render nothing and say so on the OSD, never a silent downgrade).
    /// `swapEyes` mirrors the live vr_swap_eyes parameter (default true).
    static func make(eyeN: Int, decoders: [String], swapEyes: Bool = true, output: OutputMode = .vr180, srcW: Int = 0, srcH: Int = 0) -> RenderedShotPlan? {
        guard eyeN >= 256, eyeN % 2 == 0, !output.isFlat || (srcW >= 2 && srcH >= 2 && srcW % 2 == 0) else { return nil }
        let have = Set(decoders.map { $0.lowercased() })
        let hevc = RenderedShotPlan(eyeN: eyeN, codec: .hevc, swapEyes: swapEyes, output: output, srcW: srcW, srcH: srcH)
        if have.contains("hevc") { return hevc }
        if have.contains("h264"), hevc.canvas.w <= h264MaxWidth { return RenderedShotPlan(eyeN: eyeN, codec: .h264, swapEyes: swapEyes, output: output, srcW: srcW, srcH: srcH) }
        return nil
    }

    /// Eye offset to pass as Stereo3DRenderer.render(ipd:): always positive (RenderPrefsValue.effectiveIPD); eye order is `swapEyes`.
    func ipd(effective: Double) -> Double { abs(effective) }

    /// (3) Rendered files are already stereo and full frame: projection "vr180" (never flat-2d3d, no synthetic disparity twice),
    /// no menu crop (crop 1,1) and the full source-eye rectangle, so CropAcceptPolicy has nothing to cut.
    static let projectionKind = "vr180"
    static let menuCrop = (x: 1.0, y: 1.0)
    static let sourceEyeCrop = (x: 0.0, y: 0.0, w: 1.0, h: 1.0)

    /// (5) Timing: the video packets carry FILM time (PTS = source PTS of the frame), audio is never in the render file: mpv keeps the
    /// source audio track (audio-file / the original), so a seek inside the rendered range moves both from the same film time.
    static let ptsIsFilmTime = true, carriesAudio = false
    static func fileName(shot: Int) -> String { String(format: "render_shot_%05d.mp4", shot) }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t I: the player-side messages for render_shot files, as plain JSON lines. This file only BUILDS and PARSES text; the caller sends
/// them over the existing player socket (the one call-site that owns that socket is the wiring step, not done here).
enum RenderedShotMPV {
    /// E-G condition 4: which decoders the PLAYER mpv has. Runs `<mpv> --vd=help` (no socket) and keeps the names hevc / h264 when they appear as
    /// whole words (hevc_videotoolbox alone does not count: only a software or hwdec-independent hevc decoder entry does). Empty when it cannot run.
    static func probeDecoders(executable: URL) -> [String] {
        let p = Process(); p.executableURL = executable; p.arguments = ["--no-config", "--vd=help"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { print("gor3d-decoder-probe v1 launch_failed executable=\(executable.path)"); return [] }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let found = decoders(helpText: String(decoding: data, as: UTF8.self))
        print("gor3d-decoder-probe v1 rc=\(p.terminationStatus) bytes=\(data.count) decoders=\(found.joined(separator: ",")) executable=\(executable.path)")
        return found
    }

    static func decoders(helpText: String) -> [String] {
        ["hevc", "h264"].filter { name in
            helpText.range(of: "(^|[^A-Za-z0-9_])\(name)([^A-Za-z0-9_]|$)", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func line(_ cmd: [Any]) -> String? {
        (try? JSONSerialization.data(withJSONObject: ["command": cmd])).flatMap { String(data: $0, encoding: .utf8) }
    }

    struct Look: Equatable {let source:ThreeDSource;let output:ThreeDOutput;let aspect:Double}
    /// No player messages: the store applier is the only route writer.
    static func plannedLook(plan: RenderedShotPlan) -> Look {
        let source=ThreeDSource(plan.output == .vr180 ? .vr180SBS : (plan.output == .overUnder ? .tbFull : (plan.output == .anaglyph ? .flat2D:.sbsFull)))
        return Look(source:source,output:ThreeDOutput(rawValue:plan.output.rawValue) ?? .off,aspect:plan.lookProjection?.eyeAspect ?? 0)
    }

    /// (5) Play the render file from film time `start`. rebase-start-time=no keeps the file's own timestamps (= film time), so time-pos stays film time
    /// and the source audio (which starts at film 0) lines up; the render file carries no audio. The loadfile index argument is -1 (mpv 0.38+); not run here.
    static func load(render: URL, source: URL, start: Double) -> String? {
        let opts = "start=\(String(format: "%.3f", start)),rebase-start-time=no,audio-file=\(source.path)"
        return line(["loadfile", render.path, "replace", -1, opts])
    }

    /// Back to the 2D film at film time `start` (its own audio, no audio-file option).
    static func load2D(file: URL, start: Double) -> String? {
        line(["loadfile", file.path, "replace", -1, "start=\(String(format: "%.3f", start))"])
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation) && canImport(Metal) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
import Metal

/// 190t I: writes render_shot_NNNNN.mp4 for one prepared shot. Inputs follow the agreed contracts: source_shot_NNNNN.mp4 (A-D's decoded
/// source proxy, BGRA-readable, same picture size as the depth luma after the sidecar crop), depth_shot_NNNNN.dzc (DepthFrameReader, s16 lossless),
/// thetaH from DepthShotIndex. A depth box smaller than the source (s22 letterbox) is bilinearly resampled to the source size (DepthUpsampler); the source is never resampled. Each frame: depth luma -> metric Z (decodeDepth, shift 0) -> crop to the sidecar size -> Stereo3DRenderer.render
/// -> 2N x N SBS -> HEVC/H.264 packets stamped with the SOURCE film PTS. No audio is written. Frames pair by order inside the shot
/// and the pair's PTS must agree within half a frame; any mismatch or resource failure aborts and removes the partial file (never a silent skip).
/// Not run on a Mac: the BGRA/RGBA channel order, VT behaviour and speed are unmeasured.
final class RenderShotWriter {
    enum Failure: Error { case open, size, depth, render, write, pairing }
    private let device: MTLDevice, renderer: Stereo3DRenderer

    init?(renderer: Stereo3DRenderer? = Stereo3DRenderer.make()) {
        guard let r = renderer, let d = MTLCreateSystemDefaultDevice() else { return nil }
        self.renderer = r; device = d
    }

    /// `depthSize`: sidecar depth_width/depth_height and `sourceSize`: source_width/source_height (both unpadded; nil = the buffer size).
    /// Both pictures are cropped (top-left blit, no resampling) to that size and must then agree. Returns the output URL; throws and deletes on failure.
    func write(source: URL, depth: URL, depthSize: (w: Int, h: Int)?, sourceSize: (w: Int, h: Int)? = nil, thetaH: Double, plan: RenderedShotPlan, ipd: Double,
               convergence: Double?, zNear: Double? = nil, surround: Bool = true, options: ThreeDExperimentOptions = .live, out: URL, cancelled: () -> Bool = { false }) throws -> URL {
        // Encode privately. Never unlink a currently playing last-good file.
        let destination=out
        let out=out.deletingLastPathComponent().appendingPathComponent(".render-"+UUID().uuidString+".mp4")
        defer {try? FileManager.default.removeItem(at:out)}
        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first, let sr = try? AVAssetReader(asset: asset),
              let dr = DepthFrameReader(url: depth, device: device) else { throw Failure.open }
        let so = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                                       kCVPixelBufferMetalCompatibilityKey as String: true])
        guard sr.canAdd(so) else { throw Failure.open }
        sr.add(so)
        guard sr.startReading() else { throw Failure.open }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else { throw Failure.open }

        let n = plan.eyeN, w2 = plan.canvas.w, h2 = plan.canvas.h, flat = plan.output.isFlat
        guard let sbs = Stereo3DRenderer.texture(device, .rgba8Unorm, w2, h2),
              let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { throw Failure.open }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: plan.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264, AVVideoWidthKey: w2, AVVideoHeightKey: h2,
            // review: with no compression properties AVAssetWriter picks its own (low) default bitrate for a 2x-wide canvas; same quality key the prepare encoder (VTShotEncoder) uses. UNCOMPILED on a Mac; real bitrate unmeasured.
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.9]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w2, kCVPixelBufferHeightKey as String: h2])
        guard writer.canAdd(input) else { throw Failure.open }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.write }
        writer.startSession(atSourceTime: .zero)
        guard let up = DepthUpsampler(device: device, queue: renderer.queue) else { throw Failure.open }
        var started = false, completedFrames = 0
        let totalFrames = max(1, Int((asset.duration.seconds * Double(track.nominalFrameRate)).rounded()))
        ThreeDStageLog.progress("stereo-synthesis-" + plan.output.rawValue, done: 0, total: totalFrames)
        func fail(_ f: Failure) -> Failure { sr.cancelReading(); dr.cancel(); writer.cancelWriting(); try? FileManager.default.removeItem(at: out); return f }

        while let sb = so.copyNextSampleBuffer() {
            if cancelled() { throw fail(.write) }
            guard let sp = CMSampleBufferGetImageBuffer(sb), let df = dr.next(), df.rangeOK else { throw fail(.depth) }
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            if abs(df.pts - CMTimeGetSeconds(pts)) > 0.5 / 24.0 { throw fail(.pairing) }   // half a frame at 24 fps; tighter than any cut
            let dw = depthSize?.w ?? df.width, dh = depthSize?.h ?? df.height
            let fw = sourceSize?.w ?? CVPixelBufferGetWidth(sp), fh = sourceSize?.h ?? CVPixelBufferGetHeight(sp)
            // the depth box (sidecar depth_width x depth_height, the letterbox box the native prepare stores) may be smaller than the source picture: same aspect, resampled up below
            guard DepthUpsampleKernel.compatible(depth: (dw, dh), source: (fw, fh)), dw <= df.width, dh <= df.height, fw <= CVPixelBufferGetWidth(sp), fh <= CVPixelBufferGetHeight(sp) else { throw fail(.size) }
            var ft: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, sp, nil, .bgra8Unorm, CVPixelBufferGetWidth(sp), CVPixelBufferGetHeight(sp), 0, &ft) == kCVReturnSuccess,
                  let padded = ft.flatMap({ CVMetalTextureGetTexture($0) }),
                  let ftex = Stereo3DRenderer.texture(device, .bgra8Unorm, fw, fh),
                  let full = Stereo3DRenderer.texture(device, .r32Float, df.width, df.height),
                  let box = Stereo3DRenderer.texture(device, .r32Float, dw, dh),
                  let metric = (dw == fw && dh == fh) ? box : Stereo3DRenderer.texture(device, .r32Float, fw, fh),
                  dr.decode(df, into: full, renderer: renderer) else { throw fail(.depth) }
            guard crop(full, to: box), (dw == fw && dh == fh) || up.resample(box, into: metric), withExtendedLifetime(ft, { crop(padded, to: ftex) }), renderer.render(frame: ftex, depth: metric, thetaH: thetaH, ipd: plan.ipd(effective: ipd), convergence: convergence, zNear: zNear, swapEyes: plan.swapEyes, surround: surround, outW: flat ? fw : n, outH: flat ? fh : n, sbsOut: sbs, output: plan.output, options: options) else { throw fail(.render) }   // options: one snapshot for the whole shot (review r4)
            while !input.isReadyForMoreMediaData {                                  // review: a failed/cancelled writer never becomes ready again: bail out instead of spinning forever
                if cancelled() || writer.status != .writing { throw fail(.write) }
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let pool = adaptor.pixelBufferPool else { throw fail(.write) }
            var pb: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let out_pb = pb, copy(sbs, into: out_pb) else { throw fail(.write) }
            if !started { writer.startSession(atSourceTime: pts); started = true }   // film time, not zero based
            guard adaptor.append(out_pb, withPresentationTime: pts) else { throw fail(.write) }
            completedFrames += 1; ThreeDStageLog.progress("stereo-synthesis-" + plan.output.rawValue, done: completedFrames, total: totalFrames)
        }
        guard sr.status == .completed else { throw fail(.open) }                       // review: copyNextSampleBuffer == nil is also what a FAILED reader returns; only .completed is a full read
        input.markAsFinished()
        let g = DispatchGroup(); g.enter(); writer.finishWriting { g.leave() }
        while g.wait(timeout:.now()+0.1) == .timedOut {if cancelled() {throw fail(.write)}}
        guard writer.status == .completed else { throw fail(.write) }
        SphericalTag.apply(to: out, plan: plan)          // s36: vr180 container tag, flag gor.3d.sphericalTag (default OFF); any failure leaves the untagged file
        guard !cancelled() else {throw fail(.write)}
        // Same-directory rename exposes only a complete encoded file. An existing
        // key-bearing destination stays intact rather than being overwritten.
        try FileManager.default.moveItem(at:out,to:destination)
        return destination
    }

    /// Top-left crop of a padded picture to the sidecar size (blit, no resampling).
    private func crop(_ src: MTLTexture, to dst: MTLTexture) -> Bool {
        guard src.width >= dst.width, src.height >= dst.height, let cb = renderer.queue.makeCommandBuffer(), let b = cb.makeBlitCommandEncoder() else { return false }
        b.copy(from: src, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: dst.width, height: dst.height, depth: 1),
               to: dst, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        b.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return cb.status == .completed
    }

    /// rgba8 SBS texture -> BGRA pixel buffer (CPU swizzle: slow, correct; a GPU view is a later optimisation).
    private func copy(_ tex: MTLTexture, into pb: CVPixelBuffer) -> Bool {
        let w = tex.width, h = tex.height
        guard let staging = device.makeBuffer(length: w * h * 4, options: .storageModeShared), let cb = renderer.queue.makeCommandBuffer(), let b = cb.makeBlitCommandEncoder() else { return false }
        b.copy(from: tex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1),
               to: staging, destinationOffset: 0, destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
        b.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        guard cb.status == .completed else { return false }
        CVPixelBufferLockBaseAddress(pb, []); defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let bpr = CVPixelBufferGetBytesPerRow(pb), src = staging.contents().assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            let s = src + y * w * 4, d = base.assumingMemoryBound(to: UInt8.self) + y * bpr
            for x in 0..<w { d[x * 4] = s[x * 4 + 2]; d[x * 4 + 1] = s[x * 4 + 1]; d[x * 4 + 2] = s[x * 4]; d[x * 4 + 3] = s[x * 4 + 3] }
        }
        return true
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VideoToolbox)
import AVFoundation
import CoreVideo
import VideoToolbox
#endif

/// 190t A: in-app HEVC Main 10 writer for source_shot_NNNNN.mp4 (CONTRACT-190v s9 source proxy), replacing the libx265 ffmpeg of the Linux/reference
/// path. SOURCE PROXY ONLY: the depth cache moves to a lossless per-shot container (parent decision 07:35), so there is deliberately no depth encoder here. Pure rules first (fps as an exact rational, even padding, the 10-bit word packing, the hvcC profile
/// read) so they have Python models; the AVAssetWriter part is below and has NOT been compiled or run on a Mac.
/// The proxy is lossy by design (x265 crf 10 in the reference); VT runs at maximum quality. Not measured against the reference on a Mac.
enum ShotEncoding {
    static func evenSize(_ w: Int, _ h: Int) -> (w: Int, h: Int) { (w + (w & 1), h + (h & 1)) }

    /// fps as an exact rational so frame * den / num == frame / fps with no drift (23.976 = 24000/1001, ...); other rates to 0.001.
    static func fpsRational(_ fps: Double) -> (num: Int32, den: Int32)? {
        guard fps.isFinite, fps > 0, fps <= 1000 else { return nil }
        for (n, d) in [(24000, 1001), (30000, 1001), (48000, 1001), (60000, 1001), (120000, 1001)] where abs(fps - Double(n) / Double(d)) < 0.002 { return (Int32(n), Int32(d)) }
        let r = fps.rounded()
        if abs(fps - r) < 0.002 { return (Int32(r), 1) }
        return (Int32((fps * 1000).rounded()), 1000)
    }
    /// Container PTS of film frame `frame` as CMTime(value, timescale): frame * den / num seconds.
    static func pts(frame: Int, fps: (num: Int32, den: Int32)) -> (value: Int64, scale: Int32) { (Int64(frame) * Int64(fps.den), fps.num) }

    /// 10-bit sample in a 16-bit word, MSB-aligned (shift 6): what the 10-bit biplanar formats store. Neutral chroma 512 -> 0x8000.
    static func word(_ v10: UInt16) -> UInt16 { min(v10, 1023) << 6 }
    static let neutralChromaWord: UInt16 = 512 << 6
    /// Black bottom-right padding of the source proxy: video range luma 64, full range 0 (10-bit).
    static func blackLumaWord(fullRange: Bool) -> UInt16 { fullRange ? 0 : 64 << 6 }
    /// Edge replication index for depth padding (same as prepare_film._pad_even).
    static func clampIndex(_ i: Int, _ n: Int) -> Int { min(i, n - 1) }

    /// hvcC general_profile_idc (byte 1, low 5 bits): 2 = Main 10.
    static func hvccIsMain10(_ hvcc: [UInt8]) -> Bool { hvcc.count > 1 && (hvcc[1] & 0x1F) == 2 }
}

#if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VideoToolbox)
final class VTShotEncoder {
    private let writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let tmp: URL, dest: URL, fullRange: Bool
    private let fps: (num: Int32, den: Int32), startFrame: Int
    let width: Int, height: Int, padded: (w: Int, h: Int)
    private var written = 0, failed = false

    /// `width`/`height` = the unpadded picture size (also what the sidecar json records). `colorProperties` = the source's own AVVideoColorProperties
    /// dictionary (nil = untagged proxy: no forcing, a forced bt709 tag shifts colours on SD/untagged sources).
    init?(url: URL, width: Int, height: Int, fps: Double, startFrame: Int, sourceFullRange: Bool = false, colorProperties: [String: String]? = nil) {
        guard width > 0, height > 0, let r = ShotEncoding.fpsRational(fps) else { return nil }
        let e = ShotEncoding.evenSize(width, height)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        guard let w = try? AVAssetWriter(outputURL: tmp, fileType: .mp4) else { return nil }
        let comp: [String: Any] = [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String, AVVideoQualityKey: 1.0,
                                   AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: fps]
        var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: e.w, AVVideoHeightKey: e.h, AVVideoCompressionPropertiesKey: comp]
        if let c = colorProperties { settings[AVVideoColorPropertiesKey] = c }
        let fr = sourceFullRange
        let fmt = fr ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        inp.expectsMediaDataInRealTime = false
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: fmt, kCVPixelBufferWidthKey as String: e.w, kCVPixelBufferHeightKey as String: e.h])
        guard w.canAdd(inp) else { return nil }
        w.add(inp); w.shouldOptimizeForNetworkUse = true
        let t0 = ShotEncoding.pts(frame: startFrame, fps: r)
        guard w.startWriting() else { return nil }
        w.startSession(atSourceTime: CMTime(value: t0.value, timescale: t0.scale))
        writer = w; input = inp; adaptor = ad; self.tmp = tmp; dest = url; fullRange = fr; self.fps = r; self.startFrame = startFrame
        self.width = width; self.height = height; padded = e
    }

    private func pixelBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess else { return nil }
        return pb
    }
    private func submit(_ pb: CVPixelBuffer, cancelled: () -> Bool) -> Bool {
        var waited = 0.0
        while !input.isReadyForMoreMediaData {
            if cancelled() || failed || writer.status == .failed || waited > 60 { failed = true; return false }
            Thread.sleep(forTimeInterval: 0.002); waited += 0.002
        }
        let t = ShotEncoding.pts(frame: startFrame + written, fps: fps)
        guard adaptor.append(pb, withPresentationTime: CMTime(value: t.value, timescale: t.scale)) else { failed = true; return false }
        written += 1; return true
    }

    /// Source proxy: `buffer` = a 10-bit 4:2:0 biplanar picture of the unpadded size (same range as `sourceFullRange`). Padded black bottom-right.
    func appendSource(_ buffer: CVPixelBuffer, cancelled: () -> Bool = { false }) -> Bool {
        guard !failed, CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              CVPixelBufferGetPixelFormatType(buffer) == (fullRange ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
              let pb = pixelBuffer() else { failed = true; return false }
        CVPixelBufferLockBaseAddress(buffer, .readOnly); CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []); CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        for plane in 0..<2 {
            guard let s = CVPixelBufferGetBaseAddressOfPlane(buffer, plane), let d = CVPixelBufferGetBaseAddressOfPlane(pb, plane) else { failed = true; return false }
            let ss = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane), ds = CVPixelBufferGetBytesPerRowOfPlane(pb, plane)
            let rows = plane == 0 ? padded.h : padded.h / 2, srcRows = plane == 0 ? height : height / 2 + (height & 1)
            let words = plane == 0 ? padded.w : padded.w, srcWords = plane == 0 ? width : (width + (width & 1))
            let fill = plane == 0 ? ShotEncoding.blackLumaWord(fullRange: fullRange) : ShotEncoding.neutralChromaWord
            for j in 0..<rows {
                let dr = d.advanced(by: j * ds).assumingMemoryBound(to: UInt16.self)
                if j < srcRows {
                    let sr = s.advanced(by: j * ss).assumingMemoryBound(to: UInt16.self)
                    for i in 0..<words { dr[i] = i < srcWords ? sr[i] : fill }
                } else { for i in 0..<words { dr[i] = fill } }
            }
        }
        return submit(pb, cancelled: cancelled)
    }

    /// Finishes, moves the file into place and checks the CONTRACT s9 properties. Returns nil when the file is good, else the reason (file removed).
    func finish() -> String? {
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        guard !failed, writer.status == .completed, written > 0 else { try? FileManager.default.removeItem(at: tmp); return "encoder failed (\(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"))" }
        do { try? FileManager.default.removeItem(at: dest); try FileManager.default.moveItem(at: tmp, to: dest) } catch { return "could not move the file into place" }
        if let why = Self.verify(url: dest, expectedSize: padded, expectedStart: Double(startFrame) / (Double(fps.num) / Double(fps.den)), frames: written) {
            try? FileManager.default.removeItem(at: dest); return why
        }
        return nil
    }
    func cancel() { writer.cancelWriting(); try? FileManager.default.removeItem(at: tmp); failed = true }

    /// Reads the file back: HEVC, Main 10 (hvcC), padded size, first PTS = start/fps. nil = good. Unverified on a Mac.
    static func verify(url: URL, expectedSize: (w: Int, h: Int), expectedStart: Double, frames: Int) -> String? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first, let fd = track.formatDescriptions.first else { return "no video track" }
        let f = fd as! CMFormatDescription
        guard CMFormatDescriptionGetMediaSubType(f) == kCMVideoCodecType_HEVC else { return "not HEVC" }
        let dim = CMVideoFormatDescriptionGetDimensions(f)
        guard Int(dim.width) == expectedSize.w, Int(dim.height) == expectedSize.h else { return "size \(dim.width)x\(dim.height) != \(expectedSize.w)x\(expectedSize.h)" }
        let ext = CMFormatDescriptionGetExtensions(f) as? [String: Any] ?? [:]
        if let atoms = ext[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any], let hv = atoms["hvcC"] as? Data {
            guard ShotEncoding.hvccIsMain10([UInt8](hv)) else { return "not HEVC Main 10" }
        } else { return "no hvcC" }
        guard let r = try? AVAssetReader(asset: asset) else { return "cannot read back" }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard r.canAdd(out) else { return "cannot read back" }
        r.add(out)
        guard r.startReading(), let sb = out.copyNextSampleBuffer() else { return "no first sample" }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
        return abs(t - expectedStart) < 0.0005 ? nil : "first PTS \(t) != \(expectedStart)"
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// P26: gor's prepared-shot path, separate from RenderedShotMPV. The backend
/// implements these operations on its ONE multi-source session. No IPC/MPV
/// command string, timestamp rebase, or implicit restart of source audio.
@MainActor
protocol PreparedShotSessionBackend: AnyObject {
    /// Return only after the operation is committed. On failure the backend must
    /// stop the incomplete operation or mark its session unusable, never silently
    /// fall back to another engine. Gor will invalidate its local receipt state.
    func applyPreparedShot(_ request: PreparedShotPlayback.Request) async throws
        -> PreparedShotPlayback.Receipt
}

@MainActor
final class PreparedShotPlayback {
    enum Failure: Error, Equatable {
        case invalidFilmTime
        case notLocalFile
        case noSourceSession
        case sourceAudioChanged
        case operationInFlight
        case sessionInvalidated
        case receiptMismatch
    }

    enum Operation: Equatable {
        /// Adopt an already-running source video/audio pair, then swap video.
        /// Never starts or restarts audio. Idle/separate initial audio refuses.
        case adoptRunningSource
        /// Keep the running audio decoder/device/clock. Replace video only.
        case replaceVideo
        /// Return to source film video, preserving that same source audio.
        case returnToSource
    }

    struct Request: Equatable {
        let sessionID: UUID
        let operationID: UUID
        let operation: Operation
        let videoURL: URL
        let sourceAudioURL: URL
        /// Absolute source-film time. NEVER clip-relative time.
        let filmTime: Double
        /// Always false: rendered files already carry source-film timestamps.
        let rebaseStartTime: Bool
        /// true for every replacement, including return to source video.
        let preserveRunningAudio: Bool
    }

    /// This is a backend commit receipt, not an intended-state echo produced by
    /// the coordinator. R4's implementation must populate it from committed state.
    struct Receipt: Equatable {
        let sessionID: UUID
        let operationID: UUID
        let videoURL: URL
        let sourceAudioURL: URL
        let requestedFilmTime: Double
        let committedFilmTime: Double
        let rebased: Bool
        let preservedRunningAudio: Bool
    }

    private let backend: any PreparedShotSessionBackend
    private(set) var current: Receipt?
    private(set) var invalidated = false
    private var inFlight = false

    init(backend: any PreparedShotSessionBackend) {
        self.backend = backend
    }

    /// loadfile render, replace, start=<film time>, no rebase, audio-file=source
    /// semantics, without serializing that MPV command or changing its old path.
    @discardableResult
    func loadPreparedShot(render: URL, source: URL, start: Double) async throws -> Receipt {
        try validate(render, source, start)
        let operation: Operation
        let sessionID: UUID
        if let previous = current {
            guard previous.sourceAudioURL == source else { throw Failure.sourceAudioChanged }
            operation = .replaceVideo
            sessionID = previous.sessionID
        } else {
            operation = .adoptRunningSource
            sessionID = UUID()
        }
        return try await commit(Request(sessionID: sessionID, operationID: UUID(),
            operation: operation, videoURL: render, sourceAudioURL: source,
            filmTime: start, rebaseStartTime: false,
            preserveRunningAudio: true))
    }

    /// Switch back to 2D source video at film time without restarting audio.
    /// A different source must start a separate normal media-load lifecycle.
    @discardableResult
    func loadSource2D(file: URL, start: Double) async throws -> Receipt {
        try validate(file, file, start)
        guard let previous = current else { throw Failure.noSourceSession }
        guard previous.sourceAudioURL == file else { throw Failure.sourceAudioChanged }
        return try await commit(Request(sessionID: previous.sessionID, operationID: UUID(),
            operation: .returnToSource, videoURL: file, sourceAudioURL: file,
            filmTime: start, rebaseStartTime: false, preserveRunningAudio: true))
    }

    private func validate(_ video: URL, _ audio: URL, _ time: Double) throws {
        guard !invalidated else { throw Failure.sessionInvalidated }
        guard !inFlight else { throw Failure.operationInFlight }
        guard time.isFinite, time >= 0 else { throw Failure.invalidFilmTime }
        guard video.isFileURL, audio.isFileURL,
              video.path.hasPrefix("/"), audio.path.hasPrefix("/") else {
            throw Failure.notLocalFile
        }
    }

    private func commit(_ request: Request) async throws -> Receipt {
        inFlight = true
        defer { inFlight = false }
        do {
            try Task.checkCancellation()
            let receipt = try await backend.applyPreparedShot(request)
            try Task.checkCancellation()
            guard receipt.sessionID == request.sessionID,
                  receipt.operationID == request.operationID,
                  receipt.videoURL == request.videoURL,
                  receipt.sourceAudioURL == request.sourceAudioURL,
                  receipt.committedFilmTime.isFinite,
                  receipt.committedFilmTime >= 0,
                  receipt.requestedFilmTime == request.filmTime,
                  !receipt.rebased,
                  receipt.preservedRunningAudio == request.preserveRunningAudio else {
                throw Failure.receiptMismatch
            }
            current = receipt
            return receipt
        } catch {
            // The backend might have partially changed state. Do not issue a new
            // open over a still-running audio session or reuse the old receipt.
            current = nil
            invalidated = true
            throw error
        }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t E-G side of CONTRACT-190v section 4: reads <cache_root>/render-prefs.json (written only by RenderPrefs.write in FilmPrepareStatus.swift).
/// Absent, unreadable or invalid file = contract defaults (mode off). Re-read only when the file's mtime changes. Never writes.
struct RenderPrefsValue: Equatable {
    var mode = "off"
    var depthScale = 1.0
    var ipdM = 0.063
    var convergenceM: Double? = nil
    /// Virtual screen: horizontal angular width (deg) the film occupies on the VR180 canvas. Optional key "screen_deg"; absent/invalid = default.
    /// 0 = legacy "shot FoV" (the picture is only as wide as the camera FoV, a few percent of 180 deg: faithful but a postage stamp).
    var screenDeg = RenderPrefsValue.defaultScreenDeg
    /// Optional key "surround": "soft" (default, edge-extended blurred fill of the canvas outside the film) or "off" (black). Part of the render key.
    var surroundSoft = true
    /// CONTRACT-190v s25 comfort policy (ShotComfort): per-shot convergence = shot median depth, baseline shrunk so infinity stays inside the 1 deg divergence budget, near clamp at 2 deg crossed.
    /// Default on; explicit convergence_m or depth_scale in the prefs file wins. Optional key "comfort": "off" restores the fixed-parameter renderer. Part of the render key.
    var comfort = true
    /// Optional key "over_budget": true = the user explicitly picked a strength above 100% (labelled over comfort budget in the menu); otherwise strength is capped to 1 on top of comfort.
    var overBudget = false
    static let defaultScreenDeg = 75.0, minScreenDeg = 20.0, maxScreenDeg = 150.0, maxVerticalDeg = 150.0
    /// thetaH to pass to Stereo3DRenderer.render: screen width from prefs, aspect-preserving (same f for x and y), vertical capped so the screen stays inside the canvas.
    /// Depth is NOT rescaled: disparity at depth Z stays atan(eye/Z) from the real metric depth; only the angular size of the picture changes.
    func thetaH(shotThetaH: Double, aspect: Double) -> Double {
        if screenDeg <= 0 || !(aspect > 0) { return shotThetaH }
        let h = min(max(screenDeg, RenderPrefsValue.minScreenDeg), RenderPrefsValue.maxScreenDeg) * Double.pi / 180.0
        let vMax = RenderPrefsValue.maxVerticalDeg * Double.pi / 180.0
        let hCap = 2.0 * atan(tan(vMax / 2.0) * aspect)
        return min(h, hCap)
    }
    /// Eye offset the renderer takes as `ipd`: depth_scale multiplies disparity, and disparity is linear in the eye offset.
    /// True when the comfort policy sets convergence, baseline and near clamp per shot. Only an explicit convergence_m turns it off; depth_scale (menu strength) scales on top of it.
    var comfortActive: Bool { comfort && convergenceM == nil }
    /// Eye offset under the comfort policy: ipd_m * (B_eff / IPD of the shot) * strength factor (capped to 1 unless over_budget).
    func comfortIPD(_ c: ShotComfort) -> Double { ipdM * c.depthScale * ShotComfort.strengthFactor(depthScale, overBudget: overBudget) }
    /// Strength multiplies the shot span GAIN. The hard near clamp follows the final baseline, including explicit over-budget strength.
    func comfortZNear(_ c: ShotComfort) -> Double { ShotComfort.nearClamp(zc: c.convergenceM, ipd: comfortIPD(c)) }
    var effectiveIPD: Double { ipdM * depthScale }
    static func parse(_ data: Data?) -> RenderPrefsValue {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return RenderPrefsValue() }
        var v = RenderPrefsValue()
        if let m = o["mode"] as? String, RenderPrefs.modes.contains(m) { v.mode = m } else { return RenderPrefsValue() }
        if let s = (o["depth_scale"] as? NSNumber)?.doubleValue, s.isFinite, s >= 0 { v.depthScale = s }
        if let i = (o["ipd_m"] as? NSNumber)?.doubleValue, i.isFinite, i > 0 { v.ipdM = i }
        if let c = (o["convergence_m"] as? NSNumber)?.doubleValue, c.isFinite, c > 0 { v.convergenceM = c }
        if let ob = o["over_budget"] as? Bool { v.overBudget = ob }
        if let cv = o["comfort"] as? String, cv == "off" || cv == "on" { v.comfort = cv == "on" }
        if let sv = o["surround"] as? String, sv == "off" || sv == "soft" { v.surroundSoft = sv == "soft" }
        if let d = (o["screen_deg"] as? NSNumber)?.doubleValue, d.isFinite, d == 0 || (d >= minScreenDeg && d <= maxScreenDeg) { v.screenDeg = d }
        return v
    }
}

final class RenderPrefsReader {
    private let url: URL
    private var mtime: Date?
    private(set) var value = RenderPrefsValue()
    init(root: URL = DepthCachePaths.root) { url = root.appendingPathComponent("render-prefs.json") }
    /// Call per open/play. Returns the current value; cheap when unchanged.
    @discardableResult
    func refresh() -> RenderPrefsValue {
        let m = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if m != mtime || m == nil { mtime = m; value = m == nil ? RenderPrefsValue() : RenderPrefsValue.parse(try? Data(contentsOf: url)) }
        return value
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// A render job owns an immutable generation. Returning to an earlier parameter
/// value never makes a cancelled job current again. All cross-queue reads lock.
final class RenderRevision {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var identity: String?
    private var settleAt = 0.0
    static let debounceSeconds = 0.5 // [attribution comment elided]

    @discardableResult
    func update(_ value: String, now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value != identity else { return false }
        identity=value; generation &+= 1; settleAt=now+Self.debounceSeconds
        return true
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; identity=nil
    }
    var token: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return generation==token
    }
    func ready(now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }; return identity != nil && now>=settleAt
    }
    /// A stale encode cannot publish its sidecar after a preference/source change.
    func commit(_ token: UInt64, _ body: () throws -> Void) rethrows -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation==token else { return false }
        try body(); return true
    }
    static func fileName(shot: Int, key: String) -> String {
        var hash=SHA256Pure.Hasher();hash.update(key)
        return String(format:"render_shot_%05d_",shot)+hash.hex()+".mp4"
    }
}

/// Keep the last-good encoded shot while a replacement is pending. A ready new
/// URL must replace the same shot too, so experiment changes become visible.
enum RenderContinuity {
    static func shouldLoad(showing: Int?, next: Int, seeked: Bool, showingURL: URL? = nil, candidateURL: URL? = nil) -> Bool {
        showing != next || seeked || (candidateURL != nil && showingURL != candidateURL)
    }
    static func holds(showing: Int?, next: Int, fileExists: Bool) -> Bool {
        showing==next && fileExists
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(Metal)
import Metal

/// 190t E/F/G: VR180 / SBS eye render on the GPU. Mirrors tools/vr180_render_ref.py op for op (Tests/Stereo3DKernel keeps a Python model of
/// every kernel below). 3D-mode only: nothing in flat playback creates or calls this. The Metal source is compiled at runtime with fast-math
/// off, so a compile or device failure returns nil from `make()` and the caller stays on the 2D path; it cannot break the app build.
enum Stereo3DKernelSource {
    static let text = """
    #include <metal_stdlib>
    using namespace metal;
    struct S3DParams { float f; float eye; uint w; uint h; uint ow; uint oh; float conv; float znear; uint mode; float fout; };   // s36: mode 0 = equirect180 (vr180), 1 = perspective (flat modes, fout = pixels per tan across the eye canvas)
    constant uint S3D_INF = 0x7F800000u;
    static bool s3d_map(uint2 g, constant S3DParams& p, float z, thread int2& o) {
        float rx = ((float)g.x + 0.5f - (float)p.w * 0.5f) / p.f;
        float ry = ((float)p.h * 0.5f - ((float)g.y + 0.5f)) / p.f;
        float px = rx * z - p.eye, py = ry * z, pz = z;
        if (p.mode == 1u) {          // parallel-shift convergence: no toe-in keystone or vertical parallax
            if (!(z > 0.0f)) return false;
            float uu = px / pz + tan(p.conv), vv = py / pz;
            o = int2((int)floor(uu * p.fout + (float)p.ow * 0.5f), (int)floor((float)p.oh * 0.5f - vv * p.fout));
            return o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;
        }
        float n = sqrt(px * px + py * py + pz * pz);
        float lon = atan2(px, pz) + p.conv, lat = asin(py / n);
        float u = lon / M_PI_F + 0.5f, v = 0.5f - lat / M_PI_F;
        o = int2((int)floor(u * (float)p.ow), (int)floor(v * (float)p.oh));
        return z > 0.0f && o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;
    }
    kernel void s3d_clear(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                          texture2d<float, access::write> rendered [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        atomic_store_explicit(&zb[gid.y * p.ow + gid.x], S3D_INF, memory_order_relaxed);
        rendered.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
    }
    kernel void s3d_zmin(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                         texture2d<float, access::read> depth [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear); int2 o;
        if (!s3d_map(gid, p, z, o)) return;
        atomic_fetch_min_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], as_type<uint>(z), memory_order_relaxed);
    }
    kernel void s3d_resolve(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                            texture2d<float, access::read> frame [[texture(0)]], texture2d<float, access::read> depth [[texture(1)]],
                            texture2d<float, access::write> rendered [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear); int2 o;
        if (!s3d_map(gid, p, z, o)) return;
        if (atomic_load_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], memory_order_relaxed) != as_type<uint>(z)) return;
        rendered.write(float4(frame.read(gid).rgb, 1.0f), uint2(o));
    }
    // F1 integer-exact blend and far-column average; r2 edge-run fill stays inside the frustum.
    constant uint SHORT_RUN_K = 16u, VERT_HALF = 16u;
    static uint4 s3d_codes(float4 c) { return uint4(floor(clamp(c, 0.0f, 1.0f) * 255.0f + 0.5f)); }
    static uint4 s3d_round(uint4 num, uint den) { return (2u * num + den) / (2u * den); }
    static float4 s3d_vavg(device const uint* zb, constant S3DParams& p, texture2d<float, access::read> rendered, uint row, uint col) {
        uint lo = row > VERT_HALF ? row - VERT_HALF : 0u, hi = min(p.oh - 1u, row + VERT_HALF);
        uint4 sum = uint4(0u); uint n = 0u;
        for (uint r = lo; r <= hi; r++) if (zb[r * p.ow + col] != S3D_INF) { sum += s3d_codes(rendered.read(uint2(col, r))); n++; }
        return n > 0u ? float4(s3d_round(sum, n)) / 255.0f : rendered.read(uint2(col, row));
    }
    kernel void s3d_fill(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]],
                         texture2d<float, access::read> rendered [[texture(0)]], texture2d<float, access::write> result [[texture(1)]],
                         uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c0 = 0; c0 < p.ow; c0++) result.write(float4(0.0f), uint2(c0, row));
        int a = -1, first = -1;
        for (uint c = 0; c < p.ow; c++) {
            uint zc = zb[row * p.ow + c];
            if (zc == S3D_INF) continue;
            if (a >= 0 && (int)c - a > 1) {
                uint g = c - (uint)a - 1u;
                if (g <= SHORT_RUN_K) {
                    uint4 A = s3d_codes(rendered.read(uint2((uint)a, row))), B = s3d_codes(rendered.read(uint2(c, row)));
                    for (uint k = 1u; k <= g; k++) result.write(float4(s3d_round(A * (g + 1u - k) + B * k, g + 1u)) / 255.0f, uint2((uint)a + k, row));
                } else {
                    uint za = zb[row * p.ow + (uint)a];
                    uint src = (as_type<float>(za) >= as_type<float>(zc)) ? (uint)a : c;
                    float4 col = s3d_vavg(zb, p, rendered, row, src);
                    for (uint k = (uint)a + 1u; k < c; k++) result.write(col, uint2(k, row));
                }
            }
            result.write(rendered.read(uint2(c, row)), uint2(c, row));
            if (first < 0) first = (int)c;
            a = (int)c;
        }
        if (a < 0) return;
        int lo = -1, hi = -1;
        for (uint c = 0; c < p.ow; c++) if (fp[row * p.ow + c] != 0) { if (lo < 0) lo = (int)c; hi = (int)c; }
        if (lo < 0) return;
        if (first > lo) {
            float4 col = (uint)(first - lo) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)first) : rendered.read(uint2((uint)first, row));
            for (int k = lo; k < first; k++) result.write(col, uint2((uint)k, row));
        }
        if (a < hi) {
            float4 col = (uint)(hi - a) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)a) : rendered.read(uint2((uint)a, row));
            for (int k = a + 1; k <= hi; k++) result.write(col, uint2((uint)k, row));
        }
    }
    // 195h E: dynamic floating window (doi 10.1117/1.jei.21.1.011009). Content nearer than the convergence (screen) distance that the OUTER canvas
    // edge cuts is a window violation; mask the violated outer strip per row with a one-column feather. Deterministic, per row like s3d_fill; conv 0
    // (no screen distance) = plain copy. Outer edge = the side the eye is shifted toward (left eye: x=0, right eye: x=ow-1).
    kernel void s3d_floatwin(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                             texture2d<float, access::read> result [[texture(0)]], texture2d<float, access::write> outTex [[texture(1)]],
                             uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c = 0; c < p.ow; c++) outTex.write(result.read(uint2(c, row)), uint2(c, row));
        float tc = tan(fabs(p.conv));
        if (!(tc > 1e-6f)) return;
        float zs = fabs(p.eye) / tc;                                 // screen (convergence) distance, metres
        uint maxrun = p.ow / 8u, ext = 0u;                           // furthest violated column from the outer edge (capped)
        for (uint c = 0; c < maxrun; c++) {
            uint x = p.eye < 0.0f ? c : p.ow - 1u - c;
            uint z = zb[row * p.ow + x];
            if (z != S3D_INF && as_type<float>(z) < zs) ext = c + 1u;
        }
        for (uint c = 0; c < ext; c++) {
            uint x = p.eye < 0.0f ? c : p.ow - 1u - c;
            float w = (c + 1u == ext) ? 0.5f : 0.0f;                 // feather column at the crop boundary
            outTex.write(float4(result.read(uint2(x, row)).rgb * w, 1.0f), uint2(x, row));
        }
    }
    // 195h G: depth-guided defocus (Held & Banks 2012: blur + disparity as the realism cue). Per-source-pixel disc blur with radius following the
    // circle of confusion |1/z - 1/zf| about the convergence (focus) plane; conv 0 (no screen distance) = plain copy. Deterministic 12-tap disc.
    kernel void s3d_dof(texture2d<float, access::read> frame [[texture(0)]], texture2d<float, access::read> depth [[texture(1)]],
                        texture2d<float, access::write> blurred [[texture(2)]], constant S3DParams& p [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float tc = tan(fabs(p.conv));
        if (!(tc > 1e-6f)) { blurred.write(frame.read(gid), gid); return; }
        float zf = fabs(p.eye) / tc;                                 // focus plane = the convergence distance, metres
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear);
        float r = (z > 0.0f) ? clamp(28.0f * fabs(1.0f / z - 1.0f / zf), 0.0f, 12.0f) : 0.0f;
        if (r < 0.5f) { blurred.write(frame.read(gid), gid); return; }
        const float2 taps[12] = { float2(1.0f, 0.0f), float2(-1.0f, 0.0f), float2(0.0f, 1.0f), float2(0.0f, -1.0f),
                                  float2(0.7071f, 0.7071f), float2(-0.7071f, 0.7071f), float2(0.7071f, -0.7071f), float2(-0.7071f, -0.7071f),
                                  float2(0.5f, 0.866f), float2(-0.5f, 0.866f), float2(0.5f, -0.866f), float2(-0.5f, -0.866f) };
        float3 sum = frame.read(gid).rgb; float n = 1.0f;
        for (uint k = 0; k < 12; k++) {
            int2 t = clamp(int2(gid) + int2((int)round(taps[k].x * r), (int)round(taps[k].y * r)), int2(0, 0), int2((int)p.w - 1, (int)p.h - 1));
            sum += frame.read(uint2(t)).rgb; n += 1.0f;
        }
        blurred.write(float4(sum / n, 1.0f), gid);
    }
    // 195h: deterministic depth-guided gradient hole fill, a drop-in variant of s3d_fill behind Stereo3DExperiments.holeFillGradient.
    // Short gaps, edge runs and valid pixels are byte-identical to s3d_fill; long disocclusions ramp the near endpoint's colour into the far
    // (background) vertical average over 32 px from the near side and then hold the background, instead of s3d_fill's flat vavg wall.
    kernel void s3d_fillgrad(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]],
                         texture2d<float, access::read> rendered [[texture(0)]], texture2d<float, access::write> result [[texture(1)]],
                         uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c0 = 0; c0 < p.ow; c0++) result.write(float4(0.0f), uint2(c0, row));
        int a = -1, first = -1;
        for (uint c = 0; c < p.ow; c++) {
            uint zc = zb[row * p.ow + c];
            if (zc == S3D_INF) continue;
            if (a >= 0 && (int)c - a > 1) {
                uint g = c - (uint)a - 1u;
                if (g <= SHORT_RUN_K) {
                    uint4 A = s3d_codes(rendered.read(uint2((uint)a, row))), B = s3d_codes(rendered.read(uint2(c, row)));
                    for (uint k = 1u; k <= g; k++) result.write(float4(s3d_round(A * (g + 1u - k) + B * k, g + 1u)) / 255.0f, uint2((uint)a + k, row));
                } else {
                    uint za = zb[row * p.ow + (uint)a];
                    bool nearLeft = as_type<float>(za) < as_type<float>(zc);
                    uint farC = nearLeft ? c : (uint)a, nearC = nearLeft ? (uint)a : c;
                    float4 farCol = s3d_vavg(zb, p, rendered, row, farC), nearCol = s3d_vavg(zb, p, rendered, row, nearC);
                    const uint GRAD_RUN = 32u;
                    for (uint k = 1u; k <= g; k++) {
                        uint d = nearLeft ? k : g + 1u - k;          // px from the near endpoint into the gap
                        if (d >= GRAD_RUN) { result.write(farCol, uint2((uint)a + k, row)); continue; }   // at/past the run: the far colour exactly, as s3d_fill
                        uint4 A = s3d_codes(nearCol), B = s3d_codes(farCol);
                        result.write(float4(s3d_round(A * (GRAD_RUN + 1u - d) + B * d, GRAD_RUN + 1u)) / 255.0f, uint2((uint)a + k, row));
                    }
                }
            }
            result.write(rendered.read(uint2(c, row)), uint2(c, row));
            if (first < 0) first = (int)c;
            a = (int)c;
        }
        if (a < 0) return;
        int lo = -1, hi = -1;
        for (uint c = 0; c < p.ow; c++) if (fp[row * p.ow + c] != 0) { if (lo < 0) lo = (int)c; hi = (int)c; }
        if (lo < 0) return;
        if (first > lo) {
            float4 col = (uint)(first - lo) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)first) : rendered.read(uint2((uint)first, row));
            for (int k = lo; k < first; k++) result.write(col, uint2((uint)k, row));
        }
        if (a < hi) {
            float4 col = (uint)(hi - a) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)a) : rendered.read(uint2((uint)a, row));
            for (int k = a + 1; k <= hi; k++) result.write(col, uint2((uint)k, row));
        }
    }
    kernel void s3d_depth10(texture2d<float, access::read> luma [[texture(0)]], texture2d<float, access::write> metric [[texture(1)]],
                            constant uint& shift [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= metric.get_width() || gid.y >= metric.get_height()) return;
        uint w10 = (uint)round(luma.read(gid).r * 65535.0f) >> shift;
        float v = (float)w10 / 1023.0f * 1024.0f;
        metric.write(float4(w10 == 0u ? 0.0f : 256.0f / v, 0.0f, 0.0f, 0.0f), gid);
    }
    // s3d_surround r4 (CONTRACT-190v s20 + s28/s28b), four kernels. The footprint mask `fp`, the nearest-footprint extension map `src`, the nearest-footprint (L1 BFS)
    // index `near` and the per-pixel weights `wb` = (t1, t2, wcorr, vert) are content independent and come from SurroundGeometry (CPU, exact port of the reference passes).
    // Colour work is here, float32 textures: 32x normalised 3x3 pre-blur over the footprint (np.roll wrap), gather (outside pixels copy their footprint source, then add the
    // r4 boundary correction (true - preblur32) of their nearest footprint pixel x wcorr; footprint pixels keep the TRUE film colour for the blur windows), clamped boxes
    // (16x16, 96x96 and the side-local far trend 256x64 / 64x256, rx x ry) from separable running sums blended by distance (R1 -> R2 over 1..40 px, R2 -> far over 40..120 px,
    // lerp form), one truncation to uint8. Only canvas OUTSIDE the footprint is written.
    // s31 (d): the pre-blur only matters at footprint pixels (non-footprint neighbours are skipped and gather reads `pre` at footprint pixels only), so the 32 passes are
    // dispatched over the footprint bounding box `box` = (x0, y0, w, h) alone. Exact, not an approximation: nothing outside the box is ever read.
    kernel void s3d_sur_pre(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]],
                            constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]], constant uint4& box [[buffer(6)]], constant uint& pass0 [[buffer(7)]], uint2 lid [[thread_position_in_grid]]) {
        if (lid.x >= box.z || lid.y >= box.w) return;
        uint2 gid = uint2(box.x + lid.x, box.y + lid.y);
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        if (fp[gid.y * p.ow + gid.x] == 0) { dst.write(float4(0.0f), gid); return; }
        float4 acc = float4(src.read(gid).rgb, 0.0f); float cnt = 1.0f;
        for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
            if (i == 0 && j == 0) continue;
            uint x = (uint)(((int)gid.x + i + (int)p.ow) % (int)p.ow), y = (uint)(((int)gid.y + j + (int)p.oh) % (int)p.oh);
            if (fp[y * p.ow + x] == 0) { if (pass0 != 0) acc += float4(src.read(uint2(x, y)).rgb, 0.0f); continue; }   // pass 0: the reference adds the rendered value of a non-footprint neighbour to the sum (not the count); later passes read 0 there
            acc += float4(src.read(uint2(x, y)).rgb, 0.0f); cnt += 1.0f;
        }
        dst.write(float4(acc.rgb / max(cnt, 1.0f), 1.0f), gid);
    }
    kernel void s3d_sur_gather(texture2d<float, access::read> pre [[texture(0)]], texture2d<float, access::write> work [[texture(1)]], texture2d<float, access::read> truth [[texture(2)]],
                               constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]], device const int* src [[buffer(3)]], device const float4* wb [[buffer(4)]],
                               device const int* near [[buffer(5)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        uint i = gid.y * p.ow + gid.x;
        if (fp[i] != 0) { work.write(float4(truth.read(gid).rgb, 1.0f), gid); return; }          // r4: blur windows read TRUE film content inside the footprint
        int s = src[i];
        if (s < 0) { work.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid); return; }
        float3 v = pre.read(uint2((uint)s % p.ow, (uint)s / p.ow)).rgb;
        int q = near[i];
        if (q >= 0) { uint2 qg = uint2((uint)q % p.ow, (uint)q / p.ow); v += (truth.read(qg).rgb - pre.read(qg).rgb) * wb[i].z; }   // (true - preblur32) x wcorr, additive
        work.write(float4(v, 1.0f), gid);
    }
    // r4 blur: one pass per axis computes the four clamped boxes with running sums (O(1) per pixel; float32 running-sum drift is far below 1 LSB after the divides). Horizontal radii
    // {16, 96, 256, 64}: one thread per row -> four row-blurred textures. Vertical radii {16, 96, 64, 256} for those rows give the rectangles 16x16, 96x96, 256x64 (wide-short, pixels
    // above/below the footprint) and 64x256 (tall-narrow, left/right). One thread per column, then the lerp-form blend and one truncation.
    kernel void s3d_sur_boxh(texture2d<float, access::read> work [[texture(0)]], texture2d<float, access::write> t1 [[texture(1)]], texture2d<float, access::write> t2 [[texture(2)]],
                             texture2d<float, access::write> t3 [[texture(3)]], texture2d<float, access::write> t4 [[texture(4)]], constant S3DParams& p [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
        if (gid >= p.oh) return;
        const int R[4] = {16, 96, 256, 64}; const float D[4] = {33.0f, 193.0f, 513.0f, 129.0f}; const int n = (int)p.ow; float3 s[4];
        for (int k = 0; k < 4; k++) { s[k] = float3(0.0f); for (int i = -R[k]; i <= R[k]; i++) s[k] += work.read(uint2((uint)clamp(i, 0, n - 1), gid)).rgb; }
        for (int x = 0; x < n; x++) {
            t1.write(float4(s[0] / D[0], 1.0f), uint2((uint)x, gid)); t2.write(float4(s[1] / D[1], 1.0f), uint2((uint)x, gid));
            t3.write(float4(s[2] / D[2], 1.0f), uint2((uint)x, gid)); t4.write(float4(s[3] / D[3], 1.0f), uint2((uint)x, gid));
            for (int k = 0; k < 4; k++) s[k] += work.read(uint2((uint)clamp(x + 1 + R[k], 0, n - 1), gid)).rgb - work.read(uint2((uint)clamp(x - R[k], 0, n - 1), gid)).rgb;
        }
    }
    float3 colRead(texture2d<float, access::read> t1, texture2d<float, access::read> t2, texture2d<float, access::read> t3, texture2d<float, access::read> t4, int k, uint x, int y, int n) {
        uint yy = (uint)clamp(y, 0, n - 1);
        return k == 0 ? t1.read(uint2(x, yy)).rgb : (k == 1 ? t2.read(uint2(x, yy)).rgb : (k == 2 ? t3.read(uint2(x, yy)).rgb : t4.read(uint2(x, yy)).rgb));
    }
    kernel void s3d_sur_boxv(texture2d<float, access::read> t1 [[texture(0)]], texture2d<float, access::read> t2 [[texture(1)]], texture2d<float, access::read> t3 [[texture(2)]],
                             texture2d<float, access::read> t4 [[texture(3)]], texture2d<float, access::write> result [[texture(4)]], constant S3DParams& p [[buffer(1)]],
                             device const uchar* fp [[buffer(2)]], device const float4* wb [[buffer(4)]], uint gid [[thread_position_in_grid]]) {
        if (gid >= p.ow) return;
        const int R[4] = {16, 96, 64, 256}; const float D[4] = {33.0f, 193.0f, 129.0f, 513.0f}; const int n = (int)p.oh; float3 s[4];
        for (int k = 0; k < 4; k++) { s[k] = float3(0.0f); for (int j = -R[k]; j <= R[k]; j++) s[k] += colRead(t1, t2, t3, t4, k, gid, j, n); }
        for (int y = 0; y < n; y++) {
            if (fp[(uint)y * p.ow + gid] == 0) {
                float4 w = wb[(uint)y * p.ow + gid]; float3 b1 = s[0] / D[0], b2 = s[1] / D[1], b3 = w.w != 0.0f ? s[2] / D[2] : s[3] / D[3];   // w.w = 1: far trend 256x64 (above/below)
                float3 v = b1 + (b2 - b1) * w.x; v = v + (b3 - v) * w.y;          // lerp form: exact for constant fields
                result.write(float4(floor(v * 255.0f) / 255.0f, 1.0f), uint2(gid, (uint)y));
            }
            for (int k = 0; k < 4; k++) s[k] += colRead(t1, t2, t3, t4, k, gid, y + 1 + R[k], n) - colRead(t1, t2, t3, t4, k, gid, y - R[k], n);
        }
    }
    // s36 packers (output_modes.pack_*): mode 0 side by side, 1 half sbs (2:1 box average per eye, INTER_AREA), 2 over under, 3 Dubois anaglyph (one 3x3 pass on the 0-255 codes, +0.5, clamp, truncate).
    constant float3 DUBOIS_L[3] = {float3(0.437f, 0.449f, 0.164f), float3(-0.062f, -0.062f, -0.024f), float3(-0.048f, -0.050f, -0.017f)};
    constant float3 DUBOIS_R[3] = {float3(-0.011f, -0.032f, -0.007f), float3(0.377f, 0.761f, 0.009f), float3(-0.026f, -0.093f, 1.234f)};
    kernel void s3d_pack(texture2d<float, access::read> left [[texture(0)]], texture2d<float, access::read> right [[texture(1)]],
                         texture2d<float, access::write> outTex [[texture(2)]], constant uint& mode [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = left.get_width(), oh = left.get_height();
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        if (mode == 1u) {
            uint hw = ow / 2; bool isL = gid.x < hw; uint x = isL ? gid.x : gid.x - hw;
            float3 a = isL ? left.read(uint2(2u * x, gid.y)).rgb : right.read(uint2(2u * x, gid.y)).rgb;
            float3 b = isL ? left.read(uint2(2u * x + 1u, gid.y)).rgb : right.read(uint2(2u * x + 1u, gid.y)).rgb;
            outTex.write(float4((a + b) * 0.5f, 1.0f), gid);
        } else if (mode == 2u) {
            outTex.write(gid.y < oh ? left.read(gid) : right.read(uint2(gid.x, gid.y - oh)), gid);
        } else if (mode == 3u) {
            float3 l = left.read(gid).rgb * 255.0f, r = right.read(gid).rgb * 255.0f;
            float3 a = float3(dot(DUBOIS_L[0], l) + dot(DUBOIS_R[0], r), dot(DUBOIS_L[1], l) + dot(DUBOIS_R[1], r), dot(DUBOIS_L[2], l) + dot(DUBOIS_R[2], r)) + 0.5f;
            outTex.write(float4(floor(clamp(a, 0.0f, 255.0f)) / 255.0f, 1.0f), gid);
        } else {
            outTex.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);
        }
    }
    // s37 passthrough resampling (stereo_probe.place_on_vr180 / vr180_to_perspective). One eye per dispatch. Bilinear in cv2.remap's coordinate convention (map value = pixel INDEX,
    // texel centres at integers), out-of-range taps are black (BORDER_CONSTANT 0) with the remaining weights kept like cv2.
    struct S3DRemap { uint mode; uint srcW; uint srcH; uint outW; uint outH; float f; float thetaOrHFov; };   // mode 0: baked-stereo screen -> vr180 canvas (f = (srcW/2)/tan(theta/2)); mode 1: vr180 equirect eye (srcW = srcH = n) -> perspective (f = (outW/2)/tan(hfov/2))
    static float4 s3d_tap(texture2d<float, access::read> t, int x, int y) {
        if (x < 0 || y < 0 || x >= (int)t.get_width() || y >= (int)t.get_height()) return float4(0.0f);
        return t.read(uint2((uint)x, (uint)y));
    }
    kernel void s3d_remap(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> outTex [[texture(1)]],
                          constant S3DRemap& p [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.outW || gid.y >= p.outH) return;
        float mx, my; bool inside = true;
        if (p.mode == 0u) {
            float n = (float)p.outW;
            float lon = ((float)gid.x + 0.5f) / n * M_PI_F - M_PI_F * 0.5f, lat = M_PI_F * 0.5f - ((float)gid.y + 0.5f) / n * M_PI_F;
            mx = tan(lon) * p.f + (float)p.srcW * 0.5f; my = (float)p.srcH * 0.5f - tan(lat) * p.f;
            inside = mx >= 0.0f && mx < (float)p.srcW && my >= 0.0f && my < (float)p.srcH;
        } else {
            float n = (float)p.srcW;
            float lon = atan(((float)gid.x + 0.5f - (float)p.outW * 0.5f) / p.f), lat = atan(((float)p.outH * 0.5f - (float)gid.y - 0.5f) / p.f);
            mx = (lon + M_PI_F * 0.5f) / M_PI_F * n - 0.5f; my = (M_PI_F * 0.5f - lat) / M_PI_F * n - 0.5f;
        }
        if (!inside) { outTex.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid); return; }
        int x0 = (int)floor(mx), y0 = (int)floor(my); float fx = mx - (float)x0, fy = my - (float)y0;
        float4 c = (s3d_tap(src, x0, y0) * (1.0f - fx) + s3d_tap(src, x0 + 1, y0) * fx) * (1.0f - fy) + (s3d_tap(src, x0, y0 + 1) * (1.0f - fx) + s3d_tap(src, x0 + 1, y0 + 1) * fx) * fy;
        outTex.write(float4(c.rgb, 1.0f), gid);
    }
    kernel void s3d_sbs(texture2d<float, access::read> left [[texture(0)]], texture2d<float, access::read> right [[texture(1)]],
                        texture2d<float, access::write> sbs [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = left.get_width(), oh = left.get_height();
        if (gid.x >= ow * 2 || gid.y >= oh) return;
        sbs.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);
    }
    """
}

// [attribution comment elided]
// [attribution comment elided]
enum Stereo3DExperiments {
    private static let lock = NSLock()
    static var floatingWindow = false, depthOfField = false, holeFillGradient = false   // mutated only through the toggles under lock; read only via snapshot()
    static func setAll(_ on: Bool) { lock.lock(); floatingWindow=on; depthOfField=on; holeFillGradient=on; lock.unlock() }
    static func toggleFloatingWindow() { lock.lock(); floatingWindow.toggle(); lock.unlock() }
    static func toggleDepthOfField() { lock.lock(); depthOfField.toggle(); lock.unlock() }
    static func toggleHoleFillGradient() { lock.lock(); holeFillGradient.toggle(); lock.unlock() }
    static func snapshot() -> (fw: Bool, dof: Bool, hg: Bool) { lock.lock(); defer { lock.unlock() }; return (floatingWindow, depthOfField, holeFillGradient) }
}

final class Stereo3DRenderer {
    struct Params { var f: Float; var eye: Float; var w: UInt32; var h: UInt32; var ow: UInt32; var oh: UInt32; var conv: Float; var znear: Float; var mode: UInt32 = 0; var fout: Float = 0 }
    private let device: MTLDevice; let queue: MTLCommandQueue   // queue is internal: RenderShotWriter blits on it so its blits order after render/decodeDepth
    private let clear: MTLComputePipelineState, zmin: MTLComputePipelineState, resolve: MTLComputePipelineState
    private let fill: MTLComputePipelineState, sbs: MTLComputePipelineState
    private var depth10: MTLComputePipelineState?, remapPipe: MTLComputePipelineState?, packPipe: MTLComputePipelineState?
    private var floatWinPipe: MTLComputePipelineState?          // s3d_floatwin, lazy like the surround pipes (195h E)
    private var dofPipe: MTLComputePipelineState?, dofBlurred: MTLTexture?   // s3d_dof pre-pass + its source-sized buffer (195h G)
    private var fillGradPipe: MTLComputePipelineState?                     // s3d_fillgrad, lazy (195h hole fill)
    private(set) var lastCommandBuffer: MTLCommandBuffer?          // s32: the probe waits on it to time one render (render() itself returns after commit)
    private var surroundPipes: [MTLComputePipelineState]?        // s3d_sur_pre, _gather, _boxh, _boxv (CONTRACT-190v s20, s28 r4)
    private var scratch: [MTLTexture] = []                         // rgba32Float ping, pong, work, tmp1-4 (rx = 16/96/256/64 row blurs) for the surround, sized to the canvas
    private var geoBuffers: [ObjectIdentifier: (fp: MTLBuffer, src: MTLBuffer?, wb: MTLBuffer?, near: MTLBuffer?, geo: SurroundGeometry)] = [:]
    private func buffers(_ geo: SurroundGeometry, surround: Bool) -> (fp: MTLBuffer, src: MTLBuffer?, wb: MTLBuffer?, near: MTLBuffer?)? {
        let k = ObjectIdentifier(geo)
        if geoBuffers.count > 8 { geoBuffers.removeAll() }
        var e = geoBuffers[k]
        if e == nil { guard let fp = geo.inside.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }; e = (fp, nil, nil, nil, geo) }
        if surround, e!.src == nil {
            let idx = geo.sourceIndex, wb = geo.blendWeights, nr = geo.nearIndex
            e!.src = idx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            e!.wb = wb.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            e!.near = nr.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
        geoBuffers[k] = e; return (e!.fp, e!.src, e!.wb, e!.near)
    }

    /// nil when there is no Metal device or the source does not compile: stay on the 2D path.
    static func make() -> Stereo3DRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let options = MTLCompileOptions(); options.fastMathEnabled = false
        guard let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: options) else { return nil }
        func pipe(_ name: String) -> MTLComputePipelineState? {
            guard let fn = lib.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }
        guard let c = pipe("s3d_clear"), let z = pipe("s3d_zmin"), let r = pipe("s3d_resolve"), let f = pipe("s3d_fill"), let s = pipe("s3d_sbs") else { return nil }
        let renderer = Stereo3DRenderer(device: device, queue: queue, clear: c, zmin: z, resolve: r, fill: f, sbs: s)
        renderer.remapPipe = pipe("s3d_remap")                // s37 passthrough; nil = passthrough returns false
        renderer.packPipe = pipe("s3d_pack")                  // nil = the flat output modes are unavailable (render returns false), vr180 is unaffected
        return renderer
    }
    private init(device: MTLDevice, queue: MTLCommandQueue, clear: MTLComputePipelineState, zmin: MTLComputePipelineState,
                 resolve: MTLComputePipelineState, fill: MTLComputePipelineState, sbs: MTLComputePipelineState) {
        self.device = device; self.queue = queue; self.clear = clear; self.zmin = zmin; self.resolve = resolve; self.fill = fill; self.sbs = sbs
    }

    static func texture(_ device: MTLDevice, _ format: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// frame: rgba8/bgra8 source picture, depth: r32Float aligned METRIC depth (metres along the optical axis), thetaH: radians (shot median fov_x).
    /// `swapEyes` puts the +ipd/2 eye in the left half (the vr180-look vr_swap_eyes=1 order); a negative `ipd` does the same and is not needed. Writes side-by-side (left | right) equirect-180 eyes into `sbsOut` (2*outW x outH). Returns false on any resource failure.
    func render(frame: MTLTexture, depth: MTLTexture, thetaH: Double, ipd: Double = 0.063, convergence: Double? = nil, zNear: Double? = nil, swapEyes: Bool = false, surround: Bool = false, outW: Int, outH: Int, sbsOut: MTLTexture, output: OutputMode = .vr180, options: ThreeDExperimentOptions = .live) -> Bool {
        // s36: `output` = vr180 (default, unchanged: equirect180 eyes, outW = outH = eye N, sbsOut 2N x N) or a flat mode (perspective eyes at the source size: outW x outH = frame size,
        // sbsOut = output.canvasSize; no surround, the film fills the frame). Flat modes need the s3d_pack pipeline.
        let flat = output.isFlat, canvas = output.canvasSize(srcW: outW, srcH: outH)
        guard flat ? (sbsOut.width == canvas.w && sbsOut.height == canvas.h && outW == frame.width && outH == frame.height && packPipe != nil && (output != .halfSBS || outW % 2 == 0))
                   : (sbsOut.width == outW * 2 && sbsOut.height == outH),
              depth.width == frame.width, depth.height == frame.height,
              let cb = queue.makeCommandBuffer(),
              let zb = device.makeBuffer(length: outW * outH * 4, options: .storageModePrivate) else { return false }
        let surround = surround && !flat
        if surround, surroundPipes == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil) {
            let ps = ["s3d_sur_pre", "s3d_sur_gather", "s3d_sur_boxh", "s3d_sur_boxv"].compactMap { n in lib.makeFunction(name: n).flatMap { try? device.makeComputePipelineState(function: $0) } }
            surroundPipes = ps.count == 4 ? ps : nil        // nil on failure: the surround stays black, the render still succeeds
        }
        if surround, surroundPipes != nil, scratch.count != 7 || scratch[0].width != outW || scratch[0].height != outH {
            let t = (0..<7).compactMap { _ in Stereo3DRenderer.texture(device, .rgba32Float, outW, outH) }
            scratch = t.count == 7 ? t : []
        }
        var eyes: [MTLTexture] = []
        for sign in (swapEyes ? [1.0, -1.0] : [-1.0, 1.0]) {
            guard let rendered = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH),
                  let result = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH),
                  let enc = cb.makeComputeCommandEncoder() else { return false }
            let fD = (Double(frame.width) / 2.0) / tan(thetaH / 2.0)
            let convD = convergence.map { $0 > 0 ? atan2(sign * ipd / 2.0, $0) : 0 } ?? 0
            let geo = SurroundGeometry.cached(w: frame.width, h: frame.height, f: fD, conv: Double(Float(convD)), ow: outW, oh: outH)   // Float round trip: the kernel's own conv
            guard let gb = buffers(geo, surround: surround && surroundPipes != nil && scratch.count == 7) else { return false }
            let foutD = (Double(outW) / 2.0) / tan(OutputMode.screenDeg * Double.pi / 360.0)
            // Parallel-shift source frustum, per eye. Do not fill canvas margins with stretched film edges.
            var flatFP: MTLBuffer? = nil
            if flat {
                var mask = [UInt8](repeating: 0, count: outW * outH)
                let shift = tan(Double(Float(convD)))
                for y in 0..<outH { for x in 0..<outW {
                    let u = (Double(x) + 0.5 - Double(outW) / 2) / foutD - shift
                    let v = (Double(outH) / 2 - (Double(y) + 0.5)) / foutD
                    let sx = fD * u + Double(frame.width) / 2, sy = Double(frame.height) / 2 - fD * v
                    if sx >= 0 && sx < Double(frame.width) && sy >= 0 && sy < Double(frame.height) { mask[y * outW + x] = 1 }
                } }
                flatFP = device.makeBuffer(bytes: mask, length: mask.count, options: .storageModeShared)
                guard flatFP != nil else { return false }
            }
            var p = Params(f: Float((Double(frame.width) / 2.0) / tan(thetaH / 2.0)), eye: Float(sign * ipd / 2.0),
                           w: UInt32(frame.width), h: UInt32(frame.height), ow: UInt32(outW), oh: UInt32(outH),
                           conv: convergence.map { $0 > 0 ? Float(atan2(sign * ipd / 2.0, $0)) : 0 } ?? 0,
                           znear: zNear.map { $0 > 0 ? Float($0) : 0 } ?? 0, mode: flat ? 1 : 0, fout: flat ? Float(foutD) : 0)
            let out = MTLSize(width: outW, height: outH, depth: 1), src = MTLSize(width: frame.width, height: frame.height, depth: 1)
            func dispatch(_ s: MTLComputePipelineState, _ grid: MTLSize) {
                enc.setComputePipelineState(s)
                enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: 16, height: min(16, max(1, grid.height)), depth: 1))
            }
            enc.setBuffer(zb, offset: 0, index: 0); enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)
            enc.setTexture(rendered, index: 0); dispatch(clear, out)
            enc.setTexture(depth, index: 0); dispatch(zmin, src)
            var srcFrame = frame
            if options.depthOfField {
                if dofPipe == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_dof") {
                    dofPipe = try? device.makeComputePipelineState(function: fn)
                }
                if let dp = dofPipe {
                    if dofBlurred == nil || dofBlurred!.width != frame.width || dofBlurred!.height != frame.height {
                        dofBlurred = Stereo3DRenderer.texture(device, .rgba8Unorm, frame.width, frame.height)
                    }
                    if let bt = dofBlurred {
                        enc.setComputePipelineState(dp)
                        enc.setTexture(frame, index: 0); enc.setTexture(depth, index: 1); enc.setTexture(bt, index: 2)
                        enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)   // review r1: buffer 0 is the z-buffer binding; Params stay at 1 for every kernel
                        enc.dispatchThreads(src, threadsPerThreadgroup: MTLSize(width: 16, height: min(16, max(1, src.height)), depth: 1))
                        srcFrame = bt
                    }
                }
            }
            enc.setTexture(srcFrame, index: 0); enc.setTexture(depth, index: 1); enc.setTexture(rendered, index: 2); dispatch(resolve, src)
            enc.setTexture(rendered, index: 0); enc.setTexture(result, index: 1); enc.setBuffer(flat ? flatFP : gb.fp, offset: 0, index: 2)
            if options.holeFillGradient, fillGradPipe == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_fillgrad") {
                fillGradPipe = try? device.makeComputePipelineState(function: fn)
            }
            enc.setComputePipelineState(options.holeFillGradient ? (fillGradPipe ?? fill) : fill)
            enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))
            if surround, let ps = surroundPipes, scratch.count == 7, let sb = gb.src, let wb = gb.wb, let nb = gb.near, !geo.allInside {
                // r3 soft surround: normalised pre-blur x32 (canvas -> ping -> pong ...), gather the nearest-footprint source, boundary correction, four running-sum boxes (side-local far trend), distance lerp; outside the footprint only
                enc.setBuffer(gb.fp, offset: 0, index: 2); enc.setBuffer(sb, offset: 0, index: 3); enc.setBuffer(wb, offset: 0, index: 4); enc.setBuffer(nb, offset: 0, index: 5)
                var cur: MTLTexture = result
                var bx = geo.footprintBox; enc.setBytes(&bx, length: MemoryLayout<SIMD4<UInt32>>.size, index: 6)          // s31: pre-blur over the footprint box only
                let preGrid = MTLSize(width: Int(bx[2]), height: Int(bx[3]), depth: 1)
                for k in 0..<32 { var first: UInt32 = k == 0 ? 1 : 0; enc.setBytes(&first, length: 4, index: 7); let dst = scratch[k % 2]; enc.setTexture(cur, index: 0); enc.setTexture(dst, index: 1); dispatch(ps[0], preGrid); cur = dst }
                enc.setTexture(cur, index: 0); enc.setTexture(scratch[2], index: 1); enc.setTexture(result, index: 2); dispatch(ps[1], out)          // work (r4: truth = the filled film in `result`)
                enc.setTexture(scratch[2], index: 0); enc.setTexture(scratch[3], index: 1); enc.setTexture(scratch[4], index: 2); enc.setTexture(scratch[5], index: 3); enc.setTexture(scratch[6], index: 4)
                enc.setComputePipelineState(ps[2]); enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))   // row boxes
                enc.setTexture(scratch[3], index: 0); enc.setTexture(scratch[4], index: 1); enc.setTexture(scratch[5], index: 2); enc.setTexture(scratch[6], index: 3); enc.setTexture(result, index: 4)
                enc.setComputePipelineState(ps[3]); enc.dispatchThreads(MTLSize(width: outW, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outW), height: 1, depth: 1))   // column boxes + blend
            }
            var eyeOut = result
            if options.floatingWindow {
                if floatWinPipe == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_floatwin") {
                    floatWinPipe = try? device.makeComputePipelineState(function: fn)
                }
                if let fwp = floatWinPipe, let winTex = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH) {
                    enc.setBuffer(zb, offset: 0, index: 0); enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)
                    enc.setTexture(result, index: 0); enc.setTexture(winTex, index: 1)
                    enc.setComputePipelineState(fwp)
                    enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))
                    eyeOut = winTex                                  // pipeline/texture failure keeps the un-windowed eye (experiment only)
                }
            }
            enc.endEncoding(); eyes.append(eyeOut)
        }
        guard let enc = cb.makeComputeCommandEncoder() else { return false }
        var packMode = output.packCode
        enc.setComputePipelineState(flat ? packPipe! : sbs); enc.setTexture(eyes[0], index: 0); enc.setTexture(eyes[1], index: 1); enc.setTexture(sbsOut, index: 2)
        if flat { enc.setBytes(&packMode, length: 4, index: 0) }
        enc.dispatchThreads(MTLSize(width: flat ? canvas.w : outW * 2, height: flat ? canvas.h : outH, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, outH), depth: 1))
        enc.endEncoding(); cb.commit(); lastCommandBuffer = cb
        return true
    }

    /// CONTRACT-190v v2 depth: `luma` is the Y plane of a 10-bit biplanar decode (MTLPixelFormat.r16Unorm view of plane 0, VideoToolbox), `metric`
    /// r32Float same size. Z = 256 / (w10/1023*1024) metres, w10 == 0 -> 0 (masked, skipped by s3d_map). `shift` = bits the decoder left of the 10-bit
    /// value (6 for Apple MSB-aligned 420YpCbCr10BiPlanar, 0 if right-aligned): unverified on device, so it is a parameter, not a guess baked in.
    func decodeDepth(luma: MTLTexture, metric: MTLTexture, shift: UInt32 = 6) -> Bool {
        if depth10 == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_depth10") {
            depth10 = try? device.makeComputePipelineState(function: fn)
        }
        guard let pipe = depth10, luma.width == metric.width, luma.height == metric.height, shift <= 6,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return false }
        var sh = shift
        enc.setComputePipelineState(pipe); enc.setTexture(luma, index: 0); enc.setTexture(metric, index: 1); enc.setBytes(&sh, length: 4, index: 0)
        enc.dispatchThreads(MTLSize(width: metric.width, height: metric.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, metric.height), depth: 1))
        enc.endEncoding(); cb.commit()
        return true
    }

    /// s37 passthrough of an ALREADY-3D source (no depth stage): `left`/`right` = the eye crops of the source frame (readable rgba8/bgra8; half layouts must be upscaled by the caller first).
    /// Baked-stereo (flat) source: flat output modes are lossless repacks (s3d_pack); vr180 output places each eye as a flat screen on the equirect canvas (s3d_remap mode 0, 75 deg screen).
    /// vr180 source: flat output reprojects the forward 75 deg (s3d_remap mode 1), then packs; vr180 -> vr180 is the source itself (returns false: play the file). `sbsOut` = output.canvasSize.
    /// Mirrors stereo_probe.passthrough (Linux parity of the resampling: Tests/Stereo3DKernel/stereo_remap_kernel_test.py). Not run on a Mac.
    func passthrough(left: MTLTexture, right: MTLTexture, sourceIsVR180: Bool, output: OutputMode, swap: Bool, sbsOut: MTLTexture) -> Bool {
        let needsRemap = output == .vr180 || sourceIsVR180, needsPack = output != .vr180     // review F2: each path needs only its own pipelines (a pack failure must not disable vr180 placement)
        guard left.width == right.width, left.height == right.height, !needsRemap || remapPipe != nil, !needsPack || packPipe != nil,
              !(sourceIsVR180 && output == .vr180), let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return false }
        let eyes = swap ? [right, left] : [left, right]
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        func remap(_ src: MTLTexture, _ dst: MTLTexture, mode: UInt32, f: Double) {
            var rm = S3DRemapParams(mode: mode, srcW: UInt32(src.width), srcH: UInt32(src.height), outW: UInt32(dst.width), outH: UInt32(dst.height), f: Float(f), thetaOrHFov: 0)
            enc.setComputePipelineState(remapPipe!); enc.setTexture(src, index: 0); enc.setTexture(dst, index: 1); enc.setBytes(&rm, length: MemoryLayout<S3DRemapParams>.size, index: 0)
            enc.dispatchThreads(MTLSize(width: dst.width, height: dst.height, depth: 1), threadsPerThreadgroup: tg)
        }
        let half = tan(OutputMode.screenDeg * Double.pi / 360.0)
        var out: [MTLTexture] = []
        if output == .vr180 {
            let n = sbsOut.height, f = (Double(left.width) / 2.0) / half
            guard sbsOut.width == 2 * n else { enc.endEncoding(); return false }
            for e in eyes { guard let t = Stereo3DRenderer.texture(device, .rgba8Unorm, n, n) else { enc.endEncoding(); return false }; remap(e, t, mode: 0, f: f); out.append(t) }
            enc.setComputePipelineState(sbs); enc.setTexture(out[0], index: 0); enc.setTexture(out[1], index: 1); enc.setTexture(sbsOut, index: 2)
            enc.dispatchThreads(MTLSize(width: 2 * n, height: n, depth: 1), threadsPerThreadgroup: tg)
        } else {
            let ew: Int, eh: Int
            if sourceIsVR180 { (ew, eh) = (output.eyeW(canvasW: sbsOut.width), output.eyeH(canvasH: sbsOut.height)) } else { (ew, eh) = (left.width, left.height) }
            let c = output.canvasSize(srcW: ew, srcH: eh)
            guard c.w == sbsOut.width, c.h == sbsOut.height, output != .halfSBS || ew % 2 == 0 else { enc.endEncoding(); return false }
            for e in eyes {
                if sourceIsVR180 {
                    guard let t = Stereo3DRenderer.texture(device, .rgba8Unorm, ew, eh) else { enc.endEncoding(); return false }
                    remap(e, t, mode: 1, f: (Double(ew) / 2.0) / half); out.append(t)
                } else { out.append(e) }
            }
            var pm = output.packCode
            enc.setComputePipelineState(packPipe!); enc.setTexture(out[0], index: 0); enc.setTexture(out[1], index: 1); enc.setTexture(sbsOut, index: 2); enc.setBytes(&pm, length: 4, index: 0)
            enc.dispatchThreads(MTLSize(width: c.w, height: c.h, depth: 1), threadsPerThreadgroup: tg)
        }
        enc.endEncoding(); cb.commit(); lastCommandBuffer = cb
        return true
    }
}
struct S3DRemapParams { var mode: UInt32; var srcW: UInt32; var srcH: UInt32; var outW: UInt32; var outH: UInt32; var f: Float; var thetaOrHFov: Float }   // = MSL S3DRemap (7 x 4 bytes)
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190v s37 port of tools/depth_analysis/stereo_probe.py (layers 1-3): detect sources that are ALREADY 3D so they never go through 2D->3D depth.
/// Pure Foundation (compiled and run on Linux, Tests/StereoSource). Layer 1 = container metadata (authoritative), layer 2 = filename (a CANDIDATE layout only, never a verdict),
/// layer 3 = pixel confirm: high-passed grey NCC over horizontal shifts, threshold 0.4. The menu override (force 2D->3D / force a layout) wins over all three layers.
enum StereoLayout: String, CaseIterable {
    case sbs, halfSBS = "half_sbs", ou, halfOU = "half_ou", vr180, mvhevc
}

struct StereoSideData: Equatable {
    var type = ""                    // ffprobe side_data_type, e.g. "Stereo 3D" or "Spherical Mapping"
    var kind = ""                    // "Stereo 3D" `type`, e.g. "side by side", "top_bottom"
    var inverted = false
    var sphericalStereoMode: String? = nil   // Spherical Video V2 stereo_mode: "left-right" / "right-left"
}

struct StereoVerdict: Equatable {
    enum Source: String { case metadata, filename }
    var layout: StereoLayout
    var swap: Bool
    var source: Source
}

enum StereoSource {
    static let hpThreshold = 0.4

    static let stereoModeMap: [String: (StereoLayout, Bool)] = [
        "side by side": (.sbs, false), "side by side (quincunx)": (.sbs, false), "top and bottom": (.ou, false), "left_right": (.sbs, false),
        "right_left": (.sbs, true), "top_bottom": (.ou, false), "bottom_top": (.ou, true)]
    static let sphericalMap: [String: (StereoLayout, Bool)] = ["left-right": (.vr180, false), "right-left": (.vr180, true)]
    // Same alternatives and order as stereo_probe.HINT_RE (first match wins). ICU regex: lookbehind is supported.
    static let hints: [(String, StereoLayout)] = [
        ("(?<![a-z])(h[-_.]?sbs|half[-_.]?sbs)(?![a-z])", .halfSBS), ("(?<![a-z])(f[-_.]?sbs|full[-_.]?sbs|sbs|lr[-_.]?3d)(?![a-z])", .sbs),
        ("(?<![a-z])(h[-_.]?ou|half[-_.]?ou|half[-_.]?tb)(?![a-z])", .halfOU), ("(?<![a-z])(ou|over[-_.]?under|tb|top[-_.]?bottom)(?![a-z])", .ou),
        ("(?<![a-z])(vr180|180[-_.]?3d|3d[-_.]?180)(?![a-z])", .vr180)]

    /// Layer 1 (+ weak layer 2): the first metadata match wins; a filename hit is returned with source .filename (a candidate, the caller must pixel-confirm it).
    static func metadataVerdict(path: String, sideData: [StereoSideData], profile: String, codecTag: String) -> StereoVerdict? {
        for sd in sideData {
            if sd.type == "Stereo 3D", let (lay, sw) = stereoModeMap[sd.kind] { return StereoVerdict(layout: lay, swap: sw != sd.inverted, source: .metadata) }
            if sd.type.contains("pherical"), let m = sd.sphericalStereoMode, let (lay, sw) = sphericalMap[m] { return StereoVerdict(layout: lay, swap: sw, source: .metadata) }
        }
        if profile.lowercased().contains("multiview") || codecTag.lowercased().hasPrefix("mv-") { return StereoVerdict(layout: .mvhevc, swap: false, source: .metadata) }
        return filenameCandidate(path)
    }

    /// ffprobe `-show_streams -of json` -> (side data, profile, codec tag) of the first stream: the same fields stereo_probe._ffprobe/metadata_verdict read.
    static func parseFFprobe(_ data: Data) -> (sideData: [StereoSideData], profile: String, codecTag: String)? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let st = (o["streams"] as? [[String: Any]])?.first else { return nil }
        let sd = (st["side_data_list"] as? [[String: Any]] ?? []).map { d -> StereoSideData in
            StereoSideData(type: d["side_data_type"] as? String ?? "", kind: d["type"] as? String ?? "", inverted: ((d["inverted"] as? NSNumber)?.intValue ?? 0) != 0, sphericalStereoMode: d["stereo_mode"] as? String)
        }
        return (sd, st["profile"] as? String ?? "", st["codec_tag_string"] as? String ?? "")
    }

    static func filenameCandidate(_ path: String) -> StereoVerdict? {
        let name = (path as NSString).lastPathComponent.lowercased()
        for (rx, lay) in hints where name.range(of: rx, options: .regularExpression) != nil { return StereoVerdict(layout: lay, swap: false, source: .filename) }
        return nil
    }

    /// Eye rectangles (x, y, w, h) of a frame w x h. Half layouts return the NATIVE half-size halves (the Python reference upsamples them with cv2 cubic first;
    /// the pixel confirm here runs on the native halves, same threshold: not parity-tested for half layouts).
    static func eyeRects(_ layout: StereoLayout, w: Int, h: Int) -> (l: (x: Int, y: Int, w: Int, h: Int), r: (x: Int, y: Int, w: Int, h: Int))? {
        switch layout {
        case .sbs, .vr180, .halfSBS: return ((0, 0, w / 2, h), (w / 2, 0, w / 2, h))
        case .ou, .halfOU: return ((0, 0, w, h / 2), (0, h / 2, w, h / 2))
        case .mvhevc: return nil
        }
    }

    /// cv2.cvtColor(RGB2GRAY) on uint8 (fixed point, round half up) -> Float.
    static func grey(r: UInt8, g: UInt8, b: UInt8) -> Float { Float((UInt32(r) * 4899 + UInt32(g) * 9617 + UInt32(b) * 1868 + 8192) >> 14) }

    /// grey minus a sigma-3 Gaussian blur (19 taps, normalised, reflect-101 borders: cv2.GaussianBlur(g, (0, 0), 3.0) on float32).
    static func highPass(_ g: [Float], w: Int, h: Int, sigma: Double = 3.0) -> [Float] {
        let r = Int((sigma * 6 + 1).rounded()) | 1, half = r / 2
        var k = (0..<r).map { exp(-pow(Double($0 - half), 2) / (2 * sigma * sigma)) }
        let s = k.reduce(0, +); k = k.map { $0 / s }
        let kf = k.map { Float($0) }
        func refl(_ i: Int, _ n: Int) -> Int { var j = i; if n == 1 { return 0 }; while j < 0 || j >= n { j = j < 0 ? -j : 2 * (n - 1) - j }; return j }
        var tmp = [Float](repeating: 0, count: w * h), out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { var a: Float = 0; for t in 0..<r { a += kf[t] * g[y * w + refl(x + t - half, w)] }; tmp[y * w + x] = a } }
        for y in 0..<h { for x in 0..<w { var a: Float = 0; for t in 0..<r { a += kf[t] * tmp[refl(y + t - half, h) * w + x] }; out[y * w + x] = g[y * w + x] - a } }
        return out
    }

    private static func ncc(_ a: [Float], _ b: [Float]) -> Double {
        if a.isEmpty { return -1 }
        let n = Double(a.count)
        var ma = 0.0, mb = 0.0
        for i in 0..<a.count { ma += Double(a[i]); mb += Double(b[i]) }
        ma /= n; mb /= n
        var cov = 0.0, va = 0.0, vb = 0.0
        for i in 0..<a.count { let x = Double(a[i]) - ma, y = Double(b[i]) - mb; cov += x * y; va += x * x; vb += y * y }
        return (cov / n) / ((va / n).squareRoot() * (vb / n).squareRoot() + 1e-6)
    }

    /// stereo_probe.best_shift_ncc on already high-passed halves: (best hp NCC, shift px).
    static func bestShift(hl: [Float], hr: [Float], w: Int, h: Int, maxShift: Int? = nil) -> (ncc: Double, shift: Int) {
        let ms = maxShift ?? w / 5
        var best = -1.0, bd = 0
        for d in -ms...ms {
            let cols = w - abs(d)
            if cols < w / 3 { continue }
            var x = [Float](), y = [Float](); x.reserveCapacity(cols * h); y.reserveCapacity(cols * h)
            for row in 0..<h {
                let lo = d >= 0 ? d : 0, ro = d >= 0 ? 0 : -d
                for c in 0..<cols { x.append(hl[row * w + lo + c]); y.append(hr[row * w + ro + c]) }
            }
            let v = ncc(x, y)
            if v > best { best = v; bd = d }
        }
        return (best, bd)
    }

    /// Layer 3 on RGBA/BGRA-agnostic grey input: `grey` is the w x h grey frame of ONE eye each (already extracted by eyeRects). Returns (isStereo, hpNCC, shift).
    static func confirm(leftGrey: [Float], rightGrey: [Float], w: Int, h: Int) -> (isStereo: Bool, hpNCC: Double, shift: Int) {
        let b = bestShift(hl: highPass(leftGrey, w: w, h: h), hr: highPass(rightGrey, w: w, h: h), w: w, h: h)
        return (b.ncc >= hpThreshold, b.ncc, b.shift)
    }

    /// Final routing. `override` (menu) wins over everything: .flat forces 2D->3D, .layout forces a stereo format.
    enum Override: Equatable { case flat, layout(StereoLayout, swap: Bool) }
    /// playAsIs: a confirmed stereo source we cannot repack yet (half layouts need an upscale pass): never sent to 2D->3D depth, played as the file is.
    enum Route: Equatable { case depth, passthrough(StereoLayout, swap: Bool), nativeNote, playAsIs }
    static func route(verdict: StereoVerdict?, pixelConfirmed: Bool?, override: Override?) -> Route {
        if let o = override { switch o { case .flat: return .depth; case .layout(let l, let s): return l == .mvhevc ? .nativeNote : (l == .halfSBS || l == .halfOU ? .playAsIs : .passthrough(l, swap: s)) } }
        guard let v = verdict else { return .depth }
        if v.layout == .mvhevc { return .nativeNote }
        let confirmed = v.source == .metadata || pixelConfirmed == true      // filename alone never routes
        guard confirmed else { return .depth }
        return v.layout == .halfSBS || v.layout == .halfOU ? .playAsIs : .passthrough(v.layout, swap: v.swap)
    }

    struct Disparity: Equatable {
        var pxP50 = 0.0, pxP99 = 0.0, degP50 = 0.0, degP95 = 0.0, degP99 = 0.0, overBudgetFrac = 0.0, coverage = 0.0, assumeHFOVDeg = 90.0
    }
    static let comfortBudgetDeg = 2.0

    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {      // numpy.percentile, linear interpolation
        let pos = q / 100 * Double(sorted.count - 1), lo = Int(pos.rounded(.down)), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }
    private static func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }

    /// stereo_probe.measure_disparity: WARN-ONLY comfort check of baked-in disparity (32 px blocks, +-W/8 search, high-passed grey, MAD outlier rejection). nil = unmeasurable
    /// (too few blocks lock) or the eye is narrower than 256 px (the Python upscales first with cv2 cubic; not ported: real sources are wider). A warn never blocks the passthrough.
    static func measureDisparity(leftGrey: [Float], rightGrey: [Float], w: Int, h: Int, assumeHFOVDeg: Double = 90, block: Int = 32, nccMin: Double = 0.5) -> Disparity? {
        guard w >= 256, h >= block else { return nil }
        let gl = highPass(leftGrey, w: w, h: h), gr = highPass(rightGrey, w: w, h: h), span = w / 8
        var vals = [Double](), total = 0
        var y = 0
        while y <= h - block {
            var x = 0
            while x <= w - block {
                total += 1
                var bl = [Float](); bl.reserveCapacity(block * block)
                for r in 0..<block { for c in 0..<block { bl.append(gl[(y + r) * w + x + c]) } }
                let m = bl.reduce(0, { $0 + Double($1) }) / Double(bl.count)
                let sd = (bl.reduce(0.0, { $0 + (Double($1) - m) * (Double($1) - m) }) / Double(bl.count)).squareRoot()
                if sd >= 1e-3 {
                    var best = -1.0, bd = 0
                    for d in -span...span {
                        let xs = x + d
                        if xs < 0 || xs + block > w { continue }
                        var rb = [Float](); rb.reserveCapacity(block * block)
                        for r in 0..<block { for c in 0..<block { rb.append(gr[(y + r) * w + xs + c]) } }
                        let v = ncc(bl, rb)
                        if v > best { best = v; bd = d }
                    }
                    if best >= nccMin { vals.append(Double(bd)) }
                }
                x += block / 2
            }
            y += block / 2
        }
        guard Double(vals.count) >= max(8, Double(total) * 0.05) else { return nil }
        let med = median(vals), mad = median(vals.map { abs($0 - med) }) + 1
        let kept = vals.filter { abs($0 - med) <= 4 * mad }.map { abs($0) }.sorted()
        guard !kept.isEmpty else { return nil }
        let dpp = assumeHFOVDeg / Double(w), p50 = percentile(kept, 50), p95 = percentile(kept, 95), p99 = percentile(kept, 99)
        return Disparity(pxP50: p50, pxP99: p99, degP50: p50 * dpp, degP95: p95 * dpp, degP99: p99 * dpp,
                         overBudgetFrac: Double(kept.filter { $0 * dpp > comfortBudgetDeg }.count) / Double(kept.count), coverage: Double(vals.count) / Double(total), assumeHFOVDeg: assumeHFOVDeg)
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation) && canImport(CoreGraphics)
import AVFoundation
import CoreGraphics

/// 190v s37 wiring: decides per film whether the 2D->3D depth prepare may run. A source that is already 3D never goes through depth (route != .depth): it plays as the file is
/// (the player's flat sbs/tb path) and the OSD says so once. The decision is cached per path and computed off the main thread (ffprobe + at most one frame grab); until it is known
/// `route(for:)` returns nil and the caller treats the film as "not yet": no prepare starts. Override (UserDefaults gor.3d.stereoSource: "auto", "flat" = force 2D->3D, or a layout
/// rawValue = force that stereo format) wins over all three layers. UNCOMPILED on a Mac; the decision logic itself is StereoSource (Linux-tested).
final class StereoSourceGate {
    static let shared = StereoSourceGate()
    static let overrideKey = "gor.3d.stereoSource"
    private let q = DispatchQueue(label: "gor.stereo-source", qos: .utility), lock = NSLock()
    private var cache: [String: (route: StereoSource.Route, note: String)] = [:], pending = Set<String>()
    private var told = Set<String>()
    /// true the first time this (film, note) pair is asked for (the timer ticks every 3 s: the OSD line shows once per film).
    func once(film: URL, note: String) -> Bool { lock.lock(); defer { lock.unlock() }; return told.insert(film.path + "|" + note).inserted }
    var resolvedSource:(URL)->String? = {_ in nil}
    var ffprobe: () -> String = { GORResources.vendorPath("ffmpeg/bin/ffprobe") }

    static func override(_ d: UserDefaults = .standard,source:String?=nil) -> StereoSource.Override? {
        guard let v=source,v != "auto" else{return nil}
        if v == "flat" { return .flat }
        if v.hasSuffix(":swap"), let l = StereoLayout(rawValue: String(v.dropLast(5))) { return .layout(l, swap: true) }
        return StereoLayout(rawValue: v).map { .layout($0, swap: false) }
    }

    /// nil = still deciding. The cache key includes the override so changing it re-decides at once.
    func route(for film: URL, defaults: UserDefaults = .standard) -> (route: StereoSource.Route, note: String)? {
        let manual=SourceFormatChoice.get(film.path,defaults)
        if manual.hasPrefix("vr180") || manual.hasPrefix("vr360") {return (.playAsIs,"3D: native spherical source, no depth conversion")}
        if manual=="auto",let kind=resolvedSource(film),kind != "mono",kind != "2d" {return (.playAsIs,"3D: native stereo source, no depth conversion")}
        let source=SourceFormatChoice.get(film.path,defaults),ov=Self.override(defaults,source:source),key=film.path+"|"+source
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        if let ov, case .flat = ov { let r = (route: StereoSource.Route.depth, note: ""); cache[key] = r; lock.unlock(); return r }
        let started = pending.insert(key).inserted          // review F4: check and insert under ONE lock hold, so two ticks cannot both start a decide
        lock.unlock()
        if !started { return nil }
        q.async { [self] in
            let r = decide(film, ov)
            lock.lock(); cache[key] = r; pending.remove(key); lock.unlock()
        }
        return nil
    }

    private func decide(_ film: URL, _ ov: StereoSource.Override?) -> (route: StereoSource.Route, note: String) {
        if !FileManager.default.isExecutableFile(atPath: ffprobe()), once(film: film, note: "ffprobe-missing") { print("stereo-source: ffprobe not in the vendor tree, metadata layer skipped (file name + pixel check only)"); fflush(stdout) } // [attribution comment elided]
        let verdict = StereoSourceProbe.verdict(url: film, ffprobe: ffprobe())
        var confirmed: Bool? = nil
        if ov == nil, let v = verdict, v.source == .filename { confirmed = pixelConfirm(film, v.layout) }
        let route = StereoSource.route(verdict: verdict, pixelConfirmed: confirmed, override: ov)
        let name = verdict.map { $0.layout.rawValue } ?? "none"
        switch route {
        case .depth: return (route, "")
        case .passthrough, .playAsIs: return (route, "3D: this file is already stereo (\(ov == nil ? name : "forced")), playing it as is")
        case .nativeNote: return (route, "3D: native 3D source (MV-HEVC), not converted: pick it from the 3d menu")
        }
    }

    /// Layer 3: one frame at ~10% of the duration, 640 px wide, grey eye halves -> StereoSource.confirm. nil = could not grab (unconfirmed, so the filename alone never routes).
    private func pixelConfirm(_ film: URL, _ layout: StereoLayout) -> Bool? {
        let asset = AVURLAsset(url: film), gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 640, height: 640)
        let t = CMTime(seconds: max(1, asset.duration.seconds.isFinite ? asset.duration.seconds * 0.1 : 1), preferredTimescale: 600)
        guard let img = try? gen.copyCGImage(at: t, actualTime: nil) else { return nil }
        let w = img.width, h = img.height
        guard let r = StereoSource.eyeRects(layout, w: w, h: h), let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let base = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = base.assumingMemoryBound(to: UInt8.self)
        func eye(_ q: (x: Int, y: Int, w: Int, h: Int)) -> [Float] {
            var g = [Float](); g.reserveCapacity(q.w * q.h)
            for y in 0..<q.h { for x in 0..<q.w { let i = ((q.y + y) * w + q.x + x) * 4; g.append(StereoSource.grey(r: px[i], g: px[i + 1], b: px[i + 2])) } }
            return g
        }
        return StereoSource.confirm(leftGrey: eye(r.l), rightGrey: eye(r.r), w: r.l.w, h: r.l.h).isStereo
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190v s37 Mac side of the stereo detection: runs the vendored ffprobe (same fields stereo_probe.py reads: Stereo 3D / Spherical side data, profile, codec tag) and falls back to
/// the filename candidate when ffprobe is missing or fails (a filename never routes without the pixel confirm). UNCOMPILED on a Mac; the JSON parsing and verdict logic are
/// Linux-tested (Tests/StereoSource). A pixel confirm needs decoded frames: the caller grabs eye greys from the proxy and calls StereoSource.confirm.
enum StereoSourceProbe {
    static func verdict(url: URL, ffprobe: String, timeout: TimeInterval = 20) -> StereoVerdict? {
        guard FileManager.default.isExecutableFile(atPath: ffprobe) else { return StereoSource.filenameCandidate(url.path) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: ffprobe)
        p.arguments = ["-v", "error", "-select_streams", "v:0", "-show_streams", "-of", "json", url.path]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return StereoSource.filenameCandidate(url.path) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); killer.cancel()
        guard p.terminationStatus == 0, let f = StereoSource.parseFFprobe(data) else { return StereoSource.filenameCandidate(url.path) }
        return StereoSource.metadataVerdict(path: url.path, sideData: f.sideData, profile: f.profile, codecTag: f.codecTag)
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190v s34 port of tools/depth_analysis/colorprobe.py. Pure Foundation (compiled and run on Linux against the reference in Tests/SourceFormat); the AVFoundation extraction
/// lives in SourceFormatProbe.swift (Darwin only, uncompiled). Transfer / primaries / matrix use the ffmpeg names the reference uses.
struct SourceFacts: Equatable {
    var width = 0, height = 0                    // storage pixels
    var rotation = 0                             // display-matrix rotation, degrees clockwise: 0 / 90 / 180 / 270
    var sar = 1.0                                // pixel aspect (h spacing / v spacing)
    var bitDepth = 8
    var transfer = "unknown", primaries = "unknown", matrix = "unknown"
    var fullRange: Bool? = nil                   // nil = untagged
    var dolbyVision = false
    var avgFps = 0.0, maxFps = 0.0               // nominalFrameRate, 1 / minFrameDuration
    var sampleDeltasMs: [Double] = []            // consecutive sample PTS deltas, ms; empty = not probed
    var ptsTickMs = 1.0                          // container timestamp quantum (1.0 for ms-muxed MKV/MP4)
}

enum SourceFormat {
    static let hdrTransfers: Set<String> = ["smpte2084", "arib-std-b67", "smpte428"]
    static let vfrRelTol = 0.002
    static let matrixCanon: [String: String] = ["bt709": "bt709", "bt470bg": "bt470bg", "smpte170m": "smpte170m", "fcc": "fcc", "bt2020nc": "bt2020nc", "bt2020_ncl": "bt2020nc", "bt2020c": "bt2020c", "chroma-derived-nc": "bt470bg"]

    /// Display size: square pixels, rotation applied (SAR scales the width first, then a 90/270 rotation swaps the axes).
    static func normalizedSize(_ f: SourceFacts) -> (w: Int, h: Int) {
        var w = Int((Double(f.width) * f.sar).rounded(.toNearestOrEven)), h = f.height
        if f.rotation == 90 || f.rotation == 270 { swap(&w, &h) }
        return (w, h)
    }
    static func needsNormalization(_ f: SourceFacts) -> Bool { f.rotation != 0 || abs(f.sar - 1.0) > 1e-3 }

    /// The YCbCr matrix the chain uses: the tag, else the size rule AVFoundation and mpv apply (HD bt709, SD bt470bg).
    static func matrixKey(_ f: SourceFacts) -> String {
        if let m = matrixCanon[f.matrix] { return m }
        return (f.width >= 1280 || f.height > 576) ? "bt709" : "bt470bg"
    }
    /// Whole-timeline presentation-grid fit, allowing container rounding, never dropped frames.
    /// Frame-indexed readers require one sample per grid point. Interval-only tests can miss
    /// cumulative drift (e.g. a long41ms segment then42ms); check every cumulative timestamp.
    /// nil = insufficient evidence, preserve the metadata guard.
    static func gridCFR(_ deltasMs: [Double], tickMs: Double) -> Bool? {
        guard deltasMs.count >= 30 else { return nil }
        guard tickMs.isFinite,tickMs>=0,deltasMs.allSatisfy({$0.isFinite && $0>0}) else {return false}
        let g = deltasMs.reduce(0,+) / Double(deltasMs.count)
        guard g.isFinite,g>1,g<=1000 else {return false}
        let eps=max(tickMs,1.0) // inherited millisecond mux precision after lossless remux
        var elapsed=0.0
        for (index,d) in deltasMs.enumerated() {
            elapsed += d
            if abs(d-g)>eps || abs(elapsed-Double(index+1)*g)>eps {return false}
        }
        return true
    }
    static func isVFR(_ f: SourceFacts) -> Bool {
        if let grid = gridCFR(f.sampleDeltasMs, tickMs: f.ptsTickMs) { return !grid }
        return f.avgFps > 0 && f.maxFps > 0 && abs(f.maxFps - f.avgFps) / f.avgFps > vfrRelTol
    }

    /// (dimension, status, detail) for the dimensions that gate or steer the port; same names and statuses as colorprobe.verdicts (refuse / fix / ok / note).
    static func verdicts(_ f: SourceFacts) -> [(dim: String, status: String, detail: String)] {
        var o: [(String, String, String)] = []
        o.append(("bit_depth", f.bitDepth >= 10 ? "ok" : "note", "\(f.bitDepth)-bit"))
        o.append(("hdr_transfer", hdrTransfers.contains(f.transfer) ? "refuse" : "ok", hdrTransfers.contains(f.transfer) ? "HDR transfer \(f.transfer): 3D prepare refuses; playing 2D" : "transfer \(f.transfer)"))
        o.append(("dolby_vision", f.dolbyVision ? "refuse" : "ok", f.dolbyVision ? "Dolby Vision: 3D prepare refuses; playing 2D" : "not Dolby Vision"))
        o.append(("sar", abs(f.sar - 1.0) > 1e-3 ? "fix" : "ok", "sar \(f.sar)"))
        o.append(("rotation", f.rotation != 0 ? "fix" : "ok", "rotation \(f.rotation)"))
        let vfrDetail: String
        if let grid = gridCFR(f.sampleDeltasMs, tickMs: f.ptsTickMs) {
            vfrDetail = grid ? "CFR (sample-grid consistent)" : "variable frame rate (sample timestamps off the fitted presentation grid): frame-indexed prepare assumes constant frame rate; playing 2D"
        } else {
            vfrDetail = isVFR(f) ? "variable frame rate (nominal \(f.avgFps) vs max \(f.maxFps)): frame-indexed prepare assumes constant frame rate; playing 2D" : "CFR"
        }
        o.append(("vfr", isVFR(f) ? "refuse" : "ok", vfrDetail))
        return o
    }
    static func refuseReasons(_ f: SourceFacts) -> [String] { verdicts(f).filter { $0.status == "refuse" }.map { $0.detail } }

    /// Affine (a, b, c, d, tx, ty) taking storage pixel coordinates (y down) to display pixels: SAR scale, then the track's preferredTransform, then a translation so the result
    /// fills [0, W] x [0, H] of normalizedSize. Applied by the composition reader, which also resamples to the display size.
    static func displayTransform(preferred p: (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double), sar: Double, width: Int, height: Int) -> (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        // row-vector convention as CGAffineTransform: x' = a x + c y + tx, y' = b x + d y + ty. First scale x by sar, then apply p.
        let a = sar * p.a, b = sar * p.b, c = p.c, d = p.d
        let xs = [0.0, Double(width), 0.0, Double(width)], ys = [0.0, 0.0, Double(height), Double(height)]
        var minX = Double.infinity, minY = Double.infinity
        for i in 0..<4 { minX = min(minX, a * xs[i] + c * ys[i] + p.tx); minY = min(minY, b * xs[i] + d * ys[i] + p.ty) }
        return (a, b, c, d, p.tx - minX, p.ty - minY)
    }
    /// Rotation (clockwise degrees) of a preferredTransform; 0 for anything that is not a multiple of 90 (flips and skews are not handled: treated as unrotated plus a note by the caller).
    static func rotation(a: Double, b: Double, c: Double, d: Double) -> Int {
        func eq(_ x: Double, _ y: Double) -> Bool { abs(x - y) < 1e-3 }
        if eq(a, 1) && eq(b, 0) && eq(c, 0) && eq(d, 1) { return 0 }
        if eq(a, 0) && eq(b, 1) && eq(c, -1) && eq(d, 0) { return 90 }
        if eq(a, -1) && eq(b, 0) && eq(c, 0) && eq(d, -1) { return 180 }
        if eq(a, 0) && eq(b, -1) && eq(c, 1) && eq(d, 0) { return 270 }
        return 0
    }

    /// Luma bit depth from the codec configuration record (hvcC byte 17 & 7 + 8; avcC High 10 / 4:2:2 / 4:4:4 profiles with SPS depth not parsed: 110/122/244 = 10-bit assumed).
    static func bitDepth(hvcC: [UInt8]?, avcC: [UInt8]?) -> Int {
        if let h = hvcC, h.count > 17 { return Int(h[17] & 7) + 8 }
        if let a = avcC, a.count > 1, [110, 122, 244].contains(a[1]) { return 10 }
        return 8
    }

    /// 8-bit code -> MSB-aligned 10-bit (v10 << 6) code stored in 16 bits. Video range: exact (v << 8). Full range: v10 = round(v * 1023 / 255) approximated as v * 4 + (v >> 6).
    static func widen8To10(_ v: UInt8, fullRange: Bool) -> UInt16 {
        if !fullRange { return UInt16(v) << 8 }
        return UInt16(UInt16(v) * 4 + UInt16(v >> 6)) << 6
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation) && canImport(CoreMedia)
import AVFoundation
import CoreMedia

/// 190v s34: AVAssetTrack -> SourceFacts (the colorprobe.py equivalent) and the proxy's colour tags. UNCOMPILED (no Mac): CMFormatDescription extension keys are the documented
/// kCMFormatDescriptionExtension_* constants; the string -> ffmpeg-name tables below are from memory of the CoreMedia/AVFoundation constant values (they match 1:1 for the tags the
/// proxy writer takes). A tag that is not in a table maps to "unknown" (never to a refuse verdict); an HDR file whose transfer is missing from the format description would slip
/// through, which is why Dolby Vision is also detected from the dvcC/dvvC atoms.
enum SourceFormatProbe {
    static let transferNames = ["ITU_R_709_2": "bt709", "SMPTE_ST_2084_PQ": "smpte2084", "ITU_R_2100_HLG": "arib-std-b67", "SMPTE_ST_428_1": "smpte428", "ITU_R_2020": "bt2020-10", "IEC_sRGB": "iec61966-2-1", "Linear": "linear", "SMPTE_240M_1995": "smpte240m"]
    static let primariesNames = ["ITU_R_709_2": "bt709", "SMPTE_C": "smpte170m", "EBU_3213": "bt470bg", "P3_D65": "smpte432", "DCI_P3": "smpte431", "ITU_R_2020": "bt2020"]
    static let matrixNames = ["ITU_R_709_2": "bt709", "ITU_R_601_4": "smpte170m", "ITU_R_2020": "bt2020nc", "SMPTE_240M_1995": "smpte240m"]
    static let dvFourCCs: Set<String> = ["dvhe", "dvh1", "dva1", "dvav", "dav1"]

    private static func fourCC(_ v: UInt32) -> String {
        String(bytes: [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)], encoding: .ascii) ?? ""
    }
    private static func ext(_ fd: CMFormatDescription, _ key: String) -> Any? { CMFormatDescriptionGetExtension(fd, extensionKey: key as CFString) }

    static func facts(url: URL) -> SourceFacts? {
        guard let t = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return nil }
        return facts(track: t)
    }
    static func facts(track t: AVAssetTrack) -> SourceFacts {
        var f = SourceFacts()
        let pt = t.preferredTransform
        f.rotation = SourceFormat.rotation(a: Double(pt.a), b: Double(pt.b), c: Double(pt.c), d: Double(pt.d))
        f.width = Int(abs(t.naturalSize.width).rounded()); f.height = Int(abs(t.naturalSize.height).rounded())
        if f.rotation == 90 || f.rotation == 270 { swap(&f.width, &f.height) }                 // naturalSize is the DISPLAY-rotated size on some SDKs: take storage from the format description below when present
        f.avgFps = Double(t.nominalFrameRate)
        let mfd = t.minFrameDuration; if mfd.isValid, mfd.seconds > 0 { f.maxFps = 1.0 / mfd.seconds }
        // 195k: sample-PTS deltas for the grid-consistency VFR check (the minFrameDuration metadata above quantizes
        // to whole ms after a stream copy and false-refuses known-CFR sources). AVSampleCursor/makeSampleCursor
        // names are the documented AVFoundation API (UNCOMPILED, no Mac - same status as the rest of this file).
        if t.canProvideSampleCursors,let cursor = t.makeSampleCursor(presentationTimeStamp: .zero) {
            var deltas: [Double] = []
            var prev = cursor.presentationTimeStamp.seconds
            while cursor.stepInPresentationOrder(byCount: 1) == 1 {
                let pts = cursor.presentationTimeStamp.seconds
                deltas.append((pts - prev) * 1000.0)
                prev = pts
            }
            f.sampleDeltasMs = deltas
        }
        guard let first = t.formatDescriptions.first else { return f }
        let fd = first as! CMFormatDescription
        let dim = CMVideoFormatDescriptionGetDimensions(fd); if dim.width > 0, dim.height > 0 { f.width = Int(dim.width); f.height = Int(dim.height) }
        if let n = ext(fd, kCMFormatDescriptionExtension_TransferFunction as String) as? String { f.transfer = transferNames[n] ?? "unknown" }
        if let n = ext(fd, kCMFormatDescriptionExtension_ColorPrimaries as String) as? String { f.primaries = primariesNames[n] ?? "unknown" }
        if let n = ext(fd, kCMFormatDescriptionExtension_YCbCrMatrix as String) as? String { f.matrix = matrixNames[n] ?? "unknown" }
        if let fr = ext(fd, kCMFormatDescriptionExtension_FullRangeVideo as String) as? Bool { f.fullRange = fr }
        if let par = ext(fd, kCMFormatDescriptionExtension_PixelAspectRatio as String) as? [String: Any],
           let h = (par[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber)?.doubleValue,
           let v = (par[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber)?.doubleValue, h > 0, v > 0 { f.sar = h / v }
        let atoms = ext(fd, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String) as? [String: Any] ?? [:]
        f.dolbyVision = dvFourCCs.contains(fourCC(CMFormatDescriptionGetMediaSubType(fd))) || atoms["dvcC"] != nil || atoms["dvvC"] != nil
        let hv = (atoms["hvcC"] as? Data).map { [UInt8]($0) }, av = (atoms["avcC"] as? Data).map { [UInt8]($0) }
        f.bitDepth = SourceFormat.bitDepth(hvcC: hv, avcC: av)
        return f
    }

    /// AVVideoColorProperties for the proxy writer: the source's own tags when all three are present and SDR, else nil (untagged proxy, the writer's documented default).
    static func colorProperties(track t: AVAssetTrack) -> [String: String]? {
        guard let first = t.formatDescriptions.first else { return nil }
        let fd = first as! CMFormatDescription
        guard let p = ext(fd, kCMFormatDescriptionExtension_ColorPrimaries as String) as? String, let tf = ext(fd, kCMFormatDescriptionExtension_TransferFunction as String) as? String,
              let m = ext(fd, kCMFormatDescriptionExtension_YCbCrMatrix as String) as? String, !SourceFormat.hdrTransfers.contains(transferNames[tf] ?? "") else { return nil }
        return [AVVideoColorPrimariesKey: p, AVVideoTransferFunctionKey: tf, AVVideoYCbCrMatrixKey: m]
    }
    static func colorProperties(url: URL) -> [String: String]? { AVURLAsset(url: url).tracks(withMediaType: .video).first.flatMap { colorProperties(track: $0) } }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// s36 (1): Spherical Video V2 + stereo-mode (left-right) tag for a finished vr180 render_shot mp4, so any other player that opens the cache file reads it as
/// 180x180 side-by-side equirect. Pure byte work on the mp4 box tree, no AVFoundation. Default OFF (UserDefaults gor.3d.sphericalTag, SphericalTag.defaultsKey): it changes the file bytes,
/// never a decoded frame, and the player-side look no longer depends on it (vr180-look-plan-lock). Mirrors Tests/SphericalTag/spherical_tag_test.py, which runs the
/// same layout on a real mp4. UNCOMPILED on a Mac; AVAssetWriter's own moov placement is unverified (both placements are handled).
enum SphericalTag {
    static let defaultsKey = "gor.3d.sphericalTag"
    private static func box(_ type: String, _ body: [UInt8]) -> [UInt8] { be32(UInt32(8 + body.count)) + Array(type.utf8) + body }
    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]
    }
    private static func rd32(_ d: [UInt8], _ i: Int) -> UInt32 {
        (UInt32(d[i]) << 24) | (UInt32(d[i + 1]) << 16) | (UInt32(d[i + 2]) << 8) | UInt32(d[i + 3])
    }
    private static func rd64(_ d: [UInt8], _ i: Int) -> UInt64 {
        (UInt64(rd32(d, i)) << 32) | UInt64(rd32(d, i + 4))
    }

    /// st3d (stereo_mode 2 = left-right) + sv3d (svhd, proj > prhd, equi with 180 x 180 bounds: left = right = 90 deg of 360).
    static func tagBoxes() -> [UInt8] {
        let st3d = box("st3d", be32(0) + [UInt8(2)])
        let svhd = box("svhd", be32(0) + Array("gor".utf8) + [0])
        let prhd = box("prhd", be32(0) + be32(0) + be32(0) + be32(0))
        let equi = box("equi", be32(0) + be32(0) + be32(0) + be32(0x4000_0000) + be32(0x4000_0000))
        return st3d + box("sv3d", svhd + box("proj", prhd + equi))
    }

    private struct B { let type: String; let start: Int; let end: Int; let body: Int }
    private static func children(_ d: [UInt8], _ from: Int, _ to: Int) -> [B]? {
        var out: [B] = [], i = from
        while i + 8 <= to {
            let size = Int(rd32(d, i)), type = String(decoding: d[(i + 4)..<(i + 8)], as: UTF8.self)
            if size == 0 || size == 1 || size < 8 || i + size > to { return nil }          // 64-bit and to-end boxes are not handled: leave the file alone
            out.append(B(type: type, start: i, end: i + size, body: i + 8)); i += size
        }
        return out
    }

    /// The patched bytes, or nil on any doubt (unknown layout, 64-bit box size). Already tagged = same bytes.
    static func patched(_ d: [UInt8]) -> [UInt8]? {
        guard let top = children(d, 0, d.count), let moov = top.first(where: { $0.type == "moov" }) else { return nil }
        if containsTag(Array(d[moov.start..<moov.end])) { return d }
        var chain: [B] = [moov], cur = moov
        for name in ["trak", "mdia", "minf", "stbl", "stsd"] {
            guard let kids = children(d, cur.body, cur.end), let n = kids.first(where: { $0.type == name }) else { return nil }
            chain.append(n); cur = n
        }
        let stsd = cur, stbl = chain[chain.count - 2]
        guard let entries = children(d, stsd.body + 8, stsd.end), let entry = entries.first(where: { ["hvc1", "hev1", "avc1", "avc3"].contains($0.type) }) else { return nil }
        let add = tagBoxes()
        var o = Array(d[0..<entry.end]) + add + Array(d[entry.end...])
        for b in chain + [entry] {
            let at = b.start, sz = rd32(d, at) + UInt32(add.count)
            o.replaceSubrange(at..<(at + 4), with: be32(sz))
        }
        if let mdatOffset = top.first(where: { $0.type == "mdat" })?.start, case let moovOffset = moov.start, moovOffset < mdatOffset {   // moov before mdat: every chunk offset moves
            guard let kids = children(o, stbl.body, stbl.end + add.count) else { return nil }
            for k in kids where k.type == "stco" || k.type == "co64" {
                let n = Int(rd32(o, k.body + 4)), wide = k.type == "co64"
                for j in 0..<n {
                    let p = k.body + 8 + j * (wide ? 8 : 4)
                    if wide { let v = rd64(o, p) + UInt64(add.count); o.replaceSubrange(p..<(p + 8), with: be32(UInt32(v >> 32)) + be32(UInt32(v & 0xFFFF_FFFF))) }
                    else { o.replaceSubrange(p..<(p + 4), with: be32(rd32(o, p) + UInt32(add.count))) }
                }
            }
        }
        return o
    }
    private static func containsTag(_ m: [UInt8]) -> Bool {
        let t = Array("st3d".utf8)
        return m.indices.dropLast(3).contains { Array(m[$0..<($0 + 4)]) == t }
    }

    /// After a finished render: tags `url` in place (write to a sibling, then replace). false = left untouched (flag off, not vr180, or any failure): the file plays exactly as before.
    @discardableResult static func apply(to url: URL, plan: RenderedShotPlan) -> Bool {
        guard plan.output == .vr180, UserDefaults.standard.bool(forKey: SphericalTag.defaultsKey), let data = try? Data(contentsOf: url), let out = patched([UInt8](data)), out.count != data.count else { return false }
        let tmp = url.appendingPathExtension("tagging")
        guard (try? Data(out).write(to: tmp)) != nil else { try? FileManager.default.removeItem(at: tmp); return false }
        return (try? FileManager.default.replaceItemAt(url, withItemAt: tmp)) != nil
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190v s20 (r2): the content-independent half of s3d_surround and the footprint test of s3d_fill's edge-run fill, computed once per geometry on the CPU in float64
/// (the same maths as tools/depth_analysis/reference_render.py footprint_mask / _surround_soft_vec). Why on the CPU: the nearest-footprint extension chooses WHICH footprint pixel
/// every outside pixel copies using only the mask (never the colours), so it is a gather map; the distance blend weight is also mask-only. The GPU then does the
/// colour work (normalised pre-blur, gather, box blur, blend). Pure Foundation: compiled and tested against the Python reference on Linux.
final class SurroundGeometry {
    let ow: Int, oh: Int
    /// 1 = canvas pixel whose direction lands inside the source frustum (the film footprint).
    let inside: [UInt8]
    var allInside: Bool { !inside.contains(0) }
    /// s31 (d): bounding box of the footprint as (x0, y0, w, h); the full canvas when the footprint is empty. The surround pre-blur is dispatched over this box only.
    var footprintBox: SIMD4<UInt32> {
        var x0 = ow, y0 = oh, x1 = -1, y1 = -1
        for y in 0..<oh { for x in 0..<ow where inside[y * ow + x] != 0 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        if x1 < 0 { return SIMD4<UInt32>(0, 0, UInt32(ow), UInt32(oh)) }
        return SIMD4<UInt32>(UInt32(x0), UInt32(y0), UInt32(x1 - x0 + 1), UInt32(y1 - y0 + 1))
    }

    init(w: Int, h: Int, f: Double, conv: Double, ow: Int, oh: Int) {
        self.ow = ow; self.oh = oh
        var m = [UInt8](repeating: 0, count: ow * oh)
        for y in 0..<oh {
            let lat = (0.5 - (Double(y) + 0.5) / Double(oh)) * Double.pi, cl = cos(lat), sl = sin(lat)
            for x in 0..<ow {
                let lon = ((Double(x) + 0.5) / Double(ow) - 0.5) * Double.pi - conv
                let dx = sin(lon) * cl, dy = sl, dz = cos(lon) * cl, dzc = max(dz, 1e-4)
                let sx = f * dx / dzc + Double(w) * 0.5, sy = Double(h) * 0.5 - f * dy / dzc
                if dz > 0 && sx >= 0 && sx < Double(w) && sy >= 0 && sy < Double(h) { m[y * ow + x] = 1 }
            }
        }
        inside = m
    }

    /// Per canvas pixel: the flat index of the footprint pixel whose (pre-blurred) value it copies (itself inside the footprint), -1 where the extension never reaches
    /// (empty footprint). Exact port of the reference's pass structure: 8 directions in the fixed (dy, dx) scan order, each pass reads the state at its start
    /// ("take = unfilled & neighbour filled"), sweeps repeat until a whole sweep takes nothing. Sparse (only pixels next to the filled set are visited).
    private(set) lazy var sourceIndex: [Int32] = {
        let n = ow * oh
        var idx = [Int32](repeating: -1, count: n), filled = [Bool](repeating: false, count: n)
        var active: [Int32] = [], queued = [Bool](repeating: false, count: n)
        for i in 0..<n where inside[i] != 0 { idx[i] = Int32(i); filled[i] = true }
        func enqueueNeighbours(_ p: Int) {
            let y = p / ow, x = p % ow
            for j in -1...1 { for i in -1...1 where !(j == 0 && i == 0) {
                let yy = y + j, xx = x + i
                if yy < 0 || yy >= oh || xx < 0 || xx >= ow { continue }
                let q = yy * ow + xx
                if !filled[q] && !queued[q] { queued[q] = true; active.append(Int32(q)) }
            } }
        }
        for p in 0..<n where filled[p] { enqueueNeighbours(p) }       // O(n) once; the first sweep's candidates
        var progressed = true
        while progressed && !active.isEmpty {
            progressed = false
            for j in -1...1 { for i in -1...1 where !(j == 0 && i == 0) {
                var takes: [(Int32, Int32)] = []
                for q32 in active {
                    let q = Int(q32); if filled[q] { continue }
                    let y = q / ow + j, x = q % ow + i
                    if y < 0 || y >= oh || x < 0 || x >= ow { continue }
                    let s = y * ow + x
                    if filled[s] { takes.append((q32, idx[s])) }
                }
                if takes.isEmpty { continue }
                progressed = true
                for (q, src) in takes { idx[Int(q)] = src; filled[Int(q)] = true }
                for (q, _) in takes { enqueueNeighbours(Int(q)) }
                active = active.filter { !filled[Int($0)] }
                for q in active { queued[Int(q)] = true }
            } }
        }
        return idx
    }()

    /// r4 (CONTRACT-190v s28/s28b): nearest footprint pixel + L1 distance by the reference's slice-shift BFS, ported step for step. Up to 121 iterations; each runs the four
    /// directions (dy, dx) = (-1,0), (1,0), (0,-1), (0,1) in that order; a direction compares dist[y,x] with dist[y+dy, x+dx] + 1 on a SNAPSHOT (numpy computes the whole
    /// slice before assigning), the strictly smaller one wins and copies the source's index. No wrap-around (unlike the r3 dilation). Unreached pixels keep dist 1e9 and index (0, 0).
    /// The in-place loops below reproduce the snapshot by walking against the shift direction, so a pixel never reads a value written in the same direction pass.
    static let bfsSteps = 121, bfsInf: Int32 = 1_000_000_000
    private(set) lazy var nearest: (index: [Int32], dist: [Int32]) = {
        let n = ow * oh, INF = SurroundGeometry.bfsInf
        var dist = [Int32](repeating: INF, count: n), idx = [Int32](repeating: 0, count: n)
        for i in 0..<n where inside[i] != 0 { dist[i] = 0; idx[i] = Int32(i) }
        let dirs: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for _ in 0..<SurroundGeometry.bfsSteps {
            var changed = false
            for (dy, dx) in dirs {
                let y0 = max(0, -dy), y1 = oh + min(0, -dy), x0 = max(0, -dx), x1 = ow + min(0, -dx)     // destination ranges
                if y0 >= y1 || x0 >= x1 { continue }
                // source = destination + (dy, dx): iterate destinations away from the source side so the source is still the snapshot value
                let ys: [Int] = dy > 0 ? Array(y0..<y1) : Array((y0..<y1).reversed()), xs: [Int] = dx > 0 ? Array(x0..<x1) : Array((x0..<x1).reversed())
                let yOrder = dy == 0 ? Array(y0..<y1) : ys, xOrder = dx == 0 ? Array(x0..<x1) : xs
                for y in yOrder { for x in xOrder {
                    let d = y * ow + x, s = (y + dy) * ow + (x + dx)
                    if dist[s] >= INF { continue }              // rd = 1e9 + 1 is never < dst (<= 1e9)
                    let rd = dist[s] + 1
                    if rd < dist[d] { dist[d] = rd; idx[d] = idx[s]; changed = true }
                } }
            }
            if !changed { break }
        }
        return (idx, dist)
    }()
    var nearIndex: [Int32] { nearest.index }

    /// Per pixel (t1, t2, wcorr, vert), float32 x 4. t1 = clip((dist - 1) / 39, 0, 1) (R1 -> R2), t2 = clip((dist - 40) / 80, 0, 1) (R2 -> far trend), wcorr = clip(1 - dist / 24, 0, 1)
    /// (r4 boundary-correction fade), dist = the BFS L1 distance above (unreached 1e9: t1 = t2 = 1, wcorr = 0). vert = 1 where |y - cy| >= |x - cx| (cy, cx = footprint centroid,
    /// float64): the wide-short 256x64 far-trend window (pixels above/below), else 0 = tall-narrow 64x256. Computed in float64 like the reference.
    static let d2 = 40.0, d3 = 120.0, dCorr = 24.0
    private(set) lazy var blendWeights: [Float] = {
        let n = ow * oh, dist = nearest.dist
        var sy = 0.0, sx = 0.0, cnt = 0.0
        for y in 0..<oh { for x in 0..<ow where inside[y * ow + x] != 0 { sy += Double(y); sx += Double(x); cnt += 1 } }
        let cy = cnt > 0 ? sy / cnt : 0, cx = cnt > 0 ? sx / cnt : 0
        var w = [Float](repeating: 0, count: 4 * n)
        for y in 0..<oh { for x in 0..<ow {
            let i = y * ow + x, dd = Double(dist[i])
            w[4 * i] = Float(min(max((dd - 1.0) / (SurroundGeometry.d2 - 1.0), 0.0), 1.0))
            w[4 * i + 1] = Float(min(max((dd - SurroundGeometry.d2) / (SurroundGeometry.d3 - SurroundGeometry.d2), 0.0), 1.0))
            w[4 * i + 2] = Float(min(max(1.0 - dd / SurroundGeometry.dCorr, 0.0), 1.0))
            w[4 * i + 3] = abs(Double(y) - cy) >= abs(Double(x) - cx) ? 1 : 0
        } }
        return w
    }()

    // Small cache: the geometry only changes with the shot's fov, the canvas size or the eye's convergence angle.
    private static var cache: [(key: [Double], geo: SurroundGeometry)] = []
    private static let lock = NSLock()
    static func cached(w: Int, h: Int, f: Double, conv: Double, ow: Int, oh: Int) -> SurroundGeometry {
        let key = [Double(w), Double(h), f, conv, Double(ow), Double(oh)]
        lock.lock(); defer { lock.unlock() }
        if let hit = cache.first(where: { $0.key == key }) { return hit.geo }
        let g = SurroundGeometry(w: w, h: h, f: f, conv: conv, ow: ow, oh: oh)
        cache.append((key, g)); if cache.count > 4 { cache.removeFirst() }
        return g
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// CONTRACT-190v s2 / prepare_film._analyze_shot: per-shot horizontal FoV from MoGe-2 keyframes (stride 12 frames). Pure Foundation (tested on Linux).
enum FovTrackBuilder {
    static let keyframeStride = 12
    static let confSpreadDeg = 15.0
    struct Entry: Equatable { var startPTS: Double; var endPTS: Double; var hfovDeg: Double?; var confidence: Double; var keyframes: [(pts: Double, fov: Double)]
        static func == (a: Entry, b: Entry) -> Bool { a.startPTS == b.startPTS && a.endPTS == b.endPTS && a.hfovDeg == b.hfovDeg && a.confidence == b.confidence && a.keyframes.map { $0.pts } == b.keyframes.map { $0.pts } }
        /// fov_track.json shot object: {start_pts, end_pts, hfov_deg, confidence, keyframe_values: [[pts, fov]]}
        var json: [String: Any] {
            ["start_pts": startPTS, "end_pts": endPTS, "hfov_deg": hfovDeg.map { $0 as Any } ?? NSNull(), "confidence": confidence,
             "keyframe_values": keyframes.map { [($0.pts * 1e6).rounded() / 1e6, $0.fov] }]
        }
    }
    /// Frame indices (relative to the shot start) to run MoGe on.
    static func keyframeIndices(frames: Int) -> [Int] { Array(stride(from: 0, to: max(0, frames), by: keyframeStride)) }
    static func median(_ v: [Double]) -> Double { let s = v.sorted(), n = s.count; return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2 }
    /// >= 2 keyframes: median fov, confidence = 1 - min(1, population stdev / 15 deg); 1 keyframe: that fov, confidence 0; none: nil, 0.
    static func entry(startFrame: Int, endFrame: Int, fps: Double, keyframes: [(frame: Int, fov: Double)]) -> Entry {
        let kf = keyframes.filter { $0.fov.isFinite && $0.fov > 0 && $0.fov < 180 }.map { (pts: Double($0.frame) / fps, fov: $0.fov) }
        let fovs = kf.map { $0.fov }
        var hfov: Double? = nil, conf = 0.0
        if fovs.count >= 2 {
            let mean = fovs.reduce(0, +) / Double(fovs.count), sd = (fovs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(fovs.count)).squareRoot()
            conf = 1.0 - min(1.0, sd / confSpreadDeg); hfov = median(fovs)
        } else if let f = fovs.first { hfov = f }
        return Entry(startPTS: Double(startFrame) / fps, endPTS: Double(endFrame) / fps, hfovDeg: hfov, confidence: conf, keyframes: kf)
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190v s36 port of tools/depth_analysis/output_modes.py: the output mode set behind the 3D menu. Pure Foundation (compiled and run on Linux, Tests/Stereo3DKernel/output_modes_swift_test.py).
/// The Metal side (Stereo3DKernel.swift) renders the eye with the perspective branch (flat modes) or the equirect180 branch (vr180) and packs with `s3d_pack`.
enum OutputMode: String, CaseIterable {
    case fullSBS = "full_sbs", halfSBS = "half_sbs", overUnder = "over_under", anaglyph, vr180

    static let screenDeg = 75.0                  // the flat modes' virtual screen (perspective fov across the eye width)
    /// Flat display -> full_sbs (full per-eye resolution, universal player support); headset -> vr180.
    static func defaultMode(headset: Bool) -> OutputMode { headset ? .vr180 : .fullSBS }
    /// Menu / prefs spelling. The legacy "sbs" of the pre-s36 menu was the vr180 placeholder; it now means the flat default, full_sbs.
    static func parse(_ s: String) -> OutputMode? { s == "sbs" ? .fullSBS : OutputMode(rawValue: s) }
    var isFlat: Bool { self != .vr180 }
    /// Square VR180 eye side (mirrors ThreeDRenderCoordinator.eyeN).
    static func eyeN(sourceHeight h: Int) -> Int { max(256, min(4096, h - h % 2)) }
    /// (W, H) of the packed output frame for a source of w x h (half_sbs needs an even eye width: callers pass the even-padded proxy size).
    func canvasSize(srcW w: Int, srcH h: Int) -> (w: Int, h: Int) {
        switch self {
        case .fullSBS: return (2 * w, h)
        case .halfSBS: return (w, h)
        case .overUnder: return (w, 2 * h)
        case .anaglyph: return (w, h)
        case .vr180: let n = OutputMode.eyeN(sourceHeight: h); return (2 * n, n)
        }
    }
    /// Per-eye render canvas: the source size for the flat modes, N x N for vr180.
    func eyeSize(srcW w: Int, srcH h: Int) -> (w: Int, h: Int) { isFlat ? (w, h) : (OutputMode.eyeN(sourceHeight: h), OutputMode.eyeN(sourceHeight: h)) }
    /// Frame-packing metadata the player needs (MODE_METADATA): mpv stereo-mode name (nil = ordinary 2D), SAR stretch for half_sbs, spherical V2 for vr180.
    var mpvStereoMode: String? {
        switch self { case .fullSBS, .halfSBS, .vr180: return "sbsl"; case .overUnder: return "abl"; case .anaglyph: return nil }
    }
    var playbackSARStretch: Double { self == .halfSBS ? 2.0 : 1.0 }          // player stretches horizontally 2:1
    var sphericalV2: Bool { self == .vr180 }
    /// s3d_pack mode code: 0 side by side, 1 half sbs, 2 over under, 3 anaglyph (vr180 packs with s3d_sbs).
    var packCode: UInt32 { switch self { case .fullSBS, .vr180: return 0; case .halfSBS: return 1; case .overUnder: return 2; case .anaglyph: return 3 } }

    static let duboisL: [[Float]] = [[0.437, 0.449, 0.164], [-0.062, -0.062, -0.024], [-0.048, -0.050, -0.017]]
    static let duboisR: [[Float]] = [[-0.011, -0.032, -0.007], [0.377, 0.761, 0.009], [-0.026, -0.093, 1.234]]
    /// Per-eye size recovered from a flat canvas (vr180 source reprojected to a flat mode: the eye size is the canvas divided back by the pack).
    func eyeW(canvasW w: Int) -> Int { self == .fullSBS ? w / 2 : w }
    func eyeH(canvasH h: Int) -> Int { self == .overUnder ? h / 2 : h }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t part I: what the viewer sees when. Open = 2D at once. When rendered 3D covers the playhead the picture crossfades 2D -> 3D
/// over `fadeSeconds`. A seek into the rendered range shows 3D instantly (no fade); a seek outside it drops to 2D until it is covered.
/// A shot change clears the per-shot state (depth / FoV are never carried across a cut). Pure state: the caller supplies time and coverage.
struct ThreeDPresentation: Equatable {
    static let fadeSeconds = 0.5
    enum Phase: Equatable { case flat, fading(since: Double), solid }
    private(set) var phase: Phase = .flat
    private(set) var shot: Int?

    /// 0 = 2D only, 1 = 3D only.
    func alpha(now: Double) -> Double {
        switch phase {
        case .flat: return 0
        case .solid: return 1
        case .fading(let t0): return max(0, min(1, (now - t0) / ThreeDPresentation.fadeSeconds))
        }
    }

    /// `covered`: rendered 3D exists for the playhead. `shot`: shot index at the playhead (nil = unknown). `seeked`: the playhead jumped.
    /// Returns true when per-shot depth/FoV state must be dropped (shot changed).
    @discardableResult
    mutating func update(now: Double, covered: Bool, shot newShot: Int?, seeked: Bool, enabled: Bool) -> Bool {
        let cut = newShot != shot
        shot = newShot
        guard enabled, covered else { phase = .flat; return cut }
        switch phase {
        case .flat: phase = seeked ? .solid : .fading(since: now)
        case .fading(let t0): if now - t0 >= ThreeDPresentation.fadeSeconds { phase = .solid }
        case .solid: break
        }
        return cut
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
import CoreGraphics
import Darwin

/// Original software-decoded samples, never a rendered screenshot. No user media is saved.
/// cropdetect is advisory: its line average can miss a single bright bar pixel. The exact luma
/// bounding union below vetoes every crop that would discard a sampled nonblack pixel.
enum SourcePixelBounds {
    struct Bounds: Equatable {
        var x0: Int; var y0: Int; var x1: Int; var y1: Int
        func union(_ b: Bounds) -> Bounds {
            Bounds(x0:min(x0,b.x0),y0:min(y0,b.y0),x1:max(x1,b.x1),y1:max(y1,b.y1))
        }
    }
    /// Early-apply rule for stream scans: at least `minCount` non-black frames whose bounds all agree with their union
    /// within `tol` px on every edge. Returns the union, else nil. The final scan result is never narrower than this
    /// (later frames can only widen the union), so refining after an early apply never cuts more.
    static let earlyMinCount = 3
    static let fallbackMinCount = 2   // time-budget fallback never applies from a single frame
    static let earlyTolerance = 8
    /// Seconds a stream scan may run before it applies the best frames it has (then keeps refining). Derived from how long
    /// frames really take on this machine now (disk, swarm, thermal state): twice the time of three frames, clamped.
    static func firstApplyBudget(avgSample: Double) -> Double { min(25, max(8, 6 * avgSample)) }
    static func consistent(_ members: [Bounds], tol: Int = earlyTolerance, minCount: Int = earlyMinCount) -> Bounds? {
        guard members.count >= minCount, let first = members.first else { return nil }
        let u = members.dropFirst().reduce(first) { $0.union($1) }
        for m in members where abs(m.x0-u.x0) > tol || abs(m.y0-u.y0) > tol || abs(m.x1-u.x1) > tol || abs(m.y1-u.y1) > tol { return nil }
        return u
    }
    /// Diagnostic only: luma mean/max (8-bit-equivalent, relative to black) of rows near the measured top and bottom bound, so a log shows the
    /// real bar level. Reads the first plane of little-endian 16-bit samples (luma for yuv444p16le and gray16le).
    static func edgeRows(_ bytes: Data, width: Int, height: Int, bounds b: Bounds, black: Int, bits: Int, gray: Bool) -> String {
        let planeBytes = width * height * 2
        guard width > 0, height > 0, bytes.count >= planeBytes else { return "unavailable" }
        let shift = max(0, 16 - bits), unit = 1 << max(0, bits - 8)
        var out: [String] = []
        bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            func stat(_ y: Int) -> String {
                guard y >= 0, y < height else { return "-" }
                var sum = 0, mx = 0, x = 0
                while x < width { let i = (y * width + x) * 2; let v = Int(UInt16(p[i]) | UInt16(p[i + 1]) << 8) >> shift; sum += v; mx = max(mx, v); x += 1 }
                let mean = Double(sum) / Double(width) - Double(black), top = mx - black
                return String(format: "y%d=%.1f/%d", y, mean / Double(unit), top / unit)
            }
            for d in [-24, -12, -4, 0, 4, 12, 24] { out.append("T" + stat(b.y0 + d)) }
            for d in [-24, -12, -4, 0, 4, 12, 24] { out.append("B" + stat(b.y1 - 1 - d)) }
        }
        return out.joined(separator: " ")
    }
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static func scan(_ bytes: Data, width: Int, height: Int, threshold: UInt16, speck: Int = 0, strong: UInt16 = 0) -> Bounds? {
        guard width > 0, height > 0, bytes.count >= width * height * 2 else { return nil }
        var result: Bounds?
        bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            @inline(__always) func sample(_ y: Int, _ x: Int) -> UInt16 {
                let i = (y * width + x) * 2
                return UInt16(p[i]) | UInt16(p[i + 1]) << 8
            }
            // First bright x in [from, to) or -1; last bright x in [from, to) or -1.
            func first(_ y: Int, _ from: Int, _ to: Int) -> Int {
                var x = from
                while x < to { if sample(y, x) > threshold { return x }; x += 1 }
                return -1
            }
            func last(_ y: Int, _ from: Int, _ to: Int) -> Int {
                var x = to - 1
                while x >= from { if sample(y, x) > threshold { return x }; x -= 1 }
                return -1
            }
            func rowIsContent(_ y: Int) -> Bool {
                if speck <= 0 || strong <= threshold { return first(y, 0, width) >= 0 }
                var n = 0
                var x = 0
                while x < width {
                    let v = sample(y, x)
                    if v > strong { return true }
                    if v > threshold { n += 1; if n > speck { return true } }
                    x += 1
                }
                return false
            }
            var top = -1
            var y = 0
            while y < height { if rowIsContent(y) { top = y; break }; y += 1 }
            guard top >= 0 else { return }
            var bottom = top
            y = height - 1
            while y > top { if rowIsContent(y) { bottom = y; break }; y -= 1 }
            var x0 = width, x1 = 0
            for row in [top, bottom] {
                x0 = min(x0, first(row, 0, width))
                x1 = max(x1, last(row, 0, width) + 1)
            }
            if top + 1 < bottom {
                y = top + 1
                while y < bottom {
                    if x0 == 0 && x1 == width { break }
                    if x0 > 0 { let f = first(y, 0, x0); if f >= 0 { x0 = f } }
                    if x1 < width { let l = last(y, x1, width); if l >= 0 { x1 = l + 1 } }
                    y += 1
                }
            }
            result = Bounds(x0: x0, y0: top, x1: x1, y1: bottom + 1)
        }
        return result
    }
    static func scanHalves(_ bytes:Data,width:Int,height:Int,threshold:UInt16,topBottom:Bool=false)->[Bounds]? {
        guard width%2==0,height%2==0,bytes.count>=width*height*2 else{return nil}
        if topBottom {
            var eyes:[Bounds]=[]
            for eye in 0...1 {
                let a=eye*width*height
                let bound=scan(bytes.subdata(in:a..<(a+width*height)),width:width,height:height/2,threshold:threshold)
                    ?? Bounds(x0:width,y0:height/2,x1:0,y1:0)
                eyes.append(bound)
            }
            return eyes
        }
        var halves:[Bounds]=[]
        for eye in 0...1 {
            var half=Data();half.reserveCapacity(width*height)
            for y in 0..<height {
                let a=(y*width+eye*width/2)*2
                half.append(bytes.subdata(in:a..<(a+width)))
            }
            let bound=scan(half,width:width/2,height:height,threshold:threshold)
                ?? Bounds(x0:width/2,y0:height,x1:0,y1:0)
            halves.append(bound)
        }
        return halves
    }
    /// A display viewport may crop the common local eye rectangle without touching a packed seam.
    static func eyeViewport(_ eyes:[Bounds],width:Int,height:Int,topBottom:Bool) -> CGRect? {
        guard eyes.count==2 else {return nil}
        let w=topBottom ? width:width/2,h=topBottom ? height/2:height
        let common=eyes[0].union(eyes[1])
        guard common.x1>common.x0,common.y1>common.y0 else {return nil}
        let b=outward(common,width:w,height:h,stereo:false)
        return CGRect(x:Double(b.x0)/Double(w),y:Double(b.y0)/Double(h),width:Double(b.x1-b.x0)/Double(w),height:Double(b.y1-b.y0)/Double(h))
    }
    static func outward(_ b: Bounds, width: Int, height: Int, stereo: Bool,topBottom:Bool=false) -> Bounds {
        // A rectangular video-crop cannot remove each eye's inner horizontal edge without cutting
        // the seam. Keep all SBS columns; top/bottom bounds are the union of both complete halves.
        if topBottom {
            return Bounds(x0:(b.x0/2)*2,y0:0,x1:min(width,((b.x1+1)/2)*2),y1:height)
        }
        return Bounds(x0:stereo ? 0 : (b.x0 / 2) * 2, y0:(b.y0 / 2) * 2,
               x1:stereo ? width : min(width,((b.x1 + 1) / 2) * 2),
               y1:min(height,((b.y1 + 1) / 2) * 2))
    }
}

final class SourcePixelCropScanner {
    private let lock = NSLock()
    private var epoch = 0
    private var active: Process?
    /// Work already measured on a stream (wt) survives a cancel: bars are a static property of the file, so the union of
    /// samples from an interrupted scan stays valid for the next scan of the same file, and a decisive rect that was
    /// computed but dropped by a cancel is handed to the next scan of that file instead of being thrown away.
    /// key = path|stereo|topBottom|rounded duration of the scan that wrote it; dims = "WxH pix range" once the stream was probed ("" if never).
    private struct Carry { var key: String; var dims: String; var at: Double; var bounds: SourcePixelBounds.Bounds?; var members: [SourcePixelBounds.Bounds]; var sampled: Int; var undelivered: Bool; var rect: CGRect?; var done: [Double]; var ep: Int }   // ep = epoch of the scan that wrote it: an older scan never overwrites it
    private var carry: Carry?
    private var newestKey: String?   // key of the most recently started stream scan: a stale scan may not store under another key
    private static let carryTTL: Double = 180   // seconds; older measurements are re-measured, never replayed
    private(set) var decodedWidth=0
    private(set) var decodedHeight=0
    private(set) var perEyeAspect:Double?
    private var lastDeliveredEpoch = -1   // epoch of the scan that last delivered a decisive result: an older scan may not store after it
    /// Forget everything carried (explicit manual Detect re-measures from scratch).
    /// Samples decoded so far by the scan now running (0 when none started or none decoded yet).
    private(set) var liveSamples = 0
    /// True when a scan for the file on screen is already producing samples: a manual Detect then lets it finish
    /// instead of killing it (the capture showed repeated clicks cancelling every scan at 19-27 s of ~57 s).
    func hasProgress() -> Bool { lock.lock(); defer { lock.unlock() }; return liveSamples > 0 }
    func dropCarry() { lock.lock(); if carry?.undelivered != true { carry = nil }; lock.unlock() }   // a decisive rect that was never delivered stays as the fallback for an indecisive manual scan
    func cancel() {
        lock.lock(); epoch += 1; let p = active; lock.unlock()
        if let p, p.isRunning { kill(p.processIdentifier,SIGKILL) }
    }
    private func valid(_ e: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return epoch == e }
    private func run(_ binary: String, _ args: [String], epoch e: Int, cap: Int, killAfter: Double = 20) -> (Data,Data,Int32)? {
        guard valid(e) else { return nil }
        let readerArgs = CropHTTPReader.arguments(args)
        let args = URL(fileURLWithPath: binary).lastPathComponent == "ffmpeg" ? FFmpegAnalysisThreads.arguments(readerArgs) : readerArgs
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath:binary); p.arguments = args
        // Background work: lowest priority (nice execs, same pid, so kill still hits ffmpeg).
        if FileManager.default.isExecutableFile(atPath:"/usr/bin/nice") { p.executableURL = URL(fileURLWithPath:"/usr/bin/nice"); p.arguments = ["-n","19",binary] + args }
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        lock.lock(); guard epoch == e else { lock.unlock(); return nil }; active = p
        do { try p.run() } catch { active = nil; lock.unlock(); return nil }; lock.unlock()
        let deadline = DispatchWorkItem { if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+killAfter,execute:deadline)
        let g = DispatchGroup(); let stderr = LockedData()
        g.enter(); DispatchQueue.global(qos:.utility).async {
            while true { let c = err.fileHandleForReading.availableData; if c.isEmpty { break }; stderr.append(c,cap:262144) }
            g.leave()
        }
        var data = Data(); var oversized = false
        while true {
            let c = out.fileHandleForReading.availableData; if c.isEmpty { break }
            if data.count + c.count <= cap { data.append(c) } else { oversized = true; if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
        }
        p.waitUntilExit(); g.wait(); deadline.cancel()
        lock.lock(); if active === p { active = nil }; lock.unlock()
        guard valid(e), !oversized else { return nil }
        return (data,stderr.value(),p.terminationStatus)
    }
    private final class LockedData {
        let lock = NSLock(); var data = Data()
        func append(_ c: Data, cap: Int) { lock.lock(); if data.count+c.count <= cap { data.append(c) }; lock.unlock() }
        func value() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
    func scan(path: String, duration: Double, stereo: Bool,topBottom:Bool=false, viewportOnly:Bool=false, caller: String = "", fresh: Bool = false, positions samplePositions:(()->[Double]?)?=nil, interim: ((CGRect, Double)->Void)? = nil, completion: @escaping (CGRect?,Bool,Double)->Void) {
        cancel(); perEyeAspect=nil;lock.lock(); let e = epoch; liveSamples = 0; lock.unlock()
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self else { return }
            // Only transfer relay probes wait. The worker is cancellable throughout;
            // no process exists and no upstream range is opened while deferred.
            func decode(_ binary: String, _ args: [String], epoch: Int, cap: Int, killAfter: Double) -> (Data,Data,Int32)? {
                var deferred = false
                while !TransferProbeAdmission.admits(path) {
                    guard self.valid(e) else { return nil }
                    if !deferred { print("[cropdetect] transfer probe deferred: forward buffer below 15s or stale/stalled"); deferred = true }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if deferred { print("[cropdetect] transfer probe admitted: forward buffer healthy") }
                return self.run(binary,args,epoch:epoch,cap:cap,killAfter: killAfter)
            }
            let ffmpeg = GORResources.vendorPath("ffmpeg/bin/ffmpeg")
            let ffprobe = GORResources.vendorPath("ffmpeg/bin/ffprobe")
            let wt: Bool = samplePositions != nil   // stream (wt) scan: slow opens, partial file
            let rwTimeout: String = wt ? "30000000" : "5000000" // [attribution comment elided]
            let killAfter: Double = wt ? 45 : 20
            let key = "\(path)|\(stereo)|\(topBottom)|\(Int(duration.rounded()))"
            var idDims = ""   // set once the stream is probed
            func carryUsable(_ c: Carry?) -> Carry? { guard let c, c.key == key, ProcessInfo.processInfo.systemUptime - c.at <= SourcePixelCropScanner.carryTTL else { return nil }; return c }
            print("[cropdetect] scan start caller=\(caller.isEmpty ? "?" : caller) wt=\(wt) stereo=\(stereo) file=\((path as NSString).lastPathComponent)")
            func finish(_ rect: CGRect?, _ decisive: Bool, _ why: String = "") {
                DispatchQueue.main.async {
                    if self.valid(e) {
                        self.lock.lock(); let c = self.carry; if decisive { self.carry = nil; self.lastDeliveredEpoch = e }; self.lock.unlock()
                        if !decisive, wt, let c = carryUsable(c), c.undelivered {
                            print("[cropdetect] scan ended without a result (\(why)); delivering the decisive rect measured earlier")
                            self.lock.lock(); self.carry = nil; self.lock.unlock(); completion(c.rect,true,1); return
                        }
                        if !decisive { print("[cropdetect] scan finished indecisive: \(why.isEmpty ? "no reason recorded" : why)") }
                        completion(rect,decisive,decisive ? 1 : 0)
                    } else if decisive, wt, !stereo {
                        self.lock.lock()
                        let mine = (self.newestKey == key) && e > self.lastDeliveredEpoch && (self.carry == nil || (self.carry?.key == key && (self.carry?.sampled ?? 0) == 0 && (self.carry?.ep ?? -1) < e))   // never overwrite another file's or a newer scan's carry
                        if mine { self.carry = Carry(key: key, dims: idDims, at: ProcessInfo.processInfo.systemUptime, bounds: nil, members: [], sampled: 0, undelivered: true, rect: rect, done: [], ep: e) }
                        self.lock.unlock()
                        print(mine ? "[cropdetect] decisive result was cancelled before delivery; kept for the next scan of this file" : "[cropdetect] decisive result was cancelled before delivery and a newer scan owns the state; dropped")
                    }
                }
            }
            self.lock.lock(); var c0: Carry? = wt ? carryUsable(self.carry) : nil; let keepFallback: Bool = fresh && c0?.undelivered == true; if fresh { c0 = nil }; if wt { if c0 == nil && !keepFallback { self.carry = nil }; self.newestKey = key }; self.lock.unlock()
            guard FileManager.default.isExecutableFile(atPath:ffmpeg) else { finish(nil,false,"ffmpeg not executable"); return }
            var w=0,h=0,d=duration,pix="",range="",sar=1.0
            if FileManager.default.isExecutableFile(atPath:ffprobe),
               let probe=decode(ffprobe,["-v","error","-rw_timeout",rwTimeout,"-select_streams","v:0","-show_streams","-show_format","-of","json",path],epoch:e,cap:262144,killAfter:killAfter),probe.2==0,
               let root=try? JSONSerialization.jsonObject(with:probe.0) as? [String:Any],
               let stream=(root["streams"] as? [[String:Any]])?.first {
                w=stream["width"] as? Int ?? 0;h=stream["height"] as? Int ?? 0
                let format=root["format"] as? [String:Any]
                d=Double(format?["duration"] as? String ?? "") ?? duration
                let parts=(stream["sample_aspect_ratio"] as? String ?? "1:1").split(separator:":").compactMap{Double($0)}
                if parts.count==2,parts[1]>0 {sar=parts[0]/parts[1]}
                pix=stream["pix_fmt"] as? String ?? "";range=stream["color_range"] as? String ?? ""
            } else {
// [attribution comment elided]
// [attribution comment elided]
                guard let meta=decode(ffmpeg,["-hide_banner","-nostdin","-hwaccel","none","-rw_timeout",rwTimeout,"-i",path,"-map","0:v:0","-frames:v","0","-an","-sn","-f","null","-"],epoch:e,cap:4096,killAfter:killAfter) else { finish(nil,false,"probe and metadata open failed (timeout or no data)");return }
                let text=String(data:meta.1,encoding:.utf8) ?? ""
                guard let line=text.components(separatedBy:"\n").first(where:{$0.contains("Stream #") && $0.contains("Video:")}) else {finish(nil,false,"no video stream line in metadata");return}
                func captures(_ pattern:String,_ text:String) -> [String] {
                    guard let re=try? NSRegularExpression(pattern:pattern),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return []}
                    return (1..<m.numberOfRanges).compactMap {Range(m.range(at:$0),in:text).map{String(text[$0])}}
                }
                let size=captures(#"(?:,| )([0-9]{2,5})x([0-9]{2,5})(?:[ ,\[])"#,line)
                guard size.count==2 else {finish(nil,false,"no frame size in metadata");return}
                w=Int(size[0]) ?? 0;h=Int(size[1]) ?? 0
                pix=captures(#", ([a-z0-9]+)(?:\(|,)"#,line).first ?? ""
                range=line.contains("(pc") ? "pc" : "tv"
                if d<=0 {
                    let times=captures(#"Duration: ([0-9]+):([0-9]+):([0-9.]+)"#,text)
                    if times.count==3 {d=(Double(times[0]) ?? 0)*3600+(Double(times[1]) ?? 0)*60+(Double(times[2]) ?? 0)}
                }
            }
            guard w>0,h>0,w<=16384,h<=16384,w*h<=50000000 else {finish(nil,false,"unusable frame size \(w)x\(h)");return}
            idDims = "\(w)x\(h) \(pix) \(range)"
            if let c = c0, c.dims != "" , c.dims != idDims {   // same path/duration but a different stream: nothing carried applies
                print("[cropdetect] carried measurement is for a different stream (\(c.dims) vs \(idDims)); discarded")
                c0 = nil; self.lock.lock(); self.carry = nil; self.lock.unlock()
            }
            if let c = c0, c.undelivered { print("[cropdetect] replaying the decisive rect measured earlier (same file, \(idDims), probed just now)"); finish(c.rect,true); return }
            let decodedW=w,decodedH=h
            DispatchQueue.main.async { if self.valid(e) { self.decodedWidth=decodedW;self.decodedHeight=decodedH } }
            let bits:Int = pix.contains("16") ? 16 : pix.contains("14") ? 14 : pix.contains("12") ? 12 : pix.contains("10") ? 10 : pix.contains("9") ? 9 : 8
            let full=range=="pc" || pix.hasPrefix("yuvj") || pix.hasPrefix("rgb") || pix.hasPrefix("gbr") || pix.hasPrefix("gray")
            let black=full ? 0 : 16*(1 << max(0,bits-8))
            // Margins are 8-bit-equivalent luma levels: +2 / +12 levels at ANY bit depth. They used to be raw codes, which at 10 bit
            // is only 0.5 / 3 levels, so a dithered or HDR->SDR near-black letterbox bar (a few codes above black) read as picture.
            let levelUnit = 1 << max(0,bits-8)
            let threshold=UInt16(min(65535,(black+2*levelUnit)*(1 << max(0,16-bits))))
            let strongThreshold=UInt16(min(65535,(black+12*levelUnit)*(1 << max(0,16-bits))))   // clearly non-black: never ignored as a speck
            let speckTolerance=0   // never discard even one above-threshold content pixel as a bar speck
            // Split into typed statements: one nil-coalescing + ternary + map-closure expression made the compiler time out.
            let overridePositions: [Double]? = samplePositions?()
            var positions: [Double] = [0.0]
            if let op = overridePositions { positions = op }
            else if d > 0 { positions = (0..<40).map { (i: Int) -> Double in let x: Double = d * (Double(i) + 0.5); let y: Double = x / 40.0; return max(0.0, min(d - 0.001, y)) } }
            if wt, let c = c0, c.sampled > 0 {
                let unseen: [Double] = positions.filter { (p: Double) -> Bool in !c.done.contains { (d: Double) -> Bool in abs(d - p) < 4 } }   // new frames, not repeats of carried ones
                let pool: [Double] = unseen.count >= 3 ? unseen : positions
                positions = Array(pool.prefix(max(3, positions.count - c.sampled)))
            }
            let transferBatching = TransferProbeAdmission.isSource(path)
            var wtBatching = CropDetector.isWTPlayback(path) // same bounded cached source, not a rendered screenshot
            if transferBatching { positions.sort() } // same exact positions, bounded chronological container reuse
            var batchedFrames: [Double: Data] = [:]
            var done: [Double] = c0?.done ?? []
            let window: Double = (positions.max() ?? 0) - (positions.min() ?? 0)   // samples carried from a cancelled scan count: repeated restarts converge instead of re-measuring everything
            var all: SourcePixelBounds.Bounds? = c0?.bounds; var sampled: Int = c0?.sampled ?? 0   // carried samples from an interrupted scan of the same stream
            var halves:[SourcePixelBounds.Bounds]?
            var members: [SourcePixelBounds.Bounds] = c0?.members ?? []; var interimSent = false; let scanStart = ProcessInfo.processInfo.systemUptime; var sampleSum = 0.0, sampleN = 0
            let rgbVeto = pix.hasPrefix("rgb") || pix.hasPrefix("bgr") || pix.hasPrefix("gbr") || pix.isEmpty
            let scanDeadline=ProcessInfo.processInfo.systemUptime+240 // 2 decode threads at nice 19 take longer than the old 120 s budget allowed for the same 40 samples
            for (positionIndex, t) in positions.enumerated() {
                guard self.valid(e) else { print("[cropdetect] scan cancelled mid-run after \(sampled) of \(positions.count) samples (new scan or cancel)"); return }
                if ProcessInfo.processInfo.systemUptime>=scanDeadline { break }
                // Software decode only. cropdetect runs on original decoded samples, no crop/scale/shader.
                // yuv444p16le preserves full-resolution luma code values for the exact safety veto.
                let vf = "cropdetect=limit=\(black+2):round=2:reset=0:skip=0"
                let sourceGray=pix.hasPrefix("gray")
                // The exact veto, stereo bounds and edge diagnostics read ONLY Y.
                // First make the very same YUV16 samples as the old output, then
                // extract Y without range expansion or downscale. RGB stays on
                // the old path and remains vetoed, never guessed from luma.
                let extractLuma = !sourceGray && !rgbVeto
                let outputGray = sourceGray || extractLuma
                let rawPixelFormat=outputGray ? "gray16le" : "yuv444p16le"
                let outputFilter = extractLuma ? vf + ",format=yuv444p16le,extractplanes=y" : vf
                let expectedBytes=w*h*(outputGray ? 2 : 6)
                let args = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(t),"-i",path,"-map","0:v:0","-an","-sn","-dn","-vf",outputFilter,"-frames:v","1","-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                let sampleBegan = ProcessInfo.processInfo.systemUptime
                if transferBatching, batchedFrames[t] == nil {
                    let batch = TransferProbeAdmission.cropBatch(positions,index:positionIndex,frameBytes:expectedBytes)
                    if batch.count > 1, let first = batch.first, let last = batch.last {
                        let select = TransferProbeAdmission.cropSelection(batch)
                        let batchArgs = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(first),"-i",path,"-t",String(last-first+0.5),"-map","0:v:0","-an","-sn","-dn","-vf","select='\(select)',\(outputFilter)","-vsync","0","-frames:v",String(batch.count),"-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                        if let decoded = decode(ffmpeg,batchArgs,epoch:e,cap:expectedBytes*batch.count+65536,killAfter:killAfter), decoded.2 == 0, decoded.0.count == expectedBytes*batch.count {
                            for (i, at) in batch.enumerated() { batchedFrames[at] = decoded.0.subdata(in:i*expectedBytes..<(i+1)*expectedBytes) }
                            print("[cropdetect] transfer container batch frames=\(batch.count) span_s=\(last-first) opens=1")
                        } else { print("[cropdetect] transfer container batch incomplete; bounded single-frame fallback") }
                    }
                }
                if wtBatching, batchedFrames[t] == nil {
                    let cachedBytes = batchedFrames.values.reduce(0) { $0 + $1.count }
                    let pending = Array(positions[positionIndex...]).filter { batchedFrames[$0] == nil }
                    let batch = BoundedCropFrameBatch.plan(pending, current:t,
                        frameBytes:expectedBytes, cachedBytes:cachedBytes)
                    if batch.count > 1, let first=batch.first, let last=batch.last {
                        let select = BoundedCropFrameBatch.selection(batch)
                        let batchArgs = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(first),"-i",path,"-t",String(last-first+0.5),"-map","0:v:0","-an","-sn","-dn","-vf","select='\(select)',\(outputFilter)","-vsync","0","-frames:v",String(batch.count),"-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                        if let decoded=decode(ffmpeg,batchArgs,epoch:e,cap:expectedBytes*batch.count+65536,killAfter:killAfter),
                           decoded.2 == 0, decoded.0.count == expectedBytes*batch.count {
                            for (i,at) in batch.enumerated() {
                                batchedFrames[at]=decoded.0.subdata(in:i*expectedBytes..<(i+1)*expectedBytes)
                            }
                            print("[cropdetect] wt bounded batch frames=\(batch.count) span_s=\(last-first) opens=1 cache_bytes=\(cachedBytes+expectedBytes*batch.count)")
                        } else {
                            wtBatching = false // at most one failed batch; never repeated speculative opens
                            print("[cropdetect] wt batch incomplete; original single-target fallback for rest of scan")
                        }
                    }
                }
                let decoded: (Data,Data,Int32)?
                if let frame = batchedFrames.removeValue(forKey:t) { decoded = (frame,Data(),0) }
                else { decoded = decode(ffmpeg,args,epoch:e,cap:expectedBytes+65536,killAfter:killAfter) }
                guard let decoded, decoded.2 == 0, decoded.0.count == expectedBytes else { continue }
                sampleSum += ProcessInfo.processInfo.systemUptime - sampleBegan; sampleN += 1
                done.append(t); sampled += 1; self.lock.lock(); if self.epoch == e { self.liveSamples = sampled }; self.lock.unlock()
                // A fully black sampled frame adds no content. An unreadable frame is not claimed sampled.
                if stereo,let current=SourcePixelBounds.scanHalves(decoded.0,width:w,height:h,threshold:threshold,topBottom:topBottom) {
                    halves=halves.map{[$0[0].union(current[0]),$0[1].union(current[1])]} ?? current
                }
                if let b = SourcePixelBounds.scan(decoded.0,width:w,height:h,threshold:threshold,speck:speckTolerance,strong:strongThreshold) {
                    all = all.map { $0.union(b) } ?? b
                    print("[cropdetect] edge rows sample=\(sampled) t=\(Int(t))s bounds y=\(b.y0)..\(b.y1) (8-bit-eq mean/max, black=\(black), levelUnit=\(levelUnit)): \(SourcePixelBounds.edgeRows(decoded.0,width:w,height:h,bounds:b,black:black,bits:bits,gray:outputGray))")
                    if wt, !stereo, !rgbVeto { members.append(b); if members.count > 12 { members.removeFirst() } }
                }
                // Speed: apply as soon as three frames agree, then keep refining (the union only widens).
                let elapsed: Double = ProcessInfo.processInfo.systemUptime - scanStart
                let avgSample: Double = sampleSum / Double(max(1, sampleN))
                let late: Bool = elapsed >= SourcePixelBounds.firstApplyBudget(avgSample: avgSample)
                var best: SourcePixelBounds.Bounds? = SourcePixelBounds.consistent(members)
                if best == nil, late, members.count >= SourcePixelBounds.fallbackMinCount, let f = members.first { best = members.dropFirst().reduce(f) { (a: SourcePixelBounds.Bounds, b: SourcePixelBounds.Bounds) -> SourcePixelBounds.Bounds in a.union(b) } }
                // Overcut guard: the frames behind an early apply must span at least half of the planned window, so one quiet corner of the cache cannot define the crop.
                let covered: Double = (done.max() ?? 0) - (done.min() ?? 0)
                if window > 0, covered < 0.5 * window { best = nil }
                if wt, !stereo, !rgbVeto, !interimSent, let interim, let u0 = best {
                    let u: SourcePixelBounds.Bounds = all.map { $0.union(u0) } ?? u0   // never narrower than everything measured so far (members is capped at 12, all is not)
                    let ci = SourcePixelBounds.outward(u,width:w,height:h,stereo:stereo,topBottom:topBottom)
                    if !(ci.x0 == 0 && ci.y0 == 0 && ci.x1 == w && ci.y1 == h) {
                        interimSent = true
                        let ir = CGRect(x:Double(ci.x0)/Double(w),y:Double(ci.y0)/Double(h),width:Double(ci.x1-ci.x0)/Double(w),height:Double(ci.y1-ci.y0)/Double(h))
                        print("[cropdetect] early apply after \(sampled) samples (\(members.count) non-black, \(SourcePixelBounds.consistent(members) != nil ? "agree" : "time budget reached, best available")): bounds=\(ci.x0),\(ci.y0)-\(ci.x1),\(ci.y1) of \(w)x\(h); refining on the remaining samples")
                        DispatchQueue.main.async { if self.valid(e) { interim(ir, -1) } }   // confidence < 0 marks an early apply (the final result still follows)
                    }
                }
                if wt, !stereo { self.lock.lock(); if self.epoch == e && !(self.carry?.undelivered == true && self.carry?.key == key) { self.carry = Carry(key: key, dims: idDims, at: ProcessInfo.processInfo.systemUptime, bounds: all, members: members, sampled: sampled, undelivered: false, rect: nil, done: done, ep: e) }; self.lock.unlock() }   // progress survives a cancel
            }
            let needSamples: Int = samplePositions == nil ? 1 : min(3, positions.count)
            guard sampled >= needSamples, let b = all else { print("[cropdetect] scan produced no samples: positions=\(positions.count) \(w)x\(h) \(pix)"); finish(nil,false,"\(sampled) of \(needSamples) needed samples decoded"); return }
            // RGB -> luma conversion can hide a chromatic nonblack source pixel. Until exact RGB
            // bounds are supported, veto crop rather than claim original-pixel preservation there.
            if pix.hasPrefix("rgb") || pix.hasPrefix("bgr") || pix.hasPrefix("gbr") || pix.isEmpty {
                finish(nil,true);return
            }
            if let eyes=halves {
                let common=eyes[0].union(eyes[1])
                let sx=topBottom ? 1.0 : (Double(w)/Double(h)>=3 ? 1.0:2.0)
                let aspect=Double(common.x1-common.x0)*sx*sar/Double(common.y1-common.y0)
                DispatchQueue.main.async {if self.valid(e){self.perEyeAspect=aspect}}
            }
            let c = SourcePixelBounds.outward(b,width:w,height:h,stereo:stereo,topBottom:topBottom)
            let rect = CGRect(x:Double(c.x0)/Double(w),y:Double(c.y0)/Double(h),
                              width:Double(c.x1-c.x0)/Double(w),height:Double(c.y1-c.y0)/Double(h))
            print("[cropdetect] scan done: sampled=\(sampled)/\(positions.count) bounds=\(c.x0),\(c.y0)-\(c.x1),\(c.y1) of \(w)x\(h) override=\(samplePositions != nil)")
            GeomTrace.log("sourceCrop", "{\"k\":\"sourceCrop\",\"samples\":\(sampled),\"requested\":40,\"unsampledMayBeCut\":true,\"sbs\":\(stereo),\"sbsHorizontalPreserved\":true}")
            if viewportOnly,stereo,let eyes=halves,let viewport=SourcePixelBounds.eyeViewport(eyes,width:w,height:h,topBottom:topBottom) {
                print("[cropdetect] verified per-eye viewport \(viewport) source pixels unchanged")
                finish(viewport == CGRect(x:0,y:0,width:1,height:1) ? nil:viewport,true)
            } else {finish(c.x0 == 0 && c.y0 == 0 && c.x1 == w && c.y1 == h ? nil : rect,true)}
        }
    }
}

// BEGIN relocated CropHTTPReader.swift (195w 2a, behavior unchanged)
import Foundation

/// A source-pixel reader is not the player. Label only gor's loopback WT
/// inputs; leave the URL, seek, frames, decoder and every output byte alone.
enum CropHTTPReader {
    static func arguments(_ args: [String]) -> [String] {
        let input = args.firstIndex(of: "-i").map { $0 + 1 } ?? (args.count - 1)
        guard args.indices.contains(input), let url = URLComponents(string: args[input]),
              url.scheme == "http", ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
              url.queryItems?.contains(where: { $0.name == "gor_stream" }) == true else { return args }
        var result = args
        result.insert(contentsOf: ["-headers", "X-Gor-Reader: analysis\r\n"], at: args.firstIndex(of: "-i") ?? input)
        return result
    }
}
// END relocated CropHTTPReader.swift

// BEGIN relocated FFmpegAnalysisThreads.swift (195w 2a, behavior unchanged)
import Foundation

/// Analysis-only FFmpeg worker pools. Input decoder options and every filter,
/// selected frame, pixel format and crop vote remain unchanged. FFmpeg's
/// decoder -threads option does not bound its separate filter/output pools.
enum FFmpegAnalysisThreads {
    static func arguments(_ args: [String]) -> [String] {
        var result = ["-filter_threads", "1", "-filter_complex_threads", "1"] + args
        if let f = result.lastIndex(of: "-f"), f + 1 < result.count,
           result[f + 1] == "rawvideo", result.last == "pipe:1" {
            result.insert(contentsOf: ["-threads", "1"], at: result.count - 1)
        }
        return result
    }
}
// END relocated FFmpegAnalysisThreads.swift

// BEGIN relocated BoundedCropFrameBatch.swift (195y G2, behavior unchanged)

// One scan's bounded raw-luma cache. This changes neither requested timestamps nor
// their processing order. It only shares a short container decode among targets.
// On incomplete output the scanner retains its existing single-target path.
enum BoundedCropFrameBatch {
    static let byteLimit = 64 * 1024 * 1024
    static let spanLimit = 2.0
    static func plan(_ remaining: [Double], current: Double, frameBytes: Int,
                     cachedBytes: Int = 0) -> [Double] {
        guard current.isFinite, current >= 0, frameBytes > 0,
              cachedBytes >= 0, cachedBytes <= byteLimit,
              frameBytes <= byteLimit - cachedBytes else { return [] }
        let capacity = (byteLimit - cachedBytes) / frameBytes
        var selected = [current]
        for p in remaining.filter({ $0.isFinite && $0 >= 0 }).sorted(by: {
            abs($0-current) == abs($1-current) ? $0 < $1 : abs($0-current) < abs($1-current)
        }) {
            if selected.count >= capacity { break }
            if selected.contains(p) { continue }
            let low = min(selected.min()!, p), high = max(selected.max()!, p)
            if high - low <= spanLimit { selected.append(p) }
        }
        return selected.sorted()
    }
    static func selection(_ positions: [Double]) -> String {
        guard let first = positions.first else { return "0" }
        return positions.map { position in
            let delta = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), position-first)
            return "gte(t,\(delta))*(isnan(prev_selected_t)+lt(prev_selected_t,\(delta)))"
        }.joined(separator: "+")
    }
}
// END relocated BoundedCropFrameBatch.swift

// BEGIN relocated CropAcceptPolicy.swift (195y G2, behavior unchanged)

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum CropAcceptPolicy {
    static let maxPlayheadDrift: Double = 60
    static let minKeptFraction: Double = 0.55
    static func plausible(rect: CGRect?, stereo: Bool) -> Bool {
        guard let r = rect, stereo else { return true }
        return Double(r.width) >= minKeptFraction && Double(r.height) >= minKeptFraction
    }
    static func accepts(rect: CGRect?, stereo: Bool, startPlayhead: Double?, nowPlayhead: Double, stream: Bool, manual: Bool) -> Bool {
        if rect != nil, stream, !manual, let s = startPlayhead, abs(nowPlayhead - s) > maxPlayheadDrift {
            print("[cropdetect] result dropped: stream scan began at \(Int(s)) s, playhead now \(Int(nowPlayhead)) s (stale samples)")
            return false
        }
        if !plausible(rect: rect, stereo: stereo) {
            print("[cropdetect] result dropped: crop would remove most of a stereo frame \(String(describing: rect))")
            return false
        }
        return true
    }
}

/// Playhead at the moment the current automatic scan was started.
final class CropScanGuard {
    static let shared = CropScanGuard()
    private(set) var startPlayhead: Double?
    func begin(playhead: Double) { startPlayhead = playhead }
}
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum WTCropSamples {
    static let sampleCount = 12
    /// Distance kept from the end of a range so the one frame decoded after the seek is also downloaded.
    static let tailMargin = 1.5
    static let minRange = 3.0

    /// Cache tail used by automatic detection: the newest downloaded seconds. Film start and end credits are usually
    /// black; what was downloaded last is the part most likely to show the real picture, and it moves as the cache grows.
    static let tailWindow = 240.0
    /// Manual Detect looks this far either side of the frame on screen.
    static let manualHalfSpan = 12.0

    /// Usable seconds of each downloaded range (tail margin kept), sorted by start.
    static func usable(_ ranges: [(Double, Double)]) -> [(Double, Double)] {
        ranges.filter { $0.0.isFinite && $0.1.isFinite && $0.1 - $0.0 >= minRange }
            .map { (max(0, $0.0), $0.1 - tailMargin) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }
    }

    /// Evenly spaced positions over the union length of the given segments (chronological order).
    static func spread(_ segs: [(Double, Double)], count: Int) -> [Double] {
        let total = segs.reduce(0.0) { $0 + ($1.1 - $1.0) }
        guard total > 0, count > 0 else { return [] }
        var out: [Double] = []
        for i in 0..<count {
            var u = total * (Double(i) + 0.5) / Double(count)
            for r in segs {
                let len = r.1 - r.0
                if u <= len { out.append(r.0 + u); break }
                u -= len
            }
        }
        return out
    }

    /// Pure: evenly spaced positions over the union length of the usable ranges. Empty when no range is usable.
    static func positions(ranges: [(Double, Double)], count: Int = sampleCount) -> [Double] {
        spread(usable(ranges), count: count)
    }

    /// Sampling order: start at the sample nearest `seed` (newest frame for automatic scans, the frame on screen for manual), then
    /// always take the sample farthest from those already taken. The first three frames therefore span the whole window, so an early
    /// apply cannot be decided by one quiet corner of the cache.
    static func spreadOrder(_ ps: [Double], seed: Double) -> [Double] {
        var rest: [Double] = ps
        var out: [Double] = []
        guard let si = rest.indices.min(by: { (a: Int, b: Int) -> Bool in abs(rest[a] - seed) < abs(rest[b] - seed) }) else { return [] }
        out.append(rest.remove(at: si))
        while !rest.isEmpty {
            let taken: [Double] = out
            let gaps: [Double] = rest.map { (p: Double) -> Double in taken.map { (t: Double) -> Double in abs(t - p) }.min() ?? 0 }
            guard let fi = gaps.indices.max(by: { (a: Int, b: Int) -> Bool in gaps[a] < gaps[b] }) else { break }
            out.append(rest.remove(at: fi))
        }
        return out
    }

    /// Pure plan for a stream scan. Manual: around the playhead (the frame the user sees), inside the downloaded range
    /// nearest to it, nearest samples first. Automatic: the last `tailWindow` seconds of the downloaded ranges, newest
    /// first. Every position is inside a downloaded range with the tail margin kept. Empty when nothing is usable.
    static func plan(ranges: [(Double, Double)], playhead: Double?, manual: Bool, count: Int = sampleCount) -> [Double] {
        let segs = usable(ranges)
        guard !segs.isEmpty, count > 0 else { return [] }
        if manual, let now = playhead, now.isFinite {
            func dist(_ r: (Double, Double)) -> Double { now < r.0 ? r.0 - now : (now > r.1 ? now - r.1 : 0) }
            guard let r = segs.min(by: { dist($0) < dist($1) }) else { return [] }
            let c = min(max(now, r.0), r.1)
            let lo = max(r.0, c - manualHalfSpan), hi = min(r.1, c + manualHalfSpan)
            guard hi > lo else { return [] }
            return spreadOrder(spread([(lo, hi)], count: count), seed: c)
        }
        var tail: [(Double, Double)] = []
        var left = tailWindow
        for r in segs.reversed() {
            let take = min(r.1 - r.0, left)
            tail.append((r.1 - take, r.1)); left -= take
            if left <= 0 { break }
        }
        let picked: [Double] = spread(tail.reversed(), count: count)
        return spreadOrder(picked, seed: picked.max() ?? 0)
    }

    /// Positions for a wt playback path from the running player; nil for any other source (scanner keeps its
    /// whole-file positions) or when the player cannot say anything about what is downloaded.
    static func positions(path: String, mainIPCPath: String?, manual: Bool = false) -> [Double]? {
        guard (CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)), let ipc = mainIPCPath else { return nil }
        let client = IPCClient(path: ipc)
        func property(_ name: String) -> Any? {
            IPCClient.parseFirst(client.queryBatch(MPVCommand.make(["get_property", name]), timeout: 0.5))["data"]
        }
        var ranges: [(Double, Double)] = []
        if let state = property("demuxer-cache-state") as? [String: Any],
           let list = state["seekable-ranges"] as? [[String: Any]] {
            ranges = list.compactMap {
                guard let a = ($0["start"] as? NSNumber)?.doubleValue, let b = ($0["end"] as? NSNumber)?.doubleValue else { return nil }
                return (a, b)
            }
        }
        let playhead = (property("time-pos") as? NSNumber)?.doubleValue
        let spread = plan(ranges: ranges, playhead: playhead, manual: manual)
        // One line per scan so a capture shows what the player said was on disk and where the scan will look.
        let span = ranges.map { String(format: "%.0f-%.0f", $0.0, $0.1) }.joined(separator: ",")
        print("[cropdetect] wt samples: ranges=[\(span)] positions=\(spread.count) mode=\(manual ? "manual-around-playhead" : "cache-tail") playhead=\(playhead.map { String(format: "%.1f", $0) } ?? "?")")
        if !spread.isEmpty { return spread }
        if let now = (property("time-pos") as? NSNumber)?.doubleValue, now.isFinite, now >= 0 { return playedFallback(now: now) }
        return nil
    }
}


extension WTCropSamples {
    /// No seekable range reported: the seconds just played were read through the server, so sample those.
    /// Up to three distinct seconds (now-4, now-2, now-0.5 clamped at 0); the scanner needs min(3, count) frames.
    static func playedFallback(now: Double) -> [Double] {
        var out: [Double] = []
        for back in [4.0, 2.0, 0.5] {
            let t = max(0, now - back)
            if !out.contains(where: { abs($0 - t) < 0.25 }) { out.append(t) }
        }
        return out
    }

    /// Pure summary used by diagnostics and tests: the first and last sampled second, or nil when none.
    static func span(of positions: [Double]) -> (first: Double, last: Double)? {
        guard let a = positions.min(), let b = positions.max() else { return nil }
        return (a, b)
    }

    /// True when every position lies inside one of the ranges with the tail margin kept, i.e. the whole
    /// sample set is time the player already read through the wt server.
    static func allDownloaded(_ positions: [Double], in ranges: [(Double, Double)]) -> Bool {
        positions.allSatisfy { p in ranges.contains { p >= $0.0 && p <= $0.1 - tailMargin } }
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// 190t part H: subtitle / OSD depth placement. One distance per subtitle event: the nearest valid depth under the event's box
/// minus a margin, so text never sits behind the picture it overlaps. Constant for the whole event (no per-frame jitter).
/// Depth samples are 10-bit w10 from the depth mp4 (CONTRACT-190v section 1): Z = 256 / (w10 / 1023 * 1024) metres, w10 == 0 = masked.
struct SubtitleDepth {
    static let marginM = 0.10, minZ = 0.30, maxZ = 50.0, fallbackZ = 2.0
    private var placed: [Int: Double] = [:]

    static func metres(w10: Int) -> Double? { w10 > 0 ? 256.0 / (Double(w10) / 1023.0 * 1024.0) : nil }

    /// Pure rule. `w10` = depth samples inside the event box (any order). No valid sample -> fallbackZ.
    static func placement(w10: [Int], margin: Double = marginM) -> Double {
        guard let near = w10.compactMap({ metres(w10: $0) }).min() else { return fallbackZ }
        return min(maxZ, max(minZ, near - margin))
    }

    /// First call for an event id fixes its distance; later calls (other frames of the same event) return the same value.
    mutating func distance(event: Int, w10: @autoclosure () -> [Int]) -> Double {
        if let z = placed[event] { return z }
        let z = SubtitleDepth.placement(w10: w10()); placed[event] = z; return z
    }
    mutating func end(event: Int) { placed.removeValue(forKey: event) }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
#endif

/// 190t H: subtitle depth while a ready 3D shot plays. The existing dial (VR180Controller.subtitleDepthPoints, a dimensionless factor: crossed
/// disparity = eye width * 0.004 * factor for subtitles) is replaced by a factor derived from the rendered geometry: SubtitleDepth.placement
/// of the depth under the subtitle band, then the renderer's own disparity rule (eye offset ipd/2 each way, screen at `convergence`), as a
/// fraction of the picture width f*2*tan(thetaH/2). No per-film constants. Not 3D (or no sample yet) = the user's dial, untouched.
/// Per SHOT, not per event: the subtitle event boxes are not visible at the dial path. The band is a fixed bottom strip of the picture.
final class ThreeDSubtitleDepth {
    static let shared = ThreeDSubtitleDepth()
    static let band = (x0: 0.10, x1: 0.90, y0: 0.78, y1: 0.95), perSubtitleFraction = 0.004, dialLimit = 8.0
    var changed: (() -> Void)?                       // set by the wiring: re-run the subtitle geometry pass
    private let lock = NSLock(), queue = DispatchQueue(label: "gor.3d.subdepth", qos: .utility)
    private var factor: Double?, token = 0

    /// The dial the placement code should use: the 3D-derived factor while a ready 3D shot plays, else `base`.
    static func dial(_ base: Double) -> Double { shared.lock.lock(); defer { shared.lock.unlock() }; return shared.factor ?? base }

    // Prepared-depth experiment only. No new live-plane estimate or GPU readback.
    private var experimental = false
    static var experimentalOn: Bool { shared.lock.lock(); defer {shared.lock.unlock()}; return shared.experimental }
    static func setExperimental(_ on: Bool) {
        shared.lock.lock(); shared.experimental=on
        shared.captionEvent=nil; shared.captionPX=nil; shared.captionTime=nil
        shared.lock.unlock(); shared.changed?()
    }
    private var nearestFraction: Double?, captionEvent: String?, captionPX: Double?, captionTime: Double?
    #if canImport(AVFoundation)
    private var preparedContext: (URL, Double, RenderParams)?
    private var sampleBusy = false
    #endif

    /// A physical-pixel margin, not metres. Elapsed-time form of k=.15 and
    /// .5px/frame at24fps, so geometry calls cannot change smoothing speed.
    static func captionTarget(nearest: Double, width: Double, previous: Double?, dt: Double) -> Double {
        let target = max(0, min(width * 0.010, nearest * width + 1.5))
        guard let previous else { return target }
        let frames = max(0, dt * 24), k = 1 - pow(0.85, frames)
        let step = (target - previous) * k, slew = 0.5 * frames
        return max(0, min(width * 0.010, previous + max(-slew, min(slew, step))))
    }
    static func subtitleFraction(base: Double, width: Double, event: String?, now: Double) -> Double {
        guard experimentalOn, width.isFinite, width > 0 else { return base }
        shared.lock.lock(); defer { shared.lock.unlock() }
        guard let event, let nearest = shared.nearestFraction else {
            shared.captionEvent=nil; shared.captionPX=nil; shared.captionTime=nil; return base
        }
        let previous = shared.captionEvent == event ? shared.captionPX : nil
        let dt = shared.captionTime.map { max(0, now - $0) } ?? 0
        let value = captionTarget(nearest:nearest,width:width,previous:previous,dt:dt)
        shared.captionEvent=event; shared.captionTime=now; shared.captionPX=value
        return value / width
    }

    /// Crossed disparity (positive = nearer than the screen) as a fraction of the picture width.
    static func disparityFraction(z: Double, ipd: Double, convergence: Double?, thetaH: Double) -> Double {
        guard z > 0, ipd > 0, thetaH > 0, thetaH < Double.pi else { return 0 }
        let screenAngle = (convergence ?? 0) > 0 ? 2 * atan2(ipd / 2, convergence!) : 0
        return (2 * atan2(ipd / 2, z) - screenAngle) / (2 * tan(thetaH / 2))
    }
    static func factor(z: Double, ipd: Double, convergence: Double?, thetaH: Double) -> Double {
        max(0, min(dialLimit, disparityFraction(z: z, ipd: ipd, convergence: convergence, thetaH: thetaH) / perSubtitleFraction))
    }

    /// What the render of this shot used (CONTRACT s25/s27): eye offset, convergence plane z_c and near clamp. Under the comfort policy these are per shot
    /// (ipd * B_eff/IPD * strength factor, z_c = shot median depth, z_near); otherwise the fixed prefs values and no clamp.
    struct RenderParams: Equatable { var ipd: Double, convergence: Double?, zNear: Double? }
    /// Pure: exactly the arguments the coordinator hands RenderShotWriter.write (ipd:, convergence:, zNear:), so the subtitle dial follows the same geometry as the picture.
    static func params(ipdM: Double, effectiveIPD: Double, convergenceM: Double?, comfort: ShotComfort?, comfortIPD: Double?) -> RenderParams {
        guard let c = comfort else { return RenderParams(ipd: effectiveIPD, convergence: convergenceM, zNear: nil) }
        return RenderParams(ipd: comfortIPD ?? ipdM * c.depthScale, convergence: c.convergenceM, zNear: c.zNear)
    }
    /// The render clamps scene depth to >= z_near before projecting; the subtitle is placed against the depth the viewer actually sees there.
    static func seenZ(_ z: Double, zNear: Double?) -> Double { zNear.map { max(z, $0) } ?? z }

    func end() { lock.lock(); token += 1; let had = factor != nil; factor = nil
        nearestFraction=nil; captionEvent=nil; captionPX=nil; captionTime=nil
        #if canImport(AVFoundation)
        preparedContext=nil
        #endif
        lock.unlock(); if had { DispatchQueue.main.async { self.changed?() } } }

    #if canImport(AVFoundation)
    /// Samples the depth under the band at `pts` on a utility queue, then sets the factor and asks for one geometry pass.
    /// `render` runs on the utility queue (it may read the whole shot container for the comfort median) and must return what the render of this shot used.
    func begin(depth: URL, pts: Double, thetaH: Double, render: @escaping () -> RenderParams) {
        lock.lock(); token += 1; let t = token; lock.unlock()
        queue.async { [self] in
            let samples = Self.sampleBand(depth, at: pts, rows:Self.experimentalOn ? 4:6)
            let z = SubtitleDepth.placement(w10: samples)
            let r = render()
            let f = Self.factor(z: Self.seenZ(z, zNear: r.zNear), ipd: r.ipd, convergence: r.convergence, thetaH: thetaH)
            lock.lock(); let ok = token == t
            if ok {
                factor = f
                preparedContext=(depth,thetaH,r)
                if experimental {
                    captionEvent=nil; captionPX=nil; captionTime=nil
                    nearestFraction=samples.compactMap { SubtitleDepth.metres(w10:$0) }.min().map {
                        Self.disparityFraction(z:Self.seenZ($0,zNear:r.zNear),ipd:r.ipd,convergence:r.convergence,thetaH:thetaH)
                    }
                }
            }
            lock.unlock()
            if ok { DispatchQueue.main.async { self.changed?() } }
        }
    }

    /// Real mapped playhead from the coordinator; no wall-clock media estimate.
    /// At most one utility sample in flight. end()/new shot fence completion.
    func refreshPrepared(pts: Double) {
        guard Self.experimentalOn, pts.isFinite else { return }
        lock.lock()
        guard !sampleBusy, let (url,theta,r)=preparedContext else { lock.unlock(); return }
        let t=token; sampleBusy=true; lock.unlock()
        queue.async { [self] in
            let samples=Self.sampleBand(url,at:pts,rows:4)
            let nearest=samples.compactMap { SubtitleDepth.metres(w10:$0) }.min().map {
                Self.disparityFraction(z:Self.seenZ($0,zNear:r.zNear),ipd:r.ipd,convergence:r.convergence,thetaH:theta)
            }
            lock.lock(); sampleBusy=false; let ok=token==t
            if ok, let nearest { nearestFraction=nearest }
            lock.unlock()
            if ok, nearest != nil { DispatchQueue.main.async { self.changed?() } }
        }
    }

    /// w10 samples (grid over the band) of the first container frame at/after `pts` (lossless w10, no shift). [] on any failure.
    static func sampleBand(_ url: URL, at pts: Double, rows: Int = 6) -> [Int] {
        guard let f = DZCFile(url: url), let p = f.plane(f.index(atOrAfter: pts)) else { return [] }
        let w = Int(f.meta.width), h = Int(f.meta.height)
        var s: [Int] = []
        for j in 0..<rows { for i in 0..<16 {
            let x = min(w - 1, Int((band.x0 + (band.x1 - band.x0) * (Double(i) + 0.5) / 16) * Double(w)))
            let y = min(h - 1, Int((band.y0 + (band.y1 - band.y0) * (Double(j) + 0.5) / Double(rows)) * Double(h)))
            s.append(Int(p[y * w + x]))
        } }
        return s
    }
    #endif
}

/// Container fps and estimated frame count of the open film, fed from the player's observed properties (PPController results), keyed by path.
final class ThreeDFilmInfo {
    static let shared = ThreeDFilmInfo()
    private let lock = NSLock(); private var path: String?, fps = 0.0, frames = 0
    func set(path: String?, fps: Double?, frames: Int?) {
        lock.lock(); defer { lock.unlock() }
        if path != self.path { self.path = path; self.fps = 0; self.frames = 0 }
        if let f = fps, f.isFinite, f > 0 { self.fps = f }
        if let n = frames, n > 0 { self.frames = n }
    }
    /// (fps, frames) for `film`, nil until both are known for that exact file.
    func info(for film: URL) -> (fps: Double, frames: Int)? {
        lock.lock(); defer { lock.unlock() }
        return path == film.path && fps > 0 && frames > 0 ? (fps, frames) : nil
    }
}
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static var governorEnabled: Bool { UserDefaults.standard.object(forKey: "gorHeatGovernor") as? Bool ?? true }
    /// True while the system reports serious/critical thermal pressure. One
    /// cheap syscall per read; callers are 0.5-10 Hz timers, never per-frame.
    static var thermalPressure: Bool { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
    private static var last: (wall: CFTimeInterval, cpu: Double)?
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import Foundation
#if canImport(AppKit)
import AppKit

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static var launchMasterApplied = false
    private(set) var state = ThreeDExperimentState()
    var send: (String) -> Void = { _ in }
    /// 195h r2-7: fired after an experiment row toggles; ThreeDWiring points it at the coordinator's existing re-render/re-prepare refresh.
    var onExperimentChange: () -> Void = {}
    private var captionsOn = false
    private var allOn: Bool {
        let s = Stereo3DExperiments.snapshot()
        return state.budgetOn && captionsOn && s.fw && s.dof && s.hg && DepthTemporalEMA.isEnabled()
            && DepthModelID.selected() == .dav2_small_coreml && ModelDepthEMA.enabled
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
        print("3D-EXPERIMENT requested reason=\(reason) D=\(state.budgetOn) F=\(captionsOn) options=\(o.renderKeyComponent ?? "off") conv=\(state.convergence) comp=\(state.compression) evidence=request_only prepared_effects=await_render_load")
        fflush(stdout)
    }
    func reapplyIfEnabled() { if state.budgetOn { send(state.budgetCommand) } }
    func install(in parent: NSMenu) {
        let item=NSMenuItem(title:"Experiments (default on)",action:nil,keyEquivalent:"")
        let menu=NSMenu(title:item.title);item.submenu=menu;parent.addItem(item)
        let master=NSMenuItem(title:"All experiments on/off",action:#selector(tap(_:)),keyEquivalent:"e")
        master.keyEquivalentModifierMask=[.command,.control,.option];master.target=self;master.tag=100;menu.addItem(master)
        menu.addItem(.separator())
        for (tag,title) in [(1,"D disparity budget"),(2,"D convergence nearer"),(3,"D convergence farther"),(4,"D compression more"),(5,"D compression less"),(6,"F prepared subtitle depth"),(7,"E floating window"),(8,"G depth defocus (Held-Banks)"),(9,"hole-fill gradient (deterministic)"),(10,"B depth range EMA"),(11,"A depth model: DAV2 CoreML (needs models fetch)"),(12,"A DAV2 temporal EMA")] {
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
        default:break
        }
        return true
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
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
    init(floatingWindow: Bool = false, depthOfField: Bool = false, holeFillGradient: Bool = false, depthRangeEMA: Bool = false, dav2Depth: Bool = false, dav2TemporalEMA: Bool = false) {
        self.floatingWindow = floatingWindow; self.depthOfField = depthOfField; self.holeFillGradient = holeFillGradient
        self.depthRangeEMA = depthRangeEMA; self.dav2Depth = dav2Depth; self.dav2TemporalEMA = dav2TemporalEMA
    }
    var floatingWindow = false, depthOfField = false, holeFillGradient = false, depthRangeEMA = false
    var dav2Depth = false, dav2TemporalEMA = false   // 195h A: depth-model identity (DAV2-Small CoreML) + its temporal EMA
    /// render-key component: nil when every switch is off, so flag-off keys stay byte-identical with the pre-195h strings. Sorted, fixed order.
    var renderKeyComponent: String? {
        let on = [("fw", floatingWindow), ("dof", depthOfField), ("hg", holeFillGradient), ("ema", depthRangeEMA), ("dav2", dav2Depth), ("tempema", dav2TemporalEMA)].filter { $0.1 }.map { $0.0 }   // B's integrated order preserved byte-for-byte; A's tokens append after it
        return on.isEmpty ? nil : "exp-" + on.joined(separator: ".")
    }
    /// 195h r3 + Delivery 5: identity of the switches that change PREPARED depth (B today; item A adds the depth model). Render-only
    /// switches (E/G/hole) are absent: they re-render through the render key, never re-prepare. This is the launcher request's
    /// `experiments` value and the mismatch-nudge identity.
    /// 195h A (Delivery A-1): the DAV2 producer needs no VDA/MoGe kit - loadModels, the windowed probe and the kit gate all key off this.
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
                                           dav2Depth: DepthModelID.selected() == .dav2_small_coreml, dav2TemporalEMA: ModelDepthEMA.enabled)   // lock-backed reads (195h r2-3)
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import AppKit

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    private var calibrationActive = false
    private var calibrationOnly = false
    private var refreshTimer: Timer?
    private var subscribed = false
    private var variationSubscribed = false

    private let store = ThreeDStore.shared

    private var cornerLayout: CornerTuneLayout {
        CornerTuneLayout(charW: Double(PhotonFont.chromeCharW), lineH: Double(PhotonFont.chromeLineH), pad: Double(PhotonFont.chromePad))
    }

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

/// Plain rect so the layout never touches CoreGraphics (Linux has none in Foundation).
struct CornerTuneRect: Equatable {
    var x: Double, y: Double, w: Double, h: Double
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    func intersects(_ o: CornerTuneRect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }
    func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < maxX && py >= y && py < maxY }
    func offsetBy(dx: Double, dy: Double) -> CornerTuneRect { CornerTuneRect(x: x + dx, y: y + dy, w: w, h: h) }
}

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static let spec: [(corner: CornerTuneCorner, letter: String, word: String, key: String, glyphA: String, glyphB: String)] = [
        (.topLeft,     "i", "ipd",   "ipd",         "-", "+"),
        (.topRight,    "d", "depth", "strength",    "-", "+"),
        (.bottomLeft,  "s", "scr",   "screenDepth", "←", "→"),
        (.bottomRight, "s", "size",  "screenSize",  "-", "+"),
    ]

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static func dropdownTop(videoMinY: Double, lineH: Double) -> Double {max(lineH,videoMinY)}

    // The explicitly opened control surface and the calibration marker both follow
    // ordinary chrome visibility. Toggling remains the way the surface is dismissed.
    static func overlayAlpha(calibrationOnly: Bool, chromeAlpha: Double) -> Double {
        chromeAlpha
    }

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static func crosshairFrame(in content: CornerTuneRect, charW: Double, lineH: Double) -> CornerTuneRect {
        CornerTuneRect(x: content.x + (content.w - charW) / 2, y: content.y + (content.h - lineH) / 2, w: charW, h: lineH)
    }

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    static let valueMaxChars: [String: Int] = ["ipd": 4, "strength": 4, "screenDepth": 6, "screenSize": 4]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        let wordX = dx > 0 ? sideX + titleMargin
                           : sideX - titleMargin - charW
        let wordFrame = CornerTuneRect(x: wordX, y: rowY, w: charW, h: lineH)
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        let valueW = Double(max(value.count, CornerTuneLayout.valueFieldChars)) * charW
        let valueX = dx > 0 ? sideX + titleMargin + titleReserve + gap
                            : sideX - titleMargin - titleReserve - gap - valueW
        let valueFrame = CornerTuneRect(x: valueX, y: rowY, w: valueW, h: lineH)
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum ThreeDSelfTest {
    /// The fixture's storage pixels are not its prepared display geometry (ToS has SAR120:89).
    /// Read the same committed sidecar contract as the playback render coordinator.
    struct PreparedGeometry {
        let source: (w: Int, h: Int), depth: (w: Int, h: Int)
        init?(sidecar: [String: Any]) {
            guard let sw = sidecar["source_width"] as? Int, let sh = sidecar["source_height"] as? Int,
                  let dw = sidecar["depth_width"] as? Int, let dh = sidecar["depth_height"] as? Int,
                  sw > 0, sh > 0, dw > 0, dh > 0 else { return nil }
            source = (sw, sh); depth = (dw, dh)
        }
    }
    /// The render cache writer is insert-only. Acceptance is a repeatable named
    /// report: render privately, then atomically replace only our two MP4 outputs.
    static func acceptanceRender(work: URL, evidence: URL, name: String, render: (URL) throws -> Void) throws -> URL {
        guard ["sbs", "vr180"].contains(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let staged = work.appendingPathComponent("acceptance-" + UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: staged) }
        try render(staged)
        let bytes = try Data(contentsOf: staged)
        guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let published = evidence.appendingPathComponent(name + ".mp4")
        try bytes.write(to: published, options: .atomic)
        return published
    }
    /// Runs once per (kit manifest, build): the marker file records the attempt even when it fails, so a crashing model cannot loop on every launch.
    static func markerName(manifestSha: String, build: String) -> String {
        let safe = build.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" ? Character($0) : "_" }
        return "selftest-\(manifestSha.prefix(12))-\(String(safe)).done"
    }
    static func shouldRun(enabled: Bool, kitPresent: Bool, markerExists: Bool, filmPreparing: Bool) -> Bool { enabled && kitPresent && !markerExists && !filmPreparing }
    /// The installer already runs --selftest3d in its own process. Interactive
    /// playback must not also start a model/render/telemetry workload by default.
    static func interactiveRequested(_ environment: [String: String]) -> Bool { environment["GOR_3D_INTERACTIVE_SELFTEST"] == "1" }
    /// Synthetic clip geometry: 16:9 so the 518x294 MoGe package is picked; 36 frames = three keyframes at stride 12.
    static let clipW = 640, clipH = 360, clipFrames = 36, clipFPS = 24.0
    /// Longest the synthetic clip writer may stall before the self-test logs it and gives up (seconds).
    static let writerStallLimit: TimeInterval = 30
    /// Pure test pattern: luma-ish gradient plus a moving block, BGRA. Deterministic so the depth stats are comparable between runs.
    static func pattern(frame k: Int, w: Int = clipW, h: Int = clipH) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let bx = (k * 7) % (w - 96), by = h / 3
        for y in 0..<h { for x in 0..<w {
            let o = (y * w + x) * 4
            var r = UInt8(x * 255 / (w - 1)), g = UInt8(y * 255 / (h - 1)), b = UInt8(((x + y + k * 3) / 4) % 256)
            if x >= bx && x < bx + 96 && y >= by && y < by + 96 { r = 220; g = 40; b = 40 }
            px[o] = b; px[o + 1] = g; px[o + 2] = r
        } }
        return px
    }
}

#if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Metal)
import AVFoundation
import CoreVideo
import Metal
import ImageIO

extension ThreeDSelfTest {
    /// Writes the synthetic clip (H.264, BGRA frames). nil on any writer failure (the reason goes to `telemetry`).
    static func writeClip(to url: URL, telemetry: PrepareTelemetry) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { telemetry.error("clip: cannot create writer"); return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: clipW, AVVideoHeightKey: clipH])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: clipW, kCVPixelBufferHeightKey as String: clipH])
        guard w.canAdd(input) else { telemetry.error("clip: cannot add input"); return false }
        w.add(input); guard w.startWriting() else { telemetry.error("clip: startWriting failed: \(String(describing: w.error))"); return false }
        w.startSession(atSourceTime: .zero)
        for k in 0..<clipFrames {
// [attribution comment elided]
            let waitStart = Date()
            while !input.isReadyForMoreMediaData {
                if Date().timeIntervalSince(waitStart) > writerStallLimit { telemetry.error("clip: writer not ready for frame \(k) after \(Int(writerStallLimit)) s (status \(w.status.rawValue), error \(String(describing: w.error)))"); w.cancelWriting(); return false }
                Thread.sleep(forTimeInterval: 0.002)
            }
            var pb: CVPixelBuffer?
            guard let pool = ad.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let b = pb else { telemetry.error("clip: no pixel buffer"); return false }
            CVPixelBufferLockBaseAddress(b, [])
            if let base = CVPixelBufferGetBaseAddress(b) {
                let src = pattern(frame: k), bpr = CVPixelBufferGetBytesPerRow(b)
                for y in 0..<clipH { src.withUnsafeBytes { memcpy(base.advanced(by: y * bpr), $0.baseAddress! + y * clipW * 4, clipW * 4) } }
            }
            CVPixelBufferUnlockBaseAddress(b, [])
            guard ad.append(b, withPresentationTime: CMTime(value: CMTimeValue(k), timescale: CMTimeScale(clipFPS))) else { telemetry.error("clip: append failed at \(k): \(String(describing: w.error))"); return false }
        }
        input.markAsFinished()
        let g = DispatchGroup(); g.enter(); w.finishWriting { g.leave() }
        if g.wait(timeout: .now() + writerStallLimit) == .timedOut { telemetry.error("clip: finishWriting did not return in \(Int(writerStallLimit)) s (status \(w.status.rawValue), error \(String(describing: w.error)))"); return false }
        if w.status != .completed { telemetry.error("clip: finish failed: \(String(describing: w.error))"); return false }
        return true
    }

    /// SHA-256 of the first frame (BGRA bytes) of a video file: the "first rendered 3D frame hash". Same machine and encoder => comparable between runs; not a cross-machine pin.
    static func firstFrameHash(_ url: URL) -> String? {
        let a = AVURLAsset(url: url)
        guard let t = a.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: a) else { return nil }
        let o = AVAssetReaderTrackOutput(track: t, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard r.canAdd(o) else { return nil }
        r.add(o); guard r.startReading(), let s = o.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(s) else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        var hasher = SHA256Pure.Hasher()
        for y in 0..<h { hasher.update([UInt8](UnsafeBufferPointer(start: base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self), count: w * 4))) }
        r.cancelReading(); return hasher.hex()
    }

    /// Durable, decoded first-frame evidence (not merely a file-exists or encoded-byte claim).
    static func saveFrame(_ video: URL, png: URL) -> Bool {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video)); gen.appliesPreferredTrackTransform = true
        guard let image = try? gen.copyCGImage(at: .zero, actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    static func thermalObserver(_ t: PrepareTelemetry) -> NSObjectProtocol {
        t.thermalSample(level: ThermalLevel.current().rawValue)
        return NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in t.thermalSample(level: ThermalLevel.current().rawValue) }
    }

    /// Blocking; call on a background queue. Emits the log lines with `emit` (default: stdout, which the app pipes into the gor log). Never throws; every failure is a logged line.
    /// `marker` is written first (an attempt counts even if the process dies mid-run). The test film lives in a temp cache root and is removed afterwards.
    @discardableResult
    static func run(runner: NativePrepareRunner, kitDir: URL, modelsDir: URL, build: String, marker: URL, emit: ([String]) -> Void = { $0.forEach { print($0) }; fflush(stdout) }) -> PrepareTelemetry {
        let tel = PrepareTelemetry()
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("started".utf8).write(to: marker)
        let obs = thermalObserver(tel); defer { NotificationCenter.default.removeObserver(obs) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("gor3d-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let host = ProcessInfo.processInfo
        tel.note("build", build); tel.note("os", host.operatingSystemVersionString); tel.note("cpus", "\(host.activeProcessorCount)"); tel.note("mem_gb", "\(host.physicalMemory >> 30)")
        tel.note("kit_manifest_sha", KitCompiledCache.manifestSha(kitDir: kitDir) ?? "missing")
        tel.note("clip", "320x180 48f @24 Tears of Steel CC-BY-3.0 source_sha256=b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956")
        let film = work.appendingPathComponent("selftest.mp4"), cache = work.appendingPathComponent("cache", isDirectory: true)
        let env = ProcessInfo.processInfo.environment
        let fixturePath = env["GOR_3D_TEST_CLIP"] ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4").path
        let fixture: URL? = URL(fileURLWithPath: fixturePath)
        guard let fixture, let bytes = try? Data(contentsOf: fixture), bytes.count == 63977 else { tel.error("acceptance: original ToS fixture missing or wrong size"); emit(tel.lines(header: "3D self-test FAILED")); return tel }
        var inputHash = SHA256Pure.Hasher(); inputHash.update([UInt8](bytes))
        guard inputHash.hex() == "b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956" else { tel.error("acceptance: original ToS SHA256 mismatch"); emit(tel.lines(header: "3D self-test FAILED")); return tel }
        do { try tel.time("clip_write") { try FileManager.default.copyItem(at: fixture, to: film) } } catch { tel.error("acceptance: cannot stage ToS input"); return tel }
        let evidence = env["GOR_3D_TEST_EVIDENCE"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? modelsDir.appendingPathComponent("selftest-evidence", isDirectory: true)
        do { try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true) } catch { tel.error("acceptance: cannot create evidence directory"); return tel }
        let testW = 320, testH = 180, testFrames = 48
        let test = NativePrepareRunner(kitDir: kitDir, cacheRoot: cache); test.modelsDir = modelsDir; test.telemetry = tel
        let req = ThreeDPrepareLauncher.Request(film: film, fps: clipFPS, nFrames: testFrames, startPTS: 0, quality: "selftest")
        var prepared = false
        tel.time("prepare_total") {
            do { try ThreeDStageLog.time("prepare (cuts, depth, moge)") { try test.prepare(req, cancelled: { false }) }; prepared = true } catch { tel.error("prepare: \(error)") }
        }
        // models: precision actually used, and the compute plan per package
        if let m = test.moge { tel.note("moge_precision", "fp16_used=\(m.fp16Used) fp16_rejected=\(m.fp16Rejected) fp32_used=\(m.fp32Used)") }
        // 195h A (item 5): when the DAV2 experiment is selected, the self-test also runs the pinned CoreML package on fixture frames and
        // reports its ms/frame line. Skipped silently otherwise; a missing package is a note, never a failure of the default self-test.
        if DepthModelID.selected() == .dav2_small_coreml {
            if let r = CoreMLDepthRunner(modelsDir: modelsDir), let fr = NativePrepareRunner.FrameReader(url: film, fps: clipFPS, format: kCVPixelFormatType_32BGRA) {
                var fs: [CVPixelBuffer] = []; for k in 0..<8 { if let pb = fr.frame(k, last: 47) { fs.append(pb) } }
                fr.close()
                tel.note("dav2_selftest", r.selfTest(frames: fs) ?? "dav2_small_coreml self-test: no frame succeeded")
            } else { tel.note("dav2_selftest", "dav2_small_coreml package not installed (tools/gor-fetch-models.sh); skipped") }
        }
        tel.note("compute_plan", "see bounded per-package load/device stage lines; no second model load for telemetry")
        var acceptanceComplete = false
        // render: the real RenderShotWriter over the prepared shot 0
        if prepared, let entry = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil))?.first(where: { $0.hasDirectoryPath }) {
            let depth = ShotSink.depthURL(entry, 0), source = ShotSink.sourceURL(entry, 0)
            guard let data = try? Data(contentsOf: ShotSink.sidecarURL(entry, 0)),
                  let sidecar = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let geometry = PreparedGeometry(sidecar: sidecar) else {
                tel.error("acceptance: prepared shot sidecar geometry missing or invalid")
                emit(tel.lines(header: "3D self-test FAILED")); return tel
            }
            tel.note("prepared_geometry", "source_width=\(geometry.source.w) source_height=\(geometry.source.h) depth_width=\(geometry.depth.w) depth_height=\(geometry.depth.h)")
            let fovShot = ((try? Data(contentsOf: entry.appendingPathComponent("fov_track.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["shots"] as? [[String: Any]])?.first
            let hfov = (fovShot?["hfov_deg"] as? Double) ?? 60.0
            if fovShot?["hfov_deg"] as? Double == nil { tel.error("render: fov_track.json has no hfov for shot 0, using 60 deg") }
            let fov = entry.appendingPathComponent("fov_track.json")
            do { let data = try Data(contentsOf: fov); try data.write(to: evidence.appendingPathComponent("fov_track.json"), options: .atomic) }
            catch { tel.error("acceptance: FoV track could not be saved") }
            var grabs = [String: String]()
            for (name, mode) in [("sbs", OutputMode.fullSBS), ("vr180", OutputMode.vr180)] {
                let png = evidence.appendingPathComponent(name + ".png")
                var completed: URL? // A prior run's output must never count after a failed render.
                if let w = RenderShotWriter() {
                    let plan = RenderedShotPlan(eyeN: 256, codec: .hevc, swapEyes: true, output: mode, srcW: geometry.source.w, srcH: geometry.source.h)
                    tel.time("render_" + name) { ThreeDStageLog.time("render " + name) {
                        do { completed = try acceptanceRender(work: work, evidence: evidence, name: name) { staged in
                            _ = try w.write(source: source, depth: depth, depthSize: geometry.depth, sourceSize: geometry.source, thetaH: hfov * .pi / 180, plan: plan, ipd: 0.063, convergence: nil, out: staged)
                        } }
                        catch { tel.error("render " + name + ": \(error)") }
                    } }
                    if let out = completed, let hash = firstFrameHash(out), saveFrame(out, png: png) { grabs[name] = hash; tel.note("acceptance_" + name + "_frame_sha256", hash); if name == "vr180" { tel.note("first_3d_frame_sha256", hash) } }
                    else { tel.error("acceptance: missing decoded " + name + " frame grab") }
                } else { tel.error("render: no Metal renderer") }
            }
            tel.add("render_shot", ms: tel.stages.filter { $0.name == "render_sbs" || $0.name == "render_vr180" }.reduce(0) { $0 + $1.s.ms })
            let accepted = grabs.count == 2 && FileManager.default.fileExists(atPath: evidence.appendingPathComponent("fov_track.json").path) && tel.errors.isEmpty
            acceptanceComplete = accepted
            let manifest: [String: Any] = ["schema": 1, "build": build, "fixture_sha256": inputHash.hex(), "frames": testFrames, "width": testW, "height": testH,
                "frame_hashes": grabs, "verdict": accepted ? "PASS" : "FAIL", "stage_ms": Dictionary(uniqueKeysWithValues: tel.stages.map { ($0.name, $0.s.ms) })]
            if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) { try? data.write(to: evidence.appendingPathComponent("acceptance.json"), options: .atomic) }
            tel.note("acceptance_evidence", evidence.path)
            ThreeDStageLog.time("realtime probe") { RealtimeProbe.run(tel: tel, sourceProxy: source, frames: testFrames) } // measured separately from failed/successful renders
        }
        if !acceptanceComplete { tel.error("acceptance: SBS/VR180 decoded grabs, FoV track and stage measurements are incomplete") }
        tel.addRealtimeBudget(frames: testFrames)
        tel.note("prepared", prepared ? "yes" : "no")
        try? Data((prepared && acceptanceComplete && tel.errors.isEmpty ? "done" : "failed").utf8).write(to: marker)
        emit(ThreeDDegrade.walkLines())          // s38/s39 item 12: the scripted degradation walk, verbatim 3dfsm lines
        emit(tel.lines(header: prepared ? "3D self-test finished" : "3D self-test FAILED"))
        return tel
    }
}
#endif
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// X1 (190x): headless entry for the first-Mac kit. `gor --selftest3d` runs the same ThreeDSelfTest the app runs after an update, but without
/// NSApplication, without a window and without needing 3D switched on in the UI, then exits. The kit installer redirects stdout into its log and
/// feeds that log to mac_log_check (the 13-family first-Mac checklist). Nothing here changes what the app does when it is launched normally.
/// Not compiled or run on a Mac yet; the pure parts (argument test, exit code, missing-kit line) are pinned on Linux by Tests/FirstMacKit.
enum ThreeDSelfTestCLI {
    static let flag = "--selftest3d"

    /// Printed by the installer when the headless run cannot start; says what the flag does and what it never does.
    static let usage = """
    gor --selftest3d
      Runs the 3D self-test headless: CoreML prepare of the pinned Tears of Steel 320x180 48-frame clip, SBS and VR180 renders,
      decoded PNG grabs, FoV track, stage milliseconds, thermal series and the degradation walk. Writes gor3d-selftest v1 lines to stdout.
      Exit 0 = pass, 2 = ran with errors, 3 = kit packages missing, 4 = platform has no CoreML/Metal.
      It opens no window, writes no once-per-build marker, changes no setting and does not touch the installed app.
      The kit packages are read from GOR_KIT_DIR or <models dir>/kit; they are never downloaded by this flag.
    """

    /// Pure: true when the process was started with the headless flag.
    static func requested(arguments: [String]) -> Bool { arguments.contains(flag) }

    /// Pure: exit status the kit installer reads. 0 = prepared and no errors, 2 = ran but failed or had errors, 3 = kit packages missing, 4 = no CoreML here.
    static func exitCode(kitMissing: [String], prepared: Bool, errors: Int) -> Int32 {
        if !kitMissing.isEmpty { return 3 }
        return prepared && errors == 0 ? 0 : 2
    }

    /// Pure: the one line written when the kit is incomplete, in the same family as the other self-test lines so the log checker reports it as MISSING.
    static func missingLine(_ m: [String]) -> String { "gor3d-selftest-cli v1 kit_missing " + m.joined(separator: ",") }

    /// Exit statuses, one place, so the installer's mapping and this file cannot drift apart (Tests/FirstMacKit pins the same table).
    static let exitMeanings: [Int32: String] = [
        0: "prepared, rendered, no errors",
        2: "ran, but the prepare failed or the log has error lines",
        3: "kit packages missing: nothing was run",
        4: "no CoreML/Metal/VideoToolbox on this platform: nothing was run",
    ]

    /// Pure: the closing line the installer greps for. A log without it was cut short (crash or kill) and counts as a failed run.
    static func endLine(code: Int32, errors: Int) -> String {
        "gor3d-selftest-cli v1 end code=\(code) errors=\(errors) meaning=" + (exitMeanings[code] ?? "unknown").replacingOccurrences(of: " ", with: "_")
    }

    /// Pure: a headless log is complete when it has exactly one begin line and a closing end line with the same run (the installer applies this in Python too).
    static func logIsComplete(_ lines: [String]) -> Bool {
        lines.filter { $0.hasPrefix("gor3d-selftest-cli v1 begin ") }.count == 1
            && (lines.last(where: { $0.hasPrefix("gor3d-selftest-cli v1 ") })?.hasPrefix("gor3d-selftest-cli v1 end ") ?? false)
    }

    /// Pure: header line with the build id and the kit directory, so the uploaded log says which tree and which kit it measured.
    static func beginLine(build: String, kit: String) -> String { "gor3d-selftest-cli v1 begin build=\(build) kit=\(kit)" }

    /// Blocking. Returns the process exit status; the caller exits with it.
    static func run() -> Int32 {
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Metal)
        let kit = ThreeDKit.dir, models = ThreeDModels.modelsDir
        let missing = ThreeDKit.missing(dir: kit)
        print(beginLine(build: BuildID.value(), kit: kit.path)); fflush(stdout)
        if !missing.isEmpty {
            let code = exitCode(kitMissing: missing, prepared: false, errors: 0)
            print(missingLine(missing)); print(endLine(code: code, errors: 0)); fflush(stdout)
            return code
        }
        ThreeDStageLog.enabled = true; ThreeDStageLog.start(); defer { ThreeDStageLog.stop() }
        let runner = NativePrepareRunner(kitDir: kit)
        runner.modelsDir = models
        try? FileManager.default.createDirectory(at:runner.cacheRoot,withIntermediateDirectories:true)
        guard let lane=PrepareProcessLifetime.acquireLane(root:runner.cacheRoot,cancelled:{false}) else { return 2 }
        defer { PrepareProcessLifetime.releaseLane(lane) }
        runner.externallyHeldModelLane=true
        // A throwaway marker: the headless run must not consume the app's once-per-build marker in <models>.
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("gor3d-selftest-cli-\(UUID().uuidString).marker")
        defer { try? FileManager.default.removeItem(at: marker) }
        let tel = ThreeDStageLog.time("self-test total") { ThreeDSelfTest.run(runner: runner, kitDir: kit, modelsDir: models, build: BuildID.value(), marker: marker) }
        let prepared = ((try? String(contentsOf: marker)) ?? "") == "done"
        let code = exitCode(kitMissing: [], prepared: prepared, errors: tel.errors.count)
        print(endLine(code: code, errors: tel.errors.count)); fflush(stdout)
        return code
        #else
        print("gor3d-selftest-cli v1 unsupported platform"); print(endLine(code: 4, errors: 0)); fflush(stdout)
        return 4
        #endif
    }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum ThreeDShotPlayLog {
    /// Field order of render key v4, split on "|": comfort keys carry three ipd fields (comfort|ipd..|sf..), fixed keys carry two (fixed|ipd..).
    static let keyFields = ["version", "method", "ipd", "mode", "convergence", "eye_n", "codec", "swap", "screen_deg", "surround"]

    /// Pure: `gor3d-shot v1 shot=<n> pts=<s> menu_mode=<name> method=.. ipd=comfort/ipd0.063/sf1.0 mode=.. convergence=.. eye_n=.. codec=.. swap=.. screen_deg=.. surround=.. key=<full key>`.
    /// A key that does not parse is still logged whole (key=) with parsed=no, never dropped.
    static func shotLine(shot: Int, pts: Double, menuMode: String, key: String) -> String {
        var parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.count > 1, parts[0] == "v5", parts[1] == "span-p5p95" { parts.remove(at: 1); parts[0] = "v4" }
        let head = "gor3d-shot v1 shot=\(shot) pts=\(String(format: "%.3f", pts)) menu_mode=\(clean(menuMode))"
        guard parts.count >= 10, parts[0] == "v4" else { return head + " parsed=no key=\(key)" }
        let comfort = parts[2] == "comfort"
        let ipdLen = comfort ? 3 : 2
        guard parts.count == 9 + ipdLen else { return head + " parsed=no key=\(key)" }
        let ipd = parts[2..<(2 + ipdLen)].joined(separator: "/")
        let rest = Array(parts[(2 + ipdLen)...])
        let names = ["mode", "convergence", "eye_n", "codec", "swap", "screen_deg", "surround"]
        let tail = zip(names, rest).map { "\($0)=\($1)" }.joined(separator: " ")
        return head + " parsed=yes method=\(parts[1]) ipd=\(ipd) \(tail) key=\(key)"
    }

    /// Pure: the OSD line. Text keeps its spaces (it is the tail of the line, like `note` text in PrepareTelemetry).
    static func osdLine(_ text: String) -> String { "gor3d-osd v1 " + text.replacingOccurrences(of: "\n", with: " ") }

    /// Pure: menu mode names never contain spaces or pipes, so the line stays one token per field.
    static func clean(_ s: String) -> String { s.isEmpty ? "none" : String(s.map { $0 == " " || $0 == "|" ? Character("_") : $0 }) }

    /// Pure: `gor3d-shot v1 k=v k=v ... key=<key>` back into a dictionary (the key value is everything after `key=`, it contains pipes but no spaces).
    /// Returns nil for any other line. Used by the pins here and available to the log checkers.
    static func parse(line: String) -> [String: String]? {
        let prefix = "gor3d-shot v1 "
        guard line.hasPrefix(prefix) else { return nil }
        var out: [String: String] = [:]
        for token in line.dropFirst(prefix.count).split(separator: " ") {
            guard let eq = token.firstIndex(of: "=") else { return nil }
            out[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        return out
    }

    /// Pure: how many shots were played per synthesis method in a log (for a one-line summary in diag packs). Lines that do not parse are skipped.
    static func methodCounts(_ lines: [String]) -> [String: Int] {
        var n: [String: Int] = [:]
        for l in lines { if let f = parse(line: l), f["parsed"] == "yes", let m = f["method"] { n[m, default: 0] += 1 } }
        return n
    }

    /// Pure: the field names a complete parsed line must carry, for the pin and for any consumer that wants to reject a half line.
    static let requiredParsed = ["shot", "pts", "menu_mode", "parsed", "method", "ipd", "mode", "convergence", "eye_n", "codec", "swap", "screen_deg", "surround", "key"]

    /// Most recent shot index logged, nil after a shot ended; exposed read-only so a test or the diag pack can tell whether a shot is being shown.
    static var currentShot: Int? { lock.lock(); defer { lock.unlock() }; return lastShot }

    private static let lock = NSLock()
    private static var seenOSD = Set<String>(), lastShot: Int?

    /// Called where a shot starts showing. A shot logs once per start; re-showing the same shot index back to back does not repeat the line.
    static func logShot(shot: Int, pts: Double, menuMode: String, key: String) {
        lock.lock(); let again = lastShot == shot; lastShot = shot; lock.unlock()
        guard !again else { return }
        print(shotLine(shot: shot, pts: pts, menuMode: menuMode, key: key)); fflush(stdout)
    }

    /// Called for every OSD text the 3D coordinator would announce, before the "osd line" toggle is read. Each distinct text is logged once per launch.
    static func logOSD(_ text: String) {
        lock.lock(); let fresh = seenOSD.insert(text).inserted; lock.unlock()
        guard fresh else { return }
        print(osdLine(text)); fflush(stdout)
    }

    /// The shot stopped showing (back to 2D): its next start logs again.
    static func shotEnded() { lock.lock(); lastShot = nil; lock.unlock() }

    /// Forgotten between films so the next film logs its first shot and its OSD lines again.
    static func reset() { lock.lock(); seenOSD.removeAll(); lastShot = nil; lock.unlock() }
}
// [attribution comment elided]
// [attribution comment elided]
import Foundation

/// Per-stage progress for `gor --selftest3d` (Main 16:33: a 12 min run left only the begin line, because the telemetry lines are emitted once at the very end).
/// Off in the normal app (no noise); the CLI turns it on. Every line is flushed at once, so the installer log shows where a long compile / ANE load is sitting:
///   gor3d-selftest-cli v1 stage <name> begin t=<s since start>
///   gor3d-selftest-cli v1 stage <name> end ms=<n> t=<s>
///   gor3d-selftest-cli v1 alive stage=<current> in_stage_s=<n> t=<s>      (heartbeat every `beat` seconds while a stage is open)
/// Pure Foundation: formatting and the stage stack are tested on Linux (Tests/ThreeDKit/stage_log_test.py); the model calls it wraps are Mac-only.
enum ThreeDStageLog {
    static var enabled = false
    static var beat: TimeInterval = 15
    static var sink: (String) -> Void = { print($0); fflush(stdout) }
    private static let lock = NSLock()
    private static var stack: [(name: String, start: Date)] = []
    private static var t0 = Date()
    private static var timer: DispatchSourceTimer?
    private static var work: (stage: String, done: Int, total: Int, scopeDepth: Int)?

    static func beginLine(_ name: String, t: Double) -> String { "gor3d-selftest-cli v1 stage \(name) begin t=\(String(format: "%.1f", t))" }
    static func endLine(_ name: String, ms: Double, t: Double) -> String { "gor3d-selftest-cli v1 stage \(name) end ms=\(Int(ms.rounded())) t=\(String(format: "%.1f", t))" }
    static func aliveLine(stage: String, inStage: Double, t: Double) -> String { "gor3d-selftest-cli v1 alive stage=\(stage) in_stage_s=\(Int(inStage)) t=\(String(format: "%.1f", t))" }

    static func progressLine(_ stage: String, done: Int, total: Int, t: Double) -> String {
        "gor3d-selftest-cli v1 progress stage=\(stage) done=\(done) total=\(total) t=\(String(format: "%.1f", t))"
    }
    /// Report before and after expensive work. Heartbeats repeat the most recent counter, distinguishing an in-flight model call from completed frames.
    static func progress(_ stage: String, done: Int, total: Int) {
        guard enabled else { return }
        lock.lock(); work = (stage, done, total, stack.count); let t = Date().timeIntervalSince(t0); lock.unlock()
        sink(progressLine(stage, done: done, total: total, t: t))
    }

    static func start() {
        guard enabled else { return }
        lock.lock(); t0 = Date(); stack = []; work = nil; lock.unlock()
        let q = DispatchQueue(label: "gor.3d.stagelog")
        let tm = DispatchSource.makeTimerSource(queue: q)
        tm.schedule(deadline: .now() + beat, repeating: beat)
        tm.setEventHandler {
            lock.lock(); let cur = stack.last; let current = work; let t = Date().timeIntervalSince(t0); lock.unlock()
            sink(aliveLine(stage: cur?.name ?? "between-stages", inStage: cur.map { Date().timeIntervalSince($0.start) } ?? 0, t: t))
            if let current { sink(progressLine(current.stage, done: current.done, total: current.total, t: t)) }
        }
        tm.resume(); timer = tm
    }
    static func stop() { timer?.cancel(); timer = nil }

    /// Runs `body` as a named stage: begin line, end line with the wall time, heartbeat while it runs. A plain call when logging is off.
    static func time<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let s = Date()
        lock.lock(); stack.append((name, s)); let t = s.timeIntervalSince(t0); lock.unlock()
        sink(beginLine(name, t: t))
        defer {
            lock.lock(); _ = stack.popLast()
            if let current = work, current.scopeDepth > stack.count { work = nil }
            lock.unlock()
            sink(endLine(name, ms: Date().timeIntervalSince(s) * 1000, t: Date().timeIntervalSince(t0)))
        }
        return try body()
    }
    /// A finished stage reported by someone else (PrepareTelemetry stage timers): one end line, no heartbeat.
    static func done(_ name: String, ms: Double) { if enabled { sink(endLine(name, ms: ms, t: Date().timeIntervalSince(t0))) } }
}

/// Bounded caller wait. A timed-out OS call is NOT cancelled; its late result is discarded.
/// Device circuit breakers in KitCompiledCache stop later requests accumulating stuck loads.
final class BoundedLoadResult<T> {
    private let lock = NSLock()
    private var value: T?
    private var closed = false
    func publish(_ v: T?) { lock.lock(); defer { lock.unlock() }; if !closed { value = v } }
    func finish() -> T? { lock.lock(); defer { lock.unlock() }; closed = true; let v = value; value = nil; return v }
}
enum BoundedLoad {
    static func attempt<T>(seconds: Double, body: @escaping () -> T?) -> (value: T?, timedOut: Bool) {
        let box = BoundedLoadResult<T>(), sem = DispatchSemaphore(value: 0)
        DispatchQueue(label: "gor.coreml.load." + UUID().uuidString).async { box.publish(body()); sem.signal() }
        let timeout = sem.wait(timeout: .now() + seconds) != .success
        let value = box.finish()
        return (timeout ? nil : value, timeout)
    }
}
// END relocated ThreeDStageLog.swift

// BEGIN station-move CacheKeyMemo.swift
import Foundation

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
enum CacheKeyMemo {
    private static let lock = NSLock()
    private static var memo: [String: (sig: String, key: String)] = [:]
    private static var inflight = Set<String>()
    private(set) static var hashRuns = 0
    private static func sig(_ path: String) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path), let size = (a[.size] as? NSNumber)?.int64Value, let t = a[.modificationDate] as? Date else { return nil }
        return "\(size):\(t.timeIntervalSinceReferenceDate)"
    }
    /// Memoised key (same value as PrepareSupport.cacheKey), nil while the first hash is still running or the file cannot be read.
    static func key(path: String, background: Bool = true) -> String? {
        guard let s = sig(path) else { return nil }
        lock.lock()
        if let m = memo[path], m.sig == s { lock.unlock(); return m.key }
        if inflight.contains(path) { lock.unlock(); return nil }
        inflight.insert(path); lock.unlock()
        let work: @Sendable () -> Void = {
            let k = PrepareSupport.cacheKey(path: path)
            lock.lock(); hashRuns += 1; inflight.remove(path); if let k = k { memo[path] = (s, k) }; lock.unlock()
        }
        if background { DispatchQueue.global(qos: .utility).async(execute: work); return nil }
        work(); lock.lock(); defer { lock.unlock() }; return memo[path]?.key
    }
}
// END station-move CacheKeyMemo.swift
