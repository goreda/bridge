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
// P31-STEREO-LOOK shared-caller seam (2026-11-22, lane: stereo/photon;
// narrow shared-adapter ownership per Ops assignment): the live
// admission/render seam drives the QUALIFIED v7 stage adapter per
// admitted frame through the StereoLookPresenterSubmission binding
// (StereoLookPresenterBinding.swift, same module - this file is its
// consumer, so the binding is no alias-only "integration"). Admitted
// FrameIdentity minted here flows to the stage UNPROJECTED (full core
// equality, SurfaceContract.swift); production happens AFTER the
// accepted upload and BEFORE renderAndPresent (ticketed path: inside
// the same commit section, so a stage payload can never straddle an
// admission). Stage lifecycle follows the Ops grounding: invalidate +
// fresh-install on surface/geometry/stream/source changes, retire on
// seal/close. The render seam reads stereoStageBlock(admitted:) -
// typed stale-refusal answers nil, never a substitute key. The runtime
// owner (VRRuntimeOwner/StereoProjectionMetal) is untouched: nothing
// here publishes, acknowledges or activates; the title path stays
// disabled; no 180/360 derivation. Host state is an EXPLICIT host
// input (setStereoHostState); this seam invents no pose, geometry or
// layout. NOT_RUN: no compile/native acceptance has run for this seam.
// v9: rebased onto the canonical mac-source-sync presenter (763 lines,
// instinct 55fa3618) per Z4C evidence 09629212.
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
    var subtitleVideoRect:(()->NSRect?)?
    private(set) var subtitlePosition=100.0
    private(set) var subtitleLayoutRefused=false
    private let cueLabel = NSTextField(wrappingLabelWithString: "")
    private let secondaryCueLabel = NSTextField(wrappingLabelWithString: "")
    /// GORAV-SUBTITLE-TYPOGRAPHY: user scale on the real cue surface, applied
    /// to both labels. 1.0 is the established default size; validated by the
    /// caller through SubtitleTypography.adjustedScale.
    var cueFontScale = SubtitleTypography.defaultScale {
        didSet { applyCueTypography() }
    }
    private func applyCueTypography() {
        let font = NSFont.systemFont(ofSize: SubtitleTypography.renderedFontSize(scale: cueFontScale), weight: .medium)
        cueLabel.font = font
        secondaryCueLabel.font = font
        needsLayout=true
    }
    private func configureCue(_ label: NSTextField) {
        label.textColor = .white; label.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        label.drawsBackground = true; label.alignment = .center
        label.font = .systemFont(ofSize: SubtitleTypography.baseCueFontSize, weight: .medium)
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
        subtitleLayoutRefused = !layoutCueLabels(position:subtitlePosition,apply:true)
    }
    /// Measure using each actual label cell/font/wrapping width, in AppKit points.
    /// Helper coordinates are upper-left/Y-down, unlike this unflipped NSView.
    private func cueFrames(position:Double)->[NSRect]? {
        guard position.isFinite,(0...100).contains(position),let film=subtitleVideoRect?() else{return nil}
        let visible=bounds.intersection(film)
        let safe=visible.insetBy(dx:24,dy:24)
        guard !safe.isNull,safe.width>0,safe.height>0,
              let region=SafeRectangle(minX:Double(safe.minX-bounds.minX),minY:Double(bounds.maxY-safe.maxY),width:Double(safe.width),height:Double(safe.height)) else{return nil}
        let labels=[cueLabel,secondaryCueLabel]
        var heights=[CGFloat]()
        for label in labels {
            if label.isHidden {heights.append(0);continue}
            guard let cell=label.cell else{return nil}
            let measured=cell.cellSize(forBounds:NSRect(x:0,y:0,width:safe.width,height:CGFloat.greatestFiniteMagnitude))
            guard measured.height.isFinite,measured.height>0 else{return nil}
            heights.append(ceil(measured.height))
        }
        var frames=[NSRect.zero,NSRect.zero]
        var placedPrimary:SubtitlePlacement?
        for i in 0..<2 where heights[i]>0 {
            let h=Double(heights[i])
            guard let block=SubtitleBlockRect(minX:region.minX,minY:region.minY,width:region.width,height:h) else{return nil}
            let desired=i==0 ? position/100:0
            guard case .success(var placed)=SubtitlePositionBounds.propose(safe:region,block:block,position:desired) else{return nil}
            if i==1,let primary=placedPrimary {
                // Keep the established secondary-top placement when possible;
                // choose the opposite edge only to avoid the primary cue block.
                if placed.maxY+8>primary.minY && placed.minY<primary.maxY+8 {
                    guard case .success(let bottom)=SubtitlePositionBounds.propose(safe:region,block:block,position:1),
                          bottom.minY>=primary.maxY+8 else{return nil}
                    placed=bottom
                }
            }
            if i==0 {placedPrimary=placed}
            frames[i]=NSRect(x:bounds.minX+CGFloat(placed.minX),y:bounds.maxY-CGFloat(placed.minY+placed.height),width:CGFloat(placed.width),height:CGFloat(placed.height))
        }
        return frames
    }
    @discardableResult
    private func layoutCueLabels(position:Double,apply:Bool)->Bool {
        guard let frames=cueFrames(position:position) else{return false}
        if apply {cueLabel.frame=frames[0];secondaryCueLabel.frame=frames[1]}
        return true
    }
    func setSubtitlePosition(_ percent:Double)->Bool {
        guard percent.isFinite,(0...100).contains(percent) else{return false}
        // With no cue, retain intent without inventing measured/applied pixels.
        if !cueLabel.isHidden || !secondaryCueLabel.isHidden {
            guard layoutCueLabels(position:percent,apply:false) else{return false}
        }
        subtitlePosition=percent;needsLayout=true
        return true
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
    /// fileprivate: the presenter's source-adoption reacquisition calls
    /// it (PATH A); it is the ONLY geometry-sync entry, owning-order
    /// preserved.
    fileprivate func synchronizeDrawableGeometry() {
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
/// P31: named dedup key for refusal-event emission - a persistent
/// refusal fires ONCE per authority context, never per frame. Public so
/// the integrating session can apply the same key shape.
public struct StereoProjectionRefusalDedupKey: Equatable, Sendable {
    public let reason: String
    public let stageEpoch: UInt64?
    public let hostSession: UUID?
    public let hostAcceptanceEpoch: UInt64?
    /// The accepting owner's installed source generation - rejects
    /// queued refusals across same-session/same-path re-adoption.
    public let hostSourceGeneration: UInt64?
    public let hostStateRegistration: UInt64
    public init(reason: String, stageEpoch: UInt64?, hostSession: UUID?,
                hostAcceptanceEpoch: UInt64?, hostSourceGeneration: UInt64?,
                hostStateRegistration: UInt64) {
        self.reason = reason; self.stageEpoch = stageEpoch
        self.hostSession = hostSession
        self.hostAcceptanceEpoch = hostAcceptanceEpoch
        self.hostSourceGeneration = hostSourceGeneration
        self.hostStateRegistration = hostStateRegistration
    }
}

/// P31: ONE renderer-time projection refusal with FULL origin custody -
/// enough for the host to reject QUEUED/stale refusal messages across
/// same-session/same-path re-adoption and provider changes (a string,
/// session UUID or path alone is NOT sufficient). Delivered through
/// MetalPresenter.stereoProjectionRefusalHandler after all renderer
/// locks are released, fenced on the custody still being current.
public struct StereoProjectionRefusalEvent: Equatable, Sendable {
    /// The typed refusal reason (renderer registration refusal).
    public let reason: String
    /// The full identity of the refused admitted frame.
    public let identity: FrameIdentity
    /// The stage installation the refusal arose under.
    public let stageEpoch: UInt64?
    /// Current-host custody: session UUID, source and acceptance epoch.
    public let hostSession: UUID?
    public let hostSource: String?
    public let hostAcceptanceEpoch: UInt64?
    /// The accepting owner's installed source generation at emission.
    public let hostSourceGeneration: UInt64?
    /// The presenter's monotone provider-install registration.
    public let hostStateRegistration: UInt64
    /// The renderer authority mutation generation AFTER the refusal.
    public let rendererAuthorityGeneration: UInt64
    public init(reason: String, identity: FrameIdentity, stageEpoch: UInt64?,
                hostSession: UUID?, hostSource: String?, hostAcceptanceEpoch: UInt64?,
                hostSourceGeneration: UInt64?,
                hostStateRegistration: UInt64, rendererAuthorityGeneration: UInt64) {
        self.reason = reason; self.identity = identity; self.stageEpoch = stageEpoch
        self.hostSession = hostSession; self.hostSource = hostSource
        self.hostAcceptanceEpoch = hostAcceptanceEpoch
        self.hostSourceGeneration = hostSourceGeneration
        self.hostStateRegistration = hostStateRegistration
        self.rendererAuthorityGeneration = rendererAuthorityGeneration
    }
}

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
    /// P31: the installed stereo stage binding (nil until the host
    /// installs it; never implicitly created by a frame).
    private var stereoStage: StereoLookPresenterSubmission?
    /// P31: the host's EXPLICIT per-frame stereo state. Production is
    /// skipped (counted) while a stage is installed but no host state
    /// has been supplied; nothing is defaulted.
    public private(set) var stereoHostState: StereoLookHostState?
    /// P31 host-state PROVIDER (pull model, Ops nativefeed contract):
    /// the session installs a same-actor provider; EVERY admitted frame
    /// pulls it synchronously on this actor (nil included) before
    /// stage.frame. `stereoHostStateRegistration` is the session-owned
    /// MONOTONE install fence: installs with a non-increasing
    /// registration are refused whole, and the pull captures the
    /// registration before calling the provider and rechecks it after
    /// return, so a reentrant replace/rebind can never deliver a stale
    /// result. Install, replacement, source change and close
    /// IMMEDIATELY clear the cached state AND submission - never
    /// deferred to a next frame.
    /// PATH A (Ops 8:11:41): the pull ARGUMENT is this presenter's
    /// own live sample of the actual attached view
    /// (currentStereoLookPullContext); nil context means
    /// detached/mismatch/unresolved and the provider must vend nil.
    @MainActor private var stereoHostStateProvider: (@MainActor (StereoLookPullContext?) -> StereoLookHostInput?)?
    /// PATH A (Ops 8:11:41): the renderer's last ADMITTED drawable
    /// geometry, recorded at the noteGeometryChange .applied response
    /// (the renderer's own admission, MetalRenderer l.1195-1246) -
    /// NEVER from the layer's assigned drawableSize, which can run
    /// ahead of renderer admission. The post-upload stereo drive
    /// NEVER advances this (no noteGeometryChange from the pull
    /// path): correspondence is checked, never forced.
    @MainActor private var lastAdmittedDrawableGeometry: (w: Int, h: Int, revision: UInt64)?
    /// ADMISSION EPOCH (v14 review: a queued onResize callback from
    /// BEFORE a custody-clearing event must never mint a fresh
    /// admission after it - the renderer mints whatever it is asked,
    /// so the STALE QUEUE, not the renderer, is the hole). Captured
    /// synchronously at queue time and rechecked before the renderer
    /// is touched; bumped by every custody clear (source adoption,
    /// provider replace, retire).
    @MainActor private var admittedGeometryEpoch: UInt64 = 0
    // Only the latest queued geometry request may commit. Task execution
    // order is not a physical resize-order guarantee.
    @MainActor private var admittedGeometryRequestSerial: UInt64 = 0
    /// Custody of the last pulled host input (diagnostics only; never
    /// authority here). Set only on a fenced-consistent pull.
    @MainActor public private(set) var lastStereoHostInputCustody: (session: UUID, source: String, acceptanceEpoch: UInt64, sourceGeneration: UInt64?, restrictedProjectionAdmission: StereoLookRestrictedProjectionAdmission?, withheldLanes: [String], policyConstantLanes: [String])?
    /// full182: the last pulled input's distance trace, retained under the
    /// same custody pattern as lastStereoHostInputCustody (assigned only
    /// inside pullStereoHostState after the registration/epoch fences,
    /// never derived from an encode receipt). Visibility only: consumers
    /// must not treat it as admission authority.
    @MainActor public private(set) var lastStereoDistanceTrace: StereoLookDistanceTrace?
    /// full182: the native geom-trace line for the last pulled distance
    /// evaluation (block182 owner order item 2: log d, s, the clamp flag
    /// and each fallback reason in the geom trace). The payload is
    /// Lua-identical (pin c455d945 l.406-413), so native and Lua traces
    /// compare line-for-line. nil when no traced pull has happened yet.
    @MainActor public func stereoDistanceGeomTraceLine() -> String? {
        lastStereoDistanceTrace?.geomTraceLine()
    }
    /// full182 trace-sink wiring: the EXISTING package sink contract - a
    /// handler the app bridge installs (same shape as
    /// stereoProjectionRefusalHandler above; the app routes it to its
    /// existing LOCAL GeomTrace facility, which is off by default).
    /// Emitted ONLY when the produced line changes AND a handler is
    /// installed; the change is recorded only on ACTUAL delivery, so a
    /// nil sink swallows nothing and a later-attached sink receives the
    /// current line at the next pull. The dedup resets on handler
    /// replacement and on provider install/replace/drop (a new sink or
    /// authority always gets the current line once). Nothing is
    /// buffered or sent to any external destination. Trace content
    /// stays local and bounded: one Lua-shaped vrDistance line per
    /// change (block182 owner order item 2: d, s, the clamp flag and
    /// each fallback reason).
    @MainActor public var stereoDistanceTraceHandler: ((String) -> Void)? {
        didSet { lastEmittedDistanceTraceLine = nil }
    }
    @MainActor private var lastEmittedDistanceTraceLine: String?
    @MainActor private var stereoHostStateRegistration: UInt64 = 0
    /// P31: renderer-time projection-refusal sink. Ops wires this to the
    /// EXISTING native-entry refusal UI (PPController.swift:1502
    /// nativeStereoRefusal -> spineUI.showMPVOSD(reason, force:true),
    /// reached through embeddedThreeDState/embeddedThreeDAction) with
    /// Ops's own current-source-generation/receipt fencing,
    /// deduplication, close/re-adoption clearing and G5-await
    /// preservation. The presenter NEVER mutates the Store to Off to
    /// hide a failed request.
    @MainActor public var stereoProjectionRefusalHandler: ((StereoProjectionRefusalEvent) -> Void)?
    @MainActor private var lastStereoProjectionRefusalDedup: StereoProjectionRefusalDedupKey?
    /// P31: currency validator for a queued or previously emitted
    /// refusal event - the integrating session rejects a stale event
    /// after same-source geometry changes, provider swaps or
    /// re-adoption. Compares the event's custody against the CURRENT
    /// private stage installed epoch, provider registration, host
    /// custody and the LIVE renderer authority generation.
    /// Compares the event's FULL custody - the CURRENT refused/bound
    /// frame identity (a same-HostState later-frame custody change
    /// invalidates a queued old event), stage installed epoch, provider
    /// registration, host session/source/epoch/sourceGeneration and the
    /// LIVE renderer authority generation.
    @MainActor public func isCurrentStereoProjectionRefusal(_ event: StereoProjectionRefusalEvent) -> Bool {
        guard !closed, stereoHostState != nil else { return false }
        return event.identity == renderer.stereoAuthorityIdentity()
            && event.stageEpoch == stereoStage?.installedEpoch
            && event.hostStateRegistration == stereoHostStateRegistration
            && event.hostSession == lastStereoHostInputCustody?.session
            && event.hostSource == lastStereoHostInputCustody?.source
            && event.hostAcceptanceEpoch == lastStereoHostInputCustody?.acceptanceEpoch
            && event.hostSourceGeneration == lastStereoHostInputCustody?.sourceGeneration
            && event.rendererAuthorityGeneration == renderer.stereoAuthorityGeneration()
    }
    /// P31: seam counters (own type in the binding file; the shared
    /// MetalPresenterTelemetry file is NOT touched by this lane).
    public private(set) var stereoCounters = StereoLookPresenterCounters()

    /// Bind once to the playback session, not the presenter's independent surface ID.
    /// GORAV-SUBTITLE-TYPOGRAPHY: apply the user subtitle scale to the real
    /// cue surface. Typed refusal (false) when closed or out of range; the
    /// caller commits state and announces only after true.
    @MainActor @discardableResult
    public func setSubtitleFontScale(_ scale: Double) -> Bool {
        guard !closed,
              let accepted = SubtitleTypography.adjustedScale(current: scale, delta: 0, reset: false),
              accepted == scale else { return false }
        view.cueFontScale = accepted
        return true
    }

    @MainActor @discardableResult
    public func setSubtitlePosition(_ percent:Double)->Bool {
        guard !closed else{return false}
        return view.setSubtitlePosition(percent)
    }
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
        v.subtitleVideoRect = { [weak self,weak v] in
          MainActor.assumeIsolated {
            guard let self,let v,let f=self.renderer.lastFrameSize() else{return nil}
            let d=self.drawablePixelSize,crop=self.renderer.currentSourceCrop()
            guard let r=effectiveVideoRect(drawableW:d.w,drawableH:d.h,frameW:max(1,Int((Double(f.width)*crop.width).rounded())),frameH:max(1,Int((Double(f.height)*crop.height).rounded())),self.renderer.currentHostTransform()),d.w>0,d.h>0 else{return nil}
            let sx=v.bounds.width/CGFloat(d.w),sy=v.bounds.height/CGFloat(d.h)
            return NSRect(x:v.bounds.minX+CGFloat(r.x)*sx,y:v.bounds.maxY-CGFloat(r.y+r.h)*sy,width:CGFloat(r.w)*sx,height:CGFloat(r.h)*sy)
          }
        }
        v.onResize = { [weak self] dw, dh in
            // View layout callbacks fire on the main thread (same
            // assumption as subtitleVideoRect above): capture the
            // admission epoch SYNCHRONOUSLY at queue time, before the
            // Task hop. A callback queued before a custody clear then
            // fails the recheck below and never reaches the renderer.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.admittedGeometryRequestSerial &+= 1
                let queuedSerial = self.admittedGeometryRequestSerial
                let queuedEpoch = self.admittedGeometryEpoch
                Task { @MainActor [weak self] in
                MetalPresenterTelemetry.resizeEvents += 1
                guard let self, !self.closed,
                      self.admittedGeometryEpoch == queuedEpoch,
                      self.admittedGeometryRequestSerial == queuedSerial else { return }
                let backing = self.windowContentPixelSize
                let target = self.drawablePixelSize
                guard backing.w == dw, backing.h == dh,
                      target.w == dw, target.h == dh else { return }
                switch self.renderer.noteGeometryChange(width: dw, height: dh) {
                case .applied(let revision):
                    self.lastAdmittedDrawableGeometry = (dw, dh, revision)
                    self.lastIdentity = self.renderer.canonicalRetainedIdentity()
                    // P31: an applied geometry change invalidates the
                    // stage (surface change); resume with a fresh epoch.
                    self.stereoStageInvalidate(.surfaceChange)
                case .rejectedSealed, .rejectedInvalidSize, .rejectedExhausted:
                    MetalPresenterTelemetry.geometryRejections += 1
                }
                self.rerenderIfOpen()
                }
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
        // Ops nativefeed contract: close immediately drops the provider
        // and cached host state; the seal below retires the stage.
        stereoHostStateProvider = nil
        stereoHostState = nil
        // P31: close revokes the projection input with the stage and
        // resets the refusal dedup (a re-adopted authority re-reports).
        renderer.setStereoProjectionBinding(nil)
        lastStereoProjectionRefusalDedup = nil
        lastEmittedDistanceTraceLine = nil
        cueConsumer = nil
        view.displayCues(primary: nil, secondary: nil)
        // Typed seal outcome (r6 finding 1): a residual barrier is
        // surfaced in telemetry, never hidden.
        if case .residual(let pending) = renderer.seal() {
            MetalPresenterTelemetry.sealResidualEvents += 1
            MetalPresenterTelemetry.sealResidualPending += pending
        }
        // P31: seal retires the stage (no resume).
        stereoStageInvalidate(.retire)
    }

    /// PATH A source-adoption reacquisition (Ops 8:18:48): after a
    /// source adoption cleared the admitted-geometry custody, re-assert
    /// the CURRENT geometry through the REAL owning order (view
    /// drawable sync -> onResize -> renderer noteGeometryChange), so a
    /// same-size adoption re-acquires a lawful admission. Until the
    /// admission lands, pulls vend nil (the block is never weakened).
    /// Control-plane only: callers are the session's adoption path on
    /// this actor, NEVER the post-upload pull path (no revision
    /// mutation from driveStereoStage).
    @MainActor public func readmitDrawableGeometryForSourceAdoption() {
        view.synchronizeDrawableGeometry()
    }

    /// P31: install the stereo stage for this presenter (host-driven:
    /// the session observes stereo-stage activation and supplies host
    /// state via setStereoHostState). Idempotent while installed.
    @MainActor public func installStereoStage() {
        guard !closed else { return }
        if stereoStage == nil { stereoStage = StereoLookPresenterSubmission() }
        guard stereoStage?.installedEpoch == nil else { return }
        _ = stereoStage?.install()
        stereoCounters.recordInstall()
    }
    /// P31: tear the stage down (retire; no resume) and detach the
    /// binding, so a later session restart never resurrects a stage the
    /// host removed.
    @MainActor public func uninstallStereoStage() {
        stereoStageInvalidate(.retire)
        stereoStage = nil
        stereoHostState = nil
        stereoHostStateProvider = nil
        stereoHostStateRegistration = 0
        lastEmittedDistanceTraceLine = nil
    }
    /// P31: the host's explicit per-frame stereo state input. Any
    /// ACTUAL change - loss (nil) or replacement - clears the
    /// submission and rebinds the stage through authorityChanged()
    /// (Z4C v11 authority-loss RED): a block produced under a previous
    /// authority can never bind against the new one, not even between
    /// the set and the next drive. Identical-value sets are no-ops.
    @MainActor public func setStereoHostState(_ state: StereoLookHostState?) {
        guard state != stereoHostState else { return }
        stereoHostState = state
        stereoStage?.authorityChanged()
        // P31: authority loss/change revokes the renderer's projection
        // input synchronously (nil ACTIVELY removes any prior input).
        renderer.setStereoProjectionBinding(nil)
    }
    /// P31: install/replace/remove the host-state provider (Ops
    /// nativefeed contract). ANY actual cached state is cleared NOW
    /// through the same authority-loss path (Z4C v11): a block
    /// produced under a previous provider's authority can never bind
    /// against the new one, not even between this call and the next
    /// drive. With no cached state there is no live submission to
    /// clear (loss already clears it), so nothing is churned.
    @MainActor public func setStereoHostStateProvider(_ provider: (@MainActor (StereoLookPullContext?) -> StereoLookHostInput?)?, registration: UInt64) {
        // Monotone install fence: a stale (non-increasing) registration
        // is a leftover from a superseded install order; refuse whole.
        guard !closed, registration > stereoHostStateRegistration else { return }
        stereoHostStateProvider = provider
        stereoHostStateRegistration = registration
        // Trace dedup is per-authority: a new provider re-delivers the
        // current line once even if its text matches the previous
        // authority's.
        lastEmittedDistanceTraceLine = nil
        // PATH A custody hygiene (Ops 8:16:57): geometry admitted
        // under a previous provider's authority is not this provider's
        // custody - the next pull re-proves correspondence from a
        // fresh admission.
        dropAdmittedDrawableGeometryCustody()
        // P31: provider replacement revokes the projection input NOW,
        // even with no cached state - a binding from the previous
        // authority must never survive the swap.
        renderer.setStereoProjectionBinding(nil)
        if stereoHostState != nil { setStereoHostState(nil) }
        // Reacquisition must be queued AFTER this install's custody clear.
        // All install paths, including adoption and replacement, use it.
        if provider != nil { readmitDrawableGeometryForSourceAdoption() }
    }
    /// P31: the Ops-contract pull, called at the top of every admitted
    /// drive. Captures registration + provider BEFORE the call and
    /// rechecks the registration AFTER return: if the provider was
    /// reentrantly replaced/removed/rebound mid-pull, the pulled value
    /// is stale and discarded (the replacement already cleared cached
    /// state). The provider is installed per source under a fresh
    /// registration, so the registration fence also covers source
    /// identity across rebinds.
    @MainActor private func pullStereoHostState(admitted identity: FrameIdentity) {
        let registration = stereoHostStateRegistration
        let geometryEpoch = admittedGeometryEpoch
        let provider = stereoHostStateProvider
        // PATH A (Ops 8:11:41): sample the physical context HERE, at
        // the pull instant, on this actor - never from a queued
        // callback. A nil context is delivered to the provider as-is:
        // missing-context nil admission is the CONSUMER's rule.
        let context = currentStereoLookPullContext(admitted: identity)
        let pulled = provider?(context)
        guard !closed, stereoHostStateRegistration == registration,
              admittedGeometryEpoch == geometryEpoch else { return }
        lastStereoHostInputCustody = pulled.map { (session: $0.session, source: $0.source, acceptanceEpoch: $0.acceptanceEpoch, sourceGeneration: $0.sourceGeneration, restrictedProjectionAdmission: $0.restrictedProjectionAdmission, withheldLanes: $0.withheldLanes, policyConstantLanes: $0.policyConstantLanes) }
        lastStereoDistanceTrace = pulled?.distanceTrace
        if let handler = stereoDistanceTraceHandler,
           let line = lastStereoDistanceTrace?.geomTraceLine(),
           line != lastEmittedDistanceTraceLine {
            // Dedup records ACTUAL delivery: the sink is non-nil here
            // (a nil sink swallows nothing and a later-attached sink
            // gets the line at the next pull), and the call is
            // synchronous and non-throwing, so recording immediately
            // before it is recording at delivery. Recording BEFORE the
            // call (not after) lets a re-entrant provider/handler
            // replacement inside the callback WIN: its own dedup reset
            // is not clobbered by this record.
            lastEmittedDistanceTraceLine = line
            handler(line)
            // The callback runs on this actor and may tear down, close
            // or replace the session/provider, so the full pull fence
            // is re-proven before the state install below: a pull
            // proven under superseded authority never reaches
            // setStereoHostState.
            guard !closed, stereoHostStateRegistration == registration,
                  admittedGeometryEpoch == geometryEpoch else { return }
        }
        setStereoHostState(pulled?.state)
    }
    /// PATH A (Ops 8:11:41): sample the ACTUAL attached view's
    /// backing geometry and display synchronously at the pull
    /// instant. NIL unless ALL hold: the view is attached to a
    /// window; the current backing size EQUALS the renderer's last
    /// ADMITTED drawable geometry (exact-frame correspondence; a
    /// layer assignment queued ahead of renderer admission is a
    /// mismatch, never a sample); the actual attached display
    /// identity resolved. Detached/mismatch/unresolved -> nil
    /// (absent/unimplemented source: NO fallback). A bound display
    /// with unavailable CGDisplay metrics yields a context with nil
    /// scale (bound-but-unavailable: the documented panel fallback
    /// applies at the consumer).
    @MainActor private func currentStereoLookPullContext(admitted frame: FrameIdentity) -> StereoLookPullContext? {
        guard let window = view.window, let screen = window.screen,
              let admitted = lastAdmittedDrawableGeometry else { return nil }
        // FULL frame/target/adoption correspondence (v14 review):
        // (a) the frame being driven was admitted under the SAME
        // surface revision as the cached admission - the pull path
        // NEVER advances the revision (no noteGeometryChange here);
        guard frame.surfaceRevision == admitted.revision else { return nil }
        // (b) that revision IS the renderer's CURRENT surface
        // revision: a geometry admission newer than the driven frame's
        // own makes this frame's geometry stale;
        guard renderer.currentSurfaceRevision == admitted.revision else { return nil }
        // (c) the window's current backing size equals the admitted
        // geometry;
        let size = windowContentPixelSize
        guard size.w > 0, size.h > 0,
              size.w == admitted.w, size.h == admitted.h else { return nil }
        // (d) the ACTUAL CAMetalLayer drawable size equals it too: a
        // layer target assigned ahead of or behind renderer admission
        // is a different target, never this frame's.
        let layerSize = drawablePixelSize
        guard layerSize.w == admitted.w, layerSize.h == admitted.h else { return nil }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = number.uint32Value
        return StereoLookPullContext(widthPx: size.w, heightPx: size.h,
                                     displayID: displayID,
                                     mmPerPx: Self.displayMMPerPx(displayID))
    }
    /// Display-BOUND mm/px: the Sensing VRDistance.mmPerPx formula
    /// (l.71-74) parameterized by the SAMPLED display instead of
    /// CGMainDisplayID; Sensing itself is untouched. nil = the
    /// display is bound but its metrics are unavailable.
    private static func displayMMPerPx(_ id: CGDirectDisplayID) -> Double? {
        let wmm = CGDisplayScreenSize(id).width
        guard wmm > 0, let px = CGDisplayCopyDisplayMode(id)?.pixelWidth, px > 0 else { return nil }
        return Double(wmm) / Double(px)
    }
    /// P31: the host signals a source change (new media bound to this
    /// presenter): the cached host state AND submission are cleared
    /// IMMEDIATELY (Ops nativefeed contract: never deferred to the
    /// next frame), then invalidate and resume with a fresh epoch.
    @MainActor public func stereoSourceChanged() {
        if stereoHostState != nil { setStereoHostState(nil) }
        // ...and drops the old provider outright (Ops nativefeed
        // contract): the new source's provider arrives through its own
        // install with a fresh registration; the old source's provider
        // can never serve a frame under the new source. The
        // registration itself stays monotone across the drop.
        stereoHostStateProvider = nil
        // Trace dedup is per-authority (see setStereoHostStateProvider).
        lastEmittedDistanceTraceLine = nil
        dropAdmittedDrawableGeometryCustody()
        stereoStageInvalidate(.sourceChange)
    }
    /// P31: stage rebind (host-driven): invalidate and resume fresh.
    @MainActor public func stereoStageRebind() { stereoStageInvalidate(.rebind) }

    /// P31: invalidate the installed stage for a cause and immediately
    /// resume with a FRESH installation epoch while the stage stays
    /// logically active - EXCEPT retire, which leaves it uninstalled.
    /// Invalidation clears the installation AND the remembered
    /// submission, so a payload from before the change can never bind.
    /// Every clear of the admitted-geometry custody ALSO bumps the
    /// admission epoch, so a geometry callback queued before the clear
    /// can never mint a fresh admission after it (v14 review: lawful
    /// reacquisition order - old callbacks vs adoption).
    @MainActor private func dropAdmittedDrawableGeometryCustody() {
        lastAdmittedDrawableGeometry = nil
        admittedGeometryEpoch &+= 1
    }

    @MainActor private func stereoStageInvalidate(_ cause: StereoLookStageInvalidation) {
        if cause == .retire { dropAdmittedDrawableGeometryCustody() }
        // P31: ANY stage invalidation revokes the renderer's projection
        // input synchronously; a re-installed stage re-registers on the
        // next admitted frame, never through the old binding.
        renderer.setStereoProjectionBinding(nil)
        guard let stage = stereoStage, stage.installedEpoch != nil else { return }
        stage.invalidate(cause)
        stereoCounters.recordInvalidation(cause)
        if cause != .retire { _ = stage.install() }
    }

    /// P31: drive the stage for one ADMITTED frame (identity already
    /// committed to the renderer through an accepted upload). Called
    /// BEFORE renderAndPresent - on the ticketed path inside the same
    /// commit section as the upload+present, so a stage payload can
    /// never straddle an admission. A closed publication gate clears
    /// the submission AND rebinds the stage (fresh epoch minted
    /// eagerly): while gated no payload exists to bind and pre-gate
    /// payloads stay epoch-refused; the next open-gate frame
    /// re-produces. Typed refusals are counted, never hidden.
    @MainActor private func driveStereoStage(admitted identity: FrameIdentity) {
        // Ops nativefeed contract: same-actor synchronous pull of the
        // installed provider on EVERY admitted frame, including nil,
        // BEFORE stage.frame - no Task/dispatch/notification queue.
        // pullStereoHostState's registration recheck discards a stale
        // result from a reentrant replace; the setter's identical-value
        // guard makes an unchanged pull a no-op; an actual change/loss
        // clears the submission through the authority-loss path before
        // this frame can bind under it. The admitted identity is
        // passed so the context sample is checked against THE EXACT
        // FRAME's admitted geometry revision (Ops 8:16:57).
        pullStereoHostState(admitted: identity)
        guard let stage = stereoStage, stage.installedEpoch != nil else { return }
        guard let host = stereoHostState else {
            stereoCounters.recordHostStateMissing()
            return
        }
        do {
            switch try stage.frame(identity, host: host) {
            case .produced: stereoCounters.recordProduced()
            case .unchanged: stereoCounters.recordUnchanged()
            case .gated: stereoCounters.recordGated()
            }
        } catch {
            stereoCounters.recordDriveRefusal()
        }
    }

    /// P31: build the renderer's projection binding input for one
    /// ADMITTED frame from the current staged block - the exact 508-byte
    /// wire payload, full identity, exact revision, the stage's
    /// installed epoch and the AUTHORITATIVE current-host toolsActive
    /// (fail-closed true when no host state) - or nil (stale / absent
    /// authority).
    @MainActor private var stereoProjectionFailureSinkInstalled = false
    /// P31: install the renderer-time projection failure sink once
    /// (producer checklist item 4). The renderer invokes it with NO
    /// renderer lock held; this hop re-enters the MainActor and the
    /// ordinary fenced/deduplicated emission path delivers the event.
    /// The app bridge onward stays synchronous - no Task hop, no poll.
    @MainActor private func ensureStereoProjectionFailureSinkInstalled() {
        guard !stereoProjectionFailureSinkInstalled else { return }
        stereoProjectionFailureSinkInstalled = true
        renderer.setStereoProjectionFailureSink { [weak self] reason, binding, generation in
            // The renderer fired this with NO renderer lock and NO
            // photonGraphLock held, carrying the IMMUTABLE failure-time
            // custody. The hop re-enters the MainActor; the event is
            // built from that captured origin ONLY and validated
            // against current state at delivery (Ops v6 defect 1).
            Task { @MainActor [weak self] in
                guard let self else { return }
                MetalPresenterTelemetry.stereoBindingRefusals += 1
                self.emitStereoProjectionFailure(reason: reason, binding: binding,
                                                 rendererAuthorityGeneration: generation)
            }
        }
    }

    /// P31: renderer-time projection failure event - built ENTIRELY
    /// from the immutable captured origin (the binding's own custody
    /// and the failure-time authority generation), NEVER reconstructed
    /// from current presenter state, then validated for currency at
    /// delivery, deduplicated per named key, and latched only after
    /// actual delivery.
    @MainActor private func emitStereoProjectionFailure(reason: String, binding: StereoProjectionBindingInput,
                                                        rendererAuthorityGeneration: UInt64) {
        let event = StereoProjectionRefusalEvent(
            reason: reason, identity: binding.identity, stageEpoch: binding.stageEpoch,
            hostSession: binding.hostSession, hostSource: binding.hostSource,
            hostAcceptanceEpoch: binding.hostAcceptanceEpoch,
            hostSourceGeneration: binding.hostSourceGeneration,
            hostStateRegistration: binding.hostStateRegistration,
            rendererAuthorityGeneration: rendererAuthorityGeneration)
        let key = StereoProjectionRefusalDedupKey(
            reason: reason, stageEpoch: binding.stageEpoch, hostSession: binding.hostSession,
            hostAcceptanceEpoch: binding.hostAcceptanceEpoch,
            hostSourceGeneration: binding.hostSourceGeneration,
            hostStateRegistration: binding.hostStateRegistration)
        guard key != lastStereoProjectionRefusalDedup else { return }
        guard let handler = stereoProjectionRefusalHandler,
              isCurrentStereoProjectionRefusal(event) else { return }
        handler(event)
        lastStereoProjectionRefusalDedup = key
    }

    @MainActor private func stereoProjectionBindingInput(admitted identity: FrameIdentity)
        -> StereoProjectionBindingInput? {
        ensureStereoProjectionFailureSinkInstalled()
        guard let bound = stereoStageBlock(admitted: identity),
              let epoch = stereoStage?.installedEpoch else { return nil }
        // Mechanical custody forwarding ONLY - every admission
        // decision (receipt presence, receipt scope match, SBS/TB
        // format agreement, enabled/tools/withheld, selector domain,
        // consumed-lane finiteness) is the renderer's typed-refusal
        // validation, so each failure class surfaces a typed reason.
        return StereoProjectionBindingInput(identity: identity,
                                            block: bound.block,
                                            revision: bound.revision,
                                            stageEpoch: epoch,
                                            toolsActive: stereoHostState?.session.toolsActive ?? true,
                                            sessionEnabled: stereoHostState?.session.enabled ?? false,
                                            admissionWithheldLanes: lastStereoHostInputCustody?.withheldLanes ?? ["no-current-host-input"],
                                            hostSession: lastStereoHostInputCustody?.session,
                                            hostSource: lastStereoHostInputCustody?.source,
                                            hostSourceGeneration: lastStereoHostInputCustody?.sourceGeneration,
                                            hostAcceptanceEpoch: lastStereoHostInputCustody?.acceptanceEpoch,
                                            hostStateRegistration: stereoHostStateRegistration,
                                            restrictedProjectionAdmission: lastStereoHostInputCustody?.restrictedProjectionAdmission)
    }

    /// P31: build + emit the renderer-time refusal event with FULL origin
    /// custody - full FrameIdentity, stage installed epoch, host session
    /// UUID / source / acceptance epoch, the provider install
    /// registration, and the renderer authority generation - so the host
    /// can reject QUEUED/stale refusal messages across same-session/
    /// same-path re-adoption and provider changes (a string, session
    /// UUID or path alone is NOT sufficient). Deduplicated per
    /// (reason, authority context) so a persistent refusal does not fire
    /// an OSD every frame; invoked on this actor AFTER all renderer
    /// locks are released, only while the SAME custody is still current.
    @MainActor private func emitStereoProjectionRefusal(_ reason: String, identity: FrameIdentity, stageEpoch: UInt64?) {
        let custody = lastStereoHostInputCustody
        let registration = stereoHostStateRegistration
        let event = StereoProjectionRefusalEvent(
            reason: reason, identity: identity, stageEpoch: stageEpoch,
            hostSession: custody?.session, hostSource: custody?.source,
            hostAcceptanceEpoch: custody?.acceptanceEpoch,
            hostSourceGeneration: custody?.sourceGeneration,
            hostStateRegistration: registration,
            rendererAuthorityGeneration: renderer.stereoAuthorityGeneration())
        let key = StereoProjectionRefusalDedupKey(
            reason: reason, stageEpoch: stageEpoch, hostSession: custody?.session,
            hostAcceptanceEpoch: custody?.acceptanceEpoch,
            hostSourceGeneration: custody?.sourceGeneration,
            hostStateRegistration: registration)
        guard key != lastStereoProjectionRefusalDedup else { return }
        // Fence FIRST, latch LAST (producer checklist item 5): the dedup
        // key is recorded only AFTER the currency check and the actual
        // handler delivery, so an undelivered stale event never
        // consumes the first valid notification for its context.
        guard let handler = stereoProjectionRefusalHandler,
              isCurrentStereoProjectionRefusal(event) else { return }
        handler(event)
        lastStereoProjectionRefusalDedup = key
    }

    /// P31 render seam: the current stage block for the ADMITTED frame,
    /// consumed through the adapter's typed stale-refusal (installed
    /// epoch + exact revision + full identity). Any staleness answers
    /// nil, never a substitute key. The encode-side consumption of the
    /// returned block is the renderer's StereoProjectionPass, registered
    /// through stereoProjectionBindingInput above.
    @MainActor public func stereoStageBlock(admitted identity: FrameIdentity)
        -> (block: LookParameterABI.Block, revision: ParameterBlockRevision)? {
        // Fenced by CURRENT valid authority (Z4C v11): with no host
        // state there is no authority to bind under, whatever a
        // retained submission might say.
        guard stereoHostState != nil, let stage = stereoStage else { return nil }
        if let bound = stage.block(admitted: identity) { return bound }
        stereoCounters.recordStaleQuery()
        return nil
    }

    @MainActor private func rerenderIfOpen() {
        guard !closed else { MetalPresenterTelemetry.staleWorkAfterClose += 1; return }
        guard let ml = view.metalLayer else { return }
        // Re-render the SELECTED frame's own lease+identity (r2 finding 3),
        // not an anonymous "current" pointer.
        view.needsLayout=true
        // P31: reacquire the projection authority for the RETAINED frame
        // under CURRENT stage state and geometry (port plan 5); a stale
        // or absent answer ACTIVELY revokes, so the re-render takes the
        // ordinary flat route and never reuses an old retained binding
        // solely because the video frame identity matches.
        if let retained = renderer.canonicalRetainedIdentity() {
            if case .refused(let reason) = renderer.setStereoProjectionBinding(stereoProjectionBindingInput(admitted: retained)) {
                // P31: never re-render under a refused authority.
                MetalPresenterTelemetry.stereoBindingRefusals += 1
                emitStereoProjectionRefusal(reason, identity: retained,
                                            stageEpoch: stereoStage?.installedEpoch)
                return
            }
        } else {
            renderer.setStereoProjectionBinding(nil)
        }
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
            if frame.ptsSeconds < lastPtsSeconds - 0.0005 {
                trackRevision &+= 1
                // P31: a track change invalidates the stage; resume fresh.
                stereoStageInvalidate(.streamChange)
            }
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
            // P31: admitted upload precedes render - drive the stage now.
            // Admission proof: lastIdentity is set to THIS identity only by
            // an accepted upload above (identity is freshly minted, so an
            // older success can never alias it).
            if lastIdentity == identity { driveStereoStage(admitted: identity) }
            guard let ml = view.metalLayer else { return true }
            // P31 render-seam authority: register THIS admitted frame's
            // staged block (immutable bytes + identity + revision + stage
            // epoch) as the projection pass input, or ACTIVELY revoke
            // when the stage answers nil (stale or absent authority) -
            // the present then takes the ordinary flat route, never a
            // stale projection.
            switch renderer.setStereoProjectionBinding(stereoProjectionBindingInput(admitted: identity)) {
            case .refused(let reason):
                // P31: a refused authority NEVER becomes a silent flat
                // present - stop THIS frame's present and surface the
                // typed refusal with full origin custody. The Store is
                // NOT mutated to Off.
                MetalPresenterTelemetry.stereoBindingRefusals += 1
                emitStereoProjectionRefusal(reason, identity: identity,
                                            stageEpoch: stereoStage?.installedEpoch)
                return true
            case .registered, .revoked:
                break
            }
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
            if frame.ptsSeconds < lastPtsSeconds - 0.0005 {
                trackRevision &+= 1
                // P31: a track change invalidates the stage; resume fresh.
                stereoStageInvalidate(.streamChange)
            }
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
                    // P31: admitted upload precedes render - drive the
                    // stage INSIDE the commit section so a payload can
                    // never straddle an admission. Admission proof:
                    // lastIdentity is set to THIS identity only by an
                    // accepted upload above (fresh identity, no aliasing).
                    if self.lastIdentity == identity {
                        self.driveStereoStage(admitted: identity)
                    }
                    if let ml = self.view.metalLayer {
                        // P31 render-seam authority (inside the commit
                        // section): register THIS admitted frame's staged
                        // block or actively revoke on nil; never a stale
                        // projection.
                        switch self.renderer.setStereoProjectionBinding(self.stereoProjectionBindingInput(admitted: identity)) {
                        case .refused(let reason):
                            // P31: refused authority NEVER falls through
                            // to a success-shaped flat present.
                            MetalPresenterTelemetry.stereoBindingRefusals += 1
                            self.emitStereoProjectionRefusal(reason, identity: identity,
                                                             stageEpoch: self.stereoStage?.installedEpoch)
                        case .registered, .revoked:
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
        // P31: a surface rebind invalidates the stage; resume fresh.
        stereoStageInvalidate(.surfaceChange)
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
        // P31: fenceClosed above retired the stage. The stage stays
        // logically bound to this presenter only while the host keeps it
        // installed (uninstall detaches the binding); resume it under
        // the new session with a fresh installation epoch.
        if let stage = stereoStage, stage.installedEpoch == nil { _ = stage.install() }
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
    public func setSourceCrop(_ crop:SourceCrop)->SourceCropOutcome {
        guard !closed else{return .refusedSealed}
        let result=renderer.setSourceCrop(crop,sessionID:sessionID,generation:sessionGeneration)
        if result == .applied {rerenderIfOpen()}
        return result
    }
    @MainActor @discardableResult
    public func setPhotonProducerEnabled(_ enabled:Bool,sharp:Bool=true,grain:Bool=true)->Bool {
        guard !closed else{return false}
        let accepted=renderer.setPhotonProducerEnabled(enabled,sharp:sharp,grain:grain)
        if accepted {rerenderIfOpen()}
        return accepted
    }
    @MainActor public func completedPhotonTelemetry()->PhotonPresentedTelemetry? {
        guard !closed else{return nil};return renderer.completedPhotonTelemetry()
    }
    @MainActor public func photonProducerFailure()->String? {renderer.photonProducerFailure()}
    /// P31 explicit propagated refusal: passthrough of the renderer's
    /// latched projection refusal (photonProducerFailure parity); the
    /// shell/host polling layer is Ops's integration.
    @MainActor public func stereoProjectionFailure()->String? {renderer.stereoProjectionFailure()}
    /// G3: frame size as presented, drawable size and the on-screen video rect (with the host transform).
    /// nil before the first frame or after close.
    @MainActor public func effectiveVideo() -> EffectiveVideoGeometry? {
        guard !closed, let f = renderer.lastFrameSize() else { return nil }
        let d = drawablePixelSize
        let crop=renderer.currentSourceCrop()
        return effectiveVideoGeometry(drawableW: d.w, drawableH: d.h, frameW: max(1,Int((Double(f.width)*crop.width).rounded())), frameH: max(1,Int((Double(f.height)*crop.height).rounded())),
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
