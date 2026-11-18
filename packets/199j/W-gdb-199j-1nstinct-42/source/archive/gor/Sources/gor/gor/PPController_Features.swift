// ================================================================
//  PPController_Features.swift - composed overlay feature controllers
//  Owns: drag/drop, music and IPTV modes, input, VR180, content dimming
//  Answers: I11 I45 · TRAP-04
//  Contract: PPController owns each feature and supplies callbacks
// ================================================================
//  Rules: Add a final feature class here; hold views weakly, route
//  calls to PPController through injected closures.
// ================================================================
import AppKit
import QuartzCore
// MARK: - DragDropHandler
// ================================================================
//  DragDropHandler - file drag routing
// ================================================================
// I11 / TRAP-04: match PPController.openMediaFile() routing for fonts, subtitles and media.
// Coupled: PPController.openMediaFile() (PPController.swift); edit both drag paths together.
final class DragDropHandler {
    private var lastDraggedURLs:      [URL]    = []
    private var dragInProgress                 = false
    private var dragStartLocation:    NSPoint  = .zero
    private var lastDragChangeCount:  Int      = 0
    private weak var window: NSWindow?
    private let stopTorrent: () -> Void
    private let streamTorrent: (String) -> Void
    private let openMediaFile: (String) -> Void
    private let photonEnabled: () -> Bool
    private let ipcCommand: (String) -> Void
    private let batchIPC: (String) -> Void
    init(
        window: NSWindow?,
        stopTorrent: @escaping () -> Void,
        streamTorrent: @escaping (String) -> Void,
        openMediaFile: @escaping (String) -> Void,
        photonEnabled: @escaping () -> Bool,
        ipcCommand: @escaping (String) -> Void,
        batchIPC: @escaping (String) -> Void
    ) {
        self.window = window
        self.stopTorrent = stopTorrent
        self.streamTorrent = streamTorrent
        self.openMediaFile = openMediaFile
        self.photonEnabled = photonEnabled
        self.ipcCommand = ipcCommand
        self.batchIPC = batchIPC
    }
    func start() {
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.dragStartLocation  = NSEvent.mouseLocation
            self?.dragInProgress     = false
            self?.lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }
            let cur = NSEvent.mouseLocation
            let dx  = cur.x - self.dragStartLocation.x
            let dy  = cur.y - self.dragStartLocation.y
            if sqrt(dx*dx + dy*dy) > 10 { self.dragInProgress = true }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            defer { self.dragInProgress = false }
            guard self.dragInProgress else { return }
            let currentChangeCount = NSPasteboard(name: .drag).changeCount
            guard currentChangeCount != self.lastDragChangeCount else { return }
            guard let win = self.window else { return }
            guard win.isVisible, win.isOnActiveSpace else { return }
            guard win.frame.contains(NSEvent.mouseLocation) else { return }
            let pb = NSPasteboard(name: .drag)
            guard let items = pb.pasteboardItems, !items.isEmpty else { return }
            let urls = items.compactMap { item -> URL? in
                guard let str = item.string(forType: .fileURL) else { return nil }
                return URL(string: str)
            }
            guard !urls.isEmpty else { return }
            guard urls != self.lastDraggedURLs else { return }
            self.lastDraggedURLs = urls
            var isFirst = true
            var hasNonFont = false
            for url in urls {
                let fontExts: Set<String> = ["ttf","otf","woff","woff2"]
                if !fontExts.contains(url.pathExtension.lowercased()) { hasNonFont = true; break }
            }
            if hasNonFont { self.stopTorrent() }
            for url in urls {
                let fontExts: Set<String> = ["ttf","otf","woff","woff2"]
                if fontExts.contains(url.pathExtension.lowercased()) {
                    _ = PhotonFont.loadFromURL(url)
                    if PhotonFont.needsAxisMapping {
                        PhotonFont.presentAxisMapping()
                    }
                    continue
                }
                let subExts: Set<String> = ["srt","ass","ssa","vtt","sub"]
                if subExts.contains(url.pathExtension.lowercased()) {
                    self.ipcCommand(MPVCommand.make(["sub-add", url.path]))
                    continue
                }
                if url.pathExtension.lowercased() == "torrent" {
                    self.streamTorrent(url.path)
                    continue
                }
                let imageExts: Set<String> = [
                    "jpg","jpeg","png","gif","bmp","webp",
                    "tiff","tif","ico","heic","heif","avif"
                ]
                if imageExts.contains(url.pathExtension.lowercased()) {
                    self.openMediaFile(url.path)
                    continue
                }
                let mode = isFirst ? "replace" : "append-play"
                if mode == "replace" {
                    self.openMediaFile(url.path)
                } else {
                    self.ipcCommand(MPVCommand.make(["loadfile", url.path, mode]))
                }
                isFirst = false
            }
        }
    }
}
// MARK: - MusicModeController
// ================================================================
//  MusicModeController - music playback mode
// ================================================================
final class MusicModeController {
    private(set) var musicController: MusicController?
    private(set) var isMusicMode      = false
    private(set) var musicPanel: MusicPanel?
    private var musicCoverView: NSImageView?
    private weak var hostView: NSView?
    private let sidebarUI: SidebarUI
    private let spineUI: SpineUI
    private let ipcPath: String
    private let ipcCommand: (String) -> Void
    private let getAppliedVideoFrame: () -> CGRect
    private let setAppliedVideoFrame: (CGRect) -> Void
    private let setAppliedVideoFrameWindowSize: (CGSize) -> Void
    private let setVideoDisplaySize: (Double, Double) -> Void
    /// gor 514: arms the one-shot opening fit on PPController with the
    /// given floor fraction (0.38 at music-mode exit).
    private let markOpeningFitPending: (Double) -> Void
    init(
        hostView: NSView,
        sidebarUI: SidebarUI,
        spineUI: SpineUI,
        ipcPath: String,
        ipcCommand: @escaping (String) -> Void,
        getAppliedVideoFrame: @escaping () -> CGRect,
        setAppliedVideoFrame: @escaping (CGRect) -> Void,
        setAppliedVideoFrameWindowSize: @escaping (CGSize) -> Void,
        setVideoDisplaySize: @escaping (Double, Double) -> Void,
        markOpeningFitPending: @escaping (Double) -> Void
    ) {
        self.hostView = hostView
        self.sidebarUI = sidebarUI
        self.spineUI = spineUI
        self.ipcPath = ipcPath
        self.ipcCommand = ipcCommand
        self.getAppliedVideoFrame = getAppliedVideoFrame
        self.setAppliedVideoFrame = setAppliedVideoFrame
        self.setAppliedVideoFrameWindowSize = setAppliedVideoFrameWindowSize
        self.setVideoDisplaySize = setVideoDisplaySize
        self.markOpeningFitPending = markOpeningFitPending
    }
    func setup() {
        musicController = MusicController(ipcPath: ipcPath)
        musicController?.onStatus = { [weak self] title, _, _, _, _ in
            DispatchQueue.main.async {
                if !title.isEmpty { self?.spineUI.setTitle(title) }
            }
        }
        if musicPanel == nil { setupMusicPanel() }
    }
    func panelFrame() -> CGRect {
        guard let hostView = hostView else { return .zero }
        let designPadL: CGFloat = (PhotonFont.designTwoDigitW / 2) + PhotonFont.designPad * 1.5
        let padL: CGFloat = PhotonFont.chromeValue(designPadL)
        let padR: CGFloat = IconBarFit.panelPadR(padL: designPadL)
        let padT: CGFloat = PhotonFont.chromeValue(PhotonFont.designPad / 2 + 2)
        let padB: CGFloat = padT
        let applied = getAppliedVideoFrame()
        let base    = (hostView as? PPController)?.stereoPanelBounds ?? (applied != .zero ? applied : hostView.bounds)
        return CGRect(x: base.minX + padL,
                      y: base.minY + padB,
                      width:  base.width  - padL - padR,
                      height: base.height - padT - padB)
    }
    func relayout() {
        if isMusicMode, let p = musicPanel { p.frame = panelFrame() }
    }
    private func setupMusicPanel() {
        guard let mc = musicController, let hostView = hostView else { return }
        let coverView = NSImageView(frame: hostView.bounds)
        coverView.imageScaling = .scaleProportionallyUpOrDown
        coverView.alphaValue   = 0
        coverView.wantsLayer   = true
        coverView.layer?.opacity = 0
        hostView.addSubview(coverView)
        musicCoverView = coverView
        let panel = MusicPanel(frame: panelFrame())
        panel.isHidden         = true
        panel.autoresizingMask = [.width, .height]
        panel.bind(controller: mc)
        panel.onClose         = { [weak self] in self?.toggleMusicMode() }
        panel.onScreenChange  = { [weak self] isListMode in self?.sidebarUI.isListMode = isListMode }
        panel.sidebarRef      = sidebarUI
        panel.onHoverCover    = { [weak self] urlString in self?.showCoverPreview(urlString) }
        panel.onHoverCoverEnd = { [weak self] in self?.hideCoverPreview() }
        hostView.addSubview(panel)
        musicPanel = panel
    }
    func showCoverPreview(_ urlString: String) {
        guard let coverView = musicCoverView, let hostView = hostView else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let url = URL(string: urlString) else { return }
            let cacheDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mus2/covers")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            // I45: use a stable SHA-1 cache key, never Swift hashValue.
            let fname = cacheDir.appendingPathComponent("\(StableCacheKey.sha1(urlString)).jpg")
            if !FileManager.default.fileExists(atPath: fname.path) {
                guard let data = try? Data(contentsOf: url) else { return }
                try? data.write(to: fname)
            }
            guard let image = NSImage(contentsOf: fname) else { return }
            DispatchQueue.main.async {
                coverView.image = image
                coverView.frame = hostView.bounds
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.8
                    coverView.animator().alphaValue = 1.0
                }
            }
        }
    }
    func hideCoverPreview() {
        guard let coverView = musicCoverView else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            coverView.animator().alphaValue = 0.0
        }
    }
    func toggleMusicMode() {
        guard let mc = musicController, let hostView = hostView else { return }
        if isMusicMode {
            ipcCommand(#"{"command":["stop"]}"#)
            ipcCommand(#"{"command":["set","vid","auto"]}"#)
            // gor-fit.lua sizes the next open itself (animated); the old 38% jump stays only without the script.
            if !PPController.gorFitScriptActive { ipcCommand(#"{"command":["set","geometry","38%+50%+50%"]}"#) }
            ipcCommand(#"{"command":["set","keepaspect","yes"]}"#)
            setVideoDisplaySize(0, 0)
            // gor 514: re-arm the one-shot opening fit with the music-exit
            // floor (0.38) so the restored video window follows the same
            // resolution-sensitive rule as a fresh open.
            markOpeningFitPending(PPController.gorFitScriptActive ? GorVideoFit.openBaselineFraction : GorVideoFit.musicExitBaselineFraction)
            setAppliedVideoFrame(.zero)
            setAppliedVideoFrameWindowSize(.zero)
            mc.stop()
            musicPanel?.isHidden = true
            sidebarUI.isListMode = false
            spineUI.setTitle("")
        } else {
            let musicSize = 820
            setVideoDisplaySize(Double(musicSize), Double(musicSize))
            ipcCommand(#"{"command":["stop"]}"#)
            ipcCommand(#"{"command":["set","vid","auto"]}"#)
            ipcCommand("{\"command\":[\"set\",\"geometry\",\"\(musicSize)x\(musicSize)\"]}")
            ipcCommand(#"{"command":["set","keepaspect","no"]}"#)
            mc.start()
            spineUI.setTitle("")
            musicPanel?.frame   = panelFrame()
            musicPanel?.isHidden = false
            musicPanel?.needsLayout = true
            if let p = musicPanel { p.removeFromSuperview(); hostView.addSubview(p) }
        }
        isMusicMode.toggle()
        setAppliedVideoFrame(.zero)
        setAppliedVideoFrameWindowSize(.zero)
    }
    func closeMusicPanel() { toggleMusicMode() }
    func hitTest(_ pointInHostView: CGPoint) -> Bool {
        musicPanel.map { !$0.isHidden && $0.frame.contains(pointInHostView) } ?? false
    }
}
// MARK: - IPTVModeController
// ================================================================
//  IPTVModeController - IPTV playback mode
// ================================================================
final class IPTVModeController {
    private(set) var isIptvMode = false
    private(set) var iptvPanel: IPTVPanel?
    // Any clear of the channel title (stopStream, a non-IPTV load) also retires an in-flight
    // HLS resolve: its late callback must not replace the user's newer choice.
    var iptvChannelTitle: String = "" {
        didSet { if iptvChannelTitle.isEmpty { iptvLoadGeneration &+= 1 } }
    }
    private(set) var iptvLoadGeneration = 0
    private weak var hostView: NSView?
    private let spineUI: SpineUI
    private let ipcCommand: (String) -> Void
    private let batchIPC: (String) -> Void
    private let closeMusicModeIfActive: () -> Void
    private let getAppliedVideoFrame: () -> CGRect
    private let applyVideoFrame: (CGRect) -> Void
    private let photonEnabled: () -> Bool
    private let applyIPTVProfile: () -> Void
    init(
        hostView: NSView,
        spineUI: SpineUI,
        ipcCommand: @escaping (String) -> Void,
        batchIPC: @escaping (String) -> Void,
        closeMusicModeIfActive: @escaping () -> Void,
        getAppliedVideoFrame: @escaping () -> CGRect,
        applyVideoFrame: @escaping (CGRect) -> Void,
        photonEnabled: @escaping () -> Bool,
        applyIPTVProfile: @escaping () -> Void
    ) {
        self.hostView = hostView
        self.spineUI = spineUI
        self.ipcCommand = ipcCommand
        self.batchIPC = batchIPC
        self.closeMusicModeIfActive = closeMusicModeIfActive
        self.getAppliedVideoFrame = getAppliedVideoFrame
        self.applyVideoFrame = applyVideoFrame
        self.photonEnabled = photonEnabled
        self.applyIPTVProfile = applyIPTVProfile
    }
    func setup() {
        if iptvPanel == nil { setupIPTVPanel() }
    }
    func relayout() {
        if isIptvMode, let p = iptvPanel { p.frame = iptvPanelFrame() }
    }
    func hitTest(_ pointInHostView: CGPoint) -> Bool {
        guard let panel = iptvPanel, !panel.isHidden else {
            return false
        }
        let result = panel.hitTest(NSPoint(x: pointInHostView.x, y: pointInHostView.y)) != nil
        return result
    }
    func handlePollEOF(currentTime: Double) {
        guard isIptvMode, let panel = iptvPanel else { return }
        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            if panel.isRandomMode {
                panel.handleRandomFailure()
            } else {
                panel.tryNextAlternateURL()
            }
        }
    }
    func cancelBlackScreenWarning() {
        iptvPanel?.cancelBlackScreenWarning()
    }
    func toggleIptvMode() {
        guard let hostView = hostView else { return }
        if isIptvMode {
            iptvPanel?.isHidden = true
        } else {
            closeMusicModeIfActive()
            applyVideoFrame(hostView.bounds)
            iptvPanel?.frame    = iptvPanelFrame()
            iptvPanel?.isHidden = false
            iptvPanel?.needsLayout = true
            if let p = iptvPanel { p.removeFromSuperview(); hostView.addSubview(p) }
        }
        isIptvMode.toggle()
    }
    func handleFullScreenExit() {
        guard isIptvMode else { return }
        applyIPTVProfile()
    }
    private func iptvPanelFrame() -> CGRect {
        guard let hostView = hostView else { return .zero }
        let designPadL: CGFloat = (PhotonFont.designTwoDigitW / 2) + PhotonFont.designPad * 1.5
        let padL: CGFloat = PhotonFont.chromeValue(designPadL)
        let padR: CGFloat = IconBarFit.panelPadR(padL: designPadL)
        let padT: CGFloat = PhotonFont.chromeValue(PhotonFont.designPad / 2 + 2)
        let padB: CGFloat = padT
        let applied = getAppliedVideoFrame()
        let base    = (hostView as? PPController)?.stereoPanelBounds ?? (applied != .zero ? applied : hostView.bounds)
        return CGRect(x: base.minX + padL,
                      y: base.minY + padB,
                      width:  base.width  - padL - padR,
                      height: base.height - padT - padB)
    }
    private func setupIPTVPanel() {
        guard let hostView = hostView else { return }
        let panel = IPTVPanel(frame: iptvPanelFrame())
        panel.isHidden         = true
        panel.autoresizingMask = [.width, .height]
        panel.onPlayURL = { [weak self] url, channelName in
            guard let self else { return }
            self.closeMusicModeIfActive()
            self.iptvChannelTitle = channelName
            if !channelName.isEmpty { self.spineUI.setTitle(channelName) }
            self.iptvPanel?.clearQualityVariants()
            self.iptvLoadGeneration &+= 1
            let generation = self.iptvLoadGeneration
            Self.resolveHLSVariant(masterURL: url) { [weak self] resolvedURL, variants in
                guard let self, self.iptvLoadGeneration == generation else { return }
                let photonEnabled = self.photonEnabled()
                let batch = [
                    #"{"command":["script-message-to","photon","set-live","true"]}"#,
                    #"{"command":["script-message-to","photon","set-user-enabled","\#(photonEnabled ? "true" : "false")"]}"#,
                    MPVCommand.make(["loadfile", resolvedURL]),
                ].joined(separator: "\n")
                self.batchIPC(batch)
                self.applyIPTVProfile()
                if !variants.isEmpty {
                    self.iptvPanel?.showQualityVariants(variants, currentURL: resolvedURL)
                }
            }
        }
        panel.onClose = { [weak self] in self?.toggleIptvMode() }
        panel.onSwitchURL = { [weak self] url in
            guard let self else { return }
            let photonEnabled = self.photonEnabled()
            let batch = [
                #"{"command":["script-message-to","photon","set-live","true"]}"#,
                #"{"command":["script-message-to","photon","set-user-enabled","\#(photonEnabled ? "true" : "false")"]}"#,
                MPVCommand.make(["loadfile", url]),
            ].joined(separator: "\n")
            self.batchIPC(batch)
            self.applyIPTVProfile()
        }
        hostView.addSubview(panel)
        iptvPanel = panel
    }
    // ── HLS Master Playlist Resolver ────────────────────────────────────────
    struct HLSVariant {
        let bandwidth: Int
        let resolution: String
        let url: String
        var label: String {
            let base: String
            if !resolution.isEmpty { base = resolution }
            else {
                let kbps = bandwidth / 1000
                base = kbps >= 8000 ? "\(kbps / 1000).\(kbps % 1000 / 100)Mbps" : "\(kbps) kbps"
            }
            return base.replacingOccurrences(of: "x", with: "×")
        }
    }
    static func resolveHLSVariant(masterURL: String,
                           completion: @escaping (_ bestURL: String, _ all: [HLSVariant]) -> Void) {
        guard masterURL.lowercased().contains(".m3u8"),
              let url = URL(string: masterURL) else {
            completion(masterURL, [])
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(masterURL, []) }
                return
            }

            let lines = text.components(separatedBy: .newlines)

            var variants: [HLSVariant] = []
            var i = 0
            while i < lines.count {
                let line = lines[i]
                if line.hasPrefix("#EXT-X-STREAM-INF:") {
                    var bw  = 0
                    var res = ""
                    for part in line.dropFirst(18).components(separatedBy: ",") {
                        let p = part.trimmingCharacters(in: .whitespaces)
                        if p.hasPrefix("BANDWIDTH="), let v = Int(p.dropFirst(10)) {
                            bw = max(bw, v)
                        }
                        if p.hasPrefix("RESOLUTION=") {
                            res = String(p.dropFirst(11))
                        }
                    }
                    i += 1
                    if i < lines.count {
                        var variantURLStr = lines[i].trimmingCharacters(in: .whitespaces)
                        if !variantURLStr.isEmpty && !variantURLStr.hasPrefix("#") {
                            if !variantURLStr.hasPrefix("http") {
                                var base = url
                                base.deleteLastPathComponent()
                                variantURLStr = base.absoluteString + variantURLStr
                            }
                            variants.append(HLSVariant(bandwidth: bw, resolution: res, url: variantURLStr))
                        }
                    }
                }
                i += 1
            }

            guard !variants.isEmpty else {
                DispatchQueue.main.async { completion(masterURL, []) }
                return
            }

            let sorted = variants.sorted { $0.bandwidth > $1.bandwidth }
            let best   = sorted[0]

            print("[HLS-RESOLVE] \(variants.count) variant → highest: \(best.bandwidth / 1000) kbps \(best.resolution) → \(best.url)")

            DispatchQueue.main.async { completion(best.url, sorted) }
        }.resume()
    }
}

// MARK: - InputController
// MARK: - VR180Controller

// ================================================================
//  VR180Controller - VR180 tracking and view control
// ================================================================
// MARK: - Blink control camera + IPC rules

/// Production blink-callback -> mpv IPC mapping. Pure and top-level so Tests/HeadPose
/// compiles this exact text and asserts the exact strings the app sends; the closures in
/// setBlinkControlEnabled call these, there is no second copy of the formats.
enum BlinkCommandRoute {
    static func lidsIPC(_ left: Double, _ right: Double, _ uncertain: Bool) -> String {
        "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-lids\",\"\(left)\",\"\(right)\",\"\(uncertain)\"]}"
    }
    static func seekIPC(_ seconds: Int, commandHeld: Bool = false) -> String {
        let seconds = commandHeld ? -abs(seconds) : seconds
        return "{\"command\":[\"seek\",\(seconds),\"relative\"]}"
    }
    static let playPauseIPC = #"{"command":["cycle","pause"]}"#
    static let lidsClearedIPC = lidsIPC(0.0, 0.0, true)
    static func analogIPC(_ on: Bool) -> String {
        "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-blink-analog\",\"\(on)\"]}"
    }
}

/// Which camera consumers should run for the current feature state. Pure so the harness
/// pins the composition; VR180Controller.updateCaptureConsumers applies the edges.
enum CaptureConsumerRules {
    /// Both consumers use loaded-video authority; paused video must still respond to head motion.
    static func headShouldRun(headTrackingEnabled: Bool, playbackActive: Bool) -> Bool {
        headTrackingEnabled && playbackActive
    }
    /// Blink leg: needs frames whenever blink is on in VR with a file loaded - pause must NOT
    /// stop it (loadedVideoActive, not playbackActive), or the pause toggle could never resume.
    static func blinkShouldRun(blinkOn: Bool, vrEnabled: Bool, loadedVideoActive: Bool, cameraAllowed: Bool) -> Bool {
        blinkOn && loadedVideoActive && cameraAllowed
    }
}

final class VR180Controller {

    private(set) var vrModeEnabled = false { didSet { ThreadCpuDiag.vrMode = vrModeEnabled;if !vrModeEnabled {onSubtitleTilt?(0,0);onUITilt?(0)} } }

    var vrModeSetByAutoDetect = false
    private var flatStereoFile = false; var filmLooksStereo: Bool { detectedStereoKind != nil }; func showOSDLine(_ t: String) { showBlinkOSD(t) }
    private var flatAutoEyeAspect: Double = 0
    var flatUIEyeAspect: Double? {flatStereoFile && flatAutoEyeAspect > 0 ? flatAutoEyeAspect : nil}
    var isFlatStereo: Bool {flatStereoFile}
    var isFlat2D3D: Bool {projectionKind == "flat-2d3d"}
    func requestsFlatSBSGeometry(for path:String)->Bool {MainActor.assumeIsolated {
        let s=ThreeDStore.shared.snapshot;guard !path.isEmpty,s.currentFilm == ThreeDRecognitionBridge.filmID(path:path) else{return false}
        let p=ThreeDPresentationPlan.make(state:s);return p.luaKind=="flat-2d3d" && p.output == .sbs
    }}
    var expectsSBSFilmFrame:Bool {appliedPlan?.output == .sbs || appliedPlan?.output == .halfSBS}
    var presentsFlatSBSGeometry:Bool {appliedPlan?.luaKind=="flat-2d3d" && appliedPlan?.output == .sbs}
    var usesLegacyPreviewChrome:Bool {sourceIsFlatPreview && appliedPlan?.output == .vr180}
    private var sourceIsFlatPreview:Bool {projectionKind.hasPrefix("flat-")}
    var cropSourcePacking: (stereo: Bool, topBottom: Bool) {
        // The plan includes rendered-source replacements; output SBS alone is not source stereo.
        let kind=MainActor.assumeIsolated {ThreeDPresentationPlan.make(state:ThreeDStore.shared.snapshot).luaKind}
        return CropSourcePacking.flags(kind)
    }
    var isTopBottom: Bool { projectionKind == "flat-tb" }
    private var projectionKind = "mono"
    private var projectionKey = ""

    private(set) var headTrackingEnabled = false

    /// Cross-eye order (block 180 3a). false = default order, true = swapped halves.
    /// Persisted in UserDefaults; every VR disparity sign reads this flag.
    static let swapEyesDefaultsKey = "gor.vr.swapEyes"
    /// Head-tracking opt-in (block 180 3b). VR entry (auto-detect, menu, shift+v)
    /// enables the shader only; the camera starts ONLY from an explicit shift+h /
    /// menu head-tracking choice. The last explicit choice is remembered here
    /// (UserDefaults) but is never used to start the camera by itself.
    static let headTrackingDefaultsKey = "gor.vr.headTracking"
    /// VR entry restores prior auto tracking, except an explicit saved off or a test-owned camera opt-out.
    static var headTrackingAutoStartAllowed: Bool {
        guard ProcessInfo.processInfo.environment["GOR_VR_TEST_NO_CAMERA"] != "1" else { return false }
        return (UserDefaults.standard.object(forKey: headTrackingDefaultsKey) as? Bool) ?? true
    }
    private(set) var headTrackingPreferred=false
    private(set) var swapEyes=false
    private var headTrackingCameraActive = false
    private var blinkCameraActive = false
    /// Every VR entry defaults ON, but an explicit saved OFF survives re-entry and relaunch.
    private var blinkControlPreferred=false
    /// Set only when the head-motion leg actually called HeadTracker.start(); GOR_VR_SIM_POSE=1
    /// acquires no camera consumer, so the matching stop must never release the blink leg's.
    private var headOwnsRealCameraConsumer = false
    /// File-loaded signal fed by PPController from cameraLoadedVideoActive (UI lane owns every
    /// PPController write). Unlike playbackActive this does NOT drop on pause: blink needs
    /// frames while paused, or the bilateral-double pause toggle could never resume.
    var loadedVideoActive = false {
        didSet {
            guard loadedVideoActive != oldValue else { return }
            // A file boundary retires the recognizer epoch so a previous file's
            // first blink or held wink cannot act on the replacement file.
            if #available(macOS 12.0, *) {
                if loadedVideoActive { if blinkControlPreferred { _ = setBlinkControlEnabled(true, osd: false, remember: false) } }
                else {
                    HeadTracker.shared.blinkLogEnabled = false
                    HeadTracker.shared.flushBlinkSummary(osd: nil)
                    blinkControlDidStop(osd: nil)
                }
            }
            updateCaptureConsumers()
        }
    }
    var playbackActive = false {
        didSet {
            guard playbackActive != oldValue else { return }
            updateCaptureConsumers()
        }
    }

    static let vrYawPitchDegPerPoint: Double = 0.15
    static let vrFovDegPerMagnifyUnit: Double = -60.0

    static let vrAutoFullscreen: Bool = false
    // VR output fills the whole drawable (screen in fullscreen, window when windowed): vr180-look.lua
    // sets keepaspect=no on enable and restores the user's prior value on disable, and derives each
    // eye's horizontal fov from its viewport aspect (fixed vertical fov). No aspect override is sent.

    static let headRotationGain: Double = 1.0
    static let headTranslateMetersPerUnit: Double = 0.20
    static let headLeanNudgeFovDegPerUnit: Double = -150.0
    static let headIpdNudgePerUnit: Double = 0.06 * 2

    static let headTrackingRestFovDeg: Double = 135.0
    // Block184 restores the exact pre181 mapping (6f5e28345 parent): -150 degrees per box unit.
    // Noise belongs to the one-euro filter, never to a reduced control gain.
    static let headFovGain: Double = 1.0
    static let headDeadZoneRad: Double = 0.004
    static func softDeadZone(_ x: Double) -> Double {
        let m = max(0.0, abs(x) - headDeadZoneRad)
        return x < 0 ? -m : m
    }
    private static let headZTranslateSign: Double = -1.0

    /// The ipd dial (block 182 2): canonical state is the OFFSET IN MILLIMETRES on the 63 mm default,
    /// persisted in UserDefaults (gor.vr.ipdOffsetMM), so a display change never changes the physical
    /// offset. vr180-look converts it with the current viewport and CGDisplayScreenSize mm/px.
    /// The NDC statics below (step 0.02, limit 0.3) are today's dial units; they convert to mm once,
    /// at the M1 full-screen eye half-width (2560 px / 2 eyes / 2 at 25.4/227 mm per px, Apple 111883).
    static let ipdOffsetMMDefaultsKey = "gor.vr.ipdOffsetMM"
    static let ndcToMM: Double = (2560.0 / 2.0 / 2.0) * (25.4 / 227.0)
    private var currentIPDOffsetMM: Double = 0
    /// NDC-equivalent at the M1 scale, kept for the existing test surface and the vrIPD "v" field.
    private var currentBaseIPD: Double { currentIPDOffsetMM / Self.ndcToMM }
    static let baseIPDStep:  Double = 0.02
    static let baseIPDLimit: Double = 0.3

    /// Block184 dial is a dimensionless depth factor. Default1 gives crossed0.4% eye width for
    /// subtitles and0.8% for UI. A new key avoids reinterpreting old point offsets as this scale.
    static let subtitleDepthDefaultsKey = "gor.vr.subtitleDepthScale.v184"
    static let subtitleDepthDefault: Double = 1.0
    static let subtitleDepthStep:    Double = 0.25
    static let subtitleDepthLimit:   Double = 8.0
    private(set) var subtitleDepthPoints: Double = {
        let stored = UserDefaults.standard.object(forKey: VR180Controller.subtitleDepthDefaultsKey) as? Double
        return stored ?? VR180Controller.subtitleDepthDefault
    }()

    func setSubtitleDepth(_ points: Double) {
        subtitleDepthPoints = max(0, min(Self.subtitleDepthLimit, points))
        UserDefaults.standard.set(subtitleDepthPoints, forKey: Self.subtitleDepthDefaultsKey)
    }

    func adjustSubtitleDepth(by delta: Double) {
        setSubtitleDepth(subtitleDepthPoints + delta)
    }

    /// Whether the user has a stored pref at all (snapshot/restore needs the
    /// difference between "8 stored" and "no pref, default 8").
    var hasSubtitleDepthPref: Bool {
        UserDefaults.standard.object(forKey: Self.subtitleDepthDefaultsKey) != nil
    }

    func clearSubtitleDepth() {
        UserDefaults.standard.removeObject(forKey: Self.subtitleDepthDefaultsKey)
        subtitleDepthPoints = Self.subtitleDepthDefault
    }
    private let ipcCommand: (String) -> Void

    init(ipcCommand: @escaping (String) -> Void) {
        self.ipcCommand = ipcCommand
        resetTestVRProperty()
    }

    func invalidateOpenReceipt() { openReceipt.reset() }
    func invalidateAutoFitEntry() {autoFitEntry=""}
    private var openReceipt=ThreeDOpenReceipt()
    func resetForFileChange() {
        Diag.mediaRecord("3D-CLOSE file=\(URL(fileURLWithPath:recognitionPath).lastPathComponent) generation=\(recognitionGeneration) revision=\(routeRevision) output=\(appliedPlan?.output.rawValue ?? "none")")
        invalidateOpenReceipt()
        vrModeEnabled=false;ScreenCaptureEngine.shared.vrModeActive=false;autoFitEntry="";updateCaptureConsumers()
        resetTestVRProperty()
        appliedThreeD=nil;appliedPlan=nil;appliedEffects=nil;appliedInternal=nil
        vrModeSetByAutoDetect = false
        flatStereoFile = false
        projectionKey = ""
        manualProjection = nil; recognitionGeneration &+= 1; recognitionPath = ""; recognitionIdentity = ""
        probeStarted = false; probeFinished = false; probeProjection = nil; probeStereoSBS = false;probeEyeAspect=nil;probeEyeCrop=nil;sourceMeasuredEyeAspect=nil;probeStereoTB=false
        latestWidth = 0; latestHeight = 0; latestStereo = nil
        projectionKind="mono"
        openingProjection=nil
    }

    // State is owned by ThreeDStore. Recognition supplies evidence, never preferences.
    private var manualProjectionIsCurrentSession=false
    private var manualProjection: String?
    var recognitionPath = ""
    private var recognitionIdentity = ""
    private var recognitionGeneration: UInt64 = 0
    private var probeStarted = false
    var probeFinished = false
    private var probeProjection: String?
    private var openingProjection: String?
    private var probeStereoSBS = false
    private var probeEyeAspect:Double?
    private var probeEyeCrop:SBSEyeCrop.NormalizedCrop?
    private var sourceMeasuredEyeAspect:Double?
    func acceptSourceEyeAspect(_ aspect:Double?) {
        // Detector measurement is UI-only, including legacy/delayed callers.
        clearMeasuredEyeAspect()
    }
    func clearMeasuredEyeAspect() {
        latestSourceCrop=nil; projectionKey=""
        if isTopBottom { sourceMeasuredEyeAspect = latestHeight > 0 ? latestWidth*latestPixelAspect/latestHeight*2 : nil }
        else { sourceMeasuredEyeAspect = SBSGeometry.resolve(width:latestWidth,height:latestHeight,pixelAspect:latestPixelAspect,filename:recognitionPath,stereoProven:true)?.aspect }
    }
    private var probeStereoTB=false
    private var latestStereo: String?
    private var latestContainerMetadata:[String:String]=[:]
    private var recognitionLogKey=""
    private var latestProbeStatus="pending"
    var sourceSuggestion:String {if detectedStereoKind != nil {return detectedStereoKind!};return VRRecognition.suggestion(filename:recognitionPath,width:latestWidth,height:latestHeight)}
    var latestWidth: Double = 0
    var latestHeight: Double = 0
    private var latestPixelAspect:Double=1
    private var latestSourceCrop:(Double,Double)?

    func applyManualSource(_ value:String,enable:Bool) {
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setSource(SourceFormatChoice.source(value)))}
    }
    func applySourceOutput(_ output:String) {
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setOutput(ThreeDOutput(rawValue:output) ?? .off))}
    }
    func selectProjection(_ kind:String) {
        let map=["flat-2d3d":"flat","flat-sbs":"sbs","flat-tb":"ou","vr180":"vr180"]
        applyManualSource(map[kind] ?? "flat",enable:false)
    }
    func noteManualEnabled(_ enabled:Bool) {
        MainActor.assumeIsolated {let store=ThreeDStore.shared;store.dispatch(.setOutput(enabled ? ThreeDPresentationPlan.restoredOutput(for:store.snapshot):.off))}
    }
    private var appliedThreeD:FilmThreeD?
    private var appliedPlan:ThreeDPresentationPlan?
    private var appliedEffects:ThreeDGlobalEffects?
    private var applyingStore=false
    private var appliedInternal:Bool?
    private var routeRevision: UInt64 = 0
    private var pendingRouteRevision:UInt64?
    private var pendingRouteOutput:ThreeDOutput?
    private var droppedRouteKey=""
    private var autoFitEntry=""
    func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect],revision:UInt64?=nil) {
        applyingStore=true;defer {applyingStore=false}
        routeRevision=revision ?? MainActor.assumeIsolated {ThreeDStore.shared.revision}
        let revision=routeRevision
        let requestedPlan=ThreeDPresentationPlan.make(state:state)
        let expectedLayout=requestedPlan.vrEnabled ? (["flat-2d3d":0,"flat-sbs":1,"flat-tb":2,"vr180":3,"vr180-tb":4,"vr360-mono":5,"vr360-tb":6][requestedPlan.luaKind] ?? 0):0
        let filename=URL(fileURLWithPath:recognitionPath).lastPathComponent
        let routeCommand:[Any]=["script-message-to","vr180_look","vr180-look-store-revision",String(revision),requestedPlan.luaKind,"store-applier",String(requestedPlan.vrEnabled),String(expectedLayout),String(requestedPlan.pack),requestedPlan.output.rawValue,requestedPlan.engine.rawValue,String(recognitionGeneration),filename,String(ProcessInfo.processInfo.processIdentifier)]
        let routeEnvelope=(try? JSONSerialization.data(withJSONObject:["command":routeCommand])).flatMap {String(data:$0,encoding:.utf8)}
        Diag.mediaRecord("3D-TRANSITION file=\(filename) generation=\(recognitionGeneration) revision=\(revision) previous=\(appliedPlan?.output.rawValue ?? "none") output=\(requestedPlan.output.rawValue) engine=\(requestedPlan.engine.rawValue) phase=requested app_pid=\(ProcessInfo.processInfo.processIdentifier)")
        let recognitionFilm=recognitionPath.isEmpty ? nil:MainActor.assumeIsolated {ThreeDRecognitionBridge.filmID(path:recognitionPath)}
        let identityReady = !recognitionIdentity.isEmpty && state.currentFilm == recognitionFilm
        // Off is a safety exit even without binding. Bound effects keep their
        // existing independent-tools behavior; the normal path below owns Off.
        if requestedPlan.output == .off && !identityReady {
            if let routeEnvelope {sendRaw(routeEnvelope)}
            setVRModeEnabled(false)
        }
        guard identityReady else {
            pendingRouteRevision=revision
            if effects.contains(.reapply),state.currentFilm != nil {pendingRouteOutput=state.current.output}
            let reason=recognitionIdentity.isEmpty ? "identityEmpty":"filmMismatch"
            let key=reason+"|"+(state.currentFilm?.rawValue ?? "none")
            if key != droppedRouteKey {droppedRouteKey=key;Diag.mediaRecord("3D-DROPPED reason=\(reason) storeFilm=\(state.currentFilm?.rawValue ?? "none") recognitionFilm=\(recognitionFilm?.rawValue ?? "none") revision=\(revision)")}
            return
        }
        // Identity may bind before current-file geometry. Keep the requested output
        // pending rather than publishing a zero-aspect flat2D-to-SBS projection.
        if requestedPlan.output == .sbs,requestedPlan.luaKind=="flat-2d3d",requestedPlan.luaAspect<=0,
           knownEyeAspect(kind:"flat-2d3d",filename:recognitionPath,width:latestWidth,height:latestHeight)<=0 {
            pendingRouteRevision=revision
            Diag.mediaRecord("3D-GEOMETRY-PENDING path=\(recognitionPath) width=\(latestWidth) height=\(latestHeight) revision=\(revision)")
            return
        }
        pendingRouteRevision=nil;pendingRouteOutput=nil;droppedRouteKey=""
        let previousProjectionKey=projectionKey
        let forceReapply=effects.contains(.reapply)
        if forceReapply {projectionKey=""}
        if let routeEnvelope {sendRaw(routeEnvelope)}
        let plan=ThreeDPresentationPlan.make(state:state)
        var desired=state.current;desired.source=plan.filmSource;desired.output=plan.output
        let engine=plan.engine
        let internalMedia=state.renderedSource != nil && state.renderedOutput == plan.output
        if internalMedia && desired.output == .anaglyph {desired.output = .off}
        if internalMedia != appliedInternal {
            sendRaw("{\"command\":[\"set_property\",\"user-data/gor/3d-internal\",\(internalMedia)]}")
            if let bytes=try? JSONSerialization.data(withJSONObject:["command":["set_property","user-data/gor/3d-parent-film-id",state.currentFilm!.rawValue]]),let text=String(data:bytes,encoding:.utf8) {sendRaw(text)}
            appliedInternal=internalMedia
        }
        // Generated source changes are now presented by this writer too, even
        // when the parent film and output have not changed.
        let planChanged=plan != appliedPlan
        let routeChanged=desired != appliedThreeD || planChanged
        let presentationChanged=forceReapply || routeChanged
        let effectOnlyChange = !routeChanged && state.effects != appliedEffects
        if presentationChanged {
            releaseProjectionLock()
            // Republish stale state without passing through Off: Off resets the
            // tracked pose and causes each independent effect click to jump.
            if routeChanged || (desired.output == .off && !effectOnlyChange) {setVRModeEnabled(false)}
            projectionKey=""
            let kind=plan.luaKind
            Diag.mediaRecord("3D-DECISION path=store_applier film=\(state.currentFilm!.rawValue) source=\(desired.source.format.rawValue) engine=\(engine.rawValue) output=\(desired.output.rawValue) pack=\(plan.pack) userTouched=\(desired.userTouched)")
            if desired.output == .off {if !effectOnlyChange {setVRModeEnabled(false)}} else {
                setSwapEyes(desired.source.swap)
                if engine == .nativeVR180 {
                    let aspect = plan.luaAspect > 0 ? plan.luaAspect : knownEyeAspect(kind:kind,filename:recognitionPath,width:latestWidth,height:latestHeight)
                    publishProjection(kind,aspect:aspect,reason:"nativeVR180")
                    let entering = !vrModeEnabled
                    if entering { setVRModeEnabled(true) }
                    vrModeSetByAutoDetect = true
                    if entering && !flatStereoFile { simulatePoseIfRequested() }
                } else {
                    publishProjection(kind,aspect:plan.luaAspect > 0 ? plan.luaAspect : knownEyeAspect(kind:kind,filename:recognitionPath,width:latestWidth,height:latestHeight),reason:"storeApplier")
                }
                let luaOutput = engine == .twoDVR180 ? "full_sbs" : desired.output.rawValue
                sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-output\",\"\(luaOutput)\"]}")
                setVRModeEnabled(true)
            }
            appliedThreeD=desired
        }
        // Refresh late geometry without route/media/pose reset; projectionKey dedupes.
        if !presentationChanged, desired.output != .off {publishProjection(plan.luaKind,aspect:plan.luaAspect > 0 ? plan.luaAspect : knownEyeAspect(kind:plan.luaKind,filename:recognitionPath,width:latestWidth,height:latestHeight),reason:"sourceGeometry")}
        appliedPlan=plan
        if state.effects != appliedEffects || presentationChanged {
            func n(_ key:ThreeDEffectKey,_ fallback:Double)->Double {if case let .number(v)?=state.effects[key] {return v};return fallback}
            let p=ThreeDAutoRoute.previewParams(mode:desired.output.rawValue,strength:n(.strength,1),screenDepthM:n(.screenDepth,1.5),screenDeg:n(.screenSize,75),surround:state.effects[.surround] == .text("black") ? "black":"soft")
            if desired.output != .off {
            sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-pack\",\"\(plan.pack)\",\"\(p.gain)\",\"\(p.conv)\",\"\(p.zoom)\",\"\(p.soft)\"]}")
            }
            if case let .bool(v)?=state.effects[.head] {setHeadTrackingEnabled(v,remember:false)}
            if case let .bool(v)?=state.effects[.blink] {_=setBlinkControlEnabled(v,osd:false,remember:false)}
            if case let .bool(v)?=state.effects[.crossEye] {setSwapEyes(v != desired.source.swap);sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-viewing-cross\",\"\(v ? "1":"0")\"]}")}
            if case let .number(v)?=state.effects[.ipd] {publishBaseIPD(v/Self.ndcToMM,persist:false)}
            sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-surround-invert\",\"\(state.effects[.surroundInvert] == .bool(true) ? "1":"0")\"]}")
            appliedEffects=state.effects
        }
        // Actual Off wins over callbacks emitted while reapplying persisted effects.
        // Independent tool changes while already2D remain usable and keep their pose.
        if desired.output == .off && !effectOnlyChange {setVRModeEnabled(false)}
        if internalMedia && desired.output != .off {sendRaw(#"{"command":["script-message-to","vr180_look","vr180-look-plan-lock","on","true"]}"#)}
        let fitEntry=(desired.output == .sbs || desired.output == .halfSBS) && plan.filmSource.format == .flat2D ? "\(recognitionGeneration)|\(recognitionIdentity)|\(desired.output.rawValue)":""
        if !fitEntry.isEmpty && fitEntry != autoFitEntry {resetFilmView(smooth:true)}
        autoFitEntry=fitEntry
        if effects.contains(.resetView) {resetFilmView();recenterHeadTracking()}
        if presentationChanged {Diag.mediaRecord("vrAppliedRoute file=\(URL(fileURLWithPath:recognitionPath).lastPathComponent) generation=\(recognitionGeneration) source=\(plan.filmSource.format.rawValue) output=\(plan.output.rawValue) engine=\(plan.engine.rawValue) probe=\(latestProbeStatus)")}
        publishThreeDAppliedState(plan: plan)
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-route-complete\",\"\(revision)\",\"store-applier\"]}")
        // Notify once after the complete route; intermediate false->true switches are not committed geometry.
        if presentationChanged || projectionKey != previousProjectionKey {onVRModeApplied?(vrModeEnabled)}
    }
    /// Read-only receipt of the applied 3D route, stamped so a driver can tell this build/process
    /// from a stale capture. This publishes state only; it must never change behavior.
    private func publishThreeDAppliedState(plan: ThreeDPresentationPlan) {
        let explicit=MainActor.assumeIsolated {ThreeDStore.shared.appliedOutput=plan.output;return ThreeDStore.shared.snapshot.current.explicitOutput?.rawValue ?? "none"}
        Diag.mediaRecord("3D-APPLIED phase=submitted file=\(URL(fileURLWithPath:recognitionPath).lastPathComponent) generation=\(recognitionGeneration) revision=\(routeRevision) engine=\(plan.engine.rawValue) output=\(plan.output.rawValue) source=\(SourceFormatChoice.raw(plan.filmSource)) pack=\(plan.pack) explicit=\(explicit)")
        let payload: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "revision": routeRevision,
            "build": BuildID.value(),
            "timestamp": Int64((Date().timeIntervalSince1970 * 1000).rounded()),
            "stereoSource": SourceFormatChoice.raw(plan.filmSource),
            "engine": plan.engine.rawValue,
            "output": plan.output.rawValue,
            "vr_mode": vrModeEnabled
        ]
        sendRaw(MPVCommand.make(["set_property", "user-data/gor/3d-applied-state", payload]))
    }
    func knownEyeAspect(kind: String, filename: String, width: Double, height: Double, fullByContract:Bool=false) -> Double {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        if kind == "flat-2d3d" {let a=width*latestPixelAspect/height;return a.isFinite && a>0 ? a:0}
        let source=SourceFormatChoice.get(recognitionPath).split(separator:":").first.map(String.init) ?? "auto"
        if source=="sbs" {return width*latestPixelAspect/height/2}
        if source=="half_sbs" {return width*latestPixelAspect/height}
        if source=="ou" {return width*latestPixelAspect/height*2}
        if source=="half_ou" {return width*latestPixelAspect/height}
        if kind == "flat-tb" {return width*latestPixelAspect/height*2}
        if kind != "flat-sbs" { return width / height / 2 }
        return SBSGeometry.resolve(width:width,height:height,pixelAspect:latestPixelAspect,filename:filename,stereoProven:kind=="flat-sbs",fullByContract:fullByContract,cropWidth:nil,cropHeight:nil)?.aspect ?? 0
    }
    func publishProjection(_ kind: String, aspect: Double, reason: String) {
        projectionKind = kind
        if #available(macOS 12.0, *) {HeadTracker.shared.nativeMotionResponsive=kind.hasPrefix("vr")}
        flatStereoFile = kind == "flat-sbs" || kind == "flat-tb" || kind == "flat-2d3d"
        flatAutoEyeAspect = flatStereoFile ? aspect : 0
        let x=0.0,y=0.0,w=1.0,h=1.0 // original full eye; recognition crop is UI-only
        let key = "\(kind):\(aspect):\(x):\(y):\(w):\(h)"
        guard projectionKey != key else { return }
        projectionKey = key
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-source-eye-crop\",\"\(x)\",\"\(y)\",\"\(w)\",\"\(h)\"]}")
        Diag.log("sbsEyeCrop x=\(x) y=\(y) w=\(w) h=\(h) eyeAspect=\(aspect) basis=sampledUnionWithGuard")
        if flatStereoFile && aspect == 0 {
            GeomTrace.logChanged("vrAspectUnknown", "{\"k\":\"vrAspectUnknown\",\"reason\":\"halfFullPackingUnspecified\",\"preview\":\"storedHalfFrame\",\"manualOverrideAvailable\":true}")
        }
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-projection\",\"\(kind)\",\"\(aspect)\"]}")
        GeomTrace.log("vrProjection", "{\"k\":\"vrProjection\",\"flat\":\(flatStereoFile),\"eyeAspect\":\(aspect),\"reason\":\"\(reason)\"}")
    }
    func autoDetectFromVideoParams(stereoMode: String?, width: Double, height: Double, filename: String, pixelAspect:Double=1,sourceCrop:String?=nil,containerMetadata:[String:String]=[:]) {
        guard width > 0, height > 0 else { return }
        // Prepared render shots belong to the source film's OUTPUT plan, not a new SOURCE decision.
        if ThreeDRecognitionBridge.internalMedia(filename) {return}
        let pendingChoice=pendingRouteOutput;pendingRouteOutput=nil
        let geometryChanged=latestWidth != width || latestHeight != height || latestPixelAspect != pixelAspect
        // Synchronous pending OUTPUT replay must see this film's geometry.
        latestWidth = width; latestHeight = height; latestStereo = stereoMode;latestPixelAspect=pixelAspect
        if recognitionPath != filename {
            recognitionPath = filename; recognitionGeneration &+= 1
            recognitionIdentity = VRRecognition.fileIdentity(filename)
            MainActor.assumeIsolated {ThreeDStore.shared.bindSource(path:filename,id:ThreeDRecognitionBridge.resolveAtOpen(path:filename))}
            if pendingRouteRevision != nil {MainActor.assumeIsolated {applyThreeDState(ThreeDStore.shared.snapshot,[.reapply])}}
            // Old per-projection caches are historical UI data, never SOURCE evidence.
            manualProjection=nil;manualProjectionIsCurrentSession=false
            projectionKey = ""; recognitionLogKey="";latestProbeStatus="pending"; vrModeSetByAutoDetect = false; detectedStereoKind = nil; singleSwitchActive = false; singleSwitchPending = false
            probeStarted = false; probeFinished = false; probeProjection = nil; openingProjection = nil; probeStereoSBS = false;probeEyeAspect=nil;probeEyeCrop=nil;sourceMeasuredEyeAspect=nil;probeStereoTB=false
        }
        latestContainerMetadata=containerMetadata
        latestSourceCrop=SBSGeometry.parseCrop(sourceCrop)
        if !probeStarted, !filename.isEmpty {
            probeStarted = true
            Diag.mediaRecord("vrProbeStart file=\(URL(fileURLWithPath:filename).lastPathComponent) generation=\(recognitionGeneration)")
            let generation = recognitionGeneration
            VRProjectionProbe.inspect(filename) { [weak self] result in
                guard let self, self.recognitionGeneration == generation, self.recognitionPath == filename else { return }
                self.probeFinished = true
                Diag.mediaRecord("vrProbeResult file=\(URL(fileURLWithPath:filename).lastPathComponent) generation=\(generation) status=\(result.status) projection=\(result.projection ?? "none") sbs=\(result.stereoSBS) tb=\(result.stereoTopBottom)")
                self.latestProbeStatus=result.status
                self.probeProjection = result.projection
                self.probeStereoSBS = result.stereoSBS
                self.probeStereoTB=result.stereoTopBottom
                self.probeEyeAspect=result.eyeAspect
                self.probeEyeCrop=result.eyeCrop
                GeomTrace.log("vrRecognition", "{\"k\":\"vrRecognition\",\"status\":\"\(result.status)\",\"projection\":\"\(result.projection ?? "unknown")\",\"stereoSBS\":\(result.stereoSBS)}")
                self.autoDetectFromVideoParams(stereoMode:self.latestStereo,width:self.latestWidth,height:self.latestHeight,filename:filename,pixelAspect:self.latestPixelAspect,sourceCrop:self.latestSourceCrop.map {"\($0.0)x\($0.1)"},containerMetadata:self.latestContainerMetadata)
            }
        }
        let evidence=VRRecognition.mpvEvidence(stereoMode:stereoMode,metadata:containerMetadata)
        openingProjection = ThreeDProjectionMemory.resolve(current: openingProjection, evidence: evidence.projection, probe: probeProjection)
        let projection = openingProjection
        let vrChoice=VRRecognition.choose(remembered:nil, projection:projection, stereoSBS:evidence.stereoSBS || probeStereoSBS, filename:filename, width:width, height:height, stereoTB:evidence.stereoTB || probeStereoTB);let resolved=vrChoice.kind
        let metadata=ThreeDRecognitionBridge.source(projection:projection,sbs:evidence.stereoSBS || probeStereoSBS,tb:evidence.stereoTB || probeStereoTB,filename:filename)
        let tags=ThreeDRecognitionBridge.filename(filename)
        let detected=metadata ?? tags ?? ThreeDSource(.flat2D)
        detectedStereoKind=detected.format == .flat2D ? nil:detected.projection
        let input=ThreeDEvidence(metadata:metadata,filenameTag:tags,suggestion:VRRecognition.suggestion(filename:filename,width:width,height:height))
        guard openReceipt.accept(input) else {if geometryChanged {MainActor.assumeIsolated {applyThreeDState(ThreeDStore.shared.snapshot,[.present])}};return}
        // 196w: record the decision only when the receipt accepted a real change.
        // The 200 ms poll flush replays identical inputs (~7/s observed) and the
        // verdict itself is already deduped by accept; per-flush logging was pure
        // main-thread cost. Real route decisions still log here.
        Diag.mediaRecord("vrOpenDecision {\"k\":\"vrOpenDecision\",\"decision\":\"\(vrChoice.kind)\",\"reason\":\"\(vrChoice.reason)\"}")
        Diag.mediaRecord("vrOpenRoute film=\(MainActor.assumeIsolated {ThreeDRecognitionBridge.filmID(path:recognitionPath).rawValue}) file=\(URL(fileURLWithPath:filename).lastPathComponent) generation=\(recognitionGeneration) probe=\(latestProbeStatus) metadata=\(metadata?.format.rawValue ?? "none") tag=\(tags?.format.rawValue ?? "none") detected=\(detected.format.rawValue)")
        MainActor.assumeIsolated {
            let store=ThreeDStore.shared
            store.dispatch(.open(ThreeDRecognitionBridge.filmID(path:recognitionPath),input))
            // A click during the unbound gap belongs to the file now binding,
            // never to the previous film's source format.
            if let output=pendingChoice {pendingRouteOutput=nil;store.dispatch(.setOutput(output))}
        }
    }
    /// GOR_VR_SIM_POSE=1 only (self-test): switch head tracking on without the camera (updateHeadTrackingCamera
// [attribution comment elided]
    private func simulatePoseIfRequested() {
        guard ProcessInfo.processInfo.environment["GOR_VR_SIM_POSE"] == "1" else { return }
        setHeadTrackingEnabled(true, remember: false)
    }
    func sendVRLookNudge(deltaX: CGFloat, deltaY: CGFloat, deltaRollDegrees:Double=0) {
        let dyawDeg   = Double(deltaX) * Self.vrYawPitchDegPerPoint
        let dpitchDeg = Double(deltaY) * Self.vrYawPitchDegPerPoint
        let dyawRad   = dyawDeg   * Double.pi / 180.0
        let dpitchRad = dpitchDeg * Double.pi / 180.0
        ipcCommand("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-nudge\",\"\(dyawRad)\",\"\(dpitchRad)\",\"0\",\"\(deltaRollDegrees * Double.pi / 180)\"]}")
    }
    func sendVRFovNudge(deltaFovDegrees: Double) {
        ipcCommand("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-nudge\",\"0\",\"0\",\"\(deltaFovDegrees)\"]}")
    }

    // ── Core toggle ─────────────────────────────────────────────────────────

    func setVRModeEnabled(_ enabled: Bool) {
        guard applyingStore else {noteManualEnabled(enabled);return}
        vrModeEnabled = enabled
        ScreenCaptureEngine.shared.vrModeActive = enabled
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-enabled\",\"\(enabled ? "true" : "false")\"]}")
        if enabled {
            if Self.vrAutoFullscreen { sendRaw(#"{"command":["set","fullscreen","yes"]}"#) }
            sendSwapEyes(); sendPersistedBaseIPD()
            // Effects are explicit independent preferences; output changes never start head tracking.
            // Global effects are applied only from ThreeDStore, independent of output.
        } else {
            if Self.vrAutoFullscreen { sendRaw(#"{"command":["set","fullscreen","no"]}"#) }
        }
        traceCameraState("vrMode")
        updateCameraTraceHeartbeat()
    }

    /// GOR_TRACE_GEOM=1 only: 1 Hz settled-state samples while VR is on, so the
    /// self-test can observe the capture session over a window instead of relying on
    /// a single transition line.
    private var cameraTraceTimer: DispatchSourceTimer?
    private func updateCameraTraceHeartbeat() {
        guard GeomTrace.on else { return }
        cameraTraceTimer?.cancel(); cameraTraceTimer = nil
        guard vrModeEnabled else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.traceCameraState("tick") }
        t.resume()
        cameraTraceTimer = t
    }

    /// Republish the canonical persisted dial when VR starts, including its zero default.
    func sendPersistedBaseIPD() {
        // Always republish the canonical mm, including 0: a re-entry must not keep a stale Lua mode/value.
        publishBaseIPD(currentBaseIPD, persist: false)
    }
    private func sendSwapEyes() {
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-swap-eyes\",\"\(swapEyes ? "1" : "0")\"]}")
    }

    func setSwapEyes(_ on: Bool) {
        guard applyingStore else {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.crossEye,.bool(on)))};return}
        swapEyes = on
        sendSwapEyes(); showBlinkOSD(on ? "cross-eye order on" : "cross-eye order off")
    }

    /// Blink log-only measurement (phase 2): needs head-tracking frames; starts nothing by itself.
    var blinkLogEnabled: Bool {
        if #available(macOS 12.0, *) { return HeadTracker.shared.blinkLogEnabled }
        return false
    }
    var onSoftVideoBlink: ((Double) -> Void)?
    private func showBlinkOSD(_ text: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": ["show-text", text, 3500]]),
              let json = String(data: data, encoding: .utf8) else { return }
        sendRaw(json)
    }
    func sendRaw(_ original: String) { // [attribution comment elided]
        var json=original
        if var object=(try? JSONSerialization.jsonObject(with:Data(json.utf8))) as? [String:Any],
           var command=object["command"] as? [Any],command.count>2,
           let name=command[2] as? String,ThreeDRouteEnvelope.messages.contains(name) {
            guard applyingStore else {Diag.log("3D-REJECTED sender=controller-outside-applier message=\(name) values=\(command) revision=none");return}
            let revision=routeRevision
            if name == "vr180-look-plan-lock" && command.count == 4 {command.append("false")}
            // arch-195c N3: no Swift-side admission gate on the mpv wire.
            // Stamped commands go out exactly as shipped; the restored
            // shipped Lua owns admission and the 3D-REJECTED record.
            command += [String(revision),"store-applier"];object["command"]=command
            if let data=try? JSONSerialization.data(withJSONObject:object),let encoded=String(data:data,encoding:.utf8) {json=encoded}
        }
        MainActor.assumeIsolated {ThreeDStore.shared.recordAppliedCommand(json)}
        ipcCommand(json)
    }
    var singleSwitchActive = false, singleSwitchPending = false; private(set) var detectedStereoKind: String?        // native detection of the open film (nil = not known to be stereo), read by singleSwitchPlan()
    /// Idempotent blink-control switch: the shift+e / menu toggle and the VR-entry default
    /// both land here. Blink owns a camera consumer (updateCaptureConsumers), so it works
    /// whether or not head tracking is on - the 7634 route started no camera at all unless
    /// head tracking was already running, which is why nothing responded.
    @discardableResult
    func setBlinkControlEnabled(_ on: Bool, osd: Bool = true, remember: Bool = true) -> Bool {
        if remember && !applyingStore {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.blink,.bool(on)))};return on}
        guard #available(macOS 12.0, *) else {
            if osd { showBlinkOSD("blink control needs macOS 12 or later") }
            return false
        }
        blinkControlPreferred = on

        if on == HeadTracker.shared.blinkLogEnabled {
            updateCaptureConsumers()   // state unchanged; the camera may still need reconciling (file loaded, VR re-entry)
            if osd { showBlinkOSD(on ? "blink control on" : "blink control off") }
            return on
        }
        HeadTracker.shared.blinkLogEnabled = on   // turning off snapshots the session atomically inside the setter
        onExplorableSurface?()
        traceCameraState("blinkLog")
        if on {
            // gor.vr.blinkAnalog / gor.vr.blinkRobust: default ON; defaults write ... -bool NO restores the previous behaviour.
            IntentionalEyeClosure.analog = (UserDefaults.standard.object(forKey: "gor.vr.blinkAnalog") as? Bool) ?? true
            EyeGestureCommands.robust = (UserDefaults.standard.object(forKey: "gor.vr.blinkRobust") as? Bool) ?? true
            // gor.vr.blinkCadence / gor.vr.poseHoldLock (197i): default ON; -bool NO restores the shipped behaviour byte-identically.
            EyeGestureCommands.cadenceAdaptive = (UserDefaults.standard.object(forKey: "gor.vr.blinkCadence") as? Bool) ?? true
            HeadTracker.poseHoldLock = (UserDefaults.standard.object(forKey: "gor.vr.poseHoldLock") as? Bool) ?? true
            sendRaw(BlinkCommandRoute.analogIPC(IntentionalEyeClosure.analog))
            HeadTracker.shared.onBlinkIndicator = nil
// Source commentary elided for privacy; historical proof hashes are not rebound.
            HeadTracker.shared.onEyeClosure = { [weak self] left, right, uncertain in
                self?.sendRaw(BlinkCommandRoute.lidsIPC(left, right, uncertain))
            }
            HeadTracker.shared.onBlinkControl = nil // [attribution comment elided]
            HeadTracker.shared.onEyeCommand = { [weak self] command in
                guard let self, self.loadedVideoActive else { return }
                switch command {
                case let .seek(seconds): self.sendRaw(BlinkCommandRoute.seekIPC(seconds, commandHeld: NSEvent.modifierFlags.contains(.command)))
                case .playPause: if NSEvent.modifierFlags.contains(.control) { self.sendRaw(BlinkCommandRoute.playPauseIPC) }
                }
            }
            GeomTrace.beginBlinkLog(session: HeadTracker.shared.blinkSessionID) { [weak self] sid, reason in
                // Diagnostic storage failure: GeomTrace has already set blinkLogStopped for this session,
                // so no further disk writes happen and this callback never fires twice per session. Blink
                // CONTROL does not depend on the measurement log, but SCE's recognizer (logBlinkSample /
                // captureOutput) is gated on blinkLogEnabled - so the session, epoch, callbacks, preference
                // and camera consumer all stay exactly as they are: no stopBlinkLogIfCurrent, no flush, no
                // session close while live. Delivered on main; both reads below are main-serialized with
                // every session transition, so a stale failure from before an OFF->ON has zero effects.
                guard HeadTracker.shared.blinkLogEnabled, HeadTracker.shared.blinkSessionID == sid else { return }
                self?.showBlinkOSD("\(reason) - blink control stays on")
            }
        } else {
            HeadTracker.shared.flushBlinkSummary(osd: nil)
            blinkControlDidStop(osd: nil)
        }
        updateCaptureConsumers()
        if osd { showBlinkOSD(on ? "blink control on" : "blink control off") }
        return on
    }

    /// Single off-path for every stop cause (manual toggle, VR exit, diagnostic storage
    /// failure): clears the live callbacks, zeroes the shader lids through the production
    /// IPC route and releases the blink camera consumer. Safe when already stopped.
    private func blinkControlDidStop(osd: String?) {
        if #available(macOS 12.0, *) {
            HeadTracker.shared.onBlinkIndicator = nil
            HeadTracker.shared.onBlinkDetected = nil
            HeadTracker.shared.onEyeClosure = nil
            HeadTracker.shared.onEyeCommand = nil
            HeadTracker.shared.onBlinkControl = nil
        }
        sendRaw(BlinkCommandRoute.lidsClearedIPC)
        updateCaptureConsumers()
        if let osd { showBlinkOSD(osd) }
    }

    @discardableResult
    func toggleBlinkLog() -> Bool {
        setBlinkControlEnabled(!blinkControlPreferred)
    }

    @discardableResult
    func toggleSwapEyes() -> Bool {
        setSwapEyes(!swapEyes)
        return swapEyes
    }

    @discardableResult
    func toggleHeadTracking() -> Bool {
        setHeadTrackingEnabled(!headTrackingEnabled)
        showBlinkOSD(headTrackingEnabled ? "head tracking on" : "head tracking off")
        return headTrackingEnabled
    }


    /// Explicit choices are remembered; automatic VR stops preserve that preference.
    var onExplorableSurface: (() -> Void)?
    func setHeadTrackingEnabled(_ enabled: Bool, remember: Bool = true) {
        if remember && !applyingStore {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.head,.bool(enabled)))};return}
        headTrackingPreferred=enabled
        guard enabled != headTrackingEnabled else { return }
        guard #available(macOS 12.0, *) else {
            print("[VR180Controller] Head-tracking needs macOS 12+ (VNDetectFaceRectanglesRequest revision 3).")
            return
        }
        headTrackingEnabled = enabled
        onExplorableSurface?()
        if !enabled { resetOrientation() }
        updateCaptureConsumers()
        traceCameraState("headTracking")
    }

    /// GOR_TRACE_GEOM=1 only: records whether the capture session is requested /
    /// running so the self-test can assert that opening a VR file does not start it.
    func traceCameraState(_ why: String) {
        guard GeomTrace.on else { return }
        var requested = false, running = false, consumers = 0, ambient = false
        if #available(macOS 12.0, *) {
            requested = HeadTracker.shared.isRequested
            running = HeadTracker.shared.isRunning
            (consumers, ambient) = HeadTracker.shared.traceConsumers
        }
        let vrOwned = consumers - (ambient ? 1 : 0)
        GeomTrace.log("vrCamera", "{\"k\":\"vrCamera\",\"why\":\"\(why)\",\"vr\":\(vrModeEnabled),\"head\":\(headTrackingEnabled),\"camActive\":\(headTrackingCameraActive),\"sessionRequested\":\(requested),\"sessionRunning\":\(running),\"consumers\":\(consumers),\"ambient\":\(ambient),\"vrOwned\":\(vrOwned)}")
    }

    /// Reconciles BOTH camera consumers on every state change - no shared early return,
    /// so an unchanged leg never skips the other (7634 returned early on the head edge and
    /// blink had no leg at all). Head-motion keeps its pause policy (playbackActive); the
    /// loadedVideoActive signal keeps paused head motion and blink live.
    private func updateCaptureConsumers() {
        guard #available(macOS 12.0, *) else { return }
        refreshToolsActive()
        let headShould = CaptureConsumerRules.headShouldRun(headTrackingEnabled: headTrackingEnabled, playbackActive: loadedVideoActive)
        if headShould != headTrackingCameraActive {
            headTrackingCameraActive = headShould
            if headShould {
                HeadTracker.shared.beginPoseSession(); HeadTracker.shared.onPoseUpdate = { [weak self] pose in
                    self?.applyHeadPose(pose)
                }
                if ProcessInfo.processInfo.environment["GOR_VR_SIM_POSE"] == "1" {
                    HeadTracker.shared.startSimulatedPose()   // self-test only: synthetic pose, camera never started
                } else {
                    HeadTracker.shared.start(owner: 1)
                    headOwnsRealCameraConsumer = true
                }
            } else {
                HeadTracker.shared.onPoseUpdate = nil;onSubtitleTilt?(0,0);onUITilt?(0)
                HeadTracker.shared.stopSimulatedPose()
                if headOwnsRealCameraConsumer {   // SIM_POSE acquired nothing: never release the blink leg's consumer
                    HeadTracker.shared.stop(owner: 1)
                    headOwnsRealCameraConsumer = false
                }
            }
        }
        let blinkShould = CaptureConsumerRules.blinkShouldRun(blinkOn: HeadTracker.shared.blinkLogEnabled,
                                                              vrEnabled: vrModeEnabled,
                                                              loadedVideoActive: loadedVideoActive,
                                                              cameraAllowed: Self.blinkCameraAllowed)
        if blinkShould != blinkCameraActive {
            blinkCameraActive = blinkShould
            // Blink needs frames only: never touches the onPoseUpdate slot (the head leg's
            // alone); logBlinkSample runs on every delivered camera frame in the engine.
            if blinkShould { HeadTracker.shared.start(owner: 2) } else { HeadTracker.shared.stop(owner: 2) }
        }
    }

    /// Automated tests never open the camera (same posture as headTrackingAutoStartAllowed).
    static var blinkCameraAllowed: Bool {
        ProcessInfo.processInfo.environment["GOR_VR_TEST_NO_CAMERA"] != "1"
    }

    private var recenterPosePublishing=false
    var onSubtitleTilt:((Double,Double)->Void)?
    var onVRModeApplied:((Bool)->Void)?
    var onUITilt:((Double)->Void)?
    private(set) var depthDistanceMM: Double?
    private func applyHeadPose(_ pose: HeadPose) {
        depthDistanceMM = pose.distanceMM
        guard headTrackingEnabled, loadedVideoActive else { return }
        //192d: all tracked pose filtering happens in Swift before this message.
        let direction=MainActor.assumeIsolated {ThreeDStore.shared.snapshot.effects[.headInvert] == .bool(true) ? -1.0:1.0}
        let yaw   = direction * Self.headRotationGain * pose.yaw
        let pitch = direction * Self.headRotationGain * pose.pitch
        let fov:Double
        if projectionKind.hasPrefix("vr") {
            fov=Self.headTrackingRestFovDeg + direction * Self.headFovGain * Self.headLeanNudgeFovDegPerUnit * pose.zOffset
        } else {
            // Display policy, not a camera-validity threshold: a flat film stays
            // at90...125% for head distance; manual zoom-out has its own wider rail.
            // Keep the measured pupil ratio in scale space, with the original sensitivity.
            let measured=1+direction*Self.headFovGain*pose.zOffset
            let scale=measured.isFinite ? min(1.25,max(0.90,measured)):1
            fov=2*atan(tan(Self.headTrackingRestFovDeg*Double.pi/360)/scale)*180/Double.pi
        }
        let roll  = direction * Self.headRotationGain * pose.roll
        let filmRoll=projectionKind.hasPrefix("vr") ? (direction * (pose.nativeRawRoll ?? pose.roll)):roll
        let pairRoll=projectionKind.hasPrefix("vr") ? (direction * (pose.fusionRoll ?? pose.roll)):roll
        let overlayRoll=projectionKind.hasPrefix("vr") ? 0:filmRoll
        onSubtitleTilt?(overlayRoll,projectionKind.hasPrefix("vr") ? 0:pairRoll*(swapEyes ? 1:-1))
        onUITilt?(overlayRoll)
        let headX = direction * Self.headTranslateMetersPerUnit * pose.xOffset
        let headY = direction * Self.headTranslateMetersPerUnit * pose.yOffset
        let headZ = 0.0 //192d D2: fov alone carries distance zoom, never a second multiplying headZ
        // Convergence is the same bounded display-distance request for a flat
        // film. Keeping the raw value here would bypass its viewport envelope.
        let flatDistance=pose.zOffset.isFinite ? min(0.25,max(-0.10,pose.zOffset)):0
        let ipdNudge = Self.headIpdNudgePerUnit * (projectionKind.hasPrefix("vr") ? pose.zOffset:flatDistance)
        // Block 182 2: the distance rule lives in vr180-look.lua; these three args ride on the same message.
        let distArg = pose.distanceMM.map { String(format: "%.2f", $0) } ?? "none"
        let distReason = pose.distanceFallback ?? "ok"
        let mmPerPx = VRDistance.mmPerPx()
        let ordered=recenterPosePublishing ? ",\"request_id\":194" : ""
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-orientation\",\"\(yaw)\",\"\(pitch)\",\"\(fov)\",\"\(roll)\",\"\(ipdNudge)\",\"\(headX)\",\"\(headY)\",\"\(headZ)\",\"\(distArg)\",\"\(distReason)\",\"\(mmPerPx)\",\"\(direction * (pose.fusionRoll ?? pose.roll))\",\"\(direction * (pose.nativeRawRoll ?? pose.roll))\"]\(ordered)}")
    }

    func recenterHeadTracking() {
        guard #available(macOS 12.0, *) else { return }
        resetFilmView()
        recenterPosePublishing=true;defer {recenterPosePublishing=false}
        HeadTracker.shared.recenter()
    }

    /// 180d test surface: the session IPD value for the selftest's
    /// snapshot/restore (the state itself stays private).
    var testCurrentBaseIPD: Double { currentBaseIPD }

    /// Absolute test cleanup through the same controller publication path.
    /// Inert without geometry tracing; restores the saved preference to its snapshot (below).
    /// Taken once when the selftest snapshots the dial: exact presence and value of the canonical key.
    private var testIPDSnapshot: (had: Bool, mm: Double, runtimeMM: Double)?
    func snapshotIPDForTest() { }
    func restoreBaseIPDForTest(_ value:Double) {
        guard GeomTrace.on else {return}
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.ipd,.number(value*Self.ndcToMM)))}
    }

    func adjustBaseIPD(by delta: Double) {
        MainActor.assumeIsolated {let store=ThreeDStore.shared;let current:Double;if case let .number(v)?=store.snapshot.effects[.ipd] {current=v} else {current=0};store.dispatch(.setEffect(.ipd,.number(current+delta*Self.ndcToMM)))}
    }
    private func publishBaseIPD(_ value: Double, persist: Bool = true) {
        currentIPDOffsetMM = value * Self.ndcToMM
        if persist && !applyingStore {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.ipd,.number(currentIPDOffsetMM)))};return}
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-ipd-mm\",\"\(currentIPDOffsetMM)\"]}")
        GeomTrace.log("vrIPD", String(format: #"{"k":"vrIPD","v":%.17g,"mm":%.17g}"#, currentBaseIPD, currentIPDOffsetMM))
    }
}

// ================================================================
//  InputController - mouse and keyboard routing
// ================================================================
final class InputController {
    private var keyMonitor:           Any?
    private var gorHeldMotion:        [UInt16: (Int, Int, Int)] = [:]
    private var gorMotionReleaseMonitor: Any?
    private var gorFocusObservers:    [NSObjectProtocol] = []
    private var brightnessKeyMonitor: Any?
    private var lastMouseMoveTime           = Date()
    private var lastVariationUpdate         = Date()
    private weak var view: NSView?
    private let ipcCommand: (String) -> Void
    private let wakeUI: () -> Void
    private let musicModeActive: () -> Bool
    private let iptvModeActive: () -> Bool
    private let musicHitTest: (CGPoint) -> Bool
    private let iptvHitTest: (CGPoint) -> Bool
    private let isShowingInputPanel: () -> Bool
    private let spineAlpha: () -> CGFloat
    private let updateVariationBroadcaster: (NSPoint) -> Void
    private let notifyBrightnessKeyChanged: () -> Void
    private let volume: () -> Float
    private let setVolume: (Float) -> Void
    private let seekRelative: (Double) -> Void
    private let simulateVolumeHover: () -> Void
    private let toggleRandomSubtitlePosition: () -> Void
    private let moveSubtitleToDefaultPosition: (Int) -> Void
    private let hitTest: (NSPoint) -> NSView?
    private let dismissActiveDropdown: () -> Void
    private let toggleFullScreenIfNotInPanel: () -> Void
    private let inSpineOrSidebar: (NSPoint) -> Bool
    private let moveMpv: (CGFloat, CGFloat) -> Void
    private let resetMpvPositionCache: () -> Void

    init(
        view: NSView,
        ipcCommand: @escaping (String) -> Void,
        wakeUI: @escaping () -> Void,
        musicModeActive: @escaping () -> Bool,
        iptvModeActive: @escaping () -> Bool,
        musicHitTest: @escaping (CGPoint) -> Bool,
        iptvHitTest: @escaping (CGPoint) -> Bool,
        isShowingInputPanel: @escaping () -> Bool,
        spineAlpha: @escaping () -> CGFloat,
        updateVariationBroadcaster: @escaping (NSPoint) -> Void,
        notifyBrightnessKeyChanged: @escaping () -> Void,
        volume: @escaping () -> Float,
        setVolume: @escaping (Float) -> Void,
        seekRelative: @escaping (Double) -> Void,
        simulateVolumeHover: @escaping () -> Void,
        toggleRandomSubtitlePosition: @escaping () -> Void,
        moveSubtitleToDefaultPosition: @escaping (Int) -> Void,
        hitTest: @escaping (NSPoint) -> NSView?,
        dismissActiveDropdown: @escaping () -> Void,
        toggleFullScreenIfNotInPanel: @escaping () -> Void,
        inSpineOrSidebar: @escaping (NSPoint) -> Bool,
        moveMpv: @escaping (CGFloat, CGFloat) -> Void,
        resetMpvPositionCache: @escaping () -> Void
    ) {
        self.view = view
        self.ipcCommand = ipcCommand
        self.wakeUI = wakeUI
        self.musicModeActive = musicModeActive
        self.iptvModeActive = iptvModeActive
        self.musicHitTest = musicHitTest
        self.iptvHitTest = iptvHitTest
        self.isShowingInputPanel = isShowingInputPanel
        self.spineAlpha = spineAlpha
        self.updateVariationBroadcaster = updateVariationBroadcaster
        self.notifyBrightnessKeyChanged = notifyBrightnessKeyChanged
        self.volume = volume
        self.setVolume = setVolume
        self.seekRelative = seekRelative
        self.simulateVolumeHover = simulateVolumeHover
        self.toggleRandomSubtitlePosition = toggleRandomSubtitlePosition
        self.moveSubtitleToDefaultPosition = moveSubtitleToDefaultPosition
        self.hitTest = hitTest
        self.dismissActiveDropdown = dismissActiveDropdown
        self.toggleFullScreenIfNotInPanel = toggleFullScreenIfNotInPanel
        self.inSpineOrSidebar = inSpineOrSidebar
        self.moveMpv = moveMpv
        self.resetMpvPositionCache = resetMpvPositionCache
    }

    var timeSinceLastMouseMove: TimeInterval {
        Date().timeIntervalSince(lastMouseMoveTime)
    }

    // MARK: - Keyboard

    func startKeyboardMonitor() {
        // Re-arming must not orphan an active local monitor. The newest
        // registration owns each key event; route/reset semantics stay unchanged.
        if let previous = keyMonitor {
            NSEvent.removeMonitor(previous)
            keyMonitor = nil
        }
        startGorMotionReleaseWatch()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }
            if self.musicModeActive() { return e }
            if self.iptvModeActive() { return e }
            if self.isShowingInputPanel() || PanelKeyOwnership.shared.panelOwnsKey || e.window is GORInputPanel { return e }

            if e.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option] {
                let clipKeys: [UInt16: String] = [8: "c", 5: "g", 6: "z", 7: "x", 31: "o", 3: "f"]
                if let key = clipKeys[e.keyCode] {
                    self.ipcCommand("{\"command\":[\"keypress\",\"Meta+Alt+\(key)\"]}")
                    return nil
                }
            }

            if let message = self.grainSizeTrimMessage(e) {
                guard self.hasPlayerKeyFocus(e) else { return e }
                self.sendGrainSizeTrim(message)
                return nil
            }

            if self.isPhotonAdjustKey(e) {
                guard self.hasPlayerKeyFocus(e) else { return e }
                self.forwardKeyToMPV(e)
                return nil
            }

            if self.gorMotionMatches(e) {
                guard self.hasPlayerKeyFocus(e) else { return e }
                self.gorMotionApply(e)
                return nil
            }

            if e.modifierFlags.contains(.command) { return e }

            if self.handleSpecialKeyCommands(event: e) { return nil }
            self.forwardKeyToMPV(e)
            return nil
        }
    }

    func startBrightnessKeyMonitor() {
        brightnessKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] e in
            guard e.subtype.rawValue == 8 else { return e }
            let keyCode = (e.data1 & 0xFFFF0000) >> 16
            if keyCode == 2 || keyCode == 3 {
                self?.notifyBrightnessKeyChanged()
            }
            return e
        }
    }
    private func handlePictureInPictureCornerKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty, hasPlayerKeyFocus(event),
              let direction = PlayerPictureInPicture.direction(
                keyCode: event.keyCode,
                fnHeld: CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)),
              let app = NSApp.delegate as? AppDelegate else { return false }
        return app.movePictureInPicture(direction: direction)
    }
// [attribution comment elided]
    /// (L/R volume, U/D seek), Shift+digit speeds, Shift+V/H/R/[/],
    /// and Cmd+Opt+C/G/Z/X/O/F (re-emitted to mpv as Meta+Alt+*). Everything
    /// else is forwarded to mpv via mpvKeyName. input.conf must mirror
    /// the Swift-owned set - keep them in sync when editing either side.
    private func handleSpecialKeyCommands(event: NSEvent) -> Bool {
        if handlePictureInPictureCornerKey(event) { return true }
        let flags   = event.modifierFlags
        let keyCode = event.keyCode

        if [123, 124, 125, 126].contains(keyCode) { wakeUI() }

        if keyCode == 123, !flags.contains(.command), !flags.contains(.shift) {
            let newVol = max(0, volume() - 0.05)
            setVolume(newVol)
            simulateVolumeHover()
            return true
        }

        if keyCode == 124, !flags.contains(.command), !flags.contains(.shift) {
            let newVol = min(1, volume() + 0.05)
            setVolume(newVol)
            simulateVolumeHover()
            return true
        }

        if keyCode == 126, !flags.contains(.command), !flags.contains(.shift) {
            seekRelative(60); return true
        }

        if keyCode == 125, !flags.contains(.command), !flags.contains(.shift) {
            seekRelative(-60); return true
        }

        if flags.contains(.shift) {
            if let keyChar = event.charactersIgnoringModifiers?.first,
               keyChar == "0" {
                toggleRandomSubtitlePosition()
                return true
            }
        }

        // 191b B5: the ONE keymap table (ThreeDKeymap.rows) drives both the 3d menu key equivalents and this keyboard path,
        // so they can never diverge. Exact modifier equality; keyCode pins the physical bracket keys (ANSI 30=']', 33='[')
        // because Shift/Option change the typed glyph. Anything not in the table falls through to mpv exactly as before.
        // Cross-eye stays Ctrl+Shift+X (Shift+X/Option+X are photon sharpen, non-3D); subtitle depth moved to Ctrl+Shift+[/]
        // because B4 claims Option+Shift+[/] for VR180 screen size. See ThreeDKeymap.moves for the full audit.
        if let act = ThreeDKeymap.match(charactersIgnoringModifiers: event.charactersIgnoringModifiers, keyCode: Int(keyCode),
                                        shift: flags.contains(.shift), option: flags.contains(.option),
                                        control: flags.contains(.control), command: flags.contains(.command)) {
            if !event.isARepeat { MainActor.assumeIsolated {ThreeDMenu.dispatch(act)} }
            return true
        }

        if flags.contains(.shift) {
            guard let keyChar = event.charactersIgnoringModifiers?.first,
                  let number  = Int(String(keyChar)),
                  (1...9).contains(number) else { return false }
            moveSubtitleToDefaultPosition(number)
            return true
        }

        return false
    }

    // Size trim is separate from amount/strength; plain b keeps its existing binding.
    private func grainSizeTrimMessage(_ event: NSEvent) -> String? {
        guard event.charactersIgnoringModifiers?.lowercased() == "b" else { return nil }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == [.shift] { return "photon-grain-size-trim-up" }
        if flags == [.command] { return "photon-grain-size-trim-down" }
        if flags == [.command, .shift] { return "photon-grain-size-trim-reset" }
        return nil
    }
    private func sendGrainSizeTrim(_ message: String) {
        ipcCommand("{\"command\":[\"script-message-to\",\"photon_grain\",\"\(message)\"]}")
    }

    // Grain "strength" shortcuts adjust amount offset; sharp adjusts its factor;
    // Cmd/Shift+B trims grain size; Cmd+Shift+B resets trim.
    // Accept only exact Shift or Command modifiers, ignoring Caps Lock.
    private func isPhotonAdjustKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == [.command] || flags == [.shift],
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return key == "g" || key == "x"
    }

    // gor motion keys. The easing lives in gor-fit.lua. A held key is sent as "hold dx dy dz" on every key-down and key
    // repeat; "hold 0 0 0" goes out on key-up, when shift/fn is let go, or when the app/window loses focus. The lua only
    // follows the held direction (speed eases in and out), so nothing is queued and nothing runs on after release.
    //   fn+shift+arrows  move the picture. Matched by the keyCodes a Mac keyboard reports for fn+arrow (Home 115, End 119,
    //                    Page Up 116, Page Down 121). Plain arrows (123-126) are NOT matched, so shift+arrow is untouched.
    //   fn+shift+, / .   zoom in / zoom out. Matched by PHYSICAL keyCode (43 = the ANSI comma key, 47 = the ANSI period key)
    //                    or by the typed character; both need fn+shift held.
    //   plain = and -    the zoom keys the menu already declares (single steps).
    // Platform facts used: NSEvent.ModifierFlags.function is set for any function key (F-keys, Home/End/Page Up/Down and the
    // arrows) and, per developer reports, while fn is held. Because it is set for the navigation keys themselves it cannot
    // tell fn+arrow from a real Home/End key; the keyCode is what narrows it. None of this has run on a Mac.
    // Plain arrows (123 left, 124 right, 125 down, 126 up) are accepted ONLY while the fn key is physically down according
    // to the session's modifier state (CGEventSource.flagsState / .maskSecondaryFn, the documented "Fn key is down" flag).
    // The event's own .function flag cannot tell them apart (arrows always carry it), so without a held fn plain shift+arrow
    // is untouched. This is an extra route for keyboards that deliver fn+arrow as an arrow instead of Home/End/Page keys.
    // Unverified on a Mac. Unmatched shift+fn keys are logged (first 25 only) so a real build shows the codes it receives.
    private var gorKeyLogCount = 0
    private func gorMotionVector(_ event: NSEvent) -> (Int, Int, Int)? {
        let v = gorMotionVectorCore(event)
        if v == nil, gorKeyLogCount < 25, event.type == .keyDown,
           event.modifierFlags.contains(.shift), event.modifierFlags.contains(.function),
           !event.modifierFlags.contains(.command) {
            gorKeyLogCount += 1
            print("[gor-motion] unmatched shift+fn key: keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") flags=\(event.modifierFlags.rawValue)")
        }
        return v
    }
    private func gorMotionVectorCore(_ event: NSEvent) -> (Int, Int, Int)? {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        guard mods.contains(.shift), mods.contains(.function),
              !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return nil }
        switch event.keyCode {
        case 115: return (-1, 0, 0)
        case 119: return (1, 0, 0)
        case 116: return (0, -1, 0)
        case 121: return (0, 1, 0)
        case 43:  return (0, 0, 1)
        case 47:  return (0, 0, -1)
        case 123, 124, 125, 126:
            guard CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) else { return nil }
            switch event.keyCode {
            case 123: return (-1, 0, 0)
            case 124: return (1, 0, 0)
            case 126: return (0, -1, 0)
            default:  return (0, 1, 0)
            }
        default: break
        }
        switch event.charactersIgnoringModifiers ?? "" {
        case ",", "<": return (0, 0, 1)
        case ".", ">": return (0, 0, -1)
        default: return nil
        }
    }
    private func gorMotionStep(_ event: NSEvent) -> String? {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty else { return nil }
        switch event.charactersIgnoringModifiers ?? "" {
        case "=": return LookToolsRoute.motionJSON(kind:"step",z:1,projection:(view as? PPController)?.vrModeEnabled == true)
        case "-": return LookToolsRoute.motionJSON(kind:"step",z:-1,projection:(view as? PPController)?.vrModeEnabled == true)
        default: return nil
        }
    }
    private func gorMotionMatches(_ event: NSEvent) -> Bool {
        return gorMotionVector(event) != nil || gorMotionStep(event) != nil
    }
    private func gorMotionApply(_ event: NSEvent) {
        if let v = gorMotionVector(event) {
            gorHeldMotion[event.keyCode] = v
            gorSendHold()
        } else if let step = gorMotionStep(event) {
            ipcCommand(step)
        }
    }
    private func gorSendHold() {
        var x = 0, y = 0, z = 0
        for v in gorHeldMotion.values { x += v.0; y += v.1; z += v.2 }
        x = max(-1, min(1, x)); y = max(-1, min(1, y)); z = max(-1, min(1, z))
        ipcCommand(LookToolsRoute.motionJSON(kind:"hold",x:x,y:y,z:z,projection:(view as? PPController)?.vrModeEnabled == true))
    }
    private func gorReleaseAllMotion() {
        guard !gorHeldMotion.isEmpty else { return }
        gorHeldMotion.removeAll()
        gorSendHold()
    }

    // Key-up, shift/fn released, and focus loss all end a held move/zoom. (gor-fit.lua also stops by itself 0.6 s after the
    // last refresh if a key-up is ever lost.)
    private func startGorMotionReleaseWatch() {
        if let old = gorMotionReleaseMonitor { NSEvent.removeMonitor(old) }
        gorMotionReleaseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] e in
            guard let self = self, !self.gorHeldMotion.isEmpty else { return e }
            if e.type == .keyUp {
                if self.gorHeldMotion.removeValue(forKey: e.keyCode) != nil { self.gorSendHold() }
                else if !e.modifierFlags.contains(.shift) { self.gorReleaseAllMotion() }
            } else if !e.modifierFlags.contains(.shift) || !e.modifierFlags.contains(.function) {
                self.gorReleaseAllMotion()
            }
            return e
        }
        if gorFocusObservers.isEmpty {
            let c = NotificationCenter.default
            for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification] {
                gorFocusObservers.append(c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.gorReleaseAllMotion()
                })
            }
        }
    }
    private func hasPlayerKeyFocus(_ event: NSEvent) -> Bool {
        guard !musicModeActive(), !iptvModeActive(), !isShowingInputPanel(),
              let player = view as? PPController,
              let window = player.window,
              window.isKeyWindow, NSApp.keyWindow === window,
              event.window === window,
              let responder = window.firstResponder else { return false }
        // Positive identity guard rejects every text field, field editor and
        // editable control, including future/custom ones, without a panel list.
        guard !(responder is NSText), !(responder is NSTextView),
              !(responder is NSControl) else { return false }
        return responder === player
    }

    private func forwardKeyToMPV(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == " " &&
            flags.intersection([.command, .control, .option, .shift]).isEmpty {
            ipcCommand(#"{"command":["cycle","pause"]}"#)
            return
        }
        let mpvKey = mpvKeyName(event)
        guard !mpvKey.isEmpty else { return }
        let escaped = mpvKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        ipcCommand("{\"command\":[\"keypress\",\"\(escaped)\"]}")
    }

    private func mpvKeyName(_ event: NSEvent) -> String {
        let mods  = event.modifierFlags
        var parts = [String]()
        // Never turn arbitrary Command events into mpv keys.
        if mods.contains(.command) {
            guard isPhotonAdjustKey(event), hasPlayerKeyFocus(event) else { return "" }
            parts.append("Meta")
        }
        if mods.contains(.control) { parts.append("Ctrl") }
        if mods.contains(.option)  { parts.append("Alt")  }
        if mods.contains(.shift)   { parts.append("Shift") }

        let specialKeys: [UInt16: String] = [
            36: "ENTER",  48: "TAB",       51: "BS",          53: "ESC",
            63: "PLAYPAUSE",
            71: "KP0",    75: "KP_DEC",    76: "KP_ENTER",
            78: "KP_SUBTRACT",             81: "KP_EQUAL",    82: "KP0",
            96: "F5",     97: "F6",        98: "F7",          99: "F3",
           100: "F8",    101: "F9",       103: "F11",
           109: "F10",   111: "F12",      118: "F4",
           120: "F2",    122: "F1",       123: "LEFT",       124: "RIGHT",
           125: "DOWN",  126: "UP",
        ]

        if let special = specialKeys[event.keyCode] {
            parts.append(special)
        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let c = chars.lowercased()
            switch c {
            case " ":           parts.append("SPACE")
            case "\t":          parts.append("TAB")
            case "\r", "\n":    parts.append("ENTER")
            case "\u{1b}":      parts.append("ESC")
            default:            parts.append(c)
            }
        } else {
            return ""
        }
        return parts.joined(separator: "+")
    }

    @discardableResult
    func handleViewKeyDown(_ event: NSEvent) -> Bool {
        if let message = grainSizeTrimMessage(event) {
            guard hasPlayerKeyFocus(event) else { return false }
            sendGrainSizeTrim(message)
            return true
        }
        if isPhotonAdjustKey(event) {
            guard hasPlayerKeyFocus(event) else { return false }
            forwardKeyToMPV(event)
            return true
        }
        if gorMotionMatches(event) {
            guard hasPlayerKeyFocus(event) else { return false }
            gorMotionApply(event)
            return true
        }
        // Command events not consumed by the local monitor belong to AppKit.
        if event.modifierFlags.contains(.command) { return false }
        if !handleSpecialKeyCommands(event: event) { forwardKeyToMPV(event) }
        return true
    }

    // MARK: - Mouse

    @discardableResult
    func handleMouseDown(with event: NSEvent) -> Bool {
        let loc     = event.locationInWindow
        let hit = hitTest(loc)

        var current: NSView? = hit
        while current != nil {
            if let dropRow  = current as? DropRow  {
                dropRow.mouseDown(with: event); return true
            }
            if let dropList = current as? DropdownList {
                dropList.dismiss(); return true
            }
            current = current?.superview
        }

        dismissActiveDropdown()

        if event.clickCount == 2 {
            guard let view = view else { return false }
            let convertedLoc = view.convert(loc, from: nil)
            let inMusic = musicHitTest(convertedLoc)
            let inIptv  = iptvHitTest(convertedLoc)
            if !inMusic, !inIptv { toggleFullScreenIfNotInPanel() }
        }
        return false
    }

    func handleMouseDragged(with event: NSEvent) {
        guard event.type == .leftMouseDragged, let view = view else { return }
        let loc       = view.convert(event.locationInWindow, from: nil)
        let inMusic   = musicHitTest(loc)
        let inIptv    = iptvHitTest(loc)
        if !inMusic, !inIptv, !inSpineOrSidebar(loc) {
            moveMpv(event.deltaX, event.deltaY)
        }
    }

    func handleMouseUp(with event: NSEvent) {
        resetMpvPositionCache()
    }

    func handleMouseEntered(with event: NSEvent) {
        lastMouseMoveTime = Date()
    }

    func handleMouseExited(with event: NSEvent) {
        lastMouseMoveTime = Date()
    }

    func handleMouseMoved(with event: NSEvent) {
        lastMouseMoveTime = Date()

        let throttle: TimeInterval = spineAlpha() > 0.5 ? 0.5 : 0.2

        let now = Date()
        if now.timeIntervalSince(lastVariationUpdate) > throttle {
            lastVariationUpdate = now
            updateVariationBroadcaster(event.locationInWindow)
        }
    }
}

// ================================================================
//  ContentAdaptiveDimming - scene-based display dimming
// ================================================================
final class ContentAdaptiveDimming {

    static let featureFlagEnabled: Bool = true

    var runtimeEnabled: Bool = false {
        didSet {
            guard runtimeEnabled != oldValue else { return }
            resetSceneTracking()
            if runtimeEnabled {
                setSceneTargetOverride { [weak self] in self?.smoothedBacklight ?? 1.0 }
            } else {
                setSceneTargetOverride(nil)
            }
            updateAmbientCameraFallback()
        }
    }

    // Camera sampling is allowed while a video is loaded, including while paused.
    // Idle, stopped and panel-only states with no video keep the camera off.
    // PPController supplies loaded-file state independently of pause.
    var playbackActive: Bool = false {
        didSet {
            guard playbackActive != oldValue else { return }
            if !playbackActive { playbackStalled = false }
            updateAmbientCameraFallback()
        }
    }

// [attribution comment elided]
    /// black seek/rebuffer frames. Sampling those as scene content dragged the
    /// backlight down during every post-seek wait (field log: hunting 93/88/98
    /// through a 153s stall, then a restore ramp). While stalled, hold the
    /// last real-scene target: no sampling, no target updates; the actuator
    /// converges to the held target and idles. Pause-by-user is NOT a stall;
    /// paused-frame sampling stays intentional.
    var playbackStalled: Bool = false

    private func updateAmbientCameraFallback() {
        guard #available(macOS 12.0, *) else { return }
        let shouldRun = runtimeEnabled && playbackActive && !AmbientLightProvider.shared.isAvailable
        if shouldRun {
            startAmbientDutyCycle()
        } else {
            stopAmbientDutyCycle()
        }
    }

    // MARK: - Ambient camera duty-cycling
    private static let ambientCheckpointFractions: [Double] = [0, 0.125, 0.25, 0.50, 0.75]

    private static let ambientDutyCycleOnDuration: TimeInterval = 2.0

    private static let ambientFirstWindowCeiling: TimeInterval = 15.0

    private var ambientCheckpointsFired: Set<Int> = []

    private var ambientDutyCycleCloseWorkItem: DispatchWorkItem?

    private var ambientRetryWorkItem: DispatchWorkItem?

    private static let ambientRetryDelay: TimeInterval = 7.0

    private var ambientDutyCycleActive = false

    private var firstAmbientWindowWorkItem: DispatchWorkItem?

    private static let firstAmbientWindowDelay: TimeInterval = 0.6

    @available(macOS 12.0, *)
    private func startAmbientDutyCycle() {
        guard !ambientDutyCycleActive else { return }
        ambientDutyCycleActive = true
        let firstWindowWork = DispatchWorkItem { [weak self] in
            self?.ambientCheckpointsFired.insert(0)
            self?.openAmbientWindow(isFirstWindow: true)
        }
        firstAmbientWindowWorkItem = firstWindowWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstAmbientWindowDelay, execute: firstWindowWork)
    }

    @available(macOS 12.0, *)
    private func stopAmbientDutyCycle() {
        ambientDutyCycleActive = false
        firstAmbientWindowWorkItem?.cancel()
        firstAmbientWindowWorkItem = nil
        ambientRetryWorkItem?.cancel()
        ambientRetryWorkItem = nil
        closeAmbientWindow(fromCeiling: false)
    }

    @available(macOS 12.0, *)
    func checkAmbientCheckpoints(currentTime: Double, duration: Double) {
        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }
        guard duration > 0 else { return }
        let progress = currentTime / duration
        for (index, fraction) in Self.ambientCheckpointFractions.enumerated() {
            guard !ambientCheckpointsFired.contains(index) else { continue }
            guard progress >= fraction else { continue }
            ambientCheckpointsFired.insert(index)
            Diag.mediaRecord("AMBIENT-WINDOW trigger=checkpoint fraction=\(fraction)"); openAmbientWindow()
            return
        }
    }

    @available(macOS 12.0, *)
    func handlePlaybackPaused() {
        // Pause-triggered sampling is intentional, but only for a loaded video.
        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }
        Diag.mediaRecord("AMBIENT-WINDOW trigger=pause"); openAmbientWindow()
    }

    func resetAmbientCheckpoints() {
        ambientCheckpointsFired.removeAll()
    }

    @available(macOS 12.0, *)
    private func openAmbientWindow(isFirstWindow: Bool = false) {
        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }
        ambientRetryWorkItem?.cancel()
        ambientRetryWorkItem = nil
        setAmbientWindowOpen(true)
        let ambientWindowOpenedAt = CACurrentMediaTime()
        Diag.mediaRecord("[AmbientDiag] window OPEN isFirstWindow=\(isFirstWindow) t=\(String(format: "%.2f", ambientWindowOpenedAt))")
        HeadTracker.shared.resetAmbientSettling()
        HeadTracker.shared.onAmbientFrame = { [weak self] in
            self?.closeAmbientWindow(fromCeiling: false, wasFirstWindow: isFirstWindow, openedAt: ambientWindowOpenedAt)
        }
        HeadTracker.shared.startAmbientOnly()
        ambientDutyCycleCloseWorkItem?.cancel()
        let ceilingWork = DispatchWorkItem { [weak self] in
            self?.closeAmbientWindow(fromCeiling: true, wasFirstWindow: isFirstWindow, openedAt: ambientWindowOpenedAt)
        }
        ambientDutyCycleCloseWorkItem = ceilingWork
        let ceiling = isFirstWindow ? Self.ambientFirstWindowCeiling : Self.ambientDutyCycleOnDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + ceiling, execute: ceilingWork)
    }

    @available(macOS 12.0, *)
    private func closeAmbientWindow(fromCeiling: Bool, wasFirstWindow: Bool = false, openedAt: CFTimeInterval? = nil) {
        if let openedAt {
            let lifetime = CACurrentMediaTime() - openedAt
            Diag.mediaRecord("[AmbientDiag] window CLOSE fromCeiling=\(fromCeiling) wasFirstWindow=\(wasFirstWindow) lifetime=\(String(format: "%.2f", lifetime))s ambientNilNow=\(AmbientLightProvider.shared.normalizedLevel() == nil)")
        }
        HeadTracker.shared.onAmbientFrame = nil
        HeadTracker.shared.stopAmbientOnly()
        ambientDutyCycleCloseWorkItem?.cancel()
        ambientDutyCycleCloseWorkItem = nil
        setAmbientWindowOpen(false)

        guard fromCeiling,
              AmbientLightProvider.shared.normalizedLevel() == nil else { return }

        ambientRetryWorkItem?.cancel()
        let retryWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard AmbientLightProvider.shared.normalizedLevel() == nil else { return }
            guard self.runtimeEnabled, self.playbackActive else { return }
            self.openAmbientWindow(isFirstWindow: wasFirstWindow)
        }
        ambientRetryWorkItem = retryWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ambientRetryDelay, execute: retryWork)
    }

    // MARK: - Dependencies (closures back to PPController, same

    private weak var hostView: NSView?
    private let setSceneTargetOverride: ((() -> Float)?) -> Void
    private let setBrightness: (Float) -> Void
    private let getCurrentBrightness: () -> Float
    private let isBrightnessFading: () -> Bool
    private let writeSceneStateToMPV: (_ backlight: Float, _ inertiaMode: String, _ isCut: Bool, _ ambientLevel: Double?, _ ambientSource: String, _ ambientRegions: (face: Double, room: Double)?, _ ambientLux: Double?) -> Void

    private let setAmbientWindowOpen: (Bool) -> Void

    init(
        hostView: NSView,
        setSceneTargetOverride: @escaping ((() -> Float)?) -> Void,
        setBrightness: @escaping (Float) -> Void,
        getCurrentBrightness: @escaping () -> Float,
        isBrightnessFading: @escaping () -> Bool,
        writeSceneStateToMPV: @escaping (_ backlight: Float, _ inertiaMode: String, _ isCut: Bool, _ ambientLevel: Double?, _ ambientSource: String, _ ambientRegions: (face: Double, room: Double)?, _ ambientLux: Double?) -> Void,
        setAmbientWindowOpen: @escaping (Bool) -> Void
    ) {
        self.hostView = hostView
        self.setSceneTargetOverride = setSceneTargetOverride
        self.setBrightness = setBrightness
        self.getCurrentBrightness = getCurrentBrightness
        self.isBrightnessFading = isBrightnessFading
        self.writeSceneStateToMPV = writeSceneStateToMPV
        self.setAmbientWindowOpen = setAmbientWindowOpen
    }

    func setup() {
        sceneTimer?.invalidate()
        if runtimeEnabled {
            setSceneTargetOverride { [weak self] in self?.smoothedBacklight ?? 1.0 }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: sceneTickInterval, repeats: true) { [weak self] _ in
            self?.tickScene()
        }
        RunLoop.main.add(timer, forMode: .common)
        sceneTimer = timer
    }

    deinit {
        sceneTimer?.invalidate()
        microStepTimer?.invalidate()
        setSceneTargetOverride(nil)
        if #available(macOS 12.0, *) {
            stopAmbientDutyCycle()
        }
    }

    // MARK: - A: scene-adaptive backlight

    private let contentTargetFloor: Float = 0.75

    private var ceilingTravel: Float { 1.0 - contentTargetFloor }

    private let lumaDarkThreshold:   CGFloat = 0.13
    private let lumaBrightThreshold: CGFloat = 0.55

    private func smoothstep(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3.0 - 2.0 * t)
    }

    private var sceneTimer: Timer?
    private let sceneTickInterval: TimeInterval = 0.4

    private let lumaSmoothing: Float = 0.12

    private let backlightInertiaDark: Float = 0.88

    // Match the response inertia in both directions. This is a source policy;
    // visual smoothness and native timing still require field verification.
    private let backlightInertiaBright: Float = 0.88

    private let cutThresholdBase:  CGFloat = 0.14
    private let cutThresholdScale: CGFloat = 2.2

    private func dynamicCutThreshold(_ luma: CGFloat) -> CGFloat {
        cutThresholdBase * (0.5 + min(max(luma, 0), 0.6) * cutThresholdScale)
    }

    private var smoothedLuma: CGFloat?
    private var smoothedBacklight: Float?
    private var cutPending: Bool = false

    private var lastConfirmedCutTime: Date?
    private var sceneTarget: Float?
    private var lastActuatorTime: CFTimeInterval?
    private var lastFreshSampleTime: CFTimeInterval?

    private func resetSceneTracking() {
        microStepTimer?.invalidate()
        microStepTimer = nil
        microStepGeneration += 1
        sceneTarget = nil
        lastActuatorTime = nil
        lastFreshSampleTime = nil
        cachedRawLuma = nil
        smoothedLuma = nil
        let heldBrightness = getCurrentBrightness()
        smoothedBacklight = heldBrightness.isFinite ? heldBrightness : smoothedBacklight
        cutPending = false
        captureInterval = 1
        ticksSinceCapture = 0
        consecutiveCalmTicks = 0
    }

    // Bounded sample/actuator telemetry; existing capture and cut behavior unchanged.
    // cutMicroStepDuration provenance is separate/unverified at HEAD 3a247ad0.
    private struct PhotonBrightTrace {
        let tick: UInt64
        let sample: UInt64
        let monotonicTime: TimeInterval
        let sampleAge: TimeInterval?
        let fresh: Bool
        let captureFailed: Bool
        let cutCandidate: Bool
        let confirmedCut: Bool
        let target: Float
        let hardwareReadback: Float
        let proposedBacklight: Float
        let elapsed: TimeInterval?
        let writeSuppressed: Bool
    }
    // Storage budget only, not an adaptive threshold or actuator parameter.
    private let photonBrightTraceCapacity = 512
    private var photonBrightTrace: [PhotonBrightTrace?] = Array(repeating: nil, count: 512)
    private var photonBrightTraceHead = 0
    private var photonBrightTraceCount = 0
    private var photonBrightTraceDropped: UInt64 = 0
    private var photonBrightTickID: UInt64 = 0
    private var photonBrightSampleID: UInt64 = 0
    private var photonBrightSampleAt: TimeInterval?
    private var photonBrightTickAt: TimeInterval?

    // Snapshot is explicit, outside tickScene. No disk IO or extra hardware reads.
    func photonBrightTraceSnapshot() -> [[String: String]] {
        var rows: [[String: String]] = []
        rows.reserveCapacity(photonBrightTraceCount)
        for offset in 0..<photonBrightTraceCount {
            let index = (photonBrightTraceHead - photonBrightTraceCount + offset + photonBrightTraceCapacity) % photonBrightTraceCapacity
            guard let record = photonBrightTrace[index] else { continue }
            rows.append([
                "tick": String(record.tick), "sample": String(record.sample),
                "monotonicTime": String(record.monotonicTime),
                "sampleAge": record.sampleAge.map { String($0) } ?? "unknown",
                "fresh": String(record.fresh), "captureFailed": String(record.captureFailed),
                "cutCandidate": String(record.cutCandidate), "confirmedCut": String(record.confirmedCut),
                "target": String(record.target), "hardwareReadback": String(record.hardwareReadback),
                "proposedBacklight": String(record.proposedBacklight),
                "elapsed": record.elapsed.map { String($0) } ?? "unknown",
                "writeSuppressed": String(record.writeSuppressed),
                "dropped": String(photonBrightTraceDropped)
            ])
        }
        return rows
    }

    private func tickScene() {
        guard runtimeEnabled else { return }
        // Frozen seek/rebuffer frames are not scene content; hold the target.
        guard !playbackStalled else { return }
        guard !isBrightnessFading(), let hostView, let window = hostView.window else {
            resetSceneTracking()
            return
        }

        let screenRect = window.convertToScreen(hostView.convert(lastTarget, to: nil))

        let sampleNow = CACurrentMediaTime()
        var hasFreshSample = false
        var freshElapsed = sceneTickInterval
        ticksSinceCapture += 1
        let shouldCapture = cachedRawLuma == nil || ticksSinceCapture >= captureInterval
        if shouldCapture {
            ticksSinceCapture = 0
            let previousCached = cachedRawLuma
            if let fresh = ScreenCaptureEngine.shared.currentMPVLuma(inScreenRect: screenRect),
               fresh.isFinite, fresh >= 0, fresh <= 1 {
                hasFreshSample = true
                freshElapsed = lastFreshSampleTime.map { max(0, sampleNow - $0) } ?? sceneTickInterval
                lastFreshSampleTime = sampleNow
                if let previousCached, abs(fresh - previousCached) <= dynamicCutThreshold(previousCached) {
                    consecutiveCalmTicks += 1
                    if consecutiveCalmTicks >= Self.calmTicksToWiden {
                        captureInterval = min(captureInterval + 1, Self.maxCaptureInterval)
                    }
                } else {
                    consecutiveCalmTicks = 0
                    captureInterval = 1
                }
                cachedRawLuma = fresh
            } else {
                // Failed capture is not a second observation of cached content.
                resetSceneTracking()
                return
            }
        }
        guard let rawLuma = cachedRawLuma else { return }

        let diagNow = Date()
        if diagNow.timeIntervalSince(lastDiagLog) > 2.0 {
            lastDiagLog = diagNow
            Diag.log("[ContentAdaptiveDimming] rawLuma=\(rawLuma) screenRect=\(screenRect)")
        }

        let prevLuma = smoothedLuma ?? rawLuma

        let cutCandidate = hasFreshSample && abs(rawLuma - prevLuma) > dynamicCutThreshold(prevLuma)
        let isCut = hasFreshSample && cutCandidate && cutPending
        if hasFreshSample { cutPending = cutCandidate }

        let timeSinceLastCut: TimeInterval? = isCut ? lastConfirmedCutTime.map { Date().timeIntervalSince($0) } : nil
        if isCut { lastConfirmedCutTime = Date() }

        // Preserve the existing response at its reference cadence, not per callback.
        // Cuts are observations; they do not bypass the automatic transition.
        let lumaAlpha = hasFreshSample
            ? 1.0 - pow(1.0 - Double(lumaSmoothing), freshElapsed / sceneTickInterval) : 0.0
        let newLuma = prevLuma + (rawLuma - prevLuma) * CGFloat(lumaAlpha)
        smoothedLuma = newLuma

        let contentSceneT = smoothstep(lumaDarkThreshold, lumaBrightThreshold, newLuma)

        let ambientSceneTBoost: Double = 0.35
        let ambientLevel = AmbientLightProvider.shared.normalizedLevel()
        let ambientRegions = HeadTracker.shared.lastAmbientRegions.map {
            (face: min(max($0.faceLuma, 0), 255) / 255.0,
             room: min(max($0.roomLuma, 0), 255) / 255.0)
        }
        let sceneT: CGFloat
        if let ambientLevel {
            let ambientSupport = CGFloat(ambientLevel * ambientSceneTBoost)
            sceneT = max(0.0, contentSceneT - ambientSupport)
        } else {
            sceneT = contentSceneT
        }
        let target = 1.0 - Float(sceneT) * ceilingTravel

        let applied = getCurrentBrightness()
        guard applied.isFinite else { resetSceneTracking(); return }
        sceneTarget = target
        smoothedBacklight = applied
        let inertiaMode = target < applied ? "bright" : "dark"
        startSceneActuatorIfNeeded()
        // Hardware observation, never a future target or an unexecuted fade.
        writeSceneStateToMPV(applied, inertiaMode, isCut, ambientLevel, AmbientLightProvider.shared.currentSourceLabel, ambientRegions, AmbientLightProvider.shared.lastRawLux)
    }

    private var microStepTimer: Timer?
    private var microStepGeneration = 0

    private var microStepInterval: TimeInterval {
        guard #available(macOS 12.0, *) else { return 1.0 / 60.0 }
        if let interval = hostView?.window?.screen?.maximumRefreshInterval, interval > 0 {
            return interval
        }
        return 1.0 / 60.0
    }

    private func startSceneActuatorIfNeeded() {
        guard microStepTimer == nil else { return }
        microStepGeneration += 1
        let generation = microStepGeneration
        lastActuatorTime = CACurrentMediaTime()
        let timer = Timer.scheduledTimer(withTimeInterval: microStepInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            // An old generation must not retire the replacement timer/state.
            guard self.microStepGeneration == generation else { timer.invalidate(); return }
            guard self.runtimeEnabled, !self.isBrightnessFading(),
                  self.hostView?.window != nil, let target = self.sceneTarget else {
                timer.invalidate()
                self.resetSceneTracking()
                return
            }
            let now = CACurrentMediaTime()
            let elapsed = max(0, now - (self.lastActuatorTime ?? now))
            self.lastActuatorTime = now
            // A stalled callback is not permission to compress a whole ramp into
            // one write. Resume from the observed value on the next normal tick.
            guard elapsed <= self.sceneTickInterval else { return }
            let current = self.getCurrentBrightness()
            guard current.isFinite, target.isFinite else { self.resetSceneTracking(); return }
            // Derive continuous response from existing directional inertia, without
            // cut snaps, callback-count steps or restart-from-stale-target behavior.
            let inertia = target < current ? self.backlightInertiaBright : self.backlightInertiaDark
            let alpha = 1.0 - pow(Double(inertia), elapsed / self.sceneTickInterval)
            let next = current + (target - current) * Float(alpha)
            guard next.isFinite else { self.resetSceneTracking(); return }
            self.setBrightness(next)
            self.smoothedBacklight = self.getCurrentBrightness()
        }
        RunLoop.main.add(timer, forMode: .common)
        microStepTimer = timer
    }

    // MARK: - lastTarget

    private var lastTarget: CGRect = .zero

    private var lastDiagLog: Date = .distantPast

    private static let maxCaptureInterval = 4
    private static let calmTicksToWiden = 3
    private var captureInterval = 1
    private var ticksSinceCapture = 0
    private var consecutiveCalmTicks = 0
    private var cachedRawLuma: CGFloat?

    func handleVideoFrame(_ bounds: CGRect, _ displayRect: CGRect, _ target: CGRect) {
        if lastTarget != target { resetSceneTracking() }
        lastTarget = target
    }
}
