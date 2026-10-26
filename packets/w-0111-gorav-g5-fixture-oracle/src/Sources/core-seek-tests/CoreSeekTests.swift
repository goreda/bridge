import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVPlaybackCore

// S5 core-contract adversarial coverage (FAKE provider seam). This suite proves CORE behavior
// (ACK-only-on-nativeReady, typed refusals, no-wrap mints) - it does NOT close the REAL
// held-native cancel/close/interrupt, actual partial-mutation injection, native-queue race, or
// real multi-pull drain gaps; those need the actual decoder path (separate evidence).

final class AckLog: @unchecked Sendable {
    private let l = NSLock(); private var _revs: [SeekRevision] = []; private var _n = 0
    var revs: [SeekRevision] { l.lock(); defer { l.unlock() }; return _revs }
    var count: Int { l.lock(); defer { l.unlock() }; return _n }
    func add(_ r: SeekRevision) { l.lock(); _revs.append(r); _n += 1; l.unlock() }
    func bump() { l.lock(); _n += 1; l.unlock() }
}
var pass = 0, fail = 0
func chk(_ name: String, _ cond: Bool) {
    if cond { pass += 1; print("PASS \(name)") } else { fail += 1; print("FAIL \(name)") }
}

let token = try! SourceToken(instanceID: 7, openGeneration: 1)
let sess = try! SeekSessionID(rawValue: 3)
let rev1 = SeekRevision.atOpen

final class FakeTxn: SeekTransaction, @unchecked Sendable {
    let identity: SeekEventIdentity
    let correlationID: SeekCorrelationID
    let session: SeekSessionID
    let request: SeekRequest
    let reservedRevision: SeekRevision
    let makeReceipt: @Sendable (SeekRequest, SeekEventIdentity, SeekRevision) -> SeekReceipt
    let cancelFlag = NSLock(); var cancelled = false
    var executeCalled = 0
    init(request: SeekRequest, reserved: SeekRevision,
         _ mk: @escaping @Sendable (SeekRequest, SeekEventIdentity, SeekRevision) -> SeekReceipt) {
        self.request = request; self.correlationID = request.correlationID; self.session = request.session
        self.reservedRevision = reserved
        self.identity = SeekEventIdentity(source: request.source, transactionID: try! SeekTransactionID(rawValue: 99))
        self.makeReceipt = mk
    }
    func execute() throws { executeCalled += 1 }
    func completion() async -> SeekReceipt { makeReceipt(request, identity, reservedRevision) }
    func requestCancellation() { cancelFlag.lock(); cancelled = true; cancelFlag.unlock() }
}

enum FakeMode {
    case ready                       // completion -> nativeReady (ACK path)
    case heldCancel                  // native call "held": only requestCancellation settles it -> cancelledNoMutation(.requested)
    case failInject                  // completion -> .failed poison closeRequired (partial mutation injected)
    case staleThrow, closedThrow     // admission-time throws
}

final class FakeProvider: CoreSeekProvider, @unchecked Sendable {
    var mode: FakeMode
    var binding: (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?
    init(_ mode: FakeMode) { self.mode = mode; self.binding = (token, sess, rev1) }
    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)? { binding }
    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction {
        switch mode {
        case .staleThrow: throw SeekRefusal.stale(expected: request.expectedRevision, actual: try! SeekRevision(rawValue: 2))
        case .closedThrow: throw SeekRefusal.closed
        default:
            let reserved = try! request.expectedRevision.advanced()
            let m = mode
            return FakeTxn(request: request, reserved: reserved) { req, id, rev in
                switch m {
                case .ready:
                    return SeekReceipt(identity: id, correlationID: req.correlationID, session: req.session,
                        request: req, previousRevision: rev1, nextRevision: rev, reachedStage: .cleanedUp,
                        arbitration: .nativeReadyObserved, mutation: .completedClean, resumePolicy: .resumeFromNativePosition,
                        outcome: .nativeReady(facts: NativeSeekFacts(avSeekReturn: 0, flagsApplied: 1,
                            resolvedStreamIndex: 0, requestedTicks: 100, resolvedStreamTimebase: nil,
                            startOriginTicks: 0, flushObserved: true, packetFeedReset: true, decoderReset: true,
                            packetsReleased: 1, packetAccountingReconciled: true)))
                case .heldCancel:
                    return SeekReceipt(identity: id, correlationID: req.correlationID, session: req.session,
                        request: req, previousRevision: rev1, nextRevision: rev1, reachedStage: .preSeek,
                        arbitration: .cancellationRequested, mutation: .none, resumePolicy: .unchangedCoreGated,
                        outcome: .cancelledNoMutation(reason: .requested))
                default:
                    return SeekReceipt(identity: id, correlationID: req.correlationID, session: req.session,
                        request: req, previousRevision: rev1, nextRevision: rev1, reachedStage: .cleanedUp,
                        arbitration: .none, mutation: .partial, resumePolicy: .closedRequired,
                        outcome: .failed(stage: .cleanedUp, reason: .avError(code: -5),
                            facts: NativeSeekFacts(avSeekReturn: -5, flagsApplied: 1, resolvedStreamIndex: 0,
                                requestedTicks: 100, resolvedStreamTimebase: nil, startOriginTicks: 0,
                                flushObserved: true, packetFeedReset: true, decoderReset: true,
                                packetsReleased: 1, packetAccountingReconciled: true),
                            poison: .closeRequired("injected partial mutation")))
                }
            }
        }
    }
}

@main struct CoreSeekTests {
    static func main() async {
        let pos = try! RationalTime(value: 1, timescale: 1)

        // 1. nativeReady -> ACK exactly once with the ADOPTED provider-issued revision
        do {
            let driver = CoreSeekDriver(); let acks = AckLog()
            let out = await driver.seek(on: FakeProvider(.ready), position: pos) { rev, _ in acks.add(rev) }
            if case .committed = out { chk("ready.committed", true) } else { chk("ready.committed", false) }
            chk("ready.ackOnce", acks.count == 1)
            chk("ready.ackAdoptedRev2", acks.revs.first?.rawValue == 2)
        }
        // 2. held-native cancellation settles as noMutation, NO ACK, revision untouched
        do {
            let driver = CoreSeekDriver(); let acks = AckLog()
            let out = await driver.seek(on: FakeProvider(.heldCancel), position: pos) { _, _ in acks.bump() }
            if case .noMutation(let r) = out, case .cancelledNoMutation(reason: .requested) = r.outcome {
                chk("held.noMutation", true); chk("held.revUnchanged", r.nextRevision == r.previousRevision)
            } else { chk("held.noMutation", false); chk("held.revUnchanged", false) }
            chk("held.noAck", acks.count == 0)
        }
        // 3. injected partial-mutation failure -> failedPoisoned, closeRequired, NO ACK
        do {
            let driver = CoreSeekDriver(); let acks = AckLog()
            let out = await driver.seek(on: FakeProvider(.failInject), position: pos) { _, _ in acks.bump() }
            if case .failedPoisoned(let r) = out, case .failed(_, _, _, let poison) = r.outcome {
                chk("inject.poison", true); chk("inject.closeRequired", poison.recoveryPath == .closeRequired)
                chk("inject.revUnchanged", r.nextRevision == r.previousRevision)
            } else { chk("inject.poison", false); chk("inject.closeRequired", false); chk("inject.revUnchanged", false) }
            chk("inject.noAck", acks.count == 0)
        }
        // 4. queue-stale race -> typed .stale admission refusal, NO ACK
        do {
            let driver = CoreSeekDriver(); let acks = AckLog()
            let out = await driver.seek(on: FakeProvider(.staleThrow), position: pos) { _, _ in acks.bump() }
            if case .admissionRefused(let why) = out, why == .stale { chk("stale.typed", true) } else { chk("stale.typed", false) }
            chk("stale.noAck", acks.count == 0)
        }
        // 5. multi-pull closed drain: repeated seeks after close all typed .closed, NO ACK, mints never wrap
        do {
            let driver = CoreSeekDriver(); let acks = AckLog()
            for _ in 0..<3 {
                let out = await driver.seek(on: FakeProvider(.closedThrow), position: pos) { _, _ in acks.bump() }
                guard case .admissionRefused(let why) = out, why == .closed else { chk("closed.typed", false); break }
            }
            chk("closed.drainTyped", true); chk("closed.noAck", acks.count == 0)
        }
        // 6. correlation mint exhaustion is a typed refusal, never a wrap
        do {
            let driver = CoreSeekDriver(testSeed: UInt64.max, queueTurn: UInt64.max); let acks = AckLog()
            let out = await driver.seek(on: FakeProvider(.ready), position: pos) { _, _ in acks.bump() }
            if case .admissionRefused(let why) = out, why == .correlationExhausted { chk("mint.exhausted", true) } else { chk("mint.exhausted", false) }
            chk("mint.noAckOnExhaust", acks.count == 0)
        }
        print("FINAL pass=\(pass) fail=\(fail)")
        exit(fail == 0 ? 0 : 1)
    }
}
