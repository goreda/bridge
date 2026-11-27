// Player/ExportRunLease.swift
// The queue-owned export run observation box and prepare-to-run transition: source-tagged events in, one immutable snapshot or prepared-run binding out.
// Uses: ExportFileIdentity, ExportAcceptedIdentity, ExportProducerRunContext, PhotonLoadGeneration
// Engine: mpv
import Foundation

/// A separately OPENED path observation (our own open+fstat of the path after the player loaded it). It is NOT the descriptor mpv holds and is never
/// documented as such: a replace between mpv's open and ours is not excluded. The identity the run is bound to is the accepted (session, opening, path).
public struct ExportPathObservation: Equatable {
    public var identity: ExportFileIdentity
    public init(identity: ExportFileIdentity) { self.identity = identity }
}

/// What the player has open and which producer run it was last observed under. An OBSERVATION snapshot, not a commit-owning lease.
/// - pathObservation: nil = unknown (kept open, never filled from a stat of a name).
/// - exportEpoch: the highest valid export epoch observed for this load and run; nil = none observed, never 0.
public struct PlayerCaptureSnapshot: Equatable {
    public var path: String
    public var generation: Int
    public var pathObservation: ExportPathObservation?
    public var accepted: ExportAcceptedIdentity
    public var runId: String?
    public var exportEpoch: Int64?
    public var lookPinSha256: String?
    public init(path: String, generation: Int, pathObservation: ExportPathObservation?, accepted: ExportAcceptedIdentity, runId: String?, exportEpoch: Int64?, lookPinSha256: String?) {
        self.path = path; self.generation = generation; self.pathObservation = pathObservation
        self.accepted = accepted; self.runId = runId; self.exportEpoch = exportEpoch; self.lookPinSha256 = lookPinSha256
    }
    /// The preflight/observation context. nil when run id or look pin is missing or invalid. The epoch may be nil and is carried as-is.
    public var runContext: ExportProducerRunContext? {
        guard let r = runId, ExportRunValidation.validRunId(r), let pin = lookPinSha256, ExportRunValidation.validPin(pin) else { return nil }
        if let e = exportEpoch, !ExportRunValidation.validEpoch(e) { return nil }
        return ExportProducerRunContext(identity: accepted, runId: r, exportEpoch: exportEpoch, lookPinSha256: pin)
    }
}

public enum ExportRunValidation {
    /// Existing parsed identity type: the scripts' hex-hex-hex run id, via the host receipt parser.
    public static func validRunId(_ s: String) -> Bool { PhotonLoadGeneration.parse(s + ":0:") != nil }
    /// A sha256 look pin: 64 lowercase hex.
    public static func validPin(_ s: String) -> Bool { s.utf8.count == 64 && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) } }
    public static let safeIntMax: Int64 = 9_007_199_254_740_991
    /// photon-common.lua reset parser: epoch > 0 and a safe integer (|v| <= 2^53-1).
    public static func validEpoch(_ e: Int64) -> Bool { e >= 1 && e <= safeIntMax }
}

/// The source a non-load event arrived under, captured by the CALLER when the message was read on the connection queue (never stamped from "whatever is
/// current" at callback time, which would turn an unlabelled wire message into a fake origin). The box only COMPARES it with the owner's load.
/// runId nil = the wire message carries none (ready/ack/fail/reset): it is tied to the pending request of the verified connection, never to an invented sender run id.
public struct ExportEventSource: Equatable {
    public var session: String
    public var opening: UInt64
    public var connectionEpoch: UInt64
    public var runId: String?
    public init(session: String, opening: UInt64, connectionEpoch: UInt64, runId: String?) { self.session = session; self.opening = opening; self.connectionEpoch = connectionEpoch; self.runId = runId }
}

public enum ExportRunEvent: Equatable {
    case fileLoaded(path: String, generation: Int, connectionEpoch: UInt64, pathObservation: ExportPathObservation?, accepted: ExportAcceptedIdentity, receiptRunId: String?)
    case runIdObserved(String, source: ExportEventSource)
    case lookPin(String, source: ExportEventSource)
    /// photon-export-reset: only establishes/advances the observed epoch and invalidates. It NEVER completes a prepare.
    case resetObserved(Int64, source: ExportEventSource)
    /// photon-export-ready <epoch> <script> (OUT, per reset). Only the exact pending epoch, from a required script, counts. photon-export-ack <epoch> <ordinal> <script> is per-request settlement, a different step this box does not model: it never prepares.
    case ready(epoch: Int64, script: String, source: ExportEventSource)
    /// photon-export-fail: fails a pending prepare for that exact epoch, invalidates a prepared run of that epoch. Never prepares.
    case exportFail(epoch: Int64, ordinal: Int64, script: String, source: ExportEventSource)
    case unloaded
}

public enum ExportRunApplyResult: Equatable {
    case applied
    case unchanged
    case rejected(ExportRunRejection)
}
public enum ExportRunRejection: Equatable {
    case noLoad, sessionMismatch, openingMismatch, connectionMismatch, runIdMismatch, invalidRunId, invalidPin, invalidEpoch, invalidScript
}

/// An observation context plus the box's change serial at the time it was read. beginPrepare accepts it only while nothing has changed since: an
/// invalidated prepare needs a NEW preflight, never the same old context accepted again because the fields happen to be equal.
public struct ExportPreflight: Equatable {
    public let context: ExportProducerRunContext
    public let serial: UInt64
    fileprivate init(context: ExportProducerRunContext, serial: UInt64) { self.context = context; self.serial = serial }
}

public enum ExportPrepareRefusal: Equatable {
    case noObservation, stalePreflight, invalidEpoch, notStrictlyNewer, alreadyPending, noRequiredScripts
}
public enum ExportPrepareFailure: Equatable {
    case unexpectedEpoch, changedDuringPrepare, scriptFailed(String), invalidated
}
public enum ExportPrepareState: Equatable {
    case idle
    case pending(requestedEpoch: Int64, awaiting: Set<String>)
    case prepared(ExportPreparedRun)
    case failed(ExportPrepareFailure)   // a fresh preflight and request are required
}

/// The separate immutable bound-run value: the untouched preflight context plus the run's own context at the exact requested epoch.
public struct ExportPreparedRun: Equatable {
    public let capture: ExportProducerRunContext
    public let run: ExportProducerRunContext
}

public final class ExportRunLeaseBox {
    private struct Pending { var requested: Int64; var required: Set<String>; var ready: Set<String>; var preflight: ExportProducerRunContext; var origin: ExportEventSource; var issued = false }
    private let lock = NSLock()
    private var snapshot: PlayerCaptureSnapshot?
    private var connectionEpoch: UInt64 = 0
    private var pending: Pending?
    private var state: ExportPrepareState = .idle
    private var serial: UInt64 = 0
    /// The highest epoch ever requested or observed in this process, kept across load/unload/restart. Every new request must exceed it, so an epoch number is never
    /// reused for a different request and a late reply from an older load can never match a newer pending request. (The wire carries no run id/nonce.)
    private var epochFloor: Int64 = 0
    /// Signalled (outside the lock) after any change of the prepare state: lets a waiter block on a condition instead of polling.
    public var onPrepareStateChange: (() -> Void)?
    public init() {}

    /// Connection queue only. Arrival order is never trusted: an event must match the owner's session/opening/connection (and run id when it carries one).
    @discardableResult
    public func apply(_ event: ExportRunEvent) -> ExportRunApplyResult {
        lock.lock()
        let before = state
        let r = reduce(event)
        if r == .applied { serial &+= 1 }
        let changed = state != before; let cb = onPrepareStateChange
        lock.unlock()
        if changed { cb?() }
        return r
    }

    private func reduce(_ event: ExportRunEvent) -> ExportRunApplyResult {
        switch event {
        case .fileLoaded(let path, let gen, let conn, let obs, let accepted, let receiptRun):
            let run = receiptRun.flatMap { ExportRunValidation.validRunId($0) ? $0 : nil }
            snapshot = PlayerCaptureSnapshot(path: path, generation: gen, pathObservation: obs, accepted: accepted, runId: run, exportEpoch: nil, lookPinSha256: nil)
            connectionEpoch = conn; invalidate(); return .applied
        case .unloaded:
            snapshot = nil; invalidate(); return .applied
        case .runIdObserved(let id, let src):
            guard var s = snapshot else { return .rejected(.noLoad) }
            if let r = checkSource(src, s, strictRun: false, allowRunNil: true) { return .rejected(r) }
            guard ExportRunValidation.validRunId(id) else { return .rejected(.invalidRunId) }
            if s.runId == id { return .unchanged }
            s.runId = id; s.exportEpoch = nil; s.lookPinSha256 = nil; snapshot = s
            invalidate(); return .applied
        case .lookPin(let pin, let src):
            guard var s = snapshot else { return .rejected(.noLoad) }
            if let r = checkSource(src, s, strictRun: true, allowRunNil: false) { return .rejected(r) }
            guard ExportRunValidation.validPin(pin) else { return .rejected(.invalidPin) }
            if s.lookPinSha256 == pin { return .unchanged }
            s.lookPinSha256 = pin; snapshot = s
            invalidate(); return .applied
        case .resetObserved(let e, let src):
            guard var s = snapshot else { return .rejected(.noLoad) }
            if let r = checkSource(src, s, strictRun: false, allowRunNil: true) { return .rejected(r) }
            guard ExportRunValidation.validEpoch(e) else { return .rejected(.invalidEpoch) }
            if let cur = s.exportEpoch, e <= cur { return .unchanged }   // stale/repeated reset (the scripts refuse it too)
            s.exportEpoch = e; snapshot = s; epochFloor = max(epochFloor, e)
            if let p = pending {
                if e != p.requested { state = .failed(.unexpectedEpoch); pending = nil }   // never adopted
                // e == requested: our own reset observed. Still pending: only the required ready/ack can prepare.
            } else if case .prepared = state { state = .failed(.invalidated) }
            return .applied
        case .ready(let e, let script, let src):
            guard var s = snapshot else { return .rejected(.noLoad) }
            if let r = checkSource(src, s, strictRun: false, allowRunNil: true) { return .rejected(r) }
            guard ExportRunValidation.validEpoch(e) else { return .rejected(.invalidEpoch) }
            guard !script.isEmpty else { return .rejected(.invalidScript) }
            recordParticipant(script, epoch: e)   // the script answered at this epoch: participant evidence, whatever the pending match below decides
            guard var p = pending, p.requested == e, p.issued, p.required.contains(script), !p.ready.contains(script) else { return .unchanged }   // stale/other epoch/unrequired/duplicate
            p.ready.insert(script)
            if let cur = s.exportEpoch, cur > e { return .unchanged }
            if s.exportEpoch == nil || s.exportEpoch! < e { s.exportEpoch = e; snapshot = s; epochFloor = max(epochFloor, e) }
            if s.runId != p.preflight.runId || src.connectionEpoch != p.origin.connectionEpoch { state = .failed(.changedDuringPrepare); pending = nil; return .applied }
            if p.ready == p.required, let pin = s.lookPinSha256, pin == p.preflight.lookPinSha256, s.accepted == p.preflight.identity, s.runId == p.preflight.runId {
                state = .prepared(ExportPreparedRun(capture: p.preflight, run: ExportProducerRunContext(identity: s.accepted, runId: p.preflight.runId, exportEpoch: e, lookPinSha256: pin)))
                pending = nil
            } else if p.ready == p.required { state = .failed(.changedDuringPrepare); pending = nil }
            else { pending = p; state = .pending(requestedEpoch: p.requested, awaiting: p.required.subtracting(p.ready)) }
            return .applied
        case .exportFail(let e, let ordinal, let script, let src):
            guard snapshot != nil, let s = snapshot else { return .rejected(.noLoad) }
            if let r = checkSource(src, s, strictRun: false, allowRunNil: true) { return .rejected(r) }
            guard ExportRunValidation.validEpoch(e) else { return .rejected(.invalidEpoch) }
            guard ordinal >= 0, ordinal <= ExportRunValidation.safeIntMax else { return .rejected(.invalidEpoch) }
            guard !script.isEmpty else { return .rejected(.invalidScript) }
            if let p = pending, p.requested == e { pending = nil; state = .failed(.scriptFailed(script)); return .applied }
            if case .prepared(let pr) = state, pr.run.exportEpoch == e { state = .failed(.scriptFailed(script)); return .applied }
            return .unchanged
        }
    }

    /// The current observation context with its change serial, or nil when run id/pin are missing.
    public func preflight() -> ExportPreflight? {
        lock.lock(); defer { lock.unlock() }
        guard let c = snapshot?.runContext else { return nil }
        return ExportPreflight(context: c, serial: serial)
    }

    /// nil = accepted. Request a strictly newer epoch for a FRESH preflight. The caller then asks the producer to reset to exactly `requestedEpoch`;
    /// only ready/ack from EVERY script in `requiredScripts` for exactly that epoch prepares the run. The required set comes from the real protocol's
    /// required-script semantics (the caller supplies it; this type invents no quorum).
    public func beginPrepare(preflight pf: ExportPreflight, requestedEpoch: Int64, requiredScripts: Set<String>, origin: ExportEventSource) -> ExportPrepareRefusal? {
        lock.lock(); defer { lock.unlock() }
        guard let s = snapshot, let cur = s.runContext else { return .noObservation }
        guard pf.serial == serial, pf.context == cur else { return .stalePreflight }
        guard ExportRunValidation.validEpoch(requestedEpoch) else { return .invalidEpoch }
        guard requestedEpoch > max(epochFloor, s.exportEpoch ?? 0) else { return .notStrictlyNewer }
        if let r = checkSource(origin, s, strictRun: false, allowRunNil: true) { _ = r; return .stalePreflight }   // the issuing context must be the owner's current one
        guard !requiredScripts.isEmpty, !requiredScripts.contains("") else { return .noRequiredScripts }
        if pending != nil { return .alreadyPending }
        pending = Pending(requested: requestedEpoch, required: requiredScripts, ready: [], preflight: pf.context, origin: origin)
        epochFloor = max(epochFloor, requestedEpoch)
        state = .pending(requestedEpoch: requestedEpoch, awaiting: requiredScripts)
        serial &+= 1
        return nil
    }

    /// Records, on the owner queue, that the host EMITTED the reset for the pending epoch (not that a hub echo came back: reset is a host-to-script command).
    /// Ready replies count only after this, and only while the box still sits under the origin the request was issued under.
    @discardableResult
    public func markResetIssued(epoch: Int64, source: ExportEventSource) -> ExportRunApplyResult {
        lock.lock(); defer { lock.unlock() }
        guard var s = snapshot, var p = pending else { return .rejected(.noLoad) }
        guard source == p.origin, checkSource(source, s, strictRun: false, allowRunNil: true) == nil else { return .rejected(.connectionMismatch) }
        guard p.requested == epoch, !p.issued else { return .unchanged }
        p.issued = true; pending = p
        if (s.exportEpoch ?? 0) < epoch { s.exportEpoch = epoch; snapshot = s }
        serial &+= 1
        return .applied
    }
    /// What established the cross-lifetime watermark, recorded as typed evidence (observation only; it grants nothing by itself).
    public enum ExportWatermarkBasis: Equatable {
        /// The exclusive issuer observed a session it had never seen. The session id is minted by the host immediately BEFORE the mpv process is launched
        /// (AppDelegate assigns PPController.cropPacketSession, then starts mpv), so a never-seen session comes with freshly loaded scripts: no barrier
        /// participant can hold an epoch from another lifetime. This is the lifecycle-owner source salvaged from the existing controller/player code.
        case freshLifecycle(session: String, opening: UInt64, connectionEpoch: UInt64)
        /// Every required barrier script was OBSERVED accepting an epoch (a validated ready wire event for its exact epoch), so the common floor is fixed
        /// by the participants themselves. A single owner's positive envelope epoch NEVER establishes this alone: it records one participant only. A FAIL
        /// is never participation evidence: a late fail echoes the guilty epoch, not the epoch the script accepted.
        case participantCoverage(floor: Int64)
    }
    private var watermarkBasisValue: ExportWatermarkBasis?
    /// Per-script participation: the highest epoch each script ACCEPTED (a validated ready carries script+epoch; the live envelope read counts as the owner
    /// script's acceptance). Missing participants are never assumed: coverage requires every required script, anything less keeps the watermark refused.
    private var participants: [String: Int64] = [:]
    /// Launch sessions verified by the EXCLUSIVE ISSUER (the host's real launch path: PPController.beginCropReceiverLaunch, called only when AppDelegate
    /// mints a fresh session and starts a new mpv). An observer seeing an unknown session is NOT freshness evidence: a controller attaching to an already
    /// running mpv has not seen its session either. Only a session recorded here may establish the fresh-lifecycle basis, once, at its first load.
    /// SCOPE (session-only voucher): the voucher binds the session STRING only. The process identifier and the launch-monotonic counters are NOT bound
    /// into note/consume: any process presenting the session string consumes the voucher (the session travels via --script-opts-add on the mpv command
    /// line, visible to local processes). That is accepted under the trusted-local threat model; do not read the voucher as pid-bound. The voucher is
    /// launch INTENT recorded before the process starts, not proof of a successful launch: the launch path revokes it on failure (revokeVerifiedLaunch).
    /// At most ONE voucher is outstanding: a new note purges the previous unconsumed voucher (single issuer makes that safe).
    private var verifiedLaunchSessions = Set<String>()
    /// `watermarkKnown` is explicit and starts false; an epoch floor of 0 never means "known". It becomes true only through a typed basis above and is
    /// cleared when a NEW lifetime (a different session) loads: participant coverage and the basis belong to the lifetime that produced them and never
    /// leak into a new process. The historical epoch FLOOR stays monotone across lifetimes (a new request is strictly newer than everything ever seen);
    /// only the authority/basis is lifetime-scoped. Observation only; it grants nothing. A basis is never liveness: a process that dies after its first
    /// load leaves a standing basis until the next lifetime begins.
    public var watermarkKnown: Bool { lock.lock(); defer { lock.unlock() }; return watermarkBasisValue != nil }
    /// The recorded watermark evidence, nil while unknown.
    public func watermarkBasis() -> ExportWatermarkBasis? { lock.lock(); defer { lock.unlock() }; return watermarkBasisValue }
    /// The recorded per-script participation state (script -> highest observed epoch). Missing scripts are absent, never zero-filled.
    public func participantState() -> [String: Int64] { lock.lock(); defer { lock.unlock() }; return participants }
    /// Fresh-lifecycle evidence from the exclusive issuer, with its origin recorded. Called ONLY by the observer after a consumed voucher, on the
    /// session's FIRST load (opening 1). Records the basis; never lowers the floor.
    public func establishFreshLifecycleWatermark(origin: ExportEventSource) {
        lock.lock(); defer { lock.unlock() }
        watermarkBasisValue = .freshLifecycle(session: origin.session, opening: origin.opening, connectionEpoch: origin.connectionEpoch)
    }
    /// The exclusive issuer (real launch path) vouches that this session belongs to a process it is about to launch. Launch time has no
    /// opening/connection yet: the session is recorded here, and the basis is bound to its first load's full origin (session+opening+connectionEpoch)
    /// via consumeVerifiedLaunch. A new vouch replaces any unconsumed earlier one (single issuer: at most one launch can be outstanding).
    public func noteVerifiedLaunch(session: String) {
        lock.lock(); defer { lock.unlock() }
        guard !session.isEmpty else { return }
        verifiedLaunchSessions = [session]
    }
    /// The launch path's failure hook: the process was never started (or died before its first load), so the intent voucher is revoked. Revoking an
    /// already-consumed or foreign session is a no-op.
    public func revokeVerifiedLaunch(session: String) {
        lock.lock(); defer { lock.unlock() }
        verifiedLaunchSessions.remove(session)
    }
    /// A NEW lifetime loaded (a session this box has not seen): participant coverage and the watermark basis of the previous lifetime are dropped —
    /// they were produced by another process and never bind the new one. The historical epoch floor stays monotone (never lowered): basis/authority is
    /// lifetime-scoped, the floor is not. Called by the observer when a session loads that the box is not already tracking; a later ATTACH to the
    /// same still-running session (another observer, a reconnect) is the same lifetime and clears nothing.
    private var lifetimeSession: String?
    public func beginNewLifetime(session: String) {
        lock.lock(); defer { lock.unlock() }
        guard lifetimeSession != session else { return }
        lifetimeSession = session
        participants.removeAll()
        watermarkBasisValue = nil
    }
    /// One-shot: true exactly once for a session the launch owner vouched for. The observer calls this at a load; only a vouched session's FIRST load may
    /// establish the fresh-lifecycle basis (a later attach to the same running process finds the voucher consumed and establishes nothing).
    public func consumeVerifiedLaunch(session: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return verifiedLaunchSessions.remove(session) != nil
    }
    /// Records one participant's answer at an epoch (caller already validated both) and completes the coverage basis when every required script has answered. Caller holds the lock.
    private func recordParticipant(_ script: String, epoch e: Int64) {
        participants[script] = max(participants[script] ?? 0, e)
        if epochFloor < e { epochFloor = e }
        if ExportBarrierScripts.required.allSatisfy({ participants[$0] != nil }) { watermarkBasisValue = .participantCoverage(floor: epochFloor) }
    }
    /// The scripts' own envelope epoch observed live (another controller lifetime, an earlier app run, a script reload) raises the floor so a new request is strictly newer than what the
    /// scripts already hold and records the OWNER script's acceptance at that epoch. Monotone; nil = the scripts report no epoch: ignored (a readable envelope with no epoch neither
    /// proves nor disproves a prior export). A positive owner epoch ALONE is one participant of five: it does NOT establish the common watermark; missing participant states stay refused.
    public func observeLiveEnvelope(epoch e: Int64?) {
        lock.lock(); defer { lock.unlock() }
        guard let e else { return }
        guard ExportRunValidation.validEpoch(e) else { return }
        recordParticipant("photon", epoch: e)
    }
    /// The smallest epoch a NEW request may use: above every epoch ever requested or observed. nil = no load, or exhausted (never wraps; the caller refuses).
    public func nextRequestEpoch() -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard let s = snapshot else { return nil }
        let base = max(epochFloor, s.exportEpoch ?? 0)
        return base < ExportRunValidation.safeIntMax ? base + 1 : nil
    }
    /// Attempt-scoped invalidation: drops the pending request OR the prepared run that belongs to exactly this epoch, and nothing else (a newer unrelated request or
    /// run is untouched). The epoch stays burned in the floor. Returns whether anything was dropped.
    @discardableResult
    public func abandon(epoch: Int64) -> Bool {
        lock.lock()
        var changed = false
        if let p = pending, p.requested == epoch { pending = nil; state = .failed(.invalidated); changed = true }
        else if case .prepared(let pr) = state, pr.run.exportEpoch == epoch { state = .failed(.invalidated); changed = true }
        if changed { serial &+= 1 }
        let cb = onPrepareStateChange
        lock.unlock()
        if changed { cb?() }
        return changed
    }
    /// The connection epoch the box currently observes (nil: no load).
    public func observedConnectionEpoch() -> UInt64? { lock.lock(); defer { lock.unlock() }; return snapshot == nil ? nil : connectionEpoch }

    public func prepareState() -> ExportPrepareState { lock.lock(); defer { lock.unlock() }; return state }
    public func preparedRun() -> ExportPreparedRun? { lock.lock(); defer { lock.unlock() }; if case .prepared(let p) = state { return p }; return nil }
    public func current() -> PlayerCaptureSnapshot? { lock.lock(); defer { lock.unlock() }; return snapshot }
    /// The observation context. NOT a commit-owning lease and not the run binding.
    public func runContext() -> ExportProducerRunContext? { current()?.runContext }
    /// The run binding for feed/fence/commit comparison: the prepared run's context, or nil (refused). Never the bare observation.
    public func boundRunContext() -> ExportProducerRunContext? { preparedRun()?.run }

    private func invalidate() {
        switch state { case .pending, .prepared: state = .failed(.invalidated); default: break }
        pending = nil
    }
    private func checkSource(_ src: ExportEventSource, _ s: PlayerCaptureSnapshot, strictRun: Bool, allowRunNil: Bool) -> ExportRunRejection? {
        if src.session != s.accepted.session { return .sessionMismatch }
        if src.opening != s.accepted.opening { return .openingMismatch }
        if src.connectionEpoch != connectionEpoch { return .connectionMismatch }
        if strictRun { guard let r = s.runId, src.runId == r else { return .runIdMismatch } }
        else if let sr = src.runId, sr != s.runId { return .runIdMismatch }
        return nil
    }
}

/// The scripts that answer a photon export reset with photon-export-ready: those that call export_join() in photon-common.lua. READY-ONLY: this set gates prepare by ready alone; the per-request
/// photon-export-ack (frame settlement) is deliberately not modelled here and never counts as readiness.
/// Derived from Ops' read of 46017ec7 (owner photon.lua L6897; grain L1320, negativ L1350, chrome L933, sharp L1564; photon-hud does not join). It is a SEPARATE contract from the
/// four-component chain seal (owner excluded) and from the snapshot envelope's requiredScripts, which share names but not meaning. The exact mp.get_script_name() strings
/// are the mpv script names: the shipped code addresses these scripts as photon, photon_grain, photon_negativ, photon_chrome, photon_sharp in script-message-to (MenuActions L500-504,
/// MPVCommand L280), so mpv's name for photon-grain.lua is photon_grain (hyphen to underscore). photon-sharp.lua, photon-chrome.lua, photon-negativ.lua, photon-grain.lua exist in the
/// scripts folder. No loader/config in the sources lists names; the runtime get_script_name() output itself was never observed: UNVERIFIED at runtime.
public enum ExportBarrierScripts {
    public static let required: Set<String> = ["photon", "photon_grain", "photon_negativ", "photon_chrome", "photon_sharp"]
}
