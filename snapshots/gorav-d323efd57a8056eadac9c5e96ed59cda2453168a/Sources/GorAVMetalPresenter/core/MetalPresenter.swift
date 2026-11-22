// L2 presenter (block 78d), revision 4 (architect r6 findings 2/3/6 + L8
// r7 seam): resize applies the TYPED geometry outcome and re-reads the
// CANONICAL retained identity from the renderer (no hand-copied ghost
// identity); renegotiate clears the retained identity via the same
// canonical query; sequence overflow is a typed stop (never an alias);
// the seal outcome surfaces typed; the L8 at-commit generation authority
// and plan revoke capabilities pass through.
// CAMetalLayer window + FrameSink replacement for the v1.4 DisplaySink.
// r3 close semantics (finding 1): windowShouldClose is a SYNCHRONOUS
// MainActor close-intent fence - it seals the instance and the renderer
// BEFORE the window closes, so any queued show/resize/fullscreen work is a
// typed drop from that instant; async bounded quiescence follows.
// programmaticClose seals the same way; close() seals, quiesces, THEN
// closes the window, holding its lifetime until teardown. Session identity:
// the presenter mints full FrameIdentity values (sessionID + generation +
// unique sequence + surfaceRevision, r2 finding 3 / L8 r3). Telemetry is
// session-scoped (no recreate contamination). AUTHORED NEW 2026-10-25.
#if canImport(AppKit) && canImport(Metal)
import AppKit
import Metal
import QuartzCore
import GorAVPlaybackCore
import GorAVSubtitles

/// Monotonic session generation source (process-wide, locked).
public enum GorAVSessionGenerations {
    private static let lock = NSLock()
    private static var next: UInt64 = 0
    private static var issued = Set<UInt64>()
    /// Monotonic while the space lasts; on exhaustion mint UNIQUE random
    /// generations - an aliased generation is never issued (r6 finding 6).
    public static func issue() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        if next < UInt64.max {
            next += 1
            issued.insert(next)
            return next
        }
        while true {
            let candidate = UInt64.random(in: 1...UInt64.max)
            if !issued.contains(candidate) { issued.insert(candidate); return candidate }
        }
    }
}

public final class MetalPresenterView: NSView {
    public var onResize: ((Int, Int) -> Void)?
    private let cueLabel = NSTextField(wrappingLabelWithString: "")
    private let secondaryCueLabel = NSTextField(wrappingLabelWithString: "")
    private func configureCue(_ label: NSTextField) {
        label.textColor = .white; label.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        label.drawsBackground = true; label.alignment = .center
        label.font = .systemFont(ofSize: 22, weight: .medium)
        label.isSelectable = false; label.isHidden = true
        addSubview(label)
    }
    func displayCues(primary: SubtitleCue?, secondary: SubtitleCue?) {
        cueLabel.stringValue = primary?.text ?? ""
        secondaryCueLabel.stringValue = secondary?.text ?? ""
        cueLabel.isHidden = primary == nil; secondaryCueLabel.isHidden = secondary == nil
        needsLayout = true
    }
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        configureCue(cueLabel); configureCue(secondaryCueLabel)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    public var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }
    public override func layout() {
        super.layout()
        synchronizeDrawableGeometry()
        let width = max(0, bounds.width - 48)
        // Plain text delivery surface only, not ASS/bitmap composition or film-fit placement.
        cueLabel.frame = NSRect(x: 24, y: 24, width: width, height: 90)
        secondaryCueLabel.frame = NSRect(x: 24, y: max(24, bounds.height - 114), width: width, height: 90)
    }
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeDrawableGeometry()
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeDrawableGeometry()
    }
    /// A host can move between displays without changing its logical bounds.
    /// Keep the actual drawable and renderer callback in the same backing units.
    private func synchronizeDrawableGeometry() {
        guard let ml = metalLayer else { return }
        ml.contentsScale = window?.backingScaleFactor ?? 1.0
        let size = convertToBacking(bounds.size)
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) else {
            // CAMetalLayer refuses a zero drawable. Keep the last valid size
            // while hidden, and do not submit a zero geometry callback.
            return
        }
        ml.drawableSize = size
        onResize?(Int(size.width), Int(size.height))
    }
}

/// FrameSink conformance targets the SETTLED trunk contract (PlaybackCore,
/// LANE-0 CONTRACT item 1 SETTLED + verdict S5 rev3): show(_:) async -> Bool
/// AND show(_:admission:) async -> Bool, NO default forwarding. The Bool is
/// the typed admission (validated+allocated+texture-written), never a
/// GPU-completion or scanout claim. The ticketed variant consumes the
/// per-frame admission ticket through the shared CancelCommit authority in
/// the SAME critical section as the texture assignment (ACK = no further
/// commit); with no authority bound it refuses typed, never default-accepts.
/// r8 port (block 168 L3 landing): authority bound at init, no adoption
/// surface, mirroring DisplaySink (verdict S5 rev5).
public final class MetalPresenter: NSObject, FrameSink, NSWindowDelegate, @unchecked Sendable {
    private let window: NSWindow?   // nil in E1 embed mode (host owns the window)
    private let view: MetalPresenterView
    private let renderer: MetalRenderer
    /// r8 trunk-contract port: the shared cancel/commit authority is an
    /// IMMUTABLE INIT-TIME input (verdict S5 rev5) - there is NO adopt/re-adopt
    /// mutation surface; the sink is bound to ONE authority for its life.
    /// Optional ONLY for off-pump witness-matrix presenters (gorav-metal-check);
    /// the ticketed show refuses typed when unbound.
    private let cancelCommit: CancelCommit?
    public private(set) var sessionID: String
    public private(set) var sessionGeneration: UInt64
    private var closed = false
    /// r8: instance-level close intent (pump closeRequested/shouldStop fence),
    /// set synchronously in windowShouldClose with the seal.
    public private(set) var closedByUser = false
    private var lastPtsSeconds = 0.0
    private var sequence: UInt64 = 0
    /// Source-track revision fence (L8 r4 (b): the DECODER track semantic,
    /// separate from any subtitle plan revision). A PTS regress is treated
    /// as a seek/track change: the revision bumps, so overlays minted for
    /// the old track go stale typed. Presenter-local until L3 exposes a
    /// real decoder track revision, which then replaces this fence.
    private var trackRevision: UInt64 = 0
    private var cueConsumer: SubtitleCueConsumer?

    /// Bind once to the playback session, not the presenter's independent surface ID.
    @MainActor public func bindSubtitleSession(_ session: UInt64) {
        guard !closed, cueConsumer == nil else { return }
        cueConsumer = SubtitleCueConsumer(session: session)
    }
    @MainActor @discardableResult
    public func consumeSubtitleCues(_ batch: SubtitleCueBatch) -> Bool {
        guard !closed, var consumer = cueConsumer, consumer.consume(batch) else { return false }
        cueConsumer = consumer
        view.displayCues(primary: consumer.primary?.cue, secondary: consumer.secondary?.cue)
        return true
    }

    /// r2 finding 1: windowShouldClose is the close-intent FENCE. It runs
    /// synchronously on the MainActor BEFORE the window closes: instance
    /// sealed + renderer sealed, so every queued Task that touches the GPU
    /// after this point is a typed drop. Quiescence is async afterwards.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            fenceClosed()
            closedByUser = true
            MetalPresenterTelemetry.closedByUser = true
        }
        let r = renderer
        Task { _ = await r.close() } // async quiescence follows the fence
        return true
    }
    public func windowDidEnterFullScreen(_ notification: Notification) {
        MainActor.assumeIsolated { MetalPresenterTelemetry.fullscreenEntries += 1 }
        Task { @MainActor [weak self] in self?.rerenderIfOpen() }
    }
    public func windowDidExitFullScreen(_ notification: Notification) {
        MainActor.assumeIsolated { MetalPresenterTelemetry.fullscreenExits += 1 }
        Task { @MainActor [weak self] in self?.rerenderIfOpen() }
    }

    /// E1 EMBED-HOST boundary (additive; shape settled by coordinator: gor
    /// supplies the player NSView, the presenter owns the embedded
    /// MetalPresenterView/layer/lifecycle INSIDE it). This init NEVER creates
    /// an NSWindow and never falls back to one; close() tears down GPU/audio
    /// but leaves the host view hierarchy alone - the host owns its window
    /// and its close intent. Window mode (gorav-play CLI) unchanged.
    @MainActor public init(embedIn hostView: NSView,
                           contract: SurfaceContract = .sdrDefault,
                           outputTransform: OutputTransform = .identity,
                           commit: CancelCommit? = nil) throws {
        let r = try MetalRenderer(contract: contract, outputTransform: outputTransform)
        let gen = GorAVSessionGenerations.issue()
        let sid = UUID().uuidString
        r.beginSession(sessionID: sid, generation: gen)
        let v = MetalPresenterView(frame: hostView.bounds)
        v.autoresizingMask = [.width, .height]
        // XA9 compose review (failure cleanup): negotiate BEFORE parenting. A
        // throwing SurfaceNegotiator.apply after addSubview would leak our
        // view INTO THE HOST's hierarchy from a FAILED init; negotiating first
        // means a throw leaves the host untouched (nothing was ever attached).
        // Window-mode init order is unchanged.
        // XA9 compose2 question: the layer must be NON-NIL before parenting -
        // wantsLayer=true creates it in MetalPresenterView.init via
        // makeBackingLayer (AppKit layer-hosting contract), but embed mode
        // never ASSUMES: nil is a typed refusal, not a silently skipped
        // negotiation. (Window mode keeps its historical if-let - unchanged.)
        guard let ml = v.metalLayer else {
            throw SurfaceContract.NegotiationError.metalLayerUnavailable
        }
        try SurfaceNegotiator.apply(contract, to: ml, device: r.device)
        hostView.addSubview(v)
        self.window = nil
        self.view = v
        self.renderer = r
        self.sessionID = sid
        self.sessionGeneration = gen
        self.cancelCommit = commit
        super.init()
        MetalPresenterTelemetry.beginSession()
        installGeometryHandler(v)
    }

    /// Shared typed-geometry handler (r6 finding 2 rebind path), both modes.
    private func installGeometryHandler(_ v: MetalPresenterView) {
        v.onResize = { [weak self] dw, dh in
            Task { @MainActor in
                MetalPresenterTelemetry.resizeEvents += 1
                guard let self else { return }
                switch self.renderer.noteGeometryChange(width: dw, height: dh) {
                case .applied:
                    self.lastIdentity = self.renderer.canonicalRetainedIdentity()
                case .rejectedSealed, .rejectedInvalidSize, .rejectedExhausted:
                    MetalPresenterTelemetry.geometryRejections += 1
                }
                self.rerenderIfOpen()
            }
        }
    }

    @MainActor public init(screenCheck: Void,
                           contract: SurfaceContract = .sdrDefault,
                           outputTransform: OutputTransform = .identity,
                           commit: CancelCommit? = nil) throws {
        let r = try MetalRenderer(contract: contract, outputTransform: outputTransform)
        let gen = GorAVSessionGenerations.issue()
        let sid = UUID().uuidString
        r.beginSession(sessionID: sid, generation: gen)
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 480),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "gorav probe"
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.fullScreenPrimary]
        let v = MetalPresenterView(frame: w.contentView!.bounds)
        v.autoresizingMask = [.width, .height]
        w.contentView = v
        self.window = w
        self.view = v
        self.renderer = r
        self.sessionID = sid
        self.sessionGeneration = gen
        self.cancelCommit = commit
        super.init()
        // Session-scoped telemetry (r2 finding 1): a recreate starts clean.
        MetalPresenterTelemetry.beginSession()
        // ONE surface negotiation: device + format + colorspace + EDR flags
        // + drawable bound, from the contract, in one place.
        if let ml = v.metalLayer {
            try SurfaceNegotiator.apply(contract, to: ml, device: r.device)
        }
        w.delegate = self
        installGeometryHandler(v)
        w.makeKeyAndOrderFront(nil)
    }

    /// The synchronous fence, idempotent: instance + renderer sealed NOW.
    @MainActor private func fenceClosed() {
        guard !closed else { return }
        closed = true
        cueConsumer = nil
        view.displayCues(primary: nil, secondary: nil)
        // Typed seal outcome (r6 finding 1): a residual barrier is
        // surfaced in telemetry, never hidden.
        if case .residual(let pending) = renderer.seal() {
            MetalPresenterTelemetry.sealResidualEvents += 1
            MetalPresenterTelemetry.sealResidualPending += pending
        }
    }

    @MainActor private func rerenderIfOpen() {
        guard !closed else { MetalPresenterTelemetry.staleWorkAfterClose += 1; return }
        guard let ml = view.metalLayer else { return }
        // Re-render the SELECTED frame's own lease+identity (r2 finding 3),
        // not an anonymous "current" pointer.
        let outcome = renderer.renderLast(on: ml)
        if case .noDrawable = outcome { MetalPresenterTelemetry.drawableNilPresents += 1 }
    }

    /// Nil on sequence-space exhaustion: a typed stop, NEVER a wrapped
    /// alias of an earlier frame (r6 finding 6).
    @MainActor private func nextIdentity(producerSource: SourceSession? = nil) -> FrameIdentity? {
        let (next, ov) = sequence.addingReportingOverflow(1)
        if ov { return nil }
        sequence = next
        return FrameIdentity(sessionID: sessionID, sessionGeneration: sessionGeneration,
                             sequence: sequence,
                             surfaceRevision: renderer.currentSurfaceRevision,
                             ptsSeconds: lastPtsSeconds,
                             trackRevision: trackRevision, producerSource: producerSource)
    }

    /// L1 v2 admission seam (cross-lane compile finding): returns true only
    /// when the frame was VALIDATED + ALLOCATED + texture-written. It is
    /// NOT a GPU-completion, present or scanout claim - the renderer's
    /// callback receipts carry those (offscreen/callback evidence only).
    public func show(_ frame: SourceFrame) async -> Bool {
        // Native ownership must be checked against an issuing session/ticket.
        // The legacy unticketed API has no such authority.
        guard frame.vtPayload == nil else { return false }
        guard frame.pixelPayload != nil || frame.vtPayload != nil else {
            await MainActor.run { MetalPresenterTelemetry.noPixels += 1 }
            return false
        }
        return await MainActor.run {
            // Fence check BEFORE any GPU touch: after windowShouldClose this
            // is already sealed, however the show was queued (r2 findings 1/8).
            guard !closed else { MetalPresenterTelemetry.staleWorkAfterClose += 1; return false }
            // PTS regress = seek/track change: bump the source-track fence.
            if frame.ptsSeconds < lastPtsSeconds - 0.0005 { trackRevision &+= 1 }
            lastPtsSeconds = frame.ptsSeconds
            guard let identity = nextIdentity() else {
                MetalPresenterTelemetry.sequenceExhausted += 1
                return false
            }
            // P30/W2 (arch-197b): a VT payload uploads GPU-resident via
            // CVMetalTextureCache; the RGBA path is byte-identical to before.
            if let vt = frame.vtPayload {
                switch renderer.upload(vtFrame: vt, identity: identity) {
                case .okZeroCopy:
                    MetalPresenterTelemetry.uploads += 1
                    lastIdentity = identity
                default:
                    MetalPresenterTelemetry.uploadRejections += 1
                    return false
                }
            } else if let px = frame.pixelPayload {
                switch renderer.upload(rgba: px.bytes, width: px.width, height: px.height, identity: identity) {
                case .ok:
                    // The upload counter moves only on validated success.
                    MetalPresenterTelemetry.uploads += 1
                    lastIdentity = identity
                default:
                    MetalPresenterTelemetry.uploadRejections += 1
                    return false
                }
            }
            #if GORAV_D8_PROBES
            D8Probes.shared.upload(frame.d8ProbeID)
            let probe = frame.d8ProbeID
            #else
            let probe: UInt64? = nil
            #endif
            guard let ml = view.metalLayer else { return true }
            switch renderer.renderAndPresent(on: ml, identity: identity, d8ProbeID: probe) {
            case .submitted:
                // Submit-time visibility; the renderer's presentCallbacksOK
                // receipt is a callback receipt, NOT scanout proof.
                if (window?.isVisible ?? (view.window != nil)) && (window?.windowNumber ?? (view.window?.windowNumber ?? 0)) > 0 {
                    MetalPresenterTelemetry.visibleUploads += 1
                }
            case .noDrawable:
                MetalPresenterTelemetry.drawableNilPresents += 1
            default:
                break
            }
            return true
        }
    }

    /// r8 trunk-contract port (verdict S5 rev3, STRICT): the per-frame
    /// admission ticket travels with the frame and is validated AND consumed
    /// through the commit authority in the SAME critical section as the
    /// texture upload + present submit (ACK = no further commit). The close
    /// fence is evaluated inside the section via `permit`; a fenced frame
    /// never burns its ticket. With NO authority bound the ticket cannot be
    /// validated - refused typed, never default-accepted.
    public func show(_ frame: SourceFrame, admission ticket: CancelCommit.AdmissionTicket) async -> Bool {
        guard let commit = cancelCommit else {
            await MainActor.run { MetalPresenterTelemetry.ticketRefusals += 1 }
            return false
        }
        if let vt = frame.vtPayload {
            guard let provenance = vt.provenance,
                  provenance.admits(source: SourceSession(session: commit.sessionEpoch, revision: ticket.revision),
                                    ptsSeconds: frame.ptsSeconds, durationSeconds: frame.durationSeconds) else {
                await MainActor.run { MetalPresenterTelemetry.ticketRefusals += 1 }
                return false
            }
        }
        guard frame.pixelPayload != nil || frame.vtPayload != nil else {
            await MainActor.run { MetalPresenterTelemetry.noPixels += 1 }
            return false
        }
        return await MainActor.run {
            guard !closed else {
                MetalPresenterTelemetry.staleWorkAfterClose += 1
                MetalPresenterTelemetry.ticketRefusals += 1
                return false
            }
            if frame.ptsSeconds < lastPtsSeconds - 0.0005 { trackRevision &+= 1 }
            lastPtsSeconds = frame.ptsSeconds
            // Identity + upload + present ALL run inside the commit section as
            // the contents assignment, so a cancel/seek ACK can never
            // interleave between the check and the GPU assignment.
            var assigned = false
            let committed = commit.commitFrame(ticket,
                framePTS: frame.ptsSeconds, frameDigest: frame.digest,
                permit: { UploadFence.mayUpload(closeIntent: self.closedByUser) },
                assign: {
                    guard let identity = self.nextIdentity(producerSource: frame.vtPayload?.provenance?.source) else {
                        MetalPresenterTelemetry.sequenceExhausted += 1
                        return
                    }
                    // P30/W2 (arch-197b): VT payload = GPU-resident upload.
                    if let vt = frame.vtPayload {
                        switch self.renderer.upload(vtFrame: vt, identity: identity) {
                        case .okZeroCopy:
                            MetalPresenterTelemetry.uploads += 1
                            self.lastIdentity = identity
                        default:
                            MetalPresenterTelemetry.uploadRejections += 1
                            return
                        }
                    } else if let px = frame.pixelPayload {
                        switch self.renderer.upload(rgba: px.bytes, width: px.width, height: px.height, identity: identity) {
                        case .ok:
                            MetalPresenterTelemetry.uploads += 1
                            self.lastIdentity = identity
                        default:
                            MetalPresenterTelemetry.uploadRejections += 1
                            return
                        }
                    }
                    #if GORAV_D8_PROBES
                    D8Probes.shared.upload(frame.d8ProbeID)
                    let probe = frame.d8ProbeID
                    #else
                    let probe: UInt64? = nil
                    #endif
                    if let ml = self.view.metalLayer {
                        switch self.renderer.renderAndPresent(on: ml, identity: identity, d8ProbeID: probe) {
                        case .submitted:
                            if (self.window?.isVisible ?? (self.view.window != nil)) && (self.window?.windowNumber ?? (self.view.window?.windowNumber ?? 0)) > 0 {
                                MetalPresenterTelemetry.visibleUploads += 1
                            }
                        case .noDrawable:
                            MetalPresenterTelemetry.drawableNilPresents += 1
                        default:
                            break
                        }
                    }
                    assigned = true
                })
            guard committed else {
                MetalPresenterTelemetry.ticketRefusals += 1
                return false
            }
            if assigned { MetalPresenterTelemetry.ticketedCommits += 1 }
            return assigned
        }
    }

    /// Close: synchronous seal first, then bounded GPU quiescence, THEN the
    /// window is closed - the close API owns the window's lifetime and
    /// holds it until teardown (r2 finding 1). Returns residual in-flight
    /// count (0 = quiesced), reported in receipts, never log-only.
    @MainActor @discardableResult
    public func close() async -> Int {
        fenceClosed()
        let residual = await renderer.close()
        if let window, window.isVisible {
            window.close()
        } else if window == nil {
            // E1 embed mode (XBPP factory review fix): after GPU/audio
            // quiescence, detach ONLY the presenter-owned view from the host -
            // a repeated attach/replace must never stack MetalPresenterViews.
            // The host NSView and its window are never removed or touched;
            // window-mode lifecycle is unchanged. Idempotent: a second close
            // re-seals and removeFromSuperview on an unparented view no-ops.
            // ACTUAL isolation: close() is nonisolated async and this class is
            // not @MainActor, so the AppKit call hops to the main actor
            // explicitly (never a convention assumption).
            await MainActor.run { view.removeFromSuperview() }
        }
        return residual
    }

    /// E1 embed lifecycle (facade contract): explicit detach of the
    /// presenter-owned view from the host, callable after await close().
    /// CANONICAL SHAPE (coordinator/facade aligned): close() already performs
    /// the same bounded detach in embed mode; this API is the explicit seam
    /// the facade calls. Both are idempotent, so the facade call is always
    /// safe and never double-detaches. @MainActor, EMBED-ONLY: in window mode
    /// it is a typed counted no-op - the window's contentView is never
    /// detached and window-mode behavior is unchanged. The host NSView/window
    /// hierarchy is never removed or touched beyond unparenting our own view.
    @MainActor public func detachEmbeddedView() {
        guard window == nil else { MetalPresenterTelemetry.windowModeNoOps += 1; return }
        view.removeFromSuperview()
    }

    /// L8 seam entry: composite an identity-bound overlay onto its frame.
    /// Returns the typed outcome: an invalid/stale overlay is
    /// .overlayRefused (the base frame is NOT silently presented bare).
    @MainActor @discardableResult
    public func showOverlay(_ overlay: PresenterOverlay) -> PresentOutcome {
        guard !closed else { MetalPresenterTelemetry.staleWorkAfterClose += 1; return .sealed }
        guard let ml = view.metalLayer else { return .noDrawable }
        return renderer.renderAndPresent(on: ml, identity: overlay.identity, overlay: overlay)
    }

    /// L8 r4 (a) regeneration support: the identity of the last uploaded
    /// frame REFRESHED to the current surface revision (same session,
    /// sequence, PTS and track). After a resize/fullscreen/renegotiate the
    /// old plan goes stale typed; the producer mints its new plan against
    /// THIS identity and the same frame keeps ownership.
    /// L8 r4 (a) regeneration support: the CANONICAL renderer-issued
    /// identity of the retained frame at the current revision (r6 finding
    /// 2: the r6 code hand-copied fields here and silently dropped stream
    /// index/handle, PTS timebase and presentation epoch - a ghost
    /// identity that could never match the stored slot).
    @MainActor public func lastFrameIdentityForCurrentRevision() -> FrameIdentity? {
        renderer.canonicalRetainedIdentity()
    }

    /// L5 seam passthrough: renegotiate the surface on the SAME renderer.
    @MainActor public func renegotiateSurface(_ contract: SurfaceContract,
                                              ot: OutputTransform) async throws {
        // Atomic layer + render-state handoff (r3 finding 5).
        try await renderer.renegotiate(contract, ot: ot, layer: view.metalLayer)
        // The ring is cleared by the renegotiation; the retained identity
        // must not survive as a ghost (r6 finding 2). Canonical query
        // returns nil until the next accepted upload.
        lastIdentity = renderer.canonicalRetainedIdentity()
    }
    /// Mid-life session restart (r2 finding 2 witness path): seals,
    /// quiesces old work, THEN reopens with a fresh session identity; the
    /// presenter adopts the same new session so later uploads are valid.
    @MainActor @discardableResult
    public func restartSessionForMeasurement() async throws -> Int {
        fenceClosed()
        let sid = UUID().uuidString
        let gen = GorAVSessionGenerations.issue()
        let residual = try await renderer.restartSession(sessionID: sid, generation: gen)
        sessionID = sid
        sessionGeneration = gen
        sequence = 0
        trackRevision = 0
        lastIdentity = nil
        closed = false
        return residual
    }

    /// L8 r7 at-commit current-subtitle-generation authority (the OPEN
    /// cross-lane item): registered by the subtitle producer; queried at
    /// the renderer's final commit gate. A plan that is no longer current
    /// is a typed refusal AT COMMIT - the receipt echo stays post-hoc
    /// evidence, never the barrier.
    @MainActor public func setSubtitlePlanAuthority(_ authority: ((FrameIdentity) -> UInt64?)?) {
        renderer.setSubtitlePlanAuthority(authority)
    }
    /// L8 authority receipt: which plan revision the renderer composited
    /// for one frame identity at its last gated submit.
    @MainActor public func overlayReceipt(for identity: FrameIdentity) -> OverlayCompositeReceipt? {
        renderer.overlayReceipt(for: identity)
    }
    /// L8 seal capability (r6 finding 3): withdraw one plan or all plans;
    /// re-renders stop compositing immediately, typed + counted.
    @MainActor @discardableResult
    public func revokeOverlayPlan(for identity: FrameIdentity) -> Bool {
        renderer.revokeOverlayPlan(for: identity)
    }
    @MainActor public func revokeAllOverlayPlans() { renderer.revokeAllOverlayPlans() }

    // Measurement API (matrix witnesses):
    @MainActor public func readbackLast() -> ReadbackReceipt? {
        MetalPresenterTelemetry.readbacks += 1
        guard let id = lastIdentity else { return nil }
        return renderer.readbackNative(identity: id)
    }
    @MainActor public func readback(identity: FrameIdentity) -> ReadbackReceipt? {
        MetalPresenterTelemetry.readbacks += 1
        return renderer.readbackNative(identity: identity)
    }
    /// Identity of the most recently accepted upload (for matrix readbacks).
    @MainActor public private(set) var lastIdentity: FrameIdentity?
    @MainActor public func probePixel(identity: FrameIdentity, px: Int, py: Int,
                                      drawableW: Int, drawableH: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        renderer.probePixel(identity: identity, px: px, py: py, drawableW: drawableW, drawableH: drawableH)
    }
    /// G3: live host pan/zoom. Typed outcome, never a silent no-op. Applies from the next presented frame and
    /// re-renders the retained frame now, so a paused picture follows the gesture.
    @MainActor @discardableResult
    public func setHostTransform(_ t: HostTransform) -> HostTransformOutcome {
        guard !closed else { return .refusedSealed }
        let o = renderer.setHostTransform(t)
        if o == .applied { rerenderIfOpen() }
        return o
    }
    @MainActor @discardableResult
    public func setPhotonProducerEnabled(_ enabled:Bool)->Bool {
        guard !closed else{return false}
        let accepted=renderer.setPhotonProducerEnabled(enabled)
        if accepted {rerenderIfOpen()}
        return accepted
    }
    @MainActor public func completedPhotonTelemetry()->PhotonPresentedTelemetry? {
        guard !closed else{return nil};return renderer.completedPhotonTelemetry()
    }
    @MainActor public func photonProducerFailure()->String? {renderer.photonProducerFailure()}
    /// G3: frame size as presented, drawable size and the on-screen video rect (with the host transform).
    /// nil before the first frame or after close.
    @MainActor public func effectiveVideo() -> EffectiveVideoGeometry? {
        guard !closed, let f = renderer.lastFrameSize() else { return nil }
        let d = drawablePixelSize
        return effectiveVideoGeometry(drawableW: d.w, drawableH: d.h, frameW: f.width, frameH: f.height,
                                      renderer.currentHostTransform())
    }
    @MainActor public func rendererCounters() -> RendererCounters { renderer.countersSnapshot() }
    @MainActor public func rendererRecords() -> [FrameRecord] { renderer.recordsSnapshot() }
    /// Window-mode controls: in E1 EMBED mode the host owns the window, so
    /// these are typed no-ops (counted), never silent and never a host-window
    /// side effect. Embed hosts drive geometry by resizing their own view.
    @MainActor public func setWindowSize(width: Int, height: Int) {
        guard let window else { MetalPresenterTelemetry.windowModeNoOps += 1; return }
        window.setContentSize(NSSize(width: width, height: height))
    }
    @MainActor public func toggleFullScreenNow() {
        guard let window else { MetalPresenterTelemetry.windowModeNoOps += 1; return }
        window.toggleFullScreen(nil)
    }
    @MainActor public func performUserClose() {
        guard let window else { MetalPresenterTelemetry.windowModeNoOps += 1; return }
        window.performClose(nil)
    }
    /// Programmatic close seals with the SAME synchronous fence (r2 finding
    /// 1), then closes the window; quiescence via close(). Embed mode: seals
    /// only - the host's window is never closed by the presenter.
    @MainActor public func programmaticClose() {
        fenceClosed()
        window?.close()
    }
    @MainActor public var windowIsVisible: Bool { window?.isVisible ?? (view.window != nil) }
    @MainActor public var windowContentPixelSize: (w: Int, h: Int) {
        // Backing pixels of the ATTACHED view: the window's content view in
        // window mode, the embedded presenter view (inside the host) in E1
        // embed mode - correct in both, never .zero-by-nil.
        let s = view.convertToBacking(view.bounds.size)
        return (Int(s.width), Int(s.height))
    }
    @MainActor public var drawablePixelSize: (w: Int, h: Int) {
        let s = view.metalLayer?.drawableSize ?? .zero
        return (Int(s.width), Int(s.height))
    }
}
#endif
