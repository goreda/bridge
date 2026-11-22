import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
// ================================================================
//  PlayerViewStub - player protocol adapter
// ================================================================
final class PlayerViewStub: NSView, PlayerProtocol {
    weak var controller: PPController?
    let spineUI: SpineUI

    init(controller: PPController) {
        self.controller = controller
        self.spineUI  = controller.spineUI
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    var isPlaying: Bool  { controller?.isPlaying ?? false }
    var volume: Float {
        get { controller?.volume ?? PPController.defaultVolume }
        set { controller?.setVolume(newValue) }
    }

    func togglePlay()              { controller?.togglePlay() }
    func seekRelative(_ s: Double) { controller?.seekRelative(s) }
    func seek(to p: Double)        { controller?.seek(to: p) }
    func currentTime() -> Double   { controller?.currentTime ?? 0 }
    func currentProgress() -> Double { controller?.currentProgress() ?? 0 }
    func osdString() -> String     { controller?.osdString() ?? "" }
    func showSubtitleMenu(from v: NSView) { controller?.showSubtitleMenu(from: v) }
    func closeWindow()       { NSApp.terminate(nil) }
    func miniaturizeWindow() {if let app=NSApp.delegate as? AppDelegate,app.activePlayerEngine == .gorav {app.menuWindowMinimize();return};(NSApp.delegate as? AppDelegate)?.requestMPVMinimize() }
    func toggleFullScreen()  { controller?.ipcCommand(#"{"command":["cycle","fullscreen"]}"#) }
    
    func reloadStream()    { controller?.reloadStream() }
    func resumeStream()    { controller?.resumeStream() }
    func rewindowStream()  { controller?.rewindowStream() }
    func stopStream()      { controller?.stopStream() }
}

// BEGIN station-move BrightnessReadCache.swift
import Foundation

