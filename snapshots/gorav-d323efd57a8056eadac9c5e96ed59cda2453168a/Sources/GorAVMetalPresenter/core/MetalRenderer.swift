// L2 presenter (block 78d), revision 5 (architect r6 FULL review findings
// 1-6 + L8 r7 seam coordination):
// 1 COMMIT GATE: post-drawable + pre-commit sealed re-checks; a blocked
//   nextDrawable can never commit after seal/window close. seal() returns
//   a TYPED outcome with a keepalive-stall barrier (progress heartbeat at
//   admission/drawable/gate; a stalled bracket expires typed). Offscreen
//   renders take the SAME admission barrier; their completion wait is
//   BOUNDED (monotonic poll; on timeout the completion handler keeps the
//   lease/admission/bytes - no unsafe early release).
// 2 RETAINED FRAME: geometry changes are validated + typed; the retained
//   frame is REBOUND under a canonical renderer-issued identity at the new
//   revision (textures are drawable-independent); its stored overlay plan
//   is re-keyed and re-stamped, never silently dropped; renegotiate clears
//   the ring AND the retained identity (no presenter ghost identity).
// 3 PER-FRAME OVERLAY LEASES: a STORE keyed by FULL FrameIdentity (a bare
//   present of frame B never clobbers frame A's plan); registration is
//   PRE-COMMIT at the final gate (no post-commit race); validation is FULL
//   identity equality + epoch under lock; plan revisions echo in records,
//   receipts and readbacks; L8 can REVOKE plans (typed). L8 r7 at-commit
//   CURRENT-GENERATION check: a registered authority is queried at the
//   final gate; a superseded/withdrawn plan is a typed refusal there,
//   never only a post-hoc echo.
// 4 16F: payload length checked in BYTES (r6 passed the WORD count against
//   a byte expectation, refusing EVERY 16F upload); length first, then the
//   NaN/Inf scan.
// 5 BYTES: ghost retired bytes reclaimed when no legacy readers exist;
//   temporaries accounted in a GLOBAL in-use ledger (renderer-internal
//   bound 256 MiB) ON TOP of the per-call 64 MiB seam cap aligned with
//   L8 r7 OverlayBudget.maxBytes (67_108_864) - the seam never produces a
//   buffer this renderer must refuse on size.
// 6 TRANSITIONS: state/revision derived INSIDE the serialized transition
//   (geometry during the drain is carried, never overwritten); mutation
//   only via the TransitionContext surface; CAMetalLayer applies hop to
//   the MainActor with admission still sealed; epoch/revision/sequence
//   overflow seals typed, never aliases; close() splits ONE monotonic
//   budget between the barrier and the drain; all seconds validated
//   finite/positive (no NaN/negative UInt64 trap).
// AUTHORED NEW 2026-10-25, L2 lane.
#if canImport(AppKit) && canImport(Metal)
import AppKit
import CoreVideo
import GorAVPlaybackCore
import Metal
import QuartzCore
import CryptoKit

public enum MetalRendererError: Error, Equatable {
    case noDevice, noCommandQueue, noSampler
    case shaderCompile(String), pipelineFailed(String)
    case negotiationFailed(String)
    case transitionInProgress
    case transitionResidual(Int)
    case transitionExhausted
    case surfaceApplyFailed(String)
}

/// Typed admission outcome (L1 v2 seam): ok means VALIDATED + ALLOCATED +
/// texture-written only - never GPU completion, present or scanout.
public enum UploadOutcome: Equatable, Sendable {
    case ok(sha256: String)
    case rejectedInvalidSize
    case rejectedByteBudget
    case rejectedPayloadLength(expected: Int, actual: Int)
    case rejectedOverflow
    case rejectedAllocationFailed
    case rejectedSealed
    case rejectedStaleGeneration
    case rejectedSequenceRegress
    case rejectedStarved
    case rejectedUnsupportedVariant
    case rejectedNonFinitePayload
    /// P30/W2 (arch-197b): admitted GPU-resident upload (VT zero-copy via
    /// CVMetalTextureCache). NO sha: no CPU bytes exist to hash; the
    /// content receipt is the VTRECEIPT provenance counters, not a
    /// fabricated digest.
    case okZeroCopy
    var admitted: Bool { if case .ok = self { return true }; if case .okZeroCopy = self { return true }; return false }
}

public enum PresentOutcome: Equatable, Sendable {
    case submitted
    case noDrawable
    case sealed
    case staleGeneration
    case noFrame
    case starved
    case overlayRefused
}

/// Typed seal result (r6 finding 1): the r5 seal returned Void even with
/// admitted frames still uncommitted - a hidden broken fence.
public enum SealOutcome: Equatable, Sendable {
    case quiesced
    case residual(pending: Int)
}

/// Typed geometry-change result (r6 finding 2).
public enum GeometryChangeOutcome: Equatable, Sendable {
    case applied(revision: UInt64)
    case rejectedSealed
    case rejectedInvalidSize
    case rejectedExhausted
}

public struct FrameRecord: Equatable, Sendable {
    public let identity: FrameIdentity
    public var submitted = false
    public var completed = false
    /// The completion callback observed .completed. NOT evidence the
    /// drawable was presented or scanned out.
    public var callbackOK = false
    public var errored = false
    /// L8 authority receipt (r6 finding 3): WHICH subtitle plan revision
    /// was composited into this frame's submit; nil = bare.
    public var overlayPlanRevision: UInt64?
    public init(identity: FrameIdentity) { self.identity = identity }
}

public struct RendererCounters: Equatable, Sendable {
    public var uploadsOK = 0
    public var validationRejections = 0
    public var byteBudgetRejections = 0
    public var allocationFailures = 0
    public var presentSubmitted = 0
    public var presentCallbacksOK = 0
    public var presentErrors = 0
    public var noDrawableEvents = 0
    public var slotStarvationDrops = 0
    public var staleGenerationDrops = 0
    public var sequenceRegressDrops = 0
    public var sealedDrops = 0
    public var overlayStaleDrops = 0
    public var overlayInvalidDrops = 0
    public var overlayRevocations = 0
    public var readbacksOK = 0
    public var readbackErrors = 0
    public var renegotiations = 0
    public var tempBudgetRejections = 0
    public var sealResidualEvents = 0
    public var geometryChangesOK = 0
    public var geometryRejections = 0
    public init() {}
}

/// Readback receipt: digest bound to identity + revision + contract.
/// OFFSCREEN evidence only, never scanout proof.
public struct ReadbackReceipt: Sendable {
    public let sha256: String
    public let bytes: [UInt8]?
    public let halfWords: [UInt16]?
    public let identity: FrameIdentity
    public let surfaceRevision: UInt64
    public let pixelFormat: SurfaceContract.PixelFormat
    public let width: Int
    public let height: Int
    /// L8 authority receipt (r6 finding 3): the subtitle plan revision
    /// COMPOSITED into this readback; nil = bare frame.
    public let compositedOverlayPlanRevision: UInt64?
    public init(sha256: String, bytes: [UInt8]?, halfWords: [UInt16]?,
                identity: FrameIdentity, surfaceRevision: UInt64,
                pixelFormat: SurfaceContract.PixelFormat, width: Int, height: Int,
                compositedOverlayPlanRevision: UInt64?) {
        self.sha256 = sha256; self.bytes = bytes; self.halfWords = halfWords
        self.identity = identity; self.surfaceRevision = surfaceRevision
        self.pixelFormat = pixelFormat; self.width = width; self.height = height
        self.compositedOverlayPlanRevision = compositedOverlayPlanRevision
    }
}

/// L8 authority receipt (r6 finding 3): what the renderer composited for
/// one frame identity, queryable by the plan's producer.
public struct OverlayCompositeReceipt: Equatable, Sendable {
    public let identity: FrameIdentity
    public let surfaceRevision: UInt64
    public let epoch: UInt64
    public let compositedPlanRevision: UInt64?
    public init(identity: FrameIdentity, surfaceRevision: UInt64, epoch: UInt64,
                compositedPlanRevision: UInt64?) {
        self.identity = identity; self.surfaceRevision = surfaceRevision
        self.epoch = epoch; self.compositedPlanRevision = compositedPlanRevision
    }
}

public final class MetalRenderer: @unchecked Sendable {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let sampler: MTLSamplerState

    /// Immutable render state swapped atomically under the lock: pipeline,
    /// contract, revision AND the output transform travel together.
    private struct RenderState {
        let pipeline: MTLRenderPipelineState
        let contract: SurfaceContract
        let surfaceRevision: UInt64
        let outputTransform: OutputTransform
        let kernelID: UInt32
        let armID: UInt32
    }

    private struct Slot {
        var texture: MTLTexture?
        var width = 0
        var height = 0
        var readers = 0
        var nativeFrame = NativeFrameSlot()
        var nativeBytes = 0
        var epoch: UInt64 = 0
        var identity: FrameIdentity?
    }

    /// Immutable lease handed to every GPU reader.
    private struct FrameLease {
        let texture: MTLTexture
        let slotIndex: Int
        let epoch: UInt64
        let identity: FrameIdentity // the STORED identity, never caller text
        let frameW: Int
        let frameH: Int
        let renderState: RenderState
    }

    /// Per-frame overlay lease (r6 finding 3): stored against the frame's
    /// FULL identity in the overlay store. bytes are accounted in the
    /// GLOBAL temp ledger from validation until store-evict/revoke/clear.
    private struct OverlayLease {
        let identity: FrameIdentity
        let texture: MTLTexture
        let params: GorAVFrameParamsCPU
        let epoch: UInt64
        let planRevision: UInt64?
        let bytes: Int
        let ox: Int
        let oy: Int
        let ow: Int
        let oh: Int
    }

    private let lock = NSLock() // synchronous sections only; never across await
    private var renderState: RenderState
    private var slots: [Slot]
    private var epoch: UInt64 = 0
    private var legacyInFlight = 0
    private var sessionID = ""
    private var sessionGeneration: UInt64 = 0
    private var lastSequence: UInt64 = 0
    private var sealed = false
    /// seal() from OUTSIDE a transition (close intent); a transition may
    /// only reopen admission when this is clear (r6 finding 6: reopening
    /// over a user close resurrected the renderer).
    private var sealedExternally = false
    /// Typed permanent seal on epoch/revision overflow - NEVER an alias.
    private var exhaustedSeal = false
    private var transitionInFlight = false
    /// Admission barrier: seal() waits for this to reach 0, so no admitted
    /// frame can commit after the fence returns.
    private var admittedUncommitted = 0
    /// Keepalive heartbeat (uptime ns): refreshed at admission, drawable
    /// acquisition and the commit gate; seal() expires a STALLED bracket
    /// typed instead of holding the fence open forever.
    private var barrierHeartbeat: UInt64 = 0
    private var lastUploadedIdentity: FrameIdentity?
    private var records: [FrameRecord] = []
    private var counters = RendererCounters()
    private var allocatedSlotBytes = 0
    private var retiredSlotBytes = 0 // retired rings awaiting legacy drain
    /// Per-frame overlay store (r6 finding 3), keyed by FULL identity.
    private var overlayLeases: [FrameIdentity: OverlayLease] = [:]
    private var overlayReceipts: [FrameIdentity: OverlayCompositeReceipt] = [:]
    /// L8 r7 at-commit current-subtitle-generation authority. Registered
    /// by the subtitle producer; queried at the FINAL COMMIT GATE under
    /// the lock. Returns the CURRENT plan revision for the frame, or nil
    /// when every plan for it was withdrawn. A composited plan that is no
    /// longer current is a TYPED refusal at the gate - the echoed
    /// planRevision in receipts stays evidence, never the barrier.
    private var subtitlePlanAuthority: ((FrameIdentity) -> UInt64?)?
    private var lastDrainResidual = 0
    private static let recordCap = 512
    /// Per-call temporary byte cap, aligned with L8 r7
    /// OverlayBudget.maxBytes (67_108_864 = 64 MiB): the seam never
    /// produces a buffer this renderer refuses on size.
    private static let maxTemporaryBytesPerCall = 64 * 1024 * 1024
    /// Renderer-INTERNAL global in-use temporary ledger bound (r6 finding
    /// 5: per-call caps alone leave concurrent temporaries unbounded).
    /// Covers overlay textures + offscreen targets + readback staging
    /// held at any instant. NOT a negotiated seam value - L8 r7 aligned
    /// on the per-call cap only; stated, never claimed as agreed.
    private static let maxTemporaryBytesInUse = 256 * 1024 * 1024
    private var tempBytesInUse = 0
    /// G3 host pan/zoom. Read at every encode; its own lock because encode runs outside `lock`.
    /// Presentation-only: no texture, identity or surface revision changes, no shader compile.
    private let hostTransformLock = NSLock()
    private var hostTransform = HostTransform.identity
    private var photonEnabled=false
    private var photonActivationEpoch:UInt64?
    private var photonProducer=PhotonPresenterProducer()
    private var photonGraph:PhotonWorkingGraph?
    private var photonTelemetry:PhotonPresentedTelemetry?
    private var photonFailure:String?
    private let photonGraphLock=NSLock()

    /// P30/W2 (arch-197b): lazily-created VT zero-copy state - the texture
    /// cache and the YUV->RGB conversion pipeline. Nil until the first VT
    /// upload; the CPU path never pays for them.
    private var vtTextureCache: CVMetalTextureCache?
    private var vtPipeline: MTLRenderPipelineState?

    private static func fnv1a32(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }

    private static func shaderSource(_ ot: OutputTransform) -> String {
        let otBody: String
        switch ot {
        case .identity: otBody = "float4 goravOT(float4 c) { return c; }"
        case .customMSL(let src, _, _): otBody = src
        }
        return """
        #include <metal_stdlib>
        using namespace metal;
        struct VIn { packed_float2 pos; packed_float2 uv; };
        struct VOut { float4 pos [[position]]; float2 uv; };
        struct GorAVFrameParams { uint overlayEnabled; float frameW; float frameH;
                                  float ox; float oy; float ow; float oh;
                                  uint sequence; uint surfaceRevision; uint kernelID; uint armID;
                                  float referenceWhiteNits; float sourceMinNits;
                                  float sourceMaxNits; float pad; };
        struct PhotonComposite {float4 videoRect;uint4 enabled;};
        \(otBody)
        vertex VOut goravVMain(const device VIn* vs [[buffer(0)]], uint i [[vertex_id]]) {
            VOut o; o.pos = float4(vs[i].pos, 0.0, 1.0); o.uv = vs[i].uv; return o;
        }
        // L8 overlay composites in the working space BEFORE the output
        // transform (L5 production seam): premultiplied-over, identity-bound.
        fragment float4 goravFMain(VOut in [[stage_in]],
                                   texture2d<float> base [[texture(0)]],
                                   texture2d<float> ovl [[texture(1)]],
                                   sampler s [[sampler(0)]],
                                   constant GorAVFrameParams& p [[buffer(0)]],
                                   constant PhotonComposite& photon [[buffer(3)]]) {
            float4 c = base.sample(s, in.uv);
            if (p.overlayEnabled == 1u) {
                float2 sourceUV=in.uv;
                if (photon.enabled.x == 1u) sourceUV=(in.uv-photon.videoRect.xy)/photon.videoRect.zw;
                float2 fp = sourceUV*float2(p.frameW,p.frameH);
                if (fp.x >= p.ox && fp.x < p.ox + p.ow && fp.y >= p.oy && fp.y < p.oy + p.oh) {
                    float2 ouv = float2((fp.x - p.ox) / p.ow, (fp.y - p.oy) / p.oh);
                    float4 o = ovl.sample(s, ouv);
                    c = o + c * (1.0 - o.a);
                }
            }
            return goravOT(c);
        }
        """
    }

    private static func kernelBinding(_ ot: OutputTransform) -> (UInt32, UInt32) {
        switch ot {
        case .identity: return (0, 0)
        case .customMSL(_, let kv, let arm): return (fnv1a32(kv), fnv1a32(arm))
        }
    }

    private static func makeState(device: MTLDevice, contract: SurfaceContract,
                                  revision: UInt64, ot: OutputTransform) throws -> RenderState {
        let p = try buildPipeline(device: device, contract: contract, ot: ot)
        let (k, a) = kernelBinding(ot)
        return RenderState(pipeline: p, contract: contract, surfaceRevision: revision,
                           outputTransform: ot, kernelID: k, armID: a)
    }

    public init(contract: SurfaceContract = .sdrDefault,
                outputTransform: OutputTransform = .identity) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else { throw MetalRendererError.noDevice }
        device = dev
        guard let q = dev.makeCommandQueue() else { throw MetalRendererError.noCommandQueue }
        queue = q
        let sd = MTLSamplerDescriptor()
        sd.magFilter = .nearest
        sd.minFilter = .nearest
        sd.mipFilter = .notMipmapped
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let s = dev.makeSamplerState(descriptor: sd) else { throw MetalRendererError.noSampler }
        sampler = s
        let c = try contract.validated()
        renderState = try MetalRenderer.makeState(device: dev, contract: c, revision: 0, ot: outputTransform)
        slots = (0..<c.maxInFlight).map { _ in Slot() }
    }

    private static func buildPipeline(device: MTLDevice, contract: SurfaceContract,
                                      ot: OutputTransform) throws -> MTLRenderPipelineState {
        let lib: MTLLibrary
        do {
            lib = try device.makeLibrary(source: shaderSource(ot), options: nil)
        } catch { throw MetalRendererError.shaderCompile("\(error)") }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "goravVMain")
        desc.fragmentFunction = lib.makeFunction(name: "goravFMain")
        desc.colorAttachments[0].pixelFormat = SurfaceNegotiator.metalPixelFormat(contract.pixelFormat)
        do { return try device.makeRenderPipelineState(descriptor: desc) }
        catch { throw MetalRendererError.pipelineFailed("\(error)") }
    }

    public var currentSurfaceRevision: UInt64 { lock.lock(); defer { lock.unlock() }; return renderState.surfaceRevision }
    public var renegotiateResidual: Int { lock.lock(); defer { lock.unlock() }; return lastDrainResidual }

    /// L8 r7 seam: register the at-commit current-subtitle-generation
    /// authority (nil clears). Called under the renderer lock at the final
    /// commit gate; it must be a fast CPU read (L8 fencer state).
    public func setSubtitlePlanAuthority(_ authority: ((FrameIdentity) -> UInt64?)?) {
        lock.lock(); subtitlePlanAuthority = authority; lock.unlock()
    }

    /// First session on a FRESH renderer (r6 finding 6: the r5 public
    /// beginSession reset sequence state mid-life with NO drain, reopening
    /// over live GPU work). Mid-life session changes go through
    /// restartSession (drain first). Returns false typed when the renderer
    /// is not quiescent-fresh; state is left untouched.
    @discardableResult
    public func beginSession(sessionID: String, generation: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let inFlight = slots.reduce(0) { $0 + $1.readers } + legacyInFlight + admittedUncommitted
        guard inFlight == 0, records.isEmpty, lastUploadedIdentity == nil else {
            counters.sealedDrops += 1
            return false
        }
        self.sessionID = sessionID
        self.sessionGeneration = generation
        self.lastSequence = 0
        sealed = false
        sealedExternally = false
        return true
    }

    /// Transition mutation surface (r6 finding 6 closure discipline): ALL
    /// render-state mutation during a transition goes through this type,
    /// which exists only inside transition() - running under the lock,
    /// AFTER the drain, BEFORE admission reopens. The r5 closure received
    /// the whole renderer; nothing bounded what it could mutate.
    private struct TransitionContext {
        let r: MetalRenderer
        var pendingLayerApply: (layer: CAMetalLayer, contract: SurfaceContract)? = nil
        /// Epoch advance, checked: overflow seals EXHAUSTED (typed,
        /// permanent) rather than aliasing an old epoch (r6 finding 6).
        func bumpEpoch() {
            let (e, ov) = r.epoch.addingReportingOverflow(1)
            if ov { r.exhaustedSeal = true } else { r.epoch = e }
        }
        /// Install a NEW immutable render state derived from the LATEST
        /// locked state (r6 finding 6: the r5 code computed the revision
        /// BEFORE serialization, so geometry changes during the drain were
        /// silently overwritten). Drawable geometry carries forward when
        /// the new contract pins none. Pipeline builds under the lock:
        /// slow, but transitions are serialized and rare - correctness
        /// first.
        mutating func installRenderState(contract c0: SurfaceContract, ot: OutputTransform,
                                         layer: CAMetalLayer?) throws {
            let latest = r.renderState
            var c = c0
            if (c.drawableWidth == 0 || c.drawableHeight == 0),
               latest.contract.drawableWidth > 0, latest.contract.drawableHeight > 0 {
                c = c.withDrawableSize(width: latest.contract.drawableWidth,
                                       height: latest.contract.drawableHeight)
            }
            let (rev, ov) = latest.surfaceRevision.addingReportingOverflow(1)
            if ov { r.exhaustedSeal = true; throw MetalRendererError.transitionExhausted }
            let st = try MetalRenderer.makeState(device: r.device, contract: c, revision: rev, ot: ot)
            r.renderState = st
            r.resetRingLocked(contract: c)
            r.lastUploadedIdentity = nil
            r.clearOverlayStateLocked()
            r.counters.renegotiations += 1
            if let layer { pendingLayerApply = (layer, c) }
        }
        /// Mid-life session change: same contract, cleared ring + records,
        /// adopted session identity, deliberate reopen (clears the
        /// external-seal fence; the presenter's own closed flag stays the
        /// outer fence for user-close).
        func adoptSession(sessionID: String, generation: UInt64) {
            r.resetRingLocked(contract: r.renderState.contract)
            r.records = []
            r.lastUploadedIdentity = nil
            r.clearOverlayStateLocked()
            r.sessionID = sessionID
            r.sessionGeneration = generation
            r.lastSequence = 0
            r.sealedExternally = false
        }
    }

    private func resetRingLocked(contract c: SurfaceContract) {
        slots = (0..<c.maxInFlight).map { _ in var s = Slot(); s.epoch = epoch; return s }
    }

    private func clearOverlayStateLocked() {
        let keys = [FrameIdentity](overlayLeases.keys)
        for k in keys { if let v = overlayLeases[k] { tempBytesInUse -= v.bytes } }
        overlayLeases.removeAll()
        overlayReceipts.removeAll()
    }

    /// Atomic transition core: serialize transitions, seal admission, drain
    /// the old ring (bounded, monotonic clock), THEN run the mutation
    /// surface under the lock, THEN apply the layer on the MainActor with
    /// admission STILL sealed, THEN reopen. On residual/exhaustion the
    /// state stays SEALED and a typed error is thrown - NO reopen with
    /// live GPU work.
    private func transition(_ body: (inout TransitionContext) throws -> Void) async throws {
        lock.lock()
        if transitionInFlight { lock.unlock(); throw MetalRendererError.transitionInProgress }
        transitionInFlight = true
        sealed = true
        lock.unlock()
        let residual = await drainInFlight(maxWaitSeconds: 2.0)
        lock.lock()
        lastDrainResidual = residual
        if residual != 0 {
            transitionInFlight = false // stays sealed; close() or a later transition may retry
            lock.unlock()
            throw MetalRendererError.transitionResidual(residual)
        }
        for i in slots.indices { legacyInFlight += slots[i].readers }
        retiredSlotBytes += allocatedSlotBytes
        allocatedSlotBytes = 0
        // r6 finding 5: with NO legacy readers there is nothing to drain -
        // reclaim the retired bytes NOW (the r5 code only reclaimed on
        // legacy release, permanently leaking the budget: ghost bytes).
        if legacyInFlight == 0 { retiredSlotBytes = 0 }
        var ctx = TransitionContext(r: self)
        do {
            try body(&ctx)
        } catch {
            transitionInFlight = false // stays sealed
            lock.unlock()
            throw error
        }
        if exhaustedSeal {
            transitionInFlight = false
            lock.unlock()
            throw MetalRendererError.transitionExhausted
        }
        let pending = ctx.pendingLayerApply
        lock.unlock()
        // CAMetalLayer property writes are MainActor work (r6 finding 6);
        // admission stays sealed across the hop, so no frame can commit
        // against the new state before the layer matches it.
        if let p = pending {
            await MainActor.run { SurfaceNegotiator.applyValidated(p.contract, to: p.layer, device: device) }
        }
        lock.lock()
        // Reopen ONLY when nothing sealed us externally (user close) while
        /// the drain/apply ran, and no exhaustion fired.
        if !sealedExternally && !exhaustedSeal { sealed = false }
        transitionInFlight = false
        lock.unlock()
    }

    /// L5 extension seam: renegotiate surface + pipeline on the SAME
    /// renderer (no fork). Drain BEFORE install; the live layer is
    /// re-negotiated on the MainActor before admission reopens.
    public func renegotiate(_ newContract: SurfaceContract, ot: OutputTransform,
                            layer: CAMetalLayer?) async throws {
        let c = try newContract.validated()
        try await transition { ctx in
            ctx.bumpEpoch()
            try ctx.installRenderState(contract: c, ot: ot, layer: layer)
        }
    }

    /// Mid-life session change: quiesce, THEN clear frames/records and
    /// reopen with the new session (typed failure on residual, no reopen).
    @discardableResult
    public func restartSession(sessionID: String, generation: UInt64) async throws -> Int {
        do {
            try await transition { ctx in
                ctx.bumpEpoch()
                ctx.adoptSession(sessionID: sessionID, generation: generation)
            }
            return 0
        } catch MetalRendererError.transitionResidual(let r) {
            return r
        }
    }

    /// Synchronous close-intent fence + admission barrier. TYPED result
    /// (r6 finding 1): the r5 seal returned Void even with admitted frames
    /// still uncommitted. Keepalive-stall wait: the fence holds while
    /// admitted frames show PROGRESS (heartbeat refreshed at admission,
    /// drawable acquisition, commit gate); a bracket stalled longer than
    /// the barrier budget (blocked nextDrawable) expires the wait typed.
    /// An absolute cap of 2x the budget bounds even a live-heartbeat wait.
    @discardableResult
    public func seal(maxBarrierSeconds: Double = 2.0) -> SealOutcome {
        let barrier = (maxBarrierSeconds.isFinite && maxBarrierSeconds > 0) ? min(maxBarrierSeconds, 60) : 2.0
        let stallNs = UInt64(barrier * 1e9)
        lock.lock()
        sealed = true
        sealedExternally = true
        let start = DispatchTime.now().uptimeNanoseconds
        while admittedUncommitted > 0 {
            let now = DispatchTime.now().uptimeNanoseconds
            let stalledFor = now &- barrierHeartbeat
            let waited = now &- start
            if stalledFor >= stallNs || waited >= 2 &* stallNs { break }
            lock.unlock()
            usleep(1000)
            lock.lock()
        }
        let pending = admittedUncommitted
        if pending > 0 { counters.sealResidualEvents += 1 }
        lock.unlock()
        return pending == 0 ? .quiesced : .residual(pending: pending)
    }

    private func admissionBlockedLocked() -> Bool { sealed || transitionInFlight || exhaustedSeal }

    /// Full-identity check, LOCK-HELD ONLY (r6 finding 6: the r5
    /// renderAndPresent called this unlocked - a TOCTOU against session
    /// and revision state).
    private func identityOKLocked(_ identity: FrameIdentity) -> Bool {
        identity.sessionID == sessionID &&
        identity.sessionGeneration == sessionGeneration &&
        identity.surfaceRevision == renderState.surfaceRevision
    }

    public func upload(rgba bytes: [UInt8], width: Int, height: Int,
                       identity: FrameIdentity) -> UploadOutcome {
        uploadBytes(byteCount: bytes.count, width: width, height: height,
                    bytesPerPixel: 4, requiredFormat: .sdrRGBA8, identity: identity) { tex in
            bytes.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                                mipmapLevel: 0, withBytes: base, bytesPerRow: width * 4)
                }
            }
            return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// 16F upload (EDR/linear surface only). r6 finding 4: the r5 code
    /// passed the WORD count to a BYTE expectation (count == need could
    /// never hold: 1 pixel = 4 words = 8 bytes), so EVERY 16F upload was
    /// refused. Length is validated FIRST (in bytes), THEN the NaN/Inf
    /// scan runs (no full-buffer scan on a malformed call).
    public func upload16F(halfWords: [UInt16], width: Int, height: Int,
                          identity: FrameIdentity) -> UploadOutcome {
        let (px, o1) = width.multipliedReportingOverflow(by: height)
        let (words, o2) = px.multipliedReportingOverflow(by: 4)
        guard !o1, !o2 else {
            countersAdd { $0.validationRejections += 1 }; return .rejectedOverflow
        }
        guard halfWords.count == words else {
            countersAdd { $0.validationRejections += 1 }
            return .rejectedPayloadLength(expected: words &* 2, actual: halfWords.count &* 2)
        }
        // Half-float NaN/Inf: exponent bits all set.
        for w in halfWords where (w & 0x7C00) == 0x7C00 {
            countersAdd { $0.validationRejections += 1 }
            return .rejectedNonFinitePayload
        }
        let (byteCount, o3) = halfWords.count.multipliedReportingOverflow(by: 2)
        guard !o3 else {
            countersAdd { $0.validationRejections += 1 }; return .rejectedOverflow
        }
        return uploadBytes(byteCount: byteCount, width: width, height: height,
                           bytesPerPixel: 8, requiredFormat: .edrRGBA16F, identity: identity) { tex in
            halfWords.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                                mipmapLevel: 0, withBytes: base, bytesPerRow: width * 8)
                }
            }
            return halfWords.withUnsafeBytes { raw in
                SHA256.hash(data: Data(raw)).map { String(format: "%02x", $0) }.joined()
            }
        }
    }

    /// P30/W2 (arch-197a item 2, arch-197b): ZERO-COPY VT upload. The
    /// CVPixelBuffer is textured via CVMetalTextureCache (no CPU read of
    /// pixel data) and converted YUV->RGB by a shader INTO the slot
    /// texture - BEFORE the colour stage: from there the frame is
    /// indistinguishable from a CPU RGBA upload (same output transform,
    /// overlay, geometry, present machinery). The conversion pass commits
    /// on the renderer's own queue, so in-order execution lands it before
    /// any later renderAndPresent sampling the slot. A BGRA buffer (VT
    /// already converted) blits instead - still zero CPU. .okZeroCopy
    /// carries no sha (see UploadOutcome).
    public func upload(vtFrame payload: VTFramePayload, identity: FrameIdentity) -> UploadOutcome {
        lock.lock()
        if admissionBlockedLocked() { lock.unlock(); countersAdd { $0.sealedDrops += 1 }; return .rejectedSealed }
        guard identityOKLocked(identity) else {
            lock.unlock(); countersAdd { $0.staleGenerationDrops += 1 }; return .rejectedStaleGeneration
        }
        guard identity.sequence > lastSequence else {
            lock.unlock(); countersAdd { $0.sequenceRegressDrops += 1 }; return .rejectedSequenceRegress
        }
        guard let provenance = payload.provenance, let expected = identity.producerSource,
              provenance.admits(source: expected, ptsSeconds: identity.ptsSeconds,
                                durationSeconds: provenance.durationSeconds) else {
            lock.unlock(); countersAdd { $0.staleGenerationDrops += 1 }; return .rejectedStaleGeneration
        }
        guard VTZeroCopyAdmission.isTexturable(payload.cvPixelFormat),
              payload.cvPixelFormat == CVPixelBufferGetPixelFormatType(payload.pixelBuffer),
              payload.width == CVPixelBufferGetWidth(payload.pixelBuffer),
              payload.height == CVPixelBufferGetHeight(payload.pixelBuffer),
              CVPixelBufferGetPlaneCount(payload.pixelBuffer) == 2 else {
            lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedUnsupportedVariant
        }
        let width = payload.width, height = payload.height
        guard width > 0, height > 0,
              width <= SurfaceContract.maxTextureSide, height <= SurfaceContract.maxTextureSide else {
            lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedInvalidSize
        }
        let (px, ov1) = width.multipliedReportingOverflow(by: height)
        let (need, ov2) = px.multipliedReportingOverflow(by: 4)
        guard !ov1, !ov2 else { lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedOverflow }
        guard need <= SurfaceContract.maxFrameBytes else {
            lock.unlock(); countersAdd { $0.byteBudgetRejections += 1 }; return .rejectedByteBudget
        }
        // The conversion pass writes RGBA8; an EDR/16F contract is a typed
        // refusal (same shape as a 16F upload on an SDR surface).
        guard renderState.contract.pixelFormat == .sdrRGBA8 else {
            lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedUnsupportedVariant
        }
        guard let cache = vtCacheLocked() else {
            lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
        }
        CVMetalTextureCacheFlush(cache, 0)
        let pb = payload.pixelBuffer
        // The CVMetalTexture objects own the MTLTextures; they must outlive
        // the GPU pass. The completion-handler capture retains them until
        // the conversion/copy completes.
        var keepAlive: [CVMetalTexture] = []
        func planeTexture(_ plane: Int, _ format: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture? {
            var out: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, format, w, h, plane, &out) == kCVReturnSuccess,
                  let cvt = out, let tex = CVMetalTextureGetTexture(cvt) else { return nil }
            keepAlive.append(cvt)
            return tex
        }
        enum VTSource { case biplanar(MTLTexture, MTLTexture, VTYUVToRGBCoefficients); case bgra(MTLTexture) }
        let source: VTSource
        switch payload.cvPixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard let y = planeTexture(0, .r8Unorm, width, height),
                  let uv = planeTexture(1, .rg8Unorm, (width + 1) / 2, (height + 1) / 2) else {
                lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
            }
            source = .biplanar(y, uv, payload.coefficients)
        default:
            lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedUnsupportedVariant
        }
        var freeIdx = -1
        for i in 0..<slots.count where slots[i].readers == 0 { freeIdx = i; break }
        guard freeIdx >= 0 else { lock.unlock(); countersAdd { $0.slotStarvationDrops += 1 }; return .rejectedStarved }
        var importedBytes = 0
        for plane in 0..<2 {
            let (size, overflow) = CVPixelBufferGetBytesPerRowOfPlane(pb, plane)
                .multipliedReportingOverflow(by: CVPixelBufferGetHeightOfPlane(pb, plane))
            let (total, sumOverflow) = importedBytes.addingReportingOverflow(size)
            guard !overflow, !sumOverflow, size >= 0, total <= SurfaceContract.maxFrameBytes else {
                lock.unlock(); countersAdd { $0.byteBudgetRejections += 1 }; return .rejectedByteBudget
            }
            importedBytes = total
        }
        let retainedNativeBytes = slots.reduce(0) { $0 + $1.nativeBytes }
        guard importedBytes <= SurfaceContract.maxFrameBytes,
              allocatedSlotBytes + retiredSlotBytes + retainedNativeBytes - slots[freeIdx].nativeBytes + importedBytes <= SurfaceContract.maxAggregateSlotBytes else {
            lock.unlock(); countersAdd { $0.byteBudgetRejections += 1 }; return .rejectedByteBudget
        }
        let oldBytes = slots[freeIdx].width * slots[freeIdx].height * 4
        // A slot reused from the CPU path lacks render-target usage; the
        // budget-checked replacement path is the same as a size change.
        if slots[freeIdx].width != width || slots[freeIdx].height != height
            || slots[freeIdx].texture == nil || !slots[freeIdx].texture!.usage.contains(.renderTarget) {
            if allocatedSlotBytes - oldBytes + need + retiredSlotBytes + retainedNativeBytes - slots[freeIdx].nativeBytes + importedBytes > SurfaceContract.maxAggregateSlotBytes {
                lock.unlock(); countersAdd { $0.byteBudgetRejections += 1 }; return .rejectedByteBudget
            }
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: SurfaceNegotiator.metalPixelFormat(.sdrRGBA8),
                width: width, height: height, mipmapped: false)
            // .shaderRead for the present pass, .renderTarget for the
            // conversion pass; .shared so a later CPU upload can still
            // replace() into the reused slot.
            td.usage = [.shaderRead, .renderTarget]
            td.storageMode = .shared
            guard let t = device.makeTexture(descriptor: td) else {
                lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
            }
            allocatedSlotBytes = allocatedSlotBytes - oldBytes + need
            slots[freeIdx].texture = t
            slots[freeIdx].width = width
            slots[freeIdx].height = height
        }
        let slotTex = slots[freeIdx].texture!
        guard let cb = queue.makeCommandBuffer() else {
            lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
        }
        switch source {
        case .biplanar(let yTex, let uvTex, var coeffs):
            guard let pipe = vtPipelineLocked() else {
                lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
            }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = slotTex
            rpd.colorAttachments[0].loadAction = .dontCare
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else {
                lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
            }
            enc.setRenderPipelineState(pipe)
            enc.setFragmentTexture(yTex, index: 0)
            enc.setFragmentTexture(uvTex, index: 1)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setFragmentBytes(&coeffs, length: MemoryLayout<VTYUVToRGBCoefficients>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        case .bgra(let tex):
            guard let blit = cb.makeBlitCommandEncoder() else {
                lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
            }
            blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOriginMake(0, 0, 0), sourceSize: MTLSizeMake(width, height, 1),
                      to: slotTex, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOriginMake(0, 0, 0))
            blit.endEncoding()
        }
        let slotIndex = freeIdx, conversionEpoch = epoch
        // The slot and GPU callback independently own the native image.
        // Conversion is itself a slot reader: CPU/native reuse must wait.
        slots[freeIdx].nativeFrame.replace(with: payload.ownership)
        slots[freeIdx].nativeBytes = importedBytes
        slots[freeIdx].readers += 1
        let nativeOwnership = payload.ownership, textures = keepAlive
        cb.addCompletedHandler { [self, nativeOwnership, textures] command in
            withExtendedLifetime((nativeOwnership, textures)) {
            if command.status != .completed {
                lock.lock()
                if slots.indices.contains(slotIndex), slots[slotIndex].epoch == conversionEpoch,
                   slots[slotIndex].identity == identity { slots[slotIndex].identity = nil }
                counters.presentErrors += 1
                lock.unlock()
            }
            releaseLease(slotIndex: slotIndex, epoch: conversionEpoch)
            }
        }
        cb.commit()
        slots[freeIdx].identity = identity // FULL identity stored
        slots[freeIdx].epoch = epoch
        lastSequence = identity.sequence // advance only on accepted upload
        lastUploadedIdentity = identity
        // Same overlay-lease eviction as the CPU path (r6 findings 3/5).
        var live = Set<FrameIdentity>()
        for s in slots { if let id = s.identity { live.insert(id) } }
        let deadKeys = overlayLeases.keys.filter { !live.contains($0) }
        for k in deadKeys {
            if let v = overlayLeases.removeValue(forKey: k) { tempBytesInUse -= v.bytes }
            overlayReceipts.removeValue(forKey: k)
        }
        lock.unlock()
        countersAdd { $0.uploadsOK += 1 }
        return .okZeroCopy
    }

    private func vtCacheLocked() -> CVMetalTextureCache? {
        if let c = vtTextureCache { return c }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let c = cache else { return nil }
        vtTextureCache = c
        return c
    }

    private func vtPipelineLocked() -> MTLRenderPipelineState? {
        if let p = vtPipeline { return p }
        guard let lib = try? device.makeLibrary(source: MetalRenderer.vtShaderSource, options: nil),
              let vf = lib.makeFunction(name: "goravVTVMain"),
              let ff = lib.makeFunction(name: "goravVTFMain") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf
        desc.fragmentFunction = ff
        desc.colorAttachments[0].pixelFormat = SurfaceNegotiator.metalPixelFormat(.sdrRGBA8)
        guard let p = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        vtPipeline = p
        return p
    }

    /// P30/W2 shader: field order of VTCoeffs matches
    /// VTYUVToRGBCoefficients (8 x float, 32 bytes, setFragmentBytes).
    private static let vtShaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VTCoeffs { float yGain; float yCenter; float cCenter;
                      float crvGain; float cguGain; float cgvGain; float cbuGain;
                      float p010Scale; };
    struct VTVOut { float4 pos [[position]]; float2 uv; };
    vertex VTVOut goravVTVMain(uint i [[vertex_id]]) {
        float2 p = float2(i == 2 ? 3.0 : -1.0, i == 1 ? 3.0 : -1.0);
        VTVOut o; o.pos = float4(p, 0.0, 1.0);
        // Render-target row 0 is the TOP row (Metal window coords); sample
        // the source top-down so the slot matches the CPU upload's order.
        o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
        return o;
    }
    fragment float4 goravVTFMain(VTVOut in [[stage_in]],
                                 texture2d<float> yTex [[texture(0)]],
                                 texture2d<float> uvTex [[texture(1)]],
                                 sampler s [[sampler(0)]],
                                 constant VTCoeffs& c [[buffer(0)]]) {
        float y = yTex.sample(s, in.uv).r * c.p010Scale;
        float2 uv = uvTex.sample(s, in.uv).rg * c.p010Scale;
        float Y = c.yGain * (y - c.yCenter);
        float U = uv.x - c.cCenter, V = uv.y - c.cCenter;
        float r = Y + c.crvGain * V;
        float g = Y - c.cguGain * U - c.cgvGain * V;
        float b = Y + c.cbuGain * U;
        return float4(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0), 1.0);
    }
    """

    private func uploadBytes(byteCount: Int, width: Int, height: Int, bytesPerPixel: Int,
                             requiredFormat: SurfaceContract.PixelFormat,
                             identity: FrameIdentity,
                             writer: (MTLTexture) -> String) -> UploadOutcome {
        lock.lock()
        if admissionBlockedLocked() { lock.unlock(); countersAdd { $0.sealedDrops += 1 }; return .rejectedSealed }
        guard identityOKLocked(identity) else {
            lock.unlock(); countersAdd { $0.staleGenerationDrops += 1 }; return .rejectedStaleGeneration
        }
        // Sequence must be strictly monotonic per session.
        guard identity.sequence > lastSequence else {
            lock.unlock(); countersAdd { $0.sequenceRegressDrops += 1 }; return .rejectedSequenceRegress
        }
        guard width > 0, height > 0,
              width <= SurfaceContract.maxTextureSide, height <= SurfaceContract.maxTextureSide else {
            lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedInvalidSize
        }
        let (px, ov1) = width.multipliedReportingOverflow(by: height)
        let (need, ov2) = px.multipliedReportingOverflow(by: bytesPerPixel)
        guard !ov1, !ov2 else { lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedOverflow }
        guard need <= SurfaceContract.maxFrameBytes else {
            lock.unlock(); countersAdd { $0.byteBudgetRejections += 1 }; return .rejectedByteBudget
        }
        guard byteCount == need else {
            lock.unlock(); countersAdd { $0.validationRejections += 1 }
            return .rejectedPayloadLength(expected: need, actual: byteCount)
        }
        guard renderState.contract.pixelFormat == requiredFormat else {
            lock.unlock(); countersAdd { $0.validationRejections += 1 }; return .rejectedUnsupportedVariant
        }
        var freeIdx = -1
        for i in 0..<slots.count where slots[i].readers == 0 { freeIdx = i; break }
        guard freeIdx >= 0 else { lock.unlock(); countersAdd { $0.slotStarvationDrops += 1 }; return .rejectedStarved }
        let oldBytes = slots[freeIdx].width * slots[freeIdx].height * bytesPerPixel
        if slots[freeIdx].width != width || slots[freeIdx].height != height || slots[freeIdx].texture == nil {
            // Replacement SUBTRACTS retired bytes; the budget accounts
            // live + retired-but-undrained textures.
            if allocatedSlotBytes - oldBytes + need + retiredSlotBytes + slots.reduce(0, { $0 + $1.nativeBytes }) - slots[freeIdx].nativeBytes > SurfaceContract.maxAggregateSlotBytes {
                lock.unlock(); countersAdd { $0.byteBudgetRejections += 1 }; return .rejectedByteBudget
            }
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: SurfaceNegotiator.metalPixelFormat(requiredFormat),
                width: width, height: height, mipmapped: false)
            td.usage = [.shaderRead]
            td.storageMode = .shared
            guard let t = device.makeTexture(descriptor: td) else {
                lock.unlock(); countersAdd { $0.allocationFailures += 1 }; return .rejectedAllocationFailed
            }
            allocatedSlotBytes = allocatedSlotBytes - oldBytes + need
            slots[freeIdx].texture = t
            slots[freeIdx].width = width
            slots[freeIdx].height = height
        }
        slots[freeIdx].nativeFrame.recycle()
        slots[freeIdx].nativeBytes = 0
        let sha = writer(slots[freeIdx].texture!)
        slots[freeIdx].identity = identity // FULL identity stored
        slots[freeIdx].epoch = epoch
        lastSequence = identity.sequence // advance only on accepted upload
        lastUploadedIdentity = identity
        // Evict overlay leases whose frame left the ring (r6 findings
        // 3/5): they can never composite again; their temp bytes return
        // to the global ledger.
        var live = Set<FrameIdentity>()
        for s in slots { if let id = s.identity { live.insert(id) } }
        let deadKeys = overlayLeases.keys.filter { !live.contains($0) }
        for k in deadKeys {
            if let v = overlayLeases.removeValue(forKey: k) { tempBytesInUse -= v.bytes }
            overlayReceipts.removeValue(forKey: k)
        }
        lock.unlock()
        countersAdd { $0.uploadsOK += 1 }
        return .ok(sha256: sha)
    }

    private func countersAdd(_ f: (inout RendererCounters) -> Void) {
        lock.lock(); f(&counters); lock.unlock()
    }
    /// Lock-held append with the record cap.
    private func recordsAppendLocked(_ r: FrameRecord) {
        records.append(r)
        if records.count > MetalRenderer.recordCap { records.removeFirst(records.count - MetalRenderer.recordCap) }
    }
    /// Attribution by FULL identity equality.
    private func recordUpdate(_ identity: FrameIdentity, _ f: (inout FrameRecord) -> Void) {
        lock.lock()
        if let i = records.lastIndex(where: { $0.identity == identity }) { f(&records[i]) }
        lock.unlock()
    }

    /// Typed lease acquisition (r6 finding 6): ONE locked section decides
    /// sealed/stale/no-match - no unlocked identity pre-check.
    private enum AcquireResult {
        case acquired(FrameLease)
        case sealed
        case staleIdentity
        case noMatch
    }
    private func acquireLease(identity: FrameIdentity) -> AcquireResult {
        lock.lock()
        defer { lock.unlock() }
        if admissionBlockedLocked() { return .sealed }
        if !identityOKLocked(identity) { return .staleIdentity }
        guard let idx = slots.firstIndex(where: { $0.identity == identity && $0.epoch == epoch }),
              let tex = slots[idx].texture,
              let stored = slots[idx].identity else { return .noMatch }
        slots[idx].readers += 1
        return .acquired(FrameLease(texture: tex, slotIndex: idx, epoch: slots[idx].epoch,
                                    identity: stored, frameW: slots[idx].width, frameH: slots[idx].height,
                                    renderState: renderState))
    }
    private func acquireLastLease() -> AcquireResult {
        lock.lock()
        defer { lock.unlock() }
        if admissionBlockedLocked() { return .sealed }
        guard let last = lastUploadedIdentity,
              let idx = slots.firstIndex(where: { $0.identity == last && $0.epoch == epoch }),
              let tex = slots[idx].texture,
              let stored = slots[idx].identity else { return .noMatch }
        slots[idx].readers += 1
        return .acquired(FrameLease(texture: tex, slotIndex: idx, epoch: slots[idx].epoch,
                                    identity: stored, frameW: slots[idx].width, frameH: slots[idx].height,
                                    renderState: renderState))
    }
    /// Epoch-checked release; when the legacy counter drains, retired ring
    /// bytes are reclaimed.
    private func releaseLease(slotIndex: Int, epoch leaseEpoch: UInt64) {
        lock.lock()
        if slots.indices.contains(slotIndex), slots[slotIndex].epoch == leaseEpoch, slots[slotIndex].readers > 0 {
            slots[slotIndex].readers -= 1
        } else if leaseEpoch != epoch, legacyInFlight > 0 {
            legacyInFlight -= 1
            if legacyInFlight == 0 { retiredSlotBytes = 0 }
        }
        lock.unlock()
    }

    private func releaseOverlayTemp(_ ol: OverlayLease) {
        lock.lock(); tempBytesInUse -= ol.bytes; lock.unlock()
    }

    /// L8 seal capability (r6 finding 3): withdraw ONE plan - re-renders
    /// stop compositing it immediately; typed + counted.
    @discardableResult
    public func revokeOverlayPlan(for identity: FrameIdentity) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let ol = overlayLeases.removeValue(forKey: identity) else { return false }
        tempBytesInUse -= ol.bytes
        overlayReceipts.removeValue(forKey: identity)
        counters.overlayRevocations += 1
        return true
    }
    /// L8 seal capability: withdraw ALL plans (e.g. subtitle session end).
    public func revokeAllOverlayPlans() {
        lock.lock()
        let keys = [FrameIdentity](overlayLeases.keys)
        for k in keys {
            if let v = overlayLeases.removeValue(forKey: k) { tempBytesInUse -= v.bytes }
            overlayReceipts.removeValue(forKey: k)
        }
        counters.overlayRevocations += keys.count
        lock.unlock()
    }
    /// L8 authority receipt query: what plan (if any) the renderer
    /// composited for this identity at its last gated submit.
    public func overlayReceipt(for identity: FrameIdentity) -> OverlayCompositeReceipt? {
        lock.lock(); defer { lock.unlock() }
        return overlayReceipts[identity]
    }

    /// Overlay validation (r6 finding 3): FULL identity equality (session,
    /// generation, sequence, revision, PTS, track, score, stream
    /// index/handle, PTS timebase, presentation epoch) + epoch, under a
    /// locked state snapshot - the r5 code checked session/sequence/
    /// revision only and read renderState unlocked. Geometry uses CHECKED
    /// arithmetic; premultiplication validated (color <= alpha per pixel);
    /// bytes counted in the GLOBAL in-use ledger (per-call cap 64 MiB,
    /// L8 r7 aligned). Returns nil ONLY with a typed counter; the caller
    /// turns it into a typed refusal, never a silent bare present.
    private func overlayValidation(_ overlay: PresenterOverlay, lease: FrameLease) -> OverlayLease? {
        guard overlay.identity == lease.identity else {
            countersAdd { $0.overlayStaleDrops += 1 }; return nil
        }
        lock.lock()
        let currentRevision = renderState.surfaceRevision
        let currentEpoch = epoch
        lock.unlock()
        guard overlay.identity.surfaceRevision == currentRevision, lease.epoch == currentEpoch else {
            countersAdd { $0.overlayStaleDrops += 1 }; return nil
        }
        guard lease.renderState.contract.pixelFormat == .sdrRGBA8,
              case .sdrRGBA8Premultiplied(let rgba, let ow, let oh) = overlay.representation else {
            countersAdd { $0.overlayInvalidDrops += 1 }; return nil
        }
        let (oxEnd, ov1) = overlay.frameX.addingReportingOverflow(overlay.frameW)
        let (oyEnd, ov2) = overlay.frameY.addingReportingOverflow(overlay.frameH)
        let (opx, ov3) = ow.multipliedReportingOverflow(by: oh)
        let (obytes, ov4) = opx.multipliedReportingOverflow(by: 4)
        guard !ov1, !ov2, !ov3, !ov4,
              ow > 0, oh > 0,
              ow <= SurfaceContract.maxTextureSide, oh <= SurfaceContract.maxTextureSide,
              obytes <= MetalRenderer.maxTemporaryBytesPerCall,
              rgba.count == obytes,
              overlay.frameX >= 0, overlay.frameY >= 0,
              overlay.frameW > 0, overlay.frameH > 0,
              oxEnd <= lease.frameW, oyEnd <= lease.frameH else {
            countersAdd { $0.overlayInvalidDrops += 1 }; return nil
        }
        // Premultiplication check: no color channel may exceed alpha.
        var i = 0
        while i + 3 < rgba.count {
            if rgba[i] > rgba[i + 3] || rgba[i + 1] > rgba[i + 3] || rgba[i + 2] > rgba[i + 3] {
                countersAdd { $0.overlayInvalidDrops += 1 }; return nil
            }
            i += 4
        }
        // Global in-use ledger (r6 finding 5), lock-held.
        lock.lock()
        guard tempBytesInUse + obytes <= MetalRenderer.maxTemporaryBytesInUse else {
            lock.unlock(); countersAdd { $0.tempBudgetRejections += 1 }; return nil
        }
        tempBytesInUse += obytes
        lock.unlock()
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                          width: ow, height: oh, mipmapped: false)
        td.usage = [.shaderRead]
        td.storageMode = .shared
        guard let t = device.makeTexture(descriptor: td) else {
            lock.lock(); tempBytesInUse -= obytes; lock.unlock()
            countersAdd { $0.allocationFailures += 1 }; return nil
        }
        rgba.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                t.replace(region: MTLRegionMake2D(0, 0, ow, oh), mipmapLevel: 0,
                          withBytes: base, bytesPerRow: ow * 4)
            }
        }
        var p = baseParams(lease: lease)
        p.overlayEnabled = 1
        p.ox = Float(overlay.frameX); p.oy = Float(overlay.frameY)
        p.ow = Float(overlay.frameW); p.oh = Float(overlay.frameH)
        return OverlayLease(identity: lease.identity, texture: t, params: p, epoch: lease.epoch,
                            planRevision: overlay.subtitlePlanRevision, bytes: obytes,
                            ox: overlay.frameX, oy: overlay.frameY,
                            ow: overlay.frameW, oh: overlay.frameH)
    }

    private func baseParams(lease: FrameLease) -> GorAVFrameParamsCPU {
        let st = lease.renderState
        return GorAVFrameParamsCPU(
            overlayEnabled: 0, frameW: Float(lease.frameW), frameH: Float(lease.frameH),
            ox: 0, oy: 0, ow: 0, oh: 0,
            sequence: UInt32(truncatingIfNeeded: lease.identity.sequence),
            surfaceRevision: UInt32(truncatingIfNeeded: lease.identity.surfaceRevision),
            kernelID: st.kernelID, armID: st.armID,
            referenceWhiteNits: Float(st.contract.referenceWhiteNits),
            sourceMinNits: Float(st.contract.sourceSignal?.masteringMinNits ?? 0),
            sourceMaxNits: Float(st.contract.sourceSignal?.masteringMaxNits ?? 0))
    }

    /// Geometry change without renegotiation (resize). Validated + typed
    /// (r6 finding 2): sealed/transitioning renderers and invalid sizes are
    /// typed refusals, and revision overflow seals EXHAUSTED (never an
    /// alias). On accept the retained frame is REBOUND under a CANONICAL
    /// renderer-issued identity at the new revision (textures are
    /// drawable-independent) and its stored overlay plan is re-keyed and
    /// re-stamped - L8 r7: a surfaceRevision change does NOT invalidate
    /// the subtitle plan, so the plan is carried, never silently dropped.
    @discardableResult
    public func noteGeometryChange(width: Int, height: Int) -> GeometryChangeOutcome {
        lock.lock(); defer { lock.unlock() }
        if admissionBlockedLocked() { counters.geometryRejections += 1; return .rejectedSealed }
        guard width > 0, height > 0,
              width <= SurfaceContract.maxTextureSide, height <= SurfaceContract.maxTextureSide else {
            counters.geometryRejections += 1; return .rejectedInvalidSize
        }
        let st = renderState
        let (newRev, ov) = st.surfaceRevision.addingReportingOverflow(1)
        if ov { exhaustedSeal = true; counters.geometryRejections += 1; return .rejectedExhausted }
        let newState = RenderState(pipeline: st.pipeline,
                                   contract: st.contract.withDrawableSize(width: width, height: height),
                                   surfaceRevision: newRev,
                                   outputTransform: st.outputTransform,
                                   kernelID: st.kernelID, armID: st.armID)
        renderState = newState
        if let oldID = lastUploadedIdentity,
           let idx = slots.firstIndex(where: { $0.identity == oldID && $0.epoch == epoch }) {
            let newID = oldID.withSurfaceRevision(newRev)
            slots[idx].identity = newID
            lastUploadedIdentity = newID
            if let ol = overlayLeases.removeValue(forKey: oldID) {
                let p = GorAVFrameParamsCPU(
                    overlayEnabled: 1, frameW: Float(slots[idx].width), frameH: Float(slots[idx].height),
                    ox: Float(ol.ox), oy: Float(ol.oy), ow: Float(ol.ow), oh: Float(ol.oh),
                    sequence: UInt32(truncatingIfNeeded: newID.sequence),
                    surfaceRevision: UInt32(truncatingIfNeeded: newRev),
                    kernelID: newState.kernelID, armID: newState.armID,
                    referenceWhiteNits: Float(newState.contract.referenceWhiteNits),
                    sourceMinNits: Float(newState.contract.sourceSignal?.masteringMinNits ?? 0),
                    sourceMaxNits: Float(newState.contract.sourceSignal?.masteringMaxNits ?? 0))
                overlayLeases[newID] = OverlayLease(identity: newID, texture: ol.texture, params: p,
                                                    epoch: ol.epoch, planRevision: ol.planRevision,
                                                    bytes: ol.bytes, ox: ol.ox, oy: ol.oy,
                                                    ow: ol.ow, oh: ol.oh)
            }
            if let r = overlayReceipts.removeValue(forKey: oldID) {
                overlayReceipts[newID] = OverlayCompositeReceipt(
                    identity: newID, surfaceRevision: newRev, epoch: r.epoch,
                    compositedPlanRevision: r.compositedPlanRevision)
            }
        }
        counters.geometryChangesOK += 1
        return .applied(revision: newRev)
    }

    /// G3: live host pan/zoom. Takes effect on the next encode (present or renderLast). Typed refusal when
    /// sealed or in a transition; never clamps (HostTransform validates range at construction).
    @discardableResult
    public func setHostTransform(_ t: HostTransform) -> HostTransformOutcome {
        lock.lock(); defer { lock.unlock() }
        if admissionBlockedLocked() { return .refusedSealed }
        hostTransformLock.lock(); hostTransform = t; hostTransformLock.unlock()
        return .applied
    }
    /// Candidate activation is explicit. This does not approve existing UI verbs.
    public func setPhotonProducerEnabled(_ enabled:Bool)->Bool {
        lock.lock();defer{lock.unlock()}
        guard !admissionBlockedLocked() else{return false}
        photonEnabled=enabled;photonActivationEpoch=enabled ? epoch:nil;photonTelemetry=nil;photonFailure=nil
        photonProducer.reset()
        return true
    }
    public func completedPhotonTelemetry()->PhotonPresentedTelemetry? {
        lock.lock();defer{lock.unlock()}
        guard photonEnabled,photonTelemetry?.snapshot.epoch==epoch,photonTelemetry?.snapshot.token==photonProducer.token else{return nil}
        return photonTelemetry
    }
    public func photonProducerFailure()->String? {lock.lock();defer{lock.unlock()};return photonFailure}
    private func photonStillCurrentLocked(_ frame:PhotonWorkingFrame)->Bool {
        guard let snapshot=frame.snapshot else{return !photonEnabled || photonActivationEpoch != epoch}
        return photonEnabled && photonActivationEpoch==epoch && snapshot.epoch==epoch && snapshot.token==photonProducer.token
    }
    private func completePhoton(_ snapshot:PhotonProducerSnapshot?,leaseEpoch:UInt64,identity:FrameIdentity) {
        lock.lock();defer{lock.unlock()}
        guard photonEnabled,let snapshot,snapshot.epoch==epoch,epoch==leaseEpoch,snapshot.token==photonProducer.token,
              !admissionBlockedLocked(),identity.surfaceRevision==renderState.surfaceRevision,
              snapshot.revision >= (photonTelemetry?.snapshot.revision ?? 0) else{return}
        photonTelemetry=PhotonPresentedTelemetry(snapshot:snapshot,frameSequence:identity.sequence)
    }
    private func preparePhoton(commandBuffer cb:MTLCommandBuffer,lease:FrameLease,width:Int,height:Int)->PhotonWorkingFrame? {
        let t=currentHostTransform()
        var u=FrameUniforms();u.frameWidth=Float(lease.frameW);u.frameHeight=Float(lease.frameH)
        u.fitModeID=FrameUniformABI.FitID.fit.rawValue
        u.panX=Float(t.panX);u.panY=Float(t.panY);u.log2Zoom=Float(t.log2Zoom)
        guard let quad=StageGeometry.quad(uniforms:u,drawableWidth:width,drawableHeight:height) else{return nil}
        lock.lock()
        guard photonEnabled else{lock.unlock();return PhotonWorkingFrame(texture:lease.texture,snapshot:nil,videoRect:SIMD4<Float>(0,0,1,1))}
        guard photonActivationEpoch==epoch else{photonFailure="Photon source changed; explicit activation required";lock.unlock();return nil}
        guard lease.epoch==epoch,!admissionBlockedLocked() else{lock.unlock();return nil}
        let snapshot:PhotonProducerSnapshot
        do {snapshot=try photonProducer.snapshot(epoch:epoch,sourceWidth:lease.frameW,sourceHeight:lease.frameH,
            outputWidth:width,outputHeight:height,position:lease.identity.ptsSeconds,now:ProcessInfo.processInfo.systemUptime,
            pictureWidth:Double((quad[8]-quad[0])*Float(width)*0.5),pictureHeight:Double((quad[1]-quad[5])*Float(height)*0.5))}
        catch {photonFailure="Photon parameter producer refused: \(error)";lock.unlock();return nil}
        // One existing renderer-global ledger also covers effects + flat geometry.
        let scratch=(lease.frameW*lease.frameH+2*width*height+2*width+2*height)*16
        guard scratch<=MetalRenderer.maxTemporaryBytesInUse-tempBytesInUse else {
            photonFailure="Photon working graph refused: temporary byte budget";lock.unlock();return nil
        }
        tempBytesInUse+=scratch
        lock.unlock()
        let reservation=PhotonGraphReservation{[self] in
            lock.lock();tempBytesInUse-=scratch;lock.unlock()
        }
        cb.addCompletedHandler{_ in withExtendedLifetime(reservation){}}
        do {
            photonGraphLock.lock();defer{photonGraphLock.unlock()}
            if photonGraph==nil {photonGraph=try PhotonWorkingGraph(device:device)}
            return try photonGraph!.encode(on:cb,source:lease.texture,snapshot:snapshot,quad:quad)
        } catch {
            lock.lock();photonFailure="Photon working graph refused: \(error)";lock.unlock();return nil
        }
    }
    public func currentHostTransform() -> HostTransform {
        hostTransformLock.lock(); defer { hostTransformLock.unlock() }
        return hostTransform
    }
    /// Pixel size of the retained frame as uploaded (what the quad is fitted to); nil before the first frame.
    public func lastFrameSize() -> (width: Int, height: Int)? {
        lock.lock(); defer { lock.unlock() }
        guard let id = lastUploadedIdentity,
              let idx = slots.firstIndex(where: { $0.identity == id && $0.epoch == epoch }) else { return nil }
        return (Int(slots[idx].width), Int(slots[idx].height))
    }

    /// The CANONICAL identity of the retained frame (r6 finding 2): the
    /// renderer is the sole issuer. The r5 presenter hand-copied fields
    /// and silently dropped stream index/handle, PTS timebase and
    /// presentation epoch - a ghost identity that could never match the
    /// stored slot. Nil when sealed or nothing is retained.
    public func canonicalRetainedIdentity() -> FrameIdentity? {
        lock.lock(); defer { lock.unlock() }
        guard !admissionBlockedLocked(), let last = lastUploadedIdentity,
              slots.contains(where: { $0.identity == last && $0.epoch == epoch }) else { return nil }
        return last
    }

    /// At-commit current-generation check (L8 r7 UNRESOLVED item,
    /// coordinated here): when an authority is registered, the plan about
    /// to be composited must still be the CURRENT revision for the frame.
    /// Lock-held (fast CPU read on the producer's side).
    private func planStillCurrentLocked(_ ol: OverlayLease) -> Bool {
        guard let authority = subtitlePlanAuthority else { return true } // no authority: receipts stay the post-hoc evidence (stated)
        return authority(ol.identity) == ol.planRevision
    }

    /// Present one identity-addressed frame. When an overlay is supplied
    /// and fails validation the WHOLE present is a typed refusal
    /// (.overlayRefused) - never a silent bare fallback.
    public func renderAndPresent(on layer: CAMetalLayer, identity: FrameIdentity,
                                 overlay: PresenterOverlay? = nil,
                                 d8ProbeID: UInt64? = nil) -> PresentOutcome {
        switch acquireLease(identity: identity) {
        case .sealed:
            countersAdd { $0.sealedDrops += 1 }; return .sealed
        case .staleIdentity:
            countersAdd { $0.staleGenerationDrops += 1 }; return .staleGeneration
        case .noMatch:
            if overlay != nil { countersAdd { $0.overlayStaleDrops += 1 }; return .overlayRefused }
            countersAdd { $0.staleGenerationDrops += 1 }; return .noFrame
        case .acquired(let lease):
            var overlayLease: OverlayLease?
            if let o = overlay {
                guard let validated = overlayValidation(o, lease: lease) else {
                    releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
                    return .overlayRefused // typed refusal; counters already moved
                }
                overlayLease = validated
            }
            return commitPresent(on: layer, lease: lease, overlayLease: overlayLease,
                                 ownsOverlayLease: true, d8ProbeID: d8ProbeID)
        }
    }

    /// Re-render the retained frame for resize/fullscreen. The frame's
    /// STORED overlay lease composites when it is still valid for the
    /// CURRENT epoch AND still current per the registered authority; a
    /// superseded plan is evicted typed (counter), then the frame renders
    /// bare - visibility is preserved for geometry re-renders while stale
    /// content is never composited.
    public func renderLast(on layer: CAMetalLayer) -> PresentOutcome {
        switch acquireLastLease() {
        case .sealed:
            countersAdd { $0.sealedDrops += 1 }; return .sealed
        case .staleIdentity, .noMatch:
            return .noFrame
        case .acquired(let lease):
            lock.lock()
            let stored = overlayLeases[lease.identity]
            let currentEpoch = epoch
            var evictStale = false
            var usable = false
            if let s = stored {
                if s.epoch != currentEpoch {
                    evictStale = true
                } else if !planStillCurrentLocked(s) {
                    evictStale = true // superseded/withdrawn per the authority
                } else {
                    usable = true
                }
            }
            if evictStale, let s = stored {
                overlayLeases.removeValue(forKey: lease.identity)
                overlayReceipts.removeValue(forKey: lease.identity)
                tempBytesInUse -= s.bytes
                counters.overlayStaleDrops += 1
            }
            lock.unlock()
            return commitPresent(on: layer, lease: lease,
                                 overlayLease: usable ? stored : nil,
                                 ownsOverlayLease: false)
        }
    }

    /// Store helper, lock-held: the lease's bytes were counted at
    /// validation; replacing subtracts the old entry.
    private func storeOverlayLeaseLocked(_ ol: OverlayLease) {
        if let old = overlayLeases[ol.identity] { tempBytesInUse -= old.bytes }
        overlayLeases[ol.identity] = ol
    }

    /// The admission barrier + commit gate (r6 finding 1): admission and
    /// cb.commit are bracketed; seal() waits out every bracketed frame.
    /// Sealed re-checks happen AFTER nextDrawable returns AND again at the
    /// final gate immediately before commit - a present blocked in
    /// nextDrawable across a seal/window close can never commit after it.
    /// Overlay lease registration happens AT the gate (pre-commit), never
    /// post-commit (r6 finding 3). ownsOverlayLease marks a freshly
    /// validated lease (dropped on failure paths); a store-borrowed lease
    /// (renderLast) is never released here.
    private func commitPresent(on layer: CAMetalLayer, lease: FrameLease,
                               overlayLease: OverlayLease?, ownsOverlayLease: Bool,
                               d8ProbeID: UInt64? = nil) -> PresentOutcome {
        lock.lock()
        if admissionBlockedLocked() {
            lock.unlock()
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.sealedDrops += 1 }
            return .sealed
        }
        admittedUncommitted += 1
        barrierHeartbeat = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
        defer {
            lock.lock(); admittedUncommitted -= 1; lock.unlock()
        }
        guard let drawable = layer.nextDrawable() else {
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.noDrawableEvents += 1 }
            return .noDrawable
        }
        // Post-drawable gate: seal may have landed while nextDrawable
        // blocked - NEVER commit after the fence.
        lock.lock()
        let blockedAfterDrawable = admissionBlockedLocked()
        if !blockedAfterDrawable { barrierHeartbeat = DispatchTime.now().uptimeNanoseconds }
        lock.unlock()
        if blockedAfterDrawable {
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.sealedDrops += 1 }
            return .sealed
        }
        let dw = Int(layer.drawableSize.width), dh = Int(layer.drawableSize.height)
        guard dw > 0, dh > 0 else {
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.noDrawableEvents += 1 }
            return .noDrawable
        }
        guard let cb = queue.makeCommandBuffer() else {
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.presentErrors += 1 }
            return .starved
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = drawable.texture
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rp.colorAttachments[0].storeAction = .store
        guard let photonFrame=preparePhoton(commandBuffer:cb,lease:lease,width:dw,height:dh),
              let enc = cb.makeRenderCommandEncoder(descriptor: rp) else {
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.presentErrors += 1 }
            return .starved
        }
        guard encode(encoder: enc, lease: lease, photonFrame:photonFrame, drawableWidth: dw, drawableHeight: dh,
               overlayTexture: overlayLease?.texture,
               params: overlayLease?.params ?? baseParams(lease: lease)) else {
            enc.endEncoding()
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.presentErrors += 1 }
            return .starved
        }
        enc.endEncoding()
        #if GORAV_D8_PROBES
        let d8EncodeEnd = D8Probes.now()
        #endif
        cb.present(drawable)
        #if GORAV_D8_PROBES
        let d8PresentIssued = D8Probes.now()
        #endif
        // FINAL COMMIT GATE (r6 findings 1/3): sealed re-check + L8 r7
        // at-commit current-generation check + overlay registration +
        // record/receipt writes, atomically BEFORE commit.
        lock.lock()
        if admissionBlockedLocked() || !photonStillCurrentLocked(photonFrame) {
            lock.unlock()
            if let ol = overlayLease, ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.sealedDrops += 1 }
            return .sealed
        }
        if let ol = overlayLease, !planStillCurrentLocked(ol) {
            // L8 superseded/withdrew this plan between validation and
            // commit: TYPED refusal at the gate, never a post-hoc echo.
            lock.unlock()
            if ownsOverlayLease { releaseOverlayTemp(ol) }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            countersAdd { $0.overlayStaleDrops += 1 }
            return .overlayRefused
        }
        barrierHeartbeat = DispatchTime.now().uptimeNanoseconds
        if let ol = overlayLease, ownsOverlayLease { storeOverlayLeaseLocked(ol) }
        if overlayLease != nil {
            overlayReceipts[lease.identity] = OverlayCompositeReceipt(
                identity: lease.identity, surfaceRevision: lease.identity.surfaceRevision,
                epoch: lease.epoch, compositedPlanRevision: overlayLease?.planRevision)
        }
        var rec = FrameRecord(identity: lease.identity)
        rec.submitted = true
        rec.overlayPlanRevision = overlayLease?.planRevision
        recordsAppendLocked(rec)
        counters.presentSubmitted += 1
        lock.unlock()
        let slotIdx = lease.slotIndex, leaseEpoch = lease.epoch, recID = lease.identity
        cb.addCompletedHandler { [weak self] finished in
            guard let self else { return }
            self.releaseLease(slotIndex: slotIdx, epoch: leaseEpoch)
            self.recordUpdate(recID) { r in
                r.completed = true
                if finished.status == .completed { r.callbackOK = true } else { r.errored = true }
            }
            if finished.status == .completed {
                self.completePhoton(photonFrame.snapshot,leaseEpoch:leaseEpoch,identity:recID)
                self.countersAdd { $0.presentCallbacksOK += 1 }
            } else {
                self.countersAdd { $0.presentErrors += 1 }
            }
        }
        cb.commit()
        #if GORAV_D8_PROBES
        D8Probes.shared.submitted(d8ProbeID, encode: d8EncodeEnd,
                                  present: d8PresentIssued, commit: D8Probes.now())
        #endif
        return .submitted
    }

    private func encode(encoder enc: MTLRenderCommandEncoder, lease: FrameLease, photonFrame:PhotonWorkingFrame,
                        drawableWidth: Int, drawableHeight: Int, overlayTexture: MTLTexture?, params: GorAVFrameParamsCPU) -> Bool {
        let t = currentHostTransform()
        var u = FrameUniforms()
        u.frameWidth = Float(lease.frameW); u.frameHeight = Float(lease.frameH)
        u.fitModeID = FrameUniformABI.FitID.fit.rawValue
        u.panX = Float(t.panX); u.panY = Float(t.panY); u.log2Zoom = Float(t.log2Zoom)
        enc.setRenderPipelineState(lease.renderState.pipeline)
        // Same stage binding for actual onscreen and offscreen leased frames.
        // Color/output transform and bitmap composition retain their existing pipeline.
        do {
            try MetalStagePass.bindGeometry(encoder: enc, uniforms: u,
                                            drawableWidth: drawableWidth, drawableHeight: drawableHeight)
        } catch { return false }
        if photonFrame.snapshot != nil {
            let full:[Float]=[-1,1,0,0,-1,-1,0,1,1,1,1,0,1,-1,1,1]
            full.withUnsafeBytes{enc.setVertexBytes($0.baseAddress!,length:$0.count,index:0)}
        }
        enc.setFragmentTexture(photonFrame.texture, index: 0)
        enc.setFragmentTexture(overlayTexture ?? lease.texture, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)
        var p = params
        enc.setFragmentBytes(&p, length: MemoryLayout<GorAVFrameParamsCPU>.stride, index: 0)
        var composite=PhotonCompositeUniforms()
        composite.videoRect=photonFrame.videoRect
        composite.enabled.x=photonFrame.snapshot == nil ? 0:1
        enc.setFragmentBytes(&composite,length:MemoryLayout<PhotonCompositeUniforms>.stride,index:3)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    /// Bounded quiescence on ONE monotonic budget (r6 finding 6: the r5
    /// close was seal(2s) + drain(2s) = up to 4s). The barrier gets a
    /// small share (commits take microseconds); the drain gets the rest.
    /// Seconds validated: NaN/negative/Inf fall back to the default, never
    /// trap a UInt64 conversion.
    @discardableResult
    public func close(maxWaitSeconds: Double = 2.0) async -> Int {
        let budget = (maxWaitSeconds.isFinite && maxWaitSeconds > 0) ? min(maxWaitSeconds, 60) : 2.0
        let start = DispatchTime.now().uptimeNanoseconds
        _ = seal(maxBarrierSeconds: min(0.25, budget))
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        let budgetNs = UInt64(budget * 1e9)
        let remaining = budgetNs > elapsed ? budgetNs - elapsed : 0
        return await drainInFlight(maxWaitSeconds: Double(remaining) / 1e9)
    }

    private func drainInFlight(maxWaitSeconds: Double) async -> Int {
        let bound = (maxWaitSeconds.isFinite && maxWaitSeconds >= 0) ? min(maxWaitSeconds, 60) : 2.0
        let deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(bound * 1e9)
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if Task.isCancelled { break } // typed residual below, never a spin
            lock.lock()
            let n = slots.reduce(0) { $0 + $1.readers } + legacyInFlight + admittedUncommitted
            lock.unlock()
            if n == 0 { return 0 }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        lock.lock(); defer { lock.unlock() }
        return slots.reduce(0) { $0 + $1.readers } + legacyInFlight + admittedUncommitted
    }

    public func countersSnapshot() -> RendererCounters {
        lock.lock(); defer { lock.unlock() }; return counters
    }
    public func recordsSnapshot() -> [FrameRecord] {
        lock.lock(); defer { lock.unlock() }; return records
    }
    public var frameSize: (w: Int, h: Int) {
        lock.lock(); defer { lock.unlock() }
        guard let last = lastUploadedIdentity,
              let s = slots.first(where: { $0.identity == last && $0.epoch == epoch }) else { return (0, 0) }
        return (s.width, s.height)
    }

    /// Quad vertices: aspect-fit NDC positions, texcoords (0,0)=top-left
    /// (standard CAMetalLayer convention; matrix B readback-verifies).
    static func quad(_ fit: AspectFit, transform: HostTransform) -> [Float] {
        hostTransformQuad(scaleX: fit.scaleX, scaleY: fit.scaleY, transform)
    }
    static func quad(_ fit: AspectFit) -> [Float] {
        let sx = Float(fit.scaleX), sy = Float(fit.scaleY)
        return [-sx,  sy, 0, 0,
                -sx, -sy, 0, 1,
                 sx,  sy, 1, 0,
                 sx, -sy, 1, 1]
    }

    /// Offscreen render of one leased frame through the SAME pipeline and
    /// fragment path as the present, INCLUDING the frame's valid stored
    /// overlay lease. r6 finding 1: takes the SAME admission barrier as
    /// the present path (the r5 offscreen path was uncounted - a pre-seal
    /// readback could commit after seal) and waits BOUNDED on a monotonic
    /// poll instead of waitUntilCompleted. On timeout the completion
    /// handler keeps ownership of the lease/admission/bytes (no unsafe
    /// early release while the GPU may still read). OWNS the lease release
    /// in every path - callers must not release after calling this.
    private enum OffscreenOutcome {
        case ok(texture: MTLTexture, planRevision: UInt64?)
        case failed
        case timedOut
    }
    private final class OffscreenCleanup { var claimed = false }

    private func finishOffscreen(_ box: OffscreenCleanup, bytes: Int,
                                 slotIndex: Int, slotEpoch: UInt64) {
        lock.lock()
        if box.claimed { lock.unlock(); return }
        box.claimed = true
        tempBytesInUse -= bytes
        admittedUncommitted -= 1
        if slots.indices.contains(slotIndex), slots[slotIndex].epoch == slotEpoch, slots[slotIndex].readers > 0 {
            slots[slotIndex].readers -= 1
        } else if slotEpoch != epoch, legacyInFlight > 0 {
            legacyInFlight -= 1
            if legacyInFlight == 0 { retiredSlotBytes = 0 }
        }
        lock.unlock()
    }

    private func renderOffscreen(lease: FrameLease, dw: Int, dh: Int) -> OffscreenOutcome {
        let bpp = lease.renderState.contract.pixelFormat == .edrRGBA16F ? 8 : 4
        let (dpx, o1) = dw.multipliedReportingOverflow(by: dh)
        let (obytes, o2) = dpx.multipliedReportingOverflow(by: bpp)
        guard dw > 0, dh > 0, dw <= SurfaceContract.maxTextureSide, dh <= SurfaceContract.maxTextureSide,
              !o1, !o2, obytes <= SurfaceContract.maxFrameBytes else {
            countersAdd { $0.readbackErrors += 1 }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            return .failed
        }
        // Admission + global temp ledger, lock-held.
        lock.lock()
        if admissionBlockedLocked() {
            lock.unlock()
            countersAdd { $0.readbackErrors += 1 }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            return .failed
        }
        guard tempBytesInUse + obytes <= MetalRenderer.maxTemporaryBytesInUse else {
            lock.unlock()
            countersAdd { $0.tempBudgetRejections += 1 }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            return .failed
        }
        tempBytesInUse += obytes
        admittedUncommitted += 1
        barrierHeartbeat = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
        let box = OffscreenCleanup()
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: SurfaceNegotiator.metalPixelFormat(lease.renderState.contract.pixelFormat),
            width: dw, height: dh, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let off = device.makeTexture(descriptor: td),
              let cb = queue.makeCommandBuffer() else {
            finishOffscreen(box, bytes: obytes, slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
            countersAdd { $0.readbackErrors += 1 }
            return .failed
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = off
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rp.colorAttachments[0].storeAction = .store
        guard let photonFrame=preparePhoton(commandBuffer:cb,lease:lease,width:dw,height:dh),
              let enc = cb.makeRenderCommandEncoder(descriptor: rp) else {
            finishOffscreen(box, bytes: obytes, slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
            countersAdd { $0.readbackErrors += 1 }
            return .failed
        }
        lock.lock()
        let stored = overlayLeases[lease.identity]
        let currentEpoch = epoch
        // The at-commit generation check applies to offscreen commits too:
        // a superseded/withdrawn plan is never composited into NEW
        // evidence; it is evicted typed and the render is bare.
        var evictStale = false
        var usable = false
        if let s = stored {
            if s.epoch != currentEpoch || !planStillCurrentLocked(s) { evictStale = true }
            else { usable = true }
        }
        if evictStale, let s = stored {
            overlayLeases.removeValue(forKey: lease.identity)
            overlayReceipts.removeValue(forKey: lease.identity)
            tempBytesInUse -= s.bytes
            counters.overlayStaleDrops += 1
        }
        lock.unlock()
        var ovl: OverlayLease?
        if usable { ovl = stored }
        guard encode(encoder: enc, lease: lease, photonFrame:photonFrame, drawableWidth: dw, drawableHeight: dh,
               overlayTexture: ovl?.texture, params: ovl?.params ?? baseParams(lease: lease)) else {
            enc.endEncoding()
            finishOffscreen(box, bytes: obytes, slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
            countersAdd { $0.readbackErrors += 1 }
            return .failed
        }
        enc.endEncoding()
        // Gate before commit: sealed mid-encode abandons typed.
        lock.lock()
        let blocked = admissionBlockedLocked() || !photonStillCurrentLocked(photonFrame)
        if !blocked { barrierHeartbeat = DispatchTime.now().uptimeNanoseconds }
        lock.unlock()
        if blocked {
            finishOffscreen(box, bytes: obytes, slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
            countersAdd { $0.readbackErrors += 1 }
            return .failed
        }
        cb.addCompletedHandler { [weak self, off] _ in
            self?.finishOffscreen(box, bytes: obytes,
                                  slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
        }
        cb.commit()
        // BOUNDED monotonic poll (r6 finding 1: waitUntilCompleted was
        // unbounded). finishOffscreen is idempotent; whoever runs first
        /// (handler or this poll) does the cleanup exactly once.
        let deadline = DispatchTime.now().uptimeNanoseconds &+ 2_000_000_000
        var settled = false
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if cb.status == .completed || cb.status == .error { settled = true; break }
            usleep(500)
        }
        if settled, cb.status == .completed {
            finishOffscreen(box, bytes: obytes, slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
            return .ok(texture: off, planRevision: ovl?.planRevision)
        }
        if settled { // .error
            finishOffscreen(box, bytes: obytes, slotIndex: lease.slotIndex, slotEpoch: lease.epoch)
            countersAdd { $0.readbackErrors += 1 }
            return .failed
        }
        // Timeout: the GPU may still be reading the slot + target. The
        // handler (capturing off) keeps the lease, admission and bytes
        // until real completion - bounded CPU wait, no unsafe release.
        countersAdd { $0.readbackErrors += 1 }
        return .timedOut
    }

    /// 1:1 readback of one identity-addressed frame, 8-bit path (SDR
    /// contract only). OFFSCREEN evidence, identity-bound receipt.
    public func readbackNative(identity: FrameIdentity) -> ReadbackReceipt? {
        guard case .acquired(let lease) = acquireLease(identity: identity) else {
            countersAdd { $0.readbackErrors += 1 }; return nil
        }
        guard lease.renderState.contract.pixelFormat == .sdrRGBA8 else {
            countersAdd { $0.readbackErrors += 1 }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            return nil
        }
        let fw = lease.frameW, fh = lease.frameH
        guard fw > 0, fh > 0, case .ok(let off, let planRev) = renderOffscreen(lease: lease, dw: fw, dh: fh) else { return nil }
        // Staging bytes counted in the global ledger while held (the
        /// returned receipt's payload is caller-owned evidence, bounded
        /// per call by maxFrameBytes).
        let (spx, s1) = fw.multipliedReportingOverflow(by: fh)
        let (stageBytes, s2) = spx.multipliedReportingOverflow(by: 4)
        guard !s1, !s2 else { countersAdd { $0.readbackErrors += 1 }; return nil }
        lock.lock()
        if tempBytesInUse + stageBytes > MetalRenderer.maxTemporaryBytesInUse {
            lock.unlock(); countersAdd { $0.tempBudgetRejections += 1 }; return nil
        }
        tempBytesInUse += stageBytes
        lock.unlock()
        var out = [UInt8](repeating: 0, count: fw * fh * 4)
        out.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                off.getBytes(base, bytesPerRow: fw * 4,
                             from: MTLRegionMake2D(0, 0, fw, fh), mipmapLevel: 0)
            }
        }
        lock.lock(); tempBytesInUse -= stageBytes; lock.unlock()
        countersAdd { $0.readbacksOK += 1 }
        let sha = SHA256.hash(data: Data(out)).map { String(format: "%02x", $0) }.joined()
        return ReadbackReceipt(sha256: sha, bytes: out, halfWords: nil,
                               identity: lease.identity,
                               surfaceRevision: lease.identity.surfaceRevision,
                               pixelFormat: .sdrRGBA8, width: fw, height: fh,
                               compositedOverlayPlanRevision: planRev)
    }

    /// Real FLOAT readback of one identity-addressed frame (16F contract).
    public func readbackNative16F(identity: FrameIdentity) -> ReadbackReceipt? {
        guard case .acquired(let lease) = acquireLease(identity: identity) else {
            countersAdd { $0.readbackErrors += 1 }; return nil
        }
        guard lease.renderState.contract.pixelFormat == .edrRGBA16F else {
            countersAdd { $0.readbackErrors += 1 }
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            return nil
        }
        let fw = lease.frameW, fh = lease.frameH
        guard fw > 0, fh > 0, case .ok(let off, let planRev) = renderOffscreen(lease: lease, dw: fw, dh: fh) else { return nil }
        let (spx, s1) = fw.multipliedReportingOverflow(by: fh)
        let (stageBytes, s2) = spx.multipliedReportingOverflow(by: 8)
        guard !s1, !s2 else { countersAdd { $0.readbackErrors += 1 }; return nil }
        lock.lock()
        if tempBytesInUse + stageBytes > MetalRenderer.maxTemporaryBytesInUse {
            lock.unlock(); countersAdd { $0.tempBudgetRejections += 1 }; return nil
        }
        tempBytesInUse += stageBytes
        lock.unlock()
        var out = [UInt16](repeating: 0, count: fw * fh * 4)
        out.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                off.getBytes(base, bytesPerRow: fw * 8,
                             from: MTLRegionMake2D(0, 0, fw, fh), mipmapLevel: 0)
            }
        }
        lock.lock(); tempBytesInUse -= stageBytes; lock.unlock()
        countersAdd { $0.readbacksOK += 1 }
        let sha = out.withUnsafeBytes { raw in
            SHA256.hash(data: Data(raw)).map { String(format: "%02x", $0) }.joined()
        }
        return ReadbackReceipt(sha256: sha, bytes: nil, halfWords: out,
                               identity: lease.identity,
                               surfaceRevision: lease.identity.surfaceRevision,
                               pixelFormat: .edrRGBA16F, width: fw, height: fh,
                               compositedOverlayPlanRevision: planRev)
    }

    /// Letterbox probe at one pixel of an offscreen render sized like the
    /// drawable (matrix C witness; OFFSCREEN evidence, SDR path only).
    /// Dimensions bounded.
    public func probePixel(identity: FrameIdentity, px: Int, py: Int,
                           drawableW: Int, drawableH: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard drawableW > 0, drawableH > 0,
              drawableW <= SurfaceContract.maxTextureSide, drawableH <= SurfaceContract.maxTextureSide,
              SurfaceContract.frameBytesOK(width: drawableW, height: drawableH, bytesPerPixel: 4),
              px >= 0, py >= 0, px < drawableW, py < drawableH else { return nil }
        guard case .acquired(let lease) = acquireLease(identity: identity) else { return nil }
        guard lease.renderState.contract.pixelFormat == .sdrRGBA8 else {
            releaseLease(slotIndex: lease.slotIndex, epoch: lease.epoch)
            return nil
        }
        guard case .ok(let off, _) = renderOffscreen(lease: lease, dw: drawableW, dh: drawableH) else { return nil }
        var px4 = [UInt8](repeating: 0, count: 4)
        px4.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                off.getBytes(base, bytesPerRow: 4,
                             from: MTLRegionMake2D(px, py, 1, 1), mipmapLevel: 0)
            }
        }
        return (px4[0], px4[1], px4[2])
    }
}

/// CPU mirror of the shader's GorAVFrameParams (layout: 4-byte fields only).
public struct GorAVFrameParamsCPU {
    public var overlayEnabled: UInt32 = 0
    public var frameW: Float = 0
    public var frameH: Float = 0
    public var ox: Float = 0
    public var oy: Float = 0
    public var ow: Float = 0
    public var oh: Float = 0
    public var sequence: UInt32 = 0
    public var surfaceRevision: UInt32 = 0
    public var kernelID: UInt32 = 0
    public var armID: UInt32 = 0
    public var referenceWhiteNits: Float = 0
    public var sourceMinNits: Float = 0
    public var sourceMaxNits: Float = 0
    public var pad: Float = 0
    public init() {}
    public init(overlayEnabled: UInt32, frameW: Float, frameH: Float,
                ox: Float, oy: Float, ow: Float, oh: Float,
                sequence: UInt32, surfaceRevision: UInt32, kernelID: UInt32, armID: UInt32,
                referenceWhiteNits: Float, sourceMinNits: Float, sourceMaxNits: Float) {
        self.overlayEnabled = overlayEnabled; self.frameW = frameW; self.frameH = frameH
        self.ox = ox; self.oy = oy; self.ow = ow; self.oh = oh
        self.sequence = sequence; self.surfaceRevision = surfaceRevision
        self.kernelID = kernelID; self.armID = armID
        self.referenceWhiteNits = referenceWhiteNits
        self.sourceMinNits = sourceMinNits; self.sourceMaxNits = sourceMaxNits
    }
}
#endif
