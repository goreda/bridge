#if canImport(AppKit) && canImport(CoreAudio)
import AudioUnit
import AudioToolbox
import Foundation
import QuartzCore
import GorAVPlaybackCore

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
    private var unit: AudioUnit?
    /// Rings are created in start() AFTER the registry reserve (verdict
    /// S1: allocation-before-reserve was the r2 leak class). Nil before
    /// the first start; the RT callback is installed only after.
    private var ringStorage: SPSCPCMRing?
    private var rtEventsStorage: SPSCEventRing?
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
                stD = AudioComponentInstanceDispose(unit)
                if stD == noErr {
                    stateLock.lock(); _disposeCount += 1; self.unit = nil; stateLock.unlock()
                } else {
                    stateLock.lock(); _failedDisposeCount += 1; stateLock.unlock()
                    clean = false
                }
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
    }

    /// Producer quiescence witness (GENERATION-BOUND; the witness is the
    /// AWAITED completion of the owned producer task, never a public flag
    /// anyone sets - runMuxed awaits the pump task, then calls this).
    public func markProducerJoined(generation g: UInt64) {
        stateLock.lock()
        if case .pending(let p) = producerState, p == g { producerState = .joined(g) }
        else { producerWitnessViolations += 1 }
        stateLock.unlock()
    }
    public func producerNotExpected(generation g: UInt64) {
        stateLock.lock()
        if case .pending(let p) = producerState, p == g { producerState = .absent(g) }
        else { producerWitnessViolations += 1 }
        stateLock.unlock()
    }

    public func push(_ pcm: [UInt8]) {
        // v5 bug fix: the admission check AND the ring write hold stateLock
        // TOGETHER - a stop/join/reset cannot interleave between them.
        // (The RT render path never takes stateLock: it stays lock-free.)
        stateLock.lock()
        guard let g = lifecycle.runningGen, g != 0 else {
            pushedWhileStopped += pcm.count
            stateLock.unlock()
            return
        }
        switch producerState {
        case .pending(let p) where p == g:
            break // admitted producer, current generation
        case .joined, .absent:
            witnessRejectedPushBytes += pcm.count
            stateLock.unlock()
            return
        default:
            witnessRejectedPushBytes += pcm.count
            stateLock.unlock()
            return
        }
        guard let liveRing = ringStorage else {
            witnessRejectedPushBytes += pcm.count
            stateLock.unlock()
            return
        }
        let r = pcm.withUnsafeBufferPointer { liveRing.push($0) }
        stateLock.unlock()
        let admittedB = Int(Swift.min(r.admittedFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame
        let droppedB = Int(Swift.min(r.droppedFrames, UInt64(Int.max / 4))) * SPSCPCMRing.bytesPerFrame
            + Int(Swift.min(r.droppedTailBytes, UInt64(Int.max)))
        ledger?.append(session: ledgerSession, generation: g, segment: .pump,
                       subsystem: .audio, kind: .audioPush, bytes: admittedB,
                       note: "availAfterFrames=\(liveRing.availableFrames)")
        if r.droppedFrames > 0 || r.droppedTailBytes > 0 {
            ledger?.append(session: ledgerSession, generation: g, segment: .pump,
                           subsystem: .audio, kind: .audioPushDrop, bytes: droppedB)
        }
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
    public func resetRingForSeek() -> UInt64? {
        stateLock.lock()
        guard case .active = lifecycle.current, let unit = self.unit,
              let ctx = self.registration, let ring = ringStorage, let events = rtEventsStorage else {
            stateLock.unlock(); return nil
        }
        let oldG = fence.active
        stateLock.unlock()
        let stStop = AudioOutputUnitStop(unit)
        guard stStop == noErr else {
            ledger?.append(session: ledgerSession, generation: oldG, segment: .pump, subsystem: .audio,
                           kind: .audioStopAttempt, bytes: 0, note: "seekResetStopFailed:\(stStop)")
            return nil
        }
        let newG = oldG &+ 1
        fence.setActive(newG)            // stale-generation records fence (defensive; no readers possible)
        ring.resetForNewGeneration()     // readers == 0: the stopped unit is the quiescence witness
        events.resetForNewGeneration()
        ctx.updateGenerationForSeek(newG)
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
        guard let ring = ctx.ring else {
            // Detached payload (clean tombstone): a late callback after
            // dispose renders bounded-zero silence, touching nothing.
            memset(dst, 0, n)
            return noErr
        }
        let under = ring.render(into: dst, frames: wholeFrames)
        let written = Int(wholeFrames) * SPSCPCMRing.bytesPerFrame
        if written < n { memset(dst + written, 0, n - written) }
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
            let stDisp = AudioComponentInstanceDispose(unit)
            stateLock.lock()
            registration = nil
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
            _disposeCount += 1
            _stoppedReceipt = receipt
            self.unit = nil
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
            let residual = Int(Swift.min(receipt.availableFrames, UInt64(UInt32.max))) * SPSCPCMRing.bytesPerFrame
            let out = AudioStopOutcome.complete(AudioStopEvidence(generation: g, stopStatus: stStop,
                uninitStatus: stUninit, disposeStatus: stDisp, readersDrained: true,
                producerWitnessed: true, drainResidual: residual, retainedRegistration: rid?.id))
            // Verdict S4: publication precedes the lifecycle transition.
            terminalOutcome(out)
            lifecycle.finishStop(g)
            return out
        }
    }
}
#endif
