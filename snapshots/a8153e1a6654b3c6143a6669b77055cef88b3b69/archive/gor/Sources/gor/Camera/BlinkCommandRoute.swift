import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
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

