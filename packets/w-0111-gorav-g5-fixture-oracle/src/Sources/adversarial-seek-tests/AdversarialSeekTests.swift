// AdversarialSeekTests - REAL adapter + REAL decoder v2 (pin 5892cd2f) + REAL k3 fixture.
// Written against the SHIPPED SeekDiagnostics seam (constructor-only; production init has none):
//   beforeNativeCall        - after entry arbitration, BEFORE av_seek_frame
//   afterNativeReturn       - after the real C call, BEFORE cleanup
//   afterCleanupBeforeReceipt - after real cleanup, BEFORE receipt
//   failAfterRealSeekAndCleanup - injected failure AFTER a real successful seek + real cleanup;
//                                 the receipt preserves the REAL rc and labels TEST INJECTION.
// Scope honesty: an injected failure after a real successful seek proves the real mutation +
// poison/receipt path, NOT an organic FFmpeg failure. Hold-gate assertions bind to the seam's
// actual operation boundary: Gate.entered proves the decoder really reached that point.
import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVPlaybackCore

extension FFmpegSoftwareDecoder: CoreSeekProvider {}

private final class Gate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func hold(_: SeekEventIdentity) { entered.signal(); release.wait() }
    func holdRC(_: SeekEventIdentity, _: Int32) { entered.signal(); release.wait() }
}
private final class Tripwire: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    func hit(_: SeekEventIdentity) { hit() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}
private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    func mark() { lock.lock(); done = true; lock.unlock() }
    var completed: Bool { lock.lock(); defer { lock.unlock() }; return done }
}
private final class PullBox: @unchecked Sendable {
    private let lock = NSLock(); private var e: SeekProviderEvent<NativeFrame>?
    func set(_ v: SeekProviderEvent<NativeFrame>) { lock.lock(); e = v; lock.unlock() }
    var event: SeekProviderEvent<NativeFrame>? { lock.lock(); defer { lock.unlock() }; return e }
}
private final class AckBox: @unchecked Sendable {
    private let lock = NSLock(); private var list: [SeekRevision] = []
    func add(_ r: SeekRevision) { lock.lock(); list.append(r); lock.unlock() }
    var values: [SeekRevision] { lock.lock(); defer { lock.unlock() }; return list }
}

@main private enum AdversarialSeekTests {
    static var passes = 0, failures = 0
    static func chk(_ n: String, _ c: Bool) { if c { passes += 1; print("PASS \(n)") } else { failures += 1; print("FAIL \(n)") } }

    static func openReal(_ kit: String, _ epoch: UInt64, _ diag: FFmpegSoftwareDecoder.SeekDiagnostics) async throws -> FFmpegSoftwareDecoder {
        let d = FFmpegSoftwareDecoder(testSeekDiagnostics: diag)
        try d.pinLocalRoots([kit])
        try await d.open(source: SourceDescriptor(id: "\(kit)/fixtures/seekcheck-src.mp4", kind: .local, seekable: true),
                         session: SessionID(uncheckedEpoch: epoch))
        return d
    }
    static func sess(_ e: UInt64) -> SessionID { SessionID(uncheckedEpoch: e) }

    static func main() async throws {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let target = try! RationalTime(value: 1, timescale: 1)

        // 1. held-native CANCEL: hold before av_seek_frame (post-entry), core cancels, release.
        case1: do {
            let gate = Gate(); let acks = AckBox()
            let dec = try await openReal(KIT, 301, .init(beforeNativeCall: { gate.hold($0) }))
            let driver = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()                      // decoder REALLY reached the pre-native boundary
            driver.requestCancellationOfActive()
            gate.release.signal()
            let result = await out
            guard case .failedPoisoned(let receipt) = result else { chk("heldNativeCancel.failedPoisoned", false); break case1 }
            guard case .cancelledAfterCleanup(_, let cpoison) = receipt.outcome else { chk("heldNativeCancel.cancelledAfterCleanup", false); break case1 }
            chk("heldNativeCancel.failedPoisoned", true)
            chk("heldNativeCancel.cancelledAfterCleanup", true)
            chk("heldNativeCancel.poisonCloseRequired", cpoison.recoveryRequired)
            chk("heldNativeCancel.noAck", acks.values.isEmpty)
            _ = await dec.closeAndReport(session: sess(301))
        }
        // 2. held-native CLOSE: close issued externally during the hold. Registration barrier is
        //    OBSERVABLE, not slept: close() calls seekState.requestClose() synchronously as its
        //    first statement (decoder close(), contract requestClose sets closing under the state
        //    lock), and currentBinding() returns nil iff closing||poisoned (coordinator
        //    currentBinding). Polling currentBinding()==nil therefore OBSERVES the actual
        //    close registration before the gate is released; a timeout FAILS loudly.
        case2: do {
            let gate = Gate(); let acks = AckBox()
            let dec = try await openReal(KIT, 302, .init(beforeNativeCall: { gate.hold($0) }))
            let driver = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            let probe = CompletionProbe()
            let closer = Task { try? await dec.close(); probe.mark() }
            var registered = false
            for _ in 0..<5000 {   // bounded 5s poll on ACTUAL close state, not a fixed sleep
                if dec.currentBinding() == nil { registered = true; break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            chk("heldNativeClose.closeRegisteredObserved", registered)
            chk("heldNativeClose.stillHeldBeforeRelease", dec.activeTransaction != nil && !probe.completed)
            gate.release.signal()
            let result = await out; await closer.value
            guard case .failedPoisoned(let receipt) = result else { chk("heldNativeClose.failedPoisoned", false); break case2 }
            chk("heldNativeClose.failedPoisoned", true)
            let poisoned: PoisonReport?
            switch receipt.outcome {
            case .cancelledAfterCleanup(_, let p): poisoned = p
            case .failed(_, _, _, let p): poisoned = p
            default: poisoned = nil
            }
            chk("heldNativeClose.poisonCloseRequired", poisoned?.recoveryRequired == true)
            chk("heldNativeClose.noAck", acks.values.isEmpty)
            chk("heldNativeClose.noRevisionAdvance", receipt.nextRevision == receipt.previousRevision)
            chk("heldNativeClose.closeCompleted", probe.completed)
        }
        // 3. held-native INTERRUPT: DISTINCT session-IO interrupt stimulus during the hold.
        //    The actual settle outcome is recorded verbatim; the only blanket invariants are
        //    settlement and no ACK unless the receipt itself is nativeReady.
        do {
            let gate = Gate(); let acks = AckBox()
            let dec = try await openReal(KIT, 303, .init(beforeNativeCall: { gate.hold($0) }))
            let driver = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            dec.requestInterrupt(session: sess(303))   // DISTINCT interrupt stimulus
            gate.release.signal()
            let result = await out
            var ackHonest = true
            if case .committed = result {} else if !acks.values.isEmpty { ackHonest = false }
            chk("heldNativeInterrupt.ackHonesty", ackHonest)
            print("INTERRUPT_OUTCOME \(result)")
            _ = await dec.closeAndReport(session: sess(303))
        }
        // 4. ACTUAL partial mutation: real av_seek_frame succeeds, real cleanup runs, failure is
        //    injected at the receipt boundary. Asserts bind the seam boundary: no hold needed -
        //    the receipt's own facts prove the real native ops ran (real rc, real cleanup flags).
        case4: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 304, .init(failAfterRealSeekAndCleanup: true))
            let driver = CoreSeekDriver()
            let result = await driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .failedPoisoned(let receipt) = result else { chk("partialMutation.failedPoisoned", false); break case4 }
            guard case .failed(let stage, let reason, let facts, let poison) = receipt.outcome else { chk("partialMutation.typedFailed", false); break case4 }
            chk("partialMutation.failedPoisoned", true)
            chk("partialMutation.stageCleanedUp", stage == .cleanedUp)
            chk("partialMutation.reasonPoisonedState", reason == .poisonedState)
            chk("partialMutation.realSeekRcZero", facts.avSeekReturn == 0)   // REAL seek succeeded
            chk("partialMutation.realCleanup", facts.flushObserved && facts.packetFeedReset && facts.decoderReset && facts.packetAccountingReconciled)
            chk("partialMutation.mutationPartial", receipt.mutation == .partial)
            chk("partialMutation.poisonCloseRequired", poison.recoveryRequired)
            chk("partialMutation.testInjectionLabel", poison.detail.contains("TEST INJECTION"))
            chk("partialMutation.noAck", acks.values.isEmpty)
            // 5. poisoned provider refuses every further reservation (no silent retry)
            let retry = await driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .admissionRefused(let r2) = retry else { chk("poisonedNoRetry.admissionRefused", false); break case4 }
            chk("poisonedNoRetry.admissionRefused", true)
            chk("poisonedNoRetry.noAck", acks.values.isEmpty)
            print("RETRY_REFUSAL \(r2)")
            _ = await dec.closeAndReport(session: sess(304))
        }


        case6: do {
            // 6. busy admission arbitration: a second seek during a held native call is refused
            //    busy, observably, with no ACK and no interference; the held seek then commits.
            let gate = Gate(); let acks = AckBox()
            let dec = try await openReal(KIT, 305, .init(beforeNativeCall: { gate.hold($0) }))
            let driver = CoreSeekDriver(); let driver2 = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            let second = await driver2.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .admissionRefused(let why) = second, why == .busy else { chk("busyWhileHeld.refusedBusy", false); break case6 }
            chk("busyWhileHeld.refusedBusy", true)
            gate.release.signal()
            let result = await out
            guard case .committed = result else { chk("busyWhileHeld.heldCommits", false); break case6 }
            chk("busyWhileHeld.heldCommits", true)
            chk("busyWhileHeld.singleAck", acks.values.count == 1)
            _ = await dec.closeAndReport(session: sess(305))
        }
        case7: do {
            // 7. origin-publication witness: a pull issued DURING a held seek parks on
        //    waitUntilSettled (never reaches the queue), and the first event it delivers after
        //    the seek carries the FULLY published post-seek origin (revision advanced).
        //    EventOrigin is nativeQueue-owned and finish()+publication are one synchronous
        //    queue turn (decoder lines ~309-332), so no reader can observe the interval.
            let gate = Gate(); let acks = AckBox()
            let dec = try await openReal(KIT, 306, .init(beforeNativeCall: { gate.hold($0) }))
            let driver = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            let box = PullBox()
            let pull = Task { box.set(await dec.nextEvent()) }
            try await Task.sleep(nanoseconds: 100_000_000)   // generous: the pull is settle-gated
            chk("originWitness.pullParkedWhileHeld", box.event == nil)
            gate.release.signal()
            let result = await out; _ = await pull.value
            guard case .committed = result else { chk("originWitness.seekCommitted", false); break case7 }
            chk("originWitness.seekCommitted", true)
            guard let evt = box.event else { chk("originWitness.eventDelivered", false); break case7 }
            chk("originWitness.eventDelivered", true)
            let rev: SeekRevision? = switch evt {
            case .frameDecoded(let o, _): o.providerRevision
            case .drained(let o): o.providerRevision
            case .endOfStream(let o): o.providerRevision
            case .failed(let o, _, _): o.providerRevision
            case .feedSaturated(let o, _): o.providerRevision
            case .opened(let o, _, _, _): o.providerRevision
            case .interrupted(let o): o.providerRevision
            case .closed(let o): o.providerRevision
            }
            let two = try SeekRevision(rawValue: 2)
            chk("originWitness.postSeekRevision", rev == two)
            print("ORIGIN_EVENT \(evt)")
            _ = await dec.closeAndReport(session: sess(306))
        }


        // 8. queued CLOSE at pre-validation: hold at beforeQueuedValidation (performSeek entry,
        //    pre-queueRefusal, outside the state lock), register close via the OBSERVED
        //    currentBinding()==nil predicate, release. Expected ACTUAL shape (shipped code):
        //    queueRefusal .closed -> finish arbitration cancelled -> cancelledNoMutation
        //    (.requested), mutation none, stage preSeek, no native entry (beforeNativeCall
        //    tripwire stays 0), no ACK, no revision advance, close settles.
        case8: do {
            let gate = Gate(); let acks = AckBox(); let trip = Tripwire()
            let dec = try await openReal(KIT, 307, .init(beforeQueuedValidation: { gate.hold($0) },
                                                         beforeNativeCall: { _ in trip.hit() }))
            let driver = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            let probe = CompletionProbe()
            let closer = Task { try? await dec.close(); probe.mark() }
            var registered = false
            for _ in 0..<5000 {
                if dec.currentBinding() == nil { registered = true; break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            chk("queuedClose.closeRegisteredObserved", registered)
            chk("queuedClose.stillHeldBeforeRelease", dec.activeTransaction != nil && !probe.completed)
            gate.release.signal()
            let result = await out; await closer.value
            guard case .noMutation(let receipt) = result else { chk("queuedClose.noMutation", false); break case8 }
            chk("queuedClose.noMutation", true)
            guard case .cancelledNoMutation(let reason) = receipt.outcome, reason == .requested else { chk("queuedClose.cancelledNoMutationRequested", false); break case8 }
            chk("queuedClose.cancelledNoMutationRequested", true)
            chk("queuedClose.mutationNone", receipt.mutation == .none)
            chk("queuedClose.stagePreSeek", receipt.reachedStage == .preSeek)
            chk("queuedClose.arbitrationCancel", receipt.arbitration == .cancellationRequested)
            chk("queuedClose.noRevisionAdvance", receipt.nextRevision == receipt.previousRevision)
            chk("queuedClose.noNativeEntry", trip.count == 0)
            chk("queuedClose.noAck", acks.values.isEmpty)
            chk("queuedClose.closeSettles", probe.completed)
        }
        // 9. queued SESSION-IO POISON at pre-validation: requestInterrupt registers SYNCHRONOUSLY
        //    (decoder requestInterrupt poisons the session under the lock on the caller thread),
        //    so no registration poll is needed. Same expected no-mutation shape as case 8.
        case9: do {
            let gate = Gate(); let acks = AckBox(); let trip = Tripwire()
            let dec = try await openReal(KIT, 308, .init(beforeQueuedValidation: { gate.hold($0) },
                                                         beforeNativeCall: { _ in trip.hit() }))
            let driver = CoreSeekDriver()
            async let out = driver.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            dec.requestInterrupt(session: sess(308))   // synchronous poison registration
            gate.release.signal()
            let result = await out
            guard case .noMutation(let receipt) = result else { chk("queuedPoison.noMutation", false); break case9 }
            chk("queuedPoison.noMutation", true)
            guard case .cancelledNoMutation(let reason) = receipt.outcome, reason == .requested else { chk("queuedPoison.cancelledNoMutationRequested", false); break case9 }
            chk("queuedPoison.cancelledNoMutationRequested", true)
            chk("queuedPoison.mutationNone", receipt.mutation == .none)
            chk("queuedPoison.noNativeEntry", trip.count == 0)
            chk("queuedPoison.noRevisionAdvance", receipt.nextRevision == receipt.previousRevision)
            chk("queuedPoison.noAck", acks.values.isEmpty)
            _ = await dec.closeAndReport(session: sess(308))
        }

        print("ADVERSARIAL_FINAL pass=\(passes) fail=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
