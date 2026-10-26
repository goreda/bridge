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


func arithmeticAndValueTests() throws {
// floorTicks: exact
chk("floorTicks.exact", try RationalTime(value: 3, timescale: 1).floorTicks(toTimescale: 1000) == 3000)
// inexact positive floor: 7/2 s -> 3.5 -> 3500 exact at ms; use 1/3 -> 333 (floor)
chk("floorTicks.posFloor", try RationalTime(value: 1, timescale: 3).floorTicks(toTimescale: 1000) == 333)
// negative numerator: -1/2 s -> -500ms exact
chk("floorTicks.negExact", try RationalTime(value: -1, timescale: 2).floorTicks(toTimescale: 1000) == -500)
// negative inexact: -1/3 s -> -333.33 -> floor = -334 (mathematical floor, NOT truncation -333)
chk("floorTicks.negFloor", try RationalTime(value: -1, timescale: 3).floorTicks(toTimescale: 1000) == -334)
// negative origin in stream ticks: origin -1000 ticks at 90000, convert 1s -> 90000
chk("floorTicks.streamTb", try RationalTime(value: 1, timescale: 1).floorTicks(toTimescale: 90000) == 90000)
// overflow: Int64.max seconds at timescale 100000 -> overflow thrown
do { _ = try RationalTime(value: Int64.max, timescale: 1).floorTicks(toTimescale: 100000); chk("floorTicks.overflow", false) }
catch SeekTimeError.overflow { chk("floorTicks.overflow", true) } catch { chk("floorTicks.overflow", false) }
// invalid timescale is a TIME error, not identity error
do { _ = try RationalTime(value: 1, timescale: 0); chk("timescale.err", false) }
catch SeekTimeError.invalidTimescale { chk("timescale.err", true) } catch { chk("timescale.err", false) }
// Int64.min value does not trap
if let t = try? RationalTime(value: Int64.min, timescale: 1) {
    chk("floorTicks.int64min.nocrash", (try? t.floorTicks(toTimescale: 1)) == Int64.min)
} else { chk("floorTicks.int64min.nocrash", false) }

// rational equality/hash/Comparable consistency (finding 3)
let half = try! RationalTime(value: 1, timescale: 2), quarter2 = try! RationalTime(value: 2, timescale: 4)
chk("rat.eqCross", half == quarter2)
chk("rat.hashEq", half.hashValue == quarter2.hashValue)
chk("rat.notLess", !(half < quarter2) && !(quarter2 < half))
chk("rat.thirdLtHalf", (try! RationalTime(value: 1, timescale: 3)) < half)
chk("rat.negLt", (try! RationalTime(value: -1, timescale: 2)) < (try! RationalTime(value: 1, timescale: 4)))
chk("rat.negNeg", (try! RationalTime(value: -3, timescale: 4)) < (try! RationalTime(value: -1, timescale: 2)))
// normalized forms
chk("rat.norm", (try! RationalTime(value: -6, timescale: 4)).normalized == (try! RationalTime(value: -3, timescale: 2)))
chk("rat.normZero", (try! RationalTime(value: 0, timescale: 5)).normalized == (try! RationalTime(value: 0, timescale: 1)))
// rescaled checked
chk("rat.rescale", (try? (try! RationalTime(value: -1, timescale: 3)).rescaled(to: 1000)) == (try! RationalTime(value: -334, timescale: 1000)))

// mint: reference semantics, monotonic, no duplicate issuance across "copies"
let mint = TransactionIDMint()
let a = try! mint.issue(), b = try! mint.issue()
let alias = mint  // reference, not a value copy
let c = try! alias.issue()
chk("mint.monotonic", a.rawValue == 1 && b.rawValue == 2 && c.rawValue == 3)

// identity validation
do { _ = try SourceToken(instanceID: 0, openGeneration: 1); chk("token.zero", false) } catch { chk("token.zero", true) }
do { _ = try SeekRevision(rawValue: 0); chk("rev.zero", false) } catch { chk("rev.zero", true) }
chk("rev.advance", try! SeekRevision.atOpen.advanced().rawValue == 2)
chk("composite.distinctSources", SeekEventIdentity(source: try! SourceToken(instanceID: 1, openGeneration: 1), transactionID: a) != SeekEventIdentity(source: try! SourceToken(instanceID: 2, openGeneration: 1), transactionID: a))

// poison invariants (finding 8): only two legal combinations for mutated non-nativeReady
chk("poison.cleanNativeReady", PoisonReport.cleanNativeReady.recoveryPath == .notRequired && !PoisonReport.cleanNativeReady.recoveryRequired)
chk("poison.closeRequired", PoisonReport.closeRequired("x").recoveryRequired && PoisonReport.closeRequired("x").recoveryPath == .closeRequired)

print("SUMMARY pass=\(pass) fail=\(fail)")

// ---- v4 delta 1: real rational timebase (1001/30000), media-relative, checked ----
// 1s at tb 1001/30000: floor(1 * 30000 / (1 * 1001)) = floor(29.970) = 29
chk("tb1001.1s", try (try! RationalTime(value: 1, timescale: 1)).floorTicks(toTimebaseNumerator: 1001, denominator: 30000) == 29)
// 10s: floor(10*30000/1001) = floor(299.700) = 299
chk("tb1001.10s", try (try! RationalTime(value: 10, timescale: 1)).floorTicks(toTimebaseNumerator: 1001, denominator: 30000) == 299)
// fractional source: 1001/30000 s (exactly one tick) at timescale 30000: floor(1001 * 30000 / (30000 * 1001)) = 1
chk("tb1001.onetick", try (try! RationalTime(value: 1001, timescale: 30000)).floorTicks(toTimebaseNumerator: 1001, denominator: 30000) == 1)
// negative value (negative ORIGIN arithmetic is legal): -1/2 s -> floor(-0.5*30000/1001) = floor(-14.985) = -15
chk("tb1001.negFloor", try (try! RationalTime(value: -1, timescale: 2)).floorTicks(toTimebaseNumerator: 1001, denominator: 30000) == -15)
// invalid timebase rejected as TIME error
do { _ = try (try! RationalTime(value: 1, timescale: 1)).floorTicks(toTimebaseNumerator: 0, denominator: 30000); chk("tb.invalid", false) }
catch SeekTimeError.invalidTimescale { chk("tb.invalid", true) } catch { chk("tb.invalid", false) }
// overflow: huge value * den -> typed overflow, no wrap
do { _ = try (try! RationalTime(value: Int64.max, timescale: 1)).floorTicks(toTimebaseNumerator: 1, denominator: Int64(Int32.max)); chk("tb.overflow", false) }
catch SeekTimeError.overflow { chk("tb.overflow", true) } catch { chk("tb.overflow", false) }
// checked origin sum: negative origin allowed, overflow typed
chk("origin.negok", (try? RationalTime.checkedOriginSum(deltaTicks: 100, startTimeTicks: -1000)) == -900)
do { _ = try RationalTime.checkedOriginSum(deltaTicks: Int64.max, startTimeTicks: 1); chk("origin.overflow", false) }
catch SeekTimeError.overflow { chk("origin.overflow", true) } catch { chk("origin.overflow", false) }
// backward-compat wrapper: Int32 timescale path unchanged (1/3s @1000 = 333)
chk("tb.wrapper", try (try! RationalTime(value: 1, timescale: 3)).floorTicks(toTimescale: 1000) == 333)

// ---- v4 delta 2: admitted refusedNoMutation DISTINCT from cancelledNoMutation ----
let id1 = SeekEventIdentity(source: try! SourceToken(instanceID: 1, openGeneration: 1), transactionID: try! SeekTransactionID(rawValue: 1))
let rev1 = SeekRevision.atOpen
let req = SeekRequest(correlationID: try! SeekCorrelationID(rawValue: 9, queueTurn: 4),
                      session: try! SeekSessionID(rawValue: 3), source: id1.source,
                      target: SeekTarget(position: try! RationalTime(value: 1, timescale: 1), rounding: .floorToKeyframe, requestedFlags: 0),
                      expectedRevision: rev1)
let facts0 = NativeSeekFacts(avSeekReturn: nil, flagsApplied: 0, resolvedStreamIndex: nil, requestedTicks: nil,
                             resolvedStreamTimebase: nil, startOriginTicks: nil, flushObserved: false,
                             packetFeedReset: false, decoderReset: false, packetsReleased: nil, packetAccountingReconciled: false)
let refused = SeekReceipt(identity: id1, correlationID: req.correlationID, session: req.session, request: req,
                          previousRevision: rev1, nextRevision: rev1, reachedStage: .preSeek, arbitration: .none,
                          mutation: .none, resumePolicy: .unchangedCoreGated,
                          outcome: .refusedNoMutation(reason: .stale(expected: rev1, actual: try! rev1.advanced())))
let cancelled = SeekReceipt(identity: id1, correlationID: req.correlationID, session: req.session, request: req,
                            previousRevision: rev1, nextRevision: rev1, reachedStage: .reserved, arbitration: .cancellationRequested,
                            mutation: .none, resumePolicy: .unchangedCoreGated,
                            outcome: .cancelledNoMutation(reason: .requested))
var distinct = false, refusedRevUnchanged = false, cancelReasons = 0
if case .refusedNoMutation(let r) = refused.outcome, case .stale(let e, let a) = r { distinct = true; refusedRevUnchanged = (refused.nextRevision == refused.previousRevision && e.rawValue == 1 && a.rawValue == 2) }
chk("nomut.refusedDistinctStale", distinct && refusedRevUnchanged)
if case .cancelledNoMutation = cancelled.outcome { cancelReasons += 1 }
chk("nomut.cancelDistinct", cancelReasons == 1 && cancelled.resumePolicy == .unchangedCoreGated)
chk("nomut.cancelReasonEnum", SeekReceipt.CancelReason.abandoned.rawValue == "abandoned" && SeekReceipt.CancelReason.close.rawValue == "close")
print("SUMMARY2 pass=\(pass) fail=\(fail)")

}


// Deterministic state-machine tests execute production ProviderSeekCoordinator, not a second model.
final class RecordBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProviderSeekReservation?
    func store(_ r: ProviderSeekReservation) { lock.lock(); value = r; lock.unlock() }
    func get() -> ProviderSeekReservation? { lock.lock(); defer { lock.unlock() }; return value }
}
func openedEngine(_ instance: UInt64 = 101) throws -> (ProviderSeekCoordinator, SourceToken, SeekSessionID) {
    let e = ProviderSeekCoordinator()
    let t = try SourceToken(instanceID: instance, openGeneration: 1)
    let session = try SeekSessionID(rawValue: 77)
    e.opened(token: t, session: session,
        descriptor: SeekSourceDescriptor(source: t, seekable: true, originKnown: true,
            startOrigin: try RationalTime(value: 0, timescale: 1), duration: nil, videoStreamIndex: 0,
            streamTimebase: try RationalTime(value: 1001, timescale: 30000)),
        capabilities: SeekCapabilities(seekable: true, supportedRoundings: [.floorToKeyframe], supportedFlags: 1, originKnown: true))
    return (e,t,session)
}
func request(_ token: SourceToken, _ session: SeekSessionID, _ n: UInt64 = 1,
             _ revision: SeekRevision = .atOpen) throws -> SeekRequest {
    SeekRequest(correlationID: try SeekCorrelationID(rawValue: n, queueTurn: n), session: session,
        source: token, target: SeekTarget(position: try RationalTime(value: 1, timescale: 1),
            rounding: .floorToKeyframe, requestedFlags: 1), expectedRevision: revision)
}
func readyReceipt(_ r: ProviderSeekReservation, cancelled: Bool, failed: Bool = false) -> SeekReceipt {
    let f = NativeSeekFacts(avSeekReturn: failed ? -5 : 0, flagsApplied: 1, resolvedStreamIndex: 0,
        requestedTicks: 29, resolvedStreamTimebase: try! RationalTime(value: 1001, timescale: 30000),
        startOriginTicks: 0, flushObserved: true, packetFeedReset: true, decoderReset: true,
        packetsReleased: 1, packetAccountingReconciled: true)
    let outcome: SeekReceipt.Outcome = failed
        ? .failed(stage: .cleanedUp, reason: .avError(code: -5), facts: f, poison: .closeRequired("injected provider error"))
        : (cancelled ? .cancelledAfterCleanup(facts: f, poison: .closeRequired("cancelled")) : .nativeReady(facts: f))
    return SeekReceipt(identity: r.identity, correlationID: r.request.correlationID, session: r.request.session,
        request: r.request, previousRevision: r.request.expectedRevision,
        nextRevision: !cancelled && !failed ? r.reservedRevision : r.request.expectedRevision,
        reachedStage: .cleanedUp, arbitration: cancelled ? .cancellationRequested : (failed ? .none : .nativeReadyObserved),
        mutation: failed ? .partial : .completedClean,
        resumePolicy: !cancelled && !failed ? .resumeFromNativePosition : .closedRequired, outcome: outcome)
}
func productionEngineTests() async throws {
    let (engine,token,session) = try openedEngine()
    let box = RecordBox()
    var first: (any SeekTransaction)? = try engine.tryBegin(request(token,session)) { box.store($0) }
    chk("engine.reservedBusy", engine.activeTransaction == first!.identity && !engine.outputAllowed)
    do { _ = try engine.tryBegin(request(token,session,2)) { _ in }; chk("engine.busyRefused", false) }
    catch SeekRefusal.busy { chk("engine.busyRefused", true) }
    first!.requestCancellation()
    let cancelled = await first!.completion()
    if case .cancelledNoMutation(reason: .requested) = cancelled.outcome { chk("engine.preexecuteCancel", true) }
    else { chk("engine.preexecuteCancel", false) }
    chk("engine.cancelNoOutputAdvance", engine.currentBinding()?.revision == .atOpen && engine.activeTransaction == nil)
    do { try first!.execute(); chk("engine.executeAfterSettlement", false) }
    catch SeekRefusal.alreadyExecuted { chk("engine.executeAfterSettlement", true) }
    first = nil
    var abandoned: (any SeekTransaction)? = try engine.tryBegin(request(token,session,2)) { box.store($0) }
    let abandonedID = abandoned!.identity
    abandoned = nil
    chk("engine.abandonReleases", engine.activeTransaction == nil && abandonedID.source == token)
    let held = try engine.tryBegin(request(token,session,3)) { box.store($0) }
    try held.execute()
    let record = box.get()!
    held.requestCancellation()
    chk("engine.cancelInFlightRetains", engine.activeTransaction == held.identity && !engine.outputAllowed)
    engine.finish(record) { readyReceipt(record, cancelled: $0) }
    let after = await held.completion()
    if case .cancelledAfterCleanup(_, let poison) = after.outcome { chk("engine.mutatedCancelPoison", poison.recoveryRequired && poison.recoveryPath == .closeRequired) }
    else { chk("engine.mutatedCancelPoison", false) }
    chk("engine.poisonNoBindingOrOutput", engine.currentBinding() == nil && !engine.outputAllowed)
    let repeated = await held.completion()
    chk("engine.repeatCompletion", repeated.identity == after.identity && repeated.nextRevision == after.nextRevision)
    let (e2,t2,s2) = try openedEngine(102)
    let b2 = RecordBox()
    let ready = try e2.tryBegin(request(t2,s2)) { b2.store($0) }
    try ready.execute(); let r2 = b2.get()!
    e2.finish(r2) { readyReceipt(r2, cancelled: $0) }
    ready.requestCancellation()
    let result = await ready.completion()
    if case .nativeReady = result.outcome { chk("engine.readyWinsLateCancel", true) }
    else { chk("engine.readyWinsLateCancel", false) }
    chk("engine.readyRevisionAdvance", e2.currentBinding()?.revision.rawValue == 2 && e2.outputAllowed)
    chk("engine.twoSourceIDsDistinct", ready.identity != held.identity)
    do { _ = try e2.tryBegin(request(t2,s2,2)) { _ in }; chk("engine.staleRefusal", false) }
    catch SeekRefusal.stale { chk("engine.staleRefusal", true) }
    e2.requestClose()
    do { _ = try e2.tryBegin(request(t2,s2,3,try SeekRevision(rawValue: 2))) { _ in }; chk("engine.closeRefuses", false) }
    catch SeekRefusal.closed { chk("engine.closeRefuses", true) }
    let (e3,t3,s3) = try openedEngine(103)
    let b3 = RecordBox()
    let failing = try e3.tryBegin(request(t3,s3)) { b3.store($0) }
    try failing.execute(); let r3 = b3.get()!
    e3.finish(r3) { readyReceipt(r3, cancelled: $0, failed: true) }
    let failure = await failing.completion()
    chk("engine.partialFailureNoAdvance", failure.nextRevision == .atOpen && !e3.outputAllowed)
    let (e4,t4,s4) = try openedEngine(104)
    let lease = try e4.tryBegin(request(t4,s4)) { _ in }
    e4.requestClose()
    let closed = await lease.completion()
    if case .cancelledNoMutation(reason: .close) = closed.outcome { chk("engine.reservedCloseSettlement", true) }
    else { chk("engine.reservedCloseSettlement", false) }
}

// Arithmetic compatibility edges: macOS13-compatible wide arithmetic, including a divisor >64bits.
func wideArithmeticEdges() {
    chk("wide.largeDivisor", (try? RationalTime(value: Int64.max, timescale: Int32.max)
        .floorTicks(toTimebaseNumerator: Int64.max, denominator: Int64.max)) == Int64.max / Int64(Int32.max))
    chk("wide.negativeTinyFloor", (try? RationalTime(value: -1, timescale: Int32.max)
        .floorTicks(toTimebaseNumerator: Int64.max, denominator: 1)) == -1)
    chk("wide.minOverMax", (try? RationalTime(value: Int64.min, timescale: 1)
        .floorTicks(toTimebaseNumerator: Int64.max, denominator: 1)) == -2)
    chk("wide.maxIdentity", (try? RationalTime(value: Int64.max, timescale: 1)
        .floorTicks(toTimebaseNumerator: Int64.max, denominator: Int64.max)) == Int64.max)
    chk("wide.minIdentity", (try? RationalTime(value: Int64.min, timescale: 1)
        .floorTicks(toTimebaseNumerator: Int64.max, denominator: Int64.max)) == Int64.min)
}

func legacyModeTests() throws {
    let (e,t,s) = try openedEngine(201)
    chk("engine.claimLegacy", e.claimLegacy())
    do { _ = try e.tryBegin(request(t,s)) { _ in }; chk("engine.legacyMixRefused", false) }
    catch SeekRefusal.legacyRejected { chk("engine.legacyMixRefused", true) }
    let (e2,_,_) = try openedEngine(202)
    try e2.activateEvents()
    chk("engine.envelopeModeRefusesLegacy", !e2.claimLegacy())
}

// Optional native fixture gate. Never reports native success when the fixture is absent.
func nativeProviderTests() async throws {
    guard let fixture = ProcessInfo.processInfo.environment["S5_SEEK_FIXTURE"] else {
        print("NOT_RUN native provider: S5_SEEK_FIXTURE missing")
        if ProcessInfo.processInfo.environment["S5_REQUIRE_NATIVE"] == "1" { chk("native.requiredFixture", false) }
        return
    }
    let decoder = FFmpegSoftwareDecoder()
    let root = URL(fileURLWithPath: fixture).deletingLastPathComponent().path
    try decoder.pinLocalRoots([root])
    let issued = PlaybackIdentityAuthority.shared.issue()!
    try await decoder.open(source: GorAVCore.SourceDescriptor(id: fixture, kind: .local, seekable: true), session: issued)
    guard let binding = decoder.currentBinding() else { chk("native.binding", false); return }
    chk("native.openRevision", binding.revision == .atOpen)
    var oldFrame: NativeFrame?
    for _ in 0..<100 {
        let event = await decoder.nextEvent()
        if case .frameDecoded(let origin, let frame) = event {
            chk("native.initialOrigin", origin.source == binding.token && origin.providerRevision == .atOpen)
            oldFrame = frame; break
        }
    }
    let req = SeekRequest(correlationID: try SeekCorrelationID(rawValue: 1, queueTurn: 1), session: binding.session,
        source: binding.token, target: SeekTarget(position: try RationalTime(value: 1, timescale: 1),
            rounding: .floorToKeyframe, requestedFlags: 1), expectedRevision: .atOpen)
    let transaction = try decoder.tryBegin(req)
    chk("native.reservedRevisionAdoption", transaction.reservedRevision.rawValue == 2)
    try transaction.execute()
    let result = await transaction.completion()
    if case .nativeReady(let facts) = result.outcome {
        chk("native.actualReceipt", facts.avSeekReturn.map { $0 >= 0 } == true && facts.flushObserved && facts.packetFeedReset && facts.packetAccountingReconciled)
    } else { chk("native.actualReceipt", false) }
    chk("native.receiptBinding", result.identity == transaction.identity && result.session == binding.session && result.nextRevision.rawValue == 2)
    if let oldFrame {
        let metadata = await decoder.retainedHandleMetadata(handle: oldFrame.handle, session: issued)
        chk("native.oldHandleOrigin", metadata?.origin.providerRevision == .atOpen)
        let copy = await decoder.framePlaneCopy(handle: oldFrame.handle, session: issued)
        chk("native.oldHandleCopyAfterSeek", copy != nil)
        await decoder.releaseFrame(handle: oldFrame.handle, session: issued)
    } else { chk("native.oldFrameAvailable", false) }
    var postSeek = false
    for _ in 0..<100 {
        if case .frameDecoded(let origin, let frame) = await decoder.nextEvent() {
            postSeek = origin.providerRevision.rawValue == 2 && origin.requestOrigin == .transaction(transaction.identity.transactionID)
            await decoder.releaseFrame(handle: frame.handle, session: issued); break
        }
    }
    chk("native.newEventOrigin", postSeek)
    do { try await decoder.seek(toSeconds: 0, session: issued); chk("native.legacySeekRefused", false) }
    catch FFmpegSoftwareDecoder.SeekError.coordinatedMode { chk("native.legacySeekRefused", true) }
    if case .failed(let code, _) = await decoder.nextEvent(session: issued) { chk("native.legacyPullRefused", code == -19) }
    else { chk("native.legacyPullRefused", false) }
    try await decoder.close()
    if case .closed(let origin) = await decoder.nextEvent() { chk("native.closedOrigin", origin.source == binding.token) }
    else { chk("native.closedOrigin", false) }
}

@main enum SeekContractTestMain {
    static func main() async {
        do {
            try arithmeticAndValueTests()
            wideArithmeticEdges()
            try legacyModeTests()
            try await productionEngineTests()
            try await nativeProviderTests()
        } catch { chk("unexpectedError", false); print(String(describing: error)) }
        print("FINAL pass=\(pass) fail=\(fail)")
        if fail != 0 { exit(1) }
    }
}
