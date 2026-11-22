// Sources/GorAVPlaybackCore/ControlBus.swift
// G5 (P24) gorav-side typed control surface + G6 (P25) presentation-receipt consumer.
// Vocabularies are taken from gor d8b677b0: ThreeDPresentationPlan (projection/engine/output/pack/enabled/aspect),
// vr180-look-set-orientation (yaw pitch fov roll ipdNudge head xyz, radians, nil = unchanged), vr180-look-set-tune
// (name, number), ThreeDEffectKey values, and the film-frame receipt fields gor validates today in
// PPController.noteFilmFrame. Pure value logic, no I/O, no clock. Linux only / Mac NOT_RUN.

public struct ParameterBlockRevision: Equatable, Comparable, Hashable, Sendable {
    public let value: UInt64
    public init(_ v: UInt64) { value = v }
    public static func < (a: Self, b: Self) -> Bool { a.value < b.value }
}

/// Rect in normalized [0,1] frame coordinates: finite, w/h > 0, inside the unit square.
public struct NormalizedRect: Equatable, Sendable {
    public let x: Double, y: Double, w: Double, h: Double
    public init?(x: Double, y: Double, w: Double, h: Double) {
        guard x.isFinite, y.isFinite, w.isFinite, h.isFinite, w > 0, h > 0,
              x >= 0, y >= 0, x + w <= 1.0 + 1e-9, y + h <= 1.0 + 1e-9 else { return nil }
        self.x = x; self.y = y; self.w = w; self.h = h
    }
    public static let full = NormalizedRect(x: 0, y: 0, w: 1, h: 1)!
}

/// Opaque name (projection, engine, output, fit, tune/effect key): 1...32 ASCII letters, digits, '-', '_'.
/// Examples from gor: "flat-sbs", "vr180-tb", "full_sbs", "nativeVR180", "vr_gap_frac", "screenDepth".
public struct ModeToken: Equatable, Hashable, Sendable {
    public let name: String
    public init?(_ s: String) {
        guard !s.isEmpty, s.utf8.count <= 32,
              s.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 })
        else { return nil }
        name = s
    }
}

public enum EffectValue: Equatable, Sendable {
    case bool(Bool), number(Double), text(ModeToken)
    var isValid: Bool { if case let .number(d) = self { return d.isFinite }; return true }
}

/// One presentation decision (gor ThreeDPresentationPlan fields the renderer needs).
public struct RoutePlan: Equatable, Sendable {
    public let projection: ModeToken   // luaKind, e.g. "flat-sbs", "vr180"
    public let engine: ModeToken       // e.g. "nativeVR180", "flat_full_sbs"
    public let output: ModeToken       // e.g. "off", "full_sbs", "vr180"
    public let enabled: Bool
    public let pack: Int               // 0...255
    public let aspect: Double          // 0 = none, else finite > 0
    public init?(projection: ModeToken, engine: ModeToken, output: ModeToken, enabled: Bool, pack: Int, aspect: Double) {
        guard (0...255).contains(pack), aspect.isFinite, aspect >= 0 else { return nil }
        self.projection = projection; self.engine = engine; self.output = output
        self.enabled = enabled; self.pack = pack; self.aspect = aspect
    }
}

/// View pose, radians. nil field = leave unchanged (mirrors the script's optional numbers).
/// Pitch and fov limits belong to the renderer; roll is an unwrapped tilt and is never clamped here.
public struct ViewOrientation: Equatable, Sendable {
    public var yaw: Double?, pitch: Double?, fov: Double?, roll: Double?
    public var ipdNudge: Double?, headX: Double?, headY: Double?, headZ: Double?
    public init(yaw: Double? = nil, pitch: Double? = nil, fov: Double? = nil, roll: Double? = nil,
                ipdNudge: Double? = nil, headX: Double? = nil, headY: Double? = nil, headZ: Double? = nil) {
        self.yaw = yaw; self.pitch = pitch; self.fov = fov; self.roll = roll
        self.ipdNudge = ipdNudge; self.headX = headX; self.headY = headY; self.headZ = headZ
    }
    var allFinite: Bool {
        [yaw, pitch, fov, roll, ipdNudge, headX, headY, headZ].allSatisfy { $0 == nil || $0!.isFinite }
    }
}

public enum ControlCommand: Equatable, Sendable {
    case setLook(revision: ParameterBlockRevision, plan: RoutePlan)
    case setOrientation(ViewOrientation)
    case setTune(name: ModeToken, value: Double)
    case setEffects([ModeToken: EffectValue])
    case setCrop(NormalizedRect)
    case setFit(ModeToken)
    case setAudioTrack(AudioTrackSelector)   // R6 (arch-195l)
    case setAudioDelay(Double)               // R6: seconds, mpv sign convention
}

public enum ControlRefusal: Equatable, Sendable {
    case staleRevision(current: ParameterBlockRevision)
    case revisionReused(current: ParameterBlockRevision)   // same revision, different plan
    case nonFinite
    case notOpen
    case outOfRange
}

public enum ControlOutcome: Equatable, Sendable {
    case accepted(commandSeq: UInt64)       // queued for the renderer; NOT yet applied
    case refused(ControlRefusal)
}

/// What the renderer has been asked to do. Applied state is only ever learned from receipts.
public struct ControlState: Equatable, Sendable {
    public var look: ParameterBlockRevision?
    public var plan: RoutePlan?
    public var orientation = ViewOrientation()
    public var tune: [ModeToken: Double] = [:]
    public var effects: [ModeToken: EffectValue] = [:]
    public var crop: NormalizedRect = .full
    public var fit: ModeToken?
    public var audioTrack: AudioTrackSelector = .auto   // R6
    public var audioDelaySeconds = 0.0                  // R6
    public init() {}
}

public struct ControlBus: Sendable {
    public private(set) var state = ControlState()
    public private(set) var isOpen = false
    private var seq: UInt64 = 0
    public init() {}
    public mutating func open() { isOpen = true }
    public mutating func close() { isOpen = false }

    /// Typed and loud, never a silent no-op. A command either changes `state` or is refused with no change.
    public mutating func send(_ c: ControlCommand) -> ControlOutcome {
        guard isOpen else { return .refused(.notOpen) }
        switch c {
        case let .setLook(r, plan):
            if let cur = state.look {
                if r < cur { return .refused(.staleRevision(current: cur)) }
                if r == cur { // idempotent resend of the same plan is accepted without change
                    if state.plan == plan { seq &+= 1; return .accepted(commandSeq: seq) }
                    return .refused(.revisionReused(current: cur))
                }
            }
            state.look = r; state.plan = plan
        case let .setOrientation(o):
            guard o.allFinite else { return .refused(.nonFinite) }
            if let v = o.yaw { state.orientation.yaw = v }
            if let v = o.pitch { state.orientation.pitch = v }
            if let v = o.fov { state.orientation.fov = v }
            if let v = o.roll { state.orientation.roll = v }
            if let v = o.ipdNudge { state.orientation.ipdNudge = v }
            if let v = o.headX { state.orientation.headX = v }
            if let v = o.headY { state.orientation.headY = v }
            if let v = o.headZ { state.orientation.headZ = v }
        case let .setTune(n, v):
            guard v.isFinite else { return .refused(.nonFinite) }
            state.tune[n] = v
        case let .setEffects(e):
            guard e.values.allSatisfy({ $0.isValid }) else { return .refused(.nonFinite) }
            for (k, v) in e { state.effects[k] = v }
        case let .setCrop(rect): state.crop = rect
        case let .setFit(m): state.fit = m
        case let .setAudioTrack(s):
            if case let .index(i) = s, i < 0 { return .refused(.outOfRange) }
            state.audioTrack = s
        case let .setAudioDelay(v):
            guard v.isFinite else { return .refused(.nonFinite) }
            guard AudioDelay(v) != nil else { return .refused(.outOfRange) }
            state.audioDelaySeconds = v
        }
        seq &+= 1
        return .accepted(commandSeq: seq)
    }
}

/// gor's film-frame fields (PPController.noteFilmFrame). Same acceptance rules gor applies today:
/// every field finite, scale/width/height > 0.
public struct FilmFrameGeometry: Equatable, Sendable {
    public let sequence: Double, scale: Double, angle: Double
    public let leftX: Double, leftY: Double, replicaX: Double, replicaY: Double
    public let width: Double, height: Double, frameW: Double, frameH: Double
    public let baseX: Double, baseY: Double
    public let layout: Int, instances: Int
    public let clipX: Double, clipY: Double, clipW: Double, clipH: Double
    public init?(sequence: Double, scale: Double, angle: Double, leftX: Double, leftY: Double,
                 replicaX: Double, replicaY: Double, width: Double, height: Double,
                 frameW: Double, frameH: Double, baseX: Double, baseY: Double,
                 layout: Int, instances: Int, clipX: Double, clipY: Double, clipW: Double, clipH: Double) {
        let all = [sequence, scale, angle, leftX, leftY, replicaX, replicaY, width, height,
                   frameW, frameH, baseX, baseY, clipX, clipY, clipW, clipH]
        guard all.allSatisfy({ $0.isFinite }), scale > 0, width > 0, height > 0 else { return nil }
        self.sequence = sequence; self.scale = scale; self.angle = angle
        self.leftX = leftX; self.leftY = leftY; self.replicaX = replicaX; self.replicaY = replicaY
        self.width = width; self.height = height; self.frameW = frameW; self.frameH = frameH
        self.baseX = baseX; self.baseY = baseY; self.layout = layout; self.instances = instances
        self.clipX = clipX; self.clipY = clipY; self.clipW = clipW; self.clipH = clipH
    }
}

/// One presented frame, reported synchronously to gor (P25).
public struct PresentationReceipt: Equatable, Sendable {
    public let ptsSeconds: Double?          // nil = unknown, never a fabricated zero
    public let film: FilmFrameGeometry?     // nil = film frame not published (mode off)
    public let crop: NormalizedRect
    public let projection: ModeToken
    public let output: ModeToken
    public let revision: ParameterBlockRevision
    public let generation: UInt64           // presentation generation (bumps on seek or reopen)
    public init(ptsSeconds: Double?, film: FilmFrameGeometry?, crop: NormalizedRect,
                projection: ModeToken, output: ModeToken, revision: ParameterBlockRevision, generation: UInt64) {
        self.ptsSeconds = ptsSeconds; self.film = film; self.crop = crop
        self.projection = projection; self.output = output; self.revision = revision; self.generation = generation
    }
}

#if swift(>=5.5)
@MainActor
public protocol PresentationReceiptSink: AnyObject {
    func presented(_ receipt: PresentationReceipt)
}
#endif

public enum ReceiptVerdict: Equatable, Sendable {
    case accepted
    case regressedRevision(last: ParameterBlockRevision)   // counted, not recorded
    case staleSequence(floor: Double)                      // film sequence went backwards in this generation
    case staleGeneration(current: UInt64)                  // from before the last seek or reopen: dropped
    case nonFinitePts
}

/// Consumer side of P25. Applied state comes only from receipts: a control without its observer is not done.
public struct ReceiptLedger: Sendable {
    public private(set) var last: PresentationReceipt?
    public private(set) var framesSeen = 0
    public private(set) var regressions = 0
    public private(set) var currentGeneration: UInt64 = 0
    private var sequenceFloor: Double?
    public init() {}

    /// A seek or reopen starts a new generation: drops applied state and the sequence floor.
    public mutating func beginGeneration(_ g: UInt64) {
        currentGeneration = g
        last = nil
        sequenceFloor = nil
    }
    public mutating func consume(_ r: PresentationReceipt) -> ReceiptVerdict {
        if r.generation < currentGeneration { return .staleGeneration(current: currentGeneration) }
        if let p = r.ptsSeconds, !p.isFinite { return .nonFinitePts }
        if r.generation > currentGeneration { beginGeneration(r.generation) }
        if let f = r.film, let floor = sequenceFloor, f.sequence < floor { return .staleSequence(floor: floor) }
        framesSeen += 1
        if let l = last, r.revision < l.revision {
            regressions += 1
            return .regressedRevision(last: l.revision)
        }
        last = r
        if let f = r.film { sequenceFloor = f.sequence }
        return .accepted
    }
    /// True only once a presented frame carried a revision >= the requested one.
    public func isApplied(look revision: ParameterBlockRevision) -> Bool {
        guard let l = last else { return false }
        return l.revision >= revision
    }
    public var film: FilmFrameGeometry? { last?.film }
    public var appliedRevision: ParameterBlockRevision? { last?.revision }
}
