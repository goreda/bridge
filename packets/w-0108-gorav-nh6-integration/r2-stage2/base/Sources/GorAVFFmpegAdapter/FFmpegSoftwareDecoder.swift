// AUTHORED_R4 replacement, r5 source revision (2026-10-16, ZDYM provider/build lane).
// NOT the pinned r1 member (pin 17071B/8d1921fd...); byte identity is not claimed.
// Role per DECODER-ONLY-TARGET-WIRING-r1: local software demux/decode adapter.
// Provider lock (P1): FFmpeg 8.0.1 @ 894da5ca, private-prefix headers/libs only.
// NOT_RUN: no compile/importer/native acceptance has run. FIXTURE-SPEC.json binds
// each finding (team2 D01-D16 + architect r4 REVISE points) to a NOT_RUN fixture.
// Header ABI (AVFrame/AVPacket field layout incl. flags (AV_FRAME_FLAG_KEY), AVPixFmtDescriptor
// fields) is pinned by the P1 provider header set and remains UNVERIFIED here.
//
// Threading honesty: nativeQueue is a serial DispatchQueue - NOT a pinned host
// thread and NOT G1 host-thread proof. It provides turn-serialization only.
import Foundation
import CFFmpeg
import GorAVCore
import GorAVNativeProbeKit

/// Software-only local video decoder over the locked FFmpeg provider.
/// Decoder-only: no presentation, no GPU, no queue.
///
/// SESSION/OWNERSHIP MODEL (r5): ONE serialized owner turn (nativeQueue.sync)
/// contains every session/generation decision AND every native call. Lifecycle
/// state (currentSid, terminated, handle counter, retained frames, pending packet)
/// is read and mutated ONLY inside that turn - there is no pre-check outside the
/// queue. Open is one atomic queue turn (decision + setup), so a close queued
/// behind it can never interleave with opening: close either runs after open
/// committed (and closes the live session) or after open failed (and no-ops on
/// the nil session). Foreign session ids never touch native state.
///
/// Interrupt: AVIOInterruptCB with STABLE allocated storage (allocated before
/// open_input, torn down on close/deinit/failure). open_input itself is NOT
/// interruptible - stated, not hidden. Capability .ioOnly: aborts blocking
/// demux/AVIO reads that poll the callback; does NOT interrupt a stuck decode.
public final class FFmpegSoftwareDecoder: LocalVideoDecoder, SeekProviding, SeekProviderDiscovery, SeekEventReading, @unchecked Sendable {
    public enum OpenError: Error, Equatable, Sendable {
        case rejected(String)
        case providerFailed(code: Int)
        case sessionBusy
    }
    public var interruptCapability: InterruptCapability { .ioOnly }

    private enum Pipeline: Equatable { case reading, flushing, drained }
    private enum NativeError: Error { case failed(Int, String) }

    public struct CloseReport: Equatable, Sendable {
        public let leakedHandles: [UInt64]
        public let droppedPendingPackets: Int
        public let leaseTableLeaks: [UInt64]
        public let ledgerLeaks: [UInt64]
        /// Logical close invocation/return, NOT native free/refcount/leak proof.
        public let customIOLogicalTeardown: CustomIOLogicalTeardown
    }

    // MARK: queue-owned state (nativeQueue only - no access outside a queue turn)
    private let nativeQueue = DispatchQueue(label: "gorav.ffmpeg-software-decoder.native")
    private var currentSid: UInt64?
    private var terminated = false
    private var nextHandle: UInt64 = 0
    private var fmt: UnsafeMutablePointer<AVFormatContext>?
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var videoStreamIndex: Int32 = -1
    private var pipeline: Pipeline = .reading
    private var pendingPacket: UnsafeMutablePointer<AVPacket>?
    private var pendingPacketBytes: Int = 0
    private var pendingAdmitted = false
    private var pendingOpened: DecodeEvent?
    /// r6: bounded, allowlisted pixel layout. rowBytes = visible pixel bytes per
    /// row (padding EXCLUDED); rows = plane height; stride = provider linesize.
    private struct PlaneLayout {
        let rowBytes: Int
        let rows: Int
        let stride: Int
    }
    private struct RetainedFrame {
        let frame: UnsafeMutablePointer<AVFrame>
        let planes: [PlaneLayout]
    }
    /// Bounded fixture pixel-format allowlist (r6 D06, r7 plane oracle): each
    /// plane carries its OWN (log2 shift w, log2 shift h, pixel step). Luma/plane 0
    /// is never chroma-shifted. Anything not listed, any non-positive stride, or a
    /// stride shorter than the visible row is an HONEST REFUSAL - no fallback.
    private struct PlaneSpec { let sw: Int; let sh: Int; let step: Int }
    private static func planeLayouts(format: AVPixelFormat, width w: Int, height h: Int,
                                     linesizes: [Int]) -> [PlaneLayout]? {
        let table: [(fmt: AVPixelFormat, planes: [PlaneSpec])] = [
            (AV_PIX_FMT_YUV420P, [PlaneSpec(sw: 0, sh: 0, step: 1), PlaneSpec(sw: 1, sh: 1, step: 1), PlaneSpec(sw: 1, sh: 1, step: 1)]),
            (AV_PIX_FMT_YUVJ420P, [PlaneSpec(sw: 0, sh: 0, step: 1), PlaneSpec(sw: 1, sh: 1, step: 1), PlaneSpec(sw: 1, sh: 1, step: 1)]),
            (AV_PIX_FMT_YUV422P, [PlaneSpec(sw: 0, sh: 0, step: 1), PlaneSpec(sw: 1, sh: 0, step: 1), PlaneSpec(sw: 1, sh: 0, step: 1)]),
            (AV_PIX_FMT_YUV444P, [PlaneSpec(sw: 0, sh: 0, step: 1), PlaneSpec(sw: 0, sh: 0, step: 1), PlaneSpec(sw: 0, sh: 0, step: 1)]),
            (AV_PIX_FMT_NV12, [PlaneSpec(sw: 0, sh: 0, step: 1), PlaneSpec(sw: 1, sh: 1, step: 2)]),
            (AV_PIX_FMT_RGB24, [PlaneSpec(sw: 0, sh: 0, step: 3)]),
        ]
        guard let e = table.first(where: { $0.fmt == format }) else { return nil }
        var out: [PlaneLayout] = []
        for (i, spec) in e.planes.enumerated() {
            let stride = i < linesizes.count ? linesizes[i] : 0
            let visibleW = (w + (1 << spec.sw) - 1) >> spec.sw
            let rowBytes = visibleW * spec.step
            let rows = (h + (1 << spec.sh) - 1) >> spec.sh
            guard stride > 0, stride >= rowBytes, rowBytes > 0, rows > 0 else { return nil }
            out.append(PlaneLayout(rowBytes: rowBytes, rows: rows, stride: stride))
        }
        return out
    }
    /// Single checked range implementation for retain, observation AND digest.
    /// No pointers escape; coverage includes shared-buffer planar allocations.
    private static func checkedPlaneCoverage(frame: UnsafeMutablePointer<AVFrame>,
                                             layouts: [PlaneLayout]) -> [PlaneObservation]? {
        let bufs = [frame.pointee.buf.0, frame.pointee.buf.1, frame.pointee.buf.2, frame.pointee.buf.3,
                    frame.pointee.buf.4, frame.pointee.buf.5, frame.pointee.buf.6, frame.pointee.buf.7]
        let datas = [frame.pointee.data.0, frame.pointee.data.1, frame.pointee.data.2, frame.pointee.data.3,
                     frame.pointee.data.4, frame.pointee.data.5, frame.pointee.data.6, frame.pointee.data.7]
        guard !layouts.isEmpty, layouts.count <= 8 else { return nil }
        if frame.pointee.format == AV_PIX_FMT_RGB24.rawValue && layouts.count != 1 { return nil }
        var result: [PlaneObservation] = []
        for (i, layout) in layouts.enumerated() {
            guard layout.rows > 0, layout.rowBytes > 0, layout.stride >= layout.rowBytes,
                  let data = datas[i] else { return nil }
            let (prefix, mulOverflow) = layout.stride.multipliedReportingOverflow(by: layout.rows - 1)
            let (extent, addOverflow) = prefix.addingReportingOverflow(layout.rowBytes)
            guard !mulOverflow, !addOverflow, let span = UInt(exactly: extent) else { return nil }
            let base = UInt(bitPattern: data)
            let (dataEnd, dataOverflow) = base.addingReportingOverflow(span)
            guard !dataOverflow else { return nil }
            var found: PlaneObservation?
            for buffer in bufs {
                guard let buffer = buffer, let bufferData = buffer.pointee.data,
                      let size = UInt(exactly: buffer.pointee.size) else { continue }
                let low = UInt(bitPattern: bufferData)
                let (end, overflow) = low.addingReportingOverflow(size)
                guard !overflow, base >= low, dataEnd <= end else { continue }
                found = PlaneObservation(index: i, rowBytes: layout.rowBytes, rows: layout.rows,
                    stride: layout.stride, readableExtent: extent, containingBufferExtent: size,
                    planeOffset: base - low, coverageVerified: true)
                break
            }
            guard let value = found else { return nil }
            result.append(value)
        }
        return result
    }

    private static func checkedCoverageBytes(_ planes: [PlaneObservation]) -> Int? {
        var total = 0
        for plane in planes {
            let (next, overflow) = total.addingReportingOverflow(plane.readableExtent)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
    private func validObservationLease(handle: UInt64, session: UInt64, planes: [PlaneObservation]) -> Bool {
        guard let entry = leaseTable.entry(handle: handle), entry.owner == .decoder,
              entry.bytes == Self.checkedCoverageBytes(planes),
              leases.stage(handle: handle, session: session) == .allocated else { return false }
        return true
    }

    // Queue-owned bounded trace. No ambient logger or raw provider references.
    private var customIOLogicalTeardown: CustomIOLogicalTeardown = .absent
    private var traceEpoch: UInt64?
    private var traceRecords: [SessionTraceRecord] = []
    private var traceOverflow = false
    private var traceSequence: UInt64 = 0
    private func trace(_ kind: SessionTraceKind, code: Int32? = nil) {
        guard traceEpoch != nil else { return }
        guard traceRecords.count < 128 else { traceOverflow = true; return }
        traceRecords.append(SessionTraceRecord(sequence: traceSequence, kind: kind,
            providerResult: code, selectedStreamIndex: videoStreamIndex))
        traceSequence += 1
    }

    /// Called only after format has stopped using custom IO, on nativeQueue.
    /// A crash/hang between call and return leaves a called record, never completed.
    private func observeLogicalCustomIOClose(_ owner: SnapshotAVIOOwner?) {
        guard let owner = owner else {
            customIOLogicalTeardown = .absent
            trace(.customIOAbsent)
            return
        }
        customIOLogicalTeardown = .called
        trace(.customIOCloseCalled)
        owner.close()
        customIOLogicalTeardown = .completed
        trace(.customIOCloseCompleted)
    }

    private var retainedFrames: [UInt64: RetainedFrame] = [:]
    private var interruptSlotPtr: UnsafeMutablePointer<GorAVInterruptSlot>?
    private var snapshotOwner: SnapshotAVIOOwner?
    private var pinnedRoots: [URL] = []  // empty = refuse all opens (r5 D12)
    /// r8 (architect ruling): an epoch is spent the moment its interrupt fence is
    /// exposed and is never reusable by this decoder instance (failed opens
    /// included) - a stale callback or delayed interrupt from a dead attempt can
    /// never match a later session by epoch. Explicit limit: the set grows by one
    /// entry per open attempt, unbounded.
    private var usedEpochs: Set<UInt64> = []
    private var closeReport: CloseReport?

    private let leases = FrameLeaseLedger()
    private let leaseTable = LeaseTable()
    private var feed = PacketFeedMachine(budget: .init(maxPackets: 64, maxBytes: 8 * 1024 * 1024))
    private let interruptSlot = SessionInterruptSlot()

    private final class InterruptBox {
        private let lock = NSLock(); private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        func reset() { lock.lock(); flag = false; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }
    private let interruptBox = InterruptBox()


    // MARK: - Request-bound coordinated provider API (validation pending)
    // Source instance mint is process-held; reopen changes only openGeneration. No pointer IDs.
    private static let sourceInstanceMint = TransactionIDMint()
    private let seekState = ProviderSeekCoordinator()
    private let sourceInstanceID = try? FFmpegSoftwareDecoder.sourceInstanceMint.issue().rawValue
    private var openGeneration: UInt64 = 0 // nativeQueue-owned
    private var eventOrigin: EventOrigin? // nativeQueue-owned, retained through close for sentinel replay
    private var frameOrigins: [UInt64: EventOrigin] = [:] // old handles keep their original seek origin

    public func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)? {
        seekState.currentBinding()
    }
    public func capabilities() -> SeekCapabilities { seekState.capabilities() }
    public func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor { try seekState.descriptor(for: source) }
    public var activeTransaction: SeekEventIdentity? { seekState.activeTransaction }
    public func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction {
        try seekState.tryBegin(request) { [self] record in
            nativeQueue.async { [self] in performSeek(record) }
        }
    }
    private func performSeek(_ record: ProviderSeekReservation) {
        let request = record.request
        let old = request.expectedRevision
        var facts = NativeSeekFacts(avSeekReturn: nil, flagsApplied: 0, resolvedStreamIndex: nil,
            requestedTicks: nil, resolvedStreamTimebase: nil, startOriginTicks: nil, flushObserved: false,
            packetFeedReset: false, decoderReset: false, packetsReleased: nil, packetAccountingReconciled: false)
        func receipt(_ outcome: SeekReceipt.Outcome, mutation: MutationState = .none,
                     stage: ProviderSeekStage = .preSeek, cancel: Bool = false, ready: Bool = false) -> SeekReceipt {
            SeekReceipt(identity: record.identity, correlationID: request.correlationID, session: request.session,
                request: request, previousRevision: old, nextRevision: ready ? record.reservedRevision : old,
                reachedStage: stage, arbitration: cancel ? .cancellationRequested : (ready ? .nativeReadyObserved : .none),
                mutation: mutation, resumePolicy: mutation == .none ? .unchangedCoreGated : (ready ? .resumeFromNativePosition : .closedRequired),
                outcome: outcome)
        }
        func refuse(_ reason: SeekReceipt.NoMutationRefusal) {
            seekState.finish(record) { cancelled in
                cancelled ? receipt(.cancelledNoMutation(reason: .requested), cancel: true) : receipt(.refusedNoMutation(reason: reason))
            }
        }
        if let reason = seekState.queueRefusal(record) { refuse(reason); return }
        guard currentSid == request.session.rawValue, !terminated,
              eventOrigin?.source == request.source, let fmt, let codecCtx else { refuse(.closed); return }
        guard let stream = fmt.pointee.streams[Int(videoStreamIndex)] else { refuse(.unsupported("missing video stream")); return }
        let tb = stream.pointee.time_base
        let origin = stream.pointee.start_time
        guard origin != gorav_av_nopts_value(), tb.num > 0, tb.den > 0,
              request.target.position.value >= 0, request.target.rounding == .floorToKeyframe,
              request.target.requestedFlags & ~Int32(1) == 0 else { refuse(.unsupported("target, origin or timebase")); return }
        let ticks: Int64
        do {
            let delta = try request.target.position.floorTicks(toTimebaseNumerator: Int64(tb.num), denominator: Int64(tb.den))
            ticks = try RationalTime.checkedOriginSum(deltaTicks: delta, startTimeTicks: origin)
        } catch { refuse(.unsupported("target conversion overflow")); return }
        // Last cooperative checkpoint immediately before entry. Once entered, native owns its
        // resources until return even when cancellation is requested or a caller stops waiting.
        if !seekState.enterNative(record) {
            seekState.finish(record) { _ in receipt(.cancelledNoMutation(reason: .requested), cancel: true) }; return
        }
        let rc = av_seek_frame(fmt, videoStreamIndex, ticks, 1)
        // avcodec_flush_buffers is void. Record that the call completed, never a fabricated status.
        avcodec_flush_buffers(codecCtx)
        let released = pendingPacket == nil ? 0 : 1
        if let packet = pendingPacket { var p: UnsafeMutablePointer<AVPacket>? = packet; av_packet_free(&p) }
        pendingPacket = nil; pendingPacketBytes = 0; pendingAdmitted = false
        feed.reset(); pipeline = .reading
        facts = NativeSeekFacts(avSeekReturn: rc, flagsApplied: 1, resolvedStreamIndex: videoStreamIndex,
            requestedTicks: ticks, resolvedStreamTimebase: try? RationalTime(value: Int64(tb.num), timescale: tb.den),
            startOriginTicks: origin, flushObserved: true, packetFeedReset: true, decoderReset: true,
            packetsReleased: released, packetAccountingReconciled: true)
        // Native queue owns origin publication; the state lock arbitrates cancellation/ready once.
        // No subsequent native queue turn can observe the interval between these two operations.
        var readyWon = false
        seekState.finish(record) { cancelled in
            if rc < 0 {
                return receipt(.failed(stage: .cleanedUp, reason: .avError(code: rc), facts: facts,
                    poison: .closeRequired("native seek failed after entry")), mutation: .partial, stage: .cleanedUp, cancel: cancelled)
            }
            if cancelled {
                return receipt(.cancelledAfterCleanup(facts: facts, poison: .closeRequired("cancelled after native entry")),
                    mutation: .completedClean, stage: .cleanedUp, cancel: true)
            }
            readyWon = true
            return receipt(.nativeReady(facts: facts), mutation: .completedClean, stage: .cleanedUp, ready: true)
        }
        if readyWon {
            eventOrigin = EventOrigin(session: request.session, source: request.source,
                providerRevision: record.reservedRevision, requestOrigin: .transaction(record.identity.transactionID))
        } else { terminated = true }
    }

    /// Only the coordinated channel admits new-origin events. Old delivered values retain their
    /// immutable origin; the adapter must quarantine them rather than infer eligibility by arrival.
    public func nextEvent() async -> SeekProviderEvent<NativeFrame> {
        // A read queued behind execute observes completion in nativeQueue order. A reservation not
        // yet executed must not permit native pulls, so await its immutable completion first.
        await seekState.waitUntilSettled()
        return await withCheckedContinuation { continuation in
            nativeQueue.async { [self] in
                guard let origin = eventOrigin else {
                    preconditionFailure("coordinated event channel requires one successful open")
                }
                if currentSid == nil { continuation.resume(returning: .closed(origin)); return }
                do { try seekState.activateEvents() } catch {
                    continuation.resume(returning: .failed(origin, code: -19, summary: "provider closing or recovery required")); return
                }
                guard seekState.outputAllowed else {
                    continuation.resume(returning: .feedSaturated(origin, pendingPackets: feed.pendingPackets)); return
                }
                guard let event = pipelineStep(session: origin.session.rawValue) else {
                    if retainedFrames.isEmpty { continuation.resume(returning: .drained(origin)) }
                    else { continuation.resume(returning: .feedSaturated(origin, pendingPackets: feed.pendingPackets)) }
                    return
                }
                let result: SeekProviderEvent<NativeFrame>
                switch event {
                case .opened(let codec, let width, let height): result = .opened(origin, videoCodec: codec, width: width, height: height)
                case .frameDecoded(let frame): frameOrigins[frame.handle] = origin; result = .frameDecoded(origin, frame)
                case .endOfStream: result = .endOfStream(origin)
                case .interrupted: result = .interrupted(origin)
                case .failed(let code, let summary): result = .failed(origin, code: Int32(clamping: code), summary: String(summary.prefix(256)))
                case .feedSaturated(let count): result = .feedSaturated(origin, pendingPackets: count)
                }
                continuation.resume(returning: result)
            }
        }
    }
    public func retainedHandleMetadata(handle: UInt64, session: SessionID) async -> RetainedHandleMetadata? {
        await withCheckedContinuation { continuation in
            nativeQueue.async { [self] in
                guard currentSid == session.epoch, retainedFrames[handle] != nil, let origin = frameOrigins[handle] else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: RetainedHandleMetadata(origin: origin,
                    validWhileOpenGeneration: origin.source.openGeneration, releaseRequired: true))
            }
        }
    }
    public func close() async throws {
        seekState.requestClose()
        await seekState.waitUntilSettled()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nativeQueue.async { [self] in
                if let sid = currentSid { closeReport = nativeTeardownLocked(session: sid) }
                continuation.resume()
            }
        }
    }

    private let nativeQueueKey = DispatchSpecificKey<UInt8>()
    public init() { nativeQueue.setSpecific(key: nativeQueueKey, value: 1) }

    /// Read of the last close report; the read itself is a queue turn.
    public var lastCloseReport: CloseReport? { nativeQueue.sync { closeReport } }

    // MARK: - pinned local roots (r5 D12)

    /// Pins the local roots admitted for open. Callable only while idle (no active
    /// session); the decision is a queue turn. Roots are symlink-resolved once here.
    /// Empty roots (the default) refuse every open - there is no implicit "/".
    public func pinLocalRoots(_ roots: [String]) throws {
        try nativeQueue.sync {
            guard currentSid == nil else { throw OpenError.sessionBusy }
            var resolved: [URL] = []
            for r in roots {
                // r6 R5-G: relative root input is refused - a pin must not depend
                // on an ambient cwd.
                guard r.hasPrefix("/") else {
                    throw OpenError.rejected("pinned root is not absolute: \(r)")
                }
                let u = URL(fileURLWithPath: r).resolvingSymlinksInPath().standardizedFileURL
                // K13B (team2 candidate r1 F1, verified against code behavior):
                // refuse roots that RESOLVE to '/' - one vacuous pin would
                // otherwise disable the whole containment gate below.
                guard u.path != "/" else {
                    throw OpenError.rejected("pinned root resolves to '/': vacuous containment refused")
                }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else {
                    throw OpenError.rejected("pinned root not an existing directory: \(r)")
                }
                resolved.append(u)
            }
            pinnedRoots = resolved
        }
    }

    // MARK: - open (one atomic queue turn: gate + admission + setup + commit)

    /// Two-stage admission (r5 D12):
    /// Stage 1 (pre-open): kind, scheme rejection, symlink/..-resolved containment
    ///   inside the pinned local roots. The RESOLVED path string is what reaches
    ///   avformat_open_input, so check and use cannot diverge on resolution.
    ///   Residual: a symlink swap between resolution and provider open (TOCTOU) is
    ///   not closed at source level; the pinned-fixture FD-consumption contract for
    ///   native acceptance is tracked OPEN in FIXTURE-SPEC.json.
    /// Stage 2 (post-open, pre-decode): container right after open_input; codec and
    ///   stream inventory after find_stream_info, before any decode read.
    public func open(source: GorAVCore.SourceDescriptor, session: SessionID) async throws {
        try await openImpl(source: source, snapshot: nil, session: session)
    }

    /// Source-only first-fixture route; SHA implementation qualification remains gated.
    public func openSnapshot(_ snapshot: ImmutableInputSnapshot, session: SessionID) async throws {
        guard snapshot.expectedBytes == 574,
              snapshot.sha256Hex == "009889e24805044e676ce86f9d26ed3b8cd60e9a014d623ef4e0ef48ed451fa9" else {
            throw OpenError.rejected("snapshot outside first-fixture pin")
        }
        try await openImpl(source: nil, snapshot: snapshot, session: session)
    }

    private func openImpl(source: GorAVCore.SourceDescriptor?, snapshot: ImmutableInputSnapshot?, session: SessionID) async throws {
        let sid = session.epoch
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nativeQueue.sync {
                // r6: attempt-local slot, visible to failure teardown; stays nil
                // for rejections that precede allocation (no teardown of anything).
                var attemptSlotForTeardown: UnsafeMutablePointer<GorAVInterruptSlot>?
                // r7: the fence clear in the catch paths may only run if THIS
                // attempt installed it. A rejection before install (e.g. sessionBusy)
                // must not touch another session's live interrupt route.
                var attemptFenceInstalled = false
                var attemptSnapshotOwner: SnapshotAVIOOwner?
                defer {
                    if let owner = attemptSnapshotOwner { observeLogicalCustomIOClose(owner) }
                } // fallback only for uncommitted fully initialized custom IO
                do {
                    // Session/generation gate INSIDE the queue turn (r5 S1).
                    guard currentSid == nil else { throw OpenError.sessionBusy }
                    guard let sourceInstanceID, openGeneration < UInt64.max, sid != 0 else { throw SeekIssuanceError.exhausted }
                    guard !usedEpochs.contains(sid) else {
                        throw OpenError.rejected("session epoch already used by this decoder instance")
                    }
                    // r8 (architect ruling): the epoch is spent HERE, at the gate,
                    /// before the interrupt fence is ever exposed. A failed or
                    /// cancelled open therefore consumes the epoch: a same-epoch
                    /// re-open is REFUSED by the guard above, and a delayed
                    /// requestInterrupt for a dead attempt can never match a later
                    /// session. Not left to the caller.
                    var resolvedPath: String?
                    if let source = source {
                        guard source.kind == .local else { throw OpenError.rejected("decoder-only probe admits local sources only") }
                        guard !source.id.contains("://") else {
                            throw OpenError.rejected("source id carries a URL scheme; plain local paths only")
                        }
                        guard source.id.hasPrefix("/") else {
                            throw OpenError.rejected("source id is not an absolute local path")
                        }
                        guard !pinnedRoots.isEmpty else {
                            throw OpenError.rejected("no pinned local roots configured; refusing open")
                        }
                        let resolved = URL(fileURLWithPath: source.id).resolvingSymlinksInPath().standardizedFileURL
                        // K13B: pins that resolve to '/' are refused at pin
                        // time, so no vacuous-root disjunct belongs here.
                        guard pinnedRoots.contains(where: {
                            resolved.path == $0.path || resolved.path.hasPrefix($0.path + "/")
                        }) else {
                            throw OpenError.rejected("resolved source path outside pinned local roots")
                        }
                        resolvedPath = resolved.path
                    } else if snapshot == nil {
                        throw OpenError.rejected("no input snapshot")
                    }

                    // Interrupt plumbing BEFORE any blocking provider call (r5 D03,
                    // r6 ownership): the slot is OPEN-ATTEMPT-LOCAL until commit.
                    // A failed attempt tears down only its own local storage and
                    // never touches any state of another (live) session. The
                    // sessionBusy rejection above throws before this point, so the
                    // fence install below can only run when no session is active.
                    traceEpoch = sid; traceRecords = []; traceOverflow = false; traceSequence = 0
                    customIOLogicalTeardown = .absent
                    videoStreamIndex = -1
                    interruptBox.reset()
                    usedEpochs.insert(sid) // spent at first fence exposure (r8 ruling)
                    interruptSlot.install(session: sid) { [weak self] in self?.interruptBox.set() }
                    attemptFenceInstalled = true
                    let attemptSlot = UnsafeMutablePointer<GorAVInterruptSlot>.allocate(capacity: 1)
                    attemptSlotForTeardown = attemptSlot
                    attemptSlot.initialize(to: GorAVInterruptSlot(
                        poll: { opaque in
                            guard let opaque = opaque else { return 0 }
                            return Unmanaged<InterruptBox>.fromOpaque(opaque).takeUnretainedValue().isSet ? 1 : 0
                        },
                        opaque: Unmanaged.passUnretained(interruptBox).toOpaque()))

                    var opened: UnsafeMutablePointer<AVFormatContext>? = nil
                    let openRC: Int32
                    if let snapshot = snapshot {
                        let owner = try SnapshotAVIOOwner(snapshot: snapshot)
                        attemptSnapshotOwner = owner
                        guard let allocated = avformat_alloc_context() else {
                            throw NativeError.failed(-20, "snapshot format allocation failed")
                        }
                        opened = allocated
                        gorav_bind_custom_avio(allocated, owner.io)
                        allocated.pointee.interrupt_callback = AVIOInterruptCB(
                            callback: gorav_avio_interrupt_thunk,
                            opaque: UnsafeMutableRawPointer(attemptSlot))
                        guard let demux = av_find_input_format("ppm_pipe") else {
                            avformat_free_context(allocated); opened = nil
                            throw NativeError.failed(-21, "ppm demux unavailable")
                        }
                        openRC = avformat_open_input(&opened, nil, demux, nil)
                    } else {
                        guard let path = resolvedPath else { throw OpenError.rejected("missing resolved path") }
                        openRC = path.withCString { avformat_open_input(&opened, $0, nil, nil) }
                    }
                    var rc = openRC
                    guard rc == 0, let fmtCtx = opened else {
                        // Pinned demux.c open failure frees context and NULLs pointer.
                        // Defensive remaining context cleanup precedes custom IO defer.
                        if let remaining = opened { avformat_free_context(remaining); opened = nil }
                        throw NativeError.failed(Int(rc), "avformat_open_input failed")
                    }
                    fmtCtx.pointee.interrupt_callback = AVIOInterruptCB(
                        callback: gorav_avio_interrupt_thunk,
                        opaque: UnsafeMutableRawPointer(attemptSlot))

                    let container = String(cString: fmtCtx.pointee.iformat.pointee.name)
                    guard snapshot != nil ? container == "ppm_pipe" : DemuxerPolicy.admittedContainers.contains(container) else {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-2, "demux admission rejected: container \(container)")
                    }

                    rc = avformat_find_stream_info(fmtCtx, nil)
                    guard rc >= 0 else {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        if rc == gorav_av_err_exit() { throw NativeError.failed(Int(rc), "open interrupted") }
                        throw NativeError.failed(Int(rc), "avformat_find_stream_info failed")
                    }

                    var videoCount = 0, audioCount = 0, otherCount = 0
                    var videoIndex: Int32 = -1
                    var audioIndex: Int32 = -1
                    for i in 0..<Int32(fmtCtx.pointee.nb_streams) {
                        switch fmtCtx.pointee.streams[Int(i)]?.pointee.codecpar?.pointee.codec_type ?? AVMEDIA_TYPE_UNKNOWN {
                        case AVMEDIA_TYPE_VIDEO: videoCount += 1; if videoIndex < 0 { videoIndex = i }
                        case AVMEDIA_TYPE_AUDIO: audioCount += 1; if audioIndex < 0 { audioIndex = i }
                        default: otherCount += 1
                        }
                    }
                    let codecID = videoIndex >= 0
                        ? (fmtCtx.pointee.streams[Int(videoIndex)]?.pointee.codecpar?.pointee.codec_id ?? AV_CODEC_ID_NONE)
                        : AV_CODEC_ID_NONE
                    let codecName = String(cString: avcodec_get_name(codecID))
                    // Card 465: actual audio sibling codec for the bounded muxed
                    // admission profile (AV_CODEC_ID_NONE -> "none" when video-only).
                    let audioCodecID = audioIndex >= 0
                        ? (fmtCtx.pointee.streams[Int(audioIndex)]?.pointee.codecpar?.pointee.codec_id ?? AV_CODEC_ID_NONE)
                        : AV_CODEC_ID_NONE
                    let audioCodecName = String(cString: avcodec_get_name(audioCodecID))
                    if snapshot != nil && (container != "ppm_pipe" || codecName != "ppm" || videoCount != 1 || audioCount != 0 || otherCount != 0) {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-22, "snapshot requires one ppm video stream")
                    }
                    if snapshot == nil {
                    switch DemuxerPolicy().evaluate(containerName: container, videoCodecName: codecName,
                                                    videoStreamCount: videoCount, audioStreamCount: audioCount,
                                                    otherStreamCount: otherCount, audioCodecName: audioCodecName) {
                    case .reject(let reason):
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-2, "demux admission rejected: \(reason)")
                    case .admit: break
                    }

                    }

                    guard let codec = avcodec_find_decoder(codecID) else {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-3, "no decoder for \(codecName)")
                    }
                    var localCtx: UnsafeMutablePointer<AVCodecContext>? = avcodec_alloc_context3(codec)
                    guard localCtx != nil else {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-4, "avcodec_alloc_context3 failed")
                    }
                    guard let params = fmtCtx.pointee.streams[Int(videoIndex)]?.pointee.codecpar,
                          avcodec_parameters_to_context(localCtx, params) >= 0 else {
                        avcodec_free_context(&localCtx)
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-5, "parameters_to_context failed")
                    }
                    // r4 D13: software-only deterministic bound; provider threading
                    // beyond this is unverified and not claimed.
                    localCtx!.pointee.thread_count = 1
                    guard avcodec_open2(localCtx, codec, nil) >= 0 else {
                        avcodec_free_context(&localCtx)
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-6, "avcodec_open2 failed")
                    }

                    // Commit (single queue turn, so visible atomically to all callers).
                    feed.reset()
                    self.snapshotOwner = attemptSnapshotOwner
                    attemptSnapshotOwner = nil // ownership commits with format/session
                    self.fmt = fmtCtx
                    self.codecCtx = localCtx
                    self.videoStreamIndex = videoIndex
                    trace(.selectedStream)
                    self.pipeline = .reading
                    self.pendingPacket = nil; self.pendingAdmitted = false
                    self.retainedFrames = [:]
                    self.interruptSlotPtr = attemptSlot // commit: attempt storage becomes session-owned
                    attemptSlotForTeardown = nil
                    self.currentSid = sid
                    self.terminated = false
                    self.nextHandle = 0
                    self.pendingOpened = .opened(videoCodec: codecName,
                                                 width: Int(localCtx!.pointee.width),
                                                 height: Int(localCtx!.pointee.height))
                    openGeneration += 1
                    let token = try SourceToken(instanceID: sourceInstanceID, openGeneration: openGeneration)
                    let seekSession = try SeekSessionID(rawValue: sid)
                    let stream = fmtCtx.pointee.streams[Int(videoIndex)]!
                    let tb = stream.pointee.time_base
                    let originKnown = stream.pointee.start_time != gorav_av_nopts_value()
                    let originProduct = stream.pointee.start_time.multipliedReportingOverflow(by: Int64(tb.num))
                    let originSeconds = originKnown && !originProduct.overflow && tb.den > 0
                        ? try? RationalTime(value: originProduct.partialValue, timescale: tb.den) : nil
                    let validTB = tb.num > 0 && tb.den > 0
                    let canSeek = (source?.seekable ?? true) && validTB && originSeconds != nil
                    let descriptor = SeekSourceDescriptor(source: token, seekable: canSeek,
                        originKnown: originKnown && originSeconds != nil, startOrigin: originSeconds, duration: nil,
                        videoStreamIndex: videoIndex,
                        streamTimebase: validTB ? try? RationalTime(value: Int64(tb.num), timescale: tb.den) : nil)
                    seekState.opened(token: token, session: seekSession, descriptor: descriptor,
                        capabilities: SeekCapabilities(seekable: canSeek, supportedRoundings: [.floorToKeyframe],
                            supportedFlags: 1, originKnown: originSeconds != nil))
                    eventOrigin = EventOrigin(session: seekSession, source: token, providerRevision: .atOpen, requestOrigin: .initialOpen)
                    frameOrigins = [:]
                    cont.resume()
                } catch let e as NativeError {
                    if attemptFenceInstalled { trace(.terminalFailed) }
                    if attemptFenceInstalled { observeLogicalCustomIOClose(attemptSnapshotOwner) }
                    attemptSnapshotOwner = nil // callback owner freed before interrupt slot
                    // r6: failure teardown is ATTEMPT-LOCAL. The gate at the top
                    // guarantees no session is active here, so clearing the fence
                    // is safe; self.interruptSlotPtr (a previous session's storage)
                    // is never touched by a failed attempt.
                    if attemptFenceInstalled { interruptSlot.clear() }
                    if let slot = attemptSlotForTeardown {
                        slot.deinitialize(count: 1); slot.deallocate()
                    }
                    switch e {
                    case .failed(let code, let summary):
                        if summary.hasPrefix("demux admission rejected") {
                            cont.resume(throwing: OpenError.rejected(summary))
                        } else {
                            cont.resume(throwing: OpenError.providerFailed(code: code))
                        }
                    }
                } catch {
                    if attemptFenceInstalled { trace(.terminalFailed) }
                    if attemptFenceInstalled { observeLogicalCustomIOClose(attemptSnapshotOwner) }
                    attemptSnapshotOwner = nil
                    if attemptFenceInstalled { interruptSlot.clear() }
                    if let slot = attemptSlotForTeardown {
                        slot.deinitialize(count: 1); slot.deallocate()
                    }
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func teardownInterruptLocked() {
        interruptSlot.clear()
        if let slot = interruptSlotPtr {
            slot.deinitialize(count: 1)
            slot.deallocate()
            interruptSlotPtr = nil
        }
    }

    // MARK: - nextEvent

    /// nil ONLY after a terminal event ended this session's stream, or for a
    /// session that is not the current one (checked INSIDE the queue turn, r5 S2).
    public func nextEvent(session: SessionID) async -> DecodeEvent? {
        await withCheckedContinuation { cont in
            nativeQueue.sync {
                guard seekState.claimLegacy() else { cont.resume(returning: .failed(code: -19, summary: "legacy pull refused in coordinated mode or terminal provider")); return }
                cont.resume(returning: pipelineStep(session: session.epoch))
            }
        }
    }

    private func pipelineStep(session sid: UInt64) -> DecodeEvent? {
        // Session/generation re-verification inside the owner turn (r5 S2): a stale
        // session can never observe pendingOpened/frames of a later session.
        guard sid == currentSid, !terminated else { return nil }
        if let opened = pendingOpened { pendingOpened = nil; return opened }
        guard let fmt = fmt, let ctx = codecCtx else { return nil }
        if pipeline == .drained { return nil }

        var scratchOpt: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard scratchOpt != nil else { return markTerminal(.failed(code: -10, summary: "av_frame_alloc failed")) }
        defer { av_frame_free(&scratchOpt) }
        let scratch = scratchOpt!

        var iterations = 0
        while iterations < 128 {
            iterations += 1

            let recvRC = avcodec_receive_frame(ctx, scratch)
            if recvRC == 0 {
                guard let kept = av_frame_clone(scratch) else {
                    return markTerminal(.failed(code: -7, summary: "av_frame_clone allocation failed"))
                }
                nextHandle += 1
                let handle = nextHandle
                // r4 D13: geometry sanity bound before delivery.
                guard kept.pointee.width > 0, kept.pointee.height > 0,
                      kept.pointee.width <= 16384, kept.pointee.height <= 16384 else {
                    var bad: UnsafeMutablePointer<AVFrame>? = kept
                    av_frame_free(&bad)
                    return markTerminal(.failed(code: -12, summary: "decoded frame geometry out of bounds"))
                }
                // r6: layout from the bounded fixture allowlist only (alpha,
                // palette and high-bit-depth formats are NOT modeled and are
                // refused); every plane needs a refcounted AVBufferRef whose size
                // covers the readable extent; otherwise honest terminal refusal.
                let rawLinesize = kept.pointee.linesize
                let linesizes = [rawLinesize.0, rawLinesize.1, rawLinesize.2, rawLinesize.3,
                                 rawLinesize.4, rawLinesize.5, rawLinesize.6, rawLinesize.7].map { Int($0) }
                guard let layouts = Self.planeLayouts(format: AVPixelFormat(rawValue: kept.pointee.format),
                                                      width: Int(kept.pointee.width),
                                                      height: Int(kept.pointee.height),
                                                      linesizes: linesizes),
                      let coverage = Self.checkedPlaneCoverage(frame: kept, layouts: layouts),
                      let coverageBytes = Self.checkedCoverageBytes(coverage) else {
                    var f: UnsafeMutablePointer<AVFrame>? = kept
                    av_frame_free(&f)
                    return markTerminal(.failed(code: -15, summary: "unsupported or unbounded pixel layout"))
                }
                retainedFrames[handle] = RetainedFrame(frame: kept, planes: layouts)
                leases.allocated(handle, session: sid)
                // LeaseTable acquire result is CHECKED (r5 D14): a collision is an
                // internal invariant failure, surfaced as terminal, never ignored.
                if !leaseTable.acquire(handle: handle, bytes: coverageBytes, owner: .decoder) {
                    var f: UnsafeMutablePointer<AVFrame>? = kept
                    av_frame_free(&f)
                    retainedFrames.removeValue(forKey: handle)
                    leases.released(handle, session: sid)
                    return markTerminal(.failed(code: -13, summary: "lease table acquire collision"))
                }
                let fmtName = av_get_pix_fmt_name(AVPixelFormat(rawValue: kept.pointee.format)).map { String(cString: $0) } ?? "unknown"
                let nf = NativeFrame(session: sid, handle: handle,
                                     pts: kept.pointee.pts == gorav_av_nopts_value() ? nil : kept.pointee.pts,
                                     duration: kept.pointee.duration,
                                     width: Int(kept.pointee.width), height: Int(kept.pointee.height),
                                     pixelFormatName: fmtName,
                                     isKeyFrame: (kept.pointee.flags & Int32(AV_FRAME_FLAG_KEY)) != 0)
                return .frameDecoded(nf)
            }
            if recvRC == gorav_av_err_eof() {
                trace(.receiveEOF, code: recvRC)
                pipeline = .drained
                feed.consumeEOF()
                return markTerminal(.endOfStream)
            }
            if recvRC != gorav_av_err_eagain() {
                return markTerminal(.failed(code: Int(recvRC), summary: "avcodec_receive_frame failed"))
            }
            if pipeline == .flushing {
                return markTerminal(.failed(code: -8, summary: "flush drain returned EAGAIN"))
            }

            if pendingPacket == nil {
                var newPacket: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
                guard newPacket != nil else {
                    return markTerminal(.failed(code: -11, summary: "av_packet_alloc failed"))
                }
                let rc = av_read_frame(fmt, newPacket)
                if rc == gorav_av_err_exit() {
                    av_packet_free(&newPacket)
                    return markTerminal(.interrupted(session: sid))
                }
                if rc == gorav_av_err_eof() {
                    trace(.demuxReadEOF, code: rc)
                    av_packet_free(&newPacket)
                    let flushRC = avcodec_send_packet(ctx, nil)
                    trace(.nilFlushSendResult, code: flushRC)
                    pipeline = .flushing
                    _ = feed.feedEOF()
                    if flushRC < 0 && flushRC != gorav_av_err_eof() {
                        return markTerminal(.failed(code: Int(flushRC), summary: "flush send failed"))
                    }
                    continue
                }
                if rc < 0 {
                    av_packet_free(&newPacket)
                    return markTerminal(.failed(code: Int(rc), summary: "av_read_frame failed"))
                }
                guard newPacket!.pointee.stream_index == videoStreamIndex else {
                    av_packet_free(&newPacket)
                    continue
                }
                pendingPacket = newPacket
                pendingPacketBytes = Int(newPacket!.pointee.size)
                pendingAdmitted = feed.feed(bytes: pendingPacketBytes)
                if !pendingAdmitted {
                    // r5 D08: a packet that can NEVER fit the budget is a terminal
                    // admission failure, not an endless saturated hold.
                    if pendingPacketBytes > feed.budgetBytes {
                        return markTerminal(.failed(code: -14, summary: "packet exceeds feed budget"))
                    }
                    return .feedSaturated(pendingPackets: feed.pendingPackets)
                }
            } else if !pendingAdmitted {
                // Held, not yet admitted: retry admission; no new read meanwhile.
                pendingAdmitted = feed.feed(bytes: pendingPacketBytes)
                if !pendingAdmitted {
                    return .feedSaturated(pendingPackets: feed.pendingPackets)
                }
            }

            let sendRC = avcodec_send_packet(ctx, pendingPacket)
            if sendRC == 0 {
                feed.consume(bytes: pendingPacketBytes)
                var sent: UnsafeMutablePointer<AVPacket>? = pendingPacket
                pendingPacket = nil; pendingPacketBytes = 0; pendingAdmitted = false
                av_packet_free(&sent)
                continue
            }
            if sendRC == gorav_av_err_eagain() { continue } // packet stays pending
            return markTerminal(.failed(code: Int(sendRC), summary: "avcodec_send_packet failed"))
        }
        return markTerminal(.failed(code: -9, summary: "pipeline stall guard (128 iterations)"))
    }

    /// Checksum access for the first native acceptance (r6 D06): FNV-1a over
    /// VISIBLE pixel bytes only - row by row, stride-advanced, trailing row
    /// padding never read. Total bytes read are bounded by the sum of plane
    /// readableExtents, itself bounded by the retain-time geometry cap
    /// (16384x16384) and AVBufferRef coverage checks. Session + handle verified
    /// in the queue turn.
    public func frameDigest(handle: UInt64, session: SessionID) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            nativeQueue.sync {
                guard session.epoch == self.currentSid, let rec = self.retainedFrames[handle] else {
                    cont.resume(returning: nil); return
                }
                guard let planes = Self.checkedPlaneCoverage(frame: rec.frame, layouts: rec.planes),
                      self.validObservationLease(handle: handle, session: session.epoch, planes: planes) else {
                    cont.resume(returning: nil); return
                }
                var hash: UInt64 = 14695981039346656037
                let rawData = rec.frame.pointee.data
                let datas = [rawData.0, rawData.1, rawData.2, rawData.3,
                             rawData.4, rawData.5, rawData.6, rawData.7]
                for (p, layout) in rec.planes.enumerated() {
                    guard let base = datas[p] else { cont.resume(returning: nil); return }
                    var rowPtr = UnsafeRawPointer(base)
                    for rowIndex in 0..<layout.rows {
                        let row = UnsafeRawBufferPointer(start: rowPtr, count: layout.rowBytes)
                        for b in row { hash = (hash ^ UInt64(b)) &* 1099511628211 }
                        if rowIndex + 1 < layout.rows { rowPtr = rowPtr.advanced(by: layout.stride) }
                    }
                }
                cont.resume(returning: String(format: "%016llx", hash))
            }
        }
    }

    // AUTHORED NEW (2026-10-17, K6 shell seam): visible-plane byte copy for
    // display sinks. Same coverage + lease gates as frameDigest; returns
    // per-plane VISIBLE bytes (rowBytes x rows, stride-advanced) in plane
    // order, plus the frame's format name and size. Bounded by
    // checkedPlaneCoverage/validObservationLease exactly like the digest.
    public struct PlaneCopy: Sendable { public let planes: [[UInt8]]; public let width: Int; public let height: Int; public let format: String }
    public func framePlaneCopy(handle: UInt64, session: SessionID) async -> PlaneCopy? {
        await withCheckedContinuation { (cont: CheckedContinuation<PlaneCopy?, Never>) in
            nativeQueue.sync {
                guard session.epoch == self.currentSid, let rec = self.retainedFrames[handle] else {
                    cont.resume(returning: nil); return
                }
                guard let planes = Self.checkedPlaneCoverage(frame: rec.frame, layouts: rec.planes),
                      self.validObservationLease(handle: handle, session: session.epoch, planes: planes) else {
                    cont.resume(returning: nil); return
                }
                let rawData = rec.frame.pointee.data
                let datas = [rawData.0, rawData.1, rawData.2, rawData.3,
                             rawData.4, rawData.5, rawData.6, rawData.7]
                var out: [[UInt8]] = []
                for (p, layout) in rec.planes.enumerated() {
                    guard let base = datas[p] else { cont.resume(returning: nil); return }
                    var planeBytes: [UInt8] = []
                    planeBytes.reserveCapacity(layout.rowBytes * layout.rows)
                    var rowPtr = UnsafeRawPointer(base)
                    for rowIndex in 0..<layout.rows {
                        planeBytes.append(contentsOf: UnsafeRawBufferPointer(start: rowPtr, count: layout.rowBytes))
                        if rowIndex + 1 < layout.rows { rowPtr = rowPtr.advanced(by: layout.stride) }
                    }
                    out.append(planeBytes)
                }
                let fr = rec.frame.pointee
                let name = av_get_pix_fmt_name(AVPixelFormat(rawValue: fr.format)).map { String(cString: $0) } ?? ""
                cont.resume(returning: PlaneCopy(planes: out, width: Int(fr.width), height: Int(fr.height), format: name))
            }
        }
    }

    public func observeRetainedFrame(handle: UInt64, session: SessionID) async -> Result<FrameObservation, ObservationRefusal> {
        await withCheckedContinuation { cont in
            nativeQueue.sync {
                guard session.epoch == self.currentSid else {
                    cont.resume(returning: .failure(.foreignOrStaleSession)); return
                }
                guard let rec = self.retainedFrames[handle] else {
                    cont.resume(returning: .failure(self.leases.stage(handle: handle, session: session.epoch) == .released ? .releasedHandle : .unavailableHandle)); return
                }
                guard let planes = Self.checkedPlaneCoverage(frame: rec.frame, layouts: rec.planes) else {
                    cont.resume(returning: .failure(.unboundedPlane)); return
                }
                guard validObservationLease(handle: handle, session: session.epoch, planes: planes) else {
                    cont.resume(returning: .failure(.invalidLease)); return
                }
                let frame = rec.frame.pointee
                guard let namePointer = av_get_pix_fmt_name(AVPixelFormat(rawValue: frame.format)) else {
                    cont.resume(returning: .failure(.unavailableMetadata)); return
                }
                let name = String(cString: namePointer)
                guard !name.isEmpty else {
                    cont.resume(returning: .failure(.unavailableMetadata)); return
                }
                let value = FrameObservation(sessionEpoch: session.epoch, handle: handle,
                    selectedStreamIndex: videoStreamIndex, pixelFormat: name,
                    width: Int(frame.width), height: Int(frame.height),
                    pts: frame.pts == gorav_av_nopts_value() ? nil : frame.pts, duration: frame.duration, planes: planes)
                cont.resume(returning: .success(value))
            }
        }
    }

    /// Remains queryable after close until the next admitted open attempt.
    public func observeSessionTrace(session: SessionID) async -> Result<SessionTraceSnapshot, ObservationRefusal> {
        await withCheckedContinuation { cont in
            nativeQueue.sync {
                guard traceEpoch == session.epoch else {
                    cont.resume(returning: .failure(.traceUnavailable)); return
                }
                cont.resume(returning: .success(SessionTraceSnapshot(sessionEpoch: session.epoch,
                    capacity: 128, overflowed: traceOverflow,
                    customIOLogicalTeardown: customIOLogicalTeardown, records: traceRecords)))
            }
        }
    }

    private func markTerminal(_ event: DecodeEvent) -> DecodeEvent {
        switch event {
        case .endOfStream: trace(.terminalEOF)
        case .interrupted: trace(.terminalInterrupted)
        case .failed(let code, _): trace(.terminalFailed, code: Int32(exactly: code))
        default: break
        }
        terminated = true // queue-side only; called exclusively inside a queue turn
        return event
    }

    // MARK: - releaseFrame / interrupt / close

    /// Releases exactly the retained buffer for (session, handle). Session is
    /// verified INSIDE the queue turn (r5 S4): a foreign session id touches no
    /// state at all (r6 R5-F: no ledger mutation either - silent no-op).
    public func releaseFrame(handle: UInt64, session: SessionID) async {
        let sid = session.epoch
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            nativeQueue.sync {
                // r5 S4 / r6 R5-F: foreign/stale session touches NO state - not
                // the native frame, not the lease table, not the ledger - and
                // records NO ledger violation either: a foreign id carries no
                // valid composite key, so pretending to account it would be a
                // false claim. Deliberate silent no-op; close's report is the
                // leak channel. All updates sit inside the same owner turn as the
                // session check, so a stale handle number can never free a new one.
                guard sid == currentSid else { cont.resume(); return }
                if let rec = retainedFrames.removeValue(forKey: handle) {
                    frameOrigins.removeValue(forKey: handle)
                    var f: UnsafeMutablePointer<AVFrame>? = rec.frame
                    av_frame_free(&f)
                }
                _ = leaseTable.release(handle: handle)
                leases.released(handle, session: sid)
                cont.resume()
            }
        }
    }

    public func requestInterrupt(session: SessionID) {
        if seekState.matches(session: session.epoch) { seekState.poisonSession() }
        _ = interruptSlot.request(session: session.epoch) // stale sessions fenced no-op
    }

    /// Protocol-intact definitive close (r6 R5-C): signature unchanged from
    /// LocalVideoDecoder; the report route is the separate closeAndReport API.
    public func close(session: SessionID) async {
        _ = await closeAndReport(session: session)
    }

    /// Reporting close. The session match is decided INSIDE the queue turn
    /// (r5 S3): a foreign or already-closed session is a no-op that touches no
    /// native state and emits no report. Leaks and dropped packets reach the
    /// caller here and via lastCloseReport (r5 D14): pending packet counted once
    /// (only when not yet admitted to the feed), feed queue counted once, lease
    /// table and frame-lease ledger entries settled AND cleared (r6 R5-E).
    // AUTHORED NEW (2026-10-17, K5): seek extension. Timestamp seek with
    // AVSEEK_FLAG_BACKWARD: the next decoded frame is the keyframe at or
    // before the target. Frame-exact landing is the playback core's job
    // (discard until pts >= target); the decoder guarantees a clean,
    // flush-buffers-consistent resume point. Probe scope: single active
    // session, no in-flight events between nativeQueue turns.
    public enum SeekError: Error, Equatable {
        case noActiveSession, negativeTarget, nonFiniteTarget, outOfRange, coordinatedMode, failed(Int)
    }

    // Handle interleaving contract (K5 review r2 item 3): frames RETAINED
    // before a seek are plane-copied at retain time and stay valid after it;
    // frameDigest/releaseFrame on pre-seek handles are served normally. The
    // seek discards only PROVIDER-side in-flight state (demux position,
    // codec buffers, pending packet/feed accounting). Presentation order of
    // events after a seek restarts at the landing keyframe; consumers must
    // not compare post-seek pts against pre-seek pts for monotonicity.
    public func seek(toSeconds seconds: Double, session: SessionID) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nativeQueue.sync {
                do {
                    guard seekState.claimLegacy() else { throw SeekError.coordinatedMode }
                    guard session.epoch == currentSid, !terminated, let fmtCtx = fmt, let ctx = codecCtx else {
                        throw SeekError.noActiveSession
                    }
                    // (K5 review r2 item 2) Int64 conversion traps on inf/NaN
                    // and on magnitudes past the target space: guard first.
                    guard seconds.isFinite else { throw SeekError.nonFiniteTarget }
                    guard seconds >= 0 else { throw SeekError.negativeTarget }
                    let st = fmtCtx.pointee.streams[Int(videoStreamIndex)]!
                    let tb = st.pointee.time_base
                    guard tb.num > 0, tb.den > 0 else { throw SeekError.failed(-17) }
                    let scaled = seconds * Double(tb.den) / Double(tb.num)
                    guard scaled <= 9.007199254740992e15 else { throw SeekError.outOfRange } // 2^53 exactness bound
                    let ts = Int64(scaled)
                    // AVSEEK_FLAG_BACKWARD is a stable public ABI constant (=1).
                    let rc = av_seek_frame(fmtCtx, videoStreamIndex, ts, 1)
                    guard rc >= 0 else { throw SeekError.failed(Int(rc)) }
                    avcodec_flush_buffers(ctx)
                    // (K5 review r2 item 1) drop the read-but-unconsumed packet
                    // and reset the feed accounting, mirroring open-time init.
                    if let p = self.pendingPacket { var pp: UnsafeMutablePointer<AVPacket>? = p; av_packet_free(&pp) }
                    self.pendingPacket = nil
                    self.pendingPacketBytes = 0
                    self.pendingAdmitted = false
                    self.feed.reset()
                    pipeline = .reading
                    cont.resume()
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    @discardableResult
    public func closeAndReport(session: SessionID) async -> CloseReport? {
        let sid = session.epoch
        if seekState.matches(session: sid) {
            seekState.requestClose()
            await seekState.waitUntilSettled()
        }
        return await withCheckedContinuation { cont in
            nativeQueue.sync {
                guard sid == currentSid else { cont.resume(returning: nil); return }
                let report = nativeTeardownLocked(session: sid)
                closeReport = report
                cont.resume(returning: report)
            }
        }
    }

    /// Queue-turn teardown shared by closeAndReport() and deinit. Frees every
    /// native resource exactly once and settles + clears ALL accounting (feed,
    /// lease table, frame-lease ledger) so a future session starts clean (r6 R5-E).
    private func nativeTeardownLocked(session sid: UInt64) -> CloseReport {
        // r6 ordering: stop NEW interrupt requests, detach the provider callback,
        // close provider contexts (callback storage still ALIVE - the provider may
        // legally consult it during close), then free the slot storage last.
        interruptSlot.clear()
        if fmt != nil { fmt!.pointee.interrupt_callback = AVIOInterruptCB(callback: nil, opaque: nil) }
        if codecCtx != nil { avcodec_free_context(&codecCtx) }
        if fmt != nil { avformat_close_input(&fmt) }
        observeLogicalCustomIOClose(snapshotOwner) // format stopped using custom pb
        snapshotOwner = nil
        if let slot = interruptSlotPtr {
            slot.deinitialize(count: 1); slot.deallocate()
            interruptSlotPtr = nil
        }
        var dropped = 0
        if pendingPacket != nil {
            var p: UnsafeMutablePointer<AVPacket>? = pendingPacket
            pendingPacket = nil; pendingPacketBytes = 0
            if !pendingAdmitted { dropped = 1 } // admitted packets are in the feed count
            pendingAdmitted = false
            av_packet_free(&p)
        }
        dropped += feed.close()
        let outstanding = retainedFrames.keys.sorted()
        for (h, rec) in retainedFrames {
            var f: UnsafeMutablePointer<AVFrame>? = rec.frame
            av_frame_free(&f)
            _ = leaseTable.release(handle: h) // table cleared with the buffers
        }
        retainedFrames = [:]
        frameOrigins = [:]
        let tableLeaks = leaseTable.leakedHandles() // residual entries not backed by frames
        leaseTable.removeAll() // settled AND cleared: no stale-handle collision later
        let ledgerLeaks = leases.close(session: sid)
        trace(.closed)
        pipeline = .drained
        terminated = true
        currentSid = nil
        return CloseReport(leakedHandles: outstanding, droppedPendingPackets: dropped,
                           leaseTableLeaks: tableLeaks, ledgerLeaks: ledgerLeaks,
                           customIOLogicalTeardown: customIOLogicalTeardown)
    }

    /// r4 D11 fallback for an abandoned decoder. Deadlock-safe: a running queue
    /// block holds a strong reference, so deinit runs only while the queue is idle.
    deinit {
        func cleanup() {
            if let sid = self.currentSid {
                _ = self.nativeTeardownLocked(session: sid)
            } else if self.fmt != nil || self.codecCtx != nil {
                // committed partially outside a session cannot happen (single queue
                // turn), but free defensively without ledger accounting.
                _ = self.nativeTeardownLocked(session: 0)
            } else {
                self.teardownInterruptLocked()
            }
        }
        if DispatchQueue.getSpecific(key: nativeQueueKey) != nil { cleanup() }
        else { nativeQueue.sync(execute: cleanup) }
    }
}
