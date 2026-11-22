import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
/// Which camera consumers should run for the current feature state. Pure so the harness
/// pins the composition; VR180Controller.updateCaptureConsumers applies the edges.
enum CaptureConsumerRules {
    /// Both consumers use loaded-video authority; paused video must still respond to head motion.
    static func headShouldRun(headTrackingEnabled: Bool, playbackActive: Bool) -> Bool {
        headTrackingEnabled && playbackActive
    }
    /// Blink leg: frames whenever blink is on with a file loaded, VR or normal playback alike
    /// (owner 2026-11-21); vrEnabled is retained for call-site stability only. Pause must NOT stop it.
    static func blinkShouldRun(blinkOn: Bool, vrEnabled: Bool, loadedVideoActive: Bool, cameraAllowed: Bool) -> Bool {
        blinkOn && loadedVideoActive && cameraAllowed
    }
}

