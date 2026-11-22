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
import GorAVPlaybackCore
#if canImport(CoreVideo)
import CoreVideo
#endif

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
    /// v4: entrance detection for the owner queue. A public API entered
    /// while ALREADY on this queue can only come from a borrow body
    /// (re-entrancy) and is refused, never deadlocked; borrow accessors use
    /// the same key to validate-and-read inline in the same critical section.
    private let l3QueueKey = DispatchSpecificKey<UInt8>()
    /// Queue-hop with entrance detection (v4). CONSISTENT SEMANTICS for all
    /// public entrances: READ-ONLY API (frameDigest, framePlaneCopy,
    /// framePlaneCopyDerived, l3HDRSignalInfo, observeRetainedFrame,
    /// observeSessionTrace, l3RunReport, lastCloseReport, borrow accessors,
    /// isLive) runs through l3OnQueue - inline-validated in the same
    /// critical section when called from a borrow body, queue-hopped
    /// otherwise, never deadlocked. MUTATING API (nextEvent, seek, open,
    /// openSnapshot, close, closeAndReport, releaseFrame, requestInterrupt,
    /// pinLocalRoots, withFrameLease) REFUSES at entrance when called on the
    /// queue (typed throw / nil / no-op + counted refusal), never deadlocks.
    private func l3OnQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { return try work() }
        return try nativeQueue.sync(execute: work)
    }
    private var l3ReentrantRefusals = 0
    private var currentSid: UInt64?
    private var terminated = false
    private var nextHandle: UInt64 = 0
    /// Queue-owned read: no duration fabricated for an unopened/foreign session.
    public func containerDurationTicks(session: SessionID) -> Int64? {
        l3OnQueue {
            guard currentSid == session.epoch, !terminated, let fmt else { return nil }
            let value = fmt.pointee.duration
            return value > 0 && value != gorav_av_nopts_value() ? value : nil
        }
    }
    /// Active AVIO observation only. A single native queue turn validates the
    /// caller's exact binding and copies fields; never reopens or probes a URL.
    public func activeTransportSnapshot(source: SourceToken, session: SeekSessionID,
                                        revision: SeekRevision) -> Result<ActiveTransportSnapshot, ActiveTransportRefusal> {
        l3OnQueue {
            // EOF ends decoding but the retained AVIO remains observable until close.
            guard currentSid != nil, let fmt,
                  let binding = seekState.currentBinding() else { return .failure(.notOpen) }
            guard currentSid == session.rawValue, binding.token == source,
                  binding.session == session, binding.revision == revision else { return .failure(.staleBinding) }
            return .success(ActiveTransportSnapshot.capture(fmt.pointee.pb.map { UnsafePointer($0) },
                source: source, session: session, revision: revision))
        }
    }
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
    /// fileprivate (first actual swiftc catch): the borrow-box init signature
    /// references this type and is itself fileprivate.
    fileprivate struct PlaneLayout {
        let rowBytes: Int
        let rows: Int
        let stride: Int
    }
    private struct RetainedFrame {
        let frame: UnsafeMutablePointer<AVFrame>
        let planes: [PlaneLayout]
        /// v4.2 (architect): the presentation generation this frame was
        /// retained under. A pre-seek/pre-fallback handle can no longer be
        /// borrowed or relabelled as the CURRENT presentation - acquisition
        /// checks this per-frame epoch, not the caller's.
        let presentationEpoch: UInt64
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
            // L3 (blocker 1): preserved 10-bit originals are retained with the
            // same bounded coverage discipline - 16-bit steps, no reduction.
            (AV_PIX_FMT_YUV420P10LE, [PlaneSpec(sw: 0, sh: 0, step: 2), PlaneSpec(sw: 1, sh: 1, step: 2), PlaneSpec(sw: 1, sh: 1, step: 2)]),
            (AV_PIX_FMT_P010LE, [PlaneSpec(sw: 0, sh: 0, step: 2), PlaneSpec(sw: 1, sh: 1, step: 4)]),
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
    /// R3 (arch-195b): transport options consumed by the next remote open.
    /// Read on the native queue at open time; never logged (see redactedSummary).
    private let remoteOptionsLock = NSLock()
    private var storedRemoteOptions = SourceOpenOptions()
    public var remoteOpenOptions: SourceOpenOptions {
        get { remoteOptionsLock.lock(); defer { remoteOptionsLock.unlock() }; return storedRemoteOptions }
        set { remoteOptionsLock.lock(); storedRemoteOptions = newValue; remoteOptionsLock.unlock() }
    }
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
        private let lock=NSLock()
        private var flag=false
        private var deadlineNanos:UInt64?
        func set() { lock.lock(); flag=true; lock.unlock() }
        func reset(deadlineNanos:UInt64? = nil) {
            lock.lock(); flag=false; self.deadlineNanos=deadlineNanos; lock.unlock()
        }
        func clearDeadline() { lock.lock(); deadlineNanos=nil; lock.unlock() }
        var isSet:Bool { lock.lock(); defer {lock.unlock()}; return flag }
        var deadlineExceeded:Bool {
            lock.lock(); defer {lock.unlock()}
            guard !flag, let deadlineNanos else {return false}
            return DispatchTime.now().uptimeNanoseconds >= deadlineNanos
        }
        var shouldAbort:Bool {
            lock.lock(); defer {lock.unlock()}
            if flag {return true}
            guard let deadlineNanos else {return false}
            return DispatchTime.now().uptimeNanoseconds >= deadlineNanos
        }
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
            // Pre-entry settlement from ONE atomic coordinator snapshot (peer NH6 disposition;
            // precedence is the PROPOSED technical resolution, not recovered contract policy):
            // recorded cancel (first-recorded wins) > closing flag (.close fallback; unreachable
            // once requestClose is atomic) > poison refusal > plain validation refusal.
            seekState.finishWithSnapshot(record) { snap in
                if let recorded = snap.recordedCancel { return receipt(.cancelledNoMutation(reason: recorded), cancel: true) }
                if snap.closing { return receipt(.cancelledNoMutation(reason: .close), cancel: true) }
                if snap.poisoned { return receipt(.refusedNoMutation(reason: .closed)) }   // provider refused; arbitration stays .none
                return receipt(.refusedNoMutation(reason: reason))
            }
        }
        seekDiagnostics?.beforeQueuedValidation?(record.identity)
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
            // Same atomic pre-entry settlement as refuse(): enterNative refused under a consistent
            // locked state; classify from the snapshot, never an invented .requested.
            seekState.finishWithSnapshot(record) { snap in
                if let recorded = snap.recordedCancel { return receipt(.cancelledNoMutation(reason: recorded), cancel: true) }
                if snap.closing { return receipt(.cancelledNoMutation(reason: .close), cancel: true) }
                return receipt(.refusedNoMutation(reason: .closed))   // poisoned: provider refused, arbitration .none
            }; return
        }
        seekDiagnostics?.beforeNativeCall?(record.identity)
        let rc = av_seek_frame(fmt, videoStreamIndex, ticks, 1)
        seekDiagnostics?.afterNativeReturn?(record.identity, rc)
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
        seekDiagnostics?.afterCleanupBeforeReceipt?(record.identity)
        let injectFailure = (seekDiagnostics?.failAfterRealSeekAndCleanup ?? false) && rc >= 0
        // Native queue owns origin publication; the state lock arbitrates cancellation/ready once.
        // No subsequent native queue turn can observe the interval between these two operations.
        var readyWon = false
        seekState.finish(record) { cancelled in
            if injectFailure {
                return receipt(.failed(stage: .cleanedUp, reason: .poisonedState, facts: facts,
                    poison: .closeRequired("TEST INJECTION: failure injected after real seek rc=\(rc) and real cleanup")),
                    mutation: .partial, stage: .cleanedUp, cancel: cancelled)
            }
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
            // v4 parity with the legacy seek path (ported with native101):
            // the delivery watermark and the fallback preroll mark are
            // PRE-SEEK facts. A coordinated seek decodes from the
            // pre-target keyframe (BACKWARD flag) and the pump's
            // seekLandingTarget contract discards those pre-target
            // frames - with the watermark kept, the first post-seek
            // preroll frame pts-regresses against the old mark and trips
            // the -24 presentation-order fault. Resetting here matches
            // the legacy seek path and leaves the regression guard
            // itself untouched.
            l3DiscardBeforePTS = nil
            l3LastDeliveredPTS = nil
            l3SeekPrerollBeforePTS = ticks   // native101: arm preroll skip at the seek target
            l3SeekPrerollSkipped = 0
            l3SeekPrerollSeen = 0
            l3PresentationEpoch &+= 1
            eventOrigin = EventOrigin(session: request.session, source: request.source,
                providerRevision: record.reservedRevision, requestOrigin: .transaction(record.identity.transactionID))
        } else { deregisterDecoderOnQueue(); terminated = true }
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

    /// TEST-ONLY seek seam (90d: bounded INTERNAL ProbeKit seam, no public API). `package` access:
    /// visible to sibling targets of this package (the G5 suites), NOT to external importers. It is
    /// constructor-only: the production `init()` installs none, and nothing mutates it afterwards.
    package struct SeekDiagnostics: Sendable {
        package var beforeQueuedValidation: (@Sendable (SeekEventIdentity) -> Void)?
        package var beforeNativeCall: (@Sendable (SeekEventIdentity) -> Void)?
        package var afterNativeReturn: (@Sendable (SeekEventIdentity, Int32) -> Void)?
        package var afterCleanupBeforeReceipt: (@Sendable (SeekEventIdentity) -> Void)?
        /// Inject a failure AFTER a real successful av_seek_frame + real cleanup. The receipt keeps the
        /// REAL rc/facts and is labeled TEST INJECTION; it proves the partial-mutation/poison path, not
        /// an organic FFmpeg failure.
        package var failAfterRealSeekAndCleanup: Bool
        package init(beforeQueuedValidation: (@Sendable (SeekEventIdentity) -> Void)? = nil,
                     beforeNativeCall: (@Sendable (SeekEventIdentity) -> Void)? = nil,
                     afterNativeReturn: (@Sendable (SeekEventIdentity, Int32) -> Void)? = nil,
                     afterCleanupBeforeReceipt: (@Sendable (SeekEventIdentity) -> Void)? = nil,
                     failAfterRealSeekAndCleanup: Bool = false) {
            self.beforeQueuedValidation = beforeQueuedValidation
            self.beforeNativeCall = beforeNativeCall
            self.afterNativeReturn = afterNativeReturn
            self.afterCleanupBeforeReceipt = afterCleanupBeforeReceipt
            self.failAfterRealSeekAndCleanup = failAfterRealSeekAndCleanup
        }
    }
    private let seekDiagnostics: SeekDiagnostics?

    private let nativeQueueKey = DispatchSpecificKey<UInt8>()
    private let decoderInventory: DecoderInventoryStore
    private var decoderInventoryID: DecoderIdentity?
    private var cachedMediaInventory: MediaInventory?
    private func deregisterDecoderOnQueue() {
        cachedMediaInventory=nil
        if let id=decoderInventoryID { decoderInventory.deregister(id) }
        decoderInventoryID=nil
    }
    /// Copies the cached inventory of the current context. This never opens a
    /// URL or probes stream info. An old source/session/revision is refused.
    public func activeMediaInventory(session:SessionID,
                                    expected:ActiveMediaInventoryIdentity? = nil) -> ActiveMediaInventorySnapshot? {
        guard DispatchQueue.getSpecific(key:l3QueueKey) == nil else { return nil }
        return nativeQueue.sync {
            guard self.currentSid == session.epoch, !self.terminated,
                  self.seekState.activeTransaction == nil,
                  let inventory=self.cachedMediaInventory,
                  let binding=self.seekState.currentBinding() else { return nil }
            let identity=ActiveMediaInventoryIdentity(
                sourceID:"video:\(binding.token.instanceID):\(binding.token.openGeneration)",
                session:session.epoch,revision:binding.revision.rawValue,
                presentationEpoch:self.l3PresentationEpoch)
            guard expected == nil || expected == identity else { return nil }
            return ActiveMediaInventorySnapshot(identity:identity,inventory:inventory)
        }
    }
    public init(decoderInventory: DecoderInventoryStore = .shared) {
        self.decoderInventory=decoderInventory
        seekDiagnostics = nil; nativeQueue.setSpecific(key: nativeQueueKey, value: 1); nativeQueue.setSpecific(key: l3QueueKey, value: 1) }
    package init(testSeekDiagnostics diag: SeekDiagnostics) {
        self.decoderInventory = .shared
        seekDiagnostics = diag; nativeQueue.setSpecific(key: nativeQueueKey, value: 1); nativeQueue.setSpecific(key: l3QueueKey, value: 1)
    }
    /// L3 (2026-10-25, formats/hardware-decode lane): queue-owned hardware
    /// session and pixel converter, committed with the session, torn down with
    /// it. The report is captured at teardown and stays queryable post-close.
    private var l3HW: L3HardwareSession?
    private var l3PixConv: L3PixelConverter?
    public struct L3RunReport: Equatable, Sendable {
        public let sessionEpoch: UInt64
        public let hardware: L3HardwareSession.Receipt?
        public let pixelConvertedFrames: Int
        public let pixelConversionFailures: Int
        /// Typed per-source-format reduction counts (L5 seam).
        public let pixelConversionSources: [String: Int]
        /// v4: resume pts of each CONFIRMED software reopen (generation is
        /// this session's epoch) - the a/v continuity coordination fact L1
        /// consumes; delivered frame count; scoped-borrow receipt; and the
        /// re-entrant-call refusal count.
        public let fallbackResumePTS: [Int64]
        public let deliveredFrames: Int
        public let borrow: L3BorrowReceipt
        public let reentrantRefusals: Int
        /// v4.2 (blocker 5): this session's video seek count - pairs with the
        /// audio decoder's seekCount so the coordinator's joint seeks are
        /// visible in both reports.
        public let seekCount: Int
    }
    private var l3LastReport = L3RunReport(sessionEpoch: 0, hardware: nil, pixelConvertedFrames: 0, pixelConversionFailures: 0, pixelConversionSources: [:], fallbackResumePTS: [], deliveredFrames: 0, borrow: L3BorrowReceipt(), reentrantRefusals: 0, seekCount: 0)
    /// Session-bound (review: an unbound read can serve a STALE session's
    /// receipt). Returns nil for any epoch but the one the report belongs to.
    public func l3RunReport(session: SessionID) -> L3RunReport? {
        l3OnQueue {
            // v4.3 (architect r5): materialize LIVE while this session is
            // active - a close-time-only report made the fallback surface
            // postmortem-only. Post-close, the frozen last-close report
            // still serves its own epoch.
            if self.currentSid == session.epoch, !self.terminated {
                return L3RunReport(sessionEpoch: session.epoch,
                                   hardware: self.l3HW?.receipt,
                                   pixelConvertedFrames: self.l3PixConv?.convertedFrames ?? 0,
                                   pixelConversionFailures: self.l3PixConv?.conversionFailures ?? 0,
                                   pixelConversionSources: self.l3PixConv?.conversionSources ?? [:],
                                   fallbackResumePTS: self.l3FallbackResumePTS,
                                   deliveredFrames: self.l3DeliveredCount,
                                   borrow: self.l3BorrowStats,
                                   reentrantRefusals: self.l3ReentrantRefusals,
                                   seekCount: self.l3SeekCount)
            }
            return l3LastReport.sessionEpoch == session.epoch ? l3LastReport : nil
        }
    }
    /// Preroll/dedup watermark after a hardware->software fallback (blocker 2):
    /// frames re-decoded from the seek-back keyframe with pts below the failed
    /// frame's pts are ALREADY-DELIVERED duplicates - decoded, never emitted.
    private var l3DiscardBeforePTS: Int64?
    /// native101 (ported from the vendored embedded copy, train f61829c
    /// compile fix): post-seek preroll skip window, armed by both seek
    /// paths. Mirrors the fallback preroll discard - decoded, never
    /// retained, never emitted - but keyed to the seek TARGET rather
    /// than a fallback resume mark. Skipping here removes the per-frame
    /// plane copies + RGBA conversion + pump drop + ledger line that
    /// native99 B2 measured at ~227ms/frame. The -24 order guard only
    /// compares DELIVERED pts, so a skipped window cannot trip it. The
    /// window closes at the first frame at/above the target; a no-pts
    /// frame neither skips nor closes it. The pump's preSeekLanding
    /// predicate stays as the backstop for sources that still emit
    /// preroll.
    private var l3SeekPrerollBeforePTS: Int64?
    /// native101 observability: count of frames skipped by the window
    /// above, so a still-slow catch-up shows source-side progress (the
    /// pump-side seekLandingDrops counter now stays 0 on this path by
    /// design).
    private var l3SeekPrerollSkipped = 0
    /// native101r3 (goreda T2: the r2 sticky-leak defect): per-window
    /// count of EVERY pre-target frame, skipped or leaked. The leak
    /// guard keys on THIS counter - keying on l3SeekPrerollSkipped
    /// (skips only) sticks at 31 and leaks everything after the first
    /// burst.
    private var l3SeekPrerollSeen = 0
    private var l3LastDeliveredPTS: Int64?
    /// v4: presentation generation - bumped on every seek and every fallback
    /// reopen so a borrow pin from an older presentation typed-refuses.
    private var l3PresentationEpoch: UInt64 = 0
    private var l3DeliveredCount = 0
    private var l3SeekCount = 0
    /// v4.3 (R2Y trunk seam): the admitted video stream's time_base,
    /// captured at open and validated; surfaces on DecodeEvent.opened and
    /// every FrameObservation. Never inferred from pts.
    private var l3PTSTimeBaseNum: Int32 = 0
    private var l3PTSTimeBaseDen: Int32 = 0
    private var l3FallbackResumePTS: [Int64] = []

    /// Read of the last close report; the read itself is a queue turn.
    public var lastCloseReport: CloseReport? { l3OnQueue { closeReport } }
    /// native101 (ported): skipped-preroll count; the read itself is a
    /// queue turn.
    public var seekPrerollSkipped: Int { l3OnQueue { l3SeekPrerollSkipped } }

    // MARK: - pinned local roots (r5 D12)

    /// Pins the local roots admitted for open. Callable only while idle (no active
    /// session); the decision is a queue turn. Roots are symlink-resolved once here.
    /// Empty roots (the default) refuse every open - there is no implicit "/".
    public func pinLocalRoots(_ roots: [String]) throws {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { throw OpenError.rejected("re-entrant call from a borrow body") }
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
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { throw OpenError.rejected("re-entrant call from a borrow body") }
        try await openImpl(source: source, snapshot: nil, session: session)
    }

    /// Source-only first-fixture route; SHA implementation qualification remains gated.
    public func openSnapshot(_ snapshot: ImmutableInputSnapshot, session: SessionID) async throws {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { throw OpenError.rejected("re-entrant call from a borrow body") }
        guard snapshot.expectedBytes == 574,
              snapshot.sha256Hex == "009889e24805044e676ce86f9d26ed3b8cd60e9a014d623ef4e0ef48ed451fa9" else {
            throw OpenError.rejected("snapshot outside first-fixture pin")
        }
        try await openImpl(source: nil, snapshot: snapshot, session: session)
    }

    private func remoteOpenFailure(_ phase:String, _ code:Int32) -> OpenError {
        if interruptBox.isSet { return .rejected("remote \(phase) interrupted") }
        if interruptBox.deadlineExceeded { return .rejected("remote \(phase) deadline exceeded") }
        return .providerFailed(code:Int(code)) // no URL/header/cookie disclosure
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
                    if let source = source, AdmissionTable.schemeGatedKinds.contains(source.kind) {
                        // queue 31/32: remote and iptv admission is decided HERE, before any
                        // network access. Scheme allowlist only (http, https).
                        guard AdmissionTable.isAdmittedSource(kind: source.kind) else {
                            throw OpenError.rejected("decoder-only probe admits local sources only")
                        }
                        guard AdmissionTable.isAdmittedRemoteURL(source.id) else {
                            throw OpenError.rejected("\(source.kind) scheme not admitted: \(AdmissionTable.remoteScheme(of: source.id) ?? "(none)")")
                        }
                        resolvedPath = source.id
                    } else if let source = source {
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

                    // 195b-62: immutable, typed validation before any fence/network.
                    let remoteOptions:SourceOpenOptions?
                    if let source, AdmissionTable.schemeGatedKinds.contains(source.kind) {
                        do { remoteOptions=try remoteOpenOptions.validatedForOpen() }
                        catch { throw OpenError.rejected("invalid remote open options") }
                    } else { remoteOptions=nil }

                    // Interrupt plumbing BEFORE any blocking provider call (r5 D03,
                    // r6 ownership): the slot is OPEN-ATTEMPT-LOCAL until commit.
                    // A failed attempt tears down only its own local storage and
                    // never touches any state of another (live) session. The
                    // sessionBusy rejection above throws before this point, so the
                    // fence install below can only run when no session is active.
                    traceEpoch = sid; traceRecords = []; traceOverflow = false; traceSequence = 0
                    customIOLogicalTeardown = .absent
                    videoStreamIndex = -1
                    interruptBox.reset(deadlineNanos:remoteOptions?.openDeadlineNanos())
                    usedEpochs.insert(sid) // spent at first fence exposure (r8 ruling)
                    interruptSlot.install(session: sid) { [weak self] in self?.interruptBox.set() }
                    attemptFenceInstalled = true
                    let attemptSlot = UnsafeMutablePointer<GorAVInterruptSlot>.allocate(capacity: 1)
                    attemptSlotForTeardown = attemptSlot
                    attemptSlot.initialize(to: GorAVInterruptSlot(
                        poll: { opaque in
                            guard let opaque = opaque else { return 0 }
                            return Unmanaged<InterruptBox>.fromOpaque(opaque).takeUnretainedValue().shouldAbort ? 1 : 0
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
                        if let remoteOptions {
                            guard let allocated=avformat_alloc_context() else {
                                throw OpenError.rejected("remote format context allocation failed")
                            }
                            // Install before URL open, not after a blocking connect.
                            allocated.pointee.interrupt_callback=AVIOInterruptCB(
                                callback:gorav_avio_interrupt_thunk,
                                opaque:UnsafeMutableRawPointer(attemptSlot))
                            opened=allocated
                            openRC=goravR3OpenInput(&opened,url:path,options:remoteOptions)
                        } else {
                            openRC = path.withCString { avformat_open_input(&opened, $0, nil, nil) }
                        }
                    }
                    var rc = openRC
                    guard rc == 0, let fmtCtx = opened else {
                        // Pinned demux.c open failure frees context and NULLs pointer.
                        // Defensive remaining context cleanup precedes custom IO defer.
                        if let remaining = opened { avformat_free_context(remaining); opened = nil }
                        if remoteOptions != nil { throw remoteOpenFailure("open",rc) }
                        throw NativeError.failed(Int(rc), "avformat_open_input failed")
                    }
                    fmtCtx.pointee.interrupt_callback = AVIOInterruptCB(
                        callback: gorav_avio_interrupt_thunk,
                        opaque: UnsafeMutableRawPointer(attemptSlot))

                    let container = String(cString: fmtCtx.pointee.iformat.pointee.name)
                    guard snapshot != nil ? container == "ppm_pipe" : AdmissionTable.probeContainers.contains(container) else {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-2, "demux admission rejected: container \(container)")
                    }

                    rc = avformat_find_stream_info(fmtCtx, nil)
                    guard rc >= 0 else {
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        if remoteOptions != nil { throw remoteOpenFailure("stream info",rc) }
                        if rc == gorav_av_err_exit() { throw NativeError.failed(Int(rc), "open interrupted") }
                        throw NativeError.failed(Int(rc), "avformat_find_stream_info failed")
                    }

                    var videoCount = 0, audioCount = 0, otherCount = 0, subtitleCount = 0
                    var videoIndex: Int32 = -1
                    var audioIndex: Int32 = -1
                    for i in 0..<Int32(fmtCtx.pointee.nb_streams) {
                        switch fmtCtx.pointee.streams[Int(i)]?.pointee.codecpar?.pointee.codec_type ?? AVMEDIA_TYPE_UNKNOWN {
                        case AVMEDIA_TYPE_VIDEO: videoCount += 1; if videoIndex < 0 { videoIndex = i }
                        case AVMEDIA_TYPE_AUDIO: audioCount += 1; if audioIndex < 0 { audioIndex = i }
                        case AVMEDIA_TYPE_SUBTITLE: subtitleCount += 1
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
                                                    otherStreamCount: otherCount, subtitleStreamCount: subtitleCount, audioCodecName: audioCodecName) {
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
                    // L3: attach VideoToolbox BEFORE open2 for policy-admitted
                    // codecs (h264/hevc) so format negotiation is measured by
                    // the session receipt. AV1 stays software-by-policy. A
                    // failed attach records -1/-2 and decode proceeds in
                    // software - the first clean-fallback arm.
                    let l3hw = L3HardwareSession()
                    // P30/W2 (arch-197b): arm the zero-copy receive path from
                    // policy (GORAV_VT_ZEROCOPY=1). Inert unless VT frames
                    // actually arrive.
                    l3hw.armZeroCopy()
                    let independentProducer = VTHardwareFrameProducer(source: SourceSession(session: sid, revision: 0))
                    let wantsVT = AdmissionTable.shouldAttemptHardware(videoCodec: codecName, environment: ProcessInfo.processInfo.environment)
                    var attached = false
                    if wantsVT {
                        let preparation = try independentProducer.prepareBeforeOpen(localCtx!)
                        attached = preparation == .hardwareAttached
                        l3hw.nativeProducer = independentProducer
                        l3hw.noteIndependentAttach(attached)
                        if let reason = independentProducer.receipt.fallbackReason { l3hw.noteFallbackReason(reason) }
                    }
                    var codecOpenRC = avcodec_open2(localCtx, codec, nil)
                    if codecOpenRC < 0 && attached {
                        // open2 failed WITH hw attached: detach and retry
                        // software-only on a FRESH context (v4 architect: a
                        // failed avcodec_open2 leaves the context undefined;
                        // reusing it was not a clean fallback).
                        l3hw.detachForSoftwareReopen(codecContext: localCtx!)
                        avcodec_free_context(&localCtx)
                        localCtx = avcodec_alloc_context3(codec)
                        if let fresh = localCtx,
                           avcodec_parameters_to_context(fresh, fmtCtx.pointee.streams[Int(videoIndex)]!.pointee.codecpar) >= 0 {
                            fresh.pointee.thread_count = 1
                            if independentProducer.requestFreshSoftwareRetry(reason: "vt-codec-open-failed") {
                                _ = try independentProducer.prepareBeforeOpen(fresh)
                            }
                            codecOpenRC = avcodec_open2(fresh, codec, nil)
                            if codecOpenRC >= 0 { l3hw.noteSoftwareReopenSucceeded() }
                        } else {
                            avcodec_free_context(&localCtx)
                            codecOpenRC = -1
                        }
                    }
                    guard codecOpenRC >= 0 else {
                        avcodec_free_context(&localCtx)
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-6, "avcodec_open2 failed")
                    }

                    // v4.3 (R2Y trunk seam): capture the PRODUCING stream's
                    // time_base at open; an invalid rational is a typed open
                    // refusal, never a guessed default or an inferred value.
                    guard let openStream = fmtCtx.pointee.streams[Int(videoIndex)] else {
                        avcodec_free_context(&localCtx)
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-27, "admitted stream missing at open")
                    }
                    let openTB = openStream.pointee.time_base
                    guard openTB.num > 0, openTB.den > 0 else {
                        avcodec_free_context(&localCtx)
                        var c: UnsafeMutablePointer<AVFormatContext>? = fmtCtx
                        avformat_close_input(&c)
                        throw NativeError.failed(-28, "stream time_base invalid (num=\(openTB.num) den=\(openTB.den))")
                    }

                    // v4.2 (architect): per-session report state starts
                    // CLEAN - delivered count, fallback resume points, borrow
                    // receipt, re-entry refusals and the presentation epoch
                    // are this session's facts, not an accumulation over
                    // every session this instance has run.
                    self.l3DeliveredCount = 0
                    self.l3SeekCount = 0
                    self.l3FallbackResumePTS = []
                    self.l3BorrowStats = L3BorrowReceipt()
                    self.l3ReentrantRefusals = 0
                    self.l3PresentationEpoch = 0
                    self.l3DiscardBeforePTS = nil
                    self.l3LastDeliveredPTS = nil
                    // Commit (single queue turn, so visible atomically to all callers).
                    feed.reset()
                    self.snapshotOwner = attemptSnapshotOwner
                    attemptSnapshotOwner = nil // ownership commits with format/session
                    self.fmt = fmtCtx
                    self.codecCtx = localCtx
                    self.videoStreamIndex = videoIndex
                    self.l3PTSTimeBaseNum = openTB.num
                    self.l3PTSTimeBaseDen = openTB.den
                    trace(.selectedStream)
                    self.pipeline = .reading
                    self.l3HW = l3hw
                    self.l3PixConv = L3PixelConverter()
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
                    cachedMediaInventory=MediaInventory.extract(fromOpenedContext:fmtCtx)
                    // Register only after open committed. Hardware-backed lifetime
                    // tracking is a separate row; do not mislabel it as software.
                    if self.l3HW == nil || self.l3HW?.receipt.attempted == false || self.l3HW?.receipt.attachResult != 0 || self.l3HW?.receipt.fallbackArmed == true {
                        self.decoderInventoryID=self.decoderInventory.register(session:sid,
                            kind:.videoSoftware,codec:codecName,
                            sourceID:"video:\(token.instanceID):\(token.openGeneration)",
                            revisionAtOpen:SeekRevision.atOpen.rawValue)
                    }
                    interruptBox.clearDeadline() // reads remain cancellation-only
                    cont.resume()
                } catch let e as NativeError {
                    if attemptFenceInstalled { trace(.terminalFailed) }
                    if attemptFenceInstalled { observeLogicalCustomIOClose(attemptSnapshotOwner) }
                    attemptSnapshotOwner = nil // callback owner freed before interrupt slot
                    // r6: failure teardown is ATTEMPT-LOCAL. The gate at the top
                    // guarantees no session is active here, so clearing the fence
                    // is safe; self.interruptSlotPtr (a previous session's storage)
                    // is never touched by a failed attempt.
                    if attemptFenceInstalled { interruptSlot.clear(); interruptBox.clearDeadline() }
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
                    if attemptFenceInstalled { interruptSlot.clear(); interruptBox.clearDeadline() }
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
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { self.l3ReentrantRefusals += 1; return nil }
        return await withCheckedContinuation { cont in
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
        guard let fmt = fmt, codecCtx != nil else { return nil }
        if pipeline == .drained { return nil }

        var scratchOpt: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard scratchOpt != nil else { return markTerminal(.failed(code: -10, summary: "av_frame_alloc failed")) }
        defer { av_frame_free(&scratchOpt) }
        let scratch = scratchOpt!

        var iterations = 0
        var prerollSkipsThisTurn = 0   // native101r3 (ported): per-turn skip cap (see below)
        while iterations < 128 {
            iterations += 1

            // v4 (architect, URGENT STOP): the codec context is RE-BOUND at
            // every loop boundary. The hardware-failure branch below frees
            // the old context and installs a fresh software one via
            // l3ReopenSoftwareLocked; continuing with the pre-loop binding
            // after that reopen was a use-after-free of the freed context.
            guard let ctx = codecCtx else {
                return markTerminal(.failed(code: -22, summary: "codec context lost mid-pipeline"))
            }
            let recvRC = avcodec_receive_frame(ctx, scratch)
            if recvRC == 0 {
                guard var kept = av_frame_clone(scratch) else {
                    return markTerminal(.failed(code: -7, summary: "av_frame_clone allocation failed"))
                }
                // L3 begin: hardware frames transfer out of VideoToolbox;
                // admitted 10-bit software frames convert to yuv420p 8-bit;
                // anything else keeps the trunk's honest refusal below.
                if let hw = self.l3HW {
                    var keptOpt: UnsafeMutablePointer<AVFrame>? = kept
                    // P30/W2: an armed session keeps VT frames GPU-resident
                    // (no av_hwframe_transfer_data); the unarmed path and
                    // all software frames are byte-identical to before.
                    switch hw.zeroCopyArmed ? hw.processReceivedFrameZeroCopy(&keptOpt) : hw.processReceivedFrame(&keptOpt) {
                    case .ok:
                        guard let k = keptOpt else {
                            return markTerminal(.failed(code: -18, summary: "L3 frame processing dropped frame"))
                        }
                        kept = k
                    case .refused(let summary):
                        if keptOpt != nil { var k: UnsafeMutablePointer<AVFrame>? = keptOpt; av_frame_free(&k) }
                        return markTerminal(.failed(code: -18, summary: summary))
                    case .hardwareFailed(let code):
                        // kept already freed. MEASURED software fallback
                        // (blocker 2 rework): a REAL provider reopen - the
                        // hw-attached codec context is freed and a fresh
                        // software-only context opened from the same codecpar
                        // (flush alone does not renegotiate get_format; NULL
                        // get_format mid-stream is not a contract). Then seek
                        // back and discard already-delivered preroll.
                        // Missing pts has NO resume point: typed failure,
                        // never a guessed seek-to-0.
                        guard scratch.pointee.pts != gorav_av_nopts_value() else {
                            return markTerminal(.failed(code: -21, summary: "hardware failure on a frame without pts; no honest resume point"))
                        }
                        let resumeTS = scratch.pointee.pts
                        guard self.l3ReopenSoftwareLocked(hw: hw, resumePTS: resumeTS) else {
                            return markTerminal(.failed(code: -19, summary: "hardware decode failed (rc=\(code)); software provider reopen failed"))
                        }
                        if self.pendingPacket != nil { var p: UnsafeMutablePointer<AVPacket>? = self.pendingPacket; av_packet_free(&p) }
                        self.pendingPacket = nil; self.pendingPacketBytes = 0; self.pendingAdmitted = false
                        self.feed.reset()
                        self.pipeline = .reading
                        self.l3DiscardBeforePTS = resumeTS
                        // v4: the fallback is OBSERVABLE (a/v continuity
                        // coordination is L1's; the fact is producer-typed)
                        // and the presentation generation bumps.
                        self.l3FallbackResumePTS.append(resumeTS)
                        self.l3PresentationEpoch &+= 1  // wrapping: no overflow trap
                        continue
                    }
                }
                // L3 (blocker 1): 10-bit frames are PRESERVED ORIGINALS - the
                // existing allowlist table below now includes yuv420p10le and
                // p010le, so they retain with bounded coverage, true canonical
                // pixelFormatName, and their HDR side data intact. The 8-bit
                // 8-bit reduction is a derived product available ONLY
                // through framePlaneCopyDerived; it never runs at retain
                // time, and HDR sources refuse it without preview consent.
                // P30/W2 (arch-197b): a VT-format frame from an ARMED
                // zero-copy session is retained GPU-resident - the software
                // pixel-format classification does not apply to it (it has
                // no CPU planes by design).
                let zeroCopyVT = kept.pointee.format == gorav_l3_pixfmt_videotoolbox() && (self.l3HW?.zeroCopyArmed ?? false)
                if !zeroCopyVT, L3PixelPolicy.classification(kept.pointee.format) == .refuse {
                    var f: UnsafeMutablePointer<AVFrame>? = kept
                    av_frame_free(&f)
                    return markTerminal(.failed(code: -15, summary: "unsupported or unbounded pixel layout"))
                }
                // Preroll dedup after hw->sw fallback (v4 rework): frames
                // re-decoded from the seek-back keyframe carry pts BELOW the
                // failed frame's pts - decoded, never emitted. A preroll
                // frame WITHOUT pts has no honest placement: typed terminal
                // failure, and the mark is NOT cleared (the old code let a
                // missing pts pass and clear the discard).
                if let mark = self.l3DiscardBeforePTS {
                    let pts = kept.pointee.pts
                    guard pts != gorav_av_nopts_value() else {
                        var f: UnsafeMutablePointer<AVFrame>? = kept
                        av_frame_free(&f)
                        return markTerminal(.failed(code: -23, summary: "preroll frame without pts after fallback"))
                    }
                    if pts < mark {
                        var f: UnsafeMutablePointer<AVFrame>? = kept
                        av_frame_free(&f)
                        continue
                    }
                    self.l3DiscardBeforePTS = nil
                }
                // native101 (ported): post-seek preroll skip (window armed
                // by both seek paths). Mirrors the fallback preroll
                // discard above - decoded, never retained, never emitted -
                // but keyed to the seek TARGET rather than a fallback
                // resume mark. Skipping here removes the per-frame plane
                // copies + RGBA conversion + pump drop + ledger line that
                // native99 B2 measured at ~227ms/frame. The -24 order
                // guard below only compares DELIVERED pts, so a skipped
                // window cannot trip it.
                if let mark = self.l3SeekPrerollBeforePTS {
                    if kept.pointee.pts != gorav_av_nopts_value() {
                        if kept.pointee.pts < mark {
                            // native101r3 (ported; goreda T2): (a) the leak
                            // guard keyed on the SKIPPED-only counter
                            // sticks at 31 and then leaks every remaining
                            // pre-target frame - the guard now keys on
                            // l3SeekPrerollSeen, which counts EVERY
                            // pre-target frame (skipped or leaked), so the
                            // leak is truly every 32nd; (b) the -9 stall
                            // guard (128 iterations/turn) bounds ONE queue
                            // turn - a fresh turn may already hold
                            // iterations, so skips are also capped PER
                            // TURN at 24 (24 skips ~<= 72 iterations + one
                            // emission < 128), forcing a leak/yield
                            // before the guard can trip. A leak is an
                            // honest frameDecoded that ends the turn; the
                            // pump's preSeekLanding backstop drops it.
                            self.l3SeekPrerollSeen += 1
                            if self.l3SeekPrerollSeen % 32 != 0, prerollSkipsThisTurn < 24 {
                                self.l3SeekPrerollSkipped += 1
                                prerollSkipsThisTurn += 1
                                var f: UnsafeMutablePointer<AVFrame>? = kept
                                av_frame_free(&f)
                                continue
                            }
                        } else {
                            self.l3SeekPrerollBeforePTS = nil
                        }
                    }
                }
                // v4 presentation order (architect): frame identity is
                // (pts, decode order). The decoder emits presentation order,
                // so an EQUAL pts is a new legitimate frame and DELIVERS
                // (the old <= guard dropped it and could hide an order
                // fault); only a pts REGRESSION is a fault - typed terminal,
                // never a silent drop.
                if let last = self.l3LastDeliveredPTS, kept.pointee.pts != gorav_av_nopts_value(),
                   kept.pointee.pts < last {
                    var f: UnsafeMutablePointer<AVFrame>? = kept
                    av_frame_free(&f)
                    return markTerminal(.failed(code: -24, summary: "presentation order fault: pts regression"))
                }
                // L3 end.
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
                // P30/W2: a zero-copy VT frame carries NO CPU planes. It is
                // retained with an empty layout set (every CPU accessor
                // typed-refuses on it) and the lease accounts the frame's
                // GPU-resident footprint - the bi-planar w*h*3/2 estimate,
                // CHECKED arithmetic like the CPU coverage path - against the
                // same outstanding budget, so VT retention stays bounded.
                let layouts: [PlaneLayout]
                let coverageBytes: Int
                if zeroCopyVT {
                    layouts = []
                    let (px, o1) = Int(kept.pointee.width).multipliedReportingOverflow(by: Int(kept.pointee.height))
                    let (est3, o2) = px.multipliedReportingOverflow(by: 3)
                    guard !o1, !o2 else {
                        var f: UnsafeMutablePointer<AVFrame>? = kept
                        av_frame_free(&f)
                        return markTerminal(.failed(code: -12, summary: "VT frame geometry overflow"))
                    }
                    coverageBytes = est3 / 2
                } else {
                    guard let l = Self.planeLayouts(format: AVPixelFormat(rawValue: kept.pointee.format),
                                                          width: Int(kept.pointee.width),
                                                          height: Int(kept.pointee.height),
                                                          linesizes: linesizes),
                          let coverage = Self.checkedPlaneCoverage(frame: kept, layouts: l),
                          let b = Self.checkedCoverageBytes(coverage) else {
                        var f: UnsafeMutablePointer<AVFrame>? = kept
                        av_frame_free(&f)
                        return markTerminal(.failed(code: -15, summary: "unsupported or unbounded pixel layout"))
                    }
                    layouts = l; coverageBytes = b
                }
                retainedFrames[handle] = RetainedFrame(frame: kept, planes: layouts,
                                                       presentationEpoch: self.l3PresentationEpoch)
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
                if nf.pts != nil { self.l3LastDeliveredPTS = nf.pts }
                self.l3DeliveredCount += 1
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
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            l3OnQueue {
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
    /// Queue item 13 (2026-11-08): raw linesize-PADDED plane copy for
    /// frame-dump --raw-planes. planes[p] is one contiguous stride*rows slice
    /// per plane, padding INCLUDED. Same session/handle/coverage/lease gates
    /// as framePlaneCopy; additionally refuses (nil) unless every plane's
    /// FULL padded region (planeOffset + stride*rows) lies inside its
    /// verified containing buffer - padding is dumped only when provably
    /// readable. No fallback, no clipping.
    public struct RawPlaneCopy: Sendable {
        public let planes: [[UInt8]]
        public let strides: [Int]
        public let rowBytes: [Int]
        public let rows: [Int]
        public let width: Int
        public let height: Int
        public let format: String
    }
    public func framePlaneCopyRaw(handle: UInt64, session: SessionID) async -> RawPlaneCopy? {
        await withCheckedContinuation { (cont: CheckedContinuation<RawPlaneCopy?, Never>) in
            l3OnQueue {
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
                var strides: [Int] = []
                var rowBytesOut: [Int] = []
                var rowsOut: [Int] = []
                for obs in planes {
                    guard let base = datas[obs.index] else { cont.resume(returning: nil); return }
                    let (rawCount, mulOverflow) = obs.stride.multipliedReportingOverflow(by: obs.rows)
                    guard !mulOverflow, rawCount > 0, let rawCountU = UInt(exactly: rawCount) else {
                        cont.resume(returning: nil); return
                    }
                    let (rawEnd, addOverflow) = obs.planeOffset.addingReportingOverflow(rawCountU)
                    guard !addOverflow, rawEnd <= obs.containingBufferExtent else {
                        cont.resume(returning: nil); return
                    }
                    out.append(Array(UnsafeRawBufferPointer(start: base, count: rawCount)))
                    strides.append(obs.stride)
                    rowBytesOut.append(obs.rowBytes)
                    rowsOut.append(obs.rows)
                }
                let fr = rec.frame.pointee
                let name = av_get_pix_fmt_name(AVPixelFormat(rawValue: fr.format)).map { String(cString: $0) } ?? ""
                cont.resume(returning: RawPlaneCopy(planes: out, strides: strides, rowBytes: rowBytesOut,
                                                    rows: rowsOut, width: Int(fr.width), height: Int(fr.height),
                                                    format: name))
            }
        }
    }
    public func framePlaneCopy(handle: UInt64, session: SessionID) async -> PlaneCopy? {
        await withCheckedContinuation { (cont: CheckedContinuation<PlaneCopy?, Never>) in
            l3OnQueue {
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
            l3OnQueue {
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
                    pts: frame.pts == gorav_av_nopts_value() ? nil : frame.pts, duration: frame.duration,
                    ptsTimeBaseNum: self.l3PTSTimeBaseNum, ptsTimeBaseDen: self.l3PTSTimeBaseDen,
                    planes: planes)
                cont.resume(returning: .success(value))
            }
        }
    }

    /// Remains queryable after close until the next admitted open attempt.
    public func observeSessionTrace(session: SessionID) async -> Result<SessionTraceSnapshot, ObservationRefusal> {
        await withCheckedContinuation { cont in
            l3OnQueue {
                guard traceEpoch == session.epoch else {
                    cont.resume(returning: .failure(.traceUnavailable)); return
                }
                cont.resume(returning: .success(SessionTraceSnapshot(sessionEpoch: session.epoch,
                    capacity: 128, overflowed: traceOverflow,
                    customIOLogicalTeardown: customIOLogicalTeardown, records: traceRecords)))
            }
        }
    }

    /// L3 (blocker 2): real software provider reopen after a hardware
    /// failure, inside the owner queue turn. The old hw-attached context is
    /// freed (its callbacks die with it BEFORE the hw receipt storage can be
    /// touched), a fresh context opens software-only from the same codecpar,
    /// and the demuxer seeks back to the failed frame's pts. One re-arm per
    /// session: a second hardware failure cannot occur (no hw attached), so
    /// the old "up to 3" claim is gone.
    private func l3ReopenSoftwareLocked(hw: L3HardwareSession, resumePTS: Int64) -> Bool {
        guard let fmtCtx = self.fmt, let oldCtx = self.codecCtx, !hw.receipt.fallbackArmed else { return false }
        hw.detachForSoftwareReopen()
        guard let params = fmtCtx.pointee.streams[Int(videoStreamIndex)]?.pointee.codecpar,
              let codec = avcodec_find_decoder(params.pointee.codec_id) else {
            var c: UnsafeMutablePointer<AVCodecContext>? = oldCtx
            avcodec_free_context(&c)
            self.codecCtx = nil
            return false
        }
        guard let newCtx = avcodec_alloc_context3(codec) else {
            var c: UnsafeMutablePointer<AVCodecContext>? = oldCtx
            avcodec_free_context(&c)
            self.codecCtx = nil
            return false
        }
        // v4 (architect): the old combined guard LEAKED newCtx when
        // parameters_to_context failed - the guards are split and every
        // branch frees exactly what it owns.
        guard avcodec_parameters_to_context(newCtx, params) >= 0 else {
            var nc: UnsafeMutablePointer<AVCodecContext>? = newCtx
            avcodec_free_context(&nc)
            var c: UnsafeMutablePointer<AVCodecContext>? = oldCtx
            avcodec_free_context(&c)
            self.codecCtx = nil
            return false
        }
        newCtx.pointee.thread_count = 1
        var openedCtx: UnsafeMutablePointer<AVCodecContext>? = newCtx
        guard avcodec_open2(newCtx, codec, nil) >= 0 else {
            avcodec_free_context(&openedCtx)
            var c: UnsafeMutablePointer<AVCodecContext>? = oldCtx
            avcodec_free_context(&c)
            self.codecCtx = nil
            return false
        }
        var c: UnsafeMutablePointer<AVCodecContext>? = oldCtx
        avcodec_free_context(&c)
        self.codecCtx = newCtx
        guard av_seek_frame(fmtCtx, videoStreamIndex, resumePTS, 1) >= 0 else { return false }
        hw.noteSoftwareReopenSucceeded()
        return true
    }

    /// v4.3 (architect r5): the ACTUAL source signal carried on every
    /// derived copy - matrix/range/TRC/primaries as tagged on the producing
    /// frame plus the coefficient set actually applied. No false provenance:
    /// "unspecified" stays "unspecified", never a guessed label.
    public struct L3SignalProvenance: Equatable, Sendable {
        public let sourceTransfer: String
        public let sourcePrimaries: String
        public let sourceMatrix: String
        public let sourceRange: String
        public let matrixApplied: String   // "none" (direct copy) or the coefficient set used
        /// v4.4 (r6 g5): the DERIVED OUTPUT's range descriptor - the shim
        /// tags converted output limited; a direct copy keeps the source
        /// range. The source tag alone never described the output.
        public let outputRange: String
        public init(sourceTransfer: String, sourcePrimaries: String, sourceMatrix: String,
                    sourceRange: String, matrixApplied: String, outputRange: String = "unspecified") {
            self.sourceTransfer = sourceTransfer; self.sourcePrimaries = sourcePrimaries
            self.sourceMatrix = sourceMatrix; self.sourceRange = sourceRange
            self.matrixApplied = matrixApplied; self.outputRange = outputRange
        }
    }
    /// v4.3: what the derived 8-bit copy IS. Bit-depth reduction NEVER
    /// tone-maps; every case carries the source's actual signal provenance.
    public enum L3DerivedPresentation: Equatable, Sendable {
        case direct8bit(L3SignalProvenance)                     // copied through, no conversion
        case sdrCompatible(L3SignalProvenance)                  // verifiably SDR source, reduced
        case notRenderablePreview(L3SignalProvenance)           // HDR/unknown signal, reduced precision
    }
    public enum L3DerivedCopyError: Error, Equatable {
        case foreignOrStaleSession
        case unavailableHandle
        case invalidLease
        case unsupportedLayout
        case conversionFailed
        /// HDR or untagged-HDR-capable source requested without
        /// allowUnrenderablePreview - refusal, never a mislabeled render.
        case hdrSourceRequiresPreviewConsent
        /// A combination this lane cannot convert CORRECTLY (e.g. the
        /// bt2020 CONSTANT-LUMINANCE matrix - reducing it with the NCL
        /// matrix is a wrong transform, so it refuses).
        case unsupportedSignalCombination
        /// v4.4 (r6 g6): the derived yuv420p allocation for this geometry
        /// would exceed the aggregate copy cap - refused BEFORE allocating.
        case oversizeCopy
    }
    public struct L3PlaneCopyDerived: Sendable {
        public let planes: [[UInt8]]
        public let width: Int
        public let height: Int
        public let format: String          // canonical name of the RETURNED planes
        public let presentation: L3DerivedPresentation
    }
    /// Actual signal facts of a frame, named via libavutil (unspecified
    /// stays "unspecified").
    private static func l3Provenance(of f: AVFrame, matrixApplied: String, outputRange: String = "unspecified") -> L3SignalProvenance {
        let trc = av_color_transfer_name(f.color_trc).map { String(cString: $0) } ?? "unspecified"
        let prim = av_color_primaries_name(f.color_primaries).map { String(cString: $0) } ?? "unspecified"
        let csp = av_color_space_name(f.colorspace).map { String(cString: $0) } ?? "unspecified"
        let range: String
        switch f.color_range {
        case AVCOL_RANGE_MPEG: range = "limited"
        case AVCOL_RANGE_JPEG: range = "full"
        default: range = "unspecified"
        }
        return L3SignalProvenance(sourceTransfer: trc, sourcePrimaries: prim,
                                  sourceMatrix: csp, sourceRange: range, matrixApplied: matrixApplied,
                                  outputRange: outputRange)
    }
    /// HDR-capable detector (v4.3): PQ/HLG transfer OR bt2020 primaries OR a
    /// bt2020 matrix - including UNSPECIFIED-transfer frames that carry a
    /// bt2020 matrix/primaries (an unknown transfer does not escape).
    /// arch-196x item 2 (v4.4 amendment): mastering-display metadata or
    /// content-light level side data is positive HDR evidence on its own.
    /// v4.4 (r6 g5): SDR-compatible is a POSITIVE proof, not "not HDR".
    /// Only bt709/sRGB transfer with no HDR markers counts; an unknown or
    /// exotic transfer on a non-HDR frame types as notRenderablePreview.
    /// arch-196x item 2 amends the UNTAGGED case only: transfer, primaries
    /// and matrix ALL unspecified with no HDR side data types SDR under the
    /// same guess the default mpv path makes (l3IsParitySDR below).
    private static func l3IsProvenSDR(_ f: AVFrame) -> Bool {
        return f.color_trc == AVCOL_TRC_BT709 || f.color_trc == AVCOL_TRC_IEC61966_2_1
    }
    private static func l3HasHDRSideData(_ fp: UnsafeMutablePointer<AVFrame>) -> Bool {
        if av_frame_get_side_data(fp, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA) != nil { return true }
        if av_frame_get_side_data(fp, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL) != nil { return true }
        return false
    }
    private static func l3IsHDRSignal(_ fp: UnsafeMutablePointer<AVFrame>) -> Bool {
        let f = fp.pointee
        if f.color_trc == AVCOL_TRC_SMPTE2084 || f.color_trc == AVCOL_TRC_ARIB_STD_B67 { return true }
        if f.color_primaries == AVCOL_PRI_BT2020 { return true }
        if f.colorspace == AVCOL_SPC_BT2020_NCL || f.colorspace == AVCOL_SPC_BT2020_CL { return true }
        if l3HasHDRSideData(fp) { return true }
        return false
    }
    /// arch-196x item 2 (v4.4 amendment, mpv parity): a FULLY untagged frame
    /// (transfer, primaries and matrix all unspecified) with no HDR side
    /// data types SDR. Anything partly tagged keeps the r6 g5 rule above.
    private static func l3IsParitySDR(_ fp: UnsafeMutablePointer<AVFrame>) -> Bool {
        let f = fp.pointee
        guard f.color_trc == AVCOL_TRC_UNSPECIFIED,
              f.color_primaries == AVCOL_PRI_UNSPECIFIED,
              f.colorspace == AVCOL_SPC_UNSPECIFIED else { return false }
        return !l3HasHDRSideData(fp)
    }
    /// arch-196x item 2 (mpv parity): matrix guess for an unspecified source
    /// matrix - bt709 at width>=1280 or height>576, else bt601 (the default
    /// mpv path's guess). Named in provenance; the C shim selects the same
    /// coefficient set by the same rule.
    private static func l3ParityMatrixName(width: Int32, height: Int32) -> String {
        return (width >= 1280 || height > 576)
            ? "itu709(source-matrix-unspecified,mpv-parity)"
            : "itu601(source-matrix-unspecified,mpv-parity)"
    }
    /// v4.3 (architect r5): the derived 8-bit copy, honest for every source
    /// class. The HDR/consent gate runs BEFORE the direct/converted split -
    /// an 8-bit PQ/HLG/bt2020 frame no longer bypasses consent through the
    /// direct path. bt2020-CL refuses (wrong transform, never converted as
    /// NCL). SDR matrices convert with their OWN coefficient set (601
    /// sources are no longer forced through 709). Output range is limited
    /// and TAGGED limited in the C shim (the source's full-range tag is not
    /// inherited). The real HDR transform stays L5's, off the preserved
    /// original via withFrameLease - never this helper.
    public func framePlaneCopyDerived(handle: UInt64, session: SessionID,
                                      allowUnrenderablePreview: Bool = false) async throws -> L3PlaneCopyDerived {
        try await withCheckedThrowingContinuation { cont in
            l3OnQueue {
                guard session.epoch == self.currentSid, !self.terminated else {
                    cont.resume(throwing: L3DerivedCopyError.foreignOrStaleSession); return
                }

                guard let rec = self.retainedFrames[handle] else {
                    cont.resume(throwing: L3DerivedCopyError.unavailableHandle); return
                }
                // P30/W2 (arch-197b): a retained VT frame (armed zero-copy
                // session) has no CPU planes - the derived product requires
                // the REAL hardware transfer first (counted as a CPU frame
                // copy in the session receipt). The transferred frame runs
                // through the same consent gate, matrix naming and bounded
                // plane copies below; its lease check is the handle's
                // allocation stage (the retained VT frame's lease accounts a
                // GPU-footprint estimate, not CPU coverage bytes).
                var vtTransfer: UnsafeMutablePointer<AVFrame>?
                defer { if vtTransfer != nil { av_frame_free(&vtTransfer) } }
                let sourceFrame: UnsafeMutablePointer<AVFrame>
                let sourceLayouts: [PlaneLayout]
                if rec.frame.pointee.format == gorav_l3_pixfmt_videotoolbox() {
                    guard let hw = self.l3HW, hw.zeroCopyArmed,
                          let sw = hw.transferToSoftwareCopy(rec.frame) else {
                        cont.resume(throwing: L3DerivedCopyError.conversionFailed); return
                    }
                    vtTransfer = sw
                    sourceFrame = sw
                    let ls = [sw.pointee.linesize.0, sw.pointee.linesize.1, sw.pointee.linesize.2, sw.pointee.linesize.3,
                              sw.pointee.linesize.4, sw.pointee.linesize.5, sw.pointee.linesize.6, sw.pointee.linesize.7].map { Int($0) }
                    guard let l = Self.planeLayouts(format: AVPixelFormat(rawValue: sw.pointee.format),
                                                    width: Int(sw.pointee.width),
                                                    height: Int(sw.pointee.height),
                                                    linesizes: ls) else {
                        cont.resume(throwing: L3DerivedCopyError.unsupportedLayout); return
                    }
                    sourceLayouts = l
                } else {
                    sourceFrame = rec.frame
                    sourceLayouts = rec.planes
                }
                guard let planesChecked = Self.checkedPlaneCoverage(frame: sourceFrame, layouts: sourceLayouts) else {
                    cont.resume(throwing: L3DerivedCopyError.invalidLease); return
                }
                if vtTransfer == nil {
                    guard self.validObservationLease(handle: handle, session: session.epoch, planes: planesChecked) else {
                        cont.resume(throwing: L3DerivedCopyError.invalidLease); return
                    }
                } else {
                    guard self.leases.stage(handle: handle, session: session.epoch) == .allocated else {
                        cont.resume(throwing: L3DerivedCopyError.invalidLease); return
                    }
                }
                let f = sourceFrame.pointee
                // Consent gate FIRST (v4.3 r5): covers the direct path too.
                let hdrSource = Self.l3IsHDRSignal(sourceFrame)
                if hdrSource && !allowUnrenderablePreview {
                    cont.resume(throwing: L3DerivedCopyError.hdrSourceRequiresPreviewConsent); return
                }
                // bt2020 CONSTANT-LUMINANCE cannot be correctly reduced with
                // the NCL matrix - refuse in both paths.
                if f.colorspace == AVCOL_SPC_BT2020_CL {
                    cont.resume(throwing: L3DerivedCopyError.unsupportedSignalCombination); return
                }
                let srcFmt = AVPixelFormat(rawValue: f.format)
                switch L3PixelPolicy.classification(f.format) {
                case .direct:
                    let rawData = f.data
                    let datas = [rawData.0, rawData.1, rawData.2, rawData.3, rawData.4, rawData.5, rawData.6, rawData.7]
                    var out: [[UInt8]] = []
                    for (p, layout) in sourceLayouts.enumerated() {
                        guard let base = datas[p] else {
                            cont.resume(throwing: L3DerivedCopyError.unsupportedLayout); return
                        }
                        var planeBytes: [UInt8] = []
                        planeBytes.reserveCapacity(layout.rowBytes * layout.rows)
                        var rowPtr = UnsafeRawPointer(base)
                        for rowIndex in 0..<layout.rows {
                            planeBytes.append(contentsOf: UnsafeRawBufferPointer(start: rowPtr, count: layout.rowBytes))
                            if rowIndex + 1 < layout.rows { rowPtr = rowPtr.advanced(by: layout.stride) }
                        }
                        out.append(planeBytes)
                    }
                    let name = av_get_pix_fmt_name(srcFmt).map { String(cString: $0) } ?? ""
                    let prov = Self.l3Provenance(of: f, matrixApplied: "none", outputRange: {
                        switch f.color_range { case AVCOL_RANGE_MPEG: return "limited"
                        case AVCOL_RANGE_JPEG: return "full"; default: return "unspecified" } }())
                    cont.resume(returning: L3PlaneCopyDerived(planes: out, width: Int(f.width),
                        height: Int(f.height), format: name,
                        presentation: hdrSource ? .notRenderablePreview(prov) : .direct8bit(prov)))
                case .preservedOriginal:
                    // v4.4 (r6 g6): the derived allocation is BOUNDED BEFORE
                    // it happens - padded yuv420p geometry vs the aggregate
                    // cap (the same arithmetic the C shim enforces).
                    // v4.4 repair (r6 g6): the estimate is the shim's EXACT
                    // av_frame_get_buffer model (ceil chroma, 32-row padded
                    // height, per-buffer alignment overhead) - the old inline
                    // arithmetic floored odd chroma widths and ignored the
                    // allocation's real padding, so it was not a bound.
                    let est = gorav_l3_yuv420p_alloc_estimate(f.width, f.height)
                    guard est > 0, est <= Int64(FFmpegSoftwareDecoder.borrowAggregateCap) else {
                        cont.resume(throwing: L3DerivedCopyError.oversizeCopy); return
                    }
                    // v4.4 repair (r6 g5): a KNOWN matrix the shim does not
                    // map (fcc, smpte240m, ycgco, ictcp, ...) is refused BEFORE
                    // any conversion runs - typed refusal, zero allocation.
                    // Only unspecified falls back to 709, and says so.
                    let applied: String
                    switch f.colorspace {
                    case AVCOL_SPC_BT470BG, AVCOL_SPC_SMPTE170M: applied = "itu601"
                    case AVCOL_SPC_BT2020_NCL: applied = "itu2020ncl"
                    case AVCOL_SPC_BT709: applied = "itu709"
                    case AVCOL_SPC_UNSPECIFIED: applied = Self.l3ParityMatrixName(width: f.width, height: f.height)
                    default:
                        cont.resume(throwing: L3DerivedCopyError.unsupportedSignalCombination); return
                    }
                    guard let conv = self.l3PixConv,
                          let sdr = conv.convertToYUV420P(sourceFrame) else {
                        cont.resume(throwing: L3DerivedCopyError.conversionFailed); return
                    }
                    defer { var tmp: UnsafeMutablePointer<AVFrame>? = sdr; av_frame_free(&tmp) }
                    let w = Int(sdr.pointee.width), h = Int(sdr.pointee.height)
                    let ls = sdr.pointee.linesize
                    let strides = [Int(ls.0), Int(ls.1), Int(ls.2)]
                    let rows = [h, (h + 1) / 2, (h + 1) / 2]
                    let widths = [w, (w + 1) / 2, (w + 1) / 2]
                    let datas = [sdr.pointee.data.0, sdr.pointee.data.1, sdr.pointee.data.2]
                    var out: [[UInt8]] = []
                    for p in 0..<3 {
                        guard let base = datas[p], strides[p] >= widths[p], widths[p] > 0 else {
                            cont.resume(throwing: L3DerivedCopyError.conversionFailed); return
                        }
                        var planeBytes: [UInt8] = []
                        var rowPtr = UnsafeRawPointer(base)
                        for rowIndex in 0..<rows[p] {
                            planeBytes.append(contentsOf: UnsafeRawBufferPointer(start: rowPtr, count: widths[p]))
                            if rowIndex + 1 < rows[p] { rowPtr = rowPtr.advanced(by: strides[p]) }
                        }
                        out.append(planeBytes)
                    }
                    // Provenance: the SOURCE frame's tags, plus the matrix
                    // actually applied (decided and refused pre-conversion
                    // above; the shim enforces the same contract at the C
                    // boundary).
                    let prov = Self.l3Provenance(of: f, matrixApplied: applied, outputRange: "limited")
                    let presentation: L3DerivedPresentation = hdrSource
                        ? .notRenderablePreview(prov)
                        : (Self.l3IsProvenSDR(f) || Self.l3IsParitySDR(sourceFrame) ? .sdrCompatible(prov) : .notRenderablePreview(prov))
                    cont.resume(returning: L3PlaneCopyDerived(planes: out, width: w, height: h,
                        format: "yuv420p",
                        presentation: presentation))
                case .refuse:
                    cont.resume(throwing: L3DerivedCopyError.unsupportedLayout)
                }
            }
        }
    }

    /// v4 (L5/architect): typed presence policy for signal enums. Strings
    /// alone are not a capability contract: known values carry the canonical
    /// name AND the raw value; unspecified and unknown are DISTINCT typed
    /// states - no silent signal-primary or chroma assumption as fact.
    public enum L3SignalValue: Equatable, Sendable {
        case value(name: String, raw: Int32)
        case unspecified
        case unknown(raw: Int32)
    }
    public struct L3XY: Equatable, Sendable { public let x: Double; public let y: Double }

    public struct L3HDRSignalInfo: Equatable, Sendable {
        public let colorPrimaries: L3SignalValue
        public let transferCharacteristic: L3SignalValue
        public let colorSpace: L3SignalValue
        public let colorRange: L3SignalValue
        /// v4 (L5): AVFrame chroma sample location, verbatim and typed.
        public let chromaLocation: L3SignalValue
        public let hasMasteringDisplay: Bool
        /// v4 (L5): mastering display primaries, GBR order (matching
        /// AVMasteringDisplayMetadata.display_primaries), plus white point -
        /// present only when the side data carries has_primaries.
        public let masteringPrimaries: [L3XY]?
        public let masteringWhitePoint: L3XY?
        public let masteringMaxLuminance: Double?
        public let masteringMinLuminance: Double?
        public let hasContentLight: Bool
        public let maxCLL: Int?
        public let maxFALL: Int?
    }

    private static func l3SignalValue<E>(_ raw: E, _ unspecified: E,
                                         _ name: (E) -> UnsafePointer<CChar>?) -> L3SignalValue
        where E: RawRepresentable & Equatable, E.RawValue: FixedWidthInteger {
        if raw == unspecified { return .unspecified }
        guard let n = name(raw) else { return .unknown(raw: Int32(clamping: raw.rawValue)) }
        return .value(name: String(cString: n), raw: Int32(clamping: raw.rawValue))
    }

    /// Shared builder (v4): l3HDRSignalInfo and the scoped borrow expose the
    /// SAME descriptor, read off the SAME retained original frame inside the
    /// SAME session/PTS identity - metadata and pixels are one lease.
    private static func l3BuildHDRInfo(_ frame: UnsafeMutablePointer<AVFrame>) -> L3HDRSignalInfo {
        let f = frame.pointee
        let prim = l3SignalValue(f.color_primaries, AVCOL_PRI_UNSPECIFIED) { av_color_primaries_name($0) }
        let trc = l3SignalValue(f.color_trc, AVCOL_TRC_UNSPECIFIED) { av_color_transfer_name($0) }
        let csp = l3SignalValue(f.colorspace, AVCOL_SPC_UNSPECIFIED) { av_color_space_name($0) }
        let rng = l3SignalValue(f.color_range, AVCOL_RANGE_UNSPECIFIED) { av_color_range_name($0) }
        let chroma = l3SignalValue(f.chroma_location, AVCHROMA_LOC_UNSPECIFIED) { av_chroma_location_name($0) }
        let v = gorav_l3_hdr_values(frame)
        func rational(_ num: Int32, _ den: Int32) -> Double? { den > 0 ? Double(num) / Double(den) : nil }
        var primaries: [L3XY]?
        var whitePoint: L3XY?
        if v.mastering_has_prim != 0 {
            let pn = [v.prim_num.0, v.prim_num.1, v.prim_num.2, v.prim_num.3, v.prim_num.4, v.prim_num.5]
            let pd = [v.prim_den.0, v.prim_den.1, v.prim_den.2, v.prim_den.3, v.prim_den.4, v.prim_den.5]
            var pts: [L3XY] = []
            for i in 0..<3 {
                guard let x = rational(pn[i*2], pd[i*2]), let y = rational(pn[i*2+1], pd[i*2+1]) else { break }
                pts.append(L3XY(x: x, y: y))
            }
            if pts.count == 3 { primaries = pts }
            if let wx = rational(v.wp_num.0, v.wp_den.0), let wy = rational(v.wp_num.1, v.wp_den.1) {
                whitePoint = L3XY(x: wx, y: wy)
            }
        }
        return L3HDRSignalInfo(
            colorPrimaries: prim, transferCharacteristic: trc, colorSpace: csp, colorRange: rng,
            chromaLocation: chroma,
            hasMasteringDisplay: v.has_mastering != 0,
            masteringPrimaries: primaries,
            masteringWhitePoint: whitePoint,
            masteringMaxLuminance: v.mastering_has_lum != 0 ? rational(v.max_lum_num, v.max_lum_den) : nil,
            masteringMinLuminance: v.mastering_has_lum != 0 ? rational(v.min_lum_num, v.min_lum_den) : nil,
            hasContentLight: v.has_cll != 0,
            maxCLL: v.has_cll != 0 ? Int(v.max_cll) : nil,
            maxFALL: v.has_cll != 0 ? Int(v.max_fall) : nil)
    }

    /// Session+handle bound HDR descriptor for a retained original frame.
    /// Same frame, same lease, same typed policy as the scoped borrow.
    public func l3HDRSignalInfo(handle: UInt64, session: SessionID) async -> L3HDRSignalInfo? {
        return await withCheckedContinuation { (cont: CheckedContinuation<L3HDRSignalInfo?, Never>) in
            l3OnQueue {
                guard session.epoch == self.currentSid, !self.terminated,
                      let rec = self.retainedFrames[handle],
                      let planes = Self.checkedPlaneCoverage(frame: rec.frame, layouts: rec.planes),
                      self.validObservationLease(handle: handle, session: session.epoch, planes: planes) else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: Self.l3BuildHDRInfo(rec.frame))
            }
        }
    }

#if canImport(CoreVideo)
    /// P30/W2 (arch-197b): the extracted, RETAINED CVPixelBuffer of a
    /// retained VT frame plus the facts the present path needs. nil on any
    /// check failure - extraction never guesses.
    public struct VTFrameLeaseInfo: Sendable {
        public let pixelBuffer: CVPixelBuffer
        public let width: Int
        public let height: Int
        public let cvPixelFormat: OSType
        public let ioSurfaceBacked: Bool
        public let hdr: L3HDRSignalInfo
    }

    /// P30/W2 (arch-197b): extract a retained VT frame's CVPixelBuffer for
    /// the zero-copy present path. Runs inside the decoder's owner turn:
    /// session, termination, zero-copy arm, retained handle, VT format,
    /// lease stage and the data[3] buffer are ALL validated before the
    /// buffer escapes; ARC retains the buffer, so the lease outlives the
    /// caller's releaseFrame safely. The colour descriptor is the frame's
    /// own typed HDR info - the same source the borrow path exposes.
    /// Independent native producer dispatch. Original retained epoch is
    /// checked before the caller's provenance is admitted. This unit does not
    /// touch decoder close order. Revision >0 refuses until an explicit
    /// verified barrier maps presentation revision into producer binding.
    public func nativeSourceFrame(handle: UInt64, session: SessionID,
                                  provenance: NativeFrameProvenance) async -> SourceFrame? {
        await withCheckedContinuation { continuation in
            l3OnQueue {
                guard session.epoch == self.currentSid, !self.terminated,
                      let rec = self.retainedFrames[handle],
                      rec.presentationEpoch == self.l3PresentationEpoch,
                      self.leases.stage(handle: handle, session: session.epoch) == .allocated,
                      let producer = self.l3HW?.nativeProducer else {
                    continuation.resume(returning: nil); return
                }
                do {
                    let value = try producer.retainSourceFrame(UnsafePointer(rec.frame), provenance: provenance,
                        timebase: AVRational(num: self.l3PTSTimeBaseNum, den: self.l3PTSTimeBaseDen))
                    continuation.resume(returning: value)
                } catch {
                    self.l3HW?.noteFallbackReason("vt-native-payload-refused")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func vtFrameLease(handle: UInt64, session: SessionID) async -> VTFrameLeaseInfo? {
        return await withCheckedContinuation { (cont: CheckedContinuation<VTFrameLeaseInfo?, Never>) in
            l3OnQueue {
                guard session.epoch == self.currentSid, !self.terminated,
                      let hw = self.l3HW, hw.zeroCopyArmed,
                      let rec = self.retainedFrames[handle],
                      rec.frame.pointee.format == gorav_l3_pixfmt_videotoolbox(),
                      self.leases.stage(handle: handle, session: session.epoch) == .allocated,
                      let data3 = rec.frame.pointee.data.3 else {
                    cont.resume(returning: nil); return
                }
                let pb = Unmanaged<CVPixelBuffer>.fromOpaque(UnsafeRawPointer(data3)).takeUnretainedValue()
                cont.resume(returning: VTFrameLeaseInfo(
                    pixelBuffer: pb,
                    width: CVPixelBufferGetWidth(pb),
                    height: CVPixelBufferGetHeight(pb),
                    cvPixelFormat: CVPixelBufferGetPixelFormatType(pb),
                    ioSurfaceBacked: CVPixelBufferGetIOSurface(pb) != nil,
                    hdr: Self.l3BuildHDRInfo(rec.frame)))
            }
        }
    }
#endif

    /// P30/W2 present-path counter pass-throughs (the receipt is owned by
    /// the decoder's L3HardwareSession; the shell performs the operations).
    /// Each call records an ACTUAL operation the caller performed - the
    /// same contract as L3HardwareSession.note*. No-ops for a stale session
    /// or a session without a hardware receipt.
    public func l3NotePresentCPUYUVtoRGB(session: SessionID) {
        l3OnQueue { guard session.epoch == self.currentSid else { return }; self.l3HW?.noteCPUYUVtoRGB() }
    }
    public func l3NotePresentIOSurface(session: SessionID) {
        l3OnQueue { guard session.epoch == self.currentSid else { return }; self.l3HW?.noteIOSurfaceBackedFrames() }
    }
    public func l3NoteFallbackReason(session: SessionID, reason: String) {
        l3OnQueue { guard session.epoch == self.currentSid else { return }; self.l3HW?.noteFallbackReason(reason) }
    }

    // MARK: - L3 scoped frame borrow v4 (L6 producer-owned lease, 2026-10-25)

    /// Central copy caps (v4.4, exact arithmetic per r6 g6):
    /// DCI-4K 10-bit 4:2:0 is luma 4096*2160*2 = 17,694,720 B plus two
    /// chroma planes of 2048*1080*2 = 4,423,680 B each - 26,542,080 B total
    /// (UHD 3840*2160*2 luma 16,588,800 fits 16 MiB with only 1.1% margin;
    /// DCI luma does NOT fit 16 MiB). Per copy 32 MiB covers ONE DCI-4K
    /// 10-bit plane; it does NOT cover every frame the geometry bound
    /// admits - a 16k luma plane (15360*8640*2 > 256 MiB) is typed-refused
    /// BY this cap, which is the enforcement, not coverage. Aggregate
    /// 128 MiB is PER BORROW TURN, not a global pending cap; a full
    /// DCI-4K 10-bit set (26.5 MB) fits several times over. Caps stay
    /// finite and central; a caller maxBytes can only tighten them.
    public static let borrowPerCopyCap = 32 << 20
    public static let borrowAggregateCap = 128 << 20

    public enum L3BorrowError: Error, Equatable {
        case cancelled
        case foreignOrStaleSession
        case unavailableHandle
        case invalidLease
        case ptsMismatch(expected: Int64, actual: Int64)
        /// v4: expectedPTS is REQUIRED; a frame without pts has no identity.
        case missingFramePTS
        case presentationEpochMismatch(expected: UInt64, actual: UInt64)
        case reentrancy
    }

    public enum L3CopyRefusal: Equatable, Sendable {
        case invalidated
        case staleSession
        case badIndex(requested: Int, available: Int)
        case oversize(requested: Int, limit: Int)
        case aggregateBudgetExceeded(used: Int, limit: Int)
        case malformedZeroLength
        /// v4.2: the side-data ENTRY exists but its payload pointer is nil -
        /// a malformed frame, never reportable as absence.
        case malformedNilData
    }

    /// Typed copy outcome (v4): bytes, absence and refusal are distinct -
    /// nothing collapses to a bare nil.
    public enum L3CopyResult: Equatable, Sendable {
        case bytes([UInt8])
        case absent
        case refused(L3CopyRefusal)
    }

    public struct L3BorrowReceipt: Equatable, Sendable {
        public var acquired = 0
        public var copies = 0
        public var copyBytes = 0
        public var refusals = 0
        public init() {}
    }

    /// Lease state box (v4): the frame pointer is NILLED when the borrow's
    /// owner turn ends. Every accessor re-validates session + liveness AND
    /// reads INSIDE the owner's critical section (l3OnQueue) - a check split
    /// from the read is not enough, and a stashed or returned borrow
    /// typed-refuses instead of touching a dangling AVFrame.
    fileprivate final class L3BorrowBox {
        var frame: UnsafeMutablePointer<AVFrame>?
        let owner: FFmpegSoftwareDecoder
        let sessionEpoch: UInt64
        var bytesCopied = 0
        init(frame: UnsafeMutablePointer<AVFrame>, owner: FFmpegSoftwareDecoder, sessionEpoch: UInt64) {
            self.frame = frame; self.owner = owner; self.sessionEpoch = sessionEpoch
        }
    }

    public struct L3FrameBorrow {
        public let sessionEpoch: UInt64
        /// Presentation generation at acquisition (bumps on seek/fallback).
        public let presentationEpoch: UInt64
        public let streamIndex: Int
        public let handle: UInt64
        public let pts: Int64
        public let duration: Int64
        public let pixelFormat: String
        public let width: Int
        public let height: Int
        public let isKeyFrame: Bool
        public let hdr: L3HDRSignalInfo
        public let planeCount: Int
        /// True only while the borrow's owner turn is live. v4.1: validated
        /// INSIDE the owner critical section (an unsynchronized box.frame
        /// read raced the turn-end invalidation).
        public var isLive: Bool {
            box.owner.l3OnQueue {
                box.sessionEpoch == box.owner.currentSid && !box.owner.terminated && box.frame != nil
            }
        }
        private let box: L3BorrowBox
        private let layouts: [PlaneLayout]

        fileprivate init(sessionEpoch: UInt64, presentationEpoch: UInt64, streamIndex: Int,
                         handle: UInt64, pts: Int64, duration: Int64, pixelFormat: String,
                         width: Int, height: Int, isKeyFrame: Bool, hdr: L3HDRSignalInfo,
                         box: L3BorrowBox, layouts: [PlaneLayout]) {
            self.sessionEpoch = sessionEpoch; self.presentationEpoch = presentationEpoch
            self.streamIndex = streamIndex; self.handle = handle; self.pts = pts
            self.duration = duration; self.pixelFormat = pixelFormat
            self.width = width; self.height = height; self.isKeyFrame = isKeyFrame
            self.hdr = hdr; self.planeCount = layouts.count
            self.box = box; self.layouts = layouts
        }

        /// Bounded copy of one side-data payload (L6: AV_FRAME_DATA_DOVI_RPU_BUFFER
        /// for the bounded RPU copy). Validate-and-read run in the SAME owner
        /// critical section. Absence, malformation and oversize are TYPED.
        public func sideDataCopy(_ kind: AVFrameSideDataType, maxBytes: Int) -> L3CopyResult {
            box.owner.l3AccessBorrow(box) { frame, box in
                guard let sd = av_frame_get_side_data(frame, kind) else { return .absent }
                guard let data = sd.pointee.data else { return .refused(.malformedNilData) }
                let size = Int(sd.pointee.size)
                guard size > 0 else { return .refused(.malformedZeroLength) }
                let limit = min(maxBytes, FFmpegSoftwareDecoder.borrowPerCopyCap)
                guard size <= limit else { return .refused(.oversize(requested: size, limit: limit)) }
                guard box.bytesCopied + size <= FFmpegSoftwareDecoder.borrowAggregateCap else {
                    return .refused(.aggregateBudgetExceeded(used: box.bytesCopied, limit: FFmpegSoftwareDecoder.borrowAggregateCap))
                }
                return .bytes(Array(UnsafeBufferPointer(start: data, count: size)))
            }
        }

        /// Bounded copy of one retained plane's VISIBLE bytes (rowBytes x
        /// rows, stride-advanced). Checked arithmetic, central caps, typed.
        public func planeCopy(_ index: Int, maxBytes: Int) -> L3CopyResult {
            box.owner.l3AccessBorrow(box) { frame, box in
                guard index >= 0, index < layouts.count else {
                    return .refused(.badIndex(requested: index, available: layouts.count))
                }
                let layout = layouts[index]
                let (total, overflow) = layout.rowBytes.multipliedReportingOverflow(by: layout.rows)
                guard !overflow, total > 0 else { return .refused(.malformedZeroLength) }
                let limit = min(maxBytes, FFmpegSoftwareDecoder.borrowPerCopyCap)
                guard total <= limit else { return .refused(.oversize(requested: total, limit: limit)) }
                guard box.bytesCopied + total <= FFmpegSoftwareDecoder.borrowAggregateCap else {
                    return .refused(.aggregateBudgetExceeded(used: box.bytesCopied, limit: FFmpegSoftwareDecoder.borrowAggregateCap))
                }
                let rawData = frame.pointee.data
                let datas = [rawData.0, rawData.1, rawData.2, rawData.3, rawData.4, rawData.5, rawData.6, rawData.7]
                guard let base = datas[index] else { return .absent }
                var out: [UInt8] = []
                out.reserveCapacity(total)
                var rowPtr = UnsafeRawPointer(base)
                for rowIndex in 0..<layout.rows {
                    out.append(contentsOf: UnsafeRawBufferPointer(start: rowPtr, count: layout.rowBytes))
                    if rowIndex + 1 < layout.rows { rowPtr = rowPtr.advanced(by: layout.stride) }
                }
                return .bytes(out)
            }
        }
    }

    /// Validate-and-read in the SAME owner critical section (v4): liveness,
    /// session and the pointer read are never split across the lock. Runs
    /// inline inside a borrow body (same queue), hops the queue otherwise.
    fileprivate func l3AccessBorrow(_ box: L3BorrowBox,
                                    _ work: (UnsafeMutablePointer<AVFrame>, L3BorrowBox) -> L3CopyResult) -> L3CopyResult {
        l3OnQueue {
            guard box.sessionEpoch == self.currentSid, !self.terminated else { return .refused(.staleSession) }
            guard let frame = box.frame else { self.l3BorrowStats.refusals += 1; return .refused(.invalidated) }
            let result = work(frame, box)
            switch result {
            case .bytes(let b):
                box.bytesCopied += b.count
                self.l3BorrowStats.copies += 1
                self.l3BorrowStats.copyBytes += b.count
            case .refused:
                self.l3BorrowStats.refusals += 1
            case .absent:
                break
            }
            return result
        }
    }

    private var l3BorrowStats = L3BorrowReceipt()

    /// Producer-owned scoped lease (v4). Bounds: session epoch, stream,
    /// handle retention, lease stage, REQUIRED expected PTS (missing pts has
    /// no borrow identity - typed .missingFramePTS, no sentinel), optional
    /// presentation-epoch pin (a pre-seek/pre-fallback borrow typed-refuses
    /// against the new presentation). The body executes INSIDE the owner
    /// queue turn; cancellation is checked before the queue AND again after
    /// admission (post-wait). Re-entrant calls into this decoder from the
    /// body are detected at entrance and refused, never deadlocked. The
    /// frame pointer is invalidated mechanically when the turn ends; data
    /// escapes only as typed bounded copies, inside or after the body (after
    /// the turn, accessors typed-refuse).
    public func withFrameLease<T>(handle: UInt64, session: SessionID,
                                  expectedPTS: Int64,
                                  expectedPresentationEpoch: UInt64? = nil,
                                  _ body: (L3FrameBorrow) throws -> T) async throws -> T {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { throw L3BorrowError.reentrancy }
        if Task.isCancelled { throw L3BorrowError.cancelled }
        return try await withCheckedThrowingContinuation { cont in
            nativeQueue.sync {
                // Post-wait cancellation check (v4): a task cancelled while
                // suspended on the queue is refused before admission.
                if Task.isCancelled { cont.resume(throwing: L3BorrowError.cancelled); return }
                guard session.epoch == self.currentSid, !self.terminated else {
                    cont.resume(throwing: L3BorrowError.foreignOrStaleSession); return
                }
                if let expected = expectedPresentationEpoch, expected != self.l3PresentationEpoch {
                    cont.resume(throwing: L3BorrowError.presentationEpochMismatch(expected: expected, actual: self.l3PresentationEpoch)); return
                }
                guard let rec = self.retainedFrames[handle] else {
                    cont.resume(throwing: L3BorrowError.unavailableHandle); return
                }
                // v4.2 (architect): the FRAME's own presentation epoch must
                // match the current presentation - a pre-seek/pre-fallback
                // handle is still retained, but borrowing it would relabel an
                // old-presentation frame as current. (Plain pixel copies via
                // framePlaneCopy stay presentation-agnostic; the borrow is a
                // presentation-authority API.)
                guard rec.presentationEpoch == self.l3PresentationEpoch else {
                    cont.resume(throwing: L3BorrowError.presentationEpochMismatch(expected: rec.presentationEpoch, actual: self.l3PresentationEpoch)); return
                }
                guard let planes = Self.checkedPlaneCoverage(frame: rec.frame, layouts: rec.planes),
                      self.validObservationLease(handle: handle, session: session.epoch, planes: planes) else {
                    cont.resume(throwing: L3BorrowError.invalidLease); return
                }
                let f = rec.frame.pointee
                guard f.pts != gorav_av_nopts_value() else {
                    cont.resume(throwing: L3BorrowError.missingFramePTS); return
                }
                guard f.pts == expectedPTS else {
                    cont.resume(throwing: L3BorrowError.ptsMismatch(expected: expectedPTS, actual: f.pts)); return
                }
                let fmtName = av_get_pix_fmt_name(AVPixelFormat(rawValue: f.format)).map { String(cString: $0) } ?? "unknown"
                let box = L3BorrowBox(frame: rec.frame, owner: self, sessionEpoch: session.epoch)
                let borrow = L3FrameBorrow(
                    sessionEpoch: session.epoch, presentationEpoch: self.l3PresentationEpoch,
                    streamIndex: Int(self.videoStreamIndex), handle: handle, pts: f.pts,
                    duration: f.duration, pixelFormat: fmtName,
                    width: Int(f.width), height: Int(f.height),
                    isKeyFrame: (f.flags & Int32(AV_FRAME_FLAG_KEY)) != 0,
                    hdr: Self.l3BuildHDRInfo(rec.frame), box: box, layouts: rec.planes)
                self.l3BorrowStats.acquired += 1
                defer {
                    // Mechanical invalidation INSIDE the turn, before any
                    // later releaseFrame/close can free the frame.
                    box.frame = nil
                }
                do {
                    cont.resume(returning: try body(borrow))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    #if DEBUG
    /// Adversarial-test hook (architect v4): forces the REAL hardware-failure
    /// branch on the next received frame; the actual l3ReopenSoftwareLocked
    /// reopen path runs, not a stub. Typed false when no hardware session is
    /// active (forced-software arm, off-Darwin CI) so tests SKIP honestly.
    @discardableResult
    public func l3TestInjectHardwareFailure(session: SessionID) async -> Bool {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            nativeQueue.sync {
                // v4.4 repair (safety): l3HW exists on EVERY session (open
                // creates it unconditionally), so existence is not a guard.
                // Injection requires a hardware session that was actually
                // ATTEMPTED and ATTACHED and has not already fallen back -
                // a forced-software arm (GORAV_L3_DISABLE_HW=1, off-Darwin,
                // policy-excluded codec) skips honestly with false.
                guard session.epoch == currentSid, !terminated, let hw = self.l3HW,
                      hw.receipt.attempted, hw.receipt.attachResult == 0,
                      !hw.receipt.fallbackArmed else {
                    cont.resume(returning: false); return
                }
                hw.forceNextReceiveFailure = true
                cont.resume(returning: true)
            }
        }
    }
    #endif

    private func markTerminal(_ event: DecodeEvent) -> DecodeEvent {
        switch event {
        case .endOfStream: trace(.terminalEOF)
        case .interrupted: trace(.terminalInterrupted)
        case .failed(let code, _):
            deregisterDecoderOnQueue()
            trace(.terminalFailed, code: Int32(exactly: code))
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
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { self.l3ReentrantRefusals += 1; return }
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
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { self.l3ReentrantRefusals += 1; return }
        if seekState.matches(session: session.epoch) { seekState.poisonSession() }
        _ = interruptSlot.request(session: session.epoch) // stale sessions fenced no-op
    }

    /// Protocol-intact definitive close (r6 R5-C): signature unchanged from
    /// LocalVideoDecoder; the report route is the separate closeAndReport API.
    public func close(session: SessionID) async {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { self.l3ReentrantRefusals += 1; return }
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
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { throw L3BorrowError.reentrancy }
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
                    // v4 (architect): delivery watermark and fallback preroll
                    // mark are PRE-SEEK facts - without this reset a backward
                    // seek decoded but never delivered until pts climbed past
                    // the old watermark. The presentation epoch bumps so a
                    // pre-seek borrow pin typed-refuses.
                    self.l3DiscardBeforePTS = nil
                    self.l3LastDeliveredPTS = nil
                    self.l3SeekPrerollBeforePTS = ts   // native101 (ported): arm preroll skip at the seek target
                    self.l3SeekPrerollSkipped = 0
                    self.l3SeekPrerollSeen = 0
                    self.l3PresentationEpoch &+= 1  // wrapping: no overflow trap
                    self.l3SeekCount += 1
                    cont.resume()
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    @discardableResult
    public func closeAndReport(session: SessionID) async -> CloseReport? {
        if DispatchQueue.getSpecific(key: l3QueueKey) != nil { self.l3ReentrantRefusals += 1; return nil }
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
        deregisterDecoderOnQueue()
        // r6 ordering: stop NEW interrupt requests, detach the provider callback,
        // close provider contexts (callback storage still ALIVE - the provider may
        // legally consult it during close), then free the slot storage last.
        interruptSlot.clear()
        if fmt != nil { fmt!.pointee.interrupt_callback = AVIOInterruptCB(callback: nil, opaque: nil) }
        if codecCtx != nil { avcodec_free_context(&codecCtx) }
        if fmt != nil { avformat_close_input(&fmt) }
        // L3: capture the run report before dropping the session objects.
        l3LastReport = L3RunReport(sessionEpoch: sid,
                                   hardware: l3HW?.receipt,
                                   pixelConvertedFrames: l3PixConv?.convertedFrames ?? 0,
                                   pixelConversionFailures: l3PixConv?.conversionFailures ?? 0,
                                   pixelConversionSources: l3PixConv?.conversionSources ?? [:],
                                   fallbackResumePTS: l3FallbackResumePTS,
                                   deliveredFrames: l3DeliveredCount,
                                   borrow: l3BorrowStats,
                                   reentrantRefusals: l3ReentrantRefusals,
                                   seekCount: l3SeekCount)
        l3HW = nil
        l3PixConv = nil
        l3DiscardBeforePTS = nil
        l3LastDeliveredPTS = nil
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
            self.deregisterDecoderOnQueue()
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
