import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
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

