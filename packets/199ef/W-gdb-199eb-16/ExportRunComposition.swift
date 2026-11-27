import Foundation
import Dispatch
import GorAVCore

/// As-seen export composition: the ONE constructor that binds a prepared lease run, its owned commit, the
/// owner-queue identity, the run-scoped queued-run purge, and the reset emitter together. The panel/Start
/// wiring is a separate change (not this task); this binds the seam itself over the existing
/// makeRGBA64 constructor, which stays the single real runner construction.
///
/// Invariants bound here:
///  - (a) queuedRunPurge is handed through the source's CONSTRUCTOR, never assigned after.
///  - (b) the runner's owned commit runs the source's commitUnderOwner on the owner queue over the SAME
///    prepared binding the runner's fence verifies.
///  - (d) the owner queue is the caller's engine-sourced instance (MPVCommand.exportOwnerQueue); every
///    owner transaction the composition creates targets that one queue.
///  - reset emitter: carries the RESERVATION run id (capture.loadReceipt.runId). At reset-emit time the
///    prepared run does not exist yet, so an emitter reading preparedRun would mint a nil-run line a
///    run-scoped cancel can never catch (the pre-fix hole).
public enum ExportRunComposition {

    /// Everything a bound run hands back: the source (cancel/commit owner), the prepared producer, the
    /// verified binding, and the constructed runner (capture fence + owned commit included).
    public struct BoundRun {
        public let source: ExportLeasePixelSource
        public let producer: PhotonExportProducer
        public let binding: ExportPreparedRun
        public let runner: ExportJobRunner
    }

    public enum Refusal: Error, Equatable {
        case prepare(ExportLeaseSourceError)
        /// The producer's own typed prepare refusal (init/prepare), carried losslessly — never re-labelled.
        case producer(PhotonExportProducerError)
        /// A prepare-phase error that is neither typed case, carried by its description (never a fabricated reason).
        case prepareOther(String)
        case runner(ExportRunUnavailable)
    }

    /// Bind a real run: prepare the lease source, then construct the runner over the SAME binding.
    /// - enqueueLine: the Engine-owned line mint (MPVCommand.enqueueExportLine shape): line + owner
    ///   session/opening + run id + attempt, with the tag type never leaving Engine.
    /// - dropRun: the outbox's run-scoped purge (MPVCommand.dropExportRun shape).
    /// - resetTiming: the wire timing legs for the reset line (the run's resolved ExportWireTimeline). nil = the timeline
    ///   was never resolved for this run: the reset emit fails typed, nothing is queued.
    /// - makeFeed: receives the lease source AND the prepared PhotonExportProducer (itself an ExportRGBA64FrameFeed). The product feed is `preparedProducerFeed` (the prepared producer, no second feed);
    ///   a test may build its own. It runs AFTER the source exists, so its run context can read the
    ///   source's live run token; makeRGBA64 checks it against the prepared binding at construction
    ///   (the product ordering is prepare-first, construct-after).
    /// The product `makeFeed`: the prepared producer IS the frame feed (decision: one producer per run, never a second feed over the same source).
    public static let preparedProducerFeed: (ExportLeasePixelSource, PhotonExportProducer) -> ExportRGBA64FrameFeed? = { _, producer in producer }

    public static func bindRun(box: ExportRunLeaseBox, wire: ExportWireObserver, inner: PhotonExportPixelSource,
                               ownerQueue: DispatchQueue, capture: ExportLookCapture,
                               contract: PhotonExportReadbackContract, timeBase: ExportTimeBase,
                               enqueueLine: @escaping (_ line: String, _ session: String, _ opening: UInt64, _ runId: String?, _ attempt: UInt64?) -> Bool,
                               dropRun: @escaping (String) -> Void,
                               resetTiming: @escaping () -> (ptsUs: Int64, originUs: Int64)?,
                               frameChannel: ExportFrameWireChannel? = nil,
                               result: ExportPreflightResult, adapter: ExportSnapshotAdapter,
                               backend: ExportRGBA64Backend?, makeFeed: (ExportLeasePixelSource, PhotonExportProducer) -> ExportRGBA64FrameFeed?,
                               fileSystem: ExportFileSystem, admission: ExportAdmission,
                               requireVideoEndProof: Bool,
                               copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?) -> Result<BoundRun, Refusal> {
        let emitter = ExportWireEmitter(enqueue: { line in
            let owner = wire.currentOwner()
            return enqueueLine(line, owner?.session ?? "", owner?.opening ?? 0, capture.loadReceipt.runId, nil)
        })
        let source = ExportLeasePixelSource(box: box, wire: wire, inner: inner, ownerQueue: ownerQueue, capture: capture,
                                            queuedRunPurge: dropRun,
                                            frameChannel: frameChannel,
                                            emitReset: { epoch in
                                                // nil = the run's wire timeline was never resolved (the plan read failed before bind):
                                                // typed, never a (0,0) default (W-gdb-199eb-22).
                                                guard let t = resetTiming() else { throw ExportResetTimingError.noTimeline }
                                                try emitter.reset(epoch: epoch, ptsUs: t.ptsUs, originUs: t.originUs)
                                            })
        let prepared: (producer: PhotonExportProducer, binding: ExportPreparedRun)
        do { prepared = try source.startProducer(contract: contract, timeBase: timeBase) }
        catch let e as ExportLeaseSourceError { return .failure(.prepare(e)) }
        catch let e as PhotonExportProducerError { return .failure(.producer(e)) }
        catch { return .failure(.prepareOther("\(error)")) }
        let feed = makeFeed(source, prepared.producer)   // kept local: on a construction refusal it was never handed off and the composition releases it exactly once
        let runner = ExportRunConstruction.makeRGBA64(result: result, adapter: adapter,
                                                      currentRunToken: { source.runToken() },
                                                      prepared: prepared.binding,
                                                      ownedCommit: { body in source.commitUnderOwner(prepared.binding, body) },
                                                      backend: backend, feed: feed,
                                                      fileSystem: fileSystem, admission: admission,
                                                      requireVideoEndProof: requireVideoEndProof,
                                                      copyProof: copyProof, copyProofInterrupt: copyProofInterrupt)
        switch runner {
        case .success(let r): return .success(BoundRun(source: source, producer: prepared.producer, binding: prepared.binding, runner: r))
        case .failure(let e):
            // Refusal cleanup scope — the composition factory owns the outcome of what it created:
            // - the feed was never handed off (makeRGBA64 never releases a borrowed/created feed on refusal): release it here, exactly once.
            // - the source holds a prepared/bound run with its reset line queued: cancel purges both (the constructor-bound
            //   queuedRunPurge drops the run's queued outbox lines; the in-flight attempt is abandoned; the prepared run is invalidated).
            // - the borrowed BACKEND stays the caller's: makeRGBA64 never opened or closed it, and this composition does not take its ownership.
            feed?.release()
            source.cancel()
            return .failure(.runner(e))
        }
    }
}

/// The reset line's timing legs could not be produced: the run's wire timeline was never resolved (the source pts plan
/// read failed before bind). Typed, never a (0,0) default; the lease maps it to .resetEmitFailed.
public enum ExportResetTimingError: Error, Equatable { case noTimeline }

/// The typed Player start operation: the ONE owner of a started export's lifecycle (gate, bind, run, cancel, terminal cleanup). The panel/App only expresses intent
/// (start / cancel) and shows terminal results; it never holds the source, runner, wire or feed. Nothing here is a default-on path: with no plan or no provider
/// nothing is bound.
///
/// Lifecycle (one operation = at most one run in flight; a LATER start is a new run, accepted only once the previous run's teardown debt is settled):
///  - start(): synchronous gate. .alreadyRunning while a start/run is in flight (double click = ONE bind); .tearingDown while the previous run's native close / source release /
///    admission scope is still pending (a terminal UI result is NOT lifecycle freedom); .noPlan / .noProvider bind nothing.
///    The bind itself (source prepare blocks off the owner queue) and the run happen on `background`, never on the caller.
///  - backend ownership: bindRun BORROWS the backend and never closes it on refusal. The operation creates it (`makeBackend`) and closes it EXACTLY ONCE when bind refuses
///    (bindRun created nothing that holds it). When bind succeeds the runner's pipeline owns it (closed by run's own terminal path, or by runner.discard on a cancel before the run);
///    the operation then never closes it. The backend never reaches the App. Its native close may be asynchronous: the operation keeps the object and counts its closePending in the
///    teardown debt on every terminal path.
///  - cancel(): no-op when idle or tearing down (Cancel before Export = nothing). While STARTING it is latched: the bound run is discarded (runner.discard + source.cancel) and run() is
///    never entered. Once RUNNING (including the instant between the phase flip and the run() call) it latches runner.stop(.cancelled) and cancels the source; run() MAY still be entered,
///    and then returns the stopped terminal.
///  - terminal: exactly one callback per accepted start, on `background` (the App binds main delivery). With no teardown pending the phase is already idle when it fires (a reentrant
///    start is accepted); with teardown pending it fires in .tearingDown and the phase turns idle only after the pending debt clears.
///  - the source of a bound run is cancelled exactly once on every terminal path (idempotent first-cancel claim inside the source).
public final class ExportStartOperation {
    public enum Decision: Equatable { case started, alreadyRunning, tearingDown, noPlan, noProvider }
    public enum Terminal: Equatable {
        case refused(ExportRunComposition.Refusal)   // bind refused: nothing left behind, the borrowed backend closed once
        case cancelledBeforeRun                       // cancel landed before the run was entered; the bound run was discarded
        case finished(ExportRunResult)                // the runner's own typed result (published / stopped / failed)
    }
    private enum Phase { case idle, starting, running, tearingDown }
    private let lock = NSLock()
    private var phase = Phase.idle
    private var cancelLatched = false
    private var current: ExportRunComposition.BoundRun?
    private let background: DispatchQueue
    private let makeBackend: () -> ExportRGBA64Backend?
    private let bind: (ExportRGBA64Backend?) -> Result<ExportRunComposition.BoundRun, ExportRunComposition.Refusal>
    private let run: (ExportRunComposition.BoundRun) -> ExportRunResult
    private let teardownPending: (ExportRunComposition.BoundRun) -> Bool
    private let scopeBusy: () -> Bool
    private let pollInterval: TimeInterval
    private let onTerminal: (Terminal) -> Void

    /// `teardownPending` defaults to the source's own release debt (in-flight seal queries + inner native release); `scopeBusy` is the runner's admission scope
    /// (the real caller passes `{ admission.isBusy }`: the runner holds it until its native close settled). No second admission system is created here.
    public init(background: DispatchQueue,
                makeBackend: @escaping () -> ExportRGBA64Backend?,
                bind: @escaping (ExportRGBA64Backend?) -> Result<ExportRunComposition.BoundRun, ExportRunComposition.Refusal>,
                run: @escaping (ExportRunComposition.BoundRun) -> ExportRunResult = { $0.runner.run() },
                teardownPending: @escaping (ExportRunComposition.BoundRun) -> Bool = { $0.source.releasePending },
                scopeBusy: @escaping () -> Bool = { false },
                pollInterval: TimeInterval = 0.02,
                onTerminal: @escaping (Terminal) -> Void) {
        self.background = background; self.makeBackend = makeBackend; self.bind = bind; self.run = run
        self.teardownPending = teardownPending; self.scopeBusy = scopeBusy; self.pollInterval = pollInterval; self.onTerminal = onTerminal
    }

    public var isInFlight: Bool { lock.lock(); defer { lock.unlock() }; return phase != .idle }
    /// The typed busy answer for a caller that builds a NEW operation per start: nil only when idle (a fresh start may proceed), else why a start would be refused.
    public var busyDecision: Decision? {
        lock.lock(); defer { lock.unlock() }
        switch phase { case .idle: return nil; case .tearingDown: return .tearingDown; case .starting, .running: return .alreadyRunning }
    }

    /// Stage 1: admission + `.starting` (cancel latch armed, nothing enqueued yet). A cancel from here on is written to the starting latch.
    /// `.started` here means "armed": the caller MUST follow with `launch()` exactly once. fileprivate: only ExportStartCoordinator (and start()) use the two-part surface; outside callers have start/cancel.
    fileprivate func arm(hasPlan: Bool, hasProvider: Bool) -> Decision {
        guard hasPlan else { return .noPlan }
        guard hasProvider else { return .noProvider }
        lock.lock(); defer { lock.unlock() }
        switch phase {
        case .idle: break
        case .tearingDown: return .tearingDown
        case .starting, .running: return .alreadyRunning
        }
        phase = .starting; cancelLatched = false
        return .started
    }
    /// Stage 3: enqueue the bind/run on the background queue (only after the armed latch received any earlier cancel).
    fileprivate func launch() { background.async { [self] in work() } }

    @discardableResult
    public func start(hasPlan: Bool, hasProvider: Bool) -> Decision {
        let d = arm(hasPlan: hasPlan, hasProvider: hasProvider)
        if d == .started { launch() }
        return d
    }

    public func cancel() {
        lock.lock()
        switch phase {
        case .idle, .tearingDown: lock.unlock()
        case .starting: cancelLatched = true; lock.unlock()
        case .running:
            let b = current; lock.unlock()
            b?.runner.stop(.cancelled)
            b?.source.cancel()
        }
    }

    /// Teardown debt, read WITHOUT holding the internal lock (the closures are external code and may read isInFlight): the admission scope, the bound source's release debt, and
    /// the backend this operation created (its own native close may outlive close(); a refusal or a pre-run discard takes no admission, so only this covers it).
    private func pending(_ b: ExportRunComposition.BoundRun?, _ backend: ExportRGBA64Backend?) -> Bool {
        if scopeBusy() { return true }
        if backend?.closePending == true { return true }
        if let b { return teardownPending(b) }
        return false
    }

    /// Terminal delivery + phase release. The phase is published as .tearingDown BEFORE the debt is read (no start can slip in between); the debt is checked outside the lock.
    /// Clear debt: idle first, then the callback (a reentrant start is accepted). Pending debt: the callback fires in .tearingDown and the phase turns idle only after it clears.
    /// `backend` stays strongly held here until the drain ends (a closed-but-pending backend object is not freed under its own native close).
    private func finish(_ t: Terminal, bound b: ExportRunComposition.BoundRun?, backend: ExportRGBA64Backend?) {
        lock.lock(); current = nil; cancelLatched = false; phase = .tearingDown; lock.unlock()
        let debt = pending(b, backend)
        if !debt { lock.lock(); phase = .idle; lock.unlock(); onTerminal(t); withExtendedLifetime(backend) {}; return }
        onTerminal(t)
        while pending(b, backend) { Thread.sleep(forTimeInterval: pollInterval) }
        lock.lock(); phase = .idle; lock.unlock()
        withExtendedLifetime(backend) {}
    }

    private func work() {
        let backend = makeBackend()
        switch bind(backend) {
        case .failure(let r):
            backend?.close()   // bindRun borrowed it and released nothing of it: the operation closes it, once
            finish(.refused(r), bound: nil, backend: backend)
        case .success(let b):
            lock.lock()
            if cancelLatched {
                lock.unlock()
                b.runner.discard(); b.source.cancel()   // discard releases the pipeline, which closes the backend (runner owns it now)
                finish(.cancelledBeforeRun, bound: b, backend: backend)
                return
            }
            current = b; phase = .running
            lock.unlock()
            let result = run(b)
            b.source.cancel()   // terminal cleanup on every path (idempotent first-cancel claim inside the source): purge, abandon, invalidate the prepared run
            finish(.finished(result), bound: b, backend: backend)
        }
    }
}

/// The legs only the Player controller owns (live connection, owner queue, run lease box, wire observer). Raw closures: the Engine tag type never appears here.
public struct ExportControllerLegs {
    public let box: ExportRunLeaseBox
    public let wire: ExportWireObserver
    public let ownerQueue: DispatchQueue
    public let enqueueLine: (_ line: String, _ session: String, _ opening: UInt64, _ runId: String?, _ attempt: UInt64?) -> Bool
    public let dropRun: (String) -> Void
    public init(box: ExportRunLeaseBox, wire: ExportWireObserver, ownerQueue: DispatchQueue,
                enqueueLine: @escaping (String, String, UInt64, String?, UInt64?) -> Bool, dropRun: @escaping (String) -> Void) {
        self.box = box; self.wire = wire; self.ownerQueue = ownerQueue; self.enqueueLine = enqueueLine; self.dropRun = dropRun
    }
}

/// The per-plan products the Picture/COLOUR/PANELS lanes resolve before Start (preflight result, adapter, look capture, readback contract, renderer source, backend provider).
/// `admission` is the ONE admission the runner holds for the run: the same object feeds bindRun and the operation's teardown debt (`scopeBusy`), so the two can never disagree.
public struct ExportStartInputs {
    public let result: ExportPreflightResult
    public let adapter: ExportSnapshotAdapter
    public let capture: ExportLookCapture
    public let contract: PhotonExportReadbackContract
    public let inner: PhotonExportPixelSource
    public let timeBase: ExportTimeBase
    public let makeBackend: () -> ExportRGBA64Backend?
    public let makeFeed: (ExportLeasePixelSource, PhotonExportProducer) -> ExportRGBA64FrameFeed?
    public let fileSystem: ExportFileSystem
    public let admission: ExportAdmission
    public let requireVideoEndProof: Bool
    public let copyProof: ((ExportPartialFile) -> String?)?
    public let copyProofInterrupt: (() -> Void)?
    public let resetTiming: () -> (ptsUs: Int64, originUs: Int64)?
    /// Builds the per-frame wire channel for this run from the controller's legs. nil (the default) or a nil result keeps the
    /// frame wire closed: every frame acquisition then refuses with noFrameChannel.
    public let makeFrameChannel: ((ExportControllerLegs) -> ExportFrameWireChannel?)?
    public init(result: ExportPreflightResult, adapter: ExportSnapshotAdapter, capture: ExportLookCapture, contract: PhotonExportReadbackContract,
                inner: PhotonExportPixelSource, timeBase: ExportTimeBase, makeBackend: @escaping () -> ExportRGBA64Backend?,
                makeFeed: @escaping (ExportLeasePixelSource, PhotonExportProducer) -> ExportRGBA64FrameFeed?, fileSystem: ExportFileSystem, admission: ExportAdmission,
                requireVideoEndProof: Bool, copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?,
                resetTiming: @escaping () -> (ptsUs: Int64, originUs: Int64)?,
                makeFrameChannel: ((ExportControllerLegs) -> ExportFrameWireChannel?)? = nil) {
        self.makeFrameChannel = makeFrameChannel
        self.result = result; self.adapter = adapter; self.capture = capture; self.contract = contract; self.inner = inner; self.timeBase = timeBase
        self.makeBackend = makeBackend; self.makeFeed = makeFeed; self.fileSystem = fileSystem; self.admission = admission
        self.requireVideoEndProof = requireVideoEndProof; self.copyProof = copyProof; self.copyProofInterrupt = copyProofInterrupt; self.resetTiming = resetTiming
    }
}

extension ExportStartOperation {
    /// The single production assembly (the only place the raw bindRun parts are built): the backend `makeBackend` creates is the SAME object handed to bindRun (and then to the runner's
    /// pipeline), the operation closes it only on a bind refusal, and `scopeBusy` is the real admission. A frame channel is composed here only when the inputs carry a factory and it returns one; otherwise the frame wire stays noChannel (fail-closed),
    /// a bound run on today's evidence still refuses frame acquisition. Nothing starts until a caller calls `start`.
    public static func production(background: DispatchQueue, legs: ExportControllerLegs, inputs i: ExportStartInputs,
                                  onTerminal: @escaping (Terminal) -> Void) -> ExportStartOperation {
        ExportStartOperation(background: background, makeBackend: i.makeBackend, bind: { backend in
            ExportRunComposition.bindRun(box: legs.box, wire: legs.wire, inner: i.inner, ownerQueue: legs.ownerQueue, capture: i.capture,
                                         contract: i.contract, timeBase: i.timeBase, enqueueLine: legs.enqueueLine, dropRun: legs.dropRun,
                                         resetTiming: i.resetTiming, frameChannel: i.makeFrameChannel?(legs), result: i.result, adapter: i.adapter, backend: backend,
                                         makeFeed: i.makeFeed, fileSystem: i.fileSystem, admission: i.admission,
                                         requireVideoEndProof: i.requireVideoEndProof, copyProof: i.copyProof, copyProofInterrupt: i.copyProofInterrupt)
        }, scopeBusy: { [admission = i.admission] in admission.isBusy }, onTerminal: onTerminal)
    }
}

/// Single-flight start coordination for ONE controller (what exportStartFromPanel delegates to; Linux-testable). The internal lock covers ONLY the reservation / publish / cancel latch:
/// NO external code runs under it (provider, build, operation start and the cancelled callback all run outside). A reservation (`preparing`) keeps a concurrent start at .alreadyRunning
/// from the first check until the operation was LAUNCHED. Order after publish (arm → transfer → launch):
///  1. `op.arm`: the operation becomes .starting with its cancel latch armed; nothing is enqueued on the background queue yet;
///  2. transfer: the coordinator's own cancel latch (a cancel that landed before the arm, when op.cancel would have been a no-op on an idle operation) is handed to the armed operation as op.cancel();
///     a cancel arriving after the arm reaches the operation's .starting latch directly (the reservation is still active, so it also sets the coordinator flag);
///  3. `op.launch`: only now is the bind/run enqueued; a latched start discards the bound run and never enters run().
/// Cancel before publish: latched, the prepared inputs/operation are DROPPED (nothing bound, the backend never created), terminal .cancelledBeforeRun. Cancel while running: runner.stop latched; an already-finished run is a no-op.
/// The provider must only prepare plan products: no probe/IO on the main thread.
public final class ExportStartCoordinator {
    private let lock = NSLock()
    private var operation: ExportStartOperation?
    private var preparing = false
    private var cancelDuringPrepare = false
    /// TEST SEAM ONLY: runs outside the lock between the operation's publish and op.start (the window a cancel used to fall through). nil in production.
    private let betweenPublishAndStart: (() -> Void)?
    /// TEST SEAM ONLY: runs outside the lock right after launch (lets a test observe the background having advanced). nil in production.
    private let afterLaunch: (() -> Void)?
    public init(betweenPublishAndStart: (() -> Void)? = nil, afterLaunch: (() -> Void)? = nil) { self.betweenPublishAndStart = betweenPublishAndStart; self.afterLaunch = afterLaunch }

    @discardableResult
    public func start(hasPlan: Bool, prepare: (() -> ExportStartInputs?)?,
                      build: (ExportStartInputs) -> ExportStartOperation,
                      onCancelledWhilePreparing: () -> Void) -> ExportStartOperation.Decision {
        lock.lock()
        if preparing { lock.unlock(); return .alreadyRunning }
        if let busy = operation?.busyDecision { lock.unlock(); return busy }
        guard hasPlan else { lock.unlock(); return .noPlan }
        guard let prepare else { lock.unlock(); return .noProvider }
        preparing = true; cancelDuringPrepare = false
        lock.unlock()
        let inputs = prepare()   // external code, lock NOT held
        lock.lock()
        guard let inputs else { preparing = false; lock.unlock(); return .noProvider }
        if cancelDuringPrepare { preparing = false; cancelDuringPrepare = false; lock.unlock(); onCancelledWhilePreparing(); return .started }
        lock.unlock()
        let op = build(inputs)   // external code, lock NOT held (reservation still active: a concurrent start answers .alreadyRunning, a cancel latches)
        lock.lock()
        if cancelDuringPrepare { preparing = false; cancelDuringPrepare = false; lock.unlock(); onCancelledWhilePreparing(); return .started }   // built but never started: dropped
        operation = op
        lock.unlock()
        betweenPublishAndStart?()
        let d = op.arm(hasPlan: true, hasProvider: true)   // stage 1: operation is .starting, nothing enqueued
        lock.lock()
        let late = cancelDuringPrepare; if d != .started { preparing = false; cancelDuringPrepare = false }
        lock.unlock()
        guard d == .started else { return d }
        if late { op.cancel() }   // stage 2: hand the coordinator's latch to the armed operation (a cancel arriving from now on reaches .starting directly)
        op.launch()               // stage 3: enqueue only after the transfer
        afterLaunch?()
        lock.lock(); preparing = false; cancelDuringPrepare = false; lock.unlock()
        return d
    }

    /// Cancel before Export = nothing; while a start is being prepared/handed off it latches; otherwise it forwards to the operation (starting latch / running stop).
    public func cancel() {
        lock.lock()
        if preparing { cancelDuringPrepare = true }
        let op = operation
        lock.unlock()
        op?.cancel()
    }
}

/// Lock-guarded cell for the controller's start provider (set by the composition root, read by the panel path). Holds only the closure; it never calls it.
public final class ExportStartProviderCell {
    private let lock = NSLock(); private var v: ((ExportPreflightResult) -> ExportStartInputs?)?
    public init() {}
    public var value: ((ExportPreflightResult) -> ExportStartInputs?)? { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

/// The plan-time (E0) render observation bridge: one bounded real probe of the renderer owner for the SAME job as a look capture, handed to the preflight as `ExportRenderObservation`
/// (`ExportAsSeenAction.renderReceiptSource`). It evaluates NOTHING: the verdict stays with `ExportRenderReceiptEvidence` (derive/refusal). This only decides whether a probe may be asked at all
/// and wraps the answer. Typed unavailable at every missing leg (no epoch, no owner fence, no contract, no identity), and the probe is not called then:
///  - the capture must be verified with an accepted identity, and carry its own export epoch E0 (nil = `.captureEpochUnavailable`, no epoch is invented);
///  - the frame identity is REQUIRED from the caller's owner-fenced provider (no "last uploaded frame" default: uploaded is not presented and not same-job);
///  - the owner fence (accepted-load state) is read by the provider on the owner queue, not here.
/// E0 evidence is plan-time route/render capability evidence only; it is never an E1 output-frame proof. `sealProof` stays nil here (no production chain supplies one) and framesBakedAsSeen is not promoted.
/// The exact legs are the renderer owner's own NEXT-MINT RESERVATION (`reserve`): token, photon epoch, mint counter before the mint and targets, taken in one renderer-locked read BEFORE
/// the probe and consumed by the probe's own render in the renderer's check->mint transaction. The expected snapshot is `reservation.expectedLegs` (photon snapshot revision = counter + 1, a PHOTON
/// mint revision and never a surface revision), derived from the reservation that was actually consumed - never read after the readback, never copied from the receipt being judged.
/// No reservation = the probe is NOT called (`.reservationUnavailable`). A stale reservation (another mint, a replay, token/epoch/target drift) yields no receipt and no evidence. Only a pure
/// `revisionMoved` is retried: at most ONE retry, inside `withinDeadline`, and only if the re-taken reservation has the same token, photon epoch and targets and the identity/owner fence are
/// unchanged (otherwise `.captureStale`); a second stale = `.renderStateBusy`. No present stop, no pause, no mode change.
public enum ExportRenderObservationBridge {
    public enum Refusal: Error, Equatable {
        case captureNotVerified, captureEpochUnavailable, identityUnavailable, ownerFenceUnavailable, contractUnavailable
        case reservationUnavailable
        /// Look/owner/producer context changed between attempts (token, photon epoch, targets, identity or owner fence): typed capture stale, no retry.
        case captureStale(String)
        /// The renderer kept minting under the probe (retry budget or deadline spent).
        case renderStateBusy
        case probeRefused(String), probeUnavailable(String), probeTeardownPending
    }
    public struct Providers {
        /// The owner-fenced identity of the frame to probe (provider's own binding to the job); nil = unavailable.
        public var identity: () -> PhotonExportFrameIdentity?
        public var contract: () -> PhotonExportReadbackContract?
        public var owner: () -> ExportProbeFence?
        /// The renderer owner's freeze: the reservation of its next photon snapshot mint; nil = unavailable (fail-closed).
        public var reserve: () -> PhotonExportNextMintReservation?
        public var probe: (PhotonExportFrameIdentity, PhotonExportReadbackContract, _ runID: String, _ exportEpoch: Int64?, PhotonExportNextMintReservation) -> PhotonExportReadbackCore.ProbeOutcome
        /// True while the preflight's total deadline still has room for one more attempt.
        public var withinDeadline: () -> Bool
        public init(identity: @escaping () -> PhotonExportFrameIdentity?, contract: @escaping () -> PhotonExportReadbackContract?, owner: @escaping () -> ExportProbeFence?,
                    reserve: @escaping () -> PhotonExportNextMintReservation?,
                    probe: @escaping (PhotonExportFrameIdentity, PhotonExportReadbackContract, String, Int64?, PhotonExportNextMintReservation) -> PhotonExportReadbackCore.ProbeOutcome,
                    withinDeadline: @escaping () -> Bool = { true }) {
            self.identity = identity; self.contract = contract; self.owner = owner; self.reserve = reserve; self.probe = probe; self.withinDeadline = withinDeadline
        }
    }

    /// The observation together with the typed freeze expectation the consumer (`ExportExpectedLegsConsumer`) equates with the receipt's own legs: the consumed reservation's PHOTON mint
    /// counter BEFORE the mint (`snapshotLegs.revision`; the consumer adds exactly 1 with a checked add), the owner-fenced source frame identity (the SURFACE revision axis, never converted
    /// from or into the photon axis) and the epoch legs of the capture/owner/contract. Built from the reservation that was actually consumed, before the probe; never from the receipt.
    public static func makeWithExpectedLegs(capture: ExportLookCapture, providers p: Providers) -> Result<(observation: ExportRenderObservation, expectedLegs: ExportExpectedRenderLegs), Refusal> {
        guard capture.producerRunVerified, let accepted = capture.acceptedIdentity else { return .failure(.captureNotVerified) }
        guard let e0 = capture.exportEpoch else { return .failure(.captureEpochUnavailable) }
        guard let id = p.identity() else { return .failure(.identityUnavailable) }
        guard let owner = p.owner() else { return .failure(.ownerFenceUnavailable) }
        guard let contract = p.contract() else { return .failure(.contractUnavailable) }
        guard let first = p.reserve() else { return .failure(.reservationUnavailable) }
        var reservation = first
        var retried = false
        while true {
            switch p.probe(id, contract, capture.loadReceipt.runId, e0, reservation) {
            case .ok(let receipt):
                guard let expected = reservation.expectedLegs else { return .failure(.reservationUnavailable) }
                let frozen = ExportExpectedRenderLegs(
                    snapshotLegs: PhotonExportPhotonSnapshotLegs(epoch: reservation.photonEpoch, token: reservation.token, revision: reservation.photonRevisionBeforeMint),
                    frameIdentity: id,
                    legs: ExportRendererEpochLegs(runId: capture.loadReceipt.runId, session: accepted.session, opening: accepted.opening, path: accepted.path,
                                                  connectionEpoch: owner.connectionEpoch, lookPinSha256: capture.look.pinSha256,
                                                  raster: [contract.outputRaster.width, contract.outputRaster.height], rendererEpoch: e0))
                return .success((ExportRenderObservation(receipt: receipt, identity: accepted, lookPinSha256: capture.look.pinSha256,
                                                         expectedSnapshot: expected, owner: owner, sealProof: nil, expectedLegs: frozen), frozen))
            case .unavailable(.staleRenderSnapshot(let why)):
                guard why == .revisionMoved else { return .failure(.captureStale(String(describing: why))) }
                guard !retried, p.withinDeadline() else { return .failure(.renderStateBusy) }
                guard let again = p.reserve(), again.token == first.token, again.photonEpoch == first.photonEpoch,
                      again.sharpTarget == first.sharpTarget, again.grainTarget == first.grainTarget,
                      p.identity() == id, p.owner() == owner else { return .failure(.captureStale("context changed between attempts")) }
                reservation = again; retried = true
            case .refused(let r): return .failure(.probeRefused(String(describing: r)))
            case .unavailable(let u): return .failure(.probeUnavailable(String(describing: u)))
            case .teardownPending: return .failure(.probeTeardownPending)
            }
        }
    }
    /// The observation carries the frozen reservation as `expectedLegs` (the product path: derive judges it through ONE consumer per preflight run, a replay is refused).
    public static func make(capture: ExportLookCapture, providers p: Providers) -> Result<ExportRenderObservation, Refusal> {
        makeWithExpectedLegs(capture: capture, providers: p).map { $0.observation }
    }
    /// The closure shape `ExportAsSeenAction.renderReceiptSource` expects: nil on every refusal (the adapter's own answer for "no receipt"); the typed reason stays available through `make`.
    public static func source(_ p: Providers) -> (ExportLookCapture) -> ExportRenderObservation? {
        { capture in if case .success(let o) = make(capture: capture, providers: p) { return o } else { return nil } }
    }
}

/// E1 per-frame expected legs, built from the reservation the frame's own render consumed (`ExportReservedFrame.reservation`): photon snapshot legs = (token, photon epoch, the mint counter
/// BEFORE the mint; the consumer adds exactly 1 with a checked add), the owner-fenced frame identity (SURFACE axis, never converted from or into the photon axis) and the run/epoch legs.
/// One value per frame; hand each to a fresh-per-run `ExportExpectedLegsConsumer`, which is consume-once. It is a renderer-state equality witness only: no seal, no settlement, no framesBaked.
public enum ExportFrameExpectedLegs {
    public static func make(reservation: PhotonExportNextMintReservation, identity: PhotonExportFrameIdentity, legs: ExportRendererEpochLegs) -> ExportExpectedRenderLegs {
        ExportExpectedRenderLegs(snapshotLegs: PhotonExportPhotonSnapshotLegs(epoch: reservation.photonEpoch, token: reservation.token, revision: reservation.photonRevisionBeforeMint),
                                 frameIdentity: identity, legs: legs)
    }
}

/// Plain factories for the E1 per-frame channel (the composition root calls them; they construct nothing global and hold no state of their own).
public enum ExportE1FrameProducers {
    /// The E0 `Providers.contract` closure from the decoded mpv colour probe (`ExportDecodedSignal`: video-dec-params primaries/trc/colormatrix, ExportColourEvidence.swift:30), the ffprobe source
    /// `color_transfer` tag (Sources/gor/Stereo/Source.swift:779; it decides, mpv bt.1886 or absent is only consistency) and the owner's facts: HDR/EDR from the caller, overlay policy REQUIRED (no default),
    /// planned raster. nil = refused (unavailable to the bridge, fail-closed); `refusal` receives the typed refusal (transfer refusals use the one HUD wording) so the HUD/log can print it. A nil decoded signal
    /// qualifies nothing (matrix/primaries unresolved).
    public static func contract(decoded: @escaping () -> ExportDecodedSignal?, ffprobeTransfer: @escaping () -> String?,
                                hdrSignalPresent: @escaping () -> Bool, edrArm: @escaping () -> Bool,
                                overlayPolicy: PhotonExportReadbackContract.OverlayPolicy, outputRaster: PhotonExportRaster,
                                refusal: @escaping (PhotonExportReadbackContract.Refusal) -> Void = { _ in }) -> () -> PhotonExportReadbackContract? {
        {
            let d = decoded()
            switch PhotonExportMpvLabels.qualify(matrix: d?.matrix, primaries: d?.primaries, ffprobeTransfer: ffprobeTransfer(), mpvGamma: d?.transfer,
                                                 hdrSignalPresent: hdrSignalPresent(), edrArm: edrArm(), overlayPolicy: overlayPolicy, outputRaster: outputRaster) {
            case .success(let c): return c
            case .failure(let r): refusal(r); return nil
            }
        }
    }

    /// The E0 `Providers` factory: a plain function from the host's closures to `Providers`. Nothing is invented: `identity`, `contract`, `owner`, `probe` and `withinDeadline` are the CALLER's
    /// closures (the contract from `PhotonExportMpvLabels.qualify`, the owner fence from the producer/owner, the probe from the renderer-side E0 probe, which is not in the handle), and `reserve`
    /// is the renderer handle's own next-mint reservation (`handle.reserveNextMint`: the renderer owner's freeze, nil = unavailable, fail-closed). `withinDeadline` has NO default here: a caller
    /// that passes nothing does not compile, so no unbounded retry window can be reached by omission.
    public static func providers(handle: PhotonExportReadbackHandle,
                                 identity: @escaping () -> PhotonExportFrameIdentity?,
                                 contract: @escaping () -> PhotonExportReadbackContract?,
                                 owner: @escaping () -> ExportProbeFence?,
                                 probe: @escaping (PhotonExportFrameIdentity, PhotonExportReadbackContract, String, Int64?, PhotonExportNextMintReservation) -> PhotonExportReadbackCore.ProbeOutcome,
                                 withinDeadline: @escaping () -> Bool) -> ExportRenderObservationBridge.Providers {
        ExportRenderObservationBridge.Providers(identity: identity, contract: contract, owner: owner, reserve: ExportRendererReadbackAdapter.reserve(handle), probe: probe, withinDeadline: withinDeadline)
    }

    /// The reserve-and-acquire call of one E1 frame: the closure the frame channel runs AFTER the seal wait. The next-mint reservation is taken by the renderer OWNER, inside the handle:
    /// `handle.reserveNextMint` is `MetalRenderer.frozenPhotonNextMintReservation`, which feeds `PhotonPresenterProducer.reserveNextMint(photonEnabled:activationEpoch:epoch:)` with the renderer's
    /// OWN photonEnabled / activation epoch / epoch under its lock. Those three are renderer-owner state: the host never supplies, caches or compares them, and a host-supplied value would be a
    /// copy of the thing being checked. The returned `ExportReservedFrame.reservation` is the one the render consumed (the retry's, if the first went stale).
    public static func reservedAcquire(adapter: ExportRendererReadbackAdapter, handle: PhotonExportReadbackHandle,
                                       withinDeadline: @escaping () -> Bool) -> (PhotonExportFrameIdentity, ExportPreparedRun) throws -> ExportReservedFrame? {
        { identity, binding in
            try adapter.acquireReservedFrame(identity, under: binding, reserve: ExportRendererReadbackAdapter.reserve(handle), withinDeadline: withinDeadline)
        }
    }

    /// The run/epoch legs of the E1 frames from the prepared run, the owner's accepted-load state and the planned raster. nil = unknown (the frame is refused, no default):
    /// no export epoch on the prepared run, no owner state, the owner no longer reports the run's accepted load (session/opening/path), or the owner's receipt run is not this run's.
    /// `rendererEpoch` is the prepared run's own export epoch (caller-claimed until the owner ACK wiring lands); the connection epoch is the owner's, read by the caller on the owner queue.
    public static func epochLegs(binding b: ExportPreparedRun, owner: ExportProbeFence?, raster: PhotonExportRaster) -> ExportRendererEpochLegs? {
        guard let epoch = b.run.exportEpoch, let owner else { return nil }
        let id = b.run.identity
        guard owner.session == id.session, owner.opening == id.opening, owner.path == id.path, owner.receiptRunId == b.run.runId else { return nil }
        return ExportRendererEpochLegs(runId: b.run.runId, session: id.session, opening: id.opening, path: id.path, connectionEpoch: owner.connectionEpoch,
                                       lookPinSha256: b.run.lookPinSha256, raster: [raster.width, raster.height], rendererEpoch: epoch)
    }
    /// The closure shape for the frame channel: nil when the owner state is unreadable at that moment.
    public static func epochLegs(binding b: ExportPreparedRun, owner: @escaping () -> ExportProbeFence?, raster: PhotonExportRaster) -> () -> ExportRendererEpochLegs? {
        { epochLegs(binding: b, owner: owner(), raster: raster) }
    }
}

/// The host's `ledgerConfirms` producer: (ExportSealFrozenRequest) -> Bool, synchronous, short, for the worker thread (never the owner queue). true only if proven:
///  - HOST-SIDE equalities (not renderer proof; the renderer knows neither run nor epoch nor wire ordinal): the request's run id equals the prepared run's and `frozen.epoch` equals the prepared
///    run's export epoch (the rendererEpoch leg); a prepared run without an export epoch confirms nothing;
///  - RENDERER-SIDE (`handle.confirmPresented`, the renderer's own record table): this exact surface identity (all four fields; the surface revision is not the photon mint revision) has a present
///    command that completed OK there, with ONE recorded exact rational PTS equal to `frozen.ptsUs` (`ptsNum * 1_000_000 == ptsUs * ptsDen`). `originUs` is a separate host leg and is not used.
/// It does NOT bind the wire ordinal to the surface (host-side claim), is not scanout proof, not a seal, and never reads the seal receiver, ACKs, scripts or the host's frozen map. No closure passed in = false.
public enum ExportLedgerConfirms {
    public static func make(binding b: ExportPreparedRun, handle: PhotonExportReadbackHandle) -> (ExportSealFrozenRequest) -> Bool {
        { frozen in
            guard let epoch = b.run.exportEpoch, frozen.epoch == epoch, frozen.runId == b.run.runId else { return false }
            return handle.confirmPresented(frozen.identity, frozen.ptsUs)
        }
    }
}

extension ExportFrameWireChannel {
    /// The composition of one run's frame channel from its real parts: the seal query client supplies both the per-request freeze
    /// (freezeRequest) and the chain-seal re-query (requerySeal), so the re-query is bound to the map frozen inside the request's owner-queue
    /// transaction and never to a current snapshot. The client's own fail-closed defaults apply: until its dirty read and ledger confirmation are
    /// supplied, requery yields no proof. The per-frame reserved acquire and the run's epoch legs are optional and default to none (the
    /// channel then has no renderer-state witness). This composes; it asserts nothing. The caller must call `sealClient.invalidate(_:)` on
    /// cancel, unload, reconnect, load change and epoch change.
    public static func composed(emitter: ExportWireEmitter, settlement: ExportFrameSettlement, sealClient: ExportSealQueryClient,
                                requiredScripts: Set<String> = ExportBarrierScripts.required, settleTimeout: TimeInterval = 10, sealTimeout: TimeInterval = 2,
                                wireTiming: @escaping (_ entry: ExportPtsPlanEntry) -> (ptsUs: Int64, originUs: Int64)?,
                                reservedAcquire: ExportFrameWireChannel.ReservedAcquire? = nil,
                                epochLegs: ExportFrameWireChannel.EpochLegs? = nil) -> ExportFrameWireChannel {
        ExportFrameWireChannel(emitter: emitter, settlement: settlement, requiredScripts: requiredScripts, settleTimeout: settleTimeout, sealTimeout: sealTimeout,
                               wireTiming: wireTiming,
                               requerySeal: { epoch, ordinal in sealClient.requery(epoch: epoch, wireOrdinal: ordinal) },
                               freezeRequest: { frozen in sealClient.noteFrozen(frozen) },
                               reservedAcquire: reservedAcquire, epochLegs: epochLegs)
    }
}
