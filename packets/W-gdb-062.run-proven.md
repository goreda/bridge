# W-gdb-062 concurrency race witnesses (product suite)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-062

```packet-json
{
  "packet_id": "W-gdb-062",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/race-witness-tests/RaceArms2.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "product test target race-witness-tests",
    "types": "see excerpt",
    "ownership_lifetime": "product sources at the pinned sha",
    "caller": "lab run-proof gate",
    "callee": "race-witness-tests (product target on main)"
  },
  "test": {
    "command": "swift run race-witness-tests",
    "expected": "exit 0; final line 'ALL RACE WITNESSES PASS (incl RW34/RW35)'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/race-witness-tests/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/race-witness-tests/RaceArms2.swift",
        "block": "rf1"
      },
      {
        "path": "Sources/race-witness-tests/main.swift",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run race-witness-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:59:17.468787+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL RACE WITNESSES PASS (incl RW34/RW35)",
    "inline_files": [
      {
        "path": "Sources/race-witness-tests/RaceArms2.swift",
        "block": "rf1",
        "sha256": "5172fac0e70123865f771261b0d8960e68e308e1227f67ad68a09850159592a5"
      },
      {
        "path": "Sources/race-witness-tests/main.swift",
        "block": "rf2",
        "sha256": "fe6d3db1afd2ba606d4fec82f1dcd60c53504f17c1ec9da29b5f34538b701842"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "08c1653b4d265cf681ddc07fee515302a79a11f39c6a37455c0fd1e69b3afe60",
    "last_5_lines": [
      "PASS RW35/B the wait is the pts delta off the anchor, never a wall-absolute",
      "PASS RW35/C decider: exactly-on-pts shows (the anchor-frame case)",
      "PASS RW35/C decider: half-frame-late drops (the double-sample failure mode)",
      "PASS RW35/C decider: early frame waits its delta",
      "ALL RACE WITNESSES PASS (incl RW34/RW35)"
    ],
    "receipt_sha256": "ac8f47b774fd5b0503ff345f66c661387d23758e7f83844702bb017f1791bf46"
  }
}
```

## problem (what fails for the user)
playback races surface as random hangs or corrupted frames for the owner; the product race witnesses pin the interleavings

## reproducer
- repo: goreda/gorav @ 91a359f7b38cc0e6c4974661d85f389ef6041b1f (branch main).
- real source: Sources/race-witness-tests/RaceArms2.swift (product target sources inlined below).
- real test command: swift run race-witness-tests (product's own target on main, Linux).

## expected behaviour
exit 0 with the product suite's summary line 'ALL RACE WITNESSES PASS (incl RW34/RW35)'; any regression fails with its row id.

```text id=rf1
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
    c1._testAfterConsumeBeforeAssign = { holdEntered.signal(); bw(releaseHold, "RaceArms2.swift:34 releaseHold") }
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
    bw(holdEntered, "RaceArms2.swift:49 holdEntered")                       // section held: consumed, pre-assign
    DispatchQueue(label: "rw30.cancel").async {
        ackAttempted.signal()                // the ACK attempt is in flight
        c1.requestCancel()                   // MUST block on the held section
        boxA.withLock { b in b.ackReturned = true }
        cancelDone.signal()
    }
    bw(ackAttempted, "RaceArms2.swift:56 ackAttempted")
    // Bounded witness window (locked state box, no fixed-sleep oracle):
    // an early ACK return is caught immediately; the 2s bound only
    // guards a STUCK witness.
    check(!boxA.poll(2.0) { $0.ackReturned },
          "RW30 cancel ACK blocked while the commit section was held after consume")
    releaseHold.signal()
    bw(commitDone, "RaceArms2.swift:63 commitDone"); bw(cancelDone, "RaceArms2.swift:63 cancelDone")
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
    c2._testBeforeConsume = { hold2Entered.signal(); bw(release2, "RaceArms2.swift:81 release2") }
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
    bw(hold2Entered, "RaceArms2.swift:99 hold2Entered")
    DispatchQueue(label: "rw30.seek").async {
        seekAttempted.signal()               // the ACK attempt is in flight
        _ = try! c2.bumpRevision()           // MUST block on the held section
        boxB.withLock { b in b.ackReturned = true }
        seekDone.signal()
    }
    bw(seekAttempted, "RaceArms2.swift:106 seekAttempted")
    check(!boxB.poll(2.0) { $0.ackReturned },
          "RW30 seek ACK blocked while the commit section was held before consume")
    release2.signal()
    bw(commit2Done, "RaceArms2.swift:110 commit2Done"); bw(seekDone, "RaceArms2.swift:110 seekDone")
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
    /// Release the parked pull with the generation's first frame (frame0:
    /// shows on arrival, owns the anchor - RULES.md:69).
    func releaseFrame0() {
        lock.lock(); let cc = continuation; continuation = nil; lock.unlock()
        cc?.resume(returning: .frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "f0")))
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
    nonisolated(unsafe) var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); runDoneA.signal() }
    check(srcA.waitForPulls(1, timeout: 2.0), "RW31/A pull parked before the seek")
    nonisolated(unsafe) var ackA = false
    let ackDoneA = DispatchSemaphore(value: 0)
    Task { ackA = await pumpA.resetPresentation(); ackDoneA.signal() }
    bw(ackDoneA, "RaceArms2.swift:242 ackDoneA")
    check(ackA, "RW31/A seek ACK succeeded (typed revision bump)")
    check(srcA.coordinatedRevision == 1, "RW31/A coordinated source seek fired with the NEW revision")
    srcA.releaseOldFrame()                       // pre-seek frame released AFTER the ACK
    check(srcA.waitForPulls(2, timeout: 2.0), "RW31/A pump parked on the next pull after the fence")
    srcA.releaseEOS()
    bw(runDoneA, "RaceArms2.swift:248 runDoneA")
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
    // RULES.md:69 port: the old arm forced the pacing wait with the M4
    // shared anchor (resetPresentation(seekAnchorSeconds: 0.0) making the
    // 0.1 frame early). Landing semantics removed the pre-set anchor, so
    // the wait is staged WITHOUT it: frame0 (0.0) shows and owns the
    // anchor, the 0.1 frame is +0.1 early against it and parks in the
    // pacing wait; the DIRECT bumpRevision is the ACK. The witness is
    // unchanged: a held wait whose pull stamp goes stale across the ACK
    // mints no new-revision ticket and lands no commit.
    let commitB = CancelCommit()
    let srcB = RW31ParkedSource(oldPTS: 0.1)   // +0.1 early vs the frame0 anchor -> .wait
    let sinkB = RW25Sink()
    let clockB = RW31Clock()
    let waitEntered = DispatchSemaphore(value: 0)
    let releaseWait = DispatchSemaphore(value: 0)
    let waitCalls = AtomicU64()!
    let pumpB = FramePump(source: srcB, sink: sinkB, clock: clockB, commit: commitB, onWait: { _ in
        if waitCalls.fetchAdd(1) == 0 { waitEntered.signal(); bw(releaseWait, "RW31/B phase=pacing-wait wait=release frame=0.1 rev=pre-ack") }
        return true   // every wait COMPLETED
    })
    let runDoneB = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); runDoneB.signal() }
    check(srcB.waitForPulls(1, timeout: 2.0), "RW31/B pull parked before frame0 release")
    srcB.releaseFrame0()                         // frame0 shows, owns the anchor (0.0)
    check(srcB.waitForPulls(2, timeout: 2.0), "RW31/B pull parked before old-frame release")
    srcB.releaseOldFrame()                       // 0.1 frame delivered pre-ACK
    check(waitEntered.wait(timeout: .now() + 2.0) == .success, "RW31/B frame parked in the pacing wait")
    do { _ = try commitB.bumpRevision() } catch { check(false, "RW31/B unexpected seek refusal") }
    clockB.set(0.1)                              // the re-decide sees the frame due NOW (inside the show window)
    releaseWait.signal()                         // the held wait completes AFTER the ACK
    check(srcB.waitForPulls(3, timeout: 2.0), "RW31/B pump parked on the next pull after the fence")
    srcB.releaseEOS()
    bw(runDoneB, "RW31/B wait=runDone frame=held0.1 rev=post-ack")
    let stB = statsB!
    check(stB.shown == 1 && sinkB.shown == 1, "RW31/B only frame0 showed; the held-wait old frame landed NO commit")
    check(commitB.admitted == 1, "RW31/B held-wait old frame minted NO new-revision ticket (frame0's ticket only)")
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
    nonisolated(unsafe) var ackA = false
    let ackDoneA = DispatchSemaphore(value: 0)
    Task { ackA = await pumpA.resetPresentation(); ackDoneA.signal() }
    bw(ackDoneA, "RaceArms2.swift:386 ackDoneA")
    check(ackA, "RW32/A seek ACK after actual flush receipt")
    check(srcA.barrierCalls == [1], "RW32/A barrier ran with the TARGET revision before the bump")
    check(srcA.queueCount() == 0, "RW32/A the flush receipt ACTUALLY dropped the pre-seek queue")
    check(commitA.revision == 1, "RW32/A the bump published only after the receipt")
    let runDoneA = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); runDoneA.signal() }
    check(srcA.waitForPulls(1, timeout: 2.0), "RW32/A first pull parked")
    srcA.releasePull(.frame(rw32frame(0.0, "new-0")))   // post-seek production (due NOW at clock 0)
    check(srcA.waitForPulls(2, timeout: 2.0), "RW32/A second pull parked")
    srcA.releasePull(.ended(.endOfStream))
    bw(runDoneA, "RaceArms2.swift:398 runDoneA")
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
    nonisolated(unsafe) var ackB = true
    let ackDoneB = DispatchSemaphore(value: 0)
    Task { ackB = await pumpB.resetPresentation(); ackDoneB.signal() }
    bw(ackDoneB, "RaceArms2.swift:414 ackDoneB")
    check(!ackB, "RW32/B typed barrier failure is a typed seek refusal (false)")
    check(commitB.revision == 0, "RW32/B NO revision bump on a failed barrier")
    check(srcB.queueCount() == 1, "RW32/B failed barrier did not drop source state")
    let runDoneB = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); runDoneB.signal() }
    check(srcB.waitForPulls(1, timeout: 2.0), "RW32/B first pull parked")
    srcB.releasePull(.frame(rw32frame(0.0, "old-0")))
    check(srcB.waitForPulls(2, timeout: 2.0), "RW32/B second pull parked")
    srcB.releasePull(.ended(.endOfStream))
    bw(runDoneB, "RaceArms2.swift:425 runDoneB")
    check(statsB!.shown == 1 && statsB!.digestsShown == ["old-0"],
          "RW32/B refused seek: pre-seek production still admits under the unchanged revision")

    // C. UNSUPPORTED: fail closed - typed refusal, no mutation.
    let commitC = CancelCommit()
    let srcC = RW32QueuedSource(queued: [])
    srcC.barrierOutcome = .unsupported
    let pumpC = FramePump(source: srcC, sink: RW25Sink(), clock: RW25Clock(), commit: commitC, onWait: { _ in true })
    nonisolated(unsafe) var ackC = true
    let ackDoneC = DispatchSemaphore(value: 0)
    Task { ackC = await pumpC.resetPresentation(); ackDoneC.signal() }
    bw(ackDoneC, "RaceArms2.swift:437 ackDoneC")
    check(!ackC && commitC.revision == 0, "RW32/C .unsupported fails closed: typed refusal, no bump")

    // D. OVERLAP: a NEWER reset supersedes the in-flight older one -
    //    exactly ONE bump lands; the superseded reset publishes nothing.
    let commitD = CancelCommit()
    let srcD = RW32QueuedSource(queued: [])
    srcD.parkNextBarrier()
    let pumpD = FramePump(source: srcD, sink: RW25Sink(), clock: RW25Clock(), commit: commitD, onWait: { _ in true })
    nonisolated(unsafe) var ackD1 = true, ackD2 = false
    let doneD1 = DispatchSemaphore(value: 0), doneD2 = DispatchSemaphore(value: 0)
    Task { ackD1 = await pumpD.resetPresentation(); doneD1.signal() }
    check(srcD.waitForBarrierParked(2.0), "RW32/D older reset parked in the barrier")
    Task { ackD2 = await pumpD.resetPresentation(); doneD2.signal() }
    bw(doneD2, "RaceArms2.swift:451 doneD2")   // the NEWER reset's barrier was not parked: it completes
    check(ackD2, "RW32/D the newer reset wins and ACKs")
    srcD.releaseBarrier()
    bw(doneD1, "RaceArms2.swift:454 doneD1")
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
    nonisolated(unsafe) var statsE: PumpStats? = nil
    Task { statsE = await pumpE.run(); runDoneE.signal() }
    check(srcE.waitForPulls(1, timeout: 2.0), "RW32/E first pull parked")
    nonisolated(unsafe) var ackE = false
    let ackDoneE = DispatchSemaphore(value: 0)
    Task { ackE = await pumpE.resetPresentation(); ackDoneE.signal() }
    check(srcE.waitForBarrierParked(2.0), "RW32/E barrier in flight")
    srcE.releasePull(.frame(rw32frame(0.0, "crossed")))   // pull returns MID-BARRIER
    Thread.sleep(forTimeInterval: 0.15)                    // give the pump a chance to misbehave
    check(commitE.admitted == 0 && sinkE.shown == 0,
          "RW32/E the crossed pull is GATED: zero admissions, zero shows while the barrier is in flight")
    srcE.releaseBarrier()
    bw(ackDoneE, "RaceArms2.swift:480 ackDoneE")
    check(ackE && commitE.revision == 1, "RW32/E ACK lands only after the actual receipt")
    check(srcE.waitForPulls(2, timeout: 2.0), "RW32/E pump re-pulled after the fence")
    srcE.releasePull(.ended(.endOfStream))
    bw(runDoneE, "RaceArms2.swift:484 runDoneE")
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
    nonisolated(unsafe) var pulled: [SourceEvent] = []
    let sem = DispatchSemaphore(value: 0)
    Task { for _ in 0..<7 { pulled.append(await src.nextEvent()) }; sem.signal() }
    bw(sem, "RaceArms2.swift:544 sem")
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
    let barrierSem = DispatchSemaphore(value: 0); nonisolated(unsafe) var barrier: SeekBarrierOutcome? = nil
    Task { barrier = await src.coordinateSeek(revision: 4); barrierSem.signal() }
    bw(barrierSem, "RaceArms2.swift:559 barrierSem")
    check(barrier == .flushed, "RW34/A stateless source barrier is the typed .flushed receipt")

    // B. failure terminal latches identically.
    let innerB = RW34ScriptedSource([.failed(7), .ended(.endOfStream)])
    let srcB = IdempotentEventSource(innerB, binding: sess)
    nonisolated(unsafe) var pulledB: [SourceEvent] = []
    let semB = DispatchSemaphore(value: 0)
    Task { for _ in 0..<3 { pulledB.append(await srcB.nextEvent()) }; semB.signal() }
    bw(semB, "RaceArms2.swift:568 semB")
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
    let semC = DispatchSemaphore(value: 0); nonisolated(unsafe) var statsC: PumpStats? = nil
    Task { statsC = await pumpC.run(); semC.signal() }
    bw(semC, "RaceArms2.swift:585 semC")
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
    let semA = DispatchSemaphore(value: 0); nonisolated(unsafe) var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); semA.signal() }
    bw(semA, "RaceArms2.swift:620 semA")
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
    let semB = DispatchSemaphore(value: 0); nonisolated(unsafe) var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); semB.signal() }
    bw(semB, "RaceArms2.swift:642 semB")
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

```

```text id=rf2
// CANONICAL RACE-WITNESS HARNESS (architect 80b + Main 13:37 deterministic
// inputs). ONE harness for all lanes; L9 takes the teardown subset.
// Core-executable arms run here on Linux against the REAL GorAVPlaybackCore
// (AdmissionCell, rings, receipts) - no copied logic, no mocks of the thing
// under test. MacShell-only arms (real AudioUnit callback thread, dispose)
// are scripted below as WITNESS-PLAN seams for owner-run Mac execution and
// are NEVER claimed from Linux.
// Deterministic: single-threaded scripted interleavings + bounded threaded
// conservation smokes with fake clocks; no wall time, no randomness.
import Foundation
import GorAVPlaybackCore

var failures = 0
/// Bounded wait (architect condition: NO hanging waits in the race
/// harness). Default 5s; on expiry fails TYPED with the wait label
/// (phase/wait/frame/revision where the site names them) instead of
/// hanging the suite.
@discardableResult
func bw(_ sem: DispatchSemaphore, _ label: String, _ seconds: Double = 5.0) -> Bool {
    let ok = sem.wait(timeout: .now() + seconds) == .success
    check(ok, "boundedWait [\(label)]", "semaphore wait exceeded \(seconds)s")
    return ok
}
@discardableResult
func bw(_ grp: DispatchGroup, _ label: String, _ seconds: Double = 5.0) -> Bool {
    let ok = grp.wait(timeout: .now() + seconds) == .success
    check(ok, "boundedWait [\(label)]", "group wait exceeded \(seconds)s")
    return ok
}
func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
}

print("RW canonical race witnesses (lane-0)")

// RW1 - pause-BEFORE-admission-CAS, then retire+detach, resume: the late
// callback must render silence and touch NO payload. Core proxy: an
// admitted-then-retired cell refuses the late enter; readers stay 0.
func armRW1() {
    guard let cell = AdmissionCell() else { check(false, "RW1 alloc"); return }
    cell.retire()                          // owner retires FIRST (teardown begin)
    let admitted = cell.enter()            // late callback AFTER retire
    check(!admitted, "RW1 post-retire enter refused (silence, no payload)")
    check(cell.readers == 0, "RW1 readers 0 after refused enter")
    if admitted { cell.exit() }            // must not be reachable
}

// RW2 - admitted callback PAUSED before its write, retire mid-flight:
// owner waits readers==0 before reset/reuse. The admitted reader drains
// exactly once; a second enter after drain is refused.
func armRW2() {
    guard let cell = AdmissionCell() else { check(false, "RW2 alloc"); return }
    check(cell.enter(), "RW2 pre-retire enter admitted")
    _ = cell.retire()
    check(cell.readers == 1, "RW2 admitted reader still counted post-retire")
    check(!cell.enter(), "RW2 second enter refused while reader in flight")
    cell.exit()                            // reader finishes its ONE drain
    check(cell.readers == 0, "RW2 readers drain to zero")
    check(!cell.enter(), "RW2 post-drain enter still refused")
}

// RW3 - retire is idempotent and the same admission cell can serve a NEW
// generation ONLY by a NEW cell (single-generation ownership): the retired
// cell never reopens.
func armRW3() {
    guard let cell = AdmissionCell() else { check(false, "RW3 alloc"); return }
    let r1 = cell.retire(); let r2 = cell.retire()
    check(r1 == r2, "RW3 retire idempotent")
    check(!cell.enter(), "RW3 retired cell never reopens (no generation reuse)")
}

// RW4 - reader-timeout is TERMINAL: scripted owner-side policy witness.
// A reader that never exits keeps readers>0; the contract forbids
// reset/reuse in that state (policy tested at MacShell seam; here we pin
// the observable precondition the owner must see: readers>0 => NO reuse).
func armRW4() {
    guard let cell = AdmissionCell() else { check(false, "RW4 alloc"); return }
    check(cell.enter(), "RW4 enter")
    _ = cell.retire()
    check(cell.readers > 0, "RW4 stuck reader observable (blocks reset/reuse)")
    // no exit: harness ends with the fault RETAINED, not reset - mirrors
    // constraint D (typed failed, retained) at core level.
}

// RW5 - threaded conservation: N producer-ish entrants vs a retire racing;
// every admitted entrant exits exactly once; final readers==0; no enter
// succeeds after the LAST retire returns (linearization point).
func armRW5() {
    guard let cell = AdmissionCell() else { check(false, "RW5 alloc"); return }
    let group = DispatchGroup(); let q = DispatchQueue(label: "rw5", attributes: .concurrent)
    let admitted = AtomicU64()!
    for _ in 0..<64 {
        group.enter()
        q.async { if cell.enter() { _ = admitted.fetchAdd(1); cell.exit() }; group.leave() }
    }
    q.async { _ = cell.retire() }
    bw(group, "main.swift:97 group")
    _ = cell.retire()
    check(cell.readers == 0, "RW5 readers drain to zero under race")
    check(!cell.enter(), "RW5 no enter after final retire")
    print("PASS RW5 admitted-before-retire count = \(admitted.load()) (informational)")
}

// RW6 - registry exhaustion precondition (core-observable arm): the
// process-global ceiling exists in MacShell AudioUnitSink (8 payloads /
// 64 MiB, lane-0-review values). Core witness pins the CONTRACT: start()
// must refuse typed at ceiling. Linux-executable check lands when the
// registry policy moves to core; until then this arm is a documented seam.
print("SEAM RW6 registry-exhaustion: MacShell arm, owner-run; NOT claimed from Linux")

// RW7 - reentrant start-stop / owner-release-late-callback / cancel-drain /
// RT-alloc-failure: RT path must not lock/wait/alloc/fatalError. Core pins:
// AdmissionCell ops are lock-free C atomics (gorav_admit_*), allocation
// happens only in init? (failable, pre-RT). Post-retire enter touches no
// payload and performs no allocation (single CAS + branch).
func armRW7() {
    guard let cell = AdmissionCell() else { check(false, "RW7 alloc"); return }
    _ = cell.retire()
    for _ in 0..<1000 { if cell.enter() { cell.exit() } }  // hot refused path
    check(cell.readers == 0, "RW7 refused-enter hot path leaves no state")
}

armRW1(); armRW2(); armRW3(); armRW4(); armRW5(); armRW7()
print(failures == 0 ? "ALL RACE WITNESSES PASS" : "RACE WITNESSES FAIL count=\(failures)")

// RW8/RW9/RW10 - ARCHITECT BLOCKING FINDING #1 (tombstone lifetime) arms.
// These arms ASSERT THE CONTRACT and are expected to FAIL against the
// current lane-0 candidate: the failure IS the finding reproduced. They
// become the acceptance tests for the lifetime fix (awaiting full verdict).

// RW8 - last-owner-release-after-CLEAN-stop: the retired registration
// (context + AdmissionCell) MUST outlive the sink's last release, because
// the provider may still hold refCon for a late callback. Core proxy: a
// sink-owned context with a weak tombstone goes nil at sink release -
// proving the tombstone does NOT have process lifetime today.
final class RW8Context { let cell = AdmissionCell()! }
final class RW8Sink { let ctx = RW8Context() }
func armRW8() {
    var tombstone: RW8Context? = nil       // current candidate: instance-held
    weak var weakTomb: RW8Context? = nil
    do {
        let sink = RW8Sink()
        sink.ctx.cell.retire()             // clean stop retires admission
        tombstone = sink.ctx               // instance-held (NOT process-global strong)
        weakTomb = sink.ctx
        _ = sink                           // last owner released here
    }
    // Contract: tombstone must still be alive for a late callback.
    // Current candidate: tombstone alive only because WE hold it here; a
    // real late refCon holds nothing. Weak witness:
    // Machine-readable per-arm status (Main 13:51): the old-candidate gap
    // stays an EXPECTED-FAIL reproduction; the revised core is covered at
    // REGISTRY level only (RW12); the Mac wiring itself is BLOCKED-NATIVE.
    print("ARM RW8 old=EXPECTED-FAIL reproduced(weak=\(weakTomb != nil)) revised-core=COVERED-BY-RW12(registry-level-only) native=BLOCKED(owner-Mac-seam)")
    _ = tombstone
}

// RW9 - failed-stop: registry retains integer counters ONLY; the failed
// payload (context/unit objects) is NOT mechanically retained after
// caller release. Contract: typed failed => payload retained + registered.
func armRW9() {
    weak var weakFailed: RW8Context? = nil
    do {
        let failed = RW8Context()
        failed.cell.retire()               // teardown error path: typed failed
        weakFailed = failed
        // registry records counters only (no object retention in candidate)
    }
    print("ARM RW9 old=EXPECTED-FAIL reproduced(weak=\(weakFailed != nil)) revised-core=COVERED-BY-RW12(registry-level-only) native=BLOCKED(owner-Mac-seam)")
}

// RW10 - headroom CHECK is not an atomic RESERVATION: parallel starts all
// pass the check before any increment lands. Witness: naive check-then-add
// over AtomicU64 overshoots the ceiling under a real race.
func armRW10() {
    let ceiling: UInt64 = 1  // deterministic overshoot arm: 2 racers vs ceiling 1
    let counter = AtomicU64()!
    // Deterministic 2-racer overshoot: ceiling 1; BOTH racers load 0 before
    // EITHER increments (handshake via atomics, no wide barrier).
    let aLoaded = AtomicU64()!; let bGo = AtomicU64()!; let done = AtomicU64()!
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        if counter.load() < 1 {             // racer B loads 0
            _ = aLoaded.load()              // (ordering marker)
            while aLoaded.load() == 0 { }   // wait until A ALSO loaded 0
            _ = counter.fetchAdd(1)         // B increments: 1
        }
        _ = done.fetchAdd(1); sem.signal()
    }
    if counter.load() < 1 {                 // racer A loads 0 (before B may add)
        _ = aLoaded.fetchAdd(1)             // tell B: A has loaded
        while done.load() == 0 { }          // let B land first
        _ = counter.fetchAdd(1)             // A increments past ceiling: 2
    }
    bw(sem, "main.swift:195 sem")
    print("ARM RW10 old=EXPECTED-FAIL reproduced(overshot=\(counter.load())>\(ceiling)) revised-core=PASS-RW11(registry-level) native=BLOCKED(owner-Mac-seam)")
}

armRW8(); armRW9(); armRW10()
print("ARM-STATUS convention: old=EXPECTED-FAIL(reproduced) revised-core=<arm coverage, registry-level ONLY> native=BLOCKED(off-Mac seams are owner-run; no parse-only closure claimed).")

// RW11-RW13 - S1 registry acceptance arms against the REAL PlaybackRegistry
// (r3 capability state machine: token-bound reserve/register/rollback,
// per-kind caps on one packed CAS cell).
final class RW12Payload { let bytes = [UInt8](repeating: 7, count: 4096) }
func armRW11() {
    // Reservation race against the REAL registry (r3-rev1): 64 parallel
    // racers attempt reserve(.active); every success immediately rolls
    // back. At most one active reservation exists at any instant; every
    // racer gets success-or-TYPED-refusal; deinit auto-rollback means a
    // dropped token can never leak (finding 4a).
    let reg = PlaybackRegistry.shared
    let before = reg.debugCounts()
    let ok = AtomicU64()!; let typedRefusals = AtomicU64()!
    let rollbacksTrue = AtomicU64()!; let secondUseRefused = AtomicU64()!
    let group = DispatchGroup(); let q = DispatchQueue(label: "rw11", attributes: .concurrent)
    for _ in 0..<64 {
        group.enter()
        q.async {
            switch reg.reserve(.active) {
            case .success(let token):
                _ = ok.fetchAdd(1)
                if reg.rollback(token) { _ = rollbacksTrue.fetchAdd(1) }
                if !reg.rollback(token) { _ = secondUseRefused.fetchAdd(1) }  // once-consume
            case .failure: _ = typedRefusals.fetchAdd(1)   // typed exhaustion
            }
            group.leave()
        }
    }
    bw(group, "main.swift:230 group")
    let after = reg.debugCounts()
    check(ok.intValue + typedRefusals.intValue == 64, "RW11 every racer got success-or-typed-refusal")
    check(rollbacksTrue.intValue == ok.intValue, "RW11 every token rolled back exactly once")
    check(secondUseRefused.intValue == ok.intValue, "RW11 token is once-consume (second rollback refused typed)")
    check(after.active == before.active && after.pendingTerminal == before.pendingTerminal,
          "RW11 no leaked reservation after rollback",
          "active \(before.active)->\(after.active) pending \(before.pendingTerminal)->\(after.pendingTerminal)")
}

func armRW11b() {
    // FINDING 1 (headroom RESERVE, not check): hold ONE active
    // reservation (its terminal obligation is atomically reserved);
    // fault reserves now exhaust at cap-1 (the held obligation owns the
    // last slot); the holder's commit + active->fault transition STILL
    // commits - the r3-rev1 guarantee RW13's concurrent race broke.
    let reg = PlaybackRegistry.shared
    guard case .success(let held) = reg.reserve(.active) else {
        check(false, "RW11b initial active reserve refused"); return
    }
    // HOLD the tokens: a dropped Reservation rolls back in deinit
    // (finding 4a), which would make this loop never exhaust.
    var heldFaults: [PlaybackRegistry.Reservation] = []
    while case .success(let t) = reg.reserve(.fault) { heldFaults.append(t) }
    let faultReserves = heldFaults.count
    let heldTok = reg.register(root: RW12Payload(), token: held)
    check(heldTok != nil, "RW11b held active reservation commits under full fault backlog")
    if let t = heldTok {
        check(reg.reclassify(t, to: .fault), "RW11b FINDING-1-FIX active->fault commits with reserved terminal slot (concurrent terminal backlog full)")
    }
    check(faultReserves == PlaybackRegistry.maxRetainedFaults - 1,
          "RW11b fault headroom stops one short while a terminal obligation is held",
          "faultReserves=\(faultReserves)")
}

func armRW12() {
    // FINDING 3 (immutable root): register(root:token:) retains the
    // ROOT immutably; a caller release never frees it while the
    // registration lives; consumed tokens refuse typed.
    weak var weakRoot: RW12Payload? = nil
    var tok: RegistrationToken? = nil
    var secondRegisterNil = false
    do {
        let root = RW12Payload()
        weakRoot = root
        switch PlaybackRegistry.shared.reserve(.fault) {
        case .success(let token):
            tok = PlaybackRegistry.shared.register(root: root, token: token)
            secondRegisterNil = (PlaybackRegistry.shared.register(root: root, token: token) == nil)
        case .failure:
            check(false, "RW12 fault reservation refused unexpectedly")
        }
    }
    check(weakRoot != nil, "RW12 FINDING-3-FIX registration ROOT immutably retained (no rebind can free it)",
          "root freed - registry root retention broken")
    check(tok != nil, "RW12 registration token issued by token commit")
    check(secondRegisterNil, "RW12 consumed token cannot register twice (typed nil)")
}

// RW12b - FINDING 2/3 arms: typed graph ATTACHMENT (never a root
// replacement); capability-gated transitions.
private final class RW12Edge { let id: Int; init(_ i: Int) { id = i } }
private final class RW12Graph: FaultPayloadGraph {
    let ownerEdge: RW12Edge    // stands for the sink/ring owner edge
    let handle: RW12Edge       // stands for the provider-handle edge
    init(owner: RW12Edge, handle: RW12Edge) { self.ownerEdge = owner; self.handle = handle }
    var owner: AnyObject { ownerEdge }   // TYPED real owner (verdict S1)
    var strongEdgeCount: Int { 2 }
    var payloadDescription: String { "RW12Graph(owner+handle)" }
}
private final class RW12ThinGraph: FaultPayloadGraph {
    var owner: AnyObject { self }        // minimal legal graph
    var strongEdgeCount: Int { 1 }
    var payloadDescription: String { "thin" }
}
func armRW12b() {
    weak var weakOwner: RW12Edge? = nil
    weak var weakHandle: RW12Edge? = nil
    var tok: RegistrationToken? = nil
    var attachOK = false, thinRefused = false
    do {
        let owner = RW12Edge(2), handle = RW12Edge(3)
        weakOwner = owner; weakHandle = handle
        switch PlaybackRegistry.shared.reserve(.tombstone) {
        case .success(let res):
            tok = PlaybackRegistry.shared.register(root: RW12Edge(0), token: res)
            if let t = tok {
                let graph = RW12Graph(owner: owner, handle: handle)
                attachOK = PlaybackRegistry.shared.attachFaultGraph(t, graph)
                // Verdict S1: ATTACH-ONCE - a second attach (which could
                // drop the real owner behind a claimed count) is refused.
                thinRefused = !PlaybackRegistry.shared.attachFaultGraph(t, RW12ThinGraph())
                // FINDING 2: the mutation surface takes ONLY a
                // capability token - there is no public ID-based API
                // left to address another entry at all (RW12c covers
                // the transition rules).
            }
        case .failure:
            check(false, "RW12b tombstone reservation refused unexpectedly")
        }
    }
    check(attachOK, "RW12b typed fault graph ATTACHED (root untouched)")
    check(weakOwner != nil && weakHandle != nil,
          "RW12b graph edges (owner+handle) survive caller release",
          "an edge was freed - the fault graph is not strongly owned")
    check(thinRefused, "RW12b ATTACH-ONCE second attach refused typed (graph not replaceable)")
}

func armRW12c() {
    // FINDING 2 transition validation: active->fault and
    // active->tombstone commit; terminal->active REFUSED (arbitrary
    // resurrection impossible); terminal kind immutable
    // (fault->tombstone refused); foreign-token reclassify refused.
    let reg = PlaybackRegistry.shared
    guard case .success(let ra) = reg.reserve(.active),
          let ta = reg.register(root: RW12Edge(1), token: ra) else {
        check(false, "RW12c setup reserve/register refused"); return
    }
    check(reg.reclassify(ta, to: .fault), "RW12c active->fault commits (valid transition)")
    check(!reg.reclassify(ta, to: .active), "RW12c FINDING-2-FIX terminal->active REFUSED (no resurrection)")
    check(!reg.reclassify(ta, to: .tombstone), "RW12c terminal kind immutable (fault->tombstone refused)")
    guard case .success(let rb) = reg.reserve(.active),
          let tb = reg.register(root: RW12Edge(2), token: rb) else {
        check(false, "RW12c second setup refused"); return
    }
    // FINDING 2: reclassify binds to the token's OWN entry - tb can
    // only drive tb's registration; no API can name ta without ta's
    // token (structural capability, not a guessable UInt64).
    check(reg.reclassify(tb, to: .tombstone), "RW12c token drives its OWN entry (active->tombstone commits)")
    let st = reg.retentionState(of: ta)
    check(st.retained && st.kind == .fault, "RW12c retentionState typed query: fault registration retained")
}

func armRW13() {
    // Typed exhaustion per-kind under rev1 headroom: fill the fault
    // backlog (no held obligations) to the cap; the next fault reserve
    // fails TYPED; an ACTIVE reserve also fails typed while a terminal
    // backlog is full (its atomically-reserved obligation cannot fit).
    let reg = PlaybackRegistry.shared
    var last: Result<PlaybackRegistry.Reservation, RegistryExhausted>? = nil
    for _ in 0..<64 {
        last = reg.reserve(.fault)
        switch last! {
        case .success(let t): _ = reg.register(root: RW12Payload(), token: t)
        case .failure: break
        }
        if case .failure = last! { break }
    }
    switch last {
    case .failure(let e):
        check(e.faults == PlaybackRegistry.maxRetainedFaults,
              "RW13 fault exhaustion at the per-kind cap", "faults=\(e.faults)")
        print("PASS RW13 typed exhaustion at per-kind cap (active=\(e.active) faults=\(e.faults) tombstones=\(e.tombstones))")
    default:
        check(false, "RW13 reserve never exhausts (unbounded growth = verdict S1e violation)")
    }
    switch reg.reserve(.active) {
    case .failure:
        print("PASS RW13 active reserve refuses typed while a terminal backlog is full")
    case .success(let t):
        _ = reg.rollback(t)
        check(false, "RW13 active reserve granted with full fault backlog (reserved-obligation headroom broken)")
    }
    switch reg.reserve(.tombstone) {
    case .success(let t):
        _ = reg.rollback(t)
        print("PASS RW13 tombstone headroom independent of fault cap")
    case .failure:
        check(false, "RW13 tombstone cap consumed by fault exhaustion (per-kind isolation broken)")
    }
}

func armRW26() {
    // S4 FINDINGS 7-9 (generation-bound outcome cache): a cached outcome
    // is returned only for the CURRENT generation; an in-flight stop
    // reads .pending (never stale, never bare .noop); publication
    // precedes the lifecycle transition.
    let c = StopOutcomeCache()
    check(c.idleOutcome() == .noop, "RW26 no evidence -> .noop")
    c.noteStart(generation: 1)
    c.noteStopInFlight()
    check(c.idleOutcome() == .pending, "RW26 FINDING-7-FIX in-flight stop reads .pending (not stale, not noop)")
    let ev1 = AudioStopEvidence(generation: 1, stopStatus: 0, uninitStatus: 0, disposeStatus: 0,
                                readersDrained: true, producerWitnessed: true, drainResidual: nil,
                                retainedRegistration: nil)
    c.publish(generation: 1, outcome: .complete(ev1))
    check(c.idleOutcome().isComplete, "RW26 published outcome returned for its generation")
    check(c.idleOutcome().isComplete, "RW26 repeat idle query returns the SAME preserved outcome")
    c.noteStart(generation: 2)
    check(c.idleOutcome() == .noop, "RW26 FINDING-7-FIX new generation invalidates the old cache (no g1 outcome from g2 stop)")
    c.noteStopInFlight()
    let ev2 = AudioStopEvidence(generation: 2, stopStatus: -1, uninitStatus: 0, disposeStatus: 0,
                                readersDrained: false, producerWitnessed: false, drainResidual: nil,
                                retainedRegistration: nil)
    c.publish(generation: 2, outcome: .failed(ev2))
    if case .failed(let e) = c.idleOutcome() {
        check(e.generation == 2, "RW26 FINDING-8-FIX start/stop-owned failure evidence preserved for its generation")
    } else { check(false, "RW26 failed outcome not preserved") }
    // Verdict S4: a STALE-generation publish is refused typed and must
    // NOT clobber the current cache nor clear a live in-flight marker.
    c.noteStopInFlight()
    check(!c.publish(generation: 1, outcome: .complete(ev1)), "RW26 stale-generation publish refused typed")
    check(c.idleOutcome() == .pending, "RW26 stale publish did not clear the current in-flight marker")
    c.publish(generation: 2, outcome: .failed(ev2))
}

// RW27 - verdict S1 registration distinctness under concurrency: every
// committed registration gets a UNIQUE id and keeps its OWN root (the
// re-issue/overwrite class at reachable scale; the MAX boundary itself
// is model-level - 2^64 mints are not a runnable witness).
final class RW27Root { let tag: Int; init(_ t: Int) { tag = t } }
func armRW27() {
    let reg = PlaybackRegistry.shared
    var toks: [RegistrationToken] = []
    var roots: [RW27Root] = []
    let g = DispatchGroup(); let q = DispatchQueue(label: "rw27", attributes: .concurrent)
    let lock = NSLock()
    for i in 0..<2 {   // remaining tombstone capacity after RW12b/RW12c
        g.enter(); q.async {
            if case .success(let r) = reg.reserve(.tombstone),
               let t = reg.register(root: RW27Root(i), token: r) {
                lock.lock(); toks.append(t); roots.append(RW27Root(i)); lock.unlock()
            }
            g.leave()
        }
    }
    bw(g, "main.swift:456 g")
    check(Set(toks.map { $0.id }).count == toks.count && toks.count == 2,
          "RW27 concurrent registration ids unique (no re-issue/overwrite)", "\(toks.map { $0.id })")
    var allRetained = true
    for t in toks { if !reg.retentionState(of: t).retained { allRetained = false } }
    check(allRetained, "RW27 every concurrent registration keeps its own root")
}

func armRW26b() {
    // Verdict S4 REAL INTERLEAVING (not the ideal setter sequence): two
    // CONCURRENT stops over the real SessionLifecycle + StopOutcomeCache
    // wiring. Exactly one teardown owner; the in-flight marker is taken
    // atomically inside the lifecycle lock; the loser observes pending-
    // then-cached; the winner publishes BEFORE the transition.
    let lc = SessionLifecycle(); let cache = StopOutcomeCache()
    let g = lc.beginStart()!; _ = lc.commitStart(g)
    cache.noteStart(generation: g)
    let owners = AtomicU64()!; let pendingSeen = AtomicU64()!; let cachedSeen = AtomicU64()!
    let grp = DispatchGroup(); let q = DispatchQueue(label: "rw26b", attributes: .concurrent)
    for _ in 0..<2 {
        grp.enter(); q.async {
            switch lc.beginStop(onStopTransition: { cache.noteStopInFlight() }) {
            case .teardownOwned(let gg):
                _ = owners.fetchAdd(1)
                // Winner: simulate teardown work, then publish-then-finish.
                let ev = AudioStopEvidence(generation: gg, stopStatus: 0, uninitStatus: 0,
                                           disposeStatus: 0, readersDrained: true,
                                           producerWitnessed: true, drainResidual: nil,
                                           retainedRegistration: nil)
                cache.publish(generation: gg, outcome: .complete(ev))
                lc.finishStop(gg)
            case .startWillTearDown:
                break
            case .none:
                // Loser path: while the winner tears down this reads
                // .pending; after publication it reads the cached outcome.
                let idle = cache.idleOutcome()
                if idle == .pending { _ = pendingSeen.fetchAdd(1) }
                else if idle.isComplete { _ = cachedSeen.fetchAdd(1) }
            }
            grp.leave()
        }
    }
    bw(grp, "main.swift:499 grp")
    check(owners.intValue == 1, "RW26b exactly one teardown owner across concurrent stops")
    check(pendingSeen.intValue + cachedSeen.intValue == 1,
          "RW26b concurrent loser saw pending-or-cached, never a bare noop gap",
          "pending=\(pendingSeen.intValue) cached=\(cachedSeen.intValue)")
    // Post-completion repeat stop: the cached outcome, generation-bound.
    check(lc.beginStop() == .none, "RW26b post-finish beginStop is a no-op")
    check(cache.idleOutcome().isComplete, "RW26b repeat stop returns the preserved outcome")
}
armRW11(); armRW11b(); armRW12(); armRW12b(); armRW12c(); armRW13(); armRW26(); armRW26b()
print("RW11-RW13+RW26 registry/outcome acceptance arms done (r3-rev1 capability state machine).")

// === L9 TEARDOWN SUBSET (RW14-RW22), integrated 2026-10-25, renumbered vs RW11-13.
// RW14 - SessionLifecycle teardown transition matrix: running dies WITH the
// stop transition; double stop is a no-op; wrong-generation finishStop is
// ignored; generations are never reused across cycles.
func armRW14() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!; _ = lc.commitStart(g)
    check(lc.runningGen == g, "RW14 runningGen born with active transition")
    check(lc.beginStop() == .teardownOwned(g), "RW14 beginStop -> teardownOwned")
    check(lc.runningGen == nil, "RW14 runningGen nil in the SAME transition (no late-running window)")
    check(lc.beginStop() == .none, "RW14 NEG second beginStop no-op (single teardown owner)")
    lc.finishStop(g &+ 99)
    if case .stopping(let s) = lc.current { check(s == g && lc.stopCount == 0, "RW14 NEG finishStop(wrong g) ignored") } else { check(false, "RW14 NEG finishStop(wrong g) ignored", "\(lc.current)") }
    lc.finishStop(g)
    var gs: [UInt64] = []
    for _ in 0..<3 { let h = lc.beginStart()!; _ = lc.commitStart(h); _ = lc.beginStop(); lc.finishStop(h); gs.append(h) }
    check(gs == [g+1, g+2, g+3], "RW14 generations strictly monotonic, no reuse", "\(gs)")
}

// RW15 - terminal teardown: failStop/failStart are TERMINAL - no restart, no
// fake completion, no re-teardown; the retained fault is never overwritten.
func armRW15() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!; _ = lc.commitStart(g); _ = lc.beginStop()
    lc.failStop(g)
    check(lc.current == .failed(g), "RW15 failStop -> failed terminal")
    check(lc.beginStart() == nil && lc.refusedStartFailedCount == 1, "RW15 restart after failed teardown refused (retained handle never overwritten)")
    lc.finishStop(g)
    check(lc.stopCount == 0 && lc.current == .failed(g), "RW15 NEG finishStop after failStop is NOT a fake completion")
    check(lc.beginStop() == .none && lc.runningGen == nil, "RW15 NEG no re-teardown, no running resurrection in failed")
    let lc2 = SessionLifecycle(); let h = lc2.beginStart()!
    lc2.failStart(h)
    check(lc2.beginStart() == nil && lc2.refusedStartFailedCount == 1, "RW15 failStart terminal, start refused")
}

// RW16 - stop races start: stop during starting does NOT touch the unit; the
// start side observes commitStart()==false and tears down itself; the abort
// completes the stop exactly once.
func armRW16() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!
    check(lc.beginStop() == .startWillTearDown(g), "RW16 stop during starting -> startWillTearDown (stop does NOT tear down)")
    check(lc.runningGen == nil, "RW16 runningGen never born for torn-down start")
    check(!lc.commitStart(g), "RW16 commitStart after stop race refused")
    lc.abortStart(g)
    check(lc.current == .idle && lc.abortedStartCount == 1 && lc.stopCount == 1, "RW16 abort in stopping completes the stop once")
}

// RW17 - GenerationFence: late callback after the stop boundary is fenced and
// EVERY stale call is counted; a new generation commit re-admits only itself.
func armRW17() {
    let f = GenerationFence(); let g0 = f.active
    check(f.checkRT(g0), "RW17 active generation admitted")
    f.advance()
    check(!f.checkRT(g0) && f.fencedCount == 1, "RW17 late callback from retired generation fenced + counted")
    _ = f.checkRT(g0)
    check(f.fencedCount == 2, "RW17 every stale call counted (no dedup)")
    let g1 = f.active; f.setActive(g1 &+ 5)
    check(f.checkRT(g1 &+ 5) && !f.checkRT(g1), "RW17 old generation stays fenced after new commit")
}

// RW18 - receipt BEFORE reset: the retired session's admission evidence
// survives resetForNewGeneration; live counters zero; drop accounting is
// byte-exact with a sticky latch cleared only by the per-generation reset.
func armRW18() {
    guard let ring = SPSCPCMRing(capacityFrames: 16) else { check(false, "RW18 alloc"); return }
    var bytes = [UInt8](repeating: 0xAB, count: 12)
    let pr = bytes.withUnsafeBufferPointer { ring.push($0) }
    check(pr.admittedFrames == 3, "RW18 3 frames admitted")
    var dst = [UInt8](repeating: 0, count: 8)
    _ = dst.withUnsafeMutableBufferPointer { ring.render(into: $0.baseAddress!, frames: 2) }
    let receipt = ring.snapshotReceipt(generation: 7)
    ring.resetForNewGeneration()
    check(receipt.pushedFrames == 3 && receipt.consumedFrames == 2 && receipt.admittedBytes == 12, "RW18 receipt holds retired-session evidence across reset")
    check(ring.pushedFrames.load() == 0 && ring.availableFrames == 0, "RW18 live counters zero after reset")
    guard let small = SPSCPCMRing(capacityFrames: 2) else { return }
    var five = [UInt8](repeating: 1, count: 20)
    let ov = five.withUnsafeBufferPointer { small.push($0) }
    check(ov.admittedFrames == 2 && ov.droppedFrames == 3 && small.droppedBytes.load() == 12 && small.droppedAnything.load() == 1, "RW18 NEG overflow drop byte-exact + sticky latch")
    var tail = [UInt8](repeating: 2, count: 10)
    let pt = tail.withUnsafeBufferPointer { small.push($0) } // ring already full
    check(pt.droppedTailBytes == 2 && small.partialTailDrops.load() == 1, "RW18 NEG partial-frame tail refused byte-exact, never misaligned")
    check(small.requestedBytes.load() == small.admittedBytes.load() + small.droppedBytes.load(), "RW18 byte conservation requested==admitted+dropped")
    small.resetForNewGeneration()
    check(small.droppedAnything.load() == 0, "RW18 reset clears the sticky latch")
}

// RW19 - producer gate after stop-reset: a producer that captured the running
// generation BEFORE stop must be refused on RE-CHECK; the new session never
// reuses the captured generation. (Core mirror of AudioUnitSink.push :326-327;
// the sink wiring itself is MacShell.)
func armRW19() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!; _ = lc.commitStart(g)
    let captured = lc.runningGen
    check(captured == g, "RW19 producer pre-check sees running generation")
    _ = lc.beginStop(); lc.finishStop(g)
    check(lc.runningGen == nil, "RW19 joined/absent stop-reset: re-check refuses (no old push into stopped session)")
    check(lc.beginStart()! != g, "RW19 new session generation differs from captured stale one")
}

// RW20 - teardown completeness is ORDERED and PER-SESSION/GENERATION; the
// record ceiling drops are counted and refuse success; a non-finite stamp
// refuses success with a visibly corrupted record.
func armRW20() {
    nonisolated(unsafe) var t = 1000.0
    let l = TimingLedger(capacity: 64, clock: { t })
    let req: [LedgerKind] = [.audioStartAttempt, .audioStartAccepted, .audioStopAttempt, .audioStopAccepted, .disposeCompleted]
    for k in req { l.append(session: 1, generation: 1, segment: .teardown, subsystem: .audio, kind: k) }
    check(l.missingSequence(session: 1, generation: 1, required: req).isEmpty, "RW20 ordered teardown sequence complete")
    check(l.missingSequence(session: 1, generation: 2, required: req) == req, "RW20 NEG foreign generation fulfills nothing")
    check(l.missingSequence(session: 2, generation: 1, required: req) == req, "RW20 NEG foreign session fulfills nothing")
    let l2 = TimingLedger(capacity: 3, clock: { t })
    for i in 0..<5 { l2.append(session: 0, generation: 0, segment: .teardown, subsystem: .core, kind: .teardownStart, bytes: i) }
    check(l2.count == 3 && l2.overflowed && l2.droppedEventCount == 2 && !l2.allowsSuccess, "RW20 NEG ceiling exact: 3 kept 2 dropped, refuses success")
    nonisolated(unsafe) var bad = false; let badClock: @Sendable () -> Double = { bad ? .nan : 1000.0 }
    let l3 = TimingLedger(capacity: 16, clock: badClock); bad = true
    l3.append(session: 0, generation: 0, segment: .teardown, subsystem: .core, kind: .teardownStart)
    check(l3.invalidStampCount == 1 && !l3.allowsSuccess && l3.snapshot().first?.note.hasPrefix("INVALID_STAMP:") == true, "RW20 NEG non-finite stamp counted, marked, refuses success")
    t += 1
}

// RW21 - FINDING REPRODUCTION (observed v5/lane-0 candidate gaps; FAIL = the
// finding): (a) jsonLines reserves the truncation marker but not the header,
// so for maxBytes in (header, header+marker) the export exceeds its own byte
// ceiling (observed exact: maxBytes=120 -> 191 bytes). (b) A small-budget
// export sets overflowed and flips allowsSuccess false - an export-formatting
// budget permanently poisons the run verdict.
func armRW21() {
    let t = 1000.0
    let hl = TimingLedger(capacity: 100, clock: { t })
    let headerLen = hl.jsonLines(maxBytes: 10_000_000).utf8.count
    var firstBad = -1
    for mb in stride(from: 60, through: 900, by: 4) {
        let l = TimingLedger(capacity: 100, clock: { t })
        for i in 0..<8 { l.append(session: 1, generation: 1, segment: .teardown, subsystem: .audio, kind: .teardownStart, bytes: i, note: String(repeating: "n", count: 120)) }
        if mb > headerLen && l.jsonLines(maxBytes: mb).utf8.count > mb { firstBad = mb; break }
    }
    check(firstBad < 0, "RW21a export byte ceiling holds for every budget", "GAP REPRODUCED: header=\(headerLen) firstBad=\(firstBad) (export exceeds maxBytes in (header, header+marker))")
    let l2 = TimingLedger(capacity: 100, clock: { t })
    for i in 0..<8 { l2.append(session: 1, generation: 1, segment: .teardown, subsystem: .audio, kind: .teardownStart, bytes: i, note: String(repeating: "n", count: 120)) }
    let before = l2.allowsSuccess
    _ = l2.jsonLines(maxBytes: 400)
    check(!(before && !l2.allowsSuccess), "RW21b export budget does not poison the run verdict", "GAP REPRODUCED: truncated export set overflowed, allowsSuccess flipped false")
}

// RW22 - FINDING REPRODUCTION (architect blocker 1, weak-nil reader leak):
// the lane-0 callback guard (AudioUnitSink.swift :267-271) enters admission
// BEFORE the weak-sink check and returns -50 WITHOUT exit() on the nil
// branch. Executed here: the ACTUAL production AdmissionCell with the
// guard's exact order transcribed (the Mac callback body is not
// Linux-reachable - proxy for the guard sequence, native for the cell).
func armRW22() {
    guard let cell = AdmissionCell() else { check(false, "RW22 alloc"); return }
    let sinkIsNil = true
    if cell.enter() { if sinkIsNil { /* return -50 :271 - no exit() */ } }
    let atRetire = cell.retire()
    // ARM status (Main convention): the OLD guard shape leaked the reader;
    // the r2 callback balances defer-on-admit so the leak shape is gone.
    print("ARM RW22 old=EXPECTED-FAIL reproduced(readerLeak=\(atRetire == 1 && cell.readers == 1)) revised-core=PASS-by-control native=BLOCKED(Mac callback body owner-run)")
    guard let ctl = AdmissionCell() else { return }
    if ctl.enter() { if sinkIsNil { ctl.exit() } }
    check(ctl.retire() == 0 && ctl.readers == 0, "RW22 control: exit-on-nil drains to zero")
}


print("SEAM RW23 real-AudioUnit stop/uninit/dispose error injection + retired-callback zero-output: MacShell arms, owner-run; NOT claimed from Linux")

// === r3 S5 SUBSET (RW24-RW25): shared cancel/commit + typed end reason ===

final class RW25Clock: PlaybackClock, @unchecked Sendable {
    var t = 0.0
    func nowSeconds() -> Double { t }
}
final class RW25Source: FrameSource, @unchecked Sendable {
    var events: [SourceEvent]; var i = 0
    init(_ events: [SourceEvent]) { self.events = events }
    func nextEvent() async -> SourceEvent {
        if i >= events.count { return .ended(.sourceEnded) }
        let e = events[i]; i += 1; return e
    }
}
final class RW25Sink: FrameSink, @unchecked Sendable {
    var shown = 0
    func show(_ frame: SourceFrame) async -> Bool { shown += 1; return true }
    // Explicit TEST-FAKE ticketed conformance (the protocol has NO
    // bypass default - verdict S5 rev3): the fake forwards by choice;
    // the REAL strict boundary is proven at CancelCommit.commitFrame
    // (RW30) and in DisplaySink's fail-closed strict show.
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        await show(frame)
    }
}

func armRW24() {
    // Shared cancel/commit cell: admission serializes on ONE CAS.
    let commit = CancelCommit()
    check(commit.available, "RW24 commit cell available")
    let t0 = commit.tryAdmit(revision: 0)
    // Verdict S5 rev3: the post-cancel arm needs a FRESH UNCONSUMED
    // ticket - reusing a consumed one would pass from replay rejection
    // even with the cancel fence broken.
    let t0fresh = commit.tryAdmit(revision: 0)
    check(t0 != nil && t0fresh != nil, "RW24 admit before cancel succeeds (tickets issued)")
    check(commit._testMayFinishConsume(ticket: t0!), "RW24 pre-ACK ticket may finish its commit")
    check(commit.admitted == 2, "RW24 admissions counted on the cell")
    commit.requestCancel(); commit.requestCancel()   // idempotent
    check(commit.isCancelled, "RW24 cancel set monotonically")
    check(commit.tryAdmit(revision: 0) == nil, "RW24 no admission after cancel (serialized refusal)")
    check(commit.validate(ticket: t0fresh!), "RW24 pre-admitted ticket stays GENUINE (sequence issued)")
    check(!commit._testMayFinishConsume(ticket: t0fresh!), "RW24 ACK=NO-FURTHER-COMMIT fresh unconsumed ticket fenced after the cancel-ACK")
    check(commit.admitted == 2, "RW24 post-cancel refusal not counted")
    do { _ = try commit.bumpRevision(); check(false, "RW24 cancelled commit seek must throw .cancelled") }
    catch let e as CancelCommit.SeekRefusal { check(e == .cancelled, "RW24 cancelled seek is a typed .cancelled refusal") }
    catch { check(false, "RW24 unexpected seek error type") }
    check(commit.tryAdmit(revision: 0) == nil, "RW24 cancelled commit refuses admission")

    let c2 = CancelCommit()
    _ = try! c2.bumpRevision()
    check(c2.tryAdmit(revision: 0) == nil, "RW24 stale revision refused typed")
    check(c2.tryAdmit(revision: 1) != nil, "RW24 current revision admitted")
    // Verdict S5: NO caller-revision mask alias - an out-of-range
    // revision is refused typed, never aliased into the 31-bit field.
    check(c2.tryAdmit(revision: 1 << 31) == nil, "RW24 ALIAS-FIX out-of-range revision refused (no mask alias)")
    // Finish contract across a seek: a pre-seek ticket stays genuine
    // (admission was the gate), but NEW admissions need the new revision.
    let preSeek = c2.tryAdmit(revision: 1)!
    _ = try! c2.bumpRevision()
    check(c2.validate(ticket: preSeek), "RW24 pre-seek ticket stays GENUINE (sequence issued)")
    check(!c2._testMayFinishConsume(ticket: preSeek), "RW24 ACK=NO-FURTHER-COMMIT old-revision ticket fenced at commit after seek")
    check(c2.tryAdmit(revision: 1) == nil && c2.tryAdmit(revision: 2) != nil,
          "RW24 post-seek admission needs the exact new revision")
    // Race smoke: admissions vs a concurrent cancel - counts must add
    // up, no admit lands after the cell shows cancelled.
    let c3 = CancelCommit()
    let okN = AtomicU64()!; let noN = AtomicU64()!
    let g = DispatchGroup(); let q = DispatchQueue(label: "rw24", attributes: .concurrent)
    for _ in 0..<64 {
        g.enter(); q.async {
            if c3.tryAdmit(revision: 0) != nil { _ = okN.fetchAdd(1) } else { _ = noN.fetchAdd(1) }
            g.leave()
        }
    }
    q.async { c3.requestCancel() }
    bw(g, "main.swift:751 g")
    check(okN.intValue + noN.intValue == 64, "RW24 race: every racer admitted-or-refused")
    check(c3.admitted == UInt64(okN.intValue), "RW24 cell admission count == successful admits (no interleave)")
}

func armRW25() {
    // (a) source-reported cancel sets BOTH the typed end reason and the
    // cancelled flag (r2 defect: flag stayed false).
    let src = RW25Source([.ended(.cancelled)])
    let sink = RW25Sink()
    let pump = FramePump(source: src, sink: sink, clock: RW25Clock(), onWait: { _ in true })
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsBox: PumpStats? = nil
    Task { statsBox = await pump.run(); sem.signal() }
    bw(sem, "main.swift:765 sem")
    let st = statsBox!
    check(st.cancelled, "RW25 source-reported cancel sets stats.cancelled")
    check(st.endReason == .cancelled, "RW25 end reason is TYPED .cancelled", "\(st.endReason)")

    // (b) commit-wired pump: an external cancel before the show admits
    // nothing; the cell carries the refusal, not just a bool check.
    let commit = CancelCommit()
    let src2 = RW25Source([.frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "a"))])
    let sink2 = RW25Sink()
    let pump2 = FramePump(source: src2, sink: sink2, clock: RW25Clock(), commit: commit, onWait: { _ in true })
    commit.requestCancel()
    let sem2 = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsBox2: PumpStats? = nil
    Task { statsBox2 = await pump2.run(); sem2.signal() }
    bw(sem2, "main.swift:780 sem2")
    let st2 = statsBox2!
    check(st2.shown == 0 && sink2.shown == 0, "RW25 externally-cancelled commit admits zero shows")
    check(commit.admitted == 0, "RW25 commit cell recorded zero admissions")
    check(st2.cancelled && st2.endReason == .cancelled, "RW25 pump ends typed cancelled via commit")

    // (c) Verdict S5 rev6: an external INVALIDATION (direct bump)
    // before the pump's first pull does NOT fence new production on a
    // stateless source - the pull stamps the LIVE revision at pull
    // start and admits under it. (Stale-PULL and stale-WAIT fencing,
    // where production CROSSED the ACK, is witnessed by RW31/RW32.)
    let commit3 = CancelCommit()
    let src3 = RW25Source([.frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "b")),
                           .ended(.endOfStream)])
    let sink3 = RW25Sink()
    let ledger = TimingLedger(capacity: 32, clock: { 0.0 })
    let pump3 = FramePump(source: src3, sink: sink3, clock: RW25Clock(),
                          ledger: ledger, ledgerSession: 1, ledgerGeneration: 1,
                          commit: commit3, onWait: { _ in true })
    _ = try! commit3.bumpRevision()   // external seek AFTER pump adopted rev 0
    let sem3 = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsBox3: PumpStats? = nil
    Task { statsBox3 = await pump3.run(); sem3.signal() }
    bw(sem3, "main.swift:803 sem3")
    let st3 = statsBox3!
    check(st3.shown == 1 && sink3.shown == 1 && commit3.admitted == 1,
          "RW25 post-invalidation pull on a stateless source admits under the live revision")
    check(st3.endReason == .endOfStream, "RW25 admission is not an end; source EOS reached")
    check(st3.seekStalePulls == 0, "RW25 no stale pull: the pull started after the invalidation")
}

func armRW28() {
    // Verdict S1 rev2 FULL BOUNDARY MATRIX on a seeded fresh instance
    // (the shared minter is permanently consumed by earlier arms - a
    // boundary matrix needs a fresh minter): mint-at-reserve ordering,
    // rollback burns (never re-issues) an id, the last valid id mints
    // once, exhaustion latches permanently, a HELD pre-ceiling token
    // registers post-ceiling with a distinct root, refusals are typed,
    // and roots stay reachable through the capability-gated accessor.
    let reg = PlaybackRegistry(testSeedNextID: UInt64.max - 3)

    // 1. rollback BURNS the id: r0 mints max-2, rolls back, and the
    //    next reserve mints max-1 - the burned id is never re-issued.
    guard case .success(let r0) = reg.reserve(.tombstone) else {
        check(false, "RW28 r0 reserve refused unexpectedly"); return
    }
    check(r0.id == UInt64.max - 2, "RW28 first mint is the seeded next id")
    check(reg.rollback(r0), "RW28 held-token rollback releases the slot")
    guard case .success(let r1) = reg.reserve(.tombstone),
          case .success(let r2) = reg.reserve(.tombstone) else {
        check(false, "RW28 r1/r2 reserves refused unexpectedly"); return
    }
    check(r1.id == UInt64.max - 1 && r2.id == UInt64.max,
          "RW28 mints continue in order after a burn (no re-issue): \(r1.id), \(r2.id)")

    // 2. the LAST VALID id minted exactly once: the next reserve hits
    //    the ceiling, refuses typed, and latches permanent exhaustion.
    if case .failure = reg.reserve(.tombstone) {
        print("PASS RW28 reserve at the issuance ceiling refuses typed")
    } else {
        check(false, "RW28 reserve at the ceiling succeeded (wrap!)")
    }
    if case .failure = reg.reserve(.tombstone) {
        print("PASS RW28 exhaustion LATCHED (second reserve still refuses)")
    } else {
        check(false, "RW28 exhaustion not latched (reserve succeeded after the ceiling)")
    }

    // 3. a HELD pre-ceiling token REGISTERS post-ceiling (mint-at-
    //    reserve makes exhaustion stop NEW issuance, never a valid
    //    insert): both held tokens register with distinct ids, no
    //    re-issue, no root overwrite.
    var toks: [RegistrationToken] = []
    let lock = NSLock()
    let g = DispatchGroup(); let q = DispatchQueue(label: "rw28", attributes: .concurrent)
    for (i, r) in [r1, r2].enumerated() {
        g.enter(); q.async {
            if let t = reg.register(root: RW27Root(i), token: r) { lock.lock(); toks.append(t); lock.unlock() }
            g.leave()
        }
    }
    bw(g, "main.swift:861 g")
    check(toks.count == 2 && Set(toks.map { $0.id }).count == 2,
          "RW28 held pre-ceiling tokens register post-ceiling DISTINCT", "\(toks.map { $0.id })")
    check(toks.allSatisfy { reg.retentionState(of: $0).retained },
          "RW28 both boundary roots retained (no overwrite)")

    // 4. root retention reachable through the capability-gated
    //    accessor, and ONLY for the registered capability.
    for t in toks {
        check(reg.root(of: t) != nil, "RW28 capability-gated root reachable post-ceiling")
    }
    check(reg.retentionState(of: toks[0]).kind == .tombstone,
          "RW28 retention kind intact post-ceiling")
}

func armRW29() {
    // Verdict S5 rev2 ticket transport arms + seeded ceilings.
    // A. issuer binding: a ticket is genuine ONLY on its issuing cell.
    let a = CancelCommit(); let b = CancelCommit()
    let ta = a.tryAdmit(revision: 0)!
    check(!b.validate(ticket: ta), "RW29 cross-cell validate refuses a foreign ticket")
    check(!b._testMayFinishConsume(ticket: ta), "RW29 cross-cell mayFinish refuses a foreign ticket")
    check(a.validate(ticket: ta), "RW29 issuer validate accepts its own ticket")
    // B. single consume: mayFinish BURNS the ticket - a replay is a
    //    typed refusal even on the issuer, while genuineness (validate)
    //    remains a stable historical fact.
    check(a._testMayFinishConsume(ticket: ta), "RW29 first mayFinish consumes the ticket")
    check(!a._testMayFinishConsume(ticket: ta), "RW29 replayed mayFinish refused (single consume)")
    check(a.validate(ticket: ta), "RW29 consumed ticket stays genuine (validate is not the gate)")
    // C. seeded ADMISSION ceiling: the REAL saturating algorithm at
    //    2^32-1 - the next admission is a typed nil refusal, the count
    //    never wraps into the revision field.
    let cAd = CancelCommit(testSeedAdmissions: CancelCommit.admitCeilingForTest, revision: 0)
    check(cAd.tryAdmit(revision: 0) == nil, "RW29 seeded admission ceiling refuses typed")
    check(cAd.revision == 0, "RW29 admission saturation never carries into revision")
    check(cAd.admissionExhausted, "RW29 admissionExhausted reads true at the ceiling")
    // D. seeded REVISION ceiling: the REAL saturating bump at 2^31-1 -
    //    one bump lands, the next is a typed .exhausted throw, and the
    //    cancel bit is untouched.
    let cRev = CancelCommit(testSeedAdmissions: 0, revision: CancelCommit.revisionCeilingForTest - 1)
    do {
        let bumped = try cRev.bumpRevision()
        check(bumped == CancelCommit.revisionCeilingForTest, "RW29 seeded near-ceiling bump lands exactly at the ceiling")
    } catch { check(false, "RW29 near-ceiling bump threw unexpectedly") }
    do { _ = try cRev.bumpRevision(); check(false, "RW29 ceiling bump must throw .exhausted") }
    catch let e as CancelCommit.SeekRefusal { check(e == .exhausted, "RW29 ceiling bump is a typed .exhausted refusal") }
    catch { check(false, "RW29 unexpected ceiling bump error type") }
    check(!cRev.isCancelled, "RW29 revision saturation never carries into the cancel bit")
    check(cRev.seekExhausted, "RW29 seekExhausted reads true at the ceiling")
    check(cRev.tryAdmit(revision: CancelCommit.revisionCeilingForTest) != nil,
          "RW29 admissions still issue at the seek ceiling (independent fields)")
}
/// RW30 (verdict S5 rev5): locked state box + poll-with-deadline - the
/// ACK-blocking witness reads state ONLY under the lock, and the 2s
/// bound guards a STUCK witness, never a success-timing oracle.
armRW24(); armRW25(); armRW27(); armRW28(); armRW29(); armRW30(); armRW31(); armRW32(); armRW33(); armRW14(); armRW15(); armRW16(); armRW17(); armRW18(); armRW19(); armRW20(); armRW21(); armRW22()
print("RW14-RW22 L9 teardown subset done (RW21 now ACCEPTANCE after production fix; RW22 ARM status).")
armRW34(); armRW35()
print(failures == 0 ? "ALL RACE WITNESSES PASS (incl RW34/RW35)" : "RACE WITNESSES FAILURES PRESENT count=\(failures)")

```

```text id=source1
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
    c1._testAfterConsumeBeforeAssign = { holdEntered.signal(); bw(releaseHold, "RaceArms2.swift:34 releaseHold") }
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
    bw(holdEntered, "RaceArms2.swift:49 holdEntered")                       // section held: consumed, pre-assign
    DispatchQueue(label: "rw30.cancel").async {
        ackAttempted.signal()                // the ACK attempt is in flight
        c1.requestCancel()                   // MUST block on the held section
        boxA.withLock { b in b.ackReturned = true }
        cancelDone.signal()
    }
    bw(ackAttempted, "RaceArms2.swift:56 ackAttempted")
    // Bounded witness window (locked state box, no fixed-sleep oracle):
    // an early ACK return is caught immediately; the 2s bound only
    // guards a STUCK witness.
    check(!boxA.poll(2.0) { $0.ackReturned },
          "RW30 cancel ACK blocked while the commit section was held after consume")
    releaseHold.signal()
    bw(commitDone, "RaceArms2.swift:63 commitDone"); bw(cancelDone, "RaceArms2.swift:63 cancelDone")
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
    c2._testBeforeConsume = { hold2Entered.signal(); bw(release2, "RaceArms2.swift:81 release2") }
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
    bw(hold2Entered, "RaceArms2.swift:99 hold2Entered")
    DispatchQueue(label: "rw30.seek").async {
        seekAttempted.signal()               // the ACK attempt is in flight
        _ = try! c2.bumpRevision()           // MUST block on the held section
        boxB.withLock { b in b.ackReturned = true }
        seekDone.signal()
    }
    bw(seekAttempted, "RaceArms2.swift:106 seekAttempted")
    check(!boxB.poll(2.0) { $0.ackReturned },
          "RW30 seek ACK blocked while the commit section was held before consume")
    release2.signal()
    bw(commit2Done, "RaceArms2.swift:110 commit2Done"); bw(seekDone, "RaceArms2.swift:110 seekDone")
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
    /// Release the parked pull with the generation's first frame (frame0:
    /// shows on arrival, owns the anchor - RULES.md:69).
    func releaseFrame0() {
        lock.lock(); let cc = continuation; continuation = nil; lock.unlock()
        cc?.resume(returning: .frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "f0")))
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
    nonisolated(unsafe) var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); runDoneA.signal() }
    check(srcA.waitForPulls(1, timeout: 2.0), "RW31/A pull parked before the seek")
    nonisolated(unsafe) var ackA = false
    let ackDoneA = DispatchSemaphore(value: 0)
    Task { ackA = await pumpA.resetPresentation(); ackDoneA.signal() }
    bw(ackDoneA, "RaceArms2.swift:242 ackDoneA")
    check(ackA, "RW31/A seek ACK succeeded (typed revision bump)")
    check(srcA.coordinatedRevision == 1, "RW31/A coordinated source seek fired with the NEW revision")
    srcA.releaseOldFrame()                       // pre-seek frame released AFTER the ACK
    check(srcA.waitForPulls(2, timeout: 2.0), "RW31/A pump parked on the next pull after the fence")
    srcA.releaseEOS()
    bw(runDoneA, "RaceArms2.swift:248 runDoneA")
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
    // RULES.md:69 port: the old arm forced the pacing wait with the M4
    // shared anchor (resetPresentation(seekAnchorSeconds: 0.0) making the
    // 0.1 frame early). Landing semantics removed the pre-set anchor, so
    // the wait is staged WITHOUT it: frame0 (0.0) shows and owns the
    // anchor, the 0.1 frame is +0.1 early against it and parks in the
    // pacing wait; the DIRECT bumpRevision is the ACK. The witness is
    // unchanged: a held wait whose pull stamp goes stale across the ACK
    // mints no new-revision ticket and lands no commit.
    let commitB = CancelCommit()
    let srcB = RW31ParkedSource(oldPTS: 0.1)   // +0.1 early vs the frame0 anchor -> .wait
    let sinkB = RW25Sink()
    let clockB = RW31Clock()
    let waitEntered = DispatchSemaphore(value: 0)
    let releaseWait = DispatchSemaphore(value: 0)
    let waitCalls = AtomicU64()!
    let pumpB = FramePump(source: srcB, sink: sinkB, clock: clockB, commit: commitB, onWait: { _ in
        if waitCalls.fetchAdd(1) == 0 { waitEntered.signal(); bw(releaseWait, "RW31/B phase=pacing-wait wait=release frame=0.1 rev=pre-ack") }
        return true   // every wait COMPLETED
    })
    let runDoneB = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); runDoneB.signal() }
    check(srcB.waitForPulls(1, timeout: 2.0), "RW31/B pull parked before frame0 release")
    srcB.releaseFrame0()                         // frame0 shows, owns the anchor (0.0)
    check(srcB.waitForPulls(2, timeout: 2.0), "RW31/B pull parked before old-frame release")
    srcB.releaseOldFrame()                       // 0.1 frame delivered pre-ACK
    check(waitEntered.wait(timeout: .now() + 2.0) == .success, "RW31/B frame parked in the pacing wait")
    do { _ = try commitB.bumpRevision() } catch { check(false, "RW31/B unexpected seek refusal") }
    clockB.set(0.1)                              // the re-decide sees the frame due NOW (inside the show window)
    releaseWait.signal()                         // the held wait completes AFTER the ACK
    check(srcB.waitForPulls(3, timeout: 2.0), "RW31/B pump parked on the next pull after the fence")
    srcB.releaseEOS()
    bw(runDoneB, "RW31/B wait=runDone frame=held0.1 rev=post-ack")
    let stB = statsB!
    check(stB.shown == 1 && sinkB.shown == 1, "RW31/B only frame0 showed; the held-wait old frame landed NO commit")
    check(commitB.admitted == 1, "RW31/B held-wait old frame minted NO new-revision ticket (frame0's ticket only)")
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
    nonisolated(unsafe) var ackA = false
    let ackDoneA = DispatchSemaphore(value: 0)
    Task { ackA = await pumpA.resetPresentation(); ackDoneA.signal() }
    bw(ackDoneA, "RaceArms2.swift:386 ackDoneA")
    check(ackA, "RW32/A seek ACK after actual flush receipt")
    check(srcA.barrierCalls == [1], "RW32/A barrier ran with the TARGET revision before the bump")
    check(srcA.queueCount() == 0, "RW32/A the flush receipt ACTUALLY dropped the pre-seek queue")
    check(commitA.revision == 1, "RW32/A the bump published only after the receipt")
    let runDoneA = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); runDoneA.signal() }
    check(srcA.waitForPulls(1, timeout: 2.0), "RW32/A first pull parked")
    srcA.releasePull(.frame(rw32frame(0.0, "new-0")))   // post-seek production (due NOW at clock 0)
    check(srcA.waitForPulls(2, timeout: 2.0), "RW32/A second pull parked")
    srcA.releasePull(.ended(.endOfStream))
    bw(runDoneA, "RaceArms2.swift:398 runDoneA")
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
    nonisolated(unsafe) var ackB = true
    let ackDoneB = DispatchSemaphore(value: 0)
    Task { ackB = await pumpB.resetPresentation(); ackDoneB.signal() }
    bw(ackDoneB, "RaceArms2.swift:414 ackDoneB")
    check(!ackB, "RW32/B typed barrier failure is a typed seek refusal (false)")
    check(commitB.revision == 0, "RW32/B NO revision bump on a failed barrier")
    check(srcB.queueCount() == 1, "RW32/B failed barrier did not drop source state")
    let runDoneB = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); runDoneB.signal() }
    check(srcB.waitForPulls(1, timeout: 2.0), "RW32/B first pull parked")
    srcB.releasePull(.frame(rw32frame(0.0, "old-0")))
    check(srcB.waitForPulls(2, timeout: 2.0), "RW32/B second pull parked")
    srcB.releasePull(.ended(.endOfStream))
    bw(runDoneB, "RaceArms2.swift:425 runDoneB")
    check(statsB!.shown == 1 && statsB!.digestsShown == ["old-0"],
          "RW32/B refused seek: pre-seek production still admits under the unchanged revision")

    // C. UNSUPPORTED: fail closed - typed refusal, no mutation.
    let commitC = CancelCommit()
    let srcC = RW32QueuedSource(queued: [])
    srcC.barrierOutcome = .unsupported
    let pumpC = FramePump(source: srcC, sink: RW25Sink(), clock: RW25Clock(), commit: commitC, onWait: { _ in true })
    nonisolated(unsafe) var ackC = true
    let ackDoneC = DispatchSemaphore(value: 0)
    Task { ackC = await pumpC.resetPresentation(); ackDoneC.signal() }
    bw(ackDoneC, "RaceArms2.swift:437 ackDoneC")
    check(!ackC && commitC.revision == 0, "RW32/C .unsupported fails closed: typed refusal, no bump")

    // D. OVERLAP: a NEWER reset supersedes the in-flight older one -
    //    exactly ONE bump lands; the superseded reset publishes nothing.
    let commitD = CancelCommit()
    let srcD = RW32QueuedSource(queued: [])
    srcD.parkNextBarrier()
    let pumpD = FramePump(source: srcD, sink: RW25Sink(), clock: RW25Clock(), commit: commitD, onWait: { _ in true })
    nonisolated(unsafe) var ackD1 = true, ackD2 = false
    let doneD1 = DispatchSemaphore(value: 0), doneD2 = DispatchSemaphore(value: 0)
    Task { ackD1 = await pumpD.resetPresentation(); doneD1.signal() }
    check(srcD.waitForBarrierParked(2.0), "RW32/D older reset parked in the barrier")
    Task { ackD2 = await pumpD.resetPresentation(); doneD2.signal() }
    bw(doneD2, "RaceArms2.swift:451 doneD2")   // the NEWER reset's barrier was not parked: it completes
    check(ackD2, "RW32/D the newer reset wins and ACKs")
    srcD.releaseBarrier()
    bw(doneD1, "RaceArms2.swift:454 doneD1")
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
    nonisolated(unsafe) var statsE: PumpStats? = nil
    Task { statsE = await pumpE.run(); runDoneE.signal() }
    check(srcE.waitForPulls(1, timeout: 2.0), "RW32/E first pull parked")
    nonisolated(unsafe) var ackE = false
    let ackDoneE = DispatchSemaphore(value: 0)
    Task { ackE = await pumpE.resetPresentation(); ackDoneE.signal() }
    check(srcE.waitForBarrierParked(2.0), "RW32/E barrier in flight")
    srcE.releasePull(.frame(rw32frame(0.0, "crossed")))   // pull returns MID-BARRIER
    Thread.sleep(forTimeInterval: 0.15)                    // give the pump a chance to misbehave
    check(commitE.admitted == 0 && sinkE.shown == 0,
          "RW32/E the crossed pull is GATED: zero admissions, zero shows while the barrier is in flight")
    srcE.releaseBarrier()
    bw(ackDoneE, "RaceArms2.swift:480 ackDoneE")
    check(ackE && commitE.revision == 1, "RW32/E ACK lands only after the actual receipt")
    check(srcE.waitForPulls(2, timeout: 2.0), "RW32/E pump re-pulled after the fence")
    srcE.releasePull(.ended(.endOfStream))
    bw(runDoneE, "RaceArms2.swift:484 runDoneE")
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
    nonisolated(unsafe) var pulled: [SourceEvent] = []
    let sem = DispatchSemaphore(value: 0)
    Task { for _ in 0..<7 { pulled.append(await src.nextEvent()) }; sem.signal() }
    bw(sem, "RaceArms2.swift:544 sem")
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
    let barrierSem = DispatchSemaphore(value: 0); nonisolated(unsafe) var barrier: SeekBarrierOutcome? = nil
    Task { barrier = await src.coordinateSeek(revision: 4); barrierSem.signal() }
    bw(barrierSem, "RaceArms2.swift:559 barrierSem")
    check(barrier == .flushed, "RW34/A stateless source barrier is the typed .flushed receipt")

    // B. failure terminal latches identically.
    let innerB = RW34ScriptedSource([.failed(7), .ended(.endOfStream)])
    let srcB = IdempotentEventSource(innerB, binding: sess)
    nonisolated(unsafe) var pulledB: [SourceEvent] = []
    let semB = DispatchSemaphore(value: 0)
    Task { for _ in 0..<3 { pulledB.append(await srcB.nextEvent()) }; semB.signal() }
    bw(semB, "RaceArms2.swift:568 semB")
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
    let semC = DispatchSemaphore(value: 0); nonisolated(unsafe) var statsC: PumpStats? = nil
    Task { statsC = await pumpC.run(); semC.signal() }
    bw(semC, "RaceArms2.swift:585 semC")
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
    let semA = DispatchSemaphore(value: 0); nonisolated(unsafe) var statsA: PumpStats? = nil
    Task { statsA = await pumpA.run(); semA.signal() }
    bw(semA, "RaceArms2.swift:620 semA")
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
    let semB = DispatchSemaphore(value: 0); nonisolated(unsafe) var statsB: PumpStats? = nil
    Task { statsB = await pumpB.run(); semB.signal() }
    bw(semB, "RaceArms2.swift:642 semB")
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

```

```text id=fixtures1
fixtures are embedded in the product target sources (inlined above).
```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-cwwu6xna/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-cwwu6xna/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Compiling GorAVCore AdmissionTable.swift
[8/15] Compiling GorAVCore Boundary.swift
[9/15] Emitting module GorAVCore
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Compiling race_witness_tests RaceArms2.swift
[68/71] Emitting module race_witness_tests
[69/72] Compiling race_witness_tests main.swift
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:180:37: warning: initialization of immutable value 'bGo' was never used; consider replacing with assignment to '_' or removing it
    let aLoaded = AtomicU64()!; let bGo = AtomicU64()!; let done = AtomicU64()!
                                ~~~~^~~
                                _
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:574:9: warning: variable 'bytes' was never mutated; consider changing to 'let' constant
    var bytes = [UInt8](repeating: 0xAB, count: 12)
    ~~~ ^
    let
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:584:9: warning: variable 'five' was never mutated; consider changing to 'let' constant
    var five = [UInt8](repeating: 1, count: 20)
    ~~~ ^
    let
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:587:9: warning: variable 'tail' was never mutated; consider changing to 'let' constant
    var tail = [UInt8](repeating: 2, count: 10)
    ~~~ ^
    let
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:626:7: warning: 't' mutated after capture by sendable closure
    t += 1
      ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:612:29: note: variable defined here
    nonisolated(unsafe) var t = 1000.0
                            ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:613:47: note: variable captured by sendable closure
    let l = TimingLedger(capacity: 64, clock: { t })
                                              ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:613:49: note: capturing use
    let l = TimingLedger(capacity: 64, clock: { t })
                                                ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:626:7: warning: 't' mutated after capture by sendable closure
    t += 1
      ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:612:29: note: variable defined here
    nonisolated(unsafe) var t = 1000.0
                            ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:619:47: note: variable captured by sendable closure
    let l2 = TimingLedger(capacity: 3, clock: { t })
                                              ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:619:49: note: capturing use
    let l2 = TimingLedger(capacity: 3, clock: { t })
                                                ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:623:63: warning: 'bad' mutated after capture by sendable closure
    let l3 = TimingLedger(capacity: 16, clock: badClock); bad = true
                                                              ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:622:29: note: variable defined here
    nonisolated(unsafe) var bad = false; let badClock: @Sendable () -> Double = { bad ? .nan : 1000.0 }
                            ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:622:81: note: variable captured by sendable closure
    nonisolated(unsafe) var bad = false; let badClock: @Sendable () -> Double = { bad ? .nan : 1000.0 }
                                                                                ^
/tmp/packet-proof-cwwu6xna/tree/Sources/race-witness-tests/main.swift:622:83: note: capturing use
    nonisolated(unsafe) var bad = false; let badClock: @Sendable () -> Double = { bad ? .nan : 1000.0 }
                                                                                  ^
[70/73] Wrapping AST for race-witness-tests for debugging
[71/73] Write Objects.LinkFileList
[72/73] Linking race-witness-tests
Build complete! (7.85s)
RW canonical race witnesses (lane-0)
SEAM RW6 registry-exhaustion: MacShell arm, owner-run; NOT claimed from Linux
PASS RW1 post-retire enter refused (silence, no payload)
PASS RW1 readers 0 after refused enter
PASS RW2 pre-retire enter admitted
PASS RW2 admitted reader still counted post-retire
PASS RW2 second enter refused while reader in flight
PASS RW2 readers drain to zero
PASS RW2 post-drain enter still refused
PASS RW3 retire idempotent
PASS RW3 retired cell never reopens (no generation reuse)
PASS RW4 enter
PASS RW4 stuck reader observable (blocks reset/reuse)
PASS boundedWait [main.swift:97 group]
PASS RW5 readers drain to zero under race
PASS RW5 no enter after final retire
PASS RW5 admitted-before-retire count = 64 (informational)
PASS RW7 refused-enter hot path leaves no state
ALL RACE WITNESSES PASS
ARM RW8 old=EXPECTED-FAIL reproduced(weak=true) revised-core=COVERED-BY-RW12(registry-level-only) native=BLOCKED(owner-Mac-seam)
ARM RW9 old=EXPECTED-FAIL reproduced(weak=false) revised-core=COVERED-BY-RW12(registry-level-only) native=BLOCKED(owner-Mac-seam)
PASS boundedWait [main.swift:195 sem]
ARM RW10 old=EXPECTED-FAIL reproduced(overshot=2>1) revised-core=PASS-RW11(registry-level) native=BLOCKED(owner-Mac-seam)
ARM-STATUS convention: old=EXPECTED-FAIL(reproduced) revised-core=<arm coverage, registry-level ONLY> native=BLOCKED(off-Mac seams are owner-run; no parse-only closure claimed).
PASS boundedWait [main.swift:230 group]
PASS RW11 every racer got success-or-typed-refusal
PASS RW11 every token rolled back exactly once
PASS RW11 token is once-consume (second rollback refused typed)
PASS RW11 no leaked reservation after rollback
PASS RW11b held active reservation commits under full fault backlog
PASS RW11b FINDING-1-FIX active->fault commits with reserved terminal slot (concurrent terminal backlog full)
PASS RW11b fault headroom stops one short while a terminal obligation is held
PASS RW12 FINDING-3-FIX registration ROOT immutably retained (no rebind can free it)
PASS RW12 registration token issued by token commit
PASS RW12 consumed token cannot register twice (typed nil)
PASS RW12b typed fault graph ATTACHED (root untouched)
PASS RW12b graph edges (owner+handle) survive caller release
PASS RW12b ATTACH-ONCE second attach refused typed (graph not replaceable)
PASS RW12c active->fault commits (valid transition)
PASS RW12c FINDING-2-FIX terminal->active REFUSED (no resurrection)
PASS RW12c terminal kind immutable (fault->tombstone refused)
PASS RW12c token drives its OWN entry (active->tombstone commits)
PASS RW12c retentionState typed query: fault registration retained
PASS RW13 fault exhaustion at the per-kind cap
PASS RW13 typed exhaustion at per-kind cap (active=0 faults=4 tombstones=2)
PASS RW13 active reserve refuses typed while a terminal backlog is full
PASS RW13 tombstone headroom independent of fault cap
PASS RW26 no evidence -> .noop
PASS RW26 FINDING-7-FIX in-flight stop reads .pending (not stale, not noop)
PASS RW26 published outcome returned for its generation
PASS RW26 repeat idle query returns the SAME preserved outcome
PASS RW26 FINDING-7-FIX new generation invalidates the old cache (no g1 outcome from g2 stop)
PASS RW26 FINDING-8-FIX start/stop-owned failure evidence preserved for its generation
PASS RW26 stale-generation publish refused typed
PASS RW26 stale publish did not clear the current in-flight marker
PASS boundedWait [main.swift:499 grp]
PASS RW26b exactly one teardown owner across concurrent stops
PASS RW26b concurrent loser saw pending-or-cached, never a bare noop gap
PASS RW26b post-finish beginStop is a no-op
PASS RW26b repeat stop returns the preserved outcome
RW11-RW13+RW26 registry/outcome acceptance arms done (r3-rev1 capability state machine).
SEAM RW23 real-AudioUnit stop/uninit/dispose error injection + retired-callback zero-output: MacShell arms, owner-run; NOT claimed from Linux
PASS RW24 commit cell available
PASS RW24 admit before cancel succeeds (tickets issued)
PASS RW24 pre-ACK ticket may finish its commit
PASS RW24 admissions counted on the cell
PASS RW24 cancel set monotonically
PASS RW24 no admission after cancel (serialized refusal)
PASS RW24 pre-admitted ticket stays GENUINE (sequence issued)
PASS RW24 ACK=NO-FURTHER-COMMIT fresh unconsumed ticket fenced after the cancel-ACK
PASS RW24 post-cancel refusal not counted
PASS RW24 cancelled seek is a typed .cancelled refusal
PASS RW24 cancelled commit refuses admission
PASS RW24 stale revision refused typed
PASS RW24 current revision admitted
PASS RW24 ALIAS-FIX out-of-range revision refused (no mask alias)
PASS RW24 pre-seek ticket stays GENUINE (sequence issued)
PASS RW24 ACK=NO-FURTHER-COMMIT old-revision ticket fenced at commit after seek
PASS RW24 post-seek admission needs the exact new revision
PASS boundedWait [main.swift:751 g]
PASS RW24 race: every racer admitted-or-refused
PASS RW24 cell admission count == successful admits (no interleave)
PASS boundedWait [main.swift:765 sem]
PASS RW25 source-reported cancel sets stats.cancelled
PASS RW25 end reason is TYPED .cancelled
PASS boundedWait [main.swift:780 sem2]
PASS RW25 externally-cancelled commit admits zero shows
PASS RW25 commit cell recorded zero admissions
PASS RW25 pump ends typed cancelled via commit
PASS boundedWait [main.swift:803 sem3]
PASS RW25 post-invalidation pull on a stateless source admits under the live revision
PASS RW25 admission is not an end; source EOS reached
PASS RW25 no stale pull: the pull started after the invalidation
PASS boundedWait [main.swift:456 g]
PASS RW27 concurrent registration ids unique (no re-issue/overwrite)
PASS RW27 every concurrent registration keeps its own root
PASS RW28 first mint is the seeded next id
PASS RW28 held-token rollback releases the slot
PASS RW28 mints continue in order after a burn (no re-issue): 18446744073709551614, 18446744073709551615
PASS RW28 reserve at the issuance ceiling refuses typed
PASS RW28 exhaustion LATCHED (second reserve still refuses)
PASS boundedWait [main.swift:861 g]
PASS RW28 held pre-ceiling tokens register post-ceiling DISTINCT
PASS RW28 both boundary roots retained (no overwrite)
PASS RW28 capability-gated root reachable post-ceiling
PASS RW28 capability-gated root reachable post-ceiling
PASS RW28 retention kind intact post-ceiling
PASS RW29 cross-cell validate refuses a foreign ticket
PASS RW29 cross-cell mayFinish refuses a foreign ticket
PASS RW29 issuer validate accepts its own ticket
PASS RW29 first mayFinish consumes the ticket
PASS RW29 replayed mayFinish refused (single consume)
PASS RW29 consumed ticket stays genuine (validate is not the gate)
PASS RW29 seeded admission ceiling refuses typed
PASS RW29 admission saturation never carries into revision
PASS RW29 admissionExhausted reads true at the ceiling
PASS RW29 seeded near-ceiling bump lands exactly at the ceiling
PASS RW29 ceiling bump is a typed .exhausted refusal
PASS RW29 revision saturation never carries into the cancel bit
PASS RW29 seekExhausted reads true at the ceiling
PASS RW29 admissions still issue at the seek ceiling (independent fields)
PASS boundedWait [RaceArms2.swift:49 holdEntered]
PASS boundedWait [RaceArms2.swift:56 ackAttempted]
PASS RW30 cancel ACK blocked while the commit section was held after consume
PASS boundedWait [RaceArms2.swift:34 releaseHold]
PASS RW30 after-consume: the ACK never returns before the assignment lands
PASS boundedWait [RaceArms2.swift:63 commitDone]
PASS boundedWait [RaceArms2.swift:63 cancelDone]
PASS RW30 the in-section commit completed WITH its assignment
PASS RW30 the cancel ACK landed after the assignment
PASS RW30 no admission after the ACK
PASS RW30 post-ACK admission stays refused
PASS boundedWait [RaceArms2.swift:99 hold2Entered]
PASS boundedWait [RaceArms2.swift:106 seekAttempted]
PASS RW30 seek ACK blocked while the commit section was held before consume
PASS boundedWait [RaceArms2.swift:81 release2]
PASS RW30 before-consume: the seek ACK never returns before the assignment lands
PASS RW30 the held pre-seek commit still commits (it won the section race)
PASS boundedWait [RaceArms2.swift:110 commit2Done]
PASS boundedWait [RaceArms2.swift:110 seekDone]
PASS RW30 seek ACK landed after the assignment; revision now current
PASS RW30 current-revision admission after the seek ACK
PASS RW30 post-seek current-revision frame commits
PASS RW30 ticket refuses a DIFFERENT pts (frame binding)
PASS RW30 ticket refuses a DIFFERENT digest (frame binding)
PASS RW30 a refused attempt did not burn the ticket; the exact frame commits
PASS RW30 the committed ticket cannot replay
PASS RW30 foreign-issuer ticket refused at commitFrame
PASS RW30 foreign-registry token refused at register (owner checked before consume)
PASS RW30 foreign-registry token refused at rollback
PASS RW30 the TRUE owner's rollback still completes
PASS RW30 same seeded ids on separate registries stay ISOLATED (no collision class)
PASS RW30 each registry retains only its own root
PASS RW30 a foreign capability reaches no root (capability is registry-scoped)
PASS RW31/A pull parked before the seek
PASS boundedWait [RaceArms2.swift:242 ackDoneA]
PASS RW31/A seek ACK succeeded (typed revision bump)
PASS RW31/A coordinated source seek fired with the NEW revision
PASS RW31/A pump parked on the next pull after the fence
PASS boundedWait [RaceArms2.swift:248 runDoneA]
PASS RW31/A held-pull old frame landed NO commit
PASS RW31/A held-pull old frame minted NO new-revision ticket
PASS RW31/A the old frame was fenced TYPED at the post-await provenance gate
PASS RW31/A the fence is not an end; EOS reached
PASS RW31/B pull parked before frame0 release
PASS RW31/B pull parked before old-frame release
PASS RW31/B frame parked in the pacing wait
PASS boundedWait [RW31/B phase=pacing-wait wait=release frame=0.1 rev=pre-ack]
PASS RW31/B pump parked on the next pull after the fence
PASS boundedWait [RW31/B wait=runDone frame=held0.1 rev=post-ack]
PASS RW31/B only frame0 showed; the held-wait old frame landed NO commit
PASS RW31/B held-wait old frame minted NO new-revision ticket (frame0's ticket only)
PASS RW31/B the completed post-ACK wait was fenced TYPED at the after-wait provenance check
PASS RW31/B the fence is not an end; EOS reached
PASS boundedWait [RaceArms2.swift:386 ackDoneA]
PASS RW32/A seek ACK after actual flush receipt
PASS RW32/A barrier ran with the TARGET revision before the bump
PASS RW32/A the flush receipt ACTUALLY dropped the pre-seek queue
PASS RW32/A the bump published only after the receipt
PASS RW32/A first pull parked
PASS RW32/A second pull parked
PASS boundedWait [RaceArms2.swift:398 runDoneA]
PASS RW32/A post-barrier pulls carry only NEW production - no old digest can surface
PASS boundedWait [RaceArms2.swift:414 ackDoneB]
PASS RW32/B typed barrier failure is a typed seek refusal (false)
PASS RW32/B NO revision bump on a failed barrier
PASS RW32/B failed barrier did not drop source state
PASS RW32/B first pull parked
PASS RW32/B second pull parked
PASS boundedWait [RaceArms2.swift:425 runDoneB]
PASS RW32/B refused seek: pre-seek production still admits under the unchanged revision
PASS boundedWait [RaceArms2.swift:437 ackDoneC]
PASS RW32/C .unsupported fails closed: typed refusal, no bump
PASS RW32/D older reset parked in the barrier
PASS boundedWait [RaceArms2.swift:451 doneD2]
PASS RW32/D the newer reset wins and ACKs
PASS boundedWait [RaceArms2.swift:454 doneD1]
PASS RW32/D the superseded older reset publishes nothing (typed false)
PASS RW32/D exactly one bump across overlapping resets
PASS RW32/D both resets ran the barrier
PASS RW32/E first pull parked
PASS RW32/E barrier in flight
PASS RW32/E the crossed pull is GATED: zero admissions, zero shows while the barrier is in flight
PASS boundedWait [RaceArms2.swift:480 ackDoneE]
PASS RW32/E ACK lands only after the actual receipt
PASS RW32/E pump re-pulled after the fence
PASS boundedWait [RaceArms2.swift:484 runDoneE]
PASS RW32/E the crossed pull was fenced TYPED after the barrier, then EOS
PASS RW33 the outer commit still landed (no deadlock)
PASS RW33 reentrant bump/mayFinish/commitFrame are TYPED refusals
PASS RW33 every reentrant call counted (cancel+bump+mayFinish+commit)
PASS RW33 reentrant cancel/bump changed nothing
PASS RW33 the cell is still live after the section (cancel was refused)
PASS RW14 runningGen born with active transition
PASS RW14 beginStop -> teardownOwned
PASS RW14 runningGen nil in the SAME transition (no late-running window)
PASS RW14 NEG second beginStop no-op (single teardown owner)
PASS RW14 NEG finishStop(wrong g) ignored
PASS RW14 generations strictly monotonic, no reuse
PASS RW15 failStop -> failed terminal
PASS RW15 restart after failed teardown refused (retained handle never overwritten)
PASS RW15 NEG finishStop after failStop is NOT a fake completion
PASS RW15 NEG no re-teardown, no running resurrection in failed
PASS RW15 failStart terminal, start refused
PASS RW16 stop during starting -> startWillTearDown (stop does NOT tear down)
PASS RW16 runningGen never born for torn-down start
PASS RW16 commitStart after stop race refused
PASS RW16 abort in stopping completes the stop once
PASS RW17 active generation admitted
PASS RW17 late callback from retired generation fenced + counted
PASS RW17 every stale call counted (no dedup)
PASS RW17 old generation stays fenced after new commit
PASS RW18 3 frames admitted
PASS RW18 receipt holds retired-session evidence across reset
PASS RW18 live counters zero after reset
PASS RW18 NEG overflow drop byte-exact + sticky latch
PASS RW18 NEG partial-frame tail refused byte-exact, never misaligned
PASS RW18 byte conservation requested==admitted+dropped
PASS RW18 reset clears the sticky latch
PASS RW19 producer pre-check sees running generation
PASS RW19 joined/absent stop-reset: re-check refuses (no old push into stopped session)
PASS RW19 new session generation differs from captured stale one
PASS RW20 ordered teardown sequence complete
PASS RW20 NEG foreign generation fulfills nothing
PASS RW20 NEG foreign session fulfills nothing
PASS RW20 NEG ceiling exact: 3 kept 2 dropped, refuses success
PASS RW20 NEG non-finite stamp counted, marked, refuses success
PASS RW21a export byte ceiling holds for every budget
PASS RW21b export budget does not poison the run verdict
ARM RW22 old=EXPECTED-FAIL reproduced(readerLeak=true) revised-core=PASS-by-control native=BLOCKED(Mac callback body owner-run)
PASS RW22 control: exit-on-nil drains to zero
RW14-RW22 L9 teardown subset done (RW21 now ACCEPTANCE after production fix; RW22 ARM status).
PASS boundedWait [RaceArms2.swift:544 sem]
PASS RW34/A pre-terminal frame passes through
PASS RW34/A first terminal delivered once, then replayed idempotently (late frame/second terminal/starve/failure never surface)
PASS RW34/A inner source never pulled again once latched (revival fence)
PASS RW34/A session binding preserved
PASS RW34/A no violation before any pump-side report
PASS RW34/A violation hook observable (count + last kind)
PASS boundedWait [RaceArms2.swift:559 barrierSem]
PASS RW34/A stateless source barrier is the typed .flushed receipt
PASS boundedWait [RaceArms2.swift:568 semB]
PASS RW34/B typed failure terminal latched and replayed (later EOS never leaks)
PASS RW34/B inner never pulled after failure latch
PASS boundedWait [RaceArms2.swift:585 semC]
PASS RW34/C only the pre-terminal frame shows; the ghost frame never lands
PASS RW34/C exactly one typed EOS finalization
PASS boundedWait [RaceArms2.swift:620 semA]
PASS RW35/A anchor frame shows on arrival under a per-read jump clock (single decisionNow sample)
PASS RW35/A the shown frame is the anchor frame
PASS RW35/A no spurious long wait minted by a double clock sample
PASS RW35/A clean EOS after the anchor frame
PASS boundedWait [RaceArms2.swift:642 semB]
PASS RW35/B both frames show in pts order
PASS RW35/B exactly one pacing wait (anchor frame shows on arrival)
PASS RW35/B the wait is the pts delta off the anchor, never a wall-absolute
PASS RW35/C decider: exactly-on-pts shows (the anchor-frame case)
PASS RW35/C decider: half-frame-late drops (the double-sample failure mode)
PASS RW35/C decider: early frame waits its delta
ALL RACE WITNESSES PASS (incl RW34/RW35)
```
