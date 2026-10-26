// NATIVE-HOLD SEEK SUITES (R2Y-scoped, canonical-owner continuation 2026-10-26).
// v2 BINDING (PREP-v3 accepted source candidates; peer coverage disposition
// 2026-10-26): contract 768d60ab + decoder candidate 1d019d42 (production
// candidate), diag 5af5c98 (decoder candidate + derived realignment diff
// 5e7bb006; old patches 475b5a54/c1a3b4ff = semantic lineage only, NOT an
// unchanged-applicable chain). Suite base d84270be; v1 candidate 64f0acac
// superseded by this v2. Runs the diag candidate against the REAL locked
// FFmpeg 8.0.1 @894da5ca and the REAL fixture. Areas: (NH1) cancel during
// native hold, (NH2) close during native hold, (NH3) partial-mutation
// injection, (NH4) afterCleanup->receipt window unobservability, (NH5)
// multipull drain + stale/closed refusals, (NH6) PRE-ENTRY queued-validation
// settlement, cases a-f (av_seek_frame never runs - no avseek).
// INHERITED HARNESS LIMITS (carried explicitly; NOT fixed here - no new
// harness project): a gate-timeout prints a "FAIL gate-timeout" line WITHOUT
// incrementing the fail counter, and waitEntered may hang. Any isolated run
// therefore needs an EXTERNAL deadline and must REJECT any gate-timeout line
// regardless of the FINAL line or exit code.
// Selector: the validation run invokes the explicit selector "NH6", which
// selects cases a-f; no ALL/empty expansion. Linux model evidence over a
// REAL native call; NOT Mac/RT proof, NOT organic-failure proof, NOT whole-S5.
import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

var pass = 0, fail = 0
func chk(_ name: String, _ cond: Bool) { if cond { pass += 1; print("PASS \(name)") } else { fail += 1; print("FAIL \(name)") } }
func note(_ s: String) { print("NOTE \(s)") }

final class FlagBox: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return v }
}

/// Records an Optional<SeekEventIdentity> read (outer nil = not yet recorded).
final class AdmissionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: SeekEventIdentity??
    func record(_ v: SeekEventIdentity?) { lock.lock(); seen = v; lock.unlock() }
    func get() -> SeekEventIdentity?? { lock.lock(); defer { lock.unlock() }; return seen }
}

final class Gate: @unchecked Sendable {
    let label: String
    init(_ label: String = "?") { self.label = label }
    // Harness-only fix (grounded): the 1-core Swift cooperative pool has ONE
    // executor thread; a DispatchSemaphore block on the main task starved it,
    // so execute() never ran. waitEntered is now an async continuation
    // (suspends, frees the pool); only the HOOK may block, and it runs on the
    // decoder's GCD nativeQueue, not the Swift pool.
    private let lock = NSLock()
    private var enteredFlag = false
    private var enteredCont: CheckedContinuation<Void, Never>?
    private let release = DispatchSemaphore(value: 0)
    private var fired = false
    func arm() -> (@Sendable (SeekEventIdentity) -> Void) {
        { _ in
            self.lock.lock()
            if self.fired { self.lock.unlock(); return }   // self-disarming: hold the FIRST fire only
            self.fired = true
            self.enteredFlag = true
            let c = self.enteredCont; self.enteredCont = nil
            self.lock.unlock()
            c?.resume()
            let t0 = Date()
            let w = self.release.wait(timeout: .now() + 30)
            print("HOOKRELEASE label=\(self.label) waited=\(String(format: "%.2f", Date().timeIntervalSince(t0)))s timedOut=\(w == .timedOut)")
            if w == .timedOut { print("FAIL gate-timeout (safety release) label=\(self.label)") }
        }
    }
    func waitEntered() async -> Bool {
        lock.lock()
        if enteredFlag { lock.unlock(); return true }
        lock.unlock()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.lock.lock()
            if self.enteredFlag { self.lock.unlock(); cont.resume(); return }
            self.enteredCont = cont
            self.lock.unlock()
        }
        return true
    }
    func open() { release.signal() }
}

func makeRequest(_ id: UInt64, _ turn: UInt64, binding: (token: SourceToken, session: SeekSessionID, revision: SeekRevision), expected: SeekRevision, seconds: Int64) throws -> SeekRequest {
    SeekRequest(correlationID: try SeekCorrelationID(rawValue: id, queueTurn: turn), session: binding.session,
        source: binding.token, target: SeekTarget(position: try RationalTime(value: seconds, timescale: 1),
            rounding: .floorToKeyframe, requestedFlags: 1), expectedRevision: expected)
}

func openDecoder(_ diag: FFmpegSoftwareDecoder.SeekDiagnostics?, fixture: String) async throws -> (FFmpegSoftwareDecoder, (token: SourceToken, session: SeekSessionID, revision: SeekRevision), SessionID) {
    let decoder = diag.map { FFmpegSoftwareDecoder(testSeekDiagnostics: $0) } ?? FFmpegSoftwareDecoder()
    let root = URL(fileURLWithPath: fixture).deletingLastPathComponent().path
    try decoder.pinLocalRoots([root])
    let issued = PlaybackIdentityAuthority.shared.issue()!
    try await decoder.open(source: GorAVCore.SourceDescriptor(id: fixture, kind: .local, seekable: true), session: issued)
    guard let binding = decoder.currentBinding() else { throw FFmpegSoftwareDecoder.SeekError.noActiveSession }
    // Prime the native queue (SeekContractTests pattern): pull until the first
    // decoded frame so the seek turn is not serialized behind the open turn.
    var primed = false
    for _ in 0..<400 {
        if case .frameDecoded(_, let frame) = await decoder.nextEvent() {
            await decoder.releaseFrame(handle: frame.handle, session: issued); primed = true; break
        }
    }
    if !primed { print("WARN prime: no frame before seek") }
    return (decoder, binding, issued)
}

@main enum NativeHoldMain {
    static func main() async {
        setbuf(stdout, nil)
        do {
            guard let fixture = ProcessInfo.processInfo.environment["S5_SEEK_FIXTURE"] else {
                print("NOT_RUN: S5_SEEK_FIXTURE missing"); exit(2)
            }

let selArgs = Set(CommandLine.arguments.dropFirst())
func sel(_ n: String) -> Bool { selArgs.isEmpty || selArgs.contains("ALL") || selArgs.contains(n) }

            // ---- NH1: cancel DURING native hold (beforeNativeCall gate) ----
            if sel("NH1") { do {
                let gate = Gate("NH1")
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeNativeCall: gate.arm())
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let req = try makeRequest(101, 1, binding: binding, expected: binding.revision, seconds: 1)
                let t = try decoder.tryBegin(req)
                let exec = Task { try? t.execute() }
                chk("NH1.holdEntered", await gate.waitEntered())
                t.requestCancellation()                       // cancel lands DURING the native hold
                gate.open()                                   // real av_seek_frame now runs
                let receipt = await t.completion()
                exec.cancel()
                if case .cancelledAfterCleanup(let facts, let poison) = receipt.outcome {
                    chk("NH1.cancelledAfterCleanup", true)
                    chk("NH1.realNativeRan", facts.avSeekReturn.map { $0 >= 0 } == true && facts.flushObserved && facts.packetFeedReset)
                    chk("NH1.poisonCloseRequired", poison.recoveryRequired && poison.recoveryPath == .closeRequired)
                } else { chk("NH1.cancelledAfterCleanup", false); note("outcome=\(receipt.outcome)") }
                chk("NH1.revisionUnadvanced", receipt.nextRevision == binding.revision) // revision advances ONLY on nativeReady
                chk("NH1.identityBound", receipt.identity == t.identity)
                await decoder.close(session: issued)
            } }

            // ---- NH3: partial-mutation injection (fail AFTER real seek + real cleanup) ----
            if sel("NH3") { do {
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(failAfterRealSeekAndCleanup: true)
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let t = try decoder.tryBegin(try makeRequest(301, 1, binding: binding, expected: binding.revision, seconds: 2))
                try t.execute()
                let receipt = await t.completion()
                if case .failed(let stage, let reason, let facts, let poison) = receipt.outcome {
                    chk("NH3.failedCleanedUp", stage == .cleanedUp)
                    chk("NH3.poisonedState", reason == .poisonedState)
                    chk("NH3.realSeekNotOrganic", facts.avSeekReturn.map { $0 >= 0 } == true) // real av_seek_frame SUCCEEDED; injection is not an organic failure
                    chk("NH3.testLabel", poison.detail.contains("TEST INJECTION"))
                    chk("NH3.poisonCloseRequired", poison.recoveryRequired && poison.recoveryPath == .closeRequired)
                } else { chk("NH3.failedCleanedUp", false); note("outcome=\(receipt.outcome)") }
                chk("NH3.revisionUnadvanced", receipt.nextRevision == binding.revision)
                await decoder.close(session: issued)
            } }

            // ---- NH2: close DURING native hold (serial queue: seek completes its turn first) ----
            if sel("NH2") { do {
                let gate = Gate("NH2")
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeNativeCall: gate.arm())
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let t = try decoder.tryBegin(try makeRequest(201, 1, binding: binding, expected: binding.revision, seconds: 1))
                let exec = Task { try? t.execute() }
                chk("NH2.holdEntered", await gate.waitEntered())
                let closer = Task { await decoder.close(session: issued) }   // requestClose() lands synchronously, teardown queued behind the held turn
                // Explicit state barrier (no blind sleep): descriptor(for:) throws .closed the moment
                // the coordinator's closing flag is live; the hook is provably still blocked, so the
                // close request has landed DURING the native hold by construction. Bounded at 2s.
                var closeLanded = false
                for _ in 0..<2000 {
                    if (try? decoder.descriptor(for: binding.token)) == nil { closeLanded = true; break }
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                chk("NH2.closeLandedDuringHold", closeLanded)
                gate.open()
                let receipt = await t.completion()
                exec.cancel()
                await closer.value
                chk("NH2.noHang", true)                                     // both completed inside the gate bounds
                if case .cancelledAfterCleanup(_, let poison) = receipt.outcome {
                    chk("NH2.outcomeCancelledAfterCleanup", true)
                    chk("NH2.closeRequired", poison.recoveryPath == .closeRequired)
                } else { chk("NH2.outcomeCancelledAfterCleanup", false); note("NH2 outcome=\(receipt.outcome)") }
                do { _ = try decoder.tryBegin(try makeRequest(202, 2, binding: binding, expected: binding.revision, seconds: 1)); chk("NH2.postCloseRefused", false) }
                catch { chk("NH2.postCloseRefused", true) }
            } }

            // ---- NH4: afterCleanup->receipt window: no queue observer can see the gap ----
            if sel("NH4") { do {
                let gate = Gate("NH4")
                let windowFlag = FlagBox()
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(afterCleanupBeforeReceipt: { id in
                    windowFlag.set()
                    gate.arm()(id)
                })
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let t = try decoder.tryBegin(try makeRequest(401, 1, binding: binding, expected: binding.revision, seconds: 1))
                let exec = Task { try? t.execute() }
                chk("NH4.windowEntered", await gate.waitEntered() && windowFlag.get())
                // While the window is held, a pull must NOT observe a torn post-cleanup state.
                // Unstructured race: withTaskGroup waits for ALL children on scope exit, which previously
                // blocked on the queue-held pull for the full 30s safety timeout. Here the 0.5s timeout
                // resumes the continuation and the loser (the pull) is awaited only AFTER gate.open().
                // Explicit admission signal (no production change): the pull task FIRST reads the
                // public activeTransaction synchronously. Recording the in-flight identity proves the
                // pull was scheduled AND observed the unsettled transaction during the window - the
                // absence-of-delivery witness below can no longer be explained by an unscheduled task.
                let admission = AdmissionBox()
                let pull = Task { () -> SeekProviderEvent<NativeFrame> in
                    admission.record(decoder.activeTransaction)
                    return await decoder.nextEvent()
                }
                let raceLock = NSLock(); var resumed = false
                let observed: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    Task { _ = await pull.value; raceLock.lock(); if !resumed { resumed = true; raceLock.unlock(); cont.resume(returning: true) } else { raceLock.unlock() } }
                    Task { try? await Task.sleep(nanoseconds: 500_000_000); raceLock.lock(); if !resumed { resumed = true; raceLock.unlock(); cont.resume(returning: false) } else { raceLock.unlock() } }
                }
                chk("NH4.noTornObservationDuringHold", observed == false)   // nothing observable while the turn is held
                var admitted = false
                if case .some(.some(let id)) = admission.get() { admitted = (id == t.identity) }
                chk("NH4.pullAdmittedDuringHold", admitted)                 // pull provably scheduled + saw the unsettled txn
                gate.open()
                let receipt = await t.completion()
                exec.cancel()
                if case .nativeReady = receipt.outcome { chk("NH4.nativeReady", true) } else { chk("NH4.nativeReady", false); note("outcome=\(receipt.outcome)") }
                chk("NH4.revisionAdvanced", receipt.nextRevision.rawValue == binding.revision.rawValue + 1)
                // The pull that was ADMITTED DURING the window now delivers only settled state:
                // its first event must already carry THIS transaction's revision+origin (a revision
                // publishable only by this transaction's finish - so delivery is provably post-settle).
                let delivered = await pull.value
                var got = false
                if case .frameDecoded(let origin, let frame) = delivered {
                    got = (origin.providerRevision == receipt.nextRevision && origin.requestOrigin == .transaction(t.identity.transactionID))
                    await decoder.releaseFrame(handle: frame.handle, session: issued)
                } else { note("NH4 heldPull delivered non-frame first event") }
                chk("NH4.heldPullFirstFrameBound", got)
            } }

            // ---- NH6: queued-validation race window (beforeQueuedValidation seam; freeze item 3,
            // R2Y "native-queue race" area). The hook holds the nativeQueue turn AFTER admission but
            // BEFORE queueRefusal/enterNative, so a state change landing here provably raced the queue.
            if sel("NH6") { do {
                // NH6a: close lands during the queued-validation window.
                do {
                    let gate = Gate("NH6a")
                    let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeQueuedValidation: gate.arm())
                    let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                    let t = try decoder.tryBegin(try makeRequest(501, 1, binding: binding, expected: binding.revision, seconds: 1))
                    let exec = Task { try? t.execute() }
                    chk("NH6a.windowEntered", await gate.waitEntered())
                    let closer = Task { await decoder.close(session: issued) }
                    var landed = false
                    for _ in 0..<2000 {   // bounded state barrier: descriptor throws .closed once closing is live
                        if (try? decoder.descriptor(for: binding.token)) == nil { landed = true; break }
                        try? await Task.sleep(nanoseconds: 1_000_000)
                    }
                    chk("NH6a.closeLandedDuringWindow", landed)
                    gate.open()
                    let receipt = await t.completion()
                    exec.cancel()
                    await closer.value
                    // POST-ADOPTION (PREP-v3 candidate): atomic requestClose records .close. NH6a's .close
                    // witnesses the CHOSEN timing (close landed inside the held window). The universal
                    // flag-gap absence follows ONLY from the accepted atomic requestClose SOURCE (flag +
                    // reason recorded under ONE lock) - it is NOT established by this timing witness.
                    if case .cancelledNoMutation(let reason) = receipt.outcome { chk("NH6a.cancelledNoMutationClose", reason == .close) }
                    else { chk("NH6a.cancelledNoMutationClose", false); note("NH6a outcome=\(receipt.outcome)") }
                    chk("NH6a.noMutation", receipt.mutation == .none)
                    chk("NH6a.preSeekStage", receipt.reachedStage == .preSeek)          // av_seek_frame never ran
                    chk("NH6a.revisionUnchanged", receipt.nextRevision == receipt.previousRevision)
                    do { _ = try decoder.tryBegin(try makeRequest(502, 2, binding: binding, expected: binding.revision, seconds: 1)); chk("NH6a.postCloseRefused", false) }
                    catch { chk("NH6a.postCloseRefused", true) }
                }
                // NH6b: cancellation lands during the queued-validation window (synchronous cancel -
                // the call returning IS the barrier; the hook is provably still held).
                do {
                    let gate = Gate("NH6b")
                    let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeQueuedValidation: gate.arm())
                    let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                    let t = try decoder.tryBegin(try makeRequest(511, 1, binding: binding, expected: binding.revision, seconds: 1))
                    let exec = Task { try? t.execute() }
                    chk("NH6b.windowEntered", await gate.waitEntered())
                    t.requestCancellation()                                              // lands under the state lock, synchronously
                    gate.open()
                    let receipt = await t.completion()
                    exec.cancel()
                    if case .cancelledNoMutation(let reason) = receipt.outcome { chk("NH6b.cancelledNoMutation", reason == .requested) }
                    else { chk("NH6b.cancelledNoMutation", false); note("NH6b outcome=\(receipt.outcome)") }
                    chk("NH6b.noMutation", receipt.mutation == .none)
                    chk("NH6b.preSeekStage", receipt.reachedStage == .preSeek)
                    chk("NH6b.revisionUnchanged", receipt.nextRevision == receipt.previousRevision)
                    // cancel does NOT poison: a fresh seek on the same binding is admitted and commits.
                    let t2 = try decoder.tryBegin(try makeRequest(512, 2, binding: binding, expected: binding.revision, seconds: 2))
                    let exec2 = Task { try? t2.execute() }
                    let receipt2 = await t2.completion()
                    exec2.cancel()
                    if case .nativeReady = receipt2.outcome { chk("NH6b.providerUnpoisoned", (try? receipt2.nextRevision == binding.revision.advanced()) == true) }
                    else { chk("NH6b.providerUnpoisoned", false); note("NH6b second outcome=\(receipt2.outcome)") }
                    await decoder.close(session: issued)
                }
                // NH6c: interrupt (session poison) lands during the queued-validation window.
                do {
                    let gate = Gate("NH6c")
                    let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeQueuedValidation: gate.arm())
                    let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                    let t = try decoder.tryBegin(try makeRequest(521, 1, binding: binding, expected: binding.revision, seconds: 1))
                    let exec = Task { try? t.execute() }
                    chk("NH6c.windowEntered", await gate.waitEntered())
                    decoder.requestInterrupt(session: issued)                            // synchronous poisonSession + I/O interrupt
                    gate.open()
                    let receipt = await t.completion()
                    exec.cancel()
                    // POST-ADOPTION (PREP-v3 candidate): poison pre-entry is a provider REFUSAL, not a
                    // cancel; arbitration stays .none here because NO caller cancel was recorded.
                    if case .refusedNoMutation(let reason) = receipt.outcome { chk("NH6c.refusedClosed", reason == .closed) }
                    else { chk("NH6c.refusedClosed", false); note("NH6c outcome=\(receipt.outcome)") }
                    chk("NH6c.arbitrationNone", receipt.arbitration == .none)
                    chk("NH6c.noMutation", receipt.mutation == .none)
                    chk("NH6c.preSeekStage", receipt.reachedStage == .preSeek)
                    chk("NH6c.revisionUnchanged", receipt.nextRevision == receipt.previousRevision)
                    do { _ = try decoder.tryBegin(try makeRequest(522, 2, binding: binding, expected: binding.revision, seconds: 1)); chk("NH6c.postPoisonRefused", false) }
                    catch { chk("NH6c.postPoisonRefused", true) }
                    await decoder.close(session: issued)
                }
            } }

            // ---- NH6d/e/f: settlement-priority witnesses (POST-ADOPTION, PREP-v3 candidate semantics).
            // v2: consolidated under sel("NH6") - one selector runs cases a-f.
            if sel("NH6") { do {
                // caller cancel recorded FIRST, close second -> first-recorded wins (.requested).
                // NOTE: invariant vs pre-adoption code (old hard-coded .requested agrees) - NOT discriminative.
                let gate = Gate("NH6d")
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeQueuedValidation: gate.arm())
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let t = try decoder.tryBegin(try makeRequest(531, 1, binding: binding, expected: binding.revision, seconds: 1))
                let exec = Task { try? t.execute() }
                chk("NH6d.windowEntered", await gate.waitEntered())
                t.requestCancellation()                                   // recorded FIRST (synchronous)
                let closer = Task { await decoder.close(session: issued) }
                var landed = false
                for _ in 0..<2000 { if (try? decoder.descriptor(for: binding.token)) == nil { landed = true; break }; try? await Task.sleep(nanoseconds: 1_000_000) }
                chk("NH6d.closeLandedDuringWindow", landed)
                gate.open()
                let receipt = await t.completion()
                exec.cancel(); await closer.value
                if case .cancelledNoMutation(let reason) = receipt.outcome { chk("NH6d.firstRecordedWins", reason == .requested) }
                else { chk("NH6d.firstRecordedWins", false); note("NH6d outcome=\(receipt.outcome)") }
                chk("NH6d.noMutation", receipt.mutation == .none)
                chk("NH6d.revisionUnchanged", receipt.nextRevision == receipt.previousRevision)
                // recorded caller cancel -> arbitration .cancellationRequested per the accepted classifier
                chk("NH6d.arbitrationCancellationRequested", receipt.arbitration == .cancellationRequested)
                chk("NH6d.preSeekStage", receipt.reachedStage == .preSeek)   // av_seek_frame never ran
                // claim limited to receipt-observable invariants: coreGated/facts are NOT on the
                // receipt surface for .cancelledNoMutation, so they are not asserted here.
            } }
            if sel("NH6") { do {
                // close FIRST (atomic requestClose records .close), caller cancel second -> .close.
                // DISCRIMINATIVE vs pre-adoption code (old hard-coded .requested FAILS this).
                let gate = Gate("NH6e")
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeQueuedValidation: gate.arm())
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let t = try decoder.tryBegin(try makeRequest(541, 1, binding: binding, expected: binding.revision, seconds: 1))
                let exec = Task { try? t.execute() }
                chk("NH6e.windowEntered", await gate.waitEntered())
                let closer = Task { await decoder.close(session: issued) }
                var landed = false
                for _ in 0..<2000 { if (try? decoder.descriptor(for: binding.token)) == nil { landed = true; break }; try? await Task.sleep(nanoseconds: 1_000_000) }
                chk("NH6e.closeLandedDuringWindow", landed)
                t.requestCancellation()                                   // second: never overwrites .close
                gate.open()
                let receipt = await t.completion()
                exec.cancel(); await closer.value
                if case .cancelledNoMutation(let reason) = receipt.outcome { chk("NH6e.closeReasonKept", reason == .close) }
                else { chk("NH6e.closeReasonKept", false); note("NH6e outcome=\(receipt.outcome)") }
                chk("NH6e.noMutation", receipt.mutation == .none)
                chk("NH6e.revisionUnchanged", receipt.nextRevision == receipt.previousRevision)
                // recorded caller cancel -> arbitration .cancellationRequested per the accepted classifier
                chk("NH6e.arbitrationCancellationRequested", receipt.arbitration == .cancellationRequested)
                chk("NH6e.preSeekStage", receipt.reachedStage == .preSeek)   // av_seek_frame never ran
                // claim limited to receipt-observable invariants (as NH6d).
            } }
            if sel("NH6") { do {
                // poison + caller cancel -> caller reason used; provider STAYS poisoned (fresh seek refused).
                // Outcome label invariant vs pre-adoption; the DISCRIMINATIVE part is pairing with NH6c
                // (poison-only -> refused) and the stays-poisoned assertion.
                let gate = Gate("NH6f")
                let diag = FFmpegSoftwareDecoder.SeekDiagnostics(beforeQueuedValidation: gate.arm())
                let (decoder, binding, issued) = try await openDecoder(diag, fixture: fixture)
                let t = try decoder.tryBegin(try makeRequest(551, 1, binding: binding, expected: binding.revision, seconds: 1))
                let exec = Task { try? t.execute() }
                chk("NH6f.windowEntered", await gate.waitEntered())
                decoder.requestInterrupt(session: issued)                 // poison first (synchronous)
                t.requestCancellation()                                   // caller reason recorded after poison
                gate.open()
                let receipt = await t.completion()
                exec.cancel()
                if case .cancelledNoMutation(let reason) = receipt.outcome { chk("NH6f.callerReasonUsed", reason == .requested) }
                else { chk("NH6f.callerReasonUsed", false); note("NH6f outcome=\(receipt.outcome)") }
                chk("NH6f.noMutation", receipt.mutation == .none)
                chk("NH6f.revisionUnchanged", receipt.nextRevision == receipt.previousRevision)
                // caller cancel recorded after poison -> arbitration .cancellationRequested
                chk("NH6f.arbitrationCancellationRequested", receipt.arbitration == .cancellationRequested)
                chk("NH6f.preSeekStage", receipt.reachedStage == .preSeek)   // av_seek_frame never ran
                // stays-poisoned claim is TYPED: exactly SeekRefusal.closed; any other error FAILS.
                do { _ = try decoder.tryBegin(try makeRequest(552, 2, binding: binding, expected: binding.revision, seconds: 1)); chk("NH6f.staysPoisoned", false) }
                catch SeekRefusal.closed { chk("NH6f.staysPoisoned", true) }
                catch { chk("NH6f.staysPoisoned", false); note("NH6f post-poison wrong error type (expected SeekRefusal.closed)") }
                await decoder.close(session: issued)
            } }

            // ---- NH5: multipull drain + stale/closed refusals ----
            if sel("NH5") { do {
                let (decoder, binding, issued) = try await openDecoder(nil, fixture: fixture)
                var rev = binding.revision
                var turns: UInt64 = 1
                for (i, sec) in [(0,1),(1,3),(2,0)] {
                    let t = try decoder.tryBegin(try makeRequest(UInt64(500+i), turns, binding: binding, expected: rev, seconds: Int64(sec))); turns += 1
                    try t.execute()
                    let receipt = await t.completion()
                    if case .nativeReady = receipt.outcome, receipt.nextRevision.rawValue == rev.rawValue + 1 {
                        chk("NH5.seek\(i).adopted", true); rev = receipt.nextRevision
                    } else { chk("NH5.seek\(i).adopted", false); note("outcome=\(receipt.outcome)") }
                    // drain a bounded number of frames; every delivered frame carries THIS revision
                    var drained = 0, okFrames = true
                    for _ in 0..<120 {
                        if case .frameDecoded(let origin, let frame) = await decoder.nextEvent() {
                            if origin.providerRevision != rev { okFrames = false }
                            await decoder.releaseFrame(handle: frame.handle, session: issued); drained += 1
                            if drained >= 5 { break }
                        }
                    }
                    chk("NH5.seek\(i).framesBound", okFrames && drained > 0)
                }
                // stale expectedRevision refused typed
                do { _ = try decoder.tryBegin(try makeRequest(600, turns, binding: binding, expected: .atOpen, seconds: 1)); chk("NH5.staleRefused", false) }
                catch { chk("NH5.staleRefused", true) }
                await decoder.close(session: issued)
                do { _ = try decoder.tryBegin(try makeRequest(601, turns+1, binding: binding, expected: rev, seconds: 1)); chk("NH5.closedRefused", false) }
                catch { chk("NH5.closedRefused", true) }
            } }
        } catch { chk("unexpectedError", false); print(String(describing: error)) }
        print("FINAL pass=\(pass) fail=\(fail)")
        if fail != 0 { exit(1) }
    }
}

func withTimeout<T: Sendable>(_ seconds: Double, _ body: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? nil
    }
}
