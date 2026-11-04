public actor FramePump {
    private let source: FrameSource; private let sink: FrameSink
    private let clock: PlaybackClock; private let decider: AVSyncDecider
    /// Seek pacing re-anchor (M4): maps stream pts onto the wall clock.
    /// Set at the FIRST frame decision of each presentation generation
    /// (pump start AND after every successful resetPresentation): that frame
    /// shows on arrival - the measured late-start gap is the REAL wall time
    /// it took to arrive, preserved, never smoothed - and later frames pace
    /// by their pts deltas off the anchor. Without it a post-seek pts (T)
    /// judged against raw wall time (W) freezes forward seeks (waits T-W)
    /// or drop-storms backward seeks to EOF.
    private var paceAnchorPts: Double? = nil
    private var paceAnchorWall: Double = 0
    /// The pace anchor currently in force (nil = arrival anchoring). Read by the
    /// composition so audio resumes off the ACTUAL commit anchor, not a
    /// pre-seek preparation timestamp.
    public var currentPaceAnchor: MediaWallAnchor? {
        guard let m = paceAnchorPts else { return nil }
        return MediaWallAnchor(mediaSeconds: m, wallSeconds: paceAnchorWall)
    }

    /// M1 pause state (observability for shells/receipts).
    public var isPaused: Bool { paused }
    public var pauseCount: Int { pauseCountTotal }
    public var pausedWallSecondsTotal: Double { pausedWallTotal }
    /// M1 pause (typed, idempotent): takes effect at the pump's next
    /// control point (top of loop / before a frame decision). A frame
    /// already pulled is HELD un-admitted and re-decided on resume; no
    /// frame is shown, dropped or admitted BECAUSE of a pause.
    public func pause() {
        guard !paused else { return }
        paused = true
        pauseBeganWall = ProcessInfo.processInfo.systemUptime
        pauseCountTotal += 1
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .pauseEntered)
    }
    /// Resume uses arrival anchoring, valid for frozen audio-master clocks
    /// and wall fallback alike. Never add elapsed pause time to a clock
    /// that already freezes while paused.
    public func resume() {
        guard paused, let began = pauseBeganWall else { return }
        let pausedWall = Swift.max(0, ProcessInfo.processInfo.systemUptime - began)
        paused = false
        pauseBeganWall = nil
        pausedWallTotal += pausedWall
        paceAnchorPts = nil
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .pauseResumed,
                       note: "pausedWall_s=\(pausedWall)")
    }
    /// The park loop: while paused, wait in bounded cancellable slices and
    /// keep honoring cancel/close. Returns true when the run must END
    /// (cancel or close observed while parked); reason/stats are set.
    private func parkWhilePaused(stats: inout PumpStats, reason: inout PumpEndReason) async -> Bool {
        while paused {
            guard clock.nowSeconds().isFinite else {
                reason = .failed(-93)
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "clockNonFiniteWhilePaused")
                return true
            }
            if Task.isCancelled || (commit?.isCancelled ?? false) {
                commit?.requestCancel()
                stats.cancelled = true
                reason = .cancelled
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "cancelledWhilePaused")
                return true
            }
            if let closeRequested, await closeRequested() {
                commit?.requestCancel()
                stats.cancelled = true; stats.windowClosed = true
                reason = .cancelled
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "windowClosed")
                return true
            }
            if await !onWait(0.02) {
                commit?.requestCancel()
                stats.cancelled = true
                reason = .cancelled
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "cancelledInPauseWait")
                return true
            }
        }
        return false
    }
    // Test hooks: onWait lets a fake clock advance; real shell sleeps.
    // v4: onWait reports whether the wait COMPLETED (true) or was
    // cancelled/interrupted (false) - a swallowed CancellationError can
    // never masquerade as an elapsed wait.
    private let onWait: @Sendable (Double) async -> Bool
    // L1 (ledger integration): optional TimingLedger sink. All
    // appends are off-RT (the pump is an async actor, never the render
    // callback). PTS records are classified observations - no discontinuity
    // PASS and no general monotonic-PTS claim (constraint 2).
    private let ledger: TimingLedger?
    private let ledgerSession: UInt64
    private let ledgerGeneration: UInt64
    /// r3 S5: shared cancel/commit cell. When present, show admissions
    /// serialize through it (cancel-ACK); when absent the pump falls
    /// back to Task.isCancelled checks only (test/simple paths).
    private let commit: CancelCommit?
    /// The presentation revision this pump admits under; resetPresentation
    /// adopts the commit's bumped revision on seek.
    private var presentationRevision: UInt64 = 0
    /// M1 pause/resume (typed state, cancel-safe): while paused the pump
    /// freezes pulls/decisions; a frame already pulled is HELD un-admitted
    /// and re-decided after resume against a fresh arrival anchor.
    private var paused = false
    private var pauseBeganWall: Double? = nil
    /// Total pause entries, independent of successful resume count.
    private var pauseCountTotal = 0
    private var pausedWallTotal = 0.0
    /// M1 window-close observer (additive, default nil = no behavior
    /// change): polled at loop control points; true = the user closed the
    /// window - the run ends as a typed cancel-family terminal with the
    /// windowClosed cause, instead of pumping fenced into an invisible
    /// window until EOS.
    private let closeRequested: (@Sendable () async -> Bool)?
    public init(source: FrameSource, sink: FrameSink, clock: PlaybackClock,
                decider: AVSyncDecider = AVSyncDecider(),
                ledger: TimingLedger? = nil, ledgerSession: UInt64 = 0, ledgerGeneration: UInt64 = 0,
                commit: CancelCommit? = nil,
                closeRequested: (@Sendable () async -> Bool)? = nil,
                onWait: @escaping @Sendable (Double) async -> Bool) {
        self.source = source; self.sink = sink; self.clock = clock
        self.decider = decider; self.onWait = onWait
        self.ledger = ledger; self.ledgerSession = ledgerSession; self.ledgerGeneration = ledgerGeneration
        self.commit = commit
        self.closeRequested = closeRequested
        self.presentationRevision = commit?.revision ?? 0
    }
    private var lastPts = -Double.infinity
    private var lastDuration = 0.0
    // S5 rev6: SEEK ORCHESTRATION. While a queued-source
    // barrier is in flight, pulls/admissions GATED: a pull that returns
    // has unknowable provenance, so it parks on the barrier and is then
    // fenced typed. Overlapping resets are generation-serialized; the
    // older is SUPERSEDED (publishes nothing). Waiters are released
    // once, by the gate owner, after the barrier resolves.
    private var seekBarrierInFlight: Bool = false
    private var seekGeneration: UInt64 = 0
    private var seekWaiters: [CheckedContinuation<Void, Never>] = []
    private func waitForSeekBarrier() async {
        await withCheckedContinuation { cc in seekWaiters.append(cc) }
    }
    private func releaseSeekWaiters() {
        let w = seekWaiters; seekWaiters.removeAll()
        for cc in w { cc.resume() }
    }

    /// Seek integration (K6 r3): the decoder restarts presentation order at
    /// the landing keyframe after a seek, so post-seek frames arrive with
    /// pts BELOW the pump's lastPts. Without a reset they would all be
    /// typed out-of-order drops. The shell must call this when it seeks.
    /// Between run() calls (pause/resume) the order memory persists.
    /// Seek integration. S5 rev3: the typed revision bump is
    /// attempted BEFORE any presentation-order state changes; a typed
    /// refusal (cancelled/exhausted) changes NOTHING, logs ONLY the
    /// refusal, and returns false - the caller must NOT treat it as a
    /// seek ACK and must NOT reset decoder/order state.
    /// S5 rev6: SEEK-COMPLETION ACK. Runs the actual source
    /// queue barrier FIRST; only on a `.flushed` receipt is the revision
    /// bump published (CancelCommit.bumpRevision itself is INVALIDATION
    /// ONLY). A typed barrier failure/refusal is a failed seek: NO bump,
    /// NO order reset, `false` - the caller must NOT treat this as a
    /// seek ACK (fail closed). Overlapping resets are generation-
    /// serialized: the older is SUPERSEDED and publishes nothing.
    /// Pulls/admissions GATED while the barrier is in flight.
    /// SEEK-FAILURE fail-closed (S5 shell integration): refuses every further admission/
    /// upload through the shared authority, effective IMMEDIATELY in the seek completion
    /// control path - after a refused post-commit reset or a poisoned seek, no stale frame
    /// may escape while the caller closes. Idempotent: requestCancel is monotonic.
    public func prohibitResumeAfterSeekFailure() {
        commit?.requestCancel()
    }
    /// seekAnchorSeconds: when set (seek path), the pace anchor is the SHARED
    /// one - media = seek target, wall = the commit moment - so the first
    /// post-seek frame schedules at anchor + (its pts - target): a legitimate
    /// pts gap (keyframe landing past target) is HONORED as a real wait, not
    /// flattened by arrival anchoring. nil (startup/tests) keeps arrival
    /// anchoring.
    @discardableResult
    public func resetPresentation(seekAnchorSeconds: Double? = nil) async -> Bool {
        seekGeneration &+= 1
        let gen = seekGeneration
        if let queued = source as? QueuedFrameSource {
            seekBarrierInFlight = true   // gate ALL pulls/admissions
            let target = (commit?.revision ?? presentationRevision) &+ 1
            let outcome = await queued.coordinateSeek(revision: target)
            guard gen == seekGeneration else {
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .presentationReset,
                               note: "seekSuperseded")
                return false   // the NEWER reset owns the gate and its waiters
            }
            seekBarrierInFlight = false
            if outcome != .flushed {
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .presentationReset,
                               note: "seekBarrierRefused:\(outcome)")
                releaseSeekWaiters()
                return false
            }
        }
        // The revision publish IS the seek-COMPLETION ACK: it lands only
        // after the actual queue barrier (or trivially, for stateless
        // sources, which have no cross-ACK production).
        if let commit {
            do {
                presentationRevision = try commit.bumpRevision()
            } catch {
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .presentationReset,
                               note: "seekRefused:\(error)")
                releaseSeekWaiters()
                return false   // no order reset, no successful-seek record
            }
        } else {
            presentationRevision &+= 1
        }
        lastPts = -Double.infinity
        lastDuration = 0.0
        if let a = seekAnchorSeconds {
            paceAnchorPts = a; paceAnchorWall = clock.nowSeconds()   // SHARED anchor (M4)
        } else {
            paceAnchorPts = nil   // arrival anchor: next frame owns the origin
        }
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .presentationReset)
        releaseSeekWaiters()
        return true
    }

    public func run() async -> PumpStats {
        var stats = PumpStats()
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .videoPumpStart)
        // S3 SINGLE FINALIZATION: every exit lands here exactly ONCE with
        // ONE typed end reason and ONE videoPumpEnd. There is no early
        // return anywhere below (cancelled-in-wait missing its end record
        // was an actual defect - L6 witness W1B).
        var reason: PumpEndReason = .none
        var starveBackoff = 0.002
        pumpLoop: while true {
            // 3g: the SHARED cell cancel is checked by the outer
            // loop too, not only Task cancellation.
            if Task.isCancelled || (commit?.isCancelled ?? false) {
                commit?.requestCancel()
                stats.cancelled = true
                reason = .cancelled
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "cancelled")
                break
            }
            // M1 window-close observer: same cancel-family terminal as a
            // cancel, with the cause typed (stats.windowClosed + ledger
            // note) - never an EOS, never a bare cancel.
            if let closeRequested, await closeRequested() {
                commit?.requestCancel()
                stats.cancelled = true; stats.windowClosed = true
                reason = .cancelled
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "windowClosed")
                break
            }
            guard clock.nowSeconds().isFinite else {
                reason = .failed(-93)
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "clockNonFiniteBeforePull")
                break pumpLoop
            }
            // M1 pause gate (between frames): freeze pulls while paused.
            if paused {
                if await parkWhilePaused(stats: &stats, reason: &reason) { break }
                continue
            }
            // S5 rev5: IMMUTABLE PRODUCER STAMP - the revision
            // is captured BEFORE the pull await, and the frame this pull
            // returns is admitted ONLY under that stamp. A seek ACK
            // landing DURING the pull (or during a later pacing wait for
            // the same frame) makes the stamp stale: the parked old
            // frame mints NO new-revision ticket and lands NO commit -
            // a typed fence, never a live rewind.
            // Cancel recheck AFTER the await, BEFORE any sink admission
            // (S3): a cancel observed here admits nothing further; frames
            // already admitted COUNT (no rollback).
            // S5 rev6: stamp with the LIVE revision at pull
            // start - post-ACK production on a stateless source admits;
            // a stamp that no longer matches post-await means the
            // revision moved DURING the pull (fenced typed below).
            let pullRevision = commit?.revision ?? presentationRevision
            let pulledEvent = await source.nextEvent()
            // S5 rev6: POST-AWAIT PROVENANCE GATE - immediately
            // after the await, BEFORE any EOS/failure/pts-order/drop/wait
            // semantic mutation. (i) A pull returning while a seek
            // barrier is in flight has unknowable provenance: park until
            // the barrier resolves, then fence the event typed and
            // re-pull. (ii) A stamp that no longer matches means the
            // revision moved DURING the pull: fence typed and re-pull.
            if seekBarrierInFlight {
                await waitForSeekBarrier()
                stats.seekStalePulls += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .staleRevisionFenced, note: "barrierPullFence")
                continue
            }
            if pullRevision != (commit?.revision ?? presentationRevision) {
                stats.seekStalePulls += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .staleRevisionFenced, note: "stalePullFence")
                continue
            }
            switch pulledEvent {
            case .temporarilyUnavailable:
                stats.starveWaits += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .frameWait,
                               note: "starveWait_s=\(starveBackoff)")
                if await !onWait(starveBackoff) {
                    commit?.requestCancel()
                    stats.cancelled = true
                    reason = .cancelled
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "cancelledInStarveWait")
                    break pumpLoop
                }
                // 3g: the wait COMPLETED but a shared-cell cancel
                // may have landed during it - without this check the
                // pump starves endlessly after the ACK.
                if commit?.isCancelled ?? false {
                    stats.cancelled = true
                    reason = .cancelled
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "cancelledAfterStarveWait")
                    break pumpLoop
                }
                starveBackoff = min(starveBackoff * 2, 0.05)   // bounded backoff, never an end
                continue
            case .ended(let r):
                // r3 S5: a source-reported cancel sets the typed cancel
                // flag too (r2 defect: stats.cancelled stayed false).
                if r == .cancelled { commit?.requestCancel(); stats.cancelled = true }
                reason = (r == .endOfStream) ? .endOfStream : (r == .cancelled ? .cancelled : .sourceEnded)
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: r.rawValue)
                break pumpLoop
            case .failed(let code):
                reason = .failed(code)
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: reason.rawValue)
                break pumpLoop
            case .frame(let frame):
                starveBackoff = 0.002   // a delivered frame resets starve backoff
                if Task.isCancelled || (commit?.isCancelled ?? false) {
                    // Cancel arrived DURING the pull (task or shared
                    // commit): the frame is NOT admitted (cancel-ACK
                    // serializes admission, S3/S5).
                    commit?.requestCancel()
                    stats.cancelled = true
                    reason = .cancelled
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "cancelledBeforeAdmission")
                    break pumpLoop
                }
            // (item 4) refuse non-finite provider timing at the boundary.
            guard frame.ptsSeconds.isFinite, frame.durationSeconds.isFinite, frame.durationSeconds > 0 else {
                stats.nonFiniteDrops += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .ptsNonFiniteDrop)
                continue
            }
            // (item 1) out-of-order provider pts is a typed drop, not a trap.
            guard frame.ptsSeconds >= lastPts else {
                stats.outOfOrderDrops += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .ptsBackwardDrop, pts: frame.ptsSeconds)
                continue
            }
            // L1 (constraint 2): a forward pts gap is a CLASSIFIED
            // OBSERVATION inside the reported segment. Behavior is unchanged;
            // the gap is recorded, never smoothed, and never claimed as a
            // discontinuity PASS.
            if lastPts > -Double.infinity, lastDuration > 0 {
                let gap = frame.ptsSeconds - (lastPts + lastDuration)
                if gap > lastDuration / 2 {
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .ptsGapForward, pts: frame.ptsSeconds,
                                   note: "gap_s=\(gap)")
                }
            }
            lastPts = frame.ptsSeconds // per-run tracking; resetPresentation() on seek
            lastDuration = frame.durationSeconds
            // (item 3) decision loop: after any wait, re-decide against the
            // CURRENT clock; a frame can become drop-late or still-early
            // while waiting. Bounded by maxWaitSeconds per iteration.
            var guardCount = 0
            while true {
                // M1 pause gate (HELD frame): while paused the pulled frame
                // is NOT decided/admitted; after resume it is re-decided
                // against a fresh arrival anchor. Park iterations never count
                // toward the pathological-clock guard.
                if paused {
                    if await parkWhilePaused(stats: &stats, reason: &reason) { break pumpLoop }
                    if pullRevision != (commit?.revision ?? presentationRevision) || seekBarrierInFlight {
                        stats.seekStalePulls += 1
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .staleRevisionFenced, pts: frame.ptsSeconds,
                                       note: "stalePauseFence")
                        break
                    }
                    continue
                }
                guardCount += 1
                if guardCount > 100 {
                    // Pathological clock: TYPED drop, never a silent one
                    // (r3 S5), and a cancel that arrived during the retry
                    // storm is still honored (r2 defect: ignored here).
                    stats.dropped += 1
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .frameDroppedLate, pts: frame.ptsSeconds,
                                   note: "pathologicalClockRetryLimit")
                    if Task.isCancelled || (commit?.isCancelled ?? false) {
                        commit?.requestCancel()
                        stats.cancelled = true
                        reason = .cancelled
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .terminal, note: "cancelledAtRetryLimit")
                        break pumpLoop
                    }
                    break
                }
                // ONE clock sample per frame decision, used for both the lazy
                // anchor and pacedNow (anchor frame: pacedNow == pts exactly).
                let decisionNow = clock.nowSeconds()
                guard decisionNow.isFinite else {
                    // Clock master loss must fail closed, never flow into
                    // comparisons where NaN would otherwise select SHOW.
                    reason = .failed(-93)
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "clockNonFinite")
                    break pumpLoop
                }
                if paceAnchorPts == nil { paceAnchorPts = frame.ptsSeconds; paceAnchorWall = decisionNow }
                let pacedNow = paceAnchorPts! + (decisionNow - paceAnchorWall)
                switch decider.decide(ptsSeconds: frame.ptsSeconds, nowSeconds: pacedNow, frameDuration: frame.durationSeconds) {
                case .show:
                    // r3 S5: when a shared commit is wired, admission is
                    // ONE CAS on it - a cancel or seek racing this point
                    // can never interleave between check and admit (the
                    // r2 check->await suspension gap). Without a commit,
                    // the Task.isCancelled recheck is the fallback.
                    if let commit {
                        // 3f: propagate Task cancellation to the
                        // cell BEFORE admission (a completed pacing wait
                        // did not propagate it).
                        if Task.isCancelled { commit.requestCancel() }
                        // Admission is ONE CAS returning an immutable
                        // per-frame ticket (rev2); nil = typed refusal.
                        if let ticket = commit.tryAdmit(revision: pullRevision,
                                                        framePTS: frame.ptsSeconds,
                                                        frameDigest: frame.digest) {
                            // The ticket TRAVELS WITH THE FRAME: the sink
                            // validates it on-actor immediately before the
                            // contents commit (ACK = no further commit).
                            let accepted = await sink.show(frame, admission: ticket)
                            if accepted {
                                stats.shown += 1; stats.digestsShown.append(frame.digest)
                                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                               subsystem: .video, kind: .frameShown, pts: frame.ptsSeconds)
                            } else {
                                stats.fencedShows += 1
                            }
                            break
                        } else if commit.isCancelled {
                            stats.cancelled = true
                            reason = .cancelled
                            ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                           subsystem: .video, kind: .terminal, note: "cancelledBeforeShow")
                            break pumpLoop
                        } else {
                            // Stale revision (an external seek raced us)
                            // or a saturated admission count: TYPED fence,
                            // not an admission, not an end.
                            stats.fencedShows += 1
                            ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                           subsystem: .video, kind: .staleRevisionFenced, pts: frame.ptsSeconds,
                                           note: commit.admissionExhausted ? "admissionExhausted" : "staleRevision")
                            break
                        }
                    } else if Task.isCancelled {
                        stats.cancelled = true
                        reason = .cancelled
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .terminal, note: "cancelledBeforeShow")
                        break pumpLoop
                    }
                    // Finding 4: frameShown is logged ONLY on an accepted
                    // show - a fenced upload (window closed) is not "shown".
                    let accepted = await sink.show(frame)
                    if accepted {
                        stats.shown += 1; stats.digestsShown.append(frame.digest)
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .frameShown, pts: frame.ptsSeconds)
                    } else {
                        stats.fencedShows += 1
                    }
                case .drop:
                    stats.dropped += 1
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .frameDroppedLate, pts: frame.ptsSeconds)
                case .wait(let d):
                    stats.waits += 1
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .frameWait, pts: frame.ptsSeconds,
                                   note: "wait_s=\(d)")
                    // v4: a cancelled wait is TYPED - the pump ends
                    // cancelled, it does not re-decide as if time passed.
                    if await !onWait(d) {
                        commit?.requestCancel()
                        stats.cancelled = true
                        reason = .cancelled
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration,
                                       segment: .pump, subsystem: .video, kind: .terminal,
                                       note: "cancelledInWait")
                        break pumpLoop   // S3: single finalization - NO early return (was the W1B defect)
                    }
                    // S5 rev6: a COMPLETED wait re-validates
                    // the pull-stamp BEFORE re-deciding - a seek ACK or
                    // barrier landing during the wait fences the frame
                    // typed instead of re-admitting it under a new ticket.
                    if pullRevision != (commit?.revision ?? presentationRevision) || seekBarrierInFlight {
                        stats.seekStalePulls += 1
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .staleRevisionFenced, pts: frame.ptsSeconds,
                                       note: "staleWaitFence")
                        break
                    }
                    continue // re-decide after a COMPLETED wake
                }
                break
            }
            }
        }
        // THE single finalization: one end reason, one pumpEnd, no
        // after-end events from this pump.
        stats.pauses = pauseCountTotal
        stats.pausedWallSeconds = pausedWallSecondsTotal + (pauseBeganWall.map { Swift.max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0)
        stats.endReason = reason
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .videoPumpEnd,
                       bytes: stats.shown, note: "shown=\(stats.shown) dropped=\(stats.dropped) endReason=\(reason.rawValue)")
        return stats
    }
}
