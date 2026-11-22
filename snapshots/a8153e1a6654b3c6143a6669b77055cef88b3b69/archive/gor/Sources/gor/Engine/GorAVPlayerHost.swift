import AppKit
import GorAVEmbeddedShell
import GorAVPlaybackCore
import GorAVNativeProbeKit

/// Integration-branch host. Never creates an mpv process, IPC or config file.
/// This first slice opens local media and drives real pause/seek/volume controls.
/// Local text sidecars and live time use the embedded session's source/epoch fences.
/// This row is not a full native feature or pixel-parity acceptance claim.
@MainActor
final class GorAVPlayerHost: NSWindowController {
    static let candidate = "2112af0d60df16c5473173b664903f76ce54173e"
    struct SourceContext {
        let path: String
        var headers: [String: String] = [:]
        var cookies: String? = nil
        var startSeconds: Double = 0
    }
    enum Refusal: Error { case missingSource, unsupportedSourceContext, unsupportedCapability(String) }
    private var hostWindow: GorAVHostWindow?
    private(set) var chrome:PPController?
    var onObservation:((EngineObservedState)->Void)?
    var onOpenFailure:((String)->Void)?
    var onPostOpenFailure:((String)->Void)?
    let postOpenFallback = GorAVPostOpenFallback()
    private(set) var observed = EngineObservedState()
    private(set) var sourceURL: URL?
    var currentTime: Double? { observed.timePos }
    private(set) var preparedPlayback: PreparedShotPlayback?
    private var lastVideoDimensions: (Int, Int)?
    private var session: GorAVEmbeddedSession?
    /// NATIVE stereo-look input owner (typed vr180_look command route,
    /// Ops nativefeed contract): accepts typed discrete commands at
    /// handleChromeCommand and vends the immutable accepted input to
    /// the session's per-frame pull. The renderer's accepted ack is the
    /// sole applied truth; nothing here is presented as applied state.
    private let stereoLookNativeOwner = StereoLookNativeInputOwner(clock: { ProcessInfo.processInfo.systemUptime })
    /// Monotone SOURCE-ORIGIN generation (Ops v5 finding: the session
    /// token alone is not a source fence). Incremented at every
    /// beginSession AND at every same-session source adoption; the
    /// embedded command closure captures it at install, so a command
    /// queued under a superseded source generation is refused by the
    /// owner after the adoption hook re-points the transport.
    private var stereoLookSourceGeneration: UInt64 = 0
    /// Explicit initialization for this limited native-entry successor.
    /// Neutral pose 0/0/135/0 comes from the existing native reset policy;
    /// calibration 0 is the retired-feature policy. Their labels remain until
    /// real pose commands replace the corresponding values.
    /// shippedLuaPair is a declared initialization policy: Lua sets strength
    /// to 0.4 and disparity to -strength, then copies both into vr_tune.
    /// It is not synthetic set-tune acceptance; later keys mutate independently.
    /// No IPD dial, projection, pack, swap, tools or enabled value is installed
    /// here. Current canonical Store intent must supply every required lane.
    /// Coverage is explicit original native VR180 SBS/TB plus VR180/Off only.
    /// Default blink-On and other camera requests remain visibly refused while
    /// the native viewer-camera consumer path is not integrated. Native runtime/pixels unqualified.
    private static let stereoLookNativeInitial = StereoLookNativeInitial(
        poseYaw: 0, posePitch: 0, poseFov: 135, poseRoll: 0,
        calibration: 0, declaredTune: .shippedLuaPair)
    private var photonHUDTask:Task<Void,Never>?
    private var photonHUDRevision:UInt64?
    private var livePhotonTarget=true
    private var livePhotonSharpTarget=true,livePhotonGrainTarget=true
    private var nativeStereoReceipt: NativeStereoEntryReceipt?
    private var nativeStereoSourceSeal: (sourceID:String, selectedVideoIndex:Int, revision:UInt64, presentationEpoch:UInt64)?
    private var nativeStereoFilmID: FilmID?
    private var nativeStereoOriginalMediaID: String?
    private var nativeStereoOrigin: StereoLookCommandOrigin?
    private let nativeStereoIntent=StereoLookNativeIntentAdapter()
    private struct NativeStereoProjectionRefusalKey: Equatable {
        let sourceGeneration: UInt64
        let reason: String
        let stageEpoch: UInt64?
        let acceptanceEpoch: UInt64
        let providerRegistration: UInt64
    }
    private var nativeStereoProjectionRefusalKey: NativeStereoProjectionRefusalKey?

    /// arch facade r1: the app target's native-entry seam consumes an
    /// app-owned receipt view (StereoLookNativeEntryReceipt), so the two
    /// StereoLook app files no longer import gorav-internal modules. This
    /// is a pure field copy of the receipt's FULL synthesized-equality
    /// surface (facade r2; r1 dropped the pixel-aspect pair and collapsed
    /// unequal receipts on the dedupe/reseal path) at the one existing
    /// GorAVEmbeddedShell boundary; nothing is recomputed, defaulted or
    /// filtered, and value equality is preserved for the adapter's
    /// last-evidence dedupe.
    private func nativeEntryView(_ receipt: NativeStereoEntryReceipt) -> StereoLookNativeEntryReceipt {
        let f = receipt.evidence
        return StereoLookNativeEntryReceipt(
            originalMediaID: receipt.originalMediaID,
            playbackMediaID: receipt.playbackMediaID,
            prepared: receipt.prepared,
            evidence: .init(identity: .init(
                    sourceID: f.identity.sourceID, session: f.identity.session,
                    revision: f.identity.revision,
                    presentationEpoch: f.identity.presentationEpoch),
                selectedVideoIndex: f.selectedVideoIndex,
                uncroppedWidth: f.uncroppedWidth, uncroppedHeight: f.uncroppedHeight,
                pixelAspect: f.pixelAspect,
                pixelAspectOrigin: f.pixelAspectOrigin.map { origin in
                    // Exhaustive, no default: a future package case must fail
                    // compile here, never silently map to .selectedStream.
                    switch origin {
                    case .selectedStream: return .selectedStream
                    case .openedDecoder: return .openedDecoder
                    }
                },
                attachedPicture: f.attachedPicture))
    }

    private func installNativeStereoProjectionRefusalHandler(
        on session: GorAVEmbeddedSession, origin: StereoLookCommandOrigin,
        receipt: NativeStereoEntryReceipt, film: FilmID
    ) {
        session.stereoProjectionRefusalHandler = { [weak self, weak session] event in
            guard let self, let session,
                  self.session === session, self.identity == origin.session,
                  self.nativeStereoOrigin?.session == origin.session,
                  self.nativeStereoOrigin?.source == origin.source,
                  self.nativeStereoOrigin?.generation == origin.generation,
                  self.stereoLookNativeOwner.matchesOrigin(origin),
                  self.nativeStereoReceipt == receipt,
                  session.nativeStereoEntryIsCurrent(receipt),
                  self.nativeStereoIntent.hasAcceptedSourceEvidence(nativeEntryView(receipt)),
                  ThreeDStore.shared.snapshot.currentFilm == film,
                  event.hostSession == origin.session,
                  event.hostSource == origin.source,
                  event.hostSourceGeneration == origin.generation,
                  let acceptance = event.hostAcceptanceEpoch,
                  acceptance == self.stereoLookNativeOwner.acceptanceEpoch,
                  let chrome = self.chrome else { return }
            // Frame sequence and renderer refusal-counter churn must not
            // produce an OSD every frame. Source adoption resets this key.
            let key = NativeStereoProjectionRefusalKey(
                sourceGeneration: origin.generation, reason: event.reason,
                stageEpoch: event.stageEpoch, acceptanceEpoch: acceptance,
                providerRegistration: event.hostStateRegistration)
            guard key != self.nativeStereoProjectionRefusalKey else { return }
            self.nativeStereoProjectionRefusalKey = key
            chrome.showNativeStereoProjectionRefusal(event.reason)
        }
        session.stereoDistanceTraceHandler = { line in
            // Existing local trace facility, off by default
            // (GOR_TRACE_GEOM); the presenter already dedups and
            // logChanged dedups again harmlessly.
            GeomTrace.logChanged("vrDistance", line)
        }
    }

    private func resetNativeStereoEntry(origin: StereoLookCommandOrigin?, original: String? = nil) {
        session?.stereoProjectionRefusalHandler = nil
        session?.stereoDistanceTraceHandler = nil
        nativeStereoProjectionRefusalKey = nil
        nativeStereoReceipt=nil
        nativeStereoSourceSeal=nil
        nativeStereoOrigin=origin
        nativeStereoIntent.reset(origin: origin)
        chrome?.embeddedThreeDState=nil; chrome?.embeddedThreeDAction=nil
        if let original { nativeStereoOriginalMediaID=original; nativeStereoFilmID=nil }
        if origin == nil { nativeStereoOriginalMediaID=nil; nativeStereoFilmID=nil }
    }

    private func refreshNativeStereoEntry() {
        guard let session, let origin=nativeStereoOrigin,
              identity == origin.session,
              let receipt=session.nativeStereoEntryEvidence(),
              receipt.originalMediaID == nativeStereoOriginalMediaID,
              receipt.playbackMediaID == origin.source else {
            nativeStereoReceipt=nil
            return
        }
        let facts=receipt.evidence
        if let seal=nativeStereoSourceSeal {
            guard seal.sourceID == facts.identity.sourceID,
                  seal.selectedVideoIndex == facts.selectedVideoIndex,
                  facts.identity.revision >= seal.revision,
                  facts.identity.presentationEpoch >= seal.presentationEpoch else {
                nativeStereoReceipt=nil
                return // Only an explicit source-adoption reset can change selection.
            }
        }
        nativeStereoSourceSeal=(facts.identity.sourceID, facts.selectedVideoIndex,
            facts.identity.revision, facts.identity.presentationEpoch)
        if receipt == nativeStereoReceipt { return }
        nativeStereoReceipt=receipt
        // Resolve only the original film. Prepared artifact paths are never
        // fed into identity resolution or the Store's .open action here.
        let opening=nativeStereoFilmID == nil
        if opening {
            let film=ThreeDRecognitionBridge.resolveAtOpen(path: receipt.originalMediaID)
            nativeStereoFilmID=film
            ThreeDStore.shared.bindSource(path: receipt.originalMediaID, id: film)
        }
        guard let film=nativeStereoFilmID else { return }
        installNativeStereoProjectionRefusalHandler(on: session, origin: origin,
                                                    receipt: receipt, film: film)
        chrome?.embeddedThreeDState = { [weak self, weak session] state, effects, revision in
            guard let self, let session, self.identity == origin.session,
                  self.nativeStereoReceipt == receipt else {
                return "native entry: retired host or source receipt"
            }
            return self.nativeStereoIntent.apply(state: state, effects: effects, revision: revision,
                currentState: ThreeDStore.shared.snapshot, currentRevision: ThreeDStore.shared.revision,
                receipt: nativeEntryView(receipt), receiptIsCurrent: session.nativeStereoEntryIsCurrent(receipt),
                origin: origin, filmID: film, owner: self.stereoLookNativeOwner)
        }
        chrome?.embeddedThreeDAction = { [weak self, weak session] action in
            guard let self, let session, self.identity == origin.session,
                  self.nativeStereoReceipt == receipt,
                  self.stereoLookNativeOwner.matchesOrigin(origin),
                  session.nativeStereoEntryIsCurrent(receipt),
                  ThreeDStore.shared.snapshot.currentFilm == film else {
                return "native entry: current original-film evidence required before editing"
            }
            // A command callback cannot edit a previous film while a new file
            // opens, nor reclassify a prepared artifact as the original film.
            switch action {
            case .setSource(let source):
                guard !receipt.prepared, [.vr180SBS, .vr180TB].contains(source.format) else {
                    return "native entry: source choice unavailable"
                }
            case .setOutput(let output):
                guard output == .off || (output == .vr180 && !receipt.prepared) else {
                    return "native entry: output choice unavailable"
                }
            default: return "native entry: action unavailable"
            }
            ThreeDStore.shared.dispatch(action)
            return nil
        }
        if opening {
            // No container-text projection guess, filename guess, still/moving
            // guess or borrowed mpv recognition. Explicit source choices work.
            ThreeDStore.shared.dispatch(.open(film, ThreeDEvidence()))
        } else {
            chrome?.applyThreeDState(ThreeDStore.shared.snapshot, [.reapply])
        }
    }

    private var identity = UUID()
    private let video = NSView()
    private let status = NSTextField(labelWithString: "gorav: no media")
    private var task: Task<Void, Never>?
    private var gateControlTask: Task<Void, Never>?
    private var gateCloseTask: Task<Void, Never>?
    private var gateWindowCloseTask: Task<Void, Never>?
    private(set) var gateFailureCount = 0
    private(set) var gateTerminalCount = 0
    /// Typed engine close report of the last closeSession teardown (native87);
    /// nil until a close completes in this session generation.
    private(set) var gateCloseReport: EmbeddedCloseReport?
    private var muted = false
    private var volume: Float = 1
    private var volumeSessionReady = false
    private var seekValue = NSTextField(string: "0")

    init(inWindowChrome:Bool=false,playerWindow:NSWindow?=nil) {
        super.init(window: nil)
        video.wantsLayer = true
        video.layer?.backgroundColor = NSColor.black.cgColor
        let content:NSView
        if inWindowChrome {
            let root=NSView(frame:NSRect(x:0,y:0,width:640,height:360))
            video.frame=root.bounds;video.autoresizingMask=[.width,.height];root.addSubview(video)
            let controls=PPController(frame:root.bounds,ipcPath:"",embeddedBackend:true)
            controls.autoresizingMask=[.width,.height]
            controls.embeddedCommand={ [weak self] line in self?.handleChromeCommand(line) }
            controls.embeddedDelay={ [weak self] property,seconds in guard let self else {return "host closed"};return self.applyChromeDelay(property,seconds) }
            controls.embeddedSubtitleScale={ [weak self] scale in guard let self else {return "host closed"};return self.applyChromeSubtitleScale(scale) }
            controls.embeddedSubtitlePosition={ [weak self] percent in guard let self else {return "host closed"};return self.applyChromeSubtitlePosition(percent) }
            controls.embeddedSourceCrop={ [weak self] source,crop in
                guard let self,self.sourceURL?.path==source,let session=self.session else{return "source/session changed"}
                let result=session.setSourceCrop(x:Double(crop.minX),y:Double(crop.minY),width:Double(crop.width),height:Double(crop.height))
                return result == .applied ? nil:String(describing:result)
            }
            controls.embeddedCropWindow={ [weak self] frame,aspect,finished in
                self?.hostWindow?.applyCropFrame(frame,aspect:aspect,finished:finished) ?? false
            }
            root.addSubview(controls);chrome=controls;content=root
        } else {
            let pause = NSButton(title: "Play / Pause", target: self, action: #selector(togglePause))
            let seek = NSButton(title: "Seek seconds", target: self, action: #selector(seek))
            let mute = NSButton(title: "Mute", target: self, action: #selector(toggleMute))
            let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: self, action: #selector(changeVolume(_:)))
            seekValue.widthAnchor.constraint(equalToConstant: 72).isActive = true
            let subtitles = NSButton(title: "Text subtitles", target: self, action: #selector(chooseTextSubtitles(_:)))
            let controls = NSStackView(views: [pause, seekValue, seek, mute, slider, subtitles])
            controls.orientation = .horizontal
            controls.spacing = 12
            let stack = NSStackView(views: [video, controls, status])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            content=stack
        }
        let host = GorAVHostWindow(contentView: content,playerWindow:playerWindow) { [weak self] transform in
            guard let self else { return }
            guard let session = self.session else { return }
            let outcome = session.setHostTransform(panX: transform.panX, panY: transform.panY, log2Zoom: transform.zoom)
            if outcome != .applied { self.fail(Refusal.unsupportedCapability("host transform refused: \(outcome)")) }
        }
        hostWindow = host
        host.onClose = { [weak self] in self?.closeSession() }
        host.onCropInterruption = { [weak self] in self?.chrome?.interruptCropMotion() }
        window = host.window
        host.window.title = inWindowChrome ? "gor":"gor - gorav integration"
        if !inWindowChrome {video.heightAnchor.constraint(greaterThanOrEqualToConstant:180).isActive=true}
        status.lineBreakMode = .byTruncatingTail
    }
    required init?(coder: NSCoder) { nil }

    func open(file: String?) {
        hostWindow?.show();chrome?.startPolling()
        guard let file, !file.isEmpty else { fail(Refusal.missingSource); return }
        open(SourceContext(path: file))
    }
    func open(_ context: SourceContext) {
        guard session == nil, task == nil else { fail(Refusal.unsupportedCapability("replace requires definitive teardown")); return }
        guard !context.path.contains("://"), context.headers.isEmpty, context.cookies == nil,
              context.startSeconds.isFinite, context.startSeconds >= 0 else {
            fail(Refusal.unsupportedSourceContext); return
        }
        sourceURL = URL(fileURLWithPath: context.path)
        let next = beginSession(originalMediaID: context.path)
        let token = identity
        task = Task { [weak self] in
            do {
                try await next.open(path: context.path)
                guard let self, self.identity == token else { await next.tearDown(); return }
                if context.startSeconds > 0 { try await next.seek(toSeconds: context.startSeconds) }
                self.preparedPlayback = PreparedShotPlayback(backend: GorAVLivePreparedAdapter(session: next, source: URL(fileURLWithPath: context.path)))
                self.task = nil
            } catch {
                await next.tearDown()
                guard let self, self.identity == token else { return }
                self.task = nil
                self.session = nil
                self.preparedPlayback = nil
                self.fail(error)
            }
        }
    }
    /// T4 M1 gap 1: remote stream open for magnet/IPTV/archive sources after
    /// gor-side resolution. Admission is caller-side (GorAVStreamAdmission);
    /// the vendored gorav OpenURLRouter stays the authoritative classifier and
    /// typed-refuses anything outside its direct-remote class. Needs vendored
    /// gorav >= 02251193 (R3 session open(url:)); the vendor sync is the
    /// delivery lane's seam.
    func open(url: String) {
        hostWindow?.show();chrome?.startPolling()
        guard session == nil, task == nil else { fail(Refusal.unsupportedCapability("replace requires definitive teardown")); return }
        guard !url.isEmpty else { fail(Refusal.missingSource); return }
        sourceURL = URL(string: url)
        let next = beginSession(originalMediaID: url)
        let token = identity
        task = Task { [weak self] in
            do {
                try await next.open(url: url)
                guard let self, self.identity == token else { await next.tearDown(); return }
                self.task = nil
            } catch {
                await next.tearDown()
                guard let self, self.identity == token else { return }
                self.task = nil
                self.session = nil
                self.preparedPlayback = nil
                self.fail(error)
            }
        }
    }

    /// Shared session bring-up for local and remote opens: observation state,
    /// identity, event tap and host-window sizing are identical for both.
    private func beginSession(originalMediaID: String) -> GorAVEmbeddedSession {
        observed = EngineObservedState()
        volumeSessionReady = false
        lastVideoDimensions = nil
        let token = UUID()
        identity = token
        // Same master target passed to mpv's photon-menu-enabled at launch.
        // Capture once per opening; live controls are a separate candidate.
        let photonOwner=NSApp.delegate as? AppDelegate
        livePhotonTarget=photonOwner?.photonEnabled ?? true
        let photonFamilies=photonOwner?.goravPhotonFamilyTargets ?? (sharp:true,grain:true)
        livePhotonSharpTarget=photonFamilies.sharp;livePhotonGrainTarget=photonFamilies.grain
        let next = GorAVEmbeddedSession(hostView: video, runID: token.uuidString)
        session = next
        // Native stereo-look input route (Ops nativefeed contract):
        // candidate-static initialization at this real host site; the
        // per-lane grounding is documented at
        // Self.stereoLookNativeInitial. The source-origin generation
        // increments per session (Ops v5).
        stereoLookSourceGeneration &+= 1
        let openSourcePath = originalMediaID
        let openGeneration = stereoLookSourceGeneration
        stereoLookNativeOwner.install(session: token, source: openSourcePath,
                                      generation: openGeneration,
                                      initial: Self.stereoLookNativeInitial)
        resetNativeStereoEntry(origin: StereoLookCommandOrigin(session: token,
            source: openSourcePath, generation: openGeneration), original: originalMediaID)
        // Same-session source ADOPTION reset (Ops final v4 finding) +
        // ORIGIN re-point (Ops v5): the session drives this
        // synchronously from rebindStereoGlue with the adopted source's
        // path. The re-install drops every accepted lane of the old
        // source; the generation increments AND the embedded command
        // closure is re-pointed, so a command queued BEFORE the
        // adoption still carries the old (source, generation) and is
        // refused after it.
        next.onStereoSourceAdopted = { [weak self] adoptedPath in
            guard let self, self.identity == token else { return }
            self.stereoLookSourceGeneration &+= 1
            let adoptedGeneration = self.stereoLookSourceGeneration
            self.stereoLookNativeOwner.install(session: token, source: adoptedPath,
                                               generation: adoptedGeneration,
                                               initial: Self.stereoLookNativeInitial)
            self.resetNativeStereoEntry(origin: StereoLookCommandOrigin(session: token,
                source: adoptedPath, generation: adoptedGeneration))
            self.refreshNativeStereoEntry()
            self.chrome?.embeddedCommand = { [weak self] line in
                self?.handleChromeCommand(line, origin: StereoLookCommandOrigin(
                    session: token, source: adoptedPath, generation: adoptedGeneration))
            }
        }
        // Per-frame pull provider, bound to THIS session's token: a
        // closure that outlives the session gets nil, never another
        // session's input. Custody rides the package type.
        // owner14 coherence (v14 review): the pull-model provider
        // hands the presenter's sampled context THROUGH to the owner -
        // the owner vends nil on a nil/invalid context, so the
        // presenter's frame/target correspondence proof gates the
        // input exactly as the contract intends.
        next.installStereoHostStateProvider { [weak self] context in
            guard let self, let receipt=self.nativeStereoReceipt,
                  self.nativeStereoIntent.hasAcceptedSourceEvidence(nativeEntryView(receipt)),
                  self.session?.nativeStereoEntryIsCurrent(receipt) == true else { return nil }
            var input = self.stereoLookNativeOwner.pullInput(expectedSession: token, context: context)
            if let origin = self.nativeStereoOrigin,
               self.nativeStereoIntent.hasCurrentRestrictedProjectionIntent(nativeEntryView(receipt),
                   state: ThreeDStore.shared.snapshot, revision: ThreeDStore.shared.revision,
                   origin: origin) {
                return input
            }
            // Preserve generic host behavior, but never lend projection the
            // old capability after a Store/source intent transition.
            input?.restrictedProjectionAdmission = nil
            return input
        }
        // ORIGIN-bound command transport (Ops corrections: receipt-time
        // identity is not an origin fence; the session token alone is
        // not a source fence): the closure captures (session, source,
        // generation) AT INSTALL TIME, so every queued vr180_look
        // command carries what it was queued under. Re-pointed per
        // session and per adoption; beginCloseSession nils it; the
        // window-setup closure (origin nil) only applies before the
        // first session.
        chrome?.embeddedCommand = { [weak self] line in
            self?.handleChromeCommand(line, origin: StereoLookCommandOrigin(
                session: token, source: openSourcePath, generation: openGeneration))
        }
        next.onEvent = { [weak self, weak next] event in
            guard let self, self.identity == token else { return }
            self.consume(event)
            switch event {
            case .opened, .firstFrame, .timePos, .seekCommitted:
                self.refreshNativeStereoEntry()
            default: break
            }
            switch event {
            case .firstFrame, .timePos:
                Task { [weak self, weak next] in
                    guard let next else { return }
                    let snapshot = await next.snapshot()
                    guard let self, self.identity == token, let geometry = snapshot.effectiveVideo else { return }
                    self.observed.videoParams.displayWidth = Double(geometry.frameWidth)
                    self.observed.videoParams.displayHeight = Double(geometry.frameHeight)
                    self.observed.displayWidth = Double(geometry.frameWidth)
                    self.observed.displayHeight = Double(geometry.frameHeight)
                    EngineObservationCenter.shared.ingest(self.observed)
                    self.chrome?.acceptEmbedded(self.observed,source:self.sourceURL);self.onObservation?(self.observed)
                    let dims = (geometry.frameWidth, geometry.frameHeight)
                    if self.lastVideoDimensions?.0 != dims.0 || self.lastVideoDimensions?.1 != dims.1 {
                        self.lastVideoDimensions = dims
                        self.hostWindow?.open(videoWidth: Double(dims.0), height: Double(dims.1))
                    }
                }
            default: break
            }
            print("[engine] backend=gorav candidate=\(Self.candidate) session=\(token.uuidString) event=\(event)")
        }
        return next
    }
    private func consume(_ event: EmbeddedEvent) {
        switch event {
        case .opened:
            postOpenFallback.opened()
            observed.idleActive = false; observed.eofReached = false
            volumeSessionReady = true
            applyVolume()
            installLivePhotonForCurrentSession()
        case .firstFrame: break
        case .paused: observed.paused = true
        case .resumed: observed.paused = false
        case .seekCommitted:
            observed.timePos = nil
            // A seek can advance the renderer epoch. Rebind this same target
            // only after the session reports the real committed transition.
            installLivePhotonForCurrentSession()
        case .durationKnown(let seconds): observed.duration = seconds
        case .timePos(let seconds, _): observed.timePos = seconds
        case .volumeChanged: break
        case .ended(let reason):
            volumeSessionReady = false
            gateTerminalCount += 1
            observed.idleActive = true; observed.eofReached = reason == "eof"
        case .failed(let reason):
            if onPostOpenFailure != nil, GorAVPostOpenFallback.isTerminal(reason), postOpenFallback.claim(reason) {
                gateFailureCount += 1
                chrome?.spineUI.showMPVOSD("gorav failed: " + String(reason.prefix(160)) + "; switching to mpv", force: true)
                print("[engine] backend=gorav post-open failure=\(reason); fallback pending definitive teardown")
                onPostOpenFailure?(reason)
            } else if !postOpenFallback.wasClaimed {
                fail(Refusal.unsupportedCapability(reason))
            }
        case .audioUnbound: fail(Refusal.unsupportedCapability("audioUnbound"))
        }
        EngineObservationCenter.shared.ingest(observed)
        chrome?.acceptEmbedded(observed,source:sourceURL);onObservation?(observed)
        if case .timePos = event {
            let time = observed.timePos.map { String(format: "%.2f", $0) } ?? "unknown"
            let duration = observed.duration.map { String(format: "%.2f", $0) } ?? "unknown"
            status.stringValue = "gorav: \(time) / \(duration) seconds"
        } else { status.stringValue = "gorav: \(event)" }
    }
    @objc private func chooseTextSubtitles(_ sender: NSButton) {
        guard let session else { fail(Refusal.missingSource); return }
        let menu = NSMenu(title: "Text subtitles")
        let hide = NSMenuItem(title: "Off", action: #selector(selectTextSubtitle(_:)), keyEquivalent: "")
        hide.target = self; hide.representedObject = ""; menu.addItem(hide)
        for candidate in session.subtitleCandidates where candidate.format == "srt" {
            let item = NSMenuItem(title: URL(fileURLWithPath: candidate.path).lastPathComponent,
                                  action: #selector(selectTextSubtitle(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = candidate.path; menu.addItem(item)
        }
        if menu.items.count == 1 {
            let none = NSMenuItem(title: "No local SRT sidecar found", action: nil, keyEquivalent: "")
            none.isEnabled = false; menu.addItem(none)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    @objc private func selectTextSubtitle(_ sender: NSMenuItem) {
        guard let session, let path = sender.representedObject as? String else { return }
        if path.isEmpty { session.setSubtitleVisible(false, slot: .primary); return }
        let token = identity
        Task { [weak self, weak session] in
            guard let session else { return }
            let result = await session.selectSubtitle(path: path, slot: .primary)
            guard let self, self.identity == token, self.session === session else { return }
            switch result {
            case .selected: session.setSubtitleVisible(true, slot: .primary)
            case .refused(let refusal): self.fail(Refusal.unsupportedCapability("text subtitle: \(refusal)"))
            case .noExactSidecar: self.fail(Refusal.unsupportedCapability("no exact text sidecar"))
            }
        }
    }
    /// Ordinary local and remote openings both reach this after the actual
    /// presenter exists. This is sharp/grain live only, not full Photon parity.
    private func installLivePhotonForCurrentSession() {
        guard let current=session else{return}
        guard setLivePhotonProducer(livePhotonTarget,session:current,sourceIdentity:identity) else {
            chrome?.setEngineRefusalHUD("gorav sharp/grain activation refused")
            return
        }
    }
    func gatePhotonTelemetryRows()->[String]? {session?.completedPhotonTelemetry()?.rows}
    func gatePhotonSnapshot()->PhotonProducerSnapshot? {session?.completedPhotonTelemetry()?.snapshot}
    /// Explicit qualification hook retained for older native tests. Production
    /// bring-up does not call this hook or need a test to switch effects on.
    func activatePhotonProducerCandidate()->Bool {
        guard let current=session else{return false}
        return setLivePhotonProducer(true,session:current,sourceIdentity:identity)
    }
    private func setLivePhotonProducer(_ enabled:Bool,session current:GorAVEmbeddedSession,sourceIdentity:UUID)->Bool {
        guard identity==sourceIdentity,session===current,current.setPhotonProducerEnabled(enabled,sharp:livePhotonSharpTarget,grain:livePhotonGrainTarget) else{return false}
        photonHUDTask?.cancel();photonHUDTask=nil;photonHUDRevision=nil
        chrome?.spineUI.clearPhotonHUD()
        guard enabled else{return true}
        photonHUDTask=Task { @MainActor [weak self,weak current] in
            while !Task.isCancelled {
                guard let self,let current,self.identity==sourceIdentity,self.session===current else{return}
                self.publishPhotonHUD(sourceIdentity:sourceIdentity,session:current)
                try? await Task.sleep(nanoseconds:250_000_000)
            }
        }
        return true
    }
    private func publishPhotonHUD(sourceIdentity:UUID,session expected:GorAVEmbeddedSession) {
        guard identity==sourceIdentity,session===expected else{return}
        if let failure=expected.photonProducerFailure() {
            if photonHUDRevision != nil {chrome?.spineUI.clearPhotonHUD();photonHUDRevision=nil}
            chrome?.setEngineRefusalHUD(String(failure.prefix(160)))
            return
        }
        guard let telemetry=expected.completedPhotonTelemetry() else {
            if photonHUDRevision != nil {chrome?.spineUI.clearPhotonHUD();photonHUDRevision=nil}
            return
        }
        guard photonHUDRevision != telemetry.snapshot.revision else{return}
        photonHUDRevision=telemetry.snapshot.revision
        chrome?.spineUI.showPhotonHUD(telemetry.rows.joined(separator:"‖"))
    }
    func showRoute(_ line:String) {chrome?.showEngineRoute(line)}
    private var subtitleVisible=true
    private var subtitleCycleIndex=0   // 0 = off, n = nth SRT candidate; set only after the session accepted it
    private func osd(_ text:String) {chrome?.spineUI.showMPVOSD(text,duration:1.5,force:true)}
    private func applySubtitleVisible(_ visible:Bool) {
        guard let session,session.setSubtitleVisible(visible,slot:.primary) else {fail(Refusal.unsupportedCapability("subtitle visibility: no open subtitle owner"));return}
        subtitleVisible=visible;osd(visible ? "subtitles on" : "subtitles off")
    }
    private func selectTextSubtitle(path:String,candidateIndex:Int?=nil) {
        guard let session else {fail(Refusal.missingSource);return}
        guard path.lowercased().hasSuffix(".srt") else {fail(Refusal.unsupportedCapability("text subtitle: only srt"));return}
        let token=identity
        Task { [weak self,weak session] in
            guard let session else {return}
            let result=await session.selectSubtitle(path:path,slot:.primary)
            guard let self,self.identity==token,self.session===session else {return}
            switch result {
            case .selected:
                if session.setSubtitleVisible(true,slot:.primary) {
                    self.subtitleVisible=true
                    if let candidateIndex {self.subtitleCycleIndex=candidateIndex}
                    self.osd("subtitle: "+URL(fileURLWithPath:path).lastPathComponent)
                } else {self.fail(Refusal.unsupportedCapability("text subtitle: owner closed"))}
            case .refused(let refusal):self.fail(Refusal.unsupportedCapability("text subtitle: \(refusal)"))
            case .noExactSidecar:self.fail(Refusal.unsupportedCapability("no exact text sidecar"))
            }
        }
    }
    private func cycleTextSubtitle(forward:Bool) {
        guard let session else {fail(Refusal.missingSource);return}
        let candidates=session.subtitleCandidates.filter{$0.format=="srt"}
        guard !candidates.isEmpty else {fail(Refusal.unsupportedCapability("no local srt sidecar to cycle"));return}
        let slots=candidates.count+1
        let next=(subtitleCycleIndex+(forward ? 1 : slots-1))%slots
        if next==0 {applySubtitleVisible(false);if subtitleVisible==false {subtitleCycleIndex=0};return}
        selectTextSubtitle(path:candidates[next-1].path,candidateIndex:next)
    }
    private func cycleAudioTrack(forward:Bool) {
        guard let session else {fail(Refusal.missingSource);return}
        let token=identity
        gateControlTask=Task { [weak self,weak session] in
            guard let session else {return}
            let snapshot=await session.audioTrackInventory()
            guard let self,self.identity==token,self.session===session else {return}
            guard let inventory=snapshot,inventory.tracks.count>1 else {
                self.fail(Refusal.unsupportedCapability("audio track: fewer than two tracks or inventory unavailable"));return
            }
            let tracks=inventory.tracks.sorted{$0.index<$1.index}
            let at=tracks.firstIndex{$0.index==inventory.activeIndex} ?? 0
            let target=tracks[(at+(forward ? 1 : tracks.count-1))%tracks.count]
            do {
                try await session.setAudioTrack(.index(target.index))
                guard self.identity==token,self.session===session else {return}
                self.osd("audio track: "+[target.language,target.title].compactMap{$0}.joined(separator:" ")+" (#\(target.index))")
            } catch {if self.identity==token,self.session===session {self.fail(error)}}
        }
    }
    /// Menu/keys chapter step (MENU-CAPABILITY-PARITY slice 1): mpv `add chapter`
    /// routed to the delivered chapter session API. Only +/-1 routes (one
    /// navigation per call); every other delta refuses loudly via the typed
    /// planner - no silent clamp, floor or no-op. Identity-fenced like
    /// cycleAudioTrack; a superseded or retired session drops the result.
    private func navigateChapterMenu(delta:Double?) {
        switch ChapterMenuStep.direction(forDelta:delta) {
        case .failure(let refusal):
            fail(Refusal.unsupportedCapability(refusal.token))
        case .success(let direction):
            guard let session else {fail(Refusal.missingSource);return}
            let token=identity
            gateControlTask=Task { [weak self,weak session] in
                guard let session else {return}
                do {
                    let inventory=try session.chapterInventory()
                    let landed=try await session.navigateChapter(direction,expected:inventory.identity)
                    guard let self,self.identity==token,self.session===session else {return}
                    let chapters=inventory.inventory.chapters
                    if let at=chapters.firstIndex(where:{$0.startSeconds==landed}) {
                        self.osd("chapter: \(at+1)/\(chapters.count)")
                    } else {
                        self.osd(String(format:"chapter: %.1fs",landed))
                    }
                } catch {
                    guard let self,self.identity==token,self.session===session else {return}
                    self.fail(error)
                }
            }
        }
    }
    /// Synchronous typed result: nil when the session accepted the scale, else the refusal text.
    private func applyChromeSubtitlePosition(_ percent:Double)->String? {
        guard let session,volumeSessionReady else{return "no open session"}
        if let refusal=session.setSubtitlePosition(percent) {return "subtitle position: \(refusal)"}
        chrome?.acceptEmbeddedSubtitlePosition(percent)
        return nil
    }
    private func applyChromeSubtitleScale(_ scale:Double)->String? {
        guard scale.isFinite else {return "subtitle font scale must be finite"}
        guard let session,volumeSessionReady else {return "no open session"}
        if let refusal=session.setSubtitleFontScale(scale) {return "subtitle font scale: \(refusal)"}
        return nil
    }
    private func applyChromeDelay(_ property:String,_ seconds:Double)->String? {
        guard seconds.isFinite else {return "delay must be finite"}
        guard let session,volumeSessionReady else {return "no open session"}
        if property == "sub-delay" {
            if let refusal=session.setSubtitleDelay(seconds,slot:.primary) {return "subtitle delay: \(refusal)"}
            return nil
        }
        do {try session.setAudioDelay(seconds:seconds);return nil} catch {return "audio delay: \(error)"}
    }
    func handleChromeCommand(_ line:String, origin:StereoLookCommandOrigin?=nil) {
        guard let data=line.data(using:.utf8),let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let command=object["command"] as? [Any],let name=command.first as? String else {return}
        func string(_ index:Int)->String? {guard command.indices.contains(index) else {return nil};return command[index] as? String}
        func number(_ index:Int)->Double? {guard command.indices.contains(index) else {return nil};if let n=command[index] as? NSNumber {return n.doubleValue};return Double(command[index] as? String ?? "")}
        switch name {
        case "cycle" where string(1)=="pause":togglePause()
        case "cycle" where string(1)=="mute":toggleMute()
        case "cycle" where string(1)=="fullscreen":setFullscreen(!(hostWindow?.fullscreen ?? false))
        case "cycle" where string(1)=="ontop":hostWindow?.setOnTop(window?.level != .floating)
        case "seek":
            guard let seconds=number(1),seconds.isFinite else {return}
            let mode=string(2) ?? "relative"
            guard let target=Self.chromeSeekTarget(seconds:seconds,mode:mode,time:observed.timePos,duration:observed.duration) else {
                fail(Refusal.unsupportedCapability("seek requires a supported mode and known finite timeline"));return
            }
            guard let session else {return}
            gateControlTask=Task {do {try await session.seek(toSeconds:target)} catch {fail(error)}}
        case "set_property" where string(1)=="pause":
            guard command.count>2,let desired=command[2] as? Bool,let session else {return}
            gateControlTask=Task {do {try await session.setPaused(desired)} catch {fail(error)}}
        case "set_property" where string(1)=="mute":
            if command.count > 2, let desired = command[2] as? Bool { muted = desired; applyVolume() }
        case "set_property" where string(1)=="volume":
            if let value=number(2),value.isFinite {volume=Float(max(0,min(100,value))/100);applyVolume()}
        case "add" where string(1)=="volume":
            if let value=number(2),value.isFinite {volume=max(0,min(1,volume+Float(value/100)));applyVolume()}
        case "script-message-to" where string(1)=="gor_fit":
            switch string(2) {
            case "zoom":if let value=number(3) {hostWindow?.zoom(value)}
            case "move":if let x=number(3),let y=number(4) {hostWindow?.move(dx:x,dy:y)}
            case "hold":
                if let x=number(3),let y=number(4),let z=number(5),
                   x.isFinite,y.isFinite,z.isFinite {hostWindow?.hold(dx:x,dy:y,dz:z)}
            case "reset":hostWindow?.resetPicture()
            case "fit":hostWindow?.fit()
            default:fail(Refusal.unsupportedCapability("fit command"))
            }
        case "script-message-to" where string(1)=="vr180_look":
            /// NATIVE typed acceptance (Ops nativefeed contract): the
            /// existing VR180Controller dispatches arrive here through
            /// PPController.ipcCommand l.4378-4379. Typed parse +
            /// validated acceptance into the native input owner under
            /// the command's QUEUE-TIME origin; every refusal fails
            /// loud exactly like any other unsupported chrome command.
            /// Nothing is forwarded to an mpv path.
            switch StereoLookNativeCommands.parse(Array(command.dropFirst(2))) {
            case .success(let parsed):
                if let refusal = stereoLookNativeOwner.accept(parsed, origin: origin) {
                    fail(Refusal.unsupportedCapability("vr180_look: \(refusal)"))
                }
            case .failure(let refusal):
                fail(Refusal.unsupportedCapability("vr180_look: \(refusal)"))
            }
        case "set_property" where string(1)=="sub-visibility":
            let desired:Bool?=(command.count>2 ? (command[2] as? Bool ?? (string(2).map{$0=="yes"||$0=="true"})) : nil)
            guard let desired else {return}
            applySubtitleVisible(desired)
        case "cycle" where string(1)=="sub-visibility":applySubtitleVisible(!subtitleVisible)
        case "sub-add":
            if let path=string(1) {selectTextSubtitle(path:path)} else {fail(Refusal.unsupportedCapability("sub-add without path"))}
        case "cycle" where string(1)=="sub":cycleTextSubtitle(forward:string(2) != "down")
        case "cycle" where string(1)=="audio":cycleAudioTrack(forward:string(2) != "down")
        case "add" where string(1)=="chapter":navigateChapterMenu(delta:number(2))
        case "loadfile":if let path=string(1) {(NSApp.delegate as? AppDelegate)?.launchMPV(file:path)}
        case "stop":closeSession()
        case "quit","quit-watch-later":NSApp.terminate(nil)
        case "set_property" where string(1)=="audio-delay":
            if let value=number(2),let session {do {try session.setAudioDelay(seconds:value)} catch {fail(error)}}
        case "set_property" where string(1)=="sub-pos":
            if let value=number(2),let reason=applyChromeSubtitlePosition(value) {fail(Refusal.unsupportedCapability(reason))}
        case "set_property" where string(1)=="sub-delay":
            if let value=number(2),let session,let refusal=session.setSubtitleDelay(value,slot:.primary) {fail(Refusal.unsupportedCapability("subtitle delay: \(refusal)"))}
        case "keypress":
            /// KEYPRESS-PARITY slice 2: mpv default bindings whose gorav
            /// equivalent is already routed re-enter this same command path;
            /// every other key keeps the byte-identical loud refusal below.
            if let key=string(1),let translated=MPVDefaultKeymap.command(forKey:key) {handleChromeCommand(translated, origin:origin)}
            else {fail(Refusal.unsupportedCapability("keypress"))}
        default:
            let detail:String
            if name=="script-message-to" {detail="script "+(string(1) ?? "unknown")+" "+(string(2) ?? "unknown")}
            else if ["set_property","add","cycle","get_property"].contains(name) {detail=name+" "+(string(1) ?? "unknown")}
            else {detail=name}
            fail(Refusal.unsupportedCapability(String(detail.prefix(96))))
        }
    }
    // Resolve only against observed timeline values. Unknown is not zero.
    // The backend has no keyframe/exact distinction, but admits the standard
    // mpv precision flags without treating arbitrary substrings as modes.
    static func chromeSeekTarget(seconds:Double,mode:String,time:Double?,duration:Double?)->Double? {
        guard seconds.isFinite else {return nil}
        let parts=mode.split(separator:"+",omittingEmptySubsequences:false).map(String.init)
        guard let kind=parts.first,parts.count<=2,
              parts.count==1 || ["exact","keyframes"].contains(parts[1]) else {return nil}
        let target:Double
        switch kind {
        case "absolute":target=seconds
        case "relative":
            guard let time,time.isFinite,time>=0 else {return nil}
            target=time+seconds
        case "absolute-percent":
            guard let duration,duration.isFinite,duration>0 else {return nil}
            target=(seconds/100)*duration
        case "relative-percent":
            guard let time,time.isFinite,time>=0,let duration,duration.isFinite,duration>0 else {return nil}
            target=time+(seconds/100)*duration
        default:return nil
        }
        guard target.isFinite else {return nil}
        return max(0,target)
    }
    var pictureInPicture:Bool {hostWindow?.pictureInPicture ?? false}
    func setFullscreen(_ enabled: Bool) { hostWindow?.setFullscreen(enabled) }
    func setPiP(_ enabled: Bool) { hostWindow?.setPiP(enabled) }
    @objc private func togglePause() {
        guard let session else { fail(Refusal.missingSource); return }
        // native111 (observability): the toggle route leaves a typed trace.
        // native107's resume toggle completed with zero trace (no resumed/
        // failed event, no refusal print); the request line is printed
        // synchronously so a swallowed task is distinguishable from a
        // no-op, the outcome line records the states the toggle observed.
        print("[engine] backend=gorav candidate=\(Self.candidate) togglePause requested")
        gateControlTask = Task {
            do {
                let before = await session.lifecycleState
                try await session.togglePause()
                let after = await session.lifecycleState
                print("[engine] backend=gorav candidate=\(Self.candidate) togglePause \(before.rawValue) -> \(after.rawValue)")
            } catch { fail(error) }
        }
    }
    @objc private func seek() {
        guard let session, let value = Double(seekValue.stringValue), value.isFinite, value >= 0 else {
            fail(Refusal.unsupportedCapability("seek requires finite nonnegative seconds")); return
        }
        gateControlTask = Task { do { try await session.seek(toSeconds: value) } catch { fail(error) } }
    }
    @objc private func changeVolume(_ sender: NSSlider) {
        volume = sender.floatValue
        applyVolume()
    }
    @objc private func toggleMute() { muted.toggle(); applyVolume() }
    private func applyVolume() {
        // Chrome installs controls before the media session is ready. Retain
        // the latest requested value/mute intent, never call an unready sink.
        guard volumeSessionReady, let session else { return }
        guard session.setVolume(muted ? 0 : volume) else {
            fail(Refusal.unsupportedCapability("volume unavailable")); return
        }
        // Publish only after the real sink accepts. No IPC is sent by this ack.
        chrome?.acceptEmbeddedVolume(volume)
    }
    func closeSession() {
        postOpenFallback.cancel()
        beginCloseSession()
    }
    /// Fallback owns a different close intent from a user close. A user close
    /// before/during this await cancels the permit and cannot replay a file.
    func drainForPostOpenFallback(_ permit: GorAVPostOpenFallback) async -> Bool {
        guard permit === postOpenFallback, permit.beginDrain() else { return false }
        beginCloseSession()
        await gateCloseTask?.value
        await gateWindowCloseTask?.value
        return permit.drained(definitivelyClosed: gateCloseReport?.cleanShutdown == true)
    }
    private func beginCloseSession() {
        photonHUDTask?.cancel();photonHUDTask=nil;photonHUDRevision=nil
        chrome?.spineUI.clearPhotonHUD()
        volumeSessionReady = false
        identity = UUID()
        let opening = task
        task?.cancel()
        task = nil
        let previous = session
        // Native stereo-look input route teardown (Ops nativefeed
        // contract; narrow coexistence with the G5 close/barrier lane
        // approved conceptually 6:41:23): drop the provider (immediate
        // cached-state clear) and uninstall the owner BETWEEN binding
        // `previous` and clearing `session`, preserving the G5 first
        // gateWindowCloseTask and both awaits untouched.
        previous?.stereoProjectionRefusalHandler = nil
        previous?.stereoDistanceTraceHandler = nil
        previous?.removeStereoHostStateProvider()
        stereoLookNativeOwner.uninstall()
        resetNativeStereoEntry(origin: nil)
        session = nil
        preparedPlayback = nil
        previous?.fence()
        // Window reuse must await both media teardown and the actual UI fade
        // completion. Repeated close retains this first in-flight barrier.
        if gateWindowCloseTask == nil, let closingWindow = hostWindow {
            gateWindowCloseTask = Task { await closingWindow.closeAndWait() }
        }
        chrome?.embeddedCommand=nil
        chrome?.embeddedDelay=nil
        chrome?.stopEmbeddedCropWork()
        chrome?.embeddedSourceCrop=nil;chrome?.embeddedCropWindow=nil
        chrome?.embeddedSubtitleScale=nil
        chrome?.embeddedSubtitlePosition=nil
        observed = EngineObservedState()
        sourceURL = nil
        // close() performs the same teardown and returns the measured typed
        // report; a repeated close is a typed no-op report, never a hang.
        if let previous {
            gateCloseReport = nil
            gateCloseTask = Task {
                // A cancelled open may still own teardown. Await it first.
                await opening?.value
                var report = await previous.close()
                // The engine sets tornDown before its asynchronous leg drain.
                // alreadyClosed alone is not definitive closure evidence.
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                while await previous.lifecycleState != .closed, ContinuousClock.now < deadline {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                report.cleanShutdown = await previous.lifecycleState == .closed
                gateCloseReport = report
            }
        }
        // A repeated close with session == nil must retain the in-flight task
        // and its eventual report instead of dropping the teardown barrier.
    }
    // Explicit native gate uses the actual UI action -> session route.
    // No alternative playback implementation or fabricated observations.
    var gateWindowVisible: Bool { window?.isVisible == true }
    func gateSnapshot() async -> EmbeddedSnapshot? { await session?.snapshot() }
    func gateObservation(_ property: ObservationProperty) -> ObservationValue? {
        session?.observations.read(property)
    }
    func gatePauseAction() async { togglePause(); await gateControlTask?.value }
    func gateSeekAction(seconds: Double) async {
        seekValue.stringValue = String(seconds); seek(); await gateControlTask?.value
    }
    func gateCloseAction() async {
        closeSession()
        await gateCloseTask?.value
        await gateWindowCloseTask?.value
    }
    private func fail(_ error: Error) {
        guard !postOpenFallback.wasClaimed else { return }
        gateFailureCount += 1
        // Typed tokens only: never include a source URL, cookie or private path.
        status.stringValue = "gorav refused: \(error)"
        chrome?.spineUI.showMPVOSD("gorav unavailable: "+String(String(describing:error).prefix(160)),force:true)
        print("[engine] backend=gorav refusal=\(error); no runtime replay on mpv")
    }
}

/// Narrow live-session adapter. It neither opens an idle session nor restarts
/// audio, and it never turns a past requested edit into a new future edit.
@MainActor
private final class GorAVLivePreparedAdapter: PreparedShotSessionBackend {
    private let session: GorAVEmbeddedSession
    private let source: URL
    private var adoptedID: UUID?
    private var audioBinding: UUID?
    init(session: GorAVEmbeddedSession, source: URL) {
        self.session = session; self.source = source
    }
    func applyPreparedShot(_ request: PreparedShotPlayback.Request) async throws -> PreparedShotPlayback.Receipt {
        guard request.sourceAudioURL == source, !request.rebaseStartTime,
              request.preserveRunningAudio, let epoch = session.preparedShotEpoch,
              request.filmTime.isFinite, request.filmTime >= 0,
              request.filmTime * 1_000_000 < Double(Int64.max) else {
            throw GorAVPlayerHost.Refusal.unsupportedCapability("prepared source context")
        }
        guard let now = await session.preparedShotFilmTime(), request.filmTime > now else {
            throw GorAVPlayerHost.Refusal.unsupportedCapability("prepared handoff requires a future boundary; no retiming")
        }
        let time = try RationalTime(value: Int64((request.filmTime * 1_000_000).rounded(.down)), timescale: 1_000_000)
        if request.operation == .adoptRunningSource {
            guard adoptedID == nil else { throw PreparedShotPlayback.Failure.receiptMismatch }
            let zero = try RationalTime(value: 0, timescale: 1)
            let initial = SourceRef(id: source.path, kind: .local, startOffset: zero)
            let adopted = try await session.prepare(PreparedShot(shotID: request.sessionID,
                video: initial, audio: initial, filmClockEpoch: epoch))
            guard adopted.shotID == request.sessionID, adopted.epoch == epoch,
                  adopted.audioBindingPreserved, let binding = adopted.audioBindingID else {
                throw PreparedShotPlayback.Failure.receiptMismatch
            }
            adoptedID = adopted.shotID; audioBinding = binding
        } else {
            guard adoptedID == request.sessionID else { throw PreparedShotPlayback.Failure.noSourceSession }
        }
        let committed: PreparedShotCommitReceipt
        do {
            committed = try await session.replaceVideoPreservingFilmPTS(at: time, path: request.videoURL.path)
        } catch {
            // Release only if no video handoff committed. Never stop working audio.
            if await session.abortUncommittedPreparation() == .released {
                adoptedID = nil; audioBinding = nil
            }
            throw error
        }
        guard committed.shotID == request.sessionID, committed.epoch == epoch,
              committed.audioBindingID == audioBinding, committed.audioBindingPreserved,
              committed.committedAt == time else { throw PreparedShotPlayback.Failure.receiptMismatch }
        return PreparedShotPlayback.Receipt(sessionID: committed.shotID,
            operationID: request.operationID, videoURL: request.videoURL,
            sourceAudioURL: source, requestedFilmTime: request.filmTime,
            committedFilmTime: Double(committed.committedAt.value) / Double(committed.committedAt.timescale),
            rebased: false, preservedRunningAudio: committed.audioBindingPreserved)
    }
}
