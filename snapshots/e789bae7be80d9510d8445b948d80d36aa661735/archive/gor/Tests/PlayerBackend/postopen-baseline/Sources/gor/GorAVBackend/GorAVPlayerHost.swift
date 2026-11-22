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
    private(set) var observed = EngineObservedState()
    private(set) var sourceURL: URL?
    var currentTime: Double? { observed.timePos }
    private(set) var preparedPlayback: PreparedShotPlayback?
    private var lastVideoDimensions: (Int, Int)?
    private var session: GorAVEmbeddedSession?
    private var identity = UUID()
    private let video = NSView()
    private let status = NSTextField(labelWithString: "gorav: no media")
    private var task: Task<Void, Never>?
    private var gateControlTask: Task<Void, Never>?
    private var gateCloseTask: Task<Void, Never>?
    private(set) var gateFailureCount = 0
    private(set) var gateTerminalCount = 0
    /// Typed engine close report of the last closeSession teardown (native87);
    /// nil until a close completes in this session generation.
    private(set) var gateCloseReport: EmbeddedCloseReport?
    private var muted = false
    private var volume: Float = 1
    private var seekValue = NSTextField(string: "0")

    init(inWindowChrome:Bool=false) {
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
        let host = GorAVHostWindow(contentView: content) { [weak self] transform in
            guard let self else { return }
            guard let session = self.session else { return }
            let outcome = session.setHostTransform(panX: transform.panX, panY: transform.panY, log2Zoom: transform.zoom)
            if outcome != .applied { self.fail(Refusal.unsupportedCapability("host transform refused: \(outcome)")) }
        }
        hostWindow = host
        host.onClose = { [weak self] in self?.closeSession() }
        window = host.window
        host.window.title = inWindowChrome ? "gor":"gor - gorav integration"
        host.window.center()
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
        let next = beginSession()
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
        let next = beginSession()
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
    private func beginSession() -> GorAVEmbeddedSession {
        observed = EngineObservedState()
        lastVideoDimensions = nil
        let token = UUID()
        identity = token
        let next = GorAVEmbeddedSession(hostView: video, runID: token.uuidString)
        session = next
        next.onEvent = { [weak self, weak next] event in
            guard let self, self.identity == token else { return }
            self.consume(event)
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
        case .opened: observed.idleActive = false; observed.eofReached = false
        case .firstFrame: break
        case .paused: observed.paused = true
        case .resumed: observed.paused = false
        case .seekCommitted: observed.timePos = nil
        case .durationKnown(let seconds): observed.duration = seconds
        case .timePos(let seconds, _): observed.timePos = seconds
        case .volumeChanged: break
        case .ended(let reason):
            gateTerminalCount += 1
            observed.idleActive = true; observed.eofReached = reason == "eof"
        case .failed, .audioUnbound: gateFailureCount += 1
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
    func showRoute(_ line:String) {chrome?.showEngineRoute(line)}
    func handleChromeCommand(_ line:String) {
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
        case "set_property" where string(1)=="volume":
            if let value=number(2),value.isFinite {volume=Float(max(0,min(100,value))/100);applyVolume()}
        case "add" where string(1)=="volume":
            if let value=number(2),value.isFinite {volume=max(0,min(1,volume+Float(value/100)));applyVolume()}
        case "script-message-to" where string(1)=="gor_fit":
            switch string(2) {
            case "zoom":if let value=number(3) {hostWindow?.zoom(value)}
            case "move":if let x=number(3),let y=number(4) {hostWindow?.move(dx:x,dy:y)}
            case "reset":hostWindow?.resetPicture()
            case "fit":hostWindow?.fit()
            default:fail(Refusal.unsupportedCapability("fit command"))
            }
        case "loadfile":if let path=string(1) {(NSApp.delegate as? AppDelegate)?.launchMPV(file:path)}
        case "stop":closeSession()
        case "quit","quit-watch-later":NSApp.terminate(nil)
        case "set_property" where string(1)=="audio-delay":
            if let value=number(2),let session {do {try session.setAudioDelay(seconds:value)} catch {fail(error)}}
        case "set_property" where string(1)=="sub-delay":
            if let value=number(2),let session,let refusal=session.setSubtitleDelay(value,slot:.primary) {fail(Refusal.unsupportedCapability("subtitle delay: \(refusal)"))}
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
        guard let session, session.setVolume(muted ? 0 : volume) else {
            fail(Refusal.unsupportedCapability("volume unavailable")); return
        }
    }
    func closeSession() {
        identity = UUID()
        task?.cancel()
        task = nil
        let previous = session
        session = nil
        preparedPlayback = nil
        previous?.fence()
        hostWindow?.close()
        chrome?.embeddedCommand=nil
        observed = EngineObservedState()
        sourceURL = nil
        gateCloseReport = nil
        // close() performs the same teardown and returns the measured typed
        // report; a repeated close is a typed no-op report, never a hang.
        if let previous { gateCloseTask = Task { gateCloseReport = await previous.close() } }
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
    func gateCloseAction() async { closeSession(); await gateCloseTask?.value }
    private func fail(_ error: Error) {
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
