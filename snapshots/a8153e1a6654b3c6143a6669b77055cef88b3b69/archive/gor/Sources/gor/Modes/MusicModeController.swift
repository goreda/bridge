import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
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
    private let playback: PlayerMusicModeOperations
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
        playback: PlayerMusicModeOperations,
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
        self.playback = playback
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
            playback.exit(scriptedFit:PPController.gorFitScriptActive)
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
            playback.enter(size:musicSize)
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
