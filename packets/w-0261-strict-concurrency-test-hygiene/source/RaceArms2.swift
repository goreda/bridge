// RW30-RW33 declarations split from main.swift (compile-window bound:
// the single 1395-line file exceeded one build window; pure move, no semantic change).
import Foundation
import GorAVPlaybackCore

private final class RW30Box {
    private let lock = NSLock()
    var assigned = false, committed = false, ackReturned = false
    func withLock(_ body: (RW30Box) -> Void) { lock.lock(); body(self); lock.unlock() }
    /// Poll under lock until `pred` holds or the deadline passes;
    /// returns true iff `pred` held.
    func poll(_ seconds: Double, _ pred: (RW30Box) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            lock.lock(); let hit = pred(self); lock.unlock()
            if hit || Date() >= deadline { return hit }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
}

func armRW30() {
    // Verdict S5 rev3: the REAL owner-boundary witness - ACK and the
    // contents commit share ONE critical section (commitLock), proven
    // with the in-section test hooks, not a model claim.

    // A. HELD AFTER CONSUME, BEFORE ASSIGN: a cancel ACK racing the
    //    commit section BLOCKS until the assignment lands; after the
    //    ACK returns the frame HAS committed and nothing further can.
    let c1 = CancelCommit()
    let t1 = c1.tryAdmit(revision: 0, framePTS: 1.0, frameDigest: "f1")!
    let holdEntered = DispatchSemaphore(value: 0)
    let releaseHold = DispatchSemaphore(value: 0)
    c1._testAfterConsumeBeforeAssign = { holdEntered.signal(); releaseHold.wait() }
    let boxA = RW30Box()
    let ackAttempted = DispatchSemaphore(value: 0)   // ACK-ATTEMPT handshake
    let commitDone = DispatchSemaphore(value: 0)
    let cancelDone = DispatchSemaphore(value: 0)
    DispatchQueue(label: "rw30.commit").async {
        let ok = c1.commitFrame(t1, framePTS: 1.0, frameDigest: "f1", assign: {
            boxA.withLock { b in
                check(!b.ackReturned, "RW30 after-consume: the ACK never returns before the assignment lands")
                b.assigned = true
            }
        })
        boxA.withLock { b in b.committed = ok }
        commitDone.signal()
    }
    holdEntered.wait()                       // section held: consumed, pre-assign
    DispatchQueue(label: "rw30.cancel").async {
        ackAttempted.signal()                // the ACK attempt is in flight
        c1.requestCancel()                   // MUST block on the held section
        boxA.withLock { b in b.ackReturned = true }
        cancelDone.signal()
    }
    ackAttempted.wait()
    // Bounded witness window (locked state box, no fixed-sleep oracle):
    // an early ACK return is caught immediately; the 2s bound only
    // guards a STUCK witness.
    check(!boxA.poll(2.0) { $0.ackReturned },
          "RW30 cancel ACK blocked while the commit section was held after consume")
    releaseHold.signal()
    commitDone.wait(); cancelDone.wait()
    c1._testAfterConsumeBeforeAssign = nil   // one-shot hold; never leave a hook armed
    boxA.withLock { b in
        check(b.committed && b.assigned, "RW30 the in-section commit completed WITH its assignment")
        check(b.ackReturned && c1.isCancelled, "RW30 the cancel ACK landed after the assignment")
    }
    check(c1.tryAdmit(revision: 0) == nil, "RW30 no admission after the ACK")
    let t1b = c1.tryAdmit(revision: 0) == nil  // (post-cancel typed refusal, again)
    check(t1b, "RW30 post-ACK admission stays refused")

    // B. HELD BEFORE CONSUME, SEEK ACK: same exclusion for the seek
    //    path - the bump returns only after the in-section assignment;
    //    the pre-seek frame committed under its admitted revision, and
    //    only current-revision frames commit after the ACK.
    let c2 = CancelCommit()
    let t2 = c2.tryAdmit(revision: 0, framePTS: 2.0, frameDigest: "f2")!
    let hold2Entered = DispatchSemaphore(value: 0)
    let release2 = DispatchSemaphore(value: 0)
    c2._testBeforeConsume = { hold2Entered.signal(); release2.wait() }
    let boxB = RW30Box()
    let seekAttempted = DispatchSemaphore(value: 0)   // ACK-ATTEMPT handshake
    let commit2Done = DispatchSemaphore(value: 0)
    let seekDone = DispatchSemaphore(value: 0)
    DispatchQueue(label: "rw30.commit2").async {
        let ok = c2.commitFrame(t2, framePTS: 2.0, frameDigest: "f2", assign: {
            boxB.withLock { b in
                check(!b.ackReturned, "RW30 before-consume: the seek ACK never returns before the assignment lands")
                b.assigned = true
            }
        })
        boxB.withLock { b in
            check(ok, "RW30 the held pre-seek commit still commits (it won the section race)")
            b.committed = ok
        }
        commit2Done.signal()
    }
    hold2Entered.wait()
    DispatchQueue(label: "rw30.seek").async {
        seekAttempted.signal()               // the ACK attempt is in flight
        _ = try! c2.bumpRevision()           // MUST block on the held section
        boxB.withLock { b in b.ackReturned = true }
        seekDone.signal()
    }
    seekAttempted.wait()
    check(!boxB.poll(2.0) { $0.ackReturned },
          "RW30 seek ACK blocked while the commit section was held before consume")
    release2.signal()
    commit2Done.wait(); seekDone.wait()
    c2._testBeforeConsume = nil              // one-shot hold; never leave a hook armed
    boxB.withLock { b in
        check(b.assigned && b.ackReturned && c2.revision == 1,
              "RW30 seek ACK landed after the assignment; revision now current")
    }
    let t3 = c2.tryAdmit(revision: 1, framePTS: 3.0, frameDigest: "f3")
    check(t3 != nil, "RW30 current-revision admission after the seek ACK")
    var assigned3 = false
    check(c2.commitFrame(t3!, framePTS: 3.0, frameDigest: "f3", assign: { assigned3 = true }) && assigned3,
          "RW30 post-seek current-revision frame commits")

    // C. FRAME-PROVENANCE BINDING: a ticket authorizes ONLY its exact
    //    frame; a refused attempt does NOT burn the ticket.
    let c3 = CancelCommit()
    let tp = c3.tryAdmit(revision: 0, framePTS: 5.0, frameDigest: "real")!
    check(!c3.commitFrame(tp, framePTS: 9.0, frameDigest: "real", assign: {}),
          "RW30 ticket refuses a DIFFERENT pts (frame binding)")
    let tq = c3.tryAdmit(revision: 0, framePTS: 6.0, frameDigest: "d1")!
    check(!c3.commitFrame(tq, framePTS: 6.0, frameDigest: "d2", assign: {}),
          "RW30 ticket refuses a DIFFERENT digest (frame binding)")
    var assignedP = false
    check(c3.commitFrame(tp, framePTS: 5.0, frameDigest: "real", assign: { assignedP = true }) && assignedP,
          "RW30 a refused attempt did not burn the ticket; the exact frame commits")
    check(!c3.commitFrame(tp, framePTS: 5.0, frameDigest: "real", assign: {}),
          "RW30 the committed ticket cannot replay")

    // D. CROSS-CELL + ISSUER RETENTION: a foreign ticket can never
    //    commit on this authority even at commitFrame level.
    let c4 = CancelCommit()
    let foreign = c3.tryAdmit(revision: 0, framePTS: 7.0, frameDigest: "x")!
    check(!c4.commitFrame(foreign, framePTS: 7.0, frameDigest: "x", assign: {}),
          "RW30 foreign-issuer ticket refused at commitFrame")

    // E. REGISTRY OWNER: a foreign registry's reservation can neither
    //    register nor roll back here; ownership is validated BEFORE
    //    consume.
    let regA = PlaybackRegistry(testSeedNextID: 0)
    let regB = PlaybackRegistry(testSeedNextID: 0)
    guard case .success(let rA) = regA.reserve(.tombstone) else {
        check(false, "RW30 regA reserve refused unexpectedly"); return
    }
    check(regB.register(root: RW27Root(9), token: rA) == nil,
          "RW30 foreign-registry token refused at register (owner checked before consume)")
    check(!regB.rollback(rA), "RW30 foreign-registry token refused at rollback")
    check(regA.rollback(rA), "RW30 the TRUE owner's rollback still completes")
    // Two FRESH same-seeded registries: identical ids on each stay
    // ISOLATED - each registry retains only its own root, and a
    // capability from one is meaningless on the other.
    let regC = PlaybackRegistry(testSeedNextID: 0)
    let regD = PlaybackRegistry(testSeedNextID: 0)
    guard case .success(let rC) = regC.reserve(.tombstone),
          case .success(let rD) = regD.reserve(.tombstone) else {
        check(false, "RW30 regC/regD reserves refused unexpectedly"); return
    }
    let tokC = regC.register(root: RW27Root(1), token: rC)
    let tokD = regD.register(root: RW27Root(2), token: rD)
    check(tokC != nil && tokD != nil && tokC!.id == tokD!.id,
          "RW30 same seeded ids on separate registries stay ISOLATED (no collision class)")
    check(regC.retentionState(of: tokC!).retained && regD.retentionState(of: tokD!).retained,
          "RW30 each registry retains only its own root")
    check(regC.root(of: tokC!) != nil && regD.root(of: tokC!) == nil,
          "RW30 a foreign capability reaches no root (capability is registry-scoped)")
}
/// Verdict S5 rev5 fakes: a pull-parking FrameSource (produces events
/// only on explicit release) and a settable clock for the held-wait arm.
private final class RW31ParkedSource: QueuedFrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SourceEvent, Never>?
    private(set) var pulls = 0
    private(set) var coordinatedRevision: UInt64?
    private let oldPTS: Double
    init(oldPTS: Double) { self.oldPTS = oldPTS }
    func nextEvent() async -> SourceEvent {
        await withCheckedContinuation { cc in
            lock.lock(); pulls += 1; continuation = cc; lock.unlock()
        }
    }
    func waitForPulls(_ n: Int, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock(); let p = pulls; lock.unlock()
            if p >= n { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
    /// Release the parked pull with a frame PRODUCED UNDER THE OLD
    /// revision (a pre-seek decode).
    func releaseOldFrame() {
        lock.lock(); let cc = continuation; continuation = nil; lock.unlock()
        cc?.resume(returning: .frame(SourceFrame(ptsSeconds: oldPTS, durationSeconds: 0.04, digest: "old")))
    }
    func releaseEOS() {
        lock.lock(); let cc = continuation; continuation = nil; lock.unlock()
        cc?.resume(returning: .ended(.endOfStream))
    }
    func coordinateSeek(revision: UInt64) async -> SeekBarrierOutcome {
        lock.lock(); coordinatedRevision = revision; lock.unlock()
        return .flushed
    }
}
private final class RW31Clock: PlaybackClock, @unchecked Sendable {
    private let lock = NSLock(); private var now = 0.0
    func nowSeconds() -> Double { lock.lock(); defer { lock.unlock() }; return now }
    func set(_ v: Double) { lock.lock(); now = v; lock.unlock() }
}

func armRW31() {
    // Verdict S5 rev5: IMMUTABLE PRODUCER STAMP witnesses - an old frame
    // whose PULL or pacing WAIT crossed a seek ACK mints NO new-revision
    // ticket and lands NO commit (typed fence, never a live rewind).

    // A. HELD PULL + RESET/ACK + RELEASE OLD: the pull parked BEFORE the
    //    ACK (stamp = old revision); the released old frame is fenced.
    let commitA = CancelCommit()
    let srcA = RW31ParkedSource(oldPTS: 0.0)
    let sinkA = RW25Sink()
    let pumpA = FramePump(source: srcA, sink: sinkA, clock: RW25Clock(), commit: commitA, onWait: { _ in true })
    let runDoneA = DispatchSemaphore(value: 0)
    var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); runDoneA.signal() }
    check(srcA.waitForPulls(1, timeout: 2.0), "RW31/A pull parked before the seek")
    var ackA = false
    let ackDoneA = DispatchSemaphore(value: 0)
    Task { ackA = await pumpA.resetPresentation(); ackDoneA.signal() }
    ackDoneA.wait()
    check(ackA, "RW31/A seek ACK succeeded (typed revision bump)")
    check(srcA.coordinatedRevision == 1, "RW31/A coordinated source seek fired with the NEW revision")
    srcA.releaseOldFrame()                       // pre-seek frame released AFTER the ACK
    check(srcA.waitForPulls(2, timeout: 2.0), "RW31/A pump parked on the next pull after the fence")
    srcA.releaseEOS()
    runDoneA.wait()
    let stA = statsA!
    check(stA.shown == 0 && sinkA.shown == 0, "RW31/A held-pull old frame landed NO commit")
    check(commitA.admitted == 0, "RW31/A held-pull old frame minted NO new-revision ticket")
    check(stA.seekStalePulls == 1 && stA.fencedShows == 0,
          "RW31/A the old frame was fenced TYPED at the post-await provenance gate")
    check(stA.endReason == .endOfStream, "RW31/A the fence is not an end; EOS reached")

    // B. HELD WAIT + RESET/ACK + RELEASE OLD: the frame was delivered
    //    pre-ACK and parked in the pacing wait; the completed post-ACK
    //    wait re-decides to .show - admission still uses the stale
    //    pull-stamp and is fenced typed. The commit is bumped DIRECTLY
    //    here: the parked onWait blocks the pump executor by design, so
    //    an actor-hopping resetPresentation could not interleave; the
    //    stamp check lives on the commit, not on the actor.
    let commitB = CancelCommit()
    let srcB = RW31ParkedSource(oldPTS: 0.1)   // delta > duration/2 forces .wait
    let sinkB = RW25Sink()
    let clockB = RW31Clock()
    let waitEntered = DispatchSemaphore(value: 0)
    let releaseWait = DispatchSemaphore(value: 0)
    let waitCalls = AtomicU64()!
    let pumpB = FramePump(source: srcB, sink: sinkB, clock: clockB, commit: commitB, onWait: { _ in
        if waitCalls.fetchAdd(1) == 0 { waitEntered.signal(); releaseWait.wait() }
        return true   // every wait COMPLETED
    })
    let runDoneB = DispatchSemaphore(value: 0)
    var statsB: PumpStats? = nil
    Task { _ = await pumpB.resetPresentation(seekAnchorSeconds: 0.0); statsB = await pumpB.run(); runDoneB.signal() }
    check(srcB.waitForPulls(1, timeout: 2.0), "RW31/B pull parked before frame release")
    srcB.releaseOldFrame()                       // pre-seek frame delivered pre-ACK
    check(waitEntered.wait(timeout: .now() + 2.0) == .success, "RW31/B frame parked in the pacing wait")
    do { _ = try commitB.bumpRevision() } catch { check(false, "RW31/B unexpected seek refusal") }
    clockB.set(0.1)                              // the re-decide sees the frame due NOW (inside the show window)
    releaseWait.signal()                         // the held wait completes AFTER the ACK
    check(srcB.waitForPulls(2, timeout: 2.0), "RW31/B pump parked on the next pull after the fence")
    srcB.releaseEOS()
    runDoneB.wait()
    let stB = statsB!
    check(stB.shown == 0 && sinkB.shown == 0, "RW31/B held-wait old frame landed NO commit")
    check(commitB.admitted == 0, "RW31/B held-wait old frame minted NO new-revision ticket")
    check(stB.seekStalePulls == 1 && stB.fencedShows == 0,
          "RW31/B the completed post-ACK wait was fenced TYPED at the after-wait provenance check")
    check(stB.endReason == .endOfStream, "RW31/B the fence is not an end; EOS reached")
}


// === Verdict S5 rev6: REAL TRANSPORT WITNESSES for the typed seek barrier ===
private final class RW32QueuedSource: QueuedFrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [SourceFrame]
    private(set) var barrierCalls: [UInt64] = []
    var barrierOutcome: SeekBarrierOutcome = .flushed
    private var parkBarrierNext = false
    private var barrierCC: CheckedContinuation<Void, Never>?
    private(set) var barrierParked = false
    private var pullCC: CheckedContinuation<SourceEvent, Never>?
    private(set) var pulls = 0
    init(queued: [SourceFrame]) { queue = queued }
    func parkNextBarrier() { lock.lock(); parkBarrierNext = true; lock.unlock() }
    func queueCount() -> Int { lock.lock(); defer { lock.unlock() }; return queue.count }
    func nextEvent() async -> SourceEvent {   // every pull parks; the arm releases each
        await withCheckedContinuation { cc in
            lock.lock(); pulls += 1; pullCC = cc; lock.unlock()
        }
    }
    func waitForPulls(_ n: Int, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock(); let p = pulls; lock.unlock()
            if p >= n { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
    func waitForBarrierParked(_ timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock(); let b = barrierParked; lock.unlock()
            if b { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
    func releasePull(_ ev: SourceEvent) {
        lock.lock(); let cc = pullCC; pullCC = nil; lock.unlock()
        cc?.resume(returning: ev)
    }
    func releaseBarrier() {
        lock.lock(); let cc = barrierCC; barrierCC = nil; barrierParked = false; lock.unlock()
        cc?.resume()
    }
    func coordinateSeek(revision: UInt64) async -> SeekBarrierOutcome {
        var parked = false
        lock.lock()
        barrierCalls.append(revision)
        if parkBarrierNext { parkBarrierNext = false; parked = true; barrierParked = true }
        lock.unlock()
        if parked {
            await withCheckedContinuation { cc in
                lock.lock(); barrierCC = cc; lock.unlock()
            }
        }
        let outcome = barrierOutcome
        // On a REAL flush receipt, the pre-seek queued frames are ACTUALLY
        // dropped - this is the decoder-queue obligation the receipt attests.
        if outcome == .flushed { lock.lock(); queue.removeAll(); lock.unlock() }
        return outcome
    }
}
private func rw32frame(_ pts: Double, _ digest: String) -> SourceFrame {
    SourceFrame(ptsSeconds: pts, durationSeconds: 0.04, digest: digest)
}

func armRW32() {
    // Verdict S5 rev6: the typed seek barrier is a REAL transport receipt,
    // not a documented contract - witnesses exercise flush/failure/
    // unsupported/overlap/gate on an actual queued source.

    // A. FLUSH: the barrier ACTUALLY drops pre-seek queued frames; only
    //    the revision bump published AFTER the receipt admits new frames.
    let commitA = CancelCommit()
    let srcA = RW32QueuedSource(queued: [rw32frame(0.0, "old-0"), rw32frame(0.04, "old-1")])
    let sinkA = RW25Sink()
    let pumpA = FramePump(source: srcA, sink: sinkA, clock: RW25Clock(), commit: commitA, onWait: { _ in true })
    var ackA = false
    let ackDoneA = DispatchSemaphore(value: 0)
    Task { ackA = await pumpA.resetPresentation(); ackDoneA.signal() }
    ackDoneA.wait()
    check(ackA, "RW32/A seek ACK after actual flush receipt")
    check(srcA.barrierCalls == [1], "RW32/A barrier ran with the TARGET revision before the bump")
    check(srcA.queueCount() == 0, "RW32/A the flush receipt ACTUALLY dropped the pre-seek queue")
    check(commitA.revision == 1, "RW32/A the bump published only after the receipt")
    let runDoneA = DispatchSemaphore(value: 0)
    var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); runDoneA.signal() }
    check(srcA.waitForPulls(1, timeout: 2.0), "RW32/A first pull parked")
    srcA.releasePull(.frame(rw32frame(0.0, "new-0")))   // post-seek production (due NOW at clock 0)
    check(srcA.waitForPulls(2, timeout: 2.0), "RW32/A second pull parked")
    srcA.releasePull(.ended(.endOfStream))
    runDoneA.wait()
    let stA = statsA!
    check(stA.shown == 1 && stA.digestsShown == ["new-0"],
          "RW32/A post-barrier pulls carry only NEW production - no old digest can surface")

    // B. TYPED FAILURE: a failed barrier is a failed seek - NO bump, NO
    //    order reset; pre-seek state is preserved and still admits under
    //    the UNCHANGED revision.
    let commitB = CancelCommit()
    let srcB = RW32QueuedSource(queued: [rw32frame(0.0, "old-0")])
    srcB.barrierOutcome = .failed("io error")
    let sinkB = RW25Sink()
    let pumpB = FramePump(source: srcB, sink: sinkB, clock: RW25Clock(), commit: commitB, onWait: { _ in true })
    var ackB = true
    let ackDoneB = DispatchSemaphore(value: 0)
    Task { ackB = await pumpB.resetPresentation(); ackDoneB.signal() }
    ackDoneB.wait()
    check(!ackB, "RW32/B typed barrier failure is a typed seek refusal (false)")
    check(commitB.revision == 0, "RW32/B NO revision bump on a failed barrier")
    check(srcB.queueCount() == 1, "RW32/B failed barrier did not drop source state")
    let runDoneB = DispatchSemaphore(value: 0)
    var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); runDoneB.signal() }
    check(srcB.waitForPulls(1, timeout: 2.0), "RW32/B first pull parked")
    srcB.releasePull(.frame(rw32frame(0.0, "old-0")))
    check(srcB.waitForPulls(2, timeout: 2.0), "RW32/B second pull parked")
    srcB.releasePull(.ended(.endOfStream))
    runDoneB.wait()
    check(statsB!.shown == 1 && statsB!.digestsShown == ["old-0"],
          "RW32/B refused seek: pre-seek production still admits under the unchanged revision")

    // C. UNSUPPORTED: fail closed - typed refusal, no mutation.
    let commitC = CancelCommit()
    let srcC = RW32QueuedSource(queued: [])
    srcC.barrierOutcome = .unsupported
    let pumpC = FramePump(source: srcC, sink: RW25Sink(), clock: RW25Clock(), commit: commitC, onWait: { _ in true })
    var ackC = true
    let ackDoneC = DispatchSemaphore(value: 0)
    Task { ackC = await pumpC.resetPresentation(); ackDoneC.signal() }
    ackDoneC.wait()
    check(!ackC && commitC.revision == 0, "RW32/C .unsupported fails closed: typed refusal, no bump")

    // D. OVERLAP: a NEWER reset supersedes the in-flight older one -
    //    exactly ONE bump lands; the superseded reset publishes nothing.
    let commitD = CancelCommit()
    let srcD = RW32QueuedSource(queued: [])
    srcD.parkNextBarrier()
    let pumpD = FramePump(source: srcD, sink: RW25Sink(), clock: RW25Clock(), commit: commitD, onWait: { _ in true })
    var ackD1 = true, ackD2 = false
    let doneD1 = DispatchSemaphore(value: 0), doneD2 = DispatchSemaphore(value: 0)
    Task { ackD1 = await pumpD.resetPresentation(); doneD1.signal() }
    check(srcD.waitForBarrierParked(2.0), "RW32/D older reset parked in the barrier")
    Task { ackD2 = await pumpD.resetPresentation(); doneD2.signal() }
    doneD2.wait()   // the NEWER reset's barrier was not parked: it completes
    check(ackD2, "RW32/D the newer reset wins and ACKs")
    srcD.releaseBarrier()
    doneD1.wait()
    check(!ackD1, "RW32/D the superseded older reset publishes nothing (typed false)")
    check(commitD.revision == 1, "RW32/D exactly one bump across overlapping resets")
    check(srcD.barrierCalls.count == 2, "RW32/D both resets ran the barrier")

    // E. GATE: while the barrier is in flight, a returning pull PARKS -
    //    no admission, no show, no state mutation; after the receipt the
    //    crossed pull is fenced typed.
    let commitE = CancelCommit()
    let srcE = RW32QueuedSource(queued: [])
    srcE.parkNextBarrier()
    let sinkE = RW25Sink()
    let pumpE = FramePump(source: srcE, sink: sinkE, clock: RW25Clock(), commit: commitE, onWait: { _ in true })
    let runDoneE = DispatchSemaphore(value: 0)
    var statsE: PumpStats? = nil
    Task { statsE = await pumpE.run(); runDoneE.signal() }
    check(srcE.waitForPulls(1, timeout: 2.0), "RW32/E first pull parked")
    var ackE = false
    let ackDoneE = DispatchSemaphore(value: 0)
    Task { ackE = await pumpE.resetPresentation(); ackDoneE.signal() }
    check(srcE.waitForBarrierParked(2.0), "RW32/E barrier in flight")
    srcE.releasePull(.frame(rw32frame(0.0, "crossed")))   // pull returns MID-BARRIER
    Thread.sleep(forTimeInterval: 0.15)                    // give the pump a chance to misbehave
    check(commitE.admitted == 0 && sinkE.shown == 0,
          "RW32/E the crossed pull is GATED: zero admissions, zero shows while the barrier is in flight")
    srcE.releaseBarrier()
    ackDoneE.wait()
    check(ackE && commitE.revision == 1, "RW32/E ACK lands only after the actual receipt")
    check(srcE.waitForPulls(2, timeout: 2.0), "RW32/E pump re-pulled after the fence")
    srcE.releasePull(.ended(.endOfStream))
    runDoneE.wait()
    let stE = statsE!
    check(stE.seekStalePulls == 1 && stE.shown == 0 && stE.endReason == .endOfStream,
          "RW32/E the crossed pull was fenced TYPED after the barrier, then EOS")
}

func armRW33() {
    // Verdict S5 rev6 REENTRY GUARD: public entries made ON THE SECTION
    // THREAD from inside the commit closure are TYPED refusals, never a
    // non-recursive-lock deadlock; the outer commit still lands.
    let commit = CancelCommit()
    guard let ticket = commit.tryAdmit(revision: 0, framePTS: 0.0, frameDigest: "x") else {
        check(false, "RW33 initial admission failed"); return
    }
    var bumpRefused = false, finishRefused = false, nestedRefused = false
    let ok = commit.commitFrame(ticket, framePTS: 0.0, frameDigest: "x") {
        commit.requestCancel()                                   // typed refusal, no-op
        do { _ = try commit.bumpRevision() } catch let e as CancelCommit.SeekRefusal { bumpRefused = (e == .reentrant) } catch { }
        finishRefused = !commit._testMayFinishConsume(ticket: ticket)
        if let t2 = commit.tryAdmit(revision: 0, framePTS: 1.0, frameDigest: "y") {
            nestedRefused = !commit.commitFrame(t2, framePTS: 1.0, frameDigest: "y") {}
        }
    }
    check(ok, "RW33 the outer commit still landed (no deadlock)")
    check(bumpRefused && finishRefused && nestedRefused,
          "RW33 reentrant bump/mayFinish/commitFrame are TYPED refusals")
    check(commit.reentrantRefusalCount == 4, "RW33 every reentrant call counted (cancel+bump+mayFinish+commit)")
    check(commit.revision == 0, "RW33 reentrant cancel/bump changed nothing")
    check(commit.tryAdmit(revision: 0, framePTS: 2.0, frameDigest: "z") != nil,
          "RW33 the cell is still live after the section (cancel was refused)")
}


/// RW34 (r3 S6 IdempotentEventSource adversarial coverage): the terminal
/// idempotence wrapper had no arm. A scripted inner source emits a
/// terminal followed by post-terminal junk (late frame, second terminal,
/// starve, failure); the wrapper must deliver the FIRST terminal exactly
/// once, replay it idempotently forever, never pull the inner source
/// again once latched, and keep violations observable.
private final class RW34ScriptedSource: FrameSource, @unchecked Sendable {
    var events: [SourceEvent]; var pulls = 0
    init(_ events: [SourceEvent]) { self.events = events }
    func nextEvent() async -> SourceEvent {
        let e = pulls < events.count ? events[pulls] : .ended(.sourceEnded)
        pulls += 1; return e
    }
}
func armRW34() {
    let sess = SourceSession(session: 7, revision: 3)
    // A. EOS terminal, then junk.
    let inner = RW34ScriptedSource([
        .frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 1.0/30.0, digest: "rw34-f0")),
        .ended(.endOfStream),
        .frame(SourceFrame(ptsSeconds: 0.1, durationSeconds: 1.0/30.0, digest: "rw34-late")),
        .ended(.sourceEnded), .temporarilyUnavailable, .failed(9),
    ])
    let src = IdempotentEventSource(inner, binding: sess)
    var pulled: [SourceEvent] = []
    let sem = DispatchSemaphore(value: 0)
    Task { for _ in 0..<7 { pulled.append(await src.nextEvent()) }; sem.signal() }
    sem.wait()
    guard pulled.count == 7 else { check(false, "RW34/A pulled 7 events"); return }
    if case .frame(let f) = pulled[0] {
        check(f.digest == "rw34-f0", "RW34/A pre-terminal frame passes through")
    } else { check(false, "RW34/A pre-terminal frame passes through") }
    var allEOS = true
    for e in pulled[1...] { guard case .ended(.endOfStream) = e else { allEOS = false; break } }
    check(allEOS, "RW34/A first terminal delivered once, then replayed idempotently (late frame/second terminal/starve/failure never surface)")
    check(inner.pulls == 2, "RW34/A inner source never pulled again once latched (revival fence)", "pulls=\(inner.pulls)")
    check(src.binding == sess, "RW34/A session binding preserved")
    check(src.violationCount == 0 && src.lastViolation == nil, "RW34/A no violation before any pump-side report")
    src.recordViolation(.eventAfterTerminal)
    check(src.violationCount == 1 && src.lastViolation == .eventAfterTerminal, "RW34/A violation hook observable (count + last kind)")
    let barrierSem = DispatchSemaphore(value: 0); var barrier: SeekBarrierOutcome? = nil
    Task { barrier = await src.coordinateSeek(revision: 4); barrierSem.signal() }
    barrierSem.wait()
    check(barrier == .flushed, "RW34/A stateless source barrier is the typed .flushed receipt")

    // B. failure terminal latches identically.
    let innerB = RW34ScriptedSource([.failed(7), .ended(.endOfStream)])
    let srcB = IdempotentEventSource(innerB, binding: sess)
    var pulledB: [SourceEvent] = []
    let semB = DispatchSemaphore(value: 0)
    Task { for _ in 0..<3 { pulledB.append(await srcB.nextEvent()) }; semB.signal() }
    semB.wait()
    var allFailed = true
    for e in pulledB { guard case .failed(let c) = e, c == 7 else { allFailed = false; break } }
    check(allFailed, "RW34/B typed failure terminal latched and replayed (later EOS never leaks)")
    check(innerB.pulls == 1, "RW34/B inner never pulled after failure latch", "pulls=\(innerB.pulls)")

    // C. pump-level: exactly ONE typed finalization over a wrapped source.
    let innerC = RW34ScriptedSource([
        .frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 1.0/30.0, digest: "rw34-p0")),
        .ended(.endOfStream),
        .frame(SourceFrame(ptsSeconds: 0.2, durationSeconds: 1.0/30.0, digest: "rw34-ghost")),
        .ended(.sourceEnded),
    ])
    let pumpC = FramePump(source: IdempotentEventSource(innerC, binding: sess),
                          sink: RW25Sink(), clock: RW25Clock(), onWait: { _ in true })
    let semC = DispatchSemaphore(value: 0); var statsC: PumpStats? = nil
    Task { statsC = await pumpC.run(); semC.signal() }
    semC.wait()
    let stC = statsC!
    check(stC.shown == 1 && stC.digestsShown == ["rw34-p0"], "RW34/C only the pre-terminal frame shows; the ghost frame never lands")
    check(stC.endReason == .endOfStream && !stC.cancelled, "RW34/C exactly one typed EOS finalization")
}

/// RW35 (K6 decisionNow regression): ONE clock sample per frame decision
/// feeds BOTH the lazy pace anchor and pacedNow. A per-read jumping clock
/// makes a double sample explode into a spurious drop; the single-sample
/// anchor frame must show on arrival, and the next frame must pace its
/// pts delta off the anchor.
private final class RW35JumpClock: PlaybackClock, @unchecked Sendable {
    var reads = 0; let t0: Double; let step: Double
    init(t0: Double, step: Double) { self.t0 = t0; self.step = step }
    func nowSeconds() -> Double { let v = t0 + Double(reads) * step; reads += 1; return v }
}
private final class RW35WaitBox: @unchecked Sendable {
    private let lock = NSLock(); private var values: [Double] = []
    func add(_ d: Double) { lock.lock(); values.append(d); lock.unlock() }
    func snapshot() -> [Double] { lock.lock(); defer { lock.unlock() }; return values }
}
func armRW35() {
    let dur = 1.0 / 30.0
    // A. ANCHOR FRAME UNDER A PER-READ JUMP CLOCK: single-sample =>
    //    pacedNow == pts exactly => .show. A second sample inside the
    //    same decision would place pacedNow 500s ahead => .drop.
    let clockA = RW35JumpClock(t0: 1000.0, step: 500.0)
    let srcA = RW34ScriptedSource([
        .frame(SourceFrame(ptsSeconds: 42.0, durationSeconds: dur, digest: "rw35-anchor")),
        .ended(.endOfStream),
    ])
    let waitsA = RW35WaitBox()
    let pumpA = FramePump(source: srcA, sink: RW25Sink(), clock: clockA, onWait: { d in waitsA.add(d); return true })
    let semA = DispatchSemaphore(value: 0); var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); semA.signal() }
    semA.wait()
    let stA = statsA!
    check(stA.shown == 1 && stA.dropped == 0, "RW35/A anchor frame shows on arrival under a per-read jump clock (single decisionNow sample)")
    check(stA.digestsShown == ["rw35-anchor"], "RW35/A the shown frame is the anchor frame")
    check(waitsA.snapshot().allSatisfy { $0 < 0.25 }, "RW35/A no spurious long wait minted by a double clock sample", "waits=\(waitsA.snapshot())")
    check(stA.endReason == .endOfStream, "RW35/A clean EOS after the anchor frame")

    // B. PACED NEXT FRAME OFF THE ANCHOR: gentle clock advance; the
    //    second frame waits its pts delta off the anchor, then shows.
    final class ScriptClock: PlaybackClock, @unchecked Sendable { var t = 0.0; func nowSeconds() -> Double { t } }
    let clockB = ScriptClock()
    let srcB = RW34ScriptedSource([
        .frame(SourceFrame(ptsSeconds: 10.0, durationSeconds: dur, digest: "rw35-f0")),
        .frame(SourceFrame(ptsSeconds: 10.0 + dur, durationSeconds: dur, digest: "rw35-f1")),
        .ended(.endOfStream),
    ])
    let waitsB = RW35WaitBox()
    let pumpB = FramePump(source: srcB, sink: RW25Sink(), clock: clockB, onWait: { d in
        waitsB.add(d); clockB.t += d; return true   // the wait COMPLETED; the clock advanced by it
    })
    let semB = DispatchSemaphore(value: 0); var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); semB.signal() }
    semB.wait()
    let stB = statsB!
    check(stB.shown == 2 && stB.digestsShown == ["rw35-f0", "rw35-f1"], "RW35/B both frames show in pts order")
    let wb = waitsB.snapshot()
    check(wb.count == 1, "RW35/B exactly one pacing wait (anchor frame shows on arrival)", "waits=\(wb)")
    if let w = wb.first {
        check(abs(w - dur) < 0.005, "RW35/B the wait is the pts delta off the anchor, never a wall-absolute", "wait=\(w)")
    } else { check(false, "RW35/B the wait is the pts delta off the anchor, never a wall-absolute") }

    // C. negative control: pure decider thresholds (anchor-frame math).
    let dec = AVSyncDecider()
    check(dec.decide(ptsSeconds: 100.0, nowSeconds: 100.0, frameDuration: dur) == .show,
          "RW35/C decider: exactly-on-pts shows (the anchor-frame case)")
    check(dec.decide(ptsSeconds: 99.9, nowSeconds: 100.0, frameDuration: dur) == .drop,
          "RW35/C decider: half-frame-late drops (the double-sample failure mode)")
    if case .wait(let w) = dec.decide(ptsSeconds: 100.0 + dur, nowSeconds: 100.0, frameDuration: dur) {
        check(abs(w - dur) < 1e-9, "RW35/C decider: early frame waits its delta")
    } else { check(false, "RW35/C decider: early frame waits its delta") }
}
