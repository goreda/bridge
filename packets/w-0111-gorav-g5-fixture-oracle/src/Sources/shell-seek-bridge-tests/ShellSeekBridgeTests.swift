// ShellSeekBridgeTests - REAL bridge + REAL adapter + REAL decoder v2 + REAL k3.
// Bridge-level coverage (Linux), honestly separate from the Mac-specific shell hunks.
import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVPlaybackCore

extension FFmpegSoftwareDecoder: CoreSeekProvider {}

private struct TestSrc: FrameSource {
    func nextEvent() async -> SourceEvent { .ended(.sourceEnded) }
}
private struct TestSink: FrameSink {
    func show(_ frame: SourceFrame) async -> Bool { true }
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool { true }
}
private struct TestClock: PlaybackClock { func nowSeconds() -> Double { 0 } }

private final class Gate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func hold(_: SeekEventIdentity) { entered.signal(); release.wait() }
}
private final class AckBox: @unchecked Sendable {
    private let lock = NSLock(); private var list: [SeekRevision] = []
    func add(_ r: SeekRevision) { lock.lock(); list.append(r); lock.unlock() }
    var values: [SeekRevision] { lock.lock(); defer { lock.unlock() }; return list }
}

@main private enum ShellSeekBridgeTests {
    static var passes = 0, failures = 0
    static func chk(_ n: String, _ c: Bool) { if c { passes += 1; print("PASS \(n)") } else { failures += 1; print("FAIL \(n)") } }
    static func originOf(_ evt: SeekProviderEvent<NativeFrame>) -> EventOrigin? {
        switch evt {
        case .opened(let o, _, _, _): return o
        case .frameDecoded(let o, _): return o
        case .drained(let o): return o
        case .endOfStream(let o): return o
        case .interrupted(let o): return o
        case .failed(let o, _, _): return o
        case .feedSaturated(let o, _): return o
        case .closed(let o): return o
        }
    }
    static func revOf(_ evt: SeekProviderEvent<NativeFrame>) -> SeekRevision? {
        switch evt {
        case .opened(let o, _, _, _): return o.providerRevision
        case .frameDecoded(let o, _): return o.providerRevision
        case .drained(let o): return o.providerRevision
        case .endOfStream(let o): return o.providerRevision
        case .interrupted(let o): return o.providerRevision
        case .failed(let o, _, _): return o.providerRevision
        case .feedSaturated(let o, _): return o.providerRevision
        case .closed(let o): return o.providerRevision
        }
    }

    static func sess(_ e: UInt64) -> SessionID { SessionID(uncheckedEpoch: e) }
    static func openReal(_ kit: String, _ epoch: UInt64, _ diag: FFmpegSoftwareDecoder.SeekDiagnostics? = nil) async throws -> FFmpegSoftwareDecoder {
        let d = diag.map { FFmpegSoftwareDecoder(testSeekDiagnostics: $0) } ?? FFmpegSoftwareDecoder()
        try d.pinLocalRoots([kit])
        try await d.open(source: SourceDescriptor(id: "\(kit)/fixtures/seekcheck-src.mp4", kind: .local, seekable: true), session: sess(epoch))
        return d
    }

    static func main() async throws {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let target = try! RationalTime(value: 1, timescale: 1)

        // 1+2. two sequential seeks: committedFlushed, revisions 2 then 3, one ACK each,
        //      resumePolicy resumeFromNativePosition, revision adopted from the receipt.
        seq: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 401)
            let bridge = ShellSeekBridge()
            let r1 = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .committedFlushed(let rc1, let ad1) = r1 else { chk("seq.firstCommittedFlushed", false); break seq }
            chk("seq.firstCommittedFlushed", true)
            chk("seq.adoptRev2", ad1 == (try SeekRevision(rawValue: 2)))
            chk("seq.resumeNative", rc1.resumePolicy == .resumeFromNativePosition)
            chk("seq.noActiveAfter", !bridge.hasActiveSeek)
            let r2 = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .committedFlushed(_, let ad2) = r2 else { chk("seq.secondCommittedFlushed", false); break seq }
            chk("seq.secondCommittedFlushed", true)
            chk("seq.adoptRev3", ad2 == (try SeekRevision(rawValue: 3)))
            chk("seq.twoAcks", acks.values.count == 2)
            // 3. consumer fence input: first post-seek event origin carries the adopted revision
            let evt = await dec.nextEvent()
            let fenceRev: SeekRevision? = switch evt {
            case .opened(let o, _, _, _): o.providerRevision
            case .frameDecoded(let o, _): o.providerRevision
            case .drained(let o): o.providerRevision
            case .endOfStream(let o): o.providerRevision
            case .interrupted(let o): o.providerRevision
            case .failed(let o, _, _): o.providerRevision
            case .feedSaturated(let o, _): o.providerRevision
            case .closed(let o): o.providerRevision
            }
            chk("fence.eventOriginRev3", fenceRev == (try SeekRevision(rawValue: 3)))
            _ = await dec.closeAndReport(session: sess(401))
        }
        // 4. cancel during held native via the bridge: requiresClose, cancelledAfterCleanup, no ACK.
        cancel: do {
            let gate = Gate(); let acks = AckBox()
            let dec = try await openReal(KIT, 402, .init(beforeNativeCall: { gate.hold($0) }))
            let bridge = ShellSeekBridge()
            async let out = bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            gate.entered.wait()
            chk("cancel.activeDuringHold", bridge.hasActiveSeek)
            bridge.cancelActiveSeek()
            gate.release.signal()
            let result = await out
            guard case .requiresClose(let receipt) = result else { chk("cancel.requiresClose", false); break cancel }
            chk("cancel.requiresClose", true)
            guard case .cancelledAfterCleanup = receipt.outcome else { chk("cancel.cancelledAfterCleanup", false); break cancel }
            chk("cancel.cancelledAfterCleanup", true)
            chk("cancel.closedRequired", receipt.resumePolicy == .closedRequired)
            chk("cancel.noAck", acks.values.isEmpty)
            _ = await dec.closeAndReport(session: sess(402))
        }
        // 5. injected partial after real seek: requiresClose; retry admissionRefused (poisoned).
        poison: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 403, .init(failAfterRealSeekAndCleanup: true))
            let bridge = ShellSeekBridge()
            let result = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .requiresClose(let receipt) = result else { chk("poison.requiresClose", false); break poison }
            chk("poison.requiresClose", true)
            chk("poison.closedRequired", receipt.resumePolicy == .closedRequired)
            let retry = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .admissionRefused = retry else { chk("poison.retryRefused", false); break poison }
            chk("poison.retryRefused", true)
            chk("poison.noAck", acks.values.isEmpty)
            _ = await dec.closeAndReport(session: sess(403))
        }


        // 6. CONSUMER FENCING PATH (actual, decoder-level): retained pre-seek events/handles and
        //    a delivered-but-unprocessed pre-seek frame all carry the OLD origin; the fence input
        //    (adopted revision) distinguishes every one of them from post-seek delivery. This
        //    covers the consumer path inputs - it is NOT shell-buffer proof (Mac hunks pending).
        fence: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 404)
            let bridge = ShellSeekBridge()
            // pull pre-seek: opened(rev1), then two frames retained (handles NOT released)
            var preRev: [SeekRevision] = []; var oldHandles: [UInt64] = []
            var gotOpened = false
            while oldHandles.count < 2 {
                switch await dec.nextEvent() {
                case .opened(let o, _, _, _): gotOpened = true; preRev.append(o.providerRevision)
                case .frameDecoded(let o, let f): preRev.append(o.providerRevision); oldHandles.append(f.handle)
                default: chk("fence.preSeekPulls", false); break fence
                }
            }
            chk("fence.preSeekOpened", gotOpened)
            // a delivered-but-unprocessed pre-seek frame (delayed across the seek)
            var delayedRev: SeekRevision?; var delayedHandle: UInt64?
            if case .frameDecoded(let o, let f) = await dec.nextEvent() { delayedRev = o.providerRevision; delayedHandle = f.handle }
            let result = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .committedFlushed(_, let adopted) = result else { chk("fence.committed", false); break fence }
            chk("fence.committed", true)
            // every pre-seek event (retained + delayed) is distinguishable by the fence
            chk("fence.retainedOldOrigin", preRev.count == 3 && preRev.allSatisfy { $0 != adopted })
            chk("fence.delayedOldOrigin", delayedRev != nil && delayedRev! != adopted)
            // retained old handles remain observable post-seek (observation-only, no claim)
            var digestOk = true
            for h in oldHandles { if await dec.frameDigest(handle: h, session: sess(404)) == nil { digestOk = false } }
            chk("fence.oldHandlesObservable", digestOk)
            // releasing old handles post-seek does not disturb the adopted session
            for h in oldHandles { await dec.releaseFrame(handle: h, session: sess(404)) }
            if let dh = delayedHandle { await dec.releaseFrame(handle: dh, session: sess(404)) }
            // first post-seek delivery carries the adopted revision
            let post = await dec.nextEvent()
            let postRev: SeekRevision? = switch post {
            case .opened(let o, _, _, _): o.providerRevision
            case .frameDecoded(let o, _): o.providerRevision
            case .drained(let o): o.providerRevision
            case .endOfStream(let o): o.providerRevision
            case .interrupted(let o): o.providerRevision
            case .failed(let o, _, _): o.providerRevision
            case .feedSaturated(let o, _): o.providerRevision
            case .closed(let o): o.providerRevision
            }
            chk("fence.postSeekAdopted", postRev == adopted)
            chk("fence.oneAck", acks.values.count == 1)
            _ = await dec.closeAndReport(session: sess(404))
        }


        // 7. FENCE BINDING (explicit mapping, fail closed): initial attach binding from the
        //    actual provider read; committed-seek rebind validated against the ACTUAL current
        //    binding; stale/mismatched anchors rejected; poison clears the fence.
        bind: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 405)
            let bridge = ShellSeekBridge()
            chk("bind.attachInitial", bridge.attach(to: dec))
            guard let initial = bridge.currentFence, case .initialOpen = initial.anchor else { chk("bind.initialAnchor", false); break bind }
            chk("bind.initialAnchor", true)
            chk("bind.initialRev1", initial.providerRevision == (try SeekRevision(rawValue: 1)))
            // a pre-seek delivered event admits under the initial binding
            let pre = await dec.nextEvent()
            if case .opened(let o, _, _, _) = pre { chk("bind.preSeekAdmits", initial.admits(o)) }
            else { chk("bind.preSeekAdmits", false) }
            // committed seek rebinds with a committedSeek anchor
            let r1 = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .committedFlushed = r1, let b1 = bridge.currentFence,
                  case .committedSeek = b1.anchor else { chk("bind.committedAnchor", false); break bind }
            chk("bind.committedAnchor", true)
            chk("bind.rev2", b1.providerRevision == (try SeekRevision(rawValue: 2)))
            // the old initial binding no longer admits post-seek delivery; the new one does
            let post = await dec.nextEvent()
            if case .frameDecoded(_, let f) = post { await dec.releaseFrame(handle: f.handle, session: sess(405)) }
            if let o = originOf(post) {
                chk("bind.oldBindingRejects", !initial.admits(o))
                chk("bind.newBindingAdmits", b1.admits(o))
            } else { chk("bind.oldBindingRejects", false); chk("bind.newBindingAdmits", false) }
            // a foreign-session origin admits under NEITHER binding (identity, not numeral)
            let foreign = EventOrigin(session: try! SeekSessionID(rawValue: 9999), source: b1.source,
                                      providerRevision: b1.providerRevision, requestOrigin: .initialOpen)
            chk("bind.foreignSessionRejects", !b1.admits(foreign))
            // second seek: binding replaced; the rev2 binding stops admitting
            let r2 = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .committedFlushed = r2, let b2 = bridge.currentFence else { chk("bind.rebind", false); break bind }
            chk("bind.rebind", true)
            chk("bind.rev3", b2.providerRevision == (try SeekRevision(rawValue: 3)))
            let post2 = await dec.nextEvent()
            if case .frameDecoded(_, let f) = post2 { await dec.releaseFrame(handle: f.handle, session: sess(405)) }
            if let o = originOf(post2) {
                chk("bind.priorBindingRejects", !b1.admits(o))
                chk("bind.currentAdmits", b2.admits(o))
            } else { chk("bind.priorBindingRejects", false); chk("bind.currentAdmits", false) }
            _ = await dec.closeAndReport(session: sess(405))
        }
        // 8. poison CLEARS the fence (fail closed): after an injected failure nothing admits.
        clearOnPoison: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 406, .init(failAfterRealSeekAndCleanup: true))
            let bridge = ShellSeekBridge()
            chk("clear.attach", bridge.attach(to: dec))
            let result = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .requiresClose = result else { chk("clear.requiresClose", false); break clearOnPoison }
            chk("clear.requiresClose", true)
            chk("clear.fenceNil", bridge.currentFence == nil)
            _ = await dec.closeAndReport(session: sess(406))
        }


        // 9. fenceMatchesProvider (M2 call-time check): true right after a commit; FALSE after
        //    a SECOND commit when validated through a stale snapshot is not possible (binding
        //    replaced); false after poison; false with no anchor. Mirrors the M2 barrier gate.
        match: do {
            let acks = AckBox()
            let dec = try await openReal(KIT, 407)
            let bridge = ShellSeekBridge()
            _ = bridge.attach(to: dec)
            chk("match.noAnchorYet", !bridge.fenceMatchesProvider(dec))   // initialOpen anchor is not committedSeek
            let r1 = await bridge.seek(on: dec, position: target) { rev, _ in acks.add(rev) }
            guard case .committedFlushed = r1 else { chk("match.committed", false); break match }
            chk("match.committed", true)
            chk("match.trueAfterCommit", bridge.fenceMatchesProvider(dec))
            _ = await dec.closeAndReport(session: sess(407))
            chk("match.falseAfterClose", !bridge.fenceMatchesProvider(dec))
        }


        // 10. FAILURE-ORDERING (actual, control path): after prohibitResumeAfterSeekFailure the
        //     shared authority refuses every further admission IMMEDIATELY - no stale frame can
        //     be admitted between a failed reset and the close.
        order: do {
            let commit = CancelCommit(sessionEpoch: 1)
            let pump = FramePump(source: TestSrc(), sink: TestSink(), clock: TestClock(), commit: commit) { _ in true }
            let before = commit.tryAdmit(revision: 0, framePTS: 0, frameDigest: "a")
            chk("order.admitBefore", before != nil)
            await pump.prohibitResumeAfterSeekFailure()
            chk("order.authorityCancelled", commit.isCancelled)
            chk("order.admitRefusedAfter", commit.tryAdmit(revision: 0, framePTS: 1, frameDigest: "b") == nil)
            // Held pre-failure admission: the ticket issued BEFORE the failure must be
            // obsolete at the CONSUME boundary too, not only new admissions - commitFrame
            // re-checks cancelBit inside the commit critical section.
            var assigned = false
            let committed = commit.commitFrame(before!, framePTS: 0, frameDigest: "a", assign: { assigned = true })
            chk("order.heldTicketCommitRefused", !committed)
            chk("order.heldTicketNoAssign", !assigned)
            chk("order.heldTicketConsumeRefused", !commit._testMayFinishConsume(ticket: before!))
        }

        print("BRIDGE_FINAL pass=\(passes) fail=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
