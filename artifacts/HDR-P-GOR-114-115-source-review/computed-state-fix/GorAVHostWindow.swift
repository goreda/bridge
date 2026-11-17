#if canImport(AppKit)
import AppKit

// Owned only by the gorav integration backend. Never attach to or search for mpv.
// Retain for the session lifetime; supply the renderer as contentView and upload
// onTransform to the session's typed fit parameter block (zoom is log2 scale).
@MainActor
final class GorAVHostWindow: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    /// HDR-P-GOR (DR-198A-5C): read-only screen-context signal for the HDR
    /// handoff (screen/backing changes can renegotiate SDR<->EDR). The host
    /// window stays the sole frame writer; the callback only READS metrics.
    var onScreenContextChange: (() -> Void)?
    let window: NSWindow
    private var motion = GorAVHostMotion()
    private let onTransform: (GorAVHostTransform) -> Void
    private var timer: Timer?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var placedInitialFrame = false
    private var videoSize = NSSize(width: 16, height: 9)
    private var aspect = NSSize(width: 16, height: 9)
    private var transition = false
    private var applyingFrame = false
    private var keepAspect = true
    private var restorePiPFrame: NSRect?
    private var restorePiPLevel: NSWindow.Level?
    private var heldKeys = Set<UInt16>()

    init(contentView: NSView, onTransform: @escaping (GorAVHostTransform) -> Void) {
        self.onTransform = onTransform
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = contentView
        window.delegate = self
        window.contentAspectRatio = aspect
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains([.function, .shift]) { self?.releaseKeys() }
            return event
        }
    }

    // Backend teardown must call close, including failed opens and source replacement shutdown.
    func close() {
        motion.releaseHold(immediate: true); heldKeys.removeAll(); stopTimer()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor); self.flagsMonitor = nil }
        window.delegate = nil; window.close()
    }

    // Call after effective display dimensions (pixel aspect and rotation applied) arrive.
    // A new file never repositions a window the user has already placed.
    func open(videoWidth: Double, height: Double) {
        guard videoWidth.isFinite, height.isFinite, videoWidth > 0, height > 0 else { return }
        motion.cancelFrame(); motion.newPlayback(); releaseKeys()
        videoSize = NSSize(width: videoWidth, height: height); aspect = videoSize
        restoreAspect()
        if !placedInitialFrame, !fullscreen, !motion.isPiP, let target = proposedFrame() {
            apply(target); placedInitialFrame = true
        }
        onTransform(motion.transform)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }
    var fullscreen: Bool { window.styleMask.contains(.fullScreen) }
    var pictureInPicture: Bool { motion.isPiP }

    // Explicit fit/rotate/crop actions may resize; delayed metadata must call open, not fit.
    func fit(videoWidth: Double? = nil, height: Double? = nil) {
        if let w = videoWidth, let h = height, w.isFinite, h.isFinite, w > 0, h > 0 {
            videoSize = NSSize(width: w, height: h); aspect = videoSize
        }
        guard !transition, !fullscreen, !motion.isPiP, let target = proposedFrame() else { return }
        motion.animateFrame(from: rect(window.frame), to: rect(target))
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        startTimer()
    }

    func setKeepAspect(_ enabled: Bool) { keepAspect = enabled; restoreAspect() }
    func setFullscreen(_ enabled: Bool) {
        guard !transition, enabled != fullscreen else { return }
        if motion.isPiP { setPiP(false) }
        motion.cancelFrame(); releaseKeys(); restoreAspect()
        transition = true; window.toggleFullScreen(nil)
    }
    func setPiP(_ active: Bool) {
        guard !transition, !fullscreen, active != motion.isPiP else { return }
        motion.cancelFrame(); releaseKeys()
        motion.setPiP(active)
        if active {
            restorePiPFrame = window.frame; restorePiPLevel = window.level
            window.level = .floating
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            if let screen = window.screen ?? NSScreen.main {
                let area = screen.visibleFrame
                let ratio = videoSize.width / videoSize.height
                var w = min(area.width * 0.3, 480.0), h: CGFloat
                h = w / ratio
                if h > area.height * 0.4 { h = area.height * 0.4; w = h * ratio }
                apply(NSRect(x: area.maxX - w - 16, y: area.minY + 16, width: w, height: h))
            }
        } else {
            window.level = restorePiPLevel ?? .normal
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
            if let saved = restorePiPFrame { apply(saved) }
            restorePiPFrame = nil; restorePiPLevel = nil
        }
        restoreAspect(); onTransform(motion.transform)
    }
    func setOnTop(_ active: Bool) {
        if motion.isPiP { restorePiPLevel = active ? .floating : .normal }
        else { window.level = active ? .floating : .normal }
    }
    func move(dx: Double, dy: Double) { motion.nudge(dx: dx, dy: dy); startTimer() }
    func zoom(_ direction: Double) { motion.nudge(dz: direction); startTimer() }
    func resetPicture() { releaseKeys(); motion.reset(); startTimer() }
    // External crop/reset wins over in-flight picture motion.
    func adoptTransform(_ value: GorAVHostTransform) { motion.adopt(value); onTransform(motion.transform) }
    func hold(dx: Double, dy: Double, dz: Double) {
        motion.hold(dx: dx, dy: dy, dz: dz, now: ProcessInfo.processInfo.systemUptime); startTimer()
    }

    private func proposedFrame() -> NSRect? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        let c = window.contentRect(forFrameRect: window.frame)
        let area = rect(screen.visibleFrame)
        guard let result = GorAVHostFit.frame(videoWidth: videoSize.width, videoHeight: videoSize.height,
            usable: area, chromeWidth: window.frame.width - c.width, chromeTop: window.frame.height - c.height) else { return nil }
        return nsrect(result)
    }
    private func rect(_ r: NSRect) -> GorAVHostRect {
        GorAVHostRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }
    private func nsrect(_ r: GorAVHostRect) -> NSRect { NSRect(x: r.x, y: r.y, width: r.width, height: r.height) }
    private func apply(_ frame: NSRect) {
        guard !transition, !fullscreen else { return }
        applyingFrame = true
        window.setFrame(frame, display: true, animate: false)
        applyingFrame = false
    }
    private func restoreAspect() {
        // Clear aspect locking while the frame spring owns the size. Restore the
        // latest requested lock once settled, cancelled or entering fullscreen.
        if keepAspect && !motion.frameMoving { window.contentAspectRatio = aspect }
        else { window.contentResizeIncrements = NSSize(width: 1, height: 1) }
    }
    private func startTimer() {
        guard timer == nil else { return }
        motion.tick(now: ProcessInfo.processInfo.systemUptime)
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            // Timer is installed only on the main run loop.
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = t; RunLoop.main.add(t, forMode: .common)
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func tick() {
        let old = motion.transform
        motion.tick(now: ProcessInfo.processInfo.systemUptime)
        if !transition, !fullscreen, let frame = motion.frame { apply(nsrect(frame)) }
        if motion.transform != old { onTransform(motion.transform) }
        if !motion.frameMoving { motion.cancelFrame(); restoreAspect() }
        if !motion.busy { stopTimer() }
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        let keys: Set<UInt16> = [123, 124, 125, 126, 43, 47]
        guard keys.contains(event.keyCode) else { return false }
        if event.type == .keyUp {
            guard heldKeys.remove(event.keyCode) != nil else { return false }
        } else {
            guard event.modifierFlags.contains([.function, .shift]) else { return false }
            heldKeys.insert(event.keyCode)
        }
        hold(dx: (heldKeys.contains(124) ? 1 : 0) - (heldKeys.contains(123) ? 1 : 0),
             dy: (heldKeys.contains(126) ? 1 : 0) - (heldKeys.contains(125) ? 1 : 0),
             dz: (heldKeys.contains(47) ? 1 : 0) - (heldKeys.contains(43) ? 1 : 0))
        return true
    }
    private func releaseKeys() {
        heldKeys.removeAll(); motion.releaseHold()
        if motion.busy { startTimer() }
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        placedInitialFrame = true; motion.cancelFrame(); restoreAspect()
    }
    func windowWillMove(_ notification: Notification) {
        if !applyingFrame { placedInitialFrame = true; motion.cancelFrame(); restoreAspect() }
    }
    func windowDidResignKey(_ notification: Notification) { releaseKeys() }
    func windowWillClose(_ notification: Notification) {
        onClose?()
        stopTimer(); motion.releaseHold(immediate: true); heldKeys.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor); self.flagsMonitor = nil }
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        transition = true; motion.cancelFrame(); releaseKeys(); restoreAspect()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { transition = false }
    func windowWillExitFullScreen(_ notification: Notification) {
        transition = true; motion.cancelFrame(); releaseKeys()
    }
    func windowDidExitFullScreen(_ notification: Notification) { transition = false; restoreAspect() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { transition = false; restoreAspect() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { transition = false; restoreAspect() }
    func windowDidChangeScreen(_ notification: Notification) { onScreenContextChange?() }
    func windowDidChangeBackingProperties(_ notification: Notification) { onScreenContextChange?() }
}
#endif
