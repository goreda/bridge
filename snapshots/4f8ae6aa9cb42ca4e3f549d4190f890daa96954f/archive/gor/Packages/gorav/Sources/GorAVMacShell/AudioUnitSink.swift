#if canImport(AppKit) && canImport(CoreAudio)
import AudioUnit
import CoreAudio
import AudioToolbox
import Foundation
import QuartzCore
import GorAVPlaybackCore
import GorAVAudioClockSwift
import GorAVSeekComposition

/// AudioUnit default-output sink, render-callback pull model - the shape of
/// mpv 0.41.0 audio/out/ao_audiounit.m. Probe scope: s16le stereo 44.1kHz.
///
/// LANE-0 / architect 80b constraints A-D (2026-10-25), REVISE of v5:
///  A. CALLBACK ADMISSION CAS: every registration carries an AdmissionCell
///     (bit63 RETIRED + reader count, one lock-free C cell). A callback
///     ENTERS only while not retired; after retire it touches NO payload
///     (no sink, no ring, no event ring, no ledger) and renders silence.
///     The owner retires FIRST, then drains admitted readers to ZERO
///     before any reset/reuse/dispose. LOCAL lifetime fence; NO provider
///     quiescence claim anywhere.
///  B. SINGLE-GENERATION ring use: the shared rings are reused ONLY after
///     retire + readers==0 + producer join - in that order. A stale
///     (post-retire) callback writes NOTHING, so the event ring never has
///     an old-generation producer interleaved with a new one.
///  C. TOMBSTONE WITHOUT STRONG SINK: the callback context holds the sink
///     WEAKLY; post-retire callbacks need no sink (admission fails first),
///     so a retired registration retains only its small context, never
///     the sink/rings/ledger. A PROCESS-GLOBAL registry bounds retained
///     terminal payloads (count + byte estimate); a NEW start is a typed
///     refusal once the ceiling is reached (GORAV_MAX_RETAINED_TERMINAL -
///     the VALUE is a lane-0 review item, no approved numeric cap claim).
///  D. ANY error/timeout in teardown: NO reset, NO reuse, NO new start
///     (lifecycle FAILED is terminal); the partial handle is retained and
///     registered, typed failed.
/// v5 bug fixes folded in:
///  - reader-drain timeout is TERMINAL (was: logged, then reset+finishStop
///    anyway);
///  - start-failure teardown: a stop error skips dispose (retain), a drain
///    timeout sets clean=false (was: counted but ignored);
///  - pushes are refused after EITHER witness (.joined OR .absent), and
///    the admission check + ring write hold stateLock TOGETHER (was:
///    unlocked between check and write - raced join/stop/reset);
///  - a stop with a PENDING producer retires+fences the unit (silent) and
///    is an explicitly BOUNDED RETAINED FAULT, never a "completed
///    teardown".
public final class AudioUnitSink: AudioSink, @unchecked Sendable {
    /// Per-registration callback context (tombstone, constraint C): the
    /// sink reference is WEAK - a retired context retains nothing but its
    /// admission cell and generation. Post-retire callbacks never
    /// dereference the sink (admission fails first).
    private final class CallbackContext {
        /// M4: mutable ONLY inside the RT-quiesced window of resetRingForSeek
        /// (AudioOutputUnitStop returned -> before AudioOutputUnitStart): no
        /// render callback runs there, so no torn read is possible. Identity,
        /// admission cell and rings stay the SAME objects - no registry
        /// rebind, no new reservation, retirement semantics untouched.
        private(set) var generation: UInt64
        weak var sink: AudioUnitSink?
        let admission: AdmissionCell // C-owned packed cell; failable init
        /// Verdict S4 rev3: the RT path reaches the LIVE rings STRONGLY
        /// through the context - a later generation's storage replacement
        /// can never race an admitted reader, and no RT access
        /// force-unwraps sink storage.
        /// Verdict S5 rev5 DETACHABLE PAYLOAD: strong while ADMITTED;
        /// detached ONLY on the clean stop path (retire + reader drain +
        /// producer join + dispose + receipt), so a registry TOMBSTONE
        /// retains the minimal root (admission cell + generation), never
        /// multi-MB PCM/event buffers forever. Fault paths NEVER detach -
        /// the full payload stays retained for post-mortem.
        private(set) var ring: SPSCPCMRing?
        private(set) var events: SPSCEventRing?
        init?(generation: UInt64, sink: AudioUnitSink, ring: SPSCPCMRing, events: SPSCEventRing) {
            guard let a = AdmissionCell() else { return nil }
            self.admission = a
            self.generation = generation; self.sink = sink
            self.ring = ring; self.events = events
        }
        func updateGenerationForSeek(_ g: UInt64) { generation = g }
        /// Clean-path payload drop. A late callback after dispose renders
        /// bounded-zero silence through the nil-safe render path.
        func detach() { ring = nil; events = nil }
    }

    /// S2: the REAL strong fault-payload owner. On a terminal fault the
    /// registry registration is REBOUND from the weak-sink callback
    /// context to this graph: the context stays strongly held (any late
    /// provider refCon dereference remains valid), and the sink, its
    /// rings, the ledger and the deliberately-UNDISPOSED provider handle
    /// all stay strongly owned and addressable for post-mortem. Bounded
    /// by the registry's fault cap; reclaim stays proof-gated.
    /// Peer finding 3/6: the callback context root stays IMMUTABLY in
    /// the registry entry (never replaceable, so no rebind can free a
    /// late refCon); THIS payload is the separate typed attachment with
    /// the real owner graph. The undisposed unit handle is address
    /// bookkeeping, NOT a provider-lifetime proof - native disposal
    /// stays a native obligation (no ARC edge claim).
    private final class AudioFaultPayload: FaultPayloadGraph {
        /// Typed real owner (verdict S1 rev2 protocol requirement).
        var owner: AnyObject { sink }
        let sink: AudioUnitSink          // strong: sink + its rings + fence
        let ledger: TimingLedger?        // strong graph edge
        let unit: AudioUnit?             // undisposed provider handle, addressable
        let generation: UInt64
        let stopStatus: Int32?, uninitStatus: Int32?, disposeStatus: Int32?
        let readersDrained: Bool, producerWitnessed: Bool
        let cause: String
        init(sink: AudioUnitSink, ledger: TimingLedger?,
             unit: AudioUnit?, generation: UInt64, stopStatus: Int32?, uninitStatus: Int32?,
             disposeStatus: Int32?, readersDrained: Bool, producerWitnessed: Bool, cause: String) {
            self.sink = sink; self.ledger = ledger; self.unit = unit
            self.generation = generation; self.stopStatus = stopStatus
            self.uninitStatus = uninitStatus; self.disposeStatus = disposeStatus
            self.readersDrained = readersDrained; self.producerWitnessed = producerWitnessed
            self.cause = cause
        }
        var strongEdgeCount: Int { 1 + (ledger != nil ? 1 : 0) + (unit != nil ? 1 : 0) }
        var payloadDescription: String {
            "AudioFaultPayload(gen=\(generation) cause=\(cause) stop=\(stopStatus) uninit=\(uninitStatus) dispose=\(disposeStatus) drained=\(readersDrained) witnessed=\(producerWitnessed) unit=\(unit != nil ? "retained" : "none"))"
        }
    }

    /// Rebind the fault registration to the real strong graph (S2),
    /// then classify FAULT. One helper so every fault site upgrades.
    /// Finding 5: retention is TYPED and CHECKED. Returns false when
    /// the graph could not attach or the transition was refused - the
    /// caller records that as its own terminal ledger event, never an
    /// assumed retainedRegistration.
    /// Verdict S2: NOT discardable - every caller must consume the
    /// typed retention result (an unretained "retainedRegistration"
    /// claim was the actual defect).
    private func retainFaultGraph(token rid: RegistrationToken?, unit: AudioUnit?,
                                  generation: UInt64, stopStatus: Int32?, uninitStatus: Int32?,
                                  disposeStatus: Int32?, readersDrained: Bool,
                                  producerWitnessed: Bool, cause: String) -> Bool {
        guard let rid else { return false }
        let graph = AudioFaultPayload(sink: self, ledger: ledger, unit: unit,
            generation: generation, stopStatus: stopStatus, uninitStatus: uninitStatus,
            disposeStatus: disposeStatus, readersDrained: readersDrained,
            producerWitnessed: producerWitnessed, cause: cause)
        let attached = registry.attachFaultGraph(rid, graph)
        let moved = registry.reclassify(rid, to: .fault)
        let ok = attached && moved && registry.retentionState(of: rid).retained
        if !ok {
            ledger?.append(session: ledgerSession, generation: generation, segment: .teardown,
                           subsystem: .audio, kind: .decodeError,
                           note: "RETENTION-FAILED attached=\(attached) moved=\(moved) cause=\(cause)")
        }
        return ok
    }
    /// Producer witness state (generation-bound, stateLock only):
    /// .pending = a producer exists, not yet joined; .joined = the owned
    /// producer task was AWAITED (runMuxed awaits the pump task, then
    /// calls markProducerJoined); .absent = caller declared NO producer.
    private enum ProducerState: Equatable {
        case idle
        case pending(UInt64)
        case joined(UInt64)
        case absent(UInt64)
    }
    /// PROCESS-OWNED lifetime registry (architect full verdict S1): the
    /// CORE PlaybackRegistry owns atomic reservation, STRONG retention and
    /// typed exhaustion. The old static counters + 8-payload/64-MiB byte
    /// ceiling and the "2MiB+4096" estimates are RETIRED - unapproved and
    /// not provider/unit/ledger/context-derived (verdict S1e).
    private let registry = PlaybackRegistry.shared
    /// Registration id of the LIVE session's registry reservation
    /// (stateLock). The context is STRONGLY retained by the process from
    /// start() until a PROVEN provider-release barrier exists - none
    /// exists today, so retention is the honest state.
    private var registrationToken: RegistrationToken?
    /// r3-rev1 S4: generation-bound outcome cache (peer findings 7-9).
    private let outcomeCache = StopOutcomeCache()
    public static var retainedTerminalCount: Int {
        let st = PlaybackRegistry.shared.state; return st.faults + st.tombstones
    }
    /// Retained OBJECTS (honest metric; byte estimates were ungrounded).
    public static var retainedObjectCount: Int { PlaybackRegistry.shared.state.retainedObjects }

    private let stateLock = NSLock()
    // Provider calls are serialized against stop/seek/start/volume. RT never
    // takes this lock. Existing default-output startup remains unchanged.
    private let deviceOperationLock = NSRecursiveLock()
    private var explicitDeviceTransaction: AudioOutputDeviceTransaction?
    private var outputDeviceWatch: CoreAudioOutputWatch?
    private var retainedDeviceUnits: [AudioUnit] = []
    private var deviceTerminal = false
    private var lastDeviceResult: AudioDeviceSelectionResult?
    private var unit: AudioUnit?
    /// Rings are created in start() AFTER the registry reserve (verdict
    /// S1: allocation-before-reserve was the r2 leak class). Nil before
    /// the first start; the RT callback is installed only after.
    private var ringStorage: SPSCPCMRing?
    private var rtEventsStorage: SPSCEventRing?
    // MARK: M1 audio-master pacing state (GP-47 / 164h)
    /// The pacing policy + adapter, created by attachPacing (pre-start).
    /// Nil = no audio-master capability attached; all pacing reads are
    /// typed-absent, never a trap.
    public private(set) var pacingPolicy: AudioPacingPolicy?
    public private(set) var pacingClock: AudioMasterPacingClock?
    private var pacingHostClock: (@Sendable () -> Double)?
    /// Shared admission core (GorAVAudioClockSwift; Linux-tested). The
    /// RT-read pause cell (1 = quiesced) is written ONLY under stateLock
    /// (pauseAudio/resumeAudio) and read lock-free on the render thread.
    private let admission = AudioAdmissionState()
    private var pausedFlag: AtomicU64? { admission.pausedCell }
    /// Intentional-pause silence rendered while quiesced (own counter -
    /// NEVER underrun/overrun). Folded into pacing receipts on resume.
    private let pausedSilenceRT: AtomicU64? = AtomicU64(0)
    /// Producer pushes DROPPED while quiesced (bytes; own counter -
    /// NEVER overrun/underrun). The composition gates the producer via
    /// audioPaused; this fail-safe covers the observation race window.
    private let pausedPushDropsStorage: AtomicU64? = AtomicU64(0)
    /// native87 B-gate: real render-callback invocations (RT counter). Every
    /// callback reaching the buffer-write stage counts - pause-silence,
    /// ring content and fenced silence included; a callback-COUNT freeze is
    /// NOT this product's pause contract (the silence counter is).
    private let callbacksRT: AtomicU64? = AtomicU64(0)
    /// native87 B-gate: frames of real ring content delivered to the unit
    /// (RT counter; underrun shortfall and every silence form excluded).
    private let nonSilenceRT: AtomicU64? = AtomicU64(0)
    /// C3 boost cell: requested output gain as Float bitPattern, 1.0 =
    /// unity. Written ONLY under stateLock AFTER a successful HAL set in
    /// setVolume (a refused HAL call publishes nothing); read lock-free on
    /// the render path. Missing storage refuses above-unity requests only;
    /// normal HAL attenuation remains available. One fixed sink-lifetime
    /// allocation, no RT allocation or growth. HAL and gain-cell updates
    /// are not one atomic operation at the render boundary; cross-unity
    /// transitions are not guaranteed glitch-free.
    private let outputBoostRT: AtomicU64? = AtomicU64(UInt64(Float(1).bitPattern))
    // Verdict S5 rev6 item 9: NO force-unwrap accessors - every reader
    // takes a typed-nil path (unstarted / cleanly retired), never a trap.
    private let lifecycle = SessionLifecycle()
    private let fence = GenerationFence()
    private var producerState: ProducerState = .idle
    public private(set) var producerWitnessViolations = 0
    /// Bytes pushed AFTER a witness (.joined OR .absent): typed rejects.
    public private(set) var witnessRejectedPushBytes = 0
    public private(set) var pushedWhileStopped = 0
    /// Retired contexts are PROCESS-OWNED (PlaybackRegistry), never
    /// instance-held: an instance array would free them at the sink's
    /// last release while the provider may still hold refCon (S1c UAF).
    public var retainedContextCount: Int { PlaybackRegistry.shared.state.retainedObjects }

    private var _ledger: TimingLedger?
    public var ledger: TimingLedger? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _ledger }
        set { stateLock.lock(); _ledger = newValue; stateLock.unlock() }
    }
    private var _ledgerSession: UInt64 = 0
    public var ledgerSession: UInt64 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _ledgerSession }
        set { stateLock.lock(); _ledgerSession = newValue; stateLock.unlock() }
    }
    private var registration: CallbackContext?
    /// RT-thread-only underrun transition state: touched ONLY by render()
    /// on the render thread; deliberately not locked (single thread).
    private var starving = false
    private var overflowFoldedGeneration: UInt64 = 0
    private var _stopCallCount = 0
    private var _disposeCount = 0
    private var _failedStopCount = 0
    private var _failedDisposeCount = 0
    private var _readerDrainTimeouts = 0
    public var stopCallCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return _stopCallCount }
    public var disposeCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return _disposeCount }
    public var failedStopCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return _failedStopCount }
    public var failedDisposeCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return _failedDisposeCount }
    public var joinTimeouts: Int { stateLock.lock(); defer { stateLock.unlock() }; return _readerDrainTimeouts }
    private var _stoppedReceipt: PCMRingReceipt?
    public var stoppedReceipt: PCMRingReceipt? { stateLock.lock(); defer { stateLock.unlock() }; return _stoppedReceipt }
    public var currentGeneration: UInt64 {
        switch lifecycle.current {
        case .active(let g), .starting(let g), .stopping(let g), .failed(let g): return g
        case .idle: return 0
        }
    }
    public var lifecycleState: SessionLifecycle.State { lifecycle.current }
    public var staleFencedCount: Int { fence.fencedCount }
    /// Failable (peer review item): ring construction needs C-owned atomic
    /// cells; a refusal is a TYPED nil, never a fatalError.
    public init?() {
        // Ring/event construction moved to start() (post-reserve); its
        // failure is a typed throw there, not a nil here.
    }
    private var evidence: (maxPushFrames: UInt64, maxAvailAfterPush: UInt64, pushCount: UInt64,
                           consumedFrames: UInt64, droppedFrames: UInt64, underrunFrames: UInt64) {
        // Verdict S5 rev6 item 10: ONE COHERENT SNAPSHOT - receipt,
        // storage and counters are read under the ONE stateLock hold
        // (the stoppedReceipt/public-getter-then-unlocked-storage shape
        // was an incoherent split read). _stoppedReceipt is an immutable
        // value-type receipt, so the locked read is itself the snapshot.
        // Verdict S1 rev2: an UNSTARTED sink has no rings (allocation
        // moved post-reserve) - typed-zero, never a force-unwrap trap.
        stateLock.lock(); defer { stateLock.unlock() }
        if let r = _stoppedReceipt {
            return (r.maxPushFrames, r.maxAvailAfterPushFrames, r.pushCount,
                    r.consumedFrames, r.droppedFrames, r.underrunFrames)
        }
        guard let ring = ringStorage else { return (0, 0, 0, 0, 0, 0) }
        return (ring.maxPushFrames.load(), ring.maxAvailAfterPushFrames.load(), ring.pushCount.load(),
                ring.consumedFrames.load(), ring.droppedFrames.load(), ring.underrunFrames.load())
    }
    public var maxChunkBytes: Int { Int(Swift.min(evidence.maxPushFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame }
    public var maxQueueBytes: Int { Int(Swift.min(evidence.maxAvailAfterPush, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame }
    public var pushRecords: Int { Int(Swift.min(evidence.pushCount, UInt64(Int.max))) }
    /// Verdict S5 rev6 item 10: SERIAL drain owner ENFORCED in code
    /// (was a documented convention): a concurrent drain is a typed
    /// refusal, counted - never a double-drain of the SPSC ring.
    private let drainOwner: AtomicU64? = AtomicU64(0)
    public private(set) var drainRefusals = 0   // stateLock
    public func drainRTTransitions(segment: LedgerSegment) {
        guard drainOwner?.compareExchange(expected: 0, desired: 1) == true else {
            stateLock.lock(); drainRefusals += 1; stateLock.unlock()
            return   // typed refusal: a drain is already in flight
        }
        defer { _ = drainOwner?.compareExchange(expected: 1, desired: 0) }
        // Verdict S4 rev3: an unstarted / early-alloc-failed sink has NO
        // event ring - a typed no-op, never a force-unwrap trap.
        // Verdict S5 rev5: ONE COHERENT SNAPSHOT - the ring, the session
        // and the generation are captured under ONE lock, and the
        // overflow check reads the SAME ring that was drained (never a
        // re-read force-unwrap of current storage): a storage swap
        // between drain and check can never attribute one generation's
        // drops to another. SINGLE-CONSUMER contract: callers serialize
        // drains (the shell drains on the MainActor between lifecycle
        // steps); the ring itself is SPSC with the RT thread as producer.
        // Verdict S5 rev6 item 10: the ring, session AND generation are
        // captured under the ONE lock (lifecycle.current takes only its
        // own internal lock; no path takes stateLock while holding it,
        // so this acquisition order cannot deadlock).
        stateLock.lock()
        let ring0 = rtEventsStorage
        let ses = _ledgerSession
        let g = currentGeneration
        stateLock.unlock()
        guard let ring0 else { return }
        guard let ledger else { ring0.drain(); return }
        let evs = ring0.drain()
        if !evs.isEmpty { ledger.fold(rt: evs, session: ses, segment: segment) }
        stateLock.lock()
        if ring0.droppedAnything.load() != 0 && overflowFoldedGeneration != g {
            overflowFoldedGeneration = g
            stateLock.unlock()
            ledger.foldRTOverflow()
        } else {
            stateLock.unlock()
        }
    }

    /// Bounded-zero silence for refused/orphaned callbacks (S1b): the
    /// single interleaved stereo buffer this unit carries, fully zeroed.
    static func zeroBuffers(_ data: UnsafeMutablePointer<AudioBufferList>?) {
        guard let data = data else { return }
        let b = data.pointee.mBuffers
        if let p = b.mData, b.mDataByteSize > 0 { memset(p, 0, Int(b.mDataByteSize)) }
    }

    private func goravError(_ code: Int, _ status: OSStatus, _ what: String) -> NSError {
        NSError(domain: "gorav.audio", code: code,
                userInfo: [NSLocalizedDescriptionKey: "\(what) failed OSStatus=\(status)"])
    }

    public func start() throws {
        deviceOperationLock.lock(); defer { deviceOperationLock.unlock() }
        // S1d/r3: ATOMIC RESERVATION (one-shot capability token) before
        // any allocation/start. Typed exhaustion, never a trap, never
        // unbounded growth. Every early-error path below ROLLS BACK the
        // token - an abandoned reservation is a leak (r2 defect).
        let token: PlaybackRegistry.Reservation
        switch registry.reserve(.active) {
        case .failure(let e):
            throw goravError(12, 0, "start refused: process registry exhausted typed (active=\(e.active) faults=\(e.faults) tombstones=\(e.tombstones))")
        case .success(let t): token = t
        }
        // Verdict S4 rev2: the outcome cache binds to the generation
        // ATOMICALLY with its birth (inside the lifecycle lock) - a
        // stop racing this window can never mark/clear the wrong
        // cache generation.
        guard let g = lifecycle.beginStart(andThen: { [weak self] gg in self?.outcomeCache.noteStart(generation: gg) }) else {
            registry.rollback(token)
            let why: String
            if case .failed = lifecycle.current { why = "session FAILED (payload retained); instance is terminal" }
            else { why = "session already starting/active/stopping" }
            throw goravError(10, 0, "start refused: " + why)
        }
        // Verdict S1: ring/event allocation AFTER the reservation (never
        // before). Failure rolls the reservation back typed.
        guard let newRing = SPSCPCMRing(capacityFrames: 1 << 18) else {
            registry.rollback(token)
            publishAbortedStart(generation: g)
            lifecycle.abortStart(g); throw goravError(14, 0, "SPSCPCMRing: C atomic cells refused")
        }
        guard let newEvents = SPSCEventRing(capacity: 512, clock: { CACurrentMediaTime() }) else {
            registry.rollback(token)
            publishAbortedStart(generation: g)
            lifecycle.abortStart(g); throw goravError(15, 0, "SPSCEventRing: C atomic cells refused")
        }
        self.ringStorage = newRing; self.rtEventsStorage = newEvents
        guard let ctx = CallbackContext(generation: g, sink: self, ring: newRing, events: newEvents) else {
            registry.rollback(token)
            publishAbortedStart(generation: g)
            lifecycle.abortStart(g); throw goravError(11, 0, "CallbackContext: C atomic cell refused")
        }
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_DefaultOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            registry.rollback(token)
            publishAbortedStart(generation: g)
            lifecycle.abortStart(g); throw goravError(1, 0, "AudioComponentFindNext")
        }
        var u: AudioUnit?
        let stNew = AudioComponentInstanceNew(comp, &u)
        guard stNew == noErr, let unit = u else {
            registry.rollback(token)
            publishAbortedStart(generation: g)
            lifecycle.abortStart(g); throw goravError(2, stNew, "AudioComponentInstanceNew")
        }
        // S1c/r3: COMMIT the token - the reserved slot binds to the
        // STRONGLY process-retained context. A nil return (reused token)
        // is a typed refusal, never a trap.
        guard let rid = registry.register(root: ctx, token: token) else {
            // Finding 4 + verdict S1: a refusal AFTER InstanceNew must
            // not leak the unit - dispose before throwing, and the
            // dispose result is RECORDED (a failed dispose is a
            // live-unit leak: counted + ledgered, never discarded).
            let stD = AudioComponentInstanceDispose(unit)
            if stD != noErr { stateLock.lock(); _failedDisposeCount += 1; stateLock.unlock() }
            ledger?.append(session: ledgerSession, generation: g, segment: .open,
                           subsystem: .audio, kind: .decodeError,
                           note: "registerRefusedPostInstanceNew dispose=\(stD)")
            publishAbortedStart(generation: g)
            lifecycle.abortStart(g); throw goravError(13, 0, "registry.register: token refused")
        }
        stateLock.lock()
        self.unit = unit
        registration = ctx
        registrationToken = rid
        producerState = .pending(g)
        starving = false
        _stoppedReceipt = nil
        stateLock.unlock()
        // Checked teardown (constraints A/D): retire admission FIRST (new
        // callbacks go silent touching nothing), then stop, uninit, drain
        // readers, and ONLY then dispose. A stop/uninit error or a drain
        // timeout SKIPS dispose (retain + register + TERMINAL); dispose is
        // attempted only when every earlier step succeeded.
        /// Verdict S4: returns the ACTUAL step statuses (nil = the step
        /// was not attempted - explicit unknown, never a -1000
        /// fabrication) alongside the clean flag.
        func teardown(unit: AudioUnit, ctx: CallbackContext, started: Bool, initialized: Bool)
            -> (clean: Bool, stopStatus: Int32?, uninitStatus: Int32?, disposeStatus: Int32?, readersDrained: Bool, retainedOk: Bool?) {
            ctx.admission.retire()
            var clean = true
            var stT: Int32? = nil, stU: Int32? = nil, stD: Int32? = nil
            var retainedOk: Bool? = nil
            if started { let st = AudioOutputUnitStop(unit); stT = st; if st != noErr { clean = false } }
            if initialized { let st = AudioUnitUninitialize(unit); stU = st; if st != noErr { clean = false } }
            // Drain admitted readers (bounded). Timeout = NOT clean.
            // Monotonic deadline (verdict S2: a usleep COUNT is not a
            // clock). 50ms bounded reader drain on CACurrentMediaTime.
            let drainDeadline = CACurrentMediaTime() + 0.050
            while ctx.admission.readers != 0 && CACurrentMediaTime() < drainDeadline {
                usleep(500)
            }
            let drained = ctx.admission.readers == 0
            if !drained {
                stateLock.lock(); _readerDrainTimeouts += 1; stateLock.unlock()
                clean = false
            }
            stateLock.lock()
            let rid = registrationToken
            registration = nil
            stateLock.unlock()
            if clean {
                // r4 (setVolume lifetime): the dispose is INSIDE stateLock so
                // a concurrent C3 setVolume (which holds the lock across its
                /// HAL call) is mutually exclusive with use-after-free. The
                // lock is never taken on the RT render path; teardown is a
                // non-RT caller. Counter updates merge into the same section.
                stateLock.lock()
                stD = AudioComponentInstanceDispose(unit)
                if stD == noErr {
                    _disposeCount += 1; self.unit = nil
                } else {
                    _failedDisposeCount += 1
                    clean = false
                }
                stateLock.unlock()
            }
            // r3: classify AFTER the dispose result is known - a failed
            // dispose is a FAULT, never a premature tombstone (r2 defect:
            // the classification ran before dispose). S2: the fault
            // registration is first REBOUND to the real strong graph
            // (ctx+sink+ledger+undisposed unit), not weak-sink context.
            if let rid {
                if clean {
                    _ = registry.reclassify(rid, to: .tombstone)
                    // Verdict S5 rev6 (items 8/9): START-OWNED clean
                    // teardowns (failed start / stop-raced start) retire
                    // EXACTLY like the clean stop path: the immutable
                    // ring receipt is captured BEFORE detach, the live
                    // storage refs are CLEARED (no stale residual to any
                    // accessor), and the payload is DETACHED so the
                    // registry tombstone retains only the minimal root -
                    // never multi-MB PCM/event buffers held forever.
                    stateLock.lock()
                    if let receiptRing = ctx.ring {
                        _stoppedReceipt = receiptRing.snapshotReceipt(generation: ctx.generation)
                    }
                    ringStorage = nil
                    rtEventsStorage = nil
                    stateLock.unlock()
                    ctx.detach()
                } else {
                    let ok = retainFaultGraph(token: rid, unit: unit, generation: ctx.generation,
                        stopStatus: stT, uninitStatus: stU, disposeStatus: stD,
                        readersDrained: drained, producerWitnessed: false,
                        cause: "startTeardownFailed")
                    retainedOk = ok
                    if !ok {
                        stateLock.lock(); _failedStopCount += 1; stateLock.unlock()
                    }
                }
            }
            return (clean, stT, stU, stD, drained, retainedOk)
        }
        func fail(_ code: Int, _ status: OSStatus, _ what: String,
                  started: Bool = false, initialized: Bool = false) -> NSError {
            let td = teardown(unit: unit, ctx: ctx, started: started, initialized: initialized)
            // Findings 8/9 + verdict S4: the START-OWNED teardown
            // publishes its generation-bound terminal outcome BEFORE the
            // lifecycle transition, with the ACTUAL teardown statuses
            // (nil = not attempted), never fabricated sentinels.
            // Verdict S4 rev2: the retained-registration evidence names
            // the token ONLY when the teardown's retention actually
            // succeeded - never a bare id on a failed retention.
            let ev = AudioStopEvidence(generation: g, stopStatus: td.stopStatus,
                uninitStatus: td.uninitStatus, disposeStatus: td.disposeStatus,
                readersDrained: td.readersDrained, producerWitnessed: false,
                drainResidual: nil, retainedRegistration: td.retainedOk == true ? registrationToken?.id : nil)
            outcomeCache.publish(generation: g,
                outcome: td.clean ? .complete(ev) : .failed(ev))
            if td.clean { lifecycle.abortStart(g) } else { lifecycle.failStart(g) }
            return goravError(code, status, what)
        }
        var fmt = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
                                              mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                              mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                              mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        let stFmt = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard stFmt == noErr else { throw fail(3, stFmt, "SetStreamFormat") }
        let ctxPtr = Unmanaged.passUnretained(ctx).toOpaque()
        var cb = AURenderCallbackStruct(inputProc: { refCon, _, _, _, frames, data -> OSStatus in
            // Constraint A: admission BEFORE any payload touch. A retired
            // registration's callback renders silence and dereferences
            // NOTHING (no sink, ring, event ring, or ledger).
            let c = Unmanaged<CallbackContext>.fromOpaque(refCon).takeUnretainedValue()
            // S1b: a REFUSED admission (retired) renders BOUNDED-ZERO
            // silence with a VALID noErr return - never an error status
            // with unzeroed output, and NO event post (no old ring).
            guard c.admission.enter() else {
                AudioUnitSink.zeroBuffers(data); return noErr
            }
            // S1a: EVERY admitted path is balanced - the exit is deferred
            // AT ADMISSION, not only on the render path (the old shape
            // leaked the reader when the weak sink was nil).
            defer { c.admission.exit() }
            guard let sink = c.sink else {
                AudioUnitSink.zeroBuffers(data); return noErr
            }
            return sink.render(frames: frames, data: data, generation: c.generation, ctx: c)
        }, inputProcRefCon: ctxPtr)
        let stCb = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb,
                                        UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard stCb == noErr else { throw fail(4, stCb, "SetRenderCallback") }
        let stInit = AudioUnitInitialize(unit)
        guard stInit == noErr else { throw fail(5, stInit, "AudioUnitInitialize") }
        fence.setActive(g)
        ledger?.append(session: ledgerSession, generation: g, segment: .open,
                       subsystem: .audio, kind: .audioStartAttempt)
        let stStart = AudioOutputUnitStart(unit)
        guard stStart == noErr else { throw fail(6, stStart, "AudioOutputUnitStart", started: true, initialized: true) }
        ledger?.append(session: ledgerSession, generation: g, segment: .open,
                       subsystem: .audio, kind: .audioStartAccepted)
        if !lifecycle.commitStart(g) {
            // Verdict S4: the stop-raced START owns this teardown - it
            // PUBLISHES its outcome before the lifecycle transition
            // (previously unpublished: pending then noop).
            let td = teardown(unit: unit, ctx: ctx, started: true, initialized: true)
            let ev = AudioStopEvidence(generation: g, stopStatus: td.stopStatus,
                uninitStatus: td.uninitStatus, disposeStatus: td.disposeStatus,
                readersDrained: td.readersDrained, producerWitnessed: false,
                drainResidual: nil, retainedRegistration: td.retainedOk == true ? registrationToken?.id : nil)
            outcomeCache.publish(generation: g, outcome: td.clean ? .complete(ev) : .failed(ev))
            if td.clean {
                lifecycle.abortStart(g)
            } else {
                stateLock.lock(); _failedStopCount += 1; stateLock.unlock()
                lifecycle.failStart(g)
            }
            return
        }
        // M1: the first clock generation anchors at the proven zero
        // position of a freshly started render path (8.2: consumed=0).
        // 20:22 coherence: commitStart has PUBLISHED .active, so this
        // tail re-verifies the SAME generation is still active under
        // stateLock before clearing cells and anchoring. beginStop
        // itself is NOT stateLock-serialized (the lifecycle has its own
        // lock): if beginStop already flipped the state, this tail is a
        // no-op; if beginStop races AFTER this check, the anchor applies
        // first and stop's LATER master fence (sessionStop, under the
        // same stateLock) wins. The guarantee is anchor-then-fence
        // ordering, never fence-then-anchor on this session. A new
        // session never inherits an orphaned quiesce from a torn-down
        // session (20:40): the RT cells are cleared here and the policy
        // clears its own pause state in sessionStart. A pause arriving
        // between publication and this anchor is REFUSED (policy.pause
        // requires a live master), never silently dropped.
        stateLock.lock()
        if case .active(let gg) = lifecycle.current, gg == g {
            pausedFlag?.store(0)
            pausedSilenceRT?.store(0)
            pausedPushDropsStorage?.store(0)
            callbacksRT?.store(0)
            nonSilenceRT?.store(0)
            if let p = pacingPolicy { _ = p.sessionStart(consumedFrames: 0, atHost: hostSeconds()) }
        }
        stateLock.unlock()
    }

    // MARK: - M1 audio-master pacing (GP-47 / 164h)

    /// Probe-scope PCM rate (file header: s16le stereo 44.1kHz).
    public static let pcmSampleRate: UInt32 = 44100

    private func hostSeconds() -> Double { pacingHostClock?() ?? CACurrentMediaTime() }

    /// Attach the session's SHARED wall clock reading (the same epoch the
    /// TimingLedger and the video pump use - ShellClock.rawWallSeconds())
    /// and create the pacing policy + adapter. Call BEFORE start(); typed
    /// false when already attached or the arguments are invalid. The
    /// composition (J3) then injects pacingClock where the wall clock
    /// goes today (or attaches it to ShellClock.attachAudioMaster).
    @discardableResult
    public func attachPacing(hostClock: @escaping @Sendable () -> Double,
                             consistencyTolerance: Double = 0.002) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard pacingPolicy == nil else { return false }
        guard let p = AudioPacingPolicy(hostClock: hostClock,
                                        sampleRate: AudioUnitSink.pcmSampleRate,
                                        consistencyTolerance: consistencyTolerance) else { return false }
        pacingHostClock = hostClock
        pacingPolicy = p
        pacingClock = AudioMasterPacingClock(policy: p, hostClock: hostClock)
        return true
    }

    /// M1 typed pause (condition (a)): quiesce the render path. The ring
    /// residual is HELD (no consumption), intentional silence is NOT
    /// underrun/overrun (its own counter), and no clock-drift decisions
    /// run while quiesced. Typed false when not active, unattached, or
    /// already paused. The J3 pause path calls this.
    /// The WHOLE pause is one stateLock section (20:40 lifecycle race):
    /// lifecycle check + policy pause + RT flag store are atomic against
    /// stop()/start(), so a teardown can never orphan a quiesce into the
    /// next session. Boundary contract (architect 20:12) unchanged:
    /// pushIfUnpaused holds the same lock across admission + pause check
    /// + ring write, so once pauseAudio() returns true no admitted push
    /// can enter the ring; J3's async pre-push audioPaused check is an
    /// optimization, correctness does not depend on it.
    @discardableResult
    public func pauseAudio() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard case .active = lifecycle.current, let p = pacingPolicy, pausedFlag?.load() == 0 else {
            return false
        }
        guard p.pause(atHost: hostSeconds()) else { return false }
        pausedFlag?.store(1)
        return true
    }

    /// M1 typed resume: a NEW clock generation (8.5) anchored on the
    /// device-consumed counter frozen over the pause BEFORE consumption
    /// resumes - the anchor is exact and the value continues from the
    /// frozen point (no jump).
    /// One stateLock section, symmetric with pauseAudio (20:40): the
    /// policy resume (new generation on the frozen device-consumed
    /// counter), the receipt fold, and the RT flag clear are atomic
    /// against stop()/start(). The RT thread is lock-free by design, so
    /// the silence fold carries a one-callback slack at this edge;
    /// receipts reconcile at transition granularity (condition (d)).
    @discardableResult
    public func resumeAudio() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard case .active = lifecycle.current, let p = pacingPolicy, pausedFlag?.load() == 1 else {
            return false
        }
        guard p.resume(consumedFrames: ringStorage?.consumedFrames.load() ?? 0,
                       atHost: hostSeconds()) else { return false }
        p.notePausedSilence(pausedSilenceRT?.load() ?? 0)
        pausedSilenceRT?.store(0)
        pausedFlag?.store(0)
        return true
    }

    /// Periodic re-anchor for drift tracking (non-RT; the shell pacing
    /// loop calls this). Same-generation, tolerance-checked; a refusal is
    /// typed and counted, the previous anchor stays in force.
    @discardableResult
    public func samplePacingAnchor() -> AudioClockStatus? {
        stateLock.lock(); let p = pacingPolicy; let r = ringStorage; stateLock.unlock()
        guard let p, let r else { return nil }
        return p.periodicAnchor(consumedFrames: r.consumedFrames.load(), atHost: hostSeconds())
    }

    /// Intentional-pause silence rendered so far (RT counter; NOT part of
    /// underrunBytes/overrunDrops).
    public var pausedSilenceFrames: UInt64 { pausedSilenceRT?.load() ?? 0 }
    /// Real render-callback invocations so far (RT counter; every buffer
    /// render, all silence forms included). Cumulative per session start.
    public var callbackCount: UInt64 { callbacksRT?.load() ?? 0 }
    /// Frames of real ring content delivered so far (RT counter; underrun
    /// shortfall excluded). Cumulative per session start.
    public var nonSilenceFrames: UInt64 { nonSilenceRT?.load() ?? 0 }
    /// Producer gate for the composition (J3): true while the render
    /// path is quiesced - the pump must NOT push (its frames would be
    /// dropped into pausedPushDropBytes).
    public var audioPaused: Bool { (pausedFlag?.load() ?? 0) != 0 }
    /// Admitted pushes dropped while quiesced (bytes; own counter, never
    /// overrunDrops/underrunBytes).
    public var pausedPushDropBytes: UInt64 { pausedPushDropsStorage?.load() ?? 0 }
    /// True only while the pacing clock holds a proven anchor.
    public var audioMasterAvailable: Bool { pacingClock?.hasMaster ?? false }
    /// Typed pacing receipts (anchors, refusals, transitions, generation).
    public var pacingCounters: AudioPacingCounters? { pacingPolicy?.counters }

    /// Producer quiescence witness (GENERATION-BOUND; the witness is the
    /// AWAITED completion of the owned producer task, never a public flag
    /// anyone sets - runMuxed awaits the pump task, then calls this).
    public func markProducerJoined(generation g: UInt64) {
        stateLock.lock()
        if case .pending(let p) = producerState, p == g { producerState = .joined(g) }
        else { producerWitnessViolations += 1 }
        stateLock.unlock()
    }
    /// Re-arm only the producer whose owned task was joined, in the same
    /// live session and current seek fence. Never infer a witness from push.
    @discardableResult
    public func resumeProducerAfterJoin(expectedSessionGeneration g: UInt64,
                                        expectedFenceGeneration expectedFence: UInt64) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard g != 0, lifecycle.runningGen == g,
              producerState == .joined(g), fence.active == expectedFence else { return false }
        producerState = .pending(g)
        return true
    }

    public func producerNotExpected(generation g: UInt64) {
        stateLock.lock()
        if case .pending(let p) = producerState, p == g { producerState = .absent(g) }
        else { producerWitnessViolations += 1 }
        stateLock.unlock()
    }

    public func push(_ pcm: [UInt8]) {
        // One admission path: pushIfUnpaused owns the stateLock section.
        // Callers that ignore the pause gate (not J3's pump) get the
        // fail-safe: a paused push is dropped into its OWN counter, never
        // the held ring, never overrun/underrun.
        switch pushIfUnpaused(pcm, expectedGeneration: fence.active) {
        case .admitted, .stopped:
            break   // counters + ledger already written inside
        case .heldPaused:
            pausedPushDropsStorage?.fetchAdd(UInt64(pcm.count))
            if let g = lifecycle.runningGen, g != 0 {
                ledger?.append(session: ledgerSession, generation: g, segment: .pump,
                               subsystem: .audio, kind: .audioPushDrop, bytes: pcm.count,
                               note: "paused-quiesce")
            }
        }
    }

    /// Atomic pause-aware admission (J3 20:13 contract): the lifecycle
    /// admission, the EXPECTED-GENERATION binding, the pause check, and
    /// the ring write are ONE stateLock critical section - a stop/join/
    /// reset/pause cannot interleave. (The RT render path never takes
    /// stateLock.) Results are EXPLICIT (frozen shared contract,
    /// tri-state): .heldPaused = quiesced, NOTHING written or counted,
    /// the caller RETAINS the PCM and retries after resumeAudio;
    /// .stopped = lifecycle-refused OR generation-stale (fence advanced
    /// past expectedGeneration), NEVER reported as pushed - the caller
    /// re-checks currentFenceGeneration to classify; .admitted = the
    /// ring write happened. pausedFlag is written only under
    /// stateLock (pauseAudio/resumeAudio), so .heldPaused and ring
    /// admission are mutually exclusive with the pause/resume edge.
    @discardableResult
    public func pushIfUnpaused(_ pcm: [UInt8], expectedGeneration: UInt64) -> AudioPushAdmission {
        // 20:17 deadlock fix: the ledger/ledgerSession GETTERS take
        // stateLock (non-recursive) - capture them BEFORE the critical
        // section and emit ledger records AFTER it. Audited: nothing
        // else inside the section re-enters a stateLock getter
        // (lifecycle/fence/ring have their own sync; producerState and
        // ringStorage are plain fields read under the lock).
        let lgr = ledger
        let lsess = ledgerSession
        stateLock.lock()
        guard let g = lifecycle.runningGen, g != 0 else {
            pushedWhileStopped += pcm.count
            stateLock.unlock()
            return .stopped
        }
        switch producerState {
        case .pending(let p) where p == g:
            break // admitted producer, current generation
        default:
            witnessRejectedPushBytes += pcm.count
            stateLock.unlock()
            return .stopped
        }
        // The SHARED admission decision (AudioAdmissionState - the same
        // code the Linux contention test drives), made under THIS lock
        // together with the ring write: a pause edge or a seek/reset
        // fence advance cannot interleave. A generation mismatch is
        // .stopped (never .admitted); .heldPaused is returned ONLY for a
        // genuinely quiesced sink.
        switch admission.refusal(fenceActive: fence.active, expectedGeneration: expectedGeneration) {
        case .staleGeneration:
            stateLock.unlock()
            return .stopped
        case .paused:
            stateLock.unlock()
            return .heldPaused
        case nil:
            break
        }
        guard let liveRing = ringStorage else {
            witnessRejectedPushBytes += pcm.count
            stateLock.unlock()
            return .stopped
        }
        let r = pcm.withUnsafeBufferPointer { liveRing.push($0) }
        // Occupancy snapshot INSIDE the lock (architect 20:20): an
        // outside query could observe a later reset/consume and
        // misattribute occupancy to THIS push.
        let availAfter = liveRing.availableFrames
        stateLock.unlock()
        let admittedB = Int(Swift.min(r.admittedFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame
        let droppedB = Int(Swift.min(r.droppedFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame
            + Int(Swift.min(r.droppedTailBytes, UInt64(Int.max)))
        lgr?.append(session: lsess, generation: g, segment: .pump,
                    subsystem: .audio, kind: .audioPush, bytes: admittedB,
                    note: "availAfterFrames=\(availAfter)")
        if r.droppedFrames > 0 || r.droppedTailBytes > 0 {
            lgr?.append(session: lsess, generation: g, segment: .pump,
                        subsystem: .audio, kind: .audioPushDrop, bytes: droppedB)
        }
        // Per-push admitted/dropped detail stays in the ledger + ring
        // receipt; the shared contract is tri-state.
        return .admitted
    }
    public var available: Int {
        stateLock.lock(); defer { stateLock.unlock() }   // item 10: coherent storage read
        guard let ring = ringStorage else { return 0 }   // unstarted/retired: typed zero, no trap
        return Int(Swift.min(ring.availableFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame
    }
    public var kitConsumedBytes: Int { Int(Swift.min(evidence.consumedFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame }
    public var overrunDrops: Int { Int(Swift.min(evidence.droppedFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame }
    public var underrunBytes: Int { Int(Swift.min(evidence.underrunFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame }
    /// MONOTONIC clock; TYPED cancellation.
    /// Fence-active generation: advances on every seek ring reset while the
    /// lifecycle generation stays at session start - telemetry must attribute
    /// fencing to THIS, not the lifecycle generation.
    public var currentFenceGeneration: UInt64 { fence.active }
    /// M4 SEEK RING RESET (design C - owner-side, non-RT): RT quiescence via
    /// AudioOutputUnitStop (CoreAudio guarantee: no render callback runs after
    /// it returns), then fence advance + IN-PLACE ring/event reset (readers
    /// == 0 by the stop), context generation update in the quiesced window,
    /// unit restart. SAME registry slot, context root and admission cell -
    /// reservation bounds, retirement semantics and retention untouched, no
    /// new slot per seek. The producer MUST already be joined (pushes gated
    /// separately by the composition). Returns the new fence generation; nil
    /// = typed refusal (ledger-recorded), never a silent no-op.
    /// C3 (block 168 m3, factory gap, trunk hook): host volume control on the
    /// default output unit. TYPED refusal (false) when: the input is invalid
    /// (non-finite or outside [0,2] - REFUSED, never silently clamped), the
    /// session is not active, the device is terminal, the boost cell is
    /// missing for an above-unity request, or HAL rejects the parameter.
    /// Normal [0,1] requests remain available without the boost cell.
    /// Never a silent no-op, never a fabricated success.
    /// BOOST (above-unity advance): existing HAL semantics are preserved -
    /// the HAL attenuator only ever receives [0,1]. A request above unity
    /// holds the HAL AT unity and publishes the requested gain (1,2] to the
    /// lock-free outputBoostRT cell AFTER the successful HAL call; the
    /// admitted render path applies it as saturating s16le PCM gain
    /// (PCMOutputBoost). A request in [0,1] behaves exactly as before and
    /// republishes unity, clearing any prior boost.
    /// LIFETIME (r4, review finding): stateLock is HELD across the HAL call,
    /// and this SAME patch extends stateLock coverage over BOTH live
    /// AudioComponentInstanceDispose sites (the teardown() helper and the
    /// stop() path) - before r4 those disposes ran OUTSIDE the lock, so no
    /// lesser claim was true. Mutual exclusion with dispose is the real
    /// guarantee: a set either lands before disposal starts or refuses on
    /// the nil'd unit after. A set against a STOPPED-but-not-disposed unit
    /// (mid-teardown window) is harmless - the HAL errors or applies, never
    /// use-after-free. No RT deadlock: the RT render callback never takes
    /// stateLock (contract comment at the admission path); the producer's
    /// pushIfUnpaused section is non-RT and merely blocks briefly.
    public func setVolume(_ value: Float) -> Bool {
        deviceOperationLock.lock(); defer { deviceOperationLock.unlock() }
        guard value.isFinite, value >= 0, value <= PCMOutputBoost.maximum else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !deviceTerminal, case .active = lifecycle.current, let unit = self.unit else { return false }
        let boostCell = self.outputBoostRT
        guard value <= 1 || boostCell != nil else { return false }
        // HAL output volume is an AudioUnit parameter, not a property.
        // The HAL attenuator only ever receives [0,1]: above unity the HAL
        // is held at unity and the remainder is PCM gain in the render path.
        let st = AudioUnitSetParameter(unit, kHALOutputParam_Volume, kAudioUnitScope_Global, 0,
                                       Swift.min(1, value), 0)
        guard st == noErr else { return false }
        // Atomic gain publish AFTER successful HAL only. value <= 1
        // republishes unity (clears any prior boost). Non-RT write under
        // stateLock; the RT render path reads it lock-free.
        boostCell?.store(UInt64((value > 1 ? value : Float(1)).bitPattern))
        return true
    }

    public func resetRingForSeek() -> UInt64? {
        deviceOperationLock.lock(); defer { deviceOperationLock.unlock() }
        stateLock.lock()
        guard case .active = lifecycle.current, let unit = self.unit,
              let ctx = self.registration, let ring = ringStorage, let events = rtEventsStorage else {
            stateLock.unlock(); return nil
        }
        guard !deviceTerminal else {stateLock.unlock();return nil}
        let oldG = fence.active
        stateLock.unlock()
        let stStop = AudioOutputUnitStop(unit)
        guard stStop == noErr else {
            ledger?.append(session: ledgerSession, generation: oldG, segment: .pump, subsystem: .audio,
                           kind: .audioStopAttempt, bytes: 0, note: "seekResetStopFailed:\(stStop)")
            return nil
        }
        let newG = oldG &+ 1
        // 20:17 atomicity: the fence advance + ring/event reset run under
        // stateLock, so pushIfUnpaused's generation-bound admission +
        // ring write is MUTUALLY EXCLUSIVE with the reset: a push either
        // completes fully before (old generation, wiped here as pre-seek
        // media) or runs after and binds against the NEW fence (a stale
        // expectation returns .stopped). RT readers == 0: the stopped
        // unit is the RT quiescence witness. The composition's producer
        // stop+join before seeking stays MANDATORY.
        // 20:24 coherence (same anchor/fence ordering as the start
        // path): re-verify the session under the SAME stateLock section
        // that mutates fence/ring/registration. beginStop is NOT
        // stateLock-serialized: if it already flipped the state, the
        // reset is a no-op (unit left stopped; teardown owns it); if it
        // races after this check, the reset applies and stop's LATER
        // fence wins.
        stateLock.lock()
        guard case .active = lifecycle.current else {
            stateLock.unlock()
            ledger?.append(session: ledgerSession, generation: oldG, segment: .pump, subsystem: .audio,
                           kind: .presentationReset, bytes: 0, note: "seekRingReset aborted: session stopping")
            return nil
        }
        fence.setActive(newG)
        ring.resetForNewGeneration()
        events.resetForNewGeneration()
        ctx.updateGenerationForSeek(newG)
        stateLock.unlock()
        ledger?.append(session: ledgerSession, generation: newG, segment: .pump, subsystem: .audio,
                       kind: .presentationReset, bytes: 0, note: "seekRingReset \(oldG)->\(newG)")
        let stStart = AudioOutputUnitStart(unit)
        guard stStart == noErr else {
            // Unit left STOPPED with the session still active: honest state,
            // ledger-recorded; the teardown stop() path handles a stopped unit.
            ledger?.append(session: ledgerSession, generation: newG, segment: .pump, subsystem: .audio,
                           kind: .audioStopAttempt, bytes: 0, note: "seekResetRestartFailed:\(stStart)")
            return nil
        }
        // M1: seek is a new clock generation (8.5); the value stays
        // continuous/monotonic across the reset (the pump re-anchors pts).
        // 20:24 coherence: the anchor is gated on a still-active session
        // under stateLock (order stateLock -> policy lock, same as
        // pause/resume/stop). beginStop is NOT stateLock-serialized: if
        // it already flipped the state, no anchor is created here; if it
        // races after this check, the anchor applies and stop's LATER
        // sessionStop fence (same stateLock, fences the CURRENT
        // generation, which is this new one) wins - never a late anchor
        // after the fence on this session. If skipped, newG still
        // stands: fence/ring reset were applied while active.
        if let p = pacingPolicy {
            stateLock.lock()
            if case .active = lifecycle.current { _ = p.seekReset(atHost: hostSeconds()) }
            stateLock.unlock()
        }
        return newG
    }
    public func drainBounded(maxSeconds: Double) async -> (remaining: Int, cancelled: Bool) {
        let t0 = CACurrentMediaTime()
        while available > 0 && CACurrentMediaTime() - t0 < maxSeconds {
            if Task.isCancelled { return (available, true) }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return (available, Task.isCancelled)
    }

    private func render(frames: UInt32, data: UnsafeMutablePointer<AudioBufferList>?, generation: UInt64,
                        ctx: CallbackContext) -> OSStatus {
        // Already admitted AND balanced by the caller (S1a defer-on-admit).
        guard let data = data else { return noErr }
        guard frames > 0 else { return noErr }
        let buf = data.pointee.mBuffers
        let n = min(Int(frames) * SPSCPCMRing.bytesPerFrame, Int(buf.mDataByteSize))
        guard n > 0, let rawDst = buf.mData else { return noErr }
        let dst = rawDst.assumingMemoryBound(to: UInt8.self)
        callbacksRT?.fetchAdd(1)
        // Stale-generation fence (same registration, pre-retire window):
        // fenced to silence; the event post is safe - the event ring's only
        // producers are ADMITTED readers of the live registration, and any
        // reset waits for readers==0 (constraint B).
        guard fence.checkRT(generation) else {
            ctx.events?.post(.staleFenced, generation: generation, payload: .bytes(UInt64(n)))
            memset(dst, 0, n)
            return noErr
        }
        let wholeFrames = UInt32(n / SPSCPCMRing.bytesPerFrame)
        // M1 typed pause/quiesce (architect 19:50 condition (a)): while
        // quiesced the callback renders bounded-zero silence WITHOUT
        // consuming the ring (the residual is HELD), WITHOUT underrun /
        // overrun accounting, and WITHOUT RT events. Lock-free RT read;
        // the silence is its own counter, folded into pacing receipts on
        // resume so counters reconcile 1:1.
        if pausedFlag?.load() != 0 {
            memset(dst, 0, n)
            pausedSilenceRT?.fetchAdd(UInt64(wholeFrames))
            return noErr
        }
        guard let ring = ctx.ring else {
            // Detached payload (clean tombstone): a late callback after
            // dispose renders bounded-zero silence, touching nothing.
            memset(dst, 0, n)
            return noErr
        }
        let under = ring.render(into: dst, frames: wholeFrames)
        nonSilenceRT?.fetchAdd(UInt64(under >= wholeFrames ? 0 : wholeFrames - under))
        let written = Int(wholeFrames) * SPSCPCMRing.bytesPerFrame
        if written < n { memset(dst + written, 0, n - written) }
        // C3 boost: saturating PCM gain over the just-rendered region only;
        // the underrun tail stays bounded-zero silence (disjoint regions).
        // Lock-free RT read of the gain cell; unity is a no-op inside the
        // helper. No allocation, lock, task, file or callback added here.
        let gainBits = outputBoostRT?.load() ?? UInt64(Float(1).bitPattern)
        PCMOutputBoost.apply(Float(bitPattern: UInt32(truncatingIfNeeded: gainBits)),
                             bytes: rawDst, count: written)
        if under > 0 {
            if !starving { starving = true; ctx.events?.post(.underrunStart, generation: generation, payload: .frames(UInt64(under))) }
        } else if starving {
            starving = false
            ctx.events?.post(.underrunEnd, generation: generation, payload: .frames(0))
        }
        return noErr
    }

    /// Test seam: synchronously invokes the REAL render body (including
    /// admission) against a DISPOSABLE context whose admission is live and
    /// whose generation is the fence's CURRENT one - requires a REAL
    /// started session for content (otherwise fenced silence). No
    /// fake-running state exists anywhere.
    public func testRender(frames: UInt32, data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        // S2: the test seam enters the REAL registration's admission cell -
        // an ephemeral cell would bypass the ONE-consumer contract against
        // a live provider callback (architect full verdict S2). No started
        // session is a typed refusal; a busy cell renders bounded-zero
        // silence with a valid return (S1b).
        stateLock.lock(); let ctxOpt = registration; stateLock.unlock()
        guard let ctx = ctxOpt else { return -50 }
        guard ctx.admission.enter() else { AudioUnitSink.zeroBuffers(data); return noErr }
        defer { ctx.admission.exit() }
        return render(frames: frames, data: data, generation: ctx.generation, ctx: ctx)
    }

    @discardableResult

    /// Early start aborts (a typed refusal AFTER the generation was
    /// born) publish a terminal outcome too (verdict S4 rev2) - the
    /// cache never holds a born generation with NO outcome.
    private func publishAbortedStart(generation g: UInt64) {
        let ev = AudioStopEvidence(generation: g, stopStatus: nil, uninitStatus: nil,
            disposeStatus: nil, readersDrained: false, producerWitnessed: false,
            drainResidual: nil, retainedRegistration: nil)
        outcomeCache.publish(generation: g, outcome: .failed(ev))
    }

    /// Publish-then-return (findings 8/9): the outcome is cached BEFORE
    /// the caller performs the lifecycle transition.
    private func terminalOutcome(_ o: AudioStopOutcome) -> AudioStopOutcome {
        switch o {
        case .complete(let e): outcomeCache.publish(generation: e.generation, outcome: o)
        case .failed(let e): outcomeCache.publish(generation: e.generation, outcome: o)
        case .pending, .noop: break
        }
        return o
    }

    public func stop() -> AudioStopOutcome {
        deviceOperationLock.lock(); defer { deviceOperationLock.unlock() }
        stateLock.lock()
        if deviceTerminal {
            let token=registrationToken?.id,generation=registration?.generation ?? currentGeneration
            stateLock.unlock()
            return terminalOutcome(.failed(AudioStopEvidence(generation:generation,stopStatus:nil,
                uninitStatus:nil,disposeStatus:nil,readersDrained:false,producerWitnessed:false,
                drainResidual:nil,retainedRegistration:token)))
        }
        stateLock.unlock()
        stateLock.lock(); _stopCallCount += 1; let stopN = _stopCallCount; stateLock.unlock()
        // Verdict S4: the in-flight marker is taken ATOMICALLY with the
        // lifecycle stop transition (inside its lock) - a marker taken
        // after beginStop left a noop gap for concurrent stop calls.
        switch lifecycle.beginStop(onStopTransition: { [weak self] in self?.outcomeCache.noteStopInFlight() }) {
        case .none:
            // Findings 7/9: .pending while a stop is in flight; the
            // cached outcome ONLY for the current generation; .noop
            // only when no evidence exists at all.
            let idle = outcomeCache.idleOutcome()
            ledger?.append(session: ledgerSession, generation: 0, segment: .teardown,
                           subsystem: .audio, kind: .stopCall, bytes: stopN,
                           note: idle.isComplete ? "repeatStopReturnsPreservedOutcome" : (idle == .pending ? "pending" : "noop"))
            return idle
        case .startWillTearDown(let g):
            fence.advance()
            ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                           subsystem: .audio, kind: .stopCall, bytes: stopN, note: "racedStart")
            // The racing START owns the teardown; no terminal evidence
            // exists for THIS call yet - typed .pending, never a fake
            // success struct.
            return .pending
        case .teardownOwned(let g):
            fence.advance()
            // M1: fence the pacing master with the session - a later
            // clock reading fails STOP (2.2), never substitutes wall
            // time. Under stateLock (20:22): what the shared stateLock
            // serializes is the FENCE application against the anchor
            // sections (start tail, seek reset) and pauseAudio/
            // resumeAudio (order stateLock -> policy lock, no lifecycle
            // inversion). beginStop above runs OUTSIDE stateLock and is
            // NOT serialized by it: if beginStop raced an anchor's
            // active-check, the anchor applied first and THIS later
            // fence wins.
            stateLock.lock()
            pacingPolicy?.sessionStop()
            stateLock.unlock()
            ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                           subsystem: .audio, kind: .audioStopAttempt, bytes: stopN)
            stateLock.lock()
            let unitOpt = self.unit
            let ctxOpt = self.registration
            let pState = producerState
            let rid = registrationToken
            stateLock.unlock()
            guard let unit = unitOpt, let ctx = ctxOpt else {
                stateLock.lock(); _failedStopCount += 1; stateLock.unlock()
                // Verdict S2: the no-local-ctx path retains an ORPHAN
                // FAULT OWNER - the registry still holds the immutable
                // context root, and the sink-owned graph attaches
                // alongside it (a bare reclassify retained no owner).
                // Verdict S4: statuses are NIL (never attempted), and
                // publication precedes the lifecycle transition.
                // Verdict S4 rev2: the registry still roots the stale
                // CallbackContext - RETIRE its admission through the
                // capability-gated accessor before re-owning the graph,
                // so no live provider callback keeps touching it.
                if let rid, let stale = registry.root(of: rid) as? CallbackContext {
                    stale.admission.retire()
                }
                let retainedOk = retainFaultGraph(token: rid, unit: unitOpt, generation: g,
                    stopStatus: nil, uninitStatus: nil, disposeStatus: nil,
                    readersDrained: false, producerWitnessed: false,
                    cause: "noLocalContext orphanFaultOwner")
                let out = AudioStopOutcome.failed(AudioStopEvidence(generation: g, stopStatus: nil,
                    uninitStatus: nil, disposeStatus: nil, readersDrained: false,
                    producerWitnessed: false, drainResidual: nil,
                    retainedRegistration: retainedOk ? rid?.id : nil))
                terminalOutcome(out)
                lifecycle.failStop(g)
                return out
            }
            // Constraint A ordering: RETIRE FIRST. Every later callback
            // goes silent touching nothing, regardless of provider timing.
            ctx.admission.retire()
            let witnessed: Bool
            switch pState {
            case .joined(let jg), .absent(let jg): witnessed = (jg == g)
            case .pending, .idle: witnessed = false
            }
            guard witnessed else {
                // Producer witness missing: the unit is now retired+fenced
                // (silent) but still running per the provider. This is an
                // explicitly BOUNDED RETAINED FAULT - NOT a completed
                // teardown. Nothing is drained, reset, or disposed.
                stateLock.lock(); _failedStopCount += 1; stateLock.unlock()
                // Verdict S4: stop/uninit were DELIBERATELY not attempted
                // (unit left running per the bounded-fault contract) -
                // statuses NIL, never fabricated; retain result checked.
                let retainedOk = retainFaultGraph(token: rid, unit: unit, generation: g,
                    stopStatus: nil, uninitStatus: nil, disposeStatus: nil,
                    readersDrained: false, producerWitnessed: false,
                    cause: "producerWitnessMissing unitRetiredFencedRunning")
                ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                               subsystem: .audio, kind: .decodeError,
                               note: "boundedRetainedFault=1 cause=producerWitnessMissing unitRetiredFencedRunning=1 NOTcompletedTeardown retained=\(retainedOk ? 1 : 0)")
                let out = AudioStopOutcome.failed(AudioStopEvidence(generation: g, stopStatus: nil,
                    uninitStatus: nil, disposeStatus: nil, readersDrained: false,
                    producerWitnessed: false, drainResidual: nil,
                    retainedRegistration: retainedOk ? rid?.id : nil))
                terminalOutcome(out)
                lifecycle.failStop(g)
                return out
            }
            let stStop = AudioOutputUnitStop(unit)
            let stUninit = AudioUnitUninitialize(unit)
            // Drain admitted readers AFTER stop+uninit; a timeout is
            // TERMINAL (constraint D): no dispose, no reset, no finishStop.
            // Monotonic deadline (verdict S2), 50ms bounded reader drain.
            let drainDeadline = CACurrentMediaTime() + 0.050
            while ctx.admission.readers != 0 && CACurrentMediaTime() < drainDeadline {
                usleep(500)
            }
            let drained = ctx.admission.readers == 0
            if !drained { stateLock.lock(); _readerDrainTimeouts += 1; stateLock.unlock() }
            guard stStop == noErr && stUninit == noErr && drained else {
                stateLock.lock()
                _failedStopCount += 1
                registration = nil
                stateLock.unlock()
                let retainedOk = retainFaultGraph(token: rid, unit: unit, generation: g,
                    stopStatus: stStop, uninitStatus: stUninit, disposeStatus: nil,
                    readersDrained: drained, producerWitnessed: true, cause: "teardownFailed")
                ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                               subsystem: .audio, kind: .decodeError,
                               note: "teardownFailed stop=\(stStop) uninit=\(stUninit) drained=\(drained ? 1 : 0) retained=\(retainedOk ? 1 : 0)")
                let out = AudioStopOutcome.failed(AudioStopEvidence(generation: g, stopStatus: stStop,
                    uninitStatus: stUninit, disposeStatus: nil, readersDrained: drained,
                    producerWitnessed: true, drainResidual: nil,
                    retainedRegistration: retainedOk ? rid?.id : nil))
                terminalOutcome(out)
                lifecycle.failStop(g)
                return out
            }
            // r4 (setVolume lifetime): dispose under stateLock, mutually
            // exclusive with a concurrent C3 setVolume (see its contract
            // comment). registration clearing joins the same section.
            stateLock.lock()
            let stDisp = AudioComponentInstanceDispose(unit)
            registration = nil
            if stDisp == noErr {
                // XA9 r2 finding: nil the unit INSIDE the dispose section.
                // A later separate section would leave self.unit pointing at
                // a disposed unit between the two locks - a C3 setVolume
                // acquiring the lock in that window would call the HAL on
                // freed state. With the nil here, every lock release after a
                // successful dispose observes unit == nil (typed refusal).
                _disposeCount += 1
                self.unit = nil
            }
            stateLock.unlock()
            guard stDisp == noErr else {
                stateLock.lock(); _failedDisposeCount += 1; stateLock.unlock()
                let retainedOk = retainFaultGraph(token: rid, unit: unit, generation: g,
                    stopStatus: stStop, uninitStatus: stUninit, disposeStatus: stDisp,
                    readersDrained: true, producerWitnessed: true, cause: "disposeFailed")
                ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                               subsystem: .audio, kind: .decodeError,
                               note: "disposeFailed=\(stDisp) retained=\(retainedOk ? 1 : 0)")
                let out = AudioStopOutcome.failed(AudioStopEvidence(generation: g, stopStatus: stStop,
                    uninitStatus: stUninit, disposeStatus: stDisp, readersDrained: true,
                    producerWitnessed: true, drainResidual: nil,
                    retainedRegistration: retainedOk ? rid?.id : nil))
                terminalOutcome(out)
                lifecycle.failStop(g)
                return out
            }
            // Verdict S5 rev5: the payload is still attached HERE
            // (detach happens only on the clean path below) - a nil is
            // an internal contract violation, a typed retained fault,
            // never a force-unwrap trap.
            guard let receiptRing = ctx.ring else {
                stateLock.lock(); _failedStopCount += 1; stateLock.unlock()
                let retainedOk = retainFaultGraph(token: rid, unit: nil, generation: g,
                    stopStatus: stStop, uninitStatus: stUninit, disposeStatus: stDisp,
                    readersDrained: true, producerWitnessed: true,
                    cause: "payloadDetachedBeforeReceipt")
                let out = AudioStopOutcome.failed(AudioStopEvidence(generation: g, stopStatus: stStop,
                    uninitStatus: stUninit, disposeStatus: stDisp, readersDrained: true,
                    producerWitnessed: true, drainResidual: nil,
                    retainedRegistration: retainedOk ? rid?.id : nil))
                terminalOutcome(out)
                lifecycle.failStop(g)
                return out
            }
            let receipt = receiptRing.snapshotReceipt(generation: g)
            stateLock.lock()
            _stoppedReceipt = receipt
            stateLock.unlock()
            if let rid { _ = registry.reclassify(rid, to: .tombstone) }
            drainRTTransitions(segment: .teardown)
            // Constraint B: retired, readers==0, producer witnessed,
            // disposed, receipt taken - no old-generation writer can
            // exist. Verdict S5 rev5: DETACH the payload so the registry
            // tombstone retains the minimal root only (no PCM/event
            // buffers held forever). Fault paths above NEVER detach.
            ctx.detach()
            ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                           subsystem: .audio, kind: .audioStopAccepted)
            ledger?.append(session: ledgerSession, generation: g, segment: .teardown,
                           subsystem: .audio, kind: .disposeCompleted, bytes: disposeCount,
                           note: "disposeStatus=0 readersDrained=1")
            // Stable retired-generation snapshot, after producer/readers join.
            // Saturate malformed evidence instead of unsigned underflow.
            let residualFrames = receipt.pushedFrames >= receipt.consumedFrames
                ? receipt.pushedFrames - receipt.consumedFrames : 0
            let residual = Int(Swift.min(residualFrames, UInt64(UInt32.max))) * SPSCPCMRing.bytesPerFrame
            let out = AudioStopOutcome.complete(AudioStopEvidence(generation: g, stopStatus: stStop,
                uninitStatus: stUninit, disposeStatus: stDisp, readersDrained: true,
                producerWitnessed: true, drainResidual: residual, retainedRegistration: rid?.id))
            // Verdict S4: publication precedes the lifecycle transition.
            terminalOutcome(out)
            lifecycle.finishStop(g)
            return out
        }
    }

    /// Stage A only. No session/menu caller is added in this candidate.
    /// Explicit selection is opt-in; no-selection sessions retain DefaultOutput.
    public func outputDeviceInventory() -> Result<AudioOutputDeviceInventory, AudioDeviceFailure> {
        deviceOperationLock.lock();defer {deviceOperationLock.unlock()}
        stateLock.lock();defer {stateLock.unlock()}
        guard !deviceTerminal,case .active = lifecycle.current,let unit else {
            return .failure(AudioDeviceFailure(.stopped))
        }
        do {
            let uid=try CoreAudioOutputInventory.currentUID(unit:unit)
            return .success(try CoreAudioOutputInventory.snapshot(currentUID:uid))
        } catch {return .failure(error as? AudioDeviceFailure ?? AudioDeviceFailure(.inventory))}
    }
    public var outputDeviceSelectionResult:AudioDeviceSelectionResult? {
        stateLock.lock();defer {stateLock.unlock()};return lastDeviceResult
    }
    public func selectOutputDevice(uid:String)->AudioDeviceSelectionResult {
        deviceOperationLock.lock();defer {deviceOperationLock.unlock()}
        stateLock.lock()
        guard !deviceTerminal,case .active = lifecycle.current,let unit,let ctx=registration else {
            stateLock.unlock();return .refused(AudioDeviceFailure(.stopped))
        }
        let wasPaused=pausedFlag?.load() ?? 0
        let temporaryPolicy=wasPaused==0 ? pacingPolicy:nil
        if let temporaryPolicy,!temporaryPolicy.pause(atHost:hostSeconds()) {
            stateLock.unlock();return .refused(AudioDeviceFailure(.quiesce))
        }
        pausedFlag?.store(1) // existing RT silence gate; no ring reset/rebind
        let provider=DeviceHandoff(sink:self,unit:unit,context:ctx)
        var transaction=AudioOutputDeviceTransaction(currentToken:1,selectedUID:explicitDeviceTransaction?.selectedUID)
        var result=transaction.select(uid:uid,provider:provider)
        if provider.terminal {
            result = .terminal(failure:AudioDeviceFailure(.prepare),rollback:AudioDeviceFailure(.dispose))
        }
        if case .accepted = result,transaction.currentToken==1,outputDeviceWatch==nil {
            do {
                let device=try CoreAudioOutputInventory.resolve(uid:uid)
                provider.watch=try CoreAudioOutputWatch(device:device) { [weak self] in
                    DispatchQueue.global().async { [weak self] in self?.reviewSelectedOutputDevice() }
                }
            } catch {result = .refused(error as? AudioDeviceFailure ?? AudioDeviceFailure(.inventory))}
        }
        if case .accepted = result,let selected=provider.units[transaction.currentToken] {
            self.unit=selected
            self.registration=provider.contexts[transaction.currentToken]
            self.registrationToken=provider.tokens[transaction.currentToken]
            outputDeviceWatch=provider.watch ?? outputDeviceWatch
            explicitDeviceTransaction=AudioOutputDeviceTransaction(currentToken:1,selectedUID:transaction.selectedUID)
        }
        if let temporaryPolicy,case .terminal = result {temporaryPolicy.sessionStop()}
        else if let temporaryPolicy {
            if !temporaryPolicy.resume(consumedFrames:ringStorage?.consumedFrames.load() ?? 0,atHost:hostSeconds()) {
                provider.retainTerminal(Array(provider.units.keys))
                result = .terminal(failure:AudioDeviceFailure(.activate),rollback:AudioDeviceFailure(.rollback))
            } else {
                temporaryPolicy.notePausedSilence(pausedSilenceRT?.load() ?? 0)
                pausedSilenceRT?.store(0)
            }
        }
        let terminal:Bool
        if case .terminal = result {terminal=true;deviceTerminal=true;ctx.admission.retire();pacingPolicy?.sessionStop()}
        else {terminal=false;pausedFlag?.store(wasPaused)}
        lastDeviceResult=result
        let token=registrationToken,generation=ctx.generation
        stateLock.unlock()
        if terminal {
            // Registry root is the same immutable callback context. Additional
            // failed handles are strongly retained on this fault-owned sink.
            _ = retainFaultGraph(token:token,unit:self.unit,generation:generation,
                stopStatus:nil,uninitStatus:nil,disposeStatus:nil,readersDrained:false,
                producerWitnessed:false,cause:"explicitOutputDeviceTerminal")
        }
        return result
    }
    private func reviewSelectedOutputDevice() {
        deviceOperationLock.lock();defer {deviceOperationLock.unlock()}
        stateLock.lock()
        guard !deviceTerminal,var transaction=explicitDeviceTransaction,case .active = lifecycle.current,
              let unit,let ctx=registration else {stateLock.unlock();return}
        let provider=DeviceHandoff(sink:self,unit:unit,context:ctx)
        let result=transaction.validateCurrent(provider:provider)
        explicitDeviceTransaction=transaction
        guard case .terminal = result else {stateLock.unlock();return}
        deviceTerminal=true;ctx.admission.retire();pausedFlag?.store(1);pacingPolicy?.sessionStop()
        lastDeviceResult=result
        let token=registrationToken,generation=ctx.generation
        stateLock.unlock()
        _ = retainFaultGraph(token:token,unit:unit,generation:generation,stopStatus:nil,
            uninitStatus:nil,disposeStatus:nil,readersDrained:false,producerWitnessed:false,
            cause:"selectedOutputDeviceUnavailable")
    }
    /// Synchronous, lock-owned adapter. Never escapes the transaction. Callback
    /// contexts remain registry-rooted; no fresh generation or ring is invented.
    private final class DeviceHandoff:AudioDeviceHandoffProvider {
        var requiresReplacementForSelection:Bool {true}
        unowned let sink:AudioUnitSink
        let context:CallbackContext
        var units:[UInt64:AudioUnit]
        var contexts:[UInt64:CallbackContext]
        var tokens:[UInt64:RegistrationToken]=[:]
        var watch:CoreAudioOutputWatch?
        var terminal=false
        var initialized:Set<UInt64>=[1]
        init(sink:AudioUnitSink,unit:AudioUnit,context:CallbackContext) {
            self.sink=sink;self.context=context;self.units=[1:unit];self.contexts=[1:context]
            self.tokens[1]=sink.registrationToken
        }
        func inventory()throws->AudioOutputDeviceInventory {try CoreAudioOutputInventory.snapshot()}
        func currentUID(_ token:UInt64)throws->String {
            guard let unit=units[token] else{throw AudioDeviceFailure(.readback)}
            return try CoreAudioOutputInventory.currentUID(unit:unit)
        }
        func prepare(uid:String)throws->UInt64 {
            let id=try CoreAudioOutputInventory.resolve(uid:uid)
            var description=AudioComponentDescription(componentType:kAudioUnitType_Output,
                componentSubType:kAudioUnitSubType_HALOutput,componentManufacturer:kAudioUnitManufacturer_Apple,
                componentFlags:0,componentFlagsMask:0)
            guard let component=AudioComponentFindNext(nil,&description) else {throw AudioDeviceFailure(.prepare)}
            var created:AudioUnit?
            var status=AudioComponentInstanceNew(component,&created)
            guard status==noErr,let unit=created else{throw AudioDeviceFailure(.prepare,status:status)}
            units[2]=unit
            do {
                guard let ring=context.ring,let events=context.events,
                      let fresh=CallbackContext(generation:context.generation,sink:sink,ring:ring,events:events) else {
                    throw AudioDeviceFailure(.prepare)
                }
                let reservation:PlaybackRegistry.Reservation
                switch sink.registry.reserve(.active) {
                case .failure:throw AudioDeviceFailure(.prepare)
                case .success(let value):reservation=value
                }
                guard let registration=sink.registry.register(root:fresh,token:reservation) else {
                    sink.registry.rollback(reservation);throw AudioDeviceFailure(.prepare)
                }
                contexts[2]=fresh;tokens[2]=registration
                var enabled:UInt32=1,disabled:UInt32=0,device=id
                status=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Output,0,&enabled,4)
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                status=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&disabled,4)
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                status=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&device,UInt32(MemoryLayout<AudioDeviceID>.size))
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                var format=AudioStreamBasicDescription(mSampleRate:44100,mFormatID:kAudioFormatLinearPCM,
                    mFormatFlags:kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                    mBytesPerPacket:4,mFramesPerPacket:1,mBytesPerFrame:4,mChannelsPerFrame:2,mBitsPerChannel:16,mReserved:0)
                status=AudioUnitSetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                guard let fresh=contexts[2] else{throw AudioDeviceFailure(.prepare)}
                var cb=sink.deviceCallback(fresh)
                status=AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&cb,UInt32(MemoryLayout<AURenderCallbackStruct>.size))
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                guard let old=units[1] else{throw AudioDeviceFailure(.prepare)}
                var volume:AudioUnitParameterValue=0
                status=AudioUnitGetParameter(old,kHALOutputParam_Volume,kAudioUnitScope_Global,0,&volume)
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                status=AudioUnitSetParameter(unit,kHALOutputParam_Volume,kAudioUnitScope_Global,0,volume,0)
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                status=AudioUnitInitialize(unit)
                guard status==noErr else{throw AudioDeviceFailure(.prepare,status:status)}
                initialized.insert(2)
                // Watch is established before activation. Notification only
                // queues an owner readback; it never blocks in the HAL callback.
                watch=try CoreAudioOutputWatch(device:id) { [weak sink] in
                    DispatchQueue.global().async { [weak sink] in sink?.reviewSelectedOutputDevice() }
                }
                return 2
            } catch {
                do {try dispose(2)} catch {retainTerminal([1,2])}
                throw error
            }
        }
        func quiesce(_ token:UInt64)throws {
            guard let unit=units[token] else{throw AudioDeviceFailure(.quiesce)}
            let status=AudioOutputUnitStop(unit)
            guard status==noErr else{throw AudioDeviceFailure(.quiesce,status:status)}
            let deadline=CACurrentMediaTime()+0.050
            guard let local=contexts[token] else{throw AudioDeviceFailure(.quiesce)}
            while local.admission.readers != 0 && CACurrentMediaTime()<deadline {usleep(500)}
            guard local.admission.readers==0 else{throw AudioDeviceFailure(.quiesce)}
        }
        func activate(_ token:UInt64)throws {
            guard let unit=units[token] else{throw AudioDeviceFailure(.activate)}
            let status=AudioOutputUnitStart(unit)
            guard status==noErr else{throw AudioDeviceFailure(.activate,status:status)}
        }
        func dispose(_ token:UInt64)throws {
            guard let unit=units[token] else{throw AudioDeviceFailure(.dispose)}
            // Permanent retirement is per provider registration, never the
            // shared ring. A late disposed-unit callback cannot consume media.
            if let local=contexts[token] {
                local.admission.retire()
                let deadline=CACurrentMediaTime()+0.050
                while local.admission.readers != 0 && CACurrentMediaTime()<deadline {usleep(500)}
                guard local.admission.readers==0 else{throw AudioDeviceFailure(.dispose)}
            }
            if initialized.contains(token) {
                let status=AudioUnitUninitialize(unit)
                guard status==noErr else{throw AudioDeviceFailure(.dispose,status:status)}
                initialized.remove(token)
            }
            let status=AudioComponentInstanceDispose(unit)
            guard status==noErr else{throw AudioDeviceFailure(.dispose,status:status)}
            units.removeValue(forKey:token)
            if let registration=tokens[token] {_ = sink.registry.reclassify(registration,to:.tombstone)}
            contexts[token]?.detach()
        }
        func retainTerminal(_ tokens:[UInt64]) {
            terminal=true
            for token in tokens {
                contexts[token]?.admission.retire()
                if let unit=units[token] {sink.retainedDeviceUnits.append(unit)}
                // Main selection publishes one fault graph retaining this sink;
                // extra callback roots remain registered, never freed/reused.
                if let registration=self.tokens[token] {_ = sink.registry.reclassify(registration,to:.fault)}
            }
        }
    }
    private func deviceCallback(_ ctx:CallbackContext)->AURenderCallbackStruct {
        let ctxPtr=Unmanaged.passUnretained(ctx).toOpaque()
        let cb = AURenderCallbackStruct(inputProc: { refCon, _, _, _, frames, data -> OSStatus in
            // Constraint A: admission BEFORE any payload touch. A retired
            // registration's callback renders silence and dereferences
            // NOTHING (no sink, ring, event ring, or ledger).
            let c = Unmanaged<CallbackContext>.fromOpaque(refCon).takeUnretainedValue()
            // S1b: a REFUSED admission (retired) renders BOUNDED-ZERO
            // silence with a VALID noErr return - never an error status
            // with unzeroed output, and NO event post (no old ring).
            guard c.admission.enter() else {
                AudioUnitSink.zeroBuffers(data); return noErr
            }
            // S1a: EVERY admitted path is balanced - the exit is deferred
            // AT ADMISSION, not only on the render path (the old shape
            // leaked the reader when the weak sink was nil).
            defer { c.admission.exit() }
            guard let sink = c.sink else {
                AudioUnitSink.zeroBuffers(data); return noErr
            }
            return sink.render(frames: frames, data: data, generation: c.generation, ctx: c)
        }, inputProcRefCon: ctxPtr)

        return cb
    }
}
#endif

