// ================================================================
//  GorAVEmbeddedSession.swift - r3 REAL INTERNALS (replaces the r2
//  candidate verbatim-adopted shell). gorav L7/L8 factory gap.
//  Against goreda/gorav @ 63093a8cbd67b4e81feee94bb03025f93b9052e8.
//
//  Session-shaped linkable API: open / pause / seek / volume / stop /
//  events / snapshot, video onto the host's NSView through the E1
//  embed variant of MetalPresenter (canonical seam per Main 00:53:
//  host supplies the player NSView; the presenter embeds its
//  layer-backed view and owns the layer lifecycle). Audio via
//  AudioUnitSink. Seek via the LANDED M4 orchestration
//  (ShellSeekBridge + shellPerformSeek + SeekOrchestration.
//  coordinateSeekAudio + BoundAudioPump) - the same composition the
//  trunk's runMuxedBody seek-probe path runs.
//
//  Trunk bindings below were verified against actual source at the
//  pin (binding table in the accompanying report), EXCEPT two that
//  land with the coordinator's r2/E1 composition and are NOT in the
//  pin: AudioUnitSink.setVolume (C3) and MetalPresenter(embedIn:) (E1).
//  Removed from r2: the fabricated .opened(nil,0,0) emission and the
//  nonexistent PlaybackIdentityAuthority.hasAvailableIdentity probe.
//
//  SINGLE-USE INSTANCE (Main 01:03): one session opens once. After
//  stop/failure/teardown the host DISCARDS the instance and creates a
//  new one (the gor-side factory does exactly this); there is no
//  reopen path on a used session.
//
//  ACTOR CONSISTENCY (review 00:54): every mutable property is
//  touched only on @MainActor. Pump/audio completion hops re-enter
//  via Task { @MainActor in }. No nonisolated async mutation.
//
//  REAL STATE (review 00:54): the coordinator's PlayerControlPlane
//  arbitrates every transition; lifecycleState and generation report
//  the plane, never a constant. PLANE VERSION NOTE: r2 in the e1r2
//  bundle has a seek-origin bug fixed in coordinator r3; the 12-XCTest
//  Linux venue is still PENDING (Main 00:58). This file uses only the
//  plane's public API (apply/allows/state/generation/seekAllowed); the
//  final composition MUST carry coordinator r3's plane, not r2.
//
//  E1 DEPENDENCY: the presenter construction is isolated in
//  makePresenter(); the exact E1 init label binds to the Metal
//  writer's landed variant. This file does not compile until E1
//  lands - honestly labeled, no pretend build.
//
//  MAC-GATED: compiles nowhere in current venues (Linux skips
//  canImport(AppKit) bodies). UNCOMPILED / UNRUN; no Mac claim.
//
//  PACKAGE NOTE (coordinator-owned): the r2 target dependency list
//  needs GorAVSeekComposition and GorAVNativeProbeKit added for the
//  BoundAudioPump / SeekOrchestration / RationalTime imports below.
// ================================================================
#if canImport(AppKit)
import AppKit
import Foundation
import Metal
import GorAVCore
import GorAVPlaybackCore
import GorAVSubtitles
import GorAVNativeProbeKit
import GorAVMacShell
import GorAVMetalPresenter
import GorAVFFmpegAdapter
import GorAVSeekComposition
import GorAVAudioClockSwift

/// Typed refusals. Everything outside the shell's proven envelope is a
/// refusal, never a silent fallback (matches trunk shell discipline).
public enum EmbeddedRefusal: Error, Equatable {
    case unsupportedSource(String)   // non-local-file
    case unsupportedCommand(String)  // setRate/selectTrack/screenshot/replace
    case seekUnavailable(String)     // no bridge/binding, or plane gate
    case identityExhausted           // PlaybackIdentityAuthority typed nil
    case pacingRefused               // attachPacing typed false
    case audioRefused                // AudioUnitSink bring-up refused
    case stopFlagRefused             // AtomicU64 cell refused
    case bridgeRefused               // ShellSeekBridge attach failed closed
    case alreadyOpen
    case notOpen
    case illegalState(String)        // PlayerControlPlane refusal, typed
}

/// Typed event stream for the embedder. Every case is emitted only
/// from an actual observed transition; nothing is fabricated.
/// Never carries URLs, paths with credentials, or loggable secrets
/// (PlayerBoundary rule).
public enum EmbeddedEvent: Sendable, Equatable {
    /// Both decoders opened (streams known). fileLoaded-equivalent:
    /// NOT firstVideoFrame, NOT playing (PlayerBoundary).
    case opened
    /// First presentation anchor observed on the pump (set at the
    /// first frame decision) - the honest first-presentation signal
    /// available to this venue.
    case firstFrame
    case paused
    case resumed
    case seekCommitted(seconds: Double)
    /// Terminal. reason is a typed token: eof / userStop / cancelled /
    /// windowClosed / teardown / audioClosedMuted / seekRequiresClose.
    case ended(reason: String)
    /// Typed failure token only - never a free-form path or URL.
    case failed(String)
    /// Audio opened but its seek descriptor/binding was unavailable:
    /// audio plays through the trunk's runPaced fallback, seek refuses
    /// typed. Emitted at open so the host never reads the session as a
    /// full A/V success (Main 00:58: no success stub while audio is
    /// absent or unbound).
    case audioUnbound
    case durationKnown(seconds: Double)
    case timePos(seconds: Double, generation: Int)
    case volumeChanged(Float)
}

/// Local producer receipt. ShellAudioPump.Outcome's memberwise
/// initializer is INTERNAL cross-module (XBPP r3 compile finding), so
/// the session's producer tasks carry this own type instead.
public struct EmbeddedProducerOutcome: Sendable, Equatable {
    public let pushed: Int
    public let terminal: ShellAudioPump.Terminal
    public init(pushed: Int, terminal: ShellAudioPump.Terminal) {
        self.pushed = pushed
        self.terminal = terminal
    }
}

/// What the session can actually source. Unknown stays nil - no
/// fabricated values (review 00:53).
public struct EmbeddedSnapshot: Sendable, Equatable {
    /// Read-only measured diagnostics. Sequence is local to this session.
    public var seekTrace: [String] = []
    /// native111: pause/resume toggle decisions, INCLUDING the silent
    /// idempotent-guard exits - native107 showed a resume toggle completing
    /// with zero trace, and without this ring a swallowed toggle is
    /// indistinguishable from a no-op. Text only; no behavior change.
    public var controlTrace: [String] = []
    public var audioFirstAdmissionWallSeconds: [Double] = []
    public var audioLandingFirstSampleSeconds: [Double] = []
    /// Pace-anchor media seconds (set at the first frame decision of
    /// the current presentation generation; reset on seek). This is
    /// the actual presentation anchor, not a sampled playhead; nil
    /// before the first frame.
    public var anchorMediaSeconds: Double?
    public var isPaused: Bool?
    /// nil: no honest duration source exists at the pin.
    public var timePositionSeconds: Double?
    /// G3: presented frame size, drawable size and on-screen video rect incl. the host transform.
    /// nil before the first presented frame.
    public var effectiveVideo: EffectiveVideoGeometry?
    public var durationSeconds: Double?
    /// Terminal pump counters from the actual PumpStats of the last
    /// finished pump run (EOS, cancel, failure or windowClosed).
    /// nil while no pump run has ended in this session - never a
    /// placeholder zero (XA9: previously documented but never set).
    public var shown: Int?
    public var dropped: Int?
    public var waits: Int?
    /// Real plane state + generation (never a constant).
    public var lifecycle: PlayerLifecycleState = .idle
    public var generation: UInt64 = 0
    /// native87 B-gate LIVE fields (additive; nil = honest absence, never a
    /// placeholder zero): accepted presentations - live from the running
    /// pump while open, the terminal PumpStats.shown once the pump ended.
    public var presentedFrames: Int?
    /// native96 instrumentation: pre-target frames discarded by the pump's
    /// seek-landing catch-up (PlaybackCore preSeekLanding), live from the
    /// running pump. nil once no pump is running - the terminal aggregate
    /// already carries all drops in dropped; no fabricated zero.
    public var seekLandingDrops: Int?
    /// native99 instrumentation: pts of the most recent seek-landing drop
    /// (PlaybackCore preSeekLanding), live from the running pump. nil while
    /// no drop has occurred in this presentation generation - honest
    /// absence, never a fabricated zero.
    public var seekLandingLastDropPTS: Double?
    /// native100 instrumentation (goreda T2 blind spot): landing shows
    /// refused while the landing was still pending, live from the running
    /// pump - total, commit tryAdmit-nil, and sink.show-false splits. nil
    /// while no pump is running - honest absence, never a fabricated zero.
    public var seekLandingFencedShows: Int?
    public var seekLandingFencedAdmitNil: Int?
    public var seekLandingFencedSinkFalse: Int?
    /// native100 instrumentation: most recent / maximum decoded pts seen by
    /// the pump while the landing was pending and the anchor nil (unbounded,
    /// includes fenced >=target arrivals). nil while none seen in this
    /// presentation generation - honest absence, never a fabricated zero.
    public var seekLandingLastDecodedPTS: Double?
    public var seekLandingMaxDecodedPTS: Double?
    /// native101: frames skipped by the decoder's post-seek preroll window
    /// (FFmpegSoftwareDecoder.seekPrerollSkipped) - source-side catch-up
    /// progress now that pre-target frames never reach the pump on this
    /// path. nil while no decoder exists - honest absence.
    public var seekPrerollSkipped: Int?
    /// Real AudioUnit render callbacks (every buffer render, all silence
    /// forms included). nil while no audio unit exists.
    public var audioCallbacks: UInt64?
    /// Intentional-pause silence frames rendered while quiesced (the real
    /// pause contract's own counter, AudioUnitSink.pausedSilenceFrames).
    public var audioIntentionalSilenceFrames: UInt64?
    /// Real ring content frames delivered to the unit (underrun shortfall
    /// excluded). nil while no audio unit exists.
    public var audioNonSilenceFrames: UInt64?
    /// Seeks committed this session. Pair with seekTrace and
    /// audioLandingFirstSampleSeconds for the landing witnesses.
    public var seekCommittedCount: UInt64 = 0
    /// The pump reached its typed endOfStream terminal reason. Never
    /// inferred from counters or playhead position.
    public var eofReached = false
    /// The pump's typed terminal reason (rawValue); nil while running.
    public var pumpEndReason: String?
    public init() {}
}

public struct NativeStereoEntryReceipt: Equatable, Sendable {
    public let originalMediaID: String
    public let playbackMediaID: String
    public let prepared: Bool
    public let evidence: NativeStereoEntryEvidence
    public init(originalMediaID: String, playbackMediaID: String, prepared: Bool,
                evidence: NativeStereoEntryEvidence) {
        self.originalMediaID=originalMediaID; self.playbackMediaID=playbackMediaID
        self.prepared=prepared; self.evidence=evidence
    }
}

@MainActor
public final class GorAVEmbeddedSession {

    public var onEvent: ((EmbeddedEvent) -> Void)?

    // MARK: Host + identity

    /// Host-owned player view (canonical E1 seam; supersedes the r2
    /// caller-CAMetalLayer shape). The session never creates an NSWindow.
    private let hostView: NSView
    private let runID: String
    /// Host explicitly registers the preparation implementation. No implicit
    /// browser/player fallback. Linux process backend is not Darwin support.
    public typealias SourcePreparer = @Sendable (String, String?, SourcePreparationCancellation) async throws -> PreparedLocalMedia
    private let sourcePreparer: SourcePreparer?
    private var sourcePreparationCancellation: SourcePreparationCancellation?
    private var preparingSource = false
    private var preparedMedia: PreparedLocalMedia?

    // MARK: Real state (PlayerControlPlane, coordinator r2)

    private var plane = PlayerControlPlane()
    /// Pause state captured at seek entry so it survives the seek
    /// (review: preserve paused state across seek).
    private var wasPausedAtSeek = false

    // MARK: Trunk legs (all MainActor-confined)

    private var session: SessionID?
    private var commit: CancelCommit?
    private var clock: ShellClock?
    private var audio: AudioUnitSink?
    private var decoder: FFmpegSoftwareDecoder?
    private var adec: FFmpegSoftwareAudioDecoder?
    private var openedPath: String?
    // R6 (arch-195l): audio track/delay state. The delay applies live
    // (pacing read-side offset) and is re-applied at every open; the track
    // selector applies live via setAudioTrack and at open for .index.
    private var audioDelaySeconds = 0.0
    private var audioTrackSelector: AudioTrackSelector = .auto
    private var openedSourceDescriptor: SourceDescriptor?
    private var openedRootPin: String?
    private var audioSwitchCorrelation: UInt64 = 0
    // G4 (arch-195l, dispatch L6): mpv-style observation surface. Publish
    // points: open (duration/metadata/media-title/eof/idle/hwdec), pause
    // toggles, time-pos (through the existing gated publishTime), eof at
    // endOfStream. width/height/video-params/fps/frame-drop-count are NOT
    // wired yet - their data lives behind decoder/presenter counters that
    // need a Mac compile to verify; recorded in STATUS as the open seam.
    public let observations = ObservationStore()
    private var preparedShot: PreparedShot?
    private var preparedReceipt: PreparedShotCommitReceipt?
    private var preparedOperation = false
    private var preparedAdoption = PreparedAdoption()
    private var source: ShellFrameSource?
    /// P27 (arch-195g G3): newest retained decoded frame for
    /// screenshot/readback consumers. Session- and seek-fence-checked by
    /// the source; nil when no tap is wired (e.g. ungrounded timebase at
    /// open) or the newest frame is stale. Consumers must still treat
    /// TappedFrame.seekGeneration as the frame's admitted seek identity.
    public func latestTappedFrame() -> TappedFrame? { source?.latestTappedFrame() }
    /// P27: FIFO consume of retained decoded frames for analysis consumers
    /// (crop detection, live depth, brightness reads, depth preparation).
    /// Same session/fence checks as latestTappedFrame().
    public func consumeTappedFrame() -> TappedFrame? { source?.consumeTappedFrame() }
    private var pump: FramePump?
    private var presenter: MetalPresenter?
    // P31-STEREO-LOOK session glue (lane: stereo/photon; RESERVED shared
    // caller files, Ops-confirmed): this session is the ONE place the
    // concrete decoder (B6 metadata drain), the source (frame path) and
    // the presenter (stage seam) meet. The qualified v7 transport is
    // owned here per live source; events apply only through the
    // identity/selection fence in installStereoGlue.
    private var stereoTransport: StereoStreamMetadataTransport?
    /// Typed host-state input seam, PULL MODEL (Ops nativefeed
    /// contract): the presenter pulls this provider synchronously on
    /// its own actor on EVERY admitted frame (nil included) before
    /// stage.frame, passing its own live PATH A sample of the actual
    /// attached view (StereoLookPullContext; nil = detached, geometry
    /// mismatch with the renderer's admitted geometry, or unresolved
    /// display - the provider must vend nil, an absent source never
    /// falls back). Assignment is ATOMIC: direct assignment is
    /// impossible (private(set)); install/remove below immediately
    /// propagate to the live presenter under a fresh registration,
    /// clearing cached state+submission NOW, never next frame. The
    /// ACTUAL stereo look/VR owner snapshot does not exist at this
    /// layer yet; until a real provider is installed AND yields a
    /// snapshot, the pull yields nil and NO host state is applied -
    /// never invented from dimensions or session defaults. The stage
    /// then stays installed-but-unsubmitted (presenter counts
    /// hostStateMissing): that is UNAVAILABLE, not integrated.
    /// Presentation epochs are never minted or derived here; stage-
    /// install epochs are owned by the stage adapter alone.
    public private(set) var stereoHostStateProvider: (@MainActor (StereoLookPullContext?) -> StereoLookHostInput?)?
    /// Monotone provider-registration fence handed to the presenter on
    /// every provider install/replacement (Ops nativefeed contract);
    /// session-owned, never derived from frame or stage state.
    private var stereoHostStateProviderRegistration: UInt64 = 0

    /// Current-source renderer refusal delivery. Synchronous on MainActor;
    /// no polling or Task hop can retarget an old event to a newer source.
    public var stereoProjectionRefusalHandler: ((StereoProjectionRefusalEvent) -> Void)?

    /// full182: forwards the presenter's deduped vrDistance geom-trace
    /// line to the app's installed sink. Same fencing as the refusal
    /// bridge; nil sink = nothing emitted.
    public var stereoDistanceTraceHandler: ((String) -> Void)?

    private func installStereoProjectionRefusalBridge(source: ShellFrameSource,
                                                       presenter: MetalPresenter) {
        presenter.stereoProjectionRefusalHandler = { [weak self, weak source, weak presenter] event in
            guard let self, let source, let presenter,
                  !self.tornDown, !self.fenced,
                  self.source === source, self.presenter === presenter,
                  presenter.isCurrentStereoProjectionRefusal(event),
                  event.hostStateRegistration == self.stereoHostStateProviderRegistration,
                  let custody = presenter.lastStereoHostInputCustody,
                  event.hostSession == custody.session,
                  event.hostSource == custody.source,
                  event.hostSourceGeneration == custody.sourceGeneration,
                  event.hostAcceptanceEpoch == custody.acceptanceEpoch else { return }
            self.stereoProjectionRefusalHandler?(event)
        }
        presenter.stereoDistanceTraceHandler = { [weak self, weak source, weak presenter] line in
            guard let self, let source, let presenter,
                  !self.tornDown, !self.fenced,
                  self.source === source, self.presenter === presenter
            else { return }
            self.stereoDistanceTraceHandler?(line)
        }
    }

    /// P31: install/replace the host-state provider ATOMICALLY (Ops
    /// nativefeed contract): the assignment and the presenter hand-off
    /// are one synchronous step, so a live presenter clears its cached
    /// state+submission at the moment of replacement, not next frame.
    public func installStereoHostStateProvider(_ provider: @escaping @MainActor (StereoLookPullContext?) -> StereoLookHostInput?) {
        stereoHostStateProvider = provider
        propagateStereoHostStateProvider()
    }
    /// P31: remove the provider atomically (same immediate-clear
    /// semantics as install).
    public func removeStereoHostStateProvider() {
        stereoHostStateProvider = nil
        propagateStereoHostStateProvider()
    }
    /// P31: hand the CURRENT provider to the live presenter under a
    /// FRESH monotone registration (the presenter's source/rebind
    /// fence). No-op while no live presenter exists.
    private func propagateStereoHostStateProvider() {
        guard let presenter else { return }
        stereoHostStateProviderRegistration &+= 1
        presenter.setStereoHostStateProvider(stereoHostStateProvider, registration: stereoHostStateProviderRegistration)
    }
    /// Glue outcome counters (applied/refused events, decoder-reported
    /// queue folds): diagnostics, never hidden.
    public private(set) var stereoGlueAppliedEvents: UInt64 = 0
    public private(set) var stereoGlueRefusedEvents: UInt64 = 0
    public private(set) var stereoGlueDroppedEvents: UInt64 = 0
    private var bridge: ShellSeekBridge?
    private var audioStopFlag: AtomicU64?
    private var audioBinding: AudioSourceBinding?
    private var audioCorrelation: UInt64?
    private var audioTask: Task<EmbeddedProducerOutcome, Never>?
    private var pumpTask: Task<PumpStats, Never>?
    /// Terminal counters of the last finished pump run; reset when a
    /// new run starts so a stale generation never leaks forward.
    private var terminalPumpStats: (shown: Int, dropped: Int, waits: Int)?
    /// native102: last teardown's leg timings + drain result, copied into
    /// the close report by close(). Set by tearDownInternal/cleanupLegs on
    /// EVERY teardown path (close, stop, pump-ended teardown).
    private var legTaskAwaitMs: Double?
    private var legPresenterDecoderCloseMs: Double?
    private var legAudioDrainMs: Double?
    private var legAudioStopMs: Double?
    private var lastDrainStartBytes: Int?
    private var lastDrainRemainingBytes: Int?
    private var lastDrainCancelled: Bool?
    private var terminalEndReason: PumpEndReason?
    private var tracker = PlayheadTracker()
    private var timeGate = TimePosGate(maxPerSecond: 4)
    private var volumeGate = VolumeChangeGate()
    private var durationSeconds: Double?
    private var timeTask: Task<Void, Never>?
    private var subtitleTask: Task<Void, Never>?
    private var subtitleSidecars: SubtitleSidecarSession?
    /// GORAV-SUBTITLE-TYPOGRAPHY: session-only user scale for the cue
    /// presenter (same session-only rule as embedded delays).
    private var subtitleFontScale = SubtitleTypography.defaultScale
    private var subtitlePosition = 100.0
    private var subtitleLoadTask: Task<Void, Never>?

    /// Plaintext track input and sidecar selection share the source-bound owner.
    @discardableResult public func setTextSubtitles(_ controller: SubtitleController) -> Bool {
        subtitleSidecars?.setController(controller) ?? false
    }
    public var subtitleCandidates: [SubtitleAutoLoad.Candidate] { subtitleSidecars?.candidates ?? [] }
    public func selectSubtitle(path: String, slot: SubtitleController.Slot) async -> SubtitleSidecarSelection {
        guard let sidecars = subtitleSidecars else { return .refused(.closed) }
        return await sidecars.select(path: path, slot: slot)
    }
    @discardableResult public func setSubtitleDelay(_ seconds: Double, slot: SubtitleController.Slot) -> SubtitleSidecarRefusal? {
        guard let sidecars = subtitleSidecars else { return .closed }
        return sidecars.setDelay(seconds, slot: slot)
    }
    /// Returns false when no subtitle owner is open, so a caller never announces a change that did not happen.
    @discardableResult public func setSubtitleVisible(_ visible: Bool, slot: SubtitleController.Slot) -> Bool {
        guard let sidecars = subtitleSidecars else { return false }
        sidecars.setVisible(visible, slot: slot); return true
    }
    public func resetSubtitles() { subtitleSidecars?.reset() }
    /// GORAV-SUBTITLE-TYPOGRAPHY: apply the user subtitle scale on the real
    /// cue presenter. Typed refusal when torn down, fenced, or out of range;
    /// the accepted value is session-only and re-applied to a presenter
    /// created after the call. Position is separately bounded by the measured
    /// cue surface; tilt/animation are not added here.
    public func setSubtitleFontScale(_ scale: Double) -> EmbeddedRefusal? {
        guard !tornDown, !fenced else { return .illegalState("tornDownOrFenced") }
        guard let accepted = SubtitleTypography.adjustedScale(current: scale, delta: 0, reset: false), accepted == scale else {
            return .unsupportedCommand("subtitle font scale out of range")
        }
        subtitleFontScale = accepted
        presenter?.setSubtitleFontScale(accepted)
        return nil
    }
    @discardableResult public func setSubtitlePosition(_ percent:Double)->EmbeddedRefusal? {
        guard !tornDown,!fenced,let presenter else{return .unsupportedCommand("subtitle presenter not open")}
        guard presenter.setSubtitlePosition(percent) else{return .unsupportedCommand("subtitle position or measured layout unavailable")}
        subtitlePosition=percent
        return nil
    }
    private func clearSubtitleGeneration() { subtitleSidecars?.seekBegan() }
    private func publishSubtitleCues() {
        guard !tornDown, !fenced, let session, let sidecars = subtitleSidecars,
              plane.state == .playing || plane.state == .paused,
              let filmTime = tracker.read(clockNow: trackerClockNow(), durationSeconds: durationSeconds) else { return }
        sidecars.sample(session: session.epoch, generation: sidecars.generation, filmTime: filmTime)
    }
    private func replaceSubtitleSource(path: String) {
        subtitleLoadTask?.cancel()
        guard let sidecars = subtitleSidecars else { return }
        guard sidecars.replaceSource(path: path) == nil else { return }
        subtitleLoadTask = Task { [weak self] in
            let outcome = await sidecars.loadExactPrimary()
            guard !Task.isCancelled, let self, self.subtitleSidecars === sidecars else { return }
            if case .refused(let refusal) = outcome, refusal != .staleCompletion {
                self.onEvent?(.failed("subtitleSidecar:\(refusal)"))
            }
        }
    }
    private func closeSubtitleDelivery() {
        subtitleTask?.cancel(); subtitleTask = nil
        subtitleLoadTask?.cancel(); subtitleLoadTask = nil
        subtitleSidecars?.close()
    }
    private func startSubtitleObserver() {
        subtitleTask?.cancel()
        subtitleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.tornDown, !self.fenced else { return }
                self.publishSubtitleCues()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    private func trackerClockNow() -> Double { clock?.nowSeconds() ?? .nan }
    private var firstFrameTask: Task<Void, Never>?
    private var seekCounter: UInt64 = 0
    private var diagnosticSequence: UInt64 = 0
    private var seekTrace: [String] = []
    /// native111: backing ring for traceControl. 483bb683d added the
    /// snapshot field, the emitter and the readers but not this
    /// declaration (native compile 369/1364). Capped in traceControl.
    private var controlTrace: [String] = []
    private var landingBoxes: [AudioLandingBox] = []
    private func traceSeek(_ token: String) {
        diagnosticSequence += 1
        // native96 instrumentation (local overlay vs upstream 2112af0d):
        // stamp each token with the master clock so a parked-seek wait can
        // order seekVideoCommitted / frame0Presented / audioProducerRearmed
        // against the landing. Text only; no behavior change.
        seekTrace.append("seq=\(diagnosticSequence) t=\(String(format: "%.3f", trackerClockNow())) \(token)")
    }
    private func traceControl(_ token: String) {
        diagnosticSequence += 1
        // native111 instrumentation (local overlay vs upstream 2112af0d):
        // same stamp discipline as traceSeek; capped so a spammed pause key
        // cannot grow the ring without bound. Text only; no behavior change.
        controlTrace.append("seq=\(diagnosticSequence) t=\(String(format: "%.3f", trackerClockNow())) \(token)")
        if controlTrace.count > 64 { controlTrace.removeFirst(controlTrace.count - 64) }
    }
    private var tornDown = false
    /// Synchronous admission fence (set by fence()); an in-flight open
    /// checks it after every await and fails instead of reporting
    /// success on a superseded session (XBPP P1-2).
    private var fenced = false

    /// Public, read-only, REAL state (review 00:54: no always-idle lie).
    public var lifecycleState: PlayerLifecycleState { plane.state }
    public var generation: UInt64 { plane.generation }

    public init(hostView: NSView, runID: String, sourcePreparer: SourcePreparer? = nil) {
        self.hostView = hostView
        self.runID = runID
        self.sourcePreparer = sourcePreparer
    }

    /// Cheap availability probe for the L8 switch's isAvailable path:
    /// feature presence ONLY. Opens no decoder, no audio unit, no
    /// window, consumes no identity (review: instantiate/discard must
    /// not pay future cost; hasAvailableIdentity does not exist at the
    /// pin and was removed). Identity exhaustion, pacing attach and
    /// audio bring-up refuse typed inside open().
    /// ACTUAL check (XBPP integration; was a constant-true stub, never
    /// acceptable): the one hard runtime dependency of every session
    /// is a Metal device for the presenter (E1 MetalPresenter init
    /// throws without one). Probing it here makes the switch's refusal
    /// honest on a machine where the opt-in can never work; every
    /// other failure mode refuses typed at open time, not here.
    public static func probeAvailable() -> Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    // MARK: - E1 seam (Metal writer owns)

    /// The ONE call site that depends on the landed E1 embed variant:
    /// host-NSView embedding, presenter owns the layer lifecycle.
    /// Canonical choice per Main 00:53; exact label per landed E1.
    private func makePresenter(commit: CancelCommit) throws -> MetalPresenter {
        // Landed E1 r2 signature (verified against e1r2-full-e0f7e7f4.patch):
        // @MainActor init(embedIn hostView: NSView, contract: .sdrDefault,
        // outputTransform: .identity, commit: CancelCommit? = nil) throws.
        // Never creates an NSWindow, never falls back to one; close() leaves
        // the host view hierarchy alone.
        try MetalPresenter(embedIn: hostView, commit: commit)
    }

    /// Synchronous admission fence (L8 rollback handshake): cancel the
    /// commit authority and set the audio stop flag NOW - no new frame
    /// or audio admission after return. The async drain continues in
    /// tearDown(); the callback alone is not the barrier, THIS is.
    /// MainActor-only, non-blocking, safe before/after open.
    public func fence() {
        fenced = true
        stereoProjectionRefusalHandler = nil
        presenter?.stereoProjectionRefusalHandler = nil
        stereoDistanceTraceHandler = nil
        presenter?.stereoDistanceTraceHandler = nil
        closeSubtitleDelivery()
        commit?.requestCancel()
        audioStopFlag?.store(1)
    }

    // MARK: - Open (mirrors runMuxedBody's proven sequence)

    public func open(path: String) async throws {
        guard !preparingSource else { throw EmbeddedRefusal.alreadyOpen }
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.state == .idle, session == nil else { throw EmbeddedRefusal.alreadyOpen }
        guard FileManager.default.fileExists(atPath: path), !path.contains("://") else {
            throw EmbeddedRefusal.unsupportedSource("v0 admits local files only")
        }
        applyOrReport(.beginLoad)
        do {
            // S4 identity order: issued BEFORE audio.start; the audio leg
            // SHARES the one identity (no second mint).
            guard let issued = PlaybackIdentityAuthority.shared.issue() else {
                throw EmbeddedRefusal.identityExhausted
            }
            session = issued
            let clock = ShellClock()
            self.clock = clock
            guard let audio = AudioUnitSink() else { throw EmbeddedRefusal.audioRefused }
            self.audio = audio
            audio.ledgerSession = issued.epoch
            guard audio.attachPacing(hostClock: { clock.rawWallSeconds() }) else {
                throw EmbeddedRefusal.pacingRefused
            }
            clock.attachAudioMaster(audio.pacingClock)
            try audio.start()
            // R6: re-apply the persisted user delay on the fresh pacing policy.
            if audioDelaySeconds != 0 { audio.pacingPolicy?.setDelay(seconds: audioDelaySeconds) }
            try throwIfSuperseded()
            let root = (path as NSString).deletingLastPathComponent
            let decoder = FFmpegSoftwareDecoder()
            let adec = FFmpegSoftwareAudioDecoder()
            try decoder.pinLocalRoots([root])
            try adec.pinLocalRoots([root])
            try await decoder.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: issued)
            try throwIfSuperseded()
            let audioPreferred: Int32?
            if case let .index(i) = audioTrackSelector { audioPreferred = Int32(i) } else { audioPreferred = nil }
            try await adec.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: issued,
                                preferredAudioStreamIndex: audioPreferred)
            try throwIfSuperseded()
            openedSourceDescriptor = SourceDescriptor(id: path, kind: .local, seekable: true)
            openedRootPin = root
            self.decoder = decoder
            self.adec = adec
            durationSeconds = containerDurationSeconds(ticks: decoder.containerDurationTicks(session: issued))
            if let durationSeconds { onEvent?(.durationKnown(seconds: durationSeconds)) }
            publishOpenObservations(titleFallback: (path as NSString).lastPathComponent, issued: issued)
            // One shared cancel/commit authority governs pump admissions
            // and the presenter upload fence (r3 S5).
            let commit = CancelCommit(sessionEpoch: issued.epoch)
            self.commit = commit
            let presenter = try makePresenter(commit: commit)   // E1 seam
            self.presenter = presenter
            presenter.bindSubtitleSession(issued.epoch)
            presenter.setSubtitleFontScale(subtitleFontScale)
            _ = presenter.setSubtitlePosition(subtitlePosition)
            subtitleSidecars = SubtitleSidecarSession(session: issued.epoch) { [weak presenter] batch in
                presenter?.consumeSubtitleCues(batch)
            }
            replaceSubtitleSource(path: path)
            // P27 (arch-195g G3): ground ptsSeconds in the REAL descriptor
            // streamTimebase (same rule as the prepared-replacement path
            // below), not the legacy hardcoded 12800 default. The tap is
            // wired ONLY when the timebase is grounded: with the legacy
            // default the source still plays, but nothing is tapped with
            // provisional timestamps (Delivery r3).
            let source: ShellFrameSource
            if let binding = decoder.currentBinding(),
               let descriptor = try? decoder.descriptor(for: binding.token),
               let tb = descriptor.streamTimebase, tb.value > 0 {
                source = ShellFrameSource(decoder: decoder, session: issued,
                                          timeBaseDen: Double(tb.timescale) / Double(tb.value))
                // P27: one session-owned retained-CVPixelBuffer tap per
                // playback session, created through the owner API and held
                // for the session's lifetime (closed by ShellFrameSource's
                // deinit).
                source.frameTap = FrameTap.makeForSession(session: issued.epoch)
            } else {
                source = ShellFrameSource(decoder: decoder, session: issued)
            }
            source.shouldStop = { @MainActor [weak self] in
                guard let self else { return true }
                return self.commit?.isCancelled ?? true
            }
            self.source = source
            let pump = FramePump(source: source, sink: presenter, clock: clock,
                                 ledger: nil, ledgerSession: issued.epoch, ledgerGeneration: 1,
                                 commit: commit,
                                 closeRequested: nil) { seconds in
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return true }
                catch { return false }
            }
            self.pump = pump
            installStereoGlue(source: source, presenter: presenter)
            // Bound pulls FROM THE BEGINNING - a legacy pull would claim
            // legacy mode and refuse every later seek (peer 73d2ea6c).
            guard let flag = AtomicU64(0) else { throw EmbeddedRefusal.stopFlagRefused }
            audioStopFlag = flag
            let landingBox = AudioLandingBox()
            landingBoxes.append(landingBox)
            if let d = await adec.seekDescriptor(session: issued), d.seekable, d.referenceOrigin != nil {
                audioBinding = d.binding
            } // else: binding stays nil; seek refuses typed (descriptor-unavailable)
            let bridge = ShellSeekBridge()
            guard bridge.attach(to: decoder) else { throw EmbeddedRefusal.bridgeRefused }
            source.seekBridge = bridge
            self.bridge = bridge
            startAudioProducer(landingBox: landingBox)
            try throwIfSuperseded()
            applyOrReport(.loadReady)
            applyOrReport(.play)
            startPump()
            startFirstFrameWatch()
            startTimeObserver()
            startSubtitleObserver()
            openedPath = path
            onEvent?(.opened)
            if audioBinding == nil {
                // Honest degradation, NOT a success stub: audio plays
                // unbound (runPaced, trunk fallback); seek refuses typed.
                onEvent?(.audioUnbound)
            }
        } catch {
            // Structured cleanup of the partial open, then typed failure.
            await cleanupLegs()
            _ = plane.apply(.loadFailed)
            onEvent?(.failed(typedToken(error)))
            throw error
        }
    }

    // MARK: - R6 (arch-195l, dispatch L6): audio track selection + audio delay
    // UNCOMPILED on Linux (Darwin target; no Mac here): reviewed source, not
    // measured behavior. The policy, values and pacing offset ARE
    // Linux-tested (audio-delay-tests A1-A27).

    /// mpv audio-delay semantics: positive = audio later; REPLACES the value,
    /// never accumulates. Live through the pacing read-side offset (no audio
    /// re-anchor, no clock discontinuity beyond the requested shift) and
    /// persisted for later opens on this session object.
    public func setAudioDelay(seconds: Double) throws {
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard AudioDelay(seconds) != nil else {
            throw EmbeddedRefusal.unsupportedCommand("audioDelay out of range")
        }
        audioDelaySeconds = seconds
        audio?.pacingPolicy?.setDelay(seconds: seconds)
    }

    // BEGIN chapter-navigation API (real-source portable extraction boundary)
    /// Snapshot of the opened VIDEO context only. No URL reopen or second probe.
    /// Prepared-video handoffs have a different film timeline and remain refused.
    /// Source facts, not camera authorization. Prepared and original media keep
    /// distinct identities. The active decoder supplies selected uncropped facts.
    public func nativeStereoEntryEvidence(expected: ActiveMediaInventoryIdentity? = nil)
        -> NativeStereoEntryReceipt? {
        guard !tornDown, !fenced, !preparedOperation,
              let decoder, let issued=session, let original=openedPath,
              let evidence=decoder.nativeStereoEntryEvidence(session: issued, expected: expected)
        else { return nil }
        return NativeStereoEntryReceipt(originalMediaID: original,
            playbackMediaID: preparedShot?.video.id ?? original,
            prepared: preparedShot != nil, evidence: evidence)
    }

    public func nativeStereoEntryIsCurrent(_ receipt: NativeStereoEntryReceipt) -> Bool {
        nativeStereoEntryEvidence(expected: receipt.evidence.identity) == receipt
    }

    public func chapterInventory() throws -> ActiveMediaInventorySnapshot {
        guard !tornDown, !fenced, !preparedOperation, preparedShot == nil,
              plane.seekAllowed, let decoder, let issued = session else {
            throw EmbeddedRefusal.seekUnavailable("chapter: session unavailable")
        }
        guard let snapshot = decoder.activeMediaInventory(session: issued) else {
            throw EmbeddedRefusal.seekUnavailable("chapter: inventory unavailable")
        }
        return snapshot
    }

    /// Uses a caller's inventory receipt, never an unfenced chapter index.
    /// There is no suspension between identity validation and entering real seek.
    /// Return means video seek committed, not a new full A/V readiness claim.
    @discardableResult
    public func navigateChapter(_ direction: ChapterDirection,
                                expected: ActiveMediaInventoryIdentity) async throws -> Double {
        let inventory = try chapterInventory()
        guard inventory.identity == expected, let issued = session, let openedDecoder = decoder else {
            throw EmbeddedRefusal.seekUnavailable("chapter: retired inventory")
        }
        let entries = inventory.inventory.chapters.map {
            ChapterNavigationEntry(index: $0.index, startSeconds: $0.startSeconds, endSeconds: $0.endSeconds)
        }
        let entry = try ChapterNavigation.target(entries: entries,
            position: tracker.read(clockNow: trackerClockNow(), durationSeconds: durationSeconds), direction: direction)
        let before = seekCounter
        try await seek(toSeconds: entry.startSeconds)
        // Existing seek may return after a requires-close outcome. Do not turn
        // that, teardown, replacement or a superseding seek into chapter success.
        guard !tornDown, !fenced, session == issued, decoder === openedDecoder,
              seekCounter == before &+ 1, plane.state == .playing || plane.state == .paused else {
            throw EmbeddedRefusal.seekUnavailable("chapter: seek not committed or retired")
        }
        return entry.startSeconds
    }
    // END chapter-navigation API

    /// Audio tracks of the opened container (container stream indices) and the stream currently playing.
    /// Read-only; nil when nothing is open or the inventory is unavailable.
    public func audioTrackInventory() async -> (tracks: [AudioTrackInfo], activeIndex: Int?)? {
        guard !tornDown, !fenced, let adec, let issued = session,
              let snapshot = await adec.activeMediaInventory(session: issued) else { return nil }
        var tracks: [AudioTrackInfo] = []
        for t in snapshot.inventory.tracks where t.kind == .audio {
            if let info = AudioTrackInfo(index: max(0, t.index), language: t.language,
                                         title: t.title, isDefault: t.isDefault) { tracks.append(info) }
        }
        let active = await adec.seekDescriptor(session: issued).map { Int($0.audioStreamIndex) }
        return (tracks, active)
    }

    /// Live audio track switch. The selector is validated against the OPENED
    /// container's own inventory (typed refusal, never a silent fallback);
    /// the audio leg is reopened on the chosen stream, re-anchored at the
    /// current position through the existing seek machinery, and the old leg
    /// is closed after the new one is open. Known limit (recorded in
    /// STATUS): the producer restart means a brief audio gap at the switch;
    /// the video leg is untouched.
    public func setAudioTrack(_ selector: AudioTrackSelector) async throws {
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard let oldAdec = adec, let issued = session, let descriptor = openedSourceDescriptor else {
            throw EmbeddedRefusal.notOpen
        }
        guard let audio, let flag = audioStopFlag else {
            throw EmbeddedRefusal.illegalState("audioTrack: audio sink unavailable")
        }
        guard let snapshot = await oldAdec.activeMediaInventory(session: issued) else {
            throw EmbeddedRefusal.unsupportedCommand("audioTrack: inventory unavailable")
        }
        // Snapshot tracks carry container indices (track.index); clamp
        // unlabelled entries at index 0 so a pathological container cannot
        // make the requested stream silently bind a different one.
        var audioTracks: [AudioTrackInfo] = []
        audioTracks.reserveCapacity(snapshot.inventory.tracks.count)
        for t in snapshot.inventory.tracks where t.kind == .audio {
            // AudioTrackInfo.init is failable (index < 0 only). The clamp
            // makes nil unreachable, but skip defensively: never append an
            // optional. R6 repair (195n): the direct append of the failable
            // init result failed Darwin typecheck.
            if let info = AudioTrackInfo(index: max(0, t.index), language: t.language,
                                         title: t.title, isDefault: t.isDefault) {
                audioTracks.append(info)
            }
        }
        let choice: AudioTrackInfo
        switch AudioTrackPlan.select(selector, from: audioTracks) {
        case .success(let t): choice = t
        case .failure(let r): throw EmbeddedRefusal.unsupportedCommand("audioTrack: \(r.description)")
        }
        if let d = await oldAdec.seekDescriptor(session: issued),
           d.audioStreamIndex == Int32(choice.index) {
            audioTrackSelector = selector
            return  // already on the requested stream
        }
        let position = tracker.read(clockNow: trackerClockNow(), durationSeconds: durationSeconds)
        let fresh = FFmpegSoftwareAudioDecoder()
        if let root = openedRootPin { try fresh.pinLocalRoots([root]) }
        try await fresh.open(source: descriptor, session: issued,
                             preferredAudioStreamIndex: Int32(choice.index))
        // Re-anchor the fresh leg at the current position BEFORE the swap,
        // through the same native seek path a user seek takes. R6 repair
        // (195n: the result was silently discarded): an attempted seek that
        // fails REFUSES the switch typed and the old leg keeps playing;
        // a source with no seekable position switches unanchored from the
        // fresh leg's start.
        audioSwitchCorrelation &+= 1
        if let position, let d = await fresh.seekDescriptor(session: issued), d.seekable,
           let target = try? RationalTime(value: Int64((position * 1_000_000).rounded()),
                                          timescale: 1_000_000) {
            switch await fresh.seek(binding: d.binding, videoRelativeTarget: target,
                                    correlation: audioSwitchCorrelation) {
            case .nativeReady:
                break
            case .closeRequired(_, _, let nativeCode):
                await fresh.close(session: issued)
                throw EmbeddedRefusal.unsupportedCommand("audioTrack: re-anchor seek closeRequired(\(nativeCode))")
            case .refused(let r):
                await fresh.close(session: issued)
                throw EmbeddedRefusal.unsupportedCommand("audioTrack: re-anchor seek refused: \(r)")
            }
        }
        // Stop + JOIN the old producer and reset the ring through the same
        // quiescence protocol a user seek takes, in the same order
        // (join -> ring reset -> decoder close -> re-arm). R6 repair (195n:
        // the swap started the replacement without stopping/joining the old
        // producer or resetting queued old PCM, and closed the old decoder
        // under a still-running pump).
        let producerGeneration = audio.currentGeneration
        flag.store(1)
        _ = await audioTask?.value            // old producer quiesced: JOINED
        audio.markProducerJoined(generation: producerGeneration)
        guard let resetFence = audio.resetRingForSeek() else {
            // nil has two shapes (AudioUnitSink.resetRingForSeek): EARLY
            // nils (inactive lifecycle, missing unit, AudioOutputUnitStop
            // failure) mutate nothing; LATE nils (session stopping
            // mid-reset, AudioOutputUnitStart failure) return AFTER the
            // fence advanced and the ring was reset, with the unit left
            // stopped. Either way the old producer is joined and a clean
            // switch is impossible: close both legs and refuse typed.
            // Teardown owns the stopped unit on the late shape.
            flag.store(0)
            await oldAdec.close(session: issued)
            await fresh.close(session: issued)
            self.adec = nil
            audioBinding = nil
            throw EmbeddedRefusal.unsupportedCommand("audioTrack: ringResetRefused")
        }
        await oldAdec.close(session: issued)
        self.adec = fresh
        audioBinding = nil
        if let d = await fresh.seekDescriptor(session: issued), d.seekable, d.referenceOrigin != nil {
            audioBinding = d.binding
        }
        guard audio.resumeProducerAfterJoin(expectedSessionGeneration: producerGeneration,
                                            expectedFenceGeneration: resetFence) else {
            // Witness mismatch: the session is stopping or the fence moved
            // under us. No producer is running; close the fresh leg, leave
            // audio muted typed.
            flag.store(0)
            await fresh.close(session: issued)
            self.adec = nil
            audioBinding = nil
            throw EmbeddedRefusal.illegalState("audioTrack: producer re-arm refused")
        }
        flag.store(0)
        let landingBox = AudioLandingBox()
        landingBoxes.append(landingBox)
        startAudioProducer(landingBox: landingBox)
        audioTrackSelector = selector
    }

    // MARK: - R3 (arch-195l, dispatch L6): open(url:) for transfer.it / mega / torrent
    // UNCOMPILED on Linux (this target is Darwin-only; no Mac here): reviewed
    // source mirroring open(path:)'s proven sequence, not measured behavior.
    // Classification lives in GorAVCore.OpenURLRouter (Linux-tested). Resolver
    // kinds refuse typed until their bridge/resolver produces an admitted
    // http(s) URL; direct remotes (transfer.it, generic http(s)) open here.

    public func open(url: String, selectedFilename: String? = nil) async throws {
        guard !preparingSource else { throw EmbeddedRefusal.alreadyOpen }
        switch OpenURLRouter.route(url) {
        case .directRemote(let id, let seekable):
            try await openRemote(id: id, seekable: seekable)
        case .needsTransferResolver, .needsMegaResolver:
            try await openPreparedSource(url: url, selectedFilename: selectedFilename)
        case .needsWebTorrentBridge:
            throw EmbeddedRefusal.unsupportedSource("torrent/magnet: the wt_server bridge must produce an admitted http(s) URL first (R3)")
        case .refused(let reason):
            throw EmbeddedRefusal.unsupportedSource("open(url:) refused: \(reason.rawValue)")
        }
    }

    /// Preparation is fenced before any local decoder opens. The cache lease
    /// survives until cleanupLegs has closed every decoder and audio handle.
    private func openPreparedSource(url: String, selectedFilename: String?) async throws {
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.state == .idle, session == nil, !preparingSource else { throw EmbeddedRefusal.alreadyOpen }
        guard let sourcePreparer else { throw EmbeddedRefusal.unsupportedSource("sourcePreparerNotRegistered") }
        let cancellation = SourcePreparationCancellation()
        sourcePreparationCancellation = cancellation
        preparingSource = true
        defer { preparingSource = false; sourcePreparationCancellation = nil }
        let media: PreparedLocalMedia
        do {
            media = try await withTaskCancellationHandler(operation: {
                try await sourcePreparer(url, selectedFilename, cancellation)
            }, onCancel: { cancellation.cancel() })
        } catch {
            // Never forward an external exception or URL/key to the UI.
            throw EmbeddedRefusal.unsupportedSource("sourcePreparationRefused")
        }
        guard !tornDown, !fenced, !Task.isCancelled, plane.state == .idle, session == nil else {
            do { try media.release() } catch { onEvent?(.failed("sourceCacheCleanupFailed")) }
            throw EmbeddedRefusal.illegalState("preparedSourceStale")
        }
        preparedMedia = media
        preparingSource = false
        do { try await open(path: media.path) }
        catch {
            // open(path:) owns partial decoder cleanup before throwing.
            do { try media.release(); preparedMedia = nil } catch { onEvent?(.failed("sourceCacheCleanupFailed")) }
            throw error
        }
    }

    /// Remote twin of open(path:): same proven sequence, remote differences
    /// only - no filesystem existence guard, no local root pins, no local
    /// subtitle sidecars, descriptor kind .remote.
    private func openRemote(id: String, seekable: Bool) async throws {
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.state == .idle, session == nil else { throw EmbeddedRefusal.alreadyOpen }
        applyOrReport(.beginLoad)
        do {
            guard let issued = PlaybackIdentityAuthority.shared.issue() else {
                throw EmbeddedRefusal.identityExhausted
            }
            session = issued
            let clock = ShellClock()
            self.clock = clock
            guard let audio = AudioUnitSink() else { throw EmbeddedRefusal.audioRefused }
            self.audio = audio
            audio.ledgerSession = issued.epoch
            guard audio.attachPacing(hostClock: { clock.rawWallSeconds() }) else {
                throw EmbeddedRefusal.pacingRefused
            }
            clock.attachAudioMaster(audio.pacingClock)
            try audio.start()
            // R6: re-apply the persisted user delay on the fresh pacing policy.
            if audioDelaySeconds != 0 { audio.pacingPolicy?.setDelay(seconds: audioDelaySeconds) }
            try throwIfSuperseded()
            let descriptor = SourceDescriptor(id: id, kind: .remote, seekable: seekable)
            let decoder = FFmpegSoftwareDecoder()
            let adec = FFmpegSoftwareAudioDecoder()
            try await decoder.open(source: descriptor, session: issued)
            try throwIfSuperseded()
            let remoteAudioPreferred: Int32?
            if case let .index(i) = audioTrackSelector { remoteAudioPreferred = Int32(i) } else { remoteAudioPreferred = nil }
            try await adec.open(source: descriptor, session: issued,
                                preferredAudioStreamIndex: remoteAudioPreferred)
            try throwIfSuperseded()
            openedSourceDescriptor = descriptor
            openedRootPin = nil
            self.decoder = decoder
            self.adec = adec
            durationSeconds = containerDurationSeconds(ticks: decoder.containerDurationTicks(session: issued))
            if let durationSeconds { onEvent?(.durationKnown(seconds: durationSeconds)) }
            publishOpenObservations(titleFallback: (id as NSString).lastPathComponent, issued: issued)
            let commit = CancelCommit(sessionEpoch: issued.epoch)
            self.commit = commit
            let presenter = try makePresenter(commit: commit)
            self.presenter = presenter
            presenter.bindSubtitleSession(issued.epoch)
            presenter.setSubtitleFontScale(subtitleFontScale)
            _ = presenter.setSubtitlePosition(subtitlePosition)
            subtitleSidecars = SubtitleSidecarSession(session: issued.epoch) { [weak presenter] batch in
                presenter?.consumeSubtitleCues(batch)
            }
            // No replaceSubtitleSource: a remote source has no filesystem
            // sidecars. External subtitle add-on remains its own command.
            let source: ShellFrameSource
            if let binding = decoder.currentBinding(),
               let descriptor = try? decoder.descriptor(for: binding.token),
               let tb = descriptor.streamTimebase, tb.value > 0 {
                source = ShellFrameSource(decoder: decoder, session: issued,
                                          timeBaseDen: Double(tb.timescale) / Double(tb.value))
                source.frameTap = FrameTap.makeForSession(session: issued.epoch)
            } else {
                source = ShellFrameSource(decoder: decoder, session: issued)
            }
            source.shouldStop = { @MainActor [weak self] in
                guard let self else { return true }
                return self.commit?.isCancelled ?? true
            }
            self.source = source
            let pump = FramePump(source: source, sink: presenter, clock: clock,
                                 ledger: nil, ledgerSession: issued.epoch, ledgerGeneration: 1,
                                 commit: commit,
                                 closeRequested: nil) { seconds in
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return true }
                catch { return false }
            }
            self.pump = pump
            installStereoGlue(source: source, presenter: presenter)
            guard let flag = AtomicU64(0) else { throw EmbeddedRefusal.stopFlagRefused }
            audioStopFlag = flag
            let landingBox = AudioLandingBox()
            landingBoxes.append(landingBox)
            if let d = await adec.seekDescriptor(session: issued), d.seekable, d.referenceOrigin != nil {
                audioBinding = d.binding
            }
            let bridge = ShellSeekBridge()
            guard bridge.attach(to: decoder) else { throw EmbeddedRefusal.bridgeRefused }
            source.seekBridge = bridge
            self.bridge = bridge
            startAudioProducer(landingBox: landingBox)
            try throwIfSuperseded()
            applyOrReport(.loadReady)
            applyOrReport(.play)
            startPump()
            startFirstFrameWatch()
            startTimeObserver()
            startSubtitleObserver()
            openedPath = id
            onEvent?(.opened)
            if audioBinding == nil {
                onEvent?(.audioUnbound)
            }
        } catch {
            await cleanupLegs()
            _ = plane.apply(.loadFailed)
            onEvent?(.failed(typedToken(error)))
            throw error
        }
    }

    // MARK: - Pause / resume (pump owns the actual state; plane arbitrates)

    public func setPaused(_ paused: Bool) async throws {
        guard !preparedOperation else { throw EmbeddedRefusal.illegalState("prepared handoff pending") }
        guard let pump else { throw EmbeddedRefusal.notOpen }
        if paused {
            // native111: the idempotent exits are traced (native107's
            // zero-trace toggles); the return itself stays silent.
            guard plane.state == .playing else {
                traceControl("pauseIgnored state=\(plane.state.rawValue)")
                return
            }   // idempotent
            // native92 (J3 quiesce wiring, local overlay vs upstream 2112af0d;
            // ShellFrameSource macro pause precedent): quiesce the sink BEFORE
            // any state moves, so a typed refusal leaves the session fully
            // playing - pause is atomic, never a frozen picture over an
            // un-quiesced sink. The quiesce holds the ring residual (no
            // post-pause audible tail), counts intentional pause silence on
            // its own counter, and keeps underrun accounting from accruing
            // across the hold (native91 B1.silence-advances FAIL without it).
            // pauseAudio's typed false (not active / pacing unattached /
            // already quiesced) and a nil sink while playing are both
            // incoherent for this leg: refuse typed, degrade nothing.
            guard let audio, audio.pauseAudio() else {
                // native111: trace the refused quiesce BEFORE the typed
                // throw (which half failed + sink/pacing witnesses), so a
                // venue run never again has to infer a silent refusal.
                traceControl("pauseAudioRefused state=\(plane.state.rawValue) sink=\(audio == nil ? "nil" : "typedFalse") sinkPaused=\(audio?.audioPaused == true) pacingPauses=\(audio?.pacingCounters?.pauseTransitions ?? 0) anchorRefusals=\(audio?.pacingCounters?.anchorRefusals ?? 0)")
                throw EmbeddedRefusal.illegalState("pauseAudioQuiesceRefused")
            }
            applyOrReport(.pause)
            await pump.pause()
            tracker.pause(clockNow: trackerClockNow())
            observations.publish(.pause, .bool(true))
            publishTime()
            onEvent?(.paused)
        } else {
            guard plane.state == .paused else {
                traceControl("resumeIgnored state=\(plane.state.rawValue)")
                return
            }    // idempotent
            // Symmetric and atomic with the pause leg: un-quiesce (re-anchor
            // a NEW clock generation on the device-consumed counter frozen
            // over the pause, silence receipt folded) BEFORE the pump resumes
            // and PCM production restarts. A typed refusal leaves the session
            // fully paused rather than playing video over a quiesced sink.
            guard let audio, audio.resumeAudio() else {
                // native111: same refusal trace, symmetric with the pause leg.
                traceControl("resumeAudioRefused state=\(plane.state.rawValue) sink=\(audio == nil ? "nil" : "typedFalse") sinkPaused=\(audio?.audioPaused == true) pacingResumes=\(audio?.pacingCounters?.resumeTransitions ?? 0) anchorRefusals=\(audio?.pacingCounters?.anchorRefusals ?? 0)")
                throw EmbeddedRefusal.illegalState("resumeAudioQuiesceRefused")
            }
            applyOrReport(.resume)
            await pump.resume()
            tracker.resume(clockNow: trackerClockNow())
            observations.publish(.pause, .bool(false))
            onEvent?(.resumed)
        }
    }

    public func togglePause() async throws {
        traceControl("toggle state=\(plane.state.rawValue)")
        switch plane.state {
        case .playing: try await setPaused(true)
        case .paused: try await setPaused(false)
        default: throw EmbeddedRefusal.illegalState("togglePause from \(plane.state.rawValue)")
        }
    }

    // MARK: - Volume (coordinator C3 trunk hook; typed refusal, never a no-op)

    /// Explicit candidate activation. Unsupported command routing remains separate.
    public func setPhotonProducerEnabled(_ enabled:Bool,sharp:Bool=true,grain:Bool=true)->Bool {
        guard !tornDown,!fenced,let presenter else{return false}
        return presenter.setPhotonProducerEnabled(enabled,sharp:sharp,grain:grain)
    }
    public func completedPhotonTelemetry()->PhotonPresentedTelemetry? {
        guard !tornDown,!fenced else{return nil};return presenter?.completedPhotonTelemetry()
    }
    public func photonProducerFailure()->String? {presenter?.photonProducerFailure()}

    @discardableResult
    public func setSourceCrop(x:Double,y:Double,width:Double,height:Double)->SourceCropOutcome {
        guard !tornDown,!fenced else{return .refusedSealed}
        guard let presenter else{return .refusedNotOpen}
        guard let crop=SourceCrop(x:x,y:y,width:width,height:height) else{return .refusedInvalid}
        return presenter.setSourceCrop(crop)
    }

    // MARK: - Host transform (G3 live pan/zoom; reaches the renderer quad every frame, no shader compile)

    /// panX/panY are fractions of the drawable (+x right, +y up), log2Zoom is 0 at aspect-fit (see HostTransform).
    /// Typed outcome: .refusedInvalid for non-finite or out of range, .refusedNotOpen before open or after
    /// teardown, .refusedSealed when fenced or the renderer is sealed. Never clamps, never a silent no-op.
    @discardableResult
    public func setHostTransform(panX: Double, panY: Double, log2Zoom: Double) -> HostTransformOutcome {
        guard !tornDown, !fenced else { return .refusedSealed }
        guard let presenter else { return .refusedNotOpen }
        guard let t = HostTransform(panX: panX, panY: panY, log2Zoom: log2Zoom) else { return .refusedInvalid }
        return presenter.setHostTransform(t)
    }

    @discardableResult
    public func setVolume(_ value: Float) -> Bool {
        switch plane.state {
        case .ready, .playing, .paused, .seeking:
            guard value.isFinite, audio?.setVolume(value) == true else { return false }
            if let changed = volumeGate.offer(value) { onEvent?(.volumeChanged(changed)) }
            return true
        default:
            return false
        }
    }

    // MARK: - Seek (LANDED M4 orchestration; producer stop+join enforced)

    public func seek(toSeconds seconds: Double) async throws {
        guard !preparedOperation, preparedShot == nil else {
            throw EmbeddedRefusal.seekUnavailable("prepared shot owns video timeline")
        }
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.seekAllowed else {
            throw EmbeddedRefusal.seekUnavailable("plane state \(plane.state.rawValue)")
        }
        guard let pump, let commit, let decoder, let adec, let audio,
              let issued = session, let bridge, let flag = audioStopFlag else {
            throw EmbeddedRefusal.notOpen
        }
        guard let binding = audioBinding else {
            // Legacy-stale honesty: post-seek audio would continue from its
            // own position; refuse typed instead of folding into an A/V claim.
            throw EmbeddedRefusal.seekUnavailable("descriptor-unavailable:audio-legacy-stale")
        }
        guard seconds >= 0, seconds.isFinite,
              let pos = try? RationalTime(value: Int64(seconds * 1000), timescale: 1000) else {
            throw EmbeddedRefusal.seekUnavailable("invalidTarget")
        }
        wasPausedAtSeek = plane.state == .paused
        traceSeek("seekBegin")
        clearSubtitleGeneration()
        applyOrReport(.beginSeek)
        seekCounter &+= 1
        let correlation = seekCounter
        var videoOutcome: ShellSeekWiringOutcome = .noChange
        let landingBox = AudioLandingBox()
        landingBoxes.append(landingBox)
        let producerGeneration = audio.currentGeneration
        let audioOutcome = await SeekOrchestration.coordinateSeekAudio(
            audioBinding: binding,
            audioCorrelation: audioCorrelation,
            videoSeek: { [weak self] in
                guard let self else { return false }
                let o = await shellPerformSeek(bridge: bridge, provider: decoder, pump: pump,
                                               position: pos, ledger: nil,
                                               ledgerSession: issued.epoch, ledgerGeneration: 1,
                                               seekLandingTarget: seconds)
                videoOutcome = o
                guard case .committedAndReset = o else { return false }
                self.tracker.seekCommitted(anchor: nil, clockNow: self.trackerClockNow(), wasPaused: self.wasPausedAtSeek)
                self.firstFrameTask?.cancel()
                self.traceSeek("seekVideoCommitted")
                return true
            },
            firstFrameAnchor: { [weak self] in
                guard let self else { return nil }
                let wall = ContinuousClock()
                // 10s bounds keyframe-distance decode catch-up at serial software-decode rates.
                let deadline = wall.now.advanced(by: .seconds(10))
                while wall.now < deadline {
                    if let anchor = await pump.currentPaceAnchor {
                        self.traceSeek("frame0Presented media=\(anchor.mediaSeconds)")
                        return anchor
                    }
                    if self.tornDown || Task.isCancelled { return nil }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                self.onEvent?(.failed("seekFrame0Timeout"))
                return nil
            },
            decoder: adec, session: issued, sink: audio,
            target: pos, targetSeconds: seconds, correlation: correlation,
            parkedVideo: wasPausedAtSeek,
            stopAndJoinProducer: { [weak self] in
                guard let self else { return }
                flag.store(1)
                _ = await self.audioTask?.value        // producer quiescence: JOINED
                audio.markProducerJoined(generation: producerGeneration)
            },
            resumeProducer: { [weak self] b, c, anchor, expectedFence in
                guard let self else { return false }
                guard audio.resumeProducerAfterJoin(
                    expectedSessionGeneration: producerGeneration,
                    expectedFenceGeneration: expectedFence) else { return false }
                self.audioBinding = b
                self.audioCorrelation = c
                flag.store(0)
                self.startAudioProducer(landingBox: landingBox, binding: b,
                                        correlation: c, sharedAnchor: anchor)
                self.traceSeek("audioProducerRearmed")
                return true
            },
            closeAudio: { await adec.close(session: issued) },
            onAudioRingReset: { [weak self] in self?.traceSeek("audioRingReset") },
            onAudioSeekDone: { [weak self] outcome in
                let label: String
                switch outcome {
                case .nativeReady: label = "nativeReady"
                case .closeRequired: label = "closeRequired"
                case .refused: label = "refused"
                }
                self?.traceSeek("audioSeekDone outcome=\(label)")
            })
        // Trunk failure discipline: anything but a clean commit or a
        // pre-mutation video refusal prohibits resume / closes legs.
        if audioOutcome != .nativeReady && audioOutcome != .videoRefusedResumed {
            await pump.prohibitResumeAfterSeekFailure()
        }
        switch videoOutcome {
        case .committedAndReset:
            // Paused state survives the seek (review requirement): the pump
            // never clears `paused` in resetPresentation; re-assert guarded
            // so a drifted state can never silently unpause.
            if wasPausedAtSeek, await !pump.isPaused { await pump.pause() }
            _ = plane.apply(.seekCommitted)
            if wasPausedAtSeek { _ = plane.apply(.pause) }
            if audioOutcome == .nativeReady {
                traceSeek("seekCommitted")
                onEvent?(.seekCommitted(seconds: seconds))
                if let anchor = await pump.currentPaceAnchor?.mediaSeconds {
                    acceptFirstFrame(anchor: anchor, generation: tracker.generation)
                } else if wasPausedAtSeek {
                    // native95 (local overlay vs upstream 2112af0d): parked
                    // seek - the RULES.md:69 render-order gate is vacuous
                    // while paused (SeekComposition parkedVideo), so frame0
                    // presents only after resume. The contract there states
                    // "the resume path's first-frame watch delivers
                    // acceptFirstFrame there", but the open-path watch
                    // (:483/:751) was cancelled at seek commit and the resume
                    // leg never re-arms one, so .firstFrame would never fire
                    // for the post-seek generation. Re-arm for the generation
                    // the commit just bumped: the watch polls the pace anchor
                    // and acceptFirstFrame's generation guard plus
                    // tracker.firstFrame's one-per-generation keep emission
                    // single, so this cannot double-signal a non-parked seek.
                    startFirstFrameWatch()
                }
            } else {
                // Audio muted/closed typed; A/V claim is narrowed honestly.
                traceSeek("seekCommitted")
                onEvent?(.seekCommitted(seconds: seconds))
                onEvent?(.failed("audioSeek:\(audioOutcome.rawValue)"))
            }
        case .noChange:
            _ = plane.apply(.seekRefused)
            if wasPausedAtSeek { _ = plane.apply(.pause) }
            throw EmbeddedRefusal.seekUnavailable("refused:no mutation")
        case .committedButPumpRefused:
            _ = plane.apply(.seekRequiresClose)
            await closeLegsAfterSeekFailure(videoOnly: true)
            onEvent?(.failed("seekCommittedButPumpRefused"))
        case .requiresClose:
            _ = plane.apply(.seekRequiresClose)
            await closeLegsAfterSeekFailure(videoOnly: false)
            onEvent?(.failed("seekRequiresClose"))
        }
    }

    // MARK: - Stop / teardown (exactly-once; trunk cleanup order)

    public func stop() async { await tearDownInternal(reason: "userStop") }

    /// Exactly-once teardown, matching the L8 rollback contract
    /// (PlaybackBackendControlling.tearDownForRollback calls here).
    public func tearDown() async { await tearDownInternal(reason: "teardown") }

    /// native87 B-gate (B3): measured close with a full counter snapshot.
    /// Counters are captured at close-REQUEST time (the honest pre-drain
    /// state; the teardown drain may render further callbacks). Close from
    /// any state is legal (plane close is legal from every non-terminal
    /// state); a second close is a typed no-op report, never a hang.
    @discardableResult
    /// P31: install the stereo glue for a NEW live source+presenter
    /// pair (BOTH construction paths: local open and remote open). A
    /// FRESH transport per live source; the drain handler applies only
    /// while this exact source is the session's live selection; the
    /// presenter's stage is installed (idempotent) and host state is
    /// pushed ONLY when the typed provider actually yields a snapshot.
    private func installStereoGlue(source: ShellFrameSource, presenter: MetalPresenter) {
        let transport = StereoStreamMetadataTransport()
        stereoTransport = transport
        source.stereoEventsHandler = { [weak self, weak source] events, dropped in
            guard let self, let source else { return }
            // Identity + selection fence: a superseded or prepared-but-
            // unadopted source's events are refused whole.
            guard self.source === source else { return }
            self.stereoGlueDroppedEvents &+= dropped
            self.applyStereoMetadataEvents(events, to: transport)
        }
        installStereoProjectionRefusalBridge(source: source, presenter: presenter)
        presenter.installStereoStage()
        // Pull-model hand-off (Ops nativefeed contract): install the
        // CURRENT provider under a fresh registration. The presenter
        // immediately cleared any prior cached state+submission inside
        // the install, and pulls the provider synchronously on every
        // admitted frame (nil included). A nil provider installs as
        // UNAVAILABLE - a prior source's host state is never silently
        // reused under a new source's authority. Nothing is
        // synthesized as a default.
        propagateStereoHostStateProvider()
    }

    /// P31: provider-REPLACEMENT refresh (Ops nativefeed contract):
    /// the owner calls this after replacing its provider; the
    /// re-install under a fresh registration immediately clears cached
    /// state+submission, and the next admitted frame pulls the CURRENT
    /// provider (nil included). Per-frame freshness comes from the
    /// presenter's own pull, not from this call. No-op while no live
    /// presenter exists.
    public func refreshStereoHostState() {
        propagateStereoHostStateProvider()
    }

    /// P31: same-presenter source change (prepared adoption): re-point
    /// the glue at the adopted source and signal the source change to
    /// the presenter (invalidate + fresh stage epoch; the forward-PTS
    /// case no heuristic could see). The fresh transport starts unbound;
    /// the new decoder's open-commit track event rebinds it.
    /// Notified synchronously on the main actor when a source is
    /// ADOPTED (prepared-shot commit) with the adopted source's path,
    /// after the stereo glue rebind. The embedding host uses it to
    /// reset its native input authority: accepted lanes of the old
    /// source must not survive adoption (Ops v4 finding).
    public var onStereoSourceAdopted: (@MainActor (String) -> Void)?

    private func rebindStereoGlue(source: ShellFrameSource, presenter: MetalPresenter,
                                  adoptedPath: String) {
        presenter.stereoSourceChanged()
        // Provider installation below drops old geometry custody first,
        // then requests current geometry at the new authority epoch.
        installStereoGlue(source: source, presenter: presenter)
        onStereoSourceAdopted?(adoptedPath)
    }

    /// P31: apply drained events to the qualified v7 transport, in
    /// drain order, through its typed context-bound admission. Track
    /// metadata rebinds (full atomic replace); codec-SEI events apply
    /// per field (no current producer - the codec tier is suppressed
    /// pending genuine bitstream proof). Typed refusals are counted,
    /// never hidden.
    private func applyStereoMetadataEvents(_ events: [StereoMetadataEvent],
                                           to transport: StereoStreamMetadataTransport) {
        for event in events {
            do {
                switch event.payload {
                case .trackMetadata(let metadata):
                    try transport.rebindSource(to: event.context, track: metadata)
                case .codecSEI(let field, let observation):
                    try transport.applyCodecSEI(context: event.context, field: field,
                                                observation: observation)
                }
                stereoGlueAppliedEvents &+= 1
            } catch {
                stereoGlueRefusedEvents &+= 1
            }
        }
    }

    public func close() async -> EmbeddedCloseReport {
        var report = EmbeddedCloseReport()
        guard !tornDown else {
            report.reason = "alreadyClosed"
            report.cleanShutdown = plane.state == .closed
            return report
        }
        let pre = await snapshot()
        report.audioRingBytesAtRequest = audio?.available   // native102: pre-drain ring depth
        let t0 = ContinuousClock.now
        await tearDownInternal(reason: "close")
        let elapsed = ContinuousClock.now - t0
        report.reason = "close"
        // native102: surface the measured legs + drain result (the drain
        // tuple was previously discarded without observation).
        report.audioDrainStartBytes = lastDrainStartBytes
        report.audioDrainRemainingBytes = lastDrainRemainingBytes
        report.audioDrainCancelled = lastDrainCancelled
        report.taskAwaitMs = legTaskAwaitMs
        report.presenterDecoderCloseMs = legPresenterDecoderCloseMs
        report.audioDrainMs = legAudioDrainMs
        report.audioStopMs = legAudioStopMs
        report.closeMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        report.presentedFrames = pre.presentedFrames
        report.audioCallbacks = pre.audioCallbacks
        report.audioIntentionalSilenceFrames = pre.audioIntentionalSilenceFrames
        report.audioNonSilenceFrames = pre.audioNonSilenceFrames
        report.eofReached = pre.eofReached
        report.cleanShutdown = plane.state == .closed
        return report
    }

    private func tearDownInternal(reason: String) async {
        guard !tornDown else { return }
        tornDown = true
        stereoProjectionRefusalHandler = nil
        presenter?.stereoProjectionRefusalHandler = nil
        sourcePreparationCancellation?.cancel()
        closeSubtitleDelivery()
        if plane.state != .closing { _ = plane.apply(.close) }
        firstFrameTask?.cancel()
        commit?.requestCancel()
        audioStopFlag?.store(1)
        let tTasks = ContinuousClock.now   // native102 leg timing
        _ = await audioTask?.value            // bounded: shouldStop observes the flag
        _ = await pumpTask?.value             // bounded: commit cancel + shouldStop
        legTaskAwaitMs = Self.ms(since: tTasks)
        await cleanupLegs()
        _ = plane.apply(.closed)
        onEvent?(.ended(reason: reason))
    }

    /// native102: ContinuousClock elapsed-ms helper for the leg timings.
    private static func ms(since t: ContinuousClock.Instant) -> Double {
        let e = ContinuousClock.now - t
        return Double(e.components.seconds) * 1000 + Double(e.components.attoseconds) / 1e15
    }

    /// The shared leg-cleanup sequence (trunk order): presenter quiescence
    //  BEFORE decoder/audio teardown; stop only what started, close what
    //  opened; audio unit always drained + stopped when it started.
    private func cleanupLegs() async {
        closeSubtitleDelivery()
        subtitleSidecars = nil
        timeTask?.cancel(); timeTask = nil
        firstFrameTask?.cancel(); firstFrameTask = nil
        let tLegs = ContinuousClock.now   // native102 leg timing
        if let presenter {
            // E1a819 (Metal writer's landed shape, detach isolation
            // proof PENDING at XBPP - NOT independently verified here):
            // close() detaches the presenter-owned embedded view INSIDE
            // close, after renderer quiescence; window mode and the
            // host view hierarchy are unaffected. The factory serializes
            // teardown before any new open, so if close() performs as
            // described the view-stack concern (P1-2) is covered.
            _ = await presenter.close()
        }
        presenter = nil
        if let adec, let issued = session { await adec.close(session: issued) }
        adec = nil
        if let decoder, let issued = session { _ = await decoder.closeAndReport(session: issued) }
        decoder = nil
        legPresenterDecoderCloseMs = Self.ms(since: tLegs)
        if let audio {
            let tDrain = ContinuousClock.now   // native102 leg timing
            lastDrainStartBytes = audio.available
            // native102 (goreda T2): the drain result is OBSERVED, never
            // discarded. A close from the PAUSED state holds the ring
            // quiesced (AudioUnitSink renders bounded-zero silence without
            // consuming it), so remaining stays > 0 for the full bound.
            // native103 (product fix, embedded close path only): when the
            // pump's pause witness says PAUSED at teardown, the quiesced
            // ring can NEVER drain - drop the residual without the wait
            // (bound 0.0; the residual stays explicit in the native102
            // drain fields and stop() settles it as it does for any
            // undrained remainder today). A PLAYING close keeps the 5.0s
            // drain exactly as before. Precedent: ShellFrameSource's
            // paused/user-closed teardown drains with 0.0. The pause
            // witness is the pump's own isPaused (the session-level pause
            // state), read while the pump is still alive here; no pump
            // means no pause witness, so the legacy 5.0s drain stands.
            let pausedAtTeardown = await pump?.isPaused ?? false
            let drained = await audio.drainBounded(maxSeconds: pausedAtTeardown ? 0.0 : 5.0)
            lastDrainRemainingBytes = drained.remaining
            lastDrainCancelled = drained.cancelled
            legAudioDrainMs = Self.ms(since: tDrain)
            let tStop = ContinuousClock.now   // native102 leg timing
            _ = audio.stop()
            legAudioStopMs = Self.ms(since: tStop)
            audio.drainRTTransitions(segment: .teardown)
        }
        audio = nil
        clock?.attachAudioMaster(nil)
        clock = nil
        preparedAdoption.clear()
        preparedShot = nil; preparedReceipt = nil; openedPath = nil
        pump = nil; source = nil; bridge = nil; commit = nil
        stereoTransport = nil   // P31: glue teardown with the source pair
        audioTask = nil; pumpTask = nil; audioBinding = nil; audioCorrelation = nil
        if let media = preparedMedia {
            do { try media.release(); preparedMedia = nil }
            catch { onEvent?(.failed("sourceCacheCleanupFailed")) }
        }
    }

    private func closeLegsAfterSeekFailure(videoOnly: Bool) async {
        if let decoder, let issued = session { _ = await decoder.closeAndReport(session: issued) }
        self.decoder = nil
        if !videoOnly { await cleanupLegs() }
    }

    // MARK: - Producers

    private func startPump() {
        guard let pump else { return }
        terminalPumpStats = nil
        terminalEndReason = nil
        pumpTask = Task { [weak self] in
            let stats = await pump.run()
            await self?.pumpDidFinish(stats)
            return stats
        }
    }

    private func startAudioProducer(landingBox: AudioLandingBox,
                                    binding: AudioSourceBinding? = nil,
                                    correlation: UInt64? = nil,
                                    sharedAnchor: MediaWallAnchor? = nil) {
        guard let adec, let audio, let issued = session, let flag = audioStopFlag,
              let pump, let clock, let commit else { return }
        let b = binding ?? audioBinding
        let c = correlation ?? audioCorrelation
        // @Sendable closures capture ONLY Sendable locals (no self) -
        // Swift 6 strict-concurrency safe by construction.
        let stopFlag: @Sendable () async -> Bool = { flag.load() != 0 || commit.isCancelled }
        let pauseFlag: @Sendable () async -> Bool = { await pump.isPaused }
        if let b {
            audioTask = Task {
                let o = await BoundAudioPump.run(decoder: adec, session: issued, binding: b,
                    correlation: c, sink: audio, clock: clock, sharedAnchor: sharedAnchor,
                    ledger: nil, ledgerSession: issued.epoch, landing: landingBox,
                    shouldStop: stopFlag, shouldPause: pauseFlag)
                return EmbeddedProducerOutcome(pushed: o.pushed, terminal: Self.mapTerm(o.terminal))
            }
        } else {
            // No seek binding (descriptor unavailable): the trunk's proven
            // runPaced fallback keeps real audio playback; seek stays a
            // typed refusal and the host was told via .audioUnbound.
            audioTask = Task {
                let o = await ShellAudioPump.runPaced(decoder: adec, session: issued, sink: audio,
                    ledger: nil, ledgerSession: issued.epoch,
                    shouldStop: stopFlag, shouldPause: pauseFlag)
                return EmbeddedProducerOutcome(pushed: o.pushed, terminal: o.terminal)
            }
        }
    }

    private static func mapTerm(_ bt: BoundPumpTerminal) -> ShellAudioPump.Terminal {
        switch bt {
        case .endOfStream: return .endOfStream
        case .sourceEnded: return .sourceEnded
        case .cancelled: return .cancelled
        case .stoppedEarly: return .stoppedEarly
        case .failed(let c): return .failed(Int(c))
        }
    }

    /// Honest first-presentation signal: the pump sets its pace anchor at
    /// the FIRST frame decision of a presentation generation. A bounded
    /// watch emits .firstFrame once; timeout emits nothing (no fake).
    private func startFirstFrameWatch() {
        guard let pump else { return }
        firstFrameTask?.cancel()
        let watchGeneration = tracker.generation
        firstFrameTask = Task { [weak self] in
            for _ in 0..<600 {
                if Task.isCancelled { return }
                if let anchor = await pump.currentPaceAnchor?.mediaSeconds {
                    self?.acceptFirstFrame(anchor: anchor, generation: watchGeneration)
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    private func acceptFirstFrame(anchor: Double, generation: Int) {
        guard !tornDown, !fenced,
              tracker.firstFrame(anchor: anchor, clockNow: trackerClockNow(), generation: generation) else { return }
        publishTime(newGeneration: true)
        emitFirstFrame()
    }
    private func publishTime(newGeneration: Bool = false) {
        guard !tornDown, !fenced, plane.state == .playing || plane.state == .paused else { return }
        let now = trackerClockNow()
        if let value = timeGate.offer(tracker.read(clockNow: now, durationSeconds: durationSeconds), clockNow: now, newGeneration: newGeneration) {
            onEvent?(.timePos(seconds: value, generation: tracker.generation))
            observations.publish(.timePos, .double(value))
        }
    }

    /// G4: open-time property publication. hwdec-current is the constant
    /// "no" (software decode only); a future hwdec path must change this
    /// publish, not paper over it.
    private func publishOpenObservations(titleFallback: String, issued: SessionID) {
        observations.publish(.eofReached, .bool(false))
        observations.publish(.idleActive, .bool(false))
        observations.publish(.hwdecCurrent, .string("no"))
        if let d = durationSeconds { observations.publish(.duration, .double(d)) }
        else { observations.publish(.duration, .none) }
        if let snap = adec?.activeMediaInventory(session: issued) {
            let md = snap.inventory.metadata
            observations.publish(.metadata, .stringDict(md))
            observations.publish(.mediaTitle, .string(md["title"] ?? titleFallback))
        } else {
            observations.publish(.mediaTitle, .string(titleFallback))
        }
    }
    private func startTimeObserver() {
        timeTask?.cancel()
        timeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.tornDown, !self.fenced else { return }
                self.publishTime()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func emitFirstFrame() {
        guard plane.state == .playing || plane.state == .paused else { return }
        // One actual signal, one event: the facade maps .firstFrame onto its
        // firstVideoFrame + playing vocabulary (both sourced from the same
        // observed pace anchor, never fabricated).
        onEvent?(.firstFrame)
    }

    private func pumpDidFinish(_ stats: PumpStats) async {
        // Capture the real terminal counters on EVERY pump end,
        // including teardown-cancelled runs, before the tornDown
        // guard drops the event side (XA9 stats wiring).
        terminalPumpStats = (stats.shown, stats.dropped, stats.waits)
        terminalEndReason = stats.endReason
        guard !tornDown else { return }
        // Pump reached a terminal state on its own (EOS / cancel / failure).
        tornDown = true
        stereoProjectionRefusalHandler = nil
        presenter?.stereoProjectionRefusalHandler = nil
        closeSubtitleDelivery()
        if plane.state != .closing { _ = plane.apply(.close) }
        await cleanupLegs()
        _ = plane.apply(.closed)
        switch stats.endReason {
        case .endOfStream:
            observations.publish(.eofReached, .bool(true))
            onEvent?(.ended(reason: "eof"))
        // source exhausted WITHOUT explicit EOS is NOT a clean EOS
        // (typed source states, S3): keep it distinguishable.
        case .sourceEnded: onEvent?(.ended(reason: "sourceEnded"))
        case .cancelled where stats.windowClosed: onEvent?(.ended(reason: "windowClosed"))
        case .cancelled: onEvent?(.ended(reason: "cancelled"))
        case .failed(let code): onEvent?(.failed("pump:\(code)"))
        default: onEvent?(.ended(reason: "unknown"))
        }
    }

    // MARK: - Snapshot (sourced-only fields)

    public func snapshot() async -> EmbeddedSnapshot {
        var s = EmbeddedSnapshot()
        s.seekTrace = seekTrace
        s.controlTrace = controlTrace
        s.audioFirstAdmissionWallSeconds = landingBoxes.compactMap { $0.admissionWall }
        s.audioLandingFirstSampleSeconds = landingBoxes.flatMap { box in
            box.admittedAll.map { Double($0.firstSample.value) / Double($0.firstSample.timescale) }
        }
        s.durationSeconds = durationSeconds
        s.effectiveVideo = presenter?.effectiveVideo()
        if plane.state != .seeking { s.timePositionSeconds = tracker.read(clockNow: trackerClockNow(), durationSeconds: durationSeconds) }
        s.lifecycle = plane.state
        s.generation = plane.generation
        if let pump {
            s.isPaused = await pump.isPaused
            s.anchorMediaSeconds = await pump.currentPaceAnchor?.mediaSeconds
            s.presentedFrames = await pump.livePresentedCount
            s.seekLandingDrops = await pump.liveSeekLandingDrops
            s.seekLandingLastDropPTS = await pump.liveSeekLandingLastDropPTS
            s.seekLandingFencedShows = await pump.liveSeekLandingFencedShows
            s.seekLandingFencedAdmitNil = await pump.liveSeekLandingFencedAdmitNil
            s.seekLandingFencedSinkFalse = await pump.liveSeekLandingFencedSinkFalse
            s.seekLandingLastDecodedPTS = await pump.liveSeekLandingLastDecodedPTS
            s.seekLandingMaxDecodedPTS = await pump.liveSeekLandingMaxDecodedPTS
            s.seekPrerollSkipped = decoder?.seekPrerollSkipped
        } else if let t = terminalPumpStats {
            s.presentedFrames = t.shown
        }
        if let audio {
            s.audioCallbacks = audio.callbackCount
            s.audioIntentionalSilenceFrames = audio.pausedSilenceFrames
            s.audioNonSilenceFrames = audio.nonSilenceFrames
        }
        s.seekCommittedCount = seekCounter
        s.eofReached = terminalEndReason == .endOfStream
        s.pumpEndReason = terminalEndReason?.rawValue
        if let t = terminalPumpStats {
            s.shown = t.shown
            s.dropped = t.dropped
            s.waits = t.waits
        }
        return s
    }

    // MARK: - Helpers

    /// An in-flight open must never report success after a fence or
    /// teardown landed across one of its awaits (XBPP P1-2): the failed
    /// transition throws BEFORE any success completion.
    private func throwIfSuperseded() throws {
        if tornDown || fenced || (commit?.isCancelled ?? false) {
            throw EmbeddedRefusal.illegalState("openSuperseded")
        }
    }

    private func applyOrReport(_ control: PlayerControl) {
        // Plane refusals are programming errors at these call sites
        // (guards above pre-validate); record via the typed token path.
        if case .failure(let r) = plane.apply(control) {
            onEvent?(.failed("plane:\(r)"))
        }
    }

    private func typedToken(_ error: Error) -> String {
        if let e = error as? EmbeddedRefusal {
            switch e {
            case .unsupportedSource: return "unsupportedSource"
            case .unsupportedCommand: return "unsupportedCommand"
            case .seekUnavailable: return "seekUnavailable"
            case .identityExhausted: return "identityExhausted"
            case .pacingRefused: return "pacingRefused"
            case .audioRefused: return "audioRefused"
            case .stopFlagRefused: return "stopFlagRefused"
            case .bridgeRefused: return "bridgeRefused"
            case .alreadyOpen: return "alreadyOpen"
            case .notOpen: return "notOpen"
            case .illegalState: return "illegalState"
            }
        }
        // arch-196t r3 item 2: the exact typed reason rides the token so the
        // facade can render "gorav: <reason> -> mpv" without re-deriving it.
        return "openFailed(\(String(describing: error)))"
    }

    /// arch-196t r3: typed fallback reason for the in-window engine switch.
    /// The facade offers every file to gorav first; when open throws, it
    /// renders "gorav: <this string> -> mpv" on the HUD and opens the same
    /// file on mpv. Never a refusal dialog, never a silent fallback.
    public static func fallbackReason(for error: Error) -> String {
        if let e = error as? EmbeddedRefusal { return String(describing: e) }
        return String(describing: error)
    }
}

/// native87 B-gate close report: measured counters at close-request time
/// plus the measured close duration and the typed shutdown verdict.
public struct EmbeddedCloseReport: Sendable, Equatable {
    public var reason = ""
    public var closeMs = 0.0
    public var presentedFrames: Int?
    public var audioCallbacks: UInt64?
    public var audioIntentionalSilenceFrames: UInt64?
    public var audioNonSilenceFrames: UInt64?
    public var eofReached = false
    public var cleanShutdown = false
    /// native102 (observation only; no behavior/bound change; goreda T2 -
    /// native101 B3 close 5139.1ms ~= drainBounded maxSeconds 5.0): the
    /// teardown drain result and the close leg timings, measured at the
    /// real legs. nil when the leg never ran (e.g. no audio unit) -
    /// honest absence, never a fabricated zero.
    public var audioRingBytesAtRequest: Int?
    public var audioDrainStartBytes: Int?
    public var audioDrainRemainingBytes: Int?
    public var audioDrainCancelled: Bool?
    public var taskAwaitMs: Double?
    public var presenterDecoderCloseMs: Double?
    public var audioDrainMs: Double?
    public var audioStopMs: Double?
    public init() {}
}

/// Diagnostics from the actual decoder, output unit and shared clock, not receipt tokens.
public struct EmbeddedPreparedShotWitness: Equatable {
    public let epoch: UInt64
    public let audioBinding: AudioSourceBinding
    public let videoToken: SourceToken
    public let audioUnit: ObjectIdentifier
    public let clock: ObjectIdentifier
    public let sinkGeneration: UInt64
    public let audioStopCalls: Int
    public let consumedBytes: Int
}

// MARK: - Prepared shots on a live session

/// Adopts this session's live initial sources. It never opens or starts audio.
/// Separate initial audio files and initially idle preparation are refused.
extension GorAVEmbeddedSession: PreparedShotSessionBackend {
    public var preparedShotEpoch: UInt64? { session?.epoch }
    public func preparedShotFilmTime() async -> Double? { await pump?.currentFilmTime }
    public func preparedShotLiveWitness() -> EmbeddedPreparedShotWitness? {
        guard let session, let adec, let binding = adec.preparedShotBinding(session: session),
              let audio, let clock, let videoToken = decoder?.currentBinding()?.token else { return nil }
        return EmbeddedPreparedShotWitness(epoch: session.epoch, audioBinding: binding, videoToken: videoToken,
            audioUnit: ObjectIdentifier(audio), clock: ObjectIdentifier(clock),
            sinkGeneration: audio.currentGeneration, audioStopCalls: audio.stopCallCount,
            consumedBytes: audio.kitConsumedBytes)
    }

    public func prepare(_ shot: PreparedShot) async throws -> PreparedShotCommitReceipt {
        guard preparedShot == nil, !preparedOperation, !tornDown, !fenced,
              let issued = session, let decoder, let adec, let audio,
              let openedPath, let binding = audioBinding,
              let flag = audioStopFlag else {
            throw PreparedShotError.sourceNotPrepared("live bound session required")
        }
        guard shot.filmClockEpoch == issued.epoch else {
            throw PreparedShotError.staleEpoch(expected: issued.epoch, found: shot.filmClockEpoch)
        }
        guard shot.video.kind == .local, shot.video.id == openedPath,
              shot.video.startOffset.value == 0,
              let audioRef = shot.audio, audioRef.kind == .local,
              audioRef.id == openedPath, audioRef.startOffset.value == 0 else {
            throw PreparedShotError.admissionRefused("prepare adopts the live initial local video/audio at offset zero")
        }
        let validator = LivePreparedShotSourceValidator(video: shot.video, decoder: decoder,
            audio: audioRef, audioDecoder: adec, sink: audio, session: issued,
            binding: binding, stopFlag: flag)
        guard validator.canBind(shot.video), validator.canBind(audioRef),
              validator.audioSurvivesVideoReplace(audioRef) else {
            throw PreparedShotError.audioBindingLost(reason: "live source binding unavailable")
        }
        let receipt = PreparedShotCommitReceipt(shotID: shot.shotID, epoch: issued.epoch,
            audioBindingID: binding.source, audioBindingPreserved: true,
            committedAt: shot.video.startOffset, priorVideo: nil)
        preparedAdoption.adopt()
        preparedShot = shot
        preparedReceipt = receipt
        return receipt
    }

    /// Narrow gor seam: incoming video timestamps are already absolute film PTS.
    /// Convert against the staged stream's actual origin before seeking it.
    public func replaceVideoPreservingFilmPTS(at filmTime: RationalTime, path: String) async throws -> PreparedShotCommitReceipt {
        try await replacePreparedVideo(at: filmTime,
            with: SourceRef(id: path, kind: .local, startOffset: filmTime), preserveAbsoluteFilmPTS: true)
    }

    public func replaceVideo(at filmTime: RationalTime, with video: SourceRef) async throws -> PreparedShotCommitReceipt {
        try await replacePreparedVideo(at: filmTime, with: video, preserveAbsoluteFilmPTS: false)
    }

    private func replacePreparedVideo(at filmTime: RationalTime, with video: SourceRef,
                                      preserveAbsoluteFilmPTS: Bool) async throws -> PreparedShotCommitReceipt {
        guard !preparedOperation, let shot = preparedShot, let prior = preparedReceipt,
              !tornDown, !fenced, let issued = session, let pump, let oldDecoder = decoder,
              let adec, let audio, let binding = audioBinding, let flag = audioStopFlag,
              let commit, !commit.isCancelled else {
            throw PreparedShotError.sourceNotPrepared("no live prepared shot")
        }
        guard shot.filmClockEpoch == issued.epoch else {
            throw PreparedShotError.staleEpoch(expected: issued.epoch, found: shot.filmClockEpoch)
        }
        guard video.kind == .local, video.startOffset.value >= 0,
              video.id.hasPrefix("/"), !video.id.contains("://"), filmTime.value >= 0,
              FileManager.default.fileExists(atPath: video.id) else {
            throw PreparedShotError.admissionRefused("replacement must be a seekable local video")
        }
        guard preparedAdoption.beginOperation() else {
            throw PreparedShotError.sourceNotPrepared("prepared operation in flight")
        }
        preparedOperation = true
        var didCommit = false
        defer {
            preparedOperation = false
            preparedAdoption.finishOperation(didCommit: didCommit)
        }
        let candidate = FFmpegSoftwareDecoder()
        do {
            try candidate.pinLocalRoots([(video.id as NSString).deletingLastPathComponent])
            try await candidate.open(source: SourceDescriptor(id: video.id, kind: .local, seekable: true), session: issued)
            guard !tornDown, !fenced, !commit.isCancelled,
                  let cb = candidate.currentBinding() else {
                throw PreparedShotError.audioBindingLost(reason: "session closed during staging")
            }
            let descriptor = try candidate.descriptor(for: cb.token)
            guard descriptor.seekable, let tb = descriptor.streamTimebase, tb.value > 0,
                  let origin = descriptor.startOrigin else {
                throw PreparedShotError.admissionRefused("video timebase/origin unavailable")
            }
            let seekPosition = preserveAbsoluteFilmPTS
                ? try filmTime.mediaRelativePosition(streamOrigin: origin, streamTimebase: tb)
                : video.startOffset
            let candidateBridge = ShellSeekBridge()
            guard candidateBridge.attach(to: candidate) else {
                throw PreparedShotError.admissionRefused("replacement bridge refused")
            }
            switch await candidateBridge.seek(on: candidate, position: seekPosition, commitACK: { _, _ in }) {
            case .committedFlushed: break
            default: throw PreparedShotError.admissionRefused("replacement native seek/flush refused")
            }
            // Use the actual stream timebase rather than ShellFrameSource's legacy default.
            let candidateSource = ShellFrameSource(decoder: candidate, session: issued,
                timeBaseDen: Double(tb.timescale) / Double(tb.value))
            candidateSource.seekBridge = candidateBridge
            // P27: the replacement source serves the SAME session, so its tap
            // is created for the same session identity (the previous
            // source's tap closes with it on teardown).
            candidateSource.frameTap = FrameTap.makeForSession(session: issued.epoch)
            let sourceStart = preserveAbsoluteFilmPTS
                ? Double(filmTime.value) / Double(filmTime.timescale)
                : Double(origin.value) / Double(origin.timescale)
                    + Double(video.startOffset.value) / Double(video.startOffset.timescale)
            let filmStart = Double(filmTime.value) / Double(filmTime.timescale)
            var first: SourceFrame?
            // Bounded preroll. Nothing from this candidate reaches the live presenter yet.
            for _ in 0..<4096 {
                switch await candidateSource.nextEvent() {
                case .frame(let f):
                    guard f.ptsSeconds.isFinite else {
                        throw PreparedShotError.admissionRefused("nonfinite candidate PTS")
                    }
                    if f.ptsSeconds >= sourceStart { first = f }
                default: throw PreparedShotError.admissionRefused("candidate has no decoded landing frame")
                }
                if first != nil { break }
            }
            guard let first, first.pixelPayload != nil else {
                throw PreparedShotError.admissionRefused("candidate landing pixels unavailable")
            }
            guard !tornDown, !fenced, preparedShot?.shotID == shot.shotID,
                  let audioRef = shot.audio else {
                throw PreparedShotError.audioBindingLost(reason: "prepared session superseded")
            }
            let validator = LivePreparedShotSourceValidator(video: video, decoder: candidate,
                audio: audioRef, audioDecoder: adec, sink: audio, session: issued,
                binding: binding, stopFlag: flag)
            guard validator.canBind(video), validator.audioSurvivesVideoReplace(audioRef) else {
                throw PreparedShotError.audioBindingLost(reason: "audio binding changed during staging")
            }
            let mapped = PreparedVideoFrameSource(source: candidateSource, first: first,
                sourceStart: sourceStart, filmStart: filmStart)
            let swapped = await pump.replaceVideoSource(mapped, atFilmTime: filmStart,
                validating: { validator.canBind(video) && validator.audioSurvivesVideoReplace(audioRef) })
            // Record the real pump commit before any MainActor continuation checks.
            didCommit = swapped
            guard swapped, !tornDown, !fenced, preparedShot?.shotID == shot.shotID else {
                throw PreparedShotError.audioBindingLost(reason: "handoff refused: clock, cancellation or binding changed")
            }
            // No audio decoder seek/close, producer restart, ring reset or clock rebase.
            replaceSubtitleSource(path: video.id)
            self.decoder = candidate
            self.source = candidateSource
            self.bridge = candidateBridge
            if let presenter { rebindStereoGlue(source: candidateSource, presenter: presenter, adoptedPath: video.id) }
            let receipt = PreparedShotCommitReceipt(shotID: shot.shotID, epoch: prior.epoch,
                audioBindingID: prior.audioBindingID, audioBindingPreserved: true,
                committedAt: filmTime, priorVideo: shot.video)
            preparedShot = PreparedShot(shotID: shot.shotID, video: video, audio: shot.audio,
                filmClockEpoch: shot.filmClockEpoch)
            preparedReceipt = receipt
            _ = await oldDecoder.closeAndReport(session: issued)
            return receipt
        } catch {
            // Only the isolated candidate is closed on failure. Old pump/source/audio
            // and the prior receipt are untouched. The pump swap has no fallible tail.
            _ = await candidate.closeAndReport(session: issued)
            throw error
        }
    }

    public func currentReceipt() async -> PreparedShotCommitReceipt? { preparedReceipt }
    /// Releases only an adoption whose first video swap never committed. A busy
    /// operation refuses; cancel its Task and retry after it returns. No audio teardown.
    public func abortUncommittedPreparation() async -> PreparedAdoptionRelease {
        let result = preparedAdoption.abortUncommitted()
        if result == .released { preparedShot = nil; preparedReceipt = nil }
        return result
    }

    /// Explicit terminal cancel: intentionally stops the whole session, including audio.
    public func cancel() async {
        preparedAdoption.clear()
        preparedShot = nil; preparedReceipt = nil
        await tearDownInternal(reason: "preparedShotCancelled")
    }
}

/// The booleans attest REAL open decoder bindings, not source-name allowlists.
/// Immutable handles only; each call rechecks queue/lock-protected live state.
private final class LivePreparedShotSourceValidator: PreparedShotSourceValidator, @unchecked Sendable {
    let video: SourceRef
    let decoder: FFmpegSoftwareDecoder
    let audio: SourceRef
    let audioDecoder: FFmpegSoftwareAudioDecoder
    let sink: AudioUnitSink
    let session: SessionID
    let binding: AudioSourceBinding
    let stopFlag: AtomicU64
    let sinkGeneration: UInt64
    init(video: SourceRef, decoder: FFmpegSoftwareDecoder, audio: SourceRef,
         audioDecoder: FFmpegSoftwareAudioDecoder, sink: AudioUnitSink,
         session: SessionID, binding: AudioSourceBinding, stopFlag: AtomicU64) {
        self.video = video; self.decoder = decoder; self.audio = audio
        self.audioDecoder = audioDecoder; self.sink = sink; self.session = session
        self.binding = binding; self.stopFlag = stopFlag; self.sinkGeneration = sink.currentGeneration
    }
    func canBind(_ source: SourceRef) -> Bool {
        if source == video, let current = decoder.currentBinding(),
           current.session.rawValue == session.epoch { return true }
        return source == audio && audioSurvivesVideoReplace(source)
    }
    func audioSurvivesVideoReplace(_ source: SourceRef) -> Bool {
        guard case .active = sink.lifecycleState else { return false }
        return source == audio && stopFlag.load() == 0 && sinkGeneration != 0
            && sink.currentGeneration == sinkGeneration
            && audioDecoder.preparedShotBinding(session: session) == binding
            && sink.stoppedReceipt == nil
    }
}

#endif
