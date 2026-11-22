import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
/// The stereo copy uses the original live controls and their actions, with an input surface in the
/// right eye. Retain the hit target across a drag so seek/volume tracking keeps its native lifecycle.
final class VRStereoControlInput: NSView {
    weak var host: NSView?
    var sources: [NSView] = []
    var fixedEyeBand:CGRect?
    var eyeShift: CGFloat = 0; var eyeShiftY:CGFloat=0; var tiltTranslation=NSPoint.zero
    var eyeClip: CGRect = .zero
    var roll: Double = 0; var tiltCenter: NSPoint = .zero; var tiltScale: CGFloat = 1; var stereo = false
    // Layer transforms do not alter AppKit hit testing. Route BOTH eyes through the inverse.
    private func originalPoint(_ point: NSPoint) -> NSPoint {
        let dx=point.x-tiltCenter.x-tiltTranslation.x-eyeShift*0.5
        let dy=point.y-tiltCenter.y-tiltTranslation.y-eyeShiftY*0.5
        let right=inputEyeOverride ?? (stereo && (fixedEyeBand.map {!$0.contains(point)} ?? (dx*eyeShift+dy*eyeShiftY>0))); var p=point
        if right {p.x -= eyeShift;p.y -= eyeShiftY}
        p.x -= tiltTranslation.x;p.y -= tiltTranslation.y
        let c=CGFloat(cos(-roll)),s=CGFloat(sin(-roll)),inverseScale=1/max(tiltScale,0.000001)
        let x=(p.x-tiltCenter.x)*inverseScale,y=(p.y-tiltCenter.y)*inverseScale
        return NSPoint(x:tiltCenter.x+c*x-s*y,y:tiltCenter.y+s*x+c*y)
    }
    private var inputEyeOverride:Bool?,routedRightEye:Bool?,pressedRightEye:Bool?
    var active = false
    var onInteraction: (() -> Void)?
    private weak var pressed: NSView?
    // AppKit's default responder forwarding can return an unhandled event to
    // this stereo input via a browser scroll view. Never forward it twice.
    private var forwardingEvent = false
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    private func target(at pointInHost: NSPoint) -> NSView? {
        guard active, let host else { return nil }
        let dx=pointInHost.x-tiltCenter.x-tiltTranslation.x-eyeShift*0.5
        let dy=pointInHost.y-tiltCenter.y-tiltTranslation.y-eyeShiftY*0.5
        let preferred=fixedEyeBand.map {!$0.contains(pointInHost)} ?? (dx*eyeShift+dy*eyeShiftY>0)
        // Safety placement can move a block across the geometric eye bisector.
        // Resolve against actual live controls in both inverse maps, not screen-x.
        defer {inputEyeOverride=nil}
        for right in (stereo ? (fixedEyeBand == nil ? [preferred,!preferred]:[preferred]):[false]) {
            inputEyeOverride=right
            let left=originalPoint(pointInHost)
            for source in sources.reversed() {
                var ancestor: NSView? = source
                var visible = true
                while let v = ancestor, v !== host {
                    visible = visible && !v.isHidden && v.alphaValue > 0.01
                    ancestor = v.superview
                }
                guard visible, let parent = source.superview,
                      source.convert(source.bounds, to: host).contains(left) else { continue }
                if let hit=source.hitTest(parent.convert(left,from:host)) {routedRightEye=right;return hit}
            }
        }
        routedRightEye=nil
        return nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let host else { return nil }
        let pt = host.convert(point, from: superview)
        return target(at: pt) != nil ? self : nil
    }
    private func translated(_ event: NSEvent) -> NSEvent? {
        guard let host else { return nil }
        var p = host.convert(event.locationInWindow, from: nil)
        inputEyeOverride=pressedRightEye ?? routedRightEye
        defer {inputEyeOverride=nil}
        p = originalPoint(p)
        p = host.convert(p, to: nil)
        return NSEvent.mouseEvent(with: event.type, location: p, modifierFlags: event.modifierFlags,
            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
            eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure)
    }
    override func mouseDown(with event: NSEvent) {
        guard !forwardingEvent else {return}
        forwardingEvent = true
        defer {forwardingEvent = false}
        guard let host, let control=target(at:host.convert(event.locationInWindow,from:nil)) else{return}
        pressedRightEye=routedRightEye
        guard let e=translated(event) else {pressedRightEye=nil;return}
        onInteraction?();pressed=control
        pressed?.mouseDown(with:e)
    }
    override func mouseDragged(with event: NSEvent) {
        guard !forwardingEvent else {return}
        forwardingEvent = true
        defer {forwardingEvent = false}
        onInteraction?()
        guard let e = translated(event) else { return }; pressed?.mouseDragged(with: e)
    }
    override func mouseUp(with event: NSEvent) {
        guard !forwardingEvent else {return}
        forwardingEvent = true
        defer {forwardingEvent = false}
        defer {pressed=nil;pressedRightEye=nil}
        guard let e = translated(event) else { return }; pressed?.mouseUp(with: e)
    }
    override func scrollWheel(with event: NSEvent) {
        guard !forwardingEvent else {return}
        forwardingEvent = true
        defer {forwardingEvent = false}
        guard let host, let win = window,
              let control = target(at: host.convert(event.locationInWindow, from: nil)),
              let cg = event.cgEvent?.copy() else { return }
        // Copy the real wheel event to preserve phase, precise deltas and momentum, changing location only.
        inputEyeOverride=routedRightEye;defer {inputEyeOverride=nil}
        let local = originalPoint(host.convert(event.locationInWindow, from: nil))
        let screen = win.convertPoint(toScreen: host.convert(local, to: nil))
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        cg.location = CGPoint(x: screen.x, y: screenTop - screen.y)
        guard let mapped = NSEvent(cgEvent: cg) else { return }
        onInteraction?()
        control.scrollWheel(with: mapped)
    }
}
